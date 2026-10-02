//! Mission coverage report: what every mission of the menu (main + base missions, from
//! `iaf-convert missions`) needs, as *features*, checked against what the engine supports, plus a
//! greedy "unlock order" (which feature or feature bundle makes the most missions fully playable).
//!
//! `iaf-mission-report <converted-missions-dir> <out.md>`
//!
//! Rules ported from the original (docs/front-end.md §8 / §15, docs/mission-runtime.md,
//! docs/formats/mis.md):
//! * Player: the leader of the lowest existing flight 1..4 (`FUN_004bb439` asks the flight map for 1,
//!   then 2..4; the TSD's default flight is the formation holding that object). A flight's leader is
//!   member 0 if spawned, else member 1. Training missions 3xx except 325 load the jet picked in the
//!   Jet list instead of the file's type (`FUN_004c2e30`), 325 and the rest fly the file's type.
//! * Win: every role-1 (`0x32a`) entity destroyed; role 0 must survive. A role-1 entity with an
//!   Explode (trigger op 5) in its own scripts is destroyed by the mission; any other must be killed.
//! * Loadout: pylons 0..8 from the entity's `CArmament` when any is set, else from the object type;
//!   9..11 (gun, chaff, flares) always from the type (`FUN_005951c0` / `FUN_00595220`).
//! * Brain-controlled (`0x320` bit 0 = 0) units are flown by the AI brain (`0x2da`, else the type's
//!   default brain by name); mission-controlled ones only move by their scripts.

use anyhow::{Context, Result};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

/// Trigger-list (scripts1) opcodes the mission runtime implements (docs/mission-runtime.md §4);
/// 3, 4, 15, 18, 19, 23, 26 are no-ops in the original too; 21 / 22 enable / disable combat (docs/ai.md §6).
const SUPPORTED_TRIGGER: &[i64] = &[3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 26];
/// Motion-list (scripts0) opcodes implemented: 1 Hover, 16 Path.
const SUPPORTED_MOTION: &[i64] = &[1, 16];
/// Player aircraft type codes (bdb Objects 0x5b4) that can be flown by the engine: the Jet list's seven.
const FLYABLE_NOW: &[i64] = &[100, 110, 120, 130, 140, 190, 200];
/// Type codes the original lets the player fly (`FUN_00507d00`).
const FLYABLE_ORIGINAL: &[i64] = &[100, 110, 120, 130, 140, 160, 180, 190, 200];
/// Jet list per training mission: jets disabled (`FUN_00509b80`), by type code.
const JET_LIST_DISABLED: &[(i64, &[i64])] = &[(314, &[190, 130]), (322, &[190, 130, 110]), (323, &[190, 130, 120, 110])];
/// The seven jets of the Jet list (Mirage, Kfir, F-4E, F-4 2000, F-15, F-16, Lavi).
const JET_LIST: &[i64] = &[190, 130, 120, 200, 110, 100, 140];
const AIRCRAFT: &[i64] = &[28, 3];
const HELICOPTER: i64 = 2;
const GROUND_UNITS: &[i64] = &[5, 6, 8, 9, 10, 15, 16];
/// Night in the original's rule (cockpit night dimming `FUN_0052df40`): 20 ≤ hour or hour ≤ 5.
fn is_night(t: f64) -> bool {
    let h = (t / 3600.0).floor() as i64 % 24;
    h >= 20 || h <= 5
}

const TRIGGER_NAMES: &[(i64, &str)] = &[
    (1, "Launch at location"),
    (2, "Launch at target"),
    (9, "?"),
    (20, "back to brain control"),
    (21, "Enable combat"),
    (22, "Disable combat"),
];
const MOTION_NAMES: &[(i64, &str)] = &[(5, "Turn"), (11, "Yaw to target")];

// Brain actions (bdb Actions `0x64`, lower case) that make a brain fight.
const AA_ACTIONS: &[&str] = &["launch weapon", "dogchase", "next aa missile", "change to mrm", "change to srm", "shandel", "imelman", "split s"];
const AG_ACTIONS: &[&str] = &["popup", "change to iron", "change to laser", "next ground target", "level bomb", "dive bomb", "next ag missile"];
const START_COMBAT: &str = "start combat";

// ---- features ----
const F_PLAYER_FLIGHT: &str = "player = default-flight leader (no `Player1`)";
const F_AI_FLIGHT: &str = "AI: brain flight (route, formation, take-off / landing)";
const F_AI_AA: &str = "AI: air-to-air combat";
const F_AI_AG: &str = "AI: air-to-ground attack";
const F_AI_HELI: &str = "AI: armed helicopters";
const F_GROUND_BRAIN: &str = "ground: brain-driven vehicles";
const F_SAM_RADAR: &str = "ground: radar SAMs (launch, guidance, RWR)";
const F_SAM_IR: &str = "ground: IR SAMs";
const F_AAA: &str = "ground: AAA guns";
const F_GROUND_FIRE: &str = "ground: armed vehicles / boats fire (rockets)";
const F_DAMAGE: &str = "damage & destruction (hits, kills, explosions)";
const F_NIGHT: &str = "night (lighting, cockpit dimming)";
const F_NO_WEAPON: &str = "no weapon the jet can load kills the targets";
const F_MP: &str = "multiplayer session";
const W_GUN: &str = "weapon: gun";
const W_IR: &str = "weapon: IR AAM (AIM-9, Python, Shafrir)";
const W_RADAR: &str = "weapon: radar AAM (AIM-7, AMRAAM) + radar lock";
const W_BOMB: &str = "weapon: unguided / cluster bombs (CCIP / CCRP)";
const W_ROCKET: &str = "weapon: rockets";
const W_LGB: &str = "weapon: laser-guided bombs";
const W_TV: &str = "weapon: TV / IR guided (AGM-65, AGM-62, GBU-15, Popeye)";
const W_ARM: &str = "weapon: anti-radiation (AGM-88, Shrike)";

/// Features built today (docs/status.md): the player flight choice, the damage model, the gun, the IR
/// missiles, the bombs (incl. cluster) and the rockets (docs/weapons.md).
const SUPPORTED_FEATURES: &[&str] = &[F_PLAYER_FLIGHT, F_DAMAGE, W_GUN, W_IR, F_AI_FLIGHT, W_BOMB, W_ROCKET];

/// Rough implementation size (S ≈ days, M ≈ a week, L ≈ weeks) — an estimate for planning only.
fn size(f: &str) -> &'static str {
    match f {
        F_PLAYER_FLIGHT | W_ROCKET | F_SAM_IR | F_NIGHT => "S",
        F_AI_FLIGHT | F_AI_AA | W_TV | F_MP => "L",
        _ if f.starts_with("jet: ") => "L",
        _ if f.starts_with("script: ") => "S",
        _ => "M",
    }
}

/// Player weapon feature of a bdb Weapons type code (`0x780`); None = not a weapon (tanks, pods,
/// chaff, flares, SAMs).
fn weapon_feature(t: i64) -> Option<&'static str> {
    Some(match t {
        565 => W_GUN,
        570 | 580 => W_IR,
        600 | 610 => W_RADAR,
        500 | 510 => W_BOMB,
        560 => W_ROCKET,
        650 => W_LGB,
        635 | 640 => W_TV,
        590 => W_ARM,
        _ => return None,
    })
}

struct Bdb {
    objects: BTreeMap<i64, Value>,
    weapon_type: BTreeMap<i64, i64>,
    weapon_name: BTreeMap<i64, String>,
    /// brain id → (AA, AG, start combat)
    brains: BTreeMap<i64, (bool, bool, bool)>,
    brain_by_name: BTreeMap<String, i64>,
}

fn load(dir: &Path, name: &str) -> Result<Value> {
    Ok(serde_json::from_slice(&std::fs::read(dir.join(format!("{name}.json"))).with_context(|| name.to_string())?)?)
}

fn items<'a>(v: &'a Value, part: &str) -> impl Iterator<Item = &'a Value> {
    v[part]["items"].as_array().into_iter().flatten()
}

fn i(v: &Value, k: &str) -> i64 {
    v[k].as_i64().or_else(|| v[k].as_f64().map(|f| f as i64)).unwrap_or(-1)
}

fn load_bdb(dir: &Path, name: &str) -> Result<Bdb> {
    let b = load(dir, name)?;
    let actions: BTreeMap<i64, String> = items(&b, "actions").map(|a| (i(a, "0x1e"), a["0x64"].as_str().unwrap_or("").trim().to_lowercase())).collect();
    let mut brains = BTreeMap::new();
    let mut brain_by_name = BTreeMap::new();
    for br in items(&b, "brains") {
        let (mut aa, mut ag, mut sc) = (false, false, false);
        for part in ["rules0", "rules1"] {
            for r in br[part]["items"].as_array().into_iter().flatten() {
                for l in r["list20"].as_array().into_iter().flatten() {
                    let a = actions.get(&l[2].as_i64().unwrap_or(-1)).map(String::as_str).unwrap_or("");
                    aa |= AA_ACTIONS.contains(&a);
                    ag |= AG_ACTIONS.contains(&a);
                    sc |= a == START_COMBAT;
                }
            }
        }
        brains.insert(i(br, "0x1e"), (aa, ag, sc));
        brain_by_name.insert(br["0x1f4"].as_str().unwrap_or("").to_lowercase(), i(br, "0x1e"));
    }
    Ok(Bdb {
        objects: items(&b, "objects").map(|o| (i(o, "0x1e"), o.clone())).collect(),
        weapon_type: items(&b, "weapons").map(|w| (i(w, "0x1e"), i(w, "0x780"))).collect(),
        weapon_name: items(&b, "weapons").map(|w| (i(w, "0x1e"), w["0x708"].as_str().unwrap_or("").trim().to_string())).collect(),
        brains,
        brain_by_name,
    })
}

fn hardpoints(v: &Value) -> Vec<(i64, i64)> {
    let h: Vec<i64> = v["armament"]["hardpoints"].as_array().into_iter().flatten().map(|x| x.as_i64().unwrap_or(0)).collect();
    h.chunks(2).map(|c| (c[0], *c.get(1).unwrap_or(&0))).collect()
}

/// The loadout an entity spawns with: [(weapon id, count)] for the 12 stations.
fn loadout(e: &Value, obj: &Value) -> Vec<(i64, i64)> {
    let (ent, typ) = (hardpoints(e), hardpoints(obj));
    let pylons_set = ent.iter().take(9).any(|(id, _)| *id != 0);
    (0..12)
        .map(|s| {
            let src = if s < 9 && pylons_set { &ent } else { &typ };
            src.get(s).copied().unwrap_or((0, 0))
        })
        .filter(|(id, n)| *id != 0 && *n != 0)
        .collect()
}

fn ops(e: &Value, part: &str) -> Vec<i64> {
    e[part]["items"].as_array().into_iter().flatten().filter_map(|s| s["0x83e"].as_i64()).collect()
}

fn unplaced(e: &Value) -> bool {
    i(e, "0x2e4") < 0 && i(e, "0x2ee") < 0
}

/// Off the map for good: unplaced (x, y < 0) and no Path to bring it in.
fn off_map(e: &Value) -> bool {
    unplaced(e) && !ops(e, "scripts0").contains(&16)
}

/// Requirements as clauses: the mission is playable when every clause has a supported feature.
type Clause = BTreeSet<String>;

struct Mission {
    id: i64,
    file: String,
    title: String,
    player: String,
    flight: String,
    others: String,
    start: String,
    targets: String,
    load: String,
    clauses: Vec<Clause>,
}

fn one(f: &str) -> Clause {
    [f.to_string()].into()
}

fn satisfied(m: &Mission, have: &BTreeSet<String>) -> bool {
    m.clauses.iter().all(|c| c.iter().any(|f| have.contains(f)))
}

fn missing(m: &Mission, have: &BTreeSet<String>) -> Vec<String> {
    m.clauses
        .iter()
        .filter(|c| !c.iter().any(|f| have.contains(f)))
        .map(|c| c.iter().cloned().collect::<Vec<_>>().join(" **or** "))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn analyse(dir: &Path, id: i64, names: &[String], bdbs: &mut BTreeMap<String, Bdb>) -> Result<Mission> {
    let files: Vec<Value> = names.iter().map(|n| load(dir, n)).collect::<Result<_>>()?;
    let main = &files[0];
    let bdb_name = main["bdb"].as_str().unwrap_or("").to_lowercase();
    if !bdbs.contains_key(&bdb_name) {
        bdbs.insert(bdb_name.clone(), load_bdb(dir, &bdb_name)?);
    }
    let bdb = &bdbs[&bdb_name];
    let obj = |e: &Value| bdb.objects.get(&i(e, "0x2c6")).cloned().unwrap_or(Value::Null);
    let misc = items(main, "misc").next().cloned().unwrap_or(Value::Null);
    let title = misc["0x44c"].as_str().unwrap_or("").to_string();
    let mut clauses: Vec<Clause> = Vec::new();
    let mp = (500..600).contains(&id) || id == 666 || id == 777;
    if mp {
        clauses.push(one(F_MP));
    }

    // ---- player: leader of the lowest existing flight 1..4 of the main mission ----
    let by_id: BTreeMap<i64, &Value> = items(main, "entities").map(|e| (i(e, "0x1e"), e)).collect();
    let mut flights: Vec<(i64, String, &Value)> = Vec::new();
    for f in items(main, "formations") {
        let n = i(f, "0x3f2");
        if !(1..=4).contains(&n) {
            continue;
        }
        let leader = f["members"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|m| by_id.get(&i(m, "0x41a")).copied())
            .find(|e| !unplaced(e));
        if let Some(l) = leader {
            flights.push((n, f["0x3e8"].as_str().unwrap_or("").trim().to_string(), l));
        }
    }
    flights.sort_by_key(|f| f.0);
    let type_of = |e: &Value| {
        let o = obj(e);
        (i(&o, "0x5b4"), o["0x528"].as_str().unwrap_or("?").trim().to_string())
    };
    let jet_name = |t: i64| {
        bdb.objects.values().find(|o| i(o, "0x5b4") == t && i(o, "0x5aa") == 28).and_then(|o| o["0x528"].as_str()).unwrap_or("?").trim().to_string()
    };
    let (mut player, mut flight, mut others, mut start) = ("none".to_string(), "-".to_string(), String::new(), "-".to_string());
    let mut player_ent: Option<&Value> = None;
    if let Some((n, name, leader)) = flights.first() {
        player_ent = Some(leader);
        let (t, tn) = type_of(leader);
        flight = format!("{name} ({n})");
        let jet_list = (300..400).contains(&id) && id != 325;
        if jet_list {
            let disabled = JET_LIST_DISABLED.iter().find(|(m, _)| *m == id).map_or(&[][..], |(_, d)| d);
            let allowed: Vec<i64> = JET_LIST.iter().copied().filter(|t| !disabled.contains(t)).collect();
            player = format!("Jet list: {}", allowed.iter().map(|t| jet_name(*t)).collect::<Vec<_>>().join(", "));
            clauses.push(allowed.iter().map(|t| format!("jet: {} ({t})", jet_name(*t))).collect());
        } else {
            player = format!("{tn} ({t})");
            clauses.push(one(&format!("jet: {tn} ({t})")));
        }
        if !leader["0x2bc"].as_str().unwrap_or("").eq_ignore_ascii_case("player1") {
            clauses.push(one(F_PLAYER_FLIGHT));
        }
        others = flights[1..]
            .iter()
            .filter(|(_, _, l)| FLYABLE_ORIGINAL.contains(&type_of(l).0) && i(l, "0x2d0") == 1)
            .map(|(n, _, l)| format!("{n}:{}", type_of(l).1))
            .collect::<Vec<_>>()
            .join(" ");
        start = if i(leader, "0x2f8") > 800 { "air".into() } else { "ground".into() };
    }
    let t0 = misc["0x460"].as_f64().unwrap_or(43200.0);
    let night = is_night(t0);
    if night {
        clauses.push(one(F_NIGHT));
    }
    start = format!("{start}, {:02}:{:02}{}", (t0 as i64) / 3600, (t0 as i64) / 60 % 60, if night { " night" } else { "" });

    // Player weapons by feature.
    let mut player_w: BTreeSet<&'static str> = BTreeSet::new();
    let mut load = Vec::new();
    if let Some(p) = player_ent {
        for (wid, n) in loadout(p, &obj(p)) {
            let t = bdb.weapon_type.get(&wid).copied().unwrap_or(0);
            if let Some(f) = weapon_feature(t) {
                player_w.insert(f);
                load.push(format!("{}×{n}", bdb.weapon_name.get(&wid).map(String::as_str).unwrap_or("?")));
            }
        }
    }
    let aa_w: Clause = [W_IR, W_RADAR, W_GUN].iter().filter(|f| player_w.contains(*f)).map(|f| f.to_string()).collect();
    let ag_w = |emitter: bool| -> Clause {
        [W_BOMB, W_ROCKET, W_LGB, W_TV].iter().chain(if emitter { &[W_ARM][..] } else { &[][..] }).filter(|f| player_w.contains(*f)).map(|f| f.to_string()).collect()
    };
    // The Arming screen (built, docs/front-end.md §15): the weapons the leader's bdb object may load
    // (its CDMEWeaponLoadItems with a count and a station flag), SAM types excluded.
    let mut arm_w: BTreeSet<&'static str> = BTreeSet::new();
    if let Some(p) = player_ent {
        for it in obj(p)["loads"]["items"].as_array().into_iter().flatten() {
            let flags = it["raw"].as_str().unwrap_or("");
            if i(it, "0x906") > 0 && flags.chars().any(|c| c != '0')
                && let Some(f) = bdb.weapon_type.get(&i(it, "0x910")).and_then(|t| weapon_feature(*t)) {
                    arm_w.insert(f);
                }
        }
    }
    let arm_aa: Clause = [W_IR, W_RADAR].iter().filter(|f| arm_w.contains(*f)).map(|f| f.to_string()).collect();
    let arm_ag = |emitter: bool| -> Clause {
        [W_BOMB, W_ROCKET, W_LGB, W_TV].iter().chain(if emitter { &[W_ARM][..] } else { &[][..] }).filter(|f| arm_w.contains(*f)).map(|f| f.to_string()).collect()
    };

    // ---- every entity of every file ----
    struct Unit {
        side: i64,
        kind: i64, // 0 aircraft, 1 helicopter, 2 ground unit
        class: i64,
        brain_ctl: bool,
        fights: bool,
        b_aa: bool,
        b_ag: bool,
        b_sc: bool,
        weapons: Vec<i64>,
    }
    let mut units: Vec<Unit> = Vec::new();
    let mut combat_ops: BTreeSet<i64> = BTreeSet::new();
    // Placed aircraft / ground units per side (the player is a side-1 aircraft).
    let (mut air_side, mut ground_side) = (BTreeSet::from([1i64]), BTreeSet::new());
    let (mut t_script, mut t_air, mut t_ground, mut t_lost) = (0, 0, 0, 0);
    // Role-1 targets the player must kill: (air?, emitter?)
    let mut kills: Vec<(bool, bool)> = Vec::new();
    for (fi, m) in files.iter().enumerate() {
        for e in items(m, "entities") {
            for (motion, part) in [(true, "scripts0"), (false, "scripts1")] {
                for op in ops(e, part) {
                    let (sup, names, kind) = if motion { (SUPPORTED_MOTION, MOTION_NAMES, "motion") } else { (SUPPORTED_TRIGGER, TRIGGER_NAMES, "trigger") };
                    // Enable / Disable combat only matter on a unit that fights (checked below).
                    if !sup.contains(&op) && !(!motion && (op == 21 || op == 22)) {
                        let n = names.iter().find(|(k, _)| *k == op).map_or("?", |(_, n)| n);
                        clauses.push(one(&format!("script: {kind} op {op} {n}")));
                    }
                }
            }
            if fi == 0 && player_ent.is_some_and(|p| std::ptr::eq(p, e)) {
                continue;
            }
            let o = obj(e);
            let class = i(&o, "0x5aa");
            let name = e["0x2bc"].as_str().unwrap_or("").to_lowercase();
            if unplaced(e) && name.starts_with("player") {
                continue; // unused player slot, never spawned
            }
            let trig = ops(e, "scripts1");
            let motion = ops(e, "scripts0");
            let brain_ctl = i(e, "0x320") & 1 == 0;
            let moving = brain_ctl || motion.iter().any(|op| *op == 16 || *op == 5);
            let flying = AIRCRAFT.contains(&class) || class == HELICOPTER;
            // Role-1 targets.
            if i(e, "0x32a") == 1 {
                if trig.contains(&5) {
                    t_script += 1;
                } else if off_map(e) {
                    t_lost += 1;
                } else if flying && moving {
                    t_air += 1;
                    kills.push((true, false));
                } else {
                    t_ground += 1;
                    kills.push((false, class == 8 || class == 11));
                }
            }
            if off_map(e) || !(flying || GROUND_UNITS.contains(&class)) {
                continue;
            }
            let side = i(e, "0x2d0");
            if flying {
                air_side.insert(side);
            } else {
                ground_side.insert(side);
            }
            // Behaviour of units.
            let brain = match i(e, "0x2da") {
                b if b >= 0 => b,
                _ => bdb.brain_by_name.get(&o["0x532"].as_str().unwrap_or("").to_lowercase()).copied().unwrap_or(-1),
            };
            let (b_aa, b_ag, b_sc) = bdb.brains.get(&brain).copied().unwrap_or_default();
            let weapons: Vec<i64> = loadout(e, &o).iter().filter_map(|(w, _)| bdb.weapon_type.get(w).copied()).filter(|t| !matches!(t, 0 | 540 | 550 | 660)).collect();
            let disabled_for_good = trig.contains(&22) && !trig.contains(&21);
            let fights = !weapons.is_empty() && (b_aa || b_ag || b_sc || trig.contains(&21)) && !disabled_for_good;
            let kind = if AIRCRAFT.contains(&class) { 0 } else if class == HELICOPTER { 1 } else { 2 };
            if fights {
                // Enable / Disable combat are needed on units that fight; on a unit disabled for good
                // they only keep it passive, which an engine without that unit's fire does anyway.
                for op in trig.iter().filter(|op| **op == 21 || **op == 22) {
                    combat_ops.insert(*op);
                }
            }
            units.push(Unit { side, kind, class, brain_ctl, fights, b_aa, b_ag, b_sc, weapons });
        }
    }
    for op in combat_ops.into_iter().filter(|op| !SUPPORTED_TRIGGER.contains(op)) {
        let n = TRIGGER_NAMES.iter().find(|(k, _)| *k == op).map_or("?", |(_, n)| n);
        clauses.push(one(&format!("script: trigger op {op} {n}")));
    }
    let foe = |side: i64| match side {
        1 => 2,
        2 => 1,
        _ => -1,
    };
    let mut need: BTreeSet<&'static str> = BTreeSet::new();
    let (mut friendly_aa, mut friendly_ag) = (false, false);
    for u in &units {
        let air_foe = air_side.contains(&foe(u.side));
        let ground_foe = ground_side.contains(&foe(u.side));
        let aam = u.weapons.iter().any(|t| matches!(t, 565 | 570 | 580 | 600 | 610));
        let agw = u.weapons.iter().any(|t| matches!(t, 500 | 510 | 560 | 590 | 635 | 640 | 650));
        match u.kind {
            0 | 1 => {
                if u.brain_ctl {
                    need.insert(F_AI_FLIGHT);
                }
                if !u.fights {
                    continue;
                }
                if u.kind == 1 {
                    need.insert(F_AI_HELI);
                    continue;
                }
                if (u.b_aa || (u.b_sc && aam)) && air_foe {
                    need.insert(F_AI_AA);
                    friendly_aa |= u.side == 1;
                }
                if u.b_ag || (u.b_sc && agw) {
                    need.insert(F_AI_AG);
                    friendly_ag |= u.side == 1;
                }
            }
            _ => {
                if u.brain_ctl {
                    need.insert(F_GROUND_BRAIN);
                }
                if !u.fights {
                    continue;
                }
                // Surface-to-air by the weapon (a radar-SAM class firing an IR round is still a radar site).
                for t in &u.weapons {
                    match t {
                        565 if air_foe => need.insert(F_AAA),
                        570 | 580 | 620 if air_foe => need.insert(if u.class == 8 { F_SAM_RADAR } else { F_SAM_IR }),
                        600 | 610 | 630 if air_foe => need.insert(F_SAM_RADAR),
                        565 | 570 | 580 | 600 | 610 | 620 | 630 => false,
                        _ if ground_foe => need.insert(F_GROUND_FIRE),
                        _ => false,
                    };
                }
            }
        }
    }
    // What kills the role-1 targets: the player's default loadout or a load from the Arming screen
    // (else the friendly AI flights, when they carry the right weapons).
    let mut kill_clauses: Vec<Clause> = Vec::new();
    for (air, emitter) in kills {
        let mut c: Clause = if air { aa_w.clone() } else { ag_w(emitter) };
        c.extend(if air { arm_aa.clone() } else { arm_ag(emitter) });
        if c.is_empty() {
            c.insert(F_NO_WEAPON.to_string());
            if air && friendly_aa {
                c.insert(F_AI_AA.to_string());
            }
            if !air && friendly_ag {
                c.insert(F_AI_AG.to_string());
            }
        }
        kill_clauses.push(c);
    }
    if need.contains(F_AI_AA) || need.contains(F_AI_AG) {
        need.insert(F_AI_FLIGHT);
    }
    let shooting = [F_AI_AA, F_AI_AG, F_AI_HELI, F_SAM_RADAR, F_SAM_IR, F_AAA, F_GROUND_FIRE].iter().any(|f| need.contains(f));
    if shooting || !kill_clauses.is_empty() {
        need.insert(F_DAMAGE);
    }
    clauses.extend(need.iter().map(|f| one(f)));
    clauses.extend(kill_clauses);
    let mut targets = Vec::new();
    for (n, what) in [(t_script, "scripted"), (t_air, "air"), (t_ground, "ground"), (t_lost, "unplaced")] {
        if n > 0 {
            targets.push(format!("{n} {what}"));
        }
    }
    let targets = if targets.is_empty() { "none (cannot be won)".to_string() } else { targets.join(", ") };
    let mut seen = BTreeSet::new();
    clauses.retain(|c| seen.insert(c.clone()));
    Ok(Mission {
        id,
        file: names[0].clone(),
        title,
        player,
        flight,
        others,
        start,
        targets,
        load: load.join(" "),
        clauses,
    })
}

/// Greedy unlock order: repeatedly add the candidate (a single missing feature, or the completion
/// bundle of one open mission) with the most newly playable missions per feature. Writes the table,
/// returns (steps, playable at the end).
fn greedy(missions: &[Mission], have: &BTreeSet<String>, forbidden: &BTreeSet<String>, md: &mut String) -> (usize, usize) {
    let mut have = have.clone();
    let reachable = |m: &Mission| m.clauses.iter().all(|c| c.iter().any(|f| !forbidden.contains(f)));
    let mut done: BTreeSet<i64> = missions.iter().filter(|m| satisfied(m, &have)).map(|m| m.id).collect();
    md.push_str(&format!("Start: **{}** playable.\n\n| step | add | size | newly playable | cumulative |\n|---|---|---|---|---|\n", done.len()));
    let mut step = 0;
    loop {
        let open: Vec<&Mission> = missions.iter().filter(|m| !done.contains(&m.id) && reachable(m)).collect();
        if open.is_empty() {
            break;
        }
        let freq = |f: &str| open.iter().filter(|m| m.clauses.iter().any(|c| c.contains(f))).count();
        let mut cands: BTreeSet<BTreeSet<String>> = BTreeSet::new();
        for m in &open {
            // Completion bundle: per open clause the most wanted allowed feature (or one already chosen).
            let mut b: BTreeSet<String> = BTreeSet::new();
            for c in m.clauses.iter().filter(|c| !c.iter().any(|f| have.contains(f))) {
                if c.iter().any(|f| b.contains(f)) {
                    continue;
                }
                let best = c.iter().filter(|f| !forbidden.contains(*f)).max_by_key(|f| (freq(f), std::cmp::Reverse((*f).clone()))).unwrap();
                b.insert(best.clone());
            }
            for f in &b {
                cands.insert([f.clone()].into());
            }
            cands.insert(b);
        }
        let score = |b: &BTreeSet<String>| {
            let h: BTreeSet<String> = have.union(b).cloned().collect();
            open.iter().filter(|m| satisfied(m, &h)).count()
        };
        let best = cands.iter().map(|b| (score(b), b)).filter(|(g, _)| *g > 0).max_by(|(ga, a), (gb, b)| {
            let (ra, rb) = (*ga as f64 / a.len() as f64, *gb as f64 / b.len() as f64);
            ra.partial_cmp(&rb).unwrap().then(ga.cmp(gb)).then(b.len().cmp(&a.len())).then(b.cmp(a))
        });
        let Some((_, b)) = best else { break };
        let b = b.clone();
        have.extend(b.iter().cloned());
        let new: Vec<i64> = open.iter().filter(|m| satisfied(m, &have)).map(|m| m.id).collect();
        done.extend(new.iter().copied());
        step += 1;
        md.push_str(&format!(
            "| {step} | {} | {} | {} ({}) | **{}** |\n",
            b.iter().cloned().collect::<Vec<_>>().join(" + "),
            b.iter().map(|f| size(f)).collect::<Vec<_>>().join("+"),
            new.len(),
            new.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(", "),
            done.len()
        ));
    }
    (step, done.len())
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let [_, dir, out] = &args[..] else { anyhow::bail!("usage: iaf-mission-report <converted-missions-dir> <out.md>") };
    let dir = Path::new(dir);
    let list = load(dir, "missionlist")?;
    let mut ids: Vec<(i64, Vec<String>)> = list
        .as_object()
        .context("missionlist")?
        .iter()
        .filter_map(|(k, v)| Some((k.parse().ok()?, v.as_array()?.iter().filter_map(|n| Some(n.as_str()?.to_string())).collect())))
        .collect();
    ids.sort_by_key(|(k, _)| *k);
    let mut bdbs = BTreeMap::new();
    let missions: Vec<Mission> = ids.iter().map(|(id, names)| analyse(dir, *id, names, &mut bdbs)).collect::<Result<_>>()?;

    // Supported today.
    let mut have: BTreeSet<String> = BTreeSet::new();
    let all: BTreeSet<String> = missions.iter().flat_map(|m| m.clauses.iter().flatten().cloned()).collect();
    for f in &all {
        if FLYABLE_NOW.iter().any(|t| f.starts_with("jet: ") && f.ends_with(&format!("({t})"))) || SUPPORTED_FEATURES.contains(&f.as_str()) {
            have.insert(f.clone());
        }
    }

    let now: Vec<i64> = missions.iter().filter(|m| satisfied(m, &have)).map(|m| m.id).collect();
    let is_jet = |f: &str| f.starts_with("jet: ");
    let f16_ok = |m: &Mission| m.clauses.iter().filter(|c| c.iter().any(|f| is_jet(f))).all(|c| c.iter().any(|f| have.contains(f)));
    let mut md = String::from(
        "# Mission coverage\n\nAddresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0 \
         and lists what the patch changed.\n\n",
    );
    md.push_str(
        "Generated by `iaf-mission-report` from the converted missions (`tools/setup.sh` output). Every mission is broken into \
         *features* it needs; a mission is **playable** when all of them are supported. The rules (from the original) are \
         in §4, the limits of this analysis in §5. Regenerate with \
         `./target/release/iaf-mission-report assets/converted/missions docs/mission-coverage.md`.\n\n",
    );
    md.push_str(&format!(
        "**Playable today: {} of {}** ({}). Missions the F-16 can fly (its campaign / scramble missions, and the \
         training missions through the Jet list): {} (all seven Jet list jets fly).\n\n",
        now.len(),
        missions.len(),
        now.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(", "),
        missions.iter().filter(|m| f16_ok(m)).count()
    ));
    md.push_str(
        "## 1. Unlock order (greedy)\n\nEach step adds the feature, or the smallest bundle of features that only pays off \
         together, with the most newly playable missions per feature added (ties: more missions). \"Size\" is a rough \
         estimate (S days, M about a week, L weeks).\n\n### 1.1 All missions\n\n",
    );
    let (steps, last) = greedy(&missions, &have, &BTreeSet::new(), &mut md);
    md.push_str("\n### 1.2 F-16 only (no other jet)\n\nThe same, with the other jets left out: the order to build the \
                 F-16's missions.\n\n");
    let other_jets: BTreeSet<String> = all.iter().filter(|f| is_jet(f) && !have.contains(*f)).cloned().collect();
    greedy(&missions, &have, &other_jets, &mut md);

    // ---- per jet ----
    md.push_str("\n### 1.3 Per jet\n\nMissions whose player jet is this type (training missions count for every jet \
                 of their Jet list).\n\n| jet | size | missions | ids |\n|---|---|---|---|\n");
    let mut jets: Vec<(usize, String, Vec<i64>)> = all
        .iter()
        .filter(|f| is_jet(f))
        .map(|f| {
            let ids: Vec<i64> = missions.iter().filter(|m| m.clauses.iter().any(|c| c.contains(f) && c.iter().all(|x| is_jet(x)))).map(|m| m.id).collect();
            (ids.len(), f.clone(), ids)
        })
        .collect();
    jets.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    for (n, f, ids) in jets {
        let sz = if have.contains(&f) { "done" } else { size(&f) };
        md.push_str(&format!("| {} | {sz} | {n} | {} |\n", &f[5..], ids.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(", ")));
    }

    // ---- nearest ----
    md.push_str("\n### 1.4 Nearest to playable\n\nMissions with at most four missing features (an \"or\" choice counts once).\n\n\
                 | id | title | player jet | missing |\n|---|---|---|---|\n");
    let mut near: Vec<(usize, &Mission)> = missions.iter().map(|m| (missing(m, &have).len(), m)).filter(|(n, _)| (1..=4).contains(n)).collect();
    near.sort_by_key(|(n, m)| (*n, m.id));
    for (_, m) in near {
        md.push_str(&format!("| {} | {} | {} | {} |\n", m.id, m.title, m.player, missing(m, &have).join("; ")));
    }

    // ---- most-needed features ----
    let base = have.clone();
    md.push_str(
        "\n## 2. Most-needed features\n\n\"needed by\" = missions not playable today that list the feature (for an \
         \"or\" choice, e.g. which weapon kills a target, every option is counted); \"F-16\" = of those, the missions \
         the F-16 can fly.\n\n| feature | size | needed by | F-16 |\n|---|---|---|---|\n",
    );
    let mut rows: Vec<(usize, usize, String)> = all
        .iter()
        .filter(|f| !base.contains(*f))
        .map(|f| {
            let needing: Vec<&Mission> = missions.iter().filter(|m| !satisfied(m, &base) && m.clauses.iter().any(|c| c.contains(f))).collect();
            (needing.len(), needing.iter().filter(|m| f16_ok(m)).count(), f.clone())
        })
        .collect();
    rows.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)).then(a.2.cmp(&b.2)));
    for (n, f16, f) in rows {
        md.push_str(&format!("| {f} | {} | {n} | {f16} |\n", size(&f)));
    }

    // ---- per mission ----
    md.push_str(
        "\n## 3. Missions\n\nplayer = default flight's leader type (training: the Jet list); start = air above 800 m, \
         time of day (night by the original's cockpit rule); targets = role-1 entities (scripted = the mission \
         explodes it itself); loadout = the player's default weapons.\n\n| id | file | title | player jet | flight | other \
         flyable flights | start | targets | loadout | playable | missing |\n|---|---|---|---|---|---|---|---|---|---|---|\n",
    );
    for m in &missions {
        let miss = missing(m, &base);
        md.push_str(&format!(
            "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |\n",
            m.id,
            m.file,
            m.title,
            m.player,
            m.flight,
            m.others,
            m.start,
            m.targets,
            m.load,
            if miss.is_empty() { "**yes**" } else { "no" },
            miss.join("; ")
        ));
    }
    md.push_str(NOTES);
    std::fs::write(out, md)?;
    println!("{} missions ({} playable now, {last} after {steps} greedy steps) -> {out}", missions.len(), now.len());
    Ok(())
}

const NOTES: &str = r#"
## 4. Rules used (ported from the original)

* **Player aircraft.** At mission load the player object is the leader of flight 1, else of flights 2..4
  (`FUN_004bb439` asks the flight map for 1, then 2..4); the TSD's default flight is the formation holding it
  (`FUN_005bcd70`, docs/front-end.md §8). A flight is formation `0x3f2` 1..4; its leader is member 0 if placed,
  else member 1. Campaign and scramble missions have no `Player1`: the player flies that leader's bdb type
  (`0x5b4`). Training missions 311–326 except 325 are entered through the Jet list and load the chosen jet
  (`FUN_004c2e30`; jets disabled per mission by `FUN_00509b80`), so any allowed jet flies them. The seven Jet list jets
  (100, 110, 120, 130, 140, 190, 200) are flyable in the engine; the runtime also takes the player from the entity named `Player1`, so every
  other mission needs "player = default-flight leader".
* **Other flights.** The "other flyable flights" column lists flights 2..4 the player could pick instead
  (flyable type and side 1, `FUN_00505820`). Playability is judged on the default flight only.
* **Win condition** (docs/mission-runtime.md §5.1): all role-1 (`0x32a`) entities destroyed. A role-1 entity with
  Explode (trigger op 5) in its own scripts is destroyed by the mission ("scripted"); any other one must be killed:
  aircraft / helicopters that move (brain-controlled, or a Path / Turn script) are air targets, everything else
  (buildings, parked aircraft, vehicles, runway "fire sensors") ground targets. No role-1 entity = the mission
  can never be won automatically (the multiplayer 666 / 777).
* **Weapons.** The player's default loadout (pylons 0–8 from the entity's `CArmament` when any is set, else
  the type's; 9–11 from the type) sorted by bdb Weapons type `0x780`: 565 gun, 570/580 IR AAM, 600/610 radar
  AAM, 500/510 bombs, 560 rockets, 650 laser-guided, 635/640 TV / IR guided, 590 anti-radiation (counted only
  against radars, classes 8 and 11); 540/550/660 (chaff, flares, tanks, pods) are not weapons. Air targets need
  one of the AAM / gun features the loadout has; ground targets one of its air-to-ground features (the gun is
  not counted against ground targets). The Arming screen adds the weapons the leader's bdb object may load
  (its `CDMEWeaponLoadItem`s, docs/front-end.md §15) as further choices. If none of them fits, friendly AI
  flights carrying the right weapons are the only way (the or-choice in the table).
* **AI aircraft** (classes 28 controlled aircraft, 3 aircraft, 2 helicopters). `0x320` bit 0 = 0 is
  brain-controlled: it needs the AI brain flight. A unit *fights* when it carries a weapon, its brain (`0x2da`,
  else the type's default brain `0x532` by name) has an attack action (bdb Actions: launch weapon, dog chase,
  missile selection, Shandel / Immelman / split S → air-to-air; pop-up, iron / laser, next ground target,
  level / dive bomb → air-to-ground) or a "start combat" action, or its scripts enable combat (op 21), and it is
  not disabled for good (op 22 without an op 21). Mission-controlled aircraft that do not fight only move by
  their scripts (already supported: Hover, Path), e.g. parked MiGs.
* **Ground units** (classes 5, 6, 8, 9, 10, 15, 16): all are mission-controlled, drawn today; brain-driven ones
  need the ground AI. A fighting unit needs its fire by weapon: gun → AAA, IR rounds → IR SAM (on a radar-SAM
  class → radar SAM), radar rounds → radar SAM, others (rockets) → armed vehicles / boats. Surface-to-air fire
  counts only if the other side has aircraft (the player is side 1); rockets only if the other side has ground
  units. Enable / Disable combat (ops 21 / 22) count only on units that fight.
* **Damage & destruction** is needed as soon as anything shoots or a target must be killed.
* **Start**: airborne when the player's altitude is above 800 m (docs/flight-model.md, start rules); both
  starts are supported. **Night**: start hour ≥ 20 or ≤ 5, the cockpit night rule (docs/cockpit.md).
* **Scripts**: trigger ops the runtime implements: 3–8, 10–19, 21, 22, 23, 26; motion: 1 Hover, 16 Path. Event
  conditions never take effect in the shipped missions (docs/mission-runtime.md §3.1).
* **Multiplayer**: 511–516 and 666 / 777 are multiplayer ids (the 0x1ff–0x207 range, 0x29a; 777 has sixteen
  `PlayerN` slots). They are analysed like the others plus a "multiplayer session" feature.

## 5. What this report cannot know

* **Mission-specific tricks**: which AI flight actually destroys a target (the report assumes the player must),
  targets that only need to be damaged or that a script destroys after an event of another entity, and events
  that change the flow (e.g. a Play message telling the player to go home). A "yes" means every feature the
  mission touches exists, not that it was flown through.
* **Brain rules**: brains are classified by the actions they contain, not by evaluating their conditions (range
  gates, "target is the player"); a friendly fighter with an attack brain counts as combat AI even if it never
  meets an enemy.
* **What really needs combat**: a unit whose combat is enabled but that never gets within range still counts.
  Side 0 / 3 units are treated as neutral (they fight nobody).
* **Base missions** (bmis*) are included like the main file: their SAMs / AAA count even far from the route.
* **Jet choice**: a player who picks another flight on the TSD can make more missions playable; not counted
  (the Arming screen's loads of the default flight are).
* **Weather** (`0x46a` / `0x474`, probably wind) and the time-of-day option (+0x584, which overrides `0x460`) are
  not decoded; nothing about refuelling, carriers or a landing end condition exists in the data (there is no
  landing / time / waypoint end rule, docs/mission-runtime.md §5.1).
* Sizes are rough planning estimates, not measurements.
"#;
