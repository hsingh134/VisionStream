import Foundation
import VisionStreamMedia

/// Local-file-only packet remuxing. The bundled LGPL library contains no
/// networking, encoders, executable tools or downloaded code.
enum MediaRemux {
    static var version:String { String(cString:vs_media_version()) }
    static var license:String { String(cString:vs_media_license()) }
    private static let queue=DispatchQueue(label:"personal.visionstream.media-remux",qos:.utility)
    static func convert(input:URL,output:URL,maximumBytes:Int64) async throws {
        try Task.checkCancellation()
        guard input.isFileURL,output.isFileURL,input != output,maximumBytes>0 else { throw NSError(domain:"MediaRemuxErrorDomain",code:-22) }
        let operation=try Operation()
        do { try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                queue.async {
                    let result=input.path.withCString { a in output.path.withCString { b in vs_media_remux(operation.context,a,b,maximumBytes) } }
                    if result<0 { continuation.resume(throwing:NSError(domain:"MediaRemuxErrorDomain",code:Int(result))) }
                    else { continuation.resume() }
                }
            }
            try Task.checkCancellation()
        } onCancel: { operation.cancel() } }
        catch { if Task.isCancelled { throw CancellationError() };throw error }
    }
    private final class Operation:@unchecked Sendable {
        let context:OpaquePointer
        init() throws {
            guard let context=vs_media_create() else { throw NSError(domain:"MediaRemuxErrorDomain",code:-12) }
            self.context=context
        }
        func cancel() { vs_media_cancel(context) }
        deinit { vs_media_destroy(context) }
    }
}
