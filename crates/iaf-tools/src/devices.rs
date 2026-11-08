//! Modern IAF's device settings (iaf-2026/docs/front-end.md §9): the player's keys, joystick buttons and axes over the
//! sim's key table, kept in one compact JSON file, the store (`user://devices.json`):
//!
//! `{"keys": {"<record>": key}, "buttons": {"<record>": button}, "axes": {"<role>": {"axis": n, "invert": b, "dead": x}}}`
//!
//! A key is DIK | modifiers << 16 as `key_table.gd` stores it (0 = no key); a button is the joystick's 0-based button,
//! `HAT`..`HAT + 3` the hat (up, right, down, left), −1 = none. The store keeps only what differs from the defaults:
//! the key table's own key and button, and for the axes `joystick.gd`'s axis numbers and dead zones.
//!
//! A device map (`iaf-2026/data/devices/<device>.json`: `match`, `axes` {role: axis}, `buttons` {record: button}) holds
//! a known joystick's defaults: its axes, and its whole button column (records it does not list: none). The defaults
//! are the key table with the map over it (`with_map`); the store goes over those.

use anyhow::{Context, Result};
use serde_json::{Map, Value, json};
use std::path::Path;

/// The axis roles, in the order of `Settings.joy_axes` (x, y, throttle, rudder, the rocker).
pub const ROLES: [&str; 5] = ["roll", "pitch", "throttle", "rudder", "trim"];
/// The first hat button (`joystick.gd` HAT_BUTTON).
pub const HAT: i64 = 32;

/// A binding column of the key table: the key or the joystick button.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Column {
    Key,
    Button,
}

impl Column {
    pub fn parse(s: &str) -> Option<Column> {
        match s {
            "key" => Some(Column::Key),
            "button" => Some(Column::Button),
            _ => None,
        }
    }

    fn section(self) -> &'static str {
        match self {
            Column::Key => "keys",
            Column::Button => "buttons",
        }
    }

    /// The value meaning "nothing bound".
    pub fn none(self) -> i64 {
        match self {
            Column::Key => 0,
            Column::Button => -1,
        }
    }
}

/// The store at `path`; an empty one when the file is missing or unreadable.
pub fn load(path: &Path) -> Value {
    let v = std::fs::read_to_string(path).ok().and_then(|s| serde_json::from_str::<Value>(&s).ok());
    match v {
        Some(v @ Value::Object(_)) => v,
        _ => json!({}),
    }
}

/// Writes the store compact, making its folder.
pub fn save(path: &Path, store: &Value) -> Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).with_context(|| dir.display().to_string())?;
    }
    // A temporary file renamed into place: a crash mid-write leaves the old store, never an empty one.
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_string(store)?).with_context(|| tmp.display().to_string())?;
    std::fs::rename(&tmp, path).with_context(|| path.display().to_string())
}

/// The map of the device named `name` in `dir`: the first `*.json` (in file-name order) whose `match` is part of the
/// name, case ignored; None when none matches or the folder is missing.
pub fn find_map(dir: &Path, name: &str) -> Option<std::path::PathBuf> {
    let mut files: Vec<_> = std::fs::read_dir(dir).ok()?.filter_map(|e| e.ok().map(|e| e.path())).collect();
    files.retain(|p| p.extension().is_some_and(|x| x == "json"));
    files.sort();
    let name = name.to_lowercase();
    files.into_iter().find(|p| {
        let m = load(p);
        m["match"].as_str().is_some_and(|w| !w.is_empty() && name.contains(&w.to_lowercase()))
    })
}

/// The key table with a device map's button column (`map` {} = the table's own).
pub fn with_map(table: &Value, map: &Value) -> Value {
    let mut out = table.clone();
    if let (Some(b), Some(recs)) = (map["buttons"].as_object(), out["records"].as_array_mut()) {
        for (i, r) in recs.iter_mut().enumerate() {
            r["joystick"] = b.get(&i.to_string()).and_then(Value::as_i64).unwrap_or(-1).into();
        }
    }
    out
}

fn section<'a>(store: &'a mut Value, name: &str) -> &'a mut Map<String, Value> {
    if !store.is_object() {
        *store = json!({});
    }
    let m = store.as_object_mut().expect("object");
    if !m.get(name).is_some_and(Value::is_object) {
        m.insert(name.into(), json!({}));
    }
    m.get_mut(name).and_then(Value::as_object_mut).expect("object")
}

fn records(table: &Value) -> &[Value] {
    table["records"].as_array().map(Vec::as_slice).unwrap_or(&[])
}

/// Record `rec`'s default in `col`: the table's key (dik | modifiers << 16) or button.
pub fn default_of(rec: &Value, col: Column) -> i64 {
    match col {
        Column::Key => rec["dik"].as_i64().unwrap_or(0) | (rec["modifiers"].as_i64().unwrap_or(0) << 16),
        Column::Button => rec["joystick"].as_i64().unwrap_or(-1),
    }
}

/// Record `i`'s binding in `col` with the store's override.
pub fn value_of(table: &Value, store: &Value, i: usize, col: Column) -> i64 {
    let over = store[col.section()][i.to_string()].as_i64();
    over.unwrap_or_else(|| records(table).get(i).map_or(col.none(), |r| default_of(r, col)))
}

/// The key table with the store's keys and buttons in it (the table the flight reads), each record also carrying its
/// defaults (`default_key`, `default_joystick`).
pub fn merge_keys(table: &Value, store: &Value) -> Value {
    let mut out = table.clone();
    if let Some(recs) = out["records"].as_array_mut() {
        for (i, r) in recs.iter_mut().enumerate() {
            let (dk, db) = (default_of(r, Column::Key), default_of(r, Column::Button));
            let k = store["keys"][i.to_string()].as_i64().unwrap_or(dk);
            let b = store["buttons"][i.to_string()].as_i64().unwrap_or(db);
            r["dik"] = (k & 0xffff).into();
            r["modifiers"] = (k >> 16).into();
            r["joystick"] = b.into();
            r["default_key"] = dk.into();
            r["default_joystick"] = db.into();
        }
    }
    out
}

/// The first record other than `i` already bound to `v` in `col` (the flight takes the first match), None for none.
pub fn conflict(table: &Value, store: &Value, i: usize, col: Column, v: i64) -> Option<usize> {
    if v == col.none() || (col == Column::Button && v < 0) {
        return None;
    }
    (0..records(table).len()).find(|&j| j != i && value_of(table, store, j, col) == v)
}

/// Binds record `i` to `v` in `col`; the override goes when `v` is the default again.
pub fn set(table: &Value, store: &mut Value, i: usize, col: Column, v: i64) {
    let default = records(table).get(i).map_or(col.none(), |r| default_of(r, col));
    let m = section(store, col.section());
    if v == default {
        m.remove(&i.to_string());
    } else {
        m.insert(i.to_string(), v.into());
    }
}

/// Record `i` back to its default in `col`; None: every record in `col`.
pub fn reset(store: &mut Value, i: Option<usize>, col: Column) {
    let m = section(store, col.section());
    match i {
        Some(i) => {
            m.remove(&i.to_string());
        }
        None => m.clear(),
    }
}

/// Every axis back to the defaults.
pub fn reset_axes(store: &mut Value) {
    section(store, "axes").clear();
}

/// `joystick.gd`'s dead zone of a role: DEAD_ZONE 0.25 (SOFT_DEAD_ZONE 0.05 with the Soft centre stick response) on
/// the stick and the rudder, none on the throttle, ROCKER_DEAD_ZONE 0.1 on the trim rocker.
pub fn default_dead(role: usize, soft: bool) -> f64 {
    match role {
        2 => 0.0,
        4 => 0.1,
        _ if soft => 0.05,
        _ => 0.25,
    }
}

/// Every role with the store's choices: `{role: {"axis": n (−1 none), "invert": b, "dead": x}}`; `soft` = the Soft
/// centre stick response (its dead zone is the default).
pub fn axes(store: &Value, map: &Value, soft: bool) -> Value {
    let mut out = Map::new();
    for (r, name) in ROLES.iter().enumerate() {
        let s = &store["axes"][*name];
        out.insert(
            (*name).into(),
            json!({
                "axis": s["axis"].as_i64().unwrap_or(default_axis(map, r)),
                "invert": s["invert"].as_bool().unwrap_or(false),
                "dead": s["dead"].as_f64().map_or(default_dead(r, soft), |d| d.clamp(0.0, 0.9)),
            }),
        );
    }
    Value::Object(out)
}

/// The device axis of role `r` by default: the map's, else `joystick.gd`'s 0..4.
pub fn default_axis(map: &Value, r: usize) -> i64 {
    map["axes"][ROLES[r]].as_i64().unwrap_or(r as i64)
}

/// Sets role `role` to device axis `axis` (−1 none), inverted or not, with dead zone `dead` (0..0.9). A role already on
/// that axis gives it up (none): one axis drives one role. Unknown roles change nothing (false).
pub fn set_axis(store: &mut Value, map: &Value, role: &str, axis: i64, invert: bool, dead: f64, soft: bool) -> bool {
    let Some(r) = ROLES.iter().position(|n| *n == role) else { return false };
    let now = axes(store, map, soft);
    if axis >= 0 {
        for (o, other) in ROLES.iter().enumerate() {
            if o != r && now[*other]["axis"].as_i64() == Some(axis) {
                let m = section(store, "axes");
                let e = m.entry(*other).or_insert_with(|| json!({}));
                if !e.is_object() {
                    *e = json!({}); // a hand-edited entry that is no object
                }
                e["axis"] = (-1).into();
            }
        }
    }
    let dead = dead.clamp(0.0, 0.9);
    let mut e = Map::new();
    if axis != default_axis(map, r) {
        e.insert("axis".into(), axis.into());
    }
    if invert {
        e.insert("invert".into(), true.into());
    }
    if (dead - default_dead(r, soft)).abs() > 1e-6 {
        e.insert("dead".into(), dead.into());
    }
    let m = section(store, "axes");
    if e.is_empty() {
        m.remove(role);
    } else {
        m.insert(role.into(), Value::Object(e));
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Three records in the compiled table's shape: Pitch up (Up, no button), Gun (Tab, button 0), Next target
    /// (Return, button 2).
    fn table() -> Value {
        json!({"records": [
            {"index": 0, "label": "Pitch up", "dik": 0xc8, "modifiers": 0, "joystick": -1},
            {"index": 1, "label": "Gun trigger", "dik": 0x0f, "modifiers": 0, "joystick": 0},
            {"index": 2, "label": "Next target", "dik": 0x1c, "modifiers": 0x11, "joystick": 2},
        ]})
    }

    #[test]
    fn bound_key_reaches_the_merged_table() {
        let (t, mut s) = (table(), json!({}));
        set(&t, &mut s, 0, Column::Key, 0x11 | (0x22 << 16)); // Shift + W
        let m = merge_keys(&t, &s);
        assert_eq!(m["records"][0]["dik"], 0x11);
        assert_eq!(m["records"][0]["modifiers"], 0x22);
        assert_eq!(m["records"][0]["default_key"], 0xc8);
        assert_eq!(m["records"][1]["dik"], 0x0f, "others keep their default");
        set(&t, &mut s, 1, Column::Button, HAT + 2);
        assert_eq!(merge_keys(&t, &s)["records"][1]["joystick"], HAT + 2);
    }

    #[test]
    fn conflicts_name_the_other_record() {
        let (t, mut s) = (table(), json!({}));
        let ctrl_return = 0x1c | (0x11 << 16);
        assert_eq!(conflict(&t, &s, 0, Column::Key, ctrl_return), Some(2));
        assert_eq!(conflict(&t, &s, 2, Column::Key, ctrl_return), None, "its own key is no conflict");
        assert_eq!(conflict(&t, &s, 0, Column::Button, 0), Some(1));
        assert_eq!(conflict(&t, &s, 0, Column::Button, -1), None, "no button is no conflict");
        assert_eq!(conflict(&t, &s, 0, Column::Key, 0), None, "no key is no conflict");
        // Swap: the other record takes the old key, then the new one is free.
        set(&t, &mut s, 2, Column::Key, 0xc8);
        set(&t, &mut s, 0, Column::Key, ctrl_return);
        assert_eq!(conflict(&t, &s, 0, Column::Key, ctrl_return), None);
        assert_eq!(value_of(&t, &s, 2, Column::Key), 0xc8);
    }

    #[test]
    fn axis_inverted_with_a_dead_zone() {
        let mut s = json!({});
        assert!(set_axis(&mut s, &json!({}), "pitch", 3, true, 0.1, false));
        let a = axes(&s, &json!({}), false);
        assert_eq!(a["pitch"], json!({"axis": 3, "invert": true, "dead": 0.1}));
        assert_eq!(a["rudder"]["axis"], -1, "the rudder gave axis 3 up");
        assert_eq!(a["roll"], json!({"axis": 0, "invert": false, "dead": 0.25}));
        assert_eq!(axes(&s, &json!({}), true)["roll"]["dead"], 0.05, "Soft centre's dead zone is the default then");
        assert!(!set_axis(&mut s, &json!({}), "view", 5, false, 0.0, false), "no such role");
        // Back to the default: the entry goes.
        assert!(set_axis(&mut s, &json!({}), "pitch", 1, false, 0.25, false));
        assert!(s["axes"].get("pitch").is_none());
    }

    #[test]
    fn device_map_sets_the_defaults() {
        let map = json!({"match": "Hotas X", "axes": {"rudder": 5}, "buttons": {"2": 7}});
        let t = with_map(&table(), &map);
        assert_eq!(value_of(&t, &json!({}), 2, Column::Button), 7);
        assert_eq!(value_of(&t, &json!({}), 1, Column::Button), -1, "a record the map leaves out has no button");
        assert_eq!(axes(&json!({}), &map, false)["rudder"]["axis"], 5);
        let mut s = json!({});
        assert!(set_axis(&mut s, &map, "rudder", 5, false, 0.25, false));
        assert_eq!(s["axes"], json!({}), "the map's axis is the default");
        let dir = std::env::temp_dir().join(format!("iaf-maps-{}", std::process::id()));
        save(&dir.join("hotas_x.json"), &map).unwrap();
        assert_eq!(find_map(&dir, "Thrustmaster T.Flight HOTAS X"), Some(dir.join("hotas_x.json")));
        assert_eq!(find_map(&dir, "Xbox Controller"), None);
        std::fs::remove_dir_all(&dir).unwrap();
        assert_eq!(find_map(&dir, "Hotas X"), None, "a missing folder has no map");
    }

    #[test]
    fn store_round_trips_compact() {
        let (t, mut s) = (table(), json!({}));
        set(&t, &mut s, 0, Column::Key, 0x11);
        set(&t, &mut s, 2, Column::Button, 5);
        set_axis(&mut s, &json!({}), "throttle", 4, true, 0.0, false);
        let dir = std::env::temp_dir().join(format!("iaf-devices-{}", std::process::id()));
        let path = dir.join("devices.json");
        save(&path, &s).unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(!text.contains('\n') && !text.contains(": "), "compact: {text}");
        assert!(!path.with_extension("json.tmp").exists(), "the temporary file is renamed into place");
        assert_eq!(load(&path), s);
        std::fs::remove_dir_all(&dir).unwrap();
        assert_eq!(load(&path), json!({}), "a missing file is an empty store");
        save(&path, &json!({"keys": [1], "axes": {"roll": {"dead": 7.0, "axis": "x"}}})).unwrap();
        let a = axes(&load(&path), &json!({}), false);
        assert_eq!(a["roll"], json!({"axis": 0, "invert": false, "dead": 0.9}), "a hand-edited store stays in range");
        assert_eq!(value_of(&table(), &load(&path), 0, Column::Key), 0xc8);
        std::fs::write(&path, "{not json").unwrap();
        assert_eq!(load(&path), json!({}), "a corrupt file is an empty store");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    /// A hand-edited role entry that is no object is replaced when another role takes its axis.
    #[test]
    fn a_role_entry_that_is_no_object_is_replaced() {
        let mut s = json!({"axes": {"pitch": 7}});
        assert!(set_axis(&mut s, &json!({}), "roll", 1, false, 0.25, false));
        assert_eq!(s["axes"]["pitch"], json!({"axis": -1}));
        assert_eq!(axes(&s, &json!({}), false)["roll"]["axis"], 1);
    }

    #[test]
    fn reset_one_and_all() {
        let (t, mut s) = (table(), json!({}));
        set(&t, &mut s, 0, Column::Key, 0x11);
        set(&t, &mut s, 1, Column::Key, 0x12);
        set(&t, &mut s, 1, Column::Button, 7);
        set_axis(&mut s, &json!({}), "roll", 2, false, 0.25, false);
        reset(&mut s, Some(0), Column::Key);
        assert_eq!(value_of(&t, &s, 0, Column::Key), 0xc8);
        assert_eq!(value_of(&t, &s, 1, Column::Key), 0x12);
        reset(&mut s, None, Column::Key);
        assert_eq!(value_of(&t, &s, 1, Column::Key), 0x0f);
        assert_eq!(value_of(&t, &s, 1, Column::Button), 7, "the buttons keep theirs");
        reset(&mut s, None, Column::Button);
        reset_axes(&mut s);
        assert_eq!(merge_keys(&t, &s), merge_keys(&t, &json!({})));
        assert_eq!(axes(&s, &json!({}), false), axes(&json!({}), &json!({}), false));
        // Binding the default again stores nothing.
        set(&t, &mut s, 0, Column::Key, 0xc8);
        assert_eq!(s["keys"], json!({}));
    }
}
