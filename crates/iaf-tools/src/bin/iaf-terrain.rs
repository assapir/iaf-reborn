//! Terrain tools for `map.ptt`.
//!
//! `iaf-terrain theatre <map.ptt> <out-dir> [threads]` — every level and every inset of the file as
//! a quadtree of 1024-pixel nodes (docs/formats/ptt.md "Converted layout"): colour JPEGs per level,
//! raw heights for the whole-theatre levels 6..11, `meta.json`.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};

use anyhow::{Context, Result, bail};
use iaf_formats::ptt::{Level, Ptt, TILE_PIXELS, TileEntry};
use image::RgbImage;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [_, "theatre", path, out] => theatre(path, Path::new(out), default_threads()),
        [_, "theatre", path, out, threads] => theatre(path, Path::new(out), threads.parse()?),
        [_, "georef-points", theatre, z9, z10, out, lambda] => {
            georef_points(Path::new(theatre), Path::new(z9), Path::new(z10), Path::new(out), lambda.parse()?)
        }
        [_, "geo", points, x, y] => {
            // Engine metres (X east, Y north) -> lon / lat with the given control points.
            let (pts, lambda) = iaf_tools::georef::parse(&std::fs::read_to_string(points)?)?;
            let g = iaf_tools::georef::Georef::fit(pts, lambda)?;
            let u = iaf_tools::georef::UNITS_TO_METRES;
            let [lon, lat] = g.to_geo((x.parse::<f64>()? + 166850.0) / u, (1043780.0 - y.parse::<f64>()?) / u);
            println!("{lat:.6} {lon:.6}");
            Ok(())
        }
        _ => bail!(
            "usage: iaf-terrain theatre <map.ptt> <out-dir> [threads]\n       \
             iaf-terrain georef-points <theatre-dir> <eox-z9-dir> <eox-z10-dir> <out.json> <lambda>"
        ),
    }
}

/// `iaf-terrain georef-points`: measures the automatic georeference control points (docs/georef.md
/// §2) and writes them with the hand-measured points already in `out` (kind other than "auto",
/// kept as they are; none so far).
fn georef_points(theatre: &Path, z9: &Path, z10: &Path, out: &Path, lambda: f64) -> Result<()> {
    use iaf_tools::georef_measure as gm;
    let coarse = gm::Pair::load(theatre, 7, z9, 9, 6.0)?;
    let fine = gm::Pair::load(theatre, 6, z10, 10, 6.0)?;
    // Level 8 (318 m) with 20 km patches: the coarse, painted parts of the original (Cyprus, the
    // Nile valley) where the finer passes find nothing.
    let rough = gm::Pair::load(theatre, 8, z9, 9, 16.0)?;
    let mut rough_ms = Vec::new();
    let extra: Vec<iaf_tools::georef::Point> = match std::fs::read_to_string(out) {
        Ok(s) => iaf_tools::georef::parse(&s)?.0.into_iter().filter(|p| p.kind != "auto").collect(),
        Err(_) => Vec::new(),
    };
    let threads = default_threads();
    let mut warp = gm::initial()?;
    let mut kept = Vec::new();
    for (pair, step, margin, k, floor) in [
        (&coarse, 32768.0, 40, 3.0, 300.0),
        (&coarse, 16384.0, 8, 3.0, 150.0),
        (&fine, 12288.0, 6, 3.0, 80.0),
        (&fine, 12288.0, 3, 3.0, 60.0),
    ] {
        let mut ms = gm::pass(pair, &warp, step, margin, threads);
        if pair.level == 6 {
            if rough_ms.is_empty() {
                rough_ms = gm::pass(&rough, &warp, 24576.0, 30, threads);
            }
            // Coarse points only where the fine pass has none within 20 km.
            let near = |m: &gm::Match| ms.iter().any(|f: &gm::Match| (f.game[0] - m.game[0]).hypot(f.game[1] - m.game[1]) < 16000.0);
            let add: Vec<gm::Match> = rough_ms.iter().filter(|m| m.ncc >= 0.5 && !near(m)).map(|m| gm::Match { game: m.game, geo: m.geo, ncc: m.ncc, level: m.level }).collect();
            ms.extend(add);
        }
        let n = ms.len();
        let (g, ks) = gm::robust_fit(ms, &extra, lambda, k, floor)?;
        let mut r = g.residuals_m();
        r.sort_by(f64::total_cmp);
        let rms = (r.iter().map(|x| x * x).sum::<f64>() / r.len() as f64).sqrt();
        println!(
            "pass L{} step {step} margin {margin}: {n} matches, {} kept; residual rms {rms:.0} m, median {:.0} m, max {:.0} m",
            pair.level,
            ks.len(),
            r[r.len() / 2],
            r[r.len() - 1]
        );
        warp = g;
        kept = ks;
    }
    // Hold-out check: fit on 4/5 of the points, residuals of the other fifth (docs/georef.md §3).
    let all = gm::to_points(&kept);
    let mut held = Vec::new();
    let mut worst = Vec::new();
    for f in 0..5 {
        let train: Vec<_> = all.iter().enumerate().filter(|(i, _)| i % 5 != f).map(|(_, p)| p.clone()).chain(extra.iter().cloned()).collect();
        let g = iaf_tools::georef::Georef::fit(train, lambda)?;
        for p in all.iter().skip(f).step_by(5) {
            let q = g.to_game(p.geo[0], p.geo[1]);
            let e = (q[0] - p.game[0]).hypot(q[1] - p.game[1]) * iaf_tools::georef::UNITS_TO_METRES;
            held.push(e);
            worst.push((e, p.id.clone(), p.geo));
        }
    }
    held.sort_by(f64::total_cmp);
    let rms = (held.iter().map(|x| x * x).sum::<f64>() / held.len() as f64).sqrt();
    worst.sort_by(|a, b| b.0.total_cmp(&a.0));
    for (e, id, g) in worst.iter().take(8) {
        println!("  hold-out {e:.0} m at {id} ({:.3} N {:.3} E)", g[1], g[0]);
    }
    println!("hold-out: rms {rms:.0} m, median {:.0} m, 95% {:.0} m, max {:.0} m", held[held.len() / 2], held[held.len() * 95 / 100], held[held.len() - 1]);
    let mut pts: Vec<serde_json::Value> = gm::to_points(&kept)
        .iter()
        .zip(&kept)
        .map(|(p, m)| serde_json::json!({"id": p.id, "kind": p.kind, "tx": p.game[0], "ty": p.game[1],
            "lon": (p.geo[0] * 1e6).round() / 1e6, "lat": (p.geo[1] * 1e6).round() / 1e6, "ncc": (m.ncc * 100.0).round() / 100.0}))
        .collect();
    pts.extend(extra.iter().map(|p| serde_json::json!({"id": p.id, "kind": p.kind, "tx": p.game[0], "ty": p.game[1], "lon": p.geo[0], "lat": p.geo[1]})));
    let json = serde_json::json!({
        "about": "Georeference control points (docs/georef.md): terrain units (tx east, ty south) <-> WGS84 lon/lat. \
                  auto = correlation of the original level-6/7/8 imagery with EOxCloudless 2017 (iaf-terrain georef-points).",
        "lambda": lambda,
        "points": pts,
    });
    let mut s = serde_json::to_string(&json)?;
    // One point per line (readable diffs).
    s = s.replace("},{\"id\"", "},\n{\"id\"").replace("[{\"id\"", "[\n{\"id\"");
    std::fs::write(out, s + "\n")?;
    println!("{} points -> {}", pts.len(), out.display());
    Ok(())
}

fn default_threads() -> usize {
    std::thread::available_parallelism().map_or(4, |n| n.get())
}

/// Node side in pixels: a node of level L covers `NODE_PIXELS << L` terrain units (2^L units per
/// pixel, the resolution of map.ptt level L), on a grid aligned to the theatre origin.
const NODE_PIXELS: u32 = 1024;
/// Whole-theatre levels exported as nodes (colour + own heights): all of them, 6..11.
const THEATRE_LEVELS: std::ops::RangeInclusive<u32> = 6..=11;
/// Finest level with elevation data; every inset's heights derive from it (FUN_004281e0).
const HEIGHT_LEVEL: u32 = 6;
/// Levels whose nodes get the runway-number fixes (the airbase insets; coarser the digits are
/// under 4 px).
const RUNWAY_FIX_MAX_LEVEL: u32 = 2;
/// Source pixels read beyond a crop so the Lanczos kernel (3 lobes) sees real neighbours: a
/// composition is then the same whatever rectangle it is made for (seamless across nodes).
const RESAMPLE_MARGIN: u32 = 4;
const JPEG_QUALITY: u8 = 90;

fn node_span(level: u32) -> u32 {
    NODE_PIXELS << level
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
struct Node {
    level: u32,
    i: u32,
    j: u32,
}

impl Node {
    fn rect(&self) -> [u32; 4] {
        let s = node_span(self.level);
        [self.i * s, self.j * s, (self.i + 1) * s, (self.j + 1) * s]
    }
    fn dir(&self) -> String {
        format!("L{}", self.level)
    }
}

/// Everything the workers share: the level records and their tile indices.
struct Source {
    path: PathBuf,
    levels: Vec<Level>,
    tiles: Vec<Vec<TileEntry>>,
    theatre: [u32; 4],
    fixes: Vec<iaf_tools::runway_fix::Fix>,
}

impl Source {
    fn theatre_level(&self, level: u32) -> Option<usize> {
        self.levels.iter().position(|l| l.flag == 1 && l.level == level)
    }

    /// Records painted into a node of `level` covering `cell`, coarse to fine: the theatre level
    /// (level 6 for inset nodes), then the insets of levels 5..`level` that overlap, starting at
    /// the finest record that covers the whole cell (everything under it is hidden).
    fn painters(&self, level: u32, cell: &[u32; 4]) -> Vec<usize> {
        let base = self.theatre_level(level.max(HEIGHT_LEVEL)).expect("theatre level");
        let mut v = vec![base];
        if level < HEIGHT_LEVEL {
            let mut insets: Vec<usize> = (0..self.levels.len())
                .filter(|&k| {
                    let l = &self.levels[k];
                    l.flag == 0 && l.level >= level && l.level < HEIGHT_LEVEL && overlaps(&l.rect, cell)
                })
                .collect();
            insets.sort_by_key(|&k| std::cmp::Reverse(self.levels[k].level));
            v.extend(insets);
        }
        let start = v.iter().rposition(|&k| contains(&self.levels[k].rect, cell)).unwrap_or(0);
        v.split_off(start)
    }
}

/// `iaf-terrain theatre`: see the module doc and docs/formats/ptt.md.
fn theatre(path: &str, out: &Path, threads: usize) -> Result<()> {
    let t0 = std::time::Instant::now();
    let mut ptt = Ptt::open(path)?;
    let levels = ptt.levels.clone();
    let tiles = levels.iter().map(|l| ptt.tiles(l)).collect::<Result<Vec<_>, _>>()?;
    let theatre = levels
        .iter()
        .find(|l| l.flag == 1 && l.level == HEIGHT_LEVEL)
        .context("no whole-theatre level 6")?
        .rect;
    let src = Source { path: path.into(), levels, tiles, theatre, fixes: iaf_tools::runway_fix::load()? };

    // Nodes: every node of a theatre level inside the theatre; for inset levels, every node an
    // inset record of exactly that level touches.
    let mut nodes = std::collections::BTreeSet::new();
    for l in &src.levels {
        let lv = l.level;
        let wanted = if l.flag == 1 { THEATRE_LEVELS.contains(&lv) } else { lv < HEIGHT_LEVEL };
        if !wanted {
            continue;
        }
        let s = node_span(lv);
        for j in l.rect[1] / s..l.rect[3].div_ceil(s) {
            for i in l.rect[0] / s..l.rect[2].div_ceil(s) {
                nodes.insert(Node { level: lv, i, j });
            }
        }
    }
    let nodes: Vec<Node> = nodes.into_iter().collect();
    if out.exists() {
        std::fs::remove_dir_all(out)?;
    }
    for lv in 0..=*THEATRE_LEVELS.end() {
        std::fs::create_dir_all(out.join(format!("L{lv}")))?;
    }

    let next = AtomicUsize::new(0);
    let log = Mutex::new(Vec::<String>::new());
    let bytes = AtomicUsize::new(0);
    std::thread::scope(|s| -> Result<()> {
        let workers: Vec<_> = (0..threads.max(1))
            .map(|_| {
                s.spawn(|| -> Result<()> {
                    let mut ptt = Ptt::open(&src.path)?;
                    loop {
                        let k = next.fetch_add(1, Ordering::Relaxed);
                        let Some(&node) = nodes.get(k) else { return Ok(()) };
                        let (n, msgs) = write_node(&mut ptt, &src, node, out).with_context(|| format!("{node:?}"))?;
                        bytes.fetch_add(n, Ordering::Relaxed);
                        log.lock().unwrap().extend(msgs);
                    }
                })
            })
            .collect();
        for w in workers {
            w.join().map_err(|_| anyhow::anyhow!("worker panicked"))??;
        }
        Ok(())
    })?;

    let mut per_level: HashMap<u32, Vec<[u32; 2]>> = HashMap::new();
    for n in &nodes {
        per_level.entry(n.level).or_default().push([n.i, n.j]);
    }
    let meta = serde_json::json!({
        "theatre": src.theatre,
        "node_pixels": NODE_PIXELS,
        "height_level": HEIGHT_LEVEL,
        "height_levels": THEATRE_LEVELS.collect::<Vec<_>>(),
        "root_level": THEATRE_LEVELS.end(),
        // Nodes with a colour texture, per level ("L": [[i, j], ...]); node (L, i, j) covers terrain
        // units [i, i+1) × [j, j+1) · (1024 << L).
        "nodes": (0..=*THEATRE_LEVELS.end()).map(|l| (l.to_string(), serde_json::json!(per_level.remove(&l).unwrap_or_default())))
            .collect::<serde_json::Map<_, _>>(),
        // Engine world (metres, X east / Y north) from terrain units (FUN_004053f0/…420):
        //   X = tx * units_to_metres + x_shift ;  Y = y_shift - ty * units_to_metres
        // Heights: metres = (raw - sea_level_raw) / height_scale * units_to_metres
        // (checked: Ramat David runway 63.7 m vs 63 m in takeoff.mis).
        "units_to_metres": 1.2411389,
        "x_shift": -166850,
        "y_shift": 1043780,
        "sea_level_raw": 20342,
        "height_scale": 9.2575,
    });
    std::fs::write(out.join("meta.json"), serde_json::to_string(&meta)?)?;
    let mut msgs = log.into_inner().unwrap();
    msgs.sort();
    for m in &msgs {
        println!("{m}");
    }
    let mut counts = String::new();
    for lv in 0..=*THEATRE_LEVELS.end() {
        counts += &format!(" L{lv}:{}", nodes.iter().filter(|n| n.level == lv).count());
    }
    println!(
        "{} nodes ({counts} ), {:.0} MB, {:.0} s -> {}",
        nodes.len(),
        bytes.load(Ordering::Relaxed) as f64 / 1e6,
        t0.elapsed().as_secs_f64(),
        out.display()
    );
    Ok(())
}

/// Writes one node: `L<l>/c_<i>_<j>.jpg` (colour) and, for the theatre levels, `L<l>/h_<i>_<j>.png`
/// (raw u16 heights, 1025² including the neighbour's first row/column so node edges match; R = high
/// byte, G = low byte, lossless). Returns the bytes written and log lines.
fn write_node(ptt: &mut Ptt, src: &Source, node: Node, out: &Path) -> Result<(usize, Vec<String>)> {
    use image::codecs::jpeg::JpegEncoder;
    let cell = node.rect();
    let upp = 1u32 << node.level;
    let painters = src.painters(node.level, &cell);
    let mut img = compose(ptt, src, &painters, cell, upp)?;
    let mut msgs = Vec::new();
    if node.level <= RUNWAY_FIX_MAX_LEVEL {
        for fix in src.fixes.iter().filter(|f| f.intersects(&cell)) {
            // The unfixed imagery around the patch, composed on the node's own pixel lattice.
            let r = clip(&fix.source_rect(RESAMPLE_MARGIN * upp, upp), &src.theatre);
            let around = compose(ptt, src, &src.painters(node.level, &r), r, upp)?;
            fix.apply(&mut img, [cell[0], cell[1]], &around, [r[0], r[1]], upp as f64);
            msgs.push(format!("L{}/c_{}_{}: runway number fix '{}'", node.level, node.i, node.j, fix.name));
        }
    }
    let dir = out.join(node.dir());
    let colour = dir.join(format!("c_{}_{}.jpg", node.i, node.j));
    let mut f = std::io::BufWriter::new(std::fs::File::create(&colour)?);
    img.write_with_encoder(JpegEncoder::new_with_quality(&mut f, JPEG_QUALITY))?;
    drop(f);
    let mut n = std::fs::metadata(&colour)?.len() as usize;
    if THEATRE_LEVELS.contains(&node.level) {
        let k = src.theatre_level(node.level).context("theatre level")?;
        let h = node_heights(ptt, &src.levels[k], &src.tiles[k], node)?;
        let p = dir.join(format!("h_{}_{}.png", node.i, node.j));
        h.save(&p)?;
        n += std::fs::metadata(&p)?.len() as usize;
    }
    Ok((n, msgs))
}

/// The node's own-level heights, 1025² texels at the level's pixel spacing, packed RG. Texel x of
/// the node is level pixel `i·1024 + x` (clamped to the level: the theatre's east / south edge
/// repeats its last pixel).
fn node_heights(ptt: &mut Ptt, level: &Level, tiles: &[TileEntry], node: Node) -> Result<RgbImage> {
    let n = TILE_PIXELS;
    let (cols, rows) = (level.columns(), level.rows());
    let mut cache: HashMap<u32, Option<Vec<u16>>> = HashMap::new();
    let mut img = RgbImage::new(NODE_PIXELS + 1, NODE_PIXELS + 1);
    for y in 0..=NODE_PIXELS {
        let py = (node.j * NODE_PIXELS + y).min(rows * n - 1);
        for x in 0..=NODE_PIXELS {
            let px = (node.i * NODE_PIXELS + x).min(cols * n - 1);
            let k = (py / n) * cols + px / n;
            if let std::collections::hash_map::Entry::Vacant(e) = cache.entry(k) {
                e.insert(ptt.tile_heights(&tiles[k as usize])?);
            }
            let v = cache[&k].as_ref().map_or(20342, |h| h[((py % n) * n + px % n) as usize]);
            img.put_pixel(x, y, image::Rgb([(v >> 8) as u8, (v & 0xff) as u8, 0]));
        }
    }
    Ok(img)
}

/// Paints the world rect `cell` at `upp` units per pixel from the records `painters` (coarse to
/// fine). Each record is mosaicked at its own resolution around the cell (plus
/// `RESAMPLE_MARGIN` source pixels) and Lanczos-resampled to `upp`; areas no record covers stay
/// black.
fn compose(ptt: &mut Ptt, src: &Source, painters: &[usize], cell: [u32; 4], upp: u32) -> Result<RgbImage> {
    use image::imageops::{FilterType, resize};
    let (w, h) = ((cell[2] - cell[0]) / upp, (cell[3] - cell[1]) / upp);
    let mut img = RgbImage::new(w, h);
    for &k in painters {
        let l = &src.levels[k];
        if !overlaps(&l.rect, &cell) {
            continue;
        }
        let r = clip(&l.rect, &cell);
        let sup = l.tile_span() / TILE_PIXELS; // units per source pixel
        let f = sup / upp; // magnification (a power of two, >= 1)
        // Source pixels to read: r plus the margin, within the record.
        let (lw, lh) = (l.columns() * TILE_PIXELS, l.rows() * TILE_PIXELS);
        let sx0 = ((r[0] - l.rect[0]) / sup).saturating_sub(RESAMPLE_MARGIN);
        let sy0 = ((r[1] - l.rect[1]) / sup).saturating_sub(RESAMPLE_MARGIN);
        let sx1 = ((r[2] - l.rect[0]).div_ceil(sup) + RESAMPLE_MARGIN).min(lw);
        let sy1 = ((r[3] - l.rect[1]).div_ceil(sup) + RESAMPLE_MARGIN).min(lh);
        let mut mosaic = RgbImage::new(sx1 - sx0, sy1 - sy0);
        let n = TILE_PIXELS;
        for tr in sy0 / n..sy1.div_ceil(n) {
            for tc in sx0 / n..sx1.div_ceil(n) {
                let t = &src.tiles[k][(tr * l.columns() + tc) as usize];
                let Ok(tile) = ptt.tile_jpeg(t).map_err(anyhow::Error::from).and_then(|j| Ok(image::load_from_memory(&j)?.to_rgb8()))
                else {
                    continue;
                };
                // Copy the part of the tile inside [sx0, sx1) × [sy0, sy1).
                for y in 0..n {
                    let gy = tr * n + y;
                    if gy < sy0 || gy >= sy1 {
                        continue;
                    }
                    for x in 0..n {
                        let gx = tc * n + x;
                        if gx >= sx0 && gx < sx1 {
                            mosaic.put_pixel(gx - sx0, gy - sy0, *tile.get_pixel(x, y));
                        }
                    }
                }
            }
        }
        let scaled = if f == 1 { mosaic } else { resize(&mosaic, (sx1 - sx0) * f, (sy1 - sy0) * f, FilterType::Lanczos3) };
        // Paste r: output pixel (x, y) of the cell is scaled pixel (x + ox, y + oy).
        let ox = (cell[0] as i64 - (l.rect[0] + sx0 * sup) as i64) / upp as i64;
        let oy = (cell[1] as i64 - (l.rect[1] + sy0 * sup) as i64) / upp as i64;
        for y in (r[1] - cell[1]) / upp..(r[3] - cell[1]) / upp {
            for x in (r[0] - cell[0]) / upp..(r[2] - cell[0]) / upp {
                img.put_pixel(x, y, *scaled.get_pixel((x as i64 + ox) as u32, (y as i64 + oy) as u32));
            }
        }
    }
    Ok(img)
}

fn overlaps(a: &[u32; 4], b: &[u32; 4]) -> bool {
    a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3]
}

fn contains(a: &[u32; 4], b: &[u32; 4]) -> bool {
    a[0] <= b[0] && a[1] <= b[1] && a[2] >= b[2] && a[3] >= b[3]
}

fn clip(a: &[u32; 4], b: &[u32; 4]) -> [u32; 4] {
    [a[0].max(b[0]), a[1].max(b[1]), a[2].min(b[2]), a[3].min(b[3])]
}
