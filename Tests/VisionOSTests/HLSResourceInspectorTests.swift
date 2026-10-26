import AVFoundation
import RealityKit
import XCTest
@testable import VisionStream

@MainActor final class HLSResourceInspectorTests:XCTestCase {
    private func origin() throws -> URL {
        let url=try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        guard url.scheme=="https",["127.0.0.1","localhost"].contains(url.host),url.port != nil else { throw URLError(.badURL) }
        return url
    }
    func testIdentifiesPublished404SegmentAndNeverFetchesKeysOrFollowsRedirects() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root)
        let source=base.appendingPathComponent("resource-trace/master.m3u8")
        let context=history.begin(.hlsDownload,media:.init(id:"fixture",source:source.absoluteString))
        let findings=await HLSResourceInspector.inspect(source:source,selected:[],cookies:[],userAgent:nil,history:history,context:context)
        let missing=try XCTUnwrap(findings.first { $0.status==404 })
        XCTAssertEqual(missing.role,"segment");XCTAssertEqual(missing.index,732)
        XCTAssertTrue(findings.contains { $0.role=="initialization" && $0.status==206 })
        XCTAssertFalse(findings.contains { $0.role=="key" })
        let report=history.report(snapshot:"{}")
        XCTAssertTrue(report.contains("foreground-range-headers"));XCTAssertTrue(report.contains("732"))
        XCTAssertFalse(report.contains("published=exact"));XCTAssertFalse(report.contains("missing.ts"));XCTAssertFalse(report.contains(base.absoluteString))
        let redirect=await HLSResourceInspector.inspect(source:base.appendingPathComponent("resource-trace/redirect.m3u8"),selected:[],cookies:[],userAgent:nil,history:history,context:context)
        XCTAssertEqual(redirect.first?.status,302)
        let session=URLSession(configuration:.ephemeral)
        defer { session.invalidateAndCancel() }
        let (data,_)=try await session.data(from:base.appendingPathComponent("resource-trace/status"))
        let status=try XCTUnwrap(try JSONSerialization.jsonObject(with:data) as? [String:Int])
        XCTAssertEqual(status["keyRequests"],0);XCTAssertEqual(status["redirectTargetRequests"],0)
    }
    func testResourceCheckPreservesNormalScopedAuthentication() async throws {
        let base=try origin()
        let cookie=try XCTUnwrap(HTTPCookie(properties:[.domain:"127.0.0.1",.path:"/auth/",.name:"visionstream_fixture",.value:"authorised",.secure:"TRUE"]))
        let findings=await HLSResourceInspector.inspect(source:base.appendingPathComponent("auth/resource-trace/master.m3u8"),selected:[],cookies:[cookie],userAgent:nil,history:nil,context:nil)
        XCTAssertEqual(findings.first?.status,200)
        XCTAssertTrue(findings.contains { $0.role=="segment" && $0.index==732 && $0.status==404 })
        XCTAssertFalse(findings.contains { $0.status==401 })
    }
    func testNativeMetricSelectorsAreActuallyImplemented() throws {
        let library=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let model=HLSOfflineLibrary(store:HLSOfflineStore(root:root,library:library),identifier:"personal.visionstream.metric-selector."+UUID().uuidString)
        defer { model.stopTestSession() }
        XCTAssertTrue(model.responds(to:#selector(AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didReceive:))))
        XCTAssertTrue(model.responds(to:#selector(URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:))))
    }
    func testNativeDownloadFailureStartsCorrelatedResourceChecks() async throws {
        let base=try origin(),library=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history=SessionDiagnostics(root:root.appendingPathComponent("history"))
        let model=HLSOfflineLibrary(store:HLSOfflineStore(root:root.appendingPathComponent("jobs"),library:library),identifier:"personal.visionstream.failure-inspection."+UUID().uuidString)
        model.diagnostics=history
        defer { model.stopTestSession();try? FileManager.default.removeItem(at:root) }
        let source=base.appendingPathComponent("quality/master.m3u8")
        model.start(.init(id:"fixture",source:source.absoluteString,mimeType:"application/vnd.apple.mpegurl"),cookies:[],userAgent:nil)
        var deadline=Date().addingTimeInterval(15)
        while model.videos.first?.state == .preparing,Date()<deadline { try await Task.sleep(for:.milliseconds(50)) }
        let job=try XCTUnwrap(model.videos.first)
        XCTAssertEqual(job.state,.saving)
        let session=URLSession(configuration:.ephemeral)
        defer { session.invalidateAndCancel() }
        let task=session.dataTask(with:source);task.taskDescription=job.id.uuidString
        // Inject only the native completion callback. Resource requests below
        // use the real production inspector against the HTTPS fixture server.
        model.urlSession(session,task:task,didCompleteWithError:NSError(domain:"CoreMediaErrorDomain",code:-12938,userInfo:["NSDescription":"HTTP 404: File Not Found"]))
        deadline=Date().addingTimeInterval(15)
        while !history.report(snapshot:"{}").contains("offline-resource-check-finished"),Date()<deadline { try await Task.sleep(for:.milliseconds(100)) }
        let report=history.report(snapshot:"{}")
        XCTAssertTrue(report.contains("offline-resource-check-finished"))
        XCTAssertTrue(report.contains("foreground-range-headers"));XCTAssertTrue(report.contains("HTTP:404"))
        XCTAssertTrue(report.contains(try XCTUnwrap(job.diagnosticContext).attemptID.uuidString))
        XCTAssertFalse(report.contains(source.absoluteString))
        XCTAssertEqual(model.videos.first?.state,.failed)
        // Accessible foreground resources do not falsely convert an offline
        // error into a successful download or a guessed missing-segment claim.
        XCTAssertFalse(model.videos.first?.failure?.contains("sequence") == true)
        if let failed=model.videos.first { model.remove(failed) }
    }
    func testForegroundDownloadIdentifiesActualMissingSegmentAndRemovesPartialFiles() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history=SessionDiagnostics(root:root.appendingPathComponent("history"))
        let model=DownloadModel(root:root.appendingPathComponent("saved"));model.diagnostics=history
        defer { model.cancel();try? FileManager.default.removeItem(at:root) }
        XCTAssertTrue(model.startHLS(.init(id:"fixture",source:base.appendingPathComponent("broken-hls/master.m3u8").absoluteString,mimeType:"application/vnd.apple.mpegurl"),cookies:[],userAgent:nil))
        let end=Date().addingTimeInterval(20)
        while model.isDownloading,Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(model.isDownloading);XCTAssertTrue(model.videos.isEmpty)
        XCTAssertTrue(model.message?.contains("HTTP 404") == true,model.message ?? "No message")
        XCTAssertTrue(model.message?.contains("segment 8") == true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:model.store.root.appendingPathComponent("Staging").path),[])
        let report=history.report(snapshot:"{}")
        XCTAssertTrue(report.contains("foreground-get"));XCTAssertTrue(report.contains("HTTP:404"))
        XCTAssertTrue(report.contains("resourceIndex"));XCTAssertFalse(report.contains("segment-008.ts"));XCTAssertFalse(report.contains(base.absoluteString))
    }
    func testApplicationRecoversBackgroundBrowserIdentityFailureAsPlayableOfflineMP4() async throws {
        let base=try origin(),library=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history=SessionDiagnostics(root:root.appendingPathComponent("history"))
        let offline=HLSOfflineLibrary(store:HLSOfflineStore(root:root.appendingPathComponent("jobs"),library:library),identifier:"personal.visionstream.foreground-recovery."+UUID().uuidString)
        let downloads=DownloadModel(root:root.appendingPathComponent("mp4"))
        let app=AppModel(history:history,downloads:downloads,hlsDownloads:offline)
        defer { downloads.cancel();offline.stopTestSession();for job in offline.videos { try? offline.store.removePackage(relative:job.relativePackage) };try? FileManager.default.removeItem(at:root) }
        app.browser.open(base.appendingPathComponent("agent-context-test"))
        var end=Date().addingTimeInterval(20)
        while (app.browser.isLoading || app.browser.pageHTTPStatus != 200),Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertEqual(app.browser.pageHTTPStatus,200)
        let value=await app.browser.playbackUserAgent(),agent=try XCTUnwrap(value)
        offline.start(.init(id:"agent",source:base.appendingPathComponent("agent-test/quality-4k/master.m3u8").absoluteString,mimeType:"application/vnd.apple.mpegurl"),cookies:[],userAgent:agent)
        end=Date().addingTimeInterval(75)
        while (offline.active || downloads.isDownloading),Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(offline.active);XCTAssertFalse(downloads.isDownloading)
        let video=try XCTUnwrap(downloads.videos.first,downloads.message ?? offline.message ?? "No saved MP4")
        XCTAssertTrue(offline.videos.isEmpty)
        let file=try XCTUnwrap(downloads.store.file(for:video))
        let asset=AVURLAsset(url:file)
        let (playable,protected,duration,tracks)=try await asset.load(.isPlayable,.hasProtectedContent,.duration,.tracks)
        XCTAssertTrue(playable);XCTAssertFalse(protected);XCTAssertGreaterThan(duration.seconds,5)
        XCTAssertTrue(tracks.contains { $0.mediaType == .audio })
        let playback=PlaybackModel()
        _ = await playback.prepareSavedVideo(video,store:downloads.store)
        let renderer=try ImmersiveRenderer(playback:playback,controls:Entity())
        defer { renderer.stop();playback.stop() }
        try await renderer.start()
        playback.play()
        end=Date().addingTimeInterval(12)
        while playback.decodedWidth==0,Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertEqual(playback.decodedWidth,3840);XCTAssertEqual(playback.decodedHeight,1920)
        playback.stop()
        let report=history.report(snapshot:"{}")
        XCTAssertTrue(report.contains("recovered-as-mp4"));XCTAssertTrue(report.contains("foreground-save-rendition"))
        XCTAssertFalse(report.contains(base.absoluteString));XCTAssertFalse(report.contains(agent))
        let loaded=DownloadModel(root:root.appendingPathComponent("mp4"))
        XCTAssertEqual(loaded.videos.count,1)
        downloads.remove(video)
    }

    func testTransportStreamRemuxProducesNativePlayableMP4() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let session=URLSession(configuration:.ephemeral)
        defer { session.invalidateAndCancel() }
        var data=Data()
        for index in 0..<4 {
            let url=base.appendingPathComponent(String(format:"hls/vr180-sbs/segment-%03d.ts",index))
            let (part,response)=try await session.data(from:url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
            data.append(part)
        }
        let file=root.appendingPathComponent("fixture.ts");try data.write(to:file)
        let converted=root.appendingPathComponent("saved.mp4")
        XCTAssertTrue(MediaRemux.license.contains("LGPL version 2.1"))
        try await MediaRemux.convert(input:file,output:converted,maximumBytes:50_000_000)
        let asset=AVURLAsset(url:converted)
        let (playable,protected,duration)=try await asset.load(.isPlayable,.hasProtectedContent,.duration)
        XCTAssertTrue(playable);XCTAssertFalse(protected);XCTAssertTrue(duration.seconds.isFinite)
        let item=AVPlayerItem(asset:asset),player=AVPlayer(playerItem:item)
        let output=AVPlayerItemVideoOutput(pixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        item.add(output);player.isMuted=true;player.play()
        defer { player.pause();player.replaceCurrentItem(with:nil) }
        var decoded=false;let end=Date().addingTimeInterval(10)
        while !decoded,Date()<end {
            if let buffer=output.copyPixelBuffer(forItemTime:player.currentTime(),itemTimeForDisplay:nil) { decoded=CVPixelBufferGetWidth(buffer)==1024 && CVPixelBufferGetHeight(buffer)==512 }
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertTrue(decoded)
        player.pause()
        let sought=await player.seek(to:CMTime(seconds:4,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
        XCTAssertTrue(sought);XCTAssertEqual(player.currentTime().seconds,4,accuracy:0.15)
    }
    func testClearHLSCancellationAndInvalidMediaLeaveNoSavedOrStagingFiles() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=DownloadModel(root:root)
        defer { model.cancel();try? FileManager.default.removeItem(at:root) }
        XCTAssertTrue(model.startHLS(.init(id:"delayed",source:base.appendingPathComponent("delayed/quality/master.m3u8").absoluteString,mimeType:"application/vnd.apple.mpegurl"),cookies:[],userAgent:nil))
        try await Task.sleep(for:.milliseconds(150));model.cancel()
        try await Task.sleep(for:.milliseconds(300))
        XCTAssertTrue(model.videos.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("Staging").path),[])
        let file=root.appendingPathComponent("malformed.ts"),output=root.appendingPathComponent("invalid.mp4")
        try Data(repeating:0,count:188*16).write(to:file)
        do { try await MediaRemux.convert(input:file,output:output,maximumBytes:1024);XCTFail("Malformed TS accepted") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath:output.path)) }
        let transfer=MP4DownloadTransfer(staging:root.appendingPathComponent("bad.part"),origin:base,maximumBytes:1024*1024,reserveBytes:0,payload:.transportStream) { _,_ in }
        do { _ = try await transfer.run(URLRequest(url:base.appendingPathComponent("vr180-sbs.mp4")),cookies:[]);XCTFail("MP4 accepted as TS") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("bad.part").path)) }
    }
    func testInterruptedForegroundRecoveryBecomesRetryableFailureAfterRelaunch() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]
        let store=HLSOfflineStore(root:root,library:library)
        defer { try? FileManager.default.removeItem(at:root) }
        try store.save([.init(id:UUID(),name:"Fixture",hint:nil,state:.recovering)])
        let model=HLSOfflineLibrary(store:store,identifier:"personal.visionstream.interruption."+UUID().uuidString)
        defer { model.stopTestSession() }
        XCTAssertFalse(model.active);XCTAssertEqual(model.videos.first?.state,.failed)
        XCTAssertEqual(try store.load().first?.state,.failed)
    }
    func testForegroundSavePreservesNormalNarrowPathCookiesIssuedByPlaylist() async throws {
        let base=try origin(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=DownloadModel(root:root)
        defer { model.cancel();try? FileManager.default.removeItem(at:root) }
        let cookie=try XCTUnwrap(HTTPCookie(properties:[.domain:"127.0.0.1",.path:"/quality-cookie/",.name:"quality_browser",.value:"allowed",.secure:"TRUE"]))
        XCTAssertTrue(model.startHLS(.init(id:"cookie",source:base.appendingPathComponent("quality-cookie/master.m3u8").absoluteString,mimeType:"application/vnd.apple.mpegurl"),cookies:[cookie],userAgent:nil))
        let end=Date().addingTimeInterval(20)
        while model.isDownloading,Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(model.isDownloading);XCTAssertNil(model.message)
        XCTAssertEqual(model.videos.count,1)
        let video=try XCTUnwrap(model.videos.first),file=try XCTUnwrap(model.store.file(for:video))
        let asset=AVURLAsset(url:file)
        let playable=try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        model.remove(video)
    }
}
