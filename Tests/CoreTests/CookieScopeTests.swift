import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class CookieScopeTests: XCTestCase {
    private func cookie(_ name: String, domain: String, path: String = "/", expired: Bool = false) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "test", .domain: domain, .path: path, .secure: "TRUE"]
        if expired { properties[.expires] = Date(timeIntervalSince1970: 0) }
        return HTTPCookie(properties: properties)!
    }
    func testDomainAndPathBoundaries() throws {
        let cookies = [cookie("parent", domain: ".example.com"), cookie("host", domain: "cdn.example.com"),
                       cookie("other", domain: "other.example.com"), cookie("attack", domain: ".ample.com"),
                       cookie("path", domain: ".example.com", path: "/video"),
                       cookie("badpath", domain: ".example.com", path: "/vid"),
                       cookie("expired", domain: ".example.com", expired: true)]
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/video/clip.mp4"))
        XCTAssertEqual(Set(CookieScope.matching(cookies, url: url).map(\.name)), ["parent", "host", "path"])
        XCTAssertTrue(CookieScope.matching(cookies, url: URL(string: "https://example.com.attacker.test/video/a")!).isEmpty)
        XCTAssertTrue(CookieScope.matching(cookies, url: URL(string: "http://cdn.example.com/video/a")!).isEmpty)
    }
    func testExactCookiePathDoesNotMatchSiblingPrefix() {
        let item = cookie("session", domain: ".example.com", path: "/account")
        XCTAssertEqual(CookieScope.matching([item], url: URL(string: "https://example.com/account")!).count, 1)
        XCTAssertTrue(CookieScope.matching([item], url: URL(string: "https://example.com/accounts")!).isEmpty)
    }
}
