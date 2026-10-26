//! The scenery trees' foliage textures (docs/scenery.md §3.2), made by setup from the ambientCG CC0 leaf sets of
//! `thirdparty::TREE_TEXTURES` (their colour and opacity maps, kept by `thirdparty::fetch`). A single leaf is under a
//! pixel from a jet, so each texture is a clump of hundreds of scattered leaves or sprigs, drawn back to front with the
//! back ones darker (the clump's own shade), or a palm frond of leaflets along a rib:
//!
//! | Layer | From | What |
//! |---|---|---|
//! | 0 broadleaf | LeafSet001 | a lumpy clump of small elliptic leaves (olive, carob, oak), a card about 2.5 m wide |
//! | 1 conifer | LeafSet019 | a clump of needle sprigs radiating from its centre (pine, cypress) |
//! | 2 palm | Foliage001 | one frond: leaflets on both sides of a rib, base at the bottom (v = 1), tip at the top |
//! | 3 bark | Bark012 | the bark, opaque, tiling |
//!
//! Each layer is `SIDE`² with every mip level, BC3 (DXT5): RGB = the linear colour over the layer's mean, halved (the
//! game multiplies its tree colour by twice it, as the walls' detail), A = coverage. A mip level's alpha is scaled so
//! that as many texels pass the game's 0.5 cut as on the full level: a distant crown keeps its density instead of
//! thinning out. The same files give the same bytes (a seeded generator).

use std::path::Path;

use anyhow::{Context, Result};
use image::{GrayImage, RgbaImage, imageops::FilterType};
use serde_json::json;
use texpresso::{Algorithm, Format};

use crate::thirdparty::{SIDE, TREE_TEXTURES, compress, mip_chain};

/// The layers' file names under `<dir>/trees/`, in the texture array's order.
pub const LAYERS: [&str; 4] = ["broadleaf", "conifer", "palm", "bark"];
/// The composition's version: `foliage.json` records it, and another version is made again.
pub const VERSION: u32 = 1;

/// A seeded generator (SplitMix64).
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }
    /// In [0, 1).
    fn f(&mut self) -> f32 {
        (self.next() >> 40) as f32 / (1u64 << 24) as f32
    }
    /// In [a, b).
    fn in_range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.f()
    }
}

fn linear(v: u8) -> f32 {
    let c = f32::from(v) / 255.0;
    if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
}

/// A sprite: linear RGB, premultiplied by its coverage A, its long side along x.
struct Sprite {
    w: usize,
    h: usize,
    px: Vec<[f32; 4]>,
}

impl Sprite {
    /// Bilinear, transparent outside.
    fn sample(&self, x: f32, y: f32) -> [f32; 4] {
        let (x, y) = (x - 0.5, y - 0.5);
        let (x0, y0) = (x.floor(), y.floor());
        let (fx, fy) = (x - x0, y - y0);
        let mut out = [0.0; 4];
        for (dx, dy, wt) in
            [(0, 0, (1.0 - fx) * (1.0 - fy)), (1, 0, fx * (1.0 - fy)), (0, 1, (1.0 - fx) * fy), (1, 1, fx * fy)]
        {
            let (sx, sy) = (x0 as i64 + dx, y0 as i64 + dy);
            if sx >= 0 && sy >= 0 && (sx as usize) < self.w && (sy as usize) < self.h {
                let p = self.px[sy as usize * self.w + sx as usize];
                (0..4).for_each(|c| out[c] += p[c] * wt);
            }
        }
        out
    }
}

/// The separate leaves (sprigs, blades) of a leaf set: the connected areas of `opacity` over half, at least a fifth of
/// the largest's size, each cut out with its own coverage, turned so its long side lies along x and scaled so that
/// side is `len` pixels.
fn sprites(colour: &RgbaImage, opacity: &GrayImage, len: f32) -> Vec<Sprite> {
    let (w, h) = (opacity.width() as usize, opacity.height() as usize);
    let mut label = vec![0u32; w * h];
    let mut areas: Vec<(u32, [usize; 4], usize)> = Vec::new(); // (label, bbox x0 y0 x1 y1, size)
    let mut stack = Vec::new();
    for start in 0..w * h {
        if label[start] != 0 || opacity.as_raw()[start] < 128 {
            continue;
        }
        let id = areas.len() as u32 + 1;
        let (mut bb, mut n) = ([usize::MAX, usize::MAX, 0, 0], 0);
        label[start] = id;
        stack.push(start);
        while let Some(i) = stack.pop() {
            let (x, y) = (i % w, i / w);
            bb = [bb[0].min(x), bb[1].min(y), bb[2].max(x), bb[3].max(y)];
            n += 1;
            for (nx, ny) in [(x.wrapping_sub(1), y), (x + 1, y), (x, y.wrapping_sub(1)), (x, y + 1)] {
                if nx < w && ny < h && label[ny * w + nx] == 0 && opacity.as_raw()[ny * w + nx] >= 128 {
                    label[ny * w + nx] = id;
                    stack.push(ny * w + nx);
                }
            }
        }
        areas.push((id, bb, n));
    }
    let big = areas.iter().map(|a| a.2).max().unwrap_or(0);
    let mut out = Vec::new();
    for (id, [x0, y0, x1, y1], n) in areas {
        if n * 5 < big {
            continue;
        }
        // The cut-out at full size (the area's own pixels only, a 2 px margin for the soft edge), sRGB.
        let (x0, y0, x1, y1) = (x0.saturating_sub(2), y0.saturating_sub(2), (x1 + 2).min(w - 1), (y1 + 2).min(h - 1));
        let tall = y1 - y0 > x1 - x0;
        let crop = RgbaImage::from_fn((x1 - x0 + 1) as u32, (y1 - y0 + 1) as u32, |cx, cy| {
            let (x, y) = (x0 + cx as usize, y0 + cy as usize);
            let near = (y.saturating_sub(2)..=(y + 2).min(h - 1))
                .any(|yy| (x.saturating_sub(2)..=(x + 2).min(w - 1)).any(|xx| label[yy * w + xx] == id));
            let c = colour.get_pixel(x as u32, y as u32).0;
            image::Rgba([c[0], c[1], c[2], if near { opacity.get_pixel(x as u32, y as u32).0[0] } else { 0 }])
        });
        let crop = if tall { image::imageops::rotate90(&crop) } else { crop };
        let k = len / crop.width() as f32;
        let (sw, sh) = (len.round().max(1.0) as u32, (crop.height() as f32 * k).round().max(1.0) as u32);
        // Premultiplied before the scaling, so the transparent texels' colour does not bleed in.
        let mut pre = image::Rgba32FImage::new(crop.width(), crop.height());
        for (p, q) in pre.pixels_mut().zip(crop.pixels()) {
            let a = f32::from(q.0[3]) / 255.0;
            p.0 = [linear(q.0[0]) * a, linear(q.0[1]) * a, linear(q.0[2]) * a, a];
        }
        let small = image::imageops::resize(&pre, sw, sh, FilterType::Triangle);
        out.push(Sprite { w: sw as usize, h: sh as usize, px: small.pixels().map(|p| p.0).collect() });
    }
    out
}

/// A premultiplied linear canvas, `SIDE`².
struct Canvas {
    n: usize,
    px: Vec<[f32; 4]>,
}

impl Canvas {
    fn new() -> Self {
        let n = SIDE as usize;
        Canvas { n, px: vec![[0.0; 4]; n * n] }
    }

    /// `s` drawn over the canvas centred at (cx, cy) (pixels), its x axis turned to `angle` (radians, y down), scaled
    /// by (sx, sy), its colour times `tint`.
    fn stamp(&mut self, s: &Sprite, at: [f32; 2], angle: f32, scale: [f32; 2], tint: [f32; 3]) {
        let (sn, cs) = angle.sin_cos();
        let (hw, hh) = (s.w as f32 * scale[0] / 2.0, s.h as f32 * scale[1] / 2.0);
        let r = (hw * hw + hh * hh).sqrt().ceil() + 1.0;
        let n = self.n as i64;
        let (xa, xb) = (((at[0] - r) as i64).max(0), ((at[0] + r) as i64).min(n - 1));
        let (ya, yb) = (((at[1] - r) as i64).max(0), ((at[1] + r) as i64).min(n - 1));
        for y in ya..=yb {
            for x in xa..=xb {
                let (dx, dy) = (x as f32 + 0.5 - at[0], y as f32 + 0.5 - at[1]);
                // Into the sprite's frame.
                let (u, v) = ((dx * cs + dy * sn) / scale[0], (-dx * sn + dy * cs) / scale[1]);
                let p = s.sample(u + s.w as f32 / 2.0, v + s.h as f32 / 2.0);
                if p[3] <= 0.0 {
                    continue;
                }
                let d = &mut self.px[y as usize * self.n + x as usize];
                let k = 1.0 - p[3];
                for c in 0..3 {
                    d[c] = p[c] * tint[c] + d[c] * k;
                }
                d[3] = p[3] + d[3] * k;
            }
        }
    }

    /// The finished layer: RGB = colour / the covered texels' mean, halved; the uncovered texels at the mean (no dark
    /// fringe in the mips); A = coverage.
    fn finish(&self) -> RgbaImage {
        let mut mean = [0f64; 3];
        let mut n = 0f64;
        for p in &self.px {
            if p[3] >= 0.5 {
                (0..3).for_each(|c| mean[c] += f64::from(p[c] / p[3]));
                n += 1.0;
            }
        }
        let mean = mean.map(|m| (m / n.max(1.0)).max(1e-4) as f32);
        let mut out = RgbaImage::new(SIDE, SIDE);
        for (q, p) in out.pixels_mut().zip(&self.px) {
            let a = p[3].clamp(0.0, 1.0);
            // The brightness over its mean, with a third of each channel's own deviation (the hue's variation; a
            // full per-channel ratio would blow a green leaf's little red up into magenta).
            let lum = |v: [f32; 3]| 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
            let rgb = if a > 0.02 {
                let c = [p[0] / p[3], p[1] / p[3], p[2] / p[3]];
                let l = lum(c) / lum(mean);
                [0, 1, 2].map(|k| l * (1.0 + CHROMA * (c[k] / mean[k] / l - 1.0)) * 0.5)
            } else {
                [0.5; 3]
            };
            let b = |v: f32| (v * 255.0).round().clamp(0.0, 255.0) as u8;
            q.0 = [b(rgb[0]), b(rgb[1]), b(rgb[2]), b(a)];
        }
        out
    }
}

/// How much of each channel's own deviation from the brightness a layer keeps.
const CHROMA: f32 = 0.33;

/// The share of texels whose alpha passes the 0.5 cut.
fn coverage(img: &RgbaImage) -> f32 {
    img.pixels().filter(|p| p.0[3] >= 128).count() as f32 / (img.width() * img.height()) as f32
}

/// Every level's alpha scaled so its coverage matches the full level's (a binary search on the scale).
pub fn keep_coverage(levels: &mut [RgbaImage]) {
    let Some(want) = levels.first().map(coverage) else { return };
    for l in levels.iter_mut().skip(1) {
        let src = l.clone();
        let scaled = |k: f32| {
            let mut t = src.clone();
            t.pixels_mut().for_each(|p| p.0[3] = (f32::from(p.0[3]) * k).round().min(255.0) as u8);
            t
        };
        let (mut lo, mut hi) = (0.25f32, 4.0f32);
        for _ in 0..16 {
            let mid = (lo * hi).sqrt();
            if coverage(&scaled(mid)) < want { lo = mid } else { hi = mid }
        }
        *l = scaled((lo * hi).sqrt());
    }
}

/// A point in the clump: inside the union of `blobs` (centre x, y, radius; canvas units), the shade of its depth.
fn in_blobs(rng: &mut Rng, blobs: &[[f32; 3]]) -> [f32; 2] {
    loop {
        let p = [rng.f(), rng.f()];
        if blobs.iter().any(|b| (p[0] - b[0]).hypot(p[1] - b[1]) < b[2]) {
            return p;
        }
    }
}

/// `count` lumps around the centre, the clump's outline.
fn blobs(rng: &mut Rng, count: usize, spread: f32, r: [f32; 2]) -> Vec<[f32; 3]> {
    let mut v = vec![[0.5, 0.5, r[1]]];
    for _ in 0..count {
        let a = rng.in_range(0.0, std::f32::consts::TAU);
        let d = rng.in_range(0.4, 1.0) * spread;
        v.push([0.5 + d * a.cos(), 0.5 + d * a.sin(), rng.in_range(r[0], r[1])]);
    }
    v
}

/// The depth shade of the i-th of n leaves drawn back to front, with a little per-leaf colour noise.
fn shade(rng: &mut Rng, i: usize, n: usize) -> [f32; 3] {
    let depth = (i as f32 / n as f32).powf(0.6);
    let b = (0.3 + 0.7 * depth) * rng.in_range(0.85, 1.15);
    let warm = rng.in_range(-0.08, 0.08);
    [b * (1.0 + warm), b, b * (1.0 - warm)]
}

/// A clump of leaves (broadleaf) or sprigs radiating from the centre (`radial`, conifer): `tufts` small rounded tufts
/// of `per_tuft` leaves inside the clump's outline, drawn back to front. A tuft is lit in its middle and darker toward
/// its rim, the back tufts darker than the front ones: lumps of foliage with shade between them, as a crown reads from
/// a distance.
fn clump(leaves: &[Sprite], seed: u64, tufts: usize, per_tuft: usize, radial: bool) -> RgbaImage {
    let mut rng = Rng(seed);
    let shape = if radial { blobs(&mut rng, 7, 0.15, [0.18, 0.24]) } else { blobs(&mut rng, 6, 0.15, [0.18, 0.25]) };
    let mut c = Canvas::new();
    let n = SIDE as f32;
    let tuft_r = if radial { 0.07 } else { 0.065 };
    for t in 0..tufts {
        let centre = in_blobs(&mut rng, &shape);
        let depth = (t as f32 / tufts as f32).powf(0.7);
        let lit = 0.3 + 0.7 * depth;
        let warm = rng.in_range(-0.06, 0.06);
        for _ in 0..per_tuft {
            // Gaussian-ish spread (the sum of two uniforms), at most 2 radii out.
            let (a, r) = (rng.in_range(0.0, std::f32::consts::TAU), (rng.f() + rng.f()) * tuft_r);
            let p = [centre[0] + r * a.cos(), centre[1] + r * a.sin()];
            if p.iter().any(|v| !(0.04..=0.96).contains(v)) {
                continue; // clear of the card's edge
            }
            let s = &leaves[rng.next() as usize % leaves.len()];
            let out = (p[1] - 0.5).atan2(p[0] - 0.5);
            let angle = if radial { out + rng.in_range(-0.6, 0.6) } else { rng.in_range(0.0, std::f32::consts::TAU) };
            let k = rng.in_range(0.75, 1.25);
            // The tuft's middle lit, its rim in its own shade, each leaf ±15 %.
            let b = lit * (1.0 - 0.45 * (r / (2.0 * tuft_r)).powi(2)) * rng.in_range(0.85, 1.15);
            c.stamp(s, [p[0] * n, p[1] * n], angle, [k, k], [b * (1.0 + warm), b, b * (1.0 - warm)]);
        }
    }
    c.finish()
}

/// One palm frond: leaflets on both sides of a rib from the base (bottom centre) to the tip (top centre), longest at
/// a third of the way, angled toward the tip; then the rib.
fn frond(blades: &[Sprite], seed: u64) -> RgbaImage {
    let mut rng = Rng(seed);
    let mut c = Canvas::new();
    let n = SIDE as f32;
    let (base, tip) = (n * 0.97, n * 0.03);
    let pairs = 46;
    let mut order: Vec<(usize, f32)> = (0..pairs).flat_map(|i| [(i, -1.0), (i, 1.0)]).collect();
    // Far side first (darker), so the leaflets overlap like a real frond's.
    order.sort_by_key(|&(i, side)| (side > 0.0, i));
    for (k, &(i, side)) in order.iter().enumerate() {
        let t = (i as f32 + rng.in_range(0.0, 0.6)) / pairs as f32;
        let y = base + (tip - base) * t;
        let len = n * 0.46 * (std::f32::consts::PI * (0.12 + 0.88 * t)).sin().powf(0.7) * rng.in_range(0.85, 1.1);
        let ang = side * rng.in_range(0.75, 1.0); // from the rib, toward the tip
        let dir = [ang.sin(), -ang.cos()];
        let s = &blades[rng.next() as usize % blades.len()];
        let at = [n * 0.5 + dir[0] * len * 0.5, y + dir[1] * len * 0.5];
        let mut tint = shade(&mut rng, k, order.len());
        tint = tint.map(|v| v.max(0.55));
        c.stamp(s, at, dir[1].atan2(dir[0]), [len / s.w as f32, 1.8], tint);
    }
    // The rib: a tapering stripe, the blades' own colour a little yellower.
    let rib = Sprite { w: 1, h: 1, px: vec![[0.09, 0.09, 0.03, 1.0]] };
    for k in 0..400 {
        let t = k as f32 / 400.0;
        let w = 7.0 * (1.0 - t) + 1.5;
        c.stamp(&rib, [n * 0.5, base + (tip - base) * t], 0.0, [w, 4.0], [1.0; 3]);
    }
    c.finish()
}

/// The bark: its colour at `SIDE`², opaque.
fn bark(colour: &RgbaImage) -> RgbaImage {
    let small = image::imageops::resize(colour, SIDE, SIDE, FilterType::Triangle);
    let mut c = Canvas::new();
    for (d, p) in c.px.iter_mut().zip(small.pixels()) {
        *d = [linear(p.0[0]), linear(p.0[1]), linear(p.0[2]), 1.0];
    }
    c.finish()
}

fn read(dir: &Path, id: &str, map: &str) -> Result<image::DynamicImage> {
    let p = dir.join(id).join(format!("{id}_2K-JPG_{map}.jpg"));
    image::open(&p).with_context(|| format!("{}", p.display()))
}

/// The layers (`LAYERS` order) from the materials' kept maps.
pub fn compose(dir: &Path) -> Result<[RgbaImage; 4]> {
    let ids: Vec<&str> = TREE_TEXTURES.iter().map(|m| m.id).collect();
    let set = |id: &str, len: f32| -> Result<Vec<Sprite>> {
        let s = sprites(&read(dir, id, "Color")?.to_rgba8(), &read(dir, id, "Opacity")?.to_luma8(), len);
        anyhow::ensure!(!s.is_empty(), "{id}: no leaves in its opacity map");
        Ok(s)
    };
    // Sizes at SIDE = 1024 over a card about 2.5 m wide (≈ 410 px/m): leaves ≈ 6 cm, sprigs ≈ 30 cm, leaflets 0.5 m.
    Ok([
        clump(&set(ids[0], 26.0)?, 1, 100, 240, false),
        clump(&set(ids[1], 110.0)?, 2, 90, 32, true),
        frond(&set(ids[2], 512.0)?, 3),
        bark(&read(dir, ids[3], "Color")?.to_rgba8()),
    ])
}

/// True when `<dir>/trees/` holds this version's layers made from these materials.
pub fn is_done(dir: &Path) -> bool {
    std::fs::read_to_string(dir.join("trees/foliage.json"))
        .ok()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
        .is_some_and(|v| v == meta())
        && LAYERS.iter().all(|l| dir.join("trees").join(format!("{l}.bc3")).is_file())
}

fn meta() -> serde_json::Value {
    let from: Vec<_> = TREE_TEXTURES.iter().map(|m| json!({ "id": m.id, "sha256": m.sha256 })).collect();
    json!({ "version": VERSION, "side": SIDE, "layers": LAYERS, "made_from": from })
}

/// Makes `<dir>/trees/<layer>.bc3` and `foliage.json` from the fetched materials (setup's textures step).
pub fn build(dir: &Path) -> Result<()> {
    let layers = compose(dir)?;
    let out = dir.join("trees");
    std::fs::create_dir_all(&out)?;
    for (img, name) in layers.into_iter().zip(LAYERS) {
        let mut levels = mip_chain(img);
        keep_coverage(&mut levels);
        std::fs::write(
            out.join(format!("{name}.bc3")),
            compress(&levels, Format::Bc3, Algorithm::ClusterFit, [1.0, 1.0, 1.0]),
        )?;
    }
    std::fs::write(out.join("foliage.json"), serde_json::to_string_pretty(&meta())?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A leaf set of two ellipses (one tall) on a 64² opacity map.
    fn leaf_set() -> (RgbaImage, GrayImage) {
        let colour = RgbaImage::from_pixel(64, 64, image::Rgba([60, 120, 40, 255]));
        let op = GrayImage::from_fn(64, 64, |x, y| {
            let (x, y) = (x as f32, y as f32);
            let a = ((x - 16.0) / 12.0).powi(2) + ((y - 16.0) / 5.0).powi(2) < 1.0;
            let b = ((x - 44.0) / 5.0).powi(2) + ((y - 44.0) / 14.0).powi(2) < 1.0;
            image::Luma([if a || b { 255 } else { 0 }])
        });
        (colour, op)
    }

    #[test]
    fn sprites_are_cut_and_laid_along_x() {
        let (c, o) = leaf_set();
        let s = sprites(&c, &o, 20.0);
        assert_eq!(s.len(), 2);
        assert!(s.iter().all(|s| s.w == 20 && s.h < s.w), "{:?}", s.iter().map(|s| (s.w, s.h)).collect::<Vec<_>>());
    }

    #[test]
    fn clump_is_deterministic_and_mean_is_half() {
        let (c, o) = leaf_set();
        let s = sprites(&c, &o, 26.0);
        let a = clump(&s, 1, 40, 80, false);
        assert_eq!(a, clump(&s, 1, 40, 80, false));
        let cov = coverage(&a);
        assert!(cov > 0.15 && cov < 0.6, "coverage {cov}");
        let lit: Vec<_> = a.pixels().filter(|p| p.0[3] >= 128).map(|p| f32::from(p.0[1])).collect();
        let mean = lit.iter().sum::<f32>() / lit.len() as f32;
        assert!((mean - 128.0).abs() < 12.0, "mean {mean}");
    }

    #[test]
    fn mips_keep_the_coverage() {
        // Scattered alpha, a third past the cut: the box filter pulls the mips toward the mean, under the cut.
        let mut rng = Rng(9);
        let img = RgbaImage::from_fn(64, 64, |_, _| image::Rgba([128, 128, 128, (rng.f().powi(2) * 255.0) as u8]));
        let want = coverage(&img);
        let mut levels = mip_chain(img);
        assert!(coverage(&levels[2]) < want / 2.0, "the plain mips thin out");
        keep_coverage(&mut levels);
        for l in &levels[1..4] {
            assert!((coverage(l) - want).abs() < 0.08, "level {}: {} for {want}", l.width(), coverage(l));
        }
    }
}
