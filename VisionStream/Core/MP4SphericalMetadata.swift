import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads only complete, bounded fast-start movie metadata. Never searches video
/// bytes for XML or treats an aspect ratio as evidence of a spherical projection.
public enum MP4SphericalMetadata {
    public static let maximumPrefixBytes = 262_144
    private static let sphericalID = Data([0xff,0xcc,0x82,0x63,0xf8,0x55,0x4a,0x93,0x88,0x14,0x58,0x7a,0x02,0x52,0x1f,0xdd])
    private struct Box { let type: String; let payload: Data }
    private static func boxes(_ data: Data, allowIncompleteTail: Bool = false) -> [Box]? {
        let bytes = [UInt8](data)
        var result: [Box] = [], offset = 0
        func integer(_ start: Int, _ count: Int) -> UInt64 {
            bytes[start..<start+count].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        while offset < bytes.count {
            guard result.count < 512, bytes.count - offset >= 8 else { return allowIncompleteTail ? result : nil }
            var size = integer(offset, 4), header = 8
            if size == 1 {
                guard bytes.count - offset >= 16 else { return allowIncompleteTail ? result : nil }
                size = integer(offset+8, 8); header = 16
            }
            guard size >= UInt64(header), size <= UInt64(bytes.count - offset) else { return allowIncompleteTail ? result : nil }
            guard let type = String(bytes: bytes[offset+4..<offset+8], encoding: .ascii) else { return nil }
            result.append(.init(type: type, payload: Data(bytes[offset+header..<offset+Int(size)])))
            offset += Int(size)
        }
        return result
    }

    public static func hint(prefix: Data) -> VideoFormatHint? {
        guard prefix.count <= maximumPrefixBytes, let roots = boxes(prefix, allowIncompleteTail: true),
              roots.filter({ $0.type == "moov" }).count == 1,
              let movie = roots.first(where: { $0.type == "moov" }), let children = boxes(movie.payload) else { return nil }
        var hints: [VideoFormatHint] = []
        for track in children.filter({ $0.type == "trak" }) {
            guard let entries = boxes(track.payload), let media = entries.first(where: { $0.type == "mdia" }),
                  let mediaEntries = boxes(media.payload), let handler = mediaEntries.first(where: { $0.type == "hdlr" }),
                  handler.payload.count >= 12, String(data: handler.payload.subdata(in: 8..<12), encoding: .ascii) == "vide" else { continue }
            let records = entries.filter { $0.type == "uuid" && $0.payload.prefix(16) == sphericalID }
            guard records.count <= 1 else { return nil }
            if let record = records.first {
                guard let hint = xmlHint(Data(record.payload.dropFirst(16))) else { return nil }
                hints.append(hint)
            }
        }
        guard let first = hints.first, hints.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    static func xmlHint(_ data: Data) -> VideoFormatHint? {
        guard data.count <= 65_536, let text = String(data: data, encoding: .utf8),
              !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else { return nil }
        let reader = SphericalXMLReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), !reader.invalid, reader.fields["Spherical"] == "true",
              reader.fields["Stitched"] == "true", reader.fields["ProjectionType"] == "equirectangular" else { return nil }
        let fields = reader.fields
        let layout: StereoLayout
        switch fields["StereoMode"] ?? "mono" {
        case "mono": layout = .mono
        case "left-right": layout = .sideBySide
        case "top-bottom": layout = .topBottom
        default: return nil
        }
        let dimensions = ["FullPanoWidthPixels", "FullPanoHeightPixels", "CroppedAreaImageWidthPixels", "CroppedAreaImageHeightPixels"]
        var projection = VideoProjection.vr360
        if dimensions.contains(where: { fields[$0] != nil }) {
            guard let fullW = Int(fields[dimensions[0]] ?? ""), let fullH = Int(fields[dimensions[1]] ?? ""),
                  let cropW = Int(fields[dimensions[2]] ?? ""), let cropH = Int(fields[dimensions[3]] ?? ""),
                  [fullW,fullH,cropW,cropH].allSatisfy({ (1...65536).contains($0) }),
                  let left = Int(fields["CroppedAreaLeftPixels"] ?? "0"), let top = Int(fields["CroppedAreaTopPixels"] ?? "0"),
                  (0...fullW).contains(left), cropH == fullH, top == 0 else { return nil }
            if cropW == fullW, left == 0 { projection = .vr360 }
            else if cropW * 2 == fullW, left * 4 == fullW { projection = .vr180 }
            else { return nil }
        } else if fields["CroppedAreaLeftPixels"] != nil || fields["CroppedAreaTopPixels"] != nil { return nil }
        return .init(projection: projection, layout: layout, evidence: .metadata)
    }
}

private final class SphericalXMLReader: NSObject, XMLParserDelegate {
    var fields: [String: String] = [:]
    var invalid = false
    private var active: String?
    private var value = ""
    private var depth = 0
    private var characterCount = 0
    private let allowed: Set<String> = ["Spherical", "Stitched", "ProjectionType", "StereoMode", "FullPanoWidthPixels", "FullPanoHeightPixels", "CroppedAreaImageWidthPixels", "CroppedAreaImageHeightPixels", "CroppedAreaLeftPixels", "CroppedAreaTopPixels"]
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        depth += 1
        guard depth <= 8, active == nil else { invalid = true; parser.abortParsing(); return }
        if namespaceURI == "http://ns.google.com/videos/1.0/spherical/", allowed.contains(name) { active = name; value = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterCount += string.utf8.count
        if characterCount > 16_384 { invalid = true; parser.abortParsing(); return }
        if active != nil { value += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if active == name {
            if fields[name] != nil { invalid = true; parser.abortParsing() }
            fields[name] = value.trimmingCharacters(in: .whitespacesAndNewlines); active = nil
        }
        depth -= 1
    }
}
