import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

@MainActor final class SessionDiagnosticsTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("SessionDiagnostics-"+UUID().uuidString) }
    private func object(_ history: SessionDiagnostics) throws -> [String:Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(history.report(snapshot:"{}").utf8)) as? [String:Any])
    }
    func testAttemptsCorrelateWithoutPersistingPrivateURLs() async throws {
        let root=directory(); defer { try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root)
        let media=MediaCandidate(id:"private",source:"https://user:PRIVATE_PASSWORD@cdn.example/private-title.mp4?signature=PRIVATE_SIGNATURE",title:"PRIVATE_TITLE",pageURL:"https://site.example/watch?id=PRIVATE_VIDEO")
        let playback=history.begin(.playback,media:media)
        let download=history.begin(.hlsDownload,media:media)
        let retry=history.begin(.playback,media:media)
        XCTAssertEqual(playback.mediaID,download.mediaID); XCTAssertEqual(playback.pageID,download.pageID)
        XCTAssertNotEqual(playback.attemptID,download.attemptID); XCTAssertEqual(retry.previousAttemptID,playback.attemptID)
        XCTAssertEqual(history.reference(media.pageURL+"#player",page:true),playback.pageID)
        let text=history.report(snapshot:"{}")
        XCTAssertTrue(text.contains("cdn.example")); XCTAssertFalse(text.contains("PRIVATE_")); XCTAssertFalse(text.contains("private-title")); XCTAssertFalse(text.contains("https://"))
        let log=try String(contentsOf:root.appendingPathComponent(history.sessionID.uuidString+".jsonl"),encoding:.utf8)
        XCTAssertFalse(log.contains("PRIVATE_")); XCTAssertFalse(log.contains("private-title"))
        let other=SessionDiagnostics(root:directory()); defer { try? FileManager.default.removeItem(at:other.root) }
        XCTAssertNotEqual(other.reference(media.source),playback.mediaID)
    }
    func testRetainedSessionsRecoverHistoryAndMarkTornRecords() async throws {
        let root=directory(); defer { try? FileManager.default.removeItem(at:root) }
        let old=SessionDiagnostics(root:root)
        let context=old.begin(.playback,media:.init(id:"fixture",source:"https://cdn.example/clip.mp4"))
        old.record(.playerError,context:context,codes:["CoreMediaErrorDomain:-12938"])
        let file=root.appendingPathComponent(old.sessionID.uuidString+".jsonl")
        let handle=try FileHandle(forWritingTo:file); try handle.seekToEnd(); try handle.write(contentsOf:Data("{torn".utf8)); try handle.close()
        let current=SessionDiagnostics(root:root)
        let sessions=try XCTUnwrap(try object(current)["sessionHistory"] as? [[String:Any]])
        let previous=try XCTUnwrap(sessions.first { $0["sessionID"] as? String == old.sessionID.uuidString })
        XCTAssertEqual(previous["complete"] as? Bool,false); XCTAssertEqual(previous["invalidRecords"] as? Int,1)
        XCTAssertTrue(current.report(snapshot:"{}").contains("CoreMediaErrorDomain:-12938"))
        XCTAssertEqual(sessions.count,2)
    }
    func testRedactionAlsoAppliesToUntrustedRestoredEvents() async throws {
        let root=directory(); defer { try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root)
        history.record(.transfer,labels:["phase":"https://SECRET.example/secret?token=1","Cookie":"SECRET_COOKIE","mimeType":"SECRET_MIME"],numbers:["elapsed":Double.nan,"Authorization":12],codes:["HTTP:403","PRIVATE_DOMAIN:7","https://SECRET.example/"])
        var event=try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(try String(contentsOf:root.appendingPathComponent(history.sessionID.uuidString+".jsonl"),encoding:.utf8).split(separator:"\n").last!.utf8)) as? [String:Any])
        event["labels"]=["phase":"https://SECRET.example/","Authorization":"SECRET"]
        let handle=try FileHandle(forWritingTo:root.appendingPathComponent(history.sessionID.uuidString+".jsonl")); try handle.seekToEnd(); try handle.write(contentsOf:try JSONSerialization.data(withJSONObject:event)); try handle.write(contentsOf:Data([10])); try handle.close()
        let text=history.report(snapshot:"{}")
        XCTAssertFalse(text.contains("SECRET")); XCTAssertFalse(text.contains("PRIVATE_DOMAIN")); XCTAssertFalse(text.contains("Authorization"))
    }
    func testCoverageMakesStorageLimitsAndFailuresExplicit() async throws {
        let root=directory(); defer { try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root,maximumSessionBytes:512)
        for n in 0..<300 { history.record(.controls,labels:["action":"seek"],numbers:["target":Double(n)]) }
        let report=try object(history)
        let coverage=try XCTUnwrap(report["sessionHistoryCoverage"] as? [String:Any])
        XCTAssertEqual(coverage["currentEventCount"] as? Int,301)
        XCTAssertFalse(history.storageFailureCodes.isEmpty)
        let sessions=try XCTUnwrap(report["sessionHistory"] as? [[String:Any]])
        XCTAssertEqual(sessions.first?["complete"] as? Bool,false)
        XCTAssertGreaterThan(sessions.first?["missingEvents"] as? Int ?? 0,0)
        let reopened=SessionDiagnostics(root:root)
        let retained=try XCTUnwrap(try object(reopened)["sessionHistory"] as? [[String:Any]])
        let incomplete=try XCTUnwrap(retained.first { $0["sessionID"] as? String == history.sessionID.uuidString })
        XCTAssertEqual(incomplete["complete"] as? Bool,false)
        XCTAssertGreaterThan(incomplete["missingEvents"] as? Int ?? 0,0)
        XCTAssertEqual(incomplete["missingEventCountIsExact"] as? Bool,false)
        XCTAssertFalse((incomplete["storageFailureCodes"] as? [String] ?? []).isEmpty)
        let blocked=directory(); try Data([1]).write(to:blocked); defer { try? FileManager.default.removeItem(at:blocked) }
        let failed=SessionDiagnostics(root:blocked)
        failed.record(.lifecycle,labels:["phase":"active"])
        XCTAssertFalse(failed.storageFailureCodes.isEmpty)
        XCTAssertTrue(failed.report(snapshot:"{}").contains("active"))
    }
    func testMediaPollingDeduplicatesWithoutLosingStateTransitions() async throws {
        let root=directory(); defer { try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root)
        for n in 0..<50 { history.record(.mediaState,labels:["phase":"observed"],numbers:["paused":0,"elapsed":Double(n)],deduplicate:"same-video") }
        history.record(.mediaState,labels:["phase":"observed"],numbers:["paused":1,"elapsed":51],deduplicate:"same-video")
        XCTAssertEqual(history.eventCount,3)
        let sessions=try XCTUnwrap(try object(history)["sessionHistory"] as? [[String:Any]])
        XCTAssertEqual((sessions.first?["events"] as? [Any])?.count,3)
    }
    func testFullExportRetainsEventsBeyondTheScreenPreviewSize() async throws {
        let root=directory(); defer { try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root)
        for n in 0..<1000 { history.record(.controls,labels:["action":"seek"],numbers:["target":Double(n)]) }
        let report=history.report(snapshot:"{}")
        XCTAssertGreaterThan(report.count,200_000)
        let sessions=try XCTUnwrap(try object(history)["sessionHistory"] as? [[String:Any]])
        XCTAssertEqual((sessions.first?["events"] as? [Any])?.count,1001)
        XCTAssertEqual(sessions.first?["complete"] as? Bool,true)
    }
    func testRetentionKeepsCurrentSessionAndNeverFollowsLinkedFiles() async throws {
        let root=directory(); defer { try? FileManager.default.removeItem(at:root) }
        _=SessionDiagnostics(root:root,maximumSessions:2)
        _=SessionDiagnostics(root:root,maximumSessions:2)
        let current=SessionDiagnostics(root:root,maximumSessions:2)
        let external=directory(); try Data("PRIVATE_EXTERNAL".utf8).write(to:external); defer { try? FileManager.default.removeItem(at:external) }
        let linked=root.appendingPathComponent(UUID().uuidString+".jsonl")
        try FileManager.default.createSymbolicLink(at:linked,withDestinationURL:external)
        let text=current.report(snapshot:"{}")
        XCTAssertFalse(text.contains("PRIVATE_EXTERNAL"))
        let sessions=try XCTUnwrap(try object(current)["sessionHistory"] as? [[String:Any]])
        XCTAssertEqual(sessions.count,2); XCTAssertTrue(sessions.contains { $0["sessionID"] as? String == current.sessionID.uuidString })
    }
}
