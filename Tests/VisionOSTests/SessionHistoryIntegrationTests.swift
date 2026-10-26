import AVFoundation
import RealityKit
import XCTest
@testable import VisionStream

@MainActor final class SessionHistoryIntegrationTests: XCTestCase {
    private func fixtureOrigin() throws -> String {
        guard let origin=ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"],origin.hasPrefix("https://") else { throw XCTSkip("Requires the controlled HTTPS fixture server") }
        return origin
    }
    private func wait(_ condition: () -> Bool, seconds: Double = 20) async throws {
        let deadline=Date().addingTimeInterval(seconds)
        while !condition() { guard Date()<deadline else { throw URLError(.timedOut) }; try await Task.sleep(for:.milliseconds(50)) }
    }
    func testNavigationStreamingDownloadAndOfflinePlaybackStayLinked() async throws {
        let origin=try fixtureOrigin()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("SessionAcceptance-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]
        let history=SessionDiagnostics(root:root.appendingPathComponent("history"))
        let hls=HLSOfflineLibrary(store:HLSOfflineStore(root:root.appendingPathComponent("hls"),library:library),identifier:"personal.visionstream.history-test."+UUID().uuidString)
        defer { hls.stopTestSession() }
        let app=AppModel(history:history,downloads:DownloadModel(root:root.appendingPathComponent("mp4")),hlsDownloads:hls)
        app.browser.open(URL(string:origin+"/web-playback-test")!)
        try await wait { app.browser.candidates.contains { $0.compatibility == .candidate } }
        let media=try XCTUnwrap(MediaCandidate.preferredForPlayback(in:app.browser.candidates))
        app.playback.player.isMuted=true
        let ready=await app.playback.prepare(media,cookies:[])
        XCTAssertTrue(ready)
        let renderer=try ImmersiveRenderer(playback:app.playback,controls:Entity())
        defer { renderer.stop(); app.playback.stop() }
        try await renderer.start()
        try await wait { app.playback.decodedWidth>0 }
        let playing=try XCTUnwrap(app.playback.diagnosticContext)
        app.playback.pause()
        app.downloads.start(media,cookies:[],userAgent:nil)
        try await wait { !app.downloads.isDownloading }
        let saved=try XCTUnwrap(app.downloads.videos.first,app.downloads.message ?? "No saved file")
        let downloading=try XCTUnwrap(saved.diagnosticContext)
        XCTAssertEqual(playing.mediaID,downloading.mediaID); XCTAssertEqual(playing.pageID,downloading.pageID)
        XCTAssertNotNil(playing.pageID); XCTAssertNotEqual(playing.attemptID,downloading.attemptID)
        app.browser.refresh()
        try await wait { !app.browser.isLoading }
        renderer.stop()
        let offline=await app.playback.prepareSavedVideo(saved,store:app.downloads.store)
        XCTAssertTrue(offline)
        XCTAssertEqual(app.playback.diagnosticContext?.parentAttemptID,downloading.attemptID)
        let localRenderer=try ImmersiveRenderer(playback:app.playback,controls:Entity())
        defer { localRenderer.stop() }
        try await localRenderer.start(); try await wait { app.playback.decodedWidth>0 }
        let report=app.playbackReport
        XCTAssertTrue(report.contains(playing.attemptID.uuidString)); XCTAssertTrue(report.contains(downloading.attemptID.uuidString))
        XCTAssertTrue(report.contains("decodedFrame")); XCTAssertTrue(report.contains("navigation")); XCTAssertTrue(report.contains("refresh"))
        XCTAssertTrue(report.contains("httpStatus"))
        XCTAssertFalse(report.contains("/web-playback-test")); XCTAssertFalse(report.contains(origin))
        XCTAssertTrue(history.storageFailureCodes.isEmpty)
    }
    func testAnotherVideosOldDownloadErrorIsNotAttachedToCurrentPlayback() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("SessionCorrelation-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]
        let history=SessionDiagnostics(root:root.appendingPathComponent("history"))
        let context=history.begin(.hlsDownload,media:.init(id:"other",source:"https://cdn.example/other.m3u8"))
        let store=HLSOfflineStore(root:root.appendingPathComponent("hls"),library:library)
        try store.save([.init(id:UUID(),name:"PRIVATE_TITLE",hint:nil,state:.failed,failureCodes:["CoreMediaErrorDomain:-12938"],diagnosticContext:context)])
        let hls=HLSOfflineLibrary(store:store,identifier:"personal.visionstream.history-test."+UUID().uuidString)
        defer { hls.stopTestSession() }
        let app=AppModel(history:history,downloads:DownloadModel(root:root.appendingPathComponent("mp4")),hlsDownloads:hls)
        defer { app.playback.stop() }
        let ready=await app.playback.prepare(.init(id:"current",source:try fixtureOrigin()+"/controls-demo.mp4"),cookies:[])
        XCTAssertTrue(ready)
        let snapshot=try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(app.playbackSnapshot.utf8)) as? [String:Any])
        XCTAssertEqual(snapshot["hlsDownloadFailureCodes"] as? [String],[])
        let jobs=try XCTUnwrap(snapshot["downloadJobs"] as? [[String:Any]])
        XCTAssertEqual(jobs.first?["failureCodes"] as? [String],["CoreMediaErrorDomain:-12938"])
        XCTAssertFalse(app.playbackReport.contains("PRIVATE_TITLE"))
        XCTAssertTrue(app.playbackReport.contains(context.attemptID.uuidString))
    }
}
