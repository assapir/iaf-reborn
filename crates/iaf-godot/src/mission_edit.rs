//! `IafMissionEdit`: the mission editor's edits and checks (`iaf_tools::mission_edit`, docs/mission-editor.md) for
//! `editor/mission_editor.gd`. Missions go in and come back as JSON strings (the converted mission file); a string
//! that does not parse is taken as an empty mission. Vectors are engine world metres (X east, Y north, z up).

use std::path::PathBuf;
use std::sync::{LazyLock, Mutex};

use godot::prelude::*;
use iaf_formats::terrain_types::TerrainTypes;
use iaf_tools::mission_edit as me;
use serde_json::{Map, Value, json};

/// The assets directory and what `check` / `ground_height` read from it, loaded when first asked for.
#[derive(Default)]
struct Data {
    assets: PathBuf,
    heights: Option<me::Heights>,
    bdb: Option<Value>,
    types: Option<TerrainTypes>,
    loaded: bool,
}

static DATA: LazyLock<Mutex<Data>> = LazyLock::new(Default::default);

impl Data {
    fn load(&mut self) {
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

fn parse(s: &GString) -> Value {
    serde_json::from_str(&s.to_string()).unwrap_or_else(|_| json!({}))
}

fn text(v: &Value) -> GString {
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
}
