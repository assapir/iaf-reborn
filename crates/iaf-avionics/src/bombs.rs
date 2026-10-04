//! Bombs (docs/weapons.md §9): the HUD impact prediction (`FUN_0045e7f0`), the ripple line (`FUN_00457c20`) and the
//! falling store, the original's ballistic class 0x16 (solver `FUN_005611b0`, motion `FUN_00468470`, impact check
//! `FUN_00561750`). World frame X east, Y north, Z up, metres, sim seconds.

use crate::vec3::Vec3;

/// ½g and g of the impact solvers (0x601414 4.903, 0x60cde0 −19.612, 0x60cdf0 1/9.806).
const HALF_G: f64 = 4.903;
const G: f64 = 9.806;
/// The motion's vertical acceleration (0xc11ce560 = −9.806).
const ACC_Z: f64 = -9.806;
/// Impact check period (0x60ce20 −0.5), "at the aim" distance (0x60cddc 2.0) and the ground band (0x60ce18 −1.0: at
/// or below terrain + 1).
const CHECK_PERIOD: f64 = 0.5;
const HIT_AIM: f64 = 2.0;
const GROUND_BAND: f64 = 1.0;
/// The terrain height where none is loaded (0x60ce14).
const NO_GROUND: f64 = 0.1;

fn height(terrain: &dyn Fn(Vec3) -> Option<f64>, p: Vec3) -> f64 {
    terrain(p).unwrap_or(NO_GROUND)
}

/// `FUN_0045e330`: the later root of h + vz·t − 4.903·t² = 0 (0 when there is none).
pub fn fall_time(vz: f64, h: f64) -> f64 {
    let d = vz * vz + 4.0 * HALF_G * h;
    if d < 0.0 {
        return 0.0;
    }
    let r = d.sqrt();
    ((vz + r) / (2.0 * HALF_G)).max((vz - r) / (2.0 * HALF_G))
}

/// `FUN_0045e7f0` (the HUD's predicted impact) and its fall time: V = the jet's velocity, minus the store's bdb drag
/// (0x73a) as m/s along the nose, plus `extra` m/s along the nose (rockets: _limitVel); t to the terrain under the
/// jet, I = P + V·t − (0, 0, 4.903·t²); then once more for the terrain under I, whose height I takes.
pub fn predict_impact(p: Vec3, vel: Vec3, nose: Vec3, drag: f64, extra: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> (Vec3, f64) {
    let mut v = vel;
    if extra.abs() > 0.0 {
        v += nose * extra;
    }
    if drag > 0.0 {
        v = v - nose * drag;
    }
    let at = |t: f64| p + v * t - Vec3::UP * (HALF_G * t * t);
    let mut t = fall_time(v.z, p.z - height(terrain, p));
    let mut i = at(t);
    let gi = height(terrain, i);
    if gi < i.z {
        t = fall_time(v.z, p.z - gi);
        i = at(t);
        i.z = i.z.min(height(terrain, i));
    }
    (i, t)
}

/// `FUN_00457c20`: the ripple line, frozen at the first release: `qty` points `spacing` m apart along the heading,
/// centred (index qty/2) on P, each on the terrain.
pub fn ripple_line(p: Vec3, qty: usize, spacing: f64, heading: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Vec<Vec3> {
    let d = Vec3::new(heading.sin(), heading.cos(), 0.0);
    let start = p - d * ((qty / 2) as f64 * spacing);
    (0..qty)
        .map(|k| {
            let a = start + d * (k as f64 * spacing);
            Vec3::new(a.x, a.y, height(terrain, a))
        })
        .collect()
}

/// A falling store.
#[derive(Clone, Debug, PartialEq)]
pub struct Bomb {
    pub t0: f64,
    pub p0: Vec3,
    pub v0: Vec3,
    pub aim: Vec3,
    pub acc: Vec3,
    /// The solver's impact time.
    pub end: f64,
    /// The next impact check.
    pub next_check: f64,
    /// 510: the cluster has opened (visual).
    pub opened: bool,
    pub done: bool,
}

impl Bomb {
    /// The ballistic motion (the solver `FUN_005611b0` at launch): the horizontal velocity is turned toward the aim
    /// (speed kept), the fall time to the aim's height fixes the along-track acceleration that lands it on the aim,
    /// clamped to ±`clamp_acc` (the player's bombs in single player: _debugParam016 15 m/s²; 0 = none).
    pub fn launch(now: f64, p: Vec3, v: Vec3, aim: Vec3, clamp_acc: f64) -> Self {
        let flat = Vec3::new(aim.x - p.x, aim.y - p.y, 0.0);
        let dist = flat.length();
        let vh = v.x.hypot(v.y);
        let u = flat.try_normalize().unwrap_or(Vec3::ZERO);
        let mut end = now;
        let mut a = 0.0;
        let d = v.z * v.z + 4.0 * HALF_G * (p.z - aim.z);
        if d >= 0.0 {
            let t = (d.sqrt() + v.z) / G;
            end = now + t;
            if t > 0.0 {
                a = 2.0 * (dist - vh * t) / (t * t);
            }
        }
        if clamp_acc > 0.0 {
            a = a.clamp(-clamp_acc, clamp_acc);
        }
        Bomb {
            t0: now,
            p0: p,
            v0: Vec3::new(u.x * vh, u.y * vh, v.z),
            aim,
            acc: Vec3::new(u.x * a, u.y * a, ACC_Z),
            end,
            next_check: now,
            opened: false,
            done: false,
        }
    }

    /// `FUN_00468470` / `FUN_004684d0`: p0 + v0·dt + ½·acc·dt² (v1.1: no cap at the impact time).
    pub fn position(&self, now: f64) -> Vec3 {
        let dt = (now - self.t0).max(0.0);
        self.p0 + self.v0 * dt + self.acc * (0.5 * dt * dt)
    }

    pub fn velocity(&self, now: f64) -> Vec3 {
        self.v0 + self.acc * (now - self.t0).max(0.0)
    }

    /// The impact checks of `FUN_00561750` up to `now` (the first at launch, then every 0.5 s): the bomb ends within
    /// 2 m of its aim or at / below terrain + 1, bursting at the check point (quirk: up to ~0.5·|vz| under the
    /// ground). `fix_burst` (Physics "Bombs burst at the ground", ours): the burst moves up to where the last step
    /// crossed the terrain. `open_h` > 0 (510): the cluster opens that high above the terrain. The burst point and
    /// time.
    pub fn check(&mut self, now: f64, terrain: &dyn Fn(Vec3) -> Option<f64>, fix_burst: bool, open_h: f64) -> Option<(Vec3, f64)> {
        while !self.done && self.next_check <= now {
            let t = self.next_check;
            self.next_check = t + CHECK_PERIOD;
            let mut p = self.position(t);
            let g = height(terrain, p);
            if open_h > 0.0 && p.z <= g + open_h {
                self.opened = true;
            }
            if p.distance(self.aim) < HIT_AIM || p.z <= g + GROUND_BAND {
                self.done = true;
                if fix_burst && p.z < g {
                    p = self.ground_crossing(t - CHECK_PERIOD, t, terrain);
                }
                return Some((p, t));
            }
        }
        None
    }

    /// Bisection on the last check step for the point where the bomb meets the terrain (ours).
    fn ground_crossing(&self, t0: f64, t1: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Vec3 {
        let (mut lo, mut hi) = (t0.max(self.t0), t1);
        for _ in 0..20 {
            let m = 0.5 * (lo + hi);
            let p = self.position(m);
            if p.z <= height(terrain, p) {
                hi = m;
            } else {
                lo = m;
            }
        }
        let q = self.position(hi);
        Vec3::new(q.x, q.y, q.z.max(height(terrain, q)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FLAT: &dyn Fn(Vec3) -> Option<f64> = &|_| Some(0.0);

    #[test]
    fn level_release_impact() {
        // 1000 m, 200 m/s north: t = √(1000 / 4.903).
        let (i, t) = predict_impact(Vec3::new(0.0, 0.0, 1000.0), Vec3::new(0.0, 200.0, 0.0), Vec3::NORTH, 0.0, 0.0, FLAT);
        assert!((t - (1000.0f64 / HALF_G).sqrt()).abs() < 1e-9);
        assert!((i.y - 200.0 * t).abs() < 1e-6 && i.z.abs() < 1e-6);
    }

    #[test]
    fn the_bomb_lands_on_its_aim() {
        let aim = Vec3::new(0.0, 3000.0, 0.0);
        let mut b = Bomb::launch(0.0, Vec3::new(0.0, 0.0, 1000.0), Vec3::new(0.0, 200.0, 0.0), aim, 0.0);
        assert!(b.position(b.end).distance(aim) < 1e-6);
        let (p, _) = (0..100).find_map(|k| b.check(k as f64 * 0.5, FLAT, true, 0.0)).unwrap();
        assert!(p.distance(aim) < 60.0, "{p:?}");
    }

    #[test]
    fn ripple_centred_on_the_point() {
        let l = ripple_line(Vec3::new(0.0, 1000.0, 50.0), 4, 10.0, 0.0, FLAT);
        assert_eq!(l.len(), 4);
        assert_eq!(l[2], Vec3::new(0.0, 1000.0, 0.0));
        assert_eq!(l[0], Vec3::new(0.0, 980.0, 0.0));
    }
}
