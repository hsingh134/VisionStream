# Feasibility research — 23 October 2026

## Apple frameworks

Apple's visionOS 26 media APIs can present tagged projected media and immersive/spatial formats through AVKit and RealityKit. AVPlayerViewController is Apple's preferred system playback interface, and VideoPlayerComponent supports portal, progressive and full immersive modes. These are appropriate for content carrying supported media metadata. They do not establish that an arbitrary website's packed video URL is a tagged immersive asset. [Apple's playback overview](https://developer.apple.com/documentation/technologyoverviews/immersive-media/), [AVKit guidance](https://developer.apple.com/documentation/avkit/adopting-the-system-player-interface-in-visionos), [WWDC25 media session](https://developer.apple.com/videos/play/wwdc2025/296/).

WKWebView provides the native browser surface requested here. WKUserScript can run in all frames and a dedicated content world. This isolates our JavaScript namespace while retaining DOM access. Each frame reports its own HTML video metadata; no cross-origin document traversal is required. Actual website behaviour under WKWebView, cookie policy and access prompts still needs device testing. [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview), [isolated user scripts](https://developer.apple.com/documentation/webkit/wkuserscript/init(source:injectiontime:formainframeonly:in:)).

AVFoundation supports HTTP streaming through AVURLAsset and AVPlayer. Playability and protected-content status must be loaded, and even a playable asset can require authorisation. This project probes those properties and observes AVPlayerItem readiness; it never equates a file extension with successful playback. [Asset initialisation options](https://developer.apple.com/documentation/avfoundation/avurlasset-initialization-options), [protection property](https://developer.apple.com/documentation/avfoundation/avpartialasyncproperty/hasprotectedcontent).

WebKit and AVFoundation have separate cookie handling. The documented AVURLAssetHTTPCookiesKey supplements asset cookies. Apple specifically notes HLS requests can span multiple hosts/paths and only cookies applicable to the initial asset URL may be sent. Full browser authentication therefore cannot be guaranteed by copying cookies. [WebKit cookie store](https://developer.apple.com/documentation/webkit/wkhttpcookiestore), [AVFoundation cookie semantics](https://developer.apple.com/documentation/avfoundation/avurlassethttpcookieskey).

RealityKit supports dedicated per-eye image textures through a Camera Index Switch shader graph. LowLevelTexture permits frequent Metal updates coordinated with RealityKit. Combining these lets ordinary frame-packed decoded video be mapped to a custom hemisphere/sphere, with native SwiftUI controls. This is the selected prototype architecture. [Apple stereo image sample](https://developer.apple.com/documentation/visionos/displaying-a-stereoscopic-image-in-visionos), [LowLevelTexture](https://developer.apple.com/documentation/realitykit/lowleveltexture), [GPU replacement synchronisation](https://developer.apple.com/documentation/realitykit/lowleveltexture/replace(using:)).

Apple also demonstrates stereoscopic video using AVSampleBufferVideoRenderer/VideoPlayerComponent, and a full custom Metal engine can use Compositor Services. Both add complexity for this prototype. We use AVPlayer's timing and RealityKit's existing stereo scene renderer, avoiding a custom display compositor. [Stereoscopic video sample](https://developer.apple.com/documentation/realitykit/rendering-stereoscopic-video-with-realitykit), [Compositor Services](https://developer.apple.com/documentation/compositorservices).

## Stream limitations

| Website media behaviour | Prototype outcome |
| --- | --- |
| Exposed HTTPS MP4, playable codec, accepted request | Candidate; AVPlayer must prove readiness and deliver frames |
| Exposed HTTPS HLS | Candidate; manifest, segments, codecs and access must all work |
| Cross-origin CDN URL | Readable DOM metadata does not guarantee native access; server may reject it |
| Cookie-based session | Transfer uses public APIs and original cookie scope; only partial parity is possible |
| Expiring signed URL | Current URL is used unchanged; reacquire through the normal page after expiry |
| Required Origin/Referer or custom bearer header | Unsupported when normal AVFoundation requests are rejected |
| `blob:` / MediaSource / WebRTC / encrypted browser state | No handoff; no extraction of underlying state |
| DRM or encrypted-media report | Rejected; no licence integration or decryption |
| Closed shadow root or inaccessible media element | May not be detected |
| Fisheye / equidistant / cubemap | Unsupported projection even if decoding succeeds |
| MV-HEVC / APMP / Apple Immersive Video | No dedicated tagged-media route in this prototype |

Codec, bitrate, resolution, HDR and hardware limits also matter. The generated H.264/AAC fixtures exercise a conservative baseline. Modern visionOS APIs do not imply compatibility with every codec/container or with every website.

## Open-source assessment

| Project | Observed scope | Licence | Decision |
| --- | --- | --- | --- |
| [OpenImmersiveLib](https://github.com/acuteimmersive/openimmersivelib) | Swift 6.2 / visionOS 26 spatial and immersive player library | [MIT](https://github.com/acuteimmersive/openimmersivelib/blob/main/LICENSE) | Useful future candidate for tagged immersive media; no dependency added |
| [NutshellPlayer](https://github.com/halftan/NutshellPlayer) | Vision Pro VR180 SBS, Swift/Metal/ShaderGraph with an FFmpeg fork | [GPL-3.0](https://github.com/halftan/NutshellPlayer/blob/main/LICENSE) | Reviewed at architecture/licence level; no code copied or linked |
| [RealityKitSideBySideRenderExample](https://github.com/KhaosT/RealityKitSideBySideRenderExample) | RealityKit video output + dynamic texture and stereo material example | [Apache-2.0](https://github.com/KhaosT/RealityKitSideBySideRenderExample/blob/main/LICENSE) | Adapted the small USD shader graph with licence and attribution; new streaming/render lifecycle code |
| [VR180-Web-Player](https://github.com/Verdi/VR180-Web-Player) | WebXR/Three.js 180 SBS MP4 player; not a native visionOS player | [Unlicense](https://github.com/Verdi/VR180-Web-Player/blob/main/LICENSE) | Reference for the packed-format distinction; no code or sample media included |

These assessments are based on the repositories and their stated licences, not runtime tests or a full dependency audit. The app includes only the attributed Apache material adaptation. The external players' bundled example footage was not treated as openly licensed merely because their code is open source.

## Feasibility conclusion

A prototype can legitimately stream **exposed, unprotected, accepted MP4/HLS sources** into a custom immersive renderer without creating a video download file. The project now compiles against the real visionOS SDK for simulator and device, and Debug and Release native tests on both visionOS 26 and 27 demonstrate HTTPS MP4/HLS decoding, scoped cookie handoff, WebKit detection, material loading and Metal eye splitting. These results do not establish arbitrary website compatibility or physical per-eye presentation. Pornhub VR compatibility remains unproven. The app reports unsupported sources instead of using extraction or access-control workarounds; physical Vision Pro validation remains an essential gate.
