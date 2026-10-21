//! The RWR of a controller (ctl+0x5b0, ctor `FUN_004515d0`; docs/rwr.md): 10 emitter slots filled by the lock /
//! unlock notifications of the radars and sensors that lock the jet (`FUN_0044deb0` / `FUN_0044e030`) and by the
//! missiles launched at it (`FUN_0044e160` / `FUN_0044e1d0`), the 2 s refresh (`FUN_00451a70`), the panel lights 'ai' /
//! 'sam' (`FUN_00450bc0`), the nearest threat (`FUN_00451f70`) and the cockpit copy (`FUN_00446200`).
//!
//! Extras "RWR: Real" (ours, docs/rwr.md §7) adds the SAM / AAA radars that search the jet: in their range and in
//! terrain line of sight, kept apart from the original's slots.
//!
//! World frame X east, Y north, Z up, metres, sim seconds. The host looks the units up and plays the sounds.

use crate::harm::radar_class;
use crate::radar::line_of_sight;
use crate::vec3::Vec3;
use std::f64::consts::{PI, TAU};

pub const SLOTS: usize = 10;
/// Emitter test (`FUN_004521c0`): within 37080 m (0x600d14); ground classes always, others only more than 120° off
/// the own nose (0x600d18).
const RANGE: f64 = 37080.0;
const REAR: f64 = 2.0943951;
/// bdb type codes the lock notifications ignore.
const IGNORED_TYPES: [i64; 3] = [220, 250, 270];
/// The nearest threat (`FUN_00451f70`): within 370800 m.
const NEAREST: f64 = 370800.0;
/// The refresh rides the controller's 2.0 s timer (DAT_0082f4a8; `FUN_0044a1a0`).
const REFRESH: f64 = 2.0;
/// WRN_NEW_GUY at most once per 1.0 s (gate ctl+0x860, `FUN_004d3fa0(0, 1.0, 0)` @4479fd).
const NEW_GUY_GATE: f64 = 1.0;
/// The cockpit copy shows at most 15 entries.
const DISPLAY_MAX: usize = 15;
/// The search test raises both line-of-sight ends 1.5 m, as the sites' own check (combat.gd LOS_RAISE).
const LOS_RAISE: f64 = 1.5;

/// The ground radars with an RWR glyph (docs/mfd.md §3 "RWR"): SA-2 / 3 / 5 / 6 / 8, Hawk, the AAA radars.
pub fn search_radar(type_code: i64) -> bool {
    matches!(type_code, 290 | 300 | 310 | 320 | 330 | 340 | 350 | 360 | 380 | 390)
}

/// A hostile ground unit offered to the search test: its key, its mission name and its radar's range (m).
#[derive(Clone, Debug)]
pub struct Site {
    pub key: String,
    pub name: String,
    pub reach: f64,
}

/// A radar searching the jet (Real RWR).
#[derive(Clone, Debug, PartialEq)]
pub struct Search {
    pub key: String,
    pub type_code: i64,
    pub pos: Vec3,
}

/// A unit as the RWR sees it.
#[derive(Clone, Copy, Debug, Default)]
pub struct Emitter {
    pub pos: Vec3,
    pub class: i64,
    pub type_code: i64,
    /// 5 = destroyed.
    pub state: i64,
}

impl Emitter {
    pub fn ground(&self) -> bool {
        matches!(self.class, 5 | 8 | 9 | 10 | 0x10)
    }
}

/// The host: the own jet now and the units by key.
pub struct World<'a> {
    pub pos: Vec3,
    pub yaw: f64,
    pub now: f64,
    pub unit: &'a dyn Fn(&str) -> Option<Emitter>,
}

/// One slot (+0xc + 0x24·i). `type_code` 0 = free (the add's test); the unit key stays None after a removal.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Slot {
    pub unit: Option<String>,
    pub type_code: i64,
    pub pos: Vec3,
    /// +0x14.
    pub launch: bool,
    /// +0x18: missiles in flight.
    pub missiles: i64,
    /// +0x1c: drop pending.
    pub drop: bool,
    /// +0x20.
    pub active: bool,
}

/// The panel lights (docs/cockpit.md): 3 'ai', 4 'sam'.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Lamps {
    pub ai: bool,
    pub sam: bool,
}

impl Lamps {
    fn set(&mut self, ground: bool, on: bool) {
        if ground { self.sam = on } else { self.ai = on }
    }
}

/// A missile launched at the jet (+0x178): its id and its distance to the jet at the launch.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Threat {
    pub id: i64,
    pub dist: f64,
}

/// A missile launched at the jet as the host reports it.
#[derive(Clone, Copy, Debug)]
pub struct Launched {
    pub id: i64,
    pub pos: Vec3,
    /// It chases a decoy: not listed.
    pub decoy: bool,
}

/// One entry of the cockpit copy.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Shown {
    pub type_code: i64,
    pub pos: Vec3,
    pub launch: bool,
    pub active: bool,
    /// A searching radar (Real RWR): no lock.
    pub search: bool,
}

#[derive(Clone, Debug)]
pub struct Rwr {
    slots: [Slot; SLOTS],
    /// +0x174.
    count: usize,
    threats: Vec<Threat>,
    pub lamps: Lamps,
    /// Damage 14 (RWR) blocks every notification (`FUN_0045cc90(0xe)`).
    pub damaged: bool,
    /// Ours (Flight data = Real): the display lists every used slot (the original copies the first `count`).
    pub compact: bool,
    /// The WRN_NEW_GUY gate [last, next] (`FUN_004d4100`).
    gate: (f64, f64),
    next_refresh: f64,
    /// WRN_NEW_GUY to play.
    new_guy: bool,
    /// Real RWR: the radars searching the jet, from the last [`Rwr::search`].
    searching: Vec<Search>,
}

impl Default for Rwr {
    fn default() -> Self {
        Rwr {
            slots: Default::default(),
            count: 0,
            threats: Vec::new(),
            lamps: Lamps::default(),
            damaged: false,
            compact: false,
            gate: (f64::NEG_INFINITY, f64::NEG_INFINITY),
            next_refresh: 0.0,
            new_guy: false,
            searching: Vec::new(),
        }
    }
}

impl Rwr {
    pub fn slots(&self) -> &[Slot; SLOTS] {
        &self.slots
    }
    pub fn count(&self) -> usize {
        self.count
    }
    pub fn threats(&self) -> &[Threat] {
        &self.threats
    }
    pub fn searching(&self) -> &[Search] {
        &self.searching
    }
    pub fn next_refresh(&self) -> f64 {
        self.next_refresh
    }
    /// WRN_NEW_GUY is due (cleared by the call).
    pub fn take_new_guy(&mut self) -> bool {
        std::mem::take(&mut self.new_guy)
    }

    pub fn find(&self, key: &str) -> Option<usize> {
        self.slots.iter().position(|s| s.unit.as_deref() == Some(key))
    }

    /// `FUN_004520f0`: any entry with the launch flag.
    pub fn any_launch(&self) -> bool {
        self.slots.iter().any(|s| s.launch)
    }

    /// The emitter test (`FUN_004521c0`): ≤ 37080 m (3-D) and, unless a ground class, more than 120° off the own nose
    /// (relative bearing `FUN_0044e770`).
    fn emitter_test(&self, w: &World, key: Option<&str>) -> bool {
        let Some(u) = key.and_then(|k| (w.unit)(k)) else { return false };
        let d = u.pos - w.pos;
        if d.length() > RANGE {
            return false;
        }
        let rel = (d.x.atan2(d.y) - w.yaw + PI).rem_euclid(TAU) - PI;
        u.ground() || rel.abs() > REAR
    }

    /// Add (`FUN_004518d0`): refused when full (count > 9) or listed; the first slot with type 0; the active flag from
    /// the emitter test.
    fn add(&mut self, w: &World, key: &str) -> bool {
        if self.count > 9 || self.find(key).is_some() {
            return false;
        }
        let Some(i) = self.slots.iter().position(|s| s.type_code == 0) else { return false };
        let u = (w.unit)(key);
        let active = self.emitter_test(w, Some(key));
        let s = &mut self.slots[i];
        s.type_code = u.map_or(0, |u| u.type_code);
        s.unit = Some(key.to_owned());
        s.pos = u.map_or(Vec3::ZERO, |u| u.pos);
        s.active = active;
        self.count += 1;
        true
    }

    /// Remove (`FUN_004519e0`): with missiles still flying only the drop is marked; else the slot is cleared (not
    /// compacted: the original's display copies only the first `count` slots).
    fn remove(&mut self, key: &str) -> bool {
        let Some(i) = self.find(key) else { return false };
        let s = &mut self.slots[i];
        if s.missiles == 0 {
            *s = Slot { pos: s.pos, ..Slot::default() };
            self.count -= 1;
        } else {
            s.drop = true;
        }
        true
    }

    fn type_ok(&self, w: &World, key: &str) -> Option<Emitter> {
        if self.damaged || key.is_empty() {
            return None;
        }
        (w.unit)(key).filter(|u| !IGNORED_TYPES.contains(&u.type_code))
    }

    /// A radar / sensor locks the jet (`FUN_0044deb0`): listed; when the new entry is active, its light and
    /// WRN_NEW_GUY (gated 1 s).
    pub fn lock(&mut self, w: &World, key: &str) {
        let Some(u) = self.type_ok(w, key) else { return };
        if self.add(w, key) && self.find(key).is_some_and(|i| self.slots[i].active) {
            self.light_on(w.now, u.ground());
        }
    }

    /// The lock is dropped (`FUN_0044e030`): removed; with the list empty, its light goes off.
    pub fn unlock(&mut self, w: &World, key: &str) {
        let Some(u) = self.type_ok(w, key) else { return };
        if self.remove(key) && self.count == 0 {
            self.lamps.set(u.ground(), false);
        }
    }

    /// A missile was launched at the jet by `key` (`FUN_0044e160` → `FUN_00451be0`): the entry (added if new) gets the
    /// launch flag, one more missile in flight and active; the missile joins the list unless it chases a decoy.
    /// False when ignored (damage, no key): no launch sounds.
    pub fn launch(&mut self, w: &World, key: &str, missile: Option<Launched>) -> bool {
        if self.damaged || key.is_empty() {
            return false;
        }
        let i = match self.find(key) {
            Some(i) => Some(i),
            None => {
                self.add(w, key);
                if self.count > 9 {
                    return true; // original quirk: the add that filled the list leaves the launch unmarked
                }
                self.find(key)
            }
        };
        if let Some(i) = i {
            let s = &mut self.slots[i];
            s.launch = true;
            s.missiles += 1;
            s.active = true;
        }
        if let Some(m) = missile.filter(|m| !m.decoy)
            && !self.threats.iter().any(|t| t.id == m.id)
        {
            self.threats.push(Threat { id: m.id, dist: m.pos.distance(w.pos) });
        }
        true
    }

    /// That missile is gone (`FUN_0044e1d0` → `FUN_00451e30`): one missile less; at none the launch flag drops (and a
    /// pending drop removes the entry); the missile leaves the list. False when ignored.
    pub fn missile_end(&mut self, key: &str, missile: Option<i64>) -> bool {
        if self.damaged || key.is_empty() {
            return false;
        }
        if let Some(i) = self.find(key) {
            let s = &mut self.slots[i];
            s.missiles -= 1;
            if s.missiles == 0 {
                s.launch = false;
                if s.drop {
                    self.remove(key);
                }
            }
        }
        if let Some(id) = missile {
            self.threats.retain(|t| t.id != id);
        }
        true
    }

    /// Damage 14 / 19 / 21 (`FUN_00451b90`): every entry and the missile list cleared.
    pub fn clear(&mut self) {
        self.searching.clear();
        self.slots = Default::default();
        self.count = 0;
        self.threats.clear();
    }

    /// The 2 s refresh (`FUN_00451a70`): positions; active = the emitter test or the launch flag; a destroyed emitter
    /// (state 5) is removed.
    pub fn refresh(&mut self, w: &World) {
        for i in 0..SLOTS {
            let key = self.slots[i].unit.clone();
            let u = key.as_deref().and_then(|k| (w.unit)(k));
            if let Some(u) = u {
                self.slots[i].pos = u.pos;
            }
            self.slots[i].active = self.emitter_test(w, key.as_deref()) || self.slots[i].launch;
            if let Some(k) = key
                && u.is_none_or(|u| u.state == 5)
            {
                self.remove(&k);
            }
        }
    }

    /// Every frame (the 2 s timer and `FUN_00450bc0`): with an empty list both lights off; else a light comes on (with
    /// WRN_NEW_GUY, gated 1 s) while an active entry of its kind exists, and goes off without one.
    pub fn update(&mut self, w: &World) {
        if w.now >= self.next_refresh {
            self.next_refresh = w.now + REFRESH;
            self.refresh(w);
        }
        if self.count == 0 {
            self.lamps = Lamps::default();
            return;
        }
        let (mut ground, mut air) = (false, false);
        for s in self.slots.iter().filter(|s| s.active) {
            if let Some(u) = s.unit.as_deref().and_then(|k| (w.unit)(k)) {
                if u.ground() { ground = true } else { air = true }
            }
        }
        if ground && !self.lamps.sam {
            self.light_on(w.now, true);
        }
        if air && !self.lamps.ai {
            self.light_on(w.now, false);
        }
        self.lamps.sam &= ground;
        self.lamps.ai &= air;
    }

    /// A light on, WRN_NEW_GUY through the gate (`FUN_004d4100`: passes when now is outside [last, next], then next =
    /// now + 1.0).
    fn light_on(&mut self, now: f64, ground: bool) {
        self.lamps.set(ground, true);
        if now >= self.gate.0 && now <= self.gate.1 {
            return;
        }
        self.gate = (now, now + NEW_GUY_GATE);
        self.new_guy = true;
    }

    /// Real RWR (ours), on the 2 s refresh: the `sites` that are a radar (the HARM sensor's class rule, so a SAM
    /// battery's launchers stay silent) with a search radar's type, alive, within their reach and in terrain line of
    /// sight of the jet search it. A new one plays WRN_NEW_GUY through the lock's gate; the lights stay the
    /// locks'. A damaged RWR hears none.
    pub fn search(&mut self, w: &World, sites: &[Site], terrain: &dyn Fn(Vec3) -> Option<f64>) {
        if self.damaged {
            self.searching.clear();
            return;
        }
        let raise = Vec3::new(0.0, 0.0, LOS_RAISE);
        let now: Vec<Search> = sites
            .iter()
            .filter_map(|s| {
                let u = (w.unit)(&s.key)?;
                (search_radar(u.type_code)
                    && radar_class(u.class, &s.name)
                    && u.state < 4
                    && u.pos.distance(w.pos) <= s.reach
                    && line_of_sight(u.pos + raise, w.pos + raise, terrain))
                .then(|| Search { key: s.key.clone(), type_code: u.type_code, pos: u.pos })
            })
            .collect();
        let new = now.iter().any(|s| self.find(&s.key).is_none() && !self.searching.iter().any(|o| o.key == s.key));
        self.searching = now;
        if new && !(w.now >= self.gate.0 && w.now <= self.gate.1) {
            self.gate = (w.now, w.now + NEW_GUY_GATE);
            self.new_guy = true;
        }
    }

    /// The nearest listed emitter within 370.8 km after a refresh (`FUN_00451f70`: F5's threat, AI action 430,
    /// condition 38).
    pub fn nearest(&mut self, w: &World) -> Option<String> {
        self.refresh(w);
        let mut best = None;
        let mut bd = NEAREST;
        for s in &self.slots {
            let Some(k) = s.unit.as_deref() else { continue };
            let p = (w.unit)(k).map_or(s.pos, |u| u.pos);
            let d = p.distance(w.pos);
            if d < bd {
                bd = d;
                best = Some(k.to_owned());
            }
        }
        best
    }

    /// The cockpit copy (`FUN_00446200`): the first `count` slots (at most 15; original bug: slots are not compacted,
    /// so after a removal an entry past `count` is not shown). With `compact` every listed slot is shown. Then the
    /// searching radars not listed (Real RWR), up to 15 in all.
    pub fn display(&self) -> Vec<Shown> {
        let shown =
            |s: &Slot| Shown { type_code: s.type_code, pos: s.pos, launch: s.launch, active: s.active, search: false };
        let mut out: Vec<Shown> = if self.compact {
            self.slots.iter().filter(|s| s.type_code != 0).take(DISPLAY_MAX).map(shown).collect()
        } else {
            self.slots.iter().take(self.count.min(DISPLAY_MAX)).map(shown).collect()
        };
        let searching = self.searching.iter().filter(|s| self.find(&s.key).is_none()).map(|s| Shown {
            type_code: s.type_code,
            pos: s.pos,
            launch: false,
            active: true,
            search: true,
        });
        out.extend(searching.take(DISPLAY_MAX.saturating_sub(out.len())));
        out
    }
}

/// Ours, Better cockpit `spo15` (docs/mig-cockpits.md §4.4): the MiG-23 panel's SPO-15 lamps from the cockpit
/// copy. The original RWR lists only the radars that lock the jet (docs/rwr.md §2); a searching radar (Real RWR)
/// lights its sector and type lamps without the lock lamp.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Spo15 {
    /// Sector lamps, bit i: 0..3 the left 10° / 30° / 50° / 90° lamps, 4..7 the right ones, 8 / 9 the left / right
    /// rear lamps.
    pub sectors: u16,
    /// Power strip lamps lit, 0..=SPO15_POWER_LAMPS: the strongest (nearest) emitter.
    pub power: u8,
    /// The red centre lamp: steady on a lock.
    pub lock: bool,
    /// A missile launched at the jet: the centre lamp flashes.
    pub launch: bool,
    /// Threat-type lamps, bit i: П airborne, З long-range, Х medium-range, Н short-range SAM radar, F early warning,
    /// С AWACS (the game has none of the last two).
    pub types: u8,
}

/// The art's power strip: 15 lamps (the real set's count).
pub const SPO15_POWER_LAMPS: u8 = 15;
/// The edges between the front lamps' sectors, degrees off the nose (inferred: lamps at 10 / 30 / 50 / 90°).
const SPO15_EDGES: [f64; 3] = [20.0, 40.0, 70.0];
/// Within this many degrees of the nose or of the 20° / 40° edge both neighbouring lamps light: about 10°
/// resolution within ±50° (docs/mig-cockpits.md §4.4).
const SPO15_SHARE: f64 = 5.0;

/// The sector lamps (bits as [`Spo15::sectors`]) for an emitter `rel_deg` off the nose (−180..180, right +).
pub fn spo15_sectors(rel_deg: f64) -> u16 {
    let side = if rel_deg < 0.0 { 0 } else { 4 };
    let a = rel_deg.abs();
    if a > 90.0 {
        return 1 << (8 + side / 4);
    }
    let mut m = 1 << (side + SPO15_EDGES.iter().filter(|&&e| a >= e).count());
    if a < SPO15_SHARE {
        m |= 1 << (4 - side);
    }
    for (k, e) in SPO15_EDGES[..2].iter().enumerate() {
        if (a - e).abs() < SPO15_SHARE {
            m |= 3 << (side + k);
        }
    }
    m
}

/// The threat-type lamp of a bdb type code (inferred from each system's real range): aircraft П; SA-2 / SA-5 З;
/// SA-3 / SA-6 / Hawk / ships Х; SA-8 / AAA / Gun Dish Н.
pub fn spo15_type(type_code: i64) -> Option<usize> {
    match type_code {
        100..=210 => Some(0),
        290 | 310 => Some(1),
        300 | 320 | 340 | 380 | 390 => Some(2),
        330 | 350 | 360 => Some(3),
        _ => None,
    }
}

/// The SPO-15 face from the cockpit copy `shown`, the own position and heading (degrees clockwise from north).
/// The power is the nearest active emitter's closeness: all lamps at the jet, none at the RWR range (inferred).
pub fn spo15(shown: &[Shown], own: Vec3, heading_deg: f64) -> Spo15 {
    let mut out = Spo15::default();
    let mut power: f64 = 0.0;
    for e in shown.iter().filter(|e| e.active) {
        let (dx, dy) = (e.pos.x - own.x, e.pos.y - own.y);
        let rel = (dx.atan2(dy).to_degrees() - heading_deg + 540.0).rem_euclid(360.0) - 180.0;
        out.sectors |= spo15_sectors(rel);
        power = power.max(1.0 - e.pos.distance(own) / RANGE);
        out.lock |= !e.search;
        out.launch |= e.launch;
        if let Some(t) = spo15_type(e.type_code) {
            out.types |= 1 << t;
        }
    }
    out.power = (power.clamp(0.0, 1.0) * SPO15_POWER_LAMPS as f64).ceil() as u8;
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unit(k: &str) -> Option<Emitter> {
        let e = |x, y, class, type_code| Some(Emitter { pos: Vec3::new(x, y, 3000.0), class, type_code, state: 1 });
        match k {
            "sam" => e(14142.0, 14142.0, 8, 300),
            "front" => e(0.0, 10000.0, 0x1c, 180),
            "back" => e(1000.0, -10000.0, 0x1c, 160),
            "heli" => e(0.0, 5000.0, 3, 220),
            _ => None,
        }
    }

    fn world(now: f64) -> World<'static> {
        World { pos: Vec3::new(0.0, 0.0, 3000.0), yaw: 0.0, now, unit: &unit }
    }

    #[test]
    fn locks_lights_and_the_new_guy_gate() {
        let mut r = Rwr::default();
        r.lock(&world(0.0), "sam");
        assert!(r.lamps.sam && !r.lamps.ai && r.take_new_guy());
        r.lock(&world(0.0), "front");
        assert!(!r.slots()[1].active, "ahead: inside ±120°");
        r.lock(&world(0.5), "back");
        assert!(r.lamps.ai && !r.take_new_guy(), "gated 1 s");
        r.lock(&world(0.5), "heli");
        assert_eq!(r.count(), 3, "type 220 ignored");
        assert_eq!(r.nearest(&world(0.5)).as_deref(), Some("front"));
    }

    #[test]
    fn a_drop_waits_for_the_missile() {
        let mut r = Rwr::default();
        r.lock(&world(0.0), "sam");
        r.launch(&world(0.0), "sam", Some(Launched { id: 1, pos: Vec3::new(14000.0, 14000.0, 50.0), decoy: false }));
        assert!(r.any_launch() && r.threats().len() == 1);
        r.unlock(&world(0.0), "sam");
        assert!(r.count() == 1 && r.slots()[0].drop);
        r.missile_end("sam", Some(1));
        assert!(r.count() == 0 && r.slots()[0].unit.is_none() && !r.any_launch() && r.threats().is_empty());
    }

    #[test]
    fn search_radars_in_range_and_in_sight() {
        let site = |key: &str, reach| Site { key: key.into(), name: "RADARsa3".into(), reach };
        let flat = |_: Vec3| Some(0.0);
        let ridge = |p: Vec3| Some(if (p.x - 7000.0).abs() < 500.0 { 5000.0 } else { 0.0 });
        let mut r = Rwr::default();
        let sites = [site("sam", 37080.0), site("front", 37080.0)];
        r.search(&world(0.0), &sites, &flat);
        assert_eq!(r.searching().len(), 1, "the aircraft has no search radar");
        r.search(&world(0.0), &[Site { name: "sa3 launcher".into(), ..site("sam", 37080.0) }], &flat);
        assert!(r.searching().is_empty(), "a launcher is no radar");
        r.search(&world(0.0), &sites, &flat);
        assert!(r.take_new_guy());
        let d = r.display();
        assert!(d.len() == 1 && d[0].search && d[0].active && d[0].type_code == 300);
        r.search(&world(3.0), &sites, &flat);
        assert!(!r.take_new_guy(), "only a new radar sounds");
        r.search(&world(5.0), &sites, &ridge);
        assert!(r.searching().is_empty(), "masked by the ridge");
        r.search(&world(7.0), &[site("sam", 10000.0)], &flat);
        assert!(r.searching().is_empty(), "out of its reach");
        r.search(&world(9.0), &sites, &flat);
        r.lock(&world(9.0), "sam");
        let d = r.display();
        assert!(d.len() == 1 && !d[0].search, "a lock shows once, as the lock");
        assert!(!spo15(&[Shown { search: true, ..d[0] }], Vec3::ZERO, 0.0).lock);
        r.damaged = true;
        r.search(&world(11.0), &sites, &flat);
        assert!(r.searching().is_empty());
    }

    #[test]
    fn spo15_lamps() {
        assert_eq!(spo15_sectors(0.0), 0b1_0001, "the nose: both 10° lamps");
        assert_eq!(spo15_sectors(12.0), 1 << 4);
        assert_eq!(spo15_sectors(-21.0), 0b11, "on the 20° edge: the left 10° and 30° lamps");
        assert_eq!(spo15_sectors(55.0), 1 << 6);
        assert_eq!(spo15_sectors(-80.0), 1 << 3);
        assert_eq!(spo15_sectors(-135.0), 1 << 8, "left rear");
        assert_eq!(spo15_sectors(170.0), 1 << 9, "right rear");
        // Heading east: a SAM to the south is 90° right, half the range away; an aircraft ahead launching.
        let own = Vec3::new(0.0, 0.0, 0.0);
        let sam = Shown {
            type_code: 320,
            pos: Vec3::new(0.0, -RANGE / 2.0, 0.0),
            launch: false,
            active: true,
            search: false,
        };
        let air =
            Shown { type_code: 180, pos: Vec3::new(30000.0, 0.0, 0.0), launch: true, active: true, search: false };
        let off =
            Shown { type_code: 290, pos: Vec3::new(100.0, 0.0, 0.0), launch: false, active: false, search: false };
        let s = spo15(&[sam, air, off], own, 90.0);
        assert_eq!(s.sectors, 1 << 7 | 0b1_0001);
        assert_eq!(s.power, 8, "the SAM at half the range: ceil(7.5)");
        assert!(s.lock && s.launch);
        assert_eq!(s.types, 0b101, "П and Х; the inactive SA-2 is not heard");
        assert_eq!(spo15(&[off], own, 0.0), Spo15::default());
    }
}
