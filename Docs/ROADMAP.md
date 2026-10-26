# Prioritised engineering tasks — 0.6.1

## 0.9.0 resource tracing and foreground save recovery

The current implementation adds bounded checks of exact published HLS resources after selected native save failures. Reports correlate playlist/dependency/segment role, sequence, HTTP status and a per-session resource ID without exposing private URLs or credentials. Foreground range/header checks are labelled separately from native background traffic; a successful check does not prove the background request was equivalent.

A controlled simulator fixture proved that Apple's background HLS service can send a different User-Agent from the actual working WebKit player despite public request options. Supported clear on-demand MPEG-TS can now recover as an MP4 through foreground URLSession transport with the actual browser identity and normally scoped cookies. A local-only LGPL FFmpeg framework remuxes without re-encoding; native playback and duration are checked before the saved file is committed. See `Docs/MEDIA_RUNTIME.md` for supported formats, limits and rebuilding. Other HLS packaging forms continue to need engineering; this is not universal HLS downloading.

Automatic stereo analysis now handles larger, locally varying disparity and partial occlusion using bounded regional comparison and three-frame agreement. It keeps metadata, explicit mono and manual choices authoritative and rejects unrelated/ambiguous images. No decoded image samples are stored in diagnostics.

The native background HTTP 404 resource remains unidentified. A new user-supplied 0.9.0 report on 26 October confirms two foreground MP4 saves completed and local VR playback decoded1440×720. Passive inspection subsequently found all three completed copies in the local catalogue. No new agent-controlled remote-site access was performed. This verifies those fallback attempts, not universal website support; automatic format selection for the second live stream remains unverified because the final snapshot is manual.


Latest site gaps: obtain a suitable streaming source for VirtualRealPorn rather than its non-seekable download routes; verify source association for custom/canvas players; investigate SexLikeReal secure connection failures on hardware. Saved public 4K VR180/SBS playback is verified; member-only maxima remain outside scope.

The current build implements streaming, highest supported independent HLS selection, automatic equirectangular VR/packing detection, native controls, MP4/HLS offline playback, MP4 import/export and repair, bookmarks/restoration choices, website-data clearing and audio lifecycle handling. See [production readiness](PRODUCTION_READINESS.md) and [test results](TESTING.md). Historical milestones and earlier unresolved reports are retained in [roadmap history](ROADMAP_HISTORY.md).

## P0 — Release acceptance

1. Sign and install on a physical Vision Pro using the owner’s team. Verify eye isolation/depth/ordering, orientation, panorama bounds, pose/recenter, gaze/pinch targets, text sizing, controls placement, Crown exit and scene restoration.
2. Profile 30–60 minute 4K/8K/high-frame-rate sessions. Measure memory/GPU peaks, thermals, battery, dynamic resolution and network stalls. Validate SDR colour; do not advertise mastering-accurate HDR.
3. Test multiple authorised videos on each intended website. Record actual decoded dimensions and automatic format decisions, not just readiness. The historical single Pornhub HLS success and controlled 4K fixtures are separate evidence. No restriction bypass or fabricated authentication.
4. Test physical audio routing, Bluetooth disconnection, system interruptions, headset removal, suspension, low storage and relaunch. Simulator notification tests do not substitute for these.

## P1 — Product completeness

1. Validate HLS background completion/relaunch, force-quit, cookie-authenticated sources and eviction on physical hardware. Add user-configurable storage limits, duplicate detection, stronger damaged-HLS-index recovery and a downloadable quality chooser. MP4 import/export/repair and HLS task pause/resume now exist.
2. Add per-site controls and optional history with explicit retention. Bookmarks and Home/website/page restoration choices now exist. Improve recovery for URL expiry and sources requiring a website-only player, keeping diagnostic reports private.
3. Harden extractor job deadlines and minimise bundled Python modules. Maintain pinned dependencies, licences, reproducible clean-host builds, security updates and a rollback process.
4. Complete VoiceOver, large-text, reduced-motion and comfort acceptance. Add captions and audio-track selection with HLS parent context intact.
5. Extend format handling only with documented geometry and licensed calibration media: additional spherical metadata, fisheye, MV-HEVC/APMP/Apple Immersive Video and HDR need separate pipelines/acceptance.
6. Original layered icon, in-app privacy/consent/deletion controls and local submission tooling are implemented in 0.10.0. Finish owner public contact/hosting, signing, source permission review, encryption/export classification, LGPL public source delivery, real review screenshots and physical acceptance. The packaged device archive remains unsigned.

## Deliberate boundaries

YouTube work remains deferred. No DRM, payment, authentication or site-restriction bypass is planned. A detected URL does not prove native playback or a source’s maximum available quality. Whole-video saving is an explicit action; streaming never silently becomes an offline download.
