// Dependency-free runner for the very same core test methods when Command Line Tools lack XCTest.
import Foundation

@MainActor class XCTestCase {}
@MainActor enum CheckResults {
    static var checks = 0
    static var failures = 0
    static func record(_ success: Bool, _ message: String, file: StaticString, line: UInt) {
        checks += 1
        if !success { failures += 1; print("FAIL \(file):\(line) \(message)") }
    }
}
@MainActor func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(value(), "Expected true. " + message, file: file, line: line)
}
@MainActor func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(!value(), "Expected false. " + message, file: file, line: line)
}
@MainActor func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(lhs == rhs, "\(lhs) != \(rhs). " + message, file: file, line: line)
}
@MainActor func XCTAssertEqual(_ lhs: Float, _ rhs: Float, accuracy: Float, file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(abs(lhs-rhs) <= accuracy, "\(lhs) != \(rhs) ± \(accuracy)", file: file, line: line)
}
@MainActor func XCTAssertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(lhs != rhs, "Expected unequal values", file: file, line: line)
}
@MainActor func XCTAssertGreaterThan<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(lhs > rhs, "Expected greater value", file: file, line: line)
}
@MainActor func XCTAssertNotNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(value != nil, "Expected a value. " + message, file: file, line: line)
}
@MainActor func XCTAssertNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(value == nil, "Expected nil. " + message, file: file, line: line)
}
@MainActor func XCTAssertLessThan<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    CheckResults.record(lhs < rhs, "\(lhs) is not less than \(rhs)", file: file, line: line)
}
@MainActor func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "CoreChecks", code: 1) }
    return value
}

@MainActor func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); CheckResults.record(false, "Expected an error", file: file, line: line) }
    catch { CheckResults.record(true, "", file: file, line: line) }
}

@main struct CoreTestRunner {
    @MainActor static func main() async throws {
        let hls = HLSOfflineStoreTests()
        let savedState = BrowserSavedStateTests()
        let offline = OfflineVideoStoreTests()
        let media = CompatibilityTests()
        let projection = ProjectionTests()
        let viewing = ViewingPoseTests()
        let cookies = CookieScopeTests()
        let library = VRLibraryTests()
        let diagnostics = PlaybackDiagnosticsTests()
        let extraction = ExtractionTests()
        let quality = QualityAndFormatTests()
        let clearHLS = ClearHLSPlanTests()
        let spherical = SphericalMetadataTests()
        let automatic = AutomaticPlaybackTests()
        let tests: [(String, () throws -> Void)] = [
            ("reclined viewing pose",viewing.testRecenterFacesViewerWhileSeatedReclinedAndOnSide),
            ("controls independent of tilt",viewing.testControlsStayInCapturedViewDuringTilt),
            ("upright reset at vertical pose",viewing.testUprightResetLevelsVideoButKeepsControlsFacingReclinedViewer),
            ("bounded video tilt",viewing.testPositiveTiltRaisesVideoAndRejectsNonFiniteInput),
            ("invalid tracking pose",viewing.testMalformedTrackingCannotReplaceCapturedPose),
            ("automatic play intent readiness",automatic.testAutoplayDoesNotOpenAndPlayGestureWaitsForReadiness),
            ("automatic play once per gesture",automatic.testOneHandoffUntilANewGestureEvenAfterFailureReturnOrSourceChange),
            ("automatic play safety bounds",automatic.testNavigationAndGestureBoundsRejectStaleHiddenMalformedAndProtectedMedia),
            ("automatic play preference",automatic.testDisabledPreferenceConsumesGestureRatherThanLaunchingWhenReenabled),
            ("automatic play selection",automatic.testNewestPreparedIntentWinsAndFallbacksUseTheSameElementIntent),
            ("conditional video bar",automatic.testVideoBarOnlyHasActionableNativeSources),
            ("automatic play bounded guard",automatic.testBusyPageBoundNeverEvictsATokenAndReopensOldVideo),
            ("HLS owned package round trip", hls.testPackageOwnershipAndJournalRoundTrip),
            ("HLS package boundaries", hls.testUnownedLinkedAndDamagedPackagesAreRejected),
            ("browser restoration privacy", savedState.testRestorationSeparatesHomeWebsiteAndExactPage),
            ("bookmark address bounds", savedState.testBookmarkInputIsBoundedAndKeepsIntentionalPageIdentifiers),
            ("offline catalogue recovery", offline.testRecoveryRestoresOrphansAndCorruptIndexWithoutChangingFiles),
            ("offline recovery preserves names", offline.testRecoveryPreservesHealthyNamesAndRecognizesUnlistedFiles),
            ("offline save reload remove", offline.testSaveReloadAndRemoveWithoutRetainingRemoteAddress),
            ("offline file ownership", offline.testMissingChangedAndSymlinkFilesCannotBeOpened),
            ("offline catalogue integrity", offline.testCorruptCatalogueIsNotSilentlyOverwritten),
            ("offline catalogue read boundaries", offline.testOversizedAndLinkedCatalogueAreRejected),
            ("spherical container metadata", spherical.testActualMovieHierarchyAndExplicitPacking),
            ("cropped spherical projection", spherical.testCroppedMetadataOnlyAcceptsSupportedCenteredProjection),
            ("untrusted spherical metadata", spherical.testMalformedUntrustedMetadataIsRejected),
            ("finder same-page format provenance", quality.testFinderPreservesOnlyExactPageFormatContext),
            ("finite clear HLS plan",clearHLS.testFiniteClearMuxedPlanPreservesPublishedResourceAndSequence),
            ("clear HLS rejects unsupported protection and topology",clearHLS.testRejectsEncryptedLiveFragmentedAndDiscontinuousSources),
            ("clear HLS duration and resource validation",clearHLS.testRejectsInvalidDurationOrMissingSegmentWithoutSilentlyTruncating),
            ("highest exact published rendition", quality.testHighestPublishedSupportedRenditionPreservesExactURI),
            ("HLS parent relationships", quality.testParentContextAndUnknownFormatsRetainMaster),
            ("explicit format detection", quality.testExplicitFormatLabelsAndConflicts),
            ("conservative image packing detection", quality.testImagePackingRejectsAmbiguousAndLowTexture),
            ("large disparity and occlusion",quality.testStereoPackingWithLargeDepthDisparityVerticalOffsetAndOcclusion),
            ("expanded stereo false positives",quality.testExpandedStereoSearchRejectsUnrelatedEyesAndIsBounded),
            ("published HLS resource graph",quality.testHLSReferencesKeepPublishedURLsAndResourceRoles),
            ("supported candidate sources", media.testSupportedCandidates),
            ("unsupported sources", media.testRejectedSchemesAndFormats),
            ("encrypted media", media.testEncryptionTakesPrecedence),
            ("token redaction", media.testDisplayRedactsTokens),
            ("default media selection", media.testDefaultSelectionPrefersPreparedDirectVideoOverInactiveFallback),
            ("browser addresses", media.testBrowserAddressValidation),
            ("detector JSON contract", media.testDetectorJSONContract),
            ("hemisphere and UV orientation", projection.testHemisphereLooksForwardAndUVOrientation),
            ("sphere seams and radius", projection.testSphereSeamClosesAndRadiusIsConstant),
            ("inward triangle winding", projection.testTriangleWindingFacesViewer),
            ("independent stereo mapping", projection.testStereoRegionsAreIndependentOfProjection),
            ("eye dimensions", projection.testEyeDimensions),
            ("material presentation orientation", projection.testMaterialXMappingKeepsNorthAtTopOfEachDecodedEye),
            ("cookie boundaries", cookies.testDomainAndPathBoundaries),
            ("cookie path prefix", cookies.testExactCookiePathDoesNotMatchSiblingPrefix),
            ("library URL boundaries", library.testLibraryResolvesRelativeLinksAndFiltersUnsafeURLs),
            ("library projection and stereo", library.testProjectionAndStereoAreIndependentAndExplicit),
            ("library unsupported formats", library.testUnsupportedProjectionPackingAndMaskingAreNotGuessed),
            ("library access and invalid documents", library.testAccessAndInvalidDocumentsFailWithoutExposingSecrets),
            ("library stream validation", library.testStreamURLValidationAndRedaction),
            ("library bounds", library.testLibraryBoundsAndOversizedDocuments),
            ("report privacy", diagnostics.testReportOmitsSensitiveCandidateAndErrorData),
            ("timeout and webpage diagnostics", diagnostics.testTimeoutAndWebsiteMediaDiagnosticsAreExplicitAndPrivate),
            ("report format classification", diagnostics.testReportClassifiesFormatsWithoutClaimingPlayback),
            ("report bounds", diagnostics.testReportsAreBoundedAndDoNotIncludeUnknownErrorDomains),
            ("server response guidance", diagnostics.testServerResponseHintUsesStructuredErrorCodeOnly),
            ("explicit native HTTP status redaction", diagnostics.testCoreMediaReportedHTTPStatusRetainsOnlyExplicitBoundedDigits),
            ("missing resource guidance", diagnostics.testMissingResourceHintDoesNotInventHTTPStatusOrExposeDetails),
            ("complete flat frame", projection.testScreenFitsCompleteFrameWithUprightUVs),
            ("resolved formats and private display", extraction.testResolvedFormatsAndPrivateDisplay),
            ("unsupported extraction features", extraction.testUnsupportedFeaturesRemainBlocked),
            ("request context advisory", extraction.testHeaderAdvisoryDoesNotBlockOrExposeRequestInformation),
            ("automatic playlist label", extraction.testAutomaticPlaylistLabelIsExplicitAndPrivate),
            ("resolved URL boundaries", extraction.testUnsafeResolvedSourcesAreRejected),
            ("resolved result bounds", extraction.testMalformedAndOversizedResultsAreRejected),
            ("resolved error privacy", extraction.testRemoteStatusCannotBecomeAnErrorDescription)
        ]
        for (name, test) in tests {
            let before = CheckResults.failures
            do { try test() } catch { CheckResults.failures += 1; print("FAIL \(name): \(error)") }
            print("\(before == CheckResults.failures ? "PASS" : "FAIL"): \(name)")
        }
        let session = SessionDiagnosticsTests()
        let privacy = PrivacyControlTests()
        let snapshots = BrowserCookieSnapshotTests()
        let asyncTests: [(String, () async throws -> Void)] = [
            ("browser cookie scope and expiry",snapshots.testFreshCookiesAreNormallyScopedAndExpiredCookiesAreExcluded),
            ("browser cookie timeout and late reply",snapshots.testTimeoutUsesPreviousSnapshotAndLateReplyCanRefreshWithoutDoubleCompletion),
            ("browser cookie clearing epoch",snapshots.testClearReleasesWaitingReadAndRejectsRepliesFromBeforeLogout),
            ("browser cookie cancellation",snapshots.testCancellationReleasesWaiterAndLatePlatformReplyDoesNotResumeItTwice),
            ("browser cookie reply ordering",snapshots.testOutOfOrderRepliesNeverRestoreAnOlderSnapshot),
            ("privacy off snapshot", privacy.testDisabledRecordingCreatesNoHistoryAndExplicitSnapshotRemainsAvailable),
            ("privacy opt-in boundaries", privacy.testOptOutStopsWritesAndOptInDisclosesRecordingBoundaries),
            ("privacy delete and rotate", privacy.testDeleteRemovesAllOwnedSessionsMarkersAndResetsIdentifiersWithoutFollowingLinks),
            ("privacy export deletion", privacy.testExportDeletionOnlyRemovesOwnedUUIDFilesAndKeepsExternalTargets),
            ("privacy catalogue links", privacy.testClearingCatalogueLinksKeepsVideoBytesAndRemovesOldDiagnosticBackup),
            ("testAttemptsCorrelateWithoutPersistingPrivateURLs", session.testAttemptsCorrelateWithoutPersistingPrivateURLs),
            ("testRetainedSessionsRecoverHistoryAndMarkTornRecords", session.testRetainedSessionsRecoverHistoryAndMarkTornRecords),
            ("testRedactionAlsoAppliesToUntrustedRestoredEvents", session.testRedactionAlsoAppliesToUntrustedRestoredEvents),
            ("testCoverageMakesStorageLimitsAndFailuresExplicit", session.testCoverageMakesStorageLimitsAndFailuresExplicit),
            ("testMediaPollingDeduplicatesWithoutLosingStateTransitions", session.testMediaPollingDeduplicatesWithoutLosingStateTransitions),
            ("testFullExportRetainsEventsBeyondTheScreenPreviewSize", session.testFullExportRetainsEventsBeyondTheScreenPreviewSize),
            ("testRetentionKeepsCurrentSessionAndNeverFollowsLinkedFiles", session.testRetentionKeepsCurrentSessionAndNeverFollowsLinkedFiles)
        ]
        for (name, test) in asyncTests {
            let before = CheckResults.failures
            do { try await test() } catch { CheckResults.failures += 1; print("FAIL \(name): \(error)") }
            print("\(before == CheckResults.failures ? "PASS" : "FAIL"): \(name)")
        }
        print("\(tests.count + asyncTests.count) tests; \(CheckResults.checks) assertions; \(CheckResults.failures) failures")
        if CheckResults.failures > 0 { exit(1) }
    }
}
