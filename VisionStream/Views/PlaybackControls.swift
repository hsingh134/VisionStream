import SwiftUI

@MainActor struct PlaybackControls: View {
    let app: AppModel
    var immersive = false
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var scrubTime = 0.0
    @State private var scrubbing = false
    @State private var showFormat = false
    @State private var showQuality = false
    @State private var showPosition = false
    @State private var returningToPage = false
    @State private var returnError: String?
    var body: some View {
        @Bindable var playback = app.playback
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "visionpro.fill").font(.title2).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("VisionStream").font(.headline)
                    Text(playback.decodedWidth > 0 ? "\(playback.decodedWidth) × \(playback.decodedHeight) · \(playback.qualityStatus)" : playback.qualityStatus)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if playback.isBuffering || playback.isSeeking || playback.isPreparing { ProgressView().controlSize(.small).accessibilityLabel("Loading video") }
                Button { showFormat = false; showPosition = false; showQuality.toggle() } label: { Label(playback.isOffline ? "Offline" : playback.quality.label, systemImage: "sparkles.tv") }
                    .disabled(playback.isPreparing || playback.isOffline).accessibilityLabel(playback.isOffline ? "Offline video quality" : "Streaming quality")
            }
            if let returnError { Text(returnError).font(.callout).foregroundStyle(.orange) }
            if let error = playback.errorMessage { Text(error).font(.callout).foregroundStyle(.orange) }
            if let countdown = playback.recenterCountdown {
                HStack {
                    Text("Look where you want the video centred · \(countdown)").font(.callout)
                    Spacer()
                    Button("Cancel") { playback.cancelScheduledRecenter() }
                }
            }
            if let notice = playback.systemNotice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            VStack(spacing: 6) {
                if playback.seekEnd > playback.seekStart {
                    Slider(value: Binding(
                        get: { min(max(scrubbing ? scrubTime : playback.elapsed, playback.seekStart), playback.seekEnd) },
                        set: { scrubTime = $0 }), in: playback.seekStart...playback.seekEnd,
                        onEditingChanged: { editing in
                            if editing { scrubTime = playback.elapsed }
                            scrubbing = editing
                            if !editing { playback.seek(to: scrubTime) }
                        }).tint(.white).accessibilityLabel("Playback position")
                }
                HStack {
                    Text(time(scrubbing ? scrubTime : playback.elapsed))
                    Spacer()
                    Text(playback.duration > 0 ? time(playback.duration) : "LIVE")
                }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 26) {
                transport("Back 15 seconds", icon: "gobackward.15") { playback.skip(-15) }
                    .disabled(!playback.isReady || playback.seekEnd <= playback.seekStart)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying || playback.isBuffering ? "pause.fill" : "play.fill")
                        .font(.title).frame(width: 64, height: 64)
                }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).buttonBorderShape(.circle)
                    .disabled(!playback.isReady || playback.isAudioInterrupted).accessibilityLabel(playback.isPlaying || playback.isBuffering ? "Pause" : "Play")
                    .keyboardShortcut(.space, modifiers: [])
                transport("Forward 15 seconds", icon: "goforward.15") { playback.skip(15) }
                    .disabled(!playback.isReady || playback.seekEnd <= playback.seekStart)
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            Divider().opacity(0.4)
            HStack {
                Button { showQuality = false; showPosition = false; showFormat.toggle() } label: {
                    Label("\(playback.automaticallyDetectFormat ? "Auto · " : "")\(playback.presentation.label) · \(playback.layout.label)", systemImage: "slider.horizontal.3")
                        .font(.callout)
                }
                    .accessibilityLabel("Video format settings")
                Spacer()
                if immersive {
                    Button { showQuality = false; showFormat = false; showPosition.toggle() } label: { Label("Position", systemImage: "move.3d") }
                        .accessibilityLabel("Viewing position")
                    Button("Recenter", systemImage: "scope") { startRecenter() }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                    Button("Return to page", systemImage: "xmark") { Task { await returnToPage() } }
                        .disabled(returningToPage)
                        .keyboardShortcut("b", modifiers: [.command, .shift])
                }
            }
            // View attachments cannot reliably present window popovers. Expand
            // the selected settings inside the same movable control surface.
            if showPosition {
                Divider()
                positionSettings.simulatorPanel(.position)
                Button("Done") { showPosition = false }.frame(maxWidth: .infinity, alignment: .trailing)
            } else if showFormat {
                Divider()
                formatSettings.simulatorPanel(.format)
                Button("Done") { showFormat = false }.frame(maxWidth: .infinity, alignment: .trailing)
            } else if showQuality {
                Divider()
                qualitySettings.simulatorPanel(.quality)
                Button("Done") { showQuality = false }.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(28).controlSize(.regular)
            .simulatorPanel(.playback)
            .onAppear {
                #if targetEnvironment(simulator)
                if immersive && SimulatorScenarioRunner.isConfigured {
                    SimulatorScenarioRunner.returnAction = returnToPage
                    SimulatorScenarioRunner.controlActions = .init(
                        format: { showFormat = $0 }, quality: { showQuality = $0 },
                        selectQuality: selectQuality, presentation: setPresentation, layout: setLayout,
                        automatic: setAutomatic, position: { showPosition = $0 },
                        tilt: playback.setViewingTilt, recenter: startRecenter,
                        upright: { playback.recenter(upright: true) })
                }
                #endif
            }
            .onDisappear {
                #if targetEnvironment(simulator)
                if immersive { SimulatorScenarioRunner.returnAction = nil; SimulatorScenarioRunner.controlActions = nil }
                #endif
            }
    }
    private func startRecenter() {
        showPosition = false
        app.playback.scheduleRecenter()
    }

    private var positionSettings: some View {
        let playback = app.playback
        return VStack(alignment: .leading, spacing: 18) {
            Text("Viewing position").font(.title3.bold())
            Text("Recenter, then look where you want the video to face. Your head angle becomes the new centre, whether sitting or lying down.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Recenter in 3 seconds", systemImage: "scope") { startRecenter() }
                .buttonStyle(.borderedProminent)
            Divider()
            HStack {
                Text("Video tilt")
                Spacer()
                Text("\(Int(playback.viewingTilt))°").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { playback.viewingTilt }, set: playback.setViewingTilt), in: -90...90, step: 1)
                .accessibilityLabel("Video tilt")
                .accessibilityValue("\(Int(playback.viewingTilt)) degrees")
            HStack {
                Text("Lower"); Spacer(); Text("Raise")
            }.font(.caption).foregroundStyle(.secondary)
            Button("Reset tilt") { playback.setViewingTilt(0) }.disabled(playback.viewingTilt == 0)
            Button("Reset upright", systemImage: "arrow.counterclockwise") {
                playback.recenter(upright: true)
            }
            Text("Reset upright levels the video with the room. Controls stay in front of you. Tilt adjusts only the video; Recenter clears tilt.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var qualitySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Streaming quality").font(.title3.bold())
            ForEach(PlaybackQuality.allCases) { quality in
                Button { selectQuality(quality) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(quality.label).font(.headline)
                            Text(quality == .highest ? "Use the highest supported published rendition." : "Let the player adjust to your connection.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if app.playback.quality == quality { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
            Text(app.playback.qualityStatus).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func selectQuality(_ value: PlaybackQuality) { showQuality = false; app.playback.changeQuality(value) }
    private func setPresentation(_ value: VideoPresentation) { app.playback.manualFormat(); app.playback.presentation = value }
    private func setLayout(_ value: StereoLayout) { app.playback.manualFormat(); app.playback.layout = value }
    private func setAutomatic(_ value: Bool) {
        if value { app.playback.enableAutomaticFormat() } else { app.playback.manualFormat() }
    }
    private var formatSettings: some View {
        @Bindable var playback = app.playback
        return VStack(alignment: .leading, spacing: 18) {
            Text("Video format").font(.title3.bold())
            Toggle("Detect automatically", isOn: Binding(get: { playback.automaticallyDetectFormat }, set: {
                setAutomatic($0)
            }))
            Text(playback.formatStatus).font(.caption).foregroundStyle(.secondary)
            Picker("Projection", selection: Binding(get: { playback.presentation }, set: setPresentation)) {
                ForEach(VideoPresentation.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Image layout", selection: Binding(get: { playback.layout }, set: setLayout)) {
                ForEach(StereoLayout.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Toggle("Swap eyes", isOn: $playback.swapEyes)
                Toggle("Flip vertically", isOn: $playback.flipY)
            }.toggleStyle(.button)
            Text("If the format is not identified, choose the projection and eye layout supplied with the video.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func transport(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.title2).frame(width: 44, height: 44) }
            .buttonBorderShape(.circle).accessibilityLabel(title)
    }
    private func returnToPage() async {
        guard !returningToPage else { return }
        returningToPage = true; returnError = nil
        defer { returningToPage = false }
        app.playback.cancelScheduledRecenter()
        openWindow(id: "browser")
        // Never ask visionOS to dismiss the last scene before its replacement
        // window exists. Keep the exit control alive if presentation is delayed.
        for _ in 0..<50 {
            if app.browserWindowVisible { break }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard app.browserWindowVisible else {
            returnError = "The browser window did not reopen. Try Return to page again."
            return
        }
        await dismissImmersiveSpace()
    }
    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "LIVE" }
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

