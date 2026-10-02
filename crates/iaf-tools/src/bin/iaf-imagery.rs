//! Modern terrain imagery layers (docs/imagery.md).
//!
//! `iaf-imagery sentinel2 <install-dir> <theatre-dir> <out-root> [--area lon0,lat0,lon1,lat1] [--dry-run] [--threads N]`
//!
//! Fetches ESA WorldCover 2021 Sentinel-2 RGB (10 m, CC BY 4.0) for the land outside Israel (or
//! only `--area`) by HTTP range reads through GDAL (`gdalbuildvrt` / `gdal_translate` over
//! `/vsicurl/`), warps it into the game frame with the georeference, and writes two layers under
//! `<out-root>`: `sentinel2` (colour-matched to the 1998 imagery) and `sentinel2_modern`. Each is a
//! node set like the converted theatre (`L<L>/c_<i>_<j>.jpg`, levels 3..11) plus `manifest.json`.
//! Resumable: finished 40 km work units are remembered in `<out-root>/.work/`.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};

use anyhow::{Context, Result, bail};
use iaf_tools::georef::Georef;
use iaf_tools::imagery::{self, Cache, Key, LAYER_LEVEL, ROOT_LEVEL, Rules, Source, Theatre};

const BUCKET: &str = "https://esa-worldcover-s2.s3.eu-central-1.amazonaws.com";
const PREFIX: &str = "rgbnir/2021";
/// Work unit: one level-5 node (40 km of game frame, ~27 km real): 16 level-3 nodes.
const UNIT_LEVEL: u32 = 5;
const JPEG_QUALITY: u8 = 88;
const LAYERS: [&str; 2] = ["sentinel2", "sentinel2_modern"];

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let [cmd, theatre, layers, level, i, j, png] = &args[..]
        && cmd == "compare"
    {
        // Side by side: the original as drawn, then each layer's node (docs/imagery.md §6).
        let t = Theatre::load(Path::new(theatre))?;
        let k: Key = (level.parse()?, i.parse()?, j.parse()?);
        let mut row = image::RgbImage::new(1024 * 3, 1024);
        if let Some(img) = t.rendition(k, &mut Cache::default())? {
            image::imageops::replace(&mut row, img.as_ref(), 0, 0);
        }
        for (n, layer) in LAYERS.iter().enumerate() {
            let f = Path::new(layers).join(layer).join(format!("L{}/c_{}_{}.jpg", k.0, k.1, k.2));
            if let Ok(img) = image::open(&f) {
                image::imageops::replace(&mut row, &img.to_rgb8(), 1024 * (n as i64 + 1), 0);
            }
        }
        row.save(png)?;
        return Ok(());
    }
    let usage = "usage: iaf-imagery sentinel2 <install-dir> <theatre-dir> <out-root> [--area lon0,lat0,lon1,lat1] [--dry-run] [--threads N]";
    let [source, install, theatre, out, rest @ ..] = &args[..] else { bail!(usage) };
    if source != "sentinel2" {
        bail!("unknown source '{source}' (known: sentinel2)\n{usage}");
    }
    let mut area: Option<[f64; 4]> = None;
    let mut dry = false;
    let mut threads = 4;
    let mut it = rest.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--area" => {
                let v: Vec<f64> = it.next().context(usage)?.split(',').map(str::parse).collect::<Result<_, _>>()?;
                area = Some(v.try_into().map_err(|_| anyhow::anyhow!("--area wants lon0,lat0,lon1,lat1"))?);
            }
            "--dry-run" => dry = true,
            "--threads" => threads = it.next().context(usage)?.parse()?,
            _ => bail!(usage),
        }
    }
    run(Path::new(install), Path::new(theatre), Path::new(out), area, dry, threads)
}

/// Lon / lat bounding box (lon0, lat0, lon1, lat1) of a node, from its outline.
fn geo_bbox(warp: &Georef, k: Key) -> [f64; 4] {
    let s = imagery::node_span(k.0) as f64;
    let mut b = [f64::MAX, f64::MAX, f64::MIN, f64::MIN];
    for t in 0..=16 {
        let f = t as f64 / 16.0;
        for (x, y) in [(f, 0.0), (f, 1.0), (0.0, f), (1.0, f)] {
            let [lon, lat] = warp.to_geo((k.1 as f64 + x) * s, (k.2 as f64 + y) * s);
            b = [b[0].min(lon), b[1].min(lat), b[2].max(lon), b[3].max(lat)];
        }
    }
    b
}

fn overlap(a: &[f64; 4], b: &[f64; 4]) -> f64 {
    ((a[2].min(b[2]) - a[0].max(b[0])).max(0.0)) * ((a[3].min(b[3]) - a[1].max(b[1])).max(0.0))
}

/// The WorldCover 1°×1° tiles (name → bytes) in the latitude bands N<lat0>..N<lat1> (S3 listing).
fn list_tiles(lat0: i32, lat1: i32) -> Result<BTreeMap<String, u64>> {
    let mut out = BTreeMap::new();
    for lat in lat0..=lat1 {
        let url = format!("{BUCKET}/?list-type=2&prefix={PREFIX}/N{lat:02}/");
        let o = Command::new("curl").args(["-sf", "-m", "60", &url]).output().context("running curl")?;
        if !o.status.success() {
            bail!("listing {url} failed");
        }
        let xml = String::from_utf8_lossy(&o.stdout);
        for c in xml.split("<Contents>").skip(1) {
            let tag = |t: &str| c.split(&format!("<{t}>")).nth(1).and_then(|s| s.split('<').next()).unwrap_or("").to_string();
            let key = tag("Key");
            if let Some(name) = key.rsplit('/').next().and_then(|f| f.split('_').nth(5)) {
                out.insert(name.to_string(), tag("Size").parse().unwrap_or(0));
            }
        }
    }
    Ok(out)
}

/// The tile's 1° box (lon0, lat0, lon1, lat1) from its name ("N30E032" = 30..31 N, 32..33 E).
fn tile_box(name: &str) -> Option<[f64; 4]> {
    let lat: f64 = name.get(1..3)?.parse().ok()?;
    let lon: f64 = name.get(4..7)?.parse().ok()?;
    let lat = if name.starts_with('S') { -lat } else { lat };
    let lon = if name.as_bytes().get(3) == Some(&b'W') { -lon } else { lon };
    Some([lon, lat, lon + 1.0, lat + 1.0])
}

fn tile_url(name: &str) -> String {
    format!("{BUCKET}/{PREFIX}/{}/ESA_WorldCover_10m_2021_v200_{name}_S2RGBNIR.tif", &name[..3])
}

fn gdal(cmd: &str, args: &[&str]) -> Result<()> {
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
        let err: Vec<String> = String::from_utf8_lossy(&o.stderr).lines().filter(|l| !l.contains("cannot open shared object")).map(String::from).collect();
        bail!("{cmd} {} failed ({}):\n{}{}", args.join(" "), o.status, String::from_utf8_lossy(&o.stdout), err.join("\n"));
    }
    Ok(())
}

fn run(install: &Path, theatre_dir: &Path, out: &Path, area: Option<[f64; 4]>, dry: bool, threads: usize) -> Result<()> {
    let t0 = std::time::Instant::now();
    let theatre = Theatre::load(theatre_dir)?;
    let rules = Rules::load(install, true)?;
    let warp = Georef::load()?;
    // Work units: level-5 nodes with layer pixels (land outside Israel, off airbases / insets).
    let su = imagery::node_span(UNIT_LEVEL);
    let mut units = Vec::new();
    for j in 0..theatre.rect[3].div_ceil(su) {
        for i in 0..theatre.rect[2].div_ceil(su) {
            let k = (UNIT_LEVEL, i, j);
            let b = geo_bbox(&warp, k);
            if area.is_some_and(|a| overlap(&a, &b) <= 0.0) || !rules.node_wanted(k) {
                continue;
            }
            units.push((k, b));
        }
    }
    // Every band a padded unit window can touch.
    let lat0 = units.iter().map(|u| (u.1[1] - 0.05).floor() as i32).min().unwrap_or(0);
    let lat1 = units.iter().map(|u| (u.1[3] + 0.05).floor() as i32).max().unwrap_or(-1);
    let tiles = list_tiles(lat0, lat1)?;
    let mut download = 0.0;
    for (_, b) in &units {
        for (name, &bytes) in &tiles {
            if let Some(tb) = tile_box(name) {
                download += bytes as f64 * overlap(b, &tb);
            }
        }
    }
    let l3_per_unit = 1usize << (2 * (UNIT_LEVEL - LAYER_LEVEL));
    println!(
        "{} work units (40 km), up to {} level-3 nodes; download ≈ {:.1} GB (WorldCover range reads), output ≈ {:.1} GB for both looks",
        units.len(),
        units.len() * l3_per_unit,
        download / 1e9,
        units.len() as f64 * l3_per_unit as f64 * 2.0 * 0.45e6 * 1.33 / 1e9
    );
    if dry {
        return Ok(());
    }
    let work = out.join(".work");
    std::fs::create_dir_all(&work)?;
    for layer in LAYERS {
        for l in LAYER_LEVEL..=ROOT_LEVEL {
            std::fs::create_dir_all(out.join(layer).join(format!("L{l}")))?;
        }
    }
    let next = AtomicUsize::new(0);
    let written = Mutex::new(BTreeSet::<Key>::new());
    let done_units = AtomicUsize::new(0);
    std::thread::scope(|s| -> Result<()> {
        let workers: Vec<_> = (0..threads.max(1))
            .map(|_| {
                s.spawn(|| -> Result<()> {
                    let mut cache = Cache::default();
                    loop {
                        let n = next.fetch_add(1, Ordering::Relaxed);
                        let Some(&(k, b)) = units.get(n) else { return Ok(()) };
                        let mark = work.join(format!("done_{}_{}", k.1, k.2));
                        let keys = if mark.exists() {
                            std::fs::read_to_string(&mark)?.lines().filter_map(|l| {
                                let v: Vec<u32> = l.split(' ').filter_map(|x| x.parse().ok()).collect();
                                (v.len() == 3).then(|| (v[0], v[1], v[2]))
                            }).collect()
                        } else {
                            let keys = convert_unit(k, b, &tiles, &theatre, &rules, &warp, &work, out, &mut cache)
                                .with_context(|| format!("unit {k:?}"))?;
                            let text: String = keys.iter().map(|k| format!("{} {} {}\n", k.0, k.1, k.2)).collect();
                            std::fs::write(&mark, text)?;
                            keys
                        };
                        written.lock().unwrap().extend(keys);
                        let d = done_units.fetch_add(1, Ordering::Relaxed) + 1;
                        println!("  unit {d}/{} ({:.0} s)", units.len(), t0.elapsed().as_secs_f64());
                    }
                })
            })
            .collect();
        for w in workers {
            w.join().map_err(|_| anyhow::anyhow!("worker panicked"))??;
        }
        Ok(())
    })?;
    // Coarser levels: every ancestor of a written node, from its children.
    let mut level_nodes: BTreeSet<Key> = written.into_inner().unwrap();
    for l in LAYER_LEVEL + 1..=ROOT_LEVEL {
        let parents: Vec<Key> = level_nodes.iter().filter(|k| k.0 == l - 1).map(|k| (l, k.1 >> 1, k.2 >> 1)).collect::<BTreeSet<_>>().into_iter().collect();
        let next = AtomicUsize::new(0);
        std::thread::scope(|s| -> Result<()> {
            let workers: Vec<_> = (0..threads.max(1) * 2)
                .map(|_| {
                    s.spawn(|| -> Result<()> {
                        let mut cache = Cache::default();
                        loop {
                            let n = next.fetch_add(1, Ordering::Relaxed);
                            let Some(&p) = parents.get(n) else { return Ok(()) };
                            for layer in LAYERS {
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
    for layer in LAYERS {
        write_manifest(&out.join(layer), layer)?;
    }
    println!("done in {:.0} s -> {}", t0.elapsed().as_secs_f64(), out.display());
    Ok(())
}

fn save(img: &image::RgbImage, path: &Path) -> Result<()> {
    let mut f = std::io::BufWriter::new(std::fs::File::create(path)?);
    img.write_with_encoder(image::codecs::jpeg::JpegEncoder::new_with_quality(&mut f, JPEG_QUALITY))?;
    Ok(())
}

/// Fetches one unit's source window and writes its level-3 nodes; returns the keys written.
#[allow(clippy::too_many_arguments)]
fn convert_unit(
    k: Key,
    b: [f64; 4],
    tiles: &BTreeMap<String, u64>,
    theatre: &Theatre,
    rules: &Rules,
    warp: &Georef,
    work: &Path,
    out: &Path,
    cache: &mut Cache,
) -> Result<Vec<Key>> {
    let pad = 0.01;
    let bb = [b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad];
    let urls: Vec<String> = tiles
        .keys()
        .filter(|n| tile_box(n).is_some_and(|tb| overlap(&bb, &tb) > 0.0))
        .map(|n| format!("/vsicurl/{}", tile_url(n)))
        .collect();
    if urls.is_empty() {
        return Ok(Vec::new());
    }
    let tmp: PathBuf = work.join(format!("unit_{}_{}", k.1, k.2));
    let vrt = tmp.with_extension("vrt");
    let bin = tmp.with_extension("bin");
    // The VRT is the window itself (on the source's pixel grid; no data where no tile is).
    let te = bb.map(|v| format!("{v:.6}"));
    let res = format!("{:.12}", 1.0 / 12000.0);
    let mut a = vec!["-q", "-overwrite", "-te", &te[0], &te[1], &te[2], &te[3], "-tr", &res, &res, "-tap", vrt.to_str().unwrap()];
    a.extend(urls.iter().map(String::as_str));
    gdal("gdalbuildvrt", &a)?;
    let args = ["-q", "-of", "ENVI", "-co", "INTERLEAVE=BIP", "-b", "1", "-b", "2", "-b", "3", "-b", "4", vrt.to_str().unwrap(), bin.to_str().unwrap()];
    // Network hiccups (e.g. a TLS read cut short) make GDAL fail without a message: retry.
    let mut tries = 0;
    while let Err(e) = gdal("gdal_translate", &args) {
        tries += 1;
        if tries == 4 {
            return Err(e);
        }
        eprintln!("  unit {k:?}: fetch failed, retrying ({tries}/3)");
        std::thread::sleep(std::time::Duration::from_secs(5 * tries));
    }
    let src = Source::read_envi(&bin)?;
    let d = UNIT_LEVEL - LAYER_LEVEL;
    let mut keys = Vec::new();
    for j in 0..1u32 << d {
        for i in 0..1u32 << d {
            let n = (LAYER_LEVEL, (k.1 << d) + i, (k.2 << d) + j);
            if !theatre.inside(n) || !rules.node_wanted(n) {
                continue;
            }
            if let Some((matched, modern)) = imagery::compose_node(n, theatre, rules, warp, &src, cache)? {
                for (layer, img) in LAYERS.iter().zip([&matched, &modern]) {
                    save(img, &out.join(layer).join(format!("L{}/c_{}_{}.jpg", n.0, n.1, n.2)))?;
                }
                keys.push(n);
            }
        }
    }
    for f in [vrt, bin.clone(), bin.with_extension("hdr"), PathBuf::from(format!("{}.aux.xml", bin.display()))] {
        let _ = std::fs::remove_file(f);
    }
    Ok(keys)
}

/// `manifest.json`: what the runtime and the Extras page need (docs/imagery.md §5).
fn write_manifest(dir: &Path, layer: &str) -> Result<()> {
    let mut nodes = serde_json::Map::new();
    let mut count = 0;
    for l in LAYER_LEVEL..=ROOT_LEVEL {
        let mut v = Vec::new();
        for e in std::fs::read_dir(dir.join(format!("L{l}")))? {
            let name = e?.file_name().to_string_lossy().to_string();
            if let Some(ij) = name.strip_prefix("c_").and_then(|s| s.strip_suffix(".jpg")) {
                let (i, j) = ij.split_once('_').context("node name")?;
                v.push([i.parse::<u32>()?, j.parse::<u32>()?]);
            }
        }
        v.sort();
        count += v.len();
        nodes.insert(l.to_string(), serde_json::json!(v));
    }
    let modern = layer.ends_with("_modern");
    let m = serde_json::json!({
        "name": layer,
        "title": if modern { "Sentinel-2 10 m, modern colours" } else { "Sentinel-2 10 m, 1998 colours" },
        "region": "outside_israel",
        "source": "ESA WorldCover 2021 Sentinel-2 median L2A RGB composite (10 m), https://esa-worldcover.org",
        "licence": "CC BY 4.0",
        "attribution": "Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium; ESA WorldCover project 2021 (CC BY 4.0)",
        "resolution_m": 10,
        "colours": if modern { "modern" } else { "1998" },
        "levels": [LAYER_LEVEL, ROOT_LEVEL],
        "node_count": count,
        "nodes": nodes,
    });
    std::fs::write(dir.join("manifest.json"), serde_json::to_string_pretty(&m)?)?;
    Ok(())
}
