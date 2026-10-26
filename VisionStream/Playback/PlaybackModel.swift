import AVFoundation
import Observation

@MainActor @Observable
final class PlaybackModel {
    let player = AVPlayer()
    @ObservationIgnored weak var diagnostics: SessionDiagnostics?
    private(set) var diagnosticContext: DiagnosticContext?
    private var lastMetrics = Date.distantPast
    private var loggedErrorEvents = 0
    private var metricEvents: Task<Void,Never>?
    private(set) var videoOutput: AVPlayerItemVideoOutput?
    private(set) var isPreparing = false
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var seekStart: Double = 0
    private(set) var seekEnd: Double = 0
    private(set) var isBuffering = false
    private(set) var isSeeking = false
    private(set) var isReady = false
    private(set) var isAudioInterrupted = false
    private(set) var systemNotice: String?
    private var resumeAfterInterruption = false
    private var audioResumeID = UUID()
    #if os(visionOS)
    @ObservationIgnored private var audioEvents: PlaybackAudioEvents?
    #endif
    private(set) var diagnosticStage = "not-attempted" { didSet { if diagnosticStage != oldValue { trace(.playback, action: diagnosticStage) } } }
    private(set) var failureCodes: [String] = []
    private(set) var failureReason: PlaybackDiagnostics.FailureReason = .none
    private(set) var itemStatusAtFailure: PlaybackDiagnostics.ItemStatus = .notCreated
    private(set) var errorLogCodes: [String] = []
    private(set) var mediaHTTPStatus: Int?
    private(set) var diagnosticCandidate: MediaCandidate?
    private(set) var browserUserAgentApplied = false
    var errorMessage: String?
    var projection: VideoProjection = .vr180 { didSet { if projection != oldValue { trace(.format, action: "projection-changed") } } }
    var layout: StereoLayout = .mono { didSet { if layout != oldValue { trace(.format, action: "layout-changed") } } }
    var flatScreen = true
    var presentation: VideoPresentation {
        get { flatScreen ? .screen : (projection == .vr180 ? .vr180 : .vr360) }
        set {
            flatScreen = newValue == .screen
            if newValue == .vr180 { projection = .vr180 }
            if newValue == .vr360 { projection = .vr360 }
        }
    }
    private(set) var decodedWidth = 0
    private(set) var decodedHeight = 0
    var swapEyes = false { didSet { if swapEyes != oldValue { trace(.controls, action: "swap-eyes") } } }
    var flipY = false { didSet { if flipY != oldValue { trace(.controls, action: "flip-vertical") } } }
    private(set) var recenterID = 0
    private(set) var recenterUpright = false
    private(set) var viewingTilt = 0.0
    private(set) var recenterCountdown: Int?
    @ObservationIgnored private var recenterTask: Task<Void, Never>?
    var immersiveActive = false
    var openingImmersive = false
    private var asset: AVURLAsset?
    private var generation = UUID()
    private var seekGeneration = UUID()
    private var ticker: Task<Void, Never>?
    private var frameDeadline: Date?
    private var hasSeenFrame = false
    var isOffline: Bool { asset?.url.isFileURL == true }
    var quality: PlaybackQuality = .highest { didSet { if quality != oldValue { trace(.quality, action: "preference-changed") } } }
    private(set) var qualityStatus = "Source quality"
    private(set) var selectedWidth = 0
    private(set) var selectedHeight = 0
    var automaticallyDetectFormat: Bool { didSet { if automaticallyDetectFormat != oldValue { trace(.format, action: automaticallyDetectFormat ? "automatic-enabled" : "manual-enabled") } } }
    private(set) var formatStatus = "Format not identified" { didSet { if formatStatus != oldValue { trace(.format, action: formatStatus) } } }
    private var formatVotes: [StereoLayout] = []
    private var lastAnalysis = Date.distantPast
    private var knownProjection = false
    private var knownLayout = false
    private var nativeProjectionIdentified = false
    private var embeddedFormatHint: VideoFormatHint?
    private var formatInspection: Task<Void, Never>?
    private var metadataRequest: HLSQualityRequest?
    private var qualityRequest: HLSQualityRequest?
    private var qualityChange: Task<Void, Never>?
    private var originalCandidate: MediaCandidate?
    private var playbackCookies: [HTTPCookie] = []
    private var playbackAgent: String?
    private var cookieProvider: (@MainActor (URL) async -> [HTTPCookie])?
    private var pauseAfterFrame = false
    private let preparationTimeout: Duration

    init(preparationTimeout: Duration = .seconds(30), automaticallyDetectFormat: Bool = false) {
        self.automaticallyDetectFormat = automaticallyDetectFormat
        self.preparationTimeout = preparationTimeout
        player.automaticallyWaitsToMinimizeStalling = true
        #if os(visionOS)
        audioEvents = PlaybackAudioEvents { [weak self] event in
            Task { @MainActor [weak self] in await self?.handleAudioEvent(event) }
        }
        #endif
    }

    func prepare(_ candidate: MediaCandidate, cookies: [HTTPCookie], userAgent: String? = nil, cookieProvider: (@MainActor (URL) async -> [HTTPCookie])? = nil) async -> Bool {
        await prepareVerified(candidate, cookies: cookies, userAgent: userAgent, cookieProvider: cookieProvider)
    }

    /// File URLs never come from website detection or a pasted address. Only
    /// completed files verified by the owned offline catalogue reach this path.
    func prepareSavedVideo(_ video: SavedVideo, store: OfflineVideoStore) async -> Bool {
        guard let url = store.file(for: video) else {
            errorMessage = "This saved video is missing. Remove it from Downloads and save it again."; return false
        }
        var hint = video.formatHint
        if let handle = try? FileHandle(forReadingFrom: url) {
            let prefix = try? handle.read(upToCount: 262_144)
            try? handle.close()
            if let prefix, let embedded = MP4SphericalMetadata.hint(prefix: prefix) { hint = embedded }
        }
        let candidate = MediaCandidate(id: video.id.uuidString, source: url.absoluteString, mimeType: "video/mp4", title: video.name, formatHint: hint)
        return await prepareVerified(candidate, cookies: [], userAgent: nil, cookieProvider: nil, ownedLocalFile: true, parentContext: video.diagnosticContext)
    }

    func prepareSavedHLS(_ video: SavedHLSVideo, store: HLSOfflineStore) async -> Bool {
        guard let url = store.package(for: video), AVURLAsset(url: url).assetCache?.isPlayableOffline == true else {
            errorMessage = "This saved HLS video is missing or no longer available offline. Remove it and save it again."; return false
        }
        let candidate = MediaCandidate(id: video.id.uuidString, source: url.absoluteString, mimeType: "application/vnd.apple.mpegurl", title: video.name, formatHint: video.hint)
        return await prepareVerified(candidate, cookies: [], userAgent: nil, cookieProvider: nil, ownedLocalFile: true, parentContext: video.diagnosticContext)
    }

    private func prepareVerified(_ candidate: MediaCandidate, cookies: [HTTPCookie], userAgent: String?, cookieProvider: (@MainActor (URL) async -> [HTTPCookie])?, ownedLocalFile: Bool = false, parentContext: DiagnosticContext? = nil) async -> Bool {
        guard !Task.isCancelled else { return false }
        stop(cancelQualityChange: false)
        diagnosticContext = diagnostics?.begin(.playback, media: candidate, parent: parentContext)
        lastMetrics = .distantPast; loggedErrorEvents = 0
        diagnostics?.record(.playback, context: diagnosticContext, labels: ["phase":"request-options"], numbers: ["cookieCount":Double(cookies.count),"userAgentApplied":userAgent == nil ? 0:1])
        originalCandidate = candidate; playbackCookies = cookies; playbackAgent = userAgent
        self.cookieProvider = cookieProvider
        selectedWidth = 0; selectedHeight = 0; qualityStatus = "Source quality"
        formatVotes = []; lastAnalysis = .distantPast; knownProjection = false; knownLayout = false; nativeProjectionIdentified = false; embeddedFormatHint = nil
        if automaticallyDetectFormat {
            presentation = .screen; layout = .mono; swapEyes = false; flipY = false
            formatStatus = "Format not identified"
            applyInitialFormat(candidate)
        }
        diagnosticStage = "validating-candidate"
        diagnosticCandidate = candidate
        failureCodes = []; mediaHTTPStatus = nil
        failureReason = .none; itemStatusAtFailure = .notCreated; errorLogCodes = []
        browserUserAgentApplied = false
        decodedWidth = 0; decodedHeight = 0
        guard let url = URL(string: candidate.source), ownedLocalFile ? url.isFileURL : candidate.compatibility == .candidate else {
            diagnosticStage = "unsupported-candidate"
            failureReason = .unsupportedCandidate
            errorMessage = candidate.compatibility.reason ?? "Invalid media URL."; return false
        }
        let token = generation
        return await withTaskCancellationHandler {
            await load(candidate, url: url, cookies: cookies, userAgent: userAgent, token: token)
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.stop()
            }
        }
    }

    private func load(_ candidate: MediaCandidate, url: URL, cookies: [HTTPCookie], userAgent: String?, token: UUID) async -> Bool {
        guard generation == token, !Task.isCancelled else { return false }
        isPreparing = true
        diagnosticStage = "loading-asset"
        errorMessage = nil
        // Every unfinished path releases media before returning, including task cancellation.
        defer { if generation == token, isPreparing { stop() } }
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.preparationTimeout ?? .seconds(30))
            guard !Task.isCancelled, let self, self.generation == token, self.isPreparing else { return }
            // Capture diagnostics before stop() removes the item and cancels loading.
            self.recordFailure(self.player.currentItem?.error, item: self.player.currentItem)
            self.fail("Preparation timed out before the stream became ready. The native player did not finish loading; this alone does not identify a connection, access or format problem.", reason: .preparationTimeout)
        }
        defer { timeout.cancel() }
        do {
            var selectedURL = url
            if url.isFileURL { qualityStatus = "Saved video" }
            var selectedCookies = cookies
            if !url.isFileURL, quality == .highest, candidate.normalizedMIMEType.contains("mpegurl") || url.pathExtension.lowercased() == "m3u8" {
                qualityStatus = "Adaptive · inspecting quality"
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                for (key, value) in HTTPCookie.requestHeaderFields(with: CookieScope.matching(cookies, url: url)) { request.setValue(value, forHTTPHeaderField: key) }
                if let userAgent, userAgent.utf8.count <= 1024, userAgent.rangeOfCharacter(from: .controlCharacters) == nil { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
                let probe = HLSQualityRequest(); qualityRequest = probe
                let data: Data?
                do { data=try await probe.load(request) }
                catch { data=nil; diagnostics?.record(.quality,context:diagnosticContext,labels:["phase":"manifest-inspection-failed"],codes:PlaybackDiagnostics.failure(error)) }
                guard generation == token, !Task.isCancelled else { return false }
                let inspected=data.flatMap { try? HLSManifest(data:$0,base:url) }
                if let inspected {
                    for variant in inspected.variants {
                        var available=diagnosticContext
                        available?.resource=DiagnosticResource(variant.url); available?.mediaID=diagnostics?.reference(variant.url.absoluteString)
                        diagnostics?.record(.quality,context:available,labels:["phase":"advertised-variant"],numbers:["width":Double(variant.width),"height":Double(variant.height),"indicatedBitrate":Double(variant.bandwidth),"variantCount":Double(inspected.variants.count)])
                    }
                }
                if let best = inspected?.highestIndependentVariant {
                    let browserCookies = await cookieProvider?(best.url) ?? cookies
                    guard generation == token, !Task.isCancelled else { return false }
                    selectedURL = best.url; selectedWidth = best.width; selectedHeight = best.height
                    let issued = probe.cookies(for: best.url)
                    selectedCookies = CookieScope.matching(browserCookies, url: best.url).filter { old in
                        !issued.contains { $0.name == old.name && $0.domain == old.domain && $0.path == old.path }
                    } + issued
                    qualityStatus = "Highest selected"
                } else { qualityStatus = "Adaptive · source controls quality"; diagnostics?.record(.quality,context:diagnosticContext,labels:["decision":"retain-original-adaptive-source"]) }
                qualityRequest = nil
            } else if !url.isFileURL, candidate.normalizedMIMEType.contains("mpegurl") || url.pathExtension.lowercased() == "m3u8" {
                qualityStatus = "Adaptive"
            }
            guard generation == token, !Task.isCancelled else { return false }
            // Public AVFoundation API only. No Referer spoofing, undocumented header keys, or proxy.
            var options: [String: Any] = [AVURLAssetHTTPCookiesKey: selectedCookies]
            if let userAgent, !userAgent.isEmpty, userAgent.utf8.count <= 1024,
               userAgent.rangeOfCharacter(from: .controlCharacters) == nil {
                options[AVURLAssetHTTPUserAgentKey] = userAgent
                browserUserAgentApplied = true
            }
            let asset = AVURLAsset(url: selectedURL, options: options)
            self.asset = asset
            let (playable, protected) = try await asset.load(.isPlayable, .hasProtectedContent)
            diagnostics?.record(.playback, context: diagnosticContext, labels: ["phase":"asset-properties"], numbers: ["playable":playable ? 1:0,"protected":protected ? 1:0])
            guard generation == token, !Task.isCancelled else { return false }
            guard !protected else {
                fail("This asset is protected. VisionStream has no DRM licence integration. Watch it on the website.", reason: .protectedAsset); return false
            }
            guard playable else {
                fail("AVFoundation cannot play this source. The codec, container, authentication, or URL may be unsupported.", reason: .unplayableAsset); return false
            }
            diagnostics?.record(.quality, context: diagnosticContext, labels: ["phase":"rendition-selected","quality":quality.rawValue], numbers: ["selectedWidth":Double(selectedWidth),"selectedHeight":Double(selectedHeight)])
            if let selectedURL = self.asset?.url, var selectedContext = diagnosticContext {
                selectedContext.mediaID = diagnostics?.reference(selectedURL.absoluteString)
                selectedContext.resource = DiagnosticResource(selectedURL)
                diagnostics?.record(.quality, context: selectedContext, labels: ["phase":"selected-resource"])
            }
            let item = AVPlayerItem(asset: asset)
            if diagnostics != nil {
                let context=diagnosticContext
                metricEvents=Task { @MainActor [weak self] in
                    do {
                        for try await event in item.allMetrics() {
                            guard !Task.isCancelled, let self, self.generation==token else { return }
                            NativeDiagnosticMetrics.record(event,history:self.diagnostics,context:context)
                        }
                    } catch {
                        guard !Task.isCancelled, let self, self.generation == token else { return }
                        self.diagnostics?.record(.playerError,context:context,labels:["phase":"metric-stream-ended"],codes:PlaybackDiagnostics.failure(error))
                    }
                }
            }
            diagnosticStage = "waiting-for-player"
            item.preferredForwardBufferDuration = 5
            item.preferredPeakBitRate = 0
            item.preferredMaximumResolution = .zero
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()
            ])
            item.add(output)
            videoOutput = output
            player.replaceCurrentItem(with: item)
            while item.status == .unknown {
                try await Task.sleep(for: .milliseconds(100))
                guard generation == token else { return false }
            }
            guard generation == token, !Task.isCancelled else { return false }
            guard item.status == .readyToPlay else {
                recordFailure(item.error, item: item)
                fail(PlaybackDiagnostics.failureHint(item.error) ?? "The native player rejected the stream. Check website access, URL expiry, and MP4/HLS codec support. No media was downloaded as a file.", reason: .playerRejected)
                return false
            }
            if automaticallyDetectFormat, let track = try? await asset.loadTracks(withMediaType: .video).first,
               let formats = try? await track.load(.formatDescriptions), let format = formats.first {
                let codec=CMFormatDescriptionGetMediaSubType(format)
                diagnostics?.record(.playback,context:diagnosticContext,labels:["phase":"video-format","codec":String(format:"%08x",codec)])
                let projection = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ProjectionKind) as? String
                let packing = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ViewPackingKind) as? String
                let p: VideoProjection? = projection == (kCMFormatDescriptionProjectionKind_HalfEquirectangular as String) ? .vr180 :
                    projection == (kCMFormatDescriptionProjectionKind_Equirectangular as String) ? .vr360 : nil
                let l: StereoLayout? = packing == (kCMFormatDescriptionViewPackingKind_SideBySide as String) ? .sideBySide :
                    packing == (kCMFormatDescriptionViewPackingKind_OverUnder as String) ? .topBottom : nil
                if p != nil { nativeProjectionIdentified = true }
                if p != nil || l != nil {
                    let hint = VideoFormatHint(projection: p, layout: l, evidence: .metadata)
                    embeddedFormatHint = hint; applyFormat(hint)
                }
            }
            guard generation == token, !Task.isCancelled else { return false }
            #if os(visionOS)
            try await PlaybackAudioSession.shared.activate(for: token)
            guard generation == token, !Task.isCancelled else {
                await PlaybackAudioSession.shared.deactivate(for: token)
                return false
            }
            #endif
            guard generation == token, !Task.isCancelled else { return false }
            updateTimeline()
            if candidate.currentTime.isFinite, candidate.currentTime > 0, seekEnd > seekStart {
                let target = min(max(candidate.currentTime, seekStart), seekEnd)
                await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            guard generation == token, !Task.isCancelled else { return false }
            isPreparing = false
            isReady = true
            diagnosticStage = "player-ready"
            startTicker()
            if automaticallyDetectFormat, !selectedURL.isFileURL, !nativeProjectionIdentified, candidate.normalizedMIMEType == "video/mp4" || ["mp4", "m4v"].contains(selectedURL.pathExtension.lowercased()) {
                inspectSphericalMetadata(url: selectedURL, cookies: selectedCookies, userAgent: userAgent, token: token)
            }
            return true
        } catch {
            guard generation == token else { return false }
            guard !Task.isCancelled else { return false }
            recordFailure(error, item: player.currentItem)
            fail(PlaybackDiagnostics.failureHint(error) ?? "The stream could not be opened. Check the connection and website access. Signed links, required headers, and unsupported codecs can prevent native playback.", reason: .assetLoadFailed)
            return false
        }
    }

    private func inspectSphericalMetadata(url: URL, cookies: [HTTPCookie], userAgent: String?, token: UUID) {
        let requestClient = HLSQualityRequest(kind: .mp4Prefix)
        metadataRequest = requestClient
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("bytes=0-\(MP4SphericalMetadata.maximumPrefixBytes - 1)", forHTTPHeaderField: "Range")
        for (key, value) in HTTPCookie.requestHeaderFields(with: CookieScope.matching(cookies, url: url)) { request.setValue(value, forHTTPHeaderField: key) }
        if let userAgent, userAgent.utf8.count <= 1024, userAgent.rangeOfCharacter(from: .controlCharacters) == nil { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        formatInspection = Task { @MainActor [weak self] in
            var data: Data?
            for attempt in 0..<2 {
                let client = attempt == 0 ? requestClient : HLSQualityRequest(kind: .mp4Prefix)
                guard !Task.isCancelled, self?.generation == token else { return }
                self?.metadataRequest = client
                do { data = try await client.load(request); break }
                catch {
                    // A slow/transient connection must not permanently strand a
                    // known spherical stream on Screen. Never retry server,
                    // auth, redirect, size or range-validation rejections.
                    guard attempt == 0, let error = error as? URLError,
                          [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code) else { break }
                }
            }
            guard !Task.isCancelled, let self, self.generation == token, self.isReady else { return }
            self.metadataRequest = nil
            // Metadata outranks a filename. User changes made during inspection win.
            if let data, let hint = MP4SphericalMetadata.hint(prefix: data) {
                self.embeddedFormatHint = hint
                if self.automaticallyDetectFormat { self.applyFormat(hint) }
            }
        }
    }

    func changeQuality(_ value: PlaybackQuality) {
        guard quality != value else { return }
        quality = value
        guard var candidate = originalCandidate, isReady, URL(string: candidate.source)?.isFileURL != true else { return }
        let resume = isPlaying || isBuffering
        candidate.currentTime = player.currentTime().seconds
        let cookies = playbackCookies, agent = playbackAgent, provider = cookieProvider
        qualityChange?.cancel()
        qualityChange = Task { @MainActor [weak self] in
            guard let self else { return }
            if await self.prepare(candidate, cookies: cookies, userAgent: agent, cookieProvider: provider), !Task.isCancelled {
                self.pauseAfterFrame = !resume
                self.play()
            }
        }
    }

    func manualFormat() { automaticallyDetectFormat = false; formatStatus = "Manual format" }
    func enableAutomaticFormat() {
        automaticallyDetectFormat = true; formatVotes = []; lastAnalysis = .distantPast; knownProjection = false; knownLayout = false
        guard let candidate = originalCandidate else { return }
        presentation = .screen; layout = .mono; formatStatus = "Format not identified"
        applyInitialFormat(candidate)
        applyFormat(embeddedFormatHint)
        if embeddedFormatHint == nil, metadataRequest == nil, isReady, let url = asset?.url, !url.isFileURL,
           candidate.normalizedMIMEType == "video/mp4" || ["mp4", "m4v"].contains(url.pathExtension.lowercased()) {
            inspectSphericalMetadata(url: url, cookies: playbackCookies, userAgent: playbackAgent, token: generation)
        }
    }
    private func applyInitialFormat(_ candidate: MediaCandidate) {
        // Partial element metadata must not discard a separately labelled
        // component. The element's explicit values take precedence per field.
        applyFormat(VideoFormatDetection.hint(source: candidate.source, title: candidate.title))
        applyFormat(candidate.formatHint)
    }
    private func applyFormat(_ hint: VideoFormatHint?) {
        guard automaticallyDetectFormat, let hint else { return }
        if hint.evidence == .context { return }
        if let projection = hint.projection { self.projection = projection; flatScreen = false; knownProjection = true }
        if let layout = hint.layout { self.layout = layout; knownLayout = true }
        formatStatus = hint.evidence == .imageMatch ? "Auto · image match" : (hint.evidence == .metadata ? "Auto · metadata" : "Auto · source label")
    }
    func observeFormatFrame(_ buffer: CVPixelBuffer) {
        guard automaticallyDetectFormat, !(knownProjection && knownLayout), !(knownLayout && layout == .mono),
              Date().timeIntervalSince(lastAnalysis) > 0.35, formatVotes.count < 12 else { return }
        lastAnalysis = Date()
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA, width >= 64, height >= 32 else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytes = base.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(buffer)
        let luma = VideoFormatDetection.sampleLuma(bgra: .init(start: bytes, count: stride * height), width: width, height: height, bytesPerRow: stride)
        let analysis=VideoFormatDetection.analysePacking(luma:luma,width:128,height:64)
        let match=analysis.layout
        diagnostics?.record(.format, context: diagnosticContext, labels: ["decision":match == nil ? "inconclusive" : "image-match-candidate","packing":match?.rawValue ?? "unknown"], numbers: ["formatVotes":Double(formatVotes.count),"sbsScore":(analysis.sideBySideScore*10).rounded()/10,"tbScore":(analysis.topBottomScore*10).rounded()/10,"sbsRegions":Double(analysis.sideBySideRegions),"tbRegions":Double(analysis.topBottomRegions),"expandedSearch":analysis.expandedSearch ? 1:0], deduplicate:"format-analysis-" + (diagnosticContext?.attemptID.uuidString ?? "none"))
        guard let packing = match, !knownLayout || packing == layout else { formatVotes = []; return }
        formatVotes.append(packing)
        guard formatVotes.suffix(3).count == 3, formatVotes.suffix(3).allSatisfy({ $0 == packing }),
              let projection = knownProjection ? self.projection : VideoFormatDetection.projection(width: width, height: height, layout: packing) else { return }
        applyFormat(.init(projection: projection, layout: packing, evidence: .imageMatch))
    }

    func play() {
        trace(.controls, action: "play")
        guard isReady, !isAudioInterrupted else { return }
        systemNotice = nil; audioResumeID = UUID(); resumeAfterInterruption = false
        frameDeadline = Date().addingTimeInterval(15)
        player.play()
    }
    func pause() { trace(.controls, action: "pause"); player.pause(); isPlaying = false; frameDeadline = nil; audioResumeID = UUID(); resumeAfterInterruption = false }
    #if os(visionOS)
    func handleAudioEvent(_ event: PlaybackAudioEvents.Event) async {
        guard isReady else { return }
        switch event {
        case .began:
            guard !isAudioInterrupted else { return }
            let resume = player.timeControlStatus != .paused || isPlaying
            pause(); isAudioInterrupted = true; resumeAfterInterruption = resume
            systemNotice = "Playback paused by the system."
        case .ended(let allowed):
            guard isAudioInterrupted else { return }
            isAudioInterrupted = false
            let resume = allowed && resumeAfterInterruption
            resumeAfterInterruption = false
            guard resume else { systemNotice = "Press Play when you’re ready to continue."; return }
            let token = generation, request = audioResumeID
            do {
                try await PlaybackAudioSession.shared.activate(for: token)
                guard generation == token, audioResumeID == request, isReady, !isAudioInterrupted else { return }
                play()
            } catch {
                guard generation == token, audioResumeID == request, isReady else { return }
                systemNotice = "Audio could not resume. Return to the page and try again."
            }
        case .disconnected:
            pause(); systemNotice = "Audio output disconnected. Press Play to continue."
        case .reset:
            fail("The audio system restarted. Return to the page and open the video again.")
        }
    }
    #endif
    func toggle() {
        if player.timeControlStatus == .paused {
            // The published timeline can lag the end notification by one tick.
            let position = isSeeking ? elapsed : player.currentTime().seconds
            if duration > 0, position.isFinite, position >= duration - 0.1 { seek(to: seekStart) }
            play()
        } else { pause() }
    }
    func seek(to seconds: Double) {
        guard isReady, seconds.isFinite, seekEnd > seekStart else { return }
        let target = min(max(seconds, seekStart), seekEnd)
        diagnostics?.record(.controls, context: diagnosticContext, labels: ["action":"seek"], numbers: ["target":target,"elapsed":elapsed])
        let token = generation, seekToken = UUID()
        seekGeneration = seekToken; isSeeking = true; elapsed = target
        // The convenience overload permits an arbitrarily distant keyframe.
        // Controls commit a seek only after scrubbing, so request the actual time.
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.seekGeneration == seekToken else { return }
                self.isSeeking = false; self.updateTimeline()
            }
        }
    }
    func skip(_ seconds: Double) { seek(to: (isSeeking ? elapsed : player.currentTime().seconds) + seconds) }
    func receivedFrame(width: Int = 0, height: Int = 0) {
        // A GPU completion may arrive after a player failure or cancellation.
        guard isReady else { return }
        #if targetEnvironment(simulator)
        if SimulatorTestMonitor.isEnabled { SimulatorTestMonitor.framesReceived += 1 }
        #endif
        if !hasSeenFrame || decodedWidth != width || decodedHeight != height {
            diagnostics?.record(.decodedFrame, context: diagnosticContext, numbers: ["decodedWidth":Double(width),"decodedHeight":Double(height)])
        }
        hasSeenFrame = true; frameDeadline = nil; diagnosticStage = "decoded-frame-received"
        if width > 0, height > 0 { decodedWidth = width; decodedHeight = height }
        if pauseAfterFrame { pauseAfterFrame = false; pause() }
    }
    func recenter(upright: Bool = false) {
        cancelScheduledRecenter()
        trace(.controls, action: upright ? "reset-upright" : "recenter")
        recenterUpright = upright; viewingTilt = 0; recenterID += 1
    }

    func setViewingTilt(_ degrees: Double) {
        viewingTilt = ViewingPose.boundedTilt(degrees)
    }

    func scheduleRecenter() {
        cancelScheduledRecenter()
        recenterCountdown = 3
        recenterTask = Task { @MainActor [weak self] in
            for remaining in [3, 2, 1] {
                guard !Task.isCancelled else { return }
                self?.recenterCountdown = remaining
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
            }
            self?.recenter()
        }
    }

    func cancelScheduledRecenter() {
        recenterTask?.cancel(); recenterTask = nil; recenterCountdown = nil
    }

    func resetViewingPosition() {
        cancelScheduledRecenter()
        recenterUpright = false; viewingTilt = 0
    }

    func cancelPreparation() { if isPreparing || (isReady && !immersiveActive) { stop() } }

    func resetDiagnosticsWhenIdle() {
        guard !isPreparing, !isReady, !immersiveActive else { return }
        diagnosticStage = "not-attempted"; failureCodes = []; mediaHTTPStatus = nil; errorMessage = nil
        failureReason = .none; itemStatusAtFailure = .notCreated; errorLogCodes = []
        diagnosticCandidate = nil
        browserUserAgentApplied = false
        decodedWidth = 0; decodedHeight = 0
    }

    func stop(cancelQualityChange: Bool = true) {
        metricEvents?.cancel(); metricEvents=nil
        if isReady || isPreparing { trace(.playback, action: "stopped") }
        isAudioInterrupted = false; systemNotice = nil; resumeAfterInterruption = false; audioResumeID = UUID()
        if cancelQualityChange {
            qualityChange?.cancel(); qualityChange = nil
            originalCandidate = nil; playbackCookies = []; playbackAgent = nil; cookieProvider = nil
        }
        formatInspection?.cancel(); formatInspection = nil
        metadataRequest?.cancel(); metadataRequest = nil
        qualityRequest?.cancel(); qualityRequest = nil
        pauseAfterFrame = false
        if isPreparing { diagnosticStage = "cancelled"; failureReason = .cancelled }
        #if os(visionOS)
        let previousGeneration = generation
        #endif
        generation = UUID()
        ticker?.cancel(); ticker = nil
        asset?.cancelLoading(); asset = nil
        player.pause()
        if let output = videoOutput { player.currentItem?.remove(output) }
        player.replaceCurrentItem(with: nil)
        videoOutput = nil
        isPreparing = false; isReady = false; isPlaying = false; isBuffering = false
        isSeeking = false; seekGeneration = UUID()
        elapsed = 0; duration = 0; seekStart = 0; seekEnd = 0
        hasSeenFrame = false; frameDeadline = nil
        #if os(visionOS)
        Task { await PlaybackAudioSession.shared.deactivate(for: previousGeneration) }
        #endif
    }

    func fail(_ message: String, reason: PlaybackDiagnostics.FailureReason = .presentationFailed) {
        let stage = diagnosticStage
        diagnostics?.record(.playerError, context: diagnosticContext, labels: ["phase":stage,"failureReason":reason.rawValue,"itemStatus":itemStatusAtFailure.rawValue], numbers: ["elapsed":elapsed], codes:failureCodes+errorLogCodes)
        stop(); diagnosticStage = "failed-at-" + stage; errorMessage = message; failureReason = reason
    }

    private func recordFailure(_ error: Error?, item: AVPlayerItem?) {
        failureCodes = PlaybackDiagnostics.failure(error)
        switch item?.status {
        case .unknown: itemStatusAtFailure = .unknown
        case .readyToPlay: itemStatusAtFailure = .readyToPlay
        case .failed: itemStatusAtFailure = .failed
        default: itemStatusAtFailure = .notCreated
        }
        errorLogCodes = PlaybackDiagnostics.errorLogCodes((item?.errorLog()?.events.suffix(8) ?? []).map {
            (domain: $0.errorDomain, code: $0.errorStatusCode)
        })
        // Do not reinterpret arbitrary CoreMedia/OSStatus numbers as HTTP statuses.
        mediaHTTPStatus = item?.errorLog()?.events.reversed().compactMap {
            PlaybackDiagnostics.httpErrorStatus(domain: $0.errorDomain, code: $0.errorStatusCode)
        }.first
    }

    private func trace(_ kind: DiagnosticEvent.Kind, action: String) {
        guard diagnosticContext != nil else { return }
        diagnostics?.record(kind, context: diagnosticContext, labels:["action":action,"projection":projection.rawValue,"layout":layout.rawValue,"quality":quality.rawValue], numbers:["automaticFormat":automaticallyDetectFormat ? 1:0,"elapsed":elapsed,"decodedWidth":Double(decodedWidth),"decodedHeight":Double(decodedHeight),"swapEyes":swapEyes ? 1:0,"flipY":flipY ? 1:0])
    }
    private func captureMetrics() {
        guard diagnostics != nil, let item=player.currentItem else { return }
        let errors=item.errorLog()?.events ?? []
        if errors.count > loggedErrorEvents {
            for error in errors.dropFirst(loggedErrorEvents) {
                diagnostics?.record(.playerError, context:diagnosticContext, labels:["phase":"player-error-log"], codes:PlaybackDiagnostics.errorLogCodes([(domain:error.errorDomain,code:error.errorStatusCode)]))
            }
            loggedErrorEvents=errors.count
        }
        guard Date().timeIntervalSince(lastMetrics)>=5 else { return }; lastMetrics=Date()
        var values:[String:Double]=["elapsed":elapsed,"duration":duration,"seekStart":seekStart,"seekEnd":seekEnd,"rate":Double(player.rate),"bufferEmpty":item.isPlaybackBufferEmpty ? 1:0,"likelyToKeepUp":item.isPlaybackLikelyToKeepUp ? 1:0]
        if let log=item.accessLog()?.events.last {
            values.merge(["stalls":Double(log.numberOfStalls),"observedBitrate":log.observedBitrate,"indicatedBitrate":log.indicatedBitrate,"bytesTransferred":Double(log.numberOfBytesTransferred),"transferDuration":log.transferDuration,"segmentsDuration":log.segmentsDownloadedDuration,"mediaRequests":Double(log.numberOfMediaRequests)]) { _, new in new }
        }
        diagnostics?.record(.playerMetrics,context:diagnosticContext,numbers:values)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.updateTimeline()
                if self.player.currentItem?.status == .failed {
                    self.recordFailure(self.player.currentItem?.error, item: self.player.currentItem)
                    self.fail("Playback failed during streaming. The connection, access token, or media segments may no longer be available.", reason: .streamingFailed)
                    return
                }
                if let deadline = self.frameDeadline, Date() > deadline, !self.hasSeenFrame {
                    self.fail("Audio or media loaded, but no video frames reached the immersive renderer. This stream's decoded output may be unsupported. Return to the website.", reason: .noVideoFrames)
                    return
                }
            }
        }
    }

    private func updateTimeline() {
        let current = player.currentTime().seconds
        if !isSeeking { elapsed = current.isFinite ? max(0, current) : 0 }
        let length = player.currentItem?.duration.seconds ?? 0
        duration = length.isFinite ? max(0, length) : 0
        let ranges = player.currentItem?.seekableTimeRanges.compactMap { value -> CMTimeRange? in
            let range = value.timeRangeValue
            return range.isValid && range.start.seconds.isFinite && range.duration.seconds.isFinite &&
                CMTimeRangeGetEnd(range).seconds.isFinite ? range : nil
        } ?? []
        if let last = ranges.last {
            seekStart = last.start.seconds; seekEnd = CMTimeRangeGetEnd(last).seconds
        } else { seekStart = 0; seekEnd = duration }
        let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if buffering != isBuffering { diagnostics?.record(.buffering, context: diagnosticContext, labels: ["phase":buffering ? "waiting":"resumed"], numbers:["elapsed":elapsed]) }
        isPlaying = player.timeControlStatus == .playing
        isBuffering = buffering
        captureMetrics()
    }
}

#if os(visionOS)
// Serialise blocking audio-session calls away from the main actor. Ownership prevents
// a delayed stop from deactivating a newer playback session after cancellation.
private actor PlaybackAudioSession {
    static let shared = PlaybackAudioSession()
    private var owner: UUID?

    func activate(for generation: UUID) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback)
        try session.setActive(true)
        owner = generation
    }

    func deactivate(for generation: UUID) {
        guard owner == generation else { return }
        owner = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
