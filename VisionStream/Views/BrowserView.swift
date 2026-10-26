import SwiftUI

@MainActor struct BrowserView: View {
    let app: AppModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var browserIsActive=false
    @State private var selectedID: String?
    @State private var showStreamSheet = false
    @State private var showLibrary = false
    @State private var showFinder = false
    @State private var showAddressSheet = false
    @State private var addressDraft = ""
    @State private var showDetails = false
    @State private var showDownloads = false
    @State private var pendingDownload: MediaCandidate?
    @State private var showFormat = false
    @State private var showHelp = false
    @State private var showBookmarks = false
    @State private var showSettings = false
    @State private var confirmClearData = false
    @FocusState private var addressFocused: Bool
    @FocusState private var streamAddressFocused: Bool
    @State private var streamAddress = ""
    @State private var dialogText = ""
    @State private var operation = UUID()
    @State private var preparingTask: Task<Void, Never>?

    private var selected: MediaCandidate? {
        playableCandidates.first { $0.id == selectedID } ?? MediaCandidate.preferredForPlayback(in: playableCandidates)
    }

    private var playableCandidates: [MediaCandidate] { AutomaticPlayback.actionable(in:app.browser.candidates) }
    private var videoBarVisible: Bool { !playableCandidates.isEmpty || app.playback.isPreparing || app.playback.openingImmersive }

    var body: some View {
        @Bindable var browser = app.browser
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { browser.back() } label: { Image(systemName: "chevron.left") }.disabled(!browser.canGoBack).accessibilityLabel("Back")
                Button { browser.forward() } label: { Image(systemName: "chevron.right") }.disabled(!browser.canGoForward).accessibilityLabel("Forward")
                Button { browser.refresh() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh")
                    .keyboardShortcut("r", modifiers: .command)
                Button {
                    openAddress()
                } label: {
                    Text(browser.address.isEmpty ? "Enter website address" : browser.address)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("Edit website address")
                .keyboardShortcut("l", modifiers: .command)
                .frame(minWidth: 220, maxWidth: .infinity)
                Button("Home", systemImage: "house") { browser.showStartPage() }.labelStyle(.iconOnly)
                Button("Bookmarks", systemImage: "bookmark") { showBookmarks = true }.labelStyle(.iconOnly)
                Button("Downloads", systemImage: "arrow.down.circle") { showDownloads = true }
                Menu {
                    Button("Open video link", systemImage: "link") { showStreamSheet = true }.keyboardShortcut("o", modifiers: .command)
                    Button("Find video sources",systemImage:"magnifyingglass") { showFinder=true }.keyboardShortcut("f",modifiers:[.command,.shift])
                    Button("Playback details",systemImage:"info.circle") { showDetails=true }.keyboardShortcut("d",modifiers:[.command,.shift])
                    Button("Connect VR library", systemImage: "rectangle.stack") { showLibrary = true }.keyboardShortcut("l", modifiers: [.command, .shift])
                    Divider()
                    Button("Browser settings", systemImage: "gearshape") { showSettings = true }
                    Button("How to watch", systemImage: "questionmark.circle") { showHelp = true }
                    Button("Clear website data…", systemImage: "hand.raised", role: .destructive) { confirmClearData = true }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Browser options")
            }.padding()
            if browser.isLoading { ProgressView().progressViewStyle(.linear) }
            BrowserWebView(browser: browser)
            if browser.message != nil || app.playback.errorMessage != nil {
                VStack(alignment:.leading,spacing:8) {
                    if let message=browser.message { Text(message).foregroundStyle(.orange) }
                    if let error=app.playback.errorMessage { Text(error).foregroundStyle(.orange) }
                }.font(.callout).frame(maxWidth:.infinity,alignment:.leading).padding()
            }
            if videoBarVisible {
            VStack(alignment: .leading, spacing: 10) {
                if let hint = PlaybackDiagnostics.webFailureHint(selected?.webMedia?.errorCode) {
                    Text(hint).font(.callout).foregroundStyle(.orange)
                }
                HStack {
                    if playableCandidates.isEmpty {
                        Text("Start a video on the page to detect its source.").foregroundStyle(.secondary)
                    } else {
                        Picker("Video", selection: Binding(get: { selected?.id ?? "" }, set: { selectedID = $0 })) {
                            ForEach(playableCandidates) { media in
                                Text("\(media.title.prefix(65)) · \(media.displaySource)").tag(media.id)
                            }
                        }.frame(maxWidth: 620)
                    }
                    Spacer()
                    Menu("Video tools", systemImage: "wand.and.stars") {
                        Button("Scan page again", systemImage: "arrow.clockwise") { browser.scan() }
                        Button("Find more sources", systemImage: "magnifyingglass") { showFinder = true }
                        Button(app.saveInProgress ? "Add to queue" : "Save video", systemImage: "arrow.down.circle") { if let selected { download(selected) } }
                            .disabled(selected == nil || app.saveQueueFull || selected.map { !HLSOfflineLibrary.accepts($0) && DownloadModel.unavailableReason($0) != nil } == true)
                        Button("Playback details", systemImage: "info.circle") { showDetails = true }
                    }
                    if app.playback.isPreparing || app.playback.openingImmersive {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { cancel() }
                    } else {
                        Button("Watch in VR", systemImage: "vision.pro") { if let selected { watch(selected) } }
                            .keyboardShortcut("v", modifiers: [.command, .shift])
                            .buttonStyle(.borderedProminent)
                            .disabled(selected?.compatibility != .candidate || app.playback.openingImmersive || app.playback.immersiveActive)
                    }
                }
                if let reason = selected?.compatibility.reason { Text(reason).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button { showFormat.toggle() } label: {
                        Label(app.playback.automaticallyDetectFormat ? "Format: Automatic" : "Format: \(app.playback.presentation.label) · \(app.playback.layout.label)", systemImage: "slider.horizontal.3")
                    }.popover(isPresented: $showFormat) { browserFormatSettings.padding(24).frame(width: 510) }
                    Text(app.playback.automaticallyDetectFormat ? "Automatic checks video metadata, labels and image matches. You can adjust the format at any time." : "Manual format is on. Choose Automatic to detect the next video.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if app.downloads.isDownloading || app.hlsDownloads.active {
                        Button(app.queuedSaves.isEmpty ? "Downloading…" : "Downloading · \(app.queuedSaves.count) waiting", systemImage: "arrow.down.circle") { showDownloads = true }
                    }
                }
            }.padding().simulatorPanel(.videoBar)
            }
        }
        .sheet(isPresented: $showAddressSheet) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Website address").font(.title2)
                TextField("https://example.com", text: $addressDraft)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).submitLabel(.go).focused($addressFocused)
                    .onSubmit { navigateToDraft() }
                HStack {
                    Button("Cancel") { showAddressSheet = false }.keyboardShortcut("w", modifiers: .command)
                    Spacer()
                    Button("Go") { navigateToDraft() }
                        .buttonStyle(.borderedProminent)
                        .disabled(BrowserAddress.resolve(addressDraft) == nil)
                }
            }.padding(30).frame(width: 620).simulatorPanel(.address)
                .onAppear { addressFocused = true }
        }
        .sheet(isPresented: $showDetails) {
            PlaybackDetailsView(app:app).simulatorPanel(.details)
        }
        .sheet(isPresented: $showStreamSheet) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Open video link").font(.title2)
                Text("Paste a direct HTTPS MP4 or HLS video link. Video format is detected automatically unless you choose a manual format.").foregroundStyle(.secondary)
                TextField("https://…/video.mp4", text: $streamAddress)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($streamAddressFocused)
                HStack {
                    Button("Cancel") { showStreamSheet = false }.keyboardShortcut("w", modifiers: .command)
                    Spacer()
                    Button("Watch in VR") {
                        watchManualStream()
                    }.buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(app.playback.openingImmersive || app.playback.immersiveActive)
                }
                if let error = app.playback.errorMessage { Text(error).font(.callout).foregroundStyle(.orange) }
            }.padding(30).frame(width: 620).onAppear { streamAddressFocused = true }.simulatorPanel(.stream)
        }
        .sheet(isPresented: $showDownloads) {
            DownloadsView(app: app, downloads: app.downloads, hls: app.hlsDownloads, watch: { video in showDownloads = false; watchSaved(video) }, watchHLS: { video in
                showDownloads = false
                watch(MediaCandidate(id: video.id.uuidString, source: "", title: video.name), savedHLS: video)
            })
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(preferences: app.browser.preferences,
                          page: app.browser.isLoading ? nil : app.browser.webView.url,
                          title: app.browser.webView.title ?? "Website", open: { app.browser.open($0) })
        }
        .sheet(isPresented: $showSettings) { BrowserSettingsView(app:app,preferences: app.browser.preferences, currentPage: app.browser.webView.url) }
        .sheet(isPresented: $showHelp) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Watch in VisionStream").font(.title2.bold())
                Label("Open a website and start its video.", systemImage: "1.circle")
                Label("Press the website’s Play button to open compatible video in VR.", systemImage: "2.circle")
                Label("Use Video format if the image looks doubled or distorted.", systemImage: "3.circle")
                Text("Automatic checks supported VR metadata, clear source labels and repeated image matches. Unidentified videos stay on a flat screen. Image detection is an estimate; if the view is wrong, choose Side by side or Top bottom and VR180 or VR360 yourself.").foregroundStyle(.secondary)
                Text("Video tools can find more sources or save supported videos. Downloads lets you watch saved videos offline. Website VR/motion setup affects only the website’s player.").foregroundStyle(.secondary)
                Text("Automatic opening can be turned off in Browser settings. Autoplay previews do not trigger it. If a website’s Play control is not recognised, choose Watch in VR when the video bar appears; Find video sources and Playback details are always in Browser options.").font(.callout).foregroundStyle(.secondary)
                Text("Recenter gives you three seconds to look where the video should face, including while lying down. Position lets you adjust tilt or reset the video upright.").font(.callout).foregroundStyle(.secondary)
                Text("Some websites require their own player or login and cannot hand a video to VisionStream.").font(.callout).foregroundStyle(.secondary)
                Button("Got it") { showHelp = false }.buttonStyle(.borderedProminent)
            }.padding(30).frame(width: 620)
        }
        .confirmationDialog("Clear website data?", isPresented: $confirmClearData, titleVisibility: .visible) {
            Button("Clear website data", role: .destructive) { Task { await app.browser.clearWebsiteData() } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This signs you out of websites and clears their cookies and stored data. Your downloaded videos and bookmarks stay on this headset.") }
        .sheet(isPresented: $showLibrary) {
            VRLibraryView(app: app, watch: watchLibraryStream)
        }
        .sheet(isPresented: $showFinder, onDismiss: {
            app.extractor.clear()
            if let media = pendingDownload { pendingDownload = nil; download(media) }
        }) {
            VideoFinderView(app: app, watch: watchFoundStream, download: download)
        }
        .onChange(of: showDownloads) { _, visible in app.history.record(.controls,labels:["action":visible ? "downloads-opened":"downloads-closed"]) }
        .onChange(of: showFinder) { _, visible in app.history.record(.controls,labels:["action":visible ? "finder-opened":"finder-closed"]) }
        .onChange(of: showLibrary) { _, visible in app.history.record(.controls,labels:["action":visible ? "library-opened":"library-closed"]) }
        .onChange(of: showSettings) { _, visible in app.history.record(.controls,labels:["action":visible ? "settings-opened":"settings-closed"]) }
        .onChange(of: showBookmarks) { _, visible in app.history.record(.controls,labels:["action":visible ? "bookmarks-opened":"bookmarks-closed"]) }
        .onChange(of: scenePhase, initial: true) { _, phase in observeScene(phase) }
        .onAppear { app.browserWindowVisible = true; startBrowser() }
        .onDisappear { app.browserWindowVisible = false; browserIsActive = false; if !app.playback.immersiveActive && !app.playback.openingImmersive { app.browser.onUserPlayback=nil;cancel() } }
        .onChange(of: browser.dialog?.id) { _, _ in dialogText = browser.dialog?.defaultText ?? "" }
        .alert("Website dialog", isPresented: Binding(get: { browser.dialog != nil }, set: { if !$0 { browser.finishDialog(nil) } })) {
            if let dialog = browser.dialog {
                if dialog.kind == .prompt { TextField("Response", text: $dialogText) }
                Button("OK") { browser.finishDialog(dialog.kind == .prompt ? dialogText : "confirmed") }
                if dialog.kind != .alert { Button("Cancel", role: .cancel) { browser.finishDialog(nil) } }
            }
        } message: { Text(browser.dialog?.message ?? "") }
        .simulatorPanel(.browser)
    }

    private var browserFormatSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Video format").font(.title3.bold())
            Toggle("Detect automatically", isOn: Binding(get: { app.playback.automaticallyDetectFormat }, set: {
                if $0 { app.playback.enableAutomaticFormat() } else { app.playback.manualFormat() }
            }))
            Picker("View", selection: Binding(get: { app.playback.presentation }, set: { app.playback.manualFormat(); app.playback.presentation = $0 })) {
                ForEach(VideoPresentation.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Image layout", selection: Binding(get: { app.playback.layout }, set: { app.playback.manualFormat(); app.playback.layout = $0 })) {
                ForEach(StereoLayout.allCases) { Text($0.label).tag($0) }
            }
            Text("Two images next to each other? Choose Side by side. The view selects a flat screen or a panorama; the image layout selects each eye’s part of the video.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func download(_ media: MediaCandidate) {
        if showFinder { pendingDownload = media; showFinder = false; return }
        let contextual = media.withBrowserFormatContext(page: BrowserAddress.resolve(app.browser.address), title: app.browser.webView.title ?? "", candidates: app.browser.candidates)
        showDownloads = true
        Task { @MainActor [app] in
            guard let url = URL(string: contextual.source) else { return }
            let cookies = await app.browser.cookies(for: url)
            let agent = await app.browser.playbackUserAgent()
            app.enqueueSave(contextual,cookies:cookies,userAgent:agent,cookieProvider: { [weak app] in await app?.browser.cookies(for:$0) ?? [] })
        }
    }
    private func watchSaved(_ video: SavedVideo) {
        watch(MediaCandidate(id: video.id.uuidString, source: "", title: video.name), saved: video)
    }

    private func observeScene(_ phase: ScenePhase) {
        browserIsActive = phase == .active
        app.history.record(.lifecycle,context:app.browser.diagnosticContext,labels:["phase":phase == .active ? "browser-active" : (phase == .background ? "browser-background":"browser-inactive")])
        #if targetEnvironment(simulator)
        switch phase {
        case .active: SimulatorTestMonitor.browserScenePhase = "active"
        case .background: SimulatorTestMonitor.browserScenePhase = "background"
        default: SimulatorTestMonitor.browserScenePhase = "inactive"
        }
        #endif
    }
    private func startBrowser() {
        app.browser.onUserPlayback = { media in
            guard browserIsActive, !showAddressSheet, !showStreamSheet, !showLibrary, !showFinder,
                  !showDownloads, !showDetails, !showBookmarks, !showSettings, !showHelp, !confirmClearData,
                  app.browser.dialog == nil, !app.playback.isPreparing, !app.playback.openingImmersive,
                  !app.playback.immersiveActive else { return }
            selectedID=media.id
            watch(media)
        }
        #if targetEnvironment(simulator)
        if SimulatorScenarioRunner.isRequested {
            guard SimulatorScenarioRunner.isConfigured else { app.browser.showStartPage(); return }
            SimulatorScenarioRunner.downloadAction = download
            SimulatorScenarioRunner.openDownloads = { showDownloads = true }
            SimulatorScenarioRunner.openBookmarks = { showBookmarks = true }
            SimulatorScenarioRunner.openSettings = { showSettings = true }
            SimulatorScenarioRunner.bindBrowser(
                app: app, watch: { watch($0) }, openAddress: openAddress,
                submitAddress: { addressDraft = $0; navigateToDraft() },
                openStream: { showStreamSheet = true }, submitStream: { streamAddress = $0; watchManualStream() },
                openFinder: { showFinder = true }, openLibrary: { showLibrary = true },
                openDetails: { showDetails = true }, closeSheets: {
                    showAddressSheet = false; showStreamSheet = false; showFinder = false; showLibrary = false; showDetails = false; showDownloads = false; showBookmarks = false; showSettings = false
                }, cancel: cancel)
            return
        }
        #endif
        app.browser.startIfNeeded()
    }

    private func cancel() {
        operation = UUID(); preparingTask?.cancel(); preparingTask = nil
        app.playback.cancelPreparation()
    }

    private func navigateToDraft() {
        guard let url = BrowserAddress.resolve(addressDraft) else { return }
        showAddressSheet = false
        app.browser.open(url)
    }

    private func openAddress() { addressDraft = app.browser.address; showAddressSheet = true }
    private func watchManualStream() {
        let media = MediaCandidate(id: UUID().uuidString, source: streamAddress.trimmingCharacters(in: .whitespacesAndNewlines))
        if let reason = media.compatibility.reason { app.playback.errorMessage = reason }
        else { showStreamSheet = false; watch(media) }
    }
    private func watchFoundStream(_ media: MediaCandidate) {
        let contextual = media.withBrowserFormatContext(
            page: BrowserAddress.resolve(app.browser.address) ?? app.browser.webView.url,
            title: app.browser.webView.title ?? "", candidates: app.browser.candidates)
        showFinder = false; watch(contextual)
    }
    private func watchLibraryStream(_ stream: VRLibraryStream) {
        guard stream.unavailableReason == nil, let projection = stream.projection, let layout = stream.layout else { return }
        app.playback.manualFormat()
        app.playback.projection = projection; app.playback.flatScreen = false
        app.playback.layout = layout; app.playback.swapEyes = false; app.playback.flipY = false
        watch(stream.candidate)
    }

    private func watch(_ media: MediaCandidate, saved: SavedVideo? = nil, savedHLS: SavedHLSVideo? = nil) {
        guard !app.playback.openingImmersive, !app.playback.immersiveActive else { return }
        cancel()
        let token = UUID(); operation = token
        let navigationVersion = app.browser.navigationVersion
        // Reserve the transition before awaiting cookies to prevent double launches.
        app.playback.openingImmersive = true
        preparingTask = Task { @MainActor in
            defer { app.playback.openingImmersive = false }
            let ready: Bool
            if let saved {
                ready = await app.playback.prepareSavedVideo(saved, store: app.downloads.store)
            } else if let savedHLS {
                ready = await app.playback.prepareSavedHLS(savedHLS, store: app.hlsDownloads.store)
            } else {
                guard let url = URL(string: media.source) else { return }
                let cookies = await app.browser.cookies(for: url)
                guard !Task.isCancelled, operation == token, app.browser.navigationVersion == navigationVersion else { return }
                let userAgent = await app.browser.playbackUserAgent()
                guard !Task.isCancelled, operation == token, app.browser.navigationVersion == navigationVersion else { return }
                ready = await app.playback.prepare(media, cookies: cookies, userAgent: userAgent, cookieProvider: { [weak browser = app.browser] url in await browser?.cookies(for: url) ?? [] })
            }
            guard ready, !Task.isCancelled, operation == token else { return }
            guard app.browser.navigationVersion == navigationVersion else { app.playback.stop(); return }
            guard !Task.isCancelled, operation == token, app.playback.isReady else { return }
            let result = await openImmersiveSpace(id: "video")
            // Navigation/cancellation can occur while visionOS opens the space.
            // Never hide the newer page or leave an empty immersive experience.
            guard !Task.isCancelled, operation == token,
                  app.browser.navigationVersion == navigationVersion, app.playback.isReady else {
                if case .opened = result { await dismissImmersiveSpace() }
                return
            }
            switch result {
            case .opened:
                // Keep an exit control available even if the website is slow to pause.
                // A refused/cancelled system transition must not pause the page.
                await app.browser.pausePageVideo(media)
                guard !Task.isCancelled, operation == token,
                      app.browser.navigationVersion == navigationVersion, app.playback.isReady else {
                    await dismissImmersiveSpace(); return
                }
                // The immersive view owns the controls attachment. Close this
                // window only after native readiness and normal page pausing;
                // immersive dismissal reopens the same in-memory browser.
                dismissWindow(id: "browser")
            case .userCancelled: app.playback.stop()
            case .error: app.playback.fail("visionOS could not open the immersive space. Close other immersive experiences and try again.")
            @unknown default: app.playback.fail("The immersive space is unavailable.")
            }
        }
    }
}
