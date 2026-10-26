import AVFoundation
import RealityKit
import XCTest
@testable import VisionStream

/// Explicitly supplied, browser-observed preview assets only. No page extraction,
/// credential import, invented renditions or denied-origin destinations.
@MainActor final class PublicPreviewAcceptanceTests: XCTestCase {
    func testVRBangersPublicPreview() async throws { try await check("vrBangers", host: "mov.vrbangers.com") }
    func testVirtualRealPublicTrailer() async throws { try await check("virtualReal", host: "virtualrealporn.com") }
    func testSexLikeRealPublicPreview() async throws { try await check("slr", host: "cdn-vr.sexlikereal.com") }

    func testPublicPageFinderAvailability() async throws { try await checkFinder(inspect: true) }
    func testPublicPageFinderBeforeNativeQualityInspection() async throws { try await checkFinder(inspect: false) }

    private func checkFinder(inspect: Bool) async throws {
        guard let raw = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_PUBLIC_PREVIEWS"], raw.utf8.count <= 65_536 else { throw XCTSkip("Opt into the observed public-page checks") }
        let enabled = Set(try JSONDecoder().decode([String: [Input]].self, from: Data(raw.utf8)).keys)
        // These exact pages were inspected through the browser before this probe.
        let pages = [("vrBangers", "https://vrbangers.com/video/make-it-spicy/"),
                     ("virtualReal", "https://virtualrealporn.com/vr-porn-video/after-the-film/"),
                     ("slr", "https://www.sexlikereal.com/scenes/blind-with-you-101540")]
        var records: [[String: Any]] = []
        for (site, address) in pages where enabled.contains(site) {
            do {
                let result: ExtractedMedia
                if inspect { result = try await OnDeviceExtractor.shared.resolve(address) }
                else { result = try await OnDeviceExtractor.shared.resolveUninspected(address) }
                let expectedHost = site == "virtualReal" ? "virtualrealporn.com" : (site == "vrBangers" ? "mov.vrbangers.com" : "cdn-vr.sexlikereal.com")
                records.append(["site": site, "status": "resolved", "streams": result.streams.map {
                    ["width": $0.candidate.width, "height": $0.candidate.height,
                     "mimeType": $0.candidate.mimeType, "withinProviderMediaHosts": URL(string: $0.candidate.source)?.host == expectedHost || URL(string: $0.candidate.source)?.host?.hasSuffix("." + expectedHost) == true, "unavailableCode": $0.unavailableCode,
                     "advisoryCode": $0.advisoryCode, "adaptive": $0.isAdaptive] as [String: Any]
                }])
                for (index, stream) in result.streams.enumerated() where stream.unavailableReason == nil {
                    guard let host = URL(string: stream.candidate.source)?.host,
                          !["pornhub.com", "badoinkvr.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { continue }
                    // The source is supplied by this exact public page and may
                    // now be its server-resolved CDN destination. No URLs are guessed.
                    let title = site == "vrBangers" ? "Make It Spicy VR Porn Video: 8K, 4K, Full HD and 180/360 POV | VR Bangers" : (site == "virtualReal" ? "After the Film | VirtualRealPorn" : "Blind With You | SexLikeReal")
                    let contextual = stream.candidate.withBrowserFormatContext(page: URL(string: address), title: title, candidates: [])
                    try await probe(site + (inspect ? "-finder-" : "-raw-finder-") + String(index), candidate: contextual)
                }
            } catch {
                let status: String
                if case ExtractionError.status(let value) = error { status = value } else { status = "runtime-or-invalid-result" }
                records.append(["site": site, "status": status, "streams": []])
                XCTFail("Public page finder did not resolve supported sources; see redacted finder report")
            }
        }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VisionStreamPublicPreviewTests")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report: [String: Any] = ["runtime": ProcessInfo.processInfo.operatingSystemVersionString,
                                  "scope": "Ordinary public page finder; no browser cookies, synthetic access state or downloads",
                                  "sites": records, "privacy": "No page/media URLs or request information included"]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: directory.appendingPathComponent(inspect ? "finder.json" : "finder-raw.json"), options: .atomic)
    }

    func testPublicRangeResponseHeaders() async throws {
        guard let raw = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_PUBLIC_PREVIEWS"],
              try JSONDecoder().decode([String: [Input]].self, from: Data(raw.utf8))["virtualReal"] != nil else { throw XCTSkip("Opt into the public VirtualRealPorn protocol probe") }
        let agent = await NativeStreamInspector.browserUserAgent()
        XCTAssertNotNil(agent)
        let media = try await OnDeviceExtractor.shared.resolveUninspected("https://virtualrealporn.com/vr-porn-video/after-the-film/")
        var rows: [[String: Any]] = []
        for (index, stream) in media.streams.enumerated() where stream.unavailableReason == nil {
            guard let url = URL(string: stream.candidate.source), url.host == "virtualrealporn.com" else { continue }
            do {
                let response = try await PreviewRangeHeaders().load(url, agent: agent)
                rows.append(["index": index, "response": try JSONSerialization.jsonObject(with: JSONEncoder().encode(response))])
            } catch { rows.append(["index": index, "failureCodes": PlaybackDiagnostics.failure(error)]) }
        }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VisionStreamPublicPreviewTests")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["runtime": ProcessInfo.processInfo.operatingSystemVersionString,
            "scope": "Public GET bytes=0-1 response headers only; body cancelled; no cookies", "browserUserAgentApplied": agent != nil, "rows": rows], options: [.sortedKeys])
            .write(to: directory.appendingPathComponent("range-responses.json"), options: .atomic)
        XCTAssertFalse(rows.isEmpty)
    }

    private struct Input: Decodable { let source: String }
    private func wait(seconds: Double, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() { guard Date() < deadline else { throw URLError(.timedOut) }; try await Task.sleep(for: .milliseconds(50)) }
    }
    private func check(_ site: String, host: String) async throws {
        guard let raw = ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_PUBLIC_PREVIEWS"], raw.utf8.count <= 65_536 else { throw XCTSkip("Opt into browser-observed public preview acceptance") }
        let inputs = try JSONDecoder().decode([String: [Input]].self, from: Data(raw.utf8))
        guard let input = inputs[site]?.first else { throw XCTSkip("No observed preview supplied for this site") }
        let url = try XCTUnwrap(URL(string: input.source))
        guard input.source.utf8.count <= 16_384, url.scheme == "https", url.host == host,
              url.user == nil, url.password == nil, url.fragment == nil else { throw URLError(.badURL) }
        try await probe(site, candidate: MediaCandidate(id: site, source: input.source, mimeType: "video/mp4", title: "Public VR preview"))
    }
    private func probe(_ site: String, candidate: MediaCandidate) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PublicPreview-" + UUID().uuidString).resolvingSymlinksInPath()
        let downloads = DownloadModel(root: root), playback = PlaybackModel(automaticallyDetectFormat: true)
        playback.player.isMuted = true
        var renderer: ImmersiveRenderer?
        var report: [String: Any] = ["site": site, "schemaVersion": 1, "source": site.contains("-finder-") ? "ordinary public page finder; URL omitted" : "browser-observed public preview; URL omitted", "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown", "runtime": ProcessInfo.processInfo.operatingSystemVersionString, "highestClaim": "Only the supplied observed public source is tested; member maximum is unverified.", "webpageHandoff": "Not tested by this component probe", "streamDecoded": false, "downloadSaved": false, "localDecoded": false]
        defer {
            renderer?.stop(); playback.stop(); downloads.cancel()
            try? FileManager.default.removeItem(at: root)
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VisionStreamPublicPreviewTests")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: directory.appendingPathComponent(site + ".json"), options: .atomic)
            } catch { XCTFail("Public preview report could not be written") }
        }
        let agent = await NativeStreamInspector.browserUserAgent()
        XCTAssertNotNil(agent)
        let ready = await playback.prepare(candidate, cookies: [], userAgent: agent)
        report["preparationReady"] = ready
        if ready {
            do {
                renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
                try await renderer?.start()
                try await wait(seconds: 20) { playback.decodedWidth > 0 && playback.elapsed > 0.5 }
                // Give image/metadata format detection several textured frames.
                try await Task.sleep(for: .seconds(5))
                report["streamDecoded"] = true; report["decodedWidth"] = playback.decodedWidth; report["decodedHeight"] = playback.decodedHeight
                report["automaticPresentation"] = playback.presentation.rawValue; report["automaticLayout"] = playback.layout.rawValue
                report["formatStatus"] = playback.formatStatus; report["qualityStatus"] = playback.qualityStatus
                playback.pause()
                try await Task.sleep(for: .milliseconds(300))
                let position = playback.player.currentTime().seconds
                try await Task.sleep(for: .milliseconds(400))
                let pauseHeld = abs(playback.player.currentTime().seconds - position) < 0.1
                report["pauseHeld"] = pauseHeld; XCTAssertTrue(pauseHeld)
                if playback.seekEnd > playback.seekStart { playback.seek(to: min(playback.seekEnd, playback.seekStart + 2)); try await wait(seconds: 10) { !playback.isSeeking }; let sought = abs(playback.player.currentTime().seconds - min(playback.seekEnd, playback.seekStart + 2)) < 0.3; report["seekCompleted"] = sought; XCTAssertTrue(sought) }
            } catch { report["decodeOrTransportFailed"] = true; XCTFail("Public preview did not decode or complete transport checks") }
        } else { XCTFail("Native preparation rejected the observed public preview; see redacted component report") }
        report["playbackReport"] = try? JSONSerialization.jsonObject(with: Data(PlaybackDiagnostics.report(version: "component-test", runtime: ProcessInfo.processInfo.operatingSystemVersionString, pageHTTPStatus: nil, pageFailure: [], candidates: [], playbackStage: playback.diagnosticStage, playbackFailure: playback.failureCodes, mediaHTTPStatus: playback.mediaHTTPStatus, projection: playback.projection, layout: playback.layout, attemptedMedia: playback.diagnosticCandidate, presentation: playback.presentation, decodedWidth: playback.decodedWidth, decodedHeight: playback.decodedHeight, failureReason: playback.failureReason, itemStatus: playback.itemStatusAtFailure, errorLogCodes: playback.errorLogCodes, browserUserAgentApplied: playback.browserUserAgentApplied, quality: playback.quality, automaticFormat: playback.automaticallyDetectFormat).utf8))
        renderer?.stop(); renderer = nil; playback.stop()
        downloads.start(candidate, cookies: [], userAgent: agent)
        do { try await wait(seconds: 120) { !downloads.isDownloading } }
        catch { downloads.cancel(); report["downloadTimedOut"] = true; XCTFail("Public preview download exceeded the acceptance deadline") }
        report["downloadFailureCode"] = downloads.failureCode
        guard let saved = downloads.videos.first else { report["downloadStatus"] = "failed"; XCTFail("Public preview download did not save a playable file"); return }
        report["downloadSaved"] = true; report["savedBytes"] = saved.bytes
        let localReady = await playback.prepareSavedVideo(saved, store: downloads.store)
        guard localReady else { XCTFail("Saved preview could not be reopened"); return }
        renderer = try ImmersiveRenderer(playback: playback, controls: Entity())
        try await renderer?.start()
        do { try await wait(seconds: 20) { playback.decodedWidth > 0 }; report["localDecoded"] = true; report["localWidth"] = playback.decodedWidth; report["localHeight"] = playback.decodedHeight; try await Task.sleep(for: .seconds(4)); report["localPresentation"] = playback.presentation.rawValue; report["localLayout"] = playback.layout.rawValue }
        catch { XCTFail("Saved preview did not produce local renderer frames") }
    }
}

private final class PreviewRangeHeaders: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Report: Codable, Sendable { let status: Int; let contentLength: Int64; let rangeHonored: Bool; let rangeFieldPresent: Bool; let mimeType: String; let contentEncoding: String }
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Report, Error>?
    private var session: URLSession?
    private var agent: String?
    private var redirects = 0
    func load(_ url: URL, agent: String?) async throws -> Report {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); defer { lock.unlock() }
            self.continuation = continuation; self.agent = agent
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 8
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil); self.session = session
            session.dataTask(with: request(url)).resume()
        }
    }
    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        if let agent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        return request
    }
    private func finish(_ value: Result<Report, Error>) {
        lock.lock(); let continuation = continuation; self.continuation = nil; let session = session; self.session = nil; lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: value)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.cancel)
        guard let http = response as? HTTPURLResponse else { finish(.failure(URLError(.badServerResponse))); return }
        let range = http.value(forHTTPHeaderField: "Content-Range")?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let honored = http.statusCode == 206 && range?.range(of: #"^bytes 0-1/[0-9]+$"#, options: .regularExpression) != nil
        let mime = http.mimeType?.lowercased() ?? ""
        let encoding = http.value(forHTTPHeaderField: "Content-Encoding")?.lowercased() ?? "identity"
        finish(.success(.init(status: http.statusCode, contentLength: http.expectedContentLength, rangeHonored: honored, rangeFieldPresent: range != nil,
            mimeType: ["video/mp4", "application/octet-stream", "text/html"].contains(mime) ? mime : "other",
            contentEncoding: ["identity", "gzip", "br"].contains(encoding) ? encoding : "other")))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(.failure(error ?? URLError(.badServerResponse))) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest next: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        redirects += 1
        guard let url = next.url, url.scheme == "https", url.user == nil, url.password == nil, redirects <= 10 else { completionHandler(nil); return }
        completionHandler(request(url))
    }
}
