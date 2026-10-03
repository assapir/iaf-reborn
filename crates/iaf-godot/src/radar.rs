//! `IafRadar`: the player's radar (`iaf_avionics::radar`, docs/radar.md) for `game/weapons/radar.gd`.
//!
//! `set_input` hands over the own jet, the units and the terrain before a call that can scan; `state()` and
//! `events()` read the result back.

use crate::world::{get, terrain, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::radar::{Contact, Event, Input, Own, Radar, Unit};

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRadar {
    radar: Option<Radar>,
    own: Own,
    units: Vec<Unit>,
    terrain: Option<Callable>,
}

impl IafRadar {
    /// Runs `f` on the radar with the last input; a no-op before `setup`.
    fn with<R: Default>(&mut self, f: impl FnOnce(&mut Radar, &Input) -> R) -> R {
        let terrain = terrain(self.terrain.clone());
        let input = Input { own: self.own, units: &self.units, terrain: &terrain };
        self.radar.as_mut().map(|r| f(r, &input)).unwrap_or_default()
    }
}

fn contact(r: &Radar, c: &Contact) -> VarDictionary {
    vdict! {
        "key" => c.key.as_str(),
        "pos" => vector3(c.pos),
        "heading" => c.heading,
        "locked" => r.is_locked(c),
        "selected" => r.is_selected(c),
        "hostile" => c.hostile,
        "prio" => c.priority(),
        "aspect" => c.aspect,
        "az" => c.az,
        "el" => c.el,
        "dist" => c.dist,
        "speed" => c.speed_kt,
        "type" => c.type_code,
        "alt" => c.pos.z,
    }
}

fn record(r: &Radar, c: Option<&Contact>) -> VarDictionary {
    c.map(|c| contact(r, c)).unwrap_or_default()
}

fn unit(u: &VarDictionary) -> Unit {
    Unit {
        key: get::<GString>(u, "key").unwrap_or_default().to_string(),
        pos: vec3(get(u, "pos").unwrap_or_default()),
        vel: vec3(get(u, "vel").unwrap_or_default()),
        class: get(u, "klass").unwrap_or(-1),
        state: get(u, "state").unwrap_or(1),
        coll_radius: get(u, "coll_radius").unwrap_or_default(),
        heading: get(u, "heading").unwrap_or_default(),
        type_code: get(u, "type").unwrap_or(-1),
        hostile: get(u, "hostile").unwrap_or(true),
    }
}

#[godot_api]
impl IafRadar {
    /// Create (`FUN_004ace60`) for cockpit index `cockpit` (`FUN_00447e70`); `lrs_nm` > 0: the LRS / STT detection
    /// range (Weapon data Real).
    #[func]
    fn setup(&mut self, cockpit: i64, lrs_nm: f64) {
        self.radar = Some(Radar::new(usize::try_from(cockpit).unwrap_or(1), (lrs_nm > 0.0).then_some(lrs_nm)));
    }

    /// The own jet {pos, fwd, yaw}, the units [{key, pos, vel, klass, state, coll_radius, heading, type, hostile}]
    /// and the terrain (Callable(Vector3) -> float or null) for the next calls.
    #[func]
    fn set_input(&mut self, own: VarDictionary, units: VarArray, terrain: Callable) {
        self.own = Own {
            pos: vec3(get(&own, "pos").unwrap_or_default()),
            fwd: vec3(get(&own, "fwd").unwrap_or_default()),
            yaw: get(&own, "yaw").unwrap_or_default(),
        };
        self.units = units.iter_shared().filter_map(|v| v.try_to::<VarDictionary>().ok()).map(|u| unit(&u)).collect();
        self.terrain = Some(terrain);
    }

    #[func]
    fn update(&mut self, now: f64) {
        self.with(|r, i| r.update(now, i));
    }

    #[func]
    fn scan(&mut self, now: f64) {
        self.with(|r, i| r.scan(now, i));
    }

    #[func]
    fn cycle_mode(&mut self, now: f64) {
        self.with(|r, i| r.cycle_mode(now, i));
    }

    #[func]
    fn toggle_aa_ag(&mut self, now: f64) {
        self.with(|r, i| r.toggle_aa_ag(now, i));
    }

    #[func]
    fn step_range(&mut self, step: i64, now: f64) {
        let step = if step < 0 { -1 } else { 1 };
        self.with(|r, i| r.step_range(step, now, i));
    }

    #[func]
    fn deselect(&mut self, now: f64) {
        self.with(|r, i| r.deselect(now, i));
    }

    #[func]
    fn designate(&mut self, point: Vector3, now: f64) {
        self.with(|r, i| r.designate(vec3(point), now, i));
    }

    #[func]
    fn standby(&mut self) {
        self.with(|r, _| r.standby());
    }

    #[func]
    fn boresight(&mut self, down: bool) {
        self.with(|r, _| r.boresight(down));
    }

    #[func]
    fn next_target(&mut self, forward: bool) {
        self.with(|r, _| r.next_target(forward));
    }

    #[func]
    fn lock_key(&mut self, key: GString) -> bool {
        self.with(|r, _| r.lock_key(&key.to_string()))
    }

    #[func]
    fn lock_stt(&mut self) {
        self.with(|r, _| r.lock_stt());
    }

    #[func]
    fn toggle_exp(&mut self) {
        self.with(|r, _| r.toggle_exp());
    }

    #[func]
    fn set_damaged(&mut self, on: bool) {
        self.with(|r, _| r.set_damaged(on));
    }

    /// Everything the cockpit and the weapons read: mode, last_aa, aa, off, damaged, bore_held, sel_key, sel_locked,
    /// contacts, stt ({} none), locked ({} none: the HUD / gun / seeker target), has_lock, antenna, heading_shift,
    /// designated, desig, exp, modes {mode: {max, nm, idx}}, range_index, range_m, scope_width.
    #[func]
    fn state(&self) -> VarDictionary {
        let Some(r) = &self.radar else { return VarDictionary::new() };
        let contacts: VarArray = r.contacts().iter().map(|c| contact(r, c).to_variant()).collect();
        let mut modes = VarDictionary::new();
        for (m, range) in r.ranges().iter() {
            modes.set(m as i64, &vdict! { "max" => range.max, "nm" => range.nm, "idx" => range.index });
        }
        let selection = r.selection();
        let (az, el) = r.antenna();
        vdict! {
            "mode" => r.mode() as i64,
            "last_aa" => r.last_aa() as i64,
            "aa" => r.air_to_air(),
            "off" => !r.mode().radiating(),
            "damaged" => r.damaged(),
            "bore_held" => r.bore_held(),
            "sel_key" => selection.map_or("", |s| s.key.as_str()),
            "sel_locked" => selection.is_some_and(|s| s.locked),
            "contacts" => &contacts,
            "stt" => &record(r, r.stt()),
            "locked" => &record(r, r.locked()),
            "has_lock" => r.has_lock(),
            "antenna" => Vector2::new(az as f32, el as f32),
            "heading_shift" => r.heading_shift(),
            "designated" => r.designated().is_some(),
            "desig" => vector3(r.designated().unwrap_or_default()),
            "exp" => r.expanded(),
            "modes" => &modes,
            "range_index" => r.range_index(),
            "range_m" => r.range_m(),
            "scope_width" => r.scope_width(),
        }
    }

    /// The events since the last call, in order: ["lock", key, on] (the target's RWR) or ["illum"] (`FUN_00458130`,
    /// the semi-active missiles lose their guidance).
    #[func]
    fn events(&mut self) -> VarArray {
        let Some(r) = &mut self.radar else { return VarArray::new() };
        r.take_events()
            .into_iter()
            .map(|e| match e {
                Event::Lock { key, on } => varray!["lock", key, on],
                Event::IlluminationLost => varray!["illum"],
            })
            .map(|a| a.to_variant())
            .collect()
    }
}
