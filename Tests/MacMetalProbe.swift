// Executes the application's actual Metal kernel on this Mac, without RealityKit or visionOS.
import Foundation
import Metal

@main struct MacMetalProbe {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.unavailable }
        let sourceCode = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let (device, queue, pipeline) = try setup(sourceCode)
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        inputDescriptor.storageMode = .shared; inputDescriptor.usage = [.shaderRead]
        guard let source = device.makeTexture(descriptor: inputDescriptor) else { throw Failure.unavailable }
        var pixels = [UInt8]()
        for y in 0..<4 {
            for x in 0..<4 {
                let color = (x + y * 2) % 8
                pixels += [color & 4 == 0 ? 0 : 255, color & 2 == 0 ? 0 : 255, color & 1 == 0 ? 0 : 255, 255]
            }
        }
        pixels.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 16) }
        var assertions = 0
        for (layoutIndex, layout) in StereoLayout.allCases.enumerated() {
            for swap in [false, true] {
                for flip in [false, true] {
                    let size = layout.eyeSize(width: 4, height: 4)
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: size.width, height: size.height, mipmapped: false)
                    descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .shaderWrite]
                    guard let left = device.makeTexture(descriptor: descriptor), let right = device.makeTexture(descriptor: descriptor),
                          let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw Failure.unavailable }
                    encoder.setComputePipelineState(pipeline)
                    encoder.setTexture(source, index: 0); encoder.setTexture(left, index: 1); encoder.setTexture(right, index: 2)
                    var parameters = SIMD4<UInt32>(UInt32(layoutIndex), swap ? 1 : 0, flip ? 1 : 0, 0)
                    encoder.setBytes(&parameters, length: MemoryLayout<SIMD4<UInt32>>.stride, index: 0)
                    encoder.dispatchThreads(MTLSize(width: size.width, height: size.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 2, height: 2, depth: 1))
                    encoder.endEncoding()
                    await withCheckedContinuation { continuation in
                        command.addCompletedHandler { @Sendable _ in continuation.resume() }
                        command.commit()
                    }
                    guard command.status == .completed else { throw Failure.gpu }
                    for (eye, texture) in [left, right].enumerated() {
                        var output = [UInt16](repeating: 0, count: size.width * size.height * 4)
                        output.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: size.width * 8,
                            from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0) }
                        for y in 0..<size.height {
                            for x in 0..<size.width {
                                let uv = layout.sourceUV(SIMD2<Float>((Float(x)+0.5)/Float(size.width), (Float(y)+0.5)/Float(size.height)),
                                    eye: eye, swapEyes: swap, flipY: flip)
                                let offset = (min(3, Int(uv.y*4))*4 + min(3, Int(uv.x*4))) * 4
                                let expected = [pixels[offset+2], pixels[offset+1], pixels[offset], pixels[offset+3]]
                                for channel in 0..<4 {
                                    let actual = Float(Float16(bitPattern: output[(y*size.width+x)*4+channel]))
                                    guard abs(actual - Float(expected[channel])/255) < 0.002 else {
                                        throw Failure.mismatch("\(layout.rawValue) swap=\(swap) flip=\(flip) eye=\(eye) pixel=\(x),\(y)")
                                    }
                                    assertions += 1
                                }
                            }
                        }
                    }
                    print("PASS: Metal \(layout.rawValue), swap=\(swap), flip=\(flip)")
                }
            }
        }
        print("12 Metal configurations; \(assertions) channel assertions passed on macOS. RealityKit/visionOS rendering remains untested.")
    }
    @MainActor static func setup(_ sourceCode: String) throws -> (any MTLDevice, any MTLCommandQueue, any MTLComputePipelineState) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw Failure.unavailable }
        let library = try device.makeLibrary(source: sourceCode, options: nil)
        guard let function = library.makeFunction(name: "splitStereoVideo") else { throw Failure.unavailable }
        return (device, queue, try device.makeComputePipelineState(function: function))
    }
    enum Failure: Error { case unavailable, gpu, mismatch(String) }
}
