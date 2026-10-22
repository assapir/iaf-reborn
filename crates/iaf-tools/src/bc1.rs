//! The terrain's colour tiles pre-compressed (docs/rendering.md §1.5): next to each `c_<x>_<y>.jpg` a
//! `c_<x>_<y>.dds`, BC1 with every mip down to 1×1, which the game loads without decoding or compressing.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use anyhow::{Context, Result};
use texpresso::{Algorithm, Format};

use crate::progress::{Progress, par_map};
use crate::thirdparty::{compress, mip_chain};

/// A DDS file (128-byte header, FourCC DXT1) holding `data`, the `mips` levels of a `w`×`h` BC1 image.
pub fn dds(w: u32, h: u32, mips: u32, data: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(128 + data.len());
    let mut put = |x: u32| v.extend_from_slice(&x.to_le_bytes());
    put(u32::from_le_bytes(*b"DDS "));
    put(124); // header size
    put(0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000); // CAPS HEIGHT WIDTH PIXELFORMAT MIPMAPCOUNT LINEARSIZE
    put(h);
    put(w);
    put(w.div_ceil(4) * h.div_ceil(4) * 8); // the top level's size
    put(0); // depth
    put(mips);
    (0..11).for_each(|_| put(0));
    put(32); // pixel format size
    put(0x4); // DDPF_FOURCC
    put(u32::from_le_bytes(*b"DXT1"));
    (0..5).for_each(|_| put(0)); // bit count, masks
    put(0x8 | 0x1000 | 0x400000); // COMPLEX TEXTURE MIPMAP
    (0..4).for_each(|_| put(0)); // caps2..4, reserved
    v.extend_from_slice(data);
    v
}

/// The `.dds` beside a tile.
pub fn dds_path(jpg: &Path) -> PathBuf {
    jpg.with_extension("dds")
}

/// True when `jpg`'s `.dds` is missing or older than it.
fn stale(jpg: &Path) -> bool {
    let t = |p: &Path| std::fs::metadata(p).and_then(|m| m.modified()).ok();
    match (t(jpg), t(&dds_path(jpg))) {
        (Some(j), Some(d)) => d < j,
        _ => true,
    }
}

/// Writes `jpg`'s `.dds` (through a temporary file, so a stopped run leaves no partial file).
pub fn tile(jpg: &Path) -> Result<()> {
    let img = image::open(jpg).with_context(|| format!("{}", jpg.display()))?.to_rgba8();
    let (w, h) = img.dimensions();
    let levels = mip_chain(img);
    let out = dds(w, h, levels.len() as u32, &compress(&levels, Format::Bc1, Algorithm::RangeFit, [1.0, 1.0, 1.0]));
    let dest = dds_path(jpg);
    let tmp = dest.with_extension("dds.tmp");
    std::fs::write(&tmp, out).with_context(|| format!("{}", tmp.display()))?;
    std::fs::rename(&tmp, &dest)?;
    Ok(())
}

/// Every colour tile (`L*/c_*.jpg`) under each of `dirs` whose `.dds` is missing or older; returns how many were
/// written (0: up to date).
pub fn trees(dirs: &[PathBuf], pr: &dyn Progress, cancel: &AtomicBool) -> Result<usize> {
    let mut todo = Vec::new();
    for d in dirs.iter().filter(|d| d.is_dir()) {
        let all = crate::walk_files(d)?;
        let tiles: Vec<PathBuf> = all
            .into_iter()
            .filter(|p| {
                let n = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
                n.starts_with("c_") && n.ends_with(".jpg")
            })
            .collect();
        let n = tiles.len();
        let before = todo.len();
        todo.extend(tiles.into_iter().filter(|p| stale(p)));
        pr.log(&format!("{}: {} tiles, {} to compress", d.display(), n, todo.len() - before));
    }
    let done = AtomicUsize::new(0);
    par_map(&todo, cancel, |p| {
        tile(p)?;
        let k = done.fetch_add(1, Ordering::Relaxed) + 1;
        pr.fraction(k as f32 / todo.len() as f32);
        if k.is_multiple_of(500) {
            pr.log(&format!("{k} of {}", todo.len()));
        }
        Ok(())
    })?;
    Ok(todo.len())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::progress::Stdout;

    #[test]
    fn dds_header_and_mips() {
        let dir = std::env::temp_dir().join(format!("iaf-bc1-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("L0")).unwrap();
        let jpg = dir.join("L0/c_1_2.jpg");
        image::RgbImage::from_fn(64, 64, |x, y| image::Rgb([x as u8 * 4, y as u8 * 4, 90])).save(&jpg).unwrap();
        let no = AtomicBool::new(false);
        assert_eq!(trees(std::slice::from_ref(&dir), &Stdout, &no).unwrap(), 1);
        let b = std::fs::read(dds_path(&jpg)).unwrap();
        let u = |o: usize| u32::from_le_bytes(b[o..o + 4].try_into().unwrap());
        assert_eq!(&b[..4], b"DDS ");
        assert_eq!((u(4), u(12), u(16), u(28)), (124, 64, 64, 7), "size, height, width, mips");
        assert_eq!(&b[84..88], b"DXT1");
        // 64² … 1²: 16×16, 8×8, 4×4, 2×2 and three 1-block levels of 8 bytes.
        assert_eq!(b.len(), 128 + 8 * (256 + 64 + 16 + 4 + 1 + 1 + 1));
        // Up to date: skipped; a newer tile: written again.
        assert_eq!(trees(std::slice::from_ref(&dir), &Stdout, &no).unwrap(), 0);
        let f = std::fs::File::options().write(true).open(&jpg).unwrap();
        f.set_modified(std::time::SystemTime::now() + std::time::Duration::from_secs(5)).unwrap();
        assert_eq!(trees(std::slice::from_ref(&dir), &Stdout, &no).unwrap(), 1);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
