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
pub const ROOT_LEVEL: u32 = 11;
/// Original insets of this level or finer always win: the airbase / target insets (every site has
/// level 0–2 records). map.ptt's level-3 inset records are the original's regional 9.9 m cover of
/// Israel (four large rectangles), which an Israel layer replaces.
pub const KEEP_INSET_LEVEL: u32 = 2;
/// The radii below are in pixels at this level (9.9 m per pixel); a finer layer level scales them so
/// they keep their ground size.
const REF_LEVEL: u32 = 3;
/// Extra pixels composed around a node so blurs and feathers match across node borders.
const MARGIN: i32 = 64;
/// Feather (box radius; two passes): region / airbase / inset / coverage borders ≈ 240 m, the coast
/// ≈ 20 m.
const FEATHER_SOFT: i32 = 24;
const FEATHER_COAST: i32 = 2;
/// Colour matching: local means over this box radius (two passes ≈ 500 m).
const MATCH_RADIUS: i32 = 48;
/// No-data and water patches narrower than about twice this radius (≈ 80 m) are ignored: a white
/// roof in a photo is not a sheet border, a pool is not the sea.
const SPECK: i32 = 8;
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

/// One source sample: display colour (0..255, the source's own "modern" look), open water, no data.
#[derive(Clone, Copy, Default)]
pub struct Px {
    pub rgb: [f32; 3],
    pub water: bool,
    pub nodata: bool,
}

/// A source raster cut out for one work unit.
pub trait Imagery: Sync {
    /// The source pixel position (x, y; pixel (0, 0) covers [0, 1)²) of WGS84 (lon, lat).
    fn pixel(&self, lon: f64, lat: f64) -> [f64; 2];
    /// Bilinear sample at a pixel position (no data outside the raster).
    fn sample(&self, x: f64, y: f64) -> Px;
}

/// An ENVI file written by `gdal_translate -of ENVI -co INTERLEAVE=BIP`: size, bands, GDAL data type
/// code, upper-left corner of the upper-left pixel, pixel size, raw samples.
struct Envi {
    w: usize,
    h: usize,
    bands: usize,
    dtype: String,
    ulx: f64,
    uly: f64,
    dx: f64,
    dy: f64,
    raw: Vec<u8>,
}

fn read_envi(bin: &Path) -> Result<Envi> {
    let hdr = std::fs::read_to_string(bin.with_extension("hdr"))?;
    let field = |k: &str| -> Option<String> {
        hdr.lines().find(|l| l.trim_start().starts_with(k)).and_then(|l| l.split_once('=')).map(|(_, v)| v.trim().to_string())
    };
    let w: usize = field("samples").context("samples")?.parse()?;
    let h: usize = field("lines").context("lines")?.parse()?;
    let bands: usize = field("bands").context("bands")?.parse()?;
    let dtype = field("data type").context("data type")?;
    // map info = {<projection>, 1, 1, ulx, uly, dx, dy, ...}
    let mi = field("map info").context("map info")?;
    let v: Vec<&str> = mi.trim_matches(|c| c == '{' || c == '}').split(',').map(str::trim).collect();
    let num = |i: usize| -> Result<f64> { Ok(v.get(i).context("map info")?.parse()?) };
    let (rx, ry) = (num(1)?, num(2)?);
    let (dx, dy) = (num(5)?, num(6)?);
    let (ulx, uly) = (num(3)? - (rx - 1.0) * dx, num(4)? + (ry - 1.0) * dy);
    let raw = std::fs::read(bin)?;
    Ok(Envi { w, h, bands, dtype, ulx, uly, dx, dy, raw })
}

/// Bilinear position: the four neighbours' indices (x0, y0, x1, y1) and weights, None outside.
fn bilinear(x: f64, y: f64, w: usize, h: usize) -> Option<(usize, usize, f32, f32)> {
    let (u, v) = (x - 0.5, y - 0.5);
    if u < 0.0 || v < 0.0 || u >= (w - 1) as f64 || v >= (h - 1) as f64 {
        return None;
    }
    let (x0, y0) = (u as usize, v as usize);
    Some((x0, y0, (u - x0 as f64) as f32, (v - y0 as f64) as f32))
}

fn lerp4(a: f32, b: f32, c: f32, d: f32, fx: f32, fy: f32) -> f32 {
    let top = a + (b - a) * fx;
    top + (c + (d - c) * fx - top) * fy
}

/// Sentinel-2 (WorldCover): lon / lat (EPSG:4326), red, green, blue, near-infrared u16 (reflectance ×
/// 10⁴), 0 = no data.
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
    pub fn read_envi(bin: &Path) -> Result<Self> {
        let e = read_envi(bin)?;
        if e.bands != 4 || e.dtype != "12" || e.raw.len() != e.w * e.h * 8 {
            bail!("source: want 4 bands of u16, got {} / type {} / {} bytes", e.bands, e.dtype, e.raw.len());
        }
        let data = e.raw.as_chunks::<2>().0.iter().map(|b| u16::from_le_bytes([b[0], b[1]])).collect();
        Ok(Self { w: e.w, h: e.h, ulx: e.ulx, uly: e.uly, dx: e.dx, dy: e.dy, data })
    }
}

impl Imagery for Source {
    fn pixel(&self, lon: f64, lat: f64) -> [f64; 2] {
        [(lon - self.ulx) / self.dx, (self.uly - lat) / self.dy]
    }

    fn sample(&self, x: f64, y: f64) -> Px {
        let Some((x0, y0, fx, fy)) = bilinear(x, y, self.w, self.h) else { return Px { nodata: true, ..Px::default() } };
        let px = |x: usize, y: usize| {
            let i = (y * self.w + x) * 4;
            [self.data[i], self.data[i + 1], self.data[i + 2], self.data[i + 3]]
        };
        let (a, b, c, d) = (px(x0, y0), px(x0 + 1, y0), px(x0, y0 + 1), px(x0 + 1, y0 + 1));
        let s = [0, 1, 2, 3].map(|k| lerp4(a[k] as f32, b[k] as f32, c[k] as f32, d[k] as f32, fx, fy));
        Px { rgb: tone([s[0], s[1], s[2]]), water: is_water(s), nodata: [a, b, c, d].iter().any(|p| p[..3] == [0, 0, 0]) }
    }
}

/// A colour photo in a projected grid (the Survey of Israel sheets: Israeli TM Grid, 2 m), RGB bytes;
/// pure white (the sheets' fill outside the photographed area) and pure black (no sheet) are no data.
pub struct Photo {
    pub w: usize,
    pub h: usize,
    /// Upper-left corner of the upper-left pixel (easting, northing) and the pixel size (metres).
    pub ulx: f64,
    pub uly: f64,
    pub res: f64,
    pub data: Vec<u8>,
    /// WGS84 (lon, lat) → the grid (easting, northing).
    pub project: fn(f64, f64) -> [f64; 2],
    /// Levels per sheet: (grid extent e0, n0, e1, n1; per-band dark level and the white level,
    /// `sheet_levels`). Each band is stretched from [dark, white] to [0, WHITE] (haze removal and
    /// exposure), the levels blended across sheet borders (`DARK_BLEND`) so the correction adds no seam.
    pub levels: Vec<([f64; 4], [f32; 4])>,
}

/// Display gamma after the levels.
const PHOTO_GAMMA: f32 = 1.1;
/// A sheet's white level maps to this.
const WHITE: f32 = 235.0;

/// Width (grid metres) over which neighbouring sheets' dark levels blend, centred on their border.
const DARK_BLEND: f64 = 4000.0;

/// The levels at grid point (e, n): the sheets' levels weighted by how far inside each one the
/// point lies (½ on a border, 1 from DARK_BLEND / 2 inside, 0 from DARK_BLEND / 2 outside).
fn levels_at(levels: &[([f64; 4], [f32; 4])], e: f64, n: f64) -> Option<[f32; 4]> {
    let (mut sum, mut wsum) = ([0f32; 4], 0f32);
    for (b, lv) in levels {
        let inside = (e - b[0]).min(b[2] - e).min(n - b[1]).min(b[3] - n);
        let w = (0.5 + inside / DARK_BLEND).clamp(0.0, 1.0) as f32;
        for c in 0..4 {
            sum[c] += w * lv[c];
        }
        wsum += w;
    }
    (wsum > 0.0).then(|| sum.map(|v| v / wsum))
}

/// A sheet's levels from its photo pixels (not the white / black fill): per band the 0.5th
/// percentile — the haze the aerial photo adds over its darkest shadows and water — and the white
/// level, the brightest band's 99.5th percentile (one for all bands, so the colour balance stays).
pub fn sheet_levels(rgb: &[u8]) -> [f32; 4] {
    let mut hist = [[0u64; 256]; 3];
    for p in rgb.as_chunks::<3>().0 {
        if *p != [255; 3] && *p != [0; 3] {
            for c in 0..3 {
                hist[c][p[c] as usize] += 1;
            }
        }
    }
    let pct = |c: usize, q: u64| {
        let n: u64 = hist[c].iter().sum();
        let mut acc = 0;
        hist[c].iter().position(|&v| {
            acc += v;
            acc * 1000 >= n * q
        }).unwrap_or(0) as f32
    };
    let lo = [0, 1, 2].map(|c| pct(c, 5));
    let hi = (0..3).map(|c| pct(c, 995)).fold(0.0, f32::max);
    [lo[0], lo[1], lo[2], hi.max(lo[0].max(lo[1]).max(lo[2]) + 32.0)]
}

impl Photo {
    pub fn read_envi(bin: &Path, project: fn(f64, f64) -> [f64; 2]) -> Result<Self> {
        let e = read_envi(bin)?;
        if e.bands != 3 || e.dtype != "1" || e.raw.len() != e.w * e.h * 3 {
            bail!("photo: want 3 bands of u8, got {} / type {} / {} bytes", e.bands, e.dtype, e.raw.len());
        }
        Ok(Self { w: e.w, h: e.h, ulx: e.ulx, uly: e.uly, res: e.dx, data: e.raw, project, levels: Vec::new() })
    }
}

impl Imagery for Photo {
    fn pixel(&self, lon: f64, lat: f64) -> [f64; 2] {
        let [e, n] = (self.project)(lon, lat);
        [(e - self.ulx) / self.res, (self.uly - n) / self.res]
    }

    fn sample(&self, x: f64, y: f64) -> Px {
        let Some((x0, y0, fx, fy)) = bilinear(x, y, self.w, self.h) else { return Px { nodata: true, ..Px::default() } };
        let px = |x: usize, y: usize| {
            let i = (y * self.w + x) * 3;
            [self.data[i], self.data[i + 1], self.data[i + 2]]
        };
        let (a, b, c, d) = (px(x0, y0), px(x0 + 1, y0), px(x0, y0 + 1), px(x0 + 1, y0 + 1));
        let nodata = [a, b, c, d].iter().any(|p| *p == [255; 3] || *p == [0; 3]);
        let mut rgb = [0, 1, 2].map(|k| lerp4(a[k] as f32, b[k] as f32, c[k] as f32, d[k] as f32, fx, fy));
        let (e, n) = (self.ulx + x * self.res, self.uly - y * self.res);
        if let Some(lv) = levels_at(&self.levels, e, n) {
            rgb = [0, 1, 2].map(|c| (((rgb[c] - lv[c]) / (lv[3] - lv[c])).max(0.0).powf(1.0 / PHOTO_GAMMA) * WHITE).min(255.0));
        }
        Px { rgb, water: is_photo_water(rgb), nodata }
    }
}

/// Open water in a colour photo: blue-green clearly above red and not bright (the sea's teal, the
/// Kinneret's blue; sand, roofs, fields and shadows fail one of the tests). Only patches wider than
/// ≈ 160 m count (`SPECK`), so pools and small ponds stay the photo's.
pub fn is_photo_water(c: [f32; 3]) -> bool {
    c[2] > c[0] + 12.0 && c[1] > c[0] + 6.0 && c[0] + c[1] + c[2] < 480.0
}

/// Open water in Sentinel-2: near-infrared low and below green (NDWI > 0). Water stays the
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

/// Separable box blur (radius r, clamped edges), twice ≈ a tent / Gaussian. The vertical pass runs
/// over whole rows (cache-friendly).
fn blur(img: &mut [f32], w: usize, h: usize, r: i32) {
    let mut tmp = vec![0f32; img.len()];
    let mut acc = vec![0f32; w];
    let norm = 1.0 / (2 * r + 1) as f32;
    for _ in 0..2 {
        for y in 0..h {
            let row = &img[y * w..(y + 1) * w];
            let mut a: f32 = (-r..=r).map(|k| row[k.clamp(0, w as i32 - 1) as usize]).sum();
            for x in 0..w {
                tmp[y * w + x] = a * norm;
                let add = (x as i32 + r + 1).min(w as i32 - 1) as usize;
                let sub = (x as i32 - r).max(0) as usize;
                a += row[add] - row[sub];
            }
        }
        acc.fill(0.0);
        for k in -r..=r {
            let src = &tmp[k.clamp(0, h as i32 - 1) as usize * w..][..w];
            acc.iter_mut().zip(src).for_each(|(a, v)| *a += v);
        }
        for y in 0..h {
            img[y * w..(y + 1) * w].iter_mut().zip(&acc).for_each(|(o, a)| *o = a * norm);
            let add = (y as i32 + r + 1).min(h as i32 - 1) as usize * w;
            let sub = (y as i32 - r).max(0) as usize * w;
            for x in 0..w {
                acc[x] += tmp[add + x] - tmp[sub + x];
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

/// A mask without its small patches and holes (a box blur of radius r, twice, over 0.5).
fn majority(mask: &[bool], w: usize, h: usize, r: i32) -> Vec<bool> {
    let mut f: Vec<f32> = mask.iter().map(|&m| m as u8 as f32).collect();
    blur(&mut f, w, h, r);
    f.iter().map(|&v| v > 0.5).collect()
}

/// One layer node (level ≤ 3) in both looks: (1998 colours, the source's colours); None when the
/// layer shows nowhere in it.
pub fn compose_node(k: Key, theatre: &Theatre, rules: &Rules, warp: &Georef, src: &dyn Imagery, cache: &mut Cache) -> Result<Option<(RgbImage, RgbImage)>> {
    let sc = 1i32 << (REF_LEVEL - k.0.min(REF_LEVEL));
    let (margin, feather_soft, feather_coast, match_radius, speck) = (MARGIN * sc, FEATHER_SOFT * sc, FEATHER_COAST * sc, MATCH_RADIUS * sc, SPECK * sc);
    let n = NODE_PIXELS as i32;
    let size = (n + 2 * margin) as usize;
    let upp = (1u32 << k.0) as f64;
    let x0 = k.1 as i64 * n as i64 - margin as i64;
    let y0 = k.2 as i64 * n as i64 - margin as i64;
    let orig = theatre.original_rect(k.0, x0, y0, size, size, cache)?;
    // Warp grid: the source pixel position every WARP_STEP pixels.
    let g = (size as i32 / WARP_STEP + 2) as usize;
    let grid: Vec<[f64; 2]> = (0..g * g)
        .map(|i| {
            let (gx, gy) = ((i % g) as f64 * WARP_STEP as f64, (i / g) as f64 * WARP_STEP as f64);
            let [lon, lat] = warp.to_geo((x0 as f64 + gx) * upp, (y0 as f64 + gy) * upp);
            src.pixel(lon, lat)
        })
        .collect();
    let mut modern = vec![[0f32; 3]; size * size];
    let mut allowed = vec![false; size * size];
    let mut land = vec![false; size * size];
    let mut nodata = vec![false; size * size];
    let mut water = vec![false; size * size];
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
            let sp = [0, 1].map(|c| {
                let top = p00[c] + (p10[c] - p00[c]) * fx;
                top + (p01[c] + (p11[c] - p01[c]) * fx - top) * fy
            });
            let s = src.sample(sp[0], sp[1]);
            modern[i] = s.rgb;
            nodata[i] = s.nodata;
            water[i] = s.water && !s.nodata;
        }
    }
    // No data (outside the source's coverage) fades over the soft feather; water (the real coast)
    // over the coast feather, like terraintype.dat's sea.
    let has: Vec<bool> = majority(&nodata, size, size, speck).iter().map(|&b| !b).collect();
    // Source water counts only near terraintype.dat's water (≈ 500 m): it moves the coast to the real
    // one; ponds and rivers elsewhere stay the layer's (else a blurred 1998 blob shows inside them).
    let mut near: Vec<f32> = land.iter().map(|&l| (!l) as u8 as f32).collect();
    blur(&mut near, size, size, match_radius / 2);
    let water: Vec<bool> = (0..size * size).map(|i| water[i] && near[i] > 1e-3).collect();
    let wet = majority(&water, size, size, speck);
    let ok: Vec<bool> = (0..size * size).map(|i| allowed[i] && has[i]).collect();
    let dry: Vec<bool> = (0..size * size).map(|i| land[i] && !wet[i]).collect();
    let w_soft = feather(&ok, size, size, feather_soft);
    let w_land = feather(&dry, size, size, feather_coast);
    let weight: Vec<f32> = w_soft.iter().zip(&w_land).map(|(a, b)| a * b).collect();
    let crop = |i: usize| {
        let (x, y) = (i % size, i / size);
        x >= margin as usize && y >= margin as usize && x < (margin + n) as usize && y < (margin + n) as usize
    };
    if !(0..size * size).any(|i| crop(i) && weight[i] > 0.0) {
        return Ok(None);
    }
    // 1998 colours: the modern pixel times the ratio of the local (dry land with data) means of the
    // original and the modern image, per channel.
    let m: Vec<bool> = (0..size * size).map(|i| dry[i] && !water[i] && !nodata[i] && has[i]).collect();
    let mut mw: Vec<f32> = m.iter().map(|&b| b as u8 as f32).collect();
    blur(&mut mw, size, size, match_radius);
    let mut ratio = vec![[1f32; 3]; size * size];
    for c in 0..3 {
        let mut so: Vec<f32> = (0..size * size).map(|i| if m[i] { orig[i][c] } else { 0.0 }).collect();
        let mut sm: Vec<f32> = (0..size * size).map(|i| if m[i] { modern[i][c] } else { 0.0 }).collect();
        blur(&mut so, size, size, match_radius);
        blur(&mut sm, size, size, match_radius);
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
            let i = (y + margin as usize) * size + x + margin as usize;
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
    fn majority_drops_small_patches() {
        let (w, h) = (64, 64);
        // A 4-pixel square (a white roof) and a 40-pixel-wide band (the sea).
        let mask: Vec<bool> = (0..w * h).map(|i| (i % w >= 10 && i % w < 14 && i / w >= 10 && i / w < 14) || i % w >= 24).collect();
        let m = majority(&mask, w, h, 4);
        assert!(!m[12 * w + 12], "small patch dropped");
        assert!(m[30 * w + 40] && m[30 * w + 25], "large region kept up to its edge");
        assert!(!m[30 * w + 22]);
    }

    #[test]
    fn levels_blend_across_sheets() {
        let d = [([0.0, 0.0, 20000.0, 20000.0], [10.0; 4]), ([20000.0, 0.0, 40000.0, 20000.0], [30.0; 4])];
        assert_eq!(levels_at(&d, 5000.0, 10000.0), Some([10.0; 4]), "deep inside a sheet: its own levels");
        assert_eq!(levels_at(&d, 20000.0, 10000.0), Some([20.0; 4]), "on the border: the mean");
        let near = levels_at(&d, 19000.0, 10000.0).unwrap()[0];
        assert!(near > 10.0 && near < 20.0);
        assert_eq!(levels_at(&d, 5000.0, 30000.0), None, "far outside every sheet");
    }

    #[test]
    fn sheet_levels_ignore_the_fill() {
        let mut px = vec![255u8; 3 * 1000]; // white fill
        for i in 0..1000 {
            px.extend([20 + (i % 100) as u8, 30 + (i % 100) as u8, 40 + (i % 100) as u8]);
        }
        let l = sheet_levels(&px);
        assert_eq!(&l[..3], &[20.0, 30.0, 40.0]);
        assert_eq!(l[3], 139.0, "the brightest band's 99.5th percentile");
    }

    #[test]
    fn photo_water() {
        assert!(is_photo_water([30.0, 75.0, 85.0]), "deep sea");
        assert!(is_photo_water([110.0, 160.0, 165.0]), "shallow sea");
        assert!(!is_photo_water([200.0, 185.0, 160.0]), "sand");
        assert!(!is_photo_water([45.0, 48.0, 52.0]), "shadow");
        assert!(!is_photo_water([60.0, 80.0, 50.0]), "field");
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
