//! "Original 1998" vs "real" data sets.
//!
//! The original numbers are what Jane's IAF shipped (v1.1 files when present, `crate::read_md`). The
//! real set replaces, per aircraft type (the flyable jets and the AI types, [`TYPES`]), the items the
//! validation suite (`tests/validation.rs`) checks against public data; the per-aircraft sources and
//! choices are in docs/real-aircraft.md. Anything a row leaves as `None` keeps the original value.
//! Several AI types share one original section (`[TU22]` flies the Su-22, Su-24, Tu-22 and A-4; the
//! transports keep the F-16's data): each type still gets its own real row.

use crate::aircraft::G;
use crate::params::{NoseWheel, FT};
use crate::{Envelope, Params};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DataSet {
    #[default]
    Original,
    Real,
}

const LB: f32 = 0.45359;
const KT: f32 = 0.514722;

/// How the real set changes the thrust table (lbf, 2 Mach × 2 altitude corners, `Params::thrust`).
#[derive(Debug, Clone, Copy)]
enum Thrust {
    /// Multiply every corner.
    Scale(f32),
    /// Scale every corner so the sea-level static full-AB value becomes this (lbf).
    StaticAb(f32),
}

/// Rudder-pedal nose-wheel steering geometry: max wheel angle (deg), wheelbase (ft), tyre side grip (g).
#[derive(Debug, Clone, Copy)]
struct Nws {
    angle_deg: f32,
    wheelbase_ft: f32,
    grip_g: f32,
}

/// An aircraft type the missions can place: its name (the key of the real row, `IAF_JET` and
/// [`crate::load_with`]), 3D model folder, the bd.ibx section the original loads for it and its type
/// code `veh+0xc54` (both from `FUN_005a5bb0`, v1.1 `5a8980`: types 230 / 240, the transports, load no
/// section and keep the F-16's parameters). Helicopters (type −1) have no section and no row.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Type {
    pub name: &'static str,
    pub model: &'static str,
    pub section: &'static str,
    pub type_code: u32,
}

const fn ty(name: &'static str, model: &'static str, section: &'static str, type_code: u32) -> Type {
    Type { name, model, section, type_code }
}

/// Every flown aircraft type. The first type of a section is the one a bare section name selects.
pub const TYPES: &[Type] = &[
    ty("F-16", "f16", "F-16", 100),
    ty("F-15", "f15", "F-15", 110),
    // The Kurnass 2000 (type 200) loads the same section; one row serves both
    // (docs/real-aircraft.md §4).
    ty("F-4", "f42000", "F-4", 120),
    ty("KFIR", "cfir", "KFIR", 130),
    ty("LAVI", "lavi", "LAVI", 140),
    // Not in the original: no section of its own, so it always flies its Real row (on the F-16's block;
    // docs/adding-a-plane.md §3, docs/f35i.md).
    ty("F-35I", "f35i", "F-16", 1000),
    ty("MIRAGE", "mirage", "MIRAGE", 190),
    ty("MIG21", "mig21", "MIG21", 150),
    ty("MIG23", "mig23", "MIG23", 160),
    ty("MIG25", "mig25", "MIG25", 170),
    ty("MIG29", "mig29", "MIG29", 180),
    ty("MIG17", "mig17", "MIG17", 210),
    ty("TU22", "tu22", "TU22", 220),
    ty("SU22", "su22", "TU22", 220),
    ty("SU24", "su24", "TU22", 220),
    ty("A-4", "a4", "TU22", 220),
    ty("C-130", "c130", "F-16", 230),
    ty("707", "boing", "F-16", 230),
    ty("IL-76", "il76", "F-16", 230),
];

/// Types the original never had: no Original data, so they always fly their Real row.
const NO_ORIGINAL: &[&str] = &["F-35I"];

/// The data set a type flies with: `set`, except that a type without original data always takes Real.
pub fn effective(set: DataSet, name: &str) -> DataSet {
    match find_type(name) {
        Some(t) if NO_ORIGINAL.contains(&t.name) => DataSet::Real,
        _ => set,
    }
}

/// The type for a type name, model folder or (first type of) a bd.ibx section, case-insensitive.
pub fn find_type(name: &str) -> Option<&'static Type> {
    let eq = |a: &str| a.eq_ignore_ascii_case(name);
    TYPES.iter().find(|t| eq(t.name) || eq(t.model)).or_else(|| TYPES.iter().find(|t| eq(t.section)))
}

/// The bd.ibx section `name` (see [`find_type`]) loads in `set`: the original's section, or the real
/// row's `base` section. An unknown name is taken as a section.
pub fn section(set: DataSet, name: &str) -> &str {
    let Some(t) = find_type(name) else { return name };
    match (set, real(t)) {
        (DataSet::Real, Some(Real { base: Some(b), .. })) => b,
        _ => t.section,
    }
}

/// The original's FM parameter blocks (`FUN_005a8980`: type → block, `FUN_005b2940` reads the section into it only
/// while its counter +0x17c is 0) are statics built once at program start (`FUN_005a2fa0`, a C++ static
/// initializer): each is read on the first use in a game session and kept. The Kfir (130) and the Mirage (190) share
/// one (`0x8442d4`), so the one that flies second in a session (the player's or an AI's, any mission) flies on the
/// first one's section until the game exits. `Blocks` is that session state; the Real set gives each its own.
#[derive(Debug, Default)]
pub struct Blocks {
    shared: Option<&'static str>,
}

/// The sections that share one block.
const SHARED_BLOCK: [&str; 2] = ["KFIR", "MIRAGE"];

impl Blocks {
    pub const fn new() -> Self {
        Blocks { shared: None }
    }

    /// [`section`] for `name` in `set` this session: with the original set the shared block keeps the section
    /// it was first read from.
    pub fn section<'a>(&mut self, set: DataSet, name: &'a str) -> &'a str {
        let s = section(set, name);
        match SHARED_BLOCK.iter().find(|b| b.eq_ignore_ascii_case(s)) {
            Some(b) if set == DataSet::Original => self.shared.get_or_insert(b),
            _ => s,
        }
    }
}

fn real(t: &Type) -> Option<&'static Real> {
    REAL.iter().find(|r| r.aircraft == t.name)
}

/// One aircraft type's real-world values (public data, docs/real-aircraft.md).
#[derive(Debug, Clone, Copy)]
struct Real {
    /// [`Type::name`].
    aircraft: &'static str,
    /// Section the real set starts from instead of the original's (the original has one written for
    /// the type but never loads it: `[SU24]`, and `[C130]` for the transports, which otherwise fly the
    /// F-16's data). Fields the row leaves out come from this section.
    base: Option<&'static str>,
    empty_lb: f32,
    /// Internal fuel.
    fuel_lb: Option<f32>,
    /// Max take-off weight (MaxWeight: the lift-ramp limits, MaxWeight · (MinG − 1 .. MaxG − 1) · g).
    max_lb: Option<f32>,
    thrust: Thrust,
    /// Extra factor on the high-altitude corners (20 km) of the thrust table: the original's linear
    /// altitude lapse is tuned with it to the published max speed at altitude.
    alt_thrust: Option<f32>,
    /// Sea-level static military / max-AB thrust ratio (the original's curve gives 0.6).
    mil_ratio: Option<f32>,
    /// Wing area, ft² (WingArea: lift / α and drag reference).
    wing_ft2: Option<f32>,
    /// Transonic drag rise ΔCD (Mach 0.9 → 1.2), tuned to the published max level speeds.
    wave_drag: f32,
    /// Clean drag coefficient (replaces PlaneDragIndex × 1e-4).
    cd0: Option<f32>,
    roll_deg_s: Option<f32>,
    /// Roll start / stop acceleration (deg/s²).
    roll_accel: Option<(f32, f32)>,
    /// Fuel flow at full AB, lb/s (`FuelFlowAtMaxThrust`).
    ff_ab_lb_s: Option<f32>,
    /// Fuel flow at military power, lb/h (sets the dry fraction; the original's is 0.25).
    ff_mil_lb_h: Option<f32>,
    /// 1 g stall speed at sea level (kt TAS), `Envelope::stall_floor`. A floor: it only raises the
    /// envelope's own minimum speed.
    stall_kt: Option<f32>,
    /// Max / min load factor (MaxG, MinG).
    g: Option<(f32, f32)>,
    /// Service ceiling, ft: the envelope's altitudes are scaled so that its 1 g ceiling is this
    /// (`Envelope::with_ceiling`).
    ceiling_ft: Option<f32>,
    /// Drag chute: canopy area m² and drag coefficient (`Params::chute_cd` = cd · area / wing area). The
    /// original's chute is visual only.
    chute: Option<(f32, f32)>,
    nose_wheel: Option<Nws>,
    /// Some(false): no afterburner (`HasAfterBurner = 0`: full throttle is the rated dry thrust).
    afterburner: Option<bool>,
}

const NONE: Real = Real {
    aircraft: "",
    base: None,
    empty_lb: 0.0,
    fuel_lb: None,
    max_lb: None,
    thrust: Thrust::Scale(1.0),
    alt_thrust: None,
    mil_ratio: None,
    wing_ft2: None,
    wave_drag: 0.0,
    cd0: None,
    roll_deg_s: None,
    roll_accel: None,
    ff_ab_lb_s: None,
    ff_mil_lb_h: None,
    stall_kt: None,
    g: None,
    ceiling_ft: None,
    chute: None,
    nose_wheel: None,
    afterburner: None,
};


const REAL: &[Real] = &[
    // F-16C Block 30/40 with F110-GE-100 (public figures, approximate).
    Real {
        aircraft: "F-16",
        empty_lb: 19_000.0,
        // 19,330 lbf full AB in the original → ~29,000 lbf (F110-GE-100 SL static): scale the whole table.
        thrust: Thrust::Scale(1.5),
        // No transonic drag rise in the original: tuned to Mach 1.2 at SL / ~1.9 at 40k ft.
        wave_drag: 0.02,
        // FLCS roll response: time constant ~0.3 s → ~900 deg/s² to start and stop the roll
        // (the original stops at 170 deg/s², overshooting ~1 s after the stick is centred).
        roll_deg_s: Some(280.0),
        roll_accel: Some((900.0, 900.0)),
        // ~60,000 lb/h at full AB; the original's ×0.25 below AB then gives ~11,000 lb/h at military.
        ff_ab_lb_s: Some(16.5),
        // 1 g stall ~118 kt instead of 86 kt: with Vmin ∝ √g this puts 9 g at ~355 kt,
        // matching the published ~330-350 kt corner speed.
        stall_kt: Some(118.0),
        // Nose-wheel steering through the rudder pedals, ±32° (low-gain / taxi NWS), wheelbase
        // 13.2 ft; side grip ~0.3 g (approximate). The original instead turns at stick · V · 20°/s / 145 kt.
        nose_wheel: Some(Nws { angle_deg: 32.0, wheelbase_ft: 13.2, grip_g: 0.3 }),
        // Service ceiling: USAF F-16 fact sheet: ceiling above 50,000 ft.
        ceiling_ft: Some(50_000.0),
        ..NONE
    },
    // F-15C Baz, 2 x F100-PW-220: USAF Standard Aircraft Characteristics (SAC) chart, Feb 1992.
    Real {
        aircraft: "F-15",
        empty_lb: 28_476.0,
        fuel_lb: Some(13_455.0),
        thrust: Thrust::StaticAb(46_900.0),
        mil_ratio: Some(28_740.0 / 46_900.0),
        // Fit: Mach 1.22 at SL, Mach 2.16 at 40k ft when the internal fuel runs out (SAC: ~800 KCAS at
        // SL, 1,309 kt / Mach 2.28 at 35k ft).
        alt_thrust: Some(2.4),
        cd0: Some(0.040),
        wave_drag: 0.016,
        // Military: TSFC 0.73 → ~21,000 lb/h; max AB ~2.1 (uncertain) → ~98,000 lb/h.
        ff_ab_lb_s: Some(98_000.0 / 3600.0),
        ff_mil_lb_h: Some(21_000.0),
        // SAC: power-off stall, flaps up, 135 kt at 45,713 lb → ~130 kt at full internal fuel (41,900 lb).
        stall_kt: Some(130.0),
        // NWS ±45° in manoeuvre mode (±15° normal); wheelbase 17.78 ft (SAC).
        nose_wheel: Some(Nws { angle_deg: 45.0, wheelbase_ft: 17.78, grip_g: 0.3 }),
        // Service ceiling: USAF F-15 fact sheet: 65,000 ft.
        ceiling_ft: Some(65_000.0),
        ..NONE
    },
    // F-4E Kurnass, 2 x J79-GE-17 (the Kurnass 2000 kept the engines and airframe: same row).
    Real {
        aircraft: "F-4",
        empty_lb: 30_330.0,
        fuel_lb: Some(12_060.0),
        thrust: Thrust::StaticAb(35_800.0),
        mil_ratio: Some(23_740.0 / 35_800.0),
        // Fit: Mach 1.18 at SL, Mach 2.16 at 40k ft (published: ~750 KIAS placard, Mach 2.17 at 36k ft).
        alt_thrust: Some(1.9),
        cd0: Some(0.037),
        wave_drag: 0.010,
        // No public figure: 120-180 deg/s quoted at 350-450 kt (uncertain); the original's 80 is far too low.
        roll_deg_s: Some(150.0),
        // TSFC ~0.85 dry / ~1.98 AB.
        ff_ab_lb_s: Some(71_000.0 / 3600.0),
        ff_mil_lb_h: Some(20_000.0),
        // T.O. 1F-4E-1: +7.33 g (at ≤37,500 lb) / −3 g.
        g: Some((7.33, -3.0)),
        // NWS ±70° (button, below ~70 kt); wheelbase ~23.3 ft (uncertain).
        nose_wheel: Some(Nws { angle_deg: 70.0, wheelbase_ft: 23.3, grip_g: 0.3 }),
        // Service ceiling: F-4E: 58,750 ft at maximum power, 100 ft/min (airfighters.com, SAC figure).
        ceiling_ft: Some(58_750.0),
        // 16 ft ring-slot deceleration chute (Mills Manufacturing; 4 slot rings), CD ~0.63 (ring-slot brake
        // chutes 0.56-0.65); deployed below 200 KIAS (T.O. limit, Heatblur manual).
        chute: Some((std::f32::consts::PI * (8.0 * FT) * (8.0 * FT), 0.63)),
        ..NONE
    },
    // IAI Lavi (production design figures, Jane's 1987-88) with the PW1120.
    Real {
        aircraft: "LAVI",
        empty_lb: 15_500.0,
        fuel_lb: Some(6_000.0),
        thrust: Thrust::StaticAb(20_600.0),
        mil_ratio: Some(13_550.0 / 20_600.0),
        // Fit (not public data): Mach 1.16 at SL, Mach 1.85 at 40k ft (published: 1.85 at 36k ft).
        alt_thrust: Some(1.4),
        cd0: Some(0.028),
        wave_drag: 0.018,
        // TSFC 1.86 at max AB (~38,200 lb/h) and 0.80 dry (~10,800 lb/h).
        ff_ab_lb_s: Some(38_200.0 / 3600.0),
        ff_mil_lb_h: Some(10_800.0),
        // Lowest speed flown in the flight tests (the FBW's AoA limit, like the F-16's 118 kt).
        stall_kt: Some(110.0),
        // Wheelbase 12.66 ft (Jane's); the steering angle is not public: the F-16's ±32° as a stand-in.
        nose_wheel: Some(Nws { angle_deg: 32.0, wheelbase_ft: 12.66, grip_g: 0.3 }),
        // Service ceiling: Design figure, 15,240 m (Jewish Virtual Library, Wikipedia; the prototypes flew too little to confirm it).
        ceiling_ft: Some(50_000.0),
        ..NONE
    },
    // Kfir C7 (IAI J79-J1E, licence-built J79-GE-17), Jane's.
    Real {
        aircraft: "KFIR",
        empty_lb: 16_060.0,
        fuel_lb: Some(5_670.0),
        // 17,900 lbf max AB (the C7's 18,750 lbf "combat plus" is a temporary overboost).
        thrust: Thrust::StaticAb(17_900.0),
        mil_ratio: Some(11_870.0 / 17_900.0),
        wing_ft2: Some(375.0),
        // Fit: Mach 1.16 at SL, Mach 2.0 at 40k ft (published: 1.13 SL, 2.0 sustained / 2.3 dash).
        alt_thrust: Some(1.7),
        cd0: Some(0.020),
        wave_drag: 0.012,
        // TSFC 1.965 at max AB, 0.84 dry.
        ff_ab_lb_s: Some(35_200.0 / 3600.0),
        ff_mil_lb_h: Some(9_970.0),
        // Approach ~165 kt (estimate) / 1.3.
        stall_kt: Some(127.0),
        g: Some((7.5, -3.5)),
        nose_wheel: Some(Nws { angle_deg: 30.0, wheelbase_ft: 15.96, grip_g: 0.3 }),
        // Service ceiling: Kfir C7: above 17,680 m / 58,000 ft (milavia.net).
        ceiling_ft: Some(58_000.0),
        ..NONE
    },
    // Mirage IIICJ Shahak (SNECMA Atar 09C), jet only (no SEPR rocket).
    Real {
        aircraft: "MIRAGE",
        empty_lb: 13_000.0,
        fuel_lb: Some(4_800.0),
        thrust: Thrust::StaticAb(13_228.0),
        mil_ratio: Some(9_436.0 / 13_228.0),
        wing_ft2: Some(375.0),
        // Fit: Mach 1.15 at SL, Mach 2.0 at 40k ft (published: 1.1-1.14 SL, 2.1-2.2 at 39k ft).
        alt_thrust: Some(2.0),
        cd0: Some(0.015),
        wave_drag: 0.010,
        // TSFC 2.03 at max AB, 1.01 dry.
        ff_ab_lb_s: Some(26_900.0 / 3600.0),
        ff_mil_lb_h: Some(9_500.0),
        // Approach ~180 kt / 1.3 (no flaps; Dassault 170 kt, pilots 185 kt).
        stall_kt: Some(140.0),
        nose_wheel: Some(Nws { angle_deg: 30.0, wheelbase_ft: 15.96, grip_g: 0.3 }),
        // Service ceiling: Mirage IIICJ: 17,000 m (flugzeuginfo.net, Jewish Virtual Library).
        ceiling_ft: Some(55_770.0),
        ..NONE
    },
    // F-35I Adir (F-35A airframe, F135-PW-100): Lockheed Martin F-35A brochure, Wikipedia (docs/f35i.md §2).
    Real {
        aircraft: "F-35I",
        base: Some("F-16"),
        empty_lb: 29_300.0,
        fuel_lb: Some(18_250.0),
        max_lb: Some(65_918.0),
        // F135 uninstalled: 28,000 lbf military, 43,000 lbf afterburner.
        thrust: Thrust::StaticAb(43_000.0),
        mil_ratio: Some(28_000.0 / 43_000.0),
        wing_ft2: Some(460.0),
        // Fit: 708 kt (Mach 1.07) at SL, Mach 1.58 at 40k ft (published 700 kt / Mach 1.6).
        alt_thrust: Some(1.4),
        cd0: Some(0.05),
        wave_drag: 0.06,
        // TSFC ~2.0 in afterburner (~86,000 lb/h), ~0.8 dry (~22,000 lb/h) (U).
        ff_ab_lb_s: Some(86_000.0 / 3600.0),
        ff_mil_lb_h: Some(22_000.0),
        // Approach ~150 kt at 13° AoA -> 1 g stall ~122 kt (U, derived).
        stall_kt: Some(122.0),
        // FLCS like the F-16's (no public F-35 roll rate).
        roll_deg_s: Some(280.0),
        roll_accel: Some((900.0, 900.0)),
        g: Some((9.0, -3.0)),
        ceiling_ft: Some(50_000.0),
        nose_wheel: Some(Nws { angle_deg: 32.0, wheelbase_ft: 17.6, grip_g: 0.3 }),
        afterburner: Some(true),
        ..NONE
    },
    // --- AI types (docs/real-aircraft.md §9). No public roll rate was found for any of them: the
    // original's is kept. "Jane's" = the Jane's 1997 extracts the game ships (resource/ref).
    // MiG-21MF (R-13-300), Egypt / Syria / Iraq 1970s-90s: Jane's, airwar.ru, leteckemotory.cz.
    Real {
        aircraft: "MIG21",
        empty_lb: 12_882.0,
        // 2,600 l (about 1,800 l usable at low speed within CG limits).
        fuel_lb: Some(4_586.0),
        max_lb: Some(21_605.0),
        thrust: Thrust::StaticAb(14_550.0),
        mil_ratio: Some(9_340.0 / 14_550.0),
        // Fit: Mach 1.06 at SL, Mach 2.05 above 36k ft.
        alt_thrust: Some(3.17),
        cd0: Some(0.039),
        wave_drag: 0.012,
        // TSFC 2.25 at full AB, 0.96 dry.
        ff_ab_lb_s: Some(32_700.0 / 3600.0),
        ff_mil_lb_h: Some(8_970.0),
        // Landing speed 146 kt (Jane's) / 1.1.
        stall_kt: Some(133.0),
        g: Some((8.5, -3.0)),
        // Service ceiling: MiG-21MF: 18,200 m (airwar.ru).
        ceiling_ft: Some(59_710.0),
        ..NONE
    },
    // MiG-23ML (R-35-300), Syria / Iraq / Libya: Jane's, airwar.ru, leteckemotory.cz, Wikipedia.
    Real {
        aircraft: "MIG23",
        empty_lb: 22_500.0,
        fuel_lb: Some(7_496.0),
        max_lb: Some(39_242.0),
        thrust: Thrust::StaticAb(28_660.0),
        mil_ratio: Some(18_850.0 / 28_660.0),
        // Fit: Mach 1.14 at SL, Mach 2.35 at altitude (72° sweep; the model has no sweep).
        alt_thrust: Some(4.54),
        cd0: Some(0.041),
        wave_drag: 0.008,
        // TSFC 1.94 at full AB, 0.92 dry.
        ff_ab_lb_s: Some(55_600.0 / 3600.0),
        ff_mil_lb_h: Some(17_340.0),
        // Landing 140-151 kt / 1.1.
        stall_kt: Some(132.0),
        // +8.5 below Mach 0.85 (+7.5 above); negative limit not public (original kept).
        g: Some((8.5, -3.0)),
        // Service ceiling: MiG-23ML: 18,500 m (victorymuseum.ru).
        ceiling_ft: Some(60_700.0),
        ..NONE
    },
    // MiG-25PD (2 x R-15BD-300), Syria / Iraq / Libya: Jane's, Gordon via ru.wikipedia, airwar.ru.
    Real {
        aircraft: "MIG25",
        empty_lb: 41_450.0,
        fuel_lb: Some(32_120.0),
        max_lb: Some(90_390.0),
        thrust: Thrust::StaticAb(2.0 * 24_690.0),
        // Dry 16,535 lbf per engine (Gordon); Jane's gives 19,400 (U).
        mil_ratio: Some(16_535.0 / 24_690.0),
        wing_ft2: Some(666.0),
        // Fit: ~647 kt (Mach 0.98, the SL limit), Mach 2.83 at 42,650 ft.
        alt_thrust: Some(12.4),
        cd0: Some(0.0585),
        wave_drag: 0.0,
        // TSFC 2.70 at full AB; dry ~1.25 (U).
        ff_ab_lb_s: Some(133_300.0 / 3600.0),
        ff_mil_lb_h: Some(41_300.0),
        // Landing 146-157 kt / 1.1.
        stall_kt: Some(137.0),
        // PD +5 (P +4.5, aileron reversal); negative not public (original kept).
        g: Some((5.0, -2.0)),
        // Service ceiling: MiG-25PD: 20,700 m (airwar.ru).
        ceiling_ft: Some(67_910.0),
        ..NONE
    },
    // MiG-29 9.12 (2 x RD-33), Syria / Iraq: Jane's, airwar.ru, ru.wikipedia.
    Real {
        aircraft: "MIG29",
        empty_lb: 24_030.0,
        // 4,300 l (4,200-4,365 l in the sources).
        fuel_lb: Some(7_720.0),
        max_lb: Some(40_785.0),
        thrust: Thrust::StaticAb(2.0 * 18_300.0),
        mil_ratio: Some(11_110.0 / 18_300.0),
        wing_ft2: Some(410.0),
        // Fit: Mach 1.2 at SL (700-810 kt in the sources), Mach 2.3 at 11 km.
        alt_thrust: Some(3.0),
        cd0: Some(0.057),
        wave_drag: 0.015,
        // TSFC 2.05 at full AB, 0.77 dry.
        ff_ab_lb_s: Some(75_000.0 / 3600.0),
        ff_mil_lb_h: Some(17_100.0),
        // Landing 127 kt / 1.1.
        stall_kt: Some(115.0),
        // Service ceiling: MiG-29 9.12: 18,000 m (ru.wikipedia, Russian MoD).
        ceiling_ft: Some(59_060.0),
        ..NONE
    },
    // MiG-17F (VK-1F), Egypt / Syria 1967-73: Jane's, Wikipedia, airwar.ru, leteckemotory.cz.
    Real {
        aircraft: "MIG17",
        empty_lb: 8_664.0,
        // 1,410 l.
        fuel_lb: Some(2_487.0),
        max_lb: Some(13_380.0),
        thrust: Thrust::StaticAb(7_450.0),
        mil_ratio: Some(5_730.0 / 7_450.0),
        // Fit: 594 kt at SL, 617 kt at ~10k ft (subsonic in level flight).
        alt_thrust: Some(1.2),
        cd0: Some(0.0356),
        wave_drag: 0.02,
        // TSFC 2.61 at full AB; dry 1.07 (VK-1; 1.56 in another sheet, U).
        ff_ab_lb_s: Some(19_400.0 / 3600.0),
        ff_mil_lb_h: Some(6_100.0),
        g: Some((8.0, -1.0)),
        // Service ceiling: MiG-17F: 16,600 m (airwar.ru).
        ceiling_ft: Some(54_460.0),
        ..NONE
    },
    // Su-22M4 (AL-21F-3), Syria / Iraq / Libya (the Su-22M3 had the R-29BS-300): Jane's, ru.wikipedia.
    // The original flies it with the Tu-22's section.
    Real {
        aircraft: "SU22",
        empty_lb: 26_810.0,
        // 4,550 l.
        fuel_lb: Some(8_311.0),
        max_lb: Some(42_836.0),
        thrust: Thrust::StaticAb(24_700.0),
        mil_ratio: Some(17_200.0 / 24_700.0),
        // 30° sweep.
        wing_ft2: Some(414.0),
        // Fit: Mach 1.13 at SL, Mach 1.7 at altitude.
        alt_thrust: Some(0.66),
        cd0: Some(0.0374),
        wave_drag: 0.015,
        // TSFC 1.86 at full AB, 0.86 dry.
        ff_ab_lb_s: Some(45_900.0 / 3600.0),
        ff_mil_lb_h: Some(14_800.0),
        // Landing 154 kt at max landing weight / 1.1.
        stall_kt: Some(140.0),
        // +7; negative not public (original kept).
        g: Some((7.0, -2.0)),
        // Service ceiling: Su-22M4: 14,200 m (ru.wikipedia; Su-17M4 15,200 m).
        ceiling_ft: Some(46_590.0),
        ..NONE
    },
    // Su-24MK (2 x AL-21F-3A), Libya / Syria / Iraq: Jane's, Sukhoi MK brochure via globalsecurity,
    // ru.wikipedia, airwar.ru. Starts from the original's own [SU24] section (unused by the original).
    Real {
        aircraft: "SU24",
        base: Some("SU24"),
        empty_lb: 49_160.0,
        fuel_lb: Some(21_600.0),
        max_lb: Some(87_520.0),
        thrust: Thrust::StaticAb(2.0 * 24_690.0),
        mil_ratio: Some(17_200.0 / 24_690.0),
        // 16° sweep.
        wing_ft2: Some(594.0),
        // Fit: Mach 1.07 at SL, Mach 1.5 at 40k ft (1.35 in the MK brochure, 1.6 for the Su-24M).
        cd0: Some(0.03),
        wave_drag: 0.045,
        ff_ab_lb_s: Some(91_800.0 / 3600.0),
        ff_mil_lb_h: Some(29_600.0),
        // Stall 151 kt, flaps and gear down (Jane's).
        stall_kt: Some(151.0),
        g: Some((6.0, -2.0)),
        // Service ceiling: Su-24M / MK: 11,000 m (Russian MoD).
        ceiling_ft: Some(36_090.0),
        ..NONE
    },
    // Tu-22M3 Backfire-C (2 x NK-25): the game's model and reference card are the Backfire (the
    // original's numbers are closer to the Tu-22 Blinder that Libya and Iraq flew; docs/real-aircraft.md §9).
    Real {
        aircraft: "TU22",
        // 58-78 t in the sources (U).
        empty_lb: 149_910.0,
        fuel_lb: Some(118_060.0),
        max_lb: Some(277_780.0),
        thrust: Thrust::StaticAb(2.0 * 55_120.0),
        mil_ratio: Some(31_970.0 / 55_120.0),
        // 20° sweep.
        wing_ft2: Some(1_976.0),
        // Fit: Mach 0.86 at SL, Mach 1.88 at altitude (Jane's; 2,300 km/h in Russian sources).
        alt_thrust: Some(6.6),
        cd0: Some(0.0714),
        wave_drag: 0.01,
        // SFC ~2.1 at full AB (U), 0.76 cruise.
        ff_ab_lb_s: Some(231_500.0 / 3600.0),
        ff_mil_lb_h: Some(48_600.0),
        // Landing 154-165 kt at 78-88 t / 1.1 (U).
        stall_kt: Some(140.0),
        g: Some((2.5, -2.0)),
        // Service ceiling: Tu-22M3: 13,300 m (Great Russian Encyclopedia, RIA).
        ceiling_ft: Some(43_640.0),
        ..NONE
    },
    // A-4N Ayit (J52-P-408A), Israeli (the missions place the A-4 on the Israeli side): Jane's (A-4M),
    // A-4M SAC / NATOPS as quoted, FAS. Flown by the original with the Tu-22's section.
    Real {
        aircraft: "A-4",
        empty_lb: 10_800.0,
        // 800 US gal JP-5.
        fuel_lb: Some(5_440.0),
        max_lb: Some(24_500.0),
        thrust: Thrust::StaticAb(11_200.0),
        afterburner: Some(false),
        wing_ft2: Some(260.0),
        // Fit: 597 kt clean at SL (A-4M; the IAI extended tailpipe's loss is not public). Subsonic
        // airframe: the wave drag stands in for its drag rise (Mach 0.96 at 40k ft), and the
        // Tu-22 section's high-altitude thrust is halved.
        alt_thrust: Some(0.5),
        cd0: Some(0.05),
        wave_drag: 0.3,
        // TSFC 0.79.
        ff_ab_lb_s: Some(8_850.0 / 3600.0),
        // A-4E stall 121 kt (U, weight not given).
        stall_kt: Some(121.0),
        // +8 / -3 (U).
        g: Some((8.0, -3.0)),
        // Service ceiling: A-4N: 42,250 ft (airfighters.com) (U).
        ceiling_ft: Some(42_250.0),
        ..NONE
    },
    // C-130H Karnaf (4 x T56-A-15). The original flies the transports with the F-16's data; the real set
    // starts from its unused [C130] section (no afterburner). USAF fact sheet, Jane's.
    Real {
        aircraft: "C-130",
        base: Some("C130"),
        empty_lb: 75_800.0,
        fuel_lb: Some(46_600.0),
        max_lb: Some(155_000.0),
        // Propeller static thrust ~10,600-11,500 lbf per engine (derived, U).
        thrust: Thrust::StaticAb(4.0 * 11_000.0),
        // Fit: 320 kt at 20,000 ft.
        cd0: Some(0.114),
        // 4 x 4,508 shp at ~0.5 lb/shp/h (U).
        ff_ab_lb_s: Some(9_000.0 / 3600.0),
        // 100 kt at max normal take-off weight (Jane's).
        stall_kt: Some(100.0),
        // 14 CFR 25.337 minimum (the C-130's own limit not found, U).
        g: Some((2.5, -1.0)),
        // Service ceiling: C-130H light (FAS, Lockheed: 33,000 ft; 23,000 ft at the max 42,000 lb payload, USAF fact sheet) — the game's C-130s fly at empty + fuel.
        ceiling_ft: Some(33_000.0),
        ..NONE
    },
    // Boeing 707-320C Re'em (4 x JT3D-7): Jane's, Jenkinson. Starts from [C130].
    Real {
        aircraft: "707",
        base: Some("C130"),
        empty_lb: 146_000.0,
        fuel_lb: Some(159_800.0),
        max_lb: Some(333_600.0),
        thrust: Thrust::StaticAb(4.0 * 19_000.0),
        wing_ft2: Some(3_050.0),
        // Fit: 545 kt max level speed (Jane's) at 25,000 ft (altitude not given, U).
        cd0: Some(0.0456),
        wave_drag: 0.02,
        // Approach 135 kt at max landing weight / 1.3.
        stall_kt: Some(104.0),
        g: Some((2.5, -1.0)),
        // Service ceiling: 707-320C: 42,000 ft max operating altitude (flugzeuginfo.net, Wikipedia).
        ceiling_ft: Some(42_000.0),
        ..NONE
    },
    // Il-76MD (4 x D-30KP), Syria / Iraq / Libya: airwar.ru, ru.wikipedia, Jane's. Starts from [C130].
    Real {
        aircraft: "IL-76",
        base: Some("C130"),
        // 89-92 t (U).
        empty_lb: 196_200.0,
        fuel_lb: Some(187_040.0),
        max_lb: Some(418_880.0),
        thrust: Thrust::StaticAb(4.0 * 26_455.0),
        wing_ft2: Some(3_229.0),
        // Fit: 459 kt (850 km/h, airwar; U) at 30,000 ft.
        cd0: Some(0.0834),
        wave_drag: 0.0,
        g: Some((2.5, -1.0)),
        // Service ceiling: Il-76MD: 12,000 m (airwar.ru).
        ceiling_ft: Some(39_370.0),
        ..NONE
    },
];

/// Applies the real-world values for aircraft `name` ([`find_type`]) to the data loaded from
/// [`section`]`(set, name)`; the original set, and types without real data, are returned unchanged.
pub fn apply(set: DataSet, name: &str, params: &Params, envelope: &Envelope) -> (Params, Envelope) {
    let (mut p, mut e) = (params.clone(), envelope.clone());
    // A fix of the original's instrument logic, for every type with Real data.
    p.ias_low_speed_fix = set == DataSet::Real;
    let Some(r) = find_type(name).and_then(real) else {
        return (p, e);
    };
    if set != DataSet::Real {
        return (p, e);
    }
    p.empty_mass = r.empty_lb * LB;
    if let Some(f) = r.fuel_lb {
        p.fuel_mass = f * LB;
    }
    if let Some(m) = r.max_lb {
        p.max_mass = m * LB;
    }
    let scale = match r.thrust {
        Thrust::Scale(s) => s,
        Thrust::StaticAb(t) => t / p.thrust[0][0][1],
    };
    for mach in &mut p.thrust {
        for alt in mach {
            for k in alt {
                *k *= scale;
            }
        }
    }
    if let Some(f) = r.alt_thrust {
        for mach in &mut p.thrust {
            for k in &mut mach[1] {
                *k *= f;
            }
        }
    }
    if let Some(m) = r.mil_ratio {
        // Military throttle gives k = 0.6 of the full-AB curve (§4.1).
        p.dry_thrust = m / 0.6;
    }
    if let Some(a) = r.wing_ft2 {
        p.wing_area = a * 0.092903;
    }
    p.wave_drag = r.wave_drag;
    if let Some(cd0) = r.cd0 {
        p.plane_di = cd0;
    }
    if let Some(rr) = r.roll_deg_s {
        p.max_roll_rate = rr.to_radians();
    }
    if let Some((start, stop)) = r.roll_accel {
        p.roll_accel = start.to_radians();
        p.stop_accel = stop.to_radians();
    }
    if let Some(ff) = r.ff_ab_lb_s {
        p.fuel_flow_max = ff * LB;
    }
    if let Some(ff) = r.ff_mil_lb_h {
        // Military throttle 0.74: ff = 0.74 · FuelFlowAtMaxThrust · dry fraction.
        p.dry_fuel_frac = ff / 3600.0 * LB / (0.74 * p.fuel_flow_max);
    }
    if let Some((max, min)) = r.g {
        p.max_g_m1 = max - 1.0;
        p.min_g_m1 = min - 1.0;
    }
    if let Some((area, cd)) = r.chute {
        p.chute_cd = cd * area / p.wing_area;
    }
    if let Some(c) = r.ceiling_ft {
        e = e.with_ceiling(c * FT);
    }
    if let Some(v) = r.stall_kt {
        e.stall_floor = Some(v * KT);
    }
    if let Some(ab) = r.afterburner {
        p.has_afterburner = ab;
    }
    if let Some(n) = r.nose_wheel {
        p.nose_wheel = Some(NoseWheel { max_angle: n.angle_deg.to_radians(), wheelbase: n.wheelbase_ft * FT, max_lateral: n.grip_g * G });
    }
    (p, e)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn real_f4_chute() {
        // The F-4 row's 16 ft chute: 0.63 · 18.68 m² / 49.24 m² ≈ 0.239; the original set keeps 0.
        let p = Params::from_section(iaf_formats::ini::Ini::parse(b"[F-4]\r\nWingArea = 530\r\n").section("F-4").unwrap());
        let e = Envelope::parse(b"[Min Velocity Table]\r\n0 100 0\r\n1 150 0\r\n1 160 40000\r\n");
        assert_eq!(apply(DataSet::Original, "F-4", &p, &e).0.chute_cd, 0.0);
        let (r, _) = apply(DataSet::Real, "F-4", &p, &e);
        assert!((r.chute_cd - 0.63 * 18.68 / r.wing_area).abs() < 0.01, "{} (wing {} m²)", r.chute_cd, r.wing_area);
    }

    #[test]
    fn f35i_always_flies_its_real_row() {
        assert_eq!(effective(DataSet::Original, "F-35I"), DataSet::Real);
        assert_eq!(effective(DataSet::Original, "f35i"), DataSet::Real);
        assert_eq!(effective(DataSet::Original, "F-16"), DataSet::Original);
        assert_eq!(section(effective(DataSet::Original, "F-35I"), "F-35I"), "F-16");
        assert_eq!(find_type("f35i").map(|t| t.type_code), Some(1000));
    }

    #[test]
    fn kfir_and_mirage_share_the_first_section_with_original_data() {
        let mut b = Blocks::new();
        assert_eq!(b.section(DataSet::Original, "MIRAGE"), "MIRAGE");
        assert_eq!(b.section(DataSet::Original, "KFIR"), "MIRAGE");
        assert_eq!(b.section(DataSet::Original, "cfir"), "MIRAGE");
        // The Real set: each its own; other types untouched.
        assert_eq!(b.section(DataSet::Real, "KFIR"), section(DataSet::Real, "KFIR"));
        assert_eq!(b.section(DataSet::Original, "F-16"), "F-16");
        let mut b = Blocks::new();
        assert_eq!(b.section(DataSet::Original, "KFIR"), "KFIR");
        assert_eq!(b.section(DataSet::Original, "MIRAGE"), "KFIR");
    }

    #[test]
    fn real_set_fixes_the_low_speed_ias() {
        // Every type with the Real set, also one without a Real row (the TU22); never the original set.
        let p = Params::from_section(iaf_formats::ini::Ini::parse(b"[F-4]\r\nWingArea = 530\r\n").section("F-4").unwrap());
        let e = Envelope::parse(b"[Min Velocity Table]\r\n0 100 0\r\n1 150 0\r\n1 160 40000\r\n");
        assert!(!apply(DataSet::Original, "F-4", &p, &e).0.ias_low_speed_fix);
        assert!(apply(DataSet::Real, "F-4", &p, &e).0.ias_low_speed_fix);
        assert!(apply(DataSet::Real, "TU22", &p, &e).0.ias_low_speed_fix);
    }

    #[test]
    fn types_and_rows() {
        // A bare section selects its first type; model folders and type names resolve.
        assert_eq!(find_type("TU22").unwrap().name, "TU22");
        assert_eq!(find_type("f-16").unwrap().name, "F-16");
        assert_eq!(find_type("boing").unwrap().name, "707");
        assert_eq!(find_type("A-4").unwrap().section, "TU22");
        assert!(find_type("SU24").is_some_and(|t| t.section == "TU22"));
        assert_eq!(section(DataSet::Original, "UNKNOWN"), "UNKNOWN");
        // Every row belongs to one type, once.
        for r in REAL {
            assert!(TYPES.iter().any(|t| t.name == r.aircraft), "{}", r.aircraft);
            assert_eq!(REAL.iter().filter(|x| x.aircraft == r.aircraft).count(), 1, "{}", r.aircraft);
        }
    }
}
