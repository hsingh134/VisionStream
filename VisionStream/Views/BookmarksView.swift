import SwiftUI

@MainActor struct BookmarksView: View {
    let preferences: BrowserPreferences
    let page: URL?
    let title: String
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Bookmarks").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut("w", modifiers: .command) }
            if let page, WebsiteBookmark(name: title, address: page.absoluteString) != nil {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Bookmark name", text: $name).textFieldStyle(.roundedBorder)
                    Text(page.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    Button("Save this page", systemImage: "bookmark") { saveCurrentPage() }
                        .disabled(preferences.hasDamagedBookmarks)
                    Text("The page address, including any page identifiers, is saved on this headset.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
            }
            if let message = preferences.message { Text(message).foregroundStyle(.orange).font(.callout) }
            if preferences.hasDamagedBookmarks { Button("Start a new bookmark list") { confirmReset = true } }
            if preferences.bookmarks.isEmpty {
                ContentUnavailableView("No bookmarks", systemImage: "bookmark", description: Text("Open a website and save its page here."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(preferences.bookmarks) { bookmark in
                            HStack {
                                Button {
                                    if let url = BrowserAddress.resolve(bookmark.address) { dismiss(); open(url) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.name).lineLimit(2)
                                        Text(URL(string: bookmark.address)?.host ?? "Website").font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                Button("Remove bookmark", systemImage: "trash", role: .destructive) { preferences.removeBookmark(bookmark) }.labelStyle(.iconOnly)
                                    .accessibilityLabel("Remove bookmark \(bookmark.name)")
                            }.padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
        }.padding(28).frame(width: 680, height: 580).onAppear {
            name = String(title.unicodeScalars.prefix(120))
            #if targetEnvironment(simulator)
            if SimulatorScenarioRunner.isConfigured {
                SimulatorScenarioRunner.bookmarkSave = { name = $0; saveCurrentPage() }
                SimulatorScenarioRunner.bookmarkOpen = { if let first = preferences.bookmarks.first, let url = BrowserAddress.resolve(first.address) { dismiss(); open(url) } }
            }
            #endif
        }
            .onDisappear {
                #if targetEnvironment(simulator)
                SimulatorScenarioRunner.bookmarkSave = nil; SimulatorScenarioRunner.bookmarkOpen = nil
                #endif
            }
            .simulatorPanel(.bookmarks)
            .confirmationDialog("Start a new bookmark list?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Start new list", role: .destructive) { preferences.resetBookmarks() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("The unreadable list will be kept as a local backup. You can add bookmarks to a new empty list.") }
    }
    private func saveCurrentPage() { if let page { preferences.saveBookmark(name: name, address: page.absoluteString) } }
}

@MainActor struct BrowserSettingsView: View {
    let app:AppModel
    @State private var confirmDeleteHistory=false
    @State private var showPrivacy=false
    let preferences: BrowserPreferences
    let currentPage: URL?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var preferences = preferences
        VStack(alignment: .leading, spacing: 20) {
            Text("Browser settings").font(.title2.bold())
            ScrollView {
            VStack(alignment:.leading,spacing:20) {
            Toggle("Open videos in VR when I press Play",isOn:$preferences.openVideosInVR)
            Text("Compatible videos open after you start playback on the webpage. Autoplay previews stay in the browser. If a site's Play control is not recognised, use Watch in VR.").font(.caption).foregroundStyle(.secondary)
            Text("When VisionStream opens").font(.headline)
            Picker("When VisionStream opens", selection: Binding(get: { preferences.restoration }, set: setRestoration)) {
                ForEach(BrowserRestoration.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Text(preferences.restoration == .page ? "The full last page address is saved on this headset, including page identifiers. Website sessions also persist." : (preferences.restoration == .website ? "Only the last website’s address is remembered. Page paths and identifiers are removed. Website sessions still persist." : "Open the VisionStream home page each time. Website sessions still persist until you clear website data."))
                .foregroundStyle(.secondary)
            Text("Bookmarks and downloaded videos remain until you remove them. Clear website data in Browser options to sign out of websites and remove their stored data.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Toggle("Detailed troubleshooting history",isOn:Binding(get:{ app.diagnosticsEnabled },set:app.setDiagnosticsEnabled))
            Text("When on, VisionStream stores website hosts and technical activity on this device. Private page links, passwords, cookies and video images are excluded. Nothing is uploaded automatically. Turning this off keeps older history until you delete it.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Privacy policy",systemImage:"hand.raised") { showPrivacy=true }
                Button("Delete diagnostic history…",systemImage:"trash",role:.destructive) { confirmDeleteHistory=true }
            }
            if let message=app.privacyMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth:.infinity,alignment:.leading)
            }
            Button("Done") { dismiss() }.keyboardShortcut("w", modifiers: .command).buttonStyle(.borderedProminent)
        }.padding(30).frame(width:660,height:700).simulatorPanel(.settings)
            .sheet(isPresented:$showPrivacy) { PrivacyPolicyView() }
            .confirmationDialog("Delete diagnostic history?",isPresented:$confirmDeleteHistory,titleVisibility:.visible) {
                Button("Delete and turn recording off",role:.destructive) { app.deleteDiagnosticHistory() }
                Button("Cancel",role:.cancel) { }
            } message: { Text("Removes local troubleshooting histories, generated reports and diagnostic links in saved-video catalogues. Videos, bookmarks and website sessions stay. Copies you already shared or copied to another app cannot be removed by VisionStream.") }
            .onAppear {
                #if targetEnvironment(simulator)
                if SimulatorScenarioRunner.isConfigured {
                    SimulatorScenarioRunner.restoreMode = setRestoration
                    SimulatorScenarioRunner.diagnosticsMode = app.setDiagnosticsEnabled
                    SimulatorScenarioRunner.diagnosticsDelete = app.deleteDiagnosticHistory
                }
                #endif
            }
            .onDisappear {
                #if targetEnvironment(simulator)
                SimulatorScenarioRunner.restoreMode = nil
                SimulatorScenarioRunner.diagnosticsMode = nil; SimulatorScenarioRunner.diagnosticsDelete = nil
                #endif
            }
    }
    private func setRestoration(_ value: BrowserRestoration) {
        preferences.restoration = value
        if let currentPage { preferences.remember(currentPage) }
    }

}
