//! The road layer (docs/scenery.md §6): OpenStreetMap's roads and railways of the whole theatre from pinned Geofabrik
//! extracts (Israel and Palestine: the scenery's, `thirdparty::SCENERY`; the other countries: `thirdparty::ROADS`),
//! cut to the theatre's box, warped into the engine frame with the georeference as the scenery is, into one file
//! `assets/converted/roads/roads.bin` (format: `iaf_avionics::roads`). Ways that share an OpenStreetMap node share
//! the vertex, so the junctions make a road graph, across borders too. A way piece off the game's open land (over an
//! airbase, World scale Real's base sites, the 1998 sea) is kept with `FLAG_OFF_GROUND`.

use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_avionics::roads::*;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

use crate::georef::Georef;
use crate::imagery::{Rules, Theatre};
use crate::progress::{Progress, check};
use crate::scenery::{Warp, base_moves, geojsonl, other_tags, run, tag_number};
use crate::{airbases, log, thirdparty};

/// The converter's version: part of `made_from`, so a change to the rules below makes the file again.
pub const ROADS_VERSION: u32 = 1;

/// The OSM `highway` values taken, and railway=rail.
const HIGHWAYS: [&str; 10] = [
    "motorway",
    "trunk",
    "primary",
    "secondary",
    "tertiary",
    "unclassified",
    "residential",
    "living_street",
    "service",
    "track",
];

/// A lane's width (m) for a way with `lanes` and no `width`.
const LANE_M: f32 = 3.5;

/// One OpenStreetMap way, its attributes read (`parse`).
#[derive(Clone, Debug, PartialEq)]
pub struct RawWay {
    pub osm_id: u64,
    pub class: u8,
    /// `FLAG_*` but `FLAG_OFF_GROUND`.
    pub flags: u8,
    pub layer: i8,
    pub width: f32,
    /// (lon, lat) parts, in the direction of travel for a oneway.
    pub parts: Vec<Vec<[f64; 2]>>,
}

/// A class's default width (m) of one mapped way (a dual carriageway is two ways): inferred from the usual Israeli
/// cross-sections (3.5 m lanes plus shoulders); a link 5 m.
pub fn default_width(class: u8, link: bool) -> f32 {
    if link {
        return 5.0;
    }
    [11.0, 9.0, 8.0, 7.0, 6.0, 5.0, 3.5, 3.0, 3.0][class as usize]
}

/// A way's class, flags, layer and width from its `highway` / `railway` and other tags; None for anything else.
pub fn attributes(highway: &str, railway: &str, tags: &BTreeMap<String, String>) -> Option<(u8, u8, i8, f32)> {
    let base = highway.strip_suffix("_link");
    let link = base.is_some() && highway != "track_link";
    let class = match base.unwrap_or(highway) {
        "motorway" => CLASS_MOTORWAY,
        "trunk" => CLASS_TRUNK,
        "primary" => CLASS_PRIMARY,
        "secondary" => CLASS_SECONDARY,
        "tertiary" => CLASS_TERTIARY,
        "unclassified" | "residential" | "living_street" if !link => CLASS_MINOR,
        "service" if !link => CLASS_SERVICE,
        "track" if !link => CLASS_TRACK,
        "" if railway == "rail" => CLASS_RAIL,
        _ => return None,
    };
    let t = |k: &str| tags.get(k).map(String::as_str);
    let yes = |k: &str| t(k).is_some_and(|v| v != "no");
    let mut flags = 0;
    if link {
        flags |= FLAG_LINK;
    }
    if yes("bridge") {
        flags |= FLAG_BRIDGE;
    }
    if yes("tunnel") {
        flags |= FLAG_TUNNEL;
    }
    let unpaved = match t("surface") {
        Some(
            "unpaved" | "gravel" | "fine_gravel" | "dirt" | "earth" | "ground" | "sand" | "compacted" | "grass" | "mud"
            | "pebblestone" | "rock" | "salt" | "woodchips" | "grass_paver",
        ) => true,
        Some(_) => false,
        None => class == CLASS_TRACK && t("tracktype") != Some("grade1"),
    };
    if unpaved && class != CLASS_RAIL {
        flags |= FLAG_UNPAVED;
    }
    // OSM: motorways and roundabouts are oneway unless tagged otherwise.
    let implied = class == CLASS_MOTORWAY || matches!(t("junction"), Some("roundabout" | "circular"));
    match t("oneway") {
        Some("yes" | "true" | "1" | "-1" | "reverse") => flags |= FLAG_ONEWAY,
        Some(_) => {}
        None if implied && class != CLASS_RAIL => flags |= FLAG_ONEWAY,
        None => {}
    }
    match t("lit") {
        Some("no" | "disused") => flags |= FLAG_UNLIT,
        Some(_) => flags |= FLAG_LIT,
        None => {}
    }
    let layer = t("layer").and_then(|v| v.trim().parse::<i32>().ok()).unwrap_or(0).clamp(-5, 5) as i8;
    let width = tag_number(tags.get("width"))
        .filter(|w| *w <= 60.0)
        .or_else(|| tag_number(tags.get("lanes")).filter(|l| *l <= 12.0).map(|l| l.round().max(1.0) * LANE_M))
        .unwrap_or(default_width(class, link));
    Some((class, flags, layer, width))
}

/// A GeoJSON feature of the lines layer (osm_id, highway, railway, other_tags) as a way; None when it is not a road
/// or railway taken.
pub fn parse(v: &Value) -> Option<RawWay> {
    let pr = &v["properties"];
    let s = |k: &str| pr[k].as_str().unwrap_or("");
    let tags = other_tags(s("other_tags"));
    let (class, flags, layer, width) = attributes(s("highway"), s("railway"), &tags)?;
    let line = |l: &Value| -> Vec<[f64; 2]> {
        l.as_array().into_iter().flatten().filter_map(|p| Some([p[0].as_f64()?, p[1].as_f64()?])).collect()
    };
    let g = &v["geometry"];
    let mut parts = match g["type"].as_str() {
        Some("LineString") => vec![line(&g["coordinates"])],
        Some("MultiLineString") => g["coordinates"].as_array()?.iter().map(line).collect(),
        _ => return None,
    };
    if matches!(tags.get("oneway").map(String::as_str), Some("-1" | "reverse")) {
        parts.iter_mut().for_each(|p| p.reverse());
    }
    Some(RawWay { osm_id: s("osm_id").parse().unwrap_or(0), class, flags, layer, width, parts })
}

/// The ways into the road file: each (lon, lat) is one vertex (a node shared by ways stays one), `warp` takes it to
/// engine metres; a way is cut into pieces where `open` (engine metres: on the game's open land) changes, tested at
/// each vertex and each segment's middle.
pub fn convert(
    ways: &[RawWay],
    warp: &dyn Fn(f64, f64) -> [f64; 2],
    open: &(dyn Fn([f64; 2]) -> bool + Sync),
) -> Roads {
    let mut ids: HashMap<(u64, u64), u32> = HashMap::new();
    let mut eng: Vec<[f64; 2]> = Vec::new();
    let mut out_ways = Vec::new();
    let mut index = Vec::new();
    for w in ways {
        for part in &w.parts {
            let mut idx: Vec<u32> = part
                .iter()
                .map(|p| {
                    *ids.entry((p[0].to_bits(), p[1].to_bits())).or_insert_with(|| {
                        eng.push(warp(p[0], p[1]));
                        eng.len() as u32 - 1
                    })
                })
                .collect();
            idx.dedup();
            if idx.len() < 2 {
                continue;
            }
            let seg_open: Vec<bool> = idx
                .windows(2)
                .map(|s| {
                    let (a, b) = (eng[s[0] as usize], eng[s[1] as usize]);
                    open(a) && open(b) && open([(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5])
                })
                .collect();
            let mut start = 0;
            for k in 1..=seg_open.len() {
                if k == seg_open.len() || seg_open[k] != seg_open[start] {
                    let piece = &idx[start..=k];
                    let off = if seg_open[start] { 0 } else { FLAG_OFF_GROUND };
                    out_ways.push(Way {
                        osm_id: w.osm_id,
                        first: 0,
                        count: piece.len() as u32,
                        class: w.class,
                        flags: w.flags | off,
                        layer: w.layer,
                        width: w.width,
                    });
                    index.extend_from_slice(piece);
                    start = k;
                }
            }
        }
    }
    let points = eng.iter().map(|p| [p[0] as f32, p[1] as f32]).collect();
    Roads::new(points, out_ways, index)
}

/// An extract's country for the credit line.
fn country(file: &str) -> &str {
    match file.split('-').next().unwrap_or("") {
        "israel" => "Israel and Palestine",
        "lebanon" => "Lebanon",
        "syria" => "Syria",
        "jordan" => "Jordan",
        "egypt" => "Egypt",
        "cyprus" => "Cyprus",
        _ => file,
    }
}

fn way_f32(r: &Roads, w: u32) -> Vec<[f32; 2]> {
    r.way_index(w).iter().map(|&i| r.points[i as usize]).collect()
}

/// The roads per block (`iaf_avionics::roads::block_of`): each way cut where it crosses a block's edge, at a point on
/// the edge both pieces hold.
pub fn split_blocks(r: &Roads) -> BTreeMap<(i32, i32), Roads> {
    let s = BLOCK_UNITS * crate::georef::UNITS_TO_METRES;
    let mut lines: BTreeMap<(i32, i32), Vec<Line>> = BTreeMap::new();
    for w in 0..r.ways.len() as u32 {
        let pts = way_f32(r, w);
        let mut cur: Vec<[f32; 2]> = vec![pts[0]];
        let mut cur_block = None;
        for seg in pts.windows(2) {
            let (a, b) = ([seg[0][0] as f64, seg[0][1] as f64], [seg[1][0] as f64, seg[1][1] as f64]);
            // The edges crossed: x = k·s − 166850 and y = 1043780 − k·s.
            let mut ts: Vec<f64> = Vec::new();
            for (axis, off, sign) in [(0, 166850.0, 1.0), (1, 1043780.0, -1.0)] {
                let (u0, u1) = ((sign * a[axis] + off) / s, (sign * b[axis] + off) / s);
                for k in (u0.min(u1).floor() as i64 + 1)..=(u0.max(u1).ceil() as i64 - 1) {
                    ts.push((k as f64 - u0) / (u1 - u0));
                }
            }
            ts.sort_by(f64::total_cmp);
            ts.push(1.0);
            let mut t0 = 0.0;
            for t in ts {
                let at = |t: f64| [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])];
                let q = if t >= 1.0 { seg[1] } else { at(t).map(|v| v as f32) };
                let m = at((t0 + t) * 0.5);
                let blk = block_of(m);
                if cur_block.is_some_and(|c| c != blk) {
                    let last = *cur.last().unwrap();
                    lines
                        .entry(cur_block.unwrap())
                        .or_default()
                        .push((r.ways[w as usize], std::mem::replace(&mut cur, vec![last])));
                }
                cur_block = Some(blk);
                cur.push(q);
                t0 = t;
            }
        }
        if let Some(c) = cur_block {
            lines.entry(c).or_default().push((r.ways[w as usize], cur));
        }
    }
    lines.into_iter().map(|(k, v)| (k, Roads::from_lines(v.iter().map(|(w, p)| (*w, p.as_slice()))))).collect()
}

/// What `build` made.
#[derive(Debug, Default)]
pub struct Summary {
    /// Ways per class (`CLASS_*`).
    pub ways: [usize; 9],
    pub points: usize,
    /// Block files written, the largest's size and main.bin's size; bytes: all files.
    pub blocks: usize,
    pub blocks_max: u64,
    pub main_bytes: u64,
    pub bytes: u64,
    pub up_to_date: bool,
}

/// The extracts to read, in order: Israel and Palestine (the scenery's, required), then each other country
/// downloaded (`thirdparty::ROADS`, optional).
fn inputs(assets: &Path) -> Result<Vec<(&'static thirdparty::Download, PathBuf)>> {
    let osm = thirdparty::SCENERY.iter().find(|d| d.file.starts_with("israel-and-palestine")).context("no OSM")?;
    let src = assets.join("source/scenery");
    if !thirdparty::file_done(&src, osm) {
        bail!("{} is not downloaded (setup step scenery-fetch)", osm.file);
    }
    let roads = assets.join("source/roads");
    let mut out = vec![(osm, src.join(osm.file))];
    out.extend(thirdparty::ROADS.iter().filter(|d| thirdparty::file_done(&roads, d)).map(|d| (d, roads.join(d.file))));
    Ok(out)
}

/// Downloads the other countries' extracts (`thirdparty::ROADS`) into `assets/source/roads`, one by one: a country
/// that fails is logged and left out (it has no roads). The count downloaded now.
pub fn fetch(assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<usize> {
    let dir = assets.join("source/roads");
    let mut n = 0;
    for d in thirdparty::ROADS {
        match thirdparty::fetch_files(std::slice::from_ref(d), &dir, pr, cancel) {
            Ok(k) => n += k,
            Err(e) => {
                check(cancel)?;
                log!(pr, "roads: {} not downloaded, its country has no roads: {e:#}", d.file);
            }
        }
    }
    Ok(n)
}

fn made_from(a: &Path, inputs: &[(&thirdparty::Download, PathBuf)]) -> String {
    let mut h = Sha256::new();
    for (d, _) in inputs {
        h.update(format!("{}\n", d.sha256).as_bytes());
    }
    h.update(format!("roads {ROADS_VERSION}\n").as_bytes());
    for s in ["missions.stamp", "terrain/airbases.json.stamp", "terrain/theatre.stamp"] {
        h.update(std::fs::read(a.join("converted").join(s)).unwrap_or_default());
    }
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// The theatre's box [lon0, lat0, lon1, lat1]: its rect's edges through the georeference.
fn theatre_geo(g: &Georef, rect: [u32; 4]) -> [f64; 4] {
    let mut b = [f64::MAX, f64::MAX, f64::MIN, f64::MIN];
    for k in 0..=16 {
        let f = k as f64 / 16.0;
        let lerp = |a: u32, c: u32| a as f64 + f * (c as f64 - a as f64);
        for [tx, ty] in [
            [lerp(rect[0], rect[2]), rect[1] as f64],
            [lerp(rect[0], rect[2]), rect[3] as f64],
            [rect[0] as f64, lerp(rect[1], rect[3])],
            [rect[2] as f64, lerp(rect[1], rect[3])],
        ] {
            let p = g.to_geo(tx, ty);
            b = [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])];
        }
    }
    b
}

/// The way's parts cut to the box: the points outside it dropped, a part split where it leaves.
pub fn clip(w: &mut RawWay, geo: [f64; 4]) {
    let inside = |p: &[f64; 2]| p[0] >= geo[0] && p[0] <= geo[2] && p[1] >= geo[1] && p[1] <= geo[3];
    w.parts = w
        .parts
        .iter()
        .flat_map(|part| part.split(|p| !inside(p)).filter(|s| s.len() >= 2).map(<[_]>::to_vec).collect::<Vec<_>>())
        .collect();
}

/// The road file (module doc) into `assets/converted/roads`: up to date when its manifest says it was made from the
/// same extracts and rules. Needs GDAL's ogr2ogr and the Israel and Palestine extract.
pub fn build(assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Summary> {
    let started = std::time::Instant::now();
    let inputs = inputs(assets)?;
    let out = assets.join("converted/roads");
    let manifest_p = out.join("manifest.json");
    let made = made_from(assets, &inputs);
    if let Ok(m) = std::fs::read(&manifest_p).map(|b| serde_json::from_slice::<Value>(&b).unwrap_or(Value::Null))
        && m["made_from"] == made.as_str()
    {
        return Ok(Summary { up_to_date: true, ..Summary::default() });
    }
    std::fs::create_dir_all(&out)?;
    let georef = Georef::load()?;
    let theatre = Theatre::load(&assets.join("converted/terrain/theatre"))?;
    let box_geo = theatre_geo(&georef, theatre.rect);
    let list = HIGHWAYS.iter().flat_map(|h| [format!("'{h}'"), format!("'{h}_link'")]).collect::<Vec<_>>().join(",");
    let lines = out.join("osm-lines.geojsonl");
    // A way in two extracts (they overlap at the borders) is kept once: the copy with the most points.
    let mut ways: Vec<RawWay> = Vec::new();
    let mut seen: HashMap<u64, usize> = HashMap::new();
    for (k, (d, file)) in inputs.iter().enumerate() {
        let t0 = std::time::Instant::now();
        let _ = std::fs::remove_file(&lines);
        let mut cmd = Command::new("ogr2ogr");
        cmd.env("CPL_TMPDIR", &out)
            .args(["-f", "GeoJSONSeq", "-where", &format!("highway IN ({list}) OR railway = 'rail'")])
            .args(["-select", "osm_id,highway,railway,other_tags", "-spat"])
            .args(box_geo.map(|v| v.to_string()))
            .arg(&lines)
            .arg(file)
            .arg("lines");
        run(cmd)?;
        check(cancel)?;
        let (mut n, mut pts) = (0, 0);
        for mut w in geojsonl(&lines)?.filter_map(|v| parse(&v)) {
            clip(&mut w, box_geo);
            let len: usize = w.parts.iter().map(Vec::len).sum();
            if len == 0 {
                continue;
            }
            match seen.get(&w.osm_id) {
                Some(&i) if ways[i].parts.iter().map(Vec::len).sum::<usize>() >= len => continue,
                Some(&i) => ways[i] = w,
                None => {
                    seen.insert(w.osm_id, ways.len());
                    ways.push(w);
                    n += 1;
                    pts += len;
                }
            }
        }
        std::fs::remove_file(&lines)?;
        log!(pr, "roads: {}: {n} new ways, {pts} points in {}", d.file, crate::progress::duration(t0.elapsed()));
        pr.fraction(0.6 * (k + 1) as f32 / inputs.len() as f32);
    }

    // The warp over the ways' box; the open land: off the airbases and World scale Real's sites, on land.
    let geo =
        ways.iter().flat_map(|w| w.parts.iter().flatten()).fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
            [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
        });
    if geo[0] > geo[2] {
        bail!("no road in the extracts");
    }
    let warp = Warp::new(&georef, [geo[0] - 0.01, geo[1] - 0.01, geo[2] + 0.01, geo[3] + 0.01], 0.005);
    let install = assets.join("install");
    let rules = Rules::load(&install, false, &theatre)?;
    let moves = base_moves(&install, &assets.join("converted/terrain"));
    let ring = iaf_flight::base_move::RING;
    let open = |p: [f64; 2]| {
        let t = airbases::units(p[0], p[1]);
        rules.ground_open(t[0], t[1]) && !moves.bases.iter().any(|b| b.in_old(p, 0.0) || b.to_game(p, ring).is_some())
    };
    check(cancel)?;
    let roads = convert(&ways, &|lon, lat| warp.at(lon, lat), &open);
    pr.fraction(0.8);
    let main = Roads::from_lines(
        (0..roads.ways.len() as u32)
            .filter(|&w| roads.ways[w as usize].class <= MAIN_CLASS)
            .map(|w| (roads.ways[w as usize], way_f32(&roads, w)))
            .collect::<Vec<_>>()
            .iter()
            .map(|(w, p)| (*w, p.as_slice())),
    );
    let main_data = main.encode();
    let _ = std::fs::remove_file(out.join("roads.bin"));
    std::fs::write(out.join("main.bin"), &main_data)?;
    let l3 = out.join("L3");
    if l3.is_dir() {
        std::fs::remove_dir_all(&l3)?;
    }
    std::fs::create_dir_all(&l3)?;
    let blocks = split_blocks(&roads);
    let mut s = Summary { points: roads.points.len(), bytes: main_data.len() as u64, ..Summary::default() };
    for ((i, j), b) in &blocks {
        let data = b.encode();
        s.bytes += data.len() as u64;
        s.blocks_max = s.blocks_max.max(data.len() as u64);
        std::fs::write(l3.join(format!("r_{i}_{j}.bin")), data)?;
    }
    s.blocks = blocks.len();
    s.main_bytes = main_data.len() as u64;
    for w in &roads.ways {
        s.ways[w.class as usize] += 1;
    }
    let by_class: serde_json::Map<String, Value> =
        CLASS_NAMES.iter().zip(s.ways).map(|(n, c)| (n.to_string(), json!(c))).collect();
    let manifest = json!({
        "name": "roads",
        "version": ROADS_VERSION,
        "made_from": made,
        "attribution": [format!(
            "© OpenStreetMap contributors (openstreetmap.org/copyright), roads: Geofabrik extracts of 2026-01-01 ({})",
            inputs.iter().map(|(d, _)| country(d.file)).collect::<Vec<_>>().join(", ")
        )],
        "extracts": inputs.iter().map(|(d, _)| d.file).collect::<Vec<_>>(),
        "licence": "ODbL 1.0",
        "points": s.points,
        "blocks": s.blocks,
        "ways": by_class,
    });
    std::fs::write(&manifest_p, serde_json::to_string_pretty(&manifest)? + "\n")?;
    log!(
        pr,
        "roads: {} ways ({}), {} points; main.bin {:.1} MB, {} blocks (largest {:.1} MB), {:.1} MB in all, in {}",
        roads.ways.len(),
        CLASS_NAMES.iter().zip(s.ways).map(|(n, c)| format!("{n} {c}")).collect::<Vec<_>>().join(", "),
        s.points,
        s.main_bytes as f64 / 1e6,
        s.blocks,
        s.blocks_max as f64 / 1e6,
        s.bytes as f64 / 1e6,
        crate::progress::duration(started.elapsed())
    );
    Ok(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feature(id: &str, highway: &str, railway: &str, tags: &str, coords: &[[f64; 2]]) -> Value {
        json!({"type": "Feature",
            "properties": {"osm_id": id, "highway": highway, "railway": railway, "other_tags": tags},
            "geometry": {"type": "LineString", "coordinates": coords}})
    }

    #[test]
    fn blocks_cut_at_their_edges() {
        let e = block_rect(100, 300);
        let (y, x0, x1) = ((e[1] + e[3]) * 0.5, e[0] + 100.0, e[2] + 2000.0);
        let way = Way { osm_id: 1, first: 0, count: 0, class: CLASS_PRIMARY, flags: 0, layer: 0, width: 8.0 };
        let r = Roads::from_lines([(way, &[[x0 as f32, y as f32], [x1 as f32, y as f32]][..])]);
        let b = split_blocks(&r);
        assert_eq!(b.keys().copied().collect::<Vec<_>>(), [(100, 300), (101, 300)]);
        let (w, east) = (&b[&(100, 300)], &b[&(101, 300)]);
        let edge = w.points[w.way_index(0)[1] as usize];
        assert_eq!(edge, east.points[east.way_index(0)[0] as usize], "both pieces hold the edge point");
        assert!((edge[0] as f64 - e[2]).abs() < 0.1);
        let m = Roads::merge(&[w, east]);
        assert_eq!(m.route([x0, y], [x1, y], CLASS_TRACK).unwrap().len(), 3);
    }

    #[test]
    fn attributes_from_tags() {
        let t = |s: &str| other_tags(s);
        let a = attributes("primary_link", "", &t(r#""lanes"=>"2","lit"=>"yes","bridge"=>"yes","layer"=>"1""#));
        assert_eq!(a, Some((CLASS_PRIMARY, FLAG_LINK | FLAG_BRIDGE | FLAG_LIT, 1, 7.0)));
        assert_eq!(attributes("motorway", "", &t("")), Some((CLASS_MOTORWAY, FLAG_ONEWAY, 0, 11.0)));
        assert_eq!(attributes("motorway", "", &t(r#""oneway"=>"no""#)).unwrap().1, 0);
        assert_eq!(attributes("track", "", &t("")), Some((CLASS_TRACK, FLAG_UNPAVED, 0, 3.0)));
        assert_eq!(attributes("track", "", &t(r#""surface"=>"asphalt""#)).unwrap().1, 0);
        assert_eq!(
            attributes("residential", "", &t(r#""width"=>"12 m","lit"=>"no","tunnel"=>"yes","layer"=>"-2""#)),
            Some((CLASS_MINOR, FLAG_TUNNEL | FLAG_UNLIT, -2, 12.0))
        );
        assert_eq!(attributes("", "rail", &t("")).unwrap().0, CLASS_RAIL);
        assert!(attributes("footway", "", &t("")).is_none());
        assert!(attributes("", "tram", &t("")).is_none());
    }

    #[test]
    fn junctions_share_a_vertex_and_pieces_split_off_ground() {
        let feats = [
            feature("1", "primary", "", "", &[[34.0, 31.0], [34.01, 31.0], [34.02, 31.0]]),
            feature("2", "secondary", "", r#""oneway"=>"-1""#, &[[34.01, 30.99], [34.01, 31.0], [34.01, 31.01]]),
            feature("3", "footway", "", "", &[[34.01, 31.0], [34.01, 31.02]]),
        ];
        let ways: Vec<RawWay> = feats.iter().filter_map(parse).collect();
        assert_eq!(ways.len(), 2, "the footway is dropped");
        let warp = |lon: f64, lat: f64| [lon * 1000.0, lat * 1000.0];
        // Off the ground north of y = 31 005 m.
        let r = convert(&ways, &warp, &|p| p[1] < 31_005.0);
        assert_eq!(r.points.len(), 5, "the shared node is one vertex");
        assert_eq!(r.ways.len(), 3, "the secondary is cut where it leaves the ground");
        assert_eq!(r.way_index(0), [0, 1, 2]);
        // The secondary was tagged oneway=-1: reversed, north to south; its first piece is off the ground.
        assert_eq!(r.way_index(1), [3, 1]);
        assert_eq!(r.way_index(2), [1, 4]);
        assert_eq!(r.ways[1].flags, FLAG_ONEWAY | FLAG_OFF_GROUND);
        assert_eq!(r.ways[2].flags, FLAG_ONEWAY);
        assert_eq!((r.ways[0].osm_id, r.ways[1].osm_id), (1, 2));
        // The reader: a route from the primary's west end onto the secondary's south end goes through the junction.
        let back = Roads::decode(&r.encode()).unwrap();
        let p = back.route([34_000.0, 31_000.0], [34_010.0, 30_990.0], CLASS_TRACK).unwrap();
        assert_eq!(p.len(), 3);
        assert_eq!(p[1], [34_010.0, 31_000.0]);
    }
}
