//! The mission editor's scenario rules (docs/mission-editor.md §14): "when X then Y", written as the original's own
//! event data so the runtime runs them unchanged (docs/mission-runtime.md §2–§4):
//! - an event (CDMEEventItem) with its audio and its actions [entity, motion index, trigger index];
//! - the entity event slots that fire it (0 hit, 1 destroyed, 4 left, 5 reached, with the watched entity 0xac and
//!   the radius in slot 4's 0x348);
//! - script entries (CDMEScriptObj) the actions jump to; a wait is a Wait entry (trigger op 15) on a "holder" sensor
//!   whose chain fires the later parts through trigger op 6 (fire event, `FUN_005c4340`: the same field +0x28 as
//!   op 7's audio, so 0x8ac);
//! - sensors (bdb object 130) as the originals use them: a holder, an area (a reached / left check around a point),
//!   a goal (role 1) or a lose token (role 0) that an Explode (op 5) destroys.
//!
//! `rules` reads every event back into rules; one that fits the blocks is editable, the others are listed as the
//! original's and kept. `set_rules` rewrites only the rules that changed, so the originals' data stays as it was.

use std::collections::{BTreeMap, HashMap, HashSet};

use serde_json::{Value, json};

use crate::mission_edit::{insert, int, items, num, real, remove_entity};

const SENSOR: i64 = 130;
/// The editor's label (0x316, never read by the runtime) on the sensors it makes.
const TAG_HOLDER: &str = "scenario rule";
const TAG_AREA: &str = "scenario area";
const TAG_TOKEN: &str = "scenario goal";
/// The name of the Hover a route waits on (motion entry 1) until a rule starts it.
const HOLD_NAME: &str = "WAIT FOR RULE";
const LISTS: [&str; 2] = ["scripts0", "scripts1"];
const COUNTERS: [&str; 2] = ["0xec", "0xf0"];

fn valid(i: i64) -> bool {
    i != 0 && i != -1
}

fn entity(m: &Value, id: i64) -> Option<&Value> {
    m["entities"]["items"].as_array()?.iter().find(|e| real(e) && int(&e["0x1e"]) == id)
}

fn entity_mut(m: &mut Value, id: i64) -> Option<&mut Value> {
    items(m, "entities").iter_mut().find(|e| real(e) && int(&e["0x1e"]) == id)
}

fn event(m: &Value, id: i64) -> Option<&Value> {
    m["events"]["items"].as_array()?.iter().find(|e| real(e) && int(&e["0x1e"]) == id)
}

fn entries(e: &Value, li: usize) -> &[Value] {
    e[LISTS[li]]["items"].as_array().map_or(&[], Vec::as_slice)
}

fn entry(e: &Value, li: usize, idx: i64) -> Option<&Value> {
    entries(e, li).iter().find(|s| int(&s["raw10"]) == idx)
}

fn mission_ctl(e: &Value) -> bool {
    int(&e["0x320"]).max(0) & 1 == 1
}

fn is_sensor(e: &Value) -> bool {
    int(&e["0x2c6"]) == SENSOR
}

fn slot(e: &Value, i: usize) -> i64 {
    int(&e["slots"][i]["0x33e"])
}

/// A unit's name for the summaries: its flight's name for a flight leader.
fn name_of(m: &Value, id: i64) -> String {
    for f in m["formations"]["items"].as_array().into_iter().flatten().filter(|f| real(f)) {
        if int(&f["members"][0]["0x41a"]) == id {
            return f["0x3e8"].as_str().unwrap_or("?").to_string();
        }
    }
    entity(m, id).and_then(|e| e["0x2bc"].as_str()).map_or_else(|| format!("unit {id} (missing)"), String::from)
}

fn member_of_flight(m: &Value, id: i64) -> bool {
    in_flights(m, id, 0..=i64::MAX)
}

/// The player may fly any of flights 1..4 (Alpha..Delta); the runtime never arms a player's radius check.
fn may_be_player(m: &Value, id: i64) -> bool {
    in_flights(m, id, 1..=4)
}

fn in_flights(m: &Value, id: i64, numbers: std::ops::RangeInclusive<i64>) -> bool {
    let fs = m["formations"]["items"].as_array().into_iter().flatten();
    fs.filter(|f| real(f) && numbers.contains(&int(&f["0x3f2"])))
        .any(|f| f["members"].as_array().into_iter().flatten().any(|mm| int(&mm["0x41a"]) == id))
}

/// A unit with a route or in a flight: an area around it must move with it.
fn moves(m: &Value, e: &Value) -> bool {
    !entries(e, 0).is_empty() || member_of_flight(m, int(&e["0x1e"]))
}

// --- reading ---------------------------------------------------------------------------------------------------

/// What one rule's walk through the data found.
#[derive(Default)]
struct Walk {
    blocks: Vec<(f64, Value)>,
    /// (entity, list, index) of every script entry the rule runs.
    entries: Vec<(i64, usize, i64)>,
    events: Vec<i64>,
    why: Option<String>,
}

impl Walk {
    fn fail(&mut self, why: String) {
        self.why.get_or_insert(why);
    }
}

fn walk_event(m: &Value, id: i64, t: f64, w: &mut Walk) {
    if w.events.contains(&id) {
        return w.fail("an event fires itself again".into());
    }
    let Some(ev) = event(m, id) else { return w.fail(format!("event {id} is missing")) };
    w.events.push(id);
    if ev["conds"].as_array().into_iter().flatten().any(|c| (1..10000).contains(&int(&c["0x3de"]))) {
        w.fail("it uses a counter".into());
    }
    if valid(int(&ev["0x3ac"])) {
        w.blocks.push((t, json!({"kind": "message", "audio": int(&ev["0x3ac"])})));
    }
    for a in ev["list"].as_array().into_iter().flatten() {
        let (u, s0, s1) = (int(&a[0]), int(&a[1]), int(&a[2]));
        let Some(e) = entity(m, u) else { continue };
        if valid(s0) {
            match entry(e, 0, s0) {
                Some(s) if int(&s["0x83e"]) == 16 => {
                    w.blocks.push((t, json!({"kind": "route", "unit": u, "entry": s0})));
                }
                Some(s) => w.fail(format!("{}: motion {}", name_of(m, u), s["0x8a2"].as_str().unwrap_or("?"))),
                None => {}
            }
        }
        if valid(s1) {
            walk_chain(m, u, s1, t, w);
        }
    }
}

/// A trigger chain of unit `u` from entry `idx` at time `t` (s): each entry holds the list for its 0x87a seconds.
fn walk_chain(m: &Value, u: i64, mut idx: i64, mut t: f64, w: &mut Walk) {
    let Some(e) = entity(m, u) else { return };
    while let Some(s) = entry(e, 1, idx) {
        if w.entries.contains(&(u, 1, idx)) {
            return w.fail("a script loops".into());
        }
        w.entries.push((u, 1, idx));
        let arg = int(&s["0x8ac"]);
        let mut block = |b: Value| w.blocks.push((t, b));
        match int(&s["0x83e"]) {
            15 => {}
            6 => walk_event(m, arg, t, w),
            7 if valid(arg) => block(json!({"kind": "message", "audio": arg})),
            7 => {}
            13 => block(json!({"kind": "show", "unit": u})),
            14 => block(json!({"kind": "hide", "unit": u})),
            11 => block(json!({"kind": "shield_on", "unit": u})),
            12 => block(json!({"kind": "shield_off", "unit": u})),
            21 => block(json!({"kind": "combat_on", "unit": u})),
            22 => block(json!({"kind": "combat_off", "unit": u})),
            5 if is_sensor(e) && int(&e["0x32a"]) == 1 => block(json!({"kind": "goal", "unit": u})),
            5 if is_sensor(e) && int(&e["0x32a"]) == 0 => block(json!({"kind": "fail", "unit": u})),
            5 => block(json!({"kind": "explode", "unit": u})),
            2 => block(json!({"kind": "fire_at", "unit": u, "target": arg, "hit": num(&s["0x852"]) != 0.0})),
            1 => {
                let x = s["0x848"].as_str().and_then(|x| x.trim().parse::<f64>().ok()).unwrap_or(0.0);
                block(json!({"kind": "fire_point", "unit": u, "at": [x, num(&s["0x852"]), num(&s["0x85c"])]}));
            }
            _ => w.fail(format!("{}: {}", name_of(m, u), s["0x8a2"].as_str().unwrap_or("?"))),
        }
        t += num(&s["0x87a"]).max(0.0);
        idx = int(&s["0x898"]);
    }
}

const KINDS: [&str; 13] = [
    "message",
    "route",
    "show",
    "hide",
    "shield_on",
    "shield_off",
    "combat_on",
    "combat_off",
    "fire_at",
    "fire_point",
    "explode",
    "goal",
    "fail",
];

/// The order of blocks at the same time (they run together): by kind, then unit; messages keep theirs.
fn order(b: &Value) -> (usize, i64) {
    let k = KINDS.iter().position(|k| b["kind"] == *k).unwrap_or(KINDS.len());
    (k, if k == 0 { 0 } else { int(&b["unit"]) })
}

/// The blocks in time order, a wait between different times.
fn then_of(w: &Walk) -> Vec<Value> {
    timed(&w.blocks)
}

fn timed(blocks: &[(f64, Value)]) -> Vec<Value> {
    let mut b: Vec<&(f64, Value)> = blocks.iter().collect();
    b.sort_by(|x, y| x.0.total_cmp(&y.0).then_with(|| order(&x.1).cmp(&order(&y.1))));
    let (mut out, mut at) = (vec![], 0.0);
    for (t, v) in b {
        if *t > at {
            out.push(json!({"kind": "wait", "seconds": (t - at).round()}));
            at = *t;
        }
        out.push(v.clone());
    }
    out
}

/// The WHEN of event `id` from the slots that fire it; Err with the reason when it is not one block.
fn when_of(m: &Value, id: i64) -> Result<Value, String> {
    let mut by: BTreeMap<usize, Vec<i64>> = BTreeMap::new();
    for e in m["entities"]["items"].as_array().into_iter().flatten().filter(|e| real(e)) {
        for k in [0, 1, 4, 5] {
            if slot(e, k) == id {
                by.entry(k).or_default().push(int(&e["0x1e"]));
            }
        }
    }
    let kinds: Vec<usize> = by.keys().copied().collect();
    match kinds.as_slice() {
        [] => Err("nothing fires it".into()),
        [0] => Ok(json!({"kind": "damaged", "units": by[&0]})),
        [1] => Ok(json!({"kind": "destroyed", "units": by[&1]})),
        [k @ (4 | 5)] if by[k].len() == 1 => {
            let o = entity(m, by[k][0]).unwrap();
            let radius = num(&o["slots"][4]["0x348"]);
            let mut w = json!({"kind": if *k == 5 { "enters" } else { "leaves" }, "who": int(&o["0xac"]),
                "radius": radius});
            if is_sensor(o) {
                // An area: the unit standing where the sensor stands is its centre.
                let (x, y) = (num(&o["0x2e4"]), num(&o["0x2ee"]));
                let at = m["entities"]["items"].as_array().into_iter().flatten().find(|c| {
                    real(c) && !is_sensor(c) && num(&c["0x2e4"]) == x && num(&c["0x2ee"]) == y && !moves(m, c)
                });
                match at {
                    Some(c) => w["center"] = json!(int(&c["0x1e"])),
                    None => w["at"] = json!([x, y, num(&o["0x2f8"])]),
                }
            } else {
                w["center"] = json!(int(&o["0x1e"]));
            }
            if !mission_ctl(o) {
                return Err("its radius check is never armed (the unit is brain-controlled)".into());
            }
            Ok(w)
        }
        _ => Err("several kinds of trigger fire it".into()),
    }
}

/// One rule as read: its JSON and what it owns.
struct Read {
    rule: Value,
    walk: Walk,
}

fn read_all(m: &Value) -> Vec<Read> {
    let evs: Vec<&Value> = m["events"]["items"].as_array().into_iter().flatten().filter(|e| real(e)).collect();
    // Events trigger op 6 fires, and the start rules' holders.
    let mut fired: HashSet<i64> = HashSet::new();
    let mut holders: HashMap<i64, i64> = HashMap::new(); // first event -> holder
    for e in m["entities"]["items"].as_array().into_iter().flatten().filter(|e| real(e)) {
        for s in entries(e, 1).iter().filter(|s| int(&s["0x83e"]) == 6) {
            fired.insert(int(&s["0x8ac"]));
        }
        if is_sensor(e) && e["0x316"].as_str() == Some(TAG_HOLDER) && mission_ctl(e) {
            let mut idx = 1;
            while let Some(s) = entry(e, 1, idx) {
                if int(&s["0x83e"]) == 6 {
                    holders.insert(int(&s["0x8ac"]), int(&e["0x1e"]));
                    break;
                }
                idx = int(&s["0x898"]);
            }
        }
    }
    let mut out = vec![];
    for ev in evs {
        let id = int(&ev["0x1e"]);
        let mut walk = Walk::default();
        let when = if let Some(&h) = holders.get(&id) {
            walk_chain(m, h, 1, 0.0, &mut walk);
            Ok(json!({"kind": "start"}))
        } else if fired.contains(&id) {
            continue; // a later part of a rule
        } else {
            walk_event(m, id, 0.0, &mut walk);
            when_of(m, id)
        };
        let when = when.unwrap_or_else(|why| {
            walk.fail(why.clone());
            json!({"kind": "other", "text": why})
        });
        let rule = json!({
            "key": id, "name": ev["0x384"].as_str().unwrap_or(""), "times": int(&ev["0x398"]),
            "debrief": int(&ev["0x38e"]), "text": ev["0x3a2"].as_str().unwrap_or(""),
            "when": when, "then": then_of(&walk),
        });
        out.push(Read { rule, walk });
    }
    // An entry or a later event two rules share, or a script that also runs from the start (entry 1 of a
    // mission-controlled unit), cannot be rewritten for one of them alone.
    let mut owners: HashMap<(i64, usize, i64), usize> = HashMap::new();
    let mut shared: HashSet<usize> = HashSet::new();
    for (r, rd) in out.iter().enumerate() {
        for k in &rd.walk.entries {
            if let Some(&o) = owners.get(k).filter(|&&o| o != r) {
                shared.extend([o, r]);
            }
            owners.insert(*k, r);
        }
    }
    for e in m["entities"]["items"].as_array().into_iter().flatten().filter(|e| real(e) && mission_ctl(e)) {
        let u = int(&e["0x1e"]);
        if holders.values().any(|&h| h == u) {
            continue;
        }
        let (mut idx, mut seen) = (1, HashSet::new());
        while let Some(s) = entry(e, 1, idx).filter(|_| seen.insert(idx)) {
            if let Some(&o) = owners.get(&(u, 1, idx)) {
                shared.insert(o);
            }
            idx = int(&s["0x898"]);
        }
    }
    for (r, rd) in out.iter_mut().enumerate() {
        if shared.contains(&r) {
            rd.walk.fail("it shares its scripts with another rule or the mission start".into());
        }
        let why = rd.walk.why.clone();
        rd.rule["editable"] = json!(why.is_none());
        if let Some(why) = why {
            rd.rule["why"] = json!(why);
        }
    }
    out
}

/// The rules of `mission` (JSON array): {key (the event id), editable, why?, name, times (0x398), debrief (0x38e),
/// text (0x3a2), when, then, summary}. `bdb` (the converted default6_1.bdb) names the messages.
pub fn rules(mission: &Value, bdb: &Value) -> Value {
    let mut out: Vec<Value> = read_all(mission).into_iter().map(|r| r.rule).collect();
    for r in &mut out {
        r["summary"] = json!(summary(mission, bdb, r));
    }
    json!(out)
}

/// The bdb's audio records for the message block: [{id, name, text}].
pub fn audio_list(bdb: &Value) -> Value {
    let a = bdb["audio"]["items"].as_array().into_iter().flatten().filter(|a| real(a));
    json!(a.map(|a| json!({"id": int(&a["0x1e"]), "name": a["0x12c"], "text": a["0x140"]})).collect::<Vec<_>>())
}

/// A rule in plain English: "When SA-6 is destroyed → Convoy starts its route, play "Bandits"".
pub fn summary(m: &Value, bdb: &Value, r: &Value) -> String {
    let n = |v: &Value| name_of(m, int(v));
    let w = &r["when"];
    let names = || w["units"].as_array().into_iter().flatten().map(n).collect::<Vec<_>>().join(" or ");
    let center = || if w["center"].is_null() { "a point".to_string() } else { n(&w["center"]) };
    let km = |r: f64| if r >= 1000.0 { format!("{} km", (r / 100.0).round() / 10.0) } else { format!("{r} m") };
    let when = match w["kind"].as_str().unwrap_or("") {
        "destroyed" => format!("When {} is destroyed", names()),
        "damaged" => format!("When {} is badly hit", names()),
        "enters" => format!("When {} comes within {} of {}", n(&w["who"]), km(num(&w["radius"])), center()),
        "leaves" => format!("When {} leaves {} of {}", n(&w["who"]), km(num(&w["radius"])), center()),
        "start" => "At the start".into(),
        _ => format!("Original rule ({})", w["text"].as_str().unwrap_or("")),
    };
    let audio = |id: i64| {
        let a = bdb["audio"]["items"].as_array().into_iter().flatten().find(|a| int(&a["0x1e"]) == id);
        let t = a.and_then(|a| a["0x140"].as_str().filter(|s| !s.is_empty()).or(a["0x12c"].as_str()));
        let t = t.map_or_else(|| format!("message {id}"), String::from);
        if t.chars().count() > 40 { format!("{}…", t.chars().take(40).collect::<String>()) } else { t }
    };
    let then: Vec<String> = r["then"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|b| {
            let u = n(&b["unit"]);
            match b["kind"].as_str().unwrap_or("") {
                "wait" => format!("after {} s", num(&b["seconds"])),
                "message" => format!("play \"{}\"", audio(int(&b["audio"]))),
                "route" => format!("{u} starts its route"),
                "show" => format!("{u} appears"),
                "hide" => format!("{u} disappears"),
                "shield_on" => format!("{u} cannot be hurt"),
                "shield_off" => format!("{u} can be hurt again"),
                "combat_on" => format!("{u} may fight"),
                "combat_off" => format!("{u} holds fire"),
                "explode" => format!("{u} explodes"),
                "goal" => "a goal is done".into(),
                "fail" => "the mission fails".into(),
                "fire_at" => format!("{u} fires at {}", n(&b["target"])),
                "fire_point" => format!("{u} fires at a point"),
                k => k.to_string(),
            }
        })
        .collect();
    format!("{when} → {}", if then.is_empty() { "nothing".into() } else { then.join(", ") })
}

// --- writing ---------------------------------------------------------------------------------------------------

/// Renumbers list `li` of entity `id` by `map` (old index → new, absent = removed): the entries, their next links and
/// every event action into the list.
fn renumber(m: &mut Value, id: i64, li: usize, map: &HashMap<i64, i64>) {
    let to = |i: i64| if valid(i) { map.get(&i).copied().unwrap_or(-1) } else { i };
    if let Some(e) = entity_mut(m, id) {
        let list = e[LISTS[li]]["items"].as_array_mut().unwrap();
        list.retain(|s| map.contains_key(&int(&s["raw10"])));
        for s in list.iter_mut() {
            s["raw10"] = json!(to(int(&s["raw10"])));
            let next = to(int(&s["0x898"]));
            s["0x898"] = json!(next);
            if !valid(next) {
                s["0x88e"] = json!("N.A");
            }
        }
        list.sort_by_key(|s| int(&s["raw10"]));
        set_count(e, li);
    }
    for ev in items(m, "events") {
        if let Some(list) = ev["list"].as_array_mut() {
            for a in list.iter_mut().filter(|a| int(&a[0]) == id) {
                a[1 + li] = json!(to(int(&a[1 + li])));
            }
            list.retain(|a| valid(int(&a[1])) || valid(int(&a[2])));
        }
    }
}

/// The editor's entry count (0xec / 0xf0), written only for a list with entries (formats/mis.md).
fn set_count(e: &mut Value, li: usize) {
    let n = entries(e, li).len();
    match e.as_object_mut() {
        Some(o) if n == 0 => {
            o.remove(COUNTERS[li]);
        }
        Some(o) => {
            o.insert(COUNTERS[li].into(), json!(n));
        }
        None => {}
    }
}

/// Removes the entries `drop` from list `li` of entity `id`, renumbering the rest.
fn remove_entries(m: &mut Value, id: i64, li: usize, drop: &HashSet<i64>) {
    let Some(e) = entity(m, id) else { return };
    let mut keep: Vec<i64> = entries(e, li).iter().map(|s| int(&s["raw10"])).filter(|i| !drop.contains(i)).collect();
    keep.sort();
    let map = keep.iter().enumerate().map(|(n, &i)| (i, n as i64 + 1)).collect();
    renumber(m, id, li, &map);
}

/// Appends `chain` (entries without indices) to list `li` of entity `id`, linked in order; the first's index. An empty
/// trigger list (but the editor's own sensors') first gets a Wait at entry 1, which ends the list at once: entry 1 runs at the start when the
/// unit is (or later becomes, with a route) mission-controlled.
fn append(m: &mut Value, id: i64, li: usize, chain: Vec<Value>) -> i64 {
    let e = entity_mut(m, id).unwrap();
    if !e[LISTS[li]]["items"].is_array() {
        e[LISTS[li]] = json!({"_class": "CObArray", "items": []});
    }
    let ours = [TAG_HOLDER, TAG_AREA, TAG_TOKEN].iter().any(|t| e["0x316"] == *t);
    let hold = li == 1 && !ours && e[LISTS[li]]["items"].as_array().unwrap().is_empty();
    let list = e[LISTS[li]]["items"].as_array_mut().unwrap();
    if hold {
        let mut h = op(15, 0, -1);
        (h["0x834"], h["raw10"], h["0x1e"], h["0x898"], h["0x88e"]) =
            (json!(HOLD_NAME), json!(1), json!(1), json!(-1), json!("N.A"));
        list.push(h);
    }
    let first = list.iter().map(|s| int(&s["raw10"])).max().unwrap_or(0) + 1;
    let sid = list.iter().map(|s| int(&s["0x1e"])).max().unwrap_or(0) + 1;
    let n = chain.len() as i64;
    let names: Vec<Value> = chain.iter().map(|s| s["0x834"].clone()).collect();
    for (k, mut s) in chain.into_iter().enumerate() {
        let k = k as i64;
        s["raw10"] = json!(first + k);
        s["0x1e"] = json!(sid + k);
        let last = k + 1 == n;
        s["0x898"] = json!(if last { -1 } else { first + k + 1 });
        s["0x88e"] = if last { json!("N.A") } else { names[k as usize + 1].clone() };
        list.push(s);
    }
    set_count(e, li);
    first
}

/// A trigger-list entry (CDMEScriptObj) as the originals write it.
fn op(code: i64, seconds: i64, arg: i64) -> Value {
    let name = match code {
        1 => "Launch at location",
        2 => "Launch at target",
        5 => "Explode",
        6 => "Fire event",
        7 => "Play message",
        11 => "Shield on",
        12 => "Shield off",
        13 => "Visible on",
        14 => "Visible off",
        15 => "Wait",
        21 => "Enable combat",
        _ => "Disable combat",
    };
    json!({
        "0x14": 1, "0x834": name.to_uppercase(), "0x83e": code, "0x848": "", "0x852": 0.0, "0x85c": 0.0,
        "0x866": 0.0, "0x870": 0.0, "0x87a": seconds, "0x884": -1, "0x8a2": name, "0x8ac": arg,
        "_class": "CDMEScriptObj",
    })
}

/// A new sensor (bdb object 130, invisible) at `at`: the editor's holders, areas and tokens.
fn new_sensor(m: &mut Value, name: &str, tag: &str, role: i64, ctl: bool, at: [f64; 3]) -> i64 {
    let empty = json!({"0x334": "", "0x33e": 0, "0x348": 0, "0x352": 0});
    let row = json!({
        "0x2bc": name, "0x2c6": SENSOR, "0x2d0": 1, "0x2da": -1, "0x2e4": at[0], "0x2ee": at[1], "0x2f8": at[2],
        "0x302": 0, "0x30c": 0, "0x316": tag, "0x320": i64::from(ctl), "0x32a": role, "0x35c": 0, "0xac": -1,
        "_class": "CDMEEntitiesItem",
        "armament": {"_class": "CArmament", "hardpoints": vec![0; 24]},
        "scripts0": {"_class": "CObArray", "items": []}, "scripts1": {"_class": "CObArray", "items": []},
        "slots": vec![empty; 7],
    });
    insert(items(m, "entities"), row)
}

fn new_event(m: &mut Value, name: &str) -> i64 {
    let cond = json!({"0x3b6": "", "0x3c0": "", "0x3ca": 0, "0x3d4": 0, "0x3de": -1});
    let row = json!({
        "0x384": name, "0x38e": -1, "0x398": 1, "0x3a2": "", "0x3ac": -1, "_class": "CDMEEventItem",
        "conds": [cond, cond, cond], "list": [],
    });
    insert(items(m, "events"), row)
}

/// The events whose actions jump unit `id`'s motion list (a route a rule starts).
pub fn route_jumps(m: &Value, id: i64) -> Vec<i64> {
    let evs = m["events"]["items"].as_array().into_iter().flatten().filter(|e| real(e));
    evs.filter(|ev| ev["list"].as_array().into_iter().flatten().any(|a| int(&a[0]) == id && valid(int(&a[1]))))
        .map(|ev| int(&ev["0x1e"]))
        .collect()
}

/// Unit `id` loses its route: the events' jumps into its motion list go.
pub fn drop_route_jumps(mut m: Value, id: i64) -> Value {
    let Some(e) = entity(&m, id) else { return m };
    let map = entries(e, 0).iter().map(|s| int(&s["raw10"])).map(|i| (i, i)).collect();
    for ev in items(&mut m, "events") {
        for a in ev["list"].as_array_mut().into_iter().flatten().filter(|a| int(&a[0]) == id) {
            a[1] = json!(-1);
        }
    }
    renumber(&mut m, id, 0, &map); // drops the records left with nothing to do
    m
}

/// Unit `id`'s route waits for the rules `events` (route_jumps): a mission-controlled unit whose motion list starts
/// with the Path holds on a Hover at entry 1 (the originals' pattern: "Wait" / "hov", then Path at 2), and each
/// event's action jumps to the Path. Returns the Path's index, None without a route.
fn route_waits(m: &mut Value, id: i64, events: &[i64]) -> Option<i64> {
    let e = entity(m, id)?;
    let first = entry(e, 0, 1);
    if mission_ctl(e) && first.is_some_and(|s| int(&s["0x83e"]) == 16) {
        let map = entries(e, 0).iter().map(|s| int(&s["raw10"])).map(|i| (i, i + 1)).collect();
        renumber(m, id, 0, &map);
        let list = entity_mut(m, id)?["scripts0"]["items"].as_array_mut()?;
        let sid = list.iter().map(|s| int(&s["0x1e"])).max().unwrap_or(0) + 1;
        list.insert(
            0,
            json!({
                "0x14": 1, "0x1e": sid, "0x834": HOLD_NAME, "0x83e": 1, "0x848": "", "0x852": 0.0, "0x85c": 0.0,
                "0x866": 0.0, "0x870": 0.0, "0x87a": 0, "0x884": -1, "0x88e": "N.A", "0x898": -1, "0x8a2": "Hover",
                "0x8ac": -1, "_class": "CDMEScriptObj", "raw10": 1,
            }),
        );
        set_count(entity_mut(m, id)?, 0);
    }
    let path = entries(entity(m, id)?, 0).iter().filter(|s| int(&s["0x83e"]) == 16).map(|s| int(&s["raw10"])).min()?;
    for ev in items(m, "events").iter_mut().filter(|ev| real(ev) && events.contains(&int(&ev["0x1e"]))) {
        let list = ev["list"].as_array_mut().unwrap();
        match list.iter_mut().find(|a| int(&a[0]) == id) {
            Some(a) => a[1] = json!(path),
            None => list.push(json!([id, path, -1])),
        }
    }
    Some(path)
}

/// `route_waits` for set_route: the rules `events` start unit `id`'s new route.
pub fn wait_for(mut m: Value, id: i64, events: &[i64]) -> Value {
    route_waits(&mut m, id, events);
    m
}

/// Gives back a route's Hover hold once no rule starts the route any more.
fn release_hold(m: &mut Value, id: i64) {
    let Some(e) = entity(m, id) else { return };
    if entry(e, 0, 1).is_some_and(|s| s["0x834"].as_str() == Some(HOLD_NAME)) && route_jumps(m, id).is_empty() {
        remove_entries(m, id, 0, &HashSet::from([1]));
    }
}

/// Takes rule `r` (as read) out of the mission: its events, the slots that fire them, its script entries, its
/// sensors and route holds.
fn remove_rule(m: &mut Value, r: &Read) {
    let evs: HashSet<i64> = r.walk.events.iter().copied().collect();
    let mut touched: HashSet<i64> = HashSet::new();
    for e in items(m, "entities").iter_mut().filter(|e| real(e)) {
        let mut hit = false;
        for k in [0, 1, 4, 5] {
            if evs.contains(&slot(e, k)) {
                (e["slots"][k]["0x33e"], e["slots"][k]["0x334"]) = (json!(0), json!(""));
                hit = true;
            }
        }
        if hit {
            touched.insert(int(&e["0x1e"]));
            if !valid(slot(e, 4)) && !valid(slot(e, 5)) {
                (e["slots"][4]["0x348"], e["0xac"]) = (json!(0), json!(-1));
            }
        }
    }
    items(m, "events").retain(|ev| !real(ev) || !evs.contains(&int(&ev["0x1e"])));
    let mut by: HashMap<i64, HashSet<i64>> = HashMap::new();
    for &(u, _, i) in &r.walk.entries {
        by.entry(u).or_default().insert(i);
    }
    for (u, drop) in &by {
        remove_entries(m, *u, 1, drop);
        touched.insert(*u);
        if let Some(e) = entity_mut(m, *u)
            && entries(e, 1).len() == 1
            && entries(e, 1)[0]["0x834"].as_str() == Some(HOLD_NAME)
        {
            e["scripts1"]["items"] = json!([]);
            set_count(e, 1);
        }
    }
    for b in r.rule["then"].as_array().into_iter().flatten().filter(|b| b["kind"] == "route") {
        release_hold(m, int(&b["unit"]));
    }
    // A sensor left with nothing to do goes.
    for u in touched {
        let Some(e) = entity(m, u) else { continue };
        let idle = is_sensor(e)
            && (0..2).all(|li| entries(e, li).is_empty())
            && (0..6).all(|k| !valid(slot(e, k)))
            && !m["events"]["items"]
                .as_array()
                .into_iter()
                .flatten()
                .any(|ev| ev["list"].as_array().into_iter().flatten().any(|a| int(&a[0]) == u))
            && !m["entities"]["items"].as_array().into_iter().flatten().any(|o| real(o) && int(&o["0xac"]) == u);
        if idle {
            *m = remove_entity(std::mem::take(m), u);
        }
    }
}

/// The parts of a rule's THEN between its waits: (seconds after the previous part, blocks).
fn segments(then: &[Value]) -> Vec<(i64, Vec<Value>)> {
    let mut out: Vec<(i64, Vec<Value>)> = vec![(0, vec![])];
    for b in then {
        if b["kind"] == "wait" {
            let s = num(&b["seconds"]).round().max(0.0) as i64;
            if out.last().unwrap().1.is_empty() {
                out.last_mut().unwrap().0 += s;
            } else {
                out.push((s, vec![]));
            }
        } else {
            out.last_mut().unwrap().1.push(b.clone());
        }
    }
    if out.len() > 1 && out.last().unwrap().1.is_empty() {
        out.pop(); // a wait at the end does nothing
    }
    out
}

fn free(m: &Value, e: &Value, k: usize) -> bool {
    !valid(slot(e, k)) || event(m, slot(e, k)).is_none()
}

/// Where a reached / left check goes: (owner, watched) or a new area sensor (None, watched) at `at`.
enum Watch {
    Owner(i64, i64),
    Area([f64; 3], i64),
}

/// Checks rule `r` against the mission before anything is written.
fn plan_watch(m: &Value, w: &Value) -> Result<Watch, String> {
    let who = int(&w["who"]);
    let wu = entity(m, who).ok_or("pick the unit or flight that comes near")?;
    if !w["center"].is_null() {
        let c = int(&w["center"]);
        let cu = entity(m, c).ok_or("pick the unit to come near")?;
        if c == who {
            return Err("the unit and the centre are the same".into());
        }
        // The owner's other slot may hold a rule on the same unit and radius: the two share them.
        let (k, other) = if w["kind"] == "enters" { (5, 4) } else { (4, 5) };
        let can_own = |e: &Value, watched: i64| {
            mission_ctl(e)
                && !may_be_player(m, int(&e["0x1e"]))
                && free(m, e, k)
                && (free(m, e, other)
                    || int(&e["0xac"]) == watched && num(&e["slots"][4]["0x348"]) == num(&w["radius"]).round())
        };
        if !moves(m, cu) {
            return Ok(Watch::Area([num(&cu["0x2e4"]), num(&cu["0x2ee"]), num(&cu["0x2f8"])], who));
        }
        if can_own(wu, c) {
            return Ok(Watch::Owner(who, c));
        }
        if can_own(cu, who) {
            return Ok(Watch::Owner(c, who));
        }
        return Err(format!(
            "{} and {} both move: one of them must be a unit on a route with no other area rule",
            name_of(m, who),
            name_of(m, c)
        ));
    }
    let at = w["at"].as_array().ok_or("pick the centre")?;
    Ok(Watch::Area([num(&at[0]), num(&at[1]), at.get(2).map_or(0.0, num)], who))
}

fn check_rule(m: &Value, r: &Value) -> Result<(), String> {
    let w = &r["when"];
    match w["kind"].as_str().unwrap_or("") {
        k @ ("destroyed" | "damaged") => {
            let units = w["units"].as_array().filter(|u| !u.is_empty()).ok_or("pick the unit")?;
            let s = if k == "destroyed" { 1 } else { 0 };
            for u in units {
                let e = entity(m, int(u)).ok_or("a unit of the rule is missing")?;
                if !free(m, e, s) {
                    return Err(format!("{} already has a {k} rule", name_of(m, int(u))));
                }
            }
        }
        "enters" | "leaves" => {
            if num(&w["radius"]) < 1.0 {
                return Err("the distance must be at least 1 m".into());
            }
            plan_watch(m, w)?;
        }
        "start" => {}
        _ => return Err("pick a WHEN block".into()),
    }
    for b in r["then"].as_array().into_iter().flatten() {
        let k = b["kind"].as_str().unwrap_or("");
        if !["wait", "message", "goal", "fail"].contains(&k) {
            let u = entity(m, int(&b["unit"])).ok_or_else(|| format!("{k}: pick the unit"))?;
            if k == "route" && !entries(u, 0).iter().any(|s| int(&s["0x83e"]) == 16) {
                return Err(format!("{} has no route: give it one on the Units tab", name_of(m, int(&b["unit"]))));
            }
        }
        if k == "fire_at" && entity(m, int(&b["target"])).is_none() {
            return Err("fire at: pick the target".into());
        }
        if k == "message" && !valid(int(&b["audio"])) {
            return Err("message: pick the message".into());
        }
    }
    Ok(())
}

/// Writes rule `r` (number `n` from 1, for its default name); returns its first event's id.
fn write_rule(m: &mut Value, r: &Value, n: usize) -> i64 {
    let name = r["name"].as_str().filter(|s| !s.is_empty()).map_or_else(|| format!("Rule {n}"), String::from);
    let start = r["when"]["kind"] == "start";
    let segs = segments(r["then"].as_array().map_or(&[], Vec::as_slice));
    // The first event: the rule itself.
    let e0 = new_event(m, &name);
    if let Some(ev) = items(m, "events").iter_mut().find(|ev| real(ev) && int(&ev["0x1e"]) == e0) {
        if r["times"].as_i64().or(r["times"].as_f64().map(|f| f as i64)).is_some() {
            ev["0x398"] = json!(int(&r["times"]));
        }
        if r["debrief"].is_number() {
            ev["0x38e"] = json!(int(&r["debrief"]));
        }
        ev["0x3a2"] = json!(r["text"].as_str().unwrap_or(""));
    }
    // A segment goes into an event: the first message its audio, the others (and every message of a part a holder
    // runs) trigger op 7 in the holder's chain.
    let carried = !start && segs[0].0 == 0;
    let mut chain: Vec<Value> = vec![];
    let fill = |m: &mut Value, ev: i64, blocks: &[Value], chain: &mut Vec<Value>| {
        let mut msgs = blocks.iter().filter(|b| b["kind"] == "message").map(|b| int(&b["audio"]));
        let audio = msgs.next().unwrap_or(-1);
        chain.extend(msgs.map(|a| op(7, 0, a)));
        let mut per: Vec<(i64, i64, Vec<Value>)> = vec![]; // unit, motion index, trigger chain
        let unit = |per: &mut Vec<(i64, i64, Vec<Value>)>, u: i64| -> usize {
            per.iter().position(|p| p.0 == u).unwrap_or_else(|| {
                per.push((u, -1, vec![]));
                per.len() - 1
            })
        };
        for b in blocks {
            let u = int(&b["unit"]);
            let code = match b["kind"].as_str().unwrap_or("") {
                "route" => {
                    let k = unit(&mut per, u);
                    per[k].1 = route_waits(m, u, &[]).unwrap_or(-1);
                    continue;
                }
                "goal" | "fail" => {
                    let goal = b["kind"] == "goal";
                    let t = new_sensor(
                        m,
                        &format!("{}: {name}", if goal { "Goal" } else { "Lose" }),
                        TAG_TOKEN,
                        i64::from(goal),
                        false,
                        [-1.0, -1.0, 0.0],
                    );
                    let k = unit(&mut per, t);
                    per[k].2.push(op(5, 0, -1));
                    continue;
                }
                "show" => 13,
                "hide" => 14,
                "shield_on" => 11,
                "shield_off" => 12,
                "combat_on" => 21,
                "combat_off" => 22,
                "explode" => 5,
                "fire_at" => {
                    let mut s = op(2, 0, int(&b["target"]));
                    s["0x848"] = json!(name_of(m, int(&b["target"])));
                    s["0x852"] = json!(if b["hit"].as_bool().unwrap_or(true) { 1.0 } else { 0.0 });
                    let k = unit(&mut per, u);
                    per[k].2.push(s);
                    continue;
                }
                "fire_point" => {
                    let mut s = op(1, 0, -1);
                    let at = &b["at"];
                    (s["0x848"], s["0x852"], s["0x85c"]) =
                        (json!(format!("{}", num(&at[0]).round())), json!(num(&at[1])), json!(num(&at[2])));
                    let k = unit(&mut per, u);
                    per[k].2.push(s);
                    continue;
                }
                _ => continue,
            };
            let k = unit(&mut per, u);
            per[k].2.push(op(code, 0, -1));
        }
        let mut actions = vec![];
        for (u, s0, ops) in per {
            let s1 = if ops.is_empty() { -1 } else { append(m, u, 1, ops) };
            if valid(s0) || valid(s1) {
                actions.push(json!([u, s0, s1]));
            }
        }
        let ev = items(m, "events").iter_mut().find(|e| real(e) && int(&e["0x1e"]) == ev).unwrap();
        ev["0x3ac"] = json!(audio);
        ev["list"].as_array_mut().unwrap().extend(actions);
    };
    for (k, (wait, blocks)) in segs.iter().enumerate() {
        if k == 0 && carried {
            fill(m, e0, blocks, &mut chain);
            continue;
        }
        if *wait > 0 {
            chain.push(op(15, *wait, -1));
        }
        let ev = if k == 0 && start {
            e0
        } else {
            new_event(m, &format!("{name} +{}s", segs[..=k].iter().map(|s| s.0).sum::<i64>()))
        };
        chain.push(op(6, 0, ev));
        fill(m, ev, blocks, &mut chain);
    }
    if !chain.is_empty() {
        let h = new_sensor(m, &format!("Rule: {name}"), TAG_HOLDER, 2, start, [-1.0, -1.0, 0.0]);
        let first = append(m, h, 1, chain);
        if !start {
            let ev = items(m, "events").iter_mut().find(|e| real(e) && int(&e["0x1e"]) == e0).unwrap();
            ev["list"].as_array_mut().unwrap().push(json!([h, -1, first]));
        }
    }
    // WHEN: the slots that fire the first event.
    let w = &r["when"];
    let set_slot = |m: &mut Value, u: i64, k: usize| {
        let e = entity_mut(m, u).unwrap();
        (e["slots"][k]["0x33e"], e["slots"][k]["0x334"]) = (json!(e0), json!(name.clone()));
    };
    match w["kind"].as_str().unwrap_or("") {
        k @ ("destroyed" | "damaged") => {
            for u in w["units"].as_array().into_iter().flatten() {
                set_slot(m, int(u), if k == "destroyed" { 1 } else { 0 });
            }
        }
        k @ ("enters" | "leaves") => {
            let (owner, watched) = match plan_watch(m, w).unwrap() {
                Watch::Owner(o, watched) => (o, watched),
                Watch::Area(at, watched) => {
                    let near = if w["center"].is_null() { "a point".into() } else { name_of(m, int(&w["center"])) };
                    (new_sensor(m, &format!("Area: near {near}"), TAG_AREA, 2, true, at), watched)
                }
            };
            set_slot(m, owner, if k == "enters" { 5 } else { 4 });
            let e = entity_mut(m, owner).unwrap();
            (e["slots"][4]["0x348"], e["0xac"]) = (json!(num(&w["radius"]).round() as i64), json!(watched));
        }
        _ => {}
    }
    e0
}

/// Numbers compared as numbers (Godot's JSON gives floats).
fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => x.as_f64() == y.as_f64(),
        (Value::Array(x), Value::Array(y)) => x.len() == y.len() && x.iter().zip(y).all(|(p, q)| same(p, q)),
        (Value::Object(x), Value::Object(y)) => {
            x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| same(v, w)))
        }
        _ => a == b,
    }
}

fn changed(old: &Value, new: &Value) -> bool {
    ["name", "times", "debrief", "text", "when", "then"].iter().any(|k| !same(&old[*k], &new[*k]))
}

/// Writes `rules` (as `rules` gives them, edited) into `mission`: a rule whose key and content are unchanged is left
/// as it is; a changed or deleted editable rule is taken out and a new or changed one written; the original's
/// rules that are not editable are kept whatever the list says. The events follow the list's order.
/// JSON {mission, errors: [{rule (index), text}], keys: [the key of each rule, null when not written]}.
pub fn set_rules(mission: Value, rules: &Value) -> Value {
    let mut m = mission;
    let new: Vec<Value> = rules.as_array().cloned().unwrap_or_default();
    let old = read_all(&m);
    let key_of = |r: &Value| r["key"].as_i64().or(r["key"].as_f64().map(|f| f as i64));
    let unchanged = |o: &Read| {
        new.iter().any(|r| key_of(r) == key_of(&o.rule) && !changed(&o.rule, r)) || o.rule["editable"] == json!(false)
    };
    for o in old.iter().filter(|o| !unchanged(o)) {
        remove_rule(&mut m, o);
    }
    let mut errors = vec![];
    let mut keys = vec![];
    for (i, r) in new.iter().enumerate() {
        let kept = old.iter().find(|o| key_of(&o.rule) == key_of(r) && unchanged(o));
        if let Some(o) = kept {
            keys.push(o.rule["key"].clone());
            continue;
        }
        match check_rule(&m, r) {
            Ok(()) => keys.push(json!(write_rule(&mut m, r, i + 1))),
            Err(t) => {
                errors.push(json!({"rule": i, "text": t}));
                keys.push(Value::Null);
            }
        }
    }
    // The events in the list's order; a rule's later parts after it, events of no rule last.
    let rank: HashMap<i64, usize> = read_all(&m)
        .iter()
        .flat_map(|rd| {
            let at =
                keys.iter().position(|k| k.as_i64().is_some() && k.as_i64() == key_of(&rd.rule)).unwrap_or(usize::MAX);
            rd.walk.events.iter().map(move |&e| (e, at))
        })
        .collect();
    let evs = items(&mut m, "events");
    let mut order: Vec<(usize, usize, Value)> = std::mem::take(evs)
        .into_iter()
        .enumerate()
        .map(|(i, e)| {
            (if real(&e) { rank.get(&int(&e["0x1e"])).copied().unwrap_or(usize::MAX) } else { usize::MAX }, i, e)
        })
        .collect();
    order.sort_by_key(|(r, i, e)| (!real(e), *r, *i));
    *evs = order.into_iter().map(|(_, _, e)| e).collect();
    json!({"mission": m, "errors": errors, "keys": keys})
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    fn assets() -> Option<PathBuf> {
        let a = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        a.join("converted/missions/takeoff.json").exists().then_some(a)
    }

    fn read(a: &Path, name: &str) -> Value {
        serde_json::from_str(&std::fs::read_to_string(a.join(format!("converted/missions/{name}.json"))).unwrap())
            .unwrap()
    }

    /// A THEN list in the order `rules` reads it back.
    fn canonical(then: &Value) -> Value {
        let (mut t, mut out) = (0.0, vec![]);
        for b in then.as_array().unwrap() {
            if b["kind"] == "wait" {
                t += num(&b["seconds"]);
            } else {
                out.push((t, b.clone()));
            }
        }
        json!(timed(&out))
    }

    /// Without the placeholder rows (their ids move up as rows are added).
    fn real_rows(m: &Value) -> Value {
        let mut m = m.clone();
        for p in ["entities", "events", "paths"] {
            if let Some(a) = m[p]["items"].as_array_mut() {
                a.retain(real);
            }
        }
        m
    }

    #[test]
    fn originals_round_trip() {
        let Some(a) = assets() else { return eprintln!("skip: no converted missions") };
        let bdb = read(&a, "default6_1.bdb");
        let (mut total, mut editable, mut same_again) = (0, 0, 0);
        for f in std::fs::read_dir(a.join("converted/missions")).unwrap() {
            let p = f.unwrap().path();
            let m: Value = serde_json::from_str(&std::fs::read_to_string(&p).unwrap()).unwrap();
            if m["events"].is_null() {
                continue;
            }
            let rs = rules(&m, &bdb);
            // Unchanged rules leave the file as it was.
            let back = set_rules(m.clone(), &rs);
            assert_eq!(back["mission"], m, "{}", p.display());
            assert!(back["errors"].as_array().unwrap().is_empty(), "{}: {}", p.display(), back["errors"]);
            // Every editable rule rewritten in the editor's own form reads back as the same blocks.
            let forced: Vec<Value> = rs
                .as_array()
                .unwrap()
                .iter()
                .map(|r| {
                    let mut r = r.clone();
                    if r["editable"] == json!(true) {
                        r["key"] = Value::Null;
                    }
                    r
                })
                .collect();
            let w = set_rules(m.clone(), &json!(forced));
            assert!(w["errors"].as_array().unwrap().is_empty(), "{}: {}", p.display(), w["errors"]);
            let again = rules(&w["mission"], &bdb);
            let ed = |v: &Value| -> Vec<Value> {
                v.as_array().unwrap().iter().filter(|r| r["editable"] == json!(true)).cloned().collect()
            };
            let (before, after) = (ed(&rs), ed(&again));
            total += rs.as_array().unwrap().len();
            editable += before.len();
            if before.len() != after.len() {
                let lines = |v: &Value| -> String {
                    let a = v.as_array().unwrap().iter();
                    a.map(|r| format!("{} {} {}", r["editable"], r["summary"], r["why"])).collect::<Vec<_>>().join("\n")
                };
                panic!("{}\n{}\n---\n{}", p.display(), lines(&rs), lines(&again));
            }
            for (b, c) in before.iter().zip(&after) {
                // Read back as blocks, an area's centre and a route's Path index may differ only by the rewrite.
                let strip = |v: &Value| {
                    let mut v = v["then"].clone();
                    for b in v.as_array_mut().unwrap() {
                        let o = b.as_object_mut().unwrap();
                        o.remove("entry");
                        if o["kind"] == "goal" || o["kind"] == "fail" {
                            o.remove("unit");
                        }
                    }
                    v
                };
                if same(&strip(b), &strip(c)) && same(&b["when"]["kind"], &c["when"]["kind"]) {
                    same_again += 1;
                } else {
                    panic!("{}: {} became {}", p.display(), b["summary"], c["summary"]);
                }
            }
        }
        eprintln!("{total} rules, {editable} editable, {same_again} the same after a rewrite");
        assert!(editable > total / 2, "{editable} of {total}");
    }

    fn new_mission(a: &Path) -> Value {
        let mut m = crate::mission_edit::blank(read(a, "license"));
        let sam = json!({"0x2bc": "SA6", "0x2c6": 6, "0x2d0": 2, "0x2e4": 350000.0, "0x2ee": 600000.0, "0x2f8": 200,
            "0x32a": 1, "slots": vec![json!({"0x334": "", "0x33e": 0, "0x348": 0, "0x352": 0}); 7],
            "scripts0": {"items": []}, "scripts1": {"items": []}, "0xac": -1, "0x320": 0});
        let mut jeep = sam.clone();
        (jeep["0x2bc"], jeep["0x2c6"], jeep["0x32a"]) = (json!("Convoy"), json!(10), json!(2));
        let (m2, _) = crate::mission_edit::add_entity(m, &sam, &serde_json::Map::new());
        let (m3, _) = crate::mission_edit::add_entity(m2, &jeep, &serde_json::Map::new());
        m = m3;
        let ids: Vec<i64> =
            m["entities"]["items"].as_array().unwrap().iter().filter(|e| real(e)).map(|e| int(&e["0x1e"])).collect();
        let convoy = *ids.last().unwrap();
        crate::mission_edit::set_route(
            m,
            &[convoy],
            &[[350500.0, 600000.0, 0.0], [352000.0, 600000.0, 0.0]],
            36.0,
            true,
        )
    }

    #[test]
    fn rules_write_read_and_remove() {
        let Some(a) = assets() else { return eprintln!("skip: no converted missions") };
        let bdb = read(&a, "default6_1.bdb");
        let m = new_mission(&a);
        let ids: Vec<i64> =
            m["entities"]["items"].as_array().unwrap().iter().filter(|e| real(e)).map(|e| int(&e["0x1e"])).collect();
        let (alpha, sam, convoy) = (ids[0], ids[ids.len() - 2], ids[ids.len() - 1]);
        let rs = json!([
            {"when": {"kind": "destroyed", "units": [sam]},
             "then": [{"kind": "route", "unit": convoy}, {"kind": "message", "audio": 496}]},
            {"when": {"kind": "enters", "who": alpha, "center": sam, "radius": 10000.0},
             "then": [{"kind": "message", "audio": 23}, {"kind": "wait", "seconds": 30.0}, {"kind": "hide", "unit": convoy},
                      {"kind": "goal"}]},
            {"when": {"kind": "start"}, "then": [{"kind": "wait", "seconds": 60.0}, {"kind": "combat_off", "unit": sam}]},
        ]);
        let w = set_rules(m.clone(), &rs);
        assert!(w["errors"].as_array().unwrap().is_empty(), "{}", w["errors"]);
        let wm = &w["mission"];
        let back = rules(wm, &bdb);
        let back = back.as_array().unwrap();
        assert_eq!(back.len(), 3);
        for (r, b) in rs.as_array().unwrap().iter().zip(back) {
            assert_eq!(b["editable"], json!(true), "{}", b);
            let mut t = b["then"].clone();
            for x in t.as_array_mut().unwrap() {
                let o = x.as_object_mut().unwrap();
                o.remove("entry");
                if o["kind"] == "goal" {
                    o.remove("unit");
                }
            }
            assert!(same(&t, &canonical(&r["then"])), "{} vs {}", t, r["then"]);
            assert_eq!(b["when"]["kind"], r["when"]["kind"]);
        }
        assert_eq!(back[1]["when"]["center"], json!(sam));
        assert_eq!(back[0]["then"][1]["kind"], json!("route"));
        eprintln!("{}", back.iter().map(|b| b["summary"].as_str().unwrap()).collect::<Vec<_>>().join("\n"));
        assert!(
            back[0]["summary"]
                .as_str()
                .unwrap()
                .starts_with("When SA6 is destroyed → play \"MiG's! MiG's! MiG's!\", Convoy starts its route")
        );
        // The convoy's route waits on a Hover; the rule jumps to the Path.
        let c = entity(wm, convoy).unwrap();
        assert_eq!(entry(c, 0, 1).unwrap()["0x834"], json!(HOLD_NAME));
        assert_eq!(int(&entry(c, 0, 2).unwrap()["0x83e"]), 16);
        // The unchanged list writes nothing.
        assert_eq!(set_rules(wm.clone(), &json!(back))["mission"], *wm);
        // A new route keeps the hold and the jump.
        let r2 = crate::mission_edit::set_route(
            wm.clone(),
            &[convoy],
            &[[350500.0, 600500.0, 0.0], [353000.0, 600000.0, 0.0]],
            36.0,
            false,
        );
        let back2 = rules(&r2, &bdb);
        assert_eq!(back2[0]["then"][1]["kind"], json!("route"), "{}", back2[0]);
        assert_eq!(entry(entity(&r2, convoy).unwrap(), 0, 1).unwrap()["0x834"], json!(HOLD_NAME));
        // Removing every rule gives the mission back.
        let gone = set_rules(wm.clone(), &json!([]));
        assert_eq!(real_rows(&gone["mission"]), real_rows(&m));
        // Removing the SA-6 keeps the references whole: no action or watch names it.
        let rm = remove_entity(wm.clone(), sam);
        let s = serde_json::to_string(&rules(&rm, &bdb)).unwrap();
        assert!(!s.contains(&format!("\"unit\":{sam}")), "{s}");
        // Errors: a slot used twice, a route-less unit.
        let bad =
            json!([rs[0], {"when": {"kind": "destroyed", "units": [sam]}, "then": [{"kind": "route", "unit": sam}]}]);
        let e = set_rules(m.clone(), &bad);
        assert_eq!(e["errors"].as_array().unwrap().len(), 1, "{}", e["errors"]);
    }
}
