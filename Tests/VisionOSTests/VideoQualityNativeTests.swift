import AVFoundation
import Metal
import RealityKit
import XCTest
@testable import VisionStream

@MainActor final class VideoQualityNativeTests: XCTestCase {
    private func origin() throws -> String {
        guard let value=ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"],value.hasPrefix("https://127.0.0.1:") else { throw XCTSkip("Controlled original CC0 fixtures required") };return value
    }
    private func wait(_ condition:()->Bool,seconds:Double=15) async throws {
        let end=Date().addingTimeInterval(seconds)
        while !condition(),Date()<end { try await Task.sleep(for:.milliseconds(40)) }
        XCTAssertTrue(condition(),"Video-quality condition timed out")
    }
    private func buffer(_ playback:PlaybackModel) async throws -> CVPixelBuffer {
        let end=Date().addingTimeInterval(15)
        while Date()<end {
            if let b=playback.videoOutput?.copyPixelBuffer(forItemTime:playback.player.currentTime(),itemTimeForDisplay:nil) { return b }
            if playback.player.currentItem?.status == .failed { throw playback.player.currentItem?.error ?? URLError(.cannotDecodeContentData) }
            try await Task.sleep(for:.milliseconds(30))
        };throw URLError(.timedOut)
    }
    func testColourInterpretationUsesActualAttachmentsAndReportsUnknowns() throws {
        var frame=VideoPipelineSnapshot.Frame(width:512,height:128,pixelFormat:"RGhA",storageBitsPerComponent:16,bytesPerRow:4096,
            colorPrimaries:"P3_D65",transferFunction:"Linear",yCbCrMatrix:nil,presentationSeconds:nil)
        XCTAssertEqual(try VideoPipelineInspection.colorMode(frame),1)
        frame.colorPrimaries="ITU_R_709_2";XCTAssertEqual(try VideoPipelineInspection.colorMode(frame),0)
        frame.colorPrimaries=nil;frame.transferFunction=nil;XCTAssertEqual(try VideoPipelineInspection.colorMode(frame),2)
        frame.colorPrimaries="ITU_R_2020";frame.transferFunction="SMPTE_ST_2084_PQ"
        XCTAssertThrowsError(try VideoPipelineInspection.colorMode(frame),"Encoded HDR must never be treated as linear")
    }
    func testProductionLinearGPUKernelPreservesEyesPrecisionAndMips() async throws {
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice()),library=try device.makeDefaultLibrary(bundle:.main)
        let result=try await VideoQualityGPUChecks.run(device:device,library:library,benchmark:false)
        XCTAssertGreaterThan(result.assertions,9000)
        XCTAssertEqual(result.metrics["originalBlackWhiteAverageLinear"],0.5)
        print("QUALITY_GPU_REFERENCE "+String(decoding:try JSONEncoder().encode(result),as:UTF8.self))
    }
    func testActualDecodedBT709FullAndLimitedRangeColourBars() async throws {
        var outputs=[[Float]]()
        for name in ["709-limited","709-full"] {
            let playback=PlaybackModel();playback.player.isMuted=true
            defer { playback.stop() }
            let ready=await playback.prepare(.init(id:name,source:try origin()+"/quality/"+name+".mp4"),cookies:[])
            XCTAssertTrue(ready,playback.errorMessage ?? "Not ready");guard ready else { continue }
            playback.play();let b=try await buffer(playback)
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(b),kCVPixelFormatType_64RGBAHalf)
            let frame=VideoPipelineInspection.frame(b,time:nil)
            XCTAssertEqual(frame.width,512);XCTAssertEqual(frame.height,128)
            XCTAssertEqual(frame.colorPrimaries,"P3_D65");XCTAssertEqual(frame.transferFunction,"Linear")
            CVPixelBufferLockBaseAddress(b,.readOnly);defer { CVPixelBufferUnlockBaseAddress(b,.readOnly) }
            let data=try XCTUnwrap(CVPixelBufferGetBaseAddress(b)).assumingMemoryBound(to:UInt16.self),stride=CVPixelBufferGetBytesPerRow(b)/2
            let reference:[[Float]]=[[0,0,0],[1,1,1],[1,0,0],[0,1,0],[0,0,1],[1,1,0],[0,1,1],[1,0,1]]
            var values=[Float]()
            for i in 0..<8 { for c in 0..<3 {
                let offset=64*stride+(i*64+32)*4
                let p=(0..<3).map { Float(Float16(bitPattern:data[offset+$0])) }
                let rgb=[1.224940176*p[0]-0.224940176*p[1],-0.042056955*p[0]+1.042056955*p[1],-0.019637555*p[0]-0.078636046*p[1]+1.098273600*p[2]]
                let value=rgb[c];values.append(value)
                XCTAssertEqual(value,reference[i][c],accuracy:0.035,"\(name) colour\(i) component\(c)")
            } }
            outputs.append(values)
            try await wait { playback.videoPipeline.source.codec != nil }
            XCTAssertEqual(playback.videoPipeline.source.colorPrimaries,"ITU_R_709_2")
            print("QUALITY_DECODE_"+name+" "+String(decoding:try JSONEncoder().encode(values),as:UTF8.self))
        }
        XCTAssertEqual(outputs.count,2)
        if outputs.count==2 { for (a,b) in zip(outputs[0],outputs[1]) { XCTAssertEqual(a,b,accuracy:0.025,"Range signalling must not change the intended bars") } }
    }
    func testPQAndHLGDecodeToLinearHalfWithoutAssumingDisplayHDR() async throws {
        for name in ["2020-pq","2020-hlg"] {
            let playback=PlaybackModel();playback.player.isMuted=true;defer { playback.stop() }
            let ready=await playback.prepare(.init(id:name,source:try origin()+"/quality/"+name+".mp4"),cookies:[])
            XCTAssertTrue(ready,playback.errorMessage ?? "Not ready");guard ready else { continue }
            playback.play();let b=try await buffer(playback)
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(b),kCVPixelFormatType_64RGBAHalf)
            XCTAssertEqual(VideoPipelineInspection.frame(b,time:nil).transferFunction,"Linear")
            CVPixelBufferLockBaseAddress(b,.readOnly);defer { CVPixelBufferUnlockBaseAddress(b,.readOnly) }
            let data=try XCTUnwrap(CVPixelBufferGetBaseAddress(b)).assumingMemoryBound(to:UInt16.self),stride=CVPixelBufferGetBytesPerRow(b)/2
            let values=(0..<8).map { Float(Float16(bitPattern:data[64*stride+($0*64+32)*4])) }
            XCTAssertTrue(values.allSatisfy(\.isFinite));XCTAssertLessThan(values[0],0.005)
            for pair in zip(values,values.dropFirst()) { XCTAssertLessThan(pair.0,pair.1) }
            // PQ reference: 1,000-nit fixture white is approximately 10 linear
            // reference whites in Apple's P3 output. No final-display claim.
            if name == "2020-pq" { XCTAssertGreaterThan(values[7],9);XCTAssertLessThan(values[7],11) }
            XCTAssertGreaterThan(values[7],1,"HDR values must survive, not be clipped to SDR")
            try await wait { playback.videoPipeline.source.codec != nil }
            XCTAssertEqual(playback.videoPipeline.source.codec,"hvc1")
            XCTAssertEqual(playback.videoPipeline.source.bitsPerComponent,10)
            XCTAssertEqual(playback.videoPipeline.source.colorPrimaries,"ITU_R_2020")
            XCTAssertTrue(["SMPTE_ST_2084_PQ","ITU_R_2100_HLG"].contains(playback.videoPipeline.source.transferFunction ?? "unknown"))
            print("QUALITY_HDR_"+name+" "+String(decoding:try JSONEncoder().encode(values),as:UTF8.self))
        }
    }
    func testActualMain10DecodeRetainsMoreThanEightBitGradientLevels() async throws {
        let p=PlaybackModel();p.player.isMuted=true;defer { p.stop() }
        let ready=await p.prepare(.init(id:"main10-ramp",source:try origin()+"/quality/709-main10-ramp.mp4"),cookies:[])
        XCTAssertTrue(ready,p.errorMessage ?? "Not ready");guard ready else { return }
        p.play();let b=try await buffer(p)
        XCTAssertEqual(CVPixelBufferGetWidth(b),1024);XCTAssertEqual(CVPixelBufferGetHeight(b),128)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(b),kCVPixelFormatType_64RGBAHalf)
        XCTAssertEqual(VideoPipelineInspection.frame(b,time:nil).transferFunction,"Linear")
        CVPixelBufferLockBaseAddress(b,.readOnly);defer { CVPixelBufferUnlockBaseAddress(b,.readOnly) }
        let ptr=try XCTUnwrap(CVPixelBufferGetBaseAddress(b)).assumingMemoryBound(to:UInt16.self)
        let row=64*CVPixelBufferGetBytesPerRow(b)/2
        let bits=(0..<1024).map { ptr[row+$0*4] },values=bits.map { Float(Float16(bitPattern:$0)) }
        XCTAssertTrue(values.allSatisfy(\.isFinite))
        XCTAssertLessThan(values[0],0.005);XCTAssertGreaterThan(values[1023],0.98)
        // Gray input has constant neutral chroma. >700 distinct red levels at
        // native dimensions excludes an ordinary 256-level RGB bottleneck.
        XCTAssertGreaterThan(Set(bits).count,700)
        for (a,b) in zip(values,values.dropFirst()) { XCTAssertLessThanOrEqual(a,b+0.001,"No large gradient reversals") }
        try await wait { p.videoPipeline.source.bitsPerComponent != nil }
        XCTAssertEqual(p.videoPipeline.source.bitsPerComponent,10)
        print("QUALITY_NATIVE_MAIN10_RAMP distinctRedLevels=\(Set(bits).count) sourceSteps=1024 outputFormat=RGBAHalf")
    }
    func testPictureModesReusePausedFrameAndBindActualSampler() async throws {
        #if targetEnvironment(simulator)
        let playback=PlaybackModel();playback.player.isMuted=true
        let ready=await playback.prepare(.init(id:"chart",source:try origin()+"/quality/vr180-sbs-chart.mp4"),cookies:[])
        XCTAssertTrue(ready);guard ready else { return }
        playback.manualFormat();playback.presentation = .vr180;playback.layout = .sideBySide
        let renderer=try ImmersiveRenderer(playback:playback,controls:Entity())
        defer { renderer.stop();playback.stop() }
        try await renderer.start();try await wait { playback.videoPipeline.performance.completedFrames>0 }
        playback.pause();try await Task.sleep(for:.milliseconds(200))
        let output=playback.videoOutput
        var fixedPTS:Double?
        for mode in [VideoImageMode.enhanced,.original,.maximum,.enhanced,.original] {
            let before=playback.videoPipeline.performance.completedFrames
            playback.imageMode=mode
            try await wait { playback.videoPipeline.render?.mode == mode && playback.videoPipeline.performance.completedFrames>before }
            XCTAssertTrue(playback.videoOutput === output);XCTAssertFalse(playback.isPlaying)
            if let fixedPTS { XCTAssertEqual(playback.videoPipeline.frame?.presentationSeconds ?? -1,fixedPTS,accuracy:0.0001) }
            else { fixedPTS=playback.videoPipeline.frame?.presentationSeconds }
            let info=try XCTUnwrap(playback.videoPipeline.render)
            XCTAssertEqual(info.plan.width,2048);XCTAssertEqual(info.plan.height,2048);XCTAssertFalse(info.plan.downscaled)
            XCTAssertEqual(info.plan.mipLevels>1,mode == .maximum)
            let material=try XCTUnwrap(renderer.video.model?.materials.first as? ShaderGraphMaterial)
            // RealityKit currently reads a texture+sampler value back as just
            // textureResource. Check the bound resource and public descriptor;
            // do not claim this introspects final compositor filtering.
            let resource:TextureResource?
            switch material.getParameter(name:"leftEye") {
            case .texture(let p): resource=p.resource
            case .textureResource(let r): resource=r
            default: resource=nil
            }
            XCTAssertEqual(resource?.width,2048);XCTAssertEqual(resource?.height,2048)
            let sampler=ImmersiveRenderer.sampler(mode:mode,wrapping:false)
            XCTAssertEqual(sampler.maxAnisotropy,mode == .maximum ? 8:1)
            XCTAssertEqual(sampler.mipFilter,mode == .maximum ? .linear:.notMipmapped)
            XCTAssertEqual(sampler.sAddressMode,.clampToEdge)
        }
        XCTAssertEqual(renderer.video.model?.mesh.bounds.extents.z ?? 0,ImmersiveRenderer.panoramaRadius,accuracy:0.1)
        XCTAssertNil(playback.errorMessage)
        #else
        throw XCTSkip("Use the active immersive headset comparison checklist")
        #endif
    }
    func testEightKMonoActuallyReachesAnEightKSharedEyeTexture() async throws {
        #if targetEnvironment(simulator)
        let playback=PlaybackModel();playback.player.isMuted=true
        let ready=await playback.prepare(.init(id:"8k",source:try origin()+"/quality/vr360-mono-8k.mp4"),cookies:[])
        XCTAssertTrue(ready,playback.errorMessage ?? "Not ready");guard ready else { return }
        playback.manualFormat();playback.presentation = .vr360;playback.layout = .mono
        let renderer=try ImmersiveRenderer(playback:playback,controls:Entity())
        defer { renderer.stop();playback.stop() }
        try await renderer.start();try await wait({ playback.videoPipeline.performance.completedFrames>0 },seconds:25)
        let info=try XCTUnwrap(playback.videoPipeline.render)
        XCTAssertEqual(playback.decodedWidth,8192);XCTAssertEqual(playback.decodedHeight,4096)
        XCTAssertEqual(info.plan.width,8192);XCTAssertEqual(info.plan.height,4096);XCTAssertEqual(info.plan.textureCount,1);XCTAssertFalse(info.plan.downscaled)
        let material=try XCTUnwrap(renderer.video.model?.materials.first as? ShaderGraphMaterial)
        func resource(_ name:String)->TextureResource? {
            switch material.getParameter(name:name) {
            case .texture(let p):p.resource
            case .textureResource(let r):r
            default:nil
            }
        }
        let l=try XCTUnwrap(resource("leftEye")),r=try XCTUnwrap(resource("rightEye"))
        XCTAssertEqual(l,r);XCTAssertEqual(l.width,8192);XCTAssertEqual(l.height,4096)
        XCTAssertEqual(ImmersiveRenderer.sampler(mode:playback.imageMode,wrapping:true).sAddressMode,.repeat)
        XCTAssertEqual(info.estimatedTextureHorizontalPPD ?? 0,8192.0/360,accuracy:0.001)
        print("QUALITY_8K_PIPELINE "+String(decoding:try JSONEncoder().encode(playback.videoPipeline),as:UTF8.self))
        #else
        throw XCTSkip("Headset requires an active immersive scene")
        #endif
    }
}
