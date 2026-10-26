import SwiftUI

@MainActor struct VRLibraryView: View {
    let app: AppModel
    let watch: (VRLibraryStream) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        @Bindable var library = app.library
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(library.document?.title ?? "Connect a VR library").font(.title2)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut("w", modifiers: .command)
            }
            Text("Enter the website's published HereSphere library or video address. Your matching browser cookies are used; some sites require a separate player login that is not supported yet.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("https://…/heresphere", text: $address)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .focused($addressFocused)
                    .onSubmit { connect() }
                Button("Connect") { connect() }.disabled(library.isLoading)
            }
            DisclosureGroup("Connection options") {
                Toggle("Use POST to read the library", isOn: $library.usesPOST).disabled(library.isLoading)
                Text("Enable only if the site's player interface requires POST. Requests contain an empty JSON object; account and library updates are not sent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Back", systemImage: "chevron.left") { library.back(); address = library.endpoint?.absoluteString ?? address }
                    .disabled(!library.canGoBack || library.isLoading)
                if library.isLoading {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { library.cancel() }
                }
                if let host = library.endpoint?.host { Text(host).font(.caption).foregroundStyle(.secondary) }
            }
            if let error = library.errorMessage { Text(error).font(.callout).foregroundStyle(.orange) }
            if let document = library.document {
                if document.limitedAccess {
                    Text("Limited access: only entries supplied by the server are shown. These may be previews.").font(.callout).foregroundStyle(.secondary)
                }
                List {
                    ForEach(document.entries) { entry in
                        Button {
                            address = entry.url.absoluteString
                            library.connect(entry.url, browser: app.browser)
                        } label: {
                            HStack { Text(entry.title); Spacer(); Image(systemName: "chevron.right") }
                        }.disabled(library.isLoading)
                    }
                    ForEach(document.streams) { stream in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(stream.label)
                                    Text([stream.projection?.label, stream.layout?.label, stream.candidate.displaySource].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Watch in VR", systemImage: "vision.pro") {
                                    watchStream(stream)
                                }.disabled(stream.unavailableReason != nil || library.isLoading || app.playback.openingImmersive || app.playback.immersiveActive)
                                    .keyboardShortcut(stream.id == document.streams.first(where: { $0.unavailableReason == nil })?.id
                                        ? KeyboardShortcut("v", modifiers: [.command, .shift]) : nil)
                            }
                            if let reason = stream.unavailableReason { Text(reason).font(.caption).foregroundStyle(.orange) }
                        }
                    }
                    if document.entries.isEmpty && document.streams.isEmpty {
                        Text("No supported HTTPS video links were supplied. Complete the site's normal access steps or try an individual video endpoint.")
                    }
                }
            } else { Spacer() }
        }
        .padding(24).frame(width: 780, height: 640)
        .onAppear {
            address = library.endpoint?.absoluteString ?? ""; addressFocused = true
            #if targetEnvironment(simulator)
            if SimulatorScenarioRunner.isConfigured {
                SimulatorScenarioRunner.librarySubmit = { address = $0; connect() }
                SimulatorScenarioRunner.libraryWatch = { preferHLS in
                    if let stream = library.document?.streams.first(where: {
                        $0.unavailableReason == nil && (!preferHLS || $0.candidate.source.contains(".m3u8"))
                    }) { watchStream(stream) }
                }
            }
            #endif
        }
        .onDisappear {
            library.cancel()
            #if targetEnvironment(simulator)
            SimulatorScenarioRunner.librarySubmit = nil; SimulatorScenarioRunner.libraryWatch = nil
            #endif
        }
        .simulatorPanel(.library)
    }

    private func connect() {
        app.library.connect(address: address, browser: app.browser)
    }
    private func watchStream(_ stream: VRLibraryStream) { dismiss(); watch(stream) }
}
