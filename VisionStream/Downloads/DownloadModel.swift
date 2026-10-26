import AVFoundation
import Observation

@MainActor @Observable
final class DownloadModel {
    @ObservationIgnored weak var diagnostics: SessionDiagnostics?
    private(set) var diagnosticContext: DiagnosticContext?
    private var lastDiagnosticUpdate = Date.distantPast
    private(set) var videos: [SavedVideo] = []
    private(set) var isDownloading = false
    private(set) var isImporting = false
    private(set) var needsRepair = false
    private(set) var received: Int64 = 0
    private(set) var expected: Int64 = 0
    private(set) var status = ""
    private(set) var failureCode = "none"
    var message: String?
    let store: OfflineVideoStore
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private let stagingRoot: URL

    init(root: URL? = nil) {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OfflineVideos", isDirectory: true)
        store = OfflineVideoStore(root: root.resolvingSymlinksInPath())
        stagingRoot = store.root.appendingPathComponent("Staging", isDirectory: true)
        do {
            try store.prepare()
            // Transfers intentionally do not survive an app termination. No
            // signed URLs or credential-bearing resume blobs are kept on disk.
            if FileManager.default.fileExists(atPath: stagingRoot.path) { try FileManager.default.removeItem(at: stagingRoot) }
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            videos = try store.load()
            needsRepair = try store.hasUnlistedFiles(in: videos)
            if needsRepair { message = "Some saved files are missing from the list. Repair the library to recover them." }
        } catch { needsRepair = true; message = "The saved-video list could not be opened. Repair the library to recover files already on this headset." }
    }
    static func unavailableReason(_ media: MediaCandidate) -> String? {
        if let reason = media.compatibility.reason { return reason }
        guard let url = URL(string: media.source), media.normalizedMIMEType == "video/mp4" || ["mp4", "m4v"].contains(url.pathExtension.lowercased()) else {
            return "Choose a compatible MP4 source for this download. Supported HLS sources use the separate HLS save route."
        }
        return nil
    }
    var totalBytes: Int64 { videos.reduce(0) { $0 + $1.bytes } }
    func start(_ media: MediaCandidate, cookies: [HTTPCookie], userAgent: String?,parent:DiagnosticContext? = nil) {
        guard !isDownloading else { message = "Wait for the current download, or cancel it first."; return }
        guard !needsRepair else { message = "Repair the saved-video library before saving another video."; return }
        if let reason = Self.unavailableReason(media) { message = reason; return }
        guard let url = URL(string: media.source) else { return }
        diagnosticContext=diagnostics.flatMap { $0.isEnabled ? $0.begin(.mp4Download,media:media,parent:parent):nil }
        let context=diagnosticContext
        diagnostics?.record(.transfer,context:context,labels:["phase":"downloading"],numbers:["cookieCount":Double(cookies.count),"userAgentApplied":userAgent == nil ? 0:1])
        let token = UUID(); generation = token
        message = nil; isImporting = false; failureCode = "none"; received = 0; expected = 0; isDownloading = true; status = "Downloading video…"
        let staging = stagingRoot.appendingPathComponent(token.uuidString + ".mp4")
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: staging)
                if self.generation == token { self.isDownloading = false; self.work = nil }
            }
            do {
                var request = URLRequest(url: url)
                if let userAgent, userAgent.utf8.count <= 1024, userAgent.rangeOfCharacter(from: .controlCharacters) == nil {
                    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                }
                let transfer = MP4DownloadTransfer(staging: staging, origin: url, diagnostic: { [weak self] resource, labels, numbers in
                    Task { @MainActor in
                        guard let self else { return }
                        var related=context
                        if let resource { related?.resource=DiagnosticResource(resource); related?.mediaID=self.diagnostics?.reference(resource.absoluteString) }
                        self.diagnostics?.record(.transferMetrics,context:related,labels:labels,numbers:numbers)
                    }
                }) { [weak self] bytes, total in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.received = bytes; self.expected = total
                        if Date().timeIntervalSince(self.lastDiagnosticUpdate)>2 {
                            self.lastDiagnosticUpdate=Date()
                            self.diagnostics?.record(.transfer,context:context,labels:["phase":"progress"],numbers:["receivedBytes":Double(bytes),"expectedBytes":Double(total)])
                        }
                    }
                }
                let file = try await transfer.run(request, cookies: cookies)
                try Task.checkCancellation()
                let hint = media.formatHint ?? VideoFormatDetection.persistentHint(source: media.source, title: media.title, pageURL: media.pageURL)
                try await self.saveCheckedVideo(file, id: token, name: media.title, hint: hint)
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"complete"],numbers:["receivedBytes":Double(self.received)])
            } catch is CancellationError {
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"cancelled"])
                if self.generation == token { self.status = "Download cancelled" }
            } catch {
                if self.generation == token {
                    self.diagnostics?.record(.transfer,context:context,labels:["phase":"failed"],codes:PlaybackDiagnostics.failure(error))
                    let ns = error as NSError
                    self.failureCode = error is MP4DownloadTransfer.TransferError ? "transfer-validation" : (ns.domain == NSURLErrorDomain ? "network-\(ns.code)" : "file-or-media-validation")
                    self.status = "Download failed"
                    if case MP4DownloadTransfer.TransferError.http(let status) = error {
                        self.failureCode = "http-\(status)"
                        self.message = "The website returned HTTP \(status) instead of a video. Reopen its page and check that this public preview is still available."
                    }
                    else if case MP4DownloadTransfer.TransferError.redirect = error {
                        self.failureCode = "redirect-unsupported"
                        self.message = "This download has an unsupported redirect. Only secure redirects without embedded credentials are supported. Reopen the webpage or import an authorised MP4 from Files."
                    }
                    else if case MP4DownloadTransfer.TransferError.response = error {
                        self.failureCode = "unsupported-response"
                        self.message = "The link did not return a supported MP4 video response. Reopen the webpage and choose a fresh MP4 source."
                    }
                    else if case MP4DownloadTransfer.TransferError.notMP4 = error {
                        self.failureCode = "unsupported-mp4"
                        self.message = "The response could not be verified as a playable, unprotected MP4. Reopen the webpage and try another supplied source."
                    }
                    else if let hint = PlaybackDiagnostics.failureHint(error) { self.message = hint }
                    else if case MP4DownloadTransfer.TransferError.tooLarge = error { self.message = "This video exceeds the 8 GB download limit." }
                    else if case MP4DownloadTransfer.TransferError.storage = error { self.message = "There isn’t enough free storage. Free some space and try again." }
                    else { self.message = "The video could not be saved. Reopen its webpage and try a fresh MP4 source. Protected videos and sources requiring additional website requests are unsupported." }
                }
            }
        }
    }
    @discardableResult
    func startHLS(_ media:MediaCandidate,cookies:[HTTPCookie],userAgent:String?,cookieProvider:(@MainActor (URL) async -> [HTTPCookie])? = nil,parent:DiagnosticContext? = nil,completion:(@MainActor (SavedVideo?,String?)->Void)? = nil) -> Bool {
        guard !isDownloading,!needsRepair,HLSOfflineLibrary.accepts(media) else { return false }
        let token=UUID();generation=token
        diagnosticContext=diagnostics.flatMap { $0.isEnabled ? $0.begin(.mp4Download,media:media,parent:parent):nil }
        let context=diagnosticContext
        received=0;expected=0;message=nil;failureCode="none";isDownloading=true;isImporting=false
        status="Saving a compatible MP4… Keep VisionStream open."
        let input=stagingRoot.appendingPathComponent(token.uuidString+".ts")
        let output=stagingRoot.appendingPathComponent(token.uuidString+".mp4")
        diagnostics?.record(.transfer,context:context,labels:["phase":"foreground-hls-started"])
        work=Task { @MainActor [weak self] in
            guard let self else { return }
            var saved:SavedVideo?,resultMessage:String?
            defer {
                for file in [input,output,input.deletingPathExtension().appendingPathExtension("part")] { try? FileManager.default.removeItem(at:file) }
                if self.generation==token { self.isDownloading=false;self.work=nil }
                completion?(saved,resultMessage)
            }
            do {
                let duration=try await ClearHLSDownloadTransfer.run(media:media,input:input,output:output,cookies:cookies,userAgent:userAgent,cookieProvider:cookieProvider,history:self.diagnostics,context:context) { [weak self] bytes,part,count in
                    guard let self,self.generation==token else { return }
                    self.received=bytes;self.status="Saving video part \(part) of \(count)… Keep VisionStream open."
                }
                try Task.checkCancellation()
                self.status="Checking the MP4 copy…"
                try await self.saveCheckedVideo(output,id:token,name:media.title,hint:media.formatHint ?? VideoFormatDetection.persistentHint(source:media.source,title:media.title,pageURL:media.pageURL),expectedDuration:duration)
                saved=self.videos.first { $0.id==token }
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"foreground-hls-complete"],numbers:["savedBytes":Double(saved?.bytes ?? 0)])
            } catch is CancellationError {
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"foreground-hls-cancelled"])
                if self.generation==token { self.status="Save cancelled" }
            } catch {
                guard self.generation==token else { return }
                self.failureCode="hls-foreground-save";self.status="Save failed"
                var codes=PlaybackDiagnostics.failure(error)
                if case ClearHLSDownloadTransfer.Failure.http(let code,let sequence)=error {
                    codes.append("HTTP:\(code)")
                    let resource=sequence.map { "video segment \($0)" } ?? "playlist"
                    self.message="The website returned HTTP \(code) for the HLS \(resource). Reopen its page for a fresh source."
                } else if error is ClearHLSPlan.PlanError || error is ClearHLSDownloadTransfer.Failure {
                    self.message="This HLS source cannot be saved as an MP4 copy. The fallback supports clear, on-demand MPEG-TS with combined audio and video. Check available storage or try a separate MP4."
                } else if case MP4DownloadTransfer.TransferError.tooLarge=error { self.message="This save exceeds the available temporary storage or file-size limit." }
                else if case MP4DownloadTransfer.TransferError.storage=error { self.message="There isn’t enough storage for the temporary stream and MP4 copy. Free some space and try again." }
                else { self.message="The stream could not be saved as a compatible MP4. Playback details records the failing request or conversion stage." }
                resultMessage=self.message
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"foreground-hls-failed"],codes:codes)
            }
        }
        return true
    }
    private func saveCheckedVideo(_ file: URL, id: UUID, name: String, hint: VideoFormatHint?,expectedDuration:Double? = nil) async throws {
        status = "Checking video…"
        let asset = AVURLAsset(url: file)
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { asset.cancelLoading() }
        }
        defer { deadline.cancel() }
        let (playable, protected) = try await withTaskCancellationHandler {
            try await asset.load(.isPlayable, .hasProtectedContent)
        } onCancel: { asset.cancelLoading() }
        try Task.checkCancellation()
        guard generation == id, playable, !protected else { throw MP4DownloadTransfer.TransferError.notMP4 }
        if let expectedDuration {
            let duration=try await asset.load(.duration)
            guard duration.seconds.isFinite,abs(duration.seconds-expectedDuration)<=max(1,expectedDuration*0.001) else { throw MP4DownloadTransfer.TransferError.notMP4 }
            try Task.checkCancellation()
            guard generation==id else { throw CancellationError() }
        }
        _ = try store.commit(staging: file, id: id, name: name, hint: hint, context: diagnostics?.isEnabled == true ? diagnosticContext:nil)
        videos = try store.load(); status = "Saved for offline viewing"
    }
    func importVideo(_ source: URL) {
        guard !isDownloading else { message = "Wait for the current operation, or cancel it first."; return }
        guard !needsRepair else { message = "Repair the saved-video library before importing another video."; return }
        guard source.isFileURL else { message = "Choose an MP4 video in Files."; return }
        diagnosticContext=diagnostics.flatMap { $0.isEnabled ? $0.begin(.fileImport,media:.init(id:UUID().uuidString,source:source.absoluteString)):nil }
        let context=diagnosticContext
        let token = UUID(); generation = token
        isDownloading = true; isImporting = true; received = 0; expected = 0; message = nil; failureCode = "none"; status = "Importing video…"
        let staging = stagingRoot.appendingPathComponent(token.uuidString + ".mp4")
        let scoped = source.startAccessingSecurityScopedResource()
        work = Task { @MainActor [weak self] in
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: staging)
                if self.generation == token { self.isDownloading = false; self.isImporting = false; self.work = nil }
            }
            do {
                try await VideoFileCopy.run(from: source, to: staging) { [weak self] bytes, total in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.received = bytes; self.expected = total
                        if Date().timeIntervalSince(self.lastDiagnosticUpdate)>2 {
                            self.lastDiagnosticUpdate=Date()
                            self.diagnostics?.record(.transfer,context:context,labels:["phase":"progress"],numbers:["receivedBytes":Double(bytes),"expectedBytes":Double(total)])
                        }
                    }
                }
                let name = source.deletingPathExtension().lastPathComponent
                try await self.saveCheckedVideo(staging, id: token, name: name, hint: VideoFormatDetection.hint(source: source.absoluteString, title: name))
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"import-completed"],numbers:["receivedBytes":Double(self.received)])
            } catch {
                guard self.generation == token else { return }
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"import-failed"],codes:PlaybackDiagnostics.failure(error))
                self.failureCode = "file-import-failed"; self.status = "Import failed"
                self.message = "This file could not be imported. Choose a playable, unprotected MP4 smaller than 8 GB and check available storage. The original file was kept."
            }
        }
    }
    func clearDiagnosticLinks() throws {
        videos=try store.clearDiagnosticLinks();diagnosticContext=nil
    }
    func repair() {
        guard !isDownloading else { message = "Wait for the current operation, or cancel it first."; return }
        do {
            videos = try store.recover(); needsRepair = false; message = nil
            status = "Library repaired · \(videos.count) saved videos. Some names may have been reset."
        } catch { message = "The library could not be repaired. Your original saved files have been kept." }
    }
    func cancel() { diagnostics?.record(.controls,context:diagnosticContext,labels:["action":"transfer-cancel"]); work?.cancel(); generation = UUID(); work = nil; isDownloading = false; isImporting = false; status = "Operation cancelled" }
    func remove(_ video: SavedVideo) {
        do { try store.remove(video); videos = try store.load(); message = nil }
        catch { message = "The saved video could not be removed. Try again." }
    }
}
