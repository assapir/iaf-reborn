//! GPS / INS guided bombs (ours, the F-16I Sufa's JDAMs and GBU-39; docs/weapons.md §13): no seeker, the bomb flies
//! to a point fixed at its release. Not in the original game.
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

    /// The LAR (ours): a release from `pos` at `vel` reaches `aim`. The turn toward an aim off the track costs the
    /// arc flown at the load-factor limit.
    pub fn in_range(&self, pos: Vec3, vel: Vec3, aim: Vec3) -> bool {
        let d = aim - pos;
        let dh = (d.x * d.x + d.y * d.y).sqrt();
        let s = vel.length();
        let vh = (vel.x * vel.x + vel.y * vel.y).sqrt();
        let off =
            if dh > 0.0 && vh > 0.0 { ((d.x * vel.x + d.y * vel.y) / (dh * vh)).clamp(-1.0, 1.0).acos() } else { 0.0 };
        let turn = s * s / (self.max_g * G) * off;
        dh + turn <= LAR_MARGIN * self.reach(-d.z, s)
    }
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
}
