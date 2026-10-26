import Foundation

/// One bounded foreground transfer. The delegate owns its staging file until
/// successful completion; no partial video or URLSession resume data is retained.
final class MP4DownloadTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var cancelled = false
    private var failure: Error?
    enum Payload:Sendable { case mp4,transportStream }
    private let payload:Payload
    private let staging: URL
    private let maximumBytes: Int64
    private let reserveBytes: Int64
    private let origin: URL
    private let progress: @Sendable (Int64, Int64) -> Void
    private let diagnostic: (@Sendable (URL?, [String:String], [String:Double]) -> Void)?
    private var redirectCount = 0
    private var crossedOrigin = false
    private var issuedCookies:[HTTPCookie]=[]
    func responseCookies()->[HTTPCookie] { lock.lock();defer { lock.unlock() };return issuedCookies }
    private var lastUpdate = Date.distantPast // Delegate callbacks use a serial queue.

    init(staging: URL, origin: URL, maximumBytes: Int64 = 8 * 1024 * 1024 * 1024,
         reserveBytes: Int64 = 256 * 1024 * 1024,payload:Payload = .mp4,
         diagnostic: (@Sendable (URL?, [String:String], [String:Double]) -> Void)? = nil,
         progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.staging = staging; self.origin = origin; self.maximumBytes = maximumBytes
        self.reserveBytes = reserveBytes;self.payload=payload; self.progress = progress; self.diagnostic = diagnostic
    }
    func run(_ request: URLRequest, cookies: [HTTPCookie]) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { result in
                lock.lock(); defer { lock.unlock() }
                if cancelled { result.resume(throwing: CancellationError()); return }
                continuation = result
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCredentialStorage = nil
                configuration.httpShouldSetCookies = true
                configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 7200
                for cookie in CookieScope.matching(cookies, url: origin) { configuration.httpCookieStorage?.setCookie(cookie) }
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.downloadTask(with: request); self.task = task; task.resume()
            }
        } onCancel: { self.cancel() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }
    private func reject(_ error: Error, task: URLSessionTask) {
        lock.lock(); if failure == nil { failure = error }; lock.unlock(); task.cancel()
    }
    private func valid(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https" else { return false }
        let mime = response.mimeType?.lowercased() ?? ""
        return (payload == .mp4 ? ["video/mp4","video/x-m4v","application/octet-stream"]:["video/mp2t","video/mpeg","application/octet-stream","binary/octet-stream"]).contains(mime)
    }
    private func responseError(_ response: URLResponse?) -> TransferError {
        if let response = response as? HTTPURLResponse, (400...599).contains(response.statusCode) { return .http(response.statusCode) }
        return .response
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        redirectCount += 1
        diagnostic?(request.url,["phase":"redirect"],["httpStatus":Double(response.statusCode),"redirectCount":Double(redirectCount)])
        guard let url = request.url, url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, redirectCount <= 10 else {
            lock.lock(); if failure == nil { failure = TransferError.redirect }; lock.unlock()
            completionHandler(nil); return
        }
        let sameOrigin = url.host == origin.host && url.port == origin.port
        if sameOrigin && !crossedOrigin { completionHandler(request); return }
        // Public CDN redirects are common. A fresh request carries no Cookie,
        // Authorization, Origin, Referer or other website headers. Cookie handling
        // stays disabled for the rest of this chain, even if it returns home.
        crossedOrigin = true
        var publicRequest = URLRequest(url: url)
        publicRequest.httpShouldHandleCookies = false
        if let agent = task.originalRequest?.value(forHTTPHeaderField: "User-Agent") {
            publicRequest.setValue(agent, forHTTPHeaderField: "User-Agent")
        }
        completionHandler(publicRequest)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard valid(downloadTask.response) else { reject(responseError(downloadTask.response), task: downloadTask); return }
        guard totalBytesWritten <= maximumBytes, totalBytesExpectedToWrite <= maximumBytes else { reject(TransferError.tooLarge, task: downloadTask); return }
        guard Date().timeIntervalSince(lastUpdate) >= 0.2 else { return }
        lastUpdate = Date()
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: staging.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let remaining = max(0, totalBytesExpectedToWrite - totalBytesWritten)
        guard free > reserveBytes, remaining < free - reserveBytes else { reject(TransferError.storage, task: downloadTask); return }
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard valid(downloadTask.response) else { reject(responseError(downloadTask.response), task: downloadTask); return }
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { throw TransferError.notMP4 }
            guard size <= maximumBytes else { throw TransferError.tooLarge }
            let handle = try FileHandle(forReadingFrom: location)
            defer { try? handle.close() }
            let prefix = try handle.read(upToCount:payload == .mp4 ? 12:188*8) ?? Data()
            if payload == .mp4 {
                guard prefix.count==12,String(data:prefix[4..<8],encoding:.ascii)=="ftyp" else { throw TransferError.notMP4 }
            } else {
                guard size%188==0,prefix.count>=188 else { throw TransferError.notTransportStream }
                for offset in stride(from:0,to:prefix.count-187,by:188) {
                    guard prefix[offset]==0x47,prefix[offset+3]&0xC0==0 else { throw TransferError.notTransportStream }
                }
            }
            try FileManager.default.moveItem(at: location, to: staging)
        } catch { lock.lock(); failure = error; lock.unlock() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let response=task.response as? HTTPURLResponse { diagnostic?(response.url,["phase":"response"],["httpStatus":Double(response.statusCode),"expectedBytes":Double(response.expectedContentLength),"receivedBytes":Double(task.countOfBytesReceived)]) }
        lock.lock()
        issuedCookies=session.configuration.httpCookieStorage?.cookies ?? []
        let result = continuation; continuation = nil
        let finalError: Error? = cancelled ? CancellationError() : (failure ?? error)
        self.task = nil; self.session = nil
        lock.unlock()
        if let finalError { try? FileManager.default.removeItem(at: staging); result?.resume(throwing: finalError) }
        else { result?.resume(returning: staging) }
        session.invalidateAndCancel()
    }
    enum TransferError: Error { case response, redirect, http(Int), tooLarge, storage, notMP4,notTransportStream }
}
