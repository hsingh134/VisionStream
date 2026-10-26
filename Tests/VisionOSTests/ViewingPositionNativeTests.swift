import XCTest
import RealityKit
import simd
@testable import VisionStream

@MainActor final class ViewingPositionNativeTests: XCTestCase {
    func testActualRendererReclinesScreenAndBothPanoramasAndPositionsControls() throws {
        let playback = PlaybackModel()
        let controls = Entity()
        let renderer = try ImmersiveRenderer(playback: playback, controls: controls)
        let head = simd_quatf(angle: 0.6, axis: SIMD3<Float>(0,1,0)) * simd_quatf(angle: .pi/2, axis: SIMD3<Float>(1,0,0)) * simd_quatf(angle: 0.2, axis: SIMD3<Float>(0,0,1))
        var transform = simd_float4x4(head); transform.columns.3 = [2,1,3,1]
        for mode in VideoPresentation.allCases {
            playback.presentation = mode; playback.recenter()
            renderer.applyPose(transform)
            XCTAssertLessThan(simd_length(renderer.video.orientation.act([0,0,-1]) - head.act([0,0,-1])), 0.0001)
            XCTAssertLessThan(simd_length(controls.position - (SIMD3<Float>(2,1,3) + head.act([0,-0.35,-1.6]))), 0.0001)
            let capture = renderer.video.orientation.vector, controlPosition = controls.position
            // Looking around does not drag the panorama along with the head.
            renderer.applyPose(matrix_identity_float4x4)
            XCTAssertEqual(renderer.video.orientation.vector, capture)
            XCTAssertEqual(controls.position, controlPosition)
            playback.setViewingTilt(25); renderer.applyPose(matrix_identity_float4x4)
            XCTAssertLessThan(simd_length(renderer.video.orientation.act([0,0,-1]) - (head * simd_quatf(angle: 25 * .pi/180, axis: [1,0,0])).act([0,0,-1])), 0.0001)
            XCTAssertEqual(controls.position, controlPosition)
        }
    }

    func testTiltResetAndUprightAreAppliedToActualRenderer() throws {
        let playback = PlaybackModel(), controls = Entity()
        let renderer = try ImmersiveRenderer(playback: playback, controls: controls)
        let head = simd_quatf(angle: 0.7, axis: SIMD3<Float>(0,1,0)) * simd_quatf(angle: 1.0, axis: SIMD3<Float>(1,0,0))
        let transform = simd_float4x4(head)
        renderer.applyPose(transform)
        playback.setViewingTilt(500); XCTAssertEqual(playback.viewingTilt, 90)
        playback.recenter(upright: true); renderer.applyPose(transform)
        XCTAssertEqual(playback.viewingTilt, 0)
        XCTAssertLessThan(simd_length(renderer.video.orientation.act([0,1,0]) - SIMD3<Float>(0,1,0)), 0.0001)
        XCTAssertLessThan(simd_length(controls.orientation.act([0,0,-1]) - head.act([0,0,-1])), 0.0001)
        playback.recenter(); renderer.applyPose(transform)
        XCTAssertLessThan(simd_length(renderer.video.orientation.act([0,0,-1]) - head.act([0,0,-1])), 0.0001)
    }

    func testDelayedRecenterAndCancellation() async throws {
        let playback = PlaybackModel()
        playback.setViewingTilt(30)
        let before = playback.recenterID
        playback.scheduleRecenter(); XCTAssertEqual(playback.recenterCountdown, 3)
        playback.cancelScheduledRecenter()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(playback.recenterCountdown); XCTAssertEqual(playback.recenterID, before)
        playback.scheduleRecenter()
        try await Task.sleep(for: .milliseconds(3300))
        XCTAssertEqual(playback.recenterID, before + 1)
        XCTAssertEqual(playback.viewingTilt, 0); XCTAssertFalse(playback.recenterUpright)
        XCTAssertNil(playback.recenterCountdown)
        playback.scheduleRecenter(); playback.resetViewingPosition()
        XCTAssertNil(playback.recenterCountdown)
    }
}
