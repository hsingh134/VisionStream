# Desktop yt-dlp test

yt-dlp is installed on this Mac through Homebrew. The installed executable reports
`2026.08.19`; FFmpeg reports `8.1.2`. This records the versions actually tested,
not a claim that Homebrew supplied the newest upstream release.

This report describes the separately installed desktop development tool. Version
0.3.0 now also embeds the pure Python yt-dlp package in VisionStream itself; see
[on-device extraction and its separate results](ON_DEVICE_EXTRACTION.md). The
desktop executable and FFmpeg are not bundled. Further YouTube work is deferred.

## In-app download status

VisionStream 0.4.0 streams media and runs the embedded finder in metadata-only mode (`skip_download` / `download=False`). It has no offline-download button or local download manager. The successful desktop downloads below are not in-app download tests. No new explicit-site download was performed for the quality work.

## Results

Four downloads succeeded without account cookies, custom player flags, custom
headers, projection conversion, or video re-encoding:

| Sample | Download and decoding result | Projection result |
| --- | --- | --- |
| NASA original black-hole 360 MP4 | 177,428,119 bytes; H.264 2160×1080; AAC; 69.77 seconds; full decode and two seek positions passed | Embedded equirectangular spherical mapping and 2D/mono stereo metadata present |
| NASA Goddard YouTube 360 video, format 137 | 13,435,199 bytes; H.264 1920×1080; video only; 77.71 seconds; full decode passed | Extractor labels it `1080s, mesh`; MP4 has custom `ytmp` projection, unrecognised by FFmpeg. Exact mapping and immersive rendering are unverified |
| Original CC0 VR180 side-by-side fixture | Download matches source SHA-256 exactly; full decode and seeking passed | Known side-by-side pixels preserved; fixture has no embedded spherical metadata |
| Original CC0 VR360 top-bottom fixture | Download matches source SHA-256 exactly; full decode and seeking passed | Known top-bottom pixels preserved; fixture has no embedded spherical metadata |

Files and raw extractor JSON are in `LocalMedia/`, which is ignored and excluded
from release packaging. The test reports in `TestResults/yt-dlp-*.json` record the
measured sizes, hashes and metadata. The downloaded media has not been tested in
VisionStream's immersive player or on physical Vision Pro hardware.

The normal YouTube extraction and download succeeded on this Mac for this one
public NASA video. This does not establish general YouTube compatibility.
Downloading a spherical video does not ensure that its projection is supported
by the app. VisionStream currently implements equirectangular VR180 and VR360,
not arbitrary mesh projection. Selecting VR360 cannot correct an incompatible
projection by itself. No alternate Android VR player flags were necessary or
tested.

## Reproducing the public download checks

Run these from the project directory. These are the actual public, non-explicit
sources used in the test. `--ignore-config` keeps unrelated local downloader
settings out of the checks. The YouTube format is video only to omit the separately
licensed soundtrack; it demonstrates acquisition, not compatible immersive rendering.

```sh
yt-dlp --ignore-config --no-playlist --no-overwrites \
  -o 'LocalMedia/nasa-black-hole-360.%(ext)s' \
  'https://svs.gsfc.nasa.gov/vis/a010000/a014500/a014576/14576_BHPlunge_360_FINAL_1080.mp4'

yt-dlp --ignore-config --no-playlist --no-overwrites -f 137 \
  -o 'LocalMedia/nasa-youtube-360.%(ext)s' \
  'https://www.youtube.com/watch?v=dGEIsnBRWGs'

ffprobe -v error -show_streams -show_format -of json \
  LocalMedia/nasa-black-hole-360.mp4
```

## Source and rights

- [yt-dlp installation instructions](https://github.com/yt-dlp/yt-dlp/wiki/Installation)
- [NASA visualization and published downloads](https://svs.gsfc.nasa.gov/14576/)
- [NASA SVS use guidance](https://svs.gsfc.nasa.gov/help/)

NASA visualization credit: NASA's Goddard Space Flight Center/J. Schnittman and
B. Powell. NASA identifies its visualizations as public domain unless otherwise
noted; accompanying music can have separate restrictions. The original file with
its soundtrack is retained only for private testing and is not included in app or
source packages. The stereo calibration fixtures are our original CC0 material.

No Pornhub content was requested or downloaded with this tool, and no previously
blocked website was accessed through an alternate route.
