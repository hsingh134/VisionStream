import SwiftUI

/// Standard keyboard commands for the native Playback window. These invoke the
/// same model bindings as the visible projection/layout controls.
@MainActor struct PlaybackModeCommands: Commands {
    let playback: PlaybackModel
    var body: some Commands {
        CommandMenu("Playback mode") {
            Button("Screen") { playback.manualFormat(); playback.presentation = .screen }.keyboardShortcut("1", modifiers: .command)
            Button("VR180") { playback.manualFormat(); playback.presentation = .vr180 }.keyboardShortcut("2", modifiers: .command)
            Button("VR360") { playback.manualFormat(); playback.presentation = .vr360 }.keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Single image") { playback.manualFormat(); playback.layout = .mono }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("Side by side") { playback.manualFormat(); playback.layout = .sideBySide }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("Top bottom") { playback.manualFormat(); playback.layout = .topBottom }.keyboardShortcut("3", modifiers: [.command, .option])
            Divider()
            Toggle("Swap eyes", isOn: Binding(get: { playback.swapEyes }, set: { playback.swapEyes = $0 }))
                .keyboardShortcut("e", modifiers: [.command, .option])
            Toggle("Flip vertically", isOn: Binding(get: { playback.flipY }, set: { playback.flipY = $0 }))
                .keyboardShortcut("y", modifiers: [.command, .option])
        }
    }
}
