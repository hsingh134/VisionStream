import AVFoundation
import WebKit

/// Fill absent MP4 dimensions with the public asset API before ordering finder
/// choices. This is a bounded metadata inspection, not a video download.
@MainActor enum NativeStreamInspector {
    static func refine(_ media: ExtractedMedia) async throws -> ExtractedMedia {
        let agent = await browserUserAgent()
        var streams: [ExtractedStream] = []
        var inspected = 0
        let budget = Date().addingTimeInterval(12)
        for stream in media.streams {
            try Task.checkCancellation()
            var candidate = stream.candidate
            var unavailable = stream.unavailableCode
            if Date() < budget, inspected < 8, stream.unavailableReason == nil,
               candidate.normalizedMIMEType == "video/mp4",
               candidate.width == 0 || candidate.height == 0,
               let url = URL(string: candidate.source) {
                inspected += 1
                var target = url
                var inspection = try await inspect(url, userAgent: agent)
                if case .unknown = inspection, Date() < budget,
                   let resolved = try? await PublicMediaLocation().load(url, userAgent: agent), resolved != url, Date() < budget {
                    try Task.checkCancellation()
                    target = resolved; inspection = try await inspect(resolved, userAgent: agent)
                }
                switch inspection {
                case .protected: candidate.encrypted = true; unavailable = "protected"
                case .size(let width, let height):
                    candidate.width = width; candidate.height = height
                    candidate.source = target.absoluteString
                case .unknown: break
                }
                try Task.checkCancellation()
            }
            streams.append(.init(candidate: candidate, unavailableCode: unavailable,
                                 advisoryCode: stream.advisoryCode, isAdaptive: stream.isAdaptive))
        }
        // Stable ordering keeps existing format groups and advisories. Unknown
        // dimensions cannot outrank a measured complete source in the same group.
        let ranked = streams.enumerated().sorted { left, right in
            func key(_ stream: ExtractedStream) -> (Int, Int, Int64) {
                (stream.unavailableReason == nil ? 0 : 1,
                 stream.candidate.normalizedMIMEType == "video/mp4" ? 0 : (stream.isAdaptive ? 1 : 2),
                 -Int64(stream.candidate.width) * Int64(stream.candidate.height))
            }
            let a = key(left.element), b = key(right.element)
            return a == b ? left.offset < right.offset : a < b
        }.map(\.element)
        return .init(streams: ranked)
    }
    private static var cachedAgent: String?
    /// The app uses the default platform WebKit identity. Read it from an
    /// isolated blank WebView; no website, browser session or cookie is opened.
    static func browserUserAgent() async -> String? {
        if let cachedAgent { return cachedAgent }
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        guard let agent = try? await view.evaluateJavaScript("navigator.userAgent", in: nil, contentWorld: .defaultClient) as? String,
              !agent.isEmpty, agent.utf8.count <= 1024, agent.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        cachedAgent = agent; return agent
    }

    private enum Inspection { case unknown, protected, size(Int, Int) }
    private static func inspect(_ url: URL, userAgent: String?) async throws -> Inspection {
        var options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: false, AVURLAssetHTTPCookiesKey: [HTTPCookie]()]
        if let userAgent { options[AVURLAssetHTTPUserAgentKey] = userAgent }
        let asset = AVURLAsset(url: url, options: options)
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { asset.cancelLoading() }
        }
        defer { deadline.cancel() }
        do {
            return try await withTaskCancellationHandler {
                let (playable, protected) = try await asset.load(.isPlayable, .hasProtectedContent)
                if protected { return .protected }
                guard playable, let track = try await asset.loadTracks(withMediaType: .video).first else { return .unknown }
                let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
                let display = CGRect(origin: .zero, size: size).applying(transform).size
                let width = abs(display.width), height = abs(display.height)
                guard width.isFinite, height.isFinite, width >= 1, height >= 1, width <= 32768, height <= 32768 else { return .unknown }
                return .size(Int(width.rounded()), Int(height.rounded()))
            } onCancel: { asset.cancelLoading() }
        } catch {
            try Task.checkCancellation()
            return .unknown
        }
    }

}
