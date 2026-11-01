import SwiftUI

@MainActor struct BrowserTabStrip: View {
    let tabs: BrowserTabs
    let newTab: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(tabs.pages) { page in
                            HStack(spacing: 2) {
                                Button { tabs.select(page.id) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: page.isStartPage ? "house" : "globe")
                                        Text(page.pageTitle).lineLimit(1).truncationMode(.tail)
                                    }.frame(minWidth: 85, maxWidth: 180, alignment: .leading)
                                }
                                .accessibilityLabel("Tab: \(page.pageTitle)")
                                .accessibilityValue(page.id == tabs.activeID ? "Selected" : "")
                                if page.id == tabs.activeID {
                                    close(page).keyboardShortcut("w", modifiers: .command)
                                } else { close(page) }
                            }
                            .buttonStyle(.plain).padding(10)
                            .background(.white.opacity(page.id == tabs.activeID ? 0.18 : 0.05), in: RoundedRectangle(cornerRadius: 14))
                            .id(page.id)
                        }
                    }
                }.scrollIndicators(.hidden)
                    .onChange(of: tabs.activeID) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
            Button("New tab", systemImage: "plus", action: newTab)
                .labelStyle(.iconOnly).keyboardShortcut("t", modifiers: .command)
                .disabled(!tabs.canAdd).help("New tab (up to eight)")
        }.padding(.horizontal, 16).padding(.bottom, 10)
            .disabled(tabs.isClearingWebsiteData)
    }
    private func close(_ page: BrowserModel) -> some View {
        Button { tabs.close(page.id) } label: { Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .accessibilityLabel("Close tab: \(page.pageTitle)")
    }
}
