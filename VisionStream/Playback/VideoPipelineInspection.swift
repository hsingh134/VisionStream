import AVFoundation
import CoreVideo
import Darwin
import Metal

@MainActor enum VideoPipelineInspection {
    static var outputSettings: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf,
         kCVPixelBufferMetalCompatibilityKey as String: true,
         kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int](),
         AVVideoAllowWideColorKey: true,
         AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
                                    AVVideoTransferFunctionKey: AVVideoTransferFunction_Linear,
                                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]]
    }

    /// Inspect every frame: AVPlayer can change colour metadata at rendition/
    /// clip boundaries. Never equate floating-point storage with linear light.
    static func colorMode(_ frame: VideoPipelineSnapshot.Frame) throws -> UInt32 {
        if frame.transferFunction == "Linear" {
            if frame.colorPrimaries == "P3_D65" { return 1 }
            if frame.colorPrimaries == "ITU_R_709_2" { return 0 }
        }
        // Old, untagged SDR files have no conversion metadata. Preserve their
        // previous sRGB interpretation, explicitly reported as an assumption.
        if frame.transferFunction == nil && frame.colorPrimaries == nil { return 2 }
        throw ColorError.unsupported
    }
    enum ColorError: Error { case unsupported }

    static func source(_ asset: AVAsset) async -> VideoPipelineSnapshot.Source {
        var result = VideoPipelineSnapshot.Source()
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                result.metadataSample = "No video track exposed"; return result
            }
            let (formats, fps, rate) = try await track.load(.formatDescriptions, .nominalFrameRate, .estimatedDataRate)
            result.nominalFrameRate = fps.isFinite && fps > 0 ? Double(fps) : nil
            result.estimatedBitrate = rate.isFinite && rate > 0 ? Double(rate) : nil
            if let format = formats.first {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                if dimensions.width > 0, dimensions.height > 0 { result.trackWidth = Int(dimensions.width); result.trackHeight = Int(dimensions.height) }
                result.codec = fourCC(CMFormatDescriptionGetMediaSubType(format))
                result.colorPrimaries = VideoPipelineSnapshot.safeTag(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String)
                result.transferFunction = VideoPipelineSnapshot.safeTag(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String)
                result.yCbCrMatrix = VideoPipelineSnapshot.safeTag(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String)
                if let bits = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent) as? NSNumber, (8...32).contains(bits.intValue) {
                    result.bitsPerComponent = bits.intValue; result.bitDepthEvidence = "CoreMedia format description"
                } else if ["hvc1", "hev1"].contains(result.codec ?? ""),
                          let atoms = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Data],
                          let configuration = atoms["hvcC"], let bits = VideoCodecPrecision.hevc(configuration: configuration) {
                    result.bitsPerComponent = bits; result.bitDepthEvidence = "HEVC decoder configuration: declared coded precision"
                }
                result.fullRange = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_FullRangeVideo) as? Bool
            }
            result.metadataSample = "Asset video-track metadata sampled after preparation; may differ from a later adaptive rendition"
        } catch { result.metadataSample = "Unavailable from AVFoundation" }
        return result
    }

    static func frame(_ buffer: CVPixelBuffer, time: CMTime?) -> VideoPipelineSnapshot.Frame {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let seconds = time?.seconds
        return .init(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
            pixelFormat: fourCC(format), storageBitsPerComponent: format == kCVPixelFormatType_64RGBAHalf ? 16 : (format == kCVPixelFormatType_32BGRA ? 8 : nil),
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            colorPrimaries: tag(buffer, kCVImageBufferColorPrimariesKey), transferFunction: tag(buffer, kCVImageBufferTransferFunctionKey),
            yCbCrMatrix: tag(buffer, kCVImageBufferYCbCrMatrixKey), presentationSeconds: seconds.flatMap { $0.isFinite ? $0 : nil })
    }
    private static func tag(_ buffer: CVPixelBuffer, _ key: CFString) -> String? {
        VideoPipelineSnapshot.safeTag(CVBufferCopyAttachment(buffer, key, nil) as? String)
    }
    static func fourCC(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 255) }
        return bytes.allSatisfy { (32...126).contains($0) } ? String(bytes: bytes, encoding: .ascii)! : String(format: "%08x", value)
    }
}

/// Public measurements of this process, sampled once per second, not a profiler
/// for the system compositor, video decoder service or total device GPU load.
@MainActor final class VideoProcessSampler {
    private var previous: (wall: Double, cpu: Double)?
    func sample(_ performance: inout VideoPipelineSnapshot.Performance, device: any MTLDevice) {
        var usage = rusage()
        let now = ProcessInfo.processInfo.systemUptime
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            if let previous, now > previous.wall, cpu >= previous.cpu { performance.processCPUPercentOfOneCore = (cpu - previous.cpu) / (now - previous.wall) * 100 }
            previous = (now, cpu)
        }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        performance.processFootprintBytes = status == KERN_SUCCESS ? info.phys_footprint : nil
        performance.metalDeviceAllocatedBytes = device.currentAllocatedSize
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: performance.thermalState = "nominal"
        case .fair: performance.thermalState = "fair"
        case .serious: performance.thermalState = "serious"
        case .critical: performance.thermalState = "critical"
        @unknown default: performance.thermalState = "unknown"
        }
    }
}
