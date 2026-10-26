import SwiftUI
import UniformTypeIdentifiers

@MainActor struct DownloadsView: View {
    let app: AppModel
    let downloads: DownloadModel
    let hls: HLSOfflineLibrary
    let watch: (SavedVideo) -> Void
    let watchHLS: (SavedHLSVideo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: SavedVideo?
    @State private var deletingHLS: SavedHLSVideo?
    @State private var showImporter = false
    @State private var confirmRepair = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloads").font(.title2.bold())
                    Text("\(downloads.videos.count + hls.saved.count) saved · \(ByteCountFormatter.string(fromByteCount: downloads.totalBytes + hls.saved.reduce(0) { $0 + $1.bytes }, countStyle: .file)) used")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import MP4", systemImage: "square.and.arrow.down") { showImporter = true }.disabled(downloads.isDownloading || hls.active)
                Button("Done") { dismiss() }.keyboardShortcut("w", modifiers: .command)
            }
            if downloads.isDownloading {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(downloads.status); Spacer(); Button("Cancel", role: .cancel) { downloads.cancel() } }
                    if downloads.expected > 0 { ProgressView(value: Double(downloads.received), total: Double(downloads.expected)) }
                    else { ProgressView() }
                    Text(ByteCountFormatter.string(fromByteCount: downloads.received, countStyle: .file) + (downloads.expected > 0 ? " of " + ByteCountFormatter.string(fromByteCount: downloads.expected, countStyle: .file) : " downloaded"))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            } else if !downloads.status.isEmpty { Text(downloads.status).font(.callout).foregroundStyle(.secondary) }
            if let message = downloads.message { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout) }
            if downloads.needsRepair {
                Button("Repair library", systemImage: "wrench.and.screwdriver") { confirmRepair = true }.disabled(downloads.isDownloading || hls.active)
            }
            if let message=app.saveQueueMessage { Label(message,systemImage:"info.circle").font(.callout).foregroundStyle(.secondary) }
            if let message = hls.message { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout) }
            if downloads.videos.isEmpty && hls.videos.isEmpty && app.queuedSaves.isEmpty {
                ContentUnavailableView("No saved videos", systemImage: "arrow.down.circle", description: Text("Start a video in the browser, then choose Save video from Video tools, or import an MP4 from Files. Saved videos play without an internet connection."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !app.queuedSaves.isEmpty {
                            Text("Waiting to save · \(app.queuedSaves.count)").font(.headline).frame(maxWidth:.infinity,alignment:.leading)
                            ForEach(Array(app.queuedSaves.enumerated()),id:\.element.id) { index,video in
                                HStack(spacing:14) {
                                    Image(systemName:"clock").foregroundStyle(.secondary)
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(video.name).lineLimit(2)
                                        Text(index==0 ? "Next in queue" : "Position \(index+1)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Remove",systemImage:"xmark.circle") { app.removeQueuedSave(video.id) }
                                        .labelStyle(.iconOnly).accessibilityLabel("Remove \(video.name) from queue")
                                }.padding().background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:16))
                            }
                        }
                        ForEach(hls.videos) { video in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "film.stack").foregroundStyle(.cyan)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(video.name).lineLimit(2)
                                        Text(video.state == .complete ? "HLS · " + ByteCountFormatter.string(fromByteCount: video.bytes, countStyle: .file) : (video.state == .recovering ? "Saving an MP4 copy… Keep VisionStream open." : "HLS · " + video.state.rawValue.capitalized)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if video.state == .complete {
                                        Button("Play", systemImage: "play.fill") { watchHLS(video) }.buttonStyle(.borderedProminent)
                                    } else if video.state == .saving {
                                        Button("Pause", systemImage: "pause") { hls.pause(video.id) }
                                    } else if video.state == .paused {
                                        Button("Resume", systemImage: "play") { hls.resume(video.id) }
                                    }
                                    if video.state == .complete || video.state == .failed {
                                        Button("Delete", systemImage: "trash", role: .destructive) { deletingHLS = video }.labelStyle(.iconOnly).accessibilityLabel("Delete \(video.name)")
                                    } else if video.state != .validating && video.state != .cancelling {
                                        Button("Cancel", role: .cancel) { hls.cancel(video.id) }
                                    }
                                }
                                if [.saving, .paused].contains(video.state) { ProgressView(value: video.fraction) }
                                if let failure = video.failure { Text(failure).font(.caption).foregroundStyle(.orange) }
                            }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        }
                        ForEach(downloads.videos) { video in
                            HStack(spacing: 16) {
                                Image(systemName: "film.stack").font(.title2).foregroundStyle(.cyan)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.name).lineLimit(2)
                                    Text(ByteCountFormatter.string(fromByteCount: video.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Play", systemImage: "play.fill") { watch(video) }.buttonStyle(.borderedProminent)
                                if let file = downloads.store.file(for: video) {
                                    ShareLink(item: file, preview: SharePreview(video.name)) { Image(systemName: "square.and.arrow.up") }
                                        .accessibilityLabel("Export \(video.name)")
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = video }.labelStyle(.iconOnly)
                                    .accessibilityLabel("Delete \(video.name)")
                            }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
            Text("Waiting videos start automatically, one at a time. The queue is kept only while VisionStream is running; expiring website links may need to be added again. Saved media is excluded from backups. Keep VisionStream open for MP4 downloads and imports. HLS first uses Apple’s background service. If it fails, supported clear HLS can be saved as an MP4 copy while VisionStream stays open. Force-quitting can cancel unfinished HLS downloads; the system selects download quality and may remove packages when storage is low. Native HLS packages play here; saved MP4 copies can be exported.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 760, height: 580)
            .simulatorPanel(.downloads)
            .onAppear {
                #if targetEnvironment(simulator)
                if SimulatorScenarioRunner.isConfigured {
                    SimulatorScenarioRunner.downloadWatch = { if let saved = downloads.videos.first { watch(saved) } }
                }
                #endif
            }
            .onDisappear {
                #if targetEnvironment(simulator)
                SimulatorScenarioRunner.downloadWatch = nil
                #endif
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.mpeg4Movie], allowsMultipleSelection: false) { result in
                if case let .success(files) = result, let file = files.first { downloads.importVideo(file) }
                else if case .failure = result { downloads.message = "The file could not be opened. Try selecting it again in Files." }
            }
            .confirmationDialog("Repair saved-video library?", isPresented: $confirmRepair, titleVisibility: .visible) {
                Button("Repair library") { downloads.repair() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This rebuilds the list from videos saved in VisionStream. Original videos are kept. Some names and format choices may need to be set again.") }
            .confirmationDialog("Delete saved HLS video?", isPresented: Binding(get: { deletingHLS != nil }, set: { if !$0 { deletingHLS = nil } }), titleVisibility: .visible) {
                Button("Delete video", role: .destructive) { if let deletingHLS { hls.remove(deletingHLS) }; deletingHLS = nil }
                Button("Cancel", role: .cancel) { deletingHLS = nil }
            } message: { Text("This removes only the HLS package saved in VisionStream.") }
            .confirmationDialog("Delete saved video?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete video", role: .destructive) { if let deleting { downloads.remove(deleting) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("This removes only the copy saved in VisionStream.") }
    }
}
