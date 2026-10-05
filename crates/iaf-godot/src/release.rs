//! `IafRelease`: the player's release rules and the HUD's weapon cues (`iaf_avionics::{release, hud}`) as statics for
//! `game/weapons/player_weapons.gd`, and `IafRipple` (the ripple settings).

use crate::world::{vec3, vector3};
use godot::prelude::*;
use iaf_avionics::hud;
use iaf_avionics::missile::Dlz;
use iaf_avionics::release::{self, Ripple, Sight};

/// A DLZ [max, min] ([] none).
fn dlz(a: &VarArray) -> Option<Dlz> {
    let at = |i| a.get(i).and_then(|v| v.try_to::<f64>().ok());
    at(0).zip(at(1)).map(|(max, min)| Dlz { max, min })
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRelease {}

#[godot_api]
impl IafRelease {
    #[func]
    fn release_allowed(load_factor: f64, roll_deg: f64) -> bool {
        release::release_allowed(load_factor, roll_deg)
    }

    #[func]
    fn space_allowed(hud: i64, gear_down: bool, safety_off: bool, gun: bool, weapons_damaged: bool) -> bool {
        release::space_allowed(hud, gear_down, safety_off, gun, weapons_damaged)
    }

    #[func]
    fn first_bomb_waits(off_hud: bool, first: bool, ttg: f64) -> bool {
        release::first_bomb_waits(off_hud, first, ttg)
    }

    /// The launch q: HUD mode 1 the seeker (`locked`), else the sight's `q`; `ecm` the ECM loss (null none).
    #[func]
    fn launch_q(hud_mode: i64, locked: bool, q: f64, easy: bool, ecm: Variant) -> f64 {
        let sight = if hud_mode == 1 { Sight::Seeker { locked } } else { Sight::Circle { q } };
        release::launch_q(sight, easy, ecm.try_to::<f64>().ok())
    }

    /// `designation` a world point or null.
    #[func]
    fn laser_aim(own: Vector3, p: Vector3, ripple: Vector3, designation: Variant, ground: f64) -> Vector3 {
        let d = designation.try_to::<Vector3>().ok().map(vec3);
        vector3(release::laser_aim(vec3(own), vec3(p), vec3(ripple), d, ground))
    }

    /// `flying` the flying TV weapon's type (−1 none).
    #[func]
    fn tv_status(flying: i64, guided_status: i64, selected: i64, selected_left: i64) -> i64 {
        release::tv_status((flying >= 0).then_some(flying), guided_status, selected, selected_left)
    }

    #[func]
    fn shown_time(v: f64) -> f64 {
        release::shown_time(v)
    }

    #[func]
    fn shoot_cue(inside: bool, rounds_left: bool, radar_aa: bool, z: VarArray, dist: f64) -> bool {
        hud::shoot_cue(inside, rounds_left, radar_aa, dlz(&z), dist)
    }

    #[func]
    fn harm_in_range(rounds_left: bool, z: VarArray, dist: f64) -> bool {
        hud::harm_in_range(rounds_left, dlz(&z), dist)
    }

    #[func]
    fn lock_bearing(own: Vector3, yaw: f64, target: Vector3) -> f64 {
        hud::lock_bearing(vec3(own), yaw, vec3(target))
    }

    #[func]
    fn ttg_shown(ttg: f64) -> f64 {
        hud::ttg_shown(ttg)
    }

    /// The HUD range scale's rows (min, max, caret).
    #[func]
    fn range_scale(h: i32, range_nm: f64, z: VarArray, dist: f64) -> Vector3i {
        let r = hud::range_scale(h, range_nm, dlz(&z), dist);
        Vector3i::new(r.min, r.max, r.caret)
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRipple {
    ripple: Ripple,
}

#[godot_api]
impl IafRipple {
    /// Events 0x4a (quantity) / 0x4b (interval), ±.
    #[func]
    fn step(&mut self, quantity: bool, up: bool) {
        self.ripple.step(quantity, up);
    }

    #[func]
    fn qty(&self) -> i64 {
        self.ripple.qty
    }

    #[func]
    fn interval(&self) -> i64 {
        self.ripple.interval
    }

    #[func]
    fn period(&self) -> f64 {
        self.ripple.period
    }

    #[func]
    fn set_qty(&mut self, q: i64) {
        self.ripple.qty = q;
    }

    #[func]
    fn index(&self, left: i64) -> i64 {
        self.ripple.index(left) as i64
    }
}
