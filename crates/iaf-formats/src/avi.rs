//! AVI (RIFF) demuxer: the first video and first audio stream, as byte ranges into the file.

use crate::bytes::{u16_at, u32_at};
use crate::Error;
use std::ops::Range;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioFormat {
    pub format_tag: u16,
    pub channels: u16,
    pub rate: u32,
    pub bits: u16,
}

#[derive(Debug, Clone, Default)]
pub struct Avi {
    pub width: u32,
    pub height: u32,
    pub us_per_frame: u32,
    /// Video codec FourCC (BITMAPINFOHEADER compression), e.g. `IV50`.
    pub fourcc: [u8; 4],
    pub audio: Option<AudioFormat>,
    /// Video chunks in order; an empty range repeats the previous frame.
    pub video: Vec<Range<usize>>,
    pub audio_chunks: Vec<Range<usize>>,
}

#[derive(Default)]
struct State {
    avi: Avi,
    /// Kind of each stream in `strl` order: b'v', b'a' or 0.
    streams: Vec<u8>,
    video_no: Option<usize>,
    audio_no: Option<usize>,
}

fn bad(msg: &str) -> Error {
    Error::Format(format!("avi: {msg}"))
}

fn walk(d: &[u8], mut pos: usize, end: usize, st: &mut State) -> Result<(), Error> {
    while pos + 8 <= end {
        let id: [u8; 4] = d[pos..pos + 4].try_into().unwrap();
        let size = u32_at(d, pos + 4)? as usize;
        let body = pos + 8;
        let body_end = body.checked_add(size).ok_or_else(|| bad("chunk size"))?;
        if body_end > d.len() {
            // A truncated last chunk ends the walk, as players do.
            return Ok(());
        }
        match &id {
            b"LIST" | b"RIFF" => {
                if size < 4 {
                    return Err(bad("short LIST"));
                }
                let kind = &d[body..body + 4];
                if matches!(kind, b"hdrl" | b"strl" | b"movi" | b"rec ") {
                    if kind == b"strl" {
                        st.streams.push(0);
                    }
                    walk(d, body + 4, body_end, st)?;
                }
            }
            b"avih" => st.avi.us_per_frame = u32_at(d, body)?,
            b"strh" => {
                let kind = match &d[body..body + 4] {
                    b"vids" => b'v',
                    b"auds" => b'a',
                    _ => 0,
                };
                if let Some(last) = st.streams.last_mut() {
                    *last = kind;
                    let no = st.streams.len() - 1;
                    if kind == b'v' && st.video_no.is_none() {
                        st.video_no = Some(no);
                    }
                    if kind == b'a' && st.audio_no.is_none() {
                        st.audio_no = Some(no);
                    }
                }
            }
            b"strf" => match st.streams.last() {
                Some(b'v') if st.video_no == Some(st.streams.len() - 1) => {
                    st.avi.width = u32_at(d, body + 4)?;
                    st.avi.height = u32_at(d, body + 8)?;
                    st.avi.fourcc = d.get(body + 16..body + 20).ok_or_else(|| bad("strf"))?.try_into().unwrap();
                }
                Some(b'a') if st.audio_no == Some(st.streams.len() - 1) => {
                    st.avi.audio = Some(AudioFormat {
                        format_tag: u16_at(d, body)?,
                        channels: u16_at(d, body + 2)?,
                        rate: u32_at(d, body + 4)?,
                        bits: u16_at(d, body + 14)?,
                    });
                }
                _ => {}
            },
            _ => {
                // Stream data chunk "NNxx".
                if let (Ok(no), tag) = (std::str::from_utf8(&id[..2]).unwrap_or("").parse::<usize>(), &id[2..]) {
                    if Some(no) == st.video_no && (tag == b"dc" || tag == b"db") {
                        st.avi.video.push(body..body_end);
                    } else if Some(no) == st.audio_no && tag == b"wb" {
                        st.avi.audio_chunks.push(body..body_end);
                    }
                }
            }
        }
        pos = body_end + (size & 1);
    }
    Ok(())
}

pub fn parse(data: &[u8]) -> Result<Avi, Error> {
    if data.len() < 12 || &data[..4] != b"RIFF" || &data[8..12] != b"AVI " {
        return Err(bad("not a RIFF AVI file"));
    }
    let mut st = State::default();
    walk(data, 12, data.len(), &mut st)?;
    if st.video_no.is_none() {
        return Err(bad("no video stream"));
    }
    Ok(st.avi)
}

impl Avi {
    pub fn frame_count(&self) -> usize {
        self.video.len()
    }

    /// All audio chunks concatenated (raw PCM for format tag 1).
    pub fn audio_pcm(&self, data: &[u8]) -> Vec<u8> {
        self.audio_chunks.iter().flat_map(|r| data[r.clone()].iter().copied()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chunk(id: &[u8; 4], body: &[u8]) -> Vec<u8> {
        let mut v = id.to_vec();
        v.extend((body.len() as u32).to_le_bytes());
        v.extend(body);
        if body.len() & 1 == 1 {
            v.push(0);
        }
        v
    }

    fn list(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
        let mut b = kind.to_vec();
        b.extend(body);
        chunk(b"LIST", &b)
    }

    #[test]
    fn synthetic() {
        let mut avih = vec![0u8; 56];
        avih[..4].copy_from_slice(&66667u32.to_le_bytes());
        let mut strh_v = vec![0u8; 56];
        strh_v[..4].copy_from_slice(b"vids");
        let mut strf_v = vec![0u8; 40];
        strf_v[4..8].copy_from_slice(&320u32.to_le_bytes());
        strf_v[8..12].copy_from_slice(&240u32.to_le_bytes());
        strf_v[16..20].copy_from_slice(b"IV50");
        let mut strh_a = vec![0u8; 56];
        strh_a[..4].copy_from_slice(b"auds");
        let mut strf_a = vec![0u8; 16];
        strf_a[..2].copy_from_slice(&1u16.to_le_bytes());
        strf_a[2..4].copy_from_slice(&2u16.to_le_bytes());
        strf_a[4..8].copy_from_slice(&22050u32.to_le_bytes());
        strf_a[14..16].copy_from_slice(&8u16.to_le_bytes());

        let strl_v = list(b"strl", &[chunk(b"strh", &strh_v), chunk(b"strf", &strf_v)].concat());
        let strl_a = list(b"strl", &[chunk(b"strh", &strh_a), chunk(b"strf", &strf_a)].concat());
        let hdrl = list(b"hdrl", &[chunk(b"avih", &avih), strl_v, strl_a].concat());
        let rec = list(b"rec ", &[chunk(b"01wb", &[9, 9, 9]), chunk(b"00dc", &[]), chunk(b"JUNK", &[0])].concat());
        let movi = list(b"movi", &[chunk(b"00dc", &[1, 2, 3]), chunk(b"01wb", &[4, 5]), rec].concat());
        let mut body = b"AVI ".to_vec();
        body.extend([hdrl, movi].concat());
        let file = chunk(b"RIFF", &body);

        let avi = parse(&file).unwrap();
        assert_eq!((avi.width, avi.height, avi.us_per_frame), (320, 240, 66667));
        assert_eq!(&avi.fourcc, b"IV50");
        assert_eq!(avi.audio, Some(AudioFormat { format_tag: 1, channels: 2, rate: 22050, bits: 8 }));
        assert_eq!(avi.frame_count(), 2);
        assert_eq!(&file[avi.video[0].clone()], &[1, 2, 3]);
        assert!(avi.video[1].is_empty());
        assert_eq!(avi.audio_pcm(&file), vec![4, 5, 9, 9, 9]);
    }

    #[test]
    fn rejects_garbage() {
        assert!(parse(b"not an avi at all").is_err());
    }
}
