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
/// Weapon data Real: the rear sector, the target's tail within 60° of the line of sight (inferred).
const REAR_SECTOR_DEG: f64 = 60.0;
/// The modern head's diamond on its axis: the screen point of the axis this far out (m).
const AXIS_M: f64 = 1000.0;

/// Weapon data Real lock ranges in metres (docs/real-weapons.md §1.2): in the rear sector, and from the front
/// without / with the target's afterburner (0 = no front lock: a rear-aspect missile).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RealLock {
    pub rear: f64,
    pub front_mil: f64,
    pub front_ab: f64,
}

/// The distance at which a radar missile of `generation` goes active after launch (m; modern-iaf/docs/weapons.md §8.2,
/// inferred): the reach of the generation's seeker without the target's afterburner, half its lock range (`can_track`'s
/// R/2). The time to active of the post-launch cue counts down to it (`missile::Missile::times`).
pub fn active_range(generation: i64) -> Option<f64> {
    self::generation(generation).map(|(_, nm)| nm * NM / 2.0)
}

/// The modern jets' seeker head (modern-iaf/docs/weapons.md §8.1, G26): caged it looks along its axis (the radar's
/// line of sight to an A-A lock inside its gimbal cone, else the helmet's line of sight, else the nose) and hears a
/// target there; uncaged on a heard target it tracks that target anywhere inside its gimbal cone. SPOT hears within the
/// seeker's narrow field (`FOV_DEG`), SCAN within the original's search circle about the axis (`CIRCLE_PX2`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Head {
    pub uncaged: bool,
    pub scan: bool,
}

impl Head {
    /// The half angle (°) about the axis in which the caged seeker hears a target.
    pub fn field_deg(self) -> f64 {
        if self.scan { CIRCLE_PX2.sqrt() / PX_PER_DEG } else { FOV_DEG }
    }
}

#[derive(Clone, Debug)]
pub struct Seeker {
    cone_cos: f64,
    lock_range: f64,
    /// Weapon data Real: lock ranges by aspect and afterburner, in place of the generation's range.
    pub real_lock: Option<RealLock>,
    /// The modern jets' cage / uncage and SPOT / SCAN (`set_head`); None: the original's seeker.
    head: Option<Head>,
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
            real_lock: None,
            head: None,
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

    /// The selected missile: its generation, then the Real overrides (cone = gimbal limit, lock ranges).
    pub fn set_weapon(&mut self, generation: i64, real_cone_deg: Option<f64>, real_lock: Option<RealLock>) {
        self.set_generation(generation);
        if let Some(c) = real_cone_deg {
            self.cone_cos = c.to_radians().cos();
        }
        self.real_lock = real_lock;
    }

    /// The longest lock range: the generation's, or with Real the largest of its ranges.
    pub fn lock_range(&self) -> f64 {
        self.real_lock.map_or(self.lock_range, |l| l.rear.max(l.front_ab).max(l.front_mil))
    }

    /// A target that moves away from the shooter within the rear sector of the line of sight `d`.
    fn rear_aspect(d: Vec3, vel: Vec3) -> bool {
        vel.try_normalize().is_some_and(|v| v.dot(d) >= REAR_SECTOR_DEG.to_radians().cos() * d.length())
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

    /// The modern jets' seeker head (`Head`) on, caged in SPOT, or off (the original's seeker); turning it on again
    /// keeps its state.
    pub fn set_head(&mut self, on: bool) {
        if on != self.head.is_some() {
            self.head = on.then_some(Head::default());
        }
    }
    pub fn head(&self) -> Option<Head> {
        self.head
    }

    /// The uncage button: caged and hearing a target (the lock tone), the seeker uncages and tracks it; uncaged, it
    /// cages again. Nothing without the head.
    pub fn uncage(&mut self) {
        let heard = self.target.is_some() && self.lock;
        if let Some(h) = &mut self.head {
            h.uncaged = !h.uncaged && heard;
        }
    }

    /// SPOT / SCAN (the SMS's option). Nothing without the head.
    pub fn toggle_scan(&mut self) {
        if let Some(h) = &mut self.head {
            h.scan = !h.scan;
        }
    }

    /// Uncaged and tracking its target: the HUD's large diamond.
    pub fn tracking(&self) -> bool {
        self.head.is_some_and(|h| h.uncaged) && self.target.is_some()
    }

    /// The point `p` inside the seeker's gimbal cone about the nose.
    fn within_cone(&self, eye: &Eye, p: Vec3) -> bool {
        (p - eye.pos).try_normalize().is_some_and(|d| eye.nose.fwd.dot(d) >= self.cone_cos)
    }

    /// The caged head's axis: toward the radar's A-A lock inside the gimbal cone, else the helmet's line of sight inside
    /// it, else the nose (the boresight).
    fn axis(&self, eye: &Eye, units: &[Heat]) -> Vec3 {
        let radar = find(units, self.radar_aa()).and_then(|u| (u.pos - eye.pos).try_normalize());
        radar
            .into_iter()
            .chain(eye.helmet_axis.and_then(Vec3::try_normalize))
            .find(|d| eye.nose.fwd.dot(*d) >= self.cone_cos)
            .unwrap_or(eye.nose.fwd)
    }

    /// One update of the modern head: uncaged, it keeps tracking its target while that stays inside the gimbal cone
    /// and its lock rule (`can_track`), the diamond on it; losing it, it cages (inferred). Caged, it hears the trackable
    /// unit nearest its axis within the SPOT / SCAN field (the lock tone; the seek tone without one), the diamond on the
    /// axis.
    fn update_head(&mut self, h: Head, eye: &Eye, units: &[Heat], limited: bool, have_rounds: bool) {
        if h.uncaged {
            let held = find(units, self.target.as_deref())
                .filter(|t| self.within_cone(eye, t.pos) && self.can_track(eye, t, limited));
            if let Some(t) = held {
                self.set_tone(true, have_rounds);
                self.ease_to(eye.screen_offset(t.pos));
                return;
            }
            self.head = Some(Head { uncaged: false, ..h });
        }
        let axis = self.axis(eye, units);
        let field = h.field_deg().to_radians().cos();
        let heard = units
            .iter()
            .filter_map(|u| Some(((u.pos - eye.pos).try_normalize()?.dot(axis), u)))
            .filter(|&(c, u)| c >= field && self.can_track(eye, u, limited))
            .max_by(|a, b| a.0.total_cmp(&b.0))
            .map(|(_, u)| u);
        self.target = heard.map(|u| u.key.clone());
        self.set_tone(heard.is_some(), have_rounds);
        self.ease_to(eye.screen_offset(eye.pos + axis * AXIS_M));
    }

    /// The symbol eases toward `goal` (pos = 0.3·goal + 0.7·pos), snapping within 5 px; None (behind) leaves it.
    fn ease_to(&mut self, goal: Option<Px>) {
        let Some(goal) = goal else { return };
        let s = self.symbol;
        self.symbol = Px { x: EASE * goal.x + (1.0 - EASE) * s.x, y: EASE * goal.y + (1.0 - EASE) * s.y };
        if (self.symbol.x - goal.x).abs() < SNAP_PX && (self.symbol.y - goal.y).abs() < SNAP_PX {
            self.symbol = goal;
        }
    }

    fn radar_aa(&self) -> Option<&str> {
        self.radar.as_ref().filter(|r| r.air_to_air).map(|r| r.key.as_str())
    }

    /// `FUN_00461d10`: limited heat (580) only within ±60° of the own heading (bearing, not aspect); range ≤ R;
    /// beyond R/2 only a target with its afterburner on. With Real (`real_lock`): in the rear sector the same rule
    /// with the rear range; from the front within the front range, the afterburner one when the target's is on.
    pub fn can_track(&self, eye: &Eye, u: &Heat, limited: bool) -> bool {
        let d = u.pos - eye.pos;
        if limited {
            let az = crate::vec3::wrap_pi(d.x.atan2(d.y) - eye.yaw);
            if az.abs() > LIMITED_AZ_DEG.to_radians() {
                return false;
            }
        }
        let r = d.length();
        let Some(l) = self.real_lock else {
            return r <= self.lock_range && (r <= self.lock_range / 2.0 || u.afterburner);
        };
        if Self::rear_aspect(d, u.vel) {
            return r <= l.rear && (r <= l.rear / 2.0 || u.afterburner);
        }
        let front = if u.afterburner { l.front_ab } else { l.front_mil };
        front > 0.0 && r <= front
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
        if let Some(h) = self.head {
            self.update_head(h, eye, units, limited, have_rounds);
            return;
        }
        let Some(t) = self.search(now, eye, units, limited).filter(|t| self.in_view(eye, t)) else {
            self.set_tone(false, have_rounds);
            self.symbol = Px { x: self.symbol.x * (1.0 - EASE), y: self.symbol.y * (1.0 - EASE) };
            return;
        };
        self.set_tone(self.can_track(eye, t, limited), have_rounds);
        self.ease_to(eye.screen_offset(t.pos));
    }

    /// The target a launch takes (`FUN_00462ad0`): the seeker's target when inside the HUD-centre circle. With the
    /// modern head: the target it hears or tracks, anywhere in its cone.
    pub fn target_in_circle<'a>(&self, eye: &Eye, units: &'a [Heat]) -> Option<&'a Heat> {
        if self.head.is_some() {
            return find(units, self.target.as_deref()).filter(|_| self.lock);
        }
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

    /// Lock-on after launch (ours: AIM-9X Block II, Python 5; docs/weapons.md §13.1). A missile launched without a
    /// lock at `pos` searches along `axis` (toward its cued point): the unit nearest that axis within the seeker's cone
    /// that its lock rule (`can_track`) accepts, any side (as the original's search).
    pub fn loal<'a>(&self, pos: Vec3, axis: Vec3, units: &'a [Heat]) -> Option<&'a Heat> {
        let eye = Eye { pos, ..Eye::default() };
        let axis = axis.try_normalize()?;
        units
            .iter()
            .filter_map(|u| Some((axis.dot((u.pos - pos).try_normalize()?), u)))
            .filter(|&(c, u)| c >= self.cone_cos && self.can_track(&eye, u, false))
            .max_by(|a, b| a.0.total_cmp(&b.0))
            .map(|(_, u)| u)
    }

    /// Leaving the IR mode (`FUN_00461bb0`): both tones stop.
    pub fn exit(&mut self) {
        if let Some(h) = &mut self.head {
            h.uncaged = false;
        }
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
    fn original_range_and_aspect() {
        let mut s = Seeker::default();
        s.set_weapon(1, None, None);
        let ahead = Vec3::new(0.0, 2000.0, 0.0);
        assert!(s.can_track(&eye(), &heat("a", ahead, Vec3::new(0.0, -200.0, 0.0)), false), "any aspect");
        let far = Vec3::new(0.0, 4.0 * NM, 0.0);
        assert!(!s.can_track(&eye(), &heat("a", far, Vec3::ZERO), false), "beyond R/2 without afterburner");
        assert!(s.can_track(&eye(), &Heat { afterburner: true, ..heat("a", far, Vec3::ZERO) }, false));
        let east = Vec3::new(2000.0, 100.0, 0.0);
        assert!(!s.can_track(&eye(), &heat("a", east, Vec3::ZERO), true), "limited heat: 87° off the heading");
    }

    const AIM9L: RealLock = RealLock { rear: 11_000.0, front_mil: 3000.0, front_ab: 8500.0 };
    const AIM9D: RealLock = RealLock { rear: 11_000.0, front_mil: 0.0, front_ab: 0.0 };

    fn real(lock: RealLock) -> Seeker {
        let mut s = Seeker::default();
        s.set_weapon(3, Some(40.0), Some(lock));
        s
    }

    #[test]
    fn real_rear_sector() {
        let s = real(AIM9L);
        let away = Vec3::new(0.0, 200.0, 0.0);
        let at = |km: f64| Vec3::new(0.0, km * 1000.0, 0.0);
        assert!(s.can_track(&eye(), &heat("a", at(5.0), away), false), "5 km behind");
        assert!(
            !s.can_track(&eye(), &heat("a", at(8.0), away), false),
            "8 km behind: beyond rear/2 without afterburner"
        );
        assert!(s.can_track(&eye(), &Heat { afterburner: true, ..heat("a", at(8.0), away) }, false));
        assert!(!s.can_track(&eye(), &Heat { afterburner: true, ..heat("a", at(11.5), away) }, false), "beyond rear");
        let off = |deg: f64| Vec3::new(deg.to_radians().sin(), deg.to_radians().cos(), 0.0) * 200.0;
        assert!(s.can_track(&eye(), &heat("a", at(5.0), off(50.0)), false), "50° off the line of sight: rear");
        assert!(!s.can_track(&eye(), &heat("a", at(5.0), off(70.0)), false), "70° off: front, beyond 3 km");
    }

    #[test]
    fn real_front_mil_ab_and_none() {
        let s = real(AIM9L);
        let toward = Vec3::new(0.0, -200.0, 0.0);
        let at = |km: f64| Vec3::new(0.0, km * 1000.0, 0.0);
        assert!(s.can_track(&eye(), &heat("a", at(2.5), toward), false), "head-on within 3 km");
        assert!(!s.can_track(&eye(), &heat("a", at(5.0), toward), false), "head-on 5 km without afterburner");
        assert!(s.can_track(&eye(), &Heat { afterburner: true, ..heat("a", at(5.0), toward) }, false));
        assert!(!s.can_track(&eye(), &Heat { afterburner: true, ..heat("a", at(9.0), toward) }, false));
        assert!(!real(AIM9D).can_track(&eye(), &heat("a", at(1.0), toward), false), "rear-aspect seeker: no head-on");
        assert_eq!(s.lock_range(), 11_000.0);
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
    fn loal_takes_the_unit_nearest_the_cued_axis() {
        let mut s = Seeker::default();
        s.set_weapon(4, Some(100.0), None);
        let units = [
            heat("off", Vec3::new(3000.0, 3000.0, 0.0), Vec3::ZERO),
            heat("cued", Vec3::new(4000.0, 500.0, 0.0), Vec3::ZERO),
            heat("far", Vec3::new(40_000.0, 0.0, 0.0), Vec3::ZERO),
        ];
        let east = Vec3::new(1.0, 0.0, 0.0);
        assert_eq!(s.loal(Vec3::ZERO, east, &units).map(|u| u.key.as_str()), Some("cued"));
        assert!(s.loal(Vec3::ZERO, -east, &units[..1]).is_none(), "outside the cone");
    }

    #[test]
    fn search_locks_the_centre_target_and_eases_the_symbol() {
        let mut s = Seeker::default();
        let units = [
            heat("far", Vec3::new(400.0, 3000.0, 0.0), Vec3::ZERO),
            heat("near", Vec3::new(250.0, 3000.0, 0.0), Vec3::ZERO),
        ];
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

    fn bearing(deg: f64, m: f64) -> Vec3 {
        Vec3::new(m * deg.to_radians().sin(), m * deg.to_radians().cos(), 0.0)
    }

    #[test]
    fn caged_holds_the_boresight_uncaged_tracks() {
        let mut s = Seeker::default();
        s.set_head(true);
        s.uncage();
        assert!(!s.head().unwrap().uncaged, "nothing heard: the button leaves it caged");
        // A target 3° right of the nose: the caged SPOT seeker hears it, its diamond stays on the boresight.
        let mut units = [heat("t", bearing(3.0, 3000.0), Vec3::ZERO)];
        let run = |s: &mut Seeker, units: &[Heat], from: i32| {
            for k in from..from + 30 {
                s.update(f64::from(k) * 0.1, &eye(), units, false, true);
            }
        };
        run(&mut s, &units, 0);
        assert!(s.locked() && s.tone() == Tone::Lock && !s.tracking());
        assert_eq!(s.symbol(), Px::default(), "caged: the diamond on the boresight");
        // Uncaged it tracks the target out to 20°: the diamond on it, a launch takes it.
        s.uncage();
        assert!(s.tracking());
        units[0].pos = bearing(20.0, 3000.0);
        run(&mut s, &units, 30);
        assert_eq!(s.symbol(), eye().screen_offset(units[0].pos).unwrap(), "uncaged: the diamond on the target");
        assert!(s.tracking() && s.locked());
        assert_eq!(s.target_in_circle(&eye(), &units).map(|u| u.key.as_str()), Some("t"));
        // Caged again: back on the boresight, the target outside its field.
        s.uncage();
        run(&mut s, &units, 60);
        assert_eq!(s.symbol(), Px::default());
        assert!(!s.locked() && s.tone() == Tone::Seek && s.target_in_circle(&eye(), &units).is_none());
    }

    #[test]
    fn uncaged_track_lost_cages_again() {
        let mut s = Seeker::default();
        s.set_head(true);
        let mut units = [heat("t", bearing(2.0, 3000.0), Vec3::ZERO)];
        s.update(0.0, &eye(), &units, false, true);
        s.uncage();
        units[0].pos = bearing(100.0, 3000.0); // beyond the 70° gimbal cone
        s.update(1.0, &eye(), &units, false, true);
        assert!(!s.tracking() && !s.head().unwrap().uncaged && !s.locked());
    }

    #[test]
    fn caged_on_the_radar_lock_and_scan_widens_the_field() {
        let mut s = Seeker { radar: Some(RadarLock { key: "r".into(), air_to_air: true }), ..Seeker::default() };
        s.set_head(true);
        let units = [heat("r", bearing(18.0, 3000.0), Vec3::ZERO), heat("n", bearing(1.0, 3000.0), Vec3::ZERO)];
        s.update(0.0, &eye(), &units, false, true);
        assert_eq!(s.target(), Some("r"), "caged on the radar's line of sight, not the boresight");
        let mut s = Seeker::default();
        s.set_head(true);
        let off = [heat("o", bearing(6.2, 3000.0), Vec3::ZERO)];
        s.update(0.0, &eye(), &off, false, true);
        assert!(!s.locked(), "SPOT: 6.2° is outside its 6°");
        s.toggle_scan();
        s.update(1.0, &eye(), &off, false, true);
        assert!(s.locked(), "SCAN: inside the search circle's 6.45°");
        assert!((active_range(4).unwrap() - 7.5 * NM).abs() < 1e-9 && active_range(0).is_none());
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
        assert!(
            target_in_circle(Some(Px { x: 100.0, y: 0.0 }), true)
                && !target_in_circle(Some(Px { x: 100.0, y: 0.0 }), false)
        );
    }
}
