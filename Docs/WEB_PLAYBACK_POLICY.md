# Webpage loading investigation — 25 October 2026

## Live observation

The user supplied a 0.3.3 report from visionOS 27 with a website-player loading symbol, page HTTP 200, no native attempt, and four detected source entries. Every entry had MediaError code 0, networkState 0 (NETWORK_EMPTY), readyState 0 (HAVE_NOTHING), paused true and zero dimensions. The site name was not supplied. The entries may include multiple sources for one element; they are not necessarily four visible players.

These states mean the detected elements have no media loaded/initialized at the observation time. They do not prove a CDN failure, codec error, DRM, authentication failure, or that the visible loading indicator belongs to a particular detected element. There may also be a website script, source-selection or input problem. The page HTTP 200 only establishes that the document loaded.

## Reproduced application issue and change

BrowserModel explicitly required a direct user gesture for **all** media (`mediaTypesRequiringUserActionForPlayback = .all`). WebKit distinguishes a play call directly inside a gesture handler from a later asynchronous call. A site can therefore lose permission while awaiting player initialization after its Play button was pressed.

A controlled page starts an unmuted H.264/AAC video from its own timer, without any injected play call or artificial JavaScript gesture. On the old production configuration, the new regression fails because play rejects with NotAllowedError. An explicitly restrictive WKWebView remains as a negative control in the passing test. The production configuration now uses the supported empty media-type set, allowing the website to manage when media starts. This also permits website autoplay, including audio; no artificial clicks, source replacement, header injection, cookie changes or access checks are involved.

Version **0.3.4 build 11** contains this change. It does not claim to repair every website loading failure. Existing native streaming and rendering behavior is unchanged.

## Validation and evidence

The final 0.3.4 Release suite passes on both visionOS 26.0 and 27.0: **58 passes, zero failures and two explicit optional skips per runtime**. The new delayed MP4/HLS presented-frame test passes on each runtime. The 12 HTTPS fixture tests also pass. The simulator build-for-testing and unsigned device archive succeed. Both user simulators have the matching 0.3.4 build installed and were left closed for reopening; stored WebKit/Cookies file counts are unchanged. Live login restoration is not verified.

- `web-policy-before-native-tests.txt`: expected regression failure on the old production policy; negative control rejects as expected.
- `web-policy-26-*` and `web-policy-27-*`: current Release regression results, including the policy comparison and presented frames for delayed MP4/HLS playback.
- `web-policy-fixture-tests.txt`: HTTPS fixture tests, including unmuted/delayed page setup and supported media routes.
- `web-policy-build.txt` and `web-policy-device-build.txt`: simulator build-for-testing and unsigned device archive.
- `web-policy-test-matrix.json`, `web-policy-installation.json`: final test/install evidence.

The test checks `requestVideoFrameCallback` dimensions and presented-frame count, rather than accepting only a resolved play promise or audio-clock progress. Page polling verifies the committed document path so a previous document's outcome cannot satisfy the HLS test.

The user subsequently confirmed **“It plays”** after the 0.3.4 reopening/website Play check. This verifies webpage playback on the page they tested; the site name and runtime were not reconfirmed. The report is retained in `live-user-webpage-playback-0.3.4.json`. Native playback through Watch in VR is the next separate acceptance check. General website support, live Pornhub native compatibility and physical headset behavior remain unverified.

## Sources

- [Apple: mediaTypesRequiringUserActionForPlayback](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/mediatypesrequiringuseractionforplayback)
- [WebKit: direct gestures and media playback policies](https://webkit.org/blog/6784/new-video-policies-for-ios/)
- [HTML: media network states](https://html.spec.whatwg.org/multipage/media.html#network-states)
