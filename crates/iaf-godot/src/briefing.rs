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

    /// The theatre's ground colour (`briefing::ground`) over `extent` [x0, y0, x1, y1] (UTM metres), `width` px
    /// wide: {w, h, rgb (RGB8)}, {} without the theatre.
    #[func]
    fn ground(theatre: GString, extent: PackedFloat64Array, width: i64) -> VarDictionary {
        let e = extent.as_slice();
        if e.len() != 4 {
            return VarDictionary::new();
        }
        match briefing::ground(Path::new(&theatre.to_string()), [e[0], e[1], e[2], e[3]], width.max(1) as u32) {
            Some((w, h, rgb)) => {
                let mut d = vdict! { "w" => w as i64, "h" => h as i64 };
                d.set("rgb", &PackedByteArray::from(rgb));
                d
            }
            None => VarDictionary::new(),
        }
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
