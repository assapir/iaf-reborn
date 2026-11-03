//! The sim's four jets (and TP-1538's own F-16) for the 6-DoF: mass, inertia, geometry, engines, gear. The
//! aerodynamics are TP-1538's F-16 tables for every jet, on each jet's own wing area, span and chord (as FM-0 does,
//! labelled). Sources and the inferred figures: iaf-2026/docs/flight-model.md §9.9.

use super::aero::{Flow, Surfaces, coefficients, force_moment};
use super::body::{Airframe, Body};
use super::engine::{Engine, EngineSpec, FIG66_IDLE_MAX, FIG66_IDLE_MIL};
use super::gear::{Anchors, Gear, TYRES, Wheels};
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
    EngineSpec::rated("F100-PW-229", 17_800.0, 29_160.0, 3.0)
}

/// The F110-GE-100 (F-16D Barak): 29,000 lbf with afterburner, military 0.59 of it (docs/real-aircraft.md §2, as
/// FM-0); idle → military 3.0 s (the F100's; `spool::ENGINES` type 100, inferred).
pub fn f110_100() -> EngineSpec {
    EngineSpec::rated("F110-GE-100", 0.59 * 29_000.0, 29_000.0, 3.0)
}

/// The F135-PW-100 (F-35I Adir): 28,000 / 43,000 lbf (`data_set.rs` F-35I row, docs/f35i.md §2); flight idle →
/// maximum about 6 s (Pratt & Whitney, docs/flight-model.md §10.2), figure 66's shape stretched to it.
pub fn f135() -> EngineSpec {
    EngineSpec::rated("F135-PW-100", 28_000.0, 43_000.0, 6.0 * FIG66_IDLE_MIL / FIG66_IDLE_MAX)
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
        },
        // F-16I Sufa: 20,500 lb + 8,850 lb (the F-16I REAL row).
        Jet {
            name: "F-16I Sufa",
            airframe: scaled(29_350.0, 30.0, 300.0),
            engine: f100_229(),
            engines: 1,
            gear: gear(13.2, 7.75, 1.75, 29_350.0),
            nws_deg: 32.0,
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
        },
    ]
}

/// The pilot's and the systems' inputs.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Controls {
    pub surfaces: Surfaces,
    /// 0…1, military at 0.77 (TP-1538 figure 66(b)).
    pub throttle: f64,
    pub wheels: Wheels,
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
        let flow = Flow::from_body(b);
        let qbar = 0.5 * a.rho as f64 * flow.v * flow.v;
        let (fa, ma) = force_moment(&coefficients(&flow, &c.surfaces, &self.airframe), qbar, &self.airframe);
        let thrust = engine.thrust(&self.engine, flow.v / a.sound as f64, alt) * self.engines as f64;
        let (fg, mg, loads) = self.gear.forces(b, ground_z, &self.wheels(c), &TYRES, anchors);
        (fa + fg + Vec3::new(thrust, 0.0, 0.0), ma + mg, loads)
    }
}
