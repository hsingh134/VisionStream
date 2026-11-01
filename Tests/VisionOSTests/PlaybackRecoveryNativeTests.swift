import RealityKit
import UIKit
import XCTest
@testable import VisionStream

@MainActor final class PlaybackRecoveryNativeTests: XCTestCase {
    func testFirstConnectionFailureRecoversWithoutRefreshingPage() async throws {
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        let url = origin.appendingPathComponent("first-connection-drop/" + UUID().uuidString + ".mp4")
        let playback = PlaybackModel(preparationTimeout: .seconds(12))
        defer { playback.stop() }
        let ready = await playback.prepare(MediaCandidate(id: "one-drop", source: url.absoluteString), cookies: [])
        XCTAssertTrue(ready)
        XCTAssertLessThanOrEqual(playback.preparationRetryCount, 1)
    }
    func testHandoffUsesLatestSourceFromSameDetectedElement() async throws {
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        let browser = BrowserModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { !$0.isHidden })
        browser.webView.frame = window.bounds; window.addSubview(browser.webView)
        defer { browser.webView.removeFromSuperview(); browser.closeTab() }
        browser.open(origin.appendingPathComponent("automation-mp4"))
        // A new simulator's first WebKit process can take over 15 seconds.
        // Keep navigation bounded and exercise an attached view, as production does.
        var end = Date().addingTimeInterval(25)
        while browser.candidates.isEmpty, Date() < end { try await Task.sleep(for: .milliseconds(50)) }
        let old = try XCTUnwrap(browser.candidates.first)
        let replacement = origin.appendingPathComponent("vr360-mono.mp4").absoluteString
        _ = try await browser.webView.callAsyncJavaScript("document.querySelector('video').src=source;return true", arguments: ["source": replacement], in: nil, contentWorld: .defaultClient)
        end = Date().addingTimeInterval(10)
        while !browser.candidates.contains(where: { $0.source == replacement }), Date() < end {
            browser.scan(); try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(browser.freshCandidate(for: old).source, replacement)
        var unrelated = old; unrelated.videoID = "unrelated"
        XCTAssertEqual(browser.freshCandidate(for: unrelated).source, old.source)
    }
    func testRetainedMasterPreservesCookieIssuedByQualityInspection() async throws {
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        let url = origin.appendingPathComponent("master-cookie/" + UUID().uuidString + "/master.m3u8")
        let playback = PlaybackModel(preparationTimeout: .seconds(8))
        defer { playback.stop() }
        let ready = await playback.prepare(MediaCandidate(id: "master-cookie", source: url.absoluteString), cookies: [])
        XCTAssertTrue(ready, "A legitimate cookie from quality inspection must reach native HLS requests")
        guard ready else { return }
        XCTAssertTrue(playback.qualityStatus.contains("Adaptive"))
        XCTAssertEqual(playback.manifestInspection?.httpStatus, 200)
        XCTAssertEqual(playback.manifestInspection?.outcome, .parsed)
        playback.play()
        let end = Date().addingTimeInterval(8)
        while playback.player.currentTime().seconds < 0.2, Date() < end { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertGreaterThan(playback.player.currentTime().seconds, 0.1)
        playback.changeQuality(.adaptive)
        let switchEnd = Date().addingTimeInterval(10)
        while !playback.isReady, Date() < switchEnd { try await Task.sleep(for: .milliseconds(50)) }
        // changeQuality starts on the next actor turn.
        try await Task.sleep(for: .milliseconds(500))
        while !playback.isReady, Date() < switchEnd { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(playback.isReady, "Quality changes keep the legitimate issued cookie in memory")
    }
    func testRendererTeardownReleasesCompletedFramesAndDoesNotRetainScene() async throws {
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        for _ in 0..<6 {
            let playback = PlaybackModel()
            playback.player.isMuted = true
            let ready = await playback.prepare(MediaCandidate(id: "teardown", source: origin.appendingPathComponent("vr180-sbs.mp4").absoluteString), cookies: [])
            XCTAssertTrue(ready)
            var renderer: ImmersiveRenderer? = try ImmersiveRenderer(playback: playback, controls: Entity())
            weak var released = renderer
            try await renderer?.start()
            let end = Date().addingTimeInterval(8)
            while playback.decodedWidth == 0, Date() < end { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertGreaterThan(playback.decodedWidth, 0)
            playback.layout = .topBottom
            try await Task.sleep(for: .milliseconds(15))
            renderer?.stop(); playback.stop(); renderer = nil
            let releaseEnd = Date().addingTimeInterval(5)
            while released != nil, Date() < releaseEnd { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(released, "Completed GPU commands must release the renderer after scene dismissal")
        }
    }
    func testFailedNativeAttemptDoesNotStopWebpageAndDismissKeepsEvidence() async throws {
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        let browser = BrowserModel()
        let playback = PlaybackModel(preparationTimeout: .seconds(8))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { !$0.isHidden })
        browser.webView.frame = window.bounds; window.addSubview(browser.webView)
        defer { browser.webView.removeFromSuperview(); browser.closeTab(); playback.stop() }
        browser.open(origin.appendingPathComponent("web-playback-test"))
        var end = Date().addingTimeInterval(25)
        while browser.isLoading || browser.candidates.isEmpty, Date() < end { try await Task.sleep(for: .milliseconds(50)) }
        _ = try XCTUnwrap(browser.candidates.first,
            "Fixture video did not mount: page status \(String(describing: browser.pageHTTPStatus)), loading \(browser.isLoading), codes \(browser.pageFailureCodes)")
        let started = try await browser.webView.callAsyncJavaScript("await document.querySelector('video').play();return true", in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(started, true)
        let before = try await browser.webView.evaluateJavaScript("document.querySelector('video').currentTime") as? Double ?? 0
        let ready = await playback.prepare(MediaCandidate(id: "bad-native", source: origin.appendingPathComponent("download-invalid-mp4.mp4").absoluteString), cookies: [])
        XCTAssertFalse(ready); XCTAssertNotNil(playback.errorMessage)
        let stage = playback.diagnosticStage, codes = playback.failureCodes, reason = playback.failureReason
        XCTAssertTrue(stage.hasPrefix("failed-at-"))
        let stillPlaying = try await browser.webView.evaluateJavaScript("!document.querySelector('video').paused && !document.querySelector('video').error") as? Bool
        XCTAssertEqual(stillPlaying, true)
        playback.dismissError()
        XCTAssertNil(playback.errorMessage)
        XCTAssertEqual(playback.diagnosticStage, stage); XCTAssertEqual(playback.failureCodes, codes)
        XCTAssertEqual(playback.failureReason, reason); XCTAssertEqual(playback.diagnosticCandidate?.id, "bad-native")
        end = Date().addingTimeInterval(5)
        var advanced = false
        while !advanced, Date() < end {
            let now = try await browser.webView.evaluateJavaScript("document.querySelector('video').currentTime") as? Double ?? 0
            advanced = now > before + 0.1
            if !advanced { try await Task.sleep(for: .milliseconds(50)) }
        }
        XCTAssertTrue(advanced, "The webpage can continue without refreshing after native playback failed")
    }
    func testPlaylistInspectionReportsExactResponseWithHistoryOffAndClearsOnNextAttempt() async throws {
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history = SessionDiagnostics(root: root)
        history.setEnabled(false)
        let app = AppModel(history: history)
        defer { app.playback.stop(); app.tabs.pages.forEach { $0.closeTab() }; try? FileManager.default.removeItem(at: root) }
        for (path, status, outcome) in [("library/forbidden", 403, "requestFailed"),
            ("missing-inspection.m3u8", 404, "requestFailed"),
            ("resource-trace/redirect.m3u8", 302, "requestFailed"),
            ("download-invalid-mp4.mp4", 200, "invalidManifest")] {
            let url = origin.appendingPathComponent(path).appending(queryItems: [.init(name: "private", value: "not-in-report")])
            _ = await app.playback.prepare(.init(id: "inspection", source: url.absoluteString, mimeType: "application/vnd.apple.mpegurl"), cookies: [])
            XCTAssertEqual(app.playback.manifestInspection?.httpStatus, status, path)
            XCTAssertEqual(app.playback.manifestInspection?.outcome.rawValue, outcome, path)
            let report = app.playbackReport
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])
            let inspection = try XCTUnwrap(object["manifestInspection"] as? [String: Any])
            XCTAssertEqual(inspection["httpStatus"] as? Int, status)
            XCTAssertEqual(inspection["transport"] as? String, "foregroundURLSession")
            XCTAssertFalse(report.contains("not-in-report")); XCTAssertFalse(report.contains(path))
            XCTAssertFalse(report.contains(origin.absoluteString))
        }
        let ready = await app.playback.prepare(.init(id: "clean", source: origin.appendingPathComponent("vr180-sbs.mp4").absoluteString), cookies: [])
        XCTAssertTrue(ready); XCTAssertNil(app.playback.manifestInspection, "A later MP4 must not inherit the earlier playlist's HTTP status")
        app.playback.stop(); app.playback.resetDiagnosticsWhenIdle()
        XCTAssertNil(app.playback.manifestInspection)
    }
    func testControlsTimerKeepsInteractionAndPausedVideoVisible() {
        let controls = ImmersiveControlsModel()
        controls.reset(now: 0)
        controls.tick(playing: true, attention: false, now: 4)
        XCTAssertTrue(controls.isVisible)
        controls.tick(playing: true, attention: false, now: 6)
        XCTAssertFalse(controls.isVisible)
        controls.show(now: 7)
        let placement = controls.placementID
        controls.interactionLocked = true
        controls.tick(playing: true, attention: false, now: 20)
        XCTAssertTrue(controls.isVisible)
        XCTAssertEqual(controls.placementID, placement, "Interacting with visible controls must not move them")
        controls.interactionLocked = false
        controls.tick(playing: true, attention: false, now: 24)
        XCTAssertTrue(controls.isVisible)
        controls.tick(playing: true, attention: false, now: 26)
        XCTAssertFalse(controls.isVisible)
        controls.tick(playing: false, attention: false, now: 27)
        XCTAssertTrue(controls.isVisible); XCTAssertGreaterThan(controls.placementID, placement)
        controls.hide(); controls.tick(playing: false, attention: true, now: 28)
        XCTAssertTrue(controls.isVisible, "An error or buffering transition must reveal the controls")
    }
}
