//! The HARM sensor and its page list (docs/mfd.md "HARM (10)"): the controller's sensor at ctl+0x44c (vtable 0x601190,
//! ctor `FUN_0045b850(0, 3, 20)`), a subclass of the AI target sensor (docs/ai.md §14) whose scan `FUN_004af300` runs
//! through `FUN_0045b960` (vfunc +0x60) when the sensor comes on (`FUN_0045c2b0`) and on the RWR's 2 s refresh
//! (`FUN_0044a1a0`). The page captures the list (`FUN_0045bb00` → `FUN_00446050`) into state+0xa28..0xe00.
//!
//! Extras "HARM targets: RWR" (ours, deviations.md) lists the RWR's active emitters inside the cone instead, plus the
//! hostile radar sites that have no brain (they never lock, so the RWR never lists them; inferred: they search).
//!
//! World frame X east, Y north, Z up, radians. A base is the jet's (heading, pitch).

use crate::radar::line_of_sight;
use crate::vec3::Vec3;
use std::f64::consts::{PI, TAU};

/// The cone: 15° (0x601168, static init 0x45b68e); the page's field width = 2·acos = 30° (+0xdf8).
const HALF_ANGLE: f64 = std::f64::consts::PI / 12.0;
pub const FIELD: f64 = 2.0 * HALF_ANGLE;
/// The range: 20 NM (the ctor's 0x14 at +0x70, vfunc +0x08) × 1854 m (0x603390).
const RANGE: f64 = 20.0 * 1854.0;
/// The RWR source keeps the nearest 5 (ours).
const KEEP_RWR: usize = 5;
/// The list's 15 slots (`FUN_004b0790(0xf)`), sorted by 100 / distance (`FUN_004b08e0`).
const KEEP: usize = 15;
/// Both line-of-sight ends are raised 1.5 m (0x603380).
const LOS_RAISE: f64 = 1.5;

fn wrap(a: f64) -> f64 {
    (a + PI).rem_euclid(TAU) - PI
}

/// A unit offered to the scan.
#[derive(Clone, Debug)]
pub struct Unit {
    pub key: String,
    /// The bdb type, −1 for none.
    pub type_code: i64,
    pub klass: i64,
    /// The mission entity's name.
    pub name: String,
    pub pos: Vec3,
    /// Its jammer is on.
    pub ecm: bool,
    /// A hostile site without a brain (mission 322's "dummy SA-2"): no target sensor, so it never locks (docs/ai.md
    /// §14). The RWR source counts it as searching (ours, inferred).
    pub search: bool,
}

impl Unit {
    /// The class filter (vfunc +0x3c `FUN_0045b980`, called by the spatial query's callback `0x4b2240`): classes 9,
    /// 10 and 11, and class 8 only when its name holds "RADAR" (0x631f3c, case sensitive: "RADARSA6", not "hawk 2
    /// radar").
    fn scanned(&self) -> bool {
        matches!(self.klass, 9..=11) || (self.klass == 8 && self.name.contains("RADAR"))
    }
}

/// An RWR entry offered to the RWR source.
#[derive(Clone, Debug)]
pub struct Emitter {
    pub key: String,
    pub type_code: i64,
    pub pos: Vec3,
    pub active: bool,
}

/// Where the list comes from: the original HARM sensor's scan, or (Extras, ours) the RWR's active emitters.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Source {
    #[default]
    Original,
    Rwr,
}

/// A listed unit, angles from the base at the capture. `type_code` is the page's entry +0xa38: the bdb type, or the
/// class when the type is −1.
#[derive(Clone, Debug, PartialEq)]
pub struct Contact {
    pub key: String,
    pub type_code: i64,
    pub az: f64,
    pub el: f64,
    pub dist: f64,
}

#[derive(Clone, Debug, Default)]
pub struct Harm {
    list: Vec<Contact>,
    selected: Option<String>,
    /// The heading / pitch at the capture (DAT_0082f574 / 0x82f568: the symbols move with the jet's turns until the
    /// next capture).
    base: (f64, f64),
    /// HUD mode 8 (`FUN_0045c2b0` on / `FUN_0045c2f0` off).
    pub active: bool,
    pub source: Source,
}

/// The angles of `pos` from `eye` against the base, when inside the cone.
fn in_cone(pos: Vec3, eye: Vec3, base: (f64, f64)) -> Option<(f64, f64, f64)> {
    let fwd = Vec3::new(base.0.sin() * base.1.cos(), base.0.cos() * base.1.cos(), base.1.sin());
    let d = pos - eye;
    let dist = d.length();
    (dist >= 1.0 && fwd.dot(d * (1.0 / dist)) >= HALF_ANGLE.cos())
        .then(|| (wrap(d.x.atan2(d.y) - base.0), d.z.atan2(d.x.hypot(d.y)) - base.1, dist))
}

/// The accept test (vfunc +0x48 `FUN_004aeb90`; the HARM's scan clears +0x50 first, so no "above the terrain" test):
/// inside the cone about the nose and a terrain line of sight.
fn accept(u: &Unit, eye: Vec3, base: (f64, f64), terrain: &dyn Fn(Vec3) -> Option<f64>) -> Option<Contact> {
    let raise = Vec3::new(0.0, 0.0, LOS_RAISE);
    let (az, el, dist) = in_cone(u.pos, eye, base)?;
    line_of_sight(eye + raise, u.pos + raise, terrain).then(|| Contact {
        key: u.key.clone(),
        type_code: if u.type_code == -1 { u.klass } else { u.type_code },
        az,
        el,
        dist,
    })
}

impl Harm {
    pub fn list(&self) -> &[Contact] {
        &self.list
    }
    pub fn selected(&self) -> Option<&str> {
        self.selected.as_deref()
    }

    /// A capture from the active source: the units' scan (Original) or the RWR's emitters (Rwr).
    pub fn capture(
        &mut self,
        units: &[Unit],
        emitters: &[Emitter],
        eye: Vec3,
        base: (f64, f64),
        own_ecm: bool,
        terrain: &dyn Fn(Vec3) -> Option<f64>,
    ) {
        match self.source {
            Source::Original => self.scan(units, eye, base, own_ecm, terrain),
            Source::Rwr => self.capture_rwr(units, emitters, eye, base, terrain),
        }
    }

    /// Extras "HARM targets: RWR" (ours): the RWR's active emitters inside the cone, and the searching sites the scan
    /// would accept (in range, in the cone, in sight), nearest first, at most 5; the selection kept when still listed,
    /// else the nearest.
    fn capture_rwr(
        &mut self,
        units: &[Unit],
        emitters: &[Emitter],
        eye: Vec3,
        base: (f64, f64),
        terrain: &dyn Fn(Vec3) -> Option<f64>,
    ) {
        self.base = base;
        self.list = emitters
            .iter()
            .filter(|e| e.active)
            .filter_map(|e| {
                let (az, el, dist) = in_cone(e.pos, eye, base)?;
                Some(Contact { key: e.key.clone(), type_code: e.type_code, az, el, dist })
            })
            .collect();
        let sites: Vec<Contact> = units
            .iter()
            .filter(|u| u.search && u.scanned() && (u.pos - eye).length() <= RANGE)
            .filter(|u| !self.list.iter().any(|c| c.key == u.key))
            .filter_map(|u| accept(u, eye, base, terrain))
            .collect();
        self.list.extend(sites);
        self.list.sort_by(|a, b| a.dist.total_cmp(&b.dist));
        self.list.truncate(KEEP_RWR);
        if !self.list.iter().any(|c| Some(&c.key) == self.selected.as_ref()) {
            self.selected = self.list.first().map(|c| c.key.clone());
        }
    }

    /// The scan (`FUN_004af300` via `FUN_0045b960`): the scanned classes within 20 NM, in the cone, in sight, best 15 by
    /// 100 / distance, friendlies too (the HARM's accept has no side test). Range with the own jammer on: ×0.8
    /// against a jamming unit, else ×0.5; without it a jamming unit is seen at any range. The selection is kept while
    /// alive and still accepted (forced into the list, range not re-tested), else the nearest.
    fn scan(
        &mut self,
        units: &[Unit],
        eye: Vec3,
        base: (f64, f64),
        own_ecm: bool,
        terrain: &dyn Fn(Vec3) -> Option<f64>,
    ) {
        self.base = base;
        self.list = units
            .iter()
            .filter(|u| u.scanned())
            .filter(|u| {
                let d = (u.pos - eye).length();
                match (own_ecm, u.ecm) {
                    (true, true) => d <= RANGE * 0.8,
                    (true, false) => d <= RANGE * 0.5,
                    (false, true) => true,
                    (false, false) => d <= RANGE,
                }
            })
            .filter_map(|u| accept(u, eye, base, terrain))
            .collect();
        self.list.sort_by(|a, b| a.dist.total_cmp(&b.dist));
        self.list.truncate(KEEP);
        let kept = self
            .selected
            .as_ref()
            .filter(|k| !self.list.iter().any(|c| &c.key == *k))
            .and_then(|k| units.iter().find(|u| &u.key == k).and_then(|u| accept(u, eye, base, terrain)));
        if let Some(c) = kept {
            if self.list.len() >= KEEP {
                self.list.pop();
            }
            let i = self.list.partition_point(|x| x.dist <= c.dist);
            self.list.insert(i, c);
        }
        if !self.list.iter().any(|c| Some(&c.key) == self.selected.as_ref()) {
            self.selected = self.list.first().map(|c| c.key.clone());
        }
    }

    /// Event 0x37(id) (a click on a symbol, `FUN_0045c280`): select it.
    pub fn select(&mut self, key: &str) {
        if self.list.iter().any(|c| c.key == key) {
            self.selected = Some(key.to_owned());
        }
    }

    /// Ctrl+Return (controller case 0x33: HUD mode 8 and more than one entry) / command 0x34: vfunc +0x2c
    /// `FUN_0045b930` → `FUN_004aefd0(next)`: the next (farther) / previous entry, wrapping; none selected → the first.
    pub fn step(&mut self, next: bool) {
        let n = self.list.len();
        if !self.active || n == 0 {
            return;
        }
        let i = match self.list.iter().position(|c| Some(&c.key) == self.selected.as_ref()) {
            Some(i) if next => (i + 1) % n,
            Some(i) => (i + n - 1) % n,
            None => 0,
        };
        self.selected = Some(self.list[i].key.clone());
    }

    /// The heading / pitch change since the capture (+0xdf4 / +0xdfc, wrapped to ±π).
    pub fn drift(&self, base: (f64, f64)) -> (f64, f64) {
        (wrap(self.base.0 - base.0), wrap(self.base.1 - base.1))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unit(key: &str, klass: i64, name: &str, x: f64, y: f64) -> Unit {
        Unit {
            key: key.into(),
            type_code: 300,
            klass,
            name: name.into(),
            pos: Vec3::new(x, y, 0.0),
            ecm: false,
            search: false,
        }
    }

    const FLAT: &dyn Fn(Vec3) -> Option<f64> = &|_| Some(0.0);

    #[test]
    fn the_scan() {
        let mut h = Harm::default();
        let us = [
            unit("far", 10, "AAA", 0.0, 30000.0),
            unit("near", 9, "SA13", 1000.0, 10000.0),
            unit("side", 10, "AAA", 10000.0, 1000.0),
            unit("out", 10, "AAA", 0.0, 40000.0),
            unit("launcher", 8, "SA6 launcher", 0.0, 5000.0),
            unit("radar", 8, "RADARSA6", 0.0, 20000.0),
            unit("tank", 6, "T-72", 0.0, 3000.0),
        ];
        h.capture(&us, &[], Vec3::ZERO, (0.0, 0.0), false, FLAT);
        let keys: Vec<_> = h.list().iter().map(|c| c.key.as_str()).collect();
        assert_eq!(keys, ["near", "radar", "far"]);
        assert_eq!(h.selected(), Some("near"));
        h.select("far");
        h.capture(&us, &[], Vec3::ZERO, (0.0, 0.0), false, FLAT);
        assert_eq!(h.selected(), Some("far"), "kept while listed");
        // The own jammer halves the range: "far" (30 km) drops from the scan but the kept selection is forced in.
        h.capture(&us, &[], Vec3::ZERO, (0.0, 0.0), true, FLAT);
        let keys: Vec<_> = h.list().iter().map(|c| c.key.as_str()).collect();
        assert_eq!(keys, ["near", "far"]);
        // A hill hides everything.
        h.capture(&us, &[], Vec3::ZERO, (0.0, 0.0), false, &|p: Vec3| Some(if p.y > 500.0 { 100.0 } else { 0.0 }));
        assert!(h.list().is_empty() && h.selected().is_none());
    }

    #[test]
    fn ctrl_return_steps() {
        let mut h = Harm { active: true, ..Default::default() };
        let us = [unit("a", 10, "", 0.0, 5000.0), unit("b", 10, "", 0.0, 10000.0), unit("c", 10, "", 0.0, 15000.0)];
        h.capture(&us, &[], Vec3::ZERO, (0.0, 0.0), false, FLAT);
        assert_eq!(h.selected(), Some("a"));
        h.step(true);
        assert_eq!(h.selected(), Some("b"));
        h.step(true);
        h.step(true);
        assert_eq!(h.selected(), Some("a"), "wraps");
        h.step(false);
        assert_eq!(h.selected(), Some("c"));
        let mut off = Harm::default();
        off.capture(&us, &[], Vec3::ZERO, (0.0, 0.0), false, FLAT);
        off.step(true);
        assert_eq!(off.selected(), Some("a"), "the sensor off: no step");
    }

    fn em(key: &str, x: f64, y: f64) -> Emitter {
        Emitter { key: key.into(), type_code: 300, pos: Vec3::new(x, y, 0.0), active: true }
    }

    #[test]
    fn the_rwr_source() {
        let mut h = Harm { source: Source::Rwr, active: true, ..Default::default() };
        let es = [em("far", 0.0, 20000.0), em("near", 1000.0, 10000.0), em("side", 10000.0, 1000.0)];
        // The units are ignored: only the emitters count.
        h.capture(&[unit("unit", 10, "", 0.0, 5000.0)], &es, Vec3::ZERO, (0.0, 0.0), false, FLAT);
        let keys: Vec<_> = h.list().iter().map(|c| c.key.as_str()).collect();
        assert_eq!(keys, ["near", "far"]);
        assert_eq!(h.selected(), Some("near"));
        h.select("far");
        h.capture(&[], &es, Vec3::ZERO, (0.0, 0.0), false, FLAT);
        assert_eq!(h.selected(), Some("far"), "kept while listed");
        h.step(true);
        assert_eq!(h.selected(), Some("near"), "Ctrl+Return wraps");
        // A searching site (no brain, never on the RWR) the scan accepts is listed; a launcher or one out of range is not.
        let mut site = unit("site", 8, "RADARSA2 radar", 0.0, 5000.0);
        site.search = true;
        let mut launcher = unit("launcher", 8, "sa2 launcher 1", 0.0, 4000.0);
        launcher.search = true;
        let mut far = unit("far site", 8, "RADARSA2 radar", 0.0, 40000.0);
        far.search = true;
        h.capture(&[site, launcher, far], &es, Vec3::ZERO, (0.0, 0.0), false, FLAT);
        let keys: Vec<_> = h.list().iter().map(|c| c.key.as_str()).collect();
        assert_eq!(keys, ["site", "near", "far"]);
    }
}
