//! Per-aircraft parameters from `bd.ibx` (loader `FUN_005b2940`, v1.0 `5af920`), converted to SI
//! exactly as the original does at load time.

use iaf_formats::ini::Section;

const LB: f32 = 0.45359;
const FT2: f32 = 0.092903;
pub(crate) const FT: f32 = 0.3048;
const DEG: f32 = 0.017_453_3;
const DI: f32 = 1e-4;

#[derive(Debug, Clone)]
pub struct Params {
    pub empty_mass: f32,
    pub max_mass: f32,
    pub wing_area: f32,
    pub wing_span: f32,
    pub max_roll_rate: f32,
    pub roll_accel: f32,
    pub stop_accel: f32,
    pub max_beta: f32,
    pub beta_rate: f32,
    /// Stored like the original: MaxG − 1 / MinG − 1.
    pub max_g_m1: f32,
    pub min_g_m1: f32,
    pub g_rate: f32,
    pub g_rate_for_aoa: f32,
    pub flaps_di: f32,
    pub speed_brakes_di: f32,
    pub gear_di: f32,
    pub hook_di: f32,
    /// Clean drag coefficient (PlaneDragIndex × 1e-4).
    pub plane_di: f32,
    pub wheel_brake_di: f32,
    pub flaps_lift_coef: f32,
    pub fuel_mass: f32,
    /// kg/s at full throttle.
    pub fuel_flow_max: f32,
    /// lbf, indexed [min/max mach][min/max alt][k=0 / k=1].
    pub thrust: [[[f32; 2]; 2]; 2],
    pub has_afterburner: bool,
    pub start_vibs_g: f32,
    pub use_flight_limits: bool,
    pub max_neg_alpha: f32,
    pub max_pos_alpha: f32,
    pub limit_alpha_visual: f32,
    pub max_alpha_rate: f32,
    pub alpha_stop_accel: f32,
    pub alpha_start_accel: f32,
    pub alpha_k: f32,
    pub alpha_beta: f32,
    /// v1.1 sideslip channel gains (`P+0x16c..0x178`, stored raw like the α keys; docs/flight-model.md
    /// §15.2.6). A v1.0 `bd.ibx` has none of them, so the exe's defaults apply: 5 / 0 / 0.5 / 0.5.
    pub rudder_k: f32,
    pub rudder_beta: f32,
    pub rudder_start_accel: f32,
    pub rudder_stop_accel: f32,
    pub start_move_stick_center_g: f32,
    pub map_center_stick: f32,
    pub over_g_thresh: f32,
    pub envelope_file: String,
    /// Transonic wave-drag rise (not in the original model; used by the real data set):
    /// ΔCD grows linearly from Mach 0.9 to `wave_drag` at Mach 1.2 and stays there.
    pub wave_drag: f32,
    /// Deployed drag chute ΔCD (wing reference). 0 in the original (its ParachuteDragIndex is never read,
    /// docs/flight-model.md); the Real set's chute area · CD / wing area (docs/real-aircraft.md).
    pub chute_cd: f32,
    /// Real data set only: scales the dry (non-afterburner) part of the thrust curve so military power
    /// gives the engine's real dry / max-AB ratio (the original fixes it at k = 0.6). 1 = original.
    pub dry_thrust: f32,
    /// Fuel flow below the afterburner as a fraction of `thr · FuelFlowAtMaxThrust` (the original's 0.25).
    pub dry_fuel_frac: f32,
    /// Real nose-wheel steering (real data set only): wheel angle from the rudder pedals, turn rate
    /// from the geometry. None = the original's formula (flight-model.md §7).
    pub nose_wheel: Option<NoseWheel>,
    /// Real data set: the indicated airspeed below 50 kt is the airspeed (the original returns it in kt where
    /// m/s is due, so the cockpit read 1.94 × the speed; docs/cockpit.md "Speeds"). false = original.
    pub ias_low_speed_fix: bool,
    /// Aircraft type `veh+0xc54` (set by `FUN_005a8980`, docs/part-animation.md): 100 F-16, 110 F-15,
    /// 120 F-4, 130 Kfir, 140 Lavi, 150 MiG-21, 160 MiG-23, 170 MiG-25, 180 MiG-29, 190 Mirage,
    /// 210 MiG-17, 220 Tu-22, 225 C-130; 0 = unknown. Types 100/140 never spin (§15.5); type 100
    /// lowers its flaps to a third (§15.6.4).
    pub type_code: u32,
}

/// `veh+0xc54` for a bd.ibx section name (0 if unknown, e.g. SU24).
pub fn type_code(section: &str) -> u32 {
    match section.to_ascii_uppercase().as_str() {
        "F-16" => 100,
        "F-15" => 110,
        "F-4" => 120,
        "KFIR" => 130,
        "LAVI" => 140,
        "MIG21" => 150,
        "MIG23" => 160,
        "MIG25" => 170,
        "MIG29" => 180,
        "MIRAGE" => 190,
        "MIG17" => 210,
        "TU22" => 220,
        "C130" => 225,
        _ => 0,
    }
}

/// Wrap degrees to (-180, 180] then convert to radians (the original's "deg→rad*").
fn wrap_rad(deg: f32) -> f32 {
    let mut d = deg % 360.0;
    if d > 180.0 {
        d -= 360.0;
    } else if d <= -180.0 {
        d += 360.0;
    }
    d * DEG
}

impl Params {
    pub fn from_section(s: &Section) -> Self {
        let f = |k: &str, d: f32| s.f32(k).unwrap_or(d);
        let thrust = |mach: &str, alt: &str, k: u8, d: f32| f(&format!("Thrust{mach}Mach{alt}Alt{k}"), d);
        Self {
            empty_mass: f("EmptyWeight", 16000.0) * LB,
            max_mass: f("MaxWeight", 32000.0) * LB,
            wing_area: f("WingArea", 300.0) * FT2,
            wing_span: f("WingSpan", 32.0) * FT,
            max_roll_rate: f("MaxRollRate", 100.0) * DEG,
            roll_accel: f("RollAccel", 300.0) * DEG,
            stop_accel: f("StopAccel", 300.0) * DEG,
            max_beta: wrap_rad(f("MaxBeta", 10.0)),
            beta_rate: wrap_rad(f("BetaRate", 10.0)),
            max_g_m1: f("MaxG", 9.0) - 1.0,
            min_g_m1: f("MinG", -3.0) - 1.0,
            g_rate: f("G_Rate", 5.0),
            g_rate_for_aoa: f("G_RateForAoa", 1.0),
            flaps_di: f("FlapsDragIndex", 76.0) * DI,
            speed_brakes_di: f("SpeedBrakesDragIndex", 320.0) * DI,
            gear_di: f("LandingGearDragIndex", 300.0) * DI,
            hook_di: f("LandingHookDragIndex", 100.0) * DI,
            plane_di: f("PlaneDragIndex", 500.0) * DI,
            wheel_brake_di: f("WheelsBrakeDragIndex", 5000.0) * DI,
            flaps_lift_coef: f("FlapsLiftCoef", 0.2).clamp(0.0, 0.5),
            fuel_mass: f("FuelWeight", 6000.0) * LB,
            fuel_flow_max: f("FuelFlowAtMaxThrust", 2.0) * LB,
            thrust: [
                [
                    [thrust("Min", "Min", 0, 12012.6), thrust("Min", "Min", 1, 19230.4)],
                    [thrust("Min", "Max", 0, 1629.7), thrust("Min", "Max", 1, 2691.0)],
                ],
                [
                    [thrust("Max", "Min", 0, 11128.1), thrust("Max", "Min", 1, 30873.2)],
                    [thrust("Max", "Max", 0, 2394.7), thrust("Max", "Max", 1, 8670.2)],
                ],
            ],
            has_afterburner: f("HasAfterBurner", 1.0) > 0.0,
            start_vibs_g: f("StartVibsG", 1.0),
            use_flight_limits: f("UseFlightLimits", 1.0) as i32 != 0,
            max_neg_alpha: wrap_rad(f("MaxNegAlpha", -5.0)),
            max_pos_alpha: wrap_rad(f("MaxPosAlpha", 27.5)),
            limit_alpha_visual: wrap_rad(f("LimitAlphaVisual", 15.0)),
            max_alpha_rate: f("MaxAlphaRate", 2.5),
            alpha_stop_accel: f("AlphaStopAccel", 0.1),
            alpha_start_accel: f("AlphaStartAccel", 0.5),
            alpha_k: f("AlphaK", 8.0),
            alpha_beta: f("AlphaBeta", 0.1),
            rudder_k: f("RudderK", 5.0),
            rudder_beta: f("RudderBeta", 0.0),
            rudder_start_accel: f("RudderStartAccel", 0.5),
            rudder_stop_accel: f("RudderStopAccel", 0.5),
            start_move_stick_center_g: f("StartMoveStickCenterG", 2.0),
            map_center_stick: f("MapCenterStick", 0.0),
            over_g_thresh: f("OverGThresh", 6.7),
            envelope_file: s.get("FlightEnvelopeFile").unwrap_or("").to_string(),
            wave_drag: 0.0,
            chute_cd: 0.0,
            dry_thrust: 1.0,
            dry_fuel_frac: 0.25,
            nose_wheel: None,
            ias_low_speed_fix: false,
            type_code: 0,
        }
    }
}

/// Geometric nose-wheel steering: yaw rate = V · tan(δ) / wheelbase, δ = pedals · max angle,
/// limited by the tyres' side grip.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NoseWheel {
    pub max_angle: f32,
    pub wheelbase: f32,
    /// Largest sideways acceleration before the tyres skid (m/s²).
    pub max_lateral: f32,
}
