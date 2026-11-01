import Foundation

/// These change image preparation/sampling, independently of stream rendition.
public enum VideoImageMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case original, enhanced, maximum
    public var id: Self { self }
    public var label: String {
        switch self { case .original: "Original"; case .enhanced: "Enhanced"; case .maximum: "Maximum Quality" }
    }
    public var explanation: String {
        switch self {
        case .original: "Faithful linear-light video. No sharpening."
        case .enhanced: "Gentle, locally bounded sharpening. Cannot recover missing source detail."
        case .maximum: "Faithful video with mipmaps and oblique filtering. Uses more GPU time and texture memory."
        }
    }
    public var meshRows: Int { 128 }
    public func meshColumns(for projection: VideoProjection) -> Int {
        256 * (projection == .vr360 ? 2 : 1)
    }
}

/// An application allocation policy, not a claim about the headset's limit.
/// Counts our visible eye texture descriptors, not RealityKit's private pools.
public struct VideoTexturePlan: Codable, Equatable, Sendable {
    public let sourceEyeWidth: Int
    public let sourceEyeHeight: Int
    public let width: Int
    public let height: Int
    public let textureCount: Int
    public let mipLevels: Int
    public let descriptorBytes: Int
    public let budgetBytes: Int
    public var downscaled: Bool { width != sourceEyeWidth || height != sourceEyeHeight }
    public var scale: Double { Double(width) / Double(sourceEyeWidth) }

    public init(width: Int, height: Int, layout: StereoLayout, mode: VideoImageMode,
                budgetBytes: Int? = nil) throws {
        guard (1...8192).contains(width), (1...8192).contains(height),
              layout != .sideBySide || width.isMultiple(of: 2),
              layout != .topBottom || height.isMultiple(of: 2) else { throw Invalid.dimensions }
        let eye = layout.eyeSize(width: width, height: height)
        guard eye.width > 0, eye.height > 0 else { throw Invalid.dimensions }
        sourceEyeWidth = eye.width; sourceEyeHeight = eye.height
        textureCount = layout == .mono ? 1 : 2
        let budget = budgetBytes ?? (mode == .maximum ? 512 : 384) * 1024 * 1024
        guard budget >= 8 * textureCount else { throw Invalid.budget }
        self.budgetBytes = budget
        var w = eye.width, h = eye.height
        while Self.bytes(width: w, height: h, mipmapped: mode == .maximum) * textureCount > budget {
            let bytes = Self.bytes(width: w, height: h, mipmapped: mode == .maximum) * textureCount
            let factor = sqrt(Double(budget) / Double(bytes))
            let nextW = max(1, Int(Double(w) * factor)), nextH = max(1, Int(Double(h) * factor))
            if nextW == w && nextH == h { if w >= h { w = max(1, w - 1) } else { h = max(1, h - 1) } }
            else { w = nextW; h = nextH }
        }
        self.width = w; self.height = h
        mipLevels = mode == .maximum ? Int(floor(log2(Double(max(w, h))))) + 1 : 1
        descriptorBytes = Self.bytes(width: w, height: h, mipmapped: mode == .maximum) * textureCount
    }

    private static func bytes(width: Int, height: Int, mipmapped: Bool) -> Int {
        var w = width, h = height, count = w * h * 8
        while mipmapped && (w > 1 || h > 1) { w = max(1, w / 2); h = max(1, h / 2); count += w * h * 8 }
        return count
    }
    public enum Invalid: Error { case dimensions, budget }
}

public struct VideoPipelineSnapshot: Codable, Sendable {
    public struct Source: Codable, Sendable {
        public var trackWidth: Int?
        public var trackHeight: Int?
        public var nominalFrameRate: Double?
        public var estimatedBitrate: Double?
        public var codec: String?
        public var bitsPerComponent: Int?
        public var bitDepthEvidence: String?
        public var colorPrimaries: String?
        public var transferFunction: String?
        public var yCbCrMatrix: String?
        public var fullRange: Bool?
        public var declaredHLSCodecs: String?
        public var declaredHLSWidth: Int?
        public var declaredHLSHeight: Int?
        public var declaredHLSBitrate: Int?
        public var metadataSample = "Not sampled"
        public init() {}
    }
    public struct Frame: Codable, Sendable {
        public var width: Int
        public var height: Int
        public var pixelFormat: String
        public var storageBitsPerComponent: Int?
        public var bytesPerRow: Int
        public var colorPrimaries: String?
        public var transferFunction: String?
        public var yCbCrMatrix: String?
        public var presentationSeconds: Double?
    }
    public struct Render: Codable, Sendable {
        public var mode: VideoImageMode
        public var plan: VideoTexturePlan
        public var projection: VideoPresentation
        public var layout: StereoLayout
        public var pixelFormat = "rgba16Float"
        public var magnificationFilter = "linear"
        public var minificationFilter = "linear"
        public var mipFilter: String
        public var maximumAnisotropy: Int
        public var horizontalWrap: String
        public var verticalWrap = "clampToEdge"
        public var workingColor = "Linear sRGB / BT.709 primaries"
        public var colorInterpretation = "Frame attachments verified"
        public var samplingEvidence = "Explicit public sampler descriptor bound; RealityKit final sampling is not measurable here"
        public var meshColumns: Int
        public var meshRows: Int
        public var estimatedSourceHorizontalPPD: Double?
        public var estimatedTextureHorizontalPPD: Double?
        public var estimatedVerticalPPD: Double?
        public var panoramaRadiusMetres: Double?
        public var angularEstimateAssumption = "Full equirectangular coverage; not display resolution or headset acuity"
        public var finalDrawable = "Unavailable: RealityKit owns the final eye render targets and compositor"
    }
    public struct Performance: Codable, Sendable {
        public var acquiredBuffers: Int = 0
        public var submittedFrames: Int = 0
        public var completedFrames: Int = 0
        public var backpressureSkips: Int = 0
        public var failedCommands: Int = 0
        public var lastGPUPreparationMs: Double?
        public var meanGPUPreparationMs: Double?
        public var lastCPUPreparationWallMs: Double?
        public var lastSubmitToCallbackMs: Double?
        public var lastSourcePTSIntervalMs: Double?
        public var displayLinkIntervalMs: Double?
        public var playerDroppedFrames: Int?
        public var processCPUPercentOfOneCore: Double?
        public var processFootprintBytes: UInt64?
        public var metalDeviceAllocatedBytes: Int?
        public var thermalState: String = "unknown"
        public var measurementScope = "App process and video preparation command only; not total GPU utilisation, decoder throughput, RealityKit render cost or photon latency"
        public init() {}
    }
    public var source = Source()
    public var frame: Frame?
    public var render: Render?
    public var performance = Performance()
    public var environment = "Not sampled"
    public var outputRequest = "AVFoundation extended-linear Display P3 RGBA half-float; original dimensions requested; Metal converts to linear sRGB"
    public var hardwareDecoder = "Unavailable: AVPlayer does not expose its decoder acceleration decision"
    public var hdrPresentation = "Linear extended values can be retained; final RealityKit EDR/display mapping requires physical validation"
    public init() {}

    private static let knownTags: Set<String> = ["ITU_R_709_2", "ITU_R_2020", "ITU_R_601_4", "Linear", "sRGB", "IEC_sRGB",
        "SMPTE_ST_2084_PQ", "ITU_R_2100_HLG", "SMPTE_240M_1995", "SMPTE_C", "P3_D65", "DCI_P3", "EBU_3213", "UseGamma"]
    public static func safeTag(_ value: String?) -> String? {
        value.map { knownTags.contains($0) ? $0 : "unrecognised" }
    }
    public static func safeDeclaredCodecs(_ value: String) -> String? {
        let components=value.lowercased().split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }
        guard !components.isEmpty,components.count<=8,components.allSatisfy({ c in
            !c.isEmpty && c.utf8.count<=64 && ["avc1","avc3","hvc1","hev1","mp4a","ac-3","ec-3"].contains(String(c.split(separator:".").first ?? "")) && c.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0==46 || $0==45 }
        }) else { return nil }
        return components.joined(separator:", ")
    }
}

/// ISO HEVC decoder-configuration fields also emitted by the bundled FFmpeg
/// source (libavformat/hevc.c). This reports declared coded precision only.
public enum VideoCodecPrecision {
    public static func hevc(configuration: Data) -> Int? {
        let bytes=Array(configuration.prefix(23))
        guard bytes.count==23,bytes[0]==1,bytes[17]&0xf8==0xf8,bytes[18]&0xf8==0xf8 else { return nil }
        return max(8+Int(bytes[17]&7),8+Int(bytes[18]&7))
    }
}
