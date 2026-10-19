//! The master and HUD modes of the selected store (docs/weapons.md §4; `FUN_0044ec80`, the store keys `FUN_00449810`
//! / `FUN_0044a220`, the MFD page of the mode `FUN_00449810`).

use crate::stores::{GUN, SHELL};

/// The master mode (W+0x..).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Master {
    #[default]
    Nav = 0,
    Bombs = 1,
    AgGun = 2,
    AaGun = 3,
    Missiles = 4,
    LaserBomb = 5,
    Tv = 6,
}

/// The HUD mode.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Hud {
    #[default]
    Nav = 0,
    /// SRM: the IR seeker.
    Srm = 1,
    /// MRM: the radar missiles' circle.
    Mrm = 2,
    /// The AA gun's LCOS.
    AaGun = 3,
    /// The AG gun's strafe pipper.
    AgGun = 4,
    /// CCIP bombs.
    Ccip = 5,
    /// Laser bombs with the FLIR pod.
    Laser = 6,
    Tv = 7,
    Harm = 8,
}

impl Hud {
    pub fn from_index(i: i64) -> Self {
        [Hud::Nav, Hud::Srm, Hud::Mrm, Hud::AaGun, Hud::AgGun, Hud::Ccip, Hud::Laser, Hud::Tv, Hud::Harm]
            .get(usize::try_from(i).unwrap_or(0))
            .copied()
            .unwrap_or_default()
    }
}

pub fn is_aa_missile(type_code: i64) -> bool {
    matches!(type_code, 570 | 580 | 600 | 610)
}

/// What the M key did.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MasterKey {
    Aa,
    Ag,
    Nav,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct Modes {
    pub master: Master,
    pub prev: Master,
    /// The M key's NAV → AA → AG cycle.
    cycle: u8,
    pub hud: Hud,
}

impl Modes {
    /// `FUN_0044ec80`: the master and HUD mode of a store type; `aa_key` = reached by ']'. None (660 / nothing): the
    /// mode stays.
    pub fn for_store(type_code: i64, aa_key: bool, flir_pod: bool) -> Option<(Master, Hud)> {
        Some(match type_code {
            500 | 510 | 560 => (Master::Bombs, Hud::Ccip),
            GUN if aa_key => (Master::AaGun, Hud::AaGun),
            GUN => (Master::AgGun, Hud::AgGun),
            570 | 580 => (Master::Missiles, Hud::Srm),
            600 | 610 => (Master::Missiles, Hud::Mrm),
            590 => (Master::Missiles, Hud::Harm),
            650 => (Master::LaserBomb, if flir_pod { Hud::Laser } else { Hud::Ccip }),
            635 | 640 => (Master::Tv, Hud::Tv),
            _ => return None,
        })
    }

    /// The M key's cycle position: 0 NAV, 1 AA, 2 AG.
    pub fn cycle(&self) -> u8 {
        self.cycle
    }

    /// A new master mode; the previous one is kept when it changes. The HUD mode is the host's to set (its seeker
    /// side effects).
    pub fn set_master(&mut self, m: Master) {
        if m != self.master {
            self.prev = self.master;
        }
        self.master = m;
    }

    /// ']' (event 0x3e): the AA store cycles unless an AA missile is already selected in NAV (the gun counts as AA
    /// unless the last mode was the AG gun).
    pub fn aa_key_cycles(&self, type_code: i64) -> bool {
        let aa = is_aa_missile(type_code) && !(type_code == GUN && self.prev == Master::AgGun);
        self.master != Master::Nav || !aa || type_code == SHELL
    }

    /// '[' (event 0x3c): the AG store cycles unless a non-AA store is already selected in NAV.
    pub fn ag_key_cycles(&self, type_code: i64) -> bool {
        let ag = !is_aa_missile(type_code) && !(type_code != 0 && self.prev == Master::AaGun);
        self.master != Master::Nav || !ag || type_code == SHELL
    }

    /// M (event 0x63): NAV → AA → AG → NAV; at NAV the master mode goes NAV here.
    pub fn master_key(&mut self) -> MasterKey {
        self.cycle = (self.cycle + 1) % 3;
        match self.cycle {
            1 => MasterKey::Aa,
            2 => MasterKey::Ag,
            _ => {
                self.prev = self.master;
                self.master = Master::Nav;
                MasterKey::Nav
            }
        }
    }

    /// N (event 0x62): the master mode `m`, previous kept unconditionally.
    pub fn nav_key(&mut self, m: Master) {
        self.prev = self.master;
        self.master = m;
    }

    /// `FUN_00449810`: the MFD page of the master mode (NAV 0; bombs / AG gun stores 1; AA gun radar 2; IR missiles
    /// none; radar missiles 2; HARM 10; laser bombs with the FLIR pod 6, else 1; TV weapons 5).
    pub fn mfd_page(&self, type_code: i64, flir_pod: bool) -> Option<u8> {
        match self.master {
            Master::Nav => Some(0),
            Master::Bombs | Master::AgGun => Some(1),
            Master::AaGun => Some(2),
            Master::Missiles => match type_code {
                600 | 610 => Some(2),
                590 => Some(10),
                _ => None,
            },
            Master::LaserBomb => Some(if flir_pod { 6 } else { 1 }),
            Master::Tv => Some(5),
        }
    }
}

/// The M key's MFD pages (`FUN_0044a240` case 0x63 after `FUN_00449810`, `LAB_0044b9fb`) for the cycle position
/// (0 NAV, 1 AA, 2 AG), slot by slot (`ctl+0x68 + i·4`; slot 0 = Left). `n` = active MFDs (`ctl+0x14`: 3, 2, any
/// other count sets slot 0 only), `panel_rwr` = the cockpit's panel RWR (`ctl+0x18`), `harm` = a 590 selected (AG:
/// the HARM page 10 instead of the stores page).
/// NAV: radar / NAV / TSD, 2: radar / TSD, 1: TSD. AA: radar / RWR / TSD, 2: radar / (TSD with a panel RWR, else
/// RWR), 1: radar. AG: radar / stores / TSD, 2: radar / stores, 1: stores.
pub fn m_key_pages(cycle: u8, n: usize, panel_rwr: bool, harm: bool) -> Vec<u8> {
    let ag = if harm { 10 } else { 1 };
    match (cycle, n) {
        (0, 3) => vec![2, 0, 3],
        (0, 2) => vec![2, 3],
        (0, _) => vec![3],
        (1, 3) => vec![2, 7, 3],
        (1, 2) => vec![2, if panel_rwr { 3 } else { 7 }],
        (1, _) => vec![2],
        (_, 3) => vec![2, ag, 3],
        (_, 2) => vec![2, ag],
        _ => vec![ag],
    }
}

/// `FUN_00449f20`: the slot a master mode's page goes to when no active MFD shows it (`FUN_00449f90`), from the
/// active MFDs' pages (slot 0 = Left). The first slot not showing the radar (2); all three on the radar: slot 0.
/// Two MFDs both on the radar: `None` (the exe writes the unused slot `ctl+0x70`, so no MFD shows the page).
pub fn free_slot(pages: &[i64]) -> Option<usize> {
    match pages {
        [a, b] if *a == 2 && *b == 2 => None,
        [_, _] | [_, _, _] => Some(pages.iter().position(|&p| p != 2).unwrap_or(0)),
        _ => Some(0),
    }
}

/// The M key's radar calls (`LAB_0044b9fb`): how many times R (`FUN_004ad8f0`) runs, from the radar's A-A flag
/// (`ctl+0xc4` = radar+0x40) and mode (`ctl+0xb4` = radar+0x30, 0 OFF, 1 STBY). NAV / AA: once when A-G or OFF
/// (→ the last A-A mode). AG with 2 or 3 MFDs: in A-A once, and again while still A-A (a radar not radiating goes
/// to A-A first); other counts leave the radar.
pub fn m_key_radar(cycle: u8, n: usize, aa: bool, mode: u8) -> u8 {
    match cycle {
        0 | 1 => u8::from(!aa || mode == 0),
        _ if aa && (n == 2 || n == 3) => 1 + u8::from(mode < 2),
        _ => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn store_modes() {
        assert_eq!(Modes::for_store(GUN, true, false), Some((Master::AaGun, Hud::AaGun)));
        assert_eq!(Modes::for_store(650, false, true), Some((Master::LaserBomb, Hud::Laser)));
        assert_eq!(Modes::for_store(SHELL, false, false), None);
    }

    #[test]
    fn m_key_cycles_and_keys() {
        let mut m = Modes::default();
        assert!(!m.aa_key_cycles(570), "an AIM-9 already selected in NAV");
        assert!(m.aa_key_cycles(500));
        assert_eq!(m.master_key(), MasterKey::Aa);
        m.set_master(Master::Missiles);
        assert_eq!(m.master_key(), MasterKey::Ag);
        assert_eq!(m.master_key(), MasterKey::Nav);
        assert_eq!((m.master, m.prev), (Master::Nav, Master::Missiles));
        assert_eq!(m.mfd_page(570, false), Some(0));
    }

    #[test]
    fn m_key_layouts() {
        assert_eq!(m_key_pages(0, 3, false, false), [2, 0, 3]);
        assert_eq!(m_key_pages(1, 2, true, false), [2, 3]);
        assert_eq!(m_key_pages(1, 2, false, false), [2, 7]);
        assert_eq!(m_key_pages(2, 2, false, true), [2, 10]);
        assert_eq!(m_key_pages(2, 1, false, false), [1]);
    }

    #[test]
    fn placement_and_radar() {
        assert_eq!(free_slot(&[2, 2, 0]), Some(2));
        assert_eq!(free_slot(&[2, 2, 2]), Some(0));
        assert_eq!(free_slot(&[2, 7, 3]), Some(1));
        assert_eq!(free_slot(&[2, 2]), None);
        assert_eq!(free_slot(&[2]), Some(0));
        assert_eq!(m_key_radar(1, 3, true, 4), 0);
        assert_eq!(m_key_radar(0, 1, false, 7), 1);
        assert_eq!(m_key_radar(1, 2, true, 0), 1);
        assert_eq!(m_key_radar(2, 3, true, 0), 2);
        assert_eq!(m_key_radar(2, 2, true, 5), 1);
        assert_eq!(m_key_radar(2, 1, true, 5), 0);
        assert_eq!(m_key_radar(2, 3, false, 7), 0);
    }
}
