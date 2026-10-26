import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class ClearHLSPlanTests:XCTestCase {
    let base=URL(string:"https://example.com/quality/media.m3u8?token=private")!
    let playlist="#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:732\n#EXTINF:4,\nfirst.ts?signature=published\n#EXTINF:2.5,\nlast.ts\n#EXT-X-ENDLIST\n"
    func testFiniteClearMuxedPlanPreservesPublishedResourceAndSequence() throws {
        let plan=try ClearHLSPlan(data:Data(playlist.utf8),base:base)
        XCTAssertEqual(plan.duration,6.5);XCTAssertEqual(plan.segments.count,2)
        XCTAssertEqual(plan.segments.first?.index,732)
        XCTAssertEqual(plan.segments.first?.url.absoluteString,"https://example.com/quality/first.ts?signature=published")
        XCTAssertNil(plan.segments.last?.url.query)
    }
    func testRejectsEncryptedLiveFragmentedAndDiscontinuousSources() throws {
        for tag in ["#EXT-X-KEY:METHOD=AES-128,URI=\"key\"","#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"key\"","#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"key\"","#EXT-X-DEFINE:NAME=\"path\",VALUE=\"a\"","#EXT-X-MAP:URI=\"init.mp4\"","#EXT-X-BYTERANGE:400@0","#EXT-X-DISCONTINUITY","#EXT-X-PART:DURATION=0.1,URI=\"part.ts\""] {
            XCTAssertThrowsError(try ClearHLSPlan(data:Data(playlist.replacingOccurrences(of:"#EXTM3U\n",with:"#EXTM3U\n"+tag+"\n").utf8),base:base))
        }
        XCTAssertThrowsError(try ClearHLSPlan(data:Data(playlist.replacingOccurrences(of:"#EXT-X-ENDLIST",with:"").utf8),base:base))
        XCTAssertThrowsError(try ClearHLSPlan(data:Data(playlist.replacingOccurrences(of:"last.ts",with:"last.m4s").utf8),base:base))
    }
    func testRejectsInvalidDurationOrMissingSegmentWithoutSilentlyTruncating() {
        for interval in ["nan","inf","-1","0","121"] {
            XCTAssertThrowsError(try ClearHLSPlan(data:Data(playlist.replacingOccurrences(of:"#EXTINF:4,",with:"#EXTINF:\(interval),").utf8),base:base))
        }
        XCTAssertThrowsError(try ClearHLSPlan(data:Data(playlist.replacingOccurrences(of:"first.ts?signature=published",with:"").utf8),base:base))
    }
}
