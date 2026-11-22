//! Ours, Modern IAF's countermeasures (modern-iaf/docs/ai-plan.md K8, K9; docs/real-weapons.md §2.3, docs/ai.md
//! §15.6): the chance that a flare or a chaff bundle takes a missile's seeker, and a self-protection jammer's effect
//! on a radar's range (the burn-through). The 1998 game keeps its decoy rule and its jammer (docs/weapons.md §10).
//! World frame X east, Y north, Z up, metres.

use crate::radar::{REF_RCS, reach};
use crate::vec3::Vec3;

/// A flare's chance against an infrared seeker with no rejection (inferred; the 1998 rule's 0.33, 0.5 above 4 g).
pub const FLARE_P: f64 = 0.5;
/// A chaff bundle's chance against a radar seeker with no rejection (inferred; the 1998 rule's 0.1, 0.3 above 4 g,
/// raised: the original's chaff is a weaker decoy than its flares).
pub const CHAFF_P: f64 = 0.4;
/// A decoy works fully when the missile is this close in time (s): it burns 4 s (the decoy's life, docs/weapons.md
/// §10), so one released earlier has burnt out while the missile is still far (inferred).
pub const WINDOW_S: f64 = 6.0;
/// Above this load factor the jet's turn takes it out of the seeker's view of the decoy faster (the 1998 rule's 4 g
/// threshold); the chance times [`G_BONUS`].
pub const HIGH_G: f64 = 4.0;
pub const G_BONUS: f64 = 1.5;
/// A flare beside a lit afterburner: the plume outshines it (inferred; the 1998 rule: no chance at all).
pub const AB_FACTOR: f64 = 0.25;

/// The geometry of a missile and its target at the release.
#[derive(Clone, Copy, Debug)]
pub struct Shot {
    pub missile_pos: Vec3,
    pub missile_vel: Vec3,
    pub target_pos: Vec3,
    pub target_vel: Vec3,
}

impl Shot {
    /// The time the missile needs to reach the target at the present closure (s); None when it is not closing.
    pub fn time_to_go(&self) -> Option<f64> {
        let los = self.target_pos - self.missile_pos;
        let d = los.length();
        let closing = (self.missile_vel - self.target_vel).dot(los.try_normalize()?);
        (closing > 0.0).then(|| d / closing)
    }

    /// How much of the target's motion lies across the line of sight, 0 (straight along it) to 1 (on the beam); a
    /// still target counts as on the beam (no Doppler to tell it from the chaff).
    pub fn beam(&self) -> f64 {
        match (self.target_vel.try_normalize(), (self.target_pos - self.missile_pos).try_normalize()) {
            (Some(v), Some(l)) => 1.0 - v.dot(l).abs(),
            _ => 1.0,
        }
    }
}

/// The chance that one decoy takes a missile's seeker: `flare` (else chaff) against an infrared seeker (`ir`) or a
/// radar one, `reject` the seeker's decoy rejection (its record's `_decoyReject`, 0 none to 1 all), `ab` the target's
/// afterburner lit, `g` its load factor. A decoy of the other kind does nothing.
/// - A flare: its chance times (1 − reject) (newer seekers discriminate by spectrum and trajectory[^w-flare]).
/// - Chaff: a Doppler seeker tells the slowing chaff from a jet moving along its line of sight; on the beam the jet's
///   Doppler is the chaff's[^w-chaff]: its chance times (1 − reject · (1 − beam)).
/// - Timing: full inside [`WINDOW_S`] of the missile's arrival, else falling as WINDOW_S / time to go.
///
/// [^w-flare]: Wikipedia, "Flare (countermeasure)".
/// [^w-chaff]: Wikipedia, "Chaff (countermeasure)".
pub fn decoy_chance(flare: bool, ir: bool, reject: f64, shot: &Shot, ab: bool, g: f64) -> f64 {
    if flare != ir {
        return 0.0;
    }
    let Some(tgo) = shot.time_to_go() else { return 0.0 };
    let reject = reject.clamp(0.0, 1.0);
    let mut p = if flare {
        FLARE_P * (1.0 - reject) * if ab { AB_FACTOR } else { 1.0 }
    } else {
        CHAFF_P * (1.0 - reject * (1.0 - shot.beam()))
    };
    if tgo > WINDOW_S {
        p *= WINDOW_S / tgo;
    }
    if g > HIGH_G {
        p *= G_BONUS;
    }
    p.clamp(0.0, 1.0)
}

/// A self-protection jammer's burn-through: the range inside which a radar of `reach_m` against `REF_RCS` sees a
/// jet of `sigma` m² through its jamming, `jam` the jammer's share of the radar's reference reach (its definition's
/// `jammer.burn_through`). The echo falls with the range's fourth power and the jamming with its square, so the
/// burn-through goes with the square root of the cross-section (the radar equation; inferred).
pub fn burn_through(reach_m: f64, sigma: f64, jam: f64) -> f64 {
    reach_m * jam * (sigma / REF_RCS).max(0.0).sqrt()
}

/// A radar's range against a jet of `sigma` m², jamming with `jam` (0: not jamming): the nearer of its range
/// (`radar::reach`) and the burn-through.
pub fn jammed_reach(reach_m: f64, sigma: f64, jam: f64) -> f64 {
    let r = reach(reach_m, sigma);
    if jam > 0.0 { r.min(burn_through(reach_m, sigma, jam)) } else { r }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A missile 2 km (`d`) south of a jet flying `heading` (0 north: straight away) at 250 m/s, closing at 800 m/s.
    fn shot(d: f64, heading_deg: f64) -> Shot {
        let h = heading_deg.to_radians();
        Shot {
            missile_pos: Vec3::new(0.0, -d, 0.0),
            missile_vel: Vec3::new(0.0, 800.0, 0.0),
            target_pos: Vec3::ZERO,
            target_vel: Vec3::new(h.sin(), h.cos(), 0.0) * 250.0,
        }
    }

    #[test]
    fn the_wrong_kind_does_nothing() {
        assert_eq!(decoy_chance(true, false, 0.0, &shot(2000.0, 90.0), false, 1.0), 0.0);
        assert_eq!(decoy_chance(false, true, 0.0, &shot(2000.0, 90.0), false, 1.0), 0.0);
    }

    #[test]
    fn rejection_by_generation() {
        let s = shot(2000.0, 0.0);
        let p = |r| decoy_chance(true, true, r, &s, false, 1.0);
        // AIM-9M class (0.5) against an old seeker, an imaging seeker (0.85) least of all.
        assert!((p(0.0) - FLARE_P).abs() < 1e-9);
        assert!(p(0.0) > p(0.5) && p(0.5) > p(0.85) && p(0.85) > 0.0);
    }

    #[test]
    fn afterburner_and_g() {
        let s = shot(2000.0, 0.0);
        let base = decoy_chance(true, true, 0.5, &s, false, 1.0);
        assert!((decoy_chance(true, true, 0.5, &s, true, 1.0) - base * AB_FACTOR).abs() < 1e-9);
        assert!((decoy_chance(true, true, 0.5, &s, false, 6.0) - base * G_BONUS).abs() < 1e-9);
    }

    #[test]
    fn chaff_works_on_the_beam() {
        // A Doppler seeker (0.8): the jet on the beam is lost in the chaff, flying straight away it is not.
        let beam = decoy_chance(false, false, 0.8, &shot(2000.0, 90.0), false, 1.0);
        let away = decoy_chance(false, false, 0.8, &shot(2000.0, 0.0), false, 1.0);
        assert!((beam - CHAFF_P).abs() < 1e-6, "{beam}");
        assert!(away < 0.1 && away > 0.0, "{away}");
        // An old seeker is taken anywhere.
        assert!((decoy_chance(false, false, 0.0, &shot(2000.0, 0.0), false, 1.0) - CHAFF_P).abs() < 1e-9);
    }

    #[test]
    fn early_decoys_burn_out() {
        // 2 km at 550 m/s closing: inside the window. 20 km: 36 s out, the chance a sixth.
        let near = decoy_chance(true, true, 0.0, &shot(2000.0, 0.0), false, 1.0);
        let far = decoy_chance(true, true, 0.0, &shot(20_000.0, 0.0), false, 1.0);
        assert!((near - FLARE_P).abs() < 1e-9);
        assert!((far - FLARE_P * WINDOW_S / (20_000.0 / 550.0)).abs() < 1e-9);
        // An opening missile is not taken.
        let mut s = shot(2000.0, 0.0);
        s.missile_vel = Vec3::ZERO;
        assert_eq!(decoy_chance(true, true, 0.0, &s, false, 1.0), 0.0);
    }

    #[test]
    fn burn_through_scales_with_the_root_of_the_cross_section() {
        // Against the reference jet the burn-through is the jammer's share; a four times smaller one halves it.
        assert!((burn_through(100_000.0, REF_RCS, 0.3) - 30_000.0).abs() < 1e-6);
        assert!((burn_through(100_000.0, REF_RCS / 4.0, 0.3) - 15_000.0).abs() < 1e-6);
        // Not jamming: the radar's own range; jamming: the nearer.
        assert!((jammed_reach(300_000.0, 1.2, 0.0) - reach(300_000.0, 1.2)).abs() < 1e-6);
        let j = jammed_reach(300_000.0, 1.2, 0.3);
        assert!(j < reach(300_000.0, 1.2) && (j - burn_through(300_000.0, 1.2, 0.3)).abs() < 1e-6);
        // A strong jammer never makes the jet visible farther than without it.
        assert!((jammed_reach(20_000.0, 5.0, 2.0) - 20_000.0).abs() < 1e-6);
    }
}
