//! The flight model a flight flies: the original game's ([`Aircraft`]) or the Modern IAF sim's 6-DoF ([`SixDof`]),
//! chosen by the flight data. A `bd.ibx` section with `Model = 6dof` flies the 6-DoF; the original game's sections
//! have no `Model` key, so it never reaches it (modern-iaf/docs/flight-model.md §9.12).

use crate::aircraft::{Aircraft, ApView, Controls, Start, State};
use crate::autopilot::Host;
use crate::sixdof::flight::SixDof;
use crate::sixdof::jets;
use crate::{Envelope, Params};

pub enum Fm {
    Original(Box<Aircraft>),
    SixDof(Box<SixDof>),
}

impl Fm {
    /// Starts type `name` loaded as `params` / `envelope`: the 6-DoF when its section asked for it
    /// ([`Params::model_6dof`], read with the section: no extra file read) and the 6-DoF has the jet
    /// ([`jets::by_type`]), else the original model.
    pub fn start(name: &str, params: Params, envelope: Envelope, st: Start) -> Fm {
        match jets::by_type(name).filter(|_| params.model_6dof) {
            Some(jet) => Fm::SixDof(Box::new(SixDof::start(params, envelope, jet, st))),
            None => Fm::Original(Box::new(Aircraft::start(params, envelope, st))),
        }
    }

    pub fn original(&mut self) -> Option<&mut Aircraft> {
        match self {
            Fm::Original(a) => Some(a),
            Fm::SixDof(_) => None,
        }
    }

    pub fn original_ref(&self) -> Option<&Aircraft> {
        match self {
            Fm::Original(a) => Some(a),
            Fm::SixDof(_) => None,
        }
    }

    pub fn step(&mut self, dt: f64) {
        match self {
            Fm::Original(a) => a.step(dt),
            Fm::SixDof(s) => s.step(dt),
        }
    }

    pub fn state(&self) -> State {
        match self {
            Fm::Original(a) => a.state(),
            Fm::SixDof(s) => s.state(),
        }
    }

    pub fn params(&self) -> &Params {
        match self {
            Fm::Original(a) => &a.params,
            Fm::SixDof(s) => &s.params,
        }
    }

    pub fn stick(&self) -> (f32, f32) {
        match self {
            Fm::Original(a) => a.stick(),
            Fm::SixDof(s) => s.stick(),
        }
    }

    /// The roll trim and the stick the roll command takes (the 6-DoF has no roll trim: the stick itself).
    pub fn roll_trim(&self) -> f32 {
        self.original_ref().map_or(0.0, |a| a.roll_trim())
    }

    pub fn roll_stick(&self) -> f32 {
        match self {
            Fm::Original(a) => a.roll_stick(),
            Fm::SixDof(s) => s.stick().0,
        }
    }

    pub fn engine_on(&self) -> bool {
        match self {
            Fm::Original(a) => a.engine_on,
            Fm::SixDof(s) => s.engine_on,
        }
    }

    pub fn vortex(&self) -> bool {
        self.original_ref().is_some_and(|a| a.vortex)
    }

    pub fn ground_height(&self) -> f32 {
        match self {
            Fm::Original(a) => a.ground_height,
            Fm::SixDof(s) => s.ground_height,
        }
    }

    pub fn gear_clearance(&self) -> f32 {
        match self {
            Fm::Original(a) => a.gear_clearance,
            Fm::SixDof(s) => s.gear_clearance,
        }
    }

    pub fn internal_fuel_kg(&self) -> f32 {
        match self {
            Fm::Original(a) => a.internal_fuel_kg(),
            Fm::SixDof(s) => s.internal_fuel_kg(),
        }
    }

    pub fn fuel_capacity_kg(&self) -> f32 {
        match self {
            Fm::Original(a) => a.fuel_capacity_kg(),
            Fm::SixDof(s) => s.fuel_capacity_kg(),
        }
    }

    pub fn fuel_flow(&self) -> f32 {
        match self {
            Fm::Original(a) => a.fuel_flow,
            Fm::SixDof(s) => s.fuel_flow,
        }
    }

    pub fn set_ground_height(&mut self, h: f32) {
        match self {
            Fm::Original(a) => a.ground_height = h,
            Fm::SixDof(s) => s.set_ground_height(h),
        }
    }

    pub fn set_engine_on(&mut self, on: bool) {
        match self {
            Fm::Original(a) => a.set_engine(on),
            Fm::SixDof(s) => s.set_engine_on(on),
        }
    }

    /// The "start engine" command (the 6-DoF's start sequence); the original model starts by any throttle command.
    pub fn start_engine(&mut self) {
        if let Fm::SixDof(s) = self {
            s.start_engine();
        }
    }

    /// One start-up checklist step by its key (the 6-DoF's, IAF 2026's start-up mission); the original model none.
    pub fn start_step(&mut self, step: &str) -> Result<(), &'static str> {
        match self {
            Fm::SixDof(s) => s.start_step(step),
            Fm::Original(_) => Ok(()),
        }
    }

    /// The electrical power (0 none, 1 the battery, 2 the displays up): the original model's is always up.
    pub fn power(&self) -> u8 {
        match self {
            Fm::Original(_) => 2,
            Fm::SixDof(s) => s.power(),
        }
    }

    /// The avionics up: always in the original model.
    pub fn avionics(&self) -> bool {
        match self {
            Fm::Original(_) => true,
            Fm::SixDof(s) => s.avionics(),
        }
    }

    /// The start sequence's step: "" in the original model.
    pub fn start_phase(&self) -> &'static str {
        match self {
            Fm::Original(_) => "",
            Fm::SixDof(s) => s.start_phase(),
        }
    }

    pub fn set_fuel(&mut self, kg: f32) {
        match self {
            Fm::Original(a) => a.set_fuel(kg),
            Fm::SixDof(s) => s.set_fuel(kg),
        }
    }

    pub fn set_fuel_capacity(&mut self, extra_kg: f32) {
        match self {
            Fm::Original(a) => a.set_fuel_capacity(extra_kg),
            Fm::SixDof(s) => s.set_fuel_capacity(extra_kg),
        }
    }

    pub fn set_stores(&mut self, mass_kg: f32, di_left: f32, di_right: f32) {
        match self {
            Fm::Original(a) => a.set_stores(mass_kg, di_left, di_right),
            Fm::SixDof(s) => s.set_stores(mass_kg, di_left, di_right),
        }
    }

    pub fn set_unlimited_fuel(&mut self, on: bool) {
        match self {
            Fm::Original(a) => a.unlimited_fuel = on,
            Fm::SixDof(s) => s.unlimited_fuel = on,
        }
    }
}

impl Host for Fm {
    fn ap_view(&self) -> ApView {
        match self {
            Fm::Original(a) => a.ap_view(),
            Fm::SixDof(s) => s.ap_view(),
        }
    }
    fn vmin(&self, alt: f32, g: f32) -> f32 {
        match self {
            Fm::Original(a) => a.vmin(alt, g),
            Fm::SixDof(s) => s.vmin(alt, g),
        }
    }
    fn controls(&self) -> Controls {
        match self {
            Fm::Original(a) => a.controls(),
            Fm::SixDof(s) => s.controls(),
        }
    }
    fn set_controls(&mut self, c: Controls) {
        match self {
            Fm::Original(a) => a.set_controls(c),
            Fm::SixDof(s) => s.set_controls(c),
        }
    }
    fn set_stores_trim(&mut self, on: bool) {
        match self {
            Fm::Original(a) => a.stores_trim = on,
            Fm::SixDof(s) => s.set_ap_flying(on),
        }
    }
    fn set_ai_since(&mut self, t: f64) {
        if let Fm::Original(a) = self {
            a.ai_since = t;
        }
    }
    fn set_ai_mode(&mut self, mode: u8) {
        if let Fm::Original(a) = self {
            a.ai_mode = mode;
        }
    }
    fn replace_on_ground(&mut self, x: f64, y: f64, heading: f32) {
        match self {
            Fm::Original(a) => a.replace_on_ground(x, y, heading),
            Fm::SixDof(s) => s.replace_on_ground(x, y, heading),
        }
    }
    fn set_pivot(&mut self, target: Option<f32>) {
        match self {
            Fm::Original(a) => a.set_pivot(target),
            Fm::SixDof(s) => s.set_pivot(target),
        }
    }
    fn engine_off(&mut self) {
        match self {
            Fm::Original(a) => a.engine_off(),
            Fm::SixDof(s) => s.engine_off(),
        }
    }
}
