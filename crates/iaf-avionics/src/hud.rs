//! The HUD's weapon values (the cockpit snapshot `FUN_00456520` → `FUN_00445bb0`): the MRM shoot cue and the HARM's
//! "In Range" (`FUN_00460ee0` / `FUN_00460ac0`), the lock bearing (state+0x4c, `FUN_00429390` ← `FUN_0044e770`), the
//! missile counts of the SRM / MRM windows and the CCIP time-to-go cap (`FUN_00445db0`).

use crate::missile::Dlz;
use crate::stores::Stores;
use crate::vec3::Vec3;
use std::f64::consts::{PI, TAU};

/// The mode-5 object's time-to-go is capped at 1000 s in the cockpit state (+0x638).
const TTG_MAX: f64 = 1000.0;
/// Metres per NM of the radar range (R+0x2748).
const NM: f64 = 1853.0;

/// The HUD range scale's rows (`FUN_005397a0`, HUD modes 1 / 2 / 7 with a radar lock), down from the scale's top.
#[derive(Debug, PartialEq)]
pub struct RangeScale {
    /// The DLZ bracket at the min (S+0x350) and max (S+0x348) range, held on the scale.
    pub min: i32,
    pub max: i32,
    /// The lock's range caret (S+0x388), not held.
    pub caret: i32,
}

/// The range scale `h` px high over the radar range (NM); without a DLZ its ranges read 0 (the bracket at the bottom).
pub fn range_scale(h: i32, range_nm: f64, dlz: Option<Dlz>, dist: f64) -> RangeScale {
    let k = f64::from(h) / (range_nm * NM);
    let row = |m: f64| h - (m * k) as i32;
    let z = dlz.unwrap_or(Dlz { max: 0.0, min: 0.0 });
    RangeScale { min: row(z.min).clamp(0, h), max: row(z.max).clamp(0, h), caret: row(dist) }
}

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

    #[test]
    fn range_scale_rows() {
        // 10 NM over 66 px: 5 NM half way, the DLZ max beyond the scale held at the top, the caret not held.
        let z = Some(Dlz { max: 30000.0, min: 1853.0 });
        assert_eq!(range_scale(66, 10.0, z, 9265.0), RangeScale { min: 60, max: 0, caret: 33 });
        assert_eq!(range_scale(66, 10.0, z, 37060.0).caret, -66);
        assert_eq!(range_scale(66, 10.0, None, 0.0), RangeScale { min: 66, max: 66, caret: 66 });
    }
}
