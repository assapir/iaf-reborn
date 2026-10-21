//! The mission editor's edits and checks (docs/mission-editor.md) on a converted mission file (docs/formats/mis.md):
//! names, adding and removing entities, ground routes (motion op 16 Path, docs/mission-runtime.md §4), the blue
//! flights Alpha..Delta, and the Fly / ground check. Every part keeps its placeholder row (0x14 = 1) last.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use iaf_avionics::Vec3;
use iaf_avionics::heights::{HeightField, Meta};
use iaf_formats::terrain_types::{RUNWAY, SEA, TerrainTypes};
use serde_json::{Map, Value, json};

use crate::mission_creator::beside;

/// The jets the TSD lets the player fly (`tsd.gd FLYABLE_TYPES`, bdb object 0x5b4).
const FLYABLE: [i64; 9] = [100, 110, 120, 130, 140, 160, 180, 190, 200];
const FLIGHT_NAMES: [&str; 4] = ["Alpha", "Bravo", "Charlie", "Delta"];
/// bdb object classes (0x5aa, `tsd.gd ICON_CLASS`).
const VEHICLES: [i64; 2] = [5, 6];
const SITES: [i64; 6] = [8, 9, 10, 11, 12, 13]; // SAM, IR-SAM, AAA, radars, buildings
const SHIPS: [i64; 2] = [15, 16];
/// Slope limits (degrees), inferred and tuned on the original missions (docs/mission-editor.md).
const SLOPE_SITE: f64 = 15.0;
const SLOPE_VEHICLE: f64 = 30.0;
/// How far (m) the other surface counts as the shore.
const SHORE: f64 = 200.0;

/// A mission name: also its file name, so ASCII letters, digits, space, `_` and `-`, starting with a letter or digit.
pub fn valid_name(name: &str) -> Result<(), String> {
    let mut c = name.chars();
    match c.next() {
        None => return Err("The name is empty.".into()),
        Some(f) if !f.is_ascii_alphanumeric() => {
            return Err("The name must start with an English letter or a digit.".into());
        }
        _ => {}
    }
    if name.chars().count() > 40 {
        return Err("The name is longer than 40 characters.".into());
    }
    if c.any(|ch| !(ch.is_ascii_alphanumeric() || " _-".contains(ch))) {
        return Err("Use English letters, digits, spaces, _ and - only.".into());
    }
    Ok(())
}

/// The file stem of a name: lowercase, spaces as `_`.
pub fn stem(name: &str) -> String {
    name.to_ascii_lowercase().replace(' ', "_")
}

/// `base` when no name in `taken` matches it (case-insensitively), else "base 2", "base 3"…
pub fn free_name(base: &str, taken: &[String]) -> String {
    let used = |n: &str| taken.iter().any(|t| t.eq_ignore_ascii_case(n));
    if !used(base) {
        return base.to_string();
    }
    (2..).map(|k| format!("{base} {k}")).find(|n| !used(n)).unwrap()
}

fn items<'a>(m: &'a mut Value, part: &str) -> &'a mut Vec<Value> {
    if !m[part]["items"].is_array() {
        m[part]["items"] = json!([]);
    }
    m[part]["items"].as_array_mut().unwrap()
}

fn real(v: &Value) -> bool {
    int(&v["0x14"]) == 0
}

fn int(v: &Value) -> i64 {
    v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)).unwrap_or(-1)
}

fn num(v: &Value) -> f64 {
    v.as_f64().unwrap_or(0.0)
}

/// Inserts `row` before the placeholder row with a fresh id: the placeholder's (ids are never reused, so a stale
/// reference cannot name the new row), the placeholder moving one up. Returns the id.
fn insert(rows: &mut Vec<Value>, mut row: Value) -> i64 {
    let max = rows.iter().map(|r| int(&r["0x1e"])).max().unwrap_or(0);
    let at = rows.iter().rposition(|r| !real(r));
    let id = match at {
        Some(p) => {
            let id = int(&rows[p]["0x1e"]).max(max);
            rows[p]["0x1e"] = json!(id + 1);
            id
        }
        None => max + 1,
    };
    row["0x14"] = json!(0);
    row["0x1e"] = json!(id);
    rows.insert(at.unwrap_or(rows.len()), row);
    id
}

/// A new entity copied from `template` (an entity of the wanted bdb type, from any mission) with `fields` on top: its
/// events, scripts and related entity cleared and brain-controlled (they belong to the template's mission).
pub fn add_entity(mut mission: Value, template: &Value, fields: &Map<String, Value>) -> (Value, i64) {
    let mut e = template.clone();
    if let Some(slots) = e["slots"].as_array_mut() {
        for s in slots {
            (s["0x334"], s["0x33e"], s["0x348"]) = (json!(""), json!(0), json!(0));
        }
    }
    for k in ["scripts0", "scripts1"] {
        e[k] = json!({"_class": "CObArray", "items": []});
    }
    e["0xac"] = json!(-1);
    e["0x320"] = json!(0);
    if let Some(o) = e.as_object_mut() {
        o.remove("0xec");
        o.remove("0xf0");
        for (k, v) in fields {
            o.insert(k.clone(), v.clone());
        }
    }
    let id = insert(items(&mut mission, "entities"), e);
    (mission, id)
}

/// Removes entity `id` and the references to it: formation members and targets (-1), event actions, related
/// entities (0xac = -1).
pub fn remove_entity(mut mission: Value, id: i64) -> Value {
    items(&mut mission, "entities").retain(|e| !(real(e) && int(&e["0x1e"]) == id));
    for e in items(&mut mission, "entities") {
        if int(&e["0xac"]) == id {
            e["0xac"] = json!(-1);
        }
    }
    for f in items(&mut mission, "formations") {
        for mm in f["members"].as_array_mut().into_iter().flatten() {
            if int(&mm["0x41a"]) == id {
                (mm["0x410"], mm["0x41a"]) = (json!(""), json!(-1));
            }
            if int(&mm["0x424"]) == id {
                mm["0x424"] = json!(-1);
            }
        }
    }
    for ev in items(&mut mission, "events") {
        if let Some(list) = ev["list"].as_array_mut() {
            list.retain(|a| int(&a[0]) != id);
        }
    }
    mission
}

/// A motion-list entry (CDMEScriptObj) as the original missions write it (against_all_odds' "PATH").
fn script(index: i64, op: i64, name: &str, duration: i64, next: i64, path: (&str, i64)) -> Value {
    json!({
        "0x14": 1, "0x1e": index, "0x834": name.to_uppercase(), "0x83e": op, "0x848": path.0,
        "0x852": 1.0, "0x85c": 0.0, "0x866": 0.0, "0x870": 0.0, "0x87a": duration, "0x884": -1,
        "0x88e": if next > 0 { "Hover" } else { "N.A" }, "0x898": next, "0x8a2": name, "0x8ac": path.1,
        "_class": "CDMEScriptObj", "raw10": index,
    })
}

/// The arc length (m, horizontal) from the point of `pts` closest to `p` to the last point, as the runtime joins a
/// path (`mission_runtime.gd _path_from`, `FUN_0047eb90`, `FUN_0047f280`).
fn length_from(p: [f64; 2], pts: &[[f64; 3]]) -> f64 {
    let seg = |a: &[f64; 3], b: &[f64; 3]| (b[0] - a[0]).hypot(b[1] - a[1]);
    let (mut best, mut out) = (f64::INFINITY, 0.0);
    for i in 0..pts.len().saturating_sub(1) {
        let (a, b) = (pts[i], pts[i + 1]);
        let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
        let t = (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy).max(1e-9)).clamp(0.0, 1.0);
        let d = (p[0] - a[0] - t * dx).hypot(p[1] - a[1] - t * dy);
        if d < best {
            best = d;
            out = (1.0 - t) * seg(&a, &b) + pts[i + 1..].windows(2).map(|w| seg(&w[0], &w[1])).sum::<f64>();
        }
    }
    out
}

/// Gives units `ids` a route: a new path (CDMEPathsItem) through `points` (world X east, Y north, z: 0 on the
/// ground, the height above the ground for a flyer), each unit mission-controlled (0x320 | 1) with motion list entry 1
/// = Path (op 16, the constant-speed variant 0x884 = −1) for its arc length at `speed_kmh`, then Hover (op 1) at the
/// end when `hover_end`. No ids: the route is cleared from nothing (the mission comes back unchanged).
pub fn set_route(mut mission: Value, ids: &[i64], points: &[[f64; 3]], speed_kmh: f64, hover_end: bool) -> Value {
    if ids.is_empty() || points.len() < 2 {
        return mission;
    }
    for &id in ids {
        mission = clear_route(mission, id);
    }
    let name = format!("route {}", ids.iter().map(i64::to_string).collect::<Vec<_>>().join(" "));
    let pts: Vec<Value> = points.iter().enumerate().map(|(i, p)| json!([i + 1, p[0], p[1], p[2], 0, 0])).collect();
    let row = json!({"0x5dc": name, "0x5e6": "", "_class": "CDMEPathsItem", "points": pts});
    let path = insert(items(&mut mission, "paths"), row);
    let speed = (speed_kmh / 3.6).max(0.1);
    for e in items(&mut mission, "entities").iter_mut().filter(|e| real(e) && ids.contains(&int(&e["0x1e"]))) {
        let len = length_from([num(&e["0x2e4"]), num(&e["0x2ee"])], points);
        let duration = ((len / speed).round() as i64).max(1);
        let mut list = vec![script(1, 16, "Path", duration, if hover_end { 2 } else { -1 }, (&name, path))];
        if hover_end {
            list.push(script(2, 1, "Hover", 0, -1, ("", -1)));
        }
        e["0xec"] = json!(list.len());
        e["scripts0"] = json!({"_class": "CObArray", "items": list});
        e["0x320"] = json!(int(&e["0x320"]).max(0) | 1);
    }
    mission
}

/// Takes unit `id` off its route: its motion list emptied, brain-controlled again; a path no unit follows any more
/// is removed.
pub fn clear_route(mut mission: Value, id: i64) -> Value {
    let paths_of = |e: &Value| -> Vec<i64> {
        e["scripts0"]["items"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|s| int(&s["0x83e"]) == 16)
            .map(|s| int(&s["0x8ac"]))
            .collect()
    };
    let mut dropped = vec![];
    for e in items(&mut mission, "entities").iter_mut().filter(|e| real(e) && int(&e["0x1e"]) == id) {
        dropped.extend(paths_of(e));
        e["scripts0"] = json!({"_class": "CObArray", "items": []});
        e["0x320"] = json!(int(&e["0x320"]).max(0) & !1);
        if let Some(o) = e.as_object_mut() {
            o.remove("0xec");
        }
    }
    let used: HashSet<i64> = items(&mut mission, "entities").iter().flat_map(paths_of).collect();
    items(&mut mission, "paths")
        .retain(|p| !real(p) || !dropped.contains(&int(&p["0x1e"])) || used.contains(&int(&p["0x1e"])));
    mission
}

fn formation_index(mission: &mut Value, number: i64) -> Option<usize> {
    items(mission, "formations").iter().position(|f| real(f) && int(&f["0x3f2"]) == number)
}

/// Creates or updates blue flight `number` (1..4, Alpha..Delta) from `spec` {type (bdb object id), count (1 or 2:
/// a formation has two member slots), slot_x, slot_y, alt, heading, points? ([[x, y, alt, speed(, action)]])}: the
/// leader at the slot, the wingman 50 m off its left as the Mission Creator puts it (`FUN_0058eb40`). New members are
/// named Player<n> / Player<nn> (the Mission Creator's slots) and copied from a blue aircraft of the mission.
pub fn set_flight(mut mission: Value, number: i64, spec: &Value) -> Value {
    if !(1..=4).contains(&number) {
        return mission;
    }
    let fi = match formation_index(&mut mission, number) {
        Some(i) => i,
        None => {
            let rows = items(&mut mission, "formations");
            let mut f = rows.iter().find(|f| real(f)).or(rows.last()).cloned().unwrap_or_else(|| json!({}));
            f["0x3e8"] = json!(FLIGHT_NAMES[number as usize - 1]);
            f["0x3f2"] = json!(number);
            f["members"] = json!([{"0x410": "", "0x41a": -1, "0x424": -1}, {"0x410": "", "0x41a": -1, "0x424": -1}]);
            f["_class"] = json!("CDMEFormationItem");
            insert(rows, f);
            formation_index(&mut mission, number).unwrap()
        }
    };
    let count = int(&spec["count"]).clamp(1, 2) as usize;
    let (x, y, alt, h) = (num(&spec["slot_x"]), num(&spec["slot_y"]), num(&spec["alt"]), num(&spec["heading"]));
    let (wx, wy) = beside(x, y, h + 90.0);
    let place = [[x, y], [wx, wy]];
    let members: Vec<i64> = (0..2).map(|k| int(&mission["formations"]["items"][fi]["members"][k]["0x41a"])).collect();
    let find = |m: &Value, id: i64| {
        m["entities"]["items"].as_array().and_then(|a| a.iter().find(|e| real(e) && int(&e["0x1e"]) == id)).cloned()
    };
    for k in 0..2 {
        let have = find(&mission, members[k]);
        if k >= count {
            if have.is_some() {
                mission = remove_entity(mission, members[k]);
            }
            continue;
        }
        let mut fields = Map::new();
        fields.insert("0x2c6".into(), spec["type"].clone());
        fields.insert("0x2d0".into(), json!(1));
        fields.insert("0x2e4".into(), json!(place[k][0]));
        fields.insert("0x2ee".into(), json!(place[k][1]));
        fields.insert("0x2f8".into(), json!(alt));
        fields.insert("0x302".into(), json!(h));
        fields.insert("0x35c".into(), json!(1));
        // Empty pylons load the type's own stores (FUN_005951c0).
        fields.insert("armament".into(), json!({"_class": "CArmament", "hardpoints": vec![0; 24]}));
        let id = match have {
            Some(_) => {
                for e in items(&mut mission, "entities").iter_mut().filter(|e| real(e) && int(&e["0x1e"]) == members[k])
                {
                    for (key, v) in &fields {
                        e[key] = v.clone();
                    }
                }
                members[k]
            }
            None => {
                let template = find(&mission, members[0]).or_else(|| blue_aircraft(&mission)).unwrap_or_else(|| {
                    mission["entities"]["items"]
                        .as_array()
                        .and_then(|a| a.first())
                        .cloned()
                        .unwrap_or_else(|| json!({}))
                });
                let name = if k == 0 { format!("Player{number}") } else { format!("Player{number}{number}") };
                fields.insert("0x2bc".into(), json!(name));
                fields.insert("0x14".into(), json!(0));
                let (m, id) = add_entity(mission, &template, &fields);
                mission = m;
                id
            }
        };
        let name = find(&mission, id).map(|e| e["0x2bc"].clone()).unwrap_or(json!(""));
        let mm = &mut mission["formations"]["items"][fi]["members"][k];
        (mm["0x410"], mm["0x41a"]) = (name, json!(id));
    }
    let f = &mut mission["formations"]["items"][fi];
    if let Some(pts) = spec["points"].as_array() {
        let p: Vec<Value> = pts
            .iter()
            .enumerate()
            .map(|(i, q)| json!([i + 1, num(&q[0]), num(&q[1]), num(&q[2]), num(&q[3]), int(&q[4]).max(0)]))
            .collect();
        f["names"] = json!((1..=p.len()).map(|i| json!([i, ""])).collect::<Vec<_>>());
        f["points"] = json!(p);
    } else if f["points"].as_array().is_none_or(Vec::is_empty) {
        // One waypoint 20 km ahead, so the flight has a route.
        let (dx, dy) = (20000.0 * h.to_radians().sin(), 20000.0 * h.to_radians().cos());
        f["points"] = json!([[1, x + dx, y + dy, alt.max(1000.0), 120.0, 0]]);
        f["names"] = json!([[1, ""]]);
    }
    mission
}

/// The red flights' formation number: the originals give every red flight 8 ("Other", docs/ai.md §7.2).
const RED_FLIGHT: i64 = 8;
/// The originals' red brains: leader 13, wingman 15 (the commonest pair, 55 of the originals' red flights).
const RED_BRAINS: [i64; 2] = [13, 15];
/// The planned speed (m/s) for a red route's arrival times.
const RED_ROUTE_SPEED: f64 = 250.0;

/// Adds a red flight taking off from base `spec.base` (a `mission_year::BASES` stem): {type (bdb object id), count
/// (1..2), base, name, template? (a red aircraft entity of that type from an original), points? ([[x, y, alt, T,
/// action]])}. It follows the originals' red flights: formation number 8, brains 13 / 15, the leader at the base's
/// lineup on its runway heading, the wingman 50 m off its left; the route takes off 10 km ahead (action 2), flies
/// 30 km on (3) and lands at the base (7). A waypoint's "speed" is its planned arrival time in sim seconds (docs/ai.md
/// §7.2); the take-off waits for wp0's.
pub fn set_red_flight(mut mission: Value, spec: &Value) -> Value {
    let Some(b) = crate::mission_year::base(spec["base"].as_str().unwrap_or("")) else { return mission };
    let [x, y, z, h] = b.start;
    let name = spec["name"].as_str().filter(|n| !n.is_empty()).unwrap_or(b.name).to_string();
    let template = if spec["template"].is_object() {
        spec["template"].clone()
    } else {
        let a = mission["entities"]["items"].as_array().cloned().unwrap_or_default();
        a.iter().find(|e| real(e) && int(&e["0x2d0"]) == 2 && e["armament"].is_object()).cloned().unwrap_or_else(|| {
            blue_aircraft(&mission).unwrap_or_else(|| a.first().cloned().unwrap_or_else(|| json!({})))
        })
    };
    let (wx, wy) = beside(x, y, h + 90.0);
    let mut members = vec![];
    for (k, [px, py]) in [[x, y], [wx, wy]].into_iter().enumerate().take(int(&spec["count"]).clamp(1, 2) as usize) {
        let mut f = Map::new();
        for (key, v) in [
            ("0x2bc", json!(format!("{name} {}", k + 1))),
            ("0x2c6", spec["type"].clone()),
            ("0x2d0", json!(2)),
            ("0x2da", json!(RED_BRAINS[k])),
            ("0x2e4", json!(px.round())),
            ("0x2ee", json!(py.round())),
            ("0x2f8", json!(z)),
            ("0x302", json!(h)),
            ("0x35c", json!(0)),
            ("0x14", json!(0)),
            // Empty pylons load the type's own stores (FUN_005951c0).
            ("armament", json!({"_class": "CArmament", "hardpoints": vec![0; 24]})),
        ] {
            f.insert(key.into(), v);
        }
        let (m, id) = add_entity(mission, &template, &f);
        mission = m;
        members.push(json!({"0x410": format!("{name} {}", k + 1), "0x41a": id, "0x424": -1}));
    }
    if members.len() < 2 {
        members.push(json!({"0x410": "", "0x41a": -1, "0x424": -1}));
    }
    let points: Vec<Value> = match spec["points"].as_array() {
        Some(p) => p
            .iter()
            .enumerate()
            .map(|(i, q)| json!([i + 1, num(&q[0]), num(&q[1]), num(&q[2]), num(&q[3]), int(&q[4]).max(0)]))
            .collect(),
        None => {
            let ahead = |d: f64| (x + d * h.to_radians().sin(), y + d * h.to_radians().cos());
            let (t1, t2) = (ahead(10000.0), ahead(40000.0));
            let t = [30.0, 30.0 + 30000.0 / RED_ROUTE_SPEED, 30.0 + 70000.0 / RED_ROUTE_SPEED];
            vec![
                json!([1, t1.0.round(), t1.1.round(), z + 1500.0, t[0], 2]),
                json!([2, t2.0.round(), t2.1.round(), 4000.0, t[1].round(), 3]),
                json!([3, x, y, z + 1500.0, t[2].round(), 7]),
            ]
        }
    };
    let row = json!({
        "_class": "CDMEFormationItem", "0x3e8": name, "0x3f2": RED_FLIGHT, "0x3fc": 0, "0x406": 0,
        "members": members, "names": (1..=points.len()).map(|i| json!([i, ""])).collect::<Vec<_>>(), "points": points,
    });
    insert(items(&mut mission, "formations"), row);
    mission
}

/// A base mission with its sides swapped (blue 1 ↔ red 2): a base the data has for one side, used by the other
/// (Refidim before the Six-Day War is Egyptian).
pub fn flip_base(mut base: Value) -> Value {
    for e in items(&mut base, "entities").iter_mut().filter(|e| real(e)) {
        match int(&e["0x2d0"]) {
            1 => e["0x2d0"] = json!(2),
            2 => e["0x2d0"] = json!(1),
            _ => {}
        }
    }
    base
}

/// A blue aircraft with a brain: the template for a new flight member.
fn blue_aircraft(m: &Value) -> Option<Value> {
    let a = m["entities"]["items"].as_array()?;
    a.iter().find(|e| real(e) && int(&e["0x2d0"]) == 1 && int(&e["0x2da"]) >= 0 && e["armament"].is_object()).cloned()
}

/// Removes blue flight `number` and its members.
pub fn remove_flight(mut mission: Value, number: i64) -> Value {
    let Some(fi) = formation_index(&mut mission, number) else { return mission };
    let f = items(&mut mission, "formations").remove(fi);
    for mm in f["members"].as_array().into_iter().flatten() {
        if int(&mm["0x41a"]) >= 0 {
            mission = remove_entity(mission, int(&mm["0x41a"]));
        }
    }
    mission
}

/// A mission from scratch on `mission` (an original of the wanted era): flight 1 (Alpha) and its members stay, so it
/// flies from the original's start; every other unit, flight, path, event and debrief text goes. The base missions
/// (airbases and their defences) come with the source as for a fork.
pub fn blank(mut mission: Value) -> Value {
    let keep_f = formation_index(&mut mission, 1);
    let mut keep: Vec<i64> = vec![];
    if let Some(fi) = keep_f {
        let f = &items(&mut mission, "formations")[fi];
        keep = f["members"].as_array().into_iter().flatten().map(|m| int(&m["0x41a"])).filter(|&i| i >= 0).collect();
    }
    let ids: Vec<i64> = items(&mut mission, "entities")
        .iter()
        .filter(|e| real(e) && !keep.contains(&int(&e["0x1e"])))
        .map(|e| int(&e["0x1e"]))
        .collect();
    for id in ids {
        mission = remove_entity(mission, id);
    }
    for e in items(&mut mission, "entities") {
        if real(e) {
            for k in ["scripts0", "scripts1"] {
                e[k] = json!({"_class": "CObArray", "items": []});
            }
            e["0x320"] = json!(0);
            if let Some(slots) = e["slots"].as_array_mut() {
                for s in slots {
                    (s["0x334"], s["0x33e"], s["0x348"]) = (json!(""), json!(0), json!(0));
                }
            }
        }
    }
    items(&mut mission, "formations").retain(|f| !real(f) || int(&f["0x3f2"]) == 1);
    for part in ["paths", "events", "debrief", "timevars"] {
        items(&mut mission, part).retain(|r| !real(r));
    }
    mission
}

/// The terrain heights of the level-6 height tiles (`<theatre>/L6/h_<i>_<j>.png`, `meta.json`), read as a tile is
/// first asked for: the surface `terrain.gd height_at` gives (`iaf_avionics::heights`).
pub struct Heights {
    dir: PathBuf,
    meta: Meta,
    level: u32,
    /// The theatre in terrain units (x0, y0, x1, y1).
    theatre: [f64; 4],
    field: HeightField,
    tried: HashSet<(i64, i64)>,
}

impl Heights {
    /// The theatre directory (`assets/converted/terrain/theatre`); None without its meta.json.
    pub fn open(dir: &Path) -> Option<Self> {
        let m: Value = serde_json::from_str(&std::fs::read_to_string(dir.join("meta.json")).ok()?).ok()?;
        let level = m["height_level"].as_u64()? as u32;
        let px = m["node_pixels"].as_u64()? as usize;
        let meta = Meta {
            node_pixels: px,
            span: px as f64 * f64::from(1u32 << level),
            sea_level_raw: num(&m["sea_level_raw"]),
            height_scale: num(&m["height_scale"]),
            m_per_unit: num(&m["units_to_metres"]),
            x_shift: num(&m["x_shift"]),
            y_shift: num(&m["y_shift"]),
        };
        let t = &m["theatre"];
        let mut field = HeightField::default();
        field.set_meta(meta);
        Some(Heights {
            dir: dir.to_path_buf(),
            meta,
            level,
            theatre: [num(&t[0]), num(&t[1]), num(&t[2]), num(&t[3])],
            field,
            tried: HashSet::new(),
        })
    }

    fn units(&self, x: f64, y: f64) -> (f64, f64) {
        ((x - self.meta.x_shift) / self.meta.m_per_unit, (self.meta.y_shift - y) / self.meta.m_per_unit)
    }

    /// True when world point (x east, y north) is inside the theatre.
    pub fn inside(&self, x: f64, y: f64) -> bool {
        let (tx, ty) = self.units(x, y);
        let t = self.theatre;
        tx >= t[0] && tx <= t[2] && ty >= t[1] && ty <= t[3]
    }

    /// The ground height (m) at world point (x east, y north); None outside the terrain.
    pub fn ground_height(&mut self, x: f64, y: f64) -> Option<f64> {
        if !self.inside(x, y) {
            return None;
        }
        let (tx, ty) = self.units(x, y);
        let (i, j) = ((tx / self.meta.span).floor() as i64, (ty / self.meta.span).floor() as i64);
        if self.tried.insert((i, j)) {
            let path = self.dir.join(format!("L{}/h_{i}_{j}.png", self.level));
            if let Ok(img) = image::open(path) {
                let img = img.to_rgb8();
                let rg: Vec<u8> = img.pixels().flat_map(|p| [p[0], p[1]]).collect();
                self.field.add(i, j, img.width() as usize, &rg);
            }
        }
        self.field.height(Vec3::new(x, y, 0.0))
    }

    /// One height sample's spacing (m).
    fn texel(&self) -> f64 {
        self.meta.span / self.meta.node_pixels as f64 * self.meta.m_per_unit
    }

    /// The ground slope (degrees) at (x, y): the height differences one texel east / west and north / south.
    fn slope(&mut self, x: f64, y: f64) -> Option<f64> {
        let r = self.texel();
        let (e, w) = (self.ground_height(x + r, y)?, self.ground_height(x - r, y)?);
        let (n, s) = (self.ground_height(x, y + r)?, self.ground_height(x, y - r)?);
        Some(((e - w) / (2.0 * r)).hypot((n - s) / (2.0 * r)).atan().to_degrees())
    }
}

/// One problem the check found.
#[derive(Clone, Debug, PartialEq)]
pub struct Issue {
    /// The entity (0x1e), -1 for the mission as a whole.
    pub id: i64,
    /// "error" (Fly is blocked) or "warning".
    pub level: &'static str,
    pub text: String,
}

impl Issue {
    pub fn to_json(&self) -> Value {
        json!({"id": self.id, "level": self.level, "text": self.text})
    }
}

fn error(id: i64, text: String) -> Issue {
    Issue { id, level: "error", text }
}

fn warning(id: i64, text: String) -> Issue {
    Issue { id, level: "warning", text }
}

/// The ground check of one place for a unit of bdb class `class`: off the terrain, a land unit on water, a ship on
/// land, a unit on a runway, a slope steeper than its class allows.
fn ground_issues(
    id: i64,
    class: i64,
    x: f64,
    y: f64,
    at: &str,
    h: &mut Heights,
    s: Option<&TerrainTypes>,
) -> Vec<Issue> {
    let ship = SHIPS.contains(&class);
    if !(ship || VEHICLES.contains(&class) || SITES.contains(&class)) {
        return vec![];
    }
    if h.ground_height(x, y).is_none() {
        return vec![error(id, format!("{at}outside the terrain"))];
    }
    let mut out = vec![];
    let flags = s.map_or(0, |t| t.at(x, y));
    let land = TerrainTypes::is_land(flags);
    // The surface polygons are coarse at the coast (harbours, bridges, river crossings in the originals): within
    // SHORE m of the other surface the mismatch is a warning.
    let shore = s.is_some_and(|t| {
        [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)]
            .iter()
            .any(|(dx, dy)| TerrainTypes::is_land(t.at(x + dx * SHORE, y + dy * SHORE)) != land)
    });
    let wrong = if ship && land {
        Some("a ship on land")
    } else if !ship && !land {
        Some(if flags & SEA != 0 { "on the sea" } else { "on inland water" })
    } else {
        None
    };
    if let Some(w) = wrong {
        out.push(if shore || flags & SEA == 0 && !ship { warning } else { error }(id, format!("{at}{w}")));
    }
    // Airbase buildings stand on the airbase surface (the RUNWAY flag) by design: vehicles and SAM / AAA only.
    if flags & RUNWAY != 0 && (VEHICLES.contains(&class) || [8, 9, 10].contains(&class)) {
        out.push(warning(id, format!("{at}on an airbase runway area")));
    }
    let limit = if VEHICLES.contains(&class) { SLOPE_VEHICLE } else { SLOPE_SITE };
    if let Some(sl) = h.slope(x, y).filter(|&sl| !ship && sl > limit) {
        out.push(warning(id, format!("{at}on a {sl:.0}° slope")));
    }
    out
}

/// The checks before Fly (errors block it) and the ground check of each ground unit and of each point of a ground
/// unit's route. `bdb` is the converted default6_1.bdb, `surface` terraintype.dat (None: all land).
pub fn check(mission: &Value, bdb: &Value, heights: &mut Heights, surface: Option<&TerrainTypes>) -> Vec<Issue> {
    let objects: HashMap<i64, &Value> =
        bdb["objects"]["items"].as_array().into_iter().flatten().map(|o| (int(&o["0x1e"]), o)).collect();
    let ents: Vec<&Value> = mission["entities"]["items"].as_array().into_iter().flatten().filter(|e| real(e)).collect();
    let by_id: HashMap<i64, &Value> = ents.iter().map(|e| (int(&e["0x1e"]), *e)).collect();
    let obj = |e: &Value| objects.get(&int(&e["0x2c6"])).copied();
    let mut out = vec![];
    // Flights: members exist; a blue flight 1..4 whose leader (the first member there) is a flyable jet.
    let mut flyable = false;
    for f in mission["formations"]["items"].as_array().into_iter().flatten().filter(|f| real(f)) {
        let n = int(&f["0x3f2"]);
        let ids: Vec<i64> =
            f["members"].as_array().into_iter().flatten().map(|m| int(&m["0x41a"])).filter(|&i| i >= 0).collect();
        for &i in &ids {
            if !by_id.contains_key(&i) {
                // Echo and up: the originals leave some pointing at the placeholder row; they never spawn.
                out.push(if (1..=4).contains(&n) { error } else { warning }(
                    i,
                    format!("flight {} lists entity {i}, which does not exist", f["0x3e8"].as_str().unwrap_or("?")),
                ));
            }
        }
        let leader = ids.iter().find_map(|i| by_id.get(i));
        if let Some(l) = leader.filter(|_| (1..=4).contains(&n)) {
            let code = obj(l).map_or(-1, |o| int(&o["0x5b4"]));
            flyable |= int(&l["0x2d0"]) == 1 && FLYABLE.contains(&code);
        }
        for p in f["points"].as_array().into_iter().flatten() {
            if !heights.inside(num(&p[1]), num(&p[2])) {
                let id = leader.map_or(-1, |l| int(&l["0x1e"]));
                out.push(error(
                    id,
                    format!("a waypoint of flight {} is off the map", f["0x3e8"].as_str().unwrap_or("?")),
                ));
            }
        }
    }
    if !flyable {
        out.push(error(-1, "no blue flight Alpha..Delta has a jet you can fly".into()));
    }
    let paths: HashMap<i64, &Value> =
        mission["paths"]["items"].as_array().into_iter().flatten().map(|p| (int(&p["0x1e"]), p)).collect();
    for e in &ents {
        let id = int(&e["0x1e"]);
        let (x, y) = (num(&e["0x2e4"]), num(&e["0x2ee"]));
        if !heights.inside(x, y) {
            out.push(error(id, "off the map".into()));
            continue;
        }
        let class = obj(e).map_or(-1, |o| int(&o["0x5aa"]));
        out.extend(ground_issues(id, class, x, y, "", heights, surface));
        for s in e["scripts0"]["items"].as_array().into_iter().flatten().filter(|s| int(&s["0x83e"]) == 16) {
            for (k, p) in
                paths.get(&int(&s["0x8ac"])).and_then(|p| p["points"].as_array()).into_iter().flatten().enumerate()
            {
                let at = format!("route point {}: ", k + 1);
                out.extend(ground_issues(id, class, num(&p[1]), num(&p[2]), &at, heights, surface));
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assets() -> Option<PathBuf> {
        let a = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        a.join("converted/missions/2vs2.json").exists().then_some(a)
    }

    fn read(a: &Path, name: &str) -> Value {
        serde_json::from_str(&std::fs::read_to_string(a.join(format!("converted/missions/{name}.json"))).unwrap())
            .unwrap()
    }

    #[test]
    fn names() {
        assert!(valid_name("Dog Chase 2").is_ok());
        assert!(valid_name("a_b-c").is_ok());
        assert!(valid_name("").is_err());
        assert!(valid_name(" x").is_err());
        assert!(valid_name("שלום").is_err());
        assert!(valid_name("x!").is_err());
        assert!(valid_name(&"x".repeat(40)).is_ok());
        assert!(valid_name(&"x".repeat(41)).is_err());
        assert_eq!(stem("Dog Chase 2"), "dog_chase_2");
        let taken = vec!["DOG CHASE".to_string(), "dog chase 2".to_string()];
        assert_eq!(free_name("Dog Chase", &taken), "Dog Chase 3");
        assert_eq!(free_name("Other", &taken), "Other");
    }

    #[test]
    fn blank_keeps_alpha_only() {
        let Some(a) = assets() else {
            eprintln!("skip: no converted missions (tools/setup-cli.sh)");
            return;
        };
        let m = blank(read(&a, "license"));
        let real_rows = |part: &str| m[part]["items"].as_array().unwrap().iter().filter(|r| real(r)).count();
        let f = &m["formations"]["items"].as_array().unwrap()[0];
        assert_eq!((real_rows("formations"), int(&f["0x3f2"])), (1, 1), "only Alpha");
        let members: Vec<i64> =
            f["members"].as_array().unwrap().iter().map(|x| int(&x["0x41a"])).filter(|&i| i >= 0).collect();
        assert_eq!(real_rows("entities"), members.len(), "only Alpha's jets");
        for part in ["paths", "events", "debrief"] {
            assert_eq!(real_rows(part), 0, "{part}");
        }
        for part in ["entities", "formations", "events"] {
            assert_eq!(m[part]["items"].as_array().unwrap().last().unwrap()["0x14"], 1, "{part} placeholder");
        }
    }

    #[test]
    fn length_from_the_closest_point() {
        let pts = [[0.0, 0.0, 0.0], [100.0, 0.0, 0.0], [100.0, 100.0, 0.0]];
        assert!((length_from([50.0, 10.0], &pts) - 150.0).abs() < 1e-9);
        assert!((length_from([-20.0, 0.0], &pts) - 200.0).abs() < 1e-9);
    }

    #[test]
    fn edits_keep_references_and_placeholders() {
        let Some(a) = assets() else {
            eprintln!("skip: no converted missions (tools/setup-cli.sh)");
            return;
        };
        let m = read(&a, "2vs2");
        let last_is_placeholder =
            |m: &Value, part: &str| m[part]["items"].as_array().unwrap().last().unwrap()["0x14"] == 1;
        // Round trip: no edit, the same data.
        let text = serde_json::to_string(&m).unwrap();
        assert_eq!(serde_json::from_str::<Value>(&text).unwrap(), m);
        let sam = read(&a, "against_all_odds")["entities"]["items"][0].clone();
        let mut f = Map::new();
        f.insert("0x2e4".into(), json!(1.0));
        let (m2, id) = add_entity(m.clone(), &sam, &f);
        assert_eq!(id, 5, "the placeholder's id");
        assert!(last_is_placeholder(&m2, "entities"));
        assert_eq!(m2["entities"]["items"].as_array().unwrap().last().unwrap()["0x1e"], 6);
        // Alpha's leader (1) removed: its member slot, Delta's target, the events.
        let m3 = remove_entity(m2, 1);
        let fs = &m3["formations"]["items"];
        assert_eq!(fs[0]["members"][0]["0x41a"], -1);
        assert_eq!(fs[3]["members"][0]["0x424"], -1);
        assert!(m3["entities"]["items"].as_array().unwrap().iter().all(|e| e["0x1e"] != 1));
        let (_, id2) = add_entity(m3.clone(), &sam, &Map::new());
        assert_eq!(id2, 6, "ids are not reused");
        // A route for entity 2 and 3, then cleared again.
        let pts = [[390000.0, 640000.0, 0.0], [391000.0, 640000.0, 0.0]];
        let r = set_route(m3.clone(), &[2, 3], &pts, 36.0, true);
        assert!(last_is_placeholder(&r, "paths"));
        let e2 = r["entities"]["items"].as_array().unwrap().iter().find(|e| e["0x1e"] == 2).unwrap();
        assert_eq!(e2["0x320"].as_i64().unwrap() & 1, 1);
        let s = &e2["scripts0"]["items"];
        assert_eq!(
            (s[0]["0x83e"].clone(), s[0]["0x8ac"].clone(), s[0]["0x884"].clone()),
            (json!(16), json!(1), json!(-1))
        );
        assert_eq!(s[1]["0x83e"], 1, "Hover at the end");
        // As Godot's JSON hands it over: every number a float.
        fn floats(v: &Value) -> Value {
            match v {
                Value::Number(n) => json!(n.as_f64().unwrap()),
                Value::Array(a) => Value::Array(a.iter().map(floats).collect()),
                Value::Object(o) => Value::Object(o.iter().map(|(k, v)| (k.clone(), floats(v))).collect()),
                _ => v.clone(),
            }
        }
        let rf = set_route(floats(&m3), &[2, 3], &pts, 36.0, true);
        assert_eq!(rf["entities"]["items"][0]["scripts0"]["items"][0]["0x83e"], 16, "{}", rf["entities"]["items"][0]);
        let c = clear_route(clear_route(r, 2), 3);
        assert_eq!(c["paths"]["items"].as_array().unwrap().len(), 1, "only the placeholder left");
        // Flights: Bravo moved and made a pair, Delta removed.
        let spec =
            json!({"type": 40, "count": 2, "slot_x": 380000.0, "slot_y": 600000.0, "alt": 3000.0, "heading": 90.0});
        let fl = set_flight(m.clone(), 2, &spec);
        let bravo = fl["formations"]["items"].as_array().unwrap().iter().find(|f| f["0x3f2"] == 2).unwrap().clone();
        let wing = int(&bravo["members"][1]["0x41a"]);
        let w = fl["entities"]["items"].as_array().unwrap().iter().find(|e| int(&e["0x1e"]) == wing).unwrap();
        assert_eq!((w["0x2bc"].clone(), w["0x2c6"].clone()), (json!("Player22"), json!(40)));
        let fl = remove_flight(fl, 4);
        assert!(!fl["formations"]["items"].as_array().unwrap().iter().any(|f| f["0x3f2"] == 4));
        assert!(last_is_placeholder(&fl, "formations"));
    }

    #[test]
    fn red_flight_from_a_base() {
        let Some(a) = assets() else {
            eprintln!("skip: no converted missions (tools/setup-cli.sh)");
            return;
        };
        let m = read(&a, "license");
        let mig = read(&a, "change")["entities"]["items"].as_array().unwrap().iter().find(|e| e["0x2c6"] == 8).cloned();
        let spec = json!({"type": 2, "count": 2, "base": "bmisdmsk", "name": "MiG-29", "template": mig});
        let r = set_red_flight(m.clone(), &spec);
        let f = r["formations"]["items"].as_array().unwrap().iter().find(|f| f["0x3e8"] == "MiG-29").unwrap();
        assert_eq!((int(&f["0x3f2"]), f["points"][0][5].clone(), f["points"][2][5].clone()), (8, json!(2), json!(7)));
        let ids: Vec<i64> = f["members"].as_array().unwrap().iter().map(|x| int(&x["0x41a"])).collect();
        let ents = r["entities"]["items"].as_array().unwrap();
        for (k, id) in ids.iter().enumerate() {
            let e = ents.iter().find(|e| int(&e["0x1e"]) == *id).unwrap();
            assert_eq!((int(&e["0x2c6"]), int(&e["0x2d0"]), int(&e["0x2da"])), (2, 2, [13, 15][k]));
        }
        assert_eq!(r["formations"]["items"].as_array().unwrap().last().unwrap()["0x14"], 1, "placeholder last");
        assert_eq!(set_red_flight(m.clone(), &json!({"type": 2, "base": "nowhere"})), m, "an unknown base: no change");
        // Refidim's base mission is blue; flipped for a red Refidim.
        let flipped = flip_base(read(&a, "bmisrfdim"));
        assert!(flipped["entities"]["items"].as_array().unwrap().iter().filter(|e| real(e)).all(|e| e["0x2d0"] != 1));
    }

    #[test]
    fn check_finds_problems_and_calibration() {
        let Some(a) = assets() else {
            eprintln!("skip: no converted missions (tools/setup-cli.sh)");
            return;
        };
        let Some(mut h) = Heights::open(&a.join("converted/terrain/theatre")) else {
            eprintln!("skip: no converted terrain");
            return;
        };
        let bdb = read(&a, "default6_1.bdb");
        let types = std::fs::read(a.join("install/terraintype.dat")).ok().and_then(|d| TerrainTypes::parse(&d).ok());
        let m = read(&a, "2vs2");
        assert!(check(&m, &bdb, &mut h, types.as_ref()).iter().all(|i| i.level != "error"), "2vs2 flies");
        let mut bad = m.clone();
        bad["formations"]["items"][0]["members"][1]["0x41a"] = json!(99);
        assert!(check(&bad, &bdb, &mut h, types.as_ref()).iter().any(|i| i.id == 99 && i.level == "error"));
        // An SA-6 launcher (bdb 6) in the sea off Tel Aviv.
        let sam = read(&a, "against_all_odds")["entities"]["items"][0].clone();
        let mut f = Map::new();
        for (k, v) in [("0x2c6", json!(6)), ("0x2e4", json!(280000)), ("0x2ee", json!(530000))] {
            f.insert(k.into(), v);
        }
        let (wet, id) = add_entity(m.clone(), &sam, &f);
        let issues = check(&wet, &bdb, &mut h, types.as_ref());
        assert!(issues.iter().any(|i| i.id == id && i.text == "on the sea" && i.level == "error"), "{issues:?}");
        // Calibration over every converted mission file (docs/mission-editor.md).
        let list: Value =
            serde_json::from_str(&std::fs::read_to_string(a.join("converted/missions/missionlist.json")).unwrap())
                .unwrap();
        let mains: HashSet<String> =
            list.as_object().unwrap().values().filter_map(|v| v[0].as_str().map(String::from)).collect();
        let mut counts: HashMap<String, usize> = HashMap::new();
        let mut files = 0;
        for p in std::fs::read_dir(a.join("converted/missions")).unwrap().flatten().map(|e| e.path()) {
            let stem = p.file_stem().unwrap().to_string_lossy().to_string();
            let Ok(v) = serde_json::from_str::<Value>(&std::fs::read_to_string(&p).unwrap()) else { continue };
            if !v["entities"].is_object() {
                continue;
            }
            files += 1;
            for i in check(&v, &bdb, &mut h, types.as_ref()) {
                if i.id < 0 && !mains.contains(&stem) {
                    continue; // a base mission has no flights of its own
                }
                // "route point 3: on a 34° slope" → "on a ° slope"
                let kind: String =
                    i.text.rsplit(": ").next().unwrap_or("").chars().filter(|c| !c.is_ascii_digit()).collect();
                eprintln!("calibration: {stem} {} {}: {}", i.id, i.level, i.text);
                *counts.entry(format!("{} {kind}", i.level)).or_default() += 1;
            }
        }
        eprintln!("calibration: {files} files, {counts:?}");
        let errors: usize = counts.iter().filter(|(k, _)| k.starts_with("error")).map(|(_, n)| n).sum();
        assert_eq!(errors, 10, "the originals' errors in docs/mission-editor.md");
    }
}
