//! Modern IAF's combat logbook (modern-iaf/docs/storage.md §5, front-end.md §3): what one flight did in combat, counted
//! from its recording's events (docs/blackbox.schema.json), and the sums over many flights for the Pilot screen.
//!
//! The recorder's events it reads:
//! - `kill` {record, air, shared}: a unit the player destroyed, or one a friendly destroyed after the player hit it
//!   (`shared`: a friendly unit hit it too). `record` is the unit's record id (`mig29a`) or its part name
//!   (`5P85TE2`).
//! - `fire` {weapon, n, gun}: the player released `n` of `weapon` (its record name, `AIM-120`); `gun` for rounds.
//! - `impact` {weapon, n}: `n` of the player's rounds or weapons that burst on an enemy unit (a hit).
//! - `shot_down` {by}, `crash`, `eject`: the player's jet lost; `by` = `sam`, `aaa` or `fighter`.
//! - `lost` {by}: a wingman's jet lost, `by` as above or `crashed`.
//!
//! The record (the debrief's `combat`, the sortie's `combat` column):
//! `{"kills": {unit: n}, "shared": {unit: n}, "ground": {unit: n}, "weapons": {name: {"fired", "hits", "gun"}},
//!   "lost": {cause: n}, "ejected": n, "wingmen_lost": n}`; empty (`{}`) for a flight without combat.

use serde_json::{Map, Value, json};

/// A loss's causes, in the order the screens list them.
pub const CAUSES: [&str; 4] = ["sam", "aaa", "fighter", "crashed"];

fn add(m: &mut Value, path: &[&str], n: i64) {
    let mut v = m;
    for k in path {
        if !v.is_object() {
            *v = json!({});
        }
        v = v.as_object_mut().expect("object").entry(k.to_string()).or_insert(json!(0));
    }
    *v = json!(v.as_i64().unwrap_or(0) + n);
}

/// The combat record of one flight from its events (above). The player's own jet counts once however it went: shot
/// down (its cause), else crashed (a crash, or an ejection from a jet nothing hit).
pub fn count(events: &[Value]) -> Value {
    let mut r = json!({});
    let s = |e: &Value, k: &str| e[k].as_str().unwrap_or("").to_string();
    let mut own: Option<String> = None;
    for e in events {
        match e["event"].as_str() {
            Some("kill") => {
                let unit = s(e, "record");
                let unit = if unit.is_empty() { "?".to_string() } else { unit };
                if e["air"].as_bool().unwrap_or(false) {
                    add(&mut r, &["kills", unit.as_str()], 1);
                    if e["shared"].as_bool().unwrap_or(false) {
                        add(&mut r, &["shared", unit.as_str()], 1);
                    }
                } else {
                    add(&mut r, &["ground", unit.as_str()], 1);
                }
            }
            Some(k @ ("fire" | "impact")) => {
                let w = s(e, "weapon");
                let n = e["n"].as_i64().unwrap_or(1);
                add(&mut r, &["weapons", w.as_str(), if k == "fire" { "fired" } else { "hits" }], n);
                if e["gun"].as_bool().unwrap_or(false) {
                    r["weapons"][w.as_str()]["gun"] = json!(true);
                }
            }
            Some("shot_down") => {
                if own.as_deref().is_none_or(|c| c == "crashed") {
                    own = Some(cause(&s(e, "by")));
                }
            }
            Some("crash") if own.is_none() => own = Some("crashed".into()),
            Some("eject") => {
                add(&mut r, &["ejected"], 1);
                if own.is_none() {
                    own = Some("crashed".into());
                }
            }
            Some("lost") => {
                add(&mut r, &["lost", cause(&s(e, "by")).as_str()], 1);
                add(&mut r, &["wingmen_lost"], 1);
            }
            _ => {}
        }
    }
    if let Some(c) = own {
        add(&mut r, &["lost", &c], 1);
    }
    for w in r.get_mut("weapons").and_then(Value::as_object_mut).into_iter().flat_map(|m| m.values_mut()) {
        for k in ["fired", "hits"] {
            if w[k].is_null() {
                w[k] = json!(0);
            }
        }
    }
    r
}

fn cause(by: &str) -> String {
    if CAUSES.contains(&by) { by } else { "crashed" }.to_string()
}

/// Whether a record holds any combat (a flight that fired, destroyed or lost something).
pub fn is_combat(r: &Value) -> bool {
    r.as_object().is_some_and(|m| !m.is_empty())
}

/// The records summed into one (the logbook's every flight).
pub fn sum<'a>(records: impl IntoIterator<Item = &'a Value>) -> Value {
    let mut out = json!({});
    for r in records {
        for (k, v) in r.as_object().into_iter().flatten() {
            match v {
                Value::Number(n) => add(&mut out, &[k.as_str()], n.as_i64().unwrap_or(0)),
                Value::Object(m) => {
                    for (id, x) in m {
                        if let Some(o) = x.as_object() {
                            for (f, n) in o {
                                match n {
                                    Value::Bool(b) => out[k][id][f] = json!(*b),
                                    _ => add(&mut out, &[k.as_str(), id.as_str(), f.as_str()], n.as_i64().unwrap_or(0)),
                                }
                            }
                        } else {
                            add(&mut out, &[k.as_str(), id.as_str()], x.as_i64().unwrap_or(0));
                        }
                    }
                }
                _ => {}
            }
        }
    }
    out
}

fn total(r: &Value, k: &str) -> i64 {
    r[k].as_object().map_or(0, |m| m.values().filter_map(Value::as_i64).sum())
}

/// The four totals the logbook and the debrief show: `air_kills` (with `shared`), `ground`, `hits` of `fired` (the
/// weapons, the gun's rounds left out: a burst is hundreds), and `lost` (`shot_down` + `crashed`).
pub fn totals(r: &Value) -> Value {
    let (mut fired, mut hits) = (0, 0);
    for w in r["weapons"].as_object().into_iter().flat_map(Map::values) {
        if !w["gun"].as_bool().unwrap_or(false) {
            fired += w["fired"].as_i64().unwrap_or(0);
            hits += w["hits"].as_i64().unwrap_or(0);
        }
    }
    let crashed = r["lost"]["crashed"].as_i64().unwrap_or(0);
    json!({
        "air_kills": total(r, "kills"),
        "shared": total(r, "shared"),
        "ground": total(r, "ground"),
        "fired": fired,
        "hits": hits,
        "lost": total(r, "lost"),
        "shot_down": total(r, "lost") - crashed,
        "crashed": crashed,
    })
}

/// The More stats page's lists from record `r`, each sorted by count (most first), then by name:
/// `kills` [[unit, n, shared]], `ground` [[unit, n]], `weapons` [[name, fired, hits, gun]] (the gun last), `lost`
/// [[cause, n]] in CAUSES' order (the causes with none left out), `ejected`, `wingmen_lost`.
pub fn lists(r: &Value) -> Value {
    let by_count = |k: &str| -> Vec<(String, i64)> {
        let mut v: Vec<(String, i64)> =
            r[k].as_object().into_iter().flatten().map(|(id, n)| (id.clone(), n.as_i64().unwrap_or(0))).collect();
        v.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        v
    };
    let kills: Vec<Value> =
        by_count("kills").into_iter().map(|(u, n)| json!([u, n, r["shared"][&u].as_i64().unwrap_or(0)])).collect();
    let ground: Vec<Value> = by_count("ground").into_iter().map(|(u, n)| json!([u, n])).collect();
    let mut weapons: Vec<(String, i64, i64, bool)> = r["weapons"]
        .as_object()
        .into_iter()
        .flatten()
        .map(|(id, w)| {
            let n = |k: &str| w[k].as_i64().unwrap_or(0);
            (id.clone(), n("fired"), n("hits"), w["gun"].as_bool().unwrap_or(false))
        })
        .collect();
    weapons.sort_by(|a, b| a.3.cmp(&b.3).then(b.1.cmp(&a.1)).then(a.0.cmp(&b.0)));
    let lost: Vec<Value> =
        CAUSES.iter().filter_map(|c| r["lost"][*c].as_i64().filter(|n| *n > 0).map(|n| json!([c, n]))).collect();
    json!({
        "kills": kills,
        "ground": ground,
        "weapons": weapons.into_iter().map(|(id, f, h, g)| json!([id, f, h, g])).collect::<Vec<_>>(),
        "lost": lost,
        "ejected": r["ejected"].as_i64().unwrap_or(0),
        "wingmen_lost": r["wingmen_lost"].as_i64().unwrap_or(0),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ev(v: &[Value]) -> Value {
        count(v)
    }

    #[test]
    fn kills_shared_and_ground_by_type() {
        let r = ev(&[
            json!({"event": "kill", "record": "mig29a", "air": true}),
            json!({"event": "kill", "record": "mig29a", "air": true, "shared": true}),
            json!({"event": "kill", "record": "5P85TE2", "air": false}),
            json!({"event": "kill", "record": "target_t72", "air": false}),
            json!({"event": "kill", "record": "target_t72", "air": false}),
            json!({"event": "radio", "id": "x"}),
        ]);
        assert_eq!(r["kills"], json!({"mig29a": 2}));
        assert_eq!(r["shared"], json!({"mig29a": 1}));
        assert_eq!(r["ground"], json!({"5P85TE2": 1, "target_t72": 2}));
        let t = totals(&r);
        assert_eq!((t["air_kills"].as_i64(), t["shared"].as_i64(), t["ground"].as_i64()), (Some(2), Some(1), Some(3)));
        assert_eq!(lists(&r)["ground"], json!([["target_t72", 2], ["5P85TE2", 1]]));
    }

    #[test]
    fn weapons_fired_and_hits_gun_apart() {
        let r = ev(&[
            json!({"event": "fire", "weapon": "AIM-120", "n": 1}),
            json!({"event": "fire", "weapon": "AIM-120", "n": 1}),
            json!({"event": "impact", "weapon": "AIM-120", "n": 1}),
            json!({"event": "fire", "weapon": "20 MM", "n": 180, "gun": true}),
            json!({"event": "impact", "weapon": "20 MM", "n": 3, "gun": true}),
            json!({"event": "fire", "weapon": "GBU-31", "n": 2}),
        ]);
        assert_eq!(r["weapons"]["AIM-120"], json!({"fired": 2, "hits": 1}));
        assert_eq!(r["weapons"]["GBU-31"], json!({"fired": 2, "hits": 0}));
        let t = totals(&r);
        assert_eq!((t["fired"].as_i64(), t["hits"].as_i64()), (Some(4), Some(1)), "the gun's rounds left out");
        let w = &lists(&r)["weapons"];
        assert_eq!(w[0], json!(["AIM-120", 2, 1, false]));
        assert_eq!(w[2], json!(["20 MM", 180, 3, true]), "the gun last");
    }

    #[test]
    fn own_jet_counts_once_wingmen_by_cause() {
        // Shot down by a SAM, then the crash and the ejection: one jet, by the SAM, one ejection.
        let r = ev(&[
            json!({"event": "shot_down", "by": "sam"}),
            json!({"event": "eject", "short": false}),
            json!({"event": "crash", "reason": "terrain"}),
            json!({"event": "lost", "by": "fighter"}),
            json!({"event": "lost", "by": ""}),
        ]);
        assert_eq!(r["lost"], json!({"sam": 1, "fighter": 1, "crashed": 1}));
        assert_eq!((r["ejected"].as_i64(), r["wingmen_lost"].as_i64()), (Some(1), Some(2)));
        let t = totals(&r);
        assert_eq!((t["lost"].as_i64(), t["shot_down"].as_i64(), t["crashed"].as_i64()), (Some(3), Some(2), Some(1)));
        assert_eq!(lists(&r)["lost"], json!([["sam", 1], ["fighter", 1], ["crashed", 1]]));
        // An ejection from a jet nothing hit: the jet crashed.
        assert_eq!(ev(&[json!({"event": "eject"})])["lost"], json!({"crashed": 1}));
        // A crash, then a shot_down (the hit came first in time but logged after): the hit's cause.
        assert_eq!(
            ev(&[json!({"event": "crash"}), json!({"event": "shot_down", "by": "aaa"})])["lost"],
            json!({"aaa": 1})
        );
    }

    #[test]
    fn no_combat_and_sums() {
        let none = ev(&[json!({"event": "radio"}), json!({"event": "touchdown"})]);
        assert!(!is_combat(&none));
        let a = ev(&[
            json!({"event": "kill", "record": "mig29a", "air": true}),
            json!({"event": "fire", "weapon": "AIM-120"}),
        ]);
        let b = ev(&[
            json!({"event": "kill", "record": "mig29a", "air": true, "shared": true}),
            json!({"event": "fire", "weapon": "20 MM", "n": 50, "gun": true}),
            json!({"event": "lost", "by": "sam"}),
        ]);
        let s = sum([&a, &b, &none]);
        assert_eq!(s["kills"], json!({"mig29a": 2}));
        assert_eq!(s["shared"], json!({"mig29a": 1}));
        assert_eq!(s["weapons"]["20 MM"], json!({"fired": 50, "hits": 0, "gun": true}));
        assert_eq!(s["weapons"]["AIM-120"], json!({"fired": 1, "hits": 0}));
        assert_eq!((s["lost"]["sam"].as_i64(), s["wingmen_lost"].as_i64()), (Some(1), Some(1)));
    }
}
