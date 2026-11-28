//! Modern IAF's training course (modern-iaf/docs/training.md §13, the plan modern-iaf/docs/training-plan.md): per jet
//! the eight phases and their lessons, each lesson's graded items with their standard (the data:
//! `modern-iaf/data/training/course.json`, built into the library), and the rules every screen and the flight call:
//! an item's grade against its standard, a lesson's grade from its items, the lesson a mission flies, the logbook
//! (each lesson's best attempt, each phase's progress, the next lesson) and a check ride's unannounced emergency.

use anyhow::{Context, Result, bail, ensure};
use serde_json::{Map, Value, json};
use std::sync::OnceLock;

const DATA: &str = include_str!("../../../modern-iaf/data/training/course.json");

/// Each phase's lesson content (training.md §16): `(phase id, the text of modern-iaf/data/training/lessons/<id>.json)`.
/// A phase without a file has no content yet; a new phase's file is added here and to the stamps' sources.
const LESSONS: &[(&str, &str)] = &[("ground", include_str!("../../../modern-iaf/data/training/lessons/ground.json"))];

/// The briefing's sections in their order (training-plan.md §2.2): each a list of paragraphs.
pub const SECTIONS: [&str; 8] =
    ["mission", "target", "enemy", "our_forces", "weather_area", "execution", "coordination", "signal"];

/// The tests a call (and a lesson's end) waits for, by name (training.md §16.3). The instructor's call engine reads
/// them; each needs its rule there.
pub const TESTS: [&str; 16] = [
    "start",
    "idle",
    "aligned",
    "hold_point",
    "lined_up",
    "initial",
    "over_runway",
    "downwind",
    "final_turn",
    "final",
    "touchdown_zone",
    "climb_out",
    "slowed",
    "parked",
    "engine_off",
    "power_off",
];

/// The tests with an argument after a colon: `item:<card item id>` (ticked on the jet's checklist card),
/// `cleared:<phase>` (the tower's clearance, training::CLEARANCES), `called:<radio call id>` (the pilot made the call).
pub const ARG_TESTS: [&str; 3] = ["item", "cleared", "called"];

/// An item's grade on the US Navy's flight-training scale (training-plan.md §2.4), worst first.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Grade {
    Unsatisfactory,
    BelowAverage,
    Average,
    AboveAverage,
}

impl Grade {
    pub fn id(self) -> &'static str {
        match self {
            Grade::Unsatisfactory => "unsat",
            Grade::BelowAverage => "below",
            Grade::Average => "average",
            Grade::AboveAverage => "above",
        }
    }
}

/// A lesson's grade (training-plan.md §2.4): Pass, Marginal (passed with an item Below average), Unsatisfactory.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum LessonGrade {
    Unsatisfactory,
    Marginal,
    Pass,
}

impl LessonGrade {
    pub fn id(self) -> &'static str {
        match self {
            LessonGrade::Unsatisfactory => "unsat",
            LessonGrade::Marginal => "marginal",
            LessonGrade::Pass => "pass",
        }
    }

    pub fn of(id: &str) -> Option<LessonGrade> {
        [LessonGrade::Unsatisfactory, LessonGrade::Marginal, LessonGrade::Pass].into_iter().find(|r| r.id() == id)
    }

    /// Marginal counts as passed.
    pub fn passed(self) -> bool {
        self != LessonGrade::Unsatisfactory
    }
}

/// The lesson's grade: Unsatisfactory when the flight failed (a crash, a fail rule) or an item is Unsatisfactory,
/// Marginal with an item Below average, else Pass.
pub fn lesson_grade(flight_passed: bool, items: &[Grade]) -> LessonGrade {
    match items.iter().min() {
        _ if !flight_passed => LessonGrade::Unsatisfactory,
        Some(Grade::Unsatisfactory) => LessonGrade::Unsatisfactory,
        Some(Grade::BelowAverage) => LessonGrade::Marginal,
        _ => LessonGrade::Pass,
    }
}

/// How a standard reads the flown value: at most (`Max`), at least (`Min`), or its distance from a target (`Tol`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Limit {
    Max,
    Min,
    Tol(f64),
}

/// A graded item's standard: the limits of Above average, Average (the standard itself) and Below average, in that
/// order; past the last, Unsatisfactory. `Max`: the flown value at most each; `Min`: at least each (falling);
/// `Tol(target)`: the distance from the target at most each.
#[derive(Debug, Clone, PartialEq)]
pub struct Standard {
    pub limit: Limit,
    pub bands: [f64; 3],
    pub unit: String,
}

impl Standard {
    pub fn parse(v: &Value) -> Result<Standard> {
        let b = v["bands"].as_array().context("standard: \"bands\" must be [above, average, below]")?;
        let b: Vec<f64> = b.iter().filter_map(Value::as_f64).collect();
        let bands: [f64; 3] = b.try_into().ok().context("standard: \"bands\" must be three numbers")?;
        let limit = match v["limit"].as_str() {
            Some("max") => Limit::Max,
            Some("min") => Limit::Min,
            Some("tol") => Limit::Tol(v["target"].as_f64().context("standard: \"tol\" needs \"target\"")?),
            l => bail!("standard: \"limit\" must be \"max\", \"min\" or \"tol\", not {l:?}"),
        };
        let rising = bands.windows(2).all(|w| w[0] <= w[1]);
        let falling = bands.windows(2).all(|w| w[0] >= w[1]);
        ensure!(if limit == Limit::Min { falling } else { rising }, "standard: bands {bands:?} out of order");
        Ok(Standard { limit, bands, unit: v["unit"].as_str().context("standard: \"unit\"")?.to_string() })
    }

    /// The grade of the flown value; not flown (None) is Unsatisfactory.
    pub fn grade(&self, flown: Option<f64>) -> Grade {
        let Some(f) = flown else { return Grade::Unsatisfactory };
        let within = |b: f64| match self.limit {
            Limit::Max => f <= b,
            Limit::Min => f >= b,
            Limit::Tol(_) => self.gap(f).abs() <= b,
        };
        match self.bands.iter().position(|b| within(*b)) {
            Some(0) => Grade::AboveAverage,
            Some(1) => Grade::Average,
            Some(_) => Grade::BelowAverage,
            None => Grade::Unsatisfactory,
        }
    }

    /// The gap: the flown value less what should have been flown (the target, or the Average limit); in degrees the
    /// shorter way round (359° against 1° is −2°).
    pub fn gap(&self, flown: f64) -> f64 {
        let d = flown - self.should();
        if self.unit == "deg" { (d + 180.0).rem_euclid(360.0) - 180.0 } else { d }
    }

    /// What should have been flown: the target (`Tol`) or the Average limit.
    pub fn should(&self) -> f64 {
        match self.limit {
            Limit::Tol(t) => t,
            _ => self.bands[1],
        }
    }

    pub fn to_json(&self) -> Value {
        let mut v = json!({"bands": self.bands, "unit": self.unit});
        match self.limit {
            Limit::Max => v["limit"] = json!("max"),
            Limit::Min => v["limit"] = json!("min"),
            Limit::Tol(t) => {
                v["limit"] = json!("tol");
                v["target"] = json!(t);
            }
        }
        v
    }
}

/// A lesson's kind: a day lesson, the phase's night lesson, its check ride.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Kind {
    Day,
    Night,
    Check,
}

#[derive(Debug, Clone)]
pub struct Lesson {
    pub id: String,
    pub kind: Kind,
    /// Flown at night: the night lesson, and the check rides that say so.
    pub night: bool,
    pub title: Value,
    /// What it trains, one line for the lesson list.
    pub line: Value,
    /// Its graded items' ids (a check ride: `Course::items`).
    pub items: Vec<String>,
    /// The emergencies it teaches.
    pub emergencies: Vec<String>,
    /// The mission that flies it, by jet.
    pub missions: Map<String, Value>,
    /// Its content from the phase's lesson file (training.md §16): `briefing`, `lesson_tab`, `calls`; null without.
    pub content: Value,
}

#[derive(Debug, Clone)]
pub struct Phase {
    pub id: String,
    pub title: Value,
    /// Its skills appear only in its own check ride (the formation phase).
    pub own_check_only: bool,
    pub lessons: Vec<Lesson>,
}

#[derive(Debug, Clone)]
pub struct Emergency {
    /// The moment its time counts from: "roll" (the take-off roll's start) or "airborne" (the lift-off).
    pub at: String,
    /// Its time after that moment: from, to (s).
    pub window_s: [f64; 2],
    pub label: Value,
    /// The jets it is taught in; empty: every jet.
    pub jets: Vec<String>,
}

impl Emergency {
    pub fn of(&self, jet: &str) -> bool {
        self.jets.is_empty() || self.jets.iter().any(|j| j == jet)
    }
}

#[derive(Debug, Clone)]
pub struct Item {
    pub label: Value,
    pub standard: Standard,
}

#[derive(Debug, Clone)]
pub struct Course {
    /// Per jet's unit id: `base`, `instructor`.
    pub jets: Map<String, Value>,
    pub phases: Vec<Phase>,
    pub items: Vec<(String, Item)>,
    pub emergencies: Vec<(String, Emergency)>,
}

fn strings(v: &Value, what: &str) -> Result<Vec<String>> {
    v.as_array()
        .map_or(Ok(vec![]), |a| a.iter().map(|s| s.as_str().map(String::from).context(what.to_string())).collect())
}

fn label(v: &Value, what: &str) -> Result<Value> {
    ensure!(v["en"].is_string() && v["he"].is_string(), "{what}: needs \"en\" and \"he\"");
    Ok(v.clone())
}

/// Phase `phase`'s lesson file, parsed; None for a phase without one.
fn lesson_file(phase: &str) -> Result<Option<Value>> {
    let f = LESSONS.iter().find(|l| l.0 == phase);
    f.map(|l| serde_json::from_str(l.1).with_context(|| format!("lessons/{phase}.json"))).transpose()
}

/// Lesson `id`'s content in phase `phase`'s lesson file; null without one.
fn lesson_content(phase: &str, id: &str) -> Result<Value> {
    Ok(lesson_file(phase)?.map_or(Value::Null, |f| f["lessons"][id].clone()))
}

/// A paragraph, a notebook line or a call's line: `en` and `he`, and `jets`, optional, jets of the course.
fn check_text(v: &Value, what: &str, jets: &Value) -> Result<()> {
    label(v, what)?;
    for j in strings(&v["jets"], what)? {
        ensure!(jets[&j].is_object(), "{what}: \"jets\" names {j}, no jet of the course");
    }
    Ok(())
}

/// A test's name is one of `TESTS`, or `<one of ARG_TESTS>:<argument>`.
pub fn test_ok(t: &str) -> bool {
    match t.split_once(':') {
        Some((k, a)) => ARG_TESTS.contains(&k) && !a.is_empty(),
        None => TESTS.contains(&t),
    }
}

/// Lesson `key`'s content (training.md §16): every section of the briefing with a paragraph, the Execution's places and
/// switches known, the notebook's lines, the calls' ids unique and their tests known; a check ride has no calls.
fn check_content(key: &str, c: &Value, jets: &Value, check_ride: bool) -> Result<()> {
    if c.is_null() {
        return Ok(());
    }
    for k in c.as_object().with_context(|| format!("{key}: its content must be an object"))?.keys() {
        ensure!(["missions", "briefing", "lesson_tab", "calls"].contains(&k.as_str()), "{key}: \"{k}\" is no field");
    }
    let b = &c["briefing"];
    for s in SECTIONS {
        let ps = b[s].as_array().filter(|a| !a.is_empty());
        let ps = ps.with_context(|| format!("{key}: \"briefing.{s}\" needs its paragraphs"))?;
        for (i, p) in ps.iter().enumerate() {
            let what = format!("{key}: briefing.{s}[{i}]");
            check_text(p, &what, jets)?;
            if let Some(at) = p.get("at") {
                let ok = at.as_str().is_some_and(|a| crate::training::STEP_PLACES.contains(&a));
                ensure!(ok, "{what}: \"at\" {at} is no place");
            }
            for sw in strings(&p["switches"], &what)? {
                ensure!(crate::training::STEPS.contains(&sw.as_str()), "{what}: switch {sw} is no start-up step");
            }
        }
    }
    if let Some(o) = b.as_object() {
        for k in o.keys() {
            ensure!(SECTIONS.contains(&k.as_str()), "{key}: \"briefing.{k}\" is no section");
        }
    }
    for (i, l) in c["lesson_tab"].as_array().into_iter().flatten().enumerate() {
        let what = format!("{key}: lesson_tab[{i}]");
        check_text(l, &what, jets)?;
        if !l["wait"].is_null() {
            label(&l["wait"], &what)?;
        }
    }
    let calls = c["calls"].as_array().map_or(&[][..], |a| a.as_slice());
    ensure!(!check_ride || calls.is_empty(), "{key}: a check ride has no calls");
    let mut ids: Vec<&str> = vec![];
    for (i, call) in calls.iter().enumerate() {
        let id = call["id"].as_str().with_context(|| format!("{key}: calls[{i}] without \"id\""))?;
        ensure!(!ids.contains(&id), "{key}: call {id} twice");
        ids.push(id);
        let when = strings(&call["when"], id)?;
        ensure!(!when.is_empty(), "{key}: call {id} needs \"when\"");
        for t in &when {
            ensure!(test_ok(t), "{key}: call {id}: \"{t}\" is no test");
        }
        for j in strings(&call["jets"], id)? {
            ensure!(jets[&j].is_object(), "{key}: call {id}: \"jets\" names {j}, no jet of the course");
        }
        let lines = call["lines"].as_array().filter(|a| !a.is_empty());
        for (n, line) in lines.with_context(|| format!("{key}: call {id} needs \"lines\""))?.iter().enumerate() {
            label(line, &format!("{key}: call {id} line {n}"))?;
        }
    }
    Ok(())
}

/// `v` for jet `jet`: every array's entries whose `jets` leave it out dropped, at any depth.
fn for_jet(v: &Value, jet: &str) -> Value {
    match v {
        Value::Array(a) => Value::Array(
            a.iter()
                .filter(|e| e["jets"].as_array().is_none_or(|js| js.iter().any(|j| j == jet)))
                .map(|e| for_jet(e, jet))
                .collect(),
        ),
        Value::Object(o) => Value::Object(o.iter().map(|(k, e)| (k.clone(), for_jet(e, jet))).collect()),
        _ => v.clone(),
    }
}

impl Course {
    /// The course of the data file's text, checked: every lesson's items and emergencies named, a check ride last
    /// in each phase.
    pub fn parse(text: &str) -> Result<Course> {
        let v: Value = serde_json::from_str(text)?;
        let items = v["items"]
            .as_object()
            .context("\"items\"")?
            .iter()
            .map(|(id, i)| {
                let standard = Standard::parse(&i["standard"]).with_context(|| format!("item {id}"))?;
                Ok((id.clone(), Item { label: label(&i["label"], id)?, standard }))
            })
            .collect::<Result<Vec<_>>>()?;
        let emergencies = v["emergencies"]
            .as_object()
            .context("\"emergencies\"")?
            .iter()
            .map(|(id, e)| {
                let w: Vec<f64> = e["window_s"].as_array().into_iter().flatten().filter_map(Value::as_f64).collect();
                ensure!(w.len() == 2 && w[0] <= w[1], "emergency {id}: \"window_s\" must be [from, to]");
                let at = e["at"].as_str().unwrap_or("");
                ensure!(at == "roll" || at == "airborne", "emergency {id}: \"at\" must be \"roll\" or \"airborne\"");
                let jets = strings(&e["jets"], id)?;
                for j in &jets {
                    ensure!(v["jets"][j].is_object(), "emergency {id}: \"jets\" names {j}, no jet of the course");
                }
                let label = label(&e["label"], id)?;
                Ok((id.clone(), Emergency { at: at.into(), window_s: [w[0], w[1]], label, jets }))
            })
            .collect::<Result<Vec<_>>>()?;
        let mut phases = vec![];
        for p in v["phases"].as_array().context("\"phases\"")? {
            let pid = p["id"].as_str().context("phase without \"id\"")?.to_string();
            let mut lessons = vec![];
            for l in p["lessons"].as_array().with_context(|| format!("{pid}: \"lessons\""))? {
                let id = l["id"].as_str().with_context(|| format!("{pid}: a lesson without \"id\""))?.to_string();
                let key = format!("{pid}.{id}");
                let kind = match l["kind"].as_str() {
                    None | Some("day") => Kind::Day,
                    Some("night") => Kind::Night,
                    Some("check") => Kind::Check,
                    Some(k) => bail!("{key}: \"kind\" {k} is no lesson kind"),
                };
                let items = strings(&l["items"], &key)?;
                let emergencies = strings(&l["emergencies"], &key)?;
                for i in &items {
                    ensure!(v["items"][i].is_object(), "{key}: item {i} is not in \"items\"");
                }
                for e in &emergencies {
                    ensure!(v["emergencies"][e].is_object(), "{key}: emergency {e} is not in \"emergencies\"");
                }
                ensure!(kind == Kind::Check || !items.is_empty(), "{key}: a lesson grades at least one item");
                let content = lesson_content(&pid, &id)?;
                let mut missions = l["missions"].as_object().cloned().unwrap_or_default();
                if let Some(m) = content["missions"].as_object() {
                    ensure!(missions.is_empty(), "{key}: \"missions\" both in course.json and in its lesson file");
                    missions = m.clone();
                }
                check_content(&key, &content, &v["jets"], kind == Kind::Check)?;
                for jet in missions.keys() {
                    ensure!(v["jets"][jet].is_object(), "{key}: \"missions\" names {jet}, no jet of the course");
                }
                lessons.push(Lesson {
                    night: kind == Kind::Night || l["night"] == true,
                    title: label(&l["title"], &key)?,
                    line: label(&l["line"], &format!("{key}: \"line\""))?,
                    id,
                    kind,
                    items,
                    emergencies,
                    missions,
                    content,
                });
            }
            ensure!(
                lessons.last().is_some_and(|l| l.kind == Kind::Check)
                    && lessons.iter().filter(|l| l.kind == Kind::Check).count() == 1,
                "{pid}: a phase ends with its one check ride"
            );
            phases.push(Phase {
                title: label(&p["title"], &pid)?,
                own_check_only: p["own_check_only"] == true,
                id: pid,
                lessons,
            });
        }
        for (pid, _) in LESSONS {
            let p = phases.iter().find(|p| p.id == *pid).with_context(|| format!("lessons/{pid}.json: no such phase"))?;
            for id in lesson_file(pid)?.and_then(|f| f["lessons"].as_object().cloned()).unwrap_or_default().keys() {
                ensure!(p.lessons.iter().any(|l| l.id == *id), "lessons/{pid}.json: {id} is no lesson of the phase");
            }
        }
        Ok(Course { jets: v["jets"].as_object().context("\"jets\"")?.clone(), phases, items, emergencies })
    }

    /// A lesson's key: `<phase id>.<lesson id>`.
    pub fn key(&self, phase: usize, lesson: usize) -> String {
        format!("{}.{}", self.phases[phase].id, self.phases[phase].lessons[lesson].id)
    }

    /// The lesson of key `key`: (phase, lesson) indices.
    pub fn find(&self, key: &str) -> Option<(usize, usize)> {
        let (p, l) = key.split_once('.')?;
        let pi = self.phases.iter().position(|x| x.id == p)?;
        Some((pi, self.phases[pi].lessons.iter().position(|x| x.id == l)?))
    }

    /// The lesson the mission `mission` (its readable id) flies in jet `jet`'s course, by key.
    pub fn lesson_of(&self, jet: &str, mission: &str) -> Option<String> {
        self.phases.iter().enumerate().find_map(|(pi, p)| {
            let li = p.lessons.iter().position(|l| l.missions.get(jet).and_then(Value::as_str) == Some(mission))?;
            Some(self.key(pi, li))
        })
    }

    pub fn item(&self, id: &str) -> Option<&Item> {
        self.items.iter().find(|i| i.0 == id).map(|i| &i.1)
    }

    /// A lesson's graded items. A check ride's: every item of this phase's and the earlier phases' lessons, in course
    /// order, without a phase's whose skills appear only in its own check ride (the formation phase).
    pub fn items(&self, phase: usize, lesson: usize) -> Vec<String> {
        let l = &self.phases[phase].lessons[lesson];
        if l.kind != Kind::Check {
            return l.items.clone();
        }
        let mut out: Vec<String> = vec![];
        for (pi, p) in self.phases[..=phase].iter().enumerate() {
            if p.own_check_only && pi != phase {
                continue;
            }
            for i in p.lessons.iter().flat_map(|l| &l.items) {
                if !out.contains(i) {
                    out.push(i.clone());
                }
            }
        }
        out
    }

    pub fn emergency(&self, id: &str) -> Option<&Emergency> {
        self.emergencies.iter().find(|e| e.0 == id).map(|e| &e.1)
    }

    /// The emergencies jet `jet`'s course has taught by phase `phase`'s check ride: those of its lessons and the
    /// earlier phases'.
    pub fn taught(&self, phase: usize, jet: &str) -> Vec<String> {
        let mut out: Vec<String> = vec![];
        for e in self.phases[..=phase].iter().flat_map(|p| &p.lessons).flat_map(|l| &l.emergencies) {
            if !out.contains(e) && self.emergency(e).is_some_and(|x| x.of(jet)) {
                out.push(e.clone());
            }
        }
        out
    }

    /// A check ride's unannounced emergency (training-plan.md §2.5) in jet `jet`: from check ride 2 on, one emergency
    /// already taught, at a random time inside its window after its moment (`Emergency::at`). `seed` makes the pick; None for
    /// a lesson that is no check ride, check ride 1, or nothing taught. (emergency id, its moment, the time after it s)
    pub fn check_ride_emergency(&self, jet: &str, key: &str, seed: u64) -> Option<(String, String, f64)> {
        let (p, l) = self.find(key)?;
        if self.phases[p].lessons[l].kind != Kind::Check || p == 0 {
            return None;
        }
        let taught = self.taught(p, jet);
        let mut r = Mix(seed);
        let id = taught.get((r.next() % taught.len().max(1) as u64) as usize)?;
        let e = self.emergency(id)?;
        let f = (r.next() >> 11) as f64 / (1u64 << 53) as f64;
        let t = e.window_s[0] + f * (e.window_s[1] - e.window_s[0]);
        Some((id.clone(), e.at.clone(), (t * 10.0).round() / 10.0))
    }

    /// The course of jet `jet` for the screens: `jet`, `base`, `instructor`, `phases` (each `id`, `title`, `lessons`:
    /// `key`, `kind`, `night`, `title`, `mission` (the readable id, or null), `items` (`id`, `label`, `standard`),
    /// `emergencies` (`id`, `label`)). None for a jet without a course.
    pub fn to_json(&self, jet: &str) -> Option<Value> {
        let j = self.jets.get(jet)?;
        let phases: Vec<Value> = self
            .phases
            .iter()
            .enumerate()
            .map(|(pi, p)| {
                let lessons: Vec<Value> = p
                    .lessons
                    .iter()
                    .enumerate()
                    .map(|(li, l)| {
                        let items: Vec<Value> = self
                            .items(pi, li)
                            .iter()
                            .filter_map(|id| {
                                let i = self.item(id)?;
                                Some(json!({"id": id, "label": i.label, "standard": i.standard.to_json()}))
                            })
                            .collect();
                        let emergencies: Vec<Value> = l
                            .emergencies
                            .iter()
                            .filter_map(|id| Some((id, self.emergency(id).filter(|e| e.of(jet))?)))
                            .map(|(id, e)| json!({"id": id, "label": e.label}))
                            .collect();
                        json!({
                            "key": self.key(pi, li),
                            "kind": match l.kind { Kind::Day => "day", Kind::Night => "night", Kind::Check => "check" },
                            "night": l.night,
                            "title": l.title,
                            "line": l.line,
                            "mission": l.missions.get(jet).cloned().unwrap_or(Value::Null),
                            "items": items,
                            "emergencies": emergencies,
                            "briefing": for_jet(&l.content["briefing"], jet),
                            "lesson_tab": for_jet(&l.content["lesson_tab"], jet),
                            "calls": for_jet(&l.content["calls"], jet),
                        })
                    })
                    .collect();
                json!({"id": p.id, "title": p.title, "lessons": lessons})
            })
            .collect();
        Some(json!({"jet": jet, "base": j["base"], "instructor": j["instructor"], "phases": phases}))
    }

    /// The logbook of jet `jet`'s course from the pilot's attempts (lesson key, grade id, date), oldest first: per
    /// lesson its `best` grade (the best attempt; the latest of equals) with its `date` and its `attempts`; per phase
    /// `passed` (lessons passed, Marginal included), `lessons` and `next` (the first lesson not passed, or null); the
    /// course's `next` (the first not passed in course order, or null when all are). Attempts of keys outside the
    /// course are left out.
    pub fn logbook(&self, attempts: &[(String, String, String)]) -> Value {
        let mut phases = vec![];
        let mut next = Value::Null;
        for (pi, p) in self.phases.iter().enumerate() {
            let mut lessons = vec![];
            let mut passed = 0;
            let mut first_open = Value::Null;
            for li in 0..p.lessons.len() {
                let key = self.key(pi, li);
                let mine: Vec<_> = attempts.iter().filter(|a| a.0 == key).collect();
                let best = mine.iter().filter_map(|a| Some((LessonGrade::of(&a.1)?, a))).fold(
                    None,
                    |b: Option<(LessonGrade, _)>, x| if b.is_some_and(|b| b.0 > x.0) { b } else { Some(x) },
                );
                let ok = best.is_some_and(|b| b.0.passed());
                if ok {
                    passed += 1;
                } else if first_open.is_null() {
                    first_open = json!(key);
                }
                lessons.push(json!({
                    "key": key,
                    "best": best.map(|b| b.0.id()),
                    "date": best.map(|b| b.1.2.clone()),
                    "attempts": mine.len(),
                }));
            }
            if next.is_null() {
                next = first_open.clone();
            }
            phases.push(json!({
                "id": p.id,
                "passed": passed,
                "lessons": p.lessons.len(),
                "next": first_open,
                "results": lessons,
            }));
        }
        json!({"phases": phases, "next": next})
    }
}

/// splitmix64: a seed's stream of numbers, enough for the check ride's pick.
struct Mix(u64);

impl Mix {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }
}

/// The course data built into the library (`modern-iaf/data/training/course.json`).
pub fn course() -> &'static Course {
    static C: OnceLock<Course> = OnceLock::new();
    C.get_or_init(|| Course::parse(DATA).expect("modern-iaf/data/training/course.json"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Each course emergency the flight can start is a failure the jet has (`failures::from_course`,
    /// `Failure::allowed`, modern-iaf/docs/training.md §15).
    #[test]
    fn course_emergencies_are_flight_failures() {
        use iaf_flight::sixdof::failures::from_course;
        let jets = |jet: &str| match jet {
            "f16d" => iaf_flight::sixdof::jets::by_type("F-16"),
            "f16i" => iaf_flight::sixdof::jets::by_type("F-16I"),
            _ => iaf_flight::sixdof::jets::by_type("F-35I"),
        };
        for (id, e) in &course().emergencies {
            for jet in ["f16d", "f16i", "f35i"].into_iter().filter(|j| e.of(j)) {
                for seed in [0, 1] {
                    let (f, _) =
                        from_course(id, &e.at, e.window_s[0], seed).unwrap_or_else(|| panic!("{id}: no failure"));
                    assert_eq!(f.allowed(jets(jet).unwrap().epu), Ok(()), "{id} on {jet}");
                }
            }
        }
    }

    #[test]
    fn the_course_is_the_plans() {
        let c = course();
        assert_eq!(c.phases.len(), 8);
        let count = |k: Kind| c.phases.iter().flat_map(|p| &p.lessons).filter(|l| l.kind == k).count();
        assert_eq!((count(Kind::Day), count(Kind::Night), count(Kind::Check)), (31, 8, 8));
        let night_checks: Vec<usize> = (0..8).filter(|&p| c.phases[p].lessons.last().unwrap().night).collect();
        assert_eq!(night_checks, [2, 4, 7], "check rides 3, 5 and 8 at night");
        for jet in ["f16d", "f16i", "f35i"] {
            let j = c.to_json(jet).unwrap();
            assert_eq!(j["phases"].as_array().unwrap().len(), 8);
            assert!(j["phases"][1]["lessons"][1]["line"]["he"].is_string(), "each lesson's line for the list");
        }
        assert!(c.to_json("f15").is_none());
        // The plan: the existing missions are not part of the course.
        assert!(c.lesson_of("f16i", "ramon_takeoff").is_none());
    }

    #[test]
    fn check_rides_cover_the_phases_so_far_and_formation_only_its_own() {
        let c = course();
        let (p2, l2) = c.find("pattern.check").unwrap();
        let ride2 = c.items(p2, l2);
        assert!(ride2.contains(&"startup_time".to_string()) && ride2.contains(&"touchdown_distance".to_string()));
        assert!(!ride2.contains(&"steerpoint_miss".to_string()));
        let (p4, l4) = c.find("formation.check").unwrap();
        assert!(c.items(p4, l4).contains(&"formation_position".to_string()));
        let (p5, l5) = c.find("ground_attack.check").unwrap();
        let ride5 = c.items(p5, l5);
        assert!(!ride5.contains(&"formation_position".to_string()) && ride5.contains(&"bomb_miss".to_string()));
    }

    #[test]
    fn grades_against_the_standard() {
        let s = |t: &str| Standard::parse(&serde_json::from_str(t).unwrap()).unwrap();
        let max = s(r#"{"limit": "max", "bands": [3, 8, 15], "unit": "m"}"#);
        let g: Vec<Grade> = [2.0, 3.0, 5.0, 12.0, 16.0].iter().map(|v| max.grade(Some(*v))).collect();
        use Grade::*;
        assert_eq!(g, [AboveAverage, AboveAverage, Average, BelowAverage, Unsatisfactory]);
        assert_eq!(max.grade(None), Unsatisfactory);
        assert_eq!(max.gap(12.0), 4.0);
        let min = s(r#"{"limit": "min", "bands": [200, 100, 50], "unit": "ft"}"#);
        assert_eq!(
            [250.0, 150.0, 60.0, 40.0].map(|v| min.grade(Some(v))),
            [AboveAverage, Average, BelowAverage, Unsatisfactory]
        );
        let tol = s(r#"{"limit": "tol", "target": 13, "bands": [0.5, 1, 2], "unit": "deg"}"#);
        assert_eq!(
            [13.2, 12.2, 14.5, 10.0].map(|v| tol.grade(Some(v))),
            [AboveAverage, Average, BelowAverage, Unsatisfactory]
        );
        assert_eq!(tol.gap(14.5), 1.5);
        let heading = s(r#"{"limit": "tol", "target": 359, "bands": [5, 10, 20], "unit": "deg"}"#);
        assert_eq!((heading.gap(3.0), heading.grade(Some(3.0))), (4.0, AboveAverage));
        assert!(Standard::parse(&json!({"limit": "max", "bands": [3, 1, 2], "unit": "m"})).is_err());
        assert!(Standard::parse(&json!({"limit": "tol", "bands": [1, 2, 3], "unit": "m"})).is_err());
    }

    #[test]
    fn a_lesson_is_pass_marginal_or_unsatisfactory() {
        use Grade::*;
        assert_eq!(lesson_grade(true, &[AboveAverage, Average]), LessonGrade::Pass);
        assert_eq!(lesson_grade(true, &[Average, BelowAverage]), LessonGrade::Marginal);
        assert_eq!(lesson_grade(true, &[BelowAverage, Unsatisfactory]), LessonGrade::Unsatisfactory);
        assert_eq!(lesson_grade(false, &[AboveAverage]), LessonGrade::Unsatisfactory, "a crash or a fail rule");
        assert!(LessonGrade::Marginal.passed() && !LessonGrade::Unsatisfactory.passed());
    }

    #[test]
    fn the_logbook_keeps_the_best_attempt_and_names_the_next_lesson() {
        let c = course();
        let a = |k: &str, g: &str, d: &str| (k.to_string(), g.to_string(), d.to_string());
        let log = c.logbook(&[
            a("ground.cockpit", "unsat", "2026-11-28T10:00:00"),
            a("ground.cockpit", "marginal", "2026-11-28T11:00:00"),
            a("ground.cockpit", "unsat", "2026-11-28T12:00:00"),
            a("ground.taxi", "pass", "2026-11-28T13:00:00"),
            a("pattern.overhead", "pass", "2026-11-28T14:00:00"),
            a("nowhere.lesson", "pass", "2026-11-28T15:00:00"),
        ]);
        let g = &log["phases"][0];
        assert_eq!(g["results"][0]["best"], "marginal");
        assert_eq!(g["results"][0]["date"], "2026-11-28T11:00:00");
        assert_eq!(g["results"][0]["attempts"], 3);
        assert_eq!((g["passed"].as_i64(), g["lessons"].as_i64()), (Some(2), Some(5)));
        assert_eq!(g["next"], "ground.engine", "everything is open: the first lesson not passed");
        assert_eq!(log["next"], "ground.engine");
        assert_eq!(log["phases"][1]["next"], "pattern.first_flight");
        assert_eq!(c.logbook(&[])["next"], "ground.cockpit");
    }

    #[test]
    fn a_check_ride_from_the_second_gets_one_taught_emergency() {
        let c = course();
        assert!(c.check_ride_emergency("f16i", "ground.check", 1).is_none(), "check ride 1 has none");
        assert!(c.check_ride_emergency("f16i", "pattern.overhead", 1).is_none(), "not a check ride");
        let mut seen = vec![];
        for seed in 0..200 {
            let (id, at, t) = c.check_ride_emergency("f16i", "pattern.check", seed).unwrap();
            assert!(["engine_fire_roll", "engine_fire", "flameout"].contains(&id.as_str()), "{id}: taught by phase 2");
            let e = &c.emergencies.iter().find(|e| e.0 == id).unwrap().1;
            assert!(at == e.at && t >= e.window_s[0] && t <= e.window_s[1]);
            if !seen.contains(&id) {
                seen.push(id);
            }
        }
        assert_eq!(seen.len(), 3, "every taught one can come");
        assert_eq!(
            c.check_ride_emergency("f16i", "threats.check", 7),
            c.check_ride_emergency("f16i", "threats.check", 7)
        );
        let adir: Vec<String> =
            (0..200).filter_map(|s| c.check_ride_emergency("f35i", "threats.check", s)).map(|e| e.0).collect();
        assert!(adir.iter().any(|e| e == "gear_fault") && !adir.iter().any(|e| e == "hydraulic"), "the F-35I's own");
        assert!(!adir.iter().any(|e| e == "epu") && adir.iter().any(|e| e == "flight_controls"), "no EPU in the F-35I");
        let later: Vec<String> =
            (0..200).filter_map(|s| c.check_ride_emergency("f16i", "threats.check", s)).map(|e| e.0).collect();
        assert!(later.iter().any(|e| e == "hydraulic"), "phase 3's are taught by then");
    }
}
