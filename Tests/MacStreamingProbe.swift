// Desktop AVFoundation sanity check. This is not a visionOS or RealityKit test.
import AVFoundation
import CoreVideo
import Foundation

@main struct MacStreamingProbe {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2, let origin = URL(string: CommandLine.arguments[1]) else {
            throw ProbeError.failed("Expected a local fixture origin")
        }
        for name in ["vr180-mono", "vr180-sbs", "vr180-tb", "vr360-mono", "vr360-sbs", "vr360-tb"] {
            for path in [name + ".mp4", "hls/" + name + "/master.m3u8"] {
                let asset = AVURLAsset(url: origin.appendingPathComponent(path))
                let (playable, protected) = try await asset.load(.isPlayable, .hasProtectedContent)
                guard playable, !protected else { throw ProbeError.failed("Unsupported fixture \(path)") }
                let item = AVPlayerItem(asset: asset)
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferMetalCompatibilityKey as String: true])
                item.add(output)
                let player = AVPlayer(playerItem: item)
                player.play()
                let deadline = Date().addingTimeInterval(12)
                var frame: CVPixelBuffer?
                while Date() < deadline, frame == nil {
                    if item.status == .failed { throw ProbeError.failed("Player rejected \(path): \(item.error.map { ($0 as NSError).code } ?? 0)") }
                    try await Task.sleep(for: .milliseconds(50))
                    frame = output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil)
                }
                player.pause(); player.replaceCurrentItem(with: nil)
                guard let frame else { throw ProbeError.failed("No decoded video frame from \(path)") }
                guard CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_32BGRA else {
                    throw ProbeError.failed("Unexpected output pixel format")
                }
                print("PASS: \(path) — AVPlayer decoded BGRA \(CVPixelBufferGetWidth(frame))×\(CVPixelBufferGetHeight(frame))")
            }
        }
        print("12 macOS streaming decode probes passed; visionOS and immersive rendering remain untested.")
    }
    enum ProbeError: Error { case failed(String) }
}
