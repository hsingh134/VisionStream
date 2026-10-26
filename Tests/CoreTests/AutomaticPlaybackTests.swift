import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class AutomaticPlaybackTests:XCTestCase {
    private func video(_ id:String="video",intent:String?=UUID().uuidString,age:Double=0,visible:Bool=true)->MediaCandidate {
        .init(id:id,videoID:id,source:"https://media.example/vr180-sbs.mp4",width:1440,height:720,
              webMedia:.init(errorCode:0,readyState:4,networkState:2,paused:false),
              playIntent:intent.map { .init(id:$0,age:age,visible:visible) })
    }
    func testAutoplayDoesNotOpenAndPlayGestureWaitsForReadiness() {
        var policy=AutomaticPlayback()
        XCTAssertNil(policy.next(in:[video(intent:nil)],navigation:1,pageAge:10))
        var media=video();media.webMedia?.readyState=0
        XCTAssertNil(policy.next(in:[media],navigation:1,pageAge:10))
        media.webMedia?.readyState=4;media.webMedia?.paused=true
        XCTAssertNil(policy.next(in:[media],navigation:1,pageAge:10))
        media.webMedia?.paused=false
        XCTAssertEqual(policy.next(in:[media],navigation:1,pageAge:10)?.id,media.id)
    }
    func testOneHandoffUntilANewGestureEvenAfterFailureReturnOrSourceChange() {
        var policy=AutomaticPlayback(),media=video()
        XCTAssertNotNil(policy.next(in:[media],navigation:1,pageAge:10))
        for _ in 0..<5 { XCTAssertNil(policy.next(in:[media],navigation:1,pageAge:10)) }
        media.source="https://media.example/new-variant.m3u8"
        XCTAssertNil(policy.next(in:[media],navigation:1,pageAge:10))
        media.playIntent?.id=UUID().uuidString
        XCTAssertNotNil(policy.next(in:[media],navigation:1,pageAge:10))
    }
    func testNavigationAndGestureBoundsRejectStaleHiddenMalformedAndProtectedMedia() {
        let accepted=video()
        var invalid:[MediaCandidate]=[]
        for age in [-1,31,Double.infinity,Double.nan] { var m=accepted;m.playIntent?.age=age;invalid.append(m) }
        var m=accepted;m.playIntent?.id="not-an-id";invalid.append(m)
        m=accepted;m.playIntent?.visible=false;invalid.append(m)
        m=accepted;m.encrypted=true;invalid.append(m)
        m=accepted;m.source="blob:https://media.example/local";invalid.append(m)
        m=accepted;m.width=0;invalid.append(m)
        m=accepted;m.webMedia?.errorCode=4;invalid.append(m)
        for media in invalid { var policy=AutomaticPlayback();XCTAssertNil(policy.next(in:[media],navigation:1,pageAge:40)) }
        var policy=AutomaticPlayback(),old=accepted;old.playIntent?.age=10
        XCTAssertNil(policy.next(in:[old],navigation:2,pageAge:1))
        old.playIntent?.age=0
        XCTAssertNotNil(policy.next(in:[old],navigation:2,pageAge:1))
    }
    func testDisabledPreferenceConsumesGestureRatherThanLaunchingWhenReenabled() {
        var policy=AutomaticPlayback();let media=video()
        XCTAssertNil(policy.next(in:[media],navigation:1,pageAge:10,enabled:false))
        XCTAssertNil(policy.next(in:[media],navigation:1,pageAge:10,enabled:true))
        XCTAssertNotNil(policy.next(in:[video()],navigation:1,pageAge:10))
    }
    func testNewestPreparedIntentWinsAndFallbacksUseTheSameElementIntent() {
        var policy=AutomaticPlayback();let older=video("older",age:5),newer=video("newer",age:1)
        var fallback=newer;fallback.id="unready";fallback.width=0;fallback.webMedia?.readyState=0
        XCTAssertEqual(policy.next(in:[older,fallback,newer],navigation:1,pageAge:10)?.id,"newer")
    }
    func testVideoBarOnlyHasActionableNativeSources() {
        let good=video();var blob=good;blob.id="blob";blob.source="blob:https://media.example/local"
        var protected=good;protected.id="protected";protected.encrypted=true
        var insecure=good;insecure.id="insecure";insecure.source="http://media.example/a.mp4"
        var hls=good;hls.id="hls";hls.source="https://media.example/a.m3u8"
        XCTAssertTrue(AutomaticPlayback.actionable(in:[]).isEmpty)
        XCTAssertTrue(AutomaticPlayback.actionable(in:[blob,protected,insecure]).isEmpty)
        XCTAssertEqual(AutomaticPlayback.actionable(in:[good,blob,protected,hls]).map(\.id),[good.id,hls.id])
    }
    func testBusyPageBoundNeverEvictsATokenAndReopensOldVideo() {
        var policy=AutomaticPlayback();let first=video()
        XCTAssertNotNil(policy.next(in:[first],navigation:1,pageAge:10))
        for _ in 0..<511 { XCTAssertNotNil(policy.next(in:[video()],navigation:1,pageAge:10)) }
        XCTAssertNil(policy.next(in:[first],navigation:1,pageAge:10))
        XCTAssertNil(policy.next(in:[video()],navigation:1,pageAge:10))
        XCTAssertNotNil(policy.next(in:[video()],navigation:2,pageAge:10))
    }
}
