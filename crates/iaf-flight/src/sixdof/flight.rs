//! One flight on the 6-DoF: a jet with its control system, engines, gear and fuel, stepped by the game's frames
//! and read back as the original model's [`State`] and [`ApView`] in the game's ENU frame (iaf-2026/docs/
//! flight-model.md §9.12). The original game never builds one ([`crate::fm::Fm`]).

use super::aero::{Flow, Surfaces, coefficients, compressibility, lef_schedule};
use super::body::{Body, MAX_FRAME, MAX_STEP, Quat};
use super::engine::Engine;
use super::fcs::{Fcs, Pilot, Sensors};
use super::gear::Anchors;
use super::jets::{self, Jet};
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
    /// Fuel and its capacity, stores, kg.
    fuel_kg: f64,
    capacity_kg: f64,
    stores_kg: f64,
    stores_cd: f64,
    /// The empty jet, kg (the reference weight less its fuel).
    empty_kg: f64,
    /// Terrain height under the jet (ENU z, m); the gear's height above its contact (for the instruments).
    pub ground_height: f32,
    pub gear_clearance: f32,
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
    thrust_n: f64,
    pub fuel_flow: f32,
    pub unlimited_fuel: bool,
    /// A ground start waits for the terrain height to set the jet on its gear.
    place_on_gear: bool,
    /// The air mass's velocity, world NED (the mission's wind; no gusts).
    wind: Vec3,
    /// The terrain under the jet is scenery (a roof, a tree top): meeting it is a crash.
    pub ground_obstacle: bool,
    /// The terrain's slope (the normal's vertical share) and terraintype.dat flags (water, runway, rough).
    ground_normal_z: f32,
    ground_flags: Option<u32>,
    /// The Preferences' "no crashes" / "invulnerable": the ground checks pass everything.
    pub no_crashes: bool,
    /// An autopilot loop flies: its stick is a linear g command ([`SixDof::ap_view`]).
    ap_flying: bool,
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
            fuel_kg,
            capacity_kg: fuel_kg,
            stores_kg: 0.0,
            stores_cd: 0.0,
            empty_kg,
            ground_height: 0.0,
            gear_clearance: jet.gear.struts[0].pos.z as f32,
            engine_on: st.engine_on || st.airborne,
            start_seq: if st.engine_on || st.airborne { Sequence::running() } else { Sequence::default() },
            gear: 0.0,
            accel_g: Vec3::new(0.0, 0.0, -1.0),
            acc: Vec3::ZERO,
            on_ground: !st.airborne,
            crashed: None,
            landings: 0,
            thrust_n: 0.0,
            fuel_flow: 0.0,
            unlimited_fuel: false,
            place_on_gear: !st.airborne,
            wind: Vec3::ZERO,
            ground_obstacle: false,
            ground_normal_z: 1.0,
            ground_flags: None,
            no_crashes: false,
            ap_flying: false,
        };
        s.fcs = Fcs::new(jet.g_limits);
        if st.airborne {
            s.controls = Controls { throttle: MILITARY, gear_down: false, ..Controls::default() };
            s.gear = GEAR_UP;
            s.trim_level(h.max(60.0), st.roll as f64, heading);
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
        self.empty_kg + self.fuel_kg + self.stores_kg
    }

    /// Level flight at `v` (m/s) here, wings banked `roll` (rad, the start's), heading `heading`: α and the
    /// stabilator from the 1 g force and moment balance, the engine's power from the x force (a few Newton steps;
    /// the control system then holds it).
    fn trim_level(&mut self, v: f64, roll: f64, heading: f64) {
        let alt = -self.body.pos.z;
        let (_, ps, sound) = atmosphere(alt);
        let af = self.airframe();
        let t = level_trim(&self.jet, &af, alt, v);
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

    /// The terrain height under the jet (ENU z). The first one after a ground start sets the jet on its gear,
    /// the struts at their static sag.
    pub fn set_ground_height(&mut self, h: f32) {
        self.ground_height = h;
        if self.place_on_gear && h > -1.0e8 {
            self.place_on_gear = false;
            self.body.pos.z = -(h as f64 + self.jet.gear.struts[0].pos.z - 0.15);
        }
    }

    /// The engine on or off at once (the original's meaning: any throttle command starts it, the ejection stops it),
    /// the electrical power unchanged. Modern IAF's start goes through [`SixDof::start_engine`] instead.
    pub fn set_engine_on(&mut self, on: bool) {
        self.engine_on = on;
        if on {
            self.start_seq = Sequence::running();
        }
    }

    /// The "start engine" command: a cold engine runs its jet's start sequence ([`super::start`]); it runs (gives
    /// thrust) once the sequence reaches idle.
    pub fn start_engine(&mut self) {
        if !self.engine_on {
            if self.start_seq.phase == Phase::Running {
                self.start_seq.shutdown(); // stopped since its last start: from the beginning
            }
            self.start_seq.begin();
        }
    }

    /// One start-up checklist step by its key ([`Sequence::press`]); a running engine takes none.
    pub fn start_step(&mut self, step: &str) -> Result<(), &'static str> {
        if self.engine_on && step != "avionics" && step != "ins" {
            return Ok(());
        }
        self.start_seq.press(&self.jet.start, step)
    }

    /// The electrical power: 0 none, 1 the battery, 2 the displays up ([`Sequence::power`]).
    pub fn power(&self) -> u8 {
        self.start_seq.power(&self.jet.start)
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
            self.capacity_kg = kg as f64;
            self.fuel_kg = kg as f64;
        }
    }

    /// External tanks at the start, as `Aircraft::set_fuel_capacity` (FUN_005a8980 then the start's fill): the
    /// maximum = the internal fuel + `extra_kg`, filled.
    pub fn set_fuel_capacity(&mut self, extra_kg: f32) {
        self.capacity_kg = self.jet.fuel_lb * LB + extra_kg.max(0.0) as f64;
        self.fuel_kg = self.capacity_kg;
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
    }

    pub fn internal_fuel_kg(&self) -> f32 {
        (self.jet.fuel_lb * LB) as f32
    }

    pub fn fuel_capacity_kg(&self) -> f32 {
        self.capacity_kg as f32
    }

    pub fn engine_off(&mut self) {
        self.engine_on = false;
    }

    /// Re-placed at rest on the ground at (x, y) ENU facing `heading` (the autopilot's taxi re-placement).
    pub fn replace_on_ground(&mut self, x: f64, y: f64, heading: f32) {
        let z = self.body.pos.z;
        self.body = Body::new(Vec3::new(y, x, z), Vec3::ZERO, Quat::from_euler(0.0, 0.0, heading as f64));
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
        // The mass and the rotors' momentum change slowly: once per frame.
        let af = self.airframe();
        if self.start_seq.step(&self.jet.start, dt) {
            self.engine_on = true; // the sequence reached idle
        }
        for _ in 0..n as usize {
            self.substep(dt / n, &af);
            if self.crashed.is_some() {
                break;
            }
        }
    }

    fn substep(&mut self, dt: f64, af: &super::body::Airframe) {
        let c = self.controls;
        self.t += dt;
        // Gear lever ramp.
        let target = if c.gear_down { 0.0 } else { GEAR_UP };
        self.gear += (target - self.gear).clamp(-GEAR_RATE * dt as f32, GEAR_RATE * dt as f32);
        let gear_down = self.gear < GEAR_UP;
        let ground_z = -self.ground_height as f64;
        let b = self.body;
        let alt = -b.pos.z;
        let (rho, ps, sound) = atmosphere(alt);
        let flow = Flow::from_body(&Body { vel: b.vel - b.att.rotate_inv(self.wind), ..b });
        let qbar = 0.5 * rho * flow.v * flow.v;
        let (max_g, min_g) = self.jet.g_limits;
        let stick_y = c.stick_y as f64;
        let pilot = Pilot {
            stick_x: c.stick_x as f64,
            stick_y,
            pedal: c.rudder as f64,
            speed_brake: c.brakes && !self.on_ground,
            // The autopilot's stick is linear in g (its ApView: centre 1 g, full stick MaxG / MinG).
            g_command: self.ap_flying.then_some(if stick_y >= 0.0 {
                1.0 + stick_y * (max_g - 1.0)
            } else {
                1.0 - stick_y * (min_g - 1.0)
            }),
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
        };
        self.surfaces = self.fcs.step(&pilot, &sensors, dt);
        let fuel_left = self.fuel_kg > 0.0 || self.unlimited_fuel;
        let travel = if self.engine_on && fuel_left { lever_to_travel(c.throttle) } else { 0.0 };
        if self.engine_on && fuel_left {
            self.engine.step(&self.jet.engine, travel, dt);
        } else {
            // A stopped engine winds down to idle power and then gives no thrust (inferred).
            self.engine.step(&self.jet.engine, 0.0, dt);
        }
        let jc = jets::Controls {
            surfaces: self.surfaces,
            throttle: travel,
            wheels: super::gear::Wheels {
                brake: if c.brakes && self.on_ground { 1.0 } else { 0.0 },
                steer: c.rudder as f64 * self.jet.nws_deg,
            },
            gear_down,
            stores_cd: self.stores_cd,
            engine_on: self.engine_on && fuel_left,
            wind: self.wind,
        };
        let running = jc.engine_on;
        let (jet, engine, anchors) = (&self.jet, self.engine, self.anchors);
        let forces = |s: &Body| {
            let (f, m, _) = jet.forces(s, &jc, &engine, ground_z, &anchors);
            (f, m)
        };
        let v0 = self.body.att.rotate(self.body.vel);
        self.body.rk4(af, dt, &mut { forces });
        let (f, _, loads) = jet.forces(&self.body, &jc, &engine, ground_z, &self.anchors);
        self.accel_g = f * (1.0 / (af.mass * G));
        self.acc = enu((self.body.att.rotate(self.body.vel) - v0) * (1.0 / dt));
        if gear_down {
            self.jet.update_gear(&self.body, &jc, ground_z, &mut self.anchors);
        }
        let was_on_ground = self.on_ground;
        self.on_ground = loads.iter().any(|&l| l > 0.0);
        // Fuel.
        let thrust = if running { engine.thrust(&self.jet.engine, flow.v / sound, alt) } else { 0.0 };
        self.thrust_n = thrust * self.jet.engines as f64;
        let ff = if running { engine.fuel_flow(&self.jet.engine, thrust, alt) * self.jet.engines as f64 } else { 0.0 };
        self.fuel_flow = ff as f32;
        if !self.unlimited_fuel {
            self.fuel_kg = (self.fuel_kg - ff * dt).max(0.0);
        }
        self.check_ground(was_on_ground, gear_down, ground_z);
    }

    /// Touchdowns and crashes (inferred limits, iaf-2026/docs/flight-model.md §9.12): a gear-down touchdown sinking
    /// slower than 3 m/s (about 10 ft/s, the F-16's design sink rate is open) with the wings within 15° counts as a
    /// landing; faster, banked further or with the gear up, or the c.g. reaching the runway, is a crash.
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
            if sink > 3.0 {
                Some(Crash::SinkRate)
            } else if roll.abs() > 15f64.to_radians() || pitch < -5f64.to_radians() || self.ground_normal_z < 0.985 {
                // Banked, nose down, or on more than 10° of slope (the original's landing check).
                Some(Crash::Landing)
            } else if pitch > 20f64.to_radians() {
                Some(Crash::TailStrike)
            } else {
                if self.t > 1.0 {
                    self.landings += 1;
                }
                None
            }
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
            rpm: if self.engine_on {
                (60.0 + 40.0 * (power / 50.0).min(1.0)) as f32
            } else {
                // A start in progress; a stopped engine (its sequence long done) shows none.
                if self.start_seq.phase == Phase::Running { 0.0 } else { self.start_seq.rpm as f32 }
            },
            throttle: self.controls.throttle,
            afterburner: if power > 75.0 {
                2
            } else if power > 50.0 {
                1
            } else {
                0
            },
            thrust_n: self.thrust_n as f32,
            fuel_kg: self.fuel_kg as f32,
            mass_kg: self.mass() as f32,
            stalled: false,
            buffet: alpha.to_degrees() > 15.0 && !self.on_ground,
            // The AoA warning measure: 0 below the 25° limiter, rising to the original's 1.2 at 30° (inferred).
            drag_x: ((alpha.to_degrees() - 25.0) / 5.0 * 1.2).clamp(0.0, 1.2) as f32,
            over_g: g > max_g,
            on_ground: self.on_ground,
            spinning: false,
            deep_stall: alpha.to_degrees() > 45.0 && !self.on_ground,
            tornado: false,
            end_worlds: 0,
            gear: self.gear,
            crashed: self.crashed,
            landings: self.landings,
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
        }
    }

    /// An autopilot loop starts or stops flying the jet (the autopilot's `stores_trim` hook): while it flies, the
    /// stick is a linear g command, as the autopilot reads [`SixDof::ap_view`].
    pub fn set_ap_flying(&mut self, on: bool) {
        self.ap_flying = on;
    }

    /// The autopilot's taxi pivot turn: the 6-DoF turns on the spot to the target heading (inferred: its wheels
    /// steer, but the autopilot's taxi laws were made for the original's pivot).
    pub fn set_pivot(&mut self, target: Option<f32>) {
        if let Some(h) = target {
            let (roll, pitch, _) = self.body.att.euler();
            self.body.att = Quat::from_euler(roll, pitch, h as f64);
            self.body.vel = Vec3::ZERO;
            self.anchors = Anchors::default();
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

/// `jet` (as `af`) in level flight at `alt_m`, true speed `v`: α and the stabilator from the 1 g force and
/// moment balance (Newton steps), the thrust from the x force; the flap on its schedule.
pub fn level_trim(jet: &Jet, af: &super::body::Airframe, alt_m: f64, v: f64) -> LevelTrim {
    let (rho, ps, sound) = atmosphere(alt_m);
    let qbar = 0.5 * rho * v * v;
    let w = af.mass * G;
    let mach = v / sound;
    let coeffs = |a: f64, dh: f64| {
        let s = Surfaces { dh, dlef: lef_schedule(a, qbar, ps), ..Surfaces::default() };
        let mut c = coefficients(&Flow { alpha: a, v, ..Flow::default() }, &s, af);
        compressibility(&mut c, mach, a, jet.aspect_ratio(), jet.wave_drag);
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

/// The top level speed (m/s) of `jet` at its reference weight at `alt_m`, full afterburner: from 150 m/s up, the
/// first speed where the maximum thrust no longer meets the level drag (1 m/s steps).
pub fn top_speed(jet: &Jet, alt_m: f64) -> f64 {
    let sound = atmosphere(alt_m).2;
    let max = |v: f64| Engine { power: 100.0 }.thrust(&jet.engine, v / sound, alt_m) * jet.engines as f64;
    let mut v = 150.0;
    while v < 900.0 && max(v) >= level_trim(jet, &jet.airframe, alt_m, v).thrust_needed {
        v += 1.0;
    }
    v
}

/// Figure 66(b)'s travel → the game's throttle lever (the inverse of [`lever_to_travel`]).
fn travel_to_lever(travel: f64) -> f32 {
    let mil = MILITARY as f64;
    (if travel <= 0.77 { travel / 0.77 * mil } else { mil + (travel - 0.77) / 0.23 * (1.0 - mil) }) as f32
}
