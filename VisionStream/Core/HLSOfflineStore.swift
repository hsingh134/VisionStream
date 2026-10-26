import Foundation

public struct SavedHLSVideo: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case preparing, saving, paused, validating, recovering, complete, failed, cancelling }
    public let id: UUID
    public let name: String
    public let hint: VideoFormatHint?
    public var state: State
    public var relativePackage: String?
    public var bytes: Int64 = 0
    public var fraction: Double = 0
    public var failure: String?
    public var failureCodes: [String]?
    public var diagnosticContext: DiagnosticContext?
}

public struct HLSOfflineStore: Sendable {
    public let root: URL
    public let library: URL
    public init(root: URL, library: URL) { self.root = root.resolvingSymlinksInPath(); self.library = library.resolvingSymlinksInPath() }
    public func load() throws -> [SavedHLSVideo] {
        let file = root.appendingPathComponent("jobs.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 1_000_000 else { throw OfflineVideoStore.StoreError.invalidCatalogue }
        let jobs = try JSONDecoder().decode([SavedHLSVideo].self, from: Data(contentsOf: file))
        guard jobs.count <= 200, Set(jobs.map(\.id)).count == jobs.count,
              jobs.allSatisfy({ $0.bytes >= 0 && $0.fraction.isFinite && (0...1).contains($0.fraction) && ($0.relativePackage == nil || url(for: $0.relativePackage!) != nil) }) else { throw OfflineVideoStore.StoreError.invalidCatalogue }
        return jobs
    }
    public func save(_ jobs: [SavedHLSVideo]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = root; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try folder.setResourceValues(flags)
        guard jobs.count <= 200 else { throw OfflineVideoStore.StoreError.invalidCatalogue }
        try JSONEncoder().encode(jobs).write(to: root.appendingPathComponent("jobs.json"), options: .atomic)
    }
    public func relative(_ url: URL) -> String? {
        var path = url.standardizedFileURL.path
        let prefix = library.path + "/"
        // AVAssetDownloadURLSession supplies the system no-follow alias on
        // current simulators. Accept only that alias of this exact Library;
        // relative journal entries still resolve through checked local paths.
        if path.hasPrefix("/.nofollow" + prefix) { path = String(path.dropFirst("/.nofollow".count)) }
        guard url.isFileURL, path.hasPrefix(prefix) else { return nil }
        let relative = String(path.dropFirst(prefix.count))
        return self.url(for: relative)?.path == path ? relative : nil
    }
    public func url(for relative: String) -> URL? {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.count <= 6, relative.utf8.count <= 2048,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              parts[0].hasPrefix("com.apple.UserManagedAssets."), relative.hasSuffix(".movpkg") else { return nil }
        var cursor = library
        for part in parts {
            cursor.appendPathComponent(String(part))
            if let type = try? FileManager.default.attributesOfItem(atPath: cursor.path)[.type] as? FileAttributeType, type == .typeSymbolicLink { return nil }
        }
        let url = library.appendingPathComponent(relative).standardizedFileURL
        guard url.resolvingSymlinksInPath().path == url.path else { return nil }
        return url
    }
    public func package(for video: SavedHLSVideo) -> URL? {
        guard video.state == .complete, let relative = video.relativePackage, let url = url(for: relative),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        return url
    }
    public func removePackage(relative: String?) throws {
        guard let relative, let url = url(for: relative), FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
    public static func packageBytes(_ url: URL) throws -> Int64 {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { throw OfflineVideoStore.StoreError.invalidFile }
        var bytes: Int64 = 0, count = 0
        for case let file as URL in files {
            count += 1
            guard count <= 50_000 else { throw OfflineVideoStore.StoreError.invalidFile }
            let value = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard value.isSymbolicLink != true else { throw OfflineVideoStore.StoreError.invalidFile }
            if value.isRegularFile == true { bytes += Int64(value.fileSize ?? 0) }
            guard bytes <= OfflineVideoStore.maximumFileBytes else { throw OfflineVideoStore.StoreError.invalidFile }
        }
        return bytes
    }
}
