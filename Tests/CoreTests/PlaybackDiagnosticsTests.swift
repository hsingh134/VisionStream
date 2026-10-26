import Foundation
#if canImport(XCTest) && !VISIONSTREAM_STANDALONE
import XCTest
#endif
#if canImport(VisionStream)
@testable import VisionStream
#elseif !VISIONSTREAM_STANDALONE
@testable import VisionStreamCore
#endif

final class PlaybackDiagnosticsTests: XCTestCase {
    func testDownloadFailureCodesAreSharedWithoutPrivateErrorText() throws {
        let text = PlaybackDiagnostics.report(version: "test", runtime: "test", pageHTTPStatus: nil,
            pageFailure: [], candidates: [], playbackStage: "not-attempted", playbackFailure: [],
            mediaHTTPStatus: nil, projection: .vr180, layout: .mono,
            hlsDownloadFailureCodes: ["NSURLErrorDomain:-1200", "CoreMediaErrorDomain:-12938", "https://private.example/token", "PRIVATE_DOMAIN:7"])
        let report = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(report["hlsDownloadFailureCodes"] as? [String], ["NSURLErrorDomain:-1200", "CoreMediaErrorDomain:-12938"])
        XCTAssertFalse(text.contains("private.example")); XCTAssertFalse(text.contains("PRIVATE_DOMAIN"))
    }
    func testTimeoutAndWebsiteMediaDiagnosticsAreExplicitAndPrivate() throws {
        let events = (0..<20).map { (domain: "PRIVATE_SIGNED_URL", code: $0) }
        let codes = PlaybackDiagnostics.errorLogCodes(events)
        XCTAssertEqual(codes.count, 8)
        XCTAssertEqual(codes.first, "OtherErrorDomain:12")
        XCTAssertFalse(codes.joined().contains("PRIVATE"))
        XCTAssertEqual(PlaybackDiagnostics.errorLogCodes([(domain: "CoreMediaErrorDomain", code: -12938)]), ["CoreMediaErrorDomain:-12938"])
        XCTAssertEqual(PlaybackDiagnostics.httpErrorStatus(domain: "HTTP", code: 403), 403)
        XCTAssertNil(PlaybackDiagnostics.httpErrorStatus(domain: "CoreMediaErrorDomain", code: 404))
        XCTAssertNil(PlaybackDiagnostics.httpErrorStatus(domain: "HTTP", code: 200))
        XCTAssertNil(PlaybackDiagnostics.webFailureHint(0))
        XCTAssertNil(PlaybackDiagnostics.webFailureHint(99))
        XCTAssertTrue(PlaybackDiagnostics.webFailureHint(2)?.contains("network") == true)
        XCTAssertTrue(PlaybackDiagnostics.webFailureHint(3)?.contains("decoding") == true)
        XCTAssertTrue(PlaybackDiagnostics.webFailureHint(4)?.contains("does not identify") == true)
        let media = MediaCandidate(id: "private", source: "blob:https://private.example/token", formatHint: .init(layout: .mono, evidence: .metadata), webMedia:
            .init(errorCode: 2, readyState: 0, networkState: 3, paused: true))
        let text = PlaybackDiagnostics.report(version: "test", runtime: "test", pageHTTPStatus: 200,
            pageFailure: [], candidates: [media], playbackStage: "failed-at-waiting-for-player",
            playbackFailure: [], mediaHTTPStatus: nil, projection: .vr180, layout: .mono,
            failureReason: .preparationTimeout, itemStatus: .unknown, errorLogCodes: codes, browserUserAgentApplied: true)
        let report = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(report["playbackFailureReason"] as? String, "preparationTimeout")
        XCTAssertEqual(report["playerItemStatusAtFailure"] as? String, "unknown")
        XCTAssertEqual(report["browserUserAgentApplied"] as? Bool, true)
        XCTAssertTrue((report["playbackFailureCodes"] as? [String])?.isEmpty == true)
        let detected = try XCTUnwrap(report["detectedMedia"] as? [[String: Any]])
        let hint = try XCTUnwrap(detected.first?["formatHint"] as? [String: String])
        XCTAssertEqual(hint, ["projection":"unspecified", "layout":"mono", "evidence":"metadata"])
        let web = try XCTUnwrap(detected.first?["webMedia"] as? [String: Any])
        XCTAssertEqual(web["errorCode"] as? Int, 2)
        XCTAssertEqual(web["readyState"] as? Int, 0)
        XCTAssertEqual(web["networkState"] as? Int, 3)
        XCTAssertEqual(web["paused"] as? Bool, true)
        XCTAssertFalse(text.contains("private.example"))
        // Missing website state stays absent for extractor/manual candidates.
        let legacy = try JSONDecoder().decode(MediaCandidate.self, from: Data("""
            {"id":"1","videoID":"","source":"https://example.com/a.mp4","mimeType":"","title":"","pageURL":"","encrypted":false,"width":0,"height":0,"currentTime":0}
            """.utf8))
        XCTAssertNil(legacy.webMedia)
    }

    func testMissingResourceHintDoesNotInventHTTPStatusOrExposeDetails() {
        let nested = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist,
                             userInfo: [NSLocalizedDescriptionKey: "PRIVATE_SIGNED_URL"])
        let wrapper = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                              userInfo: [NSUnderlyingErrorKey: nested])
        let hint = PlaybackDiagnostics.failureHint(wrapper)
        XCTAssertTrue(hint?.contains("reported as missing") == true)
        XCTAssertTrue(hint?.contains("Find streams") == true)
        XCTAssertTrue(hint?.contains("MP4") == true)
        XCTAssertFalse(hint?.contains("404") == true)
        XCTAssertFalse(hint?.contains("PRIVATE_SIGNED_URL") == true)
        XCTAssertNil(PlaybackDiagnostics.failureHint(NSError(domain: "CoreMediaErrorDomain", code: -12938)))
        XCTAssertNil(PlaybackDiagnostics.failureHint(NSError(domain: NSURLErrorDomain, code: -1009)))
    }
    func testReportOmitsSensitiveCandidateAndErrorData() {
        let secret = "PRIVATE_TOKEN_DO_NOT_SHARE"
        let nested = NSError(domain: NSURLErrorDomain, code: -1011, userInfo: [NSLocalizedDescriptionKey: secret])
        let failure = NSError(domain: secret, code: 7, userInfo: [NSUnderlyingErrorKey: nested, "URL": secret])
        let candidate = MediaCandidate(id: secret, videoID: secret,
            source: "https://\(secret).example/\(secret).mp4?token=\(secret)#\(secret)",
            mimeType: secret, title: secret, pageURL: secret)
        let report = PlaybackDiagnostics.report(version: "0.2.2", runtime: "test", pageHTTPStatus: 403,
            pageFailure: PlaybackDiagnostics.failure(failure), candidates: [candidate],
            playbackStage: "not-attempted", playbackFailure: [], mediaHTTPStatus: nil,
            projection: .vr180, layout: .sideBySide, attemptedMedia: candidate)
        XCTAssertFalse(report.contains(secret))
        XCTAssertFalse(report.contains("https://"))
        XCTAssertTrue(report.contains("403"))
        XCTAssertTrue(report.contains("OtherErrorDomain:7"))
        XCTAssertTrue(report.contains("NSURLErrorDomain:-1011"))
        XCTAssertFalse(report.contains("unspecified"))
    }

    func testReportClassifiesFormatsWithoutClaimingPlayback() throws {
        let candidates = [
            MediaCandidate(id: "1", source: "blob:https://site.example/secret"),
            MediaCandidate(id: "2", source: "https://cdn.example/secret.m3u8", mimeType: "application/vnd.apple.mpegurl", encrypted: true),
            MediaCandidate(id: "3", source: "https://cdn.example/secret.mp4", width: 3840, height: 1920)
        ]
        let report = PlaybackDiagnostics.report(version: "0.2.2", runtime: "test", pageHTTPStatus: 200,
            pageFailure: [], candidates: candidates, playbackStage: "player-ready", playbackFailure: [],
            mediaHTTPStatus: nil, projection: .vr360, layout: .topBottom, attemptedMedia: candidates[1])
        let record = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])
        let media = try XCTUnwrap(record["detectedMedia"] as? [[String: Any]])
        XCTAssertEqual(media.count, 3)
        XCTAssertEqual(media[0]["sourceKind"] as? String, "browser-local")
        XCTAssertEqual(media[0]["nativeCandidate"] as? Bool, false)
        XCTAssertEqual(media[1]["encrypted"] as? Bool, true)
        XCTAssertEqual(media[1]["nativeCandidate"] as? Bool, false)
        XCTAssertEqual(media[2]["nativeCandidate"] as? Bool, true)
        XCTAssertEqual(media[2]["width"] as? Int, 3840)
        XCTAssertEqual(record["projection"] as? String, "vr360")
        XCTAssertEqual(record["layout"] as? String, "topBottom")
        XCTAssertTrue(report.contains("does not verify immersive playback"))
        let attempted = try XCTUnwrap(record["attemptedMedia"] as? [String: Any])
        XCTAssertEqual(attempted["formatExtension"] as? String, "m3u8")
        XCTAssertEqual(attempted["encrypted"] as? Bool, true)
        XCTAssertEqual(candidates[1].displaySource, "cdn.example · HLS (M3U8)")
        XCTAssertEqual(MediaCandidate(id: "4", source: "https://cdn.example/signed?token=secret", mimeType: "video/mp4").displaySource, "cdn.example · MP4")
    }

    func testReportsAreBoundedAndDoNotIncludeUnknownErrorDomains() throws {
        var error = NSError(domain: NSURLErrorDomain, code: -1009)
        for code in 0..<8 { error = NSError(domain: "secret-domain", code: code, userInfo: [NSUnderlyingErrorKey: error]) }
        let codes = PlaybackDiagnostics.failure(error)
        XCTAssertEqual(codes.count, 3)
        XCTAssertFalse(codes.joined().contains("secret-domain"))
        XCTAssertEqual(PlaybackDiagnostics.failure(nil), [])
        let report = PlaybackDiagnostics.report(version: "0.2.2", runtime: "test", pageHTTPStatus: nil,
            pageFailure: codes, candidates: (0..<100).map { MediaCandidate(id: "\($0)", source: "") },
            playbackStage: "not-attempted", playbackFailure: [], mediaHTTPStatus: nil,
            projection: .vr180, layout: .mono)
        let record = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])
        XCTAssertEqual((record["detectedMedia"] as? [[String: Any]])?.count, 16)
        XCTAssertTrue(record["pageHTTPStatus"] is NSNull)
        XCTAssertTrue(record["attemptedMedia"] is NSNull)
    }

    func testServerResponseHintUsesStructuredErrorCodeOnly() {
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11850, userInfo: [NSLocalizedDescriptionKey: "secret signed URL"])
        let hint = PlaybackDiagnostics.failureHint(error)
        XCTAssertTrue(hint?.contains("byte-range") == true)
        XCTAssertFalse(hint?.contains("secret") == true)
        let wrapped = NSError(domain: NSURLErrorDomain, code: -1, userInfo: [NSUnderlyingErrorKey: error])
        XCTAssertEqual(PlaybackDiagnostics.failureHint(wrapped), hint)
        XCTAssertNil(PlaybackDiagnostics.failureHint(NSError(domain: "untrusted", code: -11850)))
        XCTAssertNil(PlaybackDiagnostics.failureHint(NSError(domain: NSURLErrorDomain, code: -1009)))
        XCTAssertNil(PlaybackDiagnostics.failureHint(nil))
    }
    func testSecureConnectionFailureIsDistinctAndRedacted() {
        let failure = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed,
                              userInfo: [NSLocalizedDescriptionKey: "private signed URL and account details"])
        let wrapper = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: failure])
        let hint = PlaybackDiagnostics.failureHint(wrapper) ?? ""
        XCTAssertTrue(hint.contains("secure connection"))
        XCTAssertFalse(hint.contains("private"))
        XCTAssertEqual(hint, PlaybackDiagnostics.failureHint(failure))
        XCTAssertTrue((PlaybackDiagnostics.failureHint(NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)) ?? "").contains("secure connection"))
    }

    func testCoreMediaReportedHTTPStatusRetainsOnlyExplicitBoundedDigits() {
        let error=NSError(domain:"CoreMediaErrorDomain",code:-12938,userInfo:["NSDescription":"HTTP 404: File Not Found https://cdn.example/PRIVATE?token=SECRET"])
        let wrapped=NSError(domain:"AVFoundationErrorDomain",code:-11800,userInfo:[NSUnderlyingErrorKey:error])
        XCTAssertEqual(PlaybackDiagnostics.failure(wrapped),["AVFoundationErrorDomain:-11800","CoreMediaErrorDomain:-12938","HTTP:404"])
        let hint=PlaybackDiagnostics.failureHint(error) ?? ""
        XCTAssertTrue(hint.contains("HTTP 404")); XCTAssertFalse(hint.contains("SECRET")); XCTAssertFalse(hint.contains("PRIVATE"))
        XCTAssertEqual(PlaybackDiagnostics.failure(NSError(domain:"CoreMediaErrorDomain",code:-12938)),["CoreMediaErrorDomain:-12938"])
        for text in ["private URL contains HTTP 404: later", "HTTP 999: invalid", "HTTP 404: "+String(repeating:"x",count:4096)] {
            XCTAssertEqual(PlaybackDiagnostics.failure(NSError(domain:"CoreMediaErrorDomain",code:-12938,userInfo:["NSDescription":text])),["CoreMediaErrorDomain:-12938"])
        }
        XCTAssertEqual(PlaybackDiagnostics.failure(NSError(domain:"UntrustedDomain",code:1,userInfo:["NSDescription":"HTTP 404: false"])),["OtherErrorDomain:1"])
    }
}
