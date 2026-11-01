import Foundation
import WebKit

/// Bounds an observer-only DOM read. Cancellation never waits for a busy page.
@MainActor final class BrowserTestingSnapshot {
    private var continuation: CheckedContinuation<TestingBrowserState?, Never>?
    private var timer: Task<Void, Never>?
    private var finished = false
    static func read(_ webView: WKWebView, frame: WKFrameInfo?) async -> TestingBrowserState? {
        let reply=BrowserTestingSnapshot()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning:nil); return }
                reply.continuation=continuation
                reply.timer=Task { @MainActor [weak reply] in
                    do { try await Task.sleep(for:.seconds(2)) } catch { return }
                    reply?.finish(nil)
                }
                webView.evaluateJavaScript("globalThis.visionStreamDetector?.diagnostics()",in:frame,in:.defaultClient) { result in
                    guard case .success(let object)=result, JSONSerialization.isValidJSONObject(object),
                          let data=try? JSONSerialization.data(withJSONObject:object),data.count<=262_144,
                          let state=try? JSONDecoder().decode(TestingBrowserState.self,from:data) else { reply.finish(nil); return }
                    reply.finish(state.sanitized())
                }
            }
        } onCancel: { Task { @MainActor in reply.finish(nil) } }
    }
    private func finish(_ value:TestingBrowserState?) {
        guard !finished else { return }; finished=true
        timer?.cancel();timer=nil
        let continuation=self.continuation;self.continuation=nil;continuation?.resume(returning:value)
    }
}
