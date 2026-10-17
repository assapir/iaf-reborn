//! The game's airbases as data (docs/imagery.md §3, docs/rendering.md §7): the base footprint the imagery
//! layers leave to the 1998 inset (runways, taxiways, aprons, shelters and the painted area around them, plus a
//! margin), from terraintype.dat's runway leaves, iaf.ibx's base points, the missions' units and the 1998 inset's
//! paved pixels.

use std::f64::consts::PI;
use std::path::Path;

use anyhow::{Context, Result};
use iaf_formats::ini::Ini;
use iaf_formats::terrain_types::{RUNWAY, TerrainTypes};

use crate::georef::UNITS_TO_METRES;
use crate::imagery::{Cache, KEEP_INSET_LEVEL, Theatre};

/// Engine metres (X east, Y north) → terrain units (x east, y south).
pub fn units(x: f64, y: f64) -> [f64; 2] {
    [(x + 166850.0) / UNITS_TO_METRES, (1043780.0 - y) / UNITS_TO_METRES]
}

/// The footprint raster's level: its cells are that level's pixels (4 units, ≈ 5 m).
const LEVEL: u32 = 2;
const CELL_M: f64 = (1 << LEVEL) as f64 * UNITS_TO_METRES;
/// Paved pixels count only this close to the seeds (runway leaves, base points): fields that look grey elsewhere in
/// the inset do not grow the base.
const GROW_M: f64 = 400.0;
/// Narrower paved strips (roads) are dropped before growing, so a road does not lead the base into the country.
const ROAD_M: f64 = 12.0;
/// Base points (iaf.ibx: tower, lineup, taxi, hangar points) and the missions' units near the base: discs of this
/// radius; units count within UNIT_NEAR_M of the paved base or of a unit already counted (two rounds: the base's
/// building clusters).
const POINT_M: f64 = 40.0;
const UNIT_M: f64 = 80.0;
const UNIT_NEAR_M: f64 = 700.0;
/// Gaps between the parts are closed over this radius; then the footprint grows by the margin.
const CLOSE_M: f64 = 150.0;
pub const MARGIN_M: f64 = 150.0;

/// A boolean raster on terrain units: cell (i, j) covers [x0 + i·cell, +cell) × [y0 + j·cell, +cell).
#[derive(Clone)]
pub struct Grid {
    pub x0: f64,
    pub y0: f64,
    pub cell: f64,
    pub w: usize,
    pub h: usize,
    pub v: Vec<bool>,
}

impl Grid {
    fn new(x0: f64, y0: f64, cell: f64, w: usize, h: usize) -> Self {
        Self { x0, y0, cell, w, h, v: vec![false; w * h] }
    }

    /// The cell at terrain units (tx, ty); false outside.
    pub fn at(&self, tx: f64, ty: f64) -> bool {
        let (i, j) = (((tx - self.x0) / self.cell).floor(), ((ty - self.y0) / self.cell).floor());
        i >= 0.0 && j >= 0.0 && (i as usize) < self.w && (j as usize) < self.h && self.v[j as usize * self.w + i as usize]
    }

    pub fn area_km2(&self) -> f64 {
        self.v.iter().filter(|&&b| b).count() as f64 * (self.cell * UNITS_TO_METRES).powi(2) / 1e6
    }

    /// Cell centre in terrain units.
    fn centre(&self, i: usize) -> [f64; 2] {
        [self.x0 + ((i % self.w) as f64 + 0.5) * self.cell, self.y0 + ((i / self.w) as f64 + 0.5) * self.cell]
    }

    fn disc(&mut self, t: [f64; 2], r_units: f64) {
        let r = (r_units / self.cell).ceil() as i64;
        let (ci, cj) = (((t[0] - self.x0) / self.cell) as i64, ((t[1] - self.y0) / self.cell) as i64);
        for j in (cj - r).max(0)..=(cj + r).min(self.h as i64 - 1) {
            for i in (ci - r).max(0)..=(ci + r).min(self.w as i64 - 1) {
                if ((i - ci).pow(2) + (j - cj).pow(2)) as f64 <= (r * r) as f64 {
                    self.v[j as usize * self.w + i as usize] = true;
                }
            }
        }
    }

    /// Fills a convex polygon (terrain units).
    fn polygon(&mut self, poly: &[[f64; 2]]) {
        let (mut lo, mut hi) = ([f64::MAX; 2], [f64::MIN; 2]);
        for p in poly {
            for c in 0..2 {
                lo[c] = lo[c].min(p[c]);
                hi[c] = hi[c].max(p[c]);
            }
        }
        let cl = |v: f64, n: usize| v.clamp(0.0, n as f64) as usize;
        let (i0, i1) = (cl(((lo[0] - self.x0) / self.cell).floor(), self.w), cl(((hi[0] - self.x0) / self.cell).ceil(), self.w));
        let (j0, j1) = (cl(((lo[1] - self.y0) / self.cell).floor(), self.h), cl(((hi[1] - self.y0) / self.cell).ceil(), self.h));
        for j in j0..j1 {
            for i in i0..i1 {
                let c = self.centre(j * self.w + i);
                if inside_convex(poly, c) {
                    self.v[j * self.w + i] = true;
                }
            }
        }
    }

    /// Square box sums (radius r cells) of the mask.
    fn box_count(&self, r: usize) -> Vec<u32> {
        let (w, h) = (self.w, self.h);
        let mut sat = vec![0u32; (w + 1) * (h + 1)];
        for j in 0..h {
            let mut row = 0u32;
            for i in 0..w {
                row += self.v[j * w + i] as u32;
                sat[(j + 1) * (w + 1) + i + 1] = sat[j * (w + 1) + i + 1] + row;
            }
        }
        (0..w * h)
            .map(|k| {
                let (i, j) = (k % w, k / w);
                let (a, b) = (i.saturating_sub(r), j.saturating_sub(r));
                let (c, d) = ((i + r + 1).min(w), (j + r + 1).min(h));
                sat[d * (w + 1) + c] + sat[b * (w + 1) + a] - sat[b * (w + 1) + c] - sat[d * (w + 1) + a]
            })
            .collect()
    }

    /// Morphological dilation by a (2r+1)² square.
    fn dilate(&self, r: usize) -> Self {
        let n = self.box_count(r);
        Self { v: n.iter().map(|&c| c > 0).collect(), ..self.clone() }
    }

    /// Morphological erosion by a (2r+1)² square (cells beyond the edge count as set).
    fn erode(&self, r: usize) -> Self {
        let n = self.box_count(r);
        let (w, h) = (self.w, self.h);
        let v = (0..w * h)
            .map(|k| {
                let (i, j) = (k % w, k / w);
                let full = ((i + r + 1).min(w) - i.saturating_sub(r)) * ((j + r + 1).min(h) - j.saturating_sub(r));
                n[k] as usize == full
            })
            .collect();
        Self { v, ..self.clone() }
    }

    fn or(&mut self, o: &Grid) {
        self.v.iter_mut().zip(&o.v).for_each(|(a, b)| *a |= b);
    }

    /// Sets the holes: unset cells not connected (4-neighbours) to the grid's border.
    fn fill_holes(&mut self) {
        let (w, h) = (self.w, self.h);
        let mut outside = vec![false; w * h];
        let mut stack: Vec<usize> = (0..w * h).filter(|&k| (k % w == 0 || k % w == w - 1 || k / w == 0 || k / w == h - 1) && !self.v[k]).collect();
        for &k in &stack {
            outside[k] = true;
        }
        while let Some(k) = stack.pop() {
            let (i, j) = (k % w, k / w);
            for (di, dj) in [(-1i64, 0i64), (1, 0), (0, -1), (0, 1)] {
                let (a, b) = (i as i64 + di, j as i64 + dj);
                if a >= 0 && b >= 0 && (a as usize) < w && (b as usize) < h {
                    let n = b as usize * w + a as usize;
                    if !self.v[n] && !outside[n] {
                        outside[n] = true;
                        stack.push(n);
                    }
                }
            }
        }
        self.v = outside.iter().map(|&o| !o).collect();
    }

    /// The cells of `allowed` reached from `seeds` through `allowed` within `max` cells (8-neighbour steps).
    fn grow(seeds: &Grid, allowed: &Grid, max: usize) -> Self {
        let (w, h) = (seeds.w, seeds.h);
        let mut dist: Vec<u32> = seeds.v.iter().map(|&s| if s { 0 } else { u32::MAX }).collect();
        let mut q: std::collections::VecDeque<usize> = (0..w * h).filter(|&k| seeds.v[k]).collect();
        while let Some(k) = q.pop_front() {
            if dist[k] as usize >= max {
                continue;
            }
            let (i, j) = (k % w, k / w);
            for dj in -1i64..=1 {
                for di in -1i64..=1 {
                    let (a, b) = (i as i64 + di, j as i64 + dj);
                    if a >= 0 && b >= 0 && (a as usize) < w && (b as usize) < h {
                        let n = b as usize * w + a as usize;
                        if allowed.v[n] && dist[n] == u32::MAX {
                            dist[n] = dist[k] + 1;
                            q.push_back(n);
                        }
                    }
                }
            }
        }
        Self { v: dist.iter().map(|&d| d != u32::MAX).collect(), ..seeds.clone() }
    }
}

fn inside_convex(poly: &[[f64; 2]], p: [f64; 2]) -> bool {
    let mut sign = 0.0;
    for (k, a) in poly.iter().enumerate() {
        let b = poly[(k + 1) % poly.len()];
        let c = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
        if c != 0.0 {
            if sign != 0.0 && c.signum() != sign {
                return false;
            }
            sign = c.signum();
        }
    }
    true
}

/// A paved or built pixel of the 1998 base art: grey asphalt and concrete (little colour), the tinted aprons (blue /
/// purple: blue at least as strong as green). Not too dark (shadow, forest) nor white (glare).
pub fn is_paved(c: [f32; 3]) -> bool {
    let (mx, mn) = (c[0].max(c[1]).max(c[2]), c[0].min(c[1]).min(c[2]));
    let lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    (mx - mn < 22.0 || is_apron(c)) && (55.0..215.0).contains(&lum)
}

/// The aprons' blue / purple tint of the 1998 base art: blue at least as strong as green, green not above red.
pub fn is_apron(c: [f32; 3]) -> bool {
    let (mx, mn) = (c[0].max(c[1]).max(c[2]), c[0].min(c[1]).min(c[2]));
    c[2] >= c[1] && mx - mn < 60.0 && c[1] <= c[0] + 4.0
}

/// Runway and taxiway asphalt in the 1998 art: grey (little colour), from near black to mid grey (the shoulders are
/// lighter and beige, the aprons tinted).
pub fn is_asphalt(c: [f32; 3]) -> bool {
    let (mx, mn) = (c[0].max(c[1]).max(c[2]), c[0].min(c[1]).min(c[2]));
    let lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    mx - mn < 25.0 && (15.0..150.0).contains(&lum)
}

/// Pavement grey in the 1998 base art, from mid-grey asphalt to light concrete: little colour (less than the beige
/// shoulders and the brown fields) and not yellow or brown: blue at most 6 below red and green, at most 2 when darkish.
/// Not dark (PAVEMENT_MIN_LUM): dark fields and orchards are as grey; the runway's own tone covers dark asphalt.
pub fn is_grey(c: [f32; 3]) -> bool {
    let (mx, mn) = (c[0].max(c[1]).max(c[2]), c[0].min(c[1]).min(c[2]));
    let lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    let warm = if lum < 90.0 { 2.0 } else { 6.0 };
    mx - mn < 14.0 && c[2] >= c[0].min(c[1]) - warm && (PAVEMENT_MIN_LUM..215.0).contains(&lum)
}

/// Where the taxiways' tones count: little enough colour for worn, warm pavement (brown and red fields have more) and
/// at least `min_lum` bright. Away from the taxi paths that is PAVEMENT_MIN_LUM: dark ploughed fields and orchards are
/// as grey as the darkest taxiways.
fn is_pavement_like(c: [f32; 3], min_lum: f32) -> bool {
    let lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    c[0].max(c[1]).max(c[2]) - c[0].min(c[1]).min(c[2]) < PAVEMENT_CHROMA && lum >= min_lum
}
const PAVEMENT_CHROMA: f32 = 30.0;
const PAVEMENT_MIN_LUM: f32 = 62.0;

/// One airbase site: the union of its inset records (kept as a rectangle before) and its footprint.
pub struct Site {
    pub rect: [u32; 4],
    pub footprint: Grid,
}

/// Base points from iaf.ibx (engine metres): every `…X` / `…Xn` key with its `…Y` partner, in every section.
pub fn ibx_points(ibx: &[u8]) -> Vec<[f64; 2]> {
    let ini = Ini::parse(ibx);
    let mut out = Vec::new();
    for s in &ini.sections {
        for (k, v) in &s.entries {
            let Some(pos) = k.rfind('X') else { continue };
            if !k[pos + 1..].chars().all(|c| c.is_ascii_digit()) {
                continue;
            }
            let ky = format!("{}Y{}", &k[..pos], &k[pos + 1..]);
            if let (Ok(x), Some(y)) = (v.trim().parse::<f64>(), s.f32(&ky)) {
                out.push([x, y as f64]);
            }
        }
    }
    out
}

/// iaf.ibx's lineup points (x, y, altitude; engine metres).
pub fn ibx_lineups(ibx: &[u8]) -> Vec<[f64; 3]> {
    Ini::parse(ibx).sections.iter().filter_map(|s| Some([ibx_f(s, "LineupLocX")?, ibx_f(s, "LineupLocY")?, ibx_f(s, "LineupLocZ")?])).collect()
}

/// Units this far above their nearest base's lineup altitude are in the air.
const GROUND_M: f64 = 150.0;

/// True for a unit (x, y, altitude) on the ground: below the nearest lineup's altitude + GROUND_M.
pub fn on_ground(lineups: &[[f64; 3]], u: &[f64; 3]) -> bool {
    let near = lineups.iter().min_by(|a, b| (a[0] - u[0]).hypot(a[1] - u[1]).total_cmp(&(b[0] - u[0]).hypot(b[1] - u[1])));
    near.is_none_or(|l| u[2] < l[2] + GROUND_M)
}

/// The playable missions' unit positions (engine metres; x, y, altitude) from the converted missions (`iaf-convert
/// missions`): the files missionlist.json names.
pub fn mission_units(dir: &Path) -> Vec<[f64; 3]> {
    let mut out = Vec::new();
    let Ok(list) = std::fs::read(dir.join("missionlist.json")) else { return out };
    let Ok(list) = serde_json::from_slice::<serde_json::Value>(&list) else { return out };
    let mut names: Vec<&str> = list.as_object().into_iter().flatten().flat_map(|(_, v)| v.as_array().into_iter().flatten()).filter_map(|n| n.as_str()).collect();
    names.sort();
    names.dedup();
    for name in names {
        let Ok(text) = std::fs::read(dir.join(format!("{name}.json"))) else { continue };
        let Ok(v) = serde_json::from_slice::<serde_json::Value>(&text) else { continue };
        for it in v["entities"]["items"].as_array().into_iter().flatten() {
            if let (Some(x), Some(y)) = (it["0x2e4"].as_f64(), it["0x2ee"].as_f64())
                && (x >= 0.0 || y >= 0.0)
            {
                out.push([x, y, it["0x2f8"].as_f64().unwrap_or(0.0)]);
            }
        }
    }
    out
}

/// The inset records of level ≤ KEEP_INSET_LEVEL merged into sites (records that overlap or touch).
pub fn inset_sites(ptt: &iaf_formats::ptt::Ptt) -> Vec<[u32; 4]> {
    let mut rects: Vec<[u32; 4]> = ptt.levels.iter().filter(|l| l.flag == 0 && l.level <= KEEP_INSET_LEVEL).map(|l| l.rect).collect();
    loop {
        let mut merged = false;
        'outer: for a in 0..rects.len() {
            for b in a + 1..rects.len() {
                let (p, q) = (rects[a], rects[b]);
                if p[0] <= q[2] && q[0] <= p[2] && p[1] <= q[3] && q[1] <= p[3] {
                    rects[a] = [p[0].min(q[0]), p[1].min(q[1]), p[2].max(q[2]), p[3].max(q[3])];
                    rects.swap_remove(b);
                    merged = true;
                    break 'outer;
                }
            }
        }
        if !merged {
            return rects;
        }
    }
}

/// The footprint of the airbase in `rect` (terrain units) from the 1998 art drawn at LEVEL, the runway leaves (terrain
/// units), the base points and the missions' units (terrain units). None when no runway leaf is in the rect (a
/// target site, kept whole).
pub fn footprint(rect: [u32; 4], art: &dyn Fn(i64, i64, usize, usize) -> Vec<[f32; 3]>, leaves: &[Vec<[f64; 2]>], points: &[[f64; 2]], units: &[[f64; 2]]) -> Option<Grid> {
    let s = (1u32 << LEVEL) as f64;
    let (px0, py0) = ((rect[0] as f64 / s).floor() as i64, (rect[1] as f64 / s).floor() as i64);
    let (w, h) = (((rect[2] as f64 / s).ceil() as i64 - px0) as usize, ((rect[3] as f64 / s).ceil() as i64 - py0) as usize);
    let mut seeds = Grid::new(px0 as f64 * s, py0 as f64 * s, s, w, h);
    let in_rect = |t: &[f64; 2]| t[0] >= rect[0] as f64 && t[0] < rect[2] as f64 && t[1] >= rect[1] as f64 && t[1] < rect[3] as f64;
    for l in leaves.iter().filter(|l| l.iter().any(in_rect)) {
        seeds.polygon(l);
    }
    if !seeds.v.iter().any(|&b| b) {
        return None;
    }
    let cells = |m: f64| (m / CELL_M).round().max(1.0) as usize;
    for p in points.iter().filter(|p| in_rect(p)) {
        seeds.disc(*p, POINT_M / UNITS_TO_METRES);
    }
    let rgb = art(px0, py0, w, h);
    let paved = Grid { v: rgb.iter().map(|&c| is_paved(c)).collect(), ..seeds.clone() };
    let paved = paved.erode(cells(ROAD_M) / 2).dilate(cells(ROAD_M) / 2);
    let mut core = Grid::grow(&seeds, &paved, cells(GROW_M));
    core.or(&seeds);
    for _ in 0..2 {
        let near = core.dilate(cells(UNIT_NEAR_M));
        for u in units.iter().filter(|u| in_rect(u) && near.at(u[0], u[1])) {
            core.disc(*u, UNIT_M / UNITS_TO_METRES);
        }
    }
    let mut f = core.dilate(cells(CLOSE_M)).erode(cells(CLOSE_M));
    f.fill_holes();
    Some(f.dilate(cells(MARGIN_M)))
}

/// Every airbase site's footprint (docs/imagery.md §3): the inset sites that hold a terraintype.dat runway leaf.
pub fn sites(install: &Path, theatre: &Theatre, missions: &Path) -> Result<Vec<Site>> {
    let ptt = iaf_formats::ptt::Ptt::open(install.join("resource/terrain/map.ptt"))?;
    let types = TerrainTypes::parse(&std::fs::read(install.join("terraintype.dat")).context("terraintype.dat")?)?;
    let leaves: Vec<Vec<[f64; 2]>> = types.leaf_polygons(RUNWAY, 2.0e6).into_iter().map(|(_, p)| p.iter().map(|q| units(q[0], q[1])).collect()).collect();
    let points: Vec<[f64; 2]> = std::fs::read(install.join("iaf.ibx")).map(|b| ibx_points(&b)).unwrap_or_default().iter().map(|p| units(p[0], p[1])).collect();
    // Units on the ground: below the nearest base's lineup altitude + GROUND_M (flights in the air stand on nothing).
    let lineups = ibx_lineups(&std::fs::read(install.join("iaf.ibx")).unwrap_or_default());
    let units_t: Vec<[f64; 2]> = mission_units(missions).iter().filter(|u| on_ground(&lineups, u)).map(|p| units(p[0], p[1])).collect();
    let mut out = Vec::new();
    for rect in inset_sites(&ptt) {
        let art = |x0: i64, y0: i64, w: usize, h: usize| theatre.original_rect(LEVEL, x0, y0, w, h, &mut Cache::default()).unwrap_or_default();
        if let Some(footprint) = footprint(rect, &art, &leaves, &points, &units_t) {
            out.push(Site { rect, footprint });
        }
    }
    Ok(out)
}

/// A runway of the 1998 base art (engine metres, X east, Y north): its paved ends on the centreline and its width.
#[derive(Debug, Clone, PartialEq)]
pub struct Runway {
    pub ends: [[f64; 2]; 2],
    pub width: f64,
    /// The thresholds: metres from each end to where the landing surface starts (the art's painted threshold stripes;
    /// 0 where it shows none). The part before a threshold is a blast pad or overrun.
    pub thresholds: [f64; 2],
}

impl Runway {
    /// Heading from ends[0] to ends[1], degrees clockwise from north, in [0, 360).
    pub fn heading(&self) -> f64 {
        let d = [self.ends[1][0] - self.ends[0][0], self.ends[1][1] - self.ends[0][1]];
        d[0].atan2(d[1]).to_degrees().rem_euclid(360.0)
    }

    /// True when the runway runs within 3° of `hdg` (either way) and passes within half its width + 30 m of `p`.
    pub fn through(&self, p: [f64; 2], hdg: f64) -> bool {
        let dh = (self.heading() - hdg).rem_euclid(180.0);
        let h = self.heading().to_radians();
        let off = (p[0] - self.ends[0][0]) * h.cos() - (p[1] - self.ends[0][1]) * h.sin();
        dh.min(180.0 - dh) < 3.0 && off.abs() < self.width / 2.0 + 30.0
    }

    pub fn length(&self) -> f64 {
        (self.ends[1][0] - self.ends[0][0]).hypot(self.ends[1][1] - self.ends[0][1])
    }

    /// The designation numbers painted at ends[0] and ends[1]: the landing heading over ten (01–36), from the art's
    /// own runway heading.
    pub fn numbers(&self) -> [u32; 2] {
        let n = |h: f64| match ((h / 10.0).round() as u32) % 36 {
            0 => 36,
            v => v,
        };
        let h = self.heading();
        [n(h), n(h + 180.0)]
    }
}

/// The detection's lengths (metres): runways are paved strips at least RUNWAY_MIN long and RUNWAY_MIN_WIDTH wide.
const RUNWAY_MIN: f64 = 1800.0;
const RUNWAY_MIN_WIDTH: f64 = 35.0;
const RUNWAY_MAX_WIDTH: f64 = 120.0;
/// The runway's edge: where the art gets this much brighter or darker than the runway's middle (0–255).
const RUNWAY_EDGE_LUM: f32 = 25.0;
/// The art's threshold stripes are looked for this far from each end (m).
const THRESHOLD_MAX_M: f64 = 900.0;
/// A runway's grey concrete ends reach at most this far past its asphalt (m).
const END_CONCRETE_M: f64 = 120.0;
/// Paved strips narrower than twice this (taxiways, roads) are dropped before the search.
const CORE_M: f64 = 14.0;

/// A picture of a base for the runway search: `rgb` (w × h pixels of `px_m` metres, rows running south) whose pixel
/// (i, j) centre is at engine metres `origin + (i·px_m, −j·px_m)`, and `asphalt`, its runway-coloured pixels.
pub struct Picture<'a> {
    pub rgb: &'a [[f32; 3]],
    pub asphalt: &'a [bool],
    pub w: usize,
    pub h: usize,
    pub px_m: f64,
    pub origin: [f64; 2],
}

/// A line in the picture's local metres (east, north of pixel (0, 0)): heading th (rad), across offset c, and the
/// along span [a0, a1].
#[derive(Clone, Copy, Debug)]
struct Line {
    th: f64,
    c: f64,
    a0: f64,
    a1: f64,
}

impl Line {
    fn dirs(&self) -> ([f64; 2], [f64; 2]) {
        ([self.th.sin(), self.th.cos()], [self.th.cos(), -self.th.sin()])
    }
    fn point(&self, al: f64, ac: f64) -> [f64; 2] {
        let (d, a) = self.dirs();
        [d[0] * al + a[0] * ac, d[1] * al + a[1] * ac]
    }
    fn local(&self, q: [f64; 2]) -> (f64, f64) {
        let (d, a) = self.dirs();
        (q[0] * d[0] + q[1] * d[1], q[0] * a[0] + q[1] * a[1])
    }
}

impl Picture<'_> {
    fn index(&self, q: [f64; 2]) -> Option<usize> {
        let (i, j) = ((q[0] / self.px_m).round(), (-q[1] / self.px_m).round());
        (i >= 0.0 && j >= 0.0 && (i as usize) < self.w && (j as usize) < self.h).then(|| j as usize * self.w + i as usize)
    }
    fn paved(&self, q: [f64; 2]) -> bool {
        self.index(q).is_some_and(|k| self.asphalt[k])
    }
    /// Asphalt, or the grey concrete of a runway's ends (where the art paints the numbers).
    fn surface(&self, q: [f64; 2]) -> bool {
        self.index(q).is_some_and(|k| self.asphalt[k] || is_paved(self.rgb[k]))
    }
    fn lum(&self, q: [f64; 2]) -> f32 {
        self.index(q).map_or(255.0, |k| {
            let c = self.rgb[k];
            0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        })
    }

    /// The runway on `l` (its heading and offset already fitted, its span a part of the runway): the width from the
    /// brightness across it, the ends where the asphalt stops along it. None when it is no runway (too narrow, wide or
    /// short).
    /// The runway's edges across `l` over the along span [b0, b1]: (offset of the low edge, of the high edge) from
    /// the line. Across the line, the median brightness along the span (1 m steps); the runway is the span around the
    /// line within RUNWAY_EDGE_LUM of its middle's brightness and paved in at least half the samples (asphalt runways
    /// have lighter shoulders and infield, concrete runways darker ground around them).
    fn edges(&self, l: &Line, b0: f64, b1: f64) -> (f64, f64) {
        let n = ((b1 - b0) / 10.0).max(1.0) as usize;
        let profile = |ac: f64| {
            let mut v: Vec<f32> = (0..n).map(|k| self.lum(l.point(b0 + k as f64 * 10.0, ac))).collect();
            v.sort_by(f32::total_cmp);
            let paved = (0..n).filter(|&k| self.paved(l.point(b0 + k as f64 * 10.0, ac))).count() * 2 >= n;
            (v[n / 2], paved)
        };
        let mid = (-5..=5).map(|k| profile(l.c + k as f64 * 2.0).0).sum::<f32>() / 11.0;
        let inside = |ac: f64| {
            let (v, pv) = profile(ac);
            pv && v <= mid + RUNWAY_EDGE_LUM
        };
        let (mut lo, mut hi) = (0.0, 0.0);
        while lo > -RUNWAY_MAX_WIDTH && inside(l.c + lo - 1.0) {
            lo -= 1.0;
        }
        while hi < RUNWAY_MAX_WIDTH && inside(l.c + hi + 1.0) {
            hi += 1.0;
        }
        (lo - 0.5, hi + 0.5)
    }

    /// The runway on `l` (its heading and offset roughly fitted, its span a part of the runway): the centreline through
    /// the middles between the edges at 20 % and 80 % of the span (twice, unless that turns it by more than 2°), the width from the edges over the whole span,
    /// the ends where the asphalt stops along it. None when it is no runway (too narrow, wide or short).
    fn measure(&self, mut l: Line) -> Option<(Runway, Line, f64)> {
        for _ in 0..2 {
            let span = l.a1 - l.a0;
            let mids: Vec<[f64; 2]> = [0.2, 0.8]
                .iter()
                .map(|f| {
                    let a = l.a0 + f * span;
                    let (lo, hi) = self.edges(&l, a - 0.15 * span, a + 0.15 * span);
                    l.point(a, l.c + 0.5 * (lo + hi))
                })
                .collect();
            let th = (mids[1][0] - mids[0][0]).atan2(mids[1][1] - mids[0][1]);
            // A middle on a crossing runway or an apron turns the line away: keep the fit then.
            if ((th - l.th + PI).rem_euclid(2.0 * PI) - PI).abs() > 2f64.to_radians() {
                break;
            }
            let t = Line { th, ..l };
            let (a0, c) = t.local(mids[0]);
            let (a1, _) = t.local(mids[1]);
            l = Line { th, c, a0: a0 - 0.2 / 0.6 * (a1 - a0), a1: a1 + 0.2 / 0.6 * (a1 - a0) };
        }
        let (lo, hi) = self.edges(&l, l.a0, l.a1);
        let width = hi - lo;
        l.c += 0.5 * (lo + hi);
        // Ends: along the centreline while 4 of 5 points across the middle 60 % of the width are asphalt or grey concrete
        // (a road is not;
        // gaps up to 60 m bridged: the painted threshold stripes).
        let on = |al: f64, test: &dyn Fn([f64; 2]) -> bool| (-2..=2).filter(|&k| test(l.point(al, l.c + k as f64 * width / 7.0))).count() >= 4;
        let walk = |from: f64, dir: f64, reach: f64, test: &dyn Fn([f64; 2]) -> bool| {
            let (mut s, mut gap, mut last) = (from, 0.0, from);
            while gap <= 60.0 && (s - from).abs() < reach {
                if on(s, test) {
                    last = s;
                    gap = 0.0;
                } else {
                    gap += 2.0;
                }
                s += 2.0 * dir;
            }
            last
        };
        // From the span's middle outward over asphalt (a span that reached past the end along a road comes back to
        // the pavement), then at most END_CONCRETE_M further over grey concrete.
        let mid = 0.5 * (l.a0 + l.a1);
        let asphalt = |q: [f64; 2]| self.paved(q);
        let concrete = |q: [f64; 2]| self.surface(q);
        let end = |dir: f64| walk(walk(mid, dir, 5000.0, &asphalt), dir, END_CONCRETE_M, &concrete);
        (l.a0, l.a1) = (end(-1.0), end(1.0));
        let ok = (RUNWAY_MIN_WIDTH..=RUNWAY_MAX_WIDTH).contains(&width) && l.a1 - l.a0 >= RUNWAY_MIN;
        let e = |al: f64| {
            let q = l.point(al, l.c);
            [self.origin[0] + q[0], self.origin[1] + q[1]]
        };
        // Thresholds: from each end inward, the first ≥ 12 m long stretch where a third to nine tenths of the points
        // across the middle 80 % are bright paint (the art's threshold stripes), less the 6 m the stripes stand inside it.
        let mid_lum = (0..20).map(|k| self.lum(l.point(l.a0 + (k as f64 + 0.5) / 20.0 * (l.a1 - l.a0), l.c))).sum::<f32>() / 20.0;
        const N_PAINT: usize = 17;
        let paint = |al: f64| {
            let n = N_PAINT;
            (0..n).filter(|&k| self.lum(l.point(al, l.c + (k as f64 / (n - 1) as f64 - 0.5) * 0.8 * width)) > (mid_lum + 55.0).min(200.0)).count()
        };
        // Stripes: a third to nine tenths of the points bright (a light concrete end is bright all across).
        let stripes = |al: f64| {
            let c = paint(al);
            3 * c >= N_PAINT && 10 * c <= 9 * N_PAINT
        };
        let threshold = |from: f64, dir: f64| {
            let mut run = 0.0;
            let mut s = 0.0;
            while s < THRESHOLD_MAX_M {
                run = if stripes(from + dir * s) { run + 2.0 } else { 0.0 };
                if run >= 12.0 {
                    return (s - run - 6.0).max(0.0);
                }
                s += 2.0;
            }
            0.0
        };
        let thresholds = [threshold(l.a0, 1.0), threshold(l.a1, -1.0)];
        ok.then(|| (Runway { ends: [e(l.a0), e(l.a1)], width, thresholds }, l, width))
    }

    /// The best heading (± `dth` rad in 0.05° steps, turning about the span's middle) and offset (± `dc` m in 1 m
    /// steps) around `l`: the most points within ± 8 m of the line over its span.
    fn fit(pts: &[[f64; 2]], l: Line, dth: f64, dc: i32) -> Line {
        let mid = l.point(0.5 * (l.a0 + l.a1), l.c);
        let half = 0.5 * (l.a1 - l.a0);
        // Only the points near the line can count (turning by dth moves the span's ends by half · dth).
        let reach = dc as f64 + 8.0 + half * dth;
        let near: Vec<[f64; 2]> = pts
            .iter()
            .map(|p| [p[0] - mid[0], p[1] - mid[1]])
            .filter(|q| {
                let (al, ac) = Line { c: 0.0, ..l }.local(*q);
                al.abs() <= half + 50.0 && ac.abs() < reach
            })
            .collect();
        let mut best = (0, l.th, 0.0);
        let steps = (dth.to_degrees() / 0.05).round() as i32;
        // Per heading: the points' across offsets in 1 m bins, then the count within ± 8 m of each offset.
        let r = (reach.ceil() as i64) + 1;
        for k in -steps..=steps {
            let t = Line { th: l.th + (k as f64 * 0.05).to_radians(), ..l };
            let mut bins = vec![0usize; (2 * r + 1) as usize];
            for q in &near {
                let (al, ac) = t.local(*q);
                if al.abs() <= half && ac.abs() < r as f64 {
                    bins[(ac.round() as i64 + r) as usize] += 1;
                }
            }
            for dcc in -dc..=dc {
                let n: usize = (dcc as i64 - 7..=dcc as i64 + 7).filter(|b| b.abs() <= r).map(|b| bins[(b + r) as usize]).sum();
                if n > best.0 {
                    best = (n, t.th, dcc as f64);
                }
            }
        }
        let t = Line { th: best.1, ..l };
        let (am, cm) = t.local(mid);
        Line { th: best.1, c: cm + best.2, a0: am - half, a1: am + half }
    }

    /// The runways: first the one through `anchor` (engine metres, heading in degrees: iaf.ibx's lineup point and
    /// RunwayNumber) when given, then the longest straight asphalt strips between RUNWAY_MIN_WIDTH and
    /// RUNWAY_MAX_WIDTH wide, each taken out before the next search.
    pub fn runways(&self, anchor: Option<([f64; 2], f64)>) -> Vec<Runway> {
        let (w, h, px_m) = (self.w, self.h, self.px_m);
        let paved = Grid { x0: 0.0, y0: 0.0, cell: 1.0, w, h, v: self.asphalt.to_vec() };
        let mut core = paved.erode((CORE_M / px_m).round().max(1.0) as usize);
        let points = |g: &Grid| -> Vec<[f64; 2]> { (0..w * h).filter(|&k| g.v[k]).map(|k| [(k % w) as f64 * px_m, -((k / w) as f64) * px_m]).collect() };
        let mut out = Vec::new();
        let take_out = |core: &mut Grid, l: &Line, width: f64| {
            for k in 0..w * h {
                if core.v[k] {
                    let (al, ac) = l.local([(k % w) as f64 * px_m, -((k / w) as f64) * px_m]);
                    if al >= l.a0 - 20.0 && al <= l.a1 + 20.0 && (ac - l.c).abs() < width / 2.0 + 20.0 {
                        core.v[k] = false;
                    }
                }
            }
        };
        if let Some((p, hdg)) = anchor {
            let q = [p[0] - self.origin[0], p[1] - self.origin[1]];
            let l = Line { th: hdg.to_radians(), c: 0.0, a0: 0.0, a1: 0.0 };
            let (al, ac) = l.local(q);
            let l = Line { c: ac, a0: al + 100.0, a1: al + 1500.0, ..l };
            let l = Self::fit(&points(&paved), l, 1.5, 30);
            if let Some((r, l, width)) = self.measure(l) {
                take_out(&mut core, &l, width);
                out.push(r);
            }
        }
        for _ in 0..6 {
            // At most ≈ 60 000 points for the coarse search (a large base's picture holds millions of core pixels).
            let all = points(&core);
            let stride = all.len() / 150_000 + 1;
            let pts: Vec<[f64; 2]> = all.iter().step_by(stride).copied().collect();
            // Coarse search: per heading (0.5° steps), the longest run of 20 m along-bins holding core pixels (gaps of
            // up to 140 m bridged: a crossing runway taken out) in 5 m across-bins.
            let mut best: Option<(f64, Line)> = None;
            for step in 0..360 {
                let th = (step as f64 * 0.5).to_radians();
                if let Some((len, c, a0, a1)) = longest_run(&pts, th, 5.0, 20.0, 7)
                    && best.is_none_or(|b| len > b.0)
                {
                    best = Some((len, Line { th, c, a0, a1 }));
                }
            }
            let Some((_, l)) = best.filter(|b| b.0 >= RUNWAY_MIN) else { break };
            let l = Self::fit(&all, l, 1.0, 6);
            match self.measure(l) {
                Some((r, l, width)) => {
                    take_out(&mut core, &l, width);
                    out.push(r);
                }
                // Not a runway: take the strip out of the search (a wide taxiway or an apron's edge).
                None => take_out(&mut core, &l, 40.0),
            }
        }
        dedupe(out)
    }
}

/// The runways without repeats: of two runways within 3° of each other, the shorter one's middle near the longer one's
/// centreline (Runway::through), the longer one.
fn dedupe(mut rw: Vec<Runway>) -> Vec<Runway> {
    rw.sort_by(|a, b| b.length().total_cmp(&a.length()));
    let mut out: Vec<Runway> = Vec::new();
    for r in rw {
        let mid = [(r.ends[0][0] + r.ends[1][0]) / 2.0, (r.ends[0][1] + r.ends[1][1]) / 2.0];
        let same = out.iter().any(|o| o.through(mid, r.heading()));
        if !same {
            out.push(r);
        }
    }
    out
}

/// The longest run along heading `th` (rad) of `along`-metre bins holding a point, in `across`-metre lanes, gaps of
/// up to `gap` bins bridged: (length m, the lane's centre offset, along start, along end).
fn longest_run(pts: &[[f64; 2]], th: f64, across: f64, along: f64, gap: usize) -> Option<(f64, f64, f64, f64)> {
    let (d, a) = ([th.sin(), th.cos()], [th.cos(), -th.sin()]);
    let proj: Vec<(f64, f64)> = pts.iter().map(|p| (p[0] * d[0] + p[1] * d[1], p[0] * a[0] + p[1] * a[1])).collect();
    let (amin, amax) = proj.iter().fold((f64::MAX, f64::MIN), |(lo, hi), q| (lo.min(q.0), hi.max(q.0)));
    let (cmin, cmax) = proj.iter().fold((f64::MAX, f64::MIN), |(lo, hi), q| (lo.min(q.1), hi.max(q.1)));
    if proj.is_empty() {
        return None;
    }
    let (na, nc) = (((amax - amin) / along) as usize + 1, ((cmax - cmin) / across) as usize + 1);
    let mut occ = vec![false; na * nc];
    for q in &proj {
        occ[((q.1 - cmin) / across) as usize * na + ((q.0 - amin) / along) as usize] = true;
    }
    let mut best: Option<(f64, f64, f64, f64)> = None;
    for lane in 0..nc {
        let row = &occ[lane * na..(lane + 1) * na];
        let (mut start, mut last, mut holes) = (None, 0usize, 0usize);
        for (i, &o) in row.iter().enumerate().chain(std::iter::once((na, &false))) {
            if o {
                if start.is_none() || holes > gap {
                    start = Some(i);
                }
                last = i;
                holes = 0;
            } else if let Some(s) = start {
                holes += 1;
                if holes > gap || i == na {
                    let len = (last - s + 1) as f64 * along;
                    if best.is_none_or(|b| len > b.0) {
                        best = Some((len, cmin + (lane as f64 + 0.5) * across, amin + s as f64 * along, amin + (last + 1) as f64 * along));
                    }
                    start = None;
                }
            }
        }
    }
    best
}

/// A surface's colour as brightness and tint (the colour minus its grey), for "the same paint" tests.
#[derive(Debug, Clone, Copy)]
pub struct Tone {
    lum: f32,
    tint: [f32; 3],
}

impl Tone {
    pub fn of(c: [f32; 3]) -> Self {
        let m = (c[0] + c[1] + c[2]) / 3.0;
        Tone { lum: 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2], tint: c.map(|v| v - m) }
    }

    /// Per component median of the samples' tones (grey 128 without samples).
    pub fn median(samples: &[[f32; 3]]) -> Self {
        let tones: Vec<Tone> = samples.iter().map(|&c| Tone::of(c)).collect();
        let med = |f: &dyn Fn(&Tone) -> f32| {
            let mut v: Vec<f32> = tones.iter().map(f).collect();
            v.sort_by(f32::total_cmp);
            v.get(v.len() / 2).copied().unwrap_or(0.0)
        };
        if tones.is_empty() {
            return Tone::of([128.0; 3]);
        }
        Tone { lum: med(&|t| t.lum), tint: [med(&|t| t.tint[0]), med(&|t| t.tint[1]), med(&|t| t.tint[2])] }
    }

    /// The same paint: a tint within TINT_TOL and a brightness within LUM_TOL (wear, markings' blur, JPEG).
    pub fn matches(&self, c: [f32; 3]) -> bool {
        let t = Tone::of(c);
        let d = (0..3).map(|k| (t.tint[k] - self.tint[k]).powi(2)).sum::<f32>().sqrt();
        d < TINT_TOL && (t.lum - self.lum).abs() < LUM_TOL
    }
}

const TINT_TOL: f32 = 7.0;
const LUM_TOL: f32 = 35.0;

/// An airbase of iaf.ibx with what the art shows of it (docs/rendering.md §7).
pub struct Base {
    pub name: String,
    /// The runway start point and the take-off heading (iaf.ibx LineupLoc, RunwayNumber).
    pub lineup: [f64; 2],
    pub runway_deg: f64,
    pub runways: Vec<Runway>,
    /// The AI's taxi paths (iaf.ibx: runway → hangars, hangars → runway, each hangar's turn point → hangar).
    pub taxi: Vec<Vec<[f64; 2]>>,
    /// The paved surface (runways, taxiways, aprons) as a raster: `paved.v` row by row, rows running south, pixel
    /// (i, j)'s north-west corner at engine metres (origin[0] + i·px_m, origin[1] − j·px_m).
    pub paved: Grid,
    /// The paved pixels in the aprons' tint (concrete), same raster.
    pub concrete: Vec<bool>,
    pub origin: [f64; 2],
    pub px_m: f64,
}

/// The AI's runway where the art shows none (m): behind the lineup point, length, width.
const IBX_BEHIND_M: f64 = 150.0;
const IBX_LENGTH_M: f64 = 3000.0;
const IBX_WIDTH_M: f64 = 45.0;

/// The taxi lines' distance field reaches this far (m).
pub const TAXI_FIELD_M: f64 = 10.0;

impl Base {
    /// Per mask pixel (its centre), the distance to the nearest taxi path in metres, at most TAXI_FIELD_M.
    pub fn taxi_distance(&self) -> Vec<f32> {
        let (w, h, px) = (self.paved.w, self.paved.h, self.px_m);
        let mut d = vec![TAXI_FIELD_M as f32; w * h];
        let to_px = |p: &[f64; 2]| [(p[0] - self.origin[0]) / px - 0.5, (self.origin[1] - p[1]) / px - 0.5];
        for path in &self.taxi {
            for seg in path.windows(2) {
                let (a, b) = (to_px(&seg[0]), to_px(&seg[1]));
                let r = TAXI_FIELD_M / px;
                let (i0, i1) = ((a[0].min(b[0]) - r).floor().max(0.0) as usize, ((a[0].max(b[0]) + r).ceil().max(0.0) as usize).min(w));
                let (j0, j1) = ((a[1].min(b[1]) - r).floor().max(0.0) as usize, ((a[1].max(b[1]) + r).ceil().max(0.0) as usize).min(h));
                let ab = [b[0] - a[0], b[1] - a[1]];
                let len2 = (ab[0] * ab[0] + ab[1] * ab[1]).max(1e-9);
                for j in j0..j1 {
                    for i in i0..i1 {
                        let q = [i as f64 - a[0], j as f64 - a[1]];
                        let t = ((q[0] * ab[0] + q[1] * ab[1]) / len2).clamp(0.0, 1.0);
                        let dist = ((q[0] - ab[0] * t).hypot(q[1] - ab[1] * t) * px) as f32;
                        let k = j * w + i;
                        d[k] = d[k].min(dist);
                    }
                }
            }
        }
        d
    }
}

/// The art's level the bases are read at (2 units, ≈ 2.5 m).
const BASE_LEVEL: u32 = 1;
/// The picture: the base's runway leaves (those within BASE_NEAR_M of the lineup point) and BASE_PAD_M around them,
/// at most BASE_HALF_M from the lineup point. Runways are looked for within RUNWAY_PAD_M of the leaves.
const BASE_NEAR_M: f64 = 3000.0;
const BASE_PAD_M: f64 = 800.0;
const BASE_HALF_M: f64 = 4500.0;
const RUNWAY_PAD_M: f64 = 250.0;
/// The runway's and taxiways' own tones count this close to the runway leaves (m).
const TONE_PAD_M: f64 = 100.0;
/// The taxiways' own tone counts this close to iaf.ibx's taxi paths (m): a taxiway's half width plus the path's offset.
const TAXI_NEAR_M: f64 = 30.0;
/// A taxi path segment needs this many pavement-like samples off the runways (one per 2.5 m pixel) for its own tone.
const TAXI_MIN_SAMPLES: usize = 8;
/// The taxi paths' tones count anywhere this close to the runway leaves (m).
const TAXIWAYS_PAD_M: f64 = 600.0;
/// The paved mask's edge is closed over this radius (m).
const CLOSE_EDGE_M: f64 = 5.0;
/// Beside the runways (this far beyond their edges, m) the paved mask is opened over SHOULDER_OPEN_M (m).
const SHOULDER_M: f64 = 40.0;
const SHOULDER_OPEN_M: f64 = 7.5;
/// Paved pixels belong to the base when reached from a runway within this distance (m).
const PAVED_REACH_M: f64 = 1500.0;

/// (south-west, north-east) corners of a polygon.
fn bbox(p: &[[f64; 2]]) -> ([f64; 2], [f64; 2]) {
    p.iter().fold(([f64::MAX; 2], [f64::MIN; 2]), |(lo, hi), q| ([lo[0].min(q[0]), lo[1].min(q[1])], [hi[0].max(q[0]), hi[1].max(q[1])]))
}

fn ibx_f(s: &iaf_formats::ini::Section, k: &str) -> Option<f64> {
    s.get(k)?.trim().parse().ok()
}

fn ibx_path(s: &iaf_formats::ini::Section, prefix: &str, n: usize) -> Vec<[f64; 2]> {
    (0..n).filter_map(|i| Some([ibx_f(s, &format!("{prefix}X{i}"))?, ibx_f(s, &format!("{prefix}Y{i}"))?])).collect()
}

/// Every iaf.ibx airbase with its runways and paved surface from the 1998 art (`theatre`).
pub fn bases(install: &Path, theatre: &Theatre) -> Result<Vec<Base>> {
    let ini = Ini::parse(&std::fs::read(install.join("iaf.ibx")).context("iaf.ibx")?);
    let s = (1u32 << BASE_LEVEL) as f64;
    let px_m = s * UNITS_TO_METRES;
    let types = TerrainTypes::parse(&std::fs::read(install.join("terraintype.dat")).context("terraintype.dat")?)?;
    let leaves: Vec<Vec<[f64; 2]>> = types.leaf_polygons(RUNWAY, 2.0e6).into_iter().map(|(_, p)| p).collect();
    let mut out = Vec::new();
    for sec in ini.sections.iter().filter(|s| s.get("LineupLocX").is_some() && s.get("RunwayNumber").is_some()) {
        let lineup = [ibx_f(sec, "LineupLocX").unwrap_or(0.0), ibx_f(sec, "LineupLocY").unwrap_or(0.0)];
        let n = |k: &str| ibx_f(sec, k).unwrap_or(0.0).max(0.0) as usize;
        let hangars = n("HangarsNum");
        let mut taxi = vec![ibx_path(sec, "ToTaxiPt", n("TaxiWayPtsTo")), ibx_path(sec, "FromTaxiPt", n("TaxiWayPtsFrom"))];
        let (hp, to, from) = (ibx_path(sec, "HangarPt", hangars), ibx_path(sec, "ToHangarTurnPt", hangars), ibx_path(sec, "FromHangarTurnPt", hangars));
        for (i, h) in hp.iter().enumerate() {
            taxi.extend(to.get(i).map(|t| vec![*t, *h]));
            taxi.extend(from.get(i).map(|f| vec![*h, *f]));
        }
        taxi.retain(|p| p.len() >= 2);
        // The picture, on the level's pixel grid (engine metres: lo = south-west, hi = north-east).
        let near: Vec<&Vec<[f64; 2]>> = leaves
            .iter()
            .filter(|l| {
                let (lo, hi) = bbox(l);
                lineup[0] > lo[0] - BASE_NEAR_M && lineup[0] < hi[0] + BASE_NEAR_M && lineup[1] > lo[1] - BASE_NEAR_M && lineup[1] < hi[1] + BASE_NEAR_M
            })
            .collect();
        let (mut lo, mut hi) = (lineup, lineup);
        for l in &near {
            let (a, b) = bbox(l);
            lo = [lo[0].min(a[0]), lo[1].min(a[1])];
            hi = [hi[0].max(b[0]), hi[1].max(b[1])];
        }
        let lo = [(lo[0] - BASE_PAD_M).max(lineup[0] - BASE_HALF_M), (lo[1] - BASE_PAD_M).max(lineup[1] - BASE_HALF_M)];
        let hi = [(hi[0] + BASE_PAD_M).min(lineup[0] + BASE_HALF_M), (hi[1] + BASE_PAD_M).min(lineup[1] + BASE_HALF_M)];
        let t0 = units(lo[0], hi[1]);
        let (px0, py0) = ((t0[0] / s).floor() as i64, (t0[1] / s).floor() as i64);
        let (w, h) = (((hi[0] - lo[0]) / px_m).ceil() as usize, ((hi[1] - lo[1]) / px_m).ceil() as usize);
        let rgb = theatre.original_rect(BASE_LEVEL, px0, py0, w, h, &mut Cache::default())?;
        // The NW corner in engine metres; pixel (i, j) → leaf mask cell.
        let corner = [px0 as f64 * s * UNITS_TO_METRES - 166850.0, 1043780.0 - py0 as f64 * s * UNITS_TO_METRES];
        let to_px = |p: &[f64; 2]| [(p[0] - corner[0]) / px_m, (corner[1] - p[1]) / px_m];
        let mut leaf = Grid::new(0.0, 0.0, 1.0, w, h);
        for l in &near {
            leaf.polygon(&l.iter().map(to_px).collect::<Vec<_>>());
        }
        let region = leaf.dilate((RUNWAY_PAD_M / px_m) as usize);
        // The runway's own colour: along the lineup runway (RunwayNumber from the lineup point), 150–1200 m.
        let at_px = |p: [f64; 2]| {
            let (i, j) = (((p[0] - corner[0]) / px_m) as i64, ((corner[1] - p[1]) / px_m) as i64);
            (i >= 0 && j >= 0 && (i as usize) < w && (j as usize) < h).then(|| rgb[j as usize * w + i as usize])
        };
        let hd = ibx_f(sec, "RunwayNumber").unwrap_or(0.0).to_radians();
        let samples: Vec<[f32; 3]> = (150..1200).step_by(5).filter_map(|d| at_px([lineup[0] + hd.sin() * d as f64, lineup[1] + hd.cos() * d as f64])).collect();
        let reference = Tone::median(&samples);
        let asphalt: Vec<bool> = rgb.iter().zip(&region.v).map(|(&c, &r)| r && (is_asphalt(c) || reference.matches(c))).collect();
        let pic = Picture { rgb: &rgb, asphalt: &asphalt, w, h, px_m, origin: [corner[0] + px_m / 2.0, corner[1] - px_m / 2.0] };
        let hdg = ibx_f(sec, "RunwayNumber").unwrap_or(0.0);
        let mut runways = pic.runways(Some((lineup, hdg)));
        // Where the art shows no runway through the lineup point (a base only in the coarse imagery), the AI's runway:
        // from IBX_BEHIND_M behind the lineup point, IBX_LENGTH_M long, IBX_WIDTH_M wide, on RunwayNumber.
        // The lineup point stands at its runway's threshold (the take-off roll starts there).
        for r in runways.iter_mut().filter(|r| r.through(lineup, hdg)) {
            let d = [r.ends[1][0] - r.ends[0][0], r.ends[1][1] - r.ends[0][1]];
            let along = ((lineup[0] - r.ends[0][0]) * d[0] + (lineup[1] - r.ends[0][1]) * d[1]) / r.length();
            if along > 0.0 && along < THRESHOLD_MAX_M {
                r.thresholds[0] = along;
            } else if r.length() - along > 0.0 && r.length() - along < THRESHOLD_MAX_M {
                r.thresholds[1] = r.length() - along;
            }
        }
        if !runways.iter().any(|r| r.through(lineup, hdg)) {
            let d = [hdg.to_radians().sin(), hdg.to_radians().cos()];
            let at = |m: f64| [lineup[0] + d[0] * m, lineup[1] + d[1] * m];
            runways.push(Runway { ends: [at(-IBX_BEHIND_M), at(IBX_LENGTH_M - IBX_BEHIND_M)], width: IBX_WIDTH_M, thresholds: [IBX_BEHIND_M, 0.0] });
        }
        // The paved surface: paved pixels (roads dropped) reached from the runways.
        let mut seeds = Grid::new(0.0, 0.0, 1.0, w, h);
        for r in &runways {
            let (d, a) = (r.heading().to_radians().sin(), r.heading().to_radians().cos());
            let hw = r.width / 2.0;
            let q = |e: [f64; 2], al: f64, ac: f64| {
                let p = [e[0] + d * al + a * ac, e[1] + a * al - d * ac];
                [(p[0] - corner[0]) / px_m, (corner[1] - p[1]) / px_m]
            };
            seeds.polygon(&[q(r.ends[0], 0.0, -hw), q(r.ends[1], 0.0, -hw), q(r.ends[1], 0.0, hw), q(r.ends[0], 0.0, hw)]);
        }
        // Paved colours: pavement grey (is_grey: light grey taxiways and aprons too) and the aprons' tint anywhere; the
        // runway's own tone (which may match dark fields) within TONE_PAD_M of the runway leaves.
        let near_leaves = leaf.dilate((TONE_PAD_M / px_m) as usize);
        let mut paved = Grid {
            v: (0..w * h).map(|k| is_grey(rgb[k]) || (is_apron(rgb[k]) && is_paved(rgb[k])) || (near_leaves.v[k] && reference.matches(rgb[k]))).collect(),
            ..seeds.clone()
        };
        // Each taxiway's own paving (often lighter or warmer than the runway's, and taxiways differ from aprons): per
        // taxi path segment, the median tone of its pavement-like samples off the runways. It counts within
        // TAXI_NEAR_M of that segment, and within TAXIWAYS_PAD_M of the runway leaves: the taxiways no taxi path
        // follows (Ramon's parallel taxiways) have the same paving.
        let mut tones: Vec<Tone> = Vec::new();
        let on_runway = |p: [f64; 2]| {
            let (i, j) = (((p[0] - corner[0]) / px_m) as usize, ((corner[1] - p[1]) / px_m) as usize);
            i < w && j < h && seeds.v[j * w + i]
        };
        let r = TAXI_NEAR_M / px_m;
        for s in taxi.iter().flat_map(|p| p.windows(2)) {
            let n = (((s[1][0] - s[0][0]).hypot(s[1][1] - s[0][1]) / px_m).ceil() as usize).max(1);
            let samples: Vec<[f32; 3]> = (0..=n)
                .map(|k| [s[0][0] + (s[1][0] - s[0][0]) * k as f64 / n as f64, s[0][1] + (s[1][1] - s[0][1]) * k as f64 / n as f64])
                .filter(|&p| !on_runway(p))
                .filter_map(at_px)
                .filter(|&c| is_paved(c))
                .collect();
            if samples.len() < TAXI_MIN_SAMPLES {
                continue;
            }
            let tone = Tone::median(&samples);
            tones.push(tone);
            let (a, b) = (to_px(&s[0]), to_px(&s[1]));
            let ab = [b[0] - a[0], b[1] - a[1]];
            let len2 = (ab[0] * ab[0] + ab[1] * ab[1]).max(1e-9);
            let (i0, i1) = ((a[0].min(b[0]) - r).max(0.0) as usize, ((a[0].max(b[0]) + r).max(0.0) as usize).min(w));
            let (j0, j1) = ((a[1].min(b[1]) - r).max(0.0) as usize, ((a[1].max(b[1]) + r).max(0.0) as usize).min(h));
            for j in j0..j1 {
                for i in i0..i1 {
                    let q = [i as f64 + 0.5 - a[0], j as f64 + 0.5 - a[1]];
                    let t = ((q[0] * ab[0] + q[1] * ab[1]) / len2).clamp(0.0, 1.0);
                    let k = j * w + i;
                    if (q[0] - ab[0] * t).hypot(q[1] - ab[1] * t) < r && is_pavement_like(rgb[k], 0.0) && tone.matches(rgb[k]) {
                        paved.v[k] = true;
                    }
                }
            }
        }
        let near_taxiways = leaf.dilate((TAXIWAYS_PAD_M / px_m) as usize);
        for (k, p) in paved.v.iter_mut().enumerate() {
            *p = *p || (near_taxiways.v[k] && is_pavement_like(rgb[k], PAVEMENT_MIN_LUM) && tones.iter().any(|t| t.matches(rgb[k])));
        }
        let k = (ROAD_M / px_m / 2.0).round() as usize;
        let mut surface = Grid::grow(&seeds, &paved.erode(k).dilate(k), (PAVED_REACH_M / px_m) as usize);
        surface.or(&seeds);
        // A smooth edge: gaps and notches up to 2 · CLOSE_EDGE_M closed (no opening everywhere: it would cut the narrow
        // taxiways; the grow from the runways already leaves loose specks out). Along the runways' sides (SHOULDER_M
        // beyond the edges) the shoulders' worn grey makes a wavy fringe: there the surface is also opened over
        // SHOULDER_OPEN_M, which keeps the taxiway junctions (wider) and drops the fringe, so the runway edge is straight.
        let c = (CLOSE_EDGE_M / px_m).round() as usize;
        let mut surface = surface.dilate(c).erode(c);
        let band = seeds.dilate((SHOULDER_M / px_m).round() as usize);
        let o = (SHOULDER_OPEN_M / px_m).round() as usize;
        let opened = surface.erode(o).dilate(o);
        for k in 0..w * h {
            if band.v[k] && !seeds.v[k] {
                surface.v[k] = opened.v[k];
            }
        }
        let concrete = surface.v.iter().zip(&rgb).map(|(&p, &c)| p && is_apron(c) && !is_asphalt(c)).collect();
        out.push(Base { name: sec.name.clone(), lineup, runway_deg: ibx_f(sec, "RunwayNumber").unwrap_or(0.0), runways, taxi, paved: surface, concrete, origin: corner, px_m });
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 4 km × 4 km site (units) with one runway leaf, a paved apron beside it, a grey road leading away and a unit
    /// near the apron: the footprint covers the leaf, the apron and the unit plus the margin, and not the road's far
    /// end nor the far corner.
    #[test]
    fn footprint_covers_the_base_not_the_country() {
        let size = 3200u32; // units (≈ 4 km)
        let rect = [0, 0, size, size];
        let leaf = vec![[800.0, 1500.0], [2400.0, 1500.0], [2400.0, 1600.0], [800.0, 1600.0]];
        let grass = [90.0, 120.0, 60.0];
        let grey = [120.0, 120.0, 124.0];
        let art = |x0: i64, y0: i64, w: usize, h: usize| {
            (0..w * h)
                .map(|k| {
                    let (tx, ty) = (((x0 + (k % w) as i64) * 4) as f64, ((y0 + (k / w) as i64) * 4) as f64);
                    let apron = (1200.0..1600.0).contains(&tx) && (1600.0..1800.0).contains(&ty);
                    let road = (2000.0..3200.0).contains(&tx) && (600.0..604.0).contains(&ty);
                    if apron || road { grey } else { grass }
                })
                .collect()
        };
        let units = [[1700.0, 1700.0], [3000.0, 200.0]];
        let f = footprint(rect, &art, &[leaf], &[], &units).unwrap();
        let m = MARGIN_M / UNITS_TO_METRES;
        assert!(f.at(1600.0, 1550.0) && f.at(1400.0, 1750.0), "leaf and apron");
        assert!(f.at(1400.0, 1800.0 + 0.8 * m), "margin beyond the apron");
        assert!(f.at(1700.0 + 40.0, 1700.0), "the unit near the base");
        assert!(!f.at(3000.0, 200.0), "a unit far away");
        assert!(!f.at(3100.0, 602.0), "the road's far end");
        assert!(!f.at(1600.0, 1600.0 + 450.0 + m + 100.0), "the grass beyond the margin");
        // ≈ the base's bounding box grown by the close and the margin, far less than the site.
        assert!(f.area_km2() < 0.25 * 16.0, "{} km²", f.area_km2());
    }

    #[test]
    fn paved_pixels() {
        assert!(is_paved([120.0, 118.0, 125.0]) && is_paved([136.0, 97.0, 137.0]));
        assert!(!is_paved([150.0, 110.0, 70.0]) && !is_paved([60.0, 110.0, 50.0]) && !is_paved([20.0, 20.0, 22.0]));
    }

    /// A field with a 3000 × 60 m runway at 050° (dark asphalt, light shoulders), a 25 m parallel taxiway 150 m off,
    /// and a crossing 2400 × 50 m runway at 150°: both runways found, at their headings, lengths and widths; the
    /// taxiway is no runway. The numbers follow the headings.
    #[test]
    fn runways_from_a_picture() {
        let (px, n) = (5.0, 1200usize); // 6 km
        let field = [150.0, 110.0, 70.0];
        let shoulder = [190.0, 180.0, 160.0];
        let asphalt = [70.0, 70.0, 75.0];
        let lines = [
            ([3000.0, -3000.0], 50.0f64, 3000.0, 60.0),
            ([3200.0, -3100.0], 150.0, 2400.0, 50.0),
        ];
        let taxi = ([3000.0 + 150.0 * 140f64.to_radians().sin(), -3000.0 + 150.0 * 140f64.to_radians().cos()], 50.0f64, 2800.0, 25.0);
        let inside = |q: [f64; 2], (c, h, len, w): ([f64; 2], f64, f64, f64), pad: f64| {
            let (d, a) = ([h.to_radians().sin(), h.to_radians().cos()], [h.to_radians().cos(), -h.to_radians().sin()]);
            let r = [q[0] - c[0], q[1] - c[1]];
            (r[0] * d[0] + r[1] * d[1]).abs() < len / 2.0 + pad && (r[0] * a[0] + r[1] * a[1]).abs() < w / 2.0 + pad
        };
        let rgb: Vec<[f32; 3]> = (0..n * n)
            .map(|k| {
                let q = [(k % n) as f64 * px, -((k / n) as f64) * px];
                if lines.iter().any(|l| inside(q, *l, 0.0)) || inside(q, taxi, 0.0) {
                    asphalt
                } else if lines.iter().any(|l| inside(q, *l, 15.0)) {
                    shoulder
                } else {
                    field
                }
            })
            .collect();
        let mask: Vec<bool> = rgb.iter().map(|&c| is_asphalt(c)).collect();
        let pic = Picture { rgb: &rgb, asphalt: &mask, w: n, h: n, px_m: px, origin: [0.0, 0.0] };
        let mut found = pic.runways(Some(([3000.0 - 1400.0 * 50f64.to_radians().sin(), -3000.0 - 1400.0 * 50f64.to_radians().cos()], 50.0)));
        found.sort_by(|a, b| b.length().total_cmp(&a.length()));
        assert_eq!(found.len(), 2, "{found:?}");
        for (r, (_, h, len, w)) in found.iter().zip(lines) {
            let dh = (r.heading() - h).rem_euclid(180.0);
            assert!(dh.min(180.0 - dh) < 0.2, "heading {} vs {h}", r.heading());
            assert!((r.length() - len).abs() < 10.0, "length {} vs {len}", r.length());
            assert!((r.width - w).abs() < 6.0, "width {} vs {w}", r.width);
        }
        let n0 = found[0].numbers();
        assert!(n0 == [5, 23] || n0 == [23, 5], "{n0:?}");
        // The anchor gives the 050 runway its direction from the lineup point: ends[0] is the lineup end.
        assert!((found[0].heading() - 50.0).abs() < 0.2, "{}", found[0].heading());
    }

    #[test]
    fn numbers_from_headings() {
        let r = |h: f64| {
            let d = [h.to_radians().sin(), h.to_radians().cos()];
            Runway { ends: [[0.0, 0.0], [d[0] * 3000.0, d[1] * 3000.0]], width: 50.0, thresholds: [0.0; 2] }
        };
        assert_eq!(r(90.0).numbers(), [9, 27]);
        assert_eq!(r(4.0).numbers(), [36, 18]);
        assert_eq!(r(229.6).numbers(), [23, 5]);
        assert!(r(150.0).through([1500.0 * 150f64.to_radians().sin() + 10.0, 1500.0 * 150f64.to_radians().cos()], 330.0));
    }

    /// The converted data (`iaf-terrain airbases` → assets/converted/terrain/airbases.json), when present: every iaf.ibx
    /// base has a runway through its lineup point at RunwayNumber; at Ramat David and Ramon the runways run at the
    /// headings between the original's painted runway digits (docs/formats/ptt.md "Runway number fix"; world units,
    /// y south) within 0.5°, longer than the digits' spacing (the paved ends lie beyond the digits) by less than 1 km.
    #[test]
    fn runways_of_the_real_bases() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        let Ok(text) = std::fs::read(root.join("converted/terrain/airbases.json")) else {
            eprintln!("skipped: no assets/converted/terrain/airbases.json");
            return;
        };
        let j: serde_json::Value = serde_json::from_slice(&text).unwrap();
        let p = |v: &serde_json::Value| [v[0].as_f64().unwrap(), v[1].as_f64().unwrap()];
        let bases: Vec<(String, [f64; 2], f64, Vec<Runway>)> = j["bases"]
            .as_array()
            .unwrap()
            .iter()
            .map(|b| {
                let rw = b["runways"].as_array().unwrap().iter().map(|r| Runway { ends: [p(&r["ends"][0]), p(&r["ends"][1])], width: r["width"].as_f64().unwrap(), thresholds: [0.0; 2] });
                (b["name"].as_str().unwrap().to_string(), p(&b["lineup"]), b["runway_deg"].as_f64().unwrap(), rw.collect())
            })
            .collect();
        assert_eq!(bases.len(), 10);
        for (name, lineup, deg, rw) in &bases {
            assert!(rw.iter().any(|r| r.through(*lineup, *deg)), "{name}: no runway through the lineup");
        }
        let digit_pairs = [
            ("David", [418606.0, 355638.0], [421704.0, 355638.0]),
            ("David", [420444.0, 355034.0], [421812.0, 357394.0]),
            ("David", [418848.0, 356435.0], [419875.0, 354652.0]),
            ("Ramon", [388240.0, 511379.0], [390312.0, 509643.0]),
            ("Ramon", [388000.0, 512258.0], [389980.0, 510595.0]),
        ];
        for (name, a, z) in digit_pairs {
            let b = &bases.iter().find(|b| b.0 == name).unwrap().3;
            let (dx, dn): (f64, f64) = (z[0] - a[0], a[1] - z[1]);
            let hdg = dx.atan2(dn).to_degrees().rem_euclid(360.0);
            let spacing = dx.hypot(dn) * UNITS_TO_METRES;
            let mid = [(a[0] + z[0]) / 2.0 * UNITS_TO_METRES - 166850.0, 1043780.0 - (a[1] + z[1]) / 2.0 * UNITS_TO_METRES];
            let r = b.iter().find(|r| r.through(mid, hdg)).unwrap_or_else(|| panic!("{name}: no runway at {hdg:.1}°"));
            let dh = (r.heading() - hdg).rem_euclid(180.0);
            assert!(dh.min(180.0 - dh) < 0.5, "{name} {hdg:.1}°: {:.2}°", r.heading());
            assert!(r.length() > spacing && r.length() < spacing + 1000.0, "{name} {hdg:.1}°: {:.0} m vs digits {spacing:.0} m", r.length());
        }
    }
}
