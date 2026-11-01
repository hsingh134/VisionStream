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
        defer { browser.closeTab() }
        browser.open(origin.appendingPathComponent("automation-mp4"))
        var end = Date().addingTimeInterval(15)
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
        var end = Date().addingTimeInterval(15)
        while browser.isLoading || browser.candidates.isEmpty, Date() < end { try await Task.sleep(for: .milliseconds(50)) }
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
