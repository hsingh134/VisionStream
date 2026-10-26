import Foundation

public enum CookieScope {
    /// Filter before giving cookies to AVURLAsset. AVFoundation also enforces cookie scope.
    public static func matching(_ cookies: [HTTPCookie], url: URL, now: Date = Date()) -> [HTTPCookie] {
        guard let host = url.host?.lowercased(), url.scheme?.lowercased() == "https" else { return [] }
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let hostMatches = host == bare || (domain.hasPrefix(".") && host.hasSuffix("." + bare))
            let path = url.path.isEmpty ? "/" : url.path
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = path == cookiePath || (path.hasPrefix(cookiePath) &&
                (cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).hasPrefix("/")))
            return hostMatches && pathMatches && (cookie.expiresDate.map { $0 > now } ?? true)
        }
    }
}
