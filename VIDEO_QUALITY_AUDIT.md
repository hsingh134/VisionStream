# VisionStream video-quality audit

Version 0.16.0 (39), 1 November 2026. Baseline: 0.15.0 (38), commit `583fe1c30437bc3fc291703b615ff8b7a05eee9d`, checkpoint tag `audit/video-quality-0.15.0-baseline`.

The changes preserve more decoded precision, correct filtering, retain large mono panoramas, improve geometric accuracy and add reversible picture controls. They do not establish that Vision Pro now looks better than Quest. That comparison needs the same source/rendition, viewpoint, brightness and a physical headset. No physical visual acceptance is claimed.

## 0.16.1 follow-up: selected source versus website offerings

The owner’s two physical 0.16.0 reports decoded 1440 × 720 SBS without texture downscaling; each inspected playlist offered one rendition. This is 720 × 720 per eye and does not establish the website maximum. Selecting a separate finder entry labelled 1440p subsequently produced a user-confirmed **2880 × 1440 decoded header**: four times the packed pixels, or 1440 × 1440 per SBS eye. This observation is not a sustained frame-rate or subjective-quality measurement.

0.16.1 (40) ranks usable finder entries by reported height, then width, so a 1440p entry with unknown width no longer loses to 2160 × 1080. Try highest resolution chooses the highest reported usable entry; availability and native decoding still require checking. Highest inside the player applies to the selected source’s playlist, not every alternate source on the website. Return to page/Open website controls now keep that page inline until manual Watch, automatic-VR resume or navigation/reload.

History now exports memory as numeric bytes rather than interpreting UInt64 bits as Double. HLS source metadata samples actual player-item/asset tracks with bounded retries; manifest declarations remain separately labelled and cannot substitute for decoded-track metadata. Final native suites pass **223 tests with 12 optional skips on each runtime**; final mounted scenes pass **7 scenarios / 72 checks each**. The earlier offscreen WebKit back-stack failure remains recorded separately. Existing 0.16.0 image/GPU benchmark values below were not remeasured or relabelled as new measurements.

## Original architecture

```mermaid
flowchart LR
    A[WKWebView / stream finder / saved library] --> B[Media candidate and legitimate request context]
    B --> C[Quality selection: supported MP4 or HLS]
    C --> D[AVPlayer: network, demux, decode, audio clock]
    D --> E[AVPlayerItemVideoOutput: 8-bit BGRA]
    E --> F[CVMetalTextureCache: no full-frame CPU copy]
    F --> G[Metal: crop eyes, filter encoded RGB, then linearize]
    G --> H[Two RGBA16F eye textures, 4096 dimension cap]
    H --> I[Camera-index material on screen / inward hemisphere / sphere]
    I --> J[RealityKit eye rendering and system compositor]
```

The app already uses AVFoundation, WebKit, Metal, RealityKit and ARKit together. It does not use a custom VideoToolbox demux/decode clock. Highest-quality HLS selection already inspects available renditions; it is separate from eye packing, projection and picture processing. The native player keeps its own audio/timing/network implementation. Downloads use the existing MP4/offline-HLS/remux recovery paths and do not feed a re-encoded copy into streaming playback.

## Diagnosed losses and decisions

| Finding in 0.15 | Implemented change | Scope of evidence |
| --- | --- | --- |
| Requesting BGRA8 discards precision beyond 8 bits before RGBA16F storage | Request wide-colour, linear Display P3 RGBA half-float from AVFoundation; verify actual frame attachments; convert P3 to linear sRGB in the crop pass | Actual native decode tests; synthetic GPU ramp comparison |
| Bilinear sampling occurred before inverse gamma | Filter known-linear input; untagged SDR fallback linearizes each contributing texel before interpolation | Production GPU kernel/readback: 0.214 versus correct 0.5 black/white average |
| Mono used two eye resources and capped wide panoramas at 4096 | Mono shares one resource; preserve up to 8192 dimensions subject to an explicit descriptor budget | Native 8192 × 4096 decode and bound 8192 × 4096 shared texture |
| Coarse panorama tessellation adds UV interpolation error | 256 × 128 for VR180; 512 × 128 for VR360 | Analytic reference using actual mesh triangles; approximately fourfold lower interpolation error |
| A 10 m shell can add unwanted geometry disparity to prerecorded stereo | Follow translation with a 1000 m skybox-distance shell; preserve recenter/tilt orientation | Geometry calculation and renderer bounds/scene checks; physical depth/comfort remains to test |
| Implicit material sampling and PBR surface configuration | Bind explicit samplers; use documented unlit ShaderGraph surface, without its post-process tone map | Successful native material/texture binding and scene rendering; final sampler decisions remain RealityKit-owned |
| No per-stage quality evidence or immediate A/B mode | Picture modes, paused-frame A/B, diagnostics overlay and report | Native and mounted-scene integration tests |

The old cap **did not reduce standard 8192 × 4096 side-by-side VR180**: each eye was already 4096 × 4096. Its measurable impact was on large mono panoramas and wider packed-eye formats. A 1440 × 720 SBS source still has only 720 × 720 per eye (about 4 source pixels/degree over 180°); these changes cannot manufacture missing detail.

## Corrected colour and texture path

An actual lossless Main10 neutral ramp additionally verifies decoder/output gradation: both simulator runtimes retain **all 1,024 distinct source steps** in the half-float red channel at native dimensions. This complements the GPU-only precision benchmark; it does not expose or certify every internal AVFoundation stage or other source codec.

`AVPlayer → actual RGBA16F buffer + colour attachments → CVMetalTextureCache → linear eye crop/gamut conversion/optional enhancement → RGBA16F eye texture(s) → explicit material sampler → unlit RealityKit surface → system compositor`.

No extra full-frame CPU copy, application encode pass, sharpening upscale or custom decoder was added. Sparse image-layout analysis samples a bounded 128 × 64 luminance grid; it does not copy the full frame. The GPU input IOSurface and Core Video texture remain leased until command completion, including during teardown.

Apple documents wide-colour half-float output and automatic pixel-transfer colour conversion in [Display HDR video in EDR with AVFoundation and Metal](https://developer.apple.com/videos/play/wwdc2022/110565/). The implemented request follows its P3/linear approach. Actual frame metadata is still checked: float storage alone is not evidence of a linear transfer function. Narrow BT.709 output tone-mapped the PQ test sample; P3 output retained its extended values.

Tagged BT.709 full/limited-range video, BT.2020 PQ and HLG fixtures exercise AVFoundation's range, YCbCr conversion, transfer handling and colour metadata. The application converts linear P3 to linear sRGB using a D65 primary conversion matrix. It preserves negative out-of-gamut components and values above reference white in half-float eye textures. It does not clamp them to [0, 1] during faithful rendering. HDR tests use neutral steps; comprehensive wide-gamut colour-chart/display validation is still required.

If AVFoundation returns completely untagged RGB, the app explicitly reports an **assumed SDR sRGB** interpretation, matching its previous compatibility path. Unsupported explicit colour encodings are rejected rather than treated as linear; known HDR source metadata cannot take that SDR fallback. The original colour intent of an untagged source cannot be recovered reliably. Diagnostic storage precision is labelled separately from source coded bit depth.

HDR pixel preservation is tested. Final panel luminance, EDR headroom, gamut mapping and HDR-to-display tone mapping are **unverified** because RealityKit owns the final eye targets/compositor and this audit has no physical display measurements. No claim of calibrated HDR output is made. Existing highest-rendition selection remains conservative about HDR-labelled HLS variants; this audit does not silently change its compatibility rules.

## Projection, eyes and filtering

Projection and packing remain independent: screen, equirectangular VR180 or VR360; mono, SBS or top/bottom; eye swap and vertical flip. The shader crops each eye before filtering, with half-texel boundary clamps, so packed eyes do not bleed across the seam. Mesh UV orientation and the material's bottom-left convention are retained. VR180 spans 180° horizontally and 180° vertically; VR360 spans 360° horizontally. Fisheye, cubemap, mesh-warped and provider-specific projections require separate support.

All modes use the improved mesh. VR360 sampling repeats horizontally and clamps vertically; VR180/screen clamp both axes. The material's camera-index switch selects the independent eye resource. A mono simulator screenshot cannot establish binocular assignment or depth comfort on hardware.

Maximum Quality generates a full mip chain from linear float pixels and requests trilinear minification with anisotropy 8. Original/Enhanced request linear sampling without mipmaps and anisotropy 1. These descriptors use the public [RealityKit texture sampler API](https://developer.apple.com/documentation/realitykit/materialparameters/texture/init(_:sampler:)); they do not claim to expose the compositor's final footprint or anisotropy. RealityKit currently reads a bound texture+sampler parameter back as a texture resource, so tests distinguish descriptor binding from final filtering measurement.

Eye descriptors have an explicit budget: 384 MiB for Original/Enhanced and 512 MiB for Maximum, including allocated mip levels. These are application policies, not device capacity measurements, and exclude decoder surfaces and RealityKit's private backing pools. Extremely large eye images can be reduced to fit; the actual dimensions, scale and a visible warning report this. Standard 8K SBS and 8192 × 4096 mono preserve their eye dimensions in every mode.

## Picture controls and diagnostics

While playing, reveal the controls and choose **Picture**:

- **Original** (default): faithful linear processing without sharpening.
- **Enhanced**: low-strength, locally bounded sharpening with contrast/coherence gates. No claimed recovery of missing detail; low-bitrate/noisy sources may look better in Original.
- **Maximum Quality**: faithful pixels with mipmaps and oblique filtering; extra memory/GPU cost. It does not force a different stream rendition.
- **A/B**: switch Original ↔ the last selected non-Original mode. Pause first to compare the same decoded frame and viewpoint; changing the mode does not replace the player item or seek.
- **Pipeline diagnostics**: independent overlay; it can remain visible while transport controls hide. Turn it off from Picture.

The current Playback details JSON includes `videoPipeline`: source track properties, coded precision evidence, actual buffer dimensions/format/colour/stride/PTS, eye sizes/descriptor bytes/scale, filtering requests, projection/mesh, estimated source/texture angular resolution, and scoped performance measurements. Normal pipeline snapshots publish at most once per second, including after pause; picture-mode changes and failures publish immediately. Frame acquisition itself does not trigger a diagnostic SwiftUI update on every video frame. Session history includes compact bounded samples and picture-mode changes. Existing diagnostic privacy/full-link preferences and retention rules remain in force; no frame images or head-pose history are saved.

Measured: copied-buffer dimensions/format, public track metadata, descriptor sizes, counters, own-process CPU/footprint/thermal state, display-link callback intervals, command GPU elapsed time where nonzero, CPU preparation wall time and submit-to-callback latency. GPU timing covers preparation only. PTS gaps, access-log dropped frames and backpressure skips are distinct; no inferred “total dropped frames” is invented.

Estimated: source/texture pixels per degree under full equirectangular coverage. Unavailable: final eye drawables/render scale, foveation state, total GPU utilisation, AVPlayer's hardware-decoder decision, photon latency and calibrated display luminance. Simulator process/thermal measurements are not headset performance acceptance.

## Alternatives evaluated

- A custom VideoToolbox decoder was **not adopted**: there is no demonstrated advantage sufficient to replace stable HLS/authentication/audio/timing behaviour. AVPlayer does not expose its decoder acceleration decision; hardware decoding is not asserted.
- Always using much denser geometry was rejected: 512 × 256 VR180 improves an already sub-quarter-texel synthetic error at four times the new triangle count, without measured perceptual/headset performance benefit.
- Spatial/temporal denoising and upscaling were not added. They risk removing real fine detail, adding latency or inventing texture. Conservative sharpening is optional.
- An explicit compute mipmap replacement was prototyped, then **removed** when a simulator readback quirk was isolated. GPU copy and level-zero texture-view reads confirmed the normal mip generator was correct.
- The legacy BGRA/gamma shader is retained only as an offline benchmark reference. It is not exposed as a live mode, avoiding two production decode paths and an extra decoder just for comparison.

## Verification and retained failures

See [VIDEO_QUALITY_BENCHMARKS.md](VIDEO_QUALITY_BENCHMARKS.md) for exact results, commands and scope. Test footage is generated locally and released CC0; no remote footage was downloaded for this audit. Native suites cover existing browsing, downloads/remux/recovery, authentication scoping, format detection, controls, cancellation and report privacy as well as the new quality tests. Scene checks mount the real SwiftUI/RealityKit immersive space and invoke shared production actions; they are not synthetic human gaze/pinch tests.

Earlier failed investigations are retained privately under `TestResults/video-quality-audit-0.16.0/`. Fixture corrections were important: FFmpeg 9 required frame `setparams` tags to write proper primaries/transfer metadata, lossless H.264 used an unsupported profile, and QP 1 H.264 decoded incorrect chroma in both simulator runtimes even through the original BGRA path. The final ordinary High-profile QP 18 bars decode correctly, with independent FFmpeg reference checks. Simulator `getBytes(mipmapLevel:)` returned base-level pixels for nonzero levels; tests now read a level-zero view, independently cross-checked against a GPU copy. A final repeat also encountered a pre-main dyld simulator-loader stall; it was sampled, cancelled and rerun after restarting only the owned labs. These failed attempts were investigated, not counted as successful runs.

## Installation and physical-headset checklist

Build the `VisionStream` scheme for your paired Vision Pro, select your own signing team and press Run; detailed/free-account steps are in [Docs/INSTALLATION.md](Docs/INSTALLATION.md). Version is 0.16.0 (39). Personal-Team provisioning expires and must be renewed through Xcode. Source is [hsingh134/VisionStream](https://github.com/hsingh134/VisionStream); it contains no developer credentials or personal media.

1. Use a known full-quality VR180 SBS source and note **decoded** dimensions and per-eye sizes in Picture → Pipeline diagnostics. Compare with the exact same file/rendition on Quest, not two differently compressed previews.
2. Pause on fine text/lines; compare Original, Enhanced and Maximum using A/B. Check centre sharpness, grain, ringing and dark gradients. Enhancement must not turn skin or texture unnaturally crisp.
3. Look toward 45–80° eccentricity, horizon, poles and seams. Check peripheral aliasing/minification, top/bottom orientation, stereo alignment and correct eye assignment. Compare SBS and top/bottom calibration patterns.
4. Check depth at centre and edges, recentering, manual tilt and reclining. A 1000 m panorama reduces geometry-induced offset but does not correct incompatible source disparity or guarantee comfort.
5. Check tagged SDR black/white and colour bars, then PQ/HLG steps. Watch for grey blacks, clipped highlights, excess brightness, saturation changes or uneven appearance between eyes. Final HDR/display mapping needs measurement/visual acceptance.
6. Run a 30/60 fps moving source for at least 20 minutes in each mode. Note stalls, PTS gaps, access-log drops, app CPU/footprint, thermal state and preparation time. Use Instruments/Metal System Trace on hardware for total renderer/decoder costs; switch to Original if Maximum cannot sustain cadence.
7. Verify audio sync, seek, pause/resume, controls hide/reveal, return/re-entry, downloaded-file playback, interruption/resume and low-memory recovery. Confirm the overlay can be disabled and comparison does not move the viewpoint.

Physical subjective quality, sustained headset thermals, final HDR mapping and Quest parity are the remaining acceptance gates. Do not interpret passing simulator tests as those gates having passed.
