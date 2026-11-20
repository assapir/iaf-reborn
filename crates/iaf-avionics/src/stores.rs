//! The stores of one aircraft (docs/weapons.md §2–§5): the station container (ctl+0xfc, `FUN_0053b460`) with its 12
//! stations (0..8 pylons StationA..I, 9 gun, 10 chaff, 11 flares) and Modern IAF's 13th and 14th (12, StationJ: the
//! F-16's left chin hardpoint; 13, StationK: its centreline; ours), the loadout at mission start, the selection
//! cycle, which station fires next, the count decrement, and the stores weight / drag the flight model reads (S+0x424,
//! S+0x428, S+0x42c).

use crate::vec3::Vec3;

pub const GUN: i64 = 565;
pub const CHAFF: i64 = 540;
pub const FLARE: i64 = 550;
/// Fuel tanks and pods.
pub const SHELL: i64 = 660;
pub const STATIONS: usize = 14;
/// The wing pylons 0..8 (the original's nine; the mirror and the drag sides count them).
const PYLONS: usize = 9;
/// Ours (Modern IAF, modern-iaf/docs/weapons.md §7.3): the F-16's left chin hardpoint (5L), pylon J, after the
/// original's gun, chaff and flares so their indexes stay. The 1998 game's data never fills it.
pub const CHIN_LEFT: usize = 12;
/// Ours (Modern IAF): the F-16's centreline station (the real jet's 5, its 300 US gal tank), pylon K, after the left
/// chin hardpoint: Modern IAF's F-16 hangs its right chin pod on the original's centre station E. The 1998 game's data
/// never fills it.
pub const CENTRELINE: usize = 13;
/// Each station's pylon letter ('-': the gun, chaff and flares).
pub const LETTERS: &[u8; STATIONS] = b"ABCDEFGHI---JK";

/// Station `i` is a pylon (A..I, J or K).
pub fn is_pylon(i: usize) -> bool {
    i < PYLONS || i == CHIN_LEFT || i == CENTRELINE
}

/// The station index of pylon letter `l` (A..K).
pub fn pylon_index(l: u8) -> Option<usize> {
    LETTERS.iter().position(|&c| c == l && c != b'-')
}

/// A centre station (the original's 4, the left chin 12, the centreline 13): its drag goes half to each side.
fn centre(i: usize) -> bool {
    i == 4 || i == CHIN_LEFT || i == CENTRELINE
}
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
    /// A tank's own empty weight (lb; ours, Modern IAF's data): with the weight fix it loads the jet until the tank
    /// leaves. The original counts a tank's weight as fuel only.
    pub empty_lb: f64,
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
    /// The attach point's lateral position (glTF x, metres, + right wing); ours, for the asymmetric stores option.
    pub arm: f64,
    /// Ours (Modern IAF's racks, a TER-9/A of Mk 82s): the rack's weight (kg) and carriage drag (the weapons' `drag`
    /// unit), carried while the station is loaded and kept when its stores go.
    pub rack_kg: f64,
    pub rack_drag: f64,
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

/// The loadout an aircraft spawns with (`FUN_0058f110`): the pylons (0..8, 12 and 13) from the entity's CArmament when
/// any of them is set, else from the object type's; 9..11 (gun, chaff, flares) always from the type. [weapon id,
/// count] × 14 (an armament of the original's 12 leaves 12 and 13 empty).
pub fn loadout(entity: &[(i64, i64)], object: &[(i64, i64)]) -> [(i64, i64); STATIONS] {
    let pylons_set = entity.iter().enumerate().any(|(i, &(id, _))| is_pylon(i) && id != 0 && id != -1);
    std::array::from_fn(|i| {
        let src = if is_pylon(i) && pylons_set { entity } else { object };
        src.get(i).copied().unwrap_or((0, 0))
    })
}

/// The store positions of a station (`FUN_0053c990`) in glTF metres, computed once in the original's E frame (x =
/// −glTF x, y = glTF z, z = glTF y) from the attach point and the store's Pilon: TER (3) for non-bombs and bombs ≤ 3,
/// MER (6) for bombs ≥ 4 spread ±BombStationLength fore / aft. Stations 6..8 are mirrored (station 5 is not: the
/// original's `> 5.0` test; nor the left chin 12 and the centreline 13, ours).
pub fn slots(index: usize, attach: Vec3, count: i64, bomb: bool, pilon: Option<Vec3>) -> Vec<Vec3> {
    let pl = pilon.unwrap_or(Vec3::new(0.0, PILON_DEFAULT_Z, 0.0));
    let (px, py, pz) = (-pl.x, pl.z, pl.y);
    let mirror = index > 5 && index < PYLONS;
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
    /// Ours: the share of `tank_fuel` in the tanks on a centre station (the F-16's centreline tank), which the 6-DoF's
    /// gauge shows at EXT CTR.
    tank_fuel_centre: f64,
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
    pub fn tank_fuel_centre(&self) -> f64 {
        self.tank_fuel_centre
    }
    pub fn load(&self) -> Load {
        self.load
    }

    /// Total displayed count of the stations with this weapon (type and name; `FUN_0053bd90` / `FUN_0053bcd0`).
    pub fn total(&self, type_code: i64, name: &str) -> i64 {
        self.stations()
            .filter(|(_, s)| s.weapon.type_code == type_code && s.weapon.name == name)
            .map(|(_, s)| s.displayed())
            .sum()
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
                let fresh = w.type_code != SHELL
                    && cur.as_ref().is_none_or(|c| !s.same_weapon(c))
                    && !self.visited.contains(&w.name);
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
            if let Some(best) = self.farthest_same() {
                self.cur = best;
            }
            self.just_fired = false;
            self.remember(if Category::of(self.type_of(self.cur)) == Category::AirToAir {
                Category::AirToAir
            } else {
                Category::AirToGround
            });
        }
        self.next_station()
    }

    /// Ours: the station [`Self::fire_station`] would answer, without moving the selection or ending the "just fired"
    /// state, for the displays that ask every frame (the helmet's cue, the GPS cues). Asking `fire_station` there
    /// cleared the state Bomb release Real's SGL reads, so a single release no longer alternated wings.
    pub fn next_station(&self) -> Option<usize> {
        if self.cur == self.last_fired
            && self.just_fired
            && let Some(best) = self.farthest_same()
        {
            return Some(best);
        }
        if self.current().is_some() {
            return Some(self.cur);
        }
        (0..11).find(|&i| self.station(i).is_some())
    }

    /// After a shot: the station of the current weapon with rounds left farthest from the last one.
    fn farthest_same(&self) -> Option<usize> {
        let w = &self.current()?.weapon;
        (0..10)
            .filter(|&i| self.station(i).is_some_and(|s| s.same_weapon(w) && s.displayed() > 0))
            .filter(|&i| i != self.last_fired)
            .max_by_key(|&i| (i.abs_diff(self.last_fired), std::cmp::Reverse(i)))
    }

    /// Extras "Bomb release" Real (ours, docs/weapons.md §9.10): the stations of the next release pulse of the
    /// current weapon, and the selection moves to the first of them. PAIRS: the outboard-most symmetric pair (i,
    /// 8 − i) that both hold rounds, one store from each at the same instant. SGL, or no full pair left: after a store,
    /// its mirror station on the other wing when that holds rounds; else the outboard-most full pair's left station;
    /// else the station whose store leaves the lateral moment nearest 0 (ties: the lowest index). Empty without rounds.
    pub fn real_pulse(&mut self, pairs: bool) -> Vec<usize> {
        let Some(w) = self.current().map(|s| s.weapon.clone()) else { return Vec::new() };
        let has = |i: usize| self.station(i).is_some_and(|s| s.same_weapon(&w) && s.displayed() > 0);
        let mirror = |i: usize| (i < PYLONS && i != 4).then(|| PYLONS - 1 - i);
        let full = (0..4).find(|&i| has(i) && has(PYLONS - 1 - i));
        let last_same = self.just_fired && self.station(self.last_fired).is_some_and(|s| s.same_weapon(&w));
        let out = match (pairs, full) {
            (true, Some(i)) => vec![i, PYLONS - 1 - i],
            _ => match mirror(self.last_fired).filter(|&m| last_same && has(m)) {
                Some(m) => vec![m],
                None => match full {
                    Some(i) => vec![i],
                    None => {
                        let m = self.roll_moment() + self.tank_moment();
                        let after = |i: usize| {
                            let s = self.station(i).map_or(0.0, |s| s.weapon.weight_lb * KG_PER_LB * s.arm);
                            ((m - s).abs() * 1e6).round() as i64
                        };
                        (0..10).filter(|&i| has(i)).min_by_key(|&i| (after(i), i)).into_iter().collect()
                    }
                },
            },
        };
        if let Some(&i) = out.first() {
            self.cur = i;
        }
        out
    }

    /// After a store left station `i` (`FUN_0053bf10` → `FUN_0053c8b0`): the count drops by one unless unlimited; the
    /// weight and drag updates follow (`FUN_004583a0` / `FUN_00458510`).
    pub fn fired(&mut self, i: usize) {
        let Some(w) = self.station(i).map(|s| s.weapon.clone()) else { return };
        self.released(i);
        if !self.unlimited && is_pylon(i) {
            self.release_drag(i, &w);
            let m = self.load.mass * LB_PER_KG - w.weight_lb;
            if m >= 0.0 {
                self.load.mass = (m * KG_PER_LB).max(0.0);
            }
        }
    }

    /// Better physics "Asymmetric stores" (ours, docs/flight-model.md §10): the pylon stores' lateral moment Σ mass ·
    /// arm in kg·m, + right wing heavier, the fuel tanks' fuel left out ([`Self::tank_moment`]). Every store counts at
    /// its bdb weight in kg (a gun pod's rounds as one store), a tank's rack and its own empty weight too.
    pub fn roll_moment(&self) -> f64 {
        self.moment(false)
    }

    /// The fuel tanks' lateral moment at full fuel, kg·m: the flight model scales it by the external fuel left
    /// (`aircraft::tank_share`), as the one fuel pool burns the tanks first.
    pub fn tank_moment(&self) -> f64 {
        self.moment(true)
    }

    /// The F-16's loading category, 1 or 3, as its stores management set gives it to the STORES CONFIG caution light
    /// (T.O. GR1F-16CJ-1 figure 3-2, sheet 6: the light shows the switch in the wrong position for the loading
    /// category; modern-iaf/docs/cockpit.md §5.7). The manual's section V counts air-to-air missiles and 370 gal tanks
    /// with suspension equipment on the wing as category I loadings; the full table is in the -1-2, not public.
    /// Category III here (inferred): a pylon holding an air-to-ground store, or a tank of more than 3,000 lb of fuel
    /// (the 600 gal tank).
    pub fn loading_category(&self) -> u8 {
        let mut pylons = self.stations.iter().enumerate().filter(|(i, _)| is_pylon(*i)).filter_map(|(_, s)| s.as_ref());
        let heavy = pylons.any(|s| {
            s.count > 0.0
                && (Category::of(s.weapon.type_code) == Category::AirToGround
                    || (s.weapon.is_tank() && s.weapon.weight_lb > 3_000.0))
        });
        if heavy { 3 } else { 1 }
    }

    fn moment(&self, tanks: bool) -> f64 {
        let stores = self.stations.iter().enumerate().filter(|(i, _)| is_pylon(*i)).filter_map(|(_, s)| s.as_ref());
        stores
            .map(|s| {
                let n = if s.weapon.rounds_per_tick.is_some() { s.count.min(1.0) } else { s.count };
                match (s.weapon.is_tank(), tanks) {
                    (true, true) => n * s.weapon.weight_lb * KG_PER_LB * s.arm,
                    (true, false) => (n * s.weapon.empty_lb * KG_PER_LB + s.rack_kg) * s.arm,
                    (false, false) => (n * s.weapon.weight_lb * KG_PER_LB + s.rack_kg) * s.arm,
                    (false, true) => 0.0,
                }
            })
            .sum()
    }

    /// A tank jettisoned from station `i` (`FUN_00458760`): count −1 and the drag update only; with the weight fix
    /// its own empty weight (ours) leaves too.
    pub fn jettisoned(&mut self, i: usize) {
        let Some(w) = self.station(i).map(|s| s.weapon.clone()) else { return };
        self.released(i);
        self.release_drag(i, &w);
        if self.weight_fix {
            self.load.mass = (self.load.mass - w.empty_lb * KG_PER_LB).max(0.0);
        }
    }

    /// Weapon data Real's jettison (ours, docs/real-weapons.md §1.11): station `i`'s rack (Modern IAF's TER-9/A,
    /// BRU-57/A, BRU-61/A) leaves with its weight, drag and moment; a station without one is unchanged.
    pub fn jettison_rack(&mut self, i: usize) {
        let unit = if self.weight_fix { 1.0 } else { LB_PER_KG };
        let Some(s) = self.stations.get_mut(i).and_then(Option::as_mut) else { return };
        let (kg, drag) = (std::mem::take(&mut s.rack_kg), std::mem::take(&mut s.rack_drag));
        self.load.mass = (self.load.mass - kg * unit).max(0.0);
        self.release_drag(i, &Weapon { drag, ..Weapon::default() });
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

    /// `FUN_00454010`: one store per pylon (0..8, Modern IAF's 12 and 13) whatever the count (original); tanks go to
    /// the fuel (`tank_fuel`, the centre stations' share also `tank_fuel_centre`)
    /// instead of the stores weight; drag of stations 0..3 left, 5..8 right, station 4 half to each (and the left
    /// chin 12 and the centreline 13, ours). The weight
    /// (pounds) goes into the kg field as is. With the weight fix: every store counted, in kg, tank fuel in kg. A rack
    /// (ours) adds its weight and drag once per station.
    pub fn init_weight_drag(&mut self) {
        let unit = if self.weight_fix { KG_PER_LB } else { 1.0 };
        let (mut weight, mut left, mut right) = (0.0, 0.0, 0.0);
        self.has_tank = false;
        self.tank_fuel = 0.0;
        self.tank_fuel_centre = 0.0;
        for (i, s) in self.stations.iter().enumerate().filter(|(i, _)| is_pylon(*i)) {
            let Some(s) = s else { continue };
            let n = if self.weight_fix { s.count } else { 1.0 };
            if s.weapon.is_tank() {
                // The tank's bdb weight becomes fuel (FUN_005a8980: fuel maximum FuelWeight + out[3]).
                self.has_tank = true;
                self.tank_fuel += n * s.weapon.weight_lb * unit;
                if centre(i) {
                    self.tank_fuel_centre += n * s.weapon.weight_lb * unit;
                }
                if self.weight_fix {
                    weight += n * s.weapon.empty_lb * unit;
                }
            } else {
                weight += n * s.weapon.weight_lb * unit;
            }
            weight += s.rack_kg * if self.weight_fix { 1.0 } else { LB_PER_KG };
            let d = n * s.weapon.drag + s.rack_drag;
            if centre(i) {
                left += 0.5 * d;
                right += 0.5 * d;
            } else if i < 4 {
                left += d;
            } else {
                right += d;
            }
        }
        self.load = Load { mass: weight, di_left: (left * 1e-4).max(0.0), di_right: (right * 1e-4).max(0.0) };
    }

    /// `FUN_004583a0`: that side's drag index loses the store's drag (half at station 4, both sides; the left chin 12
    /// and the centreline 13 the same), only when it stays ≥ 0.
    fn release_drag(&mut self, i: usize, w: &Weapon) {
        let d = w.drag * if centre(i) { 0.5 } else { 1.0 };
        let drop = |di: &mut f64| {
            let v = *di * 10000.0 - d;
            if v >= 0.0 {
                *di = (v * 1e-4).max(0.0);
            }
        };
        if i <= 4 || centre(i) {
            drop(&mut self.load.di_left);
        }
        if i >= 4 {
            drop(&mut self.load.di_right);
        }
    }
}

/// What a store needs from the rest of the jet (ours, Modern IAF's data rule, modern-iaf/docs/weapons.md §7.1): the
/// needs of a weapon record's `needs` that no store's `gives` on the jet, nor a built-in sensor, meets. A store with
/// an unmet need cannot be employed: the loadout screen keeps Fly off, the release logic holds it. The 1998 game's
/// records name no needs.
pub fn unmet<'a>(needs: &[&'a str], gives: &[&str]) -> Vec<&'a str> {
    needs.iter().copied().filter(|n| !gives.contains(n)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn needs_met_by_gives() {
        assert_eq!(unmet(&["laser"], &[]), ["laser"]);
        assert!(unmet(&["laser"], &["laser"]).is_empty());
        assert!(unmet(&[], &[]).is_empty());
    }

    fn st(type_code: i64, name: &str, count: f64) -> Option<Station> {
        let weapon =
            Weapon { type_code, name: name.into(), weight_lb: 200.0, drag: 10.0, rounds_per_tick: None, empty_lb: 0.0 };
        Some(Station { weapon, count, initial: count, unlimited: false, arm: 0.0, rack_kg: 0.0, rack_drag: 0.0 })
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
        for (i, st) in stations.iter_mut().enumerate().take(PYLONS) {
            if let Some(st) = st {
                st.arm = i as f64 - 4.0; // 1 m per station, + right
            }
        }
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
    fn the_loading_category_follows_the_air_to_ground_stores() {
        let mut s = f16();
        assert_eq!(s.loading_category(), 3);
        for _ in 0..3 {
            s.fired(2);
            s.fired(6);
        }
        assert_eq!(s.loading_category(), 1, "the bombs gone: missiles and a small tank");
        let mut stations: [Option<Station>; STATIONS] = Default::default();
        stations[3] = st(SHELL, "4006LB", 1.0);
        stations[3].as_mut().unwrap().weapon.weight_lb = 4006.0;
        s.setup(stations);
        assert_eq!(s.loading_category(), 3, "a 600 gal tank");
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
        // Better physics: station 2 lost one MK-82, so the right wing (station 6) is heavier.
        assert!((s.roll_moment() - 200.0 * KG_PER_LB * 2.0).abs() < 1e-9, "{}", s.roll_moment());
        s.jettisoned(4);
        assert!((s.load().di_left - 10e-4).abs() < 1e-12 && (s.load().di_right - 20e-4).abs() < 1e-12);
    }

    #[test]
    fn left_chin_station_loads_weighs_and_drags_both_sides() {
        // Modern IAF (weight fix): the pods on the chin stations, the navigation pod on 12 (0.69 m left), the targeting
        // pod on 4 (0.69 m right); each pod's drag half to each side, its weight in the moment at its arm.
        assert_eq!((pylon_index(b'J'), pylon_index(b'I'), pylon_index(b'-')), (Some(CHIN_LEFT), Some(8), None));
        assert!(is_pylon(CHIN_LEFT) && !is_pylon(9) && !is_pylon(11));
        let mut s = Stores { player: true, weight_fix: true, ..Stores::default() };
        let mut stations: [Option<Station>; STATIONS] = Default::default();
        stations[4] = st(SHELL, "TGP", 1.0);
        stations[CHIN_LEFT] = st(SHELL, "NVP", 1.0);
        stations[4].as_mut().unwrap().arm = 0.69;
        stations[CHIN_LEFT].as_mut().unwrap().arm = -0.69;
        stations[CHIN_LEFT].as_mut().unwrap().weapon.weight_lb = 451.0;
        s.setup(stations);
        let (tgp, nav) = (200.0 * KG_PER_LB, 451.0 * KG_PER_LB);
        assert!((s.load().mass - (tgp + nav)).abs() < 1e-9, "{}", s.load().mass);
        assert_eq!((s.load().di_left, s.load().di_right), (10e-4, 10e-4));
        assert!((s.roll_moment() - 0.69 * (tgp - nav)).abs() < 1e-9, "{}", s.roll_moment());
        // A pod is never selected; a release from 12 (a jettison) takes its weight and half its drag off each side.
        assert!(!s.select_station(CHIN_LEFT));
        s.fired(CHIN_LEFT);
        assert!((s.load().mass - tgp).abs() < 0.05 && (s.load().di_left - 5e-4).abs() < 1e-12);
        // The spawn loadout: an armament of the original's 12 pairs leaves 12 empty; a 13th pair fills it.
        let twelve = [(1, 1); 12];
        assert_eq!(loadout(&twelve, &twelve)[CHIN_LEFT], (0, 0));
        let mut ent = [(0, 0); 13];
        ent[CHIN_LEFT] = (21, 1);
        assert_eq!(loadout(&ent, &twelve)[CHIN_LEFT], (21, 1));
        assert_eq!(loadout(&ent, &twelve)[0], (0, 0), "a set pylon 12 takes the entity's pylons");
    }

    #[test]
    fn centreline_tank_adds_fuel_and_drags_both_sides() {
        // Modern IAF (weight fix): the 300 US gal tank on the centreline, pylon K: its fuel to the tanks', its empty
        // weight to the jet, its drag half to each side, no rolling moment; a jettison takes half its drag off each.
        assert_eq!((pylon_index(b'K'), LETTERS[CENTRELINE]), (Some(CENTRELINE), b'K'));
        assert!(is_pylon(CENTRELINE) && centre(CENTRELINE));
        let mut s = Stores { player: true, weight_fix: true, ..Stores::default() };
        let mut stations: [Option<Station>; STATIONS] = Default::default();
        stations[CENTRELINE] = st(SHELL, "2002LB", 1.0);
        let tank = stations[CENTRELINE].as_mut().unwrap();
        (tank.weapon.weight_lb, tank.weapon.empty_lb) = (2002.0, 360.0);
        s.setup(stations);
        assert!(s.has_tank() && (s.tank_fuel() - 2002.0 * KG_PER_LB).abs() < 1e-9, "{}", s.tank_fuel());
        assert_eq!(s.tank_fuel_centre(), s.tank_fuel(), "the centreline's share: all of it");
        assert!((s.load().mass - 360.0 * KG_PER_LB).abs() < 1e-9, "{}", s.load().mass);
        assert!((s.load().di_left - 5e-4).abs() < 1e-12 && (s.load().di_right - 5e-4).abs() < 1e-12);
        assert_eq!(s.roll_moment(), 0.0);
        s.jettisoned(CENTRELINE);
        assert!(s.load().di_left < 1e-12 && s.load().di_right < 1e-12 && s.load().mass < 1e-9);
        let mut ent = [(0, 0); STATIONS];
        ent[CENTRELINE] = (22, 1);
        assert_eq!(loadout(&ent, &[(1, 1); 12])[CENTRELINE], (22, 1));
    }

    #[test]
    fn a_rack_weighs_with_its_stores_and_stays() {
        // Modern IAF (weight fix): three Mk 82 (500 lb each) on a TER-9/A (47.6 kg) on station 3, 2 m out.
        let mut s = Stores { player: true, weight_fix: true, ..Stores::default() };
        let mut ter = st(500, "MK-82", 3.0).unwrap();
        ter.weapon.weight_lb = 500.0;
        (ter.arm, ter.rack_kg, ter.rack_drag) = (-2.0, 47.6, 6.0);
        s.setup(std::array::from_fn(|i| (i == 3).then(|| ter.clone())));
        let bombs = 3.0 * 500.0 * KG_PER_LB;
        assert!((s.load().mass - (bombs + 47.6)).abs() < 1e-9, "{}", s.load().mass);
        assert!((s.load().di_left - 36e-4).abs() < 1e-12, "three bombs at 10 and the rack's 6");
        assert!((s.roll_moment() + 2.0 * (bombs + 47.6)).abs() < 1e-9);
        // The bombs go, the rack stays.
        for _ in 0..3 {
            s.fired(3);
        }
        assert!((s.load().mass - 47.6).abs() < 0.05, "{}", s.load().mass); // the original's lb round trip
        assert!((s.load().di_left - 6e-4).abs() < 1e-12);
        assert!((s.roll_moment() + 2.0 * 47.6).abs() < 1e-9);
        // Weapon data Real's jettison: the rack leaves too, its weight, drag and moment with it.
        s.jettison_rack(3);
        assert!(s.load().mass < 0.05 && s.load().di_left.abs() < 1e-12 && s.roll_moment().abs() < 1e-9);
        s.jettison_rack(3);
        assert!(s.load().di_left.abs() < 1e-12, "a second jettison changes nothing");
    }

    /// Six MK-82 singles on stations 1–3 / 5–7 (the probe's load), 1 m arms per station.
    fn six_singles() -> Stores {
        let mut s = Stores { player: true, ..Stores::default() };
        let mut stations: [Option<Station>; STATIONS] = Default::default();
        for i in [1, 2, 3, 5, 6, 7] {
            stations[i] = st(500, "MK-82", 1.0);
            stations[i].as_mut().unwrap().arm = i as f64 - 4.0;
        }
        s.setup(stations);
        s.cur = 1;
        s
    }

    fn run(s: &mut Stores, pairs: bool) -> Vec<Vec<usize>> {
        let mut out = Vec::new();
        loop {
            let p = s.real_pulse(pairs);
            if p.is_empty() {
                return out;
            }
            p.iter().for_each(|&i| s.fired(i));
            out.push(p);
        }
    }

    #[test]
    fn real_pairs_symmetric_outboard_first() {
        let mut s = six_singles();
        let mut moments = Vec::new();
        let mut pulses = Vec::new();
        for _ in 0..3 {
            let p = s.real_pulse(true);
            p.iter().for_each(|&i| s.fired(i));
            moments.push(s.roll_moment());
            pulses.push(p);
        }
        assert_eq!(pulses, vec![vec![1, 7], vec![2, 6], vec![3, 5]]);
        assert!(moments.iter().all(|m| m.abs() < 1e-9), "{moments:?}");
        assert!(s.real_pulse(true).is_empty());
    }

    /// The displays ask for the next station every frame (the helmet's cue, the GPS cues): asking must not end the
    /// "just fired" state the SGL mirror reads, or the singles go 1 2 3 7 6 5.
    #[test]
    fn real_singles_alternate_with_displays_asking() {
        let mut s = six_singles();
        let mut out = Vec::new();
        loop {
            assert_eq!(s.next_station(), s.next_station());
            let p = s.real_pulse(false);
            if p.is_empty() {
                break;
            }
            p.iter().for_each(|&i| s.fired(i));
            s.next_station();
            out.push(p);
        }
        assert_eq!(out, [[1], [7], [2], [6], [3], [5]]);
    }

    #[test]
    fn real_singles_alternate_wings() {
        let mut s = six_singles();
        assert_eq!(run(&mut s, false), [[1], [7], [2], [6], [3], [5]]);
    }

    #[test]
    fn real_ter_pairs_and_odd_leftover() {
        // A TER of 3 on stations 3 and 5, and one store on the centreline (4): three pairs, then the single.
        let mut s = six_singles();
        let mut stations: [Option<Station>; STATIONS] = Default::default();
        stations[3] = st(500, "MK-82", 3.0);
        stations[4] = st(500, "MK-82", 1.0);
        stations[5] = st(500, "MK-82", 3.0);
        for (i, st) in stations.iter_mut().enumerate().take(PYLONS) {
            if let Some(st) = st {
                st.arm = i as f64 - 4.0;
            }
        }
        s.setup(stations);
        s.cur = 3;
        assert_eq!(run(&mut s, true), [vec![3, 5], vec![3, 5], vec![3, 5], vec![4]]);
        // SGL on a lopsided load (2 left, 1 right): the heavy side goes first.
        stations_lopsided(&mut s);
        assert_eq!(run(&mut s, false), [[2], [6], [2]]);
    }

    fn stations_lopsided(s: &mut Stores) {
        let mut stations: [Option<Station>; STATIONS] = Default::default();
        stations[2] = st(500, "MK-82", 2.0);
        stations[6] = st(500, "MK-82", 1.0);
        for (i, st) in stations.iter_mut().enumerate().take(PYLONS) {
            if let Some(st) = st {
                st.arm = i as f64 - 4.0;
            }
        }
        s.setup(stations);
        s.cur = 6;
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

    /// Modern IAF's data (finish list F27): a tank's own empty weight loads the jet with the weight fix (the 370 gal
    /// tank's 443 lb, f16net-tanks) and leaves with the jettison; without the fix (the original) it is not counted.
    #[test]
    fn a_tanks_empty_weight_loads_the_jet_until_jettisoned() {
        let tank = |fix: bool| {
            let mut s = Stores { player: true, weight_fix: fix, ..Stores::default() };
            let mut stations: [Option<Station>; STATIONS] = Default::default();
            stations[3] = st(SHELL, "2470LB", 1.0);
            if let Some(t) = stations[3].as_mut() {
                t.weapon.weight_lb = 2470.0;
                t.weapon.empty_lb = 443.0;
                t.arm = -1.5;
            }
            s.setup(stations);
            s
        };
        let mut s = tank(true);
        assert!((s.load.mass - 443.0 * KG_PER_LB).abs() < 1e-9, "{}", s.load.mass);
        assert!((s.tank_fuel - 2470.0 * KG_PER_LB).abs() < 1e-9);
        assert!((s.roll_moment() + 1.5 * 443.0 * KG_PER_LB).abs() < 1e-9, "the empty tank rolls the jet left");
        s.jettisoned(3);
        assert!(s.load.mass.abs() < 1e-9, "{}", s.load.mass);
        assert_eq!(s.roll_moment(), 0.0, "gone with the tank");
        assert_eq!(tank(false).load.mass, 0.0, "the original: a tank's weight is fuel only");
    }
}
