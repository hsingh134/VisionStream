import AVFoundation
import RealityKit
import XCTest
@testable import VisionStream

@MainActor final class HLSOfflineLibraryTests: XCTestCase {
    private func wait(seconds: Double = 60, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() { guard Date() < end else { throw URLError(.timedOut) }; try await Task.sleep(for: .milliseconds(50)) }
    }
    func testPublicAppleDownloadPauseResumeReloadAndOfflineRenderer() async throws {
        guard ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_HLS_PUBLIC_PROBE"] == "1" else { throw XCTSkip("Opt into the fixed public Apple HLS download acceptance test") }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let root = library.appendingPathComponent("Application Support/HLSAcceptance-" + UUID().uuidString)
        let store = HLSOfflineStore(root: root, library: library)
        let model = HLSOfflineLibrary(store: store, identifier: "personal.visionstream.hls-acceptance." + UUID().uuidString)
        let diagnostics=SessionDiagnostics(root:root.appendingPathComponent("diagnostics"))
        model.diagnostics=diagnostics
        model.testLowBitrate = true
        let browserAgent=await NativeStreamInspector.browserUserAgent()
        XCTAssertNotNil(browserAgent,"The public HLS compatibility check must use the real WebKit identifier")
        defer { model.stopTestSession(); for video in model.videos { try? store.removePackage(relative: video.relativePackage) }; try? FileManager.default.removeItem(at: root) }
        let media = MediaCandidate(id: "public-apple-hls", source: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8", mimeType: "application/vnd.apple.mpegurl", title: "Apple developer HLS sample")
        model.start(media, cookies: [], userAgent: browserAgent)
        try await wait { model.videos.first?.state != .preparing }
        let id = try XCTUnwrap(model.videos.first?.id)
        XCTAssertEqual(model.videos.first?.state, .saving)
        model.pause(id); XCTAssertEqual(model.videos.first?.state, .paused)
        try await Task.sleep(for: .milliseconds(200))
        model.resume(id)
        try await wait { !model.active }
        XCTAssertNil(model.message, model.failureCode ?? "No system error code")
        let saved = try XCTUnwrap(model.saved.first)
        XCTAssertGreaterThan(saved.bytes, 0)
        let reloaded = try store.load(); XCTAssertEqual(reloaded, model.videos)
        let journal = try String(contentsOf: root.appendingPathComponent("jobs.json"), encoding: .utf8)
        XCTAssertFalse(journal.contains("https:")); XCTAssertFalse(journal.contains("cookie"))
        let playback = PlaybackModel(), renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        playback.player.isMuted = true
        defer { renderer.stop(); playback.stop() }
        let ready = await playback.prepareSavedHLS(try XCTUnwrap(reloaded.first), store: store)
        XCTAssertTrue(ready); guard ready else { return }
        try await renderer.start(); try await wait(seconds: 20) { playback.decodedWidth > 0 }
        XCTAssertEqual(playback.qualityStatus, "Saved video")
        model.remove(saved); XCTAssertTrue(model.videos.isEmpty); XCTAssertNil(store.package(for: saved))
        model.start(media, cookies: [], userAgent: browserAgent)
        try await wait { model.videos.first?.state != .preparing }
        let cancelling = try XCTUnwrap(model.videos.first)
        XCTAssertEqual(cancelling.state, .saving)
        model.cancel(cancelling.id); try await wait(seconds: 15) { !model.active }
        let cancelled = try XCTUnwrap(model.videos.first)
        XCTAssertEqual(cancelled.state, .failed)
        if let relative = cancelled.relativePackage, let url = store.url(for: relative) { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        model.remove(cancelled); XCTAssertTrue(model.videos.isEmpty)
        let report=diagnostics.report(snapshot:"{}")
        XCTAssertTrue(report.contains("system-task-completed"))
        XCTAssertTrue(report.contains("offline-system-selected"))
        XCTAssertTrue(report.contains("backgroundUserAgentApplied"))
        XCTAssertFalse(report.contains("devstreaming-cdn.apple.com/videos"))
        XCTAssertTrue(diagnostics.storageFailureCodes.isEmpty)
    }
    func testInterruptedPreparationAndInvalidSourcesDoNotStickActive() throws {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let root = library.appendingPathComponent("Application Support/HLSAcceptance-" + UUID().uuidString), store = HLSOfflineStore(root: root, library: library)
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save([.init(id: UUID(), name: "Interrupted", hint: nil, state: .preparing)])
        let model = HLSOfflineLibrary(store: store, identifier: "personal.visionstream.hls-acceptance." + UUID().uuidString)
        defer { model.stopTestSession() }
        XCTAssertFalse(model.active); XCTAssertEqual(model.videos.first?.state, .failed)
        model.start(MediaCandidate(id: "invalid", source: "file:///private/video.m3u8"), cookies: [], userAgent: nil)
        XCTAssertFalse(model.active); XCTAssertNotNil(model.message)
    }
    func testDownloadDelegateFailurePersistsOnlySanitizedCodes() throws {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let root = library.appendingPathComponent("Application Support/HLSFailure-" + UUID().uuidString)
        let store = HLSOfflineStore(root: root, library: library), id = UUID()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save([.init(id: id, name: "Fixture", hint: nil, state: .saving)])
        let model = HLSOfflineLibrary(store: store, identifier: "personal.visionstream.hls-failure." + UUID().uuidString)
        defer { model.stopTestSession() }
        // Exercise an active restored task through the actual delegate without
        // making a network request; terminal tasks ignore duplicate callbacks.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://fixture.invalid/video.m3u8")!)
        task.taskDescription = id.uuidString
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE_SIGNED_LINK",
                       NSUnderlyingErrorKey: NSError(domain: "PRIVATE_DOMAIN", code: 7)])
        model.urlSession(session, task: task, didCompleteWithError: error)
        XCTAssertEqual(model.diagnosticFailureCodes, ["NSURLErrorDomain:-1200", "OtherErrorDomain:7"])
        XCTAssertTrue(model.message?.contains("secure connection") == true)
        let reloaded = HLSOfflineLibrary(store: store, identifier: "personal.visionstream.hls-failure." + UUID().uuidString)
        defer { reloaded.stopTestSession() }
        XCTAssertEqual(reloaded.diagnosticFailureCodes, model.diagnosticFailureCodes)
        let journal = try String(contentsOf: root.appendingPathComponent("jobs.json"), encoding: .utf8)
        XCTAssertFalse(journal.contains("PRIVATE_")); XCTAssertFalse(journal.contains("https:"))
    }
}
