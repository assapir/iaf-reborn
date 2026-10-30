//! GPS / INS guided bombs (ours, the JDAMs and the GBU-39; docs/weapons.md §13): no seeker, the bomb flies to the
//! coordinates handed to it at its release. Not in the original game.
//!
//! An energy model (inferred, docs/weapons.md §13.2): the bomb's specific energy e = g·z + ½·s² drains by g / LD
//! per metre flown over the ground (LD = the kit's glide ratio), its speed is what the energy leaves at its height,
//! at most the kit's dive speed. It flies straight at the aim while its speed stays above the kit's slowest; at the
//! slowest it glides at 1 : LD toward the aim and falls short. Its velocity turns toward the wanted direction at the
//! kit's load-factor limit. So the reach from height h above the aim at speed s is LD · (h + (s² − s_min²) / 2g),
//! whatever the path, and the launch acceptability region (LAR) follows from it.
//!
//! World frame X east, Y north, Z up, metres, seconds.

use crate::vec3::Vec3;

const G: f64 = 9.80665;
/// Integration step (s).
const STEP: f64 = 0.05;
/// The LAR keeps this share of the reach (inferred: a margin for the turn and the wind).
const LAR_MARGIN: f64 = 0.9;

/// A guidance kit (the record's values, docs/real-weapons.md §1.6).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Kit {
    /// Glide ratio: metres over the ground per metre of energy height.
    pub glide: f64,
    /// The slowest it flies (m/s).
    pub min_speed: f64,
    /// The fastest it dives (m/s).
    pub max_speed: f64,
    /// The load factor its fins turn it with (g).
    pub max_g: f64,
}

impl Kit {
    /// Ground distance the kit reaches from `h` metres above the aim at speed `s`.
    pub fn reach(&self, h: f64, s: f64) -> f64 {
        (self.glide * (h + (s * s - self.min_speed * self.min_speed) / (2.0 * G))).max(0.0)
    }

    /// A release from `pos` at `vel` reaches `aim` (the LAR, `lar`).
    pub fn in_range(&self, pos: Vec3, vel: Vec3, aim: Vec3) -> bool {
        self.lar(pos, vel, aim).in_range
    }

    /// The launch acceptability region (ours, docs/weapons.md §13.3) for a release from `pos` at `vel` at `aim`:
    /// - Rmax: the reach times the margin, less the arc of the turn toward an aim off the track at the load-factor
    ///   limit;
    /// - Rmin (inferred): the bomb turns down at the limit on a circle of radius s² / (n·g) below its path; an aim
    ///   inside that circle cannot be met, so the nearest ground distance is √(r² − (h − r)²), 0 from h ≥ 2r up;
    /// - the time to Rmax at the speed closing on the aim (none when not closing or already inside).
    pub fn lar(&self, pos: Vec3, vel: Vec3, aim: Vec3) -> Lar {
        let d = aim - pos;
        let range = (d.x * d.x + d.y * d.y).sqrt();
        let s = vel.length();
        let vh = (vel.x * vel.x + vel.y * vel.y).sqrt();
        let cos_off =
            if range > 0.0 && vh > 0.0 { ((d.x * vel.x + d.y * vel.y) / (range * vh)).clamp(-1.0, 1.0) } else { 1.0 };
        let r = s * s / (self.max_g * G);
        let rmax = LAR_MARGIN * self.reach(-d.z, s) - r * cos_off.acos();
        let rmin = (r * r - (-d.z - r).powi(2)).max(0.0).sqrt();
        let closing = vh * cos_off;
        let tmr = (range > rmax && closing > 1.0).then(|| (range - rmax) / closing);
        Lar { range, rmin, rmax, in_range: range >= rmin && range <= rmax, tmr }
    }
}

/// The launch acceptability region at one moment (metres over the ground, seconds).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Lar {
    /// The ground distance to the aim.
    pub range: f64,
    pub rmin: f64,
    pub rmax: f64,
    pub in_range: bool,
    /// The time to max range (TMR) while outside it and closing.
    pub tmr: Option<f64>,
}

/// How a GPS bomb takes its aim (docs/weapons.md §13.2): PRE, a pre-planned target's coordinates (from the briefing);
/// VIS, a point designated in flight (the targeting pod, the radar).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Mode {
    #[default]
    Pre,
    Vis,
}

/// The PRE targets a station steps through (docs/weapons.md §13.2): its own pre-planned target first, then the other
/// stations' and the route's steerpoints, each point once (the same within 1 m over the ground).
pub fn pre_targets(own: Option<Vec3>, others: &[Vec3], steerpoints: &[Vec3]) -> Vec<Vec3> {
    let mut out: Vec<Vec3> = Vec::new();
    for p in own.iter().chain(others).chain(steerpoints) {
        if !out.iter().any(|q| (q.x - p.x).hypot(q.y - p.y) < 1.0) {
            out.push(*p);
        }
    }
    out
}

/// Each bomb's PRE target on a station of `count` bombs (docs/weapons.md §13.2), in the stores' release order: the
/// bomb's own (`own[k]`, set per bomb on the briefing TSD, e.g. on a GBU-39 rack), else the station's (`station`, for
/// all its bombs).
pub fn rack_targets(station: Option<Vec3>, own: &[Option<Vec3>], count: usize) -> Vec<Option<Vec3>> {
    (0..count).map(|k| own.get(k).copied().flatten().or(station)).collect()
}

/// The PRE target picked by the step key's `index` (0: no step) among a station's `list` (`pre_targets`, its `own`
/// target first): the steps cycle through the list; a station without its own target starts on none (the bomb then
/// takes the CCIP aim) and steps through the others.
pub fn pre_pick(own: Option<Vec3>, list: &[Vec3], index: usize) -> Option<Vec3> {
    let skip = usize::from(own.is_none());
    let k = index % (list.len() + skip).max(1);
    if k < skip { None } else { list.get(k - skip).copied() }
}

/// The pre-planned target a station gets when the briefing set none: the route's target waypoint (action 5, the
/// TSD's red triangle), the first one; none without one.
pub fn default_target(actions: &[i64]) -> Option<usize> {
    actions.iter().position(|a| *a == 5)
}

/// One GPS bomb in flight.
#[derive(Clone, Debug)]
pub struct GpsBomb {
    pub kit: Kit,
    pub aim: Vec3,
    pub pos: Vec3,
    pub vel: Vec3,
    /// Specific energy (m²/s²).
    energy: f64,
    pub t: f64,
    pub ended: bool,
}

impl GpsBomb {
    pub fn launch(kit: Kit, now: f64, pos: Vec3, vel: Vec3, aim: Vec3) -> Self {
        let s = vel.length().max(kit.min_speed);
        GpsBomb { kit, aim, pos, vel, energy: G * pos.z + 0.5 * s * s, t: now, ended: false }
    }

    /// Flies to `now`; true when it meets the ground (`terrain` under a point; none = 0) or the aim's height: it
    /// bursts at `pos`, where its path crossed that height.
    pub fn advance(&mut self, now: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
        while !self.ended && self.t < now {
            let dt = STEP.min(now - self.t);
            let prev = self.pos;
            self.step(dt);
            self.t += dt;
            let floor = terrain(self.pos).unwrap_or(0.0).max(self.aim.z);
            if self.pos.z <= floor {
                // The burst where the last step crossed that height.
                let f =
                    if prev.z > self.pos.z { ((prev.z - floor) / (prev.z - self.pos.z)).clamp(0.0, 1.0) } else { 1.0 };
                self.pos = prev + (self.pos - prev) * f;
                self.ended = true;
            }
        }
        self.ended
    }

    fn step(&mut self, dt: f64) {
        let k = self.kit;
        let s = self.vel.length().max(1.0);
        let u = self.vel * (1.0 / s);
        let los = self.aim - self.pos;
        let flat = Vec3::new(los.x, los.y, 0.0).try_normalize().unwrap_or(Vec3::new(u.x, u.y, 0.0));
        let to_aim = los.try_normalize().unwrap_or(u);
        // At the slowest speed: the best glide toward the aim (or the aim itself when steeper).
        let glide = (flat - Vec3::UP * (1.0 / k.glide)).try_normalize().unwrap_or(to_aim);
        let want = if s <= k.min_speed * 1.001 && to_aim.z > glide.z { glide } else { to_aim };
        let max_turn = k.max_g * G / s * dt;
        let ang = u.dot(want).clamp(-1.0, 1.0).acos();
        let dir = if ang <= max_turn || ang < 1e-9 {
            want
        } else {
            let side = (want - u * u.dot(want)).try_normalize().unwrap_or(Vec3::UP);
            (u * max_turn.cos() + side * max_turn.sin()).try_normalize().unwrap_or(want)
        };
        self.pos += dir * (s * dt);
        let vh = (dir.x * dir.x + dir.y * dir.y).sqrt() * s;
        self.energy -= G / k.glide * vh * dt;
        let s2 = (2.0 * (self.energy - G * self.pos.z)).max(k.min_speed * k.min_speed);
        let speed = s2.sqrt().min(k.max_speed);
        self.energy = G * self.pos.z + 0.5 * speed * speed;
        self.vel = dir * speed;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The GBU-31's kit (docs/real-weapons.md §1.6).
    const JDAM: Kit = Kit { glide: 1.6, min_speed: 150.0, max_speed: 300.0, max_g: 3.0 };

    fn fly(kit: Kit, pos: Vec3, vel: Vec3, aim: Vec3) -> Vec3 {
        let mut b = GpsBomb::launch(kit, 0.0, pos, vel, aim);
        assert!(b.advance(600.0, &|_| Some(0.0)), "it lands");
        b.pos
    }

    #[test]
    fn hits_the_point_inside_the_lar_and_falls_short_outside() {
        let pos = Vec3::new(0.0, 0.0, 6000.0);
        let vel = Vec3::new(0.0, 250.0, 0.0);
        // 30° off the track, 9 km out.
        let aim = Vec3::new(4500.0, 7800.0, 0.0);
        assert!(JDAM.in_range(pos, vel, aim));
        let hit = fly(JDAM, pos, vel, aim);
        assert!(hit.distance(aim) < 3.0, "on the point: {hit:?}");
        let far = Vec3::new(0.0, 20_000.0, 0.0);
        assert!(!JDAM.in_range(pos, vel, far));
        let short = fly(JDAM, pos, vel, far);
        assert!(short.y < 17_000.0 && short.y > JDAM.reach(6000.0, 250.0) * 0.8, "short, near the reach: {short:?}");
    }

    #[test]
    fn high_release_reaches_the_published_range() {
        // 40,000 ft at Mach 0.9 (265 m/s): about the published 24 km (docs/real-weapons.md §1.6).
        let r = JDAM.reach(12_192.0, 265.0);
        assert!((r - 24_000.0).abs() < 1_000.0, "{r}");
    }

    #[test]
    fn lar_min_range_is_the_turn_circle() {
        // 3,000 m up at 250 m/s: r = 250² / 3g ≈ 2,124 m, Rmin = √(r² − (h − r)²) ≈ 1,936 m.
        let pos = Vec3::new(0.0, 0.0, 3000.0);
        let vel = Vec3::new(0.0, 250.0, 0.0);
        let at = |d: f64| Vec3::new(0.0, d, 0.0);
        let l = JDAM.lar(pos, vel, at(1500.0));
        assert!((l.rmin - 1936.0).abs() < 2.0 && !l.in_range, "{l:?}");
        assert!(fly(JDAM, pos, vel, at(1500.0)).distance(at(1500.0)) > 100.0, "inside Rmin it overflies");
        assert!(JDAM.lar(pos, vel, at(2000.0)).in_range);
        assert!(fly(JDAM, pos, vel, at(2000.0)).distance(at(2000.0)) < 3.0, "just past Rmin it hits");
        // From 2r up the bomb can dive onto a point below it.
        assert_eq!(JDAM.lar(Vec3::new(0.0, 0.0, 5000.0), vel, at(0.0)).rmin, 0.0);
    }

    #[test]
    fn time_to_max_range_counts_down_then_in_range() {
        let vel = Vec3::new(0.0, 250.0, 0.0);
        let aim = Vec3::new(0.0, 20_000.0, 0.0);
        let far = JDAM.lar(Vec3::new(0.0, 0.0, 6000.0), vel, aim);
        let tmr = far.tmr.expect("closing from outside");
        assert!(!far.in_range && ((far.range - far.rmax) / 250.0 - tmr).abs() < 1e-9, "{far:?}");
        // Flown on for that time (level, the reach unchanged): at Rmax, in range, no TMR.
        let near = JDAM.lar(Vec3::new(0.0, 250.0 * tmr + 1.0, 6000.0), vel, aim);
        assert!(near.in_range && near.tmr.is_none(), "{near:?}");
        // Flying away: no TMR.
        assert!(JDAM.lar(Vec3::new(0.0, 0.0, 6000.0), vel * -1.0, aim).tmr.is_none());
    }

    #[test]
    fn pre_targets_own_first_each_once() {
        let a = Vec3::new(1000.0, 0.0, 0.0);
        let b = Vec3::new(0.0, 5000.0, 0.0);
        let wp = [Vec3::new(0.0, 0.0, 0.0), b + Vec3::new(0.5, 0.0, 30.0)];
        assert_eq!(pre_targets(Some(b), &[a, b], &wp), vec![b, a, wp[0]]);
        assert_eq!(pre_targets(None, &[], &wp[..1]), vec![wp[0]]);
        // Stepping: own, then the others, round again; without an own target: none first.
        let l = pre_targets(Some(b), &[a, b], &wp);
        let picks: Vec<_> = (0..4).map(|k| pre_pick(Some(b), &l, k)).collect();
        assert_eq!(picks, vec![Some(b), Some(a), Some(wp[0]), Some(b)]);
        let l = pre_targets(None, &[a], &[]);
        assert_eq!((0..3).map(|k| pre_pick(None, &l, k)).collect::<Vec<_>>(), vec![None, Some(a), None]);
        assert_eq!(pre_pick(None, &[], 5), None);
        assert_eq!(default_target(&[0, 0, 5, 0, 5]), Some(2));
        assert_eq!(default_target(&[0, 1]), None);
    }

    #[test]
    fn rack_bombs_own_targets_and_stepping() {
        let a = Vec3::new(1000.0, 0.0, 0.0);
        let b = Vec3::new(0.0, 5000.0, 0.0);
        let wp = [Vec3::new(0.0, 0.0, 0.0)];
        // Four GBU-39s on one station: bombs 1-2 on the station's A, 3-4 on their own B.
        let t = rack_targets(Some(a), &[None, None, Some(b), Some(b)], 4);
        assert_eq!(t, vec![Some(a), Some(a), Some(b), Some(b)]);
        // A bomb's own without a station target; the rest none; a shorter own list covers the first bombs only.
        assert_eq!(rack_targets(None, &[Some(b)], 3), vec![Some(b), None, None]);
        // Stepping from bomb 3: its own B, then A, then the steerpoint, round again; step 0 is each bomb's own.
        let others: Vec<Vec3> = t.iter().flatten().copied().collect();
        let l = pre_targets(t[2], &others, &wp);
        assert_eq!(l, vec![b, a, wp[0]]);
        assert_eq!(
            (0..4).map(|k| pre_pick(t[2], &l, k)).collect::<Vec<_>>(),
            vec![Some(b), Some(a), Some(wp[0]), Some(b)]
        );
        let l0 = pre_targets(t[0], &others, &wp);
        assert_eq!(pre_pick(t[0], &l0, 0), Some(a));
        assert_eq!(pre_pick(t[0], &l0, 1), Some(b));
    }
}
