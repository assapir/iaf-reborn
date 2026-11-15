//! `IafBriefing`: Modern IAF's mission briefing map (`iaf_tools::briefing`, modern-iaf/docs/front-end.md §10) for the
//! Pick a mission screen (`menu/briefing_map.gd` draws it).

use godot::prelude::*;
use iaf_tools::{briefing, loadout, sim_bases};
use serde_json::{Value, json};

use crate::world::text;
use std::path::Path;

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafBriefing {}

#[godot_api]
impl IafBriefing {
    /// The map of the readable mission file `mission` over the airbase files in `airbases`, the compiled TSD map
    /// `map` and the theatre's folder `theatre` (roads, towns; absolute paths), `aspect` = its width / height on
    /// screen, as JSON text (`Briefing::to_json`); `{"error": …}` when
    /// it cannot be made.
    #[func]
    fn map(mission: GString, airbases: GString, map: GString, theatre: GString, aspect: f64) -> GString {
        let p = |s: &GString| s.to_string();
        let out = match briefing::briefing_files(
            Path::new(&p(&mission)),
            Path::new(&p(&airbases)),
            Path::new(&p(&map)),
            Path::new(&p(&theatre)),
            aspect,
        ) {
            Ok(b) => b.to_json(),
            Err(e) => serde_json::json!({ "error": format!("{e:#}") }),
        };
        text(&out)
    }

    /// The grid heading (deg, 0..360) of runway end `designator` at base `base` (a mission's `start.base`) from the
    /// airbase files in `airbases` (`sim_bases::Runway::heading`, the briefing map's `heading`; the kneeboard's runway
    /// row asks it too); -1 without the base or the end.
    #[func]
    fn runway_heading(airbases: GString, base: GString, designator: GString) -> f64 {
        let Ok(bases) = sim_bases::load(Path::new(&airbases.to_string())) else { return -1.0 };
        let Some(b) = sim_bases::by_name(&bases, &base.to_string()) else { return -1.0 };
        b.end(&designator.to_string()).map_or(-1.0, |(ri, k)| b.runways[ri].heading(k).rem_euclid(360.0))
    }

    /// The map's layers over its view `view` [x0, y0, x1, y1] (the map's metres from its north-west corner `origin`,
    /// UTM metres [easting, northing]; the map's `extent`) at `m_per_px` metres a pixel (`briefing::layers_files`) from
    /// the compiled TSD map `map` and the theatre's folder `theatre` (absolute paths), as JSON text {fills, roads,
    /// places}; `{"error": …}` when it cannot be made.
    #[func]
    fn layers(
        map: GString,
        theatre: GString,
        view: PackedFloat64Array,
        origin: PackedFloat64Array,
        m_per_px: f64,
    ) -> GString {
        let (v, o) = (view.as_slice(), origin.as_slice());
        let out = if v.len() != 4 || o.len() != 2 {
            json!({ "error": "view [x0, y0, x1, y1] and origin [e, n] wanted" })
        } else {
            let (map, theatre) = (map.to_string(), theatre.to_string());
            let at = [v[0], v[1], v[2], v[3]];
            match briefing::layers_files(Path::new(&map), Path::new(&theatre), at, [o[0], o[1]], m_per_px) {
                Ok(l) => l.to_json(),
                Err(e) => json!({ "error": format!("{e:#}") }),
            }
        };
        text(&out)
    }

    /// The theatre's colour nodes that draw the view `view` (the map's metres from `origin`, as `layers`) at
    /// `m_per_px` metres a pixel (`briefing::Pyramid::tiles`), coarse to fine: [level, i, j, x0, y0, x1, y1] each, its
    /// box in the map's metres; empty without the theatre's `meta.json`.
    #[func]
    fn tiles(
        theatre: GString,
        view: PackedFloat64Array,
        origin: PackedFloat64Array,
        m_per_px: f64,
    ) -> PackedFloat64Array {
        let (v, o) = (view.as_slice(), origin.as_slice());
        let Some(p) = briefing::pyramid(Path::new(&theatre.to_string())).filter(|_| v.len() == 4 && o.len() == 2)
        else {
            return PackedFloat64Array::new();
        };
        let mut out = vec![];
        for (l, i, j, b) in p.tiles(briefing::view_box([v[0], v[1], v[2], v[3]], [o[0], o[1]]), m_per_px) {
            out.extend([f64::from(l), i as f64, j as f64, b[0] - o[0], o[1] - b[3], b[2] - o[0], o[1] - b[1]]);
        }
        PackedFloat64Array::from(out)
    }

    /// The Arming page of the unit record `unit` with the weapon records in `weapons` (absolute paths) and the loadout
    /// `lo` (JSON text, {"3": {"id": "mk-82", "count": 3}, …}; "" the record's default; `briefing::arming`) as JSON
    /// text, `{}` when the record is unreadable.
    #[func]
    fn arming(unit: GString, weapons: GString, lo: GString) -> GString {
        let v =
            read(&unit).map_or(json!({}), |u| briefing::arming(&u, Path::new(&weapons.to_string()), &given(&u, &lo)));
        text(&v)
    }

    /// The loadout `lo` with store `id` hung on `station` (and on its mirror with `pair`; `loadout::put`) as JSON
    /// text, "" when the station does not take it.
    #[func]
    fn put(unit: GString, lo: GString, station: i64, id: GString, pair: bool) -> GString {
        edit(&unit, &lo, |u, l| loadout::put(u, l, station as u32, &id.to_string(), pair))
    }

    /// The loadout `lo` with the store off `station` (and its mirror's with `pair`; `loadout::take`) as JSON text.
    #[func]
    fn take(unit: GString, lo: GString, station: i64, pair: bool) -> GString {
        edit(&unit, &lo, |u, l| {
            loadout::take(u, l, station as u32, pair);
            true
        })
    }

    /// The loadout `lo` with the rack on `station` one store fewer, from one back to full (the "×n" badge; with
    /// `pair` its mirror's along; `loadout::cycle`) as JSON text, "" when the station holds no rack.
    #[func]
    fn cycle(unit: GString, lo: GString, station: i64, pair: bool) -> GString {
        edit(&unit, &lo, |u, l| loadout::cycle(u, l, station as u32, pair))
    }

    /// The loadout `lo` with the store on `from` moved to `to` (`loadout::shift`) as JSON text, "" when `to` does not
    /// take it.
    #[func]
    fn shift(unit: GString, lo: GString, from: i64, to: i64, pair: bool) -> GString {
        edit(&unit, &lo, |u, l| loadout::shift(u, l, from as u32, to as u32, pair))
    }

    /// The loadout `lo` as the engine's pylons A..I hold it (`loadout::sim_load`): [[weapon number, count, rack kg, rack drag, internal] × 9] as
    /// JSON text, "" when the record is unreadable.
    #[func]
    fn sim_load(unit: GString, weapons: GString, lo: GString) -> GString {
        let v = read(&unit).map(|u| json!(loadout::sim_load(&u, Path::new(&weapons.to_string()), &given(&u, &lo))));
        v.as_ref().map_or_else(GString::new, text)
    }
}

fn read(unit: &GString) -> Option<Value> {
    serde_json::from_slice(&std::fs::read(unit.to_string()).ok()?).ok()
}

/// The loadout in `lo` (JSON text) as the record allows it; "" or not JSON: the record's default.
fn given(unit: &Value, lo: &GString) -> loadout::Loadout {
    match serde_json::from_str::<Value>(&lo.to_string()) {
        Ok(v) if v.is_object() => loadout::parse(unit, &v),
        _ => loadout::default(unit),
    }
}

fn edit(unit: &GString, lo: &GString, f: impl FnOnce(&Value, &mut loadout::Loadout) -> bool) -> GString {
    let Some(u) = read(unit) else { return GString::new() };
    let mut l = given(&u, lo);
    GString::from(if f(&u, &mut l) { loadout::to_json(&l).to_string() } else { String::new() }.as_str())
}
