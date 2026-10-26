import AVFoundation

/// Uses only public metric APIs. Never accesses request headers, response header
/// dictionaries, response bodies, server IPs or free-form error comments.
@MainActor enum NativeDiagnosticMetrics {
    static func record(_ event: AVMetricEvent, history: SessionDiagnostics?, context: DiagnosticContext?) {
        guard let history else { return }
        if let error=event as? AVMetricErrorEvent {
            history.record(.playerError,context:context,labels:["phase":"native-metric-error"],numbers:["recovered":error.didRecover ? 1:0],codes:PlaybackDiagnostics.failure(error.error)); return
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
        }
    }
}
