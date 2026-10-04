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
}
