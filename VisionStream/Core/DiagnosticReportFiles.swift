import Foundation

/// Report files are opt-in exports, never uploaded by the app. Keep one owned
/// UUID file, and make deletion available even after the report sheet closes.
public enum DiagnosticReportFiles {
    public static var root:URL { FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("DiagnosticReports") }
    public static func clear(at folder:URL = root) throws {
        guard FileManager.default.fileExists(atPath:folder.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) {
            guard file.pathExtension=="json",UUID(uuidString:file.deletingPathExtension().lastPathComponent) != nil else { continue }
            let type=try FileManager.default.attributesOfItem(atPath:file.path)[.type] as? FileAttributeType
            if type == .typeRegular || type == .typeSymbolicLink { try FileManager.default.removeItem(at:file) }
        }
    }
    public static func write(_ text:String,at folder:URL = root) throws -> URL {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try clear(at:folder)
        let file=folder.appendingPathComponent(UUID().uuidString+".json")
        try Data(text.utf8).write(to:file,options:.atomic)
        return file
    }
}
