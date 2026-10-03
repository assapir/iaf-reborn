//! The player's radar (docs/radar.md): the radar manager of the player controller (ctl+0x84, `FUN_004acc20`)
//! with its modes, the per-aircraft range tables, the scan (`FUN_004af300`, every 2.0 s and on events), the hit
//! test (`FUN_004aeb90`), the contact list (15, nearest first), the lock / designate keys and the STT track
//! (`FUN_004b1300`).
//!
//! World frame X east, Y north, Z up, metres, sim seconds. Every call that can scan takes the scene (`Input`);
//! the RWR lock notices and the semi-active missiles' illumination loss come out as `Event`s.

use crate::vec3::Vec3;
use std::f64::consts::PI;

/// Range scale of index 1..6 (`FUN_004b0020`, `0x603358..`: 5·2^(i−1) NM at 1851.87 m/NM).
pub const RANGE_M: [f64; 6] = [9259.372, 18518.744, 37037.488, 74074.977, 148149.95, 296299.9];
/// Detection NM → m (`0x603390`).
const NM: f64 = 1854.0;
/// Full rescan period (`DAT_0082f4a8` = 2.0 s).
const SCAN_PERIOD: f64 = 2.0;
/// Cone half-angles (cos): 60° every mode, 12° BORE (static init `0x603440..` / `0x6035d8`).
const CONE_COS: f64 = 0.5;
const BORE_COS: f64 = 0.97814760;
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
const MAX_CONTACTS: usize = 15;
/// m/s → kt (`0x600a70`).
const KT: f64 = 1.9427955;
/// Classes per mode filter (vt+0x3c): air `4b1c70`, MAP `4b0ce0`, GMT `4b0fc0` (moving only).
const AIR_CLASSES: [i64; 4] = [0x1c, 3, 2, 1];
const MAP_CLASSES: [i64; 11] = [10, 8, 9, 0xb, 0xd, 0x1d, 0x1e, 5, 6, 0xf, 0x10];
const GMT_CLASSES: [i64; 8] = [5, 6, 0xf, 0x10, 8, 9, 10, 0xb];

/// The radar mode (+0x30); the discriminants are the original's.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Off = 0,
    Standby = 1,
    Stt = 2,
    Bore = 3,
    Lrs = 4,
    Tws = 5,
    Acm = 6,
    Gmt = 7,
    Map = 8,
}

impl Mode {
    pub const ALL: [Mode; 9] =
        [Mode::Off, Mode::Standby, Mode::Stt, Mode::Bore, Mode::Lrs, Mode::Tws, Mode::Acm, Mode::Gmt, Mode::Map];

    /// OFF and STBY do not radiate (+0x44).
    pub fn radiating(self) -> bool {
        !matches!(self, Mode::Off | Mode::Standby)
    }

    pub fn air_to_ground(self) -> bool {
        matches!(self, Mode::Gmt | Mode::Map)
    }

    fn cone_cos(self) -> f64 {
        if self == Mode::Bore { BORE_COS } else { CONE_COS }
    }

    /// The class filter of the mode (vt+0x3c).
    fn sees(self, u: &Unit) -> bool {
        match self {
            Mode::Map => MAP_CLASSES.contains(&u.class),
            Mode::Gmt => GMT_CLASSES.contains(&u.class) && u.vel != Vec3::ZERO,
            _ => AIR_CLASSES.contains(&u.class),
        }
    }
}

/// A mode's range: the largest scale index, the detection range (NM) and the current scale index 1..max.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Range {
    pub max: u8,
    pub nm: f64,
    pub index: u8,
}

impl Range {
    /// A mode starts at min(max index, 4).
    fn new(max: u8, nm: f64) -> Self {
        Range { max, nm, index: max.min(4) }
    }

    pub fn scale_m(&self) -> f64 {
        RANGE_M[usize::from(self.index.clamp(1, 6)) - 1]
    }

    fn detection_m(&self) -> f64 {
        self.nm * NM
    }
}

/// (max range index, detection NM) per mode, in the tables' order LRS, TWS, ACM, BORE, MAP, GMT; (0, 0) = no such mode.
type Row = [(u8, f64); 6];

/// Per cockpit index (`FUN_00447e70`: 0 F-15, 1 F-16, 2 F-4-2000, 3 Lavi, 4 Kfir, 5 F-4E, 6 Mirage, 7 MiG-29,
/// 8 MiG-23): A-A table `0x640a74` and A-G table `0x640bbc`.
const TABLES: [Row; 9] = [
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

/// The modes a jet's radar has, with their ranges.
#[derive(Clone, Copy, Debug)]
pub struct Ranges([Option<Range>; 9]);

impl Ranges {
    /// The row of cockpit index `cockpit`; `lrs_nm` overrides the LRS / STT detection range (Weapon data Real).
    /// STT takes LRS's (max index, NM), else ACM's; BORE starts at its largest scale.
    fn new(cockpit: usize, lrs_nm: Option<f64>) -> Self {
        let row = TABLES[cockpit.min(TABLES.len() - 1)];
        let mut r = [None; 9];
        let modes = [Mode::Lrs, Mode::Tws, Mode::Acm, Mode::Bore, Mode::Map, Mode::Gmt];
        for (mode, (max, nm)) in modes.into_iter().zip(row) {
            if max == 0 {
                continue;
            }
            let nm = if mode == Mode::Lrs { lrs_nm.unwrap_or(nm) } else { nm };
            let mut range = Range::new(max, nm);
            if mode == Mode::Bore {
                range.index = max;
            }
            r[mode as usize] = Some(range);
        }
        let src = r[Mode::Lrs as usize].or(r[Mode::Acm as usize]).unwrap_or(Range::new(2, 10.0));
        r[Mode::Stt as usize] = Some(Range::new(src.max, src.nm));
        Ranges(r)
    }

    pub fn get(&self, mode: Mode) -> Option<&Range> {
        self.0[mode as usize].as_ref()
    }

    fn get_mut(&mut self, mode: Mode) -> Option<&mut Range> {
        self.0[mode as usize].as_mut()
    }

    pub fn iter(&self) -> impl Iterator<Item = (Mode, &Range)> {
        Mode::ALL.into_iter().filter_map(|m| self.get(m).map(|r| (m, r)))
    }
}

/// A unit the radar can see.
#[derive(Clone, Debug, Default)]
pub struct Unit {
    pub key: String,
    pub pos: Vec3,
    pub vel: Vec3,
    /// vt+0x3c class.
    pub class: i64,
    /// 4 / 5 = destroyed / dying.
    pub state: i64,
    pub coll_radius: f64,
    /// Degrees clockwise from north.
    pub heading: f64,
    pub type_code: i64,
    pub hostile: bool,
}

impl Unit {
    fn alive(&self) -> bool {
        !matches!(self.state, 4 | 5)
    }
}

/// The own jet: position, forward axis, yaw (rad, atan2(fwd.x, fwd.y)).
#[derive(Clone, Copy, Debug, Default)]
pub struct Own {
    pub pos: Vec3,
    pub fwd: Vec3,
    pub yaw: f64,
}

/// What a call sees: the own jet, the units and the terrain height at a world point (None: no terrain there).
pub struct Input<'a> {
    pub own: Own,
    pub units: &'a [Unit],
    pub terrain: &'a dyn Fn(Vec3) -> Option<f64>,
}

impl Input<'_> {
    fn unit(&self, key: &str) -> Option<&Unit> {
        self.units.iter().find(|u| u.key == key)
    }
}

/// A contact record (`FUN_004aeb90`).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Contact {
    pub key: String,
    pub pos: Vec3,
    /// Degrees clockwise from north.
    pub heading: f64,
    pub hostile: bool,
    /// Target heading − line-of-sight bearing (rad, ±π).
    pub aspect: f64,
    /// Off the nose (rad; + right / up).
    pub az: f64,
    pub el: f64,
    pub dist: f64,
    pub speed_kt: f64,
    pub type_code: i64,
}

impl Contact {
    /// The list priority: 100 / distance.
    pub fn priority(&self) -> f64 {
        100.0 / self.dist
    }
}

/// The selected (TWS: tracked) contact's unit (+0x58) and whether it is locked (+0x14).
#[derive(Clone, Debug, PartialEq)]
pub struct Selection {
    pub key: String,
    pub locked: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Event {
    /// The target's RWR hears a lock (on-lock / on-unlock `4b0510` / `4b04d0`).
    Lock { key: String, on: bool },
    /// `FUN_00458130`: the semi-active missiles lose their guidance.
    IlluminationLost,
}

/// The antenna sweep (`FUN_004b0340`, cosmetic; one static state shared by the modes): the azimuth caret 0 → 1 → 0
/// per period, the elevation bar stepping 0.25 per sweep and reversing at 0 / 1.
#[derive(Clone, Copy, Debug)]
struct Sweep {
    t0: f64,
    rightwards: bool,
    bar: f64,
    step: f64,
}

impl Default for Sweep {
    fn default() -> Self {
        Sweep { t0: f64::INFINITY, rightwards: true, bar: 0.0, step: 0.25 }
    }
}

impl Sweep {
    /// The carets (az, el) 0..1 at `now`, None on a restart (time went back).
    fn advance(&mut self, now: f64, period: f64) -> Option<(f64, f64)> {
        let dt = now - self.t0;
        if dt < 0.0 {
            *self = Sweep { t0: now, ..Sweep::default() };
            return None;
        }
        let az = if self.rightwards { dt / period } else { 1.0 - dt / period };
        if now > self.t0 + period {
            self.bar += self.step;
            self.rightwards = !self.rightwards;
            if (self.bar >= 1.0 && self.step > 0.0) || (self.bar <= 0.0 && self.step < 0.0) {
                self.step = -self.step;
            }
            self.t0 = now;
        }
        Some((az.clamp(0.0, 1.0), self.bar.clamp(0.0, 1.0)))
    }
}

/// GDScript wrapf(x, −π, π).
fn wrap_pi(x: f64) -> f64 {
    x - 2.0 * PI * ((x + PI) / (2.0 * PI)).floor()
}

#[derive(Clone, Debug)]
pub struct Radar {
    ranges: Ranges,
    mode: Mode,
    /// +0x34 / +0x38: the last A-A and A-G modes; +0x3c: the mode BORE returns to.
    last_aa: Mode,
    last_ag: Mode,
    bore_return: Mode,
    /// +0x40.
    air_to_air: bool,
    /// +0x48: damaged radars stay off.
    damaged: bool,
    /// +0x54: the boresight key is held.
    bore_held: bool,
    /// +4 == 5: the cockpit's copy is out of date (the heading shift restarts).
    dirty: bool,
    /// The contact list, highest priority first.
    contacts: Vec<Contact>,
    selection: Option<Selection>,
    /// STT: the locked record (re-made every frame by the track).
    stt: Option<Contact>,
    /// Outside STT: the locked (TWS: selected) record at its unit this frame (`FUN_0044e370` reads the target's live
    /// position; the contact list only changes on a scan).
    live: Option<Contact>,
    /// Carets (az, el) 0..1 (state+0xa0c / +0xa10).
    antenna: (f64, f64),
    sweep: Sweep,
    /// state+0xa14: the own heading change since the last push to the cockpit (rad), so the B-scope blips turn
    /// with the jet between scans.
    heading_shift: f64,
    heading_ref: Option<f64>,
    /// The designated ground point (event 0x2f: X, Y, terrain height) and the MAP page's EXP flag (+0x4c).
    designated: Option<Vec3>,
    expanded: bool,
    next_scan: f64,
    events: Vec<Event>,
}

impl Radar {
    /// Create (`FUN_004ace60`) for cockpit index `cockpit` (`FUN_00447e70`); `lrs_nm`: the LRS / STT detection range
    /// with Weapon data Real. The radar starts OFF in A-A.
    pub fn new(cockpit: usize, lrs_nm: Option<f64>) -> Self {
        Radar {
            ranges: Ranges::new(cockpit, lrs_nm),
            mode: Mode::Off,
            last_aa: Mode::Lrs,
            last_ag: Mode::Gmt,
            bore_return: Mode::Lrs,
            air_to_air: true,
            damaged: false,
            bore_held: false,
            dirty: false,
            contacts: Vec::new(),
            selection: None,
            stt: None,
            live: None,
            antenna: (0.0, 0.0),
            sweep: Sweep::default(),
            heading_shift: 0.0,
            heading_ref: None,
            designated: None,
            expanded: false,
            next_scan: 0.0,
            events: Vec::new(),
        }
    }

    // --- read-out ------------------------------------------------------------------------------------

    pub fn mode(&self) -> Mode {
        self.mode
    }
    pub fn last_aa(&self) -> Mode {
        self.last_aa
    }
    pub fn air_to_air(&self) -> bool {
        self.air_to_air
    }
    pub fn damaged(&self) -> bool {
        self.damaged
    }
    pub fn bore_held(&self) -> bool {
        self.bore_held
    }
    pub fn ranges(&self) -> &Ranges {
        &self.ranges
    }
    pub fn contacts(&self) -> &[Contact] {
        &self.contacts
    }
    pub fn selection(&self) -> Option<&Selection> {
        self.selection.as_ref()
    }
    pub fn stt(&self) -> Option<&Contact> {
        self.stt.as_ref()
    }
    pub fn antenna(&self) -> (f64, f64) {
        self.antenna
    }
    pub fn heading_shift(&self) -> f64 {
        self.heading_shift
    }
    pub fn designated(&self) -> Option<Vec3> {
        self.designated
    }
    pub fn expanded(&self) -> bool {
        self.expanded
    }

    /// The events since the last call, in order.
    pub fn take_events(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.events)
    }

    fn radiating(&self) -> bool {
        !self.damaged && self.mode.radiating()
    }

    /// The current mode's range scale index (1 without one).
    pub fn range_index(&self) -> u8 {
        self.ranges.get(self.mode).map_or(1, |r| r.index)
    }

    pub fn range_m(&self) -> f64 {
        RANGE_M[usize::from(self.range_index().clamp(1, 6)) - 1]
    }

    /// The B-scope width (`FUN_004ad300`: 2·acos(cone cos)): 2π/3, 24° in BORE.
    pub fn scope_width(&self) -> f64 {
        2.0 * self.mode.cone_cos().acos()
    }

    pub fn is_selected(&self, c: &Contact) -> bool {
        self.selection.as_ref().is_some_and(|s| s.key == c.key)
    }

    pub fn is_locked(&self, c: &Contact) -> bool {
        self.selection.as_ref().is_some_and(|s| s.locked && s.key == c.key)
    }

    /// Has a lock (`FUN_004ada80`): not damaged, on; TWS: a selection counts; else the selection's lock flag.
    pub fn has_lock(&self) -> bool {
        self.radiating()
            && self.selection.as_ref().is_some_and(|s| match self.mode {
                Mode::Stt => self.stt.is_some(),
                Mode::Tws => true,
                _ => s.locked,
            })
    }

    /// The locked (or TWS-selected) record — the target the HUD, the IR seeker and the gun use; outside STT at its
    /// unit's position this frame.
    pub fn locked(&self) -> Option<&Contact> {
        if !self.has_lock() {
            return None;
        }
        if self.mode == Mode::Stt {
            return self.stt.as_ref();
        }
        let c = self.selected_contact()?;
        Some(self.live.as_ref().filter(|l| l.key == c.key).unwrap_or(c))
    }

    pub fn contact(&self, key: &str) -> Option<&Contact> {
        self.contacts.iter().find(|c| c.key == key)
    }

    fn selected_contact(&self) -> Option<&Contact> {
        self.contact(&self.selection.as_ref()?.key)
    }

    fn notify(&mut self, key: &str, on: bool) {
        self.events.push(Event::Lock { key: key.to_owned(), on });
    }

    fn illumination_lost(&mut self) {
        self.events.push(Event::IlluminationLost);
    }

    // --- per frame (FUN_004ad300 + the 2 s timer) -----------------------------------------------------

    pub fn update(&mut self, now: f64, input: &Input) {
        if !self.radiating() {
            return;
        }
        let yaw = input.own.yaw;
        let reference = *self.heading_ref.get_or_insert(yaw);
        self.heading_shift = wrap_pi(reference - yaw);
        if self.mode == Mode::Stt {
            self.antenna = (0.0, 0.0);
        } else if let Some(a) = self.sweep.advance(now, if self.mode == Mode::Bore { SWEEP_BORE } else { SWEEP }) {
            self.antenna = a;
        }
        self.stt_transitions(now, input);
        if now >= self.next_scan {
            self.scan(now, input);
        }
        if self.mode == Mode::Stt {
            self.track(input);
        }
        self.follow(input);
        if self.dirty || self.mode == Mode::Stt {
            self.heading_shift = 0.0;
            self.heading_ref = Some(yaw);
            self.dirty = false;
        }
    }

    /// The lock outside STT at its unit this frame.
    fn follow(&mut self, input: &Input) {
        self.live = None;
        if self.mode == Mode::Stt || !self.has_lock() {
            return;
        }
        let Some(c) = self.selected_contact() else { return };
        let Some(u) = input.unit(&c.key) else { return };
        self.live = Some(Contact { pos: u.pos, dist: u.pos.distance(input.own.pos), ..c.clone() });
    }

    /// `FUN_004adde0` (every frame): an A-A lock outside TWS goes to STT; STT without a lock returns to BORE (key
    /// held) or the last A-A mode, and scans.
    fn stt_transitions(&mut self, now: f64, input: &Input) {
        if self.mode != Mode::Tws && self.has_lock() && self.air_to_air {
            if self.mode != Mode::Stt {
                self.set_mode(Mode::Stt);
            }
        } else if self.mode == Mode::Stt && !self.has_lock() {
            self.illumination_lost();
            self.set_mode(if self.bore_held { Mode::Bore } else { self.last_aa });
            self.scan(now, input);
        }
    }

    /// SetMode (`FUN_004ad880`): STT takes the current mode's selected record and locks it; leaving STT drops the
    /// semi-active missiles' guidance (`FUN_00458130`).
    fn set_mode(&mut self, mode: Mode) {
        if self.mode == Mode::Stt && mode != Mode::Stt {
            self.illumination_lost();
        }
        if mode == Mode::Stt {
            let target = if self.mode == Mode::Tws { self.selected_contact() } else { self.locked() };
            let Some(target) = target.cloned() else { return };
            self.notify(&target.key, true);
            self.selection = Some(Selection { key: target.key.clone(), locked: true });
            self.stt = Some(target);
        }
        self.mode = mode;
        self.dirty = true;
    }

    /// `FUN_004ad880(2)` from a semi-active (610) launch with a target: the radar locks its selection (STT).
    pub fn lock_stt(&mut self) {
        if !self.damaged && self.mode != Mode::Stt {
            self.set_mode(Mode::Stt);
        }
    }

    // --- the scan (FUN_004af300) -------------------------------------------------------------------

    pub fn scan(&mut self, now: f64, input: &Input) {
        self.next_scan = now + SCAN_PERIOD;
        self.dirty = true;
        self.live = None;
        if !self.radiating() || self.mode == Mode::Stt {
            return; // STT's list is its track
        }
        let own = &input.own;
        let air = !self.mode.air_to_ground();
        let cone = self.mode.cone_cos();
        let scale = self.range_m();
        let centre = own.pos + own.fwd.flat_dir() * (scale / 2.0);
        let detection = self.ranges.get(self.mode).map_or(0.0, Range::detection_m);
        let old = self.selection.take();
        let mut old_unit = None;
        let mut list = Vec::new();
        for u in input.units.iter().filter(|u| u.alive()) {
            if (u.pos - centre).length_squared() >= QUERY_K * (u.coll_radius + scale / 2.0).powi(2) || !self.mode.sees(u) {
                continue;
            }
            if old.as_ref().is_some_and(|s| s.key == u.key) {
                old_unit = Some(u);
            }
            // (ECM rules: no jammer on either side yet, docs/radar.md)
            if u.pos.distance(own.pos) <= detection {
                insert(&mut list, hit(u, own, air, cone, input.terrain));
            }
        }
        // The old selection is kept while its unit is in the query, re-tested without the range.
        if let Some(u) = old_unit.filter(|u| !list.iter().any(|c: &Contact| c.key == u.key)) {
            insert(&mut list, hit(u, own, air, cone, input.terrain));
        }
        self.contacts = list;
        // The cursor: the old selection if still listed, else the nearest (its RWR hears a lock).
        self.selection = match old {
            Some(s) if self.contact(&s.key).is_some() => Some(s),
            old => {
                if let Some(s) = old {
                    self.notify(&s.key, false);
                }
                let nearest = self.contacts.first().map(|c| c.key.clone());
                nearest.map(|key| {
                    self.notify(&key, true);
                    Selection { key, locked: false }
                })
            }
        };
        // BORE / ACM lock the selection (FUN_004b19c0 → FUN_004b06b0).
        if matches!(self.mode, Mode::Bore | Mode::Acm)
            && let Some(s) = &mut self.selection
        {
            s.locked = true;
        }
    }

    // --- STT track (FUN_004b1300, every frame) ------------------------------------------------------

    fn track(&mut self, input: &Input) {
        let Some(key) = self.stt.as_ref().map(|s| s.key.clone()) else { return };
        let Some(&range) = self.ranges.get(Mode::Stt) else { return };
        let record = input
            .unit(&key)
            .filter(|u| u.alive() && u.pos.distance(input.own.pos) <= range.detection_m())
            .and_then(|u| hit(u, &input.own, true, CONE_COS, input.terrain));
        let Some(record) = record else {
            self.unlock();
            return;
        };
        // Auto-range (FUN_004b1590).
        if let Some(r) = self.ranges.get_mut(Mode::Stt) {
            while r.index > 1 && record.dist < AUTO_DOWN * r.scale_m() {
                r.index -= 1;
            }
            while r.index < r.max && record.dist > AUTO_UP * r.scale_m() {
                r.index += 1;
            }
        }
        self.contacts = vec![record.clone()];
        self.stt = Some(record);
    }

    fn unlock(&mut self) {
        if let Some(s) = &mut self.selection {
            s.locked = false;
            let key = s.key.clone();
            self.notify(&key, false);
        }
        self.stt = None;
        self.dirty = true;
    }

    // --- keys (FUN_0044a240) ---------------------------------------------------------------------

    /// Q (event 0x24, `FUN_004ad6f0`): A-A LRS → TWS → ACM → LRS (missing modes skipped; leaving STT unlocks), A-G
    /// GMT ↔ MAP; also turns the radar on.
    pub fn cycle_mode(&mut self, now: f64, input: &Input) {
        if self.damaged {
            return;
        }
        let was_off = !self.mode.radiating();
        if self.air_to_air {
            if self.mode == Mode::Stt {
                self.deselect(now, input);
            }
            let order = [Mode::Lrs, Mode::Tws, Mode::Acm];
            let start = order.iter().position(|&m| m == self.last_aa).map_or(0, |i| i + 1);
            self.last_aa = (0..3)
                .map(|k| order[(start + k) % 3])
                .find(|&m| self.ranges.get(m).is_some())
                .unwrap_or(order[(start + 2) % 3]);
            self.mode = self.last_aa;
        } else {
            self.last_ag = if self.last_ag == Mode::Gmt { Mode::Map } else { Mode::Gmt };
            self.mode = self.last_ag;
        }
        self.switch_on(was_off, now, input);
        self.illumination_lost();
    }

    /// R (event 0x2b, `FUN_004ad8f0`): A-G or off → the last A-A mode; else the last A-G mode.
    pub fn toggle_aa_ag(&mut self, now: f64, input: &Input) {
        if self.damaged {
            return;
        }
        let was_off = !self.mode.radiating();
        self.unlock();
        self.selection = None;
        self.air_to_air = !self.air_to_air || was_off;
        self.mode = if self.air_to_air { self.last_aa } else { self.last_ag };
        self.switch_on(was_off, now, input);
        self.illumination_lost();
    }

    /// The tail of Q / R: an off radar starts (lists cleared), then a scan.
    fn switch_on(&mut self, was_off: bool, now: f64, input: &Input) {
        if was_off {
            self.contacts.clear();
            self.selection = None;
        }
        self.scan(now, input);
    }

    /// S (event 0x2c, `FUN_004ad9c0`): STBY; from on: off first (lists cleared), then STBY.
    pub fn standby(&mut self) {
        if self.damaged {
            return;
        }
        if self.mode.radiating() {
            self.unlock();
            self.contacts.clear();
            self.selection = None;
            self.air_to_air = true;
        }
        self.mode = Mode::Standby;
        self.dirty = true;
        self.illumination_lost();
    }

    /// '.' / ',' (events 0x21 / 0x22, `FUN_004adb70`): range index ±1 within [1, max] (STT: none), then a scan.
    pub fn step_range(&mut self, step: i8, now: f64, input: &Input) {
        if !self.radiating() || self.mode == Mode::Stt {
            return;
        }
        if let Some(r) = self.ranges.get_mut(self.mode) {
            r.index = r.index.saturating_add_signed(step).clamp(1, r.max);
        }
        self.scan(now, input);
    }

    /// '\' down / up (events 0x2d / 0x2e): BORE while held (A-A only), back to the saved mode.
    pub fn boresight(&mut self, down: bool) {
        if !self.air_to_air || self.damaged || !self.mode.radiating() {
            return;
        }
        if down {
            if self.mode != Mode::Stt {
                self.bore_return = self.mode;
                self.bore_held = true;
                self.mode = Mode::Bore;
                self.dirty = true;
            }
        } else {
            if self.mode != Mode::Stt {
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
        self.illumination_lost(); // FUN_004adbc0
        if self.mode == Mode::Stt {
            self.unlock();
            return;
        }
        let n = self.contacts.len();
        if n <= 1 {
            return; // (a single contact is locked by clicking its blip, event 0x2a)
        }
        let at = self.selection.as_ref().and_then(|s| self.contacts.iter().rposition(|c| c.key == s.key));
        let next = match (at, forward) {
            (Some(i), true) => (i + 1) % n,
            (Some(i), false) => (i + n - 1) % n,
            (None, true) => 0,
            (None, false) => n - 2,
        };
        let key = self.contacts[next].key.clone();
        if self.selection.as_ref().is_none_or(|s| s.key != key) {
            if let Some(s) = self.selection.take() {
                self.notify(&s.key, false);
            }
            self.notify(&key, true);
        }
        self.selection = Some(Selection { key: key.clone(), locked: false });
        if self.mode == Mode::Lrs {
            self.lock_key(&key);
        }
        self.dirty = true;
    }

    /// Event 0x2a (`FUN_004adca0`, a click on a blip): lock that contact; from TWS straight to STT.
    pub fn lock_key(&mut self, key: &str) -> bool {
        if self.radiating() {
            self.illumination_lost();
        }
        if self.contact(key).is_none() {
            return false;
        }
        if let Some(s) = self.selection.take().filter(|s| s.key != key) {
            self.notify(&s.key, false);
        }
        self.selection = Some(Selection { key: key.to_owned(), locked: true });
        self.notify(key, true);
        if self.mode == Mode::Tws {
            self.set_mode(Mode::Stt);
        }
        self.dirty = true;
        true
    }

    /// Backspace (event 0x31, `FUN_004add60`): drop the lock (STT → the last A-A mode); without a lock it clears
    /// the designated point (the EXP flag stays).
    pub fn deselect(&mut self, now: f64, input: &Input) {
        if !self.has_lock() {
            self.designated = None;
            return;
        }
        self.unlock();
        self.illumination_lost();
        self.stt_transitions(now, input);
    }

    /// Event 0x2f (`FUN_004ade90`, a MAP page click off the contacts): a lock is dropped first, then the point (X,
    /// Y, terrain height) is designated.
    pub fn designate(&mut self, point: Vec3, now: f64, input: &Input) {
        if self.has_lock() {
            self.deselect(now, input);
        }
        self.designated = Some(point);
        self.dirty = true;
    }

    /// Event 0x30 (`FUN_004ade70`, MAP page OSB 3): NORM ↔ EXP, only with a designated point.
    pub fn toggle_exp(&mut self) {
        if self.designated.is_some() {
            self.expanded = !self.expanded;
            self.dirty = true;
        }
    }

    /// Damage (cases 0xf / 0x13 / 0x15, `FUN_004adb20`): off, every call a no-op.
    pub fn set_damaged(&mut self, on: bool) {
        if on && !self.damaged {
            self.unlock();
            self.contacts.clear();
            self.selection = None;
            self.mode = Mode::Off;
        }
        self.damaged = on;
        self.dirty = true;
    }
}

/// The hit test (`FUN_004aeb90`) and the record: air modes skip targets below 30 m AGL; the horizontal cone about
/// the antenna only (no elevation limit); terrain line of sight (ends +1.5 m).
fn hit(u: &Unit, own: &Own, air: bool, cone: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Option<Contact> {
    if air && terrain(u.pos).is_some_and(|g| u.pos.z < g + MIN_AGL) {
        return None;
    }
    let d = u.pos - own.pos;
    let dist = d.length();
    if dist < 1.0 {
        return None;
    }
    let bearing = d.flat_dir();
    let cos = bearing.dot(own.fwd.flat_dir());
    if cos < cone {
        return None;
    }
    let right = Vec3::new(own.yaw.cos(), -own.yaw.sin(), 0.0);
    let az = cos.clamp(-1.0, 1.0).acos().copysign(right.dot(bearing));
    let el = (d.z / dist).clamp(-1.0, 1.0).asin() - own.fwd.z.clamp(-1.0, 1.0).asin();
    if !line_of_sight(own.pos.raised(LOS_RAISE), u.pos.raised(LOS_RAISE), terrain) {
        return None;
    }
    Some(Contact {
        key: u.key.clone(),
        pos: u.pos,
        heading: u.heading,
        hostile: u.hostile,
        aspect: wrap_pi(u.heading.to_radians() - d.x.atan2(d.y)),
        az,
        el,
        dist,
        speed_kt: u.vel.length() * KT,
        type_code: u.type_code,
    })
}

/// Terrain line of sight (`FUN_004020d0`; ours samples the segment every 100 m: the original's sampling is
/// UNCERTAIN).
pub fn line_of_sight(a: Vec3, b: Vec3, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
    let d = b - a;
    let n = (d.length() / 100.0) as u32;
    (1..n).all(|i| {
        let p = a + d * (f64::from(i) / f64::from(n));
        terrain(p).is_none_or(|g| p.z >= g)
    })
}

/// Sorted insert, 15 at most (`FUN_004b08e0`): when full, a record replaces the last only with a strictly higher
/// priority.
fn insert(list: &mut Vec<Contact>, record: Option<Contact>) {
    let Some(r) = record else { return };
    if list.len() >= MAX_CONTACTS {
        if list.last().is_some_and(|last| r.priority() <= last.priority()) {
            return;
        }
        list.pop();
    }
    let i = list.partition_point(|c| c.priority() >= r.priority());
    list.insert(i, r);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flat(_: Vec3) -> Option<f64> {
        None
    }

    fn jet(key: &str, x: f64, y: f64) -> Unit {
        Unit {
            key: key.into(),
            pos: Vec3::new(x, y, 5000.0),
            vel: Vec3::new(0.0, 200.0, 0.0),
            class: 1,
            state: 1,
            hostile: true,
            ..Default::default()
        }
    }

    const OWN: Own = Own { pos: Vec3::new(0.0, 0.0, 5000.0), fwd: Vec3::NORTH, yaw: 0.0 };

    fn scene(units: &[Unit]) -> Input<'_> {
        Input { own: OWN, units, terrain: &flat }
    }

    fn keys(r: &Radar) -> Vec<&str> {
        r.contacts().iter().map(|c| c.key.as_str()).collect()
    }

    #[test]
    fn f16_table_range_and_cone() {
        let mut r = Radar::new(1, None);
        assert_eq!(r.mode(), Mode::Off);
        assert_eq!(r.ranges().get(Mode::Lrs), Some(&Range { max: 5, nm: 45.0, index: 4 }));
        r.toggle_aa_ag(0.0, &scene(&[jet("t", 0.0, 30000.0), jet("u", 0.0, 50.0 * NM)]));
        assert_eq!(r.mode(), Mode::Lrs);
        assert_eq!(keys(&r), ["t"]);
        assert!(r.contacts()[0].aspect.abs() < 0.01, "flying away: aspect 0 (tail)");
        r.step_range(2, 1.0, &scene(&[jet("t", 0.0, 45.0 * NM + 500.0)]));
        assert_eq!(keys(&r), ["t"], "the selection beyond 45 NM is kept (re-tested without the range)");
        let a = 65f64.to_radians();
        r.scan(2.0, &scene(&[jet("t", 30000.0 * a.sin(), 30000.0 * a.cos())]));
        assert!(r.contacts().is_empty(), "65° off the nose: outside the 60° cone");
        assert!((r.scope_width() - 2.0 * PI / 3.0).abs() < 1e-9);
    }

    #[test]
    fn list_keeps_the_15_nearest() {
        let mut list = Vec::new();
        for i in 0..20 {
            insert(&mut list, Some(Contact { key: i.to_string(), dist: 1000.0 * f64::from(20 - i), ..Default::default() }));
        }
        assert_eq!(list.len(), MAX_CONTACTS);
        assert!(list.is_sorted_by(|a, b| a.dist <= b.dist));
        assert_eq!(list[0].key, "19");
    }

    #[test]
    fn stt_auto_range_and_lost_lock() {
        let mut r = Radar::new(1, None);
        let mut units = vec![jet("t", 0.0, 20000.0)];
        r.toggle_aa_ag(0.0, &scene(&units));
        assert!(r.lock_key("t"));
        r.update(0.05, &scene(&units));
        assert_eq!(r.mode(), Mode::Stt);
        assert_eq!(r.range_index(), 3, "20 km → the 20 NM scale");
        assert!(r.take_events().contains(&Event::Lock { key: "t".into(), on: true }));
        units[0].pos.y = -20000.0;
        r.update(0.10, &scene(&units));
        r.update(0.15, &scene(&units));
        assert_eq!(r.mode(), Mode::Lrs, "behind the jet: the lock drops, back to LRS");
        assert!(r.locked().is_none());
        assert!(r.take_events().contains(&Event::IlluminationLost));
    }

    #[test]
    fn acm_locks_at_once() {
        let mut r = Radar::new(1, None);
        let units = [jet("t", 0.0, 5000.0)];
        r.toggle_aa_ag(0.0, &scene(&units));
        r.cycle_mode(0.0, &scene(&units));
        r.cycle_mode(0.0, &scene(&units));
        assert_eq!(r.mode(), Mode::Acm);
        assert!(r.selection().is_some_and(|s| s.locked));
        r.update(0.05, &scene(&units));
        assert_eq!(r.mode(), Mode::Stt);
    }

    #[test]
    fn tws_lock_follows_the_unit_between_scans() {
        let mut r = Radar::new(1, None);
        let mut units = vec![jet("t", 0.0, 20000.0)];
        r.toggle_aa_ag(0.0, &scene(&units));
        r.cycle_mode(0.0, &scene(&units));
        assert_eq!(r.mode(), Mode::Tws);
        units[0].pos = Vec3::new(300.0, 20400.0, 5000.0);
        r.update(0.05, &scene(&units));
        let lock = r.locked().expect("TWS lock");
        assert_eq!(lock.pos, units[0].pos);
        assert!((lock.dist - units[0].pos.distance(OWN.pos)).abs() < 1e-9);
        assert_eq!(r.contact("t").map(|c| c.pos), Some(Vec3::new(0.0, 20000.0, 5000.0)), "the blip waits for the scan");
    }

    #[test]
    fn terrain_hides_and_low_targets_skip() {
        let ridge = |p: Vec3| Some(if (9000.0..11000.0).contains(&p.y) { 6000.0 } else { 0.0 });
        let (a, b) = (Vec3::new(0.0, 0.0, 5000.0), Vec3::new(0.0, 20000.0, 5000.0));
        assert!(!line_of_sight(a, b, &ridge));
        assert!(line_of_sight(a, b, &flat));
        let low = |_: Vec3| Some(4990.0);
        assert!(hit(&jet("t", 0.0, 20000.0), &OWN, true, CONE_COS, &low).is_none(), "10 m AGL");
        assert!(hit(&jet("t", 0.0, 20000.0), &OWN, false, CONE_COS, &low).is_some(), "ground modes see it");
    }
}
