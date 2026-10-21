//! The mission editor's intel and randomness (docs/mission-editor.md §14, §15): what the pilot sees before the flight
//! (entity flag 0x35c, the briefing's model links) and the chance / start spread rolled at each Fly. Both only write
//! the original's own data, so the runtime needs no change.

use std::collections::HashMap;

use iaf_formats::terrain_types::TerrainTypes;
use serde_json::{Value, json};

use crate::mission_edit::{
    Heights, Issue, SENSOR, TARGET, ground_issues, int, items, num, real, remove_entity, role, spawned, warning,
};

// --- Intel (§14) ---------------------------------------------------------------------------------------------------

/// Sets entity flag 0x35c ("known to the player": the pre-flight TSD shows the unit, docs/front-end.md §8.1) on the
/// entities `ids`.
pub fn set_known(mut mission: Value, ids: &[i64], known: bool) -> Value {
    for e in items(&mut mission, "entities").iter_mut().filter(|e| real(e) && ids.contains(&int(&e["0x1e"]))) {
        e["0x35c"] = json!(i64::from(known));
    }
    mission
}

/// The briefing links (briefings.json `entries`, type 2: the TSD's 3D-model window) the mission's unit types can
/// have: one per model with an info page (briefings.json `models`), in the order the types first appear. The title is
/// the one an original briefing gives that model, else the bdb object's name. `bdb` is the converted default6_1.bdb,
/// `briefings` the converted briefings.json.
pub fn intel_links(mission: &Value, bdb: &Value, briefings: &Value) -> Vec<Value> {
    let rows = |v: &Value, part: &str| v[part]["items"].as_array().cloned().unwrap_or_default();
    let objects: HashMap<i64, Value> = rows(bdb, "objects").into_iter().map(|o| (int(&o["0x1e"]), o)).collect();
    let present: HashMap<i64, String> = rows(bdb, "present")
        .iter()
        .map(|p| (int(&p["0x1e"]), p["0x64a"].as_str().unwrap_or("").to_lowercase().replace('\\', "/")))
        .collect();
    // Each model's title: the one the originals' briefings give it most often ("MiG-21" over "MiG-21s").
    let mut counts: HashMap<String, Vec<(Value, usize)>> = HashMap::new();
    for m in briefings["missions"].as_object().into_iter().flat_map(|m| m.values()) {
        for e in m["entries"].as_array().into_iter().flatten().filter(|e| int(&e["type"]) == 2) {
            let list = counts.entry(e["file"].as_str().unwrap_or("").to_lowercase()).or_default();
            match list.iter_mut().find(|(t, _)| *t == e["title"]) {
                Some(c) => c.1 += 1,
                None => list.push((e["title"].clone(), 1)),
            }
        }
    }
    let titles: HashMap<String, Value> =
        counts.into_iter().filter_map(|(f, l)| Some((f, l.iter().rev().max_by_key(|c| c.1)?.0.clone()))).collect();
    let mut out: Vec<Value> = vec![];
    for e in spawned(mission) {
        let Some(o) = objects.get(&int(&e["0x2c6"])) else { continue };
        let Some(path) = present.get(&int(&o["0x53c"])) else { continue };
        let key = format!("3dobjects/{}", path.trim_end_matches(".xfr").trim_end_matches(".x"));
        let file = format!("/{key}.x");
        if briefings["models"].get(&key).is_none() || out.iter().any(|l| l["file"] == file) {
            continue;
        }
        let name = [o["0x528"].as_str(), o["0x514"].as_str()].into_iter().flatten().find(|s| !s.is_empty());
        let title = titles.get(&file).cloned().unwrap_or_else(|| json!({"en": name, "he": name}));
        out.push(json!({"file": file, "title": title, "type": 2}));
    }
    out
}

// --- Randomness (§15) ----------------------------------------------------------------------------------------------

/// splitmix64: a small seeded generator, so a roll repeats for a seed.
struct Rng(u64);

impl Rng {
    /// Uniform in [0, 1).
    fn unit(&mut self) -> f64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        (z ^ (z >> 31)) as f64 / 18_446_744_073_709_551_616.0
    }
}

/// A unit or a whole flight, rolled as one: (its formation index, its entity ids, its flight number 0x3f2).
type Group = (Option<usize>, Vec<i64>, i64);

/// The groups of the spawned entities: each formation's placed members together, every other unit alone.
fn groups(mission: &Value) -> Vec<Group> {
    let ids: Vec<i64> = spawned(mission).filter(|e| num(&e["0x2e4"]) >= 0.0).map(|e| int(&e["0x1e"])).collect();
    let mut out: Vec<Group> = vec![];
    for (fo, f) in mission["formations"]["items"].as_array().into_iter().flatten().enumerate().filter(|(_, f)| real(f))
    {
        let members: Vec<i64> = f["members"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|m| int(&m["0x41a"]))
            .filter(|i| ids.contains(i))
            .collect();
        if !members.is_empty() {
            out.push((Some(fo), members, int(&f["0x3f2"])));
        }
    }
    let grouped: Vec<i64> = out.iter().flat_map(|g| g.1.clone()).collect();
    out.extend(ids.into_iter().filter(|i| !grouped.contains(i)).map(|i| (None, vec![i], 0)));
    out
}

/// A group's random setting: the first member's entry in `random` ({"<id>": {chance, spread_km}}), as (chance in
/// percent, spread in metres).
fn setting(random: &Value, ids: &[i64]) -> Option<(f64, f64)> {
    let r = ids.iter().find_map(|i| random.get(i.to_string()).filter(|v| v.is_object()))?;
    Some((r["chance"].as_f64().unwrap_or(100.0), r["spread_km"].as_f64().unwrap_or(0.0) * 1000.0))
}

/// The flights Alpha..Delta: the pilot flies one of them, so they always appear (their chance is not rolled).
fn player_flight(n: i64) -> bool {
    (1..=4).contains(&n)
}

/// Tries for a spread start that passes the ground check before the unit keeps its place.
const SPREAD_TRIES: usize = 64;

/// One roll of the random settings `random` ({"<entity id>": {chance (0..100 %), spread_km}}) with `seed`: a unit
/// or flight that does not appear is removed (`remove_entity`); a spread one starts at a random point within its
/// spread, a flight with its route moved by the same offset. A ground unit's new place passes the ground check
/// (`ground_issues`: on land, a ship on water, no steep slope) and takes the ground's height; after
/// `SPREAD_TRIES` failed samples it keeps its place. Aircraft keep their altitude. `bdb` gives the classes.
pub fn roll(
    mut mission: Value,
    random: &Value,
    seed: u64,
    bdb: &Value,
    heights: &mut Heights,
    surface: Option<&TerrainTypes>,
) -> Value {
    let class: HashMap<i64, i64> =
        bdb["objects"]["items"].as_array().into_iter().flatten().map(|o| (int(&o["0x1e"]), int(&o["0x5aa"]))).collect();
    let mut rng = Rng(seed);
    for (fo, ids, n) in groups(&mission) {
        let Some((chance, spread)) = setting(random, &ids) else { continue };
        if rng.unit() * 100.0 >= chance && !player_flight(n) {
            for id in ids {
                mission = remove_entity(mission, id);
            }
            continue;
        }
        if spread <= 0.0 {
            continue;
        }
        // The members' places and classes.
        let units: Vec<(i64, f64, f64, i64)> = spawned(&mission)
            .filter(|e| ids.contains(&int(&e["0x1e"])))
            .map(|e| {
                (int(&e["0x1e"]), num(&e["0x2e4"]), num(&e["0x2ee"]), *class.get(&int(&e["0x2c6"])).unwrap_or(&-1))
            })
            .collect();
        let points: Vec<(f64, f64)> = fo
            .and_then(|fo| mission["formations"]["items"][fo]["points"].as_array())
            .into_iter()
            .flatten()
            .map(|p| (num(&p[1]), num(&p[2])))
            .collect();
        let offset = (0..SPREAD_TRIES).find_map(|_| {
            let (r, a) = (spread * rng.unit().sqrt(), std::f64::consts::TAU * rng.unit());
            let (dx, dy) = (r * a.cos(), r * a.sin());
            let fits = units.iter().all(|&(id, x, y, c)| {
                heights.inside(x + dx, y + dy) && ground_issues(id, c, x + dx, y + dy, "", heights, surface).is_empty()
            }) && points.iter().all(|&(x, y)| heights.inside(x + dx, y + dy));
            fits.then_some((dx, dy))
        });
        let Some((dx, dy)) = offset else { continue };
        for (id, x, y, c) in units {
            let (x, y) = ((x + dx).round(), (y + dy).round());
            let ground = heights.ground_height(x, y);
            let air = [2, 3, 0x1c].contains(&c);
            let e = items(&mut mission, "entities").iter_mut().find(|e| real(e) && int(&e["0x1e"]) == id).unwrap();
            (e["0x2e4"], e["0x2ee"]) = (json!(x), json!(y));
            if let Some(g) = ground.filter(|_| !air) {
                e["0x2f8"] = json!(g.round());
            }
        }
        if let Some(fo) = fo {
            for p in items(&mut mission, "formations")[fo]["points"].as_array_mut().into_iter().flatten() {
                (p[1], p[2]) = (json!((num(&p[1]) + dx).round()), json!((num(&p[2]) + dy).round()));
            }
        }
    }
    mission
}

fn entity(mission: &Value, id: i64) -> &Value {
    spawned(mission).find(|e| int(&e["0x1e"]) == id).unwrap_or(&Value::Null)
}

/// The randomness warnings: a target that may not appear (when it does not, it is not needed to pass), and the
/// chance that no target appears at all (the mission cannot pass then).
pub fn random_issues(mission: &Value, random: &Value) -> Vec<Issue> {
    let mut out = vec![];
    let mut none = 1.0;
    let mut targets = 0;
    for (_, ids, n) in groups(mission) {
        let chance = setting(random, &ids).map_or(100.0, |s| s.0).clamp(0.0, 100.0);
        let t: Vec<i64> = ids.iter().copied().filter(|&i| role(entity(mission, i)) == TARGET).collect();
        if t.is_empty() {
            continue;
        }
        targets += 1;
        if chance < 100.0 && !player_flight(n) {
            none *= 1.0 - chance / 100.0;
            for i in t.into_iter().filter(|&i| int(&entity(mission, i)["0x2c6"]) != SENSOR) {
                out.push(warning(
                    i,
                    format!(
                        "a target that appears in {chance:.0}% of flights: when it does not, it is not needed to pass"
                    ),
                ));
            }
        } else {
            none = 0.0;
        }
    }
    if targets > 0 && none > 0.0 {
        out.push(warning(
            -1,
            format!("in {:.0}% of flights no target appears: the mission cannot pass then", none * 100.0),
        ));
    }
    out
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;
    use crate::mission_edit::conditions;

    fn read(a: &Path, name: &str) -> Value {
        serde_json::from_str(&std::fs::read_to_string(a.join(format!("converted/{name}.json"))).unwrap()).unwrap()
    }

    #[test]
    fn known_and_links() {
        let a = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        if !a.join("converted/missions/closesupport.json").exists() {
            eprintln!("skip: no converted missions (tools/setup-cli.sh)");
            return;
        }
        let m = read(&a, "missions/closesupport");
        let k = set_known(m.clone(), &[4, 5], true);
        assert_eq!((int(&k["entities"]["items"][3]["0x35c"]), int(&k["entities"]["items"][4]["0x35c"])), (1, 1));
        assert_eq!(int(&set_known(k, &[4], false)["entities"]["items"][3]["0x35c"]), 0);
        let links = intel_links(&m, &read(&a, "missions/default6_1.bdb"), &read(&a, "briefings/briefings"));
        let files: Vec<&str> = links.iter().map(|l| l["file"].as_str().unwrap()).collect();
        assert!(files.contains(&"/3dobjects/noncontrollableplanes/mig21/mig21_h.x"), "{files:?}");
        let mig = links.iter().find(|l| l["file"].as_str().unwrap().contains("mig21")).unwrap();
        assert_eq!(mig["title"]["en"], "MiG-21", "the originals' title");
        assert!(mig["title"]["he"].as_str().unwrap().contains("21"));
    }

    #[test]
    fn roll_chance_and_spread() {
        let a = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        let Some(mut h) = Heights::open(&a.join("converted/terrain/theatre")) else {
            eprintln!("skip: no converted terrain (tools/setup-cli.sh)");
            return;
        };
        let bdb = read(&a, "missions/default6_1.bdb");
        let types = std::fs::read(a.join("install/terraintype.dat")).ok().and_then(|d| TerrainTypes::parse(&d).ok());
        let s = types.as_ref();
        let m = read(&a, "missions/closesupport");
        let ids = |m: &Value| spawned(m).map(|e| int(&e["0x1e"])).collect::<Vec<_>>();
        let place = |m: &Value, id: i64| (num(&entity(m, id)["0x2e4"]), num(&entity(m, id)["0x2ee"]));
        // Tank t551 (4) never appears, t552 (5) always; the MiG-21 flight (21, 36) never; Alpha's chance is ignored.
        let r = json!({"4": {"chance": 0}, "5": {"chance": 100}, "21": {"chance": 0}, "1": {"chance": 0}});
        let out = roll(m.clone(), &r, 7, &bdb, &mut h, s);
        let left = ids(&out);
        assert!(!left.contains(&4) && left.contains(&5) && !left.contains(&21) && !left.contains(&36));
        assert!(left.contains(&1) && left.contains(&2), "Alpha always appears");
        assert_eq!(left.len(), ids(&m).len() - 3);
        let targets = |m: &Value| conditions(m, &Value::Null)["targets"].as_array().unwrap().len();
        assert_eq!(targets(&out), targets(&m) - 1, "a target that does not appear is not counted");
        assert!(random_issues(&m, &r).iter().any(|i| i.id == 4));
        assert!(random_issues(&m, &json!({})).is_empty());
        // Every unit 0 % but a 100 % tank: no "no target" warning; all targets 50 %: 0.5^n.
        let all: Value = ids(&m).iter().map(|i| (i.to_string(), json!({"chance": 50}))).collect();
        assert!(random_issues(&m, &all).iter().any(|i| i.id == -1));
        // Spread: within R, on land, at the ground's height; the same seed gives the same roll.
        let spread = json!({"3": {"spread_km": 5}, "21": {"spread_km": 10}});
        for seed in 0..20 {
            let out = roll(m.clone(), &spread, seed, &bdb, &mut h, s);
            let (x0, y0) = place(&m, 3);
            let (x, y) = place(&out, 3);
            assert!((x - x0).hypot(y - y0) <= 5001.0, "seed {seed}");
            let class = int(&bdb["objects"]["items"]
                .as_array()
                .unwrap()
                .iter()
                .find(|o| int(&o["0x1e"]) == 37)
                .unwrap()["0x5aa"]);
            assert!(ground_issues(3, class, x, y, "", &mut h, s).is_empty(), "seed {seed}: on land");
            assert_eq!(num(&entity(&out, 3)["0x2f8"]), h.ground_height(x, y).unwrap().round());
            // The MiG-21 flight moves as one, its route with it.
            let (d0, d1) = ((place(&out, 21).0 - place(&m, 21).0), (place(&out, 36).0 - place(&m, 36).0));
            assert!((d0 - d1).abs() <= 1.0);
            let fo = |m: &Value| num(&m["formations"]["items"][1]["points"][0][1]);
            assert!((fo(&out) - fo(&m) - d0).abs() <= 1.0);
            assert_eq!(out, roll(m.clone(), &spread, seed, &bdb, &mut h, s));
        }
    }
}
