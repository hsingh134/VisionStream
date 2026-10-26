import Foundation

/// Diagnostics for a user-initiated failed save. Reads published playlists and
/// requests headers of a bounded sample of their actual resources. No guessed
/// paths, playlist rewriting, redirects, key retrieval or whole media bodies.
@MainActor enum HLSResourceInspector {
    struct Finding: Sendable {
        let role:String
        let index:Int
        let status:Int
    }
    static func inspect(source:URL,selected:[URL],cookies:[HTTPCookie],userAgent:String?,cookieProvider:(@MainActor (URL) async -> [HTTPCookie])? = nil,history:SessionDiagnostics?,context:DiagnosticContext?) async -> [Finding] {
        let deadline=Date().addingTimeInterval(25)
        var findings:[Finding]=[],probes=0,issued:[HTTPCookie]=[]
        func request(_ url:URL,headersOnly:Bool,scoped:[HTTPCookie]) -> URLRequest {
            var result=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData)
            var matching=CookieScope.matching(scoped,url:url)
            for cookie in CookieScope.matching(issued,url:url) {
                matching.removeAll { $0.name==cookie.name && $0.domain==cookie.domain && $0.path==cookie.path };matching.append(cookie)
            }
            for (key,value) in HTTPCookie.requestHeaderFields(with:matching) { result.setValue(value,forHTTPHeaderField:key) }
            if let userAgent,!userAgent.isEmpty,userAgent.utf8.count<=1024,userAgent.rangeOfCharacter(from:.controlCharacters)==nil { result.setValue(userAgent,forHTTPHeaderField:"User-Agent") }
            if headersOnly { result.setValue("bytes=0-1",forHTTPHeaderField:"Range") }
            return result
        }
        func check(_ url:URL,role:String,index:Int,headersOnly:Bool) async -> Data? {
            guard !Task.isCancelled,Date()<deadline,probes<12,url.scheme=="https",url.user==nil,url.password==nil else { return nil }
            probes += 1
            let probe=HLSQualityRequest(kind:headersOnly ? .resourceHeaders:.master)
            var data:Data?,codes:[String]=[]
            let scoped=await cookieProvider?(url) ?? cookies
            do { data=try await probe.load(request(url,headersOnly:headersOnly,scoped:scoped)) }
            catch { codes=PlaybackDiagnostics.failure(error) }
            guard !Task.isCancelled else { return nil }
            let status=probe.responseSummary?.status ?? 0
            findings.append(.init(role:role,index:index,status:status))
            var related=context;related?.resource=DiagnosticResource(url);related?.mediaID=history?.reference(url.absoluteString)
            history?.record(.transferMetrics,context:related,labels:["phase":"offline-resource-check","resourceRole":role,"requestMode":headersOnly ? "foreground-range-headers":"foreground-playlist","method":"GET"],numbers:["resourceIndex":Double(index),"httpStatus":Double(status),"expectedBytes":Double(probe.responseSummary?.expectedBytes ?? -1)],codes:codes)
            // Normal cookie scope is enforced by the isolated URLSession jar.
            // Values never enter diagnostics or persistent application storage.
            for cookie in probe.cookies(for:url) {
                issued.removeAll { $0.name==cookie.name && $0.domain==cookie.domain && $0.path==cookie.path };issued.append(cookie)
            }
            return data
        }
        guard let data=await check(source,role:"sourcePlaylist",index:0,headersOnly:false),let master=try? HLSManifest(data:data,base:source) else { return findings }
        let chosen=selected.first ?? master.highestIndependentVariant?.url
        var resources=master.resources
        if let chosen,chosen != source,
           let child=await check(chosen,role:"selectedPlaylist",index:0,headersOnly:false),let media=try? HLSManifest(data:child,base:chosen) {
            resources += media.resources
        }
        let dependencies=resources.filter { [.audioPlaylist,.subtitlePlaylist,.iframePlaylist,.initialization].contains($0.role) }
        let segments=resources.filter { $0.role == .segment }
        var sample=Array(dependencies.prefix(3))+Array(segments.prefix(3))
        for index in [segments.count/2,segments.count-1] where index>=0 && index<segments.count { sample.append(segments[index]) }
        var checked=Set<URL>()
        for resource in sample where checked.insert(resource.url).inserted {
            _ = await check(resource.url,role:resource.role.rawValue,index:resource.index,headersOnly:true)
        }
        history?.record(.transferMetrics,context:context,labels:["phase":"offline-resource-check-finished","requestMode":"foreground-availability-only"],numbers:["inspectedResources":Double(findings.count),"resourceCount":Double(resources.count)])
        return findings
    }
}
