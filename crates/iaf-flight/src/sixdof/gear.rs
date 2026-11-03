//! Landing gear on a flat runway: per strut a spring and damper along the world vertical, and tyre forces in the
//! runway plane (rolling friction, braking, side grip, nose-wheel steering). All forces go through the rigid
//! body's force closure (iaf-2026/docs/flight-model.md §9.8).

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

/// Tyre and runway friction (inferred, open: no public figure for these jets).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tyres {
    /// Rolling friction on concrete.
    pub rolling: f64,
    /// Braking friction at full brake on a dry runway (the FM-0 data's 0.4).
    pub braking: f64,
    /// Side grip: the 1998 data's nose-wheel "grip 0.3 g" (`data_set.rs`), as a friction coefficient.
    pub side: f64,
}

pub const TYRES: Tyres = Tyres { rolling: 0.02, braking: 0.4, side: 0.3 };

/// Below this slip speed (m/s) friction grows linearly from 0 (a regularised Coulomb law, so a standing jet holds
/// still instead of chattering; inferred).
const SLIP: f64 = 0.03;

/// The gear's three struts: nose, left main, right main.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Gear {
    pub struts: [Strut; 3],
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
        }
    }

    /// A strut's wheel on the runway at `ground_z`: the compressed wheel's position in body axes (the strut gives
    /// along its body z axis, inferred), its world position and velocity, and its normal load (N); None in the air.
    fn contact(s: &Strut, b: &Body, ground_z: f64) -> Option<(Vec3, Vec3, Vec3, f64)> {
        let depth = (b.pos + b.att.rotate(s.pos)).z - ground_z;
        if depth <= 0.0 {
            return None;
        }
        let r = s.pos - Vec3::new(0.0, 0.0, depth);
        let v = b.att.rotate(b.vel + b.omega.cross(r));
        Some((r, b.pos + b.att.rotate(r), v, (s.k * depth + s.c * v.z).max(0.0)))
    }

    /// Each strut's normal load (N) on a runway at `ground_z`.
    pub fn loads(&self, b: &Body, ground_z: f64) -> [f64; 3] {
        self.struts.map(|s| Self::contact(&s, b, ground_z).map_or(0.0, |c| c.3))
    }

    /// Body-axis force and moment from the runway at world height `ground_z` (NED, down positive), and each
    /// strut's normal load (N).
    pub fn forces(&self, b: &Body, ground_z: f64, w: &Wheels, t: &Tyres, anchors: &Anchors) -> (Vec3, Vec3, [f64; 3]) {
        let (mut f, mut m, mut loads) = (Vec3::ZERO, Vec3::ZERO, [0.0; 3]);
        for (n, s) in self.struts.iter().enumerate() {
            let Some((r, p, v, normal)) = Self::contact(s, b, ground_z) else { continue };
            loads[n] = normal;
            // The wheel's rolling direction on the runway; none when the wheel points straight up or down (a nose-
            // or tail-first impact): then the runway pushes only.
            let steer = if s.steer { w.steer.to_radians() } else { 0.0 };
            let heading = b.att.rotate(Vec3::new(steer.cos(), steer.sin(), 0.0));
            let tangential = match Vec3::new(heading.x, heading.y, 0.0).try_normalize() {
                None => Vec3::ZERO,
                Some(roll) => {
                    let side = Vec3::new(-roll.y, roll.x, 0.0);
                    let sat = |u: f64| (u / SLIP).clamp(-1.0, 1.0);
                    let mu_roll = t.rolling + if s.brake { t.braking * w.brake.clamp(0.0, 1.0) } else { 0.0 };
                    let held =
                        anchors.0[n].map(|a| Self::anchor_force(s, p, v, a)).filter(|h| h.length() <= mu_roll * normal);
                    held.unwrap_or_else(|| {
                        roll * -(mu_roll * normal * sat(v.dot(roll))) - side * (t.side * normal * sat(v.dot(side)))
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
            let held = match Self::contact(s, b, ground_z) {
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
}
