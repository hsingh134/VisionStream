# Native handoff investigation — 25 October 2026

## Latest result

The user has now confirmed moving native HLS video from Pornhub in 0.3.6 on the visionOS 27 simulator. The supplied report contains decoded 480×240 frames with no failure. Choosing VR180 alone left Mono selected, showing both packed eye images; selecting Side by side corrected this, and the user confirmed moving video. See [the current assessment](PORNHUB.md) and `TestResults/live-user-hls-vr-success-0.3.6.json`. This is a user-assisted single-stream result, not broad website or physical-headset certification. The earlier format-hint hypothesis was not shipped: this reported stream already decodes, and the confirmed split issue is its selected layout.

## Earlier live evidence

The user confirmed webpage playback after 0.3.4. A subsequent Pornhub screenshot and report showed an attempted extensionless MP4 with no dimensions, readyState 0, paused true, and networkState 3 (NETWORK_NO_SOURCE). Native loading failed with AVFoundation -11850 / CoreMedia -12939. A separate HLS candidate reported 1280×720, readyState 4, unpaused and error code 0. The default picker had selected the inactive MP4.

The user then actually selected the HLS in 0.3.4. Native preparation **still timed out** at waiting-for-player, item status unknown, no decoded dimensions, and eight CoreMedia -12938 log events. No HTTP status was captured. Do not infer a 404, DRM, authentication or codec diagnosis from that numeric code. The source-selection correction does not by itself solve this separate HLS failure.

Evidence: `TestResults/live-user-native-source-selection-0.3.4.json` and `live-user-hls-native-timeout-0.3.4.json`. URLs and titles are omitted.

## 0.3.5 changes

1. **Ignore empty declared media attributes.** WebKit resolves an empty or whitespace-only src attribute to the document URL. A real WKWebView regression exposed five candidates where only one valid MP4 existed, including the HTML document mislabelled as MP4/HLS. The detector now checks the raw src attribute before using its resolved fallback URL. Nonempty currentSrc remains authoritative; blob fallbacks are not advertised as direct URLs. The specific Pornhub MP4 URL is redacted, so this generic defect has not been independently confirmed as its source.
2. **Choose a prepared direct candidate by default.** Among direct MP4/HLS candidates, prefer prepared healthy video, then playing video and known dimensions. This chooses the active 1280×720 HLS over the empty MP4 in the reported state. Explicit picker selections still take precedence. If no direct candidate exists, an unsupported/blob entry remains visible with its explanation. Readiness in WebKit is not proof of native playability or of whether a video is the main feature.
3. **Preserve the actual WebKit User-Agent using Apple's public AVURLAssetHTTPUserAgentKey.** Read navigator.userAgent in the isolated client world, bound it to 1024 bytes and reject control characters before supplying the documented asset option. No invented Safari/device identity or extractor-provided header is used. The report records only browserUserAgentApplied, never the value. This boolean confirms that the option was supplied; it does not verify server receipt for a live source. Existing scoped cookie handoff remains. This is a supported context-preservation improvement; it is not an established explanation or verified fix for Pornhub's timeout.

The app does not add arbitrary headers, rewrite playlists or signed links, proxy media, import browser credentials into Python, or bypass website controls. Cross-host/path cookie and Origin/Referer requirements remain compatibility limitations. Native decoding, genuine stereoscopic VR rendering and physical headset acceptance are separate gates.

## Validation

Final Release suites pass on visionOS 26.0 and 27.0: **61 passes, zero failures and two explicit optional skips per runtime** (122 passes total). The optional public NASA and private-sample tests were not enabled in this release run. The 35 core methods / 932 assertions, 35 Swift Package tests, 13 HTTPS fixture tests and 11 JavaScript tests pass. The simulator test build and unsigned device archive succeed. Both user simulators have the matching 0.3.5 build installed; app/build/test source hashes remain unchanged after validation.

Two browser-navigation checks missed their five-second deadlines in both initial visionOS 27 runs; the raw failures are retained as `source-selection-cold-navigation-failure-27-*` and `source-selection-repeat-navigation-failure-27-*`. These tests were using detached WKWebViews. They now attach the views to the visible window, matching production, and allow 15 seconds for document navigation as the other WebKit integration tests do. Their targeted rerun passes. No claim is made that a live website failure had the same cause. The final matrix, rather than the earlier attempts, describes release validation.

- Empty-attribute regression was observed failing on the old detector in an actual visionOS WKWebView. Its property getters resolved the placeholders to the document address. The corrected detector keeps only the valid MP4.
- Default-selection core cases reproduce the report's inactive MP4, active HLS and active blob alternatives, and check paused, failed, larger and absent alternatives.
- An HTTPS fixture registers the actual WebKit request identifier in server memory. Native MP4, HLS playlists and segments must use that same identifier or the server rejects them. A native test checks decoded pixel buffers through this gate, without logging the identifier. A control-character input is rejected and omitted from native options.
- Current test/build/install results are recorded in `TestResults/source-selection-test-matrix.json`, `source-selection-*-native-tests.txt`, `source-selection-build.txt`, `source-selection-device-build.txt` and `source-selection-installation.json`.

Live Pornhub playback in the native player remains unresolved until a user-assisted 0.3.5 check succeeds. A prepared webpage HLS source and successful controlled tests are not a substitute for that check.

Apple documents [User-Agent](https://developer.apple.com/documentation/avfoundation/avurlassethttpuseragentkey) and [cookie options](https://developer.apple.com/documentation/avfoundation/avurlassethttpcookieskey) separately. The SDK headers explicitly describe each option and its visionOS availability.
