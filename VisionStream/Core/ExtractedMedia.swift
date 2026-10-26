import Foundation

public struct ExtractedMedia: Sendable {
    public let streams: [ExtractedStream]

    public static func parse(_ data: Data, pageURL: String = "") throws -> Self {
        guard data.count <= 1_048_576,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.streams.count <= 32 else { throw ExtractionError.invalidResult }
        guard payload.status == "ok" else { throw ExtractionError.status(payload.status) }
        let streams = payload.streams.enumerated().compactMap { index, value -> ExtractedStream? in
            guard value.source.count <= 16384,
                  ["video/mp4", "application/vnd.apple.mpegurl"].contains(value.mimeType),
                  (0...32768).contains(value.width), (0...32768).contains(value.height) else { return nil }
            let candidate = MediaCandidate(id: "resolved-\(UUID().uuidString)", source: value.source,
                mimeType: value.mimeType, title: "Resolved video \(index + 1)", pageURL: pageURL,
                encrypted: value.unavailableReason == "protected", width: value.width, height: value.height)
            guard candidate.compatibility == .candidate || candidate.encrypted else { return nil }
            return ExtractedStream(candidate: candidate, unavailableCode: value.unavailableReason,
                                   advisoryCode: value.advisory ?? "",
                                   isAdaptive: value.adaptive == true && value.mimeType == "application/vnd.apple.mpegurl")
        }
        guard !streams.isEmpty else { throw ExtractionError.status("no_stream") }
        return .init(streams: streams)
    }

    private struct Payload: Decodable { let status: String; let streams: [Stream] }
    private struct Stream: Decodable {
        let source: String; let mimeType: String; let width: Int; let height: Int; let unavailableReason: String
        let advisory: String?
        let adaptive: Bool?
    }
}

public struct ExtractedStream: Identifiable, Sendable {
    public var id: String { candidate.id }
    public let candidate: MediaCandidate
    public let unavailableCode: String
    public let advisoryCode: String
    public let isAdaptive: Bool
    public var label: String {
        if isAdaptive { return "HLS · Automatic quality" }
        let format = candidate.mimeType == "video/mp4" ? "MP4" : "HLS"
        if candidate.width > 0 && candidate.height > 0 { return "\(format) · \(candidate.width) × \(candidate.height)" }
        if candidate.height > 0 { return "\(format) · \(candidate.height)p" }
        return format
    }
    public var unavailableReason: String? {
        switch unavailableCode {
        case "": return candidate.compatibility.reason
        case "projection": return "This video reports a mesh or another unsupported projection. It cannot be rendered correctly by this player yet."
        case "protected": return "This stream is protected. Continue watching on the website."
        case "separate_audio": return "This source has a separate audio track. On-device merging is not available yet."
        case "required_headers": return "The extractor included authentication headers that this finder cannot transfer. Continue watching on the website."
        default: return "This source requires an unsupported playback feature."
        }
    }
    public var advisory: String? {
        switch advisoryCode {
        case "": return nil
        case "request_context": return "This source came with website headers. Native playback will be tried without those headers; the server may refuse it."
        default: return "Native playback still needs to be checked for this source."
        }
    }
}

public enum ExtractionError: Error, LocalizedError, Sendable {
    case runtime, invalidResult, status(String)
    public var errorDescription: String? {
        switch self {
        case .runtime: return "The on-device video finder could not start. Rebuild the app with its bundled runtime."
        case .invalidResult: return "The video finder returned an unsupported result."
        case .status("invalid_url"): return "Enter an HTTPS video page or stream address without embedded credentials."
        case .status("protected"): return "This video is protected. Continue watching on the website."
        case .status("individual_video_required"): return "Open an individual video instead of a playlist or gallery."
        case .status("no_stream"): return "No supported HTTPS MP4 or HLS source was found."
        case .status: return "This video could not be resolved on the headset. It may need browser-only login or a desktop-only player feature."
        }
    }
}
