import Foundation
import Observation

@MainActor @Observable final class BrowserPreferences {
    private let defaults: UserDefaults
    var openVideosInVR: Bool {
        didSet { defaults.set(openVideosInVR,forKey:"openVideosInVR") }
    }
    var restoration: BrowserRestoration {
        didSet {
            defaults.set(restoration.rawValue, forKey: "restorationMode")
            // Reducing retention removes information already saved under the
            // previous setting, rather than waiting for another navigation.
            if let raw = defaults.string(forKey: "lastPage"), let url = URL(string: raw) {
                defaults.set(restoration.address(url)?.absoluteString, forKey: "lastPage")
            }
        }
    }
    private(set) var bookmarks: [WebsiteBookmark] = []
    private(set) var favouriteIDs: Set<UUID> = []
    var favourites: [WebsiteBookmark] { bookmarks.filter { favouriteIDs.contains($0.id) } }
    private(set) var hasDamagedBookmarks = false
    var message: String?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openVideosInVR = defaults.object(forKey:"openVideosInVR") as? Bool ?? true
        restoration = BrowserRestoration(rawValue: defaults.string(forKey: "restorationMode") ?? "") ?? .website
        if let data = defaults.data(forKey: "bookmarks") {
            if data.count <= 2_000_000, let values = try? JSONDecoder().decode([WebsiteBookmark].self, from: data),
               values.count <= 500, Set(values.map(\.id)).count == values.count,
               values.allSatisfy({ WebsiteBookmark(id: $0.id, name: $0.name, address: $0.address) == $0 }) {
                bookmarks = values
            } else { hasDamagedBookmarks = true; message = "Saved bookmarks could not be opened. The existing data has been kept." }
        }
        if restoration == .home { clearRestoration() }
        else if let raw = defaults.string(forKey: "lastPage"), let url = URL(string: raw) { remember(url) }
        if let values = defaults.stringArray(forKey: "favouriteBookmarks"), values.count <= 500 {
            favouriteIDs = Set(values.compactMap(UUID.init(uuidString:))).intersection(bookmarks.map(\.id))
        }
    }
    var restoredURL: URL? {
        defaults.string(forKey: "lastPage").flatMap(URL.init(string:)).flatMap { restoration.address($0) }
    }
    func remember(_ url: URL) {
        guard let value = restoration.address(url), value.absoluteString.utf8.count <= 8192 else { return }
        defaults.set(value.absoluteString, forKey: "lastPage")
    }
    func clearRestoration() { defaults.removeObject(forKey: "lastPage") }
    func saveBookmark(name: String, address: String) {
        guard !hasDamagedBookmarks else { return }
        guard var bookmark = WebsiteBookmark(name: name, address: address) else { message = "Choose a website page to bookmark. Direct media links are not saved here."; return }
        var updated = bookmarks
        if let existing = updated.first(where: { $0.address == bookmark.address }) {
            bookmark = WebsiteBookmark(id: existing.id, name: bookmark.name, address: bookmark.address)!
            updated.removeAll { $0.id == existing.id }
        }
        guard updated.count < 500 else { message = "The 500-bookmark limit has been reached. Remove a bookmark first."; return }
        updated.insert(bookmark, at: 0); persist(updated)
    }
    func removeBookmark(_ bookmark: WebsiteBookmark) {
        guard !hasDamagedBookmarks else { return }
        persist(bookmarks.filter { $0.id != bookmark.id })
        setFavourite(bookmark, enabled: false)
    }
    func isFavourite(_ url: URL?) -> Bool {
        guard let url else { return false }
        return favourites.contains { $0.address == url.absoluteString }
    }
    func setFavourite(_ bookmark: WebsiteBookmark, enabled: Bool) {
        guard !hasDamagedBookmarks else { return }
        if enabled, bookmarks.contains(where: { $0.id == bookmark.id }) { favouriteIDs.insert(bookmark.id) }
        else { favouriteIDs.remove(bookmark.id) }
        defaults.set(favouriteIDs.map(\.uuidString).sorted(), forKey: "favouriteBookmarks")
    }
    func saveFavourite(name: String, address: String) {
        saveBookmark(name: name, address: address)
        if let normalized = WebsiteBookmark(name: name, address: address),
           let saved = bookmarks.first(where: { $0.address == normalized.address }) {
            setFavourite(saved, enabled: true)
        }
    }
    func resetBookmarks() {
        if let old = defaults.data(forKey: "bookmarks") {
            guard old.count <= 2_000_000 else { message = "The damaged bookmark list is too large to back up safely. It has been kept for recovery."; return }
            defaults.set(old, forKey: "bookmarks.previous")
        }
        persist([]); hasDamagedBookmarks = false
        favouriteIDs = []; defaults.removeObject(forKey: "favouriteBookmarks")
    }
    private func persist(_ values: [WebsiteBookmark]) {
        guard let data = try? JSONEncoder().encode(values), data.count <= 2_000_000 else { message = "The bookmark list is full. Remove a bookmark and try again."; return }
        defaults.set(data, forKey: "bookmarks"); bookmarks = values; message = nil
    }
}
