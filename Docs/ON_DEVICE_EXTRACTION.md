# On-device stream discovery — 0.3.3

VisionStream embeds CPython 3.14.9 and the pure Python yt-dlp 2026.10.21 package. Extraction and playback run inside the visionOS app. A Mac is required to build/sign/install the app, but is not a playback service. YouTube-specific engineering is deferred at the user's request.

## Use

1. Open an individual public video page in the browser, then choose **Find streams** below it. Alternatively paste an HTTPS page or direct media address into that sheet.
2. Choose **Find streams**. The sheet lists MP4/HLS candidates without displaying their signed URLs. Unsupported entries include a reason.
   Usable MP4 entries appear first, ordered by available reported height/width. When width is unknown, a label such as MP4 · 1440p still exposes the reported height; no width, projection or eye layout is inferred. **HLS · Automatic quality**, when present, opens the parent playlist supplied by the extractor so AVPlayer can select a variant. Individual HLS variants remain available. None of these labels guarantees website acceptance.
3. Set **View** and **Layout** below the browser before playback. Use Screen + Mono for an ordinary preview; choose VR180/VR360 and eye packing only from documented source information.
4. Choose **Watch in VR** beside a supported candidate. AVFoundation must still load it successfully. Use the native Playback window to pause, seek or return to the webpage.

This feature discovers sources for streaming; it does not save whole video files. Python may fetch page/manifest metadata and small probes. AVFoundation handles streaming and its normal buffering.

## Implementation

`OnDeviceExtractor` serialises work on a background Dispatch queue. An Objective-C bridge initialises isolated CPython with bundled resources, releases the initial GIL and acquires it per job. Objective-C ARC and a queue work-item autorelease pool retain returned strings through Swift conversion. The runtime remains alive for the app process; no finalisation races with outstanding work.

`visionstream_resolver.py` uses `YoutubeDL.extract_info(download=False)` with downloads, persistent cache, plugins, external JavaScript runtimes and remote code components disabled. An explicit single-stream format selector avoids yt-dlp's default FFmpeg capability probe. A nonexistent bundled helper location also disables FFmpeg discovery; constructing a subprocess is blocked on visionOS. Separate video/audio merging, transcoding and desktop helpers are unavailable.

Only HTTPS MP4/M4V or HLS candidates are offered, capped at 32, with a bounded Swift payload and dimensions. DRM declarations, unsupported projections, separate-audio MP4 variants and reported authentication headers disable the relevant entries. Origin/Referer-only metadata produces an advisory while allowing an ordinary native playback attempt. Header names and values are not forwarded to the Swift player; only a fixed advisory code is returned. Layout and projection remain independent user choices; dimensions do not imply VR180 or stereo. The same existing AVPlayer/Metal/RealityKit path handles accepted results.

Cancellation clears UI state immediately, skips cancelled queued jobs and discards late results. A running Python call finishes under its per-request network timeouts; there is not yet a hard whole-job deadline. Python exceptions and downloader logs are suppressed because they can contain private URLs. Only fixed, redacted errors reach the UI. Results remain in memory and are cleared on navigation or sheet dismissal.

## Boundaries

- The extractor has a separate HTTP session. It does not import WKWebView/Safari cookies, passwords, subscriptions or age-verification state. Logging into the browser does not authenticate Python extraction.
- Geographic-header spoofing is disabled. Extractors' shared synthetic-cookie setter is a no-op, including for age-verification or access-state cookies; ordinary server-issued cookies still work. Normal public requests continue without those assertions, and the server decides whether access is available. An extractor that depends on a synthetic cookie may fail. This prevents upstream convenience defaults from silently changing the user's access state.
- Public source resolution does not verify AVFoundation/CDN acceptance. Expiring URLs, unsupported codecs, HLS variants and browser-bound delivery can still fail.
- Candidates reporting Cookie or Authorization headers remain disabled. Origin/Referer-only candidates show a warning and can be tried without those headers. A declared header is not proof that the server enforces it. The app does not manufacture or inject these headers; AVFoundation readiness and decoder checks still determine whether native playback succeeds.
- Playlists/galleries are rejected. A generic page with multiple embedded videos can be classified as a playlist even if one is the desired video.
- Arbitrary webpage JavaScript is not executed by the extractor. Extractors requiring external JavaScript, impersonation libraries or helper binaries may fail.
- Mesh/cubemap/fisheye formats are not converted to equirectangular content. Audio/video are not merged.
- No site restriction, DRM, payment or authentication bypass is implemented. Pornhub support is **unverified** in this version. The app's embedded extractor is not a workaround for this agent's refused browser access.

## Dependencies and rebuilding

`Vendor/` is included in the source package. To reproduce it from checksum-pinned upstream archives:

```sh
python3 Scripts/prepare_embedded_extractor.py
python3 Scripts/generate_project.py
```

The setup script verifies SHA-256 before installing dependency files. It makes one quoted-filename fix to BeeWare's MIT-licensed build helper for workspace paths containing spaces. The Xcode build phase copies the standard library and packages, converts native Python extension modules into signed frameworks and embeds the correct architecture. Script sandboxing is disabled for this app target because the pinned helper generates those framework paths dynamically. No runtime package installation or self-update occurs.

See `Vendor/dependencies.lock.json`, `Vendor/Python-VERSIONS.txt`, [third-party notices](../THIRD_PARTY_NOTICES.md) and `Licenses/EmbeddedRuntime.txt`. Python's runtime embeds OpenSSL; encryption export/distribution classification has not been completed. The earlier unconditional non-exempt-encryption declaration was removed. Personal device development signing is the current installation path; App Store submission is not validated.

Primary references: [yt-dlp embedding API](https://github.com/yt-dlp/yt-dlp#embedding-yt-dlp), [BeeWare visionOS runtime](https://github.com/beeware/Python-Apple-support), [BeeWare integration instructions](https://github.com/beeware/Python-Apple-support/blob/main/USAGE.md), and [Python subprocess platform availability](https://docs.python.org/3/library/subprocess.html).

## Version 0.3.1 header-context correction

The user supplied a finder screenshot showing HLS candidates at 2880×1440 and 2160×1080, with Watch in VR disabled by the generic website-request-information message. Version 0.3.0 treated any Origin/Referer metadata as a mandatory playback requirement. That was too strong: those headers may be supplied as a default, and metadata alone does not establish a native request failure.

Version 0.3.1 separates an advisory from an unsupported feature. Origin/Referer metadata no longer disables Watch in VR, and the warning states that playback is tried without it. Authorization/Cookie metadata, DRM and unsupported formats remain blocked. No custom headers, proxy or extraction access workaround was added. A real media server can still refuse the native request; this change does not establish Pornhub playback support.

The controlled `/header-free/` test route rejects Origin, Referer, Authorization and Cookie on MP4, HLS manifests and segments. Resolver tests verify that header values never leave Python; core tests verify advisories stay distinct from blocking errors and cannot display private values. A native renderer regression opens MP4 and HLS candidates with the advisory against that route.

All **53 native Release tests pass on visionOS 26.0 and 27.0**, with zero failures/skips. Both header-free formats reach 1024×512 decoded renderer frames. **31 core methods / 880 assertions**, 31 Swift Package tests, 9 Python resolver tests and 8 HTTPS fixture tests pass. Evidence is in `TestResults/header-context-test-matrix.json` and the `header-context-*` logs. The visionOS 26 run used a separate disposable simulator; its test CA was removed with that simulator afterwards. These results verify the fallback mechanism on controlled media, not acceptance by a production website.

Simulator Release and unsigned Vision Pro Release archive builds pass. Version 0.3.1 build 8 is installed and launched in **VisionStream visionOS 26** for a user-assisted retry. The installed Python adapter matches source; live-site native playback and physical-headset operation remain unverified.

## Version 0.3.2 resource errors and automatic HLS selection

The user supplied redacted 0.3.1 reports for a 2560×1440 HLS attempt and a separate 240p MP4 attempt. Both failed with `NSURLErrorDomain:-1100` and `CoreMediaErrorDomain:-12938`, with no decoded frames. HLS failed at player readiness; MP4 failed while loading the asset. No actual HTTP status was recorded. Apple's SDK maps -1100 to `NSURLErrorFileDoesNotExist`; [Apple's documentation](https://developer.apple.com/documentation/foundation/urlerror/filedoesnotexist) describes a missing file. The app does not infer HTTP 404, expired links, authentication, DRM or a codec defect from these codes. A public Apple mapping for the CoreMedia code was not established. See `TestResults/live-user-missing-resource-reports-0.3.1.json`.

The new missing-resource message suggests resolving fresh sources and trying another offered format without asserting why the resource was missing. MP4's separate failure is retained; placing MP4 first is a selection improvement, not evidence that it fixes the site.

The resolver previously returned each HLS variant's `url` but omitted its supplied `manifest_url`. It now also offers that published parent as **HLS · Automatic quality**, deduplicated by exact URL and marked with unknown dimensions. Associated video-format restrictions and header advisories are retained when variants share a parent. It does not guess an endpoint, copy a child's token into another URL, rewrite playlists or discover an alternate restricted route. [Apple's HLS sample](https://developer.apple.com/documentation/avfoundation/using-avfoundation-to-play-and-persist-http-live-streams) uses the master playlist URL for playback. This can preserve native adaptive selection and audio-group context; it is not a diagnosis or verified fix for the reported missing-resource failure.

Usable MP4 candidates are listed before automatic HLS and individual variants, so many high-resolution HLS entries do not crowd a separate MP4 out of the 32-result cap. Playback remains explicitly chosen by the user; no automatic retry or hidden fallback starts.

All **55 native Release tests pass on visionOS 26.0 and 27.0**, with 110 successful executions and zero failures/skips. The controlled parent playlist reaches 1024×512 decoded frames on both runtimes, alongside individual HLS, MP4 and the existing NASA extraction checks. **33 core methods / 894 assertions**, 33 Swift Package tests, **13 Python resolver tests** and **9 HTTPS fixture tests** pass. `TestResults/adaptive-test-matrix.json` and the `adaptive-*` logs record these results. The tests establish the implemented selection path, not compatibility with the user's failing site sources.

Simulator Release and unsigned device archive builds pass. Version 0.3.2 build 9 is installed in **VisionStream visionOS 26**, with the bundled resolver verified against source. The automatic-playlist user retry and physical Vision Pro testing remain pending; no new successful live-site playback is recorded.

## Earlier 0.3.0 validation — 24 October 2026

- The user confirmed that Find streams opens the **Find a video stream** sheet in the visionOS 26 simulator. This verifies the sheet-opening interaction only; extraction results and playback through that UI still need manual acceptance. See `TestResults/yt-dlp-ui-acceptance.json`.

- **51 native Release tests pass on visionOS 26.0 and 27.0**, 102 successful executions, zero failures/skips. See `TestResults/yt-dlp-ondevice-test-matrix.json` and the corresponding per-runtime logs/summaries.
- The embedded runtime resolves the [public NASA black-hole 360° MP4](https://svs.gsfc.nasa.gov/14576/) and streams it through AVPlayer, the Metal eye-processing path and RealityKit texture resources. Both simulators produced 2160×1080 decoded frames with the renderer enabled, explicitly configured as VR360 + Mono. Tests mute audio. This is a **direct media extraction test**, not successful extraction from a production HTML video page or a visual stereo acceptance check.
- The three new non-network tests cover bundled runtime startup/input rejection, navigation cleanup and cancelled-result suppression. All existing native MP4/HLS, WebKit, library, playback and GPU tests remain passing.
- **30 Swift core tests / 873 assertions**, 30 Swift Package tests and **8 Python resolver unit tests** pass. Unit tests cover formats, restrictions, bounds, privacy and helper/download configuration.
- The unsigned physical Vision Pro Release archive builds. Physical headset execution, signing and performance remain untested.
- Initial integration exposed an Objective-C ownership crash; enabling ARC and correcting the pool lifetime fixed it. The next public extraction test exposed FFmpeg probing through unsupported subprocesses; explicit single-stream selection and disabled helper discovery fixed it. Failed result bundles are retained locally; final runs above pass.
- One visionOS 27 run also exceeded the existing five-second browser-startup test waits while WebKit logged slow process launches. This is retained as `TestResults/yt-dlp-webkit-timeout-*`; startup timing remains a simulator reliability limitation.
- A later full run exposed an existing paused-layout race: geometry was rebuilt before an asynchronously scheduled texture upload captured its layout. A layout change in that gap could leave the old Screen aspect with new eye packing. Geometry now rebuilds alongside the layout snapshot in the upload task; the native regression repeats paused mono/SBS/top-bottom reallocations. The failing run is preserved in `TestResults/yt-dlp-screen-race-*`.

Public-page probes did not establish a supported webpage: MDN and the W3 media demo returned unavailable; the W3Schools tutorial was classified as a multi-video playlist and its entries declared Referer headers. These outcomes are not site-playback success. No adult site was fetched in these extractor tests, and no new YouTube tests were performed.

To repeat:

```sh
python3 -B -m unittest discover -s Tests/Extractor -v
sh Scripts/test_core.sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project VisionStream.xcodeproj -scheme VisionStream \
  -configuration Release -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath DerivedData/OnDeviceApp CODE_SIGNING_ALLOWED=NO build-for-testing
python3 Scripts/run_visionos_tests.py --simulator YOUR_SIMULATOR_ID \
  --build-root "$PWD/DerivedData/OnDeviceApp" --public-extraction
```

Boot a dedicated simulator first. The runner uses a temporary test CA only in that simulator's system trust store for the existing CC0 fixture tests. The public extraction test uses certifi's normal CA bundle without TLS exceptions. If public networking is unavailable, omit `--public-extraction`; that one test will then skip and must not be counted as a network pass.

## User retry after 0.3.1 installation

The user supplied the native-player-rejected message after the retry request. In the current code that exact message is emitted when AVPlayerItem fails readiness, after the initial asset checks; immersive rendering has not started. The screenshot does not show the attempted format, HTTP status or numeric error codes. Playback details has been requested before attributing the failure to headers, expiry, authentication or codecs. See `TestResults/header-context-native-user-failure-0.3.1.json`. Controlled test passes do not establish live-site success.

## Version 0.3.3 reliability corrections

Deduplication retains an HLS MIME type for a supplied parent even if the same URL was first classified as MP4. Boolean dimensions become integer zero rather than invalid Swift integer fields. Known-height sources no longer tie at zero pixel area merely because width is absent: this previously could leave 240p first in ascending extractor order. Standard MIME whitespace/parameters are normalized in native candidate validation and reporting. These are contract/selection corrections, not proof that a live source now plays. The automatic HLS retry in 0.3.2 failed, and the user also reports regular webpage video failure; see the live test record and [reliability review](RELIABILITY_REVIEW.md).

## 0.3.5 playback context

The native handoff can now preserve the actual WebKit User-Agent through Apple's public asset option. This value comes from the browser, not extractor metadata; synthetic identities and extractor header dictionaries remain excluded. Scoped cookies still use their documented option. Origin/Referer and cross-host/path authentication requirements remain limitations. See `NATIVE_HANDOFF.md`.
