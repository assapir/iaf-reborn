//! Ours, Modern IAF's F-16s (modern-iaf/docs/avionics-plan.md E1, E2): the threat warning display drawn on the 3D
//! cockpit's RWR scope from the RWR's cockpit copy ([`crate::rwr::Rwr::display`]), and the missile approach warning
//! (MAW) from the RWR's list of missiles launched at the jet.
//!
//! The display follows the dash-34's threat azimuth indicator (docs/real-mfd.md "The threat azimuth indicator"): the
//! ownship in the centre, the highest-priority threat in a diamond, a lethal one (a lock) in a square, a launch in a
//! circle. Each symbol sits at its bearing on the ring of its lethality, a launch nearest the centre, a lock on the
//! inner ring, a search radar outside it (inferred, as the ALR-69 class of sets places its symbols by lethality: the
//! scope's place by range of the dash-34's set piled the range's close drones on the centre); a symbol too close to
//! one already placed moves along its ring, either way in turn. The MLU's ALR-69 adds PRI (the 5 highest-priority
//! threats) and OPEN (up to 16), and the UNKNOWN and TGT SEP buttons. World frame X east, Y north, Z up, metres.

use crate::rwr::{Shown, ground_class};
use crate::vec3::{Vec3, wrap_pi};
use std::collections::HashMap;

/// PRI mode shows the 5 highest-priority threats, OPEN up to 16 (MLU M1 fig. 7-3).
pub const PRI_MAX: usize = 5;
pub const OPEN_MAX: usize = 16;
/// A new threat's symbol flashes this long (inferred).
pub const NEW_S: f64 = 4.0;
/// SYS TEST shows its test pattern this long (inferred).
pub const TEST_S: f64 = 3.0;
/// Two symbols closer than this (in scope radii: the top threat's diamond is 0.43 wide on the 3D cockpit's scope, a
/// lock's square 0.3) are moved apart; TGT SEP held spreads them wider (inferred).
const SEP: f64 = 0.45;
const SEP_WIDE: f64 = 0.65;
/// The rings by lethality (scope radii; inferred): a launch, a lock (the inner ring), a search radar.
pub const RING_LAUNCH: f64 = 0.3;
pub const RING_LOCK: f64 = 0.58;
pub const RING_SEARCH: f64 = 0.9;

/// A threat's class, which sets its symbol's frame.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// An airborne radar: the "wingform" hat over its number.
    Air,
    /// A SAM radar: its digit.
    Sam,
    /// An AAA radar: the gun-mount box with its letter.
    Aaa,
    /// A ship's radar.
    Ship,
    /// An emitter the RWR cannot name: "U", shown only with UNKNOWN on.
    Unknown,
}

/// A threat's class and label by its type code (inferred from the dash-34's figs. 1-133 / 1-134: the aircraft by its
/// number, a SAM by its digit, AAA by a letter). Codes from 1000 are Modern IAF's (1000 = the F-35, 1020 = the
/// MiG-29A).
pub fn identify(type_code: i64) -> (Kind, &'static str) {
    use Kind::*;
    match type_code {
        100 => (Air, "16"),
        110 => (Air, "15"),
        120 => (Air, "4"),
        130 => (Air, "KF"),
        140 => (Air, "LV"),
        150 => (Air, "21"),
        160 => (Air, "23"),
        170 => (Air, "25"),
        180 => (Air, "29"),
        190 => (Air, "M3"),
        1000 => (Air, "35"),
        1020 => (Air, "29"),
        290 => (Sam, "2"),
        300 => (Sam, "3"),
        310 => (Sam, "5"),
        320 => (Sam, "6"),
        330 => (Sam, "8"),
        340 => (Sam, "H"),
        350 | 360 => (Aaa, "A"),
        380 | 390 => (Ship, "S"),
        _ => (Unknown, "U"),
    }
}

/// One symbol on the scope.
#[derive(Clone, Debug, PartialEq)]
pub struct Symbol {
    pub id: u64,
    pub kind: Kind,
    pub label: &'static str,
    /// The place in scope radii, x right, y up (heading-up).
    pub at: (f64, f64),
    pub diamond: bool,
    /// Locking the jet (not a search radar): the square.
    pub lethal: bool,
    /// A missile launched: the circle.
    pub launch: bool,
    /// First seen less than [`NEW_S`] ago: the symbol flashes.
    pub new: bool,
    /// Ours (Modern IAF): the own jammer works against it: chevrons either side, `>6<` (the dash-34's "jamming
    /// (steady)", fig. 1-133; docs/real-mfd.md).
    pub jammed: bool,
}

/// The threat warning prime panel's state and the display it drives.
#[derive(Clone, Debug, Default)]
pub struct Twd {
    /// OPEN mode (up to 16); off = PRI (the 5 highest-priority threats; at power-up, inferred).
    pub open: bool,
    /// UNKNOWN: the unknown emitters shown.
    pub unknowns: bool,
    /// TGT SEP held: the symbols spread wider.
    pub sep: bool,
    /// HANDOFF: the emitter the diamond was handed to.
    handoff: Option<u64>,
    /// When each emitter was first seen.
    seen: HashMap<u64, f64>,
    /// The last frame's symbols in priority order (HANDOFF steps through them).
    order: Vec<u64>,
    test_until: f64,
    /// A new threat came up (the new-threat tone).
    new_guy: bool,
    /// HANDOFF moved the diamond (its tone).
    handed: bool,
    /// Ours: the own jammer is on (Modern IAF's burn-through, docs/ai.md §15.6): every named radar shows the jamming
    /// chevrons.
    pub jamming: bool,
}

impl Twd {
    /// The new-threat tone is due (cleared by the call).
    pub fn take_new_guy(&mut self) -> bool {
        std::mem::take(&mut self.new_guy)
    }

    /// HANDOFF moved the diamond (cleared by the call).
    pub fn take_handoff(&mut self) -> bool {
        std::mem::take(&mut self.handed)
    }

    /// SYS TEST: the test pattern for [`TEST_S`].
    pub fn sys_test(&mut self, now: f64) {
        self.test_until = now + TEST_S;
    }

    pub fn testing(&self, now: f64) -> bool {
        now < self.test_until
    }

    /// HANDOFF: the diamond to the next symbol in priority order (round to the first).
    pub fn handoff(&mut self) {
        if self.order.is_empty() {
            return;
        }
        let at = self.handoff.and_then(|h| self.order.iter().position(|&i| i == h)).unwrap_or(0);
        self.handoff = Some(self.order[(at + 1) % self.order.len()]);
        self.handed = true;
    }

    /// The symbols for the RWR's cockpit copy `shown` from the own position and heading (radians clockwise from north):
    /// the active entries, unknowns only with UNKNOWN on, in priority order (a launch, then a lock, then the nearest),
    /// at most 5 (PRI) or 16 (OPEN); during SYS TEST the test pattern.
    pub fn update(&mut self, shown: &[(u64, Shown)], own: Vec3, heading: f64, now: f64) -> Vec<Symbol> {
        if self.testing(now) {
            return test_pattern();
        }
        let mut list: Vec<(u64, Kind, &'static str, f64, f64, bool, bool)> = shown
            .iter()
            .filter(|(_, s)| s.active)
            .map(|(id, s)| {
                let (kind, label) = identify(s.type_code);
                let d = Vec3::new(s.pos.x - own.x, s.pos.y - own.y, 0.0);
                let rel = wrap_pi(d.x.atan2(d.y) - heading);
                (*id, kind, label, d.length(), rel, !s.search, s.launch)
            })
            .filter(|e| e.1 != Kind::Unknown || self.unknowns)
            .collect();
        list.sort_by(|a, b| b.6.cmp(&a.6).then(b.5.cmp(&a.5)).then(a.3.total_cmp(&b.3)));
        list.truncate(if self.open { OPEN_MAX } else { PRI_MAX });
        let ids: Vec<u64> = list.iter().map(|e| e.0).collect();
        self.seen.retain(|id, _| ids.contains(id));
        for &id in &ids {
            self.seen.entry(id).or_insert_with(|| {
                self.new_guy = true;
                now
            });
        }
        if self.handoff.is_some_and(|h| !ids.contains(&h)) {
            self.handoff = None;
        }
        let top = self.handoff.or(ids.first().copied());
        self.order = ids;
        let gap = if self.sep { SEP_WIDE } else { SEP };
        let mut placed: Vec<(f64, f64)> = Vec::new();
        list.iter()
            .map(|&(id, kind, label, _, rel, lethal, launch)| {
                let ring = if launch {
                    RING_LAUNCH
                } else if lethal {
                    RING_LOCK
                } else {
                    RING_SEARCH
                };
                let at = separate(ring, rel, &placed, gap);
                placed.push(at);
                Symbol {
                    id,
                    kind,
                    label,
                    at,
                    diamond: Some(id) == top,
                    lethal,
                    launch,
                    new: now - self.seen[&id] < NEW_S,
                    jammed: self.jamming && kind != Kind::Unknown,
                }
            })
            .collect()
    }
}

/// A symbol's place on ring `r` (scope radii) at relative bearing `rel`, moved along the ring by a gap at a time,
/// counter-clockwise then clockwise in turn, while it lies within `gap` of one already `placed` (where the ring is
/// full, at its bearing).
fn separate(r: f64, rel: f64, placed: &[(f64, f64)], gap: f64) -> (f64, f64) {
    let xy = |a: f64| (r * a.sin(), r * a.cos());
    let clear = |p: (f64, f64)| placed.iter().all(|q| (p.0 - q.0).hypot(p.1 - q.1) >= gap);
    let step = 2.0 * (gap / (2.0 * r)).min(1.0).asin();
    let n = (std::f64::consts::PI / step).floor() as i32;
    (0..=n)
        .flat_map(|k| [rel - f64::from(k) * step, rel + f64::from(k) * step])
        .map(xy)
        .find(|p| clear(*p))
        .unwrap_or(xy(rel))
}

/// SYS TEST's pattern (inferred): one symbol of each class at the four quarters of the inner ring.
fn test_pattern() -> Vec<Symbol> {
    let s = |id, kind, label, at| Symbol {
        id,
        kind,
        label,
        at,
        diamond: id == 1,
        lethal: false,
        launch: false,
        new: false,
        jammed: false,
    };
    vec![
        s(1, Kind::Air, "16", (0.0, 0.5)),
        s(2, Kind::Sam, "6", (0.5, 0.0)),
        s(3, Kind::Aaa, "A", (0.0, -0.5)),
        s(4, Kind::Unknown, "U", (-0.5, 0.0)),
    ]
}

/// A missile launched at the jet as the MAW sees it.
#[derive(Clone, Copy, Debug)]
pub struct Approach {
    pub id: i64,
    pub pos: Vec3,
    pub vel: Vec3,
    /// The launcher's unit class (-1 unknown): where it was launched from, [`launch_class`].
    pub launcher: i64,
}

/// The missile's class an infrared MAW gives from the launch point it sees (modern-iaf/docs/ews.md §3; inferred: the
/// PAWS gives "the direction, missile type, and time to impact" and the launch point, the DAS the launch point; how
/// finely it names the type is open): "SAM" launched from the ground or the sea, "AAM" from the air.
pub fn launch_class(launcher: i64) -> &'static str {
    if ground_class(launcher) { "SAM" } else { "AAM" }
}

/// One missile warning: the direction off the nose (radians, right +), the time to impact (s; infinite while it
/// does not close) and the missile's class ([`launch_class`]).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Warning {
    pub id: i64,
    pub bearing: f64,
    pub tti: f64,
    pub class: &'static str,
    /// Not warned of before (its tone and voice).
    pub new: bool,
}

impl Warning {
    /// The text under the warning's "M": the class and the whole seconds to impact, at most 99 ("AAM 12"; "AAM --"
    /// while it does not close).
    pub fn label(&self) -> String {
        let t = if self.tti.is_finite() { format!("{}", self.tti.clamp(0.0, 99.0) as i64) } else { "--".into() };
        format!("{} {t}", self.class)
    }
}

/// The missile approach warning from the infrared plume of every missile launched at the jet, whatever its seeker
/// (the Sufa's PAWS: "the direction, missile type, and time to impact", Janes 2025; the Adir's DAS).
#[derive(Clone, Debug, Default)]
pub struct Maw {
    known: Vec<i64>,
}

impl Maw {
    /// The warnings for the `missiles` launched at the jet, from its position, velocity and heading (radians clockwise
    /// from north). The time to impact is the range over the closing speed (inferred).
    pub fn update(&mut self, missiles: &[Approach], own: Vec3, own_vel: Vec3, heading: f64) -> Vec<Warning> {
        let out: Vec<Warning> = missiles
            .iter()
            .map(|m| {
                let d = m.pos - own;
                let range = d.length();
                let closing = if range > 0.0 { -(m.vel - own_vel).dot(d) / range } else { 0.0 };
                Warning {
                    id: m.id,
                    bearing: wrap_pi(d.x.atan2(d.y) - heading),
                    tti: if closing > 1.0 { range / closing } else { f64::INFINITY },
                    class: launch_class(m.launcher),
                    new: !self.known.contains(&m.id),
                }
            })
            .collect();
        self.known = missiles.iter().map(|m| m.id).collect();
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(type_code: i64, x: f64, y: f64, search: bool, launch: bool) -> Shown {
        Shown { type_code, pos: Vec3::new(x, y, 0.0), launch, active: true, search }
    }

    #[test]
    fn symbols_priority_and_limits() {
        let mut t = Twd::default();
        let nm = 1852.0;
        let shown = vec![
            (1, at(1000, 0.0, 40.0 * nm, true, false)), // an F-35 searching ahead, 40 NM
            (2, at(100, 20.0 * nm, 0.0, false, false)), // an F-16 locking, 20 NM right
            (3, at(320, -10.0 * nm, 0.0, false, true)), // an SA-6 launching, 10 NM left
            (4, at(999, 0.0, -5.0 * nm, false, false)), // an unknown
            (5, Shown { active: false, ..at(100, 0.0, 1.0, false, false) }),
        ];
        let s = t.update(&shown, Vec3::ZERO, 0.0, 0.0);
        assert_eq!(s.iter().map(|s| s.label).collect::<Vec<_>>(), ["6", "16", "35"], "launch, lock, search");
        assert!(s[0].diamond && s[0].launch && s[0].lethal && !s[1].diamond && !s[2].lethal);
        // At their bearings, on the rings by lethality: the launch nearest, the lock on the inner ring, the search out.
        assert!((s[0].at.0 + RING_LAUNCH).abs() < 1e-9 && s[0].at.1.abs() < 1e-9, "the launch left: {:?}", s[0].at);
        assert!((s[1].at.0 - RING_LOCK).abs() < 1e-9 && s[1].at.1.abs() < 1e-9, "the lock right: {:?}", s[1].at);
        assert!(s[2].at.0.abs() < 1e-9 && (s[2].at.1 - RING_SEARCH).abs() < 1e-9, "the search ahead: {:?}", s[2].at);
        assert!(s.iter().all(|s| s.new) && t.take_new_guy() && !t.take_new_guy());
        t.unknowns = true;
        let s = t.update(&shown, Vec3::ZERO, 0.0, 1.0);
        assert!(s.iter().any(|s| s.kind == Kind::Unknown && s.label == "U" && s.new) && t.take_new_guy());
        let s = t.update(&shown, Vec3::ZERO, 0.0, 10.0);
        assert!(s.iter().all(|s| !s.new), "no longer new after 4 s");
        // The own jammer on: the named radars carry the jamming chevrons, the unknown none.
        assert!(s.iter().all(|s| !s.jammed));
        t.jamming = true;
        let s = t.update(&shown, Vec3::ZERO, 0.0, 11.0);
        assert!(s.iter().all(|s| s.jammed == (s.kind != Kind::Unknown)), "jamming chevrons");
        let many: Vec<(u64, Shown)> = (10..30).map(|i| (i, at(100, i as f64 * nm, 0.0, true, false))).collect();
        assert_eq!(t.update(&many, Vec3::ZERO, 0.0, 11.0).len(), PRI_MAX);
        t.open = true;
        assert_eq!(t.update(&many, Vec3::ZERO, 0.0, 11.0).len(), OPEN_MAX);
    }

    #[test]
    fn heading_up_rings_and_separation() {
        let mut t = Twd::default();
        let d = |a: (f64, f64), b: (f64, f64)| (a.0 - b.0).hypot(a.1 - b.1);
        // Heading east: a lock to the east is ahead on the inner ring; a search radar 90 NM north on the left.
        let shown = vec![(1, at(100, 10.0 * 1852.0, 0.0, false, false)), (2, at(110, 0.0, 90.0 * 1852.0, true, false))];
        let s = t.update(&shown, Vec3::ZERO, std::f64::consts::FRAC_PI_2, 0.0);
        assert!(d(s[0].at, (0.0, RING_LOCK)) < 1e-9 && d(s[1].at, (-RING_SEARCH, 0.0)) < 1e-9, "{s:?}");
        // The range's drones: four close together ahead, two locking: each pair apart on its ring, none on the
        // ownship, every symbol clear of every other.
        let drones: Vec<(u64, Shown)> =
            (0..4).map(|k| (k, at(1000, 100.0 * k as f64, 5.0 * 1852.0, k >= 2, false))).collect();
        for wide in [false, true] {
            t.sep = wide;
            let s = t.update(&drones, Vec3::ZERO, 0.0, 0.0);
            let gap = if wide { SEP_WIDE } else { SEP };
            for (i, a) in s.iter().enumerate() {
                let r = if a.lethal { RING_LOCK } else { RING_SEARCH };
                assert!((a.at.0.hypot(a.at.1) - r).abs() < 1e-9, "on its ring: {a:?}");
                assert!(wide || a.at.1 > 0.0, "still ahead: {a:?}");
                for b in &s[i + 1..] {
                    assert!(d(a.at, b.at) >= gap - 1e-9, "apart: {a:?} {b:?}");
                }
            }
        }
        // A full ring keeps its bearing rather than loop.
        assert_eq!(separate(0.3, 0.0, &[(0.0, 0.0)], 2.0), (0.0, 0.3));
    }

    #[test]
    fn handoff_and_test() {
        let mut t = Twd::default();
        let shown = vec![(1, at(100, 0.0, 9000.0, false, false)), (2, at(110, 0.0, 19000.0, false, false))];
        assert!(t.update(&shown, Vec3::ZERO, 0.0, 0.0)[0].diamond);
        t.handoff();
        assert!(t.take_handoff());
        let s = t.update(&shown, Vec3::ZERO, 0.0, 0.1);
        assert!(!s[0].diamond && s[1].diamond, "the diamond handed to the second");
        t.handoff();
        assert!(t.update(&shown, Vec3::ZERO, 0.0, 0.2)[0].diamond, "and round to the first");
        t.handoff();
        assert!(t.update(&shown[..1], Vec3::ZERO, 0.0, 0.3)[0].diamond, "its emitter gone: back to the top");
        t.sys_test(1.0);
        let s = t.update(&[], Vec3::ZERO, 0.0, 2.0);
        assert_eq!(s.len(), 4);
        assert!(t.update(&[], Vec3::ZERO, 0.0, 4.5).is_empty(), "the test ends after 3 s");
    }

    #[test]
    fn maw_direction_and_time_to_impact() {
        let mut m = Maw::default();
        // A missile 6 km behind, closing at 600 m/s on a jet flying north at 200 m/s: 6000 / 400 = 15 s.
        let a = Approach { id: 7, pos: Vec3::new(0.0, -6000.0, 0.0), vel: Vec3::new(0.0, 600.0, 0.0), launcher: 0x1c };
        let w = m.update(&[a], Vec3::ZERO, Vec3::new(0.0, 200.0, 0.0), 0.0);
        assert!((w[0].tti - 15.0).abs() < 1e-9 && (w[0].bearing.abs() - std::f64::consts::PI).abs() < 1e-9);
        assert!(w[0].new && w[0].label() == "AAM 15", "fired from an aircraft: {:?}", w[0]);
        let w = m.update(&[a], Vec3::ZERO, Vec3::new(0.0, 200.0, 0.0), std::f64::consts::FRAC_PI_2);
        assert!(!w[0].new && (w[0].bearing - std::f64::consts::FRAC_PI_2).abs() < 1e-9, "heading east: on the right");
        let slow = Approach { vel: Vec3::new(0.0, 100.0, 0.0), ..a };
        let w = m.update(&[slow], Vec3::ZERO, Vec3::new(0.0, 200.0, 0.0), 0.0);
        assert!(w[0].tti.is_infinite() && w[0].label() == "AAM --");
        assert!(m.update(&[], Vec3::ZERO, Vec3::ZERO, 0.0).is_empty());
        let sam = Approach { id: 8, launcher: 8, ..a };
        assert_eq!(m.update(&[sam], Vec3::ZERO, Vec3::ZERO, 0.0)[0].class, "SAM", "from a ground launcher");
        assert_eq!(launch_class(-1), "AAM", "unknown: the air");
    }
}
