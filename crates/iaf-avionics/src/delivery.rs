//! Modern IAF's F-16 air-to-ground release submodes besides CCIP (modern-iaf/docs/avionics-plan.md G21, G22, G25;
//! modern-iaf/docs/weapons.md §8): CCRP, DTOS, LADD and MAN, the bombs' fuzing and arming delay, and the LOW cue.
//! Every solution runs the store's own fall (`bombs::real_fall`, `bombs::real_impact`), the fall the released bomb then
//! flies, so a release at the solution lands on the target. Sources: the F-16 MLU M1 pilot's guide (16PR14341, 1998),
//! "Air-to-Ground Submodes" pp. 169–181 and "Manual Weapon Delivery" p. 191; the DCS F-16C guide (2026), "Unguided
//! bombs" pp. 618–632. World frame X east, Y north, Z up, metres, seconds.

use crate::bombs::{real_fall, real_impact};
use crate::vec3::Vec3;
use iaf_flight::units::G;

/// The A-G delivery submodes of the SMS's menu (MLU fig. 1-39).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Submode {
    /// The pipper on the impact point; the pilot releases (with the delayed CCIP).
    #[default]
    Ccip,
    /// Continuously computed release point: a designated target, the release automatic.
    Ccrp,
    /// Dive toss: the TD box designates in the dive, then CCRP's release.
    Dtos,
    /// Low-altitude drogue delivery: CCRP's computation with a 4 g pull-up to a 45° climb.
    Ladd,
    /// Manual: the depressible reticle, nothing computed.
    Man,
}

impl Submode {
    pub const ALL: [Submode; 5] = [Submode::Ccip, Submode::Ccrp, Submode::Dtos, Submode::Ladd, Submode::Man];

    /// The SMS and HUD mnemonic.
    pub fn name(self) -> &'static str {
        match self {
            Submode::Ccip => "CCIP",
            Submode::Ccrp => "CCRP",
            Submode::Dtos => "DTOS",
            Submode::Ladd => "LADD",
            Submode::Man => "MAN",
        }
    }

    /// The submode of a mnemonic (CCIP for any other).
    pub fn from_name(s: &str) -> Self {
        Self::ALL.into_iter().find(|m| m.name() == s).unwrap_or_default()
    }

    /// The release waits, WPN REL held, for the solution and goes by itself (CCRP, DTOS, LADD; MLU pp. 172–178).
    pub fn automatic(self) -> bool {
        matches!(self, Submode::Ccrp | Submode::Dtos | Submode::Ladd)
    }

    /// The missile step switch in A-G: CCIP → DTOS → CCRP → CCIP (MLU fig. 6-4 has STRF between, the gun's; DCS
    /// p. 620); LADD and MAN step to CCIP.
    pub fn step(self) -> Self {
        match self {
            Submode::Ccip => Submode::Dtos,
            Submode::Dtos => Submode::Ccrp,
            _ => Submode::Ccip,
        }
    }
}

/// The fuze arming option (SMS OSB 18; DCS p. 620): nose and tail, nose, tail.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Fuze {
    #[default]
    Nstl,
    Nose,
    Tail,
}

impl Fuze {
    pub const ALL: [Fuze; 3] = [Fuze::Nstl, Fuze::Nose, Fuze::Tail];

    pub fn name(self) -> &'static str {
        match self {
            Fuze::Nstl => "NSTL",
            Fuze::Nose => "NOSE",
            Fuze::Tail => "TAIL",
        }
    }

    pub fn from_name(s: &str) -> Self {
        Self::ALL.into_iter().find(|f| f.name() == s).unwrap_or_default()
    }

    /// OSB 18: NSTL → NOSE → TAIL → NSTL.
    pub fn next(self) -> Self {
        match self {
            Fuze::Nstl => Fuze::Nose,
            Fuze::Nose => Fuze::Tail,
            Fuze::Tail => Fuze::Nstl,
        }
    }
}

/// The arming delay a bomb starts with (s): the MLU's SMS page (fig. 1-38, "AD 4.80SEC").
pub const ARM_DELAY: f64 = 4.8;
/// The arming delays the SMS steps through (s; ours, inferred around the MLU's 4.80).
pub const ARM_DELAYS: [f64; 6] = [2.0, 3.0, 4.8, 6.0, 8.0, 10.0];

/// The next arming delay after `ad` (wrapping).
pub fn next_arm_delay(ad: f64) -> f64 {
    ARM_DELAYS.into_iter().find(|d| *d > ad + 1e-6).unwrap_or(ARM_DELAYS[0])
}

/// A bomb released at `released` has armed by `now`: its fuze needs the arming delay after the release; one that hits
/// sooner is a dud (DCS pp. 625, 629: "will not give the bomb time to arm and result in a dud").
pub fn armed(released: f64, now: f64, arm_delay: f64) -> bool {
    now - released >= arm_delay
}

/// LADD's loft: a 4 g pull-up to a 45° flight path angle (MLU p. 178).
pub const LOFT_G: f64 = 4.0;
pub const LOFT_DEG: f64 = 45.0;
/// LADD releases only in the loft's climb, above this flight path angle (ours, inferred: the maneuver's release is in
/// the 45° climb).
pub const LADD_MIN_CLIMB_DEG: f64 = 10.0;

/// The release computer's input this frame.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Shot {
    pub submode: Submode,
    /// The jet's position and velocity.
    pub p: Vec3,
    pub v: Vec3,
    /// The store's β (`bombs::real_beta`) and the air mass it falls through.
    pub beta: f64,
    pub wind: Vec3,
    /// The designated target (None: CCIP, MAN, DTOS before its designation).
    pub target: Option<Vec3>,
    /// The ground's height under the jet (m): the LOW cue's fall without a target.
    pub ground: f64,
    /// The selected arming delay (s).
    pub arm_delay: f64,
}

/// The solution.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Solution {
    /// Where a bomb released now meets the target's height (the automatic submodes with a target).
    pub impact: Option<Vec3>,
    /// The fall time of a bomb released now (to the target's height, else the ground under the jet).
    pub fall_s: f64,
    /// The target ahead of that impact along the ground track and across it, right + (m).
    pub along: f64,
    pub cross: f64,
    /// Seconds to the release point (negative once past; None: the impact point does not run toward the target).
    pub ttr: Option<f64>,
    /// Seconds to the loft's pull-up (CCRP, LADD): None once it is behind or the jet climbs.
    pub pull_up: Option<f64>,
    /// The automatic release goes now (WPN REL held): the impact has just reached the target.
    pub release: bool,
    /// LOW: a bomb released now hits before its fuze arms (dash-34 p. 1-173: LOW beside the marker).
    pub low: bool,
    /// The height a bomb released now falls during the arming delay (m): the lowest release height above the target.
    pub min_release_m: f64,
}

/// Where a store released at `p`, `v` meets flat ground at height `z`, and its fall time.
fn impact_on(p: Vec3, v: Vec3, beta: f64, wind: Vec3, z: f64) -> (Vec3, f64) {
    real_impact(p, v, beta, wind, &|_| Some(z))
}

/// The flight path angle of `v` (degrees, up +).
pub fn climb_deg(v: Vec3) -> f64 {
    v.z.atan2(v.x.hypot(v.y)).to_degrees()
}

/// The release computer (MLU pp. 172–178): the fall of a bomb released now, LOW, and with a target in CCRP, DTOS
/// and LADD the target's place against the impact, the time to release, the loft's pull-up and the release.
pub fn solve(s: &Shot) -> Solution {
    let z = s.target.map_or(s.ground, |t| t.z);
    let (impact, fall_s) = impact_on(s.p, s.v, s.beta, s.wind, z);
    let min_release_m = s.p.z - real_fall(s.p, s.v, s.beta, s.wind, s.arm_delay).0.z;
    let mut out = Solution { fall_s, low: fall_s < s.arm_delay, min_release_m, ..Solution::default() };
    let Some(t) = s.target.filter(|_| s.submode.automatic()) else {
        return out;
    };
    let u = match s.v.flat_dir() {
        d if d == Vec3::ZERO => Vec3::NORTH,
        d => d,
    };
    let d = t - impact;
    out.impact = Some(impact);
    out.along = d.dot(u);
    out.cross = d.dot(Vec3::new(u.y, -u.x, 0.0));
    // How fast the impact runs along the track: the impact of a release 1 s later on the same velocity.
    let rate = (impact_on(s.p + s.v, s.v, s.beta, s.wind, z).0 - impact).dot(u);
    out.ttr = (rate > 1.0).then_some(out.along / rate);
    let climb = climb_deg(s.v);
    if matches!(s.submode, Submode::Ccrp | Submode::Ladd) && climb < LADD_MIN_CLIMB_DEG {
        out.pull_up = pull_up_s(s, t, u, z);
    }
    let climbing = s.submode != Submode::Ladd || climb >= LADD_MIN_CLIMB_DEG;
    out.release = climbing && out.along <= 0.0 && out.ttr.is_some_and(|r| r > -1.0);
    out
}

/// Seconds of level flight to the loft's pull-up: pulled there at `LOFT_G` to `LOFT_DEG`, the bomb released at the
/// top of the arc lands on the target `t`. The arc's radius V² / (g·(n − 1)) (ours, inferred: the pull's start; the
/// release itself waits for the solution, so the arc only times the cue). None once the point is behind.
fn pull_up_s(s: &Shot, t: Vec3, u: Vec3, z: f64) -> Option<f64> {
    let speed = s.v.length();
    let gs = s.v.x.hypot(s.v.y);
    if gs < 1.0 {
        return None;
    }
    let r = speed * speed / (G * (LOFT_G - 1.0));
    let a = LOFT_DEG.to_radians();
    let top = s.p + u * (r * a.sin()) + Vec3::UP * (r * (1.0 - a.cos()));
    let (loft, _) = impact_on(top, (u * a.cos() + Vec3::UP * a.sin()) * speed, s.beta, s.wind, z);
    let ahead = (t - loft).dot(u);
    (ahead >= 0.0).then_some(ahead / gs)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bombs::{Bomb, real_beta};
    use iaf_flight::units::FT;

    const FLAT: &dyn Fn(Vec3) -> Option<f64> = &|_| Some(0.0);
    const DT: f64 = 1.0 / 60.0;
    /// The MK-82's blast radius in the sim's records (modern-iaf/data/db/weapons/mk-82.json `blast_m`): the bomb's
    /// spread a release must land within.
    const SPREAD: f64 = 50.0;

    /// The jet's path north in the vertical plane: flight path angle `gamma` (rad) at `speed`, pulling at `n` g from
    /// `pull_at` (s) up to `gamma_max`.
    struct Path {
        p: Vec3,
        gamma: f64,
        speed: f64,
        n: f64,
        pull_at: f64,
        gamma_max: f64,
    }

    impl Path {
        fn v(&self) -> Vec3 {
            Vec3::new(0.0, self.gamma.cos(), self.gamma.sin()) * self.speed
        }

        fn step(&mut self, t: f64) {
            if t >= self.pull_at && self.gamma < self.gamma_max {
                let rate = G * (self.n - self.gamma.cos()) / self.speed;
                self.gamma = (self.gamma + rate * DT).min(self.gamma_max);
            }
            self.p += self.v() * DT;
        }
    }

    /// The burst of a bomb released at `t` from `p`, `v` and the time it hits.
    fn release_at(t: f64, p: Vec3, v: Vec3, aim: Vec3, beta: f64) -> (Vec3, f64) {
        let mut b = Bomb::launch_real(t, p, v, aim, beta, Vec3::ZERO);
        (0..4000).find_map(|k| b.check(t + f64::from(k) * 0.5, FLAT, true, 0.0)).unwrap()
    }

    /// Flies `path` at 60 Hz, WPN REL held, until the solution releases; the burst of the bomb released then. LADD:
    /// the pull starts when the pull-up cue reaches the marker.
    fn fly(sub: Submode, target: Vec3, beta: f64, path: &mut Path) -> Vec3 {
        let mut t = 0.0;
        loop {
            let (p, v) = (path.p, path.v());
            let s = solve(&Shot {
                submode: sub,
                p,
                v,
                beta,
                wind: Vec3::ZERO,
                target: Some(target),
                ground: 0.0,
                arm_delay: ARM_DELAY,
            });
            if path.pull_at.is_infinite() && s.pull_up.is_some_and(|u| u <= 0.05) {
                path.pull_at = t;
            }
            if s.release {
                let (hit, at) = release_at(t, p, v, target, beta);
                assert!(armed(t, at, ARM_DELAY), "{sub:?}: armed by the impact");
                return hit;
            }
            assert!(t < 120.0 && p.z > 0.0, "{sub:?}: no release ({s:?})");
            path.step(t);
            t += DT;
        }
    }

    #[test]
    fn each_mode_lands_within_the_bombs_spread() {
        let beta = real_beta("MK-82", 241.0);
        let flat =
            |p: Vec3, gamma: f64, speed: f64| Path { p, gamma, speed, n: 1.0, pull_at: f64::INFINITY, gamma_max: 0.0 };
        // CCRP, level at 1,000 m and 230 m/s on a target 6 km ahead.
        let target = Vec3::new(0.0, 6000.0, 0.0);
        let hit = fly(Submode::Ccrp, target, beta, &mut flat(Vec3::new(0.0, 0.0, 1000.0), 0.0, 230.0));
        assert!(hit.distance(target) < SPREAD / 5.0, "CCRP {hit:?}");
        // DTOS: a 30° dive from 2,000 m at 250 m/s, the TD box (the flight path marker) designating its ground point,
        // then a 4 g pull-out 2 s later (the toss): the release comes in the pull.
        let (p0, g0) = (Vec3::new(0.0, 0.0, 2000.0), -30f64.to_radians());
        let mut dive = Path { p: p0, gamma: g0, speed: 250.0, n: 4.0, pull_at: 2.0, gamma_max: 20f64.to_radians() };
        let v0 = dive.v();
        let target = p0 + v0 * (p0.z / -v0.z);
        let hit = fly(Submode::Dtos, target, beta, &mut dive);
        assert!(hit.distance(target) < SPREAD * 0.3, "DTOS {hit:?} vs {target:?}");
        // LADD: the run-in 200 ft above the target at 550 KTAS (MLU p. 178), the 4 g pull-up at the cue, a 45° climb.
        let target = Vec3::new(0.0, 12000.0, 0.0);
        let mut run =
            Path { gamma_max: LOFT_DEG.to_radians(), n: LOFT_G, ..flat(Vec3::new(0.0, 0.0, 200.0 * FT), 0.0, 283.0) };
        let hit = fly(Submode::Ladd, target, beta, &mut run);
        assert!(run.pull_at.is_finite(), "the pull-up cue came");
        assert!(hit.distance(target) < SPREAD / 2.0, "LADD {hit:?}");
        // MAN: the reticle depressed to where the bomb falls; released with it on the target, the bomb lands there.
        let (p, v) = (Vec3::new(0.0, 0.0, 1500.0), Vec3::new(0.0, 250.0 * g0.cos(), 250.0 * g0.sin()));
        let sight = Vec3::new(0.0, (g0 + 3f64.to_radians()).cos(), (g0 + 3f64.to_radians()).sin());
        let (fall, _) = real_impact(p, v, beta, Vec3::ZERO, FLAT);
        let elev = |d: Vec3| d.z.atan2(d.x.hypot(d.y));
        let mr = (elev(sight) - elev(fall - p)) * 1000.0;
        let line = Vec3::new(0.0, (elev(sight) - mr / 1000.0).cos(), (elev(sight) - mr / 1000.0).sin());
        let target = p + line * (p.z / -line.z);
        let (hit, _) = release_at(0.0, p, v, target, beta);
        assert!(mr > 0.0 && hit.distance(target) < SPREAD / 5.0, "MAN {mr} mr: {hit:?} vs {target:?}");
    }

    #[test]
    fn a_release_at_150_ft_shows_low_and_is_a_dud() {
        let beta = real_beta("MK-82", 241.0);
        let shot = |h_ft: f64| Shot {
            submode: Submode::Ccip,
            p: Vec3::new(0.0, 0.0, h_ft * FT),
            v: Vec3::new(0.0, 240.0, 0.0),
            beta,
            wind: Vec3::ZERO,
            target: None,
            ground: 0.0,
            arm_delay: ARM_DELAY,
        };
        let low = solve(&shot(150.0));
        assert!(low.low && low.fall_s < ARM_DELAY, "{low:?}");
        // The lowest release height: about ½·g·t² of the 4.8 s delay (drag slows the fall a little).
        assert!((low.min_release_m - 0.5 * G * ARM_DELAY * ARM_DELAY).abs() < 10.0, "{}", low.min_release_m);
        let s = shot(150.0);
        let (aim, _) = real_impact(s.p, s.v, beta, Vec3::ZERO, FLAT);
        let (_, at) = release_at(0.0, s.p, s.v, aim, beta);
        assert!(!armed(0.0, at, ARM_DELAY), "hit {at} s after the release: a dud");
        // From 1,000 ft the fall outlasts the delay: no LOW, the bomb arms.
        let high = solve(&shot(1000.0));
        assert!(!high.low && high.fall_s > ARM_DELAY, "{high:?}");
    }

    #[test]
    fn submodes_fuzes_and_delays() {
        assert_eq!(Submode::ALL.map(Submode::name), ["CCIP", "CCRP", "DTOS", "LADD", "MAN"]);
        assert_eq!(Submode::from_name("LADD"), Submode::Ladd);
        assert_eq!(Submode::from_name("PRE"), Submode::Ccip);
        assert_eq!(Submode::Ccip.step().step().step(), Submode::Ccip, "CCIP → DTOS → CCRP → CCIP");
        assert_eq!(Submode::Ladd.step(), Submode::Ccip);
        assert!(Submode::Dtos.automatic() && !Submode::Man.automatic() && !Submode::Ccip.automatic());
        assert_eq!(Fuze::Nstl.next().next().next(), Fuze::Nstl);
        assert_eq!(Fuze::from_name("TAIL"), Fuze::Tail);
        assert_eq!(next_arm_delay(ARM_DELAY), 6.0);
        assert_eq!(next_arm_delay(10.0), 2.0, "wraps");
        assert!(armed(1.0, 5.8, ARM_DELAY) && !armed(1.0, 5.7, ARM_DELAY));
    }

    #[test]
    fn ccrp_counts_down_and_steers() {
        let beta = real_beta("MK-82", 241.0);
        let s = |y: f64, x: f64| {
            solve(&Shot {
                submode: Submode::Ccrp,
                p: Vec3::new(0.0, y, 1000.0),
                v: Vec3::new(0.0, 230.0, 0.0),
                beta,
                wind: Vec3::ZERO,
                target: Some(Vec3::new(x, 6000.0, 0.0)),
                ground: 0.0,
                arm_delay: ARM_DELAY,
            })
        };
        let (a, b) = (s(0.0, 0.0), s(230.0, 0.0));
        let (ta, tb) = (a.ttr.unwrap(), b.ttr.unwrap());
        assert!((ta - tb - 1.0).abs() < 0.01 && !a.release, "1 s of level flight is 1 s nearer: {ta} {tb}");
        assert!(s(0.0, 50.0).cross > 49.0, "a target right of the track");
        // Past the release point: no release any more.
        let past = s(230.0 * (ta + 2.0), 0.0);
        assert!(!past.release && past.along < 0.0);
        // MAN computes no release.
        let man = solve(&Shot { submode: Submode::Man, ..shot0(beta) });
        assert!(man.impact.is_none() && !man.release);
    }

    fn shot0(beta: f64) -> Shot {
        Shot {
            submode: Submode::Ccip,
            p: Vec3::new(0.0, 0.0, 1000.0),
            v: Vec3::new(0.0, 230.0, 0.0),
            beta,
            wind: Vec3::ZERO,
            target: Some(Vec3::new(0.0, 6000.0, 0.0)),
            ground: 0.0,
            arm_delay: ARM_DELAY,
        }
    }
}
