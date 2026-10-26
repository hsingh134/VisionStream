import Foundation
import XCTest
@testable import VisionStream

@MainActor final class BrowserPreferencesTests: XCTestCase {
    func testBookmarksPersistReplaceAndRemoveWithoutLosingPageIdentifiers() throws {
        let suite = "VisionStreamPrefs-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserPreferences(defaults: defaults), address = "https://example.invalid/watch?id=private#part-2"
        model.saveBookmark(name: "First", address: address)
        let id = try XCTUnwrap(model.bookmarks.first?.id)
        model.saveBookmark(name: "Renamed", address: address)
        XCTAssertEqual(model.bookmarks.count, 1); XCTAssertEqual(model.bookmarks.first?.id, id)
        let loaded = BrowserPreferences(defaults: defaults)
        XCTAssertEqual(loaded.bookmarks.first?.address, address); XCTAssertEqual(loaded.bookmarks.first?.name, "Renamed")
        loaded.removeBookmark(try XCTUnwrap(loaded.bookmarks.first))
        XCTAssertTrue(BrowserPreferences(defaults: defaults).bookmarks.isEmpty)
    }
    func testRestorationRetentionReducesImmediatelyAndDefaultsToWebsite() throws {
        let suite = "VisionStreamPrefs-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserPreferences(defaults: defaults), page = try XCTUnwrap(URL(string: "https://example.invalid/watch?id=private#chapter"))
        XCTAssertEqual(model.restoration, .website)
        model.remember(page); XCTAssertEqual(model.restoredURL?.absoluteString, "https://example.invalid/")
        model.restoration = .page; model.remember(page)
        XCTAssertEqual(BrowserPreferences(defaults: defaults).restoredURL, page)
        model.restoration = .website
        XCTAssertEqual(defaults.string(forKey: "lastPage"), "https://example.invalid/")
        model.restoration = .home
        XCTAssertNil(defaults.string(forKey: "lastPage")); XCTAssertNil(model.restoredURL)
    }
    func testDamagedBookmarksArePreservedUntilDeliberateReset() throws {
        let suite = "VisionStreamPrefs-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data("broken".utf8); defaults.set(bytes, forKey: "bookmarks")
        let model = BrowserPreferences(defaults: defaults)
        XCTAssertTrue(model.hasDamagedBookmarks)
        model.saveBookmark(name: "New", address: "https://example.invalid")
        XCTAssertEqual(defaults.data(forKey: "bookmarks"), bytes)
        model.resetBookmarks()
        XCTAssertEqual(defaults.data(forKey: "bookmarks.previous"), bytes)
        model.saveBookmark(name: "New", address: "https://example.invalid")
        XCTAssertFalse(model.hasDamagedBookmarks); XCTAssertEqual(model.bookmarks.count, 1)
    }
    func testOversizedDamagedBookmarkListIsKeptWhenBackupCannotBeMade() throws {
        let suite = "VisionStreamPrefs-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data(repeating: 32, count: 2_000_001); defaults.set(data, forKey: "bookmarks")
        let model = BrowserPreferences(defaults: defaults); model.resetBookmarks()
        XCTAssertTrue(model.hasDamagedBookmarks); XCTAssertEqual(defaults.data(forKey: "bookmarks"), data)
        XCTAssertNotNil(model.message)
    }
    func testInvalidBookmarkDoesNotPreventNextValidSave() throws {
        let suite = "VisionStreamPrefs-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserPreferences(defaults: defaults)
        model.saveBookmark(name: "Bad", address: "file:///private/video.mp4")
        XCTAssertNotNil(model.message)
        model.saveBookmark(name: "Good", address: "https://example.invalid")
        XCTAssertNil(model.message); XCTAssertEqual(model.bookmarks.count, 1)
    }
}
