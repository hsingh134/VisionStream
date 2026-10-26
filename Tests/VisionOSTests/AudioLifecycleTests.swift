import AVFoundation
import XCTest
@testable import VisionStream

@MainActor final class AudioLifecycleTests: XCTestCase {
    private func prepared() async throws -> PlaybackModel {
        let raw = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"])
        let url = try XCTUnwrap(URL(string: raw))
        guard url.scheme == "https", ["localhost", "127.0.0.1"].contains(url.host), url.port != nil else { throw URLError(.badURL) }
        let model = PlaybackModel(); model.player.isMuted = true
        let ready = await model.prepare(.init(id: "audio", source: url.appendingPathComponent("controls-demo.mp4").absoluteString), cookies: [])
        XCTAssertTrue(ready)
        return model
    }
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(8)
        while !condition() { guard Date() < end else { XCTFail("Audio event did not update playback"); throw URLError(.timedOut) }; try await Task.sleep(for: .milliseconds(50)) }
    }
    private func interrupt(_ began: Bool, resume: Bool = false) {
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: [
            AVAudioSessionInterruptionTypeKey: (began ? AVAudioSession.InterruptionType.began : .ended).rawValue,
            AVAudioSessionInterruptionOptionKey: resume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : 0])
    }
    func testSystemInterruptionPausesAndPermittedResumeRestoresPlayback() async throws {
        let model = try await prepared(); defer { model.stop() }
        model.play(); try await wait { model.isPlaying }
        interrupt(true)
        try await wait { model.isAudioInterrupted && !model.isPlaying }
        XCTAssertEqual(model.player.rate, 0)
        interrupt(false, resume: true)
        try await wait { !model.isAudioInterrupted && model.isPlaying }
        XCTAssertNil(model.systemNotice)
    }
    func testUserPauseAndStopPreventAutomaticResume() async throws {
        let model = try await prepared(); defer { model.stop() }
        model.play(); try await wait { model.isPlaying }
        interrupt(true); try await wait { model.isAudioInterrupted }
        model.pause()
        interrupt(false, resume: true)
        try await wait { !model.isAudioInterrupted }
        XCTAssertFalse(model.isPlaying); XCTAssertEqual(model.player.rate, 0)
        model.play(); try await wait { model.isPlaying }
        interrupt(true); try await wait { model.isAudioInterrupted }
        model.stop(); interrupt(false, resume: true)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(model.isReady); XCTAssertEqual(model.player.rate, 0)
    }
    func testHeadphoneDisconnectPausesAndMediaResetReleasesPlayer() async throws {
        let model = try await prepared(); defer { model.stop() }
        model.play(); try await wait { model.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        try await wait { !model.isPlaying && model.systemNotice != nil }
        XCTAssertEqual(model.player.rate, 0)
        model.play(); try await wait { model.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        try await wait { !model.isReady && model.errorMessage != nil }
        XCTAssertNil(model.player.currentItem)
    }
}
