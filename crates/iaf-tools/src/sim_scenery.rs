//! `iaf-sim scenery` (iaf-2026/docs/scenery.md): the original game's scenery and road layer (docs/scenery.md) made
//! for Modern IAF's theatre, in its UTM 36N frame (iaf-2026/docs/terrain.md §2), by the same code with the frame as a
//! parameter (`scenery::Frame::Utm`, `roads::make`):
//! - `converted/terrain/israel/roads/`: the road layer (`main.bin`, `L3/r_<i>_<j>.bin`, the manifest with "frame");
//! - `converted/terrain/israel/scenery/`: one cell per level-1 node of the theatre with a building or tree
//!   (`L1/s_<i>_<j>.bin`), the city lights' stand-ins (`lights/L1`), `manifest.json`, `theatre.json` (the cells under
//!   "israel": drawn whatever the imagery).
//!
//! The sources are the original's downloads, shared in `assets/source/scenery` and `assets/source/roads` (only what
//! is missing is downloaded). Nothing stands on water or a runway (the sim's `terraintype.dat`, `iaf-sim airbases`)
//! or inside an airbase's OpenStreetMap outline; no tree and no Microsoft footprint on OpenStreetMap's roads, railways,
//! runways, taxiways and aprons (`scenery::build_cell`). Over the Survey of Israel's 2 m nodes the trees come from the
//! 10 m canopy, elsewhere from the 20 m one, as the original's rest of the theatre (docs/scenery.md §1.7).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_avionics::scenery::{Cell, SOURCE_OSM};
use iaf_formats::terrain_types::TerrainTypes;
use image::RgbImage;
use serde_json::json;
use sha2::{Digest, Sha256};

use crate::progress::{Progress, check, par_map};
use crate::scenery::{self, Canopy, Env, Kinds, NodeIn, Sources};
use crate::sim_terrain::Meta;
use crate::thirdparty::{self, Download};
use crate::{log, roads, sim_bases, sim_coast};

/// The version of these rules: part of `made_from`.
pub const VERSION: u32 = 4;
/// The theatre, and the scenery's and roads' folders, under `assets/`.
pub const THEATRE: &str = "converted/terrain/israel";
pub const SCENERY_DIR: &str = "converted/terrain/israel/scenery";
pub const ROADS_DIR: &str = "converted/terrain/israel/roads";
/// The colour levels a roof takes its colour from, finest first: the 2 m Survey, the 8 m and 32 m Sentinel-2 nodes.
const COLOUR_LEVELS: [u32; 3] = [1, 3, 5];

/// The colour node (level, i, j) a point (terrain units) takes its roof colour from: the finest the theatre has.
fn colour_node(th: &Meta, t: [f64; 2]) -> Option<(u32, u32, u32)> {
    COLOUR_LEVELS.iter().find_map(|&l| {
        let span = th.frame.span(l);
        let k = ((t[0] / span).floor().max(0.0) as u32, (t[1] / span).floor().max(0.0) as u32);
        th.nodes.get(&l).is_some_and(|n| n.contains(&k)).then_some((l, k.0, k.1))
    })
}

/// The box [lon0, lat0, lon1, lat1] of a Microsoft quadkey tile (its name's last part) or an ETH canopy tile
/// (`eth-N30E033`: 3° from its south-west corner); None for any other file (always used).
fn tile_geo(file: &str) -> Option<[f64; 4]> {
    if let Some(n) = file.strip_prefix("eth-").and_then(|n| n.strip_suffix(".tif")) {
        let (lat, lon) = (n[1..3].parse::<f64>().ok()?, n[4..7].parse::<f64>().ok()?);
        return Some([lon, lat, lon + 3.0, lat + 3.0]);
    }
    let qk = file.strip_prefix("ms-")?.strip_suffix(".csv.gz")?.rsplit('-').next()?;
    let (mut x, mut y) = (0u64, 0u64);
    for c in qk.chars() {
        let d = c.to_digit(4)? as u64;
        (x, y) = (x * 2 + (d & 1), y * 2 + (d >> 1));
    }
    let n = (1u64 << qk.len()) as f64;
    let lon = |x: f64| x / n * 360.0 - 180.0;
    let lat = |y: f64| (std::f64::consts::PI * (1.0 - 2.0 * y / n)).sinh().atan().to_degrees();
    Some([lon(x as f64), lat(y as f64 + 1.0), lon(x as f64 + 1.0), lat(y as f64)])
}

/// The scenery's downloads (the original's `SCENERY` and `SCENERY_THEATRE`) whose tile meets the box `geo`.
pub fn downloads(geo: [f64; 4]) -> Vec<Download> {
    let k = Kinds::BOTH;
    k.downloads()
        .into_iter()
        .chain(k.theatre_downloads())
        .filter(|d| tile_geo(d.file).is_none_or(|b| b[0] < geo[2] && geo[0] < b[2] && b[1] < geo[3] && geo[1] < b[3]))
        .collect()
}

/// The exclusion zones: true where scenery may stand (engine metres): land in `terraintype.dat` (not the sea, a lake
/// or a runway), outside the inland water's own polygons (the grid's 64 m cells reach past a shore) and outside every
/// airbase outline.
pub fn open_at(tt: &TerrainTypes, water: &sim_bases::WaterIndex, outlines: &[Vec<[f64; 2]>], p: [f64; 2]) -> bool {
    let m = tt.at(p[0], p[1]);
    TerrainTypes::is_land(m) && m & 0x10 == 0 && !water.contains(p) && !outlines.iter().any(|o| scenery::contains(o, p))
}

/// How near an inland water body's box (m) a tree has the photo's water test (`photo_water`).
const WATER_NEAR_M: f64 = 1000.0;

/// A photo pixel that shows water: green over red by 20 or more (of 255) and blue at least red. The Dead Sea's pans
/// and the reservoirs are blue-green; vegetation is green over red with blue under it (inferred from the theatre's
/// tiles: the pans 176, 215, 186 and 165, 189, 165; an orchard about 90, 110, 70).
fn photo_water(c: [u8; 3]) -> bool {
    let [r, g, b] = c.map(i32::from);
    b >= r && g - r >= 20
}

/// The roofs' colour images (the theatre's 2 m, 8 m and 32 m colour nodes, L1 / L3 / L5): each file's name, size and
/// modification time, one line each. A terrain rebuild that rewrites a node changes its time even when `meta.json`
/// stays the same (a redo, or new terrain code with the same inputs), so the cells are made again.
fn roof_images(theatre: &Path) -> String {
    let mut lines = Vec::new();
    for l in ["L1", "L3", "L5"] {
        for e in std::fs::read_dir(theatre.join(l)).into_iter().flatten().flatten() {
            let n = e.file_name().to_string_lossy().to_string();
            if !n.starts_with("c_") {
                continue;
            }
            let m = e.metadata().ok();
            let t =
                m.as_ref().and_then(|m| m.modified().ok()).and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok());
            lines.push(format!("{l}/{n} {} {}", m.map_or(0, |m| m.len()), t.map_or(0, |t| t.as_nanos())));
        }
    }
    lines.sort();
    lines.join("\n")
}

/// What `scenery` made.
#[derive(Debug, Default)]
pub struct Summary {
    pub cells: usize,
    pub buildings: usize,
    pub osm: usize,
    pub trees: usize,
    pub light_cells: usize,
    pub lights: usize,
    pub bytes: u64,
    pub roads: Option<roads::Summary>,
    pub up_to_date: bool,
}

/// `iaf-sim scenery`: downloads what the shared cache lacks, then the road layer and the cells (module doc). Up to
/// date when the manifests say they were made from the same inputs. Needs the theatre (`iaf-sim terrain`), its
/// `terraintype.dat` (`iaf-sim airbases`) and GDAL.
pub fn scenery(data: &Path, assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Summary> {
    let started = std::time::Instant::now();
    let th = Meta::load(&assets.join(THEATRE))?;
    if th.crs != "EPSG:32636" {
        bail!("{THEATRE}: not Modern IAF's UTM 36N theatre");
    }
    let survey = th.nodes.get(&1).cloned().unwrap_or_default();
    let types = std::fs::read(assets.join("converted/own/terraintype.dat"))
        .context("no terraintype.dat of the sim (iaf-sim airbases)")?;
    let tt = TerrainTypes::parse(&types).map_err(|e| anyhow::anyhow!("terraintype.dat: {e:?}"))?;
    let bases = sim_bases::load(&data.join("airbases"))?;
    let geo = sim_bases::theatre_geo(th.rect);

    // The sources the theatre needs: the scenery's files and the countries' road extracts whose box meets it.
    let (src, roads_src) = (assets.join("source/scenery"), assets.join("source/roads"));
    let list = downloads(geo);
    let osm = sim_coast::osm_extract();
    let road_list = sim_coast::road_downloads(geo);
    let outlines: Vec<Vec<[f64; 2]>> = bases.iter().map(|b| b.boundary.clone()).collect();
    let water_bytes = std::fs::read(assets.join(THEATRE).join(sim_bases::WATER_FILE)).unwrap_or_default();
    let water = sim_bases::WaterIndex::load(&assets.join(THEATRE).join(sim_bases::WATER_FILE))?;
    let open = |p: [f64; 2]| open_at(&tt, &water, &outlines, p);
    // The stamps, each of the files its layer reads (a missing file counts as missing: the next run tries it again).
    let frame_inputs = |h: &mut Sha256| {
        h.update(&th.bytes);
        h.update(&types);
        h.update(&water_bytes);
        for b in &bases {
            h.update(format!("{} {:?}\n", b.icao, b.boundary).as_bytes());
        }
    };
    let stamp = |what: &str, files: &[(Download, &Path)], all: bool| -> String {
        let mut h = Sha256::new();
        h.update(format!("sim {what} {VERSION} {}\n", scenery::release(Kinds::BOTH)).as_bytes());
        for (d, dir) in files {
            let here = all || thirdparty::file_done(dir, d);
            h.update(format!("{} {}\n", d.file, if here { d.sha256 } else { "missing" }).as_bytes());
        }
        frame_inputs(&mut h);
        if what == "scenery" {
            h.update(roof_images(&assets.join(THEATRE)).as_bytes());
        }
        h.finalize().iter().map(|b| format!("{b:02x}")).collect()
    };
    let road_files: Vec<(Download, &Path)> =
        std::iter::once((osm, src.as_path())).chain(road_list.iter().map(|d| (*d, roads_src.as_path()))).collect();
    let scenery_files: Vec<(Download, &Path)> =
        list.iter().map(|d| (*d, src.as_path())).chain(road_files.iter().skip(1).copied()).collect();
    let (roads_out, out) = (assets.join(ROADS_DIR), assets.join(SCENERY_DIR));
    let mut s = Summary::default();
    if roads::up_to_date(&roads_out, &stamp("roads", &road_files, true))
        && roads::up_to_date(&out, &stamp("scenery", &scenery_files, true))
    {
        s.up_to_date = true;
        return Ok(s);
    }

    // What the shared cache lacks: the Israel and Palestine extract and the Survey layer's files are required, the
    // rest optional (a file that fails leaves its area without buildings, trees or roads).
    let required: Vec<Download> =
        list.iter().filter(|d| thirdparty::SCENERY.iter().any(|s| s.file == d.file)).copied().collect();
    if required.iter().any(|d| !thirdparty::file_done(&src, d)) {
        thirdparty::fetch_files(&required, &src, pr, cancel)?;
    }
    for (d, dir) in scenery_files.iter().filter(|(d, dir)| !thirdparty::file_done(dir, d)) {
        if let Err(e) = thirdparty::fetch_files(std::slice::from_ref(d), dir, pr, cancel) {
            check(cancel)?;
            log!(pr, "scenery: {} not downloaded, its area is left out: {e:#}", d.file);
        }
    }
    let files: Vec<PathBuf> =
        list.iter().filter(|d| thirdparty::file_done(&src, d)).map(|d| src.join(d.file)).collect();
    let pbfs: Vec<(&Download, PathBuf)> = road_files
        .iter()
        .filter(|(d, dir)| thirdparty::file_done(dir, d))
        .map(|(d, dir)| (d, dir.join(d.file)))
        .collect();

    let made = stamp("roads", &road_files, false);
    if !roads::up_to_date(&roads_out, &made) {
        let t = roads::Target {
            out: roads_out,
            frame: th.frame,
            box_geo: geo,
            to_engine: &sim_bases::utm36n,
            open: &open,
            made,
        };
        s.roads = Some(roads::make(&t, &pbfs, pr, cancel)?);
    }
    let made = stamp("scenery", &scenery_files, false);
    if roads::up_to_date(&out, &made) {
        return Ok(s);
    }
    let _ = std::fs::remove_file(out.join("manifest.json"));
    for d in ["L1", "lights/L1"] {
        if out.join(d).is_dir() {
            std::fs::remove_dir_all(out.join(d))?;
        }
        std::fs::create_dir_all(out.join(d))?;
    }
    let work = out.join(".work");
    std::fs::create_dir_all(&work)?;

    // Every level-1 node of the theatre.
    let n = [th.rect[2] - th.rect[0], th.rect[3] - th.rect[1]]
        .map(|v| (v / (th.frame.span(1) * th.frame.m_per_unit)).ceil() as u32);
    let keys: Vec<(u32, u32)> = (0..n[0]).flat_map(|i| (0..n[1]).map(move |j| (i, j))).collect();
    log!(pr, "scenery: {} nodes ({} over the Survey 2 m), {} files", keys.len(), survey.len(), files.len());
    let mut all_files = files.clone();
    all_files.extend(pbfs.iter().skip(1).map(|(_, p)| p.clone()));
    let Sources { warp, nodes, node_geos, heights, chm } =
        scenery::sources(th.frame, &keys, Kinds::BOTH, &all_files, &work, pr, cancel)?;
    let geos: HashMap<(u32, u32), [f64; 4]> = keys.iter().copied().zip(node_geos).collect();
    let built = |g: [f64; 2]| heights.at(g);
    let w = |lon: f64, lat: f64| warp.at(lon, lat);

    let mut blocks: std::collections::BTreeMap<(u32, u32), Vec<&NodeIn>> = Default::default();
    for nd in nodes.values() {
        blocks.entry((nd.key.0 / scenery::THEATRE_BLOCK, nd.key.1 / scenery::THEATRE_BLOCK)).or_default().push(nd);
    }
    let blocks: Vec<Vec<&NodeIn>> = blocks.into_values().collect();
    let done = std::sync::atomic::AtomicUsize::new(0);
    let colour_dir = assets.join(THEATRE);
    let results = par_map(&blocks, cancel, |block| {
        check(cancel)?;
        // The canopy over the block once: 10 m where it holds a Survey node, else 20 m.
        let fine = block.iter().any(|nd| survey.contains(&nd.key));
        let canopy = match &chm {
            Some(chm) => {
                let b = block.iter().map(|nd| geos[&nd.key]).fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, g| {
                    [b[0].min(g[0]), b[1].min(g[1]), b[2].max(g[2]), b[3].max(g[3])]
                });
                let step = if fine { scenery::CANOPY_STEP } else { scenery::THEATRE_CANOPY_STEP };
                let mut c = Canopy::grid(b, step);
                let g = [c.lon0, c.lat1 - c.h as f64 * c.step, c.lon0 + c.w as f64 * c.step, c.lat1];
                let tmp = work.join(format!("chm_{}_{}.bin", block[0].key.0, block[0].key.1));
                c.v = scenery::gdal_warp(std::slice::from_ref(chm), g, c.w, c.h, "max", &tmp)?;
                Some(c)
            }
            None => None,
        };
        // The colour nodes the roofs read: a 2 m node is a node's own (dropped after it), the 8 m and 32 m ones are
        // shared by the block (16 and 1 of them at most): about 60 MB a worker.
        let mut images: HashMap<(u32, u32, u32), Option<Arc<RgbImage>>> = HashMap::new();
        let mut v = Vec::new();
        for nd in block {
            images.retain(|k, _| k.0 > 1);
            let mut node = (*nd).clone();
            node.canopy = canopy
                .as_ref()
                .map(|c| c.part(geos[&nd.key]))
                .filter(|c| c.v.iter().any(|&v| v >= scenery::ORCHARD_CANOPY_MIN_M));
            if node.osm.is_empty() && node.ms.is_empty() && node.trees.is_empty() && node.canopy.is_none() {
                continue;
            }
            // The roofs' colour: the theatre's own colour node under the footprint (both looks: the sim has one).
            for f in node.osm.iter().chain(&node.ms) {
                let c = scenery::centroid(&f.pts);
                if let Some(k) = colour_node(&th, th.frame.units(c[0], c[1])) {
                    images.entry(k).or_insert_with(|| {
                        let p = colour_dir.join(format!("L{}/c_{}_{}.jpg", k.0, k.1, k.2));
                        image::open(p).ok().map(|m| Arc::new(m.to_rgb8()))
                    });
                }
            }
            let roof = |pts: &[[f64; 2]]| {
                let c = scenery::centroid(pts);
                let Some(k) = colour_node(&th, th.frame.units(c[0], c[1])) else { return ([0; 3], [0; 3]) };
                let Some(Some(img)) = images.get(&k) else { return ([0; 3], [0; 3]) };
                let (px, span) = (f64::from(1u32 << k.0), th.frame.span(k.0));
                let o = [k.1 as f64 * span, k.2 as f64 * span];
                let q: Vec<[f64; 2]> = pts
                    .iter()
                    .map(|&p| {
                        let t = th.frame.units(p[0], p[1]);
                        [(t[0] - o[0]) / px, (t[1] - o[1]) / px]
                    })
                    .collect();
                let m = scenery::median_inside(img, &q);
                (m, m)
            };
            let env = Env { open: &open, clears: &[], built_height: &built, roof: &roof, warp: &w };
            let mut cell = scenery::build_cell(&node, &env);
            // Near the inland water, no tree on the photo's water where OpenStreetMap's outline stops short of it (the
            // canopy map reads 30 m "trees" over the Dead Sea's pans; scenery.md §4).
            cell.trees.retain(|t| {
                let p = [f64::from(t.x), f64::from(t.y)];
                if !water.near(p, WATER_NEAR_M) {
                    return true;
                }
                let tp = th.frame.units(p[0], p[1]);
                let Some(k) = colour_node(&th, tp) else { return true };
                let img = images.entry(k).or_insert_with(|| {
                    let p = colour_dir.join(format!("L{}/c_{}_{}.jpg", k.0, k.1, k.2));
                    image::open(p).ok().map(|m| Arc::new(m.to_rgb8()))
                });
                let Some(img) = img else { return true };
                let (px, span) = (f64::from(1u32 << k.0), th.frame.span(k.0));
                let (x, y) = ((tp[0] - k.1 as f64 * span) / px, (tp[1] - k.2 as f64 * span) / px);
                let c = img.get_pixel((x as u32).min(img.width() - 1), (y as u32).min(img.height() - 1)).0;
                !photo_water(c)
            });
            // The city lights' stand-ins where a town's footprints are sparse (docs/rendering.md §5.1).
            let lights =
                Cell { buildings: scenery::fill_lights(&node, &heights, geos[&nd.key], &w, &open), trees: vec![] };
            let (i, j) = nd.key;
            let mut bytes = 0;
            let (nb, nt, nl) = (cell.buildings.len(), cell.trees.len(), lights.buildings.len());
            if nb + nt > 0 {
                let data = cell.encode();
                bytes += data.len() as u64;
                std::fs::write(out.join(format!("L1/s_{i}_{j}.bin")), data)?;
            }
            if nl > 0 {
                let data = lights.encode();
                bytes += data.len() as u64;
                std::fs::write(out.join(format!("lights/L1/s_{i}_{j}.bin")), data)?;
            }
            let osm = cell.buildings.iter().filter(|b| b.source == SOURCE_OSM).count();
            v.push((nd.key, nb, osm, nt, nl, bytes));
        }
        let k = done.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
        pr.fraction(0.35 + 0.65 * k as f32 / blocks.len().max(1) as f32);
        Ok(v)
    })?;
    let mut cells = Vec::new();
    for (k, nb, osm, nt, nl, bytes) in results.into_iter().flatten() {
        if nb + nt > 0 {
            s.cells += 1;
            cells.push([k.0, k.1]);
        }
        s.light_cells += (nl > 0) as usize;
        (s.buildings, s.osm, s.trees, s.lights, s.bytes) =
            (s.buildings + nb, s.osm + osm, s.trees + nt, s.lights + nl, s.bytes + bytes);
    }
    let attribution = json!([
        format!(
            "© OpenStreetMap contributors (openstreetmap.org/copyright), Geofabrik extracts of 2026-01-01 ({})",
            pbfs.iter().map(|(d, _)| roads::country(d.file)).collect::<Vec<_>>().join(", ")
        ),
        "Microsoft Global ML Building Footprints",
        "GHS-BUILT-H R2023A, European Commission, Joint Research Centre (JRC)",
        "Global Canopy Height 2020, Lang et al., ETH Zürich (EcoVision Lab)",
    ]);
    // The game lists the cells by theatre.json's "israel" (drawn whatever the imagery, shared/terrain/scenery.gd).
    std::fs::write(out.join("theatre.json"), serde_json::to_string(&json!({ "israel": cells }))? + "\n")?;
    let manifest = json!({
        "name": "scenery",
        "release": scenery::release(Kinds::BOTH),
        "generator": scenery::GENERATOR,
        "kinds": "both",
        "made_from": made,
        "frame": "EPSG:32636",
        "attribution": attribution,
        "licence": "OpenStreetMap: ODbL 1.0; Microsoft footprints: CDLA-Permissive-2.0; GHSL: free re-use with credit (CC BY 4.0); canopy height: CC BY 4.0",
        "cells": s.cells,
        "buildings": s.buildings,
        "trees": s.trees,
        "light_cells": s.light_cells,
        "light_buildings": s.lights,
    });
    std::fs::write(out.join("manifest.json"), serde_json::to_string(&manifest)? + "\n")?;
    // The countries' cut extracts are not kept (as the original's rest of the theatre, docs/scenery.md §1.7).
    let _ = std::fs::remove_dir_all(&work);
    log!(
        pr,
        "scenery: {} cells, {} buildings ({} OpenStreetMap), {} trees; city lights' stand-ins: {} in {} cells; {:.1} MB in {}",
        s.cells,
        s.buildings,
        s.osm,
        s.trees,
        s.lights,
        s.light_cells,
        s.bytes as f64 / 1e6,
        crate::progress::duration(started.elapsed())
    );
    Ok(s)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scenery::{Footprint, Warp};
    use iaf_avionics::scenery::Roof;

    /// A building lands where its lat / lon says in UTM 36N (gdaltransform's numbers for Ramon's reference point,
    /// sim_bases::utm_matches_gdal), within 5 m, through the warp, the gathering into the node and the cell's f32
    /// points; the node is the one holding it.
    #[test]
    fn a_building_lands_at_its_lat_lon() {
        let (lon, lat, e, n): (f64, f64, f64, f64) = (34.666, 30.776, 659_427.796_112_835, 3_405_963.754_670_05);
        let frame = iaf_avionics::frame::Frame {
            x_shift: 507_904.0,
            y_shift: 3_766_272.0,
            m_per_unit: 1.0,
            node_pixels: 1024.0,
        };
        let warp = Warp::new(&sim_bases::utm36n, [34.6, 30.7, 34.7, 30.8], 0.005);
        // A 20 m square house around the point, in lon / lat.
        let (dl, dp) = (10.0 / (111_320.0 * lat.to_radians().cos()), 10.0 / 110_850.0);
        let ring = [[lon - dl, lat - dp], [lon + dl, lat - dp], [lon + dl, lat + dp], [lon - dl, lat + dp]];
        let pts: Vec<[f64; 2]> = ring.iter().map(|p| warp.at(p[0], p[1])).collect();
        let key = scenery::node_of(frame, scenery::centroid(&pts));
        let r = scenery::rect_in(frame, key.0, key.1);
        assert!(r[0] <= e && e < r[2] && r[1] <= n && n < r[3], "{key:?} {r:?}");
        let f = Footprint {
            pts,
            geo: [lon, lat],
            height: Some(6.0),
            levels: 2,
            roof: Roof::Flat,
            wall: 0,
            source: SOURCE_OSM,
        };
        let node = NodeIn { key, rect: r, osm: vec![f], ..NodeIn::default() };
        let w = |lon: f64, lat: f64| warp.at(lon, lat);
        let roof = |_: &[[f64; 2]]| ([0; 3], [0; 3]);
        let env = Env { open: &|_| true, clears: &[], built_height: &|_| None, roof: &roof, warp: &w };
        let cell = scenery::build_cell(&node, &env);
        assert_eq!(cell.buildings.len(), 1);
        let c = cell.buildings[0].centroid();
        let d = (f64::from(c[0]) - e).hypot(f64::from(c[1]) - n);
        assert!(d < 5.0, "{d} m off");
        assert!(d < 0.5, "in fact within the f32 points' quarter metre: {d}");
    }

    /// The exclusion zones: the sea, a lake and the runways (terraintype.dat), inside an airbase's outline; land
    /// beside them is open.
    #[test]
    fn exclusion_zones() {
        let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../iaf-2026/data/airbases");
        let bases = sim_bases::load(&data).unwrap();
        let rws: Vec<&sim_bases::Runway> = bases.iter().flat_map(|b| b.runways.iter()).collect();
        // Ramon's box (64 km): the west quarter sea, a 6.4 km lake in the north-east.
        let r = [600_000.0, 3_380_000.0, 664_000.0, 3_444_000.0];
        let cells: Vec<u8> = (0..1000 * 1000)
            .map(|k| match (k % 1000, k / 1000) {
                (i, _) if i < 250 => 0x4,
                (800..900, 100..200) => 0x2,
                _ => 0,
            })
            .collect();
        let tt = TerrainTypes::parse(&sim_bases::terraintype(
            r,
            &sim_bases::Surface {
                water: &sim_bases::WaterGrid::new(1000, 1000, &cells),
                coast: &Default::default(),
                paved: &[],
            },
            &rws,
        ))
        .unwrap();
        let outlines: Vec<Vec<[f64; 2]>> = bases.iter().map(|b| b.boundary.clone()).collect();
        // A pond the 64 m grid misses: its own polygon keeps scenery off.
        let pond = sim_bases::WaterIndex::new(vec![vec![vec![
            [630_000.0, 3_400_000.0],
            [630_030.0, 3_400_000.0],
            [630_030.0, 3_400_030.0],
            [630_000.0, 3_400_030.0],
        ]]]);
        assert!(!open_at(&tt, &pond, &outlines, [630_015.0, 3_400_015.0]), "a pond the grid misses");
        assert!(open_at(&tt, &pond, &outlines, [630_045.0, 3_400_015.0]), "beside the pond");
        let water = sim_bases::WaterIndex::default();
        let ramon = &bases[0];
        let rw = &ramon.runways[0];
        assert!(!open_at(&tt, &water, &outlines, rw.at(0, rw.length() / 2.0)), "a runway");
        assert!(!open_at(&tt, &water, &outlines, ramon.parking[0].at), "inside the base's outline");
        assert!(!open_at(&tt, &water, &outlines, [605_000.0, 3_400_000.0]), "the sea");
        assert!(!open_at(&tt, &water, &outlines, [654_000.0, 3_434_000.0]), "the lake");
        assert!(open_at(&tt, &water, &outlines, [640_000.0, 3_400_000.0]), "the desert west of the base");
    }

    /// The tiles' boxes: a zoom-9 quadkey and an ETH tile; the downloads over the sim's box leave out what lies
    /// outside it (Cyprus, the Nile delta).
    #[test]
    fn tiles_and_downloads() {
        let b = tile_geo("ms-Israel-122103300.csv.gz").unwrap();
        let q = scenery::quadkey((b[0] + b[2]) / 2.0, (b[1] + b[3]) / 2.0, 9);
        assert_eq!(q, "122103300");
        assert_eq!(tile_geo("eth-N30E033.tif"), Some([33.0, 30.0, 36.0, 33.0]));
        assert_eq!(tile_geo("israel-and-palestine-260101.osm.pbf"), None);
        let geo = sim_bases::theatre_geo(crate::sim_terrain::BOX);
        let d = downloads(geo);
        assert!(d.iter().any(|d| d.file.starts_with("israel-and-palestine")));
        assert!(!d.iter().any(|d| d.file.starts_with("ms-Cyprus")), "Cyprus lies north of the box");
        assert!(d.iter().any(|d| d.file.starts_with("ms-Jordan")));
        assert!(!d.iter().any(|d| d.file == "eth-N30E027.tif"));
        assert!(
            photo_water([176, 215, 186]) && photo_water([130, 195, 153]) && photo_water([165, 189, 165]),
            "the pans"
        );
        assert!(!photo_water([90, 110, 70]) && !photo_water([237, 215, 166]), "an orchard, the shore's sand");
        let r: Vec<&str> = sim_coast::road_downloads(geo).iter().map(|d| d.file.split('-').next().unwrap()).collect();
        assert_eq!(r, ["lebanon", "syria", "jordan", "egypt"], "Cyprus lies north of the box");
    }
}
