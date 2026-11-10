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

    /// The mission's hold after its goal before it ends, s (the rules' `end_hold_s`).
    #[func]
    fn end_hold_s(&self) -> f64 {
        self.watch.as_ref().map_or(0.0, |w| w.rules.end_hold_s)
    }

    /// This frame's fail reason id ("ejected", a checklist fault, "crash", "damage", "off_pavement"), "" while
    /// nothing failed: `now` = {on_ground, x, y (the jet's centre in the engine frame, m), crashed, damage (0..1),
    /// ejected, fault (a start-up checklist step's fault id, IafFlight.start_step)}. The first reason sticks.
    #[func]
    fn check(&mut self, now: VarDictionary) -> GString {
        let f = |k: &str| now.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0);
        let b = |k: &str| now.get(k).and_then(|v| v.try_to::<bool>().ok()).unwrap_or(false);
        let n = Now {
            on_ground: b("on_ground"),
            x: f("x"),
            y: f("y"),
            crashed: b("crashed"),
            damage: f("damage"),
            ejected: b("ejected"),
            fault: now.get("fault").map(|v| v.to_string()).and_then(|f| training::string_id(&f)),
        };
        if self.failed.is_none() {
            self.failed = self.watch.as_ref().and_then(|w| w.check(&n));
        }
        GString::from(self.failed.unwrap_or(""))
    }

    /// The radio menu's calls that fit now, in menu order ("startup", "taxi", "takeoff", "landing";
    /// `training::radio_calls`): `now` = {on_ground, engine_on, avionics, lineup_m (to the near tower's lineup
    /// point; absent near no tower), hold_m (its holding point's distance to it; absent: HOLDING_POINT_M), answers
    /// (the tower's answer templates so far), hot (a ground start with the engine running)}.
    #[func]
    fn radio_calls(now: VarDictionary) -> PackedStringArray {
        let b = |k: &str| now.get(k).and_then(|v| v.try_to::<bool>().ok()).unwrap_or(false);
        let s = training::RadioNow {
            on_ground: b("on_ground"),
            engine_on: b("engine_on"),
            avionics: b("avionics"),
            hot: b("hot"),
            lineup_m: now.get("lineup_m").and_then(|v| v.try_to::<f64>().ok()).unwrap_or(f64::INFINITY),
            hold_m: now.get("hold_m").and_then(|v| v.try_to::<f64>().ok()).unwrap_or(training::HOLDING_POINT_M),
            answers: now
                .get("answers")
                .and_then(|v| v.try_to::<PackedStringArray>().ok())
                .map_or(vec![], |a| a.as_slice().iter().map(|s| s.to_string()).collect()),
        };
        training::radio_calls(&s).into_iter().map(GString::from).collect()
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
