//! The Mission Creator's mission 0x29a (docs/front-end.md §19.3): the converted mission files the exe loads for a
//! Mission Creator record (`iaf_formats::mcr`), changed as its mission document changes them while it loads
//! (`FUN_0058b620`, `FUN_0058f110`, `FUN_0058ed60`, `FUN_00590fe0`, `FUN_005916b0`, `FUN_0058d720`, `FUN_0058c9c0`)
//! and after (`FUN_004c286f`: the attack targets).

use iaf_formats::ini::{Ini, Section};
use iaf_formats::mcr::{Mission, WEATHER};
use serde_json::{Value, json};

/// Base index → the base mission, the target files' stem, the IAF.ibx key prefix, the exe's start-point defaults
/// (x, y, z, yaw).
const BASES: [(&str, &str, &str, [f64; 4]); 3] = [
    ("bmistlnf", "telnof", "TelNof", [312984.0, 500459.0, 59.0, 90.0]),
    ("bmisrdvd", "david", "RamatDavid", [356404.0, 602402.0, 28.0, 270.0]),
    ("bmisrmon", "ramon", "Ramon", [317439.0, 411135.0, 579.0, 230.0]),
];
/// TYPE index → IAF.ibx [MissionCreator] key and the default bdb object name (`FUN_0058d9e0`).
const TYPES: [(&str, &str); 16] = [
    ("F15", "F15"),
    ("F16", "F16"),
    ("f4E", "f4his"),
    ("f42000", "f42000"),
    ("Lavi", "Lavi"),
    ("CFIR", "CFIR"),
    ("mirage", "mirage"),
    ("Mig23", "Mig23"),
    ("MIG29", "mig29"),
    ("A4N", "A-4"),
    ("mig17", "mig17"),
    ("mig21", "mig21"),
    ("mig25", "mig25"),
    ("su22", "su22"),
    ("Su24", "Su24"),
    ("tu22", "tu22"),
];
/// AI index → [MissionCreator] leader key, exe default, wingman key, exe default (`FUN_0058e530`). Aces has no key.
const BRAINS: [(&str, &str, &str, &str); 5] = [
    ("AGRRESORSLead", "AA primary first", "AGRRESORSWing", "AA no primary wing"),
    ("DEFENDERSLead", "interceptor1", "DEFENDERSWing", "interceptor1"),
    ("BOMBERSLead", "AG LEAD", "BOMBERSWing", "agwing"),
    ("KAMIKAZIELead", "AGLevel", "KAMIKAZIEWing", "AGLevel"),
    ("", "AA leader", "", "AA wing"),
];
/// STARTING ALT. → metres added (`FUN_0058f110`, 0x6111dc..d4).
const ALT_ADD: [f64; 4] = [0.0, 1666.0, 3333.0, 5000.0];
/// WEAPONS → the weapon types (bdb 0x780) kept; None keeps all (`FUN_0058c9c0`).
const GUNS: [i64; 5] = [565, 620, 630, 540, 550];
const AAMS: [i64; 4] = [570, 580, 600, 610];
/// The ground categories (bdb object 0x5aa) a Bombers / Kamikaze formation attacks (`FUN_004c286f`).
const GROUND: [i64; 10] = [5, 6, 8, 9, 10, 11, 12, 13, 15, 16];

/// The weapon types the record allows; None = all (Multipurpose).
pub fn weapon_types(m: &Mission) -> Option<Vec<i64>> {
    match m.weapons {
        0 => Some(GUNS.to_vec()),
        2 => Some(GUNS.iter().chain(&AAMS).copied().collect()),
        _ => None,
    }
}

/// The converted files the exe loads for the record, by name (`FUN_0058b620`): mission, the base mission, the target
/// set, then missionlist's BMISAMMAN.
pub fn file_names(m: &Mission) -> Vec<String> {
    let b = BASES[m.base.clamp(0, 2) as usize];
    let mut v = vec!["mission".to_string(), b.0.to_string()];
    if (0..=4).contains(&m.target) {
        v.push(format!("{}{}", b.1, m.target + 1));
    }
    v.push("bmisamman".to_string());
    v
}

fn by_name<'a>(items: &'a Value, key: &str, name: &str) -> Option<&'a Value> {
    items["items"].as_array()?.iter().find(|o| o[key].as_str().is_some_and(|s| s.trim().eq_ignore_ascii_case(name)))
}

fn id(v: Option<&Value>) -> i64 {
    v.and_then(|o| o["0x1e"].as_i64()).unwrap_or(0)
}

struct Ctx<'a> {
    m: &'a Mission,
    ibx: &'a Ini,
    bdb: &'a Value,
    allowed: Option<Vec<i64>>,
    /// mission.mis's Player<digit> entities: (bdb object id, hardpoints), the pylon templates.
    templates: Vec<(i64, Vec<i64>)>,
}

impl Ctx<'_> {
    fn mc(&self) -> Option<&Section> {
        self.ibx.section("MissionCreator")
    }

    fn object_for(&self, kind: i32) -> Option<&Value> {
        let (key, def) = *TYPES.get(usize::try_from(kind).ok()?)?;
        let name = self.mc().and_then(|s| s.get(key)).unwrap_or(def);
        by_name(&self.bdb["objects"], "0x514", name)
    }

    fn brain(&self, ai: i32, leader: bool) -> i64 {
        let Some(&(lk, ld, wk, wd)) = usize::try_from(ai).ok().and_then(|i| BRAINS.get(i)) else { return 0 };
        let (k, d) = if leader { (lk, ld) } else { (wk, wd) };
        let name = if k.is_empty() { None } else { self.mc().and_then(|s| s.get(k)) }.unwrap_or(d);
        id(by_name(&self.bdb["brains"], "0x1f4", name))
    }

    /// The weapon type (0x780) of bdb weapon `w`.
    fn weapon_type(&self, w: i64) -> i64 {
        self.bdb["weapons"]["items"]
            .as_array()
            .and_then(|a| a.iter().find(|x| x["0x1e"].as_i64() == Some(w)))
            .and_then(|x| x["0x780"].as_i64())
            .unwrap_or(-1)
    }

    /// Pylons 0..8 from the template of the type (any pylon set), else the type's; 9..11 the type's; then the
    /// weapons the record removes leave their stations empty (`FUN_004b7ea3`).
    fn hardpoints(&self, obj: &Value) -> Value {
        let own: Vec<i64> = obj["armament"]["hardpoints"]
            .as_array()
            .map(|a| a.iter().map(|v| v.as_i64().unwrap_or(0)).collect())
            .unwrap_or_else(|| vec![0; 24]);
        let oid = obj["0x1e"].as_i64().unwrap_or(-1);
        let mut hp = own.clone();
        if let Some((_, t)) =
            self.templates.iter().find(|(o, t)| *o == oid && t.len() >= 18 && t[..18].chunks(2).any(|p| p[1] != 0))
        {
            hp[..18].copy_from_slice(&t[..18]);
        }
        if let Some(allowed) = &self.allowed {
            for p in hp.chunks_mut(2) {
                if p[0] != 0 && !allowed.contains(&self.weapon_type(p[0])) {
                    p[0] = 0;
                    p[1] = 0;
                }
            }
        }
        json!(hp)
    }

    fn base(&self) -> (&'static str, [f64; 4]) {
        let b = BASES[self.m.base.clamp(0, 2) as usize];
        let s = self.ibx.section("BlueTeam");
        let get = |k: &str, d: f64| s.and_then(|s| s.f32(&format!("{}{k}", b.2))).map_or(d, f64::from);
        (b.2, [get("X", b.3[0]), get("Y", b.3[1]), get("Z", b.3[2]), get("Yaw", b.3[3])])
    }

    /// Player<n> / Player<nn> (`FUN_0058ed60`, `FUN_0058f110`): position, altitude and heading.
    fn place(&self, n: usize, leader: bool) -> [f64; 4] {
        let (prefix, [bx, by, bz, yaw]) = self.base();
        let f = n - 1;
        let (mut x, mut y, mut z, mut h);
        if self.m.alt == 0 && n <= 2 {
            (x, y, z, h) = (bx, by, bz, yaw);
            let mut step = |bearing: f64| (x, y) = beside(x, y, bearing);
            if !leader {
                step(yaw + 90.0);
            }
            if n == 2 {
                step(yaw + 180.0);
            }
        } else {
            (x, y, z, h) = (if leader { bx + 1000.0 } else { bx }, by + n as f64 * 1000.0, bz, yaw);
        }
        if n >= 3 {
            x += if prefix == "RamatDavid" { -20000.0 } else { 25000.0 };
            z = 4000.0;
            if prefix != "Ramon" {
                h += 180.0;
            }
        }
        z += if f < 4 { ALT_ADD[self.m.alt.clamp(0, 3) as usize] } else { 3333.0 };
        [x, y, z, h]
    }

    /// The 4 waypoints of formation kind `n` (`FUN_005916b0`): [BlueTeam] / [RedTeam] keys of Alpha's base.
    fn route(&self, n: usize) -> (Value, Value) {
        let blue = n <= 2;
        let b = BASES[self.m.formations[0].base.clamp(0, 2) as usize].2;
        let s = self.ibx.section(if blue { "BlueTeam" } else { "RedTeam" });
        let get = |k: &str, i: usize| s.and_then(|s| s.f32(&format!("{b}{k}{i}"))).map_or(0.0, f64::from);
        let speed_action: [(f64, i64); 4] = if blue {
            [(if n == 1 { 0.0 } else { 40.0 }, 2), (120.0, 8), (200.0, 3), (400.0, 7)]
        } else {
            [(40.0, 3), (120.0, 8), (900.0, 3), (1000.0, 7)]
        };
        let mut points = vec![];
        let mut names = vec![];
        for (i, (sp, act)) in speed_action.iter().enumerate() {
            points.push(json!([i + 1, get("X", i), get("Y", i), get("Z", i), sp, act]));
            let name = s.and_then(|s| s.get(&format!("{b}Name{i}"))).unwrap_or("Waypoint");
            names.push(json!([i + 1, name]));
        }
        (json!(points), json!(names))
    }
}

/// 50 m from (x, y) toward `bearing` − 90°, as `FUN_0058eb40` steps a wingman: (0, 50, 0) turned about z by the bearing
/// (`FUN_0043d5b0`), i.e. (−50 sin, 50 cos).
pub fn beside(x: f64, y: f64, bearing: f64) -> (f64, f64) {
    let r = bearing.to_radians();
    (x - 50.0 * r.sin(), y + 50.0 * r.cos())
}

/// `Player<n>` (leader) / `Player<nn>` (wingman) → (n, leader); n from the last character (`FUN_0058ea00`).
fn player_slot(name: &str) -> Option<(usize, bool)> {
    let rest = name.strip_prefix("Player").or_else(|| name.strip_prefix("player"))?;
    let n = rest.chars().last()?.to_digit(10)? as usize;
    match rest.len() {
        1 => Some((n, true)),
        2 => Some((n, false)),
        _ => None,
    }
}

/// Keeps a `Sam…` / `Aaa…` site for the count chosen (`FUN_0058f110`): 0 none, 1 the "…1" ones, 2 all but "…2".
fn site_kept(name: &str, count: i32) -> bool {
    match count {
        i32::MIN..=0 => false,
        1 => name.ends_with('1'),
        2 => !name.ends_with('2'),
        _ => true,
    }
}

/// The mission files for record `m`: [(name, converted JSON)] in load order. `read(name)` gives a converted file
/// (`assets/converted/missions/<name>.json`), `ibx` is IAF.ibx, `bdb` the converted default6_1.bdb. The main file
/// gains `weapon_types` (the weapon types kept, absent = all) and its formation members `target_key`
/// ("<file index>:<entity id>") for targets in another file.
pub fn build(m: &Mission, read: &dyn Fn(&str) -> Option<Value>, ibx: &Ini, bdb: &Value) -> Vec<(String, Value)> {
    let mut files: Vec<(String, Value)> = file_names(m).into_iter().filter_map(|n| read(&n).map(|v| (n, v))).collect();
    let templates = files
        .first()
        .and_then(|(_, f)| f["entities"]["items"].as_array())
        .map(|a| {
            a.iter()
                .filter(|e| e["0x2bc"].as_str().and_then(player_slot).is_some())
                .map(|e| {
                    let hp = e["armament"]["hardpoints"].as_array().map(|h| h.iter().map(|v| v.as_i64().unwrap_or(0)));
                    (e["0x2c6"].as_i64().unwrap_or(-1), hp.map(|h| h.collect()).unwrap_or_default())
                })
                .collect()
        })
        .unwrap_or_default();
    let cx = Ctx { m, ibx, bdb, allowed: weapon_types(m), templates };
    let ground = ground_targets(&files, m, bdb);
    let by_kills = m.victory == 0;
    // formation kind n → (leader id, wingman id) in the main file.
    let mut members: [(i64, i64); 9] = [(-1, -1); 9];
    for (fi, (_, file)) in files.iter_mut().enumerate() {
        // After each file (FUN_0058ba00): every formation's member and target ids emptied.
        if let Some(fs) = file["formations"]["items"].as_array_mut() {
            for f in fs {
                if let Some(ms) = f["members"].as_array_mut() {
                    for mm in ms {
                        mm["0x41a"] = json!(-1);
                        mm["0x424"] = json!(-1);
                    }
                }
            }
        }
        let Some(items) = file["entities"]["items"].as_array_mut() else { continue };
        items.retain_mut(|e| {
            if e["0x14"].as_i64() != Some(0) {
                return true; // the editor's placeholder row
            }
            let name = e["0x2bc"].as_str().unwrap_or("").to_string();
            let lower = name.to_ascii_lowercase();
            if lower.starts_with("sam") && !site_kept(&name, m.sams)
                || lower.starts_with("aaa") && !site_kept(&name, m.aaa)
            {
                return false;
            }
            if by_kills {
                e["0x32a"] = json!(2);
            }
            let Some((n, leader)) = player_slot(&name) else { return true };
            if n == 0 || n > 8 || fi != 0 {
                return fi != 0;
            }
            let rec = m.formations[n - 1];
            if rec.count <= 0 || (!leader && rec.count == 1) {
                return false;
            }
            let Some(obj) = cx.object_for(rec.kind) else { return false };
            e["0x2c6"] = obj["0x1e"].clone();
            e["armament"]["hardpoints"] = cx.hardpoints(obj);
            e["0x2da"] = json!(cx.brain(rec.ai, leader));
            let [x, y, z, h] = cx.place(n, leader);
            (e["0x2e4"], e["0x2ee"], e["0x2f8"], e["0x302"]) = (json!(x), json!(y), json!(z), json!(h));
            if by_kills && n >= 3 {
                e["0x32a"] = json!(1); // single player: the red jets are the ones to kill
            }
            let eid = e["0x1e"].as_i64().unwrap_or(-1);
            if leader {
                members[n].0 = eid
            } else {
                members[n].1 = eid
            }
            true
        });
    }
    // Attack targets (FUN_004c286f): Bombers / Kamikaze the first ground "target" of another side in the entity
    // map's order; the others the enemy leader.
    let title = String::from_utf8_lossy(&m.name).into_owned();
    let start = [43200.0, 21600.0, 68400.0, 79200.0][m.time.clamp(0, 3) as usize];
    let main = &mut files[0].1;
    if let Some(misc) = main["misc"]["items"].as_array_mut().and_then(|a| a.first_mut()) {
        misc["0x44c"] = json!(title);
        misc["0x460"] = json!(start);
        // Ours, Extras "Mission Creator: Better": the wind chosen (the exe keeps the template's 10 kt from 270).
        if let Some(w) = m.wind {
            (misc["0x46a"], misc["0x474"]) = (json!(w.knots), json!(w.from));
            // And its weather (ours, docs/formats/mis.md misc `weather`); Default writes none, as the originals.
            if let Some(w) = WEATHER.get(m.weather as usize).filter(|w| !w.is_empty()) {
                misc["weather"] = json!(w);
            }
        }
    }
    if let Some(t) = &cx.allowed {
        main["weapon_types"] = json!(t);
    }
    let mut formations = vec![];
    for f in main["formations"]["items"].as_array().cloned().unwrap_or_default() {
        let n = f["0x3f2"].as_i64().unwrap_or(0);
        if f["0x14"].as_i64() != Some(0) {
            formations.push(f);
            continue;
        }
        // FUN_00590fe0: a formation without a leader is dropped (Echo..Other2 in single player).
        if !(1..=4).contains(&n) || members[n as usize].0 < 0 {
            continue;
        }
        let n = n as usize;
        let enemy = if n <= 2 { [3, 4] } else { [1, 2] }.iter().map(|&k| members[k].0).find(|&id| id >= 0);
        let ai = m.formations[n - 1].ai;
        let side = if n <= 2 { 1 } else { 2 };
        let target = if ai == 2 || ai == 3 {
            ground.iter().find(|g| g.2 != side).map(|g| (g.0, g.1))
        } else {
            enemy.map(|id| (0, id))
        };
        let mut f = f;
        let (points, names) = cx.route(n);
        f["points"] = points;
        f["names"] = names;
        let ids = [members[n].0, members[n].1];
        if let Some(ms) = f["members"].as_array_mut() {
            for (k, mm) in ms.iter_mut().enumerate().take(2) {
                mm["0x41a"] = json!(ids[k]);
                if let (Some((tf, tid)), true) = (target, ids[k] >= 0) {
                    mm["0x424"] = json!(if tf == 0 { tid } else { -1 });
                    mm["target_key"] = json!(format!("{tf}:{tid}"));
                }
            }
        }
        formations.push(f);
    }
    main["formations"]["items"] = json!(formations);
    files
}

/// The ground "target" entities a Bombers / Kamikaze formation can attack (`FUN_004c286f`): (file index, entity id,
/// side) in the order the exe walks its entity map (`FUN_00439f20`, a 17-bucket hash map; `FUN_004c1c90`). An entity's
/// key is {class, document index + 1, 0, 0} (`FUN_0058d860` → `FUN_004aa040`): the document appends each later file's
/// entities in reverse (`FUN_0058bce0`), the placeholder rows included. The bucket is (class << 10 | index) << 12 mod 17
/// (`FUN_00439b40`); a bucket lists its newest entry first. A candidate is spawned (the SAM / AAA filter), named with
/// "target" (case kept, `FUN_005de669`) and of a ground class (`GROUND`, the key's class).
fn ground_targets(files: &[(String, Value)], m: &Mission, bdb: &Value) -> Vec<(usize, i64, i64)> {
    let objects = &bdb["objects"]["items"];
    let class = |oid: &Value| {
        objects.as_array().and_then(|a| a.iter().find(|o| o["0x1e"] == *oid)).and_then(|o| o["0x5aa"].as_i64())
    };
    let mut found = vec![]; // (bucket, insertion, file, id, side)
    let mut index = 0i64;
    for (fi, (_, f)) in files.iter().enumerate() {
        let items = f["entities"]["items"].as_array().map(Vec::as_slice).unwrap_or_default();
        let order: Vec<&Value> = if fi == 0 { items.iter().collect() } else { items.iter().rev().collect() };
        for e in order {
            index += 1;
            let name = e["0x2bc"].as_str().unwrap_or("");
            let lower = name.to_ascii_lowercase();
            let filtered = lower.starts_with("sam") && !site_kept(name, m.sams)
                || lower.starts_with("aaa") && !site_kept(name, m.aaa);
            let Some(c) = class(&e["0x2c6"]) else { continue };
            if e["0x14"].as_i64() != Some(0) || filtered || !name.contains("target") || !GROUND.contains(&c) {
                continue;
            }
            let bucket = (((index & 0xffff) | (c & 0x3f) << 10) << 12) % 17;
            found.push((bucket, -index, fi, e["0x1e"].as_i64().unwrap_or(-1), e["0x2d0"].as_i64().unwrap_or(0)));
        }
    }
    found.sort();
    found.into_iter().map(|g| (g.2, g.3, g.4)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use iaf_formats::mcr::{Formation, Wind};
    use std::path::Path;

    fn assets() -> Option<std::path::PathBuf> {
        let a = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        a.join("converted/missions/mission.json").exists().then_some(a)
    }

    #[test]
    fn generation() {
        let Some(a) = assets() else {
            eprintln!("skip: no converted missions (tools/setup-cli.sh)");
            return;
        };
        let dir = a.join("converted/missions");
        let read = |n: &str| -> Option<Value> {
            serde_json::from_str(&std::fs::read_to_string(dir.join(format!("{n}.json"))).ok()?).ok()
        };
        let ibx = Ini::parse(&std::fs::read(a.join("install/iaf.ibx")).unwrap());
        let bdb = read("default6_1.bdb").unwrap();
        let mut m = Mission {
            name: b"Test".to_vec(),
            base: 2,
            time: 3,
            alt: 2,
            target: 3,
            sams: 1,
            aaa: 0,
            ..Default::default()
        };
        m.formations[0] = Formation { count: 2, kind: 8, ai: 0, base: 2 };
        m.formations[2] = Formation { count: 1, kind: 11, ai: 2, base: 2 };
        m.weapons = 2;
        m.victory = 1;
        let files = build(&m, &read, &ibx, &bdb);
        let names: Vec<&str> = files.iter().map(|f| f.0.as_str()).collect();
        assert_eq!(names, ["mission", "bmisrmon", "ramon4", "bmisamman"]);
        let main = &files[0].1;
        let ents = main["entities"]["items"].as_array().unwrap();
        let named = |n: &str| ents.iter().find(|e| e["0x2bc"] == n);
        let p1 = named("Player1").unwrap();
        assert_eq!(p1["0x2c6"], 2, "MiG-29 = bdb object 2");
        assert_eq!(p1["0x2da"], 31, "Aggressors leader: AA leader");
        assert_eq!(named("Player11").unwrap()["0x2da"], 51);
        // Ramon airborne: (X + 1000, Y + 1000, Z + 3333), yaw 230.
        assert_eq!(
            [&p1["0x2e4"], &p1["0x2ee"], &p1["0x2f8"], &p1["0x302"]],
            [317544.0 + 1000.0, 412180.0, 3913.0, 230.0]
        );
        assert!(named("Player2").is_none() && named("Player33").is_none(), "No 0 / 1 drop the jets");
        let p3 = named("Player3").unwrap();
        assert_eq!(p3["0x2c6"], 8, "MiG-21");
        assert_eq!(p3["0x2f8"], 4000.0 + 3333.0);
        assert_eq!(p3["0x2e4"], 317544.0 + 1000.0 + 25000.0);
        // Air To Air: the MiG-29's stores keep only AAMs, guns, chaff, flares.
        let hp: Vec<i64> =
            p1["armament"]["hardpoints"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect();
        let wtype = |w: i64| {
            bdb["weapons"]["items"].as_array().unwrap().iter().find(|x| x["0x1e"] == w).unwrap()["0x780"].as_i64()
        };
        let allowed = weapon_types(&m).unwrap();
        assert!(hp.chunks(2).all(|p| p[0] == 0 || allowed.contains(&wtype(p[0]).unwrap())), "{hp:?}");
        assert!(hp.chunks(2).any(|p| p[0] != 0 && AAMS.contains(&wtype(p[0]).unwrap())), "the AAMs stay");
        assert_eq!(main["misc"]["items"][0]["0x460"], 79200.0);
        assert_eq!(main["misc"]["items"][0]["0x44c"], "Test");
        let wind = |m: &Mission| {
            let f = build(m, &read, &ibx, &bdb);
            let misc = &f[0].1["misc"]["items"][0];
            [misc["0x46a"].clone(), misc["0x474"].clone(), misc["weather"].clone()]
        };
        assert_eq!(wind(&m), [json!(10), json!(270), Value::Null], "the template's wind, no weather");
        let gusty = Mission { wind: Some(Wind { knots: 20, from: 135 }), weather: 4, ..m.clone() };
        assert_eq!(wind(&gusty), [json!(20), json!(135), json!("random")], "Better writes its wind and weather");
        let fs = main["formations"]["items"].as_array().unwrap();
        let alpha = fs.iter().find(|f| f["0x3f2"] == 1).unwrap();
        assert_eq!(alpha["points"].as_array().unwrap().len(), 4);
        assert_eq!(alpha["points"][1][1], 331502.0, "Ramon Target waypoint");
        assert_eq!(alpha["members"][0]["0x424"], p3["0x1e"], "Aggressors attack the red leader");
        let charlie = fs.iter().find(|f| f["0x3f2"] == 3).unwrap();
        assert!(charlie["members"][0].get("target_key").is_none(), "red Bombers: the targets are red too, so none");
        assert!(!fs.iter().any(|f| f["0x3f2"] == 2 || f["0x3f2"] == 5), "Bravo (No 0) and Echo dropped");
        let sams: Vec<&str> = files[2].1["entities"]["items"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|e| e["0x2bc"].as_str())
            .filter(|n| n.starts_with("sam") || n.starts_with("AAA"))
            .collect();
        assert_eq!(sams, ["sam1"], "SAMs 1: the '1' site; AAA 0: none");
        // Runway start: Alpha on the base point, the wingman 50 m off at yaw + 90 as (−50 sin, 50 cos)
        // (FUN_0058eb40); Bravo another 50 m at yaw + 180.
        m.alt = 0;
        m.victory = 0;
        m.formations[1] = Formation { count: 2, kind: 0, ai: 2, base: 2 };
        let files = build(&m, &read, &ibx, &bdb);
        let ents = files[0].1["entities"]["items"].as_array().unwrap();
        let named = |n: &str| ents.iter().find(|e| e["0x2bc"] == n).unwrap();
        let p1 = named("Player1");
        assert_eq!([&p1["0x2e4"], &p1["0x2ee"], &p1["0x2f8"]], [317544.0, 411180.0, 580.0]);
        let num = |v: &Value| v.as_f64().unwrap();
        let off = |e: &Value| [num(&e["0x2e4"]) - 317544.0, num(&e["0x2ee"]) - 411180.0];
        let near = |a: [f64; 2], b: [f64; 2]| (a[0] - b[0]).abs() < 1e-6 && (a[1] - b[1]).abs() < 1e-6;
        let r = |deg: f64| [-50.0 * deg.to_radians().sin(), 50.0 * deg.to_radians().cos()];
        assert!(near(off(named("Player11")), r(320.0)), "{:?}", off(named("Player11")));
        assert!(near(off(named("Player2")), r(410.0)), "{:?}", off(named("Player2")));
        let w = r(320.0);
        let b = r(410.0);
        assert!(near(off(named("Player22")), [w[0] + b[0], w[1] + b[1]]));
        // Blue Bombers: Ramon's Radar Station set walked in the entity map's order: "target" (Radum1, id 7) first.
        let fs = files[0].1["formations"]["items"].as_array().unwrap();
        let bravo = fs.iter().find(|f| f["0x3f2"] == 2).unwrap();
        assert_eq!(bravo["members"][0]["target_key"], "2:7");
        assert_eq!(bravo["members"][1]["target_key"], "2:7");
        assert_eq!(named("Player3")["0x32a"], 1, "By Kills: red jets role 1");
        assert_eq!(p1["0x32a"], 2);
    }

    /// The entity map's order for each target set (FUN_00439b40 buckets over the appended document): the first blue
    /// Bombers target per base / target.
    #[test]
    fn ground_target_order() {
        let Some(a) = assets() else {
            eprintln!("skip: no converted missions (tools/setup-cli.sh)");
            return;
        };
        let dir = a.join("converted/missions");
        let read = |n: &str| -> Option<Value> {
            serde_json::from_str(&std::fs::read_to_string(dir.join(format!("{n}.json"))).ok()?).ok()
        };
        let bdb = read("default6_1.bdb").unwrap();
        let mut got = vec![];
        for base in 0..3 {
            for target in 1..5 {
                let m = Mission { base, target, sams: 3, aaa: 3, ..Default::default() };
                let files: Vec<(String, Value)> =
                    file_names(&m).into_iter().filter_map(|n| read(&n).map(|v| (n, v))).collect();
                let first = ground_targets(&files, &m, &bdb).into_iter().find(|g| g.2 != 1).map(|g| g.1);
                got.push(first.unwrap_or(-1));
            }
        }
        // Entity ids (item index + 1): Tel Nof / Ramat David 9 target5, 7 target, 7 target, 11 target3; Ramon 8
        // target2, 8 target0, 7 target, 12 target34.
        assert_eq!(got, [9, 7, 7, 11, 9, 7, 7, 11, 8, 8, 7, 12]);
    }
}
