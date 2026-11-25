//! The player's autopilot switch (docs/autopilot.md §2): the controller's mode (ctl+0x974) and the AP lamp
//! (indicator 8), with the rules of the A key, the stick and rudder break-out and NAV's throttle gate
//! (`FUN_0044a240` cases 1 / 0xa / 0x10 / throttle). The control loop it starts is `Autopilot::player_mode`; the
//! front is shared/controls/autopilot.gd.
//!
//! The mode, the lamp and the loop disagree in three cases, each as the exe does: autopilot damage puts the lamp out
//! and stops the loop but keeps the mode (NAV keeps dropping the throttle keys, the exe's ctl+0x974 == 2 gate,
//! [`Switch::damaged`]); an ejection stops the loop only (the host); NAV on an empty route flies no loop with the
//! lamp on (`Autopilot::player_mode`).

/// ctl+0x974: the autopilot's mode; the A key steps Off → Level → Nav → Off.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum PlayerAp {
    #[default]
    Off = 0,
    /// LevelFlightCL, the HUD's "AP LVL".
    Level = 1,
    /// Fly2WayPt to the selected waypoint (GoHomeCL on a landing one), the HUD's "AP NAV".
    Nav = 2,
}

impl PlayerAp {
    pub fn from_index(i: i64) -> Self {
        match i {
            1 => PlayerAp::Level,
            2 => PlayerAp::Nav,
            _ => PlayerAp::Off,
        }
    }
}

/// The stick / rudder events at or beyond ±51 (of ±100) disengage the autopilot (@44bd0e, case 0xa).
pub const BREAK_OUT: f64 = 0.51;

/// What a stick event does ([`Switch::stick`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stick {
    /// The stick reaches the flight model (the lamp is out).
    Pass,
    /// Within ±51 with the lamp on: dropped, the autopilot keeps the stick.
    Drop,
    /// Beyond: the autopilot went off and the stick reaches the flight model; `resync`: the throttle goes back to
    /// its axis (leaving anything but Level).
    Off { resync: bool },
}

/// The mode and the lamp.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Switch {
    pub mode: PlayerAp,
    /// Indicator 8, the AP lamp.
    pub lamp: bool,
}

impl Switch {
    /// The mode set, the lamp lit unless Off (the caller starts the loop: `Autopilot::player_mode`).
    pub fn engage(&mut self, mode: PlayerAp) {
        self.mode = mode;
        self.lamp = mode != PlayerAp::Off;
    }

    /// GEV 0x10 (the A key, the lamp click, the landing's StopPlane; @44d13a; the caller refuses it while the
    /// autopilot is damaged): Off → Level → Nav → Off; on the ground the press always goes to Off. The new mode, and
    /// whether the throttle re-syncs (to Off).
    pub fn key(&mut self, on_ground: bool) -> (PlayerAp, bool) {
        let old = if on_ground { PlayerAp::Nav } else { self.mode };
        let next = match old {
            PlayerAp::Off => PlayerAp::Level,
            PlayerAp::Level => PlayerAp::Nav,
            PlayerAp::Nav => PlayerAp::Off,
        };
        self.engage(next);
        (next, next == PlayerAp::Off)
    }

    /// A stick event (x, y; ±1 = ±100), from the keys or the joystick.
    pub fn stick(&mut self, x: f64, y: f64) -> Stick {
        if !self.lamp {
            return Stick::Pass;
        }
        if x.abs() < BREAK_OUT && y.abs() < BREAK_OUT {
            return Stick::Drop;
        }
        let old = self.mode;
        self.engage(PlayerAp::Off);
        Stick::Off { resync: old != PlayerAp::Level }
    }

    /// GEV 10 (the rudder keys): beyond ±51 with the lamp on the autopilot goes off (no throttle re-sync). True when
    /// it did.
    pub fn rudder(&mut self, r: f64) -> bool {
        let off = self.lamp && r.abs() >= BREAK_OUT;
        if off {
            self.engage(PlayerAp::Off);
        }
        off
    }

    /// The throttle commands (GEV 4 / 9, RPM ± 5 %) reach the jet: not in NAV (it holds the throttle), whatever the
    /// lamp.
    pub fn throttle_allowed(&self) -> bool {
        self.mode != PlayerAp::Nav
    }

    /// Damage 6 (`FUN_0044d760` case 6): the lamp out, the mode kept (as coded). True when the lamp was lit: the
    /// caller stops the loop.
    pub fn damaged(&mut self) -> bool {
        std::mem::take(&mut self.lamp)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(mode: PlayerAp) -> Switch {
        let mut s = Switch::default();
        s.engage(mode);
        s
    }

    #[test]
    fn the_a_key_cycles_and_goes_off_on_the_ground() {
        let mut s = Switch::default();
        assert_eq!(s.key(false), (PlayerAp::Level, false));
        assert!(s.lamp);
        assert_eq!(s.key(false), (PlayerAp::Nav, false));
        assert_eq!(s.key(false), (PlayerAp::Off, true));
        assert!(!s.lamp);
        for m in [PlayerAp::Off, PlayerAp::Level, PlayerAp::Nav] {
            let mut s = at(m);
            assert_eq!(s.key(true), (PlayerAp::Off, true), "{m:?} on the ground");
        }
    }

    #[test]
    fn the_stick_breaks_out_beyond_51() {
        assert_eq!(at(PlayerAp::Off).stick(1.0, 0.0), Stick::Pass);
        let mut s = at(PlayerAp::Level);
        assert_eq!(s.stick(0.3, -0.5), Stick::Drop);
        assert_eq!(s, at(PlayerAp::Level));
        assert_eq!(s.stick(0.51, 0.0), Stick::Off { resync: false });
        assert_eq!(s, at(PlayerAp::Off));
        assert_eq!(at(PlayerAp::Nav).stick(0.0, -1.0), Stick::Off { resync: true });
        // Damaged NAV: the lamp is out, so the stick passes and the mode stays.
        let mut s = at(PlayerAp::Nav);
        s.damaged();
        assert_eq!(s.stick(1.0, 0.0), Stick::Pass);
        assert_eq!(s.mode, PlayerAp::Nav);
    }

    #[test]
    fn the_rudder_breaks_out_with_the_lamp_on() {
        let mut s = at(PlayerAp::Nav);
        assert!(!s.rudder(0.5));
        assert!(s.rudder(-0.51));
        assert_eq!(s, at(PlayerAp::Off));
        assert!(!s.rudder(1.0));
    }

    #[test]
    fn damage_keeps_navs_throttle_gate() {
        let mut s = at(PlayerAp::Nav);
        assert!(!s.throttle_allowed());
        assert!(s.damaged(), "the lamp was lit: the loop stops");
        assert!(!s.lamp);
        assert_eq!(s.mode, PlayerAp::Nav);
        assert!(!s.throttle_allowed(), "the exe's ctl+0x974 == 2 gate keeps dropping the throttle keys");
        assert!(!s.damaged(), "a second hit: nothing to stop");
        assert!(at(PlayerAp::Level).throttle_allowed());
        assert!(at(PlayerAp::Off).throttle_allowed());
    }

    #[test]
    fn index_round_trip() {
        for m in [PlayerAp::Off, PlayerAp::Level, PlayerAp::Nav] {
            assert_eq!(PlayerAp::from_index(m as i64), m);
        }
        assert_eq!(PlayerAp::from_index(7), PlayerAp::Off);
    }
}
