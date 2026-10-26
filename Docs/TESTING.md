# Version 0.9.1 build 30 — save queue

Verification for 0.12.0: 95 Swift package tests pass; the standalone runner passes 89 methods / 1,797 assertions. Each visionOS 26/27 full native suite passes 185 methods with 12 optional skips and no failures. The 27 combined scene run passes 69 checks. On 26, the first five scene cases pass 57 checks; its last forms dismissal times out and the isolated 12-check forms rerun passes. Initial countdown cancellation and attachment-popover failures were corrected and retained as evidence. See `TestResults/reclined-viewing-0.12.0/matrix.json`. New coverage uses original CC0 fixtures and synthetic head transforms; no new live-site or physical-headset acceptance is claimed.

## Reclined viewing (0.12.0)

**Recenter** starts a three-second countdown. Look where the video should face; the renderer captures the full head orientation, including upward pitch and side tilt. It keeps that orientation fixed while you look around naturally. **Position → Video tilt** adjusts the video up/down by up to 90 degrees relative to the captured centre without moving the controls. **Reset tilt** removes that adjustment; **Reset upright** levels the video with the room and keeps the controls facing you. Recenter clears manual tilt. Each new immersive session starts centred on the current head pose; quality changes preserve the current position.

Playback controls are now a glass-backed RealityView attachment, rather than a separate system window. Position, Format and Quality expand within that surface because the former window popovers do not reliably present from attachments. Recenter positions the actual visible controls below the captured viewing direction. Return to page opens the browser and waits for its view to appear before dismissing immersion. System dismissal also restores the browser. The single WKWebView and its live webpage remain in AppModel. No head pose or viewing-angle history is saved. Physical Vision Pro gaze/pinch and reclining comfort remain unverified.


Current 0.11.0 validation and retained earlier failures are in `TestResults/automatic-playback-0.11.0/matrix.json`. The public-source package excludes local reports; commands in AUTOMATED_TESTING.md recreate controlled tests. No physical headset or new live website test is claimed. The 0.10.0 section below is historical.


Current 0.10.0 evidence is `TestResults/privacy-release-0.10.0/matrix.json`: 78 host core tests, 72 standalone methods/1181 assertions, 174 native methods per runtime (162 pass/12 optional skips/0 fail on visionOS 26 and 27), and 26 Release scene checks. Three dedicated native privacy methods pass separately on both runtimes, including deletion during queued saves and preservation of media. Four submission-script regressions cover safe owner input, draft metadata, HTML escaping and actual generated encryption/contact plist values. Public/network, private local-media and optional native-only offline probes were not enabled; physical headset and live website tests were not performed in this release. Historical results below remain labelled by version.


The browser and finder now enqueue additional saves instead of disabling Save while a transfer runs. Waiting requests are FIFO, removable, duplicate-checked and capped at 20. One transfer runs at a time, and HLS foreground recovery retains its turn. Source links/request context are kept in memory only; quitting clears the queue and expired links fail normally.

Final build30: visionOS26 **155 passed /11 optional skips /0 failed**; visionOS27 **154 passed /12 optional skips /0 failed** (166 methods each). Host core73 and HTTPS fixture19 tests pass. Real forms/Downloads scene checks pass **23 named checks**, including the new waiting-row flow. Final installation preserved all three saved MP4 files and their journals by checksum.

Four new native queue regressions exercise success/failure continuation, cancelling the active save, removing a waiting item, duplicate/capacity limits, private-link-free report snapshots, and HLS recovery before a queued MP4. The mounted Downloads scene also adds and removes a second request while the first is active. The final build extends the existing normal-transport fallback to observed CoreMedia -12884 without asserting what that platform error means.

See [current queue results](../TestResults/save-queue-0.9.1/matrix.json) and [user report assessment](../TestResults/save-queue-0.9.1/user-report-assessment.json). Early failed checks and the independent native-only platform probe are retained there. The native-only background downloader remains environment-dependent; the foreground MP4 fallback and queue are tested separately. No physical headset or universal site support claim is made.

## Historical 0.9.0 validation

## Final validation

Both native suites pass **151 tests, 11 optional skips, zero failures** on visionOS 26 and 27 (162 methods each). Host Swift Package: **73 pass**. Standalone: **67 methods / 1,152 assertions pass**. HTTPS fixture server: **19 pass**. Automation observation: **4 pass**. Final mounted-scene checks pass all **31 named checks** across forms, Downloads, format controls and quality controls. These are real scenes with shared actions, not synthetic gaze/pinch input.

The complete AppModel workflow recovers a controlled native background identity failure, saves the highest published **3840 × 1920** HLS rendition as MP4 without re-encoding, retains audio, decodes it through the immersive renderer and reloads its catalogue. Normal narrow-path response cookies, actual segment-8 HTTP 404, cancellation, malformed media, interrupted recovery, privacy, and cleanup regressions pass. Separate MP4 remux seek validation also passes. Native local background HLS download/decode passes independently. Release simulator and unsigned device archive build successfully; the matching device dSYM is retained.

Known failed exploratory alternatives (legacy native download API, native HLS export and raw TS playback) are recorded in the matrix and were not shipped as working features. Early harness/assertion failures and corrections are disclosed there too. No live Pornhub download or physical-headset success is claimed.

## 0.9.0 resource tracing and foreground save recovery

The current implementation adds bounded checks of exact published HLS resources after selected native save failures. Reports correlate playlist/dependency/segment role, sequence, HTTP status and a per-session resource ID without exposing private URLs or credentials. Foreground range/header checks are labelled separately from native background traffic; a successful check does not prove the background request was equivalent.

A controlled simulator fixture proved that Apple's background HLS service can send a different User-Agent from the actual working WebKit player despite public request options. Supported clear on-demand MPEG-TS can now recover as an MP4 through foreground URLSession transport with the actual browser identity and normally scoped cookies. A local-only LGPL FFmpeg framework remuxes without re-encoding; native playback and duration are checked before the saved file is committed. See `Docs/MEDIA_RUNTIME.md` for supported formats, limits and rebuilding. Other HLS packaging forms continue to need engineering; this is not universal HLS downloading.

Automatic stereo analysis now handles larger, locally varying disparity and partial occlusion using bounded regional comparison and three-frame agreement. It keeps metadata, explicit mono and manual choices authoritative and rejects unrelated/ambiguous images. No decoded image samples are stored in diagnostics.

The native background HTTP 404 resource remains unidentified. A new user-supplied 0.9.0 report on 26 October confirms two foreground MP4 saves completed and local VR playback decoded1440×720. Passive inspection subsequently found all three completed copies in the local catalogue. No new agent-controlled remote-site access was performed. This verifies those fallback attempts, not universal website support; automatic format selection for the second live stream remains unverified because the final snapshot is manual.


Host Swift Package tests pass **70 methods**. The standalone subset passes **64 methods / 1,131 assertions**. Full native suites pass **141 methods on visionOS 26** (11 optional skips) and **143 on visionOS 27** (nine optional skips), with zero failures; each run contains 152 methods. Apple’s public HLS offline acceptance is enabled on both. The existing private local-file checks run on 27 only. No new Pornhub requests are made by the agent. Original fixture/observation tests also pass. Physical-headset acceptance remains open.

The new hard stereo regression fails before the matcher change and passes afterward for both SBS and TB. It includes ±9–10 samples of depth-dependent horizontal disparity, one sample of vertical offset, a brightness difference and an occluded quadrant. The expanded search requires at least eight strongly matched textured regions distributed over three rows and columns, separation from the competing packing and three agreeing decoded frames. Twelve independent-image negative controls with a coincidental duplicated patch remain inconclusive, as do existing flat/low-texture/ambiguous controls. Bounds reject oversized analysis arrays. The optimized host test takes approximately 2 ms for both hard layouts; this is not a physical Vision Pro performance measurement.

New original CC0 MP4/HLS fixtures exercise actual AVPlayer, Metal and RealityKit decoding and automatically select VR180/SBS or VR360/TB without filename/metadata hints, including re-enabling Auto. This verifies the implemented improvement under those conditions; the unavailable second user stream has not yet been confirmed fixed. New reports include quantized packing scores, matched-region counts and whether the wider search was needed. Images/luma samples are not saved.

The local background-downloader logs show seven parallel media requests returning 404 during the second real save. They do not disclose the private URL, so that observation does not identify a particular segment. A local cache inspection finds no retained playlist response. A separate controlled loopback system-offline probe fails with CoreMedia -12884; its failed result is retained separately from the passing public Apple sample.

After a user-initiated native HLS -12938 failure, the app now inspects the exact published source/selected playlists and a bounded sample of initialization/auxiliary/segment dependencies using normal scoped cookies and the actual browser User-Agent. Availability probes send GET with Range bytes=0-1 and cancel at response headers. They do not download a full media body, follow redirects, rewrite URLs/playlists, retrieve encryption keys or change authentication. A foreground status is explicitly distinguished from the original background download failure. Successful checks cannot turn a failed download into success or prove the background requests were equivalent.

Native controlled tests identify the deliberately missing segment at sequence 732, preserve scoped authentication, prove key/redirect targets are not fetched and verify that the native metric selectors are actually implemented. A real-source fresh report is required to establish which published dependency is missing or whether the failure is specific to the background request context. No working live-source fix is claimed. See [the current recovery matrix](../TestResults/resource-recovery-0.9.0/matrix.json).

---

## Historical 0.7.1 validation

# Version 0.7.1 build 25 — explicit native HTTP failures

The complete retained session-history implementation from 0.7.0 remains in place, including persistent gap markers. A subsequent passive inspection of the user simulator’s existing local system logs identifies **HTTP 404: File Not Found** during the two failed HLS saves. No new remote website request was made. The failing resource itself is private/redacted and remains unidentified; a successful foreground video playlist does not prove every offline request succeeds. No missing-resource URL is guessed or rewritten.

A bounded CoreMedia error-description parser now retains only an explicit three-digit HTTP status and gives a precise missing-resource message. It does not classify every -12938 as HTTP 404. Unit tests reject unrelated domains, embedded text and oversized descriptions and verify that private text never reaches the hint or stored codes. Host Swift Package tests pass **67 methods**; the standalone subset passes **61 methods / 1,099 assertions**. The full visionOS 27 run passes **136 methods**, with nine optional skips. The full visionOS 26 run records **133 passes, one delayed-webpage frame timeout and 11 optional skips**; its subsequent focused run passes all 12 methods, including that browser regression, HTTP diagnostics and session integration. The failed full run is retained and is not described as clean. The final 27 scene form/export check passes nine named checks. Current native/runtime and installation results are linked in [the 0.7.1 matrix](../TestResults/session-history-0.7.1/matrix.json). The earlier failed NASA checks remain unresolved in the 0.7.0 evidence.

The configured User-Agent hypothesis did not fix the two user attempts. This release improves history durability and HTTP reporting; it does not claim successful Pornhub HLS saving. Physical-headset and background lifecycle acceptance remain open.

---

## Historical 0.7.0 validation

# Version 0.7.0 build 24 — correlated session history

Playback details now exports a schema-2 history across retained app sessions. It records app-observed navigation and video state, separate attempt IDs, related sources, retries, quality and format decisions, native playback metrics/errors, MP4 transfers, HLS tasks and offline playback. Paths, query values, titles, credentials, cookies, header values and page content are excluded; source hosts are included. The HMAC identity key is ephemeral and is never exported. History cannot reconstruct actions from older builds or replace a complete WebKit network trace. Coverage and storage limits are explicit in each report.

Final controlled native suites pass **133 methods on visionOS 26** (11 optional skips) and **135 on visionOS 27** (nine optional skips), with zero failures in those runs. Both contain 144 methods. The optional NASA checks are disabled in these final runs; their separate observed failures remain unresolved and are retained below. The public Apple offline probe is enabled on both; the existing private local file is enabled only on 27.

Host Swift Package tests pass **66 methods**. The fallback standalone runner passes **60 methods / 1,090 assertions** (it runs a subset of the package methods). Four automation-observation tests and 18 media-fixture tests pass. The new tests cover source/attempt correlation, distinct retries, retained sessions, torn records, redaction of restored events, storage failures and limits (including an incomplete tail after relaunch), polling deduplication, symlink rejection, and exports larger than the 200,000-character screen preview. Native integration covers browsing → streaming → MP4 save → offline playback and keeps another video's failed download separate from the current playback snapshot.

Final real app-scene form checks pass **nine named checks on each runtime**. The unchanged control actions also pass 13 named checks on the earlier 0.7.0 revision. The actual Playback details view creates a full schema-2 JSON file; an independent check found seven retained sessions, 87 events in each final-runtime check, explicit coverage and no raw URLs. These are mounted scene/shared-action checks, not synthetic touch or physical headset acceptance.

The first broad native runs exposed a transient website-data test timeout on visionOS 26 and public NASA webpage-playback failures on both runtimes. A focused final-build rerun passed all nine new history tests but reproduced the NASA webpage failure. The NASA download also timed out during the later visionOS 26 run. A separate bounded server probe returned HTTP 200 to HEAD and HTTP 206 with the requested two bytes to Range; this does not establish why WebKit/native transfer stalled. These failed trials are retained, not counted as successful acceptance. Controlled MP4/HLS webpages and Highest 4K renderer checks continue to pass. See the current matrix for final run counts and enabled probes.

The HLS compatibility hypothesis explicitly configures the actual browser User-Agent on a newly created background asset-download session, in addition to the existing public AVURLAsset option. No authentication, Origin or Referer headers are added. Existing system tasks retain their OS-managed request configuration. Apple sample download acceptance passes with this option; the user’s new 0.7.0 report confirms that **both real-source attempts still fail with -12938 despite the option being configured**. The report distinguishes asset preparation, task creation, native-selected variants, available resource metrics and final offline validation. A configured option is not proof of the on-wire header.

Release simulator and unsigned device builds succeed. Version 0.7.0 is installed in both user simulators with checked owned journals/preferences preserved, no reset, and no saved private webpage launched by the agent. Physical Vision Pro, background suspension/relaunch, sustained diagnostic I/O and broad live-site compatibility remain acceptance gates. See [the current matrix](../TestResults/session-history-0.7.0/matrix.json).

---

## Historical 0.6.2 acceptance

# Version 0.6.2 build 23 — automatic stereo recognition and HLS diagnostics

The final Release simulator suites pass **126 tests on visionOS 26** (nine optional skips) and **128 on visionOS 27** (seven optional skips), with zero failures. Both contain 135 methods. The extra visionOS 27 checks use an explicitly supplied private local MP4: native streaming/controls and unlabelled automatic VR180/SBS recognition, including re-enabling Automatic after a manual override. The file is not packaged and no remote Pornhub request was made. Host Swift tests pass **59 methods**; HTTPS/media fixture tests pass **18**. See [the current matrix](../TestResults/auto-detection-0.6.2/matrix.json).

The detector now analyses unlabelled decoded frames, averages a bounded luma sample and allows small horizontal disparities globally and across textured regions. It still requires three agreeing frames, adequate texture and separation from the competing layout. Explicit metadata and manual settings win. Partial metadata no longer discards a separately labelled component, and a known stereo layout no longer prevents analysis of the missing projection. Unlabelled MP4 and HLS original fixtures, an ordinary flat clip, explicit mono, ambiguous/low-texture patterns, depth-varying disparity and sampling bounds are covered. Five sampled moments of the existing private video downscaled to 1440 × 720 identify SBS. Image-derived projection remains a heuristic and can mistake a flat stereo image for a panorama; large/ambiguous disparity, fisheye and unsupported mappings remain limitations.

Apple’s public HLS sample passes native saving, pause/resume, journal reload, offline renderer frames, deletion and active-task cancellation on both runtimes. The low-bitrate qualifier bounds this test and does not verify maximum offline HLS quality. Public NASA extraction/download/reopen and original 4K Highest streaming checks also pass. The user-reported Pornhub HLS download failure remains unresolved: new preparation/delegate failures now retain sanitized error chains in the local journal and Playback details. Existing failed jobs cannot recover codes never recorded. Code tests verify redaction and retention across relaunch; links, headers and account data remain excluded.

The Release device archive compiles and matching executable/dSYM UUIDs are checked. Version 0.6.2 is installed in both user simulators; no app-data reset or saved-website launch was performed. Simulator installation migrates data containers to new UUIDs; the final-install record checks available owned journal hashes rather than equating UUID identity with data retention. Playback details remains under Video tools, as requested. Physical Vision Pro, current live-site maximum quality and the reported live HLS download still require acceptance.

Failed trial logs are retained under the matrix directory. The new disparity regression failed before the fix. Anti-aliasing made the old pixel-scale-noise fixture ambiguous, so it was replaced with coarse seeded texture that survives sampling. A partial-hint assertion initially waited only for an already-known layout, then checked projection too early; it now waits for both. Final full suites pass after these corrections.

---

## Historical 0.6.1 investigation

# Version 0.6.1 build 22 — public-preview compatibility investigation

Release simulator and unsigned device builds pass. The final ordinary suites pass **120 tests on each runtime**, with optional live/private probes skipped (seven skips on the visionOS 26 full run; eight on the later visionOS 27 full run after adding the optional header diagnostic). Host Swift Package tests pass **55 methods**. Public NASA MP4 and Apple HLS offline product acceptance are enabled in both full suites and pass. Source inspection, browser identity equality, highest published 4K HLS, repeated image-based format detection, transport, downloads and saved-file rendering are covered.

Live-site checks remain separate and contain failures. VR Bangers candidates stream/save/reopen at 600 × 300 and, in a later visionOS 26 finder check, 1920 × 960; a VR-trailer association or automatic stereo result is not established. VirtualRealPorn public downloads include a decoded 3840 × 1920 file whose local playback automatically selects VR180/SBS; the same public download routes do not reliably stream natively. A two-byte Range request received full-length HTTP 200 headers without Content-Range on all four routes. SexLikeReal public media fails secure connection setup. See [live results](LIVE_SITE_TESTS.md) and [matrix](../TestResults/live-site-selection/matrix.json).

Earlier negative probes omitted the actual WebKit identifier and were corrected to match the production Watch action. A separate comparison bypassing native quality inspection reproduced the live endpoint rejection. No cookies or credentials were imported. Historical attempts are retained, including the fresh WebKit startup timeout, an interrupted test startup, a transient quality-resume timeout that passed focused retesting, and an initially ambiguous image fixture corrected without relaxing the production detector.

The 0.6.1 changes add bounded missing-dimension inspection, credential-stripped public redirect handling, precise error reporting and a saved VR context cue without a webpage URL. Controlled tests require actual image evidence before a cue changes geometry. Unknown formats remain Screen/Mono.

Physical Vision Pro stereo, gaze/pinch input, extended high-resolution thermals, background lifecycle and broad site compatibility remain release gates. No current Pornhub/BaDoinkVR retrieval was performed. The final native test-session metadata and redacted component files are linked from the matrix; failed live attempts are not counted as successful regression acceptance.

---

## Historical 0.6.0 acceptance

# Version 0.6.0 build 21 — offline expansion and browser recovery

The Release simulator build, unsigned physical-device archive and static analysis pass. After the user enabled visual review, playback controls on both runtimes and the browser, saved MP4 library, bookmarks and reopening settings on visionOS 26 were inspected through Device Hub. No clipping or overlapping controls was visible. Pointer activation remains unreliable; mounted-sheet review uses the app’s simulator-only test mode. Current evidence is assembled in [the release matrix](../TestResults/completion-test-matrix.json); installation is recorded [separately](../TestResults/completion-installation.json).

| Check | visionOS 26.0 | visionOS 27.0 |
| --- | --- | --- |
| Full native suite | 112 pass, 2 optional skips, 0 failures | 112 pass, 2 optional skips, 0 failures |
| Product HLS download acceptance | Apple public sample: pause/resume, catalogue reload, local renderer frames, deletion | Same |
| Additional final HLS cancellation acceptance | Active task cancelled; partial package removed | Same |
| MP4 import and recovery | Original unchanged; large-copy cancellation; corrupt index repaired; local frames | Same |
| Bookmarks/restoration | Save/update/reload/remove; exact page identifiers; immediate retention reduction; damaged data preserved | Same |

The optional skips are the private local-file sample and the separate low-level HLS platform probe. Product HLS acceptance is explicitly enabled using the fixed Apple public sample. The latter test uses a low-bitrate qualifier to bound test traffic; it does **not** certify highest offline HLS download quality. Streaming Highest selection is tested independently with the published 4K CC0 fixture.

The HLS investigation retained its failures: unsigned simulator builds could not connect to the background service; ad-hoc signing fixed that connection. Local HTTPS background downloads still failed with CoreMedia -12884, so no Mac trust changes or certificate bypass were used. Product tests identified the system `/.nofollow` alias for the app-owned Library as a cause of cancellation. Review also removed a potential reconnect/new-task race by finishing reconciliation before task creation. Final public-sample download, local rendering, pause/resume and cancellation pass on both runtimes. Physical suspension/relaunch, eviction and cookie-authenticated background HLS remain unverified.

Host checks pass: 53 Swift Package methods; the same 53 standalone methods with 1,052 assertions; 12 detector, 18 fixture, 16 resolver and 4 automation methods. Six real-scene cases passed on each runtime, with 60 named checks each. The ten-minute stress case alternated Highest/Adaptive quality, loop seeks and format changes; both runs returned to 3840 × 1920. Runtime 26 received 16,844 frames over 601 seconds; runtime 27 received 17,350 over 601 seconds. Peak simulator resident memory was about 1.32 GiB / 0.96 GiB, with final values about 0.97 GiB / 0.50 GiB. These are process resident measurements, not physical GPU/thermal acceptance. See the matrix for exact values. A later simulator-only held-sheet review hook was guard-tested and its ordinary forms/download behavior rechecked; production streaming and download logic was unchanged.

No fresh Pornhub or other restricted-site retrieval was performed. The earlier user-confirmed moving Pornhub VR180/SBS HLS result remains historical evidence. Physical headset, gaze/pinch, colour/HDR, stereo comfort and thermal/battery acceptance remain outstanding.

---

## Historical results: 0.5.0

# Version 0.5.0 build 20 — browser flow, downloads and reliability

The final Release simulator app and unsigned physical-device archive build successfully. Xcode static analysis passes. The app is installed in both user simulators without clearing browser data or launching a saved webpage. Current evidence: [release matrix](../TestResults/productization-test-matrix.json), [installation](../TestResults/productization-installation.json), [production review](PRODUCTION_READINESS.md).

| Check | visionOS 26.0 | visionOS 27.0 |
| --- | --- | --- |
| Full native suite | 96 pass, 1 optional private-file skip, 0 failures | 96 pass, 1 optional private-file skip, 0 failures |
| Final real-scene cases | 4 pass, 42 named checks | 4 pass, 42 named checks |
| Public NASA complete MP4 download → local-file VR360 render | 2160 × 1080, automatic VR360/mono | 2160 × 1080, automatic VR360/mono |
| Highest published HLS + automatic VR format | 3840 × 1920, VR180/SBS | 3840 × 1920, VR180/SBS |

Final scene cases are forms, downloads, controls and quality4k. They exercise actual mounted SwiftUI windows/immersive spaces and shared production actions. Build 19 also passed eleven broader scenarios per runtime, including MP4/HLS, cookie-authenticated library MP4/HLS, cancellation, unsupported input and reentry. Build 20 adds bounded/non-symlink catalogue-read validation and privacy declarations; its final native suite covers the added read boundary and the download workflow is rechecked in real scenes. These tests do not synthesize gaze/pinch/touch or certify keyboard routing.

Host checks: 47 Swift Package methods; the same 47 standalone methods with 1,009 assertions; 12 detector, 18 HTTPS fixture, 16 resolver and 4 automation-driver methods. No final failures. The source package retains earlier failing results and their fixes rather than replacing them with pass labels.

## Downloads now tested in the app

- Original CC0 HTTPS MP4 save, atomic catalogue reload, file-backed native immersive rendering, format hints, accurate seek, offline quality behavior and deletion.
- Actual public NASA MP4 download over HTTPS, followed by local-file playback and automatic spherical metadata interpretation at 2160 × 1080 on both runtimes. This is separate from the earlier desktop yt-dlp tests.
- Legitimately scoped browser cookie handoff; rejected HTML/missing/oversized responses; immediate and partial-transfer cancellation; free-space reserve; same-origin HTTPS redirect acceptance and cross-origin redirect rejection.
- Real Downloads sheet open, save/list, close/reopen, saved-file Play, transport/format changes, return to browser and deletion.

The downloader saves supported selected MP4 sources only. HLS offline saving, transfer pause/resume, background continuation and import/export are not implemented. It does not demonstrate live Pornhub downloads. Actual website sources can still expire or require unsupported requests.

## Reliability findings and fixes

Initial tests found mismatched equivalent folder URL representations and an unsupported staging filename extension during media validation; both were fixed. A public NASA metadata request also exceeded the previous three-second resource deadline, leaving a decoded spherical video on Screen. Optional metadata inspection now permits eight seconds per attempt and one retry for transient timeout/lost/offline connections. A truncated-prefix regression and final public NASA checks pass. Size, range, redirect and HTTP access rejections are not retried.

Audio tests post real notification names and verify interruption pause, permitted resume, manual pause/stop precedence, output-disconnection pause and media-service-reset cleanup. These do not reproduce physical Bluetooth routing or headset removal. Core storage tests reject changed/missing/symlink files, corrupt/oversized/linked catalogues and avoid silently overwriting corrupt data.

## Remaining acceptance limits

No physical Vision Pro is connected; device stereo/comfort, gaze/pinch hit targets, window placement, audio routing, Crown/headset-removal behavior, sustained high-resolution memory/thermal performance and signed installation remain release gates. The Mac locked during this run, so new browser/Downloads appearance and current physical input could not be visually verified. Prior 0.4.1 controls screenshots are historical evidence only. See [visual status](../TestResults/productization-visual-review.json).

No new adult-site retrieval/login occurred. Current Pornhub maximum quality, automatic detection across real sources and broader site support remain unverified. The historical one-stream user-confirmed Pornhub HLS success is retained separately. Controlled 4K fixtures and the public NASA source are not evidence of universal site support.

Dedicated test simulators, temporary fixture servers and their simulator-only test trust stores were removed. The Mac trust stores and user browser data were unchanged. Packaging checks verify current source/resource hashes, matching archive executable/debug-symbol UUIDs, exclusion of simulator test hooks from the device binary, ZIP integrity and byte-for-byte contents. `Scripts/validate_release.py` repeats source/archive/package consistency checks after packaging.

---

# Historical results

Everything below describes earlier releases and their then-current limits. For the current build use the section above and the production review.

# Version 0.4.1 — visual controls and automatic spherical metadata

The follow-up exposed and fixed a real regression: the public NASA MP4 decoded at 2,160×1,080 but stayed in Screen mode. Its legacy spherical track metadata is now recognized through a bounded MP4-prefix inspection; the public finder test checks automatic VR360 + Single image. Original opaque-named MP4 fixtures independently verify VR180/SBS and VR360/top-bottom, late-metadata manual overrides, and returning to Auto. Finder handoff tests additionally retain format cues only for the exact current page, preserving query identifiers and declining ambiguous element metadata. Metadata tests reject malformed/oversized boxes, unknown namespaces, XML entities, duplicate declarations and out-of-range crop values.

Final evidence is in `TestResults/controls-test-matrix.json`. The native Release target has 81 methods: with the public NASA check enabled, 80 pass and the optional private-media method skips on each runtime. Swift Package and standalone checks cover 43 core methods / 991 assertions; detector 12, fixture 18, resolver 16 and host evidence protocol four. Controlled native and scene tests verify the highest published calibration rendition at **3,840×1,920**, automatic VR180/SBS, and the earlier 480×240 → 1,440×720 control. A single public NASA MP4 provides 2,160×1,080; that result does not establish all qualities on NASA's website.

Seven real-scene cases per runtime cover forms, the actual format/quality popovers, both quality masters, the public NASA finder, authenticated library MP4 and authenticated library HLS. The controls case opens/closes the popovers, changes projection/packing, returns to Auto, switches Highest/Adaptive while preserving a paused position, exercises transport and exits to the original page. They use real app scenes and shared SwiftUI actions, not synthetic pointer events.

CUA screenshots inspected the main panel on the dedicated visionOS 26 simulator and both real popovers on visionOS 27. Labels, all projection/packing choices, help, descriptions and the active quality indicator fit without observed clipping. `TestResults/controls-visual-review.json` records this appearance review. Pointer activation produced tool errors or failed to reach the simulator; captured Space also failed to start playback. Therefore pointer/keyboard delivery and physical-headset hit targets remain unverified. The automated shared actions passed; no human clicks were needed for those checks.

Retained development failures include the original NASA automatic-projection failure, an immediate assertion made before asynchronous metadata completed, and one public webpage's navigation exceeding the old 15-second deadline before successfully presenting 2,160×1,080 frames. The optional remote-page navigation check now has the same bounded 45-second allowance used by the scene suite. Failed runs are retained and are not counted as passes.

No new adult-site retrieval or login occurred. Live Pornhub maximum quality/automatic format, physical stereo depth, headset placement, sustained high-resolution decoding and thermal behavior remain unverified. Highest retains adaptive playback when the original master is needed for audio/subtitle/session context or the supported independent rendition cannot be identified. Offline downloading remains unimplemented; prior desktop download evidence is separate.

## Previous release reports

# Version 0.4.0 — quality, automatic format and playback controls

Final Release validation on visionOS 26.0 and 27.0: **72 native methods pass and two optional methods skip on each runtime**, zero failures. The optional user-supplied media and external public extractor checks were not enabled. All 39 core methods also pass through Swift Package; the standalone runner executes 960 assertions. The JavaScript detector has 12 passing tests, HTTPS fixtures 15, embedded resolver 16, and host automation protocol four.

The controlled low HLS rendition decodes at **480×240**; Highest selects the second, published rendition and decodes **1,440×720** through AVPlayer → Metal → RealityKit. A separate host check verifies AAC in both rendition segments. Quality switching preserves a paused two-second position, presents the new frames and resumes. Tests also cover a browser-cookie-gated master issuing a normal scoped child cookie, cancellation/replacement during master inspection, metadata/label-based format detection, repeated image matching with a VR cue, ordinary-video defaults and manual overrides.

Four real-scene scenarios pass on each runtime: forms, quality, authenticated library MP4, and authenticated library HLS — **34 named checks per runtime**. The quality scene starts the webpage at 480×240, invokes the normal Watch in VR action, verifies 1,440×720 native frames with automatic VR180 + side-by-side, exercises pause/seek/skips/all nine projection-layout combinations/recenter/resume, and exits to the browser. These are real app scenes and shared production actions, not synthetic pointer clicks or native visionOS XCUITest. Evidence: `TestResults/quality-test-matrix.json`, `quality-acceptance-native-*` and `quality-acceptance-scenes-*`.

The compact controls are implemented and mounted by the scene tests. A fresh visual/pointer review was **blocked by the locked Mac**; no screenshot or visual-acceptance claim is made for 0.4.0. The unsigned physical-device archive builds and matches its debug-symbol UUID. Simulator-only observation/test code is absent from its executable. Version 0.4.0 build 15 is installed into both user simulators without clearing their browser stores or launching a saved website.

Earlier development results remain retained: the first focused run failed an invalid assumption that an HLS AVURLAsset exposes an audio track inventory; audio presence is now checked from the fixture's actual segments. One later visionOS 26 run failed an old fixed 250 ms paused-render assertion under concurrent load. It now waits, with a five-second bound, for the correct visible mesh/texture update; both final full suites pass. These failed runs are not counted as successes.

Highest is limited to supported independently playable published renditions. External audio/subtitle/session context, unknown codec signaling or an inspection failure retains the adaptive master. Single-rendition/low-quality MP4 links cannot reveal unexposed higher URLs. Eye textures retain at most 4,096 pixels per dimension; sustained 8K performance, physical stereo depth, thermal behavior and headset interaction remain untested. No fresh Pornhub retrieval was performed; the earlier user-confirmed moving HLS session remains the site-specific evidence, and its high-resolution/automatic-format behavior is still unverified.

Desktop downloads of original CC0/NASA clips were tested earlier. **In-app offline downloading is not implemented or tested**: the embedded finder remains metadata-only and playback streams media. See `Docs/YT_DLP_TESTING.md`.

## Previous release reports

# Latest release validation — 0.3.7

Release builds succeed for the simulator and unsigned Vision Pro archive. On each of visionOS 26/27, 62 native tests pass with zero failures and two optional skips. This includes packed-eye Metal channel checks, paused layout/projection changes and streaming renderer uploads. Thirty-five Swift core tests pass. The forms, cookie-library MP4 and cookie-library HLS real-scene cases pass on both runtimes (six cases / 48 named checks). The UI uses the existing layout bindings; no tests duplicating the segmented-picker implementation were added.

A CUA screenshot of original CC0 playback on visionOS 26 confirms that Single image, Side by side and Top / bottom are all visible alongside the projection, transport and return controls without observed clipping. It does not certify pointer hit-testing. A Command–Option–2 experiment was intercepted by Device Hub's Reports shortcut, so host shortcut delivery remains separate from the in-process scene tests.

The user's 0.3.6 report and explicit confirmation establish moving Pornhub HLS video for one simulator stream after selecting VR180 + Side by side. Native resolution in that report was 480×240. No agent retrieval, login or broad site/headset verification is claimed. See `TestResults/layout-controls-test-matrix.json` and `TestResults/live-user-hls-vr-success-0.3.6.json`.

## Earlier validation history

# Test report — 25 October 2026

## Version 0.3.3 playback and diagnostic reliability

- **59 native Release tests pass on visionOS 26.0 and 27.0**, 118 executions in the final full matrix, zero failures/skips. See `TestResults/diagnostics-test-matrix.json` and `diagnostics-visionos-*-release-*` logs/summaries. Older failed/stopped development runs are retained separately and are not counted as passing.
- Attached WKWebView tests confirm **presented video frames**, not just an advancing clock: original CC0 MP4 and HLS each produce 1024×512 callbacks; the public NASA MP4 produces 2160×1080. They verify WebKit pause-all-media fallback followed by ordinary playback resumption, and a fresh missing-source document produces MediaError code 4. This controlled result does not diagnose a production site's error.
- The existing user-supplied MP4 streams through loopback HTTPS, AVPlayer and Metal/material/model updates at **2880×1440**. Its original approximate 5 s seek landed near **4.27 s**. Accurate seeking now reaches **5.0 s**; pause/resume, end/replay and rapid committed skips pass. This is a private development sample, excluded from packages. It verifies initial decoding and controls, not sustained decoding of every frame, correct source geometry, physical stereoscopy or the original website transport.
- Delayed-navigation tests check immediate candidate/status clearing and reject old-page scans before the new document commits. Renderer tests retain failure diagnostics despite late-frame delivery and release the failed display model/material references. Existing full projection/layout, texture orientation, scoped-cookie, cancellation, preparation, seeking and recovery checks remain passing.
- **34 core methods / 923 assertions**, **34 Swift Package tests**, **16 Python resolver tests**, **11 HTTPS fixture tests** and **10 JavaScript detector tests** pass. Contract tests cover known-height quality ordering without invented widths, duplicate parent MIME preservation, boolean-dimension normalization, MIME whitespace, private webpage errors and bounded safe player logs.
- Fresh simulator Release build, unsigned physical-device Release archive and Xcode static analysis pass. The archive executable/dSYM UUIDs match; runtime/resources match source and the test/clean products. See `diagnostics-release-binary.json`, the build/analysis logs and `release-build-manifest.json`.
- Version **0.3.3 build 10 is installed** in “VisionStream visionOS 26”. The installed executable matches the clean build; detector/resolver match source. It was left closed for the user to reopen, without automatically opening a saved private website. The simulator changed the data-container location during update, but retained existing WebKit/Cookies files and preferences dating back to 23 October; no cookie values were inspected. Live login restoration and visible updated controls are not manually verified. See `diagnostics-ui-acceptance.json`.
- The temporary minimum-version simulators and their test trust stores are removed; the separate test simulator is shut down after use. The user's simulator remains available. No physical Vision Pro is connected.

### Reproduction and optional sample

`Scripts/run_visionos_tests.py --public-extraction` enables the public NASA checks. The 59/59 matrix additionally uses `--local-media /absolute/path/to/LocalMedia/sample.mp4` for the existing user-supplied sample; source packages omit it. Without that opt-in file, the private-sample test is explicitly skipped (58 public/controlled methods remain). Without either optional flag, the public extraction test also skips. Use dedicated simulators: the runner temporarily trusts a test-only local certificate there, never in the Mac trust store.

A focused regression can be selected with `--only-testing VisionStreamTests/NativePlaybackTests/testWebpageMediaPlaybackAndFailureDiagnostics`. Results use UTC timestamps with microseconds so the daylight-saving clock change cannot collide with an earlier result name.

### Live status and remaining acceptance

The user's 0.3.2 automatic HLS attempt failed at waiting-for-player with no captured codes or decoded frames. They then reported regular webpage video failure and supplied a separate native not-attempted report. Those causes remain unknown. Version 0.3.3 captures additional evidence; its generic fixes and controlled successes do not establish live Pornhub support. A fresh report after the website's own Play button is needed. Physical tracking, eye isolation, comfort, controls, interruptions and performance remain unverified. See [the review](RELIABILITY_REVIEW.md) and [live record](LIVE_SITE_TESTS.md).

## Packaged-source verification

The release source ZIP was extracted to a fresh temporary directory with spaces in its path. A clean Release build-for-testing succeeded using only that package and Xcode, followed by a passing embedded-extractor/public-NASA native rendering smoke test (1 passed, zero failures/skips). No private sample was included. The temporary source/build/result bundle was removed; its build log, runtime log and summary are retained as `TestResults/packaged-source-*`. Final app/build/test source hashes are unchanged, and the package is regenerated only to add this evidence. The packaged device archive has matching executable/debug-symbol UUIDs.

## Version 0.3.2 parent playlists and missing-resource guidance

- **55 native Release tests pass on visionOS 26.0 and 27.0**, 110 successful executions, zero failures/skips. Evidence: `TestResults/adaptive-test-matrix.json` and `adaptive-visionos-*-release-*` logs/summaries.
- The expanded native test opens a controlled multivariant parent playlist, follows its video playlist and segments, and produces 1024×512 frames through the immersive renderer without custom headers. Existing direct MP4, individual HLS and public NASA extraction tests also pass.
- **33 core methods / 894 assertions**, 33 Swift Package tests, **13 Python resolver tests** and **9 HTTPS fixture tests** pass. Tests use yt-dlp's real offline HLS parser, verify supplied parent URL retention without token rewriting, deduplication and restriction merging, MP4 visibility under the result cap, private labels and structured missing-resource guidance. No public mapping for CoreMedia -12938 or inferred HTTP 404 is introduced.
- A fresh minimum-version simulator kept the user's page untouched during testing. It and its test-only CA were deleted after the successful run.
- The user's separate 0.3.1 HLS and 240p MP4 attempts both failed before decoded frames with URL error -1100 and CoreMedia -12938. These remain failures, not fallback successes. Their exact HTTP status and cause remain unknown; `TestResults/live-user-missing-resource-reports-0.3.1.json` contains the redacted evidence. Controlled parent-playlist success is not a live-site fix.
- Simulator Release and unsigned Vision Pro Release archive builds pass. Required embedded resources are present and the executable/dSYM UUIDs match. Version 0.3.2 build 9 is installed and launched in the user's visionOS 26 simulator; its resolver resource matches source. A live user retry of the new parent option and physical-headset execution remain pending. Evidence: `adaptive-device-release.txt`, `adaptive-release-binary.txt`, `adaptive-ui-acceptance.json` and the current release manifest.

## Version 0.3.1 request-context advisories

- **53 native Release tests pass on visionOS 26.0 and 27.0**, 106 successful executions, zero failures/skips. Evidence: `TestResults/header-context-test-matrix.json` and `header-context-visionos-*-release-*` logs/summaries.
- The new native regression decodes original CC0 MP4 and HLS streams with a request-context advisory. The HTTPS server rejects Origin, Referer, Authorization or Cookie headers on the media, manifest and segment routes. Both formats reach 1024×512 decoded renderer frames without those headers on both simulators.
- **31 Swift core methods / 880 assertions**, 31 Swift Package methods, **9 Python resolver tests** and **8 HTTPS fixture tests** pass. They verify that Origin/Referer metadata is advisory, authentication/protection restrictions remain blocking, private header values are omitted and the controlled server rejects injected context.
- The minimum-version run used a new isolated simulator so the user's video page was not interrupted. That simulator and its test-only CA were deleted after the successful run.
- Simulator Release and unsigned physical-device Release archive builds pass. The archive's debug-symbol UUID matches its executable, and required runtime/resources are present. Version 0.3.1 build 8 is installed and launched in the user's visionOS 26 simulator; the installed resolver resource matches source. The finder retry and real-site native playback remain pending. Evidence: `header-context-device-release.txt`, `header-context-release-binary.txt` and `header-context-ui-acceptance.json`.
- The user's screenshot establishes HLS candidate discovery and the old disabled-button message. It does not identify the exact header class or establish successful live native playback. See `TestResults/header-context-user-report-0.3.0.json` and [the finder correction](ON_DEVICE_EXTRACTION.md).

## Version 0.3.0 on-device extraction

- **51 native Release tests pass on visionOS 26.0 and 27.0**, 102 successful executions, zero failures/skips. See `TestResults/yt-dlp-ondevice-test-matrix.json` and `yt-dlp-visionos-*-release-*` evidence.
- Both runtimes execute bundled Python/yt-dlp, resolve a public NASA HTTPS MP4 and decode 2160×1080 frames through the native immersive renderer. This tests a direct MP4 URL, not production webpage extraction or live adult-site compatibility. No new YouTube checks were performed.
- **30 Swift core tests / 873 assertions**, 30 Swift Package methods and **8 Python resolver unit tests** pass. The unsigned physical-device Release archive builds. No physical headset is connected.
- Initial runtime integration had an ARC ownership crash, then a desktop FFmpeg probe failure. Both were fixed before the final passing matrix. Failed `.xcresult` bundles remain available locally.
- The expanded run also exposed a paused-layout geometry/upload race. Geometry rebuilding now shares the upload's layout snapshot; the existing native test repeats mono/SBS/top-bottom changes while paused. Failure evidence is retained as `yt-dlp-screen-race-*`.
- Full implementation details, reproduction commands and outstanding authentication/header/helper limits are in [on-device extraction](ON_DEVICE_EXTRACTION.md). The older results below are historical and do not imply a 0.3.0 live-site or visible-control acceptance pass.

## Version 0.2.4 complete-frame and native-window changes

- **42 native tests pass in Release on visionOS 26 and 27**: 84 successful executions, zero failures/skips. Evidence: `TestResults/screen-test-matrix.json` and `screen-visionos-*-release-*` logs/summaries.
- **25 core tests / 847 assertions pass**, and 25 standard Swift Package XCTest methods pass. The new geometry test checks complete upright UV coverage, aspect preservation, fitted bounds, winding and invalid-aspect handling. Evidence: `TestResults/screen-core-checks.txt`, `TestResults/screen-swift-package-tests.txt`.
- The new actual decoder/GPU test verifies a complete flat frame at the decoded aspect, true decoded dimensions, paused eye-layout resizing, and paused Screen/VR180 transitions. All twelve pre-existing panoramic MP4/HLS renderer variants still pass with panorama mode selected explicitly.
- **7 HTTPS fixture tests pass**, including the new original 32-second manual-control clip, range serving and its single-video page. Evidence: `TestResults/screen-fixture-tests.txt`. Regenerate it with `Scripts/generate_fixtures.py`.
- Release test/simulator builds and the unsigned physical-device archive pass; executable/dSYM UUIDs match. Evidence: `TestResults/screen-release-build.txt`, `TestResults/screen-clean-simulator-build.txt`, `TestResults/screen-device-release.txt`, `TestResults/screen-release-binary.txt`, and the release manifest. A first native test run had one incorrect expected fixture size (512×256 rather than the actual 1024×512); that test assertion was corrected. The failed result is retained in `screen-initial-27-*`; both final runs above pass.
- The clean build is installed on VisionStream visionOS 26 and launched on the local CC0 `/controls.html` page; `TestResults/screen-app-launch.txt`. The Screen + Mono page and new controls are compiled; actual separate-window appearance, button interaction and scene return await user-assisted acceptance. Automated model/render tests do not substitute for that UI check.
- Live-site observations remain from 0.2.2: BaDoinkVR reached moving immersive video but the user reported viewing/control problems; Pornhub native and webpage playback failed; VR Bangers works only on the webpage; VirtualRealPorn remains untested. No live-site success is claimed for the new 0.2.4 UI yet.

## Earlier 0.2.3 server-response diagnostics

- **40 native tests pass in Release on visionOS 26 and 27**: 80 successful executions, zero failures/skips. Evidence: `TestResults/server-response-test-matrix.json` and `server-response-visionos-*-release-*` logs/summaries. The visionOS 26 run used a new isolated simulator so the user's live-site session was not interrupted; that disposable simulator and its test-only certificate were removed afterwards.
- **24 core tests / 819 assertions pass**, and the same 24 methods pass under standard Swift Package XCTest. Evidence: `TestResults/server-response-core-checks.txt`, `TestResults/server-response-swift-package-tests.txt`.
- Report privacy tests now cover the actual attempted candidate, omitted/unknown/error fields, bounded metadata, and a qualified server-response hint keyed only to the verified AVFoundation error code. The native recovery test verifies attempted-source retention after failure and cleanup on navigation.
- Release test/simulator builds and the unsigned physical-device archive pass. Executable/dSYM UUIDs match. Evidence: `TestResults/server-response-release-build.txt`, `TestResults/server-response-clean-simulator-build.txt`, `TestResults/server-response-device-release.txt`, `TestResults/server-response-release-binary.txt`, and the current release manifest.
- Live testing was user-assisted on **0.2.2**: Pornhub returned page HTTP 200 and candidates, but native asset loading failed with -11850/-12939 and the user says webpage playback also fails. BaDoinkVR produced moving immersive video after Watch in VR, followed by a user report of control/viewing problems. VR Bangers works only on the webpage in user testing. Detailed checks are recorded separately in [live-site testing](LIVE_SITE_TESTS.md). This does not verify a live HereSphere library or physical headset.
- Apple documents -11850 as [serverIncorrectlyConfigured](https://developer.apple.com/documentation/avfoundation/averror-swift.struct/serverincorrectlyconfigured), with byte-range support a possible cause. A live range/header defect was not established. The updated error message is guidance, not a claim that the site's server was fixed.

## Earlier 0.2.2 compatibility diagnostics and navigation update

- **39 native tests pass in Release on visionOS 26 and 27**: 78 successful executions, zero failures/skips. Evidence: `TestResults/compatibility-test-matrix.json` and the `compatibility-visionos-*-release-*` logs/summaries.
- **23 core tests / 808 assertions pass**, including three report privacy/classification/bounds regressions. The same 23 XCTest methods pass as a Swift package. Evidence: `TestResults/compatibility-core-checks.txt`, `TestResults/compatibility-swift-package-tests.txt`.
- The added native test verifies a real HTTPS page HTTP 403, AVFoundation rejection of a missing MP4, safe numeric failure recording, and diagnostic/error cleanup on a subsequent successful navigation. All previous decoder, GPU, browser and library tests also pass in these two Release runs.
- Simulator Release/test builds and the unsigned physical-device Release archive pass. The device executable/dSYM UUIDs match. Evidence: `TestResults/compatibility-release-build.txt`, `TestResults/compatibility-clean-simulator-build.txt`, `TestResults/compatibility-device-release.txt`, `TestResults/compatibility-release-binary.txt` and the current release manifest.
- The clean 0.2.2 Release app is installed and launched in **VisionStream visionOS 26**; `TestResults/compatibility-app-launch.txt`. Its changed controls were observed on-screen, and the user replied “works” to the requested navigation recheck. The response does not distinguish pointer entry from Command–L; each path is not separately claimed as verified. Evidence: `TestResults/ui-navigation-0.2.2.json`. The original refresh-on-click cause has not been conclusively diagnosed.
- The initial direct browser-tool attempts were refused before navigation. Later user-assisted live results are recorded above and in [the live-site record](LIVE_SITE_TESTS.md); they supersede the initial lack of player observations.

The table below is retained **0.2.1 and earlier evidence**, not a claim that the new 39-method suite has run in Debug. The unchanged detector, fixture, desktop-decoder and Metal checks were not rerun for the diagnostics/UI update.

## Earlier executed checks

| Check | Result | Evidence |
| --- | --- | --- |
| Core Swift tests | 20 tests, 787 assertions, zero failures | `TestResults/core-checks.txt` |
| Detector JavaScript tests | 9 tests passed | `TestResults/javascript-tests.txt` |
| HTTPS fixture/server tests | 6 tests passed | `TestResults/library-fixture-tests.txt` |
| macOS AVFoundation streaming | 12 successful decoded BGRA outputs: six MP4 and six HLS | `TestResults/macos-streaming-tests.txt` |
| Actual Metal kernel on macOS | 12 configurations, 1024 output-channel assertions, zero failures | `TestResults/metal-tests.txt` |
| Core and PlaybackModel typecheck | Swift 6 typechecking passed against macOS SDK; visionOS audio-session branches excluded | `TestResults/playback-typecheck.txt` |
| Shared WebKit API signatures | Cookie access, isolated scripts and frame JavaScript calls typechecked against macOS SDK | `TestResults/webkit-api-typecheck.txt` |
| Calibration media generation | Six original MP4 clips and six segmented HLS playlists generated | `Fixtures/generated/manifest.json`, `TestResults/fixture-generation.txt` |
| Calibration image inspection | Extracted VR180 SBS frame has readable LEFT EYE/RIGHT EYE, NORTH/SOUTH, FRONT and asymmetric corner markers | Local FFmpeg frame extraction visually inspected |
| Project/Info.plist structure | Parsed successfully with plutil | `TestResults/project-validation.txt` |
| Swift source syntax | App/native-test sources parsed without syntax diagnostics | `TestResults/orientation-debug-build.txt` |
| visionOS simulator build | Passed with Xcode 27.1 / visionOS 27 SDK, arm64, deployment target 26.0 | `TestResults/orientation-debug-build.txt` |
| Vision Pro device build | Passed; unsigned development product, no physical device connected | `TestResults/orientation-device-release.txt` |
| Native tests — visionOS 26 Debug | **35 passed, zero failures/skips** | `TestResults/orientation-visionos-26-debug-tests.txt`, `TestResults/orientation-visionos-26-debug-summary.json` |
| Native tests — visionOS 26 Release | **35 passed, zero failures/skips** | `TestResults/orientation-visionos-26-release-tests.txt`, `TestResults/orientation-visionos-26-release-summary.json` |
| Native tests — visionOS 27 Debug | **35 passed, zero failures/skips** after simulator restart | `TestResults/orientation-visionos-27-debug-tests.txt`, `TestResults/orientation-visionos-27-debug-summary.json` |
| Native tests — visionOS 27 Release | **35 passed, zero failures/skips** | `TestResults/orientation-visionos-27-release-tests.txt`, `TestResults/orientation-visionos-27-release-summary.json` |
| Native Metal output | 12 configurations, 1024 channel assertions; both eyes, mono/SBS/TB, swap and flip, RGBA16Float | Same native logs |
| Optimised Vision Pro archive | Passed; required resources present, executable/dSYM UUIDs match, minimum OS 26.0 | `TestResults/orientation-device-release.txt`, `TestResults/release-0.2.1-build-manifest.json` |
| Xcode static analysis | Passed | `TestResults/orientation-static-analysis.txt` |
| Standard Swift Package tests | 20 XCTest methods passed with full Xcode | `TestResults/orientation-swift-package-tests.txt` |
| Native HTTPS decode | All six MP4 and all six HLS fixture variants produced decoded frames | Same native log |
| Native cookie handoff | WKWebView Secure HttpOnly cookie authorised MP4 and HLS including gated segments | Same native log |
| Native renderer integration | All 12 MP4/HLS variants completed GPU frames; projection/layout changes while paused succeeded | Same native logs, `Renderer fixture` lines |
| Playback model integration | Pause/resume, initial-position handoff, seeking/clamping, stop, cancellation/replacement and 404/401 recovery passed | Same native logs |
| Cross-origin browser integration | 127.0.0.1 page, localhost iframe/open shadow root detected; navigation removed stale candidates | Same native logs |
| App installation / launch | Final app installed and launched in the dedicated Vision Pro simulator | `TestResults/orientation-app-launch.txt` |
| On-screen immersive transition / controls | User-assisted simulator test: library connection, grid display, vertical flip and Return to page passed; version 0.2.1 starts the first VR180 mono MP4 upright without flipping | `TestResults/ui-validation.json`, `TestResults/ui-before-orientation-fix.png`, interactive validation below |
| BaDoinkVR live library/playback | Unverified: direct public HTTPS requests reset before an HTTP response | `TestResults/badoink-public-probe.json`, `Docs/VR_LIBRARIES.md` |
| Pornhub live playback | Not performed; public page access failed | `Docs/PORNHUB.md` |

These tests establish native decoding, GPU texture upload and material loading in the simulator. They do not establish final stereoscopic presentation, scene/window transitions or physical Vision Pro behaviour. The generated fixtures are deliberately original, openly licensed calibration grids, not prerecorded adult content or third-party footage.

## VisionStream 0.2 library validation

The final 35-method matrix adds six core parser tests, four native connector tests and a material-orientation regression to the earlier 24-method baseline. The intermediate 34-method library matrix remains in `TestResults/library-test-matrix.json`. All four final runs passed after fixing the unknown-length response stress case and correcting a WebKit test setup that returned a JavaScript function across the native bridge. The earlier baseline evidence remains in `TestResults/visionos-test-matrix.json`; it does not validate the new library code.

- The library-to-player test establishes a normal Secure HttpOnly browser cookie, loads a gated index and six detail documents, and decodes all twelve MP4/HLS variants with their explicit projection/layout. Back navigation restores the index.
- Failure/recovery tests cover invalid addresses/documents, HTTP 403/405, refused access, webpage responses, redirect refusal and both declared/unknown-length responses above 2 MB. Optional POST sends only an empty JSON object.
- Cookie tests verify path/host isolation, ignored response cookies, and normal gated MP4/HLS playback. Library cancellation/replacement and browser navigation reject stale results and clear sensitive in-memory history.
- The existing WebKit test additionally verifies that a library candidate pauses a detected page video with the same source, in the detector's isolated world.

The final simulator runs cover networking/model/rendering code, not interaction with the new sheet or final immersive presentation. The Mac was initially locked; it was later unlocked for the user-assisted checks below. Device discovery listed only simulated devices. At that earlier stage no real site's account or video had been accessed; the later user-assisted records above supersede that stage.

## What each executed test covers

Core tests exercise address validation; MP4/HLS candidate classification; blob/insecure/DRM rejection; redaction of signed query strings in candidate labels; the JavaScript-to-Swift JSON contract; independent stereo packing; hemisphere coordinates; sphere closure; constant radius; inward triangle winding; and cookie domain/path/expiry boundaries. The standalone runner compiles and executes the same test methods used by the Xcode core test target. It was used before full Xcode was installed; the same core methods have now also passed under native visionOS XCTest.

The JavaScript tests execute the actual bundled script against small DOM mocks. They cover MP4/currentSrc, HLS MIME, authoritative blob sources, encrypted events and MediaKeys, open shadow roots, dynamic insert/change/remove, selected-video pause with source identity checking, bounded reports, nonfinite time sanitisation and duplicate installation. The separate native test now also exercises the actual WKWebView and isolated content world; these nine mock tests remain useful for focused detector cases.

HTTPS fixture tests start a temporary local TLS server, trust its temporary certificate only within that Python client, and shut it down afterwards. They verify all six files' codecs/dimensions/duration, MP4 fast start and byte ranges, six HLS playlists and 24 segment requests, the normal cookie-gated test route, invalid ranges, and path traversal rejection. No system certificate or trust setting is changed. The fixture server's cookie check is test infrastructure, not a production authentication scheme.

The macOS streaming probe uses AVURLAsset, AVPlayer, and AVPlayerItemVideoOutput with the same BGRA/Metal-compatible pixel-buffer request as the app. It successfully received decoded video frames for all twelve fixture stream variants over a temporary loopback HTTP connection. That local HTTP endpoint exists only in the desktop test harness; the application continues to require HTTPS native media URLs. These results establish a desktop decoder/output sanity check, not visionOS decoding, HTTPS authentication, Metal execution, RealityKit rendering, audio quality, or perceived stereo depth.

The separate Metal probe compiles and executes the application's actual `StereoVideo.metal` kernel on this Mac's GPU. It checks every output channel of both eyes against the core coordinate model for mono/SBS/top-bottom, both eye orders and both vertical orientations, using the same RGBA16Float output format as the renderer. All twelve configurations pass. The first run exposed an inherited-main-actor completion callback; explicit Sendable callbacks corrected it in the renderer and tests, and the rerun passed. This test validates GPU packing, not RealityKit's camera-index material or final per-eye display.

## Run locally

```sh
sh Scripts/test_core.sh
node --test Tests/JavaScript/video_detector.test.cjs
python3 Scripts/generate_fixtures.py
python3 -m unittest discover -s Tests/Fixtures -v
python3 Scripts/test_macos_streaming.py
sh Scripts/test_metal.sh
```

The project can be opened directly; `python3 Scripts/generate_project.py` regenerates it after source file list changes. The initial Command Line Tools-only `swift test` attempt could not import XCTest. Full Xcode has since been installed and the core methods pass in the visionOS test target. See the native commands below.

## Executed native visionOS test target

The shared VisionStream scheme ran **35 tests with zero failures and zero skips in all four configurations**: Debug and Release on visionOS 26.0 (23M336), and Debug and Release on visionOS 27.0 (24M362). Both use an Apple Vision Pro 4K simulator and the same SDK 27-built source and HTTPS fixtures. The final matrix contains **140 successful test executions**; this is 35 unique test methods repeated across four environments. Both runtimes were also exercised after a fresh boot. Xcode is 27.1 (27A9275), Swift 6.4 in Swift 6 language mode, deployment target 26.0. `TestResults/orientation-test-matrix.json` records every result bundle, destination, configuration and per-run log. The full `.xcresult` bundles remain in the workspace; portable summaries and detailed logs are in the source archive.

- All 20 core XCTest methods.
- `testStartupDoesNotReplaceAnExplicitNavigation`: deferred startup preserves an explicit page request, does not reload on repeated appearance, loads the bundled Home page and restores a saved address.
- `testWebKitDetectsFramesShadowRootsAndDynamicSources`: isolated-world detection in a main document, srcdoc frame and open shadow root; changing a source replaces the old candidate.
- `testCrossOriginDetectionAndNavigationClearsCandidates`: actual separate 127.0.0.1/localhost origins, a nested open shadow root, and removal of old candidates after navigation.
- `testBundledStereoMaterialLoads`: loads the bundled USD material and binds both low-level textures.
- `testMetalSplitsPackedEyes`: executes all 12 mono/SBS/TB × eye swap × vertical flip configurations, reading both RGBA16Float output textures and checking 1024 channels against the independent core coordinate model.
- `testAuthorisedFixtureMP4AndHLSDecode`: the actual PlaybackModel receives BGRA output for all six MP4 and six HLS calibration variants.
- `testBrowserCookiesAuthorizeNativeMP4AndHLS`: WebKit establishes a normal Secure HttpOnly cookie; native MP4 and gated HLS playback decode using scoped public cookie APIs.
- `testStreamingRendererUploadsFrames`: all twelve format/projection/layout variants stream through AVPlayerItemVideoOutput, CVMetalTextureCache, Metal, LowLevelTexture replacement and material binding. Changing projection and layout while paused rebuilds the geometry and finishes texture upload. It uses the simulator's nominal pose fallback and does not observe either physical eye or the final scene.
- `testPlaybackPauseSeekResumeAndStop`: actual MP4/HLS clocks, initial-position handoff, pause, seek, invalid-value rejection, clamped skip, resume and media release.
- `testCancellationAndReplacementDoNotLeaveStalePlayback`: a controlled slow HTTPS source is cancelled and replaced; stale work cannot retain a preparing state or overwrite the current item.
- `testNetworkAndAuthenticationFailuresRecover`: missing and unauthorised MP4/HLS sources fail with a usable error and clean player state, followed by successful playback preparation.

The HTTPS runner trusts a one-day local test certificate only in this dedicated simulator. The Mac's trust stores are unchanged. The production app still requires HTTPS and has no certificate-validation exception. These small eight-second fixtures may be fully buffered by AVFoundation; no application video-download task or output file exists.

Initial fresh-runtime attempts stalled while XCTest was reporting failed expectations and were interrupted. The exact cold-start cause was not established. Separate checks and subsequent full runs passed, including the current 35-test matrix on both OS versions and fresh-boot runs. Physical scene lifecycle checks remain on the acceptance list. Moving blocking audio-session work off the main actor removed the observed AVAudioSession responsiveness warning. The expanded cancellation test then exposed an unfinished preparing state; a cancellation handler plus guaranteed cleanup corrected it, and the regression now passes. Minimum-version testing then exposed an initial-navigation race: on visionOS 26, an eager bundled start-page load could supersede a newer requested page. Deferring initial navigation until the browser appears and preserving explicit requests fixed it; all three browser tests and the new startup/session regression pass on both runtimes.

For a repeatable native run, generate fixtures if needed, build the test bundle, boot a dedicated compatible simulator, then run:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project VisionStream.xcodeproj -scheme VisionStream \
  -sdk xrsimulator -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath DerivedData DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  CODE_SIGNING_ALLOWED=NO build-for-testing
python3 Scripts/run_visionos_tests.py --simulator YOUR_SIMULATOR_ID --keep-serving
```

See [installation](INSTALLATION.md) for simulator creation and test-certificate scope. The fixture-dependent tests skip without `VISIONSTREAM_TEST_ORIGIN`; the runner configures it automatically. Native visionOS UI automation is [not supported by XCTest](https://developer.apple.com/documentation/xcuiautomation), so visual scene/control checks use the simulator UI and physical hardware instead.

## Physical Vision Pro acceptance checklist — pending

| Test | Expected observation |
| --- | --- |
| VR180 SBS / TB | Left eye sees LEFT EYE, right sees RIGHT EYE; square half-sphere geometry, FRONT ahead |
| VR360 SBS / TB | Same eye separation across full sphere; rear seam closes |
| Mono in both projections | Same image in both eyes; no unintended duplication |
| Orientation | NORTH above, SOUTH below, text readable, corner marker in the expected location; verify Flip vertically if needed |
| Eye swap | Each eye's label switches without changing projection |
| Pose/recenter | Turning reveals the panorama; translation keeps it distant; recenter restores forward yaw without tilting the horizon |
| Timeline | Play/pause, scrub, skip, end-of-stream and HLS seekable range behave correctly |
| Session | Enter/exit repeatedly; webpage and persistent site storage survive; native audio stops on exit |
| Error paths | Blob, encryption, invalid URL, expired source, access denial and no-frame output show usable errors with an exit control |
| Auth fixture | Browser establishes normal cookie session; native MP4 and all HLS requests remain in its legitimate scope |
| Lifecycle | Cancel loading, navigate mid-handoff, Crown dismiss, close window, background/resume and audio interruptions |
| Website | Use the normal page/access flow; record actual candidate, readiness, decoded frames and viewable projection before claiming support |

Real stereo isolation, head tracking, gaze/pinch interaction, audio routing, motion comfort, sustained decode/GPU performance, thermal behaviour, and any external website compatibility require physical hardware. Flat simulator output and desktop decoding cannot establish these.

## Known limitations

- Simulator and unsigned device builds pass. No physical device run has occurred. Simulator grid display, vertical-flip interaction and return to the browser were subsequently checked with user assistance. After the orientation correction, the user confirmed upright playback immediately without flipping on version 0.2.1. Physical per-eye presentation remains unverified. Both visionOS 26 and 27 have now passed native simulator tests.
- No Pornhub stream has played successfully: user-assisted asset loading failed, and the user also reports webpage playback failure. No site-specific extractor is implemented.
- Only unprotected equirectangular packed/mono content is targeted; browser-local blobs, DASH, WebRTC, fisheye and tagged multiview/immersive formats are unsupported.
- Public cookie APIs preserve only part of browser authentication. Required headers, segmented CDN scope, redirects and URL expiry can prevent handoff.
- SDR colour conversion is approximate. Eye textures are capped at 2048 pixels on the longest dimension; no high-resolution performance claim is made.
- The controls remain in their recentered world position. Turn back toward them or use the system exit if you look away.
- Captions, audio-track selection, flat/cinema mode, sophisticated live/DVR UI, automatic motion mitigation and audio-interruption recovery are not implemented.
- WebKit may enforce site-specific storage/media restrictions. Closed shadow roots and some frame configurations can hide videos.
- No whole-video download task exists, but normal AVFoundation/WebKit buffering or caching still occurs.

## Interactive validation after the Mac was unlocked

VisionStream's browser and library sheet were visually inspected in Device Hub. Computer-control pointer events did not reliably activate the simulated app, including after reconnecting Device Hub and restarting the dedicated simulator. The user manually opened the library sheet, connected to the existing authenticated CC0 fixture library, selected the first MP4 and reported that the immersive calibration grid appeared. The attached screenshot, retained as `TestResults/ui-before-orientation-fix.png`, showed the grid and controls but revealed vertically inverted video. The user confirmed that Flip vertically made FRONT upright and that Return to page restored the browser. These are user-assisted simulator observations, not physical-headset tests.

The initial GPU tests verified eye-texture contents and mesh geometry independently, so they did not catch the material image sampler's vertical-coordinate convention. VisionStream 0.2.1 corrects mesh V at that boundary, with a new regression covering north/south mapping across both projections and all eye packings. The original byte-splitting shader and the meaning of the optional Flip vertically control are unchanged. Final post-fix automated results are recorded in `TestResults/orientation-test-matrix.json`.

On 23 October 2026, the user tested the corrected 0.2.1 build (build 3) in “VisionStream visionOS 26”: connected to `https://127.0.0.1:58097/library`, opened the first entry and selected Watch in VR beside MP4. Asked whether FRONT was upright immediately without using Flip vertically, the user replied “Yes, upright immediately”. This passes the default-orientation visual check for the VR180 mono MP4 fixture. The observation is user-assisted; no post-fix screenshot or physical-headset check is claimed. It does not establish live website compatibility or visual acceptance of every stereo/projection combination. The structured record is `TestResults/ui-validation.json`.

A one-second process sample during the input issue showed the app's main thread in its normal event wait, with no blocking application call observed during that sample. This is limited diagnostic evidence, not a general responsiveness guarantee.

## 0.3.4 webpage policy regression

The user reported an empty, paused webpage player in 0.3.3, before a native attempt. A new page-owned delayed, unmuted playback test reproduces NotAllowedError with the former all-media gesture requirement. The production browser now allows asynchronous page playback. The regression retains the restrictive negative control and verifies presented frames for both MP4 and HLS. The fixture remains original CC0 media.

Current Release results are in `TestResults/web-policy-test-matrix.json` and the `web-policy-26-*` / `web-policy-27-*` logs. The current run does not opt into public NASA extraction or the private sample: these are explicit skips, not current-release passes. Their previous 0.3.3 results remain in `diagnostics-test-matrix.json`. This change does not establish live Pornhub compatibility. See `WEB_PLAYBACK_POLICY.md`.

## 0.3.5 native handoff follow-up

See [the native handoff investigation](NATIVE_HANDOFF.md) for the new empty-attribute and default-selection fixes, supported User-Agent preservation, controlled validation, and the confirmed 0.3.4 HLS preparation timeout. Native Pornhub compatibility remains unresolved.


## 0.3.6 unattended scene tests

See [unattended testing](AUTOMATED_TESTING.md). The simulator-only runner executes production form actions, real immersive spaces and native decoded streaming frames without host clicks. It reproduces a last-window dismissal race and verifies the pushed-window correction. Separate native unit/integration suites pass 62 methods with two optional skips on each runtime. Controlled MP4/HLS, library, cancellation and unsupported-source scene checks are distinct from the optional live public NASA finder check. The new repeated-entry case tests two complete entries/exits in one process. Final results and any earlier failed investigation runs are recorded in `TestResults/automation-test-matrix.json`.

The first public-opt-in native run on visionOS 27 failed its webpage NASA presented-frame check and subsequent assertions in that method; a fresh controlled run passed, and the separate NASA finder-to-immersive scene check passed. That initial failure is retained, not counted as a pass. It demonstrates why external-network tests remain separate from deterministic fixture checks. No current private sample or live adult-site success is claimed.


The subsequent user-supplied 0.7.0 report contains 231 recorded events and no reported gaps. Two fresh HLS saves pass playable/unprotected finite asset preparation and select the same 1440 × 720 rendition as successful native streaming, then fail with CoreMediaErrorDomain -12938 and zero received bytes reported by the download tasks. The background User-Agent option was configured; it did not resolve either attempt. Foreground playlist/segment metrics report HTTP 200, but no background download HTTP response is available. One separately selected source also fails loading and must not be conflated with the offline errors. The successful playlists each advertise one rendition. Automatic format selection is disabled in this session. Root cause and a working real-source download fix remain unestablished; the record does not establish that login is required. See `TestResults/session-history-0.7.0/user-report-assessment.json` for the sanitized assessment. No additional private-site requests were made by the agent.


The complete 0.7.0 event history also distinguishes two automatic-format outcomes: the first stream accumulates three matching frames and selects VR180/SBS automatically; the second remains inconclusive and is corrected manually, including after briefly re-enabling Auto. The final `automaticFormat:false` snapshot alone must not be taken as proof that Auto was never attempted. This source-dependent detection limitation remains open; layout cannot reliably be inferred from dimensions alone.
