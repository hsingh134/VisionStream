import Foundation

/// A bounded inspection of the exact published master, with no redirects,
/// credential-store access, playlist rewriting or whole-video download.
final class HLSQualityRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Kind { case master, mp4Prefix, resourceHeaders }
    struct ResponseSummary: Sendable { let status:Int; let expectedBytes:Int64 }
    private var observedResponse:ResponseSummary?
    var responseSummary:ResponseSummary? { lock.lock();defer { lock.unlock() };return observedResponse }
    private let kind: Kind
    private var expectedBytes: Int?
    init(kind: Kind = .master) { self.kind = kind; super.init() }
    private var maximumBytes: Int { kind == .master ? HLSManifest.maximumBytes : MP4SphericalMetadata.maximumPrefixBytes }
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var session: URLSession?
    private var requestTask: URLSessionDataTask?
    private var buffer = Data()
    // An isolated in-memory system jar applies normal response-cookie validation.
    // Never parse Set-Cookie into transferable credentials ourselves.
    private let cookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage
    func cookies(for url: URL) -> [HTTPCookie] {
        CookieScope.matching(cookieStorage?.cookies(for: url) ?? [], url: url)
    }
    private var cancelled = false

    func load(_ request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in start(request, continuation: continuation) }
        } onCancel: { self.cancel() }
    }

    private func start(_ request: URLRequest, continuation: CheckedContinuation<Data, any Error>) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = kind == .master ? 20 : 5
        configuration.timeoutIntervalForResource = kind == .master ? 30 : 8
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        let task = session.dataTask(with: request)
        lock.lock()
        guard !cancelled else {
            lock.unlock(); session.invalidateAndCancel()
            continuation.resume(throwing: CancellationError()); return
        }
        self.continuation = continuation; self.session = session; requestTask = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil; requestTask = nil; buffer = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, response.expectedContentLength <= Int64(maximumBytes) else { throw URLError(.badServerResponse) }
        if kind == .master {
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        } else {
            // Ignore servers that do not honor the bounded range; never read a whole MP4.
            guard http.statusCode == 206, let range = http.value(forHTTPHeaderField: "Content-Range"),
                  range.hasPrefix("bytes 0-"), let end = Int(range.dropFirst(8).split(separator: "/").first ?? ""),
                  end >= 0, end < maximumBytes else { throw URLError(.badServerResponse) }
            lock.lock(); expectedBytes = end + 1; lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        if let http=response as? HTTPURLResponse {
            lock.lock();observedResponse = .init(status:http.statusCode,expectedBytes:http.expectedContentLength);lock.unlock()
            if kind == .resourceHeaders || http.statusCode >= 300 {
                completionHandler(.cancel)
                if kind == .resourceHeaders { finish(.success(Data())) }
                else { finish(.failure(URLError(.badServerResponse))) }
                return
            }
        }
        do { try validate(response); completionHandler(.allow) }
        catch { completionHandler(.cancel); finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        guard buffer.count + data.count <= maximumBytes else {
            lock.unlock(); finish(.failure(URLError(.dataLengthExceedsMaximum))); return
        }
        buffer.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock(); let data = buffer; let expected = expectedBytes; lock.unlock()
        if let error { finish(.failure(error)) }
        else if expected != nil && data.count != expected { finish(.failure(URLError(.badServerResponse))) }
        else { finish(.success(data)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        lock.lock();observedResponse = .init(status:response.statusCode,expectedBytes:response.expectedContentLength);lock.unlock()
        completionHandler(nil)
    }
}
