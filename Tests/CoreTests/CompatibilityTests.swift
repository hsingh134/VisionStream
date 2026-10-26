import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class CompatibilityTests: XCTestCase {
    func testSupportedCandidates() {
        for source in ["https://cdn.example/v.mp4?token=a", "https://cdn.example/master.m3u8", "https://cdn.example/signed?id=1"] {
            XCTAssertEqual(MediaCandidate(id: "1", source: source).compatibility, .candidate)
        }
        XCTAssertEqual(MediaCandidate(id: "1", source: "https://cdn.example/path", mimeType: "video/mp4; codecs=avc1").compatibility, .candidate)
        XCTAssertEqual(MediaCandidate(id: "1", source: "https://cdn.example/path", mimeType: "application/vnd.apple.mpegurl").compatibility, .candidate)
        for mime in [" Video/MP4 ; codecs=avc1", "application/vnd.apple.mpegurl \t; charset=utf-8"] {
            let media = MediaCandidate(id: "spaces", source: "https://cdn.example/signed", mimeType: mime)
            XCTAssertEqual(media.compatibility, .candidate)
            XCTAssertFalse(media.normalizedMIMEType.contains(" "))
            XCTAssertTrue(media.displaySource.contains("MP4") || media.displaySource.contains("HLS"))
        }
    }

    func testRejectedSchemesAndFormats() {
        for source in ["blob:https://site.example/123", "data:video/mp4,a", "file:///tmp/a.mp4", "http://cdn.example/v.mp4",
                       "https://user:password@cdn.example/v.mp4", "https://cdn.example/v.webm", "", "not a url"] {
            XCTAssertNotNil(MediaCandidate(id: "1", source: source).compatibility.reason, source)
        }
        XCTAssertNotNil(MediaCandidate(id: "1", source: "https://cdn.example/v.mp4", mimeType: "application/dash+xml").compatibility.reason)
    }

    func testDefaultSelectionPrefersPreparedDirectVideoOverInactiveFallback() {
        let inactive = MediaCandidate(id: "a", source: "https://site.example/fallback", mimeType: "video/mp4",
            webMedia: .init(errorCode: 0, readyState: 0, networkState: 3, paused: true))
        let playing = MediaCandidate(id: "b", source: "https://cdn.example/master.m3u8", width: 1280, height: 720,
            webMedia: .init(errorCode: 0, readyState: 4, networkState: 2, paused: false))
        let blob = MediaCandidate(id: "c", source: "blob:https://site.example/ad", width: 4096, height: 2048,
            webMedia: .init(errorCode: 0, readyState: 4, networkState: 1, paused: false))
        XCTAssertEqual(MediaCandidate.preferredForPlayback(in: [inactive, playing, blob])?.id, "b")
        XCTAssertEqual(MediaCandidate.preferredForPlayback(in: [blob, playing, inactive])?.id, "b")
        var paused = playing; paused.id = "paused"; paused.webMedia?.paused = true
        XCTAssertEqual(MediaCandidate.preferredForPlayback(in: [paused, playing])?.id, "b")
        var larger = playing; larger.id = "larger"; larger.width = 2560; larger.height = 1440
        XCTAssertEqual(MediaCandidate.preferredForPlayback(in: [playing, larger])?.id, "larger")
        var failed = larger; failed.id = "failed"; failed.webMedia?.errorCode = 3
        XCTAssertEqual(MediaCandidate.preferredForPlayback(in: [failed, playing])?.id, "b")
        XCTAssertEqual(MediaCandidate.preferredForPlayback(in: [blob])?.id, "c")
        XCTAssertEqual(MediaCandidate.preferredForPlayback(in: [inactive])?.id, "a")
        XCTAssertNil(MediaCandidate.preferredForPlayback(in: []))
    }

    func testEncryptionTakesPrecedence() {
        XCTAssertTrue(MediaCandidate(id: "1", source: "https://cdn.example/v.mp4", encrypted: true).compatibility.reason?.contains("encrypted") == true)
    }

    func testDisplayRedactsTokens() {
        let media = MediaCandidate(id: "1", source: "https://cdn.example/path/secret.mp4?token=private#secret")
        XCTAssertEqual(media.displaySource, "cdn.example · MP4")
        XCTAssertFalse(media.displaySource.contains("secret"))
        XCTAssertFalse(media.displaySource.contains("private"))
    }

    func testBrowserAddressValidation() {
        XCTAssertEqual(BrowserAddress.resolve(" example.com/path ")?.absoluteString, "https://example.com/path")
        XCTAssertEqual(BrowserAddress.resolve("https://example.com/path?q=a")?.query, "q=a")
        for value in ["", "javascript://alert(1)", "file:///tmp/a", "https://user:pass@example.com", "not an address"] {
            XCTAssertNil(BrowserAddress.resolve(value), value)
        }
    }

    func testDetectorJSONContract() throws {
        let json = #"[{"id":"frame:v:0","videoID":"v","source":"https://cdn.example/video.mp4","mimeType":"video/mp4","title":"Example","pageURL":"https://example.com","encrypted":false,"width":4096,"height":2048,"currentTime":15.5}]"#
        let decoded = try JSONDecoder().decode([MediaCandidate].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].currentTime, 15.5)
        XCTAssertEqual(decoded[0].compatibility, .candidate)
    }
}
