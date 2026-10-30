//! The F-16's real MFD formats (ours, docs/real-mfd.md "F-16C/D Barak", docs/mfd.md §9): the format each game page
//! stands for, the three formats each MFD holds, the format menu and what each OSB (option select button) does. The
//! drawing is `game/cockpit/f16_mfd.gd`; the page an MFD shows stays the game's (docs/mfd.md §3), so the systems that
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
}

impl Format {
    pub const ALL: [Format; 6] = [Format::Fcr, Format::Sms, Format::Hsd, Format::Wpn, Format::Tgp, Format::Test];

    pub fn label(self) -> &'static str {
        match self {
            Format::Fcr => "FCR",
            Format::Sms => "SMS",
            Format::Hsd => "HSD",
            Format::Wpn => "WPN",
            Format::Tgp => "TGP",
            Format::Test => "TEST",
        }
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
        }
    }

    /// Its OSB on the format menu (fig. 1-29: FCR, TGP, WPN down the left from OSB 20; SMS, HSD by OSB 6 / 7 and TEST
    /// by OSB 9 on the right; TFR, FLIR, DTE and FLCS have no game page and are not offered).
    pub fn menu_osb(self) -> i32 {
        match self {
            Format::Fcr => 20,
            Format::Tgp => 19,
            Format::Wpn => 18,
            Format::Sms => 6,
            Format::Hsd => 7,
            Format::Test => 9,
        }
    }
}

/// A page an F-16 MFD may show: one that stands for a format, or the menu.
pub fn offered(p: i32) -> bool {
    p == page::MENU || Format::of_page(p).is_some()
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
/// menu open, the edge labels decluttered.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Mfd {
    pub slots: [Option<Format>; 3],
    pub primary: usize,
    pub menu: bool,
    pub declutter: bool,
}

impl Mfd {
    /// The formats at the start (inferred: the game's default pages first, radar on the left and the TSD on the
    /// right, docs/mfd.md §7): left FCR, TGP, TEST; right HSD, SMS, WPN.
    pub fn new(side: usize) -> Mfd {
        let slots = if side == 0 {
            [Some(Format::Fcr), Some(Format::Tgp), Some(Format::Test)]
        } else {
            [Some(Format::Hsd), Some(Format::Sms), Some(Format::Wpn)]
        };
        Mfd { slots, primary: 0, menu: false, declutter: false }
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
    /// DCLT (`S-J` on the SMS: no action). On the menu a format's OSB puts it in the primary slot (out of another slot
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
            11 if !self.menu && self.shown() == Some(Format::Sms) => return Press::None,
            11 => {
                self.declutter = !self.declutter;
                return Press::Declutter;
            }
            _ => {}
        }
        if !self.menu {
            return Press::Own(osb);
        }
        let Some(f) = Format::ALL.into_iter().find(|f| f.menu_osb() == osb) else {
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
        assert_eq!(m.press(11), Press::None, "S-J on the SMS");
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
        assert_eq!(fcr_azimuth(120f64.to_radians()), "A6");
        assert_eq!(fcr_azimuth(50f64.to_radians()), "A2");
        assert_eq!((hsd_step(80, true), hsd_step(10, false), hsd_step(20, true)), (80, 10, 40));
        assert_eq!(hsd_range_nm(40), 60);
        assert_eq!((wrap_presses(3, 1, 14, 1), wrap_presses(14, 1, 14, 1)), (1, -13));
        assert_eq!(wrap_presses(200, 10, 200, 10), -19);
    }
}
