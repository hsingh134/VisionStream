import Foundation

/// Resolve the server's exact public HTTPS destination from response headers.
/// Responses are cancelled before reading a body. No cookies or website
/// headers cross a redirect; no path, token or quality variant is constructed.
final class PublicMediaLocation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var cancelled = false
    private var redirects = 0
    private var agent: String?
    func load(_ url: URL, userAgent: String? = nil) async throws -> URL {
        guard secure(url) else { throw URLError(.badURL) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock(); defer { lock.unlock() }
                guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                if let userAgent, userAgent.utf8.count <= 1024, userAgent.rangeOfCharacter(from: .controlCharacters) == nil { agent = userAgent }
                let config = URLSessionConfiguration.ephemeral
                config.httpCookieStorage = nil; config.httpShouldSetCookies = false
                config.urlCredentialStorage = nil; config.urlCache = nil
                config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 8
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                request.httpMethod = "GET"; request.httpShouldHandleCookies = false
                if let agent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
                session.dataTask(with: request).resume()
            }
        } onCancel: { self.cancel() }
    }
    private func secure(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<URL, Error>) {
        lock.lock(); let continuation = continuation; self.continuation = nil
        let session = session; self.session = nil; lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        // Resolve only from successful headers; a login/error page is not a
        // playable-source assertion. Native asset validation still follows.
        completionHandler(.cancel)
        if let response = response as? HTTPURLResponse, [200, 206].contains(response.statusCode), secure(response.url), let url = response.url {
            finish(.success(url))
        } else { finish(.failure(URLError(.badServerResponse))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(.failure(error ?? URLError(.badServerResponse)))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        redirects += 1
        guard secure(request.url), redirects <= 10, let url = request.url else { completionHandler(nil); return }
        var next = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        next.httpMethod = "GET"; next.httpShouldHandleCookies = false
        if let agent { next.setValue(agent, forHTTPHeaderField: "User-Agent") }
        completionHandler(next)
    }
}
