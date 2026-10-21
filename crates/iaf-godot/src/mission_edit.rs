//! `IafMissionEdit`: the mission editor's edits and checks (`iaf_tools::mission_edit`, docs/mission-editor.md) for
//! `editor/mission_editor.gd`. Missions go in and come back as JSON strings (the converted mission file); a string
//! that does not parse is taken as an empty mission. Vectors are engine world metres (X east, Y north, z up).

use std::path::PathBuf;
use std::sync::{LazyLock, Mutex};

use godot::prelude::*;
use iaf_formats::terrain_types::TerrainTypes;
use iaf_tools::mission_edit as me;
use iaf_tools::mission_sanity as ms;
use iaf_tools::mission_year as my;
use serde_json::{Map, Value, json};

/// The assets directory and what `check` / `ground_height` read from it, loaded when first asked for.
#[derive(Default)]
pub(crate) struct Data {
    pub(crate) assets: PathBuf,
    pub(crate) heights: Option<me::Heights>,
    pub(crate) bdb: Option<Value>,
    pub(crate) types: Option<TerrainTypes>,
    loaded: bool,
}

pub(crate) static DATA: LazyLock<Mutex<Data>> = LazyLock::new(Default::default);

impl Data {
    pub(crate) fn load(&mut self) {
        if self.loaded {
            return;
        }
        self.loaded = true;
        let a = &self.assets;
        self.heights = me::Heights::open(&a.join("converted/terrain/theatre"));
        self.bdb = std::fs::read_to_string(a.join("converted/missions/default6_1.bdb.json"))
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok());
        self.types = std::fs::read(a.join("install/terraintype.dat")).ok().and_then(|d| TerrainTypes::parse(&d).ok());
    }
}

pub(crate) fn parse(s: &GString) -> Value {
    serde_json::from_str(&s.to_string()).unwrap_or_else(|_| json!({}))
}

pub(crate) fn text(v: &Value) -> GString {
    GString::from(serde_json::to_string(v).unwrap_or_default().as_str())
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafMissionEdit {}

#[godot_api]
impl IafMissionEdit {
    /// The assets directory (Settings.assets_dir()) that `check` and `ground_height` read from.
    #[func]
    fn set_assets(path: GString) {
        *DATA.lock().unwrap() = Data { assets: PathBuf::from(path.to_string()), ..Default::default() };
    }

    /// "" when `name` can be a mission name, else the reason.
    #[func]
    fn valid_name(name: GString) -> GString {
        GString::from(me::valid_name(&name.to_string()).err().unwrap_or_default().as_str())
    }

    #[func]
    fn stem(name: GString) -> GString {
        GString::from(me::stem(&name.to_string()).as_str())
    }

    #[func]
    fn free_name(base: GString, taken: PackedStringArray) -> GString {
        let taken: Vec<String> = taken.as_slice().iter().map(GString::to_string).collect();
        GString::from(me::free_name(&base.to_string(), &taken).as_str())
    }

    /// {"mission": the mission with the new entity, "id": its id}: `template` an entity (JSON) and `fields` (a
    /// JSON object) set on it.
    #[func]
    fn add_entity(mission: GString, template: GString, fields: GString) -> GString {
        let fields = parse(&fields).as_object().cloned().unwrap_or_else(Map::new);
        let (m, id) = me::add_entity(parse(&mission), &parse(&template), &fields);
        text(&json!({"mission": m, "id": id}))
    }

    #[func]
    fn remove_entity(mission: GString, id: i64) -> GString {
        text(&me::remove_entity(parse(&mission), id))
    }

    /// `points` world (x, y, z: 0 on the ground, a flyer's height above it); no `ids` leaves the mission unchanged.
    #[func]
    fn set_route(
        mission: GString,
        ids: PackedInt64Array,
        points: PackedVector3Array,
        speed_kmh: f64,
        hover_end: bool,
    ) -> GString {
        let pts: Vec<[f64; 3]> =
            points.as_slice().iter().map(|p| [f64::from(p.x), f64::from(p.y), f64::from(p.z)]).collect();
        text(&me::set_route(parse(&mission), ids.as_slice(), &pts, speed_kmh, hover_end))
    }

    #[func]
    fn clear_route(mission: GString, id: i64) -> GString {
        text(&me::clear_route(parse(&mission), id))
    }

    /// `spec` JSON {type (bdb object id), count (1..2), slot_x, slot_y, alt, heading, points? [[x, y, alt, speed]]}.
    #[func]
    fn set_flight(mission: GString, number: i64, spec: GString) -> GString {
        text(&me::set_flight(parse(&mission), number, &parse(&spec)))
    }

    #[func]
    fn remove_flight(mission: GString, number: i64) -> GString {
        text(&me::remove_flight(parse(&mission), number))
    }

    /// A red flight taking off from a base (mission_edit::set_red_flight): `spec` JSON {type, count, base (stem),
    /// name, template?, points?}.
    #[func]
    fn set_red_flight(mission: GString, spec: GString) -> GString {
        text(&me::set_red_flight(parse(&mission), &parse(&spec)))
    }

    /// A base mission with blue and red swapped.
    #[func]
    fn flip_base(base: GString) -> GString {
        text(&me::flip_base(parse(&base)))
    }

    /// The mission years: a JSON array of [value, label] (mission_year::years).
    #[func]
    fn years() -> GString {
        text(&json!(my::years()))
    }

    /// The original a new mission of `year` is built on (its TSD map and airbases).
    #[func]
    fn year_source(year: f64) -> i64 {
        my::source_for(year)
    }

    /// The year an original mission is set in.
    #[func]
    fn default_year(source: i64) -> f64 {
        my::default_year(source)
    }

    /// The bases `side` (1 blue, 2 red) owns in `year`: a JSON array of {stem, name, start: [x, y, z, heading]}.
    #[func]
    fn year_bases(year: f64, side: i64) -> GString {
        let b: Vec<Value> =
            my::bases(year, side).iter().map(|b| json!({"stem": b.stem, "name": b.name, "start": b.start})).collect();
        text(&json!(b))
    }

    /// The side that owns base `stem` in `year`: 1 blue, 2 red, 0 none.
    #[func]
    fn base_owner(stem: GString, year: f64) -> i64 {
        my::base(&stem.to_string()).map_or(0, |b| my::owner(b, year))
    }

    /// The jets (bdb object ids) `side` has in service in `year`; the never-served ones only with `what_if`.
    #[func]
    fn year_jets(year: f64, side: i64, what_if: bool) -> PackedInt64Array {
        PackedInt64Array::from(my::jets(year, side, what_if).as_slice())
    }

    /// The year check (warnings): a JSON array of {id, level, text}.
    #[func]
    fn year_issues(mission: GString, year: f64, what_if: bool) -> GString {
        text(&json!(
            my::year_issues(&parse(&mission), year, what_if).iter().map(me::Issue::to_json).collect::<Vec<_>>()
        ))
    }

    /// A mission from scratch on an original of the wanted era: only flight 1 (Alpha) stays (mission_edit::blank).
    #[func]
    fn blank(mission: GString) -> GString {
        text(&me::blank(parse(&mission)))
    }

    /// Role `role` (0 must survive, 1 target, 2 neutral) on the entities `ids`.
    #[func]
    fn set_role(mission: GString, ids: PackedInt64Array, role: i64) -> GString {
        text(&me::set_role(parse(&mission), ids.as_slice(), role))
    }

    /// What passes and fails the mission (mission_edit::conditions): JSON {targets, scripted, keep_alive, can_pass,
    /// passed_text, failed_text, summary}.
    #[func]
    fn conditions(mission: GString) -> GString {
        let mut d = DATA.lock().unwrap();
        d.load();
        text(&me::conditions(&parse(&mission), d.bdb.as_ref().unwrap_or(&Value::Null)))
    }

    /// The ground height (m) at world (x, y); null outside the terrain or without it.
    #[func]
    fn ground_height(x: f64, y: f64) -> Variant {
        let mut d = DATA.lock().unwrap();
        d.load();
        d.heights.as_mut().and_then(|h| h.ground_height(x, y)).map_or(Variant::nil(), |v| v.to_variant())
    }

    /// The Fly and ground check: a JSON array of {id, level ("error" / "warning"), text}; one error without the
    /// converted terrain or bdb.
    #[func]
    fn check(mission: GString) -> GString {
        let mut d = DATA.lock().unwrap();
        d.load();
        let Data { heights: Some(h), bdb: Some(bdb), types, .. } = &mut *d else {
            return text(&json!([{"id": -1, "level": "error", "text": "no converted terrain or bdb (run the setup)"}]));
        };
        let issues: Vec<Value> =
            me::check(&parse(&mission), bdb, h, types.as_ref()).iter().map(me::Issue::to_json).collect();
        text(&json!(issues))
    }

    // --- the sanity check, copy / paste, the year's map (docs/mission-editor.md §16, §17, §12) ---

    /// The sanity check (mission_sanity::sanity_issues): a JSON array of {id, level "warning", text}; none without
    /// the converted bdb.
    #[func]
    fn sanity(mission: GString) -> GString {
        let mut d = DATA.lock().unwrap();
        d.load();
        let Some(bdb) = &d.bdb else { return text(&json!([])) };
        let install = d.assets.join("install");
        text(&json!(
            ms::sanity_issues(&parse(&mission), bdb, &install).iter().map(me::Issue::to_json).collect::<Vec<_>>()
        ))
    }

    /// {"mission", "ids"}: copies of the JSON array `entities` moved by (dx, dy) m, new ids, a ground unit at the
    /// terrain's height (mission_edit::paste_group).
    #[func]
    fn paste_group(mission: GString, entities: GString, dx: f64, dy: f64) -> GString {
        let mut d = DATA.lock().unwrap();
        d.load();
        let ents = parse(&entities).as_array().cloned().unwrap_or_default();
        let Data { heights, bdb, .. } = &mut *d;
        let air = |e: &Value| {
            let o = bdb.as_ref().and_then(|b| {
                b["objects"]["items"]
                    .as_array()?
                    .iter()
                    .find(|o| o["0x1e"].as_i64() == e["0x2c6"].as_f64().map(|f| f as i64))
            });
            o.and_then(|o| o["0x5aa"].as_f64()).is_some_and(|c| [2.0, 3.0, 28.0].contains(&c))
        };
        let (m, ids) = me::paste_group(parse(&mission), &ents, dx, dy, |e, x, y| {
            if air(e) { None } else { heights.as_mut().and_then(|h| h.ground_height(x, y)) }
        });
        text(&json!({"mission": m, "ids": ids}))
    }

    /// Removes the formation at index `index` of formations.items (an enemy flight too) and its jets.
    #[func]
    fn remove_formation(mission: GString, index: i64) -> GString {
        text(&me::remove_formation(parse(&mission), usize::try_from(index).unwrap_or(usize::MAX)))
    }

    /// The source for `year` (mission_year::year_map_source): `source`, or the year's original when the year's TSD
    /// map differs.
    #[func]
    fn year_map_source(source: i64, year: f64) -> i64 {
        my::year_map_source(source, year)
    }

    /// The base missions whose side does not fit `year`: `bases` JSON [[name, side]]; a JSON array of issues.
    #[func]
    fn base_issues(bases: GString, year: f64) -> GString {
        let b: Vec<(String, i64)> = parse(&bases)
            .as_array()
            .into_iter()
            .flatten()
            .map(|x| (x[0].as_str().unwrap_or("").to_string(), x[1].as_f64().unwrap_or(0.0) as i64))
            .collect();
        text(&json!(my::base_issues(&b, year).iter().map(me::Issue::to_json).collect::<Vec<_>>()))
    }
}
