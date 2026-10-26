# Bundled runtime and distribution review

Inventory checked against local pinned packages and build outputs, 26 October 2026. This is a scoped engineering review, not a vulnerability certification or completed export/legal determination.

| Component | Included purpose | Licence / evidence |
| --- | --- | --- |
| CPython 3.14.9, BeeWare support 3.14-b13 | Bundled on-device source discovery | Python licence and MIT build helper; complete notices in Licenses/EmbeddedRuntime.txt; pinned archive SHA in Vendor/dependencies.lock.json |
| yt-dlp 2026.10.21 pure Python | Source descriptions, no media download by extractor | Unlicense; bundled package, no desktop executable or PyInstaller payload |
| certifi 2026.10.23 | Verified HTTPS root certificates for bundled Python | MPL 2.0; complete notice/text included |
| OpenSSL 3.5.9 and runtime dependencies | CPython HTTPS / runtime support | Apache 2.0 OpenSSL and other dependency texts in EmbeddedRuntime.txt |
| FFmpeg 9.0.2 | Local clear MPEG-TS packet copy to MP4 | LGPL 2.1 or later; separate dynamic framework, complete exact source archive, recipe and adapter included |
| Khaos Tian stereo material adaptation | RealityKit per-eye material | Apache 2.0, attribution/modification notice and full licence bundled |
| Original calibration media and icon | Deterministic review and identity | Calibration media CC0; icon is original vector artwork in Scripts/generate_app_icon.swift |

## Code execution boundary

The installed source finder is bundled and version-pinned. It does not install code updates, external plugins, remote JavaScript engines or helper executables. The adapter disables media downloading, external processes, synthetic cookies, browser credential import, geo bypass and persistent extractor caching; TLS verification stays on. Page JavaScript stays in WebKit. Review should see these capabilities and restrictions, rather than conceal the interpreter. Guideline 2.5.2 must be assessed against the actual packaged runtime and behavior. A Python interpreter is not by itself a guarantee of approval or rejection.

The FFmpeg build disables GPL/nonfree code, networking, encoders and executable programs. Only file protocol and required demux/mux/parsing are enabled. The app passes owned local paths to the wrapper. No copied GPL VR player is included. The earlier notice incorrectly implying no FFmpeg library was included has been corrected.

## LGPL delivery

The source package contains the exact unmodified FFmpeg source tar, the full licence, source checksum, configuration manifest, C adapter, full app source and build instructions for replacing/relinking the dynamic framework. There is no runtime library checksum lock. The project expressly permits modifications/replacement and reverse engineering needed to debug those modifications. See Docs/MEDIA_RUNTIME.md. Before public binary distribution, the publisher must make corresponding source/relink materials available through a durable public distribution route, carry notices, and review any default or custom EULA for conflicting restrictions. An unhosted local source ZIP alone is not proof that App Store recipients have received the required materials.

## Encryption

WebKit/AVFoundation/URLSession use Apple's TLS implementations. The bundled Python runtime additionally includes OpenSSL 3.5.9. Consequently this project does not assume that the OS-only encryption exemption covers everything. Classification, distribution regions, documentation and any App Store Connect compliance code must be determined by the publisher. `usesNonExemptEncryption` remains null, and no false Info.plist declaration is inserted. The generated archive plist and preflight verify an explicit answer when supplied. Check https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/ and its documentation table for the actual distribution case.

## Maintenance and remaining checks

Checksums pin reproducibility; they do not establish absence of vulnerabilities. Review upstream security advisories, source/code updates, transitive runtime APIs and licences for every public release. Required-reason API entries are in PrivacyInfo.xcprivacy for app settings, app-owned file metadata, storage checks and local timing. Xcode/Apple archive validation, runtime dependency privacy reporting, physical acceptance and a signed TestFlight run remain pending. The local preflight reports these boundaries without uploading anything.
