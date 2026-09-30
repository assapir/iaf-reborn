//! "Original 1998" vs "real" data sets.
//!
//! The original numbers are what Jane's IAF shipped (v1.1 files when present, `crate::read_md`). The
//! real set replaces, per flyable jet, the items the validation suite (`tests/validation.rs`) checks
//! against public data; the per-aircraft sources and choices are in docs/real-aircraft.md. Anything a
//! row leaves as `None` keeps the original value. Aircraft without a row (the AI types) fly their
//! original data in both sets.

use crate::params::NoseWheel;
use crate::{Envelope, Params};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DataSet {
    #[default]
    Original,
    Real,
}

const LB: f32 = 0.45359;
const KT: f32 = 0.514722;
const FT: f32 = 0.3048;
const G: f32 = 9.806;

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

/// One aircraft's real-world values (public data, docs/real-aircraft.md).
#[derive(Debug, Clone, Copy)]
struct Real {
    /// bd.ibx section.
    section: &'static str,
    empty_lb: f32,
    /// Internal fuel.
    fuel_lb: Option<f32>,
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
    /// 1 g stall speed at sea level (kt TAS), `Envelope::stall_floor`.
    stall_kt: Option<f32>,
    /// Max / min load factor (MaxG, MinG).
    g: Option<(f32, f32)>,
    nose_wheel: Option<Nws>,
}

const NONE: Real = Real {
    section: "",
    empty_lb: 0.0,
    fuel_lb: None,
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
    nose_wheel: None,
};

const REAL: &[Real] = &[
    // F-16C Block 30/40 with F110-GE-100 (public figures, approximate).
    Real {
        section: "F-16",
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
        ..NONE
    },
    // F-15C Baz, 2 x F100-PW-220: USAF Standard Aircraft Characteristics (SAC) chart, Feb 1992.
    Real {
        section: "F-15",
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
        ..NONE
    },
    // F-4E Kurnass, 2 x J79-GE-17 (the Kurnass 2000 kept the engines and airframe: same row).
    Real {
        section: "F-4",
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
        ..NONE
    },
    // IAI Lavi (production design figures, Jane's 1987-88) with the PW1120.
    Real {
        section: "LAVI",
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
        ..NONE
    },
    // Kfir C7 (IAI J79-J1E, licence-built J79-GE-17), Jane's.
    Real {
        section: "KFIR",
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
        ..NONE
    },
    // Mirage IIICJ Shahak (SNECMA Atar 09C), jet only (no SEPR rocket).
    Real {
        section: "MIRAGE",
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
        ..NONE
    },
];

/// Applies the real-world values for `section` (a bd.ibx section name); the original set, and
/// sections without real data, are returned unchanged.
pub fn apply(set: DataSet, section: &str, params: &Params, envelope: &Envelope) -> (Params, Envelope) {
    let (mut p, mut e) = (params.clone(), envelope.clone());
    let Some(r) = REAL.iter().find(|r| r.section.eq_ignore_ascii_case(section)) else {
        return (p, e);
    };
    if set != DataSet::Real {
        return (p, e);
    }
    p.empty_mass = r.empty_lb * LB;
    if let Some(f) = r.fuel_lb {
        p.fuel_mass = f * LB;
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
    if let Some(v) = r.stall_kt {
        e.stall_floor = Some(v * KT);
    }
    if let Some(n) = r.nose_wheel {
        p.nose_wheel = Some(NoseWheel { max_angle: n.angle_deg.to_radians(), wheelbase: n.wheelbase_ft * FT, max_lateral: n.grip_g * G });
    }
    (p, e)
}
