//! The missile sights of the HUD: the IR seeker of the SRM mode (docs/weapons.md §5.2; IR mode object
//! `FUN_00461210`, update `FUN_00461290`, search `FUN_00461680`, can-track `FUN_00461d10`, field of view
//! `FUN_00461f10`, per-generation limits `FUN_00462460`, tones `FUN_00461bf0`) and the launch circle of the radar
//! missiles / HARM (HUD modes 2 / 8: `FUN_00460ea0`, `FUN_00460a90` on the base `FUN_00462ab0`; docs/weapons.md §11).
//!
//! World frame X east, Y north, Z up. Screen offsets are original 640x480 pixels from the HUD centre, as angles at
//! 12 px/deg from the camera ray through it (`Eye::sight`; the nose without one). The helmet (free look / padlock
//! views, docs/weapons.md §5.4) looks along `Eye::helmet_axis`.

use crate::missile::Dlz;
use crate::vec3::Vec3;

/// HUD pixels per degree (v1.1 HUD scale).
pub const PX_PER_DEG: f64 = 12.0;

/// A view basis.
#[derive(Clone, Copy, Debug, Default)]
pub struct Frame {
    pub fwd: Vec3,
    pub up: Vec3,
    pub right: Vec3,
}

/// A screen offset from the HUD centre in original pixels (x right, y down).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Px {
    pub x: f64,
    pub y: f64,
}

impl Px {
    pub fn length_squared(self) -> f64 {
        self.x * self.x + self.y * self.y
    }
}

/// The own jet as the sights see it.
#[derive(Clone, Copy, Debug, Default)]
pub struct Eye {
    pub pos: Vec3,
    pub nose: Frame,
    /// The heading (rad, atan2(east, north)).
    pub yaw: f64,
    /// The camera ray through the HUD centre, in the cockpit views.
    pub sight: Option<Frame>,
    /// The camera axis in the free-look / padlock views.
    pub helmet_axis: Option<Vec3>,
}

impl Eye {
    /// The screen offset of a world point; None when behind.
    pub fn screen_offset(&self, p: Vec3) -> Option<Px> {
        let b = self.sight.unwrap_or(self.nose);
        let d = p - self.pos;
        let f = d.dot(b.fwd);
        (f > 0.0).then(|| Px {
            x: d.dot(b.right).atan2(f).to_degrees() * PX_PER_DEG,
            y: -d.dot(b.up).atan2(f).to_degrees() * PX_PER_DEG,
        })
    }
}

/// A unit the seeker can see.
#[derive(Clone, Debug, Default)]
pub struct Heat {
    pub key: String,
    pub pos: Vec3,
    pub vel: Vec3,
    pub afterburner: bool,
}

/// The radar's lock as the seeker reads it (`FUN_00461680` / `FUN_004625f0`).
#[derive(Clone, Debug, PartialEq)]
pub struct RadarLock {
    pub key: String,
    pub air_to_air: bool,
}

/// The seeker's tone (`FUN_00461bf0`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Tone {
    #[default]
    Off,
    Seek,
    Lock,
}

// --- the IR seeker ------------------------------------------------------------------------------------------

/// Per missile generation (bdb 0x762): seeker cone (0x6016c0.., the radar- or helmet-slaved gimbal limit, degrees)
/// and lock range (NM, 0x82f6c4).
fn generation(id: i64) -> Option<(f64, f64)> {
    match id {
        1 => Some((15.0, 6.0)),
        2 => Some((21.0, 8.0)),
        3 => Some((35.0, 10.0)),
        4 => Some((70.0, 15.0)),
        _ => None,
    }
}
const NM: f64 = 1854.0; // 0x6016a0
/// Narrow seeker field of view (cos 6°, 0x6016c8).
const FOV_DEG: f64 = 6.0;
/// The circle around the HUD centre for the search and the launch (vfunc +0x44: 60·100 px²).
const CIRCLE_PX2: f64 = 6000.0;
/// Search at most every 0.5 s; the seeker part of the update every 0.05 s.
const SEARCH_PERIOD: f64 = 0.5;
const UPDATE_PERIOD: f64 = 0.05;
/// Limited heat (580): azimuth from the own heading at most 60° (0x6016e8).
const LIMITED_AZ_DEG: f64 = 60.0;
/// Symbol easing: pos = 0.3·goal + 0.7·pos (0x601680 / 0x601684); snaps within 5 px.
const EASE: f64 = 0.3;
const SNAP_PX: f64 = 5.0;

#[derive(Clone, Debug)]
pub struct Seeker {
    cone_cos: f64,
    lock_range: f64,
    /// Weapon data Real: a rear-aspect seeker sees only a target moving away from the launcher
    /// (docs/real-weapons.md).
    pub rear_only: bool,
    /// The radar's lock, set by the host each frame.
    pub radar: Option<RadarLock>,
    /// this+0x14.
    target: Option<String>,
    /// 0x82f6ec.
    lock: bool,
    /// The seeker symbol (diamond).
    symbol: Px,
    tone: Tone,
    next_search: f64,
    next_update: f64,
}

impl Default for Seeker {
    /// The static default: generation 4.
    fn default() -> Self {
        let (cone, nm) = generation(4).unwrap();
        Seeker {
            cone_cos: cone.to_radians().cos(),
            lock_range: nm * NM,
            rear_only: false,
            radar: None,
            target: None,
            lock: false,
            symbol: Px::default(),
            tone: Tone::Off,
            next_search: f64::NEG_INFINITY,
            next_update: f64::NEG_INFINITY,
        }
    }
}

impl Seeker {
    /// The missile generation's cone and range; generation 0 / other keeps the previous values.
    pub fn set_generation(&mut self, generation: i64) {
        if let Some((cone, nm)) = self::generation(generation) {
            self.cone_cos = cone.to_radians().cos();
            self.lock_range = nm * NM;
        }
    }

    /// The selected missile: its generation, then the Real overrides (cone, rear aspect).
    pub fn set_weapon(&mut self, generation: i64, real_cone_deg: Option<f64>, rear_only: bool) {
        self.set_generation(generation);
        if let Some(c) = real_cone_deg {
            self.cone_cos = c.to_radians().cos();
        }
        self.rear_only = rear_only;
    }

    pub fn lock_range(&self) -> f64 {
        self.lock_range
    }
    pub fn target(&self) -> Option<&str> {
        self.target.as_deref()
    }
    pub fn locked(&self) -> bool {
        self.lock
    }
    pub fn symbol(&self) -> Px {
        self.symbol
    }
    pub fn tone(&self) -> Tone {
        self.tone
    }

    fn radar_aa(&self) -> Option<&str> {
        self.radar.as_ref().filter(|r| r.air_to_air).map(|r| r.key.as_str())
    }

    /// `FUN_00461d10`: limited heat (580) only within ±60° of the own heading (bearing, not aspect); range ≤ R;
    /// beyond R/2 only a target with its afterburner on.
    pub fn can_track(&self, eye: &Eye, u: &Heat, limited: bool) -> bool {
        let d = u.pos - eye.pos;
        if limited {
            let az = (d.x.atan2(d.y) - eye.yaw + std::f64::consts::PI).rem_euclid(std::f64::consts::TAU) - std::f64::consts::PI;
            if az.abs() > LIMITED_AZ_DEG.to_radians() {
                return false;
            }
        }
        let r = d.length();
        if (self.rear_only && u.vel.dot(d) <= 0.0) || r > self.lock_range {
            return false;
        }
        r <= self.lock_range / 2.0 || u.afterburner
    }

    /// `FUN_00461f10`. With an A-A radar lock (`FUN_004625f0`): the target within the generation's cone of the nose.
    /// Else with the helmet: its axis within the cone of the nose and the target within 6° of it. Else within 6° of
    /// the nose.
    pub fn in_view(&self, eye: &Eye, u: &Heat) -> bool {
        let Some(d) = (u.pos - eye.pos).try_normalize() else { return false };
        let fov = FOV_DEG.to_radians().cos();
        if self.radar_aa().is_some() {
            return eye.nose.fwd.dot(d) >= self.cone_cos;
        }
        match eye.helmet_axis {
            Some(a) => eye.nose.fwd.dot(a) >= self.cone_cos && a.dot(d) >= fov,
            None => eye.nose.fwd.dot(d) >= fov,
        }
    }

    /// The seeker looks where the radar's A-A lock is.
    pub fn slaved(&self) -> bool {
        self.radar_aa().is_some_and(|k| self.target.as_deref() == Some(k))
    }

    /// `FUN_00461680`: a radar lock clears the seeker's own target, and in A-A it takes the locked unit at once (no
    /// 0.5 s gate, no circle). Else it keeps a target that still passes can-track, or at most every 0.5 s takes the
    /// unit nearest the HUD centre inside the 6000 px² circle that passes can-track (no side test).
    pub fn search<'a>(&mut self, now: f64, eye: &Eye, units: &'a [Heat], limited: bool) -> Option<&'a Heat> {
        if let Some(r) = &self.radar {
            self.target = r.air_to_air.then(|| r.key.clone());
            if r.air_to_air {
                return find(units, self.target.as_deref());
            }
        }
        if let Some(cur) = find(units, self.target.as_deref()) {
            if self.can_track(eye, cur, limited) {
                return Some(cur);
            }
            self.target = None;
        }
        if now < self.next_search {
            return None;
        }
        self.next_search = now + SEARCH_PERIOD;
        let best = units
            .iter()
            .filter_map(|u| Some((eye.screen_offset(u.pos)?.length_squared(), u)))
            .filter(|&(d2, u)| d2 < CIRCLE_PX2 && self.can_track(eye, u, limited))
            .min_by(|a, b| a.0.total_cmp(&b.0))
            .map(|(_, u)| u);
        self.target = best.map(|u| u.key.clone());
        best
    }

    /// One frame of the IR mode (`FUN_00461290`): the seeker part every 0.05 s. `have_rounds` = the selected store
    /// has rounds left.
    pub fn update(&mut self, now: f64, eye: &Eye, units: &[Heat], limited: bool, have_rounds: bool) {
        if now < self.next_update {
            return;
        }
        self.next_update = now + UPDATE_PERIOD;
        let Some(t) = self.search(now, eye, units, limited).filter(|t| self.in_view(eye, t)) else {
            self.set_tone(false, have_rounds);
            self.symbol = Px { x: self.symbol.x * (1.0 - EASE), y: self.symbol.y * (1.0 - EASE) };
            return;
        };
        self.set_tone(self.can_track(eye, t, limited), have_rounds);
        if let Some(goal) = eye.screen_offset(t.pos) {
            let s = self.symbol;
            self.symbol = Px { x: EASE * goal.x + (1.0 - EASE) * s.x, y: EASE * goal.y + (1.0 - EASE) * s.y };
            if (self.symbol.x - goal.x).abs() < SNAP_PX && (self.symbol.y - goal.y).abs() < SNAP_PX {
                self.symbol = goal;
            }
        }
    }

    /// The target a launch takes (`FUN_00462ad0`): the seeker's target when inside the HUD-centre circle.
    pub fn target_in_circle<'a>(&self, eye: &Eye, units: &'a [Heat]) -> Option<&'a Heat> {
        find(units, self.target.as_deref())
            .filter(|t| eye.screen_offset(t.pos).is_some_and(|o| o.length_squared() < CIRCLE_PX2))
    }

    /// `FUN_00461b00` on entering IR with an empty station: the seek tone starts; the next update stops it.
    pub fn start_empty_chirp(&mut self) {
        self.tone = Tone::Seek;
    }

    /// `FUN_00461bf0`: no rounds → both tones off and no lock; else the lock or the seek tone.
    fn set_tone(&mut self, on: bool, have_rounds: bool) {
        self.lock = on && have_rounds;
        self.tone = match (have_rounds, on) {
            (false, _) => Tone::Off,
            (true, true) => Tone::Lock,
            (true, false) => Tone::Seek,
        };
    }

    /// Leaving the IR mode (`FUN_00461bb0`): both tones stop.
    pub fn exit(&mut self) {
        self.tone = Tone::Off;
        self.lock = false;
        self.target = None;
        self.symbol = Px::default();
    }
}

fn find<'a>(units: &'a [Heat], key: Option<&str>) -> Option<&'a Heat> {
    let key = key?;
    units.iter().find(|u| u.key == key)
}

// --- the MRM / HARM launch circle ---------------------------------------------------------------------------

/// The circle's base size (vfunc +0x40 `FUN_00463210`: 0x601798 = 5) and its smallest share (0x6017ac = 1/3); the
/// HUD draws it ×12 px (0x6017b4).
pub const R0: f64 = 5.0;
const R_MIN_K: f64 = 1.0 / 3.0;
const CIRCLE_PX: f64 = 12.0;
/// Launch circle around the HUD centre (vfunc +0x44 / +0x48: 0x6017a0² / 0x60179c²): 60 px without a lock, 240 px
/// with one.
const FREE_PX2: f64 = 60.0 * 60.0;
const LOCKED_PX2: f64 = 240.0 * 240.0;
/// The predicted point leads the target by √(dist² · 2.5e-7) s = dist / 2000 (0x6017bc).
const LEAD_K: f64 = 2.5e-7;

/// `FUN_00462c10`: the circle size from the DLZ and the target's distance: R0 without a lock or DLZ; at or inside
/// min, or at or beyond max, R0 / 3; between, R0 · (1 − (dist − min) / (max − min)), at least R0 / 3.
pub fn circle(locked: bool, dlz: Option<Dlz>, dist: f64) -> f64 {
    match dlz.filter(|_| locked) {
        None => R0,
        Some(z) if dist <= z.min || dist >= z.max => R0 * R_MIN_K,
        Some(z) => (R0 * (1.0 - (dist - z.min) / (z.max - z.min))).max(R0 * R_MIN_K),
    }
}

/// `FUN_00462f70`: the target's position led by dist / 2000 s at its velocity.
pub fn predicted(pos: Vec3, vel: Vec3, dist: f64) -> Vec3 {
    pos + vel * (dist * dist * LEAD_K).sqrt()
}

/// `FUN_00462ad0` (vfunc +0x30): the target's screen point within 240 px of the HUD centre with a lock, else 60 px.
pub fn target_in_circle(off: Option<Px>, locked: bool) -> bool {
    off.is_some_and(|o| o.length_squared() <= if locked { LOCKED_PX2 } else { FREE_PX2 })
}

/// `FUN_00462e80` (vfunc +0x34) with a lock: the predicted point's screen offset within the circle (r · 12 px; in
/// the HUD-only view within √2 of it: the original compares d² with 2·R²), and q (vfunc +0x38): 1 inside, else R / d.
pub fn in_circle(off: Option<Px>, r: f64, hud_only: bool) -> (bool, f64) {
    let Some(off) = off else { return (false, 0.0) };
    let r2 = (r * CIRCLE_PX).powi(2);
    let d2 = off.length_squared();
    let inside = d2 <= if hud_only { 2.0 * r2 } else { r2 };
    (inside, if inside { 1.0 } else { r2.sqrt() / d2.sqrt() })
}

#[cfg(test)]
mod tests {
    use super::*;

    const NORTH: Frame = Frame { fwd: Vec3::NORTH, up: Vec3::UP, right: Vec3::new(1.0, 0.0, 0.0) };

    fn eye() -> Eye {
        Eye { nose: NORTH, ..Eye::default() }
    }

    fn heat(key: &str, pos: Vec3, vel: Vec3) -> Heat {
        Heat { key: key.into(), pos, vel, afterburner: false }
    }

    #[test]
    fn rear_aspect_and_range() {
        let mut s = Seeker::default();
        s.set_weapon(4, None, true);
        let ahead = Vec3::new(0.0, 2000.0, 0.0);
        assert!(s.can_track(&eye(), &heat("a", ahead, Vec3::new(0.0, 200.0, 0.0)), false));
        assert!(!s.can_track(&eye(), &heat("a", ahead, Vec3::new(0.0, -200.0, 0.0)), false));
        s.set_weapon(1, None, false);
        let far = Vec3::new(0.0, 4.0 * NM, 0.0);
        assert!(!s.can_track(&eye(), &heat("a", far, Vec3::ZERO), false), "beyond R/2 without afterburner");
        assert!(s.can_track(&eye(), &Heat { afterburner: true, ..heat("a", far, Vec3::ZERO) }, false));
        let east = Vec3::new(2000.0, 100.0, 0.0);
        assert!(!s.can_track(&eye(), &heat("a", east, Vec3::ZERO), true), "limited heat: 87° off the heading");
    }

    #[test]
    fn helmet_cone_per_generation() {
        let view = Vec3::new(50f64.to_radians().sin(), 50f64.to_radians().cos(), 0.0);
        let e = Eye { helmet_axis: Some(view), ..eye() };
        let u = heat("u", view * 3000.0 + Vec3::UP * 100.0, Vec3::ZERO);
        let mut s = Seeker::default();
        assert!(s.in_view(&e, &u));
        s.set_generation(3);
        assert!(!s.in_view(&e, &u));
    }

    #[test]
    fn search_locks_the_centre_target_and_eases_the_symbol() {
        let mut s = Seeker::default();
        let units = [heat("far", Vec3::new(400.0, 3000.0, 0.0), Vec3::ZERO), heat("near", Vec3::new(250.0, 3000.0, 0.0), Vec3::ZERO)];
        s.update(0.0, &eye(), &units, false, true);
        assert_eq!(s.target(), Some("near"));
        assert!(s.locked() && s.tone() == Tone::Lock);
        let goal = eye().screen_offset(units[1].pos).unwrap();
        assert!((s.symbol().x - 0.3 * goal.x).abs() < 1e-9);
        s.update(1.0, &eye(), &units, false, false);
        assert!(!s.locked() && s.tone() == Tone::Off, "no rounds: no tone");
    }

    #[test]
    fn radar_lock_slaves_the_seeker() {
        let mut s = Seeker { radar: Some(RadarLock { key: "r".into(), air_to_air: true }), ..Seeker::default() };
        let units = [heat("r", Vec3::new(3000.0, 3000.0, 0.0), Vec3::ZERO)];
        assert_eq!(s.search(0.0, &eye(), &units, false).map(|u| u.key.as_str()), Some("r"));
        assert!(s.slaved() && s.in_view(&eye(), &units[0]), "45° inside the 70° cone");
    }

    #[test]
    fn mrm_circle_lead_and_q() {
        let z = Some(Dlz { max: 10000.0, min: 2000.0 });
        assert_eq!(circle(true, z, 6000.0), 2.5);
        assert!((circle(true, z, 12000.0) - 5.0 / 3.0).abs() < 1e-12);
        assert_eq!(circle(false, None, 0.0), 5.0);
        assert_eq!(predicted(Vec3::ZERO, Vec3::new(100.0, 0.0, 0.0), 10000.0), Vec3::new(500.0, 0.0, 0.0));
        assert_eq!(in_circle(Some(Px { x: 30.0, y: 40.0 }), 5.0, false), (true, 1.0));
        assert_eq!(in_circle(Some(Px { x: 0.0, y: 120.0 }), 5.0, false).1, 0.5);
        assert!(target_in_circle(Some(Px { x: 100.0, y: 0.0 }), true) && !target_in_circle(Some(Px { x: 100.0, y: 0.0 }), false));
    }
}
