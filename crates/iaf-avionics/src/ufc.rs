//! The F-16's up-front controls: the ICP (integrated control panel) keys and the DED (data entry display) pages, five
//! lines of 24 characters (T.O. GR1F-16CJ-34-1-1 "Up-front controls"; DCS F-16C guide "UFC"; modern-iaf/docs/
//! modern-iaf/docs/ufc.md). Modern IAF's F-16s only: reborn keeps its CNI page (`cockpit3d_display.gd` `_ded`).
//!
//! The pilot calls a page by its ICP key (1 T-ILS, 2 ALOW, 4 STPT, 5 CRUS, 6 TIME, 7 MARK, 8 FIX, 9 A-CAL, LIST, COM1,
//! COM2), steps its fields with the DCS rocker (up / down), types digits into the selected field (shown between
//! asterisks) and ENTR enters them; RCL clears the last digit, then all; RTN goes back to CNI; SEQ steps a page's own
//! sub-pages or modes; INC / DEC step the steerpoint, the TACAN channel or the radio preset. On a page with a choice
//! (`X(0)`, `*BULLSEYE*`) a lone 0 (M-SEL) then ENTR toggles it.
//!
//! The pages read the jet through `Nav`; what they change outside this state comes back as an `Effect` the host
//! applies (the steerpoint, an edited steerpoint, a markpoint, the bingo).

use crate::cmds::{Dispense, Program};
use crate::frame::{utm36n, utm36n_geo};

/// The DED's width (characters).
pub const W: usize = 24;
/// The up-down arrow the DED shows beside a number INC / DEC steps.
const ARROW: char = '\u{2195}';
const NM: f64 = 1852.0;
const FT: f64 = 0.3048;
/// The markpoints' numbers: 26 to 30 (dash-34 "MARK"); the sixth mark replaces the first.
pub const MARK_FIRST: u8 = 26;
pub const MARKS: u8 = 5;

/// A TACAN station: our own channels for the sim's bases (ours: the real channels are not public, inferred), at the
/// airbases' reference points (`modern-iaf/data/airbases/*.json` `reference`) and elevations.
pub struct Station {
    pub name: &'static str,
    pub channel: u8,
    pub y_band: bool,
    pub lat: f64,
    pub lon: f64,
    pub elev_ft: f64,
}

pub const STATIONS: [Station; 5] = [
    Station { name: "RAMON", channel: 75, y_band: false, lat: 30.7761, lon: 34.666698, elev_ft: 2126.0 },
    Station { name: "NEVATIM", channel: 83, y_band: false, lat: 31.2082996, lon: 35.0122986, elev_ft: 1329.0 },
    Station { name: "HATZERIM", channel: 62, y_band: false, lat: 31.2334, lon: 34.662601, elev_ft: 725.0 },
    Station { name: "RAMAT DAVID", channel: 99, y_band: false, lat: 32.6651, lon: 35.179501, elev_ft: 184.0 },
    Station { name: "TEL NOF", channel: 31, y_band: false, lat: 31.8395, lon: 34.8218, elev_ft: 194.0 },
];

/// The radios' presets, kHz (ours: the IAF's frequencies are not public; values in the UHF military band 225–400 MHz
/// and the VHF air band 118–137 MHz, inferred).
pub const UHF_PRESETS: [u32; 20] = [
    305_000, 292_300, 251_000, 270_500, 340_200, 236_000, 264_800, 317_600, 282_100, 344_000, 225_500, 248_600,
    262_000, 289_400, 300_200, 311_000, 327_800, 355_500, 372_600, 399_900,
];
pub const VHF_PRESETS: [u32; 20] = [
    122_100, 118_700, 120_400, 121_500, 123_450, 124_800, 126_200, 127_350, 128_900, 129_500, 130_100, 131_250,
    132_400, 133_550, 134_700, 135_850, 136_100, 119_200, 125_600, 136_900,
];

/// An ICP key (the 3D cockpit's ICP buttons and Modern IAF's keys send its number, command 250).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Btn {
    Digit(u8),
    Entr,
    Rcl,
    List,
    Com1,
    Com2,
    Iff,
    Up,
    Down,
    Rtn,
    Seq,
    Inc,
    Dec,
}

impl Btn {
    /// 0–9 the digits, 10 ENTR, 11 RCL, 12 LIST, 13 COM1, 14 COM2, 15 IFF, 16 DCS up, 17 DCS down, 18 RTN, 19 SEQ,
    /// 20 INC, 21 DEC.
    pub fn from_id(i: i64) -> Option<Btn> {
        Some(match i {
            0..=9 => Btn::Digit(i as u8),
            10 => Btn::Entr,
            11 => Btn::Rcl,
            12 => Btn::List,
            13 => Btn::Com1,
            14 => Btn::Com2,
            15 => Btn::Iff,
            16 => Btn::Up,
            17 => Btn::Down,
            18 => Btn::Rtn,
            19 => Btn::Seq,
            20 => Btn::Inc,
            21 => Btn::Dec,
            _ => return None,
        })
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Page {
    #[default]
    Cni,
    Tils,
    Alow,
    Stpt,
    Crus,
    Time,
    Mark,
    Fix,
    Acal,
    List,
    Dest,
    Bngo,
    Nav,
    Ins,
    Mode,
    Misc,
    Magv,
    Lasr,
    Bull,
    Hmcs,
    Com1,
    Com2,
    /// Modern IAF's EW and identification pages (modern-iaf/docs/ews.md §8): LIST 7, the IFF key, LIST ENTR / RCL.
    Ews,
    Iff,
    Dlnk,
    Intg,
}

impl Page {
    pub fn name(self) -> &'static str {
        match self {
            Page::Cni => "CNI",
            Page::Tils => "T-ILS",
            Page::Alow => "ALOW",
            Page::Stpt => "STPT",
            Page::Crus => "CRUS",
            Page::Time => "TIME",
            Page::Mark => "MARK",
            Page::Fix => "FIX",
            Page::Acal => "A-CAL",
            Page::List => "LIST",
            Page::Dest => "DEST",
            Page::Bngo => "BNGO",
            Page::Nav => "NAV",
            Page::Ins => "INS",
            Page::Mode => "MODE",
            Page::Misc => "MISC",
            Page::Magv => "MAGV",
            Page::Lasr => "LASR",
            Page::Bull => "BULL",
            Page::Hmcs => "HMCS",
            Page::Com1 => "COM1",
            Page::Com2 => "COM2",
            Page::Ews => "EWS",
            Page::Iff => "IFF",
            Page::Dlnk => "DLNK",
            Page::Intg => "INTG",
        }
    }
}

/// A field digits go into.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Fld {
    StptNo,
    Lat,
    Lng,
    Elev,
    Tos,
    Chan,
    Frq,
    Crs,
    Alow,
    Floor,
    Bingo,
    Hack,
    DeltaTos,
    Home,
    Radio,
    Code,
    BullNo,
    Toggle,
    /// The EWS page's options (REQCTR, BINGO, FDBK, REQJAM), its BINGO quantities and a program's BQ / BI / SQ / SI.
    Opt(u8),
    ChaffBingo,
    FlareBingo,
    /// The transponder's modes 1, 2, 3/A and C (`Xpdr`).
    Mode(u8),
    Bq,
    Bi,
    Sq,
    Si,
}

/// A steerpoint as the host's route holds it: its number (1.. the route, 26–30 the markpoints), UTM 36N metres, the
/// elevation and the time over it (s of the day), if any.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Stpt {
    pub number: u8,
    pub e: f64,
    pub n: f64,
    pub elev_ft: f64,
    pub tos_s: Option<f64>,
}

/// The INS as the flight model has it (`start.rs` `Start::ins_status`): the knob, the alignment's time and length.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Ins {
    pub knob: u8,
    pub elapsed_s: f64,
    pub need_s: f64,
    pub aligned: bool,
}

impl Ins {
    /// The navigation solution: aligned and the knob at NAV or IN FLT ALIGN.
    pub fn nav(&self) -> bool {
        self.aligned && matches!(self.knob, 3 | 4)
    }

    /// The DED's alignment status: 99 falling to 10 over the alignment (ours, linear; inferred), 10 once done.
    pub fn status(&self) -> u8 {
        if self.aligned || self.need_s <= 0.0 {
            return 10;
        }
        (99.0 - 89.0 * (self.elapsed_s / self.need_s).clamp(0.0, 1.0)).round() as u8
    }
}

/// The EW and identification state the pages show (`ews.gd`; modern-iaf/docs/ews.md).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct EwsView {
    pub programs: [Program; 4],
    /// The BINGO quantities: chaff, flares.
    pub bingo: [u32; 2],
    /// REQCTR, BINGO, FDBK, REQJAM.
    pub opts: [bool; 4],
    pub chaff: u32,
    pub flares: u32,
    /// The CMDS MODE knob's name.
    pub mode: String,
    /// The AIFF fitted; its last interrogation (Some(true) LOS, Some(false) SCAN) and replies on show.
    pub aiff: bool,
    pub intg: Option<bool>,
    pub friends: u32,
    pub unknowns: u32,
    /// The DL switch, the flight's jets and all the tracks on the link.
    pub dl: bool,
    pub team: u32,
    pub tracks: u32,
}

/// The IFF transponder as the DED sets it (modern-iaf/docs/ews.md §8): modes 1, 2, 3/A and C on or off, the codes of
/// modes 1, 2 and 3/A (octal digits as typed: mode 1 two, the others four), and the IDENT's reply, on until
/// `ident_until` (time of day, s). A cockpit procedure only: nothing in the sim interrogates the jet.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Xpdr {
    pub on: [bool; 4],
    pub codes: [u16; 3],
    pub ident_until: f64,
}

/// The IDENT's reply lasts this long (s; inferred, within the 15–30 s transponders give it).
pub const IDENT_S: f64 = 18.0;

impl Default for Xpdr {
    /// Modes 1, 3/A and C on; mode 3/A's code 2000 (ICAO's code for none assigned), the others zero (inferred).
    fn default() -> Self {
        Xpdr { on: [true, false, true, true], codes: [0, 0, 2000], ident_until: f64::NEG_INFINITY }
    }
}

impl Xpdr {
    pub fn ident(&self, tod: f64) -> bool {
        tod < self.ident_until
    }

    /// The CNI page's IFF field: "M" and the modes on (`M1 3 C`), with an `I` while IDENT replies (inferred).
    fn cni(&self, tod: f64) -> String {
        let modes: Vec<&str> = ["1", "2", "3", "C"].into_iter().zip(self.on).filter(|m| m.1).map(|m| m.0).collect();
        let mut s = if modes.is_empty() { String::new() } else { format!("M{}", modes.join(" ")) };
        if self.ident(tod) {
            s.push_str(" I");
        }
        s
    }
}

/// Octal digits `s`, exactly `n` of them.
fn octal(s: &str, n: usize) -> Option<u16> {
    (s.len() == n && s.bytes().all(|c| (b'0'..=b'7').contains(&c))).then(|| s.parse().ok())?
}

/// What an EWS page entry changes in the CMDS (`cmds.rs`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum CmdsEdit {
    /// Program `index` (0–3), its flares' part (else its chaff's).
    Program {
        index: usize,
        flare: bool,
        d: Dispense,
    },
    Bingo([u32; 2]),
    Opts([bool; 4]),
}

/// The jet and the route this frame.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Nav {
    pub e: f64,
    pub n: f64,
    pub alt_ft: f64,
    pub heading_deg: f64,
    pub ground_kt: f64,
    pub fuel_lbs: f64,
    /// Fuel flow, lb per hour.
    pub fuel_pph: f64,
    pub tod_s: f64,
    pub wind_from_deg: f64,
    pub wind_kt: f64,
    pub bingo_lbs: f64,
    pub ins: Ins,
    pub route: Vec<Stpt>,
    /// The selected steerpoint (an index into `route`).
    pub stpt: usize,
    /// The A-A (true) or A-G master mode, None in NAV.
    pub master_aa: Option<bool>,
    /// The markpoints' sensors' points (UTM metres and elevation ft): the FCR's ground cursor / designation, the
    /// targeting pod's, the HUD's boresight on the ground.
    pub fcr_at: Option<[f64; 3]>,
    pub tgp_at: Option<[f64; 3]>,
    pub hud_at: Option<[f64; 3]>,
    /// The modern F-16s' EW and identification (None: no EWS page).
    pub ews: Option<EwsView>,
}

impl Nav {
    fn selected(&self) -> Option<&Stpt> {
        self.route.get(self.stpt)
    }

    /// Bearing (°, grid) and distance (m) to a point.
    fn to(&self, e: f64, n: f64) -> (f64, f64) {
        let (de, dn) = (e - self.e, n - self.n);
        (de.atan2(dn).to_degrees().rem_euclid(360.0), de.hypot(dn))
    }

    /// Seconds to fly `m` at the ground speed, None when (nearly) stopped.
    fn time_for(&self, m: f64) -> Option<f64> {
        (self.ground_kt > 10.0).then(|| m / (self.ground_kt * NM / 3600.0))
    }
}

/// What a key did outside the DED.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Effect {
    None,
    /// Steer to route index.
    Steer(usize),
    /// Route index's new position / elevation / time over it.
    Edit(usize, Stpt),
    /// A new markpoint (its number 26–30).
    Mark(Stpt),
    Bingo(f64),
    /// The MODE page's master mode: A-A (true) or A-G.
    Master(bool),
    /// An EWS page entry.
    Cmds(CmdsEdit),
}

/// A radio: its preset, or a frequency typed in (kHz).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Radio {
    pub preset: u8,
    pub manual: Option<u32>,
}

impl Radio {
    pub fn khz(&self, table: &[u32; 20]) -> u32 {
        self.manual.unwrap_or(table[usize::from(self.preset.clamp(1, 20) - 1)])
    }
}

/// The UFC's state.
#[derive(Clone, Debug, PartialEq)]
pub struct Ufc {
    pub page: Page,
    /// The page's sub-page or mode (SEQ): CRUS TOS / RNG / HOME / EDR; MARK and FIX OFLY / FCR / TGP / HUD; T-ILS's
    /// TACAN mode REC / T/R / A/A TR.
    pub sub: u8,
    field: usize,
    scratch: String,
    /// CARA ALOW and the MSL floor (ft): the HUD's AL and the GAAF's low-altitude warning read the first.
    pub alow_ft: f64,
    pub floor_ft: f64,
    pub tcn_chan: u8,
    pub tcn_y: bool,
    pub tcn_mode: u8,
    /// The ILS frequency (kHz) and course (°); command steering on.
    pub ils_khz: u32,
    pub ils_crs: u16,
    pub cmd_strg: bool,
    pub uhf: Radio,
    pub vhf: Radio,
    /// The UHF on the backup control panel (its own channel) in place of the UFC's.
    pub uhf_backup: Option<u8>,
    /// AUTO steerpoint sequencing (the STPT page's AUTO / MAN).
    pub auto_seq: bool,
    next_mark: u8,
    /// The hack clock: running since (time of day), or stopped at (s).
    hack_from: Option<f64>,
    hack_s: f64,
    pub delta_tos_s: f64,
    /// CRUS HOME's steerpoint number.
    pub home: u8,
    pub laser_code: u16,
    /// The bullseye shown, at steerpoint `bull_no` (0: the home base, the HSD's default).
    pub bull: bool,
    pub bull_no: u8,
    /// The EWS PRGM pages' program (0–3; INC / DEC).
    pub ews_prog: usize,
    pub xpdr: Xpdr,
}

impl Default for Ufc {
    fn default() -> Self {
        Ufc {
            page: Page::Cni,
            sub: 1,
            field: 0,
            scratch: String::new(),
            alow_ft: crate::gaaf::ALOW_FT,
            floor_ft: 10_000.0,
            tcn_chan: STATIONS[0].channel,
            tcn_y: false,
            tcn_mode: 1,
            ils_khz: 108_100,
            ils_crs: 0,
            cmd_strg: true,
            uhf: Radio { preset: 1, manual: None },
            vhf: Radio { preset: 1, manual: None },
            uhf_backup: None,
            auto_seq: true,
            next_mark: 0,
            hack_from: None,
            hack_s: 0.0,
            delta_tos_s: 0.0,
            home: 1,
            laser_code: 1688,
            bull: true,
            bull_no: 0,
            ews_prog: 0,
            xpdr: Xpdr::default(),
        }
    }
}

/// Pads or cuts `s` to the DED's width.
fn fit(s: String) -> String {
    let mut s: String = s.chars().take(W).collect();
    let n = s.chars().count();
    s.extend(std::iter::repeat_n(' ', W - n));
    s
}

/// hh:mm:ss of seconds of the day.
fn hms(s: f64) -> String {
    let t = s.rem_euclid(86_400.0).floor() as i64;
    format!("{:02}:{:02}:{:02}", t / 3600, t / 60 % 60, t % 60)
}

/// `N 31°15.123'` / `E 034°45.678'`.
fn deg_min(v: f64, pos: char, neg: char, width: usize) -> String {
    let h = if v < 0.0 { neg } else { pos };
    let a = v.abs();
    let mut d = a.floor();
    let mut m = ((a - d) * 60.0 * 1000.0).round() / 1000.0;
    if m >= 60.0 {
        d += 1.0;
        m -= 60.0;
    }
    format!("{h} {:0width$}\u{b0}{m:06.3}'", d as i64)
}

/// Digits `s` as hh:mm:ss (right-aligned: "1230" = 00:12:30), None when not a time.
fn parse_hms(s: &str) -> Option<f64> {
    if s.is_empty() || s.len() > 6 {
        return None;
    }
    let v: u32 = s.parse().ok()?;
    let (h, m, sec) = (v / 10_000, v / 100 % 100, v % 100);
    (h < 24 && m < 60 && sec < 60).then_some(f64::from(h * 3600 + m * 60 + sec))
}

/// Digits as degrees and thousandths of minutes (`3115123` = 31°15.123'), `deg` digits of degrees.
fn parse_deg_min(s: &str, deg: usize, max: f64) -> Option<f64> {
    let s = if s.len() == deg + 4 { format!("0{s}") } else { s.to_string() };
    if s.len() != deg + 5 {
        return None;
    }
    let d: f64 = s[..deg].parse().ok()?;
    let m: f64 = s[deg..].parse::<f64>().ok()? / 1000.0;
    (d <= max && m < 60.0).then_some(d + m / 60.0)
}

/// A laser code: four digits, the first 1, the others 1–8 (dash-34 "Laser codes").
fn laser_code(s: &str) -> Option<u16> {
    let b = s.as_bytes();
    (b.len() == 4 && b[0] == b'1' && b[1..].iter().all(|c| (b'1'..=b'8').contains(c))).then(|| s.parse().ok())?
}

impl Ufc {
    /// The DED's five lines.
    pub fn lines(&self, nav: &Nav) -> [String; 5] {
        let l = self.page_lines(nav);
        l.map(fit)
    }

    /// A field's value with its asterisks when selected (the scratchpad in place of the value while typing).
    fn show(&self, i: usize, v: String) -> String {
        if i != self.field || self.fields().is_empty() {
            return format!(" {v} ");
        }
        let s = if self.scratch.is_empty() { v } else { format!("{:>w$}", self.scratch, w = v.chars().count()) };
        format!("*{s}*")
    }

    fn fields(&self) -> &'static [Fld] {
        match self.page {
            Page::Stpt | Page::Dest => &[Fld::StptNo, Fld::Lat, Fld::Lng, Fld::Elev, Fld::Tos],
            Page::Tils => &[Fld::Chan, Fld::Frq, Fld::Crs],
            Page::Alow => &[Fld::Alow, Fld::Floor],
            Page::Bngo => &[Fld::Bingo],
            Page::Time => &[Fld::Hack, Fld::DeltaTos],
            Page::Crus if self.sub == 3 => &[Fld::Home],
            Page::Com1 | Page::Com2 => &[Fld::Radio],
            Page::Lasr => &[Fld::Code],
            Page::Bull => &[Fld::Toggle, Fld::BullNo],
            Page::Mode => &[Fld::Toggle],
            Page::Iff if self.sub == 1 => &[Fld::Mode(0), Fld::Mode(1), Fld::Mode(2), Fld::Mode(3)],
            Page::Ews => match self.sub {
                1 => &[Fld::Opt(0), Fld::Opt(1), Fld::Opt(2), Fld::Opt(3)],
                2 => &[Fld::ChaffBingo, Fld::FlareBingo],
                _ => &[Fld::Bq, Fld::Bi, Fld::Sq, Fld::Si],
            },
            _ => &[],
        }
    }

    fn page_lines(&self, nav: &Nav) -> [String; 5] {
        let s = |x: &str| x.to_string();
        let geo = |p: &Stpt| utm36n_geo(p.e, p.n);
        let nav_ok = nav.ins.nav();
        match self.page {
            Page::Cni => {
                let uhf = match self.uhf_backup {
                    Some(_) => "UHF  BACKUP".to_string(),
                    None => format!("UHF  {:6.2}", f64::from(self.uhf.khz(&UHF_PRESETS)) / 1000.0),
                };
                let no = nav.selected().map_or(0, |p| p.number);
                let hack = self.hack(nav.tod_s);
                [
                    format!("{uhf:<13}STPT {ARROW}{no:>3}"),
                    String::new(),
                    format!("VHF  {:<8}{:>11}", self.vhf.preset, hms(nav.tod_s)),
                    if hack > 0.0 { format!("{:>24}", format!("HACK {}", hms(hack))) } else { String::new() },
                    format!(
                        "{:<12}{:>12}",
                        if nav.ews.is_some() { self.xpdr.cni(nav.tod_s) } else { String::new() },
                        format!("T {}{}", self.tcn_chan, if self.tcn_y { 'Y' } else { 'X' })
                    ),
                ]
            }
            Page::Stpt | Page::Dest => {
                let p = nav.selected().copied().unwrap_or_default();
                let [lon, lat] = geo(&p);
                let head = if self.page == Page::Dest { "DEST  DIR" } else { "STPT" };
                let mode = if self.page == Page::Stpt { if self.auto_seq { "AUTO" } else { "MAN" } } else { "" };
                [
                    format!("  {head} {ARROW}{}  {mode}", self.show(0, format!("{:>2}", p.number))),
                    format!("   LAT {}", self.show(1, deg_min(lat, 'N', 'S', 2))),
                    format!("   LNG {}", self.show(2, deg_min(lon, 'E', 'W', 3))),
                    format!("  ELEV {}", self.show(3, format!("{:>6}FT", p.elev_ft.round() as i64))),
                    format!("   TOS {}", self.show(4, p.tos_s.map_or(s("--:--:--"), hms))),
                ]
            }
            Page::Tils => {
                let mode = ["REC", "T/R", "A/A TR"][usize::from(self.tcn_mode.min(2))];
                [
                    format!("TCN {mode:<7}  ILS  ON"),
                    if self.cmd_strg { format!("{:>24}", "CMD STRG ") } else { String::new() },
                    format!(
                        "CHAN {} FRQ {}",
                        self.show(0, format!("{:>3}", self.tcn_chan)),
                        self.show(1, format!("{:6.2}", f64::from(self.ils_khz) / 1000.0))
                    ),
                    format!(
                        "BAND {}(0)   CRS {}",
                        if self.tcn_y { 'Y' } else { 'X' },
                        self.show(2, format!("{:03}\u{b0}", self.ils_crs))
                    ),
                    match self.tacan(nav) {
                        Some((name, b, r)) if nav_ok => format!("{name:<11} {b:03.0}\u{b0}{:>5.1}NM", r / NM),
                        Some((name, ..)) => s(name),
                        None => String::new(),
                    },
                ]
            }
            Page::Alow => [
                s("         ALOW"),
                format!("  CARA ALOW {}", self.show(0, format!("{:>5}FT", self.alow_ft as i64))),
                format!("  MSL FLOOR {}", self.show(1, format!("{:>5}FT", self.floor_ft as i64))),
                // TF is parked (avionics-plan.md G12): its line as the page has it, not settable.
                s("TF ADV (MSL)    400FT"),
                String::new(),
            ],
            Page::Bngo => [
                format!("        BINGO  {ARROW}"),
                format!("   SET {}", self.show(0, format!("{:>5}LBS", nav.bingo_lbs.round() as i64))),
                format!("  TOTAL  {:>5}LBS", nav.fuel_lbs.round() as i64),
                String::new(),
                String::new(),
            ],
            Page::Time => [
                s("          TIME"),
                format!("  SYSTEM   {}", hms(nav.tod_s)),
                format!("    HACK {}", self.show(0, hms(self.hack(nav.tod_s)))),
                format!("DELTA TOS {}", self.show(1, hms(self.delta_tos_s))),
                String::new(),
            ],
            Page::Crus => self.crus(nav),
            Page::Mark => {
                let kind = ["OFLY", "FCR", "TGP", "HUD"][usize::from(self.sub.min(3))];
                let no = MARK_FIRST + self.next_mark;
                let at = self.mark_point(nav);
                let [lon, lat] = at.map_or([0.0, 0.0], |p| utm36n_geo(p[0], p[1]));
                [
                    format!("    MARK *{kind}*  {no}"),
                    at.map_or(String::new(), |_| format!("   LAT  {}", deg_min(lat, 'N', 'S', 2))),
                    at.map_or(s("   NO MARK POINT"), |_| format!("   LNG  {}", deg_min(lon, 'E', 'W', 3))),
                    at.map_or(String::new(), |p| format!("  ELEV  {:>6}FT", p[2].round() as i64)),
                    String::new(),
                ]
            }
            Page::Fix => {
                let kind = ["OFLY", "FCR", "TGP", "HUD"][usize::from(self.sub.min(3))];
                let no = nav.selected().map_or(0, |p| p.number);
                // The sim's INS keeps its position exactly (no drift): every fix finds no error (inferred).
                [
                    format!("    FIX  *{kind}*  {ARROW}{no:>2}"),
                    String::new(),
                    s("   DELTA    0.00NM"),
                    format!("   SYS ACCUR {}", if nav_ok { "HIGH" } else { "LOW" }),
                    String::new(),
                ]
            }
            Page::Acal => [
                s("   A-CAL  *GPS*  AUTO"),
                String::new(),
                s("   ALT DELTA      0FT"),
                s("   POS DELTA  0.00NM"),
                String::new(),
            ],
            Page::List => [
                s("LIST"),
                s("1DEST 2BNGO 3VIP  RINTG"),
                s("4NAV  5MAN  6INS  EDLNK"),
                s("7EWS  8MODE 9VRP  0MISC"),
                String::new(),
            ],
            Page::Misc => [
                s("MISC"),
                s("1CORR 2MAGV 3OFP  RHMCS"),
                s("4INSM 5LASR 6GPS  E"),
                s("7DRNG 8BULL 9WPT  0HARM"),
                String::new(),
            ],
            Page::Nav => [
                s("      NAV STATUS"),
                format!("  SYS ACCUR   {}", if nav_ok { "HIGH" } else { "LOW" }),
                s("  GPS ACCUR   HIGH"),
                s("  MSN DUR   0 DAYS"),
                String::new(),
            ],
            Page::Ins => {
                let i = nav.ins;
                let rdy = if i.aligned || (i.need_s > 0.0 && i.elapsed_s >= i.need_s) { "RDY" } else { "" };
                let [lon, lat] = utm36n_geo(nav.e, nav.n);
                [
                    format!("INS  {:04.1}/{:02}  {rdy}", (i.elapsed_s.min(i.need_s.max(0.0)) / 60.0), i.status()),
                    format!("  LAT  {}", deg_min(lat, 'N', 'S', 2)),
                    format!("  LNG  {}", deg_min(lon, 'E', 'W', 3)),
                    format!(" SALT  {:>6}FT", nav.alt_ft.round() as i64),
                    format!("THDG {:5.1}\u{b0}  G/S {:>4}", nav.heading_deg, nav.ground_kt.round() as i64),
                ]
            }
            Page::Mode => {
                let m = match nav.master_aa {
                    Some(true) => "AA",
                    Some(false) => "AG",
                    None => "NAV",
                };
                [
                    format!("       MODE {}", self.show(0, s(m))),
                    String::new(),
                    String::new(),
                    String::new(),
                    String::new(),
                ]
            }
            Page::Magv => [
                // The magnetic variation over Israel, about 5° east in 2026 (inferred from the world magnetic model's
                // map); the sim's headings are grid headings, so it is shown only.
                s("    MAGV  AUTO  E 5.0\u{b0}"),
                String::new(),
                String::new(),
                String::new(),
                String::new(),
            ],
            Page::Lasr => [
                format!("        LASER  {ARROW}"),
                format!("   TGP CODE {}", self.show(0, format!("{}", self.laser_code))),
                format!("   LST CODE  {}", self.laser_code),
                s("A-G: CMBT  A-A: TRNG"),
                format!(" LASER ST TIME  {:.0} SEC", crate::eo::LASER_START_S),
            ],
            Page::Bull => [
                format!("     {}", self.show(0, s(if self.bull { "BULLSEYE" } else { "  OFF   " }))),
                String::new(),
                format!(
                    "  BULLSEYE {}",
                    self.show(1, if self.bull_no == 0 { s("HOME") } else { format!("{:>4}", self.bull_no) })
                ),
                String::new(),
                String::new(),
            ],
            Page::Hmcs => [
                s("     HMCS DISPLAY"),
                s("  HUD BLNK      ON"),
                s("  CKPT BLNK    OFF"),
                s("  DECLUTTER   LVL1"),
                String::new(),
            ],
            Page::Ews | Page::Iff | Page::Dlnk | Page::Intg => self.ews_lines(nav),
            Page::Com1 | Page::Com2 => {
                let (name, r, t) = if self.page == Page::Com1 {
                    ("UHF", self.uhf, &UHF_PRESETS)
                } else {
                    ("VHF", self.vhf, &VHF_PRESETS)
                };
                let backup = self.page == Page::Com1 && self.uhf_backup.is_some();
                [
                    format!("{name}  {}", if backup { "BACKUP" } else { "ON" }),
                    format!("      {}", self.show(0, s("      "))),
                    format!("  PRE {ARROW}{:>3}", r.preset),
                    format!("      {:6.2}", f64::from(r.khz(t)) / 1000.0),
                    if r.manual.is_some() { s("      MAN") } else { String::new() },
                ]
            }
        }
    }

    /// The EW and identification pages (modern-iaf/docs/ews.md §8): EWS (SEQ: CONTROLS, BINGO, the chaff and the
    /// flare program, INC / DEC the program; after the DCS guide's "EWS" pages), IFF (the AIFF's settings), DLNK (the
    /// link's status) and INTG (the last interrogation). The layouts are inferred from the DCS guide.
    fn ews_lines(&self, nav: &Nav) -> [String; 5] {
        let e = nav.ews.clone().unwrap_or_default();
        let on = |b: bool| if b { "ON " } else { "OFF" }.to_string();
        let blank = String::new;
        match self.page {
            Page::Ews if self.sub == 1 => [
                format!("   EWS CONTROLS  {}", e.mode),
                format!(" CH {:>3}    REQCTR{}", e.chaff, self.show(0, on(e.opts[0]))),
                format!(" FL {:>3}    BINGO {}", e.flares, self.show(1, on(e.opts[1]))),
                format!("            FDBK  {}", self.show(2, on(e.opts[2]))),
                format!("            REQJAM{}", self.show(3, on(e.opts[3]))),
            ],
            Page::Ews if self.sub == 2 => [
                "     CMDS  BINGO".to_string(),
                format!("   CHAFF {}", self.show(0, format!("{:>3}", e.bingo[0]))),
                format!("   FLARE {}", self.show(1, format!("{:>3}", e.bingo[1]))),
                blank(),
                blank(),
            ],
            Page::Ews => {
                let p = e.programs[self.ews_prog.min(3)];
                let (name, d) = if self.sub == 3 { ("CHAFF", p.chaff) } else { ("FLARE", p.flare) };
                [
                    format!(" CMDS {name} PRGM {ARROW}{}", self.ews_prog + 1),
                    format!("   BQ {}", self.show(0, format!("{:>2}", d.bq))),
                    format!("   BI {}", self.show(1, format!("{:6.3}", d.bi))),
                    format!("   SQ {}", self.show(2, format!("{:>2}", d.sq))),
                    format!("   SI {}", self.show(3, format!("{:6.2}", d.si))),
                ]
            }
            Page::Iff if self.sub == 1 => {
                let x = self.xpdr;
                let mode = |i: usize, name: &str| {
                    let code = match i {
                        0 => format!("  {:02}", x.codes[0]),
                        1 | 2 => format!("{:04}", x.codes[i]),
                        _ => "    ".to_string(),
                    };
                    format!(" {name} {}", self.show(i, format!("{} {code}", on(x.on[i]))))
                };
                [
                    format!("  IFF  XPDR  {}", if x.ident(nav.tod_s) { "IDENT" } else { "" }),
                    mode(0, "M1 "),
                    mode(1, "M2 "),
                    mode(2, "M3A"),
                    mode(3, "MC "),
                ]
            }
            Page::Iff if e.aiff => [
                "        IFF  AIFF".to_string(),
                format!("  SCAN  {:>3}\u{b0} AZ/EL", crate::aiff::SCAN_HALF.to_degrees().round()),
                format!("  LOS   {:>3}\u{b0} AZ", crate::aiff::LOS_HALF.to_degrees().round()),
                format!("  RNG   {:>3}NM", (crate::aiff::RANGE_M / NM).round()),
                format!("  REPLY {:>3}S", crate::aiff::SHOW_S),
            ],
            Page::Iff => ["        IFF".to_string(), "  NO INTERROGATOR".to_string(), blank(), blank(), blank()],
            Page::Intg => [
                "        INTG".to_string(),
                format!("  LAST  {}", e.intg.map_or("----", |los| if los { "LOS" } else { "SCAN" })),
                format!("  FRIEND {:>3}", e.friends),
                format!("  UNK    {:>3}", e.unknowns),
                blank(),
            ],
            _ => [
                "        DLNK".to_string(),
                format!("  POWER  {}", on(e.dl)),
                format!("  TEAM   {:>3}", e.team),
                format!("  TRACKS {:>3}", e.tracks),
                format!("  UPDATE {:>3}S", crate::datalink::PERIOD),
            ],
        }
    }

    /// CRUS: TOS, RNG, HOME, EDR (SEQ). The HOME page's optimum altitude and EDR's optimum Mach need the jet's cruise
    /// tables, which are not public (open): not shown.
    fn crus(&self, nav: &Nav) -> [String; 5] {
        let p = nav.selected().copied();
        let no = p.map_or(0, |p| p.number);
        let dist = p.map(|p| nav.to(p.e, p.n).1);
        let fuel_after = |m: f64| nav.time_for(m).map(|t| nav.fuel_lbs - nav.fuel_pph * t / 3600.0);
        let lbs = |v: Option<f64>| v.map_or("-----".to_string(), |v| format!("{:>5}", v.max(0.0).round() as i64));
        let wind = format!("  WIND  {:03.0}\u{b0} {:>3}KT", nav.wind_from_deg.rem_euclid(360.0), nav.wind_kt.round());
        match self.sub {
            1 => {
                let eta = dist.and_then(|d| nav.time_for(d)).map(|t| nav.tod_s + t);
                let want = p.and_then(|p| p.tos_s).map(|t| t + self.delta_tos_s);
                let rqd =
                    dist.zip(want).and_then(|(d, t)| (t > nav.tod_s).then(|| d / NM / ((t - nav.tod_s) / 3600.0)));
                [
                    format!("  CRUS  TOS   {ARROW}{no:>2}"),
                    format!("  SYSTEM   {}", hms(nav.tod_s)),
                    format!("  DESIRED  {}", want.map_or("--:--:--".into(), hms)),
                    format!("  ETA      {}", eta.map_or("--:--:--".into(), hms)),
                    format!("  RQD G/S  {:>5}KT", rqd.map_or("---".into(), |v| format!("{}", v.round() as i64))),
                ]
            }
            2 => [
                format!("  CRUS  RNG   {ARROW}{no:>2}"),
                format!("  FUEL  {}LBS", lbs(dist.and_then(fuel_after))),
                String::new(),
                wind,
                String::new(),
            ],
            3 => {
                let home = nav.route.iter().find(|s| s.number == self.home);
                let d = home.map(|h| nav.to(h.e, h.n).1);
                [
                    format!("  CRUS  HOME  {ARROW}"),
                    format!("  HOME STPT  {}", self.show(0, format!("{:>2}", self.home))),
                    format!("  FUEL  {}LBS", lbs(d.and_then(fuel_after))),
                    wind,
                    String::new(),
                ]
            }
            _ => {
                let t = (nav.fuel_pph > 0.0).then(|| (nav.fuel_lbs - nav.bingo_lbs).max(0.0) / nav.fuel_pph * 3600.0);
                [
                    format!("  CRUS  EDR   {ARROW}{no:>2}"),
                    format!("  TO BNGO  {}", t.map_or("--:--:--".into(), hms)),
                    format!("  FUEL FLOW {:>5}PPH", nav.fuel_pph.round() as i64),
                    wind,
                    String::new(),
                ]
            }
        }
    }

    /// The hack clock's time (s).
    pub fn hack(&self, tod: f64) -> f64 {
        self.hack_from.map_or(self.hack_s, |f| self.hack_s + (tod - f).max(0.0))
    }

    /// The MARK page's point (UTM metres, elevation ft) for its sensor: OFLY the jet's position under it, FCR / TGP /
    /// HUD their points.
    fn mark_point(&self, nav: &Nav) -> Option<[f64; 3]> {
        match self.sub {
            1 => nav.fcr_at,
            2 => nav.tgp_at,
            3 => nav.hud_at,
            _ => Some([nav.e, nav.n, f64::NAN]),
        }
    }

    /// The selected TACAN station in reach, (name, bearing °, slant range m): T/R gives both, REC the bearing only
    /// (range 0), A/A TR no ground station. The line of sight limits it: 1.23 · (√h_jet + √h_station) NM (ft).
    pub fn tacan(&self, nav: &Nav) -> Option<(&'static str, f64, f64)> {
        if self.tcn_mode == 2 {
            return None;
        }
        let s = STATIONS.iter().find(|s| s.channel == self.tcn_chan && s.y_band == self.tcn_y)?;
        let [e, n] = utm36n(s.lon, s.lat);
        let (b, d) = nav.to(e, n);
        let reach = 1.23 * (nav.alt_ft.max(0.0).sqrt() + 30.0_f64.sqrt()) * NM;
        let dz = (nav.alt_ft - s.elev_ft) * FT;
        (d <= reach.max(5.0 * NM)).then(|| (s.name, b, if self.tcn_mode == 1 { d.hypot(dz) } else { 0.0 }))
    }

    /// An ICP key.
    pub fn press(&mut self, b: Btn, nav: &Nav) -> Effect {
        let page = |p: Page, me: &mut Ufc| {
            me.page = p;
            me.sub = 1;
            me.field = 0;
            me.scratch.clear();
            Effect::None
        };
        match b {
            Btn::Rtn => page(Page::Cni, self),
            Btn::List => page(Page::List, self),
            Btn::Com1 => page(Page::Com1, self),
            Btn::Com2 => page(Page::Com2, self),
            Btn::Iff if nav.ews.is_some() => page(Page::Iff, self),
            Btn::Iff => Effect::None,
            Btn::Seq => {
                self.scratch.clear();
                match self.page {
                    Page::Crus => self.sub = self.sub % 4 + 1,
                    Page::Mark | Page::Fix => self.sub = (self.sub + 1) % 4,
                    Page::Tils => self.tcn_mode = (self.tcn_mode + 1) % 3,
                    Page::Stpt => self.auto_seq = !self.auto_seq,
                    Page::Ews => {
                        self.sub = self.sub % 4 + 1;
                        self.field = 0;
                    }
                    // The transponder, then the AIFF's page (inferred: one IFF page each).
                    Page::Iff => {
                        self.sub = self.sub % 2 + 1;
                        self.field = 0;
                    }
                    _ => {}
                }
                Effect::None
            }
            Btn::Up | Btn::Down => {
                let n = self.fields().len();
                if n > 0 {
                    self.field = if b == Btn::Down { (self.field + 1) % n } else { (self.field + n - 1) % n };
                }
                self.scratch.clear();
                Effect::None
            }
            Btn::Inc | Btn::Dec => self.step(if b == Btn::Inc { 1 } else { -1 }, nav),
            Btn::Rcl => {
                if self.scratch.is_empty() {
                    if self.page == Page::List {
                        return if nav.ews.is_some() { page(Page::Intg, self) } else { Effect::None };
                    }
                    if self.page == Page::Misc {
                        return page(Page::Hmcs, self);
                    }
                    if self.page == Page::Time && self.field == 0 {
                        self.hack_from = None;
                        self.hack_s = 0.0;
                    }
                } else {
                    self.scratch.pop();
                }
                Effect::None
            }
            Btn::Entr => {
                if self.page == Page::Mark && self.scratch.is_empty() {
                    return self.mark(nav);
                }
                if self.page == Page::List && nav.ews.is_some() {
                    return page(Page::Dlnk, self);
                }
                let s = std::mem::take(&mut self.scratch);
                self.enter(&s, nav)
            }
            Btn::Digit(d) => {
                if self.fields().is_empty() || (self.page == Page::Cni) {
                    return self.mode_key(d, nav);
                }
                if self.scratch.len() < 8 {
                    self.scratch.push(char::from(b'0' + d));
                }
                Effect::None
            }
        }
    }

    /// A digit off a data field: the page it calls (the ICP's, the LIST's or MISC's).
    fn mode_key(&mut self, d: u8, nav: &Nav) -> Effect {
        let to = match (self.page, d) {
            (Page::List, 1) => Page::Dest,
            (Page::List, 2) => Page::Bngo,
            (Page::List, 4) => Page::Nav,
            (Page::List, 6) => Page::Ins,
            (Page::List, 8) => Page::Mode,
            (Page::List, 0) => Page::Misc,
            (Page::List, 7) if nav.ews.is_some() => Page::Ews,
            // VIP, MAN, VRP serve the release modes of slice 9 (G21).
            (Page::List, _) => return Effect::None,
            (Page::Misc, 2) => Page::Magv,
            (Page::Misc, 5) => Page::Lasr,
            (Page::Misc, 8) => Page::Bull,
            (Page::Misc, _) => return Effect::None,
            (_, 1) => Page::Tils,
            (_, 2) => Page::Alow,
            (_, 4) => Page::Stpt,
            (_, 5) => Page::Crus,
            (_, 6) => Page::Time,
            (_, 7) => Page::Mark,
            (_, 8) => Page::Fix,
            (_, 9) => Page::Acal,
            _ => return Effect::None,
        };
        self.page = to;
        self.sub = if matches!(to, Page::Mark | Page::Fix) { 0 } else { 1 };
        self.field = 0;
        self.scratch.clear();
        Effect::None
    }

    /// INC / DEC.
    fn step(&mut self, d: i8, nav: &Nav) -> Effect {
        match self.page {
            Page::Tils => {
                self.tcn_chan = (i16::from(self.tcn_chan) + i16::from(d)).clamp(1, 126) as u8;
                Effect::None
            }
            Page::Com1 | Page::Com2 => {
                let r = if self.page == Page::Com1 { &mut self.uhf } else { &mut self.vhf };
                r.preset = ((i16::from(r.preset) - 1 + i16::from(d)).rem_euclid(20) + 1) as u8;
                r.manual = None;
                if self.page == Page::Com1 {
                    self.uhf_backup = None;
                }
                Effect::None
            }
            Page::Ews if self.sub >= 3 => {
                self.ews_prog = (self.ews_prog as i64 + i64::from(d)).rem_euclid(4) as usize;
                self.field = 0;
                self.scratch.clear();
                Effect::None
            }
            Page::Cni | Page::Stpt | Page::Dest | Page::Crus | Page::Fix if !nav.route.is_empty() => {
                Effect::Steer((nav.stpt as i64 + i64::from(d)).rem_euclid(nav.route.len() as i64) as usize)
            }
            _ => Effect::None,
        }
    }

    /// The MARK page's ENTR: a markpoint at the sensor's point, numbered 26 to 30 in turn.
    fn mark(&mut self, nav: &Nav) -> Effect {
        let Some([e, n, elev]) = self.mark_point(nav) else {
            return Effect::None;
        };
        let number = MARK_FIRST + self.next_mark;
        self.next_mark = (self.next_mark + 1) % MARKS;
        let elev_ft = if elev.is_finite() { elev } else { f64::NAN };
        Effect::Mark(Stpt { number, e, n, elev_ft, tos_s: None })
    }

    /// ENTR with the scratchpad `s` into the selected field.
    fn enter(&mut self, s: &str, nav: &Nav) -> Effect {
        let Some(&f) = self.fields().get(self.field) else {
            return Effect::None;
        };
        let num = s.parse::<u32>().ok();
        let sel = nav.selected().copied();
        let edit = |p: Stpt| Effect::Edit(nav.stpt, p);
        let fx = match (f, num) {
            (Fld::Toggle, Some(0)) if self.page == Page::Bull => {
                self.bull = !self.bull;
                Effect::None
            }
            (Fld::Toggle, Some(0)) => Effect::Master(nav.master_aa != Some(true)),
            (Fld::StptNo, Some(v)) => match nav.route.iter().position(|p| u32::from(p.number) == v) {
                Some(i) => Effect::Steer(i),
                None => return Effect::None,
            },
            (Fld::Lat, Some(_)) | (Fld::Lng, Some(_)) => {
                let Some(mut p) = sel else { return Effect::None };
                let [lon, lat] = utm36n_geo(p.e, p.n);
                let ll = if f == Fld::Lat {
                    parse_deg_min(s, 2, 90.0).map(|v| [lon, v])
                } else {
                    parse_deg_min(s, 3, 180.0).map(|v| [v, lat])
                };
                let Some([lon, lat]) = ll else { return Effect::None };
                [p.e, p.n] = utm36n(lon, lat);
                edit(p)
            }
            (Fld::Elev, Some(v)) => sel.map_or(Effect::None, |p| edit(Stpt { elev_ft: f64::from(v), ..p })),
            (Fld::Tos, Some(_)) => match (sel, parse_hms(s)) {
                (Some(p), Some(t)) => edit(Stpt { tos_s: Some(t), ..p }),
                _ => Effect::None,
            },
            (Fld::Chan, Some(0)) => {
                self.tcn_y = !self.tcn_y;
                Effect::None
            }
            (Fld::Chan, Some(v @ 1..=126)) => {
                self.tcn_chan = v as u8;
                Effect::None
            }
            // 108.10 to 111.95 MHz: typed as 10810 (or 1081).
            (Fld::Frq, Some(v)) => {
                let khz = if v < 10_000 { v * 100 } else { v * 10 };
                if (108_100..=111_950).contains(&khz) {
                    self.ils_khz = khz;
                }
                Effect::None
            }
            (Fld::Crs, Some(v @ 0..=359)) => {
                self.ils_crs = v as u16;
                Effect::None
            }
            (Fld::Alow, Some(v @ 0..=50_000)) => {
                self.alow_ft = f64::from(v);
                Effect::None
            }
            (Fld::Floor, Some(v @ 0..=80_000)) => {
                self.floor_ft = f64::from(v);
                Effect::None
            }
            (Fld::Bingo, Some(v @ 0..=99_999)) => Effect::Bingo(f64::from(v)),
            (Fld::Hack, None) => {
                // ENTR with nothing typed starts or stops the hack clock (inferred).
                match self.hack_from.take() {
                    Some(from) => self.hack_s += (nav.tod_s - from).max(0.0),
                    None => self.hack_from = Some(nav.tod_s),
                }
                Effect::None
            }
            (Fld::DeltaTos, Some(_)) => {
                if let Some(t) = parse_hms(s) {
                    self.delta_tos_s = t;
                }
                Effect::None
            }
            (Fld::Home, Some(v @ 1..=99)) => {
                self.home = v as u8;
                Effect::None
            }
            (Fld::Radio, Some(v)) => {
                let (r, lo, hi) = if self.page == Page::Com1 {
                    (&mut self.uhf, 225_000, 399_975)
                } else {
                    (&mut self.vhf, 116_000, 151_975)
                };
                // 1–20 a preset; five or six digits a frequency (24250 = 242.50 MHz).
                let khz = if v >= 100_000 { v } else { v * 10 };
                if (1..=20).contains(&v) {
                    *r = Radio { preset: v as u8, manual: None };
                } else if (lo..=hi).contains(&khz) {
                    r.manual = Some(khz);
                } else {
                    return Effect::None;
                }
                if self.page == Page::Com1 {
                    self.uhf_backup = None;
                }
                Effect::None
            }
            (Fld::Code, Some(_)) => {
                if let Some(c) = laser_code(s) {
                    self.laser_code = c;
                }
                Effect::None
            }
            (Fld::BullNo, Some(v @ 0..=99)) => {
                self.bull_no = v as u8;
                Effect::None
            }
            (Fld::Opt(i), Some(0)) => match &nav.ews {
                Some(e) => {
                    let mut o = e.opts;
                    o[usize::from(i)] = !o[usize::from(i)];
                    Effect::Cmds(CmdsEdit::Opts(o))
                }
                None => Effect::None,
            },
            // M-SEL (a lone 0) turns a mode on or off; octal digits set mode 1's (two) or mode 2's / 3/A's (four) code.
            (Fld::Mode(i), Some(_)) => {
                let i = usize::from(i);
                if s == "0" {
                    self.xpdr.on[i] = !self.xpdr.on[i];
                } else if let Some(c) = (i < 3).then(|| octal(s, if i == 0 { 2 } else { 4 })).flatten() {
                    self.xpdr.codes[i] = c;
                } else {
                    return Effect::None;
                }
                Effect::None
            }
            (Fld::ChaffBingo | Fld::FlareBingo, Some(v @ 0..=99)) => match &nav.ews {
                Some(e) => {
                    let mut b = e.bingo;
                    b[usize::from(f == Fld::FlareBingo)] = v;
                    Effect::Cmds(CmdsEdit::Bingo(b))
                }
                None => Effect::None,
            },
            // BQ and SQ 0–99; BI typed in thousandths (0.020–10.000 s: 20 = 0.020), SI in hundredths (0.50–150.00 s:
            // 50 = 0.50); the ranges after the DCS guide (inferred where it is silent: 0 for none).
            (Fld::Bq | Fld::Bi | Fld::Sq | Fld::Si, Some(v)) => {
                let Some(e) = &nav.ews else { return Effect::None };
                let p = e.programs[self.ews_prog.min(3)];
                let flare = self.sub == 4;
                let mut d = if flare { p.flare } else { p.chaff };
                match f {
                    Fld::Bq if v <= 99 => d.bq = v,
                    Fld::Sq if v <= 99 => d.sq = v,
                    Fld::Bi if v == 0 || (20..=10_000).contains(&v) => d.bi = f64::from(v) / 1000.0,
                    Fld::Si if v == 0 || (50..=15_000).contains(&v) => d.si = f64::from(v) / 100.0,
                    _ => return Effect::None,
                }
                Effect::Cmds(CmdsEdit::Program { index: self.ews_prog.min(3), flare, d })
            }
            _ => Effect::None,
        };
        // An entry moves to the next field, as the DED's asterisks do (DCS guide "UFC").
        if !matches!(f, Fld::StptNo | Fld::Toggle | Fld::Hack | Fld::Chan | Fld::Opt(_) | Fld::Mode(_))
            && !self.fields().is_empty()
        {
            self.field = (self.field + 1) % self.fields().len();
        }
        fx
    }

    /// The IFF IDENT button: the transponder replies with IDENT for [`IDENT_S`] from `tod` (s of the day).
    pub fn ident(&mut self, tod: f64) {
        self.xpdr.ident_until = tod + IDENT_S;
    }

    /// The backup UHF panel's channel knob (the UHF goes to BACKUP on it), one channel on.
    pub fn backup_channel(&mut self) {
        self.uhf_backup = Some(self.uhf_backup.map_or(1, |c| c % 20 + 1));
    }

    /// The bullseye's position (UTM metres) when it is a steerpoint, None for the home base or off.
    pub fn bullseye<'a>(&self, route: &'a [Stpt]) -> Option<&'a Stpt> {
        route.iter().find(|s| self.bull && self.bull_no != 0 && s.number == self.bull_no)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A jet at Ramon's reference point at 1,000 ft, a route of three steerpoints north of it.
    fn nav() -> Nav {
        let [e, n] = utm36n(34.666698, 30.7761);
        Nav {
            e,
            n,
            alt_ft: 1000.0,
            ground_kt: 360.0,
            fuel_lbs: 6000.0,
            fuel_pph: 3600.0,
            tod_s: 9.0 * 3600.0,
            bingo_lbs: 2000.0,
            ins: Ins { knob: 3, elapsed_s: 90.0, need_s: 90.0, aligned: true },
            route: (1..=3)
                .map(|i| Stpt { number: i, e, n: n + f64::from(i) * 10.0 * NM, elev_ft: 2000.0, tos_s: None })
                .collect(),
            ..Nav::default()
        }
    }

    fn keys(u: &mut Ufc, n: &Nav, ks: &[i64]) -> Effect {
        let mut fx = Effect::None;
        for &k in ks {
            fx = u.press(Btn::from_id(k).unwrap(), n);
        }
        fx
    }

    #[test]
    fn every_line_is_24_wide() {
        let n = nav();
        let mut u = Ufc::default();
        for k in [18, 1, 2, 4, 5, 6, 7, 8, 9, 12, 13, 14] {
            keys(&mut u, &n, &[18, k]);
            for l in u.lines(&n) {
                assert_eq!(l.chars().count(), W, "{:?}: {l:?}", u.page);
            }
        }
    }

    #[test]
    fn cni_shows_the_steerpoint_and_time() {
        let n = nav();
        let l = Ufc::default().lines(&n);
        assert!(l[0].starts_with("UHF  305.00") && l[0].trim_end().ends_with("STPT \u{2195}  1"), "{l:?}");
        assert!(l[2].ends_with("09:00:00"), "{l:?}");
        assert!(l[4].trim_end().ends_with("T 75X"), "{l:?}");
    }

    #[test]
    fn stpt_number_and_coordinates_are_entered() {
        let mut n = nav();
        let mut u = Ufc::default();
        assert_eq!(keys(&mut u, &n, &[4, 3, 10]), Effect::Steer(2));
        n.stpt = 2;
        assert!(u.lines(&n)[0].contains("* 3*"), "{:?}", u.lines(&n));
        // DCS down to LAT, 31°00.000' N.
        let fx = keys(&mut u, &n, &[17, 3, 1, 0, 0, 0, 0, 0, 10]);
        let Effect::Edit(2, p) = fx else { panic!("{fx:?}") };
        let [_, lat] = utm36n_geo(p.e, p.n);
        assert!((lat - 31.0).abs() < 1e-6, "{lat}");
        // ELEV after LNG (the entry moved the field on to LNG).
        let fx = keys(&mut u, &n, &[17, 1, 2, 3, 4, 10]);
        assert_eq!(fx, Effect::Edit(2, Stpt { elev_ft: 1234.0, ..n.route[2] }));
        // TOS 09:30:00.
        let Effect::Edit(_, p) = keys(&mut u, &n, &[9, 3, 0, 0, 0, 10]) else { panic!() };
        assert_eq!(p.tos_s, Some(9.5 * 3600.0));
    }

    #[test]
    fn rcl_clears_digit_by_digit_and_bad_entries_are_refused() {
        let n = nav();
        let mut u = Ufc::default();
        keys(&mut u, &n, &[2, 4, 5]);
        assert!(u.lines(&n)[1].contains("*     45*"), "{:?}", u.lines(&n));
        keys(&mut u, &n, &[11, 0, 0, 10]);
        assert_eq!(u.alow_ft, 400.0);
        keys(&mut u, &n, &[1, 2, 18, 4, 9, 10]);
        assert_eq!(n.stpt, 0, "steerpoint 9 does not exist");
    }

    #[test]
    fn bingo_and_alow_are_set() {
        let n = nav();
        let mut u = Ufc::default();
        assert_eq!(keys(&mut u, &n, &[12, 2, 3, 0, 0, 0, 10]), Effect::Bingo(3000.0));
        keys(&mut u, &n, &[18, 2, 5, 0, 0, 10]);
        assert_eq!(u.alow_ft, 500.0);
    }

    #[test]
    fn markpoints_number_26_to_30_and_round() {
        let mut n = nav();
        let mut u = Ufc::default();
        keys(&mut u, &n, &[7]);
        let Effect::Mark(m) = keys(&mut u, &n, &[10]) else { panic!() };
        assert_eq!((m.number, m.e, m.n), (26, n.e, n.n));
        for i in 0..5 {
            let Effect::Mark(m) = keys(&mut u, &n, &[10]) else { panic!() };
            assert_eq!(m.number, if i == 4 { 26 } else { 27 + i });
        }
        // FCR mark: nothing without a point, the point with one.
        keys(&mut u, &n, &[19]);
        assert_eq!(keys(&mut u, &n, &[10]), Effect::None);
        n.fcr_at = Some([1.0, 2.0, 300.0]);
        let Effect::Mark(m) = keys(&mut u, &n, &[10]) else { panic!() };
        assert_eq!((m.e, m.n, m.elev_ft), (1.0, 2.0, 300.0));
    }

    #[test]
    fn tacan_to_ramon_and_the_band() {
        let mut n = nav();
        let [e, n0] = utm36n(34.666698, 30.7761);
        n.e = e;
        n.n = n0 - 20.0 * NM;
        n.alt_ft = 20_000.0;
        let u = Ufc::default();
        let (name, b, r) = u.tacan(&n).unwrap();
        assert_eq!(name, "RAMON");
        assert!(b < 1.0 || b > 359.0, "north of us: {b}");
        assert!((r / NM - 20.2).abs() < 0.2, "{}", r / NM);
        let mut u = Ufc::default();
        keys(&mut u, &n, &[1, 0, 10]);
        assert!(u.tcn_y && u.tacan(&n).is_none(), "75Y is no station");
        keys(&mut u, &n, &[0, 10, 8, 3, 10]);
        assert_eq!(u.tacan(&n).unwrap().0, "NEVATIM");
        // Low and far: below the line of sight.
        n.alt_ft = 50.0;
        n.n = n0 - 150.0 * NM;
        assert!(Ufc::default().tacan(&n).is_none());
    }

    #[test]
    fn crus_tos_needs_the_ground_speed() {
        let mut n = nav();
        n.route[0].n = n.n + 60.0 * NM;
        n.route[0].tos_s = Some(n.tod_s + 1800.0);
        let mut u = Ufc::default();
        keys(&mut u, &n, &[5]);
        let l = u.lines(&n);
        assert!(l[3].contains("09:10:00"), "60 NM at 360 kt: {l:?}");
        assert!(l[4].contains("120KT"), "{l:?}");
        keys(&mut u, &n, &[19]);
        assert!(u.lines(&n)[1].contains(" 5400LBS"), "{:?}", u.lines(&n));
        keys(&mut u, &n, &[19, 19]);
        assert!(u.lines(&n)[1].contains("01:06:40"), "4000 lb over bingo at 3600 pph: {:?}", u.lines(&n));
    }

    #[test]
    fn ins_status_falls_to_ready() {
        let mut n = nav();
        n.ins = Ins { knob: 1, elapsed_s: 45.0, need_s: 90.0, aligned: false };
        let mut u = Ufc::default();
        keys(&mut u, &n, &[12, 6]);
        assert!(u.lines(&n)[0].starts_with("INS  00.8/55  "), "{:?}", u.lines(&n));
        n.ins.elapsed_s = 90.0;
        assert!(u.lines(&n)[0].contains("RDY"));
        assert!(!n.ins.nav(), "STOR HDG: no navigation yet");
    }

    #[test]
    fn radios_presets_and_frequencies() {
        let n = nav();
        let mut u = Ufc::default();
        keys(&mut u, &n, &[13, 5, 10]);
        assert_eq!(u.uhf.khz(&UHF_PRESETS), UHF_PRESETS[4]);
        keys(&mut u, &n, &[2, 4, 2, 5, 0, 10]);
        assert_eq!(u.uhf.khz(&UHF_PRESETS), 242_500);
        u.backup_channel();
        assert!(u.lines(&n)[0].starts_with("UHF  BACKUP"));
        keys(&mut u, &n, &[14, 20]);
        assert_eq!(u.vhf.preset, 2);
        keys(&mut u, &n, &[18]);
        assert!(u.lines(&n)[0].starts_with("UHF  BACKUP") && u.lines(&n)[2].starts_with("VHF  2"));
    }

    #[test]
    fn hack_time_and_laser_code() {
        let mut n = nav();
        let mut u = Ufc::default();
        keys(&mut u, &n, &[6, 10]);
        n.tod_s += 65.0;
        assert!(u.lines(&n)[2].contains("00:01:05"));
        keys(&mut u, &n, &[18, 0, 5, 17, 18]);
        keys(&mut u, &n, &[12, 0, 5, 1, 5, 1, 1, 10]);
        assert_eq!(u.laser_code, 1511);
        keys(&mut u, &n, &[1, 9, 1, 1, 10]);
        assert_eq!(u.laser_code, 1511, "9 is no laser code digit");
    }

    fn ews_nav() -> Nav {
        Nav {
            ews: Some(EwsView {
                programs: crate::cmds::PROGRAMS,
                bingo: [10, 10],
                opts: [true, true, false, true],
                chaff: 60,
                flares: 30,
                mode: "MAN".into(),
                aiff: true,
                intg: Some(false),
                friends: 2,
                dl: true,
                tracks: 5,
                ..Default::default()
            }),
            ..nav()
        }
    }

    #[test]
    fn ews_pages_edit_the_cmds() {
        let n = ews_nav();
        let mut u = Ufc::default();
        keys(&mut u, &n, &[12, 7]);
        assert_eq!(u.page, Page::Ews);
        let l = u.lines(&n);
        assert!(l[1].contains(" CH  60") && l[1].contains("*ON *") && l[3].contains("FDBK   OFF"), "{l:?}");
        // FDBK: DCS down twice, M-SEL.
        assert_eq!(keys(&mut u, &n, &[17, 17, 0, 10]), Effect::Cmds(CmdsEdit::Opts([true, true, true, true])));
        // SEQ: BINGO, the flares' set to 5.
        keys(&mut u, &n, &[19]);
        assert_eq!(keys(&mut u, &n, &[17, 5, 10]), Effect::Cmds(CmdsEdit::Bingo([10, 5])));
        // SEQ: the chaff program 1; INC to program 2, its BI 0.250 s.
        keys(&mut u, &n, &[19, 20]);
        assert!(u.lines(&n)[0].contains("CHAFF PRGM \u{2195}2"), "{:?}", u.lines(&n));
        let want = Dispense { bi: 0.25, ..crate::cmds::PROGRAMS[1].chaff };
        assert_eq!(
            keys(&mut u, &n, &[17, 2, 5, 0, 10]),
            Effect::Cmds(CmdsEdit::Program { index: 1, flare: false, d: want })
        );
        assert_eq!(keys(&mut u, &n, &[17, 5, 10]), Effect::None, "SI 0.05 s refused");
        // SEQ: the flare program, SQ 4.
        keys(&mut u, &n, &[19]);
        let fx = keys(&mut u, &n, &[17, 17, 4, 10]);
        let Effect::Cmds(CmdsEdit::Program { index: 1, flare: true, d }) = fx else { panic!("{fx:?}") };
        assert_eq!(d.sq, 4);
    }

    #[test]
    fn iff_dlnk_and_intg_pages() {
        let n = ews_nav();
        let mut u = Ufc::default();
        keys(&mut u, &n, &[15, 19]);
        assert!(u.page == Page::Iff && u.lines(&n)[1].contains("60"), "{:?}", u.lines(&n));
        keys(&mut u, &n, &[12, 10]);
        assert!(u.page == Page::Dlnk && u.lines(&n)[1].contains("ON") && u.lines(&n)[3].contains("  5"));
        keys(&mut u, &n, &[12, 11]);
        assert!(u.page == Page::Intg && u.lines(&n)[1].contains("SCAN") && u.lines(&n)[2].contains("  2"));
        for p in [[12, 7], [12, 10], [12, 11], [18, 15], [15, 19]] {
            keys(&mut u, &n, &p);
            for l in u.lines(&n) {
                assert_eq!(l.chars().count(), W, "{:?}: {l:?}", u.page);
            }
        }
        // Without the EWS (reborn's jets): none of them.
        let plain = nav();
        let mut u = Ufc::default();
        keys(&mut u, &plain, &[15]);
        assert_eq!(u.page, Page::Cni);
        keys(&mut u, &plain, &[12, 7]);
        assert_eq!(u.page, Page::List);
    }

    #[test]
    fn bullseye_toggles_and_takes_a_steerpoint() {
        let n = nav();
        let mut u = Ufc::default();
        keys(&mut u, &n, &[12, 0, 8, 0, 10]);
        assert!(!u.bull);
        keys(&mut u, &n, &[0, 10, 17, 2, 10]);
        assert!(u.bull && u.bullseye(&n.route).unwrap().number == 2);
    }

    #[test]
    fn the_transponder_page_and_ident() {
        let n = ews_nav();
        let mut u = Ufc::default();
        let cni = |u: &Ufc, n: &Nav| u.lines(n)[4].clone();
        assert!(cni(&u, &n).starts_with("M1 3 C") && cni(&u, &n).ends_with("T 75X"), "{:?}", cni(&u, &n));
        keys(&mut u, &n, &[15]);
        let l = u.lines(&n);
        assert!(l[0].contains("XPDR") && l[1].contains("*ON    00*") && l[3].contains("ON  2000"), "{l:?}");
        // Mode 3/A's code 4721 (DCS down twice), then mode 2 on (DCS up, M-SEL).
        keys(&mut u, &n, &[17, 17, 4, 7, 2, 1, 10]);
        assert_eq!(u.xpdr.codes[2], 4721);
        keys(&mut u, &n, &[16, 0, 10]);
        assert!(u.xpdr.on[1]);
        // 8 is no octal digit; three digits are no mode 3/A code.
        keys(&mut u, &n, &[17, 4, 7, 2, 8, 10, 1, 2, 3, 10]);
        assert_eq!(u.xpdr.codes[2], 4721);
        // Mode C off.
        keys(&mut u, &n, &[17, 0, 10]);
        assert!(!u.xpdr.on[3]);
        // IDENT: on the page and the CNI for 18 s.
        u.ident(n.tod_s);
        assert!(u.lines(&n)[0].contains("IDENT"));
        keys(&mut u, &n, &[18]);
        assert!(cni(&u, &n).starts_with("M1 2 3 I"), "{:?}", cni(&u, &n));
        let later = Nav { tod_s: n.tod_s + IDENT_S + 0.1, ..ews_nav() };
        assert!(cni(&u, &later).starts_with("M1 2 3 ") && !cni(&u, &later).contains(" I"));
        // Without the EWS (reborn's jets) the CNI has no IFF field.
        assert!(cni(&u, &nav()).starts_with("     "));
    }
}
