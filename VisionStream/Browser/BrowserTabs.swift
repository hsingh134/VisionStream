import Foundation
import Observation

/// Tabs share WebKit's normal cookie store, but keep independent pages and history.
/// Tab URLs are intentionally kept in memory rather than adding persistent history.
@MainActor @Observable final class BrowserTabs {
    static let maximumCount = 8
    let preferences: BrowserPreferences
    private(set) var pages: [BrowserModel]
    private(set) var activeID: UUID
    private(set) var isClearingWebsiteData = false
    var message: String?
    var onNavigation: (() -> Void)?
    var onUserPlayback: ((MediaCandidate) -> Void)?
    weak var diagnostics: SessionDiagnostics? {
        didSet { for page in pages { page.diagnostics = diagnostics } }
    }
    var active: BrowserModel { pages.first { $0.id == activeID } ?? pages[0] }
    var canAdd: Bool { pages.count < Self.maximumCount && !isClearingWebsiteData }

    init(preferences: BrowserPreferences = BrowserPreferences()) {
        self.preferences = preferences
        let first = BrowserModel(preferences: preferences)
        pages = [first]; activeID = first.id
        configure(first)
    }

    @discardableResult func add(url: URL? = nil) -> BrowserModel? {
        guard canAdd else { message = "You can open up to eight tabs. Close a tab to open another."; return nil }
        let page = BrowserModel(preferences: preferences, restoreOnStart: false)
        page.setTabActive(false)
        configure(page); pages.append(page); select(page.id)
        if let url { page.open(url) }
        return page
    }

    func select(_ id: UUID) {
        guard !isClearingWebsiteData, id != activeID,
              let next = pages.first(where: { $0.id == id }) else { return }
        onNavigation?()
        active.setTabActive(false)
        activeID = id; next.setTabActive(true); message = nil
        diagnostics?.record(.controls, labels: ["action": "tab-selected"], numbers: ["tabCount": Double(pages.count)])
    }

    func close(_ id: UUID) {
        guard !isClearingWebsiteData, let index = pages.firstIndex(where: { $0.id == id }) else { return }
        if pages.count == 1 {
            onNavigation?()
            let old = pages[0]
            let replacement = BrowserModel(preferences: preferences, restoreOnStart: false)
            configure(replacement); pages = [replacement]; activeID = replacement.id
            preferences.clearRestoration()
            old.closeTab(); message = nil; return
        }
        let removed = pages[index]
        if activeID == id {
            select(pages[index == pages.count - 1 ? index - 1 : index + 1].id)
        }
        pages.remove(at: index); removed.closeTab(); message = nil
    }

    func selectAdjacent(_ offset: Int) {
        guard let index = pages.firstIndex(where: { $0.id == activeID }) else { return }
        select(pages[(index + offset % pages.count + pages.count) % pages.count].id)
    }

    func clearWebsiteData() async {
        guard !isClearingWebsiteData else { return }
        isClearingWebsiteData = true
        defer { isClearingWebsiteData = false }
        for page in pages { page.resetForWebsiteDataClear() }
        await active.clearWebsiteData()
        // Invalidate delayed cookie reads in every tab, including background tabs.
        for page in pages { page.invalidateCookieSnapshot() }
    }

    private func configure(_ page: BrowserModel) {
        page.diagnostics = diagnostics
        page.onNavigation = { [weak self, weak page] in
            guard let self, let page, self.activeID == page.id else { return }
            self.onNavigation?()
        }
        page.onUserPlayback = { [weak self, weak page] media in
            guard let self, let page, self.activeID == page.id, !self.isClearingWebsiteData else { return }
            self.onUserPlayback?(media)
        }
        page.onOpenNewTab = { [weak self, weak page] url in
            guard let self, let page, self.activeID == page.id, !self.isClearingWebsiteData else { return }
            if self.add(url: url) == nil { page.message = self.message }
        }
    }
}
