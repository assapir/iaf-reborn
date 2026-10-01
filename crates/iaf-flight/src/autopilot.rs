//! The AI's autopilot: the original's control loops (`atp.ControlLoop.h`, docs/ai.md §7–§8) flying an
//! [`Aircraft`] through its normal inputs (stick, throttle, rudder, gear, flaps, brakes). Modes as the FM's
//! `setMode` (`5a8410`): 7 navigate the route, 8 go home and land, 9 take-off sequence, 1 / 3 close /
//! tactical formation on the formation leader, 10 hold, 0xb straight. The combat modes are the combat job.
//!
//! Frame: ENU metres (x east, y north, z up) of the aircraft; headings clockwise from north.

use crate::airbase::{Airbase, TaxiPt};
use crate::aircraft::{Aircraft, ApView, Controls, V3};
use iaf_formats::ini::Section;
use std::f32::consts::PI;

/// `[Autopilot]` of bd.ibx (loader around `5c726d`); defaults are the exe's.
#[derive(Debug, Clone, Copy)]
pub struct Config {
    pub roll_k: f32,
    pub roll_beta: f32,
    pub pitch_k: f32,
    pub pitch_beta: f32,
    pub speed_k: f32,
    pub speed_beta: f32,
    pub change_alt_k: f32,
    pub change_alt_beta: f32,
    pub change_head_k: f32,
    pub change_head_beta: f32,
    pub look_at_k: f32,
    pub look_at_beta: f32,
    pub watch_ground_dt: f32,
    pub change_roll_cone: f32,
    pub dog_chase_roll_k: f32,
    pub dog_chase_roll_beta: f32,
    pub no_change_roll_cone: f32,
    pub slow_cone_roll_k: f32,
    pub nose_on_target: f32,
    pub h_above_ground: f32,
    /// AllowedErrPt2..6 (index 0 = Pt2).
    pub allowed_err: [f32; 5],
    pub fpm_pitch_low: f32,
    pub speed_taxi_k: f32,
    pub speed_taxi_beta: f32,
}

impl Default for Config {
    fn default() -> Self {
        Self::from_section(&Section::default())
    }
}

impl Config {
    /// The `[Autopilot]` section of the install's bd.ibx (v1.1: bdgen.dat), else the defaults.
    pub fn load(install: &std::path::Path) -> Self {
        crate::read_md(install, "bd.ibx")
            .ok()
            .and_then(|b| {
                iaf_formats::ini::Ini::parse(&b)
                    .section("Autopilot")
                    .map(Config::from_section)
            })
            .unwrap_or_default()
    }

    pub fn from_section(s: &Section) -> Self {
        let f = |k: &str, d: f32| s.f32(k).unwrap_or(d);
        let deg = |k: &str, d: f32| f(k, d).to_radians();
        let speed_k = f("SpeedK", 6.0);
        let speed_beta = f("SpeedBeta", 0.5);
        Config {
            roll_k: f("RollK", 4.0),
            roll_beta: f("RollBeta", 0.02),
            pitch_k: f("PitchK", 16.0),
            pitch_beta: f("PitchBeta", 0.75),
            speed_k,
            speed_beta,
            change_alt_k: f("ChangeAltK", 6.0),
            change_alt_beta: f("ChangeAltBeta", 0.005),
            change_head_k: f("ChangeHeadK", 3.0),
            change_head_beta: f("ChangeHeadBeta", 1.0),
            look_at_k: f("LookAtK", 16.0),
            look_at_beta: f("LookAtBeta", 0.75),
            watch_ground_dt: f("WatchGroundDeltaTime", 4.0),
            change_roll_cone: deg("ChangeRollCone", 15.0),
            dog_chase_roll_k: f("DogChaseRollK", 8.0),
            // The loader reads the misspelt key "DogChasecRollBeta" (0x67bbe0): the file's value is never used.
            dog_chase_roll_beta: f("DogChasecRollBeta", 0.02),
            no_change_roll_cone: deg("NoChangeRollCone", 0.7),
            slow_cone_roll_k: deg("SlowConeRollK", 90.0),
            nose_on_target: deg("NoseOnTargetAng", 7.0),
            h_above_ground: f("hAboveGround", 200.0),
            allowed_err: [
                f("AllowedErrPt2", 1500.0),
                f("AllowedErrPt3", 1500.0),
                f("AllowedErrPt4", 1000.0),
                f("AllowedErrPt5", 200.0),
                f("AllowedErrPt6", 10.0),
            ],
            fpm_pitch_low: deg("FpmPitchReqAtLowVels", -5.0),
            speed_taxi_k: f("SpeedTaxiK", speed_k),
            speed_taxi_beta: f("SpeedTaxiBeta", speed_beta),
        }
    }
}

/// A route waypoint (runtime record, docs/ai.md §7.2): position, planned arrival time (sim s, 0 = none),
/// action (2 take-off, 3 navigate, 7 land, 8 hold).
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Waypoint {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub t: f64,
    pub action: i32,
}

/// The formation leader (member 0, `FUN_00587450`) as the formation, taxi and take-off loops see it.
#[derive(Debug, Clone, Copy)]
pub struct Leader {
    pub pos: V3,
    pub vel: V3,
    /// Pitch, roll, heading (rad).
    pub att: [f32; 3],
    /// Alive and controlled (`!free` in the taxi loops).
    pub active: bool,
}

// Constants (docs/ai.md §7–§8).
const V_MIN_NAV: f32 = 180.0; // 0x6134f0
const V_MAX_NAV: f32 = 300.0; // 0x6134f4
const V_NO_ETA: f32 = 275.0;
const C130: u32 = 225;
const PASS_R: f64 = 1852.0;

/// Terrain height (m) at a world point (x, y), supplied by the host.
pub type Ground<'a> = &'a dyn Fn(f64, f64) -> f32;

/// The commands one loop tick posted (applied to the aircraft by [`Autopilot::step`] and returned, so the
/// player's host can mirror them on its levers like the original's controller `44a240` does).
#[derive(Debug, Clone, Copy, Default)]
pub struct Out {
    /// (pitch law output a, roll x); the stick's pull is −a.
    pub stick: Option<(f32, f32)>,
    pub thr: Option<f32>,
    pub rudder: Option<f32>,
    pub gear: Option<bool>,
    pub flaps: Option<bool>,
    pub brakes: Option<bool>,
    pub pivot: Option<Option<f32>>,
    pub replace: Option<(f64, f64, f32)>,
    pub engine_off: bool,
    /// The player's landing stopped (StopPlaneCL in FM mode 0, @5d4b40): it presses the autopilot key
    /// (GEV 0x10, forced), which turns the autopilot off from NAV.
    pub ap_key: bool,
}

fn wrap(a: f32) -> f32 {
    let mut a = a % (2.0 * PI);
    if a > PI {
        a -= 2.0 * PI;
    } else if a <= -PI {
        a += 2.0 * PI;
    }
    a
}

fn dist2(a: V3, x: f64, y: f64) -> f64 {
    (a[0] - x).hypot(a[1] - y)
}

fn sign(v: f32) -> i32 {
    if v > 0.0 {
        1
    } else if v < 0.0 {
        -1
    } else {
        0
    }
}

/// `5d70a0` PassWaypoint: passed once the 2-D distance was ≤ R and then grows.
#[derive(Debug, Clone, Copy)]
struct Pass {
    r: f64,
    min: f64,
    armed: bool,
}

impl Pass {
    fn new(r: f64) -> Self {
        Pass {
            r,
            min: -1.0,
            armed: false,
        }
    }
    fn test(&mut self, pos: V3, x: f64, y: f64) -> bool {
        let d = dist2(pos, x, y);
        let ret = self.armed && d > self.min;
        if d <= self.r {
            self.min = d;
            self.armed = true;
        }
        ret
    }
}

/// The laws of §8.0 on one FM view.
struct Laws<'a> {
    c: &'a Config,
    v: &'a ApView,
    mode: u8,
    watch: bool,
    ground: Ground<'a>,
    out: Out,
    period: Option<f64>,
}

impl<'a> Laws<'a> {
    /// `5aaa90(V, g)`: the stick (y convention, − = pull) that commands `g`.
    fn inv_g(&self, g: f32) -> f32 {
        let [cv, a, b] = self.v.stick_centre;
        let c = if self.v.speed < cv {
            a * self.v.speed + b
        } else {
            1.0
        };
        if g > c {
            (-(g - c) / (self.v.max_g - c)).max(-1.0)
        } else {
            ((g - c) / (self.v.min_g - c)).min(1.0)
        }
    }

    /// Roll law `5c9bc0`.
    fn roll(&self, target: f32) -> f32 {
        let rmax = self.v.max_roll_rate;
        let r = self.v.rates[1];
        let d = if r.abs() <= PI {
            r * rmax
        } else {
            0.5 * rmax * r
        };
        (wrap(target - self.v.att.roll) / PI * self.c.roll_k / rmax - self.c.roll_beta * d)
            .clamp(-1.0, 1.0)
    }

    /// The g → stick map of the pitch laws: c in ±1 → g (MaxG / MinG) → stick.
    fn g_stick(&self, c: f32) -> f32 {
        let g = if -c > 0.0 {
            (self.v.max_g - 1.0) * -c + 1.0
        } else {
            (self.v.min_g - 1.0) * c + 1.0
        };
        self.inv_g(g)
    }

    /// Clean-up at the start of the pitch laws: above 150 m/s outside modes 0 / 8, gear, flaps, brakes in.
    fn clean(&mut self) {
        if self.v.speed > 150.0 && self.mode != 0 && self.mode != 8 {
            self.gear(false);
            self.flaps(false);
            self.brakes(false);
        }
    }

    /// Pitch law A `5ca010` (pitch attitude target).
    fn pitch(&mut self, target: f32) -> f32 {
        self.clean();
        let roll = self.v.att.roll;
        if (roll.abs() - PI / 2.0).abs() < 1e-5 {
            return 0.0;
        }
        let inv_cos = 1.0 / roll.cos();
        let q0 = self.inv_g(inv_cos).clamp(-1.0, 1.0);
        let mut e = (target - self.v.att.pitch) % (2.0 * PI);
        if e > PI {
            e -= 2.0 * PI;
        }
        let mut c = e / PI * self.c.pitch_k * 0.5 - self.v.rates[0] * self.c.pitch_beta;
        if inv_cos >= 0.0 {
            c = -c;
        }
        if c > 0.0 {
            c *= 1.98;
        }
        let mut q = self.g_stick(c.clamp(-1.0, 1.0));
        if sign(q) == sign(q0) {
            q += q0;
        }
        q.clamp(-1.0, 1.0)
    }

    /// Pitch law B `5c9d30` (StopPlane): the flip and ×1.98 after the g map.
    fn pitch_b(&mut self, target: f32) -> f32 {
        self.clean();
        let roll = self.v.att.roll;
        if (roll.abs() - PI / 2.0).abs() < 1e-5 {
            return 0.0;
        }
        let inv_cos = 1.0 / roll.cos();
        let q0 = self.inv_g(inv_cos).clamp(-1.0, 1.0);
        let e = wrap(target - self.v.att.pitch);
        let c =
            (e / PI * self.c.pitch_k * 0.5 - self.v.rates[0] * self.c.pitch_beta).clamp(-1.0, 1.0);
        let mut q = self.g_stick(c);
        if inv_cos >= 0.0 {
            q = -q;
        }
        if q > 0.0 {
            q *= 1.98;
        }
        if sign(q) == sign(q0) {
            q += q0;
        }
        q.clamp(-1.0, 1.0)
    }

    /// Speed law `5ca360`: throttle for a target TAS.
    fn thr(&self, vt: f32) -> f32 {
        self.thr_k(vt, self.c.speed_k, self.c.speed_beta)
    }

    fn thr_k(&self, vt: f32, k: f32, beta: f32) -> f32 {
        let (f, _, _) = self.v.att.basis();
        let a_long = (f[0] * self.v.acc[0] + f[1] * self.v.acc[1] + f[2] * self.v.acc[2]) as f32;
        (0.7 + 0.005 * k * (vt - self.v.speed) - 0.02 * beta * a_long).clamp(0.0, 1.0)
    }

    /// Watch-ground `5ca480`: 1 = override (wings level, climb over the terrain ahead, ≥ 250 m/s throttle).
    fn watch_ground(&mut self, x: &mut f32, y: &mut f32, thr: &mut f32) -> bool {
        if !self.watch || self.v.on_ground {
            return false;
        }
        let (p, vel) = (self.v.pos, self.v.vel);
        let t = (vel[2] as f32 * (-1.0 / 15.0)).max(0.0) + self.c.watch_ground_dt;
        let a = [
            p[0] + vel[0] * t as f64,
            p[1] + vel[1] * t as f64,
            p[2] + vel[2] * t as f64,
        ];
        let h = (self.ground)(a[0], a[1]) + self.c.h_above_ground;
        if a[2] as f32 > h && self.los(p, a) {
            return false;
        }
        *x = self.roll(0.0);
        let dh = ((a[0] - p[0]).hypot(a[1] - p[1])) as f32;
        let climb = wrap(PI / 24.0 + (h - p[2] as f32).atan2(dh));
        *y = self.pitch(climb.max(0.0));
        *thr = self.thr(250.0).max(*thr);
        true
    }

    /// `0x4020d0` line of sight: the segment clears the terrain. UNCERTAIN (the original's terrain ray); here
    /// 8 samples along the segment.
    fn los(&self, a: V3, b: V3) -> bool {
        (1..=8).all(|i| {
            let f = i as f64 / 8.0;
            let z = a[2] + (b[2] - a[2]) * f;
            z as f32 > (self.ground)(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        })
    }

    fn stick(&mut self, y: f32, x: f32) {
        self.out.stick = Some((y, x));
    }
    fn throttle(&mut self, t: f32) {
        self.out.thr = Some(t);
    }
    fn gear(&mut self, down: bool) {
        self.out.gear = Some(down);
    }
    fn flaps(&mut self, down: bool) {
        self.out.flaps = Some(down);
    }
    fn brakes(&mut self, on: bool) {
        self.out.brakes = Some(on);
    }

    /// LookAt `5ca7d0` + `5cb4d0` (formation: case 1). Returns (y, x) or None when on the target.
    fn look_at(&mut self, t: V3, t_roll: f32, case: u8) -> Option<(f32, f32)> {
        let p = self.v.pos;
        let d = [t[0] - p[0], t[1] - p[1], t[2] - p[2]];
        let dist = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
        if dist <= 0.0 {
            return None;
        }
        let (f, r, u) = self.v.att.basis();
        let dn = [d[0] / dist, d[1] / dist, d[2] / dist];
        let dot = |a: V3| (a[0] * dn[0] + a[1] * dn[1] + a[2] * dn[2]) as f32;
        let (v0, v1, v2) = (dot(r), dot(f), dot(u));
        let mut elev = v2.atan2(v0.hypot(v1));
        if v1 < 0.0 {
            elev = PI - elev;
        }
        let off = v1.clamp(-1.0, 1.0).acos();
        let roll = self.v.att.roll;
        let c = self.c;
        let mut roll_err = 0.0;
        if off >= c.change_roll_cone {
            let n = v2.hypot(v0);
            if n > 0.0 {
                roll_err = (v2 / n).clamp(-1.0, 1.0).acos() * if v0 >= 0.0 { 1.0 } else { -1.0 };
            }
            if roll_err.abs() > PI / 3.0 {
                elev = 0.0;
            }
        } else {
            let psi = v0.atan2(v1);
            let e = wrap(t_roll - roll);
            let (ncc, crc, slow) = (
                c.no_change_roll_cone,
                c.change_roll_cone,
                c.slow_cone_roll_k,
            );
            // 5ada30: the straight line through (x0, y0) and (x1, y1).
            let line =
                |x: f32, x0: f32, y0: f32, x1: f32, y1: f32| y0 + (y1 - y0) * (x - x0) / (x1 - x0);
            roll_err = match case {
                1 => {
                    if dist >= 1854.0 {
                        -roll
                    } else if psi >= ncc {
                        line(psi, ncc, e, crc, slow).min(PI / 2.0)
                    } else if psi > -ncc {
                        e
                    } else {
                        line(psi, -ncc, e, -crc, -slow).max(-PI / 2.0)
                    }
                }
                3 => -roll,
                _ => 0.0,
            };
        }
        let elev = wrap(elev);
        let roll_err = wrap(roll_err);
        // 5cb4d0.
        let rmax = self.v.max_roll_rate;
        let rr = self.v.rates[1];
        let dd = if rr.abs() <= PI {
            rr * rmax
        } else {
            0.5 * rmax * rr
        };
        let x = (roll_err / PI * c.dog_chase_roll_k / rmax - c.dog_chase_roll_beta * dd)
            .clamp(-1.0, 1.0);
        let mut pp = -(elev / PI * c.look_at_k * 0.5 - self.v.rates[0] * c.look_at_beta);
        if pp > 0.0 {
            pp *= 1.98;
        }
        let mut y = self.g_stick(pp.clamp(-1.0, 1.0));
        let q0 = self.inv_g(1.0 / roll.cos()).clamp(-1.0, 1.0);
        if (roll - PI / 2.0).abs() >= 1e-5 && sign(q0) == sign(y) {
            y += q0;
        }
        Some((y.clamp(-1.0, 1.0), x))
    }
}

// --- leaf loops -----------------------------------------------------------------------------------

/// A leaf's result for its parent.
#[derive(PartialEq)]
enum Leaf {
    Run,
    Done,
}

/// ChangeHeading2Pt `5ddef0` (and the landing's ChangeHeading2PtAcu, UNCERTAIN: its line capture): bank on
/// the bearing error, pitch 0; done within `tol`.
fn change_heading(l: &mut Laws, t: [f64; 2], tol: f32, lim: f32, hold_speed: Option<f32>) -> Leaf {
    let p = l.v.pos;
    let brg = ((t[0] - p[0]) as f32).atan2((t[1] - p[1]) as f32);
    let e = wrap(brg - l.v.att.heading);
    if e.abs() <= tol {
        return Leaf::Done;
    }
    let bank = (e / (PI / 6.0) * l.c.change_head_k * lim - l.v.rates[2] * l.c.change_head_beta)
        .clamp(-lim, lim);
    let mut y = l.pitch(0.0);
    let mut x = l.roll(bank);
    let mut thr = hold_speed.map_or(0.0, |s| l.thr(s).min(0.7));
    // ChangeHeading2Pt sends no throttle (its watch-ground throttle is dropped); the landing's CH4 / CH5
    // hold 140 kt (throttle ≤ 0.7, 0x613888).
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
    if hold_speed.is_some() {
        l.throttle(thr);
    }
    Leaf::Run
}

/// ChangeAlt `5cf320`: wings level, pitch from the altitude error (ends only by its condition).
fn change_alt(l: &mut Laws, z: f64) {
    let c130 = l.v.type_code == C130;
    let k = if c130 { 0.002 } else { 0.001 };
    let (lo, hi) = if c130 {
        (-PI / 12.0, PI / 18.0)
    } else {
        (-PI / 6.0, PI / 12.0)
    };
    let pt = ((z - l.v.pos[2]) as f32 * l.c.change_alt_k * (PI / 12.0) * k
        - l.v.vel[2] as f32 * l.c.change_alt_beta)
        .clamp(lo, hi);
    let mut x = l.roll(0.0);
    let mut y = l.pitch(pt);
    let mut thr = 0.0;
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
}

/// KeepAttitude2Pt `5db510` (+ AtSpeed `5dbb80` with `speed`): bank ≤ 45° on the bearing error, pitch to the
/// elevation of the point; the ring period from `5db930`.
fn keep_attitude(l: &mut Laws, t: V3, speed: Option<f32>) {
    let thr = speed.map(|s| l.thr(s));
    let p = l.v.pos;
    let d = [t[0] - p[0], t[1] - p[1], t[2] - p[2]];
    let e = wrap((d[0] as f32).atan2(d[1] as f32) - l.v.att.heading);
    let roll_t = e.clamp(-PI / 4.0, PI / 4.0);
    let elev = (d[2] as f32).atan2(d[0].hypot(d[1]) as f32);
    let mut y = l.pitch(elev);
    let mut x = l.roll(roll_t);
    let mut dummy = 0.0;
    l.watch_ground(&mut x, &mut y, &mut dummy);
    // 5db930: the ring period.
    let dist = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
    let v = l.v.vel;
    let ahead = |k: f64| [p[0] + k * v[0], p[1] + k * v[1], p[2] + k * v[2]];
    l.period = Some(if dist < 1854.0 || y.abs() > 0.01 || x.abs() > 0.01 {
        0.5
    } else if dist < 3708.0 {
        if l.los(p, ahead(1.9)) { 1.5 } else { 0.5 }
    } else if l.los(p, ahead(3.4)) {
        3.0
    } else {
        0.5
    });
    l.stick(y, x);
    if let Some(t) = thr {
        l.throttle(t);
    }
}

/// LevelWingsPitch0Accel `5d2400`: wings level, pitch 0 (FpmPitchReqAtLowVels below Vmin(1.2 g)), speed.
fn level_wings_accel(l: &mut Laws, pitch_t: &mut f32, speed: f32, vmin: f32) -> Leaf {
    let c130 = l.v.type_code == C130;
    let tol = if c130 { 6.0 } else { 3.0 };
    let spd_ok = l.v.speed > speed || (l.v.speed - speed).abs() <= tol;
    if !c130 {
        if l.v.speed <= vmin {
            *pitch_t = l.c.fpm_pitch_low;
        } else if l.v.speed >= vmin + 15.0 {
            *pitch_t = 0.0;
        }
    }
    if (l.v.att.pitch - *pitch_t).abs() <= 0.02 * PI && l.v.att.roll.abs() <= 0.01 * PI && spd_ok {
        return Leaf::Done;
    }
    let mut x = l.roll(0.0);
    let mut y = l.pitch(*pitch_t);
    let mut thr = l.thr(speed);
    if l.watch_ground(&mut x, &mut y, &mut thr) {
        *pitch_t = 0.0;
    }
    l.stick(y, x);
    l.throttle(thr);
    Leaf::Run
}

/// LevelWingsPitch0 `5d2140`: done within `pitch_tol` (ctor default 0.01π; LevelFlightCL sets 0.0035 rad) and
/// |roll| ≤ 1°.
fn level_wings(l: &mut Laws, pitch_tol: f32) -> Leaf {
    if l.v.att.pitch.abs() <= pitch_tol && l.v.att.roll.abs() <= PI / 180.0 {
        return Leaf::Done;
    }
    let mut x = l.roll(0.0);
    let mut y = l.pitch(0.0);
    let mut thr = 0.0;
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
    Leaf::Run
}

/// KeepOrientation `5d9d30` (FirstRun `5da010` stores `keep` = flight-path pitch, heading and the speed): bank
/// = clamp(heading error, ±30°), pitch law to the stored pitch; throttle (speed law to the stored speed) only in
/// an AI mode, else only when the ground watch takes over. Ends only by its condition (none here).
fn keep_orientation(l: &mut Laws, keep: (f32, f32, f32)) {
    let (pitch, heading, speed) = keep;
    let e = wrap(heading - l.v.att.heading);
    let roll_t = (e / (PI / 6.0) * (PI / 6.0)).clamp(-PI / 6.0, PI / 6.0);
    let mut y = l.pitch(pitch);
    let mut x = l.roll(roll_t);
    let mut thr = if l.mode != 0 { l.thr(speed) } else { 0.0 };
    // UNCERTAIN: the player's throttle slot is never initialised before the watch (@5d9efd); taken as 0.
    if l.watch_ground(&mut x, &mut y, &mut thr) || l.mode != 0 {
        l.throttle(thr);
    }
    l.stick(y, x);
}

/// LevelWingsAccel `5d27e0` (formation recovery, 300 m/s): wings level, pitch −11°.
fn level_wings_dive(l: &mut Laws, speed: f32) -> Leaf {
    let spd_ok = l.v.speed > speed || (l.v.speed - speed).abs() <= 3.0;
    if l.v.att.roll.abs() <= 0.01 * PI && spd_ok {
        return Leaf::Done;
    }
    let mut x = l.roll(0.0);
    let mut y = l.pitch(-11f32.to_radians());
    let mut thr = l.thr(speed);
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
    l.throttle(thr);
    Leaf::Run
}

// --- composite loops ------------------------------------------------------------------------------

/// Fly2WayPt `5d6ad0`: children [LevelWingsPitch0Accel, ChangeHeading2Pt, ChangeAlt, KeepAttitude2Pt,
/// LevelWingsPitch0]; the ETA speed law; ends when its condition holds.
#[derive(Debug, Clone)]
struct Fly2Wp {
    t: V3,
    eta: f64,
    cap: Option<f32>,
    /// GoHome's condition: within this 2-D radius (else the PassWaypoint at +0x588).
    end_radius: Option<f64>,
    pass: Pass,
    pass_alt: Pass,
    child: usize,
    lw_pitch: f32,
    first: bool,
}

impl Fly2Wp {
    fn new(t: V3, eta: f64) -> Self {
        Fly2Wp {
            t,
            eta,
            cap: None,
            end_radius: None,
            pass: Pass::new(PASS_R),
            pass_alt: Pass::new(PASS_R),
            child: 0,
            lw_pitch: 0.0,
            first: true,
        }
    }

    /// Returns Done when the waypoint is reached (or the last child ended).
    fn step(&mut self, l: &mut Laws, vmin12: f32) -> Leaf {
        let pos = l.v.pos;
        if self.first {
            self.first = false;
            // 5d6fb0: in an AI mode (≠ 0; not the player's autopilot) a larger capture radius when starting
            // inside it.
            let g = l.v.max_g;
            let r = if g <= 4.0 {
                9265.0
            } else if g < 6.5 {
                6485.5
            } else {
                3983.95
            };
            self.pass.r = if l.mode != 0 && dist2(pos, self.t[0], self.t[1]) < r {
                r
            } else {
                PASS_R
            };
        }
        let done = match self.end_radius {
            Some(r) => dist2(pos, self.t[0], self.t[1]) < r,
            None => self.pass.test(pos, self.t[0], self.t[1]),
        };
        if done {
            return Leaf::Done;
        }
        let d = ((self.t[0] - pos[0]).powi(2)
            + (self.t[1] - pos[1]).powi(2)
            + (self.t[2] - pos[2]).powi(2))
        .sqrt() as f32;
        let dt = ((self.eta - l.v.t) * 1000.0).trunc() * 0.001;
        let c130 = l.v.type_code == C130;
        let mut v = if dt > 0.0 {
            let v = d / dt as f32;
            if c130 {
                v.clamp(60.0, 215.0)
            } else {
                v.clamp(V_MIN_NAV, V_MAX_NAV)
            }
        } else if c130 {
            215.0
        } else {
            V_NO_ETA
        };
        if let Some(cap) = self.cap
            && d < 6000.0 && v >= cap {
                v = cap;
            }
        let thr = l.thr(v);
        l.throttle(thr);
        // The current child.
        let lw_speed = match l.v.type_code {
            C130 => 90.0,
            220 => 135.0,
            _ => 180.0,
        };
        let r = match self.child {
            0 => level_wings_accel(l, &mut self.lw_pitch, lw_speed, vmin12),
            1 => change_heading(
                l,
                [self.t[0], self.t[1]],
                0.02 * PI,
                80f32.to_radians(),
                None,
            ),
            2 => {
                if self.pass_alt.test(pos, self.t[0], self.t[1])
                    || (pos[2] - self.t[2]).abs() < 250.0
                {
                    Leaf::Done
                } else {
                    change_alt(l, self.t[2]);
                    Leaf::Run
                }
            }
            3 => {
                if self.pass.test(pos, self.t[0], self.t[1]) {
                    Leaf::Done
                } else {
                    keep_attitude(l, self.t, None);
                    Leaf::Run
                }
            }
            _ => level_wings(l, 0.01 * PI),
        };
        if r == Leaf::Done {
            l.stick(0.0, 0.0); // 5c99e0
            self.child += 1;
            if self.child > 4 {
                return Leaf::Done;
            }
        }
        Leaf::Run
    }
}

/// The taxi loop `TaxiCL` (docs/ai.md §8.2): departure (hangar → lineup) or to park (runway → hangar).
#[derive(Debug, Clone)]
struct Taxi {
    park: bool,
    path: Vec<TaxiPt>,
    i: usize,
    turning: bool,
    waiting: bool,
    start: f64,
    at_lineup: bool,
    first: bool,
    hangar: Option<(usize, usize)>,
}

/// Loop states per mode.
#[derive(Debug, Clone)]
enum Loop {
    None,
    Nav {
        f: Option<Fly2Wp>,
        idx: usize,
    },
    GoHome {
        f: Fly2Wp,
        /// Boxed: the landing's pattern is large next to the other states.
        land: Option<Box<Landing>>,
    },
    TakeOff {
        stage: u8,
        taxi: Taxi,
        ka_target: V3,
        ka_speed: f32,
        ka_radius: Option<f64>,
    },
    Formation {
        recover: bool,
        lateral: f32,
        longitudinal: f32,
    },
    Hold {
        t: V3,
    },
    Straight {
        pitch: f32,
    },
    /// The player's LevelFlightCL (manager +0x4528, Init `5cd8c0`): LevelWingsPitch0 (pitch within 0.0035 rad),
    /// then KeepOrientation on what it holds then.
    Level {
        keep: Option<(f32, f32, f32)>,
    },
    /// The player's NAV to one waypoint: the manager's Fly2WayPt (+0x4f8) set up by `5c7bc0`; done = stick
    /// centred (the HUD's waypoint sequencing posts the next one).
    Fly {
        f: Option<Fly2Wp>,
    },
}

/// LandingCL (docs/ai.md §8.3): the pattern points and the step list.
#[derive(Debug, Clone)]
struct Landing {
    step: usize,
    pts: [V3; 5],
    rn: f32,
    k: f64,
    lw_pitch: f32,
    taxi: Option<Taxi>,
    park: Option<(f64, f64, f32, f64)>,
    /// StopPlane passed (the landed handler, controller +0xe0).
    landed: bool,
    /// The current ChangeHeading2PtAcu leg's state.
    acu: Option<Acu>,
    /// Flown by the player's autopilot (FM mode 0): no taxi / park children (`5d43e0`), StopPlane ends at
    /// 1.0295 m/s instead of 25.736 (`5d36d2`), no landed handler, then the autopilot key.
    player: bool,
}

/// A LandingCL child (docs/ai.md §8.3).
#[derive(Debug, Clone, Copy)]
enum Leg {
    /// ChangeHeading2PtAcu to point i: heading tolerance, bank limit, fixed speed (else the entry speed).
    Ch(usize, f32, f32, Option<f32>),
    /// ChangeAlt to point i's altitude until |Δz| < r.
    Ca(usize, f64),
    /// ChangeAlt (C-130 CA1) until within r (2-D) or |Δz| < 250.
    CaOr(usize, f64),
    /// LevelWingsPitch0Accel at a speed.
    Lw(f32),
    /// KeepAttitude2PtAtSpeed to point i until within r (2-D).
    Ka(usize, f32, f64),
    Fa(f64),
    Stop,
    Taxi,
    Park,
}

/// ChangeHeading2PtAcu (vtable 0x6138a0, Run `5dbe70`, FirstRun `5dd1f0`).
#[derive(Debug, Clone, Copy)]
struct Acu {
    vt: f32,
    done_latch: bool,
    acu: bool,
}

impl Acu {
    fn new(entry_speed: f32, vt: Option<f32>) -> Self {
        Acu { vt: vt.unwrap_or(entry_speed), done_latch: false, acu: true }
    }

    fn step(&mut self, l: &mut Laws, p: V3, prev: Option<V3>, tol: f32, lim: f32) -> Leaf {
        let v = l.v;
        let pos = v.pos;
        let (dx, dy) = (p[0] - pos[0], p[1] - pos[1]);
        let target = if dx == 0.0 && dy == 0.0 { 0.0 } else { wrap((dx as f32).atan2(dy as f32)) };
        let mut cos_a = 1.0f64;
        if let Some(q) = prev {
            let (lx, ly) = (p[0] - q[0], p[1] - q[1]);
            let (ln, dn) = (lx.hypot(ly), dx.hypot(dy));
            if ln > 0.0 && dn > 0.0 {
                cos_a = (lx * dx + ly * dy) / (ln * dn);
            }
        }
        let mut e = wrap(target - v.att.heading);
        if prev.is_some() {
            // Line capture (as coded, UNCERTAIN intent): e −= ±acos(cos α).
            let mut sg = if e.to_degrees() > 0.0 { -1.0 } else { 1.0 };
            if cos_a > 0.0 {
                sg = -sg;
            }
            let a = wrap((cos_a.clamp(-1.0, 1.0).acos() as f32) * sg);
            e = wrap(e - a);
        }
        // Done on two consecutive ticks (the roll test is signed, as the original).
        let roll_deg = v.att.roll.to_degrees();
        if (e.abs() <= tol || roll_deg <= 0.2) && self.done_latch {
            l.period = Some(0.5);
            l.out.rudder = Some(0.0);
            let y = l.pitch(0.0);
            let x = l.roll(0.0);
            l.stick(y, x);
            l.throttle(0.1);
            return Leaf::Done;
        }
        self.done_latch = e.abs() <= tol && roll_deg <= 0.2;
        let c = l.c;
        let bank0 = (e / (PI / 6.0) * lim * c.change_head_k - v.rates[2] * c.change_head_beta).clamp(-lim, lim);
        let mut bank = bank0;
        if let (Some(q), true) = (prev, self.acu && e.abs() > 0.034_906_6) {
            // The "Acu" search: the bank whose turn circle is tangent to the line prev → p.
            let (mut conv, mut n, mut d_t) = (false, 0, f64::MAX);
            loop {
                if bank.abs() <= 0.017_453_3 || bank.abs() > lim {
                    break;
                }
                let r = (v.speed * v.speed / (bank.tan().abs() * 9.806)) as f64;
                let (m, cc) = if p[0] != q[0] { let m = (p[1] - q[1]) / (p[0] - q[0]); (m, p[1] - p[0] * m) } else { (0.0, 0.0) };
                let h = v.att.heading as f64;
                let sb = bank.signum() as f64;
                let cx = pos[0] + sb * r * h.cos();
                let cy = pos[1] - sb * r * h.sin();
                let (dist_cl, t) = if q[1] == p[1] {
                    ((m * cx + cc - cy).abs(), (pos[0], m * pos[0] + cc))
                } else if q[0] == p[0] {
                    ((p[0] - cx).abs(), (p[0], pos[1]))
                } else if m == 0.0 {
                    (0.0, (0.0, 0.0))
                } else {
                    // Original bug: the perpendicular uses the slope −m, and the foot is truncated to integers.
                    let ix = ((cy + m * cx - cc) / (2.0 * m)).trunc();
                    let iy = (-m * ix + cy + m * cx).trunc();
                    let jx = ((pos[1] + m * pos[0] - cc) / (2.0 * m)).trunc();
                    let jy = (-m * jx + pos[1] + m * pos[0]).trunc();
                    ((ix - cx).hypot(iy - cy), (jx, jy))
                };
                n += 1;
                let gap = dist_cl - r;
                d_t = (t.0 - pos[0]).hypot(t.1 - pos[1]);
                if gap.abs() < 1.0 || n >= 100 {
                    conv = true;
                    if d_t < 2.0 {
                        bank = bank0;
                    }
                    break;
                }
                bank += (gap * 0.01 * 0.017_453_3) as f32;
            }
            if !conv || d_t < 2.0 {
                self.acu = false;
            }
        }
        let thr = l.thr(self.vt).min(0.7);
        l.throttle(thr);
        let y = l.pitch(0.0);
        let x = l.roll(bank);
        // Watch-ground is skipped in modes 0 and 8 (the landing).
        l.out.rudder = Some(0.0);
        l.stick(y, x);
        Leaf::Run
    }
}

/// Hangars taken at every base (TowersManager +0x4f4 flags), shared by all jets of the flight.
static OCCUPIED: std::sync::Mutex<Vec<(usize, usize)>> = std::sync::Mutex::new(Vec::new());

/// Frees every hangar (`54f920`, a new mission).
pub fn reset_hangars() {
    OCCUPIED.lock().unwrap().clear();
}

fn occupy(b: usize, h: usize, on: bool) {
    let mut o = OCCUPIED.lock().unwrap();
    o.retain(|x| *x != (b, h));
    if on {
        o.push((b, h));
    }
}

/// The autopilot of one jet.
#[derive(Debug, Clone)]
pub struct Autopilot {
    pub cfg: Config,
    pub route: Vec<Waypoint>,
    pub bases: Vec<Airbase>,
    /// World position of the frame's origin (X east, Y north): the host may shift `bases`, `route` and the jet
    /// by it. LandingCL rounds its points to f32 in world coordinates, as the original.
    pub origin: [f64; 2],
    /// Formation leader (None: I am the leader, or no formation).
    pub leader: Option<Leader>,
    /// Current waypoint index (brain +0x88).
    pub wp_index: usize,
    /// Landed once (brain / controller +0xe0).
    pub landed: bool,
    mode: u8,
    lp: Loop,
    next_tick: f64,
    period: f64,
    watch: bool,
}

impl Autopilot {
    pub fn new(cfg: Config) -> Self {
        Autopilot {
            cfg,
            route: Vec::new(),
            bases: Vec::new(),
            origin: [0.0; 2],
            leader: None,
            wp_index: 0,
            landed: false,
            mode: 0,
            lp: Loop::None,
            next_tick: 0.0,
            period: 0.5,
            watch: true,
        }
    }

    pub fn mode(&self) -> u8 {
        self.mode
    }

    /// The loop's stage, for logs and tests.
    pub fn stage(&self) -> String {
        match &self.lp {
            Loop::Nav { idx, .. } => format!("nav wp {}", idx),
            Loop::GoHome { land: None, .. } => "go home: fly to the last waypoint".into(),
            Loop::GoHome { land: Some(l), .. } => format!("landing step {}", l.step),
            Loop::TakeOff { stage, taxi, .. } => format!("take-off stage {stage} taxi point {}", taxi.i),
            Loop::Formation { recover, .. } => format!("formation{}", if *recover { " (recovering)" } else { "" }),
            Loop::Hold { .. } => "hold".into(),
            Loop::Straight { .. } => "straight".into(),
            Loop::Level { keep: None } => "level: wings level".into(),
            Loop::Level { .. } => "level: keep orientation".into(),
            Loop::Fly { f } => format!("nav{}", if f.is_none() { " (passed)" } else { "" }),
            Loop::None => "none".into(),
        }
    }

    /// `setMode` (`5a8410`): an identical command is ignored; else the loop starts (first tick after 0.5 s).
    pub fn set_mode(&mut self, ac: &mut Aircraft, mode: u8) {
        if mode == self.mode {
            return;
        }
        let now = ac.ap_view().t;
        if self.mode == 0 && mode != 0 {
            ac.ai_since = now;
        }
        self.mode = mode;
        ac.ai_mode = mode;
        self.watch = true;
        self.period = 0.5;
        self.next_tick = now + 0.5;
        let v = ac.ap_view();
        self.lp = match mode {
            7 => Loop::Nav {
                f: None,
                idx: self.wp_index,
            },
            8 => self.go_home(&v, now),
            9 => {
                let (ka_target, ka_speed, ka_radius) = match self.route.first() {
                    Some(w) => ([w.x, w.y, w.z], 205.889, Some(500.0)),
                    None => (v.pos, 180.153, None),
                };
                Loop::TakeOff {
                    stage: if v.on_ground { 0 } else { 2 },
                    taxi: Taxi {
                        park: false,
                        path: Vec::new(),
                        i: 0,
                        turning: false,
                        waiting: false,
                        start: 0.0,
                        at_lineup: false,
                        first: true,
                        hangar: None,
                    },
                    ka_target,
                    ka_speed,
                    ka_radius,
                }
            }
            1 | 3 => Loop::Formation {
                recover: false,
                lateral: if mode == 1 { 100.0 } else { 200.0 },
                longitudinal: -20.0,
            },
            10 => {
                let g = v.ground_height;
                Loop::Hold {
                    t: [v.pos[0], v.pos[1], v.pos[2].max(g as f64 + 300.0)],
                }
            }
            0xb => Loop::Straight { pitch: 0.0 },
            _ => Loop::None,
        };
    }

    /// GoHomeCL Init `5cd390`: Fly2WayPt to the route's last waypoint (no route: here), then LandingCL.
    fn go_home(&self, v: &ApView, now: f64) -> Loop {
        let (t, cap) = match self.route.last() {
            Some(w) => ([w.x, w.y, w.z], if v.type_code == C130 { 128.68 } else { 180.15 }),
            None => (v.pos, 180.15),
        };
        let mut f = Fly2Wp::new(t, now + 60.0);
        f.cap = Some(cap);
        f.end_radius = Some(100.0);
        Loop::GoHome { f, land: None }
    }

    /// The player's autopilot, FM motion 0xf (`5a1e40`, docs/autopilot.md): 0 off (`5c8800`), 1 LevelFlightCL
    /// (`5c82c0`), 2 NAV to route waypoint `wp` (`5c7bc0`: Fly2WayPt with its ETA), or GoHomeCL (`5c7d80`) when
    /// that waypoint's action is 7 (land). The FM mode stays 0: the jet keeps the player's rules. The loop
    /// starts on the next ring tick (0.5 s, `5c9a90`).
    pub fn player_mode(&mut self, ac: &mut Aircraft, mode: u8, wp: usize) {
        let v = ac.ap_view();
        self.lp = match (mode, self.route.get(wp)) {
            (1, _) => Loop::Level { keep: None },
            (2, Some(w)) if w.action == 7 => self.go_home(&v, v.t),
            (2, Some(w)) => Loop::Fly { f: Some(Fly2Wp::new([w.x, w.y, w.z], w.t)) },
            // 5c7bc0 without a route starts the loop uninitialised (UNCERTAIN): nothing flies.
            _ => Loop::None,
        };
        self.watch = true;
        self.period = 0.5;
        self.next_tick = v.t + 0.5;
    }

    /// The player's autopilot loop is running (FM motion 0xf mode ≠ 0).
    pub fn player_active(&self) -> bool {
        self.mode == 0 && !matches!(self.lp, Loop::None)
    }

    /// Runs the loop's ring tick when due, applies its outputs to the aircraft and returns them.
    pub fn step(&mut self, ac: &mut Aircraft, ground: Ground) -> Out {
        if matches!(self.lp, Loop::None) {
            return Out::default();
        }
        let v = ac.ap_view();
        if v.t < self.next_tick {
            return Out::default();
        }
        let vmin12 = ac.vmin(v.pos[2] as f32, 1.2);
        let vmin125 = ac.vmin(v.pos[2] as f32, 1.25);
        let vmin25 = ac.vmin(v.pos[2] as f32, 2.5);
        let vmin1 = ac.vmin(v.pos[2] as f32, 1.0);
        let cfg = self.cfg;
        let mut l = Laws {
            c: &cfg,
            v: &v,
            mode: self.mode,
            watch: self.watch,
            ground,
            out: Out::default(),
            period: None,
        };
        let mut lp = std::mem::replace(&mut self.lp, Loop::None);
        let mut period = self.period;
        match &mut lp {
            Loop::Nav { f, idx } => {
                let mut advance = f.is_none();
                if let Some(ff) = f
                    && ff.step(&mut l, vmin12) == Leaf::Done {
                        l.stick(0.0, 0.0); // 5c99e0
                        advance = true;
                    }
                if advance {
                    // WayPtSet next (5d7450): the next waypoint, or the stick centred past the last.
                    match self.route.get(*idx).copied() {
                        Some(w) => {
                            *f = Some(Fly2Wp::new([w.x, w.y, w.z], w.t));
                            self.wp_index = *idx;
                            *idx += 1;
                        }
                        None => {
                            *f = None;
                            l.stick(0.0, 0.0);
                        }
                    }
                }
            }
            Loop::GoHome { f, land } => {
                if land.is_none() {
                    if f.step(&mut l, vmin12) == Leaf::Done {
                        l.stick(0.0, 0.0);
                        *land = Landing::new(&self.bases, self.origin, f.t, v.type_code, self.mode == 0).map(Box::new);
                    }
                } else if let Some(ld) = land {
                    ld.step(&mut l, self, &mut period, vmin1);
                    if ld.landed {
                        self.landed = true;
                    }
                    if ld.step >= 13 {
                        self.watch = false;
                    }
                }
            }
            Loop::TakeOff {
                stage,
                taxi,
                ka_target,
                ka_speed,
                ka_radius,
            } => match stage {
                0 => {
                    period = 0.2;
                    if taxi.step(&mut l, self, false) == Leaf::Done {
                        *stage = 1;
                        // TakeoffCL FirstRun: flaps down, throttle 1.
                        l.flaps(true);
                        l.throttle(1.0);
                    }
                }
                1 => {
                    period = 0.2;
                    if self.takeoff_step(&mut l) == Leaf::Done {
                        period = 0.5;
                        *stage = 2;
                    }
                }
                2 => {
                    if ka_radius.is_some_and(|r| dist2(v.pos, ka_target[0], ka_target[1]) < r) {
                        l.stick(0.0, 0.0);
                        *stage = 3;
                    } else {
                        keep_attitude(&mut l, *ka_target, Some(*ka_speed));
                    }
                }
                _ => l.stick(0.0, 0.0),
            },
            Loop::Formation {
                recover,
                lateral,
                longitudinal,
            } => {
                period = 0.25;
                self.formation_step(&mut l, recover, lateral, *longitudinal, vmin125, vmin25);
            }
            Loop::Hold { t } => keep_attitude(&mut l, *t, Some(180.0)),
            Loop::Straight { pitch } => {
                let _ = level_wings_accel(&mut l, pitch, 180.0, vmin12);
            }
            Loop::Level { keep } => match keep {
                None => {
                    if level_wings(&mut l, 0.0035) == Leaf::Done {
                        l.stick(0.0, 0.0); // 5c99e0; KeepOrientation's FirstRun on the next tick
                        *keep = Some((f32::NAN, 0.0, 0.0));
                    }
                }
                Some(k) => {
                    if k.0.is_nan() {
                        *k = (v.att.pitch, v.att.heading, v.speed);
                    }
                    keep_orientation(&mut l, *k);
                }
            },
            Loop::Fly { f } => {
                if let Some(ff) = f
                    && ff.step(&mut l, vmin12) == Leaf::Done {
                        l.stick(0.0, 0.0);
                        *f = None;
                    }
            }
            Loop::None => {}
        }
        if let Some(p) = l.period {
            period = p;
        }
        let out = l.out;
        if !matches!(self.lp, Loop::None) {
            // A loop was replaced from inside (not used).
        } else {
            self.lp = lp;
        }
        self.period = period;
        self.next_tick = v.t + period;
        self.apply(ac, out);
        out
    }

    fn apply(&self, ac: &mut Aircraft, o: Out) {
        if let Some((x, y, h)) = o.replace {
            ac.replace_on_ground(x, y, h);
        }
        if let Some(p) = o.pivot {
            ac.set_pivot(p);
        }
        let mut c: Controls = ac.controls();
        if let Some((y, x)) = o.stick {
            c.stick_y = -y;
            c.stick_x = x;
        }
        if let Some(t) = o.thr {
            c.throttle = t;
        }
        if let Some(r) = o.rudder {
            c.rudder = r;
        }
        if let Some(g) = o.gear {
            c.gear_down = g;
        }
        if let Some(f) = o.flaps {
            c.flaps = if f { 1.0 } else { 0.0 };
        }
        if let Some(b) = o.brakes {
            c.brakes = b;
        }
        ac.set_controls(c);
        if o.engine_off {
            ac.engine_off();
        }
    }

    /// TakeoffCL Run `5cda10`.
    fn takeoff_step(&self, l: &mut Laws) -> Leaf {
        let v = l.v;
        if let Some(ld) = self.leader.filter(|ld| ld.active) {
            let lv = (ld.vel[0].powi(2) + ld.vel[1].powi(2) + ld.vel[2].powi(2)).sqrt() as f32;
            if lv < 25.7361 {
                l.brakes(true);
                l.throttle(0.6);
                return Leaf::Run;
            }
        }
        l.brakes(false);
        l.throttle(1.0);
        let agl = v.pos[2] as f32 - v.ground_height;
        if agl > 100.0 {
            l.gear(false);
            l.flaps(false);
            l.stick(0.0, 0.0);
            return Leaf::Done;
        }
        let theta = if v.speed > 87.5028 && v.speed <= 97.7972 {
            3f32.to_radians()
        } else if v.speed > 97.7972 {
            if v.speed > 108.092 {
                l.gear(false);
                l.flaps(false);
            }
            6f32.to_radians()
        } else {
            return Leaf::Run;
        };
        let y = l.pitch(theta);
        let x = l.roll(0.0);
        l.stick(y, x);
        Leaf::Run
    }

    /// Close / Tactical formation step `5cfb50`.
    fn formation_step(
        &self,
        l: &mut Laws,
        recover: &mut bool,
        lateral: &mut f32,
        longitudinal: f32,
        vmin125: f32,
        vmin25: f32,
    ) {
        let v = l.v;
        let Some(ld) = self.leader else {
            l.stick(0.0, 0.0);
            return;
        };
        if v.speed < vmin125 || *recover {
            *recover = true;
            let _ = level_wings_dive(l, 300.0);
            if v.speed > vmin25 {
                *recover = false;
            }
            return;
        }
        let e = crate::aircraft::Euler {
            pitch: ld.att[0],
            roll: ld.att[1],
            heading: ld.att[2],
        };
        let (f, _, u) = e.basis();
        let an = f[0].hypot(f[1]).max(1e-9);
        let a = [f[0] / an, f[1] / an, 0.0];
        let u = if u[2] < 0.0 { [-u[0], -u[1], -u[2]] } else { u };
        // C = horizontal(U × A), normalised: the leader's left.
        let cx = u[1] * a[2] - u[2] * a[1];
        let cy = u[2] * a[0] - u[0] * a[2];
        let cn = cx.hypot(cy).max(1e-9);
        let cvec = [cx / cn, cy / cn];
        let dz = ld.pos[2] - v.pos[2];
        let k = 2000.0 - dz.abs().min(200.0) * 8.5;
        if *lateral == 200.0 && ld.pos[2] < 1524.0 {
            *lateral = 150.0;
        }
        let d = *lateral as f64;
        // Single player: the side flag stays 0, so every wingman takes the right slot (−C). UNCERTAIN.
        let mut q = [
            ld.pos[0] + k * a[0] - d * cvec[0],
            ld.pos[1] + k * a[1] - d * cvec[1],
            ld.pos[2],
        ];
        q[2] = (q[2] + dz).max((l.ground)(q[0], q[1]) as f64 + 91.44);
        let lo = longitudinal as f64;
        let s = [
            ld.pos[0] + lo * a[0] - d * cvec[0],
            ld.pos[1] + lo * a[1] - d * cvec[1],
            ld.pos[2],
        ];
        let (mut y, mut x) = l.look_at(q, ld.att[1], 1).unwrap_or((0.0, 0.0));
        // Speed law 5d0870.
        let dd = [v.pos[0] - s[0], v.pos[1] - s[1], v.pos[2] - s[2]];
        let dl = (dd[0] * dd[0] + dd[1] * dd[1] + dd[2] * dd[2]).sqrt();
        let dn = if dl > 0.0 {
            [dd[0] / dl, dd[1] / dl, dd[2] / dl]
        } else {
            [1.0, 0.0, 0.0]
        };
        let vl = (ld.vel[0].powi(2) + ld.vel[1].powi(2) + ld.vel[2].powi(2)).sqrt();
        let lvn = if vl > 0.0 {
            [ld.vel[0] / vl, ld.vel[1] / vl, ld.vel[2] / vl]
        } else {
            [0.0, 1.0, 0.0]
        };
        let cosang = (dn[0] * lvn[0] + dn[1] * lvn[1] + dn[2] * lvn[2]).clamp(-1.0, 1.0);
        let xx = ((cosang.acos() - std::f64::consts::FRAC_PI_2) * dl.min(5562.0) / 4500.0) as f32;
        let vl = vl as f32;
        let spd = (vl + 2.0 * vl * (xx - xx * xx / 2.0 + xx.powi(3) / 6.0 - xx.powi(4) / 24.0)
            - 30.0)
            .clamp(103.0, 515.0);
        let mut thr = l.thr(spd);
        l.watch_ground(&mut x, &mut y, &mut thr);
        l.stick(y, x);
        l.throttle(thr);
    }
}

impl Taxi {
    /// TaxiCL FirstRun + Run (docs/ai.md §8.2).
    fn step(&mut self, l: &mut Laws, ap: &Autopilot, _unused: bool) -> Leaf {
        let v = l.v;
        let pos = v.pos;
        let Some((bi, base)) = ap.bases.iter().enumerate().min_by(|a, b| {
            let d = |x: &Airbase| {
                (0..3)
                    .map(|i| (x.lineup[i] as f64 - pos[i]).powi(2))
                    .sum::<f64>()
            };
            d(a.1).total_cmp(&d(b.1))
        }) else {
            return Leaf::Done;
        };
        let lineup = base.lineup;
        if self.first {
            self.first = false;
            self.at_lineup = dist2(pos, lineup[0] as f64, lineup[1] as f64) < 100.0;
            if !self.park {
                let wp0 = ap.route.first().map_or(0.0, |w| w.t);
                self.start = if ap.leader.is_none() {
                    wp0
                } else {
                    wp0 + if self.at_lineup { 0.0 } else { 10.0 }
                };
                self.waiting = true;
            }
            if self.at_lineup && !self.park {
                return self.run(l, ap);
            }
            if !self.park {
                let h = base.hangar_near(pos[0] as f32, pos[1] as f32);
                let mut path = Vec::new();
                if let Some(h) = h {
                    occupy(bi, h, true);
                    self.hangar = Some((bi, h));
                    path.push(base.from_hangar_turn[h]);
                }
                path.extend(base.from_taxi.iter().copied());
                // Drop the points before the one nearest in 2-D.
                if let Some((n, _)) = path.iter().enumerate().min_by(|a, b| {
                    dist2(pos, a.1.x as f64, a.1.y as f64).total_cmp(&dist2(
                        pos,
                        b.1.x as f64,
                        b.1.y as f64,
                    ))
                }) {
                    path.drain(..n);
                }
                let at_hangar = h.is_some_and(|h| {
                    dist2(pos, base.hangars[h].x as f64, base.hangars[h].y as f64) <= 100.0
                });
                if !at_hangar
                    && let Some(p0) = path.first() {
                        // Re-placed 60 m before the first point on its heading, at rest (UNCERTAIN: the sign).
                        let x = p0.x as f64 - 60.0 * (p0.hdg as f64).sin();
                        let y = p0.y as f64 - 60.0 * (p0.hdg as f64).cos();
                        l.out.replace = Some((x, y, p0.hdg));
                    }
                if path.first().is_some_and(|p| {
                    dist2(
                        [p.x as f64, p.y as f64, 0.0],
                        lineup[0] as f64,
                        lineup[1] as f64,
                    ) < 100.0
                }) {
                    self.at_lineup = true;
                }
                self.path = path;
            } else {
                let o = OCCUPIED.lock().unwrap().clone();
                let n = base.hangars.len();
                let h = if v.type_code == C130 {
                    n.saturating_sub(1)
                } else {
                    (0..n).find(|h| !o.contains(&(bi, *h))).unwrap_or(0)
                };
                if n > 0 {
                    occupy(bi, h, true);
                    self.hangar = Some((bi, h));
                }
                let mut path: Vec<TaxiPt> = base.to_taxi.clone();
                if n > 0 {
                    path.push(base.to_hangar_turn[h]);
                    path.push(base.hangars[h]);
                }
                self.path = path;
            }
            return Leaf::Run;
        }
        self.run(l, ap)
    }

    fn run(&mut self, l: &mut Laws, ap: &Autopilot) -> Leaf {
        let v = l.v;
        let now = v.t;
        let lead = ap.leader;
        let i_am_lead = lead.is_none();
        let free = lead.is_none_or(|ld| !ld.active);
        let (mut near, mut tight, mut lead_v, mut lead_moving) = (false, false, 0.0, false);
        if let Some(ld) = lead {
            lead_v = (ld.vel[0].hypot(ld.vel[1])) as f32;
            lead_moving = lead_v > 1.0;
            let h = v.att.heading as f64;
            let (dx0, dy0) = (v.pos[0] - ld.pos[0], v.pos[1] - ld.pos[1]);
            let dx = dx0 * h.cos() - dy0 * h.sin();
            let dy = dx0 * h.sin() + dy0 * h.cos();
            near = dx.abs() < 50.0 && dy.abs() < 200.0;
            tight = dx.abs() < 50.0 && dy.abs() < 100.0;
        }
        if !i_am_lead && !free && lead_moving {
            self.start = now;
        }
        if self.waiting && !self.park {
            if now < self.start {
                if !free && !i_am_lead && tight {
                    self.start = now + 3.0;
                }
                if !i_am_lead && self.at_lineup {
                    l.out.rudder = Some(0.0);
                    l.throttle(0.0);
                    l.brakes(false);
                    return Leaf::Done;
                }
                l.brakes(true);
                l.throttle(0.0);
                return Leaf::Run;
            }
            self.waiting = false;
            l.brakes(false);
            if self.at_lineup {
                return Leaf::Done;
            }
            if let Some((b, h)) = self.hangar.take() {
                occupy(b, h, false);
            }
        }
        let mut thr = l.thr_k(15.4417, l.c.speed_taxi_k, l.c.speed_taxi_beta);
        if !self.park && !free && !i_am_lead && tight {
            self.waiting = true;
            self.start = now + 3.0;
            l.brakes(true);
            l.throttle(0.0);
            return Leaf::Run;
        } else if !self.park && !free && !i_am_lead && near && lead_moving {
            thr = l.thr_k(lead_v, l.c.speed_taxi_k, l.c.speed_taxi_beta);
        }
        l.brakes(false);
        let mut done = false;
        if let Some(p) = self.path.get(self.i).copied() {
            // Along-track distance to the point.
            let h = v.att.heading as f64;
            let along = (p.x as f64 - v.pos[0]) * h.sin() + (p.y as f64 - v.pos[1]) * h.cos();
            if !self.turning && along <= 30.0 {
                l.out.pivot = Some(Some(p.hdg));
                self.turning = true;
            }
            if self.turning && wrap(p.hdg - v.att.heading).abs() < 0.5f32.to_radians() {
                l.out.pivot = Some(None);
                self.i += 1;
                self.turning = false;
                l.stick(0.0, 0.0);
                l.out.rudder = Some(0.0);
                if self.i >= self.path.len() {
                    l.out.rudder = Some(0.0);
                    l.throttle(0.0);
                    l.brakes(false);
                    done = true;
                }
            }
        } else {
            done = true;
        }
        if !done && v.type_code != C130 {
            thr = thr.min(0.7);
        }
        if !done {
            l.throttle(thr);
        }
        if done { Leaf::Done } else { Leaf::Run }
    }
}

impl Landing {
    /// LandingCL Init `5d2b30`: the left-hand pattern from G to the nearest base's lineup.
    fn new(bases: &[Airbase], origin: [f64; 2], g: V3, type_code: u32, player: bool) -> Option<Self> {
        let base = Airbase::nearest(bases, [g[0] as f32, g[1] as f32, g[2] as f32])?;
        let c130 = type_code == C130;
        let rn = base.runway_deg.to_radians();
        let ht = base.lineup[2] as f64; // UNCERTAIN: terrain(L); the lineup's altitude here
        // The frame and the points are f32 in world coordinates, as the original (`459bd0` / `459c90`: θ =
        // rad(fmod(−RN, 360)), the matrix `43ecd0` rotated by θ, `43dd70`, then L + the offset rounded to f32). So
        // for an axis-aligned runway the residue of cos θ (~1e-8) vanishes and the legs P1→P2, P2→P3 and
        // P3→P4→P5 are exactly horizontal / vertical lines: ChangeHeading2PtAcu's tangent search takes its
        // axis-parallel branches.
        let w = |x: f64, y: f64| [(x + origin[0]) as f32, (y + origin[1]) as f32];
        let lw = w(base.lineup[0] as f64, base.lineup[1] as f64);
        let th = std::f32::consts::PI * ((-base.runway_deg) % 360.0) / 180.0;
        let (s, c) = (-th.sin(), th.cos());
        let at = |o: [f32; 2], x: f32, y: f32| {
            [(o[0] + (x * c + y * s)) as f64 - origin[0], (o[1] + (-x * s + y * c)) as f64 - origin[1]]
        };
        let side = if c130 { -9270.0 } else { -5562.0 };
        let p1 = at(w(g[0], g[1]), side, 0.0);
        let l = at(lw, 0.0, 0.0);
        let p2 = at(lw, side, -7416.0);
        let p3 = at(lw, 0.0, -7416.0);
        let p4 = at(lw, 0.0, if c130 { -1854.0 } else { -3708.0 });
        Some(Landing {
            step: 0,
            pts: [
                [p1[0], p1[1], ht + 700.0],
                [p2[0], p2[1], ht + if c130 { 600.0 } else { 500.0 }],
                [p3[0], p3[1], ht + if c130 { 350.0 } else { 300.0 }],
                [p4[0], p4[1], ht + 250.0],
                [l[0], l[1], ht],
            ],
            rn,
            k: if c130 { 2.0 } else { 1.0 },
            lw_pitch: 0.0,
            taxi: None,
            park: None,
            landed: false,
            acu: None,
            player,
        })
    }

    /// The child list of LandingCL (ctor `5c6370`): CH1, CA1, LW1, KA1, CH2, CA2, LW2, KA2, CH3, CA3, KA3, CH4,
    /// [CA4: C-130], CH5, FinalApproach, StopPlane, TaxiCL (to park), ParkInHangar.
    fn legs(&self, c130: bool, cfg: &Config) -> Vec<Leg> {
        let k = self.k;
        let ae = cfg.allowed_err;
        let d = |x: f32| x.to_radians();
        let tol = |i: usize| d(if c130 { [2.0, 1.0, 0.5, 0.5, 0.5][i] } else { [1.0, 0.5, 0.5, 0.5, 0.5][i] });
        let lim80 = if c130 { d(40.0) } else { d(80.0) };
        let (lim60, lim20) = if c130 { (lim80, lim80) } else { (d(60.0), d(20.0)) };
        let s1 = if c130 { 113.239 } else { 128.681 };
        let mut v = vec![
            Leg::Ch(0, tol(0), lim80, None),
            if c130 { Leg::CaOr(0, k * ae[0] as f64) } else { Leg::Ca(0, 50.0) },
            Leg::Lw(s1),
            Leg::Ka(0, s1, k * ae[0] as f64),
            Leg::Ch(1, tol(1), lim80, None),
            Leg::Ca(1, 50.0),
            Leg::Lw(102.944),
            Leg::Ka(1, 102.944, k * ae[1] as f64),
            Leg::Ch(2, tol(2), lim60, None),
            Leg::Ca(2, 250.0),
            Leg::Ka(2, 87.503, 1852.0),
            Leg::Ch(3, tol(3), lim60, Some(72.0611)),
        ];
        if c130 {
            v.push(Leg::Ca(3, 50.0));
        }
        v.extend([Leg::Ch(4, tol(4), lim20, Some(72.0611)), Leg::Fa(k * ae[4] as f64), Leg::Stop]);
        if !self.player {
            v.extend([Leg::Taxi, Leg::Park]);
        }
        v
    }

    /// One tick of the current child; `Next` (`5d43e0`) at the step boundaries.
    fn step(&mut self, l: &mut Laws, ap: &Autopilot, period: &mut f64, vmin1: f32) -> Leaf {
        let c130 = l.v.type_code == C130;
        let legs = self.legs(c130, &ap.cfg);
        let Some(leg) = legs.get(self.step).copied() else {
            *period = 0.5;
            l.throttle(0.0);
            return Leaf::Done;
        };
        let pos = l.v.pos;
        let pt = self.pts;
        let r = match leg {
            Leg::Ch(i, tol, lim, vt) => {
                *period = 0.2;
                let prev = if i > 0 { Some(pt[i - 1]) } else { None };
                let acu = self.acu.get_or_insert_with(|| Acu::new(l.v.speed, vt));
                acu.step(l, pt[i], prev, tol, lim)
            }
            Leg::Ca(i, r) => {
                if (pos[2] - pt[i][2]).abs() < r {
                    Leaf::Done
                } else {
                    change_alt(l, pt[i][2]);
                    Leaf::Run
                }
            }
            Leg::CaOr(i, r) => {
                if dist2(pos, pt[i][0], pt[i][1]) < r || (pos[2] - pt[i][2]).abs() < 250.0 {
                    Leaf::Done
                } else {
                    change_alt(l, pt[i][2]);
                    Leaf::Run
                }
            }
            Leg::Lw(speed) => level_wings_accel(l, &mut self.lw_pitch, speed, vmin1),
            Leg::Ka(i, speed, r) => self.ka(l, i, speed, r),
            Leg::Fa(r) => {
                *period = 0.1;
                if dist2(pos, pt[4][0], pt[4][1]) < r {
                    l.out.rudder = Some(0.0);
                    Leaf::Done
                } else {
                    self.final_approach(l, vmin1);
                    Leaf::Run
                }
            }
            Leg::Stop => {
                *period = 0.2;
                self.stop_plane(l)
            }
            Leg::Taxi => {
                *period = 0.2;
                let t = self.taxi.get_or_insert(Taxi {
                    park: true,
                    path: Vec::new(),
                    i: 0,
                    turning: false,
                    waiting: false,
                    start: 0.0,
                    at_lineup: false,
                    first: true,
                    hangar: None,
                });
                t.step(l, ap, true)
            }
            Leg::Park => {
                *period = 0.2;
                self.park_step(l, ap)
            }
        };
        if r == Leaf::Done {
            if !matches!(leg, Leg::Ch(..)) {
                l.stick(0.0, 0.0);
            }
            self.acu = None;
            self.step += 1;
            match self.step {
                7 => {
                    l.flaps(true);
                    l.gear(true);
                }
                13 => {
                    l.brakes(true);
                    l.watch = false;
                }
                _ => {}
            }
        }
        Leaf::Run
    }

    fn ka(&mut self, l: &mut Laws, i: usize, speed: f32, r: f64) -> Leaf {
        if dist2(l.v.pos, self.pts[i][0], self.pts[i][1]) < r {
            return Leaf::Done;
        }
        keep_attitude(l, self.pts[i], Some(speed));
        Leaf::Run
    }

    /// FinalApproachCL `5d4c50`: the 6° glide path to the lineup.
    fn final_approach(&mut self, l: &mut Laws, vmin1: f32) {
        let v = l.v;
        let p5 = self.pts[4];
        let d = [v.pos[0] - p5[0], v.pos[1] - p5[1], v.pos[2] - p5[2]];
        let (s, c) = ((self.rn as f64).sin(), (self.rn as f64).cos());
        let (sg, cg) = (6f64.to_radians().sin(), 6f64.to_radians().cos());
        let fwd = [s * cg, c * cg, -sg];
        let up = [s * sg, c * sg, cg];
        let right = [c, -s, 0.0];
        let dot = |a: [f64; 3]| (a[0] * d[0] + a[1] * d[1] + a[2] * d[2]) as f32;
        let (cross, along, above) = (dot(right), dot(fwd), dot(up));
        let vt = (vmin1 + 10.2944).max(72.0611);
        let thr = l.thr(vt).min(0.5);
        let e = wrap(self.rn - v.att.heading);
        let bank = (-0.001_396_3 * cross + e * l.c.change_head_k / 3.0
            - l.c.change_head_beta * v.rates[2])
            .clamp(-deg80(), deg80());
        let kz = if above < 0.0 {
            0.03
        } else if v.type_code == C130 {
            0.05
        } else {
            0.3
        };
        let pitch_deg =
            -kz * above - 0.5 * v.rates[0].to_degrees() - if along < -1000.0 { 6.0 } else { 4.0 };
        let y = l.pitch(pitch_deg.to_radians());
        let x = l.roll(bank);
        l.stick(y, x);
        l.throttle(thr);
    }

    /// StopPlaneCL `5d44d0`.
    fn stop_plane(&mut self, l: &mut Laws) -> Leaf {
        let v = l.v;
        if v.speed <= if self.player { 1.0295 } else { 25.736 } {
            l.out.rudder = Some(0.0);
            if self.player {
                l.out.ap_key = true;
            } else {
                self.landed = true;
            }
            return Leaf::Done;
        }
        let rolling = v.att.pitch.abs() <= 0.2f32.to_radians()
            && (v.pos[2] as f32) < v.ground_height + v.gear_clearance.abs() + 5.0;
        if rolling {
            l.out.rudder = Some(0.0);
            l.throttle(0.0);
            let e = wrap(self.rn - v.att.heading);
            if e.abs() > 0.1f32.to_radians() {
                let y = l.pitch_b(0.0);
                let x = l.roll((e - v.rates[2]).clamp(-deg80(), deg80()));
                l.stick(y, x);
            }
        } else {
            l.throttle(0.0);
            let y = l.pitch(0.0);
            let x = l.roll(0.0);
            l.stick(y, x);
        }
        Leaf::Run
    }

    /// ParkInHangarCL `5d66b0`: creep at 2 kt to the hangar; stop, brakes, engine off.
    fn park_step(&mut self, l: &mut Laws, ap: &Autopilot) -> Leaf {
        let v = l.v;
        if self.park.is_none() {
            let base = Airbase::nearest(
                &ap.bases,
                [v.pos[0] as f32, v.pos[1] as f32, v.pos[2] as f32],
            );
            let t = base.and_then(|b| {
                b.hangar_near(v.pos[0] as f32, v.pos[1] as f32)
                    .map(|h| b.hangars[h])
            });
            let Some(t) = t else { return Leaf::Done };
            self.park = Some((t.x as f64, t.y as f64, t.hdg, 1000.0));
        }
        let (x, y, hdg, last) = self.park.unwrap();
        let d = dist2(v.pos, x, y);
        l.throttle(l.thr(1.0294));
        if d > last {
            l.throttle(0.0);
            l.brakes(true);
            l.out.rudder = Some(0.0);
            l.stick(0.0, 0.0);
            l.out.replace = Some((v.pos[0], v.pos[1], hdg));
            l.out.engine_off = true;
            return Leaf::Done;
        }
        self.park = Some((x, y, hdg, d));
        Leaf::Run
    }
}

fn deg80() -> f32 {
    80f32.to_radians()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn landing_points_are_f32_like_the_original() {
        // Runway 270 at Ramat David: in f32 the cos θ residue (~1e-8) vanishes, so the downwind, base and final
        // legs are exactly axis-parallel (the tangent search's x == x / y == y branches).
        let b = Airbase {
            lineup: [356483.0, 602383.0, 63.0],
            runway_deg: 270.0,
            ..Default::default()
        };
        let l = Landing::new(&[b], [0.0; 2], [351083.0, 602383.0, 1500.0], 0, true).unwrap();
        let p = l.pts;
        assert_eq!((p[0][1], p[1][1]), (596821.0, 596821.0), "downwind P1 → P2");
        assert_eq!((p[1][0], p[2][0]), (363899.0, 363899.0), "base P2 → P3");
        assert_eq!(
            (p[2][1], p[3][1], p[4][1]),
            (602383.0, 602383.0, 602383.0),
            "final P3 → P4 → P5"
        );
        assert_eq!(p[3][0], 360191.0);
    }

    #[test]
    fn landing_points_round_in_world_coordinates() {
        // The Godot host shifts the bases by the terrain origin; the f32 rounding must still happen in world
        // coordinates, else the small scene coordinates keep the ~1e-8 residue and the legs are not axis-parallel.
        let o = [356400.25, 602350.5];
        let b = Airbase {
            lineup: [356483.0 - o[0] as f32, 602383.0 - o[1] as f32, 63.0],
            runway_deg: 270.0,
            ..Default::default()
        };
        let l = Landing::new(&[b], o, [351083.0 - o[0], 602383.0 - o[1], 1500.0], 0, true).unwrap();
        let p = l.pts;
        assert_eq!(p[0][1], p[1][1]);
        assert_eq!(p[1][0], p[2][0]);
        assert_eq!((p[2][1], p[3][1]), (p[4][1], p[4][1]));
        assert_eq!(p[4][1] + o[1], 602383.0);
    }
}
