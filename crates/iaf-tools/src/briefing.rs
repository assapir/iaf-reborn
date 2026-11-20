//! Modern IAF's mission briefing map (modern-iaf/docs/front-end.md §10): a training mission's area with its base, its
//! runways and its route, for the Pick a mission screen. `IafBriefing` hands it to `menu/briefing_map.gd`, which draws.
//!
//! Every place is in the sim's frame (UTM 36N, `sim_bases::utm36n`) and comes back in the map's own metres: x east and
//! y south from the map's north-west corner, so the drawing only scales.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use iaf_avionics::roads::{self, Roads};
use serde_json::{Map, Value, json};

use crate::flights;
use crate::loadout;
use crate::sim::place;
use crate::sim_bases::{self, Base, grid_heading, utm36n_geo};
use crate::sim_cockpit::{clip_to, from_map};
use crate::sim_scenery;
use crate::training::STEP_PLACES;

/// The map's shorter side at least (m; inferred: the base's surroundings with the next towns in view; zooming in
/// shows the base).
pub const MIN_SPAN_M: f64 = 50_000.0;
/// The area shows villages only with fewer towns and cities than this in it (inferred: a readable map).
pub const VILLAGES_UNDER: usize = 6;
/// Room around the base and the route (m; inferred).
pub const MARGIN_M: f64 = 6_000.0;
/// The view the map opens on: the start, the taxi and the lineup with this much room around them (m; inferred: the
/// taxiways next to the route in view) …
pub const FOCUS_MARGIN_M: f64 = 400.0;
/// … and at least this across (m; inferred: a start-up's parking spot with its apron and the runway beside it).
pub const FOCUS_MIN_M: f64 = 2_500.0;

/// A pin on the briefing map: the place of a run of the explanation's paragraphs (`STEP_PLACES`) and the paragraphs
/// done there, `first` to `last` (0-based, in the order of the mission's `briefing.how`).
#[derive(Debug, Clone, PartialEq)]
pub struct Pin {
    pub place: &'static str,
    pub at: [f64; 2],
    pub first: usize,
    pub last: usize,
}

/// The briefing's map.
#[derive(Debug)]
pub struct Briefing {
    /// The base's English name ("Ramon").
    pub base: String,
    /// The runway end the mission takes off from ("25R") and its grid heading (deg): the number the HUD, the compass,
    /// airbases.json's `runway_deg` and the tower read (the sim's world is grid north; the briefing said true 247° for
    /// Ramon's 25R, the HUD 246°, 2026-11-13).
    pub runway: Option<(String, f64)>,
    /// True north as a grid bearing (deg, −180..180; the meridian convergence at the base, the map being grid north
    /// up: east of 33° E true north leans west of grid north).
    pub north: f64,
    /// The map's width and height (m).
    pub size: [f64; 2],
    /// The map's polygons, main roads and towns over its whole area ([`layers`] at the most detail).
    pub layers: Layers,
    /// The base's runways: the two ends, the width (m) and the ends' designators.
    pub runways: Vec<([[f64; 2]; 2], f64, [String; 2])>,
    /// The jet's start (its parking spot or the lineup point).
    pub start: [f64; 2],
    /// The taxi from the start to the lineup point (the base's departure route, `sim_bases::routes`); empty when the
    /// mission takes off from no runway or from another one than that route's.
    pub taxi: Vec<[f64; 2]>,
    /// The flight from the lineup point through the mission's waypoints; empty without a take-off.
    pub route: Vec<[f64; 2]>,
    /// The map's box in the sim's frame [x0, y0, x1, y1] (UTM 36N metres).
    pub extent: [f64; 4],
    /// The base's paved shapes: the taxiways (centreline, width), the stopways (centreline), the aprons and the
    /// shelters' pads (outlines), the parking spots.
    pub taxiways: Vec<(Vec<[f64; 2]>, f64)>,
    pub stopways: Vec<Vec<[f64; 2]>>,
    pub aprons: Vec<Vec<[f64; 2]>>,
    pub shelters: Vec<Vec<[f64; 2]>>,
    pub parking: Vec<[f64; 2]>,
    /// The explanation's pins (`Pin`), in paragraph order.
    pub pins: Vec<Pin>,
    /// The view the map opens on [x0, y0, x1, y1] (the map's metres): the start, the taxi and the lineup.
    pub focus: [f64; 4],
    /// The whole built theatre [x0, y0, x1, y1] (the map's metres; `meta.json`), where the map scrolls; None without it.
    pub theatre: Option<[f64; 4]>,
    /// The mission's other flights (`flights::flights`, Kidon 2..): their callsign and route from their start.
    pub flights: Vec<(&'static str, Vec<[f64; 2]>)>,
}

impl Briefing {
    /// As JSON for the game: points as flat [x, y, …] arrays, `runway` / `heading` null without a runway.
    pub fn to_json(&self) -> Value {
        let flat = |p: &[[f64; 2]]| p.iter().flat_map(|q| [round(q[0]), round(q[1])]).collect::<Vec<_>>();
        let mut v = json!({
            "base": self.base,
            "runway": self.runway.as_ref().map(|r| r.0.clone()),
            "heading": self.runway.as_ref().map(|r| r.1.round()),
            "north": (self.north * 100.0).round() / 100.0,
            "size": [round(self.size[0]), round(self.size[1])],
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
            "pins": self.pins.iter().map(|p| json!({"place": p.place, "at": flat(&[p.at]), "first": p.first, "last": p.last})).collect::<Vec<_>>(),
            "focus": self.focus.map(round),
            "theatre": self.theatre.map(|t| t.map(round)),
            "flights": self.flights.iter().map(|(c, l)| json!({"callsign": c, "pts": flat(l)})).collect::<Vec<_>>(),
        });
        if let (Some(v), Value::Object(l)) = (v.as_object_mut(), self.layers.to_json()) {
            v.extend(l);
        }
        v
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
        runway = Some((d.to_string(), r.heading(k).rem_euclid(360.0)));
        let lineup = r.lineup(k);
        // The departure route is the main runway end's (the AI's, airbases.md §9): the taxi only there.
        if (ri, k) == base.main && at != lineup {
            // From the spot along its own way (a shelter's: airbases.md §5).
            taxi = sim_bases::routes(base)?.departure_from(base, at);
        }
        route.push(lineup);
        for p in mission["route"].as_array().into_iter().flatten() {
            route.push(place(p, "route")?);
        }
    }
    // The other flights (Kidon 2..): from their start along their waypoints.
    let others: Vec<(&'static str, Vec<[f64; 2]>)> = flights::flights(mission, |_| None)?
        .into_iter()
        .filter(|f| !f.player())
        .map(|f| (f.callsign, f.start.into_iter().chain(f.route).collect()))
        .collect();
    // The extent: the base, the start and the routes with MARGIN_M around them, at least MIN_SPAN_M across, at the
    // screen's aspect, centred on them.
    let pts = base.runways.iter().flat_map(|r| r.ends).chain([at]).chain(route.iter().copied());
    let pts = pts.chain(others.iter().flat_map(|o| o.1.iter().copied()));
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
    let layers = layers(map, roads, places, ext, [ext[0], ext[3]], 0.0)?;
    let lines = |v: &[Vec<[f64; 2]>]| -> Vec<Vec<[f64; 2]>> {
        v.iter().map(|l| l.iter().map(|&p| local(p)).collect()).collect()
    };
    let pins = pins(mission, at, &taxi, route.first().copied())?.into_iter().map(|p| Pin { at: local(p.at), ..p });
    // The opening view: the start, the taxi and the lineup, FOCUS_MARGIN_M around them, FOCUS_MIN_M across at least.
    let near = [at].into_iter().chain(taxi.iter().copied()).chain(route.first().copied()).map(local);
    let (lo, hi) = near.fold(([f64::MAX; 2], [f64::MIN; 2]), |(lo, hi), p| {
        ([lo[0].min(p[0]), lo[1].min(p[1])], [hi[0].max(p[0]), hi[1].max(p[1])])
    });
    let half = |a: f64, b: f64| ((b - a) / 2.0 + FOCUS_MARGIN_M).max(FOCUS_MIN_M / 2.0);
    let (fc, fh) = ([(lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0], [half(lo[0], hi[0]), half(lo[1], hi[1])]);
    Ok(Briefing {
        pins: pins.collect(),
        flights: others.into_iter().map(|(c, l)| (c, l.into_iter().map(local).collect())).collect(),
        focus: [fc[0] - fh[0], fc[1] - fh[1], fc[0] + fh[0], fc[1] + fh[1]],
        theatre: None,
        extent: ext,
        taxiways: base.taxiways.iter().map(|(l, w)| (l.iter().map(|&p| local(p)).collect(), *w)).collect(),
        stopways: lines(&base.stopways),
        aprons: lines(&base.aprons),
        shelters: lines(&base.shelters),
        parking: base.parking.iter().map(|p| local(p.at)).collect(),
        base: base.name_en.trim_end_matches(" Airbase").to_string(),
        runway,
        north,
        size,
        layers,
        runways: base.runways.iter().map(|r| (r.ends.map(local), r.width, r.designators.clone())).collect(),
        start: local(at),
        taxi: taxi.into_iter().map(local).collect(),
        route: route.into_iter().map(local).collect(),
    })
}

/// The pins of the mission's explanation (`briefing.how`, its paragraphs; the sim's frame): a paragraph's `at` (one
/// of STEP_PLACES) moves the run to that place, a paragraph without one is done where the one before it was (the
/// first at the start). A place the map lacks (no taxi: no holding point; no runway: no lineup) keeps the run where it
/// was.
fn pins(mission: &Value, start: [f64; 2], taxi: &[[f64; 2]], lineup: Option<[f64; 2]>) -> Result<Vec<Pin>> {
    let steps = mission["briefing"]["how"].as_array().map_or(&[][..], Vec::as_slice);
    let hold = (taxi.len() >= 3).then(|| taxi[taxi.len() - 2]);
    let mut out: Vec<Pin> = vec![];
    for (i, s) in steps.iter().enumerate() {
        let place = match s["at"].as_str() {
            None => out.last().map_or("start", |p| p.place),
            Some(a) => *STEP_PLACES
                .iter()
                .find(|p| **p == a)
                .with_context(|| format!("paragraph {}: no place \"{a}\"", i + 1))?,
        };
        let at = match place {
            "hold" => hold,
            "lineup" => lineup,
            _ => Some(start),
        };
        match (out.last_mut(), at) {
            (Some(p), Some(a)) if p.place != place => out.push(Pin { place, at: a, first: i, last: i }),
            (Some(p), _) => p.last = i,
            (None, a) => out.push(Pin {
                place: if a.is_some() { place } else { "start" },
                at: a.unwrap_or(start),
                first: i,
                last: i,
            }),
        }
    }
    Ok(out)
}

/// The map's layers over a view, in the map's metres: the TSD map's polygons cut to the view (paint order: colour,
/// triangles), the main roads (class, points) and the towns (kind, English and Hebrew name, place).
#[derive(Debug, Default)]
pub struct Layers {
    pub fills: Vec<([u8; 3], Vec<[f32; 2]>)>,
    pub roads: Vec<(u8, Vec<[f64; 2]>)>,
    pub places: Vec<(String, String, String, [f64; 2])>,
}

impl Layers {
    /// As JSON for the game, the keys and shapes of [`Briefing::to_json`]'s `fills`, `roads` and `places`.
    pub fn to_json(&self) -> Value {
        let flat = |p: &[[f64; 2]]| p.iter().flat_map(|q| [round(q[0]), round(q[1])]).collect::<Vec<_>>();
        json!({
            "fills": self.fills.iter().map(|(c, t)| json!({"color": c, "tris": t.iter().flat_map(|p| [p[0].round(), p[1].round()]).collect::<Vec<_>>()})).collect::<Vec<_>>(),
            "roads": self.roads.iter().map(|(c, l)| json!({"class": c, "pts": flat(l)})).collect::<Vec<_>>(),
            "places": self.places.iter().map(|(k, en, he, p)| json!({"kind": k, "en": en, "he": he, "at": flat(&[*p])})).collect::<Vec<_>>(),
        })
    }
}

/// From this scale (m a pixel) up the map's roads are the primary roads and above (the secondary ones would only
/// crowd it; inferred) …
pub const PRIMARY_FROM_M_PX: f64 = 60.0;
/// … and from this one the motorways and trunk roads, the cities without the towns.
pub const TRUNK_FROM_M_PX: f64 = 200.0;

/// The layers of the compiled TSD map `map`, the main roads `roads` and the towns `places` inside the box `ext` (UTM
/// 36N [x0, y0, x1, y1]) in the frame whose north-west corner is `origin` (UTM 36N), drawn at `m_per_px` metres a
/// pixel (0: the most detail): the roads by class (motorway to secondary, fewer from [`PRIMARY_FROM_M_PX`] and
/// [`TRUNK_FROM_M_PX`]) with no two points nearer than a pixel; the cities first, then the towns (none from
/// [`TRUNK_FROM_M_PX`]), the villages only where fewer than [`VILLAGES_UNDER`] towns and cities are in the box.
pub fn layers(
    map: &Value,
    roads: Option<&Roads>,
    places: &[Value],
    ext: [f64; 4],
    origin: [f64; 2],
    m_per_px: f64,
) -> Result<Layers> {
    let local = |p: [f64; 2]| [p[0] - origin[0], origin[1] - p[1]];
    let mut out = Layers::default();
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
            out.fills.push(([c(0), c(1), c(2)], tris));
        }
    }
    if let Some(r) = roads {
        let class = match m_per_px {
            m if m >= TRUNK_FROM_M_PX => roads::CLASS_TRUNK,
            m if m >= PRIMARY_FROM_M_PX => roads::CLASS_PRIMARY,
            _ => roads::CLASS_SECONDARY,
        };
        for w in r.in_rect([ext[0], ext[1]], [ext[2], ext[3]], class) {
            let mut pts: Vec<[f64; 2]> = vec![];
            let all: Vec<[f64; 2]> = r.way_points(w).collect();
            for (i, &p) in all.iter().enumerate() {
                let far = pts.last().is_none_or(|q: &[f64; 2]| (q[0] - p[0]).hypot(q[1] - p[1]) >= m_per_px);
                if far || i + 1 == all.len() {
                    pts.push(p);
                }
            }
            out.roads.push((r.ways[w as usize].class, pts.into_iter().map(local).collect()));
        }
    }
    let inside = |p: [f64; 2]| p[0] >= ext[0] && p[0] <= ext[2] && p[1] >= ext[1] && p[1] <= ext[3];
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
    if m_per_px >= TRUNK_FROM_M_PX {
        towns.retain(|t| rank(&t.0) < 1);
    } else if towns.iter().filter(|t| rank(&t.0) < 2).count() >= VILLAGES_UNDER {
        towns.retain(|t| rank(&t.0) < 2);
    }
    out.places = towns;
    Ok(out)
}

/// The UTM 36N box of the map's view `view` [x0, y0, x1, y1] (the map's metres, y south) whose map's north-west
/// corner is `origin`.
pub fn view_box(view: [f64; 4], origin: [f64; 2]) -> [f64; 4] {
    [origin[0] + view[0], origin[1] - view[3], origin[0] + view[2], origin[1] - view[1]]
}

/// [`layers`] from files over the view `view` (the map's metres from `origin`): the compiled map.json and the
/// theatre's folder (`roads/main.bin`, `places.json`; either missing leaves its layer out).
pub fn layers_files(map: &Path, theatre: &Path, view: [f64; 4], origin: [f64; 2], m_per_px: f64) -> Result<Layers> {
    let map: Value = serde_json::from_slice(&std::fs::read(map).with_context(|| map.display().to_string())?)?;
    let roads = main_roads(theatre);
    let places = towns(theatre);
    let places = places.as_deref().map_or(&[][..], Vec::as_slice);
    layers(&map, roads.as_deref(), places, view_box(view, origin), origin, m_per_px)
}

/// The theatre's colour pyramid as `meta.json` describes it (modern-iaf/docs/terrain.md §3): its frame (the
/// north-west corner's easting and northing), a level-0 node's side and pixel (m), the root level, its size (m) and the
/// colour nodes each level has (level, i, j).
#[derive(Debug, Default)]
pub struct Pyramid {
    pub e0: f64,
    pub n1: f64,
    pub span0: f64,
    pub px0: f64,
    pub root: u32,
    pub size: [f64; 2],
    pub nodes: HashSet<(u32, i64, i64)>,
}

impl Pyramid {
    fn from_meta(meta: &Value) -> Option<Pyramid> {
        let t = meta["theatre"].as_array()?;
        let mut nodes = HashSet::new();
        for (l, list) in meta["nodes"].as_object()? {
            let l: u32 = l.parse().ok()?;
            for ij in list.as_array()? {
                nodes.insert((l, ij[0].as_i64()?, ij[1].as_i64()?));
            }
        }
        let u = meta["units_to_metres"].as_f64().unwrap_or(1.0);
        Some(Pyramid {
            e0: meta["x_shift"].as_f64()?,
            n1: meta["y_shift"].as_f64()?,
            span0: meta["node_pixels"].as_f64().unwrap_or(1024.0) * u,
            px0: u,
            root: meta["root_level"].as_u64()? as u32,
            size: [(t[2].as_f64()? - t[0].as_f64()?) * u, (t[3].as_f64()? - t[1].as_f64()?) * u],
            nodes,
        })
    }

    /// The theatre's box in the frame whose north-west corner is `origin` (UTM 36N): [x0, y0, x1, y1], y south.
    pub fn local_box(&self, origin: [f64; 2]) -> [f64; 4] {
        let (x0, y0) = (self.e0 - origin[0], origin[1] - self.n1);
        [x0, y0, x0 + self.size[0], y0 + self.size[1]]
    }

    /// The colour nodes that draw the UTM 36N box `ext` at `m_per_px` metres a pixel, coarse to fine, each (level, i,
    /// j, its UTM 36N box): the level whose pixel is the largest within a screen pixel (the finest one there is, at
    /// most the root) and the [`TILE_LEVELS`]` − 1` above it (shown while the finer ones load, and where they have no
    /// node), then coarser ones until one level covers the whole box.
    pub fn tiles(&self, ext: [f64; 4], m_per_px: f64) -> Vec<(u32, i64, i64, [f64; 4])> {
        let finest = self.nodes.iter().map(|n| n.0).min().unwrap_or(0);
        let l0 = ((m_per_px / self.px0).max(1.0).log2().floor() as u32).clamp(finest, self.root.max(finest));
        let mut out = vec![];
        let mut covered = false;
        for l in l0..=self.root.max(l0) {
            let span = self.span0 * f64::from(1u32 << l);
            let last = |m: f64| ((m / span).ceil() as i64 - 1).max(0);
            let cell = |m: f64, hi: i64| ((m / span).floor() as i64).clamp(0, hi);
            let (ilast, jlast) = (last(self.size[0]), last(self.size[1]));
            let (i0, i1) = (cell(ext[0] - self.e0, ilast), cell(ext[2] - self.e0, ilast));
            let (j0, j1) = (cell(self.n1 - ext[3], jlast), cell(self.n1 - ext[1], jlast));
            let mut all = true;
            for j in j0..=j1 {
                for i in i0..=i1 {
                    if self.nodes.contains(&(l, i, j)) {
                        let x = self.e0 + i as f64 * span;
                        let y = self.n1 - j as f64 * span;
                        out.push((l, i, j, [x, y - span, x + span, y]));
                    } else {
                        all = false;
                    }
                }
            }
            covered |= all;
            if covered && l + 1 >= l0 + TILE_LEVELS {
                break;
            }
        }
        out.reverse();
        out
    }
}

/// The levels [`Pyramid::tiles`] always asks for: the view's own and the coarser ones shown while it loads.
pub const TILE_LEVELS: u32 = 3;

/// The theatre's pyramid, read once a process.
// ponytail: one theatre folder cached; a second folder replaces it.
static PYRAMID: Mutex<Option<(PathBuf, Arc<Pyramid>)>> = Mutex::new(None);

/// The theatre's colour pyramid (`meta.json`); None without it.
pub fn pyramid(theatre: &Path) -> Option<Arc<Pyramid>> {
    let mut c = PYRAMID.lock().ok()?;
    if c.as_ref().is_none_or(|(p, _)| p != theatre) {
        let meta: Value = serde_json::from_slice(&std::fs::read(theatre.join("meta.json")).ok()?).ok()?;
        *c = Some((theatre.to_path_buf(), Arc::new(Pyramid::from_meta(&meta)?)));
    }
    c.as_ref().map(|(_, p)| p.clone())
}

/// The theatre's towns (`places.json`), read once a process (350 kB; the map asks for them wherever it scrolls).
// ponytail: one theatre folder cached; a second folder replaces it.
static TOWNS: Mutex<Option<(PathBuf, Arc<Vec<Value>>)>> = Mutex::new(None);

fn towns(theatre: &Path) -> Option<Arc<Vec<Value>>> {
    let mut c = TOWNS.lock().ok()?;
    if c.as_ref().is_none_or(|(p, _)| p != theatre) {
        let v: Value = serde_json::from_slice(&std::fs::read(theatre.join("places.json")).ok()?).ok()?;
        *c = Some((theatre.to_path_buf(), Arc::new(v.as_array()?.clone())));
    }
    c.as_ref().map(|(_, t)| t.clone())
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
/// matched by the record's `name`), the stores' weight (each store's `kg`, plus a tank's `empty_kg`, from its record in
/// `weapons`, the folder of `data/db/weapons`, times its count, and each rack's `rack_kg`) and the drop tanks' fuel in it, the take-off weight
/// (empty + internal fuel + stores), the record's `max_takeoff_kg` and `over` (the take-off weight above it). Weights
/// in kg, rounded; a figure it cannot find is null. Also the record's `internal` stations, its `positions` and
/// `labels` (station → the name the screens show where it is not the number: the F-16's 5R / 5L), `pylons` (station →
/// the engine's station index), `allowed` (station → [{id, count}]) and its `inventory`, each entry `{id, count, used, left, group}`: the store's id, the record's count (null:
/// none), how many hang on the jet, how many are left (null without a count) and its group by the weapon's kind ("air"
/// air-to-air missiles, "ground" bombs, laser bombs and air-to-ground missiles (`role` "ground"), "tank", "pod"; an
/// unknown weapon is left out).
pub fn arming(unit: &Value, weapons: &Path, lo: &loadout::Loadout) -> Value {
    let record = |w: &str| -> Option<Value> {
        serde_json::from_slice(&std::fs::read(weapons.join(format!("{w}.json"))).ok()?).ok()
    };
    let kind = |id: &str| record(id).and_then(|r| r["kind"].as_str().map(String::from));
    let kg = |id: &str| record(id)?["kg"].as_f64();
    // A tank's own empty weight (`empty_kg`) beside its fuel `kg`, as the flown stores count it (stores.rs).
    let empty = |id: &str| record(id).and_then(|r| r["empty_kg"].as_f64()).unwrap_or(0.0);
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
                "bomb" | "laser_bomb" => "ground",
                "pod" => "pod",
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
    // The pylon stores only (the gun's rounds, chaff and flares are in the empty weight, inferred), racks too, each at
    // its arm (`arms`; 0 off the drawing): their sum, the wings' difference and the rolling moment (`loadout::weigh`).
    let arm = arms(unit, weapons);
    let stores_w: Option<Vec<(f64, f64)>> = lo
        .iter()
        .map(|(&st, (id, n))| {
            let a = arm.iter().find(|x| x.0 == st).map_or(0.0, |x| x.1);
            Some((a, (kg(id)? + empty(id)) * f64::from(*n) + loadout::rack_kg(unit, st, id)))
        })
        .collect();
    let weight = stores_w.map(|s| loadout::weigh(0.0, &s));
    let stores_kg = weight.map(|w| w.total);
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
    let (imbalance_kg, moment) = weight.map_or((0.0, 0.0), |w| (w.left - w.right, w.moment));
    let limit = unit["lateral_limit_kgm"].as_f64();
    let imbalanced = limit.is_some_and(|l| moment.abs() > l);
    let over = takeoff.zip(max).is_some_and(|(t, m)| t.round() > m);
    // Every station's engine station index (`loadout::letter`: A..I 0..8, J 12; null none), where the Loadout screen
    // draws its line to.
    let pylons: Map<String, Value> =
        loadout::stations(unit).into_iter().map(|s| (s.to_string(), json!(loadout::letter(unit, s)))).collect();
    let allowed: Map<String, Value> = loadout::stations(unit)
        .into_iter()
        .map(|s| {
            let a: Vec<Value> = loadout::allowed(unit, s).iter().map(|(id, n)| json!({"id": id, "count": n})).collect();
            (s.to_string(), Value::Array(a))
        })
        .collect();
    // Where the wings' stores lean, −1 (the left wing at its limit or alone) .. 1: the moment over the record's limit,
    // else (no limit published) the wings' difference over their stores.
    let balance = match (limit, weight) {
        (Some(l), _) if l > 0.0 => (moment / l).clamp(-1.0, 1.0),
        (_, Some(w)) if w.left + w.right > 0.0 => (w.right - w.left) / (w.left + w.right),
        _ => 0.0,
    };
    // Each station: its store, how many, their weight with the rack's (kg), the rack's capacity there and its pylon
    // (0..8 for A..I, the frame the model hangs it on; null for a station the engine's nine pylons leave out).
    let slots: Map<String, Value> = lo
        .iter()
        .map(|(st, (id, n))| {
            let max = loadout::allowed(unit, *st).iter().find(|a| &a.0 == id).map_or(1, |a| a.1);
            let shell = record(id).and_then(|r| r["empty_kg"].as_f64()).unwrap_or(0.0); // a tank's own weight
            let kg = kg(id).map(|k| ((k + shell) * f64::from(*n) + loadout::rack_kg(unit, *st, id)).round());
            (st.to_string(), json!({"id": id, "count": n, "max": max, "pylon": loadout::letter(unit, *st), "kg": kg}))
        })
        .collect();
    let unmet = needs(unit, &record, lo);
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
        "balance": (balance * 1000.0).round() / 1000.0,
        "positions": unit["positions"],
        "labels": unit["labels"],
        "pylons": pylons,
        "blocked": over || (imbalanced && unit["lateral_limit_hard"].as_bool().unwrap_or(false)) || !unmet.is_empty(),
        "unmet": unmet,
        "tail": unit["tail"],
        "internal": unit["internal"],
        "allowed": allowed,
        "inventory": inventory,
    })
}

/// [`arming`] for the readable mission `mission` (null: none): a lesson that counts ground kills (its `training`'s
/// `ground_kills`) needs that many air-to-ground stores aboard (the inventory's group "ground"); fewer adds the unmet
/// need {weapon: null, need: "ground", store, station} (store: the inventory's first ground store that needs nothing
/// else) and blocks the load. Every screen and the flight call ask this one rule (weapons.md §7.1; the user,
/// 2026-11-18: a saved load with no bombs flew the range lesson).
pub fn mission_arming(unit: &Value, weapons: &Path, lo: &loadout::Loadout, mission: &Value) -> Value {
    let mut a = arming(unit, weapons, lo);
    let want = mission["training"]["ground_kills"].as_u64().unwrap_or(0);
    let inv: Vec<Value> = a["inventory"].as_array().cloned().unwrap_or_default();
    let ground = || inv.iter().filter(|e| e["group"] == "ground");
    if ground().map(|e| e["used"].as_u64().unwrap_or(0)).sum::<u64>() >= want {
        return a;
    }
    let free = |e: &&Value| -> bool {
        let r = e["id"].as_str().and_then(|id| std::fs::read(weapons.join(format!("{id}.json"))).ok());
        let r: Value = r.and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        r["needs"].as_array().is_none_or(Vec::is_empty)
    };
    let store = ground().find(free).and_then(|e| e["id"].as_str());
    let station = store.and_then(|s| {
        loadout::stations(unit).into_iter().find(|&st| loadout::allowed(unit, st).iter().any(|x| x.0 == s))
    });
    let need = json!({"weapon": null, "need": "ground", "store": store, "station": station});
    if let Some(u) = a["unmet"].as_array_mut() {
        u.push(need);
    }
    a["blocked"] = json!(true);
    a
}

/// The loadout's unmet needs (modern-iaf/docs/weapons.md §7.1, `iaf_avionics::stores::unmet`): for each store on the jet
/// whose record `needs` what no store on the jet `gives` (nor the jet's built-in pod, its aircraft definition's `flir`,
/// which gives the laser), {weapon, need, store, station}: the store the record's inventory holds that gives it and the
/// first station that takes that store (null when none), for the line that says what to add.
fn needs(unit: &Value, record: &dyn Fn(&str) -> Option<Value>, lo: &loadout::Loadout) -> Vec<Value> {
    let list = |v: &Value| -> Vec<String> {
        v.as_array().into_iter().flatten().filter_map(|s| s.as_str().map(String::from)).collect()
    };
    let built_in = unit["airframe"].as_str().and_then(iaf_flight::airframe::get).and_then(|a| a.flir) == Some(true);
    let mut gives: Vec<String> = lo.values().filter_map(|(id, _)| record(id)).flat_map(|r| list(&r["gives"])).collect();
    if built_in {
        gives.push("laser".into());
    }
    let gives: Vec<&str> = gives.iter().map(String::as_str).collect();
    let mut out: Vec<Value> = vec![];
    for (id, _) in lo.values() {
        let Some(r) = record(id) else { continue };
        let wanted = list(&r["needs"]);
        let wanted: Vec<&str> = wanted.iter().map(String::as_str).collect();
        for n in iaf_avionics::stores::unmet(&wanted, &gives) {
            if out.iter().any(|o| o["weapon"] == id.as_str() && o["need"] == n) {
                continue;
            }
            let store = unit["inventory"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|e| e["weapon"].as_str())
                .find(|s| record(s).is_some_and(|g| list(&g["gives"]).iter().any(|x| x == n)));
            let station = store.and_then(|s| {
                loadout::stations(unit).into_iter().find(|&st| loadout::allowed(unit, st).iter().any(|a| a.0 == s))
            });
            out.push(json!({"weapon": id, "need": n, "store": store, "station": station}));
        }
    }
    out
}

/// A weapon record of `weapons` guides by GPS / INS to a stored point (its `guidance` "gps": the JDAMs, the GBU-39, the
/// SPICE, the Delilah): the stores that take a PRE target.
fn gps_store(weapons: &Path, id: &str) -> bool {
    let r = std::fs::read(weapons.join(format!("{id}.json"))).ok();
    let r: Value = r.and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    r["guidance"] == "gps"
}

/// The mission `mission`'s side of the pick rule (`iaf_avionics::gps::PreMission`).
fn pre_mission(mission: &Value) -> iaf_avionics::gps::PreMission<'_> {
    let n = |k: &str| mission[k].as_array().map_or(0, Vec::len);
    iaf_avionics::gps::PreMission {
        id: mission["id"].as_str().unwrap_or(""),
        targets: n("targets"),
        steers: n("route"),
    }
}

/// Station `st`'s GPS side of the pick rule on the stores `stores`: (a GPS store, how many).
fn gps_on(weapons: &Path, stores: &loadout::Loadout, st: u32) -> (bool, u32) {
    stores.get(&st).map_or((false, 0), |(id, n)| (gps_store(weapons, id), *n))
}

/// The picks of the loadout JSON `lo` that pass the rule (`gps::pick_ok`) on its stores (`loadout::parse`) and
/// `mission`, one per station or bomb.
pub fn valid_picks(unit: &Value, weapons: &Path, lo: &Value, mission: &Value) -> Vec<loadout::Pick> {
    let stores = loadout::parse(unit, lo);
    let m = pre_mission(mission);
    let mut out: Vec<loadout::Pick> = vec![];
    for p in loadout::picks(lo) {
        let (gps, n) = gps_on(weapons, &stores, p.station);
        let twice = out.iter().any(|q| (q.station, q.bomb) == (p.station, p.bomb));
        if !twice && iaf_avionics::gps::pick_ok(gps, n, p.bomb, &p.aim, m) {
            out.push(p);
        }
    }
    out
}

/// An aim on mission `mission` as the screens and the flight take it: {kind ("target", "steer", "point"), n (the
/// target's or steerpoint's number; 0 a point), name (a target's, "Target 1"; else null), lat, lon, x, y (the sim's
/// world, UTM 36N)}; null when the mission lacks it.
fn aim_json(aim: &loadout::PreAim, mission: &Value) -> Value {
    let (kind, n, p) = match aim {
        loadout::PreAim::Target(n) => ("target", *n, mission["targets"][n.saturating_sub(1)].clone()),
        loadout::PreAim::Steer(n) => ("steer", *n, mission["route"][n.saturating_sub(1)].clone()),
        loadout::PreAim::Point { lat, lon, .. } => ("point", 0, json!({"lat": lat, "lon": lon})),
    };
    let Ok([x, y]) = place(&p, kind) else { return Value::Null };
    json!({"kind": kind, "n": n, "name": p["name"], "lat": p["lat"], "lon": p["lon"], "x": x, "y": y})
}

/// The PRE targets of the loadout JSON `lo` (its stores and its `pre` picks) on `mission` (A61, modern-iaf/docs/
/// weapons.md §13.2), for the briefing's panel and the flight (`flight/fly.gd` hands them to `Settings.gps_targets`):
/// - `rows`: each GPS station in station order, {station, label (the screens' name: 5R), pylon (the engine's station
///   index), weapon, count, bomb -1, aim (its pick, `aim_json`; null: none)}, a rack's bombs after it, each {…, bomb k
///   (0 the first to leave), aim (its own pick; null: the station's)};
/// - `aims`: what a click on the map may pick: the mission's targets, then its steerpoints (`aim_json` each);
/// - `default`: the aim of a station without a pick, the route's target steerpoint (`gps::default_target`; null: none).
pub fn pre(unit: &Value, weapons: &Path, lo: &Value, mission: &Value) -> Value {
    let stores = loadout::parse(unit, lo);
    let picks = valid_picks(unit, weapons, lo, mission);
    let aim_of = |st: u32, b: Option<u32>| {
        picks.iter().find(|p| p.station == st && p.bomb == b).map_or(Value::Null, |p| aim_json(&p.aim, mission))
    };
    let mut rows = vec![];
    for (&st, (id, n)) in &stores {
        if !gps_store(weapons, id) {
            continue;
        }
        let label = unit["labels"][st.to_string()].as_str().map_or(st.to_string(), String::from);
        let row = |bomb: i64, aim: Value| {
            json!({"station": st, "label": label, "pylon": loadout::letter(unit, st), "weapon": id, "count": n,
                   "bomb": bomb, "aim": aim})
        };
        rows.push(row(-1, aim_of(st, None)));
        for k in (0..*n).filter(|_| *n > 1) {
            rows.push(row(i64::from(k), aim_of(st, Some(k))));
        }
    }
    let m = pre_mission(mission);
    let mut aims: Vec<Value> = (1..=m.targets).map(|n| aim_json(&loadout::PreAim::Target(n), mission)).collect();
    aims.extend((1..=m.steers).map(|n| aim_json(&loadout::PreAim::Steer(n), mission)));
    let route: Vec<i64> =
        mission["route"].as_array().into_iter().flatten().map(|w| if w["target"] == true { 5 } else { 0 }).collect();
    let default = iaf_avionics::gps::default_target(&route)
        .map_or(Value::Null, |i| aim_json(&loadout::PreAim::Steer(i + 1), mission));
    json!({"rows": rows, "aims": aims, "default": default})
}

/// The loadout JSON `lo` with the PRE pick of `pick` (station, and Some bomb for that bomb's own) set to `aim` (None:
/// cleared; a station's pick clears its bombs' own too), the picks that no longer pass the rule left out; None when
/// the new pick fails the rule (`gps::pick_ok`).
pub fn pre_set(
    unit: &Value,
    weapons: &Path,
    lo: &Value,
    mission: &Value,
    pick: (u32, Option<u32>),
    aim: Option<loadout::PreAim>,
) -> Option<Value> {
    let (station, bomb) = pick;
    let stores = loadout::parse(unit, lo);
    let mut picks = valid_picks(unit, weapons, lo, mission);
    picks.retain(|p| p.station != station || (bomb.is_some() && p.bomb != bomb));
    if let Some(aim) = aim {
        let (gps, n) = gps_on(weapons, &stores, station);
        if !iaf_avionics::gps::pick_ok(gps, n, bomb, &aim, pre_mission(mission)) {
            return None;
        }
        picks.push(loadout::Pick { station, bomb, aim });
    }
    Some(loadout::to_json_with(&stores, &picks))
}

/// Each station's distance from the jet's middle (m, + toward the right wing) in the drawing
/// (`data/drawings/<unit id>_front.json` beside `weapons`' folder, its `px_per_m`; station 1, the left wing tip, at the
/// drawing's right). Empty without the drawing.
fn arms(unit: &Value, weapons: &Path) -> Vec<(u32, f64)> {
    let read = || -> Option<Vec<(u32, f64)>> {
        let path = weapons.join("../../drawings").join(format!("{}_front.json", unit["id"].as_str()?));
        let d: Value = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
        let px = d["px_per_m"].as_f64()?;
        let xs: Vec<(u32, f64)> =
            d["stations"].as_object()?.iter().filter_map(|(k, v)| Some((k.parse().ok()?, v[0].as_f64()?))).collect();
        let mid = xs.iter().map(|x| x.1).sum::<f64>() / xs.len().max(1) as f64;
        // The drawing faces the reader: the left wing (station 1) on its right, x above the middle.
        Some(xs.into_iter().map(|(st, x)| (st, (mid - x) / px)).collect())
    };
    read().unwrap_or_default()
}

/// [`briefing`] from files: the readable mission, the airbases folder, the compiled map.json and the theatre's folder
/// (`converted/terrain/israel`: `roads/main.bin`, `places.json`; either missing leaves its layer out).
pub fn briefing_files(mission: &Path, airbases: &Path, map: &Path, theatre: &Path, aspect: f64) -> Result<Briefing> {
    let read = |p: &Path| -> Result<Value> {
        Ok(serde_json::from_slice(&std::fs::read(p).with_context(|| p.display().to_string())?)?)
    };
    let roads = main_roads(theatre);
    let places = towns(theatre);
    let places = places.as_deref().map_or(&[][..], Vec::as_slice);
    let mut b = briefing(&read(mission)?, &sim_bases::load(airbases)?, &read(map)?, aspect, roads.as_deref(), places)?;
    b.theatre = pyramid(theatre).map(|p| p.local_box([b.extent[0], b.extent[3]]));
    Ok(b)
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
        // The grid heading, as airbases.json's runway_deg, the HUD and the compass (246°, not true 247°).
        let ramon = sim_bases::by_name(&bases, "Ramon").unwrap();
        let (ri, k) = ramon.end("25R").unwrap();
        assert_eq!(hdg.round(), ramon.runways[ri].heading(k).round(), "25R's grid heading {hdg}");
        assert_eq!(hdg.round(), 246.0);
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
        assert_eq!(b.layers.fills.iter().map(|f| f.0).collect::<Vec<_>>(), [[34, 34, 91], [137, 136, 135]]);
        for (_, t) in &b.layers.fills {
            assert!(t.len() % 3 == 0 && !t.is_empty());
            assert!(t.iter().all(|p| p[0] >= -1.0 && p[1] >= -1.0 && p[0] <= b.size[0] as f32 + 1.0));
        }
        // The base's shapes, and the towns inside the map only.
        assert!(!b.taxiways.is_empty() && !b.aprons.is_empty() && !b.parking.is_empty());
        assert!(b.layers.places.len() <= 1 && b.layers.places.iter().all(|p| p.1 != "Eilat"));
        // The pins: the explanation's paragraphs 1-3 at the parking spot, 4 at the holding point (the taxi's last point
        // before the lineup), 5-6 at the lineup; the opening view holds them and the taxi.
        let want = [("start", b.start, 0, 2), ("hold", b.taxi[b.taxi.len() - 2], 3, 3), ("lineup", b.route[0], 4, 5)];
        assert_eq!(b.pins, want.map(|(place, at, first, last)| Pin { place, at, first, last }));
        let f = b.focus;
        let held = |p: &[f64; 2]| p[0] > f[0] && p[0] < f[2] && p[1] > f[1] && p[1] < f[3];
        assert!(b.taxi.iter().all(held) && f[2] - f[0] >= FOCUS_MIN_M && f[2] - f[0] < 8_000.0, "{f:?}");
        let v = b.to_json();
        assert_eq!(v["pins"][1]["first"], 3);
        assert_eq!(v["route"].as_array().unwrap().len(), 4);
        assert_eq!(v["heading"].as_f64().unwrap(), hdg.round());
        assert!(b.flights.is_empty() && v["flights"] == json!([]), "one flight: the player's, drawn as the route");
    }

    /// The two-flight sample (modern-iaf/tests/data, not a shipped mission): Kidon 2's route from its start, in the map,
    /// the player's route as before.
    #[test]
    fn a_second_flight_has_its_own_route() {
        let bases = sim_bases::load(&data().join("airbases")).unwrap();
        let two: Value =
            serde_json::from_slice(&std::fs::read(data().join("../tests/data/two_flights.json")).unwrap()).unwrap();
        let b = briefing(&two, &bases, &map(), 0.6, None, &[]).unwrap();
        let one = briefing(&mission("ramon_takeoff"), &bases, &map(), 0.6, None, &[]).unwrap();
        assert_eq!(b.flights.len(), 1);
        let (callsign, pts) = &b.flights[0];
        assert_eq!((*callsign, pts.len()), ("Kidon 2", 3), "its start and two waypoints");
        let inside = |p: &[f64; 2]| p[0] >= 0.0 && p[1] >= 0.0 && p[0] <= b.size[0] && p[1] <= b.size[1];
        assert!(pts.iter().all(inside), "the map holds Kidon 2's route");
        assert_eq!(b.route.len(), one.route.len());
        assert_eq!(b.to_json()["flights"][0]["callsign"], "Kidon 2");
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
        // The Sufa's weights: 8,850 lb of fuel, 29,350 lb with it, six AIM-9M (86 kg) and two tanks (1,120 kg of fuel
        // and 201 kg empty each).
        assert_eq!(a["fuel_kg"], json!(4014.0));
        assert_eq!(a["stores_kg"], json!(6.0 * 86.0 + 2.0 * (1120.0 + 201.0)));
        let t = a["takeoff_kg"].as_f64().unwrap();
        assert!((t - (29_350.0 * 0.453_592_37 + 3158.0)).abs() < 1.0, "{t}");
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
        // Three Mk 82 on a TER on 3 and 7 for their AIM-9Ms: the bombs and the racks, the tanks' fuel the same (and
        // their 201 kg empty).
        let mut lo = loadout::default(&unit);
        assert!(loadout::put(&unit, &mut lo, 3, "mk-82", true));
        let c = arming(&unit, &data().join("db/weapons"), &lo);
        assert_eq!(c["tank_fuel_kg"], json!(2240.0));
        assert_eq!(c["stores_kg"], json!((4.0f64 * 86.0 + 6.0 * 241.0 + 2.0 * 47.6 + 2.0 * (1120.0 + 201.0)).round()));
        // Each station's weight: the three bombs and their rack.
        assert_eq!(
            c["slots"]["3"],
            json!({"id": "mk-82", "count": 3, "max": 3, "pylon": 2, "kg": (3.0f64 * 241.0 + 47.6).round()})
        );
        // The store without a model of ours (the 600 gal tank) is not ready to fly; the Delilah is neither listed nor
        // allowed anywhere (dropped for now, the user 2026-11-14: no cruise-missile flight class).
        let not_ready: Vec<_> = c["inventory"].as_array().unwrap().iter().filter(|e| e["ready"] == false).collect();
        assert_eq!(not_ready.iter().map(|e| e["id"].clone()).collect::<Vec<_>>(), [json!("tank-600")]);
        assert!(!c.to_string().contains("delilah"), "the Delilah is not offered");
        assert_eq!(c["allowed"]["3"][2], json!({"id": "mk-82", "count": 3}));
        let groups: Vec<_> = a["inventory"].as_array().unwrap().iter().map(|e| e["group"].clone()).collect();
        let want = ["air", "air", "air", "ground", "ground", "ground", "ground", "ground", "ground", "ground"];
        assert_eq!(groups[..10], want.map(|g| json!(g)));
        // The laser bombs, the targeting pod (the loadout line asks for it) and the navigation pod are on the shelf too.
        assert_eq!(groups[12..], [json!("ground"), json!("ground"), json!("ground"), json!("pod"), json!("pod")]);
    }

    #[test]
    fn start_up_map_has_no_runway_and_no_route() {
        let bases = sim_bases::load(&data().join("airbases")).unwrap();
        for name in ["ramon_startup", "ramat_david_startup", "nevatim_startup"] {
            let b = briefing(&mission(name), &bases, &map(), 1.5, None, &[]).unwrap();
            assert!(b.runway.is_none() && b.taxi.is_empty() && b.route.is_empty(), "{name}");
            assert!(b.size[1] >= MIN_SPAN_M - 1e-6, "{name}: the shorter side {}", b.size[1]);
            assert!(!b.runways.is_empty());
            // One pin, the whole explanation at the parking spot; the view on it.
            assert!(b.pins.len() == 1 && b.pins[0].place == "start" && b.pins[0].at == b.start, "{name}");
            assert!(b.pins[0].last >= 3 && (b.focus[2] - b.focus[0] - FOCUS_MIN_M).abs() < 1e-6, "{name}");
        }
        // Every take-off's taxi reaches its lineup.
        for name in ["ramat_david_takeoff", "nevatim_takeoff"] {
            let b = briefing(&mission(name), &bases, &map(), 0.6, None, &[]).unwrap();
            assert!(b.taxi.len() >= 2 && b.taxi.last() == b.route.first(), "{name}");
            let inside = |p: &[f64; 2]| p[0] >= 0.0 && p[1] >= 0.0 && p[0] <= b.size[0] && p[1] <= b.size[1];
            assert!(b.taxi.iter().all(inside) && b.parking.iter().all(inside), "{name}");
            assert_eq!(b.pins.iter().map(|p| p.place).collect::<Vec<_>>(), ["start", "hold", "lineup"], "{name}");
        }
        // A paragraph at a place the mission names wrong is an error.
        let mut m = mission("ramon_takeoff");
        m["briefing"]["how"][3]["at"] = json!("tower");
        assert!(briefing(&m, &bases, &map(), 0.6, None, &[]).is_err());
    }

    #[test]
    fn tiles_pick_the_view_level_and_coarser_ones_to_fill_in() {
        // A 4 × 4 km theatre of 1 km nodes (1 m pixels): level 2 whole, level 1 whole, level 0 only its north-west
        // node.
        let mut p = Pyramid {
            e0: 1000.0,
            n1: 9000.0,
            span0: 1000.0,
            px0: 1.0,
            root: 2,
            size: [4000.0, 4000.0],
            ..Default::default()
        };
        p.nodes.extend([(2, 0, 0), (1, 0, 0), (1, 1, 0), (1, 0, 1), (1, 1, 1), (0, 0, 0)]);
        // At 1 m a pixel over the north-west node: level 0, then 1 and 2 under it, coarse first.
        let t = p.tiles([1100.0, 8100.0, 1900.0, 8900.0], 1.0);
        assert_eq!(t.iter().map(|n| (n.0, n.1, n.2)).collect::<Vec<_>>(), [(2, 0, 0), (1, 0, 0), (0, 0, 0)]);
        assert_eq!(t[2].3, [1000.0, 8000.0, 2000.0, 9000.0]);
        // Over the south-east, where level 0 has no node: levels 1 and 2.
        let t = p.tiles([4100.0, 5100.0, 4900.0, 5900.0], 1.2);
        assert_eq!(t.iter().map(|n| (n.0, n.1, n.2)).collect::<Vec<_>>(), [(2, 0, 0), (1, 1, 1)]);
        // 3 m a pixel: level 1 and the root; past the root, the root alone.
        assert_eq!(p.tiles([1000.0, 5000.0, 5000.0, 9000.0], 3.0).len(), 5);
        assert_eq!(p.tiles([1000.0, 5000.0, 5000.0, 9000.0], 50.0).len(), 1);
        assert_eq!(p.local_box([0.0, 10_000.0]), [1000.0, 1000.0, 5000.0, 5000.0]);
    }

    #[test]
    fn layers_follow_the_view() {
        let (m, e) = (sim_bases::utm36n(34.8016, 30.6106), sim_bases::utm36n(34.9519, 29.5577));
        let origin = [m[0] - 10_000.0, m[1] + 10_000.0];
        // Around Eilat, far from the map's corner: Eilat in the map's metres; Mitzpe Ramon left out.
        let view = [
            e[0] - origin[0] - 5000.0,
            origin[1] - e[1] - 5000.0,
            e[0] - origin[0] + 5000.0,
            origin[1] - e[1] + 5000.0,
        ];
        let l = layers(&map(), None, &places(), view_box(view, origin), origin, 0.0).unwrap();
        assert_eq!(l.places.len(), 1);
        assert_eq!(l.places[0].1, "Eilat");
        assert!(
            (l.places[0].3[0] - (e[0] - origin[0])).abs() < 1e-6
                && (l.places[0].3[1] - (origin[1] - e[1])).abs() < 1e-6
        );
        // The whole of both: at a coarse scale the city stays and the town goes.
        let both = [-200_000.0, -200_000.0, 200_000.0, 200_000.0];
        let l = layers(&map(), None, &places(), view_box(both, origin), origin, TRUNK_FROM_M_PX).unwrap();
        assert_eq!(l.places.iter().map(|p| p.1.as_str()).collect::<Vec<_>>(), ["Eilat"]);
        assert_eq!(l.to_json()["places"][0]["kind"], "city");
    }
}
