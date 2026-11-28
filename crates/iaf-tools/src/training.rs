//! Modern IAF's training scoring (modern-iaf/docs/training.md): a recorded flight (the blackbox JSONL,
//! docs/blackbox.schema.json) scored against a training mission (`modern-iaf/data/missions/<id>.json`, its
//! `"training"` rules) into a debrief record with English and Hebrew strings keyed by id.
//!
//! - every mission: a crash, any damage or the wheels off the pavement fails it at once (the recorder's `crash`, `hit`
//!   and `surface` events; the game's live check is `Watch`);
//! - start-up (`"kind": "startup"`): pass when the engine reaches idle with the avionics up within the time budget;
//! - take-off (`"kind": "takeoff"`): pass when airborne with the gear up on the runway heading ± the tolerance, from
//!   the mission's runway, with no runway excursion, within the time budget;
//! - weapons range (`"kind": "range"`): pass once the player has shot down `air_kills` of the range's drones and
//!   destroyed `ground_kills` of its ground targets (the recorder's `kill` events, air or ground) within the time
//!   budget.
//!
//! The record keeps every number; the rules' `goals` name the few the debrief sheet shows.
//!
//! Positions: the recorder logs scene metres (x east, z south) from the terrain's origin; the scorer turns them into
//! the engine frame (origin.x + x, origin.y − z) and the airbase file's runway ends into the same frame, UTM 36N, as
//! the mission compiler places them (`sim.rs place`), so headings compare with the recorded ones directly.

use anyhow::{Context, Result, bail, ensure};
use serde_json::{Map, Value, json};

use crate::combat_log;
use crate::course::{self, Grade, LessonGrade, Limit, Standard};
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
/// A lift-off this far from the reference speed is marked on the sheet (kt, inferred: the reference table's own
/// step between weights).
const LIFTOFF_WARN_KT: f64 = 10.0;
/// The "Next time" tip's rotation: this far below the reference take-off speed (kt, inferred: the nose comes up over
/// the last seconds of the roll).
const ROTATE_BEFORE_KT: f64 = 10.0;
/// A throttle step smaller than this between two samples is noise, not a movement.
const THROTTLE_STEP: f64 = 0.005;
/// The engine is being started once its RPM is this high (%): the starter cranks it from 0 (inferred: a cold engine
/// reads 0, the JFS cranks it to 20 %).
pub const ENGINE_TURNING_RPM: f64 = 5.0;
/// The jet has left its parking spot once its centre is this far from where it stood at the start (m, inferred: two
/// thirds of an F-16's length, far more than brake creep or the jolt of the engine start).
pub const TAXI_MOVED_M: f64 = 10.0;
/// Lined up on a runway: the jet's heading within this of the runway end's (deg, inferred: a jet turning onto it
/// from a taxiway at 90° is not yet lined up; a backtrack on it is).
pub const LINED_UP_DEG: f64 = 30.0;

// --- Strings ----------------------------------------------------------------------------------------------------------

/// Every debrief string: (id, English, Hebrew).
const STRINGS: &[(&str, &str, &str)] = &[
    ("pass", "Pass", "עבר"),
    ("fail", "Fail", "נכשל"),
    ("grade_unsat", "Unsatisfactory", "לא מספק"),
    ("grade_below", "Below average", "מתחת לממוצע"),
    ("grade_average", "Average", "ממוצע"),
    ("grade_above", "Above average", "מעל לממוצע"),
    ("lesson_unsat", "Unsatisfactory", "לא מספק"),
    ("lesson_marginal", "Marginal", "גבולי"),
    ("lesson_pass", "Pass", "עבר"),
    ("startup", "Start-up", "התנעה"),
    ("takeoff", "Take-off", "המראה"),
    ("range", "Weapons range", "מטווח"),
    ("lesson", "Lesson", "שיעור"),
    ("lesson_not_done", "The lesson did not reach its end.", "השיעור לא הגיע לסופו."),
    // Fail reasons.
    ("no_start", "The engine never started.", "המנוע לא הותנע."),
    ("over_time", "Not done within the time budget.", "לא הושלם בזמן שהוקצב."),
    ("no_liftoff", "The jet never left the ground.", "המטוס לא המריא."),
    ("ejected", "The pilot ejected.", "בוצעה נטישה מהמטוס."),
    ("crash", "The jet crashed.", "המטוס התרסק."),
    ("damage", "The jet was damaged.", "המטוס נפגע."),
    ("off_pavement", "The jet left the pavement.", "המטוס ירד מהמשטח הסלול."),
    ("not_done", "The engine never reached idle with the avionics up.", "המנוע לא הגיע לסרק עם אוויוניקה פועלת."),
    // The start-up checklist's faults (iaf_flight start.rs `press`) and skipped steps.
    ("no_power", "The starter had no power: the main power was off.", "למתנע לא היה מתח: המתח הראשי היה כבוי."),
    (
        "hot_start",
        "Hot start: the throttle went to idle below 20 % RPM; the engine was shut down.",
        "המצערת הועברה לסרק מתחת ל־20% סל\"ד (Hot start); המנוע כובה.",
    ),
    (
        "no_rotation",
        "No light-off: the throttle went to idle with the engine not turning.",
        "אין הצתה: המצערת הועברה לסרק כשהמנוע לא הסתובב.",
    ),
    (
        "no_fuel",
        "No light-off: the throttle went to idle with no fuel to the engine (MASTER FUEL or ENG FEED off).",
        "אין הצתה: המצערת הועברה לסרק בלי דלק למנוע (MASTER FUEL או ENG FEED כבויים).",
    ),
    (
        "shutdown",
        "Engine shutdown: the throttle went to OFF with the engine running.",
        "כיבוי מנוע: המצערת הועברה ל־OFF כשהמנוע פעל.",
    ),
    (
        "starter_high",
        "Starter while the engine wound down above 20 % RPM: it did not engage.",
        "מתנע בזמן שהמנוע האט מעל 20% סל\"ד: הוא לא הופעל.",
    ),
    ("no_ipp", "Engine start without the IPP running.", "התנעת מנוע בלי שה־IPP פועל."),
    ("ipp_not_ready", "Engine start before the IPP was up to speed.", "התנעת מנוע לפני שה־IPP הגיע למהירות."),
    (
        "avionics_early",
        "Avionics power on before the generators: no power for them.",
        "מתח אוויוניקה הופעל לפני הגנרטורים: לא היה להם מתח.",
    ),
    ("ins_no_power", "INS alignment without main power.", "יישור הניווט האינרציאלי ללא מתח ראשי."),
    ("skip_main_power", "Skipped: main power.", "לא בוצע: מתח ראשי."),
    ("skip_starter", "Skipped: the starter.", "לא בוצע: המתנע."),
    ("skip_engine", "Skipped: the engine start.", "לא בוצע: התנעת המנוע."),
    ("skip_avionics", "Skipped: avionics power.", "לא בוצע: מתח אוויוניקה."),
    ("skip_ins", "Skipped: INS alignment.", "לא בוצע: יישור הניווט האינרציאלי."),
    ("skip_canopy", "Skipped: the canopy.", "לא בוצע: החופה."),
    (
        "skip_item",
        "Skipped: a checklist item (the notebook's CHECKLIST page shows which).",
        "לא בוצע: פריט בבד\"ח (עמוד הבד\"ח במחברת מראה איזה).",
    ),
    ("wrong_runway", "The take-off was not from the assigned runway.", "ההמראה לא הייתה מהמסלול שהוקצה."),
    ("excursion", "The jet left the runway during the take-off roll.", "המטוס יצא מהמסלול בזמן ריצת ההמראה."),
    ("gear_down", "The gear was never raised.", "כן הנסע לא נאסף."),
    ("off_heading", "Not on the runway heading with the gear up.", "לא בכיוון המסלול עם כן נסע אסוף."),
    ("short_air_kills", "Fewer drones shot down than the range asks.", "הופלו פחות מל\"טים ממה שהמטווח דורש."),
    (
        "short_ground_kills",
        "Fewer ground targets destroyed than the range asks.",
        "הושמדו פחות מטרות קרקע ממה שהמטווח דורש.",
    ),
    // A phase without the tower's clearance (`Watch::check`, training.md §3.3).
    ("no_start_clearance", "Engine start without start-up clearance.", "התנעה ללא אישור התנעה מהמגדל."),
    ("no_taxi_clearance", "Taxied without clearance.", "הסעה ללא אישור הסעה מהמגדל."),
    ("no_runway_clearance", "Entered the runway without clearance.", "כניסה למסלול ללא אישור מהמגדל."),
    ("no_takeoff_clearance", "Take-off roll without take-off clearance.", "ריצת המראה ללא אישור המראה מהמגדל."),
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
    ("air_kills", "Drones shot down", "מל\"טים שהופלו"),
    ("ground_kills", "Ground targets destroyed", "מטרות קרקע שהושמדו"),
    ("cut_lines", "Lines cut off at the recording's end, skipped", "שורות קטועות בסוף ההקלטה, שהושמטו"),
    // The sheet's goals ({} the figures of the label).
    ("goal_runway", "Take off from runway {}", "המראה ממסלול {}"),
    ("goal_time", "Within {} min of the start", "תוך {} דקות מההתחלה"),
    ("goal_heading", "Gear up on the runway heading (±{}°)", "איסוף כן הנסע בכיוון המסלול (±{}°)"),
    ("goal_centreline", "Offset from the centreline during the roll", "סטייה מקו המרכז בריצת ההמראה"),
    (
        "goal_liftoff",
        "Lift-off speed against the reference at this weight",
        "מהירות ניתוק מול המהירות המומלצת במשקל זה",
    ),
    ("goal_calls", "Tower calls", "קריאות למגדל"),
    ("goal_startup_time", "Idle with the avionics up within {} min", "סרק ואוויוניקה פועלת תוך {} דקות"),
    ("goal_checklist", "Checklist steps done", "שלבי הבד\"ח שבוצעו"),
    ("goal_air_kills", "Shoot down {} drones", "הפלת {} מל\"טים"),
    ("goal_ground_kills", "Destroy {} ground targets", "השמדת {} מטרות קרקע"),
    ("goal_range_time", "Within {} min of the start", "תוך {} דקות מההתחלה"),
    // The "Next time" tips.
    ("next_runway", "Line up on runway {}, the one the tower names.", "להיכנס למסלול {}, המסלול שהמגדל מציין."),
    (
        "next_time",
        "Ask the tower for the next step as soon as the last one is done: {} min are allowed.",
        "לבקש מהמגדל את השלב הבא מיד עם סיום הקודם: מוקצות {} דקות.",
    ),
    (
        "next_heading",
        "Raise the gear right after the lift-off, on the runway heading, before any turn.",
        "לאסוף את כן הנסע מיד אחרי הניתוק, בכיוון המסלול, לפני כל פנייה.",
    ),
    (
        "next_centreline",
        "Keep the nose on the centreline with the rudder pedals through the whole roll.",
        "לשמור את האף על קו המרכז בעזרת דוושות ההגה לאורך כל הריצה.",
    ),
    (
        "next_fast",
        "Lift-off was {} kt above the reference speed. Start the rotation at {} kt.",
        "הניתוק היה {} קשר מעל המהירות המומלצת. להתחיל להרים את האף ב־{} קשר.",
    ),
    (
        "next_slow",
        "Lift-off was {} kt below the reference speed. Wait for {} kt before the rotation.",
        "הניתוק היה {} קשר מתחת למהירות המומלצת. להמתין ל־{} קשר לפני הרמת האף.",
    ),
    (
        "next_calls",
        "Call the tower before each phase: start-up, taxi, line-up and take-off.",
        "לקרוא למגדל לפני כל שלב: התנעה, הסעה, כניסה למסלול והמראה.",
    ),
    (
        "next_startup_time",
        "Go on to the next step as soon as the last one is done: {} min are allowed.",
        "לעבור לשלב הבא מיד עם סיום הקודם: מוקצות {} דקות.",
    ),
    ("next_checklist", "Work the checklist from the top: every step counts.", "לבצע את הבד\"ח מההתחלה: כל שלב נספר."),
    (
        "next_air_kills",
        "Find a drone on the radar, lock it and close to the gun's range, or launch a missile once the HUD shows it in range.",
        "לאתר מל\"ט במכ\"ם, לנעול עליו ולהתקרב לטווח התותח, או לשגר טיל כשהתצוגה העילית מראה שהוא בטווח.",
    ),
    (
        "next_range_time",
        "Fly to the range right after the take-off: {} min are allowed.",
        "לטוס למטווח מיד אחרי ההמראה: מוקצות {} דקות.",
    ),
    (
        "next_ground_kills",
        "Select the bombs, set the master arm and release with the pipper on the target.",
        "לבחור את הפצצות, להעביר את מתג החימוש הראשי לחמוש ולשחרר כשהכוונת על המטרה.",
    ),
    (
        "next_pavement",
        "Keep the nosewheel on the taxiway's centreline and slow down before each turn.",
        "לשמור את גלגל האף על קו המרכז של המסלול המוביל ולהאט לפני כל פנייה.",
    ),
    ("next_clearance", "Wait for the tower's answer before each phase.", "להמתין לתשובת המגדל לפני כל שלב."),
    (
        "next_liftoff",
        "Open the throttle to full on the runway and raise the nose as the speed nears the reference.",
        "לפתוח מצערת מלאה על המסלול ולהרים את האף כשהמהירות מתקרבת למהירות המומלצת.",
    ),
    ("next_start", "Start the engine once the tower clears the start-up.", "להתניע את המנוע לאחר אישור ההתנעה מהמגדל."),
    // The flight's phases and marked events (the debrief's map and graphs, `track`).
    ("ph_startup", "Start-up", "התנעה"),
    ("ph_taxi", "Taxi", "הסעה"),
    ("ph_hold", "Hold", "המתנה"),
    ("ph_roll", "Roll", "ריצה"),
    ("ph_airborne", "Airborne", "באוויר"),
    ("ev_liftoff", "lift-off", "ניתוק"),
    ("ev_rotation", "rotation", "הרמת האף"),
    ("ev_gear_up", "gear up", "איסוף כן"),
    ("ev_peak_g", "peak", "שיא"),
    ("ev_touchdown", "touchdown", "נגיעה"),
    ("ev_crash", "crash", "התרסקות"),
    ("ev_hit", "hit", "פגיעה"),
    ("ev_eject", "ejection", "נטישה"),
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

/// A training mission's pass / fail rules (the mission file's `"training"`, modern-iaf/docs/data-formats.md §5).
#[derive(Debug, Clone, PartialEq)]
pub struct Rules {
    pub kind: Kind,
    pub time_budget_s: f64,
    /// A fail shows its reason this long before the debrief (a pass: the flight goes on).
    pub end_hold_s: f64,
    /// The debrief items the sheet shows, in order (ids of ITEMS).
    pub goals: Vec<String>,
    /// A start-up lesson: the ids of the jet's checklist card's items it asks for, in order (training.md §7.1, §12);
    /// empty: none.
    pub checklist: Vec<String>,
    /// The phases that need the tower's clearance first (ids of CLEARANCES, training.md §3.3); empty: none.
    pub clearances: Vec<&'static str>,
}

/// Every phase a mission's `clearances` may name: the engine start, leaving the parking spot, entering the runway
/// and the take-off roll ("takeoff": both).
pub const CLEARANCES: [&str; 3] = ["startup", "taxi", "takeoff"];

/// The places a part of the briefing's explanation is done at (a paragraph's `at` in the mission's `briefing.how`; the
/// briefing map's pins): the start (the parking spot), the holding point (the taxi's last point before the lineup,
/// iaf.ibx's `TaxiWayPtsFrom`, as the flight's radio menu takes it), the lineup point.
pub const STEP_PLACES: [&str; 3] = ["start", "hold", "lineup"];

/// The flight model's start-up steps (iaf_flight start.rs `Start::press`): the card's items of these ids are the start
/// itself, each with its own "skipped" line; any other card item skipped is `skip_item`.
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
    /// The kills the range asks for: drones, then ground targets.
    Range {
        air_kills: usize,
        ground_kills: usize,
    },
    /// A course lesson (training.md §16.2): its end's tests and the radio calls it asks for; its items are graded
    /// against the course's standards.
    Lesson {
        end: Vec<String>,
        calls: Vec<String>,
    },
}

/// Every debrief item id a mission's `goals` may name.
pub const ITEMS: [&str; 21] = [
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
    "air_kills",
    "ground_kills",
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
        Some("range") => {
            let kills = |k: &str| {
                t[k].as_u64().map(|n| n as usize).with_context(|| format!("training: \"{k}\" must be a count"))
            };
            let (air_kills, ground_kills) = (kills("air_kills")?, kills("ground_kills")?);
            ensure!(air_kills + ground_kills > 0, "training: a range asks for at least one kill");
            Kind::Range { air_kills, ground_kills }
        }
        Some("lesson") => {
            ensure!(mission["lesson"].is_string(), "training: a lesson mission needs \"lesson\", its course key");
            let list = |k: &str| -> Result<Vec<String>> {
                let a = t[k].as_array().with_context(|| format!("training: \"{k}\" must be a list"))?;
                a.iter()
                    .map(|x| x.as_str().map(String::from).with_context(|| format!("training: \"{k}\": {x}")))
                    .collect()
            };
            let (end, calls) = (list("end")?, list("calls")?);
            ensure!(!end.is_empty(), "training: a lesson needs its \"end\"");
            for e in &end {
                let name = e.split_once(':').map_or(e.as_str(), |(k, _)| k);
                ensure!(
                    course::test_ok(e) && END_TESTS.contains(&name),
                    "training: \"end\": {e} is no test the scorer reads ({END_TESTS:?}, training.md §16.3)"
                );
            }
            Kind::Lesson { end, calls }
        }
        k => bail!("training: \"kind\" must be \"startup\", \"takeoff\", \"range\" or \"lesson\", not {k:?}"),
    };
    let checklist = t["checklist"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|c| {
            let id = c.as_str().unwrap_or("");
            ensure!(
                !id.is_empty() && id.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_'),
                "training: checklist {c} is no card item id (the jet's data/checklists file, training.md §12)"
            );
            Ok(id.to_string())
        })
        .collect::<Result<_>>()?;
    let clearances = t["clearances"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|c| {
            let id = CLEARANCES.iter().find(|k| c.as_str() == Some(**k)).copied();
            id.with_context(|| format!("training: \"clearances\": {c} is no phase"))
        })
        .collect::<Result<Vec<_>>>()?;
    ensure!(
        !clearances.contains(&"takeoff") || mission["runway"].is_string(),
        "training: a take-off clearance needs the mission's \"runway\""
    );
    let (time_budget_s, end_hold_s) = (num("time_budget_s")?, num("end_hold_s")?);
    Ok(Some(Rules { kind, time_budget_s, end_hold_s, goals, checklist, clearances }))
}

/// The rules' figures, each needing a source in the mission file (data-formats.md §1).
pub const FIGURES: [&str; 7] = [
    "training.air_kills",
    "training.ground_kills",
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
    /// The load factor (g), where the recording has the column.
    pub g: Option<f64>,
    pub heading: f64,
    pub pitch: f64,
    pub on_ground: bool,
    pub engine: bool,
    pub throttle: f64,
    pub gear: bool,
    pub fuel_kg: f64,
    pub rpm: Option<f64>,
    pub avionics: Option<bool>,
    /// The electrical power: 0 none, 1 the battery, 2 the displays up (version 2 of the recorder).
    pub power: Option<i64>,
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
    let (agl, g, rpm, avionics, power) = (col("agl_m"), col("g"), col("rpm"), col("avionics"), col("power"));
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
            g: g.and_then(|i| r.get(i)?.as_f64()),
            heading: n(heading),
            pitch: n(pitch),
            on_ground: b(ground),
            engine: b(engine),
            throttle: n(throttle),
            gear: b(gear),
            fuel_kg: n(fuel),
            rpm: rpm.and_then(|i| r.get(i)?.as_f64()),
            avionics: avionics.and_then(|i| r.get(i)?.as_bool()),
            power: power.and_then(|i| r.get(i)?.as_i64()),
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
    /// (`runway_start_m` of each end, modern-iaf/docs/airbases.md §4).
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
    /// The items the sheet shows (the rules' `goals`; records from before `checks`).
    pub goals: Vec<String>,
    /// The sheet's goals: what the mission asks against what was flown, marked.
    pub checks: Vec<Check>,
    /// The flight's combat record (`combat_log::count`), `{}` without combat.
    pub combat: Value,
    /// The faults with their place on the track, in time order.
    pub faults: Vec<Fault>,
    /// The course lesson the mission flies (`course::Course::lesson_of`, its key), None outside the course.
    pub lesson: Option<String>,
    /// A course lesson's graded items (training.md §16.2), each against its course standard; empty outside one.
    pub graded: Vec<Graded>,
}

/// A course item graded: its id, its label and standard (course.json) and the flown value (None: not flown).
#[derive(Debug, Clone, PartialEq)]
pub struct Graded {
    pub id: String,
    pub label: Value,
    pub standard: Standard,
    pub flown: Option<f64>,
    /// Where it was flown (the engine frame, [x, y], the track's frame): the sample its value comes from; None for an
    /// item of the whole flight (a count, a share).
    pub at: Option<[f64; 2]>,
    /// The item's comment (course.json `tip`), said when it is graded Below average or Unsatisfactory.
    pub tip: Option<Value>,
}

/// A fault of the flight (a fail reason's id) with its place on the track: its time from the start (s) and the
/// sample's place there (the engine frame, m).
#[derive(Debug, Clone, PartialEq)]
pub struct Fault {
    pub id: &'static str,
    pub t: f64,
    pub at: [f64; 2],
}

/// The fault `id` at sample `i` of `s`.
fn fault(s: &[Sample], i: usize, id: &'static str) -> Fault {
    Fault { id, t: s[i].t - s[0].t, at: [s[i].x, s[i].y] }
}

/// A figure of a goal: a value with its unit, a name ("25R"), or neither (not reached).
#[derive(Debug, Clone, PartialEq)]
pub struct Figure {
    pub value: Option<f64>,
    pub text: Option<String>,
    pub unit: &'static str,
}

impl Figure {
    fn value(v: f64, unit: &'static str) -> Figure {
        Figure { value: Some(v), text: None, unit }
    }

    fn text(t: &str) -> Figure {
        Figure { value: None, text: Some(t.into()), unit: "" }
    }

    fn none(unit: &'static str) -> Figure {
        Figure { value: None, text: None, unit }
    }

    fn to_json(&self) -> Value {
        let mut v = json!({"value": self.value.map(|v| (v * 10.0).round() / 10.0), "unit": self.unit});
        if let Some(t) = &self.text {
            v["text"] = json!(t);
        }
        v
    }
}

/// How a goal's target reads: as it is ("25R", "159 kt"), an upper limit ("max 10 m") or a value with a tolerance
/// ("247° ±10").
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Bound {
    Exact,
    Max,
    Tol(f64),
}

/// A goal's mark on the sheet: met (✓), off the mark without failing the mission (!), failed (✗).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Mark {
    Ok,
    Warn,
    Fail,
}

/// A goal row of the debrief sheet: its label (string `id`, each "{}" filled from `args`), the target, the flown
/// figure and the mark.
#[derive(Debug, Clone, PartialEq)]
pub struct Check {
    pub id: &'static str,
    pub args: Vec<String>,
    pub target: Figure,
    pub bound: Bound,
    pub flown: Figure,
    pub mark: Mark,
}

impl Check {
    /// The standard its grade is read against (course::Standard): its tolerance, half of it Above average and
    /// twice it Below average; an upper limit, half of it Above average; the lift-off speed within LIFTOFF_WARN_KT
    /// of the reference, half of it Above average; a count at least the target, fewer Below average. None for a
    /// name ("25R"). Inferred.
    pub fn standard(&self) -> Option<Standard> {
        let t = self.target.value?;
        let (limit, bands) = match self.bound {
            Bound::Tol(tol) => (Limit::Tol(t), [tol / 2.0, tol, 2.0 * tol]),
            Bound::Max => (Limit::Max, [t / 2.0, t, t]),
            Bound::Exact if self.id == "goal_liftoff" => {
                (Limit::Tol(t), [LIFTOFF_WARN_KT / 2.0, LIFTOFF_WARN_KT, f64::INFINITY])
            }
            Bound::Exact => (Limit::Min, [t, t, 0.0]),
        };
        Some(Standard { limit, bands, unit: self.target.unit.to_string() })
    }

    /// Its grade: the standard's, at least Average when met, at most Below average off the mark, Unsatisfactory when
    /// failed; a name: Above average when met.
    pub fn grade(&self) -> Grade {
        let g = self.standard().map_or(Grade::AboveAverage, |s| s.grade(self.flown.value));
        match self.mark {
            Mark::Ok => g.max(Grade::Average),
            Mark::Warn => g.min(Grade::BelowAverage),
            Mark::Fail => Grade::Unsatisfactory,
        }
    }

    /// The gap: the flown value less what should have been flown; None for a name or nothing flown.
    pub fn gap(&self) -> Option<f64> {
        self.standard().zip(self.flown.value).map(|(s, f)| s.gap(f))
    }
}

/// The string `id` in language `lang` (0 English, 1 Hebrew) with each "{}" filled from `args` in turn.
fn fill(id: &str, lang: usize, args: &[String]) -> String {
    let t = STRINGS.iter().find(|s| s.0 == id).map_or("?", |s| if lang == 0 { s.1 } else { s.2 });
    let mut out = String::new();
    let mut parts = t.split("{}");
    out += parts.next().unwrap_or("");
    for (i, p) in parts.enumerate() {
        out += args.get(i).map_or("", String::as_str);
        out += p;
    }
    out
}

impl Debrief {
    /// The record the debrief page renders: values, units, and every string it names in English and Hebrew.
    pub fn to_json(&self) -> Value {
        let grade = self.grade();
        let lesson_id = format!("lesson_{}", grade.id());
        let mut grade_ids: Vec<String> = self.checks.iter().map(|c| format!("grade_{}", c.grade().id())).collect();
        grade_ids.extend(self.graded.iter().map(|g| format!("grade_{}", g.standard.grade(g.flown).id())));
        let mut ids: Vec<&str> = vec![if self.pass { "pass" } else { "fail" }, self.kind, &lesson_id];
        ids.extend(grade_ids.iter().map(String::as_str));
        ids.extend(&self.reasons);
        ids.extend(self.faults.iter().map(|f| f.id));
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
            "checks": self.checks.iter().map(|c| {
                let mut target = c.target.to_json();
                match c.bound {
                    Bound::Exact => {}
                    Bound::Max => target["max"] = json!(true),
                    Bound::Tol(t) => target["tol"] = json!(t),
                }
                json!({
                    "id": c.id,
                    "label": {"en": fill(c.id, 0, &c.args), "he": fill(c.id, 1, &c.args)},
                    "target": target,
                    "flown": c.flown.to_json(),
                    "mark": match c.mark { Mark::Ok => "ok", Mark::Warn => "warn", Mark::Fail => "fail" },
                    "gap": c.gap().map(|g| (g * 10.0).round() / 10.0),
                    "grade": c.grade().id(),
                })
            }).collect::<Vec<_>>(),
            "next": self.next().map(|(id, args)| json!({"en": fill(id, 0, &args), "he": fill(id, 1, &args)})),
            "strings": {"en": strings(0), "he": strings(1)},
            "combat": self.combat,
            "grade": grade.id(),
            "lesson": self.lesson,
            "graded": self.graded.iter().map(|g| json!({
                "id": g.id,
                "label": g.label,
                "standard": g.standard.to_json(),
                "should": g.standard.should(),
                "flown": g.flown.map(|v| (v * 10.0).round() / 10.0),
                "gap": g.flown.map(|f| (g.standard.gap(f) * 10.0).round() / 10.0),
                "grade": g.standard.grade(g.flown).id(),
                "at": g.at.map(|a| [(a[0] * 10.0).round() / 10.0, (a[1] * 10.0).round() / 10.0]),
                "comment": match g.standard.grade(g.flown) {
                    Grade::BelowAverage | Grade::Unsatisfactory => g.tip.clone(),
                    _ => None,
                },
            })).collect::<Vec<_>>(),
            "faults": self.faults.iter().map(|f| json!({
                "id": f.id,
                "t": (f.t * 10.0).round() / 10.0,
                "at": [(f.at[0] * 10.0).round() / 10.0, (f.at[1] * 10.0).round() / 10.0],
            })).collect::<Vec<_>>(),
        })
    }

    /// The lesson's grade (course::lesson_grade): from the flight's pass and its checks' grades.
    pub fn grade(&self) -> LessonGrade {
        let mut grades: Vec<Grade> = self.checks.iter().map(Check::grade).collect();
        grades.extend(self.graded.iter().map(|g| g.standard.grade(g.flown)));
        course::lesson_grade(self.pass, &grades)
    }

    /// The "Next time" remark: the tip for the reason that failed it first, else for the first goal not met; None
    /// when every goal is met. (string id, its arguments)
    pub fn next(&self) -> Option<(&'static str, Vec<String>)> {
        let check = |id: &str| self.checks.iter().find(|c| c.id == id);
        let runway = || vec![check("goal_runway").and_then(|c| c.target.text.clone()).unwrap_or_default()];
        for r in &self.reasons {
            match *r {
                "off_pavement" => return Some(("next_pavement", vec![])),
                "excursion" => return Some(("next_centreline", vec![])),
                "wrong_runway" => return Some(("next_runway", runway())),
                "no_liftoff" => return Some(("next_liftoff", vec![])),
                "no_start" => return Some(("next_start", vec![])),
                r if r.starts_with("no_") && r.ends_with("_clearance") => return Some(("next_clearance", vec![])),
                _ => {}
            }
        }
        let c = self.checks.iter().find(|c| c.mark != Mark::Ok)?;
        let minutes = c.args.first().cloned().unwrap_or_default();
        Some(match c.id {
            "goal_runway" => ("next_runway", runway()),
            "goal_time" => ("next_time", vec![minutes]),
            "goal_heading" => ("next_heading", vec![]),
            "goal_centreline" => ("next_centreline", vec![]),
            "goal_liftoff" => {
                let (flown, target) = (c.flown.value.unwrap_or(0.0), c.target.value.unwrap_or(0.0));
                let rotate = format!("{}", target - ROTATE_BEFORE_KT);
                let d = format!("{}", (flown - target).abs());
                if flown > target { ("next_fast", vec![d, rotate]) } else { ("next_slow", vec![d, rotate]) }
            }
            "goal_calls" => ("next_calls", vec![]),
            "goal_startup_time" => ("next_startup_time", vec![minutes]),
            "goal_air_kills" => ("next_air_kills", vec![]),
            "goal_ground_kills" => ("next_ground_kills", vec![]),
            "goal_range_time" => ("next_range_time", vec![minutes]),
            _ => ("next_checklist", vec![]),
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
/// files (`modern-iaf/data/airbases/*.json`), read for a take-off.
pub fn score(flight: &Flight, mission: &Value, airbases: &[Value]) -> Result<Debrief> {
    let id = mission["id"].as_str().unwrap_or("?").to_string();
    ensure!(!flight.samples.is_empty(), "the recording has no samples");
    let r = rules(mission)?.with_context(|| format!("{id}: no \"training\" rules"))?;
    let failed = hard_fail(&flight.events);
    let mut d = match &r.kind {
        Kind::Startup => {
            let mut d = startup(flight, id, r.time_budget_s);
            // A card item not ticked (its last `item` event is not an untick, "on": false) fails it; the switches'
            // own `step` events carry the start-up's faults only.
            let done = |step: &str| {
                let last = flight.events.iter().rev().find(|e| e["event"] == "checklist" && e["item"] == step);
                last.is_some_and(|e| e["on"] != false)
            };
            for step in r.checklist.iter().filter(|s| !done(s.as_str())) {
                d.reasons.push(string_id(&format!("skip_{step}")).unwrap_or("skip_item"));
            }
            if !r.checklist.is_empty() {
                let n = r.checklist.iter().filter(|s| done(s.as_str())).count();
                d.checks.push(Check {
                    id: "goal_checklist",
                    args: vec![],
                    target: Figure::value(r.checklist.len() as f64, ""),
                    bound: Bound::Exact,
                    flown: Figure::value(n as f64, ""),
                    mark: if n == r.checklist.len() { Mark::Ok } else { Mark::Fail },
                });
            }
            d.pass = d.reasons.is_empty();
            d
        }
        Kind::Takeoff { heading_tolerance_deg, empty_kg, takeoff_kt } => {
            let airbase = airbase_of(mission, airbases)?;
            let base = sim_bases::base(airbase, &format!("{id}: start.base"))?;
            let rw = runway(airbase, base.mission_runway(mission).unwrap_or(""))?;
            let t = Takeoff {
                rw: &rw,
                base: &base,
                tolerance: *heading_tolerance_deg,
                empty_kg: *empty_kg,
                takeoff_kt,
                clearances: &r.clearances,
            };
            takeoff(flight, id, &t, r.time_budget_s, failed.is_some())
        }
        Kind::Range { air_kills, ground_kills } => range(flight, id, [*air_kills, *ground_kills], r.time_budget_s),
        Kind::Lesson { calls, .. } => lesson(flight, id, mission, &r, calls)?,
    };
    d.goals = r.goals;
    d.combat = combat_log::count(&flight.events);
    if let Some(reason) = failed {
        d.fail_first(reason);
    }
    let s = &flight.samples;
    for e in &flight.events {
        let Some(id) = hard_fail(std::slice::from_ref(e)) else { continue };
        let t = e["t"].as_f64().unwrap_or(s[0].t);
        d.faults.push(fault(s, s.partition_point(|x| x.t < t).min(s.len() - 1), id));
    }
    // Each fault once, at its first time.
    d.faults.sort_by(|a, b| a.t.total_cmp(&b.t));
    let mut seen = vec![];
    d.faults.retain(|f| {
        !seen.contains(&f.id) && {
            seen.push(f.id);
            true
        }
    });
    d.lesson = course::course().lesson_of(mission["start"]["unit"].as_str().unwrap_or(""), &d.mission);
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
        Some("clearance") => e["reason"].as_str().and_then(string_id),
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
    /// Engine RPM, %; ground speed, kt; the engine-frame heading, deg.
    pub rpm: f64,
    pub speed_kt: f64,
    pub heading: f64,
    /// The tower's clearances so far.
    pub cleared: Cleared,
}

/// The tower's clearances a flight holds: each stays valid once given. A call asked and answered "hold position"
/// clears nothing.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Cleared {
    pub start: bool,
    pub taxi: bool,
    /// Line up (or take-off): the jet may enter the runway.
    pub lineup: bool,
    pub takeoff: bool,
}

impl Cleared {
    /// From the tower's answers so far (radio.gd's templates). `hot`: the flight started with the engine running,
    /// so the start, the taxi and the line-up count as cleared (a ground start at the lineup point).
    pub fn of(answers: &[String], hot: bool) -> Cleared {
        let got = |t: &[&str]| answers.iter().any(|a| t.contains(&a.as_str()));
        let takeoff = got(&["ACFT_CLEAR_TO_TAKEOFF"]);
        Cleared {
            start: hot || got(&["ACFT_CLEAR_TO_START"]),
            taxi: hot || got(&["ACFT_TAXI_TO_RUNWAY"]),
            lineup: hot || takeoff || got(&["ACFT_CLEAR_TO_LINEUP", "ACFT_CLEAR_TO_LINEUP_NW"]),
            takeoff,
        }
    }
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
    /// A take-off or range mission's runway end: (its index in the base's runways, the end's index).
    pub runway: Option<(usize, usize)>,
    /// Where the jet first stood on the ground (engine frame): its parking spot.
    pub spot: Option<[f64; 2]>,
}

impl Watch {
    /// A start-up step's fault as this run counts it: the throttle to OFF with the engine running (`cutoff`'s
    /// `shutdown`) is the shutdown a lesson asks for when its card holds `throttle_off` and the card's item to do now
    /// (`current`) is it (training.md §16.2), no fault (""); any other fault stands, a cut-off earlier in the lesson too.
    pub fn step_fault<'a>(&self, step: &str, fault: &'a str, current: &str) -> &'a str {
        let asked = self.rules.checklist.iter().any(|i| i == "throttle_off");
        let taught = step == "cutoff" && fault == "shutdown" && asked && current == "throttle_off";
        if taught { "" } else { fault }
    }

    /// The rules of the readable mission file `mission` and its base from the airbase files in `airbases`.
    pub fn open(mission: &std::path::Path, airbases: &std::path::Path) -> Result<Watch> {
        let m: Value =
            serde_json::from_str(&std::fs::read_to_string(mission).with_context(|| mission.display().to_string())?)
                .with_context(|| mission.display().to_string())?;
        let bases: Vec<_> = sim_bases::files(airbases)?;
        let rules = rules(&m)?.with_context(|| format!("{}: no \"training\" rules", mission.display()))?;
        let base = sim_bases::base(airbase_of(&m, &bases)?, &mission.display().to_string())?;
        let runway = match base.mission_runway(&m) {
            Some(d) if !matches!(rules.kind, Kind::Startup) => {
                Some(base.end(d).with_context(|| format!("{}: no runway {d}", mission.display()))?)
            }
            _ => None,
        };
        Ok(Watch { rules, base, runway, spot: None })
    }

    /// The fail reason of this moment, or None: ejected, crashed, any damage (0..1), on the ground off the
    /// pavement at the jet's centre (`x`, `y` in the engine frame), or a phase of the rules' `clearances` without
    /// the tower's clearance (`clearance`).
    pub fn check(&mut self, s: &Now) -> Option<&'static str> {
        let Now { on_ground, x, y, crashed, damage, ejected, .. } = *s;
        if on_ground && self.spot.is_none() {
            self.spot = Some([x, y]);
        }
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
        } else if self.wrong_roll(s) {
            Some("wrong_runway")
        } else {
            self.clearance(s)
        }
    }

    /// The runway end the jet runs along: on the ground, its centre on a runway (within half its width of the
    /// centreline), its heading within LINED_UP_DEG of end k's. (runway, end, the distance from end k along the
    /// runway, m), else None; a jet crossing a runway is on none.
    fn aligned(&self, s: &Now) -> Option<(usize, usize, f64)> {
        if !s.on_ground {
            return None;
        }
        let p = [s.x, s.y];
        let (i, r) = self.base.runways.iter().enumerate().find(|(_, r)| r.dist(p) <= r.width / 2.0)?;
        let k = usize::from(angle(r.heading(0), s.heading).abs() > 90.0);
        let (e, d) = (r.ends[k], r.dir(k));
        let along = (p[0] - e[0]) * d[0] + (p[1] - e[1]) * d[1];
        (angle(r.heading(k), s.heading).abs() <= LINED_UP_DEG).then_some((i, k, along))
    }

    /// The runway end the jet is lined up on (`aligned`) in the first half of the runway from that end, where a
    /// take-off from it starts: (runway, end), else None. A backtrack along the runway toward its take-off end (where no
    /// taxiway leads to the start) runs the far half on the other end's heading: not lined up.
    pub fn lined_up(&self, s: &Now) -> Option<(usize, usize)> {
        let (i, k, along) = self.aligned(s)?;
        (along < self.base.runways[i].length() / 2.0).then_some((i, k))
    }

    /// A take-off mission's jet lined up (`lined_up`) on a runway end other than the mission's: that end's designator
    /// ("07L", the airbase file's), else None. The tower warns at once.
    pub fn wrong_runway(&self, s: &Now) -> Option<String> {
        let mine = self.runway?;
        let (i, k) = self.lined_up(s).filter(|e| *e != mine)?;
        Some(self.base.runways[i].designators[k].clone())
    }

    /// A take-off mission's jet rolling (faster than ROLL_START_KT) along (`aligned`, anywhere on it) a runway end
    /// other than the mission's: the mission fails.
    fn wrong_roll(&self, s: &Now) -> bool {
        let mine = self.runway;
        mine.is_some() && s.speed_kt > ROLL_START_KT && self.aligned(s).is_some_and(|(i, k, _)| Some((i, k)) != mine)
    }

    /// The mission's runway end's designator ("25R"), "" for none.
    pub fn runway_designator(&self) -> &str {
        self.runway.map_or("", |(i, k)| &self.base.runways[i].designators[k])
    }

    /// The phase done without its clearance (training.md §3.3): the engine turning (ENGINE_TURNING_RPM) without
    /// start-up clearance; on the ground TAXI_MOVED_M from the spot without taxi clearance; on the mission's runway
    /// end's heading (`aligned`, anywhere along it) past the holding point without line-up or take-off clearance; so
    /// faster than ROLL_START_KT without take-off clearance.
    fn clearance(&self, s: &Now) -> Option<&'static str> {
        let need = |k: &str| self.rules.clearances.contains(&k);
        let c = s.cleared;
        let moved = self.spot.is_some_and(|p| (s.x - p[0]).hypot(s.y - p[1]) > TAXI_MOVED_M);
        // Entered: lined up on the mission's end and past the holding point, HOLDING_POINT_MARGIN_M short of the
        // lineup point at most (Nevatim's holding point is the runway's end itself, on the centreline).
        let on_runway = self.runway.is_some_and(|(i, k)| {
            let r = &self.base.runways[i];
            let (e, d, l) = (r.ends[k], r.dir(k), r.lineup(k));
            let st = |p: [f64; 2]| (p[0] - e[0]) * d[0] + (p[1] - e[1]) * d[1];
            self.aligned(s).is_some_and(|(j, m, _)| (j, m) == (i, k))
                && st([s.x, s.y]) >= st(l) - HOLDING_POINT_MARGIN_M
        });
        if need("startup") && !c.start && s.rpm >= ENGINE_TURNING_RPM {
            Some("no_start_clearance")
        } else if need("taxi") && !c.taxi && s.on_ground && moved {
            Some("no_taxi_clearance")
        } else if need("takeoff") && s.on_ground && on_runway && !c.lineup {
            Some("no_runway_clearance")
        } else if need("takeoff") && s.on_ground && on_runway && !c.takeoff && s.speed_kt > ROLL_START_KT {
            Some("no_takeoff_clearance")
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

/// The ground calls in their order (the clearances' order, training.md §8).
pub const GROUND_CALLS: [&str; 4] = ["startup", "taxi", "lineup", "takeoff"];

/// The radio menu's calls, in menu order (the user, 2026-11-13: "all radio calls should always be available. on ground
/// show only starting calls, in the air show landing"): every ground call and the radio check on the ground,
/// "landing" in the air.
pub fn radio_calls(s: &RadioNow) -> Vec<&'static str> {
    if s.on_ground { GROUND_CALLS.iter().copied().chain(["radio_check"]).collect() } else { vec!["landing"] }
}

/// The ground call a call `id` needs first, in GROUND_CALLS' order, while its clearance is missing (the tower then
/// answers "negative, hold position, request … first"), else None: take-off before line-up, line-up before taxi, taxi
/// before start-up.
pub fn missing_before(id: &str, answers: &[String], hot: bool) -> Option<&'static str> {
    let c = Cleared::of(answers, hot);
    let held = [c.start, c.taxi, c.lineup, c.takeoff];
    let i = GROUND_CALLS.iter().position(|g| *g == id)?;
    (0..i).find(|&k| !held[k]).map(|k| GROUND_CALLS[k])
}

/// The call the moment expects next, marked in the training missions' menu: "startup" on the ground with the engine
/// off; "taxi" on the ground with the engine running, the avionics up and taxi not yet; at the holding point or past
/// it (no farther from the lineup point than `hold_m` + HOLDING_POINT_MARGIN_M) "lineup" with taxi approved and
/// line-up not yet, then "takeoff" with line-up approved and take-off not yet; "landing" in the air. A hot ground
/// start has taxi and line-up approved. None between the calls.
pub fn next_call(s: &RadioNow) -> Option<&'static str> {
    let Cleared { taxi, lineup, takeoff, .. } = Cleared::of(&s.answers, s.hot);
    let g = s.on_ground;
    let hold = g && s.lineup_m <= s.hold_m + HOLDING_POINT_MARGIN_M;
    [
        ("startup", g && !s.engine_on),
        ("taxi", g && s.engine_on && s.avionics && !taxi),
        ("lineup", hold && taxi && !lineup),
        ("takeoff", hold && lineup && !takeoff),
        ("landing", !g),
    ]
    .into_iter()
    .find_map(|(id, on)| on.then_some(id))
}

/// Scores the recording at `flight` against the readable mission file `mission` with the airbase files in `airbases`
/// (the CLI `iaf-training score` and the game's `IafTraining`).
pub fn score_files(flight: &std::path::Path, mission: &std::path::Path, airbases: &std::path::Path) -> Result<Debrief> {
    ensure!(airbases.is_dir(), "no airbases folder {} (give it as the third argument)", airbases.display());
    let read = |p: &std::path::Path| std::fs::read_to_string(p).with_context(|| p.display().to_string());
    let f = parse_flight(&read(flight)?).with_context(|| flight.display().to_string())?;
    let m: Value = serde_json::from_str(&read(mission)?).with_context(|| mission.display().to_string())?;
    let bases: Vec<_> = sim_bases::files(airbases)?;
    score(&f, &m, &bases)
}

// --- The flight's track ----------------------------------------------------------------------------------------------

/// The flight's phases, in the order they come (`track`).
pub const PHASES: [&str; 5] = ["startup", "taxi", "hold", "roll", "airborne"];
/// The jet moves on the ground faster than this (kt; the take-off's own figure for the taxi's start).
const MOVING_KT: f64 = 1.0;
/// A stop on the ground shorter than this is part of the taxi (s, inferred: a pause at a turn is not a hold).
const HOLD_MIN_S: f64 = 5.0;
/// The highest load in the air is marked from this many g (inferred: above a gentle turn's 1.15 g).
const PEAK_G_MIN: f64 = 1.3;
/// The track keeps at most this many samples (inferred: a point a pixel or two across the debrief's graphs).
const TRACK_POINTS: usize = 1200;
const FT_PER_M: f64 = 3.28084;

/// A marked moment of the flight: its event id (`ev_*` without the prefix), its time from the start (s), the graph it
/// marks ("speed", "agl", "g", or "" all three) and the value there (kt, ft or g).
#[derive(Debug, Clone, PartialEq)]
pub struct Moment {
    pub id: &'static str,
    pub t: f64,
    pub graph: &'static str,
    pub value: f64,
}

/// The debrief's view of a recording (modern-iaf/docs/front-end.md §13): its samples thinned to TRACK_POINTS, each with its phase
/// (index of PHASES); the phases' runs; the marked events; the lift-off's sample (in the thinned samples).
#[derive(Debug, Default)]
pub struct Track {
    pub samples: Vec<Sample>,
    pub phase: Vec<usize>,
    /// (phase, from, to): times from the start, s.
    pub runs: Vec<(usize, f64, f64)>,
    pub marks: Vec<Moment>,
    pub lift: Option<usize>,
}

/// The phases of every sample: the start-up until the jet first moves; on the ground then the taxi, a hold where it
/// stands HOLD_MIN_S or longer, the take-off roll from its start (`roll_start` on the mission's runway `rw`, else the
/// last moment below ROLL_START_KT) to the lift-off; airborne after it.
fn phases(s: &[Sample], lift: Option<usize>, rw: Option<&Runway>) -> Vec<usize> {
    let roll = lift.map(|l| match rw {
        Some(rw) => roll_start(s, l, rw).0,
        None => s[..l].iter().rposition(|x| x.speed_kt < ROLL_START_KT).unwrap_or(0),
    });
    let moved = s.iter().position(|x| x.speed_kt > MOVING_KT || !x.on_ground);
    let mut ph: Vec<usize> = (0..s.len())
        .map(|i| {
            if lift.is_some_and(|l| i >= l) && !s[i].on_ground {
                4
            } else if roll.is_some_and(|r| i >= r) && lift.is_some_and(|l| i < l) {
                3
            } else if moved.is_none_or(|m| i < m) {
                0
            } else if s[i].speed_kt <= MOVING_KT {
                2
            } else {
                1
            }
        })
        .collect();
    // A short stop is taxi.
    let mut i = 0;
    while i < ph.len() {
        let end = i + ph[i..].iter().take_while(|p| **p == ph[i]).count();
        if ph[i] == 2 && s[end - 1].t - s[i].t < HOLD_MIN_S {
            ph[i..end].fill(1);
        }
        i = end;
    }
    ph
}

/// The track of flight `f`, its take-off roll on the runway `rw` (a take-off mission's).
pub fn track(f: &Flight, rw: Option<&Runway>) -> Track {
    let s = &f.samples;
    if s.is_empty() {
        return Track::default();
    }
    let t0 = s[0].t;
    let lift = liftoff(s);
    let ph = phases(s, lift, rw);
    let mut runs: Vec<(usize, f64, f64)> = vec![];
    for (i, p) in ph.iter().enumerate() {
        match runs.last_mut() {
            Some(r) if r.0 == *p => r.2 = s[i].t - t0,
            _ => {
                if let Some(r) = runs.last_mut() {
                    r.2 = s[i].t - t0;
                }
                runs.push((*p, s[i].t - t0, s[i].t - t0));
            }
        }
    }
    let mut marks = vec![];
    let at = |i: usize, id: &'static str, graph: &'static str, value: f64| Moment { id, t: s[i].t - t0, graph, value };
    if let Some(l) = lift {
        marks.push(at(l, "liftoff", "speed", s[l].speed_kt.round()));
        let roll = ph.iter().position(|p| *p == 3).unwrap_or(l);
        if let Some(r) = rotation(s, roll, l).filter(|&r| s[r].g.is_some()) {
            marks.push(at(r, "rotation", "g", s[r].g.unwrap_or(1.0)));
        }
        if let Some(i) = (l..s.len()).find(|&i| !s[i].gear && !s[i].on_ground) {
            marks.push(at(i, "gear_up", "agl", (s[i].agl_m.unwrap_or(0.0) * FT_PER_M).round()));
        }
        let peak = (l..s.len())
            .filter(|&i| !s[i].on_ground)
            .max_by(|&a, &b| s[a].g.unwrap_or(0.0).total_cmp(&s[b].g.unwrap_or(0.0)));
        if let Some(p) = peak.filter(|&p| s[p].g.unwrap_or(0.0) >= PEAK_G_MIN) {
            marks.push(at(p, "peak_g", "g", s[p].g.unwrap_or(0.0)));
        }
    }
    for e in &f.events {
        let id = match e["event"].as_str() {
            Some("touchdown") => "touchdown",
            Some("crash") => "crash",
            Some("hit") => "hit",
            Some("eject") => "eject",
            _ => continue,
        };
        marks.push(Moment { id, t: e["t"].as_f64().unwrap_or(t0) - t0, graph: "", value: 0.0 });
    }
    marks.sort_by(|a, b| a.t.total_cmp(&b.t));
    // Thinned: every step-th sample and the last; the lift-off's sample kept.
    let step = s.len().div_ceil(TRACK_POINTS).max(1);
    let keep: Vec<usize> = (0..s.len()).filter(|&i| i % step == 0 || i + 1 == s.len() || Some(i) == lift).collect();
    Track {
        lift: lift.and_then(|l| keep.iter().position(|&i| i == l)),
        samples: keep.iter().map(|&i| s[i].clone()).collect(),
        phase: keep.iter().map(|&i| ph[i]).collect(),
        runs,
        marks,
    }
}

impl Track {
    /// As JSON for the debrief: times from the start (s) and the places (the sim's frame, a flat [x, y, …]) of the
    /// samples, their speed (kt), height above the ground (ft), load (g; empty without the column) and phase (index
    /// of `phases`); the phases' runs; the marks; the pins (start, lift-off, end: a sample's index); every phase's and
    /// mark's name in English and Hebrew.
    pub fn to_json(&self) -> Value {
        let r1 = |v: f64| (v * 10.0).round() / 10.0;
        let s = &self.samples;
        let t0 = s.first().map_or(0.0, |x| x.t);
        let has_g = s.iter().any(|x| x.g.is_some());
        let mut pins = vec![json!({"id": "start", "i": 0})];
        if let Some(l) = self.lift {
            pins.push(json!({"id": "liftoff", "i": l}));
        }
        if s.len() > 1 {
            pins.push(json!({"id": "end", "i": s.len() - 1}));
        }
        let ids: Vec<String> =
            PHASES.iter().map(|p| format!("ph_{p}")).chain(self.marks.iter().map(|m| format!("ev_{}", m.id))).collect();
        let strings = |lang: usize| -> Map<String, Value> {
            ids.iter().map(|id| (id.clone(), json!(fill(id, lang, &[])))).collect()
        };
        json!({
            "t": s.iter().map(|x| r1(x.t - t0)).collect::<Vec<_>>(),
            "at": s.iter().flat_map(|x| [r1(x.x), r1(x.y)]).collect::<Vec<_>>(),
            "speed_kt": s.iter().map(|x| x.speed_kt.round()).collect::<Vec<_>>(),
            "agl_ft": s.iter().map(|x| (x.agl_m.unwrap_or(0.0).max(0.0) * FT_PER_M).round()).collect::<Vec<_>>(),
            "g": if has_g { s.iter().map(|x| (x.g.unwrap_or(1.0) * 100.0).round() / 100.0).collect::<Vec<f64>>() } else { vec![] },
            "phase": self.phase,
            "phases": PHASES,
            "runs": self.runs.iter().map(|r| json!({"phase": r.0, "from": r1(r.1), "to": r1(r.2)})).collect::<Vec<_>>(),
            "marks": self.marks.iter().map(|m| json!({"id": m.id, "t": r1(m.t), "graph": m.graph, "value": (m.value * 10.0).round() / 10.0})).collect::<Vec<_>>(),
            "pins": pins,
            "strings": {"en": strings(0), "he": strings(1)},
        })
    }
}

/// The track of the recording at `flight` (`track`), its roll on the runway of the readable mission file `mission`
/// (a take-off's; the airbase files in `airbases`), else without one.
pub fn track_files(flight: &std::path::Path, mission: &std::path::Path, airbases: &std::path::Path) -> Result<Track> {
    let read = |p: &std::path::Path| std::fs::read_to_string(p).with_context(|| p.display().to_string());
    let f = parse_flight(&read(flight)?).with_context(|| flight.display().to_string())?;
    let rw = (|| -> Result<Runway> {
        let m: Value = serde_json::from_str(&read(mission)?)?;
        let bases: Vec<_> = sim_bases::files(airbases)?;
        let airbase = airbase_of(&m, &bases)?;
        let base = sim_bases::base(airbase, &mission.display().to_string())?;
        runway(airbase, base.mission_runway(&m).context("no runway")?)
    })()
    .ok();
    Ok(track(&f, rw.as_ref()))
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
    let up = idle.zip(avionics).map(|(i, a)| i.max(a));
    let checks = vec![Check {
        id: "goal_startup_time",
        args: vec![format!("{}", (budget / 60.0).round())],
        target: Figure::value(budget, "s"),
        bound: Bound::Max,
        flown: Figure { value: up, ..Figure::none("s") },
        mark: if up.is_some_and(|u| u <= budget) { Mark::Ok } else { Mark::Fail },
    }];
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
        checks,
        combat: json!({}),
        faults: vec![],
        lesson: None,
        graded: vec![],
    }
}

/// The tests a lesson's `end` may name: the ones `holds` reads from the recording (training.md §16.3).
pub const END_TESTS: [&str; 7] = ["power_off", "engine_off", "idle", "aligned", "parked", "item", "called"];

/// The card items that set the cockpit for the night (data/checklists: the F-16s' interior lights, the F-35I's HMD).
const NIGHT_ITEMS: [&str; 2] = ["interior_lights", "hmd_night"];

/// Parked: on the ground, stopped, within this of the spot the flight started from, m (inferred: a shelter's pad).
pub const PARKED_M: f64 = 30.0;

/// Test `test` (END_TESTS) at sample `i` of the recording.
// ponytail: each event test scans the events at every sample (samples x events per score); walk them once alongside
// the samples if a long lesson's score shows in the frame time.
fn holds(f: &Flight, i: usize, test: &str) -> bool {
    let (s, x) = (&f.samples, &f.samples[i]);
    let before = |e: &&Value| e["t"].as_f64().is_some_and(|t| t <= x.t);
    let (name, arg) = test.split_once(':').unwrap_or((test, ""));
    match name {
        "power_off" => x.power == Some(0),
        "engine_off" => !x.engine && x.rpm.unwrap_or(0.0) < 1.0,
        "idle" => x.engine && x.rpm.unwrap_or(0.0) >= IDLE_RPM,
        "aligned" => {
            let ins = |e: &&Value| e["event"] == "checklist" && e["step"] == "ins" && e["fault"].is_null();
            f.events.iter().filter(before).any(|e| ins(&e))
        }
        "parked" => x.on_ground && x.speed_kt < 1.0 && (x.x - s[0].x).hypot(x.y - s[0].y) <= PARKED_M,
        "item" => {
            let last = f.events.iter().rev().filter(before).find(|e| e["event"] == "checklist" && e["item"] == arg);
            last.is_some_and(|e| e["on"] != false)
        }
        "called" => f.events.iter().filter(before).any(|e| e["event"] == "radio" && e["call"] == arg),
        _ => false,
    }
}

/// The time from the start the lesson's end came (training.md §16.2): the first sample where every test of `end` has
/// failed at least once since the start and all hold; None before it.
pub fn end_at(f: &Flight, end: &[String]) -> Option<f64> {
    let mut failed = vec![false; end.len()];
    for i in 0..f.samples.len() {
        let now: Vec<bool> = end.iter().map(|t| holds(f, i, t)).collect();
        for (k, h) in now.iter().enumerate() {
            failed[k] |= !h;
        }
        if failed.iter().all(|x| *x) && now.iter().all(|x| *x) {
            return Some(f.samples[i].t - f.samples[0].t);
        }
    }
    None
}

/// A course lesson (training.md §16.2): passed when its end came (`end_at`) within the time budget; each of the
/// lesson's course items graded against its standard from what `measure` reads of the recording.
fn lesson(f: &Flight, mission_id: String, mission: &Value, r: &Rules, calls: &[String]) -> Result<Debrief> {
    let key = mission["lesson"].as_str().unwrap_or("");
    let c = course::course();
    let (p, l) = c.find(key).with_context(|| format!("{mission_id}: \"lesson\" {key} is no lesson of the course"))?;
    let Kind::Lesson { end, .. } = &r.kind else { bail!("{mission_id}: not a lesson") };
    let end = end_at(f, end);
    let mut reasons = vec![];
    match end {
        None => reasons.push("lesson_not_done"),
        Some(t) if t > r.time_budget_s => reasons.push("over_time"),
        Some(_) => {}
    }
    let graded = c
        .items(p, l)
        .into_iter()
        .filter_map(|id| {
            let i = c.item(&id)?;
            let (flown, at) = measure(f, &id, r, calls);
            let at = at.map(|k| [f.samples[k].x, f.samples[k].y]);
            Some(Graded { label: i.label.clone(), standard: i.standard.clone(), flown, at, tip: i.tip.clone(), id })
        })
        .collect();
    Ok(Debrief {
        mission: mission_id,
        kind: "lesson",
        pass: reasons.is_empty(),
        reasons,
        items: vec![],
        goals: vec![],
        checks: vec![],
        combat: json!({}),
        faults: vec![],
        lesson: None,
        graded,
    })
}

/// A course item's flown value from the recording (training.md §16.2), with the sample it was flown at (None for an
/// item of the whole flight); None: not flown, or no measure for the item yet (each phase adds its items' measures
/// here).
fn measure(f: &Flight, id: &str, r: &Rules, calls: &[String]) -> (Option<f64>, Option<usize>) {
    let s = &f.samples;
    let t0 = s[0].t;
    let pct = |done: usize, of: usize| (of > 0).then(|| 100.0 * done as f64 / of as f64);
    let ticked = |item: &str| {
        let last = f.events.iter().rev().find(|e| e["event"] == "checklist" && e["item"] == item);
        last.is_some_and(|e| e["on"] != false)
    };
    // The taxi's start: the first sample on the ground farther than TAXI_MOVED_M from the start.
    let moved = s.iter().find(|x| x.on_ground && (x.x - s[0].x).hypot(x.y - s[0].y) > TAXI_MOVED_M).map(|x| x.t);
    let whole = |v: Option<f64>| (v, None);
    match id {
        "checklist_items" => whole(pct(r.checklist.iter().filter(|i| ticked(i)).count(), r.checklist.len())),
        "tower_calls" => {
            let made = |c: &String| f.events.iter().any(|e| e["event"] == "radio" && e["call"] == c.as_str());
            whole(pct(calls.iter().filter(|c| made(c)).count(), calls.len()))
        }
        // Placed where the later of the two came.
        "startup_time" => {
            let idle = s.iter().position(|x| x.engine && x.rpm.unwrap_or(0.0) >= IDLE_RPM);
            let av = s.iter().position(|x| x.avionics == Some(true));
            match (idle, av) {
                (Some(i), Some(a)) => (Some(s[i.max(a)].t - t0), Some(i.max(a))),
                _ => (None, None),
            }
        }
        // The INS knob's step (a lesson that asks for the `ins` item); without one (the F-35I) the self test's end,
        // the avionics up.
        "ins_aligned" => {
            let at = if r.checklist.iter().any(|i| i == "ins") {
                let ins = |e: &&Value| e["event"] == "checklist" && e["step"] == "ins" && e["fault"].is_null();
                f.events.iter().find(ins).and_then(|e| e["t"].as_f64())
            } else {
                s.iter().find(|x| x.avionics == Some(true)).map(|x| x.t)
            };
            whole(Some(if at.is_some_and(|t| moved.is_none_or(|m| t <= m)) { 1.0 } else { 0.0 }))
        }
        // The night lesson's lighting items (data/checklists' lesson-only items) the lesson asks for, all ticked.
        "night_lighting" => {
            let asked: Vec<&String> = r.checklist.iter().filter(|i| NIGHT_ITEMS.contains(&i.as_str())).collect();
            whole((!asked.is_empty()).then(|| if asked.iter().all(|i| ticked(i)) { 1.0 } else { 0.0 }))
        }
        // ponytail: every sample on the ground counts; a lesson with a take-off roll needs the roll left out.
        // Placed at the fastest sample.
        "taxi_speed" => {
            let k = (0..s.len()).filter(|k| s[*k].on_ground).max_by(|a, b| s[*a].speed_kt.total_cmp(&s[*b].speed_kt));
            (k.map(|k| s[k].speed_kt), k)
        }
        _ => (None, None),
    }
}

/// A weapons range: the recorder's `kill` events by the player, air (`"air": true`) and ground, against `need` [air,
/// ground]; the time the last kill it needs came, against the budget.
fn range(f: &Flight, mission: String, need: [usize; 2], budget: f64) -> Debrief {
    let t0 = f.samples[0].t;
    let kills: Vec<(bool, f64)> = f
        .events
        .iter()
        // A unit a friendly finished after the player hit it (`assist`) is a shared kill in the combat logbook, not the
        // player's kill on the range.
        .filter(|e| e["event"] == "kill" && e["assist"] != true)
        .map(|e| (e["air"].as_bool().unwrap_or(false), e["t"].as_f64().unwrap_or(0.0) - t0))
        .collect();
    let got = |air: bool| kills.iter().filter(|k| k.0 == air).count();
    // When the kills it needs were made: the need-th kill of each kind.
    let done_at = |air: bool, n: usize| {
        if n == 0 { Some(0.0) } else { kills.iter().filter(|k| k.0 == air).nth(n - 1).map(|k| k.1) }
    };
    let done = done_at(true, need[0]).zip(done_at(false, need[1])).map(|(a, g)| a.max(g));
    let mut reasons = vec![];
    if !f.samples.iter().any(|s| !s.on_ground) {
        reasons.push("no_liftoff");
    }
    let kill_check = |id, air: bool, n: usize, short| {
        let mark = if got(air) >= n { Mark::Ok } else { Mark::Fail };
        (n > 0).then(|| {
            (
                Check {
                    id,
                    args: vec![n.to_string()],
                    target: Figure::value(n as f64, ""),
                    bound: Bound::Exact,
                    flown: Figure::value(got(air) as f64, ""),
                    mark,
                },
                (mark == Mark::Fail).then_some(short),
            )
        })
    };
    let mut checks = vec![];
    for (c, short) in [
        kill_check("goal_air_kills", true, need[0], "short_air_kills"),
        kill_check("goal_ground_kills", false, need[1], "short_ground_kills"),
    ]
    .into_iter()
    .flatten()
    {
        checks.push(c);
        reasons.extend(short);
    }
    if done.is_some_and(|d| d > budget) {
        reasons.push("over_time");
    }
    checks.push(Check {
        id: "goal_range_time",
        args: vec![format!("{}", (budget / 60.0).round())],
        target: Figure::value(budget, "s"),
        bound: Bound::Max,
        flown: Figure { value: done, ..Figure::none("s") },
        mark: if done.is_some_and(|d| d <= budget) { Mark::Ok } else { Mark::Fail },
    });
    Debrief {
        mission,
        kind: "range",
        pass: reasons.is_empty(),
        reasons,
        items: vec![
            item("air_kills", Some(got(true) as f64), ""),
            item("ground_kills", Some(got(false) as f64), ""),
            item("tower_calls", Some(f.events.iter().filter(|e| e["event"] == "radio").count() as f64), ""),
        ],
        goals: vec![],
        checks,
        combat: json!({}),
        faults: vec![],
        lesson: None,
        graded: vec![],
    }
}

/// A take-off mission's runway, base and figures.
struct Takeoff<'a> {
    rw: &'a Runway,
    base: &'a Base,
    tolerance: f64,
    empty_kg: f64,
    takeoff_kt: &'a [[f64; 2]],
    /// The phases that need the tower's clearance (the rules' `clearances`).
    clearances: &'a [&'static str],
}

/// The runway end the roll from `a` toward `b` ran on ("25R"), or None off every runway of the base.
fn runway_used(base: &Base, a: [f64; 2], b: [f64; 2]) -> Option<String> {
    let heading = (b[0] - a[0]).atan2(b[1] - a[1]).to_degrees();
    let r = base.runways.iter().find(|r| r.dist(a) <= r.width / 2.0)?;
    let k = usize::from(angle(r.heading(0), heading).abs() > 90.0);
    Some(r.designators[k].clone())
}

/// The lift-off: the first sample off the ground after one on it that starts LIFTOFF_HOLD_S airborne (or stays
/// airborne to the recording's end), so a one-sample glitch on the ground is not one.
fn liftoff(s: &[Sample]) -> Option<usize> {
    let held = |i: usize| {
        let run = s[i..].iter().take_while(|x| !x.on_ground).count();
        i + run == s.len() || s[i + run - 1].t - s[i].t >= LIFTOFF_HOLD_S
    };
    (1..s.len()).find(|&i| s[i - 1].on_ground && !s[i].on_ground && held(i))
}

/// The take-off roll's first sample before the lift-off `lift`, and its last sample below ROLL_START_KT: the slowest
/// sample on the runway (the latest of equals) between the jet's entry onto the runway and that last slow sample (the
/// stop on the lineup point, or the entry of a rolling take-off). A jet below ROLL_START_KT off the runway starts its
/// roll there.
fn roll_start(s: &[Sample], lift: usize, rw: &Runway) -> (usize, usize) {
    let k = s[..lift].iter().rposition(|x| x.speed_kt < ROLL_START_KT).unwrap_or(0);
    let mut entry = k;
    while entry > 0 && rw.on(s[k].x, s[k].y) && rw.on(s[entry - 1].x, s[entry - 1].y) {
        entry -= 1;
    }
    ((entry..=k).rev().min_by(|&a, &b| s[a].speed_kt.total_cmp(&s[b].speed_kt)).unwrap_or(k), k)
}

/// The rotation: the first sample of the roll `roll..=lift` with the pitch ROTATION_PITCH_DEG above the roll's start.
fn rotation(s: &[Sample], roll: usize, lift: usize) -> Option<usize> {
    (roll..=lift).find(|&i| s[i].pitch >= s[roll].pitch + ROTATION_PITCH_DEG)
}

/// The tower calls a mission's `clearances` need: one each for the start-up and the taxi, two for the take-off (the
/// line-up and the take-off).
fn calls_needed(clearances: &[&str]) -> usize {
    clearances.iter().map(|c| if *c == "takeoff" { 2 } else { 1 }).sum()
}

/// `ended`: a hard fail (`hard_fail`) ended the mission, so the climb-out is not judged.
fn takeoff(f: &Flight, mission: String, t: &Takeoff, budget: f64, ended: bool) -> Debrief {
    let (rw, tolerance) = (t.rw, t.tolerance);
    let s = &f.samples;
    let t0 = s[0].t;
    let radio = f.events.iter().filter(|e| e["event"] == "radio").count();
    let tower = item("tower_calls", Some(radio as f64), "");
    let needed = calls_needed(t.clearances);
    let calls = (needed > 0).then(|| Check {
        id: "goal_calls",
        args: vec![],
        target: Figure::value(needed as f64, ""),
        bound: Bound::Exact,
        flown: Figure::value(radio as f64, ""),
        mark: if radio >= needed { Mark::Ok } else { Mark::Warn },
    });
    let mut reasons = vec![];
    // The goals with nothing flown: the jet never left the ground.
    let runway_check = |used: Option<String>| Check {
        id: "goal_runway",
        args: vec![rw.designator.clone()],
        mark: if used.as_deref() == Some(rw.designator.as_str()) { Mark::Ok } else { Mark::Fail },
        target: Figure::text(&rw.designator),
        bound: Bound::Exact,
        flown: Figure { text: used, ..Figure::none("") },
    };
    let time_check = |flown: Option<f64>| Check {
        id: "goal_time",
        args: vec![format!("{}", (budget / 60.0).round())],
        target: Figure::value(budget, "s"),
        bound: Bound::Max,
        mark: if flown.is_some_and(|v| v <= budget) { Mark::Ok } else { Mark::Fail },
        flown: Figure { value: flown, ..Figure::none("s") },
    };
    let heading_check = |flown: Option<f64>, ok: bool| Check {
        id: "goal_heading",
        args: vec![format!("{}", tolerance.round())],
        target: Figure::value(rw.heading.round(), "deg"),
        bound: Bound::Tol(tolerance),
        mark: if ok { Mark::Ok } else { Mark::Fail },
        flown: Figure { value: flown.map(|h| h.rem_euclid(360.0).round()), ..Figure::none("deg") },
    };
    let Some(lift) = liftoff(s) else {
        reasons.push("no_liftoff");
        let mut checks = vec![runway_check(None), time_check(None), heading_check(None, false)];
        checks.extend(calls);
        return Debrief {
            mission,
            kind: "takeoff",
            pass: false,
            reasons,
            items: vec![tower],
            goals: vec![],
            checks,
            combat: json!({}),
            faults: vec![],
            lesson: None,
            graded: vec![],
        };
    };
    let (roll, k) = roll_start(s, lift, rw);
    // The lineup heading: at the stop, or (a rolling take-off) where the roll passes ROLL_START_KT.
    let lineup = if s[roll].speed_kt < 1.0 { roll } else { k };
    let rolls = &s[roll..lift];
    let (s_roll, _) = rw.local(s[roll].x, s[roll].y);
    let (s_lift, _) = rw.local(s[lift].x, s[lift].y);
    let moved = s.iter().position(|x| x.speed_kt > 1.0).unwrap_or(roll).min(roll);
    let mut faults = vec![];
    if !rw.on(s[roll].x, s[roll].y) || s_lift <= s_roll {
        reasons.push("wrong_runway");
        faults.push(fault(s, roll, "wrong_runway"));
    } else if let Some(off) = rolls.iter().position(|x| !rw.on(x.x, x.y)) {
        reasons.push("excursion");
        faults.push(fault(s, roll + off, "excursion"));
    }
    let rot = rotation(s, roll, lift).map(|i| s[i].speed_kt);
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
    let reference = interpolate(t.takeoff_kt, gross);
    let used = runway_used(t.base, [s[roll].x, s[roll].y], [s[lift].x, s[lift].y]);
    let max = |g: &dyn Fn(&Sample) -> f64| rolls.iter().map(g).fold(0.0, f64::max);
    let offset = max(&|x| rw.local(x.x, x.y).1.abs());
    let mut checks = vec![
        runway_check(used.clone()),
        time_check(climb.map(|x| x.t - t0)),
        heading_check(climb.or(gear_up).map(|x| x.heading), climb.is_some()),
        Check {
            id: "goal_centreline",
            args: vec![],
            target: Figure::value(rw.width_m / 2.0, "m"),
            bound: Bound::Max,
            flown: Figure::value(offset, "m"),
            mark: if reasons.contains(&"excursion") { Mark::Fail } else { Mark::Ok },
        },
        Check {
            id: "goal_liftoff",
            args: vec![],
            target: Figure::value(reference.round(), "kt"),
            bound: Bound::Exact,
            flown: Figure::value(s[lift].speed_kt.round(), "kt"),
            mark: if (s[lift].speed_kt - reference).abs() > LIFTOFF_WARN_KT { Mark::Warn } else { Mark::Ok },
        },
    ];
    if reasons.contains(&"wrong_runway") {
        checks[0].mark = Mark::Fail;
    }
    checks.extend(calls);
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
        item("reference_speed", Some(reference), "kt"),
        item("gear_up_height", gear_up.and_then(|x| x.agl_m), "m"),
        item("gear_up_time", gear_up.map(|x| x.t - s[lift].t), "s"),
        item("roll_heading_deviation", Some(max(&|x| angle(x.heading, rw.heading).abs())), "deg"),
        item("max_centreline_offset", Some(offset), "m"),
        tower,
    ];
    Debrief {
        mission,
        kind: "takeoff",
        pass: reasons.is_empty(),
        reasons,
        items,
        goals: vec![],
        checks,
        combat: json!({}),
        faults,
        lesson: None,
        graded: vec![],
    }
}

/// How often the game scores a training run that waits to pass or to end, s (modern-iaf/docs/training.md §4).
pub const SCORE_EVERY: f64 = 3.0;
/// A run whose score fails this many times in a row ends, failed: "no_score" in the debrief.
pub const SCORE_TRIES: u32 = 3;
/// A ready run is scored once the recorder has written a sample of it (10 a second), s.
pub const RECORDED_S: f64 = 0.25;

/// Where the game's training run is (sim_flight.gd; the statemachines audit #9).
#[derive(Clone, Debug, Default, PartialEq)]
pub enum Phase {
    /// Flying, its end not reached (not ready to be scored).
    #[default]
    Flying,
    /// Ready to be scored since `at` (the recording's s): a start-up done, a take-off airborne, or past its budget.
    Ready { at: f64 },
    /// The live check's fail `why` (`Watch::check`): the run is scored at once, retried every SCORE_EVERY s.
    Failing { why: String },
    /// Scored, passed: the flight goes on.
    Passed,
    /// Scored, failed: the debrief at `end_at` (sim s, so a pause or the time compression holds it; INFINITY once
    /// opened or none set).
    Failed { end_at: f64 },
}

/// The game's training run: its phase, when it is scored next and its failed scores in a row.
#[derive(Clone, Debug, Default)]
pub struct Run {
    pub phase: Phase,
    next_score: f64,
    fails: u32,
}

impl Run {
    /// Scored (passed or failed): nothing more is checked.
    pub fn finished(&self) -> bool {
        matches!(self.phase, Phase::Passed | Phase::Failed { .. })
    }

    /// The live check's fail reason, "" while none.
    pub fn why(&self) -> &str {
        match &self.phase {
            Phase::Failing { why } => why.as_str(),
            _ => "",
        }
    }

    /// The live check found `why` ("" none): a run not yet failing or scored ends now.
    pub fn fail(&mut self, why: &str) {
        if !why.is_empty() && matches!(self.phase, Phase::Flying | Phase::Ready { .. }) {
            self.phase = Phase::Failing { why: why.into() };
        }
    }

    /// A flying run's frame at `t` (the recording's s), `ready` its end reached: true when it is scored now (due,
    /// ready for RECORDED_S); the next score is SCORE_EVERY later.
    pub fn tick(&mut self, t: f64, ready: bool) -> bool {
        if t < self.next_score || !matches!(self.phase, Phase::Flying | Phase::Ready { .. }) {
            return false;
        }
        if !ready {
            self.phase = Phase::Flying;
            return false;
        }
        let at = match self.phase {
            Phase::Ready { at } => at.min(t),
            _ => t,
        };
        self.phase = Phase::Ready { at };
        if t - at < RECORDED_S {
            return false;
        }
        self.next_score = t + SCORE_EVERY;
        true
    }

    /// An ending run's score is due at `t` (`now`: whenever, the player ending the flight): true when it is scored
    /// now; the next try SCORE_EVERY later.
    pub fn due(&mut self, t: f64, now: bool) -> bool {
        if !now && t < self.next_score {
            return false;
        }
        self.next_score = t + SCORE_EVERY;
        true
    }

    /// A score came out: the failures in a row start again.
    pub fn scored(&mut self) {
        self.fails = 0;
    }

    /// A score failed: true when it is the SCORE_TRIES'th in a row of a run not yet scored (it ends, failed with
    /// "no_score").
    pub fn score_failed(&mut self) -> bool {
        self.fails += 1;
        self.fails >= SCORE_TRIES && !self.finished()
    }

    /// The failed scores in a row.
    pub fn fails(&self) -> u32 {
        self.fails
    }

    /// Scored: passed, or failed with the debrief at `end_at` (sim s).
    pub fn finish(&mut self, pass: bool, end_at: f64) {
        self.phase = if pass { Phase::Passed } else { Phase::Failed { end_at } };
    }

    /// When a failed run opens the debrief (sim s), INFINITY none.
    pub fn end_at(&self) -> f64 {
        match self.phase {
            Phase::Failed { end_at } => end_at,
            _ => f64::INFINITY,
        }
    }

    /// The debrief opened: no second end.
    pub fn ended(&mut self) {
        if let Phase::Failed { end_at } = &mut self.phase {
            *end_at = f64::INFINITY;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    const KT: f64 = 1852.0 / 3600.0; // m/s per knot
    const COLUMNS: [&str; 10] =
        ["t", "x", "z", "agl_m", "speed_kt", "heading", "pitch", "on_ground", "engine", "throttle"];

    fn data() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data")
    }

    fn mission(id: &str) -> Value {
        serde_json::from_str(&std::fs::read_to_string(data().join(format!("missions/{id}.json"))).unwrap()).unwrap()
    }

    fn airbases() -> Vec<Value> {
        sim_bases::files(&data().join("airbases")).unwrap()
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

    /// Every lesson's `checklist` names items of its jet's checklist card (training.md §12), once each, in the card's
    /// order, and holds the flight model's six start-up steps.
    #[test]
    fn lessons_name_their_jets_card_items() {
        let cards = crate::sim::read_dir(&data().join("checklists")).unwrap();
        for m in crate::sim::read_dir(&data().join("missions")).unwrap() {
            let Some(r) = rules(&m.v).unwrap() else { continue };
            if r.checklist.is_empty() {
                continue;
            }
            let unit = m.v["start"]["unit"].as_str().unwrap();
            let card = cards.iter().find(|c| c.v["jets"].as_array().unwrap().iter().any(|j| j == unit)).unwrap();
            let ids: Vec<&str> = card.v["sections"]
                .as_array()
                .unwrap()
                .iter()
                .flat_map(|s| s["items"].as_array().unwrap())
                .map(|it| it["id"].as_str().unwrap())
                .collect();
            let at: Vec<usize> = r.checklist.iter().map(|c| ids.iter().position(|i| i == c).unwrap()).collect();
            assert!(at.windows(2).all(|w| w[0] < w[1]), "{unit}: {:?} in the card's order", r.checklist);
            // A start-up mission asks for the whole start; a course lesson for what it teaches.
            if r.kind == Kind::Startup {
                let need = if unit == "f35i" { 4 } else { 6 };
                assert_eq!(STEPS.iter().filter(|s| r.checklist.iter().any(|c| c == *s)).count(), need, "{unit}");
            }
        }
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

    /// The range (`ramon_range`): the take-off, then the recorder's kill events; passes once its kills are made,
    /// within the budget, and names the kills still missing.
    #[test]
    fn a_range_passes_on_its_kills() {
        let (text, _) = takeoff(CLEAN);
        let m = mission("ramon_range");
        let Some(Rules { kind: Kind::Range { air_kills, ground_kills }, .. }) = rules(&m).unwrap() else {
            panic!("ramon_range is no range")
        };
        let kill = |air: bool, t: f64| format!("{}\n", json!({"event": "kill", "air": air, "t": t}));
        let all: String = (0..air_kills).map(|i| kill(true, 200.0 + i as f64)).collect::<String>()
            + &(0..ground_kills).map(|i| kill(false, 300.0 + i as f64)).collect::<String>();
        let d = scored(&(text.clone() + &all), "ramon_range");
        assert!(d.pass, "{:?}", d.reasons);
        assert_eq!(value(&d, "air_kills"), air_kills as f64);
        assert_eq!(value(&d, "ground_kills"), ground_kills as f64);
        assert!(d.checks.iter().all(|c| c.mark == Mark::Ok));
        // One drone short and no ground kill: both named, the drones' tip first.
        let d = scored(&(text + &kill(true, 200.0).repeat(air_kills - 1)), "ramon_range");
        assert!(!d.pass);
        assert_eq!(d.reasons, ["short_air_kills", "short_ground_kills"]);
        assert_eq!(d.next().unwrap().0, "next_air_kills");
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
        let mut w = Watch::open(&data.join("missions/ramon_takeoff.json"), &data.join("airbases")).unwrap();
        w.rules.clearances.clear(); // the pavement alone (the clearances: a_phase_without_clearance_fails)
        let rw = runway(airbase_of(&mission("ramon_takeoff"), &airbases()).unwrap(), "25R").unwrap();
        let at =
            |s: f64, d: f64| [rw.from[0] + s * rw.dir[0] + d * rw.dir[1], rw.from[1] + s * rw.dir[1] - d * rw.dir[0]];
        let [x, y] = at(rw.start_m + 100.0, 0.0);
        assert_eq!(
            w.check(&Now {
                on_ground: true,
                x,
                y,
                crashed: false,
                damage: 0.0,
                ejected: false,
                fault: None,
                ..Default::default()
            }),
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
                fault: None,
                ..Default::default()
            }),
            None
        );
        let [x, y] = at(1000.0, 200.0);
        assert_eq!(
            w.check(&Now {
                on_ground: true,
                x,
                y,
                crashed: false,
                damage: 0.0,
                ejected: false,
                fault: None,
                ..Default::default()
            }),
            Some("off_pavement")
        );
        assert_eq!(
            w.check(&Now {
                on_ground: false,
                x,
                y,
                crashed: false,
                damage: 0.0,
                ejected: false,
                fault: None,
                ..Default::default()
            }),
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
                fault: None,
                ..Default::default()
            }),
            Some("damage")
        );
        assert_eq!(
            w.check(&Now {
                on_ground: true,
                x,
                y,
                crashed: true,
                damage: 0.0,
                ejected: false,
                fault: None,
                ..Default::default()
            }),
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
        // The fault's place: the first sample of the roll off the runway, on the track's frame.
        let f = &d.faults[0];
        assert_eq!(f.id, "excursion");
        let off = d.checks.iter().find(|c| c.id == "goal_centreline").unwrap();
        assert_eq!(off.grade(), Grade::Unsatisfactory);
        assert_eq!(d.grade(), LessonGrade::Unsatisfactory);
        let j = d.to_json();
        assert_eq!(j["faults"][0]["id"], "excursion");
        assert!(j["faults"][0]["t"].as_f64().unwrap() > 70.0 && j["faults"][0]["at"].as_array().unwrap().len() == 2);
    }

    #[test]
    fn the_faults_are_placed_on_the_track_once_each() {
        let text = with(
            &takeoff(CLEAN).0,
            &[
                json!({"t": 40.0, "event": "hit"}),
                json!({"t": 45.0, "event": "hit"}),
                json!({"t": 75.0, "event": "crash"}),
            ],
        );
        let d = scored(&text, "ramon_takeoff");
        assert_eq!(d.faults.iter().map(|f| f.id).collect::<Vec<_>>(), ["damage", "crash"]);
        let f = parse_flight(&text).unwrap();
        let at = f.samples.iter().find(|x| x.t >= 40.0).unwrap();
        assert_eq!((d.faults[0].t, d.faults[0].at), (at.t - f.samples[0].t, [at.x, at.y]));
        assert_eq!(d.grade(), LessonGrade::Unsatisfactory, "a crash fails the lesson");
        assert_eq!(d.to_json()["strings"]["he"]["damage"], fill("damage", 1, &[]));
    }

    #[test]
    fn a_phase_without_clearance_fails() {
        let data = data();
        let open = || Watch::open(&data.join("missions/ramon_takeoff.json"), &data.join("airbases")).unwrap();
        let w = open();
        assert_eq!(w.rules.clearances, ["startup", "taxi", "takeoff"]);
        let rw = runway(airbase_of(&mission("ramon_takeoff"), &airbases()).unwrap(), "25R").unwrap();
        let spot = w.base.parking.iter().find(|p| p.unit == "f16i").unwrap().at;
        let lineup = [rw.from[0] + (rw.start_m + 100.0) * rw.dir[0], rw.from[1] + (rw.start_m + 100.0) * rw.dir[1]];
        let answers = |a: &[&str]| a.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        let cleared = |a: &[&str]| Cleared::of(&answers(a), false);
        let h = rw.heading;
        let at = |p: [f64; 2], c: Cleared| Now {
            on_ground: true,
            x: p[0],
            y: p[1],
            heading: h,
            cleared: c,
            ..Default::default()
        };
        let start = cleared(&["ACFT_CLEAR_TO_START"]);
        let taxi = cleared(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY"]);
        let lined = cleared(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY", "ACFT_CLEAR_TO_LINEUP_NW"]);
        let all = cleared(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY", "ACFT_CLEAR_TO_TAKEOFF"]);
        // The engine start: the starter turning the engine without start-up clearance; asked and told to hold, too.
        let mut w = open();
        let turning = Now { rpm: 3.0, ..at(spot, Cleared::default()) };
        assert_eq!(w.check(&turning), None, "below 5 % RPM: not started");
        assert_eq!(w.check(&Now { rpm: 6.0, ..turning }), Some("no_start_clearance"));
        let held = cleared(&["ACFT_HOLD_POS"]);
        assert_eq!(open().check(&Now { rpm: 20.0, ..at(spot, held) }), Some("no_start_clearance"));
        assert_eq!(open().check(&Now { rpm: 60.0, ..at(spot, start) }), None);
        // Leaving the spot: 10 m from where the jet first stood; brake creep within it is no taxi.
        let mut w = open();
        let idle = Now { rpm: 60.0, ..at(spot, start) };
        assert_eq!(w.check(&idle), None);
        assert_eq!(w.check(&Now { x: spot[0] + 6.0, y: spot[1] + 6.0, ..idle }), None, "8.5 m: creep");
        assert_eq!(w.check(&Now { x: spot[0] + 11.0, ..idle }), Some("no_taxi_clearance"));
        let mut w = open();
        assert_eq!(w.check(&Now { rpm: 60.0, ..at(spot, taxi) }), None);
        assert_eq!(w.check(&Now { x: spot[0] + 11.0, rpm: 60.0, ..at(spot, taxi) }), None, "taxi cleared");
        // The runway: entering it needs line-up (or take-off) clearance, the roll take-off clearance.
        let mut w = open();
        assert_eq!(w.check(&Now { rpm: 60.0, ..at(spot, taxi) }), None);
        let hold = [lineup[0] - 100.0 * rw.dir[0], lineup[1] - 100.0 * rw.dir[1]];
        assert_eq!(w.check(&Now { rpm: 60.0, ..at(hold, taxi) }), None, "the holding point on the centreline");
        assert_eq!(w.check(&Now { rpm: 60.0, ..at(lineup, taxi) }), Some("no_runway_clearance"));
        let mid = [lineup[0] + 1500.0 * rw.dir[0], lineup[1] + 1500.0 * rw.dir[1]];
        assert_eq!(open().check(&Now { rpm: 60.0, ..at(mid, taxi) }), Some("no_runway_clearance"), "past midfield");
        let mut w = open();
        assert_eq!(w.check(&Now { rpm: 60.0, ..at(spot, lined) }), None);
        assert_eq!(w.check(&Now { rpm: 60.0, speed_kt: 10.0, ..at(lineup, lined) }), None, "lining up");
        assert_eq!(w.check(&Now { rpm: 100.0, speed_kt: 35.0, ..at(lineup, lined) }), Some("no_takeoff_clearance"));
        let mut w = open();
        assert_eq!(w.check(&Now { rpm: 60.0, ..at(spot, all) }), None);
        assert_eq!(w.check(&Now { rpm: 100.0, speed_kt: 120.0, ..at(lineup, all) }), None, "the clean roll");
        // A hot start holds the start, taxi and line-up; a start-up mission needs the start-up and taxi clearances.
        let mut w = open();
        let hot = Cleared::of(&[], true);
        assert_eq!(w.check(&Now { rpm: 60.0, ..at(lineup, hot) }), None);
        assert_eq!(w.check(&Now { rpm: 100.0, speed_kt: 40.0, ..at(lineup, hot) }), Some("no_takeoff_clearance"));
        let s = Watch::open(&data.join("missions/ramon_startup.json"), &data.join("airbases")).unwrap();
        assert_eq!(s.rules.clearances, ["startup", "taxi"]);
        // The recording carries the live check's reason: the CLI's score fails with it first.
        let text = with(&takeoff(CLEAN).0, &[json!({"t": 5.0, "event": "clearance", "reason": "no_taxi_clearance"})]);
        let d = scored(&text, "ramon_takeoff");
        assert_eq!(d.reasons[0], "no_taxi_clearance");
        assert_eq!(d.to_json()["strings"]["he"]["no_taxi_clearance"], "הסעה ללא אישור הסעה מהמגדל.");
    }

    #[test]
    fn a_wrong_runway_warns_lined_up_and_fails_at_the_roll() {
        let data = data();
        let mut w = Watch::open(&data.join("missions/ramon_takeoff.json"), &data.join("airbases")).unwrap();
        assert_eq!(w.runway_designator(), "25R");
        let rw = runway(airbase_of(&mission("ramon_takeoff"), &airbases()).unwrap(), "25R").unwrap();
        let p = [rw.from[0] + (rw.start_m + 100.0) * rw.dir[0], rw.from[1] + (rw.start_m + 100.0) * rw.dir[1]];
        let all = Cleared::of(&[], true);
        let now = |heading: f64, speed_kt: f64| Now {
            on_ground: true,
            x: p[0],
            y: p[1],
            heading,
            speed_kt,
            rpm: 80.0,
            cleared: all,
            ..Default::default()
        };
        assert_eq!(w.wrong_runway(&now(rw.heading, 0.0)), None, "lined up on 25R");
        assert_eq!(w.wrong_runway(&now(rw.heading + 90.0, 0.0)), None, "crossing it");
        let back = rw.heading + 180.0;
        assert_eq!(w.wrong_runway(&now(back, 0.0)), None, "a backtrack toward the 25R end: 07L's far half");
        assert_eq!(w.check(&now(back, 35.0)), Some("wrong_runway"), "but a roll there fails");
        let far = rw.length_m - rw.far_start_m - 100.0;
        let q = [rw.from[0] + far * rw.dir[0], rw.from[1] + far * rw.dir[1]];
        let at07 = |speed_kt: f64| Now { x: q[0], y: q[1], ..now(back, speed_kt) };
        assert_eq!(w.wrong_runway(&at07(0.0)).as_deref(), Some("07L"), "lined up on the far end");
        assert_eq!(w.check(&at07(10.0)), None, "lined up: a warning only");
        assert_eq!(w.check(&at07(35.0)), Some("wrong_runway"), "the roll fails");
        assert_eq!(w.wrong_runway(&Now { on_ground: false, ..at07(150.0) }), None, "airborne");
    }

    /// The mission's wind turns its runway (sim_bases::Base::mission_runway, the tower's rule): a wind from 066° makes
    /// Ramon's 25R take-off a 07L one, so 07L is the assigned end and a line-up on 25R is the wrong one.
    #[test]
    fn the_assigned_runway_turns_into_the_wind() {
        let data = data();
        let mut m = mission("ramon_takeoff");
        (m["wind_kt"], m["wind_from"]) = (json!(15), json!(66));
        let dir = std::env::temp_dir().join(format!("iaf-train-wind-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("ramon_takeoff_wind.json");
        std::fs::write(&path, m.to_string()).unwrap();
        let w = Watch::open(&path, &data.join("airbases")).unwrap();
        std::fs::remove_dir_all(&dir).unwrap();
        assert_eq!(w.runway_designator(), "07L");
        let rw = runway(airbase_of(&m, &airbases()).unwrap(), "25R").unwrap();
        let p = [rw.from[0] + (rw.start_m + 100.0) * rw.dir[0], rw.from[1] + (rw.start_m + 100.0) * rw.dir[1]];
        let now = Now { on_ground: true, x: p[0], y: p[1], heading: rw.heading, rpm: 80.0, ..Default::default() };
        assert_eq!(w.wrong_runway(&now).as_deref(), Some("25R"), "lined up on 25R in a wind from 066°");
    }

    #[test]
    fn the_menu_marks_the_call_that_fits() {
        let answers = |a: &[&str]| a.iter().map(|s| s.to_string()).collect();
        // Nevatim: the parking spot 337 m from the lineup point, the holding point 86 m.
        let mut s = RadioNow { on_ground: true, lineup_m: 337.0, hold_m: 86.0, ..Default::default() };
        assert_eq!(next_call(&s), Some("startup"));
        s.answers = answers(&["ACFT_CLEAR_TO_START"]);
        s.engine_on = true;
        assert!(next_call(&s).is_none(), "idle without the avionics: nothing");
        s.avionics = true;
        assert_eq!(next_call(&s), Some("taxi"));
        s.answers = answers(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY"]);
        assert!(next_call(&s).is_none(), "taxiing, short of the holding point: nothing");
        s.lineup_m = 158.0;
        assert!(next_call(&s).is_none(), "the taxi's last turns, short of the holding point: nothing");
        s.lineup_m = 90.0;
        assert_eq!(next_call(&s), Some("lineup"), "at the holding point: line-up");
        s.answers.push("ACFT_HOLD_POS".into());
        assert_eq!(next_call(&s), Some("lineup"), "told to hold: line-up again");
        s.answers.push("ACFT_CLEAR_TO_LINEUP_NW".into());
        assert_eq!(next_call(&s), Some("takeoff"), "line-up approved: take-off");
        s.lineup_m = 0.0;
        assert_eq!(next_call(&s), Some("takeoff"), "lined up: still take-off");
        s.answers = vec![];
        assert_eq!(next_call(&s), Some("taxi"), "started without start-up approval: taxi still offered");
        s.answers = answers(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY"]);
        assert_eq!(next_call(&s), Some("lineup"), "lined up without line-up approval: line-up");
        s.answers = answers(&["ACFT_CLEAR_TO_START"]);
        assert_eq!(next_call(&s), Some("taxi"), "at the holding point without taxi approved: no take-off");
        s.answers = answers(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY", "ACFT_CLEAR_TO_TAKEOFF"]);
        assert!(next_call(&s).is_none());
        s.on_ground = false;
        assert_eq!(next_call(&s), Some("landing"));
        // A hot ground start at the lineup point: take-off at once.
        let hot = RadioNow { on_ground: true, engine_on: true, avionics: true, hot: true, ..Default::default() };
        assert_eq!(next_call(&hot), Some("takeoff"));
        // The menu itself: every ground call on the ground, landing in the air.
        assert_eq!(radio_calls(&hot), ["startup", "taxi", "lineup", "takeoff", "radio_check"]);
        assert_eq!(radio_calls(&RadioNow::default()), ["landing"]);
        // A call out of order: the one it needs first.
        let a = |l: &[&str]| l.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        assert_eq!(missing_before("takeoff", &[], false), Some("startup"));
        assert_eq!(
            missing_before("takeoff", &a(&["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY"]), false),
            Some("lineup")
        );
        assert_eq!(missing_before("taxi", &a(&["ACFT_CLEAR_TO_START"]), false), None);
        assert_eq!(missing_before("startup", &[], false), None);
        assert_eq!(missing_before("takeoff", &[], true), None, "a hot start");
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
        let card = rules(&mission("ramon_startup")).unwrap().unwrap().checklist;
        assert!(STEPS.iter().all(|s| card.iter().any(|c| c == s)), "the lesson asks for the start's steps");
        let steps: Vec<Value> = card.iter().map(|s| json!({"t": 20.0, "event": "checklist", "item": s})).collect();
        let bare = jsonl(&samples);
        let text = with(&bare, &steps);
        keep("startup.jsonl", &text);
        // The checklist not flown: each step skipped.
        let skipped = scored(&bare, "ramon_startup");
        assert!(skipped.reasons.contains(&"skip_main_power"));
        assert_eq!(skipped.reasons.len(), card.len());
        // A hot start fails it first.
        let hot = json!({"t": 21.0, "event": "checklist", "step": "engine", "fault": "hot_start"});
        assert_eq!(scored(&with(&text, &[hot]), "ramon_startup").reasons, ["hot_start"]);
        // The throttle to OFF with the engine running (the shutdown, start.rs `cut_off`) fails it too.
        let off = json!({"t": 30.0, "event": "checklist", "step": "cutoff", "fault": "shutdown"});
        assert_eq!(scored(&with(&text, &[off]), "ramon_startup").reasons, ["shutdown"]);
        // A switch put back off fails its step; on again, it is done (the switches audit's M2).
        let off = json!({"t": 25.0, "event": "checklist", "item": "avionics", "on": false});
        assert_eq!(scored(&with(&text, std::slice::from_ref(&off)), "ramon_startup").reasons, ["skip_avionics"]);
        let again = json!({"t": 26.0, "event": "checklist", "item": "avionics"});
        assert!(scored(&with(&text, &[off, again]), "ramon_startup").pass);
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

    /// The debrief's sample flight (modern-iaf/tests/data/sample_flight.py writes it): a whole take-off at Ramon as
    /// the game records it, lifting off 13 kt above the reference speed, with a 1.8 g turn in the climb.
    fn sample_takeoff() -> String {
        std::fs::read_to_string(data().join("../tests/data/ramon_takeoff_flight.jsonl")).unwrap()
    }

    #[test]
    fn the_sample_flight_scores_with_its_goals_and_next_time() {
        let d = scored(&sample_takeoff(), "ramon_takeoff");
        assert!(d.pass, "{:?}", d.reasons);
        let ids: Vec<_> = d.checks.iter().map(|c| (c.id, c.mark)).collect();
        assert_eq!(
            ids,
            [
                ("goal_runway", Mark::Ok),
                ("goal_time", Mark::Ok),
                ("goal_heading", Mark::Ok),
                ("goal_centreline", Mark::Ok),
                ("goal_liftoff", Mark::Warn),
                ("goal_calls", Mark::Ok),
            ]
        );
        let j = d.to_json();
        // Each goal graded against its standard: what should have been flown, what was, the gap and the grade.
        let grades: Vec<&str> = j["checks"].as_array().unwrap().iter().map(|c| c["grade"].as_str().unwrap()).collect();
        assert_eq!(grades[4], "below", "the lift-off off the mark");
        assert!(grades.iter().enumerate().all(|(i, g)| i == 4 || ["average", "above"].contains(g)), "{grades:?}");
        let lift = &j["checks"][4];
        let gap = lift["flown"]["value"].as_f64().unwrap() - lift["target"]["value"].as_f64().unwrap();
        assert_eq!(lift["gap"].as_f64(), Some(gap));
        assert!(j["checks"][0]["gap"].is_null(), "a runway's name has no gap");
        assert_eq!(j["grade"], "marginal");
        assert!(j["lesson"].is_null(), "the existing missions are no course lesson");
        assert_eq!(j["strings"]["he"]["lesson_marginal"], "גבולי");
        assert_eq!(j["strings"]["en"]["grade_below"], "Below average");
        assert_eq!(j["checks"][0]["label"]["en"], "Take off from runway 25R");
        assert_eq!(j["checks"][2]["target"]["tol"], 10.0);
        assert_eq!(j["checks"][3]["target"]["max"], true);
        assert_eq!(j["checks"][5]["target"]["value"], 4.0);
        let next = j["next"]["en"].as_str().unwrap();
        assert!(next.starts_with("Lift-off was ") && next.contains("above the reference speed"), "{next}");
        assert!(j["next"]["he"].as_str().unwrap().contains("מעל המהירות המומלצת"));
    }

    #[test]
    fn the_track_has_the_phases_and_the_marks() {
        let f = parse_flight(&sample_takeoff()).unwrap();
        let m = mission("ramon_takeoff");
        let rw = runway(airbase_of(&m, &airbases()).unwrap(), "25R").unwrap();
        let tr = track(&f, Some(&rw));
        let order: Vec<&str> = tr.runs.iter().map(|r| PHASES[r.0]).collect();
        assert_eq!(order, ["startup", "taxi", "hold", "taxi", "hold", "roll", "airborne"]);
        assert_eq!(tr.runs[0].1, 0.0);
        let marks: Vec<&str> = tr.marks.iter().map(|m| m.id).collect();
        assert_eq!(marks, ["rotation", "liftoff", "gear_up", "peak_g"]);
        assert!((tr.marks[3].value - 1.8).abs() < 0.01, "{:?}", tr.marks[3]);
        let l = tr.lift.unwrap();
        assert!(!tr.samples[l].on_ground && tr.samples[l - 1].on_ground);
        let j = tr.to_json();
        assert_eq!(j["at"].as_array().unwrap().len(), 2 * j["t"].as_array().unwrap().len());
        assert_eq!(j["strings"]["he"]["ph_roll"], "ריצה");
        assert_eq!(j["pins"][1]["id"], "liftoff");
        // Without the runway, the roll starts at the last moment below the roll's speed.
        let bare = track(&f, None);
        assert_eq!(bare.runs.iter().map(|r| PHASES[r.0]).next_back(), Some("airborne"));
    }

    #[test]
    fn next_time_names_the_step_never_reached() {
        let d = |reason: &'static str| Debrief {
            mission: "m".into(),
            kind: "takeoff",
            pass: false,
            reasons: vec![reason],
            items: vec![],
            goals: vec![],
            checks: vec![],
            combat: json!({}),
            faults: vec![],
            lesson: None,
            graded: vec![],
        };
        assert_eq!(d("no_liftoff").next().map(|n| n.0), Some("next_liftoff"));
        assert_eq!(d("no_start").next().map(|n| n.0), Some("next_start"));
        assert_eq!(d("no_taxi_clearance").next().map(|n| n.0), Some("next_clearance"));
    }

    /// A lesson's item below average carries the course's tip as its comment and its place; one flown well has none.
    #[test]
    fn a_graded_item_below_average_has_its_comment_and_place() {
        let c = course::course();
        let g = |id: &str, flown: f64, at: Option<[f64; 2]>| {
            let i = c.item(id).unwrap();
            Graded {
                id: id.into(),
                label: i.label.clone(),
                standard: i.standard.clone(),
                flown: Some(flown),
                at,
                tip: i.tip.clone(),
            }
        };
        let d = Debrief {
            mission: "m".into(),
            kind: "lesson",
            pass: true,
            reasons: vec![],
            items: vec![],
            goals: vec![],
            checks: vec![],
            combat: json!({}),
            faults: vec![],
            lesson: Some("ground.taxi".into()),
            graded: vec![g("taxi_speed", 28.0, Some([10.04, 20.0])), g("checklist_items", 100.0, None)],
        };
        let j = d.to_json();
        assert_eq!(j["grade"], "marginal");
        assert_eq!(j["graded"][0]["grade"], "below");
        assert_eq!(j["graded"][0]["comment"], c.item("taxi_speed").unwrap().tip.clone().unwrap());
        assert_eq!(j["graded"][0]["at"], json!([10.0, 20.0]));
        assert!(j["graded"][1]["comment"].is_null() && j["graded"][1]["at"].is_null());
        assert_eq!(j["strings"]["he"]["grade_below"], "מתחת לממוצע");
    }

    #[test]
    fn a_long_flight_is_thinned_keeping_the_liftoff() {
        let mut f = parse_flight(&sample_takeoff()).unwrap();
        let mut more = f.samples.clone();
        for k in 1..8 {
            let dt = (k as f64) * 10_000.0;
            more.extend(f.samples.iter().filter(|x| !x.on_ground).map(|x| Sample { t: x.t + dt, ..x.clone() }));
        }
        f.samples = more;
        let tr = track(&f, None);
        assert!(tr.samples.len() <= TRACK_POINTS + 2, "{}", tr.samples.len());
        assert!(tr.lift.is_some_and(|l| !tr.samples[l].on_ground));
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

    #[test]
    fn run_is_scored_once_ready_and_recorded() {
        let mut r = Run::default();
        assert!(!r.tick(0.0, false));
        assert_eq!(r.phase, Phase::Flying);
        assert!(!r.tick(1.0, true), "ready: waits for the recorder's sample");
        assert_eq!(r.phase, Phase::Ready { at: 1.0 });
        assert!(!r.tick(1.2, true));
        assert!(r.tick(1.25, true), "scored RECORDED_S after it became ready");
        assert!(!r.tick(4.0, true), "the next score SCORE_EVERY later");
        assert!(!r.tick(4.25, false), "not ready again: back to flying");
        assert_eq!(r.phase, Phase::Flying);
        assert!(!r.tick(5.0, true));
        assert!(r.tick(5.25, true));
        r.scored();
        r.finish(true, f64::INFINITY);
        assert!(r.finished() && r.end_at().is_infinite());
        assert!(!r.tick(100.0, true), "a pass flies on, not scored again");
        r.fail("crash");
        assert_eq!(r.phase, Phase::Passed, "a pass stays");
    }

    #[test]
    fn a_fail_ends_the_run_and_holds_on_sim_time() {
        let mut r = Run::default();
        r.fail("");
        assert_eq!(r.why(), "");
        r.fail("off_pavement");
        assert_eq!(r.why(), "off_pavement");
        r.fail("crash");
        assert_eq!(r.why(), "off_pavement", "the first reason stays");
        assert!(!r.tick(10.0, true), "a failing run is not scored as a flying one");
        assert!(r.due(10.0, false));
        assert!(!r.due(12.0, false));
        assert!(r.due(13.0, false));
        r.finish(false, 20.0);
        assert_eq!(r.end_at(), 20.0);
        r.ended();
        assert!(r.end_at().is_infinite() && r.finished());
        // The player ending the flight scores it whenever.
        let mut r = Run::default();
        assert!(r.due(0.0, true));
        assert!(r.due(0.0, true));
    }

    #[test]
    fn a_run_that_cannot_be_scored_gives_up_after_score_tries() {
        let mut r = Run::default();
        r.fail("off_pavement");
        for i in 1..SCORE_TRIES {
            assert!(!r.score_failed(), "try {i}");
        }
        assert!(r.score_failed(), "the third failure in a row ends it (no_score)");
        assert_eq!(r.fails(), SCORE_TRIES);
        // A score in between starts the count again.
        let mut r = Run::default();
        assert!(!r.score_failed() && !r.score_failed());
        r.scored();
        assert!(!r.score_failed() && !r.score_failed());
        assert!(r.score_failed());
        // A finished run does not end twice.
        r.finish(true, f64::INFINITY);
        assert!(!r.score_failed());
    }
}
