//! `IafStores`: the stores of one aircraft (`iaf_avionics::stores`) for `game/weapons/stores.gd`.

use crate::world::{get, num, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::stores::{self, Category, Station, Stores, Weapon, STATIONS};

/// A station index from GDScript (negative → none).
fn idx(i: i64) -> usize {
    usize::try_from(i).unwrap_or(usize::MAX)
}

/// The [weapon id, count] pairs of a bdb `armament` {hardpoints: [id, n, id, n, ...]}.
fn pairs(d: &VarDictionary) -> Vec<(i64, i64)> {
    let h: VarArray = get::<VarDictionary>(d, "armament").and_then(|a| get(&a, "hardpoints")).unwrap_or_default();
    let n = |i: usize| h.get(i).and_then(|v| v.try_to::<i64>().ok().or_else(|| v.try_to::<f64>().ok().map(|f| f as i64))).unwrap_or(0);
    (0..h.len() / 2).map(|k| (n(2 * k), n(2 * k + 1))).collect()
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafStores {
    stores: Stores,
}

#[godot_api]
impl IafStores {
    /// The loadout an aircraft spawns with (`FUN_0058f110`) from the entity's and the object's armament: [[id, n] × 12].
    #[func]
    fn loadout(entity: VarDictionary, object: VarDictionary) -> VarArray {
        stores::loadout(&pairs(&entity), &pairs(&object)).iter().map(|&(id, n)| varray![id, n].to_variant()).collect()
    }

    /// Weapon category (`FUN_004d72a0`): 0 gun, 1 AA, 2 AG, 3 other.
    #[func]
    fn category(type_code: i64) -> i64 {
        match Category::of(type_code) {
            Category::Gun => 0,
            Category::AirToAir => 1,
            Category::AirToGround => 2,
            Category::Other => 3,
        }
    }

    /// The store positions of a station (glTF); `pilon` the store's Pilon helper or null.
    #[func]
    fn slots(index: i64, attach: Vector3, count: i64, bomb: bool, pilon: Variant) -> VarArray {
        let pilon = pilon.try_to::<Vector3>().ok().map(vec3);
        stores::slots(idx(index), vec3(attach), count, bomb, pilon).into_iter().map(|p| vector3(p).to_variant()).collect()
    }

    /// The 12 stations: {} none, else {type, name, weight_lb, drag, rounds_per_tick (optional), count}.
    #[func]
    fn setup(&mut self, stations: VarArray, player: bool, weight_fix: bool, unlimited: bool) {
        let station = |i: usize| {
            let d = stations.get(i)?.try_to::<VarDictionary>().ok().filter(|d| !d.is_empty())?;
            let weapon = Weapon {
                type_code: num(&d, "type").unwrap_or_default() as i64,
                name: get::<GString>(&d, "name").unwrap_or_default().to_string(),
                weight_lb: num(&d, "weight_lb").unwrap_or_default(),
                drag: num(&d, "drag").unwrap_or_default(),
                rounds_per_tick: num(&d, "rounds_per_tick"),
            };
            let count = num(&d, "count").unwrap_or_default();
            Some(Station { weapon, count, initial: count, unlimited: false })
        };
        self.stores.player = player;
        self.stores.weight_fix = weight_fix;
        self.stores.set_unlimited(unlimited);
        self.stores.setup(std::array::from_fn(station));
    }

    #[func]
    fn cur(&self) -> i64 {
        self.stores.cur as i64
    }

    #[func]
    fn set_cur(&mut self, i: i64) {
        self.stores.cur = idx(i);
    }

    #[func]
    fn displayed(&self, i: i64) -> i64 {
        self.stores.displayed(idx(i))
    }

    #[func]
    fn total(&self, type_code: i64, name: GString) -> i64 {
        self.stores.total(type_code, &name.to_string())
    }

    /// The selection cycle (`FUN_0053b8b0`): kind 1 AA, 2 AG.
    #[func]
    fn cycle(&mut self, kind: i64, allow_gun: bool) {
        self.stores.cycle(if kind == 1 { Category::AirToAir } else { Category::AirToGround }, allow_gun);
    }

    #[func]
    fn select_station(&mut self, i: i64) -> bool {
        self.stores.select_station(idx(i))
    }

    /// The station that fires next, −1 none.
    #[func]
    fn fire_station(&mut self) -> i64 {
        self.stores.fire_station().map_or(-1, |i| i as i64)
    }

    #[func]
    fn fired(&mut self, i: i64) {
        self.stores.fired(idx(i));
    }

    #[func]
    fn jettisoned(&mut self, i: i64) {
        self.stores.jettisoned(idx(i));
    }

    #[func]
    fn consume(&mut self, i: i64) {
        self.stores.consume(idx(i));
    }

    #[func]
    fn set_unlimited(&mut self, on: bool) {
        self.stores.set_unlimited(on);
    }

    #[func]
    fn reload(&mut self) {
        self.stores.reload();
    }

    /// {counts [12] (−1 none), unlimited [12], last_fired, releases, unlimited_all, fm_mass, fm_di_left, fm_di_right,
    /// has_tank, tank_fuel}.
    #[func]
    fn state(&self) -> VarDictionary {
        let s = &self.stores;
        let counts: PackedFloat64Array = (0..STATIONS).map(|i| s.station(i).map_or(-1.0, |st| st.count)).collect();
        let unl: VarArray = (0..STATIONS).map(|i| s.station(i).is_some_and(|st| st.unlimited).to_variant()).collect();
        let load = s.load();
        vdict! {
            "counts" => &counts, "unlimited" => &unl, "last_fired" => s.last_fired() as i64,
            "releases" => s.releases() as i64, "unlimited_all" => s.unlimited(), "fm_mass" => load.mass,
            "fm_di_left" => load.di_left, "fm_di_right" => load.di_right, "has_tank" => s.has_tank(),
            "tank_fuel" => s.tank_fuel(),
        }
    }
}
