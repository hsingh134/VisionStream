#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
import simd
import Foundation
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class VideoImageQualityTests: XCTestCase {
    func testEightKMonoKeepsDetailWithoutDuplicatingEyeResources() throws {
        let mono=try VideoTexturePlan(width:8192,height:4096,layout:.mono,mode:.original)
        XCTAssertEqual(mono.width,8192);XCTAssertEqual(mono.height,4096);XCTAssertEqual(mono.textureCount,1)
        XCTAssertFalse(mono.downscaled);XCTAssertEqual(mono.scale,1)
        // The former 4,096 cap would retain only a quarter of these texels.
        XCTAssertEqual(mono.width*mono.height,4*4096*2048)
        let sbs=try VideoTexturePlan(width:8192,height:4096,layout:.sideBySide,mode:.original)
        XCTAssertEqual(sbs.width,4096);XCTAssertEqual(sbs.height,4096);XCTAssertEqual(sbs.textureCount,2)
        XCTAssertFalse(sbs.downscaled);XCTAssertEqual(sbs.descriptorBytes,mono.descriptorBytes)
    }
    func testTextureBudgetReductionsAreExplicitAndMipMemoryIsCounted() throws {
        for layout in StereoLayout.allCases {
            for mode in VideoImageMode.allCases {
                let plan=try VideoTexturePlan(width:8192,height:8192,layout:layout,mode:mode)
                XCTAssertTrue(plan.descriptorBytes<=plan.budgetBytes)
                XCTAssertGreaterThan(plan.width,0);XCTAssertGreaterThan(plan.height,0)
                XCTAssertEqual(plan.downscaled,plan.scale<1)
                XCTAssertEqual(plan.mipLevels>1,mode == .maximum)
            }
        }
        let plain=try VideoTexturePlan(width:8192,height:4096,layout:.sideBySide,mode:.original)
        let maximum=try VideoTexturePlan(width:8192,height:4096,layout:.sideBySide,mode:.maximum)
        XCTAssertFalse(maximum.downscaled);XCTAssertEqual(maximum.width,plain.width)
        XCTAssertGreaterThan(maximum.descriptorBytes,plain.descriptorBytes)
        XCTAssertLessThan(maximum.descriptorBytes,plain.descriptorBytes*2)
        let small=try VideoTexturePlan(width:4096,height:2048,layout:.mono,mode:.original,budgetBytes:1_048_576)
        XCTAssertTrue(small.downscaled);XCTAssertTrue(small.descriptorBytes <= small.budgetBytes)
        for bad in [(-1,2),(0,0),(8193,2048),(2048,8193)] { XCTAssertThrowsError(try VideoTexturePlan(width:bad.0,height:bad.1,layout:.mono,mode:.original)) }
        XCTAssertThrowsError(try VideoTexturePlan(width:7,height:4,layout:.sideBySide,mode:.original))
        XCTAssertThrowsError(try VideoTexturePlan(width:4,height:7,layout:.topBottom,mode:.original))
        XCTAssertThrowsError(try VideoTexturePlan(width:2,height:2,layout:.mono,mode:.original,budgetBytes:0))
    }
    func testHalfFloatPackingAnalysisIsSparseBoundedAndFinite() {
        var pixels=[UInt16]()
        for _ in 0..<32 { for x in 0..<64 {
            let v:Float=x<32 ? 0.125:0.75;pixels += [Float16(v).bitPattern,Float16(v).bitPattern,Float16(v).bitPattern,Float16(1).bitPattern]
        } }
        let result=pixels.withUnsafeBufferPointer { VideoFormatDetection.sampleLinearHalfLuma(rgba:$0,width:64,height:32,componentsPerRow:256) }
        XCTAssertEqual(result.count,8192);XCTAssertEqual(result[0],0.125,accuracy:0.0001);XCTAssertEqual(result[127],0.75,accuracy:0.0001)
        XCTAssertTrue(result.allSatisfy(\.isFinite))
        XCTAssertEqual(pixels.withUnsafeBufferPointer { VideoFormatDetection.sampleLinearHalfLuma(rgba:$0,width:64,height:32,componentsPerRow:255) },[])
        let invalid=[UInt16](repeating:Float16.nan.bitPattern,count:64*32*4)
        XCTAssertTrue(invalid.withUnsafeBufferPointer { VideoFormatDetection.sampleLinearHalfLuma(rgba:$0,width:64,height:32,componentsPerRow:256) }.allSatisfy { $0==0 })
    }
    func testHigherMeshDensityReducesActualUVInterpolationError() {
        func maximumError(columns:Int,rows:Int)->Double {
            let mesh=ProjectionMesh.generate(projection:.vr180,columns:columns,rows:rows,radius:1000)
            var worst=0.0
            for i in stride(from:0,to:mesh.indices.count,by:3) {
                let a=Int(mesh.indices[i]),b=Int(mesh.indices[i+1]),c=Int(mesh.indices[i+2])
                let point=(mesh.positions[a]+mesh.positions[b]+mesh.positions[c])/3
                let uv=(mesh.uv[a]+mesh.uv[b]+mesh.uv[c])/3
                let x=Double(point.x),y=Double(point.y),z=Double(point.z),length=sqrt(x*x+y*y+z*z)
                let latitude=asin(max(-1,min(1,y/length)))
                if abs(latitude)>75*Double.pi/180 { continue }
                let u=atan2(x,-z)/Double.pi+0.5,v=latitude/Double.pi+0.5
                worst=max(worst,hypot(u-Double(uv.x),v-Double(uv.y))*4096)
            }
            return worst
        }
        let before=maximumError(columns:128,rows:64),after=maximumError(columns:256,rows:128)
        XCTAssertGreaterThan(before,0.5);XCTAssertLessThan(after,0.2);XCTAssertLessThan(after,before*0.3)
    }
    func testHEVCBitDepthIsDeclaredMetadataNotFloatStoragePrecision() {
        var bytes=[UInt8](repeating:0,count:23);bytes[0]=1;bytes[17]=0xfa;bytes[18]=0xfa
        XCTAssertEqual(VideoCodecPrecision.hevc(configuration:Data(bytes)),10)
        bytes[17]=0xf8;bytes[18]=0xf8;XCTAssertEqual(VideoCodecPrecision.hevc(configuration:Data(bytes)),8)
        bytes[17]=2;XCTAssertNil(VideoCodecPrecision.hevc(configuration:Data(bytes)))
        XCTAssertNil(VideoCodecPrecision.hevc(configuration:Data(repeating:0,count:22)))
        XCTAssertNil(VideoPipelineSnapshot().source.bitsPerComponent)
        XCTAssertEqual(VideoPipelineSnapshot.safeTag("https://private.example/secret"),"unrecognised")
    }
}
