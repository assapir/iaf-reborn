//! A Modern IAF mission's flights for its briefing (modern-iaf/docs/front-end.md §10), from a readable mission
//! (modern-iaf/data/missions, data-formats.md §5).
//!
//! The flights are the player's (Kidon 1: the mission's `start` and `route`) and the mission's other `flights`
//! (Kidon 2..4), in the order the compiler (`sim.rs compile_mission`) hands them to the mission editor's `set_flight`
//! (which names their formations `mission_edit::FLIGHT_NAMES`). The callsigns are kidon style (the user, 20 November
//! 2026: "Use kidon style, where kidon 1 is the first formation the second is kidon 2 etc"; he.wikipedia טיסת מבנה,
//! modern-iaf/docs/research/radio-terms.md): flight N is "Kidon N", its jets "Kidon N-1"...

use std::path::Path;

use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};

use crate::sim::place;

/// The flights' callsigns, the player's first.
pub const CALLSIGNS: [&str; 4] = ["Kidon 1", "Kidon 2", "Kidon 3", "Kidon 4"];

/// A flight's tasks (its `task`): the briefing names each ("task_<id>" in the front end's strings).
pub const TASKS: [&str; 4] = ["training", "cap", "strike", "escort"];

/// A flight of a mission.
#[derive(Debug, Clone, PartialEq)]
pub struct Flight {
    /// "Kidon 1" (the player's), "Kidon 2", …
    pub callsign: &'static str,
    /// Its unit record's id ("f16i") and how many jets fly in it.
    pub unit: String,
    pub count: i64,
    /// One of [`TASKS`].
    pub task: String,
    /// Its start (UTM 36N; None for the player's, which starts at the mission's base: `briefing.rs`) and its waypoints.
    pub start: Option<[f64; 2]>,
    pub route: Vec<[f64; 2]>,
    /// Its loadout: the unit record's own pylon stores by store, in station order (id, count); the player's flies the
    /// pilot's own (the briefing's Arming page).
    pub stores: Vec<(String, i64)>,
}

impl Flight {
    /// The player's flight (Kidon 1) is the first.
    pub fn player(&self) -> bool {
        self.callsign == CALLSIGNS[0]
    }

    /// As JSON: {callsign, unit, count, task, player, start (null or [x, y]), route [[x, y], …] (UTM 36N, m),
    /// stores [{weapon, count}]}.
    pub fn to_json(&self) -> Value {
        let r = |p: &[f64; 2]| json!([p[0].round(), p[1].round()]);
        json!({
            "callsign": self.callsign,
            "unit": self.unit,
            "count": self.count,
            "task": self.task,
            "player": self.player(),
            "start": self.start.as_ref().map(r),
            "route": self.route.iter().map(r).collect::<Vec<_>>(),
            "stores": self.stores.iter().map(|(w, n)| json!({"weapon": w, "count": n})).collect::<Vec<_>>(),
        })
    }
}

/// The flights of readable mission `m`, the player's first; `record` answers a unit record by its id (None: no
/// stores). A flight's `task` (Kidon 1's in `start`) defaults to "training" in a training mission and is needed in any
/// other; an unknown task, or more flights than `set_flight` names, is refused.
pub fn flights(m: &Value, record: impl Fn(&str) -> Option<Value>) -> Result<Vec<Flight>> {
    let others = m["flights"].as_array().map_or(&[][..], Vec::as_slice);
    ensure!(others.len() < CALLSIGNS.len(), "{} flights besides Kidon 1; set_flight takes 3 more", others.len());
    let training = m["category"] == "training";
    let mut out = vec![];
    for (k, f) in [&m["start"]].into_iter().chain(others).enumerate() {
        let callsign = CALLSIGNS[k];
        let task = match f["task"].as_str() {
            Some(t) => t,
            None if training => "training",
            None => anyhow::bail!("{callsign}: a flight needs \"task\" outside a training mission"),
        };
        ensure!(TASKS.contains(&task), "{callsign}: no task \"{task}\" ({})", TASKS.join(", "));
        let unit = f["unit"].as_str().with_context(|| format!("{callsign}: a flight needs \"unit\""))?;
        // The player's waypoints are the mission's `route`; another flight's its own, from its own start.
        let (start, route) =
            if k == 0 { (None, &m["route"]) } else { (Some(place(&f["start"], callsign)?), &f["route"]) };
        let route = route.as_array().into_iter().flatten().map(|p| place(p, callsign)).collect::<Result<_>>()?;
        let mut stores: Vec<(String, i64)> = vec![];
        if let Some(r) = record(unit) {
            for p in r["pylons"].as_object().into_iter().flat_map(|o| o.values()) {
                let (Some(w), n) = (p["weapon"].as_str(), p["count"].as_i64().unwrap_or(1)) else { continue };
                match stores.iter_mut().find(|s| s.0 == w) {
                    Some(s) => s.1 += n,
                    None => stores.push((w.to_string(), n)),
                }
            }
        }
        out.push(Flight {
            callsign,
            unit: unit.to_string(),
            count: f["count"].as_i64().unwrap_or(if k == 0 { 1 } else { 2 }),
            task: task.to_string(),
            start,
            route,
            stores,
        });
    }
    Ok(out)
}

/// [`flights`] of the readable mission file `mission` with the unit records in `units` (`data/db/units`).
pub fn flights_files(mission: &Path, units: &Path) -> Result<Vec<Flight>> {
    flights(&read(mission)?, |u| read(&units.join(format!("{u}.json"))).ok())
}

fn read(p: &Path) -> Result<Value> {
    Ok(serde_json::from_slice(&std::fs::read(p).with_context(|| p.display().to_string())?)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn data() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data")
    }

    fn mission(name: &str) -> Value {
        read(&data().join(format!("missions/{name}.json"))).unwrap()
    }

    fn units(u: &str) -> Option<Value> {
        read(&data().join(format!("db/units/{u}.json"))).ok()
    }

    /// The two-flight sample mission (test data, not a shipped mission): Ramon's take-off with a pair of F-15Cs on CAP.
    fn two_flights() -> Value {
        read(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/tests/data/two_flights.json")).unwrap()
    }

    #[test]
    fn a_shipped_mission_has_one_flight_the_players() {
        let f = flights(&mission("ramon_takeoff"), units).unwrap();
        assert_eq!(f.len(), 1);
        let a = &f[0];
        assert!(a.player() && a.callsign == "Kidon 1" && a.unit == "f16i" && a.count == 1 && a.task == "training");
        assert_eq!(a.start, None);
        assert_eq!(a.route.len(), 1);
        // The Sufa record's pylons: six AIM-9Ms and two tanks, in station order.
        assert_eq!(a.stores, [("aim-9m".to_string(), 6), ("tank-370".to_string(), 2)]);
        assert_eq!(a.to_json()["player"], true);
    }

    #[test]
    fn the_sample_has_two_flights_each_with_its_own_route() {
        let f = flights(&two_flights(), units).unwrap();
        assert_eq!(f.iter().map(|f| f.callsign).collect::<Vec<_>>(), ["Kidon 1", "Kidon 2"]);
        let b = &f[1];
        assert!(!b.player() && b.unit == "f15c" && b.count == 2 && b.task == "cap");
        assert!(b.start.is_some() && b.route.len() == 2);
        // The F-15C's record hangs nothing on its pylons.
        assert!(b.stores.is_empty());
    }

    #[test]
    fn tasks_are_checked() {
        let mut m = two_flights();
        m["flights"][0]["task"] = json!("bingo");
        assert!(flights(&m, units).unwrap_err().to_string().contains("no task \"bingo\""));
        // Outside training a flight names its task.
        let mut m = two_flights();
        m["category"] = json!("single");
        m["start"]["task"] = json!("cap");
        m["flights"][0].as_object_mut().unwrap().remove("task");
        assert!(flights(&m, units).unwrap_err().to_string().contains("Kidon 2: a flight needs \"task\""));
        let mut m = two_flights();
        let b = m["flights"][0].clone();
        m["flights"] = json!([b, b, b, b]);
        assert!(flights(&m, units).unwrap_err().to_string().contains("4 flights"));
    }

    #[test]
    fn the_files_wrapper_reads_the_records() {
        let f = flights_files(&data().join("missions/ramon_takeoff.json"), &data().join("db/units")).unwrap();
        assert_eq!(f, flights(&mission("ramon_takeoff"), units).unwrap());
        assert!(flights_files(&data().join("missions/gone.json"), &data().join("db/units")).is_err());
    }
}
