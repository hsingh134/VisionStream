import SwiftUI
import UIKit

@MainActor struct PlaybackDetailsView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    private let previewLimit=12_000
    @State private var preview = "Preparing session history…"
    @State private var exportURL: URL?
    @State private var shortened = false
    @State private var message: String?
    @State private var checkTask: Task<Void,Never>?
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Playback details").font(.title2)
            Text(app.testingDiagnosticsEnabled ? "Testing report with full page/stream links, request and response details, readiness and playback history. Signed links may grant temporary access; keep this report private." : "Current and recent session history, including source hosts, attempts, quality, format, playback and downloads. Account data and private video links are excluded.").foregroundStyle(.secondary)
            Toggle("Testing diagnostics · include full links",isOn:Binding(get:{ app.testingDiagnosticsEnabled },set:{ app.setTestingDiagnosticsEnabled($0);refresh() }))
            if app.testingDiagnosticsEnabled {
                HStack {
                    Button("Run playback checks",systemImage:"stethoscope") {
                        checkTask=Task { @MainActor in await runChecks() }
                    }.disabled(app.testingChecksRunning)
                    if app.testingChecksRunning { ProgressView().controlSize(.small) }
                }
                if let status=app.testingChecksMessage { Text(status).font(.caption).foregroundStyle(.secondary) }
                Text("Checks request the current source and prepare a muted, paused player. They add network traffic and may affect timing. They do not change the webpage or verify visible playback.").font(.caption).foregroundStyle(.secondary)
            }
            if !app.diagnosticsEnabled { Text("Detailed recording is off. This report includes a current technical snapshot and any older history you have kept.").font(.caption).foregroundStyle(.secondary) }
            if shortened { Text("This preview is shortened. Copy report and Share report include the complete recorded history and any recording gaps.").font(.caption).foregroundStyle(.secondary) }
            ScrollView { Text(preview).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut("w",modifiers:.command)
                Spacer()
                Button { refresh() } label: { Image(systemName:"arrow.clockwise") }.accessibilityLabel("Refresh report")
                Button("Copy report",systemImage:"doc.on.doc") {
                    guard let exportURL, let data=try? Data(contentsOf:exportURL),let text=String(data:data,encoding:.utf8) else { message="The report could not be copied. Refresh it and try again."; return }
                    UIPasteboard.general.string=text
                }.disabled(exportURL == nil || app.testingChecksRunning)
                if let exportURL { ShareLink("Share report",item:exportURL).disabled(app.testingChecksRunning) }
            }.controlSize(.small)
        }.padding(30).frame(width:760,height:700).task {
            refresh()
            #if targetEnvironment(simulator)
            if SimulatorScenarioRunner.isConfigured { SimulatorScenarioRunner.diagnosticCheck=runChecks;SimulatorScenarioRunner.refreshTestingReport=refresh;SimulatorScenarioRunner.diagnosticPreviewSize={ preview.count } }
            #endif
        }.onDisappear {
            checkTask?.cancel();checkTask=nil
            #if targetEnvironment(simulator)
            SimulatorScenarioRunner.diagnosticCheck=nil;SimulatorScenarioRunner.refreshTestingReport=nil;SimulatorScenarioRunner.diagnosticPreviewSize=nil
            #endif
        }
        .onChange(of: app.browser.navigationVersion) { _,_ in checkTask?.cancel() }
        .onChange(of: app.tabs.activeID) { _,_ in checkTask?.cancel() }
    }
    private func runChecks() async {
        await app.runPlaybackChecks()
        if !Task.isCancelled { refresh() }
    }
    private func refresh() {
        app.history.record(.reportCreated,context:app.playback.diagnosticContext,labels:["phase":"user-requested"])
        let text=app.playbackReport
        shortened=text.count>previewLimit
        preview=shortened ? String(text.prefix(previewLimit))+"\n… Preview shortened; use Copy or Share for the full report." : text
        do {
            let target=try DiagnosticReportFiles.write(text)
            exportURL=target; message=nil
        } catch { exportURL=nil; message="The history is visible, but its shareable file could not be saved. Check available storage." }
    }
}
