import simd

/// A captured viewing frame, independent of stereo packing and projection.
/// Recentring captures rotation once; subsequent head turns still explore the scene.
public struct ViewingPose: Sendable {
    public private(set) var centre = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    public private(set) var controlsOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var uprightHeading: Float = 0

    public init() {}

    public mutating func recenter(head: simd_float4x4, upright: Bool = false) {
        let rotation = simd_float3x3(columns: (SIMD3(head.columns.0.x, head.columns.0.y, head.columns.0.z),
                                             SIMD3(head.columns.1.x, head.columns.1.y, head.columns.1.z),
                                             SIMD3(head.columns.2.x, head.columns.2.y, head.columns.2.z)))
        guard (0..<3).allSatisfy({ rotation.columns.0[$0].isFinite && rotation.columns.1[$0].isFinite && rotation.columns.2[$0].isFinite }),
              abs(simd_determinant(rotation) - 1) < 0.01 else { return }
        let orientation = simd_normalize(simd_quatf(rotation))
        // Heading is undefined when looking straight up/down. Preserve the last
        // stable heading instead of choosing an arbitrary atan2(0, 0) result.
        let horizontal = SIMD2<Float>(rotation.columns.2.x, rotation.columns.2.z)
        if simd_length(horizontal) > 0.01 { uprightHeading = atan2(horizontal.x, horizontal.y) }
        centre = upright ? simd_quatf(angle: uprightHeading, axis: SIMD3<Float>(0, 1, 0)) : orientation
        // Even an upright reset leaves the controls in the current line of sight.
        controlsOrientation = orientation
    }

    public func videoOrientation(tiltDegrees: Double) -> simd_quatf {
        let tilt = Self.boundedTilt(tiltDegrees)
        return simd_normalize(centre * simd_quatf(angle: Float(tilt) * .pi / 180, axis: SIMD3<Float>(1, 0, 0)))
    }

    public func controlsPosition(viewer: SIMD3<Float>) -> SIMD3<Float> {
        viewer + controlsOrientation.act(SIMD3<Float>(0, -0.35, -1.6))
    }

    public static func boundedTilt(_ degrees: Double) -> Double {
        degrees.isFinite ? min(90, max(-90, degrees)) : 0
    }
}
