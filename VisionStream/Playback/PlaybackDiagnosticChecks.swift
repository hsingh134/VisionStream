import AVFoundation

/// Explicit user-requested checks of the exact current source. No URL guessing,
/// header spoofing, audio playback, movie download or changes to the web player.
@MainActor enum PlaybackDiagnosticChecks {
    static func run(media: MediaCandidate, cookies: [HTTPCookie], userAgent: String?, history: SessionDiagnostics, context: DiagnosticContext) async {
        guard history.isTestingEnabled, let url=URL(string:media.source), media.compatibility == .candidate else { return }
        var details=TestingDiagnosticDetails();details.role="cookie-snapshot";details.url=url.absoluteString
        details.cookieMetadata=cookies.map(TestingCookieMetadata.init)
        history.record(.testingCheck,context:context,labels:["phase":"check-cookie-snapshot"],numbers:["cookieCount":Double(cookies.count)],testing:details)
        var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData)
        for (key,value) in HTTPCookie.requestHeaderFields(with:CookieScope.matching(cookies,url:url)) { request.setValue(value,forHTTPHeaderField:key) }
        if let userAgent,userAgent.utf8.count<=1024,userAgent.rangeOfCharacter(from:.controlCharacters)==nil { request.setValue(userAgent,forHTTPHeaderField:"User-Agent") }
        let hls=media.normalizedMIMEType.contains("mpegurl") || url.pathExtension.lowercased()=="m3u8"
        if !hls { request.setValue("bytes=0-\(MP4SphericalMetadata.maximumPrefixBytes-1)",forHTTPHeaderField:"Range") }
        let probe=HLSQualityRequest(kind:hls ? .master:.mp4Prefix,timeout:8,diagnosticObserver:history.testingObserver(context:context,phase:"active-source-check"))
        var codes:[String]=[];var body:Data?
        do { body=try await probe.load(request) } catch { codes=PlaybackDiagnostics.failure(error) }
        guard !Task.isCancelled,history.isTestingEnabled else { return }
        var values:[String:Double]=[:]
        if let summary=probe.responseSummary { values["httpStatus"]=Double(summary.status);values["expectedBytes"]=Double(summary.expectedBytes) }
        if let body { values["receivedBytes"]=Double(body.count) }
        history.record(.testingCheck,context:context,labels:["phase":"active-source-check-completed","status":body == nil ? "failed":"received"],numbers:values,codes:codes)

        // Unlike the production asset-property preflight, this prepares a paused
        // AVPlayerItem so public item errors/metrics may expose a failing resource.
        // Readiness is not proof of decoded or visible playback.
        var nativeCookies=CookieScope.matching(cookies,url:url)
        for cookie in probe.cookies(for:url) { nativeCookies.removeAll { $0.name==cookie.name && $0.domain==cookie.domain && $0.path==cookie.path };nativeCookies.append(cookie) }
        var options:[String:Any]=[AVURLAssetHTTPCookiesKey:nativeCookies]
        if let userAgent,userAgent.utf8.count<=1024,userAgent.rangeOfCharacter(from:.controlCharacters)==nil { options[AVURLAssetHTTPUserAgentKey]=userAgent }
        let asset=AVURLAsset(url:url,options:options),item=AVPlayerItem(asset:asset),player=AVPlayer()
        player.isMuted=true
        let metricTask=Task { @MainActor in
            do { for try await event in item.allMetrics() { guard !Task.isCancelled else { return }; NativeDiagnosticMetrics.record(event,history:history,context:context) } }
            catch { /* Item status and numeric error codes are recorded below. */ }
        }
        defer { metricTask.cancel();player.pause();player.replaceCurrentItem(with:nil);asset.cancelLoading() }
        player.replaceCurrentItem(with:item)
        let deadline=ProcessInfo.processInfo.systemUptime+10
        while item.status == .unknown,ProcessInfo.processInfo.systemUptime<deadline,!Task.isCancelled,history.isTestingEnabled {
            do { try await Task.sleep(for:.milliseconds(50)) } catch { return }
        }
        guard !Task.isCancelled,history.isTestingEnabled else { return }
        let status=item.status == .readyToPlay ? "ready-without-playback" : (item.status == .failed ? "failed":"timed-out")
        var native=TestingDiagnosticDetails();native.role="paused-native-probe";native.url=url.absoluteString
        history.record(.testingCheck,context:context,labels:["phase":"paused-native-check-completed","status":status],numbers:["rate":Double(player.rate),"width":Double(item.presentationSize.width),"height":Double(item.presentationSize.height)],codes:PlaybackDiagnostics.failure(item.error),testing:native)
        NativeDiagnosticMetrics.recordFailureResources(item.error,item:item,history:history,context:context)
    }
}
