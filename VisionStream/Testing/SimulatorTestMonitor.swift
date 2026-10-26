#if targetEnvironment(simulator)
import Foundation

/// Read-only simulator telemetry, explicitly enabled by a launch environment
/// variable. There is no command endpoint, network listener or physical-device
/// implementation. Values use the same redacted report as the visible app.
@MainActor enum SimulatorTestMonitor {
    static var framesReceived: UInt64 = 0
    static var browserScenePhase = "unknown"
    private(set) static var mountedPanels: Set<String> = []
    static func panel(_ panel: SimulatorPanel, mounted: Bool) {
        guard isEnabled else { return }
        if mounted { mountedPanels.insert(panel.rawValue) } else { mountedPanels.remove(panel.rawValue) }
    }
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["VISIONSTREAM_SIMULATOR_OBSERVE"] == "1"
    }

    static func observe(app: AppModel) -> Task<Void, Never> {
        let session = UUID().uuidString
        return Task { @MainActor [weak app] in
            var sequence = 0
            var reportedFailure = false
            while !Task.isCancelled {
                // Release the strong reference before sleeping so the monitor
                // cannot keep a discarded model or test browser alive.
                if let app {
                    do {
                        sequence += 1
                        try write(app: app, session: session, sequence: sequence)
                    } catch {
                        if !reportedFailure { print("SIMULATOR_OBSERVATION_UNAVAILABLE"); reportedFailure = true }
                    }
                } else { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private static func write(app: AppModel, session: String, sequence: Int) throws {
        let report = try JSONSerialization.jsonObject(with: Data(app.playbackSnapshot.utf8))
        let playback = app.playback
        func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }
        let record: [String: Any] = [
            "schemaVersion": 1, "session": session, "sequence": sequence,
            "observedUTC": ISO8601DateFormatter().string(from: Date()),
            "observedEpoch": Date().timeIntervalSince1970,
            "mountedPanels": mountedPanels.sorted(),
            "report": report,
            "browser": ["scenePhase": browserScenePhase, "attachedToWindow": app.browser.webView.window != nil,
                        "isLoading": app.browser.isLoading, "candidateCount": app.browser.candidates.count,
                        "canGoBack": app.browser.canGoBack, "canGoForward": app.browser.canGoForward,
                        "navigationVersion": app.browser.navigationVersion],
            "playback": ["controlsAttached": mountedPanels.contains("playback"), "isReady": playback.isReady, "isPreparing": playback.isPreparing,
                         "isPlaying": playback.isPlaying, "isBuffering": playback.isBuffering,
                         "isSeeking": playback.isSeeking, "elapsed": finite(playback.elapsed),
                         "duration": finite(playback.duration), "seekStart": finite(playback.seekStart),
                         "seekEnd": finite(playback.seekEnd), "immersiveActive": playback.immersiveActive,
                         "openingImmersive": playback.openingImmersive, "recenterID": playback.recenterID,
                         "swapEyes": playback.swapEyes, "flipY": playback.flipY],
            "finder": ["isLoading": app.extractor.isLoading, "resultCount": app.extractor.streams.count,
                       "hasError": app.extractor.errorMessage != nil],
            "library": ["isLoading": app.library.isLoading, "entryCount": app.library.document?.entries.count ?? 0,
                        "streamCount": app.library.document?.streams.count ?? 0,
                        "hasError": app.library.errorMessage != nil, "canGoBack": app.library.canGoBack]
        ]
        let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("VisionStreamAutomation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            .write(to: directory.appendingPathComponent("State.json"), options: .atomic)
    }
}
#endif
