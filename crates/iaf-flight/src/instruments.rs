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
    /// Afterburner damage (8 / 9): the AB flag reads 0. Only the Better cockpit's throttle needle reads it.
    pub afterburner: bool,
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
    /// Better cockpit (ours): total fuel / the fuel capacity with the tanks loaded now (FuelWeight + tanks).
    pub fuel_fill_total: f32,
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

/// Better cockpit (ours, docs/cockpit.md "Better cockpit"): the engine needles from the FM's own values.
/// THROTTLE = rpm, then 1.1 / 1.2 in AB 1 / 2 (no AB with the afterburner or the engine damaged); RPM = the RPM
/// ramp itself (0 engine off, 0.6 idle, 1.0 military, spool-up at 15 %/s); TEMP = `temp_c` / 1000 ([`EngineTemps`]).
/// Cut out → RPM 0, permanent damage → THROTTLE and RPM 0, as the original.
pub fn better_engine_needles(rpm: f32, ab_stage: u8, temp_c: f32, d: EngineDamage) -> [f32; 3] {
    let stage = if d.afterburner || d.permanent || d.cut_out { 0 } else { ab_stage.min(2) };
    let mut n = [rpm + 0.1 * stage as f32, rpm, temp_c / 1000.0];
    if d.cut_out {
        n[1] = 0.0;
    }
    if d.permanent {
        n[0] = 0.0;
        n[1] = 0.0;
    }
    n
}

/// Better cockpit `dials_by_label` (ours, docs/cockpit.md "Gauges on their labelled dials"): the F-16's exhaust
/// nozzle position (%, 0 closed .. 100 open) and engine oil pressure (psi) from the needle RPM `rpm` (0 engine off,
/// 0.6 idle, 1.0 military; the Better RPM after damage) and the AB stage. T.O. GR1F-16CJ-1 gives the shape: ground
/// idle (gear handle down) opens the nozzle past 80 %, flight idle 0–20 %, military at most 20 %, the AB opens it;
/// oil rises about 15 psi from idle to military, at least 15 psi at idle. The numbers are inferred: ground idle 85 %,
/// flight idle 20 %, military 5 %, AB 1 / 2 at 50 / 100 %; oil 30 psi at idle, 45 psi at military; both fall to 0
/// with the RPM below idle.
pub fn nozzle_and_oil(rpm: f32, ab_stage: u8, gear_down: bool, d: EngineDamage) -> [f32; 2] {
    let stage = if d.afterburner || d.permanent || d.cut_out { 0 } else { ab_stage.min(2) };
    let idle_noz = if gear_down { 85.0 } else { 20.0 };
    let (noz, oil) = if rpm < 0.6 {
        let k = (rpm / 0.6).max(0.0);
        (idle_noz * k, 30.0 * k)
    } else {
        let k = ((rpm - 0.6) / 0.4).min(1.0);
        (idle_noz * (1.0 - k) + 5.0 * k, 30.0 + 15.0 * k)
    };
    [if stage > 0 { 50.0 * stage as f32 } else { noz }, oil]
}

/// The Better cockpit's engine temperature (exhaust gas / turbine temperature, °C), one per engine: a first-order
/// lag toward a target from the RPM and the AB stage. All constants are inferred (docs/cockpit.md "Engine
/// temperature"): ambient 15 °C, idle (60 % RPM) 450 °C, military 650 °C, +15 °C per AB stage, an engine fire
/// 900 °C; it heats with a 2 s time constant and cools with 8 s.
#[derive(Debug, Clone, Copy, Default)]
pub struct EngineTemps {
    c: [f32; 2],
    /// The FM time of the last update; None before the first (the temperature then starts at its target).
    t: Option<f64>,
}

impl EngineTemps {
    pub const AMBIENT: f32 = 15.0;
    pub const IDLE: f32 = 450.0;
    pub const MIL: f32 = 650.0;
    pub const PER_AB_STAGE: f32 = 15.0;
    pub const FIRE: f32 = 900.0;
    pub const TAU_HEAT: f32 = 2.0;
    pub const TAU_COOL: f32 = 8.0;

    /// The temperature an engine settles at.
    pub fn target(rpm: f32, ab_stage: u8, d: EngineDamage) -> f32 {
        if d.fire {
            return Self::FIRE;
        }
        if d.cut_out || d.permanent || rpm <= 0.0 {
            return Self::AMBIENT;
        }
        let dry = if rpm < 0.6 {
            Self::AMBIENT + (Self::IDLE - Self::AMBIENT) * rpm / 0.6
        } else {
            Self::IDLE + (Self::MIL - Self::IDLE) * ((rpm - 0.6) / 0.4).min(1.0)
        };
        let stage = if d.afterburner { 0 } else { ab_stage.min(2) };
        dry + Self::PER_AB_STAGE * stage as f32
    }

    /// Steps both engines to the FM time `time` (s) and returns their temperatures (°C). A time going back (a
    /// restarted flight) starts again at the target.
    pub fn update(&mut self, time: f64, rpm: f32, ab_stage: u8, d: [EngineDamage; 2]) -> [f32; 2] {
        let dt = match self.t {
            Some(t0) if time >= t0 => (time - t0) as f32,
            _ => f32::INFINITY,
        };
        self.t = Some(time);
        for (c, d) in self.c.iter_mut().zip(d) {
            let target = Self::target(rpm, ab_stage, d);
            let tau = if target > *c { Self::TAU_HEAT } else { Self::TAU_COOL };
            *c += (target - *c) * (1.0 - (-dt / tau).exp());
        }
        self.c
    }
}

/// The cockpit state from the FM state. `ground_height` / `gear_clearance` in m, `internal_fuel_kg` the
/// capacity (FuelWeight), `fuel_capacity_kg` the fuel maximum with the tanks (FuelWeight + tanks), `ias_fix` = `Params::ias_low_speed_fix`. Both engines read the one RPM (the original
/// has one engine state too).
pub fn instruments(
    s: &State,
    ground_height: f32,
    gear_clearance: f32,
    internal_fuel_kg: f32,
    fuel_capacity_kg: f32,
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
        fuel_fill_total: if fuel_capacity_kg > 0.0 { (s.fuel_kg / fuel_capacity_kg).min(1.0) } else { 0.0 },
    }
}

/// Ours, "Better cockpit" (docs/cockpit.md "Better cockpit"): the AoA indexer's lit symbol (`aoa_indexer`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Indexer {
    /// No indexer on the jet.
    #[default]
    Off = 0,
    /// The upper chevron: AoA high, speed low.
    Slow = 1,
    /// The donut: on-speed AoA.
    OnSpeed = 2,
    /// The lower chevron: AoA low, speed high.
    Fast = 3,
}

/// The indexer for type `type_code` at `aoa_deg`. Only the F-16 (100) has one in the panel art. Its T.O.
/// GR1F-16CJ-1 fig. 1-52 shows the upper chevron at 15°, the donut at 13° (the optimum landing AoA), the lower
/// chevron at 11°, and the indexer works with the gear up or down; the band edges 12° / 14° (half-way) are
/// inferred.
pub fn aoa_indexer(type_code: u32, aoa_deg: f32) -> Indexer {
    match type_code {
        100 if aoa_deg > 14.0 => Indexer::Slow,
        100 if aoa_deg >= 12.0 => Indexer::OnSpeed,
        100 => Indexer::Fast,
        _ => Indexer::Off,
    }
}

/// Ours, "Better cockpit" warning lamps the original leaves unlit (`warning_lamps`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Warnings {
    /// F-16 FLCS: a flight-control failure, damage 18 (hydraulics) or 24 (total flight control).
    pub flcs: bool,
    /// F-16 TO/LDG CONFIG: in flight below 10,000 ft and 190 kt, descending faster than 250 ft/min, with the gear
    /// not down and locked (T.O. GR1F-16CJ-1, "TO/LDG CONFIG Warning Light"; its TEF condition is left out: the
    /// game's flaps are a key of their own).
    pub to_ldg_config: bool,
    /// F-16 AR/NWS (the AR status indicator's middle lamp, green): nose-wheel steering engaged. The real jet
    /// engages it with the NWS button on the ground (T.O. GR1F-16CJ-1, "NWS Light"); the game steers the nose wheel
    /// with the pedals whenever it is on the ground (v1.1), so: on the ground (inferred).
    pub ar_nws: bool,
}

/// The warning lamps from the flight state ([`Instruments`] units; `gear` the FM's gear ramp, 0 = down and locked)
/// and the damage flags 0..24 (docs/damage.md §5; a shorter slice reads as unset).
pub fn warnings(on_ground: bool, alt_ft: f32, ias_kt: f32, vs_fpm: f32, gear: f32, flags: &[bool]) -> Warnings {
    let flag = |i: usize| flags.get(i).copied().unwrap_or(false);
    Warnings {
        flcs: flag(18) || flag(24),
        to_ldg_config: !on_ground && alt_ft < 10_000.0 && ias_kt < 190.0 && vs_fpm < -250.0 && gear > 0.0,
        ar_nws: on_ground,
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

    #[test]
    fn f16_aoa_indexer_bands() {
        assert_eq!(aoa_indexer(100, 16.0), Indexer::Slow);
        assert_eq!(aoa_indexer(100, 13.0), Indexer::OnSpeed);
        assert_eq!(aoa_indexer(100, 12.0), Indexer::OnSpeed);
        assert_eq!(aoa_indexer(100, 11.0), Indexer::Fast);
        assert_eq!(aoa_indexer(100, 0.0), Indexer::Fast);
        assert_eq!(aoa_indexer(110, 13.0), Indexer::Off);
    }

    #[test]
    fn warnings_follow_damage_and_the_approach() {
        let w = warnings(false, 2000.0, 160.0, -1000.0, 1.569, &[]);
        assert!(w.to_ldg_config && !w.flcs);
        assert!(!warnings(false, 2000.0, 160.0, -1000.0, 0.0, &[]).to_ldg_config, "gear down and locked");
        assert!(!warnings(false, 2000.0, 200.0, -1000.0, 0.5, &[]).to_ldg_config, "fast");
        assert!(!warnings(false, 2000.0, 160.0, 0.0, 0.5, &[]).to_ldg_config, "level");
        assert!(!warnings(false, 12000.0, 160.0, -1000.0, 0.5, &[]).to_ldg_config, "high");
        assert!(!warnings(true, 0.0, 100.0, -1000.0, 0.5, &[]).to_ldg_config, "on the ground");
        assert!(warnings(true, 0.0, 0.0, 0.0, 0.0, &[]).ar_nws && !w.ar_nws, "AR/NWS on the ground only");
        let mut f = vec![false; 25];
        f[18] = true;
        assert!(warnings(false, 0.0, 0.0, 0.0, 0.0, &f).flcs);
        f[18] = false;
        f[24] = true;
        assert!(warnings(false, 0.0, 0.0, 0.0, 0.0, &f).flcs);
    }

    #[test]
    fn nozzle_opens_at_ground_idle_and_in_ab_and_oil_rises_with_rpm() {
        let ok = EngineDamage::default();
        let near = |a: [f32; 2], b: [f32; 2]| (a[0] - b[0]).abs() < 1e-4 && (a[1] - b[1]).abs() < 1e-4;
        assert!(near(nozzle_and_oil(0.6, 0, true, ok), [85.0, 30.0]));
        assert!(near(nozzle_and_oil(0.6, 0, false, ok), [20.0, 30.0]));
        assert!(near(nozzle_and_oil(1.0, 0, false, ok), [5.0, 45.0]));
        assert!(near(nozzle_and_oil(1.0, 1, false, ok), [50.0, 45.0]));
        assert!(near(nozzle_and_oil(1.0, 2, false, ok), [100.0, 45.0]));
        assert!(near(nozzle_and_oil(0.0, 0, true, ok), [0.0, 0.0]));
        // No AB with the afterburner damaged.
        assert!(near(nozzle_and_oil(1.0, 2, false, EngineDamage { afterburner: true, ..ok }), [5.0, 45.0]));
    }

    #[test]
    fn better_needles_show_real_rpm_and_ab_stages() {
        let none = EngineDamage::default();
        // Engine off, spool-up, idle, military: the RPM ramp itself (the original reads 0.6 / 0.6 / 0.6 / 0.97).
        for rpm in [0.0, 0.3, 0.6, 1.0] {
            assert_eq!(better_engine_needles(rpm, 0, 0.0, none)[1], rpm);
        }
        // AB 1 / 2 above military on the throttle needle.
        assert!((better_engine_needles(1.0, 1, 0.0, none)[0] - 1.1).abs() < 1e-6);
        assert!((better_engine_needles(1.0, 2, 0.0, none)[0] - 1.2).abs() < 1e-6);
        let ab = EngineDamage { afterburner: true, ..none };
        assert_eq!(better_engine_needles(1.0, 2, 0.0, ab)[0], 1.0);
        let dead = EngineDamage { permanent: true, ..none };
        assert_eq!(better_engine_needles(1.0, 2, 650.0, dead), [0.0, 0.0, 0.65]);
    }

    #[test]
    fn engine_temperature_heats_with_power_and_cools_with_time() {
        let none = [EngineDamage::default(); 2];
        let mut t = EngineTemps::default();
        // The first update starts at the target: idle.
        assert_eq!(t.update(0.0, 0.6, 0, none), [EngineTemps::IDLE; 2]);
        // Military: one heating time constant covers 63 % of the step.
        let c = t.update(EngineTemps::TAU_HEAT as f64, 1.0, 0, none)[0];
        let want = EngineTemps::IDLE + (EngineTemps::MIL - EngineTemps::IDLE) * (1.0 - (-1.0f32).exp());
        assert!((c - want).abs() < 0.5, "{c} {want}");
        // Settled, then AB 2 is hotter still.
        let mil = t.update(60.0, 1.0, 0, none)[0];
        assert!((mil - EngineTemps::MIL).abs() < 0.1);
        assert!(t.update(80.0, 1.0, 2, none)[0] > mil + 25.0);
        // Back to idle: cooling is slower than heating.
        let one = t.update(80.0 + EngineTemps::TAU_HEAT as f64, 0.6, 0, none)[0];
        assert!(one > EngineTemps::IDLE + 0.6 * (EngineTemps::MIL + 30.0 - EngineTemps::IDLE), "{one}");
        // A fire on the right engine only.
        let fire = [EngineDamage::default(), EngineDamage { fire: true, ..Default::default() }];
        let c = t.update(200.0, 0.6, 0, fire);
        assert!((c[0] - EngineTemps::IDLE).abs() < 0.1 && (c[1] - EngineTemps::FIRE).abs() < 0.1);
        // A restarted flight (time back to 0) starts at the target again: engine off, ambient.
        assert_eq!(t.update(0.0, 0.0, 0, none), [EngineTemps::AMBIENT; 2]);
    }
}
