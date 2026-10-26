import ARKit
import AVFoundation
import Metal
import QuartzCore
import RealityKit
import simd
import UIKit

@MainActor
final class ImmersiveRenderer: NSObject {
    let video = ModelEntity()
    let controls: Entity
    private let playback: PlaybackModel
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState
    private var cache: CVMetalTextureCache?
    private var left: LowLevelTexture?
    private var right: LowLevelTexture?
    private var material: ShaderGraphMaterial?
    private var textureSize = SIMD2<Int>(0, 0)
    private var displayLink: CADisplayLink?
    private var displayTarget: DisplayTarget?
    private var processing = false
    private var running = false
    private var token = UUID()
    private var pendingFrames = 0
    private let session = ARKitSession()
    private let tracking = WorldTrackingProvider()
    private var trackingStarted = false
    private var didCenter = false
    private var lastRecenter = -1
    private var viewingPose = ViewingPose()
    private var lastProjection: VideoProjection?
    private var lastFlatScreen: Bool?
    private var meshSourceSize = SIMD2<Int>(0, 0)
    private var lastLayout: StereoLayout?
    private var lastSwap: Bool?
    private var lastFlip: Bool?
    private var lastPixelBuffer: CVPixelBuffer?

    init(playback: PlaybackModel, controls: Entity) throws {
        self.playback = playback
        self.controls = controls
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(), let function = library.makeFunction(name: "splitStereoVideo") else {
            throw RendererError.unavailable
        }
        self.device = device; self.queue = queue
        pipeline = try device.makeComputePipelineState(function: function)
        super.init()
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw RendererError.unavailable
        }
    }

    func start() async throws {
        let currentToken = UUID(); token = currentToken
        var loaded = try await ShaderGraphMaterial(named: "/Root/StereoMaterial", from: "StereoMaterial.usda")
        guard token == currentToken, !Task.isCancelled else { return }
        // We build inward-facing triangles; disabling culling also makes pole seams robust.
        loaded.faceCulling = .none
        material = loaded
        try rebuildMesh()
        if WorldTrackingProvider.isSupported {
            try await session.run([tracking])
            guard token == currentToken, !Task.isCancelled else { session.stop(); return }
            trackingStarted = true
        }
        running = true
        video.isEnabled = false // Wait for a fully initialised texture, never show uninitialised GPU memory.
        let target = DisplayTarget(renderer: self)
        displayTarget = target
        let link = CADisplayLink(target: target, selector: #selector(DisplayTarget.frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 90, preferred: 90)
        displayLink = link
        link.add(to: .main, forMode: .common)
        playback.play()
    }

    func stop() {
        running = false; token = UUID()
        displayLink?.invalidate(); displayLink = nil; displayTarget = nil
        session.stop(); trackingStarted = false
        video.isEnabled = false
        video.model = nil
        lastPixelBuffer = nil; left = nil; right = nil; material = nil
        if let cache { CVMetalTextureCacheFlush(cache, 0) }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard running else { return }
        guard playback.isReady else { if !playback.isPreparing { stop() }; return }
        updatePose()
        guard !processing, let output = playback.videoOutput else { return }
        let time = output.itemTime(forHostTime: link.targetTimestamp)
        let meshChanged = lastProjection != playback.projection || lastFlatScreen != playback.flatScreen
        let settingsChanged = meshChanged || lastLayout != playback.layout || lastSwap != playback.swapEyes || lastFlip != playback.flipY
        if output.hasNewPixelBuffer(forItemTime: time),
           let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) { lastPixelBuffer = buffer; playback.observeFormatFrame(buffer) }
        else if !settingsChanged { return }
        guard let buffer = lastPixelBuffer else { return }
        let currentToken = token
        processing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.processing = false }
            do { try await self.upload(buffer, token: currentToken) }
            catch {
                guard self.token == currentToken else { return }
                self.playback.fail("The decoded video frame could not be rendered. Try a lower resolution SDR MP4 or HLS stream.")
            }
        }
    }

    private func upload(_ buffer: CVPixelBuffer, token currentToken: UUID) async throws {
        guard token == currentToken, running else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0, width <= 8192, height <= 8192, let cache else { throw RendererError.unsupportedSize }
        let layout = playback.layout
        // Match geometry and texture packing in the same actor turn. Settings
        // can change after tick schedules this task but before it starts.
        let dimensions = SIMD2(width, height)
        let meshChanged = lastProjection != playback.projection || lastFlatScreen != playback.flatScreen
        if meshChanged || (playback.flatScreen && (meshSourceSize != dimensions || lastLayout != layout)) {
            try rebuildMesh()
        }
        let eyeSize = layout.eyeSize(width: width, height: height)
        guard eyeSize.width > 0, eyeSize.height > 0 else { throw RendererError.unsupportedSize }
        // Keep the prototype's GPU allocation bounded. Decoder input may be larger.
        let scale = min(1, 4096 / Double(max(eyeSize.width, eyeSize.height)))
        let size = SIMD2<Int>(max(1, Int(Double(eyeSize.width) * scale)), max(1, Int(Double(eyeSize.height) * scale)))
        if size != textureSize || left == nil {
            video.isEnabled = false
            let descriptor = LowLevelTexture.Descriptor(pixelFormat: .rgba16Float,
                width: size.x, height: size.y, textureUsage: [.shaderRead, .shaderWrite])
            let newLeft = try LowLevelTexture(descriptor: descriptor)
            let newRight = try LowLevelTexture(descriptor: descriptor)
            let leftResource = try await TextureResource(from: newLeft)
            let rightResource = try await TextureResource(from: newRight)
            guard token == currentToken, running, var updated = material else { return }
            try updated.setParameter(name: "leftEye", value: .textureResource(leftResource))
            try updated.setParameter(name: "rightEye", value: .textureResource(rightResource))
            left = newLeft; right = newRight; textureSize = size; material = updated
            video.model?.materials = [updated]
        }
        guard token == currentToken, running, let left, let right, pendingFrames < 2 else { return }
        pendingFrames += 1
        var submitted = false
        defer { if !submitted { pendingFrames -= 1 } }
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture)
        guard result == kCVReturnSuccess, let cvTexture, let source = CVMetalTextureGetTexture(cvTexture),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw RendererError.unavailable
        }
        let leftTexture = left.replace(using: command), rightTexture = right.replace(using: command)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(leftTexture, index: 1)
        encoder.setTexture(rightTexture, index: 2)
        var parameters = SIMD4<UInt32>(layout == .mono ? 0 : (layout == .sideBySide ? 1 : 2),
            playback.swapEyes ? 1 : 0, playback.flipY ? 1 : 0, 0)
        encoder.setBytes(&parameters, length: MemoryLayout<SIMD4<UInt32>>.stride, index: 0)
        let group = MTLSize(width: 16, height: 8, depth: 1)
        encoder.dispatchThreads(MTLSize(width: size.x, height: size.y, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        // Retain the IOSurface and CVMetalTexture until the GPU has finished reading them.
        let lease = FrameLease(buffer: buffer, texture: cvTexture)
        command.addCompletedHandler { @Sendable [weak self, lease] command in
            withExtendedLifetime(lease) {}
            let succeeded = command.status == .completed
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingFrames -= 1
                guard self.token == currentToken, self.running, self.playback.isReady else { return }
                if succeeded { self.video.isEnabled = true; self.playback.receivedFrame(width: width, height: height) }
                else { self.playback.fail("The GPU could not display this video frame.") }
            }
        }
        lastLayout = layout; lastSwap = playback.swapEyes; lastFlip = playback.flipY
        submitted = true
        command.commit()
    }

    private func rebuildMesh() throws {
        let mesh: ProjectionMesh
        if playback.flatScreen {
            let dimensions = lastPixelBuffer.map { SIMD2(CVPixelBufferGetWidth($0), CVPixelBufferGetHeight($0)) } ?? SIMD2(16, 9)
            let eye = playback.layout.eyeSize(width: dimensions.x, height: dimensions.y)
            mesh = ProjectionMesh.screen(aspectRatio: Float(eye.width) / Float(max(1, eye.height)))
            meshSourceSize = dimensions
        } else { mesh = ProjectionMesh.generate(projection: playback.projection) }
        var descriptor = MeshDescriptor(name: playback.flatScreen ? "Complete video frame" : "Equirectangular \(playback.projection.label)")
        descriptor.positions = MeshBuffer(mesh.positions)
        descriptor.normals = MeshBuffer(mesh.normals)
        descriptor.textureCoordinates = MeshBuffer(mesh.uv)
        descriptor.primitives = .triangles(mesh.indices)
        let resource = try MeshResource.generate(from: [descriptor])
        video.model = ModelComponent(mesh: resource, materials: material.map { [$0] } ?? [])
        lastProjection = playback.projection
        lastFlatScreen = playback.flatScreen
    }

    private func updatePose() {
        let transform: simd_float4x4
        if trackingStarted {
            guard let anchor = tracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), anchor.isTracked else { return }
            transform = anchor.originFromAnchorTransform
        } else {
            // Simulator fallback. Tracking and stereoscopy still require device verification.
            var fallback = matrix_identity_float4x4
            fallback.columns.3 = SIMD4<Float>(0, 1.6, 0, 1)
            transform = fallback
        }
        applyPose(transform)
    }

    func applyPose(_ transform: simd_float4x4) {
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        // Panorama is effectively infinitely distant: follow translation, preserve orientation.
        if !playback.flatScreen { video.position = position }
        if !didCenter || lastRecenter != playback.recenterID {
            viewingPose.recenter(head: transform, upright: playback.recenterUpright)
            video.position = position
            controls.position = viewingPose.controlsPosition(viewer: position)
            controls.orientation = viewingPose.controlsOrientation
            lastRecenter = playback.recenterID; didCenter = true
        }
        // Manual tilt rotates the video around its captured local right axis.
        // Controls stay reachable while adjusting it, rather than following the slider.
        video.orientation = viewingPose.videoOrientation(tiltDegrees: playback.viewingTilt)

    }
}

private enum RendererError: Error { case unavailable, unsupportedSize }

// Immutable retention capsule; it never reads or mutates either CF object off the main actor.
private final class FrameLease: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let texture: CVMetalTexture
    init(buffer: CVPixelBuffer, texture: CVMetalTexture) { self.buffer = buffer; self.texture = texture }
}

@MainActor private final class DisplayTarget: NSObject {
    weak var renderer: ImmersiveRenderer?
    init(renderer: ImmersiveRenderer) { self.renderer = renderer }
    @objc func frame(_ link: CADisplayLink) { renderer?.tick(link) }
}
