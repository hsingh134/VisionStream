import AVFoundation
import Observation
import UIKit

/// Apple owns transport and package placement. Our journal stores only local
/// references and display metadata; URL/cookie persistence belongs to the OS.
@MainActor @Observable final class HLSOfflineLibrary: NSObject, @preconcurrency AVAssetDownloadDelegate {
    @ObservationIgnored weak var diagnostics: SessionDiagnostics?
    static let shared = HLSOfflineLibrary()
    static var sessionIdentifier: String { (Bundle.main.bundleIdentifier ?? "personal.visionstream.browser") + ".offline-hls" }
    private(set) var videos: [SavedHLSVideo] = []
    var message: String?
    private(set) var indexDamaged = false
    private(set) var failureCode: String?
    let store: HLSOfflineStore
    @ObservationIgnored private var session: AVAssetDownloadURLSession?
    @ObservationIgnored private var tasks: [UUID: AVAssetDownloadTask] = [:]
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var progress: Task<Void, Never>?
    @ObservationIgnored private var completion: (() -> Void)?
    @ObservationIgnored private var validations = 0
    private var eventsFinished = false
    private var reconnecting = false
    private let identifier: String
    private struct RequestContext {
        let media:MediaCandidate;let source:URL;let cookies:[HTTPCookie];let userAgent:String?
        let cookieProvider:(@MainActor (URL) async -> [HTTPCookie])?
        var selected:[URL]=[]
    }
    struct ForegroundFallback {
        let id:UUID;let media:MediaCandidate;let cookies:[HTTPCookie];let userAgent:String?
        let cookieProvider:(@MainActor (URL) async -> [HTTPCookie])?
        let context:DiagnosticContext?
    }
    @ObservationIgnored var onForegroundFallback:((ForegroundFallback)->Bool)?
    @ObservationIgnored var onCancelForeground:((UUID)->Void)?
    @ObservationIgnored private var diagnosticRequests:[UUID:RequestContext]=[:]
    @ObservationIgnored private var diagnosticTasks:[UUID:Task<Void,Never>]=[:]

    init(store customStore: HLSOfflineStore? = nil, identifier: String = HLSOfflineLibrary.sessionIdentifier) {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        store = customStore ?? HLSOfflineStore(root: library.appendingPathComponent("Application Support/HLSOffline"), library: library)
        self.identifier = identifier
        super.init()
        do { videos = try store.load() }
        catch { indexDamaged = true; message = "The HLS download list could not be opened. Existing packages have been kept." }
        for i in videos.indices where videos[i].state == .preparing || videos[i].state == .validating || videos[i].state == .recovering {
            videos[i].state = .failed; videos[i].failure = "The download was interrupted. Save it again from the webpage."
        }
        if !indexDamaged { _ = persist() }
        if active { connect() }
    }
    var active: Bool { videos.contains { [.preparing, .saving, .paused, .validating, .recovering, .cancelling].contains($0.state) } }
    var saved: [SavedHLSVideo] { videos.filter { $0.state == .complete } }
    static func accepts(_ media: MediaCandidate) -> Bool {
        media.compatibility == .candidate && (media.normalizedMIMEType.contains("mpegurl") || URL(string: media.source)?.pathExtension.lowercased() == "m3u8")
    }
    #if targetEnvironment(simulator)
    var testLowBitrate = false
    #endif
    func start(_ media: MediaCandidate, cookies: [HTTPCookie], userAgent: String?,cookieProvider:(@MainActor (URL) async -> [HTTPCookie])? = nil,parent:DiagnosticContext? = nil) {
        guard !active, !indexDamaged, Self.accepts(media), let url = URL(string: media.source) else { message = "Finish or cancel the current HLS download before starting another."; return }
        guard videos.count < 200 else { message = "Remove an older HLS download before saving another."; return }
        let id = UUID(), hint = media.formatHint ?? VideoFormatDetection.persistentHint(source: media.source, title: media.title, pageURL: media.pageURL)
        let context=diagnostics.flatMap { $0.isEnabled ? $0.begin(.hlsDownload,media:media,parent:parent):nil }
        videos.insert(.init(id: id, name: OfflineVideoStore.cleanName(media.title), hint: hint, state: .preparing, diagnosticContext:context), at: 0)
        diagnostics?.record(.transfer,context:context,labels:["phase":"preparing"],numbers:["cookieCount":Double(CookieScope.matching(cookies,url:url).count),"userAgentApplied":userAgent == nil ? 0:1])
        guard persist() else { videos.removeAll { $0.id == id }; return }
        diagnosticRequests[id] = .init(media:media,source:url,cookies:cookies,userAgent:userAgent,cookieProvider:cookieProvider)
        message = nil; failureCode = nil
        var options: [String: Any] = [AVURLAssetHTTPCookiesKey: CookieScope.matching(cookies, url: url)]
        if let userAgent, userAgent.utf8.count <= 1024, userAgent.rangeOfCharacter(from: .controlCharacters) == nil { options[AVURLAssetHTTPUserAgentKey] = userAgent }
        let asset = AVURLAsset(url: url, options: options)
        preparation = Task { @MainActor [weak self] in
            let timeout = Task { try? await Task.sleep(for: .seconds(30)); if !Task.isCancelled { asset.cancelLoading() } }
            defer { timeout.cancel() }
            do {
                let (playable, protected, duration) = try await withTaskCancellationHandler {
                    try await asset.load(.isPlayable, .hasProtectedContent, .duration)
                } onCancel: { asset.cancelLoading() }
                try Task.checkCancellation()
                guard let self, let index = self.index(id), self.videos[index].state == .preparing else { return }
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"asset-properties"],numbers:["playable":playable ? 1:0,"protected":protected ? 1:0,"duration":duration.seconds])
                guard playable, !protected, duration.seconds.isFinite, duration.seconds > 0 else {
                    let request=self.diagnosticRequests[id]
                    self.fail(id,"Only playable, unprotected on-demand HLS can be saved.")
                    if !protected,let request { self.inspectFailedResources(id,request:request) }
                    return
                }
                self.connect(userAgent:userAgent)
                let reconnectDeadline = Date().addingTimeInterval(8)
                while self.reconnecting {
                    try Task.checkCancellation()
                    guard Date() < reconnectDeadline else { self.fail(id, "The background download service did not respond. Reopen VisionStream and try again."); return }
                    try await Task.sleep(for: .milliseconds(20))
                }
                try Task.checkCancellation()
                guard let index = self.index(id), self.videos[index].state == .preparing else { return }
                let configuration = AVAssetDownloadConfiguration(asset: asset, title: self.videos[index].name)
                configuration.auxiliaryContentConfigurations = []
                #if targetEnvironment(simulator)
                if self.testLowBitrate { configuration.primaryContentConfiguration.variantQualifiers = [AVAssetVariantQualifier(predicate: NSPredicate(format: "peakBitRate < 600000"))] }
                #endif
                let free = (try FileManager.default.attributesOfFileSystem(forPath: self.store.library.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                guard free > 512 * 1024 * 1024 else { self.fail(id, "Free at least 512 MB before saving an HLS video."); return }
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"creating-system-task"],numbers:["freeStorageBytes":Double(free)])
                let task=self.session!.makeAssetDownloadTask(downloadConfiguration:configuration)
                task.taskDescription = id.uuidString; self.tasks[id] = task
                self.videos[index].state = .saving
                guard self.persist() else { task.cancel(); return }
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"saving"],numbers:["taskIdentifier":Double(task.taskIdentifier)])
                task.resume(); self.observeProgress()
            } catch {
                guard let self, let index = self.index(id), self.videos[index].state == .preparing else { return }
                self.recordFailure(error, id: id)
                let request=self.diagnosticRequests[id]
                self.fail(id, PlaybackDiagnostics.failureHint(error) ?? "The HLS video could not be prepared. Reopen its webpage and try a fresh source.")
                if !Task.isCancelled,let request { self.inspectFailedResources(id,request:request) }
            }
        }
    }
    private func connect(userAgent:String? = nil) {
        guard session == nil else { return }
        diagnostics?.record(.lifecycle,labels:["phase":"hls-service-connecting"])
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false; config.sessionSendsLaunchEvents = true
        config.urlCredentialStorage = nil; config.timeoutIntervalForResource = 7200
        let validAgent=userAgent.flatMap { !$0.isEmpty && $0.utf8.count<=1024 && $0.rangeOfCharacter(from:.controlCharacters)==nil ? $0 : nil }
        if let validAgent { config.httpAdditionalHeaders=["User-Agent":validAgent] }
        diagnostics?.record(.lifecycle,labels:["phase":"hls-session-request-options"],numbers:["backgroundUserAgentApplied":validAgent == nil ? 0:1])
        let session = AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: .main)
        self.session = session; reconnecting = true
        session.getAllTasks { [weak self] existing in
            Task { @MainActor in
                guard let self else { return }
                defer { self.reconnecting = false }
                for task in existing {
                    guard let task = task as? AVAssetDownloadTask, let id = task.taskDescription.flatMap(UUID.init(uuidString:)), let index = self.index(id) else { task.cancel(); continue }
                    guard [.saving, .paused, .cancelling].contains(self.videos[index].state) else { task.cancel(); continue }
                    self.tasks[id] = task
                    if self.videos[index].state == .cancelling { task.cancel() }
                    else { self.videos[index].state = task.state == .suspended ? .paused : .saving }
                }
                for video in self.videos where [.saving, .paused, .cancelling].contains(video.state) && self.tasks[video.id] == nil {
                    self.fail(video.id, "The download was interrupted. Save it again from a fresh webpage source.")
                }
                _ = self.persist(); self.observeProgress()
            }
        }
    }
    #if targetEnvironment(simulator)
    func stopTestSession() { preparation?.cancel(); progress?.cancel(); progress = nil; diagnosticTasks.values.forEach { $0.cancel() };diagnosticTasks.removeAll();diagnosticRequests.removeAll();session?.invalidateAndCancel(); session = nil }
    #endif
    func pause(_ id: UUID) { guard let i = index(id), let task = tasks[id], videos[i].state == .saving else { return }; diagnostics?.record(.controls,context:videos[i].diagnosticContext,labels:["action":"download-pause"]); task.suspend(); videos[i].state = .paused; _ = persist() }
    func resume(_ id: UUID) { guard let i = index(id), let task = tasks[id], videos[i].state == .paused else { return }; diagnostics?.record(.controls,context:videos[i].diagnosticContext,labels:["action":"download-resume"]); task.resume(); videos[i].state = .saving; _ = persist(); observeProgress() }
    func cancel(_ id: UUID) {
        guard let i = index(id) else { return }
        diagnostics?.record(.controls,context:videos[i].diagnosticContext,labels:["action":"download-cancel"])
        if videos[i].state == .recovering { onCancelForeground?(id);return }
        if videos[i].state == .validating { return }
        if videos[i].state == .preparing { preparation?.cancel(); fail(id, "HLS download cancelled."); return }
        guard let task = tasks[id] else { fail(id, "HLS download cancelled."); return }
        videos[i].state = .cancelling; _ = persist(); task.cancel()
    }
    func remove(_ video: SavedHLSVideo) {
        guard video.state == .complete || video.state == .failed else { return }
        diagnosticTasks.removeValue(forKey:video.id)?.cancel()
        do { try store.removePackage(relative: video.relativePackage); videos.removeAll { $0.id == video.id }; _ = persist() }
        catch { message = "The HLS package could not be removed. Try again." }
    }
    func clearDiagnosticLinks() throws {
        for i in videos.indices { videos[i].diagnosticContext=nil }
        guard !indexDamaged else { throw OfflineVideoStore.StoreError.invalidCatalogue }
        try store.save(videos)
    }
    func receiveBackgroundEvents(completion: @escaping () -> Void) {
        diagnostics?.record(.lifecycle,labels:["phase":"hls-background-events"])
        self.completion = completion; eventsFinished = false; connect() }
    private func flushCompletion() { guard eventsFinished, validations == 0 else { return }; let callback = completion; completion = nil; callback?() }
    private func index(_ id: UUID) -> Int? { videos.firstIndex { $0.id == id } }
    @discardableResult private func persist() -> Bool {
        guard !indexDamaged else { return false }
        do { try store.save(videos); return true }
        catch { message = "HLS download progress could not be saved. Check available storage."; return false }
    }
    private func fail(_ id: UUID, _ reason: String) {
        guard let i = index(id) else { return }
        try? store.removePackage(relative: videos[i].relativePackage)
        videos[i].state = .failed; videos[i].failure = reason; tasks[id] = nil
        diagnosticRequests[id]=nil
        diagnostics?.record(.transfer,context:videos[i].diagnosticContext,labels:["phase":"failed"],numbers:["progress":videos[i].fraction],codes:videos[i].failureCodes ?? [])
        message = reason; _ = persist(); flushCompletion()
    }
    private func recordFailure(_ error: Error, id: UUID) {
        let codes = PlaybackDiagnostics.failure(error)
        failureCode = codes.first
        if let i = index(id) { videos[i].failureCodes = codes }
    }
    var diagnosticFailureCodes: [String] {
        videos.first(where: { $0.state == .failed })?.failureCodes ?? []
    }
    private func observeProgress() {
        guard progress == nil, active else { return }
        progress = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                for (id, task) in self.tasks {
                    guard let i = self.index(id) else { continue }
                    let fraction = task.progress.fractionCompleted
                    if fraction.isFinite {
                        self.videos[i].fraction = min(1, max(0, fraction))
                        self.diagnostics?.record(.transfer,context:self.videos[i].diagnosticContext,labels:["phase":self.videos[i].state.rawValue],numbers:["progress":floor(fraction*100)/100],deduplicate:"hls-progress-" + id.uuidString)
                    }
                }
                if !self.active { self.progress = nil; return }
            }
        }
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)), let i = index(id) else { assetDownloadTask.cancel(); return }
        guard let relative = store.relative(location) else { failureCode = "unrecognised-system-package-location"; assetDownloadTask.cancel(); return }
        diagnostics?.record(.transfer,context:videos[i].diagnosticContext,labels:["phase":"system-location-accepted"])
        videos[i].relativePackage = relative
        if !persist() { assetDownloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)), let i = index(id) else { return }
        guard [.saving,.paused,.cancelling].contains(videos[i].state) else { return }
        tasks[id] = nil
        let request=diagnosticRequests.removeValue(forKey:id)
        diagnostics?.record(.transfer,context:videos[i].diagnosticContext,labels:["phase":"system-task-completed"],numbers:["receivedBytes":Double(task.countOfBytesReceived),"expectedBytes":Double(task.countOfBytesExpectedToReceive),"requestContextAvailable":request == nil ? 0:1],codes:PlaybackDiagnostics.failure(error))
        if let error { recordFailure(error, id: id) }
        guard error == nil, videos[i].state != .cancelling, let relative = videos[i].relativePackage, let url = store.url(for: relative) else {
            let cancelled=videos[i].state == .cancelling
            let codes=PlaybackDiagnostics.failure(error)
            if !cancelled,let request,codes.contains(where: { ["CoreMediaErrorDomain:-12938","CoreMediaErrorDomain:-12660","CoreMediaErrorDomain:-12884"].contains($0) }),let callback=onForegroundFallback {
                try? store.removePackage(relative:videos[i].relativePackage)
                videos[i].relativePackage=nil;videos[i].state = .recovering;videos[i].failure=nil
                _ = persist()
                if callback(.init(id:id,media:request.media,cookies:request.cookies,userAgent:request.userAgent,cookieProvider:request.cookieProvider,context:videos[i].diagnosticContext)) {
                    message=nil
                    diagnostics?.record(.transfer,context:videos[i].diagnosticContext,labels:["phase":"foreground-recovery-started"])
                    flushCompletion();return
                }
            }
            fail(id, cancelled ? "HLS download cancelled." : (PlaybackDiagnostics.failureHint(error) ?? "The HLS download failed. Streaming may still work: this source could not be saved by Apple’s offline download service. Try a fresh source or a separate MP4 if available."))
            if !cancelled,let request,PlaybackDiagnostics.failure(error).contains("CoreMediaErrorDomain:-12938") { inspectFailedResources(id,request:request) }
            return
        }
        diagnostics?.record(.transfer,context:videos[i].diagnosticContext,labels:["phase":"validating-offline-cache"])
        videos[i].state = .validating; _ = persist()
        validations += 1
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.validations -= 1; self.flushCompletion() }
            do {
                let asset = AVURLAsset(url: url)
                guard asset.assetCache?.isPlayableOffline == true else { throw OfflineVideoStore.StoreError.invalidFile }
                let bytes = try await Task.detached(priority: .utility) { try HLSOfflineStore.packageBytes(url) }.value
                guard let i = self.index(id), self.videos[i].state == .validating, bytes > 0 else { throw OfflineVideoStore.StoreError.invalidFile }
                var file = url; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try file.setResourceValues(flags)
                self.videos[i].bytes = bytes; self.videos[i].fraction = 1; self.videos[i].state = .complete
                self.diagnostics?.record(.transfer,context:self.videos[i].diagnosticContext,labels:["phase":"complete"],numbers:["savedBytes":Double(bytes)])
                _ = self.persist()
            } catch { self.fail(id, "The downloaded HLS package is incomplete, unavailable or exceeds the storage limit. Save a supported source again.") }
        }
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didReceive metricEvent: AVMetricEvent) {
        let context=assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)).flatMap { index($0) }.flatMap { videos[$0].diagnosticContext }
        NativeDiagnosticMetrics.record(metricEvent,history:diagnostics,context:context)
    }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadVariants variants: [AVAssetVariant]) {
        let context=assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)).flatMap { index($0) }.flatMap { videos[$0].diagnosticContext }
        if let id=assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) { diagnosticRequests[id]?.selected=Array(variants.prefix(4).map(\.url)) }
        for variant in variants {
            var selected=context
            selected?.resource=DiagnosticResource(variant.url); selected?.mediaID=diagnostics?.reference(variant.url.absoluteString)
            diagnostics?.record(.quality,context:selected,labels:["phase":"offline-system-selected"],numbers:["variantCount":Double(variants.count),"indicatedBitrate":variant.peakBitRate ?? -1,"width":Double(variant.videoAttributes?.presentationSize.width ?? 0),"height":Double(variant.videoAttributes?.presentationSize.height ?? 0)])
        }
    }
    func finishForegroundRecovery(_ id:UUID,saved:Bool,message:String?) {
        guard let i=index(id),videos[i].state == .recovering else { return }
        if saved {
            diagnostics?.record(.transfer,context:videos[i].diagnosticContext,labels:["phase":"recovered-as-mp4"])
            videos.remove(at:i);_ = persist();self.message=nil
        } else { fail(id,message ?? "Save cancelled. The temporary video has been removed.") }
    }
    private func inspectFailedResources(_ id:UUID,request:RequestContext) {
        guard let i=index(id) else { return }
        let context=videos[i].diagnosticContext
        diagnostics?.record(.transferMetrics,context:context,labels:["phase":"offline-resource-check-starting"])
        diagnosticTasks[id]=Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.diagnosticTasks[id]=nil }
            let findings=await HLSResourceInspector.inspect(source:request.source,selected:request.selected,cookies:request.cookies,userAgent:request.userAgent,cookieProvider:request.cookieProvider,history:self.diagnostics,context:context)
            guard !Task.isCancelled,let i=self.index(id),self.videos[i].state == .failed else { return }
            if let missing=findings.first(where: { $0.status == 404 }) {
                let kind=missing.role == "segment" ? "video segment (sequence \(missing.index))":missing.role
                self.videos[i].failureCodes=Array(Set((self.videos[i].failureCodes ?? [])+["HTTP:404"])) .sorted()
                self.videos[i].failure="Saving failed. A published HLS \(kind) returned HTTP 404 during a normal availability check. Playback details identifies this resource without exposing its private link."
                if self.videos.first?.id == id,!self.active { self.message=self.videos[i].failure }
                _ = self.persist()
            }
        }
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didFinishCollecting metrics:URLSessionTaskMetrics) {
        let context=task.taskDescription.flatMap(UUID.init(uuidString:)).flatMap { index($0) }.flatMap { videos[$0].diagnosticContext }
        NativeDiagnosticMetrics.transactions(metrics,history:diagnostics,context:context,phase:"offline-session-task")
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { eventsFinished = true; flushCompletion() }
}

@MainActor final class VisionStreamApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == HLSOfflineLibrary.sessionIdentifier else { completionHandler(); return }
        HLSOfflineLibrary.shared.receiveBackgroundEvents(completion: completionHandler)
    }
}
