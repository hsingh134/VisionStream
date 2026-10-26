import Foundation

public struct VideoFormatHint: Codable, Hashable, Sendable {
    public enum Evidence: String, Codable, Sendable { case metadata, filename, imageMatch, context }
    public var projection: VideoProjection?
    public var layout: StereoLayout?
    public var evidence: Evidence
    public init(projection: VideoProjection? = nil, layout: StereoLayout? = nil, evidence: Evidence) {
        self.projection = projection; self.layout = layout; self.evidence = evidence
    }
}

public enum VideoFormatDetection {
    /// Explicit filename/title tokens only. A bare aspect ratio never identifies VR.
    public static func hint(source: String, title: String) -> VideoFormatHint? {
        let path = URL(string: source)?.lastPathComponent.removingPercentEncoding ?? ""
        let text = (path + " " + title).lowercased()
        func contains(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        let vr180 = contains(#"(?:^|[^a-z0-9])(?:vr[ _-]?180|180[ _-]?(?:vr|sbs|tb))(?:$|[^a-z0-9])"#)
        let vr360 = contains(#"(?:^|[^a-z0-9])(?:vr[ _-]?360|360[ _-]?(?:vr|sbs|tb)|equirectangular)(?:$|[^a-z0-9])"#)
        let sbs = contains(#"(?:^|[^a-z0-9])(?:sbs|side[ _-]?by[ _-]?side|lr)(?:$|[^a-z0-9])"#)
        let tb = contains(#"(?:^|[^a-z0-9])(?:tb|top[ _/-]?bottom|over[ _-]?under)(?:$|[^a-z0-9])"#)
        let mono = contains(#"(?:^|[^a-z0-9])mono(?:$|[^a-z0-9])"#)
        guard !(vr180 && vr360), [sbs, tb, mono].filter({ $0 }).count <= 1 else { return nil }
        let projection: VideoProjection? = vr180 ? .vr180 : (vr360 ? .vr360 : nil)
        let layout: StereoLayout? = sbs ? .sideBySide : (tb ? .topBottom : (mono ? .mono : nil))
        guard projection != nil || layout != nil else { return nil }
        return .init(projection: projection, layout: layout, evidence: .filename)
    }
    public static func hasVRSignal(source: String, title: String, pageURL: String = "") -> Bool {
        let path = URL(string: source)?.path.removingPercentEncoding ?? ""
        let page = URL(string: pageURL)
        let pagePath = page?.scheme == "https" && page?.user == nil && page?.password == nil ? (page?.path.removingPercentEncoding ?? "") : ""
        return (path + " " + title + " " + pagePath).lowercased().range(of: #"(?:^|[^a-z0-9])(?:vr|vr180|vr360|180vr|360vr)(?:$|[^a-z0-9])"#, options: .regularExpression) != nil
    }

    /// Persist only a VR cue, never a page URL. A cue permits image analysis;
    /// it does not assert an eye layout or panoramic geometry.
    public static func persistentHint(source: String, title: String, pageURL: String = "") -> VideoFormatHint? {
        if let explicit = hint(source: source, title: title) { return explicit }
        return hasVRSignal(source: source, title: title, pageURL: pageURL) ? .init(evidence: .context) : nil
    }

    /// Compares downsampled image halves, allowing bounded horizontal eye
    /// disparity. Rejects low-texture and ambiguous matches; callers require
    /// agreement across multiple frames. This is a heuristic, not metadata.
    public struct PackingAnalysis: Sendable {
        public var layout: StereoLayout?
        public var sideBySideScore: Double
        public var topBottomScore: Double
        public var sideBySideRegions: Int
        public var topBottomRegions: Int
        public var expandedSearch: Bool
    }
    public static func packing(luma: [Float], width: Int, height: Int) -> StereoLayout? {
        analysePacking(luma:luma,width:width,height:height).layout
    }
    public static func analysePacking(luma: [Float], width: Int, height: Int) -> PackingAnalysis {
        var result=PackingAnalysis(layout:nil,sideBySideScore:-1,topBottomScore:-1,sideBySideRegions:0,topBottomRegions:0,expandedSearch:false)
        guard (8...256).contains(width), (8...128).contains(height), width % 2 == 0, height % 2 == 0,
              luma.count == width * height, luma.allSatisfy(\.isFinite) else { return result }
        func correlation(_ horizontal: Bool, shift: Int, vertical: Int = 0, column: Int? = nil, row: Int? = nil) -> Double {
            let w = horizontal ? width / 2 : width, h = horizontal ? height : height / 2
            let start = max(column.map { $0 * w / 4 } ?? 0, -shift)
            let end = min(column.map { ($0+1) * w / 4 } ?? w, w-shift)
            let top = max(row.map { $0 * h / 4 } ?? 0,-vertical)
            let bottom = min(row.map { ($0+1) * h / 4 } ?? h,h-vertical)
            var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
            let n = Double(max(0,end-start) * max(0,bottom-top))
            guard n >= 32 else { return -1 }
            for y in top..<bottom { for x in start..<end {
                let a = Double(luma[y * width + x])
                let b = Double(luma[(y + vertical + (horizontal ? 0 : h)) * width + x + shift + (horizontal ? w : 0)])
                sx += a; sy += b; sxx += a*a; syy += b*b; sxy += a*b
            }}
            let vx = sxx / n - (sx / n)*(sx / n), vy = syy / n - (sy / n)*(sy / n)
            guard vx > 0.002, vy > 0.002 else { return -1 }
            return min(1,max(-1,(sxy / n - sx*sy / (n*n)) / sqrt(vx*vy)))
        }
        let disparity = min(4, max(1, width / 32))
        let sbs = (-disparity...disparity).map { correlation(true, shift:$0) }.max() ?? -1
        let tb = (-disparity...disparity).map { correlation(false, shift:$0) }.max() ?? -1
        result.sideBySideScore=sbs; result.topBottomScore=tb
        if sbs > 0.94, sbs-tb > 0.12 { result.layout = .sideBySide; return result }
        if tb > 0.94, tb-sbs > 0.12 { result.layout = .topBottom; return result }
        func regionalScore(_ horizontal: Bool) -> Double {
            var scores:[Double]=[]
            for row in 0..<4 { for column in 0..<4 {
                let best=(-disparity...disparity).map { correlation(horizontal,shift:$0,column:column,row:row) }.max() ?? -1
                if best > -1 { scores.append(best) }
            }}
            guard scores.count >= 6, scores.filter({ $0>0.85 }).count*2 >= scores.count else { return -1 }
            return scores.reduce(0,+)/Double(scores.count)
        }
        let regionalSBS=regionalScore(true),regionalTB=regionalScore(false)
        result.sideBySideScore=max(sbs,regionalSBS); result.topBottomScore=max(tb,regionalTB)
        if regionalSBS > 0.82, regionalSBS-regionalTB > 0.2 { result.layout = .sideBySide; return result }
        if regionalTB > 0.82, regionalTB-regionalSBS > 0.2 { result.layout = .topBottom; return result }
        // Close subjects produce depth-dependent disparity and occlusion. Search
        // a wider horizontal range plus one vertical sample, but require strong
        // textured correspondences spread across at least three rows/columns.
        result.expandedSearch=true
        func distributed(_ horizontal:Bool) -> (Double,Int) {
            let limit=min(12,max(2,width/8))
            var accepted:[Double]=[],valid=0,rows=Set<Int>(),columns=Set<Int>()
            for row in 0..<4 { for column in 0..<4 {
                var best = -1.0
                for dy in -1...1 { for dx in -limit...limit {
                    best=max(best,correlation(horizontal,shift:dx,vertical:dy,column:column,row:row))
                }}
                if best > -1 { valid += 1 }
                if best > 0.91 { accepted.append(best);rows.insert(row);columns.insert(column) }
            }}
            guard accepted.count>=8,accepted.count*2>=valid,rows.count>=3,columns.count>=3 else { return (-1,accepted.count) }
            return (accepted.reduce(0,+)/Double(accepted.count),accepted.count)
        }
        let a=distributed(true),b=distributed(false)
        result.sideBySideScore=max(result.sideBySideScore,a.0);result.topBottomScore=max(result.topBottomScore,b.0)
        result.sideBySideRegions=a.1;result.topBottomRegions=b.1
        if a.0>0.91,a.0-b.0>0.15 { result.layout = .sideBySide }
        if b.0>0.91,b.0-a.0>0.15 { result.layout = .topBottom }
        return result
    }

    /// Bounded 4×4 averaging per output pixel avoids the aliasing caused by
    /// picking a single pixel from a high-resolution decoded frame. Pixel
    /// values are temporary; callers never store or report the samples.
    public static func sampleLuma(bgra: UnsafeBufferPointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> [Float] {
        guard (1...16384).contains(width), (1...16384).contains(height),
              bytesPerRow >= width * 4, bytesPerRow <= width * 4 + 65536,
              bgra.count >= bytesPerRow * height else { return [] }
        var result: [Float] = []; result.reserveCapacity(128 * 64)
        for y in 0..<64 { for x in 0..<128 {
            var sum: Float = 0
            for sy in 0..<4 { for sx in 0..<4 {
                let row = min(height-1, ((y*8 + sy*2 + 1) * height) / (64*8))
                let column = min(width-1, ((x*8 + sx*2 + 1) * width) / (128*8))
                let i = row * bytesPerRow + column * 4
                sum += Float(bgra[i]) * 0.114 + Float(bgra[i+1]) * 0.587 + Float(bgra[i+2]) * 0.299
            }}
            result.append(sum / (16 * 255))
        }}
        return result
    }
    public static func projection(width: Int, height: Int, layout: StereoLayout) -> VideoProjection? {
        let eye = layout.eyeSize(width: width, height: height)
        guard eye.height > 0, layout != .mono else { return nil }
        let ratio = Double(eye.width) / Double(eye.height)
        if (0.95...1.05).contains(ratio) { return .vr180 }
        if (1.9...2.1).contains(ratio) { return .vr360 }
        return nil
    }
}
