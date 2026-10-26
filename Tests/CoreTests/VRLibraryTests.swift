import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class VRLibraryTests: XCTestCase {
    private let base = URL(string: "https://library.example/heresphere/")!

    func testLibraryResolvesRelativeLinksAndFiltersUnsafeURLs() throws {
        let document = try parse(#"{"access":0,"library":[{"name":"Previews","list":["one","one","https://other.example/two","http://unsafe.example/a","https://user:pass@bad.example/a","file:///a","javascript:alert(1)"]}]}"#)
        XCTAssertTrue(document.limitedAccess)
        XCTAssertEqual(document.entries.count, 2)
        XCTAssertEqual(document.entries[0].url.absoluteString, "https://library.example/heresphere/one")
        XCTAssertEqual(document.entries[1].url.host, "other.example")
        XCTAssertTrue(document.streams.isEmpty)
    }

    func testProjectionAndStereoAreIndependentAndExplicit() throws {
        for (name, fov, projection) in [("equirectangular",180,VideoProjection.vr180),("equirectangular",360,.vr360),("equirectangular360",360,.vr360)] {
            for (stereo, layout) in [("mono",StereoLayout.mono),("sbs",.sideBySide),("tb",.topBottom)] {
                let document = try scene(projection: name, fov: fov, stereo: stereo)
                XCTAssertEqual(document.streams.count, 2)
                XCTAssertEqual(document.streams[0].projection, projection)
                XCTAssertEqual(document.streams[0].layout, layout)
                XCTAssertNil(document.streams[0].unavailableReason)
                XCTAssertEqual(document.streams[0].candidate.compatibility, .candidate)
                XCTAssertEqual(document.streams[1].label, "HLS · 2160")
            }
        }
    }

    func testUnsupportedProjectionPackingAndMaskingAreNotGuessed() throws {
        for (projection, fov, stereo) in [("fisheye",180,"sbs"),("perspective",180,"sbs"),("equirectangular",190,"sbs"),("equirectangular360",180,"sbs"),("equirectangular",180,"mvhevc"),("equirectangular",180,"")] {
            let document = try scene(projection: projection, fov: fov, stereo: stereo)
            XCTAssertNotNil(document.streams.first?.unavailableReason)
        }
        for key in ["alphaPackedSettings","chromaKeySettings"] {
            let data = #"{"access":1,"projection":"equirectangular","fov":180,"stereo":"sbs","media":[{"sources":[{"url":"a.mp4"}]}],"# + "\"\(key)\":{}}"
            let document = try parse(data)
            XCTAssertTrue(document.streams[0].unavailableReason?.contains("masking") == true)
        }
        let missing = try parse(#"{"access":1,"media":[{"sources":[{"url":"a.mp4"}]}]}"#)
        XCTAssertNotNil(missing.streams[0].unavailableReason)
    }

    func testAccessAndInvalidDocumentsFailWithoutExposingSecrets() throws {
        for json in [#"{"access":-1,"library":[]}"#,#"{"access":2,"library":[]}"#] {
            do { _ = try parse(json); XCTAssertTrue(false, "Access must be enforced") }
            catch { XCTAssertEqual(error as? VRLibraryError, .accessDenied) }
        }
        for json in ["<html>secret</html>","{}",#"{"access":1}"#,#"{"access":1,"library":"secret"}"#] {
            do { _ = try parse(json); XCTAssertTrue(false, "Invalid document must fail") }
            catch { XCTAssertEqual(error as? VRLibraryError, .invalidDocument); XCTAssertFalse(error.localizedDescription.contains("secret")) }
        }
    }

    func testStreamURLValidationAndRedaction() throws {
        let json = #"{"access":1,"projection":"equirectangular","fov":180,"stereo":"sbs","media":[{"sources":[{"url":"https://cdn.example/video.mp4?token=private"},{"url":"https://cdn.example/video.webm"},{"url":"blob:https://cdn.example/a"},{"url":"http://cdn.example/a.mp4"}]}]}"#
        let document = try parse(json)
        XCTAssertEqual(document.streams.count, 2)
        XCTAssertNil(document.streams[0].unavailableReason)
        XCTAssertTrue(document.streams[0].candidate.source.contains("token=private"))
        XCTAssertFalse(document.streams[0].candidate.displaySource.contains("private"))
        XCTAssertNotNil(document.streams[1].unavailableReason)
    }

    func testLibraryBoundsAndOversizedDocuments() throws {
        let links = (0..<1500).map { "\"item-\($0)\"" }.joined(separator: ",")
        let document = try parse("{\"access\":1,\"library\":[{\"list\":[\(links)]}]}")
        XCTAssertEqual(document.entries.count, 1000)
        do {
            _ = try VRLibraryDocument.parse(Data(repeating: 32, count: VRLibraryDocument.maximumBytes + 1), relativeTo: base)
            XCTAssertTrue(false, "Oversized documents must fail")
        } catch { XCTAssertEqual(error as? VRLibraryError, .tooLarge) }
    }

    private func parse(_ json: String) throws -> VRLibraryDocument {
        try VRLibraryDocument.parse(Data(json.utf8), relativeTo: base)
    }
    private func scene(projection: String, fov: Int, stereo: String) throws -> VRLibraryDocument {
        try parse("""
        {"access":1,"title":"Calibration","projection":"\(projection)","fov":\(fov),"stereo":"\(stereo)","media":[
        {"name":"MP4","sources":[{"resolution":1080,"url":"../video.mp4"}]},
        {"name":"HLS","sources":[{"resolution":"2160","url":"https://cdn.example/master.m3u8"}]}]}
        """)
    }
}
