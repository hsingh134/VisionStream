# Prioritised engineering tasks

Version 0.5.0 adds native MP4 downloads/offline playback, simpler browser menus, pre-playback Auto format, website-data clearing and audio lifecycle handling. See [current release gates](PRODUCTION_READINESS.md). Historical milestones follow.

Version 0.4.1 completes controlled 4K highest-rendition/automatic-format tests, real format/quality popover checks, bounded legacy spherical MP4 metadata support, and exact-page finder format cues. The highest priorities still requiring separate work are physical-headset interaction/stereo/performance acceptance, live-site maximum-quality acceptance, broader projection/metadata variants, and highest-quality selection when a master must retain external audio/subtitle context. Device Hub pointer/keyboard delivery remains an environment limitation; the shared-action scene tests run unattended.


## Completed development gates

- The user confirmed moving native Pornhub HLS video in 0.3.6 on the visionOS 27 simulator. VR180 + Side by side corrected a doubled view caused by Mono. Version 0.3.7 exposes image-layout choices clearly. One-stream loading/viewing is now demonstrated by user assistance; physical stereo/depth, high-quality native variants and broader sources remain separate checks.


- 0.3.6 adds an unattended simulator scene runner independent of Device Hub input. Real windows, WebKit MP4/HLS, cookie library handoff, AVPlayer transport, renderer mode changes, cancellation, exit and repeated entry can be checked without human clicks. The runner found a last-window dismissal race; the app now pushes its controls window over the retained browser. See [automation](AUTOMATED_TESTING.md). Physical stereo/pose and live restricted-site access remain separate acceptance gates.


- 0.3.4 repaired the all-media direct-gesture restriction; the user confirmed webpage playback. 0.3.5 removes empty source attributes that resolve to the HTML page, prefers prepared direct video by default and preserves the actual WebKit User-Agent through the documented asset option. The user selected the working webpage HLS in 0.3.4 and native preparation still timed out. That earlier failure was followed by the user-confirmed 0.3.6 HLS success described above; see `NATIVE_HANDOFF.md`.

- Version 0.3.3 corrects accurate seeking, end/replay, pending-seek/rapid-skip state, synchronous navigation invalidation, finder quality ordering/labels, page-media pause fallback and late-frame cleanup. Separate HTML media errors and native termination reasons improve failed-stream reports. The final 59 native Release methods pass on visionOS 26/27, including WebKit presented-frame callbacks, public NASA streaming and the private supplied MP4; 34 core, 16 resolver, 11 fixture and 10 detector tests pass. The updated app is installed in the user's simulator. Live production playback and physical viewing/control acceptance remain outstanding.


- Added supplied HLS parent-playlist candidates and explicit Automatic quality labels in 0.3.2, with conservative restriction merging, unchanged URLs and MP4 visibility before the result cap. Missing-resource errors now give specific guidance without inventing an HTTP status or expiry cause. The user's separate HLS and MP4 failures remain recorded as failures; these changes do not establish live playback support.

- Corrected Origin/Referer metadata handling in 0.3.1: warnings permit ordinary native attempts, while authentication headers remain unsupported. All 53 native tests pass in Release on visionOS 26/27, including MP4/HLS decoding through routes that reject injected website headers. 31 core methods, 9 resolver tests and 8 fixture tests also pass. This does not establish live Pornhub playback.

- Embedded Python/yt-dlp for on-headset public HTTPS source discovery in 0.3.0, with no Mac companion. All 51 native Release tests pass on visionOS 26/27, including public NASA MP4 extraction through native decoded renderer frames; 30 Swift core methods and 8 Python unit tests pass. The unsigned device archive builds. This is not verification of production webpage extraction or Pornhub support. YouTube engineering is deferred.

- Installed Xcode 27.1, the visionOS 27 SDK/simulator runtime, and Apple's Metal toolchain.
- Compiled the app for both simulator and physical Vision Pro, preserving the visionOS 26 minimum target; corrected Swift 6 concurrency and SDK diagnostics.
- Passed 35 native tests in all four Debug/Release × visionOS 26/27 configurations, including fresh-boot runs. These cover all twelve MP4/HLS decode and renderer variants, browser-cookie authorisation, real cross-origin WKWebView detection, navigation cleanup, seeking/pause/resume, error recovery, cancellation/replacement and 12 native Metal configurations with 1024 channel checks.
- Corrected cancellation cleanup and the visionOS 26 startup-navigation race; verified Home loading and saved-session restoration. Passed Xcode static analysis and standard Swift Package tests, and created a validated unsigned Release archive with matching debug symbols.

- Implemented the read-only HereSphere library subset, optional empty-JSON POST reads, explicit metadata application, bounded background chunk reception and exact-scope cookies. All twelve library MP4/HLS variants decode; negative and cancellation cases pass. BaDoinkVR's live library remains unverified; one separate browser-to-native video succeeded in later user-assisted testing.

- Completed user-assisted simulator entry/flip/exit checks, found and corrected default vertical orientation at the material-coordinate boundary, and added a regression across both projections and all eye packings. The user confirmed that version 0.2.1 starts the VR180 mono MP4 calibration stream upright without flipping.

## P0 — Complete viewing/control acceptance and live-site testing

1. Extend the single-stream user-confirmed Pornhub HLS success to more authorised sources and native quality levels. The reported native frame was 480×240 while the webpage reported 1440×720; determine whether native adaptation reaches a higher resolution during sustained playback. Keep documented layout/projection separate. Record actual HTTP/error evidence for any new failure rather than attributing it to access, expiry or codecs without evidence. Python still has no browser cookies. Improve extractor cancellation with a hard job deadline.

2. The native Playback window, transport and renderer bindings now have unattended CC0 scene checks; complete visible controls/frame-edge acceptance on physical hardware, then repeat the BaDoinkVR viewing/control check. The user confirmed the new 0.2.2 navigation flow works after reporting refresh-on-click. The original cause remains unconfirmed, and pointer/Command–L paths were not individually identified. Keep this distinction in the acceptance record.
3. Continue user-assisted observations from normal authorised site playback. One BaDoinkVR video reaches moving immersive playback but has unresolved viewing/control issues; Pornhub webpage playback works after 0.3.4; the native HLS route still failed in that release. Browser approval refused Pornhub and BaDoinkVR navigation in this session, so no tool workaround was attempted. VR Bangers works only in the webpage player in user testing; VirtualRealPorn remains untested live.
4. Use Playback details to identify the actual source type or native failure before implementing any further adapter. The privacy/recovery checks and all 40 native tests pass in Release on visionOS 26/27. Version 0.2.3 additionally identifies the attempted format and explains server-response failures. See [live-site testing](LIVE_SITE_TESTS.md).

## P0 — Complete physical Vision Pro acceptance

1. Sign with the user's development team, pair a physical Vision Pro, and run all six CC0 MP4 calibration clips and their HLS equivalents from trusted HTTPS. Verify per-eye isolation, readable text, orientation, seam/hemisphere bounds, head translation, level recenter and accessible controls. Repeat the native GPU colour test on device; all twelve packing/swap/flip configurations currently pass in the simulator.
2. Check play/pause, seeking, buffering, URL expiry, connection loss, cancellation during preparation/opening, repeated entry/exit, Crown dismissal, audio stopping and browser restoration.
3. Run the cookie fixture on-device. Then manually assess the normal Pornhub VR player under the user's legitimate access state. Record actual detection and playback results; do not mark site support based on generic test streams.
4. Verify interruption and background/resume behaviour on physical hardware; simulator model tests cannot establish spatial audio routing or system scene lifecycle behaviour.
5. Validate a real published BaDoinkVR HereSphere endpoint, normal browser-cookie acceptance and any separate official player-authentication contract. The read-only format adapter is implemented; live access failed from this environment and no live HereSphere-library playback claim is justified. A separate browser route reached moving video, with unresolved viewing/control issues. See [library assessment](VR_LIBRARIES.md).

## P1 — Reliability, format handling and performance

1. Profile main-actor frame work, IOSurface lifetime, two in-flight submissions, texture allocation peaks, adaptive HLS resolution changes, high frame rates, and thermals. Version 0.4.0 raises the eye texture cap to 4,096; measure allocation peaks, sustained high-resolution decoding and thermals on hardware before treating that setting as a performance guarantee.
2. Add audio-interruption/route-change handling, robust resume after app suspension, richer buffering/end-of-stream state, and a control recall mechanism when the viewer turns away from the panel.
3. Add explicit detection/routing for MV-HEVC, APMP and Apple Immersive Video through the system player or VideoPlayerComponent. Current packed-layout rendering is not sufficient for tagged multiview content.
4. Validate decoded colour metadata and implement correct transfer functions, HDR tone mapping and wide-gamut handling. The current approximate SDR sRGB treatment is a prototype limitation.
5. Extend the native WKWebView tests beyond the existing cross-origin/srcdoc/open-shadow-root/dynamic-source, navigation-clearing and cookie fixtures to production authentication flows, navigation during handoff and content-process termination.
6. Test HLS live windows, discontinuities, multi-variant manifests, segment failures and multi-host cookie constraints. Improve error categorisation without logging media tokens or credentials.

## P2 — Additional useful capabilities

1. Add explicit fisheye/equidistant projection modes only with documented source geometry and licensed calibration material.
2. Add captions, audio/subtitle selection, bookmarks and a data-clearing UI. Fitted Screen playback and a standard control window are implemented in 0.2.4; physical placement and interaction still need acceptance.
3. Add app icon artwork, release signing/archive validation, and continuous visionOS build/test coverage on an Xcode host.

Public website extraction is now provided by bundled yt-dlp, with the limits above. Access-control workarounds and DRM bypass remain outside scope. Explicit supported MP4 downloads are implemented in 0.5.0; HLS offline saving remains outstanding. If native access is refused, the current result is a clear unsupported-stream message. Further YouTube work is deferred at the user's request.
