//! Landing gear on a flat runway: per strut a spring and damper along the world vertical, and tyre forces in the
//! runway plane (rolling friction, braking, side grip, nose-wheel steering). All forces go through the rigid
//! body's force closure (modern-iaf/docs/flight-model.md §9.8).

use super::body::Body;
use crate::Vec3;

/// One strut, its wheel's contact point given with the strut fully extended.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Strut {
    /// Contact point in body axes (x forward, y right, z down from the c.g.), m.
    pub pos: Vec3,
    /// Spring (N/m) and damper (N·s/m).
    pub k: f64,
    pub c: f64,
    /// Steered by the nose-wheel steering; braked.
    pub steer: bool,
    pub brake: bool,
}

/// Tyre and runway friction on a dry runway (modern-iaf/docs/flight-model.md §9.8). No public figure for these jets'
/// tyres: the braking from NASA TP-1051's antiskid tests on a DC-9 main-gear tyre (inferred for a fighter's).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tyres {
    /// Rolling friction on concrete (inferred).
    pub rolling: f64,
    /// The tyre's peak friction (braking and cornering together): TP-1051's maximum drag-force friction coefficient
    /// on the dry runway, about 0.55.
    pub peak: f64,
    /// Braking friction at full brake: the antiskid holds the tyre near its peak, averaging 0.91–0.93 of it on a dry
    /// runway (TP-1051's braking-behaviour index): 0.92 × 0.55.
    pub braking: f64,
    /// Side grip: the same tyre's peak (TP-1051), shared with braking through the friction circle. (Until
    /// 2026-11-16 the 1998 data's nose-wheel "grip 0.3 g", `data_set.rs`: full rudder at 66–100 kt then slid the
    /// jet 9–13° sideways with the nose wheel free.)
    pub side: f64,
}

pub const TYRES: Tyres = Tyres { rolling: 0.02, peak: 0.55, braking: 0.92 * 0.55, side: 0.55 };

/// Below this slip speed (m/s) friction grows linearly from 0 (a regularised Coulomb law, so a standing jet holds
/// still instead of chattering; inferred).
const SLIP: f64 = 0.03;

/// The slip angle (between the wheel's heading and its path) at which a rolling tyre's side force reaches its
/// friction limit; below it the force grows in proportion to the angle, the tyre's cornering stiffness (inferred: a
/// typical tyre's cornering curve; no public figure for these jets' tyres).
const CORNER_SLIP_DEG: f64 = 8.0;

/// An oleo strut's damping while it extends, × its damping while it compresses: the oil returns through a smaller
/// orifice, so the strut eases back out instead of bouncing (inferred: no public figure for these struts). At × 1
/// (until 2026-11-17) the jet pitched 0.4° nose up past level when a full stop under the brakes took the braking
/// force away, and rocked three times; at × 4 it eases back to level with no overshoot
/// (modern-iaf/docs/flight-model.md §9.8).
const REBOUND: f64 = 4.0;

/// The gear's three struts: nose, left main, right main; and the runway's tilt under the jet.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Gear {
    pub struts: [Strut; 3],
    /// The ground's slope under the jet (NED): how much its height `z` grows per metre north and per metre east, so
    /// each wheel meets the ground under itself (a sloping apron), not the height under the c.g.
    pub ground_slope: [f64; 2],
}

/// Where each braked tyre sticks to the runway (world, NED), if it does: a held brake pins the tyre to its spot
/// through a stiff tangential spring until the spring's pull exceeds the braking friction (a "bristle" model, so a
/// braked jet stands still against its idle thrust; inferred). Updated once per frame by [`Gear::update`].
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Anchors(pub [Option<Vec3>; 3]);

/// The anchor spring's stiffness and damping, × the strut's (1.5 cm of give under the strut's load; inferred).
const ANCHOR_K: f64 = 10.0;

/// What the pilot does to the wheels.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Wheels {
    /// Brake pedals 0…1 (both).
    pub brake: f64,
    /// Nose-wheel angle, deg, positive right.
    pub steer: f64,
    /// The nose-wheel steering is off: the nose wheel castors, rolling along its path with no side force.
    pub castor: bool,
}

impl Gear {
    /// A tricycle gear: the mains `track` apart, `wheelbase` behind the nose wheel, the c.g. `height` above the
    /// ground with the struts extended; `nose_share` of the weight on the nose wheel; springs that sink `sag` m
    /// under `weight` N and damp at ratio `zeta` (inferred values per jet in `jets.rs`).
    pub fn tricycle(wheelbase: f64, track: f64, height: f64, nose_share: f64, weight: f64, sag: f64) -> Gear {
        const ZETA: f64 = 0.6;
        let main_x = -nose_share * wheelbase;
        let strut = |x: f64, y: f64, share: f64, nose: bool| {
            let load = weight * share;
            let k = load / sag;
            let c = 2.0 * ZETA * (k * load / crate::units::G).sqrt();
            Strut { pos: Vec3::new(x, y, height), k, c, steer: nose, brake: !nose }
        };
        let main = (1.0 - nose_share) / 2.0;
        Gear {
            struts: [
                strut(main_x + wheelbase, 0.0, nose_share, true),
                strut(main_x, -track / 2.0, main, false),
                strut(main_x, track / 2.0, main, false),
            ],
            ground_slope: [0.0; 2],
        }
    }

    /// The wheels' height set from the drawn model: at weight `weight` (N), standing on level ground, every tyre's
    /// bottom `height` m below the c.g. (the model's wheels as drawn; the struts' static sag added to their extended
    /// length). The static loads share the weight by the wheels' places along the body.
    pub fn set_static_height(&mut self, height: f64, weight: f64) {
        let (nose_x, main_x) = (self.struts[0].pos.x, self.struts[1].pos.x);
        if nose_x - main_x <= 0.0 {
            return;
        }
        let nose_share = -main_x / (nose_x - main_x);
        for (n, s) in self.struts.iter_mut().enumerate() {
            let share = if n == 0 { nose_share } else { (1.0 - nose_share) / 2.0 };
            s.pos.z = height + weight * share / s.k;
        }
    }

    /// A strut's wheel on the runway at `ground_z` (under the c.g.; under the wheel by `ground_slope`): the compressed
    /// wheel's position in body axes (the strut gives along its body z axis, inferred), its world position and
    /// velocity, and its normal load (N); None in the air.
    fn contact(&self, s: &Strut, b: &Body, ground_z: f64) -> Option<(Vec3, Vec3, Vec3, f64)> {
        let w = b.pos + b.att.rotate(s.pos);
        let [north, east] = self.ground_slope;
        let depth = w.z - (ground_z + north * (w.x - b.pos.x) + east * (w.y - b.pos.y));
        if depth <= 0.0 {
            return None;
        }
        let r = s.pos - Vec3::new(0.0, 0.0, depth);
        let v = b.att.rotate(b.vel + b.omega.cross(r));
        // An extending strut damps harder (`REBOUND`).
        let c = if v.z < 0.0 { s.c * REBOUND } else { s.c };
        Some((r, b.pos + b.att.rotate(r), v, (s.k * depth + c * v.z).max(0.0)))
    }

    /// Each strut's normal load (N) on a runway at `ground_z`.
    pub fn loads(&self, b: &Body, ground_z: f64) -> [f64; 3] {
        self.struts.map(|s| self.contact(&s, b, ground_z).map_or(0.0, |c| c.3))
    }

    /// Body-axis force and moment from the runway at world height `ground_z` (NED, down positive), and each
    /// strut's normal load (N).
    pub fn forces(&self, b: &Body, ground_z: f64, w: &Wheels, t: &Tyres, anchors: &Anchors) -> (Vec3, Vec3, [f64; 3]) {
        let (mut f, mut m, mut loads) = (Vec3::ZERO, Vec3::ZERO, [0.0; 3]);
        for (n, s) in self.struts.iter().enumerate() {
            let Some((r, p, v, normal)) = self.contact(s, b, ground_z) else { continue };
            loads[n] = normal;
            // The wheel's rolling direction on the runway; none when the wheel points straight up or down (a nose-
            // or tail-first impact): then the runway pushes only.
            let steer = if s.steer { w.steer.to_radians() } else { 0.0 };
            let heading = b.att.rotate(Vec3::new(steer.cos(), steer.sin(), 0.0));
            let castor = s.steer && w.castor && v.x.hypot(v.y) > SLIP;
            let heading = if castor { v } else { heading };
            let tangential = match Vec3::new(heading.x, heading.y, 0.0).try_normalize() {
                None => Vec3::ZERO,
                Some(roll) => {
                    let side = Vec3::new(-roll.y, roll.x, 0.0);
                    let sat = |u: f64| (u / SLIP).clamp(-1.0, 1.0);
                    let mu_roll = t.rolling + if s.brake { t.braking * w.brake.clamp(0.0, 1.0) } else { 0.0 };
                    // Braking and cornering share the tyre's peak (a friction circle): a braked tyre grips less
                    // sideways (TP-1051: the side force falls during antiskid braking).
                    let mu_side = t.side.min((t.peak * t.peak - mu_roll * mu_roll).max(0.0).sqrt());
                    // The side force grows with the slip angle up to `CORNER_SLIP_DEG`, then holds at the friction
                    // limit; at walking pace and below, the regularised Coulomb law (a standing jet holds still).
                    let (v_roll, v_side) = (v.dot(roll), v.dot(side));
                    let corner = SLIP.max(v_roll.abs() * CORNER_SLIP_DEG.to_radians().tan());
                    let held =
                        anchors.0[n].map(|a| Self::anchor_force(s, p, v, a)).filter(|h| h.length() <= mu_roll * normal);
                    held.unwrap_or_else(|| {
                        roll * -(mu_roll * normal * sat(v_roll))
                            - side * (mu_side * normal * (v_side / corner).clamp(-1.0, 1.0))
                    })
                }
            };
            let fb = b.att.rotate_inv(Vec3::new(0.0, 0.0, -normal) + tangential);
            f += fb;
            m += r.cross(fb);
        }
        (f, m, loads)
    }

    /// The anchor spring's horizontal pull on a tyre at `p` moving at `v` (world).
    fn anchor_force(s: &Strut, p: Vec3, v: Vec3, a: Vec3) -> Vec3 {
        let d = Vec3::new(p.x - a.x, p.y - a.y, 0.0);
        let vh = Vec3::new(v.x, v.y, 0.0);
        d * -(ANCHOR_K * s.k) - vh * (ANCHOR_K.sqrt() * s.c)
    }

    /// After a frame: a braked tyre on the runway that has (nearly) stopped sticks where it is; one whose anchor
    /// pulls harder than its braking friction, or that leaves the runway or loses its brake, slides again.
    pub fn update(&self, b: &Body, ground_z: f64, w: &Wheels, t: &Tyres, anchors: &mut Anchors) {
        for (n, s) in self.struts.iter().enumerate() {
            let held = match self.contact(s, b, ground_z) {
                Some((_, p, v, normal)) if s.brake && w.brake > 0.0 && normal > 0.0 => {
                    let cap = (t.rolling + t.braking * w.brake.clamp(0.0, 1.0)) * normal;
                    match anchors.0[n] {
                        Some(a) => (Self::anchor_force(s, p, v, a).length() <= cap).then_some(a),
                        None => (Vec3::new(v.x, v.y, 0.0).length() < SLIP).then_some(p),
                    }
                }
                _ => None,
            };
            anchors.0[n] = held;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sixdof::Quat;

    #[test]
    fn nose_first_impact_pushes_back() {
        // Pointing straight down onto the runway, the wheels have no rolling direction: the runway still pushes.
        let g = Gear::tricycle(4.0, 2.4, 1.75, 0.12, 100_000.0, 0.15);
        let att = Quat::from_euler(0.0, -std::f64::consts::FRAC_PI_2, 0.0);
        // The nose wheel's contact point is 1.75 m along the body z axis: horizontal now; sink the c.g. so the
        // nose strut's wheel is 0.1 m into the runway.
        let nose = att.rotate(g.struts[0].pos);
        let b = Body::new(Vec3::new(0.0, 0.0, 0.1 - nose.z), Vec3::new(0.0, 0.0, 0.0), att);
        let (f, _, loads) = g.forces(&b, 0.0, &Wheels::default(), &TYRES, &Anchors::default());
        assert!(loads[0] > 0.0, "{loads:?}");
        assert!(b.att.rotate(f).z < 0.0, "pushed up: {f:?}");
    }

    #[test]
    fn the_drawn_wheels_set_the_static_height() {
        // At its weight, level with the c.g. 1.674 m over the ground (the Sufa model's wheels), the struts carry the
        // whole weight: the drawn tyres stand on the ground.
        let w = 110_000.0;
        let mut g = Gear::tricycle(4.0, 2.4, 1.75, 0.12, 90_000.0, 0.15);
        g.set_static_height(1.674, w);
        let b = Body::new(Vec3::new(0.0, 0.0, -1.674), Vec3::ZERO, Quat::from_euler(0.0, 0.0, 0.0));
        let total: f64 = g.loads(&b, 0.0).iter().sum();
        assert!((total - w).abs() < 1.0, "{total}");
        assert!(g.struts.iter().all(|s| s.pos.z > 1.674), "the struts extended beyond the drawn wheels");
    }

    #[test]
    fn each_wheel_meets_the_ground_under_itself() {
        // The ground rises 5 cm per metre to the east: the right main wheel (east, heading north) is deeper in it.
        let mut g = Gear::tricycle(4.0, 2.4, 1.75, 0.12, 100_000.0, 0.15);
        let b = Body::new(Vec3::new(0.0, 0.0, -1.65), Vec3::ZERO, Quat::from_euler(0.0, 0.0, 0.0));
        let level = g.loads(&b, 0.0);
        g.ground_slope = [0.0, -0.05];
        let tilted = g.loads(&b, 0.0);
        assert!((level[1] - level[2]).abs() < 1e-6);
        assert!(tilted[2] > level[2] && tilted[1] < level[1], "{tilted:?}");
    }
}
