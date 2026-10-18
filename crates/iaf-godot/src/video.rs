//! `IafVideo`: an AVI (iaf_formats::avi) with Indeo 5 video (iaf_indeo) for `menu/startup.gd`, the intro videos
//! (docs/front-end.md §18.2, docs/formats/avi.md). Frames decode on demand in order; the sound is handed over whole.

use godot::prelude::*;
use iaf_formats::avi::{self, Avi};
use iaf_indeo::Decoder;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafVideo {
    data: Vec<u8>,
    avi: Option<Avi>,
    decoder: Option<Decoder>,
    /// The last frame decoded (-1 none) and its RGB pixels.
    last: i64,
    rgb: Vec<u8>,
}

#[godot_api]
impl IafVideo {
    /// Opens an AVI with IV50 video; false when the file is missing, not an AVI or another codec.
    #[func]
    fn open(&mut self, path: GString) -> bool {
        let Ok(data) = std::fs::read(path.to_string()) else { return false };
        let Ok(a) = avi::parse(&data) else { return false };
        if !a.fourcc.eq_ignore_ascii_case(b"IV50") {
            return false;
        }
        self.data = data;
        self.avi = Some(a);
        self.decoder = None;
        self.last = -1;
        true
    }

    #[func]
    fn frame_count(&self) -> i64 {
        self.avi.as_ref().map_or(0, |a| a.frame_count() as i64)
    }

    #[func]
    fn width(&self) -> i64 {
        self.avi.as_ref().map_or(0, |a| a.width as i64)
    }

    #[func]
    fn height(&self) -> i64 {
        self.avi.as_ref().map_or(0, |a| a.height as i64)
    }

    #[func]
    fn fps(&self) -> f64 {
        self.avi.as_ref().map_or(0.0, |a| 1e6 / a.us_per_frame.max(1) as f64)
    }

    /// Frame `i` as RGB8 (width × height × 3). Decodes forward from the last frame (from the start when `i` is
    /// earlier); a frame that fails to decode keeps the previous picture.
    #[func]
    fn frame_rgb(&mut self, i: i64) -> PackedByteArray {
        let Some(a) = &self.avi else { return PackedByteArray::new() };
        let i = i.clamp(0, a.frame_count() as i64 - 1);
        if i < self.last || self.decoder.is_none() {
            self.decoder = Some(Decoder::new());
            self.last = -1;
        }
        let dec = self.decoder.as_mut().unwrap();
        while self.last < i {
            self.last += 1;
            if let Ok(f) = dec.decode(&self.data[a.video[self.last as usize].clone()]) {
                f.to_rgb(&mut self.rgb);
            }
        }
        if self.rgb.is_empty() {
            self.rgb = vec![0; (a.width * a.height * 3) as usize];
        }
        PackedByteArray::from(self.rgb.as_slice())
    }

    /// The whole sound track as signed 16-bit little-endian PCM (8-bit sources widened); empty when there is none.
    #[func]
    fn audio_pcm16(&self) -> PackedByteArray {
        let Some(a) = &self.avi else { return PackedByteArray::new() };
        let Some(f) = &a.audio else { return PackedByteArray::new() };
        let pcm = a.audio_pcm(&self.data);
        let out: Vec<u8> = match (f.format_tag, f.bits) {
            (1, 8) => pcm.iter().flat_map(|&b| (((b as i16) - 128) << 8).to_le_bytes()).collect(),
            (1, 16) => pcm,
            _ => Vec::new(),
        };
        PackedByteArray::from(out)
    }

    #[func]
    fn audio_rate(&self) -> i64 {
        self.avi.as_ref().and_then(|a| a.audio.as_ref()).map_or(0, |f| f.rate as i64)
    }

    #[func]
    fn audio_channels(&self) -> i64 {
        self.avi.as_ref().and_then(|a| a.audio.as_ref()).map_or(0, |f| f.channels as i64)
    }
}
