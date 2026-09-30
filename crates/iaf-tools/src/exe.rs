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
        Ok(Self { data, link_time, sections })
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
