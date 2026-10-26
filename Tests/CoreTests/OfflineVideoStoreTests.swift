import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class OfflineVideoStoreTests: XCTestCase {
    func testRecoveryRestoresOrphansAndCorruptIndexWithoutChangingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineVideoStore(root: root); try store.prepare()
        let id = UUID(), data = Data([1,2,3,4]), file = root.appendingPathComponent(id.uuidString + ".mp4")
        try data.write(to: file)
        try Data("broken".utf8).write(to: root.appendingPathComponent("catalogue.json"))
        try Data([1]).write(to: root.appendingPathComponent("other.mp4"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(UUID().uuidString + ".mp4"), withDestinationURL: file)
        let recovered = try store.recover()
        XCTAssertEqual(recovered.count, 1); XCTAssertEqual(recovered.first?.id, id)
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual(try store.load(), recovered)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("catalogue.previous.json")), Data("broken".utf8))
        let hasOrphans = try store.hasUnlistedFiles(in: recovered); XCTAssertFalse(hasOrphans)
    }
    func testRecoveryPreservesHealthyNamesAndRecognizesUnlistedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineVideoStore(root: root); try store.prepare()
        let input = root.appendingPathComponent("input"); try Data([1]).write(to: input)
        let first = try store.commit(staging: input, id: UUID(), name: "Keep this name", hint: .init(projection: .vr180, layout: .sideBySide, evidence: .metadata))
        let before = try store.hasUnlistedFiles(in: [first]); XCTAssertFalse(before)
        try Data([2]).write(to: root.appendingPathComponent(UUID().uuidString + ".mp4"))
        let after = try store.hasUnlistedFiles(in: [first]); XCTAssertTrue(after)
        let recovered = try store.recover()
        XCTAssertEqual(recovered.count, 2)
        XCTAssertTrue(recovered.contains(first))
    }
    func testSaveReloadAndRemoveWithoutRetainingRemoteAddress() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineVideoStore(root: root)
        try store.prepare()
        let staging = root.appendingPathComponent("partial")
        try Data(repeating: 1, count: 128).write(to: staging)
        let hint = VideoFormatHint(projection: .vr180, layout: .sideBySide, evidence: .metadata)
        let saved = try store.commit(staging: staging, id: UUID(), name: "https://private.example/video?token=secret", hint: hint)
        XCTAssertEqual(saved.name, "Saved video")
        XCTAssertEqual(saved.bytes, 128)
        XCTAssertEqual(try store.load(), [saved])
        XCTAssertEqual(saved.formatHint, hint)
        XCTAssertNotNil(store.file(for: saved))
        let json = try String(contentsOf: root.appendingPathComponent("catalogue.json"), encoding: .utf8)
        XCTAssertFalse(json.contains("secret")); XCTAssertFalse(json.contains("private.example"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        try store.remove(saved)
        XCTAssertEqual(try store.load(), [])
        XCTAssertNil(store.file(for: saved))
    }
    func testMissingChangedAndSymlinkFilesCannotBeOpened() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineVideoStore(root: root); try store.prepare()
        let staging = root.appendingPathComponent("partial")
        try Data([1,2,3]).write(to: staging)
        let saved = try store.commit(staging: staging, id: UUID(), name: "Test", hint: nil)
        let file = try XCTUnwrap(store.file(for: saved))
        try Data([1]).write(to: file)
        XCTAssertNil(store.file(for: saved)); XCTAssertEqual(try store.load(), [])
        try FileManager.default.removeItem(at: file)
        try Data([1,2,3]).write(to: staging)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: staging)
        XCTAssertNil(store.file(for: saved))
    }
    func testCorruptCatalogueIsNotSilentlyOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineVideoStore(root: root); try store.prepare()
        let catalogue = root.appendingPathComponent("catalogue.json"), original = Data("corrupt".utf8)
        try original.write(to: catalogue)
        XCTAssertThrowsError(try store.load())
        let staging = root.appendingPathComponent("partial"); try Data([1]).write(to: staging)
        XCTAssertThrowsError(try store.commit(staging: staging, id: UUID(), name: "Test", hint: nil))
        XCTAssertEqual(try Data(contentsOf: catalogue), original)
    }
    func testOversizedAndLinkedCatalogueAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineVideoStore(root: root); try store.prepare()
        let catalogue = root.appendingPathComponent("catalogue.json")
        try Data(repeating: 32, count: 2_000_001).write(to: catalogue)
        XCTAssertThrowsError(try store.load())
        try FileManager.default.removeItem(at: catalogue)
        let other = root.appendingPathComponent("other.json"); try Data("[]".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: catalogue, withDestinationURL: other)
        XCTAssertThrowsError(try store.load())
    }
}
