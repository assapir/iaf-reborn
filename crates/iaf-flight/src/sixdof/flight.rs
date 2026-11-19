//! One flight on the 6-DoF: a jet with its control system, engines, gear and fuel, stepped by the game's frames
//! and read back as the original model's [`State`] and [`ApView`] in the game's ENU frame (modern-iaf/docs/
//! flight-model.md §9.12). The original game never builds one ([`crate::fm::Fm`]).

use super::aero::{Flow, Surfaces, add_drag, coefficients, compressibility, lef_schedule};
use super::autopilot::{F16Autopilot, Panel as ApPanel, Sensed};
use super::body::{Body, MAX_FRAME, MAX_STEP, Quat};
use super::engine::Engine;
use super::fcs::{Fcs, Pilot, Sensors};
use super::fuel::Tanks;
use super::gear::Anchors;
use super::jets::{self, Jet};
use super::limits::{self, Brakes, Stress};
use super::start::{Phase, Start as Sequence};
use crate::aircraft::{ApView, Controls, Crash, Euler, Start, State};
use crate::atmosphere::air;
use crate::units::{G, LB};
use crate::{Envelope, Params, Vec3};

/// The game's military throttle (the original's `MILITARY`).
const MILITARY: f32 = 0.74;

/// The gear lever's ramp, as the original's: 0 down … 1.569 up at 0.5/s.
const GEAR_UP: f32 = 1.569;
const GEAR_RATE: f32 = 0.5;
/// The trailing-edge flaps' rate, deg/s: 20° in the gear's 3.1 s (inferred from the manual's "LG and TEF retraction
/// occurs simultaneously", T.O. GR1F-16CJ-1 p. 2-21).
const TEF_RATE: f64 = 20.0 / (GEAR_UP / GEAR_RATE) as f64;
/// The AoA probe's lowest valid calibrated airspeed, kt: below it the AoA gauge and indexer rest at 0° (inferred:
/// T.O. 1F-16-1 as quoted on the DCS forum: "When NLG WOW occurs, all AOA indications are based on zero degrees", the
/// transmitters being unreliable at slow speeds, https://forum.dcs.world/topic/245600-already-reportedaoa-indicator-reading-during-nlg-wow;
/// the 60 kt figure is ours).
const PROBE_MIN_KT: f64 = 60.0;
/// The indicated AoA's lag, s (inferred: enough to steady the needle at taxi and take-off speeds).
const PROBE_TAU: f64 = 0.25;
/// The autopilot's taxi turn radius, m: the original's pivot arc (`Aircraft::set_pivot`).
const PIVOT_RADIUS: f64 = 30.0;
/// The pedals' deflection (of 1) below which the nose-wheel steering is off and the nose wheel castors. The F-16's
/// steering has no speed schedule (±32°), but the pilot engages it with a button when it is needed: "Use NWS until
/// rudder is effective (approximately 70 knots)", "NWS should not be engaged above taxi speed unless required"
/// (T.O. 1F-16A-1 pp. 2-20, 2-25). The game has no NWS button: the pedals engage it (inferred). With the steering
/// held straight under full antiskid braking (the main tyres keep 0.15 of side grip) the jet yawed away into a ground
/// loop (2026-11-16); a castoring nose wheel leaves it running straight on its mains.
const NWS_ON_PEDAL: f32 = 0.02;
/// Below this ground speed, kt, the nose-wheel steering stays engaged with the pedals centred: the nose wheel follows
/// the pedals back to straight, as when taxiing with NWS on. Castoring there let a ground turn run on after the pedals
/// were centred (the user, 2026-11-17: the jet "keeps moving after I release", turning; the Sufa at 10 kt still
/// turned at 13 deg/s 2 s later). Held straight under full braking the jet stays straight from 30 kt and below
/// and ground-loops from 40 kt (inferred: the taxi speed).
const NWS_TAXI_KT: f64 = 30.0;
/// The toe brakes go from off to full (and back) over this time, s: the brake key is a switch, and a step from no
/// braking to full pitched the nose down 40 % past its braked attitude (inferred: a pilot's press on the pedals).
const BRAKE_RAMP_S: f64 = 0.5;

/// NED → the game's ENU.
fn enu(v: Vec3) -> Vec3 {
    Vec3::new(v.y, v.x, -v.z)
}

/// ENU → NED.
fn ned(v: Vec3) -> Vec3 {
    Vec3::new(v.y, v.x, -v.z)
}

/// The game's throttle (0…1, military 0.74, maximum 1) → figure 66(b)'s throttle travel (military at 0.77).
pub fn lever_to_travel(throttle: f32) -> f64 {
    let t = throttle.clamp(0.0, 1.0) as f64;
    let mil = MILITARY as f64;
    if t <= mil { t / mil * 0.77 } else { 0.77 + (t - mil) / (1.0 - mil) * 0.23 }
}

pub struct SixDof {
    /// The flight data the game loaded for the type (the own section with its REAL row): the envelope for the
    /// autopilot's Vmin and the instruments' figures.
    pub params: Params,
    pub envelope: Envelope,
    pub jet: Jet,
    body: Body,
    engine: Engine,
    anchors: Anchors,
    fcs: Fcs,
    surfaces: Surfaces,
    t: f64,
    controls: Controls,
    /// The fuel tanks ([`Tanks`], lb); the stores, kg.
    tanks: Tanks,
    stores_kg: f64,
    stores_cd: f64,
    /// The stores' lateral moment, kg·m (+ right wing heavier: `stores.rs` `roll_moment`), and the fuel tanks' at
    /// full fuel (`tank_moment`, scaled by `aircraft::tank_share`).
    stores_moment: f64,
    tank_moment: f64,
    /// The stores' right less left drag index ×10⁻⁴ (the original's `stores_asym`).
    stores_cd_asym: f64,
    /// The roll trim, stick units (`aircraft::step_roll_trim`).
    roll_trim: f64,
    /// The MANUAL PITCH override held (`fcs::Pilot`).
    pub mpo: bool,
    /// The STORES CONFIG switch at CAT III (`fcs::Pilot`).
    pub cat3: bool,
    /// The pilot's SPD BRK switch, the F-16's on the throttle (T.O. 1F-16A-1 p. 1-118: aft is sprung and opens the
    /// speed brakes while held, so they stop where it is let go; forward is a detent and closes them): +1 held aft,
    /// 0 centred, −1 forward. None: a jet flown without the switch (the AI, the tests), whose brake control opens
    /// the speed brake in the air.
    pub sb_switch: Option<i8>,
    /// The opening the SPD BRK switch has asked for, deg.
    sb_cmd: f64,
    /// The pilot's systems damage flags (bit n = flag n) and whether the jet has two engines, as the original's
    /// (`aircraft::damage_bits`, `aircraft::stick_authority`).
    damage: u32,
    twin: bool,
    /// The empty jet, kg (the reference weight less its fuel).
    empty_kg: f64,
    /// Terrain height under the jet (ENU z, m); the gear's height above its contact (for the instruments).
    pub ground_height: f32,
    pub gear_clearance: f32,
    /// The drawn model's tyres below the c.g., m (`set_wheel_height`); None: the jet's own gear figures.
    wheel_height: Option<f64>,
    pub engine_on: bool,
    /// The ground start ([`SixDof::start_engine`]); a running engine's is [`Sequence::running`].
    start_seq: Sequence,
    gear: f32,
    /// Specific force along the body axes, g (from the last step).
    accel_g: Vec3,
    /// World acceleration (ENU), m/s² (from the last step).
    acc: Vec3,
    on_ground: bool,
    crashed: Option<Crash>,
    landings: u32,
    /// Touchdowns that passed the landing limits but sank past the gear's design limit ([`crate::aircraft::hard_landing`]).
    hard_landings: u32,
    thrust_n: f64,
    pub fuel_flow: f32,
    pub unlimited_fuel: bool,
    /// A ground start waits for the terrain height to set the jet on its gear.
    place_on_gear: bool,
    /// The air mass's velocity, world NED (the mission's wind; its gusts added each substep).
    wind: Vec3,
    /// The terrain under the jet is scenery (a roof, a tree top): meeting it is a crash.
    pub ground_obstacle: bool,
    /// The terrain's slope (the normal's vertical share) and terraintype.dat flags (water, runway, rough).
    ground_normal_z: f32,
    ground_flags: Option<u32>,
    /// The Preferences' "no crashes" / "invulnerable": the ground checks pass everything.
    pub no_crashes: bool,
    /// The Preferences' "Easy landing": the landing limits ×2 (the original's rule, [`crate::aircraft::landing_limits`]).
    pub easy_landing: bool,
    /// The player's autopilot flies the landing: the original's limits, as on the original model.
    pub ap_landing: bool,
    /// An autopilot loop flies: its stick is a linear g command ([`SixDof::ap_view`]).
    ap_flying: bool,
    /// The F-16's own autopilot (PITCH / ROLL switches, [`super::autopilot`]), its panel inputs and its last commands
    /// (g increment, roll rate deg/s), added to the stick's in the control laws.
    pub autopilot: F16Autopilot,
    pub ap_panel: ApPanel,
    ap_cmd: (f64, f64),
    /// While it flies, taken twice a second at the jet's weight and height (m/s): the level speeds of the two αs of
    /// `autopilot::REAL_CIRCUIT` with the flaps and the speed brake as they are ([`ApView::circuit`]), and the real
    /// final's speed ([`ApView::final_speed`]).
    ap_speeds: Option<(f32, f32, f32)>,
    /// The AoA the probe gives the gauge, the indexer and the HUD, deg ([`probe_aoa`]).
    aoa_ind: f64,
    /// The trailing-edge flaps, deg down ([`jets::tef_schedule`]).
    tef: f64,
    /// The autopilot's taxi pivot: its target heading, rad ([`SixDof::set_pivot`]).
    pivot: Option<f64>,
    /// The toe brakes' travel, 0…1, following the brake switch over [`BRAKE_RAMP_S`].
    brake: f64,
    /// The cockpit's fuel and brake switches ([`SixDof::set_switch`]): the parking brake set, MASTER FUEL at MASTER,
    /// the ENG FEED knob (`ENG_FEED`'s index), the FUEL QTY SEL knob ([`Tanks::gauge`]'s `sel`).
    parking_brake: bool,
    master_fuel: bool,
    eng_feed: u8,
    fuel_qty_sel: u8,
    /// The load is of category III (`stores.gd` `loading_category`): on a jet with load categories
    /// (`Limits::categories`) its lower departure resistance and its rolling g limit ([`limits`]).
    pub cat3_load: bool,
    /// The Preferences' "invulnerable": no limit has any consequence (the crashes are `no_crashes`').
    pub invulnerable: bool,
    /// The structure's worst stress so far ([`Stress::Damage`]: damaged, weaker from then on) and the last step's
    /// load and speed stresses (the counts below take their rise past the limit).
    structure: Stress,
    g_stress: Stress,
    v_stress: Stress,
    over_g: u32,
    over_speed: u32,
    /// The gear was down or moving past its speed limit.
    gear_overspeed: bool,
    /// The brakes' heat.
    brakes: Brakes,
}

/// What the limits have done so far ([`SixDof::limits`], modern-iaf/docs/flight-model.md §9.20).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct LimitsState {
    /// The structure: 0 sound, 1 past its limit (an inspection), 2 damaged, 3 failed.
    pub structure: u8,
    /// Times past the g limit and past the speed limit (the manual's over-g report and overspeed).
    pub over_g: u32,
    pub over_speed: u32,
    /// The gear was down or moving past its speed limit.
    pub gear_overspeed: bool,
    /// Burst tyres.
    pub tyres_burst: u32,
    /// The braking the brakes' heat leaves, 1…0.
    pub brakes_left: f64,
    /// The c.g., fraction of the chord, and the aft limit passed.
    pub xcg: f64,
    pub cg_aft: bool,
}

/// A damaged structure's added drag, ΔCD as a drag index × 10⁻⁴ (100: inferred, panels and skin out of shape).
const DAMAGED_DI: f64 = 0.01;

/// The F-16's ENG FEED knob's positions (flight manual figure 1-23; [`Tanks::feed`]): OFF, NORM, AFT, FWD.
pub const ENG_FEED: [&str; 4] = ["OFF", "NORM", "AFT", "FWD"];
/// The F-16's FUEL QTY SEL knob's positions (flight manual figure 1-24; [`Tanks::gauge`]).
pub const FUEL_QTY_SEL: [&str; 6] = ["TEST", "NORM", "RSVR", "INT WING", "EXT WING", "EXT CTR"];

/// The indicated AoA one frame `dt` on from `shown` (deg): toward the flow's `alpha_deg` at `cas_kt` from
/// [`PROBE_MIN_KT`] up, toward 0° below it, through a [`PROBE_TAU`] lag (modern-iaf/docs/cockpit.md §5.4).
pub fn probe_aoa(shown: f64, alpha_deg: f64, cas_kt: f64, dt: f64) -> f64 {
    let target = if cas_kt < PROBE_MIN_KT { 0.0 } else { alpha_deg };
    shown + (target - shown) * (1.0 - (-dt / PROBE_TAU).exp())
}

/// Standard atmosphere at `alt_m`: (ρ, static pressure, speed of sound).
fn atmosphere(alt_m: f64) -> (f64, f64, f64) {
    let a = air(alt_m as f32);
    (a.rho as f64, a.pressure as f64, a.sound as f64)
}

impl SixDof {
    /// Starts `jet` as the original's `Aircraft::start` does (`st`): on the ground with the gear down, brakes on,
    /// throttle 0; in the air at the start's speed, trimmed for level flight.
    pub fn start(params: Params, envelope: Envelope, jet: Jet, st: Start) -> SixDof {
        let fuel_kg = jet.fuel_lb * LB;
        let empty_kg = jet.airframe.mass - fuel_kg;
        let h = (st.velocity.x.hypot(st.velocity.y)).max(0.0);
        let heading = st.heading as f64;
        let pos = ned(st.position);
        let mut s = SixDof {
            params,
            envelope,
            jet,
            body: Body::new(pos, Vec3::ZERO, Quat::from_euler(0.0, 0.0, heading)),
            engine: Engine::default(),
            anchors: Anchors::default(),
            fcs: Fcs::default(),
            surfaces: Surfaces::default(),
            t: 0.0,
            controls: Controls { throttle: 0.0, ..Controls::default() },
            tanks: Tanks::new(jet.fuel_lb),
            stores_kg: 0.0,
            stores_cd: 0.0,
            stores_moment: 0.0,
            tank_moment: 0.0,
            stores_cd_asym: 0.0,
            roll_trim: 0.0,
            mpo: false,
            cat3: false,
            sb_switch: None,
            sb_cmd: 0.0,
            damage: 0,
            twin: false,
            empty_kg,
            ground_height: 0.0,
            gear_clearance: jet.gear.struts[0].pos.z as f32,
            wheel_height: None,
            engine_on: st.engine_on || st.airborne,
            start_seq: if st.engine_on || st.airborne { Sequence::running() } else { Sequence::default() },
            gear: 0.0,
            accel_g: Vec3::new(0.0, 0.0, -1.0),
            acc: Vec3::ZERO,
            on_ground: !st.airborne,
            crashed: None,
            landings: 0,
            hard_landings: 0,
            thrust_n: 0.0,
            fuel_flow: 0.0,
            unlimited_fuel: false,
            place_on_gear: !st.airborne,
            wind: Vec3::ZERO,
            ground_obstacle: false,
            ground_normal_z: 1.0,
            ground_flags: None,
            no_crashes: false,
            easy_landing: false,
            ap_landing: false,
            ap_flying: false,
            autopilot: F16Autopilot::default(),
            ap_panel: ApPanel::default(),
            ap_cmd: (0.0, 0.0),
            ap_speeds: None,
            aoa_ind: 0.0,
            tef: if st.airborne { 0.0 } else { jet.tef_deg },
            pivot: None,
            brake: if st.airborne { 0.0 } else { 1.0 },
            parking_brake: false,
            master_fuel: true,
            eng_feed: 1,
            fuel_qty_sel: 1,
            cat3_load: false,
            invulnerable: false,
            structure: Stress::None,
            g_stress: Stress::None,
            v_stress: Stress::None,
            over_g: 0,
            over_speed: 0,
            gear_overspeed: false,
            brakes: Brakes::default(),
        };
        s.fcs = Fcs::new(jet.g_limits, jet.roll.map(|r| (r, jet.airframe.b))).with_alpha_max(jet.alpha_max);
        if st.airborne {
            s.controls = Controls { throttle: MILITARY, gear_down: false, ..Controls::default() };
            s.gear = GEAR_UP;
            s.trim_level(h.max(60.0), st.roll as f64, heading);
            s.aoa_ind = s.body.alpha().to_degrees();
        } else {
            s.controls = Controls { throttle: 0.0, gear_down: true, brakes: true, flaps: 1.0, ..Controls::default() };
        }
        s
    }

    /// The airframe at the flight's mass: the jet's, scaled by mass (fuel and stores at the c.g., inferred), with the
    /// rotors' momentum.
    fn airframe(&self) -> super::body::Airframe {
        let mut a = self.jet.airframe(&self.engine);
        let k = self.mass() / a.mass;
        (a.mass, a.ix, a.iy, a.iz, a.ixz) = (a.mass * k, a.ix * k, a.iy * k, a.iz * k, a.ixz * k);
        a
    }

    pub fn mass(&self) -> f64 {
        self.empty_kg + self.fuel_kg() + self.stores_kg
    }

    /// Level flight at `v` (m/s) here, wings banked `roll` (rad, the start's), heading `heading`: α and the
    /// stabilator from the 1 g force and moment balance, the engine's power from the x force (a few Newton steps;
    /// the control system then holds it).
    fn trim_level(&mut self, v: f64, roll: f64, heading: f64) {
        let alt = -self.body.pos.z;
        let (_, ps, sound) = atmosphere(alt);
        let af = self.airframe();
        let t = level_trim(&self.jet, &af, alt, v, self.stores_cd);
        let ar = t.alpha.to_radians();
        self.body.att = Quat::from_euler(roll, ar, heading);
        self.body.vel = Vec3::new(v * ar.cos(), 0.0, v * ar.sin());
        // The engine's power whose thrust balances the drag.
        let (mut lo, mut hi) = (0.0, 100.0);
        for _ in 0..40 {
            let mid = 0.5 * (lo + hi);
            let thrust = Engine { power: mid }.thrust(&self.jet.engine, v / sound, alt) * self.jet.engines as f64;
            if thrust < t.thrust_needed { lo = mid } else { hi = mid }
        }
        self.engine.power = 0.5 * (lo + hi);
        self.controls.throttle = travel_to_lever(super::engine::travel_for(self.engine.power));
        self.fcs.settle(t.alpha, t.dh, t.qbar, ps);
    }

    pub fn controls(&self) -> Controls {
        self.controls
    }

    pub fn set_controls(&mut self, c: Controls) {
        self.controls = c;
    }

    /// The stick as the flight model holds it.
    pub fn stick(&self) -> (f32, f32) {
        (self.controls.stick_x, self.controls.stick_y)
    }

    /// The drawn model's wheels: their tyres' bottoms `metres` below the c.g. (the model's `height` helper). The gear
    /// stands there at the flight's weight on level ground (`gear.rs` `Gear::set_static_height`), so the tyres drawn
    /// touch the ground as the struts carry the jet.
    /// Set again each frame at the flight's weight (fuel burnt, stores gone), so the tyres stay on the ground.
    pub fn set_wheel_height(&mut self, metres: f32) {
        if metres > 0.0 {
            self.wheel_height = Some(metres as f64);
            self.jet.gear.set_static_height(metres as f64, self.mass() * G);
            self.gear_clearance = metres;
        }
    }

    /// The ground's slope under the jet (ENU): its height's rise per metre east and per metre north. Each wheel then
    /// meets the ground under itself (`gear.rs` `Gear::ground_slope`).
    pub fn set_ground_slope(&mut self, east: f32, north: f32) {
        self.jet.gear.ground_slope = [-north as f64, -east as f64];
    }

    /// The terrain height under the jet where it is now (ENU z; `gear.rs` `Gear::ground_at`). The first one after a
    /// ground start sets the jet on its gear, the struts at their static sag.
    pub fn set_ground_height(&mut self, h: f32) {
        self.ground_height = h;
        self.jet.gear.ground_at = [self.body.pos.x, self.body.pos.y];
        if self.place_on_gear && h > -1.0e8 {
            self.place_on_gear = false;
            // At the drawn wheels' height once the game gave it, else the struts' extended length less the sag.
            let up = self.wheel_height.unwrap_or(self.jet.gear.struts[0].pos.z - 0.15);
            self.body.pos.z = -(h as f64 + up);
        }
    }

    /// The engine on or off at once (the original's meaning: any throttle command starts it, the ejection stops it),
    /// the electrical power unchanged. Modern IAF's start goes through [`SixDof::start_engine`] instead.
    pub fn set_engine_on(&mut self, on: bool) {
        // An empty tank starts nothing (the throttle keys would light it again every press).
        let on = on && self.fuel_feeds();
        self.engine_on = on;
        if on {
            self.start_seq = Sequence::running();
        }
    }

    /// The "start engine" command: a cold engine runs its jet's start sequence ([`super::start`]); it runs (gives
    /// thrust) once the sequence reaches idle.
    pub fn start_engine(&mut self) {
        // The command flies the whole checklist: the fuel to the engine first.
        self.master_fuel = true;
        self.eng_feed = self.eng_feed.max(1);
        if !self.engine_on {
            if self.start_seq.phase == Phase::Running {
                self.start_seq.shutdown(); // stopped since its last start: from the beginning
            }
            self.start_seq.begin(&self.jet.start);
        }
    }

    /// One start-up checklist step by its key ([`Sequence::press`]). "cutoff": the
    /// throttle to OFF, the fuel cut ([`Sequence::cut_off`]): the engine stops giving thrust and winds down.
    pub fn start_step(&mut self, step: &str) -> Result<(), &'static str> {
        if step == "cutoff" {
            if !self.engine_on && self.start_seq.phase == Phase::Running {
                return Ok(()); // stopped already (the ejection, `engine_off`): nothing to cut
            }
            let rpm = self.rpm() as f64;
            self.engine_on = false;
            return self.start_seq.cut_off(rpm);
        }
        if step == "engine" && !self.fuel_feeds() {
            return Err("no_fuel"); // MASTER FUEL or ENG FEED off, or an empty tank: nothing to light
        }
        self.start_seq.press(&self.jet.start, step)
    }

    /// A checklist switch set: `want` 1 on ([`SixDof::start_step`]), -1 off, 0 the other way from its position
    /// ([`Sequence::on`]); the INS knob turns a position ([`Sequence::turn_ins`]). Off is [`Sequence::release`]; the
    /// engine's ("engine": the F-16's throttle, the F-35I's ENG switch) is the fuel cut, "cutoff".
    pub fn start_switch(&mut self, step: &str, want: i8) -> Result<(), &'static str> {
        if step == "ins" {
            return self.start_seq.turn_ins(&self.jet.start, want); // the knob's six positions
        }
        if want > 0 || (want == 0 && !self.start_seq.on(step)) {
            return self.start_step(step);
        }
        if step == "engine" {
            return self.start_step("cutoff");
        }
        self.start_seq.release(step);
        Ok(())
    }

    /// The position of checklist step `step`'s switch ([`Sequence::on`]).
    pub fn start_on(&self, step: &str) -> bool {
        self.start_seq.on(step)
    }

    /// The position of a switch of three positions ([`Sequence::position`]: MAIN PWR, the JFS, RDR ALT).
    pub fn start_position(&self, step: &str) -> i8 {
        self.start_seq.position(step)
    }

    /// The INS knob's position ([`Sequence::ins_knob`]: 0 OFF .. 5 ATT, `start::INS_KNOB`).
    pub fn ins_knob(&self) -> u8 {
        self.start_seq.ins_knob()
    }

    /// The INS alignment: seconds run, its length, done ([`Sequence::ins_status`]).
    pub fn ins_status(&self) -> (f64, f64, bool) {
        self.start_seq.ins_status(&self.jet.start)
    }

    /// The electrical power: 0 none, 1 the battery, 2 the displays up ([`Sequence::power`]).
    pub fn power(&self) -> u8 {
        self.start_seq.power(&self.jet.start)
    }

    /// System `name` up (the F-16's per-system power switches, [`Sequence::system`]).
    pub fn system(&self, name: &str) -> bool {
        self.start_seq.system(&self.jet.start, name)
    }

    /// The avionics up ([`Sequence::avionics`]).
    pub fn avionics(&self) -> bool {
        self.start_seq.avionics(&self.jet.start)
    }

    /// The start sequence's step ("off", "starter", "crank", "light-off", "accel", "running").
    pub fn start_phase(&self) -> &'static str {
        self.start_seq.phase.name()
    }

    /// Motion 0x18, as `Aircraft::set_fuel`: the fuel and its maximum := `kg` (the tank jettison).
    pub fn set_fuel(&mut self, kg: f32) {
        if kg >= 0.0 {
            let lb = kg as f64 / LB;
            self.tanks.set(lb - self.tanks.internal(), lb);
        }
    }

    /// External tanks at the start, as `Aircraft::set_fuel_capacity` (FUN_005a8980 then the start's fill): the
    /// maximum = the internal fuel + `extra_kg`, filled.
    pub fn set_fuel_capacity(&mut self, extra_kg: f32) {
        let ext = extra_kg.max(0.0) as f64 / LB;
        self.tanks.set(ext, self.tanks.internal() + ext);
    }

    /// The mission's wind: `knots` from `from_deg` (true), as the original's (`aircraft::wind`).
    pub fn set_wind(&mut self, knots: f32, from_deg: f32) {
        self.wind = ned(crate::aircraft::wind(knots, from_deg));
    }

    /// The terrain under the jet: the normal's vertical share and the terraintype.dat flags.
    pub fn set_ground_surface(&mut self, normal_z: f32, flags: u32) {
        self.ground_normal_z = normal_z;
        self.ground_flags = Some(flags);
    }

    /// The external stores: their mass (kg) and the left / right drag index (×1e-4 applied: ΔCD), as the game
    /// gives the original.
    pub fn set_stores(&mut self, mass_kg: f32, di_left: f32, di_right: f32) {
        self.stores_kg = mass_kg.max(0.0) as f64;
        self.stores_cd = (di_left + di_right).max(0.0) as f64;
        self.stores_cd_asym = (di_right - di_left) as f64;
    }

    /// The stores' lateral moment (kg·m, + right wing heavier), as the game gives the original (`stores.rs`
    /// `roll_moment`): in flight it rolls the jet with its weight × the load factor, and the control system meets it.
    pub fn set_stores_moment(&mut self, kg_m: f32, tanks_kg_m: f32) {
        (self.stores_moment, self.tank_moment) = (kg_m as f64, tanks_kg_m as f64);
    }

    /// The roll trim moved by a rocker −1..1 held `dt` s, as the original's (`aircraft::step_roll_trim`). Every 6-DoF
    /// jet flies TP-1538's F-16 control law, so the F-16's authority (type 100: ±66.8 of 308 deg/s, fig. 64) for all.
    pub fn trim_roll(&mut self, rocker: f32, dt: f32) {
        self.roll_trim = crate::aircraft::step_roll_trim(self.roll_trim as f32, rocker, dt, 100) as f64;
    }

    /// The pilot's systems damage (docs/damage.md §5.2), read as the original reads it (`Aircraft::set_damage`): the
    /// engines and afterburners (`damage_bits`), the fuel leak, the hydraulics and the flight controls (the stick).
    pub fn set_damage(&mut self, flags: u32, twin: bool) {
        (self.damage, self.twin) = (flags, twin);
    }

    /// The roll trim, stick units.
    pub fn roll_trim(&self) -> f32 {
        self.roll_trim as f32
    }

    pub fn internal_fuel_kg(&self) -> f32 {
        (self.jet.fuel_lb * LB) as f32
    }

    pub fn fuel_capacity_kg(&self) -> f32 {
        (self.tanks.capacity() * LB) as f32
    }

    fn fuel_kg(&self) -> f64 {
        self.tanks.total() * LB
    }

    /// The tanks (lb).
    pub fn tanks(&self) -> &Tanks {
        &self.tanks
    }

    /// The fuel quantity indicator at the FUEL QTY SEL knob: [the FR pointer, the AL pointer, the totalizer], lb.
    pub fn fuel_gauge(&self) -> [f64; 3] {
        self.tanks.gauge(self.fuel_qty_sel)
    }

    /// The [AFT, FWD] FUEL LOW caution lights ([`Tanks::low`]).
    pub fn fuel_low(&self) -> [bool; 2] {
        self.tanks.low(self.fuel_qty_sel)
    }

    /// Fuel reaches the engine: fuel aboard (or unlimited) and MASTER FUEL at MASTER (flight manual page 1-72). ENG
    /// FEED at OFF stops the electric pumps only: the fuel flow proportioner still feeds the engine (figure 1-23).
    pub fn fuel_feeds(&self) -> bool {
        (self.tanks.total() > 0.0 || self.unlimited_fuel) && self.master_fuel
    }

    /// A fuel or brake switch set (modern-iaf/docs/cockpit.md §5.7): "parking_brake" 0 off (ANTI-SKID), 1 set;
    /// "master_fuel" 0 OFF, 1 MASTER; "eng_feed" `ENG_FEED`'s index; "fuel_qty_sel" `FUEL_QTY_SEL`'s. `pos` -1: the next position, the last going
    /// round to the first; out of range: clamped. False for another name. Fuel cut off flames the engine out at the
    /// next step ([`SixDof::step`]).
    pub fn set_switch(&mut self, name: &str, pos: i8) -> bool {
        let n = match name {
            "eng_feed" => ENG_FEED.len(),
            "fuel_qty_sel" => FUEL_QTY_SEL.len(),
            _ => 2,
        } as i8;
        let to = |now: i8| if pos < 0 { (now + 1) % n } else { pos.min(n - 1) };
        match name {
            "parking_brake" => self.parking_brake = to(i8::from(self.parking_brake)) == 1,
            "master_fuel" => self.master_fuel = to(i8::from(self.master_fuel)) == 1,
            "eng_feed" => self.eng_feed = to(self.eng_feed as i8) as u8,
            "fuel_qty_sel" => self.fuel_qty_sel = to(self.fuel_qty_sel as i8) as u8,
            _ => return false,
        }
        true
    }

    /// A fuel or brake switch's position ([`SixDof::set_switch`]'s values), -1 for another name.
    pub fn switch(&self, name: &str) -> i8 {
        match name {
            "parking_brake" => i8::from(self.parking_brake),
            "master_fuel" => i8::from(self.master_fuel),
            "eng_feed" => self.eng_feed as i8,
            "fuel_qty_sel" => self.fuel_qty_sel as i8,
            _ => -1,
        }
    }

    pub fn engine_off(&mut self) {
        self.engine_on = false;
    }

    /// Re-placed at rest on the ground at (x, y) ENU facing `heading` (the autopilot's taxi re-placement).
    pub fn replace_on_ground(&mut self, x: f64, y: f64, heading: f32) {
        let z = self.body.pos.z;
        self.body = Body::new(Vec3::new(y, x, z), Vec3::ZERO, Quat::from_euler(0.0, 0.0, heading as f64));
        // The ground height in hand is taken as the new spot's until the next reading.
        self.jet.gear.ground_at = [y, x];
        self.anchors = Anchors::default();
        self.controls.throttle = 0.0;
    }

    /// Advances `dt` s: frames cut to 0.25 s and stepped at most 1/120 s, as the rigid body; a frame time that is
    /// not a positive number changes nothing. Nothing moves after a crash.
    pub fn step(&mut self, dt: f64) {
        if dt.is_nan() || dt <= 0.0 || self.crashed.is_some() {
            return;
        }
        let dt = dt.min(MAX_FRAME);
        let n = (dt / MAX_STEP).ceil().max(1.0);
        // The mass, the c.g. and the rotors' momentum change slowly: once per frame; the drawn wheels' height at that
        // weight.
        self.jet.airframe.xcg = self.xcg();
        let af = self.airframe();
        if let Some(h) = self.wheel_height {
            self.jet.gear.set_static_height(h, self.mass() * G);
        }
        // No fuel to the engine (an empty tank, MASTER FUEL or ENG FEED off): the engine flames out, lit or running,
        // and winds down with its generators (a stopped one, `engine_off`, has nothing to lose).
        let lit = self.engine_on || self.start_seq.phase != Phase::Running;
        if !self.fuel_feeds() && lit && self.start_seq.flame_out(self.rpm() as f64) {
            self.engine_on = false;
        }
        if self.start_seq.step(&self.jet.start, dt) {
            self.engine_on = true; // the sequence reached idle
        }
        let sensed = self.ap_sensed();
        self.ap_cmd = self.autopilot.step(&sensed, &self.ap_panel, dt);
        for _ in 0..n as usize {
            self.substep(dt / n, &af);
            if self.crashed.is_some() {
                break;
            }
        }
        let b = self.body;
        let flow = Flow::from_body(&Body { vel: b.vel - b.att.rotate_inv(self.wind), ..b });
        let (rho, _, _) = atmosphere(-b.pos.z);
        let cas_kt = flow.v * (rho / 1.225).sqrt() * 1.943844;
        self.aoa_ind = probe_aoa(self.aoa_ind, flow.alpha, cas_kt, dt);
        if !self.ap_flying {
            self.ap_speeds = None;
        } else if self.ap_speeds.is_none() || (2.0 * self.t).floor() != (2.0 * (self.t - dt)).floor() {
            let jet = self.jet.at_weight(self.mass() / LB);
            let level = |alpha: f32| approach_speed(&jet, -b.pos.z, alpha as f64, 0.0, self.tef, self.surfaces.dsb).0;
            let (limiter, turn) = crate::autopilot::REAL_CIRCUIT;
            let (alpha, glide) = crate::autopilot::REAL_FINAL;
            let dsb = self.jet.speed_brake.gear_down_deg;
            let fin = approach_speed(&jet, -b.pos.z, alpha as f64, glide as f64, self.jet.tef_deg, dsb).0;
            self.ap_speeds = Some((level(limiter) as f32, level(turn) as f32, fin as f32));
        }
    }

    /// What the F-16's autopilot senses ([`Sensed`]): the attitude, the air data, the stick and the switches that
    /// hold it off; its data good with power, the INS aligned and no autopilot damage (flag 6).
    pub fn ap_sensed(&self) -> Sensed {
        let b = self.body;
        let (roll, pitch, heading) = b.att.euler();
        let flow = Flow::from_body(&Body { vel: b.vel - b.att.rotate_inv(self.wind), ..b });
        let (rho, _, _) = atmosphere(-b.pos.z);
        let c = &self.controls;
        Sensed {
            pitch: pitch.to_degrees(),
            roll: roll.to_degrees(),
            heading: heading.to_degrees().rem_euclid(360.0),
            alt: -b.pos.z,
            vs: -b.att.rotate(b.vel).z,
            speed: flow.v,
            cas_kt: flow.v * (rho / 1.225).sqrt() * 1.943844,
            alpha: flow.alpha,
            stick: (c.stick_x as f64, c.stick_y as f64),
            gear_handle_down: c.gear_down,
            alt_flaps: c.flaps > 0.0,
            mpo: self.mpo,
            data_ok: self.power() >= 1 && self.ins_status().2 && self.damage & (1 << 6) == 0,
            other_ap: self.ap_flying,
        }
    }

    /// The F-16 autopilot's PITCH (`axis` 0) or ROLL (1) switch moved to `pos` ([`F16Autopilot::set_pitch`]): Err with
    /// the reason when the PITCH switch will not stay out of A/P OFF.
    pub fn ap_switch(&mut self, axis: u8, pos: i8) -> Result<(), &'static str> {
        let s = self.ap_sensed();
        if axis == 0 {
            self.autopilot.set_pitch(pos, &s, &self.ap_panel)
        } else {
            self.autopilot.set_roll(pos, &s);
            Ok(())
        }
    }

    /// The FLCS RESET switch ([`F16Autopilot::reset`]).
    pub fn flcs_reset(&mut self) {
        let s = self.ap_sensed();
        self.autopilot.reset(&s);
    }

    /// The indicated AoA, deg ([`probe_aoa`]).
    pub fn indicated_aoa(&self) -> f64 {
        self.aoa_ind
    }

    fn substep(&mut self, dt: f64, af: &super::body::Airframe) {
        let c = self.controls;
        self.t += dt;
        // The parking brake holds them on as the pedals do (flight manual pages 1-116, 1-117).
        let target = if (c.brakes || self.parking_brake) && self.on_ground { 1.0 } else { 0.0 };
        self.brake += (target - self.brake).clamp(-dt / BRAKE_RAMP_S, dt / BRAKE_RAMP_S);
        // Gear lever ramp; gear damage (7) holds the gear where it is, as the game's legs (docs/damage.md §5.2).
        if self.damage & (1 << 7) == 0 {
            let target = if c.gear_down { 0.0 } else { GEAR_UP };
            self.gear += (target - self.gear).clamp(-GEAR_RATE * dt as f32, GEAR_RATE * dt as f32);
        }
        let gear_down = self.gear < GEAR_UP;
        let ground_z = -self.ground_height as f64;
        let b = self.body;
        let alt = -b.pos.z;
        let (rho, ps, sound) = atmosphere(alt);
        // The mission's wind with its gusts in the air (crate::near_ground, reborn's Better physics `wind`).
        let air = if self.on_ground {
            self.wind
        } else {
            self.wind + ned(crate::near_ground::gust(enu(self.wind), self.t, (ground_z - b.pos.z) as f32))
        };
        let flow = Flow::from_body(&Body { vel: b.vel - b.att.rotate_inv(air), ..b });
        let qbar = 0.5 * rho * flow.v * flow.v;
        let (max_g, min_g) = self.jet.g_limits;
        // The systems damage as the original reads it: the stick's share (hydraulics, flight controls; the rudder
        // keeps its authority), the engines and afterburners, the fuel leak.
        let stick_k = crate::aircraft::stick_authority(self.damage) as f64;
        let bits = crate::aircraft::damage_bits(self.damage, self.twin);
        let (stick_x, stick_y) = (c.stick_x as f64 * stick_k, c.stick_y as f64 * stick_k);
        // The speed brake: the jet's limit with the main gear down and locked (the ramp at 0). With the SPD BRK
        // switch the opening grows at the surface's own rate while the switch is held aft and stays where it is let
        // go; an autopilot loop keeps the brake control's speed brake in the air.
        let sb = self.jet.speed_brake;
        let gear_locked = self.gear <= 0.0;
        let speed_brake = match self.sb_switch {
            Some(sw) if !(self.ap_flying && c.brakes && !self.on_ground) => {
                self.sb_cmd = match sw {
                    1.. => self.sb_cmd + super::fcs::SB_RATE * dt,
                    0 => self.sb_cmd,
                    _ => 0.0,
                }
                .min(sb.command(true, gear_locked));
                self.sb_cmd
            }
            _ => sb.command(c.brakes && !self.on_ground, gear_locked),
        };
        let pilot = Pilot {
            stick_x,
            stick_y,
            pedal: c.rudder as f64,
            speed_brake,
            // The autopilot's stick is linear in g (its ApView: centre 1 g, full stick MaxG / MinG) and in roll rate
            // (full stick the flight data's MaxRollRate, the original's roll channel `p_cmd`).
            // The trim left out while an autopilot loop flies, as the original's (`Aircraft::roll_stick`).
            roll_trim: if self.ap_flying { 0.0 } else { self.roll_trim * stick_k },
            mpo: self.mpo,
            cat3: self.cat3,
            ap_g: self.ap_cmd.0,
            ap_p: self.ap_cmd.1,
            g_command: self.ap_flying.then_some(if stick_y >= 0.0 {
                1.0 + stick_y * (max_g - 1.0)
            } else {
                1.0 - stick_y * (min_g - 1.0)
            }),
            // None on the wheels, as the original's roll channel (`p_cmd` 0 on the ground).
            roll_rate_command: (self.ap_flying && !self.on_ground)
                .then_some(stick_x * (self.params.max_roll_rate as f64).to_degrees()),
        };
        let sensors = Sensors {
            alpha: flow.alpha,
            p: flow.p.to_degrees(),
            q: flow.q.to_degrees(),
            r: flow.r.to_degrees(),
            an: -self.accel_g.z,
            ay: self.accel_g.y,
            qbar,
            ps,
            on_ground: self.on_ground,
            tas: flow.v,
            weight_lb: self.mass() / LB,
        };
        // Total flight-control damage (24): the control system no longer moves the surfaces; they stay where they were
        // (inferred; the original forces a spin, which a 6-DoF has to fly into).
        if self.damage & (1 << 24) == 0 {
            self.surfaces = self.fcs.step(&pilot, &sensors, dt);
        }
        let tef_cmd = jets::tef_schedule(c.gear_down, (2.0 * qbar / 1.225).sqrt() * 1.943844, self.jet.tef_deg);
        self.tef += (tef_cmd - self.tef).clamp(-TEF_RATE * dt, TEF_RATE * dt);
        self.surfaces.dtef = self.tef;
        // Both engines dead (a single-engine jet: its one) stop it like an empty tank; both afterburners dead stop the
        // throttle at military (as `Aircraft::thrust_at`).
        let fuel_left = self.fuel_feeds() && bits & 0xc != 0xc;
        let throttle = if bits & 0x180 == 0x180 { c.throttle.min(MILITARY) } else { c.throttle };
        let travel = if self.engine_on && fuel_left { lever_to_travel(throttle) } else { 0.0 };
        if self.engine_on && fuel_left {
            self.engine.step(&self.jet.engine, travel, dt);
        } else {
            // A stopped engine winds down to idle power and then gives no thrust (inferred).
            self.engine.step(&self.jet.engine, 0.0, dt);
        }
        let jc = jets::Controls {
            surfaces: self.surfaces,
            throttle: travel,
            wheels: self.wheels(&c),
            gear_down,
            stores_cd: self.stores_cd + if self.structure >= Stress::Damage { DAMAGED_DI } else { 0.0 },
            stores_roll: (self.stores_moment
                + self.tank_moment
                    * crate::aircraft::tank_share(
                        self.fuel_kg() as f32,
                        (self.tanks.internal() * LB) as f32,
                        (self.tanks.capacity() * LB) as f32,
                    ) as f64)
                * G
                * -self.accel_g.z,
            stores_cd_asym: self.stores_cd_asym,
            engine_on: self.engine_on && fuel_left,
            // One engine of a twin dead: half the thrust.
            thrust_k: if bits & 0xc != 0 { 0.5 } else { 1.0 },
            wind: air,
            // From the CAT III line at the jet's load factor (it rises with g, figure 1-44).
            cat3_alpha: (self.cat3_load && self.jet.limits.categories)
                .then(|| super::fcs::cat3_alpha_limit(self.mass() / LB, (-self.accel_g.z).max(1.0))),
        };
        let running = jc.engine_on;
        let (jet, engine, anchors) = (&self.jet, self.engine, self.anchors);
        let forces = |s: &Body| {
            let (f, m, _) = jet.forces(s, &jc, &engine, ground_z, &anchors);
            (f, m)
        };
        let v0 = self.body.att.rotate(self.body.vel);
        self.body.rk4(af, dt, &mut { forces });
        let (f, _, _) = jet.forces(&self.body, &jc, &engine, ground_z, &self.anchors);
        self.accel_g = f * (1.0 / (af.mass * G));
        self.acc = enu((self.body.att.rotate(self.body.vel) - v0) * (1.0 / dt));
        if gear_down {
            self.jet.update_gear(&self.body, &jc, ground_z, &mut self.anchors);
        }
        let was_on_ground = self.on_ground;
        // Weight on wheels from the struts' compression, not their load: the damper takes the load off an extending
        // strut before its wheel leaves the runway.
        self.on_ground = gear_down && self.jet.gear.on_ground(&self.body, ground_z);
        // Fuel.
        let thrust = if running { engine.thrust(&self.jet.engine, flow.v / sound, alt) } else { 0.0 };
        self.thrust_n = thrust * self.jet.engines as f64 * jc.thrust_k;
        let ff = if running { engine.fuel_flow(&self.jet.engine, thrust, alt) * self.jet.engines as f64 } else { 0.0 };
        // The fuel leak (damage 10): a quarter of the full-throttle flow on top, engine running or not (the
        // original's rule on the type's FuelFlowAtMaxThrust).
        let ff = ff * jc.thrust_k + if bits & 0x40 != 0 { 0.25 * self.params.fuel_flow_max as f64 } else { 0.0 };
        self.fuel_flow = ff as f32;
        if !self.unlimited_fuel {
            self.tanks.feed(ff * dt / LB, dt / 3600.0, self.eng_feed, self.fuel_qty_sel == 1);
        }
        self.check_ground(was_on_ground, gear_down, ground_z);
        let cas_kt = crate::atmosphere::cas(flow.v as f32, alt as f32) as f64 * 1.943844;
        self.check_limits(was_on_ground, cas_kt, flow.v / sound, ground_z, dt);
    }

    /// The c.g., fraction of the chord ([`limits::xcg`]).
    pub fn xcg(&self) -> f64 {
        let a = &self.jet.airframe;
        limits::xcg(&self.tanks, self.mass(), a.cbar, a.xcg_ref)
    }

    /// After a step at `cas_kt` and `mach`: the airframe's g and speed, the gear's speed, the tyres' ground speed and
    /// the brakes' heat against the jet's limits ([`limits`]). The airframe is checked in the air only: a touchdown's
    /// loads are the landing limits' ([`SixDof::check_ground`]).
    fn check_limits(&mut self, was_on_ground: bool, cas_kt: f64, mach: f64, ground_z: f64, dt: f64) {
        let l = self.jet.limits;
        if self.invulnerable {
            return;
        }
        if !self.on_ground && !was_on_ground {
            let rolling = self.body.omega.x.to_degrees().abs() > limits::ROLLING_DEG_S;
            let k = if self.cat3_load && l.categories && rolling { limits::CAT3_ROLLING } else { 1.0 };
            let weak = self.structure >= Stress::Damage;
            let g = limits::g_stress(-self.accel_g.z, self.jet.g_limits, k, weak);
            let v = limits::speed_stress(cas_kt, mach, &l);
            self.over_g += u32::from(g >= Stress::Over && self.g_stress < Stress::Over);
            self.over_speed += u32::from(v >= Stress::Over && self.v_stress < Stress::Over);
            (self.g_stress, self.v_stress) = (g, v);
            let worst = if g > v { g } else { v };
            if worst > self.structure {
                self.structure = worst;
            }
            if worst == Stress::Failure && !self.no_crashes {
                self.crashed = Some(Crash::Structure);
            }
        }
        // The gear down or moving (its doors open) past its speed.
        self.gear_overspeed |= self.gear < GEAR_UP && limits::gear_over(cas_kt, mach, &l);
        // The main tyres on the runway past their ground speed burst; the brakes take up their braking's power.
        let b = &self.body;
        let gs = b.att.rotate(b.vel);
        let gs = gs.x.hypot(gs.y);
        let loads = if self.gear < GEAR_UP { self.jet.gear_loads(b, ground_z) } else { [0.0; 3] };
        let mut watts = 0.0;
        let brake = self.wheels(&self.controls).brake;
        for (n, &load) in loads.iter().enumerate().skip(1) {
            if load > 0.0 && gs * 1.943844 > l.tyre_kt {
                self.jet.gear.burst[n] = true;
            }
            if !self.jet.gear.burst[n] {
                watts += super::gear::TYRES.braking * brake * load * gs;
            }
        }
        self.brakes.step(watts, dt);
    }

    /// The jet's gear speed limit from its aircraft definition's `gear_limit`: calibrated airspeed kt and Mach.
    pub fn set_gear_limit(&mut self, kcas: f64, mach: f64) {
        self.jet.limits.gear = (kcas, mach);
    }

    /// What the limits have done so far.
    pub fn limits(&self) -> LimitsState {
        let x = self.xcg();
        LimitsState {
            structure: self.structure as u8,
            over_g: self.over_g,
            over_speed: self.over_speed,
            gear_overspeed: self.gear_overspeed,
            tyres_burst: self.jet.gear.burst.iter().filter(|&&b| b).count() as u32,
            brakes_left: self.brakes.left(self.brake_limit()),
            xcg: x,
            cg_aft: x > limits::XCG_AFT,
        }
    }

    /// The brakes' energy limit, J, at 1.4 × the jet's reference weight (inferred: a heavy landing weight with stores
    /// aboard; [`limits::brake_limit`]).
    fn brake_limit(&self) -> f64 {
        limits::brake_limit(&self.jet.limits, 1.4 * (self.empty_kg + self.jet.fuel_lb * LB))
    }

    /// Touchdowns and crashes: a gear-down touchdown inside the landing limits counts as a landing; outside them,
    /// with the gear up, or the c.g. reaching the runway, it is a crash. The limits are the original model's real set
    /// ([`crate::aircraft::landing_limits`], Better physics `landing_limits`: sink 4 m/s, tail strike 15°, nose-down 5°,
    /// roll 10°, slope 10°; modern-iaf/docs/flight-model.md §9.12).
    fn check_ground(&mut self, was_on_ground: bool, gear_down: bool, ground_z: f64) {
        let b = &self.body;
        let height = ground_z - b.pos.z;
        let (roll, pitch, _) = b.att.euler();
        let v = b.att.rotate(b.vel);
        let sink = v.z;
        let flags = self.ground_flags.unwrap_or(0);
        let touched = self.on_ground || height < self.jet.gear.struts[0].pos.z;
        let crash = if height < 0.5 || (!gear_down && height < self.jet.gear.struts[0].pos.z - 0.3) {
            Some(Crash::Landing)
        } else if self.ground_obstacle && touched {
            // Scenery under the jet (a roof, a tree top) met at any speed (as the original's).
            Some(Crash::Scenery)
        } else if self.on_ground && flags & crate::aircraft::SURFACE_WATER != 0 {
            Some(Crash::Water)
        } else if self.on_ground && flags & crate::aircraft::SURFACE_ROUGH != 0 && v.x.hypot(v.y) > 25.736 {
            // Rough ground above 25.7 m/s (the original's limit).
            Some(Crash::RoughGround)
        } else if self.on_ground && !was_on_ground {
            let gear_moving = self.gear.abs() >= 1e-5;
            let real = !self.ap_landing;
            let crash = crate::aircraft::landing_limits(
                pitch as f32,
                roll as f32,
                -sink as f32,
                self.ground_normal_z,
                gear_moving,
                self.easy_landing,
                real,
            );
            if crash.is_none() && self.t > 1.0 {
                self.landings += 1;
                if crate::aircraft::hard_landing(-sink as f32, self.easy_landing, real) {
                    self.hard_landings += 1;
                }
            }
            crash
        } else {
            None
        };
        if !self.no_crashes {
            self.crashed = crash;
        }
    }

    /// The state in the game's frame.
    pub fn state(&self) -> State {
        let b = &self.body;
        let (roll, pitch, heading) = b.att.euler();
        let v = enu(b.att.rotate(b.vel));
        let alt = -b.pos.z;
        let (_, _, sound) = atmosphere(alt);
        let alpha = b.alpha();
        let power = self.engine.power;
        let g = -self.accel_g.z;
        let (max_g, _) = self.jet.g_limits;
        // The jet's α limit less the F-16's (the F-35I's 50°: the warning and the deep-stall flag move with it).
        let sh = self.jet.alpha_max - super::fcs::F16_ALPHA_MAX;
        let stalled = !self.on_ground && !(-5.0..=29.0 + sh).contains(&alpha.to_degrees());
        State {
            time: self.t,
            position: enu(b.pos),
            velocity: [v.x as f32, v.y as f32, v.z as f32],
            speed: b.speed() as f32,
            mach: (b.speed() / sound) as f32,
            forward: enu(b.att.rotate(Vec3::new(1.0, 0.0, 0.0))),
            right: enu(b.att.rotate(Vec3::new(0.0, 1.0, 0.0))),
            up: enu(b.att.rotate(Vec3::new(0.0, 0.0, -1.0))),
            pitch: pitch as f32,
            roll: roll as f32,
            heading: heading.rem_euclid(std::f64::consts::TAU) as f32,
            alpha: alpha as f32,
            beta: b.beta() as f32,
            g: g as f32,
            rpm: self.rpm(),
            throttle: self.controls.throttle,
            afterburner: if power > 75.0 {
                2
            } else if power > 50.0 {
                1
            } else {
                0
            },
            thrust_n: self.thrust_n as f32,
            fuel_kg: self.fuel_kg() as f32,
            mass_kg: self.mass() as f32,
            // Out of the control system's range (T.O. 1F-16A-1: recovery is "AOA within −5 to +25 degrees"; above
            // 29° its limiters give way to the yaw-rate limiter): stalled above 29° or below −5° in the air.
            stalled,
            buffet: alpha.to_degrees() > 15.0 && !self.on_ground,
            // The AoA warning measure: 0 below the 25° limiter, rising to the original's 1.2 at 30° (inferred).
            drag_x: ((alpha.to_degrees() - 25.0 - sh) / 5.0 * 1.2).clamp(0.0, 1.2) as f32,
            over_g: g > max_g,
            on_ground: self.on_ground,
            // A spin: stalled and turning about the vertical faster than 35 deg/s (inferred: half the 70–100 deg/s the
            // manual gives an upright F-16 spin).
            spinning: stalled && b.att.rotate(b.omega).z.abs().to_degrees() > 35.0,
            deep_stall: alpha.to_degrees() > 45.0 + sh && !self.on_ground,
            tornado: false,
            end_worlds: 0,
            gear: self.gear,
            crashed: self.crashed,
            landings: self.landings,
            hard_landings: self.hard_landings,
        }
    }

    /// The engine's RPM, %: running, from its power; a start or a run-down in progress, the sequence's; a stopped
    /// engine (its sequence long done) none.
    fn rpm(&self) -> f32 {
        if self.engine_on {
            (60.0 + 40.0 * (self.engine.power / 50.0).min(1.0)) as f32
        } else if self.start_seq.phase == Phase::Running {
            0.0
        } else {
            self.start_seq.rpm as f32
        }
    }

    /// The autopilot's view (as `Aircraft::ap_view`): position, velocity, acceleration, the flight-path attitude
    /// (velocity direction and bank), its rates.
    pub fn ap_view(&self) -> ApView {
        let s = self.state();
        let v = Vec3::new(s.velocity[0] as f64, s.velocity[1] as f64, s.velocity[2] as f64);
        let a = self.acc;
        let h2 = v.x * v.x + v.y * v.y;
        let turn = if h2 > 1e-6 { (a.x * v.y - a.y * v.x) / h2 } else { 0.0 };
        let s2 = h2 + v.z * v.z;
        let path = if h2 > 1e-6 && s2 > 1e-6 { (a.z * s2 - v.z * v.dot(a)) / (s2 * h2.sqrt()) } else { 0.0 };
        let heading = if h2 > 0.25 { v.x.atan2(v.y) as f32 } else { s.heading };
        let gamma = if s2 > 0.25 { (v.z / s2.sqrt()).asin() as f32 } else { s.pitch };
        let p = &self.params;
        ApView {
            t: self.t,
            pos: s.position,
            vel: v,
            acc: a,
            speed: s.speed,
            att: Euler { pitch: gamma, roll: s.roll, heading },
            rates: [path as f32, self.body.omega.x as f32, turn as f32],
            max_roll_rate: p.max_roll_rate,
            max_g: self.jet.g_limits.0 as f32,
            min_g: self.jet.g_limits.1 as f32,
            on_ground: s.on_ground,
            gear_down: self.controls.gear_down,
            flaps: self.controls.flaps > 0.0,
            brakes: self.controls.brakes,
            type_code: p.type_code,
            gear_clearance: self.gear_clearance,
            ground_height: self.ground_height,
            gear_speed_wait: p.gear_speed_wait,
            stick_centre: [0.0, 0.0, 1.0],
            lift_factor: 1.0,
            final_speed: self.ap_speeds.filter(|_| self.controls.gear_down && !s.on_ground).map(|v| v.2),
            circuit: self.ap_speeds.filter(|_| !s.on_ground).map(|v| ((s.speed / v.0).powi(2), v.1)),
            sixdof: true,
        }
    }

    /// An autopilot loop starts or stops flying the jet (the autopilot's `stores_trim` hook): while it flies, the
    /// stick is a linear g and roll-rate command, as the autopilot reads [`SixDof::ap_view`].
    pub fn set_ap_flying(&mut self, on: bool) {
        self.ap_flying = on;
        if on {
            self.parking_brake = false; // the autopilot taxies: the pilot's hand releases it (inferred)
        }
    }

    /// The autopilot's taxi pivot turn (motion 0x16) to the heading `target` (rad), None to end it: the 6-DoF turns
    /// on its wheels ([`SixDof::wheels`]) where the original model flies a scripted 30 m arc
    /// (`Aircraft::set_pivot`).
    pub fn set_pivot(&mut self, target: Option<f32>) {
        self.pivot = target.map(|h| h as f64);
    }

    /// The wheels this frame: the pilot's brakes and nose-wheel steering (the rudder), or during a taxi pivot the
    /// autopilot's turn: the nose wheel steered toward the target heading on the original's 30 m turn radius, wider
    /// where the side grip cannot hold that radius at the speed (half of it used), and braked down to the speed
    /// that radius allows, straight: a braked main tyre keeps little side grip (the friction circle), and turning
    /// under full brakes ground-looped the jet backwards onto its tail (2026-11-16; all inferred).
    fn wheels(&self, c: &Controls) -> super::gear::Wheels {
        // The brakes' heat takes their braking away ([`limits::Brakes`]).
        let brake = self.brake * self.brakes.left(self.brake_limit());
        let steer = c.rudder as f64 * self.jet.nws_deg;
        let Some(target) = self.pivot.filter(|_| self.on_ground) else {
            let castor = c.rudder.abs() < NWS_ON_PEDAL && self.body.speed() >= NWS_TAXI_KT * 0.514444;
            return super::gear::Wheels { brake, steer, castor };
        };
        let s = &self.jet.gear.struts;
        let wheelbase = s[0].pos.x - s[1].pos.x;
        let v = self.body.speed();
        let grip = 0.5 * super::gear::TYRES.side * G;
        let radius = PIVOT_RADIUS.max(v * v / grip);
        let err = (target - self.body.att.euler().2 + std::f64::consts::PI).rem_euclid(std::f64::consts::TAU)
            - std::f64::consts::PI;
        let max = (wheelbase / radius).atan().to_degrees();
        let too_fast = v * v > grip * PIVOT_RADIUS;
        super::gear::Wheels {
            brake: if too_fast { 1.0 } else { brake },
            steer: if too_fast { 0.0 } else { (err.to_degrees() * 20.0).clamp(-max, max) },
            castor: false,
        }
    }

    /// Vmin(alt, g) of the loaded envelope (the autopilot's speeds).
    pub fn vmin(&self, alt: f32, g: f32) -> f32 {
        self.envelope.vmin(alt, g)
    }

    /// The control surfaces' positions (deg), for the part animation and the tests.
    pub fn surfaces(&self) -> Surfaces {
        self.surfaces
    }

    /// Puts the rigid body in state `b` (the tests' departures: in a zoom the control system keeps the jet out of a
    /// deep stall).
    pub fn set_body(&mut self, b: Body) {
        self.body = b;
    }

    pub fn body(&self) -> &Body {
        &self.body
    }
}

/// A level, wings-level trim: α and stabilator (deg), and the thrust it needs (N).
pub struct LevelTrim {
    pub alpha: f64,
    pub dh: f64,
    pub thrust_needed: f64,
    pub qbar: f64,
}

/// `jet` (as `af`) in level flight at `alt_m`, true speed `v`, with stores of drag index × 10⁻⁴ `stores_cd`: α and
/// the stabilator from the 1 g force and moment balance (Newton steps), the thrust from the x force; the flap on its
/// schedule.
pub fn level_trim(jet: &Jet, af: &super::body::Airframe, alt_m: f64, v: f64, stores_cd: f64) -> LevelTrim {
    let (rho, ps, sound) = atmosphere(alt_m);
    let qbar = 0.5 * rho * v * v;
    let w = af.mass * G;
    let mach = v / sound;
    let coeffs = |a: f64, dh: f64| {
        let s = Surfaces { dh, dlef: lef_schedule(a, qbar, ps), ..Surfaces::default() };
        let mut c = coefficients(&Flow { alpha: a, v, ..Flow::default() }, &s, af);
        compressibility(&mut c, mach, a, jet.aspect_ratio(), jet.wave_drag);
        add_drag(&mut c, jet.stores_dcd(stores_cd), a);
        c
    };
    let (mut a, mut dh) = (2.0, 0.0);
    for _ in 0..30 {
        let r = |a: f64, dh: f64| {
            let c = coeffs(a, dh);
            (qbar * af.s * c.cz + w * a.to_radians().cos(), c.cm)
        };
        let (f0, g0) = r(a, dh);
        let (fa, ga) = r(a + 1e-4, dh);
        let (fd, gd) = r(a, dh + 1e-4);
        let (j11, j12, j21, j22) = ((fa - f0) / 1e-4, (fd - f0) / 1e-4, (ga - g0) / 1e-4, (gd - g0) / 1e-4);
        let det = j11 * j22 - j12 * j21;
        if det.abs() < 1e-12 {
            break;
        }
        a = (a - (f0 * j22 - g0 * j12) / det).clamp(-5.0, 25.0);
        dh = (dh - (g0 * j11 - f0 * j21) / det).clamp(-25.0, 25.0);
    }
    let thrust_needed = w * a.to_radians().sin() - qbar * af.s * coeffs(a, dh).cx;
    LevelTrim { alpha: a, dh, thrust_needed, qbar }
}

/// The top level speed (m/s) of `jet` at its reference weight at `alt_m` with stores of drag index × 10⁻⁴
/// `stores_cd`, full afterburner: from 150 m/s up, the first speed where the maximum thrust no longer meets the level
/// drag (1 m/s steps).
pub fn top_speed(jet: &Jet, alt_m: f64, stores_cd: f64) -> f64 {
    let sound = atmosphere(alt_m).2;
    let max = |v: f64| Engine { power: 100.0 }.thrust(&jet.engine, v / sound, alt_m) * jet.engines as f64;
    let mut v = 150.0;
    while v < 900.0 && max(v) >= level_trim(jet, &jet.airframe, alt_m, v, stores_cd).thrust_needed {
        v += 1.0;
    }
    v
}

/// The 1 g stall speed (m/s, true = calibrated at sea level) of `jet` at its reference weight, clean, power off: the
/// slowest level flight its lift holds at any α up to the control system's limit (`Jet::alpha_max`) with the
/// stabilator trimming the pitching moment within its ±25° (α in 0.25° steps; the flap on its schedule).
pub fn stall_speed(jet: &Jet) -> f64 {
    let (rho, ps, _) = atmosphere(0.0);
    let af = &jet.airframe;
    let w = af.mass * G;
    let mut best = f64::INFINITY;
    for i in 0..=(jet.alpha_max * 4.0) as usize {
        let a = i as f64 * 0.25;
        let (mut v, mut dh, mut ok) = (100.0, 0.0, false);
        for _ in 0..30 {
            let qbar = 0.5 * rho * v * v;
            let c = |dh: f64| {
                let s = Surfaces { dh, dlef: lef_schedule(a, qbar, ps), ..Surfaces::default() };
                let mut c = coefficients(&Flow { alpha: a, v, ..Flow::default() }, &s, af);
                if let Some(n) = jet.nose_down {
                    c.cm += n.at(a);
                }
                c
            };
            let (c0, c1) = (c(dh), c(dh + 1e-3));
            dh -= c0.cm * 1e-3 / (c1.cm - c0.cm);
            let k = c(dh);
            let cl = k.cx * a.to_radians().sin() - k.cz * a.to_radians().cos();
            ok = cl > 0.0 && dh.abs() <= 25.0;
            if !ok {
                break;
            }
            v = (2.0 * w / (rho * af.s * cl)).sqrt();
        }
        if ok {
            best = best.min(v);
        }
    }
    best
}

/// The steady final of `jet` (at its weight) at `alt_m`: the true airspeed (m/s), the stabilator (deg) and the CL
/// that fly `alpha_deg` down a `glide_deg` path with the gear down (its drag 0.02, as figure 2-3's test), the flaps at
/// `dtef` and the speed brake at `dsb`, deg. The lift and the thrust's share balance the weight's: qS (CL + CD tan α)
/// = W (cos γ + sin γ tan α), the thrust being the drag less W sin γ.
pub fn approach_speed(jet: &Jet, alt_m: f64, alpha_deg: f64, glide_deg: f64, dtef: f64, dsb: f64) -> (f64, f64, f64) {
    let (rho, ps, _) = atmosphere(alt_m);
    let af = &jet.airframe;
    let w = af.mass * G;
    let (sg, cg) = glide_deg.to_radians().sin_cos();
    let (sa, ca) = alpha_deg.to_radians().sin_cos();
    let (mut v, mut dh, mut cl) = (70.0, 0.0, 0.0);
    for _ in 0..40 {
        let qbar = 0.5 * rho * v * v;
        let c = |dh: f64| {
            let s = Surfaces { dh, dlef: lef_schedule(alpha_deg, qbar, ps), dsb, dtef, ..Surfaces::default() };
            let mut c = coefficients(&Flow { alpha: alpha_deg, v, ..Flow::default() }, &s, af);
            add_drag(&mut c, 0.02, alpha_deg);
            c
        };
        let (c0, c1) = (c(dh), c(dh + 1e-3));
        dh -= c0.cm * 1e-3 / (c1.cm - c0.cm);
        let k = c(dh);
        cl = k.cx * sa - k.cz * ca;
        let cd = -k.cx * ca - k.cz * sa;
        v = (2.0 * w * (cg + sg * sa / ca) / (rho * af.s * (cl + cd * sa / ca))).sqrt();
    }
    (v, dh, cl)
}

/// Figure 66(b)'s travel → the game's throttle lever (the inverse of [`lever_to_travel`]).
fn travel_to_lever(travel: f64) -> f32 {
    let mil = MILITARY as f64;
    (if travel <= 0.77 { travel / 0.77 * mil } else { mil + (travel - 0.77) / 0.23 * (1.0 - mil) }) as f32
}

#[cfg(test)]
mod tests {
    use super::{SixDof, probe_aoa};
    use crate::aircraft::Crash;
    use crate::sixdof::{Quat, jets};
    use crate::{Envelope, Params, Start, Vec3};

    /// A touchdown on the 6-DoF meets the original model's real landing limits (`aircraft::landing_limits`): just
    /// inside and just outside each one, Easy landing ×2, the autopilot's landing the original's 40 m/s.
    #[test]
    fn touchdowns_meet_the_shared_landing_limits() {
        let ini = iaf_formats::ini::Ini::parse(b"[X]\nMaxRollRate=308\n");
        let params = Params::from_section(ini.section("X").unwrap());
        let st = Start {
            position: Vec3::new(0.0, 0.0, 100.0),
            pitch: 0.0,
            roll: 0.0,
            heading: 0.0,
            velocity: Vec3::new(0.0, 80.0, 0.0),
            airborne: true,
            engine_on: true,
        };
        let touch = |pitch: f64, roll: f64, sink: f64, tweak: &dyn Fn(&mut SixDof)| {
            let mut f = SixDof::start(params.clone(), Envelope::parse(b""), jets::all()[0], st);
            f.gear = 0.0;
            f.on_ground = true;
            f.body.pos = Vec3::new(0.0, 0.0, -(f.jet.gear.struts[0].pos.z - 0.1).max(0.6));
            f.body.att = Quat::from_euler(roll.to_radians(), pitch.to_radians(), 0.0);
            // Body velocity straight down the body z axis: at zero attitude that is the sink rate.
            f.body.vel = Vec3::new(0.0, 0.0, sink);
            tweak(&mut f);
            f.check_ground(false, true, 0.0);
            f.crashed
        };
        let none = &|_: &mut SixDof| {};
        assert_eq!(touch(5.0, 0.0, 3.9, none), None);
        assert_eq!(touch(0.0, 0.0, 4.1, none), Some(Crash::SinkRate));
        assert_eq!(touch(14.9, 0.0, 0.0, none), None);
        assert_eq!(touch(15.1, 0.0, 0.0, none), Some(Crash::TailStrike));
        assert_eq!(touch(-4.9, 0.0, 0.0, none), None);
        assert_eq!(touch(-5.1, 0.0, 0.0, none), Some(Crash::Landing));
        assert_eq!(touch(0.0, 9.9, 0.0, none), None);
        assert_eq!(touch(0.0, -10.1, 0.0, none), Some(Crash::Landing));
        assert_eq!(touch(0.0, 0.0, 0.0, &|f| f.ground_normal_z = 11f32.to_radians().cos()), Some(Crash::Landing));
        let easy = &|f: &mut SixDof| f.easy_landing = true;
        assert_eq!(touch(0.0, 19.9, 7.9, easy), None);
        assert_eq!(touch(0.0, 0.0, 8.1, easy), Some(Crash::SinkRate));
        assert_eq!(touch(0.0, 0.0, 10.0, &|f| f.ap_landing = true), None, "the autopilot: the original's limits");
        assert_eq!(touch(0.0, 0.0, 30.0, &|f| f.no_crashes = true), None);
    }

    fn airborne(jet: jets::Jet) -> SixDof {
        let ini = iaf_formats::ini::Ini::parse(b"[X]\nMaxRollRate=308\n");
        let st = Start {
            position: Vec3::new(0.0, 0.0, 1000.0),
            pitch: 0.0,
            roll: 0.0,
            heading: 0.0,
            velocity: Vec3::new(0.0, 120.0, 0.0),
            airborne: true,
            engine_on: true,
        };
        SixDof::start(Params::from_section(ini.section("X").unwrap()), Envelope::parse(b""), jet, st)
    }

    /// A touchdown inside the landing limits that sinks past the gear's design limit, 10 ft/s (3.05 m/s), counts as
    /// a hard landing (the game damages the gear, flag 7); just under it, a plain landing. Easy landing doubles it.
    #[test]
    fn a_hard_landing_past_10_ft_per_s_counts_for_the_gear() {
        let hard = |sink: f64, easy: bool| {
            let mut f = airborne(jets::all()[0]);
            f.t = 2.0;
            f.gear = 0.0;
            f.on_ground = true;
            f.easy_landing = easy;
            f.body.pos = Vec3::new(0.0, 0.0, -(f.jet.gear.struts[0].pos.z - 0.1).max(0.6));
            f.body.att = Quat::IDENTITY;
            f.body.vel = Vec3::new(0.0, 0.0, sink);
            f.check_ground(false, true, 0.0);
            assert_eq!((f.crashed, f.landings), (None, 1), "{sink}");
            f.state().hard_landings
        };
        assert_eq!(hard(3.0, false), 0);
        assert_eq!(hard(3.1, false), 1);
        assert_eq!(hard(3.9, false), 1);
        assert_eq!((hard(6.0, true), hard(6.2, true)), (0, 1));
        assert!(!crate::aircraft::hard_landing(-3.9, false, false), "the original's limits: no hard landing");
    }

    /// Gear damage (7) holds the gear where it is: the lever no longer moves it.
    #[test]
    fn damaged_gear_ignores_the_lever() {
        let mut f = airborne(jets::all()[0]);
        f.gear = 0.0;
        f.set_damage(1 << 7, false);
        f.set_controls(crate::aircraft::Controls { gear_down: false, ..f.controls() });
        for _ in 0..240 {
            f.step(1.0 / 60.0);
        }
        assert_eq!(f.state().gear, 0.0);
        f.set_damage(0, false);
        for _ in 0..60 {
            f.step(1.0 / 60.0);
        }
        assert!(f.state().gear > 0.4, "{}", f.state().gear);
    }

    /// The SPD BRK switch (the player's): held aft the speed brake opens at 30 deg/s and stays where the switch is
    /// let go; forward closes it; with the switch the brake control opens nothing in the air, and the gear-down
    /// limit holds.
    #[test]
    fn speed_brake_switch_opens_while_held_and_closes() {
        let [barak, ..] = jets::all();
        let mut f = airborne(barak);
        f.sb_switch = Some(0);
        f.set_controls(crate::aircraft::Controls { brakes: true, ..f.controls() });
        let run = |f: &mut SixDof, sw: i8, s: f64| {
            f.sb_switch = Some(sw);
            for _ in 0..(s * 60.0) as usize {
                f.step(1.0 / 60.0);
            }
            f.surfaces().dsb
        };
        assert!(run(&mut f, 0, 1.0) < 0.1, "the brake control alone");
        let half = run(&mut f, 1, 1.0);
        assert!((half - 30.0).abs() < 2.0, "{half}");
        assert!((run(&mut f, 0, 1.0) - 30.0).abs() < 2.0, "let go: it stays");
        assert!((run(&mut f, 1, 3.0) - 60.0).abs() < 0.1, "held: fully open");
        assert!(run(&mut f, -1, 3.0) < 0.1, "forward: closed");
        f.gear = 0.0;
        f.set_controls(crate::aircraft::Controls { gear_down: true, ..f.controls() });
        assert!((run(&mut f, 1, 3.0) - 43.0).abs() < 0.1, "the gear-down limit");
    }

    /// The F-16's speed brake opens to 60°, to 43° with the main gear down and locked (T.O. 1F-16A-1 p. 1-118); the
    /// F-35I's surfaces have no gear-down limit (inferred).
    #[test]
    fn speed_brake_43_degrees_with_the_gear_down() {
        let open = |jet: jets::Jet, gear: f32| {
            let mut f = airborne(jet);
            f.gear = gear;
            let c = crate::aircraft::Controls { brakes: true, gear_down: gear == 0.0, ..f.controls() };
            f.set_controls(c);
            for _ in 0..240 {
                f.step(1.0 / 60.0);
            }
            f.surfaces().dsb
        };
        let [barak, sufa, adir, _] = jets::all();
        assert!((open(barak, 0.0) - 43.0).abs() < 0.1 && (open(sufa, 0.0) - 43.0).abs() < 0.1);
        assert!((open(barak, super::GEAR_UP) - 60.0).abs() < 0.1);
        assert!((open(adir, 0.0) - 60.0).abs() < 0.1);
    }

    /// `jet` standing on a runway heading north (ENU x = 0 the centreline), engine running, brakes on.
    fn on_runway(jet: jets::Jet) -> SixDof {
        let ini = iaf_formats::ini::Ini::parse(b"[X]\nMaxRollRate=308\n");
        let st = Start {
            position: Vec3::ZERO,
            pitch: 0.0,
            roll: 0.0,
            heading: 0.0,
            velocity: Vec3::ZERO,
            airborne: false,
            engine_on: true,
        };
        let mut f = SixDof::start(Params::from_section(ini.section("X").unwrap()), Envelope::parse(b""), jet, st);
        f.set_ground_height(0.0);
        for _ in 0..120 {
            f.step(1.0 / 60.0);
        }
        f
    }

    /// [`on_runway`] with `stores_kg` hung, settled on its struts.
    fn settled(jet: jets::Jet, stores_kg: f32) -> SixDof {
        let mut f = on_runway(jet);
        f.set_stores(stores_kg, 0.0, 0.0);
        for _ in 0..120 {
            f.step(1.0 / 60.0);
        }
        f
    }

    /// A pilot keeping the jet on the centreline with the pedals (rudder and nose-wheel steering) and the wings
    /// level with the stick: the controls for one frame (heading north, x = 0).
    fn centreline(f: &SixDof, throttle: f32, brakes: bool, pull: f32) -> crate::aircraft::Controls {
        let s = f.state();
        let hdg = (s.heading as f64 + std::f64::consts::PI).rem_euclid(std::f64::consts::TAU) - std::f64::consts::PI;
        let pedal = -(0.08 * s.position.x + 3.0 * hdg + f.body.omega.z);
        crate::aircraft::Controls {
            throttle,
            brakes,
            stick_y: pull,
            stick_x: (-2.0 * s.roll).clamp(-1.0, 1.0),
            rudder: pedal.clamp(-1.0, 1.0) as f32,
            gear_down: true,
            ..f.controls()
        }
    }

    /// The F-16's crosswind limit, 25 kt (secondary: modern-iaf/docs/flight-model.md §9.8): a maximum-power take-off
    /// and a landing roll from 140 kt to a stop in a 25 kt wind straight across the runway stay within 5 m of the
    /// centreline (a quarter of the runway's half width).
    #[test]
    fn crosswind_take_off_and_landing_track_the_centreline() {
        let [barak, sufa, ..] = jets::all();
        for jet in [barak, sufa] {
            let mut f = on_runway(jet);
            f.set_wind(25.0, 90.0);
            let (mut worst, mut kt) = (0.0f32, 0.0);
            for _ in 0..60 * 60 {
                let s = f.state();
                let pull = if s.speed as f64 > 150.0 * 0.514444 {
                    (0.15 * (12.0 - s.pitch.to_degrees())).clamp(-1.0, 1.0)
                } else {
                    0.0
                };
                f.set_controls(centreline(&f, 1.0, false, pull));
                f.step(1.0 / 60.0);
                let s = f.state();
                if !s.on_ground {
                    kt = s.speed as f64 / 0.514444;
                    break;
                }
                worst = worst.max(s.position.x.abs() as f32);
            }
            println!("{}: crosswind take-off, off the centreline at most {worst:.2} m, lift-off {kt:.0} kt", jet.name);
            assert!(kt > 100.0 && worst < 5.0, "{}: {worst} m", jet.name);

            let mut f = on_runway(jet);
            f.set_wind(25.0, 90.0);
            f.body.vel = Vec3::new(140.0 * 0.514444, 0.0, 0.0);
            let mut worst = 0.0f32;
            for i in 0..60 * 60 {
                f.set_controls(centreline(&f, 0.0, i > 120, 0.0));
                f.step(1.0 / 60.0);
                worst = worst.max(f.state().position.x.abs() as f32);
                if f.body.speed() < 1.0 {
                    break;
                }
            }
            println!("{}: crosswind landing roll, off the centreline at most {worst:.2} m", jet.name);
            assert!(f.body.speed() < 1.0 && f.crashed.is_none() && worst < 5.0, "{}: {worst} m", jet.name);
        }
    }

    /// Full right pedal on the runway, idle, no brakes, for 4 s from `kt`: the largest ground sideslip at the c.g. (deg,
    /// the path against the nose) and the mean yaw rate over the last second (deg/s).
    fn full_pedal(jet: jets::Jet, kt: f64) -> (f64, f64, f64) {
        let mut f = on_runway(jet);
        f.body.vel = Vec3::new(kt * 0.514444, 0.0, 0.0);
        let (mut slip, mut yaw, mut roll) = (0.0f64, 0.0, 0.0f64);
        for i in 0..240 {
            f.set_controls(crate::aircraft::Controls { throttle: 0.0, brakes: false, rudder: 1.0, ..f.controls() });
            f.step(1.0 / 60.0);
            let v = f.body.vel;
            if v.x > 0.5 {
                slip = slip.max(v.y.atan2(v.x).to_degrees().abs());
            }
            if i >= 180 {
                yaw += f.body.omega.z.to_degrees() / 60.0;
            }
            roll = roll.max(f.body.att.euler().0.to_degrees().abs());
        }
        (slip, yaw, roll)
    }

    /// Ground steering (the user's report, 2026-11-15: full pedal skidded the jet from about 60 kt, −6° of sideslip at
    /// 66 kt and −14° at 104 kt). At 6 kt full pedal turns the jet on the nose wheel's 32° (the kinematic yaw rate
    /// v · tan 32° / wheelbase within 25 %); at 30–140 kt it yaws hard (sideslip up to ~16°, the side grip 0.55) and
    /// the jet never tips: it leans under 10° (the struts' air-spring stiffness, `jets::STRUT_SAG`).
    #[test]
    fn full_pedal_steers_at_taxi_speed_and_never_tips() {
        for jet in jets::all().into_iter().take(3) {
            let (slip, yaw, _) = full_pedal(jet, 6.0);
            let wheelbase = jet.gear.struts[0].pos.x - jet.gear.struts[1].pos.x;
            let kinematic = (6.0 * 0.514444 * jet.nws_deg.to_radians().tan() / wheelbase).to_degrees();
            println!(
                "{}: full pedal at 6 kt: yaw {yaw:.1} deg/s (kinematic {kinematic:.1}), slip {slip:.1}°",
                jet.name
            );
            assert!((yaw / kinematic - 1.0).abs() < 0.25, "{}: {yaw} vs {kinematic}", jet.name);
            for kt in [30.0, 50.0, 66.0, 80.0, 100.0, 120.0, 140.0] {
                let (slip, yaw, roll) = full_pedal(jet, kt);
                println!("{}: full pedal at {kt} kt: slip {slip:.2}°, yaw {yaw:.2} deg/s, roll {roll:.1}°", jet.name);
                assert!(roll < 10.0, "{} at {kt} kt: rolled {roll}°", jet.name);
            }
        }
    }

    /// The autopilot's taxi pivot turns the 6-DoF on its wheels: from 10 m/s a 90° turn right ends within 10 s, the
    /// heading and the position moving smoothly (no jump), on about the original's 30 m radius.
    #[test]
    fn taxi_pivot_turns_on_the_wheels() {
        let mut f = on_runway(jets::all()[0]);
        f.body.vel = Vec3::new(10.0, 0.0, 0.0);
        f.set_controls(crate::aircraft::Controls { brakes: false, throttle: 0.0, ..f.controls() });
        f.set_pivot(Some(std::f32::consts::FRAC_PI_2));
        let (mut t, mut last) = (0.0, f.state());
        while (f.state().heading - std::f32::consts::FRAC_PI_2).abs() > 0.5f32.to_radians() && t < 10.0 {
            f.step(1.0 / 60.0);
            t += 1.0 / 60.0;
            let s = f.state();
            let turn = (s.heading - last.heading + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU)
                - std::f32::consts::PI;
            assert!(turn.abs() < 2f32.to_radians(), "a heading jump at {t:.2} s");
            assert!((s.position - last.position).length() < 0.5, "a position jump at {t:.2} s");
            last = s;
        }
        f.set_pivot(None);
        let s = f.state();
        println!(
            "taxi pivot: 90° in {t:.1} s, now {:.1} m east, {:.1} m north, heading {:.2}°, {:.1} m/s",
            s.position.x,
            s.position.y,
            s.heading.to_degrees(),
            s.speed
        );
        assert!(t < 10.0 && f.crashed.is_none(), "{t} s");
        assert!(s.position.x > 15.0 && s.position.x < 60.0, "{}", s.position.x);
    }

    /// A maximum-power take-off as the game's take-off lesson flies it: half back stick from the rotation speed on
    /// the wheels, then a 10° pitch hold. The runway rises `slope` m per metre north, and the game's frame gives the
    /// ground under the jet once per `dt`, as `terrain_view.gd` does. Returns the frames in which the
    /// weight-on-wheels state changed (s, kt, the new state) and the landings counted.
    fn rotation(jet: jets::Jet, stores_kg: f32, rotate_kt: f64, slope: f64, dt: f64) -> (Vec<(f64, f64, bool)>, u32) {
        let mut f = settled(jet, stores_kg);
        let (mut changes, mut was, mut t, mut off_at) = (Vec::new(), true, 0.0, None);
        while t < 90.0 && off_at.is_none_or(|o| t < o + 10.0) {
            let s = f.state();
            let kt = s.speed as f64 / 0.514444;
            let pull = if s.on_ground {
                if kt > rotate_kt { 0.5 } else { 0.0 }
            } else {
                (0.1 * (10.0 - s.pitch.to_degrees())).clamp(-0.3, 0.5)
            };
            f.set_controls(centreline(&f, 1.0, false, pull));
            f.set_ground_height((slope * f.body.pos.x) as f32);
            f.set_ground_slope(0.0, slope as f32);
            f.step(dt);
            t += dt;
            let on = f.state().on_ground;
            if on != was {
                changes.push((t, f.state().speed as f64 / 0.514444, on));
                off_at = off_at.or(Some(t));
            }
            was = on;
        }
        assert!(f.crashed.is_none(), "{}: crashed", jet.name);
        (changes, f.landings)
    }

    /// Weight on wheels changes once at lift-off (the Mac's `test_mvp`, 2026-11-18: the Adir's on-ground state
    /// dropped and came back during the roll and the rotation on Nevatim's runway, which falls 1.3 m in 100 m).
    /// Every jet, at its reference weight and with a mission's stores (the Sufa's 16.5 t: + 24 %), on a runway that
    /// is level, falls and rises 1.3 %, at 24 (the headless probe's) and 60 frames a second: one change, to
    /// airborne, past the rotation speed, and no landing counted.
    #[test]
    fn weight_on_wheels_changes_once_at_lift_off() {
        let mut bad = Vec::new();
        for (jet, rotate_kt) in jets::all().into_iter().zip([140.0, 155.0, 160.0, 150.0]) {
            for (heavy, slope, hz) in [false, true]
                .into_iter()
                .flat_map(|h| [0.0, -0.013, 0.013].map(|s| (h, s)))
                .flat_map(|(h, s)| [24.0, 60.0].map(|hz| (h, s, hz)))
            {
                let stores = if heavy { 0.24 * jet.airframe.mass } else { 0.0 };
                let (changes, landings) = rotation(jet, stores as f32, rotate_kt, slope, 1.0 / hz);
                let once = matches!(changes[..], [(_, kt, false)] if kt >= rotate_kt);
                println!(
                    "{} +{stores:.0} kg, slope {slope}, {hz} Hz: {} changes, first {:.1?}, landings {landings}",
                    jet.name,
                    changes.len(),
                    changes.first()
                );
                if !once || landings != 0 {
                    bad.push((jet.name, stores, slope, hz, changes.len(), landings));
                }
            }
        }
        assert!(bad.is_empty(), "{bad:.1?}");
    }

    #[test]
    fn probe_rests_at_taxi_speed_and_follows_in_flight() {
        let mut a = 0.0;
        for _ in 0..60 {
            a = probe_aoa(a, 45.0, 10.0, 1.0 / 30.0); // a near-zero flow vector at 10 kt
        }
        assert_eq!(a, 0.0);
        for _ in 0..60 {
            a = probe_aoa(a, 8.0, 150.0, 1.0 / 30.0);
        }
        assert!((a - 8.0).abs() < 0.01, "{a}");
        let step = probe_aoa(0.0, 8.0, 150.0, 1.0 / 30.0);
        assert!(step > 0.0 && step < 1.2, "lagged: {step}");
    }

    /// Ground steering released (the user, 2026-11-17: after a turn on the pedals the jet "keeps moving after I
    /// release", turning). Taxiing at 10 and 20 kt, full pedal for 2 s, then the pedals centred: the nose wheel is
    /// straight at once (not castoring), and the yaw rate falls as fast as the tyres' side grip turns the jet's yaw
    /// momentum: under 20 % of its value 2 s later at 10 kt, under 35 % at 20 kt, and under 0.5 deg/s 5 s later; the
    /// same with a mission's stores (+ 24 % weight: it stops a little sooner).
    /// Before, a castoring nose wheel let the Sufa still turn at 13 deg/s 2 s after release at 10 kt (2.6 deg/s 6 s
    /// after).
    #[test]
    fn centred_pedals_stop_the_ground_turn() {
        let dt = 1.0 / 60.0;
        for jet in jets::all() {
            for (kt, share, stores) in [(10.0, 0.2, 0.0), (20.0, 0.35, 0.0), (10.0, 0.2, 0.24), (20.0, 0.35, 0.24)] {
                let mut f = settled(jet, (stores * jet.airframe.mass) as f32);
                f.body.vel = Vec3::new(kt * 0.514444, 0.0, 0.0);
                let mut at = [0.0f64; 4];
                for i in 0..7 * 60 {
                    let rudder = if i < 120 { 1.0 } else { 0.0 };
                    f.set_controls(crate::aircraft::Controls { throttle: 0.0, brakes: false, rudder, ..f.controls() });
                    if i == 120 {
                        let w = f.wheels(&f.controls());
                        assert!(w.steer == 0.0 && !w.castor, "{}: the nose wheel at release {w:?}", jet.name);
                    }
                    f.step(dt);
                    if let Some(k) = [119, 179, 239, 419].iter().position(|&n| n == i) {
                        at[k] = f.body.omega.z.to_degrees();
                    }
                }
                println!("{} + {stores} at {kt} kt: yaw at release, +1, +2, +5 s: {at:.2?} deg/s", jet.name);
                assert!(at[2].abs() < share * at[0].abs() && at[3].abs() < 0.5, "{} at {kt} kt: {at:?}", jet.name);
            }
        }
    }

    /// Braking pitch (the user, 2026-11-17: the jet leans "to much forward and backward on the ground when pressing
    /// the breaks"). From 10, 20 and 40 kt at idle, the brake switch on to a full stop: every jet's nose dips at most
    /// 1.1° (the static braked attitude 0.9° for the F-16s), comes back up no more than 0.1° past the standing
    /// attitude when the stop takes the braking force away, is within 0.1° of it 1 s after the stop, and the jet runs
    /// straight. With a mission's stores (+ 24 % weight, the Sufa's 16.5 t) the same struts dip in proportion: at
    /// most 1.1° × 1.24 (the F-16s 1.3°; the Mac's window run of 2026-11-18 measured 1.24–1.31°).
    /// Before (a brake that stepped to full, struts damped alike both ways): 1.24° down, 0.4° back up, three rocks.
    #[test]
    fn braking_dips_the_nose_and_settles_without_rocking() {
        let dt = 1.0 / 60.0;
        for jet in jets::all() {
            for (kt, stores) in [10.0, 20.0, 40.0].into_iter().flat_map(|kt| [(kt, 0.0), (kt, 0.24)]) {
                let mut f = settled(jet, (stores * jet.airframe.mass) as f32);
                let p0 = f.body.att.euler().1.to_degrees();
                f.set_controls(crate::aircraft::Controls { throttle: 0.0, brakes: false, ..f.controls() });
                f.body.vel = Vec3::new(kt * 0.514444, 0.0, 0.0);
                f.body.omega.z = 0.5f64.to_radians(); // a small yaw to show any ground loop
                for _ in 0..30 {
                    f.step(dt);
                }
                f.set_controls(crate::aircraft::Controls { brakes: true, ..f.controls() });
                let (mut down, mut up, mut stop, mut late, mut hdg) = (0.0f64, 0.0f64, None, 0.0f64, 0.0f64);
                for i in 0..15 * 60 {
                    f.step(dt);
                    let p = f.body.att.euler().1.to_degrees() - p0;
                    hdg = hdg.max(f.body.att.euler().2.to_degrees().abs());
                    down = down.min(p);
                    if stop.is_none() && f.body.speed() < 0.05 {
                        stop = Some(i);
                    }
                    if let Some(s) = stop {
                        up = up.max(p);
                        if i > s + 60 {
                            late = late.max(p.abs());
                        }
                    }
                }
                println!(
                    "{} + {stores} braking from {kt} kt: nose down {down:.2}°, back up {up:.2}°, after the stop's \
                     first second within {late:.2}°, heading {hdg:.1}°, stopped at {:.1} s",
                    jet.name,
                    stop.unwrap_or(0) as f64 * dt
                );
                assert!(
                    stop.is_some() && down > -1.1 * (1.0 + stores) && up < 0.1 && late < 0.1 && hdg < 2.0,
                    "{} + {stores} from {kt} kt",
                    jet.name
                );
            }
        }
    }
}
