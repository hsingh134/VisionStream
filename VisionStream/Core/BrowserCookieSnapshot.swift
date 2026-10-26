import Foundation

/// A bounded public cookie-store read. Only normal snapshots supplied by WebKit
/// are cached, only in memory. A delayed reply cannot hang an opening operation.
@MainActor public final class BrowserCookieSnapshot {
    public typealias Fetch = @MainActor (@escaping @MainActor ([HTTPCookie]) -> Void) -> Void
    private let fetch: Fetch
    private let timeout: Duration
    private var epoch=UUID()
    private var cached:[HTTPCookie]=[]
    private var pending:[UUID:Reply]=[:]
    private var issued=0
    private var accepted=0
    public init(timeout:Duration = .seconds(2), fetch:@escaping Fetch) { self.timeout=timeout;self.fetch=fetch }

    public func clear() {
        epoch=UUID();cached=[];accepted=0
        let replies=Array(pending.values)
        for reply in replies { reply.finish([]) }
    }
    public func cookies(for url:URL) async -> [HTTPCookie] {
        guard !Task.isCancelled else { return [] }
        let id=UUID(),generation=epoch
        issued+=1;let sequence=issued
        let reply=Reply()
        reply.finished={ [weak self] in self?.pending[id]=nil }
        pending[id]=reply
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                reply.begin(continuation,timeout:timeout) { [weak self] in
                    guard let self,self.epoch==generation else { return [] }
                    return CookieScope.matching(self.cached,url:url)
                }
                fetch { [weak self, weak reply] values in
                    guard let self,self.epoch==generation else { reply?.finish([]);return }
                    if sequence>=self.accepted { self.cached=values;self.accepted=sequence }
                    reply?.finish(CookieScope.matching(self.cached,url:url))
                }
            }
        } onCancel: { Task { @MainActor in reply.finish([]) } }
    }
    @MainActor private final class Reply {
        var finished:(()->Void)?
        private var result:[HTTPCookie]?
        private var continuation:CheckedContinuation<[HTTPCookie],Never>?
        private var timer:Task<Void,Never>?
        func begin(_ continuation:CheckedContinuation<[HTTPCookie],Never>,timeout:Duration,fallback:@escaping @MainActor ()->[HTTPCookie]) {
            if let result { continuation.resume(returning:result);return }
            self.continuation=continuation
            timer=Task { @MainActor [weak self] in
                do { try await Task.sleep(for:timeout) } catch { return }
                self?.finish(fallback())
            }
        }
        func finish(_ values:[HTTPCookie]) {
            guard result==nil else { return }
            result=values;timer?.cancel();timer=nil
            let continuation=continuation;self.continuation=nil
            continuation?.resume(returning:values)
            finished?();finished=nil
        }
    }
}
