# Public-preview selection — 25 October 2026, VisionStream 0.6.1

## Session diagnostics and HLS follow-up — 0.7.0

A user-supplied 0.6.2 report shows Automatic on, VR180/SBS, decoded HLS at 1440 × 720, Highest selected at the same dimensions and no native playback error. Its download failure is CoreMedia -12938 with no HTTP result. In 0.6.2, the latest failed HLS job could be mixed with unrelated playback. Version 0.7.0 separates and correlates those attempts and records native transport/variant details when available. This error alone does not establish a missing URL, authentication, codec or server cause.

One compatibility hypothesis is implemented: new native background HLS sessions receive the same actual WebKit User-Agent already passed to the asset and working streaming. No access bypass or fabricated headers are added. The subsequent 0.7.0 history confirms it did not fix either of two new Pornhub saving attempts. No new remote Pornhub access was performed by the agent. See [session architecture](ARCHITECTURE.md) and [testing](TESTING.md).

## User follow-up and automatic detection update — 0.6.2

The user supplied a 0.6.1 report with decoded HLS video at 1440 × 720, Highest selected at the same resolution, and no native playback failure. That report had Automatic disabled. After enabling it, the user reported Screen/Mono while manually choosing VR180/SBS worked. A separate screenshot identifies a failed Pornhub HLS download. These observations do not establish a current highest available site rendition or a successful download.

The detector’s explicit VR-cue gate and exact whole-eye comparison missed unlabelled/disparate stereo images. Version 0.6.2 uses repeated global/regional image matches with bounded horizontal disparity, averaged samples and metadata/manual precedence. The existing user-downloaded local VR180/SBS sample now passes native automatic detection and manual-to-Automatic reactivation in the simulator. This uses an existing local file, with no remote Pornhub access. The reported live HLS download failure remains unresolved; new failures expose sanitized numeric codes in Playback details. Existing failed rows cannot recover codes that were never recorded. See [testing](TESTING.md).

## Previous 0.6.1 site investigation

The user chose **public previews only**. No login, account creation or purchase was performed. The native probes use publicly observed assets or the app’s ordinary finder on the exact public pages inspected through the browser. They use production playback, rendering and download code. These are **asset component checks**, not complete browser-to-native scene/identity acceptance on physical hardware.

| Site | Public result | Highest quality / automatic VR |
| --- | --- | --- |
| VR Bangers | The observed small public clip streams, pauses, seeks, saves and reopens at **600 × 300**. A later finder candidate also streams, saves and reopens at **1920 × 960** on visionOS 26. The finder is inconsistent, and association with the custom DL8 VR trailer is not established. | Both tested clips stay Screen/Mono. Advertised 8K does not establish an available public rendition. Highest-quality VR remains unverified. |
| VirtualRealPorn | The finder exposes four public download routes. Three files save and reopen; the largest decoded dimensions are **3840 × 1920**. The other two valid files decode at 3200 × 1600 and 1920 × 1080. One route fails MP4 validation. Native streaming from these routes is not repeatable. | Saved 4K and 3200 × 1600 files automatically become **VR180 / Side by side**. The ordinary 1920 × 1080 file remains Screen/Mono. 4K is the highest valid public file tested, not a verified member maximum or reliable live-stream quality. |
| SexLikeReal | Browser inventory exposes a 2160p public MP4. Native playback and download fail during secure connection setup (-1200), before any decoded frame. Free full-length access asks for an account and was not used. | Decoded quality and automatic VR are unverified. No certificate checks or network settings were changed. |

The separate VirtualRealPorn public header probe requested `bytes=0-1`. All four routes advertised **HTTP 200**, full-file Content-Length (about 67–102 MB) and **no Content-Range**. Response bodies were cancelled without downloading them. These download routes did not honour that byte-range request. This is concrete evidence for a seekable-media compatibility limitation, not proof that the website has no separate authorised streaming endpoint. An earlier isolated visionOS 27 streaming success was not repeatable and is retained as historical component evidence.

## Test context correction

Early asset probes omitted the browser’s User-Agent and did not fully represent the production Watch action, which already preserves it. The corrected probes use the actual default platform WKWebView identifier, verified equal to VisionStream’s browser identifier. The metadata inspector now uses it too. It is read from an isolated blank WebView without opening a website or browser session; no device/browser identity is invented. Both inspected and uninspected finder paths still reproduced the native rejection for the VirtualRealPorn download routes in the corrected run. Earlier records are retained under `TestResults/live-site-selection/before-webkit-identity/` and separate run directories; they must not be interpreted as final product acceptance.

No browser cookies, passwords or account state were imported for these public component probes. Consequently these checks do not establish behaviour for a logged-in WebKit session. The app’s normal scoped-cookie handoff is tested with controlled authorised fixtures separately. Missing metadata alone does not establish a login requirement.

## Fixes and limits

- The finder inspects missing MP4 dimensions through native asset APIs and ranks the largest known complete MP4 first. It starts optional work within a 12-second budget, caps candidate count at eight and bounds individual requests. When a server refuses native metadata, dimensions stay unknown; no higher-quality URL or dimension is invented. Controlled ordering and exact published-destination checks pass. Site-wide maximum quality is not certified.
- A VR token in an associated HTTPS page path enables conservative image analysis. It never directly forces geometry or stereo. Existing texture, confidence and repeated-frame requirements remain. A saved context cue preserves this behaviour without storing the webpage URL. Rich-texture positive and ordinary-video negative cases pass.
- MP4 downloads follow bounded public HTTPS redirects, stripping website credentials and headers on a host change and preserving only the legitimate client identifier. Downgrades and embedded credentials remain rejected. Errors distinguish HTTP responses, invalid media/response, unsupported redirects and secure connection failures; empty files are not misclassified as too large.
- Live probes are opt-in. Reports omit URLs, signed queries, titles, cookies and request headers. Platform URL logs are redacted and the runner has a 15-minute deadline. Temporary test videos are removed. The metadata-only finder itself does not download media; the separate preview probes explicitly exercise the downloader.

The earlier **Pornhub and BaDoinkVR origin-policy refusals remain in effect**. No alternate route was used to test those origins. The historical user-assisted Pornhub result below is not a current automated highest-quality or download result.

The remaining engineering work is to obtain a suitable publisher-supplied streaming source or design a bounded progressive-loading fallback for non-seekable routes, establish source association for custom players, investigate the SexLikeReal connection on physical hardware, and complete Vision Pro depth/input/thermal acceptance. This release remains a tested development build.

Redacted records and phase provenance: [site matrix](../TestResults/live-site-selection/matrix.json). Apple defines error -1200 as a secure connection failure without identifying a more specific cause: [Apple documentation](https://developer.apple.com/documentation/foundation/nsurlerrorsecureconnectionfailed-swift.var).

---

## Historical investigation and user-assisted observations

# Latest live result — 25 October 2026

**User-assisted Pornhub HLS playback succeeded in VisionStream 0.3.6 on the visionOS 27 simulator.** The report shows decoded frames at 480×240 and no native failure. The user confirmed that choosing VR180 + Side by side produced one view and moving video. This is one stream/session, not general site or headset certification. See `TestResults/live-user-hls-vr-success-0.3.6.json`. The agent did not fetch the site or handle login. Prior failures below remain historical evidence.

# Live website compatibility checks

Updated: 25 October 2026. Earlier live playback observations below are from 23 October unless separately dated.

## 25 October: automatic HLS also fails; webpage playback needs diagnosis

The user confirmed the Automatic quality row is present and reported an HLS failure at player readiness, with zero decoded dimensions and no captured failure codes. They could not recall the orange message. This is a failed live retry, not a pending parent-playlist test or a success. A subsequent report has native playback `not-attempted`; the user explicitly says regular videos fail inside the webpage too. See `TestResults/live-user-reports-0.3.2.json`.

The existing reports cannot identify why the webpage's video failed: they did not include HTML media error, ready-state or network-state values. Version 0.3.3 adds those read-only values and explicit native timeout/rejection classification. No new live-site claim is justified until the user retries the installed update. Controlled website-player tests are distinct from production site support.

## 25 October: both HLS and MP4 report missing resources

The user provided 0.3.1 Playback details for HLS (2560×1440) and MP4 (240p, width unknown). Both failed before decoded frames with `NSURLErrorDomain:-1100` and `CoreMediaErrorDomain:-12938`; no actual media HTTP status was available. HLS failed while waiting for the player; MP4 failed during asset loading. MP4 was therefore actually tried and failed, rather than remaining an untested fallback. See `TestResults/live-user-missing-resource-reports-0.3.1.json`.

This narrows the failure to media preparation; it does not establish an expiry, codec, authentication or missing-header cause. Version 0.3.2 adds clearer missing-resource guidance and offers a supplied HLS parent playlist as an automatic-quality choice. It does not repair a missing source or establish site support. No restricted site was fetched by this agent to investigate the reports.

## 0.3.0 finder result and 0.3.1 correction

The user confirmed the Find streams sheet opens. A subsequent screenshot, supplied after the requested individual Pornhub page test, shows HLS candidates at 2880×1440 and 2160×1080 with disabled Watch in VR buttons and the website-request-information warning. The screenshot does not expose the URL or distinguish which header class triggered the block; it does not establish successful native playback. See `TestResults/header-context-user-report-0.3.0.json`.

Version 0.3.1 treats Origin/Referer-only metadata as an advisory and allows an ordinary AVPlayer attempt without those headers. Authentication headers and protected/unsupported formats remain blocked. Controlled header-free MP4/HLS rendering tests pass on visionOS 26/27. Live-site acceptance after this change remains pending; no site header spoofing, proxy or access workaround was added.

## Current outcome

**BaDoinkVR: moving native immersive video observed, but viewing and control acceptance fail/remain incomplete. Pornhub: native preparation failed; user clarifies that ordinary Safari video works and VR mode fails. VR Bangers: webpage playback works; native immersive playback not demonstrated. VirtualRealPorn: pending.** Original CC0 fixture success is recorded separately in [the test report](TESTING.md).

| Site | This test session | What is needed next |
| --- | --- | --- |
| Pornhub | Browser-tool access was refused. After the navigation update, user-assisted testing reported page HTTP 200, MP4/HLS candidates, then native failure at asset loading (-11850/-12939). The user later clarifies that ordinary video works while VR mode fails. A follow-up report after an M3U8 request has the same codes plus browser-local candidates; the attempted format was not recorded by 0.2.2. | Establish normal webpage playback and access first. Use the new attempted-media field for any later native retry; the current evidence does not isolate a native-only defect. |
| BaDoinkVR | The browser tool refused its help page. The user subsequently opened the normal site in VisionStream 0.2.2 and explicitly confirmed moving immersive video after Watch in VR. This tested the ordinary browser route, not the JSON library. The user then reported improper controls and incomplete visible video. | Isolate the failed native controls and source geometry/field of view; this is a partial transport/render result, not full viewing acceptance. |
| VR Bangers | User reports “Only the webpage player works”. Native immersive playback is not demonstrated. | Collect the native candidate/error result and clarify the website motion/VR setup notice. |
| VirtualRealPorn | No live player test completed in this session. | Manually check an available packed equirectangular preview. Its dedicated tagged multiview downloads use a different, currently unsupported playback path. |

These are access/testing limitations, not proof that any particular website is supported or incompatible. No alternate access route was used after the browser refusals. No accounts were created, payments made, access checks bypassed, or whole website videos downloaded.

## Navigation change and safe diagnostics in 0.2.2

The website-address control now opens a separate sheet with an independent editable draft, explicit Go and Cancel actions, keyboard focus and Command–L support. The previous field shared state with ongoing page URL updates. This change avoids draft replacement and provides another way to enter addresses, but the reported refresh-on-click behaviour has not yet been reproduced or diagnosed conclusively: Device Hub input routing may also be involved. The user subsequently replied “works” to the navigation recheck using `https://example.com`; the response does not specify whether the pointer or Command–L path was used. See `TestResults/ui-navigation-0.2.2.json`.

**Playback details** below the browser generates a report containing main-page HTTP status (when received), allowlisted numeric network/WebKit errors, candidate source kinds, standard MIME/extension labels, dimensions, encryption flags, native player stage, allowlisted numeric playback errors, and a media HTTP error status only when AVPlayer explicitly identifies the log error domain as HTTP. Version 0.3.3 additionally reports a fixed native failure reason, item status at failure, up to eight allowlisted numeric player-log codes, and HTML media error/loading/paused states when available. It contains no page/media URLs, titles, cookie values, headers, error descriptions or AVPlayer log strings. Unknown MIME types and error-domain names are replaced by generic labels. Reports are generated locally and shared only when the user chooses Share report.

Native diagnostic stages distinguish an unattempted stream, rejected candidate, asset load, player readiness, and a decoded frame reaching the renderer. Readiness or a decoded frame alone does not prove correct eye layout, projection, tracking or successful sustained live-site playback. Native attempt diagnostics clear on a new browser navigation when playback is idle.

## Manual sequence

1. In Device Hub, select **VisionStream visionOS 26** and interaction mode. Click the website-address control; it should open a sheet. If pointer input still misses, enable Device Hub's **Capture Keyboard** and use **Command–L**. Enter an ordinary address and choose Go to confirm navigation first.
2. Open the desired website normally. Complete any required age verification, CAPTCHA, sign-in or account checks yourself. Do not send credentials or identity documents to the developer/chat. A subscription is not required merely to run this test; if no authorised preview is available, record the access gate.
3. Start one available VR preview in the page. Choose Scan videos. Record whether a candidate appears, and any unsupported reason. A browser-local blob or encrypted source remains unsupported; do not seek restricted alternate URLs.
4. If Watch in VR is available, choose the projection and eye layout actually documented by that source, then attempt playback. Record upright orientation, eye arrangement, visible movement/audio, seeking and Return to page. An ordinary flat ad is not a VR playback success.
5. Open Playback details after any failure and share the report with the site name and a short description of what happened. Avoid signed links and explicit screenshots. If no candidate appears, report that result rather than guessing its media format.
6. For the library connector, use only a published HTTPS HereSphere endpoint and its supported request method. Do not guess login/token APIs or import credentials into an unsupported protocol. Record any separate authentication or metadata requirement.

Physical Vision Pro validation remains necessary after simulator tests.

## Pornhub follow-up

The user explicitly reports that the normal webpage video also fails. The redacted report is `TestResults/pornhub-user-report-0.2.2.json`; see [the detailed assessment](PORNHUB.md) for the qualified Apple error interpretation. The subsequent BaDoinkVR browser-to-native preview played successfully; its controls and the other sites are being checked separately.

## Viewing/control follow-up

The later BaDoinkVR check did not pass full acceptance: the user reports controls do not work properly and the whole video is not visible. This may involve source projection/layout, expected panoramic field of view, native interaction, or website-controlled VR mode; no cause is confirmed. A separate user screenshot reads “Configure your browser for VR” and “Safari needs to be configured to allow motion controls”. It is website UI, not a VisionStream-native setting. The user clarified that the notice appears on all tested sites and that the problematic controls are VisionStream’s own floating panel. Website motion setup therefore does not by itself diagnose the native control failure. The app does not bridge a website XR session to its native RealityKit experience. Apple documents that the WKUIDelegate motion-permission method defaults to the system prompt when not implemented; automatic permission grants are not a compatibility fix. [Apple permission documentation](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestdeviceorientationandmotionpermissionfor:initiatedbyframe:decisionhandler:)).

## 0.2.4 viewing/control changes awaiting manual acceptance

Playback controls move from a world-space attachment to a standard visionOS utility window, with explicit transport labels, duration, seek availability, decoded dimensions, and Space/arrow/Escape shortcuts. Closing that window exits immersion. Screen + Mono is the new default for ordinary previews: a fitted rectangle displays the entire decoded frame with its aspect ratio, rather than assuming a spherical VR180/SBS source. VR180/VR360 and independent stereo options remain available; the HereSphere route applies its explicit VR metadata. Screen sizing also updates when eye packing changes while paused or decoded dimensions change. The website’s motion notice is not suppressed, and no motion permission is automatically granted. A longer original 32-second CC0 control clip is available at `/controls.html` for the manual window/transport check.

## Safari comparison

The user reports that the other sites work in Safari while Pornhub does not. Device and error details remain unknown. This broad Safari observation is separate from native VisionStream acceptance; see `TestResults/safari-user-observation.json` and the updated [Pornhub assessment](PORNHUB.md).

## Latest clarification and VR baseline

The user clarified ordinary video works and VR fails. This supersedes a broad interpretation that all Pornhub webpage playback fails; access restrictions are not established as the explanation. The simulator remains on the local Screen-mode calibration page. A true VR180 + Mono check has been requested separately; the current Screen mode is deliberately flat. Website motion/XR controls do not configure native RealityKit playback, and changing projection/eye packing cannot create a VR source from a flat preview.


The subsequent user-supplied 0.7.0 report contains 231 recorded events and no reported gaps. Two fresh HLS saves pass playable/unprotected finite asset preparation and select the same 1440 × 720 rendition as successful native streaming, then fail with CoreMediaErrorDomain -12938 and zero received bytes reported by the download tasks. The background User-Agent option was configured; it did not resolve either attempt. Foreground playlist/segment metrics report HTTP 200, but no background download HTTP response is available. One separately selected source also fails loading and must not be conflated with the offline errors. The successful playlists each advertise one rendition. Automatic format selection is disabled in this session. Root cause and a working real-source download fix remain unestablished; the record does not establish that login is required. See `TestResults/session-history-0.7.0/user-report-assessment.json` for the sanitized assessment. No additional private-site requests were made by the agent.


A subsequent passive read of existing user-simulator `nsurlsessiond` logs explicitly reports HTTP 404 (File Not Found) during both failed asset downloads, at the same times as the app’s -12938 failures. The specific requested resource remains redacted and unidentified. Foreground media requests report 200 separately. Version 0.7.1 retains only a bounded explicit numeric HTTP prefix from native CoreMedia errors; it never maps an unexplained -12938 to 404. This improves diagnosis, not download compatibility. No new private-site network request was made.


The complete 0.7.0 event history also distinguishes two automatic-format outcomes: the first stream accumulates three matching frames and selects VR180/SBS automatically; the second remains inconclusive and is corrected manually, including after briefly re-enabling Auto. The final `automaticFormat:false` snapshot alone must not be taken as proof that Auto was never attempted. This source-dependent detection limitation remains open; layout cannot reliably be inferred from dimensions alone.
