import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class HLSOfflineStoreTests: XCTestCase {
    func testPackageOwnershipAndJournalRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HLSOfflineStore(root: root.appendingPathComponent("Index"), library: root)
        let relative = "com.apple.UserManagedAssets.Test/owned.movpkg", package = try XCTUnwrap(store.url(for: relative))
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: package.appendingPathComponent("media"))
        XCTAssertEqual(store.relative(package), relative)
        XCTAssertEqual(store.relative(URL(fileURLWithPath: "/.nofollow" + package.path)), relative)
        XCTAssertNil(store.relative(URL(fileURLWithPath: "/.nofollow/tmp/unowned.movpkg")))
        let record = SavedHLSVideo(id: UUID(), name: "Test", hint: nil, state: .complete, relativePackage: relative, bytes: 3, fraction: 1)
        try store.save([record]); XCTAssertEqual(try store.load(), [record])
        XCTAssertEqual(store.package(for: record)?.path, package.path)
        XCTAssertEqual(try HLSOfflineStore.packageBytes(package), 3)
        try store.removePackage(relative: relative); XCTAssertNil(store.package(for: record))
    }
    func testUnownedLinkedAndDamagedPackagesAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HLSOfflineStore(root: root.appendingPathComponent("Index"), library: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for relative in ["../other.movpkg", "/tmp/other.movpkg", "com.apple.UserManagedAssets.Test/../other.movpkg", "Other/file.movpkg", "com.apple.UserManagedAssets.Test//file.movpkg"] { XCTAssertNil(store.url(for: relative)) }
        let owned = root.appendingPathComponent("com.apple.UserManagedAssets.Test")
        try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: root)
        XCTAssertNil(store.url(for: "com.apple.UserManagedAssets.Test/test.movpkg"))
        try store.save([])
        let journal = store.root.appendingPathComponent("jobs.json"), bytes = Data("damaged".utf8)
        try bytes.write(to: journal); XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: journal), bytes)
        try Data(repeating: 32, count: 1_000_001).write(to: journal); XCTAssertThrowsError(try store.load())
    }
}
