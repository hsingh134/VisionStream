import Foundation

public enum PlaybackQuality: String, CaseIterable, Identifiable, Sendable {
    case highest, adaptive
    public var id: Self { self }
    public var label: String { self == .highest ? "Highest" : "Adaptive" }
}

/// Inspects published HLS URIs; never manufactures tokens or rewrites playlists.
public struct HLSManifest: Sendable {
    public struct Resource: Sendable {
        public enum Role: String, Sendable { case variantPlaylist, audioPlaylist, subtitlePlaylist, iframePlaylist, initialization, key, segment }
        public let url: URL
        public let role: Role
        public let index: Int
    }
    public struct Variant: Sendable {
        public let url: URL
        public let width: Int
        public let height: Int
        public let bandwidth: Int
        public let codecs: String
        public let audioGroup: String?
        public let hasOtherRenditions: Bool
        public let isSDR: Bool
    }
    public static let maximumBytes = 524_288
    public let variants: [Variant]
    public let resources: [Resource]
    private let externalAudioGroups: Set<String>
    private let requiresParentContext: Bool

    public init(data: Data, base: URL) throws {
        guard data.count <= Self.maximumBytes, let text = String(data: data, encoding: .utf8),
              text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw ParseError.invalid }
        let lines = text.components(separatedBy: .newlines)
        guard lines.count <= 8192 else { throw ParseError.invalid }
        var pending: [String: String]?
        var found: [Variant] = []
        var audio = Set<String>()
        var context = false
        var references:[Resource]=[],sequence=0,segmentCount=0
        func reference(_ raw:String?,_ role:Resource.Role,_ index:Int=0) {
            guard references.count<2048,let raw,!raw.contains("{$"),let url=VRLibraryURL.resolve(raw,relativeTo:base) else { return }
            references.append(.init(url:url,role:role,index:index))
        }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-MEDIA:") {
                let attrs = Self.attributes(String(line.dropFirst(13)))
                if attrs["TYPE"] == "AUDIO", attrs["URI"] != nil, let group = attrs["GROUP-ID"] { audio.insert(group) }
                if attrs["TYPE"] == "AUDIO" { reference(attrs["URI"],.audioPlaylist) }
                if attrs["TYPE"] == "SUBTITLES" { reference(attrs["URI"],.subtitlePlaylist) }
            } else if line.hasPrefix("#EXT-X-SESSION-KEY:") || line.hasPrefix("#EXT-X-DEFINE:") {
                context = true
            } else if line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") {
                reference(Self.attributes(String(line.dropFirst(26)))["URI"],.iframePlaylist)
            } else if line.hasPrefix("#EXT-X-MAP:") {
                reference(Self.attributes(String(line.dropFirst(11)))["URI"],.initialization)
            } else if line.hasPrefix("#EXT-X-KEY:") {
                reference(Self.attributes(String(line.dropFirst(11)))["URI"],.key)
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                sequence=max(0,min(1_000_000_000,Int(line.dropFirst(22)) ?? 0))
            } else if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pending = Self.attributes(String(line.dropFirst(18)))
            } else if !line.isEmpty && !line.hasPrefix("#"), let attrs = pending {
                pending = nil
                guard found.count < 64 else { throw ParseError.invalid }
                guard !line.contains("{$"),
                      let url = VRLibraryURL.resolve(line, relativeTo: base) else { continue }
                reference(line,.variantPlaylist,found.count)
                let size = (attrs["RESOLUTION"] ?? "").lowercased().split(separator: "x")
                let width = size.count == 2 ? Int(size[0]) ?? 0 : 0
                let height = size.count == 2 ? Int(size[1]) ?? 0 : 0
                found.append(.init(url: url, width: width, height: height,
                    bandwidth: Int(attrs["AVERAGE-BANDWIDTH"] ?? attrs["BANDWIDTH"] ?? "") ?? 0,
                    codecs: attrs["CODECS"]?.lowercased() ?? "", audioGroup: attrs["AUDIO"],
                    hasOtherRenditions: attrs["VIDEO"] != nil || attrs["SUBTITLES"] != nil,
                    isSDR: attrs["VIDEO-RANGE"] == nil || attrs["VIDEO-RANGE"] == "SDR"))
            } else if !line.isEmpty,!line.hasPrefix("#") {
                reference(line,.segment,sequence+segmentCount);segmentCount += 1
            }
        }
        variants = found; resources=references; externalAudioGroups = audio; requiresParentContext = context
    }

    /// A child is independently playable only when it carries its own audio.
    /// Keep the original master for external audio, subtitles, session keys or
    /// unknown codec signaling instead of silently losing those relationships.
    public var highestIndependentVariant: Variant? {
        guard !requiresParentContext else { return nil }
        let supported = variants.filter { v in
            let codecs = v.codecs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let video = codecs.contains { ["avc1", "avc3", "hvc1", "hev1"].contains(String($0.prefix(4))) }
            let audio = codecs.contains { $0.hasPrefix("mp4a") || $0 == "ac-3" || $0 == "ec-3" }
            return video && audio && v.isSDR && !v.hasOtherRenditions &&
                (v.audioGroup.map { !externalAudioGroups.contains($0) } ?? true) &&
                (1...8192).contains(v.width) && (1...8192).contains(v.height)
        }
        return supported.max { a, b in
            (Int64(a.width) * Int64(a.height), a.height, a.bandwidth) <
            (Int64(b.width) * Int64(b.height), b.height, b.bandwidth)
        }
    }

    static func attributes(_ text: String) -> [String: String] {
        var parts: [String] = [], current = "", quoted = false
        for character in text {
            if character == "\"" { quoted.toggle() }
            if character == "," && !quoted { parts.append(current); current = "" }
            else { current.append(character) }
        }
        parts.append(current)
        var result: [String: String] = [:]
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            result[String(pair[0]).trimmingCharacters(in: .whitespaces)] = String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        return result
    }
    public enum ParseError: Error { case invalid }
}
