# CC0 streaming calibration media

`Scripts/generate_fixtures.py` creates six original equirectangular calibration clips, each as MP4 and segmented HLS. They cover VR180/VR360 crossed with mono/SBS/top-bottom. There is no borrowed footage, uncertain sample licence, or website content.

All generated original media is dedicated to the public domain under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/). No attribution is required. The generator uses handmade bitmap lettering and a generated audio tone. Fixture generation uses the separately installed desktop FFmpeg executable. The app separately includes a minimal LGPL FFmpeg remux library; see `Docs/MEDIA_RUNTIME.md`.

The six base clips have a longest dimension of 2048 pixels; a separate Highest-quality fixture reaches 3840 × 1920. Clips have H.264 video, AAC audio, eight-second duration, two-second keyframes and four HLS segments. Eye labels, asymmetric markers, pole labels and a blinking green square help reveal packing/orientation problems. The eye views contain calibration patterns rather than a photorealistic scene with physical binocular disparity, so these clips establish eye assignment and projection, not depth accuracy.

Generated files are present in this workspace and included in the source archive (intermediate PPMs may be omitted from the archive). They are excluded from Git because they are reproducible. Regenerate with:

```sh
python3 Scripts/generate_fixtures.py
```

See `Docs/INSTALLATION.md` for HTTPS serving and `Docs/TESTING.md` for tests actually performed. Vision Pro immersive validation remains pending.

The unlabelled `context-sample.mp4` and `unlabelled/stream.m3u8` pair contains original seeded, coarse texture duplicated into two eyes at 1024 × 512. It has no projection or packing tag. Coarse texture survives anti-aliased downsampling; the earlier pixel-scale-noise version became ambiguous after averaging and is recorded in failed detector trials. Separate host tests exercise horizontal disparity, different scene depths, low-texture rejection and ambiguous repeating patterns. The existing private local video used for optional acceptance is not a CC0 fixture and is never packaged.
