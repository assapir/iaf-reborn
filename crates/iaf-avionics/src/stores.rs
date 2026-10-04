//! The stores of one aircraft (docs/weapons.md §2–§5): the station container (ctl+0xfc, `FUN_0053b460`) with its 12
//! stations (0..8 pylons StationA..I, 9 gun, 10 chaff, 11 flares), the loadout at mission start, the selection
//! cycle, which station fires next, the count decrement, and the stores weight / drag the flight model reads (S+0x424,
//! S+0x428, S+0x42c).

use crate::vec3::Vec3;

pub const GUN: i64 = 565;
pub const CHAFF: i64 = 540;
pub const FLARE: i64 = 550;
/// Fuel tanks and pods.
pub const SHELL: i64 = 660;
pub const STATIONS: usize = 12;
/// Pylons 0..8.
const PYLONS: usize = 9;
/// [Misc] BombStationLength (IAF.ibx, default 2.0 @0x60c5bc; not in the shipped file).
const BOMB_STATION_LENGTH: f64 = 2.0;
/// [Misc] PilonDefaultZ.
const PILON_DEFAULT_Z: f64 = 5.0;
/// lb ↔ kg (0x600f70 / 0x600f74).
const LB_PER_KG: f64 = 2.2046;
const KG_PER_LB: f64 = 0.45359;

/// Weapon category (`FUN_004d72a0`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Category {
    Gun,
    AirToAir,
    AirToGround,
    Other,
}

impl Category {
    pub fn of(type_code: i64) -> Self {
        match type_code {
            GUN => Category::Gun,
            540 | 550 | 570 | 580 | 600 | 610 => Category::AirToAir,
            500 | 510 | 560 | 590 | 635 | 640 | 650 => Category::AirToGround,
            _ => Category::Other,
        }
    }
}

/// What the stores need of a weapon record (weapon_db).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Weapon {
    pub type_code: i64,
    pub name: String,
    pub weight_lb: f64,
    pub drag: f64,
    /// Weapon data Real: a gun shot tick uses rate · 0.2 s rounds (ours; the original 1), shown 1:1.
    pub rounds_per_tick: Option<f64>,
}

impl Weapon {
    /// A fuel tank ("LB" in the name).
    fn is_tank(&self) -> bool {
        self.name.contains("LB")
    }
}

#[derive(Clone, Debug)]
pub struct Station {
    pub weapon: Weapon,
    pub count: f64,
    pub initial: f64,
    /// Unlimited ammo on this station (never chaff / flares).
    pub unlimited: bool,
}

impl Station {
    /// The displayed count (`FUN_0053cfd0`): the gun shows its count ×4 when it is a "20 MM", else ×2.
    pub fn displayed(&self) -> i64 {
        let w = &self.weapon;
        if w.type_code != GUN {
            return self.count as i64;
        }
        if w.rounds_per_tick.is_some() {
            return (self.count.ceil() as i64).max(0);
        }
        ((self.count as i64) * if w.name.contains("20 MM") { 4 } else { 2 }).max(0)
    }

    fn same_weapon(&self, w: &Weapon) -> bool {
        self.weapon.type_code == w.type_code && self.weapon.name == w.name
    }
}

/// The flight-model stores values: S+0x424 (the "kg" field; the original writes pounds into it at the start), the
/// drag index of the left (stations 0..4, S+0x42c) and right (4..8, S+0x428) side, ×1e-4.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Load {
    pub mass: f64,
    pub di_left: f64,
    pub di_right: f64,
}

/// The loadout an aircraft spawns with (`FUN_0058f110`): pylons 0..8 from the entity's CArmament when any of them is
/// set, else from the object type's; 9..11 (gun, chaff, flares) always from the type. [weapon id, count] × 12.
pub fn loadout(entity: &[(i64, i64)], object: &[(i64, i64)]) -> [(i64, i64); STATIONS] {
    let pylons_set = entity.iter().take(PYLONS).any(|&(id, _)| id != 0 && id != -1);
    std::array::from_fn(|i| {
        let src = if i < PYLONS && pylons_set { entity } else { object };
        src.get(i).copied().unwrap_or((0, 0))
    })
}

/// The store positions of a station (`FUN_0053c990`) in glTF metres, computed once in the original's E frame (x =
/// −glTF x, y = glTF z, z = glTF y) from the attach point and the store's Pilon: TER (3) for non-bombs and bombs ≤ 3,
/// MER (6) for bombs ≥ 4 spread ±BombStationLength fore / aft. Stations above 5 are mirrored (station 5 is not: the
/// original's `> 5.0` test).
pub fn slots(index: usize, attach: Vec3, count: i64, bomb: bool, pilon: Option<Vec3>) -> Vec<Vec3> {
    let pl = pilon.unwrap_or(Vec3::new(0.0, PILON_DEFAULT_Z, 0.0));
    let (px, py, pz) = (-pl.x, pl.z, pl.y);
    let mirror = index > 5;
    let l = BOMB_STATION_LENGTH;
    let e = if bomb && count >= 4 {
        let s = if mirror { -1.0 } else { 1.0 };
        vec![
            Vec3::new(s * pz, l, 0.0),
            Vec3::new(s * pz, -l, 0.0),
            Vec3::new(-s * pz, l, 0.0),
            Vec3::new(-s * pz, -l, 0.0),
            Vec3::new(0.0, l, -pz),
            Vec3::new(0.0, -l, -pz),
        ]
    } else {
        let (a, b, c) = (Vec3::new(pz, 0.0, 0.0), Vec3::new(-pz, 0.0, 0.0), Vec3::new(px, py, -pz));
        let mut e = if mirror { vec![b, a, c] } else { vec![a, b, c] };
        if count == 1 {
            e[0] = c;
        }
        e
    };
    e.into_iter().map(|v| attach + Vec3::new(-v.x, v.z, v.y)).collect()
}

#[derive(Clone, Debug, Default)]
pub struct Stores {
    stations: [Option<Station>; STATIONS],
    /// C+0x38 current, +0x3c last AA, +0x40 last AG, +0x44 last fired, +0x4c just fired.
    pub cur: usize,
    last_aa: usize,
    last_ag: usize,
    last_fired: usize,
    just_fired: bool,
    /// Releases so far (fired / jettisoned; ours: the weapon bay doors watch it).
    releases: u32,
    /// +0x50..: the names visited by the cycle; +0x84 the last cycle kind.
    visited: Vec<String>,
    last_kind: Option<Category>,
    /// The owner is the player (the cycle's "may select an empty weapon" rule).
    pub player: bool,
    /// Physics option "Stores weight fix" (ours): every store counted, pounds converted to kg.
    pub weight_fix: bool,
    /// W+0x94 Unlimited ammo.
    unlimited: bool,
    /// W+0xc0: a fuel tank is carried.
    has_tank: bool,
    /// The fuel the tanks add to the fuel maximum at the start (kg field; see `init_weight_drag`).
    tank_fuel: f64,
    load: Load,
}

impl Stores {
    /// The stations (`FUN_004b7ea3` → `FUN_0053b580` → `FUN_0053c1f0`): None = no station (a count of 0 or an unknown
    /// weapon).
    pub fn setup(&mut self, stations: [Option<Station>; STATIONS]) {
        self.stations = stations;
        self.cur = 0;
        self.just_fired = false;
        self.set_unlimited(self.unlimited);
        self.init_weight_drag();
    }

    pub fn station(&self, i: usize) -> Option<&Station> {
        self.stations.get(i)?.as_ref()
    }
    pub fn stations(&self) -> impl Iterator<Item = (usize, &Station)> {
        self.stations.iter().enumerate().filter_map(|(i, s)| Some((i, s.as_ref()?)))
    }
    pub fn type_of(&self, i: usize) -> i64 {
        self.station(i).map_or(0, |s| s.weapon.type_code)
    }
    pub fn displayed(&self, i: usize) -> i64 {
        self.station(i).map_or(0, Station::displayed)
    }
    pub fn current(&self) -> Option<&Station> {
        self.station(self.cur)
    }
    pub fn releases(&self) -> u32 {
        self.releases
    }
    pub fn last_fired(&self) -> usize {
        self.last_fired
    }
    pub fn unlimited(&self) -> bool {
        self.unlimited
    }
    pub fn has_tank(&self) -> bool {
        self.has_tank
    }
    pub fn tank_fuel(&self) -> f64 {
        self.tank_fuel
    }
    pub fn load(&self) -> Load {
        self.load
    }

    /// Total displayed count of the stations with this weapon (type and name; `FUN_0053bd90` / `FUN_0053bcd0`).
    pub fn total(&self, type_code: i64, name: &str) -> i64 {
        self.stations().filter(|(_, s)| s.weapon.type_code == type_code && s.weapon.name == name).map(|(_, s)| s.displayed()).sum()
    }

    fn remember(&mut self, kind: Category) {
        if kind == Category::AirToAir {
            self.last_aa = self.cur;
        } else {
            self.last_ag = self.cur;
        }
    }

    /// The selection cycle (`FUN_0053b8b0`) of `kind` (AA or AG); the gun belongs to both when allowed. Distinct names
    /// in index order 0..9, restarting after station 9 or when the kind changes; a weapon with rounds left is
    /// preferred, the player may select an empty one when no station of that weapon has any left.
    pub fn cycle(&mut self, kind: Category, allow_gun: bool) {
        let prev = self.last_kind.replace(kind);
        let mut i = self.cur + 1;
        if i > 9 || prev != Some(kind) {
            self.visited.clear();
            i = 0;
        }
        let cur = self.current().map(|s| s.weapon.clone());
        let mut cand = None;
        let mut found = false;
        for _ in 0..10 {
            if let Some(s) = self.station(i) {
                let w = &s.weapon;
                let cat = Category::of(w.type_code);
                let fresh = w.type_code != SHELL && cur.as_ref().is_none_or(|c| !s.same_weapon(c)) && !self.visited.contains(&w.name);
                if fresh && (cat == kind || (cat == Category::Gun && allow_gun)) {
                    cand = Some(i);
                    let name = w.name.clone();
                    if s.displayed() > 0 {
                        found = true;
                        self.visited.push(name);
                        break;
                    } else if self.player && self.total(w.type_code, &w.name) == 0 {
                        self.visited.push(name);
                        break;
                    }
                }
            }
            i = (i + 1) % 10;
        }
        if found {
            self.cur = i;
        } else if let Some(c) = cand {
            self.cur = c;
        }
        self.just_fired = false;
        self.remember(kind);
    }

    /// MFD station select (`FUN_0053bfb0`): accepted if another existing station, not a tank / pod.
    pub fn select_station(&mut self, i: usize) -> bool {
        if i == self.cur || self.station(i).is_none_or(|s| s.weapon.type_code == SHELL) {
            return false;
        }
        self.cur = i;
        self.just_fired = false;
        true
    }

    /// The station that fires next (`FUN_0053b680`): after a shot from the current station, the station of the same
    /// weapon with rounds left farthest from the last one (so AIM-9 0 → 8 → 0 ...). Without a current station the
    /// first one; None without any.
    pub fn fire_station(&mut self) -> Option<usize> {
        if self.cur == self.last_fired && self.just_fired {
            if let Some(w) = self.current().map(|s| s.weapon.clone()) {
                let far = (0..10)
                    .filter(|&i| self.station(i).is_some_and(|s| s.same_weapon(&w) && s.displayed() > 0))
                    .filter(|&i| i != self.last_fired)
                    .max_by_key(|&i| (i.abs_diff(self.last_fired), std::cmp::Reverse(i)));
                if let Some(best) = far {
                    self.cur = best;
                }
            }
            self.just_fired = false;
            self.remember(if Category::of(self.type_of(self.cur)) == Category::AirToAir { Category::AirToAir } else { Category::AirToGround });
        }
        if self.current().is_some() {
            return Some(self.cur);
        }
        (0..11).find(|&i| self.station(i).is_some())
    }

    /// After a store left station `i` (`FUN_0053bf10` → `FUN_0053c8b0`): the count drops by one unless unlimited; the
    /// weight and drag updates follow (`FUN_004583a0` / `FUN_00458510`).
    pub fn fired(&mut self, i: usize) {
        let Some(w) = self.station(i).map(|s| s.weapon.clone()) else { return };
        self.released(i);
        if !self.unlimited && i < PYLONS {
            self.release_drag(i, &w);
            let m = self.load.mass * LB_PER_KG - w.weight_lb;
            if m >= 0.0 {
                self.load.mass = (m * KG_PER_LB).max(0.0);
            }
        }
    }

    /// A tank jettisoned from station `i` (`FUN_00458760`): count −1 and the drag update only.
    pub fn jettisoned(&mut self, i: usize) {
        let Some(w) = self.station(i).map(|s| s.weapon.clone()) else { return };
        self.released(i);
        self.release_drag(i, &w);
    }

    fn released(&mut self, i: usize) {
        self.last_fired = i;
        self.just_fired = true;
        self.releases += 1;
        self.consume(i);
    }

    /// `FUN_0053c8b0` alone (the gun's shots): the count drops by one (Real: a shot tick's rounds) unless unlimited.
    pub fn consume(&mut self, i: usize) {
        if let Some(s) = self.stations.get_mut(i).and_then(Option::as_mut)
            && !s.unlimited
            && s.count > 0.0
        {
            s.count = (s.count - s.weapon.rounds_per_tick.unwrap_or(1.0)).max(0.0);
        }
    }

    /// W+0x94 / `FUN_0053bf60`: unlimited on every station but chaff and flares.
    pub fn set_unlimited(&mut self, on: bool) {
        self.unlimited = on;
        for s in self.stations.iter_mut().flatten() {
            if s.weapon.type_code != CHAFF && s.weapon.type_code != FLARE {
                s.unlimited = on;
            }
        }
    }

    /// The cheat reload (`FUN_0053bed0`): every station back to its initial count (weight / drag not restored, as the
    /// original).
    pub fn reload(&mut self) {
        for s in self.stations.iter_mut().flatten() {
            s.count = s.initial;
        }
    }

    /// `FUN_00454010`: one store per station 0..8 whatever the count (original); tanks go to the fuel (`tank_fuel`)
    /// instead of the stores weight; drag of stations 0..3 left, 5..8 right, station 4 half to each. The weight
    /// (pounds) goes into the kg field as is. With the weight fix: every store counted, in kg, tank fuel in kg.
    pub fn init_weight_drag(&mut self) {
        let unit = if self.weight_fix { KG_PER_LB } else { 1.0 };
        let (mut weight, mut left, mut right) = (0.0, 0.0, 0.0);
        self.has_tank = false;
        self.tank_fuel = 0.0;
        for (i, s) in self.stations.iter().enumerate().take(PYLONS) {
            let Some(s) = s else { continue };
            let n = if self.weight_fix { s.count } else { 1.0 };
            if s.weapon.is_tank() {
                // The tank's bdb weight becomes fuel (FUN_005a8980: fuel maximum FuelWeight + out[3]).
                self.has_tank = true;
                self.tank_fuel += n * s.weapon.weight_lb * unit;
            } else {
                weight += n * s.weapon.weight_lb * unit;
            }
            let d = n * s.weapon.drag;
            match i {
                0..4 => left += d,
                4 => {
                    left += 0.5 * d;
                    right += 0.5 * d;
                }
                _ => right += d,
            }
        }
        self.load = Load { mass: weight, di_left: (left * 1e-4).max(0.0), di_right: (right * 1e-4).max(0.0) };
    }

    /// `FUN_004583a0`: that side's drag index loses the store's drag (half at station 4, both sides), only when it stays
    /// ≥ 0.
    fn release_drag(&mut self, i: usize, w: &Weapon) {
        let d = w.drag * if i == 4 { 0.5 } else { 1.0 };
        let drop = |di: &mut f64| {
            let v = *di * 10000.0 - d;
            if v >= 0.0 {
                *di = (v * 1e-4).max(0.0);
            }
        };
        if i <= 4 {
            drop(&mut self.load.di_left);
        }
        if i >= 4 {
            drop(&mut self.load.di_right);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn st(type_code: i64, name: &str, count: f64) -> Option<Station> {
        let weapon = Weapon { type_code, name: name.into(), weight_lb: 200.0, drag: 10.0, rounds_per_tick: None };
        Some(Station { weapon, count, initial: count, unlimited: false })
    }

    fn f16() -> Stores {
        let mut s = Stores { player: true, ..Stores::default() };
        let mut stations: [Option<Station>; STATIONS] = Default::default();
        stations[0] = st(570, "AIM-9L", 1.0);
        stations[2] = st(500, "MK-82", 3.0);
        stations[4] = st(SHELL, "300 LB TANK", 1.0);
        stations[6] = st(500, "MK-82", 3.0);
        stations[8] = st(570, "AIM-9L", 1.0);
        stations[9] = st(GUN, "20 MM", 100.0);
        s.setup(stations);
        s
    }

    #[test]
    fn aim9_alternates_far_stations() {
        let mut s = f16();
        assert_eq!(s.fire_station(), Some(0));
        s.fired(0);
        assert_eq!(s.fire_station(), Some(8));
        assert_eq!(s.total(570, "AIM-9L"), 1);
    }

    #[test]
    fn cycle_aa_then_ag() {
        let mut s = f16();
        s.cycle(Category::AirToAir, true);
        assert_eq!(s.cur, 9, "after the AIM-9: the gun");
        s.cycle(Category::AirToGround, true);
        assert_eq!(s.cur, 2, "AG restarts: the MK-82");
    }

    #[test]
    fn weight_drag_and_release() {
        let mut s = f16();
        assert!(s.has_tank() && s.tank_fuel() == 200.0);
        assert_eq!(s.load(), Load { mass: 800.0, di_left: 25e-4, di_right: 25e-4 });
        s.fired(2);
        assert!((s.load().mass - (800.0 * LB_PER_KG - 200.0) * KG_PER_LB).abs() < 1e-9);
        assert!((s.load().di_left - 15e-4).abs() < 1e-12);
        s.jettisoned(4);
        assert!((s.load().di_left - 10e-4).abs() < 1e-12 && (s.load().di_right - 20e-4).abs() < 1e-12);
    }

    #[test]
    fn gun_display_and_unlimited() {
        let mut s = f16();
        assert_eq!(s.displayed(9), 400);
        s.set_unlimited(true);
        s.consume(9);
        assert_eq!(s.displayed(9), 400);
    }

    #[test]
    fn loadout_and_slots() {
        let ent = [(0, 0), (8, 2)];
        let obj = [(9, 1); 12];
        assert_eq!(loadout(&ent, &obj)[1], (8, 2));
        assert_eq!(loadout(&ent, &obj)[0], (0, 0), "a set pylon takes all nine from the entity");
        assert_eq!(loadout(&[(0, 0)], &obj)[0], (9, 1));
        let s = slots(6, Vec3::ZERO, 6, true, None);
        assert_eq!(s.len(), 6);
        assert_eq!(s[0], Vec3::new(5.0, 0.0, 2.0));
    }
}
