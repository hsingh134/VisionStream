import Foundation
import Metal
@main struct MacVideoQualityProbe {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count==3,let device=MTLCreateSystemDefaultDevice() else { throw VideoQualityGPUChecks.Failure.unavailable }
        let code=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
        let library=try await device.makeLibrary(source:code,options:nil)
        let result=try await VideoQualityGPUChecks.run(device:device,library:library,benchmark:true)
        let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];let data=try e.encode(result)
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2]));print(String(decoding:data,as:UTF8.self))
    }
}
