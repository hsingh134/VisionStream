import RealityKit
import SwiftUI

@MainActor struct ImmersivePlayerView: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var renderer: ImmersiveRenderer?

    var body: some View {
        RealityView { content, attachments in
            guard let transport = attachments.entity(for: "transport") else { return }
            app.playback.resetViewingPosition()
            app.playback.controls.reset()
            transport.position = [0, 1.2, -1.6]
            content.add(transport)
            do {
                let diagnostic = attachments.entity(for:"video-diagnostics")
                if let diagnostic { diagnostic.isEnabled = app.playback.showVideoDiagnostics; content.add(diagnostic) }
                let renderer = try ImmersiveRenderer(playback: app.playback, controls: transport, diagnosticOverlay: diagnostic)
                self.renderer = renderer
                content.add(renderer.video)
                content.add(renderer.inputSurface)
                try await renderer.start()
                #if targetEnvironment(simulator)
                if SimulatorScenarioRunner.isConfigured {
                    SimulatorScenarioRunner.sceneTap = { app.playback.controls.toggle() }
                    SimulatorScenarioRunner.controlsVisible = { [weak renderer] in renderer?.controls.isEnabled == true }
                    SimulatorScenarioRunner.diagnosticsVisible = { [weak diagnostic] in diagnostic?.isEnabled == true }
                    SimulatorScenarioRunner.inputSurfaceReady = { [weak renderer] in
                        guard let renderer, let scene = renderer.inputSurface.scene else { return false }
                        let viewer = renderer.inputSurface.position
                        return [SIMD3<Float>(0,0,-1), SIMD3<Float>(1,0,0), SIMD3<Float>(0,1,0)].allSatisfy { direction in
                            scene.raycast(origin: viewer, direction: direction, length: 8).contains { $0.entity === renderer.inputSurface }
                        }
                    }
                    SimulatorScenarioRunner.rendererPose = { [weak renderer] in
                        guard let renderer, renderer.video.isEnabled else { return nil }
                        let q = renderer.video.orientation.vector
                        let c = renderer.controls.position
                        return [Double(q.x),Double(q.y),Double(q.z),Double(q.w),Double(c.x),Double(c.y),Double(c.z)]
                    }
                    SimulatorScenarioRunner.rendererBounds = { [weak renderer] in
                        guard let renderer, renderer.video.isEnabled, let mesh = renderer.video.model?.mesh else { return nil }
                        let bounds = mesh.bounds.extents
                        return [Double(bounds.x), Double(bounds.y), Double(bounds.z)]
                    }
                }
                #endif
            } catch {
                app.history.record(.playerError,context:app.playback.diagnosticContext,labels:["phase":"renderer-start-failed"],codes:PlaybackDiagnostics.failure(error))
                app.playback.fail("The immersive renderer could not start. Check the bundled shader and device support, then return to the browser.")
            }
        } attachments: {
            Attachment(id:"video-diagnostics") { VideoPipelineOverlay(playback:app.playback) }
            Attachment(id: "transport") {
                PlaybackControls(app: app, immersive: true)
                    .accessibilityHidden(!app.playback.controls.isVisible)
                    .frame(width: 820)
                    .glassBackgroundEffect()
            }
        }
        .gesture(TapGesture().targetedToAnyEntity().onEnded { value in
            guard let renderer, value.entity === renderer.inputSurface else { return }
            app.playback.controls.toggle()
        })
        .onAppear { app.history.record(.lifecycle,context:app.playback.diagnosticContext,labels:["phase":"immersive-opened"]); app.playback.immersiveActive = true }
        .task(id: app.playback.quality) { await app.upgradeStreamingQualityIfNeeded() }
        .onDisappear {
            app.browser.useWebsiteControls()
            #if targetEnvironment(simulator)
            SimulatorScenarioRunner.rendererBounds = nil
            SimulatorScenarioRunner.rendererPose = nil
            SimulatorScenarioRunner.diagnosticsVisible = nil
            SimulatorScenarioRunner.sceneTap = nil; SimulatorScenarioRunner.controlsVisible = nil; SimulatorScenarioRunner.inputSurfaceReady = nil
            #endif
            app.history.record(.lifecycle,context:app.playback.diagnosticContext,labels:["phase":"immersive-closed"])
            renderer?.stop(); renderer = nil
            app.playback.stop(); app.playback.immersiveActive = false
            app.playback.cancelScheduledRecenter()
            openWindow(id: "browser")
        }
        .simulatorPanel(.immersive)
    }
}
