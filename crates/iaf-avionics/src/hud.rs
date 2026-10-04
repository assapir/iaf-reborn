//! The HUD's weapon values (the cockpit snapshot `FUN_00456520` → `FUN_00445bb0`): the MRM shoot cue and the HARM's
//! "In Range" (`FUN_00460ee0` / `FUN_00460ac0`), the lock bearing (state+0x4c, `FUN_00429390` ← `FUN_0044e770`), the
//! missile counts of the SRM / MRM windows and the CCIP time-to-go cap (`FUN_00445db0`).

use crate::missile::Dlz;
use crate::stores::Stores;
use crate::vec3::Vec3;
use std::f64::consts::{PI, TAU};

/// The mode-5 object's time-to-go is capped at 1000 s in the cockpit state (+0x638).
const TTG_MAX: f64 = 1000.0;

/// The MRM shoot cue (state+0x1010): the predicted point inside the circle, rounds left, the radar in A-A and the target
/// between the DLZ's min and max.
pub fn shoot_cue(inside: bool, rounds_left: bool, radar_aa: bool, dlz: Option<Dlz>, dist: f64) -> bool {
    inside && rounds_left && radar_aa && dlz.is_some_and(|z| dist >= z.min && dist <= z.max)
}

/// The HARM's "In Range" (+0xdf0): rounds left and the selected emitter nearer than the DLZ max.
pub fn harm_in_range(rounds_left: bool, dlz: Option<Dlz>, dist: f64) -> bool {
    rounds_left && dlz.is_some_and(|z| dist < z.max)
}

/// The locked target's bearing from the own heading (rad, wrapped ±π; the caret on the missile circle).
pub fn lock_bearing(own: Vec3, yaw: f64, target: Vec3) -> f64 {
    let d = target - own;
    (d.x.atan2(d.y) - yaw + PI).rem_euclid(TAU) - PI
}

/// The SRM (570 / 580) and MRM (600 / 610) rounds over every station.
pub fn missile_counts(stores: &Stores) -> (i64, i64) {
    stores.stations().fold((0, 0), |(srm, mrm), (_, s)| match s.weapon.type_code {
        570 | 580 => (srm + s.displayed(), mrm),
        600 | 610 => (srm, mrm + s.displayed()),
        _ => (srm, mrm),
    })
}

/// The CCIP time-to-go as the cockpit gets it.
pub fn ttg_shown(ttg: f64) -> f64 {
    ttg.min(TTG_MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cues() {
        let z = Some(Dlz { max: 10000.0, min: 2000.0 });
        assert!(shoot_cue(true, true, true, z, 5000.0));
        assert!(!shoot_cue(true, true, true, z, 1000.0) && !shoot_cue(true, true, false, z, 5000.0));
        assert!(harm_in_range(true, z, 9000.0) && !harm_in_range(true, None, 9000.0));
        assert!((lock_bearing(Vec3::ZERO, 0.1, Vec3::new(0.0, -1.0, 0.0)) - (PI - 0.1)).abs() < 1e-12);
    }
}
