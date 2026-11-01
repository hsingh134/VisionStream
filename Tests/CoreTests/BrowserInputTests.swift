import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class BrowserInputTests: XCTestCase {
    func testAddressesStayAddressesAndQueriesAreEncoded() throws {
        XCTAssertEqual(BrowserInput.destination("example.com/path")?.absoluteString, "https://example.com/path")
        XCTAssertEqual(BrowserInput.destination("https://example.com/watch?q=a#part")?.fragment, "part")
        XCTAssertEqual(BrowserInput.destination("localhost:8443/library")?.host, "localhost")
        let result = try XCTUnwrap(BrowserInput.destination("VR films & nature"))
        XCTAssertEqual(result.host, "duckduckgo.com")
        XCTAssertEqual(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "VR films & nature")
        XCTAssertTrue(BrowserInput.isSearch("nature"))
        XCTAssertFalse(BrowserInput.isSearch("example.com"))
    }
    func testInvalidOrCredentialBearingURLsNeverBecomeSearches() {
        for value in ["", "https://user:password@example.com/private", "file:///private/video.mp4", "javascript:alert(1)", "https://", "https://bad host.example", "two\nlines", String(repeating: "x", count: 8200)] {
            XCTAssertNil(BrowserInput.destination(value), value)
        }
    }
}
