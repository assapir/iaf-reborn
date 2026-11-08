//! Modern IAF's data compilers (`iaf-sim`, iaf-2026/docs/data-formats.md): the readable unit, weapon and mission files
//! under `iaf-2026/data/` compiled into the shapes the shared readers consume today, with no reader change:
//! - `db`: `db/units/*.json` and `db/weapons/*.json` → `converted/missions/sim.bdb.json` (the parts and hex keys of a
//!   converted `.bdb`, docs/formats/mis.md §4), its models under the key `"sim.bdb"` of
//!   `converted/objects/objects.json` (the scenery's fingerprint leaves that key out), and the weapons' motion in
//!   `converted/own/resource/weaponsmotion/weapons.ibx` (`[WEAPONnnn]` by type, the shape `weapon_db.gd` reads; the
//!   game reads it once A1's `install_dir()` switch points there);
//! - `missions`: `missions/*.json` → `converted/iaf-2026/missions/<id>.json` + `missionlist.json`, built with the
//!   mission editor's builders (`mission_edit`), `bdb: "sim.bdb"`;
//! - `own`: `sounds/soundprop.json` and its clips → `converted/own/resource/soundfiles/` (`soundprop.trx`, the
//!   columns `sound_table.gd` reads), `keys.json` → `converted/own/keys.json` (the shape `key_table.gd` reads).
//!
//! Nothing is read from the install or the exe: every figure comes from the data files, each with its source; every
//! clip from an open licence or our own tones (`iaf-2026/data/sounds/SOURCES.md`).

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail, ensure};
use serde_json::{Map, Value, json};

use crate::log;
use crate::mission_edit;
use crate::progress::{Progress, check};
use crate::sim_bases::{self, Base, Ground};
use crate::training;

pub use crate::sim_files::{BDB, BDB_FILE};
pub const OBJECTS_FILE: &str = "converted/objects/objects.json";
pub const IBX_FILE: &str = "converted/own/resource/weaponsmotion/weapons.ibx";
/// The sim's missions: their own folder, beside the original's `converted/missions` (whose readers and tests take
/// every file there as an original mission).
pub const MISSIONS_DIR: &str = "converted/iaf-2026/missions";
/// The sim's sound table and clips (the original's `resource/soundfiles` layout, docs/sound.md §1).
pub const SOUNDS_DIR: &str = "converted/own/resource/soundfiles";
/// The sim's key table (the shape of `iaf-convert keys`' `converted/keys.json`, read by `key_table.gd`).
pub const KEYS_FILE: &str = "converted/own/keys.json";
/// The same table with the laptop map's keys (`keys.json`'s `laptop` column; iaf-2026/docs/front-end.md §9.1).
pub const KEYS_LAPTOP_FILE: &str = "converted/own/keys_laptop.json";
/// The sim's aircraft descriptors (aircraft_model.gd through `Settings.planes_folder()`): `<plane>/aircraft.json` and the
/// index `aircraft.json`, under the assets root.
pub const PLANES_DIR: &str = "converted/own/planes";
/// The sim's F-16 model (the Barak's; the Sufa's f16i.glb has the same frames), from which `own` describes the F-16.
pub const F16_GLB: &str = "shared/extra/models/f16/f16d.glb";
/// The F-16's stations the sim's loadout hangs stores on (glTF metres on our model), each where its store's origin
/// goes: a store with no original model hangs by its own origin (player_weapons.gd `_pilon_of`). The model's own
/// helpers are the original's, which put the AIM-9 about a missile diameter above and outboard of our rails and the
/// tank's top inside the wing (iaf-2026/docs/data-formats.md §3, side and front views).
///   - 1 and 9 (StationA, StationI): under the launcher rails (x 4.62 to 4.795 m out, y −0.138 to 0.127 m, z 1.17 to
///     3.54 m in f16d.glb and f16i.glb), the AIM-9's axis one body radius (63.5 mm) below the rail, on its middle (the
///     hang under the rail inferred from the F-16's LAU-129);
///   - 2 and 8 (StationB, StationH), 3 and 7 (StationC, StationG): under the outboard and middle pylons (x ±3.97 and
///     ±2.98 m, bottoms y −0.322 and −0.392 m, z 1.89 to 3.10 and 0.71 to 3.12 m), the AIM-9's axis one body radius
///     below the pylon's bottom, on its middle (inferred, as at the rails);
///   - 4 and 6 (StationD, StationF): under the inboard pylons (x ±1.73 m, bottom y −0.341 m, z −0.18 to 2.23 m), the
///     370 US gal tank's top (0.328 m above its origin in stores/f16ftk.glb) on the pylon's bottom.
///
/// ponytail: one origin per station, right for the AIM-9 and the tank; a store of another shape there needs its own
/// hang offset.
const F16_SIM_STATIONS: [(&str, [f64; 3]); 8] = [
    ("StationA", [-4.7075, -0.2015, 2.35]),
    ("StationB", [-3.974, -0.3855, 2.496]),
    ("StationC", [-2.986, -0.4555, 1.912]),
    ("StationD", [-1.735, -0.669, 1.023]),
    ("StationF", [1.726, -0.669, 1.023]),
    ("StationG", [2.977, -0.4555, 1.912]),
    ("StationH", [3.965, -0.3855, 2.496]),
    ("StationI", [4.7115, -0.2015, 2.347]),
];

// --- The readable → hex mapping ------------------------------------------------------------------------------------

/// Every readable field the compilers write, by record: (record, readable name, hex key of the converted JSON,
/// docs/formats/mis.md).
pub const FIELDS: &[(&str, &str, &str)] = &[
    ("unit", "id", "0x514"),
    ("unit", "category", "0x51e"),
    ("unit", "label", "0x528"),
    ("unit", "brain", "0x532"),
    ("unit", "present", "0x53c"),
    ("unit", "radius_m", "0x564"),
    ("unit", "strength", "0x56e"),
    ("unit", "collider", "0x58c"),
    ("unit", "class", "0x5aa"),
    ("unit", "type", "0x5b4"),
    ("present", "name", "0x640"),
    ("present", "model", "0x64a"),
    ("present", "scale", "0x65e"),
    ("weapon", "name", "0x708"),
    ("weapon", "kind", "0x712"),
    ("weapon", "model", "0x730"),
    ("weapon", "drag", "0x73a"),
    ("weapon", "power", "0x744"),
    ("weapon", "blast_m", "0x74e"),
    ("weapon", "kg", "0x758"),
    ("weapon", "generation", "0x762"),
    ("weapon", "type", "0x780"),
    ("mission", "title", "0x44c"),
    ("mission", "time", "0x460"),
    ("mission", "wind_kt", "0x46a"),
    ("mission", "wind_from", "0x474"),
    ("mission", "win", "0x47e"),
    ("mission", "lose", "0x492"),
    ("mission", "category", "0x4d8"),
    ("entity", "name", "0x2bc"),
    ("entity", "unit", "0x2c6"),
    ("entity", "side", "0x2d0"),
    ("entity", "x", "0x2e4"),
    ("entity", "y", "0x2ee"),
    ("entity", "alt_m", "0x2f8"),
    ("entity", "heading", "0x302"),
];

/// The hex key of `record`'s readable `field` (FIELDS).
pub fn hex(record: &str, field: &str) -> &'static str {
    FIELDS.iter().find(|f| f.0 == record && f.1 == field).map(|f| f.2).unwrap_or_else(|| panic!("{record}.{field}"))
}

/// Unit classes: readable name → (bdb class 0x5aa, category 0x51e; docs/damage.md "By class").
const CLASSES: &[(&str, i64, &str)] = &[
    ("fighter", 0x1c, "Controlled aircraft"),
    ("radar_sam", 8, "Radar sam"),
    ("ir_sam", 9, "Infra red sam"),
    ("aaa", 10, "Gundish"),
    ("ground_radar", 11, "Ground radar"),
];
/// Weapon kinds: readable name → (sub type 0x780, kind 0x712, station: 9–11 for the gun / chaff / flare, -1 a pylon
/// store; weapons.ibx's OST_* enum, docs/weapons.md §1).
const KINDS: &[(&str, i64, &str, i64)] = &[
    ("gun", 565, "Gun bullet", 9),
    ("chaff", 540, "Chaff", 10),
    ("flare", 550, "Flare", 11),
    ("ir_missile", 570, "Heat missile", -1),
    ("bomb", 500, "Bomb", -1),
    ("radar_missile", 600, "Radar missile", -1),
    ("semi_radar_missile", 610, "Semi radar missile", -1),
    ("ir_sam", 620, "Heat sam", -1),
    ("radar_sam", 630, "Radar sam", -1),
    ("tank", 660, "Shell", -1),
];
const SIDES: &[(&str, i64)] = &[("blue", 1), ("red", 2)];
/// Pylon stations A..I are stations 0..8 (CArmament, docs/formats/mis.md "CArmament").
const PYLONS: &str = "ABCDEFGHI";
/// The Objects fields whose meaning is open (docs/formats/mis.md §4): every reader ignores them; written as the
/// format's usual values.
const OBJECT_REST: &[(&str, i64)] = &[
    ("0x546", 0),
    ("0x550", 0),
    ("0x55a", 0),
    ("0x578", 1),
    ("0x582", 1),
    ("0x596", 1),
    ("0x5a0", 1),
    ("0x5be", 1),
    ("0x5c8", 0),
    ("0x5cd", 0),
    ("0x5d2", 0),
    ("0x5d7", 0),
];
/// Optional figures a unit or weapon may hold for the threat set (iaf-2026/docs/threats.md §6); checked for their
/// sources, not compiled (no shared reader takes them yet).
const THREAT_FIGURES: &[&str] =
    &["range_km", "min_range_km", "ceiling_m", "floor_m", "speed_ms", "mach", "radar_km", "g_limit", "warhead_kg"];
/// The sub-folder of `db` that holds the drafts: records pending the user's decision, which `iaf-sim db` skips
/// (iaf-2026/docs/data-formats.md §11).
pub const DRAFTS: &str = "db/drafts";
const LB_PER_KG: f64 = 1.0 / 0.45359;

fn side(name: &str) -> Result<i64> {
    SIDES.iter().find(|t| t.0 == name).map(|t| t.1).with_context(|| format!("unknown side \"{name}\""))
}

// --- Reading the data -----------------------------------------------------------------------------------------------

/// A data file: its path (for messages) and its JSON.
pub struct File {
    pub name: String,
    pub v: Value,
}

/// Every `*.json` in `dir`, by file name.
pub fn read_dir(dir: &Path) -> Result<Vec<File>> {
    let mut out = vec![];
    if !dir.exists() {
        return Ok(out);
    }
    for e in std::fs::read_dir(dir).with_context(|| dir.display().to_string())? {
        let p = e?.path();
        if p.extension().is_some_and(|x| x == "json") {
            let text = std::fs::read_to_string(&p).with_context(|| p.display().to_string())?;
            let v = serde_json::from_str(&text).with_context(|| p.display().to_string())?;
            out.push(File { name: p.display().to_string(), v });
        }
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(out)
}

fn text<'a>(f: &'a File, k: &str) -> Result<&'a str> {
    f.v[k].as_str().with_context(|| format!("{}: \"{k}\" must be a string", f.name))
}

fn number(f: &File, k: &str) -> Result<f64> {
    f.v[k].as_f64().with_context(|| format!("{}: \"{k}\" must be a number", f.name))
}

fn int(f: &File, k: &str) -> Result<i64> {
    f.v[k].as_i64().with_context(|| format!("{}: \"{k}\" must be a whole number", f.name))
}

/// A figure the file holds: not null, not an empty list (a route with no points).
fn given(v: &Value) -> bool {
    !v.is_null() && v.as_array().is_none_or(|a| !a.is_empty())
}

/// Every figure named in `figures` that `f` holds (a dotted name reaches into an object: "motion._limitVel", or
/// "loadout.*" every key of one) has a source: a footnote of the file's `footnotes`, "inferred" or "open".
fn check_sources(f: &File, figures: &[&str]) -> Result<()> {
    let notes = f.v["footnotes"].as_object();
    let mut names = vec![];
    for fig in figures {
        match fig.split_once('.') {
            Some((obj, "*")) => {
                names.extend(f.v[obj].as_object().into_iter().flatten().map(|(k, _)| format!("{obj}.{k}")))
            }
            Some((obj, k)) if given(&f.v[obj][k]) => names.push(fig.to_string()),
            None if given(&f.v[*fig]) => names.push(fig.to_string()),
            _ => {}
        }
    }
    for n in names {
        let src = f.v["sources"][&n].as_str().with_context(|| format!("{}: \"{n}\" has no source", f.name))?;
        for s in src.split(',').map(str::trim) {
            let known = s == "inferred" || s == "open" || notes.is_some_and(|m| m.contains_key(s));
            ensure!(known, "{}: source \"{s}\" of \"{n}\" is not in \"footnotes\"", f.name);
        }
    }
    Ok(())
}

/// The units and weapons, each with its bdb number.
pub struct Db {
    pub units: Vec<File>,
    pub weapons: Vec<File>,
}

impl Db {
    pub fn read(data: &Path) -> Result<Self> {
        let db = Db { units: read_dir(&data.join("db/units"))?, weapons: read_dir(&data.join("db/weapons"))? };
        for (files, what) in [(&db.units, "unit"), (&db.weapons, "weapon")] {
            let (mut numbers, mut ids) = (HashSet::new(), HashSet::new());
            for f in files {
                // An approved draft drops its "status" as it moves out of db/drafts.
                ensure!(f.v.get("status").is_none(), "{}: a record with a \"status\" belongs in {DRAFTS}", f.name);
                let n = int(f, "number")?;
                ensure!((1..1000).contains(&n), "{}: number {n} is not 1..999", f.name);
                ensure!(numbers.insert(n), "{}: {what} number {n} is taken", f.name);
                ensure!(ids.insert(text(f, "id")?.to_string()), "{}: {what} id is taken", f.name);
            }
        }
        Ok(db)
    }

    /// The unit whose `id` is `id`.
    pub fn unit(&self, id: &str) -> Result<&File> {
        self.units.iter().find(|u| u.v["id"] == id).with_context(|| format!("no unit \"{id}\""))
    }

    fn weapon(&self, id: &str) -> Result<&File> {
        self.weapons.iter().find(|w| w.v["id"] == id).with_context(|| format!("no weapon \"{id}\""))
    }
}

// --- db -------------------------------------------------------------------------------------------------------------

/// A part of the bdb: its rows, then the placeholder row every part ends with (0x14 = 1, "Add data here").
fn part(class: &str, item: &str, name_key: &str, mut rows: Vec<Value>) -> Value {
    let next = rows.iter().filter_map(|r| r["0x1e"].as_i64()).max().unwrap_or(0) + 1;
    rows.push(json!({"0x14": 1, "0x1e": next, name_key: "Add data here", "_class": item}));
    json!({"_class": class, "items": rows})
}

/// The compiled object database (`sim.bdb.json`), its models ({present id: model path}) and its `weapons.ibx` text.
pub fn compile_db(db: &Db) -> Result<(Value, Map<String, Value>, String)> {
    let (mut objects, mut present, mut weapons, mut models) = (vec![], vec![], vec![], Map::new());
    let mut add_present = |id: i64, name: &str, model: &str, scale: f64| {
        present.push(json!({
            "0x14": 0, "0x1e": id, hex("present", "name"): name, hex("present", "model"): model, "0x654": 0,
            hex("present", "scale"): scale, "_class": "CDMEPresentItem",
        }));
        if !model.is_empty() {
            models.insert(id.to_string(), json!(model));
        }
    };
    for w in &db.weapons {
        check_sources(w, &["kg", "power", "blast_m", "drag", "motion.*"])?;
        check_sources(w, THREAT_FIGURES)?;
        let (kind, n) = (text(w, "kind")?, int(w, "number")?);
        let (sub, kind_name, station) = KINDS
            .iter()
            .find(|k| k.0 == kind)
            .map(|k| (k.1, k.2, k.3))
            .with_context(|| format!("{}: unknown kind \"{kind}\"", w.name))?;
        // A pylon store's weight loads the jet (the gun's rounds, chaff and flare weigh nothing here).
        ensure!(station >= 0 || number(w, "kg")? > 0.0, "{}: a pylon store needs its weight (\"kg\" > 0)", w.name);
        let model = w.v["model"].as_str().unwrap_or("");
        // A weapon's Present record follows the units' (ids 1000 + number).
        let pid = if model.is_empty() { 0 } else { 1000 + n };
        if pid > 0 {
            add_present(pid, text(w, "id")?, model, 1.0);
        }
        weapons.push(json!({
            "0x14": 0, "0x1e": n, hex("weapon", "name"): text(w, "name")?, hex("weapon", "kind"): kind_name,
            "0x71c": "", "0x726": "", hex("weapon", "model"): pid, hex("weapon", "drag"): number(w, "drag")?,
            hex("weapon", "power"): number(w, "power")?, hex("weapon", "blast_m"): number(w, "blast_m")?,
            hex("weapon", "kg"): (number(w, "kg")? * LB_PER_KG).round(),
            hex("weapon", "generation"): int(w, "generation")? as f64, "0x76c": 4, "0x776": "N.A",
            hex("weapon", "type"): sub, "_class": "CDMEWeaponsItem",
        }));
    }
    for u in &db.units {
        check_sources(u, &["type", "scale", "radius_m", "strength", "loadout.*"])?;
        check_sources(u, THREAT_FIGURES)?;
        let n = int(u, "number")?;
        let (class, category) = CLASSES
            .iter()
            .find(|c| c.0 == text(u, "class").unwrap_or(""))
            .map(|c| (c.1, c.2))
            .with_context(|| format!("{}: unknown class {}", u.name, u.v["class"]))?;
        add_present(n, text(u, "id")?, u.v["model"].as_str().unwrap_or(""), number(u, "scale")?);
        let mut hard = vec![0i64; 24];
        for (wid, count) in u.v["loadout"].as_object().into_iter().flatten() {
            let w = db.weapon(wid).with_context(|| u.name.clone())?;
            let station = KINDS.iter().find(|k| w.v["kind"] == k.0).map_or(-1, |k| k.3);
            ensure!(station >= 9, "{}: {wid} is a pylon store: give it under \"pylons\"", u.name);
            hard[2 * station as usize] = int(w, "number")?;
            hard[2 * station as usize + 1] = count.as_i64().with_context(|| format!("{}: loadout.{wid}", u.name))?;
        }
        // A flyable jet's gun rounds are the record's (loadout.<gun>): the sim's gun counts them down to empty, so a
        // jet without a count is refused rather than flying with no gun or an endless one.
        ensure!(
            u.v["airframe"].is_null() || hard[2 * 9 + 1] > 0,
            "{}: a flyable jet needs its gun rounds (\"loadout\": {{\"<gun id>\": rounds}})",
            u.name
        );
        for (st, p) in u.v["pylons"].as_object().into_iter().flatten() {
            let i = PYLONS.find(st.as_str()).filter(|_| st.len() == 1);
            let i = i.with_context(|| format!("{}: pylon \"{st}\" is not A..I", u.name))?;
            let w = db.weapon(p["weapon"].as_str().unwrap_or("")).with_context(|| u.name.clone())?;
            hard[2 * i] = int(w, "number")?;
            hard[2 * i + 1] = p["count"].as_i64().unwrap_or(1);
        }
        let mut o = Map::new();
        for (k, v) in [
            (hex("unit", "id"), json!(text(u, "id")?)),
            (hex("unit", "category"), json!(category)),
            (hex("unit", "label"), json!(text(u, "label")?)),
            (hex("unit", "brain"), json!(u.v["brain"].as_str().unwrap_or(""))),
            (hex("unit", "present"), json!(n)),
            (hex("unit", "radius_m"), json!(number(u, "radius_m")?)),
            (hex("unit", "strength"), json!(number(u, "strength")?)),
            (hex("unit", "collider"), json!(i64::from(u.v["collider"].as_bool().unwrap_or(true)))),
            (hex("unit", "class"), json!(class)),
            (hex("unit", "type"), json!(int(u, "type")?)),
        ] {
            o.insert(k.into(), v);
        }
        for (k, v) in OBJECT_REST {
            o.insert((*k).into(), json!(v));
        }
        o.insert("0x14".into(), json!(0));
        o.insert("0x1e".into(), json!(n));
        o.insert("_class".into(), json!("CDMEObjectsItem"));
        o.insert("armament".into(), json!({"_class": "CArmament", "hardpoints": hard}));
        o.insert("loads".into(), json!({"_class": "CObArray", "items": []}));
        // Ours, unhexed (as "weather" in a mission): the aircraft definition the unit flies as. The Sufa and the Barak
        // share type 100, which `airframe::id_for` resolves by the F-16 switch alone; the sim's settings (item A1)
        // set that switch from this key.
        if let Some(a) = u.v["airframe"].as_str() {
            ensure!(iaf_flight::airframe::get(a).is_some(), "{}: no aircraft definition \"{a}\"", u.name);
            o.insert("airframe".into(), json!(a));
        }
        // Ours, unhexed: the unit's sensor reach, which combat.gd `sensor_nm` takes before the type code's table.
        if let Some(km) = u.v["radar_km"].as_f64() {
            o.insert("radar_km".into(), json!(km));
        }
        objects.push(Value::Object(o));
    }
    let bdb = json!({
        "_file": BDB,
        "actions": part("CDMEActionPart", "CDMEActionItem", "0x64", vec![]),
        "audio": part("CDMEAudioPart", "CDMEAudioItem", "0x12c", vec![]),
        "brains": part("CDMEBrainPart", "CDMEBrainItem", "0x1f4", vec![]),
        "objects": part("CDMEObjectsPart", "CDMEObjectsItem", "0x514", objects),
        "present": part("CDMEPresentPart", "CDMEPresentItem", "0x640", present),
        "weapons": part("CDMEWeaponsPart", "CDMEWeaponsItem", "0x708", weapons),
    });
    Ok((bdb, models, ibx(db)?))
}

/// `weapons.ibx`: one `[WEAPONnnn]` section per weapon, `type` = generation · 1000 + sub type, then its motion; the
/// first weapon of each sub type also as the sub type's default section (generation 0: `weapon_db.gd motion_for`).
fn ibx(db: &Db) -> Result<String> {
    let mut out = String::from("; Modern IAF's weapon motion, compiled by iaf-sim db from iaf-2026/data/db/weapons.\n");
    let mut sections: BTreeMap<i64, (&str, &Map<String, Value>)> = BTreeMap::new();
    let mut defaults = BTreeMap::new();
    for w in &db.weapons {
        let sub = KINDS.iter().find(|k| w.v["kind"] == k.0).map(|k| k.1).unwrap_or(0);
        let motion = w.v["motion"].as_object().with_context(|| format!("{}: \"motion\" must be an object", w.name))?;
        let name = text(w, "name")?;
        let code = int(w, "generation")? * 1000 + sub;
        ensure!(sections.insert(code, (name, motion)).is_none(), "{}: a second weapon of type {code}", w.name);
        defaults.entry(sub).or_insert((name, motion));
    }
    // A type with no generation-0 weapon of its own takes its first weapon's as its default.
    for (sub, d) in defaults {
        sections.entry(sub).or_insert(d);
    }
    for (i, (code, (name, motion))) in sections.iter().enumerate() {
        out += &format!("\n; {name}\n[WEAPON{i:03}]\n\ttype = {code:06}\n");
        for (k, v) in *motion {
            let v = v.as_f64().with_context(|| format!("{name}: motion.{k} must be a number"))?;
            out += &format!("\t{k} = {v:?}\n");
        }
    }
    Ok(out)
}

/// `iaf-sim db`: compiles `<data>/db` into `<assets>/converted/…` (BDB_FILE, OBJECTS_FILE's "sim.bdb" key, IBX_FILE).
pub fn db(data: &Path, assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    check(cancel)?;
    let d = Db::read(data)?;
    let (bdb, models, ibx) = compile_db(&d)?;
    write(&assets.join(BDB_FILE), &serde_json::to_string(&bdb)?)?;
    // objects.json belongs to `iaf-convert objects` too: only the "sim.bdb" key is ours. A missing file starts
    // empty; any other read error stops (never rewrite a file that could not be read).
    let objects = assets.join(OBJECTS_FILE);
    let mut index: Map<String, Value> = match std::fs::read_to_string(&objects) {
        Ok(t) => serde_json::from_str(&t).with_context(|| objects.display().to_string())?,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Map::new(),
        Err(e) => return Err(e).with_context(|| objects.display().to_string()),
    };
    index.insert(BDB.into(), Value::Object(models));
    write(&objects, &serde_json::to_string_pretty(&index)?)?;
    write(&assets.join(IBX_FILE), &ibx)?;
    log!(pr, "db: {} units, {} weapons -> {}", d.units.len(), d.weapons.len(), assets.join(BDB_FILE).display());
    Ok(())
}

fn write(path: &Path, text: &str) -> Result<()> {
    std::fs::create_dir_all(path.parent().context("no folder")?)?;
    std::fs::write(path, text).with_context(|| path.display().to_string())
}

// --- missions -------------------------------------------------------------------------------------------------------

/// The empty mission every compiled one starts from: the seven parts (docs/formats/mis.md §2), each with only its
/// placeholder row, the header row of misc, and the bdb.
pub fn skeleton() -> Value {
    let slot = json!({"0x334": "", "0x33e": 0, "0x348": 0, "0x352": 0});
    let entity = json!({
        "0x14": 1, "0x1e": 1, "0x2bc": "Add data here", "0x2c6": -1, "0x2d0": 1, "0x2da": -1, "0x2e4": -1,
        "0x2ee": -1, "0x2f8": 0, "0x302": 0, "0x30c": 0, "0x316": "", "0x320": 0, "0x32a": 2, "0x35c": 0, "0xac": -1,
        "_class": "CDMEEntitiesItem", "armament": {"_class": "CArmament", "hardpoints": vec![0; 24]},
        "scripts0": {"_class": "CObArray", "items": []}, "scripts1": {"_class": "CObArray", "items": []},
        "slots": vec![slot; 7],
    });
    let misc = |real: bool| {
        json!({
            "0x14": i64::from(!real), "0x1e": if real { 1 } else { 2 }, "0x44c": if real { "" } else { "Add data here" },
            "0x456": "", "0x460": 0.0, "0x46a": 0, "0x474": 0, "0x47e": "", "0x488": "", "0x492": "", "0x49c": "",
            "0x4a6": "", "0x4b0": "", "0x4ba": -1, "0x4c4": -1, "0x4ce": -1, "0x4d8": "", "0x4e2": 0, "0x4ec": 0,
            "_class": "CDMEMiscItem",
        })
    };
    let cond = json!({"0x3b6": "", "0x3c0": "", "0x3ca": 0, "0x3d4": 0, "0x3de": -1});
    let one = |class: &str, row: Value| json!({"_class": class, "items": [row]});
    json!({
        "bdb": BDB, "version": 9,
        "misc": {"_class": "CDMEMiscPart", "items": [misc(true), misc(false)]},
        "timevars": one("CDMETimeVarsPart",
            json!({"0x14": 1, "0x1e": 1, "0x6a4": "Add data here", "0x6ae": 0.0, "_class": "CDMETimeVarsItem"})),
        "paths": one("CDMEPathsPart",
            json!({"0x14": 1, "0x1e": 1, "0x5dc": "Add data here", "0x5e6": "", "_class": "CDMEPathsItem", "points": []})),
        "entities": one("CDMEEntitiesPart", entity),
        "formations": one("CDMEFormationPart", json!({
            "0x14": 1, "0x1e": 1, "0x3e8": "Add data here", "0x3f2": 0, "0x3fc": 0, "0x406": 0,
            "_class": "CDMEFormationItem", "members": vec![json!({"0x410": "", "0x41a": -1, "0x424": -1}); 2], "names": [],
            "points": [],
        })),
        "debrief": one("CDMEDebriefPart",
            json!({"0x14": 1, "0x1e": 1, "0x258": "Add data here", "0x262": 1, "0x26c": "", "_class": "CDMEDebriefItem"})),
        "events": one("CDMEEventPart", json!({
            "0x14": 1, "0x1e": 1, "0x384": "Add data here", "0x38e": -1, "0x398": 1, "0x3a2": "", "0x3ac": -1,
            "_class": "CDMEEventItem", "conds": vec![cond; 3], "list": [],
        })),
    })
}

/// A point of a mission file in the sim's frame: UTM 36N (x east, y north) from its "lat" / "lon"
/// (iaf-2026/docs/terrain.md §2).
pub(crate) fn place(p: &Value, what: &str) -> Result<[f64; 2]> {
    let (lat, lon) = (p["lat"].as_f64(), p["lon"].as_f64());
    let (Some(lat), Some(lon)) = (lat, lon) else { bail!("{what}: \"lat\" and \"lon\" must be numbers") };
    Ok(sim_bases::utm36n(lon, lat))
}

/// The lineup point of `base`'s runway end `number` ("25R"): (x, y, grid heading), LINEUP_IN_M past the declared
/// runway's start (iaf-2026/docs/airbases.md §4).
fn runway_start(base: &Base, number: &str) -> Result<[f64; 3]> {
    let (ri, k) = base.end(number).with_context(|| format!("{}: no runway end {number}", base.name_en))?;
    let r = &base.runways[ri];
    let [x, y] = r.lineup(k);
    Ok([x, y, r.heading(k)])
}

/// A flight's route with points; without one set_flight gives the flight its one point 20 km ahead.
fn has_route(r: &Value) -> bool {
    r.as_array().is_some_and(|a| !a.is_empty())
}

/// The figures of a mission file, of each of its flights and of each placed unit that need a source (§1 of
/// data-formats.md): a whole route is one figure.
const MISSION_FIGURES: [&str; 8] =
    ["time", "wind_kt", "wind_from", "start.lat", "start.lon", "start.heading", "start.elevation_m", "route"];
const FLIGHT_FIGURES: [&str; 5] = ["start.lat", "start.lon", "start.heading", "start.alt_m", "route"];
const PLACED_FIGURES: [&str; 6] = ["lat", "lon", "heading", "alt_m", "route", "speed_kmh"];

/// The texts of a mission file: `{"en": …, "he": …}`, both required.
fn texts(f: &File, k: &str) -> Result<Value> {
    for lang in ["en", "he"] {
        ensure!(f.v[k][lang].is_string(), "{}: \"{k}\" needs \"{lang}\"", f.name);
    }
    Ok(f.v[k].clone())
}

/// The mission card shown at a training mission's start (iaf-2026/docs/front-end.md §8): the readable mission's
/// own `card` ({"objective": {"en", "he"}, "keys": [record index of the sim's keys.json…]}), else its kind's. In the
/// objective, `{key:N}` stands for record N's key as bound (the game fills it in, "Cmd" on macOS) and `{runway}` for
/// the mission's runway.
fn card(f: &File) -> Result<Value> {
    if !f.v["card"].is_null() {
        texts(&File { name: f.name.clone(), v: f.v["card"].clone() }, "objective")?;
        let keys = f.v["card"]["keys"].as_array().filter(|k| k.iter().all(|i| i.as_u64().is_some_and(|i| i < 126)));
        ensure!(keys.is_some(), "{}: \"card.keys\" must list key records (0..125)", f.name);
        return Ok(f.v["card"].clone());
    }
    // Start engine 117, Call the tower 47, Mission card 118, the start-up checklist 119..124; the throttle 7 (idle), 16 / 15 (± 5 %), 12 (MIL); the
    // wheel brakes 22, the rudder (nose wheel) 37 / 38, the stick 24..27, the gear 20.
    Ok(match f.v["training"]["kind"].as_str() {
        Some("startup") => json!({
            "objective": {
                "en": "Run the start-up checklist on its card step by step, from {key:119}. The mission passes once the \
                       engine idles with the avionics up.",
                "he": "ביצוע רשימת ההתנעה שבכרטיס שלב אחר שלב, החל מ־{key:119}. המשימה עוברת כשהמנוע בסרק והאוויוניקה פועלת.",
            },
            "keys": [119, 120, 121, 122, 123, 124, 118],
        }),
        Some("takeoff") => json!({
            "objective": {
                "en": "Call the tower with {key:47} and pick 1, 2, 3 in turn: start-up, taxi, take-off. Start the \
                       engine with {key:117}, taxi to runway {runway}, line up and take off on its heading; gear up.",
                "he": "קריאה למגדל: {key:47}, ואז 1, 2, 3 לפי הסדר: התנעה, הסעה, המראה. התנעת המנוע: \
                       {key:117}, הסעה למסלול {runway}, כניסה למסלול והמראה בכיוונו; איסוף כן הנסע.",
            },
            "keys": [47, 117, 7, 16, 15, 12, 22, 37, 38, 24, 25, 20, 118],
        }),
        _ => Value::Null,
    })
}

/// One compiled mission file from a readable one.
/// `bases`: the four airbases (sim_bases::load); `ground`: the theatre's height at a point, None without it (the
/// start's `elevation_m` then stands).
pub fn compile_mission(
    f: &File,
    db: &Db,
    bases: &[Base],
    ground: &mut dyn FnMut(f64, f64) -> Option<f64>,
) -> Result<Value> {
    check_sources(f, &MISSION_FIGURES)?;
    // The training rules (iaf-2026/docs/training.md): they parse, and each figure has its source.
    training::rules(&f.v).with_context(|| f.name.clone())?;
    check_sources(f, &training::FIGURES)?;
    // Each flight and placed unit names its own sources (the mission's footnotes serve them).
    for (list, figures) in
        [("flights", &FLIGHT_FIGURES[..]), ("targets", &PLACED_FIGURES), ("sam_sites", &PLACED_FIGURES)]
    {
        for (k, part) in f.v[list].as_array().into_iter().flatten().enumerate() {
            let mut v = part.clone();
            v["footnotes"] = f.v["footnotes"].clone();
            check_sources(&File { name: format!("{} {list}[{k}]", f.name), v }, figures)?;
        }
    }
    let id = text(f, "id")?;
    mission_edit::valid_name(id).map_err(|e| anyhow::anyhow!("{}: id: {e}", f.name))?;
    let mut m = mission_edit::blank(skeleton());
    let misc = &mut m["misc"]["items"][0];
    let time = text(f, "time")?;
    let (hh, mm) = time.split_once(':').with_context(|| format!("{}: time \"{time}\" is not HH:MM", f.name))?;
    misc[hex("mission", "title")] = f.v["title"]["en"].clone();
    misc[hex("mission", "time")] = json!(hh.parse::<f64>()? * 3600.0 + mm.parse::<f64>()? * 60.0);
    misc[hex("mission", "wind_kt")] = json!(f.v["wind_kt"].as_i64().unwrap_or(0));
    misc[hex("mission", "wind_from")] = json!(f.v["wind_from"].as_i64().unwrap_or(0));
    misc[hex("mission", "win")] = texts(f, "win")?["en"].clone();
    misc[hex("mission", "lose")] = texts(f, "lose")?["en"].clone();
    misc[hex("mission", "category")] = json!(f.v["category"].as_str().unwrap_or(""));
    // The player's flight (Alpha): the start, its unit and its route.
    let start = &f.v["start"];
    let unit = db.unit(start["unit"].as_str().unwrap_or("")).with_context(|| f.name.clone())?;
    let base_name = start["base"].as_str().with_context(|| format!("{}: start needs \"base\"", f.name))?;
    let base =
        sim_bases::by_name(bases, base_name).with_context(|| format!("{}: no airbase \"{base_name}\"", f.name))?;
    let [x, y, h] = match start["at"].as_str() {
        Some("runway") => runway_start(base, start["runway"].as_str().unwrap_or("")).with_context(|| f.name.clone())?,
        // A parking start without its own place takes the base's spot for its unit (data/airbases, §10).
        Some("parking") if start["lat"].is_null() => {
            let unit = start["unit"].as_str().unwrap_or("");
            let p = base.parking.iter().find(|p| p.unit == unit);
            let p = p.with_context(|| format!("{}: {} has no parking spot for {unit}", f.name, base.name_en))?;
            [p.at[0], p.at[1], p.heading]
        }
        Some("parking") => {
            let [x, y] = place(start, &f.name)?;
            let hdg = start["heading"].as_f64().with_context(|| format!("{}: parking needs \"heading\"", f.name))?;
            [
                x,
                y,
                sim_bases::grid_heading(
                    start["lon"].as_f64().unwrap_or(0.0),
                    start["lat"].as_f64().unwrap_or(0.0),
                    hdg,
                ),
            ]
        }
        _ => bail!("{}: start \"at\" must be \"parking\" or \"runway\"", f.name),
    };
    // The start's altitude: the theatre's ground there (as the game's height_at), else the field elevation given.
    let given = start["elevation_m"].as_f64().with_context(|| format!("{}: start needs \"elevation_m\"", f.name))?;
    let elev = ground(x, y).map_or(given, |g| (g * 10.0).round() / 10.0);
    // A waypoint's fourth value is its planned arrival time in sim seconds (docs/ai.md §7.2): its own "t_s", else the
    // time from the flight's start along the legs (3-D) at each point's "speed_kmh".
    let route = |r: &Value, from: [f64; 3]| -> Result<Vec<Value>> {
        let (mut out, mut at, mut t) = (vec![], from, 0.0);
        for p in r.as_array().into_iter().flatten() {
            let [px, py] = place(p, &f.name)?;
            let alt = p["alt_m"].as_f64().unwrap_or(1000.0);
            let leg = ((px - at[0]).powi(2) + (py - at[1]).powi(2) + (alt - at[2]).powi(2)).sqrt();
            t = match p["t_s"].as_f64() {
                Some(ts) => ts,
                None => {
                    let v = p["speed_kmh"].as_f64().filter(|v| *v > 0.0);
                    t + leg
                        / (v.with_context(|| format!("{}: a waypoint needs \"speed_kmh\" or \"t_s\"", f.name))? / 3.6)
                }
            };
            out.push(json!([px.round(), py.round(), alt, t.round(), 0]));
            at = [px, py, alt];
        }
        Ok(out)
    };
    let mut spec = json!({"type": int(unit, "number")?, "count": start["count"].as_i64().unwrap_or(1),
        "slot_x": x.round(), "slot_y": y.round(), "alt": elev, "heading": h.round()});
    if has_route(&f.v["route"]) {
        spec["points"] = json!(route(&f.v["route"], [x, y, elev])?);
    }
    m = mission_edit::set_flight(m, 1, &spec);
    // Only the player's jet (Alpha's leader, Player1) must survive; a wingman keeps the neutral role.
    let player = m["formations"]["items"][0]["members"][0]["0x41a"].as_i64().unwrap_or(-1);
    m = mission_edit::set_role(m, &[player], mission_edit::MUST_SURVIVE);
    // The other blue flights (Bravo..Delta).
    let flights = f.v["flights"].as_array().map_or(&[][..], Vec::as_slice);
    ensure!(flights.len() <= 3, "{}: {} flights besides Alpha; set_flight takes Bravo..Delta", f.name, flights.len());
    for (k, fl) in flights.iter().enumerate() {
        let u = db.unit(fl["unit"].as_str().unwrap_or("")).with_context(|| f.name.clone())?;
        let at = &fl["start"];
        let [fx, fy] = place(at, &f.name)?;
        let fh = sim_bases::grid_heading(
            at["lon"].as_f64().unwrap_or(0.0),
            at["lat"].as_f64().unwrap_or(0.0),
            at["heading"].as_f64().unwrap_or(0.0),
        );
        let mut spec = json!({"type": int(u, "number")?, "count": fl["count"].as_i64().unwrap_or(2),
            "slot_x": fx.round(), "slot_y": fy.round(), "alt": at["alt_m"].as_f64().unwrap_or(elev), "heading": fh.round()});
        if has_route(&fl["route"]) {
            spec["points"] = json!(route(&fl["route"], [fx, fy, at["alt_m"].as_f64().unwrap_or(elev)])?);
        }
        m = mission_edit::set_flight(m, k as i64 + 2, &spec);
    }
    // Targets (role 1) and SAM sites (red, neutral role), each optionally on a ground route.
    let template = skeleton()["entities"]["items"][0].clone();
    for (list, default_side, role) in [("targets", "red", mission_edit::TARGET), ("sam_sites", "red", 2)] {
        for (k, t) in f.v[list].as_array().into_iter().flatten().enumerate() {
            let u = db.unit(t["unit"].as_str().unwrap_or("")).with_context(|| f.name.clone())?;
            let [tx, ty] = place(t, &f.name)?;
            let mut fields = Map::new();
            for (key, v) in [
                (hex("entity", "name"), json!(t["name"].as_str().map_or(format!("{list} {}", k + 1), String::from))),
                (hex("entity", "unit"), json!(int(u, "number")?)),
                (hex("entity", "side"), json!(side(t["side"].as_str().unwrap_or(default_side))?)),
                (hex("entity", "x"), json!(tx.round())),
                (hex("entity", "y"), json!(ty.round())),
                (hex("entity", "alt_m"), json!(t["alt_m"].as_f64().unwrap_or(0.0))),
                (
                    hex("entity", "heading"),
                    json!(
                        sim_bases::grid_heading(
                            t["lon"].as_f64().unwrap_or(0.0),
                            t["lat"].as_f64().unwrap_or(0.0),
                            t["heading"].as_f64().unwrap_or(0.0)
                        )
                        .round()
                    ),
                ),
                ("0x14", json!(0)),
            ] {
                fields.insert(key.into(), v);
            }
            let (mm, eid) = mission_edit::add_entity(m, &template, &fields);
            m = mission_edit::set_role(mm, &[eid], role);
            if let Some(r) = t["route"].as_array().filter(|r| !r.is_empty()) {
                ensure!(r.len() >= 2, "{}: {list}[{k}]: a ground route needs at least two points", f.name);
                let pts: Vec<[f64; 3]> =
                    r.iter().map(|p| place(p, &f.name).map(|[a, b]| [a, b, 0.0])).collect::<Result<_>>()?;
                m = mission_edit::set_route(m, &[eid], &pts, t["speed_kmh"].as_f64().unwrap_or(30.0), true);
            }
        }
    }
    // Ours, only in the compiled JSON (as "weather" is): the texts in both languages for the sim's own screens.
    m["name"] = json!(id);
    // Placed at the real bases already: World scale Real's base move leaves the file as it is
    // (mission_runtime.gd move_with_bases).
    m["frame"] = json!("real");
    m["sim"] = json!({"title": texts(f, "title")?, "briefing": texts(f, "briefing")?, "win": f.v["win"],
        "lose": f.v["lose"], "menu_id": int(f, "menu_id")?, "runway": f.v["runway"], "training": f.v["training"],
        "base": base_name, "card": card(f)?});
    if let Some(note) = f.v["note"].as_str() {
        m["sim"]["note"] = json!(note);
    }
    Ok(m)
}

/// `iaf-sim missions`: compiles `<data>/missions` into `<assets>/MISSIONS_DIR` (`<id>.json` + `missionlist.json`:
/// menu id → [id]).
pub fn missions(data: &Path, assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let db = Db::read(data)?;
    let bases = sim_bases::load(&data.join("airbases"))?;
    let mut ground = Ground::open(&assets.join("converted/terrain/israel"));
    if ground.is_none() {
        pr.warn("missions: no theatre (iaf-sim terrain): the starts take the files' elevation_m");
    }
    let mut height = |x: f64, y: f64| ground.as_mut().and_then(|g| g.at(x, y));
    let out = assets.join(MISSIONS_DIR);
    let mut list = Map::new();
    let files = read_dir(&data.join("missions"))?;
    let mut ids = HashSet::new();
    for f in &files {
        check(cancel)?;
        ensure!(ids.insert(text(f, "id")?.to_lowercase()), "{}: mission id {} is taken", f.name, f.v["id"]);
        let m = compile_mission(f, &db, &bases, &mut height)?;
        if let Some(note) = m["sim"]["note"].as_str() {
            pr.warn(&format!("missions: {}: {note}", m["name"].as_str().unwrap_or("")));
        }
        let key = int(f, "menu_id")?.to_string();
        ensure!(!list.contains_key(&key), "{}: menu_id {key} is taken", f.name);
        list.insert(key, json!([m["name"]]));
        write(&out.join(format!("{}.json", text(f, "id")?)), &serde_json::to_string(&m)?)?;
    }
    write(&out.join("missionlist.json"), &serde_json::to_string_pretty(&list)?)?;
    log!(pr, "missions: {} -> {}", files.len(), out.display());
    Ok(())
}

// --- own: sounds and keys -------------------------------------------------------------------------------------------

/// The sound format the game's table plays (`AudioStreamWAV.load_from_file`): PCM WAV, 16-bit, mono, 22050 Hz.
const SOUND_RATE: u32 = 22050;

/// The length in seconds of a PCM 16-bit mono WAV at SOUND_RATE, or why it is not one.
pub fn wav_seconds(bytes: &[u8]) -> Result<f64> {
    ensure!(bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WAVE", "not a RIFF WAVE file");
    let (mut fmt, mut data, mut at) = (None, None, 12);
    while at + 8 <= bytes.len() {
        let len = u32::from_le_bytes(bytes[at + 4..at + 8].try_into()?) as usize;
        let body = bytes.get(at + 8..at + 8 + len).context("a chunk runs past the end")?;
        match &bytes[at..at + 4] {
            b"fmt " => fmt = Some(body),
            b"data" => data = Some(body),
            _ => {}
        }
        at += 8 + len + (len & 1);
    }
    let fmt = fmt.filter(|f| f.len() >= 16).context("no fmt chunk")?;
    let u16_at = |i: usize| u16::from_le_bytes([fmt[i], fmt[i + 1]]);
    let rate = u32::from_le_bytes(fmt[4..8].try_into()?);
    ensure!(u16_at(0) == 1 && u16_at(2) == 1 && u16_at(14) == 16, "not PCM 16-bit mono");
    ensure!(rate == SOUND_RATE, "{rate} Hz, not {SOUND_RATE}");
    let data = data.filter(|d| !d.is_empty()).context("no samples")?;
    Ok(data.len() as f64 / 2.0 / f64::from(rate))
}

/// The readable sound table (`sounds/soundprop.json`) as SoundProp.trx's tab-separated rows (docs/sound.md §1:
/// code, sub 1, sub 2, category, resident, cyclic, 3d, channel, # random files, inside / outside volume, 3d min / max
/// distance, file). `own` checks the clips.
pub fn compile_soundprop(table: &Value) -> Result<String> {
    let mut out = String::from("; Modern IAF's sound table, compiled by iaf-sim own from iaf-2026/data/sounds.\n");
    let (mut keys, rows) = (HashSet::new(), table["rows"].as_array().context("soundprop: no \"rows\"")?);
    for r in rows {
        let s = |k: &str| r[k].as_str().with_context(|| format!("soundprop {r}: \"{k}\" must be a string"));
        let n = |k: &str| r[k].as_f64().with_context(|| format!("soundprop {r}: \"{k}\" must be a number"));
        let yn = |k: &str| r[k].as_bool().map(|b| if b { "Y" } else { "N" }).context(format!("soundprop {r}: \"{k}\""));
        let (code, sub) = (s("code")?, r["sub"].as_str().unwrap_or("None"));
        ensure!(keys.insert(format!("{code}/{sub}")), "soundprop: {code} / {sub} twice");
        let category = match s("category")? {
            "engine" => "E",
            "effect" => "F",
            "speech" => "V",
            c => bail!("soundprop {code}: category \"{c}\" is not engine / effect / speech"),
        };
        let play = match s("play")? {
            "loop" => "C",
            "once" => "O",
            "periodic" => "T",
            p => bail!("soundprop {code}: play \"{p}\" is not loop / once / periodic"),
        };
        let file = s("file")?;
        let cols = [
            code.to_string(),
            sub.to_string(),
            "None".into(),
            category.into(),
            yn("resident")?.into(),
            play.into(),
            yn("3d")?.into(),
            (n("channel")? as i64).to_string(),
            "0".into(),
            n("volume_in")?.to_string(),
            n("volume_out")?.to_string(),
            format!("{:.1}", n("min_m")?),
            format!("{:.1}", n("max_m")?),
            file.into(),
        ];
        out += &(cols.join("\t") + "\n");
    }
    Ok(out)
}

/// DirectInput scancodes by our key names (the PC set-1 scancodes DirectInput uses; the names are ours): exactly the
/// keys `key_table.gd`'s `DIK_TO_KEY` can press (a test keeps the two in step).
const KEY_CODES: &[(&str, u32)] = &[
    ("Esc", 0x01),
    ("1", 0x02),
    ("2", 0x03),
    ("3", 0x04),
    ("4", 0x05),
    ("5", 0x06),
    ("6", 0x07),
    ("7", 0x08),
    ("8", 0x09),
    ("9", 0x0a),
    ("0", 0x0b),
    ("-", 0x0c),
    ("=", 0x0d),
    ("Backspace", 0x0e),
    ("Tab", 0x0f),
    ("Q", 0x10),
    ("W", 0x11),
    ("E", 0x12),
    ("R", 0x13),
    ("T", 0x14),
    ("Y", 0x15),
    ("U", 0x16),
    ("I", 0x17),
    ("O", 0x18),
    ("P", 0x19),
    ("[", 0x1a),
    ("]", 0x1b),
    ("Return", 0x1c),
    ("A", 0x1e),
    ("S", 0x1f),
    ("D", 0x20),
    ("F", 0x21),
    ("G", 0x22),
    ("H", 0x23),
    ("J", 0x24),
    ("K", 0x25),
    ("L", 0x26),
    (";", 0x27),
    ("'", 0x28),
    ("~", 0x29),
    ("\\", 0x2b),
    ("Z", 0x2c),
    ("X", 0x2d),
    ("C", 0x2e),
    ("V", 0x2f),
    ("B", 0x30),
    ("N", 0x31),
    ("M", 0x32),
    (",", 0x33),
    (".", 0x34),
    ("/", 0x35),
    ("Numpad *", 0x37),
    ("Space", 0x39),
    ("Caps Lock", 0x3a),
    ("F1", 0x3b),
    ("F2", 0x3c),
    ("F3", 0x3d),
    ("F4", 0x3e),
    ("F5", 0x3f),
    ("F6", 0x40),
    ("F7", 0x41),
    ("F8", 0x42),
    ("F9", 0x43),
    ("F10", 0x44),
    ("Num Lock", 0x45),
    ("Scroll Lock", 0x46),
    ("Numpad 7", 0x47),
    ("Numpad 8", 0x48),
    ("Numpad 9", 0x49),
    ("Numpad -", 0x4a),
    ("Numpad 4", 0x4b),
    ("Numpad 5", 0x4c),
    ("Numpad 6", 0x4d),
    ("Numpad +", 0x4e),
    ("Numpad 1", 0x4f),
    ("Numpad 2", 0x50),
    ("Numpad 3", 0x51),
    ("Numpad 0", 0x52),
    ("Decimal", 0x53),
    ("F11", 0x57),
    ("F12", 0x58),
    ("F13", 0x64),
    ("F14", 0x65),
    ("F15", 0x66),
    ("Numpad Enter", 0x9c),
    ("Numpad /", 0xb5),
    ("SysRQ", 0xb7),
    ("Home", 0xc7),
    ("Up", 0xc8),
    ("Page Up", 0xc9),
    ("Left", 0xcb),
    ("Right", 0xcd),
    ("End", 0xcf),
    ("Down", 0xd0),
    ("Page Down", 0xd1),
    ("Insert", 0xd2),
    ("Delete", 0xd3),
    ("Apps", 0xdd),
];

/// The modifier bits of a key (docs/controls.md §1) and the prefix the Controls page shows.
const MODIFIERS: &[(u32, &str)] = &[(0x11, "Ctrl + "), (0x22, "Shift + "), (0x44, "Alt + "), (0x88, "Win + ")];

/// The readable key table (`keys.json`: label {en, he}, key "Ctrl + Q", joystick, press, release, shown, group) in the
/// shape of `iaf-convert keys`' output (records with dik / modifiers / label / label_he, key_names, modifiers,
/// button_format), so `key_table.gd` reads it unchanged; `laptop`: a record's `laptop` key, when it has one, in place
/// of its `key`.
pub fn compile_keys(src: &Value, laptop: bool) -> Result<Value> {
    let (mut records, mut bound) = (vec![], HashSet::new());
    for (i, r) in src["records"].as_array().context("keys: no \"records\"")?.iter().enumerate() {
        ensure!(r["index"] == i, "keys: record {i} holds index {}", r["index"]);
        let col = if laptop && r.get("laptop").is_some() { "laptop" } else { "key" };
        let mut key = r[col].as_str().with_context(|| format!("keys {i}: \"{col}\" must be a string"))?;
        let mut modifiers = 0;
        if let Some(&(bits, prefix)) = MODIFIERS.iter().find(|m| key.starts_with(m.1)) {
            (modifiers, key) = (bits, &key[prefix.len()..]);
        }
        let dik = match key {
            "" => 0,
            k => {
                KEY_CODES.iter().find(|c| c.0 == k).map(|c| c.1).with_context(|| format!("keys {i}: no key \"{k}\""))?
            }
        };
        // An unlisted record may have no label: key_table.gd's "all keys" list leaves those out (records 115 / 116,
        // docs/controls.md §3).
        let shown = r["shown"].as_bool().with_context(|| format!("keys {i}: \"shown\""))?;
        let label = |l: &str| -> Result<Value> {
            let t = r["label"][l].as_str().filter(|t| !t.is_empty() || !shown);
            Ok(t.with_context(|| format!("keys {i}: no \"{l}\" label"))?.into())
        };
        let triple = |k: &str| -> Result<Value> {
            let a = r[k].as_array().filter(|a| a.len() == 3 && a.iter().all(Value::is_i64));
            Ok(a.with_context(|| format!("keys {i}: \"{k}\" must be three whole numbers"))?.clone().into())
        };
        let mut rec = json!({
            "index": i,
            "label": label("en")?,
            "label_he": label("he")?,
            "press": triple("press")?,
            "release": triple("release")?,
            "dik": dik,
            "modifiers": modifiers,
            "joystick": r["joystick"].as_i64().with_context(|| format!("keys {i}: \"joystick\""))?,
            "shown": shown,
        });
        // The Keys screen's part (iaf-2026/docs/front-end.md §9); a record without one is not listed there.
        if let Some(g) = r.get("group") {
            rec["group"] = g.as_str().with_context(|| format!("keys {i}: \"group\" must be a string"))?.into();
        }
        records.push(rec);
        ensure!(dik == 0 || bound.insert((dik, modifiers)), "keys {i}: \"{}\" is bound twice", r[col]);
    }
    let names: Map<String, Value> = KEY_CODES.iter().map(|&(n, c)| (c.to_string(), n.into())).collect();
    let modifiers: Vec<Value> =
        MODIFIERS.iter().map(|&(bits, prefix)| json!({"bits": bits, "prefix": prefix})).collect();
    Ok(json!({
        "source": "Modern IAF's own key table, compiled by iaf-sim own from iaf-2026/data/keys.json",
        "records": records,
        "key_names": names,
        "modifiers": modifiers,
        "button_format": "Button %d",
    }))
}

/// The radio's phrase files from `sounds/voices.json` (docs/radio.md §1, the shape `radio.gd` reads):
/// `phrasetemplates.trx` (`NAME token…`), `phraseparticalsdata.trx` (`KEY file text…`), `phraseparticles_he.trx`
/// (`KEY text_he`: the Hebrew subtitles), and the particles' files.
pub struct Radio {
    pub templates: String,
    pub particles: String,
    pub particles_he: String,
    pub files: Vec<String>,
}

/// Compiles the radio's files from `voices` (each particle needs its `text_he`).
pub fn compile_radio(voices: &Value) -> Result<Radio> {
    let head = "; Modern IAF's radio phrases, compiled by iaf-sim own from iaf-2026/data/sounds/voices.json.\n";
    let (mut templates, mut particles, mut files) = (head.to_string(), head.to_string(), vec![]);
    let mut particles_he = head.to_string();
    let parts = voices["particles"].as_object().context("voices: no \"particles\"")?;
    for (name, t) in voices["templates"].as_object().context("voices: no \"templates\"")? {
        let t = t.as_str().with_context(|| format!("voices: template {name} must be a string"))?;
        for tok in t.split_whitespace().filter(|t| !t.starts_with('%')) {
            ensure!(parts.contains_key(tok), "voices: template {name} names no particle \"{tok}\"");
        }
        templates += &format!("{name}\t{t}\n");
    }
    for (key, p) in parts {
        let file = p["file"].as_str().with_context(|| format!("voices: particle {key} has no file"))?;
        let text = p["text"].as_str().with_context(|| format!("voices: particle {key} has no text"))?;
        let he = p["text_he"].as_str().with_context(|| format!("voices: particle {key} has no text_he"))?;
        particles += &format!("{key}\t{file}\t{text}\n");
        particles_he += &format!("{key}\t{he}\n");
        files.push(file.to_string());
    }
    Ok(Radio { templates, particles, particles_he, files })
}

/// `iaf-sim own`: `<data>/sounds` → `<assets>/SOUNDS_DIR`: `soundprop.trx`, the radio's phrase files, and every clip
/// they name or the shared code opens by name (soundprop.json `by_name`), each checked once; any other file in that
/// folder is removed (`sound_table.gd` lists the whole folder). `<data>/keys.json` → `<assets>/KEYS_FILE` and, with its laptop column, `KEYS_LAPTOP_FILE`. Every
/// `<data>/planes/<jet>/cockpit/` → `<assets>/sim_cockpit::COCKPITS_DIR/<jet>/` (sim_cockpit.rs).
pub fn own(data: &Path, repo: &Path, assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    check(cancel)?;
    let read = |p: &Path| -> Result<Value> {
        serde_json::from_str(&std::fs::read_to_string(p).with_context(|| p.display().to_string())?)
            .with_context(|| p.display().to_string())
    };
    let (sounds, out) = (data.join("sounds"), assets.join(SOUNDS_DIR));
    let table = read(&sounds.join("soundprop.json"))?;
    let trx = compile_soundprop(&table)?;
    let radio = compile_radio(&read(&sounds.join("voices.json"))?)?;
    let names = |k: &str| table[k].as_array().into_iter().flatten().filter_map(|v| v.as_str().map(String::from));
    let rows = table["rows"].as_array().into_iter().flatten().filter_map(|r| r["file"].as_str().map(String::from));
    let files: BTreeSet<String> = rows.chain(names("by_name")).chain(radio.files.clone()).collect();
    std::fs::create_dir_all(&out).with_context(|| out.display().to_string())?;
    for f in &files {
        check(cancel)?;
        let src = sounds.join(f);
        let bytes = std::fs::read(&src).with_context(|| src.display().to_string())?;
        wav_seconds(&bytes).with_context(|| src.display().to_string())?;
        std::fs::write(out.join(f), bytes).with_context(|| out.join(f).display().to_string())?;
    }
    let trx_files = [
        ("soundprop.trx", &trx),
        ("phrasetemplates.trx", &radio.templates),
        ("phraseparticalsdata.trx", &radio.particles),
        ("phraseparticles_he.trx", &radio.particles_he),
    ];
    for (name, text) in trx_files {
        write(&out.join(name), text)?;
    }
    for e in std::fs::read_dir(&out)? {
        let name = e?.file_name().to_string_lossy().into_owned();
        if !files.contains(&name) && !trx_files.iter().any(|t| t.0 == name) {
            std::fs::remove_file(out.join(&name)).with_context(|| out.join(&name).display().to_string())?;
        }
    }
    let src = read(&data.join("keys.json"))?;
    let keys = compile_keys(&src, false)?;
    write(&assets.join(KEYS_FILE), &serde_json::to_string_pretty(&keys)?)?;
    write(&assets.join(KEYS_LAPTOP_FILE), &serde_json::to_string_pretty(&compile_keys(&src, true)?)?)?;
    planes(repo, assets)?;
    gun_art(assets)?;
    crate::sim_cockpit::cockpits(data, assets, pr, cancel)?;
    log!(
        pr,
        "own: {} sound rows, {} clips -> {}; keys -> {}",
        trx.lines().count() - 1,
        files.len(),
        out.display(),
        assets.join(KEYS_FILE).display()
    );
    Ok(())
}

/// The sim's effects art in the original's layout (`resource/3dobjects`, where the original keeps gunfire.tga).
pub const ART_DIR: &str = "converted/own/resource/3dobjects";

/// Our own gun art, drawn here from formulas (no source image): `gunfire.tga`, the muzzle flash on the original's two
/// crossed quads (player_weapons.gd `_muzzle_flash`: the top edge points forward, the muzzle at the centre), a flame
/// white-hot at the muzzle tapering forward to an orange tip; `tracer.tga`, a round's streak (`_tracer`: the top edge
/// is the head), a hot head fading to a red-orange tail. The alpha carries the shape (the flash's material adds by it,
/// the tracer's blends).
fn gun_art(assets: &Path) -> Result<()> {
    let hot = [1.0, 0.95, 0.75];
    let pixel = |c: [f32; 3], edge: [f32; 3], k: f32| {
        let k = k.clamp(0.0, 1.0);
        let mix = |i: usize| edge[i] + (c[i] - edge[i]) * k * k;
        image::Rgba([mix(0), mix(1), mix(2), k].map(|v| (v * 255.0).round() as u8))
    };
    // x across (−1..1), d along the gun line: 1 the flame's tip, 0 the muzzle, −1 behind it.
    let flash = image::RgbaImage::from_fn(64, 128, |x, y| {
        let (u, d) = ((x as f32 + 0.5) / 32.0 - 1.0, 1.0 - (y as f32 + 0.5) / 64.0);
        let w = if d >= 0.0 { 0.9 * (1.0 - d).powf(0.7) } else { 0.6 * (1.0 + 4.0 * d) };
        let k = if w > 0.0 { (1.0 - (u / w).powi(2)).max(0.0) * (1.0 - 0.6 * d.max(0.0)) } else { 0.0 };
        pixel(hot, [1.0, 0.45, 0.1], k)
    });
    // x across (−1..1), v along the streak: 0 the head, 1 the tail.
    let tracer = image::RgbaImage::from_fn(16, 128, |x, y| {
        let (u, v) = ((x as f32 + 0.5) / 8.0 - 1.0, (y as f32 + 0.5) / 128.0);
        let along = (v / 0.04).min(1.0) * (1.0 - v).powf(1.5);
        pixel(hot, [1.0, 0.35, 0.1], along * (-(u / 0.45).powi(2)).exp())
    });
    let dir = assets.join(ART_DIR);
    std::fs::create_dir_all(&dir).with_context(|| dir.display().to_string())?;
    for (name, img) in [("gunfire.tga", flash), ("tracer.tga", tracer)] {
        img.save(dir.join(name)).with_context(|| dir.join(name).display().to_string())?;
    }
    Ok(())
}

/// The F-16's descriptor from our model's frames ([`F16_GLB`] under the repo `repo`), never the original's
/// converted one: the parts' hinges, the stations, the gun and the nozzle (aircraft::describe_glb). `model` names the
/// original file the detailed-model tables key on (gltf.gd DETAILED, IafAirframe.model_for), which the sim always swaps.
fn planes(repo: &Path, assets: &Path) -> Result<()> {
    let glb = repo.join(F16_GLB);
    let bytes = std::fs::read(&glb).with_context(|| glb.display().to_string())?;
    let jet = crate::aircraft::DbObject {
        name: "f16".into(),
        class: "Controlled aircraft".into(),
        label: "F-16".into(),
        type_code: 100,
    };
    let mut d = crate::aircraft::describe_glb(&bytes, "f16", "f16_h.gltf", F16_GLB, &[jet])?;
    for (station, p) in F16_SIM_STATIONS {
        d["stations"][station] = json!(p);
    }
    let out = assets.join(PLANES_DIR);
    write(&out.join("f16/aircraft.json"), &serde_json::to_string(&d)?)?;
    let index = json!({"f16": {"model": "f16/f16_h.gltf", "descriptor": "f16/aircraft.json", "type": 100,
        "label": "F-16", "group": "controllableplanes"}});
    write(&out.join("aircraft.json"), &serde_json::to_string(&index)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::progress::Stdout;

    fn data() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../iaf-2026/data")
    }

    /// Every data file compiles, and the result loads as the game reads it: the bdb's references resolve (each
    /// entity's unit, each station's weapon, each weapon's motion section), the missions pass the editor's
    /// Win-and-lose reading, and weapons.ibx parses as `Settings.load_ibx` reads it (the ini parser).
    #[test]
    fn every_data_file_compiles_and_loads() {
        let dir = std::env::temp_dir().join(format!("iaf-sim-test-{}", std::process::id()));
        let cancel = AtomicBool::new(false);
        db(&data(), &dir, &Stdout, &cancel).unwrap();
        missions(&data(), &dir, &Stdout, &cancel).unwrap();
        let read = |p: &str| -> Value { serde_json::from_str(&std::fs::read_to_string(dir.join(p)).unwrap()).unwrap() };
        let bdb = read(BDB_FILE);
        assert_eq!(bdb["_file"], BDB);
        let rows = |part: &str| -> Vec<Value> { bdb[part]["items"].as_array().unwrap().clone() };
        let ids = |part: &str| -> HashSet<i64> { rows(part).iter().map(|r| r["0x1e"].as_i64().unwrap()).collect() };
        let (objects, weapons, present) = (ids("objects"), ids("weapons"), ids("present"));
        let ini = iaf_formats::ini::Ini::parse(&std::fs::read(dir.join(IBX_FILE)).unwrap());
        let types: HashSet<i64> = ini
            .sections
            .iter()
            .filter_map(|s| s.entries.iter().find(|e| e.0 == "type").and_then(|e| e.1.parse().ok()))
            .collect();
        for w in rows("weapons").iter().filter(|w| w["0x14"] == 0) {
            let t = w["0x780"].as_i64().unwrap();
            assert!(types.contains(&t), "{} has no motion section", w["0x708"]);
        }
        for o in rows("objects").iter().filter(|o| o["0x14"] == 0) {
            assert!(present.contains(&o["0x53c"].as_i64().unwrap()));
            for pair in o["armament"]["hardpoints"].as_array().unwrap().chunks(2) {
                let w = pair[0].as_i64().unwrap();
                assert!(w == 0 || weapons.contains(&w), "{}: weapon {w}", o["0x514"]);
            }
        }
        // The Sufa and the Barak (both type 100) tell their aircraft definitions apart.
        let airframe = |id: &str| rows("objects").iter().find(|o| o["0x514"] == id).unwrap()["airframe"].clone();
        assert_eq!((airframe("f16i"), airframe("f16d")), (json!("f16i"), json!("f16")));
        // The names the modern weapons base on (modern_weapons.gd RECORDS "base").
        let names: Vec<String> = rows("weapons").iter().map(|w| w["0x708"].as_str().unwrap().to_string()).collect();
        for n in ["AIM-9M", "MK-84", "20 MM"] {
            assert!(names.iter().any(|x| x == n), "{n}");
        }
        let list = read(&format!("{MISSIONS_DIR}/missionlist.json"));
        assert_eq!(list.as_object().unwrap().len(), read_dir(&data().join("missions")).unwrap().len());
        for files in list.as_object().unwrap().values() {
            let m = read(&format!("{MISSIONS_DIR}/{}.json", files[0].as_str().unwrap()));
            assert_eq!(m["bdb"], BDB);
            assert_eq!(m["frame"], "real");
            for e in mission_edit::spawned(&m) {
                assert!(objects.contains(&e["0x2c6"].as_i64().unwrap()), "{}: {}", m["name"], e["0x2bc"]);
            }
            // Waypoint "speed" = the planned arrival time (s): the take-off's point is over a minute out at 600 km/h.
            for p in m["formations"]["items"][0]["points"].as_array().unwrap() {
                assert!(p[4].as_f64().unwrap() > 60.0, "{}: {p}", m["name"]);
            }
            let c = mission_edit::conditions(&m, &bdb);
            assert_eq!(c["keep_alive"].as_array().unwrap().len(), 1, "{}: the player must survive", m["name"]);
        }
        std::fs::remove_dir_all(&dir).unwrap();
    }

    /// A mission file from Ramon's start-up with `extra` on top.
    fn ramon(extra: Value) -> File {
        let mut v: Value =
            serde_json::from_str(&std::fs::read_to_string(data().join("missions/ramon_startup.json")).unwrap())
                .unwrap();
        for (k, x) in extra.as_object().unwrap() {
            v[k] = x.clone();
        }
        File { name: "ramon".into(), v }
    }

    #[test]
    fn placed_units_take_the_grid_heading() {
        let (db, bases) = (Db::read(&data()).unwrap(), sim_bases::load(&data().join("airbases")).unwrap());
        let src = json!({"lat": "inferred", "lon": "inferred", "heading": "inferred"});
        let t = json!({"unit": "f16d", "name": "T", "lat": 30.9, "lon": 34.8, "heading": 90, "sources": src});
        let m = compile_mission(&ramon(json!({"targets": [t]})), &db, &bases, &mut |_, _| None).unwrap();
        let e = m["entities"]["items"].as_array().unwrap().iter().find(|e| e["0x2bc"] == "T").unwrap().clone();
        assert_eq!(e["0x302"].as_f64().unwrap(), sim_bases::grid_heading(34.8, 30.9, 90.0).round());
        assert_eq!(e["0x32a"], mission_edit::TARGET);
        assert_eq!(m["sim"]["base"], "Ramon", "the loading screen's base");
        // A ground route of one point is refused (set_route needs two).
        let mut one = t.clone();
        one["route"] = json!([{"lat": 30.9, "lon": 34.81}]);
        one["sources"]["route"] = json!("inferred");
        let e = compile_mission(&ramon(json!({"targets": [one]})), &db, &bases, &mut |_, _| None).unwrap_err();
        assert!(e.to_string().contains("at least two points"), "{e}");
        // Its figures need sources as the mission's do.
        let bare = json!({"unit": "f16d", "name": "T", "lat": 30.9, "lon": 34.8, "heading": 90});
        let e = compile_mission(&ramon(json!({"targets": [bare]})), &db, &bases, &mut |_, _| None).unwrap_err();
        assert!(e.to_string().contains("targets[0]: \"lat\" has no source"), "{e}");
    }

    #[test]
    fn only_the_players_jet_must_survive() {
        let (db, bases) = (Db::read(&data()).unwrap(), sim_bases::load(&data().join("airbases")).unwrap());
        let mut f = ramon(json!({}));
        f.v["start"]["count"] = json!(2);
        let m = compile_mission(&f, &db, &bases, &mut |_, _| None).unwrap();
        let c = mission_edit::conditions(&m, &Value::Null);
        assert_eq!(c["keep_alive"], json!([{"id": 1, "name": "Player1"}]), "{c}");
    }

    /// A flight without a route (none or empty) gets set_flight's default point, as Alpha does.
    #[test]
    fn a_flight_without_a_route_gets_the_default_point() {
        let (db, bases) = (Db::read(&data()).unwrap(), sim_bases::load(&data().join("airbases")).unwrap());
        let src = json!({"start.lat": "inferred", "start.lon": "inferred", "start.heading": "inferred"});
        let fl = |r: Value| {
            json!({"unit": "f16d", "start": {"lat": 30.9, "lon": 34.8, "heading": 0}, "route": r,
            "sources": src})
        };
        let f = ramon(json!({"flights": [fl(json!([])), fl(Value::Null)], "route": []}));
        let m = compile_mission(&f, &db, &bases, &mut |_, _| None).unwrap();
        for fm in m["formations"]["items"].as_array().unwrap().iter().filter(|f| f["0x14"] == 0) {
            assert_eq!(fm["points"].as_array().unwrap().len(), 1, "{}", fm["0x3e8"]);
        }
    }

    #[test]
    fn clashes_are_refused() {
        let (db, bases) = (Db::read(&data()).unwrap(), sim_bases::load(&data().join("airbases")).unwrap());
        let src = json!({"start.lat": "inferred", "start.lon": "inferred", "start.heading": "inferred"});
        let fl =
            json!({"unit": "f16d", "start": {"lat": 30.9, "lon": 34.8, "heading": 0}, "route": [], "sources": src});
        let m = compile_mission(&ramon(json!({"flights": [fl, fl, fl, fl]})), &db, &bases, &mut |_, _| None);
        assert!(m.unwrap_err().to_string().contains("4 flights"));
        let mut db = Db::read(&data()).unwrap();
        let twin = File { name: "twin".into(), v: db.weapon("aim-9m").unwrap().v.clone() };
        db.weapons.push(twin);
        assert!(ibx(&db).unwrap_err().to_string().contains("a second weapon of type 3570"));
        let root = db_copy("dup", |_| vec![]);
        let dir = &root.0;
        std::fs::create_dir_all(dir.join("missions")).unwrap();
        std::fs::create_dir_all(dir.join("airbases")).unwrap();
        for e in std::fs::read_dir(data().join("airbases")).unwrap() {
            let p = e.unwrap().path();
            std::fs::copy(&p, dir.join("airbases").join(p.file_name().unwrap())).unwrap();
        }
        let mut a = ramon(json!({})).v;
        std::fs::write(dir.join("missions/a.json"), a.to_string()).unwrap();
        a["menu_id"] = json!(9999);
        std::fs::write(dir.join("missions/b.json"), a.to_string()).unwrap();
        let e = missions(dir, &dir.join("out"), &Stdout, &AtomicBool::new(false)).unwrap_err();
        assert!(e.to_string().contains("is taken"), "{e}");
    }

    /// A temporary data root `iaf-sim-<name>-<pid>`, cleared first and removed when dropped: a copy of db/units and
    /// db/weapons, plus `extra(kind)` for each kind.
    fn db_copy(name: &str, extra: impl Fn(&str) -> Vec<File>) -> TempRoot {
        let root = TempRoot(std::env::temp_dir().join(format!("iaf-sim-{name}-{}", std::process::id())));
        let _ = std::fs::remove_dir_all(&root.0);
        for kind in ["units", "weapons"] {
            let out = root.0.join("db").join(kind);
            std::fs::create_dir_all(&out).unwrap();
            for f in read_dir(&data().join("db").join(kind)).unwrap().into_iter().chain(extra(kind)) {
                std::fs::write(out.join(Path::new(&f.name).file_name().unwrap()), f.v.to_string()).unwrap();
            }
        }
        root
    }

    /// The drafts (db/drafts, pending the user's decision) stay out of the compile, and each compiles cleanly once
    /// approved as data-formats.md §11 says (moved to db/units or db/weapons, its "status" line deleted): numbers,
    /// ids, classes, kinds, weights and every figure's source checked; each weapon finds its own weapons.ibx section
    /// as `weapon_db.gd motion_for` looks it up (generation · 1000 + type, read by the ini parser); a unit's
    /// `radar_km` reaches its Objects row; each SAM's launch zone from rest (combat.gd fires from the unit's pose at
    /// speed 0) is its published range. A moved draft that keeps its status is refused.
    #[test]
    fn drafts_are_skipped_and_compile_once_approved() {
        let live = Db::read(&data()).unwrap();
        let approved = |kind: &str| -> Vec<File> {
            let mut drafts = read_dir(&data().join(DRAFTS).join(kind)).unwrap();
            assert!(!drafts.is_empty(), "no {kind} drafts");
            for f in &mut drafts {
                let status = f.v.as_object_mut().unwrap().remove("status");
                assert_eq!(status, Some(json!("pending the user's decision")), "{}", f.name);
                assert!(f.v["notes"].get("status").is_none(), "{}: a status note outlives the approval", f.name);
                let id = f.v["id"].as_str().unwrap();
                assert!(live.unit(id).is_err() && live.weapon(id).is_err(), "{id} is compiled");
            }
            drafts
        };
        let root = db_copy("drafts", approved);
        let db = Db::read(&root.0).unwrap();
        let (bdb, _, ibx_text) = compile_db(&db).unwrap();
        // weapon_db.gd motion_for: the section of type generation · 1000 + type.
        let ini = iaf_formats::ini::Ini::parse(ibx_text.as_bytes());
        let section = |code: i64| {
            ini.sections.iter().find(|s| s.entries.iter().any(|e| e.0 == "type" && e.1.parse() == Ok(code)))
        };
        for w in &db.weapons {
            let sub = KINDS.iter().find(|k| w.v["kind"] == k.0).unwrap().1;
            let s = section(int(w, "generation").unwrap() * 1000 + sub).unwrap_or_else(|| panic!("{}", w.name));
            for (k, v) in w.v["motion"].as_object().unwrap() {
                let got = s.entries.iter().find(|e| &e.0 == k).map(|e| e.1.parse::<f64>().unwrap());
                assert_eq!(got, v.as_f64(), "{}: motion.{k}", w.name);
            }
        }
        let row = |id: &str| bdb["objects"]["items"].as_array().unwrap().iter().find(|o| o["0x514"] == id).cloned();
        assert_eq!(row("s300-tel").unwrap()["radar_km"], json!(200.0));
        assert!(row("f16i").unwrap().get("radar_km").is_none());
        // missile.rs dlz from a still launcher at a still target straight ahead (the "burn" key: the zone travelled).
        for w in db.weapons.iter().filter(|w| w.v["kind"] == "radar_sam" || w.v["kind"] == "ir_sam") {
            let (m, km) = (&w.v["motion"], number(w, "range_km").unwrap());
            let f = |k: &str| m[k].as_f64().unwrap_or_else(|| panic!("{}: motion.{k}", w.name));
            let motion = iaf_avionics::missile::ChaseMotion {
                accel: f("_absAcceleration"),
                beta: f("_spiralAccelBeta"),
                spiral: 1000.0,
                t_co: f("_timeConstOrientation"),
                burn: f("burn"),
                chase: iaf_avionics::missile::Chase::from_type(f("_chaseType") as i64),
                high_angle_turn: false,
                release_time: 0.0,
                release_accel: 0.0,
                real: true,
                off_boresight: false,
            };
            use iaf_avionics::{Vec3, missile};
            let site = missile::Launcher { pos: Vec3::ZERO, vel: Vec3::ZERO, fwd: Vec3::NORTH, up: Vec3::UP };
            let target = missile::Kinematics { pos: Vec3::new(0.0, km * 1e3, 0.0), vel: Vec3::ZERO };
            let zone = motion.dlz(&site, Some(&target)).max / 1e3;
            assert!((zone / km - 1.0).abs() < 0.02, "{}: zone {zone:.1} km against {km} km", w.name);
        }
        std::fs::copy(data().join(DRAFTS).join("units/tor-m1.json"), root.0.join("db/units/tor-m1.json")).unwrap();
        let e = Db::read(&root.0).err().unwrap();
        assert!(e.to_string().contains("status"), "{e}");
    }

    /// A pylon store without a weight is refused (the gun, chaff and flare weigh nothing in their record).
    #[test]
    fn a_pylon_store_needs_its_weight() {
        let mut db = Db::read(&data()).unwrap();
        db.weapons.iter_mut().find(|w| w.v["id"] == "mk-84").unwrap().v["kg"] = json!(0);
        assert!(compile_db(&db).unwrap_err().to_string().contains("weight"));
    }

    /// Each flyable jet's gun rounds are its record's (station 9's count in the bdb), and a jet without one is refused.
    #[test]
    fn a_flyable_jet_needs_its_gun_rounds() {
        let mut db = Db::read(&data()).unwrap();
        let (bdb, _, _) = compile_db(&db).unwrap();
        let rounds = |id: &str| {
            let rows = bdb["objects"]["items"].as_array().unwrap();
            let row = rows.iter().find(|r| r[hex("unit", "id")] == id).unwrap();
            row["armament"]["hardpoints"][19].as_i64().unwrap()
        };
        assert_eq!((rounds("f16i"), rounds("f16d"), rounds("f35i")), (511, 511, 180));
        db.units.iter_mut().find(|u| u.v["id"] == "f16i").unwrap().v["loadout"] = json!({"chaff": 60, "flare": 60});
        assert!(compile_db(&db).unwrap_err().to_string().contains("gun rounds"));
    }

    /// The original's converters (`iaf-convert aircraft` / `objects`) skip the sim's object database.
    #[test]
    fn the_converters_skip_the_sims_bdb() {
        let dir = std::env::temp_dir().join(format!("iaf-sim-bdbs-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("default6_1.bdb.json"), "{}").unwrap();
        std::fs::write(dir.join("sim.bdb.json"), "{}").unwrap();
        let names: Vec<String> = crate::aircraft::read_bdbs(&dir).unwrap().into_iter().map(|b| b.0).collect();
        assert_eq!(names, ["default6_1"]);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_runway_start_takes_the_end_its_number_names() {
        let bases = sim_bases::load(&data().join("airbases")).unwrap();
        let ramon = sim_bases::by_name(&bases, "Ramon").unwrap();
        // 07L/25R: 25R takes off toward the west-south-west, from the east end.
        let [x25, _, h] = runway_start(ramon, "25R").unwrap();
        assert!((h - 246.0).abs() < 3.0, "{h}");
        let [x07, _, h] = runway_start(ramon, "07L").unwrap();
        assert!((h - 66.0).abs() < 3.0, "{h}");
        assert!(x25 > x07 + 2000.0, "25R starts from the east end: {x25} vs {x07}");
        assert!(runway_start(ramon, "12").is_err());
    }

    /// A parking start without its own place stands on its base's spot for its unit, at the theatre's ground there.
    #[test]
    fn a_parking_start_takes_the_bases_spot() {
        let (db, bases) = (Db::read(&data()).unwrap(), sim_bases::load(&data().join("airbases")).unwrap());
        let mut f = ramon(json!({}));
        for k in ["lat", "lon", "heading"] {
            f.v["start"].as_object_mut().unwrap().remove(k);
        }
        let m = compile_mission(&f, &db, &bases, &mut |_, _| Some(643.27)).unwrap();
        let e = &m["entities"]["items"][0];
        let spot = &sim_bases::by_name(&bases, "Ramon").unwrap().parking[0];
        assert_eq!(
            (e["0x2e4"].as_f64().unwrap(), e["0x2ee"].as_f64().unwrap()),
            (spot.at[0].round(), spot.at[1].round())
        );
        assert_eq!(e["0x302"].as_f64().unwrap(), spot.heading.round());
        assert_eq!(e["0x2f8"].as_f64().unwrap(), 643.3, "the ground's height");
        f.v["start"]["unit"] = json!("f35i");
        assert!(
            compile_mission(&f, &db, &bases, &mut |_, _| None).unwrap_err().to_string().contains("no parking spot")
        );
    }

    /// The training rules are checked: a training figure without a source, an unknown kind and an unknown goal are
    /// refused, and every take-off mission's runway is an end of its base's airbase file.
    #[test]
    fn training_rules_are_checked() {
        let (db, bases) = (Db::read(&data()).unwrap(), sim_bases::load(&data().join("airbases")).unwrap());
        assert!(compile_mission(&ramon(json!({})), &db, &bases, &mut |_, _| None).is_ok());
        let mut unsourced = ramon(json!({}));
        unsourced.v["sources"].as_object_mut().unwrap().remove("training.time_budget_s");
        let e = compile_mission(&unsourced, &db, &bases, &mut |_, _| None).unwrap_err().to_string();
        assert!(e.contains("\"training.time_budget_s\" has no source"), "{e}");
        let unknown =
            ramon(json!({"training": {"kind": "landing", "time_budget_s": 60, "end_hold_s": 5, "goals": []}}));
        let e = compile_mission(&unknown, &db, &bases, &mut |_, _| None).unwrap_err();
        assert!(format!("{e:#}").contains("\"kind\""), "{e:#}");
        let goal =
            ramon(json!({"training": {"kind": "startup", "time_budget_s": 60, "end_hold_s": 5, "goals": ["fps"]}}));
        let e = compile_mission(&goal, &db, &bases, &mut |_, _| None).unwrap_err();
        assert!(format!("{e:#}").contains("\"fps\" is no debrief item"), "{e:#}");
        let airbases: Vec<Value> = read_dir(&data().join("airbases")).unwrap().into_iter().map(|f| f.v).collect();
        for f in read_dir(&data().join("missions")).unwrap() {
            if let Some(r) = f.v["runway"].as_str() {
                let base = training::airbase_of(&f.v, &airbases).unwrap();
                training::runway(base, r).unwrap_or_else(|e| panic!("{}: {e}", f.name));
            }
        }
    }

    #[test]
    fn every_training_mission_has_a_card() {
        let (db, bases) = (Db::read(&data()).unwrap(), sim_bases::load(&data().join("airbases")).unwrap());
        let m = compile_mission(&ramon(json!({})), &db, &bases, &mut |_, _| None).unwrap();
        let card = &m["sim"]["card"];
        assert!(card["objective"]["he"].as_str().unwrap().contains("{key:"), "{card}");
        assert!(!card["keys"].as_array().unwrap().is_empty());
        let own = json!({"card": {"objective": {"en": "Go", "he": "סע"}, "keys": [117]}});
        let m = compile_mission(&ramon(own), &db, &bases, &mut |_, _| None).unwrap();
        assert_eq!(m["sim"]["card"]["objective"]["en"], "Go");
        let bad = ramon(json!({"card": {"objective": {"en": "Go"}, "keys": [117]}}));
        assert!(compile_mission(&bad, &db, &bases, &mut |_, _| None).is_err(), "a card needs both languages");
        let bad = ramon(json!({"card": {"objective": {"en": "Go", "he": "סע"}, "keys": [500]}}));
        assert!(compile_mission(&bad, &db, &bases, &mut |_, _| None).is_err(), "a card's keys are records");
    }

    #[test]
    fn a_figure_without_a_source_is_refused() {
        let f = |v: Value| File { name: "t".into(), v };
        let ok = f(json!({"kg": 1, "sources": {"kg": "mk84"}, "footnotes": {"mk84": "x"}}));
        assert!(check_sources(&ok, &["kg"]).is_ok());
        assert!(check_sources(&f(json!({"kg": 1})), &["kg"]).is_err());
        assert!(check_sources(&f(json!({"kg": 1, "sources": {"kg": "nowhere"}})), &["kg"]).is_err());
        let star = f(json!({"motion": {"a": 1, "b": 2}, "sources": {"motion.a": "inferred"}}));
        assert!(check_sources(&star, &["motion.*"]).is_err());
    }

    #[test]
    fn every_hex_key_is_named_once() {
        let mut seen = HashSet::new();
        for (rec, name, key) in FIELDS {
            assert!(seen.insert((rec, name)) && key.starts_with("0x"), "{rec}.{name}");
        }
    }

    /// A temporary assets root, removed when dropped (also after a failed assert: the clips are ~3 MB).
    struct TempRoot(std::path::PathBuf);

    impl Drop for TempRoot {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    /// `iaf-sim own`: every sound row's clip exists and parses as the game's format, every code the shared flight
    /// code plays has a row, every file it opens by name is there, the radio's templates name only particles with a
    /// clip, a stale clip is removed, the key table compiles to the 126 records `key_table.gd` reads (the 117 of
    /// docs/controls.md, Start engine, Mission card, the six start-up checklist steps and Master arm), and the gun art
    /// is there.
    #[test]
    fn own_sounds_and_keys_compile() {
        let root = TempRoot(std::env::temp_dir().join(format!("iaf-sim-own-{}", std::process::id())));
        let sounds = root.0.join(SOUNDS_DIR);
        std::fs::create_dir_all(&sounds).unwrap();
        std::fs::write(sounds.join("stale.wav"), b"x").unwrap();
        own(&data(), &data().join("../.."), &root.0, &Stdout, &AtomicBool::new(false)).unwrap();
        assert!(!sounds.join("stale.wav").exists());
        // The F-16's descriptor from our model: its hinges, stations and gun, the type, no original source.
        let f16: Value =
            serde_json::from_slice(&std::fs::read(root.0.join(PLANES_DIR).join("f16/aircraft.json")).unwrap()).unwrap();
        assert_eq!(
            (f16["type"].as_i64(), f16["fm_section"].as_str(), f16["source"].as_str()),
            (Some(100), Some("F-16"), Some(F16_GLB))
        );
        assert!(
            f16["parts"]["LdgF"]["axis"].is_array() && f16["stations"]["StationE"].is_array() && f16["gun"].is_array()
        );
        assert_eq!(f16["engines"]["pairs"], 1);
        assert_eq!(f16["stations"]["StationA"], json!(F16_SIM_STATIONS[0].1));
        let clip = |f: &str| wav_seconds(&std::fs::read(sounds.join(f.to_lowercase())).unwrap()).unwrap();
        let trx = std::fs::read_to_string(sounds.join("soundprop.trx")).unwrap();
        let rows: Vec<Vec<&str>> =
            trx.lines().filter(|l| !l.starts_with(';')).map(|l| l.split('\t').collect()).collect();
        for r in &rows {
            assert_eq!(r.len(), 14, "{r:?}");
            assert!(clip(r[13]) > 0.05, "{}", r[13]);
        }
        // The codes iaf-reborn/ plays by code (flight_sounds.gd, player_weapons.gd, player_damage.gd, rwr.gd, combat.gd,
        // damage_model.gd); BTY_MISS, BTY_OVER_G and BTY_SPIN have no row on purpose (the F-16 VMS has no such voice).
        for key in [
            "SFX_LANDING/None",
            "SFX_START_ENGINE/None",
            "SFX_DRY_THRUST/None",
            "SFX_AFTERBURNER_THRUST/None",
            "SFX_BUTTON/None",
            "SFX_LANDING_GEAR/None",
            "SFX_FLAPS/None",
            "SFX_SPEED_BREAKES/None",
            "SFX_SPEED_BREAKES_LOOP/None",
            "SFX_AIRCRAFT_FIRED_WEAPON/OST_GUNBULLET",
            "SFX_ENTITY_FIRED_WEAPON/OST_GUNBULLET",
            "SFX_AIRCRAFT_FIRED_WEAPON/OST_RADARMISSILE",
            "SFX_AIRCRAFT_FIRED_WEAPON/OST_BOMB",
            "SFX_OBJECT_SPECIFIC/OST_HEATMISSILE",
            "SFX_OBJECT_SPECIFIC/OST_BOMB",
            "SFX_WEAPON_EXPLODED/OST_BOMB",
            "SFX_WEAPON_EXPLODED/OST_ROCKET",
            "SFX_WEAPON_EXPLODED/OST_GUNBULLET",
            "SFX_WEAPON_HIT_TARGET/None",
            "SFX_SPLASH/None",
            "SFX_AIRCRAFT_EXPLODED/None",
            "SFX_AIRCRAFT_DAMAGED/DAMAGED_ELECTRICITY",
            "SFX_AIRCRAFT_DAMAGED/DAMAGED_GUN_BULLETS",
            "SFX_AIRCRAFT_DAMAGED/DAMAGED_MISSILE_HIT",
            "SFX_IR_SEEK/None",
            "SFX_IR_LOCK/None",
            "SFX_WARNING/WRN_MASTER",
            "SFX_WARNING/WRN_NEW_GUY",
            "SFX_WARNING/WRN_MISSILE_LAUNCH",
            "SFX_WARNING/WRN_AOA",
            "SFX_TOUCHDOWN/None",
            "SFX_SCREECH/None",
            "SFX_FIRE_EXTINGUISHER/None",
            "VOC_BBETTY/BTY_ALT",
            "VOC_BBETTY/BTY_PULL_UP",
            "VOC_BBETTY/BTY_CAUTION",
            "VOC_BBETTY/BTY_FIRE",
            "VOC_BBETTY/BTY_ENGINE",
            "VOC_BBETTY/BTY_FUEL",
            "VOC_WINGMAN/WINGMAN_EJECT_EJECT",
            "VOC_TARGET_SAY_FRIENDLY_HIT/None",
            "VOC_WINGMAN_SAY_FRIENDLY_HIT/None",
            "VOC_TOWER_SAY_FRIENDLY_HIT/None",
        ] {
            assert!(rows.iter().any(|r| format!("{}/{}", r[0], r[1]) == key), "no row {key}");
        }
        // The files the shared code opens by name: g_effects.gd (cock_g_02; cock_bty_over is silent on purpose),
        // terrain_view.gd (EndWorld) and radio.gd (KCH2, its phrase files).
        for f in ["cock_g_02.wav", "EndWorld.wav", "KCH2.WAV"] {
            assert!(clip(f) > 0.05, "{f}");
        }
        let particles = std::fs::read_to_string(sounds.join("phraseparticalsdata.trx")).unwrap();
        let keys_of: HashSet<&str> = particles
            .lines()
            .filter(|l| !l.starts_with(';'))
            .map(|l| {
                let c: Vec<&str> = l.split('\t').collect();
                assert!(clip(c[1]) > 0.0, "{l}");
                c[0]
            })
            .collect();
        // The Hebrew subtitles: one line per particle, the tower's words in Hebrew.
        let he = std::fs::read_to_string(sounds.join("phraseparticles_he.trx")).unwrap();
        let he_keys: HashSet<&str> =
            he.lines().filter(|l| !l.starts_with(';')).map(|l| l.split('\t').next().unwrap()).collect();
        assert_eq!(he_keys, keys_of, "a Hebrew line per particle");
        assert!(he.contains("TAKEOFF\tאישור המראה"), "{he}");
        let templates = std::fs::read_to_string(sounds.join("phrasetemplates.trx")).unwrap();
        for t in [
            "ACFT_TAXI_TO_RUNWAY",
            "ACFT_CLEAR_TO_LINEUP",
            "ACFT_CLEAR_TO_LINEUP_NW",
            "ACFT_HOLD_POS",
            "ACFT_CLEAR_TO_TAKEOFF",
            "ACFT_ROGER",
        ] {
            assert!(templates.lines().any(|l| l.starts_with(&format!("{t}\t"))), "no template {t}");
        }
        // radio.gd's arguments: the callsign, greeting and wind keys, every runway number, the letters.
        let numbers: Vec<String> = (1..=36).map(|n| n.to_string()).collect();
        let args = ["ALPHA_T", "MORNING", "AFTERNOON", "EVENING", "WI_KNOTS10", "WI_KNOTS15", "WI_KNOTS20", "RWY_L"];
        for k in args.iter().copied().chain(["RWY_R", "RWY_C", ","]).chain(numbers.iter().map(String::as_str)) {
            assert!(keys_of.contains(k), "no particle {k}");
        }
        let keys: Value = serde_json::from_str(&std::fs::read_to_string(root.0.join(KEYS_FILE)).unwrap()).unwrap();
        let recs = keys["records"].as_array().unwrap();
        assert_eq!(recs.len(), 126);
        for r in recs {
            let labelled = r["label"].as_str().is_some_and(|l| !l.is_empty());
            assert!(labelled || r["shown"] == false, "{r}");
            let dik = r["dik"].as_u64().unwrap();
            assert!(dik == 0 || keys["key_names"][dik.to_string()].is_string(), "{r}");
        }
        // Records 115 / 116 stay out of the "all keys" list (no label), as in the original (docs/controls.md §3).
        assert_eq!((recs[115]["label"].as_str(), recs[116]["label"].as_str()), (Some(""), Some("")));
        // Our gun art (gun_art): the flash white-hot at the muzzle (the centre), clear at the corners; the tracer's head.
        let art = |f: &str| image::open(root.0.join(ART_DIR).join(f)).unwrap().to_rgba8();
        let (flash, tracer) = (art("gunfire.tga"), art("tracer.tga"));
        assert!(flash.get_pixel(32, 66)[3] > 200 && flash.get_pixel(0, 0)[3] == 0);
        assert!(tracer.get_pixel(8, 8)[3] > 200 && tracer.get_pixel(8, 127)[3] < 10);
        // Record 1 quits on Ctrl + Q (docs/controls.md §3).
        assert_eq!((recs[1]["dik"].as_u64(), recs[1]["modifiers"].as_u64()), (Some(0x10), Some(0x11)));
        // The laptop map: the rudder on Z / X (records 37 / 38), no numpad key (front-end.md §9.1).
        let lap: Value =
            serde_json::from_str(&std::fs::read_to_string(root.0.join(KEYS_LAPTOP_FILE)).unwrap()).unwrap();
        let lrecs = lap["records"].as_array().unwrap();
        assert_eq!((lrecs.len(), lrecs[37]["dik"].as_u64(), lrecs[38]["dik"].as_u64()), (126, Some(0x2c), Some(0x2d)));
        for r in lrecs {
            let dik = r["dik"].as_u64().unwrap();
            assert!(!matches!(dik, 0x37 | 0x47..=0x53 | 0x9c | 0xb5), "{r}");
        }
    }

    /// Two records on one key, or a shown record without a label, are refused.
    #[test]
    fn a_key_bound_twice_is_refused() {
        let rec = |i: usize, key: &str, en: &str, shown: bool| {
            json!({"index": i, "label": {"en": en, "he": en}, "key": key, "joystick": -1, "press": [1, 0, 0],
                "release": [0, 0, 0], "shown": shown})
        };
        assert!(
            compile_keys(&json!({"records": [rec(0, "Ctrl + Q", "a", true), rec(1, "Q", "b", true)]}), false).is_ok()
        );
        let twice = json!({"records": [rec(0, "Ctrl + Q", "a", true), rec(1, "Ctrl + Q", "b", true)]});
        assert!(compile_keys(&twice, false).is_err());
        assert!(compile_keys(&json!({"records": [rec(0, "Q", "", true)]}), false).is_err());
        assert!(compile_keys(&json!({"records": [rec(0, "Q", "", false)]}), false).is_ok());
        // The laptop column is checked the same way: its key may not be another record's.
        let mut lap = json!({"records": [rec(0, "Numpad 0", "a", true), rec(1, "Z", "b", true)]});
        lap["records"][0]["laptop"] = "Z".into();
        assert!(compile_keys(&lap, false).is_ok() && compile_keys(&lap, true).is_err());
    }

    /// KEY_CODES holds exactly the scancodes key_table.gd's DIK_TO_KEY can press (a key it cannot press would compile
    /// and never fire).
    #[test]
    fn the_key_names_are_the_keys_the_reader_presses() {
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let gd = ["game", "shared", "iaf-reborn"]
            .iter()
            .find_map(|d| std::fs::read_to_string(repo.join(d).join("controls/key_table.gd")).ok())
            .expect("key_table.gd");
        let body = &gd[gd.find("const DIK_TO_KEY").unwrap()..];
        let body = &body[..body.find("\n}").unwrap()];
        let reader: BTreeSet<u32> = body
            .lines()
            .filter_map(|l| l.trim().strip_prefix("0x"))
            .map(|l| u32::from_str_radix(&l[..l.find(':').unwrap()], 16).unwrap())
            .collect();
        let ours: BTreeSet<u32> = KEY_CODES.iter().map(|c| c.1).collect();
        assert_eq!(ours, reader);
        assert_eq!(ours.len(), KEY_CODES.len(), "a scancode named twice");
    }

    #[test]
    fn a_clip_in_another_format_is_refused() {
        let wav = |fmt: u16, ch: u16, rate: u32, bits: u16| {
            let mut b = b"RIFF\0\0\0\0WAVEfmt \x10\0\0\0".to_vec();
            for v in [fmt, ch] {
                b.extend(v.to_le_bytes());
            }
            b.extend(rate.to_le_bytes());
            b.extend((rate * 2).to_le_bytes());
            b.extend(2u16.to_le_bytes());
            b.extend(bits.to_le_bytes());
            b.extend(b"data\x04\0\0\0\0\0\0\0");
            b
        };
        assert!(wav_seconds(&wav(1, 1, 22050, 16)).is_ok());
        assert!(wav_seconds(&wav(1, 2, 22050, 16)).is_err());
        assert!(wav_seconds(&wav(1, 1, 44100, 16)).is_err());
        assert!(wav_seconds(&wav(3, 1, 22050, 32)).is_err());
        assert!(wav_seconds(b"OggS").is_err());
    }

    /// Every airbase layout (`airbases/*.json`, iaf-2026/docs/airbases.md) parses, and every runway has two ends
    /// with a place and a heading, and a width; every source names a footnote of the file, "inferred" or "open".
    #[test]
    fn every_airbase_has_runways_with_two_ends_and_a_width() {
        let files = read_dir(&data().join("airbases")).unwrap();
        for f in &files {
            let (base, name) = (&f.v, &f.name);
            let runways = base["runways"].as_array().unwrap();
            assert!(!runways.is_empty(), "{name}: no runway");
            for r in runways {
                let ends = r["ends"].as_array().unwrap();
                assert_eq!(ends.len(), 2, "{name} {}: two ends", r["designator"]);
                for e in ends {
                    for k in ["lat", "lon", "heading"] {
                        assert!(e[k].is_f64(), "{name} {}: end without {k}", e["designator"]);
                    }
                }
                assert!(r["width_m"].as_f64().is_some_and(|w| w > 0.0), "{name} {}: no width", r["designator"]);
            }
            // Every source, at any depth: one name or several joined by commas (§1).
            let notes = base["footnotes"].as_object().unwrap();
            let mut stack = vec![base];
            while let Some(v) = stack.pop() {
                match v {
                    Value::Object(m) => {
                        for (k, v) in m {
                            let given = match (k.as_str(), v) {
                                ("source", Value::String(s)) => vec![s.as_str()],
                                ("sources", Value::Object(s)) => s.values().filter_map(Value::as_str).collect(),
                                _ => vec![],
                            };
                            for n in given.iter().flat_map(|g| g.split(',')).map(str::trim) {
                                assert!(["inferred", "open"].contains(&n) || notes.contains_key(n), "{name}: {n}");
                            }
                            stack.push(v);
                        }
                    }
                    Value::Array(a) => stack.extend(a),
                    _ => {}
                }
            }
        }
        assert_eq!(files.len(), 4, "Ramon, Hatzerim, Nevatim, Ramat David");
    }
}
