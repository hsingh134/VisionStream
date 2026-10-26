import SwiftUI

@main
@MainActor
struct VisionStreamApp: App {
    @UIApplicationDelegateAdaptor(VisionStreamApplicationDelegate.self) private var applicationDelegate
    @State private var app = AppModel()
    var body: some Scene {
        Window("VisionStream", id: "browser") { BrowserView(app: app) }
            .defaultSize(width: 1200, height: 850)
            .commands { PlaybackModeCommands(playback: app.playback) }
        ImmersiveSpace(id: "video") { ImmersivePlayerView(app: app) }
            .immersionStyle(selection: .constant(.full), in: .full)
    }
}
