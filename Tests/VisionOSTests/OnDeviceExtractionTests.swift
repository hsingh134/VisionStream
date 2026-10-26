import AVFoundation
import RealityKit
import XCTest
@testable import VisionStream

@MainActor final class OnDeviceExtractionTests: XCTestCase {
    func testBundledRuntimeRejectsNonHTTPSInput() async throws {
        do {
            _ = try await OnDeviceExtractor.shared.resolve("file:///private/test.mp4")
            XCTFail("The embedded runtime accepted a local file URL")
        } catch ExtractionError.status(let status) {
            XCTAssertEqual(status, "invalid_url")
        }
    }

    func testFinderNavigationCancelsState() {
        let app = AppModel()
        app.extractor.find("invalid")
        XCTAssertNotNil(app.extractor.errorMessage)
        app.browser.onNavigation?()
        XCTAssertNil(app.extractor.errorMessage)
        XCTAssertFalse(app.extractor.isLoading)
        XCTAssertTrue(app.extractor.streams.isEmpty)
    }

    func testCancelledFinderDiscardsLateResults() async throws {
        let gate = SuspendedResolution()
        let finder = ExtractorModel(resolve: { _ in await gate.resolve() })
        finder.find("https://video.example/watch")
        await gate.waitForStart()
        XCTAssertTrue(finder.isLoading)
        finder.clear()
        try await gate.finish()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(finder.isLoading)
        XCTAssertTrue(finder.streams.isEmpty)
        XCTAssertNil(finder.errorMessage)
    }

    func testPublicExtractionToNativeRenderer() async throws {
        guard ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_PUBLIC_EXTRACTOR"] == "1" else {
            throw XCTSkip("Enable the public NASA network check explicitly")
        }
        let address = "https://svs.gsfc.nasa.gov/vis/a010000/a014500/a014576/14576_BHPlunge_360_FINAL_1080.mp4"
        let result = try await OnDeviceExtractor.shared.resolve(address)
        let stream = try XCTUnwrap(result.streams.first { $0.unavailableReason == nil })
        XCTAssertEqual(stream.candidate.mimeType, "video/mp4")
        let playback = PlaybackModel(automaticallyDetectFormat: true)
        playback.player.isMuted = true
        let ready = await playback.prepare(stream.candidate, cookies: [])
        XCTAssertTrue(ready, "The resolved public MP4 failed native readiness")
        guard ready else { playback.stop(); return }
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop(); playback.stop() }
        try await renderer.start()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && (playback.decodedWidth == 0 || playback.presentation != .vr360) {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(playback.decodedWidth, 2160)
        XCTAssertEqual(playback.decodedHeight, 1080)
        XCTAssertEqual(playback.presentation, .vr360, "Known spherical MP4 metadata must configure VR automatically")
        XCTAssertEqual(playback.layout, .mono)
        XCTAssertTrue(renderer.video.isEnabled)
        XCTAssertNil(playback.errorMessage)
        if playback.decodedWidth == 2160 && playback.presentation == .vr360 && playback.layout == .mono && renderer.video.isEnabled && playback.errorMessage == nil {
            print("PUBLIC_EXTRACTION_NATIVE_RENDER_OK: H.264 2160x1080 VR360 mono")
        }
    }

    func testHeaderAdvisoryAllowsNativeMP4AndHLSWithoutCustomHeaders() async throws {
        guard let origin = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"] else {
            throw XCTSkip("Run with the controlled HTTPS fixture server")
        }
        for (path, mime, adaptive) in [("/vr360-mono.mp4", "video/mp4", false),
                                       ("/hls/vr360-mono/master.m3u8", "application/vnd.apple.mpegurl", false),
                                       ("/adaptive-test/master.m3u8", "application/vnd.apple.mpegurl", true)] {
            let data = try JSONSerialization.data(withJSONObject: ["status": "ok", "streams": [[
                "source": origin + "/header-free" + path, "mimeType": mime,
                "width": adaptive ? 0 : 1024, "height": adaptive ? 0 : 512,
                "unavailableReason": "", "advisory": "request_context", "adaptive": adaptive
            ]]])
            let stream = try XCTUnwrap(ExtractedMedia.parse(data).streams.first)
            XCTAssertNil(stream.unavailableReason)
            XCTAssertNotNil(stream.advisory)
            XCTAssertEqual(stream.isAdaptive, adaptive)
            let playback = PlaybackModel()
            playback.player.isMuted = true
            playback.presentation = .vr360; playback.layout = .mono
            let ready = await playback.prepare(stream.candidate, cookies: [])
            XCTAssertTrue(ready, "The header-free fixture failed native readiness")
            guard ready else { playback.stop(); continue }
            let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
            defer { renderer.stop(); playback.stop() }
            try await renderer.start()
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline && playback.decodedWidth == 0 {
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(playback.decodedWidth, 1024)
            XCTAssertEqual(playback.decodedHeight, 512)
            XCTAssertTrue(renderer.video.isEnabled)
            XCTAssertNil(playback.errorMessage)
            print("HEADER_ADVISORY_NATIVE_RENDER_OK: \(mime), adaptive=\(adaptive), no custom headers or cookies")
        }
    }
    func testMissingMP4DimensionsAreMeasuredAndHighestCompleteSourceComesFirst() async throws {
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"])
        let payload: [String: Any] = ["status": "ok", "streams": ["dimensions-low.mp4", "dimensions-route.mp4"].map {
            ["source": origin + "/" + $0, "mimeType": "video/mp4", "width": 0, "height": 0, "unavailableReason": ""] as [String: Any]
        }]
        let found = try ExtractedMedia.parse(JSONSerialization.data(withJSONObject: payload))
        let result = try await NativeStreamInspector.refine(found)
        XCTAssertEqual(result.streams[0].candidate.width, 2048)
        XCTAssertEqual(result.streams[0].candidate.height, 512)
        XCTAssertEqual(result.streams[1].candidate.width, 512)
        XCTAssertEqual(result.streams[1].candidate.height, 512)
        XCTAssertEqual(result.streams[0].candidate.source, origin + "/dimensions-route.mp4")
    }

    func testPublicLocationUsesHeaderOnlyGETAndPreservesPublishedDestination() async throws {
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"])
        let url = try XCTUnwrap(URL(string: origin + "/dimensions-route.mp4"))
        let result = try await PublicMediaLocation().load(url)
        XCTAssertEqual(result.absoluteString, "https://localhost:" + String(try XCTUnwrap(URL(string: origin)?.port)) + "/dimensions-high.mp4?fixture=published%2Buri")
    }

    func testInspectionIdentityMatchesTheActualBrowser() async throws {
        let browser = BrowserModel()
        let browserAgent = await browser.playbackUserAgent()
        let inspectionAgent = await NativeStreamInspector.browserUserAgent()
        XCTAssertNotNil(browserAgent); XCTAssertEqual(browserAgent, inspectionAgent)
    }

}

private actor SuspendedResolution {
    private var continuation: CheckedContinuation<ExtractedMedia, Never>?
    func resolve() async -> ExtractedMedia {
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForStart() async {
        while continuation == nil { await Task.yield() }
    }
    func finish() throws {
        let data = Data(#"{"status":"ok","streams":[{"source":"https://media.example/test.mp4","mimeType":"video/mp4","width":512,"height":512,"unavailableReason":""}]}"#.utf8)
        continuation?.resume(returning: try ExtractedMedia.parse(data))
        continuation = nil
    }
}
