# Current additions — 0.6.0

## Reclined viewing (0.12.0)

**Recenter** starts a three-second countdown. Look where the video should face; the renderer captures the full head orientation, including upward pitch and side tilt. It keeps that orientation fixed while you look around naturally. **Position → Video tilt** adjusts the video up/down by up to 90 degrees relative to the captured centre without moving the controls. **Reset tilt** removes that adjustment; **Reset upright** levels the video with the room and keeps the controls facing you. Recenter clears manual tilt. Each new immersive session starts centred on the current head pose; quality changes preserve the current position.

Playback controls are now a glass-backed RealityView attachment, rather than a separate system window. Position, Format and Quality expand within that surface because the former window popovers do not reliably present from attachments. Recenter positions the actual visible controls below the captured viewing direction. Return to page opens the browser and waits for its view to appear before dismissing immersion. System dismissal also restores the browser. The single WKWebView and its live webpage remain in AppModel. No head pose or viewing-angle history is saved. Physical Vision Pro gaze/pinch and reclining comfort remain unverified.


Automatic-playback validation (0.11.0): `node Scripts/test_video_detector.js` exercises the shipped isolated DOM script with modelled trusted events. `sh Scripts/test_webkit_input.sh` additionally delivers public AppKit input to a real WKWebView using original local CC0 video, proving synthetic clicks are rejected and WebKit-trusted clicks produce the intent. That check needs a graphical Mac session; it is not physical Vision Pro gaze/pinch acceptance. Native tests validate the isolated bridge, once-per-gesture policy and persistent opt-out. The `auto-play` scene starts page playback programmatically as a negative control, then injects an attested signal at the isolated bridge boundary and verifies the real native scene, highest 4K, VR180/SBS, return/re-entry and conditional bar. It never calls the manual Watch action. This boundary injection is disclosed and is not a synthetic human gesture on the simulator.

Run `python3 Scripts/run_scene_checks.py --runtime 26.0 --build-root DerivedData/SignedSimulator --cases auto-play forms controls downloads` after building Release. Only disposable Automation Lab simulators and original CC0 loopback sources are used. Full native suites have explicit opt-in skips for external/private-media probes; no website compatibility is inferred from these controlled tests. The current matrix and any earlier failures are retained in `TestResults/automatic-playback-0.11.0/` for the private development handover; local reports are excluded from the public GitHub source package.


For 0.9.1, `SaveQueueTests` covers FIFO/mixed MP4+HLS, capacity/duplicates, cancellation/removal, failure continuation and privacy. The `downloads` scene adds a second waiting video while the first saves, then removes it and verifies the first save continues. Optional native background-download feasibility checks remain separate from the app's normal foreground recovery; retain failures and list opt-in skips when reporting suites.

The `forms` scenario now mounts Bookmarks and Browser settings. `saved-state` invokes their actual save/open/settings actions and checks Home versus origin-only versus exact-page reopening. Import/recovery native tests keep original MP4 bytes intact, cancel a large copy, rebuild a damaged catalogue, and decode the recovered local file.

`HLSOfflineLibraryTests` exercises the product downloader with one fixed Apple public developer HLS sample: pause/resume, completion, catalogue reload, local package rendering and deletion. Enable it explicitly with `--hls-offline-public-probe`. This does not grant arbitrary site access or test physical suspension/relaunch. `--hls-offline-probe` separately enables the lower-level platform probe; with no public flag that uses local HTTPS and currently fails in the background service. Use normal ad-hoc simulator signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`); unsigned simulator builds failed to connect to that service. The Mac trust store is not changed to work around local-background TLS failures.

The simulator-only `VISIONSTREAM_TEST_REVIEW_PANEL` launch setting can hold one of `address`, `stream`, `finder`, `library`, `details`, `downloads`, `bookmarks` or `settings` open after it mounts. It is accepted only alongside the `forms` scenario, the existing HTTPS loopback origin and a fresh UUID. Unknown panel/scenario combinations fail configuration. Downloads/bookmarks review uses only original local calibration data. Launch the app test scenario directly to keep the view visible; the normal host runner terminates passed scenarios. This is a developer inspection fixture, not an unrestricted UI endpoint or synthetic-input test.

`--cases soak --soak-seconds 600` runs repeated 4K decoding, loop seeks, format restoration and Highest/Adaptive changes. It records simulator resident memory and decoded-frame progression; this is not a physical thermal/GPU/battery measurement. The bound is configurable from 60 to 1,800 seconds. The driver preserves its normal per-step deadlines and adds only the requested soak duration to its scenario deadline.

```sh
python3 Scripts/run_scene_checks.py --runtime 26.0 --build-root DerivedData/SignedSimulator \
  --cases forms saved-state downloads controls quality4k soak --soak-seconds 600 \
  --output TestResults/my-06-scene-check
```

# Version 0.5.0 additions (historical)

The `downloads` scenario invokes the browser’s production download action, observes the real Downloads sheet, waits for the original CC0 MP4 to be validated/listed, closes and reopens the sheet, invokes its Play action, checks a file-backed AVPlayer in the actual immersive scene, runs transport/format/exit checks and removes the saved copy. The `forms` scenario now includes Downloads. Both are restricted to the existing dedicated-lab/HTTPS-loopback configuration.

`DownloadNativeTests` covers save/reload/offline render/seek/delete, legitimately scoped browser cookies, HLS rejection, immediate and active cancellation, bad/oversized responses, free-space reserve and same-origin versus cross-origin redirects. `AudioLifecycleTests` posts real system notification names to check interruption, permitted resume, pause/stop precedence, output disconnection and media reset. These are simulator integration tests; they do not emulate Bluetooth hardware or certify gaze/pinch usability.

A controlled truncated-prefix fixture verifies spherical metadata recovery. The optional fixed NASA check remains network-dependent and its failures remain recorded. Version 0.5.0 retries a metadata-prefix read once only for transient network errors, within eight seconds per attempt; range/size/HTTP rejection is not retried. No arbitrary external site is enabled by the scene driver.

Example current real-scene run:

```sh
python3 Scripts/run_scene_checks.py --runtime 26.0 \
  --cases forms downloads controls quality4k mp4 hls library library-hls cancel unsupported reentry \
  --output TestResults/my-release-check
```

The build must finish before running tests. Use a newly named output directory. The runner creates/deletes its own dedicated simulator when none is specified. A user simulator, browser login or private webpage is never used for these scenarios.

---

# Unattended simulator testing

VisionStream 0.3.6 adds repeatable scene integration tests that require no human clicks. They run the actual browser, sheets, native player, immersive space, RealityKit renderer and separate controls window. The runner uses the production form actions and model controls inside the app; it does not synthesize touch, exercise hit targets or replace visual/headset acceptance.

Apple documents that [XCUITest is unavailable for native visionOS SDK applications](https://developer.apple.com/documentation/xcuiautomation). Device Hub pointer and keyboard forwarding have also been inconsistent in this environment. A captured Command–L opened the address sheet, but repeated shortcut/navigation attempts did not provide reliable end-to-end input. Keyboard shortcuts remain an additional interaction route, not the unattended test mechanism.

## Run

Build the Release simulator app and test bundle first:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project VisionStream.xcodeproj -scheme VisionStream -configuration Release \
  -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath DerivedData/SignedSimulator CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
python3 Scripts/run_scene_checks.py --runtime 26.0 --build-root DerivedData/SignedSimulator
python3 Scripts/run_scene_checks.py --runtime 27.0 --build-root DerivedData/SignedSimulator
```

Each invocation creates a disposable simulator, serves original CC0 calibration media over loopback HTTPS, installs the app, runs each scenario in a fresh app process, records JSON evidence, stops the server and deletes the simulator. It does not use the user's saved browser session. A temporary test certificate is installed only in that disposable simulator; the Mac trust store is unchanged. Deletion removes the test certificate. An interrupted run may leave a simulator named “VisionStream Automation Lab…”; remove only that dedicated test device after checking its identifier.

The default cases include two consecutive immersive entries/exits in one app process and cover address/finder/library/details/manual-entry forms, webpage MP4 and HLS playback, native decoded frames, cookie-authenticated library MP4/HLS, pause/resume and seeks, all nine presentation/layout bindings on the real renderer, recenter requests, cancellation, unsupported sources, exit and browser restoration. Eye flags and recenter requests do not verify physical stereo separation or headset pose.

Optional `--public-extraction` adds one fixed public-domain NASA HTTPS sample through the actual Find streams sheet and on-device extractor. It is a network-dependent check. It does not grant the runner arbitrary website navigation or access to private browser credentials.

Use `--cases forms mp4 reentry` for a focused run. `--output TestResults/your-new-folder` retains evidence in a chosen new directory. Existing dedicated lab devices and their fixture sessions can be reused with `--simulator` and `--fixture-session`; these are not deleted automatically. Do not supply a personal simulator.

The native XCTest runner also supports `--output TestResults/new-native-folder` for isolated logs and a unique test configuration. Use a separate dedicated simulator for each concurrent run.

## Evidence and boundaries

`summary.json` records the app version/build, runtime and each case result. Per-case files record named checks and fixed failure codes. Every launch uses a new UUID and the host rejects results from earlier launches. Tests fail on a deadline rather than treating an already-ready player as success.

Opt-in read-only telemetry (`VISIONSTREAM_SIMULATOR_OBSERVE=1`) writes `Library/Caches/VisionStreamAutomation/State.json` inside the app's simulator container. `Scripts/assert_simulator_state.py` checks freshness, types, numeric bounds and clock motion. It never sends input. Reports omit page/media URLs, titles, cookies, headers and raw error descriptions. View lifecycle markers indicate mounting; playback-window attachment is checked separately through UIKit. Browser restoration requires an attached window and a foreground scene (active or inactive, since host focus can be elsewhere). The browser remains backgrounded under the pushed controls window during immersion.

The scene driver and telemetry are compiled only for the simulator. There is no network control endpoint. Scene execution additionally requires an explicit scenario name, UUID and HTTPS origin restricted to localhost/127.0.0.1 with an explicit port. Malformed requested configuration opens the bundled start page instead of restoring a saved website.

These checks can run with the Mac locked because they do not need host input. The Mac locked again before a CUA keyboard check; the scene/native runs and cleanup continued without another unlock. After the user unlocked again, a fresh disposable simulator confirmed Command–L opens the actual address sheet (screenshot plus telemetry). Typing/Return and paste/Return still failed to complete navigation; all three outcomes are recorded in the matrix. That final disposable simulator was also deleted. Computer-use screenshots and keyboard/pointer testing still require an unlocked Mac. The tests do not solve sign-in, age checks, CAPTCHAs, DRM or website restrictions. Prior tool-denied website access is not routed through this runner. Successful calibration streaming does not establish site compatibility. A later user-assisted 0.3.6 HLS success for one Pornhub stream is documented in [the current assessment](PORNHUB.md).

## Window lifecycle correction

The initial runner reproduced a controls panel left alive after exit: the old code dismissed the browser, then tried to close the final controls window before its replacement browser had finished opening. visionOS can ignore dismissal of the last scene. Version 0.3.6 used Apple's [associated controls-window pattern](https://developer.apple.com/documentation/visionos/associating-a-window-with-an-immersive-space): `pushWindow` backgrounds the existing browser, and closing the controls restores that same browser. The historical suite checked backgrounding, real native frames, controls-window removal and browser foreground restoration. Version 0.12.0 instead checks actual attachment mounting, controls popovers, browser window dismissal, reopening before exit and automatic reentry. Both browser and controls use visionOS 26 unique `Window` scenes, matching the single retained WKWebView/player. The controls scene disables restoration and suppresses default launching so a fresh process cannot restore an empty player panel. A focused `--cases interrupted forms` run leaves the first process in immersion, terminates it, then verifies clean browser/forms startup in the next process.

## Results and remaining limits

Version 0.3.6 has passing evidence for ten scenarios on both visionOS 26.0 and 27.0: interrupted playback/relaunch, forms, MP4, HLS, library MP4, library HLS, cancellation, unsupported input, repeated entry/exit and the public NASA finder. The visionOS 27 final scene suite passed in one run. The visionOS 26 final run passed its first eight cases, then its repeat-entry page remained paused at readyState 2; a focused repeat-entry and finder run passed. This is retained as an intermittent simulator inline-autoplay stall, not treated as a resolved website issue. Earlier cold-start forms timed out after receiving HTTP 200 while WebKit still reported loading; a fresh simulator passed after a bounded 45-second load allowance.

The controlled native suites pass 62 tests on each runtime, with two explicit optional skips each. Additional host checks cover 35 Swift core tests (932 standalone assertions), 11 detector tests, 16 resolver tests, 14 HTTPS fixture tests and four evidence-protocol tests. `TestResults/automation-test-matrix.json` links the final evidence and earlier failures.

No physical Vision Pro, stereoscopic visual acceptance, pointer hit-testing, all keyboard shortcuts or live adult-site native playback is certified by these automated results; the later one-stream user-assisted result is recorded separately. The prior website-tool access refusal remains in effect. Authentication and normal website access checks still belong to the user; generic simulator operation no longer depends on their clicks.

## Keyboard routes

[Device Hub](https://developer.apple.com/documentation/xcode/interacting-with-your-visionos-app-in-device-hub) must capture the keyboard. Escape releases that capture, so Return to page uses Command–Shift–B.

| Action | Shortcut |
|---|---|
| Website address / refresh / open direct stream | Command–L / Command–R / Command–O |
| Library / finder / playback details | Command–Shift–L / F / D |
| Watch selected or first available stream | Command–Shift–V |
| Close a sheet | Command–W |
| Play/pause / skip backward/forward | Space / Left / Right |
| Recenter / return | Command–Shift–R / B |
| Screen / VR180 / VR360 | Command–1 / 2 / 3 |
| Mono / side-by-side / top-bottom | Command–Option–1 / 2 / 3 |
| Swap eyes / flip vertically | Command–Option–E / Y |

A later 0.3.7 check observed Command–Option–2 opening Device Hub’s Reports inspector instead of reaching the app. Capture Keyboard therefore does not prevent every host menu shortcut from being consumed. The mode menu belongs to the Playback scene. Shortcuts compile, but only Command–L has a reliable visual observation in the current Device Hub investigation. The unattended scene suite verifies the shared actions rather than claiming keyboard delivery for every shortcut.


## Quality and automatic format regression (0.4.0)

`run_scene_checks.py --cases quality` opens the original CC0 `quality.html` page through the real address action, reads its explicit VR180/SBS metadata, enters the real immersive space, checks actual 1,440×720 decoded frames, exercises transport/mode changes, and returns to the browser. The fixture master lists a 480×240 rendition first and a 1,440×720 rendition second. Native tests separately render the low child to establish the control size, switch quality while paused, verify cancellation/replacement, and exercise a cookie-gated master that issues a legitimate child cookie. The host fixture suite verifies AAC in both media renditions; AVURLAsset's HLS track list is not used as proof of audio presence.

`QualityAndFormatTests` covers exact published URI preservation, unsupported codecs, external audio/subtitle/session context, size bounds, explicit labels and conflicts, image-half matches and ambiguous/low-texture rejection. Automatic detection is intentionally confidence-based. The image fallback requires a VR cue and three agreeing frames; it does not identify arbitrary projections from aspect ratio alone. No test runner accepts arbitrary external site URLs.


## Popover, 4K and embedded-metadata checks (0.4.1)

Run `--cases controls quality quality4k finder --public-extraction` for the new scene regressions. `controls` exercises the actual SwiftUI format/quality actions and popover mounting, with manual/Auto restoration and paused quality switching. `quality4k` verifies the highest published 3,840×1,920 grid and automatic VR180/SBS. `finder` is still restricted to the fixed public NASA sample and now checks automatic VR360/mono and 2,160×1,080 frames. Optional `controls-format`/`controls-quality` scenarios leave a real popover presented for CUA visual inspection when launched directly in a dedicated fixture session; the host runner normally terminates each completed case.

The native public sample regression requires `--public-extraction`. Additional native cases exercise opaque-named spherical MP4s, metadata arriving after a manual choice, Auto restoration, and rejected ignored/oversized byte ranges. `SphericalMetadataTests` covers the pure bounded container/XML parser. These checks do not navigate arbitrary external sites or import private browser credentials.

Finder provenance is covered by `QualityAndFormatTests.testFinderPreservesOnlyExactPageFormatContext`: same-page fragments are accepted, query/video changes and other origins are rejected, ambiguous page videos do not transfer packing, explicit source hints win, and the media source URL remains unchanged.


## Explicit public-preview component checks (0.6.1)

`Scripts/run_visionos_tests.py --public-preview-input /path/to/private-input.json` enables `PublicPreviewAcceptanceTests`. Input is a dictionary with optional `vrBangers`, `virtualReal` and `slr` keys, each containing one object with a `source` field. The source must be the exact HTTPS preview URL already observed through the browser, with the expected media host. Do not invent quality variants, include credentials/headers, import browser cookies or use these tests to access a denied origin.

Keep this temporary input outside the repository. The runner places it only in a temporary test configuration, removes that configuration after the run, and retains site names rather than URLs in session metadata. Platform log URLs are redacted even on timeout. Result bundles are excluded from source packages. The tests delete their own temporary saved videos and write redacted component JSON to the app’s `Caches/VisionStreamPublicPreviewTests` directory. A successful asset check does not prove browser discovery, stereo correctness or the site’s maximum available rendition. Two live checks currently fail; see LIVE_SITE_TESTS.md.
