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
/// The TgenAPI terrain unit, horizontal and height (PlaneScalePR, docs/formats/ptt.md), metres.
const UNIT: f64 = 1.2411389;
/// `FUN_0045ed40` lifts both ends of the ray (0x601420 −1.5, subtracted from z).
const RAY_LIFT: f64 = 1.5;
/// The ray's ceiling (0x5fda90 4500 m): above it no terrain can be hit.
const RAY_CEILING: f64 = 4500.0;

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

/// TgenAPI slot 0x28 (`0x404ae0`): the terrain between two points, marched from the lower end toward the higher
/// one in steps of clearance / 8 + clamp(length / 300, 80, 300) terrain units; the hit is the first sample more
/// than 5 height units under the terrain (the sample itself, not the crossing). None once the ray is above 4500 m,
/// at the end, or without terrain.
pub fn terrain_ray(a: Vec3, b: Vec3, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Option<Vec3> {
    let (s, e) = if a.z > b.z { (b, a) } else { (a, b) };
    let n = s.distance(e) / UNIT;
    if n < 1.0 {
        return None;
    }
    let min_step = (n / 300.0).trunc().clamp(80.0, 300.0);
    let mut k = 0.0;
    while k < n {
        let p = s + (e - s) * (k / n);
        if p.z >= RAY_CEILING {
            return None;
        }
        let clear = (p.z / UNIT).floor() - (terrain(p)? / UNIT).floor();
        if clear < -5.0 {
            return Some(p);
        }
        k += (clear / 8.0).floor() + min_step;
    }
    None
}

/// TgenAPI slot 0x2c (`0x404e90`): the cockpit views' pick of the picture at a point's screen position, i.e. the
/// first terrain along the line of sight from `eye` toward `p`, or None (ours: marched in 1 % steps of the distance,
/// then bisected; the original reads the rendered picture, and a point off the screen finds nothing: UNCERTAIN, not
/// modelled).
pub fn sight_ray(eye: Vec3, p: Vec3, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Option<Vec3> {
    let under = |q: Vec3| terrain(q).is_some_and(|g| q.z <= g);
    let at = |f: f64| eye + (p - eye) * f;
    let mut a = 0.0;
    for k in 1..=101 {
        let b = k as f64 * 0.01;
        if under(at(b)) {
            let mut b = b;
            for _ in 0..20 {
                let m = 0.5 * (a + b);
                if under(at(m)) {
                    b = m;
                } else {
                    a = m;
                }
            }
            return Some(at(b));
        }
        a = b;
    }
    None
}

/// `FUN_0045e7f0` (the HUD's predicted impact) and its fall time: V = the jet's velocity, minus the store's bdb drag
/// (0x73a) as m/s along the nose, plus `extra` m/s along the nose (rockets: _limitVel); t to the terrain under the
/// jet, I = P + V·t − (0, 0, 4.903·t²); then once more for the terrain under I, whose height I takes. Then the
/// terrain ray P → I (`FUN_0045ed40`: in the cockpit views 1 / 5 / 0x12 / 0x16 `sight_ray`, else `terrain_ray`
/// with both ends 1.5 m up): a hit H is the impact (fall time to the terrain under H); a second ray P → the impact
/// solved for that height, if it hits too, moves it to that hit, on the terrain. A hill in front of the impact
/// takes the pipper.
pub fn predict_impact(
    p: Vec3,
    vel: Vec3,
    nose: Vec3,
    drag: f64,
    extra: f64,
    cockpit: bool,
    terrain: &dyn Fn(Vec3) -> Option<f64>,
) -> (Vec3, f64) {
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
    let lift = Vec3::UP * RAY_LIFT;
    let ray = |q: Vec3| if cockpit { sight_ray(p, q, terrain) } else { terrain_ray(p + lift, q + lift, terrain) };
    if let Some(h) = ray(i) {
        t = fall_time(v.z, p.z - height(terrain, h));
        if let Some(h2) = ray(at(t)) {
            return (Vec3::new(h2.x, h2.y, height(terrain, h2)), t);
        }
        return (h, t);
    }
    (i, t)
}

/// `FUN_00457c20`: the ripple line, frozen at the first release: `qty` points `spacing` m apart along the heading,
/// centred (index qty/2) on P, each on the terrain.
pub fn ripple_line(
    p: Vec3,
    qty: usize,
    spacing: f64,
    heading: f64,
    terrain: &dyn Fn(Vec3) -> Option<f64>,
) -> Vec<Vec3> {
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
    pub fn check(
        &mut self,
        now: f64,
        terrain: &dyn Fn(Vec3) -> Option<f64>,
        fix_burst: bool,
        open_h: f64,
    ) -> Option<(Vec3, f64)> {
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
        for cockpit in [false, true] {
            let (i, t) = predict_impact(
                Vec3::new(0.0, 0.0, 1000.0),
                Vec3::new(0.0, 200.0, 0.0),
                Vec3::NORTH,
                0.0,
                0.0,
                cockpit,
                FLAT,
            );
            assert!((t - (1000.0f64 / HALF_G).sqrt()).abs() < 1e-9);
            assert!((i.y - 200.0 * t).abs() < 1e-3 && i.z.abs() < 1e-3, "{cockpit} {i:?}");
        }
    }

    #[test]
    fn a_hill_in_front_takes_the_impact() {
        // A 600 m ridge 1500..1700 m north; the drag-free impact from 1000 m at 200 m/s is 2856 m north.
        let hill: &dyn Fn(Vec3) -> Option<f64> = &|q| Some(if (1500.0..1700.0).contains(&q.y) { 600.0 } else { 0.0 });
        for cockpit in [false, true] {
            let (i, _) = predict_impact(
                Vec3::new(0.0, 0.0, 1000.0),
                Vec3::new(0.0, 200.0, 0.0),
                Vec3::NORTH,
                0.0,
                0.0,
                cockpit,
                hill,
            );
            assert!((1500.0..1700.0).contains(&i.y), "{cockpit} {i:?}");
        }
        assert_eq!(terrain_ray(Vec3::new(0.0, 0.0, 1000.0), Vec3::new(0.0, 2856.0, 1.5), FLAT), None);
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
