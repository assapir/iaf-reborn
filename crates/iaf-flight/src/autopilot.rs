//! The AI's autopilot: the original's control loops (`atp.ControlLoop.h`, docs/ai.md §7–§8) flying an
//! [`Aircraft`] through its normal inputs (stick, throttle, rudder, gear, flaps, brakes). Modes as the FM's
//! `setMode` (`5a8410`): 7 navigate the route, 8 go home and land, 9 take-off sequence, 1 / 3 close /
//! tactical formation on the formation leader, 10 hold, 0xb straight; combat: 0x11 Dogchase on `target`.
//!
//! Frame: ENU metres (x east, y north, z up) of the aircraft; headings clockwise from north.

use crate::airbase::{Airbase, TaxiPt};
use crate::aircraft::{Aircraft, ApView, Controls, G, sign, unit};

/// What the autopilot reads from and does to a flight model: the original's [`Aircraft`], or the Modern IAF sim's
/// 6-DoF ([`crate::sixdof::flight::SixDof`]).
pub trait Host {
    fn ap_view(&self) -> ApView;
    /// Vmin(alt, g) of the flight data's envelope, m/s.
    fn vmin(&self, alt: f32, g: f32) -> f32;
    fn controls(&self) -> Controls;
    fn set_controls(&mut self, c: Controls);
    /// While a loop flies, the roll trim is left out (`Aircraft::stores_trim`).
    fn set_stores_trim(&mut self, on: bool);
    fn set_ai_since(&mut self, t: f64);
    fn set_ai_mode(&mut self, mode: u8);
    /// The taxi re-placement at rest (`5a4d40`) and the pivot turn (motion 0x16).
    fn replace_on_ground(&mut self, x: f64, y: f64, heading: f32);
    fn set_pivot(&mut self, target: Option<f32>);
    fn engine_off(&mut self);
}

impl Host for Aircraft {
    fn ap_view(&self) -> ApView {
        Aircraft::ap_view(self)
    }
    fn vmin(&self, alt: f32, g: f32) -> f32 {
        Aircraft::vmin(self, alt, g)
    }
    fn controls(&self) -> Controls {
        Aircraft::controls(self)
    }
    fn set_controls(&mut self, c: Controls) {
        Aircraft::set_controls(self, c)
    }
    fn set_stores_trim(&mut self, on: bool) {
        self.stores_trim = on;
    }
    fn set_ai_since(&mut self, t: f64) {
        self.ai_since = t;
    }
    fn set_ai_mode(&mut self, mode: u8) {
        self.ai_mode = mode;
    }
    fn replace_on_ground(&mut self, x: f64, y: f64, heading: f32) {
        Aircraft::replace_on_ground(self, x, y, heading)
    }
    fn set_pivot(&mut self, target: Option<f32>) {
        Aircraft::set_pivot(self, target)
    }
    fn engine_off(&mut self) {
        Aircraft::engine_off(self)
    }
}
use crate::vec3::Vec3;
use iaf_formats::ini::Section;
use std::f32::consts::PI;

/// `[Autopilot]` of bd.ibx (loader around `5c726d`); defaults are the exe's.
#[derive(Debug, Clone, Copy)]
pub struct Config {
    pub roll_k: f32,
    pub roll_beta: f32,
    pub pitch_k: f32,
    pub pitch_beta: f32,
    pub speed_k: f32,
    pub speed_beta: f32,
    pub change_alt_k: f32,
    pub change_alt_beta: f32,
    pub change_head_k: f32,
    pub change_head_beta: f32,
    pub look_at_k: f32,
    pub look_at_beta: f32,
    pub watch_ground_dt: f32,
    pub change_roll_cone: f32,
    pub dog_chase_roll_k: f32,
    pub dog_chase_roll_beta: f32,
    pub no_change_roll_cone: f32,
    pub slow_cone_roll_k: f32,
    pub nose_on_target: f32,
    /// Dogchase's aim point behind the target (exe 500, v1.1 bdgen.dat 300).
    pub distance_behind_target: f32,
    pub h_above_ground: f32,
    /// AllowedErrPt2..6 (index 0 = Pt2).
    pub allowed_err: [f32; 5],
    pub fpm_pitch_low: f32,
    pub speed_taxi_k: f32,
    pub speed_taxi_beta: f32,
}

impl Default for Config {
    fn default() -> Self {
        Self::from_section(&Section::default())
    }
}

impl Config {
    /// The `[Autopilot]` section of the install's bd.ibx (v1.1: bdgen.dat), else the defaults.
    pub fn load(install: &std::path::Path) -> Self {
        crate::read_md(install, "bd.ibx")
            .ok()
            .and_then(|b| iaf_formats::ini::Ini::parse(&b).section("Autopilot").map(Config::from_section))
            .unwrap_or_default()
    }

    pub fn from_section(s: &Section) -> Self {
        let f = |k: &str, d: f32| s.f32(k).unwrap_or(d);
        let deg = |k: &str, d: f32| f(k, d).to_radians();
        let speed_k = f("SpeedK", 6.0);
        let speed_beta = f("SpeedBeta", 0.5);
        Config {
            roll_k: f("RollK", 4.0),
            roll_beta: f("RollBeta", 0.02),
            pitch_k: f("PitchK", 16.0),
            pitch_beta: f("PitchBeta", 0.75),
            speed_k,
            speed_beta,
            change_alt_k: f("ChangeAltK", 6.0),
            change_alt_beta: f("ChangeAltBeta", 0.005),
            change_head_k: f("ChangeHeadK", 3.0),
            change_head_beta: f("ChangeHeadBeta", 1.0),
            look_at_k: f("LookAtK", 16.0),
            look_at_beta: f("LookAtBeta", 0.75),
            watch_ground_dt: f("WatchGroundDeltaTime", 4.0),
            change_roll_cone: deg("ChangeRollCone", 15.0),
            dog_chase_roll_k: f("DogChaseRollK", 8.0),
            // The loader reads the misspelt key "DogChasecRollBeta" (0x67bbe0): the file's value is never used.
            dog_chase_roll_beta: f("DogChasecRollBeta", 0.02),
            no_change_roll_cone: deg("NoChangeRollCone", 0.7),
            slow_cone_roll_k: deg("SlowConeRollK", 90.0),
            nose_on_target: deg("NoseOnTargetAng", 7.0),
            distance_behind_target: f("DistanceBehindTarget", 500.0),
            h_above_ground: f("hAboveGround", 200.0),
            allowed_err: [
                f("AllowedErrPt2", 1500.0),
                f("AllowedErrPt3", 1500.0),
                f("AllowedErrPt4", 1000.0),
                f("AllowedErrPt5", 200.0),
                f("AllowedErrPt6", 10.0),
            ],
            fpm_pitch_low: deg("FpmPitchReqAtLowVels", -5.0),
            speed_taxi_k: f("SpeedTaxiK", speed_k),
            speed_taxi_beta: f("SpeedTaxiBeta", speed_beta),
        }
    }
}

/// A route waypoint (runtime record, docs/ai.md §7.2): position, planned arrival time (sim s, 0 = none),
/// action (2 take-off, 3 navigate, 7 land, 8 hold).
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Waypoint {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub t: f64,
    pub action: i32,
}

/// The formation leader (member 0, `FUN_00587450`) as the formation, taxi and take-off loops see it.
#[derive(Debug, Clone, Copy)]
pub struct Leader {
    pub pos: Vec3,
    pub vel: Vec3,
    /// Pitch, roll, heading (rad).
    pub att: [f32; 3],
    /// Alive and controlled (`!free` in the taxi loops).
    pub active: bool,
}

// Constants (docs/ai.md §7–§8).
const V_MIN_NAV: f32 = 180.0; // 0x6134f0
const V_MAX_NAV: f32 = 300.0; // 0x6134f4
const V_NO_ETA: f32 = 275.0;
const C130: u32 = 225;
const PASS_R: f64 = 1852.0;
/// Ours, the player's StopPlane flare ([`Landing::flare`]): the sink it asks for is the wheels' height over
/// `FLARE_TAU` (s) plus `FLARE_SINK` (m/s). It asks for the vertical acceleration `FLARE_KV` (1/s) × the sink's
/// error, which with `FLARE_TAU` = 2 / `FLARE_KV` is critically damped, plus that error summed at `FLARE_KI`
/// (1/s²), at most `FLARE_I_MAX` (m/s²). FinalApproach hands over to it once the wheels are below the profile's
/// height for the jet's sink.
const FLARE_TAU: f32 = 2.0;
const FLARE_SINK: f32 = 1.5;
const FLARE_KV: f32 = 2.0;
const FLARE_KI: f32 = 0.5;
const FLARE_I_MAX: f32 = 3.0;
/// Ours, the flare on the 6-DoF ([`ApView::final_speed`] set), s: the time its g takes to follow a command with the
/// gear down (63 % in 2.0–2.3 s at 220 kt, test `sixdof_g_follows_a_command`). The flare's sum takes the sink the
/// jet's present vertical acceleration leaves after it (modern-iaf/docs/flight-model.md §9.6).
const FLARE_LAG_6DOF: f32 = 2.0;
/// Ours, an AI jet's flare on the 6-DoF, s: the flare flies the sink this far ahead (the vertical acceleration's
/// part added). The MiG-29A's vertical acceleration follows the flare's command about 2 s late; on the sink of the
/// moment the flare pushed while the jet still rose (0.5 m/s at 13° of pitch, 3 m off the runway) and the push came
/// on as it neared the runway: 2.3 m/s at the touch on level ground, 4.7 m/s where it falls (a crash). Swept
/// 2026-11-22 (`crates/iaf-ai/tests/landing.rs`): 0.5 s 2.0 m/s, 1.0 s 1.3 m/s, 1.5 s 2.0 m/s, 2.0 s 2.5 m/s.
const FLARE_LEAD_AI: f32 = 1.0;
/// Ours, Modern IAF's 6-DoF ([`ApView::final_speed`] set): the real final's α and glide path, deg. The α is the F-16
/// manual's 13° (T.O. GR1F-16CJ-1 p. 2-23, "arrive on final at 11 or 13 degrees AOA", and figure 2-3), the F-35's
/// too (the Eglin F-35A accident report); the glide path the usual 3° of an ILS (inferred: the F-16 manual gives
/// none). modern-iaf/docs/flight-model.md §9.6.
pub const REAL_FINAL: (f32, f32) = (13.0, 3.0);
/// Ours, the landing circuit on Modern IAF's 6-DoF ([`ApView::circuit`], modern-iaf/docs/flight-model.md §9.6), deg:
/// the α where the F-16's control system leaves its g command for its limiter (T.O. 1F-16A-1: "g increments per
/// stick force for AOA below 15 degrees"): the circuit asks no more lift than the wing gives there; and the faster
/// of the manual's two approach αs ("11 or 13 degrees AOA", T.O. GR1F-16CJ-1 figure 2-3): the gear-down legs fly no
/// slower than its level speed, so the turn to the final has the lift of 15° over 11° α, a bank near 40°.
pub const REAL_CIRCUIT: (f32, f32) = (15.0, 11.0);
/// The time the circuit's path law takes to close a flight-path error on the 6-DoF, s: twice the slowest time the
/// jet's g takes to follow a g command (63 % in 0.8–0.9 s at 450 kt, 2.0–2.3 s at 220 kt with the gear down, test
/// `sixdof_g_follows_a_command`), which damps the loop of a path error through such a lag at 0.7.
const PATH_TAU: f32 = 5.0;
/// Ours, the real final's laws on the 6-DoF (swept 2026-11-16, modern-iaf/docs/flight-model.md §9.6): the path's
/// gain, deg of flight path per m off the glide path, the same both sides (the original's 0.3 above / 0.03 below
/// cycled ±2 m/s about the path at 150 kt); its damping, deg per deg/s of path rate (the original's 0.5); the flare's
/// `FLARE_TAU`, s (the 6-DoF's g lags: its flare starts at 6 × (sink − 1.5) ≈ 15 m).
const REAL_FINAL_LAWS: (f32, f32, f32) = (0.1, 1.0, 6.0);

/// Ours, the slot loop (Modern IAF's flights, docs/ai.md §8.7): the mode number (the original's modes end at 0x18).
pub const MODE_SLOT: u8 = 0x20;
/// The slot loop's laws, all inferred (tuned on the 6-DoF, test `crates/iaf-ai/tests/four_ship.rs`): the position
/// loop's natural frequency (rad/s) and damping across the flight path; the error it acts on at most (m, the
/// horizontal and the vertical each), so a far slot is closed sideways at about `SLOT_W · SLOT_E_MAX / (2 ·
/// SLOT_ZETA)` m/s; the along-track gain (m/s of overtake per m) and its overtake limits (m/s); the throttle's PI
/// gains (per m/s, per m/s·s); the load factor it asks at most; the bank it flies at most (deg).
const SLOT_W: f64 = 0.3;
const SLOT_ZETA: f64 = 0.8;
const SLOT_E_MAX: f64 = 150.0;
const SLOT_K_ALONG: f64 = 0.08;
const SLOT_OVERTAKE: (f64, f64) = (-30.0, 60.0);
const SLOT_THR: (f32, f32) = (0.03, 0.01);
const SLOT_G_MAX: f32 = 7.0;
const SLOT_BANK_MAX: f64 = 75.0;
/// Ours, the slot loop's roll law (inferred): the stick per radian of bank error and per rad/s of roll rate, over the
/// jet's highest roll rate, close up ([`Autopilot::close`]). The original's (`RollK`, `RollBeta`) rolled a wingman 12 m
/// off the lead into its 45° bank turn so late that its pull-away tripped and threw it 98 m out of its slot; with this
/// one, 10 m at most (test four_ship `close_up_and_spread_out`). At the standard spacing the original's stays (this one
/// moved the landings' order and spacing).
const SLOT_ROLL: (f32, f32) = (4.0, 0.3);
/// Close up ([`Autopilot::close`]), the slot loop's throttle gain is this many times [`SLOT_THR`]'s (inferred: with
/// the standard gain a wingman 30 m off the lead still swung 7.6 m along its slot half a minute after the close-up,
/// with this one 3.5 m).
const SLOT_CLOSE_KP: f32 = 3.0;
/// Close up ([`Autopilot::close`]), the slot loop rolls the leader's lift on by the leader's roll rate over this, s (the
/// wingman's roll lag; inferred: without it, a wingman 12 m off the lead in its roll into a 45° bank turn fell 98 m
/// out of its slot, with it 10 m).
const SLOT_ROLL_LEAD_S: f64 = 0.5;
/// A slot leader this far from where its last position and velocity put it is a new leader (a promotion), m.
const LEADER_JUMP_M: f64 = 20.0;
/// Ours, the flight's collision avoidance ([`Autopilot::avoid`]): the acceleration it pulls away with, m/s² (3 g;
/// inferred).
const AVOID_A: f64 = 3.0 * G as f64;
/// Below this over the ground the avoidance never pulls down, m.
const AVOID_LOW_M: f64 = 150.0;
/// The slot loop's speed leads the slot's acceleration by this, s (the throttle's and the speed brake's lag).
const SLOT_ANTICIPATE_S: f64 = 1.5;
/// Ours, the steer loop (Modern IAF's flights, docs/ai.md §8.8): the mode number.
pub const MODE_STEER: u8 = 0x21;
/// The steer loop's laws, inferred: the turn rate it asks per radian of heading error (1/s); the height loop's
/// natural frequency (rad/s) and damping.
const STEER_K: f64 = 0.3;
const STEER_W: f64 = 0.15;
const STEER_ZETA: f64 = 0.8;
/// The bank the steer loop flies at most for a [`Steer::fighter`] (deg): a level turn holds its height up to
/// 1 / cos 85° = 11 g, and a 6.5 g turn going down at 85° has 0.56 g of lift upward (at the slot loop's 75° the full
/// load factor lifted the jet: a notch's 6.5 g turn climbed at 39 m/s, 22 November 2026).
const STEER_BANK_MAX: f64 = 85.0;
/// The steer loop goes down (at most 1 g of lift upward) for a [`Steer::fighter`] point this far below the jet (m): a
/// defence's descent (`iaf_ai::fighter`'s 500 m), not a level point's small error.
pub const STEER_DOWN_M: f64 = 200.0;
/// The enemy fighters' laws ([`Steer::fighter`]; inferred, 22 November 2026): the roll rate asked per radian of bank
/// error (1/s), within the jet's MaxRollRate, and the height law's natural frequency (rad/s; the damping is the steer
/// loop's). The 1998 roll law (`5c9bc0`) rolls in with a time constant near 1.3 s on the 6-DoF: a 6.5 g turn was still
/// rolling in after 4 s. A bank a little past the target sinks a 9 g turn fast (a degree is 0.16 g): at the steer
/// loop's 0.15 rad/s the plain tactics' level break lost 46 m in 8 s, at 0.5 rad/s 9 m (0.3: 17 m, 0.8: 7 m; a damping
/// term on the roll rate changed nothing). `crates/iaf-ai/tests/intercept.rs` `fighter_laws_only_when_asked`,
/// `dogfight.rs` `defensive_break`.
const FIGHTER_ROLL_K: f32 = 4.0;
const FIGHTER_STEER_W: f64 = 0.5;
/// Ours, the BFM loop (Modern IAF's enemy fighters, docs/ai.md §18.2): the mode number; the turn rate it asks per
/// radian of the angle between the flight path and the line to its point (1/s), and its tick (s): the least mean
/// tracking error behind a jet in a 5 g turn (`crates/iaf-ai/tests/dogfight.rs`: 2.9° at 0.5 and 1/30 s, 5.7° at 1.0,
/// 3.9° at 0.1 s; inferred).
pub const MODE_BFM: u8 = 0x22;
const BFM_K: f64 = 0.5;
const BFM_PERIOD: f64 = 1.0 / 30.0;
/// The BFM loop: the swing of the line to its point it follows at most (rad/s; a jet's turn near its corner speed: a
/// faster swing is a new point); the line's steepest climb or dive off the horizon (deg; inferred: no loops, the bank
/// about the horizon stays defined).
const BFM_SWING: f64 = 1.0;
/// The BFM loop opens the speed brake this much faster than its order's speed (m/s; the speed law is at idle 23 m/s
/// fast; inferred).
const BFM_BRAKE_MS: f32 = 25.0;
const BFM_STEEP: f64 = 60.0;

/// Ours, the AI jets' ground collision avoidance (Modern IAF's, [`Autopilot::floor`], docs/ai.md §20): the fly-up rolls
/// wings level and pulls this load factor (the F-16's Auto GCAS: a roll to wings level, then a 5 g pull[^gcas]), to a
/// climb of [`FLY_UP_DEG`] (inferred), held until the predicted fly-up clears the floor by half again and the jet
/// climbs. The prediction: [`FLY_UP_LAG_S`] of delay (inferred: the 6-DoF's load factor builds over about a second)
/// and the roll at the jet's roll rate, the climb rate changing as its acceleration has it now, then the pull, then
/// the climb [`FLY_UP_LOOK_S`] on (inferred), in steps of [`FLY_UP_STEP_S`], at most every [`FLY_UP_CHECK_S`] (the
/// host's terrain is a script call).
///
/// [^gcas]: NASA / AFRL, "Automatic Ground Collision Avoidance System" briefing (ntrs.nasa.gov 20090035618): the
///     maneuver phase is a roll to wings level and a 5 g pull.
pub const FLY_UP_G: f32 = 5.0;
const FLY_UP_DEG: f64 = 20.0;
const FLY_UP_LAG_S: f64 = 1.0;
const FLY_UP_LOOK_S: f64 = 3.0;
const FLY_UP_STEP_S: f64 = 0.25;
const FLY_UP_CHECK_S: f64 = 0.1;
/// Ours, the terrain following ([`Autopilot::follow`], docs/ai.md §20; inferred): the terrain this far ahead along the
/// track (s of flight, one sample a second) is cleared by its height when climbed to at [`FOLLOW_DEG`]. The height law:
/// the height's own rate (the same profile a second on) plus a climb rate of [`FOLLOW_K`] per m of height error (1/s),
/// within a path [`FOLLOW_PATH_DEG`] below and above the horizon, flown by [`FOLLOW_KV`] of lift upward per m/s of
/// climb rate error (1/s), within `.0` g down and `.1` g up (a descent eases over; the climbs pull).
const FOLLOW_LOOK_S: usize = 10;
const FOLLOW_LEAD_S: f64 = 1.5;
const FOLLOW_DEG: f64 = 10.0;
const FOLLOW_K: f64 = 0.3;
const FOLLOW_PATH_DEG: (f64, f64) = (15.0, 30.0);
const FOLLOW_KV: f64 = 1.0;
const FOLLOW_G: (f64, f64) = (0.8, 2.0);

/// The horizontal unit of the jet's track (its heading when it flies straight up or down).
fn track(v: &ApView) -> Vec3 {
    let h = v.att.heading as f64;
    Vec3::new(v.vel[0], v.vel[1], 0.0).try_normalize().unwrap_or(Vec3::new(h.sin(), h.cos(), 0.0))
}

/// Ours, the least clearance (m) over the terrain `ground` of a fly-up started now at `n` g ([`FLY_UP_G`]), along the
/// jet's present track.
pub fn fly_up_clearance(v: &ApView, ground: Ground, n: f64) -> f64 {
    let g = G as f64;
    let speed = (v.speed as f64).max(50.0);
    let th = track(v);
    let mut gam = 0.0;
    let t_roll = FLY_UP_LAG_S + (v.att.roll as f64).abs() / (v.max_roll_rate as f64).max(0.5);
    let up = FLY_UP_DEG.to_radians();
    let (mut s, mut h, mut t, mut end) = (0.0, v.pos[2], 0.0, f64::INFINITY);
    let mut low = h - ground(v.pos[0], v.pos[1]) as f64;
    while t < end && t < 30.0 {
        if t < t_roll {
            // The delay and the roll: the climb rate goes on changing as the jet's acceleration has it now.
            gam = ((v.vel[2] + v.acc[2] * t) / speed).clamp(-1.0, 1.0).asin();
        } else if gam < up {
            gam = (gam + g * (n - gam.cos()) / speed * FLY_UP_STEP_S).min(up);
        }
        if gam >= up && end.is_infinite() {
            end = t + FLY_UP_LOOK_S;
        }
        s += speed * gam.cos() * FLY_UP_STEP_S;
        h += speed * gam.sin() * FLY_UP_STEP_S;
        t += FLY_UP_STEP_S;
        let p = v.pos + th * s;
        low = low.min(h - ground(p[0], p[1]) as f64);
    }
    low
}

/// Ours, the terrain following's height (m) and its rate (m/s): the least height that clears the terrain
/// [`FOLLOW_LOOK_S`] ahead along the track by `agl` when climbed to at [`FOLLOW_DEG`], now and a second on.
pub fn follow_height(v: &ApView, ground: Ground, agl: f32) -> (f64, f64) {
    let th = track(v);
    let step = (v.speed as f64).max(50.0);
    let rise = step * FOLLOW_DEG.to_radians().tan();
    let hs: Vec<f64> = (0..=FOLLOW_LOOK_S + 1)
        .map(|i| {
            let p = v.pos + th * (step * i as f64);
            ground(p[0], p[1]) as f64 + agl as f64
        })
        .collect();
    let profile = |from: usize| {
        (from..hs.len())
            .map(|i| hs[i] - ((i - from) as f64 - FOLLOW_LEAD_S).max(0.0) * rise)
            .fold(f64::NEG_INFINITY, f64::max)
    };
    let now = profile(0);
    (now, profile(1) - now)
}

/// The unit direction `d` brought within [`BFM_STEEP`] of the horizon.
fn steep_cut(d: Vec3) -> Vec3 {
    let max = BFM_STEEP.to_radians().sin();
    if d[2].abs() <= max {
        return d;
    }
    let h = Vec3::new(d[0], d[1], 0.0).try_normalize().unwrap_or(Vec3::NORTH);
    h * (1.0 - max * max).sqrt() + Vec3::UP * max.copysign(d[2])
}

/// The steer loop's order ([`MODE_STEER`], set by the host): fly toward `to` at its height, turning at up to `g`, at
/// `speed` m/s with the throttle at most `thr_max` (0.74, military: the afterburner stays out). With `fighter`
/// (Modern IAF's enemy fighters only; the wingmen and the 1998 game never set it) the loop flies a hard turn as a
/// fighter pilot does: it rolls in at once ([`FIGHTER_ROLL_K`]) to up to [`STEER_BANK_MAX`], and pulls only the load
/// factor whose lift upward is what the point's height asks, so a level turn holds its height while it rolls in and
/// turns; a point more than [`STEER_DOWN_M`] below is flown as a turn going down.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Steer {
    pub to: Vec3,
    pub g: f32,
    pub speed: f32,
    pub thr_max: f32,
    pub fighter: bool,
}

/// The point of a slot `(forward, right, up)` m in the leader's horizontal frame: its track (its nose at rest), its
/// right, up.
pub fn slot_point(ld: &Leader, slot: [f32; 3]) -> Vec3 {
    ld.pos + slot_offset(ld, slot)
}

fn slot_offset(ld: &Leader, slot: [f32; 3]) -> Vec3 {
    let h = if ld.vel[0].hypot(ld.vel[1]) > 1.0 { ld.vel[0].atan2(ld.vel[1]) } else { ld.att[2] as f64 };
    let (s, c) = h.sin_cos();
    Vec3::new(s * slot[0] as f64 + c * slot[1] as f64, c * slot[0] as f64 - s * slot[1] as f64, slot[2] as f64)
}

/// Ours, an AI jet's taxi on the 6-DoF ([`Laws::taxi_thr`], inferred): the PI's gains (lever per m/s, per m/s·s)
/// and its highest lever.
const TAXI_PI: (f32, f32, f32) = (0.02, 0.01, 0.4);
/// Ours, an AI jet's take-off roll on the 6-DoF (inferred): the nose wheel's pedal per radian of heading error to the
/// runway's, per rad/s of turn, and at most below [`NWS_KT_MS`] (Autopilot::roll_steer).
const ROLL_STEER: (f32, f32, f32) = (1.0, 0.5, 0.1);
/// Ours, the take-off roll's line (inferred): the heading aimed at turns back onto the jet's line by the atan of its
/// distance off over this, m (2 m off: 1.1°, about where the castoring nose wheel engages).
const ROLL_LINE_LOOK: f32 = 100.0;
/// ... and past 30 kt, its nose wheel castoring, the pedal's error (rad, the heading's and its turn's) that engages
/// the nose wheel with the least pedal, [`NWS_PEDAL`] (inferred).
const ROLL_NUDGE: f32 = 0.005;
/// 30 kt, m/s, and the pedal: the 6-DoF's nose wheel castors above that speed unless a pedal this far engages it.
const NWS_KT_MS: f32 = 15.4333;
const NWS_PEDAL: f32 = 0.02;
/// Ours, an AI jet's taxi on the 6-DoF (inferred): a pivot begins at the turn's own lead, its radius × tan(half the
/// turn), m, within [5, 40] m (the original's 30 m for any turn: a 97° turn onto the runway swung 15 m past the
/// centreline, and the last pivot of 2° onto the lineup stopped the jet 30 m short of it); the departure's last point
/// is reached at a walk, m/s, and the take-off holds its brakes there.
const PIVOT_R: f32 = 40.0;
const PIVOT_LEAD: (f32, f32) = (5.0, 40.0);
const LINEUP_WALK: f32 = 2.0;
/// The leg to the lineup steers at the runway's line through the lineup this far ahead of the jet, m (inferred): at
/// the point alone a pairs wingman, swung 13 m past its line by the turn onto the runway, came to it 21° off and its
/// last pivot left it 10 m beside its lead, not 15.
const LINEUP_LOOK: f64 = 25.0;
/// ... with up to this wheel (the rudder's share; elsewhere between the pivots 0.1): the leg is flown at or below the
/// pivot's speed, slowing to [`LINEUP_WALK`].
const LINEUP_WHEEL: f32 = 0.3;
/// The pivot onto the lineup ends this near the runway's heading, deg (elsewhere 0.5°): the pivot's wheel is still near
/// full lock at 0.5°, and the 1.5° it swung on past put a pairs wingman 10 m wide by its lift-off.
const LINEUP_TOL_DEG: f32 = 0.1;
/// Ours, a pairs take-off's wingman on the roll (inferred): the lever about military power per m its lead is ahead,
/// per m/s the lead is faster, and at least.
const PAIR_KEEP: (f32, f32, f32) = (0.03, 0.1, 0.3);
/// Ours, a pairs take-off's wingman keeps station only on a lead this near, m.
const PAIR_NEAR_M: f64 = 200.0;
/// Ours, an AI jet's taxi on the 6-DoF (inferred): before a pivot of more than `.2` deg it slows to `.0` m/s, under
/// the speed of the pivot's 30 m wheel turn (9 m/s on the tyres' side grip), braking at most `.1` m/s² from the taxi
/// speed: at the 30 kt taxi speed it braked straight on into the turn and swung 40 m wide, into the next shelter's
/// spot at Nevatim (2026-11-22).
const PIVOT_IN: (f32, f32, f32) = (8.0, 1.5, 10.0);

/// The flare's `FLARE_TAU`: the real final's on the 6-DoF ([`REAL_FINAL_LAWS`]).
fn flare_tau(v: &ApView) -> f32 {
    if v.final_speed.is_some() { REAL_FINAL_LAWS.2 } else { FLARE_TAU }
}

/// Terrain height (m) at a world point (x, y), supplied by the host.
pub type Ground<'a> = &'a dyn Fn(f64, f64) -> f32;

/// The commands one loop tick posted (applied to the aircraft by [`Autopilot::step`] and returned, so the
/// player's host can mirror them on its levers like the original's controller `44a240` does).
#[derive(Debug, Clone, Copy, Default)]
pub struct Out {
    /// (pitch law output a, roll x); the stick's pull is −a.
    pub stick: Option<(f32, f32)>,
    pub thr: Option<f32>,
    pub rudder: Option<f32>,
    pub gear: Option<bool>,
    pub flaps: Option<bool>,
    pub brakes: Option<bool>,
    pub pivot: Option<Option<f32>>,
    pub replace: Option<(f64, f64, f32)>,
    pub engine_off: bool,
    /// The player's landing stopped (StopPlaneCL in FM mode 0, @5d4b40): it presses the autopilot key
    /// (GEV 0x10, forced), which turns the autopilot off from NAV.
    pub ap_key: bool,
    /// A bombing manoeuvre's release (LevelBomb / DiveBomb / PopupRelease, `440440`): the host fires the selected
    /// weapon through the fire gate, as action 300.
    pub release: bool,
}

fn wrap(a: f32) -> f32 {
    let mut a = a % (2.0 * PI);
    if a > PI {
        a -= 2.0 * PI;
    } else if a <= -PI {
        a += 2.0 * PI;
    }
    a
}

fn dist2(a: Vec3, x: f64, y: f64) -> f64 {
    (a[0] - x).hypot(a[1] - y)
}

/// Ours, an AI jet's taxi on the 6-DoF: where a pivot of `turn` rad begins before its point, m ([`PIVOT_R`]).
fn pivot_lead(turn: f32) -> f32 {
    (PIVOT_R * (turn / 2.0).tan()).clamp(PIVOT_LEAD.0, PIVOT_LEAD.1)
}

/// A taxi path's last point when it is the lineup (within 100 m of it).
fn path_end_at(path: &[TaxiPt], lineup: [f32; 3]) -> Option<TaxiPt> {
    let p = *path.last()?;
    (dist2(Vec3::new(p.x as f64, p.y as f64, 0.0), lineup[0] as f64, lineup[1] as f64) < 100.0).then_some(p)
}

/// `5d70a0` PassWaypoint: passed once the 2-D distance was ≤ R and then grows.
#[derive(Debug, Clone, Copy)]
struct Pass {
    r: f64,
    min: f64,
    armed: bool,
}

impl Pass {
    fn new(r: f64) -> Self {
        Pass { r, min: -1.0, armed: false }
    }
    fn test(&mut self, pos: Vec3, x: f64, y: f64) -> bool {
        let d = dist2(pos, x, y);
        let ret = self.armed && d > self.min;
        if d <= self.r {
            self.min = d;
            self.armed = true;
        }
        ret
    }
}

/// The laws of §8.0 on one FM view.
struct Laws<'a> {
    c: &'a Config,
    v: &'a ApView,
    mode: u8,
    watch: bool,
    ground: Ground<'a>,
    out: Out,
    period: Option<f64>,
    /// The landing circuit's legs before the final on Modern IAF's 6-DoF ([`REAL_CIRCUIT`]): the path law asks the
    /// g that closes its error over [`PATH_TAU`], the bank and that g stay inside the wing's lift, the speed law
    /// sums its error and the gear-down legs keep the turn's speed.
    real: Option<(f32, f32)>,
    /// The speed law's summed error (m/s, [`Landing::thr_i`]); the last speed law's lever and error; this tick's
    /// error, kept only when the lever sent is that law's and inside its travel (no sum while a cap holds it).
    thr_i: f32,
    thr_last: std::cell::Cell<Option<(f32, f32)>>,
    thr_err: Option<f32>,
}

impl<'a> Laws<'a> {
    /// `5aaa90(V, g)`: the stick (y convention, − = pull) that commands `g`.
    fn inv_g(&self, g: f32) -> f32 {
        let [cv, a, b] = self.v.stick_centre;
        let c = if self.v.speed < cv { a * self.v.speed + b } else { 1.0 };
        if g > c { (-(g - c) / (self.v.max_g - c)).max(-1.0) } else { ((g - c) / (self.v.min_g - c)).min(1.0) }
    }

    /// Roll law `5c9bc0`.
    fn roll(&self, target: f32) -> f32 {
        // The 6-DoF's circuit: no more bank than the wing holds level.
        let target = match self.real {
            Some((g, _)) => target.clamp(-(1.0 / g.max(1.0)).acos(), (1.0 / g.max(1.0)).acos()),
            None => target,
        };
        let rmax = self.v.max_roll_rate;
        let r = self.v.rates[1];
        let d = if r.abs() <= PI { r * rmax } else { 0.5 * rmax * r };
        (wrap(target - self.v.att.roll) / PI * self.c.roll_k / rmax - self.c.roll_beta * d).clamp(-1.0, 1.0)
    }

    /// The g → stick map of the pitch laws: c in ±1 → g (MaxG / MinG) → stick.
    fn g_stick(&self, c: f32) -> f32 {
        let g = if -c > 0.0 { (self.v.max_g - 1.0) * -c + 1.0 } else { (self.v.min_g - 1.0) * c + 1.0 };
        self.inv_g(g)
    }

    /// Clean-up at the start of the pitch laws: above 150 m/s outside modes 0 / 8, gear, flaps, brakes in.
    fn clean(&mut self) {
        if self.v.speed > 150.0 && self.mode != 0 && self.mode != 8 {
            self.gear(false);
            self.flaps(false);
            self.brakes(false);
        }
    }

    /// Pitch law A `5ca010` (pitch attitude target).
    fn pitch(&mut self, target: f32) -> f32 {
        self.clean();
        if let Some((avail, _)) = self.real {
            // The load factor that turns the path at e / PATH_TAU, at this bank; never a push below 0 g (inferred).
            let v = self.v;
            let n =
                (v.att.pitch.cos() + v.speed / G * wrap(target - v.att.pitch) / PATH_TAU) / v.att.roll.cos().max(0.2);
            return self.inv_g(n.clamp(0.0, avail.max(1.0)));
        }
        let roll = self.v.att.roll;
        if (roll.abs() - PI / 2.0).abs() < 1e-5 {
            return 0.0;
        }
        let inv_cos = 1.0 / roll.cos();
        let q0 = self.inv_g(inv_cos).clamp(-1.0, 1.0);
        let mut e = (target - self.v.att.pitch) % (2.0 * PI);
        if e > PI {
            e -= 2.0 * PI;
        }
        let mut c = e / PI * self.c.pitch_k * 0.5 - self.v.rates[0] * self.c.pitch_beta;
        if inv_cos >= 0.0 {
            c = -c;
        }
        if c > 0.0 {
            c *= 1.98;
        }
        let mut q = self.g_stick(c.clamp(-1.0, 1.0));
        if sign(q) == sign(q0) {
            q += q0;
        }
        q.clamp(-1.0, 1.0)
    }

    /// Pitch law B `5c9d30` (StopPlane): the flip and ×1.98 after the g map.
    fn pitch_b(&mut self, target: f32) -> f32 {
        self.clean();
        let roll = self.v.att.roll;
        if (roll.abs() - PI / 2.0).abs() < 1e-5 {
            return 0.0;
        }
        let inv_cos = 1.0 / roll.cos();
        let q0 = self.inv_g(inv_cos).clamp(-1.0, 1.0);
        let e = wrap(target - self.v.att.pitch);
        let c = (e / PI * self.c.pitch_k * 0.5 - self.v.rates[0] * self.c.pitch_beta).clamp(-1.0, 1.0);
        let mut q = self.g_stick(c);
        if inv_cos >= 0.0 {
            q = -q;
        }
        if q > 0.0 {
            q *= 1.98;
        }
        if sign(q) == sign(q0) {
            q += q0;
        }
        q.clamp(-1.0, 1.0)
    }

    /// Speed law `5ca360`: throttle for a target TAS.
    fn thr(&self, vt: f32) -> f32 {
        self.thr_k(vt, self.c.speed_k, self.c.speed_beta)
    }

    fn thr_k(&self, vt: f32, k: f32, beta: f32) -> f32 {
        let (f, _, _) = self.v.att.basis();
        let a_long = (f[0] * self.v.acc[0] + f[1] * self.v.acc[1] + f[2] * self.v.acc[2]) as f32;
        let lever = |vt: f32| 0.7 + 0.005 * k * (vt - self.v.speed) - 0.02 * beta * a_long;
        let Some((_, turn)) = self.real else { return lever(vt).clamp(0.0, 1.0) };
        // The 6-DoF's circuit: the law's fixed 0.7 lever at no error holds the jet 30–50 kt fast, so the error is
        // summed (0.2 /s, as the real final's) while the lever is inside its travel.
        let vt = if self.v.gear_down { vt.max(turn) } else { vt };
        let u = lever(vt + self.thr_i).clamp(0.0, 1.0);
        self.thr_last.set(Some((u, vt - self.v.speed)));
        u
    }

    /// The taxi's speed law (the original's, `5cc9d0`); for an AI jet on the 6-DoF (ours, inferred) a PI from idle on
    /// the speed at the taxi's 0.2 s tick, its summed lever in `i`: the original's 0.7 lever at no error is near the
    /// 6-DoF engine's military power, which ran the jet past its taxi speed and tipped it in a braked pivot.
    fn taxi_thr(&self, vt: f32, i: &mut f32) -> f32 {
        if !self.v.sixdof || self.mode == 0 {
            return self.thr_k(vt, self.c.speed_taxi_k, self.c.speed_taxi_beta);
        }
        let (kp, ki, max) = TAXI_PI;
        let e = vt - self.v.speed;
        let u = (*i + kp * e).clamp(0.0, max);
        if u > 0.0 && u < max {
            *i = (*i + ki * e * 0.2).clamp(0.0, max);
        }
        u
    }

    /// Watch-ground `5ca480`: 1 = override (wings level, climb over the terrain ahead, ≥ 250 m/s throttle).
    fn watch_ground(&mut self, x: &mut f32, y: &mut f32, thr: &mut f32) -> bool {
        if !self.watch || self.v.on_ground {
            return false;
        }
        let (p, vel) = (self.v.pos, self.v.vel);
        let t = (vel[2] as f32 * (-1.0 / 15.0)).max(0.0) + self.c.watch_ground_dt;
        let a = p + vel * t as f64;
        let h = (self.ground)(a[0], a[1]) + self.c.h_above_ground;
        if a[2] as f32 > h && self.los(p, a) {
            return false;
        }
        *x = self.roll(0.0);
        let dh = ((a[0] - p[0]).hypot(a[1] - p[1])) as f32;
        let climb = wrap(PI / 24.0 + (h - p[2] as f32).atan2(dh));
        *y = self.pitch(climb.max(0.0));
        *thr = self.thr(250.0).max(*thr);
        true
    }

    /// `0x4020d0` line of sight: the segment clears the terrain. UNCERTAIN (the original's terrain ray); here
    /// 8 samples along the segment.
    fn los(&self, a: Vec3, b: Vec3) -> bool {
        (1..=8).all(|i| {
            let f = i as f64 / 8.0;
            let z = a[2] + (b[2] - a[2]) * f;
            z as f32 > (self.ground)(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        })
    }

    fn stick(&mut self, y: f32, x: f32) {
        self.out.stick = Some((y, x));
    }
    fn throttle(&mut self, t: f32) {
        self.out.thr = Some(t);
        let last = self.thr_last.take().filter(|&(u, _)| u == t);
        // Ours: an AI jet going home on the 6-DoF ([`Laws::real`], mode 8) opens the speed brake while its speed law is
        // at idle and still 15 m/s fast: the clean jet bleeds speed slowly, entered the landing circuit at 235 m/s and
        // lowered the gear at 390 kt.
        if let Some((_, e)) = last.filter(|_| self.real.is_some() && self.mode == 8) {
            self.out.brakes = Some(t <= 0.0 && e < -15.0);
        }
        self.thr_err = last.filter(|_| t > 0.0 && t < 1.0).map(|(_, e)| e);
    }
    fn gear(&mut self, down: bool) {
        self.out.gear = Some(down);
    }
    fn flaps(&mut self, down: bool) {
        self.out.flaps = Some(down);
    }
    fn brakes(&mut self, on: bool) {
        self.out.brakes = Some(on);
    }

    /// LookAt `5ca7d0` + `5cb4d0` (formation: case 1). Returns (y, x) or None when on the target.
    fn look_at(&mut self, t: Vec3, t_roll: f32, case: u8) -> Option<(f32, f32)> {
        let p = self.v.pos;
        let d = t - p;
        let dist = d.length();
        if dist <= 0.0 {
            return None;
        }
        let (f, r, u) = self.v.att.basis();
        let dn = d / dist;
        let dot = |a: Vec3| a.dot(dn) as f32;
        let (v0, v1, v2) = (dot(r), dot(f), dot(u));
        let mut elev = v2.atan2(v0.hypot(v1));
        if v1 < 0.0 {
            elev = PI - elev;
        }
        let off = v1.clamp(-1.0, 1.0).acos();
        let roll = self.v.att.roll;
        let c = self.c;
        let mut roll_err = 0.0;
        if off >= c.change_roll_cone {
            let n = v2.hypot(v0);
            if n > 0.0 {
                roll_err = (v2 / n).clamp(-1.0, 1.0).acos() * if v0 >= 0.0 { 1.0 } else { -1.0 };
            }
            if roll_err.abs() > PI / 3.0 {
                elev = 0.0;
            }
        } else {
            let psi = v0.atan2(v1);
            let e = wrap(t_roll - roll);
            let (ncc, crc, slow) = (c.no_change_roll_cone, c.change_roll_cone, c.slow_cone_roll_k);
            // 5ada30: the straight line through (x0, y0) and (x1, y1).
            let line = |x: f32, x0: f32, y0: f32, x1: f32, y1: f32| y0 + (y1 - y0) * (x - x0) / (x1 - x0);
            roll_err = match case {
                1 => {
                    if dist >= 1854.0 {
                        -roll
                    } else if psi >= ncc {
                        line(psi, ncc, e, crc, slow).min(PI / 2.0)
                    } else if psi > -ncc {
                        e
                    } else {
                        line(psi, -ncc, e, -crc, -slow).max(-PI / 2.0)
                    }
                }
                3 => -roll,
                4 => e,
                _ => 0.0,
            };
        }
        let elev = wrap(elev);
        let roll_err = wrap(roll_err);
        // 5cb4d0.
        let rmax = self.v.max_roll_rate;
        let rr = self.v.rates[1];
        let dd = if rr.abs() <= PI { rr * rmax } else { 0.5 * rmax * rr };
        let x = (roll_err / PI * c.dog_chase_roll_k / rmax - c.dog_chase_roll_beta * dd).clamp(-1.0, 1.0);
        let mut pp = -(elev / PI * c.look_at_k * 0.5 - self.v.rates[0] * c.look_at_beta);
        if pp > 0.0 {
            pp *= 1.98;
        }
        let mut y = self.g_stick(pp.clamp(-1.0, 1.0));
        let q0 = self.inv_g(1.0 / roll.cos()).clamp(-1.0, 1.0);
        if (roll - PI / 2.0).abs() >= 1e-5 && sign(q0) == sign(y) {
            y += q0;
        }
        Some((y.clamp(-1.0, 1.0), x))
    }
}

// --- leaf loops -----------------------------------------------------------------------------------

/// A leaf's result for its parent.
#[derive(PartialEq)]
enum Leaf {
    Run,
    Done,
}

/// ChangeHeading2Pt `5ddef0` (and the landing's ChangeHeading2PtAcu, UNCERTAIN: its line capture): bank on
/// the bearing error, pitch 0; done within `tol`.
fn change_heading(l: &mut Laws, t: [f64; 2], tol: f32, lim: f32, hold_speed: Option<f32>) -> Leaf {
    let p = l.v.pos;
    let brg = ((t[0] - p[0]) as f32).atan2((t[1] - p[1]) as f32);
    let e = wrap(brg - l.v.att.heading);
    if e.abs() <= tol {
        return Leaf::Done;
    }
    let bank = (e / (PI / 6.0) * l.c.change_head_k * lim - l.v.rates[2] * l.c.change_head_beta).clamp(-lim, lim);
    let mut y = l.pitch(0.0);
    let mut x = l.roll(bank);
    let mut thr = hold_speed.map_or(0.0, |s| l.thr(s).min(0.7));
    // ChangeHeading2Pt sends no throttle (its watch-ground throttle is dropped); the landing's CH4 / CH5
    // hold 140 kt (throttle ≤ 0.7, 0x613888).
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
    if hold_speed.is_some() {
        l.throttle(thr);
    }
    Leaf::Run
}

/// ChangeAlt `5cf320`: wings level, pitch from the altitude error (ends only by its condition).
fn change_alt(l: &mut Laws, z: f64) {
    let c130 = l.v.type_code == C130;
    let k = if c130 { 0.002 } else { 0.001 };
    let (lo, hi) = if c130 { (-PI / 12.0, PI / 18.0) } else { (-PI / 6.0, PI / 12.0) };
    let pt = ((z - l.v.pos[2]) as f32 * l.c.change_alt_k * (PI / 12.0) * k - l.v.vel[2] as f32 * l.c.change_alt_beta)
        .clamp(lo, hi);
    let mut x = l.roll(0.0);
    let mut y = l.pitch(pt);
    let mut thr = 0.0;
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
}

/// KeepAttitude2Pt `5db510` (+ AtSpeed `5dbb80` with `speed`): bank ≤ 45° on the bearing error, pitch to the
/// elevation of the point; the ring period from `5db930`.
fn keep_attitude(l: &mut Laws, t: Vec3, speed: Option<f32>) {
    let thr = speed.map(|s| l.thr(s));
    let p = l.v.pos;
    let d = t - p;
    let e = wrap((d[0] as f32).atan2(d[1] as f32) - l.v.att.heading);
    let roll_t = e.clamp(-PI / 4.0, PI / 4.0);
    let elev = (d[2] as f32).atan2(d[0].hypot(d[1]) as f32);
    let mut y = l.pitch(elev);
    let mut x = l.roll(roll_t);
    let mut dummy = 0.0;
    l.watch_ground(&mut x, &mut y, &mut dummy);
    // 5db930: the ring period.
    let dist = d.length();
    let v = l.v.vel;
    let ahead = |k: f64| p + v * k;
    l.period = Some(if dist < 1854.0 || y.abs() > 0.01 || x.abs() > 0.01 {
        0.5
    } else if dist < 3708.0 {
        if l.los(p, ahead(1.9)) { 1.5 } else { 0.5 }
    } else if l.los(p, ahead(3.4)) {
        3.0
    } else {
        0.5
    });
    l.stick(y, x);
    if let Some(t) = thr {
        l.throttle(t);
    }
}

/// LevelWingsPitch0Accel `5d2400`: wings level, pitch 0 (FpmPitchReqAtLowVels below Vmin(1.2 g)), speed.
fn level_wings_accel(l: &mut Laws, pitch_t: &mut f32, speed: f32, vmin: f32) -> Leaf {
    level_wings_accel_max(l, pitch_t, speed, vmin, None)
}

/// [`level_wings_accel`]; ours: `max` keeps it running while faster than that.
fn level_wings_accel_max(l: &mut Laws, pitch_t: &mut f32, speed: f32, vmin: f32, max: Option<f32>) -> Leaf {
    let c130 = l.v.type_code == C130;
    let tol = if c130 { 6.0 } else { 3.0 };
    let spd_ok = (l.v.speed > speed || (l.v.speed - speed).abs() <= tol) && max.is_none_or(|m| l.v.speed <= m);
    if !c130 {
        if l.v.speed <= vmin {
            *pitch_t = l.c.fpm_pitch_low;
        } else if l.v.speed >= vmin + 15.0 {
            *pitch_t = 0.0;
        }
    }
    if (l.v.att.pitch - *pitch_t).abs() <= 0.02 * PI && l.v.att.roll.abs() <= 0.01 * PI && spd_ok {
        return Leaf::Done;
    }
    let mut x = l.roll(0.0);
    let mut y = l.pitch(*pitch_t);
    let mut thr = l.thr(speed);
    if l.watch_ground(&mut x, &mut y, &mut thr) {
        *pitch_t = 0.0;
    }
    l.stick(y, x);
    l.throttle(thr);
    Leaf::Run
}

/// LevelWingsPitch0 `5d2140`: done within `pitch_tol` (ctor default 0.01π; LevelFlightCL sets 0.0035 rad) and
/// |roll| ≤ 1°.
fn level_wings(l: &mut Laws, pitch_tol: f32) -> Leaf {
    if l.v.att.pitch.abs() <= pitch_tol && l.v.att.roll.abs() <= PI / 180.0 {
        return Leaf::Done;
    }
    let mut x = l.roll(0.0);
    let mut y = l.pitch(0.0);
    let mut thr = 0.0;
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
    Leaf::Run
}

/// KeepOrientation `5d9d30` (FirstRun `5da010` stores `keep` = flight-path pitch, heading and the speed): bank
/// = clamp(heading error, ±30°), pitch law to the stored pitch; throttle (speed law to the stored speed) only in
/// an AI mode, else only when the ground watch takes over. Ends only by its condition (none here).
fn keep_orientation(l: &mut Laws, keep: (f32, f32, f32)) {
    let (pitch, heading, speed) = keep;
    let e = wrap(heading - l.v.att.heading);
    let roll_t = (e / (PI / 6.0) * (PI / 6.0)).clamp(-PI / 6.0, PI / 6.0);
    let mut y = l.pitch(pitch);
    let mut x = l.roll(roll_t);
    let mut thr = if l.mode != 0 { l.thr(speed) } else { 0.0 };
    // UNCERTAIN: the player's throttle slot is never initialised before the watch (@5d9efd); taken as 0.
    if l.watch_ground(&mut x, &mut y, &mut thr) || l.mode != 0 {
        l.throttle(thr);
    }
    l.stick(y, x);
}

/// LevelWingsAccel `5d27e0` (formation recovery, 300 m/s): wings level, pitch −11°.
fn level_wings_dive(l: &mut Laws, speed: f32) -> Leaf {
    let spd_ok = l.v.speed > speed || (l.v.speed - speed).abs() <= 3.0;
    if l.v.att.roll.abs() <= 0.01 * PI && spd_ok {
        return Leaf::Done;
    }
    let mut x = l.roll(0.0);
    let mut y = l.pitch(-11f32.to_radians());
    let mut thr = l.thr(speed);
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
    l.throttle(thr);
    Leaf::Run
}

// --- composite loops ------------------------------------------------------------------------------

/// Fly2WayPt `5d6ad0`: children [LevelWingsPitch0Accel, ChangeHeading2Pt, ChangeAlt, KeepAttitude2Pt,
/// LevelWingsPitch0]; the ETA speed law; ends when its condition holds.
#[derive(Debug, Clone)]
struct Fly2Wp {
    t: Vec3,
    eta: f64,
    cap: Option<f32>,
    /// GoHome's condition: within this 2-D radius (else the PassWaypoint at +0x588).
    end_radius: Option<f64>,
    pass: Pass,
    pass_alt: Pass,
    child: usize,
    lw_pitch: f32,
    first: bool,
}

impl Fly2Wp {
    fn new(t: Vec3, eta: f64) -> Self {
        Fly2Wp {
            t,
            eta,
            cap: None,
            end_radius: None,
            pass: Pass::new(PASS_R),
            pass_alt: Pass::new(PASS_R),
            child: 0,
            lw_pitch: 0.0,
            first: true,
        }
    }

    /// Returns Done when the waypoint is reached (or the last child ended).
    fn step(&mut self, l: &mut Laws, vmin12: f32) -> Leaf {
        let pos = l.v.pos;
        if self.first {
            self.first = false;
            // 5d6fb0: in an AI mode (≠ 0; not the player's autopilot) a larger capture radius when starting
            // inside it.
            let g = l.v.max_g;
            let r = if g <= 4.0 {
                9265.0
            } else if g < 6.5 {
                6485.5
            } else {
                3983.95
            };
            self.pass.r = if l.mode != 0 && dist2(pos, self.t[0], self.t[1]) < r { r } else { PASS_R };
        }
        // Ours, GoHome on the 6-DoF ([`Laws::real`]): the waypoint is passed within 1.5 turns' radius at KeepAttitude's
        // 45° bank. A jet sent home abeam of it and near circled it there for good (a MiG-29A round Nevatim's last
        // waypoint, 4 km off at 197 m/s, until its fuel ran out); the landing's pattern starts from where it is.
        if self.end_radius.is_some() && l.real.is_some() {
            self.pass.r = self.pass.r.max(1.5 * (l.v.speed as f64).powi(2) / 9.81);
        }
        let done = match self.end_radius {
            Some(r) => dist2(pos, self.t[0], self.t[1]) < r,
            None => self.pass.test(pos, self.t[0], self.t[1]),
        };
        if done {
            return Leaf::Done;
        }
        let d =
            ((self.t[0] - pos[0]).powi(2) + (self.t[1] - pos[1]).powi(2) + (self.t[2] - pos[2]).powi(2)).sqrt() as f32;
        let dt = ((self.eta - l.v.t) * 1000.0).trunc() * 0.001;
        let c130 = l.v.type_code == C130;
        let mut v = if dt > 0.0 {
            let v = d / dt as f32;
            if c130 { v.clamp(60.0, 215.0) } else { v.clamp(V_MIN_NAV, V_MAX_NAV) }
        } else if c130 {
            215.0
        } else {
            V_NO_ETA
        };
        if let Some(cap) = self.cap
            && d < 6000.0
            && v >= cap
        {
            v = cap;
        }
        let thr = l.thr(v);
        l.throttle(thr);
        // The current child.
        let lw_speed = match l.v.type_code {
            C130 => 90.0,
            220 => 135.0,
            _ => 180.0,
        };
        let r = match self.child {
            0 => level_wings_accel(l, &mut self.lw_pitch, lw_speed, vmin12),
            1 => change_heading(l, [self.t[0], self.t[1]], 0.02 * PI, 80f32.to_radians(), None),
            2 => {
                if self.pass_alt.test(pos, self.t[0], self.t[1]) || (pos[2] - self.t[2]).abs() < 250.0 {
                    Leaf::Done
                } else {
                    change_alt(l, self.t[2]);
                    Leaf::Run
                }
            }
            3 => {
                if self.pass.test(pos, self.t[0], self.t[1]) {
                    Leaf::Done
                } else {
                    keep_attitude(l, self.t, None);
                    Leaf::Run
                }
            }
            _ => level_wings(l, 0.01 * PI),
        };
        if r == Leaf::Done {
            l.stick(0.0, 0.0); // 5c99e0
            self.child += 1;
            if self.child > 4 {
                return Leaf::Done;
            }
        }
        Leaf::Run
    }
}

/// The taxi loop `TaxiCL` (docs/ai.md §8.2): departure (hangar → lineup) or to park (runway → hangar).
#[derive(Debug, Clone)]
struct Taxi {
    park: bool,
    path: Vec<TaxiPt>,
    i: usize,
    turning: bool,
    waiting: bool,
    start: f64,
    at_lineup: bool,
    first: bool,
    hangar: Option<(usize, usize)>,
    /// The 6-DoF's taxi lever summed ([`Laws::taxi_thr`]).
    thr_i: f32,
}

/// Loop states per mode.
#[derive(Debug, Clone)]
enum Loop {
    None,
    Nav {
        f: Option<Fly2Wp>,
        idx: usize,
    },
    GoHome {
        f: Fly2Wp,
        /// Boxed: the landing's pattern is large next to the other states.
        land: Option<Box<Landing>>,
    },
    TakeOff {
        stage: u8,
        taxi: Taxi,
        ka_target: Vec3,
        ka_speed: f32,
        ka_radius: Option<f64>,
    },
    Formation {
        recover: bool,
        lateral: f32,
        longitudinal: f32,
    },
    Hold {
        t: Vec3,
    },
    Straight {
        pitch: f32,
    },
    /// The player's LevelFlightCL (manager +0x4528, Init `5cd8c0`): LevelWingsPitch0 (pitch within 0.0035 rad),
    /// then KeepOrientation on what it holds then.
    Level {
        keep: Option<(f32, f32, f32)>,
    },
    /// The player's NAV to one waypoint: the manager's Fly2WayPt (+0x4f8) set up by `5c7bc0`; done = stick
    /// centred (the HUD's waypoint sequencing posts the next one).
    Fly {
        f: Option<Fly2Wp>,
    },
    /// Dogchase (mode 0x11, manager +0x1de8, Run `5cea30`): chase the target (`Autopilot::target`).
    Dogchase,
    /// Shandel (0xd, kind 0x17) / SplitS (0xf, kind 0x16) / Horizontal (0x10, kind 0x18): Run `5d1100`.
    Pursuit {
        kind: u8,
        speed: f32,
    },
    /// Himmelman (0xe, Run `5ce8c0`): ChangeAlt, Fly2ImpactPt, Dogchase.
    Himmelman {
        child: u8,
        pt_z: f64,
    },
    /// TailClear (0x14, Run `5dac30`).
    TailClear {
        state: u8,
        a: f64,
    },
    /// DiveBomb (0x17, Run `5d8590`).
    DiveBomb(Box<DiveBomb>),
    /// LevelBomb (0x16, Run `5d9290`): to above the target, release, then LevelWingsPitch0Accel.
    LevelBomb {
        released: bool,
        z: f64,
        lw_pitch: f32,
    },
    /// RunAway (0x12, Init `5dd330`, Run `5dd4a0`).
    RunAway {
        state: u8,
        t30: f64,
        t60: f64,
        pt: Vec3,
        speed: f32,
        thr: f32,
    },
    /// Break90 (0x13, Init `5da210`, Run `5da7a0`); set up on its first tick.
    Break90(Option<Box<Break90>>),
    /// PopupRelease (0x18, Init `5ccbd0`, Run `5cc0f0`); set up on its first tick.
    Popup(Option<Box<Popup>>),
    /// Ours, the slot ([`MODE_SLOT`]): the throttle's summed speed error (the lever it holds at no error); the
    /// leader's time, position and velocity at the last tick (its acceleration).
    Slot {
        thr_i: f32,
        prev: Option<(f64, Vec3, Vec3, f32)>,
    },
    /// Ours, the steer loop ([`MODE_STEER`]).
    Steer,
    /// Ours, the BFM loop ([`MODE_BFM`]): the time and the line to its point at the last tick (the line's swing).
    Bfm(Option<(f64, Vec3)>),
}

/// Break90's state (`5da7a0`): the break point B, the entry-heading point A, the KeepOrientation capture.
#[derive(Debug, Clone)]
struct Break90 {
    state: u8,
    a: Vec3,
    b: Vec3,
    keep: Option<(f32, f32, f32)>,
    lw_pitch: f32,
}

/// PopupRelease's children (`5ccbd0`): Fly2WayPt to Q, PullG to 45°, KeepOrientation to T.z + 1828.8, Fly2PtXYZ to U,
/// KeepAttitude2Pt on U with the release, ChangeAlt T.z + 1000 (no condition: never ends).
#[derive(Debug, Clone)]
struct Popup {
    child: u8,
    t: Vec3,
    u: Vec3,
    f2w: Fly2Wp,
    keep: Option<(f32, f32, f32)>,
}

/// DiveBomb's state (`5d8590`): the state code, the two Fly2TargetXyzSt points with their speed / throttle / case.
#[derive(Debug, Clone)]
struct DiveBomb {
    state: u8,
    a: Option<(Vec3, f32)>,
    b: (Vec3, f32, f32, u8),
    lw_pitch: f32,
}

/// Dogchase Run `5cea30` (docs/ai.md §13.3), every 0.5 s: the aim point is the target within 1000 m, else
/// DistanceBehindTarget behind it along its nose; LookAt case 1 on it (the target's roll); speed: beyond 1000 m
/// |V_T| + 0.027762795·dist, a target closing on me (V_T·(T − P) ≤ 0) 0, else (|V_T| + a·dist + b)·cos(V_T, V) with
/// a = −51.472221 / (D − 1854), b = −D·a; watch-ground. Returns the nose-on flag.
fn dogchase(l: &mut Laws, t: &Leader) -> bool {
    let v = l.v;
    let d = t.pos - v.pos;
    let dist = d.length() as f32;
    let behind = l.c.distance_behind_target as f64;
    let aim = if dist < 1000.0 {
        t.pos
    } else {
        let (sp, cp) = t.att[0].sin_cos();
        let (sh, ch) = t.att[2].sin_cos();
        let f = Vec3::new((sh * cp) as f64, (ch * cp) as f64, sp as f64);
        t.pos - f * behind
    };
    let (mut y, mut x) = l.look_at(aim, t.att[1], 1).unwrap_or((0.0, 0.0));
    let (f, _, _) = v.att.basis();
    let a = aim - v.pos;
    let an = a.length();
    let nose_on = an > 0.0 && ((f.dot(a) / an).clamp(-1.0, 1.0).acos() as f32) < l.c.nose_on_target;
    let dot32 = |p: Vec3, q: Vec3| p.dot(q) as f32;
    let tv = dot32(t.vel, t.vel).sqrt();
    let vt = if dist > 1000.0 {
        tv + 0.027_762_795 * dist
    } else if dot32(t.vel, d) <= 0.0 {
        0.0
    } else {
        let k = -51.472_22 / (behind as f32 - 1854.0);
        let b = -(behind as f32) * k;
        let my = dot32(v.vel, v.vel).sqrt();
        if my > 0.0 && tv > 0.0 { (tv + k * dist + b) * dot32(t.vel, v.vel) / (my * tv) } else { 0.0 }
    };
    let mut thr = l.thr(vt.max(0.0));
    l.watch_ground(&mut x, &mut y, &mut thr);
    l.stick(y, x);
    l.throttle(thr);
    nose_on
}

// --- combat manoeuvres (docs/ai.md §13.3) ----------------------------------------------------------------

/// Fly2TargetXyzSt `5d9740` (vtable 0x612d10): LookAt (`case`) on the point with the target roll 0 (`5d9970`);
/// throttle: the speed law to `speed` when > 0, else `thr` when > 0, else 0.75; watch-ground unless case 4.
fn fly_to_point(l: &mut Laws, t: Vec3, case: u8, speed: f32, thr: f32) {
    let (mut y, mut x) = l.look_at(t, 0.0, case).unwrap_or((0.0, 0.0));
    let mut th = if speed > 0.0 {
        l.thr(speed)
    } else if thr > 0.0 {
        thr
    } else {
        0.75
    };
    if case != 4 {
        l.watch_ground(&mut x, &mut y, &mut th);
    }
    l.stick(y, x);
    l.throttle(th);
}

/// `5d18b0`: the point L ahead on the turn that joins the target's track (w the target's direction, m the part of
/// P − A across it): φ = θ + sqrt(θ² + 2(a − b)/a), θ = atan2(d·w, d·m), a = |V|, b = max(|V_T|, 1).
fn turn_point(p: Vec3, v: Vec3, a: Vec3, vt: Vec3, l: f64) -> Vec3 {
    let Some(w) = unit(vt) else { return a };
    let d = p - a;
    let Some(u) = unit(d) else { return a };
    let Some(n) = unit(u.cross(w)) else { return a };
    let Some(m) = unit(w.cross(n)) else { return a };
    let (dx, dy) = (d.dot(m), d.dot(w));
    let th = dy.atan2(dx);
    let (sa, sb) = (v.length(), vt.length().max(1.0));
    let mut phi = th + (th * th + 2.0 * (sa - sb) / sa.max(1e-9)).max(0.0).sqrt();
    if dx < 0.0 {
        phi = -phi;
    }
    p + (w * phi.cos() - m * phi.sin()) * l
}

/// Shandel / SplitS / Horizontal (Run `5d1100`): within R (SplitS 5562, others 7416 m) Dogchase; else
/// Fly2TargetXyzSt (case 1) to the turn point toward A: SplitS above the target (T.z + 3048, at least 3657.6);
/// Shandel / Horizontal 5191.2 m to the near side of the target's track, Shandel 1828.8 above (below when I am lower
/// and it is high above its terrain), Horizontal at its height. The speed 231.75 is set after the run (quirk: the
/// first tick flies at 0.75).
fn pursuit(l: &mut Laws, t: &Leader, kind: u8, speed: &mut f32) -> bool {
    let v = l.v;
    let d = t.pos - v.pos;
    let r = if kind == 0x16 { 5562.0 } else { 7416.0 };
    if d.length() < r {
        return dogchase(l, t);
    }
    let a = match kind {
        0x16 => Vec3::new(t.pos[0], t.pos[1], (t.pos[2] + 3048.0).max(3657.6)),
        _ => {
            let ht = (l.ground)(t.pos[0], t.pos[1]) as f64;
            let z = match kind {
                0x17 if v.pos[2] < t.pos[2] && t.pos[2] > ht + 1828.8 + 609.6 => (t.pos[2] - 1828.8).max(ht + 304.8),
                0x17 => (t.pos[2] + 1828.8).max(ht + 3048.0),
                _ => t.pos[2],
            };
            let f = unit(Vec3::new(t.vel[0], t.vel[1], 0.0)).unwrap_or(Vec3::new(1.0, 0.0, 0.0));
            let rt = Vec3::new(f[1], -f[0], 0.0);
            let (a1, a2) = (t.pos + rt * 5191.2, t.pos - rt * 5191.2);
            let near = if (a1 - v.pos).length() <= (a2 - v.pos).length() { a1 } else { a2 };
            Vec3::new(near[0], near[1], z)
        }
    };
    let q = turn_point(v.pos, v.vel, a, t.vel, 10000.0);
    fly_to_point(l, q, 1, *speed, 0.0);
    *speed = 231.75;
    false
}

/// `5cb850`: the heading to intercept the target (lead collision when possible, else pursuit of a lead point; quirk:
/// the lead scales V_T by |V| / d, 1/s not s) and the speed to fly: (horizontal distance, speed, heading).
fn intercept(p: Vec3, s: f64, t: Vec3, vt: Vec3) -> (f64, f32, f32) {
    let d = t - p;
    let dh = Vec3::new(d[0], d[1], 0.0);
    let dist = dh.length();
    if dist <= 0.0 {
        return (0.0, s as f32, 0.0);
    }
    let u = dh * (-1.0 / dist);
    let c = u.dot(vt);
    let w2 = vt.dot(vt) - c * c;
    let k = s * s - w2;
    let (dir, speed) = if k > 0.0 && (c > 0.0 || c.abs() <= k.sqrt()) {
        let b0 = d[1].atan2(d[0]);
        let mut g = (k.sqrt() / s.max(1e-9)).clamp(-1.0, 1.0).acos();
        if vt.cross(u)[2] < 0.0 {
            g = -g;
        }
        ([(b0 + g).cos(), (b0 + g).sin()], s)
    } else {
        let lp = t + vt * (s / dist);
        ([lp[0] - p[0], lp[1] - p[1]], 2.0 * s)
    };
    (dist, speed as f32, wrap((dir[0] as f32).atan2(dir[1] as f32)))
}

/// Himmelman (Run `5ce8c0`, children of `5c6be0`): ChangeAlt to the averaged terrain + 166.5 m (re-aimed when it
/// moves by more than 200 m) until within 250 m; Fly2ImpactPt, terrain following on the intercept heading, until the
/// target is within 3708 m or more than 35° above; then Dogchase.
fn himmelman(l: &mut Laws, t: &Leader, child: &mut u8, pt_z: &mut f64, origin: [f64; 2]) -> bool {
    let v = l.v;
    let c = l.c;
    if pt_z.is_nan() {
        // Init 5ce5a0: the terrain at the world origin + 333 within 0..3000 (quirk: the origin, not the jet).
        *pt_z = ((l.ground)(-origin[0], -origin[1]) as f64 + 333.0).clamp(0.0, 3000.0);
    }
    if *child == 0 {
        let dt = c.watch_ground_dt as f64;
        let p1 = v.pos + v.vel * dt;
        let z = (((l.ground)(v.pos[0], v.pos[1]) as f64 + 333.0 + (l.ground)(p1[0], p1[1]) as f64) * 0.5)
            .clamp(-100.0, 3200.0);
        if (*pt_z - z).abs() > 200.0 {
            *pt_z = z;
        }
        if (v.pos[2] - *pt_z).abs() < 250.0 {
            *child = 1;
        } else {
            change_alt(l, *pt_z);
            return false;
        }
    }
    if *child == 1 {
        let d = t.pos - v.pos;
        let hd = d[0].hypot(d[1]);
        if d.length() <= 3708.0 || (d[2].atan2(hd) as f32) > 35f32.to_radians() {
            *child = 2;
        } else {
            fly_to_impact(l, t);
            return false;
        }
    }
    dogchase(l, t)
}

/// Fly2ImpactPt `5d7ad0`: the intercept heading by the change-heading bank (±80°), full throttle within 22248 m else
/// the speed law; pitch to clear the terrain 333 m above the point WatchGroundDeltaTime ahead (quirk: + V.z/15 on every
/// axis), else wings level and 15° up; no descent while banked beyond 20°.
fn fly_to_impact(l: &mut Laws, t: &Leader) {
    let v = l.v;
    let c = l.c;
    let (d, vt, hdg) = intercept(v.pos, v.speed as f64, t.pos, t.vel);
    let thr = if d < 22248.0 { 1.0 } else { l.thr(vt) };
    let lim = 80f32.to_radians();
    let e = wrap(hdg - v.att.heading);
    let bank = (e / (PI / 6.0) * c.change_head_k * lim - v.rates[2] * c.change_head_beta).clamp(-lim, lim);
    let mut xs = l.roll(bank);
    let k = v.vel[2] / 15.0;
    let a = v.pos + v.vel * c.watch_ground_dt as f64 + Vec3::new(k, k, k);
    let ha = (l.ground)(a[0], a[1]) as f64 + 333.0;
    let mut pitch_t = if l.los(v.pos, Vec3::new(a[0], a[1], ha)) {
        ((ha - v.pos[2]) as f32).atan2((a[0] - v.pos[0]).hypot(a[1] - v.pos[1]) as f32)
    } else {
        xs = l.roll(0.0);
        15f32.to_radians()
    };
    if bank.abs() > 20f32.to_radians() && pitch_t < 0.0 {
        pitch_t = 0.0;
    }
    let y = l.pitch(pitch_t);
    l.stick(y, xs);
    l.throttle(thr);
}

/// TailClear (Run `5dac30`): while the target is ahead (and every other tick: quirk, the state flips) Dogchase; else
/// Fly2TargetXyzSt to 200 m ahead and 600 m along D × F (float noise picks the sign: +600 as coded, the target brain
/// fields of the −600 case UNCERTAIN), at least terrain + A (A already holds terrain: quirk), 103 m/s when at or above
/// it + 182.88, else 309 m/s.
fn tail_clear(l: &mut Laws, t: &Leader, state: &mut u8, a: f64) -> bool {
    let v = l.v;
    let Some(f) = unit(v.vel) else {
        l.stick(0.0, 0.0);
        return false;
    };
    let d = t.pos - v.pos;
    *state = if d.dot(f) > 0.0 && *state != 0x19 { 0x19 } else { 0x1f };
    if *state == 0x19 {
        return dogchase(l, t);
    }
    let r = unit(d.cross(f)).unwrap_or(Vec3::UP);
    let h = v.ground_height as f64;
    let speed = if h + a <= v.pos[2] + 182.88 { 103.0 } else { 309.0 };
    let mut q = v.pos + f * 200.0 + r * 600.0;
    q[2] = q[2].max(h + a);
    fly_to_point(l, q, 1, speed, 0.0);
    false
}

/// PullGFullThrottle `5da080` (vtable 0x612d78): the stick for 7 g (`5ca310`), wings level, full throttle (no
/// afterburner in the AI modes); no ground watch; it ends by its parent's condition.
fn pull_g(l: &mut Laws) {
    let y = l.inv_g(7.0).clamp(-1.0, 1.0);
    let x = l.roll(0.0);
    l.stick(y, x);
    l.throttle(1.0);
}

/// Fly2PtXYZ `5d9580` (vtable 0x612e88): LookAt case 0 on the point; the throttle only when the ground watch acts.
fn fly_to_xyz(l: &mut Laws, p: Vec3) {
    let (mut y, mut x) = l.look_at(p, 0.0, 0).unwrap_or((0.0, 0.0));
    let mut thr = 0.0;
    if l.watch_ground(&mut x, &mut y, &mut thr) {
        l.throttle(thr);
    }
    l.stick(y, x);
}

/// The nose (pitch included) of an attitude (pitch, roll, heading).
fn nose(att: [f32; 3]) -> Vec3 {
    let (sp, cp) = (att[0] as f64).sin_cos();
    let (sh, ch) = (att[2] as f64).sin_cos();
    Vec3::new(sh * cp, ch * cp, sp)
}

/// `5cc1f0`: the angle between a nose (pitch included) and the horizontal direction from `p` to `pt`.
fn angle_to(att: [f32; 3], p: Vec3, pt: Vec3) -> f32 {
    let h = Vec3::new(pt[0] - p[0], pt[1] - p[1], 0.0);
    match h.try_normalize() {
        Some(h) => (nose(att).dot(h).clamp(-1.0, 1.0)).acos() as f32,
        None => 0.0,
    }
}

/// RunAway (Run `5dd4a0`, every 0.5 s, never ends): beyond 18540 m (horizontal) run 1854 km straight away (state 1);
/// beyond 9270 m, after 60 s or with the target's nose more than 60° off me, fly to −1854000·F_T, an ABSOLUTE point
/// (state 2, quirk); else attack the target + 30 m on each axis at throttle 1.0 (state 3). The states flip every tick
/// at the borders (quirk, as coded). The throttle, posted last, overrides everything: 1.0 for 30 s, then 0.75.
fn run_away(
    l: &mut Laws,
    t: &Leader,
    state: &mut u8,
    times: (f64, f64),
    pt: &mut Vec3,
    speed: &mut f32,
    thr: &mut f32,
) {
    let v = l.v;
    let d = t.pos - v.pos;
    let n = d.try_normalize().unwrap_or(Vec3::ZERO);
    let h = d[0].hypot(d[1]);
    if h > 18540.0 && *state != 1 {
        *state = 1;
        *pt = v.pos - Vec3::new(n[0], n[1], 0.0) * 1.854e6;
        pt[2] = (t.pos[2] + 914.4).max(v.pos[2]);
    } else {
        let ang = angle_to(t.att, t.pos, v.pos);
        if h > 9270.0 || v.t > times.1 || (ang > 60f32.to_radians() && *state != 2) {
            *state = 2;
            *pt = nose(t.att) * -1.854e6;
            pt[2] = (pt[2] + 914.4).max(v.pos[2]);
        } else if *state != 3 {
            *state = 3;
        }
    }
    match *state {
        1 => {
            (*speed, *thr) = (800.0, 0.0);
            fly_to_point(l, *pt, 1, *speed, *thr);
        }
        2 => fly_to_point(l, *pt, 1, *speed, *thr),
        _ => {
            (*speed, *thr) = (0.0, 1.0);
            fly_to_point(l, t.pos + Vec3::new(30.0, 30.0, 30.0), 1, *speed, *thr);
        }
    }
    l.throttle(if v.t < times.0 { 1.0 } else { 0.75 });
}

impl Break90 {
    /// Init `5da210`: A 1854 km ahead along my horizontal nose; B 185.4 km to the target's side of its track (sgn from
    /// a local→world transform applied to a world vector: original bug, kept), both at my height.
    fn new(v: &ApView, t: &Leader) -> Self {
        let p = v.pos;
        let f = nose([v.att.pitch, v.att.roll, v.att.heading]);
        let fh = Vec3::new(f[0], f[1], 0.0).try_normalize().unwrap_or(Vec3::new(0.0, 1.0, 0.0));
        let mut a = p + fh * 1.854e6;
        a[2] = p[2];
        let e = crate::aircraft::Euler { pitch: t.att[0], roll: t.att[1], heading: t.att[2] };
        let (ft, rt, _) = e.basis();
        let sgn = if fh[0] * rt[0] + fh[1] * ft[0] > 0.0 { 1.0 } else { -1.0 };
        let mut b = p + Vec3::new(-ft[1], ft[0], 0.0) * (185400.0 * sgn);
        b[2] = p[2];
        Break90 { state: 0xf, a, b, keep: None, lw_pitch: 0.0 }
    }

    /// Run `5da7a0`: turn to B (within 10°, pitch included), wings level, pull 7 g at full throttle to 45° pitch, keep
    /// the orientation until above 1066.8 m (the base +0x5b0 is never written: absolute, quirk), turn to A, then
    /// LevelWingsPitch0Accel 180 m/s forever.
    fn step(&mut self, l: &mut Laws, vmin12: f32) {
        let v = l.v;
        let att = [v.att.pitch, v.att.roll, v.att.heading];
        let ten = 10f32.to_radians();
        match self.state {
            0xf => {
                if angle_to(att, v.pos, self.b) < ten {
                    self.state = 0x10;
                } else {
                    fly_to_point(l, self.b, 1, 0.0, 0.0);
                }
            }
            0x10 => {
                if level_wings_accel(l, &mut self.lw_pitch, 180.0, vmin12) == Leaf::Done {
                    l.stick(0.0, 0.0);
                }
                if v.att.roll.abs() < ten {
                    self.state = 0x11;
                }
            }
            0x11 => {
                if v.att.pitch > PI / 4.0 {
                    self.state = 0x12;
                } else {
                    pull_g(l);
                }
            }
            0x12 => {
                if v.pos[2] > 1066.8 {
                    self.state = 0x14;
                } else {
                    let k = *self.keep.get_or_insert((v.att.pitch, v.att.heading, v.speed));
                    keep_orientation(l, k);
                }
            }
            0x14 => {
                if angle_to(att, v.pos, self.a) < ten {
                    self.state = 0x15;
                } else {
                    fly_to_point(l, self.a, 1, 0.0, 0.0);
                }
            }
            _ => {
                let _ = level_wings_accel(l, &mut self.lw_pitch, 180.0, vmin12);
            }
        }
    }
}

impl Popup {
    /// Init `5ccbd0` with the target's pose: Q = 3708 m right of the line to T and 4635 m short of it, 300 m above
    /// the terrain; U = T + 500 up; Fly2WayPt to Q with the ETA dist / 308.4 taken as an absolute time (quirk).
    fn new(l: &mut Laws, t: &Leader) -> Self {
        let p = l.v.pos;
        let d = t.pos - p;
        let b = if d[0] == 0.0 && d[1] == 0.0 { 0.0 } else { d[0].atan2(d[1]) };
        let dist = d.length();
        let fb = Vec3::new(b.sin(), b.cos(), 0.0);
        let rb = Vec3::new(b.cos(), -b.sin(), 0.0);
        let mut q = p + rb * 3708.0 + fb * (dist - 4635.0);
        q[2] = (l.ground)(q[0], q[1]) as f64 + 300.0;
        let u = Vec3::new(t.pos[0], t.pos[1], t.pos[2] + 500.0);
        Popup { child: 0, t: t.pos, u, f2w: Fly2Wp::new(q, dist * 0.003_242_54), keep: None }
    }

    /// Base Run `5cc0f0` over the children, each ending by its condition and the next starting on the next tick.
    /// The release (`440440`, l.out.release) when the vacuum impact is within 600 m of U (3-D: U is 500 m up, so only
    /// within ~332 m horizontally of T, quirk) or I am within 1000 m of U. Returns the root period when it changes.
    fn step(&mut self, l: &mut Laws, prev: &mut f32) -> Option<f64> {
        let v = l.v;
        match self.child {
            0 => {
                if self.f2w.step(l, 0.0) == Leaf::Done {
                    l.stick(0.0, 0.0);
                    self.child = 1;
                }
            }
            1 => {
                // 5da190: done once |pitch − 45°| starts growing (prev ≥ 0); prev is never reset (quirk).
                let cur = (v.att.pitch - PI / 4.0).abs();
                let done = *prev >= 0.0 && cur > *prev;
                *prev = cur;
                if done {
                    l.stick(0.0, 0.0);
                    self.child = 2;
                } else {
                    pull_g(l);
                }
            }
            2 => {
                if v.pos[2] > self.t[2] + 1828.8 {
                    l.stick(0.0, 0.0);
                    self.child = 3;
                } else {
                    let k = *self.keep.get_or_insert((v.att.pitch, v.att.heading, v.speed));
                    keep_orientation(l, k);
                }
            }
            3 => {
                let f = nose([v.att.pitch, v.att.roll, v.att.heading]);
                if (self.u - v.pos).try_normalize().is_some_and(|d| f.dot(d) >= 0.966) {
                    l.stick(0.0, 0.0);
                    self.child = 4;
                } else {
                    fly_to_xyz(l, self.u);
                }
            }
            4 => {
                let i = vacuum_impact(v.pos, v.vel, self.t[2]);
                let r1 = (i - self.u).length() <= 600.0;
                let r2 = (self.u - v.pos).length() < 1000.0;
                if r1 || r2 {
                    l.out.release = true;
                    l.stick(0.0, 0.0);
                    self.child = 5;
                } else {
                    keep_attitude(l, self.u, None);
                }
            }
            _ => change_alt(l, self.t[2] + 1000.0),
        }
        l.period
    }
}

/// The vacuum impact of a store released now (`45ed10`, UNCERTAIN: its integration; here the drop to the target's
/// height under gravity alone).
fn vacuum_impact(p: Vec3, v: Vec3, z: f64) -> Vec3 {
    let h = p[2] - z;
    let vz = v[2];
    let t = (vz + (vz * vz + 2.0 * 9.80665 * h.max(0.0)).sqrt()) / 9.80665;
    Vec3::new(p[0] + v[0] * t, p[1] + v[1] * t, z)
}

/// LevelBomb (Run `5d9290`): Fly2TargetXyzSt at 257.5 m/s to (T.x, T.y, max(z, T.z + 609.6)); the release when the
/// vacuum impact is within 2·(z − T.z) of the target; then LevelWingsPitch0Accel 180 m/s.
fn level_bomb(l: &mut Laws, t: &Leader, released: &mut bool, z: f64, lw: &mut f32, vmin12: f32) {
    let v = l.v;
    if *released {
        let _ = level_wings_accel(l, lw, 180.0, vmin12);
        return;
    }
    let zz = z.max(t.pos[2] + 609.6);
    fly_to_point(l, Vec3::new(t.pos[0], t.pos[1], zz), 1, 257.5, 0.0);
    let i = vacuum_impact(v.pos, v.vel, t.pos[2]);
    if (i[0] - t.pos[0]).hypot(i[1] - t.pos[1]) <= 2.0 * (v.pos[2] - t.pos[2]).max(0.0) {
        l.out.release = true;
        *released = true;
    }
}

impl DiveBomb {
    /// Run `5d8590`: approach high (5), dive at the point 800 m short of the target (7), on the target once the
    /// vacuum impact misses by less than 1000 m (9), release with the miss under 400 m (600 for types 210 / 220) and
    /// the wings within 15° (0xb), zoom climb 13716 m on (0xd), re-attack. Returns the root period when it changes.
    fn step(&mut self, l: &mut Laws, t: &Leader, vmin12: f32) -> Option<f64> {
        let v = l.v;
        let d = t.pos - v.pos;
        let d3 = d.length().max(1e-9);
        let dir = [d[0] / d3, d[1] / d3]; // quirk: divided by the 3-D distance
        let dh = d[0].hypot(d[1]);
        let ht = v.pos[2] - t.pos[2];
        let s = self.state;
        let mut period = None;
        let in_win = s != 0xb && dh > 300.0 && dh < 3657.6 && ht < 3048.0;
        if in_win {
            let i = vacuum_impact(v.pos, v.vel, t.pos[2]);
            let miss = (i[0] - t.pos[0]).hypot(i[1] - t.pos[1]);
            let rr = if v.type_code == 210 || v.type_code == 220 { 600.0 } else { 400.0 };
            if miss < rr && v.att.roll.abs() < 15f32.to_radians() && s == 9 {
                l.out.release = true;
                self.state = 0xb;
            } else if miss < 1000.0 && ![9, 0xd, 5].contains(&s) {
                self.state = 8;
            }
        } else if dh > 4572.0 && ![0xb, 0xd, 5].contains(&s) {
            self.state = 4;
        } else if s != 0xb && dh > 300.0 && dh < 3657.6 && ![0xd, 9, 7].contains(&s) {
            self.state = 6;
        } else if (s == 0xb || ht < 3048.0 || dh < 1524.0) && ![0xd, 5, 7].contains(&s) {
            self.state = 0xc;
        } else if ![5, 9, 7].contains(&s) {
            self.state = if dh > 2.0 * 5486.4 || s == 0xb { 0xe } else { 0 };
        }
        match self.state {
            4 => {
                let a = Vec3::new(t.pos[0] - 1524.0 * dir[0], t.pos[1] - 1524.0 * dir[1], t.pos[2] + 4572.0);
                self.a = Some((a, 360.5));
                self.state = 5;
                fly_to_point(l, a, 1, 360.5, 0.0);
            }
            5 => {
                if let Some((a, sp)) = self.a {
                    fly_to_point(l, a, 1, sp, 0.0);
                }
            }
            6 => {
                self.b = (Vec3::new(t.pos[0] - 800.0 * dir[0], t.pos[1] - 800.0 * dir[1], t.pos[2]), 206.0, 0.0, 4);
                period = Some(0.125);
                self.state = 7;
                fly_to_point(l, self.b.0, self.b.3, self.b.1, self.b.2);
            }
            8 => {
                self.b = (t.pos, 206.0, 0.0, 4);
                period = Some(0.125);
                self.state = 9;
                fly_to_point(l, self.b.0, self.b.3, self.b.1, self.b.2);
            }
            7 | 9 | 0xd => fly_to_point(l, self.b.0, self.b.3, self.b.1, self.b.2),
            0xc => {
                let hd = unit(Vec3::new(d[0], d[1], 0.0)).unwrap_or(Vec3::NORTH);
                let z = v.pos[2].max(t.pos[2] + 9144.0);
                self.b = (Vec3::new(v.pos[0] + 13716.0 * hd[0], v.pos[1] + 13716.0 * hd[1], z), 0.0, 1.0, 4);
                period = Some(0.5);
                self.state = 0xd;
                fly_to_point(l, self.b.0, self.b.3, self.b.1, self.b.2);
            }
            0xe => {
                let _ = level_wings_accel(l, &mut self.lw_pitch, 180.0, vmin12);
                l.throttle(0.75);
            }
            _ => {} // 0, 0xb: nothing this tick
        }
        period
    }
}

/// LandingCL (docs/ai.md §8.3): the pattern points and the step list.
#[derive(Debug, Clone)]
struct Landing {
    step: usize,
    pts: [Vec3; 5],
    rn: f32,
    k: f64,
    lw_pitch: f32,
    taxi: Option<Taxi>,
    park: Option<(f64, f64, f32, f64)>,
    /// StopPlane passed (the landed handler, controller +0xe0).
    landed: bool,
    /// The current ChangeHeading2PtAcu leg's state.
    acu: Option<Acu>,
    /// Flown by the player's autopilot (FM mode 0): no taxi / park children (`5d43e0`), StopPlane ends at
    /// 1.0295 m/s instead of 25.736 (`5d36d2`), no landed handler, then the autopilot key.
    player: bool,
    /// `Autopilot::align_final`.
    align: bool,
    /// `Autopilot::player_flare`.
    flare: bool,
    /// The player's flare: the vertical acceleration (m/s²) summed from the sink's error ([`Landing::flare`]).
    flare_i: f32,
    /// The real final's speed error summed, m/s ([`Landing::final_approach`]).
    final_i: f32,
    /// The 6-DoF circuit's speed error summed, m/s ([`REAL_CIRCUIT`]; 0.2 /s at its 0.1 s tick).
    thr_i: f32,
    /// The player's flare: the wheels have touched (a bounce flares to [`FLARE_SINK`] only).
    touched: bool,
    /// Ours: an AI jet on Modern IAF's 6-DoF (its circuit seen, [`ApView::circuit`]) lands as the player's autopilot
    /// does there, with the flare ([`Landing::flares`]); the original's level float stalls the 6-DoF onto the runway.
    six: bool,
    /// ParkInHangar's lever summed on the 6-DoF ([`Laws::taxi_thr`]).
    park_thr: f32,
}

/// A LandingCL child (docs/ai.md §8.3).
#[derive(Debug, Clone, Copy)]
enum Leg {
    /// ChangeHeading2PtAcu to point i: heading tolerance, bank limit, fixed speed (else the entry speed).
    Ch(usize, f32, f32, Option<f32>),
    /// ChangeAlt to point i's altitude until |Δz| < r.
    Ca(usize, f64),
    /// ChangeAlt (C-130 CA1) until within r (2-D) or |Δz| < 250.
    CaOr(usize, f64),
    /// LevelWingsPitch0Accel at a speed.
    Lw(f32),
    /// KeepAttitude2PtAtSpeed to point i until within r (2-D).
    Ka(usize, f32, f64),
    Fa(f64),
    Stop,
    Taxi,
    Park,
}

/// ChangeHeading2PtAcu (vtable 0x6138a0, Run `5dbe70`, FirstRun `5dd1f0`).
#[derive(Debug, Clone, Copy)]
struct Acu {
    vt: f32,
    done_latch: bool,
    acu: bool,
}

impl Acu {
    fn new(entry_speed: f32, vt: Option<f32>) -> Self {
        Acu { vt: vt.unwrap_or(entry_speed), done_latch: false, acu: true }
    }

    fn step(&mut self, l: &mut Laws, p: Vec3, prev: Option<Vec3>, tol: f32, lim: f32, off: bool) -> Leaf {
        let v = l.v;
        let pos = v.pos;
        let (dx, dy) = (p[0] - pos[0], p[1] - pos[1]);
        let target = if dx == 0.0 && dy == 0.0 { 0.0 } else { wrap((dx as f32).atan2(dy as f32)) };
        let mut cos_a = 1.0f64;
        if let Some(q) = prev {
            let (lx, ly) = (p[0] - q[0], p[1] - q[1]);
            let (ln, dn) = (lx.hypot(ly), dx.hypot(dy));
            if ln > 0.0 && dn > 0.0 {
                cos_a = (lx * dx + ly * dy) / (ln * dn);
            }
        }
        let mut e = wrap(target - v.att.heading);
        if prev.is_some() {
            // Line capture (as coded, UNCERTAIN intent): e −= ±acos(cos α).
            let mut sg = if e.to_degrees() > 0.0 { -1.0 } else { 1.0 };
            if cos_a > 0.0 {
                sg = -sg;
            }
            let a = wrap((cos_a.clamp(-1.0, 1.0).acos() as f32) * sg);
            e = wrap(e - a);
        }
        // Done on two consecutive ticks (the roll test is signed, as the original).
        let roll_deg = v.att.roll.to_degrees();
        // Off the original (`off`, docs/autopilot.md §2.3): rolled out within 1°, and the leg also ends once the jet
        // has passed `p`. The F-4 on Real data with the Better physics switches holds 0.4° of right bank on CH2's
        // line (e within tol), so the original's 0.2° test let CH2 creep on to P2; CH3 then began 8 km late, crept up
        // the base with e ≈ 0.9° and passed P3, where the capture term flips e by ±2α each tick and |e| never comes
        // within tol: the leg never ended.
        let roll_max = if off { 1.0 } else { 0.2 };
        if off && cos_a < 0.0 || (e.abs() <= tol || roll_deg <= roll_max) && self.done_latch {
            l.period = Some(0.5);
            l.out.rudder = Some(0.0);
            let y = l.pitch(0.0);
            let x = l.roll(0.0);
            l.stick(y, x);
            l.throttle(0.1);
            return Leaf::Done;
        }
        self.done_latch = e.abs() <= tol && roll_deg <= roll_max;
        let c = l.c;
        let bank0 = (e / (PI / 6.0) * lim * c.change_head_k - v.rates[2] * c.change_head_beta).clamp(-lim, lim);
        let mut bank = bank0;
        if let (Some(q), true) = (prev, self.acu && e.abs() > 0.034_906_6) {
            // The "Acu" search: the bank whose turn circle is tangent to the line prev → p.
            let (mut conv, mut n, mut d_t) = (false, 0, f64::MAX);
            loop {
                if bank.abs() <= 0.017_453_3 || bank.abs() > lim {
                    break;
                }
                let r = (v.speed * v.speed / (bank.tan().abs() * 9.806)) as f64;
                let (m, cc) = if p[0] != q[0] {
                    let m = (p[1] - q[1]) / (p[0] - q[0]);
                    (m, p[1] - p[0] * m)
                } else {
                    (0.0, 0.0)
                };
                let h = v.att.heading as f64;
                let sb = bank.signum() as f64;
                let cx = pos[0] + sb * r * h.cos();
                let cy = pos[1] - sb * r * h.sin();
                let (dist_cl, t) = if q[1] == p[1] {
                    ((m * cx + cc - cy).abs(), (pos[0], m * pos[0] + cc))
                } else if q[0] == p[0] {
                    ((p[0] - cx).abs(), (p[0], pos[1]))
                } else if m == 0.0 {
                    (0.0, (0.0, 0.0))
                } else {
                    // Original bug: the perpendicular uses the slope −m, and the foot is truncated to integers.
                    let ix = ((cy + m * cx - cc) / (2.0 * m)).trunc();
                    let iy = (-m * ix + cy + m * cx).trunc();
                    let jx = ((pos[1] + m * pos[0] - cc) / (2.0 * m)).trunc();
                    let jy = (-m * jx + pos[1] + m * pos[0]).trunc();
                    ((ix - cx).hypot(iy - cy), (jx, jy))
                };
                n += 1;
                let gap = dist_cl - r;
                d_t = (t.0 - pos[0]).hypot(t.1 - pos[1]);
                if gap.abs() < 1.0 || n >= 100 {
                    conv = true;
                    if d_t < 2.0 {
                        bank = bank0;
                    }
                    break;
                }
                bank += (gap * 0.01 * 0.017_453_3) as f32;
            }
            if !conv || d_t < 2.0 {
                self.acu = false;
            }
        }
        let thr = l.thr(self.vt).min(0.7);
        l.throttle(thr);
        let y = l.pitch(0.0);
        let x = l.roll(bank);
        // Watch-ground is skipped in modes 0 and 8 (the landing).
        l.out.rudder = Some(0.0);
        l.stick(y, x);
        Leaf::Run
    }
}

/// Hangars taken at every base (TowersManager +0x4f4 flags), shared by all jets of the flight.
static OCCUPIED: std::sync::Mutex<Vec<(usize, usize)>> = std::sync::Mutex::new(Vec::new());

/// Frees every hangar (`54f920`, a new mission).
pub fn reset_hangars() {
    OCCUPIED.lock().unwrap().clear();
}

fn occupy(b: usize, h: usize, on: bool) {
    let mut o = OCCUPIED.lock().unwrap();
    o.retain(|x| *x != (b, h));
    if on {
        o.push((b, h));
    }
}

/// The autopilot of one jet.
#[derive(Debug, Clone)]
pub struct Autopilot {
    pub cfg: Config,
    pub route: Vec<Waypoint>,
    pub bases: Vec<Airbase>,
    /// World position of the frame's origin (X east, Y north): the host may shift `bases`, `route` and the jet
    /// by it. LandingCL rounds its points to f32 in world coordinates, as the original.
    pub origin: [f64; 2],
    /// Formation leader (None: I am the leader, or no formation).
    pub leader: Option<Leader>,
    /// The combat manoeuvres' target (brain +0x70 as Init2 hands it over), fed by the host every frame.
    pub target: Option<Leader>,
    /// Dogchase has the nose on its aim point (LookAt's flag, NoseOnTargetAng; condition 20 for the gun).
    pub nose_on: bool,
    /// PopupRelease's PullG condition `5da190` (+0xc40): the last |pitch − 45°|, −1 from the manager's ctor and never
    /// reset by Init (quirk: stale on a second popup).
    popup_prev: f32,
    /// Current waypoint index (brain +0x88).
    pub wp_index: usize,
    /// Landed once (brain / controller +0xe0).
    pub landed: bool,
    /// TakeoffCL finished above 100 m AGL: the AirborneReport is posted then (`5cdb5d`, docs/radio.md §4).
    pub airborne: bool,
    /// World scale Real (docs/world-scale.md §4.3): the final approach and the float before touchdown hold the
    /// runway's centreline (`Landing::align_bank`); false: the original's laws.
    pub align_final: bool,
    /// The player's landing flares onto the runway (`Landing::flare`, docs/autopilot.md §2.3); false: StopPlane's
    /// original level float. The host sets it when the player has left the original: World scale Real, Real flight
    /// data or a Better physics switch.
    pub player_flare: bool,
    /// The slot loop's slot ([`MODE_SLOT`]): (forward, right, up) m in the leader's horizontal frame ([`slot_point`]).
    pub slot: [f32; 3],
    /// Ours (Modern IAF's flights): the slot is a close-up step (the lead's "close up", iaf-ai `CLOSE_STEPS`): the slot
    /// loop rolls with the leader ([`SLOT_ROLL_LEAD_S`]) by its own roll law ([`SLOT_ROLL`]), its throttle quicker
    /// ([`SLOT_CLOSE_KP`]).
    pub close: bool,
    /// Ours (Modern IAF's flights): the hangar (base index in `bases`, hangar) the landing's taxi parks in when it is
    /// free; None: the original's first free hangar.
    pub home_hangar: Option<(usize, usize)>,
    /// Ours (Modern IAF's flights): a jet about to come too near; the unit direction (world, ENU) to pull away in.
    /// While set, any loop's stick in the air gives way to the pull ([`AVOID_A`]) every 0.1 s.
    pub avoid: Option<Vec3>,
    /// Ours (Modern IAF's flights): the steer loop's order ([`MODE_STEER`]).
    pub steer: Option<Steer>,
    /// Ours (Modern IAF's flights): stop on the brakes at idle on the ground, set every frame: the taxi to park and
    /// ParkInHangar behind a jet ahead on the way, TakeoffCL's roll held for a pair's wingman to line up beside.
    pub hold: bool,
    /// Ours (Modern IAF's flights, a pairs take-off): this jet lines up this far right of the lineup point (m; 0 the
    /// original's lineup) beside its element lead, and rolls when the lead starts its roll.
    pub lineup_offset: f32,
    /// Ours (Modern IAF's flights, a pairs take-off): this jet leads a pair; its roll is at military power.
    pub pair_lead: bool,
    /// Ours (Modern IAF's AI jets, set by `iaf_ai::apply`; docs/ai.md §20): the ground collision avoidance's floor, m
    /// above the terrain: in every loop but the take-off and the landing a predicted fly-up below it takes the stick
    /// ([`FLY_UP_G`]) over the loop and the original's watch-ground; with [`Autopilot::low`] in place of the
    /// watch-ground (its 200 m above the terrain would hold the jet up). None (the 1998 game, the player): the
    /// watch-ground alone.
    pub floor: Option<f32>,
    /// Ours (Modern IAF's AI jets, set by `iaf_ai::apply`): the jet flies low (its flight's low level): the ground
    /// collision avoidance ([`Autopilot::floor`]) in place of the watch-ground.
    pub low: bool,
    /// Ours (Modern IAF's AI jets, set by `iaf_ai::apply`): the steer loop flies this high above the terrain ahead
    /// ([`follow_height`]) in place of its point's height; None: the point's.
    pub follow: Option<f32>,
    /// Ours (Modern IAF's flights, set by `iaf_ai::apply`): going home, the speed it flies at most, m/s, until the turn
    /// to final (the throttle held under it, the speed brake out 15 m/s above it): its spacing behind the jet ahead
    /// in the circuit. None: the loops' own speeds.
    pub pace: Option<f32>,
    /// The fly-up flies; the next prediction's time.
    fly_up: bool,
    fly_up_next: f64,
    mode: u8,
    lp: Loop,
    next_tick: f64,
    period: f64,
    watch: bool,
}

impl Autopilot {
    pub fn new(cfg: Config) -> Self {
        Autopilot {
            cfg,
            route: Vec::new(),
            bases: Vec::new(),
            origin: [0.0; 2],
            leader: None,
            target: None,
            nose_on: false,
            popup_prev: -1.0,
            wp_index: 0,
            landed: false,
            airborne: false,
            align_final: false,
            player_flare: false,
            slot: [0.0; 3],
            close: false,
            home_hangar: None,
            avoid: None,
            steer: None,
            hold: false,
            lineup_offset: 0.0,
            pair_lead: false,
            floor: None,
            low: false,
            follow: None,
            pace: None,
            fly_up: false,
            fly_up_next: 0.0,
            mode: 0,
            lp: Loop::None,
            next_tick: 0.0,
            period: 0.5,
            watch: true,
        }
    }

    pub fn mode(&self) -> u8 {
        self.mode
    }

    /// Ours (Modern IAF's flights): going home, the way left to the lineup along its track, m: to the route's last
    /// waypoint, then the landing pattern's points in turn (2-D); None in any other loop or past the final.
    pub fn to_go(&self, pos: Vec3) -> Option<f64> {
        let Loop::GoHome { f, land } = &self.lp else { return None };
        let flat = |a: Vec3, b: Vec3| (a[0] - b[0]).hypot(a[1] - b[1]);
        let (pts, i, from) = match land {
            Some(l) => {
                let i = match l.legs(false, &self.cfg).get(l.step)? {
                    Leg::Ch(i, ..) | Leg::Ca(i, _) | Leg::CaOr(i, _) | Leg::Ka(i, ..) => *i,
                    Leg::Lw(_) => [0, 1].get(l.step / 4).copied()?,
                    Leg::Fa(_) => 4,
                    _ => return None,
                };
                (l.pts, i, pos)
            }
            None => {
                let l = Landing::new(&self.bases, self.origin, f.t, 0, false)?;
                return Some(
                    flat(pos, f.t) + flat(f.t, l.pts[0]) + (1..5).map(|j| flat(l.pts[j - 1], l.pts[j])).sum::<f64>(),
                );
            }
        };
        Some(flat(from, pts[i]) + (i + 1..5).map(|j| flat(pts[j - 1], pts[j])).sum::<f64>())
    }

    /// Ours (Modern IAF's flights): the take-off's stage (0 the taxi, 1 TakeoffCL on the runway, 2 and 3 in the air)
    /// or the landing pattern's step (LandingCL's children: 11 the turn to final, 13 the final, 14 StopPlane, 15 the
    /// taxi in, 16 ParkInHangar); None in any other loop.
    pub fn phase(&self) -> Option<usize> {
        match &self.lp {
            Loop::TakeOff { stage, .. } => Some(*stage as usize),
            Loop::GoHome { land: Some(l), .. } => Some(l.step),
            _ => None,
        }
    }

    /// The loop's stage, for logs and tests.
    pub fn stage(&self) -> String {
        match &self.lp {
            Loop::Nav { idx, .. } => format!("nav wp {}", idx),
            Loop::GoHome { land: None, .. } => "go home: fly to the last waypoint".into(),
            Loop::GoHome { land: Some(l), .. } => match l.taxi.as_ref().filter(|_| l.step == 15) {
                Some(t) => format!(
                    "landing step 15 taxi point {}/{}{}",
                    t.i,
                    t.path.len(),
                    ["", " turning"][t.turning as usize]
                ),
                None => format!("landing step {}", l.step),
            },
            Loop::TakeOff { stage, taxi, .. } => format!("take-off stage {stage} taxi point {}", taxi.i),
            Loop::Formation { recover, .. } => format!("formation{}", if *recover { " (recovering)" } else { "" }),
            Loop::Hold { .. } => "hold".into(),
            Loop::Straight { .. } => "straight".into(),
            Loop::Level { keep: None } => "level: wings level".into(),
            Loop::Level { .. } => "level: keep orientation".into(),
            Loop::Fly { f } => format!("nav{}", if f.is_none() { " (passed)" } else { "" }),
            Loop::Dogchase => format!("dogchase{}", if self.nose_on { " (nose on)" } else { "" }),
            Loop::Pursuit { kind, .. } => format!("pursuit kind {kind:#x}"),
            Loop::Himmelman { child, .. } => format!("himmelman child {child}"),
            Loop::TailClear { state, .. } => format!("tail clear {state:#x}"),
            Loop::LevelBomb { released, .. } => format!("level bomb{}", if *released { " (released)" } else { "" }),
            Loop::DiveBomb(d) => format!("dive bomb state {:#x}", d.state),
            Loop::RunAway { state, .. } => format!("run away state {state}"),
            Loop::Break90(b) => format!("break90 state {:#x}", b.as_ref().map_or(0, |b| b.state)),
            Loop::Popup(p) => format!("popup child {}", p.as_ref().map_or(0, |p| p.child)),
            Loop::Slot { .. } => "slot".into(),
            Loop::Steer => "steer".into(),
            Loop::Bfm(_) => "bfm".into(),
            Loop::None => "none".into(),
        }
    }

    /// `setMode` (`5a8410`): an identical command is ignored; else the loop starts (first tick after 0.5 s).
    pub fn set_mode(&mut self, ac: &mut impl Host, mode: u8) {
        if mode == self.mode {
            return;
        }
        let now = ac.ap_view().t;
        let old = self.mode;
        if self.mode == 0 && mode != 0 {
            ac.set_ai_since(now);
        }
        self.mode = mode;
        ac.set_ai_mode(mode);
        self.watch = true;
        self.period = 0.5;
        // Ours: the enemy fighter's moves switch between the steer and the BFM loop each decision (its level moves are
        // the steer loop's, §18.2); the 0.5 s hold of the old stick at up to 9 g is skipped between the two.
        let ours = |m: u8| m == MODE_STEER || m == MODE_BFM;
        let held = if ours(mode) && ours(old) { 0.0 } else { 0.5 };
        self.next_tick = now + held;
        let v = ac.ap_view();
        self.lp = match mode {
            7 => Loop::Nav { f: None, idx: self.wp_index },
            8 => self.go_home(&v, now),
            9 => {
                let (ka_target, ka_speed, ka_radius) = match self.route.first() {
                    Some(w) => (Vec3::new(w.x, w.y, w.z), 205.889, Some(500.0)),
                    None => (v.pos, 180.153, None),
                };
                Loop::TakeOff {
                    stage: if v.on_ground { 0 } else { 2 },
                    taxi: Taxi {
                        park: false,
                        path: Vec::new(),
                        i: 0,
                        turning: false,
                        waiting: false,
                        start: 0.0,
                        at_lineup: false,
                        first: true,
                        hangar: None,
                        thr_i: 0.0,
                    },
                    ka_target,
                    ka_speed,
                    ka_radius,
                }
            }
            1 | 3 => {
                Loop::Formation { recover: false, lateral: if mode == 1 { 100.0 } else { 200.0 }, longitudinal: -20.0 }
            }
            10 => {
                let g = v.ground_height;
                Loop::Hold { t: Vec3::new(v.pos[0], v.pos[1], v.pos[2].max(g as f64 + 300.0)) }
            }
            0xb => Loop::Straight { pitch: 0.0 },
            0x11 => Loop::Dogchase,
            0xd => Loop::Pursuit { kind: 0x17, speed: 0.0 },
            0xf => Loop::Pursuit { kind: 0x16, speed: 0.0 },
            0x10 => Loop::Pursuit { kind: 0x18, speed: 0.0 },
            // Init 5ce5a0 (on the first tick, with the terrain): see `himmelman`.
            0xe => Loop::Himmelman { child: 0, pt_z: f64::NAN },
            0x14 => Loop::TailClear { state: 0, a: v.pos[2].max(v.ground_height as f64 + 1219.2) },
            0x16 => Loop::LevelBomb { released: false, z: v.pos[2], lw_pitch: 0.0 },
            0x12 => Loop::RunAway { state: 0, t30: now + 30.0, t60: now + 60.0, pt: Vec3::ZERO, speed: 0.0, thr: 0.0 },
            0x13 => Loop::Break90(None),
            0x18 => Loop::Popup(None),
            0x17 => {
                Loop::DiveBomb(Box::new(DiveBomb { state: 0, a: None, b: (Vec3::ZERO, 0.0, 0.0, 4), lw_pitch: 0.0 }))
            }
            MODE_SLOT => Loop::Slot { thr_i: ac.controls().throttle, prev: None },
            MODE_STEER => Loop::Steer,
            MODE_BFM => Loop::Bfm(None),
            _ => Loop::None,
        };
        self.nose_on = false;
    }

    /// Ours, for the mission editor's "takes off" rule (docs/mission-editor.md §18.3; editor missions only): a
    /// take-off held by a late planned time at wp0 starts now. wp0's time becomes `now`, and a TaxiCL already waiting
    /// is timed as its FirstRun would time it then: the leader now, a wingman away from the lineup 10 s later.
    pub fn release_takeoff(&mut self, now: f64) {
        let Some(w) = self.route.first_mut().filter(|w| w.t > now) else { return };
        w.t = now;
        let lead = self.leader.is_none();
        if let Loop::TakeOff { taxi, .. } = &mut self.lp
            && taxi.waiting
            && !taxi.park
        {
            taxi.start = if lead || taxi.at_lineup { now } else { now + 10.0 };
        }
    }

    /// GoHomeCL Init `5cd390`: Fly2WayPt to the route's last waypoint (no route: here), then LandingCL.
    fn go_home(&self, v: &ApView, now: f64) -> Loop {
        let (t, cap) = match self.route.last() {
            Some(w) => (Vec3::new(w.x, w.y, w.z), if v.type_code == C130 { 128.68 } else { 180.15 }),
            None => (v.pos, 180.15),
        };
        let mut f = Fly2Wp::new(t, now + 60.0);
        f.cap = Some(cap);
        f.end_radius = Some(100.0);
        Loop::GoHome { f, land: None }
    }

    /// The player's autopilot, FM motion 0xf (`5a1e40`, docs/autopilot.md): 0 off (`5c8800`), 1 LevelFlightCL
    /// (`5c82c0`), 2 NAV to route waypoint `wp` (`5c7bc0`: Fly2WayPt with its ETA), or GoHomeCL (`5c7d80`) when
    /// that waypoint's action is 7 (land). The FM mode stays 0: the jet keeps the player's rules. The loop
    /// starts on the next ring tick (0.5 s, `5c9a90`).
    pub fn player_mode(&mut self, ac: &mut impl Host, mode: u8, wp: usize) {
        let v = ac.ap_view();
        self.lp = match (mode, self.route.get(wp)) {
            (1, _) => Loop::Level { keep: None },
            (2, Some(w)) if w.action == 7 => self.go_home(&v, v.t),
            (2, Some(w)) => Loop::Fly { f: Some(Fly2Wp::new(Vec3::new(w.x, w.y, w.z), w.t)) },
            // 5c7bc0 without a route starts the loop uninitialised (UNCERTAIN): nothing flies.
            _ => Loop::None,
        };
        ac.set_stores_trim(!matches!(self.lp, Loop::None));
        self.watch = true;
        self.period = 0.5;
        self.next_tick = v.t + 0.5;
    }

    /// The player's autopilot loop is running (FM motion 0xf mode ≠ 0).
    pub fn player_active(&self) -> bool {
        self.mode == 0 && !matches!(self.lp, Loop::None)
    }

    /// Runs the loop's ring tick when due, applies its outputs to the aircraft and returns them.
    pub fn step(&mut self, ac: &mut impl Host, ground: Ground) -> Out {
        // Better physics "Asymmetric stores" (ours): a running loop trims the stores' roll; its roll laws are
        // P-only and would otherwise hold a steady bank against it (docs/autopilot.md §2.5).
        ac.set_stores_trim(!matches!(self.lp, Loop::None));
        if matches!(self.lp, Loop::None) {
            return Out::default();
        }
        let v = ac.ap_view();
        if v.t < self.next_tick {
            return Out::default();
        }
        let vmin12 = ac.vmin(v.pos[2] as f32, 1.2);
        let vmin125 = ac.vmin(v.pos[2] as f32, 1.25);
        let vmin25 = ac.vmin(v.pos[2] as f32, 2.5);
        let vmin1 = ac.vmin(v.pos[2] as f32, 1.0);
        let cfg = self.cfg;
        // Ours: the AI jets' ground collision avoidance, but in the take-off and the landing; in place of the
        // watch-ground while the jet flies low (its 200 m would hold it up), else over it.
        let floor = self.floor.filter(|_| {
            self.watch && !v.on_ground && !matches!(self.lp, Loop::TakeOff { .. } | Loop::GoHome { land: Some(_), .. })
        });
        if floor.is_none() {
            self.fly_up = false;
        }
        let mut l = Laws {
            c: &cfg,
            v: &v,
            mode: self.mode,
            watch: self.watch && (floor.is_none() || !self.low),
            ground,
            out: Out::default(),
            period: None,
            // Ours: an AI jet on the 6-DoF flies its route, take-off, go-home, hold and slot loops on the circuit's path law
            // and bank limit (the landing sets its own): the original pitch law pushed it to −3.5 g rolling out of an
            // 80° bank (a structural failure). The player's autopilot (mode 0), the other modes (untested on the
            // 6-DoF) and the original model keep the original laws.
            real: v.circuit.filter(|_| matches!(self.mode, 7 | 8 | 9 | 10 | MODE_SLOT)),
            thr_i: 0.0,
            thr_last: Default::default(),
            thr_err: None,
        };
        let mut lp = std::mem::replace(&mut self.lp, Loop::None);
        let mut period = self.period;
        match &mut lp {
            Loop::Nav { f, idx } => {
                let mut advance = f.is_none();
                if let Some(ff) = f
                    && ff.step(&mut l, vmin12) == Leaf::Done
                {
                    l.stick(0.0, 0.0); // 5c99e0
                    advance = true;
                }
                if advance {
                    // WayPtSet next (5d7450): the next waypoint, or the stick centred past the last.
                    match self.route.get(*idx).copied() {
                        Some(w) => {
                            *f = Some(Fly2Wp::new(Vec3::new(w.x, w.y, w.z), w.t));
                            self.wp_index = *idx;
                            *idx += 1;
                        }
                        None => {
                            *f = None;
                            l.stick(0.0, 0.0);
                        }
                    }
                }
            }
            Loop::GoHome { f, land } => {
                if land.is_none() {
                    if f.step(&mut l, vmin12) == Leaf::Done {
                        l.stick(0.0, 0.0);
                        *land = Landing::new(&self.bases, self.origin, f.t, v.type_code, self.mode == 0)
                            .map(|ld| Box::new(Landing { align: self.align_final, flare: self.player_flare, ..ld }));
                    }
                } else if let Some(ld) = land {
                    ld.step(&mut l, self, &mut period, vmin1, vmin12);
                }
                // Ours (Modern IAF's flights): the spacing's pace, until the turn to final.
                if let Some(p) = self.pace.filter(|_| land.as_ref().is_none_or(|ld| ld.step < 11)) {
                    if let Some(t) = l.out.thr {
                        l.out.thr = Some(t.min(l.thr(p)));
                    }
                    if v.speed > p + 15.0 {
                        l.out.brakes = Some(true);
                    }
                }
                if let Some(ld) = land {
                    if ld.landed {
                        self.landed = true;
                    }
                    if ld.step >= 13 {
                        self.watch = false;
                    }
                }
            }
            Loop::TakeOff { stage, taxi, ka_target, ka_speed, ka_radius } => match stage {
                0 => {
                    period = 0.2;
                    if taxi.step(&mut l, self, false) == Leaf::Done {
                        *stage = 1;
                        // TakeoffCL FirstRun: flaps down, throttle 1.
                        l.flaps(true);
                        l.throttle(1.0);
                    }
                }
                1 => {
                    period = 0.2;
                    if self.takeoff_step(&mut l) == Leaf::Done {
                        self.airborne = true;
                        period = 0.5;
                        *stage = 2;
                    }
                }
                2 => {
                    if ka_radius.is_some_and(|r| dist2(v.pos, ka_target[0], ka_target[1]) < r) {
                        l.stick(0.0, 0.0);
                        *stage = 3;
                    } else {
                        keep_attitude(&mut l, *ka_target, Some(*ka_speed));
                    }
                }
                _ => l.stick(0.0, 0.0),
            },
            Loop::Formation { recover, lateral, longitudinal } => {
                period = 0.25;
                self.formation_step(&mut l, recover, lateral, *longitudinal, vmin125, vmin25);
            }
            Loop::Hold { t } => keep_attitude(&mut l, *t, Some(180.0)),
            Loop::Straight { pitch } => {
                let _ = level_wings_accel(&mut l, pitch, 180.0, vmin12);
            }
            Loop::Level { keep } => match keep {
                None => {
                    if level_wings(&mut l, 0.0035) == Leaf::Done {
                        l.stick(0.0, 0.0); // 5c99e0; KeepOrientation's FirstRun on the next tick
                        *keep = Some((f32::NAN, 0.0, 0.0));
                    }
                }
                Some(k) => {
                    if k.0.is_nan() {
                        *k = (v.att.pitch, v.att.heading, v.speed);
                    }
                    keep_orientation(&mut l, *k);
                }
            },
            Loop::Fly { f } => {
                if let Some(ff) = f
                    && ff.step(&mut l, vmin12) == Leaf::Done
                {
                    l.stick(0.0, 0.0);
                    *f = None;
                }
            }
            Loop::Dogchase => match self.target {
                Some(t) => self.nose_on = dogchase(&mut l, &t),
                None => l.stick(0.0, 0.0),
            },
            Loop::Pursuit { kind, speed } => match self.target {
                Some(t) => self.nose_on = pursuit(&mut l, &t, *kind, speed),
                None => l.stick(0.0, 0.0),
            },
            Loop::Himmelman { child, pt_z } => match self.target {
                Some(t) => self.nose_on = himmelman(&mut l, &t, child, pt_z, self.origin),
                None => l.stick(0.0, 0.0),
            },
            Loop::TailClear { state, a } => match self.target {
                Some(t) => self.nose_on = tail_clear(&mut l, &t, state, *a),
                None => l.stick(0.0, 0.0),
            },
            Loop::RunAway { state, t30, t60, pt, speed, thr } => match self.target {
                Some(t) => run_away(&mut l, &t, state, (*t30, *t60), pt, speed, thr),
                None => l.stick(0.0, 0.0),
            },
            Loop::Break90(b) => match self.target {
                Some(t) => {
                    let b = b.get_or_insert_with(|| Box::new(Break90::new(&v, &t)));
                    b.step(&mut l, vmin12);
                }
                None => l.stick(0.0, 0.0),
            },
            Loop::Popup(pp) => match self.target {
                Some(t) => {
                    let pp = pp.get_or_insert_with(|| Box::new(Popup::new(&mut l, &t)));
                    if let Some(p) = pp.step(&mut l, &mut self.popup_prev) {
                        period = p;
                    }
                }
                None => l.stick(0.0, 0.0),
            },
            Loop::LevelBomb { released, z, lw_pitch } => match self.target {
                Some(t) => level_bomb(&mut l, &t, released, *z, lw_pitch, vmin12),
                None => l.stick(0.0, 0.0),
            },
            Loop::DiveBomb(d) => match self.target {
                Some(t) => {
                    period = d.step(&mut l, &t, vmin12).unwrap_or(period);
                }
                None => l.stick(0.0, 0.0),
            },
            Loop::Slot { thr_i, prev } => {
                period = 0.1;
                self.slot_step(&mut l, thr_i, prev);
            }
            Loop::Steer => {
                // A fighter's roll law at the BFM loop's tick: at 0.1 s its fast roll overshot (inferred).
                period = if self.steer.is_some_and(|s| s.fighter) { BFM_PERIOD } else { 0.1 };
                self.steer_step(&mut l);
            }
            Loop::Bfm(prev) => {
                period = BFM_PERIOD;
                self.bfm_step(&mut l, prev);
            }
            Loop::None => {}
        }
        if let Some(p) = l.period {
            period = p;
        }
        // (Not once the landing's ground watch is off; near the ground never down, and straight down there nothing
        // is left: the loop's own stick and its ground watch stay.)
        let low = v.pos[2] - (v.ground_height as f64) < AVOID_LOW_M;
        if let Some(a) = (self.avoid.filter(|_| !v.on_ground && self.watch))
            .map(|a| if low { Vec3::new(a[0], a[1], a[2].max(0.0)) } else { a })
            .filter(|a| a.length() > 0.1)
        {
            let t = v.vel.try_normalize().unwrap_or(Vec3::NORTH);
            let lift = a * AVOID_A + Vec3::UP * G as f64;
            let (y, x) = lift_stick(&l, lift - t * lift.dot(t), None, false);
            l.stick(y, x);
            period = period.min(0.1);
        }
        if let Some(floor) = floor {
            let n = FLY_UP_G.min(v.max_g);
            if self.fly_up || v.t >= self.fly_up_next {
                self.fly_up_next = v.t + FLY_UP_CHECK_S;
                let low = fly_up_clearance(&v, ground, n as f64);
                let floor = floor as f64;
                self.fly_up = low < floor || self.fly_up && (low < 1.5 * floor || v.vel[2] < 0.0);
            }
            if self.fly_up {
                let (y, x) = fly_up_stick(&l, n);
                l.stick(y, x);
                let thr = l.out.thr.unwrap_or(crate::aircraft::MILITARY).max(crate::aircraft::MILITARY);
                l.throttle(thr);
                period = period.min(BFM_PERIOD);
            }
        }
        let out = l.out;
        let real = l.real.is_some();
        if !matches!(self.lp, Loop::None) {
            // A loop was replaced from inside (not used).
        } else {
            self.lp = lp;
        }
        // The 6-DoF's circuit ticks as the final does: a stick held for the legs' 0.2–3 s outlasts the jet's answer.
        if real {
            period = period.min(0.1);
        }
        self.period = period;
        self.next_tick = v.t + period;
        self.apply(ac, out);
        out
    }

    fn apply(&self, ac: &mut impl Host, o: Out) {
        if let Some((x, y, h)) = o.replace {
            ac.replace_on_ground(x, y, h);
        }
        if let Some(p) = o.pivot {
            ac.set_pivot(p);
        }
        let mut c: Controls = ac.controls();
        if let Some((y, x)) = o.stick {
            c.stick_y = -y;
            c.stick_x = x;
        }
        if let Some(t) = o.thr {
            c.throttle = t;
        }
        if let Some(r) = o.rudder {
            c.rudder = r;
        }
        if let Some(g) = o.gear {
            c.gear_down = g;
        }
        if let Some(f) = o.flaps {
            c.flaps = if f { 1.0 } else { 0.0 };
        }
        if let Some(b) = o.brakes {
            c.brakes = b;
        }
        ac.set_controls(c);
        if o.engine_off {
            ac.engine_off();
        }
    }

    /// Ours, an AI jet's take-off on the 6-DoF: the nose wheel onto the runway's heading on the roll ([`ROLL_STEER`]).
    /// Left alone the jet kept the heading its taxi left: up to 10° off where its last pivot ended in a turn and it
    /// coasted on turning, 3° off on the roll (60 m across 1.2 km), and a pair rolled 15 m apart. Past 30 kt a pedal
    /// that engages the nose wheel turns the jet hard and less leaves the wheel castoring, so there the pedal falls
    /// with the speed squared and only an error of a degree or more engages it. In a pairs take-off the heading aimed
    /// at turns back onto the jet's own line, the runway's through its lineup point ([`Autopilot::lineup_offset`] right of it), within
    /// [`ROLL_LINE_LOOK`]: on the heading alone each jet of a pair kept whatever error under that degree its pivot
    /// left, and at Nevatim the two closed from 15 m to 10 m by the lift-off.
    fn roll_steer(&self, l: &mut Laws) {
        let v = l.v;
        let pair = self.lineup_offset != 0.0 || self.pair_lead;
        let rn = Airbase::nearest(&self.bases, [v.pos[0] as f32, v.pos[1] as f32, v.pos[2] as f32]).map_or(
            v.att.heading,
            |b| {
                let rn = b.runway_deg.to_radians();
                if !pair {
                    return rn;
                }
                let (s, c) = (rn as f64).sin_cos();
                let (dx, dy) = (v.pos[0] - b.lineup[0] as f64, v.pos[1] - b.lineup[1] as f64);
                let right = (dx * c - dy * s) as f32 - self.lineup_offset;
                rn - (right / ROLL_LINE_LOOK).atan()
            },
        );
        let max = ROLL_STEER.2 * (NWS_KT_MS / v.speed.max(1.0)).min(1.0).powi(2);
        let want = ROLL_STEER.0 * wrap(rn - v.att.heading) - ROLL_STEER.1 * v.rates[2];
        let p = want.clamp(-max, max);
        let castor = v.speed >= NWS_KT_MS && p.abs() < NWS_PEDAL;
        // In a pairs take-off a castoring jet off its line by more than ROLL_NUDGE engages the nose wheel with the
        // least pedal, a frame at a time.
        let nudge = if pair && want.abs() > ROLL_NUDGE { NWS_PEDAL.copysign(want) } else { 0.0 };
        l.out.rudder = Some(if !v.on_ground {
            0.0
        } else if castor {
            nudge
        } else {
            p
        });
    }

    /// TakeoffCL's lever on the roll: 1. Ours (Modern IAF's flights, a pairs take-off): the lead at military power
    /// ([`Autopilot::pair_lead`]); its wingman keeps beside it ([`PAIR_KEEP`]) until it lifts off.
    fn roll_throttle(&self, v: &ApView) -> f32 {
        if self.pair_lead {
            return crate::aircraft::MILITARY;
        }
        // (Only beside it: a lead already in the air, or far down the runway, is not kept station on.)
        let beside = |ld: &Leader| ld.pos.distance(v.pos) < PAIR_NEAR_M;
        let Some(ld) = self.leader.filter(|ld| ld.active && self.lineup_offset != 0.0 && v.on_ground && beside(ld))
        else {
            return 1.0;
        };
        let h = v.att.heading as f64;
        let gap = ((ld.pos[0] - v.pos[0]) * h.sin() + (ld.pos[1] - v.pos[1]) * h.cos()) as f32;
        let dv = ld.vel[0].hypot(ld.vel[1]) as f32 - v.speed;
        (crate::aircraft::MILITARY + PAIR_KEEP.0 * gap + PAIR_KEEP.1 * dv).clamp(PAIR_KEEP.2, 1.0)
    }

    /// TakeoffCL Run `5cda10`.
    fn takeoff_step(&self, l: &mut Laws) -> Leaf {
        let v = l.v;
        if v.sixdof && l.mode != 0 {
            self.roll_steer(l);
        }
        // Ours (Modern IAF's flights): a pair's lead holds for its wingman beside it; the wingman rolls with the lead.
        if self.hold && v.on_ground && v.speed < 20.0 {
            l.brakes(true);
            l.throttle(0.0);
            return Leaf::Run;
        }
        let roll_with = if self.lineup_offset != 0.0 { 1.0 } else { 25.7361 };
        if let Some(ld) = self.leader.filter(|ld| ld.active) {
            let lv = (ld.vel[0].powi(2) + ld.vel[1].powi(2) + ld.vel[2].powi(2)).sqrt() as f32;
            if lv < roll_with {
                l.brakes(true);
                // Ours: the 6-DoF's 0.6 lever is near military power against the brakes; it holds at idle.
                l.throttle(if v.sixdof { 0.0 } else { 0.6 });
                return Leaf::Run;
            }
        }
        l.brakes(false);
        l.throttle(self.roll_throttle(v));
        let agl = v.pos[2] as f32 - v.ground_height;
        if agl > 100.0 {
            l.gear(false);
            l.flaps(false);
            l.stick(0.0, 0.0);
            return Leaf::Done;
        }
        // Ours, an AI jet on the 6-DoF: from the rotation speed a 10° climb angle (its view's pitch is the flight
        // path's: on the runway it pulls until the jet lifts off, at most 9.4° on the wheels with 2 t of stores), and
        // the gear up once off the runway: at the original's 3° / 6° a Sufa with 2 t of stores was still on its wheels
        // past the tyres' 225 kt and burst them, and on its rims it stopped for good in its taxi turn after landing.
        if v.sixdof && l.mode != 0 {
            if v.speed <= 87.5028 {
                return Leaf::Run;
            }
            if v.speed > 108.092 && !v.on_ground {
                l.gear(false);
                l.flaps(false);
            }
            let y = l.pitch(10f32.to_radians());
            let x = l.roll(0.0);
            l.stick(y, x);
            return Leaf::Run;
        }
        let theta = if v.speed > 87.5028 && v.speed <= 97.7972 {
            3f32.to_radians()
        } else if v.speed > 97.7972 {
            if v.speed > 108.092 {
                l.gear(false);
                l.flaps(false);
            }
            6f32.to_radians()
        } else {
            return Leaf::Run;
        };
        let y = l.pitch(theta);
        let x = l.roll(0.0);
        l.stick(y, x);
        Leaf::Run
    }

    /// Close / Tactical formation step `5cfb50`.
    fn formation_step(
        &self,
        l: &mut Laws,
        recover: &mut bool,
        lateral: &mut f32,
        longitudinal: f32,
        vmin125: f32,
        vmin25: f32,
    ) {
        let v = l.v;
        let Some(ld) = self.leader else {
            l.stick(0.0, 0.0);
            return;
        };
        if v.speed < vmin125 || *recover {
            *recover = true;
            let _ = level_wings_dive(l, 300.0);
            if v.speed > vmin25 {
                *recover = false;
            }
            return;
        }
        let e = crate::aircraft::Euler { pitch: ld.att[0], roll: ld.att[1], heading: ld.att[2] };
        let (f, _, u) = e.basis();
        let an = f[0].hypot(f[1]).max(1e-9);
        let a = Vec3::new(f[0] / an, f[1] / an, 0.0);
        let u = if u[2] < 0.0 { -u } else { u };
        // C = horizontal(U × A), normalised: the leader's left.
        let c = u.cross(a);
        let (cx, cy) = (c[0], c[1]);
        let cn = cx.hypot(cy).max(1e-9);
        let cvec = [cx / cn, cy / cn];
        let dz = ld.pos[2] - v.pos[2];
        let k = 2000.0 - dz.abs().min(200.0) * 8.5;
        if *lateral == 200.0 && ld.pos[2] < 1524.0 {
            *lateral = 150.0;
        }
        let d = *lateral as f64;
        // Single player: the side flag stays 0, so every wingman takes the right slot (−C). UNCERTAIN.
        let mut q = Vec3::new(ld.pos[0] + k * a[0] - d * cvec[0], ld.pos[1] + k * a[1] - d * cvec[1], ld.pos[2]);
        q[2] = (q[2] + dz).max((l.ground)(q[0], q[1]) as f64 + 91.44);
        let lo = longitudinal as f64;
        let s = Vec3::new(ld.pos[0] + lo * a[0] - d * cvec[0], ld.pos[1] + lo * a[1] - d * cvec[1], ld.pos[2]);
        let (mut y, mut x) = l.look_at(q, ld.att[1], 1).unwrap_or((0.0, 0.0));
        // Speed law 5d0870.
        let dd = v.pos - s;
        let dl = dd.length();
        let dn = if dl > 0.0 { dd / dl } else { Vec3::new(1.0, 0.0, 0.0) };
        let vl = (ld.vel[0].powi(2) + ld.vel[1].powi(2) + ld.vel[2].powi(2)).sqrt();
        let lvn = if vl > 0.0 { ld.vel / vl } else { Vec3::NORTH };
        let cosang = dn.dot(lvn).clamp(-1.0, 1.0);
        let xx = ((cosang.acos() - std::f64::consts::FRAC_PI_2) * dl.min(5562.0) / 4500.0) as f32;
        let vl = vl as f32;
        let spd =
            (vl + 2.0 * vl * (xx - xx * xx / 2.0 + xx.powi(3) / 6.0 - xx.powi(4) / 24.0) - 30.0).clamp(103.0, 515.0);
        let mut thr = l.thr(spd);
        l.watch_ground(&mut x, &mut y, &mut thr);
        l.stick(y, x);
        l.throttle(thr);
    }

    /// Ours, the slot loop ([`MODE_SLOT`], docs/ai.md §8.7; laws inferred): the acceleration that closes the error to
    /// the slot S = leader + `slot` (the slot's own acceleration in the leader's turn, plus a spring and a damper on
    /// the position and velocity errors, the position error at most [`SLOT_E_MAX`]) is flown across the flight path
    /// as a bank and a load factor (with gravity's share), and along it as a speed: the slot's speed plus an overtake
    /// on the along-track error, through a PI throttle (the original's speed law leaves a standing error on the
    /// 6-DoF) and the speed brake when 10 m/s fast. The ground watch stays on. A far slot is the same law: the
    /// rejoin.
    fn slot_step(&self, l: &mut Laws, thr_i: &mut f32, prev: &mut Option<(f64, Vec3, Vec3, f32)>) {
        let v = l.v;
        let Some(ld) = self.leader else {
            l.stick(0.0, 0.0);
            return;
        };
        let g = G as f64;
        let d = slot_offset(&ld, self.slot);
        // The leader's acceleration from its velocity at the last tick, and its turn rate (clockwise seen from above);
        // the slot moves with the leader's frame turning.
        // (A leader 20 m off where the last tick's would be is a new one, after a promotion: none.)
        let (a_l, rate) = match *prev {
            Some((t0, p0, v0, r0)) if v.t > t0 && ld.pos.distance(p0 + v0 * (v.t - t0)) < LEADER_JUMP_M => {
                ((ld.vel - v0) * (1.0 / (v.t - t0)), wrap(ld.att[1] - r0) as f64 / (v.t - t0))
            }
            _ => (Vec3::ZERO, 0.0),
        };
        *prev = Some((v.t, ld.pos, ld.vel, ld.att[1]));
        // Close up, the leader's lift rolled on by its roll rate for SLOT_ROLL_LEAD_S: the wingman rolls with the
        // leader, as a wingman in close formation watches the leader's wings, not its path ("welded wing" turns).
        let a_l = match ld.vel.try_normalize().filter(|_| self.close) {
            Some(tl) => {
                let lift = a_l + Vec3::UP * G as f64;
                let lift = lift - tl * lift.dot(tl);
                let th = (rate * SLOT_ROLL_LEAD_S).clamp(-1.0, 1.0);
                a_l + lift * (th.cos() - 1.0) + tl.cross(lift) * th.sin()
            }
            None => a_l,
        };
        let h2 = (ld.vel[0] * ld.vel[0] + ld.vel[1] * ld.vel[1]).max(1.0);
        let w = ((a_l[0] * ld.vel[1] - a_l[1] * ld.vel[0]) / h2).clamp(-0.5, 0.5);
        let vs = ld.vel + Vec3::new(w * d[1], -w * d[0], 0.0);
        let a_s = a_l - Vec3::new(d[0], d[1], 0.0) * (w * w);
        let e = ld.pos + d - v.pos;
        let de = vs - v.vel;
        let t = v.vel.try_normalize().unwrap_or(Vec3::NORTH);
        let across = |x: Vec3| x - t * x.dot(t);
        // The horizontal and the vertical error each at most SLOT_E_MAX: a far slot still gets its full height (the
        // transit's step down before paths cross).
        let eh = Vec3::new(e[0], e[1], 0.0);
        let ec = eh * (SLOT_E_MAX / eh.length().max(SLOT_E_MAX)) + Vec3::UP * e[2].clamp(-SLOT_E_MAX, SLOT_E_MAX);
        let kd = 2.0 * SLOT_ZETA * SLOT_W;
        let lift = across(a_s + ec * (SLOT_W * SLOT_W) + de * kd + Vec3::UP * g);
        let (mut y, mut x) = lift_stick(l, lift, None, self.close);
        // Along the path: the slot's speed and the overtake; the PI throttle.
        let (lo, hi) = SLOT_OVERTAKE;
        let vt = (vs.dot(t) + (SLOT_K_ALONG * e.dot(t)).clamp(lo, hi) + a_s.dot(t) * SLOT_ANTICIPATE_S) as f32;
        // Never slower than the jet flies level at the circuit's α (a slow leader, a big-angle rejoin); toward a far
        // slot never slower than the slot's speed less the overtake's closing back while the slot flies more than 60°
        // off the jet's path (one flying the other way had its speed along the path below zero: idle and the speed
        // brake in the climb to it, a stall on the 6-DoF; one 60–90° off still idled through the turn to it).
        let far = if e.length() > SLOT_E_MAX && vs.dot(t) < 0.5 * vs.length() { vs.length() + lo } else { 0.0 };
        let vt = vt.max(v.circuit.map_or(0.0, |c| c.1)).max(far as f32);
        let err = vt - v.speed;
        let (kp, ki) = SLOT_THR;
        let kp = if self.close { kp * SLOT_CLOSE_KP } else { kp };
        let mut thr = (*thr_i + kp * err).clamp(0.0, 1.0);
        if thr > 0.0 && thr < 1.0 {
            *thr_i = (*thr_i + ki * err * 0.1).clamp(0.0, 1.0);
        }
        l.watch_ground(&mut x, &mut y, &mut thr);
        if !v.on_ground {
            l.gear(false);
            l.flaps(false);
        }
        l.brakes(err < -10.0);
        l.stick(y, x);
        l.throttle(thr);
    }

    /// Ours, the steer loop ([`MODE_STEER`], docs/ai.md §8.8; laws inferred): the heading error to the point flown as
    /// a turn rate ([`STEER_K`] per radian, at most the order's load factor), the point's height through a spring and
    /// a damper, both as a bank and a load factor ([`lift_stick`]); the speed law's throttle, at most the order's.
    /// The ground watch stays on. A far point is a heading; a near one is circled.
    fn steer_step(&self, l: &mut Laws) {
        let v = l.v;
        let Some(s) = self.steer else {
            l.stick(0.0, 0.0);
            return;
        };
        let g = G as f64;
        let t = v.vel.try_normalize().unwrap_or(Vec3::NORTH);
        let th = Vec3::new(t[0], t[1], 0.0).try_normalize().unwrap_or(Vec3::NORTH);
        let d = s.to - v.pos;
        let dh = Vec3::new(d[0], d[1], 0.0).try_normalize().unwrap_or(th);
        // The heading error, + to the left.
        let e = th.cross(dh)[2].atan2(th.dot(dh));
        // Ours: the terrain following's height in place of the point's.
        let (dz, rate) = self.follow.map_or((d[2], 0.0), |agl| {
            let (h, rate) = follow_height(v, l.ground, agl);
            (h - v.pos[2], rate)
        });
        let hw = if s.fighter { FIGHTER_STEER_W } else { STEER_W };
        let a_up = if self.follow.is_some() {
            let (down, up) = (FOLLOW_PATH_DEG.0.to_radians().sin(), FOLLOW_PATH_DEG.1.to_radians().sin());
            let vz = (rate + FOLLOW_K * dz).clamp(-down * v.speed as f64, up * v.speed as f64);
            (FOLLOW_KV * (vz - v.vel[2])).clamp(-FOLLOW_G.0 * g, FOLLOW_G.1 * g)
        } else {
            (hw * hw * dz - 2.0 * STEER_ZETA * hw * v.vel[2]).clamp(-g, g)
        };
        // A fighter's turn: what the load factor leaves once the height law's lift upward is held.
        let a_max = if s.fighter {
            let n = s.g.min(v.max_g) as f64 * g;
            (n * n - (g + a_up).powi(2)).max(0.0).sqrt()
        } else {
            ((s.g * s.g) as f64 - 1.0).max(0.0).sqrt() * g
        };
        let a_turn = (STEER_K * v.speed as f64 * e).clamp(-a_max, a_max);
        let lift = Vec3::UP.cross(th) * a_turn + Vec3::UP * (g + a_up);
        // A fighter's lift upward: 1 g at most going down, else the height law's.
        let hold = s.fighter.then_some(if dz < -STEER_DOWN_M { g } else { g + a_up });
        let (mut y, mut x) = lift_stick(l, lift - t * lift.dot(t), hold, false);
        let mut thr = l.thr(s.speed).min(s.thr_max);
        l.watch_ground(&mut x, &mut y, &mut thr);
        l.gear(false);
        l.flaps(false);
        // (A fighter's speed brake, opened by the BFM loop, closes: its steer loop flies full power or the speed law.)
        if s.fighter {
            l.brakes(false);
        }
        l.stick(y, x);
        l.throttle(thr);
    }

    /// Ours, the BFM loop ([`MODE_BFM`], docs/ai.md §18.2; laws inferred): the steer order's point flown in any plane,
    /// the lift rolled onto it with no bank limit ([`lift_stick_in`]), the line to it within [`BFM_STEEP`] of the
    /// horizon; the turn asked [`BFM_K`] per radian of the angle to the point plus the swing of the line to it since
    /// the last tick (the point's own motion, as a proportional navigation's: a moving point is tracked with no
    /// standing error; the swing at most [`BFM_SWING`], so a new point adds no jolt), within the order's load factor
    /// and the jet's once gravity's share across the path is held; the speed law's throttle, at most the order's. The
    /// ground watch stays on.
    fn bfm_step(&self, l: &mut Laws, prev: &mut Option<(f64, Vec3)>) {
        let v = l.v;
        let Some(s) = self.steer else {
            l.stick(0.0, 0.0);
            return;
        };
        let g = G as f64;
        let t = v.vel.try_normalize().unwrap_or(Vec3::NORTH);
        let d = steep_cut((s.to - v.pos).try_normalize().unwrap_or(t));
        let n_max = s.g.min(v.max_g);
        let swing = match prev.replace((v.t, d)) {
            Some((t0, d0)) if v.t > t0 => (d - d0) / (v.t - t0),
            _ => Vec3::ZERO,
        };
        let swing = swing * (BFM_SWING / swing.length().max(1e-9)).min(1.0);
        let across = (d - t * t.dot(d)).try_normalize().unwrap_or(Vec3::ZERO);
        let want = across * (BFM_K * t.dot(d).clamp(-1.0, 1.0).acos()) + (swing - t * t.dot(swing));
        // The turn inside the load factor left once gravity's share is held: |a u + w| = n g along the turn's u.
        let w = (Vec3::UP - t * t[2]) * g;
        let a = want.length() * v.speed as f64;
        let u = want.try_normalize().unwrap_or(Vec3::ZERO);
        let uw = u.dot(w);
        let room = (uw * uw - w.dot(w) + (n_max as f64 * g).powi(2)).max(0.0).sqrt() - uw;
        let lift = u * a.min(room.max(0.0)) + w;
        // (The bank is measured about the horizon's right, undefined straight up or down: the line to the point is
        // kept within BFM_STEEP of the horizon, so the path stays off the vertical.)
        let (mut y, mut x) = lift_stick_in(l, lift, std::f64::consts::PI, f64::NEG_INFINITY, n_max, None, false);
        let mut thr = l.thr(s.speed).min(s.thr_max);
        l.watch_ground(&mut x, &mut y, &mut thr);
        l.gear(false);
        l.flaps(false);
        l.brakes(v.speed > s.speed + BFM_BRAKE_MS);
        l.stick(y, x);
        l.throttle(thr);
    }
}

/// Ours, the fly-up's stick ([`FLY_UP_G`]): the lift rolled onto the world's up across the flight path at the
/// fighter's roll rate, `n` g until the path climbs at [`FLY_UP_DEG`], then gravity's share across it (the climb held).
fn fly_up_stick(l: &Laws, n: f32) -> (f32, f32) {
    let t = l.v.vel.try_normalize().unwrap_or(Vec3::NORTH);
    let w = Vec3::UP - t * t[2];
    let lift = if t[2] < FLY_UP_DEG.to_radians().sin() {
        w.try_normalize().unwrap_or(track(l.v)) * (n as f64 * G as f64)
    } else {
        w * G as f64
    };
    lift_stick_in(l, lift, std::f64::consts::PI, 0.0, n, Some(f64::INFINITY), false)
}

/// The stick (pitch, roll) that flies the lift `lift` (m/s², world, across the flight path): a bank about the flight
/// path and a load factor on the wing's present lift axis (no pull while the jet is still rolled the wrong way; never a
/// push), within the slot loop's bank and the jet's load factor; rolled by [`SLOT_ROLL`] with `slot` (the slot loop),
/// else by the original's roll law. With `hold` (a [`Steer::fighter`]: its lift upward,
/// m/s²) within the steer loop's bank, rolled by the fighter's roll law, and never more lift upward than `hold`: a jet
/// still rolling into a hard turn pulls only what holds its height, so the turn's lift does not climb it.
fn lift_stick(l: &Laws, lift: Vec3, hold: Option<f64>, slot: bool) -> (f32, f32) {
    let v = l.v;
    // (A fighter's load factor: the jet's, its order's turn within it.)
    let n_max = if hold.is_some() { v.max_g } else { v.circuit.map_or(v.max_g, |c| c.0.min(v.max_g)).min(SLOT_G_MAX) };
    let lim = if hold.is_some() { STEER_BANK_MAX } else { SLOT_BANK_MAX }.to_radians();
    lift_stick_in(l, lift, lim, 0.2 * G as f64, n_max, hold, slot)
}

/// [`lift_stick`] within the bank `lim` (rad), the lift's up share taken as at least `up_min` (m/s²) for the bank, and
/// the load factor `n_max`; `hold` as [`lift_stick`]'s.
fn lift_stick_in(l: &Laws, lift: Vec3, lim: f64, up_min: f64, n_max: f32, hold: Option<f64>, slot: bool) -> (f32, f32) {
    let v = l.v;
    let t = v.vel.try_normalize().unwrap_or(Vec3::NORTH);
    let right = t.cross(Vec3::UP).try_normalize().unwrap_or(Vec3::new(1.0, 0.0, 0.0));
    let up = right.cross(t);
    let (lr, lu) = (lift.dot(right), lift.dot(up));
    let bank = lr.atan2(lu.max(up_min)).clamp(-lim, lim) as f32;
    let roll = v.att.roll;
    let mut n = ((lr as f32 * roll.sin() + lu as f32 * roll.cos()) / G).max(0.0);
    let x = match hold {
        Some(up) => {
            if roll.cos() > 0.05 {
                n = n.min((up.max(0.0) / G as f64) as f32 / roll.cos());
            }
            (wrap(bank - roll) * FIGHTER_ROLL_K / v.max_roll_rate.max(1e-3)).clamp(-1.0, 1.0)
        }
        None if slot => {
            let rmax = v.max_roll_rate.max(1e-3);
            ((wrap(bank - roll) * SLOT_ROLL.0 - SLOT_ROLL.1 * v.rates[1]) / rmax).clamp(-1.0, 1.0)
        }
        None => l.roll(bank),
    };
    (l.inv_g(n.min(n_max)), x)
}

impl Taxi {
    /// TaxiCL FirstRun + Run (docs/ai.md §8.2).
    fn step(&mut self, l: &mut Laws, ap: &Autopilot, _unused: bool) -> Leaf {
        let v = l.v;
        let pos = v.pos;
        let Some((bi, base)) = ap.bases.iter().enumerate().min_by(|a, b| {
            let d = |x: &Airbase| (0..3).map(|i| (x.lineup[i] as f64 - pos[i]).powi(2)).sum::<f64>();
            d(a.1).total_cmp(&d(b.1))
        }) else {
            return Leaf::Done;
        };
        let lineup = base.lineup;
        if self.first {
            self.first = false;
            self.at_lineup = dist2(pos, lineup[0] as f64, lineup[1] as f64) < 100.0;
            if !self.park {
                let wp0 = ap.route.first().map_or(0.0, |w| w.t);
                self.start = if ap.leader.is_none() { wp0 } else { wp0 + if self.at_lineup { 0.0 } else { 10.0 } };
                self.waiting = true;
            }
            if self.at_lineup && !self.park {
                return self.run(l, ap, lineup);
            }
            if !self.park {
                let h = base.hangar_near(pos[0] as f32, pos[1] as f32);
                if let Some(h) = h {
                    occupy(bi, h, true);
                    self.hangar = Some((bi, h));
                }
                // The hangar's turn point and the shared path, or the hangar's own path (Modern IAF's bases).
                let mut path = base.departure(h);
                // Drop the points before the one nearest in 2-D.
                if let Some((n, _)) = path.iter().enumerate().min_by(|a, b| {
                    dist2(pos, a.1.x as f64, a.1.y as f64).total_cmp(&dist2(pos, b.1.x as f64, b.1.y as f64))
                }) {
                    path.drain(..n);
                }
                let at_hangar =
                    h.is_some_and(|h| dist2(pos, base.hangars[h].x as f64, base.hangars[h].y as f64) <= 100.0);
                if !at_hangar && let Some(p0) = path.first() {
                    // Re-placed 60 m before the first point on its heading, at rest (UNCERTAIN: the sign).
                    let x = p0.x as f64 - 60.0 * (p0.hdg as f64).sin();
                    let y = p0.y as f64 - 60.0 * (p0.hdg as f64).cos();
                    l.out.replace = Some((x, y, p0.hdg));
                }
                if path.first().is_some_and(|p| {
                    dist2(Vec3::new(p.x as f64, p.y as f64, 0.0), lineup[0] as f64, lineup[1] as f64) < 100.0
                }) {
                    self.at_lineup = true;
                }
                // Ours, a pairs take-off: the wingman's path ends beside the lineup, its offset right of it, and so
                // does its runway entry (the point before, on the centreline: 86–101 m before the lineup at each base
                // of Modern IAF's iaf.ibx), so its last leg runs beside its lead's.
                if ap.lineup_offset != 0.0
                    && let Some(e) = path_end_at(&path, lineup)
                {
                    let (s, c) = (e.hdg as f64).sin_cos();
                    let o = ap.lineup_offset as f64;
                    let n = path.len();
                    for p in path.iter_mut().skip(n.saturating_sub(2)) {
                        let across = (p.x - e.x) as f64 * c - (p.y - e.y) as f64 * s;
                        if across.abs() < 10.0 {
                            (p.x, p.y) = ((p.x as f64 + o * c) as f32, (p.y as f64 - o * s) as f32);
                        }
                    }
                }
                self.path = path;
            } else {
                let o = OCCUPIED.lock().unwrap().clone();
                let n = base.hangars.len();
                // Ours: a jet with a home hangar parks there when it is free (Modern IAF's flights).
                let home = ap.home_hangar.filter(|&(b, h)| b == bi && h < n && !o.contains(&(b, h)));
                let h = if v.type_code == C130 {
                    n.saturating_sub(1)
                } else if let Some((_, h)) = home {
                    h
                } else {
                    (0..n).find(|h| !o.contains(&(bi, *h))).unwrap_or(0)
                };
                if n > 0 {
                    occupy(bi, h, true);
                    self.hangar = Some((bi, h));
                }
                self.path = base.arrival((n > 0).then_some(h));
                // Ours: the 6-DoF turns on its wheels (a 30 m radius), so the turn about at the hangar point is left
                // out; ParkInHangar steers in from the turn point.
                if v.sixdof && n > 0 {
                    self.path.pop();
                }
            }
            return Leaf::Run;
        }
        self.run(l, ap, lineup)
    }

    fn run(&mut self, l: &mut Laws, ap: &Autopilot, lineup: [f32; 3]) -> Leaf {
        let v = l.v;
        let now = v.t;
        let lead = ap.leader;
        let i_am_lead = lead.is_none();
        let free = lead.is_none_or(|ld| !ld.active);
        let (mut near, mut tight, mut lead_v, mut lead_moving) = (false, false, 0.0, false);
        if let Some(ld) = lead {
            lead_v = (ld.vel[0].hypot(ld.vel[1])) as f32;
            lead_moving = lead_v > 1.0;
            let h = v.att.heading as f64;
            let (dx0, dy0) = (v.pos[0] - ld.pos[0], v.pos[1] - ld.pos[1]);
            let dx = dx0 * h.cos() - dy0 * h.sin();
            let dy = dx0 * h.sin() + dy0 * h.cos();
            near = dx.abs() < 50.0 && dy.abs() < 200.0;
            tight = dx.abs() < 50.0 && dy.abs() < 100.0;
        }
        if !i_am_lead && !free && lead_moving {
            self.start = now;
        }
        // Ours, a pairs take-off: its lead lined up (at rest by the lineup), the wingman taxies up beside it.
        let lined_up = lead.is_some_and(|ld| dist2(ld.pos, lineup[0] as f64, lineup[1] as f64) < 100.0);
        let beside = ap.lineup_offset != 0.0 && lined_up && !lead_moving;
        if self.waiting && !self.park {
            if now < self.start {
                if !free && !i_am_lead && tight && !beside {
                    self.start = now + 3.0;
                }
                if !i_am_lead && self.at_lineup {
                    l.out.rudder = Some(0.0);
                    l.throttle(0.0);
                    l.brakes(false);
                    return Leaf::Done;
                }
                l.brakes(true);
                l.throttle(0.0);
                return Leaf::Run;
            }
            self.waiting = false;
            l.brakes(false);
            if self.at_lineup {
                return Leaf::Done;
            }
            if let Some((b, h)) = self.hangar.take() {
                occupy(b, h, false);
            }
        }
        // Ours (Modern IAF's flights): to park, a jet ahead on the way holds it (the flight's word).
        if self.park && ap.hold {
            l.brakes(true);
            l.throttle(0.0);
            return Leaf::Run;
        }
        if !self.park && !free && !i_am_lead && tight && !beside {
            self.waiting = true;
            self.start = now + 3.0;
            l.brakes(true);
            l.throttle(0.0);
            return Leaf::Run;
        }
        let mut vt = if !self.park && !free && !i_am_lead && near && lead_moving { lead_v } else { 15.4417 };
        // Ours, an AI jet on the 6-DoF: slow before a pivot to its wheel turn's speed ([`PIVOT_IN`]).
        let ai6 = v.sixdof && l.mode != 0;
        let mut slow = false;
        if let Some(p) = self.path.get(self.i).filter(|_| ai6 && !self.turning) {
            let h = v.att.heading as f64;
            let along = ((p.x as f64 - v.pos[0]) * h.sin() + (p.y as f64 - v.pos[1]) * h.cos()) as f32;
            let turn = wrap(p.hdg - v.att.heading).abs();
            let lineup = !self.park && self.i + 1 == self.path.len();
            if lineup || turn > PIVOT_IN.2.to_radians() {
                let v0 = if lineup { LINEUP_WALK } else { PIVOT_IN.0 };
                let cap = (v0 * v0 + 2.0 * PIVOT_IN.1 * (along - pivot_lead(turn)).max(0.0)).sqrt();
                slow = cap < vt;
                vt = vt.min(cap);
            }
        }
        // Ours, the 6-DoF: idle through a pivot (thrust in a tight wheel turn tipped the jet onto its tail).
        let mut thr = if ai6 && self.turning { 0.0 } else { l.taxi_thr(vt, &mut self.thr_i) };
        // Ours, an AI jet on the 6-DoF: its idle thrust runs it past the taxi speed (36 m/s on the taxiway); the
        // wheel brakes hold it within 3 m/s of it (inferred), and within 0.5 m/s of a pivot's speed.
        l.brakes(ai6 && v.speed > vt + if slow { 0.5 } else { 3.0 });
        let mut done = false;
        if let Some(p) = self.path.get(self.i).copied() {
            // Along-track distance to the point.
            let h = v.att.heading as f64;
            let along = (p.x as f64 - v.pos[0]) * h.sin() + (p.y as f64 - v.pos[1]) * h.cos();
            let lead_m = if ai6 { pivot_lead(wrap(p.hdg - v.att.heading).abs()) as f64 } else { 30.0 };
            if !self.turning && along <= lead_m {
                l.out.pivot = Some(Some(p.hdg));
                self.turning = true;
            }
            let lineup = !self.park && self.i + 1 == self.path.len();
            let tol = if ai6 && lineup { LINEUP_TOL_DEG } else { 0.5 };
            if self.turning && wrap(p.hdg - v.att.heading).abs() < tol.to_radians() {
                l.out.pivot = Some(None);
                self.i += 1;
                self.turning = false;
                l.stick(0.0, 0.0);
                l.out.rudder = Some(0.0);
                if self.i >= self.path.len() {
                    l.out.rudder = Some(0.0);
                    l.throttle(0.0);
                    l.brakes(false);
                    done = true;
                }
            }
            // Ours, an AI jet on the 6-DoF: between the pivots the nose wheel steers a little at the point (inferred:
            // at most a 3° wheel, gentle at taxi speed); the pivot's 30 m wheel turn leaves the jet off the next leg,
            // and on the heading alone it wandered to another shelter.
            if v.sixdof && l.mode != 0 && !self.turning && !done {
                let (mut x, mut y, mut lim) = (p.x as f64, p.y as f64, 0.1);
                if lineup {
                    let (s, c) = (p.hdg as f64).sin_cos();
                    let k = ((v.pos[0] - x) * s + (v.pos[1] - y) * c + LINEUP_LOOK).min(0.0);
                    (x, y, lim) = (x + k * s, y + k * c, LINEUP_WHEEL);
                }
                let e = wrap(((x - v.pos[0]) as f32).atan2((y - v.pos[1]) as f32) - v.att.heading);
                l.out.rudder = Some((0.5 * e).clamp(-lim, lim));
            }
        } else {
            done = true;
        }
        if !done && v.type_code != C130 {
            thr = thr.min(0.7);
        }
        if !done {
            l.throttle(thr);
        }
        if done { Leaf::Done } else { Leaf::Run }
    }
}

impl Landing {
    /// LandingCL Init `5d2b30`: the left-hand pattern from G to the nearest base's lineup.
    fn new(bases: &[Airbase], origin: [f64; 2], g: Vec3, type_code: u32, player: bool) -> Option<Self> {
        let base = Airbase::nearest(bases, [g[0] as f32, g[1] as f32, g[2] as f32])?;
        let c130 = type_code == C130;
        let rn = base.runway_deg.to_radians();
        let ht = base.lineup[2] as f64; // UNCERTAIN: terrain(L); the lineup's altitude here
        // The frame and the points are f32 in world coordinates, as the original (`459bd0` / `459c90`: θ =
        // rad(fmod(−RN, 360)), the matrix `43ecd0` rotated by θ, `43dd70`, then L + the offset rounded to f32). So
        // for an axis-aligned runway the residue of cos θ (~1e-8) vanishes and the legs P1→P2, P2→P3 and
        // P3→P4→P5 are exactly horizontal / vertical lines: ChangeHeading2PtAcu's tangent search takes its
        // axis-parallel branches.
        let w = |x: f64, y: f64| [(x + origin[0]) as f32, (y + origin[1]) as f32];
        let lw = w(base.lineup[0] as f64, base.lineup[1] as f64);
        let th = std::f32::consts::PI * ((-base.runway_deg) % 360.0) / 180.0;
        let (s, c) = (-th.sin(), th.cos());
        let at = |o: [f32; 2], x: f32, y: f32| {
            [(o[0] + (x * c + y * s)) as f64 - origin[0], (o[1] + (-x * s + y * c)) as f64 - origin[1]]
        };
        let side = if c130 { -9270.0 } else { -5562.0 };
        let p1 = at(w(g[0], g[1]), side, 0.0);
        let l = at(lw, 0.0, 0.0);
        let p2 = at(lw, side, -7416.0);
        let p3 = at(lw, 0.0, -7416.0);
        let p4 = at(lw, 0.0, if c130 { -1854.0 } else { -3708.0 });
        Some(Landing {
            step: 0,
            pts: [
                Vec3::new(p1[0], p1[1], ht + 700.0),
                Vec3::new(p2[0], p2[1], ht + if c130 { 600.0 } else { 500.0 }),
                Vec3::new(p3[0], p3[1], ht + if c130 { 350.0 } else { 300.0 }),
                Vec3::new(p4[0], p4[1], ht + 250.0),
                Vec3::new(l[0], l[1], ht),
            ],
            rn,
            k: if c130 { 2.0 } else { 1.0 },
            lw_pitch: 0.0,
            taxi: None,
            park: None,
            landed: false,
            acu: None,
            player,
            align: false,
            flare: false,
            flare_i: 0.0,
            final_i: 0.0,
            thr_i: 0.0,
            touched: false,
            six: false,
            park_thr: 0.0,
        })
    }

    /// The wheels' height the flare flies to. Ours, an AI jet on the 6-DoF: over the runway, which is the lineup's
    /// height short of the lineup and the ground under the jet past it. The ground under the final can
    /// stand above the runway (Nevatim's, up to 12 m) and the runway can fall past the lineup (Nevatim's, 2 m in its
    /// first 240 m): over the ground the flare began 20 m up over the rise, levelled off 6 m over the runway, slowed
    /// at idle and dropped onto it at 6 m/s (a crash on the sink rate). The player's flare keeps the ground's.
    fn wheels_height(&self, v: &ApView) -> f32 {
        if self.player || !self.six {
            return wheels_height(v);
        }
        let l = self.pts[4];
        let along = (v.pos[0] - l[0]) * (self.rn as f64).sin() + (v.pos[1] - l[1]) * (self.rn as f64).cos();
        let runway = if along < 0.0 { l[2] as f32 } else { v.ground_height };
        v.pos[2] as f32 - runway - v.gear_clearance.abs()
    }

    /// The player's flare and its leg ends ([`Autopilot::player_flare`]), or an AI jet on the 6-DoF.
    fn flares(&self) -> bool {
        if self.player { self.flare } else { self.six }
    }

    /// The child list of LandingCL (ctor `5c6370`): CH1, CA1, LW1, KA1, CH2, CA2, LW2, KA2, CH3, CA3, KA3, CH4,
    /// [CA4: C-130], CH5, FinalApproach, StopPlane, TaxiCL (to park), ParkInHangar.
    fn legs(&self, c130: bool, cfg: &Config) -> Vec<Leg> {
        let k = self.k;
        let ae = cfg.allowed_err;
        let d = |x: f32| x.to_radians();
        let tol = |i: usize| d(if c130 { [2.0, 1.0, 0.5, 0.5, 0.5][i] } else { [1.0, 0.5, 0.5, 0.5, 0.5][i] });
        let lim80 = if c130 { d(40.0) } else { d(80.0) };
        let (lim60, lim20) = if c130 { (lim80, lim80) } else { (d(60.0), d(20.0)) };
        let s1 = if c130 { 113.239 } else { 128.681 };
        let mut v = vec![
            Leg::Ch(0, tol(0), lim80, None),
            if c130 { Leg::CaOr(0, k * ae[0] as f64) } else { Leg::Ca(0, 50.0) },
            Leg::Lw(s1),
            Leg::Ka(0, s1, k * ae[0] as f64),
            Leg::Ch(1, tol(1), lim80, None),
            Leg::Ca(1, 50.0),
            Leg::Lw(102.944),
            Leg::Ka(1, 102.944, k * ae[1] as f64),
            Leg::Ch(2, tol(2), lim60, None),
            Leg::Ca(2, 250.0),
            Leg::Ka(2, 87.503, 1852.0),
            Leg::Ch(3, tol(3), lim60, Some(72.0611)),
        ];
        if c130 {
            v.push(Leg::Ca(3, 50.0));
        }
        v.extend([Leg::Ch(4, tol(4), lim20, Some(72.0611)), Leg::Fa(k * ae[4] as f64), Leg::Stop]);
        if !self.player {
            v.extend([Leg::Taxi, Leg::Park]);
        }
        v
    }

    /// One tick of the current child; `Next` (`5d43e0`) at the step boundaries.
    fn step(&mut self, l: &mut Laws, ap: &Autopilot, period: &mut f64, vmin1: f32, vmin12: f32) -> Leaf {
        let c130 = l.v.type_code == C130;
        let legs = self.legs(c130, &ap.cfg);
        let Some(leg) = legs.get(self.step).copied() else {
            *period = 0.5;
            l.throttle(0.0);
            return Leaf::Done;
        };
        let pos = l.v.pos;
        let pt = self.pts;
        // Modern IAF's 6-DoF: the legs' own laws ([`REAL_CIRCUIT`]), and the final starts where the base turn ends,
        // on the centreline law (as World scale Real's, `align`): CH5 ends about 1 km before the lineup, where the
        // 3° path is 50 m up and the circuit 250–300 m.
        l.real = l.v.circuit.filter(|_| self.step < 13);
        l.thr_i = self.thr_i;
        self.align |= l.real.is_some();
        self.six |= l.v.circuit.is_some();
        let r = match leg {
            // World scale Real: CH5's pursuit of P5 is not a line capture on a runway off the axes (CH4 can leave
            // the jet 700 m off the centreline, and CH5 then flew level over the runway, so the final began
            // 450 m above the lineup and dived into it); FinalApproach's centreline law takes over at once
            // (docs/world-scale.md §4.3).
            Leg::Ch(4, ..) if self.align => Leaf::Done,
            Leg::Ch(i, tol, lim, vt) => {
                *period = 0.2;
                let prev = if i > 0 { Some(pt[i - 1]) } else { None };
                let off = self.flares();
                let acu = self.acu.get_or_insert_with(|| Acu::new(l.v.speed, vt));
                acu.step(l, pt[i], prev, tol, lim, off)
            }
            Leg::Ca(i, r) => {
                if (pos[2] - pt[i][2]).abs() < r {
                    Leaf::Done
                } else {
                    change_alt(l, pt[i][2]);
                    // ChangeAlt sends no throttle: the lever stays where CH's end left it (0.1). The 6-DoF climbs
                    // or descends at the next leg's speed.
                    if let (Some(_), Some(Leg::Lw(s) | Leg::Ka(_, s, _))) = (l.real, legs.get(self.step + 1)) {
                        l.throttle(l.thr(*s));
                    }
                    Leaf::Run
                }
            }
            Leg::CaOr(i, r) => {
                if dist2(pos, pt[i][0], pt[i][1]) < r || (pos[2] - pt[i][2]).abs() < 250.0 {
                    Leaf::Done
                } else {
                    change_alt(l, pt[i][2]);
                    Leaf::Run
                }
            }
            // 5d2400 takes Vmin at 1.2 g (push 0x3f99999a @5d24ad), as in Fly2WayPt.
            Leg::Lw(speed) => {
                // Ours (Real data, the player): LW2 ends below the gear's 300 kt lever limit (150 m/s = 292 kt),
                // so step 7's gear command is not refused (docs/autopilot.md §2.5).
                let wait = self.step == 6 && self.player && l.v.gear_speed_wait;
                let r = level_wings_accel_max(l, &mut self.lw_pitch, speed, vmin12, wait.then_some(150.0));
                // The wait runs with the speed brake out, so the downwind ends near P2: the F-4 on Real data with
                // the Better physics switches entered at 400 kt and needed 6.7 km at idle, and arrived on final
                // at 200 kt.
                if wait {
                    l.brakes(r == Leaf::Run);
                }
                r
            }
            Leg::Ka(i, speed, r) => self.ka(l, i, speed, r),
            Leg::Fa(r) => {
                *period = 0.1;
                // Ours, the player's flare: StopPlane takes over once the wheels are below the flare's height for the
                // jet's sink, so a fast final (the Kurnass 2000 Real at 200 kt sinks 11 m/s) starts on its profile
                // instead of 2° below it at the original's ~12 m (docs/autopilot.md §2.3).
                let v = l.v;
                let flare_h = flare_tau(v) * (-(v.vel[2] as f32) - FLARE_SINK);
                let early = self.flares() && self.wheels_height(v) < flare_h;
                if early || dist2(pos, pt[4][0], pt[4][1]) < r {
                    l.out.rudder = Some(0.0);
                    Leaf::Done
                } else {
                    self.final_approach(l, vmin1);
                    Leaf::Run
                }
            }
            Leg::Stop => {
                *period = 0.2;
                self.stop_plane(l)
            }
            Leg::Taxi => {
                *period = 0.2;
                let t = self.taxi.get_or_insert(Taxi {
                    park: true,
                    path: Vec::new(),
                    i: 0,
                    turning: false,
                    waiting: false,
                    start: 0.0,
                    at_lineup: false,
                    first: true,
                    hangar: None,
                    thr_i: 0.0,
                });
                t.step(l, ap, true)
            }
            Leg::Park => {
                *period = 0.2;
                self.park_step(l, ap)
            }
        };
        if l.real.is_some() {
            self.thr_i = (self.thr_i + 0.2 * 0.1 * l.thr_err.unwrap_or(0.0)).clamp(-40.0, 40.0);
        }
        if r == Leaf::Done {
            if !matches!(leg, Leg::Ch(..)) {
                l.stick(0.0, 0.0);
            }
            self.acu = None;
            self.step += 1;
            match self.step {
                7 => {
                    l.flaps(true);
                    l.gear(true);
                }
                13 => {
                    l.brakes(true);
                    l.watch = false;
                }
                _ => {}
            }
        }
        Leaf::Run
    }

    fn ka(&mut self, l: &mut Laws, i: usize, speed: f32, r: f64) -> Leaf {
        if dist2(l.v.pos, self.pts[i][0], self.pts[i][1]) < r {
            return Leaf::Done;
        }
        keep_attitude(l, self.pts[i], Some(speed));
        Leaf::Run
    }

    /// FinalApproachCL `5d4c50`: the 6° glide path to the lineup.
    fn final_approach(&mut self, l: &mut Laws, vmin1: f32) {
        let v = l.v;
        let p5 = self.pts[4];
        let d = v.pos - p5;
        let (s, c) = ((self.rn as f64).sin(), (self.rn as f64).cos());
        let glide = if v.final_speed.is_some() { REAL_FINAL.1 } else { 6.0 };
        let (sg, cg) = ((glide as f64).to_radians().sin(), (glide as f64).to_radians().cos());
        let fwd = Vec3::new(s * cg, c * cg, -sg);
        let up = Vec3::new(s * sg, c * sg, cg);
        let right = Vec3::new(c, -s, 0.0);
        let dot = |a: Vec3| a.dot(d) as f32;
        let (cross, along, above) = (dot(right), dot(fwd), dot(up));
        // The real final flies its on-speed α's speed (the speed brake is open from step 13 on, as the F-16 manual's
        // final has it: figure 2-3, "SPEEDBRAKES OPEN"). The speed law's error is summed (0.2 /s, ours): its fixed
        // 0.7 lever at no error held the 6-DoF 50 kt fast.
        let vt = match v.final_speed {
            Some(vt) if self.player => {
                self.final_i = (self.final_i + 0.2 * 0.1 * (vt - v.speed)).clamp(-40.0, 40.0);
                vt + self.final_i
            }
            Some(vt) => vt + self.final_i,
            None => (vmin1 + 10.2944).max(72.0611),
        };
        // The original caps the throttle at 0.5 (`5d4c50`, 0.5 at 0x6133c4): a heavy jet (the Kurnass 2000 with
        // its 312 load) sinks below the glide path at its AoA limit and lands short. Off the original the player's
        // jet below the path keeps the speed law's full throttle (docs/autopilot.md §2.3).
        let thr = l.thr(vt);
        let thr = if self.flares() && above < 0.0 { thr } else { thr.min(0.5) };
        // Ours: an AI jet's sum runs only while the lever is inside its travel; summed through a fast arrival it wound
        // to −40 m/s and held the throttle at idle below the final's speed.
        if let Some(f) = v.final_speed.filter(|_| !self.player && thr > 0.0 && thr < 0.5) {
            self.final_i = (self.final_i + 0.2 * 0.1 * (f - v.speed)).clamp(-40.0, 40.0);
        }
        let e = wrap(self.rn - v.att.heading);
        let bank = if self.align {
            self.align_bank(l)
        } else {
            (-0.001_396_3 * cross + e * l.c.change_head_k / 3.0 - l.c.change_head_beta * v.rates[2])
                .clamp(-DEG80, DEG80)
        };
        let kz = if v.final_speed.is_some() {
            REAL_FINAL_LAWS.0
        } else if above < 0.0 {
            0.03
        } else if v.type_code == C130 {
            0.05
        } else {
            0.3
        };
        let bias = if v.final_speed.is_some() || along < -1000.0 { glide } else { glide * 2.0 / 3.0 };
        let kd = if v.final_speed.is_some() { REAL_FINAL_LAWS.1 } else { 0.5 };
        let mut pitch_deg = -kz * above - kd * v.rates[0].to_degrees() - bias;
        // The real final is met from below in level flight: it never climbs to its path.
        if v.final_speed.is_some() {
            pitch_deg = pitch_deg.min(0.0);
        }
        let y = l.pitch(pitch_deg.to_radians());
        let x = l.roll(bank);
        l.stick(y, x);
        l.throttle(thr);
    }

    /// StopPlaneCL `5d44d0`.
    fn stop_plane(&mut self, l: &mut Laws) -> Leaf {
        let v = l.v;
        if v.speed <= if self.player { 1.0295 } else { 25.736 } {
            l.out.rudder = Some(0.0);
            if self.player {
                l.out.ap_key = true;
            } else {
                self.landed = true;
            }
            return Leaf::Done;
        }
        // The player's flare (below) holds a small sink down to the wheels: within 5 m of the runway that path
        // passes the original's test before the touchdown, so its "rolling" is the wheels on the ground.
        let flare = self.flares();
        let rolling = if flare {
            v.on_ground
        } else {
            v.att.pitch.abs() <= 0.2f32.to_radians()
                && (v.pos[2] as f32) < v.ground_height + v.gear_clearance.abs() + 5.0
        };
        if rolling {
            // The flare's summed correction is kept: it is the pitch law's bias at this speed, and dropping it lifted
            // the jet off again after a soft touch.
            self.touched = true;
            l.out.rudder = Some(0.0);
            l.throttle(0.0);
            // The original steers (and sets the stick) only off the runway heading; the flare's last pull then stays
            // on the wheels. The player's flare flies the ground law on every tick (docs/autopilot.md §2.3).
            let e = wrap(self.rn - v.att.heading);
            if flare || e.abs() > 0.1f32.to_radians() {
                let y = l.pitch_b(0.0);
                let x = l.roll((e - v.rates[2]).clamp(-DEG80, DEG80));
                l.stick(y, x);
            }
        } else {
            l.throttle(0.0);
            // The original holds the flight path level (pitch 0): the jet floats at idle until it stalls and drops
            // onto the runway nose first. The player's autopilot off the original flares onto it instead
            // (docs/autopilot.md §2.3).
            let y = if flare { self.flare(l) } else { l.pitch(0.0) };
            let x = l.roll(if self.align { self.align_bank(l) } else { 0.0 });
            l.stick(y, x);
        }
        Leaf::Run
    }

    /// Ours, the player's flare (docs/autopilot.md §2.3): the stick for the g that brings the sink to the wheels'
    /// height over [`FLARE_TAU`] plus [`FLARE_SINK`], once per StopPlane tick (0.2 s). The g is divided by the lift
    /// the flight model adds on top of the stick's (flaps, ground effect). The original's pitch law (`5ca010`)
    /// holds a flight path through a lagging lift ramp with a 1 g stick short of that lift, and its flare floated
    /// up to 1.6 m before the touch.
    fn flare(&mut self, l: &Laws) -> f32 {
        let v = l.v;
        // After a bounce the height term would dive the jet back at the runway (the Kurnass 2000 Real with 312's
        // load bounced to 16 m at 185 kt, then hit nose 9° down): it holds the small sink instead.
        let h = if self.touched { 0.0 } else { self.wheels_height(v).max(0.0) };
        let vz = v.vel[2] as f32;
        let tau = flare_tau(v);
        // Ours, an AI jet on the 6-DoF: the sink a lead ahead ([`FLARE_LEAD_AI`]).
        let vz_e = if !self.player && self.six { vz + v.acc[2] as f32 * FLARE_LEAD_AI } else { vz };
        let e = -(h / tau + FLARE_SINK) - vz_e;
        // On the 6-DoF the sum learns the sink's error left once the jet's vertical acceleration has acted over its
        // g lag (`FLARE_LAG_6DOF`): summing the error the lag still holds wound it to its limit in a long flare, the
        // Adir with 3 t of stores ballooned 2.6 m off the runway and dropped onto it at 4.05 m/s.
        let lag = if v.final_speed.is_some() { FLARE_LAG_6DOF } else { 0.0 };
        let e_sum = e - v.acc[2] as f32 * lag;
        self.flare_i = (self.flare_i + e_sum * 0.2 * FLARE_KI).clamp(-FLARE_I_MAX, FLARE_I_MAX);
        let a = FLARE_KV * e + self.flare_i;
        // The load factor for that vertical acceleration on the flight path, at the bank.
        let cos_path = (1.0 - (vz / v.speed.max(1.0)).powi(2)).max(0.0).sqrt();
        let n = (G + a) / (G * cos_path * v.att.roll.cos().max(0.2));
        l.inv_g(n / v.lift_factor.max(0.1)).clamp(-1.0, 1.0)
    }

    /// World scale Real only (docs/world-scale.md §4.3): the bank that holds the centreline through the lineup at
    /// RunwayNumber. The original's law (`final_approach`) is underdamped (its base turn can leave the final 100–700 m
    /// off, and it still swings ±80 m at the threshold), and the float wings-level drifts on. Here the track to the
    /// line closes at −cross / 8 s (an intercept of at most 30°) and the heading follows at 3× the original's gain.
    fn align_bank(&self, l: &Laws) -> f32 {
        let v = l.v;
        let (s, c) = ((self.rn as f64).sin(), (self.rn as f64).cos());
        let d = v.pos - self.pts[4];
        let cross = (d[0] * c - d[1] * s) as f32;
        let speed = v.speed.max(1.0);
        let want = wrap(self.rn + (-cross / 8.0 / speed).clamp(-0.5, 0.5).asin());
        let e = wrap(want - v.att.heading);
        (e * l.c.change_head_k - l.c.change_head_beta * v.rates[2]).clamp(-DEG30, DEG30)
    }

    /// ParkInHangarCL `5d66b0`: creep at 2 kt to the hangar; stop, brakes, engine off.
    fn park_step(&mut self, l: &mut Laws, ap: &Autopilot) -> Leaf {
        let v = l.v;
        if self.park.is_none() {
            let base = Airbase::nearest(&ap.bases, [v.pos[0] as f32, v.pos[1] as f32, v.pos[2] as f32]);
            let t = base.and_then(|b| b.hangar_near(v.pos[0] as f32, v.pos[1] as f32).map(|h| b.hangars[h]));
            // Ours, the 6-DoF: the hangar the taxi went to.
            let own = self.taxi.as_ref().and_then(|t| t.hangar).and_then(|(b, h)| ap.bases.get(b)?.hangars.get(h));
            let t = if v.sixdof { own.copied().or(t) } else { t };
            let Some(t) = t else { return Leaf::Done };
            self.park = Some((t.x as f64, t.y as f64, t.hdg, 1000.0));
        }
        let (x, y, hdg, last) = self.park.unwrap();
        // Ours (Modern IAF's flights): a jet ahead on the way holds it.
        if ap.hold {
            l.throttle(0.0);
            l.brakes(true);
            return Leaf::Run;
        }
        let d = dist2(v.pos, x, y);
        let mut i = self.park_thr;
        l.throttle(if v.sixdof { l.taxi_thr(1.0294, &mut i) } else { l.thr(1.0294) });
        self.park_thr = i;
        if v.sixdof {
            l.brakes(v.speed > 3.0);
        }
        // Ours, the 6-DoF: the nose wheel steers at the hangar point, and the jet is set on it facing out (the ground
        // crew's push into the shelter).
        if v.sixdof {
            l.out.pivot = Some(Some(((x - v.pos[0]) as f32).atan2((y - v.pos[1]) as f32)));
        }
        if d > last || v.sixdof && d < 2.0 {
            l.throttle(0.0);
            l.brakes(true);
            l.out.rudder = Some(0.0);
            l.stick(0.0, 0.0);
            l.out.replace = Some(if v.sixdof { (x, y, hdg) } else { (v.pos[0], v.pos[1], hdg) });
            if v.sixdof {
                l.out.pivot = Some(None);
            }
            l.out.engine_off = true;
            return Leaf::Done;
        }
        self.park = Some((x, y, hdg, d));
        Leaf::Run
    }
}

/// The wheels' height above the terrain (m).
fn wheels_height(v: &ApView) -> f32 {
    v.pos[2] as f32 - v.ground_height - v.gear_clearance.abs()
}

const DEG30: f32 = 30f32.to_radians();
const DEG80: f32 = 80f32.to_radians();

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn landing_points_are_f32_like_the_original() {
        // Runway 270 at Ramat David: in f32 the cos θ residue (~1e-8) vanishes, so the downwind, base and final
        // legs are exactly axis-parallel (the tangent search's x == x / y == y branches).
        let b = Airbase { lineup: [356483.0, 602383.0, 63.0], runway_deg: 270.0, ..Default::default() };
        let l = Landing::new(&[b], [0.0; 2], Vec3::new(351083.0, 602383.0, 1500.0), 0, true).unwrap();
        let p = l.pts;
        assert_eq!((p[0][1], p[1][1]), (596821.0, 596821.0), "downwind P1 → P2");
        assert_eq!((p[1][0], p[2][0]), (363899.0, 363899.0), "base P2 → P3");
        assert_eq!((p[2][1], p[3][1], p[4][1]), (602383.0, 602383.0, 602383.0), "final P3 → P4 → P5");
        assert_eq!(p[3][0], 360191.0);
    }

    #[test]
    fn landing_points_round_in_world_coordinates() {
        // The Godot host shifts the bases by the terrain origin; the f32 rounding must still happen in world
        // coordinates, else the small scene coordinates keep the ~1e-8 residue and the legs are not axis-parallel.
        let o = [356400.25, 602350.5];
        let b = Airbase {
            lineup: [356483.0 - o[0] as f32, 602383.0 - o[1] as f32, 63.0],
            runway_deg: 270.0,
            ..Default::default()
        };
        let l = Landing::new(&[b], o, Vec3::new(351083.0 - o[0], 602383.0 - o[1], 1500.0), 0, true).unwrap();
        let p = l.pts;
        assert_eq!(p[0][1], p[1][1]);
        assert_eq!(p[1][0], p[2][0]);
        assert_eq!((p[2][1], p[3][1]), (p[4][1], p[4][1]));
        assert_eq!(p[4][1] + o[1], 602383.0);
    }
}
