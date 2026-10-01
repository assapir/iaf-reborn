//! Automatic control points for the georeference (docs/georef.md §2): the original level-7 / 6
//! mosaics (159 / 79 m per pixel) are matched against a real-world reference mosaic (EOxCloudless
//! 2017, WGS84 tile matrix level 9 / 10, 150 / 76 m per pixel) by normalised cross-correlation of high-passed
//! luminance patches on a regular grid, coarse to fine; between passes a smoothed thin-plate
//! spline is fitted and outliers are dropped. Run once by a developer (`iaf-terrain georef-points`);
//! its output, coordinates only, is `data/georef_points.json`.

use std::path::Path;

use anyhow::{Context, Result};

use crate::georef::{Georef, Point};

/// Patch half size (pixels of the original level): 64² px.
const HALF: i32 = 32;

/// An original level and the reference mosaic at about the same resolution.
pub struct Pair {
    pub orig: Gray,
    pub refg: Gray,
    /// Original level (2^level terrain units per pixel).
    pub level: u32,
    /// Reference WGS84 tile matrix level (2 × 1 tiles of 256 px at level 0) and the tile row /
    /// column of the mosaic's top-left corner.
    pub zoom: u32,
    /// Second-peak test: the best score this far (pixels) from the peak must be clearly lower
    /// (the correlation peak is about as wide as the high-pass radius).
    pub excl: i32,
    pub r0: u32,
    pub c0: u32,
}

impl Pair {
    /// `hp`: high-pass radius in original pixels (texture for the fine levels; a wide one keeps
    /// the land / sea contrast that the coarse, painted areas still share with the real world).
    pub fn load(theatre: &Path, level: u32, tiles: &Path, zoom: u32, hp: f64) -> Result<Self> {
        let mut orig = load_original(theatre, level)?;
        let (mut refg, r0, c0) = load_reference(tiles)?;
        orig.high_pass(hp as i32);
        // The same ground radius in reference pixels.
        let ref_m = 180.0 / ((1u64 << zoom) as f64 * 256.0) * 111_000.0;
        refg.high_pass((hp * (1u32 << level) as f64 * crate::georef::UNITS_TO_METRES / ref_m).round() as i32);
        Ok(Self { orig, refg, level, zoom, excl: ((hp / 3.0) as i32).max(2), r0, c0 })
    }
    fn upp(&self) -> f64 {
        (1u32 << self.level) as f64
    }
    /// Degrees per reference pixel.
    fn deg(&self) -> f64 {
        180.0 / ((1u64 << self.zoom) as f64 * 256.0)
    }
}

pub struct Gray {
    pub w: usize,
    pub h: usize,
    pub px: Vec<f32>,
}

impl Gray {
    fn at(&self, x: f64, y: f64) -> f32 {
        // Bilinear, clamped.
        let x = x.clamp(0.0, (self.w - 1) as f64 - 1e-6);
        let y = y.clamp(0.0, (self.h - 1) as f64 - 1e-6);
        let (x0, y0) = (x as usize, y as usize);
        let (fx, fy) = ((x - x0 as f64) as f32, (y - y0 as f64) as f32);
        let i = y0 * self.w + x0;
        let (a, b, c, d) = (self.px[i], self.px[i + 1], self.px[i + self.w], self.px[i + self.w + 1]);
        a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }

    /// x − box mean (radius r): keeps edges and texture, drops the colour / brightness differences
    /// between the 1998 photos and the 2017 mosaic.
    fn high_pass(&mut self, r: i32) {
        let (w, h) = (self.w, self.h);
        let mut sat = vec![0f64; (w + 1) * (h + 1)];
        for y in 0..h {
            let mut row = 0f64;
            for x in 0..w {
                row += self.px[y * w + x] as f64;
                sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row;
            }
        }
        let mut out = vec![0f32; w * h];
        for y in 0..h as i32 {
            for x in 0..w as i32 {
                let (x0, y0) = ((x - r).max(0) as usize, (y - r).max(0) as usize);
                let (x1, y1) = ((x + r + 1).min(w as i32) as usize, (y + r + 1).min(h as i32) as usize);
                let s = sat[y1 * (w + 1) + x1] - sat[y0 * (w + 1) + x1] - sat[y1 * (w + 1) + x0] + sat[y0 * (w + 1) + x0];
                let mean = s / ((x1 - x0) * (y1 - y0)) as f64;
                out[y as usize * w + x as usize] = self.px[y as usize * w + x as usize] - mean as f32;
            }
        }
        self.px = out;
    }
}

fn luma(p: &image::Rgb<u8>) -> f32 {
    0.299 * p[0] as f32 + 0.587 * p[1] as f32 + 0.114 * p[2] as f32
}

/// The original nodes of one theatre level as one grey mosaic.
pub fn load_original(theatre: &Path, level: u32) -> Result<Gray> {
    let lv = level;
    let meta: serde_json::Value = serde_json::from_slice(&std::fs::read(theatre.join("meta.json"))?)?;
    let t = &meta["theatre"];
    let np = meta["node_pixels"].as_u64().context("node_pixels")? as usize;
    let w = (t[2].as_u64().context("theatre")? >> lv) as usize;
    let h = (t[3].as_u64().context("theatre")? >> lv) as usize;
    let mut g = Gray { w, h, px: vec![0.0; w * h] };
    for ij in meta["nodes"][lv.to_string()].as_array().context("level nodes")? {
        let (i, j) = (ij[0].as_u64().unwrap() as usize, ij[1].as_u64().unwrap() as usize);
        let img = image::open(theatre.join(format!("L{lv}/c_{i}_{j}.jpg")))?.to_rgb8();
        for (x, y, p) in img.enumerate_pixels() {
            let (gx, gy) = (i * np + x as usize, j * np + y as usize);
            if gx < w && gy < h {
                g.px[gy * w + gx] = luma(p);
            }
        }
    }
    Ok(g)
}

/// The reference tiles `<dir>/<row>_<col>.jpg` (WGS84 matrix level 9) as one grey mosaic; returns
/// it with the tile row / column of its top-left corner.
pub fn load_reference(dir: &Path) -> Result<(Gray, u32, u32)> {
    let mut tiles = Vec::new();
    for e in std::fs::read_dir(dir)? {
        let p = e?.path();
        let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        if let Some((r, c)) = stem.split_once('_') {
            tiles.push((r.parse::<u32>()?, c.parse::<u32>()?, p));
        }
    }
    let r0 = tiles.iter().map(|t| t.0).min().context("no reference tiles")?;
    let c0 = tiles.iter().map(|t| t.1).min().unwrap();
    let w = ((tiles.iter().map(|t| t.1).max().unwrap() - c0 + 1) * 256) as usize;
    let h = ((tiles.iter().map(|t| t.0).max().unwrap() - r0 + 1) * 256) as usize;
    let mut g = Gray { w, h, px: vec![0.0; w * h] };
    for (r, c, p) in tiles {
        let Ok(img) = image::open(&p) else { continue };
        let img = img.to_rgb8();
        for (x, y, px) in img.enumerate_pixels() {
            let (gx, gy) = (((c - c0) * 256 + x) as usize, ((r - r0) * 256 + y) as usize);
            g.px[gy * w + gx] = luma(px);
        }
    }
    Ok((g, r0, c0))
}

pub struct Match {
    pub game: [f64; 2],
    pub geo: [f64; 2],
    pub ncc: f64,
    /// Original level it was measured on.
    pub level: u32,
}

/// Correlates the original patch centred on terrain point `c` with the reference resampled into
/// the original's pixel grid through `warp`, over shifts of ±`margin` pixels. Returns the
/// control point (c ↔ where the reference shows the same ground) when the peak is clear.
fn match_cell(pair: &Pair, warp: &Georef, c: [f64; 2], margin: i32) -> Option<Match> {
    let (orig, refg, r0, c0) = (&pair.orig, &pair.refg, pair.r0, pair.c0);
    let upp = pair.upp();
    let s = (2 * HALF) as usize;
    let (ox, oy) = (c[0] / upp - HALF as f64, c[1] / upp - HALF as f64);
    if ox < 0.0 || oy < 0.0 || ox + s as f64 >= orig.w as f64 || oy + s as f64 >= orig.h as f64 {
        return None;
    }
    // Original patch, zero mean, unit norm.
    let mut o = vec![0f32; s * s];
    for y in 0..s {
        for x in 0..s {
            o[y * s + x] = orig.px[(oy as usize + y) * orig.w + ox as usize + x];
        }
    }
    let mean = o.iter().sum::<f32>() / o.len() as f32;
    o.iter_mut().for_each(|v| *v -= mean);
    let norm = o.iter().map(|v| v * v).sum::<f32>().sqrt();
    if norm / (s as f32) < 2.0 {
        return None; // featureless (sea, flat sand)
    }
    o.iter_mut().for_each(|v| *v /= norm);
    // Reference window in original pixel units around c, through the local affine of the warp.
    let d = pair.deg();
    let g0 = warp.to_geo(c[0], c[1]);
    let span = 4096.0;
    let gx = warp.to_geo(c[0] + span, c[1]);
    let gy = warp.to_geo(c[0], c[1] + span);
    let to_ref = |px: f64, py: f64| {
        // px, py: offsets from c in original pixels.
        let (ux, uy) = (px * upp / span, py * upp / span);
        let lon = g0[0] + (gx[0] - g0[0]) * ux + (gy[0] - g0[0]) * uy;
        let lat = g0[1] + (gx[1] - g0[1]) * ux + (gy[1] - g0[1]) * uy;
        ((lon + 180.0) / d - (c0 * 256) as f64 - 0.5, (90.0 - lat) / d - (r0 * 256) as f64 - 0.5)
    };
    let rs = s + 2 * margin as usize;
    let mut rw = vec![0f32; rs * rs];
    for y in 0..rs {
        for x in 0..rs {
            let (u, v) = to_ref(x as f64 - (HALF + margin) as f64, y as f64 - (HALF + margin) as f64);
            if u < 0.0 || v < 0.0 || u >= (refg.w - 1) as f64 || v >= (refg.h - 1) as f64 {
                return None;
            }
            rw[y * rs + x] = refg.at(u, v);
        }
    }
    let n = (2 * margin + 1) as usize;
    let mut score = vec![-1f32; n * n];
    for dy in 0..n {
        for dx in 0..n {
            let (mut so, mut sr, mut srr) = (0f32, 0f32, 0f32);
            for y in 0..s {
                let row = &rw[(dy + y) * rs + dx..(dy + y) * rs + dx + s];
                let orow = &o[y * s..(y + 1) * s];
                for x in 0..s {
                    so += orow[x] * row[x];
                    sr += row[x];
                    srr += row[x] * row[x];
                }
            }
            let var = srr - sr * sr / (s * s) as f32;
            if var > 1e-3 {
                score[dy * n + dx] = so / var.sqrt();
            }
        }
    }
    let (best, &peak) = score.iter().enumerate().max_by(|a, b| a.1.total_cmp(b.1))?;
    let (bx, by) = ((best % n) as i32, (best / n) as i32);
    if peak < 0.35 || bx == 0 || by == 0 || bx == n as i32 - 1 || by == n as i32 - 1 {
        return None;
    }
    // Distinct: the best score away from the peak must be clearly lower.
    let mut second = -1f32;
    for (k, &v) in score.iter().enumerate() {
        let (x, y) = ((k % n) as i32, (k / n) as i32);
        if (x - bx).abs() > pair.excl || (y - by).abs() > pair.excl {
            second = second.max(v);
        }
    }
    if peak - second < 0.08 {
        return None;
    }
    let sub = |m: f32, z: f32, p: f32| {
        let den = m - 2.0 * z + p;
        if den.abs() < 1e-6 { 0.0 } else { (0.5 * (m - p) / den).clamp(-0.5, 0.5) as f64 }
    };
    let at = |x: i32, y: i32| score[y as usize * n + x as usize];
    let fx = bx as f64 - margin as f64 + sub(at(bx - 1, by), peak, at(bx + 1, by));
    let fy = by as f64 - margin as f64 + sub(at(bx, by - 1), peak, at(bx, by + 1));
    // The ground at original c shows up in the reference at c + (fx, fy) pixels.
    let (u, v) = to_ref(fx, fy);
    let geo = [(u + 0.5 + (c0 * 256) as f64) * d - 180.0, 90.0 - (v + 0.5 + (r0 * 256) as f64) * d];
    Some(Match { game: c, geo, ncc: peak as f64, level: pair.level })
}

/// One pass over a grid with spacing `step` (terrain units), shifts ±`margin` pixels.
pub fn pass(pair: &Pair, warp: &Georef, step: f64, margin: i32, threads: usize) -> Vec<Match> {
    let mut cells = Vec::new();
    let (w, h) = (pair.orig.w as f64 * pair.upp(), pair.orig.h as f64 * pair.upp());
    let mut y = step / 2.0;
    while y < h {
        let mut x = step / 2.0;
        while x < w {
            cells.push([x, y]);
            x += step;
        }
        y += step;
    }
    let next = std::sync::atomic::AtomicUsize::new(0);
    let out = std::sync::Mutex::new(Vec::new());
    std::thread::scope(|s| {
        for _ in 0..threads.max(1) {
            s.spawn(|| {
                loop {
                    let k = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    let Some(&c) = cells.get(k) else { return };
                    if let Some(m) = match_cell(pair, warp, c, margin) {
                        out.lock().unwrap().push(m);
                    }
                }
            });
        }
    });
    let mut v = out.into_inner().unwrap();
    v.sort_by(|a, b| (a.game[1], a.game[0]).partial_cmp(&(b.game[1], b.game[0])).unwrap());
    v
}

pub fn to_points(ms: &[Match]) -> Vec<Point> {
    ms.iter()
        .map(|m| Point {
            id: format!("a{:.0}_{:.0}", m.game[0] / 1024.0, m.game[1] / 1024.0),
            kind: "auto".into(),
            game: m.game,
            geo: m.geo,
        })
        .collect()
}

/// Fits with smoothing `lambda`, drops points whose residual exceeds `k` × the median (at least
/// `floor_m` metres, × 4 for the level-8 matches: they are less precise) and refits until none
/// is dropped. Returns the fit and the kept matches.
pub fn robust_fit(mut ms: Vec<Match>, extra: &[Point], lambda: f64, k: f64, floor_m: f64) -> Result<(Georef, Vec<Match>)> {
    loop {
        let mut pts = to_points(&ms);
        pts.extend_from_slice(extra);
        let g = Georef::fit(pts, lambda)?;
        let r = g.residuals_m();
        let mut sorted = r[..ms.len()].to_vec();
        sorted.sort_by(f64::total_cmp);
        let med = sorted[sorted.len() / 2];
        let lim = |m: &Match| (k * med).max(floor_m) * if m.level >= 8 { 4.0 } else { 1.0 };
        let before = ms.len();
        let mut i = 0;
        ms.retain(|m| {
            i += 1;
            r[i - 1] <= lim(m)
        });
        if ms.len() == before {
            return Ok((g, ms));
        }
    }
}

/// Bilinear initial guess from the theatre corners (docs/imagery-research.md §1 first cut).
pub fn initial() -> Result<Georef> {
    let c = |id: &str, tx: f64, ty: f64, lon: f64, lat: f64| Point { id: id.into(), kind: "init".into(), game: [tx, ty], geo: [lon, lat] };
    Georef::fit(
        vec![
            c("nw", 0.0, 0.0, 29.77, 36.62),
            c("ne", 655360.0, 0.0, 38.24, 36.70),
            c("sw", 0.0, 851968.0, 29.79, 27.01),
            c("se", 655360.0, 851968.0, 38.26, 27.09),
        ],
        0.0,
    )
}
