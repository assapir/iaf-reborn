//! `iafjets.exe` as a PE image: virtual address → file offset, and which release it is.
//!
//! The release is told by the PE header's link time (TimeDateStamp), never by file size or path:
//! v1.0 was linked 1998-08-12, the v1.1 patch's full rebuild 1998-11-09 (docs/formats/rtpatch.md,
//! docs/v1.1.md). Any other exe is rejected, so a caller never reads one release's addresses in the
//! other's image.

use std::path::Path;

use anyhow::{Context, Result, bail};

/// An `iafjets.exe` release.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Release {
    V10,
    V11,
}

impl Release {
    /// PE TimeDateStamp of each release's `iafjets.exe`.
    pub const LINK_TIME: [(u32, Release); 2] = [(0x35d1_73f4, Release::V10), (0x3646_a9a3, Release::V11)];

    pub fn name(self) -> &'static str {
        match self {
            Release::V10 => "v1.0",
            Release::V11 => "v1.1",
        }
    }
}

/// A PE file with its section table (virtual address → file offset).
pub struct PeImage {
    pub data: Vec<u8>,
    /// PE header TimeDateStamp (link time, seconds since 1970).
    pub link_time: u32,
    /// Image base and the resource directory RVA (optional header data directory 2).
    base: u32,
    resource_rva: u32,
    sections: Vec<(u32, u32, u32)>, // (va, raw size, raw offset)
}

impl PeImage {
    pub fn load(path: &Path) -> Result<Self> {
        let data = std::fs::read(path).with_context(|| format!("reading {}", path.display()))?;
        Self::parse(data).with_context(|| path.display().to_string())
    }

    pub fn parse(data: Vec<u8>) -> Result<Self> {
        let u16_at = |o: usize| -> Result<usize> {
            Ok(u16::from_le_bytes(data.get(o..o + 2).context("truncated PE")?.try_into().unwrap()) as usize)
        };
        let u32_at = |o: usize| -> Result<u32> {
            Ok(u32::from_le_bytes(data.get(o..o + 4).context("truncated PE")?.try_into().unwrap()))
        };
        let pe = u32_at(0x3c)? as usize;
        if data.get(pe..pe + 4) != Some(b"PE\0\0") {
            bail!("not a PE file");
        }
        let count = u16_at(pe + 6)?;
        let link_time = u32_at(pe + 8)?;
        let base = u32_at(pe + 24 + 28)?;
        let table = pe + 24 + u16_at(pe + 20)?;
        let sections = (0..count)
            .map(|i| {
                let s = table + i * 40;
                Ok((base + u32_at(s + 12)?, u32_at(s + 16)?, u32_at(s + 20)?))
            })
            .collect::<Result<_>>()?;
        let resource_rva = u32_at(pe + 24 + 96 + 2 * 8)?;
        Ok(Self { data, link_time, base, resource_rva, sections })
    }

    /// The `iafjets.exe` release this image is; an error for any other exe.
    pub fn release(&self) -> Result<Release> {
        Release::LINK_TIME
            .iter()
            .find(|(t, _)| *t == self.link_time)
            .map(|&(_, r)| r)
            .with_context(|| format!("not a known iafjets.exe (v1.0 or v1.1): PE link time {:#x}", self.link_time))
    }

    pub fn offset(&self, va: u32) -> Option<usize> {
        self.sections
            .iter()
            .find(|(start, size, _)| va >= *start && va < start + size)
            .map(|(start, _, raw)| (raw + va - start) as usize)
    }

    pub fn i32_at(&self, va: u32) -> Result<i32> {
        let o = self.offset(va).with_context(|| format!("address {va:#x} not in the file"))?;
        Ok(i32::from_le_bytes(self.data[o..o + 4].try_into().unwrap()))
    }

    /// The NUL-terminated bytes at `va` (without the NUL).
    pub fn cstr(&self, va: u32) -> Result<&[u8]> {
        let o = self.offset(va).with_context(|| format!("address {va:#x} not in the file"))?;
        let end = self.data[o..].iter().position(|&c| c == 0).context("unterminated string")?;
        Ok(&self.data[o..o + end])
    }
}

impl PeImage {
    /// The icon images in the resources (RT_ICON, type 3) as RGBA, largest first. Supports the 1/4/8/24/32-bit
    /// DIBs icons use (height doubled: colour bitmap, then the 1-bit AND mask).
    pub fn icons(&self) -> Result<Vec<image::RgbaImage>> {
        let d = &self.data;
        let root = self.offset(self.base + self.resource_rva).context("no resources")?;
        let u16a = |o: usize| u16::from_le_bytes([d[o], d[o + 1]]) as usize;
        let u32a = |o: usize| u32::from_le_bytes(d[o..o + 4].try_into().unwrap());
        // Directory entries: (id, offset relative to the resource root, is_dir).
        let entries = |dir: usize| -> Vec<(u32, usize, bool)> {
            let n = u16a(dir + 12) + u16a(dir + 14);
            (0..n)
                .map(|i| {
                    let e = dir + 16 + i * 8;
                    let off = u32a(e + 4);
                    (u32a(e), (off & 0x7fff_ffff) as usize, off & 0x8000_0000 != 0)
                })
                .collect()
        };
        let mut out = Vec::new();
        for (ty, off, is_dir) in entries(root) {
            if ty != 3 || !is_dir {
                continue;
            }
            for (_, id_off, _) in entries(root + off) {
                for (_, lang_off, leaf_dir) in entries(root + id_off) {
                    if leaf_dir {
                        continue;
                    }
                    let leaf = root + lang_off;
                    let (rva, size) = (u32a(leaf), u32a(leaf + 4) as usize);
                    let Some(o) = self.offset(self.base + rva) else { continue };
                    if let Some(img) = dib_icon(&d[o..(o + size).min(d.len())]) {
                        out.push(img);
                    }
                }
            }
        }
        out.sort_by_key(|i| std::cmp::Reverse(i.width() * i.height()));
        Ok(out)
    }
}

fn dib_icon(b: &[u8]) -> Option<image::RgbaImage> {
    let u16a = |o: usize| u16::from_le_bytes([b[o], b[o + 1]]) as u32;
    let u32a = |o: usize| u32::from_le_bytes(b[o..o + 4].try_into().unwrap());
    let hdr = u32a(0) as usize;
    let (w, h, bpp) = (u32a(4), u32a(8) / 2, u16a(14));
    let colours = match u32a(32) { 0 if bpp <= 8 => 1usize << bpp, n => n as usize };
    let pal = hdr;
    let xor = pal + if bpp <= 8 { colours * 4 } else { 0 };
    let row = |bits: u32| ((w * bits).div_ceil(32) * 4) as usize;
    let and = xor + row(bpp) * h as usize;
    if b.len() < and + row(1) * h as usize {
        return None;
    }
    let mut img = image::RgbaImage::new(w, h);
    for y in 0..h {
        let src = (h - 1 - y) as usize; // bottom-up
        for x in 0..w {
            let px = |i: usize| -> [u8; 4] { [b[pal + i * 4 + 2], b[pal + i * 4 + 1], b[pal + i * 4], 255] };
            let r = xor + src * row(bpp);
            let mut c = match bpp {
                1 => px(((b[r + x as usize / 8] >> (7 - x % 8)) & 1) as usize),
                4 => px(((b[r + x as usize / 2] >> if x % 2 == 0 { 4 } else { 0 }) & 15) as usize),
                8 => px(b[r + x as usize] as usize),
                24 => { let o = r + x as usize * 3; [b[o + 2], b[o + 1], b[o], 255] }
                32 => { let o = r + x as usize * 4; [b[o + 2], b[o + 1], b[o], b[o + 3]] }
                _ => return None,
            };
            let m = and + src * row(1);
            if bpp != 32 && (b[m + x as usize / 8] >> (7 - x % 8)) & 1 == 1 {
                c[3] = 0;
            }
            img.put_pixel(x, y, image::Rgba(c));
        }
    }
    Some(img)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The real exes, when present: v1.0 in `assets/v1.0` (kept by tools/setup.sh when it patches)
    /// or an unpatched `assets/install`, v1.1 in `assets/v1.1` (the `iaf-patch` output).
    #[test]
    fn releases_of_the_real_exes() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        let mut seen = vec![];
        for p in ["v1.0/iafjets.exe", "install/iafjets.exe", "v1.1/iafjets.exe"] {
            let Ok(exe) = PeImage::load(&root.join(p)) else { continue };
            let r = exe.release().unwrap();
            if p.starts_with("v1.") {
                assert_eq!(r.name(), &p[..4], "{p}");
            }
            seen.push(r);
        }
        if seen.is_empty() {
            eprintln!("skipped: no iafjets.exe under assets/");
        }
    }

    #[test]
    fn unknown_exe_is_rejected() {
        // Minimal PE: header at 0x40, no sections, link time 1.
        let mut d = vec![0u8; 0x100];
        d[0x3c] = 0x40;
        d[0x40..0x44].copy_from_slice(b"PE\0\0");
        d[0x48] = 1;
        let exe = PeImage::parse(d).unwrap();
        assert!(exe.release().is_err());
        assert!(PeImage::parse(vec![0; 0x80]).is_err());
    }
}
