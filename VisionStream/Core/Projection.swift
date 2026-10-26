import Foundation

public enum VideoPresentation: String, CaseIterable, Identifiable, Sendable {
    case screen, vr180, vr360
    public var id: Self { self }
    public var label: String {
        switch self { case .screen: "Screen"; case .vr180: "VR180"; case .vr360: "VR360" }
    }
}

public enum VideoProjection: String, CaseIterable, Codable, Identifiable, Sendable {
    case vr180, vr360
    public var id: Self { self }
    public var label: String { self == .vr180 ? "VR180" : "VR360" }
    public var horizontalRadians: Float { self == .vr180 ? .pi : 2 * .pi }
}

public enum StereoLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    case mono, sideBySide, topBottom
    public var id: Self { self }
    public var label: String {
        switch self { case .mono: "Single image"; case .sideBySide: "Side by side"; case .topBottom: "Top / bottom" }
    }

    public func eyeSize(width: Int, height: Int) -> (width: Int, height: Int) {
        (self == .sideBySide ? width / 2 : width, self == .topBottom ? height / 2 : height)
    }

    /// Matches StereoVideo.metal: coordinates use the decoded image's top-left origin.
    public func sourceUV(_ uv: SIMD2<Float>, eye: Int, swapEyes: Bool = false, flipY: Bool = false) -> SIMD2<Float> {
        let index = swapEyes ? 1 - min(1, max(0, eye)) : min(1, max(0, eye))
        var result = SIMD2<Float>(uv.x, flipY ? 1 - uv.y : uv.y)
        if self == .sideBySide { result.x = result.x * 0.5 + Float(index) * 0.5 }
        if self == .topBottom { result.y = result.y * 0.5 + Float(index) * 0.5 }
        return result
    }
}

public struct ProjectionMesh: Sendable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var uv: [SIMD2<Float>]
    public var indices: [UInt32]

    /// Complete image on a fitted rectangle; never infers projection or eye packing.
    public static func screen(aspectRatio: Float) -> Self {
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 9
        let width = min(2.4, 1.6 * aspect)
        let height = width / aspect
        let x = width / 2, y = height / 2
        return Self(positions: [SIMD3(-x, y, -2.4), SIMD3(-x, -y, -2.4), SIMD3(x, y, -2.4), SIMD3(x, -y, -2.4)],
                    normals: Array(repeating: SIMD3(0, 0, 1), count: 4),
                    uv: [SIMD2(0, 1), SIMD2(0, 0), SIMD2(1, 1), SIMD2(1, 0)], indices: [0, 1, 2, 2, 1, 3])
    }

    public static func generate(projection: VideoProjection, columns: Int = 128, rows: Int = 64,
                                radius: Float = 10) -> Self {
        precondition(columns > 1 && rows > 1 && radius > 0)
        var result = Self(positions: [], normals: [], uv: [], indices: [])
        for row in 0...rows {
            let v = Float(row) / Float(rows)
            let latitude = (0.5 - v) * Float.pi
            for column in 0...columns {
                let u = Float(column) / Float(columns)
                let longitude = (u - 0.5) * projection.horizontalRadians
                let direction = SIMD3<Float>(sin(longitude) * cos(latitude), sin(latitude), -cos(longitude) * cos(latitude))
                result.positions.append(direction * radius)
                result.normals.append(-direction)
                // MaterialX tiledimage uses a bottom-left texture-coordinate
                // origin. Metal-decoded eye textures retain their top-left image
                // origin, so the north pole must receive material V = 1.
                result.uv.append(SIMD2<Float>(u, 1 - v))
            }
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let a = UInt32(row * (columns + 1) + column)
                let b = a + UInt32(columns + 1)
                result.indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
            }
        }
        return result
    }
}
