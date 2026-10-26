# Installation and signing

Current 0.12.0 release preparation is documented in `Submission/README.md`. Building and simulator tests are free. A free Apple Account can use Xcode Personal Team for personal device testing with seven-day provisioning; App Store/TestFlight distribution requires paid membership. The supplied device archive remains unsigned until you configure your own team. No purchase or enrollment is performed by this project. Keep the `VisionStream` scheme for the existing personal installation; `VisionStream-AppStore` is separate distribution preparation. Public policy/contact and encryption answers are deliberately not invented.


## Requirements

- An Apple silicon Mac with Xcode 26+ and a compatible visionOS SDK/platform installed. This checkout has been compiled with Xcode 27.1 (27A9275), Swift 6.4 in Swift 6 language mode, and the visionOS 27 SDK, retaining a visionOS 26 minimum target.
- Vision Pro running visionOS 26+ for the final stereo/tracking checks.
- An Apple account configured in Xcode. Device installation needs a team and a provisioning profile permitted for that device.

This checkout contains a complete `.xcodeproj`, shared scheme, test target, Info.plist, configuration files, shader, JavaScript, resources and the bundled `Vendor/` runtime/packages. No project-generation tool is needed to open it. Version 0.3.0's Find streams feature runs on Vision Pro; no Mac companion or desktop yt-dlp installation is required for playback. Run `python3 Scripts/prepare_embedded_extractor.py` before opening the project: the public repository intentionally fetches the pinned extractor packages instead of checking them into Git. See [on-device dependency/licence details](ON_DEVICE_EXTRACTION.md).

## Signing

1. Open `VisionStream.xcodeproj` in Xcode.
2. Choose the VisionStream target → Signing & Capabilities. Keep automatic signing enabled and select your own team.
3. Change the bundle identifier from `personal.visionstream.browser` to a unique identifier under your control.
4. Alternatively, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, then enter your team ID and identifier. The local file is ignored by Git.
5. For device tests, set a unique test target bundle identifier too if Xcode requires it. Both targets inherit your development team.

No team ID, signing certificate, provisioning profile, or account credential is supplied. Use normal ad-hoc simulator signing for background HLS downloads; disabling simulator signing caused background-service connection failures in testing. Both the device and simulator configurations use arm64. There are no custom entitlements for ordinary browsing, AVPlayer playback, Metal textures, or querying device pose in the immersive space. The app does not request hand tracking, camera capture, or world-mesh access.

## Run on Vision Pro

Follow Apple's current [running your app in Simulator or on a device](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device) guidance to pair Vision Pro in Xcode, enable Developer Mode when prompted, and trust your developer account if the device requires it. Choose that Vision Pro as the destination and press Run.

The first test should use a calibration stream. Automatic format detection is enabled; verify its result and use Video format settings to override it if needed. Highest is the default quality preference; Adaptive allows AVPlayer to adjust to the connection. Confirm orientation and comfort before trying a website stream. The Playback window’s Return to page control dismisses the immersive space. The Digital Crown remains a system exit mechanism if an immersive app becomes unresponsive.

## Command-line validation with Xcode installed

The installed Xcode is at `/Applications/Xcode.app`. Both visionOS 26.0 (23M336) and 27.0 (24M362) simulator runtimes are installed; the SDK is visionOS 27.0 and the app deployment target is 26.0. The scripts explicitly select it, so they work even when the Mac's global developer directory still points to Command Line Tools.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sh Scripts/build_visionos.sh simulator
VISIONSTREAM_BUILD_ROOT="$PWD/DerivedData/Device" sh Scripts/build_visionos.sh device
xcodebuild -project VisionStream.xcodeproj -scheme VisionStream \
  -sdk xrsimulator -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
```

For the minimum-version runtime, `xcodebuild -downloadPlatform visionOS -buildVersion 26.0 -architectureVariant arm64` installs the Apple-provided simulator. Its runtime identifier is `com.apple.CoreSimulator.SimRuntime.xrOS-26-0` and it also uses the 4K Vision Pro type. The running test device is named **VisionStream visionOS 26**.

Create a dedicated simulator with a device type compatible with the installed runtime. With the installed visionOS 27 runtime, use the 4K Vision Pro type (the older 2732×2048 type is incompatible):

```sh
xcrun simctl create 'VisionStream Test Vision Pro' \
  com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-4K \
  com.apple.CoreSimulator.SimRuntime.xrOS-27-0
xcrun simctl boot YOUR_SIMULATOR_ID
xcrun simctl bootstatus YOUR_SIMULATOR_ID -b
python3 Scripts/run_visionos_tests.py --simulator YOUR_SIMULATOR_ID --keep-serving
```

The last command generates a one-day HTTPS certificate, trusts it **only inside the specified dedicated simulator**, serves the CC0 fixtures on Mac loopback, configures the native test environment, and runs XCTest. It leaves the fixture server available for manual checks until interrupted. The Mac's trust stores are unchanged. Use a disposable test simulator; deleting it after testing removes its test certificate too. The local test origin and result paths are written to `TestResults/native-test-session.json`.

Install the simulator app with `xcrun simctl install YOUR_SIMULATOR_ID DerivedData/Build/Products/Debug-xrsimulator/VisionStream.app`, then launch `personal.visionstream.browser`. Open Device Hub from Xcode to see its window. Open the recorded HTTPS fixture origin in VisionStream's address bar.

For a physical device, choose its destination and your signing settings, rather than `CODE_SIGNING_ALLOWED=NO`. Native fixture decode tests need `VISIONSTREAM_TEST_ORIGIN` set to a trusted HTTPS fixture server reachable from that device.

To modify the source file list deterministically, run `python3 Scripts/generate_project.py`. It rewrites the project and shared scheme; keep signing customisations in Local.xcconfig so regenerating does not lose them.

## Release validation and archive

Version 0.3.3 passes all 59 native tests in Release on visionOS 26.0 and 27.0, including explicitly enabled public NASA extraction, presented webpage frames, the optional user-supplied MP4 sample, and controlled MP4, individual HLS and parent-playlist decoding without injected website headers. Omit the private-sample opt-in to reproduce 58 public/controlled passes and one explicit skip; see the test report. The earlier 0.2.1 build passed its 35 tests in both Debug and Release on both runtimes, including fresh-boot checks. Repeat a Release build and test with:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project VisionStream.xcodeproj -scheme VisionStream \
  -configuration Release -sdk xrsimulator \
  -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath DerivedData/ReleaseSimulator \
  CODE_SIGNING_ALLOWED=NO build-for-testing
python3 Scripts/run_visionos_tests.py --simulator YOUR_SIMULATOR_ID \
  --build-root "$PWD/DerivedData/ReleaseSimulator" --public-extraction --keep-serving
```

A packaged copy is `VisionStream-VisionPro-unsigned.xcarchive.zip` at the project root. The unsigned physical-device release archive is at `DerivedData/Archives/VisionStream-0.9.1.xcarchive`. Its app declares visionOS 26.0 as its minimum; the shader, detector, start page, notices, Python runtime and extraction packages are present, and its dSYM UUID matches the executable. `TestResults/release-build-manifest.json` records its versions and checksums. The archive is a build artifact, not an installable signed application. Use your development team and the Xcode Run workflow above for headset installation. Encryption export classification/App Store distribution of the embedded OpenSSL runtime is not completed; the project no longer asserts that it contains no non-exempt encryption.

To reproduce the archive:

```sh
xcodebuild -project VisionStream.xcodeproj -scheme VisionStream \
  -configuration Release -sdk xros -destination 'generic/platform=visionOS' \
  -derivedDataPath DerivedData/Release \
  -archivePath DerivedData/Archives/VisionStream-0.9.1.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
```

## Serving the CC0 test media

Run `python3 Scripts/generate_fixtures.py` if `Fixtures/generated` does not exist. Use an HTTPS host you control with a certificate trusted by Vision Pro. Copy the generated directory to that host, or run:

```sh
python3 Scripts/serve_fixtures.py --cert /absolute/path/certificate.pem \
  --key /absolute/path/private-key.pem --host 0.0.0.0 --port 8443
```

The certificate must cover the hostname you enter on the headset. A Mac's `localhost` refers to the headset itself when used on physical Vision Pro, so use the Mac's reachable hostname or the HTTPS host. The development server defaults to loopback unless you explicitly choose a network interface. The standalone `serve_fixtures.py` does not install certificates; the separate simulator test runner adds its temporary certificate only to the dedicated simulator as described above.

Open `https://YOUR_HOST:8443/` in VisionStream. The page includes six MP4 videos, a nested frame, and an open shadow root. Use Open stream with `https://YOUR_HOST:8443/hls/vr180-sbs/master.m3u8` for the first HLS test. Open `/auth-test` to set the fixture's normal Secure HttpOnly cookie and test scoped native handoff.

To test the new library connection, choose **VR library** and enter `https://YOUR_HOST:8443/library`. Open an entry, choose MP4 or HLS, and Watch in VR; its declared projection and layout are applied. For authenticated fixtures, browse `/auth-test` first, then connect to `/auth/library`. These original calibration endpoints implement the connector's supported HereSphere subset. See [library support](VR_LIBRARIES.md) for the limits of real website integration.

## Storage and streaming

Website cookies and storage remain in the app's normal WebKit container. They are not imported from Safari. Browser settings choose Home, Last website (origin only, the default) or Last page (complete address including query/fragment). Bookmarks deliberately retain exact page links. These preferences may enter normal system backups; session-only cookies need not survive process termination. Preserving login does not restore an expired media URL.

Streaming playback opens media with AVURLAsset and AVPlayer without saving a user-owned video. The separate, explicit Save video action uses native download tasks and saves a validated MP4 file or managed HLS package. AVFoundation and WebKit may buffer or cache media as part of normal playback. Small fixtures may be fetched completely because they are only eight seconds long.

Package the validated source/evidence and unsigned archive with `python3 Scripts/package_release.py`. This verifies the recorded executable checksum and ZIP integrity and excludes local signing settings, build caches, TLS keys and full result bundles.

## Entering an address and checking a website

Click the website-address control to open the entry sheet, or use Command–L with Device Hub keyboard capture enabled. The draft is separate from the page address; only Go or Return navigates. Playback details below the browser provides a locally generated report with numeric failure codes and format classifications while omitting account data and URLs. See [live-site test steps](LIVE_SITE_TESTS.md).

## Full-frame and control check

Serve the generated `/controls.html` page for a longer original CC0 clip (approximately 32 seconds). Select Screen + Single image and Watch in VR. Verify all frame edges and NORTH/SOUTH labels, then Pause/Play, seek and Return to page in the separate native Playback window. Space toggles playback, arrows skip 15 seconds when seeking is available, and Command–Shift–B returns to the browser. The source has to expose a seekable timeline; disabled seeking is reported explicitly. The page's own Safari VR/motion setup does not configure native rendering. Use a documented VR180/VR360 and eye layout for actual panoramic content.

Version 0.3.3 includes a local-network purpose description for user-entered LAN stream/library addresses. A physical headset may ask for local-network access; the simulator tests do not validate that permission prompt. No Bonjour discovery is used.

Version 0.3.4 allows page-managed asynchronous playback, including website autoplay/audio. See `WEB_PLAYBACK_POLICY.md` for the controlled reproduction, regression evidence and live-site acceptance still required.


## Current quality and saved-video controls (0.6.1)

Highest is selected by default. The playback header shows the actual decoded resolution and whether a rendition was selected or the source remains adaptive. Use Streaming quality → Adaptive if a high rendition buffers. Video format settings contains automatic detection and manual projection/layout overrides; Return to page restores the browser. Supported MP4 and unprotected on-demand HLS downloads are available through Video tools or finder results. Open Downloads to view progress, play offline or delete; HLS offers pause/resume. Import MP4 copies from Files, and the share button exports an MP4. HLS packages cannot be exported as MP4. Keep the app open for MP4 work; HLS uses Apple’s background service.

The 0.9.0 project also links `Vendor/VisionStreamMedia.xcframework`. It is supplied for device and simulator; see `MEDIA_RUNTIME.md` for its LGPL source and rebuild/replacement instructions. No extra executable tool needs installing on Vision Pro.
