//! Modern IAF's loadout editor (modern-iaf/docs/front-end.md §10, data-formats.md §3): the stores a pilot hangs on the
//! jet's stations on the briefing's Arming page. A loadout is real station number → the store's id (its weapon
//! record's) and how many hang there (a rack's: three Mk 82 on a TER); the unit record's `allowed` says which stores
//! each station takes and how many, its `pylons` the default. `IafBriefing` hands these rules to `menu/front_end.gd`;
//! `pilot_log` keeps each pilot's per jet.

use iaf_avionics::stores::{CHIN_LEFT, STATIONS, pylon_index};
use serde_json::{Map, Value, json};
use std::collections::BTreeMap;
use std::path::Path;

/// Real station number → (the store's id, how many hang there).
pub type Loadout = BTreeMap<u32, (String, u32)>;

/// The record's stations, by real number (the keys of `allowed`).
pub fn stations(unit: &Value) -> Vec<u32> {
    let mut v: Vec<u32> =
        unit["allowed"].as_object().into_iter().flatten().filter_map(|(k, _)| k.parse().ok()).collect();
    v.sort_unstable();
    v
}

/// The stores station `st` takes: each its id and how many it holds there (1, or its rack's count). An entry is the
/// id, or `{"id", "count", "rack", "rack_kg"}` for a rack.
pub fn allowed(unit: &Value, st: u32) -> Vec<(String, u32)> {
    unit["allowed"][st.to_string()]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|s| match s.as_str() {
            Some(id) => Some((id.to_string(), 1)),
            None => Some((s["id"].as_str()?.to_string(), s["count"].as_u64().unwrap_or(1) as u32)),
        })
        .collect()
}

/// How many of `id` station `st` holds (0: it does not take it).
fn holds(unit: &Value, st: u32, id: &str) -> u32 {
    allowed(unit, st).into_iter().find(|a| a.0 == id).map_or(0, |a| a.1)
}

/// The rack's weight on station `st` for store `id` (kg; 0 without a rack).
pub fn rack_kg(unit: &Value, st: u32, id: &str) -> f64 {
    rack(unit, st, id, "rack_kg")
}

/// Field `f` of the rack entry for store `id` on station `st` (0 without one).
fn rack(unit: &Value, st: u32, id: &str, f: &str) -> f64 {
    let list = unit["allowed"][st.to_string()].as_array();
    list.into_iter().flatten().find(|s| s["id"] == id).and_then(|s| s[f].as_f64()).unwrap_or(0.0)
}

/// The station across the jet from `st` (stations numbered from the left wing tip: 3 ↔ 7 of nine), none for the
/// middle one and the left chin hardpoint (pylon J, numbered after the wing's: the F-16's 5L).
pub fn mirror(unit: &Value, st: u32) -> Option<u32> {
    let all: Vec<u32> = stations(unit).into_iter().filter(|&s| letter(unit, s) != Some(CHIN_LEFT)).collect();
    let n = (all.last()? + 1).checked_sub(st)?;
    (n != st && all.contains(&n)).then_some(n)
}

/// The engine's station index of station `st`'s pylon letter (A..I 0..8, J 12: `iaf_avionics::stores::LETTERS`; the
/// record's `stations` where its numbers differ, else the number's letter, 10 → J), none for a station the engine's
/// pylons leave out.
pub fn letter(unit: &Value, st: u32) -> Option<usize> {
    let l = match unit["stations"].as_object() {
        Some(m) => m.get(&st.to_string())?.as_str()?.bytes().next()?,
        None => b'A' + u8::try_from(st.checked_sub(1)?).ok()?,
    };
    pylon_index(l)
}

/// The inventory entry of store `id`.
fn entry<'a>(unit: &'a Value, id: &str) -> Option<&'a Value> {
    unit["inventory"].as_array()?.iter().find(|e| e["weapon"].as_str() == Some(id))
}

/// The record's default loadout: its `pylons` on their real stations.
pub fn default(unit: &Value) -> Loadout {
    let mut lo = Loadout::new();
    for (k, p) in unit["pylons"].as_object().into_iter().flatten() {
        let Some(w) = p["weapon"].as_str() else { continue };
        let Some(i) = k.bytes().next().and_then(pylon_index) else { continue };
        if let Some(st) = stations(unit).into_iter().find(|&s| letter(unit, s) == Some(i)) {
            lo.insert(st, (w.to_string(), p["count"].as_u64().unwrap_or(1) as u32));
        }
    }
    lo
}

/// A loadout from JSON ({"3": "aim-9m"} or {"3": {"id": "mk-82", "count": 3}}), keeping only what the record allows
/// where it stands, at most as many as the station holds.
pub fn parse(unit: &Value, v: &Value) -> Loadout {
    let mut lo = Loadout::new();
    for (k, e) in v.as_object().into_iter().flatten() {
        let (id, n) = match e.as_str() {
            Some(id) => (id, 1),
            // A count written by Godot's JSON is a float (3.0).
            None => (e["id"].as_str().unwrap_or(""), e["count"].as_f64().unwrap_or(1.0) as u32),
        };
        if let Ok(st) = k.parse::<u32>() {
            let max = holds(unit, st, id);
            if max > 0 && n > 0 {
                lo.insert(st, (id.to_string(), n.min(max)));
            }
        }
    }
    lo
}

pub fn to_json(lo: &Loadout) -> Value {
    Value::Object(lo.iter().map(|(k, (id, n))| (k.to_string(), json!({"id": id, "count": n}))).collect::<Map<_, _>>())
}

/// How many of store `id` hang on the jet.
pub fn used(lo: &Loadout, id: &str) -> u32 {
    lo.values().filter(|v| v.0 == id).map(|v| v.1).sum()
}

/// How many of store `id` are left in the inventory (its record's `count` less those on the jet); none: no count.
pub fn left(unit: &Value, lo: &Loadout, id: &str) -> Option<i64> {
    Some(entry(unit, id)?["count"].as_i64()? - i64::from(used(lo, id)))
}

/// Hangs store `id` on station `st` (a full rack where the station holds several, as many as are left), and with
/// `pair` on its mirror station too where that takes it (real loadouts are symmetric); a store already there goes
/// back to the inventory. False (nothing changed) when `st` does not take it or none is left.
pub fn put(unit: &Value, lo: &mut Loadout, st: u32, id: &str, pair: bool) -> bool {
    let hang = |lo: &mut Loadout, s: u32| -> bool {
        let max = holds(unit, s, id);
        let back = lo.remove(&s);
        let free = left(unit, lo, id).map_or(i64::from(max), |n| n.min(i64::from(max)));
        if max == 0 || free < 1 {
            if let Some(b) = back {
                lo.insert(s, b);
            }
            return false;
        }
        lo.insert(s, (id.to_string(), free as u32));
        true
    };
    if !hang(lo, st) {
        return false;
    }
    if pair && let Some(m) = mirror(unit, st) {
        hang(lo, m);
    }
    true
}

/// Takes the store off station `st` (and with `pair` the same store off its mirror station): the store's id.
pub fn take(unit: &Value, lo: &mut Loadout, st: u32, pair: bool) -> Option<String> {
    let (id, _) = lo.remove(&st)?;
    if pair
        && let Some(m) = mirror(unit, st)
        && lo.get(&m).is_some_and(|v| v.0 == id)
    {
        lo.remove(&m);
    }
    Some(id)
}

/// The next count of the rack on station `st` (the "×n" badge): one fewer, from one back to the full rack (as many as
/// are left); with `pair` the mirror station's rack of the same store takes the same count. False when `st` holds no
/// rack.
pub fn cycle(unit: &Value, lo: &mut Loadout, st: u32, pair: bool) -> bool {
    let Some((id, n)) = lo.get(&st).cloned() else { return false };
    let max = holds(unit, st, &id);
    if max < 2 {
        return false;
    }
    let mut next = if n > 1 { n - 1 } else { max };
    if let Some(l) = left(unit, lo, &id) {
        next = next.min((l + i64::from(n)).max(1) as u32);
    }
    lo.insert(st, (id.clone(), next));
    if pair
        && let Some(m) = mirror(unit, st)
        && lo.get(&m).is_some_and(|v| v.0 == id)
    {
        let free = left(unit, lo, &id).map_or(next, |l| (l + i64::from(lo[&m].1)).clamp(1, i64::from(next)) as u32);
        lo.insert(m, (id, free.min(holds(unit, m, &lo[&m].0))));
    }
    true
}

/// Moves the store on `from` to `to` (with `pair`, its mirror's along); false (nothing changed) when `to` does not
/// take it.
pub fn shift(unit: &Value, lo: &mut Loadout, from: u32, to: u32, pair: bool) -> bool {
    let mut next = lo.clone();
    let Some(id) = take(unit, &mut next, from, pair) else { return false };
    if !put(unit, &mut next, to, &id, pair) {
        return false;
    }
    *lo = next;
    true
}

/// The stores' weight on a jet, the one rule of both games' arming checks (reborn's `mission_weapons.gd` `check`,
/// FUN_00507bd0 / FUN_00507480, in lb; the sim's `briefing::arming`, in kg): `base` plus every store's mass, each
/// wing's share and the rolling moment. A store is (arm, mass): its distance from the jet's middle, + toward the
/// right wing (any unit; the 1998 rule counts sides only, ±1), 0 on the middle.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Weight {
    pub total: f64,
    pub left: f64,
    pub right: f64,
    /// Σ mass × arm: + the right wing heavier.
    pub moment: f64,
}

pub fn weigh(base: f64, stores: &[(f64, f64)]) -> Weight {
    let mut w = Weight { total: base, left: 0.0, right: 0.0, moment: 0.0 };
    for &(arm, m) in stores {
        w.total += m;
        w.moment += m * arm;
        if arm > 0.0 {
            w.right += m;
        } else if arm < 0.0 {
            w.left += m;
        }
    }
    w
}

/// The stores on the pylons as the engine's armament holds them, [weapon number, count, rack kg, rack drag, internal]
/// by station index × 13 (A..I 0..8, J 12; 9..11 the gun, chaff and flares, left empty) (`Settings.arm_loadouts`, player_weapons.gd `_armed`, stores.gd `setup`): each store's weapon
/// record's `sim` (a `modern_weapons.gd` record built on it, the GBU-31's 1003), else its `number`, its rack's
/// `rack_kg` / `rack_drag` (0 without a rack), and 1 on a station inside a weapons bay (the record's `internal`: its
/// stores and rack add no drag, the rack's drag written 0), else 0; a station the engine has no pylon for carries nothing.
pub fn sim_load(unit: &Value, weapons: &Path, lo: &Loadout) -> Vec<Value> {
    let mut out = vec![json!([0, 0, 0.0, 0.0, 0]); STATIONS];
    let bays = unit["internal"].as_array();
    for (&st, (id, n)) in lo {
        let rec: Option<Value> =
            std::fs::read(weapons.join(format!("{id}.json"))).ok().and_then(|b| serde_json::from_slice(&b).ok());
        let number = rec.and_then(|w| w["sim"].as_i64().or(w["number"].as_i64()));
        if let (Some(i), Some(num)) = (letter(unit, st), number) {
            let bay = bays.is_some_and(|b| b.iter().any(|s| s.as_u64() == Some(st.into())));
            let rack_drag = if bay { 0.0 } else { rack(unit, st, id, "rack_drag") };
            out[i] = json!([num, n, rack(unit, st, id, "rack_kg"), rack_drag, i32::from(bay)]);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unit(id: &str) -> Value {
        let p = Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("../../modern-iaf/data/db/units/{id}.json"));
        serde_json::from_slice(&std::fs::read(p).unwrap()).unwrap()
    }

    fn weapons() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data/db/weapons")
    }

    fn at(lo: &Loadout, st: u32) -> (&str, u32) {
        lo.get(&st).map_or(("", 0), |(id, n)| (id.as_str(), *n))
    }

    #[test]
    fn sufa_rules_pairs_racks_and_sim_load() {
        let u = unit("f16i");
        let mut lo = default(&u);
        assert_eq!(lo.len(), 8);
        assert_eq!(at(&lo, 4), ("tank-370", 1));
        assert_eq!(mirror(&u, 3), Some(7));
        assert_eq!(mirror(&u, 9), Some(1));
        // A tank on a missile station is refused; a bomb on 3 fills 7 too, or 3 alone with the modifier.
        assert!(!put(&u, &mut lo, 2, "tank-370", true));
        assert!(!put(&u, &mut lo, 3, "python-5", true));
        assert!(put(&u, &mut lo, 3, "mk-84", true));
        assert_eq!((at(&lo, 3), at(&lo, 7)), (("mk-84", 1), ("mk-84", 1)));
        assert!(put(&u, &mut lo, 3, "aim-120", false));
        assert_eq!((at(&lo, 3), at(&lo, 7)), (("aim-120", 1), ("mk-84", 1)));
        // A TER: three Mk 82 on a station, counted per bomb; two GBU-38 on a BRU-57/A.
        assert!(put(&u, &mut lo, 4, "mk-82", true));
        assert_eq!((at(&lo, 4), at(&lo, 6)), (("mk-82", 3), ("mk-82", 3)));
        assert_eq!(used(&lo, "mk-82"), 6);
        assert_eq!(rack_kg(&u, 4, "mk-82"), 47.6);
        assert!(put(&u, &mut lo, 7, "gbu-38", false));
        assert_eq!(at(&lo, 7), ("gbu-38", 2));
        // The badge: 3 → 2 → 1 → 3 on the TER, the pair along; 2 → 1 → 2 on the BRU-57/A; none on a single store.
        assert!(cycle(&u, &mut lo, 4, true));
        assert_eq!((at(&lo, 4), at(&lo, 6)), (("mk-82", 2), ("mk-82", 2)));
        assert!(cycle(&u, &mut lo, 4, true) && cycle(&u, &mut lo, 4, true));
        assert_eq!((at(&lo, 4), at(&lo, 6)), (("mk-82", 3), ("mk-82", 3)));
        assert!(cycle(&u, &mut lo, 7, false) && at(&lo, 7) == ("gbu-38", 1));
        assert!(cycle(&u, &mut lo, 7, false) && at(&lo, 7) == ("gbu-38", 2));
        assert!(!cycle(&u, &mut lo, 9, true));
        // Off the jet: the pair goes when the same store hangs across, else the one.
        assert_eq!(take(&u, &mut lo, 4, true).as_deref(), Some("mk-82"));
        assert!(!lo.contains_key(&4) && !lo.contains_key(&6));
        assert_eq!(take(&u, &mut lo, 3, true).as_deref(), Some("aim-120"));
        assert_eq!(at(&lo, 7), ("gbu-38", 2));
        // A move: 7's JDAMs cannot go to 8; 9's missile goes to 3 (and 1's to 7 with the pair).
        assert!(!shift(&u, &mut lo, 7, 8, false));
        assert!(shift(&u, &mut lo, 9, 3, true));
        assert_eq!((lo.get(&9), lo.get(&1), at(&lo, 3), at(&lo, 7)), (None, None, ("aim-9m", 1), ("aim-9m", 1)));
        assert!(put(&u, &mut lo, 4, "mk-82", false));
        let load = sim_load(&u, &weapons(), &lo);
        assert_eq!(load[2], json!([1, 1, 0.0, 0.0, 0])); // C: an AIM-9M (number 1)
        assert_eq!(load[3], json!([4, 3, 47.6, 4.2, 0])); // D: three Mk 82 (number 4) on their TER-9/A
        assert_eq!(load[0], json!([0, 0, 0.0, 0.0, 0])); // A: empty
        // The JDAM flies as modern_weapons.gd's record; two GBU-38 on the BRU-57/A carry its 265 lb.
        assert!(put(&u, &mut lo, 3, "gbu-31", false));
        assert_eq!(sim_load(&u, &weapons(), &lo)[2], json!([1003, 1, 0.0, 0.0, 0]));
        assert!(put(&u, &mut lo, 7, "gbu-38", false));
        assert_eq!(sim_load(&u, &weapons(), &lo)[6], json!([1006, 2, 120.2, 5.3, 0]));
        // A saved loadout keeps only what the record allows, as many as the station holds.
        let p = parse(&u, &json!({"2": "tank-370", "4": "tank-370", "6": {"id": "mk-82", "count": 9}, "x": "mk-84"}));
        assert_eq!(to_json(&p), json!({"4": {"id": "tank-370", "count": 1}, "6": {"id": "mk-82", "count": 3}}));
    }

    #[test]
    fn chin_stations_take_their_own_pods() {
        // The Sufa's LANTIRN navigation pod and the Barak's Pathfinder on 10 (5L, pylon J: station index 12) only;
        // the Litening on 5 (5R) only; neither chin station has a mirror.
        for (id, nav, number) in [("f16i", "lantirn-nav", 20), ("f16d", "pathfinder", 21)] {
            let u = unit(id);
            let mut lo = default(&u);
            assert_eq!((letter(&u, 10), letter(&u, 5), letter(&u, 9)), (Some(12), Some(4), Some(8)), "{id}");
            assert_eq!((mirror(&u, 10), mirror(&u, 5), mirror(&u, 1)), (None, None, Some(9)), "{id}");
            assert!(!put(&u, &mut lo, 5, nav, true) && !put(&u, &mut lo, 10, "litening", true), "{id}");
            assert!(put(&u, &mut lo, 10, nav, true) && put(&u, &mut lo, 5, "litening", true), "{id}");
            assert_eq!((at(&lo, 10), at(&lo, 5)), ((nav, 1), ("litening", 1)), "{id}");
            let load = sim_load(&u, &weapons(), &lo);
            assert_eq!(load.len(), STATIONS);
            assert_eq!((load[12][0].as_i64(), load[4][0].as_i64()), (Some(number), Some(19)), "{id}");
            let a = crate::briefing::arming(&u, &weapons(), &lo);
            assert_eq!((a["labels"]["10"].as_str(), a["labels"]["5"].as_str()), (Some("5L"), Some("5R")), "{id}");
            assert_eq!((a["pylons"]["10"].as_i64(), a["slots"]["10"]["pylon"].as_i64()), (Some(12), Some(12)), "{id}");
            assert!(a["inventory"].as_array().unwrap().iter().any(|e| e["id"] == nav && e["group"] == "pod"));
        }
    }

    #[test]
    fn adir_bays_and_racks() {
        let u = unit("f35i");
        let mut lo = default(&u);
        assert_eq!(to_json(&lo), json!({"5": {"id": "aim-120", "count": 1}, "7": {"id": "aim-120", "count": 1}}));
        assert_eq!(mirror(&u, 4), Some(8));
        assert!(!put(&u, &mut lo, 5, "gbu-31", true));
        // The AIM-9X on the wingtips only, not in the bays.
        assert!(!put(&u, &mut lo, 5, "aim-9x", true));
        assert!(put(&u, &mut lo, 1, "aim-9x", true));
        assert!(put(&u, &mut lo, 4, "gbu-39", true));
        assert_eq!((at(&lo, 4), at(&lo, 8)), (("gbu-39", 4), ("gbu-39", 4)));
        let load = sim_load(&u, &weapons(), &lo);
        // A / I the AIM-9X (1001), C / G four GBU-39 (1007), D / F the AIM-120 (3).
        let ids: Vec<(i64, i64)> =
            [0, 8, 2, 6, 3].iter().map(|&i| (load[i][0].as_i64().unwrap(), load[i][1].as_i64().unwrap())).collect();
        assert_eq!(ids, [(1001, 1), (1001, 1), (1007, 4), (1007, 4), (3, 1)]);
        assert_eq!(load[2][2], 147.0, "the BRU-61/A");
        assert_eq!((load[2][4].as_i64(), load[0][4].as_i64()), (Some(1), Some(0)), "C in the bay, A on the wingtip");
        assert_eq!(load[2][3], 0.0, "no rack drag in the bay");
    }

    #[test]
    fn modern_records_carry_their_public_figures() {
        // id → its modern_weapons.gd record, then each figure within its public range (real-weapons.md §1.6).
        type Range = (&'static str, f64, f64);
        let figures: [(&str, i64, &[Range]); 5] = [
            ("aim-9x", 1001, &[("range_km", 10.0, 35.4), ("mach", 2.5, 3.0), ("g_limit", 60.0, 60.0)]),
            ("python-5", 1002, &[("range_km", 20.0, 40.0), ("mach", 4.0, 4.0), ("warhead_kg", 11.0, 11.0)]),
            ("spice-1000", 1009, &[("range_km", 60.0, 125.0)]),
            ("spice-2000", 1011, &[("range_km", 60.0, 60.0)]),
            ("delilah", 1012, &[("range_km", 250.0, 250.0), ("mach", 0.3, 0.85), ("warhead_kg", 30.0, 30.0)]),
        ];
        for (id, sim, checks) in figures {
            let w: Value =
                serde_json::from_slice(&std::fs::read(weapons().join(format!("{id}.json"))).unwrap()).unwrap();
            assert_eq!(w["sim"].as_i64(), Some(sim), "{id}");
            for &(f, lo, hi) in checks {
                let v = w[f].as_f64().unwrap_or_else(|| panic!("{id}: {f}"));
                assert!((lo..=hi).contains(&v), "{id}: {f} {v} outside {lo}..{hi}");
                assert!(w["sources"][f].as_str().is_some_and(|s| !s.is_empty()), "{id}: {f} unsourced");
            }
        }
    }

    #[test]
    fn weigh_sums_sides_and_moment() {
        // Reborn's sides (±1): 2 × 500 lb on the right wing, 300 on the middle, 400 on the left.
        let w = weigh(20000.0, &[(1.0, 1000.0), (0.0, 300.0), (-1.0, 400.0)]);
        assert_eq!(w, Weight { total: 21700.0, left: 400.0, right: 1000.0, moment: 600.0 });
        assert_eq!(weigh(5.0, &[]), Weight { total: 5.0, left: 0.0, right: 0.0, moment: 0.0 });
    }

    #[test]
    fn one_sided_loads_warn_past_the_sufas_limit() {
        let u = unit("f16i");
        let mut lo = default(&u);
        // One tank off: 1,120 kg of fuel and 201 kg empty on the left wing's station 4 alone, under the 3,459 kg·m limit.
        take(&u, &mut lo, 6, false);
        let a = crate::briefing::arming(&u, &weapons(), &lo);
        assert_eq!((a["imbalance_kg"].as_f64(), a["imbalanced"].as_bool()), (Some(1321.0), Some(false)));
        // An MK-84 on 3 too: past it; a warning, not a block.
        assert!(put(&u, &mut lo, 3, "mk-84", false));
        let a = crate::briefing::arming(&u, &weapons(), &lo);
        assert_eq!((a["imbalanced"].as_bool(), a["blocked"].as_bool()), (Some(true), Some(false)));
        assert!(a["moment_kgm"].as_f64().unwrap() < -3459.0, "{}", a["moment_kgm"]);
        assert_eq!(a["balance"].as_f64(), Some(-1.0), "the left wing heavier, past the limit");
        assert_eq!(a["slots"]["3"]["kg"].as_f64(), Some(925.0), "the Mk 84's weight on its station");
        assert_eq!(a["positions"]["3"], "mid");
    }

    #[test]
    fn laser_bombs_need_the_pod() {
        let u = unit("f16i");
        let mut lo = default(&u);
        assert!(put(&u, &mut lo, 3, "gbu-12", true));
        let a = crate::briefing::arming(&u, &weapons(), &lo);
        assert_eq!(a["blocked"], true, "a laser bomb without a designator: Fly off");
        assert_eq!(a["unmet"], json!([{"weapon": "gbu-12", "need": "laser", "store": "litening", "station": 5}]));
        assert!(put(&u, &mut lo, 5, "litening", false));
        let a = crate::briefing::arming(&u, &weapons(), &lo);
        assert_eq!((a["blocked"].as_bool(), a["unmet"].as_array().map(Vec::len)), (Some(false), Some(0)));
        // The F-35I's EOTS is a built-in pod (its aircraft definition's `flir`).
        let mut adir = unit("f35i");
        adir["allowed"]["4"] = json!(["gbu-12"]);
        let lo = parse(&adir, &json!({"4": "gbu-12"}));
        assert_eq!(crate::briefing::arming(&adir, &weapons(), &lo)["unmet"], json!([]));
    }

    #[test]
    fn a_range_lesson_refuses_a_load_without_bombs() {
        // The user, 2026-11-18: a saved load with no bombs flew the range lesson (two ground kills).
        let read = |p: &str| -> Value {
            let p = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data").join(p);
            serde_json::from_slice(&std::fs::read(p).unwrap()).unwrap()
        };
        let (u, m) = (unit("f16i"), read("missions/ramon_range.json"));
        let air = parse(&u, &json!({"1": "aim-9m", "2": "aim-9m", "8": "aim-9m", "9": "aim-9m"}));
        let a = crate::briefing::mission_arming(&u, &weapons(), &air, &m);
        assert_eq!(a["blocked"], true, "no bombs on the range: Fly off");
        assert_eq!(a["unmet"], json!([{"weapon": null, "need": "ground", "store": "mk-82", "station": 3}]));
        assert_eq!(crate::briefing::mission_arming(&u, &weapons(), &air, &Value::Null)["blocked"], false);
        let own = parse(&u, &m["loadout"]);
        assert_eq!(crate::briefing::mission_arming(&u, &weapons(), &own, &m)["unmet"], json!([]));
    }

    #[test]
    fn every_default_load_can_be_employed() {
        // Every unit's own load (the AI's, and a mission's without a load of its own) meets its needs.
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data/db/units");
        for f in std::fs::read_dir(dir).unwrap() {
            let u: Value = serde_json::from_slice(&std::fs::read(f.unwrap().path()).unwrap()).unwrap();
            let a = crate::briefing::arming(&u, &weapons(), &default(&u));
            assert_eq!(a["unmet"], json!([]), "{}", u["id"]);
        }
    }

    /// Every mission's load for its player's jet (its own `loadout`, else the unit record's) hangs as written, can
    /// be employed and flown, and a range lesson's can pass the lesson (the user, 2026-11-18: the range asked for
    /// two ground kills with no bomb aboard): a gun or a missile for each air kill, a bomb for each ground kill.
    #[test]
    fn every_lesson_load_can_pass_its_lesson() {
        let kind = |w: &str| -> String {
            let v: Value =
                serde_json::from_slice(&std::fs::read(weapons().join(format!("{w}.json"))).unwrap()).unwrap();
            v["kind"].as_str().unwrap().to_string()
        };
        let missions = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data/missions");
        let mut ranges = 0;
        for f in std::fs::read_dir(missions).unwrap() {
            let m: Value = serde_json::from_slice(&std::fs::read(f.unwrap().path()).unwrap()).unwrap();
            let (id, u) = (&m["id"], unit(m["start"]["unit"].as_str().unwrap()));
            let lo = match m["loadout"].as_object() {
                Some(own) => {
                    let lo = parse(&u, &m["loadout"]);
                    assert_eq!(lo.len(), own.len(), "{id}: a store its station does not take");
                    let godot = json!({"3": {"id": "mk-82", "count": 3.0}});
                    assert_eq!(parse(&unit("f16i"), &godot)[&3].1, 3, "a count as Godot's JSON writes it");
                    for (st, e) in own {
                        let n = e["count"].as_u64().unwrap_or(1) as u32;
                        assert_eq!(lo[&st.parse().unwrap()].1, n, "{id}: station {st} holds fewer");
                    }
                    lo
                }
                None => default(&u),
            };
            let a = crate::briefing::arming(&u, &weapons(), &lo);
            assert_eq!((&a["unmet"], &a["blocked"], &a["over"]), (&json!([]), &json!(false), &json!(false)), "{id}");
            let count = |want: &dyn Fn(&str) -> bool| -> u64 {
                lo.values().filter(|(w, _)| want(&kind(w))).map(|(_, n)| u64::from(*n)).sum()
            };
            let rounds =
                u["loadout"].as_object().unwrap().iter().any(|(w, n)| kind(w) == "gun" && n.as_i64() > Some(0));
            let t = &m["training"];
            if t["kind"] == "range" {
                ranges += 1;
                let (air, ground) = (t["air_kills"].as_u64().unwrap_or(0), t["ground_kills"].as_u64().unwrap_or(0));
                assert!(rounds || count(&|k| k.ends_with("missile")) >= air, "{id}: {air} air kills");
                assert!(count(&|k| k.ends_with("bomb")) >= ground, "{id}: {ground} ground kills, no bombs for them");
            }
        }
        assert_eq!(ranges, 3, "the three jets' range lessons");
    }

    #[test]
    fn heaviest_loadouts_stay_under_the_maximum() {
        // No sourced loadout reaches a jet's maximum: the heaviest store on every station; a lower maximum is over.
        let heavy: [(&str, &[(u32, &str)]); 2] = [
            ("f16i", &[(1, "aim-120"), (2, "aim-120"), (3, "gbu-31"), (4, "tank-600")]),
            ("f35i", &[(1, "aim-9x"), (3, "gbu-31"), (4, "gbu-31"), (5, "aim-120")]),
        ];
        for (id, stores) in heavy {
            let mut u = unit(id);
            let mut lo = default(&u);
            for &(s, w) in stores {
                assert!(put(&u, &mut lo, s, w, true), "{id} {s} {w}");
            }
            let a = crate::briefing::arming(&u, &weapons(), &lo);
            assert_eq!(a["over"], false, "{id}: {}", a["takeoff_kg"]);
            u["max_takeoff_kg"] = json!(a["takeoff_kg"].as_f64().unwrap() - 1.0);
            assert_eq!(crate::briefing::arming(&u, &weapons(), &lo)["over"], true);
        }
    }
}
