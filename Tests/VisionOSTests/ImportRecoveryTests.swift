import AVFoundation
import RealityKit
import XCTest
@testable import VisionStream

@MainActor final class ImportRecoveryTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(20)
        while !condition() { guard Date() < end else { XCTFail("Local video operation did not finish"); throw URLError(.timedOut) }; try await Task.sleep(for: .milliseconds(50)) }
    }
    func testImportKeepsOriginalAndRecoveredVideoCanDecode() async throws {
        let raw = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"]), base = try XCTUnwrap(URL(string: raw))
        guard base.scheme == "https", ["localhost", "127.0.0.1"].contains(base.host), base.port != nil else { throw URLError(.badURL) }
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("vr180-sbs.mp4"))
        let original = parent.appendingPathComponent("User VR180 SBS.mp4"), root = parent.appendingPathComponent("Library")
        try data.write(to: original)
        let model = DownloadModel(root: root)
        model.importVideo(original); try await wait { !model.isDownloading }
        XCTAssertNil(model.message); XCTAssertEqual(model.videos.count, 1)
        XCTAssertEqual(try Data(contentsOf: original), data)
        XCTAssertEqual(model.videos.first?.formatHint?.layout, .sideBySide)
        try Data("damaged index".utf8).write(to: root.appendingPathComponent("catalogue.json"))
        let recovered = DownloadModel(root: root)
        XCTAssertTrue(recovered.needsRepair)
        recovered.repair(); XCTAssertFalse(recovered.needsRepair); XCTAssertEqual(recovered.videos.count, 1)
        let saved = try XCTUnwrap(recovered.videos.first), playback = PlaybackModel()
        playback.player.isMuted = true
        defer { playback.stop() }
        let ready = await playback.prepareSavedVideo(saved, store: recovered.store)
        XCTAssertTrue(ready)
        guard ready else { return }
        let renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        defer { renderer.stop() }
        try await renderer.start(); try await wait { playback.decodedWidth > 0 }
        XCTAssertEqual(try Data(contentsOf: original), data)
    }
    func testCancelledLargeImportRemovesCopyAndKeepsOriginal() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let original = parent.appendingPathComponent("large.mp4")
        try Data([0,0,0,24,102,116,121,112,105,115,111,109]).write(to: original)
        let handle = try FileHandle(forWritingTo: original); try handle.truncate(atOffset: 512 * 1024 * 1024); try handle.close()
        let root = parent.appendingPathComponent("Library"), model = DownloadModel(root: root)
        model.importVideo(original)
        try await wait { model.received > 0 }
        model.cancel()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(model.videos.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Staging").path), [])
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: original.path)[.size] as? NSNumber)?.int64Value, 512 * 1024 * 1024)
    }
    func testImportRejectsNetworkAddressAndInvalidFileWithoutLosingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DownloadModel(root: root)
        model.importVideo(URL(string: "https://example.invalid/video.mp4")!)
        XCTAssertFalse(model.isDownloading); XCTAssertNotNil(model.message)
        let original = root.appendingPathComponent("invalid.mp4"), bytes = Data("not a movie".utf8)
        try bytes.write(to: original)
        model.importVideo(original); try await wait { !model.isDownloading }
        XCTAssertTrue(model.videos.isEmpty); XCTAssertNotNil(model.message)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }
}
