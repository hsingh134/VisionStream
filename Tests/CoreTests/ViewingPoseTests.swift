#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
import simd
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class ViewingPoseTests: XCTestCase {
    func testRecenterFacesViewerWhileSeatedReclinedAndOnSide() {
        for pitch: Float in [0, .pi / 4, .pi / 2, -.pi / 2] {
            for roll: Float in [0, .pi / 2, -.pi / 2] {
                let head = simd_quatf(angle: 0.7, axis: [0,1,0]) * simd_quatf(angle: pitch, axis: [1,0,0]) * simd_quatf(angle: roll, axis: [0,0,1])
                var pose = ViewingPose()
                pose.recenter(head: simd_float4x4(head))
                let video = pose.videoOrientation(tiltDegrees: 0)
                XCTAssertLessThan(simd_length(video.act([0,0,-1]) - head.act([0,0,-1])), 0.0001)
                XCTAssertLessThan(simd_length(video.act([0,1,0]) - head.act([0,1,0])), 0.0001)
                XCTAssertLessThan(simd_length(pose.controlsOrientation.act([0,1,0]) - head.act([0,1,0])), 0.0001)
            }
        }
    }

    func testControlsStayInCapturedViewDuringTilt() {
        let head = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1,0,0))
        var pose = ViewingPose(); pose.recenter(head: simd_float4x4(head))
        let viewer = SIMD3<Float>(2,1,4)
        let before = pose.controlsPosition(viewer: viewer)
        for angle: Double in [-90,-30,30,90] {
            let q = pose.videoOrientation(tiltDegrees: angle)
            let expected = head * simd_quatf(angle: Float(angle) * .pi / 180, axis: [1,0,0])
            XCTAssertLessThan(simd_length(q.act([0,0,-1]) - expected.act([0,0,-1])), 0.0001)
            XCTAssertEqual(pose.controlsPosition(viewer: viewer), before)
        }
        let offset = head.inverse.act(before-viewer)
        XCTAssertEqual(offset.x, 0, accuracy: 0.0001)
        XCTAssertEqual(offset.y, -0.35, accuracy: 0.0001)
        XCTAssertEqual(offset.z, -1.6, accuracy: 0.0001)
    }

    func testUprightResetLevelsVideoButKeepsControlsFacingReclinedViewer() {
        var pose = ViewingPose()
        let yaw: Float = 0.8
        let level = simd_quatf(angle: yaw, axis: SIMD3<Float>(0,1,0))
        pose.recenter(head: simd_float4x4(level))
        let lying = level * simd_quatf(angle: .pi / 2, axis: [1,0,0])
        pose.recenter(head: simd_float4x4(lying), upright: true)
        XCTAssertLessThan(simd_length(pose.centre.act([0,1,0]) - SIMD3<Float>(0,1,0)), 0.0001)
        XCTAssertLessThan(simd_length(pose.centre.act([0,0,-1]) - level.act([0,0,-1])), 0.0001)
        XCTAssertLessThan(simd_length(pose.controlsOrientation.act([0,0,-1]) - lying.act([0,0,-1])), 0.0001)
        // At first entry exactly vertical, the default room heading is deterministic.
        var vertical = ViewingPose(); vertical.recenter(head: simd_float4x4(lying), upright: true)
        XCTAssertTrue(vertical.centre.vector.x.isFinite && vertical.centre.vector.w.isFinite)
    }

    func testPositiveTiltRaisesVideoAndRejectsNonFiniteInput() {
        let pose = ViewingPose()
        XCTAssertGreaterThan(pose.videoOrientation(tiltDegrees: 30).act([0,0,-1]).y, 0)
        XCTAssertLessThan(pose.videoOrientation(tiltDegrees: -30).act([0,0,-1]).y, 0)
        XCTAssertEqual(ViewingPose.boundedTilt(900), 90)
        XCTAssertEqual(ViewingPose.boundedTilt(-900), -90)
        for invalid: Double in [.nan,.infinity,-.infinity] {
            XCTAssertEqual(ViewingPose.boundedTilt(invalid), 0)
        }
    }

    func testMalformedTrackingCannotReplaceCapturedPose() {
        var pose = ViewingPose()
        pose.recenter(head: simd_float4x4(simd_quatf(angle: 0.3, axis: SIMD3<Float>(1,0,0))))
        let before = pose.centre.vector
        var invalid = matrix_identity_float4x4
        invalid.columns.0.x = .nan
        pose.recenter(head: invalid)
        XCTAssertEqual(pose.centre.vector, before)
        invalid = simd_float4x4(0)
        pose.recenter(head: invalid)
        XCTAssertEqual(pose.centre.vector, before)
    }
}
