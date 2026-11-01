import Foundation

/// Only an explicit address/search submission can contact the search provider.
/// Invalid explicit URLs are never sent to a search engine as a fallback.
public enum BrowserInput {
    public static func destination(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 8192,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if text.contains("://") { return BrowserAddress.resolve(text) }
        if !text.contains(" "), let url = BrowserAddress.resolve(text),
           url.host == "localhost" || text.contains(".") || text.hasPrefix("[") { return url }
        guard text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) == nil,
              text.utf8.count <= 2048 else { return nil }
        var parts = URLComponents(string: "https://duckduckgo.com/")!
        parts.queryItems = [URLQueryItem(name: "q", value: text)]
        return parts.url
    }

    public static func isSearch(_ input: String) -> Bool {
        guard let url = destination(input) else { return false }
        return url.host == "duckduckgo.com" && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "q" }) == true
    }
}
