import SwiftUI

@MainActor struct VideoPipelineOverlay: View {
    let playback: PlaybackModel
    var body: some View {
        let s=playback.videoPipeline
        VStack(alignment:.leading,spacing:7) {
            Text("Video pipeline · \(playback.imageMode.label)").font(.headline)
            row("Source track", "\(s.source.codec ?? "unknown") · \(size(s.source.trackWidth,s.source.trackHeight)) · \(number(s.source.nominalFrameRate)) fps · \(number(s.source.estimatedBitrate.map { $0/1_000_000 })) Mb/s estimated")
            row("Source precision", s.source.bitsPerComponent.map { "\($0)-bit declared" } ?? "Not exposed; float output does not establish source bit depth")
            if let codecs=s.source.declaredHLSCodecs {
                row("HLS declaration", "\(size(s.source.declaredHLSWidth,s.source.declaredHLSHeight)) · \(codecs) · \(number(s.source.declaredHLSBitrate.map { Double($0)/1_000_000 })) Mb/s advertised; not a decoded-track measurement")
            }
            if let f=s.frame {
                row("Decoded buffer", "\(f.width) × \(f.height) · \(f.pixelFormat) · \(f.storageBitsPerComponent.map(String.init) ?? "?")-bit storage/component")
                row("Output colour", "\(f.colorPrimaries ?? "unknown") / \(f.transferFunction ?? "unknown")")
            }
            row("Source colour", "\(s.source.colorPrimaries ?? "unknown") / \(s.source.transferFunction ?? "unknown") / \(s.source.yCbCrMatrix ?? "unknown")")
            if let r=s.render {
                row("Interpretation", r.colorInterpretation)
                row("Per eye", "\(r.plan.sourceEyeWidth) × \(r.plan.sourceEyeHeight) source → \(r.plan.width) × \(r.plan.height) texture")
                row("Textures", "RGBA16F · \(r.plan.textureCount) resource(s) · \(r.plan.mipLevels) mip(s) · aniso \(r.maximumAnisotropy) requested")
                row("Angular estimate", "\(number(r.estimatedTextureHorizontalPPD)) horizontal px/° · assumes full equirectangular coverage")
                if r.plan.downscaled { Text("Application texture budget reduced eye resolution to \(Int(r.plan.scale*100))%.").foregroundStyle(.orange) }
            }
            row("GPU preparation", "\(number(s.performance.meanGPUPreparationMs)) ms mean · excludes RealityKit rendering/compositor")
            row("CPU preparation", "\(number(s.performance.lastCPUPreparationWallMs)) ms wall · app CPU \(number(s.performance.processCPUPercentOfOneCore))% of one core")
            row("Buffers / uploads", "\(s.performance.acquiredBuffers) acquired · \(s.performance.completedFrames) completed · \(s.performance.backpressureSkips) poll/upload skips")
            row("Last source interval", "\(number(s.performance.lastSourcePTSIntervalMs)) ms between acquired frame timestamps; not nominal frame rate")
            row("Memory / thermal", "\(number(s.performance.processFootprintBytes.map { Double($0)/1_048_576 })) MiB process · \(s.performance.thermalState)")
            Text("Final eye drawables, total GPU use and hardware decoder choice: not exposed.\n\(s.environment)").foregroundStyle(.secondary)
        }.font(.system(.caption,design:.monospaced)).padding(22).frame(width:690,alignment:.leading)
            .glassBackgroundEffect().allowsHitTesting(false)
    }
    private func row(_ key:String,_ value:String)->some View { Text("\(key): \(value)").frame(maxWidth:.infinity,alignment:.leading) }
    private func number(_ value:Double?)->String { value.flatMap { $0.isFinite ? String(format:"%.2f",$0):nil } ?? "—" }
    private func size(_ w:Int?,_ h:Int?)->String { if let w,let h { return "\(w) × \(h)" };return "unknown size" }
}
