//! The "Real HUD" (ours, Extras > HUD): each jet's real head-up display, gunsight or helmet display instead of the
//! original's simplified 1998 symbology, laid out as drawing primitives in the original's HUD pixels (x right, y down,
//! from the HUD centre); the cockpit draws them. The per-aircraft reference, its sources and how sure each element is:
//! docs/real-hud.md.
//!
//! - `f16`: the F-16C/D Block 30/40/50 HUD (dash-34).
//! - `k2000`: the Kurnass 2000's wide-angle HUD (layout a reconstruction).
//! - `kfir`: the Kfir C7's (Elbit System 82; layout a reconstruction).
//! - `lavi`: the Lavi's wide-angle HUD (its symbology is not public: a reconstruction).
//! - `f15`: the F-15A/C HUD (TO 1F-15A-1, NADC 1976): moving tapes, no digital boxes.
//! - `f15e`: the F-15E HUD (TO 1F-15E-1), the F-15I Ra'am's (its definition's `hud`): digital windows.
//! - `f35`: the F-35's helmet display (the forward "virtual HUD"; LM slides and flight-test video).
//! - `sights`: the F-4E's AN/ASG-26 LCOSS and the Mirage IIICJ's CSF gyro gunsight (no HUD: a reticle only).
//! - `mig23`: the MiG-23ML's АСП-17МЛ sight (radar / IRST data on the sight; no flight data; a reconstruction).
//! - `mig29`: the MiG-29 9.12's ИЛС-31 HUD and the Щель-3УМ helmet sight (layout from the simulator manuals).

mod dash;
mod f15;
mod f15e;
mod f16;
mod f35;
mod k2000;
mod kfir;
mod lavi;
mod mig23;
mod mig29;
mod sights;

use crate::missile::Dlz;
use iaf_flight::units::{FT, G};

/// A point in HUD pixels.
pub type P = (f64, f64);

/// Degrees per milliradian.
const MR_DEG: f64 = 0.0572958;
/// m → NM, m/s → kt.
const NM: f64 = 1852.0;
const MS_TO_KT: f64 = 1.943844;
/// kt → km/h.
const KT_KMH: f64 = 1.852;

/// The jet whose display is drawn.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Jet {
    #[default]
    F16,
    F15,
    /// The F-15E's HUD, the F-15I Ra'am's (its aircraft definition's `hud`: "f15e").
    F15E,
    F35,
    /// The F-4E's optical sight.
    Phantom,
    /// The Mirage IIICJ's gyro gunsight.
    Mirage,
    /// The Kurnass 2000's wide-angle HUD.
    Kurnass2000,
    /// The Kfir C7's HUD.
    Kfir,
    /// The Lavi's wide-angle HUD (a reconstruction).
    Lavi,
    /// The MiG-23ML's АСП-17МЛ sight (a reconstruction).
    MiG23,
    /// The MiG-29 9.12's ИЛС-31 HUD.
    MiG29,
}

impl Jet {
    /// The display of a Real HUD key (the game's `cockpit.real_hud_key`): an aircraft definition's `hud` ("f35",
    /// "f15e"), or a cockpit directory: the `hud` of the definition with that `cockpit` (`iaf_flight::airframe`),
    /// else each 1998 jet's own; f16 (and anything else) the F-16's.
    pub fn of_cockpit(dir: &str) -> Self {
        let d = dir.to_ascii_lowercase();
        let def = iaf_flight::airframe::all()
            .find(|(_, a)| a.cockpit.as_deref().is_some_and(|c| c.eq_ignore_ascii_case(d.trim_end_matches('/'))))
            .and_then(|(_, a)| a.hud.as_deref());
        let key = def.unwrap_or(&d);
        if key == "f35" {
            Jet::F35
        } else if key == "f15e" {
            Jet::F15E
        } else if d.ends_with("f15") {
            Jet::F15
        } else if d.ends_with("phantom") {
            Jet::Phantom
        } else if d.ends_with("mirage") {
            Jet::Mirage
        } else if d.ends_with("f4-2000") {
            Jet::Kurnass2000
        } else if d.ends_with("cfir") {
            Jet::Kfir
        } else if d.ends_with("lavi") {
            Jet::Lavi
        } else if d.ends_with("mig23") {
            Jet::MiG23
        } else if d.ends_with("mig29") {
            Jet::MiG29
        } else {
            Jet::F16
        }
    }

    /// The real display's instantaneous field of view across × up (°; docs/real-hud.md "Real view"): the F-16's
    /// wide-angle HUD and the MiG-29's ИЛС-31 from sources; the wide-angle diffractive HUDs (Lavi, Kurnass 2000) at
    /// their class's 30° × 18°, the rest at a refractive HUD's typical 17.8° × 12° (inferred). None: no glass to fit
    /// (the F-35's helmet).
    pub fn fov_deg(self) -> Option<(f64, f64)> {
        match self {
            Jet::F16 => Some((20.0, 13.5)),
            Jet::F15E => Some((28.0, 21.0)),
            Jet::MiG29 => Some((13.0, 18.0)),
            Jet::Lavi | Jet::Kurnass2000 => Some((30.0, 18.0)),
            Jet::F15 | Jet::Kfir | Jet::MiG23 | Jet::Phantom | Jet::Mirage => Some((17.8, 12.0)),
            Jet::F35 => None,
        }
    }

    /// Real view: the HUD pixels per degree that fit the real field of view, centred on the HUD centre, in the
    /// cockpit art's glass `f`. None: keep the original projection.
    pub fn real_view_px_per_deg(self, f: Field) -> Option<f64> {
        let (across, up) = self.fov_deg()?;
        Some((2.0 * (-f.left).min(f.right) / across).min(2.0 * (-f.top).min(f.bottom) / up))
    }
}

/// Text alignment at its anchor (the baseline's left, centre or right end).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Align {
    Left,
    Centre,
    Right,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Prim {
    Line {
        a: P,
        b: P,
    },
    Circle {
        c: P,
        r: f64,
    },
    /// A filled dot.
    Dot {
        c: P,
        r: f64,
    },
    /// An arc from `from` clockwise through `sweep` (radians, 0 = 12 o'clock).
    Arc {
        c: P,
        r: f64,
        from: f64,
        sweep: f64,
    },
    Text {
        at: P,
        text: String,
        align: Align,
    },
}

fn line(a: P, b: P) -> Prim {
    Prim::Line { a, b }
}

fn text(at: P, t: impl Into<String>, align: Align) -> Prim {
    Prim::Text { at, text: t.into(), align }
}

fn add(a: P, b: P) -> P {
    (a.0 + b.0, a.1 + b.1)
}

fn box_poly(x0: f64, y0: f64, x1: f64, y1: f64) -> [Prim; 4] {
    [line((x0, y0), (x1, y0)), line((x1, y0), (x1, y1)), line((x1, y1), (x0, y1)), line((x0, y1), (x0, y0))]
}

/// The symbology field in HUD pixels from the HUD centre.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Field {
    pub left: f64,
    pub top: f64,
    pub right: f64,
    pub bottom: f64,
}

impl Field {
    fn contains(&self, p: P) -> bool {
        p.0 >= self.left && p.0 <= self.right && p.1 >= self.top && p.1 <= self.bottom
    }

    /// The field narrowed by `dx` on both sides: where the scales and data blocks go, so that they stay on the
    /// cockpit art's glass, which is narrower than the real HUD's.
    fn inset(&self, dx: f64) -> Field {
        Field { left: self.left + dx, right: self.right - dx, ..*self }
    }

    fn centre_y(&self) -> f64 {
        0.5 * (self.top + self.bottom)
    }

    /// A point held on the field's edge along the line from `from` (inside), and whether it was limited.
    fn clamp_from(&self, from: P, p: P) -> (P, bool) {
        if self.contains(p) {
            return (p, false);
        }
        let d = (p.0 - from.0, p.1 - from.1);
        let mut k: f64 = 1.0;
        if d.0 < 0.0 {
            k = k.min((self.left - from.0) / d.0);
        }
        if d.0 > 0.0 {
            k = k.min((self.right - from.0) / d.0);
        }
        if d.1 < 0.0 {
            k = k.min((self.top - from.1) / d.1);
        }
        if d.1 > 0.0 {
            k = k.min((self.bottom - from.1) / d.1);
        }
        ((from.0 + d.0 * k, from.1 + d.1 * k), true)
    }
}

/// The locked target: range (m), closure (m/s, positive closing), its HUD point (None: behind the view).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Target {
    pub range_m: f64,
    pub closure: f64,
    pub at: Option<P>,
    /// Target aspect (rad): 0 its tail toward us, ±π nose-on, positive its left side toward us.
    pub aspect: Option<f64>,
    /// The F-35I's combat ID of the target (`aiff::combat_id`; None: the jet has none).
    pub ident: Option<crate::aiff::Ident>,
}

/// The current steerpoint: its number, bearing (°), distance (m), the time to it (s; None when not closing) and its HUD
/// point on the ground (None: behind the view).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Steerpoint {
    pub number: i64,
    pub bearing_deg: f64,
    pub dist_m: f64,
    pub eta_s: Option<f64>,
    pub at: Option<P>,
}

/// The weapon state the display needs.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Weapons {
    /// The original's HUD mode: 0 NAV, 1 SRM, 2 MRM, 3 A-A gun, 4 A-G gun, 5 bombs, 6 laser bombs, 7 TV, 8 HARM.
    pub hud_mode: i64,
    /// The selected store's name ("AMRAAM", "AIM-9L", "PYTH-5", …).
    pub name: String,
    /// Rounds of the selected store; the SRM and MRM rounds aboard.
    pub selected: i64,
    pub srm: i64,
    pub mrm: i64,
    /// HUD points: the IR seeker (mode 1), the AA gun's lead-computing pipper (mode 3), the strafe / CCIP pipper
    /// (modes 4..6), the MRM steering point (mode 2).
    pub seeker: Option<P>,
    pub lcos: Option<P>,
    pub pipper: Option<P>,
    pub steering: Option<P>,
    /// The MRM launch circle's size (the original's 5 / 3 .. 5).
    pub circle: f64,
    pub shoot: bool,
    /// The delayed CCIP (modes 5 / 6 with the impact point below the HUD; docs/weapons.md §9.4): the time to go (s),
    /// the target under the HUD-edge pipper (HUD px; None: behind the view) and whether Space designated it.
    pub delay: Option<Delay>,
    /// A GPS bomb selected (modes 5 / 6) with coordinates to fly to (docs/weapons.md §13.3).
    pub gps: Option<GpsCue>,
    /// The time to impact (s) of the player's last released GPS bomb while it flies (docs/weapons.md §13.3), in any
    /// HUD mode.
    pub tti: Option<f64>,
    /// A high off-boresight IR missile selected in mode 1 (AIM-9X, Python 5; docs/weapons.md §13.1): the helmet's cues.
    pub hobs: Option<Hobs>,
    /// Modern IAF's F-16s, a bomb selected (modes 5 / 6, no GPS bomb): its release submode's cues and LOW
    /// (`DeliveryCue`; modern-iaf/docs/weapons.md §9).
    pub delivery: Option<DeliveryCue>,
    /// The modern jets' SRM seeker uncaged and tracking its target (modern-iaf/docs/weapons.md §8.1): the large diamond.
    pub srm_track: bool,
    /// The post-launch cue of the player's air-to-air missile in flight (modern-iaf/docs/weapons.md §8.2).
    pub msl_time: Option<MslTime>,
}

/// The post-launch cue: the seconds until the missile's seeker goes active (`active`, "A") or until it reaches its
/// target ("T").
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct MslTime {
    pub active: bool,
    pub s: f64,
}

impl MslTime {
    /// "A12" / "T07" (the DCS F-16C guide's post-launch "Time Until Active/Termination"; whole seconds, at most 99).
    pub fn text(self) -> String {
        format!("{}{:02}", if self.active { 'A' } else { 'T' }, self.s.clamp(0.0, 99.0).ceil() as i64)
    }
}

/// The high off-boresight missile's state for the helmet (docs/real-hud.md "DASH helmet"): its seeker cone (°), the
/// seeker's target in HUD px (None: no target; far along its direction when behind the view) and whether a missile of
/// the player's flies lock-on after launch, still searching.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Hobs {
    pub cone_deg: f64,
    pub target: Option<P>,
    pub loal: bool,
}

/// The release submode's state for the HUD (`crate::delivery`; MLU pp. 172–181, docs/real-hud.md "F-16C/D").
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct DeliveryCue {
    pub submode: crate::delivery::Submode,
    /// The TD box on the target (CCRP, LADD; DTOS once designated) in HUD px, far along its direction off the view;
    /// None without a target.
    pub td: Option<P>,
    /// DTOS: the TD box is ground-stabilized on its designated point (before, it rides the flight path marker).
    pub designated: bool,
    /// Seconds to the automatic release and to the loft's pull-up (CCRP, LADD).
    pub ttr: Option<f64>,
    pub pull_up: Option<f64>,
    /// LOW: a bomb released now hits before its fuze arms (dash-34 p. 1-173).
    pub low: bool,
    /// The lowest release height above the ground below (ft): the fuze's arming, for the pull-up anticipation cue.
    pub min_release_ft: Option<f64>,
    /// MAN with DEPR RET at PRI: the primary reticle, depressed this far (mr) by the RET DEPR wheel.
    pub man_mr: Option<f64>,
}

/// A GPS bomb's cues: its mode (PRE or VIS), the aim's HUD point (far along its direction when outside the view) and
/// the launch acceptability region (`gps::Lar`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GpsCue {
    pub pre: bool,
    pub at: Option<P>,
    pub lar: crate::gps::Lar,
}

/// The delayed CCIP's state (the original's mode-5 object off the HUD).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Delay {
    pub ttg: f64,
    pub target: Option<P>,
    pub designated: bool,
}

/// The real FCR's ACM pattern drawn on the F-16's HUD: the 10 × 60, SLEW at its patch's centre (deg right of the
/// heading and up from the horizon), BORE.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum AcmCue {
    Sixty,
    Slew { az: f64, el: f64 },
    Bore,
}

/// One frame's values.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Input {
    pub jet: Jet,
    /// Sim seconds (the animated symbols).
    pub time_s: f64,
    /// The helmet looking off the nose (the F-35's head-stabilised set; the F-16's / F-15's DASH) and the head's
    /// heading (°); the helmet's line of sight on the view (HUD px) and its direction from the nose (azimuth right +,
    /// elevation up +, °).
    pub off_boresight: bool,
    /// The F-16's helmet display dark: its HMCS SYM INT knob at OFF (`cockpit.gd` `helmet_power`).
    pub helmet_off: bool,
    /// Modern IAF's F-16s: the night-vision goggles down (`nvg::Goggles`). The helmet display then shows no symbols:
    /// the first JHMCS gives the pilot the helmet display or the goggles, never both (modern-iaf/docs/research/nvg.md
    /// §2.2; inferred for the IAF's DASH).
    pub goggles_down: bool,
    pub head_heading_deg: f64,
    pub head_view: P,
    pub head_rel_deg: (f64, f64),
    pub kcas: f64,
    pub ground_kt: f64,
    pub tas_ms: f64,
    pub alt_ft: f64,
    /// Radar altitude (ft), None when invalid.
    pub agl_ft: Option<f64>,
    pub vs_fpm: f64,
    pub heading_deg: f64,
    /// Pitch (nose up +) and roll (right wing down +), degrees.
    pub pitch_deg: f64,
    pub roll_deg: f64,
    pub mach: f64,
    pub g: f64,
    /// The jet's positive g limit (its flight data's MaxG; the F-15E HUD's allowable g).
    pub g_limit: f64,
    pub aoa_deg: f64,
    pub gear_down: bool,
    pub fuel_lbs: f64,
    /// The bingo fuel (lb) below which the bingo cue shows: the player's setting (Settings.bingo_lbs), as the real
    /// pilot sets it.
    pub bingo_lbs: f64,
    /// The flight path marker (None: off the view), the boresight / waterline and the gun cross in HUD pixels.
    pub fpm: Option<P>,
    pub boresight: P,
    pub gun_cross: P,
    /// The horizon straight ahead (the level direction along the heading) in HUD pixels and the view's HUD pixels per
    /// degree: the conformal ladder.
    pub horizon: P,
    pub px_per_deg: f64,
    /// The radar mode (`radar::Mode` as its number: 3 BORE, 6 ACM, …).
    pub radar_mode: i64,
    /// The real FCR's ACM pattern while nothing is locked (the F-16s in Modern IAF; docs/radar.md §9.2).
    pub acm: Option<AcmCue>,
    /// The real FCR's AGR slant range to the visual delivery's aim point (m; docs/radar.md §9.7).
    pub agr_m: Option<f64>,
    /// The ILS bars drawn over the HUD (NAV, gear down): the localizer's x and the glide slope's y (HUD px).
    pub ils: Option<P>,
    pub steerpoint: Option<Steerpoint>,
    pub target: Option<Target>,
    /// The selected store's launch zone at the target (m).
    pub dlz: Option<Dlz>,
    pub weapons: Weapons,
    /// The MAW's warnings (`ews::Maw`; the F-35I's DAS): each missile's bearing off the nose (radians, right +) and its
    /// time to impact (s; infinite while it does not close).
    pub maw: Vec<(f64, f64)>,
    /// Modern IAF's F-16s: the HUD control panel and the up-front controls (modern-iaf/docs/ufc.md). The
    /// default draws the HUD as before (reborn's).
    pub panel: Panel,
}

/// The F-16's HUD control panel switches (dash-34 "HUD remote control panel") and what the up-front controls give the
/// HUD.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Panel {
    pub scales: Scales,
    pub fpm: FpmSwitch,
    pub velocity: Velocity,
    pub alt: AltSwitch,
    /// DED DATA: the DED's lines repeated low on the HUD (empty: OFF).
    pub ded: Vec<String>,
    /// DEPR RET at STBY: the standby reticle depressed this far (mr) by the RET DEPR wheel.
    pub depr_mr: Option<f64>,
    /// The CARA ALOW setting (ft; None: `gaaf::ALOW_FT`).
    pub alow_ft: Option<f64>,
    /// The INS alignment: Some(false) aligning (ALIGN), Some(true) ready to navigate (ALIGN flashing), None neither.
    pub align: Option<bool>,
    /// The DGFT / MSL OVRD switch (`master::Override` as its number: 1 DGFT, 2 MSL OVRD).
    pub over: u8,
    /// MASTER ARM at SIMULATE.
    pub sim: bool,
    /// The HUD is the sensor of interest.
    pub soi: bool,
    /// The ICP's DRIFT C/O switch at DRIFT C/O: the flight path marker centred laterally.
    pub drift_co: bool,
    /// The navigation pod's TFR (`nav_pod`): its HUD cues while it works (modern-iaf/docs/weapons.md §7.4).
    pub tf: Option<TfCue>,
    /// The navigation FLIR's picture shifted by snap-look or look-into-turn: the flight path marker dashed.
    pub flir_shift: bool,
}

/// The TFR's HUD cues (research/pods.md §3.3, secondary; places ours): the TF box this far above the flight path marker
/// (degrees), LIMIT, the fly-up's legend, NO TER, and the airspeed scale flashing outside the TF speed band.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct TfCue {
    pub above_deg: f64,
    pub limit: bool,
    pub fly_up: Option<&'static str>,
    pub no_ter: bool,
    pub speed_out: bool,
}

/// SCALES: VV/VAH (the vertical velocity scale too), VAH (airspeed, altitude, heading), OFF.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Scales {
    VvVah,
    #[default]
    Vah,
    Off,
}

/// FP MARKER: ATT/FPM (the ladder and the marker), FPM (the marker only), OFF.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FpmSwitch {
    #[default]
    AttFpm,
    Fpm,
    Off,
}

/// VELOCITY: CAS, TAS, GND SPD (CAS always with the gear down or in DGFT).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Velocity {
    #[default]
    Cas,
    Tas,
    Gnd,
}

/// ALT: RADAR (the radar altitude on the scale), BARO, AUTO (the radar altitude's thermometer below 1,200 ft).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum AltSwitch {
    Radar,
    #[default]
    Baro,
    Auto,
}

impl Input {
    /// Milliradians → HUD pixels.
    fn mr(&self, mr: f64) -> f64 {
        mr * MR_DEG * self.px_per_deg
    }

    /// Degrees → HUD pixels.
    fn deg(&self, d: f64) -> f64 {
        d * self.px_per_deg
    }
}

/// A frame: `field` is clipped to the symbology field, `outer` is not; `colour` overrides the HUD's colour (the
/// sights' lamp-lit reticles) and `sight` means the jet has no HUD (the original HUD is not drawn at all).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Frame {
    pub field: Vec<Prim>,
    pub outer: Vec<Prim>,
    pub colour: Option<[f32; 3]>,
    pub sight: bool,
    /// MRM (mode 2) with the steering dot shown: the dot inside the launch circle this display draws (the shoot cue
    /// tests it in place of the original's circle, so SHOOT agrees with the picture); None otherwise.
    pub mrm_inside: Option<bool>,
}

/// The Real HUD's own state: the max g latch, the F-15's glide-slope capture.
#[derive(Clone, Debug, Default)]
pub struct RealHud {
    max_g: f64,
    gs_captured: bool,
    /// WARN RESET has put the F-16's FUEL cue out; it re-arms once the fuel is above the bingo again (inferred).
    fuel_reset: bool,
}

impl RealHud {
    pub fn max_g(&self) -> f64 {
        self.max_g
    }

    /// The max g resets (the pilot's reset).
    pub fn reset_max_g(&mut self) {
        self.max_g = 0.0;
    }

    /// The F-16 ICP's WARN RESET: the HUD's FUEL cue out until the fuel is above the bingo again.
    pub fn warn_reset(&mut self) {
        self.fuel_reset = true;
    }

    pub fn frame(&mut self, f: Field, i: &Input) -> Frame {
        self.max_g = self.max_g.max(i.g);
        self.fuel_reset &= i.fuel_lbs < i.bingo_lbs;
        let mut fr = self.jet_frame(f, i);
        if i.weapons.hud_mode == 2 && !i.off_boresight {
            fr.mrm_inside = mrm_circle(i)
                .zip(i.weapons.steering)
                .map(|((c, r), s)| ((s.0 - c.0).powi(2) + (s.1 - c.1).powi(2)).sqrt() <= r);
        }
        fr
    }

    fn jet_frame(&mut self, f: Field, i: &Input) -> Frame {
        match i.jet {
            // The helmet display dark (the HMCS off, the goggles down): nothing, drawn as a jet without a HUD
            // (`sight`), so no other symbol takes its place.
            Jet::F16 | Jet::F15 | Jet::F15E if i.off_boresight && (i.helmet_off || i.goggles_down) => {
                Frame { sight: true, ..Frame::default() }
            }
            Jet::F16 | Jet::F15 | Jet::F15E if i.off_boresight => dash::frame(i),
            Jet::MiG29 if i.off_boresight => mig29::helmet(i),
            Jet::F16 => f16::frame(f, i, self.max_g, self.fuel_reset),
            Jet::F15 => {
                self.gs_captured = f15::gs_capture(i, self.gs_captured);
                f15::frame(f, i, self.gs_captured)
            }
            Jet::F15E => {
                self.gs_captured = f15::gs_capture(i, self.gs_captured);
                f15e::frame(f, i, self.gs_captured)
            }
            Jet::F35 => f35::frame(f, i, self.max_g),
            Jet::Phantom => sights::lcoss(i),
            Jet::Mirage => sights::csf(i),
            Jet::Kurnass2000 => k2000::frame(f, i),
            Jet::Kfir => kfir::frame(f, i),
            Jet::Lavi => lavi::frame(f, i),
            Jet::MiG23 => mig23::frame(f, i),
            Jet::MiG29 => mig29::frame(f, i),
        }
    }
}

// --- shared pieces ----------------------------------------------------------------------------------------------

/// The MRM launch circle (mode 2) the jet's display draws: centre and radius in HUD px; None where it draws none fixed.
/// F-16: the ASEC, 6° under the gun cross, up to 56 mr; F-35: 4° under the boresight, up to 40 mr; F-15, Lavi,
/// Kurnass 2000: on the HUD centre, 60 / 50 / 60 mr. The radius follows the original's circle size (3 .. 5).
fn mrm_circle(i: &Input) -> Option<(P, f64)> {
    let k = |lo: f64| (i.weapons.circle / 5.0).clamp(lo, 1.0);
    match i.jet {
        Jet::F16 => Some((add(i.gun_cross, (0.0, i.deg(6.0))), i.mr(56.0) * k(0.3))),
        Jet::F35 => Some((add(i.boresight, (0.0, i.deg(4.0))), i.mr(40.0) * k(0.4))),
        Jet::F15 | Jet::F15E | Jet::Kurnass2000 => Some(((0.0, 0.0), i.mr(60.0) * k(0.3))),
        Jet::Lavi => Some(((0.0, 0.0), i.mr(50.0) * k(0.3))),
        _ => None,
    }
}

/// Bearing `b` relative to heading `hdg`, degrees in [−180, 180).
fn rel_deg(b: f64, hdg: f64) -> f64 {
    (b - hdg + 180.0).rem_euclid(360.0) - 180.0
}

/// A vertical scale's ticks: values `step` apart within ±half px of `v` at `k` px per unit; `up`: higher values up.
fn ticks(v: f64, step: f64, k: f64, half: f64, up: bool) -> impl Iterator<Item = (f64, f64)> {
    let first = ((v - half / k) / step).ceil() as i64;
    let last = ((v + half / k) / step).floor() as i64;
    (first..=last).map(move |n| {
        let t = n as f64 * step;
        (t, (t - v) * k * if up { -1.0 } else { 1.0 })
    })
}

/// The ±90° symbols: none (the rungs), the F-16's star / earth ([R], the MIL-STD-1787 convention) or the F-15's
/// ⊖ "90" / ⊗ (TO 1F-15A-1) or the F-15E's ○ / ⊗ (TO 1F-15E-1 p. 1-70).
#[derive(Clone, Copy, Debug, PartialEq)]
enum Zenith {
    None,
    StarEarth,
    F15,
    F15E,
}

/// How the ladder's rungs look.
#[derive(Clone, Copy, Debug)]
struct LadderStyle {
    /// Rung half: gap from the centre line (the horizon's too) and length (px); the horizon's length.
    gap: f64,
    len: f64,
    horizon_len: f64,
    tip: f64,
    /// The tips at the rungs' inner ends (F-35) instead of the outer ends (F-15, F-16).
    inner_tips: bool,
    /// Rungs bend toward the horizon by half their angle (F-16 "bendy bars").
    bend: bool,
    /// Labels at both ends (else the left only); signed ("-5") or not.
    both_labels: bool,
    signed: bool,
    /// Rungs whose centre falls within these bands of the field's bottom / top are left out (the heading scale's).
    bottom_band: f64,
    top_band: f64,
    /// What replaces the ±90° rungs.
    zenith: Zenith,
    /// Tabs at the horizon line's outer ends pointing to the ground (F-15E).
    horizon_tabs: bool,
}

/// The conformal pitch ladder: rung e sits e degrees up from the level point ahead, rolled with the jet, slid along
/// the rungs to the marker; climb rungs solid with their tips toward the horizon, dive rungs dashed.
fn ladder(p: &mut Vec<Prim>, i: &Input, fpm: P, f: Field, s: LadderStyle) {
    let k = i.px_per_deg;
    if k <= 0.0 {
        return;
    }
    let (sn, cs) = i.roll_deg.to_radians().sin_cos();
    let (eu, ev) = ((cs, -sn), (-sn, -cs));
    let h = i.horizon;
    let hv = h.0 * ev.0 + h.1 * ev.1;
    let mu = (fpm.0 - h.0) * eu.0 + (fpm.1 - h.1) * eu.1;
    let at = |u: f64, v: f64| (h.0 + (u + mu) * eu.0 + v * ev.0, h.1 + (u + mu) * eu.1 + v * ev.1);
    let (centre, reach) = (-hv / k, (f.bottom - f.top).max(f.right - f.left) / k);
    let first = ((centre - reach) / 5.0).ceil() as i64;
    let last = ((centre + reach) / 5.0).floor() as i64;
    for n in first.max(-18)..=last.min(18) {
        let deg = n * 5;
        let v = deg as f64 * k;
        let y = at(0.0, v).1;
        // The zenith / nadir symbol is not left out under the heading scale.
        if s.zenith != Zenith::None && deg.abs() == 90 {
            zenith_nadir(p, at(0.0, v), i.mr(6.0), deg > 0, s.zenith);
            continue;
        }
        if y > f.bottom - s.bottom_band || y < f.top + s.top_band {
            continue;
        }
        if deg == 0 {
            for side in [-1.0, 1.0] {
                let end = at(side * (s.gap + s.horizon_len), v);
                p.push(line(at(side * s.gap, v), end));
                if s.horizon_tabs {
                    p.push(line(end, (end.0 - s.tip * ev.0, end.1 - s.tip * ev.1)));
                }
            }
            continue;
        }
        // The rung's outer end drops toward the horizon by half its angle when bent.
        let slope = if s.bend { -(deg as f64 / 2.0).to_radians().tan() } else { 0.0 };
        let tip = if deg > 0 { -s.tip } else { s.tip };
        for side in [-1.0, 1.0] {
            let pt = |u: f64| at(side * u, v + slope * (u - s.gap));
            if deg > 0 {
                p.push(line(pt(s.gap), pt(s.gap + s.len)));
            } else {
                for d in 0..3 {
                    let a = s.gap + s.len * d as f64 / 3.0;
                    p.push(line(pt(a), pt(a + s.len * 0.2)));
                }
            }
            let u = if s.inner_tips { s.gap } else { s.gap + s.len };
            let base = pt(u);
            p.push(line(base, (base.0 + tip * ev.0, base.1 + tip * ev.1)));
            if s.both_labels || side < 0.0 {
                let label = if s.signed { format!("{deg}") } else { format!("{}", deg.abs()) };
                let (lx, ly) = pt(s.gap + s.len + 4.0);
                p.push(text((lx, ly + 3.0), label, if side < 0.0 { Align::Right } else { Align::Left }));
            }
        }
    }
}

/// The zenith / nadir symbol, radius `r`. F-16: a star (a circle with eight spokes) / the earth (a circle with a
/// cross). F-15: ⊖ with "90" / ⊗.
fn zenith_nadir(p: &mut Vec<Prim>, (x, y): P, r: f64, zenith: bool, style: Zenith) {
    p.push(Prim::Circle { c: (x, y), r });
    match (style, zenith) {
        (Zenith::StarEarth, true) => {
            for k in 0..8 {
                let (sn, cs) = (f64::from(k) * std::f64::consts::FRAC_PI_4).sin_cos();
                p.push(line((x + r * cs, y + r * sn), (x + 1.8 * r * cs, y + 1.8 * r * sn)));
            }
        }
        (Zenith::StarEarth, false) => {
            p.push(line((x - r, y), (x + r, y)));
            p.push(line((x, y - r), (x, y + r)));
        }
        (Zenith::F15E, true) => {}
        (_, true) => {
            p.push(line((x - r, y), (x + r, y)));
            p.push(text((x + r + 4.0, y + 3.0), "90", Align::Left));
        }
        (_, false) => {
            let d = r * std::f64::consts::FRAC_1_SQRT_2;
            p.push(line((x - d, y - d), (x + d, y + d)));
            p.push(line((x - d, y + d), (x + d, y - d)));
        }
    }
}

/// The flight path marker: a circle of radius `r` with wings `wing` long and a fin `fin` long (px).
fn marker(p: &mut Vec<Prim>, (x, y): P, r: f64, wing: f64, fin: f64) {
    p.push(Prim::Circle { c: (x, y), r });
    marker_wings(p, (x, y), r, wing, fin);
}

/// The flight path marker drawn dashed: its circle in eight arcs (the navigation FLIR's picture shifted).
fn dashed_marker(p: &mut Vec<Prim>, c: P, r: f64, wing: f64, fin: f64) {
    for k in 0..8 {
        p.push(Prim::Arc { c, r, from: k as f64 * std::f64::consts::FRAC_PI_4, sweep: std::f64::consts::PI / 8.0 });
    }
    marker_wings(p, c, r, wing, fin);
}

fn marker_wings(p: &mut Vec<Prim>, (x, y): P, r: f64, wing: f64, fin: f64) {
    p.push(line((x - r, y), (x - r - wing, y)));
    p.push(line((x + r, y), (x + r + wing, y)));
    p.push(line((x, y - r), (x, y - r - fin)));
}

/// An X over a symbol limited at the field's edge.
fn x_over(p: &mut Vec<Prim>, (x, y): P, h: f64) {
    p.push(line((x - h, y - h), (x + h, y + h)));
    p.push(line((x - h, y + h), (x + h, y - h)));
}

fn diamond(p: &mut Vec<Prim>, (x, y): P, h: f64) {
    p.push(line((x, y - h), (x + h, y)));
    p.push(line((x + h, y), (x, y + h)));
    p.push(line((x, y + h), (x - h, y)));
    p.push(line((x - h, y), (x, y - h)));
}

/// The "-W-" waterline symbol at `c`, `w` px half wide.
fn waterline(p: &mut Vec<Prim>, (x, y): P, w: f64) {
    let q = w / 4.0;
    p.push(line((x - w, y), (x - 2.0 * q, y)));
    p.push(line((x - 2.0 * q, y), (x - q, y + q)));
    p.push(line((x - q, y + q), (x, y)));
    p.push(line((x, y), (x + q, y + q)));
    p.push(line((x + q, y + q), (x + 2.0 * q, y)));
    p.push(line((x + 2.0 * q, y), (x + w, y)));
}

/// The EEGS funnel's wingspan (ours: set by the pilot in the real jet) and the M61A1's muzzle speed.
const WINGSPAN_FT: f64 = 35.0;
const MUZZLE: f64 = 1036.0;

/// The EEGS funnel's centre at range `r_ft` for a load factor `g` (HUD px): where the rounds fired one time of flight
/// ago are now — the gun line moved by the jet's pitch rate (n − cos φ)·g / V, and gravity — and the funnel's half
/// width there (the wingspan at that range). The time of flight is Weapon data Real's round (`gun::real_time_of_flight`,
/// drag at the jet's height), so the funnel and the real rounds agree.
fn funnel_at(i: &Input, r_ft: f64, g: f64) -> (P, f64) {
    funnel_at_v(i, r_ft, g, MUZZLE)
}

/// `funnel_at` for a gun of muzzle speed `muzzle` (m/s).
fn funnel_at_v(i: &Input, r_ft: f64, g: f64, muzzle: f64) -> (P, f64) {
    let v = i.tas_ms.max(50.0);
    let roll = i.roll_deg.to_radians();
    let omega = (g - roll.cos()) * G / v;
    let r = r_ft * FT;
    // Rounded to the microsecond: libm's exp / powf differ in the last bit between platforms, and the HUD snapshot
    // tests hash the drawn floats.
    let t =
        (crate::gun::real_time_of_flight(muzzle + v, r, crate::gun::real_drag_k(i.alt_ft * FT)) * 1e6).round() / 1e6;
    let drop = gravity_drop(t, r);
    let down = (omega * t + drop * roll.cos()).to_degrees();
    let side = (drop * roll.sin()).to_degrees();
    let half = ((WINGSPAN_FT * FT / 2.0) / r).atan().to_degrees();
    (add(i.gun_cross, (i.deg(side), i.deg(down))), i.deg(half))
}

/// The A-A gun's funnel (EEGS, F-16, dash-34 fig. 1-257): two lines whose midpoint at each range from 600 ft (top) to
/// `max_ft` (3,000 ft without a lock; longer, toward the HUD's bottom, once the radar tracks the target) is the aim
/// point at that range and whose width is the wingspan there.
fn funnel(p: &mut Vec<Prim>, i: &Input, max_ft: f64) {
    funnel_v(p, i, max_ft, MUZZLE);
}

/// `funnel` for a gun of muzzle speed `muzzle` (m/s).
fn funnel_v(p: &mut Vec<Prim>, i: &Input, max_ft: f64, muzzle: f64) {
    let mut left = Vec::new();
    let mut right = Vec::new();
    let mut r = 600.0;
    while r <= max_ft {
        let (c, half) = funnel_at_v(i, r, i.g, muzzle);
        left.push((c.0 - half, c.1));
        right.push((c.0 + half, c.1));
        r += 200.0;
    }
    for l in [left, right] {
        for w in l.windows(2) {
            p.push(line(w[0], w[1]));
        }
    }
}

/// The angle (rad) a round falls below its line at range `r` after `t` seconds.
fn gravity_drop(t: f64, r: f64) -> f64 {
    9.80665 * t * t / 2.0 / r
}

/// The target-aspect triangle on a reticle circle: 6 o'clock = tail (0°), 12 o'clock = nose-on, 3 o'clock = its left
/// side, 9 o'clock = its right side; the tip on the circle pointing in.
fn aspect_triangle(p: &mut Vec<Prim>, c: P, r: f64, aspect: f64, size: f64) {
    let a = std::f64::consts::PI - aspect;
    let (s, co) = a.sin_cos();
    let tip = (c.0 + r * s, c.1 - r * co);
    let base = (c.0 + (r + size) * s, c.1 - (r + size) * co);
    let (px, py) = (co * size * 0.6, s * size * 0.6);
    let (l, rr) = ((base.0 + px, base.1 + py), (base.0 - px, base.1 - py));
    p.push(line(tip, l));
    p.push(line(l, rr));
    p.push(line(rr, tip));
}

/// The pipper of a lead-computing / CCIP sight: a dot of `dot` px inside a circle of `ring` px.
fn pipper(p: &mut Vec<Prim>, c: P, dot: f64, ring: f64) {
    p.push(Prim::Dot { c, r: dot });
    p.push(Prim::Circle { c, r: ring });
}

/// A vertical launch-zone / range scale: 0 at the bottom, the radar range (10 / 20 / 40 / 80 NM, the smallest above
/// Rmax and the range) at the top; Rmax / Rmin ticks; the target's range caret with the closure (kt) left of it.
/// Returns the scale's top (NM).
fn dlz_scale(p: &mut Vec<Prim>, x: f64, y0: f64, half: f64, t: Target, z: Dlz) -> f64 {
    const SCALES_NM: [f64; 4] = [10.0, 20.0, 40.0, 80.0];
    let top_nm = SCALES_NM.iter().copied().find(|&n| n * NM > z.max.max(t.range_m)).unwrap_or(80.0);
    let y = |m: f64| y0 + half - (m / (top_nm * NM)).clamp(0.0, 1.0) * 2.0 * half;
    p.push(line((x, y0 - half), (x, y0 + half)));
    p.push(text((x, y0 - half - 2.0), format!("{}", top_nm as i64), Align::Centre));
    for m in [z.max, z.min] {
        p.push(line((x, y(m)), (x + 4.0, y(m))));
    }
    let r = y(t.range_m);
    p.push(line((x, r), (x - 3.0, r - 2.0)));
    p.push(line((x, r), (x - 3.0, r + 2.0)));
    p.push(text((x - 5.0, r + 3.0), format!("{}>", (t.closure * MS_TO_KT / 10.0).round() as i64 * 10), Align::Right));
    top_nm
}

/// A GPS bomb's cues (ours after the F-16's JDAM symbology, docs/real-hud.md "GPS bombs"; the layout is inferred from
/// the simulators' manuals):
/// - the target marker: a TD box (`box_half` px) on the aim, held inside the field's edge with an X over it when
///   outside;
/// - the azimuth steering line: through the aim along the rolled vertical; the pilot puts the marker on it;
/// - the LAR staple at `x` (centred on `y0`, `half` px high, 0 at the bottom, the scale's NM above): a bracket from
///   Rmin to Rmax opening left, the range caret on its left; with `cue`, under it, ending at the bracket, the range cue
///   ([`gps_cue`]; the F-15E puts it in its window 19 instead).
///
/// Field symbols go to `p`, the scale to `o`.
fn gps_cues(
    p: &mut Vec<Prim>,
    o: &mut Vec<Prim>,
    i: &Input,
    f: Field,
    (x, y0, half): (f64, f64, f64),
    box_half: f64,
    cue: bool,
) {
    let Some(g) = i.weapons.gps else { return };
    if let Some(at) = g.at {
        let roll = i.roll_deg.to_radians();
        let down = (roll.sin(), roll.cos());
        let long = 2.0 * (f.right - f.left).hypot(f.bottom - f.top);
        // Through the aim's point on the field's edge when it is far out (behind the view: 10,000 px away).
        let inner = Field {
            left: f.left + box_half,
            top: f.top + box_half,
            right: f.right - box_half,
            bottom: f.bottom - box_half,
        };
        let (q, limited) = inner.clamp_from(i.fpm.unwrap_or(i.boresight), at);
        // Ended at the field's edges (the F-35's helmet draws unclipped).
        let (top, _) = f.clamp_from(q, (q.0 - down.0 * long, q.1 - down.1 * long));
        let (bottom, _) = f.clamp_from(q, (q.0 + down.0 * long, q.1 + down.1 * long));
        p.push(line(top, bottom));
        p.extend(box_poly(q.0 - box_half, q.1 - box_half, q.0 + box_half, q.1 + box_half));
        if limited {
            x_over(p, q, box_half);
        }
    }
    const SCALES_NM: [f64; 5] = [5.0, 10.0, 20.0, 40.0, 80.0];
    let l = g.lar;
    let top_nm = SCALES_NM.iter().copied().find(|&n| n * NM > l.rmax.max(l.range)).unwrap_or(80.0);
    let y = |m: f64| y0 + half - (m / (top_nm * NM)).clamp(0.0, 1.0) * 2.0 * half;
    o.push(text((x, y0 - half - 2.0), format!("{}", top_nm as i64), Align::Centre));
    if l.rmax > l.rmin {
        let (a, b) = (y(l.rmax), y(l.rmin));
        o.extend([line((x, a), (x + 4.0, a)), line((x + 4.0, a), (x + 4.0, b)), line((x + 4.0, b), (x, b))]);
    }
    let r = y(l.range);
    o.push(line((x, r), (x - 3.0, r - 2.0)));
    o.push(line((x, r), (x - 3.0, r + 2.0)));
    if let Some(c) = gps_cue(&l).filter(|_| cue) {
        o.push(text((x + 4.0, y0 + half + 10.0), c, Align::Right));
    }
}

/// A GPS bomb's range cue: `IN RNG` inside the LAR, else the time to Rmax (`TMR m:ss`) while closing.
fn gps_cue(l: &crate::gps::Lar) -> Option<String> {
    if l.in_range {
        return Some("IN RNG".to_string());
    }
    l.tmr.map(|t| {
        let t = t.min(5999.0).ceil() as i64;
        format!("TMR {}:{:02}", t / 60, t % 60)
    })
}

/// A GPS bomb's time to impact as the HUDs show it (`TTI m:ss`, whole seconds rounded up).
fn tti_text(t: f64) -> String {
    let t = t.clamp(0.0, 5999.0).ceil() as i64;
    format!("TTI {}:{:02}", t / 60, t % 60)
}

/// A distance in km as the Soviet displays show it: tenths below 10 km, whole km above.
fn km(m: f64) -> String {
    let k = m / 1000.0;
    if k < 9.95 { format!("{k:.1}") } else { format!("{:.0}", k) }
}

/// A metric range scale (the MiGs'): 0 at the bottom, the smallest of `scales_km` above Rmax and the range at the top
/// (its number above the line); Rmax / Rmin ticks right of the line; the target's caret left of it with its range in
/// km. Rmin and Rmax come from the game's launch zone (`Dlz`).
fn km_scale(p: &mut Vec<Prim>, x: f64, y0: f64, half: f64, t: Target, z: Option<Dlz>, scales_km: &[f64]) {
    let far = z.map_or(0.0, |z| z.max).max(t.range_m);
    let top = scales_km.iter().copied().find(|&k| k * 1000.0 > far).unwrap_or(scales_km[scales_km.len() - 1]);
    let y = |m: f64| y0 + half - (m / (top * 1000.0)).clamp(0.0, 1.0) * 2.0 * half;
    p.push(line((x, y0 - half), (x, y0 + half)));
    p.push(text((x, y0 - half - 2.0), format!("{}", top as i64), Align::Centre));
    if let Some(z) = z {
        for m in [z.max, z.min] {
            p.push(line((x, y(m)), (x + 4.0, y(m))));
        }
    }
    let r = y(t.range_m);
    p.push(line((x, r), (x - 3.0, r - 2.0)));
    p.push(line((x, r), (x - 3.0, r + 2.0)));
    p.push(line((x - 3.0, r - 2.0), (x - 3.0, r + 2.0)));
    p.push(text((x - 5.0, r + 3.0), km(t.range_m), Align::Right));
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(super) const FIELD: Field = Field { left: -80.0, top: -70.0, right: 80.0, bottom: 70.0 };

    #[test]
    fn real_view_fits_the_real_field_in_the_glass() {
        // The F-16's glass (cockpit.json HUD borders).
        let f = Field { left: -69.0, top: -75.0, right: 70.0, bottom: 60.0 };
        let k = Jet::F16.real_view_px_per_deg(f).unwrap();
        let (across, up) = Jet::F16.fov_deg().unwrap();
        assert!(k * across / 2.0 <= 69.0 && k * up / 2.0 <= 60.0, "the field overflows the glass");
        assert!(k * across / 2.0 > 68.9 || k * up / 2.0 > 59.9, "the field does not touch the glass");
        assert_eq!(Jet::F35.real_view_px_per_deg(f), None);
    }

    pub(super) fn texts(ps: &[Prim]) -> Vec<&str> {
        ps.iter()
            .filter_map(|p| match p {
                Prim::Text { text, .. } => Some(text.as_str()),
                _ => None,
            })
            .collect()
    }

    pub(super) fn input(jet: Jet) -> Input {
        Input {
            jet,
            kcas: 352.4,
            ground_kt: 380.0,
            tas_ms: 200.0,
            alt_ft: 10450.0,
            heading_deg: 333.0,
            mach: 0.85,
            g: 2.3,
            g_limit: 8.1,
            fuel_lbs: 5000.0,
            bingo_lbs: 1500.0,
            fpm: Some((0.0, 10.0)),
            horizon: (0.0, 10.0),
            px_per_deg: 12.0,
            steerpoint: Some(Steerpoint {
                number: 3,
                bearing_deg: 10.0,
                dist_m: 12.0 * NM,
                eta_s: Some(323.0),
                at: Some((30.0, 20.0)),
            }),
            ..Input::default()
        }
    }

    #[test]
    fn gps_cues_on_the_gps_jets() {
        use crate::gps::Lar;
        for jet in [Jet::F16, Jet::F15, Jet::F35, Jet::F15E] {
            let mut i = input(jet);
            i.weapons.hud_mode = 5;
            i.weapons.pipper = Some((-5.0, 30.0));
            let outside = Lar { range: 20_000.0, rmin: 2000.0, rmax: 12_000.0, in_range: false, tmr: Some(64.2) };
            i.weapons.gps = Some(GpsCue { pre: true, at: Some((20.0, 40.0)), lar: outside });
            let fr = RealHud::default().frame(FIELD, &i);
            let all: Vec<Prim> = fr.field.iter().chain(&fr.outer).cloned().collect();
            let t = texts(&all);
            assert!(t.contains(&"TMR 1:05") && !t.contains(&"IN RNG"), "{jet:?}: {t:?}");
            assert!(t.iter().any(|s| s.contains("PRE")), "{jet:?}: the mode {t:?}");
            assert!(!all.iter().any(|p| matches!(p, Prim::Dot { .. })), "{jet:?}: no CCIP pipper");
            // The steering line through the aim along the vertical (wings level), across the field.
            let asl = all
                .iter()
                .any(|p| matches!(p, Prim::Line { a, b } if a.0 == 20.0 && b.0 == 20.0 && a.1 < 0.0 && b.1 > 60.0));
            assert!(asl, "{jet:?}: the azimuth steering line");
            i.weapons.gps = Some(GpsCue {
                pre: false,
                at: Some((20.0, 40.0)),
                lar: Lar { range: 8000.0, in_range: true, tmr: None, ..outside },
            });
            let fr = RealHud::default().frame(FIELD, &i);
            let all: Vec<Prim> = fr.field.iter().chain(&fr.outer).cloned().collect();
            let t = texts(&all);
            assert!(t.contains(&"IN RNG") && t.iter().any(|s| s.contains("VIS")), "{jet:?}: {t:?}");
        }
    }

    #[test]
    fn the_helmet_display_is_dark_with_the_hmcs_off_or_the_goggles_down() {
        let mut i = Input { off_boresight: true, ..input(Jet::F16) };
        assert!(!RealHud::default().frame(FIELD, &i).outer.is_empty(), "the DASH's symbols");
        for (off, down) in [(true, false), (false, true)] {
            (i.helmet_off, i.goggles_down) = (off, down);
            let fr = RealHud::default().frame(FIELD, &i);
            assert!(fr.sight && fr.field.is_empty() && fr.outer.is_empty(), "HMCS off {off}, goggles down {down}");
        }
        // Looking ahead the HUD on the glass stays.
        i.off_boresight = false;
        assert!(!RealHud::default().frame(FIELD, &i).field.is_empty(), "the HUD with the goggles down");
    }

    #[test]
    fn tti_replaces_the_time_row_on_the_gps_jets() {
        for jet in [Jet::F16, Jet::F15, Jet::F35] {
            let mut i = input(jet);
            i.weapons.hud_mode = 0;
            i.weapons.tti = Some(41.3);
            for off in [false, true].into_iter().take(if jet == Jet::F35 { 2 } else { 1 }) {
                i.off_boresight = off;
                let fr = RealHud::default().frame(FIELD, &i);
                let all: Vec<Prim> = fr.field.iter().chain(&fr.outer).cloned().collect();
                let t = texts(&all);
                assert!(t.contains(&"TTI 0:42"), "{jet:?} {off}: {t:?}");
                assert!(
                    !t.iter().any(|s| s.contains("05:23") || s.contains("MIN")),
                    "{jet:?}: in the time's row {t:?}"
                );
            }
        }
    }

    /// The F-16's frames for fixed inputs in every mode, hashed: other jets' displays must leave them unchanged.
    /// A frame as the snapshot hashes it: what it draws (mrm_inside, a value for the shoot cue, left out).
    pub(super) fn snapshot(fr: &Frame) -> String {
        format!("{:?}", Frame { mrm_inside: None, ..fr.clone() }).replace(", mrm_inside: None", "")
    }

    fn f16_fingerprint() -> u64 {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        for mode in 0..=8 {
            for gear in [false, true] {
                let mut i = input(Jet::F16);
                i.gear_down = gear;
                i.weapons.hud_mode = mode;
                i.weapons.lcos = Some((5.0, 15.0));
                i.weapons.pipper = Some((-5.0, 30.0));
                i.weapons.seeker = Some((8.0, -4.0));
                i.weapons.steering = Some((3.0, 3.0));
                i.weapons.circle = 4.0;
                i.target = Some(Target {
                    range_m: 5000.0,
                    closure: 150.0,
                    at: Some((10.0, -5.0)),
                    aspect: Some(1.0),
                    ident: None,
                });
                i.dlz = Some(Dlz { max: 9000.0, min: 1500.0 });
                snapshot(&RealHud::default().frame(FIELD, &i)).hash(&mut h);
            }
        }
        h.finish()
    }

    #[test]
    fn mrm_inside_is_the_drawn_circle() {
        for jet in [Jet::F16, Jet::F15, Jet::F35, Jet::Lavi, Jet::Kurnass2000] {
            let mut i = input(jet);
            i.weapons.hud_mode = 2;
            i.weapons.circle = 5.0;
            let (c, r) = mrm_circle(&i).unwrap();
            i.weapons.steering = Some(c);
            assert_eq!(RealHud::default().frame(FIELD, &i).mrm_inside, Some(true), "{jet:?}: the dot on the centre");
            // The original's circle is on the HUD centre: a dot there is outside the F-16's ASEC (6° lower).
            i.weapons.steering = Some((c.0, c.1 - r * 1.2));
            assert_eq!(
                RealHud::default().frame(FIELD, &i).mrm_inside,
                Some(false),
                "{jet:?}: the dot above the circle"
            );
            i.weapons.steering = None;
            assert_eq!(RealHud::default().frame(FIELD, &i).mrm_inside, None, "{jet:?}: no dot");
        }
        let mut i = input(Jet::MiG29);
        i.weapons.hud_mode = 2;
        i.weapons.steering = Some((0.0, 0.0));
        assert_eq!(RealHud::default().frame(FIELD, &i).mrm_inside, None, "no fixed circle: the original's test");
    }

    #[test]
    fn the_f16_display_is_unchanged() {
        assert_eq!(f16_fingerprint(), 17_852_158_275_609_010_620, "the F-16 Real HUD changed");
    }

    #[test]
    fn cockpits_pick_their_display() {
        assert_eq!(Jet::of_cockpit("converted/cockpits/f15"), Jet::F15);
        assert_eq!(Jet::of_cockpit("f15e"), Jet::F15E);
        assert_eq!(Jet::of_cockpit("f35"), Jet::F35, "a definition's hud key");
        assert_eq!(Jet::of_cockpit("converted/cockpits/lavi"), Jet::Lavi);
        assert_eq!(Jet::of_cockpit("res://shared/extra/planes/f35i/cockpit"), Jet::F35);
        assert_eq!(Jet::of_cockpit("converted/cockpits/phantom"), Jet::Phantom);
        assert_eq!(Jet::of_cockpit("converted/cockpits/mirage"), Jet::Mirage);
        assert_eq!(Jet::of_cockpit("converted/cockpits/f4-2000"), Jet::Kurnass2000);
        assert_eq!(Jet::of_cockpit("converted/cockpits/cfir"), Jet::Kfir);
        assert_eq!(Jet::of_cockpit("converted/cockpits/mig23"), Jet::MiG23);
        assert_eq!(Jet::of_cockpit("converted/cockpits/mig29"), Jet::MiG29);
    }

    #[test]
    fn the_funnel_narrows_and_sags_with_range() {
        let mut p = Vec::new();
        let i = Input { g: 4.0, ..input(Jet::F16) };
        funnel(&mut p, &i, 3000.0);
        let lines: Vec<(P, P)> =
            p.iter().filter_map(|x| if let Prim::Line { a, b } = x { Some((*a, *b)) } else { None }).collect();
        let (near, far) = (lines[0].0, lines[lines.len() / 2 - 1].1);
        assert!(far.1 > near.1, "pulling 4 g: the far end of the funnel lower");
        assert!(far.0 > near.0, "the left line narrows toward the centre");
    }

    #[test]
    fn the_funnel_and_the_real_rounds_agree() {
        // Level 1 g at 250 m/s, 10,000 ft, wings level: at 1,000 m the funnel's centre sits where a Weapon data Real
        // round fired along the gun line passes, within the M61A1's 4 mrad dispersion (GD-OTS).
        use crate::gun::{Motion, real_time_of_flight};
        let i = Input { g: 1.0, tas_ms: 250.0, alt_ft: 10_000.0, roll_deg: 0.0, ..input(Jet::F16) };
        let r = 1000.0;
        let (c, _) = funnel_at(&i, r / FT, 1.0);
        let down_deg = (c.1 - i.gun_cross.1) / i.px_per_deg;
        let m = Motion { real_hits: true, velocity_jump: MUZZLE, ..Motion::default() };
        let p0 = crate::vec3::Vec3::new(0.0, 0.0, 10_000.0 * FT);
        let f = m.real_flight(0.0, p0, crate::vec3::Vec3::new(0.0, 250.0, 0.0), p0 + crate::vec3::Vec3::NORTH * 2781.0);
        let pos = m.position(&f, real_time_of_flight(f.s, r, f.k));
        let round_down_deg = ((p0.z - pos.z) / r).atan().to_degrees();
        assert!(round_down_deg > 0.3, "{round_down_deg}: the round falls");
        assert!((down_deg - round_down_deg).abs().to_radians() < 0.004, "funnel {down_deg} vs round {round_down_deg}");
    }

    #[test]
    fn aspect_triangle_clock() {
        let tip = |aspect: f64| {
            let mut p = Vec::new();
            aspect_triangle(&mut p, (0.0, 0.0), 10.0, aspect, 3.0);
            match p[0] {
                Prim::Line { a, .. } => a,
                _ => unreachable!(),
            }
        };
        let (x, y) = tip(0.0);
        assert!(x.abs() < 1e-9 && (y - 10.0).abs() < 1e-9, "tail: 6 o'clock");
        let (x, y) = tip(std::f64::consts::FRAC_PI_2);
        assert!((x - 10.0).abs() < 1e-9 && y.abs() < 1e-9, "left side: 3 o'clock");
    }

    #[test]
    fn edge_clamp() {
        let (p, lim) = FIELD.clamp_from((0.0, 0.0), (160.0, 0.0));
        assert!(lim && p == (80.0, 0.0));
    }
}

#[cfg(test)]
mod f16_snapshot {
    use super::tests::{FIELD, input, snapshot};
    use super::*;

    /// FNV-1a of the F-16's frames in every mode, gear up / down, with a target and a pipper: the Kfir / Lavi /
    /// Kurnass 2000 displays must leave it byte-identical.
    fn f16_frames_hash() -> u64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        for mode in 0..=8 {
            for gear in [false, true] {
                let mut i = input(Jet::F16);
                i.gear_down = gear;
                i.weapons.hud_mode = mode;
                i.weapons.seeker = Some((5.0, -4.0));
                i.weapons.lcos = Some((2.0, 18.0));
                i.weapons.pipper = Some((-3.0, 30.0));
                i.target = Some(Target {
                    range_m: 3000.0,
                    closure: 120.0,
                    at: Some((10.0, -8.0)),
                    aspect: Some(0.5),
                    ident: None,
                });
                i.dlz = Some(Dlz { max: 9000.0, min: 900.0 });
                for b in snapshot(&RealHud::default().frame(FIELD, &i)).bytes() {
                    h = (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3);
                }
            }
        }
        // The delayed CCIP before and after designation.
        for designated in [false, true] {
            let mut i = input(Jet::F16);
            i.weapons.hud_mode = 5;
            i.weapons.pipper = Some((-3.0, 130.0));
            i.weapons.delay = Some(Delay { ttg: 6.0, target: Some((-2.0, 60.0)), designated });
            for b in snapshot(&RealHud::default().frame(FIELD, &i)).bytes() {
                h = (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3);
            }
        }
        h
    }

    #[test]
    fn mrm_inside_is_the_drawn_circle() {
        for jet in [Jet::F16, Jet::F15, Jet::F35, Jet::Lavi, Jet::Kurnass2000] {
            let mut i = input(jet);
            i.weapons.hud_mode = 2;
            i.weapons.circle = 5.0;
            let (c, r) = mrm_circle(&i).unwrap();
            i.weapons.steering = Some(c);
            assert_eq!(RealHud::default().frame(FIELD, &i).mrm_inside, Some(true), "{jet:?}: the dot on the centre");
            // The original's circle is on the HUD centre: a dot there is outside the F-16's ASEC (6° lower).
            i.weapons.steering = Some((c.0, c.1 - r * 1.2));
            assert_eq!(
                RealHud::default().frame(FIELD, &i).mrm_inside,
                Some(false),
                "{jet:?}: the dot above the circle"
            );
            i.weapons.steering = None;
            assert_eq!(RealHud::default().frame(FIELD, &i).mrm_inside, None, "{jet:?}: no dot");
        }
        let mut i = input(Jet::MiG29);
        i.weapons.hud_mode = 2;
        i.weapons.steering = Some((0.0, 0.0));
        assert_eq!(RealHud::default().frame(FIELD, &i).mrm_inside, None, "no fixed circle: the original's test");
    }

    #[test]
    fn the_f16_display_is_unchanged() {
        assert_eq!(f16_frames_hash(), 14_087_280_463_823_746_070, "F-16 frames hash");
    }
}
