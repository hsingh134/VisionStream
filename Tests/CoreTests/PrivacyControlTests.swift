import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

@MainActor final class PrivacyControlTests:XCTestCase {
    func testDisabledRecordingCreatesNoHistoryAndExplicitSnapshotRemainsAvailable() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root,enabled:false)
        let context=history.begin(.navigation,page:URL(string:"https://private.example/secret?id=private")!)
        history.record(.navigation,context:context,labels:["phase":"test"])
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path));XCTAssertEqual(history.eventCount,0)
        let object=try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(history.report(snapshot:"{\"currentTechnicalState\":true}").utf8)) as? [String:Any])
        XCTAssertEqual(object["diagnosticsRecordingEnabled"] as? Bool,false)
        XCTAssertEqual((object["sessionHistory"] as? [Any])?.count,0)
        XCTAssertEqual(object["currentTechnicalState"] as? Bool,true)
        XCTAssertTrue(history.storageFailureCodes.isEmpty)
    }
    func testOptOutStopsWritesAndOptInDisclosesRecordingBoundaries() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root,enabled:false)
        history.setEnabled(true);history.record(.controls,labels:["action":"captured"])
        history.setEnabled(false)
        let file=root.appendingPathComponent(history.sessionID.uuidString+".jsonl"),before=try Data(contentsOf:file)
        history.record(.controls,labels:["action":"must-not-exist"])
        let after=try Data(contentsOf:file);XCTAssertEqual(after,before)
        history.setEnabled(true)
        let report=history.report(snapshot:"{}")
        XCTAssertTrue(report.contains("diagnostics-disabled"));XCTAssertTrue(report.contains("diagnostics-enabled"))
        XCTAssertFalse(report.contains("must-not-exist"));XCTAssertTrue(report.contains("Actions while disabled are not recorded"))
    }
    func testDeleteRemovesAllOwnedSessionsMarkersAndResetsIdentifiersWithoutFollowingLinks() throws {
        let base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),root=base.appendingPathComponent("history")
        defer { try? FileManager.default.removeItem(at:base) }
        let old=SessionDiagnostics(root:root);old.record(.controls,labels:["action":"old-record"])
        let history=SessionDiagnostics(root:root),identity=history.reference("private-source"),session=history.sessionID
        let marker=root.appendingPathComponent(UUID().uuidString+".coverage.json")
        try Data("owned-gap".utf8).write(to:marker)
        let outside=base.appendingPathComponent("keep.txt");try Data("keep".utf8).write(to:outside)
        let neighbour=root.appendingPathComponent("settings.json");try Data("keep".utf8).write(to:neighbour)
        let link=root.appendingPathComponent(UUID().uuidString+".jsonl")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:outside)
        try history.deleteHistory()
        XCTAssertFalse(history.isEnabled);XCTAssertEqual(history.eventCount,0);XCTAssertEqual(history.persistedEventCount,0)
        XCTAssertNotEqual(history.sessionID,session);XCTAssertNotEqual(history.reference("private-source"),identity)
        let outsideContents=try String(contentsOf:outside,encoding:.utf8);XCTAssertEqual(outsideContents,"keep")
        let names=try FileManager.default.contentsOfDirectory(atPath:root.path);XCTAssertEqual(names,["settings.json"])
        XCTAssertFalse(history.report(snapshot:"{}").contains("old-record"))
        history.setEnabled(true);XCTAssertEqual(history.eventCount,1)
    }
    func testExportDeletionOnlyRemovesOwnedUUIDFilesAndKeepsExternalTargets() throws {
        let base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),root=base.appendingPathComponent("reports")
        defer { try? FileManager.default.removeItem(at:base) }
        let first=try DiagnosticReportFiles.write("first",at:root)
        let second=try DiagnosticReportFiles.write("second",at:root)
        XCTAssertFalse(FileManager.default.fileExists(atPath:first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:second.path))
        let outside=base.appendingPathComponent("outside.txt");try Data("keep".utf8).write(to:outside)
        let link=root.appendingPathComponent(UUID().uuidString+".json")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:outside)
        let neighbour=root.appendingPathComponent("keep.json");try Data("keep".utf8).write(to:neighbour)
        try DiagnosticReportFiles.clear(at:root)
        let names=try FileManager.default.contentsOfDirectory(atPath:root.path);XCTAssertEqual(names,["keep.json"])
        let outsideContents=try String(contentsOf:outside,encoding:.utf8);XCTAssertEqual(outsideContents,"keep")
    }
    func testClearingCatalogueLinksKeepsVideoBytesAndRemovesOldDiagnosticBackup() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=OfflineVideoStore(root:root);try store.prepare()
        let staging=root.appendingPathComponent("stage.mp4"),bytes=Data("original owned video".utf8)
        try bytes.write(to:staging)
        let history=SessionDiagnostics(root:root.appendingPathComponent("history"))
        let saved=try store.commit(staging:staging,id:UUID(),name:"Video",hint:nil,context:history.begin(.mp4Download,page:URL(string:"https://private.example/watch")!))
        let previous=root.appendingPathComponent("catalogue.previous.json")
        try FileManager.default.copyItem(at:root.appendingPathComponent("catalogue.json"),to:previous)
        let records=try store.clearDiagnosticLinks()
        XCTAssertEqual(records.count,1);XCTAssertNil(records[0].diagnosticContext)
        let savedBytes=try Data(contentsOf:try XCTUnwrap(store.file(for:saved)));XCTAssertEqual(savedBytes,bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath:previous.path))
        let catalogue=try String(contentsOf:root.appendingPathComponent("catalogue.json"),encoding:.utf8);XCTAssertFalse(catalogue.contains("private.example"))
    }
}
