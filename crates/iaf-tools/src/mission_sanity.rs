//! The mission editor's sanity check (docs/mission-editor.md §16): warnings for a mission that flies but may not play
//! as meant. A blue flight short of fuel for its route, a target the SAM rings cover from every side, a route without
//! points, a target no blue flight's loadout can destroy. The limits are inferred and tuned on the original missions.

use std::collections::HashMap;
use std::path::Path;

use iaf_avionics::stores::{Category, STATIONS, Station, Stores, Weapon, loadout};
use iaf_flight::{DataSet, Params, atmosphere, data_set};
use serde_json::Value;

use crate::mission_edit::Issue;

/// The share of a flight's fuel its route may burn before it warns: the rest is for the take-off, the climb, the
/// fight and a reserve (inferred, docs/mission-editor.md §16.1).
const FUEL_SHARE: f64 = 0.8;
/// A leg's planned speed (m/s) as the AI flies a waypoint (docs/ai.md §7.2, `FUN_005d6dc0`): d / (T − T_prev)
/// clamped to [180, 300], 275 without an arrival time.
const SPEED_MIN: f64 = 180.0;
const SPEED_MAX: f64 = 300.0;
const SPEED_NONE: f64 = 275.0;
/// A route that ends this near (m) its start ends at home: no leg back.
const HOME: f64 = 10_000.0;
/// Waypoint action 7: land (docs/ai.md §7.2).
const LAND: i64 = 7;
/// SAM ring radius (m) by bdb type code (0x5b4), as the TSD draws them (`tsd.gd SAM_RING`): SA-2, Hawk, SA-3,
/// SA-6.
const SAM_RING: [(i64, f64); 4] = [(290, 37080.0), (340, 37080.0), (300, 16686.0), (320, 22248.0)];
/// How far (m) from a target an attack starts (inferred): the target is covered from every side when every point at
/// this distance lies inside a SAM ring. SAMs within `LOCAL` m of the target are its own site's defence, left out.
/// Both tuned on the originals (docs/mission-editor.md §16).
const APPROACH: f64 = 15_000.0;
const LOCAL: f64 = 5000.0;
const BEARINGS: usize = 36;
/// bdb object classes (0x5aa): aircraft, the SAM sites, the sensor object.
const AIR: [i64; 3] = [2, 3, 0x1c];
const SAM_CLASS: i64 = 8;
const SENSOR: i64 = 130;
const TARGET: i64 = 1;
const G: f64 = 9.806;
/// N per lbf (the thrust table is in lbf, §4.1).
const LBF: f64 = 4.4479;

fn int(v: &Value) -> i64 {
    v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)).unwrap_or(-1)
}

fn num(v: &Value) -> f64 {
    v.as_f64().unwrap_or(0.0)
}

fn real(v: &Value) -> bool {
    int(&v["0x14"]) == 0
}

fn warning(id: i64, text: String) -> Issue {
    Issue { id, level: "warning", text }
}

/// The flight model's parameters of a bdb type code (0x5b4), the original data set; None for a type without them.
/// The Kurnass 2000 (200) flies the F-4's section (docs/real-aircraft.md §4).
pub fn params(install: &Path, code: i64) -> Option<Params> {
    let code = if code == 200 { 120 } else { code };
    let t = data_set::TYPES.iter().find(|t| i64::from(t.type_code) == code)?;
    iaf_flight::load_with(install, t.name, DataSet::Original).ok().map(|(p, _)| p)
}

/// Fuel (kg) per metre of level flight at `alt` m and `v` m/s for mass `m` kg and stores drag `di` (×1e-4 applied):
/// the drag of the flight model's polar at 1 g (§4.3), the throttle whose thrust (§4.1) matches it, and that
/// throttle's fuel flow. More drag than full afterburner gives burns at full afterburner.
pub fn burn_per_m(p: &Params, alt: f64, v: f64, m: f64, di: f64) -> f64 {
    let (alt32, v32) = (alt as f32, v as f32);
    let qs = f64::from(atmosphere::q_s(alt32, v32, p.wing_area));
    let mach = v / f64::from(atmosphere::air(alt32).sound);
    let (span, area) = (f64::from(p.wing_span), f64::from(p.wing_area));
    let k_ind = 1.0 / (std::f64::consts::PI * span * span / area * 0.85);
    let cl = m * G / qs;
    let drag = (f64::from(p.plane_di) + di + k_ind * cl * cl) * qs / LBF;
    let a = (alt * 5e-5).clamp(0.0, 1.0);
    let mm = (mach / 1.2).clamp(0.0, 1.0);
    let lerp = |t: f64, x: f32, y: f32| f64::from(x) + (f64::from(y) - f64::from(x)) * t;
    let th = |k: usize| {
        let lo = lerp(mm, p.thrust[0][0][k], p.thrust[1][0][k]);
        let hi = lerp(mm, p.thrust[0][1][k], p.thrust[1][1][k]);
        lo + (hi - lo) * a
    };
    let (t0, t1) = (th(0), th(1));
    let k = ((drag - t0) / (t1 - t0).max(1e-6)).max(0.0);
    // The throttle that gives k (§4.1): with an afterburner k = 0.05 + 0.7432432·thr below 0.75, AB1 k = 0.875 from
    // 0.75, AB2 k = 1 from 0.875; without, k = (thr − 0.2)·1.25.
    let (thr, k) = if p.has_afterburner {
        if k <= 0.6 {
            (((k - 0.05) / 0.743_243_2).max(0.0), k)
        } else if k <= 0.875 {
            (0.75, 0.875)
        } else {
            (0.875, 1.0)
        }
    } else {
        ((k / 1.25 + 0.2).min(1.0), k)
    };
    let mut ff = thr * f64::from(p.fuel_flow_max);
    if k <= 0.6 {
        ff *= f64::from(p.dry_fuel_frac);
    }
    ff / v
}

/// The stores an aircraft entity spawns with (`stores::loadout`, `FUN_0058f110`) from its CArmament and its bdb
/// object's.
fn stores_of(e: &Value, obj: Option<&Value>, weapons: &HashMap<i64, &Value>) -> Stores {
    let pairs = |a: &Value| -> Vec<(i64, i64)> {
        let h: Vec<i64> = a["hardpoints"].as_array().into_iter().flatten().map(int).collect();
        h.chunks(2).map(|c| (c[0], *c.get(1).unwrap_or(&0))).collect()
    };
    let load = loadout(&pairs(&e["armament"]), &obj.map(|o| pairs(&o["armament"])).unwrap_or_default());
    let stations: [Option<Station>; STATIONS] = std::array::from_fn(|i| {
        let (id, count) = load[i];
        let w = weapons.get(&id).filter(|_| count > 0)?;
        let weapon = Weapon {
            type_code: int(&w["0x780"]),
            name: w["0x708"].as_str().unwrap_or("").to_string(),
            weight_lb: num(&w["0x758"]),
            drag: num(&w["0x73a"]),
            rounds_per_tick: None,
        };
        Some(Station { weapon, count: count as f64, initial: count as f64, unlimited: false, arm: 0.0 })
    });
    let mut s = Stores::default();
    s.setup(stations);
    s
}

/// The fuel (kg) blue flight `f` burns on its route, and the fuel it has: from its leader's start along its waypoints,
/// then back to the start unless the route lands (action 7) or ends within 10 km of it. Each leg at its waypoint's
/// altitude and planned speed, the mass with half the fuel burnt (inferred). None without flight data.
fn route_fuel(f: &Value, leader: &Value, p: &Params, stores: &Stores) -> Option<(f64, f64)> {
    let pts = f["points"].as_array()?;
    let start = [num(&leader["0x2e4"]), num(&leader["0x2ee"]), num(&leader["0x2f8"])];
    let fuel = f64::from(p.fuel_mass) + stores.tank_fuel();
    // The original adds the stores' pounds to the kg field (stores.rs `init_weight_drag`).
    let load = stores.load();
    let mass = f64::from(p.empty_mass) + load.mass + fuel / 2.0;
    let di = load.di_left + load.di_right;
    let (mut at, mut t_prev, mut burn) = (start, 0.0, 0.0);
    let leg = |from: [f64; 3], to: [f64; 3], t: f64, t_prev: f64| {
        let d = ((to[0] - from[0]).powi(2) + (to[1] - from[1]).powi(2) + (to[2] - from[2]).powi(2)).sqrt();
        let v = if t > 0.0 && t > t_prev { (d / (t - t_prev)).clamp(SPEED_MIN, SPEED_MAX) } else { SPEED_NONE };
        d * burn_per_m(p, to[2].max(0.0), v, mass, di)
    };
    for q in pts {
        let to = [num(&q[1]), num(&q[2]), num(&q[3])];
        let t = num(&q[4]);
        burn += leg(at, to, t, t_prev);
        (at, t_prev) = (to, t);
    }
    let lands = pts.last().is_some_and(|q| int(&q[5]) == LAND);
    if !lands && (at[0] - start[0]).hypot(at[1] - start[1]) > HOME {
        burn += leg(at, [start[0], start[1], at[2]], 0.0, 0.0);
    }
    Some((burn, fuel))
}

/// The sanity check: warnings only. `bdb` is the converted default6_1.bdb, `install` the extracted install (the
/// flight model's data, `resource/md`).
pub fn sanity_issues(mission: &Value, bdb: &Value, install: &Path) -> Vec<Issue> {
    let objects: HashMap<i64, &Value> =
        bdb["objects"]["items"].as_array().into_iter().flatten().map(|o| (int(&o["0x1e"]), o)).collect();
    let weapons: HashMap<i64, &Value> =
        bdb["weapons"]["items"].as_array().into_iter().flatten().map(|w| (int(&w["0x1e"]), w)).collect();
    let ents: Vec<&Value> = mission["entities"]["items"].as_array().into_iter().flatten().filter(|e| real(e)).collect();
    let by_id: HashMap<i64, &Value> = ents.iter().map(|e| (int(&e["0x1e"]), *e)).collect();
    let obj = |e: &Value| objects.get(&int(&e["0x2c6"])).copied();
    let class = |e: &Value| obj(e).map_or(-1, |o| int(&o["0x5aa"]));
    let kind = |e: &Value| {
        let o = obj(e);
        let name = |k: &str| o.and_then(|o| o[k].as_str()).filter(|s| !s.is_empty()).map(String::from);
        name("0x528").or_else(|| name("0x514")).unwrap_or_else(|| "unit".into())
    };
    let mut out = vec![];
    let mut params_of: HashMap<i64, Option<Params>> = HashMap::new();
    let (mut aa, mut ag, mut blue) = (false, false, false);
    for f in mission["formations"]["items"].as_array().into_iter().flatten().filter(|f| real(f)) {
        let n = int(&f["0x3f2"]);
        let name = f["0x3e8"].as_str().unwrap_or("?");
        let members: Vec<&Value> = f["members"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|m| by_id.get(&int(&m["0x41a"])).copied())
            .collect();
        let Some(leader) = members.first() else { continue };
        // A route without points: an enemy flight that never leaves its start.
        if int(&leader["0x2d0"]) == 2 && f["points"].as_array().is_none_or(Vec::is_empty) {
            out.push(warning(int(&leader["0x1e"]), format!("enemy flight {name} has no waypoints")));
        }
        if !(1..=4).contains(&n) || int(&leader["0x2d0"]) != 1 {
            continue;
        }
        blue = true;
        for m in &members {
            let s = stores_of(m, obj(m), &weapons);
            for (_, st) in s.stations() {
                match Category::of(st.weapon.type_code) {
                    Category::AirToGround => ag = true,
                    Category::AirToAir | Category::Gun => aa = true,
                    Category::Other => {}
                }
            }
        }
        let code = obj(leader).map_or(-1, |o| int(&o["0x5b4"]));
        let Some(p) = params_of.entry(code).or_insert_with(|| params(install, code)).as_ref() else { continue };
        let stores = stores_of(leader, obj(leader), &weapons);
        if let Some((burn, fuel)) = route_fuel(f, leader, p, &stores).filter(|(_, fuel)| *fuel > 0.0)
            && burn > FUEL_SHARE * fuel
        {
            let pct = (burn / fuel * 20.0).round() * 5.0;
            out.push(warning(int(&leader["0x1e"]), format!("{name}: about {pct:.0}% of its fuel for this route")));
        }
    }
    let spawned = |e: &Value| {
        let unplaced = num(&e["0x2e4"]) < 0.0 && num(&e["0x2ee"]) < 0.0;
        !(unplaced && e["0x2bc"].as_str().unwrap_or("").to_ascii_lowercase().starts_with("player"))
    };
    let role = |e: &Value| e["0x32a"].as_i64().or_else(|| e["0x32a"].as_f64().map(|f| f as i64)).unwrap_or(2);
    // The red SAM rings, but a SAM the mission makes a target is meant to be attacked.
    let rings: Vec<(&Value, f64)> = ents
        .iter()
        .filter(|e| int(&e["0x2d0"]) == 2 && class(e) == SAM_CLASS && role(e) != TARGET && spawned(e))
        .filter_map(|e| {
            let code = obj(e).map_or(-1, |o| int(&o["0x5b4"]));
            SAM_RING.iter().find(|(c, _)| *c == code).map(|(_, r)| (*e, *r))
        })
        .collect();
    let at = |e: &Value| (num(&e["0x2e4"]), num(&e["0x2ee"]));
    let inside = |x: f64, y: f64, s: &Value, r: f64| (at(s).0 - x).hypot(at(s).1 - y) < r;
    let paths: HashMap<i64, &Value> = mission["paths"]["items"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|p| real(p))
        .map(|p| (int(&p["0x1e"]), p))
        .collect();
    for e in ents.iter().filter(|e| spawned(e)) {
        let id = int(&e["0x1e"]);
        // A route without points: a Path motion (op 16) on a missing path or one of fewer than two points.
        for s in e["scripts0"]["items"].as_array().into_iter().flatten().filter(|s| int(&s["0x83e"]) == 16) {
            let n = paths.get(&int(&s["0x8ac"])).and_then(|p| p["points"].as_array()).map_or(0, Vec::len);
            if n < 2 {
                out.push(warning(id, "its route has no points: it stays where it is".into()));
                break;
            }
        }
        if role(e) != TARGET || int(&e["0x2c6"]) == SENSOR {
            continue;
        }
        let air = AIR.contains(&class(e));
        if blue && !(if air { aa } else { ag }) {
            let what = if air { "air-to-air" } else { "air-to-ground" };
            out.push(warning(id, format!("no blue flight carries an {what} weapon for this {}", kind(e))));
        }
        let (x, y) = at(e);
        let rings: Vec<&(&Value, f64)> = rings.iter().filter(|(s, _)| !inside(x, y, s, LOCAL)).collect();
        let cover: Vec<&&(&Value, f64)> = rings.iter().filter(|(s, r)| inside(x, y, s, *r)).collect();
        if air || cover.is_empty() {
            continue;
        }
        let open = (0..BEARINGS).any(|k| {
            let b = k as f64 * std::f64::consts::TAU / BEARINGS as f64;
            let (px, py) = (x + APPROACH * b.sin(), y + APPROACH * b.cos());
            !rings.iter().any(|(s, r)| inside(px, py, s, *r))
        });
        if !open {
            let near = cover.iter().min_by(|a, b| {
                let d = |s: &Value| (at(s).0 - x).hypot(at(s).1 - y);
                d(a.0).total_cmp(&d(b.0))
            });
            let sam = near.map_or_else(|| "a SAM".into(), |(s, _)| kind(s));
            out.push(warning(id, format!("{sam} battery covers this target from every side")));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::path::PathBuf;

    fn assets() -> Option<PathBuf> {
        let a = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        (a.join("converted/missions/2vs2.json").exists() && a.join("install/resource/md").exists()).then_some(a)
    }

    fn read(a: &Path, name: &str) -> Value {
        serde_json::from_str(&std::fs::read_to_string(a.join(format!("converted/missions/{name}.json"))).unwrap())
            .unwrap()
    }

    #[test]
    fn sanity_warns_and_originals_stay_clean() {
        let Some(a) = assets() else {
            eprintln!("skip: no converted missions or install (tools/setup-cli.sh)");
            return;
        };
        let (bdb, install) = (read(&a, "default6_1.bdb"), a.join("install"));
        // An F-16 at 6 km and 275 m/s burns some kg per km (the fuel flow divided by the speed).
        let p = params(&install, 100).unwrap();
        let per_km = 1000.0 * burn_per_m(&p, 6000.0, 275.0, f64::from(p.empty_mass) + 1500.0, 0.0);
        eprintln!("F-16 clean, 6 km, 275 m/s: {per_km:.2} kg/km, fuel {} kg", p.fuel_mass);
        assert!(per_km > 0.3 && per_km < 10.0, "{per_km}");
        // With its own stores (bdb object 1's): heavier and draggier, it burns more.
        let weapons: HashMap<i64, &Value> =
            bdb["weapons"]["items"].as_array().unwrap().iter().map(|w| (int(&w["0x1e"]), w)).collect();
        let f16 = bdb["objects"]["items"].as_array().unwrap().iter().find(|o| int(&o["0x1e"]) == 1).unwrap();
        let s = stores_of(&json!({}), Some(f16), &weapons);
        let l = s.load();
        let loaded =
            1000.0 * burn_per_m(&p, 3000.0, 275.0, f64::from(p.empty_mass) + l.mass + 1500.0, l.di_left + l.di_right);
        eprintln!(
            "F-16 loaded ({} kg-field, DI {:.4}), 3 km, 275 m/s: {loaded:.2} kg/km",
            l.mass,
            l.di_left + l.di_right
        );
        assert!(loaded > per_km);
        // 231 License to Kill as it is, then with Alpha sent 900 km away and back.
        let m = read(&a, "license");
        let none = sanity_issues(&m, &bdb, &install);
        assert!(none.iter().all(|i| !i.text.contains("fuel")), "{none:?}");
        let mut far = m.clone();
        let fi = far["formations"]["items"].as_array().unwrap().iter().position(|f| f["0x3f2"] == 1).unwrap();
        far["formations"]["items"][fi]["points"] = json!([[1, -400000.0, 600000.0, 3000.0, 0.0, 3]]);
        let i = sanity_issues(&far, &bdb, &install);
        assert!(
            i.iter().any(|i| i.text.starts_with("Alpha: about ") && i.text.ends_with("% of its fuel for this route")),
            "{i:?}"
        );
        assert!(i.iter().all(|i| i.level == "warning"));
        // Calibration over the 66 originals (docs/mission-editor.md §16).
        let list: Value =
            serde_json::from_str(&std::fs::read_to_string(a.join("converted/missions/missionlist.json")).unwrap())
                .unwrap();
        let mut counts: HashMap<String, usize> = HashMap::new();
        let mut missions = 0;
        for (k, v) in list.as_object().unwrap() {
            if k == "666" || k == "777" {
                continue;
            }
            missions += 1;
            let stem = v[0].as_str().unwrap();
            for i in sanity_issues(&read(&a, stem), &bdb, &install) {
                eprintln!("calibration: {k} {stem} {}: {}", i.id, i.text);
                let kind = if i.text.contains("fuel") {
                    "fuel"
                } else if i.text.contains("every side") {
                    "sam"
                } else if i.text.contains("weapon") {
                    "weapon"
                } else {
                    "route"
                };
                *counts.entry(kind.into()).or_default() += 1;
            }
        }
        eprintln!("calibration: {missions} missions, {counts:?}");
        // The originals stay mostly clean: 16 warnings in 9 of 66 missions (docs/mission-editor.md §16).
        let n = |k: &str| counts.get(k).copied().unwrap_or(0);
        assert_eq!((n("fuel"), n("sam"), n("route"), n("weapon")), (3, 11, 2, 0), "{counts:?}");
    }
}
