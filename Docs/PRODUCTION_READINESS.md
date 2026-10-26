# Production readiness — current 0.12.0

Verification for 0.12.0: 95 Swift package tests pass; the standalone runner passes 89 methods / 1,797 assertions. Each visionOS 26/27 full native suite passes 185 methods with 12 optional skips and no failures. The 27 combined scene run passes 69 checks. On 26, the first five scene cases pass 57 checks; its last forms dismissal times out and the isolated 12-check forms rerun passes. Initial countdown cancellation and attachment-popover failures were corrected and retained as evidence. See `TestResults/reclined-viewing-0.12.0/matrix.json`. New coverage uses original CC0 fixtures and synthetic head transforms; no new live-site or physical-headset acceptance is claimed.

## Reclined viewing (0.12.0)

**Recenter** starts a three-second countdown. Look where the video should face; the renderer captures the full head orientation, including upward pitch and side tilt. It keeps that orientation fixed while you look around naturally. **Position → Video tilt** adjusts the video up/down by up to 90 degrees relative to the captured centre without moving the controls. **Reset tilt** removes that adjustment; **Reset upright** levels the video with the room and keeps the controls facing you. Recenter clears manual tilt. Each new immersive session starts centred on the current head pose; quality changes preserve the current position.

Playback controls are now a glass-backed RealityView attachment, rather than a separate system window. Position, Format and Quality expand within that surface because the former window popovers do not reliably present from attachments. Recenter positions the actual visible controls below the captured viewing direction. Return to page opens the browser and waits for its view to appear before dismissing immersion. System dismissal also restores the browser. The single WKWebView and its live webpage remain in AppModel. No head pose or viewing-angle history is saved. Physical Vision Pro gaze/pinch and reclining comfort remain unverified.


Version 0.11.0 adds recent-user-Play automatic native entry, default-on persistent opt-out, a conditional browser video bar, and bounded legitimate cookie snapshots with cancellation and logout invalidation. Original code is now MIT at the owner's request. A separate public source package excludes local reports/media and private owner settings; whoever distributes an App Store build configures their own publisher/signing/compliance details. Controlled WebKit/native/scene tests are documented in AUTOMATED_TESTING.md. Physical headset input/comfort and arbitrary site compatibility remain unverified. One parallel quality-switch scene timeout is retained separately; the isolated rerun passed, and its original cause is not established. The cookie deadline is a separately verified resilience improvement, not proof of that failure's cause.


The general-purpose browser now has opt-in detailed diagnostics, confirmed deletion, an in-app policy/licence reader, original layered icon, separate App Store archive configuration and reproducible submission preparation/preflight. Source and native privacy checks pass; local-only support/privacy drafts are prepared. No signed distribution build, hosted public pages, completed encryption classification, source-authorization review or physical-headset release acceptance exists yet. See `Submission/README.md` and `TestResults/privacy-release-0.10.0/matrix.json`. Simulator success is not App Store approval.

The older assessments below are retained as development history; the current release matrix and save-queue/resource-recovery evidence supersede claims that no foreground save has succeeded.

## Earlier readiness assessments


Current 0.9.0 adds a tested clear-TS foreground MP4 fallback and stronger regional stereo detection. This remains a personal-use prototype, not a production-ready universal website player. The actual failing private source is unverified; physical-headset performance, long/high-bitrate remux saves, interrupted foreground recovery, broad codec/playlist support and App Store distribution review remain release gates. See MEDIA_RUNTIME.md and the resource-recovery evidence matrix.

Version 0.8.0 improves difficult stereo matching and adds resource-level HLS checks. Controlled tests pass; the specific live missing resource and second-stream automatic detection still require new user-initiated evidence because the agent cannot fetch the restricted site. This is not a confirmed live download repair.

Version 0.7.1 surfaces an explicit HTTP status from bounded native CoreMedia errors. Existing local system logs identify HTTP 404 during the user’s failed offline requests, but not which resource failed. No source URL is guessed or rewritten; successful real-source saving remains unresolved.

Version 0.7.0 adds persistent session diagnostics and an explicit public-API User-Agent option for new HLS background sessions. Reports expose coverage and separate legacy/unrelated failures. The user’s subsequent 0.7.0 report confirms two HLS saving failures despite this option being configured; public-sample acceptance is separate. History collection does not make the app production-certified: physical headset, long-session report memory/IO, privacy/retention controls and authenticated background lifecycle acceptance remain gates.

The 0.6.2 detector update removes the explicit-label gate, handles stereo disparity and preserves per-component metadata priority. It is tested with original fixtures and an existing privately downloaded local VR180/SBS file; this is not new live-site acceptance. HLS diagnostics improve failure investigation, but the user-reported Pornhub HLS download failure remains unresolved. Physical Vision Pro acceptance and the live-site failures below remain release gates.

This is a functioning development build for personal use. It is not yet a release validated on physical hardware. Simulator test success is strong evidence for code paths and scene lifecycle, but cannot establish stereo comfort, gaze/pinch usability, sustained performance or arbitrary website support.

The 0.6.1 public-preview investigation adds site acceptance probes, precise connection/download error messages and public CDN redirects with credentials removed. See [live-site results](LIVE_SITE_TESTS.md) for the observed failures; this does not establish general highest-quality site compatibility. The broader 0.6.0 acceptance evidence below remains historical where stated.

## Current 0.6.1 outcome

The ordinary native suites pass 120 checks on each simulator runtime; live failures are separate. The observed public VirtualRealPorn 4K file downloads and reopens in automatic VR180/SBS, while its download endpoints ignore a two-byte Range request and do not reliably prepare as native streams. The VR Bangers small clip saves/plays but does not establish VR-trailer support; SexLikeReal fails secure connection setup. See [the live matrix](LIVE_SITE_TESTS.md). No account/member-only testing was performed.

Missing MP4 dimensions can be measured before ordering compatible finder results. Failed metadata remains unknown. Public redirects are handled without forwarding website credentials; saved VR cues do not retain page URLs. The metadata client and probes use the actual default WebKit identity, verified against the browser. This does not replace the site's missing streaming endpoint or physical headset acceptance.

## Is it easy to use?

The main journey now has three steps: open a page, start its video, choose Watch in VR. The browser retains navigation and Downloads as visible controls; Video tools contains scanning, source discovery, download and diagnostics. Format is Automatic by default and can be restored before or during playback. The floating panel has named skip/play/recenter/return actions, a timeline, decoded resolution and quality settings. Help explains doubled images and separates image layout from panorama shape.

These decisions reduce the earlier clutter. Shared-action tests verify the windows, settings and playback behavior. They do not measure discoverability or successful human gaze/pinch input. The revised browser, saved MP4 library, bookmarks and settings were visually reviewed in visionOS 26 after the user enabled inspection. Playback controls were reviewed on both runtimes with original calibration media; no clipping/overlap was observed. Device Hub input still moves the pointer without reliably activating controls. The simulator-only mounted-sheet review hook avoids human setup, while an independent first-use/gaze/pinch test on a physical headset remains necessary. HLS task-row presentation has not yet received a separate visual review.

## Do downloads work?

There is now a real, separate native MP4 downloader. Controlled HTTPS tests verify complete saving, catalogue reload, offline AVPlayer/immersive rendering, format hints, seeking, deletion, normal scoped cookie handoff, cancellation and rejection of invalid/oversized responses. A public NASA MP4 was also fully downloaded and reopened locally in automatic VR360/mono at 2160 × 1080 on both simulator runtimes. A real-scene scenario exercises the browser download action, Downloads sheet, reopen and offline Watch path. This is no longer only a desktop yt-dlp download test.

**Save video** now supports MP4 and unprotected on-demand HLS through Apple’s native download service. MP4 import preserves originals; export uses the share sheet; a confirmed repair rebuilds damaged MP4 indexes. HLS supports pause/resume and a persisted local journal, with system-managed background requests and package location. HLS download quality is system-selected. Physical suspension/relaunch/eviction acceptance remains pending. Keep the app open for MP4 downloads/imports. Automatic transfer retry is not implemented. MP4 saving has an 8 GiB file limit and free-space checks. Completed HLS packages above 8 GiB are rejected, but suspended/background allocation is not continuously capped; storage is not reserved. Expired links and incompatible website requests can still fail. No new live Pornhub download was performed by the agent.

## Previous 0.6.0 capabilities retained

- Save video routes compatible MP4 and unprotected on-demand HLS to separate native transfer paths. HLS uses Apple’s background service, keeps packages in the supplied location, reconnects task identifiers and offers pause/resume/cancel. Active cancellation removes partial packages.
- Downloads imports MP4 from Files without changing originals, exports MP4 through the system share sheet, and can repair a damaged MP4 catalogue. Recovery preserves owned files and valid metadata; malformed or linked entries cannot become arbitrary local playback paths.
- Bookmarks retain intentional page links. Browser settings let the owner reopen Home, the last website’s origin or the exact last page. Reduced retention immediately removes saved detail. Damaged bookmark data is preserved, including when too large to back up safely.
- Shared-action scene checks cover the new windows and existing download/transport paths. Full native suites pass 112 methods on each supported runtime; focused HLS checks additionally verify active cancellation. The sustained playback run uses the published 4K fixture and measures actual frame progression and simulator process memory during repeated seeking, format changes and Highest/Adaptive transitions.
- Packaging verifies source/resource checksums, executable/crash-symbol agreement, normal simulator signatures, absence of simulator test hooks from the device binary and byte-for-byte consistency of deliverable archives. Updated builds are installed without clearing browser data or launching saved pages.

## Release gates, in order

| Priority | Gate | What must pass |
| --- | --- | --- |
| P0 | Physical Vision Pro acceptance | Correct per-eye isolation/depth, orientation, seams, field of view, head translation, recenter, gaze/pinch hit targets, window placement, Crown exit, audio/Bluetooth interruption, headset removal and relaunch. |
| P0 | Sustained performance and fidelity | Profile 30–60 minute 4K/8K sessions, high frame rates, GPU/CPU peaks, memory pressure, battery and thermals. Current RGBA16Float eye textures can consume substantial memory. Validate SDR colour; HDR is not supported as a mastering-quality path. |
| P0 | Current live compatibility | Test multiple authorised sources per intended site, record source/codec/quality behavior privately, distinguish webpage versus native failures, and verify actual highest decoded quality. One historical Pornhub success does not establish general support. No restriction bypass. |
| P0 | Signed device release | Configure the owner’s team/bundle identity, sign and install, verify sandbox/data protection and device entitlements, retain reproducible archives/symbols. Current archive is unsigned. |
| P1 | Offline expansion | Physical HLS background/relaunch/eviction acceptance, download-quality selection, duplicate detection and user-selected storage limits. |
| P1 | Browser essentials | Per-site controls, optional history, navigation/download failure recovery and independent first-use testing. Bookmarks and intentional restoration choices are implemented. Session persistence alone is not a full browser product. |
| P1 | Format and accessibility | Broader spherical metadata and documented fisheye support, physical stereo eye ordering, captions/audio selection, VoiceOver and large-text acceptance, reduced-motion/comfort testing. Unknown formats must remain explicit and manually adjustable. |
| P1 | Release operations | Minimal bundled Python dependencies, dependency/security update cadence, licence and encryption/export review for the actual distribution channel, app icon, automated clean-host builds, crash-reporting policy and regression/rollback process. |

The first four gates require hardware, normal live-site access or signing identity that cannot be replaced by simulator assertions. The app should remain labelled a development build until those gates pass. Adding every conceivable browser feature is not a substitute for passing them.

## If starting again

1. Define a narrow acceptance contract first: a source must produce native decoded frames, the correct image in each eye, usable transport/exit, measured quality and a successful restart. Separate website browsing, source discovery, streaming and saving as different capabilities.
2. Obtain physical hardware early and build the deterministic CC0 stream/scene harness before adding website-specific discovery. Keep human interaction tests separate from shared-action integration tests. This would have caught orientation, scene exit and format-selection problems sooner.
3. Model source provenance, request context, format confidence and quality policy explicitly from the beginning. Avoid a generic URL being treated as proof of playable VR. Preserve exact published URLs and parent playlist relationships.
4. Design the user journey first: Automatic, one Watch action, quality status, clear recovery, saved videos and privacy controls. Advanced projection, packing and diagnostics belong behind understandable settings.
5. Introduce the local media collection and transfer boundaries alongside streaming rather than retrofitting file URLs into the web candidate type. Prefer standard Apple playback/download APIs; isolate the large extractor runtime behind a replaceable adapter and ship the smallest necessary dependencies.
6. Plan source updates, reproducible builds, privacy and release gates from the first iteration. Add extra formats only when a licensed calibration source and physical acceptance method exist.

A more modular source-provider interface and separate transfer store would improve maintainability further. Rewriting the working renderer or adding unrestricted request interception would add risk without satisfying the missing acceptance gates.


The subsequent user-supplied 0.7.0 report contains 231 recorded events and no reported gaps. Two fresh HLS saves pass playable/unprotected finite asset preparation and select the same 1440 × 720 rendition as successful native streaming, then fail with CoreMediaErrorDomain -12938 and zero received bytes reported by the download tasks. The background User-Agent option was configured; it did not resolve either attempt. Foreground playlist/segment metrics report HTTP 200, but no background download HTTP response is available. One separately selected source also fails loading and must not be conflated with the offline errors. The successful playlists each advertise one rendition. Automatic format selection is disabled in this session. Root cause and a working real-source download fix remain unestablished; the record does not establish that login is required. See `TestResults/session-history-0.7.0/user-report-assessment.json` for the sanitized assessment. No additional private-site requests were made by the agent.
