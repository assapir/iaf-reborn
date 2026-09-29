//! "Original 1998" vs "real" data sets.
//!
//! The original numbers are what Jane's IAF shipped. The real set corrects the items the
//! validation suite (`tests/validation.rs`) flags against public data. Only the F-16 has
//! real-world corrections so far; other aircraft use their original data in both sets.

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

/// Applies the real-world corrections for `section` (a bd.ibx section name).
pub fn apply(set: DataSet, section: &str, params: &Params, envelope: &Envelope) -> (Params, Envelope) {
    let (mut p, mut e) = (params.clone(), envelope.clone());
    if set == DataSet::Real && section.eq_ignore_ascii_case("F-16") {
        // F-16C Block 30/40 with F110-GE-100 (public figures, approximate).
        p.empty_mass = 19_000.0 * LB;
        // 19,330 lbf full AB in the original → ~29,000 lbf (F110-GE-100 SL static): scale the whole table.
        for mach in &mut p.thrust {
            for alt in mach {
                for k in alt {
                    *k *= 1.5;
                }
            }
        }
        // No transonic drag rise in the original: tuned to Mach 1.2 at SL / ~1.9 at 40k ft.
        p.wave_drag = 0.02;
        p.max_roll_rate = 280f32.to_radians();
        // FLCS roll response: time constant ~0.3 s → ~900 deg/s² to start and stop the roll
        // (the original stops at 170 deg/s², overshooting ~1 s after the stick is centred).
        p.roll_accel = 900f32.to_radians();
        p.stop_accel = 900f32.to_radians();
        // ~60,000 lb/h at full AB; the original's ×0.25 below AB then gives ~11,000 lb/h at military.
        p.fuel_flow_max = 16.5 * LB;
        // 1 g stall ~118 kt instead of 86 kt: with Vmin ∝ √g this puts 9 g at ~355 kt,
        // matching the published ~330-350 kt corner speed.
        e.stall_floor = Some(118.0 * KT);
        // Nose-wheel steering through the rudder pedals, ±32° (low-gain / taxi NWS), wheelbase
        // 13.2 ft; side grip ~0.3 g (approximate). The original instead turns at stick · V · 20°/s / 145 kt.
        p.nose_wheel = Some(NoseWheel { max_angle: 32f32.to_radians(), wheelbase: 13.2 * 0.3048, max_lateral: 0.3 * 9.806 });
    }
    (p, e)
}
