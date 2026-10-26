import Foundation

// Foundation documents cancel() as safe from another thread. Only the copy
// worker coordinates; cancellation never touches its file handles.
private final class FileCopyCoordinator: @unchecked Sendable { let value = NSFileCoordinator() }

enum VideoFileCopy {
    /// Chunked copy keeps memory bounded and cancellation responsive for large
    /// user-selected files. The caller owns the security-scoped access lifetime.
    static func run(from source: URL, to destination: URL,
                    progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let coordinator = FileCopyCoordinator()
        let job = Task.detached(priority: .utility) {
            guard source.isFileURL, ["mp4", "m4v"].contains(source.pathExtension.lowercased()) else { throw MP4DownloadTransfer.TransferError.notMP4 }
            var coordinationError: NSError?
            var copyError: Error?
            coordinator.value.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
                do {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true, let size = values.fileSize, size > 0 else { throw MP4DownloadTransfer.TransferError.notMP4 }
                    guard size <= OfflineVideoStore.maximumFileBytes else { throw MP4DownloadTransfer.TransferError.tooLarge }
                    let free = (try FileManager.default.attributesOfFileSystem(forPath: destination.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                    guard free > Int64(size) + 256 * 1024 * 1024 else { throw MP4DownloadTransfer.TransferError.storage }
                    let input = try FileHandle(forReadingFrom: url)
                    defer { try? input.close() }
                    let header = try input.read(upToCount: 12) ?? Data()
                    guard header.count == 12, String(data: header[4..<8], encoding: .ascii) == "ftyp" else { throw MP4DownloadTransfer.TransferError.notMP4 }
                    try input.seek(toOffset: 0)
                    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                    let output = try FileHandle(forWritingTo: destination)
                    defer { try? output.close() }
                    var copied: Int64 = 0, last = Date.distantPast
                    while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                        try Task.checkCancellation()
                        copied += Int64(chunk.count)
                        guard copied <= OfflineVideoStore.maximumFileBytes, copied <= Int64(size) else { throw MP4DownloadTransfer.TransferError.tooLarge }
                        try output.write(contentsOf: chunk)
                        if Date().timeIntervalSince(last) > 0.2 || copied == size { last = Date(); progress(copied, Int64(size)) }
                    }
                    guard copied == size else { throw CocoaError(.fileReadCorruptFile) }
                    try Task.checkCancellation()
                } catch { copyError = error }
            }
            if let error = coordinationError ?? copyError { throw error }
        }
        try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel(); coordinator.value.cancel() }
    }
}
