import Foundation

/// Foreground compatibility transport. Downloads only after an explicit Save;
/// all URIs are published by the server and all authentication uses normal scope.
@MainActor enum ClearHLSDownloadTransfer {
    enum Failure:Error { case unsupported,http(Int,Int?),storage }
    static func run(media:MediaCandidate,input:URL,output:URL,cookies:[HTTPCookie],userAgent:String?,cookieProvider:(@MainActor (URL) async -> [HTTPCookie])?,history:SessionDiagnostics?,context:DiagnosticContext?,progress:@escaping @MainActor (Int64,Int,Int)->Void) async throws -> Double {
        guard HLSOfflineLibrary.accepts(media),let source=URL(string:media.source),source.scheme=="https" else { throw Failure.unsupported }
        var jars:[HLSQualityRequest]=[],issued:[HTTPCookie]=[]
        func scoped(_ url:URL) async -> [HTTPCookie] {
            var values=CookieScope.matching(await cookieProvider?(url) ?? cookies,url:url)
            for cookie in jars.flatMap({ $0.cookies(for:url) })+CookieScope.matching(issued,url:url) {
                values.removeAll { $0.name==cookie.name && $0.domain==cookie.domain && $0.path==cookie.path };values.append(cookie)
            }
            return values
        }
        func request(_ url:URL,cookies:[HTTPCookie]) -> URLRequest {
            var result=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData)
            for (key,value) in HTTPCookie.requestHeaderFields(with:cookies) { result.setValue(value,forHTTPHeaderField:key) }
            if let userAgent,!userAgent.isEmpty,userAgent.utf8.count<=1024,userAgent.rangeOfCharacter(from:.controlCharacters)==nil { result.setValue(userAgent,forHTTPHeaderField:"User-Agent") }
            return result
        }
        func playlist(_ url:URL) async throws -> Data {
            let probe=HLSQualityRequest()
            var data:Data?,failure:Error?
            do { data=try await probe.load(request(url,cookies:await scoped(url))) }
            catch { failure=error }
            var related=context;related?.resource=DiagnosticResource(url);related?.mediaID=history?.reference(url.absoluteString)
            var numbers:[String:Double]=[:]
            if let status=probe.responseSummary?.status { numbers["httpStatus"]=Double(status) }
            history?.record(.transferMetrics,context:related,labels:["phase":"foreground-hls-playlist","requestMode":"foreground-get","resourceRole":"playlist"],numbers:numbers,codes:PlaybackDiagnostics.failure(failure))
            if let status=probe.responseSummary?.status,status != 200 { throw Failure.http(status,nil) }
            if let failure { throw failure }
            guard let data else { throw Failure.unsupported }
            jars.append(probe)
            return data
        }
        let first=try await playlist(source),graph=try HLSManifest(data:first,base:source)
        let data:Data,base:URL
        if !graph.variants.isEmpty {
            guard let best=graph.highestIndependentVariant else { throw Failure.unsupported }
            base=best.url;data=try await playlist(base)
            history?.record(.quality,context:context,labels:["phase":"foreground-save-rendition","quality":"highest"],numbers:["width":Double(best.width),"height":Double(best.height)])
        } else { base=source;data=first }
        let plan=try ClearHLSPlan(data:data,base:base)
        let reserve:Int64=512*1024*1024
        let free=(try FileManager.default.attributesOfFileSystem(forPath:input.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free>reserve+1024*1024 else { throw Failure.storage }
        // The temporary TS and resulting MP4 coexist. Reserve space for both.
        let limit=min(OfflineVideoStore.maximumFileBytes,(free-reserve)/2)
        guard FileManager.default.createFile(atPath:input.path,contents:nil) else { throw CocoaError(.fileWriteUnknown) }
        let fragment=input.deletingPathExtension().appendingPathExtension("part")
        defer { try? FileManager.default.removeItem(at:fragment) }
        var received:Int64=0
        for (ordinal,segment) in plan.segments.enumerated() {
            try Task.checkCancellation()
            guard received<limit else { throw Failure.storage }
            let already=received,segmentCookies=await scoped(segment.url)
            var related=context;related?.resource=DiagnosticResource(segment.url);related?.mediaID=history?.reference(segment.url.absoluteString)
            let relatedContext=related
            let transfer=MP4DownloadTransfer(staging:fragment,origin:segment.url,maximumBytes:min(512*1024*1024,limit-received),reserveBytes:reserve,payload:.transportStream,diagnostic: { resource,labels,numbers in
                Task { @MainActor in
                    var record=relatedContext
                    if let resource { record?.resource=DiagnosticResource(resource);record?.mediaID=history?.reference(resource.absoluteString) }
                    var values=numbers;values["resourceIndex"]=Double(segment.index)
                    var fields=labels;fields["requestMode"]="foreground-get";fields["resourceRole"]="segment"
                    history?.record(.transferMetrics,context:record,labels:fields,numbers:values)
                }
            }) { bytes,_ in
                Task { @MainActor in progress(already+bytes,ordinal+1,plan.segments.count) }
            }
            do { _ = try await transfer.run(request(segment.url,cookies:[]),cookies:segmentCookies) }
            catch MP4DownloadTransfer.TransferError.http(let status) { throw Failure.http(status,segment.index) }
            for cookie in transfer.responseCookies() {
                issued.removeAll { $0.name==cookie.name && $0.domain==cookie.domain && $0.path==cookie.path };issued.append(cookie)
            }
            issued=Array(issued.suffix(256))
            received += try await append(fragment,to:input,maximum:limit)
            try FileManager.default.removeItem(at:fragment)
            progress(received,ordinal+1,plan.segments.count)
        }
        try Task.checkCancellation()
        let remaining=(try FileManager.default.attributesOfFileSystem(forPath:input.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard remaining>received+reserve else { throw Failure.storage }
        history?.record(.transfer,context:context,labels:["phase":"remuxing-local-media"],numbers:["receivedBytes":Double(received)])
        try await MediaRemux.convert(input:input,output:output,maximumBytes:OfflineVideoStore.maximumFileBytes)
        try FileManager.default.removeItem(at:input)
        return plan.duration
    }
    private static func append(_ source:URL,to destination:URL,maximum:Int64) async throws -> Int64 {
        let task=Task.detached(priority:.utility) {
            let read=try FileHandle(forReadingFrom:source),write=try FileHandle(forWritingTo:destination)
            defer { try? read.close();try? write.close() }
            let start=try write.seekToEnd()
            var copied:Int64=0
            while let data=try read.read(upToCount:1024*1024),!data.isEmpty {
                try Task.checkCancellation();copied += Int64(data.count)
                guard start+UInt64(copied)<=UInt64(maximum) else { throw Failure.storage }
                try write.write(contentsOf:data)
            }
            try Task.checkCancellation();return copied
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
