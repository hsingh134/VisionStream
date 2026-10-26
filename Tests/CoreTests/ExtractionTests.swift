import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class ExtractionTests: XCTestCase {
    private func document(source: String = "https://cdn.example/video.mp4?token=private",
                          mime: String = "video/mp4", reason: String = "", advisory: String = "") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": "ok", "streams": [[
            "source": source, "mimeType": mime, "width": 2880, "height": 1440,
            "unavailableReason": reason, "advisory": advisory
        ]]])
    }

    func testResolvedFormatsAndPrivateDisplay() throws {
        let mp4 = try ExtractedMedia.parse(document()).streams[0]
        XCTAssertEqual(mp4.label, "MP4 · 2880 × 1440")
        XCTAssertNil(mp4.unavailableReason)
        XCTAssertFalse(mp4.label.contains("private"))
        XCTAssertFalse(mp4.candidate.displaySource.contains("private"))
        let hls = try ExtractedMedia.parse(document(source: "https://cdn.example/master.m3u8", mime: "application/vnd.apple.mpegurl")).streams[0]
        XCTAssertEqual(hls.label, "HLS · 2880 × 1440")
        XCTAssertEqual(hls.candidate.compatibility, .candidate)
    }

    func testUnsupportedFeaturesRemainBlocked() throws {
        for code in ["projection", "protected", "separate_audio", "required_headers", "unknown"] {
            let stream = try ExtractedMedia.parse(document(reason: code)).streams[0]
            XCTAssertNotNil(stream.unavailableReason)
            XCTAssertFalse(stream.unavailableReason?.contains("private") == true)
        }
    }

    func testAutomaticPlaylistLabelIsExplicitAndPrivate() throws {
        var payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: document(mime: "application/vnd.apple.mpegurl")) as? [String: Any])
        var entries = try XCTUnwrap(payload["streams"] as? [[String: Any]])
        entries[0]["adaptive"] = true
        entries[0]["width"] = 0; entries[0]["height"] = 0
        payload["streams"] = entries
        let automatic = try ExtractedMedia.parse(JSONSerialization.data(withJSONObject: payload)).streams[0]
        XCTAssertTrue(automatic.isAdaptive)
        XCTAssertEqual(automatic.label, "HLS · Automatic quality")
        XCTAssertFalse(automatic.label.contains("private"))
        XCTAssertNil(automatic.unavailableReason)
        XCTAssertEqual(automatic.candidate.width, 0)
        let old = try ExtractedMedia.parse(document()).streams[0]
        XCTAssertFalse(old.isAdaptive)
        XCTAssertEqual(old.label, "MP4 · 2880 × 1440")
        entries[0]["adaptive"] = false
        entries[0]["mimeType"] = "video/mp4"
        entries[0]["height"] = 1440
        payload["streams"] = entries
        let heightOnly = try ExtractedMedia.parse(JSONSerialization.data(withJSONObject: payload)).streams[0]
        XCTAssertEqual(heightOnly.label, "MP4 · 1440p")
        XCTAssertEqual(heightOnly.candidate.width, 0)
    }

    func testHeaderAdvisoryDoesNotBlockOrExposeRequestInformation() throws {
        let stream = try ExtractedMedia.parse(document(mime: "application/vnd.apple.mpegurl", advisory: "request_context")).streams[0]
        XCTAssertNil(stream.unavailableReason)
        XCTAssertEqual(stream.candidate.compatibility, .candidate)
        XCTAssertNotNil(stream.advisory)
        XCTAssertFalse(stream.advisory?.contains("private") == true)
        let blocked = try ExtractedMedia.parse(document(reason: "required_headers", advisory: "request_context")).streams[0]
        XCTAssertNotNil(blocked.unavailableReason)
        let unknown = try ExtractedMedia.parse(document(advisory: "https://private.example/?secret=value")).streams[0]
        XCTAssertFalse(unknown.advisory?.contains("private") == true)
        XCTAssertFalse(unknown.advisory?.contains("secret") == true)
    }

    func testUnsafeResolvedSourcesAreRejected() throws {
        for source in ["http://cdn.example/a.mp4", "file:///tmp/a.mp4", "blob:https://cdn.example/a", "https://user:pass@cdn.example/a.mp4"] {
            XCTAssertNil(try? ExtractedMedia.parse(document(source: source)))
        }
        XCTAssertNil(try? ExtractedMedia.parse(document(mime: "application/dash+xml")))
    }

    func testMalformedAndOversizedResultsAreRejected() throws {
        XCTAssertNil(try? ExtractedMedia.parse(Data("invalid".utf8)))
        XCTAssertNil(try? ExtractedMedia.parse(Data(repeating: 0, count: 1_048_577)))
        let stream = try XCTUnwrap((try JSONSerialization.jsonObject(with: document()) as? [String: Any])?["streams"] as? [[String: Any]])[0]
        let tooMany = try JSONSerialization.data(withJSONObject: ["status": "ok", "streams": Array(repeating: stream, count: 33)])
        XCTAssertNil(try? ExtractedMedia.parse(tooMany))
    }

    func testRemoteStatusCannotBecomeAnErrorDescription() throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": "https://private.example/?token=secret", "streams": []])
        do { _ = try ExtractedMedia.parse(data); XCTAssertTrue(false) }
        catch { XCTAssertFalse(error.localizedDescription.contains("secret")); XCTAssertFalse(error.localizedDescription.contains("private.example")) }
    }
}
