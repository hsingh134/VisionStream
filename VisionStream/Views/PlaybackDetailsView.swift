import SwiftUI
import UIKit

@MainActor struct PlaybackDetailsView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var preview = "Preparing session history…"
    @State private var exportURL: URL?
    @State private var shortened = false
    @State private var message: String?
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Playback details").font(.title2)
            Text("Current and recent session history, including source hosts, attempts, quality, format, playback and downloads. Account data and private video links are excluded.").foregroundStyle(.secondary)
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
                }.disabled(exportURL == nil)
                if let exportURL { ShareLink("Share report",item:exportURL) }
            }.controlSize(.small)
        }.padding(30).frame(width:700,height:560).task { refresh() }
    }
    private func refresh() {
        app.history.record(.reportCreated,context:app.playback.diagnosticContext,labels:["phase":"user-requested"])
        let text=app.playbackReport
        shortened=text.count>200_000
        preview=shortened ? String(text.prefix(200_000))+"\n… Preview shortened; use Copy or Share for the full report." : text
        do {
            let target=try DiagnosticReportFiles.write(text)
            exportURL=target; message=nil
        } catch { exportURL=nil; message="The history is visible, but its shareable file could not be saved. Check available storage." }
    }
}
