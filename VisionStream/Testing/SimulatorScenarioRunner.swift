#if targetEnvironment(simulator)
import AVFoundation
import Foundation
import Darwin

/// In-process scene integration tests. These use the production form/actions and
/// real SwiftUI immersive-space environment; they are not synthetic touch or
/// keyboard events. Configuration is restricted to a local HTTPS fixture origin.
@MainActor enum SimulatorScenarioRunner {
    struct Configuration {
        let name: String
        let origin: URL
        let identifier: String
        let soakSeconds: Int
        let reviewPanel: String?
        static var current: Self? {
            return from(ProcessInfo.processInfo.environment)
        }
        static func from(_ env: [String: String]) -> Self? {
            let names: Set<String> = ["auto-play", "soak", "saved-state", "downloads", "forms", "quality", "quality4k", "controls", "controls-format", "controls-quality", "mp4", "hls", "library", "library-hls", "cancel", "unsupported", "finder", "reentry", "interrupted"]
            guard let name = env["VISIONSTREAM_SCENE_TEST"], names.contains(name),
                  let raw = env["VISIONSTREAM_TEST_ORIGIN"], let url = URL(string: raw),
                  url.scheme == "https", ["127.0.0.1", "localhost"].contains(url.host ?? ""),
                  let port = url.port, (1...65535).contains(port), url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil, ["", "/"].contains(url.path),
                  let identifier = env["VISIONSTREAM_SCENE_TEST_ID"], UUID(uuidString: identifier) != nil else { return nil }
            if name == "finder", env["VISIONSTREAM_TEST_PUBLIC_EXTRACTOR"] != "1" { return nil }
            let review = env["VISIONSTREAM_TEST_REVIEW_PANEL"]
            if let review { guard name == "forms", ["address", "stream", "finder", "library", "details", "downloads", "bookmarks", "settings"].contains(review) else { return nil } }
            let seconds = Int(env["VISIONSTREAM_TEST_SOAK_SECONDS"] ?? "600") ?? 0
            guard name != "soak" || (60...1800).contains(seconds) else { return nil }
            return .init(name: name, origin: url, identifier: identifier, soakSeconds: seconds, reviewPanel: review)
        }
    }
    static var isRequested: Bool { ProcessInfo.processInfo.environment["VISIONSTREAM_SCENE_TEST"] != nil }
    static var isConfigured: Bool { Configuration.current != nil }
    struct ControlActions {
        let format: (Bool) -> Void
        let quality: (Bool) -> Void
        let selectQuality: (PlaybackQuality) -> Void
        let presentation: (VideoPresentation) -> Void
        let layout: (StereoLayout) -> Void
        let automatic: (Bool) -> Void
        let position: (Bool) -> Void
        let tilt: (Double) -> Void
        let recenter: () -> Void
        let upright: () -> Void
    }
    static var controlActions: ControlActions?
    static var returnAction: (() async -> Void)?
    static var rendererBounds: (() -> [Double]?)?
    static var rendererPose: (() -> [Double]?)?
    static var openBookmarks: (() -> Void)?
    static var openSettings: (() -> Void)?
    static var bookmarkSave: ((String) -> Void)?
    static var bookmarkOpen: (() -> Void)?
    static var diagnosticsMode: ((Bool) -> Void)?
    static var diagnosticsDelete: (() -> Void)?
    static var restoreMode: ((BrowserRestoration) -> Void)?
    static var downloadWatch: (() -> Void)?
    static var downloadAction: ((MediaCandidate) -> Void)?
    static var openDownloads: (() -> Void)?
    static var finderSubmit: ((String) -> Void)?
    static var finderWatch: (() -> Void)?
    static var librarySubmit: ((String) -> Void)?
    static var libraryWatch: ((Bool) -> Void)?
    private static var watchAction: ((MediaCandidate) -> Void)?
    private static var openAddress: (() -> Void)?
    private static var submitAddress: ((String) -> Void)?
    private static var openStream: (() -> Void)?
    private static var submitStream: ((String) -> Void)?
    private static var openFinder: (() -> Void)?
    private static var openLibrary: (() -> Void)?
    private static var openDetails: (() -> Void)?
    private static var closeSheets: (() -> Void)?
    private static var cancelAction: (() -> Void)?
    private static var started = false
    private static var checks: [[String: Any]] = []
    private static var configuration: Configuration?
    private static var startedAt = Date()
    private static var soakMetrics: [String: Any] = [:]
    private enum Failure: Error { case check(String) }

    static func bindBrowser(app: AppModel, watch: @escaping (MediaCandidate) -> Void,
                            openAddress: @escaping () -> Void, submitAddress: @escaping (String) -> Void,
                            openStream: @escaping () -> Void, submitStream: @escaping (String) -> Void,
                            openFinder: @escaping () -> Void, openLibrary: @escaping () -> Void,
                            openDetails: @escaping () -> Void, closeSheets: @escaping () -> Void,
                            cancel: @escaping () -> Void) {
        guard let config = Configuration.current else { return }
        self.watchAction = watch; self.openAddress = openAddress; self.submitAddress = submitAddress
        self.openStream = openStream; self.submitStream = submitStream; self.openFinder = openFinder
        self.openLibrary = openLibrary; self.openDetails = openDetails; self.closeSheets = closeSheets
        cancelAction = cancel
        guard !started else { return }
        started = true; configuration = config; startedAt = Date()
        Task { @MainActor in
            app.setDiagnosticsEnabled(true) // Explicit local test opt-in; fresh customer installs stay off.
            app.playback.player.isMuted = true
            write(status: "running", app: app)
            do {
                try await run(config, app: app)
                write(status: "passed", app: app)
            } catch {
                let reason: String
                if let failure = error as? Failure {
                    switch failure { case let .check(code): reason = code }
                } else { reason = "unexpected-error" }
                write(status: "failed", app: app, failure: reason)
            }
        }
    }

    private static func run(_ config: Configuration, app: AppModel) async throws {
        try await wait("browser-mounted") { mounted(.browser) && app.browser.webView.window != nil }
        if config.name == "forms" { try await forms(config, app: app); return }
        if config.name == "auto-play" { try await automaticPlayback(config,app:app);return }
        let path = ["quality4k", "soak"].contains(config.name) ? "quality-4k.html" : (["quality", "quality4k", "soak"].contains(config.name) || config.name.hasPrefix("controls")) ? "quality.html" : ["mp4", "reentry", "interrupted"].contains(config.name) ? "automation-mp4" : (config.name == "hls" ? "automation-hls" : "empty-test")
        // Submit through the actual address form action rather than restoring a
        // user's saved page or asking an external UI tool to type while locked.
        openAddress?()
        try await wait("address-mounted") { mounted(.address) }
        submitAddress?(config.origin.appendingPathComponent(path).absoluteString)
        try await wait("page-loaded", seconds: 45) { !mounted(.address) && app.browser.pageHTTPStatus == 200 && !app.browser.isLoading }
        record("address-form-and-page", app: app)
        switch config.name {
        case "saved-state":
            openSettings?(); try await wait("settings-mounted") { mounted(.settings) && restoreMode != nil }
            restoreMode?(.page)
            try require(app.browser.preferences.restoration == .page && app.browser.preferences.restoredURL?.path == "/empty-test", "restore-exact-current-page")
            record("settings-exact-page", app: app)
            closeSheets?(); try await wait("settings-dismissed") { !mounted(.settings) }
            openBookmarks?(); try await wait("bookmarks-mounted") { mounted(.bookmarks) && bookmarkSave != nil }
            bookmarkSave?("CC0 test bookmark")
            try require(app.browser.preferences.bookmarks.count == 1, "bookmark-created")
            record("bookmark-save-action", app: app)
            closeSheets?(); try await wait("bookmarks-dismissed") { !mounted(.bookmarks) }
            openBookmarks?(); try await wait("bookmarks-reopened") { mounted(.bookmarks) && bookmarkOpen != nil }
            bookmarkOpen?(); try await wait("bookmark-navigation") { !mounted(.bookmarks) && !app.browser.isLoading }
            record("bookmark-reopen-and-navigation", app: app)
            openSettings?(); try await wait("settings-remounted") { mounted(.settings) && restoreMode != nil }
            restoreMode?(.website)
            try require(app.browser.preferences.restoredURL?.path == "/" && app.browser.preferences.restoredURL?.query == nil, "restoration-privacy-reduced")
            restoreMode?(.home); try require(app.browser.preferences.restoredURL == nil, "restoration-home")
            restoreMode?(.website)
            closeSheets?(); try await wait("settings-closed") { !mounted(.settings) }
            if let bookmark = app.browser.preferences.bookmarks.first { app.browser.preferences.removeBookmark(bookmark) }
            record("settings-reduce-retention-and-home", app: app)
            return
        case "downloads":
            let media = MediaCandidate(id: "download", source: config.origin.appendingPathComponent("delayed/controls-demo.mp4").absoluteString,
                title: "CC0 VR180 SBS", formatHint: .init(projection: .vr180, layout: .sideBySide, evidence: .metadata))
            downloadAction?(media)
            try await wait("downloads-sheet") { mounted(.downloads) }
            downloadAction?(.init(id:"waiting-fixture",source:config.origin.appendingPathComponent("vr180-sbs.mp4").absoluteString,title:"CC0 queued video"))
            try await wait("waiting-save-listed") { app.queuedSaves.count==1 }
            try require(app.saveInProgress,"original-save-still-active")
            record("second-save-queued-on-mounted-downloads-sheet",app:app)
            if let waiting=app.queuedSaves.first { app.removeQueuedSave(waiting.id) }
            try require(app.queuedSaves.isEmpty,"waiting-save-removed")
            record("waiting-save-removal-keeps-active-transfer",app:app)
            try await wait("download-saved", seconds: 30) { !app.downloads.isDownloading && app.downloads.videos.count == 1 }
            try require(app.downloads.message == nil && app.downloads.videos[0].bytes > 0, "download-complete")
            record("download-saved-and-listed", app: app)
            closeSheets?(); try await wait("downloads-dismissed") { !mounted(.downloads) }
            openDownloads?(); try await wait("downloads-reopened") { mounted(.downloads) && downloadWatch != nil }
            record("downloads-close-and-reopen", app: app)
            downloadWatch?()
        case "cancel":
            let media = MediaCandidate(id: "delayed", source: config.origin.appendingPathComponent("delayed/controls-demo.mp4").absoluteString)
            watchAction?(media)
            try await wait("preparing-delayed-stream") { app.playback.isPreparing }
            cancelAction?()
            try await wait("cancelled-without-space") { !app.playback.isPreparing && !app.playback.openingImmersive && !app.playback.immersiveActive }
            try require(app.playback.failureReason == .cancelled && app.playback.decodedWidth == 0, "cancel-releases-preparation")
            record("cancel-releases-preparation", app: app); return
        case "unsupported":
            watchAction?(MediaCandidate(id: "unsupported", source: "blob:" + config.origin.absoluteString + "/fixture"))
            try await wait("unsupported-rejected") { app.playback.failureReason == .unsupportedCandidate && !app.playback.openingImmersive }
            try require(!app.playback.immersiveActive && !app.playback.isReady, "unsupported-no-space")
            record("unsupported-no-space", app: app); return
        case "library", "library-hls":
            app.browser.open(config.origin.appendingPathComponent("auth-test"))
            try await wait("cookie-page", seconds: 20) { app.browser.webView.url?.path == "/auth-test" && app.browser.pageHTTPStatus == 200 && !app.browser.isLoading }
            openLibrary?()
            try await wait("library-mounted") { mounted(.library) && librarySubmit != nil }
            librarySubmit?(config.origin.appendingPathComponent("auth/library/vr180-sbs").absoluteString)
            try await wait("library-loaded", seconds: 20) { !app.library.isLoading && (app.library.document?.streams.count ?? 0) == 2 }
            record("cookie-authenticated-library", app: app)
            libraryWatch?(config.name == "library-hls")
        case "finder":
            openFinder?()
            try await wait("finder-mounted") { mounted(.finder) && finderSubmit != nil }
            // Optional, fixed public-domain NASA sample. No site URLs, browser
            // credentials or arbitrary external destinations are accepted here.
            finderSubmit?("https://svs.gsfc.nasa.gov/vis/a010000/a014500/a014576/14576_BHPlunge_360_FINAL_1080.mp4")
            try await wait("finder-resolved", seconds: 75) { !app.extractor.isLoading && !app.extractor.streams.isEmpty }
            record("embedded-public-finder", app: app)
            finderWatch?()
        default:
            try await wait("web-inline-playing", seconds: 20) {
                app.browser.candidates.contains { $0.width > 0 && $0.webMedia?.readyState == 4 && $0.webMedia?.paused == false }
            }
            guard let media = MediaCandidate.preferredForPlayback(in: app.browser.candidates) else { throw Failure.check("no-direct-candidate") }
            if ["quality", "quality4k", "soak"].contains(config.name) || config.name.hasPrefix("controls") {
                try require(media.formatHint?.projection == .vr180 && media.formatHint?.layout == .sideBySide, "dom-format-metadata")
            }
            record("web-inline-playing", app: app)
            watchAction?(media)
        }
        for iteration in 0..<(config.name == "reentry" ? 2 : 1) {
            if iteration > 0 {
                guard let media = MediaCandidate.preferredForPlayback(in: app.browser.candidates) else { throw Failure.check("reentry-no-candidate") }
                watchAction?(media)
            }
            try await wait("native-space-and-frame", seconds: 45) {
                app.playback.immersiveActive && app.playback.decodedWidth > 0 && app.playback.isPlaying &&
                    mounted(.playback) && mounted(.immersive) && returnAction != nil && rendererBounds?() != nil
            }
            try await wait("browser-window-dismissed") { !mounted(.browser) }
            if config.name.hasPrefix("library") {
                try require(app.playback.presentation == .vr180 && app.playback.layout == .sideBySide, "library-projection-layout")
            }
            if ["quality", "quality4k", "soak"].contains(config.name) || config.name.hasPrefix("controls") {
                let width = ["quality4k", "soak"].contains(config.name) ? 3840 : 1440, height = ["quality4k", "soak"].contains(config.name) ? 1920 : 720
                try await wait("highest-decoded-resolution") { app.playback.decodedWidth == width && app.playback.decodedHeight == height }
                try require(app.playback.presentation == .vr180 && app.playback.layout == .sideBySide && app.playback.automaticallyDetectFormat,
                            "automatic-vr180-sbs")
                record("highest-resolution-and-automatic-format", app: app)
            }
            if config.name == "downloads" {
                try require(app.playback.presentation == .vr180 && app.playback.layout == .sideBySide &&
                    (app.playback.player.currentItem?.asset as? AVURLAsset)?.url.isFileURL == true, "offline-file-and-format")
                record("saved-file-offline-and-automatic-format", app: app)
            }
            record("real-immersive-space-native-frames", app: app)
            if config.name == "interrupted" { return }
            if config.name == "soak" { try await soak(config, app: app) }
            if config.name.hasPrefix("controls") {
                try await playbackPopovers(config, app: app)
                if config.name != "controls" { return }
            }
            if config.name == "finder" {
                try await wait("public-spherical-metadata", seconds: 8) { app.playback.presentation == .vr360 && app.playback.layout == .mono }
                try require(app.playback.decodedWidth == 2160 && app.playback.decodedHeight == 1080, "public-source-resolution")
                record("public-source-resolution-and-automatic-vr360", app: app)
            }
            try await transportAndModes(app: app)
            guard let returnAction else { throw Failure.check("missing-return-control-action") }
            await returnAction()
            try await wait("browser-restored", seconds: 20) {
                !app.playback.immersiveActive && !app.playback.isReady && app.browser.webView.window != nil && mounted(.browser) && ["active", "inactive"].contains(SimulatorTestMonitor.browserScenePhase) && !mounted(.playback)
            }
            try require(rendererBounds?() == nil, "renderer-released-on-exit")
            record("real-exit-and-browser-restoration", app: app)
            if config.name == "downloads", let saved = app.downloads.videos.first {
                app.downloads.remove(saved)
                try require(app.downloads.videos.isEmpty && app.downloads.store.file(for: saved) == nil, "download-deleted")
                record("saved-file-deletion", app: app)
            }
        }
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { value in
            value.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    private static func soak(_ config: Configuration, app: AppModel) async throws {
        let playback = app.playback, start = Date(), firstFrames = SimulatorTestMonitor.framesReceived
        var samples = 0, peak: UInt64 = 0, baseline: UInt64 = 0, nextControl = 20.0, nextQuality = 60.0
        while Date().timeIntervalSince(start) < Double(config.soakSeconds) {
            let elapsed = Date().timeIntervalSince(start)
            if playback.elapsed > max(1, playback.duration - 2) || !playback.isPlaying {
                playback.seek(to: 0); try await wait("soak-loop-seek") { !playback.isSeeking }; playback.play()
            }
            let frames = SimulatorTestMonitor.framesReceived
            try await Task.sleep(for: .seconds(2))
            try require(playback.isReady && playback.errorMessage == nil && SimulatorTestMonitor.framesReceived > frames, "soak-continued-decoding")
            if elapsed >= nextControl {
                playback.pause(); playback.seek(to: 1)
                try await wait("soak-control-seek") { !playback.isSeeking }
                controlActions?.presentation(.screen); controlActions?.layout(.mono)
                try await Task.sleep(for: .milliseconds(150))
                controlActions?.automatic(true); playback.play(); nextControl += 20
            }
            if elapsed >= nextQuality {
                let quality: PlaybackQuality = playback.quality == .highest ? .adaptive : .highest
                playback.changeQuality(quality)
                try await wait("soak-quality-reprepare", seconds: 35) {
                    playback.isReady && playback.decodedWidth > 0 && !playback.isPreparing && playback.qualityStatus == (quality == .highest ? "Highest selected" : "Adaptive")
                }
                playback.play(); nextQuality += 60
            }
            let resident = residentBytes(); peak = max(peak, resident); samples += 1
            if baseline == 0, elapsed >= 30 { baseline = resident }
            soakMetrics = ["requestedSeconds": config.soakSeconds, "elapsedSeconds": Date().timeIntervalSince(start), "samples": samples,
                           "framesReceived": SimulatorTestMonitor.framesReceived - firstFrames, "residentBytes": resident, "peakResidentBytes": peak,
                           "baselineResidentBytes": baseline, "scope": "Simulator process resident memory; not physical GPU/thermal acceptance"]
            if samples % 5 == 0 { write(status: "running", app: app) }
        }
        let final = residentBytes()
        try require(baseline > 0 && final <= baseline * 2 + 256 * 1024 * 1024, "soak-resident-memory-bound")
        if playback.quality != .highest { playback.changeQuality(.highest) }
        try await wait("soak-final-highest", seconds: 35) { playback.isReady && playback.decodedWidth == 3840 && playback.decodedHeight == 1920 && playback.qualityStatus == "Highest selected" }
        playback.play(); try await wait("soak-final-resume") { playback.isPlaying }
        record("sustained-decoding-controls-quality-and-memory", app: app)
    }

    private static func playbackPopovers(_ config: Configuration, app: AppModel) async throws {
        guard let controls = controlActions else { throw Failure.check("controls-not-bound") }
        let playback = app.playback
        playback.pause()
        if config.name == "controls-quality" {
            controls.quality(true); try await wait("quality-popover-mounted") { mounted(.quality) }
            record("quality-popover-mounted", app: app); return
        }
        if config.name == "controls" {
            controls.position(true); try await wait("position-popover-mounted") { mounted(.position) }
            record("position-popover-mounted", app: app)
            controls.tilt(30)
            try await wait("tilt-applied-to-renderer") {
                guard let pose = rendererPose?() else { return false }
                return abs(pose[0] - sin(Double.pi / 12)) < 0.001 && abs(pose[3] - cos(Double.pi / 12)) < 0.001
            }
            record("position-slider-rotates-real-video", app: app)
            controls.upright()
            try await wait("upright-applied-to-renderer") { playback.viewingTilt == 0 && abs(rendererPose?()?.first ?? 1) < 0.001 }
            record("position-reset-upright", app: app)
            controls.recenter()
            try await wait("delayed-recenter-complete",seconds:8) { playback.recenterCountdown == nil && !playback.recenterUpright }
            try await wait("position-popover-dismissed") { !mounted(.position) }
            record("delayed-recenter-and-position-dismiss", app: app)
        }
        controls.format(true); try await wait("format-popover-mounted") { mounted(.format) }
        record("format-popover-mounted", app: app)
        if config.name == "controls-format" { return }
        controls.presentation(.screen); controls.layout(.topBottom)
        try require(!playback.automaticallyDetectFormat && playback.presentation == .screen && playback.layout == .topBottom, "manual-format-control")
        controls.automatic(true)
        try require(playback.automaticallyDetectFormat && playback.presentation == .vr180 && playback.layout == .sideBySide, "auto-format-control")
        record("format-controls-and-return-to-auto", app: app)
        controls.format(false); try await wait("format-popover-dismissed") { !mounted(.format) }
        playback.seek(to: 2); try await wait("quality-position") { !playback.isSeeking }
        for quality in [PlaybackQuality.adaptive, .highest] {
            controls.quality(true); try await wait("quality-popover-mounted") { mounted(.quality) }
            controls.selectQuality(quality)
            try await wait("quality-choice-and-new-frame", seconds: 35) {
                !mounted(.quality) && playback.isReady && !playback.isPreparing && playback.quality == quality && playback.decodedWidth > 0 && !playback.isPlaying
            }
            try require(abs(playback.player.currentTime().seconds - 2) < 0.3, "quality-keeps-paused-position")
        }
        try require(playback.decodedWidth == 1440 && playback.decodedHeight == 720, "highest-quality-control")
        record("quality-controls-reprepare-and-preserve-pause", app: app)
        playback.play(); try await wait("controls-resumed") { playback.isPlaying }
    }

    private static func transportAndModes(app: AppModel) async throws {
        let playback = app.playback
        playback.toggle()
        try await wait("paused") { !playback.isPlaying && playback.player.timeControlStatus == .paused }
        let paused = playback.player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(600))
        try require(abs(playback.player.currentTime().seconds - paused) < 0.15, "paused-clock-stable")
        record("paused-clock-stable", app: app)
        let target = min(4, playback.seekEnd / 4)
        playback.seek(to: target)
        try await wait("accurate-seek") { !playback.isSeeking && abs(playback.player.currentTime().seconds - target) < 0.2 }
        let forward = min(playback.seekEnd, target + 15)
        playback.skip(15)
        try await wait("forward-skip") { !playback.isSeeking && abs(playback.player.currentTime().seconds - forward) < 0.2 }
        let back = max(playback.seekStart, forward - 15)
        playback.skip(-15)
        try await wait("back-skip") { !playback.isSeeking && abs(playback.player.currentTime().seconds - back) < 0.2 }
        record("accurate-seek-and-both-skips", app: app)
        for presentation in VideoPresentation.allCases {
            for layout in StereoLayout.allCases {
                playback.presentation = presentation; playback.layout = layout
                let mesh: ProjectionMesh
                if presentation == .screen {
                    let eye = layout.eyeSize(width: playback.decodedWidth, height: playback.decodedHeight)
                    mesh = .screen(aspectRatio: Float(eye.width) / Float(max(1, eye.height)))
                } else { mesh = .generate(projection: playback.projection) }
                let xs = mesh.positions.map(\.x), ys = mesh.positions.map(\.y), zs = mesh.positions.map(\.z)
                let expected = [Double((xs.max() ?? 0) - (xs.min() ?? 0)), Double((ys.max() ?? 0) - (ys.min() ?? 0)), Double((zs.max() ?? 0) - (zs.min() ?? 0))]
                try await wait("renderer-mode-" + presentation.rawValue + "-" + layout.rawValue) {
                    guard let actual = rendererBounds?(), actual.count == 3 else { return false }
                    return zip(actual, expected).allSatisfy { abs($0.0 - $0.1) < 0.02 }
                }
            }
        }
        record("real-renderer-nine-projection-layout-bindings", app: app)
        playback.swapEyes = true; playback.flipY = true
        let previousRecenter = playback.recenterID
        playback.recenter()
        try require(playback.recenterID == previousRecenter + 1, "recenter-request")
        record("eye-flags-and-recenter-request", app: app)
        playback.swapEyes = false; playback.flipY = false; playback.presentation = .screen; playback.layout = .mono
        playback.toggle()
        let before = playback.player.currentTime().seconds
        try await wait("resumed-clock") { playback.isPlaying && playback.player.currentTime().seconds > before + 0.3 }
        record("resumed-clock", app: app)
    }

    /// Exercise the real scene/native launch path without calling watchAction.
    /// The integration signal is injected at the isolated detector boundary;
    /// trusted WebKit input itself is covered by the separate AppKit driver.
    private static func automaticPlayback(_ config:Configuration,app:AppModel) async throws {
        try require(app.browser.candidates.isEmpty && !mounted(.videoBar),"empty-browser-hides-video-bar")
        record("empty-browser-hides-video-bar",app:app)
        app.browser.preferences.openVideosInVR=true
        openAddress?();try await wait("automatic-address") { mounted(.address) }
        submitAddress?(config.origin.appendingPathComponent("quality-4k.html").absoluteString)
        try await wait("automatic-page-playing",seconds:45) {
            app.browser.pageHTTPStatus==200 && app.browser.candidates.contains { $0.width>0 } && mounted(.videoBar)
        }
        // Some cold simulator HLS sessions defer autoplay; deliberately starting
        // page playback through JavaScript must still never open native VR.
        _ = try await app.browser.webView.callAsyncJavaScript("await document.querySelector('video').play();return true;",arguments:[:],in:nil,contentWorld:.defaultClient)
        try await wait("programmatic-page-playing") { app.browser.candidates.contains { $0.webMedia?.paused==false } }
        try require(!app.playback.immersiveActive && !app.playback.openingImmersive,"autoplay-does-not-open-native-viewer")
        record("programmatic-play-stays-inline-and-detected-video-shows-bar",app:app)
        func signal(_ id:String) async throws {
            _ = try await app.browser.webView.callAsyncJavaScript("""
                const video=document.querySelector('video');
                await video.play();
                const candidates=globalThis.visionStreamDetector.scan();
                const candidate=candidates.find(c=>c.width>0 && !c.webMedia.paused);
                if (!candidate) throw new Error('calibration player not ready');
                candidate.playIntent={id:token,age:0,visible:true};
                globalThis.webkit.messageHandlers.visionStream.postMessage({frameID:candidate.id.split(':')[0],candidates:[candidate]});
                return true;
                """,arguments:["token":id],in:nil,contentWorld:.defaultClient)
        }
        let id=UUID().uuidString
        try await signal(id)
        try await wait("automatic-native-frame",seconds:45) {
            app.playback.immersiveActive && app.playback.isPlaying && app.playback.decodedWidth==3840 && app.playback.decodedHeight==1920 &&
            mounted(.immersive) && mounted(.playback) && returnAction != nil
        }
        try require(app.playback.automaticallyDetectFormat && app.playback.presentation == .vr180 && app.playback.layout == .sideBySide,"automatic-format-retained")
        record("automatic-handoff-highest-4k-vr180-sbs-and-controls",app:app)
        let firstFrames=SimulatorTestMonitor.framesReceived
        try await wait("automatic-progressing-frames") { SimulatorTestMonitor.framesReceived>firstFrames+3 }
        record("automatic-native-frames-progress",app:app)
        if let exit=returnAction { await exit() } else { throw Failure.check("automatic-missing-exit") }
        try await wait("automatic-browser-return",seconds:20) {
            !app.playback.immersiveActive && !app.playback.isReady && SimulatorTestMonitor.browserScenePhase=="active" && !mounted(.playback)
        }
        try await signal(id)
        try await Task.sleep(for:.milliseconds(1800))
        try require(!app.playback.immersiveActive && !app.playback.isPreparing && !app.playback.openingImmersive,"return-does-not-reopen-same-gesture")
        record("return-and-replayed-gesture-do-not-reopen-viewer",app:app)
        try await signal(UUID().uuidString)
        try await wait("automatic-second-user-play",seconds:45) { app.playback.immersiveActive && app.playback.isPlaying && returnAction != nil }
        record("new-play-gesture-opens-again",app:app)
        if let exit=returnAction { await exit() }
        try await wait("automatic-second-return",seconds:20) { !app.playback.immersiveActive && SimulatorTestMonitor.browserScenePhase=="active" }
        app.browser.open(config.origin.appendingPathComponent("empty-test"))
        try await wait("automatic-empty-navigation") { app.browser.pageHTTPStatus==200 && !app.browser.isLoading && app.browser.candidates.isEmpty && !mounted(.videoBar) }
        try require(app.downloads.videos.isEmpty && app.queuedSaves.isEmpty && !app.saveInProgress,"automatic-play-does-not-download")
        record("leaving-video-hides-bar-and-no-download-was-started",app:app)
    }

    private static func forms(_ config: Configuration, app: AppModel) async throws {
        try require(!app.playback.immersiveActive && !mounted(.playback), "launch-does-not-restore-empty-controls")
        openAddress?(); try await wait("address-sheet") { mounted(.address) }
        if config.reviewPanel == "address" { record("review-address-mounted", app: app); return }
        submitAddress?(config.origin.appendingPathComponent("empty-test").absoluteString)
        try await wait("address-submit", seconds: 45) { !mounted(.address) && app.browser.pageHTTPStatus == 200 && !app.browser.isLoading }
        record("address-form-navigation", app: app)
        for (panel, action) in [(SimulatorPanel.finder, openFinder), (.library, openLibrary), (.details, openDetails), (.downloads, openDownloads), (.bookmarks, openBookmarks), (.settings, openSettings)] {
            action?(); try await wait("sheet-" + panel.rawValue) { mounted(panel) }
            record("mounted-" + panel.rawValue, app: app)
            if config.reviewPanel == panel.rawValue {
                if panel == .downloads {
                    app.downloads.start(.init(id: "review-cc0", source: config.origin.appendingPathComponent("controls-demo.mp4").absoluteString, title: "CC0 calibration · VR180 SBS"), cookies: [], userAgent: nil)
                    try await wait("review-saved-file", seconds: 30) { !app.downloads.isDownloading && app.downloads.videos.count == 1 }
                    try require(app.downloads.message == nil, "review-download-complete")
                }
                if panel == .bookmarks { app.browser.preferences.saveBookmark(name: "Calibration library", address: config.origin.appendingPathComponent("empty-test").absoluteString) }
                record("review-panel-ready", app: app); return
            }
            closeSheets?(); try await wait("dismiss-" + panel.rawValue) { !mounted(panel) }
        }
        openStream?(); try await wait("manual-stream-sheet") { mounted(.stream) }
        if config.reviewPanel == "stream" { record("review-stream-mounted", app: app); return }
        submitStream?("http://127.0.0.1/insecure.mp4")
        try require(app.playback.errorMessage != nil && !app.playback.immersiveActive && mounted(.stream), "invalid-manual-stream-stays-in-form")
        record("invalid-manual-stream-rejected", app: app)
        closeSheets?(); try await wait("manual-stream-dismissed") { !mounted(.stream) }
        try require(!app.playbackReport.contains("://"), "redacted-report")
        record("redacted-report", app: app)
        openSettings?(); try await wait("privacy-settings") { mounted(.settings) && diagnosticsMode != nil && diagnosticsDelete != nil }
        diagnosticsMode?(false)
        try require(!app.diagnosticsEnabled && !app.history.isEnabled && app.history.eventCount > 0,"privacy-opt-out-retains-history")
        record("privacy-opt-out-retains-history",app:app)
        diagnosticsMode?(true)
        try require(app.diagnosticsEnabled && app.history.isEnabled,"privacy-opt-in")
        record("privacy-opt-in",app:app)
        let savedCount=app.downloads.videos.count
        diagnosticsDelete?()
        try require(!app.history.isEnabled && app.history.eventCount == 0 && app.downloads.videos.count == savedCount && app.privacyMessage?.contains("deleted") == true,"privacy-delete-keeps-videos")
        record("privacy-delete-keeps-videos",app:app)
        closeSheets?(); try await wait("privacy-settings-dismissed") { !mounted(.settings) }
    }

    private static func mounted(_ panel: SimulatorPanel) -> Bool { SimulatorTestMonitor.mountedPanels.contains(panel.rawValue) }
    private static func require(_ condition: Bool, _ code: String) throws { if !condition { throw Failure.check(code) } }
    private static func wait(_ code: String, seconds: Double = 12, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        try require(predicate(), "timeout-" + code)
    }
    private static func record(_ name: String, app: AppModel) {
        checks.append(["name": name, "outcome": "passed", "elapsedSeconds": Date().timeIntervalSince(startedAt)])
        write(status: "running", app: app)
    }
    private static func write(status: String, app: AppModel, failure: String? = nil) {
        guard let config = configuration else { return }
        do {
            let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("VisionStreamAutomation", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let report = try JSONSerialization.jsonObject(with: Data(app.playbackSnapshot.utf8))
            let record: [String: Any] = ["schemaVersion": 1, "identifier": config.identifier, "scenario": config.name,
                                        "status": status, "checks": checks, "soakMetrics": soakMetrics, "failureCode": failure.map { $0 as Any } ?? NSNull(),
                                        "elapsedSeconds": Date().timeIntervalSince(startedAt), "report": report,
                                        "testKind": "In-process real-scene integration; no synthetic input", "audioMuted": true]
            try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]).write(to: directory.appendingPathComponent("Scenario.json"), options: .atomic)
        } catch { print("SIMULATOR_SCENARIO_REPORT_UNAVAILABLE") }
    }
}
#endif
