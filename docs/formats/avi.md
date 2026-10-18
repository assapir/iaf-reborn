# Intro videos — AVI with Indeo 5 video

The CD's `Resource\Avi` holds the two videos the exe plays at start-up (front-end.md §18.2). `iaf-extract` copies them
to `assets/install/resource/avi/`. The port goes straight to the main menu; the
[README](../../README.md#intro-videos) tells how to watch them.

| file | length | video chunks | picture | sound |
|---|---|---|---|---|
| `janes.avi` | 28.8 s | 432 (the last 9 are 2-byte null frames) | Indeo 5 (`IV50`), 320×240, 15 fps | PCM 8-bit unsigned, stereo, 22 050 Hz |
| `intro.avi` | 93.5 s | 1402 | Indeo 5 (`IV50`), 320×240, 15 fps | PCM 8-bit unsigned, stereo, 22 050 Hz |

## AVI container
A RIFF file (`RIFF` size `AVI `), little-endian.

- `LIST hdrl`: `avih` (`dwMicroSecPerFrame` at offset 0: 66 666 µs = 15 fps), then one `LIST strl` per stream with
  `strh` (type `vids` / `auds`) and `strf` (video: a `BITMAPINFOHEADER`, width, height and the codec FourCC `IV50`;
  sound: a `WAVEFORMATEX`).
- `LIST movi`: the data chunks, `##dc` / `##db` for video and `##wb` for sound, where `##` is the stream number;
  `LIST rec ` groups may nest in it. A chunk of odd size is followed by one pad byte.
- A zero-length or null video chunk repeats the previous picture.

## Indeo 5 video
Indeo 5 is Intel's 1990s wavelet codec. The picture is planar YUV 4:1:0. ffmpeg's `indeo5` decoder reads all 1402
frames of `intro.avi` and the 423 picture frames of `janes.avi`; it reports the 9 null frames at the end as
invalid data.
