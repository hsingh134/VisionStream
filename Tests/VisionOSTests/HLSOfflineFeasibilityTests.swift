import AVFoundation
import RealityKit
import XCTest
@testable import VisionStream

/// Explicit platform probe, separate from advertised product functionality.
@MainActor final class HLSOfflineFeasibilityTests: XCTestCase {
    func testSystemHLSDownloadAndOfflineDecode() async throws {
        guard ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_HLS_OFFLINE_PROBE"] == "1" else {
            throw XCTSkip("Opt into the HLS offline platform probe")
        }
        let raw = try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"])
        let base = try XCTUnwrap(URL(string: raw))
        guard base.scheme == "https", ["localhost", "127.0.0.1"].contains(base.host), base.port != nil else { throw URLError(.badURL) }
        let publicSample = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_HLS_PUBLIC_PROBE"] == "1"
        let url = publicSample ? URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")! : base.appendingPathComponent("quality/master.m3u8")
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let probe = HLSOfflineProbe()
        let deadline = Task { try? await Task.sleep(for: .seconds(45)); if !Task.isCancelled { probe.cancel() } }
        defer { deadline.cancel(); probe.cancel() }
        let package: URL
        do { package = try await probe.download(asset, publicSample: publicSample) }
        catch {
            let error = error as NSError
            XCTFail("HLS offline probe rejected by platform: \(error.domain):\(error.code)")
            return
        }
        defer { try? FileManager.default.removeItem(at: package) }
        let local = AVURLAsset(url: package)
        XCTAssertTrue(local.assetCache?.isPlayableOffline == true)
        let item = AVPlayerItem(asset: local), player = AVPlayer(playerItem: item)
        player.isMuted = true
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output); player.play()
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        let end = Date().addingTimeInterval(15)
        var decoded = false
        while Date() < end, !decoded {
            if let buffer = output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) {
                decoded = CVPixelBufferGetWidth(buffer) > 0 && CVPixelBufferGetHeight(buffer) > 0
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(decoded, "The downloaded HLS package did not yield local frames")
    }
}

private final class HLSOfflineProbe: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AVAssetDownloadURLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var location: URL?
    func download(_ asset: AVURLAsset, publicSample: Bool) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let config = URLSessionConfiguration.background(withIdentifier: "personal.visionstream.hls-probe." + UUID().uuidString)
                config.sessionSendsLaunchEvents = false
                let session = AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: nil)
                let download = AVAssetDownloadConfiguration(asset: asset, title: publicSample ? "Apple developer HLS sample" : "Original CC0 HLS calibration")
                if publicSample { download.primaryContentConfiguration.variantQualifiers = [AVAssetVariantQualifier(predicate: NSPredicate(format: "peakBitRate < 600000"))] }
                download.auxiliaryContentConfigurations = []
                lock.lock(); self.continuation = continuation; self.session = session; lock.unlock()
                session.makeAssetDownloadTask(downloadConfiguration: download).resume()
            }
        } onCancel: { self.cancel() }
    }
    func cancel() { lock.lock(); let session = session; lock.unlock(); session?.invalidateAndCancel() }
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        lock.lock(); self.location = location; lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let callback = continuation; continuation = nil; let location = location; self.session = nil; lock.unlock()
        session.finishTasksAndInvalidate()
        if let error { if let location { try? FileManager.default.removeItem(at: location) }; callback?.resume(throwing: error) }
        else if let location { callback?.resume(returning: location) }
        else { callback?.resume(throwing: URLError(.fileDoesNotExist)) }
    }
}
