import XCTest
import WebKit
import UIKit
@testable import VisionStream

@MainActor final class AutomaticPlaybackNativeTests:XCTestCase {
    private func origin() throws -> URL {
        let url=try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        guard url.scheme=="https",["127.0.0.1","localhost"].contains(url.host) else { throw URLError(.badURL) };return url
    }
    private func wait(_ condition:()->Bool) async throws {
        let end=Date().addingTimeInterval(20)
        while !condition(),Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertTrue(condition())
    }
    private func preferences() throws -> (BrowserPreferences,UserDefaults,String) {
        let name="AutomaticPlayback-"+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:name))
        return (BrowserPreferences(defaults:defaults),defaults,name)
    }
    private func attach(_ browser:BrowserModel) throws {
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window=try XCTUnwrap(scene.windows.first { !$0.isHidden })
        browser.webView.frame=window.bounds;window.addSubview(browser.webView)
    }
    func testAutomaticOpeningPreferenceDefaultsOnAndPersistsUserChoice() throws {
        let (preferences,defaults,name)=try preferences();defer { defaults.removePersistentDomain(forName:name) }
        XCTAssertTrue(preferences.openVideosInVR)
        preferences.openVideosInVR=false
        XCTAssertFalse(BrowserPreferences(defaults:defaults).openVideosInVR)
        preferences.openVideosInVR=true
        XCTAssertTrue(BrowserPreferences(defaults:defaults).openVideosInVR)
    }
    func testWebKitAutoplayAndSyntheticClicksDoNotCreatePlayIntents() async throws {
        let (preferences,defaults,name)=try preferences(),browser=BrowserModel(preferences:preferences),origin=try origin()
        try attach(browser)
        defer { browser.webView.stopLoading();browser.webView.removeFromSuperview();defaults.removePersistentDomain(forName:name) }
        var requests=0;browser.onUserPlayback={ _ in requests+=1 }
        browser.open(origin.appendingPathComponent("automation-mp4"))
        try await wait { browser.candidates.contains { $0.width>0 } }
        // Cold simulator WebKit may defer autoplay. Explicit programmatic play
        // still must not be mistaken for a trusted DOM play gesture.
        _ = try await browser.webView.callAsyncJavaScript("await document.querySelector('video').play();return true;",arguments:[:],in:nil,contentWorld:.defaultClient)
        try await wait { browser.candidates.contains { $0.webMedia?.paused==false } }
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('video').pause();document.querySelector('video').click();document.querySelector('video').play();true")
        try await Task.sleep(for:.milliseconds(400));browser.scan()
        try await wait { browser.candidates.contains { $0.webMedia?.paused==false } }
        XCTAssertTrue(browser.candidates.allSatisfy { $0.playIntent==nil });XCTAssertEqual(requests,0)
        let isolated=try await browser.webView.evaluateJavaScript("typeof globalThis.visionStreamDetector") as? String
        XCTAssertEqual(isolated,"undefined","Website code cannot access the isolated detector")
    }
    func testIsolatedBridgeDispatchesOnceSuppressesDisabledAndClearsOnNavigation() async throws {
        let (preferences,defaults,name)=try preferences(),browser=BrowserModel(preferences:preferences),origin=try origin()
        try attach(browser)
        defer { browser.webView.stopLoading();browser.webView.removeFromSuperview();defaults.removePersistentDomain(forName:name) }
        var requests=0;browser.onUserPlayback={ _ in requests+=1 }
        browser.open(origin.appendingPathComponent("automation-mp4"))
        try await wait { browser.candidates.contains { $0.width>0 } }
        // Cold simulator WebKit may defer autoplay. Explicit programmatic play
        // still must not be mistaken for a trusted DOM play gesture.
        _ = try await browser.webView.callAsyncJavaScript("await document.querySelector('video').play();return true;",arguments:[:],in:nil,contentWorld:.defaultClient)
        try await wait { browser.candidates.contains { $0.webMedia?.paused==false } }
        let token=UUID().uuidString
        try await inject(browser,id:token)
        try await wait { requests==1 }
        try await inject(browser,id:token);try await Task.sleep(for:.milliseconds(250))
        XCTAssertEqual(requests,1)
        preferences.openVideosInVR=false
        let ignored=UUID().uuidString;try await inject(browser,id:ignored)
        try await Task.sleep(for:.milliseconds(250));XCTAssertEqual(requests,1)
        preferences.openVideosInVR=true;try await inject(browser,id:ignored)
        try await Task.sleep(for:.milliseconds(250));XCTAssertEqual(requests,1)
        try await inject(browser,id:UUID().uuidString);try await wait { requests==2 }
        browser.open(origin.appendingPathComponent("empty-test"))
        XCTAssertTrue(browser.candidates.isEmpty)
        try await wait { browser.pageHTTPStatus==200 && !browser.isLoading }
        XCTAssertTrue(AutomaticPlayback.actionable(in:browser.candidates).isEmpty)
    }
    /// Test the real isolated bridge/native handoff boundary, not simulated human
    /// input. The JS unit tests cover trusted-gesture recognition separately.
    private func inject(_ browser:BrowserModel,id:String) async throws {
        _ = try await browser.webView.callAsyncJavaScript("""
            const candidates=globalThis.visionStreamDetector.scan();
            const candidate=candidates.find(c=>c.width>0 && !c.webMedia.paused);
            if (!candidate) throw new Error('fixture not ready');
            candidate.playIntent={id:token,age:0,visible:true};
            globalThis.webkit.messageHandlers.visionStream.postMessage({frameID:candidate.id.split(':')[0],candidates:[candidate]});
            return true;
            """,arguments:["token":id],in:nil,contentWorld:.defaultClient)
    }
}
