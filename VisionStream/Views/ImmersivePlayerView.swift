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
            transport.position = [0, 1.2, -1.6]
            content.add(transport)
            do {
                let renderer = try ImmersiveRenderer(playback: app.playback, controls: transport)
                self.renderer = renderer
                content.add(renderer.video)
                try await renderer.start()
                #if targetEnvironment(simulator)
                if SimulatorScenarioRunner.isConfigured {
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
            Attachment(id: "transport") {
                PlaybackControls(app: app, immersive: true)
                    .frame(width: 820)
                    .glassBackgroundEffect()
            }
        }
        .onAppear { app.history.record(.lifecycle,context:app.playback.diagnosticContext,labels:["phase":"immersive-opened"]); app.playback.immersiveActive = true }
        .onDisappear {
            #if targetEnvironment(simulator)
            SimulatorScenarioRunner.rendererBounds = nil
            SimulatorScenarioRunner.rendererPose = nil
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
