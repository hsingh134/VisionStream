# HereSphere library connection and site assessment

Research date: 23 October 2026. VisionStream 0.2.3 includes a functioning read-only **subset** of the HereSphere JSON format. It is not an official HereSphere client. A user-assisted browser-to-native preview test on BaDoinkVR subsequently reached moving immersive playback, with later viewing/control issues, in version 0.2.2; its live HereSphere library integration remains unverified.

## Using the implemented connection

1. Browse the site and complete its ordinary access and sign-in steps.
2. Choose **VR library** in VisionStream's toolbar. Enter the site's published HTTPS HereSphere library or individual-video endpoint, then Connect.
3. If that interface requires POST, expand Connection options and enable **Use POST to read the library**. The request body is exactly `{}`. No authentication payload or library updates are submitted.
4. Open a numbered library entry to see its title and available streams. Index documents commonly supply only URLs, so the app does not fetch every title/thumbnail in advance.
5. Choose a stream and Watch in VR. Its explicit projection and stereo layout are applied; native AVFoundation checks and decoded-frame handling remain the same as for browser-detected streams.

The connector does not automatically discover or construct site-specific endpoints. It does not turn a normal watch-page address into a stream. A separate player login/token may be needed even after browser sign-in; those account interfaces are not implemented. The website remains the place to complete access requirements.

## Implemented format and transport

- A library document contains `access` and `library` groups with `name` and a `list` of video-document URLs. Relative URLs resolve against the requested endpoint. Only HTTPS URLs without embedded credentials are accepted.
- A video document contains `title`, `projection`, `stereo`, `fov`, and `media` groups with `sources`. Sources contain `url` and optional numeric/string `resolution`.
- Access 1 is treated as normal server-supplied access. Access 0 is labelled limited/preview access; only URLs actually returned by the server are shown. Negative or unknown access states fail.
- Supported metadata is equirectangular with explicit 180/360-degree field of view, or `equirectangular360` with absent/360 FOV, crossed independently with `mono`, `sbs`, or `tb`. Conflicting/missing settings, fisheye, unknown layouts and declared passthrough masks are reported as unsupported.
- Only MP4/HLS-compatible candidates reach AVFoundation. No unsupported codec is made playable by the JSON wrapper.
- Connections use an ephemeral URLSession, honest VisionStream User-Agent, bounded chunk reception, a 2 MB response limit and request/resource deadlines. JSON content type is required. No redirect is followed, so an original request's cookies cannot reach a new redirect path or host. Open the final HTTPS address explicitly if needed.
- Cookies come from the existing WKWebView, filtered for the exact requested HTTPS host/path/expiry. Session response cookies are not persisted or imported into WebKit. Each selected media URL receives its own cookie scope check before AVPlayer preparation.
- Requests, results and the last twenty library pages stay in memory. A browser navigation clears library state and cancels pending requests. Cancellation/replacement uses generation ownership so stale results cannot appear later. Query-bearing source URLs are not displayed as stream labels or included in errors.

HSP profile corrections, lens calibration, multipart sequencing, subtitles, scripts, event callbacks, ratings, favourites and server writes are not implemented. The connector is deliberately limited to reading a library and streaming a selected compatible source. No external player/extractor package is linked into the app.

## Evidence and protocol limits

[BaDoinkVR's official HereSphere setup guide](https://badoinkvr.com/help/heresphere) describes a trailer library before login and an account library after login. Its [streaming guide](https://badoinkvr.com/help/vr-porn-streaming) describes browser playback and dedicated player integrations, while recommending downloaded files with Moon Player on Vision Pro. These statements establish supported routes in the site's own instructions, not VisionStream compatibility.

[HereSphere's FAQ](https://heresphere.com/faq/) distinguishes API libraries from streaming direct file links. A [developer response](https://itch.io/t/2354516/web-api) locates its complete API documentation in its Discord channel. That channel was not joined and its current full specification was not obtained. The implemented subset was independently written after inspecting the publicly maintained [XBVR server's JSON structures and read routes](https://github.com/xbapps/xbvr/blob/master/pkg/api/heresphere.go). Those structures establish an interoperable example, not an authoritative promise about BaDoinkVR's current API. No XBVR or downloader implementation was copied or executed.

Direct unauthenticated HTTPS requests to BaDoinkVR's homepage and `/heresphere` ended with connection resets before an HTTP response. See `TestResults/badoink-public-probe.json`. This does not establish the cause, current endpoint availability, required request method, cookie acceptance, or any stream's format. No live video or authenticated account was accessed. No stream was extracted or downloaded by those tool probes. That earlier tool-access result remains unverified for the HereSphere endpoint. A later user-assisted normal browser-to-native video test succeeded, as recorded below; it did not test this JSON connector.

## Other site routes checked

| Site | Public first-party evidence | VisionStream implication |
| --- | --- | --- |
| BaDoinkVR | HereSphere/Prism integration and browser playback; Vision Pro guidance favours Moon Player/downloads | One normal browser-to-native preview played immersively in user-assisted 0.2.2 testing; HereSphere endpoint/account-library compatibility remains unverified |
| VR Bangers | [Vision Pro guide](https://vrbangers.com/devices/apple-vision-pro/) names PLAY'A and browser streaming, with 8K streaming limitations | No PLAY'A adapter is implemented; exposed compatible DOM streams could still be tried |
| VirtualRealPorn | [Vision Pro guide](https://virtualrealporn.com/support/how-to-watch-vr-porn/apple-vision-pro/) offers dedicated MV-HEVC downloads and compatible third-party players | Tagged multiview playback needs a separate path; ordinary packed MP4/HLS remains conditional on actual access and metadata |
| Pornhub | User-assisted page access and candidates were reported, but native and webpage playback failed; see [assessment](PORNHUB.md) | No native playback claim |

DeoVR's separately documented [JSON integration](https://deovr.com/documentation) is another potential adapter. It is not implemented in this change. Website WebXR/Safari support is distinct from handing a stream to this app's AVPlayer/RealityKit renderer.

## Tests and remaining gates

Six new core tests exercise URL/access boundaries, independent projection/layout, unsupported geometry/masks, redaction, malformed data and size/item limits. Four new native tests exercise the actual HTTPS connector, normal browser-established cookies, all twelve MP4/HLS library-to-decoder variants, index/detail/back navigation, limited access, HTTP/JSON/access failures, GET/POST, redirect refusal, known/unknown-length oversize responses, cookie isolation, ignored response cookies, cancellation/replacement and browser-navigation cleanup. The existing native WebKit test also checks that a library handoff pauses a page video with the same exact source.

See [the test report](TESTING.md) and `TestResults/orientation-test-matrix.json` for final executed results. The first byte-by-byte response reader exceeded a native stress-test deadline for a 2 MB body without a Content-Length. Chunk-based bounded reception corrected the issue. The failed initial result bundle is retained as development history; it is not the final result.

Remaining gates are access to a real published site endpoint, verification of its supported authentication contract, a playable authorised source, and physical Vision Pro acceptance. Neither synthetic fixtures nor a successful unsigned archive establishes live-site support or final per-eye presentation.

## Latest live-test attempt

The 23 October 2026 browser-tool attempt was refused by its origin approval gate before navigation. No workaround was used. The updated [live-site test record](LIVE_SITE_TESTS.md) distinguishes these access limits from app compatibility and documents the user-assisted steps and redacted Playback details report in version 0.2.2. This tool-access result is separate from the later user-assisted partial native playback observation below.

## User-assisted BaDoinkVR playback success

On 23 October 2026, the user opened BaDoinkVR in VisionStream 0.2.2 (build 4) on the visionOS 26 simulator, tried an available video and explicitly confirmed **“Immersive video plays after Watch in VR”**. This is a successful normal website/DOM-to-native immersive streaming observation for that selected video. The report is `TestResults/badoink-user-playback-0.2.2.json`. The source format, exact projection/eye packing and broad account state were not supplied; no video URL, title, credentials or explicit imagery was collected. The later control check failed/remains incomplete: the user says controls do not work properly and the whole video is not visible. The individual control, source geometry and cause have not been isolated. This is partial transport/render evidence, not full viewing acceptance. This result does not validate the HereSphere connector against the live service, other content, paid account access or physical Vision Pro presentation.
