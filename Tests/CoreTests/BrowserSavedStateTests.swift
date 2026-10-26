import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class BrowserSavedStateTests: XCTestCase {
    func testRestorationSeparatesHomeWebsiteAndExactPage() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com:8443/watch?id=private#/part/2"))
        XCTAssertNil(BrowserRestoration.home.address(url))
        XCTAssertEqual(BrowserRestoration.website.address(url)?.absoluteString, "https://example.com:8443/")
        XCTAssertEqual(BrowserRestoration.page.address(url), url)
        for source in ["file:///private/test.mp4", "https://user:password@example.com/watch", "https://example.com/v.mp4?token=private", "https://example.com/master.m3u8"] {
            let candidate = try XCTUnwrap(URL(string: source))
            XCTAssertNil(BrowserRestoration.website.address(candidate)); XCTAssertNil(BrowserRestoration.page.address(candidate))
        }
    }
    func testBookmarkInputIsBoundedAndKeepsIntentionalPageIdentifiers() throws {
        let bookmark = try XCTUnwrap(WebsiteBookmark(name: "Page\nName", address: "https://example.com/watch?id=123#chapter-2"))
        XCTAssertEqual(bookmark.address, "https://example.com/watch?id=123#chapter-2")
        XCTAssertEqual(bookmark.name, "PageName")
        XCTAssertEqual(WebsiteBookmark(name: "", address: "https://example.com")?.name, "example.com")
        XCTAssertNil(WebsiteBookmark(name: "Unsafe", address: "https://user:password@example.com"))
        XCTAssertNil(WebsiteBookmark(name: "Video", address: "https://example.com/v.mp4"))
        XCTAssertNil(WebsiteBookmark(name: "Huge", address: "https://example.com/" + String(repeating: "x", count: 8200)))
    }
}
