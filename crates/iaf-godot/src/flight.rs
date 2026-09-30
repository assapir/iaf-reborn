//! `IafFlight`: the original flight model exposed to GDScript.
//!
//! Godot frame: X east, Y up, Z south (−north), metres — the same frame as the terrain.

use godot::prelude::*;
use iaf_flight::{Aircraft, Controls, Start};

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafFlight {
    aircraft: Option<Aircraft>,
}

/// ENU (east, north, up) → Godot (x, y, z) = (east, up, −north).
fn to_godot(v: [f64; 3]) -> Vector3 {
    Vector3::new(v[0] as f32, v[2] as f32, -v[1] as f32)
}

#[godot_api]
impl IafFlight {
    /// Loads `section` (e.g. "F-16") from `<install>/resource/md` and starts it (`FUN_005a2a10`,
    /// docs/flight-model.md §15.6.4) at `position` (Godot frame) with `heading_deg` (clockwise from
    /// north), `pitch_deg` / `roll_deg`, and `velocity` (Godot frame, m/s; the horizontal speed is
    /// re-aimed along the heading). `airborne`: see `is_airborne_start`; a ground start has gear
    /// down, full flaps, brakes on, throttle 0, RPM 0 and the engine running only if `engine_on`.
    /// `real_data` picks the corrected real-world data set (chosen before the flight).
    /// Returns an error string or "" on success.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn start(
        &mut self,
        install: GString,
        section: GString,
        position: Vector3,
        heading_deg: f64,
        pitch_deg: f64,
        roll_deg: f64,
        velocity: Vector3,
        airborne: bool,
        engine_on: bool,
        real_data: bool,
    ) -> GString {
        let set = if real_data { iaf_flight::DataSet::Real } else { iaf_flight::DataSet::Original };
        match iaf_flight::load_with(std::path::Path::new(&install.to_string()), &section.to_string(), set) {
            Ok((params, envelope)) => {
                let st = Start {
                    position: [position.x as f64, -position.z as f64, position.y as f64],
                    pitch: (pitch_deg as f32).to_radians(),
                    roll: (roll_deg as f32).to_radians(),
                    heading: (heading_deg as f32).to_radians(),
                    velocity: [velocity.x as f64, -velocity.z as f64, velocity.y as f64],
                    airborne,
                    engine_on,
                };
                self.aircraft = Some(Aircraft::start(params, envelope, st));
                GString::new()
            }
            Err(e) => GString::from(e.as_str()),
        }
    }

    /// The original's start decision: airborne ⇔ altitude > 800 m and not at a base.
    #[func]
    fn is_airborne_start(altitude: f64, near_base: bool) -> bool {
        Aircraft::start_is_airborne(altitude as f32, near_base)
    }

    /// Stick x/y −1..1 (y: pull positive), rudder −1..1, throttle 0..1 (0.74 military, ≥0.75 AB).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn set_controls(&mut self, stick_x: f64, stick_y: f64, rudder: f64, throttle: f64, flaps: f64, gear_down: bool, brakes: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_controls(Controls {
                stick_x: stick_x as f32,
                stick_y: stick_y as f32,
                rudder: rudder as f32,
                throttle: throttle as f32,
                flaps: flaps as f32,
                gear_down,
                brakes,
            });
        }
    }

    /// Terrain elevation under the aircraft (metres).
    #[func]
    fn set_ground_height(&mut self, height: f64) {
        if let Some(ac) = &mut self.aircraft {
            ac.ground_height = height as f32;
        }
    }

    /// Height of the aircraft origin above its wheels (the model's `height` helper).
    #[func]
    fn set_gear_clearance(&mut self, metres: f64) {
        if let Some(ac) = &mut self.aircraft {
            ac.gear_clearance = metres as f32;
        }
    }

    /// Terrain under the wheels: the surface normal's vertical share `nz/|n|` (1 = flat; the
    /// landing check fails above 10° of slope) and water (§15.6).
    #[func]
    fn set_ground_surface(&mut self, normal_z: f64, water: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.ground_normal_z = normal_z as f32;
            ac.ground_water = water;
        }
    }

    /// "Better physics" option: opt-in fixes of original quirks (docs/flight-model.md §10, §15.11).
    #[func]
    fn set_better_physics(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_better_physics(on);
        }
    }

    /// Preferences (docs/flight-model.md §15.7): No stalls, No spins, Easy landing, Invulnerable,
    /// No crashes, Unlimited fuel.
    #[func]
    fn set_no_stalls(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.no_stalls = on;
        }
    }

    #[func]
    fn set_no_spins(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.no_spins = on;
        }
    }

    #[func]
    fn set_easy_landing(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.easy_landing = on;
        }
    }

    #[func]
    fn set_invulnerable(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.invulnerable = on;
        }
    }

    #[func]
    fn set_no_crashes(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.no_crashes = on;
        }
    }

    #[func]
    fn set_unlimited_fuel(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.unlimited_fuel = on;
        }
    }

    /// Engine running or off (a ground start begins with the engine off).
    #[func]
    fn set_engine_on(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_engine(on);
        }
    }

    #[func]
    fn step(&mut self, dt: f64) {
        if let Some(ac) = &mut self.aircraft {
            ac.step(dt.clamp(0.0, 0.25));
        }
    }

    /// Current state for the renderer and instruments.
    #[func]
    fn state(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(ac) = &self.aircraft else { return d };
        let s = ac.state();
        let v = s.velocity;
        d.set("position", to_godot(s.position));
        d.set("velocity", to_godot([v[0] as f64, v[1] as f64, v[2] as f64]));
        d.set("forward", to_godot(s.forward));
        d.set("right", to_godot(s.right));
        d.set("up", to_godot(s.up));
        d.set("speed_kt", s.speed * 1.943844);
        d.set("mach", s.mach);
        d.set("alt_ft", s.position[2] as f32 * 3.28084);
        d.set("vs_fpm", v[2] * 196.85);
        d.set("pitch", s.pitch.to_degrees());
        d.set("roll", s.roll.to_degrees());
        d.set("heading", s.heading.to_degrees());
        d.set("aoa", s.alpha.to_degrees());
        d.set("g", s.g);
        d.set("rpm", s.rpm / 100.0);
        d.set("throttle", s.throttle);
        d.set("afterburner", s.afterburner as i64);
        d.set("fuel_lbs", s.fuel_kg / 0.45359);
        d.set("stalled", s.stalled);
        d.set("buffet", s.buffet);
        d.set("over_g", s.over_g);
        d.set("on_ground", s.on_ground);
        d.set("spinning", s.spinning);
        d.set("gear", s.gear);
        d.set("crashed", s.crashed.is_some());
        d.set("crash_reason", s.crashed.map_or("", |c| c.name()));
        if let Some(ac) = &self.aircraft {
            d.set("engine_on", ac.engine_on);
        }
        d
    }
}
