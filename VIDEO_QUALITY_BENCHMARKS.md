# Video-quality benchmarks and verification

VisionStream 0.16.0 (39), 1 November 2026. Baseline: 0.15.0 (38), `583fe1c`. These are measured texture/geometry tests and controlled simulator integration results, not a perceptual Vision Pro/Quest comparison.

## Test environment and evidence

Apple M4 Max host; Xcode 27.1; visionOS 27 SDK; deployment target 26.0; dedicated visionOS 26.0 and 27.0 simulators. Original locally generated CC0 footage only. Sources include 4096 × 2048 VR180 SBS fine lines/checker/text/gradients/stereo disparity/flashing motion marker, a low-bitrate version, 8192 × 4096 Main10 mono, BT.709 full/limited-range colour bars and BT.2020 PQ/HLG steps. No third-party footage was downloaded for this audit.

Private detailed evidence is retained in `TestResults/video-quality-audit-0.16.0/`; public source excludes test reports, generated media, signing material and owner configuration. The generator writes colour/reference metadata and checks that encoded primaries, transfer tags and container colour information are present.

## Before/after pixel and geometry measurements

| Controlled measurement | 0.15 reference | Corrected result | Interpretation |
| --- | ---: | ---: | --- |
| Linear average of equal black/white texels | 0.2139893 | 0.5 | Expected linear average is 0.5. Exposes encoded-light filtering when resizing. |
| Linear RMSE, 1024-level reference ramp after transport/preparation | 0.00176020 | 0.000106500 | About 16.5× lower error by avoiding the extra 8-bit conversion; this is not an end-to-end perceptual score. |
| Blurred synthetic edge RMSE | 0.0988212 | Enhanced 0.0986105 | Small 0.21% improvement on this edge; no claim of universal fidelity improvement. |
| Enhanced low-contrast synthetic-noise deviation gain | 1.0 input | 1.01195 | Approximately 1.2% increase for this noise pattern; enhancement remains optional. |
| Black/white checker, final linear mip | Expected 0.5 | 0.5 | Tests generated mip data, not final compositor sampling. |
| VR180 mesh interpolation: 95th-percentile error, 4096² eye, latitude ≤75° | 0.509126 texels | 0.125494 texels | Geometry-only error using four barycentric samples per triangle. |
| Same mesh: maximum sampled error | 0.693512 texels | 0.174052 texels | 128 × 64 → 256 × 128 mesh. Actual production-mesh core tests independently enforce the bound. |

A 512 × 256 mesh measured 0.031474 p95 / 0.043817 maximum texel error, but was rejected as the default: it quadruples the new VR180 triangle count for a smaller already-subpixel error, without measured headset benefit. VR360 uses twice the horizontal columns to keep angular density consistent.

A **synthetic** 64 mm eye baseline on a 4096-pixel-wide 180° texture gives approximately 8.344 geometry-offset texels at 10 m shell distance and 0.08344 at 1000 m. This is an analytic illustration, not a measured user IPD, headset optical model, source-disparity correction or comfort score.

## Resolution preservation

| Source / layout | Former eye texture | New Original eye texture | New allocation |
| --- | --- | --- | --- |
| 8192 × 4096 mono / VR360 | 4096 × 2048 | 8192 × 4096 | One shared 256 MiB descriptor instead of duplicated eye images; native decode/binding verified |
| 8192 × 4096 SBS / VR180 | 4096 × 4096 | 4096 × 4096 | Two descriptors; 256 MiB total before mips; no invented resolution improvement |
| 4096 × 2048 SBS chart / VR180 | 2048 × 2048 | 2048 × 2048 | All three modes retain these eye dimensions in mounted-scene tests |

Maximum allocates the complete mip chain, approximately one-third additional descriptor memory for power-of-two images. Descriptor budgets, actual dimensions, texture count and scale are explicit in `videoPipeline`. Decoder buffers, multiple in-flight surfaces and RealityKit private pools are additional and must be measured on hardware.

A full-width 8192-pixel mono VR360 source/texture has an estimated 22.756 horizontal pixels/degree. A 4096-wide eye over 180° has the same estimate. These are source/texture angular estimates, not final display PPD, optical resolution, foveation or acuity.

## Native colour evidence

Both simulator runtimes decode tagged full/limited BT.709 bars through the production half-float output settings; converted RGB agrees with the reference within the stated 0.035 component tolerance, and both ranges agree within 0.025. These tolerances include encoding, chroma reconstruction and half precision, not calibrated display error.

The known Main10 BT.2020 PQ neutral steps produced linear P3 values on visionOS 26:

`0, 0.0099411, 0.101074, 1.00195, 2.51172, 5.05469, 7.51172, 10.10156`

The source steps correspond to 0, 1, 10, 100, 250, 500, 750 and 1000 nits. The test verifies monotonic finite values and that highlights survive above reference white; it does not derive actual display nits from those buffer values. HLG steps produced:

`0, 0.0120316, 0.120667, 1.20410, 3.01172, 6.04688, 9.05469, 12`

Source declarations report HEVC Main10 coded precision, BT.2020 primaries and PQ/HLG transfer independently from 16-bit half-float **storage**. Production GPU tests also verify P3-to-linear-sRGB conversion preserves extended and negative gamut components. Comprehensive coloured HDR charts, final gamut mapping and display headroom still need physical validation.

## GPU preparation timing

Final portable GPU run (`mac-gpu-final.json`): 4096 × 2048 varying gradients/checker input → two 2048 × 2048 RGBA16F eyes, 25 submissions/mode, first 5 excluded. Corrected paths include the production P3-to-linear-sRGB conversion. Source data creation/upload is excluded from command elapsed times; legacy input uses the BGRA reference transport. Maximum includes mip generation. The exact same production Metal functions are compiled for this Mac probe.

| Preparation mode | Median GPU ms | Sample p95 GPU ms |
| --- | ---: | ---: |
| Legacy reference | 0.3265 | 0.6020 |
| Original | 0.3072 | 0.5259 |
| Enhanced | 0.3387 | 0.6166 |
| Maximum | 0.4666 | 0.8029 |

These are **M4 Max preparation-command timings**, excluding decode conversion, RealityKit rendering/sampling, compositor, foveation, audio and presentation. Other exploratory runs varied considerably under concurrent simulator work. The small Original/legacy difference is not evidence of a speedup. Maximum deliberately spends additional work on filtering; its sustained headset cost is unmeasured.

## Automated results

- Release simulator build and signed physical-device build succeed; device signature verification succeeds.
- Full native visionOS 26 suite: **219 passed, 12 optional skips, 0 failures** (231 methods).
- Full native visionOS 27 suite: **219 passed, 12 optional skips, 0 failures** (231 methods).
- Six dedicated native quality methods per runtime cover actual colour/range/HDR decode, attachment validation, paused mode switching, bound resources and full 8K mono. Production GPU readback contributes **9,248 checks** per runtime; the Mac probe also passes 9,248.
- Host Swift Package: **106 passed**. Standalone: **100 methods, 1,949 assertions, 0 failures**.
- Legacy Metal regression: **12 configurations, 1,024 pixel assertions**. Mac streaming: **12 MP4/HLS decode probes**.
- HTTPS fixture regressions: **19 passed**; resolver: **19 passed**; automation/evidence: **16 passed**; detector unit tests: **15 passed**; submission/public-source scripts: **6 passed**. Both shipped JavaScript resources pass syntax checks.
- Real mounted-scene suites: **19 scenarios / 184 named checks per runtime**, including Picture/A-B/overlay, forms, tabs, user-play handoff, downloads, diagnostics, transport, hiding controls, libraries, cancellation, re-entry, restoration, highest-quality HLS and a 120-second soak. They use shared production actions and the actual SwiftUI immersive-space environment, not physical gaze/pinch injection.

The 26 soak received 3,537 frames in 121.90 seconds while rendering the controlled 3840 × 1920 source and exercising controls/quality changes. Its peak simulator resident memory was 1.64 GB; the final sample was 467 MB. These process samples include warm-up/platform behaviour and are not a memory-leak proof or physical sustained-decoder/display benchmark. A separate 27 soak also passed its cadence and bounded-memory assertions. Exact counters remain in the private JSON evidence.

Original/Maximum screenshots from both runtimes were visually reviewed: the calibration frame is upright, the Picture panel and independent diagnostics overlay fit, and the 1000 m shell renders. Screenshots are not used to assert binocular depth, subjective sharpness or HDR calibration.

### Desktop trusted-input harness repair

The pre-existing desktop click driver initially failed: its inactive/hidden owned window discarded the activation click. Making a floating fixture window visible and delivering the event through the hit-tested view's public NSResponder methods fixes the harness. **Both real WebKit checks pass**: programmatic JavaScript playback does not create intent, while native AppKit input is reported as trusted by WebKit and produces the shipped isolated intent. A bundled-launch experiment was stopped after it failed to progress. No production input guard was weakened and no private event API was used. This remains an owned-fixture AppKit test; physical Vision Pro gaze/pinch requires separate acceptance.

### Retained exploratory failures

Initial lossless H.264 fixtures selected High 4:4:4 Predictive and failed decode. QP 1 High-profile chroma was wrong in both simulator runtimes through **both old BGRA and new half-float outputs**; QP 18 bars pass and independent FFmpeg RGB readback confirms the reference. FFmpeg 9 also required frame `setparams` tags to retain primaries/transfer metadata; encoder flags alone produced unspecified tags. The final generator validates these conditions.

An early mip assertion read the wrong level through simulator `getBytes(mipmapLevel:)`. Level-zero texture-view reads and a separate GPU copy agreed on correct mip data. A temporary compute generator was therefore reverted. Early rounded P3 coefficient/half-float tolerances were corrected to a D65 matrix and a precision-scaled tolerance. Failed logs are retained and excluded from final pass counts. A final repeated native launch stalled in the simulator's dyld system loader before app code started; its sample was retained, the attempt was cancelled and the owned lab simulators were restarted for a clean focused rerun. Both restarted focused quality suites passed (six methods per runtime), followed by final complete suites of 219 pass / 12 optional skips / zero failures per runtime. Their production executable hashes match the final built app.

## Reproduction

From a clean source checkout with Xcode, Python 3, Node and FFmpeg/ffprobe:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 Scripts/generate_fixtures.py
python3 Scripts/generate_quality_fixtures.py
swift test
sh Scripts/test_core.sh
sh Scripts/test_metal.sh
sh Scripts/test_video_quality.sh
python3 Scripts/benchmark_projection.py
node Scripts/test_video_detector.js
python3 Tests/Fixtures/test_fixture_streams.py
python3 Tests/Extractor/test_resolver.py
python3 Tests/Automation/test_observation.py
python3 -m unittest discover -s Scripts -p 'test_*.py'
python3 Scripts/generate_project.py
xcodebuild -project VisionStream.xcodeproj -scheme VisionStream \
  -configuration Release -sdk xrsimulator \
  -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath DerivedData/VideoQuality \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing
```

Prepare the bundled extractor/media runtime as described in [Docs/AUTOMATED_TESTING.md](Docs/AUTOMATED_TESTING.md) when building a clean checkout. Generated fixtures/vendor packages are not in public source.

Create a dedicated simulator named `VisionStream Automation Lab ...` and use its UUID with:

```sh
python3 Scripts/run_visionos_tests.py --simulator YOUR_LAB_UUID \
  --build-root DerivedData/VideoQuality --output TestResults/quality-native
python3 Scripts/run_scene_checks.py --runtime 26.0 \
  --build-root DerivedData/VideoQuality \
  --cases image-quality controls controls-hide auto-play downloads quality4k soak \
  --soak-seconds 120 --output TestResults/quality-scenes
```

Use `--only-testing VisionStreamTests/VideoQualityNativeTests` for the six focused native quality methods. The drivers restrict fixture origins to HTTPS loopback, trust the temporary certificate only in disposable lab simulators and never change the Mac trust store or personal simulator sessions. Optional external/private-media tests are skipped unless explicitly enabled. Device/Quest acceptance steps are in [VIDEO_QUALITY_AUDIT.md](VIDEO_QUALITY_AUDIT.md).
