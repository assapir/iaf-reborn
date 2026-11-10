//! `iaf-imagery sentinel2|mapi2015`'s work (docs/imagery.md): each source warped into the game frame and written
//! as two node-set layers under the out root, resumable and incremental (`<out>/.work/` marks per work unit).

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

use crate::georef::Georef;
use crate::imagery::{self, Cache, Imagery, Key, Photo, ROOT_LEVEL, Rules, Source, Theatre};
use crate::itm;
use crate::log;
use crate::progress::{Part, Progress, check, utf8};
use anyhow::{Context, Result, bail};

/// The WorldCover bucket the Sentinel-2 tiles come from.
pub const BUCKET: &str = "https://esa-worldcover-s2.s3.eu-central-1.amazonaws.com";
const PREFIX: &str = "rgbnir/2021";
const JPEG_QUALITY: u8 = 88;

/// A source's fixed parameters (`SENTINEL2`, `MAPI2015`).
pub struct Spec {
    id: &'static str,
    layers: [&'static str; 2],
    /// Work unit: one node of this level (5: 40 km of game frame = 16 level-3 nodes; 4: 20 km = 64 level-1
    /// nodes, so a unit's 2 m window stays ≈ 0.4 GB).
    unit_level: u32,
    /// The finest level written.
    layer_level: u32,
    outside_israel: bool,
}

pub const SENTINEL2: Spec = Spec {
    id: "sentinel2",
    layers: ["sentinel2", "sentinel2_modern"],
    unit_level: 5,
    layer_level: 3,
    outside_israel: true,
};
/// Work units are compared by their rect plus this margin (m): the node margins (≈ 640 m at level 1) and feathers.
const UNIT_PAD_M: f64 = 1000.0;
pub const MAPI2015: Spec = Spec {
    id: "mapi2015",
    layers: ["mapi2015", "mapi2015_modern"],
    unit_level: 4,
    layer_level: 1,
    outside_israel: false,
};

/// One Survey of Israel sheet: a GeoTIFF inside a downloaded ZIP.
#[derive(Clone)]
pub(crate) struct Sheet {
    /// "<zip>/<tif inside>", the sheet's identity in the resume marks.
    pub(crate) name: String,
    /// The GDAL path (`/vsizip/…`).
    pub(crate) gdal: String,
    /// Israeli TM Grid extent (e0, n0, e1, n1), metres.
    pub(crate) bbox: [f64; 4],
    /// Levels: per-band dark, white (`imagery::sheet_levels`).
    pub(crate) levels: [f32; 4],
}

/// What a source needs per unit.
enum Prep {
    /// The tiles (name → bytes) and, once fetched, their GDAL paths (`tile_sources`).
    Sentinel {
        tiles: BTreeMap<String, u64>,
        paths: BTreeMap<String, String>,
    },
    Mapi {
        sheets: Vec<Sheet>,
        zips: Vec<PathBuf>,
    },
}

/// A work unit: its node, lon / lat box, and (mapi2015) its padded Israeli TM window and the sheets in it.
struct Unit {
    k: Key,
    geo: [f64; 4],
    itm: [f64; 4],
    sheets: Vec<String>,
    /// The rules tag of the unit and its margin (Rules::tag), and whether an airbase site reaches into it.
    rules: String,
    on_base: bool,
}

/// Points along a node's outline (17 per side).
fn outline(k: Key) -> Vec<[f64; 2]> {
    let s = imagery::node_span(k.0) as f64;
    let mut v = Vec::new();
    for t in 0..=16 {
        let f = t as f64 / 16.0;
        for (x, y) in [(f, 0.0), (f, 1.0), (0.0, f), (1.0, f)] {
            v.push([(k.1 as f64 + x) * s, (k.2 as f64 + y) * s]);
        }
    }
    v
}

fn bbox(points: impl Iterator<Item = [f64; 2]>) -> [f64; 4] {
    points.fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, [x, y]| {
        [b[0].min(x), b[1].min(y), b[2].max(x), b[3].max(y)]
    })
}

fn overlap(a: &[f64; 4], b: &[f64; 4]) -> f64 {
    ((a[2].min(b[2]) - a[0].max(b[0])).max(0.0)) * ((a[3].min(b[3]) - a[1].max(b[1])).max(0.0))
}

/// The WorldCover tiles' download folder under `assets/`, shared by both games (docs/imagery.md §2): the tiles under
/// the bucket's file names, one listing per latitude band (`listing_N30.tsv`).
pub const S2_CACHE: &str = "source/imagery/sentinel2";
/// The free disk a tile download must leave (bytes); a tile with no room is read over the network as before.
// ponytail: one fixed margin; a setting if a user wants the whole 28 GB mirror on a nearly full disk.
const S2_KEEP_FREE: u64 = 5_000_000_000;
const USER_AGENT: &str = "iaf-reborn imagery setup (curl)";
/// Tiles downloading at once (both games; 4.6 MB/s measured per transfer, modern-iaf/docs/terrain.md §7).
const S2_JOBS: usize = 3;

/// The WorldCover 1°×1° tiles (name → bytes) in the latitude bands N<lat0>..N<lat1>: the S3 listing, kept in `cache`
/// per band, so a listed band needs no network.
pub fn list_tiles(cache: &Path, bucket: &str, lat0: i32, lat1: i32) -> Result<BTreeMap<String, u64>> {
    let mut out = BTreeMap::new();
    for lat in lat0..=lat1 {
        let mark = cache.join(format!("listing_N{lat:02}.tsv"));
        let text = match std::fs::read_to_string(&mark) {
            Ok(t) => t,
            Err(_) => {
                let url = format!("{bucket}/?list-type=2&prefix={PREFIX}/N{lat:02}/");
                let o = Command::new("curl").args(["-sf", "-m", "60", &url]).output().context("running curl")?;
                if !o.status.success() {
                    bail!("listing {url} failed ({})", crate::thirdparty::curl_error(o.status));
                }
                let t = parse_listing(&String::from_utf8_lossy(&o.stdout)).with_context(|| format!("listing {url}"))?;
                // Written whole or not at all: a listing in the cache is trusted from then on.
                std::fs::create_dir_all(cache)?;
                let tmp = mark.with_extension("tmp");
                std::fs::write(&tmp, &t)?;
                std::fs::rename(&tmp, &mark)?;
                t
            }
        };
        for l in text.lines() {
            if let Some((n, b)) = l.split_once('\t') {
                out.insert(n.to_string(), b.parse().unwrap_or(0));
            }
        }
    }
    Ok(out)
}

/// An S3 listing (ListObjectsV2 XML) as `tile\tbytes` lines; refused when it lists nothing or only a first page,
/// so a broken answer is never cached. Empty files are left out.
fn parse_listing(xml: &str) -> Result<String> {
    if !xml.contains("<Contents>") || xml.contains("<IsTruncated>true") {
        bail!("an empty or incomplete answer");
    }
    let mut t = String::new();
    for c in xml.split("<Contents>").skip(1) {
        let tag =
            |t: &str| c.split(&format!("<{t}>")).nth(1).and_then(|s| s.split('<').next()).unwrap_or("").to_string();
        let key = tag("Key");
        let size = tag("Size").parse::<u64>().unwrap_or(0);
        if let Some(name) = key.rsplit('/').next().and_then(|f| f.split('_').nth(5))
            && size > 0
        {
            t += &format!("{name}\t{size}\n");
        }
    }
    Ok(t)
}

/// The tile's file name, in the bucket and in the cache.
fn tile_file(name: &str) -> String {
    format!("ESA_WorldCover_10m_2021_v200_{name}_S2RGBNIR.tif")
}

/// Free bytes on the disk holding `dir` (`df -Pk`; None where there is no df).
fn free_bytes(dir: &Path) -> Option<u64> {
    let o = Command::new("df").arg("-Pk").arg(dir).output().ok()?;
    let text = String::from_utf8_lossy(&o.stdout);
    text.lines().last()?.split_whitespace().nth(3)?.parse::<u64>().ok().map(|k| k * 1024)
}

/// `url` into `dest` through `<dest>.part` (resumed), checked against `bytes` (0: unknown); curl's stall rule, `cancel`
/// stops it, `on_bytes` gets the part's size four times a second. `<dest>.lock` keeps two runs (both games, or two
/// threads) from writing one part: the second waits and then finds the file whole.
pub(crate) fn curl_to(
    url: &str,
    dest: &Path,
    bytes: u64,
    user_agent: &str,
    cancel: &AtomicBool,
    on_bytes: &dyn Fn(u64),
) -> Result<()> {
    let whole = || std::fs::metadata(dest).is_ok_and(|m| bytes == 0 || m.len() == bytes);
    let lock = std::fs::File::create(dest.with_extension("lock"))?;
    lock.lock()?;
    if whole() {
        return Ok(());
    }
    let part = dest.with_extension("part");
    let have = std::fs::metadata(&part).map_or(0, |m| m.len());
    if bytes > 0 && have > bytes {
        std::fs::remove_file(&part)?;
    }
    if bytes == 0 || have != bytes {
        let child = Command::new("curl")
            .args(["-sS", "-f", "-L", "-C", "-", "-A", user_agent])
            .args(crate::thirdparty::CURL_PATIENCE)
            .args(["-o", utf8(&part)?, url])
            .spawn()
            .context("running curl")?;
        let s = crate::thirdparty::wait_curl(child, &part, &|| cancel.load(Ordering::Relaxed), &|| {
            on_bytes(std::fs::metadata(&part).map_or(0, |m| m.len()))
        })?;
        if s.code() == Some(23) {
            bail!("{}: disk full (curl could not write): free space and run again", part.display());
        }
        if !s.success() {
            bail!("{url}: {}; run again to resume it", crate::thirdparty::curl_error(s));
        }
    }
    let got = std::fs::metadata(&part)?.len();
    if bytes > 0 && got != bytes {
        let _ = std::fs::remove_file(&part);
        bail!("{url}: {got} bytes, want {bytes}");
    }
    std::fs::rename(&part, dest)?;
    Ok(())
}

/// The tiles `names` of `tiles` as GDAL paths: the file in `cache` when it is there whole, else downloaded into it
/// first (`S2_JOBS` at once); a tile with no room on the disk (`S2_KEEP_FREE`) is read over the network (`/vsicurl/`).
/// An edge tile (in `edges`) is read only at 20 m: one not in the cache whole is never downloaded whole; its 20 m
/// extract over the edges' window is cut once from the network ([`edge_file`]) and kept, so a later run reads it with
/// no network. Also returns the line saying what was reused and fetched.
pub fn tile_sources(
    cache: &Path,
    bucket: &str,
    tiles: &BTreeMap<String, u64>,
    names: &[String],
    edges: &Edges,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<(BTreeMap<String, String>, String)> {
    std::fs::create_dir_all(cache)?;
    let size = |n: &str| tiles.get(n).copied().unwrap_or(0);
    let path = |n: &str| cache.join(tile_file(n));
    let (reused, missing): (Vec<&String>, Vec<&String>) = names.iter().partition(|n| tile_whole(cache, tiles, n));
    // ponytail: the room is measured once per run; another job filling the disk meanwhile ends in curl's "disk full".
    // Without df (Windows) there is no room check (docs/imagery.md §2).
    let mut room = free_bytes(cache).map_or(u64::MAX, |f| f.saturating_sub(S2_KEEP_FREE));
    let (mut fetch, mut stream, mut overview) = (Vec::new(), Vec::new(), Vec::new());
    for n in missing {
        if edges.names.contains(n) {
            overview.push(n.clone());
            continue;
        }
        let need = size(n).saturating_sub(std::fs::metadata(path(n).with_extension("part")).map_or(0, |m| m.len()));
        if need <= room {
            room -= need;
            fetch.push(n.clone());
        } else {
            stream.push(n.clone());
        }
    }
    let gb = |v: &[&String]| v.iter().map(|n| size(n)).sum::<u64>() as f64 / 1e9;
    let fetch_refs: Vec<&String> = fetch.iter().collect();
    let stream_refs: Vec<&String> = stream.iter().collect();
    log!(
        pr,
        "  {} tiles: {} reused ({:.2} GB), {} to fetch ({:.2} GB) into {}",
        names.len(),
        reused.len(),
        gb(&reused),
        fetch.len(),
        gb(&fetch_refs),
        cache.display()
    );
    if !stream.is_empty() {
        pr.warn(&format!(
            "  {} tiles ({:.2} GB) read over the network: no room to keep them (under {} GB free would be left)",
            stream.len(),
            gb(&stream_refs),
            S2_KEEP_FREE / 1_000_000_000
        ));
    }
    // The bar and a line every FETCH_LOG_S seconds: the bytes on disk (whole tiles and the parts growing) of those to
    // fetch, so a run of large tiles never looks stuck.
    let total = fetch.iter().map(|n| size(n)).sum::<u64>().max(1);
    let (done, parts) = (AtomicU64::new(0), Mutex::new(BTreeMap::<String, u64>::new()));
    let kept: u64 =
        fetch.iter().map(|n| std::fs::metadata(path(n).with_extension("part")).map_or(0, |m| m.len())).sum();
    let (t0, last_log) = (std::time::Instant::now(), AtomicU64::new(0));
    let report = || {
        let now = done.load(Ordering::Relaxed) + parts.lock().map_or(0, |p| p.values().sum::<u64>());
        pr.fraction(now as f32 / total as f32);
        let (secs, last) = (t0.elapsed().as_secs(), last_log.load(Ordering::Relaxed));
        if secs >= last + crate::thirdparty::FETCH_LOG_S
            && last_log.compare_exchange(last, secs, Ordering::Relaxed, Ordering::Relaxed).is_ok()
        {
            let line = crate::progress::download_line(now, total, now.saturating_sub(kept), t0.elapsed().as_secs_f64());
            log!(pr, "  Sentinel-2 tiles: {line}");
        }
    };
    crate::sim_terrain::par(&fetch, S2_JOBS, cancel, |n| {
        let on_bytes = |b: u64| {
            if let Ok(mut p) = parts.lock() {
                p.insert(n.clone(), b);
            }
            report();
        };
        curl_to(&tile_url(bucket, n), &path(n), size(n), USER_AGENT, cancel, &on_bytes)?;
        if let Ok(mut p) = parts.lock() {
            p.remove(n.as_str());
        }
        done.fetch_add(size(n), Ordering::Relaxed);
        log!(pr, "  {n}: fetched {:.0} MB", size(n) as f64 / 1e6);
        report();
        Ok(())
    })?;
    // The edge tiles: their kept 20 m extracts, the missing ones cut now.
    let (mut kept, mut cut) = (0, 0);
    for n in &overview {
        check(cancel)?;
        let w = edge_window(n, edges.window);
        if edge_kept(cache, n, w) {
            kept += 1;
        } else {
            cut_edge(cache, bucket, n, w)?;
            log!(pr, "  {n}: 20 m extract cut, {:.0} MB", std::fs::metadata(edge_file(cache, n))?.len() as f64 / 1e6);
            cut += 1;
        }
    }
    let mut out = BTreeMap::new();
    for n in names {
        let p = if stream.contains(n) {
            format!("/vsicurl/{}", tile_url(bucket, n))
        } else if overview.contains(n) {
            utf8(&edge_file(cache, n))?.to_string()
        } else {
            utf8(&path(n))?.to_string()
        };
        out.insert(n.clone(), p);
    }
    let mut line = format!("{} tiles, {} reused ({:.2} GB)", names.len(), reused.len(), gb(&reused));
    line += &format!(", {} fetched ({:.2} GB)", fetch.len(), gb(&fetch_refs));
    if !stream.is_empty() {
        line += &format!(", {} streamed ({:.2} GB)", stream.len(), gb(&stream_refs));
    }
    if !overview.is_empty() {
        line += &format!(", edge tiles at 20 m: {kept} kept, {cut} cut from the network");
    }
    Ok((out, line))
}

/// The tiles read only at 20 m (the theatre's edge tiles, outside its 8 m nodes) and the window (lon / lat) they
/// are read over.
pub struct Edges<'a> {
    pub names: &'a [String],
    pub window: [f64; 4],
}

/// No edge tiles: every tile at 10 m.
pub const NO_EDGES: Edges = Edges { names: &[], window: [0.0; 4] };

/// The kept 20 m extract of edge tile `n` (the tile's own name with `_20m`); its `.ok` mark names the window (lon /
/// lat) it was cut to.
pub fn edge_file(cache: &Path, n: &str) -> PathBuf {
    cache.join(tile_file(n).replace(".tif", "_20m.tif"))
}

/// The part of `window` on tile `n`.
fn edge_window(n: &str, window: [f64; 4]) -> [f64; 4] {
    let b = tile_box(n).unwrap_or(window);
    [b[0].max(window[0]), b[1].max(window[1]), b[2].min(window[2]), b[3].min(window[3])]
}

/// The extract of `n` is there and was cut to a window holding `w`.
fn edge_kept(cache: &Path, n: &str, w: [f64; 4]) -> bool {
    let p = edge_file(cache, n);
    let had: Vec<f64> = std::fs::read_to_string(p.with_extension("ok"))
        .unwrap_or_default()
        .split_whitespace()
        .filter_map(|v| v.parse().ok())
        .collect();
    let e = 1e-9;
    p.is_file()
        && had.len() == 4
        && had[0] <= w[0] + e
        && had[1] <= w[1] + e
        && had[2] >= w[2] - e
        && had[3] >= w[3] - e
}

/// Cuts the 20 m extract of edge tile `n` over `w` from the bucket: the tile's first overview (the pixels the 32 m
/// nodes read, on the tile's own grid), range reads of that window alone.
fn cut_edge(cache: &Path, bucket: &str, n: &str, w: [f64; 4]) -> Result<()> {
    let dest = edge_file(cache, n);
    let part = dest.with_extension("part");
    let src = format!("/vsicurl/{}", tile_url(bucket, n));
    let win = w.map(|v| v.to_string());
    let co = ["-of", "COG", "-co", "COMPRESS=DEFLATE", "-co", "PREDICTOR=2"];
    let mut a = vec!["-q", "-oo", "OVERVIEW_LEVEL=0", "-projwin", &win[0], &win[3], &win[2], &win[1]];
    a.extend(co);
    a.extend([src.as_str(), utf8(&part)?]);
    if let Err(e) = gdal("gdal_translate", &a) {
        let _ = std::fs::remove_file(&part);
        return Err(e.context(format!("{n}: the 20 m extract (offline? run again when online)")));
    }
    std::fs::rename(&part, &dest)?;
    std::fs::write(dest.with_extension("ok"), format!("{} {} {} {}\n", w[0], w[1], w[2], w[3]))?;
    Ok(())
}

/// The Copernicus GLO-30 DEM's tile cache under `assets/` (the sim's heights; any open-data terrain reads it too).
pub const DEM_CACHE: &str = "source/dem";
const DEM_URL: &str = "https://copernicus-dem-30m.s3.amazonaws.com";
const DEM_USER_AGENT: &str = "iaf-reborn terrain setup (curl)";

/// The GLO-30 tile name of the 1° cell whose south-west corner is (lat, lon).
pub(crate) fn dem_tile(lat: i32, lon: i32) -> String {
    let (ns, ew) = (if lat < 0 { 'S' } else { 'N' }, if lon < 0 { 'W' } else { 'E' });
    format!("Copernicus_DSM_COG_10_{ns}{:02}_00_{ew}{:03}_00_DEM", lat.abs(), lon.abs())
}

/// The DEM bucket has no tile for the cell (open sea): S3 answers a missing key with 404, or with 403 and NoSuchKey
/// in the body. Any other answer (a transient 403 too) must not mark the cell as sea for good.
fn no_tile(code: &str, body: &str) -> bool {
    code == "404" || (code == "403" && body.contains("NoSuchKey"))
}

/// The GLO-30 tiles over `geo` in the cache, fetched once each (a `.none` mark for a cell with no tile: open sea),
/// and the line saying what was reused and fetched.
pub fn fetch_dem(
    cache: &Path,
    geo: [f64; 4],
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<(Vec<PathBuf>, String)> {
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
            // A part left by a cut download resumes; one holding anything but a TIFF's start (an error page) is
            // dropped first.
            if !resumable(&part) {
                let _ = std::fs::remove_file(&part);
            }
            let url = format!("{DEM_URL}/{name}/{name}.tif");
            let mut child = Command::new("curl")
                .args(["-sS", "-L", "-C", "-", "-A", DEM_USER_AGENT])
                .args(crate::thirdparty::CURL_PATIENCE)
                .args(["-w", "%{http_code}", "-o", utf8(&part)?, &url])
                .stdout(Stdio::piped())
                .spawn()
                .context("running curl")?;
            // The answer is a few bytes: the pipe never fills while curl runs.
            let mut out = child.stdout.take().context("curl's stdout")?;
            // A line every FETCH_LOG_S seconds, so the heights never look stuck.
            let (t0, last_log) = (std::time::Instant::now(), std::sync::atomic::AtomicU64::new(0));
            let tick = || {
                let secs = t0.elapsed().as_secs();
                if secs >= last_log.load(Ordering::Relaxed) + crate::thirdparty::FETCH_LOG_S {
                    last_log.store(secs, Ordering::Relaxed);
                    log!(pr, "  DEM {name}: {:.0} MB so far", mb(&part) as f64 / 1e6);
                }
            };
            let status = crate::thirdparty::wait_curl(child, &part, &|| cancel.load(Ordering::Relaxed), &tick)?;
            let mut code = String::new();
            std::io::Read::read_to_string(&mut out, &mut code)?;
            let code = code.trim().to_string();
            match code.as_str() {
                // A tile cut short (a stall) is not a tile: only a clean exit renames the part; the part stays for
                // the next run to resume.
                "200" | "206" if !status.success() => {
                    bail!("{url}: {}; run again to resume it", crate::thirdparty::curl_error(status));
                }
                "200" | "206" => {
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
                _ => {
                    let _ = std::fs::remove_file(&part);
                    bail!("{url}: HTTP {code} ({})", crate::thirdparty::curl_error(status))
                }
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

/// A DEM part a download can resume: it begins as a TIFF does (an error page written by an older run does not).
fn resumable(part: &Path) -> bool {
    let mut head = [0u8; 4];
    std::fs::File::open(part).and_then(|mut f| std::io::Read::read_exact(&mut f, &mut head)).is_ok()
        && (head == *b"II*\0" || head == *b"MM\0*")
}

/// The tile `n` is in the cache whole (its listed size).
pub(crate) fn tile_whole(cache: &Path, tiles: &BTreeMap<String, u64>, n: &str) -> bool {
    let size = tiles.get(n).copied().unwrap_or(0);
    std::fs::metadata(cache.join(tile_file(n))).is_ok_and(|m| size > 0 && m.len() == size)
}

/// The tile's 1° box (lon0, lat0, lon1, lat1) from its name ("N30E032" = 30..31 N, 32..33 E).
pub(crate) fn tile_box(name: &str) -> Option<[f64; 4]> {
    let lat: f64 = name.get(1..3)?.parse().ok()?;
    let lon: f64 = name.get(4..7)?.parse().ok()?;
    let lat = if name.starts_with('S') { -lat } else { lat };
    let lon = if name.as_bytes().get(3) == Some(&b'W') { -lon } else { lon };
    Some([lon, lat, lon + 1.0, lat + 1.0])
}

pub(crate) fn tile_url(bucket: &str, name: &str) -> String {
    format!("{bucket}/{PREFIX}/{}/{}", &name[..3], tile_file(name))
}

pub(crate) fn gdal_output(cmd: &str, args: &[&str]) -> Result<String> {
    let o = Command::new(cmd)
        .args(args)
        .env("CPL_VSIL_CURL_ALLOWED_EXTENSIONS", ".tif,.vrt")
        .env("GDAL_HTTP_MERGE_CONSECUTIVE_RANGES", "YES")
        .env("GDAL_HTTP_MAX_RETRY", "5")
        .env("GDAL_HTTP_RETRY_DELAY", "2")
        .env("VSI_CACHE", "TRUE")
        .output()
        .with_context(|| format!("running {cmd} (install GDAL: sudo pacman -S gdal)"))?;
    if !o.status.success() {
        // GDAL prints plugin-loading noise on some installs; show only the real errors.
        let err: Vec<String> = String::from_utf8_lossy(&o.stderr)
            .lines()
            .filter(|l| !l.contains("cannot open shared object"))
            .map(String::from)
            .collect();
        bail!(
            "{cmd} {} failed ({}):\n{}{}",
            args.join(" "),
            o.status,
            String::from_utf8_lossy(&o.stdout),
            err.join("\n")
        );
    }
    Ok(String::from_utf8_lossy(&o.stdout).into_owned())
}

pub(crate) fn gdal(cmd: &str, args: &[&str]) -> Result<()> {
    gdal_output(cmd, args).map(|_| ())
}

/// The complete sheet ZIPs in `dir` (`*.zip`; a browser's `*.part` / `*.crdownload` are still downloading)
/// and the GeoTIFFs in them with their Israeli TM Grid extents. The extents are cached in `<work>/sheets.tsv`
/// (per ZIP name, size and time; `gdalinfo` on a sheet in a ZIP takes a second or two).
pub(crate) fn list_sheets(
    dir: &Path,
    work: &Path,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<(Vec<Sheet>, Vec<PathBuf>)> {
    let mut zips: Vec<PathBuf> = std::fs::read_dir(dir)
        .with_context(|| format!("{}: no sheets (iaf-imagery fetch-mapi2015)", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("zip")))
        .collect();
    zips.sort();
    let cache_file = work.join("sheets.tsv");
    // zip \t size \t mtime \t tif \t e0 n0 e1 n1 \t levels r g b white
    let cached: Vec<Vec<String>> = std::fs::read_to_string(&cache_file)
        .unwrap_or_default()
        .lines()
        .map(|l| l.split('\t').map(String::from).collect())
        .collect();
    let mut cache_out = String::new();
    let mut sheets = Vec::new();
    let mut ok = Vec::new();
    for z in zips {
        check(cancel)?;
        let abs = std::fs::canonicalize(&z)?;
        let zname = z
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .with_context(|| format!("{}: no file name", z.display()))?;
        let meta = std::fs::metadata(&abs)?;
        let stamp =
            [meta.len().to_string(), meta.modified()?.duration_since(std::time::UNIX_EPOCH)?.as_secs().to_string()];
        let mut found: Vec<(String, [f64; 4], [f32; 4])> = cached
            .iter()
            .filter(|c| c.len() == 6 && c[0] == zname && c[1] == stamp[0] && c[2] == stamp[1])
            .filter_map(|c| {
                let b: Vec<f64> = c[4].split(' ').filter_map(|v| v.parse().ok()).collect();
                let d: Vec<f32> = c[5].split(' ').filter_map(|v| v.parse().ok()).collect();
                Some((c[3].clone(), b.try_into().ok()?, d.try_into().ok()?))
            })
            .collect();
        if found.is_empty() {
            log!(pr, "  measuring {zname}");
            let names: Vec<String> =
                match std::fs::File::open(&abs).map_err(anyhow::Error::from).and_then(|f| Ok(zip::ZipArchive::new(f)?))
                {
                    Ok(a) => a
                        .file_names()
                        .filter_map(Result::ok)
                        .filter(|n| n.to_ascii_lowercase().ends_with(".tif"))
                        .map(String::from)
                        .collect(),
                    Err(e) => {
                        pr.warn(&format!("  skipping {} (not a complete ZIP: {e})", z.display()));
                        continue;
                    }
                };
            for n in names {
                let path = format!("/vsizip/{}/{n}", abs.display());
                let info: serde_json::Value =
                    serde_json::from_str(&gdal_output("gdalinfo", &["-json", "-nomd", "-norat", "-noct", &path])?)?;
                let (gt, size) = (&info["geoTransform"], &info["size"]);
                let f = |v: &serde_json::Value| v.as_f64().unwrap_or(0.0);
                let (e0, n1, px) = (f(&gt[0]), f(&gt[3]), f(&gt[1]));
                // RGB, some sheets RGBA (alpha all opaque; the fill is white as in the others).
                if px <= 0.0 || info["bands"].as_array().map_or(0, |b| b.len()) < 3 {
                    pr.warn(&format!("  skipping {zname}/{n}: not an RGB georeferenced sheet"));
                    continue;
                }
                let (w, h) = (f(&size[0]), f(&size[1]));
                // The levels from a 40 m version of the sheet.
                let tmp = work.join("levels.bin");
                gdal(
                    "gdal_translate",
                    &[
                        "-q",
                        "-of",
                        "ENVI",
                        "-co",
                        "INTERLEAVE=BIP",
                        "-b",
                        "1",
                        "-b",
                        "2",
                        "-b",
                        "3",
                        "-tr",
                        "40",
                        "40",
                        "-r",
                        "nearest",
                        &path,
                        utf8(&tmp)?,
                    ],
                )?;
                let small = Photo::read_envi(&tmp, itm::from_wgs84)?;
                for f in [tmp.clone(), tmp.with_extension("hdr"), PathBuf::from(format!("{}.aux.xml", tmp.display()))] {
                    let _ = std::fs::remove_file(f);
                }
                found.push((n, [e0, n1 - h * px, e0 + w * px, n1], imagery::sheet_levels(&small.data)));
            }
        }
        for (n, b, d) in found {
            cache_out += &format!(
                "{zname}\t{}\t{}\t{n}\t{} {} {} {}\t{} {} {} {}\n",
                stamp[0], stamp[1], b[0], b[1], b[2], b[3], d[0], d[1], d[2], d[3]
            );
            sheets.push(Sheet {
                name: format!("{zname}/{n}"),
                gdal: format!("/vsizip/{}/{n}", abs.display()),
                bbox: b,
                levels: d,
            });
        }
        ok.push(abs);
    }
    std::fs::write(&cache_file, cache_out)?;
    if sheets.is_empty() {
        bail!("{}: no sheets (iaf-imagery fetch-mapi2015)", dir.display());
    }
    Ok((sheets, ok))
}

/// "YYYY-MM-DD" (UTC) of a file's modification time.
fn file_date(p: &Path) -> Result<String> {
    let secs = std::fs::metadata(p)?.modified()?.duration_since(std::time::UNIX_EPOCH)?.as_secs() as i64;
    // Days → civil date (H. Hinnant's algorithm).
    let z = secs.div_euclid(86400) + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    Ok(format!("{:04}-{m:02}-{d:02}", yoe + era * 400 + (m <= 2) as i64))
}

/// One `iaf-imagery sentinel2|mapi2015` run.
pub struct Run {
    pub spec: &'static Spec,
    pub install: PathBuf,
    pub theatre: PathBuf,
    /// The layers' root (`<out>/<layer>`, `<out>/.work`).
    pub out: PathBuf,
    /// mapi2015: the folder of downloaded sheet ZIPs.
    pub sheets: PathBuf,
    /// sentinel2: the WorldCover tile cache (`assets/` + [`S2_CACHE`]).
    pub s2_cache: PathBuf,
    /// Only the units overlapping lon0, lat0, lon1, lat1.
    pub area: Option<[f64; 4]>,
    /// Only the estimate.
    pub dry_run: bool,
    /// Only the units whose mark is out of date (after a restore from a mirror).
    pub stale: bool,
    pub threads: usize,
}

/// A unit to convert again (its node i, j at the unit level) and why.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Again {
    pub i: u32,
    pub j: u32,
    pub reason: &'static str,
}

/// What a run has to do (all a dry run gives).
#[derive(Debug, Clone, Default)]
pub struct Estimate {
    /// Work units in the area (after `stale`).
    pub units: usize,
    /// Units to (re)convert: not converted yet or out of date.
    pub to_convert: usize,
    /// Units not converted yet.
    pub unmarked: usize,
    /// Units converted with older sheets or rules.
    pub again: Vec<Again>,
    /// Layer-level nodes the units can hold.
    pub max_nodes: usize,
    /// Bytes to download (sentinel2) or read from the ZIPs (mapi2015), estimated.
    pub download_bytes: f64,
    /// Output size for both looks, estimated.
    pub output_bytes: f64,
}

/// `iaf-imagery sentinel2|mapi2015`: logs the estimate (the CLI's text) and, unless a dry run, converts.
pub fn run(r: &Run, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Estimate> {
    let (spec, install, theatre_dir, out, sheets_dir, area, dry, stale, threads) = (
        r.spec,
        r.install.as_path(),
        r.theatre.as_path(),
        r.out.as_path(),
        r.sheets.as_path(),
        r.area,
        r.dry_run,
        r.stale,
        r.threads,
    );
    let t0 = std::time::Instant::now();
    let theatre = Theatre::load(theatre_dir)?;
    let rules = Rules::load(install, spec.outside_israel, &theatre)?;
    let warp = Georef::load()?;
    let work = if spec.id == "sentinel2" { out.join(".work") } else { out.join(".work").join(spec.id) };
    std::fs::create_dir_all(&work)?;
    let mut prep = match spec.id {
        "sentinel2" => Prep::Sentinel { tiles: BTreeMap::new(), paths: BTreeMap::new() },
        _ => {
            let (sheets, zips) = list_sheets(sheets_dir, &work, pr, cancel)?;
            Prep::Mapi { sheets, zips }
        }
    };
    // Work units: nodes of the unit level with layer pixels (land in the region, off airbases / insets) and,
    // for local sheets, at least one sheet.
    let su = imagery::node_span(spec.unit_level);
    let mut units = Vec::new();
    for j in 0..theatre.rect[3].div_ceil(su) {
        for i in 0..theatre.rect[2].div_ceil(su) {
            let k = (spec.unit_level, i, j);
            let pts: Vec<[f64; 2]> = outline(k).into_iter().map(|[x, y]| warp.to_geo(x, y)).collect();
            let geo = bbox(pts.iter().copied());
            if area.is_some_and(|a| overlap(&a, &geo) <= 0.0) || !rules.node_wanted(k) {
                continue;
            }
            // The unit's rect with UNIT_PAD_M around it: node margins and feathers reach that far.
            let pad = UNIT_PAD_M / crate::georef::UNITS_TO_METRES;
            let r = [
                (i * su) as f64 - pad,
                (j * su) as f64 - pad,
                ((i + 1) * su) as f64 + pad,
                ((j + 1) * su) as f64 + pad,
            ];
            let mut u =
                Unit { k, geo, itm: [0.0; 4], sheets: Vec::new(), rules: rules.tag(r), on_base: rules.touches_base(r) };
            if let Prep::Mapi { sheets, .. } = &prep {
                let b = bbox(pts.iter().map(|p| itm::from_wgs84(p[0], p[1])));
                if !sheets.iter().any(|s| overlap(&b, &s.bbox) > 0.0) {
                    continue;
                }
                // The node margins (≈ 640 m at level 1) and the bilinear neighbours, on the sheets' 2 m grid.
                let pad = 1000.0;
                u.itm = [b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad].map(|v| (v / 2.0).round() * 2.0);
                u.sheets = sheets.iter().filter(|s| overlap(&u.itm, &s.bbox) > 0.0).map(|s| s.name.clone()).collect();
            }
            units.push(u);
        }
    }
    // --stale (after a restore from a mirror): only the units whose mark is out of date, and the unmarked ones on an
    // airbase (written by an older tool, they may hold the old rules); units not converted yet stay so.
    if stale {
        units.retain(|u| !matches!(unit_done(&work, u), Err("no mark")) || u.on_base);
    }
    let per_unit = 1usize << (2 * (spec.unit_level - spec.layer_level));
    let mut est = Estimate { units: units.len(), max_nodes: units.len() * per_unit, ..Default::default() };
    match &mut prep {
        Prep::Sentinel { tiles, .. } => {
            // Every band a padded unit window can touch.
            let lat0 = units.iter().map(|u| (u.geo[1] - 0.05).floor() as i32).min().unwrap_or(0);
            let lat1 = units.iter().map(|u| (u.geo[3] + 0.05).floor() as i32).max().unwrap_or(-1);
            *tiles = list_tiles(&r.s2_cache, BUCKET, lat0, lat1)?;
            let mut download = 0.0;
            for u in &units {
                for (name, &bytes) in tiles.iter() {
                    if let Some(tb) = tile_box(name) {
                        download += bytes as f64 * overlap(&u.geo, &tb);
                    }
                }
            }
            est.download_bytes = download;
            est.output_bytes = units.len() as f64 * per_unit as f64 * 2.0 * 0.45e6 * 1.33;
            log!(
                pr,
                "{} work units (40 km), up to {} level-3 nodes; download ≈ {:.1} GB (WorldCover range reads), output ≈ {:.1} GB for both looks",
                units.len(),
                units.len() * per_unit,
                download / 1e9,
                est.output_bytes / 1e9
            );
        }
        Prep::Mapi { sheets, zips, .. } => {
            // Output: the sheets' area in level-1 nodes (2.54 km), ≈ 0.45 MB per node and look, + ⅓ coarser.
            let km2: f64 = sheets.iter().map(|s| (s.bbox[2] - s.bbox[0]) * (s.bbox[3] - s.bbox[1]) / 1e6).sum();
            let node_km = imagery::node_span(spec.layer_level) as f64 * crate::georef::UNITS_TO_METRES / 1000.0;
            let todo = units.iter().filter(|u| unit_done(&work, u).is_err()).count();
            est.download_bytes = todo as f64
                * ((units.first().map_or(0.0, |u| (u.itm[2] - u.itm[0]) * (u.itm[3] - u.itm[1]))) / 4.0 * 3.0);
            est.output_bytes = km2 / (node_km * node_km) * 2.0 * 0.45e6 * 1.33;
            log!(
                pr,
                "{} sheets in {} ZIPs ({:.0} km²); {} work units (20 km), {} to (re)convert, up to {} level-1 nodes; reads ≈ {:.1} GB from the ZIPs, output ≈ {:.1} GB for both looks",
                sheets.len(),
                zips.len(),
                km2,
                units.len(),
                todo,
                units.len() * per_unit,
                est.download_bytes / 1e9,
                est.output_bytes / 1e9
            );
        }
    }
    // Units to (re)convert and why (a missing mark, changed sheets, changed rules).
    let mut unmarked = 0;
    for u in &units {
        match unit_done(&work, u) {
            Err("no mark") => unmarked += 1,
            Err(why) => {
                log!(pr, "  unit {} {} to convert again: {why}", u.k.1, u.k.2);
                est.again.push(Again { i: u.k.1, j: u.k.2, reason: why });
            }
            Ok(_) => {}
        }
    }
    log!(pr, "  {unmarked} units not converted yet");
    est.unmarked = unmarked;
    est.to_convert = unmarked + est.again.len();
    if dry {
        return Ok(est);
    }
    // The tiles the units to convert read, from the shared cache (fetched there when missing).
    if let Prep::Sentinel { tiles, paths } = &mut prep {
        let names: Vec<String> = tiles
            .keys()
            .filter(|n| {
                units.iter().any(|u| {
                    let b = u.geo;
                    unit_done(&work, u).is_err()
                        && tile_box(n)
                            .is_some_and(|tb| overlap(&[b[0] - 0.01, b[1] - 0.01, b[2] + 0.01, b[3] + 0.01], &tb) > 0.0)
                })
            })
            .cloned()
            .collect();
        // This step's bar is its units' 0..1 (below), as before the tile cache: a part from 0 to 0 holds the bar at 0
        // through the download (the tiles' lines still go to the log).
        let quiet = Part { pr, from: 0.0, to: 0.0 };
        let (p, line) = tile_sources(&r.s2_cache, BUCKET, tiles, &names, &NO_EDGES, &quiet, cancel)?;
        log!(pr, "Sentinel-2: {line}");
        *paths = p;
    }
    for layer in spec.layers {
        for l in 0..=ROOT_LEVEL {
            std::fs::create_dir_all(out.join(layer).join(format!("L{l}")))?;
        }
    }
    let job = Job { spec, prep: &prep, theatre: &theatre, rules: &rules, warp: &warp, work: &work, out, pr };
    let next = AtomicUsize::new(0);
    let written = Mutex::new(BTreeSet::<Key>::new());
    let done_units = AtomicUsize::new(0);
    std::thread::scope(|s| -> Result<()> {
        let workers: Vec<_> = (0..threads.max(1))
            .map(|_| {
                s.spawn(|| -> Result<()> {
                    let mut cache = Cache::default();
                    loop {
                        check(cancel)?;
                        let n = next.fetch_add(1, Ordering::Relaxed);
                        let Some(u) = units.get(n) else { return Ok(()) };
                        let keys = match unit_done(&work, u) {
                            Ok(keys) => keys,
                            Err(_) => {
                                let keys =
                                    convert_unit(&job, u, &mut cache).with_context(|| format!("unit {:?}", u.k))?;
                                let mut text = format!("rules {}\n", u.rules);
                                if !u.sheets.is_empty() {
                                    text += &format!("# {}\n", u.sheets.join(" "));
                                }
                                text.extend(keys.iter().map(|k| format!("{} {} {}\n", k.0, k.1, k.2)));
                                std::fs::write(mark(&work, u), text)?;
                                keys
                            }
                        };
                        written.lock().map_err(|_| anyhow::anyhow!("worker panicked"))?.extend(keys);
                        let d = done_units.fetch_add(1, Ordering::Relaxed) + 1;
                        pr.fraction(d as f32 / units.len() as f32);
                        log!(pr, "  unit {d}/{} ({})", units.len(), crate::progress::duration(t0.elapsed()));
                    }
                })
            })
            .collect();
        for w in workers {
            w.join().map_err(|_| anyhow::anyhow!("worker panicked"))??;
        }
        Ok(())
    })?;
    // Coarser levels: every ancestor of a written node, from its children (all rebuilt each run, so nodes
    // above newly converted units take them in).
    let mut level_nodes: BTreeSet<Key> = written.into_inner().map_err(|_| anyhow::anyhow!("worker panicked"))?;
    for l in spec.layer_level + 1..=ROOT_LEVEL {
        let parents: Vec<Key> = level_nodes
            .iter()
            .filter(|k| k.0 == l - 1)
            .map(|k| (l, k.1 >> 1, k.2 >> 1))
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        let next = AtomicUsize::new(0);
        std::thread::scope(|s| -> Result<()> {
            let workers: Vec<_> = (0..threads.max(1) * 2)
                .map(|_| {
                    s.spawn(|| -> Result<()> {
                        let mut cache = Cache::default();
                        loop {
                            check(cancel)?;
                            let n = next.fetch_add(1, Ordering::Relaxed);
                            let Some(&p) = parents.get(n) else { return Ok(()) };
                            for layer in spec.layers {
                                let dir = out.join(layer);
                                let path = |c: Key| {
                                    let f = dir.join(format!("L{}/c_{}_{}.jpg", c.0, c.1, c.2));
                                    f.exists().then_some(f)
                                };
                                let img = imagery::compose_parent(p, &theatre, path, &mut cache)?;
                                save(&img, &dir.join(format!("L{}/c_{}_{}.jpg", p.0, p.1, p.2)))?;
                            }
                        }
                    })
                })
                .collect();
            for w in workers {
                w.join().map_err(|_| anyhow::anyhow!("worker panicked"))??;
            }
            Ok(())
        })?;
        level_nodes.extend(parents);
    }
    for layer in spec.layers {
        write_manifest(&prep, &out.join(layer), layer)?;
    }
    log!(pr, "done in {} -> {}", crate::progress::duration(t0.elapsed()), out.display());
    Ok(est)
}

fn mark(work: &Path, u: &Unit) -> PathBuf {
    work.join(format!("done_{}_{}", u.k.1, u.k.2))
}

/// The keys a finished unit wrote, or why it must be (re)converted.
fn unit_done(work: &Path, u: &Unit) -> std::result::Result<Vec<Key>, &'static str> {
    let text = std::fs::read_to_string(mark(work, u)).map_err(|_| "no mark")?;
    mark_valid(&text, u)?;
    Ok(text
        .lines()
        .filter(|l| !l.starts_with("rules ") && !l.starts_with("# "))
        .filter_map(|l| {
            let v: Vec<u32> = l.split(' ').filter_map(|x| x.parse().ok()).collect();
            (v.len() == 3).then(|| (v[0], v[1], v[2]))
        })
        .collect())
}

/// A mark (`rules <tag>`, `# <sheets>`, then one written key per line) still holds when its sheets and rules tag are the
/// unit's. A mark from before the rules tags holds only off the airbases (the one rule changed since: RULES_VERSION 2).
fn mark_valid(text: &str, u: &Unit) -> std::result::Result<(), &'static str> {
    let sheets = text.lines().find_map(|l| l.strip_prefix("# ")).unwrap_or("");
    if sheets != u.sheets.join(" ") {
        return Err("sheets changed");
    }
    match text.lines().find_map(|l| l.strip_prefix("rules ")) {
        Some(tag) if tag != u.rules => Err("rules changed"),
        None if u.on_base => Err("rules changed (a mark from before the rules tags, on an airbase)"),
        _ => Ok(()),
    }
}

fn save(img: &image::RgbImage, path: &Path) -> Result<()> {
    let mut f = std::io::BufWriter::new(std::fs::File::create(path)?);
    img.write_with_encoder(image::codecs::jpeg::JpegEncoder::new_with_quality(&mut f, JPEG_QUALITY))?;
    Ok(())
}

/// What every work unit of a run shares.
struct Job<'a> {
    spec: &'a Spec,
    prep: &'a Prep,
    theatre: &'a Theatre,
    rules: &'a Rules,
    warp: &'a Georef,
    work: &'a Path,
    out: &'a Path,
    pr: &'a dyn Progress,
}

/// Cuts one unit's source window and writes its layer-level nodes; returns the keys written.
fn convert_unit(job: &Job, u: &Unit, cache: &mut Cache) -> Result<Vec<Key>> {
    let Job { spec, prep, theatre, rules, warp, work, out, pr } = *job;
    let (vrt_s, bin_s);
    let k = u.k;
    let tmp: PathBuf = work.join(format!("unit_{}_{}", k.1, k.2));
    let vrt_unit = tmp.with_extension("vrt");
    let bin = tmp.with_extension("bin");
    (vrt_s, bin_s) = (utf8(&vrt_unit)?.to_string(), utf8(&bin)?.to_string());
    let src: Box<dyn Imagery> = match prep {
        Prep::Sentinel { paths, .. } => {
            let b = u.geo;
            let pad = 0.01;
            let bb = [b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad];
            let urls: Vec<String> = paths
                .iter()
                .filter(|(n, _)| tile_box(n).is_some_and(|tb| overlap(&bb, &tb) > 0.0))
                .map(|(_, p)| p.clone())
                .collect();
            if urls.is_empty() {
                return Ok(Vec::new());
            }
            // The VRT is the window itself (on the source's pixel grid; no data where no tile is).
            let te = bb.map(|v| format!("{v:.6}"));
            let res = format!("{:.12}", 1.0 / 12000.0);
            let mut a =
                vec!["-q", "-overwrite", "-te", &te[0], &te[1], &te[2], &te[3], "-tr", &res, &res, "-tap", &vrt_s];
            a.extend(urls.iter().map(String::as_str));
            gdal("gdalbuildvrt", &a)?;
            let args = [
                "-q",
                "-of",
                "ENVI",
                "-co",
                "INTERLEAVE=BIP",
                "-b",
                "1",
                "-b",
                "2",
                "-b",
                "3",
                "-b",
                "4",
                &vrt_s,
                &bin_s,
            ];
            // Network hiccups (e.g. a TLS read cut short) make GDAL fail without a message: retry.
            let mut tries = 0;
            while let Err(e) = gdal("gdal_translate", &args) {
                tries += 1;
                if tries == 4 {
                    return Err(e);
                }
                pr.warn(&format!("  unit {k:?}: fetch failed, retrying ({tries}/3)"));
                std::thread::sleep(std::time::Duration::from_secs(5 * tries));
            }
            Box::new(Source::read_envi(&bin)?)
        }
        Prep::Mapi { sheets, .. } => {
            // The window on the sheets' 2 m grid (black where no sheet is); only the unit's sheets are opened
            // (opening a sheet inside its ZIP inflates it up to the TIFF directory, a second or two each).
            let w = u.itm.map(|v| format!("{v:.0}"));
            let mut a = vec![
                "-q",
                "-overwrite",
                "-a_srs",
                "EPSG:2039",
                "-allow_projection_difference",
                "-b",
                "1",
                "-b",
                "2",
                "-b",
                "3",
            ];
            a.extend(["-te", &w[0], &w[1], &w[2], &w[3], "-tr", "2", "2", &vrt_s]);
            a.extend(sheets.iter().filter(|s| u.sheets.contains(&s.name)).map(|s| s.gdal.as_str()));
            gdal("gdalbuildvrt", &a)?;
            gdal("gdal_translate", &["-q", "-of", "ENVI", "-co", "INTERLEAVE=BIP", &vrt_s, &bin_s])?;
            let mut photo = Photo::read_envi(&bin, itm::from_wgs84)?;
            photo.levels = sheets.iter().filter(|s| u.sheets.contains(&s.name)).map(|s| (s.bbox, s.levels)).collect();
            Box::new(photo)
        }
    };
    let d = spec.unit_level - spec.layer_level;
    let mut nodes: Vec<Key> = (0..1u32 << (2 * d))
        .map(|n| (spec.layer_level, (k.1 << d) + n % (1 << d), (k.2 << d) + n / (1 << d)))
        .collect();
    // The original's finer nodes (the site insets) in the unit too: near the jet the runtime draws them instead
    // of the layer's node above, so the layer's feather around a kept inset must be in them as well (a node
    // wholly inside the inset composes to nothing and stays the original's).
    let mut finer: Vec<Key> = theatre
        .nodes
        .iter()
        .filter(|n| n.0 < spec.layer_level && (n.1 >> (k.0 - n.0), n.2 >> (k.0 - n.0)) == (k.1, k.2))
        .copied()
        .collect();
    finer.sort();
    nodes.extend(finer);
    let mut keys = Vec::new();
    for n in nodes {
        if !theatre.inside(n) || !rules.node_wanted(n) {
            continue;
        }
        if let Some((matched, modern)) = imagery::compose_node(n, theatre, rules, warp, src.as_ref(), cache)? {
            for (layer, img) in spec.layers.iter().zip([&matched, &modern]) {
                save(img, &out.join(layer).join(format!("L{}/c_{}_{}.jpg", n.0, n.1, n.2)))?;
            }
            keys.push(n);
        }
    }
    drop(src);
    for f in [vrt_unit, bin.clone(), bin.with_extension("hdr"), PathBuf::from(format!("{}.aux.xml", bin.display()))] {
        let _ = std::fs::remove_file(f);
    }
    Ok(keys)
}

/// `manifest.json`: what the runtime and the Extras page need (docs/imagery.md §5).
fn write_manifest(prep: &Prep, dir: &Path, layer: &str) -> Result<()> {
    let mut nodes = serde_json::Map::new();
    let mut count = 0;
    let mut finest = ROOT_LEVEL;
    for l in 0..=ROOT_LEVEL {
        let Ok(entries) = std::fs::read_dir(dir.join(format!("L{l}"))) else { continue };
        let mut v = Vec::new();
        for e in entries {
            let name = e?.file_name().to_string_lossy().to_string();
            if let Some(ij) = name.strip_prefix("c_").and_then(|s| s.strip_suffix(".jpg")) {
                let (i, j) = ij.split_once('_').context("node name")?;
                v.push([i.parse::<u32>()?, j.parse::<u32>()?]);
            }
        }
        v.sort();
        if !v.is_empty() {
            finest = finest.min(l);
        }
        count += v.len();
        nodes.insert(l.to_string(), serde_json::json!(v));
    }
    let modern = layer.ends_with("_modern");
    let looks = if modern { "modern colours" } else { "1998 colours" };
    let mut m = match prep {
        Prep::Sentinel { .. } => serde_json::json!({
            "title": format!("Sentinel-2 10 m, {looks}"),
            "region": "outside_israel",
            "source": "ESA WorldCover 2021 Sentinel-2 median L2A RGB composite (10 m), https://esa-worldcover.org",
            "licence": "CC BY 4.0",
            "attribution": "Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium; ESA WorldCover project 2021 (CC BY 4.0)",
            "resolution_m": 10,
        }),
        Prep::Mapi { sheets, zips, .. } => {
            // The data.gov.il licence in force at download time governs (docs/imagery-sources.md §2.1).
            let dates: BTreeSet<String> = zips.iter().map(|z| file_date(z)).collect::<Result<_>>()?;
            let downloaded = match (dates.first(), dates.last()) {
                (Some(a), Some(b)) if a != b => format!("{a}..{b}"),
                (Some(a), _) => a.clone(),
                _ => String::new(),
            };
            serde_json::json!({
                "title": format!("Survey of Israel 2015 2 m, {looks}"),
                "region": "israel",
                "source": "Survey of Israel aerial orthophoto 2015, 2 m (data.gov.il, one ZIP per 1:50 000 sheet)",
                "licence": "data.gov.il open licence (Israel Government Open Data terms of use, https://data.gov.il/he/terms-of-use)",
                "attribution": "© Survey of Israel 2015, via data.gov.il",
                "resolution_m": 2,
                "downloaded": downloaded,
                "sheets": sheets.iter().map(|s| s.name.clone()).collect::<Vec<_>>(),
            })
        }
    };
    let o = m.as_object_mut().context("manifest")?;
    o.insert("name".into(), layer.into());
    o.insert("colours".into(), (if modern { "modern" } else { "1998" }).into());
    o.insert("levels".into(), serde_json::json!([finest, ROOT_LEVEL]));
    o.insert("node_count".into(), count.into());
    o.insert("nodes".into(), nodes.into());
    std::fs::write(dir.join("manifest.json"), serde_json::to_string_pretty(&m)?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A bucket nothing answers on: any network call fails.
    const OFFLINE: &str = "http://127.0.0.1:9";

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("iaf-s2-cache-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    /// A complete cache (listing and whole tiles) is read with no network at all.
    #[test]
    fn a_complete_cache_needs_no_network() {
        let c = tmp("complete");
        std::fs::write(c.join("listing_N30.tsv"), "N30E034\t5\nN30E035\t3\n").unwrap();
        std::fs::write(c.join(tile_file("N30E034")), "12345").unwrap();
        std::fs::write(c.join(tile_file("N30E035")), "123").unwrap();
        let tiles = list_tiles(&c, OFFLINE, 30, 30).unwrap();
        assert_eq!(tiles.len(), 2);
        let names: Vec<String> = tiles.keys().cloned().collect();
        let (paths, line) =
            tile_sources(&c, OFFLINE, &tiles, &names, &NO_EDGES, &crate::progress::Stdout, &AtomicBool::new(false))
                .unwrap();
        assert_eq!(paths["N30E034"], c.join(tile_file("N30E034")).to_str().unwrap());
        assert!(line.contains("2 reused") && line.contains("0 fetched"), "{line}");
        assert!(list_tiles(&c, OFFLINE, 31, 31).is_err(), "an unlisted band goes to the network");
        std::fs::remove_dir_all(&c).unwrap();
    }

    /// An edge tile is never downloaded whole: the cache's whole copy (e.g. one the other game fetched) is read, else
    /// its kept 20 m extract when it covers the window; one still to cut needs the network (none here: an error).
    #[test]
    fn an_edge_tile_is_read_from_disk() {
        let c = tmp("coarse");
        std::fs::write(c.join(tile_file("N30E034")), "12345").unwrap();
        std::fs::write(edge_file(&c, "N30E033"), "20m").unwrap();
        let tiles = BTreeMap::from([("N30E033".to_string(), 9), ("N30E034".to_string(), 5)]);
        let names: Vec<String> = tiles.keys().cloned().collect();
        let no = AtomicBool::new(false);
        let go = |window| {
            let edges = Edges { names: &names, window };
            tile_sources(&c, OFFLINE, &tiles, &names, &edges, &crate::progress::Stdout, &no)
        };
        std::fs::write(edge_file(&c, "N30E033").with_extension("ok"), "33.5 30 34 30.5\n").unwrap();
        let (paths, line) = go([33.5, 30.0, 34.5, 30.5]).unwrap();
        assert_eq!(paths["N30E034"], c.join(tile_file("N30E034")).to_str().unwrap(), "the cached copy");
        assert_eq!(paths["N30E033"], edge_file(&c, "N30E033").to_str().unwrap(), "the kept extract");
        assert!(!c.join(tile_file("N30E033")).exists() && line.contains("1 kept, 0 cut"), "{line}");
        assert!(go([33.2, 30.0, 34.5, 30.5]).is_err(), "a wider window cuts it again (from the network)");
        std::fs::remove_dir_all(&c).unwrap();
    }

    /// A listing that lists nothing, or only its first page, is refused (never cached); empty files are left out.
    #[test]
    fn a_broken_listing_is_refused() {
        let item = |k: &str, n: u64| {
            format!(
                "<Contents><Key>rgbnir/2021/N30/ESA_WorldCover_10m_2021_v200_{k}_S2RGBNIR.tif</Key><Size>{n}</Size></Contents>"
            )
        };
        let ok = format!(
            "<ListBucketResult><IsTruncated>false</IsTruncated>{}{}</ListBucketResult>",
            item("N30E034", 9),
            item("N30E035", 0)
        );
        assert_eq!(parse_listing(&ok).unwrap(), "N30E034\t9\n");
        assert!(parse_listing("<ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>").is_err());
        assert!(parse_listing("").is_err(), "a cut answer");
        assert!(parse_listing(&ok.replace("<IsTruncated>false", "<IsTruncated>true")).is_err(), "a first page");
    }

    /// Two downloads of one tile at once (both games): the lock makes the second find the first's whole file.
    #[test]
    fn two_downloads_of_one_tile_share_it() {
        let (c, bucket) = (tmp("lock"), tmp("lock-bucket"));
        let body = vec![7u8; 3_000_000];
        std::fs::write(bucket.join("t.tif"), &body).unwrap();
        let (url, dest) = (format!("file://{}/t.tif", bucket.display()), c.join("t.tif"));
        std::thread::scope(|s| {
            for _ in 0..2 {
                s.spawn(|| curl_to(&url, &dest, body.len() as u64, "test", &AtomicBool::new(false), &|_| {}).unwrap());
            }
        });
        assert_eq!(std::fs::read(&dest).unwrap(), body);
        assert!(!dest.with_extension("part").exists());
        std::fs::remove_dir_all(&c).unwrap();
        std::fs::remove_dir_all(&bucket).unwrap();
    }

    /// A missing or truncated tile is fetched into the cache under the bucket's file name (a file:// bucket here).
    #[test]
    fn a_missing_tile_is_fetched_into_the_cache() {
        let (c, bucket) = (tmp("fetch"), tmp("bucket"));
        let src = bucket.join(PREFIX).join("N30");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join(tile_file("N30E034")), "abcdef").unwrap();
        std::fs::write(src.join(tile_file("N30E035")), "xyz").unwrap();
        std::fs::write(c.join(tile_file("N30E035")), "x").unwrap();
        let tiles = BTreeMap::from([("N30E034".to_string(), 6), ("N30E035".to_string(), 3)]);
        let names: Vec<String> = tiles.keys().cloned().collect();
        let url = format!("file://{}", bucket.display());
        let (paths, line) =
            tile_sources(&c, &url, &tiles, &names, &NO_EDGES, &crate::progress::Stdout, &AtomicBool::new(false))
                .unwrap();
        assert_eq!(std::fs::read(c.join(tile_file("N30E034"))).unwrap(), b"abcdef");
        assert_eq!(std::fs::read(c.join(tile_file("N30E035"))).unwrap(), b"xyz", "the truncated one again");
        assert!(!paths["N30E035"].starts_with("/vsicurl/") && line.contains("2 fetched"), "{line}");
        std::fs::remove_dir_all(&c).unwrap();
        std::fs::remove_dir_all(&bucket).unwrap();
    }

    /// A part left by a cut download resumes where it stopped (its bytes kept, the rest appended), and the bytes so
    /// far reach `on_bytes`; a part longer than the listed size is dropped and fetched again.
    #[test]
    fn a_partial_tile_resumes() {
        let (c, bucket) = (tmp("resume"), tmp("resume-bucket"));
        std::fs::write(bucket.join("t.tif"), b"abcdefgh").unwrap();
        let (url, dest) = (format!("file://{}/t.tif", bucket.display()), c.join("t.tif"));
        let no = AtomicBool::new(false);
        // "ABC": three bytes kept from a cut run (upper case, so a fresh fetch would show).
        std::fs::write(dest.with_extension("part"), b"ABC").unwrap();
        curl_to(&url, &dest, 8, "test", &no, &|_| {}).unwrap();
        assert_eq!(std::fs::read(&dest).unwrap(), b"ABCdefgh");
        std::fs::remove_file(&dest).unwrap();
        std::fs::write(dest.with_extension("part"), b"too long a part").unwrap();
        curl_to(&url, &dest, 8, "test", &no, &|_| {}).unwrap();
        assert_eq!(std::fs::read(&dest).unwrap(), b"abcdefgh");
        std::fs::remove_dir_all(&c).unwrap();
        std::fs::remove_dir_all(&bucket).unwrap();
    }

    /// Only a part that starts as a TIFF resumes; an error page or a missing part starts afresh.
    #[test]
    fn a_dem_part_resumes_only_as_a_tiff() {
        let d = tmp("dempart");
        let part = d.join("t.part");
        assert!(!resumable(&part), "no part");
        std::fs::write(&part, b"II*\0abc").unwrap();
        assert!(resumable(&part));
        std::fs::write(&part, b"<?xml version").unwrap();
        assert!(!resumable(&part), "an error page");
        std::fs::remove_dir_all(&d).unwrap();
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

    fn unit(rules: &str, on_base: bool) -> Unit {
        Unit {
            k: (4, 1, 2),
            geo: [0.0; 4],
            itm: [0.0; 4],
            sheets: vec!["a.zip/a.tif".into()],
            rules: rules.into(),
            on_base,
        }
    }

    #[test]
    fn marks_hold_only_for_the_same_rules_and_sheets() {
        let mark = "rules v2 00ff\n# a.zip/a.tif\n1 3 4\n";
        assert_eq!(mark_valid(mark, &unit("v2 00ff", true)), Ok(()));
        assert_eq!(mark_valid(mark, &unit("v2 0100", true)), Err("rules changed"), "the footprint changed");
        assert_eq!(mark_valid(mark, &unit("v3 00ff", false)), Err("rules changed"), "RULES_VERSION bumped");
        let mut u = unit("v2 00ff", false);
        u.sheets.push("b.zip/b.tif".into());
        assert_eq!(mark_valid(mark, &u), Err("sheets changed"));
        // Marks from before the rules tags: kept off the airbases, converted again on them.
        let old = "# a.zip/a.tif\n1 3 4\n";
        assert_eq!(mark_valid(old, &unit("v2 00ff", false)), Ok(()));
        assert!(mark_valid(old, &unit("v2 00ff", true)).is_err());
    }
}
