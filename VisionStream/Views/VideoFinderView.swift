import SwiftUI

@MainActor struct VideoFinderView: View {
    let app: AppModel
    let watch: (MediaCandidate) -> Void
    let download: (MediaCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Find a video stream").font(.title2)
            Text("Find MP4 and HLS sources on this headset. Some videos require browser-only login or a player feature that is not supported yet.")
                .foregroundStyle(.secondary)
            TextField("HTTPS video page or stream address", text: $address)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                .autocorrectionDisabled().keyboardType(.URL)
                .focused($addressFocused)
                .onSubmit { if !app.extractor.isLoading { find() } }
            HStack {
                Button("Done") { app.extractor.clear(); dismiss() }.keyboardShortcut("w", modifiers: .command)
                Spacer()
                if app.extractor.isLoading {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { app.extractor.clear() }
                } else {
                    Button("Find streams") { find() }.buttonStyle(.borderedProminent)
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let error = app.extractor.errorMessage { Text(error).foregroundStyle(.orange) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(app.extractor.streams) { stream in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(stream.label)
                                Spacer()
                                Button("Download", systemImage: "arrow.down.circle") { download(stream.candidate) }
                                    .labelStyle(.iconOnly).accessibilityLabel((app.saveInProgress ? "Add to queue " : "Download ")+stream.label)
                                    .disabled(stream.unavailableReason != nil || (!HLSOfflineLibrary.accepts(stream.candidate) && DownloadModel.unavailableReason(stream.candidate) != nil) || app.saveQueueFull)
                                Button("Watch in VR") { watch(stream.candidate) }
                                    .disabled(stream.unavailableReason != nil || app.playback.openingImmersive || app.playback.immersiveActive)
                                    .keyboardShortcut(stream.id == app.extractor.streams.first(where: { $0.unavailableReason == nil })?.id
                                        ? KeyboardShortcut("v", modifiers: [.command, .shift]) : nil)
                            }
                            if let reason = stream.unavailableReason {
                                Text(reason).font(.callout).foregroundStyle(.orange)
                            } else if let advisory = stream.advisory {
                                Text(advisory).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                    }
                }
            }
            Text("The download button saves supported MP4 and unprotected on-demand HLS sources. HLS packages play within VisionStream and cannot be exported as MP4. Automatic format detection runs during playback; you can override it in Video format settings. Finding a source does not verify native playback.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(30).frame(width: 760, height: 560)
        .onAppear {
            app.extractor.clear()
            // During provisional navigation WKWebView.url can still be the old page.
            let requested = BrowserAddress.resolve(app.browser.address) ?? app.browser.webView.url
            if let url = requested, url.scheme == "https" { address = url.absoluteString }
            addressFocused = true
            #if targetEnvironment(simulator)
            if SimulatorScenarioRunner.isConfigured {
                SimulatorScenarioRunner.finderSubmit = { address = $0; find() }
                SimulatorScenarioRunner.finderWatch = {
                    if let stream = app.extractor.streams.first(where: { $0.unavailableReason == nil }) { watch(stream.candidate) }
                }
            }
            #endif
        }
        .onDisappear {
            #if targetEnvironment(simulator)
            SimulatorScenarioRunner.finderSubmit = nil; SimulatorScenarioRunner.finderWatch = nil
            #endif
        }
        .simulatorPanel(.finder)
    }

    private func find() {
        app.extractor.find(address.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
