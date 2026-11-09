//! Modern IAF's training scoring (iaf-2026/docs/training.md): a recorded flight (the blackbox JSONL,
//! docs/blackbox.schema.json) scored against a training mission (`iaf-2026/data/missions/<id>.json`, its
//! `"training"` rules) into a debrief record with English and Hebrew strings keyed by id.
//!
//! - every mission: a crash, any damage or the wheels off the pavement fails it at once (the recorder's `crash`, `hit`
//!   and `surface` events; the game's live check is `Watch`);
//! - start-up (`"kind": "startup"`): pass when the engine reaches idle with the avionics up within the time budget;
//! - take-off (`"kind": "takeoff"`): pass when airborne with the gear up on the runway heading ± the tolerance, from
//!   the mission's runway, with no runway excursion, within the time budget.
//!
//! The record keeps every number; the rules' `goals` name the few the debrief sheet shows.
//!
//! Positions: the recorder logs scene metres (x east, z south) from the terrain's origin; the scorer turns them into
//! the engine frame (origin.x + x, origin.y − z) and the airbase file's runway ends into the same frame, UTM 36N, as
//! the mission compiler places them (`sim.rs place`), so headings compare with the recorded ones directly.

use anyhow::{Context, Result, bail, ensure};
use serde_json::{Map, Value, json};

use crate::sim;
use crate::sim_bases::{self, Base};

/// The flight model's ground start: the RPM winds up from 0 at 15 %/s to the 60 % idle (docs/flight-model.md
/// §10.2), so idle comes 4 s after the engine starts. Used while the recorder has no RPM column.
const IDLE_WINDUP_S: f64 = 60.0 / 15.0;
/// The model's idle RPM, % (docs/flight-model.md §10.2), for a recording with an "rpm" column.
const IDLE_RPM: f64 = 60.0;
/// The take-off roll starts at the slowest point before the jet last passes this speed ahead of the lift-off
/// (inferred: above taxi speed).
const ROLL_START_KT: f64 = 30.0;
/// A lift-off holds the jet off the ground this long (inferred: longer than a bump while taxiing).
const LIFTOFF_HOLD_S: f64 = 1.0;
/// Rotation: the first moment of the roll the pitch is this much above the pitch at the roll's start (inferred).
const ROTATION_PITCH_DEG: f64 = 2.0;
/// A throttle step smaller than this between two samples is noise, not a movement.
const THROTTLE_STEP: f64 = 0.005;

// --- Strings ----------------------------------------------------------------------------------------------------------

/// Every debrief string: (id, English, Hebrew).
const STRINGS: &[(&str, &str, &str)] = &[
    ("pass", "Pass", "עבר"),
    ("fail", "Fail", "נכשל"),
    ("startup", "Start-up", "התנעה"),
    ("takeoff", "Take-off", "המראה"),
    // Fail reasons.
    ("no_start", "The engine never started.", "המנוע לא הותנע."),
    ("over_time", "Not done within the time budget.", "לא הושלם בזמן שהוקצב."),
    ("no_liftoff", "The jet never left the ground.", "המטוס לא המריא."),
    ("ejected", "The pilot ejected.", "בוצע מילוט מהמטוס."),
    ("crash", "The jet crashed.", "המטוס התרסק."),
    ("damage", "The jet was damaged.", "המטוס נפגע."),
    ("off_pavement", "The jet left the pavement.", "המטוס ירד מהמשטח הסלול."),
    ("not_done", "The engine never reached idle with the avionics up.", "המנוע לא הגיע לסרק עם אוויוניקה פועלת."),
    // The start-up checklist's faults (iaf_flight start.rs `press`) and skipped steps.
    ("no_power", "The starter had no power: the main power was off.", "למתנע לא היה מתח: המתח הראשי היה כבוי."),
    (
        "hot_start",
        "Hot start: the throttle went to idle below 20 % RPM; the engine was shut down.",
        "התנעה חמה: המצערת הועברה לסרק מתחת ל־20% סל״ד; המנוע כובה.",
    ),
    (
        "no_rotation",
        "No light-off: the throttle went to idle with the engine not turning.",
        "אין הצתה: המצערת הועברה לסרק כשהמנוע לא הסתובב.",
    ),
    ("no_ipp", "Engine start without the IPP running.", "התנעת מנוע בלי שה־IPP פועל."),
    ("ipp_not_ready", "Engine start before the IPP was up to speed.", "התנעת מנוע לפני שה־IPP הגיע למהירות."),
    (
        "avionics_early",
        "Avionics power on before the generators: no power for them.",
        "מתח אוויוניקה הופעל לפני הגנרטורים: לא היה להם מתח.",
    ),
    ("ins_no_power", "INS alignment without avionics power.", "יישור הניווט האינרציאלי ללא מתח אוויוניקה."),
    ("skip_main_power", "Skipped: main power.", "לא בוצע: מתח ראשי."),
    ("skip_starter", "Skipped: the starter.", "לא בוצע: המתנע."),
    ("skip_engine", "Skipped: the engine start.", "לא בוצע: התנעת המנוע."),
    ("skip_avionics", "Skipped: avionics power.", "לא בוצע: מתח אוויוניקה."),
    ("skip_ins", "Skipped: INS alignment.", "לא בוצע: יישור הניווט האינרציאלי."),
    ("skip_canopy", "Skipped: the canopy.", "לא בוצע: החופה."),
    ("wrong_runway", "The take-off was not from the assigned runway.", "ההמראה לא הייתה מהמסלול שהוקצה."),
    ("excursion", "The jet left the runway during the take-off roll.", "המטוס יצא מהמסלול בזמן ריצת ההמראה."),
    ("gear_down", "The gear was never raised.", "כן הנסע לא נאסף."),
    ("off_heading", "Not on the runway heading with the gear up.", "לא בכיוון המסלול עם כן נסע אסוף."),
    // Debrief items.
    ("runway", "Runway", "מסלול"),
    ("time_to_idle", "Time to idle", "זמן עד סרק"),
    ("time_to_avionics", "Time to avionics up", "זמן עד הפעלת האוויוניקה"),
    ("throttle_moves", "Throttle movements", "הזזות מצערת"),
    ("faults", "Faults", "תקלות"),
    ("taxi_time", "Taxi time", "זמן הסעה"),
    ("lineup_heading_error", "Lineup heading error", "סטיית כיוון בהתייצבות"),
    ("roll_start_from_runway_start", "Roll start from the runway start", "תחילת ריצת ההמראה מתחילת המסלול"),
    ("roll_length", "Take-off roll", "אורך ריצת ההמראה"),
    ("runway_left", "Runway left at lift-off", "מסלול שנותר בניתוק"),
    ("rotation_speed", "Rotation speed", "מהירות הרמת האף"),
    ("liftoff_speed", "Lift-off speed", "מהירות ניתוק"),
    ("reference_speed", "Reference take-off speed at this weight", "מהירות המראה מומלצת במשקל זה"),
    ("gross_weight", "Gross weight at lift-off", "משקל כולל בניתוק"),
    ("gear_up_height", "Gear-up height", "גובה איסוף כן הנסע"),
    ("gear_up_time", "Gear-up time after lift-off", "זמן איסוף כן הנסע מהניתוק"),
    ("roll_heading_deviation", "Heading deviation during the roll", "סטיית כיוון בזמן ריצת ההמראה"),
    ("max_centreline_offset", "Max offset from the centreline", "סטייה מרבית מקו המרכז"),
    ("tower_calls", "Tower calls", "קריאות למגדל"),
    ("cut_lines", "Lines cut off at the recording's end, skipped", "שורות קטועות בסוף ההקלטה, שהושמטו"),
    // Notes in place of a value.
    ("none_modelled", "none modelled", "לא ממודל"),
    ("from_spool", "from the engine start and the model's wind-up", "מהתנעת המנוע וזמן ההאצה של המודל"),
    ("with_idle", "with the engine at idle: no avionics column", "עם המנוע בסרק: אין עמודת אוויוניקה"),
    ("not_reached", "not reached", "לא הושג"),
];

fn en(id: &str) -> &'static str {
    STRINGS.iter().find(|s| s.0 == id).map_or("?", |s| s.1)
}

// --- The rules -------------------------------------------------------------------------------------------------------

/// A training mission's pass / fail rules (the mission file's `"training"`, iaf-2026/docs/data-formats.md §5).
#[derive(Debug, Clone, PartialEq)]
pub struct Rules {
    pub kind: Kind,
    pub time_budget_s: f64,
    /// The mission ends this long after its goal is reached.
    pub end_hold_s: f64,
    /// The debrief items the sheet shows, in order (ids of ITEMS).
    pub goals: Vec<String>,
    /// A start-up by keys: its checklist's step ids, in order (training.md §7.1); empty: none.
    pub checklist: Vec<&'static str>,
}

/// Every step a start-up checklist may name (iaf_flight start.rs `Start::press`).
pub const STEPS: [&str; 6] = ["main_power", "starter", "engine", "avionics", "ins", "canopy"];

#[derive(Debug, Clone, PartialEq)]
pub enum Kind {
    Startup,
    Takeoff {
        heading_tolerance_deg: f64,
        empty_kg: f64,
        /// (gross weight kg, reference take-off speed kt), by weight; interpolated, held at the ends.
        takeoff_kt: Vec<[f64; 2]>,
    },
}

/// Every debrief item id a mission's `goals` may name.
pub const ITEMS: [&str; 19] = [
    "time_to_idle",
    "time_to_avionics",
    "throttle_moves",
    "faults",
    "taxi_time",
    "lineup_heading_error",
    "runway",
    "roll_start_from_runway_start",
    "roll_length",
    "runway_left",
    "rotation_speed",
    "liftoff_speed",
    "reference_speed",
    "gross_weight",
    "gear_up_height",
    "gear_up_time",
    "roll_heading_deviation",
    "max_centreline_offset",
    "tower_calls",
];

/// The rules of a readable mission file, or None for a mission without `"training"`.
pub fn rules(mission: &Value) -> Result<Option<Rules>> {
    let t = &mission["training"];
    if t.is_null() {
        return Ok(None);
    }
    let num = |k: &str| -> Result<f64> {
        let v = t[k].as_f64().with_context(|| format!("training: \"{k}\" must be a number"))?;
        ensure!(v >= 0.0, "training: \"{k}\" must not be negative");
        Ok(v)
    };
    let goals: Vec<String> = t["goals"]
        .as_array()
        .context("training: \"goals\" must be a list of debrief item ids")?
        .iter()
        .map(|g| match g.as_str() {
            Some(id) if ITEMS.contains(&id) => Ok(id.to_string()),
            _ => bail!("training: \"goals\": {g} is no debrief item"),
        })
        .collect::<Result<_>>()?;
    let kind = match t["kind"].as_str() {
        Some("startup") => Kind::Startup,
        Some("takeoff") => {
            let takeoff_kt: Vec<[f64; 2]> = t["takeoff_kt"]
                .as_array()
                .context("training: \"takeoff_kt\" must be a list of [kg, kt]")?
                .iter()
                .map(|p| match (p[0].as_f64(), p[1].as_f64()) {
                    (Some(kg), Some(kt)) => Ok([kg, kt]),
                    _ => bail!("training: \"takeoff_kt\": {p} is not [kg, kt]"),
                })
                .collect::<Result<_>>()?;
            ensure!(!takeoff_kt.is_empty(), "training: \"takeoff_kt\" is empty");
            ensure!(takeoff_kt.windows(2).all(|w| w[0][0] < w[1][0]), "training: \"takeoff_kt\" must rise in kg");
            ensure!(mission["runway"].is_string(), "training: a take-off mission needs \"runway\"");
            Kind::Takeoff {
                heading_tolerance_deg: num("heading_tolerance_deg")?,
                empty_kg: num("empty_kg")?,
                takeoff_kt,
            }
        }
        k => bail!("training: \"kind\" must be \"startup\" or \"takeoff\", not {k:?}"),
    };
    let checklist = t["checklist"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|c| {
            let id = c["step"].as_str().unwrap_or("");
            ensure!(
                c["en"].is_string() && c["he"].is_string(),
                "training: checklist step {id:?} needs \"en\" and \"he\""
            );
            STEPS.iter().find(|s| **s == id).copied().with_context(|| format!("training: {c} is no checklist step"))
        })
        .collect::<Result<_>>()?;
    Ok(Some(Rules { kind, time_budget_s: num("time_budget_s")?, end_hold_s: num("end_hold_s")?, goals, checklist }))
}

/// The rules' figures, each needing a source in the mission file (data-formats.md §1).
pub const FIGURES: [&str; 5] = [
    "training.time_budget_s",
    "training.end_hold_s",
    "training.heading_tolerance_deg",
    "training.empty_kg",
    "training.takeoff_kt",
];

fn interpolate(table: &[[f64; 2]], x: f64) -> f64 {
    let i = table.partition_point(|p| p[0] <= x);
    match i {
        0 => table[0][1],
        i if i == table.len() => table[i - 1][1],
        i => {
            let ([x0, y0], [x1, y1]) = (table[i - 1], table[i]);
            y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        }
    }
}

// --- The recording ---------------------------------------------------------------------------------------------------

/// One recorded sample (the columns the scorer reads; `rpm` / `avionics` once the recorder has them).
#[derive(Debug, Clone, Default)]
pub struct Sample {
    pub t: f64,
    /// Engine frame, metres (x east, y north).
    pub x: f64,
    pub y: f64,
    pub agl_m: Option<f64>,
    pub speed_kt: f64,
    pub heading: f64,
    pub pitch: f64,
    pub on_ground: bool,
    pub engine: bool,
    pub throttle: f64,
    pub gear: bool,
    pub fuel_kg: f64,
    pub rpm: Option<f64>,
    pub avionics: Option<bool>,
}

/// A flight recording: samples and events in time order.
#[derive(Debug, Default)]
pub struct Flight {
    pub samples: Vec<Sample>,
    pub events: Vec<Value>,
    /// A last line cut off mid-write (the game stopped while recording), skipped: 0 or 1.
    pub cut_lines: usize,
}

/// Parses a blackbox JSONL (docs/blackbox.schema.json): the header's `columns` name the row's values. A last line
/// that does not parse (cut off mid-write) is skipped and counted; any other refuses the recording.
pub fn parse_flight(text: &str) -> Result<Flight> {
    let mut lines = text.lines().enumerate().filter(|(_, l)| !l.trim().is_empty()).peekable();
    let head: Value = serde_json::from_str(lines.next().context("empty recording")?.1).context("line 1")?;
    let cols: Vec<&str> =
        head["columns"].as_array().context("header without \"columns\"")?.iter().filter_map(Value::as_str).collect();
    let col = |name: &str| cols.iter().position(|c| *c == name);
    let need = |name: &str| col(name).with_context(|| format!("recording has no \"{name}\" column"));
    let (ox, oy) = (head["origin"][0].as_f64().unwrap_or(0.0), head["origin"][1].as_f64().unwrap_or(0.0));
    let [t, x, z, speed, heading, pitch, ground, engine, throttle, gear, fuel] =
        ["t", "x", "z", "speed_kt", "heading", "pitch", "on_ground", "engine", "throttle", "gear", "fuel_kg"].map(need);
    let (t, x, z, speed, heading, pitch) = (t?, x?, z?, speed?, heading?, pitch?);
    let (ground, engine, throttle, gear, fuel) = (ground?, engine?, throttle?, gear?, fuel?);
    let (agl, rpm, avionics) = (col("agl_m"), col("rpm"), col("avionics"));
    let mut f = Flight::default();
    while let Some((i, l)) = lines.next() {
        let v: Value = match serde_json::from_str(l) {
            Ok(v) => v,
            Err(_) if lines.peek().is_none() => {
                f.cut_lines = 1;
                break;
            }
            Err(e) => bail!("line {}: {e}", i + 1),
        };
        let Some(r) = v.as_array() else {
            f.events.push(v);
            continue;
        };
        let n = |i: usize| r.get(i).and_then(Value::as_f64).unwrap_or(0.0);
        let b = |i: usize| r.get(i).and_then(Value::as_bool).unwrap_or(false);
        f.samples.push(Sample {
            t: n(t),
            x: ox + n(x),
            y: oy - n(z),
            agl_m: agl.and_then(|i| r.get(i)?.as_f64()),
            speed_kt: n(speed),
            heading: n(heading),
            pitch: n(pitch),
            on_ground: b(ground),
            engine: b(engine),
            throttle: n(throttle),
            gear: b(gear),
            fuel_kg: n(fuel),
            rpm: rpm.and_then(|i| r.get(i)?.as_f64()),
            avionics: avionics.and_then(|i| r.get(i)?.as_bool()),
        });
    }
    ensure!(!f.samples.is_empty(), "recording has no samples");
    Ok(f)
}

// --- The runway ------------------------------------------------------------------------------------------------------

/// The mission's runway in the engine frame, from the take-off end.
#[derive(Debug, Clone)]
pub struct Runway {
    pub designator: String,
    /// The take-off end (the way's end) and the unit vector toward the far end.
    pub from: [f64; 2],
    pub dir: [f64; 2],
    pub length_m: f64,
    pub width_m: f64,
    /// The engine-frame heading down the runway.
    pub heading: f64,
    /// Where the declared runway starts from the take-off end, and where it ends seen from the far end
    /// (`runway_start_m` of each end, iaf-2026/docs/airbases.md §4).
    pub start_m: f64,
    pub far_start_m: f64,
}

impl Runway {
    /// (along from the take-off end, right of the centreline), metres.
    pub fn local(&self, x: f64, y: f64) -> (f64, f64) {
        let (dx, dy) = (x - self.from[0], y - self.from[1]);
        (dx * self.dir[0] + dy * self.dir[1], dx * self.dir[1] - dy * self.dir[0])
    }

    pub fn on(&self, x: f64, y: f64) -> bool {
        let (s, d) = self.local(x, y);
        (0.0..=self.length_m).contains(&s) && d.abs() <= self.width_m / 2.0
    }
}

/// The airbase file of the mission's `start.base` (its English name is "<base> Airbase").
pub fn airbase_of<'a>(mission: &Value, airbases: &'a [Value]) -> Result<&'a Value> {
    let base = mission["start"]["base"].as_str().context("mission: \"start.base\" missing")?;
    airbases
        .iter()
        .find(|a| a["name"]["en"].as_str() == Some(&format!("{base} Airbase")))
        .with_context(|| format!("no airbase file named \"{base} Airbase\""))
}

/// The runway end `designator` ("25R") of `airbase`, in the engine frame.
pub fn runway(airbase: &Value, designator: &str) -> Result<Runway> {
    for r in airbase["runways"].as_array().into_iter().flatten() {
        let ends = r["ends"].as_array().context("runway without \"ends\"")?;
        let Some(i) = ends.iter().position(|e| e["designator"].as_str() == Some(designator)) else { continue };
        let (a, b) = (&ends[i], &ends[1 - i]);
        let what = format!("runway {designator}");
        let (from, to) = (sim::place(a, &what)?, sim::place(b, &what)?);
        let length_m = (to[0] - from[0]).hypot(to[1] - from[1]);
        ensure!(length_m > 0.0, "runway {designator}: both ends at one place");
        let dir = [(to[0] - from[0]) / length_m, (to[1] - from[1]) / length_m];
        return Ok(Runway {
            designator: designator.into(),
            from,
            dir,
            length_m,
            width_m: r["width_m"].as_f64().context("runway without \"width_m\"")?,
            heading: dir[0].atan2(dir[1]).to_degrees().rem_euclid(360.0),
            start_m: a["runway_start_m"].as_f64().unwrap_or(0.0),
            far_start_m: b["runway_start_m"].as_f64().unwrap_or(0.0),
        });
    }
    bail!("{}: no runway end {designator}", airbase["icao"])
}

/// Signed difference a − b in degrees, in (−180, 180].
fn angle(a: f64, b: f64) -> f64 {
    180.0 - (b - a + 180.0).rem_euclid(360.0)
}

// --- The debrief -----------------------------------------------------------------------------------------------------

/// One debrief number: a value with its unit, or a note id in place of the value.
#[derive(Debug, Clone, PartialEq)]
pub struct Item {
    pub id: &'static str,
    pub value: Option<f64>,
    /// A value that is a name (the runway used, "25R").
    pub text: Option<String>,
    pub unit: &'static str,
    pub note: Option<&'static str>,
}

fn item(id: &'static str, value: Option<f64>, unit: &'static str) -> Item {
    Item { id, value, text: None, unit, note: value.is_none().then_some("not_reached") }
}

fn noted(id: &'static str, value: Option<f64>, unit: &'static str, note: &'static str) -> Item {
    Item { id, value, text: None, unit, note: Some(note) }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Debrief {
    pub mission: String,
    pub kind: &'static str,
    pub pass: bool,
    /// Fail reason ids, in the order checked.
    pub reasons: Vec<&'static str>,
    pub items: Vec<Item>,
    /// The items the sheet shows (the rules' `goals`).
    pub goals: Vec<String>,
}

impl Debrief {
    /// The record the debrief page renders: values, units, and every string it names in English and Hebrew.
    pub fn to_json(&self) -> Value {
        let mut ids: Vec<&str> = vec![if self.pass { "pass" } else { "fail" }, self.kind];
        ids.extend(&self.reasons);
        ids.extend(self.items.iter().flat_map(|i| [Some(i.id), i.note]).flatten());
        let strings = |lang: usize| -> Map<String, Value> {
            STRINGS
                .iter()
                .filter(|s| ids.contains(&s.0))
                .map(|s| (s.0.to_string(), json!(if lang == 0 { s.1 } else { s.2 })))
                .collect()
        };
        json!({
            "mission": self.mission,
            "kind": self.kind,
            "pass": self.pass,
            "reasons": self.reasons,
            "items": self.items.iter().map(|i| {
                let mut v = json!({"id": i.id, "value": i.value.map(|v| (v * 10.0).round() / 10.0), "unit": i.unit});
                if let Some(t) = &i.text {
                    v["text"] = json!(t);
                }
                if let Some(n) = i.note {
                    v["note"] = json!(n);
                }
                v
            }).collect::<Vec<_>>(),
            "goals": self.goals,
            "strings": {"en": strings(0), "he": strings(1)},
        })
    }

    /// Fails the debrief with `reason` first (the game's live check, `Watch`, ended the mission on it).
    pub fn fail_first(&mut self, reason: &'static str) {
        self.reasons.retain(|r| *r != reason);
        self.reasons.insert(0, reason);
        self.pass = false;
    }

    /// The English text summary.
    pub fn summary(&self) -> String {
        let mut out = format!("{} {}: {}\n", en(self.kind), self.mission, en(if self.pass { "pass" } else { "fail" }));
        for r in &self.reasons {
            out += &format!("  - {}\n", en(r));
        }
        for i in &self.items {
            let v = i.text.clone().or(i.value.map(|v| format!("{v:.1} {}", i.unit).trim_end().to_string()));
            let line = match (v, i.note) {
                (Some(v), Some(n)) => format!("{v} ({})", en(n)),
                (Some(v), None) => v,
                (None, n) => en(n.unwrap_or("not_reached")).to_string(),
            };
            out += &format!("  {}: {line}\n", en(i.id));
        }
        out
    }
}

// --- Scoring ---------------------------------------------------------------------------------------------------------

/// Scores `flight` against the readable mission `mission` (its `"training"` rules); `airbases` are the airbase
/// files (`iaf-2026/data/airbases/*.json`), read for a take-off.
pub fn score(flight: &Flight, mission: &Value, airbases: &[Value]) -> Result<Debrief> {
    let id = mission["id"].as_str().unwrap_or("?").to_string();
    ensure!(!flight.samples.is_empty(), "the recording has no samples");
    let r = rules(mission)?.with_context(|| format!("{id}: no \"training\" rules"))?;
    let failed = hard_fail(&flight.events);
    let mut d = match &r.kind {
        Kind::Startup => {
            let mut d = startup(flight, id, r.time_budget_s);
            // A checklist step never done (its event without a fault) fails it.
            let done = |step: &str| {
                flight.events.iter().any(|e| e["event"] == "checklist" && e["step"] == step && e["fault"].is_null())
            };
            for step in r.checklist.iter().filter(|s| !done(s)) {
                d.reasons.push(string_id(&format!("skip_{step}")).unwrap_or("not_done"));
            }
            d.pass = d.reasons.is_empty();
            d
        }
        Kind::Takeoff { heading_tolerance_deg, empty_kg, takeoff_kt } => {
            let airbase = airbase_of(mission, airbases)?;
            let rw = runway(airbase, mission["runway"].as_str().unwrap_or(""))?;
            let base = sim_bases::base(airbase, &format!("{id}: start.base"))?;
            let t =
                Takeoff { rw: &rw, base: &base, tolerance: *heading_tolerance_deg, empty_kg: *empty_kg, takeoff_kt };
            takeoff(flight, id, &t, r.time_budget_s, failed.is_some())
        }
    };
    d.goals = r.goals;
    if let Some(reason) = failed {
        d.fail_first(reason);
    }
    if flight.cut_lines > 0 {
        d.items.push(item("cut_lines", Some(flight.cut_lines as f64), ""));
    }
    Ok(d)
}

/// The first event that fails any training mission at once: `crash`; a `hit` on the jet ("damage"); a `surface`
/// event with the wheels off the pavement ("off_pavement").
pub fn hard_fail(events: &[Value]) -> Option<&'static str> {
    events.iter().find_map(|e| match e["event"].as_str() {
        Some("eject") => Some("ejected"),
        Some("crash") => Some("crash"),
        Some("hit") => Some("damage"),
        Some("surface") if e["paved"] == false => Some("off_pavement"),
        Some("checklist") => e["fault"].as_str().and_then(string_id),
        _ => None,
    })
}

/// One frame of a training run for `Watch::check`.
#[derive(Debug, Clone, Copy, Default)]
pub struct Now {
    pub on_ground: bool,
    pub x: f64,
    pub y: f64,
    pub crashed: bool,
    pub damage: f64,
    pub ejected: bool,
    /// A start-up checklist step's fault this frame (a string id), or None.
    pub fault: Option<&'static str>,
}

/// The string `id` in `lang` ("en" / "he"), "" when unknown.
pub fn text(id: &str, lang: &str) -> &'static str {
    STRINGS.iter().find(|s| s.0 == id).map_or("", |s| if lang == "he" { s.2 } else { s.1 })
}

/// The string id `id` names ('static), or None.
pub fn string_id(id: &str) -> Option<&'static str> {
    STRINGS.iter().find(|s| s.0 == id).map(|s| s.0)
}

/// The game's live check of a training run (IafTraining): the same fail rules as `hard_fail`, on the frame's state.
pub struct Watch {
    pub rules: Rules,
    /// The mission's base (its pavement).
    pub base: Base,
}

impl Watch {
    /// The rules of the readable mission file `mission` and its base from the airbase files in `airbases`.
    pub fn open(mission: &std::path::Path, airbases: &std::path::Path) -> Result<Watch> {
        let m: Value =
            serde_json::from_str(&std::fs::read_to_string(mission).with_context(|| mission.display().to_string())?)
                .with_context(|| mission.display().to_string())?;
        let bases: Vec<_> = sim::read_dir(airbases)?.into_iter().map(|f| f.v).collect();
        let rules = rules(&m)?.with_context(|| format!("{}: no \"training\" rules", mission.display()))?;
        let base = sim_bases::base(airbase_of(&m, &bases)?, &mission.display().to_string())?;
        Ok(Watch { rules, base })
    }

    /// The fail reason of this moment, or None: ejected, crashed, any damage (0..1), or on the ground off the
    /// pavement at the jet's centre (`x`, `y` in the engine frame).
    pub fn check(&self, s: &Now) -> Option<&'static str> {
        let Now { on_ground, x, y, crashed, damage, ejected, .. } = *s;
        if ejected {
            Some("ejected")
        } else if s.fault.is_some() {
            s.fault
        } else if crashed {
            Some("crash")
        } else if damage > 0.0 {
            Some("damage")
        } else if on_ground && !self.base.paved([x, y], sim_bases::PAVEMENT_MARGIN_M) {
            Some("off_pavement")
        } else {
            None
        }
    }
}

/// At the holding point: no farther from the lineup point than the holding point plus this (m, inferred: a jet's
/// length or two short of it).
pub const HOLDING_POINT_MARGIN_M: f64 = 50.0;
/// The holding point's distance to the lineup point where the base gives none (m): the own iaf.ibx's taxi-out paths
/// end 86–101 m from it.
pub const HOLDING_POINT_M: f64 = 100.0;

/// The moment the radio menu offers its calls for (training.md §8, `radio_calls`).
#[derive(Debug, Clone, Default)]
pub struct RadioNow {
    pub on_ground: bool,
    /// The engine runs (at idle or above).
    pub engine_on: bool,
    pub avionics: bool,
    /// 2-D distance from the jet to the near tower's lineup point, m (INFINITY near no tower).
    pub lineup_m: f64,
    /// The holding point's 2-D distance to that lineup point, m: the base's taxi-out path's last point before the
    /// lineup (iaf.ibx FromTaxiPt n−2).
    pub hold_m: f64,
    /// The tower's answers so far (radio.gd's templates): `ACFT_CLEAR_TO_START`, `ACFT_TAXI_TO_RUNWAY`,
    /// `ACFT_CLEAR_TO_TAKEOFF` mark a call approved.
    pub answers: Vec<String>,
    /// The flight started with the engine running on the ground (at the lineup point, terrain_view.gd's ground
    /// start): taxi counts as approved.
    pub hot: bool,
}

/// The radio menu's calls that fit the moment, in menu order: "startup" on the ground with the engine off; "taxi" on
/// the ground with the engine running, the avionics up and taxi not yet (start-up approved or not: no dead end on the
/// spot); "takeoff" at the holding
/// point or past it (no farther from the lineup point than `hold_m` + HOLDING_POINT_MARGIN_M) with taxi approved and
/// take-off not yet; "landing" in the air. A hot ground start has taxi approved.
pub fn radio_calls(s: &RadioNow) -> Vec<&'static str> {
    let got = |t: &str| s.answers.iter().any(|a| a == t);
    let taxi = s.hot || got("ACFT_TAXI_TO_RUNWAY");
    let takeoff = got("ACFT_CLEAR_TO_TAKEOFF");
    let g = s.on_ground;
    [
        ("startup", g && !s.engine_on),
        ("taxi", g && s.engine_on && s.avionics && !taxi),
        ("takeoff", g && s.lineup_m <= s.hold_m + HOLDING_POINT_MARGIN_M && taxi && !takeoff),
        ("landing", !g),
    ]
    .into_iter()
    .filter_map(|(id, on)| on.then_some(id))
    .collect()
}

/// Scores the recording at `flight` against the readable mission file `mission` with the airbase files in `airbases`
/// (the CLI `iaf-training score` and the game's `IafTraining`).
pub fn score_files(flight: &std::path::Path, mission: &std::path::Path, airbases: &std::path::Path) -> Result<Debrief> {
    ensure!(airbases.is_dir(), "no airbases folder {} (give it as the third argument)", airbases.display());
    let read = |p: &std::path::Path| std::fs::read_to_string(p).with_context(|| p.display().to_string());
    let f = parse_flight(&read(flight)?).with_context(|| flight.display().to_string())?;
    let m: Value = serde_json::from_str(&read(mission)?).with_context(|| mission.display().to_string())?;
    let bases: Vec<_> = sim::read_dir(airbases)?.into_iter().map(|f| f.v).collect();
    score(&f, &m, &bases)
}

/// Throttle movements: the runs of samples in which the lever moves.
fn throttle_moves(s: &[Sample]) -> f64 {
    let mut moving = false;
    let mut n = 0;
    for w in s.windows(2) {
        let m = (w[1].throttle - w[0].throttle).abs() > THROTTLE_STEP;
        n += usize::from(m && !moving);
        moving = m;
    }
    n as f64
}

fn startup(f: &Flight, mission: String, budget: f64) -> Debrief {
    let s = &f.samples;
    let t0 = s[0].t;
    let has_rpm = s.iter().any(|x| x.rpm.is_some());
    let idle = if has_rpm {
        s.iter().find(|x| x.engine && x.rpm.unwrap_or(0.0) >= IDLE_RPM).map(|x| x.t - t0)
    } else {
        s.iter().find(|x| x.engine).map(|x| x.t - t0 + IDLE_WINDUP_S)
    };
    let has_avionics = s.iter().any(|x| x.avionics.is_some());
    let avionics = if has_avionics { s.iter().find(|x| x.avionics == Some(true)).map(|x| x.t - t0) } else { idle };
    let mut reasons = vec![];
    match idle.zip(avionics) {
        _ if !s.iter().any(|x| x.engine) => reasons.push("no_start"),
        None => reasons.push("not_done"),
        Some((i, a)) if i.max(a) > budget => reasons.push("over_time"),
        Some(_) => {}
    }
    // The model's figure is noted when the recording has no column of its own.
    let idle_item = match (has_rpm, idle) {
        (false, Some(_)) => noted("time_to_idle", idle, "s", "from_spool"),
        _ => item("time_to_idle", idle, "s"),
    };
    let av_item = match (has_avionics, avionics) {
        (false, Some(_)) => noted("time_to_avionics", avionics, "s", "with_idle"),
        _ => item("time_to_avionics", avionics, "s"),
    };
    Debrief {
        mission,
        kind: "startup",
        pass: reasons.is_empty(),
        reasons,
        items: vec![
            idle_item,
            av_item,
            item("throttle_moves", Some(throttle_moves(s)), ""),
            noted("faults", None, "", "none_modelled"),
        ],
        goals: vec![],
    }
}

/// A take-off mission's runway, base and figures.
struct Takeoff<'a> {
    rw: &'a Runway,
    base: &'a Base,
    tolerance: f64,
    empty_kg: f64,
    takeoff_kt: &'a [[f64; 2]],
}

/// The runway end the roll from `a` toward `b` ran on ("25R"), or None off every runway of the base.
fn runway_used(base: &Base, a: [f64; 2], b: [f64; 2]) -> Option<String> {
    let heading = (b[0] - a[0]).atan2(b[1] - a[1]).to_degrees();
    let r = base.runways.iter().find(|r| r.dist(a) <= r.width / 2.0)?;
    let k = usize::from(angle(r.heading(0), heading).abs() > 90.0);
    Some(r.designators[k].clone())
}

/// `ended`: a hard fail (`hard_fail`) ended the mission, so the climb-out is not judged.
fn takeoff(f: &Flight, mission: String, t: &Takeoff, budget: f64, ended: bool) -> Debrief {
    let (rw, tolerance) = (t.rw, t.tolerance);
    let s = &f.samples;
    let t0 = s[0].t;
    let radio = f.events.iter().filter(|e| e["event"] == "radio").count();
    let tower = item("tower_calls", Some(radio as f64), "");
    let mut reasons = vec![];
    // The lift-off: the first sample off the ground after one on it that starts LIFTOFF_HOLD_S airborne (or stays
    // airborne to the recording's end), so a one-sample glitch on the ground is not one.
    let held = |i: usize| {
        let run = s[i..].iter().take_while(|x| !x.on_ground).count();
        i + run == s.len() || s[i + run - 1].t - s[i].t >= LIFTOFF_HOLD_S
    };
    let lift = (1..s.len()).find(|&i| s[i - 1].on_ground && !s[i].on_ground && held(i));
    let Some(lift) = lift else {
        reasons.push("no_liftoff");
        return Debrief { mission, kind: "takeoff", pass: false, reasons, items: vec![tower], goals: vec![] };
    };
    // The roll: the slowest sample on the runway (the latest of equals) between the jet's entry onto the runway and
    // its last sample below ROLL_START_KT before the lift-off: the stop on the lineup point, or the entry of a rolling
    // take-off. A jet below ROLL_START_KT off the runway starts its roll there.
    let k = s[..lift].iter().rposition(|x| x.speed_kt < ROLL_START_KT).unwrap_or(0);
    let mut entry = k;
    while entry > 0 && rw.on(s[k].x, s[k].y) && rw.on(s[entry - 1].x, s[entry - 1].y) {
        entry -= 1;
    }
    let roll = (entry..=k).rev().min_by(|&a, &b| s[a].speed_kt.total_cmp(&s[b].speed_kt)).unwrap_or(k);
    // The lineup heading: at the stop, or (a rolling take-off) where the roll passes ROLL_START_KT.
    let lineup = if s[roll].speed_kt < 1.0 { roll } else { k };
    let rolls = &s[roll..lift];
    let (s_roll, _) = rw.local(s[roll].x, s[roll].y);
    let (s_lift, _) = rw.local(s[lift].x, s[lift].y);
    let moved = s.iter().position(|x| x.speed_kt > 1.0).unwrap_or(roll).min(roll);
    if !rw.on(s[roll].x, s[roll].y) || s_lift <= s_roll {
        reasons.push("wrong_runway");
    } else if rolls.iter().any(|x| !rw.on(x.x, x.y)) {
        reasons.push("excursion");
    }
    let rot = s[roll..=lift].iter().find(|x| x.pitch >= s[roll].pitch + ROTATION_PITCH_DEG).map(|x| x.speed_kt);
    let gear_up = s[lift..].iter().find(|x| !x.gear && !x.on_ground);
    // The first airborne sample with the gear up on the runway heading; the earliest, so the budget is checked on it.
    let climb = s[lift..].iter().find(|x| !x.on_ground && !x.gear && angle(x.heading, rw.heading).abs() <= tolerance);
    if !ended {
        match climb {
            None if gear_up.is_none() => reasons.push("gear_down"),
            None => reasons.push("off_heading"),
            Some(x) if x.t - t0 > budget => reasons.push("over_time"),
            Some(_) => {}
        }
    }
    let gross = t.empty_kg + s[lift].fuel_kg;
    let used = runway_used(t.base, [s[roll].x, s[roll].y], [s[lift].x, s[lift].y]);
    let max = |g: &dyn Fn(&Sample) -> f64| rolls.iter().map(g).fold(0.0, f64::max);
    let items = vec![
        item("taxi_time", Some(s[roll].t - s[moved].t), "s"),
        item("lineup_heading_error", Some(angle(s[lineup].heading, rw.heading)), "deg"),
        Item { id: "runway", value: None, note: used.is_none().then_some("not_reached"), text: used, unit: "" },
        item("roll_start_from_runway_start", Some(s_roll - rw.start_m), "m"),
        item("roll_length", Some(s_lift - s_roll), "m"),
        item("runway_left", Some(rw.length_m - rw.far_start_m - s_lift), "m"),
        item("rotation_speed", rot, "kt"),
        item("liftoff_speed", Some(s[lift].speed_kt), "kt"),
        item("gross_weight", Some(gross), "kg"),
        item("reference_speed", Some(interpolate(t.takeoff_kt, gross)), "kt"),
        item("gear_up_height", gear_up.and_then(|x| x.agl_m), "m"),
        item("gear_up_time", gear_up.map(|x| x.t - s[lift].t), "s"),
        item("roll_heading_deviation", Some(max(&|x| angle(x.heading, rw.heading).abs())), "deg"),
        item("max_centreline_offset", Some(max(&|x| rw.local(x.x, x.y).1.abs())), "m"),
        tower,
    ];
    Debrief { mission, kind: "takeoff", pass: reasons.is_empty(), reasons, items, goals: vec![] }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    const KT: f64 = 1852.0 / 3600.0; // m/s per knot
    const COLUMNS: [&str; 10] =
        ["t", "x", "z", "agl_m", "speed_kt", "heading", "pitch", "on_ground", "engine", "throttle"];

    fn data() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../iaf-2026/data")
    }

    fn mission(id: &str) -> Value {
        serde_json::from_str(&std::fs::read_to_string(data().join(format!("missions/{id}.json"))).unwrap()).unwrap()
    }

    fn airbases() -> Vec<Value> {
        crate::sim::read_dir(&data().join("airbases")).unwrap().into_iter().map(|f| f.v).collect()
    }

    /// A recording as the game writes it (header, rows of COLUMNS + gear + fuel_kg) from engine-frame samples.
    fn jsonl(samples: &[Sample]) -> String {
        let mut cols: Vec<&str> = COLUMNS.to_vec();
        cols.extend(["gear", "fuel_kg"]);
        let head = json!({"blackbox": 1, "date": "synthetic", "mission": -1, "jet": "F-16", "origin": [0.0, 0.0],
            "columns": cols});
        let mut out = head.to_string() + "\n";
        for (i, s) in samples.iter().enumerate() {
            if i > 0 && samples[i - 1].on_ground && !s.on_ground {
                let e =
                    json!({"t": s.t, "event": "lift-off", "agl_m": s.agl_m, "speed_kt": s.speed_kt, "pitch": s.pitch});
                out += &format!("{e}\n");
            }
            let row = json!([
                s.t,
                s.x,
                -s.y,
                s.agl_m,
                s.speed_kt,
                s.heading,
                s.pitch,
                s.on_ground,
                s.engine,
                s.throttle,
                s.gear,
                s.fuel_kg
            ]);
            out += &format!("{row}\n");
        }
        out
    }

    /// Writes a synthetic flight where `IAF_TRAINING_WRITE` names a folder (for the CLI and the timeline picture).
    fn keep(name: &str, text: &str) {
        if let Ok(dir) = std::env::var("IAF_TRAINING_WRITE") {
            std::fs::write(Path::new(&dir).join(name), text).unwrap();
        }
    }

    /// How a synthetic take-off from Ramon 25R goes (`takeoff`).
    #[derive(Clone, Copy)]
    struct Opts {
        gear_up: bool,
        /// Drift right of the centreline, metres per 1500 m of roll.
        drift_m: f64,
        /// No stop on the lineup point: the taxi accelerates from a stop 450 m off the runway onto the roll.
        rolling: bool,
        /// The speed from which the pitch rises, and its rise per sample.
        rotate_kt: f64,
        pitch_step: f64,
        /// A sample of the taxi recorded off the ground (a one-row glitch).
        glitch: bool,
    }

    const CLEAN: Opts =
        Opts { gear_up: true, drift_m: 0.0, rolling: false, rotate_kt: 150.0, pitch_step: 0.3, glitch: false };

    /// A take-off from Ramon 25R: a 60 s taxi in from 450 m right of the lineup point (at 7.5 m/s, or from a stop
    /// at 0.25 m/s² when rolling), 10 s lined up 2° off (none when rolling), a roll at 3 m/s² drifting `drift_m` to
    /// the right, the pitch rising from `rotate_kt`, lift-off at 165 kt, a 30 s climb with the gear up after 3 s
    /// (or never).
    fn takeoff(o: Opts) -> (String, Runway) {
        let rw = runway(airbase_of(&mission("ramon_takeoff"), &airbases()).unwrap(), "25R").unwrap();
        let right = [rw.dir[1], -rw.dir[0]];
        let at =
            |s: f64, d: f64| [rw.from[0] + s * rw.dir[0] + d * right[0], rw.from[1] + s * rw.dir[1] + d * right[1]];
        let line = rw.start_m + 100.0;
        let base =
            Sample { engine: true, throttle: 0.3, gear: true, fuel_kg: 3000.0, on_ground: true, ..Default::default() };
        let mut out = vec![];
        let mut t = 0.0;
        while t < 60.0 {
            let (d, v) = if o.rolling { (450.0 - 0.125 * t * t, 0.25 * t) } else { (450.0 * (1.0 - t / 60.0), 7.5) };
            let [x, y] = at(line, d);
            let on_ground = !(o.glitch && out.len() == 300);
            out.push(Sample {
                t,
                x,
                y,
                agl_m: Some(1.0),
                speed_kt: v / KT,
                heading: rw.heading - 90.0,
                on_ground,
                ..base.clone()
            });
            t += 0.1;
        }
        let [x, y] = at(line, 0.0);
        while !o.rolling && t < 70.0 {
            out.push(Sample { t, x, y, agl_m: Some(1.0), heading: rw.heading + 2.0, ..base.clone() });
            t += 0.1;
        }
        // The roll, the lift-off and the climb.
        let v0 = if o.rolling { 15.0 } else { 0.0 };
        let (mut s, mut v, mut pitch, mut agl, mut air) = (line, v0, 0.0, 1.0, 0.0);
        while air < 30.0 {
            let ground = v < 165.0 * KT;
            if v >= o.rotate_kt * KT {
                pitch = f64::min(pitch + o.pitch_step, 10.0);
            }
            if ground {
                v += 3.0 * 0.1;
            } else {
                air += 0.1;
                agl += 10.0 * 0.1;
            }
            s += v * 0.1;
            let [x, y] = at(s, o.drift_m * (s - line) / 1500.0);
            out.push(Sample {
                t,
                x,
                y,
                agl_m: Some(agl),
                speed_kt: v / KT,
                heading: rw.heading,
                pitch,
                on_ground: ground,
                throttle: 1.0,
                gear: !(o.gear_up && air > 3.0),
                ..base.clone()
            });
            t += 0.1;
        }
        (jsonl(&out), rw)
    }

    fn scored(text: &str, id: &str) -> Debrief {
        let d = score(&parse_flight(text).unwrap(), &mission(id), &airbases()).unwrap();
        println!("{}", d.summary());
        d
    }

    fn value(d: &Debrief, id: &str) -> f64 {
        d.items.iter().find(|i| i.id == id).and_then(|i| i.value).unwrap_or(f64::NAN)
    }

    #[test]
    fn a_clean_takeoff_passes_with_its_numbers() {
        let (text, rw) = takeoff(CLEAN);
        keep("clean_takeoff.jsonl", &text);
        let d = scored(&text, "ramon_takeoff");
        assert!(d.pass, "{:?}", d.reasons);
        let near =
            |id: &str, want: f64, tol: f64| assert!((value(&d, id) - want).abs() <= tol, "{id}: {}", value(&d, id));
        near("taxi_time", 70.0, 0.2);
        near("lineup_heading_error", 2.0, 0.01);
        near("roll_start_from_runway_start", 100.0, 1.0);
        // v² / 2a at 165 kt and 3 m/s².
        near("roll_length", (165.0 * KT).powi(2) / 6.0, 15.0);
        near("liftoff_speed", 165.0, 1.0);
        // The pitch passes 2° on the seventh 0.3° step from 150 kt, 0.6 s later at 3 m/s².
        near("rotation_speed", 150.0 + 2.1 / KT, 1.0);
        near("gear_up_time", 3.0, 0.2);
        near("gear_up_height", 31.0, 2.0);
        near("max_centreline_offset", 0.0, 0.1);
        near("gross_weight", 8573.0 + 3000.0, 0.1);
        near("reference_speed", 130.0 + 84.0 * (11573.0 - 9072.0) / 12700.0, 0.1);
        let left = rw.length_m - rw.far_start_m - (rw.start_m + 100.0 + value(&d, "roll_length"));
        near("runway_left", left, 1.0);
        // The debrief record names every string it uses in both languages.
        let j = d.to_json();
        for lang in ["en", "he"] {
            for i in j["items"].as_array().unwrap() {
                assert!(j["strings"][lang][i["id"].as_str().unwrap()].is_string(), "{lang}: {}", i["id"]);
            }
        }
        assert_eq!(j["strings"]["en"]["tower_calls"], "Tower calls");
        assert_eq!(value(&d, "tower_calls"), 0.0);
        let runway = d.items.iter().find(|i| i.id == "runway").unwrap();
        assert_eq!(runway.text.as_deref(), Some("25R"));
        // The sheet's goals: the rules' list, each an item of the record.
        assert_eq!(
            j["goals"],
            json!(["runway", "liftoff_speed", "reference_speed", "max_centreline_offset", "tower_calls"])
        );
        for g in j["goals"].as_array().unwrap() {
            assert!(d.items.iter().any(|i| i.id == g), "{g}");
        }
    }

    /// A recording with `events` (JSON objects) appended.
    fn with(text: &str, events: &[Value]) -> String {
        events.iter().fold(text.to_string(), |t, e| t + &format!("{e}\n"))
    }

    #[test]
    fn a_crashed_takeoff_fails_at_once_with_the_crash_first() {
        // A crash on the roll, before any lift-off.
        let text = with(&takeoff(CLEAN).0, &[json!({"t": 75.0, "event": "crash", "reason": "tail strike"})]);
        let d = scored(&text, "ramon_takeoff");
        assert!(!d.pass);
        assert_eq!(d.reasons[0], "crash");
        assert!(!d.reasons.contains(&"gear_down"), "{:?}", d.reasons);
    }

    #[test]
    fn an_ejection_fails_with_its_reason_first() {
        let text = with(&takeoff(CLEAN).0, &[json!({"t": 40.0, "event": "eject", "short": true})]);
        assert_eq!(scored(&text, "ramon_takeoff").reasons, ["ejected"]);
    }

    #[test]
    fn damage_fails() {
        let text = with(&takeoff(CLEAN).0, &[json!({"t": 80.0, "event": "hit", "kind": "gun", "damage": 0.1})]);
        assert_eq!(scored(&text, "ramon_takeoff").reasons, ["damage"]);
    }

    #[test]
    fn leaving_the_pavement_fails() {
        let text = with(&takeoff(CLEAN).0, &[json!({"t": 30.0, "event": "surface", "paved": false})]);
        assert_eq!(scored(&text, "ramon_takeoff").reasons, ["off_pavement"]);
        // The live check: the parking spot and the lineup point paved, 200 m beside the runway not.
        let data = data();
        let w = Watch::open(&data.join("missions/ramon_takeoff.json"), &data.join("airbases")).unwrap();
        let rw = runway(airbase_of(&mission("ramon_takeoff"), &airbases()).unwrap(), "25R").unwrap();
        let at =
            |s: f64, d: f64| [rw.from[0] + s * rw.dir[0] + d * rw.dir[1], rw.from[1] + s * rw.dir[1] - d * rw.dir[0]];
        let [x, y] = at(rw.start_m + 100.0, 0.0);
        assert_eq!(
            w.check(&Now { on_ground: true, x, y, crashed: false, damage: 0.0, ejected: false, fault: None }),
            None
        );
        let spot = w.base.parking[0].at;
        assert_eq!(
            w.check(&Now {
                on_ground: true,
                x: spot[0],
                y: spot[1],
                crashed: false,
                damage: 0.0,
                ejected: false,
                fault: None
            }),
            None
        );
        let [x, y] = at(1000.0, 200.0);
        assert_eq!(
            w.check(&Now { on_ground: true, x, y, crashed: false, damage: 0.0, ejected: false, fault: None }),
            Some("off_pavement")
        );
        assert_eq!(
            w.check(&Now { on_ground: false, x, y, crashed: false, damage: 0.0, ejected: false, fault: None }),
            None,
            "airborne"
        );
        assert_eq!(
            w.check(&Now {
                on_ground: true,
                x: spot[0],
                y: spot[1],
                crashed: false,
                damage: 0.2,
                ejected: false,
                fault: None
            }),
            Some("damage")
        );
        assert_eq!(
            w.check(&Now { on_ground: true, x, y, crashed: true, damage: 0.0, ejected: false, fault: None }),
            Some("crash")
        );
        let out = Now { on_ground: false, x, y, ejected: true, ..Default::default() };
        assert_eq!(w.check(&out), Some("ejected"));
        assert_eq!(w.rules.end_hold_s, 5.0);
    }

    /// A rolling take-off: from a stop 450 m off the runway the jet accelerates without stopping; the roll starts
    /// where it enters the runway.
    #[test]
    fn a_rolling_takeoff_starts_its_roll_on_the_runway() {
        let (text, rw) = takeoff(Opts { rolling: true, ..CLEAN });
        let d = scored(&text, "ramon_takeoff");
        assert!(d.pass, "{:?}", d.reasons);
        // The entry: the first taxi sample within half the width of the centreline, 100 m in from the runway start.
        assert!((value(&d, "roll_start_from_runway_start") - 100.0).abs() < 1.0);
        assert!(value(&d, "lineup_heading_error").abs() < 0.01);
        assert!(value(&d, "max_centreline_offset") <= rw.width_m / 2.0);
    }

    /// One taxi sample recorded off the ground is no lift-off: the take-off scores as the clean one.
    #[test]
    fn a_glitch_off_the_ground_is_no_liftoff() {
        let d = scored(&takeoff(Opts { glitch: true, ..CLEAN }).0, "ramon_takeoff");
        let clean = scored(&takeoff(CLEAN).0, "ramon_takeoff");
        assert!(d.pass, "{:?}", d.reasons);
        assert_eq!(d.items, clean.items);
    }

    /// A rotation that first passes 2° on the lift-off sample is found there.
    #[test]
    fn a_rotation_on_the_liftoff_sample_counts() {
        let d = scored(&takeoff(Opts { rotate_kt: 165.0, pitch_step: 3.0, ..CLEAN }).0, "ramon_takeoff");
        assert_eq!(value(&d, "rotation_speed"), value(&d, "liftoff_speed"));
    }

    /// A recording cut mid-line at its end scores, the cut line counted; a bad line in the middle refuses it.
    #[test]
    fn a_cut_last_line_is_skipped() {
        let text = takeoff(CLEAN).0;
        let cut = format!("{text}[123.4, 56");
        let d = scored(&cut, "ramon_takeoff");
        assert!(d.pass, "{:?}", d.reasons);
        assert_eq!(value(&d, "cut_lines"), 1.0);
        let mut lines: Vec<&str> = text.lines().collect();
        lines.insert(5, "[1, 2");
        let e = parse_flight(&lines.join("\n")).unwrap_err().to_string();
        assert!(e.starts_with("line 6:"), "{e}");
    }

    #[test]
    fn a_flight_without_samples_is_refused() {
        let empty = Flight::default();
        assert!(score(&empty, &mission("ramon_startup"), &[]).is_err());
    }

    #[test]
    fn a_gear_down_climb_out_fails() {
        let (text, _) = takeoff(Opts { gear_up: false, ..CLEAN });
        keep("gear_down_takeoff.jsonl", &text);
        let d = scored(&text, "ramon_takeoff");
        assert_eq!(d.reasons, ["gear_down"]);
        assert!(value(&d, "gear_up_time").is_nan());
    }

    #[test]
    fn a_runway_excursion_fails() {
        let (text, _) = takeoff(Opts { drift_m: 40.0, ..CLEAN });
        keep("excursion_takeoff.jsonl", &text);
        let d = scored(&text, "ramon_takeoff");
        assert_eq!(d.reasons, ["excursion"]);
        assert!(value(&d, "max_centreline_offset") > 22.6);
    }

    #[test]
    fn the_radio_menu_offers_only_the_call_that_fits() {
        let answers = |a: &[&str]| a.iter().map(|s| s.to_string()).collect();
        // Nevatim: the parking spot 337 m from the lineup point, the holding point 86 m.
        let mut s = RadioNow { on_ground: true, lineup_m: 337.0, hold_m: 86.0, ..Default::default() };
        assert_eq!(radio_calls(&s), ["startup"]);
        s.answers = answers(&["ACFT_CLEAR_TO_START"]);
        s.engine_on = true;
        assert!(radio_calls(&s).is_empty(), "idle without the avionics: nothing");
        s.avionics = true;
        assert_eq!(radio_calls(&s), ["taxi"]);
        s.answers = answers(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY"]);
        assert!(radio_calls(&s).is_empty(), "taxiing, short of the holding point: nothing");
        s.lineup_m = 158.0;
        assert!(radio_calls(&s).is_empty(), "the taxi's last turns, short of the holding point: nothing");
        s.lineup_m = 90.0;
        assert_eq!(radio_calls(&s), ["takeoff"]);
        s.lineup_m = 0.0;
        assert_eq!(radio_calls(&s), ["takeoff"], "lined up: still take-off");
        s.answers = vec![];
        assert_eq!(radio_calls(&s), ["taxi"], "started without start-up approval: taxi still offered");
        s.answers = answers(&["ACFT_CLEAR_TO_START"]);
        assert_eq!(radio_calls(&s), ["taxi"], "at the holding point without taxi approved: no take-off");
        s.answers = answers(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY", "ACFT_CLEAR_TO_TAKEOFF"]);
        assert!(radio_calls(&s).is_empty());
        s.on_ground = false;
        assert_eq!(radio_calls(&s), ["landing"]);
        // A hot ground start at the lineup point: take-off at once.
        let hot = RadioNow { on_ground: true, engine_on: true, avionics: true, hot: true, ..Default::default() };
        assert_eq!(radio_calls(&hot), ["takeoff"]);
    }

    #[test]
    fn the_startup_counts_from_the_engine_start() {
        // 20 s cold, then the throttle to idle (the engine starts) and two more moves.
        let samples: Vec<Sample> = (0..600)
            .map(|i| {
                let t = i as f64 * 0.1;
                let throttle = if t < 20.0 {
                    0.0
                } else if t < 40.0 {
                    0.1
                } else if t < 50.0 {
                    0.3
                } else {
                    0.0
                };
                Sample { t, engine: t >= 20.0, throttle, on_ground: true, gear: true, ..Default::default() }
            })
            .collect();
        let steps: Vec<Value> = STEPS.iter().map(|s| json!({"t": 20.0, "event": "checklist", "step": s})).collect();
        let bare = jsonl(&samples);
        let text = with(&bare, &steps);
        keep("startup.jsonl", &text);
        // The checklist not flown: each step skipped.
        let skipped = scored(&bare, "ramon_startup");
        assert_eq!(skipped.reasons[0], "skip_main_power");
        assert_eq!(skipped.reasons.len(), 6);
        // A hot start fails it first.
        let hot = json!({"t": 21.0, "event": "checklist", "step": "engine", "fault": "hot_start"});
        assert_eq!(scored(&with(&text, &[hot]), "ramon_startup").reasons, ["hot_start"]);
        let d = scored(&text, "ramon_startup");
        assert!(d.pass, "a clean start-up passes at its end");
        assert!(d.goals.is_empty(), "the start-up's sheet: pass / fail and the reason");
        assert!((value(&d, "time_to_idle") - 24.0).abs() < 1e-9);
        // A crash fails it with the crash first, even with the engine at idle.
        let crashed = scored(&with(&text, &[json!({"t": 50.0, "event": "crash"})]), "ramon_startup");
        assert_eq!(crashed.reasons, ["crash"]);
        assert_eq!(value(&d, "throttle_moves"), 3.0);
        let mut m = mission("ramon_startup");
        m["training"]["time_budget_s"] = json!(10);
        let late = score(&parse_flight(&text).unwrap(), &m, &[]).unwrap();
        assert_eq!(late.reasons, ["over_time"]);
        let cold: Vec<Sample> = samples.iter().map(|s| Sample { engine: false, ..s.clone() }).collect();
        assert_eq!(scored(&with(&jsonl(&cold), &steps), "ramon_startup").reasons, ["no_start"]);
    }

    /// The newest recording in the player's flights folder (user://flights, docs/blackbox.schema.json) scores
    /// against Ramon's take-off without an error; skipped when the folder holds none.
    #[test]
    fn a_real_recorded_flight_scores() {
        let home = std::env::var("HOME").unwrap_or_default();
        let dirs = [
            std::env::var("IAF_FLIGHTS").unwrap_or_default(),
            format!("{home}/.local/share/godot/app_userdata/iaf-reborn/flights"),
            format!("{home}/Library/Application Support/Godot/app_userdata/iaf-reborn/flights"),
            format!("{}/Godot/app_userdata/iaf-reborn/flights", std::env::var("APPDATA").unwrap_or_default()),
        ];
        let newest = dirs
            .iter()
            .filter(|d| !d.is_empty())
            .flat_map(|d| std::fs::read_dir(d).into_iter().flatten().flatten().map(|e| e.path()))
            .filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("flight-")))
            .max();
        let Some(path) = newest else {
            println!("skipped: no recorded flight in the flights folder (set IAF_FLIGHTS to one)");
            return;
        };
        println!("{}", path.display());
        let text = std::fs::read_to_string(&path).unwrap();
        let d = scored(&text, "ramon_takeoff");
        assert!(!d.items.is_empty());
    }
}
