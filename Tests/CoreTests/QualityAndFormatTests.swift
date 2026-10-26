#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
import Foundation
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class QualityAndFormatTests: XCTestCase {
    func testHighestPublishedSupportedRenditionPreservesExactURI() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=200000,RESOLUTION=480x240,CODECS="avc1.64001f,mp4a.40.2"
        low/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=3840x1920,CODECS="avc1.640033,mp4a.40.2"
        high/index.m3u8?signature=a%2Bb&key=1
        #EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=7680x3840,CODECS="av01.0.12M.08,mp4a.40.2"
        unsupported.m3u8
        """
        let manifest = try HLSManifest(data: Data(text.utf8), base: URL(string: "https://cdn.example/folder/master.m3u8?parent=private")!)
        XCTAssertEqual(manifest.variants.count, 3)
        XCTAssertEqual(manifest.highestIndependentVariant?.width, 3840)
        XCTAssertEqual(manifest.highestIndependentVariant?.url.absoluteString, "https://cdn.example/folder/high/index.m3u8?signature=a%2Bb&key=1")
    }
    func testParentContextAndUnknownFormatsRetainMaster() throws {
        let base = URL(string: "https://cdn.example/master.m3u8")!
        let variant = "#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=2048x1024,CODECS=\"avc1.64001f,mp4a.40.2\""
        for text in [
            "#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"key\"\n\(variant)\nhigh.m3u8",
            "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",URI=\"audio.m3u8\"\n\(variant),AUDIO=\"a\"\nhigh.m3u8",
            "#EXTM3U\n\(variant),SUBTITLES=\"subs\"\nhigh.m3u8",
            "#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=16384x8192,CODECS=\"avc1,mp4a\"\nhigh.m3u8",
            "#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=2048x1024\nhigh.m3u8",
            "#EXTM3U\n\(variant)\nhttp://cdn.example/high.m3u8",
            "#EXTM3U\n\(variant)\nhttps://user:password@cdn.example/high.m3u8"
        ] { XCTAssertNil(try HLSManifest(data: Data(text.utf8), base: base).highestIndependentVariant) }
        let tooMany = "#EXTM3U\n" + String(repeating: variant + "\nhigh.m3u8\n", count: 65)
        XCTAssertThrowsError(try HLSManifest(data: Data(tooMany.utf8), base: base))
        XCTAssertThrowsError(try HLSManifest(data: Data("<html>denied</html>".utf8), base: base))
        XCTAssertThrowsError(try HLSManifest(data: Data(repeating: 0, count: HLSManifest.maximumBytes + 1), base: base))
    }
    func testHLSReferencesKeepPublishedURLsAndResourceRoles() throws {
        let base=URL(string:"https://cdn.example/path/master.m3u8?signature=private")!
        let text="""
        #EXTM3U
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=10000,URI="iframe.m3u8?token=exact%2Bvalue"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="audio.m3u8"
        #EXT-X-STREAM-INF:RESOLUTION=1024x512,CODECS="avc1,mp4a"
        video.m3u8
        """
        let master=try HLSManifest(data:Data(text.utf8),base:base)
        XCTAssertEqual(master.resources.map(\.role),[.iframePlaylist,.audioPlaylist,.variantPlaylist])
        XCTAssertEqual(master.resources.first?.url.absoluteString,"https://cdn.example/path/iframe.m3u8?token=exact%2Bvalue")
        let media=try HLSManifest(data:Data("#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:731\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXT-X-KEY:METHOD=AES-128,URI=\"private-key\"\n#EXTINF:4,\nfirst.ts\n#EXTINF:4,\nmissing.ts?token=exact%2Bvalue\n#EXT-X-ENDLIST\n".utf8),base:base)
        XCTAssertEqual(media.resources.map(\.role),[.initialization,.key,.segment,.segment])
        XCTAssertEqual(media.resources.filter { $0.role == .segment }.map(\.index),[731,732])
        let unsafe=try HLSManifest(data:Data("#EXTM3U\n#EXTINF:4,\nhttp://unsafe.example/a.ts\nfile:///private/a.ts\nhttps://user:pass@cdn.example/a.ts\n{$unresolved}.ts".utf8),base:base)
        XCTAssertTrue(unsafe.resources.isEmpty)
    }
    func testExplicitFormatLabelsAndConflicts() {
        let hint = VideoFormatDetection.hint(source: "https://cdn.example/vr180-sbs.mp4", title: "Calibration")
        XCTAssertEqual(hint?.projection, .vr180); XCTAssertEqual(hint?.layout, .sideBySide)
        XCTAssertEqual(VideoFormatDetection.hint(source: "https://cdn.example/video.mp4", title: "VR360 top-bottom")?.layout, .topBottom)
        XCTAssertNil(VideoFormatDetection.hint(source: "https://cdn.example/video.mp4", title: "Regular 2:1 movie"))
        XCTAssertNil(VideoFormatDetection.hint(source: "https://cdn.example/vr180.mp4", title: "VR360"))
        XCTAssertNil(VideoFormatDetection.hint(source: "https://cdn.example/video.mp4", title: "sbs mono"))
        XCTAssertFalse(VideoFormatDetection.hasVRSignal(source: "https://vr.example/ordinary.mp4?vr180=true", title: "Movie"))
        XCTAssertTrue(VideoFormatDetection.hasVRSignal(source: "https://cdn.example/vr/sample.mp4", title: "Movie"))
    }
    func testFinderPreservesOnlyExactPageFormatContext() throws {
        let page = URL(string: "https://site.example/watch?id=one")!
        let payload = Data(#"{"status":"ok","streams":[{"source":"https://cdn.example/master.m3u8","mimeType":"application/vnd.apple.mpegurl","width":0,"height":0,"unavailableReason":""}]}"#.utf8)
        let found = try XCTUnwrap(ExtractedMedia.parse(payload, pageURL: page.absoluteString).streams.first).candidate
        let hint = VideoFormatHint(projection: .vr180, layout: .sideBySide, evidence: .metadata)
        let video = MediaCandidate(id: "page-video", source: "blob:https://site.example/local", pageURL: page.absoluteString, formatHint: hint)
        let merged = found.withBrowserFormatContext(page: URL(string:page.absoluteString+"#player"), title: "VR calibration", candidates: [video])
        XCTAssertEqual(merged.source, found.source)
        XCTAssertEqual(merged.formatHint, hint)
        XCTAssertTrue(VideoFormatDetection.hasVRSignal(source: merged.source, title: merged.title))
        for other in ["https://site.example/watch?id=two", "https://other.example/watch?id=one"] {
            let result = found.withBrowserFormatContext(page:URL(string:other), title:"VR180 SBS", candidates:[video])
            XCTAssertNil(result.formatHint); XCTAssertEqual(result.title, found.title)
        }
        var second = video; second.id = "other-video"; second.formatHint = .init(projection:.vr360, layout:.topBottom, evidence:.metadata)
        let ambiguous = found.withBrowserFormatContext(page:page, title:"VR calibration", candidates:[video,second])
        XCTAssertNil(ambiguous.formatHint)
        var explicit = found; explicit.formatHint = .init(projection:.vr360, layout:.mono, evidence:.metadata)
        XCTAssertEqual(explicit.withBrowserFormatContext(page:page, title:"VR calibration", candidates:[video]).formatHint, explicit.formatHint)
    }

    func testImagePackingRejectsAmbiguousAndLowTexture() {
        let w = 64, h = 32
        var sbs = [Float](repeating: 0, count: w*h), tb = sbs
        for y in 0..<h { for x in 0..<w {
            sbs[y*w+x] = Float(((x % (w/2))*17 + y*37 + x%7*y*3) % 101) / 100
            tb[y*w+x] = Float((x*17 + (y % (h/2))*37 + x%7*(y % (h/2))*3) % 101) / 100
        }}
        // Exact duplicate halves, avoiding an unrelated repeating column pattern.
        for y in 0..<h { for x in 0..<w/2 { sbs[y*w+x+w/2] = sbs[y*w+x] } }
        XCTAssertEqual(VideoFormatDetection.packing(luma: sbs, width: w, height: h), .sideBySide)
        XCTAssertEqual(VideoFormatDetection.packing(luma: tb, width: w, height: h), .topBottom)
        XCTAssertNil(VideoFormatDetection.packing(luma: [Float](repeating: 0.4, count:w*h), width:w, height:h))
        XCTAssertNil(VideoFormatDetection.packing(luma: [], width:w, height:h))
        XCTAssertNil(VideoFormatDetection.projection(width: 1920, height:1080, layout:.mono))
        XCTAssertEqual(VideoFormatDetection.projection(width: 1440, height:720, layout:.sideBySide), .vr180)
        XCTAssertEqual(VideoFormatDetection.projection(width: 2048, height:2048, layout:.topBottom), .vr360)
    }
    func testImagePackingAllowsHorizontalStereoDisparity() {
        let w = 128, h = 64, eyeW = w / 2
        func value(_ x: Int, _ y: Int) -> Float { Float((x * 17 + y * 37 + (x % 7) * y * 3) % 101) / 100 }
        for shift in [-3, 3] {
            var image = [Float](repeating: 0, count: w * h)
            for y in 0..<h { for x in 0..<eyeW {
                image[y*w+x] = value(x, y)
                image[y*w+eyeW+x] = value(max(0, min(eyeW-1, x+shift)), y)
            }}
            XCTAssertEqual(VideoFormatDetection.packing(luma: image, width: w, height: h), .sideBySide)
        }
        // A normal textured image must not be interpreted as stereo merely
        // because a small displacement is now allowed.
        var unrelated = [Float](repeating: 0, count: w*h)
        for y in 0..<h { for x in 0..<w { unrelated[y*w+x] = value(x, y) } }
        XCTAssertNil(VideoFormatDetection.packing(luma: unrelated, width: w, height: h))
    }
    func testStereoPackingWithLargeDepthDisparityVerticalOffsetAndOcclusion() {
        let w=128,h=64
        func texture(_ x:Int,_ y:Int) -> Float {
            var v=UInt32(truncatingIfNeeded:x*73856093)^UInt32(truncatingIfNeeded:y*19349663)
            v = (v ^ (v >> 13)) &* 1274126177
            return Float(v & 255)/255
        }
        for horizontal in [true,false] {
            let ew=horizontal ? w/2:w,eh=horizontal ? h:h/2
            var image=[Float](repeating:0,count:w*h)
            for y in 0..<eh { for x in 0..<ew {
                image[y*w+x]=texture(x,y)
                let shift=y<eh/2 ? 9:-10
                let sx=x+shift,sy=y+1
                let right=(y+(horizontal ? 0:eh))*w+x+(horizontal ? ew:0)
                image[right] = sx>=0 && sx<ew && sy<eh ? texture(sx,sy)*0.7+0.1:0
                // One occluded quadrant must not erase distributed stereo evidence.
                if x>=ew*3/4 { image[right]=texture(x+551,y+231) }
            }}
            XCTAssertEqual(VideoFormatDetection.packing(luma:image,width:w,height:h),horizontal ? .sideBySide:.topBottom)
        }
    }
    func testExpandedStereoSearchRejectsUnrelatedEyesAndIsBounded() {
        let w=128,h=64
        for seed in 1...12 {
            var state=UInt32(seed),image=[Float]()
            for _ in 0..<(w*h) {
                state=state &* 1664525 &+ 1013904223
                image.append(Float((state>>16)&255)/255)
            }
            // A small coincidentally duplicated patch is insufficient evidence.
            for y in 0..<12 { for x in 0..<12 { image[y*w+x+w/2]=image[y*w+x] } }
            let analysis=VideoFormatDetection.analysePacking(luma:image,width:w,height:h)
            XCTAssertNil(analysis.layout)
            XCTAssertTrue(analysis.expandedSearch)
        }
        XCTAssertNil(VideoFormatDetection.packing(luma:[Float](repeating:0,count:512*128),width:512,height:128))
    }
    func testImagePackingAllowsDifferentDepthAcrossTexturedRegions() {
        let w = 128, h = 64, eyeW = w/2
        func value(_ x: Int, _ y: Int) -> Float { Float((x*17+y*37+(x%7)*y*3)%101)/100 }
        var image = [Float](repeating: 0, count: w*h)
        for y in 0..<h { for x in 0..<eyeW {
            image[y*w+x] = value(x,y)
            let shift = ((x/16 + y/16) % 3 - 1) * 3
            image[y*w+eyeW+x] = value(max(0,min(eyeW-1,x+shift)),y)
        }}
        XCTAssertEqual(VideoFormatDetection.packing(luma: image, width: w, height: h), .sideBySide)
        // Repeating textures with equally plausible horizontal and vertical
        // packing remain inconclusive.
        for y in 0..<h { for x in 0..<w { image[y*w+x] = value(x%32,y%16) } }
        XCTAssertNil(VideoFormatDetection.packing(luma:image,width:w,height:h))
    }
    func testLumaSamplingAveragesHighFrequencyPixelsAndChecksBounds() {
        let w = 512, h = 256, stride = w*4+16
        var bytes = [UInt8](repeating:255,count:stride*h)
        for y in 0..<h { for x in 0..<w {
            let value: UInt8 = (x+y)%2 == 0 ? 0 : 255
            for channel in 0..<3 { bytes[y*stride+x*4+channel] = value }
        }}
        let sample = bytes.withUnsafeBufferPointer { VideoFormatDetection.sampleLuma(bgra:$0,width:w,height:h,bytesPerRow:stride) }
        XCTAssertEqual(sample.count,128*64)
        XCTAssertTrue(sample.allSatisfy { abs($0-0.5)<0.001 })
        XCTAssertNil(VideoFormatDetection.packing(luma:sample,width:128,height:64))
        bytes.withUnsafeBufferPointer {
            XCTAssertTrue(VideoFormatDetection.sampleLuma(bgra:$0,width:w,height:h,bytesPerRow:w*4-1).isEmpty)
            XCTAssertTrue(VideoFormatDetection.sampleLuma(bgra:$0,width:w,height:h+100,bytesPerRow:stride).isEmpty)
        }
    }
    func testPageVRCueDoesNotAssertFormatAndSurvivesWithoutURL() throws {
        let cue = VideoFormatDetection.persistentHint(source: "https://cdn.example/opaque.mp4", title: "Video", pageURL: "https://site.example/vr-porn-video/clip")
        XCTAssertEqual(cue?.evidence, .context)
        XCTAssertNil(cue?.projection); XCTAssertNil(cue?.layout)
        let data = try JSONEncoder().encode(cue)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("site.example"))
        XCTAssertEqual(try JSONDecoder().decode(VideoFormatHint?.self, from: data), cue)
        for page in ["https://vr.example/watch?vr180=true", "https://vr.example/watch#vr", "http://site.example/vr/test", "https://user:pass@site.example/vr/test"] {
            XCTAssertNil(VideoFormatDetection.persistentHint(source:"https://cdn.example/opaque.mp4", title:"Video", pageURL:page))
        }
        XCTAssertEqual(VideoFormatDetection.persistentHint(source:"https://cdn.example/vr180-sbs.mp4", title:"Video", pageURL:"")?.evidence, .filename)
    }

}
