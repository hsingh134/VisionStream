# Pornhub VR compatibility assessment

## User evidence received 26 October 2026

The user-supplied schema-2 report from 0.9.0 records three native background failures with explicit HTTP 404. The first two foreground recoveries then complete successfully, saving MP4 files of 71,451,899 and 70,130,506 bytes. All 227 recorded foreground segment responses are HTTP 200; the third save is still active at report export. The final snapshot identifies a local MP4 decoding1440×720 in VR180/SBS without playback errors. Thus real-source fallback saving is now established for two attempts, not universal site support. Native background resource identity remains unavailable. See `TestResults/save-queue-0.9.1/user-report-assessment.json`; no raw private browsing history was copied into the source package.

## 0.9.0 resource tracing and foreground save recovery

The current implementation adds bounded checks of exact published HLS resources after selected native save failures. Reports correlate playlist/dependency/segment role, sequence, HTTP status and a per-session resource ID without exposing private URLs or credentials. Foreground range/header checks are labelled separately from native background traffic; a successful check does not prove the background request was equivalent.

A controlled simulator fixture proved that Apple's background HLS service can send a different User-Agent from the actual working WebKit player despite public request options. Supported clear on-demand MPEG-TS can now recover as an MP4 through foreground URLSession transport with the actual browser identity and normally scoped cookies. A local-only LGPL FFmpeg framework remuxes without re-encoding; native playback and duration are checked before the saved file is committed. See `Docs/MEDIA_RUNTIME.md` for supported formats, limits and rebuilding. Other HLS packaging forms continue to need engineering; this is not universal HLS downloading.

Automatic stereo analysis now handles larger, locally varying disparity and partial occlusion using bounded regional comparison and three-frame agreement. It keeps metadata, explicit mono and manual choices authoritative and rejects unrelated/ambiguous images. No decoded image samples are stored in diagnostics.

The native background HTTP 404 resource remains unidentified. A new user-supplied 0.9.0 report on 26 October confirms two foreground MP4 saves completed and local VR playback decoded1440×720. Passive inspection subsequently found all three completed copies in the local catalogue. No new agent-controlled remote-site access was performed. This verifies those fallback attempts, not universal website support; automatic format selection for the second live stream remains unverified because the final snapshot is manual.


## Version 0.4.1 follow-up

The new release adds bounded spherical MP4 metadata detection and preserves browser VR cues for finder results only when the exact resolved page matches. Highest-rendition selection plus automatic VR180/SBS passes on a 3,840×1,920 original calibration stream; a public NASA MP4 passes 2,160×1,080 with automatic VR360/mono. Both real playback popovers have been visually inspected, and shared-action scene tests cover switching quality and formats. These results do not verify Pornhub's current maximum rendition or automatic geometry on its sources. No new site retrieval or login occurred; the earlier user-assisted HLS result remains the live-site evidence. See `TestResults/controls-test-matrix.json`.

## Version 0.4.0 quality work — controlled verification

The app now defaults to Highest, with bounded selection of supported independently playable HLS variants, automatic format detection and a 4,096-pixel per-eye renderer limit. Controlled CC0 tests compare 480×240 with 1,440×720 decoded frames. These tests do not establish the highest quality currently available for the user's Pornhub stream. No fresh site retrieval or agent login was performed. The earlier user-confirmed moving HLS result below remains the live-site evidence; high-resolution playback and automatic identification on that particular source still need user/headset acceptance.

## 25 October 2026 — user-confirmed moving native HLS video

The user supplied a 0.3.6 report on visionOS 27 showing HLS, `decoded-frame-received`, 480×240 decoded video, no native failure and the browser User-Agent option applied. The screenshots showed Screen/VR180 with **Mono** selected while the source contained two side-by-side images. After keeping VR180 and choosing Side by side, the user confirmed one view, then explicitly confirmed **“Pornhub — moving video works”**.

This establishes user-assisted moving native HLS playback for one current Pornhub stream/session in the simulator. It supersedes the older statement that no reported attempt had decoded frames. It does not establish independent agent access to the site, physical stereo depth, every source/quality, paid access, or complete transport/recenter/exit acceptance on that stream. The webpage reported 1440×720 while the native frame was initially 480×240; native quality selection remains a separate check. No site login or content retrieval was performed by the agent.

The immediate split-image issue was layout selection, not a new stream transport failure. Version 0.3.7 makes the three eye layouts visible in the playback panel, calls Mono “Single image”, and adds guidance for doubled/stacked images. It does not infer projection or stereo packing from resolution. Record: `TestResults/live-user-hls-vr-success-0.3.6.json`.

## Historical investigation and earlier failures

## 25 October 2026 automatic HLS and ordinary webpage failure

The user confirmed that **HLS · Automatic quality** is listed, then supplied a 0.3.2 HLS report with unknown dimensions, `failed-at-waiting-for-player`, no playback failure codes, null media HTTP status and no decoded frames. Page HTTP 200 establishes only navigation. The user had navigated away and could not recall the orange error message, so the existing report cannot distinguish the app's preparation timeout from a failed player item without an NSError.

The user subsequently clarified that regular videos fail **inside the webpage too**, and supplied a separate report with `attemptedMedia: null` and `playbackStage: not-attempted`. This must be investigated separately from the native renderer. Neither report establishes a login requirement, expired link, unsupported codec or a website restriction. The redacted reports and the earlier 0.3.2 MP4 report on runtime 27 are retained in `TestResults/live-user-reports-0.3.2.json`.

Version 0.3.3 adds read-only HTML media error/loading states and distinct native termination reasons, and retains bounded numeric player-log codes before cleanup. It does not claim a live streaming fix. A fresh report after pressing the website's own Play button will be needed when the user returns. Existing agent origin refusals have not been worked around.

## 25 October 2026 redacted HLS and MP4 failures

The user supplied two 0.3.1 reports: HLS at 2560×1440 failed at `waiting-for-player`; a 240p MP4 candidate with unknown width failed at `loading-asset`. Both contain `NSURLErrorDomain:-1100` and `CoreMediaErrorDomain:-12938`, null media HTTP status, and zero decoded dimensions. The MP4 report contains page HTTP 200; that is not the media response status. URLs are deliberately omitted, so the source identity and specific failed HLS resource are not independently verified.

The installed Foundation SDK defines -1100 as `NSURLErrorFileDoesNotExist`, consistent with [Apple's missing-file documentation](https://developer.apple.com/documentation/foundation/urlerror/filedoesnotexist). No public Apple definition for -12938 was established. The reports do not prove HTTP 404, expiry, a header requirement, codec failure, DRM or an access restriction. Both attempts failed before immersive rendering. Changing projection or stereo settings cannot correct that preparation failure.

Version 0.3.2 adds a missing-resource hint, lists MP4 candidates first and offers an automatic HLS parent only when its exact URL is supplied by the extractor. This improves supported selection paths but does not establish successful site playback or explain the original failure. See [implementation boundaries](ON_DEVICE_EXTRACTION.md) and `TestResults/live-user-missing-resource-reports-0.3.1.json`.

## 24 October 2026 native retry after 0.3.1

The user supplied a subsequent screenshot with “The native player rejected the stream”. Its exact text maps to AVPlayerItem failing readiness in the installed source, before immersion. The chosen format and error codes are not visible; a Playback details report has been requested. This confirms a failed native attempt in the requested workflow, but does not establish missing headers, a codec defect, URL expiry or an access restriction as its cause. See `TestResults/header-context-native-user-failure-0.3.1.json`.

## 24 October 2026 finder result and 0.3.1 correction

After the requested individual-video finder check, the user supplied a screenshot showing HLS candidates at 2880×1440 and 2160×1080. Both visible entries were disabled with the generic website-request-information message. This establishes returned candidates in that workflow, not native asset readiness, decoded video or projection/layout. The screenshot does not reveal whether the classified header was Origin, Referer, Cookie or Authorization.

Version 0.3.1 corrects the overly conservative treatment of Origin/Referer metadata: it now permits an ordinary native attempt with a warning, without injecting those headers. Cookie/Authorization metadata remains blocked. The actual site may still refuse native requests. No successful Pornhub immersive playback is claimed, and this agent has not fetched the restricted site through another route.

**Result on 23 October 2026: user-assisted testing reached a page with HTTP 200 and exposed MP4/HLS candidates, but native asset loading failed. The user later clarified that ordinary videos work while VR mode fails. No Pornhub video has been successfully decoded or viewed in VisionStream's immersive renderer.**

## User-assisted live result

The user supplied the redacted 0.2.2 report retained in `TestResults/pornhub-user-report-0.2.2.json`. It contains page HTTP 200, no navigation error, an extensionless HTTPS `video/mp4` candidate and an HTTPS HLS candidate. Their dimensions were zero and neither reported encryption. Native preparation stopped at `loading-asset` with `AVFoundationErrorDomain:-11850` and `CoreMediaErrorDomain:-12939`; no media HTTP status or decoded frame was reported.

After a request to try the M3U8 option, the user supplied another report with the same failure and two additional browser-local candidates. Version 0.2.2 did not retain the attempted candidate in its report, so this is not independent proof of which URL failed or that both formats were separately tested. The user then explicitly confirmed that the webpage video itself also fails. This limits attribution: a normal webpage failure is present as well as the native failure, and the cause has not been isolated.

Apple defines `-11850` as [serverIncorrectlyConfigured](https://developer.apple.com/documentation/avfoundation/averror-swift.struct/serverincorrectlyconfigured); its documentation identifies unsupported byte-range requests as one possible cause. The installed AVFoundation header confirms that numeric mapping. No public Apple mapping for `-12939` was verified here. The actual media response, server range headers, account/access state and working website playback remain unverified. No range mismatch, DRM, missing login or regional restriction is asserted as the cause.

Version 0.2.3 adds a specific, qualified server-response error message, clearer MP4/HLS picker labels and a redacted `attemptedMedia` report field. It does not introduce a server workaround, proxy, custom access headers, blob extraction or a website-support claim.

## Earlier tool-access evidence

The research browser could not open the public `https://www.pornhub.com/vr` page or the corresponding official help/blog pages. A direct public HTTPS HEAD request from this environment ended with a connection reset before an HTTP response. That establishes only an access failure from these tools; it does not identify the reason or prove the site is unavailable to a particular user/device.

The publicly maintained [yt-dlp Pornhub extractor source](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/pornhub.py) contains code paths for MP4 media and HLS playlists, as well as DASH. It also documents Origin/Referer requirements for some manifest requests. This is primary evidence about that open-source implementation, **not** verification of the current VR player's formats, publicly exposed HTML sources, or native playback access. Version 0.3.0 now bundles yt-dlp for public source discovery, but disables synthetic cookies (including this extractor's automatic age-verification cookies), geographic-header spoofing and desktop helpers. No browser login is imported. This extractor has not been run against Pornhub in the app; its upstream cookie requirements may prevent it running under these constraints. See [on-device extraction](ON_DEVICE_EXTRACTION.md). No Pornhub compatibility improvement is claimed.

Search-indexed copies of VR help material describe several projections and packed eye arrangements. Those mirrors were not treated as authoritative current documentation, and no assumptions about the active player were taken from them. No live URL was collected in the report, and per-video projection/layout remains unverified.

## What the app can legitimately attempt

The user navigates to the normal site in WKWebView, completes any required access/account/consent process there, and starts an available video. The detector reads ordinary video `currentSrc`, `src`, and source elements. If a direct unprotected HTTPS MP4/HLS candidate is exposed, the app can try it unchanged in AVPlayer with matching WebKit cookies through documented AVFoundation options.

AVFoundation must load the asset, confirm playability without protected content, make its player item ready, and deliver decoded video frames. Only then can native immersive playback be considered demonstrated for that particular source, account/session, region, device, and app version. A format label or a detected candidate alone is insufficient.

## Likely compatibility gates, all unverified for the live VR player

| Gate | Current implementation |
| --- | --- |
| Page can be accessed under WKWebView | User-supplied app report records HTTP 200 after navigation; no special site handling |
| HTML media element exists in an accessible frame/open shadow root | User report contains ordinary DOM video candidates; association with the intended VR player is not independently verified |
| Exposed network URL rather than a blob | MP4/HLS candidates and later browser-local candidates reported; no blob-to-manifest discovery |
| Accepted AVFoundation request context | Asset loading failed; scoped cookies only, no custom Origin/Referer/bearer headers |
| MP4 or HLS with a supported codec | Preparation attempted and failed before readiness; codec unknown |
| No unsupported content protection | Candidates report no encryption; failed asset loading did not establish protection status |
| Equirectangular VR180 or VR360 | Implemented in source; fisheye/equidistant projections unsupported |
| Correct eye packing | Manual mono/SBS/top-bottom and eye swap; live source layout unknown |

If the website requires a particular header, refuses native clients, uses only MediaSource blobs, or restricts native playback, this prototype may be unable to support it within these boundaries. Preserving a browser login does not make an independent AVPlayer request equivalent to the website's request context. Apple's [cookie documentation](https://developer.apple.com/documentation/avfoundation/avurlassethttpcookieskey) also describes restrictions across HLS paths and hosts.

## Manual verification record to complete on Vision Pro

Record the date, device/visionOS/app version, broad access state, candidate type, selected projection/layout, AVPlayer readiness, decoded-frame success, and whether playback/seek/recenter/exit work. Avoid sharing account cookies, signed media URLs, private browsing history or explicit screenshots in bug reports.

The automated investigation did not alter an access state or use authenticated content. The user performed the app interactions; their broad account/access state was not supplied. No region/age/payment restriction was bypassed and no complete website video was downloaded. If the site blocks access or exposes no suitable source, keep the failure result rather than seeking restricted alternate routes.

## Latest live-test attempt

The 23 October 2026 browser-tool attempt was refused by its origin approval gate before navigation. No workaround was used. The updated [live-site test record](LIVE_SITE_TESTS.md) distinguishes these access limits from app compatibility and documents the user-assisted steps and redacted Playback details report in version 0.2.2. No live playback success is claimed.

## Safari comparison and access-policy context

The user subsequently reports that the other tested sites work in Safari while Pornhub does not. The Safari device/version and actual error message were not supplied. This adds a failure outside VisionStream, so normal website access/playback needs to be established before blaming only the native handoff. It does not rule out additional app compatibility limits.

[Aylo's official UK access statements](https://www.aylo.com/newsroom/aylo-upgrades-age-assurance-methods-in-united-kingdom/) say new UK users were restricted from 2 February 2026 while existing age-verified account users retained access, and eligible age-confirmed UK iOS users were welcomed back from 5 May 2026. These are conditional access-policy facts, not a diagnosis of this session. The user's actual location, account/access state and device eligibility are unknown; a London timezone does not establish UK network location. The iOS announcement alone does not establish Mac or visionOS support. The error shown by Safari and the device used are needed to distinguish an access gate from a media/CDN/player failure. No access workaround is proposed.

## Latest clarification: ordinary video works, VR fails

The user clarified: **“The videos work, the vr doesn't.”** Treat this as ordinary video playback working with VR-specific failure, rather than a general website-video failure. The earlier native preparation errors remain valid observations, but neither they nor a generic earlier message establish an age/account restriction as the cause.

Website-controlled VR can involve its own XR/motion setup and a different source from an ordinary preview. VisionStream's current native path does not bridge that website XR session. It opens an exposed accepted source and applies explicitly chosen Screen/VR180/VR360 and independent eye packing. Screen is intentionally a fitted rectangle and cannot demonstrate panoramic VR. The selected source must actually carry the intended VR content; changing view/layout does not create missing stereo information or establish source geometry.

The simulator was observed still on the local calibration page with Screen selected. Computer-control attempts did not visibly change that selection; a user-assisted VR180 + Mono calibration check has been requested. Its outcome and the 0.2.4 native-window interaction remain pending. Physical per-eye presentation and tracking still require a real Vision Pro. No successful live Pornhub immersive playback is claimed.

## 0.3.5 native handoff follow-up

See [the native handoff investigation](NATIVE_HANDOFF.md) for the new empty-attribute and default-selection fixes, supported User-Agent preservation, controlled validation, and the confirmed 0.3.4 HLS preparation timeout. Native Pornhub compatibility remains unresolved.
