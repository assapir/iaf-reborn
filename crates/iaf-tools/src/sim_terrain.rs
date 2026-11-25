//! `iaf-sim terrain` (modern-iaf/docs/terrain.md): Modern IAF's theatre from open data, in the shape `terrain::theatre`
//! writes (docs/formats/ptt.md "Converted layout": colour nodes `L<l>/c_<i>_<j>.jpg`, 16-bit height nodes
//! `L<l>/h_<i>_<j>.png` for the levels 6–11, `meta.json`), so `shared/terrain/terrain.gd` and `IafHeights` read it
//! unchanged.
//!
//! The frame is UTM zone 36N (EPSG:32636) at 1 terrain unit = 1 m: terrain unit (tx, ty) is easting `E0 + tx`,
//! northing `N1 − ty`, so `meta.json`'s `x_shift` / `y_shift` are `E0` / `N1` and the engine's world X / Y are the
//! UTM easting / northing. Heights: Copernicus GLO-30 (cached under `assets/source/dem/`), warped to a 64 m grid.
//! Colour: ESA WorldCover's Sentinel-2 composite (range reads; 8 m nodes over the detail area, 32 m elsewhere) and
//! the Survey of Israel 2 m sheets already downloaded (2 m nodes, levelled per sheet as the original game's Survey
//! layer, and the 4 m and 8 m nodes over them from these). GDAL does every reprojection.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use anyhow::{Context, Result, bail};
use image::RgbImage;
use image::imageops::{FilterType, resize};

use crate::imagery::{self, read_envi, save};
use crate::imagery_run::{
    BUCKET, Edges, Sheet, gdal, list_sheets, list_tiles, tile_box, tile_sources, tile_whole, tiles_begun,
};
use crate::log;
use crate::progress::{Part, Progress, check, utf8};
use crate::sim_bases::{utm36n, utm36n_geo};

/// The theatre in UTM 36N metres (E0, N0, E1, N1): Ramon, Hatzerim, Nevatim and Ramat David with ≥ 150 km around
/// them, the corners on multiples of 1024 m (modern-iaf/docs/terrain.md §2).
pub const BOX: [f64; 4] = [507_904.0, 3_255_296.0, 855_040.0, 3_766_272.0];
/// Israel's bounding box (lon 34.2–35.95° E, lat 29.45–33.35° N) in UTM 36N, the "detail area": 8 m Sentinel-2
/// nodes in every level-5 node it touches, 32 m elsewhere.
pub const DETAIL: [f64; 4] = [611_000.0, 3_258_000.0, 786_500.0, 3_694_000.0];
const NODE_PIXELS: u32 = 1024;
const HEIGHT_LEVEL: u32 = 6;
pub const ROOT_LEVEL: u32 = 11;
/// Height grid spacing: the level-6 texel (2^6 units of 1 m).
const DEM_STEP: f64 = 64.0;
/// Raw height = SEA_LEVEL_RAW + metres · HEIGHT_SCALE (0.1 m steps, −500 m to 6,000 m).
const SEA_LEVEL_RAW: f64 = 5000.0;
const HEIGHT_SCALE: f64 = 10.0;
/// The Sentinel-2 composite has no pixels over open sea away from the coast: this colour fills them (the
/// composite's own open-sea tone at the edge of its pixels off Tel Aviv and Ashdod, measured 2026-11-08,
/// modern-iaf/docs/terrain.md §3).
const SEA: [u8; 3] = [53, 72, 82];
/// The fill before 2026-11-08, darker than the composite's sea (its edge showed as steps): `repaint_sea` turns it into
/// SEA in a theatre built with it.
const OLD_SEA: [u8; 3] = [30, 52, 78];
/// The 32 m nodes read the composite's 20 m overviews, whose pixels at the composite's edge were averaged with its
/// no-data (zero): a rim up to two 32 m pixels wide, darker than both the fill and the sea inside it (51, 69, 79
/// against SEA and 62, 87, 94 off El Arish, measured 2026-11-11), drew a faint line where Sentinel-2 ends offshore
/// (modern-iaf/docs/terrain.md §3). Pixels within RIM of no-data take SEA there. The 8 m nodes' bilinear warp skips
/// the no-data, so their edge keeps the composite's own colour.
const RIM: usize = 2;
pub const ATTRIBUTION: [&str; 3] = [
    "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved",
    "Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium; ESA WorldCover project 2021 (CC BY 4.0)",
    "© Survey of Israel 2015, via data.gov.il",
];
/// Copernicus WorldDEM-30 licence, Article 6 (c): this sentence goes with every distribution.
pub const DEM_LIABILITY: &str = "The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30";

/// A Survey sheet's extent (ITM), its levels (`imagery::sheet_levels`: per-band dark, white) and its tone to its
/// neighbours (`sheet_tone`: a log gain per band), blended across sheet borders by `imagery::levels_at`.
type SheetLevels = ([f64; 4], [f32; 7]);

/// A Survey pixel at ITM `itm` through its sheets' levels (the original game's `mapi2015_modern`) and tone.
fn photo_px(levels: &[SheetLevels], itm: [f64; 2], rgb: [f32; 3]) -> [f32; 3] {
    let Some(l) = imagery::levels_at(levels, itm[0], itm[1]) else { return rgb };
    let v = imagery::photo_levels(rgb, [l[0], l[1], l[2], l[3]]);
    [0, 1, 2].map(|c| (v[c] * l[4 + c].exp()).min(255.0))
}

/// A node: level, i (east), j (south); it covers units [i, i+1) × [j, j+1) · (1024 << level).
type Key = (u32, u32, u32);

fn span(level: u32) -> f64 {
    f64::from(NODE_PIXELS << level)
}

/// The airbases' outlines (`boundary`, lat / lon, of `<dir>/*.json`, modern-iaf/docs/airbases.md) in UTM 36N.
fn base_outlines(dir: &Path) -> Result<Vec<Vec<[f64; 2]>>> {
    let mut out = Vec::new();
    // Without them the Survey's painted-over bases would show: a missing folder is an error.
    for e in std::fs::read_dir(dir).with_context(|| format!("{}: the airbases' layouts", dir.display()))? {
        let p = e?.path();
        if p.extension().is_none_or(|x| x != "json") {
            continue;
        }
        let v: serde_json::Value = serde_json::from_slice(&std::fs::read(&p)?)?;
        let pts: Vec<[f64; 2]> = v["boundary"]
            .as_array()
            .with_context(|| format!("{}: no boundary", p.display()))?
            .iter()
            .filter_map(|q| Some([q[1].as_f64()?, q[0].as_f64()?]))
            .collect();
        out.push(pts.iter().map(|p| utm36n(p[0], p[1])).collect());
    }
    Ok(out)
}

/// One `iaf-sim terrain` run.
pub struct Run {
    /// The theatre folder (`assets/converted/terrain/israel`).
    pub out: PathBuf,
    /// The DEM tile cache (`assets/source/dem`).
    pub dem_cache: PathBuf,
    /// The WorldCover tile cache shared with the original game (`assets/source/imagery/sentinel2`, imagery_run::S2_CACHE).
    pub s2_cache: PathBuf,
    /// The original game's measured sheet extents and levels (`converted/imagery/.work/mapi2015/sheets.tsv`): a
    /// first run starts from them (each line is checked against its ZIP's size and date) instead of measuring again.
    pub sheet_index: PathBuf,
    /// The Survey of Israel sheet ZIPs (`assets/source/imagery/mapi2015`); none there = no 2 m nodes.
    pub sheets: PathBuf,
    /// The airbases' layouts (`modern-iaf/data/airbases`): Sentinel-2 replaces the Survey photo inside their outlines.
    pub airbases: PathBuf,
    /// The assets folder whose `source/scenery` and `source/roads` hold the OpenStreetMap extracts (`sim_coast`): with
    /// the Survey, its coastline is where the photo gives way to the sea.
    pub osm: PathBuf,
    pub area: [f64; 4],
    pub detail: [f64; 4],
    pub threads: usize,
}

/// The theatre: the box in UTM and its size in units.
#[derive(Clone, Copy)]
struct Frame {
    e0: f64,
    n1: f64,
    w: u32,
    h: u32,
}

impl Frame {
    fn new(b: [f64; 4]) -> Result<Self> {
        let (w, h) = (b[2] - b[0], b[3] - b[1]);
        if w <= 0.0 || h <= 0.0 || w % 1024.0 != 0.0 || h % 1024.0 != 0.0 {
            bail!("box {b:?}: want E0 < E1, N0 < N1 and a size in whole 1024 m");
        }
        Ok(Self { e0: b[0], n1: b[3], w: w as u32, h: h as u32 })
    }
    /// The node's UTM extent (xmin, ymin, xmax, ymax), as gdalwarp's `-te`.
    fn utm(&self, k: Key) -> [f64; 4] {
        let s = span(k.0);
        let (x0, y0) = (f64::from(k.1) * s, f64::from(k.2) * s);
        [self.e0 + x0, self.n1 - y0 - s, self.e0 + x0 + s, self.n1 - y0]
    }
    /// The nodes of `level` inside the theatre.
    fn nodes(&self, level: u32) -> Vec<Key> {
        let s = NODE_PIXELS << level;
        (0..self.h.div_ceil(s)).flat_map(|j| (0..self.w.div_ceil(s)).map(move |i| (level, i, j))).collect()
    }
    /// The nodes of `level` touching the UTM rect `r` (none when `r` lies outside the theatre).
    fn nodes_in(&self, level: u32, r: [f64; 4]) -> Vec<Key> {
        let s = span(level);
        let (e1, n0) = (self.e0 + f64::from(self.w), self.n1 - f64::from(self.h));
        if r[2] <= self.e0 || r[0] >= e1 || r[3] <= n0 || r[1] >= self.n1 {
            return Vec::new();
        }
        let tx = |e: f64| ((e - self.e0) / s).clamp(0.0, f64::from(self.w) / s);
        let ty = |n: f64| ((self.n1 - n) / s).clamp(0.0, f64::from(self.h) / s);
        let (i0, i1, j0, j1) = (tx(r[0]).floor(), tx(r[2]).ceil(), ty(r[3]).floor(), ty(r[1]).ceil());
        (j0 as u32..j1 as u32).flat_map(|j| (i0 as u32..i1 as u32).map(move |i| (level, i, j))).collect()
    }
}

/// The DEM resampled to the theatre's height grid: point (x, y) at UTM (E0 + 64x, N1 − 64y), metres above the
/// EGM2008 geoid (≈ mean sea level), 0 where GLO-30 has no tile (open sea).
pub struct HeightGrid {
    pub w: usize,
    pub h: usize,
    pub data: Vec<f32>,
}

impl HeightGrid {
    /// The raw (encoded) height of texel (x, y) of node (level, i, j); the theatre's east / south edge repeats.
    fn raw(&self, level: u32, i: u32, j: u32, x: u32, y: u32) -> u16 {
        let k = level - HEIGHT_LEVEL;
        let gx = (((i * NODE_PIXELS + x) as usize) << k).min(self.w - 1);
        let gy = (((j * NODE_PIXELS + y) as usize) << k).min(self.h - 1);
        // ponytail: coarser levels point-sample the 64 m grid; average if far ridges shimmer.
        (SEA_LEVEL_RAW + f64::from(self.data[gy * self.w + gx]) * HEIGHT_SCALE).round().clamp(0.0, 65535.0) as u16
    }
}

/// The bases' graded ground (modern-iaf/docs/terrain.md "Graded airbases"), its version in GRADE_FILE beside
/// `meta.json` (not in the stamp: a new grading rewrites the height nodes around the bases alone and leaves `meta.json`,
/// which the scenery's stamp reads, as it was; the scenery reads no ground height). The grid points
/// within GRADE_IN m of the pavement take the graded surface, fading back to the DEM at GRADE_OUT (a 64 m texel's
/// diagonal is 91 m: every texel touching the pavement is graded whole).
const GRADE: &str = "runway quadratic, smoothed apron, 96-320 m shoulder";
const GRADE_FILE: &str = "grade.txt";
const GRADE_IN: f64 = 96.0;
const GRADE_OUT: f64 = 320.0;
/// The graded surface: the base's runway surface (one quadratic fitted to the DEM on its runways, so crossing runways
/// meet) to RUNWAY_IN m off a runway's edge, fading to the smoothed DEM (the taxiways, aprons) at RUNWAY_OUT.
const RUNWAY_IN: f64 = 100.0;
const RUNWAY_OUT: f64 = 400.0;
/// The smoothed DEM: imagery::blur's box of this radius (grid points), twice (σ ≈ 230 m).
const GRADE_BLUR: i32 = 4;

/// 1 up to `a`, 0 from `b`, smooth between.
fn fade(d: f64, a: f64, b: f64) -> f64 {
    let t = ((b - d) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Grades base `b`'s runways, taxiways and aprons in the grid (see GRADE); returns the UTM rect it changed, None for
/// a base outside the theatre.
fn grade_base(g: &mut HeightGrid, f: &Frame, b: &crate::sim_bases::Base) -> Option<[f64; 4]> {
    let pts: Vec<[f64; 2]> = b
        .runways
        .iter()
        .flat_map(|r| r.ends)
        .chain(b.taxiways.iter().flat_map(|t| t.0.iter().copied()))
        .chain(b.stopways.iter().chain(&b.aprons).chain(&b.shelters).flatten().copied())
        .collect();
    let m = GRADE_OUT + DEM_STEP * f64::from(2 * GRADE_BLUR + 2);
    let lo = |k: usize| pts.iter().map(|p| p[k]).fold(f64::INFINITY, f64::min) - m;
    let hi = |k: usize| pts.iter().map(|p| p[k]).fold(f64::NEG_INFINITY, f64::max) + m;
    let gx = |e: f64| ((e - f.e0) / DEM_STEP).clamp(0.0, (g.w - 1) as f64) as usize;
    let gy = |n: f64| ((f.n1 - n) / DEM_STEP).clamp(0.0, (g.h - 1) as f64) as usize;
    let (x0, x1, y0, y1) = (gx(lo(0)), gx(hi(0)), gy(hi(1)), gy(lo(1)));
    if pts.is_empty() || x0 >= x1 || y0 >= y1 {
        return None;
    }
    let (w, h) = (x1 - x0 + 1, y1 - y0 + 1);
    let at = |k: usize| [f.e0 + DEM_STEP * (x0 + k % w) as f64, f.n1 - DEM_STEP * (y0 + k / w) as f64];
    let dem: Vec<f32> = (0..w * h).map(|k| g.data[(y0 + k / w) * g.w + x0 + k % w]).collect();
    let near: Vec<[f64; 2]> = (0..w * h).map(|k| [b.runway_dist(at(k)), b.paved_dist(at(k))]).collect();
    // The runway surface: least squares over the grid points within a texel of a runway, in km about their centre.
    let on: Vec<usize> = (0..w * h).filter(|&k| near[k][0] <= DEM_STEP).collect();
    let c = on.iter().fold([0.0; 2], |s, &k| [s[0] + at(k)[0], s[1] + at(k)[1]]).map(|v| v / on.len().max(1) as f64);
    let terms = |p: [f64; 2]| {
        let (x, y) = ((p[0] - c[0]) / 1000.0, (p[1] - c[1]) / 1000.0);
        [1.0, x, y, x * x, x * y, y * y]
    };
    let (mut a, mut q) = (vec![0.0; 36], vec![[0.0; 2]; 6]);
    for &k in &on {
        let (t, z) = (terms(at(k)), f64::from(dem[k]));
        for ((ti, qi), row) in t.iter().zip(&mut q).zip(a.chunks_mut(6)) {
            qi[0] += ti * z;
            row.iter_mut().zip(&t).for_each(|(r, tj)| *r += ti * tj);
        }
    }
    crate::georef::solve(&mut a, &mut q, 6)?;
    let runway = |p: [f64; 2]| terms(p).iter().zip(&q).map(|(t, q)| t * q[0]).sum::<f64>();
    let mut smooth = dem.clone();
    imagery::blur(&mut smooth, w, h, GRADE_BLUR);
    for (k, (&[dr, dp], (&d, &s))) in near.iter().zip(dem.iter().zip(&smooth)).enumerate() {
        let (d, s) = (f64::from(d), f64::from(s));
        let graded = s + (runway(at(k)) - s) * fade(dr, RUNWAY_IN, RUNWAY_OUT);
        g.data[(y0 + k / w) * g.w + x0 + k % w] = (d + (graded - d) * fade(dp, GRADE_IN, GRADE_OUT)) as f32;
    }
    let (sw, ne) = (at(w * (h - 1)), at(w - 1));
    Some([sw[0], sw[1], ne[0], ne[1]])
}

/// The UTM rect's lon / lat bounding box (17 points per side).
fn geo_bbox(r: [f64; 4]) -> Result<[f64; 4]> {
    let mut pts = Vec::new();
    for t in 0..=16 {
        let f = f64::from(t) / 16.0;
        let (x, y) = (r[0] + (r[2] - r[0]) * f, r[1] + (r[3] - r[1]) * f);
        pts.extend([[x, r[1]], [x, r[3]], [r[0], y], [r[2], y]]);
    }
    let g: Vec<[f64; 2]> = pts.iter().map(|p| utm36n_geo(p[0], p[1])).collect();
    Ok(crate::bbox(&g))
}

/// gdalwarp of `src` to the UTM rect `te` at `size` pixels into ENVI (band-interleaved by pixel) at `bin`.
fn warp(src: &str, te: [f64; 4], size: [usize; 2], extra: &[&str], bin: &Path) -> Result<imagery::Envi> {
    warp_in("EPSG:32636", src, te, size, extra, bin)
}

/// `warp` to the grid `srs` (`te` in its metres).
fn warp_in(srs: &str, src: &str, te: [f64; 4], size: [usize; 2], extra: &[&str], bin: &Path) -> Result<imagery::Envi> {
    let te = te.map(|v| format!("{v}"));
    let ts = size.map(|v| v.to_string());
    let mut a = vec!["-q", "-overwrite", "-t_srs", srs, "-te", &te[0], &te[1], &te[2], &te[3]];
    a.extend(["-ts", &ts[0], &ts[1], "-wm", "256", "-of", "ENVI", "-co", "INTERLEAVE=BIP"]);
    a.extend(extra);
    a.extend([src, utf8(bin)?]);
    // Network hiccups make GDAL fail without a message: retry (as imagery_run's units).
    let mut tries = 0;
    while let Err(e) = gdal("gdalwarp", &a) {
        tries += 1;
        if tries == 4 {
            return Err(e);
        }
        std::thread::sleep(std::time::Duration::from_secs(5 * tries));
    }
    let e = read_envi(bin);
    for f in [bin.to_path_buf(), bin.with_extension("hdr"), PathBuf::from(format!("{}.aux.xml", bin.display()))] {
        let _ = std::fs::remove_file(f);
    }
    e
}

/// The DEM tiles `src` (any GDAL raster with heights in metres) warped to the frame's height grid.
pub fn dem_grid(src: &[PathBuf], area: [f64; 4], work: &Path) -> Result<HeightGrid> {
    let f = Frame::new(area)?;
    let vrt = work.join("dem.vrt");
    let mut a = vec!["-q", "-overwrite", utf8(&vrt)?];
    for s in src {
        a.push(utf8(s)?);
    }
    gdal("gdalbuildvrt", &a)?;
    let half = DEM_STEP / 2.0;
    let te = [f.e0 - half, f.n1 - f64::from(f.h) - half, f.e0 + f64::from(f.w) + half, f.n1 + half];
    let size = [(f.w as f64 / DEM_STEP) as usize + 1, (f.h as f64 / DEM_STEP) as usize + 1];
    let e = warp(
        utf8(&vrt)?,
        te,
        size,
        &["-r", "average", "-ot", "Float32", "-dstnodata", "-32768"],
        &work.join("dem_grid.bin"),
    )?;
    if e.bands != 1 || e.dtype != "4" || e.raw.len() != size[0] * size[1] * 4 {
        bail!("DEM grid: want 1 band of f32, got {} / type {}", e.bands, e.dtype);
    }
    let data = e
        .raw
        .as_chunks::<4>()
        .0
        .iter()
        .map(|b| f32::from_le_bytes(*b))
        .map(|v| if v <= -32767.0 { 0.0 } else { v })
        .collect();
    Ok(HeightGrid { w: size[0], h: size[1], data })
}

/// Height nodes `L<l>/h_<i>_<j>.png` for the levels 6–11: 1025² texels (the neighbour's first row / column
/// included), R = high byte, G = low byte, as `terrain::theatre`. With `only`, just the nodes touching those UTM rects.
fn write_heights(
    f: &Frame,
    g: &HeightGrid,
    out: &Path,
    only: Option<&[[f64; 4]]>,
    threads: usize,
    cancel: &AtomicBool,
) -> Result<()> {
    let touches = |k: &Key| {
        let n = f.utm(*k);
        only.is_none_or(|rs| rs.iter().any(|r| r[0] < n[2] && n[0] < r[2] && r[1] < n[3] && n[1] < r[3]))
    };
    let nodes: Vec<Key> = (HEIGHT_LEVEL..=ROOT_LEVEL).flat_map(|l| f.nodes(l)).filter(touches).collect();
    par(&nodes, threads, cancel, |&(l, i, j)| {
        let img = RgbImage::from_fn(NODE_PIXELS + 1, NODE_PIXELS + 1, |x, y| {
            let v = g.raw(l, i, j, x, y);
            image::Rgb([(v >> 8) as u8, (v & 0xff) as u8, 0])
        });
        img.save(out.join(format!("L{l}/h_{i}_{j}.png")))?;
        Ok(())
    })
}

/// Runs `f` on every item on `threads` workers; stops at the first error or a cancel.
pub(crate) fn par<T: Sync>(
    items: &[T],
    threads: usize,
    cancel: &AtomicBool,
    f: impl Fn(&T) -> Result<()> + Sync,
) -> Result<()> {
    use rayon::prelude::*;
    crate::progress::pool(threads)?.install(|| items.par_iter().try_for_each(|it| check(cancel).and_then(|()| f(it))))
}

fn colour_path(out: &Path, k: Key) -> PathBuf {
    out.join(format!("L{}/c_{}_{}.jpg", k.0, k.1, k.2))
}

/// Node `k`'s part of its ancestor at `level` (written already), upsampled to a node.
fn ancestor_crop(out: &Path, k: Key, level: u32) -> Result<RgbImage> {
    let d = level - k.0;
    let a = image::open(colour_path(out, (level, k.1 >> d, k.2 >> d)))?.to_rgb8();
    let part = NODE_PIXELS >> d;
    let (x, y) = ((k.1 & ((1 << d) - 1)) * part, (k.2 & ((1 << d) - 1)) * part);
    let crop = image::imageops::crop_imm(&a, x, y, part, part).to_image();
    Ok(resize(&crop, NODE_PIXELS, NODE_PIXELS, FilterType::Triangle))
}

/// The written colour nodes of `level`.
fn written(out: &Path, level: u32) -> Result<BTreeSet<Key>> {
    let mut v = BTreeSet::new();
    let Ok(entries) = std::fs::read_dir(out.join(format!("L{level}"))) else { return Ok(v) };
    for e in entries {
        let name = e?.file_name().to_string_lossy().to_string();
        if let Some((i, j)) =
            name.strip_prefix("c_").and_then(|s| s.strip_suffix(".jpg")).and_then(|s| s.split_once('_'))
        {
            v.insert((level, i.parse()?, j.parse()?));
        }
    }
    Ok(v)
}

/// Every parent of the nodes of `level − 1`, from the children.
fn parents(out: &Path, level: u32, fallback: Option<u32>, threads: usize, cancel: &AtomicBool) -> Result<()> {
    let ps: Vec<Key> = written(out, level - 1)?
        .into_iter()
        .map(|c| (level, c.1 >> 1, c.2 >> 1))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    // A missing child is `fallback`'s (None: black, outside the theatre).
    par(&ps, threads, cancel, |&p| {
        let img = imagery::compose_parent(p, |c| {
            let path = colour_path(out, c);
            let img = if path.exists() {
                Some(image::open(path)?.to_rgb8())
            } else {
                fallback.map(|l| ancestor_crop(out, c, l)).transpose()?
            };
            Ok(img.map(std::sync::Arc::new))
        })?;
        save(&img, &colour_path(out, p))
    })
}

/// Every colour node's OLD_SEA pixels (within JPEG's noise) made SEA, once per theatre (its mark in `work`).
fn repaint_sea(out: &Path, work: &Path, threads: usize, cancel: &AtomicBool) -> Result<()> {
    let mark = work.join(format!("done_sea_{}_{}_{}", SEA[0], SEA[1], SEA[2]));
    if mark.exists() {
        return Ok(());
    }
    let mut nodes = Vec::new();
    for l in 1..=ROOT_LEVEL {
        nodes.extend(written(out, l)?);
    }
    par(&nodes, threads, cancel, |&k| {
        let mut img = image::open(colour_path(out, k))?.to_rgb8();
        let mut changed = false;
        for p in img.pixels_mut() {
            if p.0.iter().zip(OLD_SEA).all(|(&v, o)| v.abs_diff(o) <= 8) {
                p.0 = SEA;
                changed = true;
            }
        }
        if changed {
            save(&img, &colour_path(out, k))?;
        }
        Ok(())
    })?;
    std::fs::write(mark, "")?;
    Ok(())
}

/// A unit's mark: its nodes are written (a run after a failure skips it).
fn done(work: &Path, what: &str, k: Key) -> PathBuf {
    work.join(format!("done_{what}_{}_{}_{}", k.0, k.1, k.2))
}

/// Sentinel-2 (the VRT `vrt`) over one unit (a node of `unit.0`), cut into its nodes of `level` that `want` keeps,
/// toned at the border (`border`).
fn sentinel_unit(
    (vrt, border): (&str, Option<&BorderTone>),
    f: &Frame,
    unit: Key,
    level: u32,
    want: &(dyn Fn(Key) -> bool + Sync),
    work: &Path,
    out: &Path,
) -> Result<()> {
    let d = unit.0 - level;
    let n = (NODE_PIXELS << d) as usize;
    let r = if level >= 5 { "average" } else { "bilinear" };
    let bin = work.join(format!("s2_{}_{}_{}.bin", unit.0, unit.1, unit.2));
    let extra = ["-r", r, "-srcnodata", "0", "-dstnodata", "0", "-wo", "UNIFIED_SRC_NODATA=YES"];
    let e = warp(vrt, f.utm(unit), [n, n], &extra, &bin)?;
    if e.bands != 4 || e.dtype != "12" || e.raw.len() != n * n * 8 {
        bail!("Sentinel-2 unit {unit:?}: want 4 bands of u16, got {} / type {}", e.bands, e.dtype);
    }
    let px = e.raw.as_chunks::<2>().0;
    let empty = |i: usize| (0..3).all(|c| px[i * 4 + c] == [0, 0]);
    let sea = if level >= 5 { near_empty(n, RIM, empty) } else { (0..n * n).map(empty).collect() };
    let m = NODE_PIXELS as usize;
    for sj in 0..1u32 << d {
        for si in 0..1u32 << d {
            let k = (level, (unit.1 << d) + si, (unit.2 << d) + sj);
            if !want(k) {
                continue;
            }
            let (rect, step) = (f.utm(k), span(level) / f64::from(NODE_PIXELS));
            let img = RgbImage::from_fn(NODE_PIXELS, NODE_PIXELS, |x, y| {
                let p = (sj as usize * m + y as usize) * n + si as usize * m + x as usize;
                if sea[p] {
                    return image::Rgb(SEA);
                }
                let b = |c: usize| f32::from(u16::from_le_bytes(px[p * 4 + c]));
                let mut c = imagery::tone([b(0), b(1), b(2)]);
                if let Some(bt) = border {
                    let (e, n) = (rect[0] + (f64::from(x) + 0.5) * step, rect[3] - (f64::from(y) + 0.5) * step);
                    c = bt.tone(e, n, c);
                }
                image::Rgb(c.map(|v| v.round() as u8))
            });
            save(&img, &colour_path(out, k))?;
        }
    }
    Ok(())
}

/// Per pixel of an n × n raster: some pixel within `r` (a square) is empty.
fn near_empty(n: usize, r: usize, empty: impl Fn(usize) -> bool) -> Vec<bool> {
    let row: Vec<bool> = (0..n * n)
        .map(|i| {
            let (x, y) = (i % n, i / n);
            (x.saturating_sub(r)..=(x + r).min(n - 1)).any(|x| empty(y * n + x))
        })
        .collect();
    (0..n * n)
        .map(|i| {
            let (x, y) = (i % n, i / n);
            (y.saturating_sub(r)..=(y + r).min(n - 1)).any(|y| row[y * n + x])
        })
        .collect()
}

/// What the Survey units share: the sheets' levels (per sheet extent, blended by `levels_at`) and the airbases'
/// outlines (UTM).
struct Survey<'a> {
    vrt: &'a str,
    /// OpenStreetMap's coastline: on its water side the photo gives way to Sentinel-2 (the sheets' white no-data and
    /// the sea's JPEG noise never show).
    coast: &'a crate::sim_coast::Coast,
    levels: Vec<SheetLevels>,
    bases: &'a [Vec<[f64; 2]>],
    /// Each base's Sentinel-2 toned to the photo around it.
    tones: Vec<BaseTone>,
}

/// Sentinel-2 on an airbase toned to the levelled photo around it (2026-11-14; before, its own colours: a tan block in
/// the photo's grey at every base). Both images on TONE_CELL_M cells over the ground the photo shows within
/// TONE_REACH_M of the outline (off the bases' cover, BaseMask), over the cells whose brightness ratio is within
/// TONE_KEEP of the median one: the base's median brightness (Sentinel-2's inside the outline) to the photo's, the
/// spread about it brought to the photo's (TONE_SPREAD), and Sentinel-2's tint scaled onto the photo's. Tried the
/// same day and dropped: the ratio of local means (one darker Survey sheet beside Ramon shaded its south-west; carried
/// to the base's brighter dry grass from the darker fields around Ramat David it made an icy white); a histogram match
/// per band (Ramon pink with black blots, its values past the ring's on both ends); gain and offset per band (Ramon
/// black-red); a ratio per band (Ramon cyan, Hatzerim's grey roofs and gravel pale blue).
#[derive(Clone, Copy)]
struct BaseTone {
    /// The UTM rect it serves: the outline's box and TONE_REACH_M around it.
    rect: [f64; 4],
    /// The gain and offset from Sentinel-2's brightness (the bands' mean) to the photo's.
    grey: [f32; 2],
    /// The factor on Sentinel-2's tint (a band's value over the bands' mean), and the tint added.
    chroma: f32,
    tint: [f32; 3],
    /// The photo's bright ground around (TONE_KNEE_AT of its cells darker): brighter toned values come down toward it.
    knee: f32,
}

const TONE_CELL_M: f64 = 40.0;
const TONE_REACH_M: f64 = 3000.0;
const TONE_CHROMA_MAX: f32 = 40.0;
/// The spread's factor's bounds: above 1 a base's own difference from the ground around grew with it (cyan at Ramon,
/// blue-grey at Hatzerim, where the photo spreads more than Sentinel-2).
const TONE_SPREAD: [f32; 2] = [0.5, 1.0];
/// The knee: the photo's cells darker than it around a base, and the brightness's slope above it.
const TONE_KNEE_AT: f32 = 0.9;
const TONE_KNEE_SLOPE: f32 = 0.3;
/// The least factor on Sentinel-2's tint: the photo's tint scaled onto it (0.08 around Ramat David, whose fields
/// Sentinel-2 sees green and brown where the photo is mauve-grey) left the base's dry grass grey.
const TONE_CHROMA_MIN: f32 = 0.3;
/// The brightness ratios kept: within this factor of their median.
const TONE_KEEP: f32 = 1.25;

impl BaseTone {
    /// The tone of base `outline` from the level-3 Sentinel-2 nodes (written by the 8 m units, before the photo) and
    /// the photo warped to TONE_CELL_M; None when the photo shows nowhere around it.
    fn new(sv: &Survey, f: &Frame, outline: &[[f64; 2]], out: &Path, work: &Path) -> Result<Option<Self>> {
        let b = crate::bbox(outline.iter());
        let c = TONE_CELL_M;
        let r = [b[0] - TONE_REACH_M, b[1] - TONE_REACH_M, b[2] + TONE_REACH_M, b[3] + TONE_REACH_M];
        let (w, h) = (((r[2] - r[0]) / c).ceil() as usize, ((r[3] - r[1]) / c).ceil() as usize);
        let r = [r[0], r[3] - h as f64 * c, r[0] + w as f64 * c, r[3]];
        let bin = work.join(format!("tone_{:.0}_{:.0}.bin", r[0], r[1]));
        let extra = ["-r", "average", "-srcnodata", "255 255 255", "-wo", "UNIFIED_SRC_NODATA=YES", "-dstalpha"];
        let e = warp(sv.vrt, r, [w, h], &extra, &bin)?;
        if e.bands != 4 || e.raw.len() != w * h * 4 {
            bail!("base tone: want RGBA bytes, got {} bands", e.bands);
        }
        // Sentinel-2's mean over each cell.
        let mut s2 = vec![[0f32; 3]; w * h];
        let mut count = vec![0f32; w * h];
        for k in f.nodes_in(3, r) {
            let Ok(img) = image::open(colour_path(out, k)) else { continue };
            let (img, nr) = (img.to_rgb8(), f.utm(k));
            let px = (nr[2] - nr[0]) / f64::from(img.width());
            for (x, y, p) in img.enumerate_pixels() {
                let (e, n) = (nr[0] + (f64::from(x) + 0.5) * px, nr[3] - (f64::from(y) + 0.5) * px);
                let (cx, cy) = (((e - r[0]) / c).floor(), ((r[3] - n) / c).floor());
                if cx < 0.0 || cy < 0.0 || cx >= w as f64 || cy >= h as f64 {
                    continue;
                }
                let i = cy as usize * w + cx as usize;
                for k in 0..3 {
                    s2[i][k] += f32::from(p[k]);
                }
                count[i] += 1.0;
            }
        }
        // Both images on the cells where the photo shows (levelled) and Sentinel-2 has data, off the bases' cover.
        let mask = BaseMask::new(sv.bases, r);
        let (mut sat, mut photo, mut inner) = (Vec::new(), Vec::new(), Vec::new());
        for i in (0..w * h).filter(|&i| count[i] > 0.0) {
            let q = [r[0] + ((i % w) as f64 + 0.5) * c, r[3] - ((i / w) as f64 + 0.5) * c];
            let px = &e.raw[i * 4..i * 4 + 4];
            let cover = mask.as_ref().map_or(0.0, |k| k.at(q[0], q[1]));
            if cover >= 1.0 {
                inner.push(s2[i].map(|v| v / count[i]));
            }
            if px[3] < 250 || px[..3].iter().all(|&v| v >= NEAR_WHITE) || cover > 0.0 {
                continue;
            }
            let g = utm36n_geo(q[0], q[1]);
            let itm = crate::itm::from_wgs84(g[0], g[1]);
            let rgb = [0, 1, 2].map(|k| f32::from(px[k]));
            photo.push(photo_px(&sv.levels, itm, rgb));
            sat.push(s2[i].map(|v| v / count[i]));
        }
        Ok(Self::fit(r, &photo, &sat, &inner))
    }

    /// The tone from the photo's and Sentinel-2's colours on the same cells (`photo`, `sat`), Sentinel-2's median
    /// brightness over `inner` brought to the photo's (a base's own ground; at the border the same cells); None
    /// without cells.
    fn fit(r: [f64; 4], photo: &[[f32; 3]], sat: &[[f32; 3]], inner: &[[f32; 3]]) -> Option<Self> {
        if sat.is_empty() || inner.is_empty() {
            return None;
        }
        let q = |v: &[[f32; 3]], f: f32, band: Option<usize>| {
            let mut v: Vec<f32> = v.iter().map(|p| band.map_or((p[0] + p[1] + p[2]) / 3.0, |k| p[k])).collect();
            let i = ((v.len() - 1) as f32 * f).round() as usize;
            *v.select_nth_unstable_by(i, f32::total_cmp).1
        };
        // The cells whose brightness ratio is within TONE_KEEP of the median's: a darker Survey sheet beside Ramon is
        // out.
        let grey = |p: &[f32; 3]| (p[0] + p[1] + p[2]) / 3.0 + 4.0;
        let ratios: Vec<[f32; 3]> = photo.iter().zip(sat).map(|(p, s)| [grey(p) / grey(s); 3]).collect();
        let m = q(&ratios, 0.5, Some(0));
        let keep = |i: &usize| (m / TONE_KEEP..=m * TONE_KEEP).contains(&ratios[*i][0]);
        let kp: Vec<[f32; 3]> = (0..photo.len()).filter(keep).map(|i| photo[i]).collect();
        let ks: Vec<[f32; 3]> = (0..sat.len()).filter(keep).map(|i| sat[i]).collect();
        // The ratio of those cells' median brightness (one ratio per band turned Hatzerim's grey roofs and gravel pale
        // blue, the desert's ratios applied to a colour other than the desert's). Sentinel-2's values spread as the
        // photo's over every cell (one factor, at most 1: over the kept cells alone the deserts' spread halved, their
        // wadis flat).
        let med = [0, 1, 2].map(|k| (q(&kp, 0.5, Some(k)), q(&ks, 0.5, Some(k))));
        let (mp, ms) = med.iter().fold((0.0, 0.0), |(a, b), m| (a + m.0 / 3.0, b + m.1 / 3.0));
        let mr = ((mp + 4.0) / (ms + 4.0)).clamp(0.33, 3.0);
        let spread = |v: &[[f32; 3]]| q(v, 0.75, None) - q(v, 0.25, None);
        let g = (spread(photo) / (mr * spread(sat)).max(1.0)).clamp(TONE_SPREAD[0], TONE_SPREAD[1]);
        // The tint: Sentinel-2's (a band's median over the bands' mean) scaled onto the photo's, and the rest of the
        // photo's added, so grey stays near grey.
        let (tp, ts) = (med.map(|m| m.0 - mp), med.map(|m| m.1 - ms));
        let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
        let chroma = (dot(tp, ts) / dot(ts, ts).max(1.0)).clamp(TONE_CHROMA_MIN, 1.5);
        // The base's median brightness (Sentinel-2's inside the outline) to the photo's around: Sentinel-2 sees the
        // dry grass on a base brighter than the fields around, where the photo's ratio left it a light grey at Ramat
        // David.
        let grey = [mr * g, mp - mr * g * q(inner, 0.5, None)];
        let tint = [0, 1, 2].map(|k| tp[k] - chroma * ts[k]);
        Some(Self { rect: r, grey, chroma, tint, knee: q(photo, TONE_KNEE_AT, None) })
    }

    /// Sentinel-2's colour `v` at UTM (e, n) toned; None outside the rect.
    fn tone(&self, e: f64, n: f64, v: [f32; 3]) -> Option<[f32; 3]> {
        let r = self.rect;
        if e < r[0] || e > r[2] || n < r[1] || n > r[3] {
            return None;
        }
        Some(self.apply(v))
    }

    /// Sentinel-2's colour `v` toned.
    fn apply(&self, v: [f32; 3]) -> [f32; 3] {
        let m = (v[0] + v[1] + v[2]) / 3.0;
        let c = [0, 1, 2].map(|k| m * self.grey[0] + self.grey[1] + self.chroma * (v[k] - m) + self.tint[k]);
        // Above the knee the brightness rises at TONE_KNEE_SLOPE, the hue kept: Sentinel-2's bright tracks in a base's
        // dry grass were white streaks from the cockpit (the runways, taxiways and aprons are painted over).
        let m = (c[0] + c[1] + c[2]) / 3.0;
        let c = if m > self.knee { c.map(|v| v * (self.knee + (m - self.knee) * TONE_KNEE_SLOPE) / m) } else { c };
        // The bands at most TONE_CHROMA_MAX apart: an irrigated lawn's green went a lime disc on Nevatim.
        let m = (c[0] + c[1] + c[2]) / 3.0;
        let spread = c.iter().fold(f32::MIN, |a, &v| a.max(v)) - c.iter().fold(f32::MAX, |a, &v| a.min(v));
        let k = (TONE_CHROMA_MAX / spread.max(1e-3)).min(1.0);
        c.map(|v| (m + (v - m) * k).clamp(0.0, 255.0))
    }
}

/// The neighbours' Sentinel-2 toned to the Survey photo along its edge (2026-11-15; before, the ground changed at the
/// border from the levelled 2 m photo to Sentinel-2's own colours, the user: "the change between israel and other
/// country looks bad"). On BORDER_CELL_M cells over the detail area and BORDER_FEATHER_M around it: the signed distance
/// to the photo's edge (out of the photo positive), and on a BORDER_BLOCK_M grid one BaseTone per block from the cells
/// of the photo within BORDER_SAMPLE_M of its edge (in the block and half a block around), Sentinel-2's own median
/// brightness brought to the photo's there, no knee. A pixel out of the photo takes the blocks' tones blended
/// bilinearly between their centres, fully at the edge and fading out over BORDER_FEATHER_M; the photo's own side
/// keeps Sentinel-2 as it is past BORDER_INSIDE_M (the bases' fill, BaseTone, reads it). Water keeps its colour.
struct BorderTone {
    /// The cells' rect (UTM) and size.
    rect: [f64; 4],
    w: usize,
    h: usize,
    /// Per cell, metres to the photo's edge: > 0 out of the photo, < 0 in it.
    dist: Vec<f32>,
    /// The blocks' tones (None: too few photo cells near the edge), bw per row.
    bw: usize,
    bh: usize,
    tones: Vec<Option<BaseTone>>,
    /// Per cell, the photo's own colour along its edge over the blocks' tone: each band's log ratio (`local`).
    local: Vec<[f32; 3]>,
    /// The 8 m Sentinel-2 units (level 5) and the Survey units (level 4) holding a pixel it tones.
    s2_units: BTreeSet<Key>,
    survey_units: BTreeSet<Key>,
}

const BORDER_CELL_M: f64 = 100.0;
const BORDER_FEATHER_M: f32 = 10_000.0;
/// On the photo's side: Sentinel-2 (under the photo's soft edge in the 2 m nodes) toned fully to this far in, none
/// from the second value (m).
const BORDER_INSIDE_M: [f32; 2] = [200.0, 400.0];
const BORDER_BLOCK_M: f64 = 16_400.0;
const BORDER_SAMPLE_M: f32 = 4_000.0;
/// The fewest photo cells near the edge a block's tone is fitted from.
const BORDER_MIN_CELLS: usize = 200;
/// The local match (2026-11-25, the user: "the shim between tiles can look better"): the photo's cells this far in
/// from its edge (m) give its own colour there, over the blocks' tone of Sentinel-2 (a darker sheet beside a lighter
/// one left a step at the edge); their log ratios averaged by three box blurs of LOCAL_BLUR cells (σ ≈ 850 m) and
/// applied out of the photo fully at its edge, none from LOCAL_REACH_M; each band within × LOCAL_MAX.
const LOCAL_SAMPLE_M: [f32; 2] = [150.0, 800.0];
const LOCAL_BLUR: usize = 8;
const LOCAL_REACH_M: f32 = 2_000.0;
const LOCAL_MAX: f32 = 1.6;

/// Three box blurs of radius `r` (rows, then columns) over a w × h grid of `N` values: about a Gaussian, σ ≈ r.
fn box_blur3<const N: usize>(v: &mut [[f32; N]], w: usize, h: usize, r: usize) {
    let mut tmp = vec![[0f32; N]; v.len()];
    let pass =
        |src: &[[f32; N]], dst: &mut [[f32; N]], len: usize, lines: usize, at: &dyn Fn(usize, usize) -> usize| {
            for l in 0..lines {
                let mut sum = [0f32; N];
                for k in 0..r.min(len) {
                    (0..N).for_each(|j| sum[j] += src[at(l, k)][j]);
                }
                for k in 0..len {
                    if k + r < len {
                        (0..N).for_each(|j| sum[j] += src[at(l, k + r)][j]);
                    }
                    if k > r {
                        (0..N).for_each(|j| sum[j] -= src[at(l, k - r - 1)][j]);
                    }
                    dst[at(l, k)] = sum.map(|s| s / (2 * r + 1) as f32);
                }
            }
        };
    for _ in 0..3 {
        pass(v, &mut tmp, w, h, &|y, x| y * w + x);
        pass(&tmp, v, h, w, &|x, y| y * w + x);
    }
}

fn smoothstep(a: f32, b: f32, x: f32) -> f32 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Two passes of a chamfer distance (1 and √2 per step): per cell of a w × h grid, cells to the nearest `seed`,
/// within 8 % of the straight distance; 1e7 where there is none.
fn chamfer(seed: &[bool], w: usize, h: usize) -> Vec<f32> {
    let mut d: Vec<f32> = seed.iter().map(|&s| if s { 0.0 } else { 1e7 }).collect();
    let r2 = std::f32::consts::SQRT_2;
    for y in 0..h {
        for x in 0..w {
            let i = y * w + x;
            let mut v = d[i];
            if x > 0 {
                v = v.min(d[i - 1] + 1.0);
            }
            if y > 0 {
                v = v.min(d[i - w] + 1.0);
                if x > 0 {
                    v = v.min(d[i - w - 1] + r2);
                }
                if x + 1 < w {
                    v = v.min(d[i - w + 1] + r2);
                }
            }
            d[i] = v;
        }
    }
    for y in (0..h).rev() {
        for x in (0..w).rev() {
            let i = y * w + x;
            let mut v = d[i];
            if x + 1 < w {
                v = v.min(d[i + 1] + 1.0);
            }
            if y + 1 < h {
                v = v.min(d[i + w] + 1.0);
                if x + 1 < w {
                    v = v.min(d[i + w + 1] + r2);
                }
                if x > 0 {
                    v = v.min(d[i + w - 1] + r2);
                }
            }
            d[i] = v;
        }
    }
    d
}

impl BorderTone {
    /// From the Survey's VRT (`levels` its sheets' levels) and Sentinel-2's (the 10 m tiles), both warped to the
    /// cells over `area` (UTM); the 8 m units listed only where `has` (their tiles on disk).
    fn new(
        (sv_vrt, levels): (&str, &[SheetLevels]),
        s2_vrt: &str,
        f: &Frame,
        area: [f64; 4],
        work: &Path,
        bases: &[Vec<[f64; 2]>],
        has: &dyn Fn(Key) -> bool,
    ) -> Result<Self> {
        let c = BORDER_CELL_M;
        let (w, h) = (((area[2] - area[0]) / c).ceil() as usize, ((area[3] - area[1]) / c).ceil() as usize);
        let r = [area[0], area[3] - h as f64 * c, area[0] + w as f64 * c, area[3]];
        let extra = ["-r", "average", "-srcnodata", "255 255 255", "-wo", "UNIFIED_SRC_NODATA=YES", "-dstalpha"];
        let photo = warp(sv_vrt, r, [w, h], &extra, &work.join("border_photo.bin"))?;
        if photo.bands != 4 || photo.raw.len() != w * h * 4 {
            bail!("border tone: want RGBA bytes from the Survey, got {} bands", photo.bands);
        }
        let extra = ["-r", "average", "-srcnodata", "0", "-dstnodata", "0", "-wo", "UNIFIED_SRC_NODATA=YES"];
        let s2 = warp(s2_vrt, r, [w, h], &extra, &work.join("border_s2.bin"))?;
        if s2.bands != 4 || s2.dtype != "12" || s2.raw.len() != w * h * 8 {
            bail!("border tone: want 4 bands of u16 from Sentinel-2, got {} / type {}", s2.bands, s2.dtype);
        }
        let px = s2.raw.as_chunks::<2>().0;
        let sat: Vec<Option<[f32; 3]>> = (0..w * h)
            .map(|i| {
                let b = |k: usize| f32::from(u16::from_le_bytes(px[i * 4 + k]));
                let empty = (0..3).all(|k| px[i * 4 + k] == [0, 0]);
                (!empty).then(|| imagery::tone([b(0), b(1), b(2)]))
            })
            .collect();
        let land = |i: usize| sat[i].is_some_and(|s| !imagery::is_photo_water(s));
        let covered: Vec<bool> = (0..w * h)
            .map(|i| {
                let p = &photo.raw[i * 4..i * 4 + 4];
                p[3] >= 250 && !p[..3].iter().all(|&v| v >= NEAR_WHITE)
            })
            .collect();
        let uncovered_land: Vec<bool> = (0..w * h).map(|i| !covered[i] && land(i)).collect();
        let (out, inside) = (chamfer(&covered, w, h), chamfer(&uncovered_land, w, h));
        let cf = c as f32;
        let dist: Vec<f32> = (0..w * h).map(|i| if covered[i] { -inside[i] * cf } else { out[i] * cf }).collect();
        let centre = |i: usize| [r[0] + ((i % w) as f64 + 0.5) * c, r[3] - ((i / w) as f64 + 0.5) * c];
        // The photo's colour of cell i with its sheets' levels.
        let photo_at = |i: usize| {
            let g = centre(i);
            let g = utm36n_geo(g[0], g[1]);
            let itm = crate::itm::from_wgs84(g[0], g[1]);
            let rgb = [0, 1, 2].map(|k| f32::from(photo.raw[i * 4 + k]));
            photo_px(levels, itm, rgb)
        };
        // The blocks' tones from the photo's cells near its edge.
        let b = BORDER_BLOCK_M;
        let (bw, bh) = (((r[2] - r[0]) / b).ceil() as usize, ((r[3] - r[1]) / b).ceil() as usize);
        let cells = (b / c) as isize;
        let mut tones = Vec::with_capacity(bw * bh);
        for bj in 0..bh as isize {
            for bi in 0..bw as isize {
                let (mut ph, mut sa) = (Vec::new(), Vec::new());
                for y in (bj * cells - cells / 2).max(0)..((bj + 1) * cells + cells / 2).min(h as isize) {
                    for x in (bi * cells - cells / 2).max(0)..((bi + 1) * cells + cells / 2).min(w as isize) {
                        let i = y as usize * w + x as usize;
                        let Some(s) = sat[i] else { continue };
                        if !covered[i] || dist[i] < -BORDER_SAMPLE_M || !land(i) {
                            continue;
                        }
                        ph.push(photo_at(i));
                        sa.push(s);
                    }
                }
                let t = (ph.len() >= BORDER_MIN_CELLS).then(|| BaseTone::fit(r, &ph, &sa, &sa)).flatten();
                // No knee: the neighbours' bright ground (Sinai's dunes) keeps its contrast.
                tones.push(t.map(|t| BaseTone { knee: 255.0, ..t }));
            }
        }
        let mut bt = Self {
            rect: r,
            w,
            h,
            dist,
            bw,
            bh,
            tones,
            local: Vec::new(),
            s2_units: BTreeSet::new(),
            survey_units: BTreeSet::new(),
        };
        // The local match (LOCAL_SAMPLE_M): per band the log ratio of the photo to the blocks' tone of Sentinel-2 on
        // the photo's cells near its edge, averaged around (the sum of ratios and of cells blurred alike).
        let mut acc = vec![[0f32; 4]; w * h];
        let near = -LOCAL_SAMPLE_M[1]..=-LOCAL_SAMPLE_M[0];
        for (i, a) in acc.iter_mut().enumerate() {
            let Some(s) = sat[i].filter(|_| covered[i] && land(i) && near.contains(&bt.dist[i])) else { continue };
            let q = centre(i);
            let Some(t) = bt.blocks(q[0], q[1], s) else { continue };
            let p = photo_at(i);
            let l = [0, 1, 2].map(|k| ((p[k] + 4.0) / (t[k] + 4.0)).ln());
            *a = [l[0], l[1], l[2], 1.0];
        }
        box_blur3(&mut acc, w, h, LOCAL_BLUR);
        let lim = LOCAL_MAX.ln();
        bt.local = acc
            .iter()
            .map(|a| if a[3] > 1e-4 { [0, 1, 2].map(|k| (a[k] / a[3]).clamp(-lim, lim)) } else { [0.0; 3] })
            .collect();
        drop(acc);
        for i in (0..w * h).filter(|&i| land(i)) {
            let q = centre(i);
            if bt.weight(q[0], q[1]) <= 0.0 {
                continue;
            }
            for (level, set) in [(5, &mut bt.s2_units), (4, &mut bt.survey_units)] {
                let s = span(level);
                let (x, y) = ((q[0] - f.e0) / s, (f.n1 - q[1]) / s);
                if x >= 0.0 && y >= 0.0 && x < f64::from(f.w) / s && y < f64::from(f.h) / s {
                    set.insert((level, x as u32, y as u32));
                }
            }
        }
        // A unit whose 10 m tiles are not all on disk (`has`) stays as it is: Sentinel-2's own colour.
        bt.s2_units.retain(|&k| has(k));
        // A base whose 8 m units the tone touches gets all of them redone: its tone (BaseTone::new) reads Sentinel-2
        // from the level-3 nodes within TONE_REACH_M, which hold the photo after a run (review, 2026-11-16). When one
        // of them cannot be redone, none near the base is.
        for b in bases {
            let bb = crate::bbox(b.iter());
            let m = TONE_REACH_M + BASE_COVER_M + BASE_FEATHER_M;
            let near = f.nodes_in(5, [bb[0] - m, bb[1] - m, bb[2] + m, bb[3] + m]);
            if near.iter().any(|k| bt.s2_units.contains(k)) {
                if near.iter().all(|&k| has(k)) {
                    bt.s2_units.extend(near);
                } else {
                    near.iter().for_each(|k| _ = bt.s2_units.remove(k));
                }
            }
        }
        // A Survey unit is redone only over its 8 m unit's new Sentinel-2.
        let s2 = &bt.s2_units;
        bt.survey_units.retain(|k| s2.contains(&(5, k.1 >> 1, k.2 >> 1)));
        Ok(bt)
    }

    /// How much of the tone UTM (e, n) takes: the distance to the photo's edge bilinear between the cells' centres.
    fn weight(&self, e: f64, n: f64) -> f32 {
        let d = self.cell(e, n, |i| [self.dist[i]; 3])[0];
        if d >= 0.0 {
            1.0 - smoothstep(0.0, BORDER_FEATHER_M, d)
        } else {
            1.0 - smoothstep(BORDER_INSIDE_M[0], BORDER_INSIDE_M[1], -d)
        }
    }

    /// Sentinel-2's colour `v` at UTM (e, n): toned by its weight, the blocks' tones blended between their centres,
    /// then the local match (LOCAL_SAMPLE_M); outside the cells' rect, on water or far from the photo as it is.
    fn tone(&self, e: f64, n: f64, v: [f32; 3]) -> [f32; 3] {
        let r = self.rect;
        if e < r[0] || e > r[2] || n < r[1] || n > r[3] || imagery::is_photo_water(v) {
            return v;
        }
        let k = self.weight(e, n);
        if k <= 0.0 {
            return v;
        }
        let Some(t) = self.blocks(e, n, v) else { return v };
        let (l, d) = (self.cell(e, n, |i| self.local[i]), self.cell(e, n, |i| [self.dist[i]; 3])[0]);
        let kl = if d >= 0.0 { 1.0 - smoothstep(0.0, LOCAL_REACH_M, d) } else { 1.0 };
        [0, 1, 2].map(|j| v[j] + ((t[j] * (l[j] * kl).exp()).clamp(0.0, 255.0) - v[j]) * k)
    }

    /// The cells' values at UTM (e, n), bilinear between the cells' centres (`at` cell i's).
    fn cell(&self, e: f64, n: f64, at: impl Fn(usize) -> [f32; 3]) -> [f32; 3] {
        let c = BORDER_CELL_M;
        let x = ((e - self.rect[0]) / c - 0.5).clamp(0.0, (self.w - 1) as f64);
        let y = ((self.rect[3] - n) / c - 0.5).clamp(0.0, (self.h - 1) as f64);
        let (x0, y0) = (x as usize, y as usize);
        let (x1, y1) = ((x0 + 1).min(self.w - 1), (y0 + 1).min(self.h - 1));
        let (fx, fy) = ((x - x0 as f64) as f32, (y - y0 as f64) as f32);
        let v = |x: usize, y: usize| at(y * self.w + x);
        let (a, b, cc, d) = (v(x0, y0), v(x1, y0), v(x0, y1), v(x1, y1));
        [0, 1, 2].map(|j| {
            let top = a[j] + (b[j] - a[j]) * fx;
            top + (cc[j] + (d[j] - cc[j]) * fx - top) * fy
        })
    }

    /// Sentinel-2's colour `v` at UTM (e, n) by the blocks' tones blended between their centres; None where no block
    /// near is fitted.
    fn blocks(&self, e: f64, n: f64, v: [f32; 3]) -> Option<[f32; 3]> {
        let r = self.rect;
        let b = BORDER_BLOCK_M;
        let x = ((e - r[0]) / b - 0.5).clamp(0.0, (self.bw - 1) as f64);
        let y = ((r[3] - n) / b - 0.5).clamp(0.0, (self.bh - 1) as f64);
        let (x0, y0) = (x as usize, y as usize);
        let (fx, fy) = ((x - x0 as f64) as f32, (y - y0 as f64) as f32);
        let (mut acc, mut sum) = ([0f32; 3], 0f32);
        for (bx, by, wt) in [
            (x0, y0, (1.0 - fx) * (1.0 - fy)),
            (x0 + 1, y0, fx * (1.0 - fy)),
            (x0, y0 + 1, (1.0 - fx) * fy),
            (x0 + 1, y0 + 1, fx * fy),
        ] {
            let Some(t) = self.tones.get(by.min(self.bh - 1) * self.bw + bx.min(self.bw - 1)).copied().flatten() else {
                continue;
            };
            if wt <= 0.0 {
                continue;
            }
            let c = t.apply(v);
            for (a, cj) in acc.iter_mut().zip(c) {
                *a += wt * cj;
            }
            sum += wt;
        }
        (sum > 0.0).then(|| acc.map(|a| a / sum))
    }
}

/// The units the border tone touches (`BorderTone`'s s2_units and survey_units), kept in the work folder between runs:
/// a run with every Sentinel-2 unit done partitions its Survey units from it. None: not made yet.
fn border_units(work: &Path) -> Option<[BTreeSet<Key>; 2]> {
    let v: serde_json::Value = serde_json::from_slice(&std::fs::read(border_path(work)).ok()?).ok()?;
    let set = |k: &str, level: u32| -> BTreeSet<Key> {
        v[k].as_array()
            .into_iter()
            .flatten()
            .filter_map(|ij| Some((level, ij[0].as_u64()? as u32, ij[1].as_u64()? as u32)))
            .collect()
    };
    Some([set("s2", 5), set("survey", 4)])
}

fn border_path(work: &Path) -> PathBuf {
    work.join(format!("border_{BORDER_FILL}.json"))
}

fn write_border_units(work: &Path, s2: &BTreeSet<Key>, survey: &BTreeSet<Key>) -> Result<()> {
    let list = |s: &BTreeSet<Key>| s.iter().map(|k| [k.1, k.2]).collect::<Vec<_>>();
    std::fs::write(border_path(work), serde_json::json!({ "s2": list(s2), "survey": list(survey) }).to_string())?;
    Ok(())
}

/// The published Survey photo paints the military bases over with made-up ground: Sentinel-2 shows instead inside
/// the bases' outlines and BASE_COVER_M beyond them, the Survey fading back in over the next BASE_FEATHER_M.
const BASE_COVER_M: f64 = 160.0;
const BASE_FEATHER_M: f64 = 160.0;
/// The mask's cell: the fade spans 16 of them, and a 2 m raster per unit would cost 2 × 268 MB per worker.
const BASE_CELL_M: f64 = 10.0;
/// A Survey pixel this bright in every band near the coast, or joined to the sheets' no-data through such pixels, is
/// the sheets' no-data (white, JPEG-noisy), not ground (inferred from the sheets' borders off Tel Aviv: 240–255; on
/// the Egyptian border west of Ramon the fill took the levels' white, 235 grey-white, before 2026-11-24).
const NEAR_WHITE: u8 = 235;

/// A near-white patch (NEAR_WHITE in every band) this large is the sheets' fill, joined to their no-data or not: 0.1
/// km² at 2 m. Ground that white comes in patches of 0.004 km² at most (the salt pans at Sedom, the greenhouses in the
/// Arava, measured 2026-11-25); west of Ramon a patch of fill 37 km² (249 grey, alpha 255) lies in a unit whose
/// no-data is in the next unit.
const FILL_MIN_PX: usize = 25_000;
/// How far (pixels) the fill reaches past its near-white pixels (`white_fill`).
const FILL_EDGE_PX: usize = 2;
/// The photo fades out over this far (m) toward the sheets' fill and no-data (`white_fill`; not toward the sea), onto
/// Sentinel-2 toned to it there (BorderTone's local match): its edge was a line (2026-11-25, the user: "the shim
/// between tiles can look better"). The Survey unit's warp reaches this far past the unit, so the fade sees the fill
/// across a unit's border.
const FILL_FEATHER_M: f64 = 200.0;
/// The fade's distance is measured on cells of this many pixels (8 m at 2 m; a 2 m distance field would take 280 MB
/// per worker).
const FEATHER_CELL: usize = 4;

/// Clears the patches (4-connected) of `m` (`w` wide) smaller than `min` cells.
fn large_only(m: &mut [bool], w: usize, min: usize) {
    let mut seen = vec![false; m.len()];
    for i in 0..m.len() {
        if !m[i] || seen[i] {
            continue;
        }
        seen[i] = true;
        let (mut stack, mut patch) = (vec![i], Vec::new());
        while let Some(j) = stack.pop() {
            patch.push(j);
            let (x, y) = (j % w, j / w);
            let near = [
                (x > 0).then(|| j - 1),
                (x + 1 < w).then(|| j + 1),
                (y > 0).then(|| j - w),
                (j + w < m.len()).then(|| j + w),
            ];
            for k in near.into_iter().flatten() {
                if m[k] && !seen[k] {
                    seen[k] = true;
                    stack.push(k);
                }
            }
        }
        if patch.len() < min {
            patch.into_iter().for_each(|j| m[j] = false);
        }
    }
}

/// Per pixel of an `n` × `n` raster (UTM `rect`, its margin included), 0 at the fill (`seed` per FEATHER_CELL cell) to
/// 1 from FILL_FEATHER_M: the distance between the cells' centres bilinear, smoothstep.
fn feather(seed: &[bool], n: usize, px: f64) -> impl Fn(usize, usize) -> f32 + use<> {
    let cw = n / FEATHER_CELL;
    let d = chamfer(seed, cw, cw);
    let cm = (FEATHER_CELL as f64 * px) as f32;
    move |x: usize, y: usize| {
        let at = |v: usize| ((v as f32 + 0.5) / FEATHER_CELL as f32 - 0.5).clamp(0.0, (cw - 1) as f32);
        let (fx, fy) = (at(x), at(y));
        let (x0, y0) = (fx as usize, fy as usize);
        let (x1, y1) = ((x0 + 1).min(cw - 1), (y0 + 1).min(cw - 1));
        let (tx, ty) = (fx - x0 as f32, fy - y0 as f32);
        let v = |x: usize, y: usize| d[y * cw + x].min(1e5);
        let top = v(x0, y0) + (v(x1, y0) - v(x0, y0)) * tx;
        let c = top + (v(x0, y1) + (v(x1, y1) - v(x0, y1)) * tx - top) * ty;
        smoothstep(0.0, FILL_FEATHER_M as f32, c * cm)
    }
}

/// The unit's near-white pixels (NEAR_WHITE in every band) joined, through near-white pixels, to one the warp left
/// without the photo (alpha below 255), to a pure white one (the sheets' fill: west of Ramon a whole unit of it came
/// through the warp with alpha 255, 2026-11-24), or to FILL_MIN_PX of them: the sheets' white fill with its JPEG noise.
/// White ground inside the photo (a roof, a salt pan) touches no fill and stays, but for a clipped pure-white roof.
/// `raw`: RGBA, `n` × `n`.
fn white_fill(raw: &[u8], n: usize) -> Vec<bool> {
    let white = |i: usize| raw[i * 4..i * 4 + 3].iter().all(|&c| c >= NEAR_WHITE);
    // Marks the near-white pixels joined to `stack`'s (marked already); the count marked, `stack`'s included.
    let flood = |mark: &mut [bool], mut stack: Vec<usize>| {
        let mut count = stack.len();
        while let Some(i) = stack.pop() {
            let (x, y) = (i % n, i / n);
            let near = [
                (x > 0).then(|| i - 1),
                (x + 1 < n).then(|| i + 1),
                (y > 0).then(|| i - n),
                (y + 1 < n).then(|| i + n),
            ];
            for j in near.into_iter().flatten() {
                if !mark[j] && white(j) {
                    mark[j] = true;
                    stack.push(j);
                    count += 1;
                }
            }
        }
        count
    };
    let mut fill = vec![false; n * n];
    let seeds: Vec<usize> = (0..n * n).filter(|&i| raw[i * 4 + 3] < 255 || raw[i * 4..i * 4 + 3] == [255; 3]).collect();
    for &i in &seeds {
        fill[i] = true;
    }
    flood(&mut fill, seeds);
    // The patches joined to no seed: each counted once, marked again in `fill` when large enough.
    let mut seen = fill.clone();
    for i in 0..n * n {
        if !seen[i] && white(i) {
            seen[i] = true;
            if flood(&mut seen, vec![i]) >= FILL_MIN_PX {
                fill[i] = true;
                flood(&mut fill, vec![i]);
            }
        }
    }
    drop(seen);
    // The fill's edge, FILL_EDGE_PX wide: the photo's pixels the warp blended with it, a grey-white seam along the
    // photo otherwise (west of Ramon the first pixel out 185 grey, the second 99, the photo 90; 2026-11-25).
    for _ in 0..FILL_EDGE_PX {
        let was = fill.clone();
        for i in (0..n * n).filter(|&i| !was[i]) {
            let (x, y) = (i % n, i / n);
            fill[i] = (x > 0 && was[i - 1])
                || (x + 1 < n && was[i + 1])
                || (y > 0 && was[i - n])
                || (y + 1 < n && was[i + n]);
        }
    }
    fill
}

/// Where Sentinel-2 replaces the Survey around the bases, on a BASE_CELL_M grid over a UTM rect and its margin.
struct BaseMask {
    e0: f64,
    n1: f64,
    w: usize,
    h: usize,
    data: Vec<f32>,
}

impl BaseMask {
    /// 1 inside the polygons (UTM) and up to BASE_COVER_M beyond them, 0 from BASE_COVER_M + BASE_FEATHER_M; None
    /// when no polygon comes that near the rect `r`.
    fn new(bases: &[Vec<[f64; 2]>], r: [f64; 4]) -> Option<Self> {
        let pad = BASE_COVER_M + BASE_FEATHER_M + 2.0 * BASE_CELL_M;
        let rp = [r[0] - pad, r[1] - pad, r[2] + pad, r[3] + pad];
        // A polygon is near when its bounding box meets the padded rect (an edge may cross it with no vertex near).
        let near: Vec<&Vec<[f64; 2]>> = bases
            .iter()
            .filter(|p| {
                let b = crate::bbox(p.iter());
                b[0] < rp[2] && rp[0] < b[2] && b[1] < rp[3] && rp[1] < b[3]
            })
            .collect();
        if near.is_empty() {
            return None;
        }
        let c = BASE_CELL_M;
        let (w, h) = (((rp[2] - rp[0]) / c).ceil() as usize, ((rp[3] - rp[1]) / c).ceil() as usize);
        let mut m = vec![0f32; w * h];
        // Even-odd scanlines at the cell centres.
        for y in 0..h {
            let northing = rp[3] - (y as f64 + 0.5) * c;
            let mut xs = Vec::new();
            for p in &near {
                for k in 0..p.len() {
                    let (a, b) = (p[k], p[(k + 1) % p.len()]);
                    if (a[1] > northing) != (b[1] > northing) {
                        xs.push(a[0] + (northing - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
                    }
                }
            }
            xs.sort_by(f64::total_cmp);
            for s in xs.as_chunks::<2>().0 {
                let x0 = (((s[0] - rp[0]) / c - 0.5).ceil().max(0.0) as usize).min(w);
                let x1 = (((s[1] - rp[0]) / c - 0.5).floor() as isize + 1).clamp(0, w as isize) as usize;
                m[y * w + x0..y * w + x1.max(x0)].fill(1.0);
            }
        }
        // Grown by the cover plus half the fade (a square max filter), then two box passes of a quarter of the fade:
        // 1 up to BASE_COVER_M past the outline, 0 from BASE_COVER_M + BASE_FEATHER_M.
        dilate(&mut m, w, h, ((BASE_COVER_M + BASE_FEATHER_M / 2.0) / c).round() as usize);
        imagery::blur(&mut m, w, h, (BASE_FEATHER_M / 4.0 / c).round().max(1.0) as i32);
        Some(Self { e0: rp[0], n1: rp[3], w, h, data: m })
    }

    /// The mask at UTM (e, n), bilinear between the cell centres.
    fn at(&self, e: f64, n: f64) -> f32 {
        let x = ((e - self.e0) / BASE_CELL_M - 0.5).clamp(0.0, (self.w - 1) as f64);
        let y = ((self.n1 - n) / BASE_CELL_M - 0.5).clamp(0.0, (self.h - 1) as f64);
        let (x0, y0) = (x as usize, y as usize);
        let (x1, y1) = ((x0 + 1).min(self.w - 1), (y0 + 1).min(self.h - 1));
        let (fx, fy) = ((x - x0 as f64) as f32, (y - y0 as f64) as f32);
        let v = |x: usize, y: usize| self.data[y * self.w + x];
        let top = v(x0, y0) + (v(x1, y0) - v(x0, y0)) * fx;
        top + (v(x0, y1) + (v(x1, y1) - v(x0, y1)) * fx - top) * fy
    }
}

/// The sea over a shore unit on its 8 m Sentinel-2 nodes' grid (level 3, written before the Survey): within the
/// coastline's reach its water side; beyond it the nodes' open water (`imagery::is_photo_water`) joined by its sides to
/// that. So the sea is Sentinel-2's from the beach to the open sea, and an inland pond keeps the photo.
struct ShoreSea {
    e0: f64,
    n1: f64,
    cell: f64,
    w: usize,
    sea: Vec<bool>,
}

impl ShoreSea {
    fn new(coast: &crate::sim_coast::Coast, f: &Frame, unit: Key, out: &Path) -> Result<Self> {
        let d = unit.0 - 3;
        let (m, rect) = (NODE_PIXELS as usize, f.utm(unit));
        let w = m << d;
        let cell = (rect[2] - rect[0]) / w as f64;
        let mut pass = vec![false; w * w];
        for sj in 0..1u32 << d {
            for si in 0..1u32 << d {
                let Ok(img) = image::open(colour_path(out, (3, (unit.1 << d) + si, (unit.2 << d) + sj))) else {
                    continue;
                };
                for (x, y, p) in img.to_rgb8().enumerate_pixels() {
                    let k = (sj as usize * m + y as usize) * w + si as usize * m + x as usize;
                    pass[k] = imagery::is_photo_water(p.0.map(f32::from));
                }
            }
        }
        let centre = |k: usize| [rect[0] + ((k % w) as f64 + 0.5) * cell, rect[3] - ((k / w) as f64 + 0.5) * cell];
        let mut seeds = Vec::new();
        for (k, v) in pass.iter_mut().enumerate() {
            match coast.sea(centre(k)) {
                Some(true) => {
                    *v = true;
                    seeds.push(k);
                }
                Some(false) => *v = false,
                None => {}
            }
        }
        Ok(Self { e0: rect[0], n1: rect[3], cell, w, sea: crate::sim_bases::flood(w, w, &pass, seeds) })
    }

    /// Whether UTM (e, n) is sea.
    fn at(&self, e: f64, n: f64) -> bool {
        let x = (((e - self.e0) / self.cell).max(0.0) as usize).min(self.w - 1);
        let y = (((self.n1 - n) / self.cell).max(0.0) as usize).min(self.w - 1);
        self.sea[y * self.w + x]
    }
}

/// A square max filter of radius `r` cells (rows, then columns).
fn dilate(m: &mut [f32], w: usize, h: usize, r: usize) {
    let src = m.to_vec();
    let mut tmp = vec![0f32; m.len()];
    for y in 0..h {
        for x in 0..w {
            let row = &src[y * w + x.saturating_sub(r)..y * w + (x + r + 1).min(w)];
            tmp[y * w + x] = row.iter().copied().fold(0.0, f32::max);
        }
    }
    for y in 0..h {
        for x in 0..w {
            m[y * w + x] = (y.saturating_sub(r)..(y + r + 1).min(h)).map(|k| tmp[k * w + x]).fold(0.0, f32::max);
        }
    }
}

/// The Survey of Israel sheets over one level-4 unit: 2 m warp, the sheets' levels (the original game's Survey layer's
/// own, `imagery::photo_levels`: the same pixel as its `mapi2015_modern`, docs/imagery.md §4), over the level-3
/// Sentinel-2 node where no sheet is and on the airbases; writes the level-1 nodes with any sheet pixel.
fn survey_unit(sv: &Survey, f: &Frame, unit: Key, itm: [[f64; 2]; 4], work: &Path, out: &Path) -> Result<()> {
    let d = unit.0 - 1;
    let n = (NODE_PIXELS << d) as usize;
    let rect = f.utm(unit);
    let px = (rect[2] - rect[0]) / n as f64;
    // The warp with a margin of FILL_FEATHER_M (whole FEATHER_CELLs): unit pixel i is raw pixel ri(i).
    let mg = ((FILL_FEATHER_M / px).ceil() as usize).next_multiple_of(FEATHER_CELL);
    let (nn, o) = (n + 2 * mg, mg as f64 * px);
    let ri = |i: usize| (i / n + mg) * nn + i % n + mg;
    let bin = work.join(format!("soi_{}_{}_{}.bin", unit.0, unit.1, unit.2));
    let extra = ["-r", "bilinear", "-srcnodata", "255 255 255", "-wo", "UNIFIED_SRC_NODATA=YES", "-dstalpha"];
    let e = warp(sv.vrt, [rect[0] - o, rect[1] - o, rect[2] + o, rect[3] + o], [nn, nn], &extra, &bin)?;
    if e.bands != 4 || e.dtype != "1" || e.raw.len() != nn * nn * 4 {
        bail!("Survey unit {unit:?}: want RGBA bytes, got {} / type {}", e.bands, e.dtype);
    }
    let bases = BaseMask::new(sv.bases, rect);
    // The Israeli TM position of unit pixel (u, v) (0..1): bilinear between the corners (NW, NE, SW, SE); the
    // grids differ by ≈ 1° of rotation and < 0.1 % of scale, so the levels' 4 km blend sees no error.
    let at = |u: f64, v: f64| -> [f64; 2] {
        let l = |a: usize| itm[0][a] + (itm[1][a] - itm[0][a]) * u;
        let r = |a: usize| itm[2][a] + (itm[3][a] - itm[2][a]) * u;
        [l(0) + (r(0) - l(0)) * v, l(1) + (r(1) - l(1)) * v]
    };
    let shore = if sv.coast.touches(rect) { Some(ShoreSea::new(sv.coast, f, unit, out)?) } else { None };
    let fill = white_fill(&e.raw, nn);
    // The fade toward the fill (FILL_FEATHER_M), its cells on the sea left out: the beach stays the photo's.
    let cw = nn / FEATHER_CELL;
    let cm = FEATHER_CELL as f64 * px;
    let mut seed: Vec<bool> = (0..cw * cw)
        .map(|c| {
            let (x, y) = (c % cw * FEATHER_CELL, c / cw * FEATHER_CELL);
            let any = (y..y + FEATHER_CELL).any(|y| fill[y * nn + x..y * nn + x + FEATHER_CELL].contains(&true));
            let p = [rect[0] - o + ((c % cw) as f64 + 0.5) * cm, rect[3] + o - ((c / cw) as f64 + 0.5) * cm];
            any && sv.coast.sea(p) != Some(true) && !shore.as_ref().is_some_and(|s| s.at(p[0], p[1]))
        })
        .collect();
    // Only toward a fill of FILL_MIN_PX or more: a clipped white roof's few pixels show Sentinel-2 untoned (deep in
    // the photo), and a fade toward them made tan discs 400 m wide (first build of "tone6", 2026-11-25).
    large_only(&mut seed, cw, FILL_MIN_PX / (FEATHER_CELL * FEATHER_CELL));
    let fade = feather(&seed, nn, px);
    drop(seed);
    let centre = |i: usize| [rect[0] + ((i % n) as f64 + 0.5) * px, rect[3] - ((i / n) as f64 + 0.5) * px];
    // The photo's weight and the base cover's (BaseMask) at unit pixel i.
    let weight = |i: usize| {
        let p = centre(i);
        let base = bases.as_ref().map_or(0.0, |b| b.at(p[0], p[1]));
        let j = ri(i);
        if fill[j] {
            return (0.0, base); // the sheets' white fill (white_fill)
        }
        let a = f32::from(e.raw[j * 4 + 3]) / 255.0 * (1.0 - base) * fade(i % n + mg, i / n + mg);
        // At the shore: none of the photo on the sea (the coastline's water side, beyond its reach Sentinel-2's water
        // joined to it), nor its near-white (the sheets' no-data with JPEG noise) beyond the coastline's reach.
        if let Some(sea) = shore.as_ref().filter(|_| a > 0.0) {
            match sv.coast.sea(p) {
                Some(true) => return (0.0, base),
                None if sea.at(p[0], p[1]) || e.raw[j * 4..j * 4 + 3].iter().all(|&c| c >= NEAR_WHITE) => {
                    return (0.0, base);
                }
                _ => {}
            }
        }
        (a, base)
    };
    let m = NODE_PIXELS as usize;
    for sj in 0..1u32 << d {
        for si in 0..1u32 << d {
            let k = (1, (unit.1 << d) + si, (unit.2 << d) + sj);
            let (ox, oy) = (si as usize * m, sj as usize * m);
            // A node written before with the photo is written again (as Sentinel-2 when none of the photo is left);
            // one on a base's cover is written with its toned Sentinel-2.
            if k.1 * 2048 >= f.w
                || k.2 * 2048 >= f.h
                || (!colour_path(out, k).exists()
                    && (0..m).all(|y| (0..m).all(|x| weight((oy + y) * n + ox + x) == (0.0, 0.0))))
            {
                continue;
            }
            let mut img = ancestor_crop(out, k, 3)?;
            for y in 0..m {
                for x in 0..m {
                    let i = (oy + y) * n + ox + x;
                    let (a, base) = weight(i);
                    if base > 0.0 {
                        let p = centre(i);
                        let q = img.get_pixel_mut(x as u32, y as u32);
                        if let Some(t) = sv.tones.iter().find_map(|t| t.tone(p[0], p[1], q.0.map(f32::from))) {
                            q.0 = t.map(|v| v.round() as u8);
                        }
                    }
                    if a == 0.0 {
                        continue;
                    }
                    let [ie, inn] = at((ox + x) as f64 / n as f64, (oy + y) as f64 / n as f64);
                    let j = ri(i);
                    let rgb = photo_px(&sv.levels, [ie, inn], [0, 1, 2].map(|c| f32::from(e.raw[j * 4 + c])));
                    let p = img.get_pixel_mut(x as u32, y as u32);
                    for (v, s) in p.0.iter_mut().zip(rgb) {
                        *v = (f32::from(*v) * (1.0 - a) + s * a).round() as u8;
                    }
                }
            }
            save(&img, &colour_path(out, k))?;
        }
    }
    Ok(())
}

/// Runs the units not marked done (`what` names them), logging the count and time.
fn units(
    what: &str,
    list: &[Key],
    work: &Path,
    threads: usize,
    pr: &dyn Progress,
    cancel: &AtomicBool,
    f: impl Fn(Key) -> Result<()> + Sync,
) -> Result<()> {
    let t0 = std::time::Instant::now();
    let todo: Vec<Key> = list.iter().copied().filter(|&k| !done(work, what, k).exists()).collect();
    log!(pr, "{what}: {} units, {} to do", list.len(), todo.len());
    let n = AtomicUsize::new(0);
    par(&todo, threads, cancel, |&k| {
        f(k).with_context(|| format!("{what} unit {k:?}"))?;
        std::fs::write(done(work, what, k), "")?;
        let d = n.fetch_add(1, Ordering::Relaxed) + 1;
        pr.fraction(d as f32 / todo.len() as f32);
        if d.is_multiple_of(10) || d == todo.len() {
            log!(pr, "  {what} {d}/{} ({})", todo.len(), crate::progress::duration(t0.elapsed()));
        }
        Ok(())
    })
}

/// GRADE_FILE's text: GRADE and a hash of the bases' furniture files (`data/furniture/*.json`, beside the airbases:
/// the shelters' pads are graded with the pavement), so a furniture change re-grades the height nodes only.
fn grade_text(r: &Run) -> String {
    let mut files: Vec<_> = std::fs::read_dir(r.airbases.with_file_name("furniture"))
        .map(|d| {
            d.filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.extension().is_some_and(|x| x == "json")).collect()
        })
        .unwrap_or_default();
    files.sort();
    let h = files
        .iter()
        .flat_map(|p| std::fs::read(p).unwrap_or_default())
        .fold(0xcbf29ce484222325u64, |h, b| (h ^ u64::from(b)).wrapping_mul(0x100000001b3));
    if files.is_empty() { GRADE.to_string() } else { format!("{GRADE}; furniture {h:016x}") }
}

/// What a finished run was built from (`meta.json` "built_from"): the box, the detail area, the sheet ZIPs (name and
/// size) and the airbases' layouts (name and a hash of the content: their outlines mask the Survey photo). A run whose
/// inputs are the same as the stamp's has nothing to do.
pub fn stamp(r: &Run) -> serde_json::Value {
    let mut zips: Vec<String> = std::fs::read_dir(&r.sheets)
        .map(|d| {
            d.filter_map(|e| e.ok())
                .filter(|e| e.path().extension().is_some_and(|x| x.eq_ignore_ascii_case("zip")))
                .map(|e| format!("{} {}", e.file_name().to_string_lossy(), e.metadata().map_or(0, |m| m.len())))
                .collect()
        })
        .unwrap_or_default();
    zips.sort();
    let mut bases: Vec<String> = std::fs::read_dir(&r.airbases)
        .map(|d| {
            d.filter_map(|e| e.ok())
                .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
                .map(|e| {
                    let h = std::fs::read(e.path())
                        .unwrap_or_default()
                        .iter()
                        .fold(0xcbf29ce484222325u64, |h, b| (h ^ u64::from(*b)).wrapping_mul(0x100000001b3));
                    format!("{} {h:016x}", e.file_name().to_string_lossy())
                })
                .collect()
        })
        .unwrap_or_default();
    bases.sort();
    // With the Survey, the coastline's extracts (the photo is cut to it).
    let osm = if zips.is_empty() {
        Vec::new()
    } else {
        crate::sim_coast::extracts_stamp(crate::sim_bases::theatre_geo(r.area))
    };
    // With the Survey, its rule at the shore: 2 = the sea beyond the coastline's reach is Sentinel-2's too. "sea": the
    // open sea's fill. "survey": the photo's colours, "levels" = by its sheets' levels alone, the original game's
    // (2026-11-13; before: matched to Sentinel-2, no key); "levels sheets1" with the sheets toned to their
    // neighbours (SHEET_TONE, 2026-11-25).
    let shore = if zips.is_empty() { 0 } else { 2 };
    let survey = if zips.is_empty() { String::new() } else { format!("levels {SHEET_TONE}") };
    // "base_fill": the bases' Sentinel-2 toned to the photo around them (BASE_FILL, 2026-11-14; before: no key).
    let base_fill = if zips.is_empty() { "" } else { BASE_FILL };
    // "border_fill": the neighbours' Sentinel-2 toned to the photo along its edge (BORDER_FILL, 2026-11-15).
    let border_fill = if zips.is_empty() { "" } else { BORDER_FILL };
    let mut v = serde_json::json!({ "box": r.area, "detail": r.detail, "survey_zips": zips, "airbases": bases,
        "osm": osm, "shore": shore, "sea": SEA, "survey": survey, "base_fill": base_fill, "border_fill": border_fill });
    // "s2_begun" (2026-11-24): a 10 m tile under the 8 m nodes begun and not finished (`sentinel` finishes it). Only
    // while there is one; `terrain` leaves it out of the stored stamp, so the run after the fetch is up to date.
    if !zips.is_empty() && s2_begun(r) {
        v["s2_begun"] = true.into();
    }
    v
}

/// With the Survey sheets, a 10 m tile under the 8 m nodes whose download began and stopped short (`tiles_begun`):
/// the next run finishes it (`sentinel`). Setup's stamp of the terrain does not hold while there is one (iaf-setup
/// `Stamp::pending`).
pub fn s2_pending(r: &Run) -> bool {
    has_zips(&r.sheets) && s2_begun(r)
}

fn s2_begun(r: &Run) -> bool {
    let Ok(f) = Frame::new(r.area) else { return false };
    geo_bbox(fine_area(&f, r.detail)).is_ok_and(|g| {
        let over = |b: [f64; 4]| b[0] < g[2] && g[0] < b[2] && b[1] < g[3] && g[1] < b[3];
        tiles_begun(&r.s2_cache).iter().any(|n| tile_box(n).is_some_and(over))
    })
}

/// `meta.json` (the shape `terrain::theatre` writes) with the georeference, the sources and the run's stamp.
/// A theatre's `meta.json` as the sim's steps read it (`iaf-sim airbases`, `iaf-sim scenery`): its frame
/// (`iaf_avionics::frame`), its rect in world metres [E0, N0, E1, N1], its colour nodes per level and the file's bytes.
pub struct Meta {
    pub frame: iaf_avionics::frame::Frame,
    pub rect: [f64; 4],
    pub nodes: std::collections::HashMap<u32, BTreeSet<(u32, u32)>>,
    pub crs: String,
    pub bytes: Vec<u8>,
}

impl Meta {
    pub fn load(dir: &Path) -> Result<Self> {
        let p = dir.join("meta.json");
        let bytes = std::fs::read(&p).with_context(|| format!("{}: no theatre (iaf-sim terrain)", p.display()))?;
        let m: serde_json::Value = serde_json::from_slice(&bytes).with_context(|| format!("{}", p.display()))?;
        let f = |k: &str| m[k].as_f64().with_context(|| format!("{}: no {k}", p.display()));
        let frame = iaf_avionics::frame::Frame {
            x_shift: f("x_shift")?,
            y_shift: f("y_shift")?,
            m_per_unit: f("units_to_metres")?,
            node_pixels: f("node_pixels")?,
        };
        let t: Vec<f64> = (0..4).filter_map(|k| m["theatre"][k].as_f64()).collect();
        if t.len() != 4 || t[2] <= t[0] || t[3] <= t[1] {
            bail!("{}: no theatre size", p.display());
        }
        let (a, b) = (frame.engine(t[0], t[3]), frame.engine(t[2], t[1]));
        let nodes = m["nodes"]
            .as_object()
            .into_iter()
            .flatten()
            .filter_map(|(l, v)| {
                let set = v
                    .as_array()?
                    .iter()
                    .filter_map(|ij| Some((ij[0].as_u64()? as u32, ij[1].as_u64()? as u32)))
                    .collect();
                Some((l.parse().ok()?, set))
            })
            .collect();
        let crs = m["crs"].as_str().unwrap_or("").to_string();
        Ok(Meta { frame, rect: [a[0], a[1], b[0], b[1]], nodes, crs, bytes })
    }
}

fn write_meta(f: &Frame, out: &Path, built_from: serde_json::Value) -> Result<()> {
    let mut nodes = serde_json::Map::new();
    for l in 0..=ROOT_LEVEL {
        let v: Vec<[u32; 2]> = written(out, l)?.into_iter().map(|k| [k.1, k.2]).collect();
        nodes.insert(l.to_string(), serde_json::json!(v));
    }
    let meta = serde_json::json!({
        "theatre": [0, 0, f.w, f.h],
        "node_pixels": NODE_PIXELS,
        "height_level": HEIGHT_LEVEL,
        "height_levels": (HEIGHT_LEVEL..=ROOT_LEVEL).collect::<Vec<_>>(),
        "root_level": ROOT_LEVEL,
        "nodes": nodes,
        // World X = tx + x_shift = UTM easting; Y = y_shift − ty = UTM northing; heights in metres above the geoid.
        "units_to_metres": 1.0,
        "x_shift": f.e0,
        "y_shift": f.n1,
        "sea_level_raw": SEA_LEVEL_RAW,
        "height_scale": HEIGHT_SCALE,
        "crs": "EPSG:32636",
        "attribution": ATTRIBUTION,
        "notice": DEM_LIABILITY,
        "built_from": built_from,
    });
    std::fs::write(out.join("meta.json"), serde_json::to_string(&meta)?)?;
    Ok(())
}

/// The sheets that reach within `pad` metres of any of the Israeli TM boxes, in their order.
fn near(sheets: &[Sheet], boxes: &[[f64; 4]], pad: f64) -> Vec<Sheet> {
    let touches = |s: &Sheet, b: &[f64; 4]| {
        s.bbox[0] < b[2] + pad && b[0] - pad < s.bbox[2] && s.bbox[1] < b[3] + pad && b[1] - pad < s.bbox[3]
    };
    sheets.iter().filter(|s| boxes.iter().any(|b| touches(s, b))).cloned().collect()
}

/// The VRT over the given sheets, `<work>/soi.vrt`. Building it opens every sheet inside its ZIP, so it is kept
/// with a stamp (`soi.vrt.stamp`) and reused while the stamp is the same. With no sheets there is no VRT (no unit
/// reads it).
fn soi_vrt(sheets: &[Sheet], dir: &Path, work: &Path, pr: &dyn Progress) -> Result<PathBuf> {
    let (vrt, stamp_file) = (work.join("soi.vrt"), work.join("soi.vrt.stamp"));
    if sheets.is_empty() {
        return Ok(vrt);
    }
    let mut a = vec!["-q", "-overwrite", "-a_srs", "EPSG:2039", "-allow_projection_difference"];
    a.extend(["-b", "1", "-b", "2", "-b", "3", "-srcnodata", "255 255 255", utf8(&vrt)?]);
    let stamp = vrt_stamp(&a, sheets, dir)?;
    if vrt.is_file() && std::fs::read_to_string(&stamp_file).is_ok_and(|s| s == stamp) {
        log!(pr, "survey: the VRT over {} sheets reused", sheets.len());
        return Ok(vrt);
    }
    let _ = std::fs::remove_file(&stamp_file);
    a.extend(sheets.iter().map(|s| s.gdal.as_str()));
    gdal("gdalbuildvrt", &a)?;
    std::fs::write(&stamp_file, stamp)?;
    Ok(vrt)
}

/// `soi_vrt`'s stamp: gdalbuildvrt's options, then per sheet its GDAL path (`/vsizip/<absolute ZIP>/<tif>`) and its
/// ZIP's size and modification time (seconds); the ZIP is `dir/<the sheet name's first part>`.
fn vrt_stamp(opts: &[&str], sheets: &[Sheet], dir: &Path) -> Result<String> {
    let mut s = opts.join(" ") + "\n";
    for sh in sheets {
        let zip = dir.join(sh.name.split('/').next().unwrap_or_default());
        let m = std::fs::metadata(&zip).with_context(|| format!("{}", zip.display()))?;
        let t = m.modified()?.duration_since(std::time::UNIX_EPOCH)?.as_secs();
        s += &format!("{}\t{}\t{t}\n", sh.gdal, m.len());
    }
    Ok(s)
}

/// The cells over which the sheets are compared with their neighbours (`sheet_tone`), metres.
const SHEET_CELL_M: f64 = 100.0;
/// A sheet's strip along a neighbour: its cells within this many cells of the neighbour's.
const SHEET_STRIP: usize = 15;
/// The least land cells on each side of a border for it to count.
const SHEET_MIN_CELLS: usize = 100;
/// How much the gains are held to 1 (`balance`), against the borders' weight.
const SHEET_HOLD: f64 = 0.02;
/// A border whose difference stays more than this (log) after the fit counts less (real ground changing there).
const SHEET_ROBUST: f64 = 0.1;
/// The tone's rule, in its work file's stamp (`sheet_tone.stamp`), the stamp's "survey" and the 8 m and Survey units'
/// marks: a new rule makes them again. "sheets1" (2026-11-25): the first.
const SHEET_TONE: &str = "sheets1";

/// Per sheet a log gain per band that brings it to its neighbours: the Survey's sheets were flown on different days,
/// and their levels (`imagery::sheet_levels`) leave them darker or lighter than the ground around, rectangles 10 to
/// 25 km wide from the air (a dark block 20 by 40 km south-west of Ramon, 2026-11-25). On 100 m cells (ITM) with each
/// sheet's own levels, the land along every border between two sheets: each sheet's strip (SHEET_STRIP) against the
/// other's, the difference of their medians per band (`border_diffs`). The gains are the least-squares fit that
/// cancels those differences, held to 1 on average (`balance`). Kept in `sheet_tone.tsv` while the VRT's stamp is
/// the same (the 100 m warp reads every sheet whole: about 10 minutes).
fn sheet_tone(sheets: &[Sheet], vrt: &Path, work: &Path, pr: &dyn Progress) -> Result<Vec<[f32; 3]>> {
    let (file, stamp_file) = (work.join("sheet_tone.tsv"), work.join("sheet_tone.stamp"));
    // The rule, the VRT's stamp (the sheets' files) and each sheet's levels (the cells are levelled by them).
    let mut stamp =
        format!("{SHEET_TONE}\n{}", std::fs::read_to_string(work.join("soi.vrt.stamp")).unwrap_or_default());
    for s in sheets {
        stamp += &format!("{}\t{:?}\n", s.name, s.levels);
    }
    if std::fs::read_to_string(&stamp_file).is_ok_and(|s| s == stamp) {
        let text = std::fs::read_to_string(&file)?;
        let kept: BTreeMap<&str, [f32; 3]> = text
            .lines()
            .filter_map(|l| {
                let (n, g) = l.split_once('\t')?;
                let g: Vec<f32> = g.split(' ').filter_map(|v| v.parse().ok()).collect();
                Some((n, g.try_into().ok()?))
            })
            .collect();
        if let Some(g) = sheets.iter().map(|s| kept.get(s.name.as_str()).copied()).collect::<Option<Vec<_>>>() {
            log!(pr, "survey: the sheets' tone reused");
            return Ok(g);
        }
    }
    let _ = std::fs::remove_file(&stamp_file);
    let t0 = std::time::Instant::now();
    let c = SHEET_CELL_M;
    let b = sheets.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |a, s| {
        [a[0].min(s.bbox[0]), a[1].min(s.bbox[1]), a[2].max(s.bbox[2]), a[3].max(s.bbox[3])]
    });
    let (w, h) = (((b[2] - b[0]) / c).ceil() as usize, ((b[3] - b[1]) / c).ceil() as usize);
    let r = [b[0], b[3] - h as f64 * c, b[0] + w as f64 * c, b[3]];
    let extra = ["-r", "average", "-srcnodata", "255 255 255", "-wo", "UNIFIED_SRC_NODATA=YES", "-dstalpha"];
    let e = warp_in("EPSG:2039", utf8(vrt)?, r, [w, h], &extra, &work.join("sheet_tone.bin"))?;
    if e.bands != 4 || e.raw.len() != w * h * 4 {
        bail!("sheet tone: want RGBA bytes from the Survey, got {} bands", e.bands);
    }
    // Each land cell's sheet (the last whose extent holds its centre: the VRT's order, the later sheet on top) and its
    // colour by that sheet's levels alone, as log.
    let (mut own, mut lg) = (vec![None; w * h], vec![[0f32; 3]; w * h]);
    for (i, p) in e.raw.as_chunks::<4>().0.iter().enumerate() {
        if p[3] < 250 || p[..3].iter().all(|&v| v >= NEAR_WHITE) {
            continue;
        }
        let (x, y) = (r[0] + ((i % w) as f64 + 0.5) * c, r[3] - ((i / w) as f64 + 0.5) * c);
        let Some(k) =
            sheets.iter().rposition(|s| (s.bbox[0]..s.bbox[2]).contains(&x) && (s.bbox[1]..s.bbox[3]).contains(&y))
        else {
            continue;
        };
        let v = imagery::photo_levels([0, 1, 2].map(|j| f32::from(p[j])), sheets[k].levels);
        if !imagery::is_photo_water(v) {
            own[i] = Some(k);
            lg[i] = v.map(|v| (v.min(255.0) + 4.0).ln());
        }
    }
    let borders = border_diffs(&own, &lg, w, h);
    let gain = balance(sheets.len(), &borders);
    let mut text = String::new();
    for (s, g) in sheets.iter().zip(&gain) {
        text += &format!("{}\t{} {} {}\n", s.name, g[0], g[1], g[2]);
    }
    std::fs::write(&file, text)?;
    std::fs::write(&stamp_file, stamp)?;
    let most = gain.iter().map(|g| ((g[0] + g[1] + g[2]) / 3.0).abs()).fold(0f32, f32::max).exp();
    log!(
        pr,
        "survey: the sheets toned to their neighbours over {} borders, up to × {most:.2} ({})",
        borders.len(),
        crate::progress::duration(t0.elapsed())
    );
    Ok(gain)
}

/// One border between two sheets (`border_diffs`): the sheets, sheet a's strip's median minus sheet b's per band
/// (log), the fewer cells of the two strips.
type Border = (usize, usize, [f32; 3], usize);

/// The borders between the sheets (`own` each cell's, `lg` its log colour): per pair, each sheet's cells whose cell
/// SHEET_STRIP away across or along the grid is the other's, with SHEET_MIN_CELLS on both sides.
fn border_diffs(own: &[Option<usize>], lg: &[[f32; 3]], w: usize, h: usize) -> Vec<Border> {
    let mut strips: BTreeMap<(usize, usize), Vec<[f32; 3]>> = BTreeMap::new();
    let d = SHEET_STRIP as isize;
    for (i, a) in own.iter().enumerate() {
        let Some(a) = *a else { continue };
        let (x, y) = ((i % w) as isize, (i / w) as isize);
        for (dx, dy) in [(d, 0), (-d, 0), (0, d), (0, -d)] {
            let (u, v) = (x + dx, y + dy);
            if u < 0 || v < 0 || u >= w as isize || v >= h as isize {
                continue;
            }
            if let Some(b) = own[v as usize * w + u as usize].filter(|&b| b != a) {
                strips.entry((a, b)).or_default().push(lg[i]);
            }
        }
    }
    let median = |v: &[[f32; 3]], j: usize| {
        let mut v: Vec<f32> = v.iter().map(|p| p[j]).collect();
        let m = v.len() / 2;
        *v.select_nth_unstable_by(m, f32::total_cmp).1
    };
    strips
        .iter()
        .filter(|((a, b), s)| a < b && s.len() >= SHEET_MIN_CELLS)
        .filter_map(|(&(a, b), s)| {
            let o = strips.get(&(b, a)).filter(|o| o.len() >= SHEET_MIN_CELLS)?;
            Some((a, b, [0, 1, 2].map(|j| median(s.as_slice(), j) - median(o.as_slice(), j)), s.len().min(o.len())))
        })
        .collect()
}

/// The sheets' log gains per band (`n` sheets) that cancel the borders' differences: least squares weighted by the
/// square root of a border's cells, held to 0 by SHEET_HOLD; ten rounds weighting down a border whose difference
/// stays past SHEET_ROBUST (Huber), so a border on a real change in the ground does not shade a whole sheet.
fn balance(n: usize, borders: &[Border]) -> Vec<[f32; 3]> {
    let mut gain = vec![[0f32; 3]; n];
    if borders.is_empty() {
        return gain;
    }
    let base: Vec<f64> = borders.iter().map(|b| (b.3 as f64).sqrt()).collect();
    let hold = SHEET_HOLD * base.iter().sum::<f64>() / base.len() as f64;
    for j in 0..3 {
        let mut wt = base.clone();
        for _ in 0..10 {
            // The normal equations, row-major (`georef::solve`); the right side in the first of its two columns.
            let (mut m, mut rhs) = (vec![0f64; n * n], vec![[0f64; 2]; n]);
            for (k, &(a, b, d, _)) in borders.iter().enumerate() {
                let (wk, dk) = (wt[k], f64::from(d[j]));
                m[a * n + a] += wk;
                m[b * n + b] += wk;
                m[a * n + b] -= wk;
                m[b * n + a] -= wk;
                rhs[a][0] -= wk * dk;
                rhs[b][0] += wk * dk;
            }
            (0..n).for_each(|i| m[i * n + i] += hold);
            if crate::georef::solve(&mut m, &mut rhs, n).is_none() {
                return vec![[0f32; 3]; n];
            }
            let g: Vec<f64> = rhs.iter().map(|r| r[0]).collect();
            for (k, &(a, b, d, _)) in borders.iter().enumerate() {
                let res = (g[a] - g[b] + f64::from(d[j])).abs();
                wt[k] = base[k] * (SHEET_ROBUST / res.max(1e-9)).min(1.0);
            }
            gain.iter_mut().zip(&g).for_each(|(o, v)| o[j] = *v as f32);
        }
    }
    gain
}

/// The original's sheet measurements as this run's start (`list_sheets` checks each line against its ZIP), when the
/// run has none yet.
fn seed_sheets(work: &Path, index: &Path, pr: &dyn Progress) -> Result<()> {
    if !work.join("sheets.tsv").exists() && index.is_file() {
        std::fs::copy(index, work.join("sheets.tsv"))?;
        log!(pr, "survey: the sheet measurements reused from {}", index.display());
    }
    Ok(())
}

/// Runs `a` on a thread beside `b`, both with a stop flag that `cancel` or the first failure sets; returns the first
/// failure (not the other branch's "cancelled" that followed it), else both results.
fn both<A: Send, B>(
    cancel: &AtomicBool,
    a: impl FnOnce(&AtomicBool) -> Result<A> + Send,
    b: impl FnOnce(&AtomicBool) -> Result<B>,
) -> Result<(A, B)> {
    let (stop, done) = (AtomicBool::new(false), AtomicBool::new(false));
    // Which branch failed first: 0 none, 1 a, 2 b.
    let first = std::sync::atomic::AtomicU8::new(0);
    let fail = |who: u8| {
        let _ = first.compare_exchange(0, who, Ordering::SeqCst, Ordering::SeqCst);
        stop.store(true, Ordering::SeqCst);
    };
    let (ra, rb) = std::thread::scope(|s| {
        s.spawn(|| {
            while !done.load(Ordering::Relaxed) {
                if cancel.load(Ordering::Relaxed) {
                    stop.store(true, Ordering::Relaxed);
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
        });
        let ha = s.spawn(|| a(&stop).inspect_err(|_| fail(1)));
        let rb = b(&stop).inspect_err(|_| fail(2));
        let ra = ha.join().unwrap_or_else(|_| Err(anyhow::anyhow!("a branch panicked")));
        done.store(true, Ordering::Relaxed);
        (ra, rb)
    });
    match (ra, rb) {
        (Ok(a), Ok(b)) => Ok((a, b)),
        (Err(e), Ok(_)) | (Ok(_), Err(e)) => Err(e),
        (Err(ea), Err(eb)) => Err(if first.load(Ordering::SeqCst) == 2 { eb } else { ea }),
    }
}

/// The Sentinel-2 tiles' download rate (bytes/s): 3 transfers at the 4.6 MB/s measured per transfer (terrain.md §7).
// ponytail: one fixed rate; another line speed makes the time left wrong during the download only. Tiles streamed for
// want of disk room are counted as a download too: the bar then jumps to the 32 m part.
const FETCH_RATE: f64 = 13.8e6;
/// The colour branch's other parts' seconds on the developer's laptop: Sentinel-2 at 32 m and at 8 m from the cached
/// tiles (inferred: the streamed run's 191 s and 557 s (setup.md §7) times 4 s / 35 s, a cached 8 m unit against a
/// streamed one, terrain.md §7), the Survey's 2 m, the coarser levels after both branches. The heights run beside
/// the colour and end before it, except with every tile cached and the DEM to download (a pause of about a minute).
const S2_32M_S: f64 = 22.0;
const S2_8M_S: f64 = 64.0;
const SURVEY_S: f64 = 4500.0;
const LEVELS_S: f64 = 60.0;

/// Where each part of the terrain step's bar ends: part i is `ends[i]..ends[i + 1]` (0 the Sentinel-2 download of
/// `fetch` bytes, 1 the 32 m nodes, 2 the 8 m nodes, 3 the Survey's 2 m when `survey`); the coarser levels fill the
/// rest. By expected seconds, so the fraction grows evenly with time and the wizard's time left holds steady.
fn part_ends(fetch: u64, survey: bool) -> [f32; 5] {
    let secs = [fetch as f64 / FETCH_RATE, S2_32M_S, S2_8M_S, if survey { SURVEY_S } else { 0.0 }];
    let total = secs.iter().sum::<f64>() + LEVELS_S;
    let mut ends = [0.0; 5];
    for i in 0..4 {
        ends[i + 1] = ends[i] + (secs[i] / total) as f32;
    }
    ends
}

/// The listed tiles that meet the lon / lat box `geo`.
fn tiles_in(tiles: &BTreeMap<String, u64>, geo: [f64; 4]) -> Vec<String> {
    tiles
        .keys()
        .filter(|n| tile_box(n).is_some_and(|b| b[0] < geo[2] && geo[0] < b[2] && b[1] < geo[3] && geo[1] < b[3]))
        .cloned()
        .collect()
}

/// The UTM rect of the level-5 nodes the detail area touches (the 8 m nodes, at full Sentinel-2 resolution), inside
/// the theatre.
fn fine_area(f: &Frame, detail: [f64; 4]) -> [f64; 4] {
    let (e1, n0) = (f.e0 + f64::from(f.w), f.n1 - f64::from(f.h));
    let b =
        f.nodes_in(5, detail).into_iter().map(|k| f.utm(k)).fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, u| {
            [b[0].min(u[0]), b[1].min(u[1]), b[2].max(u[2]), b[3].max(u[3])]
        });
    [b[0].max(f.e0), b[1].max(n0), b[2].min(e1), b[3].min(f.n1)]
}

/// The bytes of the Sentinel-2 tiles the theatre downloads (those under the 8 m nodes) already whole in `cache` (the
/// setup wizard's disk check): only the listings already cached count (no network); 0 without them or without GDAL.
pub fn s2_cached_bytes(cache: &Path) -> u64 {
    let fine = Frame::new(BOX).map(|f| fine_area(&f, DETAIL));
    fine.and_then(geo_bbox).map_or(0, |geo| cached_in(cache, geo))
}

/// [`s2_cached_bytes`] over the lon / lat box `geo`.
fn cached_in(cache: &Path, geo: [f64; 4]) -> u64 {
    let mut sum = 0;
    for lat in geo[1].floor() as i32..=geo[3].floor() as i32 {
        let Ok(t) = std::fs::read_to_string(cache.join(format!("listing_N{lat:02}.tsv"))) else { continue };
        let tiles: BTreeMap<String, u64> = t
            .lines()
            .filter_map(|l| l.split_once('\t'))
            .map(|(n, b)| (n.to_string(), b.parse().unwrap_or(0)))
            .collect();
        for (n, b) in &tiles {
            let inside = tile_box(n).is_some_and(|x| x[0] < geo[2] && geo[0] < x[2] && x[1] < geo[3] && geo[1] < x[3]);
            if inside && tile_whole(cache, &tiles, n) {
                sum += b;
            }
        }
    }
    sum
}

/// The heights branch: the GLO-30 tiles (cache first), the 64 m grid, the bases graded, the height nodes (`bases_only`:
/// those around the bases); returns what it reused.
fn heights(
    r: &Run,
    f: &Frame,
    geo: [f64; 4],
    work: &Path,
    bases_only: bool,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<String> {
    let t0 = std::time::Instant::now();
    log!(pr, "heights: GLO-30 tiles from {}", r.dem_cache.display());
    let (tiles, line) = crate::imagery_run::fetch_dem(&r.dem_cache, geo, pr, cancel)?;
    log!(pr, "heights: DEM {line}");
    log!(pr, "heights: the 64 m grid from {} tiles", tiles.len());
    let mut grid = dem_grid(&tiles, r.area, work)?;
    let graded: Vec<[f64; 4]> =
        crate::sim_bases::load(&r.airbases)?.iter().filter_map(|b| grade_base(&mut grid, f, b)).collect();
    log!(
        pr,
        "heights: {} bases graded; the height nodes{}",
        graded.len(),
        if bases_only { " around them" } else { "" }
    );
    // Half the workers: the colour branch runs beside it.
    write_heights(f, &grid, &r.out, bases_only.then_some(&graded[..]), (r.threads / 2).max(1), cancel)?;
    log!(pr, "heights: done ({})", crate::progress::duration(t0.elapsed()));
    Ok(line)
}

/// The Sentinel-2 units (the 32 m nodes' level-7 units, the 8 m nodes' level-5 units) and their done marks' names.
fn s2_units(
    f: &Frame,
    detail: [f64; 4],
    bases: &[Vec<[f64; 2]>],
    border: &BTreeSet<Key>,
) -> [(&'static str, Vec<Key>); 4] {
    let detail5: BTreeSet<Key> = f.nodes_in(5, detail).into_iter().collect();
    let inside = |k: Key| (k.1 << k.0) * NODE_PIXELS < f.w && (k.2 << k.0) * NODE_PIXELS < f.h;
    let coarse = |k: Key| inside(k) && !detail5.contains(&k);
    let u7: Vec<Key> = f.nodes(7).into_iter().filter(|u| f.nodes_in(5, f.utm(*u)).into_iter().any(coarse)).collect();
    // "_rim": the 32 m nodes without the overviews' rim (RIM): a theatre rebuilt for a change in its inputs makes them
    // again, though their old marks say done (Setup's redo clears the marks anyway).
    // The 8 m units around an airbase (its outline and TONE_REACH_M beyond) are marked with BASE_FILL: the bases' toned
    // Sentinel-2 is read from their level-3 nodes before the photo goes into them.
    let near: Vec<[f64; 4]> = bases
        .iter()
        .map(|p| {
            let b = crate::bbox(p.iter());
            let m = TONE_REACH_M + BASE_COVER_M + BASE_FEATHER_M;
            [b[0] - m, b[1] - m, b[2] + m, b[3] + m]
        })
        .collect();
    // The 8 m units the border tone touches (BorderTone) are marked with BORDER_FILL, before the bases'.
    let (on_border, detail5): (Vec<Key>, Vec<Key>) = detail5.into_iter().partition(|k| border.contains(k));
    let (on_base, rest): (Vec<Key>, Vec<Key>) =
        detail5.into_iter().partition(|&k| near.iter().any(|b| f.nodes_in(5, *b).contains(&k)));
    [("s2_32m_rim", u7), (S2_8M, rest), (S2_8M_BASE, on_base), (S2_8M_BORDER, on_border)]
}

/// The bases' fill (the done marks of the units on them, `stamp`'s "base_fill"): Sentinel-2 toned to the photo around
/// (BaseTone; "tone" on 2026-11-14 morning: local means, then "median"). S2_8M_BASE changes with it: those units put
/// Sentinel-2 back into the level-3 nodes the tone reads.
const BASE_FILL: &str = "median";
const S2_8M_BASE: &str = "s2_8m_median_sheets1";
/// The other 8 m units' marks. Every 8 m and Survey mark ends in SHEET_TONE ("_sheets1", 2026-11-25): a new sheet tone
/// writes the photo everywhere again, over Sentinel-2 put back into the level-3 nodes first.
const S2_8M: &str = "s2_8m_sheets1";
/// The border's fill (`stamp`'s "border_fill", the done marks of the units at the border and the work file of their
/// list): the neighbours' Sentinel-2 toned to the photo (BorderTone, 2026-11-15). S2_8M_BORDER changes with it. A
/// border unit has only this mark, also when it lies on a base or the shore: renaming BASE_FILL, S2_8M or the
/// Survey's marks (SHEET_TONE), rename S2_8M_BORDER with them, or the border units keep the old build.
/// "tone2", "tone3" (2026-11-24): the sheets' white fill joined to their no-data, then to pure white, left out inland
/// too (`white_fill`); "tone4" (2026-11-25): a large near-white patch too (FILL_MIN_PX); "tone5" with its edge
/// (FILL_EDGE_PX); "tone6" (2026-11-25): the local match (LOCAL_SAMPLE_M) and the photo's fade toward the fill
/// (FILL_FEATHER_M); "tone7" the same, the fade toward a large fill only (`large_only`).
const BORDER_FILL: &str = "tone7";
const S2_8M_BORDER: &str = "s2_8m_border_tone7_sheets1";

/// Whether `dir` holds a Survey sheet ZIP: only then does the colour branch make the 2 m nodes (and read the shore).
fn has_zips(dir: &Path) -> bool {
    std::fs::read_dir(dir)
        .map(|d| d.filter_map(|e| e.ok()).any(|e| e.path().extension().is_some_and(|x| x.eq_ignore_ascii_case("zip"))))
        .unwrap_or(false)
}

/// Whether a Sentinel-2 unit is still to do (its mark missing in `work`), or with the Survey (`zips`) the border's
/// units not listed yet: only then are the tiles listed and read.
fn s2_left(f: &Frame, detail: [f64; 4], bases: &[Vec<[f64; 2]>], work: &Path, zips: bool) -> bool {
    let border = border_units(work);
    if zips && border.is_none() {
        return true;
    }
    let [s2, _] = border.unwrap_or_default();
    s2_units(f, detail, bases, &s2).iter().any(|(what, list)| list.iter().any(|&u| !done(work, what, u).exists()))
}

/// Whether a Sentinel-2 unit other than the border's is still to do. When none is, the border's units are made from
/// the 10 m tiles on disk alone (`sentinel`): the border tone never fetches a tile (2026-11-17: on the laptop it
/// wanted 7 tiles, 4.6 GB, the theatre had read over the network before).
/// A unit an earlier run built under an older mark (a code change renamed it) does not count: it is made again from
/// the tiles on disk alone (`sentinel`). 2026-11-25: renaming "s2_8m" fetched 3 tiles, 1.94 GB (the user's rule: a
/// code change never triggers a download).
fn s2_rest_left(f: &Frame, detail: [f64; 4], bases: &[Vec<[f64; 2]>], work: &Path) -> bool {
    let [s2, _] = border_units(work).unwrap_or_default();
    let built = s2_built(work);
    s2_units(f, detail, bases, &s2)[..3]
        .iter()
        .any(|(what, list)| list.iter().any(|&u| !done(work, what, u).exists() && !built.contains(&u)))
}

/// The units with a Sentinel-2 mark of any name, current or older: those an earlier run built.
fn s2_built(work: &Path) -> BTreeSet<Key> {
    let names = std::fs::read_dir(work).into_iter().flatten().flatten();
    names
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| n.starts_with("done_s2_"))
        .filter_map(|n| {
            let mut p = n.rsplit('_').map(|x| x.parse::<u32>().ok());
            let (j, i, l) = (p.next()??, p.next()??, p.next()??);
            Some((l, i, j))
        })
        .collect()
}

/// Whether the Sentinel-2 units still to do read only the cache: every 32 m unit done (the edge tiles' extracts read
/// then), and every 10 m tile under the 8 m nodes listed and whole there. So a theatre made again for its bases' fill
/// (BASE_FILL) fetches nothing.
fn s2_cached(r: &Run, f: &Frame, bases: &[Vec<[f64; 2]>]) -> bool {
    let work = r.out.join(".work");
    let [(m32, u7), ..] = s2_units(f, r.detail, bases, &BTreeSet::new());
    if u7.iter().any(|&u| !done(&work, m32, u).exists()) {
        return false;
    }
    let Ok(geo) = geo_bbox(fine_area(f, r.detail)) else { return false };
    let mut tiles = BTreeMap::new();
    for lat in geo[1].floor() as i32..=geo[3].floor() as i32 {
        let Ok(t) = std::fs::read_to_string(r.s2_cache.join(format!("listing_N{lat:02}.tsv"))) else { return false };
        tiles
            .extend(t.lines().filter_map(|l| l.split_once('\t')).map(|(n, b)| (n.to_string(), b.parse().unwrap_or(0))));
    }
    tiles_in(&tiles, geo).iter().all(|n| tile_whole(&r.s2_cache, &tiles, n))
}

/// What a run of `r` would fetch over the network, by name: the DEM tiles missing from the cache (neither `.tif` nor
/// `.none`), with the Survey sheets the OpenStreetMap extracts the shore's photo is cut by, and "sentinel-2" while a Sentinel-2 unit is still
/// to do besides the border's (`s2_rest_left`), or while a 10 m tile under the 8 m nodes was begun and not finished (a
/// `.part`, `sentinel` finishes it). Empty: the run reads only local files (setup's "Nothing to download").
pub fn would_fetch(r: &Run) -> Result<Vec<String>> {
    let geo = crate::sim_bases::theatre_geo(r.area);
    let mut v = Vec::new();
    for lat in geo[1].floor() as i32..=geo[3].floor() as i32 {
        for lon in geo[0].floor() as i32..=geo[2].floor() as i32 {
            let name = crate::imagery_run::dem_tile(lat, lon);
            if !["tif", "none"].iter().any(|x| r.dem_cache.join(format!("{name}.{x}")).exists()) {
                v.push(name);
            }
        }
    }
    let extracts = if has_zips(&r.sheets) { crate::sim_coast::water_extracts(geo) } else { Vec::new() };
    for (d, dir) in extracts {
        if !crate::thirdparty::file_done(&r.osm.join(dir), &d) {
            v.push(d.file.to_string());
        }
    }
    let (f, bases) = (Frame::new(r.area)?, base_outlines(&r.airbases)?);
    if s2_pending(r) || s2_rest_left(&f, r.detail, &bases, &r.out.join(".work")) && !s2_cached(r, &f, &bases) {
        v.push("sentinel-2".into());
    }
    Ok(v)
}

/// The Sentinel-2 nodes: the tiles from the cache (fetched or cut when missing, `tile_sources`), their VRTs and the
/// units still to do; the colour branch's progress parts (`part_ends`) and its log line.
fn sentinel(
    r: &Run,
    f: &Frame,
    geo: [f64; 4],
    work: &Path,
    survey: Option<(&str, &[SheetLevels])>,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<([f32; 5], String)> {
    let has_zips = survey.is_some();
    let (t0, out, f) = (std::time::Instant::now(), r.out.as_path(), *f);
    // Sentinel-2: one VRT over the WorldCover tiles (their overviews serve the 32 m nodes).
    log!(pr, "sentinel-2: WorldCover tiles from {}", r.s2_cache.display());
    let tiles = list_tiles(&r.s2_cache, BUCKET, geo[1].floor() as i32, geo[3].floor() as i32)?;
    let whole = |n: &String| tile_whole(&r.s2_cache, &tiles, n);
    // Only the border's units to do: the whole tiles on disk alone, and those whose download began (a `.part`,
    // finished now: the user, 2026-11-24, "download the missing tiles, ofcourse!"); nothing else fetched or cut
    // (`s2_rest_left`).
    let local = !s2_rest_left(&f, r.detail, &base_outlines(&r.airbases)?, work);
    let mut names = tiles_in(&tiles, geo);
    // The tiles outside the 8 m nodes are read only at 32 m, from their 20 m overview: not downloaded whole.
    let mut fine = tiles_in(&tiles, geo_bbox(fine_area(&f, r.detail))?);
    if local {
        let begun = tiles_begun(&r.s2_cache);
        fine.retain(|n| whole(n) || begun.contains(n));
        names.clone_from(&fine);
        if fine.is_empty() {
            write_border_units(work, &BTreeSet::new(), &BTreeSet::new())?;
            log!(pr, "sentinel-2: no 10 m tile on disk, the border left as it is");
            return Ok((part_ends(0, has_zips), "no tile on disk".to_string()));
        }
    }
    let coarse: Vec<String> = names.iter().filter(|n| !fine.contains(n)).cloned().collect();
    // One bar over the colour branch, the longer of the two (the heights run beside it): its parts by their expected
    // seconds (`part_ends`).
    let fetch: u64 =
        fine.iter().filter(|n| !tile_whole(&r.s2_cache, &tiles, n)).map(|n| tiles.get(n).copied().unwrap_or(0)).sum();
    let ends = part_ends(fetch, has_zips);
    let part = |i: usize| Part { pr, from: ends[i], to: ends[i + 1] };
    // The edge tiles' window: the theatre's level-5 nodes (the last row and column reach past its box), a little
    // wider for the resampling.
    let span5 = f64::from(NODE_PIXELS << 5);
    let (w5, h5) = ((f64::from(f.w) / span5).ceil() * span5, (f64::from(f.h) / span5).ceil() * span5);
    let g = geo_bbox([f.e0, f.n1 - h5, f.e0 + w5, f.n1])?;
    let edges = Edges { names: &coarse, window: [g[0] - 0.01, g[1] - 0.01, g[2] + 0.01, g[3] + 0.01] };
    let (paths, s2_line) = tile_sources(&r.s2_cache, BUCKET, &tiles, &names, &edges, &part(0), cancel)?;
    log!(pr, "sentinel-2: {s2_line} ({})", crate::progress::duration(t0.elapsed()));
    let urls: Vec<String> = paths.into_values().collect();
    // The 8 m nodes read the 10 m tiles; the 32 m nodes read every tile at 20 m: each 10 m tile through its first
    // overview (a one-line VRT), each edge tile's kept 20 m extract as it is (the same pixels).
    let (full, edge): (Vec<&String>, Vec<&String>) = urls.iter().partition(|u| !u.ends_with("_20m.tif"));
    let s2 = work.join("s2.vrt");
    let mut a = vec!["-q", "-overwrite", utf8(&s2)?];
    a.extend(full.iter().map(|u| u.as_str()));
    gdal("gdalbuildvrt", &a)?;
    // gdalbuildvrt skips a source it cannot open with only a warning: a tile read online while offline would turn
    // into sea in the finished nodes.
    let text = std::fs::read_to_string(&s2)?;
    if let Some(u) = full.iter().find(|u| u.starts_with("/vsicurl/") && !text.contains(u.as_str())) {
        bail!("{u}: not readable over the network; run again when online");
    }
    let mut ovr = Vec::new();
    for (k, u) in full.iter().enumerate() {
        let v = work.join(format!("s2_20m_{k}.vrt"));
        gdal("gdal_translate", &["-q", "-of", "VRT", "-oo", "OVERVIEW_LEVEL=0", u.as_str(), utf8(&v)?])?;
        ovr.push(utf8(&v)?.to_string());
    }
    ovr.extend(edge.iter().map(|u| u.to_string()));
    let s2_20 = work.join("s2_20m.vrt");
    let mut a = vec!["-q", "-overwrite", "-resolution", "highest", utf8(&s2_20)?];
    a.extend(ovr.iter().map(String::as_str));
    gdal("gdalbuildvrt", &a)?;
    let (s2, s2_20) = (utf8(&s2)?, utf8(&s2_20)?);
    let detail5: BTreeSet<Key> = f.nodes_in(5, r.detail).into_iter().collect();
    let inside = |k: Key| (k.1 << k.0) * NODE_PIXELS < f.w && (k.2 << k.0) * NODE_PIXELS < f.h;
    let coarse = |k: Key| inside(k) && !detail5.contains(&k);
    let fine = |k: Key| inside(k) && detail5.contains(&(5, k.1 >> (5 - k.0), k.2 >> (5 - k.0)));
    // Local: a unit with a tile not on disk is left out of the border's list, and a unit built before
    // (`s2_rest_left`) keeps its earlier build: its mark is written, so nothing is fetched for it later either.
    // ponytail: a kept unit misses the change that renamed its mark; a first build downloads every 10 m tile under the
    // 8 m nodes, so only a cache that never held one keeps a unit. A 32 m unit reads the edge tiles, never whole on
    // disk: local, it is always kept (rename "s2_32m_rim" only with its tiles in mind).
    let has = |k: Key| !local || geo_bbox(f.utm(k)).is_ok_and(|g| tiles_in(&tiles, g).iter().all(whole));
    // With the Survey: the border's tone over the detail area and BORDER_FEATHER_M around (in the theatre), and the
    // units it touches listed for the runs after.
    let border = match survey {
        Some((vrt, levels)) => {
            let m = f64::from(BORDER_FEATHER_M);
            let area = [
                (r.detail[0] - m).max(f.e0),
                (r.detail[1] - m).max(f.n1 - f64::from(f.h)),
                (r.detail[2] + m).min(f.e0 + f64::from(f.w)),
                (r.detail[3] + m).min(f.n1),
            ];
            let t1 = std::time::Instant::now();
            let bt = BorderTone::new((vrt, levels), s2, &f, area, work, &base_outlines(&r.airbases)?, &has)?;
            write_border_units(work, &bt.s2_units, &bt.survey_units)?;
            log!(
                pr,
                "sentinel-2: the border toned to the photo, {} of {} blocks fitted, {} 8 m and {} Survey units ({})",
                bt.tones.iter().flatten().count(),
                bt.tones.len(),
                bt.s2_units.len(),
                bt.survey_units.len(),
                crate::progress::duration(t1.elapsed())
            );
            Some(bt)
        }
        None => None,
    };
    let none = BTreeSet::new();
    let on_border = border.as_ref().map_or(&none, |b| &b.s2_units);
    let [(m32, u7), (m8, u5), (m8b, u5b), (m8x, u5x)] = s2_units(&f, r.detail, &base_outlines(&r.airbases)?, on_border);
    let bt = border.as_ref();
    units(m32, &u7, work, r.threads, &part(1), cancel, |u| {
        if has(u) { sentinel_unit((s2_20, None), &f, u, 5, &coarse, work, out) } else { Ok(()) }
    })?;
    for (m, list) in [(m8, &u5), (m8b, &u5b), (m8x, &u5x)] {
        units(m, list, work, r.threads, &part(2), cancel, |u| {
            if has(u) { sentinel_unit((s2, bt), &f, u, 3, &fine, work, out) } else { Ok(()) }
        })?;
    }
    Ok((ends, s2_line))
}

/// The colour branch: Sentinel-2 from the shared tile cache (the missing tiles fetched into it), its 32 m and 8 m
/// nodes, then the Survey sheets over them; returns what it reused.
fn colour(r: &Run, f: &Frame, geo: [f64; 4], work: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<String> {
    let t0 = std::time::Instant::now();
    let (out, work) = (r.out.as_path(), work.to_path_buf());
    let f = *f;
    let has_zips = has_zips(&r.sheets);
    let detail5: BTreeSet<Key> = f.nodes_in(5, r.detail).into_iter().collect();
    let inside = |k: Key| (k.1 << k.0) * NODE_PIXELS < f.w && (k.2 << k.0) * NODE_PIXELS < f.h;
    let fine = |k: Key| inside(k) && detail5.contains(&(5, k.1 >> (5 - k.0), k.2 >> (5 - k.0)));
    // The Survey of Israel 2 m sheets already downloaded: their units, levels and VRT, before Sentinel-2 (its units at
    // the border are toned to the photo, BorderTone).
    let survey = if has_zips {
        seed_sheets(&work, &r.sheet_index, pr)?;
        log!(pr, "survey: the sheet ZIPs in {}", r.sheets.display());
        let (sheets, _) = list_sheets(&r.sheets, &work, pr, cancel)?;
        let u4: Vec<Key> = f.nodes(4).into_iter().filter(|&k| fine(k)).collect();
        let corners: Vec<[f64; 2]> = u4
            .iter()
            .flat_map(|&k| {
                let e = f.utm(k);
                [[e[0], e[3]], [e[2], e[3]], [e[0], e[1]], [e[2], e[1]]]
            })
            .collect();
        let itm: Vec<[f64; 2]> = corners
            .iter()
            .map(|p| {
                let g = utm36n_geo(p[0], p[1]);
                crate::itm::from_wgs84(g[0], g[1])
            })
            .collect();
        // Units with a sheet: (key, ITM corners, ITM bounding box).
        let mut list = Vec::new();
        for (n, &k) in u4.iter().enumerate() {
            let c: [[f64; 2]; 4] = itm[n * 4..n * 4 + 4].try_into()?;
            let b = crate::bbox(c.iter());
            if !near(&sheets, &[b], 0.0).is_empty() {
                list.push((k, c, b));
            }
        }
        let keys: Vec<Key> = list.iter().map(|u| u.0).collect();
        // The sheets whose levels reach a unit (their blend spans DARK_BLEND / 2 = 2 km beyond a sheet).
        let sheets = near(&sheets, &list.iter().map(|u| u.2).collect::<Vec<_>>(), 2000.0);
        let vrt = soi_vrt(&sheets, &r.sheets, &work, pr)?;
        log!(pr, "survey: {} sheets ({})", sheets.len(), crate::progress::duration(t0.elapsed()));
        let tone = sheet_tone(&sheets, &vrt, &work, pr)?;
        let levels: Vec<SheetLevels> = sheets
            .iter()
            .zip(&tone)
            .map(|(s, g)| (s.bbox, [s.levels[0], s.levels[1], s.levels[2], s.levels[3], g[0], g[1], g[2]]))
            .collect();
        Some((list, keys, levels, vrt))
    } else {
        None
    };
    // Sentinel-2 only while one of its units is still to do: a theatre rebuilt for its photo (or any later change)
    // reads no tile and fetches nothing (the user, 2026-11-13: a code change never makes the player download again).
    // Or while a 10 m tile's download was begun and not finished (`s2_begun`): `sentinel` finishes it and redoes the
    // border's units over it, which the border's list left out while the tile was not whole.
    let (ends, s2_line) = if s2_pending(r) || s2_left(&f, r.detail, &base_outlines(&r.airbases)?, &work, has_zips) {
        let sv = match &survey {
            Some((_, _, levels, vrt)) => Some((utf8(vrt)?, levels.as_slice())),
            None => None,
        };
        sentinel(r, &f, geo, &work, sv, pr, cancel)?
    } else {
        log!(pr, "sentinel-2: every node built, no tile read");
        (part_ends(0, has_zips), "every node built".to_string())
    };
    let part = |i: usize| Part { pr, from: ends[i], to: ends[i + 1] };

    if let Some((list, keys, levels, vrt)) = survey {
        let bases = base_outlines(&r.airbases)?;
        let pbfs = crate::sim_coast::fetch_extracts(&r.osm, geo, pr, cancel)?;
        log!(pr, "survey: the coastline from {} OpenStreetMap extracts", pbfs.len());
        let coast = crate::sim_coast::Coast::load(&pbfs, geo, &work)?;
        let mut sv = Survey { vrt: utf8(&vrt)?, coast: &coast, levels, bases: &bases, tones: Vec::new() };
        // The units on a base's cover have their own marks (BASE_FILL), as their 8 m Sentinel-2 units (s2_units): they
        // run again when the bases' fill changes, over Sentinel-2's own level-3 nodes.
        // The units the border's tone touches (BorderTone: their 2 m nodes hold its Sentinel-2 under the photo's soft
        // edge) have theirs too (BORDER_FILL), as their 8 m units; a base's cover in one is toned as in the others.
        let border4 = border_units(&work).map(|[_, s]| s).unwrap_or_default();
        let border_mark = format!("survey_2m_border_{BORDER_FILL}_{SHEET_TONE}");
        let base_mark = format!("survey_2m_{BASE_FILL}_{SHEET_TONE}");
        let (on_border, keys): (Vec<Key>, Vec<Key>) = keys.iter().partition(|&&k| border4.contains(&k));
        let (on_base, keys): (Vec<Key>, Vec<Key>) =
            keys.iter().partition(|&&k| BaseMask::new(&bases, f.utm(k)).is_some());
        if on_base.iter().any(|&k| !done(&work, &base_mark, k).exists())
            || on_border
                .iter()
                .any(|&k| !done(&work, &border_mark, k).exists() && BaseMask::new(&bases, f.utm(k)).is_some())
        {
            for b in &bases {
                if let Some(t) = BaseTone::new(&sv, &f, b, out, &work)? {
                    let c = crate::bbox(b.iter());
                    log!(
                        pr,
                        "survey: the base at {:.0} E {:.0} N, grey × {:.2} + {:.0}, tint × {:.2} + {:.0} {:.0} {:.0}",
                        c[0],
                        c[1],
                        t.grey[0],
                        t.grey[1],
                        t.chroma,
                        t.tint[0],
                        t.tint[1],
                        t.tint[2]
                    );
                    sv.tones.push(t);
                }
            }
            log!(pr, "survey: {} bases' Sentinel-2 toned to the photo", sv.tones.len());
        }
        let sv = sv;
        units(&base_mark, &on_base, &work, r.threads, &part(3), cancel, |k: Key| {
            let (_, c, _) = list.iter().find(|u| u.0 == k).context("unit")?;
            survey_unit(&sv, &f, k, *c, &work, out)
        })?;
        // The units the coastline comes near have their own marks: they run again once when the photo's sea rule
        // changes (cut to the coastline, then the sea beyond its reach Sentinel-2's; 2026-11-08).
        let (shore, inland): (Vec<Key>, Vec<Key>) = keys.iter().partition(|&&k| coast.touches(f.utm(k)));
        let run = |k: Key| {
            let (_, c, _) = list.iter().find(|u| u.0 == k).context("unit")?;
            survey_unit(&sv, &f, k, *c, &work, out)
        };
        // "_lv" (2026-11-13): the photo by its sheets' levels alone (before, matched to Sentinel-2); "_sheets1"
        // (2026-11-25): and the sheets' tone (`sheet_tone`). So a theatre built before writes its 2 m nodes again.
        // Their base (`ancestor_crop(.., 3)`) is Sentinel-2 only until the first `parents(out, 3, ..)` below writes
        // the photo into level 3: renaming these marks again, rename S2_8M with them, or the units run over the old
        // photo at 8 m (the airbases' made-up ground, the sea's no-data).
        units(&border_mark, &on_border, &work, r.threads, &part(3), cancel, run)?;
        units(&format!("survey_2m_{SHEET_TONE}"), &inland, &work, r.threads, &part(3), cancel, run)?;
        units(&format!("survey_2m_sea_{SHEET_TONE}"), &shore, &work, r.threads, &part(3), cancel, run)?;
        // The coarser levels over the photo are the photo's, as the original game's Survey layer (its own pyramid):
        // level 2 from the 2 m nodes, level 3 from level 2, each over Sentinel-2's level-3 node where no sheet is.
        // Level 3 is its own fallback: a node is read before it is written.
        parents(out, 2, Some(3), r.threads, cancel)?;
        parents(out, 3, Some(3), r.threads, cancel)?;
    } else {
        log!(pr, "{}: no sheet ZIPs, no 2 m nodes", r.sheets.display());
    }
    let survey = if has_zips { "the Survey sheets local" } else { "no Survey sheets" };
    Ok(format!("Sentinel-2 {s2_line}; {survey} ({})", crate::progress::duration(t0.elapsed())))
}

/// `iaf-sim terrain`: see the module doc. Resumable: finished units are marked in `<out>/.work`.
pub fn terrain(r: &Run, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let t0 = std::time::Instant::now();
    let f = Frame::new(r.area)?;
    let (out, work) = (r.out.as_path(), r.out.join(".work"));
    let built_from = stamp(r);
    let old: serde_json::Value =
        std::fs::read(out.join("meta.json")).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    // The same theatre (a "grade" key: the stamp of the grading's first build, 2026-11-16, now GRADE_FILE).
    let mut was = old["built_from"].clone();
    if let Some(o) = was.as_object_mut() {
        o.remove("grade");
        o.remove("s2_begun");
    }
    let grade = grade_text(r);
    let graded = std::fs::read_to_string(out.join(GRADE_FILE)).is_ok_and(|g| g == grade);
    if was == built_from && graded {
        log!(pr, "{}: up to date (same box, detail area and sheets)", out.display());
        return Ok(());
    }
    std::fs::create_dir_all(&work)?;
    if was == built_from {
        log!(pr, "{}: the bases' grading changed: their height nodes only", out.display());
        heights(r, &f, geo_bbox(r.area)?, &work, true, pr, cancel)?;
        return Ok(std::fs::write(out.join(GRADE_FILE), grade)?);
    }
    for l in 0..=ROOT_LEVEL {
        std::fs::create_dir_all(out.join(format!("L{l}")))?;
    }
    let geo = geo_bbox(r.area)?;
    log!(
        pr,
        "theatre {} × {} km, lon {:.2}–{:.2}, lat {:.2}–{:.2}",
        f.w / 1000,
        f.h / 1000,
        geo[0],
        geo[2],
        geo[1],
        geo[3]
    );

    // Two branches at once: the heights (DEM download, warp, height nodes; minutes) and the colour (Sentinel-2 tiles,
    // its nodes, the Survey over them; the long one). At most 4 transfers: the DEM's one by one, the tiles' 3 at once.
    // A failure in either stops the other at its next check.
    let (heights, colour) =
        both(cancel, |stop| heights(r, &f, geo, &work, false, pr, stop), |stop| colour(r, &f, geo, &work, pr, stop))?;

    // A theatre finished with the old fill (its stamp has no "sea"); a fresh one has only SEA, and the composite's own
    // pixels near OLD_SEA stay.
    if old["built_from"].is_object() && old["built_from"]["sea"].is_null() {
        repaint_sea(out, &work, r.threads, cancel)?;
    }
    // The coarser levels from their children (level 4 exists in the detail area only, so the 32 m level-5 nodes
    // stay the source's).
    log!(pr, "levels: the coarser levels 4–{ROOT_LEVEL} from their children");
    for l in 4..=ROOT_LEVEL {
        parents(out, l, None, r.threads, cancel)?;
    }
    write_meta(&f, out, built_from)?;
    std::fs::write(out.join(GRADE_FILE), grade)?;
    let mut bytes = 0u64;
    let mut counts = String::new();
    for l in 0..=ROOT_LEVEL {
        let mut n = 0;
        for e in std::fs::read_dir(out.join(format!("L{l}")))? {
            bytes += e?.metadata()?.len();
            n += 1;
        }
        counts += &format!(" L{l}:{n}");
    }
    log!(
        pr,
        "files ({counts} ), {:.0} MB, {} -> {}",
        bytes as f64 / 1e6,
        crate::progress::duration(t0.elapsed()),
        out.display()
    );
    log!(pr, "terrain done in {}: DEM {heights}; {colour}", crate::progress::duration(t0.elapsed()));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("iaf-sim-terrain-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    /// The sheets' white fill: near-white joined to the warp's no-data is fill; a white roof inside the photo stays.
    #[test]
    fn the_white_fill_is_no_ground() {
        let n = 8;
        let mut raw = vec![0u8; n * n * 4];
        for (i, p) in raw.chunks_mut(4).enumerate() {
            let (x, y) = (i % n, i / n);
            p.copy_from_slice(&match (x, y) {
                (0, 0) => [255, 255, 255, 0],           // the warp's no-data
                (0..=2, _) => [248, 241, 252, 255],     // the fill's JPEG noise
                (5..=6, 5..=6) => [250, 250, 250, 255], // a white roof in the photo
                _ => [120, 110, 90, 255],               // ground
            });
        }
        let fill = white_fill(&raw, n);
        assert!((0..n).all(|y| (0..3).all(|x| fill[y * n + x])), "the fill column");
        // A fill with no pixel left without the photo: its pure white seeds it.
        raw[3] = 255;
        let fill = white_fill(&raw, n);
        assert!(fill[0] && fill[n + 1], "the fill seeded by pure white");
        assert!(!fill[5 * n + 5] && !fill[6 * n + 6], "the roof");
        assert!(fill[n + 4] && !fill[n + 7], "the fill's edge, the ground");
    }

    /// A near-white patch of FILL_MIN_PX joined to no seed is fill (its no-data in the next unit); a small one stays.
    #[test]
    fn a_large_white_patch_is_fill() {
        let n = 256;
        let mut raw = vec![0u8; n * n * 4];
        for (i, p) in raw.chunks_mut(4).enumerate() {
            let (x, y) = (i % n, i / n);
            p.copy_from_slice(&match (x, y) {
                (0..=99, _) => [249, 249, 248, 255],            // the fill: 25,600 pixels, no seed
                (200..=209, 200..=209) => [250, 250, 250, 255], // a white roof
                _ => [120, 110, 90, 255],
            });
        }
        let fill = white_fill(&raw, n);
        assert!(fill[0] && fill[n * n - n + 99], "the fill");
        assert!(!fill[200 * n + 200] && fill[101] && !fill[102], "the roof, the fill's edge, the ground");
    }

    /// The 32 m nodes' rim: a pixel within RIM of an empty one counts as empty, one farther out keeps its own colour.
    #[test]
    fn the_rim_takes_the_fill() {
        let n = 8;
        let near = near_empty(n, 2, |i| i % n == 0 && i / n == 4);
        assert!(near[4 * n + 2] && near[2 * n + 2] && near[6 * n] && !near[4 * n + 3] && !near[n]);
    }

    /// The bar's parts follow their expected seconds: in order, inside 0..1, the download's share from its bytes.
    #[test]
    fn part_ends_follow_the_seconds() {
        for (fetch, survey) in [(0, false), (11_400_000_000, false), (0, true), (11_400_000_000, true)] {
            let e = part_ends(fetch, survey);
            assert_eq!(e[0], 0.0);
            assert!(e.windows(2).all(|w| w[0] <= w[1]) && e[4] < 1.0, "{e:?}");
            let total = fetch as f64 / FETCH_RATE + S2_32M_S + S2_8M_S + if survey { SURVEY_S } else { 0.0 } + LEVELS_S;
            // Each part's share is its seconds' share: the 8 m nodes, e.g.
            assert!(((e[3] - e[2]) as f64 - S2_8M_S / total).abs() < 1e-6);
        }
        assert_eq!(part_ends(0, false)[1], 0.0, "a complete cache: no download part");
        let dl = 11.4e9 / FETCH_RATE;
        assert!((part_ends(11_400_000_000, false)[1] as f64 - dl / (dl + 146.0)).abs() < 1e-6, "the download's share");
        assert_eq!(part_ends(0, false)[4], part_ends(0, false)[3], "no Survey: no 2 m part");
    }

    /// The cached bytes count whole tiles inside the box from cached listings only.
    #[test]
    fn cached_tiles_inside_the_box() {
        let c = tmp("s2cached");
        std::fs::write(c.join("listing_N30.tsv"), "N30E034\t5\nN30E035\t3\nN30E040\t7\n").unwrap();
        let file = |n: &str| c.join(format!("ESA_WorldCover_10m_2021_v200_{n}_S2RGBNIR.tif"));
        std::fs::write(file("N30E034"), "12345").unwrap(); // whole
        std::fs::write(file("N30E035"), "1").unwrap(); // partial
        std::fs::write(file("N30E040"), "1234567").unwrap(); // whole, outside the box
        assert_eq!(cached_in(&c, [34.2, 30.1, 35.9, 31.5]), 5);
        assert_eq!(cached_in(&c.join("none"), [34.2, 30.1, 35.9, 31.5]), 0, "no listing: nothing cached");
    }

    /// The 8 m nodes' rect: the level-5 nodes over Israel, cut to the theatre (the tiles west of 34° E and north
    /// of 34° N lie outside it).
    #[test]
    fn the_fine_area_is_the_detail_nodes() {
        let f = Frame::new(BOX).unwrap();
        assert_eq!(fine_area(&f, DETAIL), [606_208.0, 3_255_296.0, 802_816.0, 3_700_736.0]);
    }

    #[test]
    fn nodes_in_clips_to_the_theatre() {
        let f = Frame::new([500_000.0, 3_400_000.0, 500_000.0 + 2.0 * 32768.0, 3_400_000.0 + 32768.0]).unwrap();
        assert!(f.nodes_in(5, [400_000.0, 3_400_000.0, 450_000.0, 3_410_000.0]).is_empty(), "west of it");
        assert!(f.nodes_in(5, [500_000.0, 3_500_000.0, 520_000.0, 3_510_000.0]).is_empty(), "north of it");
        assert!(f.nodes_in(5, [565_536.0, 3_400_000.0, 600_000.0, 3_410_000.0]).is_empty(), "touching the east edge");
        assert_eq!(f.nodes_in(5, [490_000.0, 3_390_000.0, 510_000.0, 3_410_000.0]), vec![(5, 0, 0)]);
        assert_eq!(f.nodes_in(5, [400_000.0, 3_300_000.0, 700_000.0, 3_500_000.0]).len(), 2);
    }

    /// A base outline whose long edge crosses the rect with no vertex near still masks it; Sentinel-2 covers the
    /// outline and BASE_COVER_M beyond, the Survey is back from BASE_COVER_M + BASE_FEATHER_M.
    #[test]
    fn base_mask_covers_the_outline_and_beyond() {
        // A 20 km × 1 km strip running east-west through a 2 km rect: every vertex is ≥ 9 km away.
        let strip = vec![vec![[0.0, 0.0], [20_000.0, 0.0], [20_000.0, 1000.0], [0.0, 1000.0]]];
        let r = [9000.0, -1000.0, 11_000.0, 2000.0];
        let m = BaseMask::new(&strip, r).expect("the strip crosses the rect");
        assert!(m.at(10_000.0, 500.0) > 0.99, "inside");
        assert!(m.at(10_000.0, 1000.0 + 100.0) > 0.99, "100 m past the outline");
        assert!(m.at(10_000.0, 1000.0 + 240.0) > 0.2 && m.at(10_000.0, 1240.0) < 0.8, "fading");
        assert!(m.at(10_000.0, 1000.0 + 340.0) < 0.01, "340 m past it");
        assert!(BaseMask::new(&strip, [30_000.0, 0.0, 32_000.0, 1000.0]).is_none(), "far from it");
    }

    /// A failing branch stops the other at its next check, and its own error is the one returned.
    #[test]
    fn a_failing_branch_stops_the_other() {
        let t0 = std::time::Instant::now();
        let r = both(
            &AtomicBool::new(false),
            |_| -> Result<()> { bail!("no DEM") },
            |stop| -> Result<()> {
                for _ in 0..600 {
                    check(stop)?;
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
                Ok(())
            },
        );
        assert_eq!(r.unwrap_err().to_string(), "no DEM");
        assert!(t0.elapsed() < std::time::Duration::from_secs(3), "the long branch stopped");
        let ok = both(&AtomicBool::new(false), |_| Ok(1), |_| Ok(2)).unwrap();
        assert_eq!(ok, (1, 2));
    }

    /// The original's sheet measurements start a run that has none, never replace a run's own.
    #[test]
    fn the_sheet_index_seeds_a_new_run() {
        let d = tmp("seed");
        let (work, index) = (d.join("work"), d.join("index.tsv"));
        std::fs::create_dir_all(&work).unwrap();
        seed_sheets(&work, &index, &crate::progress::Stdout).unwrap();
        assert!(!work.join("sheets.tsv").exists(), "no index, nothing");
        std::fs::write(&index, "original\n").unwrap();
        seed_sheets(&work, &index, &crate::progress::Stdout).unwrap();
        assert_eq!(std::fs::read_to_string(work.join("sheets.tsv")).unwrap(), "original\n");
        std::fs::write(work.join("sheets.tsv"), "own\n").unwrap();
        seed_sheets(&work, &index, &crate::progress::Stdout).unwrap();
        assert_eq!(std::fs::read_to_string(work.join("sheets.tsv")).unwrap(), "own\n");
        std::fs::remove_dir_all(&d).unwrap();
    }

    /// One failing item stops the other workers at their next item.
    #[test]
    fn par_stops_after_a_failure() {
        let done = AtomicUsize::new(0);
        let items: Vec<usize> = (0..1000).collect();
        let r = par(&items, 4, &AtomicBool::new(false), |&i| {
            std::thread::sleep(std::time::Duration::from_millis(2));
            done.fetch_add(1, Ordering::Relaxed);
            if i == 0 { bail!("fails") } else { Ok(()) }
        });
        assert!(r.is_err());
        assert!(done.load(Ordering::Relaxed) < 20, "{} items ran", done.load(Ordering::Relaxed));
    }

    /// The shore between Tel Aviv and Ashdod in a built theatre (data: `IAF_ASSETS` or the repo's assets, with the
    /// Survey and the coastline cut, else skipped): at 50 points along OpenStreetMap's coastline, 20 m seaward is sea
    /// in terraintype.dat and no near-white pixel in the 2 m colour, 20 m landward is land; 1 km seaward (beyond the
    /// coastline's reach), where Sentinel-2 shows water, the 2 m colour is Sentinel-2's (its 8 m node's), not the photo's.
    #[test]
    fn the_shore_follows_the_coastline() {
        let assets = std::env::var("IAF_ASSETS")
            .map(PathBuf::from)
            .unwrap_or_else(|_| Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets"));
        let th = assets.join("converted/terrain/israel");
        let meta: serde_json::Value =
            std::fs::read(th.join("meta.json")).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        let tt = std::fs::read(assets.join("converted/own/terraintype.dat")).ok();
        if meta["built_from"]["osm"].as_array().is_none_or(|a| a.is_empty()) || tt.is_none() {
            eprintln!("skip: no theatre cut to the coastline in {} (iaf-sim terrain with the Survey)", th.display());
            return;
        }
        let tt = iaf_formats::terrain_types::TerrainTypes::parse(&tt.unwrap()).unwrap();
        let rect = Meta::load(&th).unwrap().rect;
        let f = Frame::new(rect).unwrap();
        // Tel Aviv's north (Tel Baruch) to Ashdod's port.
        let geo = [34.6, 31.8, 34.82, 32.13];
        let pbf = assets.join("source/scenery").join(crate::sim_coast::osm_extract().file);
        let work = std::env::temp_dir().join(format!("iaf-shore-{}", std::process::id()));
        let coast = crate::sim_coast::Coast::load(&[pbf], geo, &work).unwrap();
        let _ = std::fs::remove_dir_all(&work);
        let (s0, s1) = (crate::sim_bases::utm36n(34.6, 31.8), crate::sim_bases::utm36n(34.82, 32.13));
        let segs: Vec<[[f64; 2]; 2]> = coast
            .segments()
            .iter()
            .copied()
            .filter(|s| (s0[1]..s1[1]).contains(&s[0][1]) && crate::sim_coast::len(s) > 30.0)
            .collect();
        // The points of a plain shore: 20 m off the segment on each side, each on its own side of the whole coastline
        // and no other coastline within 15 m (a pier, a breakwater or a marina narrower than the 16 m leaves).
        let pairs: Vec<([f64; 2], [f64; 2])> = segs
            .iter()
            .map(|s| {
                let m = [(s[0][0] + s[1][0]) / 2.0, (s[0][1] + s[1][1]) / 2.0];
                let l = crate::sim_coast::len(s);
                let d = [(s[1][0] - s[0][0]) / l, (s[1][1] - s[0][1]) / l];
                // The water on the way's right.
                ([m[0] + d[1] * 20.0, m[1] - d[0] * 20.0], [m[0] - d[1] * 20.0, m[1] + d[0] * 20.0])
            })
            .filter(|(sea, land)| {
                coast.sea(*sea) == Some(true)
                    && coast.sea(*land) == Some(false)
                    && !coast.near(*sea, 15.0)
                    && !coast.near(*land, 15.0)
            })
            .collect();
        assert!(pairs.len() >= 50, "{} shore points", pairs.len());
        let mut tiles: std::collections::HashMap<Key, image::RgbImage> = Default::default();
        let (mut white_checked, mut open_checked) = (0, 0);
        for k in 0..50 {
            let (sea, land) = pairs[k * pairs.len() / 50];
            assert_eq!(tt.at(sea[0], sea[1]) & 0x4, 0x4, "{sea:?}: 20 m seaward is not sea");
            assert!(
                iaf_formats::terrain_types::TerrainTypes::is_land(tt.at(land[0], land[1])),
                "{land:?}: 20 m inland ({:#x})",
                tt.at(land[0], land[1])
            );
            let key = (1, ((sea[0] - f.e0) / 2048.0) as u32, ((f.n1 - sea[1]) / 2048.0) as u32);
            if let std::collections::hash_map::Entry::Vacant(e) = tiles.entry(key) {
                match image::open(colour_path(&th, key)) {
                    Ok(i) => e.insert(i.to_rgb8()),
                    Err(_) => continue,
                };
            }
            let r = f.utm(key);
            let px = tiles[&key].get_pixel(((sea[0] - r[0]) / 2.0) as u32, ((r[3] - sea[1]) / 2.0) as u32);
            assert!(px.0.iter().any(|&c| c < NEAR_WHITE), "{sea:?}: a white pixel at sea {px:?}");
            white_checked += 1;
            // 1 km out: the 2 m node (if any) shows its 8 m Sentinel-2 ancestor, as far as JPEG lets (mean of 5 × 5).
            let off = [sea[0] + (sea[0] - land[0]) * 25.0, sea[1] + (sea[1] - land[1]) * 25.0];
            let key = (1, ((off[0] - f.e0) / 2048.0) as u32, ((f.n1 - off[1]) / 2048.0) as u32);
            let r = f.utm(key);
            let (x, y) = (((off[0] - r[0]) / 2.0) as u32, ((r[3] - off[1]) / 2.0) as u32);
            if let (Ok(a), Ok(b)) = (image::open(colour_path(&th, key)), ancestor_crop(&th, key, 3)) {
                let a = a.to_rgb8();
                let mean = |i: &image::RgbImage| {
                    let mut m = [0f32; 3];
                    for (dx, dy) in (0..25).map(|k| (k % 5, k / 5)) {
                        let p = i.get_pixel((x + dx).clamp(2, 1021) - 2, (y + dy).clamp(2, 1021) - 2);
                        (0..3).for_each(|c| m[c] += f32::from(p.0[c]) / 25.0);
                    }
                    m
                };
                let (ma, mb) = (mean(&a), mean(&b));
                open_checked += usize::from(imagery::is_photo_water(mb));
                // A bend or a port may put land there: only Sentinel-2's water counts.
                assert!(
                    !imagery::is_photo_water(mb) || (0..3).all(|c| (ma[c] - mb[c]).abs() < 12.0),
                    "{off:?}: the sea {ma:?}, Sentinel-2 {mb:?}"
                );
            }
        }
        assert!(white_checked >= 25, "{white_checked} points with a 2 m colour node");
        assert!(open_checked >= 25, "{open_checked} points with open water 1 km out");
    }

    /// The chamfer distance: 0 on the seeds, a cell a step along a row, √2 along a diagonal, within 8 % far off.
    #[test]
    fn chamfer_measures_cells_to_the_seed() {
        let (w, h) = (40, 30);
        let mut seed = vec![false; w * h];
        seed[10 * w + 5] = true;
        let d = chamfer(&seed, w, h);
        assert_eq!(d[10 * w + 5], 0.0);
        assert_eq!(d[10 * w + 6], 1.0);
        assert!((d[11 * w + 6] - std::f32::consts::SQRT_2).abs() < 1e-6);
        let (dx, dy) = (30.0f32, 15.0f32);
        let far = d[25 * w + 35];
        assert!((far / dx.hypot(dy) - 1.0).abs() < 0.08, "{far}");
        assert!(chamfer(&[false; 4], 2, 2).iter().all(|&v| v >= 1e6), "no seed: far");
    }

    /// A tone fitted on the same colours on both sides changes nothing (BaseTone::fit, as the bases' and the border's).
    #[test]
    fn a_tone_of_equal_images_is_identity() {
        let cells: Vec<[f32; 3]> = (0..400)
            .map(|i| {
                let v = 60.0 + (i % 20) as f32 * 4.0;
                [v + 6.0, v, v - 8.0]
            })
            .collect();
        let t = BaseTone::fit([0.0; 4], &cells, &cells, &cells).unwrap();
        let t = BaseTone { knee: 255.0, ..t };
        for c in [[70.0, 64.0, 56.0], [120.0, 110.0, 100.0]] {
            let o = t.apply(c);
            assert!((0..3).all(|k| (o[k] - c[k]).abs() < 1.5), "{c:?} -> {o:?}");
        }
    }

    /// The border's tone: full at the photo's edge, half way across the feather partly, none past it, none deep in the
    /// photo (the bases' Sentinel-2) and none on water.
    #[test]
    fn the_border_tone_fades_from_the_edge() {
        // Cells 100 m wide along x: x < 50 in the photo, the edge at 5,000 m.
        let (w, h) = (300, 2);
        let dist: Vec<f32> = (0..w * h).map(|i| ((i % w) as f32 + 0.5) * 100.0 - 5000.0).collect();
        let darker = BaseTone { rect: [0.0; 4], grey: [0.5, 0.0], chroma: 1.0, tint: [0.0; 3], knee: 255.0 };
        let bt = BorderTone {
            rect: [0.0, 0.0, 30_000.0, 200.0],
            w,
            h,
            dist,
            bw: 2,
            bh: 1,
            tones: vec![Some(darker); 2],
            local: vec![[0.0; 3]; w * h],
            s2_units: BTreeSet::new(),
            survey_units: BTreeSet::new(),
        };
        let sand = [200.0, 180.0, 150.0];
        let at = |e: f64| bt.tone(e, 100.0, sand);
        let toned = darker.apply(sand);
        assert!((0..3).all(|k| (at(5_000.0)[k] - toned[k]).abs() < 0.5), "the edge: {:?}", at(5_000.0));
        let mid = at(10_000.0)[0];
        assert!((mid - (sand[0] + toned[0]) / 2.0).abs() < 1.0, "half the feather: {mid}");
        assert_eq!(at(16_000.0), sand, "past the feather");
        assert_eq!(at(4_000.0), sand, "1 km into the photo");
        let water = [40.0, 70.0, 90.0];
        assert_eq!(bt.tone(5_000.0, 100.0, water), water, "water");
        assert_eq!(bt.tone(-10.0, 100.0, sand), sand, "outside the cells");
    }

    /// The local match: at the photo's edge Sentinel-2 takes the photo's own colour over the blocks' tone, half of it
    /// part way, none from LOCAL_REACH_M; a blurred field of equal ratios keeps them.
    #[test]
    fn the_local_match_meets_the_photo() {
        let (w, h) = (300, 2);
        let dist: Vec<f32> = (0..w * h).map(|i| ((i % w) as f32 + 0.5) * 100.0 - 5000.0).collect();
        let same = BaseTone { rect: [0.0; 4], grey: [1.0, 0.0], chroma: 1.0, tint: [0.0; 3], knee: 255.0 };
        let mut acc = vec![[0.8f32.ln(), 0.8f32.ln(), 0.8f32.ln(), 1.0]; w * h];
        box_blur3(&mut acc, w, h, LOCAL_BLUR);
        let bt = BorderTone {
            rect: [0.0, 0.0, 30_000.0, 200.0],
            w,
            h,
            dist,
            bw: 2,
            bh: 1,
            tones: vec![Some(same); 2],
            local: acc.iter().map(|a| [0, 1, 2].map(|k| a[k] / a[3])).collect(),
            s2_units: BTreeSet::new(),
            survey_units: BTreeSet::new(),
        };
        let sand = [190.0, 180.0, 160.0];
        let at = |e: f64| bt.tone(e, 100.0, sand)[0];
        assert!((at(5_000.0) - 152.0).abs() < 1.0, "the edge: {}", at(5_000.0));
        let mid = at(6_000.0);
        assert!(mid > 160.0 && mid < 185.0, "1 km out: {mid}");
        assert!((at(7_500.0) - 190.0).abs() < 0.5, "past the reach: {}", at(7_500.0));
    }

    /// The photo's fade toward the fill: none at the fill, full from FILL_FEATHER_M, rising between.
    #[test]
    fn the_photo_fades_toward_the_fill() {
        let n = 400;
        let cw = n / FEATHER_CELL;
        let seed: Vec<bool> = (0..cw * cw).map(|c| c % cw == 0).collect();
        let fade = feather(&seed, n, 2.0);
        assert!(fade(0, 50) < 0.01, "at the fill: {}", fade(0, 50));
        let v: Vec<f32> = (0..n).step_by(10).map(|x| fade(x, 50)).collect();
        assert!(v.windows(2).all(|p| p[1] >= p[0]), "rising: {v:?}");
        assert!((fade(50, 50) - 0.5).abs() < 0.1, "about half at 100 m: {}", fade(50, 50));
        assert_eq!(fade(120, 50), 1.0, "past the fade");
        assert_eq!(feather(&vec![false; cw * cw], n, 2.0)(10, 10), 1.0, "no fill");
    }

    /// The fade's seeds: a small patch is dropped, a large one kept.
    #[test]
    fn a_small_fill_has_no_fade() {
        let w = 50;
        let mut m: Vec<bool> = (0..w * w).map(|i| (i % w < 20 && i / w < 20) || (i % w > 45 && i / w > 45)).collect();
        large_only(&mut m, w, 100);
        assert!(m[0] && m[19 * w + 19], "the large patch stays");
        assert!(!m[w * w - 1], "the small one goes");
        assert_eq!(m.iter().filter(|&&v| v).count(), 400);
    }

    /// A finished run is stamped in meta.json; the same inputs again return before any work (no network).
    #[test]
    fn a_finished_run_is_not_redone() {
        let out = tmp("stamp");
        let run = Run {
            out: out.clone(),
            dem_cache: out.join("dem"),
            s2_cache: out.join("s2"),
            sheet_index: out.join("sheets.tsv"),
            sheets: out.join("sheets"),
            airbases: out.join("airbases"),
            osm: out.clone(),
            area: [500_000.0, 3_400_000.0, 500_000.0 + 1024.0, 3_400_000.0 + 1024.0],
            detail: DETAIL,
            threads: 1,
        };
        let f = Frame::new(run.area).unwrap();
        write_meta(&f, &out, stamp(&run)).unwrap();
        std::fs::write(out.join(GRADE_FILE), grade_text(&run)).unwrap();
        terrain(&run, &crate::progress::Stdout, &AtomicBool::new(false)).unwrap();
        assert!(!out.join(".work").exists(), "returned before any work");
        std::fs::remove_dir_all(&out).unwrap();
    }

    /// A built theatre rebuilt for a code change (its stamp changed) reads only local files: with every source by its
    /// name in the caches and every Sentinel-2 unit done, `would_fetch` (setup's "Nothing to download") is empty, so
    /// `colour` lists and reads no tile. One unit left, or one source missing, and it says what it would fetch.
    #[test]
    fn a_built_theatre_fetches_nothing() {
        let out = tmp("fetch");
        let run = Run {
            out: out.join("out"),
            dem_cache: out.join("dem"),
            s2_cache: out.join("s2"),
            sheet_index: out.join("sheets.tsv"),
            sheets: out.join("sheets"),
            airbases: out.join("airbases"),
            osm: out.clone(),
            area: [600_000.0, 3_400_000.0, 600_000.0 + 65536.0, 3_400_000.0 + 65536.0],
            detail: [600_000.0, 3_400_000.0, 600_000.0 + 65536.0, 3_400_000.0 + 32768.0],
            threads: 1,
        };
        // A base in the western 8 m unit (its units are marked apart, BASE_FILL).
        std::fs::create_dir_all(&run.airbases).unwrap();
        let ring: Vec<[f64; 2]> = [[610_000.0, 3_410_000.0], [612_000.0, 3_410_000.0], [612_000.0, 3_411_000.0]]
            .iter()
            .map(|p| utm36n_geo(p[0], p[1]))
            .map(|g| [g[1], g[0]])
            .collect();
        std::fs::write(run.airbases.join("x.json"), serde_json::json!({ "boundary": ring }).to_string()).unwrap();
        let geo = crate::sim_bases::theatre_geo(run.area);
        std::fs::create_dir_all(&run.dem_cache).unwrap();
        for lat in geo[1].floor() as i32..=geo[3].floor() as i32 {
            for lon in geo[0].floor() as i32..=geo[2].floor() as i32 {
                let name = crate::imagery_run::dem_tile(lat, lon);
                std::fs::write(run.dem_cache.join(format!("{name}.none")), "").unwrap();
            }
        }
        for (d, dir) in crate::sim_coast::water_extracts(geo) {
            let dir = run.osm.join(dir);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join(d.file), "").unwrap();
            std::fs::write(dir.join(format!("{}.ok", d.file)), d.sha256).unwrap();
        }
        // A sheet ZIP: the extracts count (`colour` reads them for the shore).
        std::fs::create_dir_all(&run.sheets).unwrap();
        std::fs::write(run.sheets.join("a.zip"), "").unwrap();
        let work = run.out.join(".work");
        std::fs::create_dir_all(&work).unwrap();
        let units = s2_units(
            &Frame::new(run.area).unwrap(),
            run.detail,
            &base_outlines(&run.airbases).unwrap(),
            &BTreeSet::new(),
        );
        assert!(units[..3].iter().all(|(_, l)| !l.is_empty()), "the box has units of every kind");
        assert_eq!(would_fetch(&run).unwrap(), ["sentinel-2"], "a new theatre reads Sentinel-2");
        for (what, list) in &units {
            for &u in list {
                std::fs::write(done(&work, what, u), "").unwrap();
            }
        }
        assert!(would_fetch(&run).unwrap().is_empty(), "the border's units not listed yet: from the tiles on disk");
        // The other 8 m unit at the border (BorderTone's list, written by `sentinel`), done.
        let east = units[1].1[0];
        write_border_units(&work, &[east].into(), &BTreeSet::new()).unwrap();
        assert!(would_fetch(&run).unwrap().is_empty(), "the border's unit left: from the tiles on disk");
        std::fs::write(done(&work, S2_8M_BORDER, east), "").unwrap();
        assert!(would_fetch(&run).unwrap().is_empty(), "every unit done, every source here: nothing to fetch");
        // A code change renamed the 8 m mark (2026-11-25, "s2_8m" -> S2_8M): the units built before fetch nothing.
        let (m8, u5) = &units[1];
        for &u in u5 {
            std::fs::rename(done(&work, m8, u), done(&work, "s2_8m", u)).unwrap();
        }
        assert!(would_fetch(&run).unwrap().is_empty(), "a renamed mark, no 10 m tile on disk: nothing to fetch");
        for &u in u5 {
            std::fs::rename(done(&work, "s2_8m", u), done(&work, m8, u)).unwrap();
        }
        // And `colour` itself (without the sheet, no GDAL run) lists no tile: a listing would land in (or fail to
        // reach) the empty `s2_cache`.
        std::fs::remove_file(run.sheets.join("a.zip")).unwrap();
        let f = Frame::new(run.area).unwrap();
        colour(&run, &f, geo, &work, &crate::progress::Stdout, &AtomicBool::new(false)).unwrap();
        assert!(!run.s2_cache.exists(), "colour read no Sentinel-2 tile");
        // The base's 8 m unit left (a theatre made again for its bases' fill): local while the cache holds the 10 m
        // tiles whole.
        let (what, list) = &units[2];
        std::fs::remove_file(done(&work, what, list[0])).unwrap();
        assert_eq!(would_fetch(&run).unwrap(), ["sentinel-2"], "the base's unit left, no listing");
        std::fs::create_dir_all(&run.s2_cache).unwrap();
        for lat in [30, 31] {
            std::fs::write(run.s2_cache.join(format!("listing_N{lat}.tsv")), format!("N{lat}E034\t5\n")).unwrap();
            let tile = format!("ESA_WorldCover_10m_2021_v200_N{lat}E034_S2RGBNIR.tif");
            std::fs::write(run.s2_cache.join(tile), "12345").unwrap();
        }
        assert!(would_fetch(&run).unwrap().is_empty(), "the base's unit left, every tile whole: nothing to fetch");
        std::fs::remove_file(done(&work, S2_8M_BORDER, east)).unwrap();
        std::fs::remove_file(run.s2_cache.join("ESA_WorldCover_10m_2021_v200_N30E034_S2RGBNIR.tif")).unwrap();
        assert_eq!(would_fetch(&run).unwrap(), ["sentinel-2"], "the base's unit left, a tile missing");
        // Every unit done again, a tile's download begun under the 8 m nodes: it is finished (2026-11-24).
        std::fs::write(done(&work, what, list[0]), "").unwrap();
        std::fs::write(done(&work, S2_8M_BORDER, east), "").unwrap();
        assert!(would_fetch(&run).unwrap().is_empty(), "every unit done");
        std::fs::write(run.s2_cache.join("ESA_WorldCover_10m_2021_v200_N30E034_S2RGBNIR.part"), "12").unwrap();
        // Without the Survey sheets nothing finishes it (the stamp's "s2_begun" is the Survey's border fill).
        assert!(would_fetch(&run).unwrap().is_empty(), "a begun tile, no Survey sheets");
        std::fs::create_dir_all(&run.sheets).unwrap();
        std::fs::write(run.sheets.join("x.zip"), "").unwrap();
        assert!(s2_pending(&run), "a begun tile is finished");
        // A lock left with no tile beside it (the download stopped before its first bytes) is a begun tile too.
        let part = run.s2_cache.join("ESA_WorldCover_10m_2021_v200_N30E034_S2RGBNIR.part");
        std::fs::rename(&part, part.with_extension("lock")).unwrap();
        assert!(s2_pending(&run), "a lock without its tile");
        std::fs::write(part.with_extension("tif"), "12345").unwrap();
        assert!(!s2_pending(&run), "a lock beside its whole tile");
        std::fs::remove_dir_all(&out).unwrap();
    }

    /// A base on bumpy ground (3 m bumps a kilometre apart, the DEM's kind): graded, its crossing runways' height has
    /// a second difference over a texel within a real runway's (FAA AC 150/5300-13B: 305 m of vertical curve per 1 %
    /// of grade change, 0.134 m over 64 m; plus the 0.1 m height step) along the centreline and the edges, and across
    /// the width within a 1.5 % crown's; the ground past the shoulder is the DEM's.
    #[test]
    fn grading_smooths_the_runways() {
        let f = Frame::new([600_000.0, 3_500_000.0, 608_192.0, 3_508_192.0]).unwrap();
        let w = 129;
        let dem = |x: f64, y: f64| (50.0 + 0.01 * x + 3.0 * (x / 150.0).sin() * (y / 170.0).cos()) as f32;
        let data = (0..w * w).map(|k| dem(64.0 * (k % w) as f64, 64.0 * (k / w) as f64)).collect();
        let bumpy = HeightGrid { w, h: w, data };
        let ll = |e: f64, n: f64| {
            let g = utm36n_geo(e, n);
            serde_json::json!([g[1], g[0]])
        };
        let end = |d: &str, e: f64, n: f64| {
            let g = utm36n_geo(e, n);
            serde_json::json!({ "designator": d, "lat": g[1], "lon": g[0] })
        };
        let g = utm36n_geo(604_200.0, 3_504_600.0);
        let v = serde_json::json!({
            "icao": "LLRD", "elevation_m": 50.0, "reference": ll(604_096.0, 3_504_096.0),
            "runways": [
                { "width_m": 45.0, "ends": [end("09", 602_596.0, 3_504_096.0), end("27", 605_596.0, 3_504_096.0)] },
                { "width_m": 45.0, "ends": [end("15", 603_300.0, 3_505_300.0), end("33", 604_900.0, 3_502_700.0)] },
            ],
            "taxiways": [{ "points": [ll(602_800.0, 3_504_400.0), ll(605_400.0, 3_504_400.0)], "width_m": 23.0 }],
            "aprons": [{ "polygon": [ll(604_000.0, 3_504_500.0), ll(604_400.0, 3_504_500.0),
                ll(604_400.0, 3_504_700.0), ll(604_000.0, 3_504_700.0)] }],
            "parking": [{ "unit": "x", "lat": g[1], "lon": g[0], "heading": 180.0 }],
        });
        let b = crate::sim_bases::base(&v, "test").unwrap();
        let mut graded = HeightGrid { w, h: w, data: bumpy.data.clone() };
        let rect = grade_base(&mut graded, &f, &b).unwrap();
        assert!(rect[0] > 600_000.0 && rect[3] < 3_508_192.0, "{rect:?}: the base's window");
        // The height as the flight reads it: the texel's two triangles (iaf_avionics::heights).
        let at = |g: &HeightGrid, p: [f64; 2]| {
            let (tx, ty) = ((p[0] - f.e0) / DEM_STEP, (f.n1 - p[1]) / DEM_STEP);
            let (x0, y0) = (tx.floor() as usize, ty.floor() as usize);
            let (fx, fy) = (tx - x0 as f64, ty - y0 as f64);
            let z = |x: usize, y: usize| f64::from(g.data[y * g.w + x]);
            let (a, b, c, d) = (z(x0, y0), z(x0 + 1, y0), z(x0, y0 + 1), z(x0 + 1, y0 + 1));
            if fx >= fy { a + (b - a) * fx + (d - b) * fy } else { a + (d - c) * fx + (c - a) * fy }
        };
        // The worst second difference along (over 64 m, every 4 m) and across (edge, centre, edge).
        let worst = |g: &HeightGrid| {
            let mut out = [0.0f64; 2];
            for r in &b.runways {
                let (u, half) = (r.dir(0), r.width / 2.0);
                let p = |m: f64, x: f64| at(g, [r.at(0, m)[0] - u[1] * x, r.at(0, m)[1] + u[0] * x]);
                for m in (16..(r.length() / 4.0) as usize - 16).map(|k| 4.0 * k as f64) {
                    for x in [-half, 0.0, half] {
                        out[0] = out[0].max((p(m - 64.0, x) - 2.0 * p(m, x) + p(m + 64.0, x)).abs());
                    }
                    out[1] = out[1].max((p(m, -half) - 2.0 * p(m, 0.0) + p(m, half)).abs() / r.width);
                }
            }
            out
        };
        let (before, after) = (worst(&bumpy), worst(&graded));
        assert!(before[0] > 0.24, "the test's ground is bumpy: {before:?}");
        assert!(after[0] < 0.24 && after[1] < 0.015, "graded: {after:?} (before {before:?})");
        for k in [0, w - 1, w * w - 1] {
            assert_eq!(graded.data[k], bumpy.data[k], "the DEM past the shoulder");
        }
    }

    /// The tile writer on a box of two level-6 nodes: the height nodes' edges match, the raw encoding, the parents
    /// up to the root and meta.json.
    #[test]
    fn writes_a_two_node_theatre() {
        let out = tmp("writer");
        let area = [500_000.0, 3_400_000.0, 500_000.0 + 2.0 * 65536.0, 3_400_000.0 + 65536.0];
        let f = Frame::new(area).unwrap();
        for l in 0..=ROOT_LEVEL {
            std::fs::create_dir_all(out.join(format!("L{l}"))).unwrap();
        }
        // A ramp: 1 m per grid step east, −100 m in the first row.
        let (w, h) = (2049, 1025);
        let data = (0..w * h).map(|k| if k < w { -100.0 } else { (k % w) as f32 }).collect();
        let g = HeightGrid { w, h, data };
        write_heights(&f, &g, &out, None, 2, &AtomicBool::new(false)).unwrap();
        let px = |p: &str, x: u32, y: u32| {
            let v = image::open(out.join(p)).unwrap().to_rgb8().get_pixel(x, y).0;
            u16::from(v[0]) << 8 | u16::from(v[1])
        };
        assert_eq!(px("L6/h_0_0.png", 0, 0), 4000, "−100 m");
        assert_eq!(px("L6/h_0_0.png", 7, 3), 5070, "7 m");
        for y in [1, 500, 1024] {
            assert_eq!(px("L6/h_0_0.png", 1024, y), px("L6/h_1_0.png", 0, y), "shared edge");
        }
        assert_eq!(px("L6/h_1_0.png", 1024, 9), 5000 + 20480, "east edge repeats the last column");
        assert_eq!(px("L7/h_0_0.png", 3, 2), 5060, "level 7 = every other grid point");
        assert!(out.join("L11/h_0_0.png").exists() && !out.join("L6/h_0_1.png").exists());
        // Colour: the level-5 nodes, then the parents.
        for k in f.nodes(5) {
            save(
                &RgbImage::from_pixel(NODE_PIXELS, NODE_PIXELS, image::Rgb([10 * k.1 as u8, 0, 0])),
                &colour_path(&out, k),
            )
            .unwrap();
        }
        for l in 6..=ROOT_LEVEL {
            parents(&out, l, None, 2, &AtomicBool::new(false)).unwrap();
        }
        write_meta(&f, &out, serde_json::json!({ "box": area })).unwrap();
        let meta: serde_json::Value = serde_json::from_slice(&std::fs::read(out.join("meta.json")).unwrap()).unwrap();
        assert_eq!(meta["theatre"], serde_json::json!([0, 0, 131072, 65536]));
        assert_eq!(meta["nodes"]["5"].as_array().unwrap().len(), 8);
        assert_eq!(meta["nodes"]["6"], serde_json::json!([[0, 0], [1, 0]]));
        assert_eq!(meta["nodes"]["11"], serde_json::json!([[0, 0]]));
        assert_eq!((meta["x_shift"].as_f64(), meta["y_shift"].as_f64()), (Some(500_000.0), Some(3_465_536.0)));
        assert_eq!(meta["units_to_metres"], 1.0);
        // The parent's west half is the level-5 node (5, 2, *)'s red (20), its east half (5, 3, *)'s (30).
        let c = image::open(colour_path(&out, (6, 1, 0))).unwrap().to_rgb8();
        assert!((i32::from(c.get_pixel(100, 500).0[0]) - 20).abs() <= 3);
        std::fs::remove_dir_all(&out).unwrap();
    }

    /// The DEM reader: a synthetic lon / lat raster (an ASCII grid, 0.001° cells) warped to the height grid.
    #[test]
    fn reads_a_dem_into_the_grid() {
        if std::process::Command::new("gdalwarp").arg("--version").output().is_err() {
            eprintln!("skipped: GDAL not installed");
            return;
        }
        let dir = tmp("dem");
        // 34.6–34.8° E, 30.7–30.9° N, heights = 1000 + 1000 · (lon − 34.6), nodata (sea) in the north-west cell.
        let mut asc =
            String::from("ncols 200\nnrows 200\nxllcorner 34.6\nyllcorner 30.7\ncellsize 0.001\nNODATA_value -9999\n");
        for row in 0..200 {
            for col in 0..200 {
                let v = if row == 0 && col == 0 { -9999.0 } else { 1000.0 + f64::from(col) + 0.5 };
                asc += &format!("{v} ");
            }
            asc += "\n";
        }
        std::fs::write(dir.join("dem.asc"), asc).unwrap();
        std::fs::write(dir.join("dem.prj"), "GEOGCS[\"WGS 84\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\",6378137,298.257223563]],PRIMEM[\"Greenwich\",0],UNIT[\"degree\",0.0174532925199433]]").unwrap();
        // 10 km around Ramon (34.666° E: 659,428 E, 3,405,964 N).
        let area = [654_336.0, 3_400_960.0, 664_576.0, 3_411_200.0];
        let g = dem_grid(&[dir.join("dem.asc")], area, &dir).unwrap();
        assert_eq!((g.w, g.h), (161, 161));
        let lon = |e: f64, n: f64| utm36n_geo(e, n)[0];
        for (x, y) in [(0, 0), (80, 80), (160, 10)] {
            let (e, n) = (area[0] + 64.0 * x as f64, area[3] - 64.0 * y as f64);
            let want = 1000.0 + (lon(e, n) - 34.6) * 1000.0;
            let got = f64::from(g.data[y * g.w + x]);
            assert!((got - want).abs() < 1.0, "({x}, {y}): {got} vs {want}");
        }
        std::fs::remove_dir_all(&dir).unwrap();
    }

    fn sheet(name: &str, bbox: [f64; 4]) -> Sheet {
        Sheet { name: name.into(), gdal: String::new(), bbox, levels: [0.0; 4] }
    }

    /// A sheet beyond the pad is left out; one that crosses the padded box's edge is kept.
    #[test]
    fn sheets_near_the_box() {
        let b = [100_000.0, 500_000.0, 110_000.0, 510_000.0];
        let all = [
            sheet("far.zip/a.tif", [113_000.0, 500_000.0, 120_000.0, 510_000.0]),
            sheet("edge.zip/b.tif", [111_000.0, 505_000.0, 121_000.0, 515_000.0]),
            sheet("in.zip/c.tif", [101_000.0, 501_000.0, 102_000.0, 502_000.0]),
        ];
        let names = |v: Vec<Sheet>| v.into_iter().map(|s| s.name).collect::<Vec<_>>();
        assert_eq!(names(near(&all, &[b], 2000.0)), ["edge.zip/b.tif", "in.zip/c.tif"]);
        assert_eq!(names(near(&all, &[b], 0.0)), ["in.zip/c.tif"]);
    }

    /// The VRT's stamp is the same for the same sheets and options, and changes with a ZIP's size or time, a sheet
    /// added or removed, another path for the same sheet name, or other options.
    #[test]
    fn vrt_stamp_tracks_the_zips() {
        let dir = tmp("vrt-stamp");
        let t = std::time::UNIX_EPOCH + std::time::Duration::from_secs(1_700_000_000);
        let touch = |name: &str, bytes: &[u8], t: std::time::SystemTime| {
            std::fs::write(dir.join(name), bytes).unwrap();
            std::fs::File::options().write(true).open(dir.join(name)).unwrap().set_modified(t).unwrap();
        };
        touch("a.zip", b"1234", t);
        touch("b.zip", b"5678", t);
        let at = |name: &str, root: &str| Sheet { gdal: format!("/vsizip/{root}/{name}"), ..sheet(name, [0.0; 4]) };
        let (a, b) = (at("a.zip/a.tif", "/x"), at("b.zip/b.tif", "/x"));
        let opts = ["-q", "-b", "1"];
        let stamp = |s: &[Sheet]| vrt_stamp(&opts, s, &dir).unwrap();
        let s0 = stamp(std::slice::from_ref(&a));
        assert_eq!(stamp(std::slice::from_ref(&a)), s0, "unchanged: reused");
        assert_ne!(stamp(&[a.clone(), b.clone()]), s0, "a sheet added");
        assert_ne!(stamp(&[a.clone(), b.clone()]), stamp(std::slice::from_ref(&b)), "a sheet removed");
        assert_ne!(stamp(&[at("a.zip/a.tif", "/moved")]), s0, "the same sheet at another path");
        assert_ne!(vrt_stamp(&["-q"], std::slice::from_ref(&a), &dir).unwrap(), s0, "other options");
        touch("a.zip", b"1234", t + std::time::Duration::from_secs(60));
        assert_ne!(stamp(std::slice::from_ref(&a)), s0, "a new modification time");
        touch("a.zip", b"12345", t);
        assert_ne!(stamp(&[a]), s0, "a new size");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn sheet_balance_lifts_the_dark_sheet() {
        // 3 × 3 sheets of 40² cells, the centre one 30 % darker; and a lone sheet with no neighbour.
        let (w, h) = (120, 120);
        let own: Vec<Option<usize>> = (0..w * h).map(|i| Some((i / w) / 40 * 3 + (i % w) / 40)).collect();
        let lg: Vec<[f32; 3]> = own.iter().map(|k| [if *k == Some(4) { 70f32.ln() } else { 100f32.ln() }; 3]).collect();
        let borders = border_diffs(&own, &lg, w, h);
        assert_eq!(borders.len(), 12, "the 3 × 3 grid's inner borders");
        let g = balance(10, &borders);
        let lift = (g[4][1] - g[0][1]).exp();
        assert!((lift - 1.0 / 0.7).abs() < 0.01, "the centre brought to its neighbours: × {lift}");
        for k in [0, 1, 2, 3, 5, 6, 7, 8] {
            assert!((g[k][0] - g[0][0]).abs() < 1e-3, "sheet {k} as the others");
        }
        assert!(g.iter().map(|g| g[2]).sum::<f32>().abs() < 1e-3, "held to 1 on average");
        assert_eq!(g[9], [0.0; 3], "no neighbour, no gain");
        assert_eq!(balance(2, &[]), vec![[0.0; 3]; 2]);
    }

    #[test]
    fn the_8m_marks_follow_the_sheet_tone() {
        // The Survey's marks are made from SHEET_TONE; the 8 m units' must change with them (their level-3 nodes are
        // the Survey units' base).
        for m in [S2_8M, S2_8M_BASE, S2_8M_BORDER] {
            assert!(m.ends_with(&format!("_{SHEET_TONE}")), "{m}");
        }
        assert!(S2_8M_BORDER.contains(BORDER_FILL) && S2_8M_BASE.contains(BASE_FILL));
    }
}
