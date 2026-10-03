//! The player's radar (docs/radar.md): the radar manager of the player controller (ctl+0x84, `FUN_004acc20`)
//! with its modes (OFF / STBY, STT, BORE, LRS, TWS, ACM, GMT, MAP), the per-aircraft range tables, the scan
//! (`FUN_004af300`, every 2.0 s and on events), the hit test (`FUN_004aeb90`), the contact list (15, nearest
//! first), the lock / designate keys and the STT track (`FUN_004b1300`).
//!
//! World frame X east, Y north, Z up, metres, sim seconds. The caller passes the own pose and the units with
//! every call that can scan (`Input`), and drains `events` afterwards (the target's RWR lock notices and the
//! semi-active missiles' illumination loss, `FUN_00458130`).

use std::f64::consts::PI;

pub const OFF: usize = 0;
pub const STBY: usize = 1;
pub const STT: usize = 2;
pub const BORE: usize = 3;
pub const LRS: usize = 4;
pub const TWS: usize = 5;
pub const ACM: usize = 6;
pub const GMT: usize = 7;
pub const MAP: usize = 8;

/// Range scale of index 1..6 (`FUN_004b0020`, `0x603358..`: 5·2^(i−1) NM at 1851.87 m/NM).
pub const RANGE_M: [f64; 6] = [9259.372, 18518.744, 37037.488, 74074.977, 148149.95, 296299.9];
/// Detection NM → m (`0x603390`).
pub const NM: f64 = 1854.0;
/// Full rescan period (`DAT_0082f4a8` = 2.0 s).
pub const SCAN_PERIOD: f64 = 2.0;
/// Cone half-angles (cos): 60° every mode, 12° BORE (static init `0x603440..` / `0x6035d8`).
pub const CONE_COS: f64 = 0.5;
pub const BORE_COS: f64 = 0.97814760;
/// Air modes skip targets lower than 30 m above the terrain (`0x60337c`).
const MIN_AGL: f64 = 30.0;
/// Line-of-sight ends raised 1.5 m (`0x603380`).
const LOS_RAISE: f64 = 1.5;
/// The candidate query: |c − C|² < 3·(r + R/2)² (`0x604e6c`).
const QUERY_K: f64 = 3.0;
/// STT auto-range: below 0.33·R one scale down, above 0.75·R one up (`0x60355c` / `0x603560`).
const AUTO_DOWN: f64 = 0.33;
const AUTO_UP: f64 = 0.75;
/// Antenna sweep period (vt+0x54): 4.0 s, BORE 1.0 s (`0x6033b8` / `0x6035e8`); bar step 0.25.
const SWEEP: f64 = 4.0;
const SWEEP_BORE: f64 = 1.0;
pub const MAX_CONTACTS: usize = 15;
/// m/s → kt (`0x600a70`).
const KT: f64 = 1.9427955;
/// Classes per mode filter (vt+0x3c): air `4b1c70`, MAP `4b0ce0`, GMT `4b0fc0` (moving only).
const AIR_CLASSES: [i64; 4] = [0x1c, 3, 2, 1];
const MAP_CLASSES: [i64; 11] = [10, 8, 9, 0xb, 0xd, 0x1d, 0x1e, 5, 6, 0xf, 0x10];
const GMT_CLASSES: [i64; 8] = [5, 6, 0xf, 0x10, 8, 9, 10, 0xb];

/// Per cockpit index (`FUN_00447e70`: 0 F-15, 1 F-16, 2 F-4-2000, 3 Lavi, 4 Kfir, 5 F-4E, 6 Mirage, 7 MiG-29,
/// 8 MiG-23): A-A table `0x640a74` [LRS, TWS, ACM, BORE] and A-G table `0x640bbc` [MAP, GMT], each (max range
/// index, detection NM); (0, 0) = no such mode.
pub const TABLES: [[(u8, f64); 6]; 9] = [
    [(6, 90.0), (4, 40.0), (2, 10.0), (2, 10.0), (4, 40.0), (4, 20.0)],
    [(5, 45.0), (4, 35.0), (2, 10.0), (2, 10.0), (4, 40.0), (4, 30.0)],
    [(5, 55.0), (4, 40.0), (2, 10.0), (2, 10.0), (5, 60.0), (5, 40.0)],
    [(6, 90.0), (4, 40.0), (2, 10.0), (2, 10.0), (5, 60.0), (5, 40.0)],
    [(2, 8.0), (0, 0.0), (1, 5.0), (1, 5.0), (2, 10.0), (2, 10.0)],
    [(4, 25.0), (0, 0.0), (2, 10.0), (2, 10.0), (2, 10.0), (2, 10.0)],
    [(2, 8.0), (0, 0.0), (1, 5.0), (1, 5.0), (2, 10.0), (2, 10.0)],
    [(5, 45.0), (4, 35.0), (2, 10.0), (2, 10.0), (2, 10.0), (2, 10.0)],
    [(4, 25.0), (0, 0.0), (2, 10.0), (2, 10.0), (4, 40.0), (4, 25.0)],
];

pub type V3 = [f64; 3];

fn sub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn len(a: V3) -> f64 {
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt()
}
/// Godot's Vector2.normalized(): the zero vector stays zero.
fn norm2(x: f64, y: f64) -> (f64, f64) {
    let l = (x * x + y * y).sqrt();
    if l == 0.0 { (0.0, 0.0) } else { (x / l, y / l) }
}
/// GDScript wrapf(x, −π, π).
fn wrap_pi(x: f64) -> f64 {
    x - 2.0 * PI * ((x + PI) / (2.0 * PI)).floor()
}

/// A unit the radar can see.
#[derive(Clone, Debug, Default)]
pub struct Unit {
    pub key: String,
    pub pos: V3,
    pub vel: V3,
    /// vt+0x3c class.
    pub klass: i64,
    /// 4 / 5 = destroyed / dying.
    pub state: i64,
    pub coll_radius: f64,
    /// Degrees clockwise from north.
    pub heading: f64,
    pub type_code: i64,
    pub hostile: bool,
}

/// The own jet: position, forward axis (world), yaw (rad, atan2(fwd.x, fwd.y)).
#[derive(Clone, Copy, Debug, Default)]
pub struct Own {
    pub pos: V3,
    pub fwd: V3,
    pub yaw: f64,
}

/// What a call sees: the own pose, the units and the terrain height at a world point (None: no terrain).
pub struct Input<'a> {
    pub own: Own,
    pub units: &'a [Unit],
    pub ground: &'a dyn Fn(V3) -> Option<f64>,
}

/// A contact record (`FUN_004aeb90`).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Contact {
    pub key: String,
    pub pos: V3,
    pub heading: f64,
    pub locked: bool,
    pub selected: bool,
    pub hostile: bool,
    /// 100 / distance.
    pub prio: f64,
    /// Target heading − line-of-sight bearing (rad, ±π).
    pub aspect: f64,
    /// Off the nose (rad; + right / up).
    pub az: f64,
    pub el: f64,
    pub dist: f64,
    /// kt.
    pub speed: f64,
    pub type_code: i64,
    pub alt: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Event {
    /// The target's RWR hears a lock (on-lock / on-unlock `4b0510` / `4b04d0`).
    Lock(String, bool),
    /// `FUN_00458130`: the semi-active missiles lose their guidance.
    IlluminationLost,
}

/// A mode's range: max index, detection NM, current index 1..max.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ModeRange {
    pub max: i64,
    pub nm: f64,
    pub idx: i64,
}

#[derive(Clone, Debug)]
pub struct Radar {
    pub modes: [Option<ModeRange>; 9],
    pub mode: usize,   // +0x30
    pub last_aa: usize, // +0x34
    pub last_ag: usize, // +0x38
    pub bore_return: usize, // +0x3c
    pub aa: bool,      // +0x40
    pub off: bool,     // +0x44 (OFF or STBY: not radiating)
    pub damaged: bool, // +0x48
    pub bore_held: bool, // +0x54
    /// +4 == 5: push to the cockpit.
    pub dirty: bool,
    /// The contact list (15, priority highest first).
    pub contacts: Vec<Contact>,
    /// +0x58: the selected / locked record's unit key ("" none) and whether it is locked (+0x14).
    pub sel_key: String,
    pub sel_locked: bool,
    /// STT: the locked record (kept between scans).
    pub stt: Option<Contact>,
    /// Outside STT: the locked (TWS: selected) record with its unit's position and distance this frame
    /// (`FUN_0044e370` reads the target's live position; the contact list only changes on a scan).
    live: Option<Contact>,
    /// Carets (az, el) 0..1 (state+0xa0c / +0xa10).
    pub antenna: (f64, f64),
    /// The designated ground point (event 0x2f, `FUN_004ade90`): +0x50 flag, +0x58.. X / Y / terrain height;
    /// +0x4c the MAP page's EXP flag (event 0x30, `FUN_004ade70`).
    pub designated: bool,
    pub desig: V3,
    pub exp: bool,
    /// state+0xa14 (rad).
    pub heading_shift: f64,
    href: Option<f64>,
    next_scan: f64,
    sweep_t0: f64,
    sweep_dir: bool,
    sweep_bar: f64,
    sweep_step: f64,
    pub events: Vec<Event>,
}

impl Radar {
    /// Create (`FUN_004ace60`) for cockpit index `cockpit` (`FUN_00447e70`); `lrs_nm` > 0 overrides the LRS / STT
    /// detection range (Weapon data Real). The radar starts OFF in A-A.
    pub fn new(cockpit: usize, lrs_nm: f64) -> Self {
        let t = TABLES[cockpit.min(TABLES.len() - 1)];
        let mut modes = [None; 9];
        for (k, id) in [LRS, TWS, ACM, BORE, MAP, GMT].into_iter().enumerate() {
            let (a, mut b) = t[k];
            if a == 0 {
                continue;
            }
            if id == LRS && lrs_nm > 0.0 {
                b = lrs_nm;
            }
            let a = a as i64;
            modes[id] = Some(ModeRange { max: a, nm: b, idx: if id == BORE { a } else { a.min(4) } });
        }
        // STT takes LRS's (max index, NM), else ACM's.
        let src = modes[LRS].or(modes[ACM]).unwrap_or(ModeRange { max: 2, nm: 10.0, idx: 2 });
        modes[STT] = Some(ModeRange { max: src.max, nm: src.nm, idx: src.max.min(4) });
        Radar {
            modes,
            mode: OFF,
            last_aa: LRS,
            last_ag: GMT,
            bore_return: LRS,
            aa: true,
            off: true,
            damaged: false,
            bore_held: false,
            dirty: false,
            contacts: Vec::new(),
            sel_key: String::new(),
            sel_locked: false,
            stt: None,
            live: None,
            antenna: (0.0, 0.0),
            designated: false,
            desig: [0.0; 3],
            exp: false,
            heading_shift: 0.0,
            href: None,
            next_scan: 0.0,
            sweep_t0: f64::INFINITY,
            sweep_dir: true,
            sweep_bar: 0.0,
            sweep_step: 0.25,
            events: Vec::new(),
        }
    }

    fn radiating(&self) -> bool {
        !(self.damaged || self.mode == OFF || self.mode == STBY)
    }

    pub fn range_index(&self) -> i64 {
        self.modes[self.mode].map_or(1, |m| m.idx)
    }

    pub fn range_m(&self) -> f64 {
        RANGE_M[(self.range_index().clamp(1, 6) - 1) as usize]
    }

    fn cone_cos(m: usize) -> f64 {
        if m == BORE { BORE_COS } else { CONE_COS }
    }

    /// The B-scope width (`FUN_004ad300`: 2·acos(cone cos)): 2π/3, 24° in BORE.
    pub fn scope_width(&self) -> f64 {
        2.0 * Self::cone_cos(self.mode).acos()
    }

    /// Has a lock (`FUN_004ada80`): not damaged, on; TWS: a selection counts; else the record's lock flag.
    pub fn has_lock(&self) -> bool {
        if !self.radiating() || self.sel_key.is_empty() {
            return false;
        }
        match self.mode {
            STT => self.stt.as_ref().is_some_and(|s| s.locked),
            TWS => true,
            _ => self.sel_locked,
        }
    }

    /// The locked (or TWS-selected) record — the target the HUD, the IR seeker and the gun use.
    pub fn locked(&self) -> Option<&Contact> {
        if !self.has_lock() {
            return None;
        }
        if self.mode == STT {
            return self.stt.as_ref();
        }
        let c = self.find(&self.sel_key)?;
        Some(self.live.as_ref().filter(|l| l.key == self.sel_key).unwrap_or(c))
    }

    pub fn find(&self, key: &str) -> Option<&Contact> {
        self.contacts.iter().find(|c| c.key == key)
    }

    fn find_mut(&mut self, key: &str) -> Option<&mut Contact> {
        self.contacts.iter_mut().find(|c| c.key == key)
    }

    fn notify(&mut self, key: &str, on: bool) {
        self.events.push(Event::Lock(key.to_string(), on));
    }

    fn illum(&mut self) {
        self.events.push(Event::IlluminationLost);
    }

    // --- per frame (FUN_004ad300 + the 2 s timer) -----------------------------------------------------

    pub fn update(&mut self, now: f64, inp: &Input) {
        if !self.radiating() {
            return;
        }
        let h = inp.own.yaw;
        let href = *self.href.get_or_insert(h);
        self.heading_shift = wrap_pi(href - h);
        self.sweep(now);
        self.stt_transitions(now, inp);
        if now >= self.next_scan {
            self.next_scan = now + SCAN_PERIOD;
            self.scan(now, inp);
        }
        if self.mode == STT {
            self.track(inp);
        }
        self.follow(inp);
        if self.dirty || self.mode == STT {
            self.heading_shift = 0.0;
            self.href = Some(h);
            self.dirty = false;
        }
    }

    /// The lock outside STT at its unit this frame (STT's record is re-made every frame by the track).
    fn follow(&mut self, inp: &Input) {
        self.live = None;
        if self.mode == STT || !self.has_lock() {
            return;
        }
        let (Some(c), Some(u)) = (self.find(&self.sel_key), inp.units.iter().find(|u| u.key == self.sel_key)) else {
            return;
        };
        let mut l = c.clone();
        l.pos = u.pos;
        l.alt = u.pos[2];
        l.dist = len(sub(u.pos, inp.own.pos));
        self.live = Some(l);
    }

    /// Antenna sweep (`FUN_004b0340`, cosmetic; one static state shared by the modes).
    fn sweep(&mut self, now: f64) {
        if self.mode == STT {
            self.antenna = (0.0, 0.0);
            return;
        }
        let period = if self.mode == BORE { SWEEP_BORE } else { SWEEP };
        let dt = now - self.sweep_t0;
        if dt < 0.0 {
            self.sweep_t0 = now;
            self.sweep_dir = true;
            self.sweep_bar = 0.0;
            self.sweep_step = 0.25;
            return;
        }
        let az = if self.sweep_dir { dt / period } else { 1.0 - dt / period };
        if now > self.sweep_t0 + period {
            self.sweep_bar += self.sweep_step;
            self.sweep_dir = !self.sweep_dir;
            if (self.sweep_bar >= 1.0 && self.sweep_step > 0.0) || (self.sweep_bar <= 0.0 && self.sweep_step < 0.0) {
                self.sweep_step = -self.sweep_step;
            }
            self.sweep_t0 = now;
        }
        self.antenna = (az.clamp(0.0, 1.0), self.sweep_bar.clamp(0.0, 1.0));
    }

    /// `FUN_004adde0` (every frame): an A-A lock outside TWS goes to STT; STT without a lock returns to BORE
    /// (key held) or the last A-A mode, and scans.
    fn stt_transitions(&mut self, now: f64, inp: &Input) {
        if self.mode != TWS && self.has_lock() && self.aa {
            if self.mode != STT {
                self.set_mode(STT);
            }
            return;
        }
        if self.mode == STT && !self.has_lock() {
            self.illum();
            self.set_mode(if self.bore_held { BORE } else { self.last_aa });
            self.scan(now, inp);
        }
    }

    /// SetMode (`FUN_004ad880`): STT takes the current mode's selected record and locks it; leaving STT drops
    /// the semi-active missiles' guidance (`FUN_00458130`).
    fn set_mode(&mut self, m: usize) {
        if self.mode == STT && m != STT {
            self.illum();
        }
        if m == STT {
            let r = if self.mode != TWS { self.locked() } else { self.find(&self.sel_key) };
            let Some(mut r) = r.cloned() else {
                return;
            };
            r.locked = true;
            self.stt = Some(r);
            self.sel_locked = true;
            let k = self.sel_key.clone();
            self.notify(&k, true);
        }
        self.mode = m;
        self.dirty = true;
    }

    /// `FUN_004ad880(2)` from a semi-active (610) launch with a target: the radar locks its selected record (STT).
    pub fn lock_stt(&mut self) {
        if self.damaged || self.mode == STT || self.modes[STT].is_none() {
            return;
        }
        self.set_mode(STT);
    }

    // --- the scan (FUN_004af300) -------------------------------------------------------------------

    fn class_ok(m: usize, u: &Unit) -> bool {
        match m {
            MAP => MAP_CLASSES.contains(&u.klass),
            GMT => GMT_CLASSES.contains(&u.klass) && len(u.vel) > 0.0,
            _ => AIR_CLASSES.contains(&u.klass),
        }
    }

    pub fn scan(&mut self, now: f64, inp: &Input) {
        self.next_scan = now + SCAN_PERIOD;
        self.dirty = true;
        self.live = None;
        if !self.radiating() || self.mode == STT {
            return; // STT's list is its track (FUN_004b1300 every frame)
        }
        let o = inp.own;
        let (ax, ay) = norm2(o.fwd[0], o.fwd[1]);
        let air = !(self.mode == GMT || self.mode == MAP);
        let r = self.range_m();
        let c = [o.pos[0] + ax * r / 2.0, o.pos[1] + ay * r / 2.0, o.pos[2]];
        let rd = self.modes[self.mode].map_or(0.0, |m| m.nm) * NM;
        let cone = Self::cone_cos(self.mode);
        let old_key = self.sel_key.clone();
        let old_locked = self.sel_locked;
        let mut list: Vec<Contact> = Vec::new();
        let mut old_seen: Option<&Unit> = None;
        for u in inp.units {
            if u.state == 4 || u.state == 5 {
                continue;
            }
            let d = sub(u.pos, c);
            if d[0] * d[0] + d[1] * d[1] + d[2] * d[2] >= QUERY_K * (u.coll_radius + r / 2.0).powi(2) {
                continue;
            }
            if !Self::class_ok(self.mode, u) {
                continue;
            }
            if u.key == old_key {
                old_seen = Some(u);
            }
            if len(sub(u.pos, o.pos)) > rd {
                continue; // (ECM rules: no jammer on either side yet, docs/radar.md)
            }
            if let Some(rec) = hit(u, &o, air, cone, inp.ground) {
                insert(&mut list, rec);
            }
        }
        // The old selection is kept when its unit is still in the query, re-tested without the range.
        if let Some(u) = old_seen {
            if !old_key.is_empty() && !list.iter().any(|c| c.key == old_key) {
                if let Some(rec) = hit(u, &o, air, cone, inp.ground) {
                    insert(&mut list, rec);
                }
            }
        }
        self.contacts = list;
        // The cursor: the old id if present, else the nearest; it becomes "selected" (and the target's RWR
        // hears a lock: on-lock notify).
        let cur = if self.contacts.iter().any(|c| c.key == old_key) {
            old_key.clone()
        } else {
            self.contacts.first().map(|c| c.key.clone()).unwrap_or_default()
        };
        if cur != old_key {
            if !old_key.is_empty() {
                self.notify(&old_key, false);
            }
            self.sel_locked = false;
            self.sel_key = cur.clone();
            if !cur.is_empty() {
                self.notify(&cur, true);
            }
        } else {
            self.sel_locked = old_locked && !cur.is_empty();
        }
        let (sel, locked) = (self.sel_key.clone(), self.sel_locked);
        for c in &mut self.contacts {
            c.selected = c.key == sel;
            c.locked = c.selected && locked;
        }
        // BORE / ACM lock the selection (FUN_004b19c0 → FUN_004b06b0).
        if (self.mode == BORE || self.mode == ACM) && !sel.is_empty() {
            self.sel_locked = true;
            if let Some(c) = self.find_mut(&sel) {
                c.locked = true;
            }
        }
    }

    // --- STT track (FUN_004b1300, every frame) ------------------------------------------------------

    fn track(&mut self, inp: &Input) {
        let Some(key) = self.stt.as_ref().filter(|s| s.locked).map(|s| s.key.clone()) else {
            return;
        };
        let stt = self.modes[STT].expect("STT range");
        let rec = inp
            .units
            .iter()
            .find(|u| u.key == key)
            .filter(|u| u.state != 4 && u.state != 5 && len(sub(u.pos, inp.own.pos)) <= stt.nm * NM)
            .and_then(|u| hit(u, &inp.own, true, CONE_COS, inp.ground));
        let Some(mut r) = rec else {
            self.unlock();
            return;
        };
        r.locked = true;
        r.selected = true;
        // Auto-range (FUN_004b1590).
        let m = self.modes[STT].as_mut().expect("STT range");
        while m.idx > 1 && r.dist < AUTO_DOWN * RANGE_M[(m.idx - 1) as usize] {
            m.idx -= 1;
        }
        while m.idx < m.max && r.dist > AUTO_UP * RANGE_M[(m.idx - 1) as usize] {
            m.idx += 1;
        }
        self.stt = Some(r.clone());
        self.contacts = vec![r];
    }

    fn unlock(&mut self) {
        if !self.sel_key.is_empty() {
            let k = self.sel_key.clone();
            self.notify(&k, false);
        }
        self.stt = None;
        self.sel_locked = false;
        for c in &mut self.contacts {
            c.locked = false;
        }
        self.dirty = true;
    }

    // --- keys (FUN_0044a240) ---------------------------------------------------------------------

    /// Q (event 0x24, `FUN_004ad6f0`): A-A LRS → TWS → ACM → LRS (missing modes skipped; leaving STT unlocks),
    /// A-G GMT ↔ MAP; also turns the radar on.
    pub fn cycle_mode(&mut self, now: f64, inp: &Input) {
        if self.damaged {
            return;
        }
        if self.aa {
            if self.mode == STT {
                self.deselect(now, inp);
            }
            let order = [LRS, TWS, ACM];
            let mut i = order.iter().position(|&m| m == self.last_aa).map_or(-1, |i| i as i64);
            for _ in 0..3 {
                i = (i + 1).rem_euclid(3);
                if self.modes[order[i as usize]].is_some() {
                    break;
                }
            }
            self.last_aa = order[i as usize];
            self.mode = self.last_aa;
        } else {
            self.last_ag = if self.last_ag == GMT { MAP } else { GMT };
            self.mode = self.last_ag;
        }
        self.on_tail(now, inp);
        self.illum();
    }

    /// R (event 0x2b, `FUN_004ad8f0`): A-G or off → the last A-A mode; else the last A-G mode.
    pub fn toggle_aa_ag(&mut self, now: f64, inp: &Input) {
        if self.damaged {
            return;
        }
        self.unlock();
        self.sel_key.clear();
        if !self.aa || self.off {
            self.aa = true;
            self.mode = self.last_aa;
        } else {
            self.aa = false;
            self.mode = self.last_ag;
        }
        self.on_tail(now, inp);
        self.illum();
    }

    /// The tail of Q / R: an off radar starts (lists cleared), then a scan.
    fn on_tail(&mut self, now: f64, inp: &Input) {
        if self.off {
            self.off = false;
            self.contacts.clear();
            self.sel_key.clear();
        }
        self.scan(now, inp);
    }

    /// S (event 0x2c, `FUN_004ad9c0`): STBY; from on: off first (lists cleared), then STBY.
    pub fn standby(&mut self) {
        if self.damaged {
            return;
        }
        if !self.off {
            self.unlock();
            self.contacts.clear();
            self.sel_key.clear();
            self.off = true;
            self.aa = true;
        }
        self.mode = STBY;
        self.dirty = true;
        self.illum();
    }

    /// '.' / ',' (events 0x21 / 0x22, `FUN_004adb70`): range index ±1 within [1, max] (STT: none), then a scan.
    pub fn step_range(&mut self, d: i64, now: f64, inp: &Input) {
        if !self.radiating() || self.mode == STT {
            return;
        }
        if let Some(m) = self.modes[self.mode].as_mut() {
            m.idx = (m.idx + d).clamp(1, m.max);
        }
        self.scan(now, inp);
    }

    /// '\' down / up (events 0x2d / 0x2e): BORE while held (A-A only), back to the saved mode.
    pub fn boresight(&mut self, down: bool) {
        if !self.aa || self.damaged {
            return;
        }
        if down {
            if !matches!(self.mode, OFF | STBY | STT) {
                self.bore_return = self.mode;
                self.bore_held = true;
                self.mode = BORE;
                self.dirty = true;
            }
        } else if !matches!(self.mode, OFF | STBY) {
            if self.mode != STT {
                self.mode = self.bore_return;
            }
            self.bore_held = false;
            self.dirty = true;
        }
    }

    /// Return / Shift+Return (events 0x26 / 0x27, `FUN_004aefd0`): the cursor walks to the next (farther) or
    /// previous contact, wrapping; it becomes the selection; LRS also locks it (→ STT); STT unlocks.
    pub fn next_target(&mut self, forward: bool) {
        if !self.radiating() {
            return;
        }
        self.illum(); // FUN_004adbc0
        if self.mode == STT {
            self.unlock();
            return;
        }
        let n = self.contacts.len();
        if n <= 1 {
            return; // (a single contact is locked by clicking its blip, event 0x2a)
        }
        let i = self.contacts.iter().rposition(|c| c.key == self.sel_key).map_or(-1, |i| i as i64);
        let key = self.contacts[(i + if forward { 1 } else { -1 }).rem_euclid(n as i64) as usize].key.clone();
        if key != self.sel_key {
            if !self.sel_key.is_empty() {
                let k = self.sel_key.clone();
                self.notify(&k, false);
            }
            self.sel_key = key.clone();
            self.sel_locked = false;
            self.notify(&key, true);
        }
        for c in &mut self.contacts {
            c.selected = c.key == key;
            c.locked = false;
        }
        if self.mode == LRS {
            self.lock_key(&key);
        }
        self.dirty = true;
    }

    /// Event 0x2a (`FUN_004adca0`, a click on a blip): lock that contact; from TWS straight to STT.
    pub fn lock_key(&mut self, key: &str) -> bool {
        if self.radiating() {
            self.illum(); // FUN_004adca0
        }
        if self.find(key).is_none() {
            return false;
        }
        if key != self.sel_key && !self.sel_key.is_empty() {
            let k = self.sel_key.clone();
            self.notify(&k, false);
        }
        self.sel_key = key.to_string();
        self.sel_locked = true;
        for c in &mut self.contacts {
            c.selected = c.key == key;
            c.locked = c.selected;
        }
        self.notify(key, true);
        if self.mode == TWS {
            self.set_mode(STT);
        }
        self.dirty = true;
        true
    }

    /// Backspace (event 0x31, `FUN_004add60`): drop the lock (STT → the last A-A mode on the next frame); without
    /// a lock it clears the designated point (the EXP flag stays).
    pub fn deselect(&mut self, now: f64, inp: &Input) {
        if !self.has_lock() {
            self.designated = false;
            self.desig = [0.0; 3];
            return;
        }
        self.unlock();
        self.illum();
        self.stt_transitions(now, inp);
    }

    /// Event 0x2f (`FUN_004ade90`, a MAP page click off the contacts): a lock is dropped first, then the point
    /// (X, Y, terrain height) is designated.
    pub fn designate(&mut self, p: V3, now: f64, inp: &Input) {
        if self.has_lock() {
            self.deselect(now, inp);
        }
        self.desig = p;
        self.designated = true;
        self.dirty = true;
    }

    /// Event 0x30 (`FUN_004ade70`, MAP page OSB 3): NORM ↔ EXP, only with a designated point.
    pub fn toggle_exp(&mut self) {
        if self.designated {
            self.exp = !self.exp;
            self.dirty = true;
        }
    }

    /// Damage (cases 0xf / 0x13 / 0x15, `FUN_004adb20`): off, every call a no-op.
    pub fn set_damaged(&mut self, on: bool) {
        if on && !self.damaged {
            self.unlock();
            self.contacts.clear();
            self.sel_key.clear();
            self.off = true;
            self.mode = OFF;
        }
        self.damaged = on;
        self.dirty = true;
    }
}

/// The hit test (`FUN_004aeb90`) and the record: air modes skip targets below 30 m AGL; the horizontal cone about
/// the antenna only (no elevation limit); terrain line of sight (ends +1.5 m).
fn hit(u: &Unit, o: &Own, air: bool, cone: f64, ground: &dyn Fn(V3) -> Option<f64>) -> Option<Contact> {
    let t = u.pos;
    if air && ground(t).is_some_and(|g| t[2] < g + MIN_AGL) {
        return None;
    }
    let d = sub(t, o.pos);
    let dist = len(d);
    if dist < 1.0 {
        return None;
    }
    let hd = norm2(d[0], d[1]);
    let ant = norm2(o.fwd[0], o.fwd[1]);
    let c = hd.0 * ant.0 + hd.1 * ant.1;
    if c < cone {
        return None;
    }
    let mut az = c.clamp(-1.0, 1.0).acos();
    if o.yaw.cos() * hd.0 - o.yaw.sin() * hd.1 < 0.0 {
        az = -az;
    }
    let pitch = o.fwd[2].clamp(-1.0, 1.0).asin();
    let el = (d[2] / dist).clamp(-1.0, 1.0).asin() - pitch;
    let raise = |p: V3| [p[0], p[1], p[2] + LOS_RAISE];
    if !line_of_sight(raise(o.pos), raise(t), ground) {
        return None;
    }
    let beta = d[0].atan2(d[1]);
    Some(Contact {
        key: u.key.clone(),
        pos: t,
        heading: u.heading,
        locked: false,
        selected: false,
        hostile: u.hostile,
        prio: 100.0 / dist,
        aspect: wrap_pi(u.heading.to_radians() - beta),
        az,
        el,
        dist,
        speed: len(u.vel) * KT,
        type_code: u.type_code,
        alt: t[2],
    })
}

/// Terrain line of sight (`FUN_004020d0`; ours samples the segment every 100 m: the original's sampling is
/// UNCERTAIN).
pub fn line_of_sight(a: V3, b: V3, ground: &dyn Fn(V3) -> Option<f64>) -> bool {
    let d = sub(b, a);
    let n = (len(d) / 100.0) as i64;
    (1..n).all(|i| {
        let f = i as f64 / n as f64;
        let p = [a[0] + d[0] * f, a[1] + d[1] * f, a[2] + d[2] * f];
        ground(p).is_none_or(|g| p[2] >= g)
    })
}

/// Sorted insert, 15 at most (`FUN_004b08e0`): when full, a record replaces the last only when its priority is
/// strictly higher.
fn insert(list: &mut Vec<Contact>, r: Contact) {
    if list.len() >= MAX_CONTACTS {
        if r.prio <= list[list.len() - 1].prio {
            return;
        }
        list.pop();
    }
    let i = list.iter().position(|c| c.prio < r.prio).unwrap_or(list.len());
    list.insert(i, r);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn no_ground(_: V3) -> Option<f64> {
        None
    }

    fn jet(key: &str, pos: V3) -> Unit {
        Unit { key: key.into(), pos, vel: [0.0, 200.0, 0.0], klass: 1, state: 1, hostile: true, ..Default::default() }
    }

    const OWN: Own = Own { pos: [0.0, 0.0, 5000.0], fwd: [0.0, 1.0, 0.0], yaw: 0.0 };

    fn inp(units: &[Unit]) -> Input<'_> {
        Input { own: OWN, units, ground: &no_ground }
    }

    #[test]
    fn f16_table_range_and_cone() {
        let mut r = Radar::new(1, 0.0);
        assert_eq!(r.mode, OFF);
        assert_eq!(r.modes[LRS], Some(ModeRange { max: 5, nm: 45.0, idx: 4 }));
        let units = [jet("t", [0.0, 30000.0, 5000.0]), jet("u", [0.0, 50.0 * 1854.0, 5000.0])];
        r.toggle_aa_ag(0.0, &inp(&units));
        assert_eq!(r.mode, LRS);
        assert_eq!(r.contacts.iter().map(|c| c.key.as_str()).collect::<Vec<_>>(), ["t"]);
        assert!(r.contacts[0].aspect.abs() < 0.01, "flying away: aspect 0 (tail)");
        // The selection beyond 45 NM is kept (re-tested without the range).
        let units = [jet("t", [0.0, 45.0 * 1854.0 + 500.0, 5000.0])];
        r.step_range(2, 1.0, &inp(&units));
        assert_eq!(r.contacts.len(), 1);
        // 65° off the nose: outside the 60° cone.
        let a = 65f64.to_radians();
        let units = [jet("t", [30000.0 * a.sin(), 30000.0 * a.cos(), 5000.0])];
        r.scan(2.0, &inp(&units));
        assert!(r.contacts.is_empty());
        assert!((r.scope_width() - 2.0 * PI / 3.0).abs() < 1e-9);
    }

    #[test]
    fn list_keeps_the_15_nearest() {
        let mut list = Vec::new();
        for i in 0..20 {
            let d = 1000.0 * (20 - i) as f64;
            insert(&mut list, Contact { key: i.to_string(), prio: 100.0 / d, ..Default::default() });
        }
        assert_eq!(list.len(), MAX_CONTACTS);
        assert!(list.windows(2).all(|w| w[0].prio >= w[1].prio));
        assert_eq!(list[0].key, "19");
    }

    #[test]
    fn stt_auto_range_and_lost_lock() {
        let mut r = Radar::new(1, 0.0);
        let mut units = vec![jet("t", [0.0, 20000.0, 5000.0])];
        r.toggle_aa_ag(0.0, &inp(&units));
        assert!(r.lock_key("t"));
        r.update(0.05, &inp(&units));
        assert_eq!(r.mode, STT);
        assert_eq!(r.range_index(), 3, "20 km → the 20 NM scale");
        assert!(r.events.contains(&Event::Lock("t".into(), true)));
        // Behind the jet: the lock drops, back to LRS.
        units[0].pos = [0.0, -20000.0, 5000.0];
        r.update(0.10, &inp(&units));
        r.update(0.15, &inp(&units));
        assert_eq!(r.mode, LRS);
        assert!(r.locked().is_none());
        assert!(r.events.contains(&Event::IlluminationLost));
    }

    #[test]
    fn acm_and_bore_lock_at_once() {
        let mut r = Radar::new(1, 0.0);
        let units = [jet("t", [0.0, 5000.0, 5000.0])];
        r.toggle_aa_ag(0.0, &inp(&units));
        r.cycle_mode(0.0, &inp(&units)); // TWS
        r.cycle_mode(0.0, &inp(&units)); // ACM: the selection locks
        assert_eq!(r.mode, ACM);
        assert!(r.sel_locked);
        r.update(0.05, &inp(&units));
        assert_eq!(r.mode, STT);
        // BORE: 12° cone.
        assert!((Radar::cone_cos(BORE) - 12f64.to_radians().cos()).abs() < 1e-6);
    }

    #[test]
    fn tws_lock_follows_the_unit_between_scans() {
        let mut r = Radar::new(1, 0.0);
        let mut units = vec![jet("t", [0.0, 20000.0, 5000.0])];
        r.toggle_aa_ag(0.0, &inp(&units));
        r.cycle_mode(0.0, &inp(&units)); // TWS: the nearest is selected = locked
        assert_eq!(r.mode, TWS);
        units[0].pos = [300.0, 20400.0, 5000.0];
        r.update(0.05, &inp(&units));
        let l = r.locked().expect("TWS lock");
        assert_eq!(l.pos, units[0].pos);
        assert!((l.dist - len(sub(units[0].pos, OWN.pos))).abs() < 1e-9);
        assert_eq!(r.find("t").unwrap().pos, [0.0, 20000.0, 5000.0], "the blip waits for the next scan");
    }

    #[test]
    fn terrain_hides_and_low_targets_skip() {
        let hill = |p: V3| Some(if p[1] > 9000.0 && p[1] < 11000.0 { 6000.0 } else { 0.0 });
        assert!(!line_of_sight([0.0, 0.0, 5000.0], [0.0, 20000.0, 5000.0], &hill));
        assert!(line_of_sight([0.0, 0.0, 5000.0], [0.0, 20000.0, 5000.0], &no_ground));
        let o = OWN;
        let flat = |_: V3| Some(4990.0);
        assert!(hit(&jet("t", [0.0, 20000.0, 5000.0]), &o, true, CONE_COS, &flat).is_none(), "10 m AGL");
        assert!(hit(&jet("t", [0.0, 20000.0, 5000.0]), &o, false, CONE_COS, &flat).is_some(), "ground modes see it");
    }
}
