//! The navigation pod on the F-16's 5L (modern-iaf/docs/research/pods.md P7, P8; modern-iaf/docs/weapons.md §7.4): the
//! LANTIRN AN/AAQ-13 on the Sufa, a FLIR and a terrain-following radar (TFR); the Pathfinder on the Barak, the FLIR
//! only. Here: the FLIR's warm-up, and the TFR's settings, its commands for automatic and manual terrain following, its
//! fly-ups and its cues. Sources: research/pods.md §3.2 and §3.3 (a Falcon BMS community page that follows the dash-34,
//! secondary); every number those pages do not give is ours, inferred (marked "ours").

use crate::eo::{Pod, pod_state_after};
use iaf_flight::units::G;

const FT: f64 = 3.28084;

/// The FLIR's warm-up: STBY, then 7 to 15 minutes before OPER gives a picture (research/pods.md §3.2); ours the
/// shortest, 7 minutes.
pub const FLIR_WARM_S: f64 = 420.0;

/// The FLIR's state from how long the pod has had power (None: none) and the FLIR format's STBY.
pub fn flir_state(powered_s: Option<f64>, standby: bool) -> Pod {
    pod_state_after(powered_s, standby, FLIR_WARM_S)
}

/// The TFR's modes (research/pods.md §3.3): NORM, WX (rain), LPI (low emission), VLC (very low clearance).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Mode {
    #[default]
    Norm,
    Wx,
    Lpi,
    Vlc,
}

impl Mode {
    pub const ALL: [Mode; 4] = [Mode::Norm, Mode::Wx, Mode::Lpi, Mode::Vlc];

    pub fn label(self) -> &'static str {
        ["NORM", "WX", "LPI", "VLC"][self as usize]
    }
}

/// The ride: how hard the TFR flies the jet over the terrain (research/pods.md §3.3: HARD; SOFT and SMOOTH not
/// described, ours by name).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Ride {
    #[default]
    Hard,
    Soft,
    Smooth,
}

impl Ride {
    pub const ALL: [Ride; 3] = [Ride::Hard, Ride::Soft, Ride::Smooth];

    pub fn label(self) -> &'static str {
        ["HARD", "SOFT", "SMTH"][self as usize]
    }

    /// The g the TFR commands at most and at least (ours).
    pub fn g_limits(self) -> (f64, f64) {
        [(0.0, 3.0), (0.5, 2.5), (0.75, 2.0)][self as usize]
    }

    /// How fast the flight path is brought to the commanded one (s; ours).
    pub fn tau_s(self) -> f64 {
        [1.5, 2.5, 3.5][self as usize]
    }
}

/// The set clearance plane's settings (ft; research/pods.md §3.3, as an operations guide's excerpt is quoted).
pub const SCP_FT: [f64; 4] = [1000.0, 500.0, 300.0, 200.0];
/// VLC's clearance (ft; ours).
pub const VLC_FT: f64 = 100.0;
/// The terrain the TFR sees ahead: SAMPLES heights every STEP_M along the ground track (6 km; ours).
pub const STEP_M: f64 = 250.0;
pub const SAMPLES: usize = 24;
/// A fly-up below this share of the clearance (research/pods.md §3.3 "a share"; ours a half), at about 2 g.
const FLY_UP_SHARE: f64 = 0.5;
pub const FLY_UP_G: f64 = 2.0;
/// OBSTACLE: the path needed to clear the terrain ahead is this far above the jet's (ours).
const OBSTACLE_DEG: f64 = 10.0;
/// G-LIMIT: the climb needed is past the ride's g this long (s; ours).
const G_LIMIT_S: f64 = 1.0;
/// The clearance under the jet is closed over this many times the ride's time, slow enough to level off at the SCP
/// from GAMMA_MIN_DEG within the ride's g (ours; a point-mass closed loop, the test levels_off_at_the_scp_and_rides_over_a_ridge).
const OWN_TAU_K: f64 = 2.0;
/// The commanded flight path stays within these (degrees; ours).
const GAMMA_MIN_DEG: f64 = -15.0;
const GAMMA_MAX_DEG: f64 = 25.0;
/// The TF speed band (KCAS; ours: research/pods.md §3.3 names the band, not its values).
pub const SPEED_BAND_KT: (f64, f64) = (300.0, 600.0);
/// The stick law (the player's stick y: + = pull; ours, tuned on the Sufa's flight model): a proportional and an integral part on
/// the g error.
const STICK_KP: f64 = 0.15;
const STICK_KI: f64 = 0.5;

/// The MISC panel's RF switch (research/pods.md §3.3): QUIET keeps the TFR in LPI, SILENT keeps it from radiating.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Rf {
    #[default]
    Norm,
    Quiet,
    Silent,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Settings {
    pub mode: Mode,
    /// Index into SCP_FT.
    pub scp: usize,
    pub ride: Ride,
}

impl Settings {
    /// The clearance the TFR holds (ft): VLC's, else the SCP.
    pub fn clearance_ft(&self) -> f64 {
        if self.mode == Mode::Vlc { VLC_FT } else { SCP_FT[self.scp.min(SCP_FT.len() - 1)] }
    }

    /// The mode the TFR works in under the RF switch: QUIET forces LPI.
    pub fn mode_under(&self, rf: Rf) -> Mode {
        if rf == Rf::Quiet { Mode::Lpi } else { self.mode }
    }
}

/// Why the TFR flies the jet up (research/pods.md §3.3), with the legend shown.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlyUp {
    /// Below the share of the clearance.
    Low,
    Obstacle,
    GLimit,
    /// The TFR lost while flying automatic TF: wings level and pull up.
    Fail,
}

impl FlyUp {
    pub fn label(self) -> &'static str {
        match self {
            FlyUp::Low => "FLY UP",
            FlyUp::Obstacle => "OBSTACLE",
            FlyUp::GLimit => "G-LIMIT",
            FlyUp::Fail => "TF FAIL",
        }
    }
}

/// The jet and the terrain ahead, each frame.
#[derive(Clone, Debug, Default)]
pub struct Input {
    pub agl_m: f64,
    pub alt_m: f64,
    pub tas_ms: f64,
    /// The flight path angle and the bank (radians).
    pub gamma: f64,
    pub roll: f64,
    pub kcas: f64,
    /// The terrain's height (m) STEP_M · (k + 1) ahead along the ground track; None where there is none (NO TER).
    pub profile: Vec<Option<f64>>,
    pub gear_down: bool,
}

/// The switches the pilot sets.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Switches {
    /// The TFR has its power (LEFT HDPT) and the pod is the LANTIRN.
    pub powered: bool,
    pub rf: Rf,
    /// ADV MODE selected: automatic TF.
    pub adv: bool,
    /// The FLCS panel's MANUAL TF FLYUP at ENABLE.
    pub man_flyup: bool,
    /// The paddle switch held: no fly-up.
    pub paddle: bool,
}

/// What the TFR commands and shows this frame.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Cue {
    /// The TFR radiates and gives commands.
    pub operating: bool,
    /// Automatic TF flies the pitch (ADV MODE's ACTIVE).
    pub active: bool,
    /// The flight path the TFR asks for (radians): the HUD's TF box.
    pub gamma_cmd: f64,
    /// The load factor to fly now (the stick law's target).
    pub g_cmd: f64,
    /// The climb needed is past the ride's g.
    pub limit: bool,
    pub fly_up: Option<FlyUp>,
    /// Part of the terrain ahead is unknown.
    pub no_ter: bool,
    /// The speed is outside the TF band.
    pub speed_out: bool,
    /// The system flies the jet: automatic TF or a fly-up.
    pub flies: bool,
}

/// The TFR's state between frames.
#[derive(Clone, Debug, Default)]
pub struct Tfr {
    pub settings: Settings,
    fly_up: Option<FlyUp>,
    over_s: f64,
    was_active: bool,
    stick_i: f64,
    flying: bool,
}

impl Tfr {
    /// One frame: the command, the fly-ups and the cues.
    pub fn step(&mut self, i: &Input, sw: Switches, dt: f64) -> Cue {
        let operating = sw.powered && sw.rf != Rf::Silent;
        let mut c = Cue { operating, ..Cue::default() };
        // TF FAIL: automatic TF had the jet and the TFR stopped; it holds until ADV MODE is let go (ours).
        if self.was_active && !operating && sw.adv && !i.gear_down {
            self.fly_up = Some(FlyUp::Fail);
        }
        if self.fly_up == Some(FlyUp::Fail) && (!sw.adv || operating) {
            self.fly_up = None;
        }
        if !operating {
            self.was_active = false;
            self.over_s = 0.0;
            c.fly_up = self.fly_up.filter(|_| !sw.paddle);
            c.g_cmd = FLY_UP_G;
            c.flies = c.fly_up.is_some();
            return self.done(c);
        }
        let scp = self.settings.clearance_ft() / FT;
        let v = i.tas_ms.max(50.0);
        // The clearance under the jet closed over OWN_TAU_K times the ride's time (a level-off at the SCP within the
        // ride's g), then the ski toe: the climb over that path a point ahead needs, its clearance above both that path
        // and the clearance plane over the ground here (where the jet levels off) (ours).
        let own = ((scp - i.agl_m) / (v * self.settings.ride.tau_s() * OWN_TAU_K)).atan();
        let ground = i.alt_m - i.agl_m;
        let mut need = own;
        for (k, h) in i.profile.iter().enumerate() {
            let d = STEP_M * (k + 1) as f64;
            match h {
                Some(h) => {
                    let over = h + scp - (i.alt_m + d * own.tan()).max(ground + scp);
                    if over > 0.0 {
                        need = need.max(own + (over / d).atan());
                    }
                }
                None => c.no_ter = true,
            }
        }
        c.gamma_cmd = need.clamp(GAMMA_MIN_DEG.to_radians(), GAMMA_MAX_DEG.to_radians());
        let (lo, hi) = self.settings.ride.g_limits();
        let g_vert = i.gamma.cos() + v * (c.gamma_cmd - i.gamma) / (G * self.settings.ride.tau_s());
        c.limit = g_vert > hi;
        self.over_s = if c.limit { self.over_s + dt } else { 0.0 };
        c.g_cmd = g_vert.clamp(lo, hi) / i.roll.cos().max(0.5);
        c.speed_out = i.kcas < SPEED_BAND_KT.0 || i.kcas > SPEED_BAND_KT.1;
        c.active = sw.adv && !i.gear_down;
        self.was_active = c.active;
        // The fly-ups: with automatic TF, or manual TF with MANUAL TF FLYUP at ENABLE; never with the gear down.
        let armed = (c.active || sw.man_flyup) && !i.gear_down;
        let why = if i.agl_m < FLY_UP_SHARE * scp {
            Some(FlyUp::Low)
        } else if c.gamma_cmd - i.gamma > OBSTACLE_DEG.to_radians() {
            Some(FlyUp::Obstacle)
        } else if self.over_s > G_LIMIT_S {
            Some(FlyUp::GLimit)
        } else {
            None
        };
        if !armed {
            self.fly_up = None;
        } else if why.is_some() && self.fly_up.is_none() {
            self.fly_up = why;
        } else if why.is_none() && i.agl_m >= scp {
            // Over: back above the clearance with nothing ahead (ours).
            self.fly_up = None;
        }
        c.fly_up = self.fly_up.filter(|_| !sw.paddle);
        if c.fly_up.is_some() {
            c.g_cmd = c.g_cmd.max(FLY_UP_G / i.roll.cos().max(0.5));
        }
        c.flies = c.active || c.fly_up.is_some();
        self.done(c)
    }

    fn done(&mut self, c: Cue) -> Cue {
        self.flying = c.flies;
        c
    }

    /// The pitch stick (+ = pull) that flies `g_cmd` from the jet's `g`; `pilot` the stick the pilot holds, where the
    /// law starts from when it takes the jet (no jump).
    pub fn stick(&mut self, g_cmd: f64, g: f64, pilot: f64, dt: f64) -> f64 {
        if !self.flying {
            self.stick_i = pilot;
            return pilot;
        }
        let err = g_cmd - g;
        self.stick_i = (self.stick_i + STICK_KI * err * dt).clamp(-1.0, 1.0);
        (self.stick_i + STICK_KP * err).clamp(-1.0, 1.0)
    }
}

/// TF FAIL's roll to wings level: the roll stick (+ right) for the bank `roll` (radians; ours).
pub fn level_wings(roll: f64) -> f64 {
    (-roll.to_degrees() / 45.0).clamp(-1.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flat(agl: f64, ground: f64) -> Input {
        Input {
            agl_m: agl,
            alt_m: ground + agl,
            tas_ms: 240.0,
            kcas: 450.0,
            profile: vec![Some(ground); SAMPLES],
            ..Input::default()
        }
    }

    const ON: Switches = Switches { powered: true, rf: Rf::Norm, adv: true, man_flyup: true, paddle: false };

    #[test]
    fn flir_warms_up() {
        assert_eq!(flir_state(None, false), Pod::Off);
        assert_eq!(flir_state(Some(60.0), false), Pod::Cooling);
        assert_eq!(flir_state(Some(FLIR_WARM_S), true), Pod::Standby);
        assert_eq!(flir_state(Some(FLIR_WARM_S), false), Pod::Operate);
    }

    #[test]
    fn holds_the_clearance_on_flat_ground() {
        let mut t = Tfr::default();
        let c = t.step(&flat(1000.0 / FT, 0.0), ON, 0.1);
        assert!(c.active && c.operating && c.fly_up.is_none() && !c.limit);
        assert!(c.gamma_cmd.abs() < 0.01 && (c.g_cmd - 1.0).abs() < 0.05, "{c:?}");
        // High: it descends; low but above the fly-up: it climbs.
        assert!(t.step(&flat(600.0, 0.0), ON, 0.1).gamma_cmd < 0.0);
        assert!(t.step(&flat(200.0, 0.0), ON, 0.1).gamma_cmd > 0.0);
    }

    #[test]
    fn climbs_ahead_of_a_ridge_and_flies_up_at_a_wall() {
        let mut t = Tfr::default();
        let mut i = flat(1000.0 / FT, 0.0);
        i.profile[11] = Some(300.0); // 300 m high, 3 km ahead
        let c = t.step(&i, ON, 0.1);
        assert!(c.gamma_cmd > 0.05 && c.fly_up.is_none(), "{c:?}");
        i.profile[1] = Some(500.0); // 500 m high, 500 m ahead
        let c = t.step(&i, ON, 0.1);
        assert_eq!(c.fly_up, Some(FlyUp::Obstacle));
        assert!(c.limit && c.g_cmd >= FLY_UP_G);
    }

    #[test]
    fn fly_up_below_half_the_clearance_until_back_above_it() {
        let mut t = Tfr::default();
        assert_eq!(t.step(&flat(100.0, 0.0), ON, 0.1).fly_up, Some(FlyUp::Low));
        assert_eq!(t.step(&flat(250.0, 0.0), ON, 0.1).fly_up, Some(FlyUp::Low));
        assert_eq!(t.step(&flat(310.0, 0.0), ON, 0.1).fly_up, None);
        // The paddle holds it off; manual TF with MANUAL TF FLYUP off has none.
        assert_eq!(t.step(&flat(100.0, 0.0), Switches { paddle: true, ..ON }, 0.1).fly_up, None);
        let mut m = Tfr::default();
        assert_eq!(m.step(&flat(100.0, 0.0), Switches { adv: false, man_flyup: false, ..ON }, 0.1).fly_up, None);
        assert!(!m.step(&flat(100.0, 0.0), Switches { adv: false, man_flyup: false, ..ON }, 0.1).flies);
    }

    /// A point mass flown by the cue (its g a first-order lag of `g_cmd`, 0.3 s) over `terrain(x)` from `agl` m: the
    /// fly-ups seen after the first 5 s and the least height above the ground then.
    fn closed_loop(agl: f64, terrain: impl Fn(f64) -> f64, secs: f64) -> (Vec<FlyUp>, f64, f64) {
        let (mut t, dt, v) = (Tfr::default(), 0.02, 220.0);
        let (mut x, mut alt, mut gam, mut g) = (0.0, terrain(0.0) + agl, 0.0_f64, 1.0);
        let (mut ups, mut least) = (vec![], f64::MAX);
        for n in 0..(secs / dt) as usize {
            let ground = terrain(x);
            let i = Input {
                agl_m: alt - ground,
                alt_m: alt,
                tas_ms: v,
                gamma: gam,
                kcas: 450.0,
                profile: (1..=SAMPLES).map(|k| Some(terrain(x + STEP_M * k as f64))).collect(),
                ..Input::default()
            };
            let c = t.step(&i, ON, dt);
            if n as f64 * dt > 5.0 {
                least = least.min(alt - ground);
                if let Some(f) = c.fly_up {
                    ups.push(f);
                }
            }
            g += (c.g_cmd - g) * dt / 0.3;
            gam += (g - gam.cos()) * G / v * dt;
            alt += v * gam.sin() * dt;
            x += v * gam.cos() * dt;
        }
        (ups, alt - terrain(x), least)
    }

    #[test]
    fn levels_off_at_the_scp_and_rides_over_a_ridge() {
        let scp = 1000.0 / FT;
        for agl in [1500.0, 800.0] {
            let (ups, end, least) = closed_loop(agl, |_| 0.0, 60.0);
            assert!(ups.is_empty() && (end - scp).abs() < 5.0 && least > scp - 15.0, "{agl}: {ups:?} {end} {least}");
        }
        let ridge = |x: f64| 400.0 * (-((x - 8000.0) / 1500.0).powi(2)).exp();
        let (ups, _, least) = closed_loop(scp, ridge, 60.0);
        assert!(ups.is_empty() && least > scp - 20.0, "{ups:?} {least}");
    }

    #[test]
    fn tf_fail_when_the_tfr_stops_under_automatic_tf() {
        let mut t = Tfr::default();
        t.step(&flat(300.0, 0.0), ON, 0.1);
        let c = t.step(&flat(300.0, 0.0), Switches { rf: Rf::Silent, ..ON }, 0.1);
        assert_eq!(c.fly_up, Some(FlyUp::Fail));
        assert!(c.flies && !c.operating);
        // ADV MODE let go ends it.
        let c = t.step(&flat(300.0, 0.0), Switches { rf: Rf::Silent, adv: false, ..ON }, 0.1);
        assert!(c.fly_up.is_none() && !c.flies);
        assert!(level_wings(0.5) < 0.0 && level_wings(-0.5) > 0.0);
    }

    #[test]
    fn quiet_forces_lpi_and_vlc_its_clearance() {
        let s = Settings { mode: Mode::Vlc, scp: 0, ride: Ride::Hard };
        assert_eq!(s.clearance_ft(), VLC_FT);
        assert_eq!(s.mode_under(Rf::Quiet), Mode::Lpi);
        assert_eq!(Settings::default().clearance_ft(), 1000.0);
    }

    #[test]
    fn the_stick_starts_from_the_pilots_and_pulls_for_more_g() {
        let mut t = Tfr::default();
        assert_eq!(t.stick(2.0, 1.0, 0.1, 0.1), 0.1);
        t.flying = true;
        let s = t.stick(2.0, 1.0, 0.1, 0.1);
        assert!(s > 0.1, "{s}");
    }
}
