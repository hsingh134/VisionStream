import XCTest
@testable import VisionStream

@MainActor final class PrivacyNativeTests:XCTestCase {
    private func models(_ root:URL,defaults:UserDefaults,testingDefault:Bool? = nil)->AppModel {
        let library=FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0]
        return AppModel(downloads:DownloadModel(root:root.appendingPathComponent("saved")),hlsDownloads:HLSOfflineLibrary(store:HLSOfflineStore(root:root.appendingPathComponent("hls"),library:library),identifier:"personal.visionstream.privacy."+UUID().uuidString),privacyDefaults:defaults,diagnosticRoot:root.appendingPathComponent("history"),testingDefault:testingDefault)
    }
    func testFreshInstallOptInOptOutAndUpgradePreferenceArePersistent() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),name="PrivacyNative-"+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name);try? FileManager.default.removeItem(at:root) }
        let first=models(root,defaults:defaults);defer { first.hlsDownloads.stopTestSession() }
        XCTAssertFalse(first.diagnosticsEnabled);XCTAssertFalse(first.history.isEnabled);XCTAssertEqual(first.history.eventCount,0)
        first.setDiagnosticsEnabled(true)
        XCTAssertTrue(first.history.isEnabled);XCTAssertGreaterThan(first.history.eventCount,0)
        first.setDiagnosticsEnabled(false)
        let second=models(root,defaults:defaults);defer { second.hlsDownloads.stopTestSession() }
        XCTAssertFalse(second.diagnosticsEnabled);XCTAssertFalse(second.history.isEnabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("history").path))
        second.setDiagnosticsEnabled(true)
        let third=models(root,defaults:defaults);defer { third.hlsDownloads.stopTestSession() }
        XCTAssertTrue(third.diagnosticsEnabled)
    }
    func testDeleteHistoryClearsSavedLinksReportsAndWaitingLinksWithoutCancellingSaves() async throws {
        let origin=try XCTUnwrap(ProcessInfo.processInfo.environment["VISIONSTREAM_TEST_ORIGIN"].flatMap(URL.init(string:)))
        guard origin.scheme=="https",["127.0.0.1","localhost"].contains(origin.host) else { throw URLError(.badURL) }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),name="PrivacyDelete-"+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:name)),app=models(root,defaults:defaults)
        defer { app.downloads.cancel();app.hlsDownloads.stopTestSession();defaults.removePersistentDomain(forName:name);try? FileManager.default.removeItem(at:root) }
        app.setDiagnosticsEnabled(true)
        app.enqueueSave(.init(id:"active",source:origin.appendingPathComponent("delayed/controls-demo.mp4").absoluteString),cookies:[],userAgent:nil)
        app.enqueueSave(.init(id:"waiting",source:origin.appendingPathComponent("vr180-sbs.mp4").absoluteString),cookies:[],userAgent:nil)
        XCTAssertEqual(app.queuedSaves.count,1)
        XCTAssertNotNil(app.queuedSaves.first?.context)
        let exported=try DiagnosticReportFiles.write(app.playbackReport)
        app.deleteDiagnosticHistory()
        XCTAssertFalse(app.diagnosticsEnabled);XCTAssertFalse(app.history.isEnabled)
        XCTAssertTrue(app.privacyMessage?.contains("deleted") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath:exported.path))
        XCTAssertNil(app.queuedSaves.first?.context)
        let end=Date().addingTimeInterval(25)
        while (app.saveInProgress || !app.queuedSaves.isEmpty || app.saveQueueWorker != nil),Date()<end { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(app.saveInProgress);XCTAssertEqual(app.downloads.videos.count,2)
        XCTAssertTrue(app.downloads.videos.allSatisfy { $0.diagnosticContext==nil })
        XCTAssertEqual(app.history.eventCount,0)
        let report=app.playbackReport
        XCTAssertFalse(report.contains(origin.host!));XCTAssertFalse(report.contains("private-source"))
        app.setDiagnosticsEnabled(true)
        XCTAssertGreaterThan(app.history.eventCount,0)
    }
    func testTestingBuildDefaultHonoursOptOutAndDeletesFullDetails() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),name="TestingPrivacy-"+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name);try? FileManager.default.removeItem(at:root) }
        let first=models(root,defaults:defaults,testingDefault:true);defer { first.hlsDownloads.stopTestSession() }
        XCTAssertTrue(first.testingDiagnosticsEnabled);XCTAssertTrue(first.diagnosticsEnabled);XCTAssertTrue(first.history.isTestingEnabled)
        _ = first.history.begin(.playback,media:.init(id:"test",source:"https://cdn.example/private-stream.m3u8?signature=SIGNED_TEST"))
        XCTAssertTrue(first.playbackReport.contains("SIGNED_TEST"))
        first.setTestingDiagnosticsEnabled(false)
        XCTAssertFalse(first.playbackReport.contains("SIGNED_TEST"))
        let second=models(root,defaults:defaults,testingDefault:true);defer { second.hlsDownloads.stopTestSession() }
        XCTAssertFalse(second.testingDiagnosticsEnabled,"A testing build must honour an explicit opt-out")
        second.setTestingDiagnosticsEnabled(true)
        XCTAssertTrue(second.playbackReport.contains("SIGNED_TEST"))
        second.deleteDiagnosticHistory()
        XCTAssertFalse(second.testingDiagnosticsEnabled);XCTAssertFalse(second.diagnosticsEnabled)
        XCTAssertFalse(second.playbackReport.contains("SIGNED_TEST"))
    }
    func testInjectedRedactedHistoryDoesNotInheritUnrelatedTestingPreference() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),name="TestingIsolation-"+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:name))
        defaults.set(true,forKey:"diagnostics.testing.enabled")
        defer { defaults.removePersistentDomain(forName:name);try? FileManager.default.removeItem(at:root) }
        let history=SessionDiagnostics(root:root.appendingPathComponent("history"),enabled:false)
        let app=AppModel(history:history,privacyDefaults:defaults,testingDefault:true)
        XCTAssertFalse(app.testingDiagnosticsEnabled);XCTAssertFalse(app.diagnosticsEnabled)
        XCTAssertFalse(app.history.isEnabled);XCTAssertFalse(app.history.isTestingEnabled)
        _ = history.begin(.playback,media:.init(id:"test",source:"https://cdn.example/private-stream.m3u8?signature=PRIVATE_TEST"))
        XCTAssertFalse(app.playbackReport.contains("PRIVATE_TEST"))
        XCTAssertEqual(defaults.object(forKey:"diagnostics.testing.enabled") as? Bool,true,"An injected store must not rewrite another profile's saved setting")
    }
    func testPolicyLicencesAndOriginalLayeredIconAreBundled() throws {
        for (name,ext) in [("PrivacyPolicy","txt"),("THIRD_PARTY_NOTICES","md"),("FFmpeg-LGPL-2.1","txt"),("EmbeddedRuntime","txt"),("VisionStream-MIT","txt")] {
            let file=try XCTUnwrap(Bundle.main.url(forResource:name,withExtension:ext))
            XCTAssertGreaterThan(try Data(contentsOf:file).count,100)
        }
        let icons=Bundle.main.object(forInfoDictionaryKey:"CFBundleIcons") as? [String:Any]
        XCTAssertNotNil(icons,"Asset compilation must supply the visionOS app icon metadata")
        XCTAssertNotNil(Bundle.main.url(forResource:"Assets",withExtension:"car"))
        let notice=try String(contentsOf:try XCTUnwrap(Bundle.main.url(forResource:"THIRD_PARTY_NOTICES",withExtension:"md")),encoding:.utf8)
        XCTAssertFalse(notice.contains("No GPL player code, FFmpeg library"))
    }
}
