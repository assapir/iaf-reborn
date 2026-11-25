//! The F-16's real MFD formats (ours, docs/real-mfd.md "F-16C/D Barak", docs/mfd.md §9): the format each game page
//! stands for, the three formats each MFD holds, the format menu and what each OSB (option select button) does. The
//! drawing is `shared/cockpit/f16_mfd.gd`; the page an MFD shows stays the game's (docs/mfd.md §3), so the systems that
//! set pages (a weapon, the M key) work as before.

/// The game's MFD pages (state+0x504, docs/mfd.md §3).
pub mod page {
    pub const NAV: i32 = 0;
    pub const STORES: i32 = 1;
    pub const RADAR: i32 = 2;
    pub const TSD: i32 = 3;
    pub const DAMAGE: i32 = 4;
    pub const TV: i32 = 5;
    pub const FLIR: i32 = 6;
    pub const RWR: i32 = 7;
    pub const MENU: i32 = 8;
    pub const ADI: i32 = 9;
    pub const HARM: i32 = 10;
    /// Ours (Modern IAF): a format with no game page (DTE, FLCS, BLANK, RESET); the drawing reads the format.
    pub const OWN: i32 = 11;
}

/// A real head-down format (dash-34 fig. 1-29). HAS (the HARM page) is the WPN format with a HARM selected, as on the
/// real jet the WPN format shows the selected weapon's page.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
    Fcr,
    Sms,
    Hsd,
    Wpn,
    Tgp,
    Test,
    Dte,
    Flcs,
    Blank,
    Reset,
    /// The navigation pod's FLIR and TFR formats (modern-iaf/docs/weapons.md §7.4), offered with that pod.
    Flir,
    Tfr,
}

impl Format {
    pub const ALL: [Format; 12] = [
        Format::Fcr,
        Format::Sms,
        Format::Hsd,
        Format::Wpn,
        Format::Tgp,
        Format::Test,
        Format::Dte,
        Format::Flcs,
        Format::Blank,
        Format::Reset,
        Format::Flir,
        Format::Tfr,
    ];

    pub fn label(self) -> &'static str {
        match self {
            Format::Fcr => "FCR",
            Format::Sms => "SMS",
            Format::Hsd => "HSD",
            Format::Wpn => "WPN",
            Format::Tgp => "TGP",
            Format::Test => "TEST",
            Format::Dte => "DTE",
            Format::Flcs => "FLCS",
            Format::Blank => "BLANK",
            Format::Reset => "RESET",
            Format::Flir => "FLIR",
            Format::Tfr => "TFR",
        }
    }

    /// Ours (Modern IAF, the modern MFDs): the formats with no game page, offered only there.
    pub fn modern_only(self) -> bool {
        matches!(self, Format::Dte | Format::Flcs | Format::Blank | Format::Reset | Format::Flir | Format::Tfr)
    }

    /// The formats that can be the sensor of interest (the FCR, HSD, TGP and WPN; the DCS F-16 manual, a simulator
    /// manual, inferred for the Sufa): the others draw no SOI box and pass the SOI to the HUD.
    pub fn soi(self) -> bool {
        matches!(self, Format::Fcr | Format::Hsd | Format::Tgp | Format::Wpn)
    }

    pub fn from_label(s: &str) -> Option<Format> {
        Format::ALL.into_iter().find(|f| f.label() == s)
    }

    /// The format a game page stands for. None: the menu, or a page with no real counterpart (NAV: the steerpoints
    /// are on the DED and the route on the HSD; RWR: the panel's threat azimuth indicator; ADI: the panel ADI).
    pub fn of_page(p: i32) -> Option<Format> {
        match p {
            page::STORES => Some(Format::Sms),
            page::RADAR => Some(Format::Fcr),
            page::TSD => Some(Format::Hsd),
            page::DAMAGE => Some(Format::Test),
            page::TV | page::HARM => Some(Format::Wpn),
            page::FLIR => Some(Format::Tgp),
            _ => None,
        }
    }

    /// The game page this format shows; WPN is the HARM page with a HARM selected, else the TV page.
    pub fn page(self, harm: bool) -> i32 {
        match self {
            Format::Fcr => page::RADAR,
            Format::Sms => page::STORES,
            Format::Hsd => page::TSD,
            Format::Wpn if harm => page::HARM,
            Format::Wpn => page::TV,
            Format::Tgp => page::FLIR,
            Format::Test => page::DAMAGE,
            _ => page::OWN,
        }
    }

    /// Its OSB on the format menu (fig. 1-29: FCR, TGP, WPN down the left from OSB 20; SMS, HSD, DTE, TEST, FLCS by
    /// OSBs 6..10 on the right; BLANK by OSB 1 and RESET (the RESET MENU) by OSB 5 on the top; TFR and FLIR by OSBs 17
    /// and 16 (the DCS F-16 manual's menu, a simulator manual), shown with a navigation pod (f16_mfd.gd). HAD and RCCE
    /// are not offered: the sim has no HARM targeting system or recce pod).
    pub fn menu_osb(self) -> i32 {
        match self {
            Format::Fcr => 20,
            Format::Tgp => 19,
            Format::Wpn => 18,
            Format::Sms => 6,
            Format::Hsd => 7,
            Format::Test => 9,
            Format::Dte => 8,
            Format::Flcs => 10,
            Format::Blank => 1,
            Format::Reset => 5,
            Format::Tfr => 17,
            Format::Flir => 16,
        }
    }
}

/// The formats on the menu: the modern MFDs' all, else the six with a game page.
pub fn menu(modern: bool) -> Vec<Format> {
    Format::ALL.into_iter().filter(|f| modern || !f.modern_only()).collect()
}

/// A page an F-16 MFD may show: one that stands for a format, the menu, or (the modern MFDs) a format of its own.
pub fn offered(p: i32) -> bool {
    p == page::MENU || p == page::OWN || Format::of_page(p).is_some()
}

/// The master modes whose formats each MFD keeps (the real MFDs store their three formats per master mode; the DCS
/// F-16 manual, a simulator manual): NAV, A-A, A-G. (DGFT and MSL override come with avionics-plan.md G17.)
pub const NAV: usize = 0;
pub const AA: usize = 1;
pub const AG: usize = 2;

/// The master mode group of the game's master mode (`Master`) and the selected store's type: the A-A gun and the
/// missiles A-A, the HARM (590) among them A-G; the bombs, the A-G gun, the laser bombs and the TV weapons A-G.
pub fn group(master: i32, store_type: i64) -> usize {
    match master {
        0 => NAV,
        3 => AA,
        4 if store_type != 590 => AA,
        _ => AG,
    }
}

/// The page shown in place of one that is not offered (NAV by the M key): the HSD, which carries the route (inferred).
pub const STAND_IN: i32 = page::TSD;

/// The real OSB number of the game's button `id` (`FUN_00520db0`: top 1–5 and bottom 6–10 left to right, left 11–15
/// and right 16–20 top to bottom). The real numbering runs clockwise from the top left (dash-34 fig. 1-26): top 1–5,
/// right 6–10 down, bottom 11–15 right to left, left 16–20 up. 0: not a button.
pub fn real_osb(id: i32) -> i32 {
    match id {
        1..=5 => id,
        6..=10 => 21 - id,
        11..=15 => 31 - id,
        16..=20 => id - 10,
        _ => 0,
    }
}

/// What an OSB press asks for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Press {
    None,
    /// Show this format (its page).
    Format(Format),
    /// The format menu opened (`Mfd::menu`) or closed.
    Menu,
    /// SWAP: the left and right MFDs trade formats.
    Swap,
    /// DCLT: the edge labels toggled (`Mfd::declutter`).
    Declutter,
    /// One of the shown format's own OSBs (its real number).
    Own(i32),
}

/// One MFD: its three formats (OSBs 14, 13, 12; an empty slot shows no mnemonic), the primary one shown, the format
/// menu open, the edge labels decluttered. The modern MFDs (Modern IAF) keep the three formats per master mode
/// (`sets`, the current mode's in `slots` / `primary`), offer the formats with no game page and hold the HSD's
/// settings.
#[derive(Clone, Debug, PartialEq)]
pub struct Mfd {
    pub slots: [Option<Format>; 3],
    pub primary: usize,
    pub menu: bool,
    pub declutter: bool,
    pub modern: bool,
    pub group: usize,
    sets: [([Option<Format>; 3], usize); 3],
    side: usize,
    pub hsd: Hsd,
}

/// The formats at the start (inferred: the game's default pages first, radar on the left and the TSD on the right,
/// docs/mfd.md §7): left FCR, TGP, TEST; right HSD, SMS, WPN; the same in every master mode (inferred: the real
/// jet's come from its data cartridge).
fn start_slots(side: usize) -> [Option<Format>; 3] {
    if side == 0 {
        [Some(Format::Fcr), Some(Format::Tgp), Some(Format::Test)]
    } else {
        [Some(Format::Hsd), Some(Format::Sms), Some(Format::Wpn)]
    }
}

/// The modern MFDs' formats at the start, per master mode: `start_slots`, the right MFD's A-G primary the SMS.
fn start_sets(side: usize) -> [([Option<Format>; 3], usize); 3] {
    let s = start_slots(side);
    [(s, 0), (s, 0), (s, if side == 1 { 1 } else { 0 })]
}

impl Mfd {
    pub fn new(side: usize) -> Mfd {
        let slots = start_slots(side);
        Mfd {
            slots,
            primary: 0,
            menu: false,
            declutter: false,
            modern: false,
            group: NAV,
            sets: [(slots, 0); 3],
            side,
            hsd: Hsd::default(),
        }
    }

    /// The modern MFDs (Modern IAF, `Settings.modern_mfds()`): A-G starts with the right MFD on the SMS, as the 1998
    /// game shows the stores page for the bombs (inferred: the real jet's sets come from its data cartridge).
    pub fn modern(side: usize) -> Mfd {
        let mut m = Mfd { modern: true, ..Mfd::new(side) };
        m.sets = start_sets(side);
        m
    }

    /// The master mode group changed (`group`): the current formats are kept for the old one and the new one's come
    /// back, with its primary shown. False when the group stays (or on the 1998 game's MFDs, which hold one set).
    pub fn set_group(&mut self, g: usize) -> bool {
        if !self.modern || g == self.group || g > AG {
            return false;
        }
        self.sets[self.group] = (self.slots, self.primary);
        (self.slots, self.primary) = self.sets[g];
        self.group = g;
        self.menu = false;
        true
    }

    /// The RESET MENU's MSMD RESET (ours on its OSB, inferred): every master mode's formats back to the start.
    pub fn reset_modes(&mut self) {
        self.sets = start_sets(self.side);
        (self.slots, self.primary) = self.sets[self.group];
        self.menu = false;
    }

    /// DMS left (the left MFD) / right (the right MFD): the next format of the three becomes the primary, skipping
    /// empty slots (the DCS F-16 manual, a simulator manual; inferred for the Sufa).
    pub fn step(&mut self) -> Option<Format> {
        for k in 1..=3 {
            let i = (self.primary + k) % 3;
            if self.slots[i].is_some() {
                self.primary = i;
                self.menu = false;
                return self.slots[i];
            }
        }
        None
    }

    /// SWAP: the two MFDs trade their current formats (and the HSD's settings with them).
    pub fn swap(&mut self, o: &mut Mfd) {
        std::mem::swap(&mut self.slots, &mut o.slots);
        std::mem::swap(&mut self.primary, &mut o.primary);
        std::mem::swap(&mut self.hsd, &mut o.hsd);
        self.menu = false;
        o.menu = false;
    }

    pub fn shown(&self) -> Option<Format> {
        self.slots[self.primary]
    }

    /// Follows the page the MFD shows (set by the pilot, a weapon or the M key): the menu opens or closes; a format
    /// becomes the primary, from its slot or in place of the primary's.
    pub fn follow(&mut self, p: i32) {
        self.menu = p == page::MENU;
        let Some(f) = Format::of_page(p) else {
            return;
        };
        match self.slots.iter().position(|&s| s == Some(f)) {
            Some(i) => self.primary = i,
            None => self.slots[self.primary] = Some(f),
        }
    }

    /// An OSB press (its real number). The bottom row on every format (fig. 1-43): OSB 15 SWAP, OSBs 14..12 the three
    /// formats (the primary's opens or closes the menu; an empty one becomes the primary with the menu open), OSB 11
    /// DCLT (`S-J` on the SMS: the format's own, the selective jettison with Weapon data Real). On the menu a format's OSB puts it in the primary slot (out of another slot
    /// holding it).
    pub fn press(&mut self, osb: i32) -> Press {
        match osb {
            15 => return Press::Swap,
            12..=14 => {
                let k = (14 - osb) as usize;
                if k == self.primary || self.slots[k].is_none() {
                    self.primary = k;
                    self.menu = !self.menu || self.slots[k].is_none();
                    return Press::Menu;
                }
                self.primary = k;
                self.menu = false;
                return self.slots[k].map_or(Press::None, Press::Format);
            }
            11 if !self.menu && self.shown() == Some(Format::Sms) => return Press::Own(11),
            11 => {
                self.declutter = !self.declutter;
                return Press::Declutter;
            }
            _ => {}
        }
        if !self.menu {
            return Press::Own(osb);
        }
        let Some(f) = menu(self.modern).into_iter().find(|f| f.menu_osb() == osb) else {
            return Press::None;
        };
        if let Some(j) = self.slots.iter().position(|&s| s == Some(f)) {
            self.slots[j] = self.slots[self.primary];
        }
        self.slots[self.primary] = Some(f);
        self.menu = false;
        Press::Format(f)
    }
}

/// The sensor of interest on the HUD (else the MFD's side, 0 left, 1 right).
pub const SOI_HUD: i32 = -1;

/// DMS up / down (ours on keys; the DCS F-16 manual, a simulator manual, inferred for the Sufa): up puts the SOI on
/// the HUD; down moves it from the HUD to the left MFD (else the right) and from one MFD to the other, only onto an MFD
/// whose shown format can be the SOI (`ok`).
pub fn dms(soi: i32, down: bool, ok: [bool; 2]) -> i32 {
    if !down {
        return SOI_HUD;
    }
    let order: [i32; 2] = match soi {
        0 => [1, 0],
        1 => [0, 1],
        _ => [0, 1],
    };
    order.into_iter().find(|&i| ok[i as usize]).unwrap_or(SOI_HUD)
}

/// The SOI kept valid: an MFD whose format can no longer be the SOI hands it to the HUD (inferred).
pub fn soi_valid(soi: i32, ok: [bool; 2]) -> i32 {
    if (0..2).contains(&soi) && !ok[soi as usize] { SOI_HUD } else { soi }
}

/// The HSD's settings (dash-34 pp. 1-82..1-83 and fig. 1-45; the CNTL page's options and their OSBs inferred from
/// the DCS F-16 manual, a simulator manual): OSB 1 DEP / CEN (the ownship a quarter up or in the middle), OSB 2 CPL /
/// DCPL (the range coupled to the FCR's), OSB 3 NORM / EXP1 / EXP2 (2:1, 4:1 about the HSD cursor), OSB 4 FRZ (the
/// picture held where it was), OSB 5 CNTL; the CNTL page's options; the HSD cursor (the SOI's cursor slews it).
#[derive(Clone, Debug, PartialEq)]
pub struct Hsd {
    pub centred: bool,
    pub coupled: bool,
    pub exp: u8,
    /// FRZ: the ownship's world (x, y) and heading when frozen.
    pub frozen: Option<[f64; 3]>,
    pub cntl: bool,
    /// The CNTL options shown (`HSD_OPTIONS`' order).
    pub show: [bool; 5],
    /// The HSD cursor (MFD px); None: on the ownship.
    pub cursor: Option<(f64, f64)>,
    /// EXP's centre (MFD px), the cursor when EXP was pressed.
    pub exp_at: (f64, f64),
}

impl Default for Hsd {
    fn default() -> Self {
        Hsd {
            centred: false,
            coupled: false,
            exp: 0,
            frozen: None,
            cntl: false,
            show: [true; 5],
            cursor: None,
            exp_at: HSD_DEP,
        }
    }
}

/// The CNTL page's options by OSB: the FCR's scan, the preplanned threats, the route, the range rings, the bullseye.
pub const HSD_OPTIONS: [(i32, &str); 5] = [(20, "FCR"), (19, "PRE"), (6, "NAV1"), (7, "RINGS"), (8, "BULL")];
/// The ownship's place and the outer ring's radius (MFD px): depressed a quarter up from the bottom (fig. 1-45), or
/// centred (inferred).
const HSD_DEP: (f64, f64) = (66.0, 99.0);
const HSD_CEN: (f64, f64) = (66.0, 66.0);
const HSD_DEP_R: f64 = 88.0;
const HSD_CEN_R: f64 = 54.0;

impl Hsd {
    /// The ownship (MFD px), the outer ring's radius (px) and its range (NM) for the HSD's own range `scale_nm`, or
    /// the FCR's `fcr_nm` when coupled.
    pub fn view(&self, scale_nm: f64, fcr_nm: f64) -> ((f64, f64), f64, f64) {
        let nm = if self.coupled && fcr_nm > 0.0 { fcr_nm } else { scale_nm };
        if self.centred { (HSD_CEN, HSD_CEN_R, nm) } else { (HSD_DEP, HSD_DEP_R, nm) }
    }

    /// EXP's magnification (1, 2, 4).
    pub fn exp_k(&self) -> f64 {
        f64::from(1u8 << self.exp.min(2))
    }

    /// The cursor's place (MFD px).
    pub fn cursor_px(&self) -> (f64, f64) {
        self.cursor.unwrap_or(if self.centred { HSD_CEN } else { HSD_DEP })
    }

    /// An OSB press of the HSD (`own` = the ownship's world x, y and heading for FRZ): true when it was the HSD's.
    pub fn press(&mut self, osb: i32, own: [f64; 3]) -> bool {
        if osb == 5 {
            self.cntl = !self.cntl;
            return true;
        }
        if self.cntl {
            return match HSD_OPTIONS.iter().position(|o| o.0 == osb) {
                Some(i) => {
                    self.show[i] = !self.show[i];
                    true
                }
                None => false,
            };
        }
        match osb {
            1 => {
                self.centred = !self.centred;
                self.cursor = None;
            }
            2 => self.coupled = !self.coupled,
            3 => {
                self.exp = (self.exp + 1) % 3;
                self.exp_at = self.cursor_px();
            }
            4 => self.frozen = if self.frozen.is_some() { None } else { Some(own) },
            _ => return false,
        }
        true
    }

    /// The labels by their OSBs: [(osb, text, highlighted)].
    pub fn labels(&self) -> Vec<(i32, String, bool)> {
        if self.cntl {
            let mut v: Vec<(i32, String, bool)> =
                HSD_OPTIONS.iter().zip(self.show).map(|(o, on)| (o.0, o.1.to_string(), on)).collect();
            v.push((5, "CNTL".into(), true));
            return v;
        }
        vec![
            (1, if self.centred { "CEN" } else { "DEP" }.into(), false),
            (2, if self.coupled { "CPL" } else { "DCPL" }.into(), false),
            (3, ["NORM", "EXP1", "EXP2"][usize::from(self.exp.min(2))].into(), false),
            (4, "FRZ".into(), self.frozen.is_some()),
            (5, "CNTL".into(), false),
        ]
    }

    /// The cursor slewed by (dx, dy) MFD px, kept on the format.
    pub fn slew(&mut self, dx: f64, dy: f64) {
        let (x, y) = self.cursor_px();
        self.cursor = Some(((x + dx).clamp(12.0, 120.0), (y + dy).clamp(14.0, 118.0)));
    }

    /// TMS up on the HSD: the point under the cursor (within 6 px, the nearest) among `pts` (MFD px).
    pub fn pick(&self, pts: &[(f64, f64)]) -> Option<usize> {
        let c = self.cursor_px();
        let d = |p: &(f64, f64)| (p.0 - c.0).hypot(p.1 - c.1);
        pts.iter().enumerate().filter(|(_, p)| d(p) <= 6.0).min_by(|a, b| d(a.1).total_cmp(&d(b.1))).map(|(i, _)| i)
    }
}

/// The SMS A-G page's submodes offered for the selected bomb (dash-34 fig. 1-70's list, MLU fig. 1-39): a GPS bomb's
/// PRE / VIS, else the release submodes (`delivery::Submode`: CCIP, CCRP, DTOS, LADD, MAN).
pub fn ag_submodes(gps: bool) -> &'static [&'static str] {
    if gps { &["PRE", "VIS"] } else { &["CCIP", "CCRP", "DTOS", "LADD", "MAN"] }
}

/// The FLCS format's BIT (ours, inferred: the real BIT runs on the ground for about 45 s; the DCS F-16 manual, a
/// simulator manual): "" not run, RUN, then PASS, or FAIL with an FLCS fault.
pub const FLCS_BIT_S: f64 = 45.0;
pub fn flcs_bit(started: Option<f64>, now: f64, fault: bool) -> &'static str {
    match started {
        None => "",
        Some(t) if now - t < FLCS_BIT_S => "RUN",
        Some(_) if fault => "FAIL",
        Some(_) => "PASS",
    }
}

/// The TGP's track mode legend (ours from the DCS F-16 manual, a simulator manual, inferred for the Sufa's Litening):
/// `aim` 0 free (slewing: INR), 1 a ground point (AREA), 2 a unit (POINT); slaved to the SPI: none.
pub fn tgp_track(aim: i64, slaved: bool) -> &'static str {
    match aim {
        _ if slaved => "",
        1 => "AREA",
        2 => "POINT",
        _ => "INR",
    }
}

/// The FCR's mode and submode mnemonics (OSB 1, OSB 2; dash-34 pp. 1-118..1-120, figs. 1-84, 1-89, 1-97) for the
/// game's radar mode (state+0xa04): OFF / STBY → STBY; STT and LRS → CRM with the game's search as `LRS` (STT keeps
/// the submode it locked from); TWS → CRM TWS; BORE → ACM BORE; ACM → ACM 20 (the 30° × 20° scan); GMT; MAP → GM MAN.
pub fn fcr_mode(mode: i32) -> (&'static str, &'static str) {
    match mode {
        2 | 4 => ("CRM", "LRS"),
        3 => ("ACM", "BORE"),
        5 => ("CRM", "TWS"),
        6 => ("ACM", "20"),
        7 => ("GMT", ""),
        8 => ("GM", "MAN"),
        _ => ("STBY", ""),
    }
}

/// The real FCR's OSB 2 (ours, docs/radar.md §9): CRM's search `RWS` or `VSR` (the game's LRS), ACM's pattern `20`,
/// `60`, `SLEW` (`acm` 0, 1, 2); else `fcr_mode`'s.
pub fn fcr_real_submode(mode: i32, vsr: bool, acm: i64) -> &'static str {
    match mode {
        4 if vsr => "VSR",
        4 => "RWS",
        6 => ["20", "60", "SLEW"][acm.clamp(0, 2) as usize],
        _ => fcr_mode(mode).1,
    }
}

/// The FCR's azimuth scan mnemonic (OSB 18, p. 1-122): `A` and the half width in tens of degrees, 6 = ±60°, 3 = ±30°,
/// 2 = ±25°, 1 = ±10°, from the scan's full width (radians).
pub fn fcr_azimuth(width: f64) -> &'static str {
    let half = width.to_degrees() / 2.0;
    if half >= 45.0 {
        "A6"
    } else if half >= 27.5 {
        "A3"
    } else if half >= 17.5 {
        "A2"
    } else {
        "A1"
    }
}

/// The HSD's range scale (NM; 15, 30, 60, 120, fig. 1-45) for the game's TSD scale (10, 20, 40, 80): the next step
/// up or down, stopping at the ends (the original's TSD wraps, `FUN_00531850`).
pub fn hsd_step(scale: i32, up: bool) -> i32 {
    if up { (scale * 2).min(80) } else { (scale / 2).max(10) }
}

/// The HSD's range in NM shown for the game's TSD scale: 1.5 × (10 → 15 … 80 → 120); its three rings are a third
/// apart.
pub fn hsd_range_nm(scale: i32) -> i32 {
    scale * 3 / 2
}

/// The presses of a stepped value (the stores' release pulses / interval, events 0x4a / 0x4b) that step it by one
/// on a single OSB, wrapping at the top (the real SMS enters them on a keypad page; one OSB that steps is ours): +1
/// = one step up, −n = n steps down back to `lo`.
pub fn wrap_presses(value: i32, lo: i32, hi: i32, step: i32) -> i32 {
    if value + step > hi { -((value - lo) / step.max(1)) } else { 1 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_game_button_has_its_real_number() {
        let real: Vec<i32> = (1..=20).map(real_osb).collect();
        // top 1..5; bottom left→right = 15..11; left top→bottom = 20..16; right top→bottom = 6..10.
        assert_eq!(real, [1, 2, 3, 4, 5, 15, 14, 13, 12, 11, 20, 19, 18, 17, 16, 6, 7, 8, 9, 10]);
        assert_eq!(real_osb(0), 0);
    }

    #[test]
    fn offered_pages_have_a_format_and_back() {
        for p in 0..=10 {
            match Format::of_page(p) {
                Some(f) => assert_eq!(f.page(p == page::HARM), p, "page {p}"),
                None => assert!(p == page::MENU || [page::NAV, page::RWR, page::ADI].contains(&p)),
            }
        }
        assert!(!offered(page::NAV) && !offered(page::RWR) && !offered(page::ADI) && offered(page::MENU));
        assert!(offered(STAND_IN));
        for f in Format::ALL {
            assert_eq!(Format::from_label(f.label()), Some(f));
        }
    }

    #[test]
    fn bottom_row_selects_opens_the_menu_and_picks() {
        let mut m = Mfd::new(0);
        assert_eq!(m.press(13), Press::Format(Format::Tgp));
        assert_eq!((m.primary, m.menu), (1, false));
        assert_eq!(m.press(13), Press::Menu, "the primary's OSB opens the menu");
        assert!(m.menu);
        assert_eq!(m.press(7), Press::Format(Format::Hsd), "menu OSB 7: HSD into the primary slot");
        assert_eq!(m.slots, [Some(Format::Fcr), Some(Format::Hsd), Some(Format::Test)]);
        m.press(13);
        assert_eq!(m.press(20), Press::Format(Format::Fcr), "a format held elsewhere trades places");
        assert_eq!(m.slots, [Some(Format::Hsd), Some(Format::Fcr), Some(Format::Test)]);
        assert_eq!(m.press(3), Press::Own(3));
        assert_eq!(m.press(15), Press::Swap);
        assert_eq!(m.press(11), Press::Declutter);
        assert!(m.declutter);
        m.follow(page::STORES);
        assert_eq!(m.press(11), Press::Own(11), "S-J on the SMS");
    }

    #[test]
    fn follow_takes_the_slot_or_the_primary() {
        let mut m = Mfd::new(1);
        m.follow(page::STORES);
        assert_eq!((m.primary, m.shown()), (1, Some(Format::Sms)));
        m.follow(page::FLIR);
        assert_eq!(m.slots, [Some(Format::Hsd), Some(Format::Tgp), Some(Format::Wpn)]);
        m.follow(page::MENU);
        assert!(m.menu);
        m.follow(page::HARM);
        assert_eq!((m.primary, m.menu), (2, false));
    }

    #[test]
    fn labels_and_steps() {
        assert_eq!(fcr_mode(5), ("CRM", "TWS"));
        assert_eq!(fcr_mode(8), ("GM", "MAN"));
        assert_eq!((fcr_real_submode(4, false, 0), fcr_real_submode(4, true, 0)), ("RWS", "VSR"));
        assert_eq!((fcr_real_submode(6, false, 2), fcr_real_submode(3, false, 0)), ("SLEW", "BORE"));
        assert_eq!(fcr_azimuth(120f64.to_radians()), "A6");
        assert_eq!(fcr_azimuth(50f64.to_radians()), "A2");
        assert_eq!((hsd_step(80, true), hsd_step(10, false), hsd_step(20, true)), (80, 10, 40));
        assert_eq!(hsd_range_nm(40), 60);
        assert_eq!((wrap_presses(3, 1, 14, 1), wrap_presses(14, 1, 14, 1)), (1, -13));
        assert_eq!(wrap_presses(200, 10, 200, 10), -19);
    }

    #[test]
    fn modern_menu_offers_the_own_formats() {
        let mut m = Mfd::new(0);
        m.press(14);
        assert_eq!(m.press(8), Press::None, "the 1998 game's MFDs offer no DTE");
        let mut m = Mfd::modern(0);
        m.press(14);
        assert_eq!(m.press(8), Press::Format(Format::Dte));
        assert_eq!(m.shown(), Some(Format::Dte));
        assert_eq!(Format::Dte.page(false), page::OWN);
        m.follow(page::OWN);
        assert_eq!(m.shown(), Some(Format::Dte), "the own page keeps the format");
        assert!(offered(page::OWN));
        assert_eq!(menu(false).len(), 6);
        assert_eq!(menu(true).len(), 12);
        let osbs: Vec<i32> = menu(true).iter().map(|f| f.menu_osb()).collect();
        let mut sorted = osbs.clone();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(sorted.len(), osbs.len(), "one OSB per format");
    }

    #[test]
    fn each_master_mode_keeps_its_formats() {
        let mut m = Mfd::modern(1);
        assert!(!m.set_group(NAV));
        m.press(13);
        assert_eq!(m.shown(), Some(Format::Sms));
        assert!(m.set_group(AG));
        assert_eq!((m.primary, m.shown()), (1, Some(Format::Sms)), "A-G starts on its own primary: the SMS");
        m.press(12);
        assert!(m.set_group(NAV));
        assert_eq!(m.shown(), Some(Format::Sms), "NAV's choice came back");
        assert!(m.set_group(AG));
        assert_eq!(m.shown(), Some(Format::Wpn));
        m.reset_modes();
        assert_eq!((m.primary, m.shown()), (1, Some(Format::Sms)));
        let mut old = Mfd::new(0);
        assert!(!old.set_group(AG), "the 1998 game's MFDs hold one set");
        assert_eq!((group(0, 0), group(4, 570), group(4, 590), group(1, 500), group(3, 565)), (NAV, AA, AG, AG, AA));
    }

    #[test]
    fn dms_steps_formats_and_moves_the_soi() {
        let mut m = Mfd::modern(0);
        assert_eq!(m.step(), Some(Format::Tgp));
        assert_eq!(m.step(), Some(Format::Test));
        assert_eq!(m.step(), Some(Format::Fcr));
        assert_eq!(dms(SOI_HUD, true, [true, true]), 0);
        assert_eq!(dms(0, true, [true, true]), 1);
        assert_eq!(dms(1, true, [false, true]), 1, "the left shows no SOI format: stays");
        assert_eq!(dms(SOI_HUD, true, [false, false]), SOI_HUD);
        assert_eq!(dms(1, false, [true, true]), SOI_HUD);
        assert_eq!(soi_valid(1, [true, false]), SOI_HUD);
        assert_eq!(soi_valid(0, [true, false]), 0);
        assert!(Format::Tgp.soi() && !Format::Sms.soi());
        let mut r = Mfd::modern(1);
        m.swap(&mut r);
        assert_eq!((m.shown(), r.shown()), (Some(Format::Hsd), Some(Format::Fcr)));
    }

    #[test]
    fn hsd_settings_and_cursor() {
        let mut h = Hsd::default();
        assert_eq!(h.view(30.0, 40.0), ((66.0, 99.0), 88.0, 30.0));
        assert!(h.press(1, [0.0; 3]) && h.press(2, [0.0; 3]));
        assert_eq!(h.view(30.0, 40.0), ((66.0, 66.0), 54.0, 40.0), "CEN, coupled to the FCR");
        h.slew(10.0, -5.0);
        assert_eq!(h.cursor_px(), (76.0, 61.0));
        assert!(h.press(3, [0.0; 3]));
        assert_eq!((h.exp_k(), h.exp_at), (2.0, (76.0, 61.0)));
        assert_eq!(h.pick(&[(10.0, 10.0), (78.0, 60.0), (75.0, 62.0)]), Some(2));
        assert_eq!(h.pick(&[(10.0, 10.0)]), None);
        assert!(h.press(4, [1.0, 2.0, 0.5]));
        assert_eq!(h.frozen, Some([1.0, 2.0, 0.5]));
        assert!(h.press(5, [0.0; 3]) && h.cntl);
        assert!(h.press(20, [0.0; 3]) && !h.show[0]);
        assert!(!h.press(1, [0.0; 3]), "OSB 1 is not a CNTL option");
        assert_eq!(h.labels()[0], (20, "FCR".to_string(), false));
        h.press(5, [0.0; 3]);
        assert_eq!(h.labels()[3], (4, "FRZ".to_string(), true));
    }

    #[test]
    fn sms_flcs_and_tgp_legends() {
        assert_eq!(ag_submodes(true), ["PRE", "VIS"]);
        assert_eq!(ag_submodes(false), crate::delivery::Submode::ALL.map(crate::delivery::Submode::name));
        assert_eq!(flcs_bit(None, 5.0, false), "");
        assert_eq!(flcs_bit(Some(0.0), 10.0, false), "RUN");
        assert_eq!((flcs_bit(Some(0.0), 50.0, false), flcs_bit(Some(0.0), 50.0, true)), ("PASS", "FAIL"));
        assert_eq!(
            (tgp_track(0, false), tgp_track(1, false), tgp_track(2, false), tgp_track(1, true)),
            ("INR", "AREA", "POINT", "")
        );
    }
}
