//! Modern imagery layers (docs/imagery.md): a source converted into its own node set on the game's
//! terrain quadtree (same keys as the converted map.ptt, `L<L>/c_<i>_<j>.jpg`), so the runtime can
//! take a node's texture from a layer instead of the original. The source is warped into the game
//! frame with the georeference (`georef`), kept off the sea (terraintype.dat), off the game's
//! airbases and off the original's finest insets, feathered at those borders, and written in two
//! looks: colour-matched to the 1998 imagery and modern colours.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use image::RgbImage;

use crate::georef::{Georef, UNITS_TO_METRES};
use crate::terrain_types::{RUNWAY, TerrainTypes};

/// Pixels per node side (as the converted theatre).
pub const NODE_PIXELS: u32 = 1024;
/// Finest level a layer writes (9.9 m per pixel; Sentinel-2's 10 m).
pub const LAYER_LEVEL: u32 = 3;
pub const ROOT_LEVEL: u32 = 11;
/// Original insets of this level or finer always win (the airbase / target insets).
pub const KEEP_INSET_LEVEL: u32 = 3;
/// Extra pixels composed around a node so blurs and feathers match across node borders.
const MARGIN: i32 = 64;
/// Feather (pixels at LAYER_LEVEL, box radius; two passes): region / airbase / inset borders
/// ≈ 240 m, the coast ≈ 20 m.
const FEATHER_SOFT: i32 = 24;
const FEATHER_COAST: i32 = 2;
/// Colour matching: local means over this box radius (pixels at LAYER_LEVEL, two passes ≈ 500 m).
const MATCH_RADIUS: i32 = 48;
/// Warp evaluated every this many pixels, bilinear in between.
const WARP_STEP: i32 = 32;

pub type Key = (u32, u32, u32); // level, i, j

pub fn node_span(level: u32) -> u32 {
    NODE_PIXELS << level
}

/// The converted original theatre (`iaf-terrain theatre` output).
pub struct Theatre {
    pub dir: PathBuf,
    pub rect: [u32; 4],
    pub nodes: HashSet<Key>,
}

impl Theatre {
    pub fn load(dir: &Path) -> Result<Self> {
        let meta: serde_json::Value = serde_json::from_slice(&std::fs::read(dir.join("meta.json")).context("theatre meta.json")?)?;
        let t = meta["theatre"].as_array().context("theatre rect")?;
        let rect = [0, 1, 2, 3].map(|k| t[k].as_u64().unwrap_or(0) as u32);
        let mut nodes = HashSet::new();
        for (l, list) in meta["nodes"].as_object().context("nodes")? {
            let l: u32 = l.parse()?;
            for ij in list.as_array().context("node list")? {
                nodes.insert((l, ij[0].as_u64().unwrap_or(0) as u32, ij[1].as_u64().unwrap_or(0) as u32));
            }
        }
        Ok(Self { dir: dir.to_path_buf(), rect, nodes })
    }

    pub fn inside(&self, k: Key) -> bool {
        let s = node_span(k.0);
        k.1 * s < self.rect[2] && k.2 * s < self.rect[3]
    }

    /// What the game draws for node `k` with the original data: its own texture, or the part of its
    /// nearest textured ancestor (bilinear, as the GPU samples it). None outside the theatre.
    pub fn rendition(&self, k: Key, cache: &mut Cache) -> Result<Option<std::sync::Arc<RgbImage>>> {
        if !self.inside(k) {
            return Ok(None);
        }
        if let Some(img) = cache.get(&k) {
            return Ok(Some(img));
        }
        let mut a = k;
        while !self.nodes.contains(&a) {
            if a.0 >= ROOT_LEVEL {
                return Ok(None);
            }
            a = (a.0 + 1, a.1 >> 1, a.2 >> 1);
        }
        let src = image::open(self.dir.join(format!("L{}/c_{}_{}.jpg", a.0, a.1, a.2)))?.to_rgb8();
        let img = if a == k {
            src
        } else {
            let d = a.0 - k.0;
            let part = NODE_PIXELS >> d;
            let (x, y) = ((k.1 - (a.1 << d)) * part, (k.2 - (a.2 << d)) * part);
            upsample(&src, x, y, part, NODE_PIXELS)
        };
        let img = std::sync::Arc::new(img);
        cache.put(k, img.clone());
        Ok(Some(img))
    }

    /// The original as drawn at `level` over the pixel rect (x0, y0, w, h) of that level (pixel
    /// (x, y) covers terrain units [x, x+1) · 2^level); black outside the theatre.
    pub fn original_rect(&self, level: u32, x0: i64, y0: i64, w: usize, h: usize, cache: &mut Cache) -> Result<Vec<[f32; 3]>> {
        let mut out = vec![[0.0f32; 3]; w * h];
        let np = NODE_PIXELS as i64;
        for nj in y0.div_euclid(np)..=(y0 + h as i64 - 1).div_euclid(np) {
            for ni in x0.div_euclid(np)..=(x0 + w as i64 - 1).div_euclid(np) {
                if ni < 0 || nj < 0 {
                    continue;
                }
                let Some(img) = self.rendition((level, ni as u32, nj as u32), cache)? else { continue };
                for y in (nj * np).max(y0)..((nj + 1) * np).min(y0 + h as i64) {
                    for x in (ni * np).max(x0)..((ni + 1) * np).min(x0 + w as i64) {
                        let p = img.get_pixel((x - ni * np) as u32, (y - nj * np) as u32);
                        out[(y - y0) as usize * w + (x - x0) as usize] = [p[0] as f32, p[1] as f32, p[2] as f32];
                    }
                }
            }
        }
        Ok(out)
    }
}

/// `part`² pixels at (x, y) of `src` scaled to `size`², bilinear with pixel centres aligned (the
/// GPU's linear filter on the ancestor's sub-rectangle).
fn upsample(src: &RgbImage, x: u32, y: u32, part: u32, size: u32) -> RgbImage {
    let f = part as f32 / size as f32;
    let (w, h) = (src.width() as f32, src.height() as f32);
    RgbImage::from_fn(size, size, |ox, oy| {
        let sx = (x as f32 + (ox as f32 + 0.5) * f - 0.5).clamp(0.0, w - 1.0);
        let sy = (y as f32 + (oy as f32 + 0.5) * f - 0.5).clamp(0.0, h - 1.0);
        let (x0, y0) = (sx as u32, sy as u32);
        let (x1, y1) = ((x0 + 1).min(src.width() - 1), (y0 + 1).min(src.height() - 1));
        let (fx, fy) = (sx - x0 as f32, sy - y0 as f32);
        let px = |a: u32, b: u32| src.get_pixel(a, b).0.map(|v| v as f32);
        let (a, b, c, d) = (px(x0, y0), px(x1, y0), px(x0, y1), px(x1, y1));
        image::Rgb([0, 1, 2].map(|k| {
            let top = a[k] + (b[k] - a[k]) * fx;
            let bot = c[k] + (d[k] - c[k]) * fx;
            (top + (bot - top) * fy).round() as u8
        }))
    })
}

/// A small cache of node renditions (per worker).
#[derive(Default)]
pub struct Cache(HashMap<Key, std::sync::Arc<RgbImage>>);

impl Cache {
    fn get(&self, k: &Key) -> Option<std::sync::Arc<RgbImage>> {
        self.0.get(k).cloned()
    }
    fn put(&mut self, k: Key, v: std::sync::Arc<RgbImage>) {
        if self.0.len() >= 24 {
            self.0.clear();
        }
        self.0.insert(k, v);
    }
}

/// Where the layer may replace the original (docs/imagery.md §3).
pub struct Rules {
    /// The region the layer is for: map.ptt's Israel inset (its largest record) — "Israel" is
    /// inside, "outside Israel" the rest of the theatre.
    pub israel: [u32; 4],
    pub outside_israel: bool,
    /// Original inset records of level ≤ KEEP_INSET_LEVEL (airbases / targets): kept.
    pub keep: Vec<[u32; 4]>,
    pub types: TerrainTypes,
}

impl Rules {
    /// From the install (map.ptt records, terraintype.dat).
    pub fn load(install: &Path, outside_israel: bool) -> Result<Self> {
        let ptt = iaf_formats::ptt::Ptt::open(install.join("resource/terrain/map.ptt"))?;
        let area = |r: &[u32; 4]| (r[2] - r[0]) as u64 * (r[3] - r[1]) as u64;
        let israel = ptt.levels.iter().filter(|l| l.flag == 0).max_by_key(|l| area(&l.rect)).context("no inset records")?.rect;
        let keep = ptt.levels.iter().filter(|l| l.flag == 0 && l.level <= KEEP_INSET_LEVEL).map(|l| l.rect).collect();
        let types = TerrainTypes::parse(&std::fs::read(install.join("terraintype.dat")).context("terraintype.dat")?)?;
        Ok(Self { israel, outside_israel, keep, types })
    }

    fn in_rect(r: &[u32; 4], tx: f64, ty: f64) -> bool {
        tx >= r[0] as f64 && tx < r[2] as f64 && ty >= r[1] as f64 && ty < r[3] as f64
    }

    /// (allowed apart from the coast, land) at terrain units (tx, ty).
    fn at(&self, tx: f64, ty: f64) -> (bool, bool) {
        let mask = self.types.at(tx * UNITS_TO_METRES - 166850.0, 1043780.0 - ty * UNITS_TO_METRES);
        let in_region = Self::in_rect(&self.israel, tx, ty) != self.outside_israel;
        let allowed = in_region && mask & RUNWAY == 0 && !self.keep.iter().any(|r| Self::in_rect(r, tx, ty));
        (allowed, TerrainTypes::is_land(mask))
    }

    /// True when any pixel of the node may take the layer (sampled on a 32² grid).
    pub fn node_wanted(&self, k: Key) -> bool {
        let s = node_span(k.0) as f64;
        (0..32).any(|y| {
            (0..32).any(|x| {
                let (a, l) = self.at((k.1 as f64 + (x as f64 + 0.5) / 32.0) * s, (k.2 as f64 + (y as f64 + 0.5) / 32.0) * s);
                a && l
            })
        })
    }
}

/// A source raster in lon / lat (EPSG:4326), red, green, blue, near-infrared u16 interleaved (GDAL
/// ENVI, BIP), 0 = no data.
pub struct Source {
    pub w: usize,
    pub h: usize,
    /// Upper-left corner of the upper-left pixel and the pixel size (degrees).
    pub ulx: f64,
    pub uly: f64,
    pub dx: f64,
    pub dy: f64,
    pub data: Vec<u16>,
}

impl Source {
    /// Reads `<path>.bin` + `<path>.hdr` written by `gdal_translate -of ENVI -co INTERLEAVE=BIP`.
    pub fn read_envi(bin: &Path) -> Result<Self> {
        let hdr = std::fs::read_to_string(bin.with_extension("hdr"))?;
        let field = |k: &str| -> Option<String> {
            hdr.lines().find(|l| l.trim_start().starts_with(k)).and_then(|l| l.split_once('=')).map(|(_, v)| v.trim().to_string())
        };
        let w: usize = field("samples").context("samples")?.parse()?;
        let h: usize = field("lines").context("lines")?.parse()?;
        let bands: usize = field("bands").context("bands")?.parse()?;
        if bands != 4 || field("data type").as_deref() != Some("12") {
            bail!("source: want 4 bands of u16, got {bands} / type {:?}", field("data type"));
        }
        // map info = {Geographic Lat/Lon, 1, 1, ulx, uly, dx, dy, WGS-84, ...}
        let mi = field("map info").context("map info")?;
        let v: Vec<&str> = mi.trim_matches(|c| c == '{' || c == '}').split(',').map(str::trim).collect();
        let num = |i: usize| -> Result<f64> { Ok(v.get(i).context("map info")?.parse()?) };
        let (rx, ry) = (num(1)?, num(2)?);
        let (dx, dy) = (num(5)?, num(6)?);
        let (ulx, uly) = (num(3)? - (rx - 1.0) * dx, num(4)? + (ry - 1.0) * dy);
        let raw = std::fs::read(bin)?;
        if raw.len() != w * h * 8 {
            bail!("source: {} bytes, expected {}", raw.len(), w * h * 8);
        }
        let data = raw.as_chunks::<2>().0.iter().map(|b| u16::from_le_bytes([b[0], b[1]])).collect();
        Ok(Self { w, h, ulx, uly, dx, dy, data })
    }

    /// Bilinear sample at (lon, lat): reflectance × 10⁴ per band (R, G, B, NIR); None where any
    /// neighbour is no data.
    pub fn sample(&self, lon: f64, lat: f64) -> Option<[f32; 4]> {
        let u = (lon - self.ulx) / self.dx - 0.5;
        let v = (self.uly - lat) / self.dy - 0.5;
        if u < 0.0 || v < 0.0 || u >= (self.w - 1) as f64 || v >= (self.h - 1) as f64 {
            return None;
        }
        let (x0, y0) = (u as usize, v as usize);
        let (fx, fy) = ((u - x0 as f64) as f32, (v - y0 as f64) as f32);
        let px = |x: usize, y: usize| {
            let i = (y * self.w + x) * 4;
            [self.data[i], self.data[i + 1], self.data[i + 2], self.data[i + 3]]
        };
        let (a, b, c, d) = (px(x0, y0), px(x0 + 1, y0), px(x0, y0 + 1), px(x0 + 1, y0 + 1));
        if [a, b, c, d].iter().any(|p| p[..3] == [0, 0, 0]) {
            return None;
        }
        Some([0, 1, 2, 3].map(|k| {
            let (a, b, c, d) = (a[k] as f32, b[k] as f32, c[k] as f32, d[k] as f32);
            let top = a + (b - a) * fx;
            top + (c + (d - c) * fx - top) * fy
        }))
    }
}

/// Open water in the source: near-infrared low and below green (NDWI > 0). Water stays the
/// original's (docs/imagery.md §3), so the drawn sea keeps the 1998 look and the layer's coast is
/// the real one.
pub fn is_water(s: [f32; 4]) -> bool {
    s[3] < 900.0 && s[1] > s[3]
}

/// Modern colours: surface reflectance (× 10⁴) to display values — a linear scale (0.42
/// reflectance = white), a display gamma and a little extra saturation (docs/imagery.md §4).
pub fn tone(refl: [f32; 3]) -> [f32; 3] {
    let v = refl.map(|r| (r / 4200.0).clamp(0.0, 1.0).powf(1.0 / 1.9) * 255.0);
    let m = (v[0] + v[1] + v[2]) / 3.0;
    v.map(|c| (m + (c - m) * 1.15).clamp(0.0, 255.0))
}

/// Separable box blur (radius r, clamped edges), twice ≈ a tent / Gaussian.
fn blur(img: &mut [f32], w: usize, h: usize, r: i32) {
    let mut tmp = vec![0f32; img.len()];
    for _ in 0..2 {
        for y in 0..h {
            let row = &img[y * w..(y + 1) * w];
            let mut acc: f32 = (-r..=r).map(|k| row[k.clamp(0, w as i32 - 1) as usize]).sum();
            for x in 0..w {
                tmp[y * w + x] = acc / (2 * r + 1) as f32;
                let add = (x as i32 + r + 1).min(w as i32 - 1) as usize;
                let sub = (x as i32 - r).max(0) as usize;
                acc += row[add] - row[sub];
            }
        }
        for x in 0..w {
            let mut acc: f32 = (-r..=r).map(|k| tmp[k.clamp(0, h as i32 - 1) as usize * w + x]).sum();
            for y in 0..h {
                img[y * w + x] = acc / (2 * r + 1) as f32;
                let add = (y as i32 + r + 1).min(h as i32 - 1) as usize;
                let sub = (y as i32 - r).max(0) as usize;
                acc += tmp[add * w + x] - tmp[sub * w + x];
            }
        }
    }
}

/// Hard mask → weight with the feather on the inside only: 0 at and beyond the border, 1 deep inside.
fn feather(mask: &[bool], w: usize, h: usize, r: i32) -> Vec<f32> {
    let mut f: Vec<f32> = mask.iter().map(|&m| m as u8 as f32).collect();
    blur(&mut f, w, h, r);
    f.iter().zip(mask).map(|(&b, &m)| if m { (2.0 * b - 1.0).clamp(0.0, 1.0) } else { 0.0 }).collect()
}

/// One layer node in both looks: (1998 colours, modern colours); None when the layer shows nowhere
/// in it.
pub fn compose_node(k: Key, theatre: &Theatre, rules: &Rules, warp: &Georef, src: &Source, cache: &mut Cache) -> Result<Option<(RgbImage, RgbImage)>> {
    let n = NODE_PIXELS as i32;
    let size = (n + 2 * MARGIN) as usize;
    let upp = (1u32 << k.0) as f64;
    let x0 = k.1 as i64 * n as i64 - MARGIN as i64;
    let y0 = k.2 as i64 * n as i64 - MARGIN as i64;
    let orig = theatre.original_rect(k.0, x0, y0, size, size, cache)?;
    // Warp grid: (lon, lat) every WARP_STEP pixels.
    let g = (size as i32 / WARP_STEP + 2) as usize;
    let grid: Vec<[f64; 2]> = (0..g * g)
        .map(|i| {
            let (gx, gy) = ((i % g) as f64 * WARP_STEP as f64, (i / g) as f64 * WARP_STEP as f64);
            warp.to_geo((x0 as f64 + gx) * upp, (y0 as f64 + gy) * upp)
        })
        .collect();
    let mut modern = vec![[0f32; 3]; size * size];
    let mut allowed = vec![false; size * size];
    let mut land = vec![false; size * size];
    let mut valid = vec![false; size * size];
    for y in 0..size {
        for x in 0..size {
            let i = y * size + x;
            let (px, py) = (x as f64 + 0.5, y as f64 + 0.5);
            let (a, l) = rules.at((x0 as f64 + px) * upp, (y0 as f64 + py) * upp);
            allowed[i] = a;
            land[i] = l;
            let (gx, gy) = (px / WARP_STEP as f64, py / WARP_STEP as f64);
            let (cx, cy) = (gx as usize, gy as usize);
            let (fx, fy) = (gx - cx as f64, gy - cy as f64);
            let at = |c: usize, r: usize| grid[r * g + c];
            let (p00, p10, p01, p11) = (at(cx, cy), at(cx + 1, cy), at(cx, cy + 1), at(cx + 1, cy + 1));
            let geo = [0, 1].map(|c| {
                let top = p00[c] + (p10[c] - p00[c]) * fx;
                top + (p01[c] + (p11[c] - p01[c]) * fx - top) * fy
            });
            if let Some(s) = src.sample(geo[0], geo[1]) {
                modern[i] = tone([s[0], s[1], s[2]]);
                valid[i] = !is_water(s);
            }
        }
    }
    let ok: Vec<bool> = (0..size * size).map(|i| allowed[i] && valid[i]).collect();
    let w_soft = feather(&ok, size, size, FEATHER_SOFT);
    let w_land = feather(&land, size, size, FEATHER_COAST);
    let weight: Vec<f32> = w_soft.iter().zip(&w_land).map(|(a, b)| a * b).collect();
    let crop = |i: usize| {
        let (x, y) = (i % size, i / size);
        x >= MARGIN as usize && y >= MARGIN as usize && x < (MARGIN + n) as usize && y < (MARGIN + n) as usize
    };
    if !(0..size * size).any(|i| crop(i) && weight[i] > 0.0) {
        return Ok(None);
    }
    // 1998 colours: the modern pixel times the ratio of the local (land, valid) means of the
    // original and the modern image, per channel.
    let m: Vec<bool> = (0..size * size).map(|i| land[i] && valid[i]).collect();
    let mut mw: Vec<f32> = m.iter().map(|&b| b as u8 as f32).collect();
    blur(&mut mw, size, size, MATCH_RADIUS);
    let mut ratio = vec![[1f32; 3]; size * size];
    for c in 0..3 {
        let mut so: Vec<f32> = (0..size * size).map(|i| if m[i] { orig[i][c] } else { 0.0 }).collect();
        let mut sm: Vec<f32> = (0..size * size).map(|i| if m[i] { modern[i][c] } else { 0.0 }).collect();
        blur(&mut so, size, size, MATCH_RADIUS);
        blur(&mut sm, size, size, MATCH_RADIUS);
        for i in 0..size * size {
            if mw[i] > 1e-3 && sm[i] > 1e-3 {
                ratio[i][c] = ((so[i] + 4.0) / (sm[i] + 4.0)).clamp(0.33, 3.0);
            }
        }
    }
    let mut a = RgbImage::new(NODE_PIXELS, NODE_PIXELS);
    let mut b = RgbImage::new(NODE_PIXELS, NODE_PIXELS);
    for y in 0..n as usize {
        for x in 0..n as usize {
            let i = (y + MARGIN as usize) * size + x + MARGIN as usize;
            let w = weight[i];
            let mix = |s: [f32; 3]| image::Rgb([0, 1, 2].map(|c| (w * s[c] + (1.0 - w) * orig[i][c]).round().clamp(0.0, 255.0) as u8));
            a.put_pixel(x as u32, y as u32, mix([0, 1, 2].map(|c| modern[i][c] * ratio[i][c])));
            b.put_pixel(x as u32, y as u32, mix(modern[i]));
        }
    }
    Ok(Some((a, b)))
}

/// A parent node from its four children: the layer's child where it has one, else the original's
/// rendition (the downsampled 2048² mosaic, Triangle filter).
pub fn compose_parent(k: Key, theatre: &Theatre, child_path: impl Fn(Key) -> Option<PathBuf>, cache: &mut Cache) -> Result<RgbImage> {
    let n = NODE_PIXELS;
    let mut big = RgbImage::new(2 * n, 2 * n);
    for dy in 0..2 {
        for dx in 0..2 {
            let c = (k.0 - 1, 2 * k.1 + dx, 2 * k.2 + dy);
            let img = match child_path(c) {
                Some(p) => Some(std::sync::Arc::new(image::open(p)?.to_rgb8())),
                None => theatre.rendition(c, cache)?,
            };
            if let Some(img) = img {
                image::imageops::replace(&mut big, img.as_ref(), (dx * n) as i64, (dy * n) as i64);
            }
        }
    }
    Ok(image::imageops::resize(&big, n, n, image::imageops::FilterType::Triangle))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feather_is_inside_only() {
        let (w, h) = (64, 8);
        let mask: Vec<bool> = (0..w * h).map(|i| i % w >= 32).collect();
        let f = feather(&mask, w, h, 4);
        for y in 0..h {
            assert_eq!(f[y * w + 31], 0.0);
            assert!(f[y * w + 32] < 0.2, "border pixel");
            assert!(f[y * w + 36] > 0.0 && f[y * w + 36] < 1.0);
            assert!(f[y * w + 50] > 0.999);
        }
    }

    #[test]
    fn tone_is_monotonic_and_bounded() {
        let mut last = -1.0;
        for r in (0..10000).step_by(250) {
            let v = tone([r as f32; 3]);
            assert!(v[0] >= last && v[0] <= 255.0);
            last = v[0];
        }
        assert_eq!(tone([9000.0; 3]), [255.0; 3]);
    }
}
