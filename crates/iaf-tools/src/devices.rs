//! Modern IAF's joystick axes (modern-iaf/docs/front-end.md §9), kept in one compact JSON file, the store
//! (`user://devices.json`):
//!
//! `{"axes": {"<role>": {"axis": n, "invert": b, "dead": x}}}`
//!
//! The store keeps only what differs from the defaults: `joystick.gd`'s axis numbers and dead zones, or a device map's.
//! The keys and buttons are both games' one store, `Settings.key_bindings` (`key_table.gd`); a store from before
//! 2026-11-14 also held them (`"keys"`, `"buttons"`), which the sim moves there once (`drop_bindings`).
//!
//! A device map (`modern-iaf/data/devices/<device>.json`: `match`, `axes` {role: axis}, `buttons` {record: button}) holds
//! a known joystick's defaults: its axes here, and its whole button column, which the sim hands to
//! `Joystick.default_buttons` as reborn's `.joy` files do (records it does not list: none).

use anyhow::{Context, Result};
use serde_json::{Map, Value, json};
use std::path::Path;

/// The axis roles, in the order of `Settings.joy_axes` (x, y, throttle, rudder, the rocker).
pub const ROLES: [&str; 5] = ["roll", "pitch", "throttle", "rudder", "trim"];

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

/// Drops the keys and buttons a store from before 2026-11-14 held (the sim moved them into `Settings.key_bindings`);
/// true when it had any.
pub fn drop_bindings(store: &mut Value) -> bool {
    let Some(m) = store.as_object_mut() else { return false };
    m.remove("keys").is_some() | m.remove("buttons").is_some()
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
    fn device_map_sets_the_axes() {
        let map = json!({"match": "Hotas X", "axes": {"rudder": 5}, "buttons": {"2": 7}});
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
        let mut s = json!({});
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
    fn reset_axes_and_drop_old_bindings() {
        let mut s = json!({"keys": {"24": 0x25}, "buttons": {"64": 5}});
        set_axis(&mut s, &json!({}), "roll", 2, false, 0.25, false);
        assert!(drop_bindings(&mut s), "a store from before 2026-11-14 had keys and buttons");
        assert_eq!(s, json!({"axes": {"roll": {"axis": 2}, "throttle": {"axis": -1}}}), "the axes stay");
        assert!(!drop_bindings(&mut s), "none left");
        reset_axes(&mut s);
        assert_eq!(axes(&s, &json!({}), false), axes(&json!({}), &json!({}), false));
    }
}
