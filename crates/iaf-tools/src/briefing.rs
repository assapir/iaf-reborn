//! Modern IAF's mission briefing map (modern-iaf/docs/front-end.md §10): a training mission's area with its base, its
//! runways and its route, for the Pick a mission screen. `IafBriefing` hands it to `menu/briefing_map.gd`, which draws.
//!
//! Every place is in the sim's frame (UTM 36N, `sim_bases::utm36n`) and comes back in the map's own metres: x east and
//! y south from the map's north-west corner, so the drawing only scales.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use iaf_avionics::roads::{self, Roads};
use serde_json::{Map, Value, json};

use crate::loadout;
use crate::sim::place;
use crate::sim_bases::{self, Base, grid_heading, utm36n_geo};
use crate::sim_cockpit::{clip_to, from_map};
use crate::sim_scenery;

/// The map's shorter side at least (m; inferred: the base's surroundings with the next towns in view; zooming in
/// shows the base).
pub const MIN_SPAN_M: f64 = 50_000.0;
/// The area shows villages only with fewer towns and cities than this in it (inferred: a readable map).
pub const VILLAGES_UNDER: usize = 6;
/// Room around the base and the route (m; inferred).
pub const MARGIN_M: f64 = 6_000.0;

/// The briefing's map.
#[derive(Debug)]
pub struct Briefing {
    /// The base's English name ("Ramon").
    pub base: String,
    /// The runway end the mission takes off from ("25R") and its true heading (deg).
    pub runway: Option<(String, f64)>,
    /// True north as a grid bearing (deg, −180..180; the meridian convergence at the base, the map being grid north
    /// up: east of 33° E true north leans west of grid north).
    pub north: f64,
    /// The map's width and height (m).
    pub size: [f64; 2],
    /// The map's polygons in paint order: their colour and their fill as triangles (three points each).
    pub fills: Vec<([u8; 3], Vec<[f32; 2]>)>,
    /// The base's runways: the two ends, the width (m) and the ends' designators.
    pub runways: Vec<([[f64; 2]; 2], f64, [String; 2])>,
    /// The jet's start (its parking spot or the lineup point).
    pub start: [f64; 2],
    /// The taxi from the start to the lineup point (the base's departure route, `sim_bases::routes`); empty when the
    /// mission takes off from no runway or from another one than that route's.
    pub taxi: Vec<[f64; 2]>,
    /// The flight from the lineup point through the mission's waypoints; empty without a take-off.
    pub route: Vec<[f64; 2]>,
    /// The map's box in the sim's frame [x0, y0, x1, y1] (UTM 36N metres; for [`ground`]).
    pub extent: [f64; 4],
    /// The base's paved shapes: the taxiways (centreline, width), the stopways (centreline), the aprons and the
    /// shelters' pads (outlines), the parking spots.
    pub taxiways: Vec<(Vec<[f64; 2]>, f64)>,
    pub stopways: Vec<Vec<[f64; 2]>>,
    pub aprons: Vec<Vec<[f64; 2]>>,
    pub shelters: Vec<Vec<[f64; 2]>>,
    pub parking: Vec<[f64; 2]>,
    /// The theatre's main roads in the map (`roads/main.bin`): class (`iaf_avionics::roads::CLASS_*`) and points.
    pub roads: Vec<(u8, Vec<[f64; 2]>)>,
    /// The towns in the map (`places.json`): kind, English and Hebrew name, place.
    pub places: Vec<(String, String, String, [f64; 2])>,
}

impl Briefing {
    /// As JSON for the game: points as flat [x, y, …] arrays, `runway` / `heading` null without a runway.
    pub fn to_json(&self) -> Value {
        let flat = |p: &[[f64; 2]]| p.iter().flat_map(|q| [round(q[0]), round(q[1])]).collect::<Vec<_>>();
        json!({
            "base": self.base,
            "runway": self.runway.as_ref().map(|r| r.0.clone()),
            "heading": self.runway.as_ref().map(|r| r.1.round()),
            "north": (self.north * 100.0).round() / 100.0,
            "size": [round(self.size[0]), round(self.size[1])],
            "fills": self.fills.iter().map(|(c, t)| json!({"color": c, "tris": t.iter().flat_map(|p| [p[0].round(), p[1].round()]).collect::<Vec<_>>()})).collect::<Vec<_>>(),
            "runways": self.runways.iter().map(|(e, w, d)| json!([round(e[0][0]), round(e[0][1]), round(e[1][0]), round(e[1][1]), w, d[0], d[1]])).collect::<Vec<_>>(),
            "start": flat(&[self.start]),
            "taxi": flat(&self.taxi),
            "route": flat(&self.route),
            "extent": self.extent.map(round),
            "taxiways": self.taxiways.iter().map(|(l, w)| json!({"w": w, "pts": flat(l)})).collect::<Vec<_>>(),
            "stopways": self.stopways.iter().map(|l| flat(l)).collect::<Vec<_>>(),
            "aprons": self.aprons.iter().map(|l| flat(l)).collect::<Vec<_>>(),
            "shelters": self.shelters.iter().map(|l| flat(l)).collect::<Vec<_>>(),
            "parking": flat(&self.parking),
            "roads": self.roads.iter().map(|(c, l)| json!({"class": c, "pts": flat(l)})).collect::<Vec<_>>(),
            "places": self.places.iter().map(|(k, en, he, p)| json!({"kind": k, "en": en, "he": he, "at": flat(&[*p])})).collect::<Vec<_>>(),
        })
    }
}

fn round(v: f64) -> f64 {
    (v * 10.0).round() / 10.0
}

/// The briefing map of the readable mission `mission` (modern-iaf/data/missions) over its base from `bases` and the
/// compiled TSD map `map` (EMF-JSON, `sim_cockpit::compile_map`), `aspect` = the map's width / height on screen,
/// with the theatre's main roads `roads` and towns `places` (`places.json`'s entries) inside it. The map zooms in to
/// the base's shapes, which it holds whole.
pub fn briefing(
    mission: &Value,
    bases: &[Base],
    map: &Value,
    aspect: f64,
    roads: Option<&Roads>,
    places: &[Value],
) -> Result<Briefing> {
    let start = &mission["start"];
    let name = start["base"].as_str().context("the mission's start has no \"base\"")?;
    let base = sim_bases::by_name(bases, name).with_context(|| format!("no airbase \"{name}\""))?;
    // The start as the compiler places it (sim.rs compile_mission).
    let at = match start["at"].as_str() {
        Some("runway") => {
            let d = start["runway"].as_str().unwrap_or("");
            let (ri, k) = base.end(d).with_context(|| format!("{}: no runway end {d}", base.name_en))?;
            base.runways[ri].lineup(k)
        }
        Some("parking") if start["lat"].is_null() => {
            let unit = start["unit"].as_str().unwrap_or("");
            base.parking.iter().find(|p| p.unit == unit).map_or(base.parking[0].at, |p| p.at)
        }
        _ => place(start, "start")?,
    };
    let [lon, lat] = utm36n_geo(base.reference[0], base.reference[1]);
    let north = (grid_heading(lon, lat, 0.0) + 180.0).rem_euclid(360.0) - 180.0;
    let (mut taxi, mut route, mut runway) = (vec![], vec![], None);
    if let Some(d) = mission["runway"].as_str() {
        let (ri, k) = base.end(d).with_context(|| format!("{}: no runway end {d}", base.name_en))?;
        let r = &base.runways[ri];
        runway = Some((d.to_string(), (r.heading(k) - north).rem_euclid(360.0)));
        let lineup = r.lineup(k);
        // The departure route is the main runway end's (the AI's, airbases.md §9): the taxi only there.
        if (ri, k) == base.main && at != lineup {
            let rt = sim_bases::routes(base)?;
            taxi = [vec![at], rt.from].concat();
        }
        route.push(lineup);
        for p in mission["route"].as_array().into_iter().flatten() {
            route.push(place(p, "route")?);
        }
    }
    // The extent: the base, the start and the route with MARGIN_M around them, at least MIN_SPAN_M across, at the
    // screen's aspect, centred on them.
    let pts = base.runways.iter().flat_map(|r| r.ends).chain([at]).chain(route.iter().copied());
    let (lo, hi) = pts.fold(([f64::MAX; 2], [f64::MIN; 2]), |(lo, hi), p| {
        ([lo[0].min(p[0]), lo[1].min(p[1])], [hi[0].max(p[0]), hi[1].max(p[1])])
    });
    let need = [hi[0] - lo[0] + 2.0 * MARGIN_M, hi[1] - lo[1] + 2.0 * MARGIN_M];
    let aspect = if aspect > 0.0 { aspect } else { 1.0 };
    let h = need[1].max(need[0] / aspect).max(MIN_SPAN_M / aspect.min(1.0));
    let size = [h * aspect, h];
    let c = [(lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0];
    let ext = [c[0] - size[0] / 2.0, c[1] - size[1] / 2.0, c[0] + size[0] / 2.0, c[1] + size[1] / 2.0];
    let local = |p: [f64; 2]| [p[0] - ext[0], ext[3] - p[1]];
    let mut fills = vec![];
    for op in map["ops"].as_array().context("the map has no \"ops\"")? {
        let (Some(ring), Some(b)) = (op["rings"][0].as_array(), op["brush"].as_array()) else { continue };
        let ring: Vec<[f64; 2]> = ring
            .as_chunks::<2>()
            .0
            .iter()
            .map(|p| from_map([p[0].as_f64().unwrap_or(0.0), p[1].as_f64().unwrap_or(0.0)]))
            .collect();
        let ring = clip_to(ring, ext);
        if ring.len() < 3 {
            continue;
        }
        let ring: Vec<[f32; 2]> = ring.into_iter().map(|p| local(p).map(|v| v as f32)).collect();
        let tris = iaf_formats::emf::fill_triangles(&[ring], true);
        let c = |i: usize| b.get(i).and_then(Value::as_u64).unwrap_or(0).min(255) as u8;
        if !tris.is_empty() {
            fills.push(([c(0), c(1), c(2)], tris));
        }
    }
    let lines = |v: &[Vec<[f64; 2]>]| -> Vec<Vec<[f64; 2]>> {
        v.iter().map(|l| l.iter().map(|&p| local(p)).collect()).collect()
    };
    let inside = |p: [f64; 2]| p[0] >= ext[0] && p[0] <= ext[2] && p[1] >= ext[1] && p[1] <= ext[3];
    let mut road_lines = vec![];
    if let Some(r) = roads {
        for w in r.in_rect([ext[0], ext[1]], [ext[2], ext[3]], roads::CLASS_SECONDARY) {
            let pts: Vec<[f64; 2]> = r.way_points(w).map(local).collect();
            road_lines.push((r.ways[w as usize].class, pts));
        }
    }
    let mut towns: Vec<(String, String, String, [f64; 2])> = places
        .iter()
        .filter_map(|p| {
            let at = [p["x"].as_f64()?, p["y"].as_f64()?];
            let s = |k: &str| p[k].as_str().unwrap_or("").to_string();
            inside(at).then(|| (s("kind"), s("en"), s("he"), local(at)))
        })
        .collect();
    // The cities first, then the towns; the villages only where fewer than VILLAGES_UNDER towns are in the map.
    let rank = |k: &str| sim_scenery::PLACE_KINDS.iter().position(|x| *x == k).unwrap_or(9);
    towns.sort_by_key(|t| rank(&t.0));
    if towns.iter().filter(|t| rank(&t.0) < 2).count() >= VILLAGES_UNDER {
        towns.retain(|t| rank(&t.0) < 2);
    }
    Ok(Briefing {
        extent: ext,
        taxiways: base.taxiways.iter().map(|(l, w)| (l.iter().map(|&p| local(p)).collect(), *w)).collect(),
        stopways: lines(&base.stopways),
        aprons: lines(&base.aprons),
        shelters: lines(&base.shelters),
        parking: base.parking.iter().map(|p| local(p.at)).collect(),
        roads: road_lines,
        places: towns,
        base: base.name_en.trim_end_matches(" Airbase").to_string(),
        runway,
        north,
        size,
        fills,
        runways: base.runways.iter().map(|r| (r.ends.map(local), r.width, r.designators.clone())).collect(),
        start: local(at),
        taxi: taxi.into_iter().map(local).collect(),
        route: route.into_iter().map(local).collect(),
    })
}

/// The theatre's main roads, read once a process (10 MB; the briefing asks for them on every map).
// ponytail: one theatre folder cached; a second folder replaces it.
static ROADS: Mutex<Option<(PathBuf, Arc<Roads>)>> = Mutex::new(None);

fn main_roads(theatre: &Path) -> Option<Arc<Roads>> {
    let mut c = ROADS.lock().ok()?;
    if c.as_ref().is_none_or(|(p, _)| p != theatre) {
        *c = Some((theatre.to_path_buf(), Arc::new(Roads::load(&theatre.join("roads/main.bin"))?)));
    }
    c.as_ref().map(|(_, r)| r.clone())
}

/// The briefing's Arming page (front-end.md §10) with the loadout `lo` (`loadout`): its stores in station order (each
/// store's id, how many hang on the jet and their stations) and `slots` (station → {id, count, max, pylon}), the
/// record's gun rounds, chaff and flares, the 6-DoF jet's internal fuel and empty weight (`iaf_flight::sixdof::jets`,
/// matched by the record's `name`), the stores' weight (each store's `kg` from its record in `weapons`, the folder of
/// `data/db/weapons`, times its count, and each rack's `rack_kg`) and the drop tanks' fuel in it, the take-off weight
/// (empty + internal fuel + stores), the record's `max_takeoff_kg` and `over` (the take-off weight above it). Weights
/// in kg, rounded; a figure it cannot find is null. Also the record's `internal` stations, `allowed` (station → [{id,
/// count}]) and its `inventory`, each entry `{id, count, used, left, group}`: the store's id, the record's count (null:
/// none), how many hang on the jet, how many are left (null without a count) and its group by the weapon's kind ("air"
/// air-to-air missiles, "ground" bombs and air-to-ground missiles (`role` "ground"), "tank"; an unknown weapon is left
/// out).
pub fn arming(unit: &Value, weapons: &Path, lo: &loadout::Loadout) -> Value {
    let record = |w: &str| -> Option<Value> {
        serde_json::from_slice(&std::fs::read(weapons.join(format!("{w}.json"))).ok()?).ok()
    };
    let kind = |id: &str| record(id).and_then(|r| r["kind"].as_str().map(String::from));
    let kg = |id: &str| record(id)?["kg"].as_f64();
    let inventory: Vec<Value> = unit["inventory"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|e| {
            let id = e["weapon"].as_str()?;
            let r = record(id)?;
            let group = match r["kind"].as_str()? {
                _ if r["role"] == "ground" => "ground",
                k if k.ends_with("missile") => "air",
                "bomb" => "ground",
                "tank" => "tank",
                _ => return None,
            };
            let ready = r["model"].as_str().is_some_and(|m| !m.is_empty());
            Some(json!({"id": id, "count": e["count"], "used": loadout::used(lo, id),
                        "left": loadout::left(unit, lo, id), "group": group, "ready": ready}))
        })
        .collect();
    let mut list: Vec<(String, u32, Vec<u32>)> = vec![];
    for (&st, (id, n)) in lo {
        match list.iter_mut().find(|o| &o.0 == id) {
            Some(o) => {
                o.1 += n;
                o.2.push(st);
            }
            None => list.push((id.clone(), *n, vec![st])),
        }
    }
    let mut stores: Vec<Value> =
        list.iter().map(|(w, n, st)| json!({"weapon": w, "count": n, "stations": st})).collect();
    for (w, n) in unit["loadout"].as_object().into_iter().flatten() {
        stores.push(json!({"weapon": w, "count": n.as_i64().unwrap_or(0), "stations": []}));
    }
    // The pylon stores only (the gun's rounds, chaff and flares are in the empty weight, inferred).
    let stores_kg: Option<f64> =
        lo.iter().map(|(&st, (id, n))| Some(kg(id)? * f64::from(*n) + loadout::rack_kg(unit, st, id))).sum();
    let tank_kg: Option<f64> = lo
        .values()
        .filter(|(id, _)| kind(id).as_deref() == Some("tank"))
        .map(|(id, n)| Some(kg(id)? * f64::from(*n)))
        .sum();
    let jet = iaf_flight::sixdof::jets::all().into_iter().find(|j| Some(j.name) == unit["name"].as_str());
    let fuel = jet.as_ref().map(|j| j.fuel_lb * iaf_flight::sixdof::LB);
    let empty = jet.as_ref().zip(fuel).map(|(j, f)| j.airframe.mass - f);
    let takeoff = empty.zip(fuel).zip(stores_kg).map(|((e, f), s)| e + f + s);
    let max = unit["max_takeoff_kg"].as_f64();
    let (imbalance_kg, moment) = lateral(unit, weapons, lo, &kg).unwrap_or((0.0, 0.0));
    let limit = unit["lateral_limit_kgm"].as_f64();
    let imbalanced = limit.is_some_and(|l| moment.abs() > l);
    let over = takeoff.zip(max).is_some_and(|(t, m)| t.round() > m);
    let allowed: Map<String, Value> = loadout::stations(unit)
        .into_iter()
        .map(|s| {
            let a: Vec<Value> = loadout::allowed(unit, s).iter().map(|(id, n)| json!({"id": id, "count": n})).collect();
            (s.to_string(), Value::Array(a))
        })
        .collect();
    // Each station's store, how many, the rack's capacity there and its pylon (0..8 for A..I, the frame the model
    // hangs it on; null for a station the engine's nine pylons leave out).
    let slots: Map<String, Value> = lo
        .iter()
        .map(|(st, (id, n))| {
            let max = loadout::allowed(unit, *st).iter().find(|a| &a.0 == id).map_or(1, |a| a.1);
            (st.to_string(), json!({"id": id, "count": n, "max": max, "pylon": loadout::letter(unit, *st)}))
        })
        .collect();
    let r = |v: Option<f64>| v.map(f64::round);
    json!({
        "stores": stores,
        "slots": slots,
        "loadout": unit["loadout"],
        "fuel_kg": r(fuel),
        "tank_fuel_kg": r(tank_kg),
        "empty_kg": r(empty),
        "stores_kg": r(stores_kg),
        "takeoff_kg": r(takeoff),
        "max_takeoff_kg": unit["max_takeoff_kg"],
        "over": over,
        "imbalance_kg": imbalance_kg.round(),
        "moment_kgm": moment.round(),
        "lateral_limit_kgm": limit,
        "imbalanced": imbalanced,
        "blocked": over || (imbalanced && unit["lateral_limit_hard"].as_bool().unwrap_or(false)),
        "tail": unit["tail"],
        "internal": unit["internal"],
        "allowed": allowed,
        "inventory": inventory,
    })
}

/// The wings' store masses against each other: the difference (kg, the left wing's less the right's) and the rolling
/// moment (kg·m, + the right wing heavier), each station's stores (racks too) at its distance from the jet's middle
/// in the drawing (`data/drawings/<unit id>_front.json` beside `weapons`' folder, its `px_per_m`; station 1, the left
/// wing tip, at the drawing's right). None without the drawing.
fn lateral(
    unit: &Value,
    weapons: &Path,
    lo: &loadout::Loadout,
    kg: &dyn Fn(&str) -> Option<f64>,
) -> Option<(f64, f64)> {
    let path = weapons.join("../../drawings").join(format!("{}_front.json", unit["id"].as_str()?));
    let d: Value = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
    let px = d["px_per_m"].as_f64()?;
    let xs: Vec<(u32, f64)> =
        d["stations"].as_object()?.iter().filter_map(|(k, v)| Some((k.parse().ok()?, v[0].as_f64()?))).collect();
    let mid = xs.iter().map(|x| x.1).sum::<f64>() / xs.len().max(1) as f64;
    let (mut diff, mut moment) = (0.0, 0.0);
    for (&st, (id, n)) in lo {
        let Some(&(_, x)) = xs.iter().find(|x| x.0 == st) else { continue };
        let m = kg(id)? * f64::from(*n) + loadout::rack_kg(unit, st, id);
        // The drawing faces the reader: the left wing (station 1) on its right, x above the middle.
        let arm = (mid - x) / px;
        moment += m * arm;
        diff += if arm < 0.0 {
            m
        } else if arm > 0.0 {
            -m
        } else {
            0.0
        };
    }
    Some((diff, moment))
}

/// [`briefing`] from files: the readable mission, the airbases folder, the compiled map.json and the theatre's folder
/// (`converted/terrain/israel`: `roads/main.bin`, `places.json`; either missing leaves its layer out).
pub fn briefing_files(mission: &Path, airbases: &Path, map: &Path, theatre: &Path, aspect: f64) -> Result<Briefing> {
    let read = |p: &Path| -> Result<Value> {
        Ok(serde_json::from_slice(&std::fs::read(p).with_context(|| p.display().to_string())?)?)
    };
    let roads = main_roads(theatre);
    let places = read(&theatre.join("places.json")).unwrap_or(Value::Null);
    let places = places.as_array().map_or(&[][..], Vec::as_slice);
    briefing(&read(mission)?, &sim_bases::load(airbases)?, &read(map)?, aspect, roads.as_deref(), places)
}

/// The theatre's ground colour over the box `ext` (UTM 36N [x0, y0, x1, y1]) as RGB8, `w` pixels wide (the height at
/// the box's aspect), north up: its level-5 colour nodes (32 m a pixel, `L5/c_<i>_<j>.jpg`, modern-iaf/docs/terrain.md
/// §3) sampled at each pixel's centre; outside the nodes the theatre's sea colour. None without the theatre's
/// `meta.json`.
pub fn ground(theatre: &Path, ext: [f64; 4], w: u32) -> Option<(u32, u32, Vec<u8>)> {
    const LEVEL: u32 = 5;
    let meta: Value = serde_json::from_slice(&std::fs::read(theatre.join("meta.json")).ok()?).ok()?;
    let (e0, n1) = (meta["x_shift"].as_f64()?, meta["y_shift"].as_f64()?);
    let node_px = meta["node_pixels"].as_f64().unwrap_or(1024.0);
    let sea: Vec<u8> = meta["built_from"]["sea"]
        .as_array()
        .map_or(vec![53, 72, 82], |a| a.iter().map(|v| v.as_u64().unwrap_or(0) as u8).collect());
    let w = w.clamp(1, 2048);
    let h = ((f64::from(w) * (ext[3] - ext[1]) / (ext[2] - ext[0])).round() as u32).clamp(1, 4096);
    let (m, span) = (f64::from(1u32 << LEVEL), node_px * f64::from(1u32 << LEVEL));
    let mut nodes: std::collections::HashMap<(i64, i64), Option<image::RgbImage>> = Default::default();
    let mut out = Vec::with_capacity((w * h * 3) as usize);
    for r in 0..h {
        for c in 0..w {
            let x = ext[0] + (f64::from(c) + 0.5) / f64::from(w) * (ext[2] - ext[0]);
            let y = ext[3] - (f64::from(r) + 0.5) / f64::from(h) * (ext[3] - ext[1]);
            let (tx, ty) = (x - e0, n1 - y);
            let k = ((tx / span).floor() as i64, (ty / span).floor() as i64);
            let img = nodes.entry(k).or_insert_with(|| {
                image::open(theatre.join(format!("L{LEVEL}/c_{}_{}.jpg", k.0, k.1))).ok().map(|i| i.to_rgb8())
            });
            match img {
                Some(img) => {
                    let px = (((tx - k.0 as f64 * span) / m) as u32).min(img.width() - 1);
                    let py = (((ty - k.1 as f64 * span) / m) as u32).min(img.height() - 1);
                    out.extend_from_slice(&img.get_pixel(px, py).0);
                }
                None => out.extend_from_slice(&sea[..3]),
            }
        }
    }
    Some((w, h, out))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim_cockpit::{Frame, compile_map};
    use std::path::Path;

    fn data() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data")
    }

    /// A map of one land square around the Negev on the sea, compiled as `iaf-sim own` compiles the TSD's.
    fn map() -> Value {
        let tsd = json!({"background": [34, 34, 91], "background_radar": 0, "layers": [{"name": "land",
            "brush": [137, 136, 135], "radar": 200, "rings": [[[34.0, 30.0], [35.5, 30.0], [35.5, 31.5], [34.0, 31.5]]]}]});
        compile_map(&tsd, &Frame::sim()).unwrap().0
    }

    /// Mitzpe Ramon (in the take-off's area) and Eilat (far outside it).
    fn places() -> Vec<Value> {
        let at = |lon, lat| sim_bases::utm36n(lon, lat);
        let (m, e) = (at(34.8016, 30.6106), at(34.9519, 29.5577));
        vec![
            json!({"kind": "town", "en": "Mitzpe Ramon", "he": "מצפה רמון", "x": m[0], "y": m[1]}),
            json!({"kind": "city", "en": "Eilat", "he": "אילת", "x": e[0], "y": e[1]}),
        ]
    }

    fn mission(name: &str) -> Value {
        serde_json::from_slice(&std::fs::read(data().join(format!("missions/{name}.json"))).unwrap()).unwrap()
    }

    #[test]
    fn take_off_map_holds_the_base_the_taxi_and_the_route() {
        let bases = sim_bases::load(&data().join("airbases")).unwrap();
        let b = briefing(&mission("ramon_takeoff"), &bases, &map(), 0.6, None, &places()).unwrap();
        assert_eq!(b.base, "Ramon");
        let (rwy, hdg) = b.runway.clone().unwrap();
        assert_eq!(rwy, "25R");
        assert!((240.0..260.0).contains(&hdg), "25R's true heading {hdg}");
        assert!((-2.0..-0.5).contains(&b.north), "true north leans west east of 33° E: {}", b.north);
        assert!((b.size[0] / b.size[1] - 0.6).abs() < 1e-9 && b.size[0] >= MIN_SPAN_M);
        let inside = |p: &[f64; 2]| p[0] >= 0.0 && p[1] >= 0.0 && p[0] <= b.size[0] && p[1] <= b.size[1];
        assert!(inside(&b.start) && b.route.iter().all(inside) && b.taxi.iter().all(inside));
        // The taxi runs from the parking spot to the lineup, where the flight starts; one waypoint after it.
        assert_eq!(b.taxi[0], b.start);
        assert_eq!(b.taxi.last(), b.route.first());
        assert_eq!(b.route.len(), 2);
        // The waypoint lies west-south-west of the lineup (25R): x smaller, y larger (south down).
        assert!(b.route[1][0] < b.route[0][0] && b.route[1][1] > b.route[0][1]);
        // The sea first (the background), then the land; every fill is whole triangles inside the map.
        assert_eq!(b.fills.iter().map(|f| f.0).collect::<Vec<_>>(), [[34, 34, 91], [137, 136, 135]]);
        for (_, t) in &b.fills {
            assert!(t.len() % 3 == 0 && !t.is_empty());
            assert!(t.iter().all(|p| p[0] >= -1.0 && p[1] >= -1.0 && p[0] <= b.size[0] as f32 + 1.0));
        }
        // The base's shapes, and the towns inside the map only.
        assert!(!b.taxiways.is_empty() && !b.aprons.is_empty() && !b.parking.is_empty());
        assert!(b.places.len() <= 1 && b.places.iter().all(|p| p.1 != "Eilat"));
        let v = b.to_json();
        assert_eq!(v["route"].as_array().unwrap().len(), 4);
        assert_eq!(v["heading"].as_f64().unwrap(), hdg.round());
    }

    #[test]
    fn stores_list_the_sufas_record() {
        let unit: Value = serde_json::from_slice(&std::fs::read(data().join("db/units/f16i.json")).unwrap()).unwrap();
        let w = data().join("db/weapons");
        let a = arming(&unit, &w, &loadout::default(&unit));
        let v = &a["stores"];
        assert_eq!(v[0], json!({"weapon": "aim-9m", "count": 6, "stations": [1, 2, 3, 7, 8, 9]}));
        assert_eq!(v[1], json!({"weapon": "tank-370", "count": 2, "stations": [4, 6]}));
        assert_eq!(v[2], json!({"weapon": "20mm", "count": 511, "stations": []}));
        assert_eq!(v.as_array().unwrap().len(), 5);
        // The F-35I: an AIM-120 on each bay's inboard station, its real numbers 5 and 7 (pylons D and F).
        let f35: Value = serde_json::from_slice(&std::fs::read(data().join("db/units/f35i.json")).unwrap()).unwrap();
        assert_eq!(
            arming(&f35, &w, &loadout::default(&f35))["stores"][0],
            json!({"weapon": "aim-120", "count": 2, "stations": [5, 7]})
        );
        // The Sufa's weights: 8,850 lb of fuel, 29,350 lb with it, six AIM-9M (86 kg) and two tanks (1,120 kg).
        assert_eq!(a["fuel_kg"], json!(4014.0));
        assert_eq!(a["stores_kg"], json!(6.0 * 86.0 + 2.0 * 1120.0));
        let t = a["takeoff_kg"].as_f64().unwrap();
        assert!((t - (29_350.0 * 0.453_592_37 + 2756.0)).abs() < 1.0, "{t}");
        assert!(t < a["max_takeoff_kg"].as_f64().unwrap());
        assert_eq!(a["tail"], "846");
        let b = arming(&f35, &data().join("db/weapons"), &loadout::default(&f35));
        assert_eq!(b["stores_kg"], json!(2.0 * 161.5));
        assert_eq!(b["internal"], json!([4, 5, 7, 8]));
        // The F-35I's real station numbers on the engine's pylons: 5 is D, 7 is F (its record's `stations`).
        assert_eq!(b["slots"]["5"]["pylon"], json!(3));
        assert_eq!(b["slots"]["7"]["pylon"], json!(5));
        assert_eq!(
            b["inventory"][2],
            json!({"id": "gbu-31", "count": null, "used": 0, "left": null, "group": "ground", "ready": true})
        );
        assert_eq!(b["inventory"][0]["used"], 2);
        assert_eq!(a["over"], false);
        // Three Mk 82 on a TER on 3 and 7 for their AIM-9Ms: the bombs and the racks, the tanks' fuel the same.
        let mut lo = loadout::default(&unit);
        assert!(loadout::put(&unit, &mut lo, 3, "mk-82", true));
        let c = arming(&unit, &data().join("db/weapons"), &lo);
        assert_eq!(c["tank_fuel_kg"], json!(2240.0));
        assert_eq!(c["stores_kg"], json!((4.0f64 * 86.0 + 6.0 * 241.0 + 2.0 * 47.6 + 2.0 * 1120.0).round()));
        assert_eq!(c["slots"]["3"], json!({"id": "mk-82", "count": 3, "max": 3, "pylon": 2}));
        // The stores without a model of ours (the Delilah, the 600 gal tank) are not ready to fly.
        let not_ready: Vec<_> = c["inventory"].as_array().unwrap().iter().filter(|e| e["ready"] == false).collect();
        assert_eq!(
            not_ready.iter().map(|e| e["id"].clone()).collect::<Vec<_>>(),
            [json!("delilah"), json!("tank-600")]
        );
        assert_eq!(c["allowed"]["3"][2], json!({"id": "mk-82", "count": 3}));
        let groups: Vec<_> = a["inventory"].as_array().unwrap().iter().map(|e| e["group"].clone()).collect();
        let want =
            ["air", "air", "air", "ground", "ground", "ground", "ground", "ground", "ground", "ground", "ground"];
        assert_eq!(groups[..11], want.map(|g| json!(g)));
        assert_eq!(groups.len(), 13);
    }

    #[test]
    fn start_up_map_has_no_runway_and_no_route() {
        let bases = sim_bases::load(&data().join("airbases")).unwrap();
        for name in ["ramon_startup", "ramat_david_startup", "nevatim_startup"] {
            let b = briefing(&mission(name), &bases, &map(), 1.5, None, &[]).unwrap();
            assert!(b.runway.is_none() && b.taxi.is_empty() && b.route.is_empty(), "{name}");
            assert!(b.size[1] >= MIN_SPAN_M - 1e-6, "{name}: the shorter side {}", b.size[1]);
            assert!(!b.runways.is_empty());
        }
        // Every take-off's taxi reaches its lineup.
        for name in ["ramat_david_takeoff", "nevatim_takeoff"] {
            let b = briefing(&mission(name), &bases, &map(), 0.6, None, &[]).unwrap();
            assert!(b.taxi.len() >= 2 && b.taxi.last() == b.route.first(), "{name}");
            let inside = |p: &[f64; 2]| p[0] >= 0.0 && p[1] >= 0.0 && p[0] <= b.size[0] && p[1] <= b.size[1];
            assert!(b.taxi.iter().all(inside) && b.parking.iter().all(inside), "{name}");
        }
    }
}
