import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

@MainActor final class BrowserCookieSnapshotTests:XCTestCase {
    private let url=URL(string:"https://media.example/private/video.mp4")!
    private func cookie(_ value:String,domain:String="media.example",path:String="/private/",expired:Bool=false)->HTTPCookie {
        var properties:[HTTPCookiePropertyKey:Any]=[.name:"session",.value:value,.domain:domain,.path:path,.secure:"TRUE"]
        if expired { properties[.expires]=Date().addingTimeInterval(-60) }
        return HTTPCookie(properties:properties)!
    }
    private func ready(_ condition:()->Bool) async {
        for _ in 0..<50 { if condition() { return };await Task.yield() }
        XCTAssertTrue(condition())
    }
    func testFreshCookiesAreNormallyScopedAndExpiredCookiesAreExcluded() async {
        let allowed=cookie("valid"),foreign=cookie("foreign",domain:"other.example"),sibling=cookie("sibling",path:"/private-other/"),expired=cookie("expired",expired:true)
        let store=BrowserCookieSnapshot { callback in callback([allowed,foreign,sibling,expired]) }
        let values=await store.cookies(for:url)
        XCTAssertEqual(values.map(\.value),["valid"])
        let insecure=await store.cookies(for:URL(string:"http://media.example/private/video.mp4")!)
        XCTAssertTrue(insecure.isEmpty)
    }
    func testTimeoutUsesPreviousSnapshotAndLateReplyCanRefreshWithoutDoubleCompletion() async {
        var callbacks:[@MainActor ([HTTPCookie])->Void]=[]
        let store=BrowserCookieSnapshot(timeout:.milliseconds(20)) { callbacks.append($0) }
        let first=Task { await store.cookies(for:url) }
        await ready { callbacks.count==1 };callbacks[0]([cookie("first")])
        let initial=await first.value;XCTAssertEqual(initial.map(\.value),["first"])
        let second=Task { await store.cookies(for:url) }
        await ready { callbacks.count==2 }
        let fallback=await second.value;XCTAssertEqual(fallback.map(\.value),["first"])
        callbacks[1]([cookie("new")])
        let refreshed=await store.cookies(for:url)
        XCTAssertEqual(refreshed.map(\.value),["new"])
    }
    func testClearReleasesWaitingReadAndRejectsRepliesFromBeforeLogout() async {
        var callbacks:[@MainActor ([HTTPCookie])->Void]=[]
        let store=BrowserCookieSnapshot(timeout:.milliseconds(20)) { callbacks.append($0) }
        let first=Task { await store.cookies(for:url) }
        await ready { callbacks.count==1 };callbacks[0]([cookie("old")]);_ = await first.value
        let waiting=Task { await store.cookies(for:url) }
        await ready { callbacks.count==2 };store.clear()
        let cleared=await waiting.value;XCTAssertTrue(cleared.isEmpty)
        callbacks[1]([cookie("old-late")])
        let after=await store.cookies(for:url);XCTAssertTrue(after.isEmpty)
    }
    func testCancellationReleasesWaiterAndLatePlatformReplyDoesNotResumeItTwice() async {
        var callback:(@MainActor ([HTTPCookie])->Void)?
        let store=BrowserCookieSnapshot(timeout:.seconds(10)) { callback=$0 }
        let read=Task { await store.cookies(for:url) }
        await ready { callback != nil };read.cancel()
        let values=await read.value;XCTAssertTrue(values.isEmpty)
        callback?([cookie("legitimate-late")])
        store.clear()
    }
    func testOutOfOrderRepliesNeverRestoreAnOlderSnapshot() async {
        var callbacks:[@MainActor ([HTTPCookie])->Void]=[]
        let store=BrowserCookieSnapshot(timeout:.seconds(10)) { callbacks.append($0) }
        let first=Task { await store.cookies(for:url) },second=Task { await store.cookies(for:url) }
        await ready { callbacks.count==2 }
        callbacks[1]([cookie("new")]);callbacks[0]([cookie("old")])
        let a=await first.value,b=await second.value
        XCTAssertEqual(a.map(\.value),["new"]);XCTAssertEqual(b.map(\.value),["new"])
    }
}
