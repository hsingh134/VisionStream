import Foundation

/// The catalogue contains local identifiers, names and format hints only.
/// Remote URLs, browser sessions and download resume data are never persisted.
public struct SavedVideo: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public let bytes: Int64
    public let savedAt: Date
    public let formatHint: VideoFormatHint?
    public var diagnosticContext: DiagnosticContext?
}

public struct OfflineVideoStore: Sendable {
    public static let maximumFileBytes: Int64 = 8 * 1024 * 1024 * 1024
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }
    private var catalogue: URL { root.appendingPathComponent("catalogue.json") }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
    public func load() throws -> [SavedVideo] {
        guard FileManager.default.fileExists(atPath: catalogue.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: catalogue.path)
        guard catalogue.resolvingSymlinksInPath().path == catalogue.path,
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value, size <= 2_000_000 else { throw StoreError.invalidCatalogue }
        let data = try Data(contentsOf: catalogue)
        guard data.count <= 2_000_000 else { throw StoreError.invalidCatalogue }
        let records = try JSONDecoder().decode([SavedVideo].self, from: data)
        guard records.count <= 2000, Set(records.map(\.id)).count == records.count else { throw StoreError.invalidCatalogue }
        return records.filter { file(for: $0) != nil }
    }
    public func file(for record: SavedVideo) -> URL? {
        let url = root.appendingPathComponent(record.id.uuidString + ".mp4")
        guard root.resolvingSymlinksInPath().path == root.path,
              url.resolvingSymlinksInPath().path == url.path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value == record.bytes,
              record.bytes > 0, record.bytes <= Self.maximumFileBytes else { return nil }
        return url
    }
    public func commit(staging: URL, id: UUID, name: String, hint: VideoFormatHint?, context: DiagnosticContext? = nil) throws -> SavedVideo {
        try prepare()
        var records = try load()
        guard records.count < 2000, !records.contains(where: { $0.id == id }),
              let size = (try FileManager.default.attributesOfItem(atPath: staging.path)[.size] as? NSNumber)?.int64Value,
              size > 0, size <= Self.maximumFileBytes else { throw StoreError.invalidFile }
        let record = SavedVideo(id: id, name: Self.cleanName(name), bytes: size, savedAt: Date(), formatHint: hint, diagnosticContext: context?.sanitized())
        let destination = root.appendingPathComponent(id.uuidString + ".mp4")
        try FileManager.default.moveItem(at: staging, to: destination)
        do {
            var file = destination
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try file.setResourceValues(values)
            records.insert(record, at: 0)
            try save(records)
            return record
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    public func remove(_ record: SavedVideo) throws {
        let records = try load().filter { $0.id != record.id }
        // Only a verified, owned UUID filename can be removed.
        if let url = file(for: record) { try FileManager.default.removeItem(at: url) }
        try save(records)
    }
    /// Recover references after an interrupted commit or damaged catalogue.
    /// Only regular UUID-named MP4 files directly inside this store participate.
    /// Original videos are never moved, modified or deleted by recovery.
    public func recover() throws -> [SavedVideo] {
        try prepare()
        let existing = (try? load()) ?? []
        let preserved = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let files = try ownedFiles()
        var recovered: [SavedVideo] = []
        for (id, url, size) in files {
            if let record = preserved[id], record.bytes == size { recovered.append(record) }
            else {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                recovered.append(.init(id: id, name: "Recovered video", bytes: size, savedAt: date, formatHint: nil))
            }
        }
        // Keep a bounded regular-file copy of the old index for diagnosis or
        // future manual recovery. Never follow a corrupt index's symbolic link.
        if catalogue.resolvingSymlinksInPath().path == catalogue.path,
           let attributes = try? FileManager.default.attributesOfItem(atPath: catalogue.path),
           attributes[.type] as? FileAttributeType == .typeRegular,
           let bytes = (attributes[.size] as? NSNumber)?.int64Value, bytes <= 2_000_000 {
            try Data(contentsOf: catalogue).write(to: root.appendingPathComponent("catalogue.previous.json"), options: .atomic)
        }
        recovered.sort { $0.savedAt > $1.savedAt }
        // Replace a linked index itself, without following or touching its target.
        if (try? FileManager.default.attributesOfItem(atPath: catalogue.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
            try FileManager.default.removeItem(at: catalogue)
        }
        try save(recovered)
        return recovered
    }
    public func hasUnlistedFiles(in records: [SavedVideo]) throws -> Bool {
        let listed = Set(records.map(\.id))
        return try ownedFiles().contains { !listed.contains($0.0) }
    }
    private func ownedFiles() throws -> [(UUID, URL, Int64)] {
        guard root.resolvingSymlinksInPath().path == root.path,
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) else { throw StoreError.invalidFile }
        var result: [(UUID, URL, Int64)] = []
        var count = 0
        for case let file as URL in enumerator {
            count += 1
            guard count <= 4004 else { throw StoreError.invalidCatalogue }
            guard file.pathExtension == "mp4", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  file.lastPathComponent == id.uuidString + ".mp4",
                  let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  let bytes = attributes.fileSize, bytes > 0, Int64(bytes) <= Self.maximumFileBytes else { continue }
            result.append((id, file, Int64(bytes)))
            guard result.count <= 2000 else { throw StoreError.invalidCatalogue }
        }
        return result
    }
    public func clearDiagnosticLinks() throws -> [SavedVideo] {
        guard root.resolvingSymlinksInPath().path==root.path else { throw StoreError.invalidCatalogue }
        var records=try load()
        for i in records.indices { records[i].diagnosticContext=nil }
        try save(records)
        let previous=root.appendingPathComponent("catalogue.previous.json")
        if FileManager.default.fileExists(atPath:previous.path) {
            let type=try FileManager.default.attributesOfItem(atPath:previous.path)[.type] as? FileAttributeType
            guard type == .typeRegular || type == .typeSymbolicLink else { throw StoreError.invalidCatalogue }
            try FileManager.default.removeItem(at:previous)
        }
        return records
    }
    private func save(_ records: [SavedVideo]) throws {
        try JSONEncoder().encode(records).write(to: catalogue, options: .atomic)
    }
    public static func cleanName(_ name: String) -> String {
        let text = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A direct stream's URL must not become its visible/persisted name.
        return text.isEmpty || text.contains("://") ? "Saved video" : text
    }
    public enum StoreError: Error { case invalidCatalogue, invalidFile }
}
