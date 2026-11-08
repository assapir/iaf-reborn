//! `iaf-sim terrain` (iaf-2026/docs/terrain.md): Modern IAF's theatre from open data, in the shape `terrain::theatre`
//! writes (docs/formats/ptt.md "Converted layout": colour nodes `L<l>/c_<i>_<j>.jpg`, 16-bit height nodes
//! `L<l>/h_<i>_<j>.png` for the levels 6–11, `meta.json`), so `shared/terrain/terrain.gd` and `IafHeights` read it
//! unchanged.
//!
//! The frame is UTM zone 36N (EPSG:32636) at 1 terrain unit = 1 m: terrain unit (tx, ty) is easting `E0 + tx`,
//! northing `N1 − ty`, so `meta.json`'s `x_shift` / `y_shift` are `E0` / `N1` and the engine's world X / Y are the
//! UTM easting / northing. Heights: Copernicus GLO-30 (cached under `assets/source/dem/`), warped to a 64 m grid.
//! Colour: ESA WorldCover's Sentinel-2 composite (range reads; 8 m nodes over the detail area, 32 m elsewhere) and
//! the Survey of Israel 2 m sheets already downloaded (2 m nodes). GDAL does every reprojection.

use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use anyhow::{Context, Result, bail};
use image::RgbImage;
use image::imageops::{FilterType, resize};

use crate::imagery::{self, read_envi};
use crate::imagery_run::{BUCKET, Sheet, gdal, list_sheets, list_tiles, tile_box, tile_sources, tile_whole};
use crate::log;
use crate::progress::{Part, Progress, check, utf8};

/// The theatre in UTM 36N metres (E0, N0, E1, N1): Ramon, Hatzerim, Nevatim and Ramat David with ≥ 150 km around
/// them, the corners on multiples of 1024 m (iaf-2026/docs/terrain.md §2).
pub const BOX: [f64; 4] = [507_904.0, 3_255_296.0, 855_040.0, 3_766_272.0];
/// Israel's bounding box (lon 34.2–35.95° E, lat 29.45–33.35° N) in UTM 36N, the "detail area": 8 m Sentinel-2
/// nodes in every level-5 node it touches, 32 m elsewhere.
pub const DETAIL: [f64; 4] = [611_000.0, 3_258_000.0, 786_500.0, 3_694_000.0];
const NODE_PIXELS: u32 = 1024;
const HEIGHT_LEVEL: u32 = 6;
const ROOT_LEVEL: u32 = 11;
/// Height grid spacing: the level-6 texel (2^6 units of 1 m).
const DEM_STEP: f64 = 64.0;
/// Raw height = SEA_LEVEL_RAW + metres · HEIGHT_SCALE (0.1 m steps, −500 m to 6,000 m).
const SEA_LEVEL_RAW: f64 = 5000.0;
const HEIGHT_SCALE: f64 = 10.0;
const JPEG_QUALITY: u8 = 88;
/// The Sentinel-2 composite has no pixels over open sea away from the coast: this colour fills them (the
/// composite's own open-sea tone near Ashdod, iaf-2026/docs/terrain.md §3).
const SEA: [u8; 3] = [30, 52, 78];
const DEM_URL: &str = "https://copernicus-dem-30m.s3.amazonaws.com";
const USER_AGENT: &str = "iaf-reborn Modern IAF terrain setup (curl)";
pub const ATTRIBUTION: [&str; 3] = [
    "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved",
    "Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium; ESA WorldCover project 2021 (CC BY 4.0)",
    "© Survey of Israel 2015, via data.gov.il",
];
/// Copernicus WorldDEM-30 licence, Article 6 (c): this sentence goes with every distribution.
pub const DEM_LIABILITY: &str = "The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30";

/// A node: level, i (east), j (south); it covers units [i, i+1) × [j, j+1) · (1024 << level).
type Key = (u32, u32, u32);

fn span(level: u32) -> f64 {
    f64::from(NODE_PIXELS << level)
}

/// The airbases' outlines (`boundary`, lat / lon, of `<dir>/*.json`, iaf-2026/docs/airbases.md) in UTM 36N.
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
        out.push(transform("EPSG:4326", "EPSG:32636", &pts)?);
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
    /// The airbases' layouts (`iaf-2026/data/airbases`): Sentinel-2 replaces the Survey photo inside their outlines.
    pub airbases: PathBuf,
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

/// The GLO-30 tile name of the 1° cell whose south-west corner is (lat, lon).
pub fn dem_tile(lat: i32, lon: i32) -> String {
    let (ns, ew) = (if lat < 0 { 'S' } else { 'N' }, if lon < 0 { 'W' } else { 'E' });
    format!("Copernicus_DSM_COG_10_{ns}{:02}_00_{ew}{:03}_00_DEM", lat.abs(), lon.abs())
}

/// Points through `gdaltransform` (x y in, x y out; EPSG:4326 as lon, lat).
fn transform(from: &str, to: &str, pts: &[[f64; 2]]) -> Result<Vec<[f64; 2]>> {
    let mut c = Command::new("gdaltransform")
        .args(["-s_srs", from, "-t_srs", to, "-output_xy"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .context("running gdaltransform (install GDAL)")?;
    let mut input = String::new();
    for p in pts {
        input += &format!("{} {}\n", p[0], p[1]);
    }
    // Written from a thread: gdaltransform answers line by line, so a full stdout pipe would block a writer that
    // reads nothing back (≈ 64 KB).
    let mut stdin = c.stdin.take().context("stdin")?;
    let writer = std::thread::spawn(move || stdin.write_all(input.as_bytes()));
    let o = c.wait_with_output()?;
    writer.join().map_err(|_| anyhow::anyhow!("gdaltransform writer panicked"))??;
    let out: Vec<[f64; 2]> = String::from_utf8_lossy(&o.stdout)
        .lines()
        .filter_map(|l| {
            let v: Vec<f64> = l.split_whitespace().filter_map(|s| s.parse().ok()).collect();
            (v.len() == 2).then(|| [v[0], v[1]])
        })
        .collect();
    if !o.status.success() || out.len() != pts.len() {
        bail!("gdaltransform {from} → {to} failed");
    }
    Ok(out)
}

/// The UTM rect's lon / lat bounding box (17 points per side).
fn geo_bbox(r: [f64; 4]) -> Result<[f64; 4]> {
    let mut pts = Vec::new();
    for t in 0..=16 {
        let f = f64::from(t) / 16.0;
        let (x, y) = (r[0] + (r[2] - r[0]) * f, r[1] + (r[3] - r[1]) * f);
        pts.extend([[x, r[1]], [x, r[3]], [r[0], y], [r[2], y]]);
    }
    let g = transform("EPSG:32636", "EPSG:4326", &pts)?;
    Ok(g.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
        [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
    }))
}

/// The DEM bucket has no tile for the cell (open sea): S3 answers a missing key with 404, or with 403 and NoSuchKey
/// in the body. Any other answer (a transient 403 too) must not mark the cell as sea for good.
fn no_tile(code: &str, body: &str) -> bool {
    code == "404" || (code == "403" && body.contains("NoSuchKey"))
}

/// The GLO-30 tiles over `geo` in the cache, fetched once each (a `.none` mark for a cell with no tile: open sea),
/// and the line saying what was reused and fetched.
fn fetch_dem(cache: &Path, geo: [f64; 4], pr: &dyn Progress, cancel: &AtomicBool) -> Result<(Vec<PathBuf>, String)> {
    std::fs::create_dir_all(cache)?;
    let (mut tiles, mut reused, mut fetched, mut sea) = (Vec::new(), 0u64, 0u64, 0);
    let mb = |p: &Path| std::fs::metadata(p).map_or(0, |m| m.len());
    for lat in geo[1].floor() as i32..=geo[3].floor() as i32 {
        for lon in geo[0].floor() as i32..=geo[2].floor() as i32 {
            check(cancel)?;
            let name = dem_tile(lat, lon);
            let (tif, none) = (cache.join(format!("{name}.tif")), cache.join(format!("{name}.none")));
            if tif.exists() {
                reused += mb(&tif);
                tiles.push(tif);
                continue;
            }
            if none.exists() {
                sea += 1;
                continue;
            }
            let part = cache.join(format!("{name}.part"));
            let url = format!("{DEM_URL}/{name}/{name}.tif");
            let mut child = Command::new("curl")
                .args(["-sS", "-L", "-A", USER_AGENT])
                .args(crate::thirdparty::CURL_PATIENCE)
                .args(["-w", "%{http_code}", "-o", utf8(&part)?, &url])
                .stdout(Stdio::piped())
                .spawn()
                .context("running curl")?;
            // The answer is a few bytes: the pipe never fills while curl runs.
            let mut out = child.stdout.take().context("curl's stdout")?;
            let status = crate::thirdparty::wait_curl(child, &part, &|| cancel.load(Ordering::Relaxed), &|| {})?;
            let mut code = String::new();
            std::io::Read::read_to_string(&mut out, &mut code)?;
            let code = code.trim().to_string();
            match code.as_str() {
                // A 200 cut short (a stall) is not a tile: only a clean exit renames the part.
                "200" if !status.success() => {
                    let _ = std::fs::remove_file(&part);
                    bail!("{url}: {}; run again", crate::thirdparty::curl_error(status));
                }
                "200" => {
                    std::fs::rename(&part, &tif)?;
                    fetched += mb(&tif);
                    log!(pr, "  DEM {name}: fetched {:.0} MB", mb(&tif) as f64 / 1e6);
                    tiles.push(tif);
                }
                _ if no_tile(&code, &std::fs::read_to_string(&part).unwrap_or_default()) => {
                    let _ = std::fs::remove_file(&part);
                    sea += 1;
                    std::fs::write(&none, "no GLO-30 tile (open sea)\n")?;
                }
                _ => bail!("{url}: HTTP {code} ({})", crate::thirdparty::curl_error(status)),
            }
        }
    }
    if tiles.is_empty() {
        bail!("no GLO-30 tile over {geo:?}");
    }
    let line = format!(
        "{} tiles, reused {:.0} MB, fetched {:.0} MB ({sea} open-sea cells)",
        tiles.len(),
        reused as f64 / 1e6,
        fetched as f64 / 1e6
    );
    Ok((tiles, line))
}

/// gdalwarp of `src` to the UTM rect `te` at `size` pixels into ENVI (band-interleaved by pixel) at `bin`.
fn warp(src: &str, te: [f64; 4], size: [usize; 2], extra: &[&str], bin: &Path) -> Result<imagery::Envi> {
    let te = te.map(|v| format!("{v}"));
    let ts = size.map(|v| v.to_string());
    let mut a = vec!["-q", "-overwrite", "-t_srs", "EPSG:32636", "-te", &te[0], &te[1], &te[2], &te[3]];
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
/// included), R = high byte, G = low byte, as `terrain::theatre`.
fn write_heights(f: &Frame, g: &HeightGrid, out: &Path, threads: usize, cancel: &AtomicBool) -> Result<()> {
    let nodes: Vec<Key> = (HEIGHT_LEVEL..=ROOT_LEVEL).flat_map(|l| f.nodes(l)).collect();
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
    let next = AtomicUsize::new(0);
    // Set by the first worker that fails: the others stop at their next item.
    let stop = AtomicBool::new(false);
    std::thread::scope(|s| -> Result<()> {
        let workers: Vec<_> = (0..threads.max(1))
            .map(|_| {
                s.spawn(|| -> Result<()> {
                    loop {
                        check(cancel)?;
                        if stop.load(Ordering::Relaxed) {
                            return Ok(());
                        }
                        let Some(it) = items.get(next.fetch_add(1, Ordering::Relaxed)) else { return Ok(()) };
                        if let Err(e) = f(it) {
                            stop.store(true, Ordering::Relaxed);
                            return Err(e);
                        }
                    }
                })
            })
            .collect();
        for w in workers {
            w.join().map_err(|_| anyhow::anyhow!("worker panicked"))??;
        }
        Ok(())
    })
}

fn colour_path(out: &Path, k: Key) -> PathBuf {
    out.join(format!("L{}/c_{}_{}.jpg", k.0, k.1, k.2))
}

fn save(img: &RgbImage, path: &Path) -> Result<()> {
    let mut f = std::io::BufWriter::new(std::fs::File::create(path)?);
    img.write_with_encoder(image::codecs::jpeg::JpegEncoder::new_with_quality(&mut f, JPEG_QUALITY))?;
    Ok(())
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

/// A parent node from its four children; a missing child is `fallback`'s (None: black, outside the theatre).
fn compose_parent(out: &Path, p: Key, fallback: Option<u32>) -> Result<RgbImage> {
    let n = NODE_PIXELS;
    let mut big = RgbImage::new(2 * n, 2 * n);
    for dy in 0..2 {
        for dx in 0..2 {
            let c = (p.0 - 1, 2 * p.1 + dx, 2 * p.2 + dy);
            let path = colour_path(out, c);
            let img = if path.exists() {
                Some(image::open(path)?.to_rgb8())
            } else {
                fallback.map(|l| ancestor_crop(out, c, l)).transpose()?
            };
            if let Some(img) = img {
                image::imageops::replace(&mut big, &img, i64::from(dx * n), i64::from(dy * n));
            }
        }
    }
    Ok(resize(&big, n, n, FilterType::Triangle))
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
    par(&ps, threads, cancel, |&p| save(&compose_parent(out, p, fallback)?, &colour_path(out, p)))
}

/// A unit's mark: its nodes are written (a run after a failure skips it).
fn done(work: &Path, what: &str, k: Key) -> PathBuf {
    work.join(format!("done_{what}_{}_{}_{}", k.0, k.1, k.2))
}

/// Sentinel-2 over one unit (a node of `unit.0`), cut into its nodes of `level` that `want` keeps.
fn sentinel_unit(
    vrt: &str,
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
    let m = NODE_PIXELS as usize;
    for sj in 0..1u32 << d {
        for si in 0..1u32 << d {
            let k = (level, (unit.1 << d) + si, (unit.2 << d) + sj);
            if !want(k) {
                continue;
            }
            let img = RgbImage::from_fn(NODE_PIXELS, NODE_PIXELS, |x, y| {
                let i = ((sj as usize * m + y as usize) * n + si as usize * m + x as usize) * 4;
                let b = |c: usize| f32::from(u16::from_le_bytes(px[i + c]));
                if [0, 1, 2].iter().all(|&c| b(c) == 0.0) {
                    return image::Rgb(SEA);
                }
                image::Rgb(imagery::tone([b(0), b(1), b(2)]).map(|v| v.round() as u8))
            });
            save(&img, &colour_path(out, k))?;
        }
    }
    Ok(())
}

/// What the Survey units share: the sheets' levels and colour match (per sheet extent, blended by `levels_at`) and
/// the airbases' outlines (UTM).
struct Survey<'a> {
    vrt: &'a str,
    levels: Vec<([f64; 4], [f32; 4])>,
    scales: Vec<([f64; 4], [f32; 4])>,
    offsets: Vec<([f64; 4], [f32; 4])>,
    bases: &'a [Vec<[f64; 2]>],
}

/// The published Survey photo paints the military bases over with made-up ground: Sentinel-2 shows instead inside
/// the bases' outlines and BASE_COVER_M beyond them, the Survey fading back in over the next BASE_FEATHER_M.
const BASE_COVER_M: f64 = 160.0;
const BASE_FEATHER_M: f64 = 160.0;
/// The mask's cell: the fade spans 16 of them, and a 2 m raster per unit would cost 2 × 268 MB per worker.
const BASE_CELL_M: f64 = 10.0;

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
                let b = p.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, q| {
                    [b[0].min(q[0]), b[1].min(q[1]), b[2].max(q[0]), b[3].max(q[1])]
                });
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

/// Per sheet: the scale and offset per band that give its levelled photo Sentinel-2's mean and spread (over the
/// sheet's dry land at 40 m, both on the sheet's grid; the scale clamped to 0.5–2); cached in `<work>/gains.tsv`.
/// A gain alone (the means' ratio) came out at 1.4–2 and burnt the bright desert white (2026-11-03).
fn sheet_gains(sheets: &[Sheet], s2: &str, work: &Path, threads: usize, cancel: &AtomicBool) -> Result<Vec<Gain>> {
    let cache = work.join("gains.tsv");
    let mut text = std::fs::read_to_string(&cache).unwrap_or_default();
    let todo: Vec<usize> = (0..sheets.len()).filter(|&k| cached_gain(&text, &sheets[k].name).is_none()).collect();
    let found = std::sync::Mutex::new(Vec::new());
    par(&todo, threads, cancel, |&k| {
        let s = &sheets[k];
        let b = s.bbox;
        let te = b.map(|v| format!("{v}"));
        // One pixel count for both (`-tr` rounds a sheet extent off the 40 m grid differently per source).
        let ts = [b[2] - b[0], b[3] - b[1]].map(|v| format!("{}", (v / 40.0).round().max(1.0)));
        let base =
            ["-q", "-overwrite", "-t_srs", "EPSG:2039", "-te", &te[0], &te[1], &te[2], &te[3], "-ts", &ts[0], &ts[1]];
        let read = |src: &str, extra: &[&str], tag: &str| -> Result<imagery::Envi> {
            let bin = work.join(format!("gain_{k}_{tag}.bin"));
            let mut a = base.to_vec();
            a.extend(["-of", "ENVI", "-co", "INTERLEAVE=BIP"]);
            a.extend(extra);
            a.extend([src, utf8(&bin)?]);
            gdal("gdalwarp", &a)?;
            let e = read_envi(&bin);
            for f in [bin.clone(), bin.with_extension("hdr"), PathBuf::from(format!("{}.aux.xml", bin.display()))] {
                let _ = std::fs::remove_file(f);
            }
            e
        };
        // Both averaged to 40 m, so their spreads compare (a nearest 2 m sample is far noisier than a 10 m average).
        let photo = read(
            &s.gdal,
            &["-s_srs", "EPSG:2039", "-r", "average", "-b", "1", "-b", "2", "-b", "3", "-srcnodata", "255 255 255"]
                .into_iter()
                .chain(["-wo", "UNIFIED_SRC_NODATA=YES", "-dstnodata", "0"])
                .collect::<Vec<_>>(),
            "p",
        )?;
        let sat = read(s2, &["-r", "average", "-srcnodata", "0", "-dstnodata", "0"], "s")?;
        // An RGBA sheet keeps its alpha band through gdalwarp: the photo's pixels are `bands` bytes apart.
        if photo.bands < 3
            || photo.dtype != "1"
            || sat.bands != 4
            || sat.dtype != "12"
            || (photo.w, photo.h) != (sat.w, sat.h)
        {
            bail!(
                "{}: colour match rasters differ ({} bands type {} / {} bands type {})",
                s.name,
                photo.bands,
                photo.dtype,
                sat.bands,
                sat.dtype
            );
        }
        let sat: Vec<u16> = sat.raw.as_chunks::<2>().0.iter().map(|b| u16::from_le_bytes(*b)).collect();
        // Per band: n, Σ, Σ² of the photo and of Sentinel-2.
        let (mut n, mut sp, mut sp2, mut ss, mut ss2) = (0f64, [0f64; 3], [0f64; 3], [0f64; 3], [0f64; 3]);
        for (i, p) in photo.raw.chunks_exact(photo.bands).map(|c| [c[0], c[1], c[2]]).enumerate() {
            let q = [sat[i * 4], sat[i * 4 + 1], sat[i * 4 + 2], sat[i * 4 + 3]].map(f32::from);
            if p == [255; 3] || p == [0; 3] || q[..3] == [0.0; 3] || imagery::is_water(q) {
                continue;
            }
            let lv = imagery::photo_levels(p.map(f32::from), s.levels);
            let t = imagery::tone([q[0], q[1], q[2]]);
            n += 1.0;
            for c in 0..3 {
                let (a, b) = (f64::from(lv[c]), f64::from(t[c]));
                (sp[c], sp2[c], ss[c], ss2[c]) = (sp[c] + a, sp2[c] + a * a, ss[c] + b, ss2[c] + b * b);
            }
        }
        let mut g = [1.0, 1.0, 1.0, 0.0, 0.0, 0.0];
        if n > 100.0 {
            for c in 0..3 {
                let (mp, ms) = (sp[c] / n, ss[c] / n);
                let sd = |s2: f64, m: f64| (s2 / n - m * m).max(1.0).sqrt();
                let k = (sd(ss2[c], ms) / sd(sp2[c], mp)).clamp(0.5, 2.0);
                (g[c], g[3 + c]) = (k as f32, (ms - mp * k) as f32);
            }
        }
        found.lock().map_err(|_| anyhow::anyhow!("worker panicked"))?.push((s.name.clone(), g));
        Ok(())
    })?;
    for (name, g) in found.into_inner().map_err(|_| anyhow::anyhow!("worker panicked"))? {
        text += &format!("{name}\t{} {} {} {} {} {}\n", g[0], g[1], g[2], g[3], g[4], g[5]);
    }
    std::fs::write(&cache, &text)?;
    sheets.iter().map(|s| cached_gain(&text, &s.name).context("sheet gain")).collect()
}

/// A sheet's colour match: scale and offset per band, as `levels_at` blends them ([r, g, b, 0]).
type Gain = ([f32; 4], [f32; 4]);

/// A sheet's line in gains.tsv (`<sheet>\t<scale r g b> <offset r g b>`; the last one counts).
fn cached_gain(text: &str, name: &str) -> Option<Gain> {
    let l = text.lines().rev().find(|l| l.split('\t').next() == Some(name))?;
    let v: Vec<f32> = l.split('\t').nth(1)?.split(' ').filter_map(|x| x.parse().ok()).collect();
    (v.len() == 6).then(|| ([v[0], v[1], v[2], 0.0], [v[3], v[4], v[5], 0.0]))
}

/// The Survey of Israel sheets over one level-4 unit: 2 m warp, the sheets' levels and gains, over the level-3
/// Sentinel-2 node where no sheet is and on the airbases; writes the level-1 nodes with any sheet pixel.
fn survey_unit(sv: &Survey, f: &Frame, unit: Key, itm: [[f64; 2]; 4], work: &Path, out: &Path) -> Result<()> {
    let d = unit.0 - 1;
    let n = (NODE_PIXELS << d) as usize;
    let bin = work.join(format!("soi_{}_{}_{}.bin", unit.0, unit.1, unit.2));
    let extra = ["-r", "bilinear", "-srcnodata", "255 255 255", "-wo", "UNIFIED_SRC_NODATA=YES", "-dstalpha"];
    let e = warp(sv.vrt, f.utm(unit), [n, n], &extra, &bin)?;
    if e.bands != 4 || e.dtype != "1" || e.raw.len() != n * n * 4 {
        bail!("Survey unit {unit:?}: want RGBA bytes, got {} / type {}", e.bands, e.dtype);
    }
    let rect = f.utm(unit);
    let bases = BaseMask::new(sv.bases, rect);
    let px = (rect[2] - rect[0]) / n as f64;
    // The Israeli TM position of unit pixel (u, v) (0..1): bilinear between the corners (NW, NE, SW, SE); the
    // grids differ by ≈ 1° of rotation and < 0.1 % of scale, so the levels' 4 km blend sees no error.
    let at = |u: f64, v: f64| -> [f64; 2] {
        let l = |a: usize| itm[0][a] + (itm[1][a] - itm[0][a]) * u;
        let r = |a: usize| itm[2][a] + (itm[3][a] - itm[2][a]) * u;
        [l(0) + (r(0) - l(0)) * v, l(1) + (r(1) - l(1)) * v]
    };
    let weight = |i: usize| {
        let base = bases
            .as_ref()
            .map_or(0.0, |b| b.at(rect[0] + ((i % n) as f64 + 0.5) * px, rect[3] - ((i / n) as f64 + 0.5) * px));
        f32::from(e.raw[i * 4 + 3]) / 255.0 * (1.0 - base)
    };
    let m = NODE_PIXELS as usize;
    for sj in 0..1u32 << d {
        for si in 0..1u32 << d {
            let k = (1, (unit.1 << d) + si, (unit.2 << d) + sj);
            let (ox, oy) = (si as usize * m, sj as usize * m);
            if k.1 * 2048 >= f.w
                || k.2 * 2048 >= f.h
                || (0..m).all(|y| (0..m).all(|x| weight((oy + y) * n + ox + x) == 0.0))
            {
                continue;
            }
            let mut img = ancestor_crop(out, k, 3)?;
            for y in 0..m {
                for x in 0..m {
                    let i = (oy + y) * n + ox + x;
                    let a = weight(i);
                    if a == 0.0 {
                        continue;
                    }
                    let [ie, inn] = at((ox + x) as f64 / n as f64, (oy + y) as f64 / n as f64);
                    let mut rgb = [0, 1, 2].map(|c| f32::from(e.raw[i * 4 + c]));
                    if let Some(lv) = imagery::levels_at(&sv.levels, ie, inn) {
                        rgb = imagery::photo_levels(rgb, lv);
                    }
                    if let (Some(k), Some(o)) =
                        (imagery::levels_at(&sv.scales, ie, inn), imagery::levels_at(&sv.offsets, ie, inn))
                    {
                        rgb = [0, 1, 2].map(|c| (rgb[c] * k[c] + o[c]).clamp(0.0, 255.0));
                    }
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
    serde_json::json!({ "box": r.area, "detail": r.detail, "survey_zips": zips, "airbases": bases })
}

/// `meta.json` (the shape `terrain::theatre` writes) with the georeference, the sources and the run's stamp.
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

/// The bytes of the theatre's Sentinel-2 tiles already whole in `cache` (the setup wizard's disk check): only the
/// listings already cached count (no network); 0 without them or without GDAL.
pub fn s2_cached_bytes(cache: &Path) -> u64 {
    geo_bbox(BOX).map_or(0, |geo| cached_in(cache, geo))
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

/// The heights branch: the GLO-30 tiles (cache first), the 64 m grid, the height nodes; returns what it reused.
fn heights(r: &Run, f: &Frame, geo: [f64; 4], work: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<String> {
    let t0 = std::time::Instant::now();
    log!(pr, "heights: GLO-30 tiles from {}", r.dem_cache.display());
    let (tiles, line) = fetch_dem(&r.dem_cache, geo, pr, cancel)?;
    log!(pr, "heights: DEM {line}");
    let grid = dem_grid(&tiles, r.area, work)?;
    // Half the workers: the colour branch runs beside it.
    write_heights(f, &grid, &r.out, (r.threads / 2).max(1), cancel)?;
    log!(pr, "heights: done ({})", crate::progress::duration(t0.elapsed()));
    Ok(line)
}

/// The colour branch: Sentinel-2 from the shared tile cache (the missing tiles fetched into it), its 32 m and 8 m
/// nodes, then the Survey sheets over them; returns what it reused.
fn colour(r: &Run, f: &Frame, geo: [f64; 4], work: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<String> {
    let t0 = std::time::Instant::now();
    let (out, work) = (r.out.as_path(), work.to_path_buf());
    let f = *f;
    // Sentinel-2: one VRT over the WorldCover tiles (their overviews serve the 32 m nodes).
    log!(pr, "sentinel-2: WorldCover tiles from {}", r.s2_cache.display());
    let tiles = list_tiles(&r.s2_cache, BUCKET, geo[1].floor() as i32, geo[3].floor() as i32)?;
    let names: Vec<String> = tiles
        .keys()
        .filter(|n| tile_box(n).is_some_and(|b| b[0] < geo[2] && geo[0] < b[2] && b[1] < geo[3] && geo[1] < b[3]))
        .cloned()
        .collect();
    // One bar over the colour branch, the longer of the two (the heights run beside it): its parts by their expected
    // seconds (`part_ends`).
    let has_zips = std::fs::read_dir(&r.sheets)
        .map(|d| d.filter_map(|e| e.ok()).any(|e| e.path().extension().is_some_and(|x| x.eq_ignore_ascii_case("zip"))))
        .unwrap_or(false);
    let fetch: u64 =
        names.iter().filter(|n| !tile_whole(&r.s2_cache, &tiles, n)).map(|n| tiles.get(n).copied().unwrap_or(0)).sum();
    let ends = part_ends(fetch, has_zips);
    let part = |i: usize| Part { pr, from: ends[i], to: ends[i + 1] };
    let (paths, s2_line) = tile_sources(&r.s2_cache, BUCKET, &tiles, &names, 3, &part(0), cancel)?;
    log!(pr, "sentinel-2: {s2_line} ({})", crate::progress::duration(t0.elapsed()));
    let urls: Vec<String> = paths.into_values().collect();
    let s2 = work.join("s2.vrt");
    let mut a = vec!["-q", "-overwrite", utf8(&s2)?];
    a.extend(urls.iter().map(String::as_str));
    gdal("gdalbuildvrt", &a)?;
    let s2 = utf8(&s2)?;
    let detail5: BTreeSet<Key> = f.nodes_in(5, r.detail).into_iter().collect();
    let inside = |k: Key| (k.1 << k.0) * NODE_PIXELS < f.w && (k.2 << k.0) * NODE_PIXELS < f.h;
    let coarse = |k: Key| inside(k) && !detail5.contains(&k);
    let fine = |k: Key| inside(k) && detail5.contains(&(5, k.1 >> (5 - k.0), k.2 >> (5 - k.0)));
    let u7: Vec<Key> = f.nodes(7).into_iter().filter(|u| f.nodes_in(5, f.utm(*u)).into_iter().any(coarse)).collect();
    let s2_32 = |u| sentinel_unit(s2, &f, u, 5, &coarse, &work, out);
    units("s2_32m", &u7, &work, r.threads, &part(1), cancel, s2_32)?;
    let u5: Vec<Key> = detail5.iter().copied().collect();
    units("s2_8m", &u5, &work, r.threads, &part(2), cancel, |u| sentinel_unit(s2, &f, u, 3, &fine, &work, out))?;

    // The Survey of Israel 2 m sheets already downloaded.
    if has_zips {
        seed_sheets(&work, &r.sheet_index, pr)?;
        let (sheets, _) = list_sheets(&r.sheets, &work, pr, cancel)?;
        let u4: Vec<Key> = f.nodes(4).into_iter().filter(|&k| fine(k)).collect();
        let corners: Vec<[f64; 2]> = u4
            .iter()
            .flat_map(|&k| {
                let e = f.utm(k);
                [[e[0], e[3]], [e[2], e[3]], [e[0], e[1]], [e[2], e[1]]]
            })
            .collect();
        let itm = transform("EPSG:32636", "EPSG:2039", &corners)?;
        // Units with a sheet: (key, ITM corners, ITM bounding box).
        let mut list = Vec::new();
        for (n, &k) in u4.iter().enumerate() {
            let c: [[f64; 2]; 4] = itm[n * 4..n * 4 + 4].try_into()?;
            let b = c.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
                [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
            });
            if !near(&sheets, &[b], 0.0).is_empty() {
                list.push((k, c, b));
            }
        }
        let keys: Vec<Key> = list.iter().map(|u| u.0).collect();
        // The sheets whose levels reach a unit (their blend spans DARK_BLEND / 2 = 2 km beyond a sheet).
        let sheets = near(&sheets, &list.iter().map(|u| u.2).collect::<Vec<_>>(), 2000.0);
        let vrt = soi_vrt(&sheets, &r.sheets, &work, pr)?;
        let gains = sheet_gains(&sheets, s2, &work, r.threads, cancel)?;
        log!(
            pr,
            "survey: {} sheets, colours matched to Sentinel-2 ({})",
            sheets.len(),
            crate::progress::duration(t0.elapsed())
        );
        let bases = base_outlines(&r.airbases)?;
        let sv = Survey {
            vrt: utf8(&vrt)?,
            levels: sheets.iter().map(|s| (s.bbox, s.levels)).collect(),
            scales: sheets.iter().zip(&gains).map(|(s, g)| (s.bbox, g.0)).collect(),
            offsets: sheets.iter().zip(&gains).map(|(s, g)| (s.bbox, g.1)).collect(),
            bases: &bases,
        };
        units("survey_2m", &keys, &work, r.threads, &part(3), cancel, |k| {
            let (_, c, _) = list.iter().find(|u| u.0 == k).context("unit")?;
            survey_unit(&sv, &f, k, *c, &work, out)
        })?;
        parents(out, 2, Some(3), r.threads, cancel)?;
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
    if old["built_from"] == built_from {
        log!(pr, "{}: up to date (same box, detail area and sheets)", out.display());
        return Ok(());
    }
    std::fs::create_dir_all(&work)?;
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
        both(cancel, |stop| heights(r, &f, geo, &work, pr, stop), |stop| colour(r, &f, geo, &work, pr, stop))?;

    // The coarser levels from their children (level 4 exists in the detail area only, so the 32 m level-5 nodes
    // stay the source's).
    for l in 4..=ROOT_LEVEL {
        parents(out, l, None, r.threads, cancel)?;
    }
    write_meta(&f, out, built_from)?;
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

    #[test]
    fn dem_tile_names() {
        assert_eq!(dem_tile(31, 34), "Copernicus_DSM_COG_10_N31_00_E034_00_DEM");
        assert_eq!(dem_tile(-1, -5), "Copernicus_DSM_COG_10_S01_00_W005_00_DEM");
    }

    /// Only a missing key marks a DEM cell as open sea.
    #[test]
    fn only_a_missing_key_is_sea() {
        assert!(no_tile("404", ""));
        assert!(no_tile("403", "<Error><Code>NoSuchKey</Code></Error>"));
        assert!(!no_tile("403", "<Error><Code>AccessDenied</Code></Error>"), "a transient 403");
        assert!(!no_tile("500", "NoSuchKey"));
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

    /// gdaltransform with more than a pipe's worth of input (≈ 64 KB) answers instead of blocking.
    #[test]
    fn transform_takes_many_points() {
        if Command::new("gdaltransform").arg("--version").output().is_err() {
            eprintln!("skipped: GDAL not installed");
            return;
        }
        let pts: Vec<[f64; 2]> = (0..20_000).map(|k| [600_000.0 + f64::from(k), 3_400_000.0]).collect();
        let g = transform("EPSG:32636", "EPSG:4326", &pts).unwrap();
        assert_eq!(g.len(), pts.len());
        assert!((g[0][1] - 30.72).abs() < 0.1, "{:?}", g[0]);
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
            area: [500_000.0, 3_400_000.0, 500_000.0 + 1024.0, 3_400_000.0 + 1024.0],
            detail: DETAIL,
            threads: 1,
        };
        let f = Frame::new(run.area).unwrap();
        write_meta(&f, &out, stamp(&run)).unwrap();
        terrain(&run, &crate::progress::Stdout, &AtomicBool::new(false)).unwrap();
        assert!(!out.join(".work").exists(), "returned before any work");
        std::fs::remove_dir_all(&out).unwrap();
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
        write_heights(&f, &g, &out, 2, &AtomicBool::new(false)).unwrap();
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
        if Command::new("gdalwarp").arg("--version").output().is_err() {
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
        let lon = |e: f64, n: f64| transform("EPSG:32636", "EPSG:4326", &[[e, n]]).unwrap()[0][0];
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
}
