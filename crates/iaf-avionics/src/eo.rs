//! The player's EO sensor (docs/mfd.md "FLIR (6), TV (5)"): the controller's EO mode (ctl+0x7f4: 1 TV weapon, 2 FLIR
//! pod), the camera of view slot 1 (type 0xb: `FUN_005817a0` start, `FUN_005805e0` angles, `FUN_00581b30` slew,
//! `FUN_005820e0` / `FUN_00582160` zoom), WIDE / SPOT (the FLIR object's +0x14), the laser flag (ctl+0x960) and the
//! FLIR / TV page values (`FUN_0045d7f0` / `FUN_004604c0`).
//!
//! World frame X east, Y north, Z up, metres, radians, sim seconds; headings clockwise from north. A base is the jet's
//! (heading, pitch).

use crate::vec3::Vec3;
use std::f64::consts::{PI, TAU};


/// The start elevation (0xbdb2b8c2 = −5°).
pub const EL0: f64 = -0.08726646;
/// Zoom 1, 2, 4, 8 (`FUN_005820e0` while < 8, `FUN_00582160` while > 1).
const ZOOM_MAX: f64 = 8.0;
/// The FLIR / TV page scales (0x601354 = 4/π: ±45° = ±56 px about −5°; 0x601524 = 6/π: ±30°).
const FLIR_K: f64 = 1.2732395;
const TV_K: f64 = 1.9098593;
/// 1/1853 NM per m (0x60c4a0); "XXX.X" from 20 NM (0x60c4a8).
const NM: f64 = 1853.0;
/// The slew keys' rest value (DAT_00843b84 / 88).
const KEYS_REST: (i64, i64) = (6, 6);

/// The controller's EO mode.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Mode {
    #[default]
    None = 0,
    Tv = 1,
    Flir = 2,
}

/// The gimbal limits by the store's class (`FUN_005817a0`): az ±, el max / min.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Limits {
    pub az: f64,
    pub el_max: f64,
    pub el_min: f64,
}

/// Class 0x1a (660, the pod): az ±45°, el +30° / −80°.
pub const POD_LIMITS: Limits = Limits { az: PI / 4.0, el_max: PI / 6.0, el_min: -1.3962634015954636 };
/// The weapons: az ±30°, el +15° / −45°.
pub const WEAPON_LIMITS: Limits = Limits { az: PI / 6.0, el_max: PI / 12.0, el_min: -PI / 4.0 };

/// What the camera looks at (+0x50: 1 free from the slew rates, 2 tracking; +0x1e0 point, +0x60 unit).
#[derive(Clone, Debug, PartialEq)]
pub enum Aim {
    Free,
    Point(Vec3),
    Unit(String),
}

#[derive(Clone, Debug)]
pub struct Eo {
    pub mode: Mode,
    /// Slot 1 holds the EO camera once one was started; it stays (zoom keys still act on it).
    camera: bool,
    limits: Limits,
    aim: Aim,
    /// +0x1e0: the tracked point (a tracked unit's last position).
    point: Vec3,
    /// +0x1ec / +0x1f0.
    az: f64,
    el: f64,
    /// +0x1f4 az, +0x1f8 el (rad/s).
    rate: (f64, f64),
    /// +0x1d8.
    t0: f64,
    /// +0xc.
    zoom: f64,
    /// +0x208 / +0x220: the base frozen when a slew starts from tracking; None = the jet's live one.
    frozen: Option<(f64, f64)>,
    /// The FLIR object's +0x14 (false = WIDE).
    spot: bool,
    /// ctl+0x960.
    pub laser: bool,
    /// weapons.ibx _debugParam008 (0.09): °/s per key unit (±100) at zoom 1.
    pub pan_k: f64,
    keys: (i64, i64),
}

impl Default for Eo {
    fn default() -> Self {
        Eo {
            mode: Mode::None,
            camera: false,
            limits: POD_LIMITS,
            aim: Aim::Free,
            point: Vec3::ZERO,
            az: 0.0,
            el: EL0,
            rate: (0.0, 0.0),
            t0: 0.0,
            zoom: 1.0,
            frozen: None,
            spot: false,
            laser: false,
            pan_k: 0.09,
            keys: KEYS_REST,
        }
    }
}

impl Eo {
    pub fn camera(&self) -> bool {
        self.camera
    }
    pub fn limits(&self) -> Limits {
        self.limits
    }
    pub fn aim(&self) -> &Aim {
        &self.aim
    }
    pub fn point(&self) -> Vec3 {
        self.point
    }
    pub fn zoom(&self) -> f64 {
        self.zoom
    }
    pub fn spot(&self) -> bool {
        self.spot
    }
    /// The base frozen by a slew from tracking.
    pub fn frozen(&self) -> Option<(f64, f64)> {
        self.frozen
    }
    /// The slew rates (az, el) in rad/s.
    pub fn rate(&self) -> (f64, f64) {
        self.rate
    }

    fn set_aim(&mut self, aim: Aim) {
        if let Aim::Point(p) = aim {
            self.point = p;
        }
        self.aim = aim;
    }

    /// `FUN_00450280` → `FUN_005817a0` with a store: EO mode `mode`, limits by the store's class (`pod` = class 0x1a),
    /// the aim. The zoom starts at 1 only when slot 1 had no EO camera.
    pub fn start(&mut self, mode: Mode, pod: bool, aim: Aim, t: f64) {
        self.mode = mode;
        self.limits = if pod { POD_LIMITS } else { WEAPON_LIMITS };
        self.az = 0.0;
        self.el = EL0;
        self.rate = (0.0, 0.0);
        self.t0 = t;
        self.frozen = None;
        self.set_aim(aim);
        if !self.camera {
            self.zoom = 1.0;
            self.camera = true;
        }
        self.keys = KEYS_REST;
    }

    /// `FUN_0044e6e0`: leaving the EO master modes.
    pub fn stop(&mut self) {
        self.mode = Mode::None;
    }

    /// `FUN_005805e0`: the camera's (az, el) at `t` against `base` from `eye`; tracking stores them (unclamped) as the
    /// new az / el; then clamped to the limits.
    pub fn angles(&mut self, t: f64, base: (f64, f64), eye: Vec3, unit_pos: &dyn Fn(&str) -> Option<Vec3>) -> (f64, f64) {
        let b = self.frozen.unwrap_or(base);
        let wrap = |a: f64| if a > PI { a - TAU } else { a };
        let (a, e) = match &self.aim {
            Aim::Free => (self.az + self.rate.0 * (t - self.t0), self.el + self.rate.1 * (t - self.t0)),
            aim => {
                if let Aim::Unit(k) = aim
                    && let Some(p) = unit_pos(k)
                {
                    self.point = p;
                }
                let d = self.point - eye;
                let a = wrap(d.x.atan2(d.y) - b.0);
                let e = wrap(d.z.atan2(d.x.hypot(d.y)) - b.1);
                self.az = a;
                self.el = e;
                (a, e)
            }
        };
        let l = self.limits;
        (a.clamp(-l.az, l.az), e.min(l.el_max).max(l.el_min))
    }

    /// The camera's line of sight (world unit vector) for angles `ae` on `base`: heading + az, pitch + el, roll 0.
    pub fn los(&self, ae: (f64, f64), base: (f64, f64)) -> Vec3 {
        let b = self.frozen.unwrap_or(base);
        let (h, p) = (b.0 + ae.0, b.1 + ae.1);
        Vec3::new(h.sin() * p.cos(), h.cos() * p.cos(), p.sin())
    }

    /// Event 0x8a(x, y) (Ctrl+arrows, ±100; release 0): with the keys released and (a launched TV weapon or FLIR) the
    /// camera locks on `centre`; else `FUN_00581b30`: a changed (x, y) restarts the slew from the current angles (from
    /// tracking: free, the base frozen) at 0.09·x / zoom, 0.09·y / zoom °/s.
    #[allow(clippy::too_many_arguments)] // the original's event arguments and the world
    pub fn pan(&mut self, keys: (i64, i64), t: f64, base: (f64, f64), eye: Vec3, centre: Aim, launched: bool, unit_pos: &dyn Fn(&str) -> Option<Vec3>) {
        if self.mode == Mode::None || !self.camera {
            return;
        }
        if keys.0.abs() < 10 && keys.1.abs() < 10 && (launched || self.mode == Mode::Flir) {
            self.frozen = None;
            self.set_aim(centre);
            self.keys = KEYS_REST;
            return;
        }
        if keys == self.keys {
            return;
        }
        self.keys = keys;
        if self.aim == Aim::Free {
            (self.az, self.el) = self.angles(t, base, eye, unit_pos);
        } else {
            self.angles(t, base, eye, unit_pos); // the stored az / el are the current ones
            self.aim = Aim::Free;
            self.frozen = Some(base);
        }
        self.t0 = t;
        let k = self.pan_k.to_radians() / self.zoom;
        self.rate = (k * keys.0 as f64, k * keys.1 as f64);
    }

    /// Events 0x14 / 0x15 on the EO camera: ×2 while < 8 / ×0.5 while > 1, the slew rates the other way; az0 / t0 stay
    /// (original quirk: zooming during a slew jumps the picture).
    pub fn zoom_step(&mut self, zoom_in: bool) {
        if !self.camera {
            return;
        }
        if zoom_in && self.zoom < ZOOM_MAX {
            self.zoom *= 2.0;
            self.rate = (self.rate.0 * 0.5, self.rate.1 * 0.5);
        } else if !zoom_in && self.zoom > 1.0 {
            self.zoom *= 0.5;
            self.rate = (self.rate.0 * 2.0, self.rate.1 * 2.0);
        }
    }

    /// Event 0x20 (FLIR OSB 5): WIDE ↔ SPOT and three zoom steps in (to SPOT) or out (to WIDE).
    pub fn wide_spot(&mut self) {
        let was = self.spot;
        self.spot = !self.spot;
        for _ in 0..3 {
            self.zoom_step(!was);
        }
    }

    /// Event 0x6a (L, FLIR OSB 3): only with the pod fitted (ctl+0x93c).
    pub fn laser_key(&mut self, pod_fitted: bool) {
        if pod_fitted {
            self.laser = !self.laser;
        }
    }

    /// The page zoom 1..10.
    fn page_zoom(&self) -> i64 {
        (self.zoom as i64).clamp(1, 10)
    }

    /// The FLIR page (`FUN_0045d7f0` → state+0x5e0..0x600): zoom, gimbal u / v, the range text.
    pub fn flir_page(&self, ae: (f64, f64), range_m: f64) -> (i64, f64, f64, String) {
        let nm = range_m / NM;
        let range = if nm >= 20.0 { "XXX.X".to_owned() } else { format!("{nm:3.1}") };
        (self.page_zoom(), ae.0 * FLIR_K, (ae.1 - EL0) * FLIR_K, range)
    }

    /// The TV page (`FUN_004604c0` → state+0x5e0..0x5f4): zoom, seeker u / v.
    pub fn tv_page(&self, ae: (f64, f64)) -> (i64, f64, f64) {
        (self.page_zoom(), ae.0 * TV_K, ae.1 * TV_K)
    }
}

/// The full-screen weapon MFD (key Z, docs/mfd.md §3) opens and stays open while an EO mode is on with a picture: the
/// TV with a status (RDY / TRA / TER, `FUN_00460940`), the FLIR always (`FUN_0044a240` case 0x1f, `FUN_00448b20`).
pub fn full_screen_ok(mode: Mode, tv_status: i64) -> bool {
    match mode {
        Mode::None => false,
        Mode::Tv => tv_status != 0,
        Mode::Flir => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NONE: &dyn Fn(&str) -> Option<Vec3> = &|_| None;

    #[test]
    fn full_screen() {
        assert!(!full_screen_ok(Mode::None, 1) && !full_screen_ok(Mode::Tv, 0));
        assert!(full_screen_ok(Mode::Tv, 3) && full_screen_ok(Mode::Flir, 0));
    }

    #[test]
    fn tracks_a_point_within_the_limits() {
        let mut eo = Eo::default();
        eo.start(Mode::Flir, true, Aim::Point(Vec3::new(1000.0, 1000.0, 0.0)), 0.0);
        let (a, e) = eo.angles(0.0, (0.0, 0.0), Vec3::new(0.0, 0.0, 1000.0), NONE);
        assert!((a - PI / 4.0).abs() < 1e-9 && (e + (1000.0 / 2f64.sqrt() / 1000.0).atan()).abs() < 1e-9);
        let far_right = Aim::Point(Vec3::new(1000.0, 0.0, 1000.0));
        eo.start(Mode::Tv, false, far_right, 0.0);
        assert_eq!(eo.angles(0.0, (0.0, 0.0), Vec3::new(0.0, 0.0, 1000.0), NONE).0, WEAPON_LIMITS.az);
    }

    #[test]
    fn slew_freezes_the_base_and_zoom_halves_the_rate() {
        let mut eo = Eo::default();
        eo.start(Mode::Tv, false, Aim::Point(Vec3::new(0.0, 1000.0, 0.0)), 0.0);
        eo.pan((100, 0), 1.0, (0.0, 0.0), Vec3::ZERO, Aim::Free, false, NONE);
        assert_eq!(*eo.aim(), Aim::Free);
        let (a, _) = eo.angles(2.0, (1.0, 0.0), Vec3::ZERO, NONE);
        assert!((a - 9f64.to_radians()).abs() < 1e-9, "1 s at 9°/s, base frozen: {a}");
        eo.zoom_step(true);
        assert_eq!(eo.zoom(), 2.0);
        assert_eq!(eo.flir_page((0.0, EL0), 40000.0).3, "XXX.X");
        assert_eq!(eo.flir_page((0.0, EL0), 18530.0).3, "10.0");
    }
}
