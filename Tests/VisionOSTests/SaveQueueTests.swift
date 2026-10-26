import AVFoundation
import XCTest
@testable import VisionStream

@MainActor final class SaveQueueTests:XCTestCase {
    private func origin() throws -> URL {
        let url=try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        guard url.scheme=="https",["127.0.0.1","localhost"].contains(url.host),url.port != nil else { throw URLError(.badURL) }
        return url
    }
    private func app(_ root:URL)->AppModel {
        let library=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]
        return AppModel(history:SessionDiagnostics(root:root.appendingPathComponent("history")),downloads:DownloadModel(root:root.appendingPathComponent("saved")),hlsDownloads:HLSOfflineLibrary(store:HLSOfflineStore(root:root.appendingPathComponent("hls"),library:library),identifier:"personal.visionstream.queue."+UUID().uuidString))
    }
    private func wait(_ condition:()->Bool,seconds:Double=25) async throws {
        let end=Date().addingTimeInterval(seconds)
        while !condition(),Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertTrue(condition(),"Queue did not reach the expected state")
    }
    func testSequentialSavesContinueAfterFailureAndReportQueueWithoutPrivateLinks() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app=app(root)
        defer { app.downloads.cancel();app.hlsDownloads.stopTestSession();try? FileManager.default.removeItem(at:root) }
        let paths=["delayed/controls-demo.mp4","missing.mp4","vr360-sbs.mp4"]
        for path in paths { XCTAssertTrue(app.enqueueSave(.init(id:path,source:base.appendingPathComponent(path).absoluteString,title:"PRIVATE_TITLE"),cookies:[],userAgent:nil)) }
        XCTAssertTrue(app.downloads.isDownloading);XCTAssertEqual(app.queuedSaves.count,2)
        let report=app.playbackReport
        XCTAssertTrue(report.contains("queuedSaveCount"));XCTAssertFalse(report.contains("PRIVATE_TITLE"));XCTAssertFalse(report.contains(base.absoluteString))
        try await wait { app.queuedSaves.isEmpty && !app.saveInProgress && app.saveQueueWorker==nil }
        XCTAssertEqual(app.downloads.videos.count,2)
        XCTAssertTrue(app.saveQueueMessage?.contains("HTTP 404") == true)
        let events=app.history.report(snapshot:"{}")
        XCTAssertTrue(events.contains("httpStatus"));XCTAssertTrue(events.contains("queue-starting"))
        for video in app.downloads.videos {
            let asset=AVURLAsset(url:try XCTUnwrap(app.downloads.store.file(for:video)))
            let playable=try await asset.load(.isPlayable)
            XCTAssertTrue(playable)
        }
    }
    func testRemoveWaitingCancelActiveAndAutomaticallyStartNext() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),app=app(root)
        defer { app.downloads.cancel();app.hlsDownloads.stopTestSession();try? FileManager.default.removeItem(at:root) }
        for path in ["download-slow.mp4","missing.mp4","vr180-sbs.mp4"] {
            XCTAssertTrue(app.enqueueSave(.init(id:path,source:base.appendingPathComponent(path).absoluteString),cookies:[],userAgent:nil))
        }
        app.removeQueuedSave(try XCTUnwrap(app.queuedSaves.first).id)
        XCTAssertEqual(app.queuedSaves.count,1)
        try await wait { app.downloads.received>0 }
        app.downloads.cancel()
        try await wait { app.queuedSaves.isEmpty && !app.saveInProgress && app.saveQueueWorker==nil }
        XCTAssertEqual(app.downloads.videos.count,1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:app.downloads.store.root.appendingPathComponent("Staging").path),[])
    }
    func testCapacityDuplicateRemovalAndMemoryOnlyWaitingRequests() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),app=app(root)
        defer { app.downloads.cancel();app.hlsDownloads.stopTestSession();try? FileManager.default.removeItem(at:root) }
        let first=MediaCandidate(id:"first",source:base.appendingPathComponent("delayed/controls-demo.mp4").absoluteString)
        XCTAssertTrue(app.enqueueSave(first,cookies:[],userAgent:nil))
        XCTAssertFalse(app.enqueueSave(first,cookies:[],userAgent:nil))
        for index in 0..<20 {
            XCTAssertTrue(app.enqueueSave(.init(id:"\(index)",source:base.appendingPathComponent("vr180-sbs.mp4").absoluteString+"?private=\(index)"),cookies:[],userAgent:nil))
        }
        XCTAssertEqual(app.queuedSaves.count,20);XCTAssertTrue(app.saveQueueFull)
        XCTAssertFalse(app.enqueueSave(.init(id:"excess",source:base.appendingPathComponent("vr360-sbs.mp4").absoluteString),cookies:[],userAgent:nil))
        app.removeQueuedSave(app.queuedSaves[0].id);XCTAssertFalse(app.saveQueueFull)
        let isolated=AppModel(history:SessionDiagnostics(root:root.appendingPathComponent("separate-history")),downloads:DownloadModel(root:root.appendingPathComponent("other")),hlsDownloads:HLSOfflineLibrary(store:HLSOfflineStore(root:root.appendingPathComponent("other-hls"),library:FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]),identifier:"personal.visionstream.empty-queue."+UUID().uuidString))
        XCTAssertTrue(isolated.queuedSaves.isEmpty);isolated.hlsDownloads.stopTestSession()
        XCTAssertFalse(app.playbackReport.contains("private="))
        for video in app.queuedSaves { app.removeQueuedSave(video.id) }
        app.downloads.cancel()
        try await wait { app.saveQueueWorker==nil }
    }
    func testHLSRecoveryFinishesBeforeQueuedMP4Starts() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),app=app(root)
        defer { app.downloads.cancel();app.hlsDownloads.stopTestSession();try? FileManager.default.removeItem(at:root) }
        app.browser.open(base.appendingPathComponent("agent-context-test"))
        // The response is sufficient to register the real WebKit identity.
        // isLoading KVO can lag on a cold detached WebView.
        try await wait { app.browser.pageHTTPStatus==200 }
        let agent=await app.browser.playbackUserAgent()
        XCTAssertNotNil(agent)
        XCTAssertTrue(app.enqueueSave(.init(id:"hls",source:base.appendingPathComponent("agent-test/quality/master.m3u8").absoluteString,mimeType:"application/vnd.apple.mpegurl"),cookies:[],userAgent:agent))
        XCTAssertTrue(app.enqueueSave(.init(id:"mp4",source:base.appendingPathComponent("vr180-sbs.mp4").absoluteString),cookies:[],userAgent:nil))
        XCTAssertEqual(app.queuedSaves.count,1)
        try await wait({ app.queuedSaves.isEmpty && !app.saveInProgress && app.saveQueueWorker==nil },seconds:75)
        XCTAssertTrue(app.hlsDownloads.videos.isEmpty)
        XCTAssertEqual(app.downloads.videos.count,2)
        XCTAssertTrue(app.history.report(snapshot:"{}").contains("recovered-as-mp4"))
    }
}
