import AVFoundation
import RealityKit
import XCTest
@testable import VisionStream

@MainActor final class DownloadNativeTests: XCTestCase {
    func testPublicNASADownloadReopensOfflineWithSphericalMetadata() async throws {
        guard ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_PUBLIC_EXTRACTOR"] == "1" else {
            throw XCTSkip("Enable the fixed public NASA network check explicitly")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let model = DownloadModel(root: root)
        defer { model.cancel(); try? FileManager.default.removeItem(at: root) }
        let address = "https://svs.gsfc.nasa.gov/vis/a010000/a014500/a014576/14576_BHPlunge_360_FINAL_1080.mp4"
        model.start(.init(id: "public-nasa", source: address, title: "NASA public calibration sample"), cookies: [], userAgent: nil)
        try await wait({ !model.isDownloading }, seconds: 90)
        XCTAssertNil(model.message, model.failureCode)
        let saved = try XCTUnwrap(model.videos.first)
        let playback = PlaybackModel(automaticallyDetectFormat: true); playback.player.isMuted = true
        defer { playback.stop() }
        let ready = await playback.prepareSavedVideo(saved, store: model.store)
        XCTAssertTrue(ready)
        guard ready else { return }
        XCTAssertTrue((playback.player.currentItem?.asset as? AVURLAsset)?.url.isFileURL == true)
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop() }
        try await renderer.start()
        try await wait { playback.decodedWidth == 2160 && playback.decodedHeight == 1080 }
        XCTAssertEqual(playback.presentation, .vr360); XCTAssertEqual(playback.layout, .mono)
    }
    private func origin() throws -> URL {
        let url = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        guard url.scheme == "https", ["localhost", "127.0.0.1"].contains(url.host), url.port != nil else { throw URLError(.badURL) }
        return url
    }
    private func wait(_ condition: () -> Bool, seconds: Double = 20) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() { guard Date() < end else { XCTFail("Timed out waiting for download state"); throw URLError(.timedOut) }; try await Task.sleep(for: .milliseconds(50)) }
    }
    func testDownloadReloadOfflineRenderSeekAndDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try origin().appendingPathComponent("vr180-sbs.mp4")
        let model = DownloadModel(root: root)
        model.start(.init(id: "test", source: url.absoluteString, title: "VR180 SBS calibration"), cookies: [], userAgent: nil)
        try await wait { !model.isDownloading }
        XCTAssertNil(model.message, model.failureCode)
        let saved = try XCTUnwrap(model.videos.first)
        let reloaded = DownloadModel(root: root)
        XCTAssertEqual(reloaded.videos, [saved])
        let playback = PlaybackModel(automaticallyDetectFormat: true)
        playback.player.isMuted = true
        defer { playback.stop() }
        let ready = await playback.prepareSavedVideo(saved, store: reloaded.store)
        XCTAssertTrue(ready)
        guard ready else { return }
        XCTAssertTrue(playback.player.currentItem?.asset is AVURLAsset)
        XCTAssertTrue((playback.player.currentItem?.asset as? AVURLAsset)?.url.isFileURL == true)
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop() }
        try await renderer.start()
        try await wait { playback.decodedWidth > 0 }
        XCTAssertEqual(playback.presentation, .vr180); XCTAssertEqual(playback.layout, .sideBySide)
        playback.pause(); playback.seek(to: 1)
        try await wait { !playback.isSeeking }
        XCTAssertEqual(playback.player.currentTime().seconds, 1, accuracy: 0.2)
        playback.changeQuality(.adaptive)
        XCTAssertTrue(playback.isReady) // Offline files do not reopen a remote source.
        playback.stop(); renderer.stop()
        reloaded.remove(saved)
        XCTAssertTrue(reloaded.videos.isEmpty); XCTAssertNil(reloaded.store.file(for: saved))
    }
    func testDownloadRejectsHLSBeforeStartingAndCancelsWithoutSavedFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DownloadModel(root: root), base = try origin()
        model.start(.init(id: "hls", source: base.appendingPathComponent("hls/vr180-sbs/master.m3u8").absoluteString), cookies: [], userAgent: nil)
        XCTAssertFalse(model.isDownloading); XCTAssertNotNil(model.message)
        model.start(.init(id: "cancel", source: base.appendingPathComponent("controls-demo.mp4").absoluteString), cookies: [], userAgent: nil)
        model.cancel()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(model.isDownloading); XCTAssertTrue(model.videos.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Staging").path), [])
    }
    func testDownloadRejectsHTMLMissingAndOversizedResponses() async throws {
        let base = try origin()
        for (path, cap) in [("automation-mp4", Int64(1_000_000)), ("missing.mp4", 1_000_000), ("controls-demo.mp4", 1024)] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            let transfer = MP4DownloadTransfer(staging: file, origin: base, maximumBytes: cap, reserveBytes: 0) { _,_ in }
            do { _ = try await transfer.run(URLRequest(url: base.appendingPathComponent(path)), cookies: []); XCTFail("Invalid response accepted") }
            catch { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)) }
        }
    }
    func testDownloadPreservesLegitimatelyScopedCookieAndAgent() async throws {
        let base = try origin()
        let browser = BrowserModel()
        browser.open(base.appendingPathComponent("auth-test"))
        try await wait { !browser.isLoading && browser.pageHTTPStatus == 200 }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = base.appendingPathComponent("auth/vr180-sbs.mp4"), model = DownloadModel(root: root)
        model.start(.init(id: "auth", source: url.absoluteString), cookies: await browser.cookies(for: url), userAgent: await browser.playbackUserAgent())
        try await wait { !model.isDownloading }
        XCTAssertNil(model.message, model.failureCode); XCTAssertEqual(model.videos.count, 1)
    }
    func testActiveDownloadCancellationRemovesPartialFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DownloadModel(root: root)
        model.start(.init(id: "slow", source: try origin().appendingPathComponent("download-slow.mp4").absoluteString), cookies: [], userAgent: nil)
        try await wait { model.received > 0 }
        model.cancel()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(model.videos.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Staging").path), [])
    }
    func testDownloadStorageReserveAndOriginRedirectBoundaries() async throws {
        let base = try origin()
        for (path, reserve, expectedSuccess) in [("download-redirect.mp4", Int64(0), true), ("download-foreign.mp4", 0, true), ("download-insecure.mp4", 0, false), ("vr180-sbs.mp4", Int64.max, false)] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            let transfer = MP4DownloadTransfer(staging: file, origin: base, reserveBytes: reserve) { _,_ in }
            do {
                _ = try await transfer.run(URLRequest(url: base.appendingPathComponent(path)), cookies: [])
                XCTAssertTrue(expectedSuccess); XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            } catch { XCTAssertFalse(expectedSuccess); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)) }
        }
    }
    func testClearWebsiteDataRemovesCookies() async throws {
        let browser = BrowserModel(), base = try origin(), url = base.appendingPathComponent("auth/vr180-sbs.mp4")
        browser.open(base.appendingPathComponent("auth-test"))
        try await wait { !browser.isLoading && browser.pageHTTPStatus == 200 }
        let before = await browser.cookies(for: url)
        XCTAssertTrue(before.contains { $0.name == "visionstream_fixture" })
        await browser.clearWebsiteData()
        let after = await browser.cookies(for: url)
        XCTAssertFalse(after.contains { $0.name == "visionstream_fixture" })
    }
    func testDownloadReportsMissingHTMLInvalidFileAndInsecureRedirectSeparately() async throws {
        let base = try origin()
        for (path, code) in [("missing.mp4", "http-404"), ("automation-mp4", "unsupported-response"), ("download-insecure.mp4", "redirect-unsupported"), ("download-invalid-mp4.mp4", "unsupported-mp4")] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
            defer { try? FileManager.default.removeItem(at: root) }
            let model = DownloadModel(root: root)
            model.start(.init(id: "response", source: base.appendingPathComponent(path).absoluteString, mimeType: "video/mp4"), cookies: [], userAgent: nil)
            try await wait { !model.isDownloading }
            XCTAssertTrue(model.videos.isEmpty)
            XCTAssertEqual(model.failureCode, code)
            XCTAssertNotNil(model.message)
        }
    }

    func testPublicCDNRedirectStripsWebsiteCredentialsAndHeaders() async throws {
        let base = try origin()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var request = URLRequest(url: base.appendingPathComponent("download-public-redirect.mp4"))
        for name in ["Cookie", "Authorization", "Origin", "Referer", "X-Private-Test"] { request.setValue("private-fixture-value", forHTTPHeaderField: name) }
        request.setValue("VisionStream-public-redirect-test", forHTTPHeaderField: "User-Agent")
        let transfer = MP4DownloadTransfer(staging: file, origin: base, reserveBytes: 0) { _,_ in }
        _ = try await transfer.run(request, cookies: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

}
