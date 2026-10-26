import Foundation
import Observation

@MainActor @Observable
final class VRLibraryModel {
    @ObservationIgnored weak var diagnostics: SessionDiagnostics?
    private var diagnosticContext: DiagnosticContext?
    private(set) var document: VRLibraryDocument?
    private(set) var endpoint: URL?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var usesPOST = false
    private var history: [(URL, VRLibraryDocument)] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var canGoBack: Bool { !history.isEmpty }

    func connect(address: String, browser: BrowserModel) {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            cancel(); errorMessage = VRLibraryError.invalidURL.localizedDescription; return
        }
        connect(url, browser: browser)
    }

    func connect(_ url: URL, browser: BrowserModel) {
        cancel()
        guard VRLibraryURL.isAllowed(url) else { errorMessage = VRLibraryError.invalidURL.localizedDescription; return }
        diagnosticContext=diagnostics?.begin(.library,page:url)
        let context=diagnosticContext
        diagnostics?.record(.transfer,context:context,labels:["phase":"library-request","method":usesPOST ? "POST":"GET"])
        let token = generation
        let usesPOST = usesPOST
        errorMessage = nil; isLoading = true
        task = Task { @MainActor [weak self, weak browser] in
            guard let self, let browser else { return }
            defer { if self.generation == token { self.isLoading = false; self.task = nil } }
            do {
                let cookies = await browser.cookies(for: url)
                try Task.checkCancellation()
                let data = try await Self.fetch(url, cookies: cookies, usesPOST: usesPOST)
                try Task.checkCancellation()
                let document = try VRLibraryDocument.parse(data, relativeTo: url)
                guard self.generation == token else { return }
                if let oldURL = self.endpoint, let old = self.document {
                    self.history.append((oldURL, old))
                    if self.history.count > 20 { self.history.removeFirst() }
                }
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"library-ready"])
                self.endpoint = url; self.document = document
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.diagnostics?.record(.transfer,context:context,labels:["phase":"library-failed"],codes:PlaybackDiagnostics.failure(error))
                self.errorMessage = (error as? VRLibraryError ?? .network).localizedDescription
            }
        }
    }

    func back() {
        cancel()
        guard let previous = history.popLast() else { return }
        endpoint = previous.0; document = previous.1; errorMessage = nil
    }

    func cancel() {
        if isLoading { diagnostics?.record(.controls,context:diagnosticContext,labels:["action":"library-cancel"]) }
        generation = UUID(); task?.cancel(); task = nil; isLoading = false
    }

    func clear() {
        cancel(); document = nil; endpoint = nil; history = []; errorMessage = nil
    }

    private static func fetch(_ url: URL, cookies: [HTTPCookie], usesPOST: Bool) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        if usesPOST {
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VisionStream/0.2", forHTTPHeaderField: "User-Agent")
        // The exact cookie path/domain is checked again here. No shared URLSession
        // jar, copied site tokens, synthetic Origin/Referer, or player impersonation.
        for (key, value) in HTTPCookie.requestHeaderFields(with: CookieScope.matching(cookies, url: url)) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await LibraryHTTPClient().load(request)
    }
}

/// Delegate callbacks deliver chunks away from the UI actor. A lock protects
/// cancellation from racing request startup or the final delegate callback.
private final class LibraryHTTPClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var session: URLSession?
    private var requestTask: URLSessionDataTask?
    private var buffer = Data()
    private var cancelled = false

    func load(_ request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in start(request, continuation: continuation) }
        } onCancel: { self.cancel() }
    }

    private func start(_ request: URLRequest, continuation: CheckedContinuation<Data, any Error>) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
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

    private func cancel() {
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
        guard let http = response as? HTTPURLResponse else { throw VRLibraryError.network }
        if (300..<400).contains(http.statusCode) { throw VRLibraryError.redirected }
        if [401, 403].contains(http.statusCode) { throw VRLibraryError.accessDenied }
        guard http.statusCode == 200 else { throw VRLibraryError.http(http.statusCode) }
        let mime = (http.mimeType ?? "").lowercased()
        guard mime == "application/json" || mime.hasSuffix("+json") else { throw VRLibraryError.notJSON }
        guard response.expectedContentLength <= Int64(VRLibraryDocument.maximumBytes) else { throw VRLibraryError.tooLarge }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do { try validate(response); completionHandler(.allow) }
        catch { completionHandler(.cancel); finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        guard buffer.count + data.count <= VRLibraryDocument.maximumBytes else {
            lock.unlock(); finish(.failure(VRLibraryError.tooLarge)); return
        }
        buffer.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock(); let data = buffer; lock.unlock()
        if error != nil { finish(.failure(VRLibraryError.network)) }
        else { finish(.success(data)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
