//! The aircraft: state, controls and the original's update schedule
//! (docs/flight-model.md §4–§7, §14, §15).
//!
//! World frame is ENU: X east, Y north, Z up (metres). Positive roll = right wing down.
//! Faithful to the original by default; the [`BetterPhysics`] options switch on the fixes listed in
//! docs/flight-model.md §10 / §15.11 ("BP"), each on its own.

use crate::atmosphere::{air, q_s};
use crate::channels::{Angle, Axis, Ramp};
use crate::envelope::{Envelope, GLimit};
use crate::params::Params;
use std::f32::consts::PI;

pub const G: f32 = 9.806;
const LBF: f32 = 4.4479;
/// Aero data refresh (plus every control event).
const AERO_PERIOD: f64 = 1.0;
/// Acceleration / rate refresh.
const ACCEL_PERIOD: f64 = 0.2;
/// Departure latch after a stall (`now − t ≤ 3.0`, §15.2.4).
const STALL_LATCH: f64 = 3.0;
/// Rolling friction, IAF.ibx `[TAXI] fric1` (load-time initialiser 0x5ba8e0 → DAT_008454a8).
const FRIC1: f32 = 0.05;
/// Nose-wheel yaw limit K (DAT_008454d4 = 1° · 20, set at load by 0x5bab80).
const NOSE_K: f32 = 0.349_065_9;
/// Control ramps (§15.6.4): gear 0 = extended .. 1.569 = up, flaps 0..0.29275, brakes 0..0.855, all 0.5/s.
const GEAR_UP: f32 = 1.569;
const FLAPS_MAX: f32 = 0.29275;
const BRAKES_MAX: f32 = 0.855;
const CONTROL_RATE: f32 = 0.5;
/// Flap ramp → flap factor (`×3.4158838`, full flaps = 1.0).
const FLAPS_K: f32 = 3.415_883_8;
/// Throttle: military, first AB value, the player's dead band (§15.8).
const MILITARY: f32 = 0.74;
const AB: f32 = 0.75;
const THROTTLE_DEADBAND: f32 = 0.015;
/// Better physics `ground_idle`: the idle share of the thrust on the ground falls with speed as a jet's net thrust
/// does (ram drag, ṁ·(Vj − V)), at an idle exhaust speed Vj (m/s). The original's idle is constant (k 0.05 of the
/// full-AB curve, F-16 ≈ 1000 lbf static), so a light F-16 rolls past 90 kt at idle; a real one settles near 30 kt
/// (GAO: 50 kt on the first engines, cut to 30). Vj gives the F-16 (Original data, start weight) ≈ 30 kt.
const IDLE_VJ: f32 = 46.0;
/// v1.1 AI wheel-brake factor (`0x612474`; v1.0 2.0).
const AI_BRAKE: f32 = 4.0;
/// Crash immunity: an AI control loop older than this (s) (`0x611d20`).
const AI_OLD: f64 = 3.5;
/// RPM ramp: 0..100 % at 15 %/s; AB light-up delay 1/15 s per missing % (`0x612050`).
const RPM_RATE: f32 = 15.0;
/// Start rules (`FUN_005a5820`): airborne above 800 m unless at a base.
const AIRBORNE_START_Z: f32 = 800.0;
/// Rough-ground crash speed (0x6124a4 = 25.736 m/s = 50 kt).
const ROUGH_CRASH_SPEED: f32 = 25.736;
/// Ground roll: the whole drag × 0.8 above 1 m/s (`0x612480`; v1.0 0.7, §14.2).
const ROLL_DRAG: f32 = 0.8;
/// β channel (`5aa700`, §15.2.6): gains scale with V below 400 m/s (`0x611cc8`; v1.0 375), ×1.5 on K
/// while |β_cmd| ≤ 0.1·MaxBeta (`0x611ccc`).
const BETA_V: f32 = 400.0;
/// Spin recovery: yaw target slope π/(2.2·MaxBeta) (`0x611cf0` = 1.1, v1.0 0.9 → 1.8).
const SPIN_SLOPE: f32 = 2.2;

// Better physics: FLCS (fly-by-wire) departure = deep stall (types 100 F-16, 140 Lavi; not in the
// original, which never lets them depart). Estimates from public F-16 high-AoA data (NASA TP-1538 wind-tunnel
// data, the F-16 deep-stall reports and the -1 recovery procedure); docs/flight-model.md §10.1.
/// Deep-stall trim AoA (the F-16's second pitch trim point, ~60°, beyond the horizontal tail's nose-down power).
const DS_ALPHA: f32 = 60.0 * PI / 180.0;
/// Normal-force coefficient at the trim AoA (flat-plate-like, NASA TP-1538 CN(60°) ≈ 1.5): lift = N·cos α,
/// drag = N·sin α, so L/D = cot α and the path settles near γ = −α = −60°, at the speed where N = W
/// (F-16 at sea level ≈ 63 m/s along the path, ≈ 55 m/s = 10,800 ft/min down).
const DS_CN: f32 = 1.5;
/// Entry: stalled (latch, §15.2.4), below the 1 g minimum speed and the nose at least this high.
const DS_ENTRY_PITCH: f32 = 30.0 * PI / 180.0;
/// Pitch rocking: natural amplitude, maximum, period; the pilot pumps it at DS_PUMP (rad/s) by moving
/// the stick in phase with the pitch rate (MPO + "rocking"); it decays back at DS_DECAY.
const DS_AMP0: f32 = 8.0 * PI / 180.0;
const DS_AMP_MAX: f32 = 50.0 * PI / 180.0;
const DS_PERIOD: f64 = 4.0;
const DS_PUMP: f32 = 5.0 * PI / 180.0;
const DS_DECAY: f32 = 2.0 * PI / 180.0;
/// Recovery: the nose below this AoA (the FLCS AoA limiter, ~25°) with the rocking pumped up.
const DS_EXIT_ALPHA: f32 = 25.0 * PI / 180.0;
const DS_EXIT_AMP: f32 = 20.0 * PI / 180.0;
/// Wing rock and yaw wander (amplitude rad, period s), and how fast the mean attitude follows (rad/s).
const DS_ROLL_AMP: f32 = 10.0 * PI / 180.0;
const DS_ROLL_PERIOD: f64 = 5.3;
const DS_YAW_AMP: f32 = 5.0 * PI / 180.0;
const DS_YAW_PERIOD: f64 = 6.7;
const DS_ATT_RATE: f32 = 20.0 * PI / 180.0;

pub type V3 = [f64; 3];

fn add(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}
fn scale(a: V3, s: f64) -> V3 {
    [a[0] * s, a[1] * s, a[2] * s]
}
fn dot(a: V3, b: V3) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn cross(a: V3, b: V3) -> V3 {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
fn norm(a: V3) -> V3 {
    let l = dot(a, a).sqrt();
    if l > 1e-12 { scale(a, 1.0 / l) } else { [0.0, 1.0, 0.0] }
}
/// Rotate `v` about unit `axis` by `angle` (right-hand rule, Rodrigues).
fn rotate(v: V3, axis: V3, angle: f64) -> V3 {
    let (s, c) = angle.sin_cos();
    add(add(scale(v, c), scale(cross(axis, v), s)), scale(axis, dot(axis, v) * (1.0 - c)))
}
/// `fmod(x, 2π)`, then −2π if > π (helpers `44f5f0`/`43d460`): (−π, π].
fn wrap(a: f64) -> f64 {
    let tau = std::f64::consts::TAU;
    let mut a = a % tau;
    if a > std::f64::consts::PI {
        a -= tau;
    } else if a <= -std::f64::consts::PI {
        a += tau;
    }
    a
}
/// The α law of the second-order channels (α `5aa3a0`/`5ae4c0`, β `5aa700`/`5ae4c0`, §15.2.5): a target rate
/// `clamp(err/π·K/Rmax − damp, ±1)·Rmax` with `damp = B·rate·Rmax` (halved while |rate| > π), then the
/// channel re-based at its sampled angle.
/// `5bc350`: the flight model's damage bits from the systems damage flags (bit n = flag n, docs/damage.md
/// §5.2). Engine (cut out 2 / on fire 16 / permanent 22, right 3 / 17 / 23) → 4 left, 8 right; afterburner 8 /
/// 9 → 0x80 / 0x100; a single-engine jet sets both bits from the left flags and never reads the right ones.
/// Fuel leak 10 → 0x40, hydraulics 18 → 0x10, total flight control 24 → 0x20 (0x10 / 0x20 are not read by
/// the thrust; the stick and the spin read flags 18 / 24 directly).
pub fn damage_bits(sys: u32, twin: bool) -> u32 {
    let f = |n: u32| sys & (1 << n) != 0;
    let mut b = 0;
    if f(2) || f(16) || f(22) {
        b |= if twin { 4 } else { 0xc };
    }
    if twin && (f(3) || f(17) || f(23)) {
        b |= 8;
    }
    if f(8) {
        b |= if twin { 0x80 } else { 0x180 };
    }
    if twin && f(9) {
        b |= 0x100;
    }
    if f(10) {
        b |= 0x40;
    }
    if f(18) {
        b |= 0x10;
    }
    if f(24) {
        b |= 0x20;
    }
    b
}

fn second_order_step(ch: &mut Angle, t: f64, target: f32, b: f32, k: f32) {
    let (pos, rate) = ch.sample(t);
    let pos = wrap(pos);
    let rmax = ch.max_rate;
    let err = wrap(target as f64 - pos) as f32;
    let damp = if rate.abs() <= PI { b * rate * rmax } else { 0.5 * b * rate * rmax };
    let r = if rmax > 0.0 { (err / PI * k / rmax - damp).clamp(-1.0, 1.0) * rmax } else { 0.0 };
    ch.set(t, pos, r);
}

fn sign(x: f32) -> f32 {
    if x > 0.0 {
        1.0
    } else if x < 0.0 {
        -1.0
    } else {
        0.0
    }
}

/// Euler attitude (pitch, roll, heading), radians; heading clockwise from north.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Euler {
    pub pitch: f32,
    pub roll: f32,
    pub heading: f32,
}

impl Euler {
    /// Body axes (forward, right wing, up) in world ENU — the matrix `5ba740` builds.
    pub fn basis(&self) -> (V3, V3, V3) {
        let (sp, cp) = (self.pitch as f64).sin_cos();
        let (sh, ch) = (self.heading as f64).sin_cos();
        let (sr, cr) = (self.roll as f64).sin_cos();
        let fwd = [cp * sh, cp * ch, sp];
        let right_h = [ch, -sh, 0.0];
        let up0 = cross(right_h, fwd);
        (fwd, add(scale(right_h, cr), scale(up0, -sr)), add(scale(up0, cr), scale(right_h, sr)))
    }
}

/// The autopilot's view of the FM (see [`Aircraft::ap_view`]); ENU metres, rad, rad/s.
#[derive(Debug, Clone, Copy)]
pub struct ApView {
    pub t: f64,
    pub pos: V3,
    pub vel: V3,
    pub acc: V3,
    pub speed: f32,
    pub att: Euler,
    /// (pitch rate of the flight path, roll rate, turn rate), rad/s.
    pub rates: [f32; 3],
    pub max_roll_rate: f32,
    pub max_g: f32,
    pub min_g: f32,
    pub on_ground: bool,
    pub gear_down: bool,
    pub flaps: bool,
    pub brakes: bool,
    pub type_code: u32,
    pub gear_clearance: f32,
    pub ground_height: f32,
    /// Stick-centre line (P+0x144, P+0x180, P+0x184): centre g = V < v ? a·V + b : 1.
    pub stick_centre: [f32; 3],
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Controls {
    /// Stick roll −1..1 (right positive).
    pub stick_x: f32,
    /// Stick pitch −1..1 (**pull positive**, i.e. nose up).
    pub stick_y: f32,
    /// Rudder −1..1 (right positive).
    pub rudder: f32,
    /// Requested throttle 0..1: 0.74 = military, 0.75..0.875 = AB1, ≥0.875 = AB2. The effective
    /// throttle follows the original's AB rules (§15.8), see [`State::throttle`].
    pub throttle: f32,
    /// 0..1 (flap lever; the ramp goes to 0.29275, ×0.33 for the F-16).
    pub flaps: f32,
    pub gear_down: bool,
    /// Speed brakes in the air, wheel brakes on the ground (one key in the original).
    pub brakes: bool,
}

impl Default for Controls {
    fn default() -> Self {
        Self { stick_x: 0.0, stick_y: 0.0, rudder: 0.0, throttle: MILITARY, flaps: 0.0, gear_down: false, brakes: false }
    }
}

/// Why the jet was destroyed (§15.6).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Crash {
    /// Touchdown outside the landing limits (nose-down, roll, sink rate or slope; `5bb7d0`).
    Landing,
    /// Touchdown or rolling on water (`S+0x2c8 = 4`).
    Water,
    /// Rough ground above 25.7 m/s.
    RoughGround,
    /// Better physics only: sink rate beyond the real gear's limit.
    SinkRate,
    /// Better physics only: nose too high at touchdown (tail strike).
    TailStrike,
}

impl Crash {
    pub fn name(&self) -> &'static str {
        match self {
            Crash::Landing => "landing",
            Crash::Water => "water",
            Crash::RoughGround => "rough ground",
            Crash::SinkRate => "sink rate",
            Crash::TailStrike => "tail strike",
        }
    }
}

/// Mission start (`FUN_005a5820`, §15.6.4).
#[derive(Debug, Clone, Copy)]
pub struct Start {
    /// ENU metres.
    pub position: V3,
    /// Radians. `pitch` is used on the ground only (in the air it comes from the velocity).
    pub pitch: f32,
    pub roll: f32,
    pub heading: f32,
    /// ENU m/s. The horizontal speed is re-aimed along the heading; vz is kept.
    pub velocity: V3,
    /// See [`Aircraft::start_is_airborne`].
    pub airborne: bool,
    /// Ground start only: the engine runs only within 100 m of the runway start point.
    pub engine_on: bool,
}

/// "Better physics" options (docs/flight-model.md §10): each one an opt-in fix of an original quirk
/// or a missing effect. All off (the default) = the original.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct BetterPhysics {
    /// Neutral-stick 1 g hold on the flight path (γ) with the thrust's lift share, not the nose pitch.
    pub flight_path_hold: bool,
    /// Forces decomposed with α(t) and β(t) in both updates (not the α target / commanded β).
    pub force_angles: bool,
    /// Airborne start: lift ramps at m·g instead of MaxWeight·g (no up-jolt).
    pub start_lift: bool,
    /// Airborne start: RPM at the start throttle's value instead of 70 % (no AB light-up delay).
    pub start_rpm: bool,
    /// Airborne start: α at its trim value instead of 0 (no nose rise in the first second).
    pub start_alpha: bool,
    /// Landing check: 4 m/s sink limit, 15° tail strike, the current attitude.
    pub landing_limits: bool,
    /// Spin: "No spins" blocks, 1.2 s entry, descent with drag, velocity kept at recovery, s1 = 0 recoverable.
    pub spin_fixes: bool,
    /// F-16 / Lavi: FLCS deep stall with MPO rocking recovery (the original never lets them depart).
    pub fbw_departure: bool,
    /// Lift-ramp rate factor floored at 1 % below 20 m/s (the original's grows again below 18 m/s).
    pub lift_rate_floor: bool,
    /// No reversed roll command below Veff ≈ 9.5 m/s.
    pub low_speed_roll: bool,
    /// No ×4 vertical lift from a strong nose-wheel side force.
    pub no_nose_wheel_lift: bool,
    /// Ground effect on the induced drag.
    pub ground_effect: bool,
    /// On the ground the idle thrust falls with speed (ram drag) and no ×0.8 ground drag: taxi speeds near 30 kt, not 90+.
    pub ground_idle: bool,
}

impl BetterPhysics {
    /// Stable ids (snake_case) and English labels, in menu order.
    pub const OPTIONS: [(&'static str, &'static str); 13] = [
        ("flight_path_hold", "1 g hold keeps the flight path (no slow climb/dive with neutral stick)"),
        ("force_angles", "Forces use the current angle of attack and sideslip"),
        ("start_lift", "Airborne start without the upward jolt"),
        ("start_rpm", "Airborne start with the engine at speed (afterburner at once)"),
        ("start_alpha", "Airborne start trimmed (no nose rise)"),
        ("landing_limits", "Realistic landing limits: sink rate and tail strike"),
        ("spin_fixes", "Realistic spins: entry, descent and recovery"),
        ("fbw_departure", "F-16 / Lavi deep stall (fly-by-wire departure, rocking recovery)"),
        ("lift_rate_floor", "No faster lift changes below 20 m/s"),
        ("low_speed_roll", "No reversed roll at very low speed"),
        ("no_nose_wheel_lift", "No lift jump from nose-wheel steering"),
        ("ground_effect", "Ground effect (less induced drag near the ground)"),
        ("ground_idle", "Realistic idle thrust on the ground (taxi speed)"),
    ];

    pub fn none() -> Self {
        Self::default()
    }

    pub fn all() -> Self {
        let mut b = Self::default();
        for (id, _) in Self::OPTIONS {
            b.set(id, true);
        }
        b
    }

    fn field(&mut self, id: &str) -> Option<&mut bool> {
        Some(match id {
            "flight_path_hold" => &mut self.flight_path_hold,
            "force_angles" => &mut self.force_angles,
            "start_lift" => &mut self.start_lift,
            "start_rpm" => &mut self.start_rpm,
            "start_alpha" => &mut self.start_alpha,
            "landing_limits" => &mut self.landing_limits,
            "spin_fixes" => &mut self.spin_fixes,
            "fbw_departure" => &mut self.fbw_departure,
            "lift_rate_floor" => &mut self.lift_rate_floor,
            "low_speed_roll" => &mut self.low_speed_roll,
            "no_nose_wheel_lift" => &mut self.no_nose_wheel_lift,
            "ground_effect" => &mut self.ground_effect,
            "ground_idle" => &mut self.ground_idle,
            _ => return None,
        })
    }

    /// Sets the option `id`; false if there is no such option.
    pub fn set(&mut self, id: &str, on: bool) -> bool {
        self.field(id).map(|f| *f = on).is_some()
    }

    pub fn get(&self, id: &str) -> Option<bool> {
        let mut c = *self;
        c.field(id).map(|f| *f)
    }
}

/// Everything the cockpit, HUD and renderer need, sampled at the current time.
#[derive(Debug, Clone, Copy)]
pub struct State {
    pub time: f64,
    pub position: V3,
    pub velocity: [f32; 3],
    pub speed: f32,
    pub mach: f32,
    /// Body axes in world (ENU) coordinates.
    pub forward: V3,
    pub right: V3,
    pub up: V3,
    pub pitch: f32,
    pub roll: f32,
    /// Radians clockwise from north, 0..2π.
    pub heading: f32,
    pub alpha: f32,
    pub beta: f32,
    /// Load factor (lift / weight).
    pub g: f32,
    /// Engine RPM, percent.
    pub rpm: f32,
    /// Effective throttle (`S+0x2dc`): stays at 0.74 while the afterburner lights up.
    pub throttle: f32,
    pub afterburner: u8,
    pub thrust_n: f32,
    pub fuel_kg: f32,
    pub mass_kg: f32,
    /// Stall / departure latch active (no lift for up to 3 s).
    pub stalled: bool,
    pub buffet: bool,
    /// The lift rule's stall / limit measure `dragX` (`S+0x2f0`, getter 0x12): 1.2 when stalled or too
    /// slow, (g − limit) / MaxG when the G is limited; drives the AoA warning tone (docs/sound.md).
    pub drag_x: f32,
    pub over_g: bool,
    pub on_ground: bool,
    pub spinning: bool,
    /// Better physics only: F-16 / Lavi deep stall (§10.1). `alpha` then shows the stalled AoA (~60°).
    pub deep_stall: bool,
    /// Gear ramp: 0 = down and locked … 1.569 = up.
    pub gear: f32,
    pub crashed: Option<Crash>,
    /// Landings so far: +1 at each touchdown with the gear down that passes the landing check (the mission's
    /// landed handler fires on each, v1.1; the flag is re-armed at lift-off).
    pub landings: u32,
}

/// In/out values of the mode hooks (`5aab90`): acceleration, lift targets, roll command.
struct ModeIo {
    acc: V3,
    lift: f32,
    lift_noflap: f32,
    p_cmd: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    /// `veh+0xc6c`.
    Normal,
    /// `veh+0xc70` (§15.5).
    Spin,
    /// Better physics only: the fly-by-wire jets' deep stall (§10.1). Not in the original.
    DeepStall,
}

struct LiftOut {
    lift: f32,
    lift_noflap: f32,
    drag_x: f32,
    stall: bool,
    vib: bool,
}

#[derive(Clone)]
pub struct Aircraft {
    pub params: Params,
    pub envelope: Envelope,
    t: f64,
    controls: Controls,
    /// Effective throttle `S+0x2dc` and a pending afterburner request (time, value) (§15.8).
    throttle: f32,
    ab_request: Option<(f64, f32)>,
    /// Rudder `S+0x2ec`: only taken while airborne (the handler drops it on the ground, §7).
    rudder: f32,
    axes: [Axis; 3],
    roll: Angle,
    alpha: Angle,
    /// α gains set at 1 Hz (`S+0x250` B, `S+0x254` K) and the target `S+0x258`.
    alpha_b: f32,
    alpha_k: f32,
    /// Sideslip β `S+0x260`: a second-order channel of the α class (v1.1; v1.0 a rate ramp clamped to
    /// ±MaxBeta), its gains B `S+0x290`, K `S+0x294` and the command β_cmd `S+0x298` (§15.2.6).
    beta: Angle,
    beta_b: f32,
    beta_k: f32,
    beta_cmd: f32,
    /// Nose-wheel yaw rate `S+0x2a8` (ramp at |BetaRate|, limits ±MaxBeta).
    nose_yaw: Ramp,
    lift: Ramp,
    lift_aoa: Ramp,
    rpm: Ramp,
    fuel: Ramp,
    flaps: Ramp,
    gear: Ramp,
    brakes: Ramp,
    /// Left-wing unit vector (`S+0x08`) and the roll and Euler angles saved with it (`5aa330`).
    wing_left: V3,
    wing_roll: f64,
    saved: Euler,
    thrust: f32,
    afterburner: u8,
    drag: f32,
    mass: f32,
    /// Last Lift `dragX` (`S+0x2f0`).
    drag_x: f32,
    /// Stall latch `S+0x2f8` (None = −1, unset).
    stall_time: Option<f64>,
    buffet: bool,
    mode: Mode,
    /// Spin channels: yaw angle `S+0xb0`, pitch `S+0xe0`, roll `S+0x100`, arm timer `S+0x128`.
    spin_yaw: Angle,
    spin_pitch: Ramp,
    spin_roll: Ramp,
    spin_arm: Option<f64>,
    /// Deep stall (BP): entry time (phase origin of the rocking) and the pitch-rocking amplitude (rad). The
    /// mean pitch / roll / heading reuse the spin channels.
    ds_t0: f64,
    ds_amp: Ramp,
    /// Engine running (`S+0x1d0`): off at a ground start away from the runway start point, turned on
    /// by any throttle event (§8, §15.8); on at an airborne start.
    pub engine_on: bool,
    /// "Better physics" options (§10, §15.11); none = the original. Change them with [`Aircraft::set_better`]
    /// so the start options apply.
    pub better: BetterPhysics,
    /// Preferences (§15.7, pref instance `DAT_00699424`). Single player: all apply.
    pub no_stalls: bool,
    pub no_spins: bool,
    /// Default on in the original.
    pub easy_landing: bool,
    /// The autopilot is flying the landing (NAV to a land waypoint): the landing check uses the original's
    /// limits even with better physics `landing_limits`, which the 1998 autopilot's touchdown exceeds.
    pub ap_landing: bool,
    pub invulnerable: bool,
    pub no_crashes: bool,
    pub unlimited_fuel: bool,
    /// The pilot's systems damage (docs/damage.md §5.2): bit n = damage flag n (controller `+0x3d8+0xc+4n`,
    /// 1..24), read by the flight model through `5bc350` (thrust), `59f3d0` (stick) and `5aab90` (spin).
    pub damage: u32,
    /// `S+0x420` (§15.1 step 16): 75 < V < 150 m/s and the stick pulled more than 0.7, set at each aero update;
    /// read by getter 0x14 for the wingtip vortex trails (`FUN_004da090`, docs/damage.md §6.4).
    pub vortex: bool,
    /// Twin-engine jet (controller +0x24): the left / right engine flags are separate (`5bc350`).
    pub twin: bool,
    /// AI pilot (docs/ai.md, docs/flight-model.md §14/§15 "ai"): the control-loop mode the FM reads through
    /// `FUN_005c89f0(veh+0xc50)`; 0 = no control loop (the player flying by hand).
    pub ai_mode: u8,
    /// Sim time the AI's control loop took over (`[veh+0xc50]+0x10`, crash immunity "aiOld").
    pub ai_since: f64,
    /// The FM's AI "team" test: the jet is not on the player's side (`FUN_004a4cf0`; no player: side 2 / 3).
    pub ai_team: bool,
    /// Preferences AI level (pref +0x50): 0 Rookie, 1 Normal, 2 Expert (the default).
    pub ai_level: u8,
    /// The AI jet's damage fraction is ≤ 0.1 (`dmgObj+0x10`, crash immunity "lowDmg").
    pub ai_low_damage: bool,
    /// Current fuel flow (kg/s), from the last aero update.
    pub fuel_flow: f32,
    /// External stores (docs/weapons.md "Weight and drag"): extra mass `S+0x424` (kg, added to the empty
    /// weight with the fuel), stores drag index of the left wing (stations A–E, `S+0x42c`) and the right
    /// wing (E–I, `S+0x428`), already ×1e-4, added to CD; right − left is the asymmetry that biases the
    /// β command. Set by the host at the start and after every release; read at the next aero update.
    pub stores_mass: f32,
    pub stores_di_left: f32,
    pub stores_di_right: f32,
    // Load-time derived constants.
    cl0: f32,
    cl_alpha: f32,
    stick_centre_v: f32,
    stick_centre_a: f32,
    stick_centre_b: f32,
    next_aero: f64,
    next_accel: f64,
    pub on_ground: bool,
    /// Terrain elevation under the aircraft, supplied by the host every frame.
    pub ground_height: f32,
    /// Height of the aircraft origin above the wheels' contact point (the model's `height`
    /// helper, F-16 1.69 m), so the jet rests on its gear.
    pub gear_clearance: f32,
    /// Terrain under the wheels, supplied by the host: `nz/|n|` of the surface normal (1 = flat),
    /// water, rough ground (terrain flags `4024b0`, §15.6.2).
    pub ground_normal_z: f32,
    pub ground_water: bool,
    pub ground_rough: bool,
    /// Drag chute deployed (adds `Params::chute_cd`, 0 in the original set).
    pub drag_chute: bool,
    /// Destroyed (§15.6); the simulation stops.
    pub crashed: Option<Crash>,
    /// Horizontal direction the aircraft points on the ground (unit, ENU).
    ground_dir: V3,
    /// The mission's "landed" flag (player object `+0xe0`, `5bb9f0`): set by a touchdown with the gear down
    /// that passes the landing check, cleared at lift-off (v1.1; v1.0 never cleared it). `landings` counts
    /// its 0 → 1 edges, i.e. the calls of the landed handler (`440f90`).
    landed: bool,
    landings: u32,
    /// Motion 0x16 scripted heading turn (mode `veh+0xc78`, `5a8d40`), the AI's taxi pivots.
    pivot: Option<Pivot>,
}

/// A flat 3 s turn about a point 30 m to the side of the turn (docs/ai.md §8.2).
#[derive(Debug, Clone, Copy)]
struct Pivot {
    t0: f64,
    s0: f32,
    target: f32,
    rate: f32,
    t_end: f32,
    p: V3,
    r: f64,
    v0: f32,
}

impl Pivot {
    fn heading(&self, t: f64) -> f32 {
        let tau = ((t - self.t0) as f32).clamp(0.0, 3.5);
        let psi = if tau < self.t_end { self.s0 + self.rate * tau } else { self.target };
        psi.clamp(-2.0 * PI, 2.0 * PI)
    }
}

impl Aircraft {
    /// The original's air/ground start decision (`FUN_005a5820`): airborne ⇔ z > 800 m and not at a
    /// base (within 5 km horizontally and 15 m vertically of the nearest airbase).
    pub fn start_is_airborne(z: f32, near_base: bool) -> bool {
        z > AIRBORNE_START_Z && !near_base
    }

    /// Airborne start at `position` (ENU), `heading` (rad, clockwise from north), `speed` (m/s),
    /// wings level.
    pub fn new(params: Params, envelope: Envelope, position: V3, heading: f32, speed: f32) -> Self {
        let (s, c) = (heading as f64).sin_cos();
        let v = speed as f64;
        Self::start(params, envelope, Start { position, pitch: 0.0, roll: 0.0, heading, velocity: [v * s, v * c, 0.0], airborne: true, engine_on: true })
    }

    /// Mission start (`FUN_005a5820`, §15.6.4).
    pub fn start(params: Params, envelope: Envelope, st: Start) -> Self {
        let p = &params;
        let (cl0, cl_alpha, stick_centre_v, stick_centre_a, stick_centre_b) = Self::derive(p, &envelope);
        let (sh, ch) = (st.heading as f64).sin_cos();
        let vh = (st.velocity[0].powi(2) + st.velocity[1].powi(2)).sqrt();
        let (vel, euler) = if st.airborne {
            let v = [vh * sh, vh * ch, st.velocity[2]];
            let pitch = (v[2] / dot(v, v).sqrt().max(1e-9)).clamp(-1.0, 1.0).asin() as f32;
            (v, Euler { pitch, roll: st.roll, heading: st.heading })
        } else {
            ([0.0; 3], Euler { pitch: st.pitch, roll: 0.0, heading: st.heading })
        };
        let lift_lo = p.max_mass * p.min_g_m1 * G;
        let lift_hi = p.max_mass * p.max_g_m1 * G;
        let mass = p.empty_mass + p.fuel_mass;
        // Lift ramps: MaxWeight·g in the air (value = target, `5ad8a0`); 0 on the ground.
        // Better physics: m·g (the MaxWeight value gives a short up-jolt until the first update).
        let lift0 = if !st.airborne { 0.0 } else { p.max_mass * G };
        let controls = if st.airborne {
            Controls { throttle: MILITARY, ..Default::default() }
        } else {
            Controls { throttle: 0.0, flaps: 1.0, gear_down: true, brakes: true, ..Default::default() }
        };
        let (_, right, _) = euler.basis();
        let mut ac = Self {
            t: 0.0,
            controls,
            throttle: controls.throttle,
            ab_request: None,
            rudder: 0.0,
            axes: [Axis::new(st.position[0], vel[0] as f32), Axis::new(st.position[1], vel[1] as f32), Axis::new(st.position[2], vel[2] as f32)],
            roll: Angle::new(euler.roll as f64, p.roll_accel.abs(), p.stop_accel.abs(), p.max_roll_rate.abs()),
            alpha: Angle::new(0.0, p.alpha_start_accel.abs(), p.alpha_stop_accel.abs(), p.max_alpha_rate.abs()),
            alpha_b: p.alpha_beta,
            alpha_k: p.alpha_k,
            // SetType `5b1f30`: rates ±BetaRate, accelerations |RudderStart/StopAccel|, B / K raw; placement
            // `5a4d40`: pos = rate = 0 (the immediate aero update below re-bases it at t = 0).
            beta: Angle::new(0.0, p.rudder_start_accel.abs(), p.rudder_stop_accel.abs(), p.beta_rate.abs()),
            beta_b: p.rudder_beta,
            beta_k: p.rudder_k,
            beta_cmd: 0.0,
            nose_yaw: Ramp::new(0.0, -p.max_beta.abs(), p.max_beta.abs()),
            lift: Ramp::new(lift0, lift_lo, lift_hi),
            lift_aoa: Ramp::new(lift0, lift_lo, lift_hi),
            rpm: Ramp::new(if st.airborne { 70.0 } else { 0.0 }, 0.0, 100.0),
            fuel: Ramp::new(p.fuel_mass, 0.0, p.fuel_mass),
            flaps: Ramp::new(if st.airborne { 0.0 } else { FLAPS_MAX }, 0.0, FLAPS_MAX),
            gear: Ramp::new(if st.airborne { GEAR_UP } else { 0.0 }, 0.0, GEAR_UP),
            brakes: Ramp::new(if st.airborne { 0.0 } else { BRAKES_MAX }, 0.0, BRAKES_MAX),
            wing_left: scale(right, -1.0),
            wing_roll: euler.roll as f64,
            saved: euler,
            thrust: 0.0,
            afterburner: 0,
            drag: 0.0,
            mass,
            drag_x: 0.0,
            stall_time: None,
            buffet: false,
            mode: Mode::Normal,
            spin_yaw: Angle::new(0.0, (0.4 * p.roll_accel).abs(), (0.2 * p.stop_accel).abs(), (0.4 * p.max_roll_rate).abs()),
            spin_pitch: Ramp::new(0.0, -PI / 2.0, PI / 2.0),
            spin_roll: Ramp::new(0.0, -PI, PI),
            spin_arm: None,
            ds_t0: 0.0,
            ds_amp: Ramp::new(DS_AMP0, 0.0, DS_AMP_MAX),
            engine_on: st.airborne || st.engine_on,
            better: BetterPhysics::none(),
            no_stalls: false,
            no_spins: false,
            easy_landing: true,
            ap_landing: false,
            invulnerable: false,
            no_crashes: false,
            unlimited_fuel: false,
            damage: 0,
            vortex: false,
            twin: false,
            ai_mode: 0,
            ai_since: 0.0,
            ai_team: false,
            ai_level: 2,
            ai_low_damage: true,
            fuel_flow: 0.0,
            stores_mass: 0.0,
            stores_di_left: 0.0,
            stores_di_right: 0.0,
            cl0,
            cl_alpha,
            stick_centre_v,
            stick_centre_a,
            stick_centre_b,
            next_aero: AERO_PERIOD,
            next_accel: ACCEL_PERIOD,
            on_ground: !st.airborne,
            ground_height: f32::NEG_INFINITY,
            gear_clearance: 0.0,
            ground_normal_z: 1.0,
            ground_water: false,
            ground_rough: false,
            drag_chute: false,
            crashed: None,
            ground_dir: [sh, ch, 0.0],
            landed: false,
            landings: 0,
            pivot: None,
            params,
            envelope,
        };
        // The RPM ramp starts at its value (70 → 70 in the air, 0 on the ground), rate 15.
        ac.rpm.set(0.0, ac.rpm.sample(0.0), RPM_RATE);
        // Immediate aero update (5a4200); the timers then run at 1 s / 0.2 s.
        ac.aero_update();
        ac
    }

    /// Load-time derived constants (§1): CL at α=0 and dCL/dα from the 1 g / max g minimum
    /// speeds, and the stick-centre shift line (P.170 / P.174).
    fn derive(p: &Params, envelope: &Envelope) -> (f32, f32, f32, f32, f32) {
        let alt = 330.0;
        let v1 = envelope.vmin(alt, 1.0);
        let vg = envelope.vmin(alt, p.max_g_m1 + 1.0);
        let (qs1, qs2) = (q_s(alt, v1, p.wing_area), q_s(alt, vg, p.wing_area));
        let w = p.empty_mass * G;
        let cl0 = w / qs2;
        let cl_alpha = (w - qs1 * cl0) / (qs1 * p.max_pos_alpha);
        let stick_centre_v = envelope.vmin(3048.0, p.start_move_stick_center_g);
        let (a, b) = if 10.0 - stick_centre_v != 0.0 {
            let a = (p.map_center_stick - 1.0) / (10.0 - stick_centre_v);
            (a, p.map_center_stick - a * 10.0)
        } else {
            (0.0, 0.0)
        };
        (cl0, cl_alpha, stick_centre_v, a, b)
    }

    /// Engine on/off (motion @5a2890). Off stops the engine at once: no thrust, RPM 0.
    pub fn set_engine(&mut self, on: bool) {
        if on == self.engine_on {
            return;
        }
        self.engine_on = on;
        if !on {
            self.rpm.reset(self.t, 0.0);
        }
        self.aero_update();
    }

    /// All "better physics" options on or off (the game's single switch).
    pub fn set_better_physics(&mut self, on: bool) {
        self.set_better(if on { BetterPhysics::all() } else { BetterPhysics::none() });
    }

    /// One "better physics" option by id ([`BetterPhysics::OPTIONS`]); false if there is no such option.
    pub fn set_better_option(&mut self, id: &str, on: bool) -> bool {
        let mut b = self.better;
        let ok = b.set(id, on);
        self.set_better(b);
        ok
    }

    /// Sets the "better physics" options. At an airborne start (t = 0) the start options also re-initialise
    /// what they change (§15.6.4): `start_lift` puts the lift ramps at m·g (original MaxWeight·g), `start_rpm` the
    /// RPM at the start throttle's value (original 70 %), `start_alpha` α at its trim value (original 0).
    /// Switching them off later does not undo that.
    pub fn set_better(&mut self, b: BetterPhysics) {
        let old = self.better;
        self.better = b;
        if self.t != 0.0 || self.on_ground {
            return;
        }
        let mut changed = false;
        if b.start_lift && !old.start_lift {
            let w = self.mass * G;
            for r in [&mut self.lift, &mut self.lift_aoa] {
                let (target, rate) = (r.target(), r.rate());
                r.place(0.0, w, target, rate);
            }
            changed = true;
        }
        if b.start_rpm && !old.start_rpm {
            let target = self.rpm.target();
            self.rpm.reset(0.0, target);
        }
        if b.start_alpha && !old.start_alpha {
            let alt = self.axes[2].sample(0.0).0 as f32;
            let (_, v) = self.velocity_at(0.0);
            let at = self.alpha_target(self.lift_aoa.target(), q_s(alt, v, self.params.wing_area));
            self.alpha.set(0.0, at as f64, 0.0);
            changed = true;
        }
        if changed || b != old {
            self.aero_update(); // the start acceleration used the old lift sample / α / rules
        }
    }

    pub fn controls(&self) -> Controls {
        self.controls
    }

    fn flaps_on_target(&self) -> f32 {
        FLAPS_MAX * if self.params.type_code == 100 { 0.33 } else { 1.0 }
    }

    /// Applies new controls; like the original, any change is a control event with an immediate
    /// aero update. The throttle follows motion 2 (`FUN_0059f7d0`, §15.8).
    pub fn set_controls(&mut self, c: Controls) {
        if self.crashed.is_some() {
            return;
        }
        // Motion 1 (`59f3d0`): hydraulics damage (18) leaves a quarter of the stick, total flight control
        // (24) none; the rudder is not affected.
        let stick_k = if self.damage & (1 << 24) != 0 {
            0.0
        } else if self.damage & (1 << 18) != 0 {
            0.25
        } else {
            1.0
        };
        let c = Controls {
            stick_x: c.stick_x.clamp(-1.0, 1.0) * stick_k,
            stick_y: c.stick_y.clamp(-1.0, 1.0) * stick_k,
            rudder: c.rudder.clamp(-1.0, 1.0),
            throttle: c.throttle.clamp(0.0, 1.0),
            flaps: c.flaps.clamp(0.0, 1.0),
            ..c
        };
        let old = self.controls;
        if c == old {
            return;
        }
        let t = self.t;
        self.controls = c;
        if c.throttle != old.throttle {
            self.throttle_event(c.throttle);
        }
        if c.flaps != old.flaps {
            let target = c.flaps * self.flaps_on_target();
            self.flaps.set(t, target, CONTROL_RATE);
        }
        if c.gear_down != old.gear_down {
            self.gear.set(t, if c.gear_down { 0.0 } else { GEAR_UP }, CONTROL_RATE);
        }
        if c.brakes != old.brakes {
            self.brakes.set(t, if c.brakes { BRAKES_MAX } else { 0.0 }, CONTROL_RATE);
        }
        // Motion 5 stores the rudder only while airborne; on the ground it keeps its last value.
        if !self.on_ground {
            self.rudder = c.rudder;
        }
        self.aero_update();
    }

    /// Throttle event (motion 2 `59f7d0`, player): the first one starts the engine; moves under 0.015 are
    /// ignored; any other move cancels a pending afterburner request (v1.1; v1.0 kept the older one), and
    /// crossing into AB sets 0.74 and applies the request once the RPM would be at 100 %.
    fn throttle_event(&mut self, new: f32) {
        let ai = self.ai();
        if !ai {
            self.engine_on = true;
        }
        // The AI's moves all count; it lights the afterburner at once (no RPM delay).
        if if ai { new == self.throttle } else { (new - self.throttle).abs() < THROTTLE_DEADBAND } {
            return;
        }
        self.engine_on = true;
        if !ai {
            self.ab_request = None;
        }
        if !ai && self.throttle < AB && new >= AB {
            self.throttle = MILITARY;
            let delay = ((100.0 - self.rpm.sample(self.t)) / RPM_RATE).max(0.0) as f64;
            self.ab_request = Some((self.t + delay, new));
        } else {
            self.throttle = new.clamp(0.0, 1.0);
        }
    }

    /// Advances the simulation to `t + dt`, running the 1 Hz / 5 Hz updates and the afterburner
    /// timer on schedule. Nothing moves after a crash.
    pub fn step(&mut self, dt: f64) {
        let end = self.t + dt;
        if self.pivot.is_some() {
            // The pose comes from the pivot (mode c78); the axes are re-based when it ends.
            self.t = end;
            return;
        }
        loop {
            if self.crashed.is_some() {
                return;
            }
            let ab = self.ab_request.map_or(f64::INFINITY, |r| r.0);
            let next = self.next_accel.min(self.next_aero).min(ab);
            if next > end {
                break;
            }
            self.t = next;
            if ab <= self.next_aero.min(self.next_accel) {
                let (_, value) = self.ab_request.take().unwrap();
                self.throttle = value.clamp(0.0, 1.0);
                self.aero_update();
            } else if self.next_aero <= self.next_accel {
                self.aero_update();
                self.next_aero += AERO_PERIOD;
            } else {
                self.accel_update();
                self.next_accel += ACCEL_PERIOD;
            }
        }
        self.t = end;
    }

    // --- sampling ------------------------------------------------------------------------------

    /// Velocity and |v| (not capped: the 1 Hz path).
    fn velocity_at(&self, t: f64) -> (V3, f32) {
        if let Some(pv) = &self.pivot {
            // Slot 3 of mode c78: the entry speed along the heading (not the arc's own speed).
            let h = pv.heading(t) as f64;
            return ([pv.v0 as f64 * h.sin(), pv.v0 as f64 * h.cos(), 0.0], pv.v0);
        }
        let v = [self.axes[0].sample(t).1 as f64, self.axes[1].sample(t).1 as f64, self.axes[2].sample(t).1 as f64];
        (v, dot(v, v).sqrt() as f32)
    }

    fn position_at(&self, t: f64) -> V3 {
        if let Some(pv) = &self.pivot {
            let h = pv.heading(t) as f64;
            return [pv.p[0] - pv.r * h.cos(), pv.p[1] + pv.r * h.sin(), pv.p[2]];
        }
        [self.axes[0].sample(t).0, self.axes[1].sample(t).0, self.axes[2].sample(t).0]
    }

    fn latched(&self, t: f64) -> bool {
        self.stall_time.is_some_and(|t0| t - t0 <= STALL_LATCH)
    }

    /// `cfg[7]`: the gear ramp exactly at its extended end.
    fn gear_flag(&self, t: f64) -> bool {
        self.gear.sample(t).abs() < 1e-5
    }

    /// `cfg[6]`: on the ground any brake value; in the air the ramp finished at its maximum.
    fn brake_flag(&self, t: f64) -> f32 {
        let b = &self.brakes;
        let on = if self.on_ground {
            b.sample(t).abs() >= 1e-5
        } else {
            b.finished(t) && (b.target() - b.max).abs() < 0.01 * (b.max - b.min)
        };
        if on { 1.0 } else { 0.0 }
    }

    /// A control loop flies the jet (`FUN_005c89f0() != 0`).
    fn ai(&self) -> bool {
        self.ai_mode != 0
    }

    /// The player's "No crashes" / "Invulnerable" preferences (never for an AI jet).
    fn cheat(&self) -> bool {
        !self.ai() && (self.invulnerable || self.no_crashes)
    }

    /// Crash immunity `5abef0` (§15.6.3): the preferences, or an AI jet in mode 9 with fuel, or one whose
    /// control loop has run > 3.5 s with fuel and damage ≤ 0.1 (not in mode 0x11 when on the enemy team).
    fn immune(&self) -> bool {
        if self.cheat() {
            return true;
        }
        if !self.ai() {
            return false;
        }
        let fuel = self.fuel.sample(self.t) > 0.0;
        let old = self.t - self.ai_since > AI_OLD;
        let team_ok = !(self.ai_team && self.ai_mode == 0x11);
        (self.ai_mode == 9 && fuel) || (old && fuel && self.ai_low_damage && team_ok)
    }

    /// Attitude of the current mode (mode object slot 0).
    fn attitude(&self, t: f64) -> Euler {
        self.attitude_ab(t, true)
    }

    /// `with_ab` false: the flight-path attitude (α = β = 0), what `5a68f0` gives the control loops.
    fn attitude_ab(&self, t: f64, with_ab: bool) -> Euler {
        if let Some(pv) = &self.pivot {
            return Euler { pitch: 0.0, roll: 0.0, heading: wrap(pv.heading(t) as f64) as f32 };
        }
        if self.mode == Mode::DeepStall {
            // BP deep stall: mean attitude from the spin channels plus pitch rocking, wing rock, yaw wander.
            let osc = |period: f64| ((t - self.ds_t0) * std::f64::consts::TAU / period).sin() as f32;
            let pitch = self.spin_pitch.sample(t) + self.ds_amp.sample(t) * osc(DS_PERIOD);
            return Euler {
                pitch: pitch.clamp(-PI / 2.0 + 1e-3, PI / 2.0 - 1e-3),
                roll: wrap((self.spin_roll.sample(t) + DS_ROLL_AMP * osc(DS_ROLL_PERIOD)) as f64) as f32,
                heading: wrap(self.spin_yaw.sample(t).0 + (DS_YAW_AMP * osc(DS_YAW_PERIOD)) as f64) as f32,
            };
        }
        if self.mode == Mode::Spin {
            // 5b8b70: pitch / roll ramps, heading = yaw angle.
            return Euler {
                pitch: wrap(self.spin_pitch.sample(t) as f64) as f32,
                roll: wrap(self.spin_roll.sample(t) as f64) as f32,
                heading: wrap(self.spin_yaw.sample(t).0) as f32,
            };
        }
        let (v, speed) = self.velocity_at(t);
        if self.on_ground {
            // Ground attitude: level; the heading follows the velocity (§14.5), else the last heading.
            let f = if speed > 0.5 { norm([v[0], v[1], 0.0]) } else { self.ground_dir };
            return Euler { pitch: 0.0, roll: 0.0, heading: f[0].atan2(f[1]) as f32 };
        }
        // 5b9530 (§15.3): velocity, roll about the saved body nose axis (v1.1; v1.0 about the velocity), α
        // about the (left) wing, β about w × f.
        let mut f = if speed > 0.5 { scale(v, 1.0 / speed as f64) } else { self.saved.basis().0 };
        let mut w = self.wing_left;
        let dphi = wrap(self.roll.sample(t).0 - self.wing_roll);
        if dphi != 0.0 {
            w = rotate(w, self.saved.basis().0, dphi);
        }
        let alpha = if with_ab { wrap(self.alpha.sample(t).0) } else { 0.0 };
        if alpha != 0.0 {
            f = rotate(f, w, -alpha);
        }
        let beta = if with_ab { self.beta.sample(t).0 } else { 0.0 };
        if beta != 0.0 {
            let n = norm(cross(w, f));
            f = rotate(f, n, wrap(beta));
        }
        let heading = if f[0] == 0.0 && f[1] == 0.0 { 0.0 } else { f[0].atan2(f[1]) };
        let pitch = f[2].clamp(-1.0, 1.0).asin();
        // Roll from the raw w in the heading/pitch frame (no re-orthogonalisation).
        let right_h = [heading.cos(), -heading.sin(), 0.0];
        let up_l = cross(right_h, f);
        let mut roll = (-dot(w, right_h)).clamp(-1.0, 1.0).acos();
        if dot(w, up_l) < 0.0 {
            roll = -roll;
        }
        Euler { pitch: pitch as f32, roll: wrap(roll) as f32, heading: heading as f32 }
    }

    /// `5aa330`: saves the Euler angles and the left-wing vector for the attitude sampler.
    fn save_attitude(&mut self, att: Euler) {
        self.saved = att;
        self.wing_left = scale(att.basis().1, -1.0);
        self.wing_roll = att.roll as f64;
    }

    // --- aero ----------------------------------------------------------------------------------

    /// Thrust (N), RPM (0..1), fuel flow (kg/s), afterburner stage (§4.1).
    /// `no_ab`: the original passes !HasAfterBurner in the air but "AI" (false for the player) on
    /// the ground (§14.2), so the player's ground roll always uses the AB curve.
    fn thrust_at(&self, alt: f32, mach: f32, no_ab: bool) -> (f32, f32, f32, u8) {
        let p = &self.params;
        // 5a70f0 step 4: bit 2 = no fuel, then the damage bits (`5bc350`).
        let flags = damage_bits(self.damage, self.twin) | if self.fuel.sample(self.t) < 1e-5 { 2 } else { 0 };
        let mut thr = if flags & 2 != 0 { 0.0 } else { self.throttle };
        let (mut thrust, mut rpm, mut ff, mut stage) = (0.0, 0.0, 0.0, 0);
        // Both engines dead (a single-engine jet: either flag), the engine off or no fuel: nothing, but a
        // fuel leak still drains (below).
        if flags & 0xc != 0xc && self.engine_on && flags & 2 == 0 {
            // Both afterburners damaged (a single-engine jet: flag 8): the throttle stops at military.
            if flags & 0x180 == 0x180 && thr >= 0.75 {
                thr = 0.74;
            }
            let stage_of = |thr: f32| if thr < 0.75 { 0 } else if thr < 0.875 { 1 } else { 2 };
            let (mut k, st) = if !no_ab {
                if thr < 0.75 {
                    // BP ground_idle: the idle share loses its ram drag, ×(1 − V/Vj) (net thrust ṁ·(Vj − V)).
                    let v = mach * crate::atmosphere::air(alt).sound;
                    let idle = if self.on_ground && self.better.ground_idle { 0.05 * (1.0 - v / IDLE_VJ).max(0.0) } else { 0.05 };
                    (idle + 0.743_243_2 * thr, 0)
                } else if thr < 0.875 {
                    (0.875, 1)
                } else {
                    (1.0, 2)
                }
            } else {
                ((thr - 0.2) * 1.25, stage_of(thr))
            };
            // One engine of a twin dead: half the thrust (the dry fuel-flow test below sees the halved k).
            if flags & 0xc != 0 {
                k *= 0.5;
            }
            let a = (alt * 5e-5).clamp(0.0, 1.0);
            let m = (mach / 1.2).clamp(0.0, 1.0);
            let lerp = |t: f32, x: f32, y: f32| x + (y - x) * t;
            // Real data set: the dry range scaled to the engine's military / max-AB ratio (1 = original).
            let kt = if !no_ab && st == 0 { k * p.dry_thrust } else { k };
            let tk = |mach_i: usize, alt_i: usize| lerp(kt, p.thrust[mach_i][alt_i][0], p.thrust[mach_i][alt_i][1]);
            thrust = lerp(a, lerp(m, tk(0, 0), tk(1, 0)), lerp(m, tk(0, 1), tk(1, 1))) * LBF;
            rpm = 0.6 + 0.4 * thr * 1.351_351_4;
            ff = thr * p.fuel_flow_max;
            if k <= 0.6 {
                ff *= p.dry_fuel_frac;
            }
            stage = st;
        }
        // Fuel leak (damage 10): a quarter of the full-throttle flow on top, engine running or not.
        if flags & 0x40 != 0 {
            ff += 0.25 * p.fuel_flow_max;
        }
        if self.unlimited_fuel {
            ff = 0.0;
        }
        (thrust, rpm, ff, stage)
    }

    /// `(L − e4·qS)/(e8·qS)`.
    fn alpha_of_lift(&self, lift: f32, qs: f32) -> f32 {
        if qs > 0.0 { (lift - self.cl0 * qs) / (self.cl_alpha * qs) } else { 0.0 }
    }

    /// α target `5b4c60`: 0 on the ground, else clamped to [MaxNegAlpha, min(MaxPosAlpha, LimitAlphaVisual)].
    fn alpha_target(&self, lift_aoa: f32, qs: f32) -> f32 {
        let p = &self.params;
        if self.on_ground {
            return 0.0;
        }
        self.alpha_of_lift(lift_aoa, qs).min(p.max_pos_alpha.min(p.limit_alpha_visual)).max(p.max_neg_alpha)
    }

    /// Lift `5b4470` (§14.3), shared by the air and ground branches.
    #[allow(clippy::too_many_arguments)]
    fn lift_fn(&self, v: f32, alt: f32, mass: f32, att: Euler, latched: bool, gamma: f32, alpha_now: f32, flaps: f32) -> LiftOut {
        let p = &self.params;
        // An AI jet stalls unless it is an Expert (AI level 2) on the enemy team.
        let ai = self.ai();
        let b_stall = if ai { !(self.ai_level == 2 && self.ai_team) } else { !self.no_stalls };
        if latched && b_stall {
            return LiftOut { lift: 0.0, lift_noflap: 0.0, drag_x: 1.2, stall: false, vib: false };
        }
        let (mut drag_x, mut stall, mut lim) = (0.0, false, 0.0);
        let centre = if v < self.stick_centre_v { self.stick_centre_a * v + self.stick_centre_b } else { 1.0 };
        let sp = self.controls.stick_y;
        let mut g = if sp > 0.0 { centre + sp * p.max_g_m1 } else { centre + (-sp) * ((p.min_g_m1 + 1.0) - centre) };
        if (g - 1.0).abs() < 1e-5 && att.roll.abs() < 10f32.to_radians() {
            // Neutral stick: 1 g hold, cos(pitch)/cos(roll) in the original. The jet slowly
            // dives with it at high speed (α < 0 there tilts the thrust down); "better physics"
            // holds the flight path instead and subtracts the thrust's lift share.
            g = if self.better.flight_path_hold {
                gamma.cos() / att.roll.cos() - self.thrust * alpha_now.sin() / (mass * G)
            } else {
                att.pitch.cos() / att.roll.cos()
            };
        }
        let g_cmd = g;
        let mut code = 3;
        if p.use_flight_limits {
            match self.envelope.g_limit(alt, v, g) {
                r @ (GLimit::Stall | GLimit::TooHigh) => {
                    code = if r == GLimit::Stall { 0 } else { 2 };
                    lim = -1.0;
                    drag_x = 1.2;
                    if b_stall {
                        g = 0.0;
                        stall = true;
                    } else {
                        g = if code == 0 { g_cmd.min(0.4) } else { 0.4 };
                    }
                }
                GLimit::None => lim = g,
                GLimit::Max(l) => {
                    code = 4;
                    lim = l;
                    if g_cmd > 0.0 {
                        let mut r = g_cmd;
                        if lim <= g_cmd {
                            drag_x = (g_cmd - lim) / (p.max_g_m1 + 1.0);
                            r = lim;
                        }
                        if !b_stall {
                            r = r.max(0.4);
                            if g_cmd < 0.4 {
                                r = g_cmd;
                            }
                        }
                        g = r;
                    } else {
                        g = g_cmd.max(lim);
                    }
                }
            }
        }
        // A Rookie enemy AI pulls softer above 4.3 g (single player).
        if ai && self.ai_level == 0 && self.ai_team && g > 4.3 {
            g = 4.0 + 0.02 * g * g;
        }
        let lift_noflap = g * mass * G;
        // Vibration needs `P+0x84` (vibration allowed = "No stalls" off) and a player.
        let vib = lim <= p.start_vibs_g && code == 4 && g_cmd > 0.0 && !self.no_stalls && !ai;
        let mut lift = lift_noflap;
        if v < 125.0 {
            lift += lift_noflap.abs() * p.flaps_lift_coef * flaps * FLAPS_K;
        }
        LiftOut { lift, lift_noflap, drag_x, stall, vib }
    }

    /// Better physics: ground effect on the induced drag, McCormick's `φ = (16h/b)² / (1 + (16h/b)²)`
    /// (h = wing height above the terrain, b = span): 0.5 at h ≈ b/16, 0.8 at b/8, 0.94 at b/4. Not in the
    /// original (no ground effect at all).
    fn ground_effect(&self, alt: f32) -> f32 {
        let h = (alt - self.ground_height).max(0.0);
        let r = 16.0 * h / self.params.wing_span.max(1.0);
        if !r.is_finite() || r > 64.0 {
            return 1.0;
        }
        (r * r / (1.0 + r * r)).max(0.05)
    }

    /// Nose-wheel yaw target (7a20 arg 19): clamp(stickX · V · K / 74.53, ±K), 0 with the gear not
    /// fully down or below 1e-4. The rudder is ignored on the ground.
    fn nose_wheel_yaw(&self, v: f32, gear: bool) -> f32 {
        if !gear {
            return 0.0;
        }
        let yaw = (self.controls.stick_x * v * NOSE_K / 74.53).clamp(-NOSE_K, NOSE_K);
        if yaw.abs() < 1e-4 { 0.0 } else { yaw }
    }

    /// Stall latch `5a9e60`: a stall starts it when unset; an update more than 3 s after the start
    /// clears it (even if still stalled).
    fn latch(&mut self, t: f64, stall: bool, vib: bool) {
        match self.stall_time {
            None if stall => self.stall_time = Some(t),
            Some(t0) if t - t0 > STALL_LATCH => self.stall_time = None,
            _ => {}
        }
        self.buffet = vib;
    }

    /// 1 Hz / event update `5a70f0` (§15.1): thrust, lift, drag, the acceleration (at once), the
    /// latch and modes, lift ramps, α, β / nose wheel, roll target.
    fn aero_update(&mut self) {
        if self.crashed.is_some() {
            return;
        }
        let t = self.t;
        let p = self.params.clone();
        let c = self.controls;
        let alt = self.axes[2].sample(t).0 as f32;
        let (vel, v) = self.velocity_at(t); // not capped here
        let air = air(alt);
        let mach = v / air.sound;
        let qs = q_s(alt, v, p.wing_area);
        let beta_s = self.beta.sample(t).0 as f32;
        let alpha_s = wrap(self.alpha.sample(t).0) as f32;
        let att = self.attitude(t);
        let flaps = self.flaps.sample(t);
        let gear = self.gear_flag(t);
        let brakes = self.brake_flag(t);
        let fuel = self.fuel.sample(t);
        // m = EmptyWeight + m_x, m_x = S+0x424 + fuel (§4).
        let mass = p.empty_mass + self.stores_mass + fuel;
        let ground = self.on_ground;
        let latched = self.latched(t);
        let gamma = if v > 1.0 { (vel[2] / v as f64).clamp(-1.0, 1.0).asin() as f32 } else { 0.0 };

        // noAB: the ground call passes "ai"; airborne !HasAfterBurner, or an AI outside modes 7 / 8.
        let ai = self.ai();
        let no_ab = if ground { ai } else { !p.has_afterburner || (ai && !matches!(self.ai_mode, 7 | 8)) };
        let (mut thrust, rpm, ff, stage) = self.thrust_at(alt, mach, no_ab);
        // The ground call passes latched = 0 (§14.3).
        let lo = self.lift_fn(v, alt, mass, att, latched && !ground, gamma, alpha_s, flaps);
        let (mut lift, mut lift_noflap, drag_x, mut stall) = (lo.lift, lo.lift_noflap, lo.drag_x, lo.stall);
        let c_f = p.flaps_lift_coef * flaps * FLAPS_K;
        let easy = self.cheat();
        if ground {
            // 5bac40: half the lift, flaps added again, gated by speed / pull and gear.
            thrust = thrust.max(0.0);
            lift *= 0.5;
            lift += lift.abs() * c_f;
            if !((v > 74.53 || c.stick_y > 0.5) && (gear || ai || self.easy_landing || easy)) {
                lift = 0.0;
                lift_noflap = 0.0;
                stall = false;
            }
        }
        // Drag (5b4800); the ground call passes α = 0.
        let alpha_d = if stall || ground { 0.0 } else { self.alpha_of_lift(lift_noflap, qs).clamp(p.max_neg_alpha, p.max_pos_alpha) };
        let n = lift / (mass * G);
        let cl = if qs > 0.0 { alpha_d.cos() * mass * n * G / qs } else { 0.0 };
        let mut k = 1.0 / (std::f32::consts::PI * p.wing_span * p.wing_span / p.wing_area * 0.85);
        if self.better.ground_effect {
            k *= self.ground_effect(alt);
        }
        // An AI jet's gear has no drag (5b4800: cfg[7]·GearDI·(ai ? 0 : 1)).
        let gear_f = if gear && !ai { 1.0 } else { 0.0 };
        let stores_di = self.stores_di_left + self.stores_di_right;
        let mut cd = p.plane_di + brakes * p.speed_brakes_di + gear_f * p.gear_di + p.flaps_di * flaps * FLAPS_K + stores_di + k * cl * cl;
        if p.wave_drag > 0.0 && mach > 0.9 {
            cd += p.wave_drag * ((mach - 0.9) / 0.3).min(1.0);
        }
        if self.drag_chute {
            cd += p.chute_cd;
        }
        let mut drag = cd * qs;
        let mut yaw_nw = 0.0;
        if ground {
            // v1.1: the AI's wheel brakes ×4 (v1.0 ×2).
            let mut mu = brakes * p.wheel_brake_di * if ai { AI_BRAKE } else { 1.0 } + FRIC1;
            if !gear && !ai && !easy {
                mu = 20.0; // belly
            }
            drag = (drag + 0.5 * mu * (mass * G - lift)).max(0.0);
            if v > 1.0 && !self.better.ground_idle {
                drag *= ROLL_DRAG;
            }
            yaw_nw = self.nose_wheel_yaw(v, gear);
        }
        // 5b4910: β_cmd = (ru + 10·asym)·MaxBeta, asym = S+0x428 − S+0x42c (the spin tick passes 0).
        let beta_cmd = (self.rudder + 10.0 * self.stores_asym()) * p.max_beta;
        let p_cmd = if ground { 0.0 } else { p.max_roll_rate * c.stick_x };

        self.thrust = thrust;
        self.afterburner = stage;
        self.drag = drag;
        self.mass = mass;

        // Acceleration at once (5b3ef0 @5a784b) with the lift ramp sampled before its new target,
        // the sampled α and the commanded β (better physics: β(t)); on the ground the raw nose-wheel yaw.
        let lift_old = self.lift.sample(t);
        let acc = if ground {
            self.ground_acc(t, lift_old, v, yaw_nw, att)
        } else {
            let beta = if self.better.force_angles { beta_s } else { beta_cmd };
            self.air_acc(att, lift_old, v, alpha_s, beta)
        };
        self.latch(t, stall, lo.vib);
        let mut io = ModeIo { acc, lift, lift_noflap, p_cmd };
        self.mode_hook(t, drag_x, v, beta_s, att, &mut io, true);
        self.drag_x = drag_x;

        // Lift ramps; rate factor 1 % at 20 m/s … 100 % at 220, no floor (|negative| below 18 m/s, so the
        // lift changes faster the slower the jet: at 0 m/s as fast as at 20). BP: floor at 1 %.
        let floor = if self.better.lift_rate_floor { 0.01 } else { f32::NEG_INFINITY };
        let rate = |r: f32| if v >= 220.0 { r } else { r * (0.01 + 0.99 * (v - 20.0) / 200.0).max(floor) };
        self.lift.set(t, io.lift, rate(p.g_rate) * mass * G);
        self.lift_aoa.set(t, io.lift_noflap, rate(p.g_rate_for_aoa) * mass * G);

        // α dynamics 5aa3a0: target from the new Lnoflap, gains f(V) set here only.
        let f = if v >= 220.0 { 1.0 } else { (0.004995 * v - 0.0989).max(0.001) };
        self.alpha.start_accel = (p.alpha_start_accel * f).abs();
        self.alpha.stop_accel = (p.alpha_stop_accel * f).abs();
        self.alpha.max_rate = (p.max_alpha_rate * f).abs();
        self.alpha_b = p.alpha_beta * f;
        self.alpha_k = p.alpha_k * f;
        let at = self.alpha_target(io.lift_noflap, qs);
        self.alpha_step(t, at);

        if !ground {
            self.beta_update(t, v, beta_cmd);
            self.nose_yaw.rebase(t);
        } else {
            // v1.1: on the ground the β channel steps with its stored gains and command (`5ae4c0`/`5ae240`).
            self.nose_yaw.set(t, yaw_nw, p.beta_rate);
            self.beta_step(t);
        }
        for (axis, a) in self.axes.iter_mut().zip(io.acc) {
            axis.set(t, a as f32);
        }
        self.save_attitude(att);
        // Roll: re-base on the attitude roll, new target k·p_cmd (no lower clamp on k).
        let veff = ((-1.305e-5 + 3.1825e-9 * v) * alt + 1.0017) * v - 3.122;
        let mut kroll = if veff < 220.0 { 0.00475 * veff - 0.045 } else { 1.0 };
        if self.better.low_speed_roll {
            kroll = kroll.max(0.0); // BP: no reversed roll below Veff ≈ 9.5 m/s
        }
        self.roll.set(t, att.roll as f64, kroll * io.p_cmd);
        for r in [&mut self.flaps, &mut self.gear, &mut self.brakes] {
            r.rebase(t);
        }
        self.fuel.set(t, 0.0, ff);
        self.fuel_flow = ff;
        self.vortex = v > 75.0 && v < 150.0 && c.stick_y > 0.7;
        self.rpm.set(t, 100.0 * rpm, RPM_RATE);
    }

    /// α channel target rate (`5aa3a0` / `5ae4c0`) toward `alpha_target` with the stored gains.
    fn alpha_step(&mut self, t: f64, alpha_target: f32) {
        second_order_step(&mut self.alpha, t, alpha_target, self.alpha_b, self.alpha_k);
    }

    /// β update `5aa700` (v1.1, §15.2.6): gains from V, then one step of the α law toward `beta_cmd`. No
    /// ±MaxBeta clamp and no damping term unless the data has RudderBeta (none does).
    fn beta_update(&mut self, t: f64, v: f32, beta_cmd: f32) {
        let p = &self.params;
        let br = p.beta_rate;
        // k = max(V·slope + b, 0.25·BetaRate) / BetaRate with slope/b from SetType (0x8453e8/ec: 0.0025·BetaRate, 0).
        let k = if v < BETA_V && br != 0.0 { (v * 0.0025 * br).max(0.25 * br) / br } else { 1.0 };
        // Re-base first with the old limits (5adc70, target BetaRate·k), then store the new gains.
        let (pos, _) = self.beta.sample(t);
        self.beta.set(t, pos, br * k);
        self.beta.max_rate = br * k;
        self.beta.start_accel = (p.rudder_start_accel * k).abs();
        self.beta.stop_accel = (p.rudder_stop_accel * k).abs();
        let centre = if beta_cmd.abs() <= p.max_beta * 0.1 { 1.5 } else { 1.0 };
        self.beta_k = p.rudder_k * centre * k;
        self.beta_b = p.rudder_beta * k;
        self.beta_cmd = beta_cmd;
        self.beta_step(t);
    }

    /// One β step toward the stored command with the stored gains (`5ae4c0` + `5ae240`).
    fn beta_step(&mut self, t: f64) {
        second_order_step(&mut self.beta, t, self.beta_cmd, self.beta_b, self.beta_k);
    }

    /// 5 Hz update `5a4230` (§15.1): transitions, then forces from the current channel values.
    fn accel_update(&mut self) {
        let t = self.t;
        self.transitions(t);
        if self.crashed.is_some() {
            return;
        }
        let p = &self.params;
        let alt = self.axes[2].sample(t).0 as f32;
        let (_, v) = self.velocity_at(t);
        let v = v.min(1200.0); // slot 0x3c caps the speed
        let qs = q_s(alt, v, p.wing_area);
        let beta_air = self.beta.sample(t).0 as f32;
        // On the ground the beta slot carries the nose-wheel yaw ramp (5bb9f0).
        let beta_s = if self.on_ground { self.nose_yaw.sample(t) } else { beta_air };
        if self.mode == Mode::DeepStall {
            let att = self.attitude(t);
            let mut io = ModeIo { acc: [0.0; 3], lift: 0.0, lift_noflap: 0.0, p_cmd: 0.0 };
            self.deep_stall_hook(t, att, &mut io, false);
            if self.mode == Mode::DeepStall {
                self.beta_update(t, v, self.rudder * self.params.max_beta);
                return;
            }
            // Recovered: this tick continues as a normal one.
        }
        let att = self.attitude(t);
        if self.mode == Mode::Spin {
            let mut io = ModeIo { acc: [0.0; 3], lift: 0.0, lift_noflap: 0.0, p_cmd: 0.0 };
            self.spin_hook(t, self.drag_x, v, beta_air, att, &mut io, false);
            // v1.1: the β command (asym = 0 in the spin) and the β update also run in the spin tick.
            self.beta_update(t, v, self.rudder * self.params.max_beta);
            return;
        }
        self.save_attitude(att);
        let alpha_t = self.alpha_target(self.lift_aoa.sample(t), qs);
        let lift = self.lift.sample(t);
        let mut acc = if self.on_ground {
            self.ground_acc(t, lift, v, beta_s, att)
        } else {
            // The 5 Hz force uses the α target (better physics: α(t)).
            let alpha = if self.better.force_angles { wrap(self.alpha.sample(t).0) as f32 } else { alpha_t };
            self.air_acc(att, lift, v, alpha, beta_s)
        };
        let mut stop = false;
        if self.on_ground {
            // Stop rule (5 Hz only): a deceleration that would reverse the motion within 0.2 s
            // stops the jet (all three velocities 0).
            let (fwd, _, _) = att.basis();
            let (vel, _) = self.velocity_at(t);
            let a_fwd = dot(acc, fwd);
            if a_fwd < 0.0 && dot(vel, fwd) + 0.2 * a_fwd < 0.0 {
                acc = add(acc, scale(fwd, -a_fwd));
                stop = true;
            }
            if v > 0.5 {
                self.ground_dir = fwd;
            }
        }
        for (i, axis) in self.axes.iter_mut().enumerate() {
            if stop {
                let (p, _) = axis.sample(t);
                axis.set_state(t, p, 0.0, acc[i] as f32);
            } else {
                axis.set(t, acc[i] as f32);
            }
        }
        self.roll.reset_angle(t, att.roll as f64);
        self.alpha_step(t, alpha_t);
        let beta_cmd = (self.rudder + 10.0 * self.stores_asym()) * self.params.max_beta;
        self.beta_update(t, v, beta_cmd);
    }

    /// Airborne acceleration `5b4930` (§15.2.2): forces in the body frame of the Euler attitude,
    /// decomposed with the given α / β.
    fn air_acc(&self, att: Euler, lift: f32, v: f32, alpha: f32, beta: f32) -> V3 {
        let (fwd, right, up) = att.basis();
        let (thrust, drag, mass) = (self.thrust, self.drag, self.mass);
        let fy = thrust + lift * alpha.sin() - drag * alpha.cos() * beta.cos();
        let fz = lift * alpha.cos() + drag * alpha.sin() * beta.cos();
        let fx = drag * beta.sin() + 5.0 * v * v * beta;
        let force = add(add(scale(fwd, fy as f64), scale(up, fz as f64)), scale(right, fx as f64));
        let mut acc = scale(force, 1.0 / mass as f64);
        acc[2] -= G as f64;
        acc
    }

    /// Ground acceleration (FUN_005bb060, §14.5): level attitude along the heading; the nose wheel
    /// pushes sideways (Fc), which scrubs speed and can multiply the vertical lift by 4.
    fn ground_acc(&self, _t: f64, lift: f32, v: f32, yaw: f32, att: Euler) -> V3 {
        let (fwd, right, up) = att.basis();
        let m = self.mass;
        let fc = match self.params.nose_wheel {
            // Real data set: geometric steering from the pedals, limited by the tyres' grip.
            Some(nw) if self.gear_flag(self.t) && v > 0.1 => {
                let rate = v * (self.controls.rudder * nw.max_angle).tan() / nw.wheelbase;
                m * (v * rate).clamp(-nw.max_lateral, nw.max_lateral)
            }
            Some(_) => 0.0,
            None => {
                let mut r = if yaw == 0.0 { 5.0 } else { v / (G * yaw.tan()) };
                if r.abs() < 2.0 {
                    r = 2.0 * r.signum();
                }
                let mut fc = if v > 2.0 && yaw != 0.0 { v * v * m / r } else { 0.0 };
                fc *= if v < 25.736 { 1.0 } else { (0.1 - 0.000_777_118 * v).abs() };
                fc
            }
        };
        let mut lz = lift;
        // Original quirk (5bb060 @5bb157): a strong side force multiplies the vertical lift by 4.
        // Not physical, so the real data set leaves it out.
        // Better physics leaves it out too.
        if self.params.nose_wheel.is_none() && !self.better.no_nose_wheel_lift && fc.abs() > 0.1 * lz && v > 20.5889 {
            lz *= 4.0;
        }
        let (thrust, drag) = (self.thrust, self.drag);
        let fx = if v < 0.01 && thrust < drag { 0.0 } else { thrust - drag - fc.abs() * 0.0625 };
        let f = add(add(scale(right, fc as f64), scale(fwd, fx as f64)), scale(up, lz as f64));
        [f[0] / m as f64, f[1] / m as f64, ((f[2] - (m * G) as f64).max(0.0)) / m as f64]
    }

    // --- departure modes ------------------------------------------------------------------------

    /// Better physics: the fly-by-wire jets (F-16, Lavi) get the FLCS deep stall instead of the spin.
    fn fbw_departure(&self) -> bool {
        self.better.fbw_departure && matches!(self.params.type_code, 100 | 140 | 1000)
    }

    /// Mode hook (`5aab90`'s place in both updates): the deep stall (BP, FBW jets) or the spin.
    #[allow(clippy::too_many_arguments)]
    fn mode_hook(&mut self, t: f64, drag_x: f32, v: f32, beta: f32, att: Euler, io: &mut ModeIo, aero: bool) {
        if self.mode == Mode::DeepStall {
            self.deep_stall_hook(t, att, io, aero);
        } else if self.fbw_departure() {
            if aero && self.mode == Mode::Normal {
                self.deep_stall_entry(t, v, att);
            }
        } else {
            self.spin_hook(t, drag_x, v, beta, att, io, aero);
        }
    }

    /// Deep-stall entry (BP, aero updates): the FLCS AoA limiter holds ~25° AoA until the airspeed is gone.
    /// Stalled (the latch, §15.2.4: below the envelope's lowest speed) with the nose ≥ 30° up and below the
    /// 1 g minimum speed — a zoom climb run out of airspeed — the nose falls through to the deep-stall
    /// trim. "No spins" or "No stalls" prevent it.
    fn deep_stall_entry(&mut self, t: f64, v: f32, att: Euler) {
        if self.no_spins || self.no_stalls || self.on_ground || !self.latched(t) || att.pitch < DS_ENTRY_PITCH {
            return;
        }
        let alt = self.axes[2].sample(t).0 as f32;
        if v >= self.envelope.vmin(alt, 1.0) {
            return;
        }
        let p = &self.params;
        self.mode = Mode::DeepStall;
        self.spin_arm = None;
        self.ds_t0 = t;
        self.ds_amp.reset(t, DS_AMP0);
        self.spin_pitch.place(t, att.pitch.clamp(-PI / 2.0, PI / 2.0), att.pitch.clamp(-PI / 2.0, PI / 2.0), DS_ATT_RATE);
        self.spin_roll.place(t, att.roll.clamp(-PI, PI), 0.0, 0.5 * DS_ATT_RATE);
        self.spin_yaw = Angle::new(att.heading as f64, (0.4 * p.roll_accel).abs(), (0.2 * p.stop_accel).abs(), (0.4 * p.max_roll_rate).abs());
        self.spin_yaw.set(t, att.heading as f64, 0.0);
    }

    /// Deep-stall update (both updates). The jet hangs at the trim AoA: normal force `CN·qS` (lift N·cos α,
    /// drag N·sin α) plus thrust along the nose and gravity, so the path settles near −60° at the speed
    /// where N = W. The nose rocks in pitch; a full forward stick alone does not recover (the tail has no
    /// nose-down power left), but rocking the stick in phase with the pitch motion (MPO) pumps the rocking
    /// up until the nose falls below the FLCS AoA limit, where the FLCS takes over again.
    fn deep_stall_hook(&mut self, t: f64, att: Euler, io: &mut ModeIo, aero: bool) {
        if self.on_ground {
            self.mode = Mode::Normal; // touchdown (the landing check already ran)
            return;
        }
        let (vel, v) = self.velocity_at(t);
        let gamma = if v > 1.0 { (vel[2] / v as f64).clamp(-1.0, 1.0).asin() as f32 } else { -PI / 2.0 };
        let alpha = att.pitch - gamma;
        if self.ds_amp.sample(t) >= DS_EXIT_AMP && alpha < DS_EXIT_ALPHA {
            // Recovered: the velocity is kept; α continues from the nose-to-path angle.
            self.mode = Mode::Normal;
            self.save_attitude(att);
            self.alpha.set(t, alpha as f64, 0.0);
            self.roll.set(t, att.roll as f64, 0.0);
            self.stall_time = None;
            self.ds_amp.reset(t, DS_AMP0);
            return;
        }
        // Mean attitude: the nose DS_ALPHA above the path; wings toward level; heading held.
        self.spin_pitch.set(t, (gamma + DS_ALPHA).clamp(-PI / 4.0, 85f32.to_radians()), DS_ATT_RATE);
        self.spin_roll.set(t, 0.0, 0.5 * DS_ATT_RATE);
        let (h, _) = self.spin_yaw.sample(t);
        self.spin_yaw.reset_angle(t, h);
        // Rocking: the stick in phase with the pitch rate pumps it, against the phase damps it.
        let rising = ((t - self.ds_t0) * std::f64::consts::TAU / DS_PERIOD).cos().signum() as f32;
        let pump = self.controls.stick_y * rising;
        if pump > 0.5 {
            self.ds_amp.set(t, DS_AMP_MAX, DS_PUMP * pump);
        } else if pump < -0.5 {
            self.ds_amp.set(t, DS_AMP0, -DS_PUMP * pump);
        } else {
            self.ds_amp.set(t, DS_AMP0, DS_DECAY);
        }
        // Forces.
        let (fwd, _, up) = att.basis();
        let m = self.mass as f64;
        let mut acc = scale(fwd, self.thrust as f64 / m);
        acc[2] -= G as f64;
        let mut n = 0.0;
        if v > 0.5 {
            let alt = self.axes[2].sample(t).0 as f32;
            n = DS_CN * q_s(alt, v, self.params.wing_area);
            let vh = scale(vel, 1.0 / v as f64);
            let l = add(up, scale(vh, -dot(up, vh)));
            let l = if dot(l, l) > 1e-9 { norm(l) } else { [0.0; 3] };
            let f = add(scale(vh, -(n * DS_ALPHA.sin()) as f64), scale(l, (n * DS_ALPHA.cos()) as f64));
            acc = add(acc, scale(f, 1.0 / m));
        }
        io.lift = n;
        io.lift_noflap = n;
        io.p_cmd = 0.0;
        io.acc = acc;
        if !aero {
            for (axis, a) in self.axes.iter_mut().zip(acc) {
                axis.set(t, a as f32);
            }
        }
    }

    // --- spin (§15.5) --------------------------------------------------------------------------

    /// Mode hook `5aab90`: spin entry (aero update, normal mode) and the spin update (both updates).
    #[allow(clippy::too_many_arguments)]
    fn spin_hook(&mut self, t: f64, drag_x: f32, v: f32, beta: f32, att: Euler, io: &mut ModeIo, aero: bool) {
        let p = self.params.clone();
        let max_beta = p.max_beta.abs();
        if self.mode == Mode::Normal {
            if !aero || matches!(p.type_code, 100 | 140 | 1000) {
                return; // the F-16 and the Lavi never spin (better physics: the deep stall, `mode_hook`)
            }
            let qual = beta.abs() >= 0.8 * max_beta && drag_x > 0.57;
            // Total flight control damage (24) enters the spin whatever β, dragX and the preferences say.
            let forced = self.damage & (1 << 24) != 0;
            if self.better.spin_fixes {
                // BP: "No spins" blocks entry; the condition must hold for 1.2 s.
                if (self.no_spins || !qual) && !forced {
                    self.spin_arm = None;
                    return;
                }
                let t0 = *self.spin_arm.get_or_insert(t);
                if t <= t0 + 1.2 && !forced {
                    return;
                }
            } else {
                // Original: the arm step resets itself, so the second consecutive qualifying update
                // enters; with "No spins" the arm step is skipped and the first one enters.
                self.spin_arm = if self.spin_arm.is_none() && qual && !self.no_spins { Some(t) } else { None };
                if (t <= self.spin_arm.unwrap_or(-1.0) + 1.2 || !qual) && !forced {
                    return;
                }
            }
            self.mode = Mode::Spin;
            let s = sign(beta);
            self.spin_yaw = Angle::new(att.heading as f64, (0.4 * p.roll_accel).abs(), (0.2 * p.stop_accel).abs(), (0.4 * p.max_roll_rate).abs());
            self.spin_yaw.set(t, att.heading as f64, s * PI / 2.0);
            let rate = (0.05 * p.max_roll_rate).abs();
            self.spin_pitch.place(t, att.pitch.clamp(-PI / 2.0, PI / 2.0), -30f32.to_radians(), rate);
            self.spin_roll.place(t, att.roll.clamp(-PI, PI), 0.1, rate);
            return;
        }
        // Update.
        let tau_axis = (t - self.axes[0].t0()) as f32;
        let yaw_rate = if self.better.spin_fixes { self.spin_yaw.sample(t).1 } else { self.spin_yaw.sample_tau(tau_axis).1 };
        let s1 = sign(yaw_rate);
        let s2 = sign(beta);
        if s1 == -s2 && s1 != 0.0 {
            // Opposite rudder slows the rotation (0 at β = −1.1·MaxBeta·s1; v1.0 0.9).
            let (pos, _) = self.spin_yaw.sample(t);
            self.spin_yaw.set(t, pos, s1 * PI / 2.0 + beta * PI / (SPIN_SLOPE * max_beta));
        }
        let recovering = (s1 > 0.0 && beta <= -0.9 * max_beta) || (s1 < 0.0 && beta >= 0.9 * max_beta);
        let mut stay = !self.on_ground && (!recovering || drag_x >= 0.1);
        if self.better.spin_fixes && s1 == 0.0 {
            stay = !self.on_ground && drag_x >= 0.1; // BP: no rotation → recoverable
        }
        if stay {
            io.lift = 0.0;
            io.lift_noflap = 0.0;
            io.p_cmd = 0.0;
            if self.better.spin_fixes {
                // BP: drag bleeds the horizontal speed; the descent settles near 65 m/s.
                let (vel, _) = self.velocity_at(t);
                let vh = [vel[0], vel[1], 0.0];
                let d = (self.drag / self.mass) as f64;
                let h = if dot(vh, vh) > 1e-6 { scale(norm(vh), -d) } else { [0.0; 3] };
                let vz = vel[2].min(0.0);
                io.acc = [h[0], h[1], -(G as f64) + G as f64 * (vz / 65.0).powi(2)];
            } else {
                io.acc = [0.0, 0.0, (0.04 * v - G).min(0.0) as f64];
            }
            let (pos, _) = self.spin_yaw.sample(t);
            self.spin_yaw.reset_angle(t, pos);
            self.spin_pitch.rebase(t);
            self.spin_roll.rebase(t);
            // v1.1: the X/Y/Z axes are re-based too, keeping their acceleration (Z through `5adae0`, which
            // also clamps the height to the axis limits, not modelled).
            for axis in self.axes.iter_mut() {
                let a = axis.accel();
                axis.set(t, a);
            }
            return;
        }
        // Exit (@5ab6e7): velocity := nose rotated back by α and β, times V.
        let (f, right, _) = att.basis();
        self.save_attitude(att);
        let w = scale(right, -1.0);
        if !self.better.spin_fixes {
            let u = norm(cross(f, w));
            let alpha = self.alpha.sample(t).0;
            let f2 = rotate(rotate(f, u, beta as f64), w, alpha);
            for (i, axis) in self.axes.iter_mut().enumerate() {
                let (pos, _) = axis.sample(t);
                let a = axis.accel();
                axis.set_state(t, pos, (f2[i] * v as f64) as f32, a);
            }
            io.acc[0] = 0.0;
            io.acc[1] = 0.0;
        }
        self.roll.reset_angle(t, att.roll as f64);
        self.spin_arm = None;
        io.p_cmd = s1 * 0.1;
        self.mode = Mode::Normal;
    }

    // --- ground contact (§14.6, §15.6) ---------------------------------------------------------

    /// Landing check `5bb7d0` (§15.6.1) at touchdown; `vz` = vertical speed now. None = OK.
    fn landing_check(&self, t: f64, vz: f32) -> Option<Crash> {
        if self.immune() {
            return None;
        }
        let bp = self.better.landing_limits && !self.ap_landing;
        // The original uses the Euler angles saved at the last update; better physics the current ones.
        let att = if bp { self.attitude(t) } else { self.saved };
        let (mut lp, mut lr, mut lv) = (5f32.to_radians(), 10f32.to_radians(), -40.0f32);
        // BP: a real gear's sink limit (~13 ft/s) and a tail-strike limit.
        let mut lt = 15f32.to_radians();
        if bp {
            lv = -4.0;
        }
        if self.easy_landing {
            lp *= 2.0;
            lr *= 2.0;
            lv *= 2.0;
            lt *= 2.0;
        }
        if self.gear.sample(t).abs() >= 1e-5 {
            lp *= 0.2;
            lr *= 0.2;
            lv *= 0.25;
        }
        let slope_ok = self.ground_normal_z.abs() >= 0.984_807_7;
        if att.pitch >= -lp && att.roll.abs() <= lr && vz >= lv && slope_ok {
            if bp && att.pitch > lt {
                return Some(Crash::TailStrike);
            }
            return None;
        }
        Some(if bp && vz < lv && att.pitch >= -lp && att.roll.abs() <= lr && slope_ok { Crash::SinkRate } else { Crash::Landing })
    }

    /// Touchdown / lift-off / rolling checks (FUN_005bb9f0, §14.6, §15.6.2), at the start of every
    /// 5 Hz tick.
    fn transitions(&mut self, t: f64) {
        let clear = (self.ground_height + self.gear_clearance) as f64;
        let (z, vz) = self.axes[2].sample(t);
        if !self.on_ground {
            if z > clear {
                return;
            }
            // Touchdown: the landing check, vz := 0 (acceleration kept), Z onto the ground, aero
            // update (ground branch).
            let (fwd, _, _) = self.attitude(t).basis();
            self.ground_dir = norm([fwd[0], fwd[1], 0.0]);
            self.on_ground = true;
            self.crashed = self.landing_check(t, vz);
            if self.mode == Mode::DeepStall {
                self.mode = Mode::Normal; // the ground attitude takes over
            }
            let a = self.axes[2].accel();
            self.axes[2].set_state(t, clear, 0.0, a);
            if self.crashed.is_some() {
                return;
            }
            // Gear down and the check passed: the mission's landed handler, once per landing (flag re-armed at
            // lift-off in v1.1).
            if self.gear_flag(t) && !self.landed {
                self.landed = true;
                self.landings += 1;
            }
            self.aero_update();
            return;
        }
        if z > clear && vz > 0.001 {
            // Lift-off: airborne branch; then roll angle 0, its rate and target kept; the landed flag cleared.
            self.on_ground = false;
            self.landed = false;
            self.aero_update();
            self.roll.reset_angle(t, 0.0);
            return;
        }
        // Rolling: rough ground above 25.7 m/s and water destroy the jet (unless immune).
        let (_, v) = self.velocity_at(t);
        if !self.immune() {
            if self.ground_water {
                self.crashed = Some(Crash::Water);
                return;
            }
            if self.ground_rough && v > ROUGH_CRASH_SPEED {
                self.crashed = Some(Crash::RoughGround);
                return;
            }
        }
        // Keep the wheels on the terrain (Z p0 = clear, t0 = now; velocity and acceleration kept).
        let (_, vz_now) = self.axes[2].sample(t);
        let a = self.axes[2].accel();
        self.axes[2].set_state(t, clear, vz_now, a);
    }

    /// Stores asymmetry `S+0x428 − S+0x42c` (right minus left drag index).
    fn stores_asym(&self) -> f32 {
        self.stores_di_right - self.stores_di_left
    }

    /// External stores: extra mass `S+0x424` (kg) and the left (`S+0x42c`) / right (`S+0x428`) stores
    /// drag index (×1e-4 already applied).
    pub fn set_stores(&mut self, mass_kg: f32, di_left: f32, di_right: f32) {
        self.stores_mass = mass_kg;
        self.stores_di_left = di_left;
        self.stores_di_right = di_right;
    }

    /// External fuel tanks at mission start (docs/weapons.md "Fuel tanks"): FUN_005a8980 sets the fuel
    /// ramp's maximum `S+0x448` to FuelWeight + the tanks' bdb weight (one per station, the pounds
    /// number added to the kg field), and the start (FUN_005a5820 @5a6145) fills the fuel to that
    /// maximum. One pool: the fuel above FuelWeight is the external fuel, burnt first.
    pub fn set_fuel_capacity(&mut self, extra_kg: f32) {
        self.fuel.max = self.params.fuel_mass + extra_kg.max(0.0);
        self.fuel.reset(self.t, self.fuel.max);
    }

    /// The pilot's systems damage flags (bit n = flag n, docs/damage.md §5.2) and whether the jet has two
    /// engines. The thrust reads them at the next aero update (`5bc350`, at most 1 s later), the stick at the
    /// next stick event, the spin entry at the next aero update.
    pub fn set_damage(&mut self, flags: u32, twin: bool) {
        self.damage = flags;
        self.twin = twin;
    }

    /// Motion 0x18 (FUN_005a2270): fuel maximum and fuel := `kg` (the tank jettison sends FuelWeight
    /// when the fuel is at or above it, FUN_00458760).
    pub fn set_fuel(&mut self, kg: f32) {
        if kg >= self.fuel.min {
            self.fuel.max = kg;
            self.fuel.reset(self.t, kg);
        }
    }

    /// Internal fuel capacity (FuelWeight, kg).
    pub fn internal_fuel_kg(&self) -> f32 {
        self.params.fuel_mass
    }

    /// What the autopilot's control loops read from the FM (docs/ai.md §8): the pose `5a68f0` (position and
    /// the flight-path attitude: velocity direction and roll, α = β = 0), the rates
    /// `5a6b10` (flight-path pitch rate, roll rate, turn rate), TAS, the acceleration (slot 0x44) and the
    /// getters.
    pub fn ap_view(&self) -> ApView {
        let t = self.t;
        let (v, speed) = self.velocity_at(t);
        let a = [self.axes[0].accel() as f64, self.axes[1].accel() as f64, self.axes[2].accel() as f64];
        let h2 = v[0] * v[0] + v[1] * v[1];
        let turn = if h2 > 1e-6 { (a[0] * v[1] - a[1] * v[0]) / h2 } else { 0.0 };
        let s2 = h2 + v[2] * v[2];
        let path = if h2 > 1e-6 && s2 > 1e-6 { (a[2] * s2 - v[2] * dot(v, a)) / (s2 * h2.sqrt()) } else { 0.0 };
        let p = &self.params;
        ApView {
            t,
            pos: self.position_at(t),
            vel: v,
            acc: a,
            speed,
            att: self.attitude_ab(t, false),
            rates: [path as f32, self.roll.sample(t).1, turn as f32],
            max_roll_rate: p.max_roll_rate,
            max_g: p.max_g_m1 + 1.0,
            min_g: p.min_g_m1 + 1.0,
            on_ground: self.on_ground,
            gear_down: self.gear_flag(t),
            flaps: self.flaps.sample(t) > 0.0,
            brakes: self.brakes.sample(t) > 0.0,
            type_code: p.type_code,
            gear_clearance: self.gear_clearance,
            ground_height: self.ground_height,
            stick_centre: [self.stick_centre_v, self.stick_centre_a, self.stick_centre_b],
        }
    }

    /// `5b5070` Vmin(alt, g) of the envelope.
    pub fn vmin(&self, alt: f32, g: f32) -> f32 {
        self.envelope.vmin(alt, g)
    }

    /// `5a4d40` re-placement at rest on the ground (taxi / park): position, heading, velocity 0, throttle 0
    /// (docs/flight-model.md §15.6.4).
    pub fn replace_on_ground(&mut self, x: f64, y: f64, heading: f32) {
        let t = self.t;
        let z = self.axes[2].sample(t).0;
        self.axes = [Axis::new(x, 0.0), Axis::new(y, 0.0), Axis::new(z, 0.0)];
        for ax in &mut self.axes {
            ax.set(t, 0.0);
        }
        self.ground_dir = [heading.sin() as f64, heading.cos() as f64, 0.0];
        self.throttle = 0.0;
        self.controls.throttle = 0.0;
        self.aero_update();
    }

    /// Motion 0x16 (`5a8d40`): `Some(heading)` starts a flat pivot turn of 3 s about a point 30 m to the
    /// turn's side (heading rate |Δψ|/3); `None` ends it with the re-placement `5a4d40` at the arc point,
    /// the entry speed along the new heading (on the ground: throttle 0).
    pub fn set_pivot(&mut self, target: Option<f32>) {
        let t = self.t;
        let pos = self.position_at(t);
        let (_, speed) = self.velocity_at(t);
        let h = self.attitude(t).heading;
        match target {
            Some(tt) => {
                let tw = wrap(tt as f64) as f32;
                let d = wrap((tw - h) as f64) as f32;
                let (s0, e) = if tt < 0.0 && h > 0.0 { (h, d + h) } else { (tt - d, tt) };
                let sg = if d > 0.0 { 1.0 } else if d < 0.0 { -1.0 } else { 0.0 };
                let (ch, sh) = ((h as f64).cos(), (h as f64).sin());
                self.pivot = Some(Pivot {
                    t0: t,
                    s0,
                    target: e,
                    rate: (d.abs() / 3.0) * (e - s0).signum(),
                    t_end: if d == 0.0 { 0.0 } else { 3.0 },
                    p: [pos[0] + 30.0 * sg * ch, pos[1] - 30.0 * sg * sh, pos[2]],
                    r: 30.0 * sg,
                    v0: speed,
                });
            }
            None => {
                self.pivot = None;
                let hh = h as f64;
                let v = [speed as f64 * hh.sin(), speed as f64 * hh.cos(), 0.0];
                for i in 0..3 {
                    self.axes[i] = Axis::new(pos[i], v[i] as f32);
                    self.axes[i].set(t, 0.0);
                }
                self.ground_dir = [hh.sin(), hh.cos(), 0.0];
                self.next_aero = t + AERO_PERIOD;
                self.next_accel = t + ACCEL_PERIOD;
                if self.on_ground {
                    self.throttle = 0.0;
                    self.controls.throttle = 0.0;
                }
                self.aero_update();
            }
        }
    }

    /// Motion 0x19 with 0: engine off (`5a2890`).
    pub fn engine_off(&mut self) {
        self.engine_on = false;
        self.aero_update();
    }

    pub fn state(&self) -> State {
        let t = self.t;
        let position = self.position_at(t);
        let (v, speed) = self.velocity_at(t);
        let speed = speed.min(1200.0);
        let att = self.attitude(t);
        let (fwd, right, up) = att.basis();
        let alt = position[2] as f32;
        let mass = self.params.empty_mass + self.stores_mass + self.fuel.sample(t);
        // On the wheels the load factor is 1 (the ground carries the weight); in the air it is L / (m·g).
        // Display only; the original's ground readout is not traced (UNCERTAIN).
        let g = if self.on_ground { 1.0 } else { self.lift.sample(t) / (mass * G) };
        State {
            time: t,
            position,
            velocity: [v[0] as f32, v[1] as f32, v[2] as f32],
            speed,
            mach: speed / air(alt).sound,
            forward: fwd,
            right,
            up,
            pitch: att.pitch,
            roll: att.roll,
            heading: att.heading.rem_euclid(std::f32::consts::TAU),
            alpha: if self.mode == Mode::DeepStall {
                let gamma = if speed > 1.0 { (v[2] as f32 / speed).clamp(-1.0, 1.0).asin() } else { -PI / 2.0 };
                att.pitch - gamma
            } else {
                wrap(self.alpha.sample(t).0) as f32
            },
            beta: self.beta.sample(t).0 as f32,
            g,
            rpm: self.rpm.sample(t),
            throttle: self.throttle,
            afterburner: self.afterburner,
            thrust_n: self.thrust,
            fuel_kg: self.fuel.sample(t),
            mass_kg: mass,
            stalled: self.latched(t),
            buffet: self.buffet,
            drag_x: self.drag_x,
            over_g: g > self.params.over_g_thresh,
            on_ground: self.on_ground,
            spinning: self.mode == Mode::Spin,
            deep_stall: self.mode == Mode::DeepStall,
            gear: self.gear.sample(t),
            crashed: self.crashed,
            landings: self.landings,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A synthetic envelope (not from the game), shaped like a fighter's.
    const ENV: &[u8] = b"[Params]\r\nAltitudeStep = 3000\r\n[Min Velocity Table]\r\n\
        -1\t90\t0\r\n-1\t110\t10000\r\n-1\t140\t20000\r\n\
        0\t50\t0\r\n0\t100\t27000\r\n\
        1\t90\t0\r\n1\t100\t5000\r\n1\t110\t10000\r\n1\t140\t20000\r\n\
        2\t150\t0\r\n2\t185\t10000\r\n2\t225\t20000\r\n\
        3\t185\t0\r\n3\t215\t5000\r\n3\t285\t20000\r\n[End Of Envelope]\r\n";

    fn params(type_code: u32) -> Params {
        let ini = iaf_formats::ini::Ini::parse(b"[X]\r\nMaxBeta = 15\r\nBetaRate = 32\r\n");
        let mut p = Params::from_section(ini.section("X").unwrap());
        p.type_code = type_code;
        p
    }

    fn airborne(type_code: u32, alt: f64, speed: f32) -> Aircraft {
        Aircraft::new(params(type_code), Envelope::parse(ENV), [0.0, 0.0, alt], 0.0, speed)
    }

    fn ground(engine_on: bool) -> Aircraft {
        let st = Start { position: [0.0, 0.0, 10.0], pitch: 0.0, roll: 0.0, heading: 0.0, velocity: [0.0; 3], airborne: false, engine_on };
        let mut ac = Aircraft::start(params(100), Envelope::parse(ENV), st);
        ac.ground_height = 10.0;
        ac
    }

    fn run_to(ac: &mut Aircraft, t: f64) {
        let dt = t - ac.t;
        run(ac, dt);
    }

    fn run(ac: &mut Aircraft, seconds: f64) {
        for _ in 0..(seconds * 100.0).round() as usize {
            ac.step(0.01);
        }
    }

    /// External stores (docs/weapons.md): the extra mass adds to the weight, the drag indices to CD
    /// (less speed), and right − left heavier biases β_cmd = (ru + 10·asym)·MaxBeta.
    #[test]
    fn stores_mass_drag_and_asymmetry() {
        let mut clean = airborne(100, 3000.0, 200.0);
        let mut loaded = airborne(100, 3000.0, 200.0);
        loaded.set_stores(1500.0, 0.002, 0.002);
        run(&mut clean, 10.0);
        run(&mut loaded, 10.0);
        let (sc, sl) = (clean.state(), loaded.state());
        assert!((sl.mass_kg - sc.mass_kg - 1500.0).abs() < 1.0, "mass {} vs {}", sl.mass_kg, sc.mass_kg);
        assert!(sl.speed < sc.speed, "stores drag slows the jet: {} vs {}", sl.speed, sc.speed);
        let mut asym = airborne(100, 3000.0, 200.0);
        asym.set_stores(0.0, 0.0, 0.001);
        run(&mut asym, 1.5);
        assert!((asym.beta_cmd - 0.01 * asym.params.max_beta).abs() < 1e-6, "β_cmd {}", asym.beta_cmd);
    }

    #[test]
    fn external_fuel_tanks() {
        let mut a = airborne(100, 3000.0, 200.0);
        let internal = a.internal_fuel_kg();
        a.set_fuel_capacity(1000.0);
        assert!((a.state().fuel_kg - internal - 1000.0).abs() < 1e-3);
        run(&mut a, 10.0);
        let f = a.state().fuel_kg;
        assert!(f < internal + 1000.0 && f > internal, "the external part burns first: {f}");
        // Jettison with the fuel above FuelWeight: fuel := FuelWeight, the maximum too.
        a.set_fuel(internal);
        assert!((a.state().fuel_kg - internal).abs() < 1e-3);
    }

    #[test]
    fn start_rules() {
        assert!(Aircraft::start_is_airborne(801.0, false));
        assert!(!Aircraft::start_is_airborne(800.0, false));
        assert!(!Aircraft::start_is_airborne(3000.0, true));
        let a = airborne(100, 3000.0, 180.0);
        let s = a.state();
        assert_eq!(s.throttle, 0.74);
        assert!((s.rpm - 70.0).abs() < 1e-3, "rpm {}", s.rpm);
        assert_eq!(s.gear, GEAR_UP);
        assert!(a.engine_on && !s.on_ground);
        // Lift ramps start at MaxWeight·g (value = target); better physics: m·g.
        assert!((a.lift.sample(0.0) - a.params.max_mass * G).abs() < 1.0);
        let mut b = airborne(100, 3000.0, 180.0);
        b.set_better_physics(true);
        assert!((b.lift.sample(0.0) - b.mass * G).abs() < 1.0);
        for engine in [false, true] {
            let g = ground(engine);
            let s = g.state();
            assert!(s.on_ground && s.speed == 0.0 && s.throttle == 0.0 && s.rpm == 0.0);
            assert_eq!(s.gear, 0.0);
            assert_eq!(g.flaps.sample(0.0), FLAPS_MAX);
            assert_eq!(g.brakes.sample(0.0), BRAKES_MAX);
            assert_eq!(g.engine_on, engine);
            assert_eq!(g.lift.sample(0.0), 0.0);
        }
    }

    /// AI special cases (docs/flight-model.md §14/§15): an AI jet (control-loop mode ≠ 0) lights the AB at
    /// once and uses the AB curve only in modes 7 / 8, its gear has no drag, and a jet with fuel whose loop ran > 3.5 s
    /// cannot crash.
    #[test]
    fn ai_special_cases() {
        let mut a = airborne(100, 5000.0, 200.0);
        a.ai_mode = 7;
        a.set_controls(Controls { throttle: 1.0, ..Default::default() });
        run(&mut a, 0.05);
        assert_eq!((a.state().throttle, a.state().afterburner), (1.0, 2));
        a.ai_mode = 3;
        a.set_controls(Controls { throttle: 0.99, ..Default::default() });
        run(&mut a, 0.05);
        assert_eq!(a.state().afterburner, 2, "stage from the throttle");
        // Outside modes 7 / 8 the no-AB curve: k = (thr − 0.2)·1.25 (0.9875), in them the AB step 1.0.
        let no_ab = a.thrust;
        a.ai_mode = 7;
        a.set_controls(Controls { throttle: 1.0, ..Default::default() });
        assert!(a.thrust > no_ab, "{} vs {no_ab}", a.thrust);
        let mut up = airborne(100, 3000.0, 150.0);
        let mut down = airborne(100, 3000.0, 150.0);
        up.ai_mode = 3;
        down.ai_mode = 3;
        down.set_controls(Controls { gear_down: true, throttle: 0.74, ..Default::default() });
        up.set_controls(Controls { throttle: 0.74, ..Default::default() });
        run(&mut down, 5.0);
        run(&mut up, 5.0);
        assert!((up.drag - down.drag).abs() < 0.01 * up.drag, "no gear drag (a player: +30 %): {} {}", up.drag, down.drag);
        down.ai_since = down.t - 3.0;
        assert!(!down.immune());
        down.ai_since = down.t - 4.0;
        assert!(down.immune());
    }

    #[test]
    fn afterburner_light_up_delay() {
        // RPM 70 at the start: the AB request is applied after (100 − 70)/15 = 2 s.
        let mut a = airborne(100, 5000.0, 200.0);
        a.set_controls(Controls { throttle: 1.0, ..Default::default() });
        assert_eq!(a.state().throttle, 0.74);
        run(&mut a, 1.9);
        assert_eq!(a.state().throttle, 0.74);
        run(&mut a, 0.2);
        assert_eq!(a.state().throttle, 1.0);
        assert_eq!(a.state().afterburner, 2);
        // A non-AB change cancels a pending request.
        let mut b = airborne(100, 5000.0, 200.0);
        b.set_controls(Controls { throttle: 1.0, ..Default::default() });
        run(&mut b, 0.5);
        b.set_controls(Controls { throttle: 0.6, ..Default::default() });
        run(&mut b, 3.0);
        assert_eq!(b.state().throttle, 0.6);
        // Player moves under 0.015 are ignored.
        b.set_controls(Controls { throttle: 0.61, ..Default::default() });
        assert_eq!(b.state().throttle, 0.6);
        b.set_controls(Controls { throttle: 0.62, ..Default::default() });
        assert_eq!(b.state().throttle, 0.62);
        // From idle RPM (60 %) the delay is 2.67 s.
        let mut c = airborne(100, 5000.0, 200.0);
        c.set_controls(Controls { throttle: 0.0, ..Default::default() });
        run(&mut c, 8.0);
        assert!((c.state().rpm - 60.0).abs() < 0.01);
        c.set_controls(Controls { throttle: 0.8, ..Default::default() });
        run(&mut c, 2.6);
        assert_eq!(c.state().throttle, 0.74);
        run(&mut c, 0.1);
        assert_eq!(c.state().throttle, 0.8);
    }

    #[test]
    fn ground_start_engine_starts_with_the_first_throttle_event() {
        let mut g = ground(false);
        g.set_controls(Controls { throttle: 0.005, flaps: 1.0, gear_down: true, brakes: true, ..Default::default() });
        assert!(g.engine_on, "any throttle event starts the engine");
        assert_eq!(g.state().throttle, 0.0, "but a 0.005 move is ignored");
    }

    #[test]
    fn stall_latch_timing() {
        // Above the envelope's levels (code 2): stalled at every update.
        let mut a = airborne(0, 29000.0, 250.0);
        assert_eq!(a.stall_time, Some(0.0));
        for t in [0.99, 1.01, 2.99, 3.01, 3.99] {
            run_to(&mut a, t);
            assert_eq!(a.stall_time, Some(0.0), "not re-triggered at {t}");
            assert_eq!(a.state().stalled, a.t <= 3.0, "at {t}");
        }
        // Held through the updates at 1, 2, 3 (≤ 3.0): L = 0 until the update at 4.
        assert_eq!(a.lift.target(), 0.0);
        run_to(&mut a, 4.01);
        assert_eq!(a.stall_time, None, "cleared by the update at 4 even though still stalled");
        run_to(&mut a, 5.01);
        assert_eq!(a.stall_time, Some(5.0), "set again by the next stalled update");
    }

    #[test]
    fn no_stalls_keeps_minimum_lift() {
        let mut a = airborne(0, 29000.0, 250.0);
        a.no_stalls = true;
        a.stall_time = None;
        a.set_controls(Controls { stick_y: 0.5, ..Default::default() });
        assert_eq!(a.stall_time, None);
        assert!((a.lift.target() / (a.mass * G) - 0.4).abs() < 1e-3, "code 2 → g = 0.4");
    }

    #[test]
    fn landing_limits() {
        let mut a = airborne(0, 1000.0, 80.0);
        let check = |a: &Aircraft, pitch: f32, roll: f32, vz: f32| {
            let mut b = a.clone();
            b.saved = Euler { pitch: pitch.to_radians(), roll: roll.to_radians(), heading: 0.0 };
            b.landing_check(b.t, vz)
        };
        // Gear down (set instantly), Easy landing off.
        a.gear.reset(a.t, 0.0);
        a.easy_landing = false;
        assert_eq!(check(&a, 0.0, 0.0, -39.0), None);
        assert_eq!(check(&a, 0.0, 0.0, -41.0), Some(Crash::Landing));
        assert_eq!(check(&a, -4.9, 0.0, -1.0), None);
        assert_eq!(check(&a, -5.1, 0.0, -1.0), Some(Crash::Landing));
        assert_eq!(check(&a, 0.0, 9.9, -1.0), None);
        assert_eq!(check(&a, 0.0, -10.1, -1.0), Some(Crash::Landing));
        assert_eq!(check(&a, 40.0, 0.0, -1.0), None, "no tail-strike limit in the original");
        // Easy landing doubles the limits.
        a.easy_landing = true;
        assert_eq!(check(&a, 0.0, 0.0, -79.0), None);
        assert_eq!(check(&a, 0.0, 0.0, -81.0), Some(Crash::Landing));
        assert_eq!(check(&a, -9.9, 19.9, -1.0), None);
        // Gear not fully down: ×0.2 / 0.2 / 0.25.
        a.gear.reset(a.t, 0.5);
        assert_eq!(check(&a, 0.0, 0.0, -19.0), None);
        assert_eq!(check(&a, 0.0, 0.0, -21.0), Some(Crash::Landing));
        assert_eq!(check(&a, -2.1, 0.0, -1.0), Some(Crash::Landing));
        assert_eq!(check(&a, 0.0, 4.1, -1.0), Some(Crash::Landing));
        a.easy_landing = false;
        assert_eq!(check(&a, 0.0, 0.0, -9.0), None);
        assert_eq!(check(&a, 0.0, 0.0, -11.0), Some(Crash::Landing));
        assert_eq!(check(&a, -1.1, 0.0, -1.0), Some(Crash::Landing));
        // Slope > 10°.
        a.gear.reset(a.t, 0.0);
        a.ground_normal_z = 11f32.to_radians().cos();
        assert_eq!(check(&a, 0.0, 0.0, -1.0), Some(Crash::Landing));
        a.ground_normal_z = 1.0;
        // Invulnerable / No crashes: immune.
        a.no_crashes = true;
        assert_eq!(check(&a, -60.0, 0.0, -100.0), None);
        a.no_crashes = false;
        a.invulnerable = true;
        assert_eq!(check(&a, -60.0, 0.0, -100.0), None);
        a.invulnerable = false;
        // Better physics: real sink limit (4 m/s, ×2 easy) and a tail-strike limit (15°, ×2 easy).
        a.better.landing_limits = true;
        let now = |a: &Aircraft, vz: f32| a.landing_check(a.t, vz);
        a.easy_landing = false;
        assert_eq!(now(&a, -3.9), None);
        assert_eq!(now(&a, -4.1), Some(Crash::SinkRate));
        // The autopilot landing keeps the original's limits (40 m/s sink, no tail strike).
        a.ap_landing = true;
        assert_eq!(now(&a, -10.0), None, "autopilot landing: original sink limit");
        a.ap_landing = false;
    }

    #[test]
    fn touchdown_crash_and_gentle_landing() {
        for (vz, crash) in [(-60.0, true), (-1.5, false)] {
            let mut a = airborne(0, 20.0, 80.0);
            // Start the lift ramps at m·g (no start jolt) but keep the original rules.
            a.set_better_option("start_lift", true);
            a.easy_landing = false;
            a.ground_height = 0.0;
            a.gear.reset(0.0, 0.0);
            a.controls.gear_down = true;
            a.axes[2] = Axis::new(5.0, vz);
            run(&mut a, 5.0);
            assert!(a.on_ground);
            assert_eq!(a.crashed.is_some(), crash, "vz {vz}: {:?}", a.crashed);
            if crash {
                let p = a.state().position;
                run(&mut a, 1.0);
                assert_eq!(a.state().position, p, "frozen after the crash");
            }
        }
    }

    /// A jet with thrust tables (lbf: dry 10000 → AB 20000 everywhere) and fuel.
    fn engined(twin: bool) -> Aircraft {
        let mut a = airborne(0, 3000.0, 200.0);
        a.params.thrust = [[[0.0, 20000.0]; 2]; 2];
        a.params.fuel_flow_max = 4.0;
        a.params.has_afterburner = true;
        a.twin = twin;
        a.set_fuel(1000.0);
        a.throttle = 1.0;
        a
    }

    #[test]
    fn damage_bits_follow_5bc350() {
        let f = |ns: &[u32]| ns.iter().fold(0u32, |m, n| m | 1 << n);
        assert_eq!(damage_bits(f(&[16]), false), 0xc);
        assert_eq!(damage_bits(f(&[22]), true), 4);
        assert_eq!(damage_bits(f(&[17]), true), 8);
        assert_eq!(damage_bits(f(&[17]), false), 0); // a single-engine jet never reads the right flags
        assert_eq!(damage_bits(f(&[8]), false), 0x180);
        assert_eq!(damage_bits(f(&[8, 9]), true), 0x180);
        assert_eq!(damage_bits(f(&[10, 18, 24]), true), 0x70);
    }

    #[test]
    fn engine_damage_cuts_thrust() {
        let full = engined(false).thrust_at(3000.0, 0.5, false);
        assert!(full.0 > 80000.0 && full.3 == 2, "{full:?}");
        // Single engine on fire (16) or permanently damaged (22): no thrust, no RPM.
        for n in [16, 22] {
            let mut a = engined(false);
            a.set_damage(1 << n, false);
            let t = a.thrust_at(3000.0, 0.5, false);
            assert_eq!((t.0, t.1, t.3), (0.0, 0.0, 0), "{n}");
        }
        // A twin with one engine gone: half the thrust (k 1 → 0.5), and k ≤ 0.6 takes the dry fuel flow.
        let mut b = engined(true);
        b.set_damage(1 << 16, true);
        let t = b.thrust_at(3000.0, 0.5, false);
        assert!((t.0 - full.0 * 0.5).abs() < 1.0, "{t:?}");
        assert!((t.2 - 4.0 * b.params.dry_fuel_frac).abs() < 1e-4, "{t:?}");
        b.set_damage(1 << 16 | 1 << 17, true);
        assert_eq!(b.thrust_at(3000.0, 0.5, false).0, 0.0);
    }

    #[test]
    fn afterburner_damage_and_fuel_leak() {
        // Single engine, AB damaged (8): full throttle stays at military (0.74).
        let mut a = engined(false);
        a.set_damage(1 << 8, false);
        let t = a.thrust_at(3000.0, 0.5, false);
        let k = 0.05 + 0.743_243_2 * 0.74;
        assert_eq!(t.3, 0);
        assert!((t.0 - k * 20000.0 * LBF).abs() < 1.0, "{t:?}");
        // A twin with one AB damaged keeps both burning (only its flame goes out).
        let mut b = engined(true);
        b.set_damage(1 << 8, true);
        assert_eq!(b.thrust_at(3000.0, 0.5, false).3, 2);
        // Fuel leak (10): +0.25·FuelFlowAtMaxThrust, even with the engine off.
        let mut c = engined(false);
        let ff = c.thrust_at(3000.0, 0.5, false).2;
        c.set_damage(1 << 10, false);
        assert!((c.thrust_at(3000.0, 0.5, false).2 - ff - 1.0).abs() < 1e-4);
        c.engine_on = false;
        assert!((c.thrust_at(3000.0, 0.5, false).2 - 1.0).abs() < 1e-4);
        c.unlimited_fuel = true;
        assert_eq!(c.thrust_at(3000.0, 0.5, false).2, 0.0);
    }

    #[test]
    fn hydraulics_and_flight_control_damage() {
        let stick = |a: &mut Aircraft| {
            a.set_controls(Controls { stick_x: 1.0, stick_y: -0.8, rudder: 0.5, ..a.controls() });
            a.controls()
        };
        let mut a = airborne(0, 3000.0, 200.0);
        a.set_damage(1 << 18, false);
        let c = stick(&mut a);
        assert_eq!((c.stick_x, c.stick_y, c.rudder), (0.25, -0.2, 0.5));
        let mut b = airborne(0, 3000.0, 200.0);
        b.set_damage(1 << 24, false);
        let c = stick(&mut b);
        assert_eq!((c.stick_x, c.stick_y, c.rudder), (0.0, 0.0, 0.5));
        // Total flight control damage forces the spin at the next aero update, whatever β / dragX
        // (not on the F-16 / Lavi, which return before the test).
        let att = Euler { pitch: 0.0, roll: 0.0, heading: 0.5 };
        let mut io = ModeIo { acc: [0.0; 3], lift: 5.0, lift_noflap: 5.0, p_cmd: 0.0 };
        b.spin_hook(1.0, 0.0, 200.0, 0.0, att, &mut io, true);
        assert_eq!(b.mode, Mode::Spin);
        let mut f16 = airborne(100, 3000.0, 200.0);
        f16.set_damage(1 << 24, false);
        f16.spin_hook(1.0, 0.0, 200.0, 0.0, att, &mut io, true);
        assert_eq!(f16.mode, Mode::Normal);
    }

    #[test]
    fn spin_entry_and_exit() {
        let mb = 15f32.to_radians();
        let att = Euler { pitch: 0.0, roll: 0.0, heading: 0.5 };
        let io = || ModeIo { acc: [1.0, 1.0, 1.0], lift: 5.0, lift_noflap: 5.0, p_cmd: 1.0 };
        // Original: the second consecutive qualifying aero update enters, whatever the spacing.
        let mut a = airborne(0, 3000.0, 100.0);
        a.spin_hook(1.0, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
        assert_eq!(a.mode, Mode::Normal);
        a.spin_hook(1.05, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
        assert_eq!(a.mode, Mode::Spin);
        // A non-qualifying update in between resets the arm step.
        let mut b = airborne(0, 3000.0, 100.0);
        b.spin_hook(1.0, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
        b.spin_hook(2.0, 0.5, 100.0, 0.9 * mb, att, &mut io(), true);
        b.spin_hook(3.0, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
        assert_eq!(b.mode, Mode::Normal);
        b.spin_hook(4.0, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
        assert_eq!(b.mode, Mode::Spin);
        // "No spins" (original bug): the arm step is skipped, so the first qualifying update enters.
        let mut c = airborne(0, 3000.0, 100.0);
        c.no_spins = true;
        c.spin_hook(1.0, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
        assert_eq!(c.mode, Mode::Spin);
        // Better physics: "No spins" blocks; otherwise the condition must hold for 1.2 s.
        let mut d = airborne(0, 3000.0, 100.0);
        d.better.spin_fixes = true;
        for t in [1.0, 2.0, 2.2] {
            d.spin_hook(t, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
            assert_eq!(d.mode, Mode::Normal, "{t}");
        }
        d.spin_hook(2.3, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
        assert_eq!(d.mode, Mode::Spin);
        let mut e = airborne(0, 3000.0, 100.0);
        e.better.spin_fixes = true;
        e.no_spins = true;
        for t in [1.0, 2.0, 3.0, 4.0] {
            e.spin_hook(t, 1.2, 100.0, 0.9 * mb, att, &mut io(), true);
        }
        assert_eq!(e.mode, Mode::Normal);
        // The F-16 (type 100) and the Lavi (140) never spin; not below 0.8·MaxBeta or dragX ≤ 0.57.
        for (ty, beta, dx) in [(100, 0.9 * mb, 1.2), (140, 0.9 * mb, 1.2), (0, 0.79 * mb, 1.2), (0, 0.9 * mb, 0.57)] {
            let mut f = airborne(ty, 3000.0, 100.0);
            for t in [1.0, 2.0, 3.0] {
                f.spin_hook(t, dx, 100.0, beta, att, &mut io(), true);
            }
            assert_eq!(f.mode, Mode::Normal, "type {ty} β {beta} dragX {dx}");
        }
        // In the spin: no lift, no roll command, frozen horizontal velocity, acc.z = min(0, 0.04 V − g).
        let t = a.t.max(1.05);
        let mut o = io();
        a.spin_hook(t + 1.0, 1.2, 100.0, 0.9 * mb, att, &mut o, true);
        assert_eq!(a.mode, Mode::Spin);
        assert_eq!((o.lift, o.lift_noflap, o.p_cmd), (0.0, 0.0, 0.0));
        assert_eq!(o.acc, [0.0, 0.0, (0.04 * 100.0 - G) as f64]);
        let spin_att = a.attitude(t + 1.0);
        assert!(spin_att.pitch < 0.0 && spin_att.heading != 0.5, "nose drops and turns: {spin_att:?}");
        // Recovery: ≥ 90 % opposite rudder but still stalled (dragX ≥ 0.1) → stays.
        a.spin_hook(t + 2.0, 0.1, 100.0, -0.95 * mb, att, &mut io(), true);
        assert_eq!(a.mode, Mode::Spin);
        // ... and with dragX < 0.1 it exits at the next tick (the yaw rate is still positive):
        // velocity = the nose direction · V, roll command s1·0.1.
        for ax in a.axes.iter_mut() {
            ax.set(t + 2.0, 0.0);
        }
        let mut o = io();
        a.spin_hook(t + 2.2, 0.05, 100.0, -0.95 * mb, att, &mut o, false);
        assert_eq!(a.mode, Mode::Normal);
        assert!((o.p_cmd - 0.1).abs() < 1e-6);
        let v = a.velocity_at(t + 2.2).0;
        assert!((dot(v, v).sqrt() - 100.0).abs() < 0.5);
    }

    /// A near-vertical zoom at low speed, the "pilot" holding the flight path at 85° until the jet departs
    /// (or 20 s), then neutral stick. Returns whether a deep stall / spin ever started.
    fn zoom(type_code: u32, bp: bool, setup: impl Fn(&mut Aircraft)) -> (Aircraft, bool, bool) {
        let r = 85f64.to_radians();
        let st = Start { position: [0.0, 0.0, 3000.0], pitch: 0.0, roll: 0.0, heading: 0.0, velocity: [0.0, 70.0 * r.cos(), 70.0 * r.sin()], airborne: true, engine_on: true };
        let mut a = Aircraft::start(params(type_code), Envelope::parse(ENV), st);
        a.set_better_physics(bp);
        setup(&mut a);
        let (mut ds, mut spin) = (false, false);
        for _ in 0..(40 * 60) {
            let s = a.state();
            let gamma = (s.velocity[2] / s.speed.max(0.01)).asin().to_degrees();
            let sy = if s.deep_stall || s.time > 20.0 { 0.0 } else { ((85.0 - gamma) / 10.0).clamp(-1.0, 1.0) };
            a.set_controls(Controls { stick_y: sy, ..Default::default() });
            a.step(1.0 / 60.0);
            ds |= a.state().deep_stall;
            spin |= a.state().spinning;
            if ds {
                break;
            }
        }
        (a, ds, spin)
    }

    #[test]
    fn fbw_deep_stall_only_with_better_physics() {
        // The F-16 and the Lavi: never without better physics (the original exempts them), a deep stall with it.
        for ty in [100, 140] {
            let (_, ds, spin) = zoom(ty, false, |_| {});
            assert!(!ds && !spin, "type {ty}, original: no departure");
            let (a, ds, spin) = zoom(ty, true, |_| {});
            assert!(ds && !spin, "type {ty}, better physics: deep stall");
            let s = a.state();
            assert!(s.stalled && s.speed < a.envelope.vmin(s.position[2] as f32, 1.0), "entered stalled, below the 1 g Vmin");
        }
        // The option alone is enough (each better-physics behaviour has its own switch).
        assert!(zoom(100, false, |a| assert!(a.set_better_option("fbw_departure", true))).1);
        // Not for the other jets (they keep the spin), and "No spins" / "No stalls" prevent it.
        assert!(!zoom(0, true, |_| {}).1);
        assert!(!zoom(100, true, |a| a.no_spins = true).1);
        assert!(!zoom(100, true, |a| a.no_stalls = true).1);
        // Level flight at a normal speed never departs, even pulling hard.
        let mut a = airborne(100, 3000.0, 150.0);
        a.set_better_physics(true);
        a.set_controls(Controls { stick_y: 1.0, ..Default::default() });
        for _ in 0..600 {
            a.step(0.01);
            assert!(!a.state().deep_stall);
        }
    }

    #[test]
    fn fbw_deep_stall_behaviour_and_recovery() {
        let (mut a, ds, _) = zoom(100, true, |_| {});
        assert!(ds);
        // Established after ~15 s: nose near the horizon, AoA around 60°, a steep fast descent, ~1 g normal load.
        let fly = |a: &mut Aircraft, secs: f64, stick: &dyn Fn(&State, f32) -> f32| {
            let mut last = a.state().pitch;
            for _ in 0..(secs * 60.0) as usize {
                let s = a.state();
                let rate = (s.pitch - last) * 60.0;
                last = s.pitch;
                a.set_controls(Controls { stick_y: stick(&s, rate), ..Default::default() });
                a.step(1.0 / 60.0);
            }
            a.state()
        };
        let s = fly(&mut a, 15.0, &|_, _| 0.0);
        assert!(s.deep_stall);
        let gamma = (s.velocity[2] / s.speed).asin().to_degrees();
        assert!((-75.0..-40.0).contains(&gamma), "path {gamma}");
        assert!((40.0..80.0).contains(&s.alpha.to_degrees()), "AoA {}", s.alpha.to_degrees());
        assert!((-80.0..-30.0).contains(&s.velocity[2]), "vz {}", s.velocity[2]);
        assert!(s.pitch.abs() < 40f32.to_radians(), "pitch {}", s.pitch.to_degrees());
        // Full forward stick alone does not recover (the tail has no nose-down power left).
        let s = fly(&mut a, 20.0, &|_, _| -1.0);
        assert!(s.deep_stall, "a steady push does not recover");
        // Rocking the stick in phase with the pitch motion (MPO) does, within a few cycles.
        let z0 = s.position[2];
        let s = fly(&mut a, 20.0, &|s, rate| if s.deep_stall { rate.signum() } else { 0.0 });
        assert!(!s.deep_stall && !s.crashed.is_some(), "recovered");
        assert!(s.alpha < 30f32.to_radians(), "flying again: AoA {}", s.alpha.to_degrees());
        assert!(z0 - s.position[2] < 2500.0, "height lost {}", z0 - s.position[2]);
    }

    #[test]
    fn better_physics_options() {
        let all = BetterPhysics::all();
        assert_eq!(BetterPhysics::default(), BetterPhysics::none());
        for (id, _) in BetterPhysics::OPTIONS {
            assert_eq!(all.get(id), Some(true), "{id}");
            assert_eq!(BetterPhysics::none().get(id), Some(false), "{id}");
            let mut one = BetterPhysics::none();
            assert!(one.set(id, true));
            assert_eq!(BetterPhysics::OPTIONS.iter().filter(|(o, _)| one.get(o) == Some(true)).count(), 1, "{id} is its own switch");
        }
        assert!(!BetterPhysics::none().set("warp_drive", true));
        assert_eq!(all.get("warp_drive"), None);
        let mut a = airborne(0, 3000.0, 180.0);
        a.set_better_physics(true);
        assert_eq!(a.better, all);
        assert!(a.set_better_option("ground_effect", false));
        assert!(!a.better.ground_effect && a.better.spin_fixes);
        a.set_better_physics(false);
        assert_eq!(a.better, BetterPhysics::none());
    }

    #[test]
    fn better_physics_minor_fixes() {
        // Lift-ramp rate factor: the original grows again below 18 m/s (|0.01 + 0.99·(V − 20)/200|); BP 1 %.
        for (bp, factor) in [(false, (0.01f32 + 0.99 * (5.0 - 20.0) / 200.0).abs()), (true, 0.01)] {
            let mut a = airborne(0, 3000.0, 5.0);
            a.better = if bp { BetterPhysics::all() } else { BetterPhysics::none() };
            a.aero_update();
            let expect = factor * a.params.g_rate * a.mass * G;
            assert!((a.lift.rate().abs() - expect).abs() < 1e-2 * expect, "bp {bp}: {} vs {expect}", a.lift.rate());
        }
        // Roll command below Veff ≈ 9.5 m/s: reversed in the original, none with BP.
        for (bp, sign) in [(false, -1.0f32), (true, 0.0)] {
            let mut a = airborne(0, 3000.0, 5.0);
            a.better = if bp { BetterPhysics::all() } else { BetterPhysics::none() };
            a.set_controls(Controls { stick_x: 1.0, ..Default::default() });
            let r = a.roll.sample(a.t + 0.1).1;
            assert_eq!(r.signum() * (r.abs() > 1e-6) as i32 as f32, sign, "bp {bp}: roll rate {r}");
        }
        // Ground effect (BP): less induced drag near the ground, none without BP or far from it.
        let drag = |bp: bool, ground: f32| {
            let mut a = airborne(0, 11.0, 80.0);
            a.better = if bp { BetterPhysics::all() } else { BetterPhysics::none() };
            a.ground_height = ground;
            a.aero_update();
            a.drag
        };
        assert_eq!(drag(false, 10.0), drag(false, f32::NEG_INFINITY));
        assert_eq!(drag(true, -1000.0), drag(true, f32::NEG_INFINITY));
        assert!(drag(true, 10.0) < 0.95 * drag(true, f32::NEG_INFINITY));
        let a = airborne(0, 12.0, 80.0);
        let b = a.params.wing_span;
        let phi = |h: f32| {
            let mut c = a.clone();
            c.ground_height = 0.0;
            c.ground_effect(h)
        };
        assert!((phi(b / 16.0) - 0.5).abs() < 1e-3 && phi(b / 4.0) > 0.93 && phi(5.0 * b) == 1.0);
        // The nose-wheel side force's ×4 vertical lift (original data set): gone with BP.
        let az = |bp: bool| {
            let mut g = ground(true);
            g.better = if bp { BetterPhysics::all() } else { BetterPhysics::none() };
            g.mass = 10000.0;
            g.ground_acc(0.0, 0.5 * g.mass * G, 40.0, 0.2, Euler::default())[2]
        };
        assert!(az(false) > 0.0, "×4: {}", az(false));
        assert_eq!(az(true), 0.0);
        // Airborne start: the RPM at the start throttle's value (AB at once) and α at its trim value.
        let mut a = airborne(100, 3000.0, 180.0);
        a.set_better_physics(true);
        assert!((a.state().rpm - 100.0).abs() < 1e-3);
        let at = a.alpha.sample(0.0).0 as f32;
        let trim = a.alpha_target(a.lift_aoa.target(), q_s(3000.0, 180.0, a.params.wing_area));
        assert!(at.abs() > 0.01 && (at - trim).abs() < 0.01, "α {at} trim {trim}");
        assert_eq!(airborne(100, 3000.0, 180.0).alpha.sample(0.0).0, 0.0, "original: α starts at 0");
        a.set_controls(Controls { throttle: 1.0, ..Default::default() });
        a.step(0.01);
        assert_eq!(a.state().throttle, 1.0, "no light-up delay at 100 %");
    }

    #[test]
    fn nose_wheel_yaw_ramps_at_beta_rate() {
        let mut g = ground(true);
        g.axes[1] = Axis::new(0.0, 60.0);
        g.set_controls(Controls { stick_x: 1.0, throttle: 0.0, flaps: 1.0, gear_down: true, brakes: true, ..Default::default() });
        // Target clamp(1·60·K/74.53, ±K) = 0.281 rad/s, ramp limit ±MaxBeta (15°/s = 0.262), rate 32°/s².
        let t0 = g.t;
        let r = g.nose_yaw.sample(t0 + 0.2);
        assert!((r - 32f32.to_radians() * 0.2).abs() < 1e-4, "{r}");
        assert!((g.nose_yaw.sample(t0 + 3.0) - 15f32.to_radians()).abs() < 1e-4);
    }

    #[test]
    fn flap_ramp_range() {
        let mut g = ground(true);
        // Full flaps at a ground start; the F-16's flap lever then gives a third of the travel.
        assert_eq!(g.flaps.sample(0.0), FLAPS_MAX);
        g.set_controls(Controls { throttle: 0.0, flaps: 0.0, gear_down: true, brakes: true, ..Default::default() });
        run(&mut g, 1.0);
        assert_eq!(g.flaps.sample(g.t), 0.0);
        g.set_controls(Controls { throttle: 0.0, flaps: 1.0, gear_down: true, brakes: true, ..Default::default() });
        run(&mut g, 1.0);
        assert!((g.flaps.sample(g.t) - FLAPS_MAX * 0.33).abs() < 1e-6);
        // The gear takes 1.569 / 0.5 = 3.1 s.
        let mut a = airborne(100, 3000.0, 100.0);
        a.set_controls(Controls { gear_down: true, ..Default::default() });
        run(&mut a, 3.1);
        assert!(!a.gear_flag(a.t));
        run(&mut a, 0.05);
        assert!(a.gear_flag(a.t));
    }

    #[test]
    fn rudder_keys_and_v10_defaults() {
        // A v1.0 bd.ibx has no Rudder* keys: the exe's defaults 5 / 0 / 0.5 / 0.5 (loader `5b2940`).
        let p = params(0);
        assert_eq!((p.rudder_k, p.rudder_beta, p.rudder_start_accel, p.rudder_stop_accel), (5.0, 0.0, 0.5, 0.5));
        // The v1.1 values are stored raw (no degree conversion).
        let ini = iaf_formats::ini::Ini::parse(b"[X]\r\nRudderK = 5.5\r\nRudderBeta = 0.2\r\nRudderStartAccel = 0.7\r\nRudderStopAccel = 0.3\r\n");
        let p = Params::from_section(ini.section("X").unwrap());
        assert_eq!((p.rudder_k, p.rudder_beta, p.rudder_start_accel, p.rudder_stop_accel), (5.5, 0.2, 0.7, 0.3));
    }

    #[test]
    fn beta_channel_second_order() {
        let mut a = airborne(0, 3000.0, 180.0);
        let (mb, br) = (a.params.max_beta, a.params.beta_rate);
        a.set_controls(Controls { rudder: 1.0, ..Default::default() });
        // Gains at 180 m/s: k = 0.0025·V = 0.45 (below 400 m/s; v1.0 375), K ×1 (|β_cmd| > 0.1·MaxBeta).
        let k = 0.0025 * 180.0;
        assert!((a.beta.max_rate - br * k).abs() < 1e-5, "Rmax {}", a.beta.max_rate);
        assert!((a.beta.start_accel - 0.5 * k).abs() < 1e-6 && (a.beta.stop_accel - 0.5 * k).abs() < 1e-6);
        assert!((a.beta_k - 5.0 * k).abs() < 1e-5 && a.beta_b == 0.0 && a.beta_cmd == mb);
        // Starts from rest: the rate builds at startAccel (second order, not a constant-rate ramp).
        let t0 = a.t;
        let (b1, r1) = a.beta.sample(t0 + 0.1);
        assert!((r1 - 0.5 * k * 0.1).abs() < 1e-5 && (b1 as f32 - 0.25 * k * 0.01).abs() < 1e-5, "β {b1} rate {r1}");
        run(&mut a, 4.0);
        let s = a.state();
        assert!(s.beta > 0.9 * mb && s.beta <= 1.01 * mb, "β {}", s.beta.to_degrees());
        // Neutral rudder: K ×1.5 near zero, back to ~0.
        a.set_controls(Controls::default());
        let k = 0.0025 * a.velocity_at(a.t).1;
        assert!((a.beta_k - 1.5 * 5.0 * k).abs() < 1e-5, "K {} k {k}", a.beta_k);
        run(&mut a, 5.0);
        assert!(a.state().beta.abs() < 0.02 * mb, "β {}", a.state().beta.to_degrees());
        // At and above 400 m/s the gains are the data's (k = 1); at 390 m/s k = 0.975 (v1.0: 1 above 375).
        for (v, k) in [(390.0, 0.975), (400.0, 1.0), (500.0, 1.0)] {
            let a = airborne(0, 3000.0, v);
            assert!((a.beta.max_rate - br * k).abs() < 1e-5, "{v}: {}", a.beta.max_rate);
        }
        // No ±MaxBeta clamp (v1.0 clamped the ramp).
        let mut c = airborne(0, 3000.0, 180.0);
        let t = c.t;
        c.beta.set(t, 1.3 * mb as f64, 0.0);
        c.beta.reset_angle(t, 1.3 * mb as f64);
        assert!(c.state().beta > 1.2 * mb);
    }

    #[test]
    fn beta_steps_on_the_ground_and_in_the_spin() {
        // Ground 1 Hz: the channel steps toward its stored command with the stored gains (v1.0 re-based it).
        let mut g = ground(true);
        g.beta_cmd = 0.2;
        g.aero_update();
        assert_eq!(g.beta_cmd, 0.2);
        assert!(g.beta.sample(g.t + 0.5).1 > 0.0, "moves toward the stored command");
        // Spin 5 Hz tick: β_cmd = rudder·MaxBeta (asym 0) and the β update run too (v1.0 only at 1 Hz there).
        let mut a = airborne(0, 3000.0, 100.0);
        a.mode = Mode::Spin;
        a.rudder = -1.0;
        a.t += 0.2;
        a.accel_update();
        assert_eq!(a.mode, Mode::Spin);
        assert_eq!(a.beta_cmd, -a.params.max_beta);
    }

    #[test]
    fn roll_about_the_body_nose() {
        // v1.1 `5b9530`: the left wing turns by dφ about the saved attitude's nose, not the velocity.
        let mut a = airborne(0, 3000.0, 150.0);
        let t = a.t;
        let saved = Euler { pitch: 0.2, roll: 0.0, heading: 0.0 };
        a.save_attitude(saved);
        a.alpha.set(t, 0.2, 0.0);
        a.alpha.reset_angle(t, 0.2);
        a.roll.set(t, 1.0, 0.0);
        a.roll.reset_angle(t, 1.0);
        let (v, speed) = a.velocity_at(t);
        let w = rotate(scale(saved.basis().1, -1.0), saved.basis().0, 1.0);
        let f = rotate(scale(v, 1.0 / speed as f64), w, -0.2);
        let att = a.attitude(t);
        assert!((att.pitch as f64 - f[2].asin()).abs() < 1e-5 && (att.heading as f64 - f[0].atan2(f[1])).abs() < 1e-5, "{att:?}");
        // Rolling about the velocity (v1.0) gives a different attitude.
        let w0 = rotate(scale(saved.basis().1, -1.0), scale(v, 1.0 / speed as f64), 1.0);
        let f0 = rotate(scale(v, 1.0 / speed as f64), w0, -0.2);
        assert!((f0[2].asin() - f[2].asin()).abs() > 1e-3);
    }

    #[test]
    fn spin_recovery_slope_v11() {
        // Opposite rudder at 0.95·MaxBeta: target π/2 − 0.95·π/2.2 > 0, the spin keeps turning the same way
        // (v1.0's π/(1.8·MaxBeta) reversed it). Stalled (dragX ≥ 0.1), so it stays in the spin.
        let mb = 15f32.to_radians();
        let att = Euler { pitch: 0.0, roll: 0.0, heading: 0.5 };
        let mut a = airborne(0, 3000.0, 100.0);
        let mut io = ModeIo { acc: [0.0; 3], lift: 0.0, lift_noflap: 0.0, p_cmd: 0.0 };
        a.spin_hook(1.0, 1.2, 100.0, 0.9 * mb, att, &mut io, true);
        a.spin_hook(1.05, 1.2, 100.0, 0.9 * mb, att, &mut io, true);
        assert_eq!(a.mode, Mode::Spin);
        for ax in a.axes.iter_mut() {
            ax.set(1.05, 0.0);
        }
        for i in 0..10 {
            a.spin_hook(1.5 + 0.2 * i as f64, 1.2, 100.0, -0.95 * mb, att, &mut io, false);
        }
        assert_eq!(a.mode, Mode::Spin);
        let (_, rate) = a.spin_yaw.sample(3.5);
        let expect = PI / 2.0 - 0.95 * PI / SPIN_SLOPE;
        assert!(rate > 0.0 && (rate - expect).abs() < 1e-3, "yaw rate {rate} vs {expect}");
    }

    #[test]
    fn drag_chute_adds_its_cd() {
        // Rolling at 60 m/s: the deployed chute adds chute_cd · q·S (× the ground factor 0.8); 0 = no change.
        let mut g = ground(true);
        g.axes[1] = Axis::new(0.0, 60.0);
        g.aero_update();
        let d0 = g.drag;
        g.drag_chute = true;
        g.aero_update();
        assert_eq!(g.drag, d0, "chute_cd 0 (original): no drag");
        g.params.chute_cd = 0.24;
        g.aero_update();
        let qs = q_s(10.0, 60.0, g.params.wing_area);
        assert!((g.drag - d0 - 0.8 * 0.24 * qs).abs() < 0.02 * (g.drag - d0), "chute drag {} vs {}", g.drag - d0, 0.8 * 0.24 * qs);
    }

    #[test]
    fn ground_idle_thrust_falls_with_speed() {
        // BP ground_idle: on the ground the idle share (k 0.05) is ×(1 − V/Vj); the throttle's share is kept.
        let mut g = ground(true);
        g.throttle = 0.0;
        g.params.thrust = [[[0.0, 20000.0]; 2]; 2];
        let a = crate::atmosphere::air(10.0).sound;
        let still = g.thrust_at(10.0, 0.0, false).0;
        g.better.ground_idle = true;
        assert_eq!(g.thrust_at(10.0, 0.0, false).0, still, "same idle at rest");
        let half = g.thrust_at(10.0, 0.5 * IDLE_VJ / a, false).0;
        g.better.ground_idle = false;
        let half_orig = g.thrust_at(10.0, 0.5 * IDLE_VJ / a, false).0;
        assert!((half - 0.5 * half_orig).abs() < 0.01 * half_orig, "{half} vs {half_orig}");
        g.better.ground_idle = true;
        assert_eq!(g.thrust_at(10.0, 2.0 * IDLE_VJ / a, false).0, 0.0, "no idle thrust above Vj");
    }

    #[test]
    fn ground_roll_drag_factor() {
        // Above 1 m/s the ground drag (aero + rolling friction) is × 0.8 (v1.0 0.7).
        let mut g = ground(true);
        g.axes[1] = Axis::new(0.0, 20.0);
        g.aero_update();
        let d = g.drag;
        g.axes[1] = Axis::new(0.0, 0.9);
        g.aero_update();
        let p = &g.params;
        let (_, v) = g.velocity_at(g.t);
        let qs = q_s(10.0, 20.0, p.wing_area);
        let qs_slow = q_s(10.0, v, p.wing_area);
        let mu = p.wheel_brake_di + FRIC1; // brakes on at a ground start
        let w = g.mass * G;
        assert!((d - 0.8 * (p.plane_di * qs + p.gear_di * qs + p.flaps_di * FLAPS_MAX * FLAPS_K * qs + 0.5 * mu * w)).abs() < 1e-2 * d, "drag {d}");
        assert!((g.drag - (p.plane_di * qs_slow + p.gear_di * qs_slow + p.flaps_di * FLAPS_MAX * FLAPS_K * qs_slow + 0.5 * mu * w)).abs() < 1e-2 * g.drag, "not below 1 m/s");
    }

    #[test]
    fn new_throttle_request_cancels_the_pending_afterburner() {
        // AB request at t = 0 (RPM 70 → 2 s); a second one at 1 s re-times it from the RPM then (85 % → 1 s)
        // and applies its own value (v1.0: the first timer fired at 2 s with the first value).
        let mut a = airborne(100, 5000.0, 200.0);
        a.set_controls(Controls { throttle: 1.0, ..Default::default() });
        run(&mut a, 1.0);
        a.set_controls(Controls { throttle: 0.8, ..Default::default() });
        assert_eq!(a.state().throttle, 0.74);
        run(&mut a, 0.95);
        assert_eq!(a.state().throttle, 0.74);
        run(&mut a, 0.1);
        assert_eq!(a.state().throttle, 0.8);
    }

    #[test]
    fn landed_flag_rearmed_at_lift_off() {
        let mut a = airborne(0, 20.0, 80.0);
        a.ground_height = 0.0;
        a.gear.reset(0.0, 0.0);
        let land = |a: &mut Aircraft| {
            a.axes[2] = Axis::new(-0.1, -1.0);
            let t = a.t;
            a.transitions(t);
            assert!(a.on_ground && a.crashed.is_none());
        };
        let lift_off = |a: &mut Aircraft| {
            a.axes[2] = Axis::new(1.0, 2.0);
            let t = a.t;
            a.transitions(t);
            assert!(!a.on_ground);
        };
        land(&mut a);
        assert_eq!(a.state().landings, 1);
        // Rolling on: no new landing.
        a.axes[2] = Axis::new(0.0, 0.0);
        let t = a.t;
        a.transitions(t);
        assert_eq!(a.state().landings, 1);
        // Every landing after a lift-off fires again (v1.0: only the first).
        lift_off(&mut a);
        land(&mut a);
        assert_eq!(a.state().landings, 2);
        // A belly landing (gear not down) does not count.
        lift_off(&mut a);
        a.gear.reset(a.t, 1.0);
        land(&mut a);
        assert_eq!(a.state().landings, 2);
    }
}
