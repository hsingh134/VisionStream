import AVFoundation
import Metal
import RealityKit
import WebKit
import UIKit
import XCTest
@testable import VisionStream

@MainActor
final class NativePlaybackTests: XCTestCase {
    func testHighestHLSRenditionDecodesAboveLowDefault() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel()
        playback.player.isMuted = true
        defer { playback.stop() }
        for (path, width, height) in [("/quality/low/index.m3u8", 480, 240), ("/quality/master.m3u8", 1440, 720)] {
            let ready = await playback.prepare(MediaCandidate(id: path, source: origin + path), cookies: [])
            XCTAssertTrue(ready)
            guard ready else { return }
            let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
            try await renderer.start()
            try await waitUntil({ playback.decodedWidth == width && playback.decodedHeight == height }, seconds: 20)
            XCTAssertEqual(playback.decodedWidth, width); XCTAssertEqual(playback.decodedHeight, height)
            // HLS AVURLAsset does not expose a stable track inventory. The host
            // fixture test verifies AAC in both renditions; here measure decoded video.
            if width == 1440 { XCTAssertEqual(playback.selectedWidth, width); XCTAssertEqual(playback.selectedHeight, height) }
            renderer.stop(); playback.stop()
        }
    }

    func testAutomaticVRFormatsAndManualOverride() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel(automaticallyDetectFormat: true)
        playback.player.isMuted = true
        defer { playback.stop() }
        for (name, projection, layout) in [("vr180-sbs", VideoProjection.vr180, StereoLayout.sideBySide),
                                           ("vr360-tb", .vr360, .topBottom), ("vr180-mono", .vr180, .mono)] {
            let ready = await playback.prepare(MediaCandidate(id: name, source: origin + "/" + name + ".mp4"), cookies: [])
            XCTAssertTrue(ready)
            XCTAssertEqual(playback.projection, projection); XCTAssertEqual(playback.layout, layout)
            XCTAssertFalse(playback.flatScreen)
        }
        playback.manualFormat(); playback.layout = .topBottom; playback.presentation = .screen
        let ready = await playback.prepare(MediaCandidate(id: "manual", source: origin + "/vr180-sbs.mp4"), cookies: [])
        XCTAssertTrue(ready); XCTAssertEqual(playback.layout, .topBottom); XCTAssertTrue(playback.flatScreen)
        playback.enableAutomaticFormat()
        XCTAssertEqual(playback.layout, .sideBySide); XCTAssertEqual(playback.presentation, .vr180)
        let ordinary = await playback.prepare(MediaCandidate(id: "ordinary", source: origin + "/controls-demo.mp4"), cookies: [])
        XCTAssertTrue(ordinary); XCTAssertEqual(playback.layout, .mono); XCTAssertEqual(playback.presentation, .screen)
    }

    func testQualityChangeKeepsRendererAndPausedPosition() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel()
        playback.player.isMuted = true
        playback.quality = .adaptive
        let ready = await playback.prepare(MediaCandidate(id: "quality", source: origin + "/quality/master.m3u8"), cookies: [])
        XCTAssertTrue(ready)
        guard ready else { return }
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop(); playback.stop() }
        try await renderer.start()
        try await waitUntil { playback.decodedWidth > 0 }
        playback.pause(); playback.seek(to: 2)
        try await waitUntil { !playback.isSeeking }
        playback.changeQuality(.highest)
        try await waitUntil({ playback.decodedWidth == 1440 && !playback.isPlaying && playback.isReady }, seconds: 30)
        XCTAssertEqual(playback.player.currentTime().seconds, 2, accuracy: 0.3)
        XCTAssertTrue(renderer.video.isEnabled)
        playback.play()
        try await waitUntil { playback.player.currentTime().seconds > 2.5 }
    }

    func testVRImageDetectionRequiresRepeatedFramesAndRespectsManualOverride() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel(automaticallyDetectFormat: true)
        defer { playback.stop() }
        let ready = await playback.prepare(MediaCandidate(id: "visual", source: origin + "/controls-demo.mp4", title: "VR calibration"), cookies: [])
        XCTAssertTrue(ready)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 128, 64, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let frame = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        let bytes = CVPixelBufferGetBaseAddress(frame)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(frame)
        for y in 0..<64 { for x in 0..<128 {
            let i = y*stride+x*4
            let value = UInt8(((x % 64)*17+y*37+(x%64)%7*y*3)%251)
            bytes[i] = value; bytes[i+1] = value; bytes[i+2] = value; bytes[i+3] = 255
        }}
        CVPixelBufferUnlockBaseAddress(frame, [])
        playback.observeFormatFrame(frame)
        XCTAssertEqual(playback.layout, .mono, "A single frame must not trigger a guess")
        for _ in 0..<2 { try await Task.sleep(for: .milliseconds(400)); playback.observeFormatFrame(frame) }
        XCTAssertEqual(playback.presentation, .vr180); XCTAssertEqual(playback.layout, .sideBySide)
        playback.manualFormat(); playback.presentation = .screen; playback.layout = .mono
        try await Task.sleep(for: .milliseconds(400)); playback.observeFormatFrame(frame)
        XCTAssertEqual(playback.presentation, .screen); XCTAssertEqual(playback.layout, .mono)
    }

    func testHighestQualityPreservesScopedBrowserAndServerIssuedCookies() async throws {
        let origin = try fixtureOrigin(), url = try XCTUnwrap(URL(string: origin))
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: url.host!, .path: "/quality-cookie/", .name: "quality_browser", .value: "allowed", .secure: "TRUE"]))
        let playback = PlaybackModel(); playback.player.isMuted = true
        defer { playback.stop() }
        let ready = await playback.prepare(MediaCandidate(id: "cookie-quality", source: origin + "/quality-cookie/master.m3u8"), cookies: [cookie])
        XCTAssertTrue(ready)
        guard ready else { return }
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop() }
        try await renderer.start()
        try await waitUntil({ playback.decodedWidth == 1440 }, seconds: 20)
        XCTAssertEqual(playback.selectedWidth, 1440)
    }

    func testCancellingHLSInspectionDoesNotOverwriteReplacement() async throws {
        let origin = try fixtureOrigin(), playback = PlaybackModel()
        defer { playback.stop() }
        let first = Task { await playback.prepare(MediaCandidate(id: "slow-master", source: origin + "/delayed/quality/master.m3u8"), cookies: []) }
        try await waitUntil { playback.isPreparing }
        try await Task.sleep(for: .milliseconds(100))
        first.cancel()
        let ready = await playback.prepare(MediaCandidate(id: "replacement", source: origin + "/controls-demo.mp4"), cookies: [])
        let cancelled = await first.value
        XCTAssertTrue(ready); XCTAssertFalse(cancelled)
        XCTAssertEqual(playback.diagnosticCandidate?.id, "replacement")
        XCTAssertEqual(playback.qualityStatus, "Source quality")
        try await Task.sleep(for: .seconds(1.2))
        XCTAssertTrue(playback.isReady); XCTAssertEqual(playback.qualityStatus, "Source quality")
    }

    func testOpaqueMP4SphericalMetadataSelectsProjectionAndPacking() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel(automaticallyDetectFormat: true)
        playback.player.isMuted = true
        defer { playback.stop() }
        for (path, projection, layout) in [("/opaque-a.mp4", VideoProjection.vr180, StereoLayout.sideBySide),
                                            ("/opaque-b.mp4", .vr360, .topBottom)] {
            let ready = await playback.prepare(MediaCandidate(id: path, source: origin + path), cookies: [])
            XCTAssertTrue(ready)
            try await waitUntil({ playback.presentation != .screen }, seconds: 8)
            XCTAssertEqual(playback.projection, projection); XCTAssertEqual(playback.layout, layout)
            XCTAssertEqual(playback.formatStatus, "Auto · metadata")
        }
        let ready = await playback.prepare(MediaCandidate(id: "manual", source: origin + "/opaque-b.mp4"), cookies: [])
        XCTAssertTrue(ready)
        playback.manualFormat(); playback.presentation = .screen; playback.layout = .mono
        try await Task.sleep(for: .seconds(3))
        XCTAssertEqual(playback.presentation, .screen); XCTAssertEqual(playback.layout, .mono)
        playback.enableAutomaticFormat()
        try await waitUntil { playback.presentation == .vr360 && playback.layout == .topBottom }
    }

    func testAutomaticSphericalMetadataRecoversFromInterruptedPrefixRequest() async throws {
        let playback = PlaybackModel(automaticallyDetectFormat: true)
        defer { playback.stop() }
        let ready = await playback.prepare(.init(id: "retry", source: try fixtureOrigin() + "/metadata-transient.mp4", mimeType: "video/mp4"), cookies: [])
        XCTAssertTrue(ready)
        try await waitUntil({ playback.presentation == .vr360 && playback.layout == .topBottom }, seconds: 20)
    }

    func testHighest4KPublishedHLSRenditionAndAutomaticFormat() async throws {
        let origin = try fixtureOrigin(), playback = PlaybackModel(automaticallyDetectFormat: true)
        playback.player.isMuted = true
        defer { playback.stop() }
        let media = MediaCandidate(id: "4k", source: origin + "/quality-4k/master.m3u8", formatHint: .init(projection: .vr180, layout: .sideBySide, evidence: .metadata))
        let ready = await playback.prepare(media, cookies: [])
        XCTAssertTrue(ready)
        guard ready else { return }
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop() }
        try await renderer.start()
        try await waitUntil({ playback.decodedWidth == 3840 && playback.decodedHeight == 1920 }, seconds: 20)
        XCTAssertEqual(playback.selectedWidth, 3840)
        XCTAssertEqual(playback.presentation, .vr180); XCTAssertEqual(playback.layout, .sideBySide)
        XCTAssertTrue(renderer.video.isEnabled)
    }

    func testSphericalMetadataInspectionRejectsIgnoredAndOversizedRanges() async throws {
        let origin = try fixtureOrigin()
        for path in ["/metadata-ignore-range.mp4", "/metadata-oversize"] {
            var request = URLRequest(url: URL(string: origin + path)!)
            request.setValue("bytes=0-262143", forHTTPHeaderField: "Range")
            do {
                _ = try await HLSQualityRequest(kind: .mp4Prefix).load(request)
                XCTFail("An ignored or oversized metadata range was accepted")
            } catch { XCTAssertTrue(error is URLError) }
        }
    }

    func testSceneAutomationConfigurationIsLocalAndExplicit() {
        #if targetEnvironment(simulator)
        let base = ["VISIONSTREAM_SCENE_TEST": "mp4", "VISIONSTREAM_TEST_ORIGIN": "https://127.0.0.1:12345",
                    "VISIONSTREAM_SCENE_TEST_ID": UUID().uuidString]
        XCTAssertNotNil(SimulatorScenarioRunner.Configuration.from(base))
        for origin in ["http://127.0.0.1:12345", "https://example.com:12345", "https://127.0.0.1",
                       "https://127.0.0.1:12345/path", "https://user@127.0.0.1:12345",
                       "https://127.0.0.1:12345?secret=x", "https://127.0.0.1:12345#fragment"] {
            var env = base; env["VISIONSTREAM_TEST_ORIGIN"] = origin
            XCTAssertNil(SimulatorScenarioRunner.Configuration.from(env))
        }
        for key in base.keys {
            var env = base; env.removeValue(forKey: key)
            XCTAssertNil(SimulatorScenarioRunner.Configuration.from(env))
        }
        var review = base; review["VISIONSTREAM_TEST_REVIEW_PANEL"] = "downloads"
        XCTAssertNil(SimulatorScenarioRunner.Configuration.from(review))
        review["VISIONSTREAM_SCENE_TEST"] = "forms"
        XCTAssertEqual(SimulatorScenarioRunner.Configuration.from(review)?.reviewPanel, "downloads")
        review["VISIONSTREAM_TEST_REVIEW_PANEL"] = "arbitrary"
        XCTAssertNil(SimulatorScenarioRunner.Configuration.from(review))
        var env = base; env["VISIONSTREAM_SCENE_TEST"] = "finder"
        XCTAssertNil(SimulatorScenarioRunner.Configuration.from(env))
        env["VISIONSTREAM_TEST_PUBLIC_EXTRACTOR"] = "1"
        XCTAssertNotNil(SimulatorScenarioRunner.Configuration.from(env))
        env["VISIONSTREAM_SCENE_TEST_ID"] = "invalid"
        XCTAssertNil(SimulatorScenarioRunner.Configuration.from(env))
        #endif
    }

    func testOptInUserSuppliedMP4StreamingAndControls() async throws {
        guard ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_LOCAL_MEDIA"] == "1" else {
            throw XCTSkip("Enable only for a user-supplied local MP4 sample")
        }
        let origin = try fixtureOrigin()
        let playback = PlaybackModel()
        playback.player.isMuted = true
        playback.presentation = .screen; playback.layout = .mono
        let ready = await playback.prepare(MediaCandidate(id: "local-sample", source: origin + "/local-user-media.mp4"), cookies: [])
        XCTAssertTrue(ready, "The user-supplied MP4 did not become ready")
        guard ready else { playback.stop(); return }
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop(); playback.stop() }
        try await renderer.start()
        try await waitUntil({ renderer.video.isEnabled && playback.decodedWidth > 0 }, seconds: 20)
        XCTAssertGreaterThan(playback.decodedWidth, 0)
        XCTAssertGreaterThan(playback.decodedHeight, 0)
        XCTAssertGreaterThan(playback.duration, 0)
        playback.pause()
        let paused = playback.player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(playback.player.currentTime().seconds, paused, accuracy: 0.15)
        let target = min(5, playback.duration / 2)
        playback.seek(to: target)
        try await waitUntil { abs(playback.player.currentTime().seconds - target) < 0.2 }
        print("LOCAL_USER_MEDIA_SEEK_STATE: target=\(target), actual=\(playback.player.currentTime().seconds), bounds=\(playback.seekStart)...\(playback.seekEnd)")
        playback.play()
        try await waitUntil { playback.player.currentTime().seconds > target + 0.3 }
        playback.seek(to: playback.duration - 0.4)
        try await waitUntil({ !playback.isSeeking && playback.player.timeControlStatus == .paused &&
            playback.player.currentTime().seconds >= playback.duration - 0.2 }, seconds: 10)
        playback.toggle()
        try await waitUntil({ !playback.isSeeking && playback.isPlaying &&
            playback.player.currentTime().seconds > 0.3 && playback.player.currentTime().seconds < 2 }, seconds: 10)
        XCTAssertNil(playback.errorMessage)
        print("LOCAL_USER_MEDIA_RENDER_OK: \(playback.decodedWidth)x\(playback.decodedHeight), Screen Mono, pause/seek/resume; no title or source identity logged")
    }

    func testPreparationTimeoutKeepsItsReasonAfterCleanup() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel(preparationTimeout: .milliseconds(200))
        defer { playback.stop() }
        let ready = await playback.prepare(MediaCandidate(id: "timeout", source: origin + "/delayed/vr180-sbs.mp4"), cookies: [])
        XCTAssertFalse(ready)
        XCTAssertEqual(playback.failureReason, .preparationTimeout)
        XCTAssertTrue(playback.diagnosticStage.hasPrefix("failed-at-"))
        XCTAssertTrue(playback.errorMessage?.contains("timed out") == true)
        XCTAssertFalse(playback.isPreparing)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertEqual(playback.decodedWidth, 0)
        // Cancellation of asset loading must not replace timeout with a URL cancellation error.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(playback.failureReason, .preparationTimeout)
        playback.resetDiagnosticsWhenIdle()
        XCTAssertEqual(playback.failureReason, .none)
        XCTAssertTrue(playback.errorLogCodes.isEmpty)
    }

    func testDelayedWebsitePlaybackWithoutDirectGesture() async throws {
        let origin = try fixtureOrigin()
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { !$0.isHidden })
        let url = try XCTUnwrap(URL(string: origin + "/web-delayed-playback-test"))

        // Negative control: the previous policy rejects the page's own delayed,
        // unmuted play call even though its MP4 and codecs are supported.
        let restrictive = WKWebViewConfiguration()
        restrictive.allowsInlineMediaPlayback = true
        restrictive.mediaTypesRequiringUserActionForPlayback = .all
        let control = WKWebView(frame: window.bounds, configuration: restrictive)
        window.addSubview(control)
        defer { control.stopLoading(); control.removeFromSuperview() }
        control.load(URLRequest(url: url))
        let rejected = try await delayedPlaybackResult(control, path: "/web-delayed-playback-test")
        XCTAssertEqual(rejected, "gesture-required")
        control.removeFromSuperview()

        let browser = BrowserModel()
        browser.webView.frame = window.bounds
        window.addSubview(browser.webView)
        defer { browser.webView.stopLoading(); browser.webView.removeFromSuperview() }
        for path in ["/web-delayed-playback-test", "/web-delayed-hls-playback-test"] {
            browser.open(try XCTUnwrap(URL(string: origin + path)))
            let result = try await delayedPlaybackResult(browser.webView, path: path)
            XCTAssertEqual(result, "started", "A website may begin playback after asynchronous player setup")
            guard result == "started" else { return }
            try await waitUntil({ browser.candidates.contains { $0.currentTime > 0.1 && $0.webMedia?.paused == false } }, seconds: 15)
            let presented = try await browser.webView.callAsyncJavaScript("""
                const video = document.querySelector('video');
                return await new Promise(resolve => {
                    const timer = setTimeout(() => { video.cancelVideoFrameCallback(handle); resolve(false); }, 8000);
                    const handle = video.requestVideoFrameCallback((_, metadata) => {
                        clearTimeout(timer); resolve(metadata.width === 1024 && metadata.height === 512 && metadata.presentedFrames > 0);
                    });
                });
                """, in: nil, contentWorld: .page)
            XCTAssertEqual(presented as? Bool, true)
            await browser.webView.pauseAllMediaPlayback()
            print("DELAYED_WEB_PLAYBACK_OK: previous policy rejected; production policy presented 1024x512 video, \(path)")
        }
    }

    private func delayedPlaybackResult(_ webView: WKWebView, path: String) async throws -> String {
        // Poll the page-owned outcome. Calling play from evaluateJavaScript can
        // carry an artificial user gesture and would invalidate this regression.
        for _ in 0..<150 {
            if let state = try? await webView.evaluateJavaScript("({path:location.pathname,result:window.fixtureResult})") as? [String: Any],
               state["path"] as? String == path, let value = state["result"] as? String,
               value != "pending" { return value }
            try await Task.sleep(for: .milliseconds(100))
        }
        return "timed-out"
    }

    func testWebpageMediaPlaybackAndFailureDiagnostics() async throws {
        let origin = try fixtureOrigin()
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let browser = BrowserModel()
        // WKWebView can suspend media when detached from a visible window. This
        // test exercises the same attached view used by the app, not a hidden DOM.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { !$0.isHidden })
        browser.webView.frame = window.bounds
        window.addSubview(browser.webView)
        defer { browser.webView.stopLoading(); browser.webView.removeFromSuperview() }
        var paths = ["/web-playback-test", "/web-hls-playback-test"]
        if ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_PUBLIC_EXTRACTOR"] == "1" {
            paths.append("/web-public-playback-test")
        }
        for path in paths {
            let previous = browser.navigationVersion
            browser.open(try XCTUnwrap(URL(string: origin + path)))
            try await waitUntil({ browser.navigationVersion > previous && browser.webView.url?.path == path &&
                !browser.isLoading && !browser.candidates.isEmpty }, seconds: path == "/web-public-playback-test" ? 45 : 15)
            let outcome = try await browser.webView.callAsyncJavaScript("""
            return await Promise.race([document.querySelector('video').play().then(() => 'started', () => 'rejected'),
                new Promise(resolve => setTimeout(() => resolve('timed-out'), 10000))]);
            """, in: nil, contentWorld: .page)
            XCTAssertEqual(outcome as? String, "started", path)
            try await waitUntil({ browser.candidates.contains { $0.currentTime > 0.1 && $0.webMedia?.paused == false } }, seconds: 15)
            XCTAssertEqual(browser.candidates.first?.webMedia?.errorCode, 0)
            XCTAssertGreaterThanOrEqual(browser.candidates.first?.webMedia?.readyState ?? 0, 2)
            // Confirm a presented video frame, rather than relying only on the
            // media clock (which can advance for audio while video stays blank).
            let frame = try await browser.webView.callAsyncJavaScript("""
                const video = document.querySelector('video');
                if (typeof video.requestVideoFrameCallback !== 'function') return {unsupported:true};
                return await new Promise(resolve => {
                    const timer = setTimeout(() => { video.cancelVideoFrameCallback(handle); resolve({timedOut:true}); }, 8000);
                    const handle = video.requestVideoFrameCallback((_, metadata) => {
                        clearTimeout(timer);
                        resolve({width:metadata.width, height:metadata.height, frames:metadata.presentedFrames});
                    });
                });
                """, in: nil, contentWorld: .page) as? [String: Any]
            let expectedWidth = path == "/web-public-playback-test" ? 2160 : 1024
            let expectedHeight = path == "/web-public-playback-test" ? 1080 : 512
            XCTAssertEqual(frame?["width"] as? Int, expectedWidth, "WebKit must present a decoded frame: \(path)")
            XCTAssertEqual(frame?["height"] as? Int, expectedHeight)
            XCTAssertGreaterThan(frame?["frames"] as? Int ?? 0, 0)
            print("WEBPAGE_PRESENTED_FRAME_OK: \(path), \(frame?["width"] as? Int ?? 0)x\(frame?["height"] as? Int ?? 0)")
            let beforePause = browser.candidates.first?.currentTime ?? 0
            await browser.pausePageVideo(MediaCandidate(id: "finder-parent", source: origin + "/unmatched-native-source.mp4"))
            try await waitUntil { browser.candidates.first?.webMedia?.paused == true }
            let resumed = try await browser.webView.callAsyncJavaScript("return await Promise.race([document.querySelector('video').play().then(() => true, () => false), new Promise(resolve => setTimeout(() => resolve(false), 10000))])", in: nil, contentWorld: .page)
            XCTAssertEqual(resumed as? Bool, true)
            try await waitUntil { (browser.candidates.first?.currentTime ?? 0) > beforePause + 0.1 }
            print("WEBPAGE_PLAYBACK_OK: \(path), moving inline video, no native handoff")
        }
        // A fresh document isolates error capture from HLS source-switch behaviour.
        browser.open(try XCTUnwrap(URL(string: origin + "/web-error-test")))
        try await waitUntil({ browser.webView.url?.path == "/web-error-test" && !browser.isLoading &&
            browser.candidates.contains { $0.source.hasSuffix("/missing-test.mp4") } }, seconds: 15)
        _ = try await browser.webView.callAsyncJavaScript("document.querySelector('video').play().catch(() => {}); return true", in: nil, contentWorld: .page)
        try await waitUntil({ browser.candidates.contains { ($0.webMedia?.errorCode ?? 0) > 0 } }, seconds: 15)
        let state = try await browser.webView.callAsyncJavaScript("const v = document.querySelector('video'); return {error: v.error?.code || 0, ready: v.readyState, network: v.networkState, paused: v.paused}", in: nil, contentWorld: .page)
        print("WEBPAGE_ERROR_TEST_STATE: \(String(describing: state))")
        print("WEBPAGE_DETECTOR_ERROR_CODES: \(browser.candidates.map { $0.webMedia?.errorCode ?? -1 })")
        XCTAssertTrue((1...4).contains(browser.candidates.first?.webMedia?.errorCode ?? 0))
    }

    func testFlatScreenFrameAndPausedPresentationChanges() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel()
        XCTAssertEqual(playback.presentation, .screen)
        XCTAssertEqual(playback.layout, .mono)
        let ready = await playback.prepare(MediaCandidate(id: "screen", source: origin + "/vr180-sbs.mp4"), cookies: [])
        XCTAssertTrue(ready)
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop(); playback.stop() }
        try await renderer.start()
        try await waitUntil { renderer.video.isEnabled && playback.decodedWidth > 0 }
        playback.pause()
        var bounds = try XCTUnwrap(renderer.video.model).mesh.bounds.extents
        XCTAssertEqual(bounds.x, 2.4, accuracy: 0.01)
        XCTAssertEqual(bounds.y, 1.2, accuracy: 0.01)
        XCTAssertEqual(playback.decodedWidth, 1024)
        XCTAssertEqual(playback.decodedHeight, 512)
        playback.layout = .sideBySide
        try await waitUntil { abs((renderer.video.model?.mesh.bounds.extents.x ?? 0) - 1.6) < 0.01 }
        bounds = try XCTUnwrap(renderer.video.model).mesh.bounds.extents
        XCTAssertEqual(bounds.y, 1.6, accuracy: 0.01)
        // Repeat paused texture reallocations to exercise settings changes near
        // asynchronously scheduled uploads, not just a fresh initial frame.
        for layout in [StereoLayout.mono, .sideBySide, .topBottom, .sideBySide] {
            playback.layout = layout
            let expectedX: Float = layout == .sideBySide ? 1.6 : 2.4
            let expectedY: Float = layout == .sideBySide ? 1.6 : (layout == .mono ? 1.2 : 0.6)
            try await waitUntil {
                guard let size = renderer.video.model?.mesh.bounds.extents else { return false }
                return abs(size.x - expectedX) < 0.01 && abs(size.y - expectedY) < 0.01
            }
        }
        playback.presentation = .vr180
        try await waitUntil { (renderer.video.model?.mesh.bounds.extents.x ?? 0) > 19 }
        playback.presentation = .screen
        try await waitUntil { (renderer.video.model?.mesh.bounds.extents.x ?? 0) < 2 }
        XCTAssertNil(playback.errorMessage)
        playback.fail("Controlled renderer failure")
        let failedStage = playback.diagnosticStage
        playback.receivedFrame(width: 777, height: 777)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(playback.diagnosticStage, failedStage, "Late GPU frames must not erase failure diagnostics")
        XCTAssertEqual(playback.decodedWidth, 1024)
        XCTAssertFalse(renderer.video.isEnabled)
        XCTAssertNil(renderer.video.model, "Failure must release the displayed material and texture references")
    }

    func testCompatibilityDiagnosticsAndRecovery() async throws {
        let origin = try fixtureOrigin()
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let app = AppModel()
        try attachBrowser(app.browser)
        defer { app.browser.webView.stopLoading(); app.browser.webView.removeFromSuperview(); app.playback.stop() }
        app.browser.open(try XCTUnwrap(URL(string: origin + "/library/forbidden")))
        try await waitUntil({ app.browser.pageHTTPStatus == 403 && !app.browser.isLoading }, seconds: 15)
        XCTAssertEqual(app.browser.pageHTTPStatus, 403)
        let failed = await app.playback.prepare(MediaCandidate(id: "missing", source: origin + "/missing.mp4?token=secret"), cookies: [])
        XCTAssertFalse(failed)
        XCTAssertTrue(app.playback.diagnosticStage.hasPrefix("failed-at-"))
        XCTAssertFalse(app.playback.failureCodes.isEmpty)
        XCTAssertFalse(app.playback.failureCodes.joined().contains("secret"))
        XCTAssertEqual(app.playback.diagnosticCandidate?.id, "missing")
        app.browser.open(try XCTUnwrap(URL(string: origin + "/empty-test")))
        try await waitUntil({ app.browser.pageHTTPStatus == 200 && !app.browser.isLoading }, seconds: 15)
        XCTAssertEqual(app.playback.diagnosticStage, "not-attempted")
        XCTAssertTrue(app.playback.failureCodes.isEmpty)
        XCTAssertTrue(app.browser.pageFailureCodes.isEmpty)
        XCTAssertNil(app.playback.errorMessage)
        XCTAssertNil(app.playback.diagnosticCandidate)
    }

    func testStartupDoesNotReplaceAnExplicitNavigation() async throws {
        let origin = try fixtureOrigin()
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let browser = BrowserModel()
        try attachBrowser(browser)
        defer { browser.webView.stopLoading(); browser.webView.removeFromSuperview() }
        XCTAssertNil(browser.webView.url)
        let requested = try XCTUnwrap(URL(string: origin + "/empty-test"))
        browser.open(requested)
        browser.startIfNeeded()
        try await waitUntil({ browser.webView.url == requested && !browser.webView.isLoading }, seconds: 15)
        let version = browser.navigationVersion
        browser.startIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(browser.webView.url, requested)
        XCTAssertEqual(browser.navigationVersion, version)
        XCTAssertNil(browser.message)

        UserDefaults.standard.removeObject(forKey: "lastPage")
        let home = BrowserModel()
        try attachBrowser(home)
        defer { home.webView.stopLoading(); home.webView.removeFromSuperview() }
        home.startIfNeeded()
        try await waitUntil({ home.webView.url?.lastPathComponent == "Start.html" && !home.webView.isLoading }, seconds: 15)
        let title = try await home.webView.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(title, "VisionStream")
        XCTAssertNil(home.message)

        UserDefaults.standard.set(requested.absoluteString, forKey: "lastPage")
        let preferences = BrowserPreferences(defaults: UserDefaults(suiteName: "VisionStreamRestore-" + UUID().uuidString)!)
        preferences.restoration = .page; preferences.remember(requested)
        let restored = BrowserModel(preferences: preferences)
        try attachBrowser(restored)
        defer { restored.webView.stopLoading(); restored.webView.removeFromSuperview() }
        restored.startIfNeeded()
        try await waitUntil({ restored.webView.url == requested && !restored.webView.isLoading }, seconds: 15)
        XCTAssertEqual(restored.address, requested.absoluteString)
        XCTAssertNil(restored.message)
    }

    private func attachBrowser(_ browser: BrowserModel) throws {
        // Navigation/media tests must exercise a view in the visible hierarchy,
        // as production does. Detached WebKit views can be throttled/suspended.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { !$0.isHidden })
        browser.webView.frame = window.bounds
        window.addSubview(browser.webView)
    }

    func testDocumentedBrowserUserAgentHandoffForMP4AndHLS() async throws {
        let origin = try fixtureOrigin()
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let browser = BrowserModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { !$0.isHidden })
        browser.webView.frame = window.bounds
        window.addSubview(browser.webView)
        defer { browser.webView.stopLoading(); browser.webView.removeFromSuperview() }
        browser.open(try XCTUnwrap(URL(string: origin + "/agent-context-test")))
        try await waitUntil({ browser.webView.url?.path == "/agent-context-test" && browser.pageHTTPStatus == 200 && !browser.webView.isLoading }, seconds: 15)
        let browserAgent = await browser.playbackUserAgent()
        let userAgent = try XCTUnwrap(browserAgent)
        XCTAssertFalse(userAgent.isEmpty)
        // The fixture compares against the identifier it received from WebKit.
        // Every native manifest/segment request must match; no identifier is logged.
        let playback = PlaybackModel()
        defer { playback.stop() }
        for path in ["/agent-test/vr180-sbs.mp4", "/agent-test/hls/vr180-sbs/master.m3u8"] {
            let ready = await playback.prepare(MediaCandidate(id: path, source: origin + path), cookies: [], userAgent: userAgent)
            XCTAssertTrue(ready)
            guard ready else { continue }
            XCTAssertTrue(playback.browserUserAgentApplied)
            playback.play()
            var frame: CVPixelBuffer?
            let deadline = Date().addingTimeInterval(10)
            while frame == nil, Date() < deadline {
                frame = playback.videoOutput?.copyPixelBuffer(forItemTime: playback.player.currentTime(), itemTimeForDisplay: nil)
                if frame == nil { try await Task.sleep(for: .milliseconds(50)) }
            }
            XCTAssertNotNil(frame)
            playback.stop()
        }
        let ordinary = MediaCandidate(id: "no-agent", source: origin + "/vr180-sbs.mp4")
        let ready = await playback.prepare(ordinary, cookies: [], userAgent: "invalid\r\nheader")
        XCTAssertTrue(ready)
        XCTAssertFalse(playback.browserUserAgentApplied, "Control characters cannot become a request header")
        playback.stop(); playback.resetDiagnosticsWhenIdle()
        XCTAssertFalse(playback.browserUserAgentApplied)
        print("BROWSER_USER_AGENT_HANDOFF_OK: MP4/HLS decoded with the actual WebKit request identifier; value omitted")
    }

    func testEmptyMediaAttributesAreNotVideoSources() async throws {
        let origin = try fixtureOrigin()
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let browser = BrowserModel()
        browser.webView.loadHTMLString("""
            <!doctype html><title>Empty media attributes fixture</title>
            <video id="empty" preload="none" src=""></video>
            <video preload="none" src="  "></video>
            <video preload="none"><source id="emptySource" src="" type="video/mp4"><source src="  " type="application/vnd.apple.mpegurl"></video>
            <video id="valid" preload="none"><source src="/vr180-sbs.mp4" type="video/mp4"></video>
            """, baseURL: URL(string: origin + "/empty-attribute-page"))
        defer { browser.webView.stopLoading() }
        try await waitUntil({ browser.candidates.contains { $0.source == origin + "/vr180-sbs.mp4" } }, seconds: 15)
        let state = try await browser.webView.evaluateJavaScript("""
            ({videoResolvesToDocument:document.querySelector('#empty').src === location.href,
              sourceResolvesToDocument:document.querySelector('#emptySource').src === location.href,
              emptyAttribute:document.querySelector('#empty').getAttribute('src') === ''})
            """) as? [String: Any]
        XCTAssertEqual(state?["emptyAttribute"] as? Bool, true)
        print("EMPTY_SOURCE_DOM_BEHAVIOUR: \(String(describing: state))")
        XCTAssertEqual(browser.candidates.count, 1, "Empty attributes must not advertise the HTML document as MP4/HLS")
        XCTAssertEqual(browser.candidates.first?.source, origin + "/vr180-sbs.mp4")
    }

    func testWebKitDetectsFramesShadowRootsAndDynamicSources() async throws {
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let browser = BrowserModel()
        browser.webView.loadHTMLString("""
            <!doctype html><title>Native detector fixture</title>
            <video id="main" src="https://media.example/main.mp4"></video>
            <iframe srcdoc='<video src="https://media.example/frame.m3u8"></video>'></iframe>
            <div id="shadow"></div>
            <script>document.querySelector('#shadow').attachShadow({mode:'open'}).innerHTML='<video src="https://media.example/shadow.mp4"></video>';</script>
            """, baseURL: URL(string: "https://fixture.example/"))
        defer { browser.webView.stopLoading() }
        let expected: Set<String> = ["https://media.example/main.mp4", "https://media.example/frame.m3u8", "https://media.example/shadow.mp4"]
        let deadline = Date().addingTimeInterval(15)
        while !expected.isSubset(of: Set(browser.candidates.map(\.source))), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        print("WebKit detected sources: \(browser.candidates.map(\.source)); browser error: \(browser.message ?? "none")")
        if !expected.isSubset(of: Set(browser.candidates.map(\.source))) {
            let details = try await browser.webView.callAsyncJavaScript(
                "return JSON.stringify({url:location.href, videos:document.querySelectorAll('video').length, installed:!!globalThis.visionStreamDetector, scan:globalThis.visionStreamDetector?.scan()})",
                arguments: [:], in: nil, contentWorld: .defaultClient)
            print("WebKit detector diagnostics: \(String(describing: details))")
        }
        XCTAssertTrue(expected.isSubset(of: Set(browser.candidates.map(\.source))))
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('#main').src = 'https://media.example/changed.mp4'")
        let changedDeadline = Date().addingTimeInterval(8)
        while !browser.candidates.contains(where: { $0.source == "https://media.example/changed.mp4" }), Date() < changedDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(browser.candidates.contains { $0.source == "https://media.example/changed.mp4" })
        XCTAssertFalse(browser.candidates.contains { $0.source == "https://media.example/main.mp4" })
        _ = try await browser.webView.callAsyncJavaScript(
            "document.querySelector('#main').pause = () => { document.body.dataset.nativePaused = 'yes'; }; return true;",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        await browser.pausePageVideo(MediaCandidate(id: "library-entry", source: "https://media.example/changed.mp4"))
        let nativePaused = try await browser.webView.evaluateJavaScript("document.body.dataset.nativePaused") as? String
        XCTAssertEqual(nativePaused, "yes", "A library handoff should pause a matching page video")
    }

    func testBundledStereoMaterialLoads() async throws {
        var material = try await ShaderGraphMaterial(named: "/Root/StereoMaterial", from: "StereoMaterial.usda", in: Bundle.main)
        let texture = try LowLevelTexture(descriptor: .init(pixelFormat: .rgba16Float, width: 2, height: 2,
                                                          textureUsage: [.shaderRead, .shaderWrite]))
        let resource = try await TextureResource(from: texture)
        try material.setParameter(name: "leftEye", value: .textureResource(resource))
        try material.setParameter(name: "rightEye", value: .textureResource(resource))
    }

    func testCrossOriginDetectionAndNavigationClearsCandidates() async throws {
        let origin = try fixtureOrigin()
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let browser = BrowserModel()
        defer { browser.webView.stopLoading() }
        browser.open(try XCTUnwrap(URL(string: origin + "/cross-origin-test")))
        let deadline = Date().addingTimeInterval(20)
        while browser.candidates.count < 3, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        print("Cross-origin sources: \(browser.candidates.map(\.source)); error=\(browser.message ?? "none")")
        XCTAssertTrue(browser.candidates.contains { URL(string: $0.source)?.host == "127.0.0.1" })
        XCTAssertTrue(browser.candidates.contains { URL(string: $0.pageURL)?.host == "localhost" && $0.source.hasSuffix("vr360-tb.mp4") })
        XCTAssertTrue(browser.candidates.contains { URL(string: $0.pageURL)?.host == "localhost" && $0.source.hasSuffix("vr360-mono.mp4") })
        let version = browser.navigationVersion
        browser.open(try XCTUnwrap(URL(string: origin + "/delayed/empty-test")))
        XCTAssertTrue(browser.candidates.isEmpty, "Old media must disappear before WebKit begins the request")
        XCTAssertTrue(browser.isLoading)
        XCTAssertNil(browser.pageHTTPStatus)
        XCTAssertGreaterThan(browser.navigationVersion, version)
        browser.scan()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(browser.candidates.isEmpty, "The departing page must not repopulate candidates during navigation")
        let navigationDeadline = Date().addingTimeInterval(10)
        while browser.navigationVersion == version || browser.isLoading, Date() < navigationDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        // Allow an old frame's scheduled report time to pass too.
        try await Task.sleep(for: .seconds(2))
        XCTAssertGreaterThan(browser.navigationVersion, version)
        XCTAssertTrue(browser.candidates.isEmpty)
        XCTAssertNil(browser.message)
    }

    func testPlaybackPauseSeekResumeAndStop() async throws {
        let origin = try fixtureOrigin()
        for path in ["/vr180-sbs.mp4", "/hls/vr180-sbs/master.m3u8"] {
            let playback = PlaybackModel()
            defer { playback.stop() }
            let ready = await playback.prepare(MediaCandidate(id: path, source: origin + path, currentTime: 1.5), cookies: [])
            XCTAssertTrue(ready, playback.errorMessage ?? path)
            guard ready else { continue }
            XCTAssertEqual(playback.player.currentTime().seconds, 1.5, accuracy: 0.15)
            XCTAssertGreaterThan(playback.seekEnd, 7)
            playback.play()
            try await waitUntil { playback.isPlaying }
            playback.pause()
            let pausedTime = playback.player.currentTime().seconds
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(playback.player.currentTime().seconds, pausedTime, accuracy: 0.1)
            playback.seek(to: 1)
            XCTAssertTrue(playback.isSeeking)
            XCTAssertEqual(playback.elapsed, 1)
            playback.skip(2)
            XCTAssertEqual(playback.elapsed, 3)
            try await waitUntil { !playback.isSeeking && abs(playback.player.currentTime().seconds - 3) < 0.2 }
            playback.seek(to: 4)
            try await waitUntil { abs(playback.player.currentTime().seconds - 4) < 0.2 }
            playback.seek(to: .nan)
            XCTAssertTrue(playback.player.currentTime().seconds.isFinite)
            playback.skip(-100)
            try await waitUntil { playback.player.currentTime().seconds < 0.2 }
            playback.toggle()
            try await waitUntil { playback.isPlaying && playback.player.currentTime().seconds > 0.3 }
            playback.seek(to: playback.duration - 0.3)
            try await waitUntil({ !playback.isSeeking && playback.player.timeControlStatus == .paused &&
                playback.player.currentTime().seconds >= playback.duration - 0.2 }, seconds: 10)
            playback.toggle()
            try await waitUntil({ !playback.isSeeking && playback.isPlaying &&
                playback.player.currentTime().seconds > 0.3 && playback.player.currentTime().seconds < 2 }, seconds: 10)
            playback.receivedFrame()
            playback.stop()
            XCTAssertFalse(playback.isReady)
            XCTAssertFalse(playback.isPlaying)
            XCTAssertNil(playback.videoOutput)
            XCTAssertNil(playback.player.currentItem)
            XCTAssertFalse(playback.isSeeking)
            XCTAssertNil(playback.errorMessage)
            print("Playback controls passed for \(path)")
        }
    }

    func testCancellationAndReplacementDoNotLeaveStalePlayback() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel()
        defer { playback.stop() }
        let delayed = MediaCandidate(id: "slow", source: origin + "/delayed/vr180-sbs.mp4")
        let cancelled = Task { await playback.prepare(delayed, cookies: []) }
        try await waitUntil { playback.isPreparing }
        try await Task.sleep(for: .milliseconds(100))
        cancelled.cancel()
        let cancelledReady = await cancelled.value
        print("Cancelled preparation: ready=\(cancelledReady), preparing=\(playback.isPreparing), error=\(playback.errorMessage ?? "none")")
        XCTAssertFalse(cancelledReady)
        XCTAssertFalse(playback.isPreparing)
        XCTAssertFalse(playback.isReady)
        XCTAssertNil(playback.videoOutput)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertNil(playback.errorMessage)

        let replaced = Task { await playback.prepare(delayed, cookies: []) }
        try await waitUntil { playback.isPreparing }
        try await Task.sleep(for: .milliseconds(100))
        let current = MediaCandidate(id: "current", source: origin + "/vr360-tb.mp4")
        let currentReady = await playback.prepare(current, cookies: [])
        let replacedReady = await replaced.value
        XCTAssertFalse(replacedReady)
        XCTAssertTrue(currentReady, playback.errorMessage ?? "Replacement did not become ready")
        XCTAssertTrue(playback.isReady)
        XCTAssertEqual((playback.player.currentItem?.asset as? AVURLAsset)?.url.absoluteString, current.source)
        XCTAssertNil(playback.errorMessage)
    }

    func testNetworkAndAuthenticationFailuresRecover() async throws {
        let origin = try fixtureOrigin()
        let playback = PlaybackModel()
        defer { playback.stop() }
        for path in ["/missing.mp4", "/auth/vr180-sbs.mp4", "/auth/hls/vr180-sbs/master.m3u8"] {
            let ready = await playback.prepare(MediaCandidate(id: path, source: origin + path), cookies: [])
            print("Expected rejection \(path): ready=\(ready), error=\(playback.errorMessage ?? "none")")
            XCTAssertFalse(ready)
            XCTAssertFalse(playback.isPreparing)
            XCTAssertFalse(playback.isReady)
            XCTAssertNil(playback.videoOutput)
            XCTAssertNil(playback.player.currentItem)
            XCTAssertNotNil(playback.errorMessage)
        }
        let recovered = await playback.prepare(MediaCandidate(id: "recovery", source: origin + "/vr180-sbs.mp4"), cookies: [])
        XCTAssertTrue(recovered, playback.errorMessage ?? "Recovery failed")
        XCTAssertNil(playback.errorMessage)
    }

    private func fixtureOrigin() throws -> String {
        guard let origin = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"], origin.hasPrefix("https://") else {
            throw XCTSkip("Set VISIONSTREAM_TEST_ORIGIN to the HTTPS fixture server.")
        }
        return origin
    }

    private func waitUntil(_ condition: () -> Bool, seconds: Double = 5, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "Native playback condition did not become true within \(seconds) seconds", file: file, line: line)
    }

    func testMetalSplitsPackedEyes() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let library = try device.makeDefaultLibrary(bundle: Bundle.main)
        let function = try XCTUnwrap(library.makeFunction(name: "splitStereoVideo"))
        let pipeline = try makePipeline(device: device, function: function)
        // Distinct primary colours expose eye, row and column errors without transfer-function ambiguity.
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        desc.storageMode = .shared; desc.usage = [.shaderRead]
        let source = try XCTUnwrap(device.makeTexture(descriptor: desc))
        var pixels = [UInt8]()
        for y in 0..<4 {
            for x in 0..<4 {
                let colour = (x + y * 2) % 8
                pixels += [colour & 4 == 0 ? 0 : 255, colour & 2 == 0 ? 0 : 255, colour & 1 == 0 ? 0 : 255, 255]
            }
        }
        pixels.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 16) }
        var assertions = 0
        for (layoutIndex, layout) in StereoLayout.allCases.enumerated() {
            for swap in [false, true] {
                for flip in [false, true] {
                    let size = layout.eyeSize(width: 4, height: 4)
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: size.width, height: size.height, mipmapped: false)
                    descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .shaderWrite]
                    let left = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
                    let right = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
                    let command = try XCTUnwrap(queue.makeCommandBuffer())
                    let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
                    encoder.setComputePipelineState(pipeline)
                    encoder.setTexture(source, index: 0); encoder.setTexture(left, index: 1); encoder.setTexture(right, index: 2)
                    var params = SIMD4<UInt32>(UInt32(layoutIndex), swap ? 1 : 0, flip ? 1 : 0, 0)
                    encoder.setBytes(&params, length: MemoryLayout<SIMD4<UInt32>>.stride, index: 0)
                    encoder.dispatchThreads(MTLSize(width: size.width, height: size.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 2, height: 2, depth: 1))
                    encoder.endEncoding()
                    await withCheckedContinuation { continuation in
                        command.addCompletedHandler { @Sendable _ in continuation.resume() }
                        command.commit()
                    }
                    XCTAssertEqual(command.status, .completed)
                    for (eye, texture) in [left, right].enumerated() {
                        var output = [UInt16](repeating: 0, count: size.width * size.height * 4)
                        output.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: size.width * 8,
                            from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0) }
                        for y in 0..<size.height {
                            for x in 0..<size.width {
                                let uv = layout.sourceUV(SIMD2<Float>((Float(x) + 0.5) / Float(size.width), (Float(y) + 0.5) / Float(size.height)), eye: eye, swapEyes: swap, flipY: flip)
                                let offset = (min(3, Int(uv.y * 4)) * 4 + min(3, Int(uv.x * 4))) * 4
                                let expected = [pixels[offset + 2], pixels[offset + 1], pixels[offset], pixels[offset + 3]]
                                for channel in 0..<4 {
                                    let actual = Float(Float16(bitPattern: output[(y * size.width + x) * 4 + channel]))
                                    XCTAssertEqual(actual, Float(expected[channel]) / 255, accuracy: 0.002,
                                        "\(layout.rawValue) swap=\(swap) flip=\(flip) eye=\(eye) pixel=\(x),\(y) channel=\(channel)")
                                    assertions += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        print("Native Metal: 12 configurations, \(assertions) channel assertions, RGBA16Float output")
    }

    private func makePipeline(device: any MTLDevice, function: any MTLFunction) throws -> any MTLComputePipelineState {
        try device.makeComputePipelineState(function: function)
    }

    func testStreamingRendererUploadsFrames() async throws {
        #if targetEnvironment(simulator)
        guard let origin = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"], origin.hasPrefix("https://") else {
            throw XCTSkip("Set VISIONSTREAM_TEST_ORIGIN to the HTTPS fixture server.")
        }
        // Exercise the actual decoder → CVMetalTexture → LowLevelTexture → material path.
        // This cannot establish final per-eye presentation or physical head tracking.
        let formats: [(String, VideoProjection, StereoLayout)] = [
            ("vr180-mono", .vr180, .mono), ("vr180-sbs", .vr180, .sideBySide), ("vr180-tb", .vr180, .topBottom),
            ("vr360-mono", .vr360, .mono), ("vr360-sbs", .vr360, .sideBySide), ("vr360-tb", .vr360, .topBottom)
        ]
        for (name, projection, layout) in formats {
          for path in ["/\(name).mp4", "/hls/\(name)/master.m3u8"] {
            let playback = PlaybackModel()
            playback.flatScreen = false; playback.projection = projection; playback.layout = layout
            let ready = await playback.prepare(MediaCandidate(id: path, source: origin + path), cookies: [])
            XCTAssertTrue(ready, "\(path): \(playback.errorMessage ?? "not ready")")
            guard ready else { continue }
            let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
            defer { renderer.stop(); playback.stop() }
            try await renderer.start()
            let deadline = Date().addingTimeInterval(12)
            while !renderer.video.isEnabled, playback.errorMessage == nil, Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            print("Renderer fixture \(path): visible=\(renderer.video.isEnabled), error=\(playback.errorMessage ?? "none")")
            XCTAssertNil(playback.errorMessage)
            XCTAssertTrue(renderer.video.isEnabled, "No completed GPU frame for \(path)")
            XCTAssertNotNil(renderer.video.model)
            playback.pause()
            playback.projection = projection == .vr180 ? .vr360 : .vr180
            playback.layout = layout == .mono ? .topBottom : .mono
            playback.swapEyes = true; playback.flipY = true
            let expectedExtent: Float = projection == .vr180 ? 20 : 10
            try await waitUntil({ renderer.video.isEnabled &&
                abs((renderer.video.model?.mesh.bounds.extents.z ?? 0) - expectedExtent) < 0.1 }, seconds: 5)
            let extent = try XCTUnwrap(renderer.video.model).mesh.bounds.extents.z
            XCTAssertEqual(extent, expectedExtent, accuracy: 0.1)
            XCTAssertTrue(renderer.video.isEnabled, "A paused layout change did not finish uploading for \(path)")
            XCTAssertNil(playback.errorMessage)
          }
        }
        #else
        throw XCTSkip("Physical renderer tests require an active immersive space; use the device acceptance checklist.")
        #endif
    }

    func testBrowserCookiesAuthorizeNativeMP4AndHLS() async throws {
        guard let origin = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"], origin.hasPrefix("https://") else {
            throw XCTSkip("Set VISIONSTREAM_TEST_ORIGIN to the HTTPS fixture server.")
        }
        let previousPage = UserDefaults.standard.string(forKey: "lastPage")
        defer { UserDefaults.standard.set(previousPage, forKey: "lastPage") }
        let browser = BrowserModel()
        browser.open(try XCTUnwrap(URL(string: origin + "/auth-test")))
        defer { browser.webView.stopLoading() }
        for path in ["/auth/vr180-sbs.mp4", "/auth/hls/vr180-sbs/master.m3u8"] {
            let url = try XCTUnwrap(URL(string: origin + path))
            var cookies: [HTTPCookie] = []
            let cookieDeadline = Date().addingTimeInterval(15)
            while Date() < cookieDeadline, !cookies.contains(where: { $0.name == "visionstream_fixture" }) {
                cookies = await browser.cookies(for: url)
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(cookies.contains { $0.name == "visionstream_fixture" && $0.isHTTPOnly && $0.isSecure })
            let playback = PlaybackModel()
            let ready = await playback.prepare(MediaCandidate(id: path, source: url.absoluteString), cookies: cookies)
            print("Cookie fixture \(path): ready=\(ready), error=\(playback.errorMessage ?? "none")")
            XCTAssertTrue(ready, "\(path): \(playback.errorMessage ?? "unknown preparation failure")")
            guard ready else { continue }
            playback.play()
            var frame: CVPixelBuffer?
            let frameDeadline = Date().addingTimeInterval(10)
            while Date() < frameDeadline, frame == nil {
                try await Task.sleep(for: .milliseconds(50))
                frame = playback.videoOutput?.copyPixelBuffer(forItemTime: playback.player.currentTime(), itemTimeForDisplay: nil)
            }
            print("Cookie fixture \(path): decoded frame=\(frame != nil)")
            XCTAssertNotNil(frame, "\(path): \(playback.errorMessage ?? "no decoded frame")")
            playback.stop()
        }
    }

    func testAuthorisedFixtureMP4AndHLSDecode() async throws {
        guard let origin = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"], origin.hasPrefix("https://") else {
            throw XCTSkip("Set VISIONSTREAM_TEST_ORIGIN to the HTTPS host serving Fixtures/generated.")
        }
        let names = ["vr180-mono", "vr180-sbs", "vr180-tb", "vr360-mono", "vr360-sbs", "vr360-tb"]
        let paths = names.flatMap { [$0 + ".mp4", "hls/" + $0 + "/master.m3u8"] }
        for path in paths {
            let media = MediaCandidate(id: path, source: origin + "/" + path)
            let playback = PlaybackModel()
            let ready = await playback.prepare(media, cookies: [])
            print("Fixture \(path): ready=\(ready), error=\(playback.errorMessage ?? "none")")
            XCTAssertTrue(ready, "\(path): \(playback.errorMessage ?? "unknown preparation failure")")
            guard ready else { continue }
            playback.play()
            let end = Date().addingTimeInterval(10)
            var frame: CVPixelBuffer?
            while Date() < end, frame == nil {
                try await Task.sleep(for: .milliseconds(50))
                let time = playback.player.currentTime()
                frame = playback.videoOutput?.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
            }
            print("Fixture \(path): decoded frame=\(frame != nil)")
            XCTAssertNotNil(frame, "No decoded pixel buffer for \(path): \(playback.errorMessage ?? "no player error")")
            if let frame { XCTAssertGreaterThan(CVPixelBufferGetWidth(frame), 0) }
            playback.stop()
        }
    }
    func testDepthDisparityOcclusionAutomaticDetectionThroughNativeStreams() async throws {
        let origin=try fixtureOrigin()
        for (path,layout,presentation) in [("disparity-a.mp4",StereoLayout.sideBySide,VideoPresentation.vr180),("disparity-b.mp4",.topBottom,.vr360),("disparity-a/stream.m3u8",.sideBySide,.vr180)] {
            let playback=PlaybackModel(automaticallyDetectFormat:true);playback.player.isMuted=true
            defer { playback.stop() }
            let ready=await playback.prepare(.init(id:path,source:origin+"/"+path),cookies:[])
            XCTAssertTrue(ready);guard ready else { continue }
            XCTAssertEqual(playback.presentation,.screen)
            let renderer=try ImmersiveRenderer(playback:playback,controls:Entity())
            defer { renderer.stop() }
            try await renderer.start()
            try await waitUntil({ playback.layout==layout && playback.presentation==presentation },seconds:15)
            XCTAssertEqual(playback.formatStatus,"Auto · image match")
            playback.manualFormat();playback.layout = .mono;playback.enableAutomaticFormat()
            try await waitUntil({ playback.layout==layout && playback.presentation==presentation },seconds:15)
        }
    }
    func testUnlabelledStereoAndSavedCueRequireImageEvidenceBeforeAutomaticStereo() async throws {
        let origin = try fixtureOrigin()
        for context in 0...3 {
            let playback = PlaybackModel(automaticallyDetectFormat: true); playback.player.isMuted = true
            defer { playback.stop() }
            let media = MediaCandidate(id: "cue", source: origin + (context == 3 ? "/unlabelled/stream.m3u8" : "/context-sample.mp4"), pageURL: context == 1 ? "https://site.example/vr-porn-video/clip" : "",
                formatHint: context == 2 ? .init(layout: .sideBySide, evidence: .metadata) : nil)
            let ready = await playback.prepare(media, cookies: [])
            XCTAssertTrue(ready); XCTAssertEqual(playback.presentation, .screen)
            let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
            defer { renderer.stop() }
            try await renderer.start()
            try await waitUntil({ playback.decodedWidth == 1024 }, seconds: 20)
            try await waitUntil({ playback.layout == .sideBySide && playback.presentation == .vr180 }, seconds: 10)
            XCTAssertEqual(playback.presentation, .vr180); XCTAssertEqual(playback.formatStatus, "Auto · image match")
        }
        let playback = PlaybackModel(automaticallyDetectFormat: true); playback.player.isMuted = true
        defer { playback.stop() }
        let cue = VideoFormatDetection.persistentHint(source:"https://cdn.example/unknown.mp4", title:"Video", pageURL:"https://site.example/vr/test")
        let ready = await playback.prepare(.init(id:"saved-cue", source:origin + "/context-sample.mp4", formatHint:cue), cookies:[])
        XCTAssertTrue(ready); XCTAssertEqual(playback.presentation, .screen)
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop() }
        try await renderer.start()
        try await waitUntil({ playback.layout == .sideBySide }, seconds:10)
        XCTAssertEqual(playback.presentation, .vr180)
    }

    func testOptInUserSuppliedVR180StereoAutomaticDetection() async throws {
        guard ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_LOCAL_VR180_SBS"] == "1" else {
            throw XCTSkip("Explicitly supply a known local VR180/SBS sample")
        }
        let playback = PlaybackModel(automaticallyDetectFormat: true)
        playback.player.isMuted = true
        let ready = await playback.prepare(.init(id: "private-local-sample", source: try fixtureOrigin() + "/local-user-media.mp4", currentTime: 5), cookies: [])
        XCTAssertTrue(ready)
        guard ready else { return }
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop(); playback.stop() }
        try await renderer.start()
        try await waitUntil({ playback.layout == .sideBySide && playback.presentation == .vr180 }, seconds: 25)
        XCTAssertEqual(playback.formatStatus, "Auto · image match")
        playback.manualFormat(); playback.layout = .mono; playback.presentation = .screen
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(playback.layout, .mono); XCTAssertEqual(playback.presentation, .screen)
        playback.enableAutomaticFormat()
        try await waitUntil({ playback.layout == .sideBySide && playback.presentation == .vr180 }, seconds: 15)
        XCTAssertNil(playback.errorMessage)
    }

    func testPartialMetadataKeepsLabelledLayoutAndUnlabelledOrdinaryVideoStaysFlat() async throws {
        let origin = try fixtureOrigin(), playback = PlaybackModel(automaticallyDetectFormat: true)
        playback.player.isMuted = true
        defer { playback.stop() }
        // The element labels only projection; the source labels both fields.
        let ready = await playback.prepare(.init(id: "partial", source: origin + "/vr180-sbs.mp4",
            formatHint: .init(projection: .vr180, evidence: .metadata)), cookies: [])
        XCTAssertTrue(ready)
        XCTAssertEqual(playback.layout, .sideBySide); XCTAssertEqual(playback.presentation, .vr180)
        let ordinary = await playback.prepare(.init(id: "ordinary", source: origin + "/controls-demo.mp4"), cookies: [])
        XCTAssertTrue(ordinary)
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop() }
        try await renderer.start()
        try await waitUntil({ playback.decodedWidth > 0 }, seconds: 15)
        try await Task.sleep(for: .seconds(3))
        XCTAssertEqual(playback.presentation, .screen); XCTAssertEqual(playback.layout, .mono)
        // Explicit mono metadata remains authoritative over duplicated imagery.
        renderer.stop()
        let mono = await playback.prepare(.init(id: "explicit-mono", source: origin + "/context-sample.mp4",
            formatHint: .init(layout: .mono, evidence: .metadata)), cookies: [])
        XCTAssertTrue(mono)
        let monoRenderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { monoRenderer.stop() }
        try await monoRenderer.start()
        try await waitUntil({ playback.decodedWidth > 0 }, seconds: 15)
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(playback.presentation, .screen); XCTAssertEqual(playback.layout, .mono)
    }

}
