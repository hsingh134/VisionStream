#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
import simd
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class ProjectionTests: XCTestCase {
    func testScreenFitsCompleteFrameWithUprightUVs() {
        for aspect: Float in [16 / 9, 2, 1, 0.5] {
            let mesh = ProjectionMesh.screen(aspectRatio: aspect)
            let width = mesh.positions[2].x - mesh.positions[0].x
            let height = mesh.positions[0].y - mesh.positions[1].y
            XCTAssertEqual(width / height, aspect, accuracy: 0.001)
            XCTAssertTrue(width <= 2.401 && height <= 1.601)
            XCTAssertEqual(mesh.uv, [SIMD2(0, 1), SIMD2(0, 0), SIMD2(1, 1), SIMD2(1, 0)])
            XCTAssertTrue(mesh.positions.allSatisfy { $0.z == -2.4 })
            for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.positions[Int(mesh.indices[i])], b = mesh.positions[Int(mesh.indices[i + 1])], c = mesh.positions[Int(mesh.indices[i + 2])]
                XCTAssertLessThan(simd_dot(simd_cross(b - a, c - a), a), 0)
            }
        }
        for aspect: Float in [0, -1, .nan, .infinity] {
            let mesh = ProjectionMesh.screen(aspectRatio: aspect)
            XCTAssertTrue(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
    }

    func testHemisphereLooksForwardAndUVOrientation() {
        let mesh = ProjectionMesh.generate(projection: .vr180, columns: 8, rows: 4, radius: 10)
        XCTAssertEqual(mesh.positions.count, 45)
        XCTAssertEqual(mesh.indices.count, 192)
        let center = mesh.positions[2 * 9 + 4]
        XCTAssertEqual(center.x, 0, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0, accuracy: 0.0001)
        XCTAssertEqual(center.z, -10, accuracy: 0.0001)
        XCTAssertEqual(mesh.uv[0], SIMD2<Float>(0, 1))
        XCTAssertEqual(mesh.uv.last, SIMD2<Float>(1, 0))
        XCTAssertTrue(mesh.positions.allSatisfy { $0.z < 0.0001 })
    }

    func testSphereSeamClosesAndRadiusIsConstant() {
        let mesh = ProjectionMesh.generate(projection: .vr360, columns: 16, rows: 8)
        for row in 0...8 {
            XCTAssertLessThan(simd_length(mesh.positions[row * 17] - mesh.positions[row * 17 + 16]), 0.0001)
        }
        for point in mesh.positions { XCTAssertEqual(simd_length(point), 10, accuracy: 0.0001) }
        XCTAssertTrue(mesh.positions.contains { $0.z > 9 })
    }

    func testTriangleWindingFacesViewer() {
        for projection in VideoProjection.allCases {
            let mesh = ProjectionMesh.generate(projection: projection, columns: 16, rows: 8)
            for index in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.positions[Int(mesh.indices[index])]
                let b = mesh.positions[Int(mesh.indices[index + 1])]
                let c = mesh.positions[Int(mesh.indices[index + 2])]
                let normal = simd_cross(b - a, c - a)
                if simd_length(normal) > 0.001 { XCTAssertLessThan(simd_dot(normal, a), 0) }
            }
        }
    }

    func testStereoRegionsAreIndependentOfProjection() {
        let center = SIMD2<Float>(0.5, 0.5)
        XCTAssertEqual(StereoLayout.mono.sourceUV(center, eye: 1), center)
        XCTAssertEqual(StereoLayout.sideBySide.sourceUV(center, eye: 0), SIMD2<Float>(0.25, 0.5))
        XCTAssertEqual(StereoLayout.sideBySide.sourceUV(center, eye: 1), SIMD2<Float>(0.75, 0.5))
        XCTAssertEqual(StereoLayout.topBottom.sourceUV(center, eye: 0), SIMD2<Float>(0.5, 0.25))
        XCTAssertEqual(StereoLayout.topBottom.sourceUV(center, eye: 1), SIMD2<Float>(0.5, 0.75))
        XCTAssertEqual(StereoLayout.sideBySide.sourceUV(center, eye: 0, swapEyes: true), SIMD2<Float>(0.75, 0.5))
        XCTAssertEqual(StereoLayout.topBottom.sourceUV(SIMD2<Float>(0.2, 0.1), eye: 0, flipY: true), SIMD2<Float>(0.2, 0.45))
    }

    func testEyeDimensions() {
        XCTAssertEqual(StereoLayout.sideBySide.eyeSize(width: 4096, height: 2048).width, 2048)
        XCTAssertEqual(StereoLayout.topBottom.eyeSize(width: 4096, height: 4096).height, 2048)
        XCTAssertEqual(StereoLayout.mono.eyeSize(width: 4096, height: 2048).width, 4096)
    }

    func testMaterialXMappingKeepsNorthAtTopOfEachDecodedEye() {
        for projection in VideoProjection.allCases {
            let mesh = ProjectionMesh.generate(projection: projection, columns: 8, rows: 4)
            // MaterialX tiledimage maps material V=1 to the top of a Metal image.
            // Check the presentation boundary, independently of the compute kernel.
            let northUV = mesh.uv[4]
            let southUV = mesh.uv[4 * 9 + 4]
            XCTAssertTrue(mesh.positions[4].y > 9)
            XCTAssertTrue(mesh.positions[4 * 9 + 4].y < -9)
            for layout in StereoLayout.allCases {
                for eye in 0...1 {
                    let north = layout.sourceUV(SIMD2<Float>(northUV.x, 1 - northUV.y), eye: eye)
                    let south = layout.sourceUV(SIMD2<Float>(southUV.x, 1 - southUV.y), eye: eye)
                    let expectedTop: Float = layout == .topBottom ? Float(eye) * 0.5 : 0
                    let expectedBottom: Float = layout == .topBottom ? Float(eye + 1) * 0.5 : 1
                    XCTAssertEqual(north.y, expectedTop, accuracy: 0.0001)
                    XCTAssertEqual(south.y, expectedBottom, accuracy: 0.0001)
                    XCTAssertLessThan(north.y, south.y)
                }
            }
        }
    }
}
