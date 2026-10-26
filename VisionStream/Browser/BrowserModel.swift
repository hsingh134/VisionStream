import Foundation
import Observation
import WebKit

@MainActor @Observable
final class BrowserModel: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @ObservationIgnored weak var diagnostics: SessionDiagnostics?
    private(set) var diagnosticContext: DiagnosticContext?
    let preferences: BrowserPreferences
    let webView: WKWebView
    var address = ""
    private(set) var candidates: [MediaCandidate] = []
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var pageHTTPStatus: Int?
    private(set) var pageFailureCodes: [String] = []
    var message: String?
    var dialog: WebsiteDialog?
    private var observations: [NSKeyValueObservation] = []
    private var frames: [String: WKFrameInfo] = [:]
    private var frameCandidates: [String: [MediaCandidate]] = [:]
    private var diagnosticCandidates: [String:MediaCandidate] = [:]
    private var candidateFrames: [String: String] = [:]
    private var frameSeen: [String: Date] = [:]
    private var hasStartedBrowsing = false
    private var acceptsMediaReports = true
    private(set) var navigationVersion = 0
    private let dataStore: WKWebsiteDataStore
    @ObservationIgnored private let cookieSnapshot:BrowserCookieSnapshot
    var onNavigation: (() -> Void)?
    var onUserPlayback: ((MediaCandidate) -> Void)?
    @ObservationIgnored private var automaticPlayback=AutomaticPlayback()
    @ObservationIgnored private var navigationStartedAt=Date()

    func clearWebsiteData() async {
        cookieSnapshot.clear()
        diagnostics?.record(.controls,context:diagnosticContext,labels:["action":"clear-website-data"])
        webView.stopLoading()
        showStartPage()
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        cookieSnapshot.clear() // Invalidate reads that overlapped the platform deletion.
        preferences.clearRestoration()
        message = "Website data cleared. You have been signed out of websites."
    }

    override convenience init() { self.init(preferences: BrowserPreferences()) }

    init(preferences: BrowserPreferences) {
        self.preferences = preferences
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        // Website players often call play() after asynchronous setup. Requiring
        // a direct DOM gesture here rejects that call even after the user presses
        // the site's Play button. Let the page manage its playback lifecycle.
        config.mediaTypesRequiringUserActionForPlayback = []
        let store=config.websiteDataStore
        dataStore = store
        cookieSnapshot=BrowserCookieSnapshot { callback in store.httpCookieStore.getAllCookies(callback) }
        if let url = Bundle.main.url(forResource: "VideoDetector", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(
                source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient))
        }
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(WeakMessageHandler(self), contentWorld: .defaultClient, name: "visionStream")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncNavigation() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncNavigation() }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncNavigation() }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, let url = self.webView.url, ["https", "http"].contains(url.scheme ?? "") else { return }
                    self.address = url.absoluteString
                    self.preferences.remember(url)
                }
            }
        ]
    }

    // Loading a file during init can race a newer navigation before WebKit launches
    // its content process (observed on visionOS 26). Begin only after the view appears,
    // and never replace a navigation that has already been explicitly requested.
    func startIfNeeded() {
        guard !hasStartedBrowsing else { return }
        if let url = preferences.restoredURL {
            open(url)
        } else { showStartPage() }
    }

    func navigate() {
        guard let url = BrowserAddress.resolve(address) else {
            message = "Enter a website address such as https://example.com."; return
        }
        invalidateForNavigation()
        webView.load(URLRequest(url: url))
    }

    func open(_ url: URL) { address = url.absoluteString; navigate() }
    func back() { guard webView.canGoBack else { return }; diagnostics?.record(.controls,context:diagnosticContext,labels:["action":"back"]); invalidateForNavigation(); webView.goBack() }
    func forward() { guard webView.canGoForward else { return }; diagnostics?.record(.controls,context:diagnosticContext,labels:["action":"forward"]); invalidateForNavigation(); webView.goForward() }
    func refresh() { guard webView.url != nil else { return }; diagnostics?.record(.controls,context:diagnosticContext,labels:["action":"refresh"]); invalidateForNavigation(); webView.reload() }

    func showStartPage() {
        guard let url = Bundle.main.url(forResource: "Start", withExtension: "html") else {
            message = "The start page is missing from the app bundle."; return
        }
        invalidateForNavigation()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        address = ""
    }

    func scan() {
        diagnostics?.record(.controls, context:diagnosticContext, labels:["action":"scan-page"])
        webView.evaluateJavaScript("globalThis.visionStreamDetector?.scan()", in: nil, in: .defaultClient) { _ in }
        for frame in frames.values where !frame.isMainFrame {
            webView.evaluateJavaScript("globalThis.visionStreamDetector?.scan()", in: frame, in: .defaultClient) { _ in }
        }
    }

    func pausePageVideo(_ candidate: MediaCandidate) async {
        // A library stream has no DOM identifier. If its exact source is also
        // playing on the page, pause that detected element after native readiness.
        let media = candidate.videoID.isEmpty ? (candidates.first { $0.source == candidate.source } ?? candidate) : candidate
        if let frameID = candidateFrames[media.id], let frame = frames[frameID] {
            let paused = try? await webView.callAsyncJavaScript(
                "return globalThis.visionStreamDetector?.pause(videoID, source) ?? false",
                arguments: ["videoID": media.videoID, "source": media.source], in: frame, contentWorld: .defaultClient)
            if paused as? Bool == true { return }
        }
        // A finder parent URL can differ from the page's variant/blob URL. Once
        // native immersion opens, prevent the webpage from playing underneath it.
        // This public API pauses, rather than persistently suspending, page media.
        await webView.pauseAllMediaPlayback()
    }

    func cookies(for url: URL) async -> [HTTPCookie] {
        await cookieSnapshot.cookies(for:url)
    }

    func playbackUserAgent() async -> String? {
        // Match this WebKit client's actual identifier, rather than inventing a
        // Safari/device identity or using an extractor-supplied header.
        let value = try? await webView.evaluateJavaScript("navigator.userAgent", in: nil, contentWorld: .defaultClient)
        return value as? String
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard acceptsMediaReports, message.name == "visionStream", let body = message.body as? [String: Any],
              let frameID = body["frameID"] as? String, frameID.count < 128,
              let raw = body["candidates"] as? [[String: Any]], raw.count <= 16,
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw), data.count < 128_000,
              let decoded = try? JSONDecoder().decode([MediaCandidate].self, from: data),
              frames[frameID] != nil || frames.count < 32 else { return }
        frames[frameID] = message.frameInfo
        frameSeen[frameID] = Date()
        let expired = frameSeen.filter { Date().timeIntervalSince($0.value) > 6 }.map(\.key)
        for id in expired { frames[id] = nil; frameCandidates[id] = nil; frameSeen[id] = nil }
        frameCandidates[frameID] = decoded
        candidates = frameCandidates.values.flatMap { $0 }.sorted { $0.id < $1.id }
        let current=Dictionary(candidates.map { ($0.id,$0) },uniquingKeysWith:{ _, new in new })
        for (id,old) in diagnosticCandidates where current[id]?.source != old.source {
            diagnostics?.record(.mediaState,context:diagnostics?.mediaContext(old,parent:diagnosticContext),labels:["phase":"element-source-removed"],numbers:["candidateCount":Double(candidates.count)])
        }
        diagnosticCandidates=current
        for candidate in decoded {
            let context=diagnostics?.mediaContext(candidate,parent:diagnosticContext)
            var labels=["mimeType":candidate.normalizedMIMEType,"phase":"observed"]
            if let hint=candidate.formatHint { labels["projection"]=hint.projection?.rawValue ?? "unspecified"; labels["layout"]=hint.layout?.rawValue ?? "unspecified"; labels["evidence"]=hint.evidence.rawValue }
            var values=diagnostics?.mediaNumbers(candidate) ?? [:]; values["frameMain"]=message.frameInfo.isMainFrame ? 1:0
            diagnostics?.record(.mediaState,context:context,labels:labels,numbers:values,deduplicate:"media-state-" + (context?.mediaID?.uuidString ?? "unknown") + candidate.id)
        }
        candidateFrames = Dictionary(frameCandidates.flatMap { frame, list in list.map { ($0.id, frame) } }, uniquingKeysWith: { a, _ in a })
        let eligible=candidates.filter { media in
            // A delayed message from a departing main document cannot launch
            // its media after navigation. Frames additionally share the gesture
            // age check against this navigation's start.
            guard let frame=candidateFrames[media.id].flatMap({ frames[$0] }) else { return false }
            guard frame.isMainFrame else { return true }
            func document(_ value:URL?) -> String? {
                guard let value,var parts=URLComponents(url:value,resolvingAgainstBaseURL:false) else { return nil }
                parts.fragment=nil;return parts.string
            }
            return document(URL(string:media.pageURL)) == document(webView.url)
        }
        if let media=automaticPlayback.next(in:eligible,navigation:navigationVersion,pageAge:Date().timeIntervalSince(navigationStartedAt),enabled:preferences.openVideosInVR) {
            diagnostics?.record(.controls,context:diagnosticContext,labels:["action":"webpage-play-native-handoff"])
            onUserPlayback?(media)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        invalidateForNavigation()
        diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":"started"])
    }
    private func invalidateForNavigation() {
        // Invalidate at the request, before WebKit's asynchronous callback. The
        // departing page cannot supply media again until the new document commits.
        hasStartedBrowsing = true; isLoading = true; acceptsMediaReports = false
        navigationVersion += 1
        navigationStartedAt=Date()
        pageHTTPStatus = nil; pageFailureCodes = []
        finishDialog(nil)
        onNavigation?()
        clearCandidates(); message = nil
    }
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let url=webView.url { diagnosticContext?.resource=DiagnosticResource(url) }
        diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":"server-redirect"])
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        clearCandidates(); acceptsMediaReports = true
        if let url=webView.url { diagnosticContext?.pageID=diagnostics?.reference(url.absoluteString,page:true); diagnosticContext?.resource=DiagnosticResource(url) }
        diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":"committed"])
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { acceptsMediaReports = true; syncNavigation(); scan(); diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":"finished"],numbers:["candidateCount":Double(candidates.count)]) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":"content-process-terminated"])
        acceptsMediaReports = false; clearCandidates(); message = "The website stopped responding. Refresh to reload it."
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame {
            pageHTTPStatus = (navigationResponse.response as? HTTPURLResponse)?.statusCode
            diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":"response"],numbers:pageHTTPStatus.map { ["httpStatus":Double($0)] } ?? [:])
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        // Local bundle start page only; file links supplied by websites cannot open arbitrary files.
        let bundled = url.isFileURL && url.deletingLastPathComponent() == Bundle.main.resourceURL
        let allowed = ["http", "https", "about"].contains(url.scheme ?? "") || bundled
        if navigationAction.targetFrame?.isMainFrame == true {
            diagnosticContext=diagnostics?.begin(.navigation,page:url)
            diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":allowed ? "allowed":"blocked"],numbers:["statusCode":Double(navigationAction.navigationType.rawValue)])
        }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme ?? "") { invalidateForNavigation(); webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage text: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        presentDialog(WebsiteDialog(kind: .alert, message: String(text.prefix(500))) { _ in completionHandler() })
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage text: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        presentDialog(WebsiteDialog(kind: .confirm, message: String(text.prefix(500))) { completionHandler($0 != nil) })
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        presentDialog(WebsiteDialog(kind: .prompt, message: String(prompt.prefix(500)), defaultText: defaultText ?? "", completion: completionHandler))
    }
    func finishDialog(_ response: String?) {
        let pending = dialog; dialog = nil
        if pending != nil { diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":response == nil ? "dialog-closed-without-confirmation":"dialog-confirmed"]) }
        pending?.completion(response)
    }
    private func presentDialog(_ value: WebsiteDialog) {
        finishDialog(nil); dialog = value
        diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":"website-dialog","mode":String(describing:value.kind)])
    }

    private func syncNavigation() {
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward; isLoading = webView.isLoading
    }
    private func clearCandidates() {
        if !candidates.isEmpty { diagnostics?.record(.mediaState,context:diagnosticContext,labels:["phase":"page-sources-cleared"],numbers:["candidateCount":Double(candidates.count)]) }
        diagnosticCandidates=[:]
        candidates = []; frames = [:]; frameCandidates = [:]; candidateFrames = [:]; frameSeen = [:]
    }
    private func navigationFailed(_ error: Error) {
        diagnostics?.record(.navigation,context:diagnosticContext,labels:["phase":"failed"],codes:PlaybackDiagnostics.failure(error))
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        pageFailureCodes = PlaybackDiagnostics.failure(error)
        acceptsMediaReports = true
        message = "This page could not load. Check the address, connection, or website access requirements."
        syncNavigation()
    }
}

@MainActor struct WebsiteDialog {
    enum Kind: Equatable { case alert, confirm, prompt }
    let id = UUID()
    let kind: Kind
    let message: String
    var defaultText = ""
    let completion: @MainActor (String?) -> Void
}

@MainActor private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: BrowserModel?
    init(_ target: BrowserModel) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
