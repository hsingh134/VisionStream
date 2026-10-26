import Foundation

public enum BrowserRestoration: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, website, page
    public var id: String { rawValue }
    public var label: String { switch self { case .home: "Home"; case .website: "Last website"; case .page: "Last page" } }
    public func address(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else { return nil }
        if self == .home { return nil }
        guard !["mp4", "m4v", "m3u8"].contains(url.pathExtension.lowercased()) else { return nil }
        if self == .website { parts.path = "/"; parts.query = nil; parts.fragment = nil }
        return parts.url
    }
}

public struct WebsiteBookmark: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let address: String
    public init?(id: UUID = UUID(), name: String, address: String) {
        guard address.utf8.count <= 8192, let url = BrowserAddress.resolve(address),
              let cleaned = BrowserRestoration.page.address(url), cleaned.absoluteString.utf8.count <= 8192 else { return nil }
        self.id = id; self.address = cleaned.absoluteString
        let text = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = text.isEmpty || text.contains("://") ? (cleaned.host ?? "Website") : text
    }
}
