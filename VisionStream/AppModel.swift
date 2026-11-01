import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    var browserWindowVisible = false
    let history: SessionDiagnostics
    var diagnosticsEnabled:Bool
    var testingDiagnosticsEnabled:Bool
    private(set) var testingChecksRunning=false
    var testingChecksMessage:String?
    var privacyMessage:String?
    @ObservationIgnored private let privacyDefaults:UserDefaults
    let tabs = BrowserTabs()
    var browser: BrowserModel { tabs.active }
    let playback = PlaybackModel(automaticallyDetectFormat: true)
    let library = VRLibraryModel()
    let extractor = ExtractorModel()
    let downloads: DownloadModel
    let hlsDownloads: HLSOfflineLibrary
    var queuedSaves:[QueuedSave]=[]
    var saveQueueMessage:String?
    @ObservationIgnored var saveQueueWorker:Task<Void,Never>?
    @ObservationIgnored var activeSaveSource:String?
    @ObservationIgnored var activeSaveIsHLS=false
    @ObservationIgnored private var foregroundFallbackID:UUID?
    #if targetEnvironment(simulator)
    @ObservationIgnored private var simulatorObservation: Task<Void, Never>?
    #endif
    init(history: SessionDiagnostics? = nil, downloads: DownloadModel? = nil, hlsDownloads: HLSOfflineLibrary? = nil, privacyDefaults:UserDefaults = .standard, diagnosticRoot:URL? = nil, testingDefault:Bool? = nil) {
        self.downloads=downloads ?? DownloadModel()
        self.hlsDownloads=hlsDownloads ?? .shared
        self.privacyDefaults=privacyDefaults
        // Preserve the existing personal user's requested troubleshooting history;
        // fresh installations do not record a browsing history without opting in.
        let legacyRoot=diagnosticRoot ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SessionDiagnostics")
        let legacyExists=((try? FileManager.default.contentsOfDirectory(at:legacyRoot,includingPropertiesForKeys:nil)) ?? []).contains { $0.pathExtension=="jsonl" }
        let enabled=history?.isEnabled ?? ((privacyDefaults.object(forKey:"diagnostics.capture.enabled") as? Bool) ?? legacyExists)
        self.diagnosticsEnabled=enabled
        self.history=history ?? SessionDiagnostics(root:diagnosticRoot,enabled:enabled)
        let testingFallback=testingDefault ?? ((Bundle.main.object(forInfoDictionaryKey:"VisionStreamTestingDiagnosticsDefault") as? String) == "YES")
        // An explicitly supplied diagnostic store owns its capture profile, just as
        // it owns ordinary recording. Unrelated saved UI preferences must not
        // enable full-link capture in an injected redacted store.
        let testing=history?.isTestingEnabled ?? ((privacyDefaults.object(forKey:"diagnostics.testing.enabled") as? Bool) ?? testingFallback)
        self.testingDiagnosticsEnabled=testing
        self.history.setTestingEnabled(testing)
        if testing {
            self.diagnosticsEnabled=true;self.history.setTestingEnabled(true)
            privacyDefaults.set(true,forKey:"diagnostics.capture.enabled")
        }

        tabs.diagnostics=self.history; playback.diagnostics=self.history; library.diagnostics=self.history
        self.downloads.diagnostics=self.history; self.hlsDownloads.diagnostics=self.history; extractor.diagnostics=self.history
        self.hlsDownloads.onForegroundFallback = { [weak self] request in
            guard let self,!self.downloads.isDownloading else { return false }
            let started=self.downloads.startHLS(request.media,cookies:request.cookies,userAgent:request.userAgent,cookieProvider:request.cookieProvider,parent:request.context) { [weak self] saved,message in
                guard let self,self.foregroundFallbackID==request.id else { return }
                self.foregroundFallbackID=nil
                self.hlsDownloads.finishForegroundRecovery(request.id,saved:saved != nil,message:message)
            }
            if started { self.foregroundFallbackID=request.id }
            return started
        }
        self.hlsDownloads.onCancelForeground = { [weak self] id in
            guard let self,self.foregroundFallbackID==id else { return }
            self.downloads.cancel()
        }
        #if targetEnvironment(simulator)
        let platform="simulator"
        #else
        let platform="device"
        #endif
        self.history.record(.lifecycle,labels:["phase":"app-configured","appVersion":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown","runtime":ProcessInfo.processInfo.operatingSystemVersionString,"platform":platform])
        for job in self.hlsDownloads.videos {
            self.history.record(.restoredDownload,context:job.diagnosticContext,labels:["phase":job.state.rawValue,"reason":job.diagnosticContext == nil ? "legacy-unlinked":"restored-existing-job"],numbers:["savedBytes":Double(job.bytes),"progress":job.fraction],codes:job.failureCodes ?? [])
        }
        tabs.onNavigation = { [weak playback, weak library, weak extractor] in
            playback?.cancelPreparation()
            playback?.resetDiagnosticsWhenIdle()
            library?.clear()
            extractor?.clear()
        }
        #if targetEnvironment(simulator)
        if SimulatorTestMonitor.isEnabled {
            simulatorObservation = SimulatorTestMonitor.observe(app: self)
        }
        #endif
    }

    func setDiagnosticsEnabled(_ enabled:Bool) {
        diagnosticsEnabled=enabled;privacyDefaults.set(enabled,forKey:"diagnostics.capture.enabled")
        if !enabled { setTestingDiagnosticsEnabled(false) }
        history.setEnabled(enabled);privacyMessage=nil
    }
    func setTestingDiagnosticsEnabled(_ enabled:Bool) {
        testingDiagnosticsEnabled=enabled;privacyDefaults.set(enabled,forKey:"diagnostics.testing.enabled")
        history.setTestingEnabled(enabled)
        if enabled { diagnosticsEnabled=true;privacyDefaults.set(true,forKey:"diagnostics.capture.enabled") }
        privacyMessage=nil
    }

    func runPlaybackChecks() async {
        guard testingDiagnosticsEnabled,!testingChecksRunning else { return }
        testingChecksRunning=true;testingChecksMessage="Checking webpage readiness and the current source…"
        defer { testingChecksRunning=false }
        let browser=self.browser,version=browser.navigationVersion
        let attempted=playback.diagnosticCandidate.flatMap { candidate in browser.candidates.contains(where: { $0.source==candidate.source }) ? candidate:nil }
        guard let media=attempted ?? MediaCandidate.preferredForPlayback(in:browser.candidates),media.compatibility == .candidate,let url=URL(string:media.source) else {
            testingChecksMessage="Start a video on the webpage first, then run checks.";return
        }
        let context=history.begin(.diagnosticCheck,media:media,page:browser.webView.url,parent:playback.diagnosticContext)
        history.record(.testingCheck,context:context,labels:["phase":"active-checks-started"])
        let state=await browser.captureTestingReadiness(phase:"active-check-webpage")
        let cookies=await browser.cookies(for:url)
        guard !Task.isCancelled,testingDiagnosticsEnabled,self.browser === browser,browser.navigationVersion==version else { testingChecksMessage="Checks cancelled because the page or diagnostic mode changed.";return }
        await PlaybackDiagnosticChecks.run(media:media,cookies:cookies,userAgent:state?.userAgent,history:history,context:context)
        guard !Task.isCancelled,testingDiagnosticsEnabled else { testingChecksMessage="Checks cancelled.";return }
        history.record(.testingCheck,context:context,labels:["phase":"active-checks-completed"])
        testingChecksMessage="Checks complete. Share this updated report. A ready paused player does not prove video playback."
    }

    func deleteDiagnosticHistory() {
        setDiagnosticsEnabled(false)
        var failed=false
        do { try history.deleteHistory() } catch { failed=true }
        do { try downloads.clearDiagnosticLinks() } catch { failed=true }
        do { try hlsDownloads.clearDiagnosticLinks() } catch { failed=true }
        for index in queuedSaves.indices {
            let old=queuedSaves[index]
            queuedSaves[index] = .init(id:old.id,media:old.media,cookies:old.cookies,userAgent:old.userAgent,cookieProvider:old.cookieProvider,context:nil)
        }
        do { try DiagnosticReportFiles.clear() } catch { failed=true }
        privacyMessage=failed ? "Recording is off. Some diagnostic files could not be removed; try again after checking storage. Saved videos and website data were kept." : "Diagnostic history and report files deleted. Recording is off. Saved videos, bookmarks and website data were kept."
    }

    var playbackReport: String { history.report(snapshot: playbackSnapshot) }

    var playbackSnapshot: String {
        let text=PlaybackDiagnostics.report(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            runtime: ProcessInfo.processInfo.operatingSystemVersionString,
            pageHTTPStatus: browser.pageHTTPStatus, pageFailure: browser.pageFailureCodes,
            candidates: browser.candidates, playbackStage: playback.diagnosticStage,
            playbackFailure: playback.failureCodes, mediaHTTPStatus: playback.mediaHTTPStatus,
            projection: playback.projection, layout: playback.layout,
            attemptedMedia: playback.diagnosticCandidate, presentation: playback.presentation,
            decodedWidth: playback.decodedWidth, decodedHeight: playback.decodedHeight,
            failureReason: playback.failureReason, itemStatus: playback.itemStatusAtFailure,
            errorLogCodes: playback.errorLogCodes, browserUserAgentApplied: playback.browserUserAgentApplied, quality: playback.quality, selectedWidth: playback.selectedWidth, selectedHeight: playback.selectedHeight, automaticFormat: playback.automaticallyDetectFormat,
            hlsDownloadFailureCodes: hlsDownloads.videos.first(where: { $0.state == .failed && $0.diagnosticContext?.mediaID != nil && $0.diagnosticContext?.mediaID == playback.diagnosticContext?.mediaID && $0.diagnosticContext?.sessionID == playback.diagnosticContext?.sessionID })?.failureCodes ?? [])
        struct Job: Encodable {
            let id:UUID; let state:String; let bytes:Int64; let progress:Double
            let context:DiagnosticContext?; let legacyUnlinked:Bool; let failureCodes:[String]
        }
        var object=(try? JSONSerialization.jsonObject(with:Data(text.utf8))) as? [String:Any] ?? [:]
        let encoder=JSONEncoder()
        let jobs=hlsDownloads.videos.map { Job(id:$0.id,state:$0.state.rawValue,bytes:$0.bytes,progress:$0.fraction,context:$0.diagnosticContext?.sanitized(),legacyUnlinked:$0.diagnosticContext == nil,failureCodes:PlaybackDiagnostics.sanitizedCodes($0.failureCodes ?? [])) }
        object["queuedSaveCount"]=queuedSaves.count
        object["openTabCount"]=tabs.pages.count
        object["preparationRetryCount"]=playback.preparationRetryCount
        object["videoPipeline"] = (try? JSONSerialization.jsonObject(with:encoder.encode(playback.videoPipeline))) ?? NSNull()
        object["manifestInspection"] = playback.manifestInspection.flatMap { try? JSONSerialization.jsonObject(with:encoder.encode($0)) } ?? NSNull()
        if testingDiagnosticsEnabled {
            func link(_ value:String?) -> Any { value.flatMap(TestingDiagnosticDetails.link).map { $0 as Any } ?? NSNull() }
            let detected=browser.candidates.prefix(16).map { media -> [String:Any] in
                ["id":media.id,"videoID":media.videoID,"source":link(media.source),"pageURL":link(media.pageURL),"title":String(media.title.prefix(160))]
            }
            object["testingSnapshot"]=["pageURL":link(browser.webView.url?.absoluteString),"pageTitle":String(browser.pageTitle.prefix(160)),"attemptedSource":link(playback.diagnosticCandidate?.source),"attemptedPageURL":link(playback.diagnosticCandidate?.pageURL),"detectedSources":detected,"pageLoading":browser.isLoading,"navigationVersion":browser.navigationVersion,"activeTabID":browser.id.uuidString]
        }

        object["queuedSaveAttempts"]=queuedSaves.compactMap { $0.context.flatMap { try? JSONSerialization.jsonObject(with:encoder.encode($0.sanitized())) } }
        object["downloadJobs"]=(try? JSONSerialization.jsonObject(with:encoder.encode(jobs))) ?? []
        object["playbackAttempt"] = playback.diagnosticContext.flatMap { try? JSONSerialization.jsonObject(with:encoder.encode($0)) } ?? NSNull()
        object["mp4DownloadAttempt"] = downloads.diagnosticContext.flatMap { try? JSONSerialization.jsonObject(with:encoder.encode($0)) } ?? NSNull()
        guard let data=try? JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]), let report=String(data:data,encoding:.utf8) else { return text }
        return report
    }
}
