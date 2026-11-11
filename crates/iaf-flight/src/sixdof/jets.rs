//! The sim's four jets (and TP-1538's own F-16) for the 6-DoF: mass, inertia, geometry, engines, gear. The
//! aerodynamics are TP-1538's F-16 tables for every jet, on each jet's own wing area, span and chord (as FM-0 does,
//! labelled). Sources and the inferred figures: modern-iaf/docs/flight-model.md §9.9.

use super::aero::{Flow, Surfaces, add_drag, coefficients, compressibility, force_moment};
use super::body::{Airframe, Body};
use super::engine::{Engine, EngineSpec, FIG66_IDLE_MAX, FIG66_IDLE_MIL, TSFC_F100};
use super::gear::{Anchors, Gear, TYRES, Wheels};
use super::start::{IPP, JFS, StartSpec};
use crate::Vec3;
use crate::atmosphere::air;
use crate::units::{FT, G, LB};

/// One jet.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Jet {
    pub name: &'static str,
    /// At its reference weight (empty + full internal fuel; TP-1538's 20,500 lb for its F-16).
    pub airframe: Airframe,
    pub engine: EngineSpec,
    /// Engines (all alike, turning the same way: inferred).
    pub engines: u32,
    pub gear: Gear,
    /// Nose-wheel steering limit, deg.
    pub nws_deg: f64,
    /// Internal fuel at the reference weight, lb.
    pub fuel_lb: f64,
    /// The wave drag (w, k) of `aero::compressibility`: ΔCD `w` at Mach 1.2, × (M / 1.2)^k above. Fit to public
    /// performance, not a sourced table (2026-11-03, `fit_wave_drag` in tests/sixdof.rs): each jet's level top speed
    /// at its reference weight meets its published figures (modern-iaf/docs/flight-model.md §9.15).
    pub wave_drag: (f64, f64),
    /// Maximum and minimum load factor, g (the REAL rows: the F-16's +9 / −3, the F-15E's +8.1 / −2).
    pub g_limits: (f64, f64),
    /// The trailing-edge flaps' droop with the gear handle down, deg ([`tef_schedule`]): the F-16's 20° (T.O.
    /// GR1F-16CJ-1); the F-35I's the same (inferred); 0 on the Ra'am (no public F-15E flap schedule was read: its model keeps the flap key).
    pub tef_deg: f64,
    /// The ground start's sequence ([`super::start`]).
    pub start: StartSpec,
}

/// TP-1538's F-16 (Table I) scaled to `weight_lb`, span `span_ft`, area `area_ft2`: the inertia × the mass ratio
/// × (span / 30 ft)², the chord = 1.132 × area / span (the F-16's ratio of chord to mean geometric chord). All
/// inferred for any jet but TP-1538's.
fn scaled(weight_lb: f64, span_ft: f64, area_ft2: f64) -> Airframe {
    let t = Airframe::TP1538;
    let k = weight_lb * LB / t.mass * (span_ft / 30.0).powi(2);
    Airframe {
        mass: weight_lb * LB,
        ix: t.ix * k,
        iy: t.iy * k,
        iz: t.iz * k,
        ixz: t.ixz * k,
        s: area_ft2 * FT * FT,
        b: span_ft * FT,
        cbar: 11.32 / 10.0 * area_ft2 / span_ft * FT,
        ..t
    }
}

/// Gear from the public wheelbase and track (ft) and the inferred c.g. height (m); 12 % of the weight on the nose
/// wheel and 0.15 m of strut sag at `weight_lb` (inferred).
fn gear(wheelbase_ft: f64, track_ft: f64, height_m: f64, weight_lb: f64) -> Gear {
    Gear::tricycle(wheelbase_ft * FT, track_ft * FT, height_m, 0.12, weight_lb * LB * G, 0.15)
}

/// The F100-PW-229 (F-16I Sufa, F-15I Ra'am): 17,800 / 29,160 lbf (Pratt & Whitney); idle → military 3.0 s, the
/// -220's (NASA TM-4320; inferred for the -229, as `shared/extra/planes/f15i/airframe.json`).
pub fn f100_229() -> EngineSpec {
    EngineSpec::rated("F100-PW-229", 17_800.0, 29_160.0, 3.0, TSFC_F100)
}

/// The F110-GE-100 (F-16D Barak): 29,000 lbf with afterburner, military 0.59 of it (docs/real-aircraft.md §2, as
/// FM-0); idle → military 3.0 s (the F100's; `spool::ENGINES` type 100, inferred); TSFC 0.64 / 2.05: the F-16 REAL
/// row's fuel flows over these ratings.
pub fn f110_100() -> EngineSpec {
    EngineSpec::rated("F110-GE-100", 0.59 * 29_000.0, 29_000.0, 3.0, (0.64, 2.05))
}

/// The F135-PW-100 (F-35I Adir): 28,000 / 43,000 lbf (`data_set.rs` F-35I row, docs/f35i.md §2); flight idle →
/// maximum about 6 s (Pratt & Whitney, docs/flight-model.md §10.2), figure 66's shape stretched to it; TSFC 0.79 /
/// 2.0: the F-35I REAL row's fuel flows over these ratings.
pub fn f135() -> EngineSpec {
    EngineSpec::rated("F135-PW-100", 28_000.0, 43_000.0, 6.0 * FIG66_IDLE_MIL / FIG66_IDLE_MAX, (0.79, 2.0))
}

/// TP-1538's F-16A as simulated: Table I, its own engine (Table VI, figure 66).
pub fn tp1538() -> Jet {
    Jet {
        name: "F-16 (TP-1538)",
        airframe: Airframe::TP1538,
        engine: EngineSpec::tp1538(),
        engines: 1,
        gear: gear(13.2, 7.75, 1.75, 20_500.0),
        nws_deg: 32.0,
        fuel_lb: 5_800.0,
        // The Barak's fit (inferred: the same airframe).
        wave_drag: (0.0509, 0.195),
        g_limits: (9.0, -3.0),
        tef_deg: 20.0,
        start: JFS,
    }
}

/// The four sim jets.
pub fn all() -> [Jet; 4] {
    [
        // F-16D Block 40 Barak: 19,100 lb empty + 5,800 lb fuel (FM-0, the F-16 REAL row).
        Jet {
            name: "F-16D Barak",
            airframe: scaled(24_900.0, 30.0, 300.0),
            engine: f110_100(),
            engines: 1,
            gear: gear(13.2, 7.75, 1.75, 24_900.0),
            nws_deg: 32.0,
            fuel_lb: 5_800.0,
            // Fit: Mach 1.2 at sea level, 2.0 at 40,000 ft (the F-16's public figures, tests/validation.rs REFS).
            wave_drag: (0.0509, 0.195),
            g_limits: (9.0, -3.0),
            tef_deg: 20.0,
            start: JFS,
        },
        // F-16I Sufa: 20,500 lb + 8,850 lb (the F-16I REAL row).
        Jet {
            name: "F-16I Sufa",
            airframe: scaled(29_350.0, 30.0, 300.0),
            engine: f100_229(),
            engines: 1,
            gear: gear(13.2, 7.75, 1.75, 29_350.0),
            nws_deg: 32.0,
            fuel_lb: 8_850.0,
            // Fit: Mach 1.2 at sea level, 2.0 at 40,000 ft (the F-16's; Block 50/52 1.89 sustained to 2.05).
            wave_drag: (0.0513, 0.212),
            g_limits: (9.0, -3.0),
            tef_deg: 20.0,
            start: JFS,
        },
        // F-35I Adir: 29,300 lb + 18,250 lb, wing 460 ft² (the F-35I REAL row), span 35 ft (Lockheed Martin);
        // wheelbase 19.75 ft, track 14.24 ft (Mason, Virginia Tech, F-35A data).
        Jet {
            name: "F-35I Adir",
            airframe: scaled(47_550.0, 35.0, 460.0),
            engine: f135(),
            engines: 1,
            gear: gear(19.75, 14.24, 2.0, 47_550.0),
            nws_deg: 32.0,
            fuel_lb: 18_250.0,
            // Fit: Mach 1.6 at 40,000 ft (Lockheed Martin), with the Barak's k; the 700 kt at sea level is the F-35A's
            // placard (inferred), not fitted: Mach 1.14 there.
            wave_drag: (0.0682, 0.195),
            g_limits: (9.0, -3.0),
            tef_deg: 20.0,
            start: IPP,
        },
        // F-15I Ra'am: 37,000 lb + 22,665 lb, wing 608 ft², span 42.8 ft (the F-15I REAL row, TO 1F-15E-1, USAF);
        // wheelbase 17.78 ft (the F-15 row, SAC), track 9 ft (TO 1F-15E-1, docs/f15i.md).
        Jet {
            name: "F-15I Ra'am",
            airframe: scaled(59_665.0, 42.8, 608.0),
            engine: f100_229(),
            engines: 2,
            gear: gear(17.78, 9.0, 2.1, 59_665.0),
            nws_deg: 45.0,
            fuel_lb: 22_665.0,
            // Fit: about Mach 2.0 at 40,000 ft with CFTs (F-15E, secondary), with the Barak's k (no sea-level figure).
            wave_drag: (0.0509, 0.195),
            g_limits: (8.1, -2.0),
            tef_deg: 0.0,
            start: JFS,
        },
    ]
}

/// The 6-DoF jet flying as the flight-model type `name` (`data_set::TYPES`): the F-16 as the Barak, the F-16I as the
/// Sufa, the F-35I as the Adir, the F-15I (and an F-15 on the own data) as the Ra'am.
pub fn by_type(name: &str) -> Option<Jet> {
    let [barak, sufa, adir, raam] = all();
    match name.to_ascii_uppercase().as_str() {
        "F-16" => Some(barak),
        "F-16I" => Some(sufa),
        "F-35I" => Some(adir),
        "F-15I" | "F-15" => Some(raam),
        _ => None,
    }
}

/// The trailing-edge flaps' command, deg (T.O. GR1F-16CJ-1 p. 1-120): with the gear handle down, `max` (20°) at
/// all calibrated airspeeds below 240 kt, less above, "nearly/fully retracted at 370 knots" (linear between:
/// inferred); with the handle up, 0 (the manual's up-and-away schedule by Mach is not public: inferred streamlined).
pub fn tef_schedule(handle_down: bool, cas_kt: f64, max: f64) -> f64 {
    if handle_down { max * ((370.0 - cas_kt) / 130.0).clamp(0.0, 1.0) } else { 0.0 }
}

/// The pilot's and the systems' inputs.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Controls {
    pub surfaces: Surfaces,
    /// 0…1, military at 0.77 (TP-1538 figure 66(b)).
    pub throttle: f64,
    pub wheels: Wheels,
    /// The gear is down (retracted: no struts).
    pub gear_down: bool,
    /// The external stores' ΔCD (the game's stores drag index, ×1e-4 applied, as the original adds it).
    pub stores_cd: f64,
    /// The engines give thrust (off: none, at any Mach).
    pub engine_on: bool,
    /// The air mass's velocity, world NED, m/s (the mission's wind).
    pub wind: Vec3,
}

impl Jet {
    /// The jet at another weight: the mass and the inertia × the weight ratio (stores and fuel at the c.g.:
    /// inferred); the gear unchanged.
    pub fn at_weight(mut self, weight_lb: f64) -> Jet {
        let k = weight_lb * LB / self.airframe.mass;
        let a = &mut self.airframe;
        (a.mass, a.ix, a.iy, a.iz, a.ixz) = (a.mass * k, a.ix * k, a.iy * k, a.iz * k, a.ixz * k);
        self
    }

    pub fn aspect_ratio(&self) -> f64 {
        self.airframe.b * self.airframe.b / self.airframe.s
    }

    /// The wheels as commanded, the steering within the jet's limit.
    pub fn wheels(&self, c: &Controls) -> Wheels {
        Wheels { steer: c.wheels.steer.clamp(-self.nws_deg, self.nws_deg), ..c.wheels }
    }

    /// After a frame: the braked tyres stick or slide ([`Gear::update`]).
    pub fn update_gear(&self, b: &Body, c: &Controls, ground_z: f64, anchors: &mut Anchors) {
        self.gear.update(b, ground_z, &self.wheels(c), &TYRES, anchors);
    }

    /// The airframe for a flight whose engines are at `engine`: the rotors' momentum is the flight's, the jet's
    /// definition stays as it is.
    pub fn airframe(&self, engine: &Engine) -> Airframe {
        Airframe { h_engine: engine.angular_momentum(&self.engine) * self.engines as f64, ..self.airframe }
    }

    /// The gear's strut loads (N) at `b` on a runway at `ground_z`.
    pub fn gear_loads(&self, b: &Body, ground_z: f64) -> [f64; 3] {
        self.gear.loads(b, ground_z)
    }

    /// Body-axis force (without gravity) and moment: aerodynamics, thrust along the body x axis (inferred: no
    /// offset or cant) and the gear on a runway at `ground_z` (NED), with the gear's loads.
    pub fn forces(
        &self,
        b: &Body,
        c: &Controls,
        engine: &Engine,
        ground_z: f64,
        anchors: &Anchors,
    ) -> (Vec3, Vec3, [f64; 3]) {
        let alt = -b.pos.z;
        let a = air(alt as f32);
        // The aerodynamics see the velocity through the air.
        let flow = Flow::from_body(&Body { vel: b.vel - b.att.rotate_inv(c.wind), ..*b });
        let qbar = 0.5 * a.rho as f64 * flow.v * flow.v;
        let mach = flow.v / a.sound as f64;
        let mut coeffs = coefficients(&flow, &c.surfaces, &self.airframe);
        compressibility(&mut coeffs, mach, flow.alpha, self.aspect_ratio(), self.wave_drag);
        // The gear's drag, ΔCD 0.02 (FM-0's LandingGearDragIndex, inferred), and the stores'.
        add_drag(&mut coeffs, if c.gear_down { 0.02 } else { 0.0 } + c.stores_cd, flow.alpha);
        let (fa, ma) = force_moment(&coeffs, qbar, &self.airframe);
        let thrust = if c.engine_on { engine.thrust(&self.engine, mach, alt) * self.engines as f64 } else { 0.0 };
        let (fg, mg, loads) = if c.gear_down {
            self.gear.forces(b, ground_z, &self.wheels(c), &TYRES, anchors)
        } else {
            (Vec3::ZERO, Vec3::ZERO, [0.0; 3])
        };
        (fa + fg + Vec3::new(thrust, 0.0, 0.0), ma + mg, loads)
    }
}
