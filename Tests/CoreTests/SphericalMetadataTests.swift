#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
import Foundation
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class SphericalMetadataTests: XCTestCase {
    private func box(_ type: String, _ payload: Data) -> Data {
        let n = UInt32(payload.count + 8)
        return Data([UInt8((n >> 24)&255),UInt8((n >> 16)&255),UInt8((n >> 8)&255),UInt8(n&255)]) + Data(type.utf8) + payload
    }
    private func xml(_ extra: String = "", namespace: String = "http://ns.google.com/videos/1.0/spherical/") -> Data {
        Data("<rdf:SphericalVideo xmlns:rdf=\"urn:rdf\" xmlns:s=\"\(namespace)\"><s:Spherical>true</s:Spherical><s:Stitched>true</s:Stitched><s:ProjectionType>equirectangular</s:ProjectionType>\(extra)</rdf:SphericalVideo>".utf8)
    }
    private func movie(_ xml: Data, audio: Bool = false) -> Data {
        let identifier = Data([0xff,0xcc,0x82,0x63,0xf8,0x55,0x4a,0x93,0x88,0x14,0x58,0x7a,0x02,0x52,0x1f,0xdd])
        let handler = Data(repeating: 0, count: 8) + Data((audio ? "soun" : "vide").utf8)
        return box("ftyp", Data("isom".utf8)) + box("moov", box("trak", box("mdia",box("hdlr",handler)) + box("uuid",identifier+xml)))
    }
    func testActualMovieHierarchyAndExplicitPacking() {
        XCTAssertEqual(MP4SphericalMetadata.hint(prefix: movie(xml()))?.projection, .vr360)
        XCTAssertEqual(MP4SphericalMetadata.hint(prefix: movie(xml()))?.layout, .mono)
        XCTAssertEqual(MP4SphericalMetadata.hint(prefix: movie(xml("<s:StereoMode>left-right</s:StereoMode>")))?.layout, .sideBySide)
        XCTAssertEqual(MP4SphericalMetadata.hint(prefix: movie(xml("<s:StereoMode>top-bottom</s:StereoMode>")))?.layout, .topBottom)
        // An incomplete media-data tail must not hide the complete fast-start moov.
        let tail = Data([0,16,0,0]) + Data("mdat".utf8) + Data(repeating:0,count:20)
        XCTAssertEqual(MP4SphericalMetadata.hint(prefix: movie(xml()) + tail)?.projection, .vr360)
        XCTAssertNil(MP4SphericalMetadata.hint(prefix: movie(xml(), audio: true)))
        XCTAssertNil(MP4SphericalMetadata.hint(prefix: box("mdat",movie(xml()))))
    }
    func testCroppedMetadataOnlyAcceptsSupportedCenteredProjection() {
        let sizes = "<s:FullPanoWidthPixels>2048</s:FullPanoWidthPixels><s:FullPanoHeightPixels>1024</s:FullPanoHeightPixels><s:CroppedAreaImageWidthPixels>1024</s:CroppedAreaImageWidthPixels><s:CroppedAreaImageHeightPixels>1024</s:CroppedAreaImageHeightPixels>"
        XCTAssertEqual(MP4SphericalMetadata.hint(prefix: movie(xml(sizes + "<s:CroppedAreaLeftPixels>512</s:CroppedAreaLeftPixels>")))?.projection, .vr180)
        XCTAssertNil(MP4SphericalMetadata.hint(prefix: movie(xml(sizes + "<s:CroppedAreaLeftPixels>0</s:CroppedAreaLeftPixels>"))))
        XCTAssertNil(MP4SphericalMetadata.hint(prefix: movie(xml(sizes + "<s:CroppedAreaLeftPixels>9223372036854775807</s:CroppedAreaLeftPixels>"))))
        XCTAssertNil(MP4SphericalMetadata.hint(prefix: movie(xml("<s:FullPanoWidthPixels>2048</s:FullPanoWidthPixels>"))))
    }
    func testMalformedUntrustedMetadataIsRejected() {
        for data in [Data(), Data([0,0,0,1]), Data(repeating:0,count:MP4SphericalMetadata.maximumPrefixBytes+1), movie(Data("<!DOCTYPE x [<!ENTITY evil SYSTEM 'file:///private'>]><x>&evil;</x>".utf8)), movie(xml(namespace:"https://unrelated.example/")), movie(xml("<s:StereoMode>mesh</s:StereoMode>")), movie(xml("<s:Spherical>false</s:Spherical>"))] {
            XCTAssertNil(MP4SphericalMetadata.hint(prefix:data))
        }
        let valid = movie(xml())
        for count in [1,7,16,valid.count-1] { XCTAssertNil(MP4SphericalMetadata.hint(prefix:Data(valid.prefix(count)))) }
    }
}
