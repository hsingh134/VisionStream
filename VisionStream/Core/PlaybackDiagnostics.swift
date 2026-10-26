import Foundation

/// A deliberately small report: never serialise URLs, titles, cookies, headers,
/// NSError descriptions/userInfo, or AVPlayer error-log strings.
public enum PlaybackDiagnostics {
    public enum FailureReason: String, Sendable {
        case none, cancelled, unsupportedCandidate, preparationTimeout, protectedAsset,
             unplayableAsset, playerRejected, assetLoadFailed, streamingFailed, noVideoFrames, presentationFailed
    }

    public enum ItemStatus: String, Sendable {
        case notCreated, unknown, readyToPlay, failed
    }

    private static func code(domain: String, value: Int) -> String {
        let allowed = [NSURLErrorDomain, "AVFoundationErrorDomain", "CoreMediaErrorDomain", "WKErrorDomain", "NSOSStatusErrorDomain", "HTTP"]
        return "\(allowed.contains(domain) ? domain : "OtherErrorDomain"):\(value)"
    }

    public static func sanitizedCodes(_ codes: [String]) -> [String] {
        Array(codes.filter { $0.range(of: #"^(?:NSURLErrorDomain|AVFoundationErrorDomain|CoreMediaErrorDomain|WKErrorDomain|NSOSStatusErrorDomain|HTTP|OtherErrorDomain):-?[0-9]{1,12}$"#, options:.regularExpression) != nil }.prefix(16))
    }

    /// Only domain classification and numeric codes survive; log comments/URLs are never read.
    public static func errorLogCodes(_ events: [(domain: String, code: Int)]) -> [String] {
        events.suffix(8).map { code(domain: $0.domain, value: $0.code) }
    }

    public static func webFailureHint(_ code: Int?) -> String? {
        switch code {
        case 1: "The webpage's video was aborted. Try the website's Play button again."
        case 2: "The webpage's video reported a network loading error. Refresh the page and retry its Play button."
        case 3: "The webpage's video reported a decoding error. The media may be damaged or unsupported."
        case 4: "The webpage's video could not load a supported source. This does not identify whether its URL, format or access requirements caused the failure."
        default: nil
        }
    }

    /// A numeric log error is not an HTTP response unless its domain identifies HTTP.
    public static func httpErrorStatus(domain: String, code: Int) -> Int? {
        domain == "HTTP" && (400...599).contains(code) ? code : nil
    }

    public static func failure(_ error: Error?) -> [String] {
        guard let error else { return [] }
        var current: NSError? = error as NSError
        var result: [String] = []
        for _ in 0..<3 {
            guard let value = current else { break }
            result.append(code(domain: value.domain, value: value.code))
            // CoreMedia sometimes exposes an HTTP failure only as this fixed
            // diagnostic prefix. Retain just its three digits, never the text.
            if value.domain == "CoreMediaErrorDomain",
               let text=value.userInfo["NSDescription"] as? String, text.utf8.count <= 4096,
               let match=text.range(of:#"^HTTP [1-5][0-9]{2}:(?:[ \t]|$)"#,options:.regularExpression),
               let status=Int(text[match].dropFirst(5).prefix(3)) {
                result.append("HTTP:\(status)")
            }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return result
    }

    public static func failureHint(_ error: Error?) -> String? {
        let codes = failure(error)
        if codes.contains("HTTP:404") {
            return "The native media service reported HTTP 404: a required playlist or media resource was not found for its request. Streaming and saving can make different requests. Refresh the webpage for a fresh source; this message does not identify which resource failed."
        }
        if codes.contains("NSURLErrorDomain:\(NSURLErrorSecureConnectionFailed)") || (-1206 ... -1201).contains(where: { codes.contains("NSURLErrorDomain:\($0)") }) {
            return "A secure connection to the media server could not be established. Try the website again later or check your connection. This error does not identify a codec or login problem."
        }
        if codes.contains("NSURLErrorDomain:\(NSURLErrorFileDoesNotExist)") {
            return "A playlist or media resource was reported as missing. Run Find streams again for fresh links, then try MP4 or HLS Automatic quality if available. This error alone does not prove that the link expired or identify an HTTP status."
        }
        guard codes.contains("AVFoundationErrorDomain:-11850") else { return nil }
        return "AVPlayer rejected the server's media response. Its byte-range handling may be incompatible. If this video offers a separate HLS (M3U8) candidate, try that option. If the webpage video also fails, check the website's normal access and playback requirements."
    }

    private static func media(_ candidate: MediaCandidate) -> [String: Any] {
        let url = URL(string: candidate.source)
        let source: String
        if candidate.source.isEmpty { source = "missing" }
        else if url?.scheme?.lowercased() == "blob" { source = "browser-local" }
        else if url?.scheme?.lowercased() == "https" { source = "https" }
        else { source = "other" }
        let ext = url?.pathExtension.lowercased() ?? ""
        let mime = candidate.normalizedMIMEType
        let knownMIMEs = ["video/mp4", "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "application/dash+xml", "video/webm"]
        var result: [String: Any] = ["sourceKind": source,
                "formatExtension": ["mp4", "m4v", "m3u8", "mpd", "webm"].contains(ext) ? ext : "unknown",
                "mimeType": mime.isEmpty ? "unspecified" : (knownMIMEs.contains(mime) ? mime : "other"),
                "encrypted": candidate.encrypted,
                "width": candidate.width, "height": candidate.height,
                "nativeCandidate": candidate.compatibility == .candidate]
        if let web = candidate.webMedia {
            result["webMedia"] = [
                "errorCode": (0...4).contains(web.errorCode) ? web.errorCode as Any : NSNull(),
                "readyState": (0...4).contains(web.readyState) ? web.readyState as Any : NSNull(),
                "networkState": (0...3).contains(web.networkState) ? web.networkState as Any : NSNull(),
                "paused": web.paused
            ]
        }
        if let hint = candidate.formatHint {
            result["formatHint"] = ["projection": hint.projection?.rawValue ?? "unspecified",
                "layout": hint.layout?.rawValue ?? "unspecified", "evidence": hint.evidence.rawValue]
        }
        return result
    }

    public static func report(version: String, runtime: String, pageHTTPStatus: Int?,
                              pageFailure: [String], candidates: [MediaCandidate],
                              playbackStage: String, playbackFailure: [String],
                              mediaHTTPStatus: Int?, projection: VideoProjection,
                              layout: StereoLayout, attemptedMedia: MediaCandidate? = nil,
                              presentation: VideoPresentation? = nil, decodedWidth: Int = 0, decodedHeight: Int = 0,
                              failureReason: FailureReason = .none, itemStatus: ItemStatus = .notCreated,
                              errorLogCodes: [String] = [], browserUserAgentApplied: Bool = false, quality: PlaybackQuality = .highest, selectedWidth: Int = 0, selectedHeight: Int = 0, automaticFormat: Bool = false,
                              hlsDownloadFailureCodes: [String] = []) -> String {
        let detected = candidates.prefix(16).map { media($0) }
        let record: [String: Any] = [
            "qualityPreference": quality.rawValue, "selectedRenditionWidth": selectedWidth, "selectedRenditionHeight": selectedHeight, "automaticFormat": automaticFormat,
            "appVersion": version, "runtime": runtime,
            "pageHTTPStatus": pageHTTPStatus.map { $0 as Any } ?? NSNull(),
            "pageFailureCodes": pageFailure, "detectedMedia": detected,
            "attemptedMedia": attemptedMedia.map { media($0) as Any } ?? NSNull(),
            "playbackStage": playbackStage, "playbackFailureCodes": playbackFailure,
            "playbackFailureReason": failureReason.rawValue, "playerItemStatusAtFailure": itemStatus.rawValue,
            "browserUserAgentApplied": browserUserAgentApplied,
            // The local journal is untrusted input too. Only numeric codes
            // from the same fixed domain vocabulary can enter a shared report.
            "hlsDownloadFailureCodes": Array(hlsDownloadFailureCodes.filter {
                $0.range(of: #"^(?:NSURLErrorDomain|AVFoundationErrorDomain|CoreMediaErrorDomain|WKErrorDomain|NSOSStatusErrorDomain|HTTP|OtherErrorDomain):-?[0-9]{1,12}$"#, options: .regularExpression) != nil
            }.prefix(8)),
            "playerErrorLogCodes": Array(errorLogCodes.suffix(8)),
            "mediaHTTPStatus": mediaHTTPStatus.map { $0 as Any } ?? NSNull(),
            "projection": projection.rawValue, "layout": layout.rawValue,
            "presentation": presentation?.rawValue ?? projection.rawValue, "decodedWidth": decodedWidth, "decodedHeight": decodedHeight,
            "privacy": "No page/media URLs, titles, cookies, headers or error descriptions included.",
            "interpretation": "A detected candidate or ready player alone does not verify immersive playback or website support."
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "Report unavailable." }
        return text
    }
}
