import Foundation

extension AppModel {
    struct QueuedSave:Identifiable {
        let id:UUID
        let media:MediaCandidate
        let cookies:[HTTPCookie]
        let userAgent:String?
        let cookieProvider:(@MainActor (URL) async -> [HTTPCookie])?
        let context:DiagnosticContext?
        var name:String { OfflineVideoStore.cleanName(media.title) }
    }
    var saveInProgress:Bool { downloads.isDownloading || hlsDownloads.active }
    var saveQueueFull:Bool { queuedSaves.count>=20 }

    /// Source URLs and request context stay in memory. Expired signed URLs fail
    /// normally; queued requests never fabricate replacements or credentials.
    @discardableResult
    func enqueueSave(_ media:MediaCandidate,cookies:[HTTPCookie],userAgent:String?,cookieProvider:(@MainActor (URL) async -> [HTTPCookie])? = nil) -> Bool {
        guard HLSOfflineLibrary.accepts(media) || DownloadModel.unavailableReason(media)==nil else {
            saveQueueMessage="This source cannot be saved. Choose a supported MP4 or on-demand HLS video.";return false
        }
        guard !saveQueueFull else { saveQueueMessage="The queue is full. Remove a waiting video or let a save finish.";return false }
        guard !queuedSaves.contains(where: { $0.media.source==media.source }),!(saveInProgress && activeSaveSource==media.source) else {
            saveQueueMessage="This video is already saving or waiting in the queue.";return false
        }
        let context=history.isEnabled ? history.begin(HLSOfflineLibrary.accepts(media) ? .hlsDownload:.mp4Download,media:media):nil
        queuedSaves.append(.init(id:UUID(),media:media,cookies:cookies,userAgent:userAgent,cookieProvider:cookieProvider,context:context))
        history.record(.transfer,context:context,labels:["phase":"queued"])
        saveQueueMessage=nil
        startNextSaveIfIdle()
        observeSaveQueue()
        return true
    }
    func removeQueuedSave(_ id:UUID) {
        guard let index=queuedSaves.firstIndex(where: { $0.id==id }) else { return }
        history.record(.controls,context:queuedSaves[index].context,labels:["action":"queued-save-remove"])
        queuedSaves.remove(at:index)
    }
    private func startNextSaveIfIdle() {
        guard !saveInProgress else { return }
        if activeSaveSource != nil,!activeSaveIsHLS,downloads.failureCode != "none",let message=downloads.message {
            saveQueueMessage="A queued video could not be saved. \(message)"
        }
        activeSaveSource=nil
        guard !queuedSaves.isEmpty else { return }
        let next=queuedSaves.removeFirst()
        activeSaveSource=next.media.source
        activeSaveIsHLS=HLSOfflineLibrary.accepts(next.media)
        history.record(.transfer,context:next.context,labels:["phase":"queue-starting"])
        if HLSOfflineLibrary.accepts(next.media) {
            hlsDownloads.start(next.media,cookies:next.cookies,userAgent:next.userAgent,cookieProvider:next.cookieProvider,parent:next.context)
        } else { downloads.start(next.media,cookies:next.cookies,userAgent:next.userAgent,parent:next.context) }
    }
    private func observeSaveQueue() {
        guard saveQueueWorker==nil else { return }
        saveQueueWorker=Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.startNextSaveIfIdle()
                if self.queuedSaves.isEmpty && !self.saveInProgress {
                    self.activeSaveSource=nil;self.saveQueueWorker=nil;return
                }
                do { try await Task.sleep(for:.milliseconds(150)) } catch { return }
            }
        }
    }
}
