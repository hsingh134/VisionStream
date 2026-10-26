import Foundation

public struct MediaCandidate: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var videoID: String
    public var source: String
    public var mimeType: String
    public var title: String
    public var pageURL: String
    public var encrypted: Bool
    public var width: Int
    public var height: Int
    public var currentTime: Double
    public var formatHint: VideoFormatHint?
    public var webMedia: WebMediaState?
    public var playIntent: WebPlayIntent?

    /// Ephemeral signal from the isolated DOM detector. Never a download URL or
    /// a persistent preference. Programmatic autoplay does not produce one.
    public struct WebPlayIntent: Codable, Hashable, Sendable {
        public var id: String
        public var age: Double
        public var visible: Bool
        public init(id: String, age: Double, visible: Bool) { self.id=id; self.age=age; self.visible=visible }
    }

    public struct WebMediaState: Codable, Hashable, Sendable {
        public var errorCode: Int
        public var readyState: Int
        public var networkState: Int
        public var paused: Bool
    }

    public init(id: String, videoID: String = "", source: String, mimeType: String = "",
                title: String = "Video", pageURL: String = "", encrypted: Bool = false,
                width: Int = 0, height: Int = 0, currentTime: Double = 0, formatHint: VideoFormatHint? = nil, webMedia: WebMediaState? = nil, playIntent: WebPlayIntent? = nil) {
        self.id = id; self.videoID = videoID; self.source = source; self.mimeType = mimeType
        self.title = title; self.pageURL = pageURL; self.encrypted = encrypted
        self.width = width; self.height = height; self.currentTime = currentTime
        self.webMedia = webMedia; self.formatHint = formatHint; self.playIntent=playIntent
    }

    public var compatibility: StreamCompatibility { StreamCompatibility.evaluate(self) }
    /// Default choice only; an explicit picker selection remains authoritative.
    /// Prefer a direct candidate that the webpage has actually prepared/started
    /// over an inactive fallback. This is evidence for selection, not proof that
    /// AVPlayer can load the source.
    public static func preferredForPlayback(in candidates: [Self]) -> Self? {
        let native = candidates.filter { $0.compatibility == .candidate }
        let pool = native.isEmpty ? candidates : native
        func score(_ media: Self) -> (Int, Int, Double) {
            let healthy = media.webMedia?.errorCode == 0
            let ready = healthy && (media.webMedia?.readyState ?? 0) >= 2 && media.width > 0 && media.height > 0
            let playing = healthy && media.webMedia?.paused == false
            return (ready ? 1 : 0, playing ? 1 : 0, Double(max(0, media.width)) * Double(max(0, media.height)))
        }
        var best: Self?
        for media in pool {
            if best == nil || score(media) > score(best!) { best = media }
        }
        return best
    }
    /// A finder result can reuse geometry cues only from the exact page it
    /// resolved. Keep query identifiers; fragments alone do not change the page.
    /// No source URL, authentication value or browser-local media is transferred.
    public func withBrowserFormatContext(page: URL?, title: String, candidates: [Self]) -> Self {
        func document(_ url: URL?) -> URL? {
            guard let url, url.scheme == "https", url.user == nil, url.password == nil,
                  var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            parts.fragment = nil
            return parts.url
        }
        guard let current = document(page), document(URL(string: pageURL)) == current else { return self }
        var result = self
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.title = String(title.prefix(160)) }
        let local = candidates.filter { document(URL(string: $0.pageURL)) == current }
        // Multiple page videos may have different packing. A page title remains
        // only a cue; transfer an element's explicit metadata when unambiguous.
        let groups = Set(local.map { $0.videoID.isEmpty ? $0.id : $0.videoID })
        if result.formatHint == nil, groups.count == 1,
           let first = local.first?.formatHint, local.allSatisfy({ $0.formatHint == first }) { result.formatHint = first }
        return result
    }

    public var normalizedMIMEType: String {
        mimeType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? ""
    }

    // Never put signed query strings in the candidate list or error messages.
    public var displaySource: String {
        guard let url = URL(string: source), let host = url.host else { return "Browser-only media" }
        let mime = normalizedMIMEType
        let ext = url.pathExtension.lowercased()
        if ["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl"].contains(mime) || ext == "m3u8" {
            return host + " · HLS (M3U8)"
        }
        if mime == "video/mp4" || ["mp4", "m4v"].contains(ext) { return host + " · MP4" }
        return host
    }
}

public enum StreamCompatibility: Equatable, Sendable {
    case candidate
    case unsupported(String)

    public static func evaluate(_ media: MediaCandidate) -> Self {
        if media.encrypted {
            return .unsupported("This video reports encrypted media. VisionStream has no DRM licence integration. Continue watching on the website.")
        }
        guard let url = URL(string: media.source), let scheme = url.scheme?.lowercased() else {
            return .unsupported("The website has not exposed a usable video URL. Start the video on the page, then scan again.")
        }
        if scheme == "blob" {
            return .unsupported("This player uses a browser-local blob or Media Source stream. It cannot be handed to AVPlayer. No underlying stream URL has been verified.")
        }
        guard scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            return .unsupported("Native playback requires a direct HTTPS stream without credentials in the URL. Browser-only and insecure URLs are unsupported.")
        }
        let mime = media.normalizedMIMEType
        let ext = url.pathExtension.lowercased()
        let supportedMIMEs = ["video/mp4", "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl"]
        if !mime.isEmpty, !supportedMIMEs.contains(mime) {
            return .unsupported("The reported media type is unsupported. This prototype accepts MP4 and HLS candidates.")
        }
        if mime.isEmpty, !ext.isEmpty, !["mp4", "m4v", "m3u8"].contains(ext) {
            return .unsupported("The source is not an identified MP4 or HLS stream.")
        }
        // Extensionless signed CDN endpoints are probed by AVFoundation, never assumed playable.
        return .candidate
    }

    public var reason: String? {
        if case .unsupported(let reason) = self { return reason }
        return nil
    }
}

public enum BrowserAddress {
    public static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let value = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, !host.contains(" "),
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
