//! The release rules of the player's weapons (docs/weapons.md §4–§12): who may fire (`FUN_0044a240`, `FUN_00454270`),
//! the release permission of bombs and jettisons (`FUN_0045ee10`), the ripple settings (`FUN_004562a0` /
//! `FUN_004562f0`), the delayed first bomb, the launch q (`FUN_00457f70`), the laser designation (`FUN_00454b70` case
//! 0x28a) and the TV status (`FUN_00460940`).

use crate::vec3::Vec3;

/// The delayed release: the first bomb off the HUD waits for time-to-go ≤ 0.9 s (_DAT_0082f528).
pub const TTG_RELEASE: f64 = 0.9;
/// Launch q without Easy aiming (v1.1: ×0.8, 0x600f64) and the q of an unlocked target (0x82f6ec).
pub const Q_NO_EASY: f64 = 0.8;
pub const Q_UNLOCKED: f64 = 0.1;
/// The lowest q of a launch at a target.
const Q_MIN: f64 = 0.1;
/// The laser designation: within 60° of the line to the bomb's point (0x82f4e0 from 0x600ee8), at most 2 m above the
/// terrain (0x600f08).
const LASER_CONE_DEG: f64 = 60.0;
const LASER_ABOVE: f64 = 2.0;

/// `FUN_0045ee10`, the release permission of bombs and jettisons: load factor ≥ 0 and |roll| ≤ 90°.
pub fn release_allowed(load_factor: f64, roll_deg: f64) -> bool {
    load_factor >= 0.0 && roll_deg.abs() <= 90.0
}

/// Space (event 0x40): HUD mode 1..8; the gear handle down only with Safety off and the gun; not with weapon systems
/// damage (flag 20).
pub fn space_allowed(hud: i64, gear_down: bool, safety_off: bool, gun: bool, weapons_damaged: bool) -> bool {
    (1..=8).contains(&hud) && (!gear_down || (safety_off && gun)) && !weapons_damaged
}

/// The ripple settings (W+0xd4 quantity 1..14, W+0xd8 interval 10..200: the spacing in m and the period in ms, W+0xdc
/// the period: interval × 0.001 s @0x600f48, at least 0.1 s @0x600f0c).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Ripple {
    pub qty: i64,
    pub interval: i64,
    pub period: f64,
}

impl Default for Ripple {
    /// `FUN_004585f0`: 2 bombs, 10 m, 0.3 s (@0x600eb0).
    fn default() -> Self {
        Ripple { qty: 2, interval: 10, period: 0.3 }
    }
}

impl Ripple {
    /// Events 0x4a (quantity ±1) / 0x4b (interval ±10) → `FUN_004562a0` → `FUN_004562f0`.
    pub fn step(&mut self, quantity: bool, up: bool) {
        let d = if up { 1 } else { -1 };
        if quantity {
            self.qty = (self.qty + d).clamp(1, 14);
        } else {
            self.interval = (self.interval + 10 * d).clamp(10, 200);
        }
        self.period = (self.interval as f64 * 0.001).max(0.1);
    }

    /// The ripple line index of the next bomb (`ripple_left` bombs left).
    pub fn index(&self, left: i64) -> usize {
        (self.qty - left).clamp(0, (self.qty - 1).max(0)) as usize
    }
}

/// The first bomb of a ripple off the HUD waits for time-to-go ≤ 0.9 s.
pub fn first_bomb_waits(off_hud: bool, first: bool, ttg: f64) -> bool {
    off_hud && first && ttg > TTG_RELEASE
}

/// What a launch's target came from (the HUD mode's object).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Sight {
    /// HUD mode 1: the IR seeker's target inside its circle; locked or not.
    Seeker { locked: bool },
    /// HUD modes 2 / 8: the MRM / HARM sight's q (vfunc +0x38).
    Circle { q: f64 },
}

/// The launch q (`FUN_00457f70`) with a target: the sight's q × 0.8 without Easy aiming (1 with it); against the radar
/// seeker (HUD mode 2) a target with its ECM on loses `ecm_rand` (0..1); at least 0.1.
pub fn launch_q(sight: Sight, easy: bool, ecm: Option<f64>) -> f64 {
    let q = if easy {
        1.0
    } else {
        match sight {
            Sight::Seeker { locked } => (if locked { 1.0 } else { Q_UNLOCKED }) * Q_NO_EASY,
            Sight::Circle { q } => q * Q_NO_EASY,
        }
    };
    (q - ecm.unwrap_or(0.0)).max(Q_MIN)
}

/// `FUN_00454b70` case 0x28a: with the laser on, the designation replaces the ripple aim when it lies within 60° of the
/// line to the bomb's point `p` and at most 2 m above the terrain `ground`; else the ripple aim.
pub fn laser_aim(own: Vec3, p: Vec3, ripple: Vec3, designation: Option<Vec3>, ground: f64) -> Vec3 {
    let Some(d) = designation else { return ripple };
    let (Some(to_d), Some(to_p)) = ((d - own).try_normalize(), (p - own).try_normalize()) else { return ripple };
    if to_d.dot(to_p) < LASER_CONE_DEG.to_radians().cos() || d.z > ground + LASER_ABOVE {
        return ripple;
    }
    d
}

/// The TV status (`FUN_00460940`): 0 NO SOURCE unless the TV weapon (the flying one, else the selected store) is a 635 /
/// 640 / 650; 1 RDY before launch and for a launched Maverick, else the guided weapon's 2 TRA / 3 TER
/// (`guided_status`); 0 when the selected store has no rounds left and (nothing flies or a Maverick flies).
pub fn tv_status(flying: Option<i64>, guided_status: i64, selected: i64, selected_left: i64) -> i64 {
    let t = flying.unwrap_or(selected);
    if !matches!(t, 635 | 640 | 650) {
        return 0;
    }
    let mut st = 1;
    if flying.is_some() && t != 635 {
        st = guided_status;
    }
    if selected_left == 0 && (flying.is_none() || t == 635) {
        st = 0;
    }
    st
}

/// `FUN_004d6ac0`: a weapon's time left on the HUD / TV page: below 0 → 0, above 300 → 60.
pub fn shown_time(v: f64) -> f64 {
    if v < 0.0 {
        0.0
    } else if v > 300.0 {
        60.0
    } else {
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ripple_limits() {
        let mut r = Ripple::default();
        for _ in 0..20 {
            r.step(true, true);
            r.step(false, false);
        }
        assert_eq!(r, Ripple { qty: 14, interval: 10, period: 0.1 });
        r.step(false, true);
        assert!((r.period - 0.1).abs() < 1e-12 && r.interval == 20);
        assert_eq!(r.index(14), 0);
    }

    #[test]
    fn q_and_permissions() {
        assert!((launch_q(Sight::Seeker { locked: false }, false, None) - 0.1).abs() < 1e-12, "0.08 → at least 0.1");
        assert_eq!(launch_q(Sight::Circle { q: 0.5 }, true, None), 1.0);
        assert!(!space_allowed(5, true, true, false, false) && space_allowed(3, true, true, true, false));
        assert!(!release_allowed(-0.5, 0.0) && release_allowed(1.0, -90.0));
    }

    #[test]
    fn tv_and_laser() {
        assert_eq!(tv_status(None, 0, 640, 2), 1);
        assert_eq!(tv_status(Some(640), 3, 500, 0), 3);
        assert_eq!(tv_status(Some(635), 0, 635, 0), 0);
        let own = Vec3::new(0.0, 0.0, 3000.0);
        let p = Vec3::new(0.0, 5000.0, 0.0);
        assert_eq!(laser_aim(own, p, p, Some(Vec3::new(100.0, 5000.0, 0.0)), 0.0), Vec3::new(100.0, 5000.0, 0.0));
        assert_eq!(laser_aim(own, p, p, Some(Vec3::new(0.0, -5000.0, 0.0)), 0.0), p, "behind: refused");
        assert_eq!(shown_time(400.0), 60.0);
    }
}
