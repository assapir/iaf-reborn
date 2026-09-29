//! Windows raster fonts (`.FNT`, version 2.0/3.0), used for the HUD, MFD and key labels
//! (`resource/menu/fnt/{hud,mfd,key}.fnt`).
//!
//! Layout: 118-byte header (v2; v3 adds 30 bytes), then a character table of
//! `last - first + 2` entries `{u16 width, u16 offset}` (v3: `u16 width, u32 offset`), then
//! glyph bitmaps stored column-strip by column-strip: for each 8-pixel-wide strip, `height`
//! bytes top to bottom (MSB = leftmost pixel).

use crate::Error;

#[derive(Debug, Clone)]
pub struct Glyph {
    pub code: u32,
    pub width: u32,
    /// Row-major coverage, `width × height`, 0 or 255.
    pub pixels: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct WinFont {
    pub face: String,
    pub height: u32,
    pub ascent: u32,
    pub glyphs: Vec<Glyph>,
}

fn u16_at(d: &[u8], at: usize) -> Result<u32, Error> {
    d.get(at..at + 2).map(|b| u16::from_le_bytes([b[0], b[1]]) as u32).ok_or_else(|| Error::Format("FNT truncated".into()))
}

fn u32_at(d: &[u8], at: usize) -> Result<u32, Error> {
    d.get(at..at + 4).map(|b| u32::from_le_bytes(b.try_into().unwrap())).ok_or_else(|| Error::Format("FNT truncated".into()))
}

pub fn parse(d: &[u8]) -> Result<WinFont, Error> {
    let version = u16_at(d, 0)?;
    if version != 0x200 && version != 0x300 {
        return Err(Error::Format(format!("FNT version {version:#x} not supported")));
    }
    let ascent = u16_at(d, 74)?;
    let height = u16_at(d, 88)?;
    let pix_width = u16_at(d, 86)?;
    let first = *d.get(95).ok_or_else(|| Error::Format("FNT truncated".into()))? as u32;
    let last = *d.get(96).ok_or_else(|| Error::Format("FNT truncated".into()))? as u32;
    let face_off = u32_at(d, 105)? as usize;
    let face = d.get(face_off..).map(|f| f.split(|&c| c == 0).next().unwrap_or(&[])).unwrap_or(&[]);
    let face = String::from_utf8_lossy(face).to_string();
    let (table, entry) = if version == 0x200 { (118, 4) } else { (148, 6) };
    let mut glyphs = Vec::new();
    for (i, code) in (first..=last).enumerate() {
        let at = table + i * entry;
        let width = if pix_width != 0 { u16_at(d, at)?.max(pix_width) } else { u16_at(d, at)? };
        let offset = if version == 0x200 { u16_at(d, at + 2)? } else { u32_at(d, at + 2)? } as usize;
        let mut pixels = vec![0u8; (width * height) as usize];
        for strip in 0..width.div_ceil(8) {
            for y in 0..height {
                let byte = *d.get(offset + (strip * height + y) as usize).unwrap_or(&0);
                for bit in 0..8 {
                    let x = strip * 8 + bit;
                    if x < width && byte & (0x80 >> bit) != 0 {
                        pixels[(y * width + x) as usize] = 255;
                    }
                }
            }
        }
        glyphs.push(Glyph { code, width, pixels });
    }
    Ok(WinFont { face, height, ascent, glyphs })
}
