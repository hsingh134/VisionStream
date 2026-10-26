import Foundation

/// A read-only subset of the HereSphere JSON library format. No account writes,
/// password exchange, HSP execution, extraction, or peripheral requests are made.
public struct VRLibraryDocument: Sendable {
    public static let maximumBytes = 2_097_152
    public let title: String
    public let limitedAccess: Bool
    public let entries: [VRLibraryEntry]
    public let streams: [VRLibraryStream]

    public static func parse(_ data: Data, relativeTo base: URL) throws -> Self {
        guard data.count <= maximumBytes else { throw VRLibraryError.tooLarge }
        guard VRLibraryURL.isAllowed(base) else { throw VRLibraryError.invalidURL }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw VRLibraryError.invalidDocument }
        guard let access = payload.access, [0, 1].contains(access) else {
            if payload.access != nil { throw VRLibraryError.accessDenied }
            throw VRLibraryError.invalidDocument
        }
        guard payload.library != nil || payload.media != nil else { throw VRLibraryError.invalidDocument }
        var entries: [VRLibraryEntry] = []
        var seen = Set<URL>()
        for group in (payload.library ?? []).prefix(100) {
            for (index, path) in (group.list ?? []).prefix(1000).enumerated() {
                guard entries.count < 1000 else { break }
                guard let url = VRLibraryURL.resolve(path, relativeTo: base), seen.insert(url).inserted else { continue }
                // Library indexes usually contain URLs only; do not fetch 1000 details
                // or thumbnails in the background to obtain prettier titles.
                entries.append(.init(url: url, title: "\(clean(group.name, fallback: "Videos")) · \(index + 1)"))
            }
        }
        let title = clean(payload.title, fallback: "VR library")
        let settings = settings(for: payload)
        var streams: [VRLibraryStream] = []
        var sourceURLs = Set<URL>()
        for media in (payload.media ?? []).prefix(32) {
            for source in (media.sources ?? []).prefix(64) {
                guard streams.count < 128 else { break }
                guard let url = VRLibraryURL.resolve(source.url, relativeTo: base), sourceURLs.insert(url).inserted else { continue }
                let candidate = MediaCandidate(id: "library-\(streams.count)", source: url.absoluteString,
                                               title: title, pageURL: base.absoluteString)
                let size = source.resolution?.text ?? ""
                let label = [clean(media.name, fallback: "Stream"), String(size.prefix(32))].filter { !$0.isEmpty }.joined(separator: " · ")
                streams.append(.init(candidate: candidate, label: label, projection: settings.0,
                                     layout: settings.1, unavailableReason: settings.2 ?? candidate.compatibility.reason))
            }
        }
        return .init(title: title, limitedAccess: access == 0, entries: entries, streams: streams)
    }

    private static func clean(_ value: String?, fallback: String) -> String {
        let text = String((value ?? "").filter { !$0.isNewline && !$0.unicodeScalars.contains(where: { $0.value < 32 }) }.prefix(160))
        return text.isEmpty ? fallback : text
    }

    private static func settings(for value: Payload) -> (VideoProjection?, StereoLayout?, String?) {
        let projection: VideoProjection
        switch value.projection?.lowercased() {
        case "equirectangular":
            guard let fov = value.fov, fov == 180 || fov == 360 else {
                return (nil, nil, "This library must specify a 180° or 360° equirectangular field of view.")
            }
            projection = fov == 180 ? .vr180 : .vr360
        case "equirectangular360":
            guard value.fov == nil || value.fov == 360 else {
                return (nil, nil, "The library contains conflicting projection and field-of-view settings.")
            }
            projection = .vr360
        default: return (nil, nil, "This library's projection is unsupported. VisionStream supports equirectangular VR180 and VR360.")
        }
        let layout: StereoLayout
        switch value.stereo?.lowercased() {
        case "mono": layout = .mono
        case "sbs": layout = .sideBySide
        case "tb": layout = .topBottom
        default: return (projection, nil, "This library's eye layout is missing or unsupported. MV-HEVC and custom layouts require another playback path.")
        }
        if value.alphaPackedSettings != nil || value.chromaKeySettings != nil {
            return (projection, layout, "This video declares passthrough masking, which VisionStream does not render.")
        }
        return (projection, layout, nil)
    }

    private struct Payload: Decodable {
        let access: Int?
        let title: String?
        let library: [Group]?
        let media: [Media]?
        let projection: String?
        let stereo: String?
        let fov: Double?
        let alphaPackedSettings: IgnoredObject?
        let chromaKeySettings: IgnoredObject?
    }
    private struct IgnoredObject: Decodable {}
    private struct Group: Decodable { let name: String?; let list: [String]? }
    private struct Media: Decodable { let name: String?; let sources: [Source]? }
    private struct Source: Decodable { let url: String; let resolution: Resolution? }
    private struct Resolution: Decodable {
        let text: String
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let number = try? value.decode(Int.self) { text = String(number) }
            else { text = try value.decode(String.self) }
        }
    }
}

public struct VRLibraryEntry: Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let title: String
}

public struct VRLibraryStream: Identifiable, Sendable {
    public var id: String { candidate.id }
    public let candidate: MediaCandidate
    public let label: String
    public let projection: VideoProjection?
    public let layout: StereoLayout?
    public let unavailableReason: String?
}

public enum VRLibraryURL {
    public static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
    }
    public static func resolve(_ value: String, relativeTo base: URL) -> URL? {
        guard !value.isEmpty, value.count <= 16_384,
              let url = URL(string: value, relativeTo: base)?.absoluteURL, isAllowed(url) else { return nil }
        return url
    }
}

public enum VRLibraryError: Error, LocalizedError, Equatable {
    case invalidURL, invalidDocument, accessDenied, tooLarge, redirected, http(Int), notJSON, network
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a direct HTTPS HereSphere library address without embedded credentials."
        case .invalidDocument: "This address did not return a supported HereSphere library or video document. Use the site's published player endpoint."
        case .accessDenied: "The library refused access. Sign in normally on the website. A separate player login or token may be required; this app does not implement that site's account interface."
        case .tooLarge: "The library exceeds the 2 MB limit. Open a smaller library or an individual video endpoint."
        case .redirected: "The library redirected the request. Open its final HTTPS address in the browser, then connect to that address."
        case .http(let code): "The library returned HTTP \(code). It may require a different address, request method, or a separate player login."
        case .notJSON: "The address returned a webpage instead of a JSON library. Complete the website's normal access steps and use its published player endpoint."
        case .network: "The library could not be reached. Check the address, connection, and website access requirements."
        }
    }
}
