import Foundation

/// A deliberately narrow fallback: finite, independently muxed, clear MPEG-TS.
/// Reject dependencies rather than decrypt, rewrite or silently omit tracks.
public struct ClearHLSPlan:Sendable {
    public let segments:[HLSManifest.Resource]
    public let duration:Double
    public init(data:Data,base:URL) throws {
        let graph=try HLSManifest(data:data,base:base)
        guard graph.variants.isEmpty,let text=String(data:data,encoding:.utf8) else { throw PlanError.unsupported }
        let lines=text.components(separatedBy:.newlines).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
        guard lines.contains("#EXT-X-ENDLIST") else { throw PlanError.live }
        guard !lines.contains(where: { line in
            line.hasPrefix("#EXT-X-SESSION-KEY:") || line.hasPrefix("#EXT-X-DEFINE:") || line.hasPrefix("#EXT-X-MAP:") || line.hasPrefix("#EXT-X-BYTERANGE:") || line.hasPrefix("#EXT-X-DISCONTINUITY") || line.hasPrefix("#EXT-X-PART:") || (line.hasPrefix("#EXT-X-KEY:") && HLSManifest.attributes(String(line.dropFirst(11)))["METHOD"] != "NONE")
        }) else { throw PlanError.unsupported }
        guard !graph.resources.contains(where: { $0.role != .segment }) else { throw PlanError.unsupported }
        let resources=graph.resources.filter { $0.role == .segment }
        let intervals=lines.filter { $0.hasPrefix("#EXTINF:") }.compactMap { Double($0.dropFirst(8).split(separator:",",omittingEmptySubsequences:false).first ?? "") }
        guard !resources.isEmpty,resources.count<=2048,resources.count==intervals.count,
              intervals.allSatisfy({ $0.isFinite && $0>0 && $0<=120 }),
              resources.allSatisfy({ $0.url.pathExtension.lowercased()=="ts" }) else { throw PlanError.unsupported }
        self.segments=resources;duration=intervals.reduce(0,+)
    }
    public enum PlanError:Error { case unsupported,live }
}
