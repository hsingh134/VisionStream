import AVFoundation

/// Public metrics; selected headers and network addresses are captured only
/// in explicit testing mode. No bodies, credential values or error comments.
@MainActor enum NativeDiagnosticMetrics {
    static func record(_ event: AVMetricEvent, history: SessionDiagnostics?, context: DiagnosticContext?) {
        guard let history else { return }
        if let error=event as? AVMetricErrorEvent {
            history.record(.playerError,context:context,labels:["phase":"native-metric-error"],numbers:["recovered":error.didRecover ? 1:0],codes:PlaybackDiagnostics.failure(error.error)); recordFailureResources(error.error,item:nil,history:history,context:context); return
        }
        let resource: AVMetricMediaResourceRequestEvent?
        let phase: String
        if let playlist=event as? AVMetricHLSPlaylistRequestEvent { resource=playlist.mediaResourceRequestEvent; phase=playlist.isMultivariantPlaylist ? "master-playlist":"media-playlist" }
        else if let segment=event as? AVMetricHLSMediaSegmentRequestEvent { resource=segment.mediaResourceRequestEvent; phase="media-segment" }
        else if let request=event as? AVMetricMediaResourceRequestEvent { resource=request; phase="media-resource" }
        else { resource=nil; phase=String(describing:type(of:event)) }
        var related=context
        if let url=resource?.url { related?.resource=DiagnosticResource(url); related?.mediaID=history.reference(url.absoluteString) }
        var values:[String:Double]=[:]
        if let resource {
            values["durationMs"]=max(0,resource.requestEndTime.timeIntervalSince(resource.requestStartTime)*1000)
            // This is the requested byte range, not the response body size.
            // A zero range means no byte-range request was supplied.
            if resource.byteRange.length > 0 { values["requestedRangeBytes"]=Double(resource.byteRange.length) }
            if let metrics=resource.networkTransactionMetrics { transactions(metrics,history:history,context:related,phase:phase) }
        }
        history.record(.transferMetrics,context:related,labels:["phase":phase],numbers:values,codes:PlaybackDiagnostics.failure(resource?.errorEvent?.error))
    }
    static func recordFailureResources(_ error: Error?, item: AVPlayerItem?, history: SessionDiagnostics?, context: DiagnosticContext?) {
        guard let history,history.isTestingEnabled else { return }
        var current=error as NSError?
        for _ in 0..<4 {
            guard let value=current else { break }
            for key in [NSURLErrorFailingURLErrorKey,NSURLErrorFailingURLStringErrorKey] {
                let raw=(value.userInfo[key] as? URL)?.absoluteString ?? (value.userInfo[key] as? String)
                if let raw,let url=TestingDiagnosticDetails.link(raw) {
                    var details=TestingDiagnosticDetails();details.url=url;details.resourceID=history.reference(url)
                    history.record(.testingCheck,context:context,labels:["phase":"native-failure-resource"],codes:PlaybackDiagnostics.failure(value),testing:details)
                }
            }
            current=value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        for event in item?.errorLog()?.events.suffix(8) ?? [] {
            var details=TestingDiagnosticDetails();details.url=event.uri
            if let uri=event.uri { details.resourceID=history.reference(uri) }
            details.remoteAddress=event.serverAddress
            if let status=PlaybackDiagnostics.httpErrorStatus(domain:event.errorDomain,code:event.errorStatusCode) { details.httpStatus=status }
            history.record(.testingCheck,context:context,labels:["phase":"native-error-log-resource"],codes:PlaybackDiagnostics.errorLogCodes([(event.errorDomain,event.errorStatusCode)]),testing:details)
        }
    }

    static func transactions(_ metrics: URLSessionTaskMetrics, history: SessionDiagnostics?, context: DiagnosticContext?, phase: String) {
        guard let history else { return }
        for transaction in metrics.transactionMetrics {
            var related=context
            if let url=transaction.request.url { related?.resource=DiagnosticResource(url); related?.mediaID=history.reference(url.absoluteString) }
            var values:[String:Double]=["redirectCount":Double(metrics.redirectCount),"bytesTransferred":Double(transaction.countOfResponseBodyBytesReceived)]
            if let response=transaction.response as? HTTPURLResponse {
                values["httpStatus"]=Double(response.statusCode); values["resourceBytes"]=Double(response.expectedContentLength)
                if let ranges=response.value(forHTTPHeaderField:"Accept-Ranges")?.lowercased(), ["bytes","none"].contains(ranges) { values["rangeSupported"]=ranges == "bytes" ? 1:0 }
            }
            if let start=transaction.fetchStartDate, let end=transaction.responseEndDate { values["durationMs"]=max(0,end.timeIntervalSince(start)*1000) }
            history.record(.transferMetrics,context:related,labels:["phase":phase,"method":transaction.request.httpMethod ?? "unknown","protocol":transaction.networkProtocolName ?? "unknown"],numbers:values)
            if history.isTestingEnabled { history.record(.testingCheck,context:related,labels:["phase":"native-"+phase],testing:TestingDiagnosticDetails.transaction(transaction)) }
        }
    }
}
