import AVFoundation
import WebKit
import XCTest
@testable import VisionStream

@MainActor final class VRLibraryNativeTests: XCTestCase {
    func testCookieLibraryToNativeMP4AndHLSForAllLayouts() async throws {
        let origin = try origin()
        let saved = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(saved, forKey: "lastPage") }
        let browser = BrowserModel()
        defer { browser.webView.stopLoading() }
        browser.open(try url(origin + "/auth-test"))
        try await wait { browser.webView.url?.path == "/auth-test" && !browser.webView.isLoading }
        let library = VRLibraryModel()
        library.connect(try url(origin + "/auth/library"), browser: browser)
        try await loaded(library)
        XCTAssertNil(library.errorMessage)
        let root = try XCTUnwrap(library.document)
        XCTAssertFalse(root.limitedAccess)
        XCTAssertEqual(root.entries.count, 6)
        for entry in root.entries {
            library.connect(entry.url, browser: browser)
            try await loaded(library)
            XCTAssertNil(library.errorMessage)
            let document = try XCTUnwrap(library.document)
            XCTAssertEqual(document.streams.count, 2)
            for stream in document.streams {
                XCTAssertNil(stream.unavailableReason)
                let playback = PlaybackModel()
                defer { playback.stop() }
                playback.projection = try XCTUnwrap(stream.projection)
                playback.layout = try XCTUnwrap(stream.layout)
                XCTAssertEqual(playback.projection, entry.url.lastPathComponent.hasPrefix("vr180") ? .vr180 : .vr360)
                XCTAssertEqual(playback.layout.rawValue, entry.url.lastPathComponent.hasSuffix("mono") ? "mono" : entry.url.lastPathComponent.hasSuffix("sbs") ? "sideBySide" : "topBottom")
                let cookies = await browser.cookies(for: try url(stream.candidate.source))
                let ready = await playback.prepare(stream.candidate, cookies: cookies)
                XCTAssertTrue(ready, playback.errorMessage ?? "Library source was not playable")
                guard ready else { continue }
                playback.play()
                var frame: CVPixelBuffer?
                try await wait {
                    frame = playback.videoOutput?.copyPixelBuffer(forItemTime: playback.player.currentTime(), itemTimeForDisplay: nil)
                    return frame != nil
                }
                XCTAssertNotNil(frame)
                print("HereSphere cookie library decoded \(entry.url.lastPathComponent) \(stream.label)")
            }
            XCTAssertTrue(library.canGoBack)
            library.back()
            XCTAssertEqual(library.document?.entries.count, 6)
            XCTAssertFalse(library.canGoBack)
        }
    }

    func testLibraryFailuresAndRecovery() async throws {
        let origin = try origin()
        let browser = BrowserModel()
        let library = VRLibraryModel()
        library.connect(address: "https://[invalid", browser: browser)
        XCTAssertFalse(library.isLoading)
        XCTAssertEqual(library.errorMessage, VRLibraryError.invalidURL.localizedDescription)
        for path in ["/library/forbidden", "/library/post-only", "/library/denied", "/library/invalid", "/library/huge", "/library/oversize-chunked", "/empty-test", "/library/redirect"] {
            library.connect(try url(origin + path), browser: browser)
            try await loaded(library)
            XCTAssertNotNil(library.errorMessage, path)
            XCTAssertNil(library.document, path)
            if path.contains("huge") || path.contains("oversize") { XCTAssertEqual(library.errorMessage, VRLibraryError.tooLarge.localizedDescription) }
            if path.contains("redirect") { XCTAssertEqual(library.errorMessage, VRLibraryError.redirected.localizedDescription) }
        }
        library.connect(try url(origin + "/library"), browser: browser)
        try await loaded(library)
        XCTAssertNil(library.errorMessage)
        XCTAssertEqual(library.document?.entries.count, 6)
        XCTAssertTrue(library.document?.limitedAccess == true)
        library.usesPOST = true
        library.connect(try url(origin + "/library/post-only"), browser: browser)
        try await loaded(library)
        XCTAssertNil(library.errorMessage)
        XCTAssertEqual(library.document?.streams.count, 2)
    }

    func testLibraryCookiesStayWithinHostAndPathAndResponseCookiesAreNotSaved() async throws {
        let origin = try origin()
        let saved = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(saved, forKey: "lastPage") }
        let browser = BrowserModel()
        defer { browser.webView.stopLoading() }
        browser.open(try url(origin + "/auth-test"))
        try await wait { browser.webView.url?.path == "/auth-test" && !browser.webView.isLoading }
        let library = VRLibraryModel()
        for endpoint in [origin + "/library/set-cookie", origin + "/library/no-cookie", origin.replacingOccurrences(of: "127.0.0.1", with: "localhost") + "/library/no-cookie"] {
            library.connect(try url(endpoint), browser: browser)
            try await loaded(library)
            XCTAssertNil(library.errorMessage)
            XCTAssertEqual(library.document?.streams.count, 2)
        }
        let all = await browser.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertFalse(all.contains { $0.name == "visionstream_library_ignored" })
    }

    func testLibraryCancellationReplacementAndBrowserNavigationClearStaleResults() async throws {
        let origin = try origin()
        let saved = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(saved, forKey: "lastPage") }
        let app = AppModel()
        defer { app.browser.webView.stopLoading(); app.library.clear() }
        app.library.connect(try url(origin + "/delayed/library"), browser: app.browser)
        XCTAssertTrue(app.library.isLoading)
        app.library.cancel()
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertFalse(app.library.isLoading)
        XCTAssertNil(app.library.document)
        XCTAssertNil(app.library.errorMessage)
        app.library.connect(try url(origin + "/delayed/library"), browser: app.browser)
        app.library.connect(try url(origin + "/library/vr360-tb"), browser: app.browser)
        try await loaded(app.library)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(app.library.document?.streams.first?.projection, .vr360)
        XCTAssertEqual(app.library.document?.streams.first?.layout, .topBottom)
        app.browser.open(try url(origin + "/empty-test"))
        try await wait { app.browser.webView.url?.path == "/empty-test" && !app.browser.webView.isLoading }
        XCTAssertNil(app.library.document)
        XCTAssertNil(app.library.endpoint)
        XCTAssertFalse(app.library.canGoBack)
    }

    private func loaded(_ library: VRLibraryModel) async throws {
        try await wait(seconds: 30) { !library.isLoading }
    }
    private func wait(seconds: Double = 15, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "Library condition timed out")
    }
    private func url(_ value: String) throws -> URL { try XCTUnwrap(URL(string: value)) }
    private func origin() throws -> String {
        guard let value = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"] else {
            throw XCTSkip("Run with Scripts/run_visionos_tests.py for HTTPS library fixtures")
        }
        return value
    }
}
