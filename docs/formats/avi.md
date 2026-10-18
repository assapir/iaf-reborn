# Intro videos — AVI with Indeo 5 video

The CD's `Resource\Avi` holds the two videos the exe plays at start-up (front-end.md §18.2). `iaf-extract` copies them
to `assets/install/resource/avi/`.

| file | length | video chunks | picture | sound |
|---|---|---|---|---|
| `janes.avi` | 28.8 s | 432 (the last 9 are 2-byte null frames) | Indeo 5 (`IV50`), 320×240, 15 fps | PCM 8-bit unsigned, stereo, 22 050 Hz |
| `intro.avi` | 93.5 s | 1402 | Indeo 5 (`IV50`), 320×240, 15 fps | PCM 8-bit unsigned, stereo, 22 050 Hz |

## AVI container
A RIFF file (`RIFF` size `AVI `), little-endian. Parser: `crates/iaf-formats/src/avi.rs`.

- `LIST hdrl`: `avih` (`dwMicroSecPerFrame` at offset 0: 66 666 µs = 15 fps), then one `LIST strl` per stream with
  `strh` (type `vids` / `auds`) and `strf` (video: a `BITMAPINFOHEADER`, width, height and the codec FourCC `IV50`;
  sound: a `WAVEFORMATEX`).
- `LIST movi`: the data chunks, `##dc` / `##db` for video and `##wb` for sound, where `##` is the stream number;
  `LIST rec ` groups may nest in it. A chunk of odd size is followed by one pad byte.
- A zero-length or null video chunk repeats the previous picture.

## Indeo 5 decoder
`crates/iaf-indeo` decodes the video at run time, frame by frame (about 0.3 ms per frame, release build). It is a port
of the Indeo 5 decoder of [NihAV](https://nihav.org) (Kostya Shishkov; snapshot commit 7552f86) and keeps NihAV's
licence, the GNU AGPL v3 or later (`crates/iaf-indeo/COPYING`), in a crate of its own; the rest of the repository is
GPL v3 or later, and GPLv3 §13 allows the combination.

Why a run-time decoder: Godot plays only Ogg Theora video, and the setup must not need ffmpeg to convert the files.
Decoding the original files at run time keeps the CD's videos as they are and needs no converted copy. The port keeps
only Indeo 5's paths (no Indeo 4, bidirectional, scalable or transparency code) and pads each wavelet band by one
replicated row and column so the picture's last two rows and columns decode too.

Checks against ffmpeg's decoder (`yuv410p`, all frames): every frame of `intro.avi` is identical. Of `janes.avi`'s
423 non-null frames, 412 are identical and 11 (stream frames 10–14, 16, 17, 94, 95, 97, 98) differ at 25–41 dB PSNR,
where motion vectors point outside a tile; UNCERTAIN which decoder matches Intel's there. The errors do not carry
on to later frames.

The picture is planar YUV 4:1:0; `Frame::to_rgb` converts it with BT.601 limited-range coefficients.
Tests: `crates/iaf-indeo/tests/avi_decode.rs` (frame counts, 320×240, every frame decodes, a checksum of frame 100),
`tests/godot/test_startup.gd`.
