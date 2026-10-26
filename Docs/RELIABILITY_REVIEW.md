# Reliability review — 25 October 2026

**0.3.4 follow-up:** the webpage loading report exposed a reproducible direct-gesture restriction in the browser policy. See [the follow-up investigation](WEB_PLAYBACK_POLICY.md) for the old/new policy comparison, current tests and live-site acceptance still pending. The 0.3.3 review below remains historical evidence.

Version 0.3.3 (build 10) is a playback, navigation and diagnostic reliability update. No successful live Pornhub playback has been established. This review covers the application source, its embedded-resolver contract, test fixtures, and release packaging; it cannot establish that every possible defect is absent.

## Delivered and tested

- 0.3.3 build 10 installed in “VisionStream visionOS 26”; left closed for the user to reopen. Existing browser storage/preferences are retained; a live login restoration check is pending.
- Final matrix: **59 native Release tests pass on each of visionOS 26/27**, 118 executions, zero failures/skips. WebKit reports presented frames for CC0 MP4/HLS (1024×512) and public NASA media (2160×1080). Native NASA extraction/rendering and the private 2880×1440 MP4/controls also pass.
- 34 core tests / 923 assertions, 34 Swift Package tests, 16 resolver tests, 11 HTTPS fixture tests and 10 JavaScript detector tests pass. Clean simulator build, unsigned device archive and static analysis pass.
- Evidence: `TestResults/diagnostics-test-matrix.json`, `diagnostics-ui-acceptance.json`, `diagnostics-release-binary.json` and the individual build/test logs. The source ZIP and unsigned archive ZIP are updated at the project root. Previous 0.3.2 packages remain under `DerivedData/ReleaseHistory/0.3.2/`.
- **Live Pornhub compatibility remains unresolved. Physical Vision Pro testing and visible updated control acceptance remain pending.** These were not replaced by simulator/model test claims.

## Packaged-source verification

The release source ZIP was extracted to a fresh temporary directory with spaces in its path. A clean Release build-for-testing succeeded using only that package and Xcode, followed by a passing embedded-extractor/public-NASA native rendering smoke test (1 passed, zero failures/skips). No private sample was included. The temporary source/build/result bundle was removed; its build log, runtime log and summary are retained as `TestResults/packaged-source-*`. Final app/build/test source hashes are unchanged, and the package is regenerated only to add this evidence. The packaged device archive has matching executable/debug-symbol UUIDs.

## Findings addressed

| Finding | Change | Validation boundary |
| --- | --- | --- |
| Seeking the supplied MP4 to 5 s actually landed at about 4.27 s | Use sample-accurate seek tolerances; publish pending targets and accumulate rapid skips from them | Real-file seek/pause/resume and controlled MP4/HLS tests |
| Replay could fail because displayed time lagged the end notification | Read the actual player clock when deciding whether to restart | End/replay checks on the supplied sample and controlled MP4/HLS |
| A late GPU callback could overwrite failure diagnostics or restore stale video | Reject frames after readiness ends; stop/release the failed renderer and its displayed model; guard asynchronous material assignment | Real renderer failure/late-frame regression |
| Old page candidates/status remained usable briefly after requesting navigation | Clear synchronously; gate departing-page reports until commit; use the requested finder address | Delayed-navigation regression with an explicit old-page scan |
| A finder/library stream could differ from the page's current blob/variant, leaving page audio/video running | Use public WebKit pause-all-media as fallback after successful native opening; no persistent suspension | Inline MP4/HLS/public media pause and resume checks |
| Missing widths could hide known quality and leave 240p ahead of 1440p | Sort by available reported height/width and show known height in labels | Resolver/core tests; no geometry inferred |
| Valid MIME types with whitespace before parameters were rejected | Normalize MIME case, whitespace and parameters consistently | Core compatibility tests |
| A preparation timeout and player rejection could produce indistinguishable reports | Fixed failure-reason values and item-status snapshot; collect numeric error logs before stop removes the player item | Controlled delayed-response test, including preservation after cancelled asset loading |
| Regular webpage playback failures were invisible in Playback details | Read only MediaError.code, readyState, networkState and paused; show fixed error guidance without reading MediaError.message | Detector/core privacy tests and attached WKWebView presented-frame/playback/error tests |
| Arbitrary numeric player-log errors could be interpreted as HTTP status | Require the HTTP error domain for mediaHTTPStatus; keep other safe numeric codes separately | Core tests reject CoreMedia:404 as evidence of an HTTP response |
| A shared parent playlist could retain an earlier MP4 MIME label | Promote the deduplicated entry to HLS when a supplied parent is recognized | Both format-order permutations in resolver tests |
| Python boolean dimensions violate Swift's integer decoding contract | Treat boolean dimensions as unknown integers (0) | Resolver regression |
| Refused/cancelled immersive opening could pause a working webpage | Pause only after the system reports opened; expose Cancel through preparation/opening | Compiled; visible system-transition acceptance remains manual |
| Navigation/cancellation could finish while immersive opening awaited visionOS | Recheck operation, navigation version, readiness and cancellation after opening; dismiss stale opened spaces | Compiled; real scene-race acceptance remains manual |
| Invalid/non-finite seekable start/end values could reach the controls | Filter start, duration and computed end before publishing a range | Compiled; existing native seek/recovery tests retained |
| Physical headset tests may use a LAN fixture/library address | Add the local-network usage description; no discovery or network-permission bypass | Plist/build validation; physical permission prompt untested |

The initial webpage test used a detached WKWebView, where play remained pending. An HTTPS page alone did not cure that. Attaching it to the app's visible window made playback possible. Later tests also needed to await the specific committed document, rather than accept the previous page's still-published state; that exposed and motivated synchronous production navigation invalidation. The final tests additionally use requestVideoFrameCallback to confirm decoded, presented video instead of merely audio-clock progress. The initial real-file checks exposed actual approximate-seek and end/replay defects. Failed/stopped attempts remain in TestResults, and the final matrix must be used for release validation. UTC timestamps with microseconds prevent result-name collisions across the daylight-saving clock change.

## Reviewed areas and remaining limits

- **Browser:** normal persistent WebKit storage, navigation cancellation, isolated DOM detection, frame/open-shadow-root bounds, popup handling and JS dialogs. No page-content interception or invented account/age state. Production player scripts, input routing, content-process crashes and normal access checks still need user-assisted observation. Saved-page restoration deliberately omits queries/fragments, so query-based video pages may need reopening; this privacy tradeoff does not restore a complete browsing history. A page HTTP 200 is not video success. HTML error code 0 does not establish that video is moving, and a site may display its own JavaScript error without a MediaError.
- **Source discovery:** HTTPS input/output contracts, bounded results, no helper executables/remote updates, no fabricated extractor cookies, restriction merging, exact parent URL retention and private error text. The embedded extractor still has per-socket timeouts rather than a hard whole-job deadline; a cancelled running job can delay the next queued job. Browser credentials are not imported into Python. Do not add an access workaround without a supported legitimate contract and evidence.
- **Native transport:** MP4/HLS asset readiness/protection checks, generation cancellation, scoped public cookie handoff, timeline/pause/seek recovery and no whole-video download task. Expiring media, multi-host cookie policies, request-context requirements, network loss and HLS discontinuities remain production compatibility gates. No arbitrary HTTP-header injection or proxy was added.
- **Rendering:** equirectangular VR180/VR360, independent packed eye layout, vertical orientation, paused texture/mesh updates, bounded texture allocation and IOSurface retention. Approximate SDR treatment, 2048-pixel eye textures and an 8192-axis input limit remain. HDR, MV-HEVC, APMP, fisheye/cubemap/mesh projections and passthrough masking are unsupported. Physical eye isolation, tracking, comfort, performance and thermals are unverified.
- **Lifecycle and controls:** native Playback window, return-to-page cleanup, cancellation checks and audio-session ownership. Physical system interruptions, route changes, background/resume, Crown dismissal and visible control recall/placement still need a real headset. The previously reported BaDoinkVR controls/viewing issue has not passed acceptance.
- **Installation:** simulator and unsigned device builds can be validated here. A development team, pairing and physical Vision Pro are still needed for installation on hardware. App Store distribution and encryption export classification are not completed.

## What remains useful when the user returns

When the user returns, try the website's own Play button in version 0.3.3 and share Playback details while the failure is still present, before choosing Watch in VR. The new `webMedia` fields can separate a reported network/decode/source error from an unstarted video. If ordinary playback succeeds, make one native attempt and share its distinct failure reason and numeric log codes. Do not share credentials, cookies, signed links or explicit screenshots.

HTML media codes and states follow the [HTML standard](https://html.spec.whatwg.org/multipage/media.html#mediaerror). Native log fields are documented by [Apple](https://developer.apple.com/documentation/avfoundation/avplayeritemerrorlogevent); error comments and URLs are never retained. The local-network purpose string uses [Apple's Info.plist key](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription).

## 0.3.5 native handoff follow-up

See [the native handoff investigation](NATIVE_HANDOFF.md) for the new empty-attribute and default-selection fixes, supported User-Agent preservation, controlled validation, and the confirmed 0.3.4 HLS preparation timeout. Native Pornhub compatibility remains unresolved.
