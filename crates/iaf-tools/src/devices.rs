//! Modern IAF's joystick axes (modern-iaf/docs/front-end.md §9), kept in one compact JSON file, the store
//! (`user://devices.json`):
//!
//! `{"axes": {"<role>": {"axis": n, "invert": b, "dead": x, "device": "<name>"}}}`
//!
//! `device` puts a role on another device than the main joystick (a throttle, pedals): the device's name as Godot
//! reports it. Absent = the main joystick, the device of the roll role (`joystick.gd` `device()`). Two devices with
//! one name are told apart by the order they were plugged in: the second is `"<name> #2"` (`joystick.gd` `dev_key()`).
//!
//! `"button_devices": ["<name>", …]` numbers the devices other than the main joystick whose buttons are bound: a button
//! on the device at index i is stored in `Settings.key_bindings` as `(i + 1) * 1000 + button` (`button_slot`), so the
//! key table keeps one number per binding; the main joystick's buttons are 0..999 as before.
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

/// The slot (1..) of device `name`'s buttons: its place in `button_devices` plus one, the device added when new; 0 for
/// "" (the main joystick).
pub fn button_slot(store: &mut Value, name: &str) -> i64 {
    if name.is_empty() {
        return 0;
    }
    if !store.is_object() {
        *store = json!({});
    }
    let m = store.as_object_mut().expect("object");
    if !m.get("button_devices").is_some_and(Value::is_array) {
        m.insert("button_devices".into(), json!([]));
    }
    let list = m.get_mut("button_devices").and_then(Value::as_array_mut).expect("array");
    let i = list.iter().position(|v| v == name).unwrap_or_else(|| {
        list.push(name.into());
        list.len() - 1
    });
    i as i64 + 1
}

/// The devices of the button slots 1.. in order (`button_slot`).
pub fn button_devices(store: &Value) -> Value {
    let list = store["button_devices"].as_array().cloned().unwrap_or_default();
    Value::Array(list.into_iter().map(|v| v.as_str().unwrap_or("").into()).collect())
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

/// Every role with the store's choices: `{role: {"axis": n (−1 none), "invert": b, "dead": x, "device": name ("" the
/// main joystick)}}`; `soft` = the Soft centre stick response (its dead zone is the default).
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
                "device": s["device"].as_str().unwrap_or(""),
            }),
        );
    }
    Value::Object(out)
}

/// The device axis of role `r` by default: the map's, else `joystick.gd`'s 0..4.
pub fn default_axis(map: &Value, r: usize) -> i64 {
    map["axes"][ROLES[r]].as_i64().unwrap_or(r as i64)
}

/// One role's choice on the Joystick screen: `axis` (−1 none) of the device named `device`, inverted or not, with dead
/// zone `dead` (0..0.9). `main` is the main joystick's name: a role on it keeps no `device` in the store.
pub struct Choice<'a> {
    pub device: &'a str,
    pub main: &'a str,
    pub axis: i64,
    pub invert: bool,
    pub dead: f64,
}

/// Sets role `role` to the choice `c`. A role already on that axis of that device gives it up (none): one axis drives
/// one role. The roll role names the main joystick, so when it moves to another device every role still on the main
/// joystick is pinned to it by name first. Unknown roles change nothing (false).
pub fn set_axis(store: &mut Value, map: &Value, role: &str, c: &Choice, soft: bool) -> bool {
    let Some(r) = ROLES.iter().position(|n| *n == role) else { return false };
    let now = axes(store, map, soft);
    fn on<'a>(name: &'a str, main: &'a str) -> &'a str {
        if name.is_empty() { main } else { name }
    }
    let other_device = c.axis >= 0 && on(c.device, c.main) != c.main;
    for (o, other) in ROLES.iter().enumerate() {
        let n = &now[*other];
        let same = n["axis"].as_i64() == Some(c.axis)
            && on(n["device"].as_str().unwrap_or(""), c.main) == on(c.device, c.main);
        let pin = r == 0 && other_device && n["device"] == "" && n["axis"].as_i64() >= Some(0) && !c.main.is_empty();
        if o == r || !(c.axis >= 0 && same || pin) {
            continue;
        }
        let m = section(store, "axes");
        let e = m.entry(*other).or_insert_with(|| json!({}));
        if !e.is_object() {
            *e = json!({}); // a hand-edited entry that is no object
        }
        if c.axis >= 0 && same {
            e["axis"] = (-1).into();
        } else {
            e["axis"] = n["axis"].clone();
            e["device"] = c.main.into();
        }
    }
    // Roll once on a device by name keeps it: that device is the main joystick now, so `c.device == c.main` there.
    let pinned_roll = r == 0 && now["roll"]["device"] != "" && c.axis >= 0 && !c.device.is_empty();
    let dead = c.dead.clamp(0.0, 0.9);
    let mut e = Map::new();
    if other_device || pinned_roll {
        e.insert("axis".into(), c.axis.into());
        e.insert("device".into(), c.device.into());
    } else if c.axis != default_axis(map, r) {
        e.insert("axis".into(), c.axis.into());
    }
    if c.invert {
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

    /// A choice on the main joystick.
    fn ch(axis: i64, invert: bool, dead: f64) -> Choice<'static> {
        Choice { device: "", main: "", axis, invert, dead }
    }

    #[test]
    fn axis_inverted_with_a_dead_zone() {
        let mut s = json!({});
        assert!(set_axis(&mut s, &json!({}), "pitch", &ch(3, true, 0.1), false));
        let a = axes(&s, &json!({}), false);
        assert_eq!(a["pitch"], json!({"axis": 3, "invert": true, "dead": 0.1, "device": ""}));
        assert_eq!(a["rudder"]["axis"], -1, "the rudder gave axis 3 up");
        assert_eq!(a["roll"], json!({"axis": 0, "invert": false, "dead": 0.25, "device": ""}));
        assert_eq!(axes(&s, &json!({}), true)["roll"]["dead"], 0.05, "Soft centre's dead zone is the default then");
        assert!(!set_axis(&mut s, &json!({}), "view", &ch(5, false, 0.0), false), "no such role");
        // Back to the default: the entry goes.
        assert!(set_axis(&mut s, &json!({}), "pitch", &ch(1, false, 0.25), false));
        assert!(s["axes"].get("pitch").is_none());
    }

    #[test]
    fn device_map_sets_the_axes() {
        let map = json!({"match": "Hotas X", "axes": {"rudder": 5}, "buttons": {"2": 7}});
        assert_eq!(axes(&json!({}), &map, false)["rudder"]["axis"], 5);
        let mut s = json!({});
        assert!(set_axis(&mut s, &map, "rudder", &ch(5, false, 0.25), false));
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
        set_axis(&mut s, &json!({}), "throttle", &ch(4, true, 0.0), false);
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
        assert_eq!(
            a["roll"],
            json!({"axis": 0, "invert": false, "dead": 0.9, "device": ""}),
            "a hand-edited store stays in range"
        );
        std::fs::write(&path, "{not json").unwrap();
        assert_eq!(load(&path), json!({}), "a corrupt file is an empty store");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    /// A hand-edited role entry that is no object is replaced when another role takes its axis.
    #[test]
    fn a_role_entry_that_is_no_object_is_replaced() {
        let mut s = json!({"axes": {"pitch": 7}});
        assert!(set_axis(&mut s, &json!({}), "roll", &ch(1, false, 0.25), false));
        assert_eq!(s["axes"]["pitch"], json!({"axis": -1}));
        assert_eq!(axes(&s, &json!({}), false)["roll"]["axis"], 1);
    }

    #[test]
    fn reset_axes_and_drop_old_bindings() {
        let mut s = json!({"keys": {"24": 0x25}, "buttons": {"64": 5}});
        set_axis(&mut s, &json!({}), "roll", &ch(2, false, 0.25), false);
        assert!(drop_bindings(&mut s), "a store from before 2026-11-14 had keys and buttons");
        assert_eq!(s, json!({"axes": {"roll": {"axis": 2}, "throttle": {"axis": -1}}}), "the axes stay");
        assert!(!drop_bindings(&mut s), "none left");
        reset_axes(&mut s);
        assert_eq!(axes(&s, &json!({}), false), axes(&json!({}), &json!({}), false));
    }

    /// A throttle quadrant as a second device: its axis 2 drives the throttle while the stick's axis 2 stays free; a
    /// role on the same axis number of the other device keeps it.
    #[test]
    fn a_role_on_a_second_device() {
        let (stick, quad) = ("Stick", "Throttle Quadrant");
        let on = |device, axis| Choice { device, main: stick, axis, invert: false, dead: 0.0 };
        let mut s = json!({});
        assert!(set_axis(&mut s, &json!({}), "throttle", &on(quad, 0), false));
        let a = axes(&s, &json!({}), false);
        assert_eq!(a["throttle"], json!({"axis": 0, "invert": false, "dead": 0.0, "device": quad}));
        assert_eq!(a["roll"]["axis"], 0, "the stick's axis 0 keeps roll: another device");
        assert_eq!(a["roll"]["device"], "", "roll stays on the main joystick");
        // The quadrant's axis 0 given to the rudder takes it from the throttle.
        assert!(set_axis(&mut s, &json!({}), "rudder", &on(quad, 0), false));
        assert_eq!(axes(&s, &json!({}), false)["throttle"]["axis"], -1);
        // Back on the main joystick by name: no device kept, the default again.
        assert!(set_axis(&mut s, &json!({}), "rudder", &Choice { dead: 0.25, ..on(stick, 3) }, false));
        assert!(s["axes"].get("rudder").is_none());
    }

    /// A second device's buttons get a slot that stays: a new device the next one, a known one its own.
    #[test]
    fn button_slots_stay() {
        let mut s = json!({"axes": {}});
        assert_eq!(button_slot(&mut s, ""), 0, "the main joystick");
        assert_eq!(button_slot(&mut s, "Throttle"), 1);
        assert_eq!(button_slot(&mut s, "Pedals"), 2);
        assert_eq!(button_slot(&mut s, "Throttle"), 1, "known: its slot");
        assert_eq!(button_slot(&mut s, "Throttle #2"), 3, "a second throttle of the same name");
        assert_eq!(button_devices(&s), json!(["Throttle", "Pedals", "Throttle #2"]));
        assert_eq!(button_devices(&json!({"button_devices": [7]})), json!([""]), "a hand-edited entry names none");
        reset_axes(&mut s);
        assert_eq!(
            button_devices(&s).as_array().unwrap().len(),
            3,
            "Reset all keeps the slots: bound buttons use them"
        );
    }

    /// Roll moved to another device makes that one the main joystick: the roles still on the old one are pinned to it.
    #[test]
    fn roll_moved_pins_the_others() {
        let on = |device, axis| Choice { device, main: "Old", axis, invert: false, dead: 0.25 };
        let mut s = json!({});
        assert!(set_axis(&mut s, &json!({}), "roll", &on("New", 0), false));
        let a = axes(&s, &json!({}), false);
        assert_eq!(a["roll"]["device"], "New");
        assert_eq!(a["pitch"]["device"], "Old", "pitch stays on the old stick");
        assert_eq!(a["pitch"]["axis"], 1);
        assert_eq!(a["throttle"]["device"], "Old");
        // Roll tuned on its device, now the main joystick: it keeps the device's name.
        let tune = Choice { main: "New", invert: true, ..on("New", 0) };
        assert!(set_axis(&mut s, &json!({}), "roll", &tune, false));
        assert_eq!(axes(&s, &json!({}), false)["roll"]["device"], "New");
    }
}
