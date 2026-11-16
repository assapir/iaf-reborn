//! The release rules of the player's weapons (docs/weapons.md §4–§12): who may fire (`FUN_0044a240`, `FUN_00454270`),
//! the release permission of bombs and jettisons (`FUN_0045ee10`), the ripple settings (`FUN_004562a0` /
//! `FUN_004562f0`), the delayed first bomb, the launch q (`FUN_00457f70`), the laser designation (`FUN_00454b70` case
//! 0x28a) and the TV status (`FUN_00460940`).

use crate::gps::Mode;
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

/// Weapon data Real (ours, docs/real-weapons.md §1.11): the fastest bomb release, KCAS. Low-drag deliveries are
/// limited to 600 KCAS: above it the bomb's fall turns unstable and scatters (T.O. 1-1M-34).
pub const REAL_BOMB_KCAS: f64 = 600.0;
/// Weapon data Real: the steepest release dive, degrees below the horizon: the AGM-65's (T.O. 1-1M-34), held for the
/// bombs too (inferred: no public F-16 bomb dive limit found).
pub const REAL_MAX_DIVE_DEG: f64 = 60.0;
/// Weapon data Real: the AGM-65's launch limits besides the dive, Mach 1.2 and 30° of bank (T.O. 1-1M-34).
pub const REAL_AGM65_MACH: f64 = 1.2;
pub const REAL_AGM65_BANK_DEG: f64 = 30.0;
/// The Maverick's type code.
const AGM65: i64 = 635;
/// m/s to kt.
const KT: f64 = 1.943_844;

/// The calibrated airspeed (kt) of true airspeed `tas` (m/s) at `alt_m` in the standard atmosphere
/// (`iaf_flight::atmosphere::cas`).
pub fn kcas(tas: f64, alt_m: f64) -> f64 {
    iaf_flight::atmosphere::cas(tas as f32, alt_m as f32) as f64 * KT
}

/// Weapon data Real: the release permission of a bomb (500 / 510 / 650) or an AGM-65 (635): the exe's rule
/// ([`release_allowed`]) and the T.O. 1-1M-34 limits: a bomb at most 600 KCAS, a Maverick at most Mach 1.2 and 30° of
/// bank; neither in a dive steeper than 60°. `tas` m/s, `climb` m/s (up +).
pub fn real_release_allowed(type_code: i64, load_factor: f64, roll_deg: f64, tas: f64, alt_m: f64, climb: f64) -> bool {
    let dive = -(climb / tas.max(1.0)).clamp(-1.0, 1.0).asin().to_degrees();
    if !release_allowed(load_factor, roll_deg) || dive > REAL_MAX_DIVE_DEG {
        return false;
    }
    if type_code == AGM65 {
        let mach = tas / iaf_flight::atmosphere::air(alt_m as f32).sound as f64;
        return mach <= REAL_AGM65_MACH && roll_deg.abs() <= REAL_AGM65_BANK_DEG;
    }
    kcas(tas, alt_m) <= REAL_BOMB_KCAS
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
            self.set(self.qty + d, self.interval);
        } else {
            self.set(self.qty, self.interval + 10 * d);
        }
    }

    /// `FUN_004562f0`: quantity 1..14, interval 10..200, the period from the interval. The AI's weapon-change actions
    /// 350 / 360 / 380 set W+0xe8 / 0xec / 0xf0 this way from their bdb 0x82 / 0x96 (`FUN_00452710`).
    pub fn set(&mut self, qty: i64, interval: i64) {
        self.qty = qty.clamp(1, 14);
        self.interval = interval.clamp(10, 200);
        self.period = (self.interval as f64 * 0.001).max(0.1);
    }

    /// Extras "Bomb release" Real (ours, docs/weapons.md §9.10): the release pulses of one Space press. The F-16's
    /// SMS (and every jet but the F-4s, inferred) counts the quantity in pulses, each one store (SGL) or one pair
    /// (PAIRS); the F-4E's AWRU (`awru`, also the Kurnass 2000, inferred) counts stores and drops one pair per press.
    pub fn pulses(&self, pairs: bool, awru: bool) -> i64 {
        if awru && pairs { 1 } else { self.qty }
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

/// An AI jet's homing launch (`FUN_00454b70` with a shooter, types 570 / 580 / 590 / 600 / 610): q 1.0; against a
/// target with its ECM on (only the player has one) a roll `ecm_rand` (0..1) above 0.5 makes q 1 − roll, at least 0.1.
pub fn ai_launch_q(ecm_rand: Option<f64>) -> f64 {
    match ecm_rand {
        Some(r) if r > 0.5 => (1.0 - r).max(Q_MIN),
        _ => 1.0,
    }
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

/// A GPS bomb's aim (ours, docs/weapons.md §13.2), the coordinates handed to it at its release, and whether it is a
/// designation. PRE: the pre-planned target `pre`. VIS: the targeting pod's designated point (`pod`, with the laser
/// on, at most 2 m above the terrain `ground`; in any direction), else the radar's designated point (`td`, the HUD's
/// TD box). Without one of them the bombs' own aim (`ripple`: the CCIP / delayed CCIP).
pub fn gps_aim(
    mode: Mode,
    pre: Option<Vec3>,
    ripple: Vec3,
    pod: Option<Vec3>,
    ground: f64,
    td: Option<Vec3>,
) -> (Vec3, bool) {
    let vis = || pod.filter(|d| d.z <= ground + LASER_ABOVE).or(td);
    match if mode == Mode::Pre { pre } else { vis() } {
        Some(d) => (d, true),
        None => (ripple, false),
    }
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

    #[test]
    fn ai_ripple_from_the_action() {
        let mut r = Ripple::default();
        r.set(2, 20); // default6_1.bdb action 380: 2 bombs, 20 m
        assert_eq!((r.qty, r.interval, r.period), (2, 20, 0.1));
        r.set(0, 0); // 350 / 360: quantity 1, interval 0
        assert_eq!((r.qty, r.interval), (1, 10));
        r.set(40, 500);
        assert_eq!((r.qty, r.interval, r.period), (14, 200, 0.2));
    }

    use super::*;

    #[test]
    fn ai_launch_q_against_a_jammer() {
        assert_eq!(ai_launch_q(None), 1.0);
        assert_eq!(ai_launch_q(Some(0.4)), 1.0, "a roll up to 0.5 does not count");
        assert!((ai_launch_q(Some(0.7)) - 0.3).abs() < 1e-12);
        assert_eq!(ai_launch_q(Some(0.99)), Q_MIN);
    }

    #[test]
    fn real_pulses() {
        let r = Ripple { qty: 3, ..Ripple::default() };
        assert_eq!((r.pulses(true, false), r.pulses(false, false)), (3, 3), "SMS: 3 pulses of a pair or a store");
        assert_eq!((r.pulses(true, true), r.pulses(false, true)), (1, 3), "AWRU: one pair per press");
    }

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
    fn real_release_limits() {
        // Calibrated airspeed: equal to the true at sea level; 348 KTAS at 10,000 ft is 300 KCAS (the standard
        // airspeed table); the two pitot formulas meet at Mach 1.
        assert!((kcas(600.0 / KT, 0.0) - 600.0).abs() < 0.5, "{}", kcas(600.0 / KT, 0.0));
        let k10 = kcas(348.0 / KT, 3048.0);
        assert!((k10 - 300.0).abs() < 3.0, "348 KTAS at 10,000 ft: {k10:.1} KCAS");
        let a20 = iaf_flight::atmosphere::air(6096.0).sound as f64;
        let (below, above) = (kcas(0.9999 * a20, 6096.0), kcas(1.0001 * a20, 6096.0));
        assert!(above > below && above - below < 0.2, "Mach 1 at 20,000 ft: {below:.2} / {above:.2} KCAS");
        let level = |t, kt: f64, alt| real_release_allowed(t, 1.0, 0.0, kt / KT, alt, 0.0);
        // T.O. 1-1M-34: low-drag bombs at most 600 KCAS.
        assert!(level(500, 595.0, 0.0) && !level(500, 605.0, 0.0));
        assert!(level(650, 640.0, 3048.0), "640 KTAS at 10,000 ft is under 600 KCAS: the limit is calibrated");
        // Dive: 59° allowed, 61° refused (bombs and the AGM-65).
        let v = 250.0;
        let dive = |t, deg: f64| real_release_allowed(t, 1.0, 0.0, v, 3000.0, -v * deg.to_radians().sin());
        assert!(dive(500, 59.0) && !dive(500, 61.0) && dive(635, 59.0) && !dive(635, 61.0));
        // The AGM-65: Mach 1.2 and 30° of bank (sea level: 340.3 m/s a Mach).
        assert!(real_release_allowed(635, 1.0, 29.0, 1.19 * 340.3, 0.0, 0.0));
        assert!(!real_release_allowed(635, 1.0, 31.0, 300.0, 0.0, 0.0));
        assert!(!real_release_allowed(635, 1.0, 0.0, 1.21 * 340.3, 0.0, 0.0));
        // The exe's rule still holds under Real.
        assert!(!real_release_allowed(500, -0.5, 0.0, 200.0, 0.0, 0.0));
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

    #[test]
    fn gps_aim_pre_or_pod_then_td_then_ccip() {
        let (ccip, pod, td) = (Vec3::new(0.0, 1.0, 0.0), Vec3::new(0.0, -9000.0, 0.0), Vec3::new(5.0, 5.0, 0.0));
        let pre = Vec3::new(3000.0, 8000.0, 0.0);
        let vis = |pod, td| gps_aim(Mode::Vis, Some(pre), ccip, pod, 0.0, td);
        assert_eq!(vis(Some(pod), Some(td)), (pod, true), "behind the jet too: no seeker cone");
        assert_eq!(vis(Some(pod + Vec3::UP * 50.0), Some(td)), (td, true), "a pod point in the air");
        assert_eq!(vis(None, None), (ccip, false));
        // PRE: the pre-planned coordinates whatever the sensors point at; none set: the CCIP.
        assert_eq!(gps_aim(Mode::Pre, Some(pre), ccip, Some(pod), 0.0, Some(td)), (pre, true));
        assert_eq!(gps_aim(Mode::Pre, None, ccip, Some(pod), 0.0, Some(td)), (ccip, false));
    }
}
