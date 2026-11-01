import Foundation
import Metal
#if canImport(VisionStream)
@testable import VisionStream
#endif

/// The production Metal kernel, read back before RealityKit/compositor display.
/// No screenshot or perceptual score is substituted for these pixel checks.
@MainActor enum VideoQualityGPUChecks {
    struct Result: Codable {
        let device: String
        let assertions: Int
        let metrics: [String: Double]
        let scope: String
    }
    enum Failure: Error { case unavailable, mismatch(String), gpu }
    static func run(device: any MTLDevice, library: any MTLLibrary, benchmark: Bool) async throws -> Result {
        guard let queue=device.makeCommandQueue(),let f=library.makeFunction(name:"prepareVideoFrame"),let old=library.makeFunction(name:"splitStereoVideo") else { throw Failure.unavailable }
        let pipeline=try await device.makeComputePipelineState(function:f),baseline=try await device.makeComputePipelineState(function:old)
        var assertions=0,metrics:[String:Double]=[:]
        func check(_ condition:Bool,_ reason:String) throws { assertions+=1;if !condition { throw Failure.mismatch(reason) } }
        for layout in StereoLayout.allCases {
            for mode in VideoImageMode.allCases {
                for swap in [false,true] { for flip in [false,true] {
                    let source=try texture(device,.rgba16Float,8,8)
                    var pixels=[Float]()
                    for y in 0..<8 { for x in 0..<8 { pixels += [Float(x)*0.125,Float(y)*0.125,Float(x+y)*0.25,1] } }
                    write(pixels,to:source)
                    let size=layout.eyeSize(width:8,height:8)
                    let left=try texture(device,.rgba16Float,size.width,size.height,mips:mode == .maximum)
                    let right=try texture(device,.rgba16Float,layout == .mono ? 1:size.width,layout == .mono ? 1:size.height,mips:mode == .maximum)
                    write([99,99,99,1],to:right,onlyFirst:true)
                    _ = try await submit(queue,pipeline,source,left,right,flags:flags(layout,swap,flip,mode),mips:mode == .maximum)
                    for (eye,t) in [left,right].enumerated() {
                        if layout == .mono && eye==1 { try check(read(t)[0]==99,"Mono must not write a duplicate eye");continue }
                        let values=read(t)
                        for y in 0..<size.height { for x in 0..<size.width {
                            let uv=layout.sourceUV(SIMD2<Float>((Float(x)+0.5)/Float(size.width),(Float(y)+0.5)/Float(size.height)),eye:eye,swapEyes:swap,flipY:flip)
                            let offset=(min(7,Int(uv.y*8))*8+min(7,Int(uv.x*8)))*4
                            for c in 0..<4 { try check(abs(values[(y*size.width+x)*4+c]-pixels[offset+c])<0.001,"Identity/eye mapping \(layout) \(mode) swap=\(swap) flip=\(flip) \(x),\(y) channel\(c)") }
                        } }
                    }
                } }
            }
        }
        // Before/after: average black/white in linear light, not encoded sRGB.
        let linear=try texture(device,.rgba16Float,2,2),encoded=try texture(device,.bgra8Unorm,2,2)
        write([0,0,0,1, 1,1,1,1, 0,0,0,1, 1,1,1,1],to:linear)
        writeBGRA([0,0,0,255,255,255,255,255,0,0,0,255,255,255,255,255],to:encoded)
        let a=try texture(device,.rgba16Float,1,1),b=try texture(device,.rgba16Float,1,1)
        _ = try await submit(queue,baseline,encoded,a,b,flags:SIMD4(0,0,0,0))
        let legacyMean=Double(read(a)[0])
        _ = try await submit(queue,pipeline,linear,a,b,flags:SIMD4(0,0,0,0))
        let correctedMean=Double(read(a)[0])
        metrics["legacyBlackWhiteAverageLinear"]=legacyMean;metrics["originalBlackWhiteAverageLinear"]=correctedMean
        try check(abs(correctedMean-0.5)<0.0001,"Linear light average");try check(abs(legacyMean-0.5)>0.2,"Baseline must expose encoded-light filtering error")
        _ = try await submit(queue,pipeline,linear,a,b,flags:SIMD4(0,0,0,0),colorMode:2)
        try check(abs(read(a)[0]-0.5)<0.0001,"Untagged SDR must also linearize before averaging")
        let p3=try texture(device,.rgba16Float,4,1),converted=try texture(device,.rgba16Float,4,1)
        let p3Values:[Float]=[1,0,0,1, 0,1,0,1, 0,0,1,1, 10,10,10,1]
        write(p3Values,to:p3)
        _ = try await submit(queue,pipeline,p3,converted,b,flags:SIMD4(0,0,0,0),colorMode:1)
        let convertedValues=read(converted)
        let matrix:[[Float]]=[[1.224940176,-0.224940176,0],[-0.042056955,1.042056955,0],[-0.019637555,-0.078636046,1.098273600]]
        for i in 0..<4 { for c in 0..<3 {
            let expected=(0..<3).reduce(Float(0)) { $0+matrix[c][$1]*p3Values[i*4+$1] }
            try check(abs(convertedValues[i*4+c]-expected)<max(0.001,abs(expected)*0.001),"P3 conversion must preserve negative gamut and extended highlights: pixel\(i) channel\(c) actual=\(convertedValues[i*4+c]) expected=\(expected)")
        } }
        // 1,024 representable source levels: quantify extra 8-bit conversion loss.
        let ramp=try texture(device,.rgba16Float,1024,4),ramp8=try texture(device,.bgra8Unorm,1024,4)
        var values=[Float](),bytes=[UInt8]()
        for _ in 0..<4 { for i in 0..<1024 {
            let v=Float(i)/1023;values += [v,v,v,1]
            let srgb=v<=0.0031308 ? v*12.92 : 1.055*pow(v,1/2.4)-0.055
            let n=UInt8(max(0,min(255,Int((srgb*255).rounded()))));bytes += [n,n,n,255]
        } }
        write(values,to:ramp);writeBGRA(bytes,to:ramp8)
        let ra=try texture(device,.rgba16Float,1024,4),rb=try texture(device,.rgba16Float,1024,4)
        _ = try await submit(queue,baseline,ramp8,ra,rb,flags:SIMD4(0,0,0,0));let before=read(ra)
        _ = try await submit(queue,pipeline,ramp,ra,rb,flags:SIMD4(0,0,0,0));let after=read(ra)
        func rmse(_ actual:[Float],_ reference:[Float])->Double { sqrt(zip(actual,reference).enumerated().filter { $0.offset%4 != 3 }.reduce(0) { $0+pow(Double($1.element.0-$1.element.1),2) } / Double(reference.count/4*3)) }
        metrics["legacyRampLinearRMSE"]=rmse(before,values);metrics["originalRampLinearRMSE"]=rmse(after,values)
        try check(metrics["originalRampLinearRMSE"]!<metrics["legacyRampLinearRMSE"]!*0.2,"Half precision must preserve the original ramp better than an extra 8-bit conversion")
        // Bounded enhancement against a known blurred synthetic edge.
        let edge=try texture(device,.rgba16Float,32,8);var blurred=[Float](),reference=[Float]()
        for _ in 0..<8 { for x in 0..<32 {
            let v:Float=x<14 ? 0 : (x==14 ? 0.125 : (x==15 ? 0.375 : (x==16 ? 0.625 : (x==17 ? 0.875:1))))
            blurred += [v,v,v,1];let ideal:Float=x<16 ? 0:1;reference += [ideal,ideal,ideal,1]
        } }
        write(blurred,to:edge);let ea=try texture(device,.rgba16Float,32,8),eb=try texture(device,.rgba16Float,1,1)
        _ = try await submit(queue,pipeline,edge,ea,eb,flags:SIMD4(0,0,0,1));let enhanced=read(ea)
        metrics["blurredEdgeRMSE"]=rmse(blurred,reference);metrics["enhancedEdgeRMSE"]=rmse(enhanced,reference)
        try check(metrics["enhancedEdgeRMSE"]!<metrics["blurredEdgeRMSE"]!,"Conservative enhancement should improve this controlled blurred edge")
        try check(enhanced.allSatisfy { $0>=0 && $0<=1 },"No edge overshoot/ringing outside local extrema")
        let noise=try texture(device,.rgba16Float,32,32),noiseOut=try texture(device,.rgba16Float,32,32)
        var state:UInt32=42,noisePixels=[Float]()
        for _ in 0..<1024 { state=1664525 &* state &+ 1013904223;let n:Float=0.5+(Float(state>>16)/65535-0.5)*0.01;noisePixels += [n,n,n,1] }
        write(noisePixels,to:noise)
        _ = try await submit(queue,pipeline,noise,noiseOut,b,flags:SIMD4(0,0,0,1))
        func noiseDeviation(_ pixels:[Float])->Double { sqrt(stride(from:0,to:pixels.count,by:4).reduce(0) { $0+pow(Double(pixels[$1])-0.5,2) }/Double(pixels.count/4)) }
        let noiseGain=noiseDeviation(read(noiseOut))/noiseDeviation(noisePixels)
        metrics["lowContrastNoiseDeviationGain"]=noiseGain
        try check(noiseGain<1.03,"Enhanced must not materially amplify this low-contrast synthetic noise; gain=\(noiseGain)")
        // Mips are generated from linear float data, including extended highlights.
        let checker=try texture(device,.rgba16Float,64,64);var checkerPixels=[Float]()
        for y in 0..<64 { for x in 0..<64 { let v:Float=(x+y)%2==0 ? 0:1;checkerPixels += [v,v,v,1] } }
        write(checkerPixels,to:checker);let ma=try texture(device,.rgba16Float,64,64,mips:true),mb=try texture(device,.rgba16Float,1,1)
        _ = try await submit(queue,pipeline,checker,ma,mb,flags:SIMD4(0,0,0,2),mips:true)
        let last=read(ma,level:ma.mipmapLevelCount-1)[0];metrics["linearCheckerLastMip"]=Double(last)
        try check(abs(last-0.5)<0.0001,"Minified checker must converge to its linear area average; actual=\(last)")
        if benchmark {
            let s=try texture(device,.rgba16Float,4096,2048),s8=try texture(device,.bgra8Unorm,4096,2048)
            // Same varying gradients/checker structure in both transports.
            // Timing excludes CPU pattern creation/upload, as it should.
            for y in 0..<2048 {
                var halfRow=[UInt16](),byteRow=[UInt8]()
                for x in 0..<4096 {
                    let rgb:[Float]=[Float(x%2048)/2047,Float(y)/2047,(x/3+y/3)%2==0 ? 0.15:0.85]
                    halfRow += (rgb+[1]).map { Float16($0).bitPattern }
                    let encoded=rgb.map { v in UInt8(max(0,min(255,Int(((v<=0.0031308 ? v*12.92:1.055*pow(v,1/2.4)-0.055)*255).rounded())))) }
                    byteRow += [encoded[2],encoded[1],encoded[0],255]
                }
                halfRow.withUnsafeBytes { s.replace(region:MTLRegionMake2D(0,y,4096,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4096*8) }
                byteRow.withUnsafeBytes { s8.replace(region:MTLRegionMake2D(0,y,4096,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4096*4) }
            }
            for (name,p,src,mode) in [("legacy",baseline,s8,VideoImageMode.original),("original",pipeline,s,.original),("enhanced",pipeline,s,.enhanced),("maximum",pipeline,s,.maximum)] {
                let l=try texture(device,.rgba16Float,2048,2048,mips:mode == .maximum),r=try texture(device,.rgba16Float,2048,2048,mips:mode == .maximum)
                var times=[Double]()
                for i in 0..<25 { let t=try await submit(queue,p,src,l,r,flags:flags(.sideBySide,false,false,mode),mips:mode == .maximum,colorMode:name == "legacy" ? 0:1);if i>=5,let t { times.append(t) } }
                if !times.isEmpty { times.sort();metrics[name+"GPUmsMedian"]=times[times.count/2];metrics[name+"GPUmsP95"]=times[min(times.count-1,Int(Double(times.count)*0.95))] }
            }
        }
        return Result(device:device.name,assertions:assertions,metrics:metrics,scope:"GPU texture preparation/readback on this host; excludes decoding, RealityKit sampling, final display and perceived quality. GPU timing unavailable if absent.")
    }
    static func flags(_ layout:StereoLayout,_ swap:Bool,_ flip:Bool,_ mode:VideoImageMode)->SIMD4<UInt32> { SIMD4(layout == .mono ? 0:(layout == .sideBySide ? 1:2),swap ? 1:0,flip ? 1:0,mode == .enhanced ? 1:(mode == .maximum ? 2:0)) }
    static func texture(_ device:any MTLDevice,_ format:MTLPixelFormat,_ w:Int,_ h:Int,mips:Bool=false)throws->any MTLTexture {
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:w,height:h,mipmapped:mips);d.storageMode = .shared;d.usage=[.shaderRead,.shaderWrite]
        guard let t=device.makeTexture(descriptor:d) else { throw Failure.unavailable };return t
    }
    static func write(_ values:[Float],to texture:any MTLTexture,onlyFirst:Bool=false) {
        let bytes=values.map { Float16($0).bitPattern };bytes.withUnsafeBytes { texture.replace(region:MTLRegionMake2D(0,0,onlyFirst ? 1:texture.width,onlyFirst ? 1:texture.height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:(onlyFirst ? 1:texture.width)*8) }
    }
    static func writeConstant(_ color:[Float],to texture:any MTLTexture) {
        var row=[UInt16]();for _ in 0..<texture.width { row += color.map { Float16($0).bitPattern } }
        row.withUnsafeBytes { p in for y in 0..<texture.height { texture.replace(region:MTLRegionMake2D(0,y,texture.width,1),mipmapLevel:0,withBytes:p.baseAddress!,bytesPerRow:texture.width*8) } }
    }
    static func writeBGRA(_ values:[UInt8],to texture:any MTLTexture) { values.withUnsafeBytes { texture.replace(region:MTLRegionMake2D(0,0,texture.width,texture.height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:texture.width*4) } }
    static func read(_ texture:any MTLTexture,level:Int=0)->[Float] {
        // visionOS Simulator getBytes(mipmapLevel: n) returned base-level
        // pixels for n > 0. Reading a level-zero *view* and a GPU blit agreed;
        // use the view so this tests the actual mip rather than that API quirk.
        let sampled:any MTLTexture
        if level==0 { sampled=texture }
        else {
            guard let view=texture.makeTextureView(pixelFormat:texture.pixelFormat,textureType:.type2D,levels:level..<(level+1),slices:0..<1) else { return [] }
            sampled=view
        }
        let w=sampled.width,h=sampled.height;var data=[UInt16](repeating:0,count:w*h*4)
        data.withUnsafeMutableBytes { sampled.getBytes($0.baseAddress!,bytesPerRow:w*8,from:MTLRegionMake2D(0,0,w,h),mipmapLevel:0) };return data.map { Float(Float16(bitPattern:$0)) }
    }
    static func submit(_ queue:any MTLCommandQueue,_ pipeline:any MTLComputePipelineState,_ source:any MTLTexture,_ left:any MTLTexture,_ right:any MTLTexture,flags:SIMD4<UInt32>,mips:Bool=false,colorMode:UInt32=0)async throws->Double? {
        guard let command=queue.makeCommandBuffer(),let encoder=command.makeComputeCommandEncoder() else { throw Failure.unavailable }
        encoder.setComputePipelineState(pipeline);encoder.setTexture(source,index:0);encoder.setTexture(left,index:1);encoder.setTexture(right,index:2)
        var p=flags;encoder.setBytes(&p,length:MemoryLayout<SIMD4<UInt32>>.stride,index:0)
        var color=colorMode;encoder.setBytes(&color,length:MemoryLayout<UInt32>.stride,index:1)
        encoder.dispatchThreads(MTLSize(width:left.width,height:left.height,depth:1),threadsPerThreadgroup:MTLSize(width:16,height:8,depth:1));encoder.endEncoding()
        if mips {
            guard let blit=command.makeBlitCommandEncoder() else { throw Failure.unavailable }
            blit.generateMipmaps(for:left);if right.mipmapLevelCount>1 { blit.generateMipmaps(for:right) };blit.endEncoding()
        }
        await withCheckedContinuation { continuation in command.addCompletedHandler { @Sendable _ in continuation.resume() };command.commit() }
        guard command.status == .completed else { throw Failure.gpu }
        return command.gpuEndTime>command.gpuStartTime && command.gpuStartTime>0 ? (command.gpuEndTime-command.gpuStartTime)*1000:nil
    }
}
