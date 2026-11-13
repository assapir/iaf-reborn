//! `IafTraining`: Modern IAF's training scorer (`iaf_tools::training`, modern-iaf/docs/training.md) for the game: the
//! live check that ends a training run at once on a fail, and the score at its end on the flight's recording.

use godot::prelude::*;
use iaf_tools::training::{self, Now, Watch};
use std::path::Path;

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafTraining {
    watch: Option<Watch>,
    /// The live check's fail reason, once it found one.
    failed: Option<&'static str>,
}

#[godot_api]
impl IafTraining {
    /// Opens the run of the readable mission file `mission` with the airbase files in `airbases` (absolute paths):
    /// its rules and its base's pavement. "" when opened, else the error.
    #[func]
    fn open(&mut self, mission: GString, airbases: GString) -> GString {
        match Watch::open(Path::new(&mission.to_string()), Path::new(&airbases.to_string())) {
            Ok(w) => {
                self.watch = Some(w);
                GString::new()
            }
            Err(e) => GString::from(format!("{e:#}").as_str()),
        }
    }

    /// How long a fail shows its reason before the debrief, s (the rules' `end_hold_s`).
    #[func]
    fn end_hold_s(&self) -> f64 {
        self.watch.as_ref().map_or(0.0, |w| w.rules.end_hold_s)
    }

    /// This frame's fail reason id ("ejected", a checklist fault, "crash", "damage", "off_pavement", "wrong_runway"
    /// (the roll on another runway end), a phase without the tower's clearance: "no_start_clearance" …), "" while
    /// nothing failed: `now` = {on_ground, x, y (the jet's centre in the engine frame, m), crashed, damage (0..1),
    /// ejected, fault (a start-up checklist step's fault id, IafFlight.start_step), rpm (%), speed_kt, heading (deg,
    /// the engine frame's), answers (the tower's answer templates so far), hot (the flight started with the engine
    /// running)}. The first reason sticks.
    #[func]
    fn check(&mut self, now: VarDictionary) -> GString {
        let n = now_of(&now);
        if self.failed.is_none() {
            self.failed = self.watch.as_mut().and_then(|w| w.check(&n));
        }
        GString::from(self.failed.unwrap_or(""))
    }

    /// The runway end the jet is lined up on when it is not the mission's ("07L"; `training::Watch::wrong_runway`),
    /// "" otherwise: `now` as check's.
    #[func]
    fn wrong_runway(&self, now: VarDictionary) -> GString {
        let w = self.watch.as_ref().and_then(|w| w.wrong_runway(&now_of(&now)));
        GString::from(w.unwrap_or_default().as_str())
    }

    /// The mission's runway end ("25R", the airbase file's designator), "" for none.
    #[func]
    fn runway(&self) -> GString {
        GString::from(self.watch.as_ref().map_or("", |w| w.runway_designator()))
    }

    /// The radio menu's calls, in menu order (`training::radio_calls`: "startup", "taxi", "lineup", "takeoff" on the
    /// ground, "landing" in the air): `now` as next_call's.
    #[func]
    fn radio_calls(now: VarDictionary) -> PackedStringArray {
        training::radio_calls(&radio_now(&now)).into_iter().map(GString::from).collect()
    }

    /// The call the moment expects next ("" none; `training::next_call`), marked in the menu: `now` = {on_ground,
    /// engine_on, avionics, lineup_m (to the near tower's lineup point; absent near no tower), hold_m (its holding
    /// point's distance to it; absent: HOLDING_POINT_M), answers (the tower's answer templates so far), hot (a ground
    /// start with the engine running)}.
    #[func]
    fn next_call(now: VarDictionary) -> GString {
        GString::from(training::next_call(&radio_now(&now)).unwrap_or(""))
    }

    /// The ground call `id` needs first while its clearance is missing ("taxi" before "lineup" …;
    /// `training::missing_before`), "" none: `answers` the tower's answer templates so far, `hot` a start with the
    /// engine running.
    #[func]
    fn missing_before(id: GString, answers: PackedStringArray, hot: bool) -> GString {
        let a: Vec<String> = answers.as_slice().iter().map(|s| s.to_string()).collect();
        GString::from(training::missing_before(&id.to_string(), &a, hot).unwrap_or(""))
    }

    /// The debrief string `id` in `lang` ("en" / "he"; a checklist fault for the card), "" when unknown.
    #[func]
    fn text(id: GString, lang: GString) -> GString {
        GString::from(training::text(&id.to_string(), &lang.to_string()))
    }

    /// The debrief record (training.md §4) of the recording `flight` against the readable mission file `mission`
    /// with the airbase files in `airbases` (absolute paths), as JSON text; `{"error": …}` when it cannot be scored.
    /// A live check's fail comes first.
    #[func]
    fn score(&self, flight: GString, mission: GString, airbases: GString) -> GString {
        let p = |s: &GString| s.to_string();
        let out = match training::score_files(Path::new(&p(&flight)), Path::new(&p(&mission)), Path::new(&p(&airbases)))
        {
            Ok(mut d) => {
                if let Some(r) = self.failed {
                    d.fail_first(r);
                }
                d.to_json()
            }
            Err(e) => serde_json::json!({ "error": format!("{e:#}") }),
        };
        GString::from(out.to_string().as_str())
    }
}

/// `now["answers"]`: the tower's answer templates so far.
fn answers(now: &VarDictionary) -> Vec<String> {
    now.get("answers")
        .and_then(|v| v.try_to::<PackedStringArray>().ok())
        .map_or(vec![], |a| a.as_slice().iter().map(|s| s.to_string()).collect())
}

/// A frame of the run (`check`'s `now`).
fn now_of(now: &VarDictionary) -> Now {
    let f = |k: &str| now.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0);
    let b = |k: &str| now.get(k).and_then(|v| v.try_to::<bool>().ok()).unwrap_or(false);
    Now {
        on_ground: b("on_ground"),
        x: f("x"),
        y: f("y"),
        crashed: b("crashed"),
        damage: f("damage"),
        ejected: b("ejected"),
        fault: now.get("fault").map(|v| v.to_string()).and_then(|f| training::string_id(&f)),
        rpm: f("rpm"),
        speed_kt: f("speed_kt"),
        heading: f("heading"),
        cleared: training::Cleared::of(&answers(now), b("hot")),
    }
}

/// The radio menu's moment (`radio_calls`' `now`).
fn radio_now(now: &VarDictionary) -> training::RadioNow {
    let b = |k: &str| now.get(k).and_then(|v| v.try_to::<bool>().ok()).unwrap_or(false);
    training::RadioNow {
        on_ground: b("on_ground"),
        engine_on: b("engine_on"),
        avionics: b("avionics"),
        hot: b("hot"),
        lineup_m: now.get("lineup_m").and_then(|v| v.try_to::<f64>().ok()).unwrap_or(f64::INFINITY),
        hold_m: now.get("hold_m").and_then(|v| v.try_to::<f64>().ok()).unwrap_or(training::HOLDING_POINT_M),
        answers: answers(now),
    }
}
