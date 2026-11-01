import ARKit
import AVFoundation
import Metal
import QuartzCore
import RealityKit
import simd
import UIKit

@MainActor
final class ImmersiveRenderer: NSObject {
    static let panoramaRadius: Float = 1000
    let video = ModelEntity()
    let controls: Entity
    let inputSurface = Entity()
    private let diagnosticOverlay: Entity?
    private let playback: PlaybackModel
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState
    private let unusedRight: any MTLTexture
    private var cache: CVMetalTextureCache?
    private var left: LowLevelTexture?
    private var right: LowLevelTexture?
    private var material: ShaderGraphMaterial?
    private var texturePlan: VideoTexturePlan?
    private var eyeResources: (TextureResource, TextureResource)?
    private var lastImageMode: VideoImageMode?
    private var samplerMode: VideoImageMode?
    private var samplerWrapping: Bool?
    private weak var lastOutput: AVPlayerItemVideoOutput?
    private var frameTime: CMTime?
    private var frameInfo: VideoPipelineSnapshot.Frame?
    private var renderInfo: VideoPipelineSnapshot.Render?
    private var performance = VideoPipelineSnapshot.Performance()
    private let processSampler = VideoProcessSampler()
    private var lastPublish = -Double.infinity
    private var gpuSum = 0.0
    private var gpuSamples = 0
    private var displayLink: CADisplayLink?
    private var displayTarget: DisplayTarget?
    private var processing = false
    private var running = false
    private var token = UUID()
    private var pendingFrames = 0
    private var frameLeases: [UUID: FrameLease] = [:]
    private let session = ARKitSession()
    private let tracking = WorldTrackingProvider()
    private var trackingStarted = false
    private var didCenter = false
    private var lastRecenter = -1
    private var lastControlsPlacement = -1
    private var viewingPose = ViewingPose()
    private var lastProjection: VideoProjection?
    private var lastFlatScreen: Bool?
    private var meshSourceSize = SIMD2<Int>(0, 0)
    private var lastLayout: StereoLayout?
    private var lastSwap: Bool?
    private var lastFlip: Bool?
    private var lastPixelBuffer: CVPixelBuffer?

    init(playback: PlaybackModel, controls: Entity, diagnosticOverlay: Entity? = nil) throws {
        self.playback = playback
        self.controls = controls
        self.diagnosticOverlay = diagnosticOverlay
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(), let function = library.makeFunction(name: "prepareVideoFrame") else {
            throw RendererError.unavailable
        }
        self.device = device; self.queue = queue
        let dummy = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        dummy.usage = [.shaderWrite]; dummy.storageMode = .private
        guard let unused = device.makeTexture(descriptor: dummy) else { throw RendererError.unavailable }
        unusedRight = unused
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
        // A hollow inward-facing mesh is hittable from inside the panorama.
        // Keep it behind the attachment so it cannot steal taps on its buttons.
        let inputMesh = ProjectionMesh.generate(projection: .vr360, columns: 32, rows: 16, radius: 6)
        let shape = try await ShapeResource.generateStaticMesh(positions: inputMesh.positions, faceIndices: inputMesh.indices.map(UInt16.init))
        guard token == currentToken, !Task.isCancelled else { return }
        inputSurface.name = "Show or hide playback controls"
        inputSurface.components.set(CollisionComponent(shapes: [shape], mode: .trigger))
        inputSurface.components.set(InputTargetComponent(allowedInputTypes: .indirect))
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
        // A request, not a claim about display refresh. Publish the observed interval.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        displayLink = link
        link.add(to: .main, forMode: .common)
        playback.play()
    }

    func stop() {
        running = false; token = UUID()
        displayLink?.invalidate(); displayLink = nil; displayTarget = nil
        session.stop(); trackingStarted = false
        releaseVideoResources()
    }

    private func releaseVideoResources() {
        video.isEnabled = false
        guard video.model != nil || lastPixelBuffer != nil || left != nil || right != nil || material != nil else { return }
        video.model = nil
        lastPixelBuffer = nil; left = nil; right = nil; material = nil; eyeResources = nil; texturePlan = nil
        if let cache { CVMetalTextureCacheFlush(cache, 0) }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard running else { return }
        // Keep the tap surface and tracking alive if streaming fails, so an
        // error can reveal usable exit controls rather than strand the viewer.
        updatePose()
        playback.controls.tick(playing: playback.isPlaying,
            attention: playback.errorMessage != nil || playback.isBuffering || playback.isSeeking || playback.recenterCountdown != nil)
        if controls.isEnabled != playback.controls.isVisible { controls.isEnabled = playback.controls.isVisible }
        diagnosticOverlay?.isEnabled = playback.showVideoDiagnostics
        let interval = (link.targetTimestamp - link.timestamp) * 1000
        performance.displayLinkIntervalMs = interval.isFinite && interval > 0 ? interval : nil
        guard playback.isReady else {
            if !playback.isPreparing { releaseVideoResources() }
            else { video.isEnabled = false }
            return
        }
        guard let output = playback.videoOutput else { return }
        if lastOutput !== output {
            lastOutput = output; lastPixelBuffer = nil; frameTime = nil; frameInfo = nil
            lastImageMode = nil; performance = .init(); gpuSum = 0; gpuSamples = 0; lastPublish = -.infinity
            video.isEnabled = false
        }
        // Flush the most recent frame/metrics at most once a second, including
        // after pause when no new GPU completion would otherwise publish them.
        publishDiagnostics()
        guard !processing else { performance.backpressureSkips += 1; return }
        let time = output.itemTime(forHostTime: link.targetTimestamp)
        let meshChanged = lastProjection != playback.projection || lastFlatScreen != playback.flatScreen
        let settingsChanged = meshChanged || lastLayout != playback.layout || lastSwap != playback.swapEyes || lastFlip != playback.flipY || lastImageMode != playback.imageMode
        var actualTime = CMTime.invalid
        if output.hasNewPixelBuffer(forItemTime: time),
           let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &actualTime) {
            if let previous = frameTime?.seconds, actualTime.seconds.isFinite, actualTime.seconds > previous {
                let delta = (actualTime.seconds - previous) * 1000
                performance.lastSourcePTSIntervalMs = delta < 1000 && !playback.isSeeking ? delta : nil
            }
            frameTime = actualTime; lastPixelBuffer = buffer; performance.acquiredBuffers += 1
            playback.observeFormatFrame(buffer)
        }
        else if !settingsChanged { return }
        guard let buffer = lastPixelBuffer else { return }
        let currentToken = token
        processing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.processing = false }
            do { try await self.upload(buffer, time: self.frameTime, output: output, token: currentToken) }
            catch {
                guard self.token == currentToken else { return }
                // Preserve unsupported-frame evidence without publishing normal
                // frame metadata to SwiftUI at video cadence. Successful frames
                // publish through the throttled completion path below.
                self.playback.observedDecodedFrame(VideoPipelineInspection.frame(buffer, time: self.frameTime))
                self.playback.fail("This decoded frame’s colour format or size is unsupported. Check Playback details or try an SDR source.")
            }
        }
    }

    private func upload(_ buffer: CVPixelBuffer, time: CMTime?, output: AVPlayerItemVideoOutput, token currentToken: UUID) async throws {
        guard token == currentToken, running, playback.videoOutput === output else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let inspected = VideoPipelineInspection.frame(buffer, time: time)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_64RGBAHalf, let cache else { throw RendererError.unsupportedSize }
        var colorMode = try VideoPipelineInspection.colorMode(inspected)
        if colorMode == 2, ["SMPTE_ST_2084_PQ", "ITU_R_2100_HLG"].contains(playback.videoPipeline.source.transferFunction ?? "") {
            throw VideoPipelineInspection.ColorError.unsupported
        }
        let layout = playback.layout
        let mode = playback.imageMode
        let plan = try VideoTexturePlan(width: width, height: height, layout: layout, mode: mode)
        // Match geometry and texture packing in the same actor turn. Settings
        // can change after tick schedules this task but before it starts.
        let dimensions = SIMD2(width, height)
        let meshChanged = lastProjection != playback.projection || lastFlatScreen != playback.flatScreen
        if meshChanged || (playback.flatScreen && (meshSourceSize != dimensions || lastLayout != layout)) {
            try rebuildMesh()
        }
        let size = SIMD2<Int>(plan.width, plan.height)
        if plan != texturePlan || left == nil {
            video.isEnabled = false
            let descriptor = LowLevelTexture.Descriptor(pixelFormat: .rgba16Float,
                width: size.x, height: size.y, mipmapLevelCount: plan.mipLevels, textureUsage: [.shaderRead, .shaderWrite])
            let newLeft = try LowLevelTexture(descriptor: descriptor)
            let newRight = plan.textureCount == 2 ? try LowLevelTexture(descriptor: descriptor) : nil
            let leftResource = try await TextureResource(from: newLeft)
            let rightResource: TextureResource
            if let newRight { rightResource = try await TextureResource(from: newRight) } else { rightResource = leftResource }
            guard token == currentToken, running, playback.videoOutput === output else { return }
            left = newLeft; right = newRight; texturePlan = plan; samplerMode = nil
            eyeResources = (leftResource, rightResource)
        }
        let wrapping = !playback.flatScreen && playback.projection == .vr360
        if let resources = eyeResources, var updated = material, samplerMode != mode || samplerWrapping != wrapping {
            let descriptor = Self.sampler(mode: mode, wrapping: wrapping)
            let sampler = MaterialParameters.Texture.Sampler(descriptor)
            try updated.setParameter(name: "leftEye", value: .texture(.init(resources.0, sampler: sampler)))
            try updated.setParameter(name: "rightEye", value: .texture(.init(resources.1, sampler: sampler)))
            material = updated; video.model?.materials = [updated]
            samplerMode = mode; samplerWrapping = wrapping
        }
        guard token == currentToken, running, playback.videoOutput === output, let left else { return }
        guard pendingFrames < 2 else { performance.backpressureSkips += 1; return }
        pendingFrames += 1
        var submitted = false
        defer { if !submitted { pendingFrames -= 1 } }
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil,
            .rgba16Float, width, height, 0, &cvTexture)
        guard result == kCVReturnSuccess, let cvTexture, let source = CVMetalTextureGetTexture(cvTexture),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw RendererError.unavailable
        }
        let leftTexture = left.replace(using: command), rightTexture = right?.replace(using: command) ?? unusedRight
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(leftTexture, index: 1)
        encoder.setTexture(rightTexture, index: 2)
        var parameters = SIMD4<UInt32>(layout == .mono ? 0 : (layout == .sideBySide ? 1 : 2),
            playback.swapEyes ? 1 : 0, playback.flipY ? 1 : 0, mode == .enhanced ? 1 : (mode == .maximum ? 2 : 0))
        encoder.setBytes(&parameters, length: MemoryLayout<SIMD4<UInt32>>.stride, index: 0)
        encoder.setBytes(&colorMode, length: MemoryLayout<UInt32>.stride, index: 1)
        let group = MTLSize(width: 16, height: 8, depth: 1)
        encoder.dispatchThreads(MTLSize(width: size.x, height: size.y, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        if plan.mipLevels > 1 {
            guard let blit = command.makeBlitCommandEncoder() else { throw RendererError.unavailable }
            blit.generateMipmaps(for: leftTexture)
            if plan.textureCount == 2 { blit.generateMipmaps(for: rightTexture) }
            blit.endEncoding()
        }
        frameInfo = VideoPipelineInspection.frame(buffer, time: time)
        let horizontalDegrees: Double = playback.projection == .vr180 ? 180 : 360
        renderInfo = .init(mode: mode, plan: plan, projection: playback.presentation, layout: layout,
            mipFilter: plan.mipLevels > 1 ? "linear" : "notMipmapped", maximumAnisotropy: mode == .maximum ? 8 : 1,
            horizontalWrap: !playback.flatScreen && playback.projection == .vr360 ? "repeat" : "clampToEdge",
            meshColumns: playback.flatScreen ? 1 : mode.meshColumns(for: playback.projection), meshRows: playback.flatScreen ? 1 : mode.meshRows,
            estimatedSourceHorizontalPPD: playback.flatScreen ? nil : Double(plan.sourceEyeWidth) / horizontalDegrees,
            estimatedTextureHorizontalPPD: playback.flatScreen ? nil : Double(plan.width) / horizontalDegrees,
            estimatedVerticalPPD: playback.flatScreen ? nil : Double(plan.height) / 180, panoramaRadiusMetres: playback.flatScreen ? nil : Double(Self.panoramaRadius))
        renderInfo?.colorInterpretation = colorMode == 2 ? "Untagged RGB: assumed SDR sRGB, matching previous playback; source colour intent unknown" : "Verified linear frame attachments; P3 converted to linear sRGB when needed"
        performance.lastCPUPreparationWallMs = (ProcessInfo.processInfo.systemUptime - started) * 1000
        performance.submittedFrames += 1
        let submittedAt = ProcessInfo.processInfo.systemUptime
        let modeChanged = lastImageMode != mode
        // Retain the IOSurface and CVMetalTexture until the GPU has finished reading them.
        let leaseID = UUID()
        frameLeases[leaseID] = FrameLease(buffer: buffer, texture: cvTexture)
        // Keep this cache owner alive until the command completes. Release
        // Core Video objects on the same actor as cache creation/flush, even if
        // the scene was dismissed while GPU work was still in flight.
        command.addCompletedHandler { @Sendable [self] command in
            let succeeded = command.status == .completed
            let gpuMs = command.gpuStartTime > 0 && command.gpuEndTime > command.gpuStartTime ? (command.gpuEndTime - command.gpuStartTime) * 1000 : nil
            Task { @MainActor [self] in
                self.frameLeases.removeValue(forKey: leaseID)
                self.pendingFrames -= 1
                guard self.token == currentToken, self.running, self.playback.isReady, self.playback.videoOutput === output else { return }
                self.performance.lastGPUPreparationMs = gpuMs
                if let gpuMs { self.gpuSum += gpuMs; self.gpuSamples += 1; self.performance.meanGPUPreparationMs = self.gpuSum / Double(self.gpuSamples) }
                self.performance.lastSubmitToCallbackMs = (ProcessInfo.processInfo.systemUptime - submittedAt) * 1000
                if succeeded { self.performance.completedFrames += 1; self.video.isEnabled = true; self.playback.receivedFrame(width: width, height: height); self.publishDiagnostics(force: modeChanged || self.performance.completedFrames == 1) }
                else { self.performance.failedCommands += 1; self.publishDiagnostics(force: true); self.playback.fail("The GPU could not display this video frame.") }
            }
        }
        lastLayout = layout; lastSwap = playback.swapEyes; lastFlip = playback.flipY
        lastImageMode = mode
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
        } else { mesh = ProjectionMesh.generate(projection: playback.projection, columns: playback.imageMode.meshColumns(for: playback.projection), rows: playback.imageMode.meshRows, radius: Self.panoramaRadius) }
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
        inputSurface.position = position
        // Panorama is effectively infinitely distant: follow translation, preserve orientation.
        if !playback.flatScreen { video.position = position }
        if !didCenter || lastRecenter != playback.recenterID {
            viewingPose.recenter(head: transform, upright: playback.recenterUpright)
            video.position = position
            controls.position = viewingPose.controlsPosition(viewer: position)
            controls.orientation = viewingPose.controlsOrientation
            lastRecenter = playback.recenterID; didCenter = true
        }
        if lastControlsPlacement != playback.controls.placementID {
            viewingPose.placeControls(head: transform)
            controls.position = viewingPose.controlsPosition(viewer: position)
            controls.orientation = viewingPose.controlsOrientation
            lastControlsPlacement = playback.controls.placementID
        }
        // Manual tilt rotates the video around its captured local right axis.
        // Controls stay reachable while adjusting it, rather than following the slider.
        video.orientation = viewingPose.videoOrientation(tiltDegrees: playback.viewingTilt)
        diagnosticOverlay?.orientation = controls.orientation
        diagnosticOverlay?.position = controls.position + controls.orientation.act(SIMD3<Float>(-0.7, 0.75, 0.05))

    }

    static func sampler(mode: VideoImageMode, wrapping: Bool) -> MTLSamplerDescriptor {
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear; sampler.magFilter = .linear
        sampler.mipFilter = mode == .maximum ? .linear : .notMipmapped
        sampler.maxAnisotropy = mode == .maximum ? 8 : 1
        sampler.sAddressMode = wrapping ? .repeat : .clampToEdge; sampler.tAddressMode = .clampToEdge
        return sampler
    }

    private func publishDiagnostics(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard (force || now - lastPublish >= 1), let frameInfo, let renderInfo else { return }
        lastPublish = now
        performance.playerDroppedFrames = playback.player.currentItem?.accessLog()?.events.last.flatMap { $0.numberOfDroppedVideoFrames >= 0 ? $0.numberOfDroppedVideoFrames : nil }
        processSampler.sample(&performance, device: device)
        playback.updateVideoPipeline(frame: frameInfo, render: renderInfo, performance: performance)
    }
}

private enum RendererError: Error { case unavailable, unsupportedSize }

// Owned and released only on the main actor after GPU completion.
@MainActor private final class FrameLease {
    let buffer: CVPixelBuffer
    let texture: CVMetalTexture
    init(buffer: CVPixelBuffer, texture: CVMetalTexture) { self.buffer = buffer; self.texture = texture }
}

@MainActor private final class DisplayTarget: NSObject {
    weak var renderer: ImmersiveRenderer?
    init(renderer: ImmersiveRenderer) { self.renderer = renderer }
    @objc func frame(_ link: CADisplayLink) { renderer?.tick(link) }
}
