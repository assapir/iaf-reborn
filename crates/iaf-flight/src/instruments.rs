//! The cockpit state the panel, HUD and MFD pages read (`S`, the global 0x684760; docs/cockpit.md "Round gauges"
//! and "Attitude indicators"), from the flight model's state as the player controller fills it (`FUN_00448b20`:
//! `FUN_004458b0`, `FUN_004459a0`; the engine and fuel values @45ac00). The host only draws them.

use crate::aircraft::State;

/// m/s → kt (`0x600a70`, `0x611cac`).
const KT: f32 = 1.942_795_5;
/// m/s → ft/min (`0x600a74`).
const FPM: f32 = 196.848;
/// m → ft (`0x600a68`, `0x611cb0`).
const FT: f32 = 3.281;
/// kg → lb (`0x6010b0`).
const LB: f32 = 2.204_63;

/// One engine's damage flags (docs/damage.md §5, left 2 / 16 / 22, right 3 / 17 / 23).
#[derive(Debug, Clone, Copy, Default)]
pub struct EngineDamage {
    pub cut_out: bool,
    pub fire: bool,
    pub permanent: bool,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct Instruments {
    /// S+0x330: the airspeed (FM query 5), kt — SPEEDCLOCK, the HUD's "T".
    pub tas_kt: f32,
    /// S+0x334: the horizontal ground speed (query 6), kt — the HUD's "G".
    pub ground_kt: f32,
    /// S+0x33c: the indicated airspeed (query 0x10, [`ias`]) · KT — the HUD's plain number, the MFD ADI page.
    pub ias_kt: f32,
    /// S+0x54: vertical speed (query 7), ft/min — VARIOCLOCK, PANELVARIO.
    pub vs_fpm: f32,
    /// S+0x3c: the wheels' height above the ground, ft; 0 below 1 ft.
    pub agl_ft: f32,
    /// S+0x1058: total fuel / internal capacity, at most 1 — FUELCLOCK.
    pub fuel_fill: f32,
    /// S+0x1040.. / +0x1060..: [THROTTLE, RPM, TEMP] needles per engine (left, right), [`engine_needles`].
    pub engines: [[f32; 3]; 2],
}

/// FM query 0x10 (@5a9894): with V the airspeed in kt and h the height in ft,
/// `r = ((−1.305e-5 + 3.1825e-9·V)·h + 1.0017)·V − 3.122`; it returns r in m/s (·0.5147222) when
/// 50 ≤ r ≤ 999, else V itself — in kt, which the caller converts to kt once more (below 50 kt indicated,
/// e.g. taxiing, the cockpit shows 1.94 × the speed: the original's unit slip). `fix` (Real data,
/// `Params::ias_low_speed_fix`): the airspeed in m/s instead.
pub fn ias(speed: f32, height_m: f32, fix: bool) -> f32 {
    let v = speed * KT;
    let r = ((-1.305e-5 + 3.1825e-9 * v) * (height_m * FT) + 1.0017) * v - 3.122;
    if (50.0..=999.0).contains(&r) {
        r * 0.514_722_2
    } else if fix {
        speed
    } else {
        v
    }
}

/// The engine needles (@45ac00) from the RPM fraction: THROTTLE = rpm, RPM = clamp(rpm, 0.6, 0.97),
/// TEMP = clamp(rpm, 0.5, 0.8); fire → TEMP 0.9, cut out → RPM 0, permanent damage → THROTTLE and RPM 0.
pub fn engine_needles(rpm: f32, d: EngineDamage) -> [f32; 3] {
    let mut n = [rpm, rpm.clamp(0.6, 0.97), rpm.clamp(0.5, 0.8)];
    if d.fire {
        n[2] = 0.9;
    }
    if d.cut_out {
        n[1] = 0.0;
    }
    if d.permanent {
        n[0] = 0.0;
        n[1] = 0.0;
    }
    n
}

/// The cockpit state from the FM state. `ground_height` / `gear_clearance` in m, `internal_fuel_kg` the
/// capacity (FuelWeight), `ias_fix` = `Params::ias_low_speed_fix`. Both engines read the one RPM (the original
/// has one engine state too).
pub fn instruments(
    s: &State,
    ground_height: f32,
    gear_clearance: f32,
    internal_fuel_kg: f32,
    ias_fix: bool,
    damage: [EngineDamage; 2],
) -> Instruments {
    let v = s.velocity;
    let height = s.position[2] as f32;
    // FUN_004458b0: (z − ground)·FT − clearance·FT, 0 below 1.
    let agl = (height - ground_height) * FT - gear_clearance * FT;
    // @45acb9: fuel / capacity, capped at 1; with no capacity the fuel itself.
    let (fuel, cap) = (s.fuel_kg * LB, internal_fuel_kg * LB);
    let rpm = s.rpm * 0.01;
    Instruments {
        tas_kt: s.speed * KT,
        ground_kt: (v[0] * v[0] + v[1] * v[1]).sqrt() * KT,
        ias_kt: ias(s.speed, height, ias_fix) * KT,
        vs_fpm: v[2] * FPM,
        agl_ft: if agl < 1.0 { 0.0 } else { agl },
        fuel_fill: if cap > 0.0 { (fuel / cap).min(1.0) } else { fuel },
        engines: [engine_needles(rpm, damage[0]), engine_needles(rpm, damage[1])],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ias_reads_low_at_altitude_and_slips_below_50_unless_fixed() {
        // Sea level: about the airspeed (1.0017·V − 3.1).
        let sl = ias(150.0, 0.0, false) * KT;
        assert!((sl - (1.0017 * 150.0 * KT - 3.122)).abs() < 0.1, "{sl}");
        // 30,000 ft at 250 m/s (486 kt): well below the true speed.
        let hi = ias(250.0, 9144.0, false) * KT;
        assert!(hi < 0.75 * 250.0 * KT && hi > 50.0, "{hi}");
        // 10 m/s (19 kt) taxiing: r < 50, so V in kt comes back and reads ×1.94 again.
        assert!((ias(10.0, 0.0, false) * KT - 10.0 * KT * KT).abs() < 0.01);
        // Real data: the airspeed itself.
        assert!((ias(10.0, 0.0, true) * KT - 10.0 * KT).abs() < 0.001);
        assert_eq!(ias(150.0, 0.0, true), ias(150.0, 0.0, false));
    }

    #[test]
    fn engine_needles_follow_rpm_and_damage() {
        let none = EngineDamage::default();
        assert_eq!(engine_needles(0.3, none), [0.3, 0.6, 0.5]);
        let fire = EngineDamage { fire: true, ..none };
        assert_eq!(engine_needles(1.0, fire), [1.0, 0.97, 0.9]);
        let dead = EngineDamage { permanent: true, ..none };
        assert_eq!(engine_needles(1.0, dead), [0.0, 0.0, 0.8]);
        let cut = EngineDamage { cut_out: true, ..none };
        assert_eq!(engine_needles(0.7, cut), [0.7, 0.0, 0.7]);
    }
}
