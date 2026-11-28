//! The instructor's calls in flight (modern-iaf/docs/training.md §17, training-plan.md §2.3): each lesson's calls in
//! order, from its content in the phase's lesson file (training.md §16, `course::Lesson::content`). A call fires when
//! the call before it has fired and the flight's state passes its tests (§16.3); a call is any number of lines, and
//! any number of calls may fire on one step. The voices step (`sim_voices`) says each line into its clip, the flight
//! (`IafCalls`) plays them.

use crate::course::{self, Kind};
use crate::sim_bases::{Base, Runway};
use anyhow::{Context, Result, bail};
use serde_json::Value;

/// Engine idle, % RPM (training.md §3.1).
const IDLE_RPM: f64 = 60.0;
/// Stopped, kt (inferred: below brake creep).
pub(crate) const STOPPED_KT: f64 = 3.0;
/// The initial point: on the runway's extended centreline 2 to 6 NM out, within 1.5 km of it, on the runway's heading
/// within 30° (inferred: the overhead pattern's initial lies 3 to 5 NM out).
pub(crate) const INITIAL_M: [f64; 2] = [3_704.0, 11_112.0];
pub(crate) const INITIAL_CROSS_M: f64 = 1_500.0;
/// On a leg's heading (deg; inferred).
pub(crate) const LEG_DEG: f64 = 30.0;
/// Over the runway (the break): within this of its centreline, m (inferred).
const OVER_RUNWAY_M: f64 = 500.0;
/// The downwind leg: this far abeam the runway, m (inferred: about 1 NM, A137's pattern).
const DOWNWIND_M: [f64; 2] = [500.0, 4_000.0];
/// The final: up to 6 km out, within 150 m of the centreline, on its heading within 10°, wings within 10° of level
/// (inferred).
pub(crate) const FINAL_M: f64 = 6_000.0;
pub(crate) const FINAL_CROSS_M: f64 = 150.0;
pub(crate) const FINAL_DEG: f64 = 10.0;
const LEVEL_DEG: f64 = 10.0;
/// The touchdown zone: the first 3,000 ft of the runway, below 300 ft over it (FAA's touchdown zone).
const TDZ_M: f64 = 914.4;
const LOW_FT: f64 = 300.0;
/// Climbing out: above 300 ft and climbing at 300 ft/min or more (inferred).
const CLIMB_FPM: f64 = 300.0;
/// Slowed on the runway: at most this, kt (inferred: taxi speed plus a margin).
const SLOWED_KT: f64 = 40.0;
/// Back at the spot the flight started from, m (inferred: a shelter's pad).
const PARKED_M: f64 = 30.0;
/// At a steerpoint: within 1 NM of it, m (inferred: the HUD's steering turns the jet to the next leg about there).
const STEER_M: f64 = 1_852.0;

/// A test of the flight's state a call waits for (training.md §16.3; its names `course::TESTS`, `course::ARG_TESTS`).
#[derive(Debug, Clone, PartialEq)]
pub enum Test {
    /// Always: the lesson's start.
    Start,
    /// The engine at idle or above.
    Idle,
    /// The INS aligned.
    Aligned,
    /// On the ground, stopped at the runway's holding point.
    HoldPoint,
    /// On the ground, stopped on the runway in use, lined up on it.
    LinedUp,
    /// In the air at the initial point.
    Initial,
    /// In the air over the runway.
    OverRunway,
    /// In the air on the downwind leg.
    Downwind,
    /// In the air abeam the threshold or past it on the downwind side: the final turn's start.
    FinalTurn,
    /// In the air on final, wings level.
    Final,
    /// Low over the touchdown zone (in the air or on the ground).
    TouchdownZone,
    /// In the air past the threshold, climbing.
    ClimbOut,
    /// On the ground on the runway, slowed to taxi speed.
    Slowed,
    /// On the ground, stopped at the spot the flight started from.
    Parked,
    /// The engine stopped.
    EngineOff,
    /// No electrical power: the jet dark.
    PowerOff,
    /// The checklist card's item ticked (training.md §12).
    Item(String),
    /// The tower's clearance given for `startup`, `taxi` or `takeoff` (§3.3).
    Cleared(String),
    /// The pilot made the radio call (§8); a flight command is `<command>:<addressee>`.
    Called(String),
    /// The failure is on (training.md §15): the engine fire while it burns, any other once started.
    Failure(String),
    /// In the air at least this far above the field, ft.
    Alt(f64),
    /// In the air at an angle of attack of at least this, deg.
    Aoa(f64),
    /// In the air at a load factor of at least this, g.
    G(f64),
    /// In the air.
    Airborne,
    /// The player, a wingman, in its slot (§16.8: `iaf_ai::Flight::facts`).
    InSlot,
    /// Every other live jet of the flight in position.
    FlightJoined,
    /// Every live jet of the flight down after its flight.
    FlightLanded,
    /// The AI lead gave the order (`iaf_ai::LEAD_CALLS` without "lead_").
    LeadOrder(String),
    /// The tanker's event for the player's jet came (`course::TANKER_EVENTS`, training.md §16.3).
    Tanker(String),
    /// In the air within STEER_M of the route's steerpoint (1 the first).
    Steerpoint(usize),
}

impl Test {
    fn of(s: &str) -> Result<Test> {
        Ok(match s {
            "start" => Test::Start,
            "idle" => Test::Idle,
            "aligned" => Test::Aligned,
            "hold_point" => Test::HoldPoint,
            "lined_up" => Test::LinedUp,
            "initial" => Test::Initial,
            "over_runway" => Test::OverRunway,
            "downwind" => Test::Downwind,
            "final_turn" => Test::FinalTurn,
            "final" => Test::Final,
            "touchdown_zone" => Test::TouchdownZone,
            "climb_out" => Test::ClimbOut,
            "slowed" => Test::Slowed,
            "parked" => Test::Parked,
            "engine_off" => Test::EngineOff,
            "power_off" => Test::PowerOff,
            "airborne" => Test::Airborne,
            "in_slot" => Test::InSlot,
            "flight_joined" => Test::FlightJoined,
            "flight_landed" => Test::FlightLanded,
            t => match t.split_once(':') {
                Some(("item", a)) if !a.is_empty() => Test::Item(a.into()),
                Some(("cleared", a)) if ["startup", "taxi", "takeoff"].contains(&a) => Test::Cleared(a.into()),
                Some(("called", a)) if !a.is_empty() => Test::Called(a.into()),
                Some(("failure", a)) if !a.is_empty() => Test::Failure(a.into()),
                Some((k @ ("alt" | "aoa" | "g"), a)) if a.parse::<f64>().is_ok() => {
                    let v = a.parse::<f64>().unwrap_or(0.0);
                    match k {
                        "alt" => Test::Alt(v),
                        "aoa" => Test::Aoa(v),
                        _ => Test::G(v),
                    }
                }
                Some(("lead_order", a)) if !a.is_empty() => Test::LeadOrder(a.into()),
                Some(("tanker", a)) if course::TANKER_EVENTS.contains(&a) => Test::Tanker(a.into()),
                Some(("steerpoint", a)) if a.parse::<usize>().is_ok_and(|n| n > 0) => {
                    Test::Steerpoint(a.parse().unwrap_or(1))
                }
                _ => bail!("calls: \"{t}\" is no test"),
            },
        })
    }
}

#[derive(Debug, Clone)]
pub struct Call {
    pub id: String,
    pub when: Vec<Test>,
    /// Its tests must first fail after the call before it fired.
    pub new: bool,
    /// A start-up call: left out once the pilot has passed phase 1.
    pub startup: bool,
    /// The jets it is said in.
    pub jets: Vec<String>,
    /// Its lines, each {en, he}.
    pub lines: Vec<Value>,
}

impl Call {
    /// A call of a lesson file (training.md §16.1, checked by `course`): `jets` none, every jet of the course.
    fn of(v: &Value) -> Result<Call> {
        let strings = |v: &Value| -> Vec<String> {
            v.as_array().into_iter().flatten().filter_map(|s| s.as_str().map(String::from)).collect()
        };
        let id = v["id"].as_str().context("calls: a call without \"id\"")?;
        let when = strings(&v["when"]).iter().map(|t| Test::of(t)).collect::<Result<Vec<_>>>()?;
        let jets =
            if v["jets"].is_array() { strings(&v["jets"]) } else { course::course().jets.keys().cloned().collect() };
        Ok(Call {
            id: id.into(),
            when,
            new: v["new"] == true,
            startup: v["startup"] == true,
            jets,
            lines: v["lines"].as_array().cloned().unwrap_or_default(),
        })
    }
}

impl Call {
    /// Said in jet `jet`: none in a check ride, a start-up call not once the pilot passed phase 1 (`startup_known`).
    fn said_in(&self, jet: &str, check: bool, startup_known: bool) -> bool {
        !check && self.jets.iter().any(|j| j == jet) && !(self.startup && startup_known)
    }
}

/// Every lesson's calls: (lesson key, its calls), the lessons with content.
pub fn all() -> Result<Vec<(String, Vec<Call>)>> {
    let c = course::course();
    let mut out = vec![];
    for (pi, p) in c.phases.iter().enumerate() {
        for (li, l) in p.lessons.iter().enumerate() {
            let calls =
                l.content["calls"].as_array().into_iter().flatten().map(Call::of).collect::<Result<Vec<_>>>()?;
            if !calls.is_empty() {
                out.push((c.key(pi, li), calls));
            }
        }
    }
    Ok(out)
}

/// The runway end `d` ("25R", "07L") as said ("two five right", "seven left"), shown in English ("25 right") and in
/// Hebrew ("25 ימין"): the tower's way (modern-iaf/docs/sound.md §3).
pub fn runway_words(d: &str) -> [String; 3] {
    const DIGITS: [&str; 10] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"];
    let digits: String = d.chars().take_while(char::is_ascii_digit).collect();
    let n = digits.trim_start_matches('0');
    let letter = &d[digits.len()..];
    let side = |en: bool| match letter {
        "L" => {
            if en {
                " left"
            } else {
                " שמאל"
            }
        }
        "R" => {
            if en {
                " right"
            } else {
                " ימין"
            }
        }
        "C" => {
            if en {
                " centre"
            } else {
                " מרכז"
            }
        }
        _ => "",
    };
    let said: Vec<&str> = n.bytes().map(|b| DIGITS[(b - b'0') as usize]).collect();
    [format!("{}{}", said.join(" "), side(true)), format!("{n}{}", side(true)), format!("{n}{}", side(false))]
}

/// The clip of line `n` of call `call` of lesson `key` for runway end `rwy` (a line with {rwy}, else None), through
/// the radio (`radio`: the F-35I's instructor in a second jet) or the intercom.
pub fn file(key: &str, call: &str, n: usize, rwy: Option<&str>, radio: bool) -> String {
    let r = rwy.map_or(String::new(), |r| format!("_{}", r.to_lowercase()));
    format!("ins{}_{}_{call}_{n}{r}.ogg", if radio { "r" } else { "" }, key.replace('.', "_"))
}

/// The instructor of jet `jet` talks on the radio (a second jet, `lead`), not the intercom (`back_seat`).
fn on_radio(jet: &str) -> bool {
    course::course().jets.get(jet).is_some_and(|j| j["instructor"] == "lead")
}

/// One clip the voices step says: its file, the words said, and whether it goes through the radio chain (else the
/// helmet's, the intercom).
pub struct Clip {
    pub file: String,
    pub say: String,
    pub radio: bool,
}

/// Every clip of every lesson's calls: each line in each jet's chain, a line with {rwy} once per runway end of the
/// jet's home base (`bases`: the airbase files).
pub fn clips(bases: &[Base]) -> Result<Vec<Clip>> {
    let c = course::course();
    let mut out: Vec<Clip> = vec![];
    for (key, calls) in all()? {
        for call in &calls {
            for jet in &call.jets {
                let name = c.jets[jet]["base"].as_str().unwrap_or("");
                let base = crate::sim_bases::by_name(bases, name).with_context(|| format!("calls: no base {name}"))?;
                let ends: Vec<&str> =
                    base.runways.iter().flat_map(|r| r.designators.iter().map(|d| d.as_str())).collect();
                for (n, l) in call.lines.iter().enumerate() {
                    let en = l["en"].as_str().unwrap_or("");
                    let rwys: Vec<Option<&str>> =
                        if en.contains("{rwy}") { ends.iter().map(|e| Some(*e)).collect() } else { vec![None] };
                    for r in rwys {
                        let f = file(&key, &call.id, n, r, on_radio(jet));
                        if out.iter().all(|x| x.file != f) {
                            let say = r.map_or(en.to_string(), |r| en.replace("{rwy}", &runway_words(r)[0]));
                            out.push(Clip { file: f, say, radio: on_radio(jet) });
                        }
                    }
                }
            }
        }
    }
    Ok(out)
}

/// One frame of the flight for the calls.
#[derive(Debug, Clone, Default)]
pub struct Now {
    pub on_ground: bool,
    /// The jet's centre in the engine frame, m.
    pub x: f64,
    pub y: f64,
    /// Altitude above sea level, ft.
    pub alt_ft: f64,
    pub speed_kt: f64,
    /// The engine frame's heading and the bank, deg.
    pub heading: f64,
    pub roll: f64,
    pub vs_fpm: f64,
    pub rpm: f64,
    pub ins_aligned: bool,
    pub engine_on: bool,
    /// Electrical power: 0 none, 1 the battery, 2 the displays up (`IafFlight` state's `power`).
    pub power: i64,
    /// The checklist card's items ticked, by id.
    pub items: Vec<String>,
    /// The tower's clearances so far.
    pub cleared: crate::training::Cleared,
    /// The radio calls the pilot made, by id; a flight command `<command>:<addressee>`.
    pub called: Vec<String>,
    /// The angle of attack (deg) and the load factor (g).
    pub aoa: f64,
    pub g: f64,
    /// The failures on (training.md §15; the engine fire while it burns), by id.
    pub failures: Vec<String>,
    /// The player's flight (`IafAi.facts`, §16.8): the player in its slot, every other jet in position, every jet
    /// down; the AI lead's orders given.
    pub in_slot: bool,
    pub flight_joined: bool,
    pub flight_landed: bool,
    pub lead_orders: Vec<String>,
    /// The tanker's events for the player's jet so far (`course::TANKER_EVENTS`).
    pub tanker: Vec<String>,
    /// The route's steerpoints in the engine frame, m, the first first.
    pub route: Vec<[f64; 2]>,
}

/// A line said: its call, its clip, its English and Hebrew subtitles.
#[derive(Debug, Clone, PartialEq)]
pub struct Said {
    pub call: String,
    pub file: String,
    pub en: String,
    pub he: String,
}

/// A lesson's calls in one flight.
pub struct Calls {
    key: String,
    calls: Vec<Call>,
    radio: bool,
    runway: Runway,
    /// The runway end in use (its index in `runway`).
    end: usize,
    /// The base's elevation, ft.
    elevation_ft: f64,
    /// Where the jet first stood on the ground.
    spot: Option<[f64; 2]>,
    next: usize,
    /// A `new` call's tests failed since the call before it fired.
    armed: bool,
}

fn angle(a: f64, b: f64) -> f64 {
    180.0 - (b - a + 180.0).rem_euclid(360.0)
}

impl Calls {
    /// The calls of lesson `key` in jet `jet` at `base`, from runway end `rwy` ("" the base's main end); none in a
    /// check ride or a lesson without calls, and no start-up call once `startup_known` (the pilot passed phase 1).
    pub fn open(key: &str, jet: &str, base: &Base, rwy: &str, startup_known: bool) -> Result<Calls> {
        let c = course::course();
        let (p, l) = c.find(key).with_context(|| format!("calls: {key} is no lesson"))?;
        let check = c.phases[p].lessons[l].kind == Kind::Check;
        let content = &c.phases[p].lessons[l].content["calls"];
        let calls = content.as_array().into_iter().flatten().map(Call::of).collect::<Result<Vec<_>>>()?;
        let calls = calls.into_iter().filter(|x| x.said_in(jet, check, startup_known)).collect();
        let (ri, end) = if rwy.is_empty() { Some(base.main) } else { base.end(rwy) }
            .with_context(|| format!("calls: {} has no runway {rwy}", base.name_en))?;
        Ok(Calls {
            key: key.into(),
            calls,
            radio: on_radio(jet),
            runway: base.runways[ri].clone(),
            end,
            elevation_ft: base.elevation * 3.28084,
            spot: None,
            next: 0,
            armed: false,
        })
    }

    /// The runway end in use.
    pub fn runway(&self) -> &str {
        &self.runway.designators[self.end]
    }

    /// The engine-frame point `along` m from the threshold of the runway in use and `right` m to its right, the
    /// base's elevation (ft) and the runway's heading (deg): where a scripted flight puts the jet.
    pub fn place(&self, along: f64, right: f64) -> ([f64; 2], f64, f64) {
        let (e, d) = (self.runway.ends[self.end], self.runway.dir(self.end));
        let p = [e[0] + d[0] * along + d[1] * right, e[1] + d[1] * along - d[0] * right];
        (p, self.elevation_ft, self.runway.heading(self.end))
    }

    /// The calls left to say, by id.
    pub fn left(&self) -> Vec<&str> {
        self.calls[self.next.min(self.calls.len())..].iter().map(|c| c.id.as_str()).collect()
    }

    fn holds(&self, t: &Test, s: &Now) -> bool {
        let r = &self.runway;
        let k = self.end;
        let (e, d) = (r.ends[k], r.dir(k));
        let (dx, dy) = (s.x - e[0], s.y - e[1]);
        let along = dx * d[0] + dy * d[1];
        let cross = (dx * d[1] - dy * d[0]).abs();
        let off = angle(r.heading(k), s.heading).abs();
        let air = !s.on_ground;
        let agl = s.alt_ft - self.elevation_ft;
        let stopped = s.speed_kt < STOPPED_KT;
        let on_runway = cross <= r.width / 2.0 && (0.0..=r.length()).contains(&along);
        match t {
            Test::Start => true,
            Test::Idle => s.rpm >= IDLE_RPM,
            Test::Aligned => s.ins_aligned,
            Test::HoldPoint => {
                let l = r.lineup(k);
                let near = (s.x - l[0]).hypot(s.y - l[1])
                    <= crate::training::HOLDING_POINT_M + crate::training::HOLDING_POINT_MARGIN_M;
                s.on_ground && stopped && near && !on_runway
            }
            Test::LinedUp => {
                s.on_ground && stopped && on_runway && along < r.length() / 2.0 && off <= crate::training::LINED_UP_DEG
            }
            Test::Initial => {
                air && (-INITIAL_M[1]..=-INITIAL_M[0]).contains(&along) && cross <= INITIAL_CROSS_M && off <= LEG_DEG
            }
            Test::OverRunway => air && (0.0..=r.length()).contains(&along) && cross <= OVER_RUNWAY_M,
            Test::Downwind => air && 180.0 - off <= LEG_DEG && (DOWNWIND_M[0]..=DOWNWIND_M[1]).contains(&cross),
            Test::FinalTurn => air && along <= 0.0 && (DOWNWIND_M[0]..=DOWNWIND_M[1]).contains(&cross),
            Test::Final => {
                air && (-FINAL_M..=0.0).contains(&along)
                    && cross <= FINAL_CROSS_M
                    && off <= FINAL_DEG
                    && s.roll.abs() <= LEVEL_DEG
            }
            Test::TouchdownZone => (0.0..=TDZ_M).contains(&along) && cross <= OVER_RUNWAY_M && agl <= LOW_FT,
            Test::ClimbOut => air && along > 0.0 && agl > LOW_FT && s.vs_fpm >= CLIMB_FPM,
            Test::Slowed => s.on_ground && on_runway && s.speed_kt <= SLOWED_KT,
            Test::Parked => {
                s.on_ground && stopped && self.spot.is_some_and(|p| (s.x - p[0]).hypot(s.y - p[1]) <= PARKED_M)
            }
            Test::EngineOff => !s.engine_on,
            Test::PowerOff => s.power == 0,
            Test::Item(id) => s.items.contains(id),
            Test::Cleared(k) => match k.as_str() {
                "startup" => s.cleared.start,
                "taxi" => s.cleared.taxi,
                _ => s.cleared.takeoff,
            },
            Test::Called(id) => s.called.contains(id),
            Test::Failure(id) => s.failures.contains(id),
            Test::Alt(ft) => air && agl >= *ft,
            Test::Aoa(deg) => air && s.aoa >= *deg,
            Test::G(g) => air && s.g >= *g,
            Test::Airborne => air,
            Test::InSlot => s.in_slot,
            Test::FlightJoined => s.flight_joined,
            Test::FlightLanded => s.flight_landed,
            Test::LeadOrder(o) => s.lead_orders.contains(o),
            Test::Tanker(e) => s.tanker.contains(e),
            Test::Steerpoint(n) => air && s.route.get(n - 1).is_some_and(|p| (s.x - p[0]).hypot(s.y - p[1]) <= STEER_M),
        }
    }

    /// The lines to say now: those of every call whose turn came and whose tests hold, in order.
    pub fn tick(&mut self, s: &Now) -> Vec<Said> {
        if s.on_ground && self.spot.is_none() {
            self.spot = Some([s.x, s.y]);
        }
        let mut out = vec![];
        while let Some(c) = self.calls.get(self.next) {
            let ok = c.when.iter().all(|t| self.holds(t, s));
            if c.new && !self.armed {
                self.armed = !ok;
                break;
            }
            if !ok {
                break;
            }
            let rwy = self.runway().to_string();
            let w = runway_words(&rwy);
            for (n, l) in c.lines.iter().enumerate() {
                let (en, he) = (l["en"].as_str().unwrap_or(""), l["he"].as_str().unwrap_or(""));
                let has = en.contains("{rwy}");
                out.push(Said {
                    call: c.id.clone(),
                    file: file(&self.key, &c.id, n, has.then_some(rwy.as_str()), self.radio),
                    en: en.replace("{rwy}", &w[1]),
                    he: he.replace("{rwy}", &w[2]),
                });
            }
            self.next += 1;
            self.armed = false;
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn ramon() -> Base {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data/airbases");
        let bases = crate::sim_bases::load(&dir).unwrap();
        crate::sim_bases::by_name(&bases, "Ramon").unwrap().clone()
    }

    /// Calls of ids and tests, one line each ("en" its id).
    fn calls(list: &[(&str, &[&str], bool)]) -> Vec<Call> {
        list.iter()
            .map(|(id, when, new)| {
                Call::of(&json!({"id": id, "when": when, "new": new, "lines": [{"en": id, "he": id}]})).unwrap()
            })
            .collect()
    }

    #[test]
    fn every_test_has_its_rule_and_the_runway_its_words() {
        for t in course::TESTS {
            assert!(Test::of(t).is_ok(), "{t}");
        }
        let args = ["item:batt", "cleared:taxi", "called:radio_check", "failure:flameout", "alt:9500", "aoa:15", "g:7"];
        for t in args.into_iter().chain([
            "called:fingertip:0",
            "lead_order:tac_right",
            "called:awacs:checkin",
            "tanker:contact",
            "steerpoint:4",
        ]) {
            assert!(Test::of(t).is_ok(), "{t}");
        }
        assert!(Test::of("cleared:landing").is_err() && Test::of("nope").is_err() && Test::of("aoa:x").is_err());
        assert!(Test::of("tanker:nope").is_err());
        assert_eq!(runway_words("25R"), ["two five right".to_string(), "25 right".into(), "25 ימין".into()]);
        assert_eq!(runway_words("07L")[0], "seven left");
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data/airbases");
        let clips = clips(&crate::sim_bases::load(&dir).unwrap()).unwrap();
        assert!(clips.iter().any(|c| c.file == "ins_ground_cockpit_intro_1.ogg" && !c.radio), "the F-16s' intercom");
        assert!(clips.iter().any(|c| c.file == "insr_ground_cockpit_intro_1.ogg"), "the F-35I's radio");
        assert_eq!(file("pattern.overhead", "taxi", 0, Some("25R"), false), "ins_pattern_overhead_taxi_0_25r.ogg");
    }

    /// Lesson 1.1 (ground.json) in the Sufa: each call at its checklist item, the radio call, then the jet dark.
    #[test]
    fn the_cockpit_lessons_calls_fire_in_order() {
        let b = ramon();
        let mut c = Calls::open("ground.cockpit", "f16i", &b, "", false).unwrap();
        let mut n = Now { on_ground: true, ..Now::default() };
        let mut flown: Vec<String> = vec![];
        let mut fly = |c: &mut Calls, n: &Now| flown.extend(c.tick(n).into_iter().map(|s| s.call));
        fly(&mut c, &n);
        for item in ["batt", "flcs_pwr_test", "main_power", "fire_test"] {
            n.items.push(item.into());
            n.power = 1;
            fly(&mut c, &n);
        }
        n.items.push("mal_ind_test".into());
        fly(&mut c, &n);
        n.called.push("radio_check".into());
        fly(&mut c, &n);
        n.power = 0;
        fly(&mut c, &n);
        let want =
            ["intro", "intro", "batt", "main_power", "dark_displays", "dark_displays", "radio", "power_down", "end"];
        assert_eq!(flown, want, "each line of each call");
        assert!(c.left().is_empty());
        // The Adir's calls are its own.
        let c = Calls::open("ground.cockpit", "f35i", &b, "", false).unwrap();
        assert!(c.left().contains(&"ipp") && !c.left().contains(&"batt"));
    }

    /// Lesson 2.4 (pattern.json) in the Sufa, its exercises' calls on the height, the angle of attack and the load; and
    /// lesson 2.5's fire calls on the fire burning, the second once the first is out.
    #[test]
    fn the_figures_and_failures_calls_fire_at_their_values() {
        let b = ramon();
        let mut c = Calls::open("pattern.high_aoa", "f16i", &b, "25R", true).unwrap();
        c.calls.retain(|x| ["slow", "limiter", "corner", "home"].contains(&x.id.as_str()));
        let (p, elev, hdg) = c.place(2000.0, 0.0);
        let mut n = Now { x: p[0], y: p[1], heading: hdg, alt_ft: elev + 15_000.0, g: 1.0, aoa: 5.0, ..Now::default() };
        let mut flown: Vec<String> = vec![];
        let mut fly = |c: &mut Calls, n: &Now| flown.extend(c.tick(n).into_iter().map(|s| s.call));
        fly(&mut c, &n);
        n.aoa = 14.0;
        fly(&mut c, &n);
        n.aoa = 24.0;
        fly(&mut c, &n);
        n.g = 8.0;
        fly(&mut c, &n);
        assert_eq!(flown, ["slow", "limiter", "corner", "home"]);
        let mut c = Calls::open("pattern.engine_fire", "f16i", &b, "25R", true).unwrap();
        c.calls.retain(|x| ["abort", "fire"].contains(&x.id.as_str()));
        c.calls[1].new = true;
        let mut n = Now { failures: vec!["engine_fire".into()], ..Now::default() };
        assert_eq!(c.tick(&n).len(), 1, "the roll's fire");
        assert!(c.tick(&n).is_empty(), "the same fire: no second call");
        n.failures.clear();
        c.tick(&n);
        n.failures.push("engine_fire".into());
        assert_eq!(c.tick(&n).len(), 1, "the flight's fire");
    }

    /// Lesson 3.1 (navigation.json) in the Sufa: each steerpoint's call within a mile of it, in the air, in order; and
    /// lesson 3.4's failure calls as each failure comes, the Adir's gear fault its own.
    #[test]
    fn the_steerpoint_and_failure_calls_fire_at_their_step() {
        let b = ramon();
        let mut c = Calls::open("navigation.steerpoints", "f16i", &b, "25R", true).unwrap();
        c.calls.retain(|x| x.id.starts_with("sp"));
        let route = vec![
            [700_000.0, 3_420_000.0],
            [710_000.0, 3_400_000.0],
            [720_000.0, 3_410_000.0],
            [715_000.0, 3_415_000.0],
        ];
        let mut n = Now { alt_ft: 15_000.0, route: route.clone(), ..Now::default() };
        let mut flown: Vec<String> = vec![];
        for (k, p) in route.iter().enumerate() {
            [n.x, n.y] = [p[0] + 2_500.0, p[1]];
            assert!(c.tick(&n).is_empty(), "steerpoint {} not yet: 2.5 km out", k + 1);
            n.x = p[0] + 1_000.0;
            n.on_ground = k == 0;
            flown.extend(c.tick(&n).into_iter().map(|s| s.call));
            n.on_ground = false;
            flown.extend(c.tick(&n).into_iter().map(|s| s.call));
        }
        assert_eq!(flown, ["sp1", "sp2", "sp3", "sp4"]);
        assert!(Test::of("steerpoint:0").is_err() && Test::of("steerpoint:x").is_err());
        let mut c = Calls::open("navigation.systems", "f16i", &b, "25R", true).unwrap();
        c.calls.retain(|x| x.id.starts_with('g') || ["epu", "hyd"].contains(&x.id.as_str()));
        assert_eq!(c.left(), ["gen", "gains", "epu", "hyd"], "the Sufa's: no gear fault");
        let mut n = Now::default();
        let mut said = vec![];
        for f in ["gen_main", "standby_gains", "gen_epu", "hyd_b"] {
            n.failures.push(f.into());
            said.extend(c.tick(&n).into_iter().map(|s| s.call));
        }
        assert_eq!(said, ["gen", "gains", "epu", "hyd"]);
        let c = Calls::open("navigation.systems", "f35i", &b, "25R", true).unwrap();
        assert!(c.left().contains(&"gear") && !c.left().contains(&"epu"), "the Adir's: the gear fault, no EPU");
    }

    /// Phase 6's lessons (control.json) open in each jet: their AWACS `called:` and `tanker:` tests are known.
    #[test]
    fn the_control_lessons_calls_open() {
        let b = ramon();
        for l in ["checkin", "vectors", "tanker", "night"] {
            for jet in ["f16d", "f16i", "f35i"] {
                let c = Calls::open(&format!("control.{l}"), jet, &b, "", true).unwrap();
                assert!(!c.left().is_empty(), "control.{l} {jet}");
            }
        }
        let t = Test::of("tanker:contact").unwrap();
        let c = Calls::open("control.tanker", "f16i", &b, "", true).unwrap();
        let mut n = Now::default();
        assert!(!c.holds(&t, &n));
        n.tanker.push("contact".into());
        assert!(c.holds(&t, &n));
    }

    /// A lesson of the overhead pattern flown as a script of frames: every call in order, each once, at its step.
    #[test]
    fn the_pattern_tests_fire_in_order() {
        let b = ramon();
        let mut c = Calls::open("ground.cockpit", "f16i", &b, "25R", false).unwrap();
        c.calls = calls(&[
            ("intro", &["start"], false),
            ("taxi", &["idle", "aligned"], false),
            ("hold", &["hold_point"], false),
            ("lined_up", &["lined_up"], false),
            ("my_controls", &["initial"], false),
            ("demo_break", &["over_runway"], false),
            ("demo_downwind", &["downwind"], false),
            ("demo_final_turn", &["final_turn"], false),
            ("demo_touchdown", &["touchdown_zone"], false),
            ("your_controls", &["climb_out"], false),
            ("initial", &["initial"], true),
            ("downwind", &["downwind"], false),
            ("final", &["final"], false),
            ("rollout", &["slowed"], false),
            ("shelter", &["parked"], true),
        ]);
        c.elevation_ft = 0.0;
        let r = c.runway.clone();
        let (e, d) = (r.ends[c.end], r.dir(c.end));
        let hdg = r.heading(c.end);
        assert_eq!(c.place(10.0, 0.0).0, [e[0] + d[0] * 10.0, e[1] + d[1] * 10.0]);
        // A point `along` the runway from its threshold and `cross` to its right, m.
        let at = |along: f64, cross: f64| [e[0] + d[0] * along + d[1] * cross, e[1] + d[1] * along - d[0] * cross];
        let ground = |p: [f64; 2], kt: f64, hdg: f64, rpm: f64| Now {
            on_ground: true,
            x: p[0],
            y: p[1],
            speed_kt: kt,
            heading: hdg,
            rpm,
            ins_aligned: rpm > 0.0,
            ..Now::default()
        };
        let air = |p: [f64; 2], ft: f64, hdg: f64, vs: f64| Now {
            x: p[0],
            y: p[1],
            alt_ft: ft,
            speed_kt: 300.0,
            heading: hdg,
            vs_fpm: vs,
            rpm: 90.0,
            ins_aligned: true,
            ..Now::default()
        };
        let spot = at(-400.0, 600.0);
        let lu = r.lineup(c.end);
        let frames = [
            ground(spot, 0.0, 0.0, 0.0),
            ground(spot, 0.0, 0.0, 70.0),
            ground([lu[0] - d[1] * 80.0, lu[1] + d[0] * 80.0], 0.0, hdg, 70.0),
            ground(lu, 0.0, hdg, 90.0),
            air(at(3000.0, 0.0), 500.0, hdg, 2000.0), // the climb after take-off: nothing yet
            air(at(-7000.0, 0.0), 1500.0, hdg, 0.0),  // initial: my controls
            air(at(300.0, 0.0), 1500.0, hdg, 0.0),    // the break
            air(at(1500.0, -1800.0), 1500.0, hdg + 180.0, 0.0),
            air(at(-200.0, -1800.0), 1000.0, hdg + 180.0, -500.0),
            air(at(300.0, 0.0), 50.0, hdg, 0.0), // low over the touchdown zone
            air(at(2000.0, 0.0), 800.0, hdg, 2000.0),
            air(at(-7000.0, 0.0), 1500.0, hdg, 0.0),
            air(at(1500.0, -1800.0), 1500.0, hdg + 180.0, 0.0),
            air(at(-2000.0, 0.0), 600.0, hdg, -700.0),
            ground(at(1500.0, 0.0), 30.0, hdg, 90.0),
            ground(spot, 0.0, 0.0, 90.0),
        ];
        let flown: Vec<String> = frames.iter().flat_map(|f| c.tick(f)).map(|s| s.call).collect();
        let want = [
            "intro",
            "taxi",
            "hold",
            "lined_up",
            "my_controls",
            "demo_break",
            "demo_downwind",
            "demo_final_turn",
            "demo_touchdown",
            "your_controls",
            "initial",
            "downwind",
            "final",
            "rollout",
            "shelter",
        ];
        assert_eq!(flown, want);
    }

    /// A `new` call waits for its tests to fail once after the call before it; `{rwy}` takes the runway.
    #[test]
    fn a_new_call_waits_for_its_step_to_come_again() {
        let b = ramon();
        let mut c = Calls::open("ground.cockpit", "f16i", &b, "25R", false).unwrap();
        c.calls = calls(&[("a", &["idle"], false), ("b", &["idle"], true)]);
        c.calls[0].lines.push(json!({"en": "Taxi to runway {rwy}.", "he": "הסעה למסלול {rwy}."}));
        let idle = Now { rpm: 70.0, ..Now::default() };
        let said = c.tick(&idle);
        assert_eq!(said.len(), 2, "a: its two lines");
        assert_eq!((said[1].en.as_str(), said[1].he.as_str()), ("Taxi to runway 25 right.", "הסעה למסלול 25 ימין."));
        assert_eq!(said[1].file, file("ground.cockpit", "a", 1, Some("25R"), false));
        assert!(c.tick(&idle).is_empty(), "b's step has not come again");
        assert!(c.tick(&Now::default()).is_empty());
        assert_eq!(c.tick(&idle).len(), 1, "b");
    }

    #[test]
    fn no_start_up_calls_once_phase_1_is_passed_and_none_in_check_rides() {
        let mut c = calls(&[("a", &["start"], false)]).remove(0);
        assert!(c.said_in("f16i", false, true) && c.said_in("f35i", false, false));
        assert!(!c.said_in("f16i", true, false), "a check ride");
        c.startup = true;
        assert!(c.said_in("f16i", false, false) && !c.said_in("f16i", false, true), "phase 1 passed");
        c.jets = vec!["f35i".into()];
        assert!(!c.said_in("f16i", false, false), "another jet's");
        assert!(Calls::open("ground.check", "f16i", &ramon(), "", false).unwrap().left().is_empty());
    }
}
