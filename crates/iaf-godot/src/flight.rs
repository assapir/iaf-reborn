//! `IafFlight`: the original flight model exposed to GDScript.
//!
//! Godot frame: X east, Y up, Z south (−north), metres — the same frame as the terrain.

use godot::prelude::*;
use iaf_flight::{Aircraft, Controls};

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
    /// Loads `section` (e.g. "F-16") from `<install>/resource/md` and starts airborne at `position`
    /// (Godot frame), `heading_deg` (clockwise from north) and `speed` (m/s). `real_data` picks the
    /// corrected real-world data set instead of the original 1998 numbers (chosen before the flight).
    /// Returns an error string or "" on success.
    #[func]
    fn start(&mut self, install: GString, section: GString, position: Vector3, heading_deg: f64, speed: f64, real_data: bool) -> GString {
        let set = if real_data { iaf_flight::DataSet::Real } else { iaf_flight::DataSet::Original };
        match iaf_flight::load_with(std::path::Path::new(&install.to_string()), &section.to_string(), set) {
            Ok((params, envelope)) => {
                let enu = [position.x as f64, -position.z as f64, position.y as f64];
                self.aircraft = Some(Aircraft::new(params, envelope, enu, (heading_deg as f32).to_radians(), speed as f32));
                GString::new()
            }
            Err(e) => GString::from(e.as_str()),
        }
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
        d
    }
}
