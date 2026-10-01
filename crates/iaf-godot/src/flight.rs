//! `IafFlight`: the original flight model exposed to GDScript.
//!
//! Godot frame: X east, Y up, Z south (−north), metres — the same frame as the terrain.

use godot::prelude::*;
use iaf_flight::airbase::Airbase;
use iaf_flight::autopilot::{self, Autopilot, Leader, Waypoint};
use iaf_flight::{Aircraft, Controls, Start};

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafFlight {
    aircraft: Option<Aircraft>,
    /// The AI's autopilot (docs/ai.md), in the FM's frame: world minus `origin`.
    ap: Option<Autopilot>,
    origin: (f64, f64),
    /// Terrain height at a scene position (Callable(Vector3) -> float).
    ground: Option<Callable>,
}

/// Godot scene position → the FM's ENU frame.
fn to_enu(v: Vector3) -> [f64; 3] {
    [v.x as f64, -v.z as f64, v.y as f64]
}

/// ENU (east, north, up) → Godot (x, y, z) = (east, up, −north).
fn to_godot(v: [f64; 3]) -> Vector3 {
    Vector3::new(v[0] as f32, v[2] as f32, -v[1] as f32)
}

#[godot_api]
impl IafFlight {
    /// Loads `section` (e.g. "F-16") from `<install>/resource/md` and starts it (`FUN_005a5820`,
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

    /// The start rule's base tests (`FUN_005a5820`, docs/ai.md §7.1): the base is the one whose lineup point
    /// (iaf.ibx) is nearest; x = at the base (within 5000 m horizontally and 15 m vertically of its tower),
    /// y = the engine runs (within 100 m of its lineup point). World coordinates.
    #[func]
    fn start_rule(install: GString, x: f64, y: f64, z: f64) -> Vector2i {
        let path = std::path::PathBuf::from(install.to_string()).join("iaf.ibx");
        let bases = std::fs::read(path).map(|b| Airbase::load_all(&b)).unwrap_or_default();
        let Some(b) = Airbase::nearest(&bases, [x as f32, y as f32, z as f32]) else { return Vector2i::ZERO };
        let near = (b.tower[0] as f64 - x).hypot(b.tower[1] as f64 - y) < 5000.0 && (z - b.tower[2] as f64).abs() < 15.0;
        let engine = (b.lineup[0] as f64 - x).hypot(b.lineup[1] as f64 - y) <= 100.0;
        Vector2i::new(near as i32, engine as i32)
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
    /// landing check fails above 10° of slope), water and rough ground (terraintype.dat, §15.6).
    #[func]
    fn set_ground_surface(&mut self, normal_z: f64, water: bool, rough: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.ground_normal_z = normal_z as f32;
            ac.ground_water = water;
            ac.ground_rough = rough;
        }
    }

    /// Drag chute deployed (Shift+B on the ground): its drag under the Real data set (`Params::chute_cd`).
    #[func]
    fn set_drag_chute(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.drag_chute = on;
        }
    }

    /// "Better physics" option: opt-in fixes of original quirks (docs/flight-model.md §10, §15.11).
    #[func]
    fn set_better_physics(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_better_physics(on);
        }
    }

    /// One "better physics" option by its id (see `better_options`); set the start options right
    /// after `start`. Returns false for an unknown id.
    #[func]
    fn set_better_option(&mut self, name: GString, on: bool) -> bool {
        self.aircraft.as_mut().is_some_and(|ac| ac.set_better_option(&name.to_string(), on))
    }

    /// The ids of the "better physics" options (stable snake_case, menu order).
    #[func]
    fn better_options() -> PackedStringArray {
        iaf_flight::BetterPhysics::OPTIONS.iter().map(|(id, _)| GString::from(*id)).collect()
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

    /// External stores (docs/weapons.md "Weight and drag"): extra mass `S+0x424` in kg and the left /
    /// right wing stores drag index `S+0x42c` / `S+0x428` (×1e-4 applied). Read at the next aero update.
    #[func]
    fn set_stores(&mut self, mass_kg: f64, di_left: f64, di_right: f64) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_stores(mass_kg as f32, di_left as f32, di_right as f32);
        }
    }

    /// External fuel tanks at the start: fuel maximum = FuelWeight + `extra_kg`, filled (FUN_005a8980
    /// then the start, docs/weapons.md "Fuel tanks").
    #[func]
    fn set_fuel_capacity(&mut self, extra_kg: f64) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_fuel_capacity(extra_kg as f32);
        }
    }

    /// Motion 0x18: fuel and its maximum := `kg` (tank jettison).
    #[func]
    fn set_fuel(&mut self, kg: f64) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_fuel(kg as f32);
        }
    }

    /// Engine running or off (a ground start begins with the engine off).
    #[func]
    fn set_engine_on(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_engine(on);
        }
    }

    // --- AI (docs/ai.md) ------------------------------------------------------------------------------

    /// An AI jet: the FM's AI "team" test (not on the player's side) and the Preferences AI level (0..2).
    #[func]
    fn set_ai(&mut self, team: bool, level: i64) {
        if let Some(ac) = &mut self.aircraft {
            ac.ai_team = team;
            ac.ai_level = level.clamp(0, 2) as u8;
        }
    }

    /// The AI jet's damage is ≤ 0.1 (crash immunity).
    #[func]
    fn set_ai_damage(&mut self, low: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.ai_low_damage = low;
        }
    }

    /// Current fuel flow, kg/s.
    #[func]
    fn fuel_flow(&self) -> f64 {
        self.aircraft.as_ref().map_or(0.0, |ac| ac.fuel_flow as f64)
    }

    /// Creates the autopilot: `[Autopilot]` of bd.ibx and the airbases of iaf.ibx; world coordinates (X east,
    /// Y north) are shifted by the terrain origin into the FM's frame.
    #[func]
    fn ap_setup(&mut self, install: GString, origin_x: f64, origin_y: f64) {
        let dir = std::path::PathBuf::from(install.to_string());
        let mut ap = Autopilot::new(autopilot::Config::load(&dir));
        let mut bases = std::fs::read(dir.join("iaf.ibx")).map(|b| Airbase::load_all(&b)).unwrap_or_default();
        let (ox, oy) = (origin_x as f32, origin_y as f32);
        for b in &mut bases {
            for p in [&mut b.tower, &mut b.lineup] {
                p[0] -= ox;
                p[1] -= oy;
            }
            for list in [&mut b.to_taxi, &mut b.from_taxi, &mut b.hangars, &mut b.to_hangar_turn, &mut b.from_hangar_turn] {
                for p in list.iter_mut() {
                    p.x -= ox;
                    p.y -= oy;
                }
            }
        }
        ap.bases = bases;
        ap.origin = [origin_x, origin_y];
        self.ap = Some(ap);
        self.origin = (origin_x, origin_y);
    }

    /// Terrain height for the control loops: Callable(Vector3 scene position) -> float.
    #[func]
    fn ap_set_ground(&mut self, f: Callable) {
        self.ground = Some(f);
    }

    /// The formation's route: [X, Y, alt, T, action] per waypoint (world coordinates, T = arrival time s).
    #[func]
    fn ap_set_route(&mut self, flat: PackedFloat64Array) {
        let (ox, oy) = self.origin;
        if let Some(ap) = &mut self.ap {
            ap.route = flat
                .as_slice()
                .chunks_exact(5)
                .map(|w| Waypoint { x: w[0] - ox, y: w[1] - oy, z: w[2], t: w[3], action: w[4] as i32 })
                .collect();
        }
    }

    /// `setMode` (docs/ai.md §5, §8.1); an identical mode is ignored.
    #[func]
    fn ap_set_mode(&mut self, mode: i64, _now: f64) {
        if let (Some(ap), Some(ac)) = (&mut self.ap, &mut self.aircraft) {
            ap.set_mode(ac, mode.clamp(0, 255) as u8);
        }
    }

    #[func]
    fn ap_mode(&self) -> i64 {
        self.ap.as_ref().map_or(0, |ap| ap.mode() as i64)
    }

    /// Runs the control loop's tick when due (call before `step`). Returns the commands the tick posted (keys
    /// stick_x / stick_y (pull +), throttle, rudder, gear_down, flaps, brakes, ap_key; absent = not posted), which
    /// the player's host mirrors on its levers (docs/autopilot.md).
    #[func]
    fn ap_step(&mut self, _now: f64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let (Some(ap), Some(ac)) = (&mut self.ap, &mut self.aircraft) else { return d };
        let ground = self.ground.clone();
        let g = move |x: f64, y: f64| -> f32 {
            match &ground {
                Some(f) => f.call(&[Vector3::new(x as f32, 0.0, -y as f32).to_variant()]).try_to::<f32>().unwrap_or(-1.0e9),
                None => 0.0,
            }
        };
        let o = ap.step(ac, &g);
        if let Some((y, x)) = o.stick {
            d.set("stick_x", x);
            d.set("stick_y", -y);
        }
        if let Some(t) = o.thr {
            d.set("throttle", t);
        }
        if let Some(r) = o.rudder {
            d.set("rudder", r);
        }
        if let Some(g) = o.gear {
            d.set("gear_down", g);
        }
        if let Some(f) = o.flaps {
            d.set("flaps", f);
        }
        if let Some(b) = o.brakes {
            d.set("brakes", b);
        }
        if o.ap_key {
            d.set("ap_key", true);
        }
        d
    }

    /// The player's autopilot (FM motion 0xf, `5a1e40`): 0 off, 1 level, 2 NAV to route waypoint `wp` (GoHome and
    /// the landing when its action is 7). Needs `ap_setup` and the route.
    #[func]
    fn ap_player_mode(&mut self, mode: i64, wp: i64) {
        if let (Some(ap), Some(ac)) = (&mut self.ap, &mut self.aircraft) {
            ap.player_mode(ac, mode.clamp(0, 2) as u8, wp.max(0) as usize);
        }
    }

    /// The control loop the player's autopilot runs, for logs and tests ("none" when off).
    #[func]
    fn ap_stage(&self) -> GString {
        self.ap.as_ref().map_or("none".into(), |ap| ap.stage()).as_str().into()
    }

    /// The current waypoint index (brain +0x88).
    #[func]
    fn ap_waypoint_index(&self) -> i64 {
        self.ap.as_ref().map_or(0, |ap| ap.wp_index as i64)
    }

    #[func]
    fn ap_set_waypoint_index(&mut self, i: i64) {
        if let Some(ap) = &mut self.ap {
            ap.wp_index = i.max(0) as usize;
        }
    }

    /// The formation leader (member 0) for the formation / taxi / take-off loops: scene position and
    /// velocity, attitude in degrees; `has` false = I lead (or no formation).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn ap_set_leader(&mut self, has: bool, active: bool, pos: Vector3, vel: Vector3, pitch: f64, roll: f64, heading: f64) {
        if let Some(ap) = &mut self.ap {
            ap.leader = has.then(|| Leader {
                pos: to_enu(pos),
                vel: to_enu(vel),
                att: [(pitch as f32).to_radians(), (roll as f32).to_radians(), (heading as f32).to_radians()],
                active,
            });
        }
    }

    /// The landing's StopPlane has run (the landed handler, controller +0xe0).
    #[func]
    fn ap_landed(&self) -> bool {
        self.ap.as_ref().is_some_and(|ap| ap.landed)
    }

    /// Frees every airbase hangar (a new mission, `54f920`).
    #[func]
    fn ap_reset_hangars() {
        autopilot::reset_hangars();
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
        d.set("speed", s.speed);
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
        d.set("mass_kg", s.mass_kg);
        d.set("internal_fuel_kg", ac.internal_fuel_kg());
        d.set("stalled", s.stalled);
        d.set("buffet", s.buffet);
        d.set("drag_x", s.drag_x);
        d.set("over_g", s.over_g);
        d.set("on_ground", s.on_ground);
        d.set("spinning", s.spinning);
        d.set("gear", s.gear);
        d.set("crashed", s.crashed.is_some());
        d.set("crash_reason", s.crashed.map_or("", |c| c.name()));
        // Successful gear-down touchdowns so far: the mission's landed handler fires on each (v1.1).
        d.set("landings", s.landings as i64);
        d.set("time", s.time);
        d.set("alpha", s.alpha);
        d.set("beta", s.beta);
        // The pilot's controls as the flight model holds them (the part animation reads these).
        let c = ac.controls();
        d.set("stick_x", c.stick_x);
        d.set("stick_y", c.stick_y);
        d.set("rudder", c.rudder);
        d.set("flaps", c.flaps);
        d.set("gear_down", c.gear_down);
        d.set("brakes", c.brakes);
        d.set("engine_on", ac.engine_on);
        d
    }
}
