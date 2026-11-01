import XCTest
import UIKit
import WebKit
@testable import VisionStream

@MainActor final class BrowserTabsNativeTests: XCTestCase {
    private func preferences() throws -> (BrowserPreferences, UserDefaults, String) {
        let name = "BrowserUsability-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (BrowserPreferences(defaults: defaults), defaults, name)
    }
    private func origin() throws -> URL {
        let url = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        XCTAssertEqual(url.host, "127.0.0.1"); return url
    }
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(25)
        while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition())
    }
    func testTabIdentityCapacitySelectionAndLastClose() throws {
        let (preferences, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        let tabs = BrowserTabs(preferences: preferences), first = tabs.active
        defer { tabs.pages.forEach { $0.closeTab() } }
        var activeNavigations = 0
        tabs.onNavigation = { activeNavigations += 1 }
        let second = try XCTUnwrap(tabs.add())
        XCTAssertFalse(first.isActiveTab); XCTAssertTrue(second.isActiveTab)
        XCTAssertFalse(first.webView === second.webView)
        let count = activeNavigations
        first.onNavigation?()
        XCTAssertEqual(activeNavigations, count, "Background navigation cannot cancel active preparation")
        tabs.select(first.id); XCTAssertTrue(tabs.active === first)
        tabs.close(second.id); XCTAssertTrue(tabs.active === first)
        for _ in 1..<BrowserTabs.maximumCount { XCTAssertNotNil(tabs.add()) }
        XCTAssertNil(tabs.add()); XCTAssertEqual(tabs.pages.count, BrowserTabs.maximumCount)
        tabs.selectAdjacent(1); XCTAssertTrue(tabs.active === first)
        for page in tabs.pages where page.id != first.id { tabs.close(page.id) }
        tabs.close(first.id)
        XCTAssertEqual(tabs.pages.count, 1); XCTAssertFalse(tabs.active === first)
        XCTAssertFalse(tabs.active.canGoBack); XCTAssertTrue(tabs.active.isStartPage)
        XCTAssertNil(preferences.restoredURL)
    }
    func testFavouritesPreserveExistingBookmarksAndSurviveRestart() throws {
        let (preferences, defaults, name) = try preferences()
        defer { defaults.removePersistentDomain(forName: name) }
        preferences.saveBookmark(name: "Original", address: "https://example.com/watch?id=1")
        XCTAssertTrue(preferences.favourites.isEmpty)
        let original = try XCTUnwrap(preferences.bookmarks.first)
        preferences.setFavourite(original, enabled: true)
        preferences.saveBookmark(name: "Renamed", address: original.address)
        XCTAssertEqual(preferences.favourites.first?.id, original.id)
        XCTAssertEqual(preferences.favourites.first?.name, "Renamed")
        let restored = BrowserPreferences(defaults: defaults)
        XCTAssertEqual(restored.favourites.count, 1)
        restored.setFavourite(original, enabled: false)
        XCTAssertEqual(restored.bookmarks.count, 1); XCTAssertTrue(restored.favourites.isEmpty)
        restored.saveFavourite(name: "Second", address: "https://example.org/")
        let second = try XCTUnwrap(restored.favourites.first)
        restored.removeBookmark(second)
        XCTAssertFalse(BrowserPreferences(defaults: defaults).favouriteIDs.contains(second.id))
    }
    func testTabsKeepIndependentBackStacksAndNewTabsDoNotRestoreOldWebsite() async throws {
        let (preferences, defaults, name) = try preferences(), base = try origin()
        defer { defaults.removePersistentDomain(forName: name) }
        preferences.restoration = .page
        let tabs = BrowserTabs(preferences: preferences), first = tabs.active
        defer { tabs.pages.forEach { $0.closeTab() } }
        first.open(base.appendingPathComponent("empty-test"))
        try await wait { !first.isLoading && first.pageHTTPStatus == 200 }
        first.open(base.appendingPathComponent("quality.html"))
        try await wait { !first.isLoading && first.canGoBack }
        let second = try XCTUnwrap(tabs.add()); second.startIfNeeded()
        try await wait { !second.isLoading }
        XCTAssertTrue(second.isStartPage); XCTAssertTrue(second.address.isEmpty)
        XCTAssertFalse(second.canGoBack)
        tabs.select(first.id)
        XCTAssertEqual(first.webView.url?.path, "/quality.html")
        let history = try XCTUnwrap(first.backPages.first { $0.url.path == "/empty-test" })
        first.go(to: history)
        try await wait { !first.isLoading && first.webView.url?.path == "/empty-test" }
        XCTAssertTrue(first.canGoForward)
    }
    func testBackgroundTabsSuspendMediaAndResumePermissionWhenSelected() async throws {
        let (preferences, defaults, name) = try preferences(), base = try origin()
        defer { defaults.removePersistentDomain(forName: name) }
        let tabs = BrowserTabs(preferences: preferences), first = tabs.active
        defer { tabs.pages.forEach { $0.closeTab(); $0.webView.removeFromSuperview() } }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { !$0.isHidden })
        first.webView.frame = window.bounds; window.addSubview(first.webView)
        first.open(base.appendingPathComponent("automation-mp4"))
        try await wait { first.candidates.contains { $0.width > 0 } }
        _ = try await first.webView.callAsyncJavaScript("await document.querySelector('video').play();return true", arguments: [:], in: nil, contentWorld: .defaultClient)
        _ = tabs.add()
        try await Task.sleep(for: .milliseconds(400))
        let paused = try await first.webView.evaluateJavaScript("document.querySelector('video').paused") as? Bool
        XCTAssertEqual(paused, true)
        let blocked = try await first.webView.callAsyncJavaScript("return await Promise.race([document.querySelector('video').play().then(()=>false,()=>true),new Promise(resolve=>setTimeout(()=>resolve(true),500))]);", arguments: [:], in: nil, contentWorld: .defaultClient) as? Bool
        XCTAssertEqual(blocked, true)
        tabs.select(first.id)
        _ = try await first.webView.callAsyncJavaScript("await document.querySelector('video').play();return true", arguments: [:], in: nil, contentWorld: .defaultClient)
        let resumed = try await first.webView.evaluateJavaScript("!document.querySelector('video').paused") as? Bool
        XCTAssertEqual(resumed, true)
    }
    func testClearWebsiteDataResetsEveryTabWithoutDeletingFavourites() async throws {
        let (preferences, defaults, name) = try preferences(), base = try origin()
        defer { defaults.removePersistentDomain(forName: name) }
        let tabs = BrowserTabs(preferences: preferences)
        defer { tabs.pages.forEach { $0.closeTab() } }
        tabs.active.open(base.appendingPathComponent("empty-test"))
        _ = tabs.add(url: base.appendingPathComponent("quality.html"))
        preferences.saveFavourite(name: "Saved", address: "https://example.com/")
        await tabs.clearWebsiteData()
        XCTAssertTrue(tabs.pages.allSatisfy(\.isStartPage))
        XCTAssertEqual(preferences.favourites.count, 1)
        XCTAssertNil(preferences.restoredURL)
        XCTAssertFalse(tabs.isClearingWebsiteData)
    }
    func testInactiveAndOldPlayIntentsCannotLaunchAfterTabSwitch() async throws {
        let (preferences, defaults, name) = try preferences(), base = try origin()
        defer { defaults.removePersistentDomain(forName: name) }
        let tabs = BrowserTabs(preferences: preferences), first = tabs.active
        defer { tabs.pages.forEach { $0.closeTab(); $0.webView.removeFromSuperview() } }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { !$0.isHidden })
        first.webView.frame = window.bounds; window.addSubview(first.webView)
        first.open(base.appendingPathComponent("automation-mp4"))
        try await wait { first.candidates.contains { $0.width > 0 } }
        var requests = 0
        tabs.onUserPlayback = { _ in requests += 1 }
        // Attest at the isolated native bridge, not through a simulated DOM gesture.
        func inject(age: Double) async throws {
            _ = try await first.webView.callAsyncJavaScript("""
                const c=globalThis.visionStreamDetector.scan().find(c=>c.width>0);
                c.playIntent={id:token,age:age,visible:true};c.webMedia.paused=false;c.webMedia.readyState=4;
                globalThis.webkit.messageHandlers.visionStream.postMessage({frameID:c.id.split(':')[0],candidates:[c]});
                return true;
                """, arguments: ["token": UUID().uuidString, "age": age], in: nil, contentWorld: .defaultClient)
        }
        try await inject(age: 0); try await wait { requests == 1 }
        _ = tabs.add()
        try await inject(age: 0)
        try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(requests, 1)
        tabs.select(first.id)
        try await inject(age: 5)
        try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(requests, 1)
        try await inject(age: 0); try await wait { requests == 2 }
    }
}
