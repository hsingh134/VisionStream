import Foundation
import CryptoKit

public struct DiagnosticResource: Codable, Hashable, Sendable {
    public let scheme: String
    public let host: String?
    public let fileExtension: String
    public let hasQuery: Bool
    public init(_ url: URL) {
        scheme = ["https", "http", "file", "blob"].contains(url.scheme ?? "") ? url.scheme! : "other"
        host = Self.safeHost(url.host)
        let ext = url.pathExtension.lowercased()
        fileExtension = ["mp4", "m4v", "m3u8", "ts", "m4s", "html"].contains(ext) ? ext : "unknown"
        hasQuery = url.query != nil
    }
    private static func safeHost(_ text: String?) -> String? {
        guard let text, text.utf8.count <= 253,
              text.range(of: #"^[a-zA-Z0-9.\-:\[\]]+$"#, options: .regularExpression) != nil else { return nil }
        return text.lowercased()
    }
    func sanitized() -> Self {
        var parts = URLComponents(); parts.scheme = ["https", "http", "file", "blob"].contains(scheme) ? scheme : "other"
        // Do not reconstruct any URL or copy untrusted decoded text verbatim.
        return .init(scheme: parts.scheme!, host: Self.safeHost(host), fileExtension: ["mp4","m4v","m3u8","ts","m4s","html"].contains(fileExtension) ? fileExtension : "unknown", hasQuery: hasQuery)
    }
    private init(scheme: String, host: String?, fileExtension: String, hasQuery: Bool) {
        self.scheme = scheme; self.host = host; self.fileExtension = fileExtension; self.hasQuery = hasQuery
    }
}

public struct DiagnosticContext: Codable, Hashable, Sendable {
    public enum Operation: String, Codable, Hashable, Sendable { case navigation, playback, hlsDownload, mp4Download, extraction, fileImport, library }
    public let sessionID: UUID
    public let attemptID: UUID
    public var pageID: UUID?
    public var mediaID: UUID?
    public let operation: Operation
    public var resource: DiagnosticResource?
    public var previousAttemptID: UUID?
    public var parentAttemptID: UUID?
    public func sanitized() -> Self { var result=self; result.resource=resource?.sanitized(); return result }
}

public struct DiagnosticEvent: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case sessionStarted, lifecycle, attemptStarted, navigation, mediaState, extraction,
             playback, quality, format, controls, buffering, decodedFrame, playerMetrics,
             playerError, transfer, transferMetrics, restoredDownload, reportCreated
    }
    public let sequence: Int
    public let timestamp: Date
    public let elapsedSeconds: Double
    public let kind: Kind
    public var context: DiagnosticContext?
    public var labels: [String: String]
    public var numbers: [String: Double]
    public var codes: [String]
}

/// Local append-only session events. URL identities use an ephemeral random HMAC
/// key, so reports can link attempts without storing paths, queries or URL hashes
/// that someone could reproduce from a known page URL. No network or uploads.
@MainActor public final class SessionDiagnostics {
    public private(set) var sessionID = UUID()
    public let root: URL
    public private(set) var eventCount = 0
    public private(set) var persistedEventCount = 0
    public private(set) var storageFailureCodes: [String] = []
    public private(set) var isEnabled:Bool
    private var key = SymmetricKey(size: .bits256)
    private let start = ProcessInfo.processInfo.systemUptime
    private let clock: () -> Date
    private let maximumSessionBytes: Int
    private let maximumRetainedBytes: Int
    private let maximumSessions: Int
    private var fileBytes = 0
    private var wroteGapMarker = false
    private var recent: [DiagnosticEvent] = []
    private var unsaved: [DiagnosticEvent] = []
    private var lastAttempts: [String: UUID] = [:]
    private var deduplicated: [String: Data] = [:]
    private var file: URL { root.appendingPathComponent(sessionID.uuidString + ".jsonl") }
    private static let labelKeys: Set<String> = ["phase","status","reason","action","projection","layout","evidence","quality","mode","mimeType","scheme","extension","method","protocol","appVersion","build","runtime","platform","itemStatus","decision","packing","waitingReason","sourceKind","failureReason","codec","audioCodec","contentEncoding","resourceRole","requestMode"]
    private static let numberKeys: Set<String> = ["width","height","selectedWidth","selectedHeight","decodedWidth","decodedHeight","elapsed","duration","seekStart","seekEnd","target","rate","progress","receivedBytes","expectedBytes","savedBytes","cookieCount","userAgentApplied","backgroundUserAgentApplied","automaticFormat","swapEyes","flipY","protected","playable","paused","readyState","networkState","errorCode","frameMain","httpStatus","statusCode","durationMs","redirectCount","stalls","observedBitrate","indicatedBitrate","transferDuration","mediaRequests","segmentsDuration","bytesTransferred","freeStorageBytes","variantCount","candidateCount","formatVotes","imageMatch","taskIdentifier","loadedSeconds","expectedSeconds","recordCount","errorCount","requestCount","cached","recovered","tlsVersion","videoRange","responseBytes","requestedRangeBytes","bufferEmpty","likelyToKeepUp","rangeSupported","rangeStart","rangeEnd","resourceBytes","resourceIndex","resourceCount","inspectedResources","sbsScore","tbScore","sbsRegions","tbRegions","expandedSearch","requestContextAvailable"]

    public init(root: URL? = nil, maximumSessionBytes: Int = 32 * 1024 * 1024, maximumRetainedBytes: Int = 96 * 1024 * 1024, maximumSessions: Int = 7, enabled:Bool = true, clock: @escaping () -> Date = Date.init) {
        self.root = (root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SessionDiagnostics")).resolvingSymlinksInPath()
        self.maximumSessionBytes = max(512, maximumSessionBytes)
        self.maximumRetainedBytes = max(512, maximumRetainedBytes)
        self.maximumSessions = max(1, maximumSessions)
        self.clock = clock
        self.isEnabled=enabled
        guard enabled else { return }
        prepareRecording()
        record(.sessionStarted, labels: ["phase":"started"])
    }
    private func prepareRecording() {
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            var directory = self.root; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try directory.setResourceValues(flags)
            prune()
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        } catch { storageFailureCodes = PlaybackDiagnostics.failure(error) }
    }
    public func setEnabled(_ enabled:Bool) {
        guard enabled != isEnabled else { return }
        if !enabled { record(.lifecycle,labels:["phase":"diagnostics-disabled"]);isEnabled=false;return }
        isEnabled=true
        if !FileManager.default.fileExists(atPath:file.path) { prepareRecording() }
        record(eventCount==0 ? .sessionStarted:.lifecycle,labels:["phase":"diagnostics-enabled"])
    }
    /// Deletes only this store's UUID-named histories/coverage markers. No
    /// bookmarks, website data, media or arbitrary neighbouring files are removed.
    public func deleteHistory() throws {
        isEnabled=false
        let paths=FileManager.default.fileExists(atPath:root.path) ? try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil):[]
        var failure:Error?
        for path in paths {
            let name=path.lastPathComponent
            let id=name.hasSuffix(".coverage.json") ? String(name.dropLast(14)) : (path.pathExtension=="jsonl" ? path.deletingPathExtension().lastPathComponent:"")
            guard UUID(uuidString:id) != nil else { continue }
            do {
                let type=try FileManager.default.attributesOfItem(atPath:path.path)[.type] as? FileAttributeType
                guard type == .typeRegular || type == .typeSymbolicLink else { throw CocoaError(.fileReadUnknown) }
                try FileManager.default.removeItem(at:path)
            } catch { failure=error }
        }
        sessionID=UUID();key=SymmetricKey(size:.bits256)
        eventCount=0;persistedEventCount=0;fileBytes=0;wroteGapMarker=false
        recent.removeAll();unsaved.removeAll();lastAttempts.removeAll();deduplicated.removeAll();storageFailureCodes=[]
        if let failure { throw failure }
    }

    public func reference(_ value: String, page: Bool = false) -> UUID {
        var identity = value
        if page, var components = URLComponents(string: value) { components.fragment = nil; identity = components.string ?? value }
        let digest = Array(HMAC<SHA256>.authenticationCode(for: Data(((page ? "page:" : "media:") + identity).utf8), using: key).prefix(16))
        return UUID(uuid: (digest[0],digest[1],digest[2],digest[3],digest[4],digest[5],digest[6],digest[7],digest[8],digest[9],digest[10],digest[11],digest[12],digest[13],digest[14],digest[15]))
    }

    public func begin(_ operation: DiagnosticContext.Operation, media: MediaCandidate? = nil, page: URL? = nil, parent: DiagnosticContext? = nil) -> DiagnosticContext {
        let source = media.flatMap { URL(string: $0.source) }
        let document = (page ?? media.flatMap { URL(string: $0.pageURL) }).flatMap { ["https","http"].contains($0.scheme ?? "") && $0.host != nil ? $0 : nil }
        var context = DiagnosticContext(sessionID: sessionID, attemptID: UUID(), pageID: document.map { reference($0.absoluteString, page: true) }, mediaID: source.map { reference($0.absoluteString) }, operation: operation, resource: (source ?? document).map(DiagnosticResource.init), parentAttemptID: parent?.attemptID)
        let previousKey = operation.rawValue + (context.mediaID ?? context.pageID ?? UUID()).uuidString
        if isEnabled { context.previousAttemptID = lastAttempts[previousKey]; lastAttempts[previousKey] = context.attemptID }
        record(.attemptStarted, context: context, labels: ["phase":"requested"], numbers: media.map { mediaNumbers($0) } ?? [:])
        return context
    }

    public func mediaContext(_ media: MediaCandidate, parent: DiagnosticContext?) -> DiagnosticContext {
        .init(sessionID: sessionID, attemptID: parent?.attemptID ?? UUID(), pageID: URL(string: media.pageURL).flatMap { ["https","http"].contains($0.scheme ?? "") && $0.host != nil ? reference($0.absoluteString,page:true) : nil }, mediaID: reference(media.source), operation: parent?.operation ?? .navigation, resource: URL(string: media.source).map(DiagnosticResource.init))
    }

    public func mediaNumbers(_ media: MediaCandidate) -> [String: Double] {
        var values: [String:Double] = ["width":Double(media.width),"height":Double(media.height),"elapsed":media.currentTime,"protected":media.encrypted ? 1:0]
        if let state = media.webMedia { values.merge(["paused":state.paused ? 1:0,"readyState":Double(state.readyState),"networkState":Double(state.networkState),"errorCode":Double(state.errorCode)]) { _, new in new } }
        return values
    }

    public func record(_ kind: DiagnosticEvent.Kind, context: DiagnosticContext? = nil, labels: [String:String] = [:], numbers: [String:Double] = [:], codes: [String] = [], deduplicate: String? = nil) {
        guard isEnabled else { return }
        let labels = Self.safeLabels(labels), numbers = Self.safeNumbers(numbers), codes = Self.safeCodes(codes)
        if let deduplicate {
            let fingerprint = (try? Self.encoder().encode(Fingerprint(labels:labels,numbers:kind == .mediaState ? numbers.filter { $0.key != "elapsed" } : numbers,codes:codes))) ?? Data()
            if deduplicated[deduplicate] == fingerprint { return }
            if deduplicated.count > 2048 { deduplicated.removeAll() }
            deduplicated[deduplicate] = fingerprint
        }
        eventCount += 1
        let event = DiagnosticEvent(sequence:eventCount,timestamp:clock(),elapsedSeconds:max(0,ProcessInfo.processInfo.systemUptime-start),kind:kind,context:context?.sanitized(),labels:labels,numbers:numbers,codes:codes)
        recent.append(event); if recent.count > 200 { recent.removeFirst(recent.count-200) }
        do {
            var data = try Self.encoder().encode(event); data.append(10)
            guard storageFailureCodes.isEmpty, fileBytes + data.count <= maximumSessionBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            let handle = try FileHandle(forWritingTo:file); defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf:data)
            fileBytes += data.count; persistedEventCount += 1
        } catch {
            if storageFailureCodes.isEmpty { storageFailureCodes = PlaybackDiagnostics.failure(error) }
            // Reserve a separate, bounded indication of an incomplete tail. A
            // full event file must not look complete after the next launch.
            if !wroteGapMarker {
                let marker = GapMarker(firstMissingSequence:eventCount, codes:storageFailureCodes)
                if let data=try? Self.encoder().encode(marker) {
                    do { try data.write(to:gapFile(sessionID),options:.atomic); wroteGapMarker=true }
                    catch { /* The current report still exposes storageFailureCodes. */ }
                }
            }
            unsaved.append(event); if unsaved.count > 200 { unsaved.removeFirst(unsaved.count-200) }
        }
    }

    private struct GapMarker: Codable { let firstMissingSequence:Int; let codes:[String] }
    private func gapFile(_ id:UUID) -> URL { root.appendingPathComponent(id.uuidString+".coverage.json") }

    private struct Fingerprint: Encodable { let labels:[String:String]; let numbers:[String:Double]; let codes:[String] }
    private static func encoder() -> JSONEncoder { let value=JSONEncoder(); value.dateEncodingStrategy = .iso8601; value.outputFormatting = [.sortedKeys]; return value }
    private static func safeLabels(_ labels: [String:String]) -> [String:String] {
        labels.filter { ($0.key != "mimeType" || ["video/mp4","application/vnd.apple.mpegurl","application/x-mpegurl","audio/mpegurl","video/webm","application/dash+xml","video/mp2t","application/octet-stream",""].contains($0.value)) && labelKeys.contains($0.key) && $0.value.utf8.count <= 256 && !$0.value.contains("://") && !$0.value.contains("?") && !$0.value.contains("=") && $0.value.rangeOfCharacter(from:.controlCharacters) == nil }
    }
    private static func safeNumbers(_ numbers: [String:Double]) -> [String:Double] { numbers.filter { numberKeys.contains($0.key) && $0.value.isFinite } }
    private static func safeCodes(_ codes: [String]) -> [String] {
        Array(codes.filter { $0.range(of:#"^(?:NSURLErrorDomain|AVFoundationErrorDomain|CoreMediaErrorDomain|WKErrorDomain|NSOSStatusErrorDomain|HTTP|OtherErrorDomain):-?[0-9]{1,12}$"#,options:.regularExpression) != nil }.prefix(16))
    }
    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.contentModificationDateKey,.isRegularFileKey])) ?? []).filter {
            $0.pathExtension == "jsonl" && UUID(uuidString:$0.deletingPathExtension().lastPathComponent) != nil &&
            (try? FileManager.default.attributesOfItem(atPath:$0.path)[.type] as? FileAttributeType) == .typeRegular && $0.resolvingSymlinksInPath() == $0.standardizedFileURL
        }.sorted { ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
    }
    private func prune() {
        var old=files(), bytes=old.reduce(0) { $0 + ((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
        while old.count >= maximumSessions || bytes > max(0,maximumRetainedBytes-maximumSessionBytes) {
            guard !old.isEmpty else { break }
            let next=old.removeFirst(); bytes -= (try? next.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at:next)
            if let id=UUID(uuidString:next.deletingPathExtension().lastPathComponent) { try? FileManager.default.removeItem(at:gapFile(id)) }
        }
    }

    public func report(snapshot: String) -> String {
        struct Session: Encodable { let sessionID:UUID; let current:Bool; let complete:Bool; let invalidRecords:Int; let missingEvents:Int; let missingEventCountIsExact:Bool; let storageFailureCodes:[String]; let events:[DiagnosticEvent] }
        var sessions:[Session] = []
        let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var paths=files(); if (eventCount>0 || FileManager.default.fileExists(atPath:file.path)),!paths.contains(where: { $0.standardizedFileURL.path == file.standardizedFileURL.path }) { paths.append(file) }
        for path in paths {
            guard let id=UUID(uuidString:path.deletingPathExtension().lastPathComponent) else { continue }
            let size=(try? path.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
            let oversized=size>maximumSessionBytes
            var readFailed=false
            let data:Data
            do { data=oversized ? Data() : try Data(contentsOf:path) }
            catch { data=Data(); readFailed=true }
            var events:[DiagnosticEvent]=[], invalid=(oversized || readFailed) ? 1:0
            var marker:GapMarker?
            let markerFile=gapFile(id)
            if FileManager.default.fileExists(atPath:markerFile.path) {
                let attributes=try? FileManager.default.attributesOfItem(atPath:markerFile.path)
                if attributes?[.type] as? FileAttributeType == .typeRegular,
                   (attributes?[.size] as? NSNumber)?.intValue ?? Int.max <= 4096,
                   let markerData=try? Data(contentsOf:markerFile),let value=try? decoder.decode(GapMarker.self,from:markerData),value.firstMissingSequence>0 {
                    marker=value
                } else { invalid += 1 }
            }
            for line in data.split(separator:10) {
                if var event=try? decoder.decode(DiagnosticEvent.self,from:Data(line)) {
                    event.labels=Self.safeLabels(event.labels); event.numbers=Self.safeNumbers(event.numbers); event.codes=Self.safeCodes(event.codes)
                    if var context=event.context { context.resource=context.resource?.sanitized(); event.context=context }
                    events.append(event)
                } else { invalid += 1 }
            }
            if id==sessionID { events.append(contentsOf:unsaved) }
            var unique:[Int:DiagnosticEvent]=[:]; for event in events { unique[event.sequence]=event }
            events=unique.values.sorted { $0.sequence < $1.sequence }
            let expected=id==sessionID ? eventCount : max(events.last?.sequence ?? 0,marker?.firstMissingSequence ?? 0)
            let missing=max(0,expected-events.count)
            sessions.append(.init(sessionID:id,current:id==sessionID,complete:missing==0 && invalid==0 && marker==nil,invalidRecords:invalid,missingEvents:missing,missingEventCountIsExact:id==sessionID || marker==nil,storageFailureCodes:Self.safeCodes(marker?.codes ?? []),events:events))
        }
        var object=(try? JSONSerialization.jsonObject(with:Data(snapshot.utf8))) as? [String:Any] ?? [:]
        object["reportSchemaVersion"]=2
        object["generatedAtUTC"]=ISO8601DateFormatter().string(from:clock())
        object["sessionHistory"]=(try? JSONSerialization.jsonObject(with:Self.encoder().encode(sessions))) ?? []
        object["currentSessionID"]=sessionID.uuidString
        object["diagnosticsRecordingEnabled"]=isEnabled
        object["sessionHistoryCoverage"]=["currentEventCount":eventCount,"persistedEventCount":persistedEventCount,"storageFailureCodes":storageFailureCodes,"maximumRetainedSessions":maximumSessions,"maximumCurrentSessionBytes":maximumSessionBytes,"scope":"App-observed events while detailed history is enabled; not a complete WebKit network capture. Actions while disabled are not recorded. Current technical snapshot is generated only when requested."] as [String:Any]
        object["privacy"]="Includes website/media hosts, anonymous correlated IDs, timing and technical state. Excludes URL paths/queries, titles, cookies, credentials, header values, page content and decoded images. Local only until you share."
        guard let data=try? JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),let text=String(data:data,encoding:.utf8) else { return snapshot }
        return text
    }
}
