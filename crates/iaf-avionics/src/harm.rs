//! The HARM page's emitter list (docs/mfd.md "HARM (10)"): the original's HARM sensor (vtable 0x601190, a target sensor
//! with a ±15° cone) captured by `FUN_0045bb00` → `FUN_00446050` into state+0xa28..0xe00. Ours lists the RWR's active
//! emitters inside that cone — the HARM sensor itself waits for the AI target sensor (deviations.md).
//!
//! World frame X east, Y north, Z up, radians. A base is the jet's (heading, pitch).

use crate::vec3::Vec3;
use std::f64::consts::{PI, TAU};

/// The cone: 15° (0x601168, static init 0x45b68e); the page's field width = 2·acos = 30° (+0xdf8).
const HALF_ANGLE: f64 = std::f64::consts::PI / 12.0;
pub const FIELD: f64 = 2.0 * HALF_ANGLE;
/// The sensor keeps the best 5 by 100 / distance (ai.md §14).
const KEEP: usize = 5;

fn wrap(a: f64) -> f64 {
    (a + PI).rem_euclid(TAU) - PI
}

/// An RWR entry offered to the capture.
#[derive(Clone, Debug)]
pub struct Emitter {
    pub key: String,
    pub type_code: i64,
    pub pos: Vec3,
    pub active: bool,
}

/// A captured emitter, angles from the base at the capture.
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
}

impl Harm {
    pub fn list(&self) -> &[Contact] {
        &self.list
    }
    pub fn selected(&self) -> Option<&str> {
        self.selected.as_deref()
    }

    /// A capture (the mcp's state 5): the active emitters inside the cone, nearest first, at most 5; the selection
    /// kept when still listed, else the nearest (UNCERTAIN: the sensor's own pick).
    pub fn capture(&mut self, emitters: &[Emitter], eye: Vec3, base: (f64, f64)) {
        self.base = base;
        let fwd = Vec3::new(base.0.sin() * base.1.cos(), base.0.cos() * base.1.cos(), base.1.sin());
        self.list = emitters
            .iter()
            .filter(|e| e.active)
            .filter_map(|e| {
                let d = e.pos - eye;
                let dist = d.length();
                (dist >= 1.0 && fwd.dot(d * (1.0 / dist)) >= HALF_ANGLE.cos()).then(|| Contact {
                    key: e.key.clone(),
                    type_code: e.type_code,
                    az: wrap(d.x.atan2(d.y) - base.0),
                    el: d.z.atan2(d.x.hypot(d.y)) - base.1,
                    dist,
                })
            })
            .collect();
        self.list.sort_by(|a, b| a.dist.total_cmp(&b.dist));
        self.list.truncate(KEEP);
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

    /// The heading / pitch change since the capture (+0xdf4 / +0xdfc, wrapped to ±π).
    pub fn drift(&self, base: (f64, f64)) -> (f64, f64) {
        (wrap(self.base.0 - base.0), wrap(self.base.1 - base.1))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn em(key: &str, x: f64, y: f64) -> Emitter {
        Emitter { key: key.into(), type_code: 300, pos: Vec3::new(x, y, 0.0), active: true }
    }

    #[test]
    fn the_cone_nearest_first() {
        let mut h = Harm::default();
        let es = [em("far", 0.0, 20000.0), em("near", 1000.0, 10000.0), em("side", 10000.0, 1000.0)];
        h.capture(&es, Vec3::ZERO, (0.0, 0.0));
        let keys: Vec<_> = h.list().iter().map(|c| c.key.as_str()).collect();
        assert_eq!(keys, ["near", "far"]);
        assert_eq!(h.selected(), Some("near"));
        h.select("far");
        h.capture(&es, Vec3::ZERO, (0.0, 0.0));
        assert_eq!(h.selected(), Some("far"), "kept while listed");
    }
}
