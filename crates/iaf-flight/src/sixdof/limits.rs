//! The jets' physical limits and what passing them does (modern-iaf/docs/flight-model.md §9.20): the airframe's g and
//! speed, the gear's speed, the tyres' ground speed, the brakes' energy, the centre of gravity and a category III
//! load's lower departure resistance. The flight ([`super::flight::SixDof`]) applies them; the original model never
//! reaches this module.
//!
//! A limit is the placard; the structure gives way past its design margins, not at it:
//! * the manual's over-g report (an inspection) at 9.5 / −3.2 g of the F-16's +9 / −3 (T.O. GR1F-16CJ-1 p. 5-3),
//!   the same fractions on every jet (inferred);
//! * permanent damage from [`DAMAGE`] × the limit load: a structure carries its limit load "without detrimental
//!   permanent deformation" (14 CFR 25.305), the 15 % margin to damage is inferred;
//! * failure at [`ULTIMATE`] × the limit load, the factor of safety of 14 CFR 25.303 (1.5) taken for the military
//!   jets (inferred: the US military's own airframe specifications use the same 1.5);
//! * flutter, the airframe's failure from speed, at [`FLUTTER`] × the limit speed (inferred: the 15 % flutter margin
//!   of the US military's airframe flutter specification, quoted from memory); damage from [`SPEED_DAMAGE`] ×
//!   (inferred: panels and doors before the flutter).

use super::fuel::{AFT, FUSELAGE, FWD, RSVR, Tanks};
use crate::units::LB;

/// The over-g report's loads as fractions of the F-16's +9 / −3 g (9.5 / 9 and 3.2 / 3).
pub const INSPECT: (f64, f64) = (9.5 / 9.0, 3.2 / 3.0);
/// Permanent structural damage, × the limit load (inferred).
pub const DAMAGE: f64 = 1.15;
/// Structural failure, × the limit load (14 CFR 25.303).
pub const ULTIMATE: f64 = 1.5;
/// A damaged structure's failure, × the limit load (inferred: between the damage and the ultimate load).
pub const WEAK_ULTIMATE: f64 = 1.3;
/// Damage from speed, × the limit speed (inferred).
pub const SPEED_DAMAGE: f64 = 1.1;
/// Flutter: failure from speed, × the limit speed (inferred).
pub const FLUTTER: f64 = 1.15;
/// A rolling manoeuvre: the roll rate past 20 deg/s (T.O. GR1F-16CJ-1 p. 5-4, the note).
pub const ROLLING_DEG_S: f64 = 20.0;
/// A category III load's structural g limit while rolling, × the symmetric limit (inferred: the rolling pull-out at
/// 80 % of the symmetric limit of the US military's airframe strength specification; the real figures are in the
/// stores supplement, not public). Category I loads keep the symmetric limit while rolling (inferred).
pub const CAT3_ROLLING: f64 = 0.8;

/// One jet's limits.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Limits {
    /// The airframe's limit speed: calibrated airspeed, kt, and Mach.
    pub kcas: f64,
    pub mach: f64,
    /// The gear down or moving: calibrated airspeed, kt, and Mach (the lower holds).
    pub gear: (f64, f64),
    /// The main tyres' ground speed, kt.
    pub tyre_kt: f64,
    /// The brakes' energy, as a full stop from this ground speed (kt) at the jet's reference weight: past it they
    /// fade ([`Brakes`]).
    pub brake_kt: f64,
    /// The load categories apply (the F-16's STORES CONFIG): a category III load departs more easily and has the
    /// rolling g limit ([`CAT3_ROLLING`], [`cat3_cn`]).
    pub categories: bool,
}

/// The F-16 (T.O. GR1F-16CJ-1): 800 KCAS to 30,000 ft, Mach 2.05 above (p. 5-2); the gear 300 KCAS / Mach 0.65
/// (figure 5-6); the main tyres 225 kt of ground speed (p. 5-2). The brakes: a stop from 150 kt (inferred: the
/// brake energy charts are in the performance supplement, not public).
pub const F16: Limits =
    Limits { kcas: 800.0, mach: 2.05, gear: (300.0, 0.65), tyre_kt: 225.0, brake_kt: 150.0, categories: true };
/// The F-35A's 700 KCAS placard (inferred: `jets.rs`) and Mach 1.6 (Lockheed Martin's top speed); the gear, the
/// tyres and the brakes the F-16's (inferred: no public figure); no load categories.
pub const F35: Limits = Limits { kcas: 700.0, mach: 1.6, categories: false, ..F16 };
/// The F-15E's 800 KCAS and Mach 2.5; the gear, the tyres and the brakes the F-16's (inferred); no load categories.
/// A jet's aircraft definition `gear_limit` is the gear's one source: the flight sets it over the `gear` here
/// ([`crate::sixdof::flight::SixDof::set_gear_limit`]).
pub const F15: Limits = Limits { kcas: 800.0, mach: 2.5, categories: false, ..F16 };
/// The MiG-29A: its published top speeds as its limits, 1,500 km/h (810 kt) low down and Mach 2.3 (Wikipedia; as
/// placards inferred); the gear, the tyres and the brakes the F-16's (inferred); no load categories.
pub const MIG29: Limits = Limits { kcas: 810.0, mach: 2.3, categories: false, ..F16 };

/// How hard a load or a speed has used the structure.
#[derive(Clone, Copy, Debug, Default, PartialEq, PartialOrd)]
pub enum Stress {
    #[default]
    None,
    /// Past the limit: reported for an inspection, nothing breaks.
    Over,
    /// Permanent damage.
    Damage,
    /// The airframe fails.
    Failure,
}

/// The stress of load factor `n` (g) on a jet limited to `(max, min)` g, × `k` (a category III load rolling:
/// [`CAT3_ROLLING`]). A `weakened` structure (damaged already) fails at [`WEAK_ULTIMATE`].
pub fn g_stress(n: f64, (max, min): (f64, f64), k: f64, weakened: bool) -> Stress {
    let (r, inspect) = if n >= 0.0 { (n / (max * k), INSPECT.0) } else { (n / (min * k), INSPECT.1) };
    if r >= if weakened { WEAK_ULTIMATE } else { ULTIMATE } {
        Stress::Failure
    } else if r >= DAMAGE {
        Stress::Damage
    } else if r >= inspect {
        Stress::Over
    } else {
        Stress::None
    }
}

/// The stress of calibrated airspeed `cas_kt` at `mach` on a jet of limits `l`.
pub fn speed_stress(cas_kt: f64, mach: f64, l: &Limits) -> Stress {
    let r = (cas_kt / l.kcas).max(mach / l.mach);
    if r >= FLUTTER {
        Stress::Failure
    } else if r >= SPEED_DAMAGE {
        Stress::Damage
    } else if r > 1.0 {
        Stress::Over
    } else {
        Stress::None
    }
}

/// The gear down or moving past its speed limit.
pub fn gear_over(cas_kt: f64, mach: f64, l: &Limits) -> bool {
    cas_kt > l.gear.0 || mach > l.gear.1
}

/// The brakes' heat: the energy they have taken up, cooling over [`Brakes::COOL_S`].
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Brakes {
    pub joules: f64,
}

impl Brakes {
    /// The brakes' cooling time constant, s (inferred).
    pub const COOL_S: f64 = 900.0;
    /// Past the limit the braking falls to nothing at this × the limit (inferred).
    pub const GONE: f64 = 1.25;

    /// One step of `dt` s with the brakes taking up `watts`.
    pub fn step(&mut self, watts: f64, dt: f64) {
        self.joules = self.joules * (-dt / Self::COOL_S).exp() + watts.max(0.0) * dt;
    }

    /// The braking left, 1…0: full to `limit_j`, none at [`Brakes::GONE`] × it.
    pub fn left(&self, limit_j: f64) -> f64 {
        (1.0 - (self.joules / limit_j - 1.0) / (Self::GONE - 1.0)).clamp(0.0, 1.0)
    }
}

/// The brakes' energy limit, J: a stop from `l.brake_kt` at `ref_kg`.
pub fn brake_limit(l: &Limits, ref_kg: f64) -> f64 {
    let v = l.brake_kt * 0.514444;
    0.5 * ref_kg * v * v
}

/// The fuselage tanks' arms from the reference c.g., m, aft positive: the aft system's (A-1 and its reservoir) and the
/// forward system's (F-1, F-2 and theirs). Inferred: the F-16's tank arms are not public; these balance the full
/// tanks (2,810 lb aft, 1,890 lb forward, `fuel::FUSELAGE_LB`) at the reference c.g., so a jet with its fuel as the
/// feed keeps it stays near the reference, and the c.g. moves aft as the forward system empties ahead of the aft.
/// The wing and external tanks and the stores sit at the reference c.g. (inferred: their arms are not public).
pub const ARM_AFT: f64 = 2.0;
pub const ARM_FWD: f64 = -2.0 * 2_810.0 / 1_890.0;

/// The c.g., fraction of the chord: `xcg_ref` moved by the fuselage fuel's moment over the jet's `mass_kg`.
pub fn xcg(t: &Tanks, mass_kg: f64, cbar: f64, xcg_ref: f64) -> f64 {
    let fus = |s: usize| (t.lb[RSVR][s] + t.lb[FUSELAGE][s]) * LB;
    let full = |s: usize| (t.cap[RSVR][s] + t.cap[FUSELAGE][s]) * LB;
    // The fuel's moment against the full tanks' (a jet's full internal fuel at its reference c.g.).
    let m = (fus(AFT) - full(AFT)) * ARM_AFT + (fus(FWD) - full(FWD)) * ARM_FWD;
    xcg_ref + m / mass_kg.max(1.0) / cbar
}

/// The F-16's aft c.g. limit, fraction of the chord (inferred: the limits are in a supplement that is not public;
/// TP-1538 flies 0.35 as nominal and the F-16 is unstable in pitch behind about 0.35, so 0.38 is taken).
pub const XCG_AFT: f64 = 0.38;

/// A category III load's loss of directional stability, ΔCn: −[`CAT3_CNB`] per degree of α past `alpha_lim` (the
/// CAT III limiter's α at 1 g), per radian of sideslip β (inferred: heavy wing stores lower the F-16's directional
/// stability at high α, T.O. GR1F-16CJ-1 section VI; sized so that at about 25° α the jet's own Cnβ is gone and it
/// yaws off: the departure the CAT III limiter keeps it from).
pub fn cat3_cn(alpha_deg: f64, beta: f64, alpha_lim: f64) -> f64 {
    -CAT3_CNB * (alpha_deg - alpha_lim).max(0.0) * beta
}

/// The CAT III load's ΔCnβ per degree of α, per radian.
pub const CAT3_CNB: f64 = 0.1;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn g_margins() {
        let f16 = (9.0, -3.0);
        assert_eq!(g_stress(9.3, f16, 1.0, false), Stress::None);
        assert_eq!(g_stress(9.5, f16, 1.0, false), Stress::Over);
        assert_eq!(g_stress(-3.2, f16, 1.0, false), Stress::Over);
        assert_eq!(g_stress(10.4, f16, 1.0, false), Stress::Damage);
        assert_eq!(g_stress(13.5, f16, 1.0, false), Stress::Failure);
        assert_eq!(g_stress(-4.5, f16, 1.0, false), Stress::Failure);
        // Damaged: 1.3 × the limit breaks it.
        assert_eq!(g_stress(10.4, f16, 1.0, true), Stress::Damage);
        assert_eq!(g_stress(11.8, f16, 1.0, true), Stress::Failure);
        // A category III load rolling: 9 g damages.
        assert_eq!(g_stress(9.0, f16, CAT3_ROLLING, false), Stress::Damage);
    }

    #[test]
    fn speed_margins() {
        assert_eq!(speed_stress(790.0, 1.2, &F16), Stress::None);
        assert_eq!(speed_stress(810.0, 1.2, &F16), Stress::Over);
        assert_eq!(speed_stress(890.0, 1.2, &F16), Stress::Damage);
        assert_eq!(speed_stress(500.0, 2.4, &F16), Stress::Failure);
        assert_eq!(speed_stress(720.0, 1.2, &F35), Stress::Over);
    }

    #[test]
    fn gear_speed() {
        assert!(!gear_over(290.0, 0.5, &F16));
        assert!(gear_over(310.0, 0.5, &F16));
        assert!(gear_over(280.0, 0.7, &F16));
        assert!(gear_over(310.0, 0.5, &F15));
    }

    #[test]
    fn brakes_fade_and_cool() {
        let lim = brake_limit(&F16, 13_000.0);
        let mut b = Brakes::default();
        b.step(lim, 1.0);
        assert!((b.left(lim) - 1.0).abs() < 1e-9);
        b.step(0.2 * lim, 1.0);
        assert!(b.left(lim) < 0.3, "{}", b.left(lim));
        b.step(0.0, 3_600.0);
        assert_eq!(b.left(lim), 1.0);
    }

    #[test]
    fn the_cg_moves_aft_as_the_forward_tanks_empty() {
        let mut t = Tanks::new(5_800.0);
        let m = 11_000.0;
        assert!((xcg(&t, m, 3.45, 0.35) - 0.35).abs() < 1e-9);
        // The forward system's fuselage tanks empty, the aft full.
        t.lb[RSVR][FWD] = 0.0;
        t.lb[FUSELAGE][FWD] = 0.0;
        let x = xcg(&t, m, 3.45, 0.35);
        assert!(x > XCG_AFT, "{x}");
        // The aft emptied instead: forward.
        let mut u = Tanks::new(5_800.0);
        u.lb[RSVR][AFT] = 0.0;
        u.lb[FUSELAGE][AFT] = 0.0;
        assert!(xcg(&u, m, 3.45, 0.35) < 0.35);
    }

    #[test]
    fn cat3_destabilises_past_its_alpha() {
        assert_eq!(cat3_cn(15.0, 0.1, 16.0), 0.0);
        assert!(cat3_cn(25.0, 0.1, 16.0) < 0.0);
        assert!(cat3_cn(25.0, -0.1, 16.0) > 0.0);
    }
}
