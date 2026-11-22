//! The player's radar (docs/radar.md): the radar manager of the player controller (ctl+0x84, `FUN_004acc20`)
//! with its modes, the per-aircraft range tables, the scan (`FUN_004af300`, every 2.0 s and on events), the hit
//! test (`FUN_004aeb90`), the contact list (15, nearest first), the lock / designate keys and the STT track
//! (`FUN_004b1300`).
//!
//! World frame X east, Y north, Z up, metres, sim seconds. Every call that can scan takes the scene (`Input`);
//! the RWR lock notices and the semi-active missiles' illumination loss come out as `Event`s.

use crate::vec3::Vec3;
use iaf_flight::airframe::Rcs;
use std::f64::consts::PI;

/// Ours (docs/ai.md §15.2): the target size a radar's reach is quoted against (m²), a fighter (inferred; public
/// ranges rarely name one). Every range table here is read as against it.
pub const REF_RCS: f64 = 5.0;

/// Ours: the radar cross-section (m²) of a jet with its nose along `nose`, seen from `to_radar` (the direction from
/// the jet to the radar): front, side and rear blended by the aspect (inferred), plus the open bays and each external
/// store.
pub fn sigma(r: &Rcs, nose: Vec3, to_radar: Vec3, bays_open: bool, stores: u32) -> f64 {
    let c = match (nose.try_normalize(), to_radar.try_normalize()) {
        (Some(n), Some(d)) => n.dot(d).clamp(-1.0, 1.0),
        _ => 1.0,
    };
    let aspect = r.front_m2 * c.max(0.0).powi(2) + r.side_m2 * (1.0 - c * c) + r.rear_m2 * (-c).max(0.0).powi(2);
    aspect + if bays_open { r.bays_open_m2 } else { 0.0 } + r.store_m2 * f64::from(stores)
}

/// Ours: a radar's range against `sigma` (m²), the radar equation's fourth root, from its reach against `REF_RCS`.
pub fn reach(reach_m: f64, sigma: f64) -> f64 {
    reach_m * (sigma / REF_RCS).max(0.0).powf(0.25)
}

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

// Ours, the real F-16 fire-control radar (docs/radar.md §9; the dash-34's FCR, docs/real-mfd.md "FCR").
/// The RWS azimuth scans (OSB 18 `A6` / `A3` / `A1`: ±60°, ±30°, ±10°) and bar counts (OSB 17 `B1` / `B2` / `B4`).
const RWS_AZ: [f64; 3] = [60.0, 30.0, 10.0];
const RWS_BARS: [u8; 3] = [4, 1, 2];
/// The TWS scans (p. 1-139): ±25° / 3 bars (the first), ±10° / 4 bars, ±60° / 2 bars.
const TWS_SCANS: [(f64, u8); 3] = [(25.0, 3), (10.0, 4), (60.0, 2)];
/// One bar's height (deg) and the antenna's scan rate (deg/s): inferred (the dash-34's coverage figure 1-86 is not
/// transcribed); an A6 B4 frame takes 8 s, an A1 B1 frame 0.5 s at the least (`MIN_FRAME`).
const BAR_DEG: f64 = 3.0;
const SCAN_RATE: f64 = 60.0;
/// The shortest frame (s) and the ACM patterns' frame (inferred).
const MIN_FRAME: f64 = 0.5;
const ACM_FRAME: f64 = 1.0;
/// The antenna elevation's limit and its thumbwheel rate (deg, deg/s; inferred), the cursor's slew rate (scope
/// widths per second; inferred).
const ELEV_MAX: f64 = 60.0;
const ELEV_RATE: f64 = 10.0;
const CURSOR_RATE: f64 = 0.5;
/// A target is under the cursor within this much of the scope (≈ 4 MFD px, the mouse's tolerance).
const CURSOR_NEAR: f64 = 0.04;
/// The cursor bumps the range scale below 5 % / above 95 % (p. 1-122).
const BUMP: (f64, f64) = (0.05, 0.95);
/// The smallest A-A range index of the real FCR (10 NM; the 5 NM scale is the 1998 game's).
const REAL_MIN_INDEX: u8 = 2;
/// STT auto-range of the real FCR: down below 40 %, up above 95 % (p. 1-131); TWS and SAM: up beyond 90 %, TWS down
/// closer than 45 %.
const REAL_STT: (f64, f64) = (0.40, 0.95);
const REAL_BUG: (f64, f64) = (0.45, 0.90);
/// TWS track files: at most 10, extrapolated for 13 s without a return, flashing for the last 8 s (p. 1-140).
const TWS_FILES: usize = 10;
const TWS_KEEP: f64 = 13.0;
/// VSR: the closure scale's top (kt; inferred).
pub const VSR_MAX_KT: f64 = 1200.0;
/// The real FCR's EXP: a 4:1 expansion about the bugged target or the cursor (p. 1-140).
pub const EXP_K: f64 = 4.0;
/// MTR LO / HI: in look-down every air mode loses a target whose speed along the line of sight is under these, the
/// ground's band (kt; inferred; docs/radar.md §9.8).
const MTR_KT: [f64; 2] = [60.0, 100.0];

/// The CNTL page (fig. 1-76, p. 1-116): each option's OSB, legend and values, in `Real::cntl`'s order. TGT HIS (the
/// search frames shown, the older dimmer) and MTR act on the search; the sim has no radar channels, marker
/// intervals, band, pulse modes or levels to change, so those step as the real page's and change nothing. BCN DLY
/// (OSB 9) is left off: the sim has no BCN mode.
pub const CNTL: [(u8, &str, &[&str]); 8] = [
    (6, "CHAN", &["1", "2", "3", "4"]),
    (7, "MK INT", &["1", "2", "3", "4"]),
    (8, "BAND", &["WIDE", "NARO"]),
    (10, "PM", &["ON", "OFF"]),
    (20, "MTR", &["LO", "HI"]),
    (19, "ALT TRK", &["OFF", "ON"]),
    (18, "TGT HIS", &["1", "2", "3", "4"]),
    (17, "LVL", &["1", "2", "3", "4"]),
];
const CNTL_MTR: usize = 4;
const CNTL_TGT_HIS: usize = 6;

// Ours, the real FCR's air-to-ground modes (docs/radar.md §9.7; the dash-34's GM, GMT, SEA and AGR, docs/real-mfd.md
// "A-G modes").
/// GM's fields of view on OSB 3 (the pinky switch): NORM, EXP 4:1, DBS1 8:1, DBS2 64:1 (a simulator guide; the
/// dash-34's A-A EXP is 4:1, p. 1-140). GMT and SEA have NORM and EXP only (p. 1-150, p. 1-151).
pub const AG_FOV: [(&str, f64); 4] = [("NORM", 1.0), ("EXP", 4.0), ("DBS1", 8.0), ("DBS2", 64.0)];
/// The A-G display in MFD px (the 132 px format): the PPI fan's apex, the expanded patch's centre, the fan's radius
/// (= the range scale) and the picture's window (x, y, width, height; one picture px per MFD px).
pub const FAN_APEX: (f64, f64) = (66.0, 109.0);
pub const PATCH_CENTRE: (f64, f64) = (66.0, 66.0);
pub const FAN_PX: f64 = 94.0;
pub const PIC_WINDOW: (f64, f64, usize, usize) = (12.0, 12.0, 108, 106);
/// Doppler beam sharpening needs the patch off the ground track: inside this many degrees of it OSB 3 skips DBS1 /
/// DBS2 and a DBS patch falls back to EXP (inferred; the real limit is open).
const DBS_NOTCH_DEG: f64 = 10.0;
/// The ships' classes (15 boat, 16 armed boat; docs/front-end.md "TSD icon class"): SEA lists only these.
const SHIP_CLASSES: [i64; 2] = [0xf, 0x10];
/// The A-G cursor's slew: the display widths per second (as the A-A cursor's).
const GROUND_SLEW: f64 = CURSOR_RATE;
/// GMT's map is dimmed under its movers (p. 1-150; the factor inferred).
const GMT_DIM: f64 = 0.35;
/// AGR ranges along the aim line to this far (m; inferred: 20 NM).
const AGR_REACH: f64 = 37040.0;

/// The A-G display's frame: the world point at MFD px `sym`, heading-up for `yaw` (rad, clockwise from north), `k`
/// metres per MFD px (mfd.gd `_heading_up`'s transform).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GroundFrame {
    pub centre: Vec3,
    pub yaw: f64,
    pub k: f64,
    pub sym: (f64, f64),
}

impl GroundFrame {
    /// A world point's place on the display (MFD px).
    pub fn to_px(&self, w: Vec3) -> (f64, f64) {
        let (s, c) = self.yaw.sin_cos();
        let (e, n) = (w.x - self.centre.x, w.y - self.centre.y);
        (self.sym.0 + (e * c - n * s) / self.k, self.sym.1 - (e * s + n * c) / self.k)
    }

    /// The world point (z 0) at a place on the display.
    pub fn from_px(&self, (x, y): (f64, f64)) -> Vec3 {
        let (s, c) = self.yaw.sin_cos();
        let (a, b) = ((x - self.sym.0) * self.k, (self.sym.1 - y) * self.k);
        Vec3::new(self.centre.x + a * c + b * s, self.centre.y - a * s + b * c, 0.0)
    }
}

/// A runway: its two ends (world X, Y) and half width (m). The GM picture shows it dark: a smooth surface returns
/// little (inferred).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Runway {
    pub a: (f64, f64),
    pub b: (f64, f64),
    pub half_width: f64,
}

impl Runway {
    fn holds(&self, p: Vec3) -> bool {
        let (dx, dy) = (self.b.0 - self.a.0, self.b.1 - self.a.1);
        let len2 = (dx * dx + dy * dy).max(1.0);
        let t = ((p.x - self.a.0) * dx + (p.y - self.a.1) * dy) / len2;
        let (cx, cy) = (self.a.0 + t * dx, self.a.1 + t * dy);
        (0.0..=1.0).contains(&t) && (p.x - cx).hypot(p.y - cy) <= self.half_width
    }
}

/// The GM picture of one radar frame: luminance and alpha per px over `PIC_WINDOW` (alpha 0: no terrain data there,
/// the map under it shows), drawn in `frame`; `serial` counts the pictures.
#[derive(Clone, Debug, Default)]
pub struct Picture {
    pub frame: Option<GroundFrame>,
    pub la8: Vec<u8>,
    pub serial: u64,
}

/// Ours: the real F-16 fire-control radar, from the aircraft definition's `radar.fcr` (docs/radar.md §9). The jets
/// without one keep the original's radar.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Fcr {
    /// The bugged targets the situation-awareness mode (SAM) tracks while it searches: the APG-68(V)9's four (Lockheed
    /// Martin 2002), the APG-68's one.
    pub sam_tracks: usize,
}

/// The ACM scan patterns (OSB 2 `20`, `60`, `SLEW`; `BORE` is [`Mode::Bore`]). Volumes inferred from simulator
/// forums: 30° × 20° about the HUD's field, 10° × 60° scanning up, a 60° × 20° stabilised patch the cursor slews.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Acm {
    #[default]
    Twenty,
    Sixty,
    Slew,
}

/// The target management switch (the keyboard's TMS keys).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tms {
    Up,
    Down,
    Right,
    Left,
}

/// A scan volume (deg): azimuth centre and half width, elevation low and high; `body` about the jet's axes, else
/// stabilised on the horizon and the heading.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Volume {
    pub az: f64,
    pub half: f64,
    pub lo: f64,
    pub hi: f64,
    pub body: bool,
}

impl Volume {
    fn holds(&self, az: f64, el: f64) -> bool {
        (az - self.az).abs() <= self.half && (self.lo..=self.hi).contains(&el)
    }
}

/// The real FCR's settings and state.
#[derive(Clone, Debug)]
pub struct Real {
    pub fcr: Fcr,
    /// RWS: indices into `RWS_AZ`, `RWS_BARS`; TWS: into `TWS_SCANS`.
    pub rws_az: usize,
    pub rws_bars: usize,
    pub tws: usize,
    /// Antenna elevation (deg, + up) and its thumbwheel (−1..1).
    pub elevation: f64,
    elev_rate: f64,
    /// The acquisition cursor on the scope, 0..1 across (−60°..+60°) and up (range or VSR closure); its slew (−1..1).
    pub cursor: (f64, f64),
    slew: (f64, f64),
    /// CRM's VSR submode (in [`Mode::Lrs`]).
    pub vsr: bool,
    /// SAM's bugged tracks, the primary last.
    pub sam: Vec<String>,
    pub acm: Acm,
    /// OSB 4 OVRD: the radar stops radiating.
    pub ovrd: bool,
    /// OSB 3 EXP (CRM's RWS and TWS) and its centre on the NORM scope while nothing is bugged.
    pub exp: bool,
    exp_at: (f64, f64),
    /// The CNTL page's options, indices into `CNTL`'s values (TGT HIS 3 by default, p. 1-134).
    pub cntl: [usize; 8],
    /// RWS's earlier search frames for TGT HIS, the newest first.
    pub history: Vec<Vec<Contact>>,
    /// A-G: the field of view (index into `AG_FOV`), SEA (in [`Mode::Map`]), the ground cursor (a world point,
    /// ground-stabilised; None until the first A-G frame), SP (snowplow: the cursor half the range ahead), OSB 10's
    /// TGT (CZ to the designated point, else the steerpoint), FZ's frozen frame, AGR's slant range and its aim point.
    pub fov: usize,
    pub sea: bool,
    pub ground: Option<Vec3>,
    pub snowplow: bool,
    pub tgt: bool,
    pub frozen: Option<GroundFrame>,
    pub agr: Option<f64>,
    agr_at: Option<Vec3>,
    pub runways: Vec<Runway>,
    pub picture: Picture,
}

impl Real {
    fn new(fcr: Fcr) -> Self {
        Real {
            fcr,
            rws_az: 0,
            rws_bars: 0,
            tws: 0,
            elevation: 0.0,
            elev_rate: 0.0,
            cursor: (0.5, 0.5),
            slew: (0.0, 0.0),
            vsr: false,
            sam: Vec::new(),
            acm: Acm::Twenty,
            ovrd: false,
            exp: false,
            exp_at: (0.5, 0.5),
            cntl: [0, 0, 0, 0, 0, 0, 2, 0],
            history: Vec::new(),
            fov: 0,
            sea: false,
            ground: None,
            snowplow: false,
            tgt: false,
            frozen: None,
            agr: None,
            agr_at: None,
            runways: Vec::new(),
            picture: Picture::default(),
        }
    }

    /// The azimuth half width and bars of the RWS / TWS scan.
    pub fn scan(&self, tws: bool) -> (f64, u8) {
        if tws { TWS_SCANS[self.tws] } else { (RWS_AZ[self.rws_az], RWS_BARS[self.rws_bars]) }
    }

    /// The cursor's azimuth off the nose (deg).
    fn cursor_az(&self) -> f64 {
        (self.cursor.0 - 0.5) * 120.0
    }
}

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

/// Ours: the row of the F-16I Sufa's AN/APG-68(V)9 (docs/f16i.md §2), after the original's nine.
pub const F16I: usize = 9;
/// Ours: the row of the F-35I's AN/APG-81 (docs/f35i.md), after the Sufa's.
pub const F35I: usize = 10;

/// Per cockpit index (`FUN_00447e70`: 0 F-15, 1 F-16, 2 F-4-2000, 3 Lavi, 4 Kfir, 5 F-4E, 6 Mirage, 7 MiG-29,
/// 8 MiG-23): A-A table `0x640a74` and A-G table `0x640bbc`; then ours, [`F16I`] and [`F35I`].
const TABLES: [Row; 11] = [
    [(6, 90.0), (4, 40.0), (2, 10.0), (2, 10.0), (4, 40.0), (4, 20.0)],
    [(5, 45.0), (4, 35.0), (2, 10.0), (2, 10.0), (4, 40.0), (4, 30.0)],
    [(5, 55.0), (4, 40.0), (2, 10.0), (2, 10.0), (5, 60.0), (5, 40.0)],
    [(6, 90.0), (4, 40.0), (2, 10.0), (2, 10.0), (5, 60.0), (5, 40.0)],
    [(2, 8.0), (0, 0.0), (1, 5.0), (1, 5.0), (2, 10.0), (2, 10.0)],
    [(4, 25.0), (0, 0.0), (2, 10.0), (2, 10.0), (2, 10.0), (2, 10.0)],
    [(2, 8.0), (0, 0.0), (1, 5.0), (1, 5.0), (2, 10.0), (2, 10.0)],
    [(5, 45.0), (4, 35.0), (2, 10.0), (2, 10.0), (2, 10.0), (2, 10.0)],
    [(4, 25.0), (0, 0.0), (2, 10.0), (2, 10.0), (4, 40.0), (4, 25.0)],
    // The F-16's row with the (V)9's 30 % more air-to-air range (Lockheed Martin): LRS 45 → 58 NM, TWS 35 → 45 NM
    // (inferred); the scales and the other modes as the F-16's.
    [(5, 58.0), (4, 45.0), (2, 10.0), (2, 10.0), (4, 40.0), (4, 30.0)],
    // The F-35I's APG-81: search to 80 NM (148 km, as its Weapon data Real `RADAR_KM`), track-while-scan and the
    // SAR map to 60 NM, GMT 40 NM, all on scales to 80 NM (inferred; the public figures give only "beyond 80 NM").
    [(5, 80.0), (5, 60.0), (2, 10.0), (2, 10.0), (5, 60.0), (4, 40.0)],
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
            // BORE starts at its largest scale; ours (the Sufa, the F-35I: their search reaches past 40 NM) every mode.
            if mode == Mode::Bore || cockpit >= F16I {
                range.index = max;
            }
            r[mode as usize] = Some(range);
        }
        let src = r[Mode::Lrs as usize].or(r[Mode::Acm as usize]).unwrap_or(Range::new(2, 10.0));
        let mut stt = Range::new(src.max, src.nm);
        if cockpit >= F16I {
            stt.index = src.max;
        }
        r[Mode::Stt as usize] = Some(stt);
        Ranges(r)
    }

    /// The real FCR's scales (docs/real-mfd.md "FCR"): RWS / VSR to 160 NM, TWS to 80 NM, from where they start.
    fn real(mut self) -> Self {
        for (mode, max) in [(Mode::Lrs, 6), (Mode::Tws, 5), (Mode::Map, 5)] {
            if let Some(r) = self.get_mut(mode) {
                r.max = r.max.max(max);
            }
        }
        // GMT: 10, 20 and 40 NM only (p. 1-150).
        if let Some(r) = self.get_mut(Mode::Gmt) {
            r.max = r.max.min(4);
            r.index = r.index.min(4);
        }
        self
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
    /// Ours: its radar cross-section (Modern IAF's drones, docs/ai.md §16); None: seen at the tables' ranges, as the
    /// original.
    pub rcs: Option<Rcs>,
    /// Ours: its self-protection jammer on, its burn-through share (`ecm::jammed_reach`, docs/radar.md §8), 0 not
    /// jamming.
    pub jam: f64,
}

impl Unit {
    fn alive(&self) -> bool {
        !matches!(self.state, 4 | 5)
    }

    /// A detection range `base` (against `REF_RCS`) against this unit seen from `from`: scaled by its cross-section
    /// from there, its nose along its velocity; jamming, the nearer of that and its burn-through.
    fn reach_from(&self, base: f64, from: Vec3) -> f64 {
        crate::ecm::jammed_reach(base, self.sigma_from(from), self.jam())
    }

    /// Its jammer's share against the own radar: a friendly's jams the enemy, not us.
    fn jam(&self) -> f64 {
        if self.hostile { self.jam } else { 0.0 }
    }

    fn sigma_from(&self, from: Vec3) -> f64 {
        self.rcs.as_ref().map_or(REF_RCS, |r| sigma(r, self.vel, from - self.pos, false, 0))
    }

    /// Jamming and beyond its burn-through, yet inside the range it would be seen at: the radar shows its strobe.
    fn strobe_from(&self, base: f64, from: Vec3) -> bool {
        let d = self.pos.distance(from);
        self.jam() > 0.0 && d > self.reach_from(base, from) && d <= reach(base, self.sigma_from(from))
    }
}

/// The own jet: position, forward axis, yaw (rad, atan2(fwd.x, fwd.y)); ours: the up axis (zero: straight up), the
/// velocity and the weight on wheels.
#[derive(Clone, Copy, Debug, Default)]
pub struct Own {
    pub pos: Vec3,
    pub fwd: Vec3,
    pub yaw: f64,
    pub up: Vec3,
    pub vel: Vec3,
    pub wow: bool,
    /// Ours: the current steerpoint (z: any; the real FCR's A-G cursor starts there and CZ returns it there).
    pub steer: Option<Vec3>,
}

/// What a call sees: the own jet, the units and the terrain height at a world point (None: no terrain there).
pub struct Input<'a> {
    pub own: Own,
    pub units: &'a [Unit],
    pub terrain: &'a dyn Fn(Vec3) -> Option<f64>,
    /// Ours: the bare ground's height (no roofs or trees; the A-G picture's cheaper lookup), None: `terrain`.
    pub bare: Option<&'a dyn Fn(Vec3) -> Option<f64>>,
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
    /// Mach (the MFD record +0x67c, shown ×10 beside the STT / hovered TWS target, `FUN_00534160`). Ours: the
    /// speed over the standard atmosphere's speed of sound at the unit's height (inferred; the original's source is
    /// open).
    pub mach: f64,
    pub type_code: i64,
    /// Ours: the closure (kt, + closing), the unit's velocity and when the scan last saw it (TWS track files).
    pub closure_kt: f64,
    pub vel: Vec3,
    pub seen: f64,
}

impl Contact {
    /// A TWS track file moved on along its velocity by `dt`, its geometry from the own jet again.
    fn extrapolated(&self, dt: f64, own: &Own) -> Contact {
        let pos = self.pos + self.vel * dt;
        let d = pos - own.pos;
        let right = Vec3::new(own.yaw.cos(), -own.yaw.sin(), 0.0);
        let cos = d.flat_dir().dot(own.fwd.flat_dir()).clamp(-1.0, 1.0);
        Contact { pos, dist: d.length(), az: cos.acos().copysign(right.dot(d.flat_dir())), ..self.clone() }
    }

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
    /// The scan recorded this unit (@4afae6): it becomes known to the player (state +0x44, the TSD shows it).
    Detected { key: String },
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
    /// Ours: the last search's jam strobes, each a jammer's azimuth off the nose (rad; docs/radar.md §8).
    strobes: Vec<f64>,
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
    /// Ours (Modern IAF's jets): powered, the radar comes up in STBY; it does not radiate with weight
    /// on wheels and goes to the last A-A mode by itself once airborne (`auto_on`) unless the pilot chose a mode.
    ours: bool,
    wow: bool,
    /// The own altitude at the last update (m): the bugged target's elevation for the scan's centre.
    own_z: f64,
    /// The own jet at the last update (the A-G display's frame).
    own: Own,
    auto_on: bool,
    /// Ours: the real F-16 FCR (None: the original's radar).
    real: Option<Real>,
    /// The last update's and the last scan's time.
    now: f64,
    last_scan: f64,
}

impl Radar {
    /// Create (`FUN_004ace60`) for cockpit index `cockpit` (`FUN_00447e70`); `lrs_nm`: the LRS / STT detection range
    /// with Weapon data Real; `fcr`: ours, the real F-16 FCR; `ours`: Modern IAF's power rules (STBY at power-on, no
    /// radiating with weight on wheels). The radar starts OFF in A-A; ours in STBY.
    pub fn new(cockpit: usize, lrs_nm: Option<f64>, fcr: Option<Fcr>, ours: bool) -> Self {
        let ranges = Ranges::new(cockpit, lrs_nm);
        Radar {
            ranges: if fcr.is_some() { ranges.real() } else { ranges },
            mode: if ours { Mode::Standby } else { Mode::Off },
            last_aa: Mode::Lrs,
            // The real FCR's first A-G mode is GM (ours; the original's GMT).
            last_ag: if fcr.is_some() { Mode::Map } else { Mode::Gmt },
            bore_return: Mode::Lrs,
            air_to_air: true,
            damaged: false,
            bore_held: false,
            dirty: false,
            contacts: Vec::new(),
            strobes: Vec::new(),
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
            ours,
            wow: false,
            own_z: 0.0,
            own: Own::default(),
            auto_on: ours,
            real: fcr.map(Real::new),
            now: 0.0,
            last_scan: 0.0,
        }
    }

    /// The last update's time.
    pub fn now(&self) -> f64 {
        self.now
    }

    pub fn real(&self) -> Option<&Real> {
        self.real.as_ref()
    }

    /// The SAM primary's key.
    fn sam_primary(&self) -> Option<&str> {
        self.real.as_ref()?.sam.last().map(String::as_str)
    }

    /// The scan volume of the real FCR's mode; None: the original's cone (and the real FCR's STT / ground modes).
    pub fn volume(&self) -> Option<Volume> {
        let r = self.real.as_ref()?;
        let stab = |half: f64, bars: u8, az: f64| {
            let h = f64::from(bars) * BAR_DEG / 2.0;
            let az = if half < 60.0 { az.clamp(half - 60.0, 60.0 - half) } else { 0.0 };
            Volume { az, half, lo: r.elevation - h, hi: r.elevation + h, body: false }
        };
        let body = |half: f64, lo: f64, hi: f64| Volume { az: 0.0, half, lo, hi, body: true };
        Some(match self.mode {
            // The bugged target (SAM's primary, TWS's bug) centres the scan; else the cursor's azimuth and the
            // antenna elevation (p. 1-139).
            Mode::Lrs | Mode::Tws => {
                let (half, bars) = r.scan(self.mode == Mode::Tws);
                match self.bug() {
                    Some(c) => {
                        let el = ((c.pos.z - self.own_z) / c.dist.max(1.0)).clamp(-1.0, 1.0).asin().to_degrees();
                        let h = f64::from(bars) * BAR_DEG / 2.0;
                        Volume { lo: el - h, hi: el + h, ..stab(half, bars, c.az.to_degrees()) }
                    }
                    None => stab(half, bars, r.cursor_az()),
                }
            }
            Mode::Acm => match r.acm {
                Acm::Twenty => body(15.0, -5.0, 15.0),
                Acm::Sixty => body(5.0, -5.0, 55.0),
                Acm::Slew => Volume {
                    az: r.cursor_az().clamp(-30.0, 30.0),
                    half: 30.0,
                    lo: r.elevation - 10.0,
                    hi: r.elevation + 10.0,
                    body: false,
                },
            },
            // ACM BORE: the beam along the boresight (inferred ±2°).
            Mode::Bore => body(2.0, -2.0, 2.0),
            _ => return None,
        })
    }

    /// The frame time (s): the original's 2 s; the real FCR's search the scan's sweep at `SCAN_RATE`, ACM `ACM_FRAME`.
    fn frame_time(&self) -> f64 {
        let Some(r) = &self.real else { return SCAN_PERIOD };
        match self.mode {
            Mode::Lrs | Mode::Tws => {
                let (half, bars) = r.scan(self.mode == Mode::Tws);
                (2.0 * half * f64::from(bars) / SCAN_RATE).max(MIN_FRAME)
            }
            Mode::Acm | Mode::Bore => ACM_FRAME,
            _ => SCAN_PERIOD,
        }
    }

    /// A contact's place on the real FCR's scope (0..1 across ±60°, up by range, VSR by closure; EXP about its
    /// centre).
    pub fn scope_xy(&self, c: &Contact) -> (f64, f64) {
        self.display(self.norm_xy(c))
    }

    /// A contact's place on the NORM scope.
    fn norm_xy(&self, c: &Contact) -> (f64, f64) {
        let vsr = self.real.as_ref().is_some_and(|r| r.vsr) && self.mode == Mode::Lrs;
        let y = if vsr { c.closure_kt / VSR_MAX_KT } else { c.dist / self.range_m() };
        (0.5 + (c.az + self.heading_shift) / (2.0 * PI / 3.0), y)
    }

    /// EXP's centre on the NORM scope: the bugged target, else the cursor's place when EXP was pressed; None in
    /// NORM, and outside CRM's RWS and TWS.
    pub fn exp_centre(&self) -> Option<(f64, f64)> {
        let r = self.real.as_ref()?;
        if !r.exp || !matches!(self.mode, Mode::Lrs | Mode::Tws) || r.vsr {
            return None;
        }
        Some(self.bug().map_or(r.exp_at, |c| self.norm_xy(c)))
    }

    /// A NORM scope place on the display (EXP: 4:1 about its centre, which sits mid-scope).
    fn display(&self, p: (f64, f64)) -> (f64, f64) {
        self.exp_centre().map_or(p, |c| (0.5 + EXP_K * (p.0 - c.0), 0.5 + EXP_K * (p.1 - c.1)))
    }

    /// The acquisition cursor's place on the display.
    pub fn cursor_xy(&self) -> Option<(f64, f64)> {
        Some(self.display(self.real.as_ref()?.cursor))
    }

    /// RWS's earlier search frames (TGT HIS), the newest first: each return's place on the display.
    pub fn history_xy(&self) -> Vec<Vec<(f64, f64)>> {
        let Some(r) = &self.real else { return Vec::new() };
        r.history.iter().map(|f| f.iter().map(|c| self.scope_xy(c)).collect()).collect()
    }

    /// The search altitudes (ft, high and low) the stabilised scan covers at the cursor's range (fig. 1-85).
    pub fn cursor_alt(&self, own_alt: f64) -> Option<(f64, f64)> {
        let v = self.volume().filter(|v| !v.body)?;
        let at = self.real.as_ref()?.cursor.1 * self.range_m();
        let alt = |deg: f64| (own_alt + at * deg.to_radians().tan()) / 0.3048;
        Some((alt(v.hi), alt(v.lo)))
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
    /// Ours: the jam strobes of the last search (azimuths off the nose, rad), none while it does not radiate.
    pub fn strobes(&self) -> &[f64] {
        if self.radiating() { &self.strobes } else { &[] }
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

    /// Radiating: on, not damaged; ours not with weight on wheels; the real FCR not in OVRD.
    pub fn radiating(&self) -> bool {
        !self.damaged
            && self.mode.radiating()
            && !(self.ours && self.wow)
            && !self.real.as_ref().is_some_and(|r| r.ovrd)
    }

    /// Ours, Modern IAF's FCR: the ground's band in look-down, CNTL's MTR (kt); 0 for the original's radar.
    fn gate_kt(&self) -> f64 {
        self.real.as_ref().map_or(0.0, |r| MTR_KT[r.cntl[CNTL_MTR]])
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
        if self.real.is_some() {
            return 2.0 * CONE_COS.acos(); // the real FCR's scope is ±60° in every A-A mode
        }
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
                // Ours: the SAM primary counts as TWS's bug does.
                Mode::Lrs if self.sam_primary() == Some(s.key.as_str()) => true,
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

    /// The real FCR's bugged target: SAM's primary in RWS, the bug in TWS (a selection left in RWS after a lock is
    /// dropped is no bug).
    fn bug(&self) -> Option<&Contact> {
        match self.mode {
            Mode::Lrs => self.contact(self.sam_primary()?),
            Mode::Tws => self.selected_contact(),
            _ => None,
        }
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

    fn detected(&mut self, record: &Option<Contact>) {
        if let Some(c) = record {
            self.events.push(Event::Detected { key: c.key.clone() });
        }
    }

    // --- per frame (FUN_004ad300 + the 2 s timer) -----------------------------------------------------

    pub fn update(&mut self, now: f64, input: &Input) {
        let dt = (now - self.now).clamp(0.0, 0.5);
        self.now = now;
        self.wow = input.own.wow;
        self.own_z = input.own.pos.z;
        self.own = input.own;
        // Ours: airborne and powered in STBY, the radar goes to the last A-A mode by itself.
        if self.auto_on && !self.wow && !self.damaged && self.mode == Mode::Standby {
            self.toggle_aa_ag(now, input);
        }
        self.real_controls(dt, now, input);
        if !self.radiating() {
            // Ours: touched down with returns listed, they go as in OVRD.
            if self.ours && self.wow && (!self.contacts.is_empty() || self.selection.is_some()) {
                self.silence();
            }
            return;
        }
        let yaw = input.own.yaw;
        let reference = *self.heading_ref.get_or_insert(yaw);
        self.heading_shift = wrap_pi(reference - yaw);
        if self.mode == Mode::Stt {
            self.antenna = (0.0, 0.0);
        } else if let Some(v) = self.volume() {
            self.antenna = self.real_antenna(now, &v);
        } else if let Some(a) = self.sweep.advance(now, if self.mode == Mode::Bore { SWEEP_BORE } else { SWEEP }) {
            self.antenna = a;
        }
        self.stt_transitions(now, input);
        // Ours: FZ holds the A-G picture and its returns.
        if now >= self.next_scan && self.real.as_ref().is_none_or(|r| r.frozen.is_none()) {
            self.scan(now, input);
        }
        if self.mode == Mode::Stt {
            self.track(input);
        }
        self.sam_track(now, input);
        self.follow(input);
        self.bug_range();
        if self.dirty || self.mode == Mode::Stt {
            self.heading_shift = 0.0;
            self.heading_ref = Some(yaw);
            self.dirty = false;
        }
    }

    /// The real FCR per frame: the antenna elevation and the cursor follow their keys; the cursor bumps the range
    /// scale; SAM lives in CRM's RWS only.
    fn real_controls(&mut self, dt: f64, now: f64, input: &Input) {
        let mode = self.mode;
        let Some(r) = &mut self.real else { return };
        if mode != Mode::Lrs {
            r.sam.clear();
        }
        if mode != Mode::Lrs || r.vsr {
            r.history.clear();
        }
        r.elevation = (r.elevation + r.elev_rate * ELEV_RATE * dt).clamp(-ELEV_MAX, ELEV_MAX);
        if mode.air_to_ground() {
            return self.ground_controls(dt, now, input);
        }
        r.frozen = None;
        // EXP: the cursor moves at the same speed over the expanded display.
        let rate = CURSOR_RATE * dt / if r.exp && matches!(mode, Mode::Lrs | Mode::Tws) { EXP_K } else { 1.0 };
        r.cursor.0 = (r.cursor.0 + r.slew.0 * rate).clamp(0.0, 1.0);
        r.cursor.1 = (r.cursor.1 + r.slew.1 * rate).clamp(0.0, 1.0);
        if !matches!(mode, Mode::Lrs | Mode::Tws) || r.vsr {
            return;
        }
        let step = if r.cursor.1 > BUMP.1 {
            1
        } else if r.cursor.1 < BUMP.0 {
            -1
        } else {
            return;
        };
        let Some(range) = self.ranges.get(mode) else { return };
        if (step > 0 && range.index < range.max) || (step < 0 && range.index > REAL_MIN_INDEX) {
            r.cursor.1 = (r.cursor.1 * if step > 0 { 0.5 } else { 2.0 }).clamp(BUMP.0, BUMP.1);
            self.step_range(step, now, input);
        } else {
            r.cursor.1 = r.cursor.1.clamp(BUMP.0, BUMP.1);
        }
    }

    /// The real FCR's antenna carets (0..1 across ±60°, down from +60°): the beam sweeps the volume bar by bar,
    /// alternating, once per frame.
    fn real_antenna(&self, now: f64, v: &Volume) -> (f64, f64) {
        let bars = ((v.hi - v.lo) / BAR_DEG).round().max(1.0);
        let k = (now / self.frame_time()).fract() * bars;
        let bar = k.floor();
        let x = if bar as i64 % 2 == 0 { k.fract() } else { 1.0 - k.fract() };
        let az = v.az + v.half * (2.0 * x - 1.0);
        let el = v.hi - (bar + 0.5) / bars * (v.hi - v.lo);
        (((az + 60.0) / 120.0).clamp(0.0, 1.0), ((60.0 - el) / 120.0).clamp(0.0, 1.0))
    }

    /// SAM: each bugged track is revisited every frame (inside the ±60° cone and the STT range, as STT's track); a
    /// lost one leaves the list, the next becomes the primary.
    fn sam_track(&mut self, now: f64, input: &Input) {
        if self.mode != Mode::Lrs || self.real.as_ref().is_none_or(|r| r.sam.is_empty()) {
            return;
        }
        let reach = self.ranges.get(Mode::Stt).map_or(0.0, Range::detection_m);
        let gate = self.gate_kt();
        let keys = self.real.as_ref().map(|r| r.sam.clone()).unwrap_or_default();
        for key in keys {
            let record = input
                .unit(&key)
                .filter(|u| u.alive() && u.pos.distance(input.own.pos) <= u.reach_from(reach, input.own.pos))
                .and_then(|u| hit(u, &input.own, true, CONE_COS, None, input.terrain))
                .filter(|c| !notched(c, &input.own, gate, reach, input.terrain));
            self.contacts.retain(|c| c.key != key);
            match record {
                Some(c) => {
                    let i = self.contacts.partition_point(|o| o.priority() >= c.priority());
                    self.contacts.insert(i, Contact { seen: now, ..c });
                }
                None => {
                    if let Some(r) = &mut self.real {
                        r.sam.retain(|k| *k != key);
                    }
                    self.notify(&key, false);
                }
            }
        }
        let primary = self.sam_primary().map(str::to_owned);
        if self.selection.as_ref().map(|s| &s.key) != primary.as_ref() {
            if let Some(key) = &primary {
                self.notify(key, true);
            }
            self.selection = primary.map(|key| Selection { key, locked: false });
        }
    }

    /// The real FCR's range follows the bugged target (p. 1-131): STT in `track`; TWS and SAM up beyond 90 % of the
    /// scale, TWS down closer than 45 %.
    fn bug_range(&mut self) {
        if self.real.is_none() || !matches!(self.mode, Mode::Lrs | Mode::Tws) {
            return;
        }
        let Some(dist) = self.locked().map(|c| c.dist) else { return };
        let mode = self.mode;
        if let Some(r) = self.ranges.get_mut(mode) {
            if dist > REAL_BUG.1 * r.scale_m() && r.index < r.max {
                r.index += 1;
            } else if mode == Mode::Tws && dist < REAL_BUG.0 * r.scale_m() && r.index > REAL_MIN_INDEX {
                r.index -= 1;
            }
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
        let locked = self.radiating() && self.selection.as_ref().is_some_and(|s| s.locked);
        if !matches!(self.mode, Mode::Tws | Mode::Stt) && locked && self.air_to_air {
            self.set_mode(Mode::Stt);
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
        self.dirty = true;
        self.live = None;
        if !self.radiating() {
            return; // the first update that radiates scans
        }
        self.next_scan = now + self.frame_time();
        let since = now - self.last_scan;
        self.last_scan = now;
        if self.mode == Mode::Stt {
            self.strobes.clear();
            return; // STT's list is its track
        }
        let own = &input.own;
        let air = !self.mode.air_to_ground();
        let cone = self.mode.cone_cos();
        let vol = self.volume();
        let vsr = self.mode == Mode::Lrs && self.real.as_ref().is_some_and(|r| r.vsr);
        let gate = if air { self.gate_kt() } else { 0.0 };
        let scale = self.range_m();
        let centre = own.pos + own.fwd.flat_dir() * (scale / 2.0);
        let detection = self.ranges.get(self.mode).map_or(0.0, Range::detection_m);
        // Ours, the real FCR's SEA: ships only.
        let sea = self.mode == Mode::Map && self.real.as_ref().is_some_and(|r| r.sea);
        let test = |u: &Unit| {
            if sea && !SHIP_CLASSES.contains(&u.class) {
                return None;
            }
            hit(u, own, air, cone, vol.as_ref(), input.terrain)
                .filter(|c| !vsr || c.closure_kt > 0.0)
                .filter(|c| !notched(c, own, gate, detection, input.terrain))
                .map(|c| Contact { seen: now, ..c })
        };
        let old = self.selection.take();
        let mut old_unit = None;
        let mut list = Vec::new();
        let mut strobes = Vec::new();
        for u in input.units.iter().filter(|u| u.alive()) {
            if (u.pos - centre).length_squared() >= QUERY_K * (u.coll_radius + scale / 2.0).powi(2)
                || !self.mode.sees(u)
            {
                continue;
            }
            if old.as_ref().is_some_and(|s| s.key == u.key) {
                old_unit = Some(u);
            }
            // Ours: a jammer beyond its burn-through shows as a strobe at its azimuth (docs/radar.md §8).
            if u.strobe_from(detection, own.pos) {
                if let Some(c) = hit(u, own, air, cone, vol.as_ref(), input.terrain) {
                    strobes.push(c.az);
                }
                continue;
            }
            if u.pos.distance(own.pos) <= u.reach_from(detection, own.pos) {
                let record = test(u);
                self.detected(&record);
                insert(&mut list, record);
            }
        }
        // The old selection is kept while its unit is in the query, re-tested without the range.
        if let Some(u) = old_unit.filter(|u| !list.iter().any(|c: &Contact| c.key == u.key)) {
            let record = test(u);
            self.detected(&record);
            insert(&mut list, record);
        }
        // Ours, the real FCR: SAM's tracks stay listed (sam_track revisits them); TWS keeps its track files 13 s
        // without a return, extrapolated, at most 10.
        let keep = |c: &Contact| match (self.mode, &self.real) {
            (Mode::Lrs, Some(r)) => r.sam.contains(&c.key),
            (Mode::Tws, Some(_)) => now - c.seen < TWS_KEEP,
            _ => false,
        };
        let kept: Vec<Contact> = self
            .contacts
            .iter()
            .filter(|c| keep(c) && !list.iter().any(|n| n.key == c.key))
            .map(|c| if self.mode == Mode::Tws { c.extrapolated(since, own) } else { c.clone() })
            .collect();
        for c in kept {
            insert(&mut list, Some(c));
        }
        if self.real.is_some() && self.mode == Mode::Tws {
            list.truncate(TWS_FILES);
        }
        // TGT HIS: RWS keeps its last frames' search returns (TGT HIS n shows n frames, the current one included).
        if let Some(r) = &mut self.real
            && self.mode == Mode::Lrs
            && !r.vsr
        {
            let old: Vec<Contact> = self.contacts.iter().filter(|c| !r.sam.contains(&c.key)).cloned().collect();
            r.history.insert(0, old);
            r.history.truncate(r.cntl[CNTL_TGT_HIS]);
        }
        self.contacts = list;
        self.strobes = if air { strobes } else { Vec::new() };
        // The cursor: the old selection if still listed, else the nearest (its RWR hears a lock); the real FCR's
        // search waits for the pilot's bug.
        let auto = self.real.is_none() || matches!(self.mode, Mode::Acm | Mode::Bore);
        self.selection = match old {
            Some(s) if self.contact(&s.key).is_some() => Some(s),
            old => {
                if let Some(s) = old {
                    self.notify(&s.key, false);
                }
                let nearest = self.contacts.first().map(|c| c.key.clone()).filter(|_| auto);
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
        // Ours: the real FCR's GM / GMT / SEA picture of this frame.
        if self.real.is_some() && self.mode.air_to_ground() {
            self.render(input);
        }
    }

    // --- STT track (FUN_004b1300, every frame) ------------------------------------------------------

    fn track(&mut self, input: &Input) {
        let Some(key) = self.stt.as_ref().map(|s| s.key.clone()) else { return };
        let Some(&range) = self.ranges.get(Mode::Stt) else { return };
        let record = input
            .unit(&key)
            .filter(|u| u.alive() && u.pos.distance(input.own.pos) <= u.reach_from(range.detection_m(), input.own.pos))
            .and_then(|u| hit(u, &input.own, true, CONE_COS, None, input.terrain))
            .filter(|c| !notched(c, &input.own, self.gate_kt(), range.detection_m(), input.terrain));
        let Some(record) = record else {
            self.unlock();
            return;
        };
        // Auto-range (FUN_004b1590); the real FCR's at its own fractions, from 10 NM.
        let ((down, up), min) =
            if self.real.is_some() { (REAL_STT, REAL_MIN_INDEX) } else { ((AUTO_DOWN, AUTO_UP), 1) };
        if let Some(r) = self.ranges.get_mut(Mode::Stt) {
            while r.index > min && record.dist < down * r.scale_m() {
                r.index -= 1;
            }
            while r.index < r.max && record.dist > up * r.scale_m() {
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
        // Ours: the first mode press out of STBY gives the last A-A mode.
        if self.ours && !self.mode.radiating() {
            return self.toggle_aa_ag(now, input);
        }
        self.auto_on = false;
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
        } else if let Some(r) = &mut self.real {
            // Ours, the real FCR (the mode menu's GM, GMT, SEA; fig. 1-77): GM → GMT → SEA → GM. A lock, FZ and the
            // DBS steps go.
            (self.last_ag, r.sea) = match (self.mode, r.sea) {
                (Mode::Map, false) => (Mode::Gmt, false),
                (Mode::Gmt, _) => (Mode::Map, true),
                _ => (Mode::Map, false),
            };
            r.frozen = None;
            r.fov = r.fov.min(1);
            self.mode = self.last_ag;
            self.unlock();
            self.selection = None;
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
        self.auto_on = false;
        let was_off = !self.mode.radiating();
        self.unlock();
        self.selection = None;
        self.air_to_air = !self.air_to_air || was_off;
        self.mode = if self.air_to_air { self.last_aa } else { self.last_ag };
        if let Some(r) = &mut self.real {
            r.frozen = None;
        }
        self.switch_on(was_off, now, input);
        self.illumination_lost();
    }

    /// Ours, the F-16's DGFT / MSL OVRD switch (modern-iaf/docs/ufc.md): mode `m` at once, from any mode (ACM
    /// for DGFT, LRS = CRM for MSL OVRD; the mode before when the switch is centred again). A lock stays (STT is kept,
    /// inferred); OFF / STBY go to standby; a mode the jet's radar lacks is ignored.
    pub fn override_mode(&mut self, m: Mode, now: f64, input: &Input) {
        if self.damaged || self.mode == Mode::Stt || m == Mode::Stt || m == self.mode {
            return;
        }
        if !m.radiating() {
            return self.standby();
        }
        if !m.air_to_ground() && self.ranges.get(m).is_none() {
            return;
        }
        self.auto_on = false;
        let was_off = !self.mode.radiating();
        self.unlock();
        self.selection = None;
        self.air_to_air = !m.air_to_ground();
        if self.air_to_air {
            self.last_aa = m;
        } else {
            self.last_ag = m;
        }
        self.mode = m;
        if let Some(r) = &mut self.real {
            r.frozen = None;
        }
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
        self.auto_on = false;
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
        let real = self.real.is_some();
        // The real FCR's ACM and BORE stay at 10 NM.
        if !self.radiating() || self.mode == Mode::Stt || (real && matches!(self.mode, Mode::Acm | Mode::Bore)) {
            return;
        }
        let min = if real { REAL_MIN_INDEX } else { 1 };
        if let Some(r) = self.ranges.get_mut(self.mode) {
            r.index = r.index.saturating_add_signed(step).clamp(min, r.max);
        }
        // Ours, the real FCR's A-G: a range step returns EXP / DBS to NORM and ends FZ (inferred from a simulator).
        if let Some(r) = &mut self.real
            && self.mode.air_to_ground()
        {
            r.fov = 0;
            r.frozen = None;
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

    /// Return / Shift+Return (events 0x26 / 0x27, `FUN_004adbc0` → the mode's vt+0x2c, cursor walk `FUN_004aefd0`):
    /// the cursor walks to the next (farther) or previous contact, wrapping; it becomes the selection; LRS also locks
    /// it (→ STT, `FUN_004b21e0`); GMT / MAP drop the lock, walk and lock the new selection (`FUN_004b0cb0`:
    /// `FUN_004b0680`, walk, `FUN_004b06b0`), so there a single contact gets locked too; STT unlocks.
    pub fn next_target(&mut self, forward: bool) {
        if !self.radiating() {
            return;
        }
        self.illumination_lost(); // FUN_00458130
        if self.mode == Mode::Stt {
            self.unlock();
            return;
        }
        let n = self.contacts.len();
        if n >= 2 {
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
        }
        if self.mode.air_to_ground()
            && let Some(s) = &mut self.selection
        {
            s.locked = true;
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
        // Ours, the real FCR's RWS: the first press bugs the target (SAM), a press on the SAM primary locks it.
        if self.mode == Mode::Lrs
            && self.sam_primary() != Some(key)
            && let Some(r) = &mut self.real
        {
            r.sam.retain(|k| k != key);
            r.sam.push(key.to_owned());
            if r.sam.len() > r.fcr.sam_tracks.max(1) {
                let gone = r.sam.remove(0);
                self.notify(&gone, false);
            }
            if let Some(s) = self.selection.take().filter(|s| s.key != key) {
                self.notify(&s.key, false);
            }
            self.selection = Some(Selection { key: key.to_owned(), locked: false });
            self.notify(key, true);
            self.dirty = true;
            return true;
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

    /// Event 0x32 (`FUN_004add20`, a TWS press on a contact): the mode's vt+0x38(key, 0) → vt+0x34 `FUN_004b05a0`
    /// with the lock flag 0: that contact becomes the selection, unlocked (a locked selection of the same unit
    /// stays); no illumination loss, no mode change.
    pub fn select_key(&mut self, key: &str) -> bool {
        if !self.radiating() || self.contact(key).is_none() {
            return false;
        }
        if self.selection.as_ref().is_some_and(|s| s.locked && s.key == key) {
            return true;
        }
        if let Some(s) = self.selection.take() {
            self.notify(&s.key, false);
        }
        self.selection = Some(Selection { key: key.to_owned(), locked: false });
        self.notify(key, true);
        self.dirty = true;
        true
    }

    /// Backspace (event 0x31, `FUN_004add60`): drop the lock (STT → the last A-A mode); without a lock it clears
    /// the designated point (the EXP flag stays).
    pub fn deselect(&mut self, now: f64, input: &Input) {
        if self.mode == Mode::Lrs && self.real.as_ref().is_some_and(|r| !r.sam.is_empty()) {
            self.drop_bugs();
            return;
        }
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

    /// Event 0x30 (`FUN_004ade70`, MAP page OSB 3): NORM ↔ EXP, only with a designated point. Ours, the real FCR's
    /// OSB 3 / the pinky switch in CRM's RWS and TWS: EXP about the bugged target, else about the cursor.
    pub fn toggle_exp(&mut self) {
        if self.real.is_some() && self.mode.air_to_ground() {
            return self.step_fov();
        }
        if let Some(r) = &mut self.real
            && matches!(self.mode, Mode::Lrs | Mode::Tws)
            && !r.vsr
        {
            r.exp = !r.exp;
            r.exp_at = r.cursor;
            self.dirty = true;
            return;
        }
        if self.designated.is_some() {
            self.expanded = !self.expanded;
            self.dirty = true;
        }
    }

    // --- ours: the real FCR's controls (docs/radar.md §9) -------------------------------------------------

    /// SAM's or TWS's bugs dropped (TMS down; Backspace in SAM).
    fn drop_bugs(&mut self) {
        if let Some(r) = &mut self.real {
            for key in std::mem::take(&mut r.sam) {
                self.events.push(Event::Lock { key, on: false });
            }
        }
        if let Some(s) = self.selection.take() {
            self.notify(&s.key, false);
        }
        self.dirty = true;
    }

    /// The target under the acquisition cursor, the nearest within `CURSOR_NEAR` of the scope.
    pub fn under_cursor(&self) -> Option<&Contact> {
        let (cx, cy) = self.cursor_xy()?;
        let off = |c: &&Contact| {
            let (x, y) = self.scope_xy(c);
            (x - cx).abs().max((y - cy).abs())
        };
        self.contacts.iter().filter(|c| off(c) < CURSOR_NEAR).min_by(|a, b| off(a).total_cmp(&off(b)))
    }

    /// The TMS (keys; docs/radar.md §9.4). Up: in RWS / VSR bug the target under the cursor (SAM), on the bugged
    /// one lock it (STT); in TWS bug, on the bug lock; in ACM go to BORE. Down: drop the lock (STT) or the bugs; ACM,
    /// and a lock taken in ACM, back to the 30 × 20 pattern. Right: CRM's submode RWS → TWS → VSR (inferred: the real switch toggles RWS /
    /// TWS, VSR is on OSB 2); ACM the 10 × 60 pattern. Left: ACM's SLEW pattern (inferred); in CRM the AIFF (G13,
    /// later).
    pub fn tms(&mut self, dir: Tms, now: f64, input: &Input) {
        if self.real.is_none() || self.damaged || !self.mode.radiating() {
            return;
        }
        self.auto_on = false;
        let acm = matches!(self.mode, Mode::Acm | Mode::Bore);
        match dir {
            Tms::Up if self.mode == Mode::Acm => {
                self.bore_return = Mode::Acm;
                self.mode = Mode::Bore;
                self.scan(now, input);
            }
            Tms::Up if matches!(self.mode, Mode::Lrs | Mode::Tws) => {
                let Some(key) = self.under_cursor().map(|c| c.key.clone()) else { return };
                if self.mode == Mode::Tws && !self.selection.as_ref().is_some_and(|s| s.key == key) {
                    self.select_key(&key);
                } else {
                    self.lock_key(&key);
                }
            }
            Tms::Up if self.mode.air_to_ground() => self.ground_track(now, input),
            Tms::Down if self.mode.air_to_ground() => self.ground_drop(now, input),
            Tms::Down if self.mode == Mode::Stt && self.last_aa == Mode::Acm => {
                self.acm_pattern(Acm::Twenty, now, input)
            }
            Tms::Down if self.mode == Mode::Stt => self.deselect(now, input),
            Tms::Down if acm => self.acm_pattern(Acm::Twenty, now, input),
            Tms::Down if matches!(self.mode, Mode::Lrs | Mode::Tws) => self.drop_bugs(),
            Tms::Right if acm => self.acm_pattern(Acm::Sixty, now, input),
            Tms::Left if acm => self.acm_pattern(Acm::Slew, now, input),
            Tms::Right if matches!(self.mode, Mode::Lrs | Mode::Tws) => self.cycle_submode(now, input),
            _ => {}
        }
    }

    /// An ACM pattern (out of BORE, a lock dropped).
    fn acm_pattern(&mut self, p: Acm, now: f64, input: &Input) {
        if let Some(r) = &mut self.real {
            r.acm = p;
        }
        self.unlock();
        self.selection = None;
        self.bore_held = false;
        self.last_aa = Mode::Acm;
        self.mode = Mode::Acm;
        self.illumination_lost();
        self.scan(now, input);
    }

    /// OSB 2: CRM's submode RWS → TWS → VSR → RWS; ACM's pattern 20 → 60 → SLEW → BORE → 20.
    pub fn cycle_submode(&mut self, now: f64, input: &Input) {
        let Some(r) = &mut self.real else { return };
        if self.damaged || !self.mode.radiating() || !self.air_to_air {
            return;
        }
        match self.mode {
            Mode::Lrs if !r.vsr => self.mode = Mode::Tws,
            Mode::Tws => {
                r.vsr = true;
                self.mode = Mode::Lrs;
            }
            Mode::Lrs => r.vsr = false,
            Mode::Acm if r.acm == Acm::Slew => {
                self.bore_return = Mode::Acm;
                self.mode = Mode::Bore;
            }
            Mode::Acm => {
                let next = if r.acm == Acm::Twenty { Acm::Sixty } else { Acm::Slew };
                return self.acm_pattern(next, now, input);
            }
            Mode::Bore => return self.acm_pattern(Acm::Twenty, now, input),
            _ => return,
        }
        self.drop_bugs();
        if matches!(self.mode, Mode::Lrs | Mode::Tws) {
            self.last_aa = self.mode;
        }
        self.illumination_lost();
        self.scan(now, input);
    }

    /// OSB 18: the azimuth scan A6 → A3 → A1 (TWS: its three scans); OSB 17: the bars B4 → B1 → B2 (TWS: as OSB 18).
    pub fn step_scan(&mut self, bars: bool) {
        let mode = self.mode;
        let Some(r) = &mut self.real else { return };
        match mode {
            Mode::Tws => r.tws = (r.tws + 1) % TWS_SCANS.len(),
            Mode::Lrs if bars => r.rws_bars = (r.rws_bars + 1) % RWS_BARS.len(),
            Mode::Lrs => r.rws_az = (r.rws_az + 1) % RWS_AZ.len(),
            _ => return,
        }
        self.dirty = true;
    }

    /// The antenna elevation thumbwheel (−1 down … 1 up, 0 stops) and the cursor's slew (x right, y up, −1..1).
    pub fn set_slews(&mut self, elevation: Option<f64>, cursor: Option<(f64, f64)>) {
        let Some(r) = &mut self.real else { return };
        if let Some(e) = elevation {
            r.elev_rate = e.clamp(-1.0, 1.0);
        }
        if let Some((x, y)) = cursor {
            r.slew = (x.clamp(-1.0, 1.0), y.clamp(-1.0, 1.0));
        }
    }

    /// The cursor put at a place on the display (a mouse move over the FCR; EXP's display maps back to NORM).
    pub fn set_cursor(&mut self, x: f64, y: f64) {
        let (x, y) = self.exp_centre().map_or((x, y), |c| (c.0 + (x - 0.5) / EXP_K, c.1 + (y - 0.5) / EXP_K));
        if let Some(r) = &mut self.real {
            r.cursor = (x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
        }
    }

    /// A press on the CNTL page's OSB `osb`: its option steps to the next value.
    pub fn cntl_press(&mut self, osb: u8) {
        let Some(r) = &mut self.real else { return };
        if let Some(i) = CNTL.iter().position(|o| o.0 == osb) {
            r.cntl[i] = (r.cntl[i] + 1) % CNTL[i].2.len();
            if i == CNTL_TGT_HIS {
                r.history.truncate(r.cntl[i]);
            }
        }
    }

    /// OSB 4 OVRD: radiating off and on again.
    pub fn toggle_ovrd(&mut self) {
        let Some(r) = &mut self.real else { return };
        r.ovrd = !r.ovrd;
        if r.ovrd {
            self.silence();
        }
        self.dirty = true;
    }

    /// Radiating stopped (OVRD, weight on wheels): the bugs, the lock, the contacts and the target history go.
    fn silence(&mut self) {
        self.drop_bugs();
        self.unlock();
        self.contacts.clear();
        self.selection = None;
        if let Some(r) = &mut self.real {
            r.history.clear();
            // The A-G picture goes too (a new serial, no bytes).
            r.picture = Picture { frame: None, la8: Vec::new(), serial: r.picture.serial + 1 };
        }
        self.illumination_lost();
    }

    // --- ours: the real FCR's air-to-ground modes (docs/radar.md §9.7) ------------------------------------------

    /// The A-G mode's name (OSB 1): `GM`, `GMT`, `SEA`, or `AGR` while a visual delivery ranges; None outside A-G.
    pub fn ag_mode(&self) -> Option<&'static str> {
        let r = self.real.as_ref()?;
        Some(match self.mode {
            _ if r.agr_at.is_some() && self.mode.air_to_ground() => "AGR",
            Mode::Gmt => "GMT",
            Mode::Map if r.sea => "SEA",
            Mode::Map => "GM",
            _ => return None,
        })
    }

    /// The field of view's expansion (1 NORM, 4 EXP, 8 DBS1, 64 DBS2).
    pub fn zoom(&self) -> f64 {
        self.real.as_ref().map_or(1.0, |r| AG_FOV[r.fov].1)
    }

    /// The A-G display's frame: FZ's frozen one; NORM the PPI fan from the jet, heading-up, the fan's radius the
    /// range scale; EXP / DBS the patch about the ground cursor, mid-display, the range scale over the zoom.
    pub fn ground_frame(&self) -> Option<GroundFrame> {
        let r = self.real.as_ref()?;
        if !self.mode.air_to_ground() {
            return None;
        }
        if r.frozen.is_some() {
            return r.frozen;
        }
        let k = self.range_m() / FAN_PX / self.zoom();
        Some(match r.ground {
            Some(g) if r.fov > 0 => GroundFrame { centre: g, yaw: self.own.yaw, k, sym: PATCH_CENTRE },
            _ => GroundFrame { centre: self.own.pos, yaw: self.own.yaw, k, sym: FAN_APEX },
        })
    }

    /// The ground cursor's place on the display (MFD px).
    pub fn ground_cursor_px(&self) -> Option<(f64, f64)> {
        Some(self.ground_frame()?.to_px(self.real.as_ref()?.ground?))
    }

    /// The point the A-G weapons aim at (the SPI): the real FCR's ground track (FTT / GMT's), else the designated
    /// point. The original's radar: the designated point only.
    pub fn target_point(&self) -> Option<Vec3> {
        if self.real.is_some()
            && self.mode.air_to_ground()
            && let Some(c) = self.locked()
        {
            return Some(c.pos);
        }
        self.designated
    }

    /// The ground cursor's bearing off the ground track (deg).
    fn off_track(&self, g: Vec3) -> f64 {
        let own = &self.own;
        let track = if own.vel.flat_dir() == Vec3::ZERO { own.fwd } else { own.vel };
        let (t, d) = (track.flat_dir(), (g - own.pos).flat_dir());
        t.dot(d).clamp(-1.0, 1.0).acos().to_degrees()
    }

    /// The A-G per frame: the ground cursor follows the slew (ground-stabilised), SP holds it half the range ahead, a
    /// ground track carries it; DBS inside the notch falls back to EXP; the cursor bumps the range scale in NORM; AGR
    /// ranges along its aim line.
    fn ground_controls(&mut self, dt: f64, now: f64, input: &Input) {
        let own = input.own;
        let range = self.range_m();
        let frame = self.ground_frame();
        let locked = self.locked().map(|c| c.pos);
        let radiating = self.radiating();
        let Some(r) = &mut self.real else { return };
        let ahead = own.pos + own.fwd.flat_dir() * (range / 2.0);
        let mut g = r.ground.unwrap_or_else(|| own.steer.filter(|s| s.distance(own.pos) < range).unwrap_or(ahead));
        if r.slew != (0.0, 0.0) {
            r.snowplow = false;
        }
        if let Some(p) = locked {
            g = p;
        } else if r.snowplow {
            g = ahead;
        } else if let Some(f) = frame {
            let (s, c) = f.yaw.sin_cos();
            let rate = GROUND_SLEW * PIC_WINDOW.2 as f64 * f.k * dt;
            g.x += (r.slew.0 * c + r.slew.1 * s) * rate;
            g.y += (-r.slew.0 * s + r.slew.1 * c) * rate;
        }
        g.z = (input.terrain)(g).unwrap_or(0.0);
        r.ground = Some(g);
        r.agr = r.agr_at.filter(|_| radiating).and_then(|p| ground_hit(own.pos, p - own.pos, input.terrain));
        let notch = self.off_track(g) < DBS_NOTCH_DEG;
        let Some(r) = &mut self.real else { return };
        if r.fov >= 2 && notch {
            r.fov = 1;
        }
        // NORM: the cursor slewed beyond 95 % of the scale steps it up, inside 5 % down (p. 1-122, as in A-A).
        if r.fov == 0 && r.frozen.is_none() && locked.is_none() && !r.snowplow && r.slew != (0.0, 0.0) {
            let rel = Vec3::new(g.x - own.pos.x, g.y - own.pos.y, 0.0);
            let ahead = rel.dot(own.fwd.flat_dir());
            let frac = rel.length() / range;
            let step = i8::from(frac > BUMP.1) - i8::from(ahead > 0.0 && frac < BUMP.0);
            let index = self.range_index();
            let max = self.ranges.get(self.mode).map_or(1, |x| x.max);
            if (step > 0 && index < max) || (step < 0 && index > REAL_MIN_INDEX) {
                self.step_range(step, now, input);
            }
        }
    }

    /// OSB 3 / the pinky switch in A-G: NORM → EXP → DBS1 → DBS2 → NORM in GM; GMT and SEA NORM ↔ EXP; DBS skipped
    /// inside the notch.
    fn step_fov(&mut self) {
        let max = if self.mode == Mode::Map && !self.real.as_ref().is_some_and(|r| r.sea) { 3 } else { 1 };
        let notch = self.real.as_ref().and_then(|r| r.ground).is_some_and(|g| self.off_track(g) < DBS_NOTCH_DEG);
        let Some(r) = &mut self.real else { return };
        r.fov = if r.fov >= max || (r.fov >= 1 && notch) { 0 } else { r.fov + 1 };
        r.frozen = None;
        self.dirty = true;
        self.next_scan = self.now; // a new picture at once
    }

    /// TMS up in A-G: a return under the cursor is tracked (GM / SEA: FTT, GMT: the mover; the solid diamond), else
    /// the cursor's point is designated (the target point). SP ends: the cursor stays where it is.
    fn ground_track(&mut self, now: f64, input: &Input) {
        let Some(f) = self.ground_frame() else { return };
        let Some((cx, cy)) = self.ground_cursor_px() else { return };
        let near = |c: &Contact| {
            let (x, y) = f.to_px(c.pos);
            (x - cx).hypot(y - cy)
        };
        let key = self
            .contacts
            .iter()
            .filter(|c| near(c) < CURSOR_NEAR * 100.0)
            .min_by(|a, b| near(a).total_cmp(&near(b)))
            .map(|c| c.key.clone());
        if let Some(r) = &mut self.real {
            r.snowplow = false;
            r.tgt = true;
        }
        match key {
            Some(key) => {
                self.designated = None;
                self.lock_key(&key);
            }
            None => {
                let g = self.real.as_ref().and_then(|r| r.ground).unwrap_or_default();
                self.designate(g, now, input);
            }
        }
    }

    /// TMS down in A-G: the track or the designation is dropped and the cursor returns to the steerpoint (STP).
    fn ground_drop(&mut self, now: f64, input: &Input) {
        if self.has_lock() {
            self.unlock();
            self.selection = None;
            self.illumination_lost();
        }
        self.designated = None;
        if let Some(r) = &mut self.real {
            r.tgt = false;
        }
        self.cursor_zero(input);
        self.scan(now, input);
    }

    /// CZ: the cursor's slews removed: back on the steerpoint (STP) or the designated point (TGT); with neither, half
    /// the range ahead.
    fn cursor_zero(&mut self, input: &Input) {
        let own = input.own;
        let ahead = own.pos + own.fwd.flat_dir() * (self.range_m() / 2.0);
        let target = self.designated;
        let Some(r) = &mut self.real else { return };
        let mut g = if r.tgt { target.or(own.steer) } else { own.steer }.unwrap_or(ahead);
        g.z = (input.terrain)(g).unwrap_or(0.0);
        r.ground = Some(g);
        r.snowplow = false;
    }

    /// The GM format's right-edge OSBs: 7 FZ (freeze), 8 SP (snowplow), 9 CZ (cursor zero), 10 STP / TGT.
    pub fn ag_press(&mut self, osb: u8, now: f64, input: &Input) {
        if !self.mode.air_to_ground() || self.real.is_none() {
            return;
        }
        let frame = self.ground_frame();
        let Some(r) = &mut self.real else { return };
        match osb {
            7 => r.frozen = if r.frozen.is_some() { None } else { frame },
            8 => r.snowplow = !r.snowplow,
            9 => self.cursor_zero(input),
            10 => r.tgt = !r.tgt,
            _ => return,
        }
        self.dirty = true;
        if osb == 7 && self.real.as_ref().is_some_and(|r| r.frozen.is_none()) {
            self.scan(now, input);
        }
    }

    /// The ground cursor put on a world point (a mouse move over the A-G display); SP ends.
    pub fn set_ground_cursor(&mut self, w: Vec3) {
        if let Some(r) = &mut self.real {
            r.ground = Some(w);
            r.snowplow = false;
        }
    }

    /// AGR: a visual A-G delivery's aim point (the CCIP pipper's ground point), None: no visual delivery.
    pub fn set_agr(&mut self, at: Option<Vec3>) {
        if let Some(r) = &mut self.real {
            r.agr_at = at;
            if at.is_none() {
                r.agr = None;
            }
        }
    }

    /// The runways the GM picture shows dark.
    pub fn set_runways(&mut self, runways: Vec<Runway>) {
        if let Some(r) = &mut self.real {
            r.runways = runways;
        }
    }

    /// The GM picture of this frame (radar.md §9.7): each px of `PIC_WINDOW` at its ground point. The ground returns
    /// by the terrain's slope toward the radar with a fixed speckle (land), none from water (the sea level) and
    /// runways, none in the terrain's shadow; NORM only inside the ±60° fan; the listed returns bright, as large as
    /// their units; GMT's map dimmed under its movers; no data (unstreamed terrain): transparent. Inferred shading.
    fn render(&mut self, input: &Input) {
        let Some(f) = self.ground_frame() else { return };
        let Some(r) = &self.real else { return };
        if r.agr_at.is_some() {
            return;
        }
        let ground = input.bare.unwrap_or(input.terrain);
        let own = input.own.pos.raised(LOS_RAISE);
        let (x0, y0, w, h) = PIC_WINDOW;
        let gain = if self.mode == Mode::Gmt { GMT_DIM } else { 1.0 };
        let fan = f.sym == FAN_APEX;
        let d = (f.k * 0.75).max(10.0);
        let mut la8 = vec![0u8; w * h * 2];
        // The terrain's shadow by azimuth: out along each bin's ray from the jet, the steepest rise seen so far (tan of
        // its elevation) at each step; a point lower than that is in shadow. One march per 0.25° bin, not per px.
        let corners = [(x0, y0), (x0 + w as f64, y0), (x0, y0 + h as f64), (x0 + w as f64, y0 + h as f64)];
        let reach = corners.iter().map(|&q| f.from_px(q).distance(Vec3::new(own.x, own.y, 0.0))).fold(0.0, f64::max);
        let step = (f.k * 0.75).max(20.0).max(reach / 2000.0);
        let mut horizon: std::collections::HashMap<i64, Vec<f64>> = std::collections::HashMap::new();
        let mut shadowed = |p: Vec3| -> bool {
            let (dx, dy) = (p.x - own.x, p.y - own.y);
            let dist = dx.hypot(dy);
            let bin = (dx.atan2(dy).to_degrees() * 4.0).round() as i64;
            let prof = horizon.entry(bin).or_insert_with(|| {
                let a = (bin as f64 / 4.0).to_radians();
                let (sa, ca) = a.sin_cos();
                let mut best = f64::NEG_INFINITY;
                (0..=(reach / step) as usize + 1)
                    .map(|i| {
                        let seen = best;
                        let s = i as f64 * step;
                        if let Some(g) = ground(Vec3::new(own.x + s * sa, own.y + s * ca, 0.0)).filter(|_| s > 0.0) {
                            best = best.max((g - own.z) / s);
                        }
                        seen
                    })
                    .collect()
            });
            let i = ((dist / step) as usize).min(prof.len() - 1);
            dist > step && (p.z - own.z) / dist < prof[i] - 1e-3
        };
        for j in 0..h {
            for i in 0..w {
                let (x, y) = (x0 + i as f64 + 0.5, y0 + j as f64 + 0.5);
                let at = 2 * (j * w + i);
                if fan {
                    let (dx, dy) = (x - FAN_APEX.0, FAN_APEX.1 - y);
                    if dy <= 0.0 || dx.abs() > dy * 3f64.sqrt() || dx.hypot(dy) > FAN_PX {
                        la8[at + 1] = 255; // black outside the fan
                        continue;
                    }
                }
                let mut p = f.from_px((x, y));
                let Some(z) = ground(p) else { continue };
                p.z = z;
                la8[at + 1] = 255;
                let water = z.abs() < 0.5;
                if water || r.runways.iter().any(|rw| rw.holds(p)) {
                    continue;
                }
                let hx = ground(Vec3::new(p.x + d, p.y, 0.0)).unwrap_or(z) - z;
                let hy = ground(Vec3::new(p.x, p.y + d, 0.0)).unwrap_or(z) - z;
                let n = Vec3::new(-hx / d, -hy / d, 1.0);
                let look = own - p;
                let cos = (n.dot(look) / (n.length() * look.length()).max(1e-9)).max(0.0);
                if shadowed(p) {
                    continue;
                }
                let v = (0.12 + 0.88 * cos.powf(1.5)) * speckle(p) * gain;
                la8[at] = (v * 255.0).clamp(0.0, 255.0) as u8;
            }
        }
        for c in &self.contacts {
            let (cx, cy) = f.to_px(c.pos);
            let rad = (input.unit(&c.key).map_or(5.0, |u| u.coll_radius) / f.k).max(0.8);
            let reach = rad.ceil() as i64;
            for dj in -reach..=reach {
                for di in -reach..=reach {
                    let (x, y) = (cx + di as f64, cy + dj as f64);
                    if (di as f64).hypot(dj as f64) > rad || x < x0 || y < y0 {
                        continue;
                    }
                    let (i, j) = ((x - x0) as usize, (y - y0) as usize);
                    if i < w && j < h {
                        la8[2 * (j * w + i)] = 255;
                        la8[2 * (j * w + i) + 1] = 255;
                    }
                }
            }
        }
        let serial = r.picture.serial + 1;
        if let Some(r) = &mut self.real {
            r.picture = Picture { frame: Some(f), la8, serial };
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
        // Ours: powered again, the radar comes up in STBY (G1).
        if !on && self.damaged && self.ours {
            self.mode = Mode::Standby;
            self.air_to_air = true;
            self.auto_on = true;
        }
        self.damaged = on;
        self.dirty = true;
    }
}

/// The hit test (`FUN_004aeb90`) and the record: air modes skip targets below 30 m AGL; the horizontal cone about
/// the antenna only (no elevation limit); terrain line of sight (ends +1.5 m). Ours: inside the real FCR's scan
/// volume `vol` too.
fn hit(
    u: &Unit,
    own: &Own,
    air: bool,
    cone: f64,
    vol: Option<&Volume>,
    terrain: &dyn Fn(Vec3) -> Option<f64>,
) -> Option<Contact> {
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
    if let Some(v) = vol {
        let (a, e) = if v.body { body_angles(own, d) } else { (az.to_degrees(), (d.z / dist).asin().to_degrees()) };
        if !v.holds(a, e) {
            return None;
        }
    }
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
        mach: u.vel.length() / f64::from(iaf_flight::atmosphere::air(u.pos.z as f32).sound),
        type_code: u.type_code,
        closure_kt: (own.vel - u.vel).dot(d / dist) * KT,
        vel: u.vel,
        seen: 0.0,
    })
}

/// Ours, a pulse-Doppler radar's ground clutter (docs/radar.md §9.8): in look-down a contact whose speed along the line
/// of sight is under `gate_kt` sits in the ground's Doppler band and is lost (the beam notch, a slow drone).
fn notched(c: &Contact, own: &Own, gate_kt: f64, reach: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
    (c.vel.dot(c.pos - own.pos) / c.dist.max(1.0)).abs() * KT < gate_kt && look_down(own.pos, c.pos, reach, terrain)
}

/// Ours: the ground lies behind `to` seen from `from`: the line of sight, carried on past it, meets the ground (taken
/// level at the height under `to`, sea level where there is none) within `reach` (inferred; a flat earth).
fn look_down(from: Vec3, to: Vec3, reach: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
    let (d, drop) = (to - from, from.z - to.z);
    drop > 0.0 && d.x.hypot(d.y) * (from.z - terrain(to).unwrap_or(0.0)) / drop <= reach
}

/// Azimuth (+ right) and elevation (+ up) of `d` about the jet's own axes (deg).
fn body_angles(own: &Own, d: Vec3) -> (f64, f64) {
    let up = if own.up == Vec3::ZERO { Vec3::UP } else { own.up };
    let (x, y, z) = (d.dot(own.fwd.cross(up)), d.dot(own.fwd), d.dot(up));
    (x.atan2(y).to_degrees(), z.atan2(x.hypot(y)).to_degrees())
}

/// The GM picture's fixed speckle (0.85..1.15) on a 30 m grid: a hash of the ground cell, so the picture keeps it
/// frame to frame (inferred).
fn speckle(p: Vec3) -> f64 {
    let (i, j) = ((p.x / 30.0).floor() as i64, (p.y / 30.0).floor() as i64);
    let mut h = (i.wrapping_mul(73_856_093) ^ j.wrapping_mul(19_349_663)) as u64;
    h ^= h >> 13;
    h = h.wrapping_mul(0x5bd1_e995);
    h ^= h >> 15;
    0.85 + 0.3 * ((h & 0xffff) as f64 / 65535.0)
}

/// AGR: the slant range (m) from `from` along `dir` to where it meets the terrain, within `AGR_REACH`.
fn ground_hit(from: Vec3, dir: Vec3, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Option<f64> {
    let dir = dir.try_normalize()?;
    let mut s = 0.0;
    let mut last = 0.0;
    while s <= AGR_REACH {
        let p = from + dir * s;
        let h = p.z - terrain(p)?;
        if h <= 0.0 {
            // Back to the crossing between the last two samples.
            let prev = from + dir * last;
            let hp = prev.z - terrain(prev).unwrap_or(prev.z);
            return Some(last + (s - last) * hp / (hp - h).max(1e-9));
        }
        last = s;
        s += (h / 2.0).clamp(LOS_MIN_STEP / 4.0, 500.0);
    }
    None
}

/// Line-of-sight sampling: the smallest step (m) and the steepest terrain assumed (rise per metre).
const LOS_MIN_STEP: f64 = 20.0;
const LOS_MAX_SLOPE: f64 = 1.5;

/// Terrain line of sight (`FUN_004020d0`; the original's sampling is UNCERTAIN). Ours steps by clearance: where the
/// segment is h above the ground, the terrain (at most `LOS_MAX_SLOPE` steep) cannot reach it sooner than
/// h / (slope − the segment's own rise), so the step is that, at least `LOS_MIN_STEP`: a narrow ridge is never
/// stepped over, and a segment high above the terrain costs few samples. The end points are not tested.
pub fn line_of_sight(a: Vec3, b: Vec3, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
    let d = b - a;
    let len = d.length();
    if len <= LOS_MIN_STEP {
        return true;
    }
    let dir = d / len;
    let closing = (LOS_MAX_SLOPE - dir.z / dir.x.hypot(dir.y).max(1e-6)).max(0.1);
    let mut s = LOS_MIN_STEP;
    while s < len - LOS_MIN_STEP / 2.0 {
        let p = a + dir * s;
        let h = terrain(p).map_or(f64::INFINITY, |g| p.z - g);
        if h < 0.0 {
            return false;
        }
        s += (h / closing).clamp(LOS_MIN_STEP, len);
    }
    true
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

    const OWN: Own = Own {
        pos: Vec3::new(0.0, 0.0, 5000.0),
        fwd: Vec3::NORTH,
        yaw: 0.0,
        up: Vec3::UP,
        vel: Vec3::new(0.0, 250.0, 0.0),
        wow: false,
        steer: None,
    };

    fn scene(units: &[Unit]) -> Input<'_> {
        Input { own: OWN, units, terrain: &flat, bare: None }
    }

    fn keys(r: &Radar) -> Vec<&str> {
        r.contacts().iter().map(|c| c.key.as_str()).collect()
    }

    #[test]
    fn set_mode_for_dgft_and_back() {
        let mut r = Radar::new(1, None, None, false);
        let sc = scene(&[]);
        r.override_mode(Mode::Acm, 0.0, &sc);
        assert_eq!((r.mode(), r.air_to_air), (Mode::Acm, true), "DGFT from OFF: ACM radiating");
        r.override_mode(Mode::Map, 1.0, &sc);
        assert_eq!((r.mode(), r.air_to_air), (Mode::Map, false));
        r.override_mode(Mode::Lrs, 2.0, &sc);
        assert_eq!(r.mode(), Mode::Lrs);
        r.override_mode(Mode::Standby, 3.0, &sc);
        assert_eq!(r.mode(), Mode::Standby);
    }

    #[test]
    fn f16_table_range_and_cone() {
        let mut r = Radar::new(1, None, None, false);
        assert_eq!(r.mode(), Mode::Off);
        assert_eq!(r.ranges().get(Mode::Lrs), Some(&Range { max: 5, nm: 45.0, index: 4 }));
        r.toggle_aa_ag(0.0, &scene(&[jet("t", 0.0, 30000.0), jet("u", 0.0, 50.0 * NM)]));
        assert_eq!(r.mode(), Mode::Lrs);
        assert_eq!(keys(&r), ["t"]);
        let ev = r.take_events();
        assert!(ev.contains(&Event::Detected { key: "t".into() }), "the recorded unit becomes known");
        assert!(!ev.contains(&Event::Detected { key: "u".into() }), "beyond 45 NM: not detected");
        assert!(r.contacts()[0].aspect.abs() < 0.01, "flying away: aspect 0 (tail)");
        r.step_range(2, 1.0, &scene(&[jet("t", 0.0, 45.0 * NM + 500.0)]));
        assert_eq!(keys(&r), ["t"], "the selection beyond 45 NM is kept (re-tested without the range)");
        let a = 65f64.to_radians();
        r.scan(2.0, &scene(&[jet("t", 30000.0 * a.sin(), 30000.0 * a.cos())]));
        assert!(r.contacts().is_empty(), "65° off the nose: outside the 60° cone");
        assert!((r.scope_width() - 2.0 * PI / 3.0).abs() < 1e-9);
    }

    #[test]
    fn f16i_row() {
        let r = Radar::new(F16I, None, None, false);
        assert_eq!(r.ranges().get(Mode::Lrs), Some(&Range { max: 5, nm: 58.0, index: 5 }), "starts at 80 NM");
        assert_eq!(r.ranges().get(Mode::Tws).map(|t| t.nm), Some(45.0));
        assert_eq!(r.ranges().get(Mode::Stt).map(|t| t.nm), Some(58.0));
        assert_eq!(r.ranges().get(Mode::Map).map(|m| (m.max, m.nm)), Some((4, 40.0)));
        // The Sufa's aircraft definition names this row (radar.gd setup).
        assert_eq!(iaf_flight::airframe::get("f16i").and_then(|a| a.radar.as_ref()?.row), Some(F16I as u32));
    }

    #[test]
    fn f35i_row_starts_at_80_nm() {
        let r = Radar::new(F35I, None, None, false);
        assert_eq!(r.ranges().get(Mode::Lrs), Some(&Range { max: 5, nm: 80.0, index: 5 }));
        assert_eq!(r.ranges().get(Mode::Tws).map(|t| (t.nm, t.index)), Some((60.0, 5)));
        assert_eq!(r.ranges().get(Mode::Stt).map(|t| t.index), Some(5));
        assert_eq!(
            Radar::new(1, None, None, false).ranges().get(Mode::Lrs).map(|t| t.index),
            Some(4),
            "the originals at 40 NM"
        );
        // The F-35I's aircraft definition names this row (radar.gd setup).
        let def = iaf_flight::airframe::get("f35i").and_then(|a| a.radar.as_ref()?.row);
        assert_eq!(def, Some(F35I as u32));
    }

    #[test]
    fn list_keeps_the_15_nearest() {
        let mut list = Vec::new();
        for i in 0..20 {
            insert(
                &mut list,
                Some(Contact { key: i.to_string(), dist: 1000.0 * f64::from(20 - i), ..Default::default() }),
            );
        }
        assert_eq!(list.len(), MAX_CONTACTS);
        assert!(list.is_sorted_by(|a, b| a.dist <= b.dist));
        assert_eq!(list[0].key, "19");
    }

    #[test]
    fn stt_auto_range_and_lost_lock() {
        let mut r = Radar::new(1, None, None, false);
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
    fn gmt_return_locks_the_next_contact() {
        let units: Vec<Unit> = (0..3)
            .map(|i| Unit {
                class: 8,
                pos: Vec3::new(0.0, 5000.0 + 1000.0 * f64::from(i), 0.0),
                vel: Vec3::new(5.0, 0.0, 0.0),
                ..jet(&format!("t{i}"), 0.0, 0.0)
            })
            .collect();
        let mut r = Radar::new(1, None, None, false);
        r.toggle_aa_ag(0.0, &scene(&units));
        r.toggle_aa_ag(0.0, &scene(&units));
        assert_eq!(r.mode(), Mode::Gmt);
        assert_eq!(keys(&r), ["t0", "t1", "t2"]);
        assert_eq!(r.selection().map(|s| (s.key.as_str(), s.locked)), Some(("t0", false)));
        r.next_target(true);
        assert_eq!(r.selection().map(|s| (s.key.as_str(), s.locked)), Some(("t1", true)));
        r.next_target(false);
        assert_eq!(r.selection().map(|s| (s.key.as_str(), s.locked)), Some(("t0", true)));
        assert!(r.has_lock());
    }

    #[test]
    fn acm_locks_at_once() {
        let mut r = Radar::new(1, None, None, false);
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
        let mut r = Radar::new(1, None, None, false);
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
    fn tws_press_selects_without_a_lock() {
        let mut r = Radar::new(1, None, None, false);
        let units = [jet("t", 0.0, 20000.0), jet("u", 1000.0, 25000.0)];
        r.toggle_aa_ag(0.0, &scene(&units));
        r.cycle_mode(0.0, &scene(&units));
        assert_eq!(r.mode(), Mode::Tws);
        r.take_events();
        assert!(r.select_key("u"));
        assert_eq!(r.selection().map(|s| (s.key.as_str(), s.locked)), Some(("u", false)));
        assert_eq!(r.mode(), Mode::Tws, "a select keeps TWS");
        assert!(!r.take_events().contains(&Event::IlluminationLost));
        assert!((r.contact("u").unwrap().mach - 200.0 / 320.5).abs() < 0.01, "Mach at 5000 m");
        assert!(!r.select_key("nobody"));
    }

    #[test]
    fn terrain_hides_and_low_targets_skip() {
        let ridge = |p: Vec3| Some(if (9000.0..11000.0).contains(&p.y) { 6000.0 } else { 0.0 });
        let (a, b) = (Vec3::new(0.0, 0.0, 5000.0), Vec3::new(0.0, 20000.0, 5000.0));
        assert!(!line_of_sight(a, b, &ridge));
        assert!(line_of_sight(a, b, &flat));
        // A 30 m wide crest across a 17 km low line (a SAM site and a jet 30 m up): never stepped over.
        let crest = |p: Vec3| Some(if (8000.0..8030.0).contains(&p.y) { 60.0 } else { 0.0 });
        let (site, low_jet) = (Vec3::new(0.0, 0.0, 1.5), Vec3::new(0.0, 17000.0, 30.0));
        assert!(!line_of_sight(site, low_jet, &crest), "the crest hides the jet");
        assert!(line_of_sight(site, low_jet, &flat));
        // High above the terrain the steps grow: few samples.
        let n = std::cell::Cell::new(0);
        let count = |_: Vec3| {
            n.set(n.get() + 1);
            Some(0.0)
        };
        assert!(line_of_sight(Vec3::new(0.0, 0.0, 5000.0), Vec3::new(0.0, 70000.0, 5000.0), &count));
        assert!(n.get() < 40, "{} samples", n.get());
        let low = |_: Vec3| Some(4990.0);
        assert!(hit(&jet("t", 0.0, 20000.0), &OWN, true, CONE_COS, None, &low).is_none(), "10 m AGL");
        assert!(hit(&jet("t", 0.0, 20000.0), &OWN, false, CONE_COS, None, &low).is_some(), "ground modes see it");
    }

    // --- ours: the real FCR (docs/radar.md §9) ---

    fn sufa() -> Radar {
        Radar::new(F16I, None, Some(Fcr { sam_tracks: 4 }), true)
    }

    /// A jet `deg` right of the nose and `up` m above the own jet, `km` out.
    fn at(key: &str, deg: f64, km: f64, up: f64) -> Unit {
        let a = deg.to_radians();
        Unit { pos: Vec3::new(km * 1000.0 * a.sin(), km * 1000.0 * a.cos(), 5000.0 + up), ..jet(key, 0.0, 0.0) }
    }

    fn ground(units: &[Unit]) -> Input<'_> {
        Input { own: Own { wow: true, ..OWN }, units, terrain: &flat, bare: None }
    }

    /// Airborne: the radar comes out of STBY into CRM by itself.
    fn up(units: &[Unit]) -> Radar {
        let mut r = sufa();
        r.update(0.0, &scene(units));
        assert_eq!(r.mode(), Mode::Lrs);
        r
    }

    #[test]
    fn power_on_standby_weight_on_wheels_and_take_off() {
        let units = [at("t", 0.0, 20.0, 0.0)];
        let mut r = sufa();
        assert_eq!(r.mode(), Mode::Standby, "ours come up in STBY");
        assert_eq!(Radar::new(1, None, None, false).mode(), Mode::Off, "the originals start OFF");
        r.update(0.0, &ground(&units));
        assert_eq!(r.mode(), Mode::Standby, "on the ground it stays in STBY");
        r.cycle_mode(0.1, &ground(&units));
        r.update(0.2, &ground(&units));
        assert_eq!(r.mode(), Mode::Lrs, "a mode can be chosen on the ground");
        assert!(!r.radiating() && r.contacts().is_empty(), "but it does not radiate with weight on wheels");
        r.update(3.0, &scene(&units));
        assert_eq!(keys(&r), ["t"], "airborne it radiates");
        let mut r = sufa();
        r.update(0.0, &ground(&units));
        r.update(5.0, &scene(&units));
        assert_eq!((r.mode(), keys(&r)), (Mode::Lrs, vec!["t"]), "after take-off: CRM by itself");
        r.set_damaged(true);
        assert_eq!(r.mode(), Mode::Off);
        r.set_damaged(false);
        assert_eq!(r.mode(), Mode::Standby, "powered again: STBY");
        r.standby();
        r.update(6.0, &scene(&units));
        assert_eq!(r.mode(), Mode::Standby, "the pilot's STBY holds in the air");
        let mut r = up(&units);
        assert!(!r.contacts().is_empty());
        r.update(0.1, &ground(&units));
        assert!(r.contacts().is_empty() && r.selection().is_none(), "touched down: the returns go");
    }

    #[test]
    fn scan_width_bars_and_elevation() {
        let units = [at("wide", 40.0, 20.0, 0.0), at("low", 0.0, 20.0, -3500.0)];
        let mut r = up(&units);
        assert_eq!(keys(&r), ["wide"], "A6 B4: 40° right inside, 10° low outside the four bars");
        assert!((r.frame_time() - 8.0).abs() < 1e-9, "A6 B4: an 8 s frame");
        r.step_scan(false);
        r.step_scan(false);
        assert_eq!(r.real().map(|x| x.scan(false)), Some((10.0, 4)), "A1 B4");
        r.scan(1.0, &scene(&units));
        assert!(keys(&r).is_empty(), "A1: ±10° about the cursor");
        r.set_cursor(0.5 + 40.0 / 120.0, 0.5);
        r.scan(2.0, &scene(&units));
        assert_eq!(keys(&r), ["wide"], "the narrow scan centres on the cursor");
        r.set_cursor(0.5, 0.5);
        r.set_slews(Some(-1.0), None);
        r.update(2.2, &scene(&units));
        r.update(2.7, &scene(&units));
        r.update(3.2, &scene(&units));
        r.set_slews(Some(0.0), None);
        r.scan(4.0, &scene(&units));
        assert_eq!(keys(&r), ["low"], "the antenna down 15°: the low target");
        let (hi, lo) = r.cursor_alt(5000.0).unwrap();
        assert!(hi < 5000.0 / 0.3048 && lo < hi, "the cursor's coverage below the jet: {hi:.0} / {lo:.0} ft");
        r.step_scan(true);
        assert_eq!(r.real().map(|x| x.scan(false).1), Some(1), "B4 → B1");
    }

    #[test]
    fn vsr_shows_closing_targets_only() {
        let mut units = [at("hot", 0.0, 30.0, 0.0), at("cold", 5.0, 30.0, 0.0)];
        units[0].vel = Vec3::new(0.0, -250.0, 0.0);
        units[1].vel = Vec3::new(0.0, 300.0, 0.0);
        let mut r = up(&units);
        assert_eq!(keys(&r).len(), 2);
        r.cycle_submode(1.0, &scene(&units));
        assert_eq!(r.mode(), Mode::Tws);
        r.cycle_submode(2.0, &scene(&units));
        assert!(r.mode() == Mode::Lrs && r.real().unwrap().vsr);
        assert_eq!(keys(&r), ["hot"]);
        let c = r.contact("hot").unwrap();
        assert!((c.closure_kt - 500.0 * KT).abs() < 1.0);
        assert!((r.scope_xy(c).1 - 500.0 * KT / VSR_MAX_KT).abs() < 1e-6, "VSR: up the scope by closure");
        r.cycle_submode(3.0, &scene(&units));
        assert!(!r.real().unwrap().vsr, "back to RWS");
    }

    #[test]
    fn sam_tracks_four_while_searching_then_stt() {
        let units: Vec<Unit> = (0..5).map(|i| at(&format!("t{i}"), -20.0 + 10.0 * f64::from(i), 20.0, 0.0)).collect();
        let mut r = up(&units);
        assert!(r.selection().is_none(), "the real FCR's search bugs nothing by itself");
        for i in 0..5 {
            assert!(r.lock_key(&format!("t{i}")));
        }
        let sam = &r.real().unwrap().sam;
        assert_eq!(sam, &["t1", "t2", "t3", "t4"], "the (V)9's four, the oldest dropped");
        r.update(0.1, &scene(&units));
        assert_eq!(r.mode(), Mode::Lrs, "SAM keeps searching");
        assert_eq!(r.locked().map(|c| c.key.as_str()), Some("t4"), "the primary is the weapons' target");
        // A narrow scan away from them: the search loses them, SAM keeps them.
        r.step_scan(false);
        r.step_scan(false);
        r.set_cursor(0.0, 0.5);
        r.update(9.0, &scene(&units));
        for k in ["t1", "t2", "t3", "t4"] {
            assert!(r.contact(k).is_some(), "{k} tracked");
        }
        assert!(r.contact("t0").is_none());
        assert!(r.lock_key("t4"));
        r.update(9.1, &scene(&units));
        assert_eq!(r.mode(), Mode::Stt, "a press on the primary locks it");
        let mut barak = Radar::new(F16I, None, Some(Fcr { sam_tracks: 1 }), true);
        barak.update(0.0, &scene(&units));
        barak.lock_key("t0");
        barak.lock_key("t1");
        assert_eq!(barak.real().unwrap().sam, ["t1"], "the APG-68's one");
    }

    #[test]
    fn tms_bugs_locks_and_drops_at_the_cursor() {
        let units = [at("a", -10.0, 20.0, 0.0), at("b", 15.0, 30.0, 0.0)];
        let mut r = up(&units);
        let (x, y) = r.scope_xy(r.contact("b").unwrap());
        r.set_cursor(x + 0.01, y - 0.01);
        assert_eq!(r.under_cursor().map(|c| c.key.as_str()), Some("b"));
        r.tms(Tms::Up, 0.1, &scene(&units));
        assert_eq!(r.real().unwrap().sam, ["b"], "TMS up: bugged");
        r.tms(Tms::Up, 0.2, &scene(&units));
        r.update(0.3, &scene(&units));
        assert_eq!((r.mode(), r.locked().map(|c| c.key.as_str())), (Mode::Stt, Some("b")), "again: STT");
        r.tms(Tms::Down, 0.4, &scene(&units));
        r.update(0.5, &scene(&units));
        assert_eq!(r.mode(), Mode::Lrs, "TMS down: back to the search");
        r.lock_key("a");
        r.tms(Tms::Down, 0.6, &scene(&units));
        assert!(r.real().unwrap().sam.is_empty() && r.selection().is_none(), "TMS down drops SAM");
        // The cursor bumps the range scale.
        let idx = r.range_index();
        r.set_cursor(0.5, 0.99);
        r.update(0.7, &scene(&units));
        assert_eq!(r.range_index(), idx + 1);
        r.set_cursor(0.5, 0.01);
        r.update(0.8, &scene(&units));
        assert_eq!(r.range_index(), idx);
    }

    #[test]
    fn target_history_bug_centred_scan_exp_and_mtr() {
        let beam = Unit { vel: Vec3::new(200.0, 0.0, 0.0), ..at("beam", -5.0, 30.0, -2000.0) };
        let units = [at("a", 20.0, 30.0, 0.0), at("b", 22.0, 32.0, 0.0), at("n", 0.0, 30.0, 0.0), beam];
        let mut r = up(&units);
        for t in [8.1, 16.2, 24.3] {
            r.update(t, &scene(&units));
        }
        let sorted = |r: &Radar| {
            let mut k = keys(r);
            k.sort();
            k.join(" ")
        };
        assert_eq!(sorted(&r), "a b n", "MTR LO drops the beaming target in look-down");
        assert_eq!(r.history_xy().len(), 2, "TGT HIS 3: two earlier frames");
        r.cntl_press(18);
        r.update(32.4, &scene(&units));
        assert_eq!((r.real().unwrap().cntl[6], r.history_xy().len()), (3, 3), "TGT HIS 4");
        // SAM on a, then A1: the scan centred on the bug finds b beside it, not n on the nose.
        let a = r.contact("a").unwrap().clone();
        let (ax, ay) = r.scope_xy(&a);
        r.set_cursor(ax, ay);
        r.tms(Tms::Up, 32.5, &scene(&units));
        r.update(32.6, &scene(&units));
        r.step_scan(false);
        r.step_scan(false);
        let v = r.volume().unwrap();
        assert!((v.half, (v.az - 20.0).abs() < 0.5) == (10.0, true), "A1 about the bug: {v:?}");
        r.update(41.0, &scene(&units));
        assert_eq!(sorted(&r), "a b");
        // EXP: the bug mid-scope, b four times as far from it as on NORM; the cursor maps back.
        let b = r.contact("b").unwrap().clone();
        let (na, nb) = (r.scope_xy(r.contact("a").unwrap()), r.scope_xy(&b));
        r.toggle_exp();
        let (ea, eb) = (r.scope_xy(r.contact("a").unwrap()), r.scope_xy(&b));
        assert!((ea.0 - 0.5).abs() < 1e-9 && (ea.1 - 0.5).abs() < 1e-9);
        assert!((eb.0 - 0.5 - EXP_K * (nb.0 - na.0)).abs() < 1e-9 && (eb.1 - 0.5 - EXP_K * (nb.1 - na.1)).abs() < 1e-9);
        r.set_cursor(eb.0, eb.1);
        assert_eq!(r.under_cursor().map(|c| c.key.as_str()), Some("b"));
        let c = r.real().unwrap().cursor;
        assert!((c.0 - nb.0).abs() < 1e-9 && (c.1 - nb.1).abs() < 1e-9, "the cursor kept on NORM's scope");
        r.toggle_exp();
        assert_eq!(r.exp_centre(), None);
        r.cntl_press(20);
        assert_eq!(r.real().unwrap().cntl[4], 1, "MTR HI");
    }

    #[test]
    fn ground_clutter_notch_in_look_down_only() {
        // 30 km out, 2 km below (the ground behind it 75 km out: look-down) or 2 km above (look-up), crossing (the
        // beam) or coming (hot).
        let unit = |key: &str, up, vel| Unit { vel, ..at(key, 0.0, 30.0, up) };
        let (beam, hot) = (Vec3::new(200.0, 0.0, 0.0), Vec3::new(0.0, -200.0, 0.0));
        let units = [
            unit("low_beam", -2000.0, beam),
            unit("low_hot", -2000.0, hot),
            unit("high_beam", 2000.0, beam),
            unit("high_hot", 2000.0, hot),
        ];
        let sorted = |r: &Radar| {
            let mut k = keys(r);
            k.sort();
            k.join(" ")
        };
        let mut r = up(&units);
        assert_eq!(sorted(&r), "high_beam high_hot low_hot", "look-down loses the beam only");
        // The 1998 game's radar (the Sufa's row without the real FCR) has no clutter.
        let mut old = Radar::new(F16I, None, None, false);
        old.toggle_aa_ag(0.0, &scene(&units));
        assert_eq!(sorted(&old), "high_beam high_hot low_beam low_hot");
        // STT on the low jet coming; it turns to the beam: the lock breaks.
        assert!(r.lock_key("low_hot") && r.lock_key("low_hot"));
        r.update(0.1, &scene(&units));
        assert_eq!(r.mode(), Mode::Stt);
        let turned = [unit("low_hot", -2000.0, beam)];
        r.update(0.2, &scene(&turned));
        assert!(r.locked().is_none(), "in the notch the lock breaks");
        assert!(r.take_events().contains(&Event::Lock { key: "low_hot".into(), on: false }));
    }

    #[test]
    fn slow_drone_inside_the_speed_gate_only() {
        // A drone (0.01 m², 50 m/s = 97 kt) 10 km out, 600 m below: head on, or 60° off the line of sight (25 m/s
        // along it); and 600 m above, 60° off.
        let shahed = Rcs { front_m2: 0.01, side_m2: 0.01, rear_m2: 0.01, bays_open_m2: 0.0, store_m2: 0.0 };
        let drone = |key: &str, up, off: f64| {
            let a = (180.0 + off).to_radians();
            Unit { vel: Vec3::new(50.0 * a.sin(), 50.0 * a.cos(), 0.0), rcs: Some(shahed), ..at(key, 0.0, 10.0, up) }
        };
        let units = [drone("hot", -600.0, 0.0), drone("off", -600.0, 60.0), drone("above", 600.0, 60.0)];
        let mut r = up(&units);
        assert_eq!(keys(&r).len(), 2);
        assert!(r.contact("hot").is_some() && r.contact("above").is_some(), "MTR LO (60 kt): head on, and look-up");
        r.cntl_press(20);
        r.update(8.1, &scene(&units));
        assert_eq!(keys(&r), ["above"], "MTR HI (100 kt): no drone in look-down");
    }

    #[test]
    fn a_jammer_shows_as_a_strobe_beyond_its_burn_through() {
        // The Sufa's FCR, a jet (no cross-section: the reference) 40 km ahead and 5° right: seen; jamming with 0.3 its
        // burn-through is under 40 km, so only its strobe; 10 km out it burns through.
        let base = sufa().ranges.get(Mode::Lrs).map_or(0.0, Range::detection_m);
        assert!(base * 0.3 < 40_000.0 && base > 40_000.0, "{base:.0} m");
        let jet = |km, jam| [Unit { jam, ..at("j", 5.0, km, 0.0) }];
        let r = up(&jet(40.0, 0.0));
        assert_eq!((keys(&r), r.strobes().len()), (vec!["j"], 0));
        let r = up(&jet(40.0, 0.3));
        assert!(keys(&r).is_empty(), "no contact beyond the burn-through");
        assert_eq!(r.strobes().len(), 1);
        assert!((r.strobes()[0].to_degrees() - 5.0).abs() < 0.5, "the strobe at its azimuth");
        let r = up(&jet(10.0, 0.3));
        assert_eq!((keys(&r), r.strobes().len()), (vec!["j"], 0), "burnt through");
        // A friendly's jammer (a defending wingman) works on the enemy, not on the own radar.
        let r = up(&[Unit { jam: 0.3, hostile: false, ..at("j", 5.0, 40.0, 0.0) }]);
        assert_eq!((keys(&r), r.strobes().len()), (vec!["j"], 0), "a friendly jammer");
    }

    #[test]
    fn acm_patterns_acquire_inside_their_volumes() {
        let above = [at("above", 0.0, 4.0, 4.0 * 1000.0 * 30f64.to_radians().tan())];
        let mut r = up(&above);
        r.cycle_mode(0.0, &scene(&above));
        r.cycle_mode(0.0, &scene(&above));
        assert_eq!((r.mode(), r.range_index()), (Mode::Acm, 2), "ACM at 10 NM");
        assert!(r.contacts().is_empty(), "30° up: outside the 30 × 20");
        r.tms(Tms::Right, 0.1, &scene(&above));
        assert_eq!(r.real().unwrap().acm, Acm::Sixty);
        r.update(0.2, &scene(&above));
        assert_eq!(r.mode(), Mode::Stt, "the 10 × 60 acquires it");
        r.tms(Tms::Down, 0.25, &scene(&above));
        r.update(0.3, &scene(&above));
        assert_eq!((r.mode(), r.real().unwrap().acm), (Mode::Acm, Acm::Twenty), "TMS down: the 30 × 20, no re-lock");
        let side = [at("side", 25.0, 4.0, 0.0)];
        r.update(0.4, &scene(&side));
        assert_eq!((r.mode(), r.real().unwrap().acm), (Mode::Acm, Acm::Twenty));
        assert!(r.contacts().is_empty(), "25° right: outside the 30 × 20");
        r.set_cursor(0.5 + 25.0 / 120.0, 0.5);
        r.tms(Tms::Left, 0.6, &scene(&side));
        r.update(0.7, &scene(&side));
        assert_eq!(r.mode(), Mode::Stt, "SLEW onto it acquires");
        let nose = [at("nose", 1.0, 3.0, 0.0), at("off", 6.0, 2.0, 0.0)];
        r.tms(Tms::Down, 0.8, &scene(&nose));
        r.tms(Tms::Down, 0.9, &scene(&nose));
        r.tms(Tms::Up, 1.0, &scene(&nose));
        assert_eq!(r.mode(), Mode::Bore);
        assert_eq!(keys(&r), ["nose"], "BORE: the beam along the nose only");
    }

    #[test]
    fn tws_keeps_its_files_13_s() {
        let mut units = vec![at("t", 0.0, 20.0, 0.0)];
        let mut r = up(&units);
        r.cycle_mode(0.0, &scene(&units));
        assert_eq!((r.mode(), keys(&r)), (Mode::Tws, vec!["t"]));
        assert!(r.selection().is_none(), "TWS waits for the pilot's bug");
        let p0 = r.contact("t").unwrap().pos;
        units[0] = at("t", 50.0, 20.0, 0.0);
        r.scan(5.0, &scene(&units));
        let c = r.contact("t").expect("the file stays without a return");
        assert!((c.pos.y - (p0.y + 200.0 * 5.0)).abs() < 1e-6, "extrapolated along its velocity");
        r.scan(14.0, &scene(&units));
        assert!(r.contact("t").is_none(), "dropped 13 s after its last return");
        let many: Vec<Unit> = (0..12).map(|i| at(&format!("m{i}"), 0.0, 10.0 + f64::from(i), 0.0)).collect();
        r.scan(15.0, &scene(&many));
        assert_eq!(r.contacts().len(), 10, "ten track files");
    }

    #[test]
    fn exp_spreads_the_scope_four_times() {
        let units = [at("a", 2.0, 20.0, 0.0), at("b", 6.0, 22.0, 0.0)];
        let mut r = up(&units);
        r.scan(1.0, &scene(&units));
        let gap = |r: &Radar| {
            let (a, b) = (r.scope_xy(r.contact("a").unwrap()), r.scope_xy(r.contact("b").unwrap()));
            (a.0 - b.0).hypot(a.1 - b.1)
        };
        let norm = gap(&r);
        r.set_cursor(0.53, 0.14);
        r.toggle_exp();
        assert!((gap(&r) / norm - EXP_K).abs() < 1e-9, "EXP draws the returns 4 times farther apart");
    }

    // --- ours: the real FCR's air-to-ground modes (docs/radar.md §9.7) ---

    /// 100 m plains with a north–south ridge 300 m high at x 3–4 km (its west face toward the jet at x 0).
    fn hills(p: Vec3) -> Option<f64> {
        let ridge = 300.0 * (1.0 - ((p.x - 3500.0) / 500.0).abs()).max(0.0);
        Some(100.0 + ridge)
    }

    /// A ground unit (class 6, a vehicle) `deg` right of the nose `km` out; moving north at `v` m/s.
    fn hulk(key: &str, deg: f64, km: f64, v: f64) -> Unit {
        let a = deg.to_radians();
        let pos = Vec3::new(km * 1000.0 * a.sin(), km * 1000.0 * a.cos(), 100.0);
        Unit {
            key: key.into(),
            pos,
            vel: Vec3::new(0.0, v, 0.0),
            class: 6,
            state: 1,
            coll_radius: 5.0,
            ..Default::default()
        }
    }

    fn land(units: &[Unit]) -> Input<'_> {
        Input { own: Own { steer: Some(Vec3::new(0.0, 15000.0, 0.0)), ..OWN }, units, terrain: &hills, bare: None }
    }

    /// Airborne in CRM, then R: GM.
    fn gm(units: &[Unit]) -> Radar {
        let mut r = sufa();
        r.update(0.0, &land(units));
        r.toggle_aa_ag(0.0, &land(units));
        r.update(0.01, &land(units));
        assert_eq!((r.mode(), r.ag_mode()), (Mode::Map, Some("GM")), "R: the real FCR's GM first");
        r
    }

    #[test]
    fn ground_map_shows_the_returns_where_they_are_and_expands() {
        let units = [hulk("h1", 20.0, 20.0, 0.0), hulk("h2", 20.3, 20.0, 0.0)];
        let mut r = gm(&units);
        assert_eq!(r.range_m(), RANGE_M[3], "GM at 40 NM");
        assert!(r.selection().is_none(), "GM bugs nothing by itself");
        assert_eq!(keys(&r).len(), 2);
        let f = r.ground_frame().unwrap();
        assert_eq!((f.sym, f.k), (FAN_APEX, RANGE_M[3] / FAN_PX));
        let (x, y) = f.to_px(units[0].pos);
        let (a, d) = (20f64.to_radians(), 20000.0 / f.k);
        assert!((x - (66.0 + d * a.sin())).abs() < 1e-6 && (y - (109.0 - d * a.cos())).abs() < 1e-6, "PPI place");
        let back = f.from_px((x, y));
        assert!(back.distance(Vec3::new(units[0].pos.x, units[0].pos.y, 0.0)) < 1e-6);
        assert_eq!(r.real().unwrap().ground.map(|g| g.y), Some(15000.0), "the cursor starts on the steerpoint");
        // The cursor on the hulks (20° off the track: outside the DBS notch); OSB 3 steps EXP, DBS1, DBS2, NORM.
        r.set_ground_cursor(units[0].pos);
        let gap = |r: &Radar| {
            let f = r.ground_frame().unwrap();
            let (a, b) = (f.to_px(units[0].pos), f.to_px(units[1].pos));
            (a.0 - b.0).hypot(a.1 - b.1)
        };
        let norm = gap(&r);
        for (legend, zoom) in [("EXP", 4.0), ("DBS1", 8.0), ("DBS2", 64.0), ("NORM", 1.0)] {
            r.toggle_exp();
            r.update(r.now() + 0.01, &land(&units));
            assert_eq!(AG_FOV[r.real().unwrap().fov].0, legend);
            assert!((gap(&r) / norm - zoom).abs() < 1e-6, "{legend}: the scale × {zoom}");
            if zoom > 1.0 {
                let f = r.ground_frame().unwrap();
                assert_eq!(f.sym, PATCH_CENTRE);
                let c = r.ground_cursor_px().unwrap();
                assert!((c.0 - 66.0).abs() < 1e-6 && (c.1 - 66.0).abs() < 1e-6, "the patch about the cursor");
            }
        }
        // On the nose (inside the notch) DBS is skipped; a range step returns to NORM.
        r.set_ground_cursor(Vec3::new(0.0, 20000.0, 100.0));
        r.toggle_exp();
        r.toggle_exp();
        assert_eq!(r.real().unwrap().fov, 0, "EXP → NORM on the ground track");
        r.toggle_exp();
        r.step_range(-1, r.now(), &land(&units));
        assert_eq!((r.real().unwrap().fov, r.range_m()), (0, RANGE_M[2]), "a range step: NORM at 20 NM");
        // The cursor slewed past 95 % of the scale bumps it up.
        r.set_ground_cursor(Vec3::new(0.0, 0.97 * RANGE_M[2], 100.0));
        r.set_slews(None, Some((0.0, 1.0)));
        r.update(r.now() + 0.01, &land(&units));
        r.set_slews(None, Some((0.0, 0.0)));
        assert_eq!(r.range_m(), RANGE_M[3], "the cursor bumps the scale up");
        r.update(r.now() + 0.01, &land(&units));
        assert_eq!(r.range_m(), RANGE_M[3], "held still, no bump");
        assert!(Radar::new(F16I, None, Some(Fcr { sam_tracks: 4 }), true).ranges().get(Mode::Map).unwrap().max == 5);
    }

    #[test]
    fn freeze_holds_the_picture_and_snowplow_and_cz_move_the_cursor() {
        let mut units = vec![hulk("h", 20.0, 20.0, 0.0)];
        let mut r = gm(&units);
        r.update(2.5, &land(&units));
        let serial = r.real().unwrap().picture.serial;
        assert!(serial > 0, "a picture each frame");
        r.ag_press(7, 2.6, &land(&units));
        let f = r.ground_frame().unwrap();
        units[0] = hulk("h", 30.0, 20.0, 0.0);
        let moved = Input { own: Own { pos: Vec3::new(0.0, 3000.0, 5000.0), ..land(&units).own }, ..land(&units) };
        for t in [3.0, 6.0, 9.0] {
            r.update(t, &moved);
        }
        assert_eq!(r.ground_frame(), Some(f), "FZ: the frame stays");
        assert_eq!(r.real().unwrap().picture.serial, serial, "FZ: no new picture");
        assert_eq!(r.contact("h").unwrap().pos, hulk("h", 20.0, 20.0, 0.0).pos, "FZ: the returns stay");
        let own_px = f.to_px(moved.own.pos);
        assert!((own_px.1 - (FAN_APEX.1 - 3000.0 / f.k)).abs() < 1e-6, "the jet moves over the frozen map");
        r.ag_press(7, 9.1, &moved);
        assert!(r.real().unwrap().picture.serial > serial, "FZ off: a new frame");
        assert_eq!(r.contact("h").unwrap().pos, units[0].pos);
        // SP: the cursor half the range ahead, with the jet; CZ back on the steerpoint.
        r.ag_press(8, 9.2, &moved);
        r.update(9.3, &moved);
        let g = r.real().unwrap().ground.unwrap();
        assert!((g.y - (3000.0 + RANGE_M[3] / 2.0)).abs() < 1.0 && g.x.abs() < 1.0, "SP: {g:?}");
        r.ag_press(9, 9.4, &moved);
        assert_eq!(r.real().unwrap().ground.map(|g| (g.x, g.y)), Some((0.0, 15000.0)), "CZ: the steerpoint");
        assert!(!r.real().unwrap().snowplow);
    }

    #[test]
    fn gmt_shows_movers_and_sea_ships_only() {
        let mut ship = hulk("ship", -20.0, 20.0, 0.0);
        ship.class = 0xf;
        let units = [hulk("still", 20.0, 20.0, 0.0), hulk("mover", 10.0, 15.0, 8.0), ship];
        let mut r = gm(&units);
        assert_eq!(keys(&r).len(), 3, "GM: every ground return");
        r.cycle_mode(0.1, &land(&units));
        assert_eq!((r.mode(), r.ag_mode(), keys(&r)), (Mode::Gmt, Some("GMT"), vec!["mover"]), "GMT: the mover");
        assert!(r.range_m() <= RANGE_M[3], "GMT to 40 NM");
        r.cycle_mode(0.2, &land(&units));
        assert_eq!((r.mode(), r.ag_mode(), keys(&r)), (Mode::Map, Some("SEA"), vec!["ship"]), "SEA: the ship");
        r.toggle_exp();
        r.toggle_exp();
        assert_eq!(r.real().unwrap().fov, 0, "SEA: no DBS");
        r.cycle_mode(0.3, &land(&units));
        assert_eq!(r.ag_mode(), Some("GM"));
        // The original's radar keeps its GMT / MAP with the nearest selected.
        let mut o = Radar::new(1, None, None, false);
        o.toggle_aa_ag(0.0, &land(&units));
        o.toggle_aa_ag(0.0, &land(&units));
        assert_eq!((o.mode(), o.ag_mode()), (Mode::Gmt, None));
        assert_eq!(o.selection().map(|s| s.key.as_str()), Some("mover"));
    }

    #[test]
    fn tms_tracks_or_designates_and_the_weapons_get_the_point() {
        let units = [hulk("h", 20.0, 20.0, 0.0)];
        let mut r = gm(&units);
        let spot = Vec3::new(-4000.0, 18000.0, 0.0);
        r.set_ground_cursor(spot);
        r.update(0.1, &land(&units));
        r.tms(Tms::Up, 0.2, &land(&units));
        let p = r.target_point().expect("TMS up off the returns: the point designated");
        assert!((p.x, p.y, p.z) == (-4000.0, 18000.0, 100.0), "{p:?}");
        assert!(r.real().unwrap().tgt, "TGT");
        r.set_ground_cursor(units[0].pos);
        r.tms(Tms::Up, 0.3, &land(&units));
        assert!(r.has_lock() && r.designated().is_none(), "on the hulk: FTT");
        assert_eq!(r.target_point(), Some(units[0].pos), "the weapons get the tracked hulk");
        r.update(0.4, &land(&units));
        assert_eq!(r.mode(), Mode::Map, "a ground track stays in GM");
        assert_eq!(r.real().unwrap().ground, Some(units[0].pos), "the cursor rides the track");
        r.tms(Tms::Down, 0.5, &land(&units));
        assert!(!r.has_lock() && r.target_point().is_none(), "TMS down drops it");
        assert_eq!(r.real().unwrap().ground.map(|g| g.y), Some(15000.0), "back on the steerpoint");
    }

    #[test]
    fn the_picture_shades_slopes_and_shows_runways_dark() {
        let units = [hulk("h", 0.0, 6.0, 0.0)];
        let mut r = gm(&units);
        r.set_runways(vec![Runway { a: (-2000.0, 8000.0), b: (-2000.0, 11000.0), half_width: 30.0 }]);
        // 10 NM (197 m a px), the jet 600 m up: the ridge shadows the ground behind it.
        let low = Input { own: Own { pos: Vec3::new(0.0, 0.0, 600.0), ..land(&units).own }, ..land(&units) };
        r.step_range(-2, 1.0, &low);
        let pic = r.real().unwrap().picture.clone();
        let f = pic.frame.unwrap();
        let at = |w: Vec3| {
            let (x, y) = f.to_px(w);
            let (i, j) = ((x - PIC_WINDOW.0) as usize, (y - PIC_WINDOW.1) as usize);
            (pic.la8[2 * (j * PIC_WINDOW.2 + i)], pic.la8[2 * (j * PIC_WINDOW.2 + i) + 1])
        };
        let face = at(Vec3::new(3250.0, 10000.0, 0.0));
        let plain = at(Vec3::new(-8000.0, 16000.0, 0.0));
        let behind = at(Vec3::new(4600.0, 10000.0, 0.0));
        assert_eq!(at(units[0].pos), (255, 255), "the hulk a bright return");
        assert!(face.0 > plain.0, "the ridge's face toward the radar brighter ({face:?} vs {plain:?})");
        assert_eq!(behind, (0, 255), "the ridge's shadow dark");
        assert!(plain.0 > 10, "the plains return");
        assert_eq!(at(Vec3::new(-9000.0, 3000.0, 0.0)), (0, 255), "outside the fan: black");
        // DBS1 on the runway (25 m a px): the 60 m strip dark, the ground beside it lit.
        r.set_ground_cursor(Vec3::new(-2000.0, 9500.0, 0.0));
        r.toggle_exp();
        r.toggle_exp();
        r.update(r.now() + 0.01, &low);
        assert_eq!(AG_FOV[r.real().unwrap().fov].0, "DBS1");
        let pic = r.real().unwrap().picture.clone();
        let f = pic.frame.unwrap();
        let at = |w: Vec3| {
            let (x, y) = f.to_px(w);
            pic.la8[2 * ((y - PIC_WINDOW.1) as usize * PIC_WINDOW.2 + (x - PIC_WINDOW.0) as usize)]
        };
        assert_eq!(at(Vec3::new(-2000.0, 9500.0, 0.0)), 0, "the runway dark");
        assert!(at(Vec3::new(-2150.0, 9500.0, 0.0)) > 10, "the ground beside it lit");
    }

    #[test]
    fn agr_ranges_along_the_aim_line() {
        let units = [];
        let mut r = gm(&units);
        r.set_agr(Some(Vec3::new(0.0, 6000.0, 100.0)));
        r.update(0.2, &land(&units));
        assert_eq!(r.ag_mode(), Some("AGR"));
        let want = Vec3::new(0.0, 6000.0, 100.0).distance(OWN.pos);
        let got = r.real().unwrap().agr.unwrap();
        assert!((got - want).abs() < 2.0, "slant range {got} vs {want}");
        r.set_agr(None);
        r.update(0.3, &land(&units));
        assert_eq!((r.ag_mode(), r.real().unwrap().agr), (Some("GM"), None));
    }
}
