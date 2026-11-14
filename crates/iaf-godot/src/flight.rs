//! `IafFlight`: the flight model exposed to GDScript: the original's, or the Modern IAF sim's 6-DoF when the flight
//! data asks for it (`iaf_flight::fm::Fm`).
//!
//! Godot frame: X east, Y up, Z south (−north), metres — the same frame as the terrain.

use godot::prelude::*;
use iaf_flight::airbase::Airbase;
use iaf_flight::autopilot::{self, Autopilot, Host, Leader, Waypoint};
use iaf_flight::fm::Fm;
use iaf_flight::{Aircraft, Controls, Start, Vec3};

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafFlight {
    aircraft: Option<Fm>,
    /// The AI's autopilot (docs/ai.md), in the FM's frame: world minus `origin`.
    ap: Option<Autopilot>,
    origin: (f64, f64),
    /// Terrain height at a scene position (Callable(Vector3) -> float).
    ground: Option<Callable>,
    /// The Better cockpit's engine temperatures (iaf_flight::instruments::EngineTemps).
    temps: iaf_flight::instruments::EngineTemps,
    /// The F-16 3D cockpit's turn needle and slip ball (iaf_flight::instruments::TurnSlip).
    turn_slip: iaf_flight::instruments::TurnSlip,
    /// The MiG-29 AoA / g meter's max-g memory (iaf_flight::instruments::g_memory); reset by `start`.
    g_max: f32,
}

/// Logs once per feature that the Modern IAF 6-DoF does not model it (modern-iaf/docs/flight-model.md §9.6).
fn sixdof_lacks(what: &'static str) {
    static SEEN: std::sync::Mutex<Vec<&'static str>> = std::sync::Mutex::new(Vec::new());
    let mut seen = SEEN.lock().unwrap_or_else(|e| e.into_inner());
    if !seen.contains(&what) {
        seen.push(what);
        godot_print!("IafFlight: the 6-DoF does not model {what} yet (modern-iaf/docs/flight-model.md §9.6)");
    }
}

/// Godot scene position → the FM's ENU frame.
fn to_enu(v: Vector3) -> Vec3 {
    Vec3::new(v.x as f64, -v.z as f64, v.y as f64)
}

/// ENU (east, north, up) → Godot (x, y, z) = (east, up, −north).
fn to_godot(v: Vec3) -> Vector3 {
    Vector3::new(v[0] as f32, v[2] as f32, -v[1] as f32)
}

#[godot_api]
impl IafFlight {
    /// Loads `section` (e.g. "F-16") from `<install>/resource/md` and starts it (`FUN_005a5820`,
    /// docs/flight-model.md §15.6.4) at `position` (Godot frame) with `attitude_deg` (pitch, roll,
    /// heading clockwise from north), and `velocity` (Godot frame, m/s; the horizontal speed is
    /// re-aimed along the heading). `flags` = {airborne, engine_on, real_data}: `airborne`: see
    /// `is_airborne_start`; a ground start has gear down, full flaps, brakes on, throttle 0, RPM 0
    /// and the engine running only if `engine_on`. `real_data` picks the corrected real-world data
    /// set (chosen before the flight); `f16_variant` / `f15_variant` (the Extras switches) pick the aircraft
    /// definition's flight-model type (`data_set::variant`: an F-16 as the F-16I on Sufa, docs/f16i.md), whatever the
    /// data set. `sixdof_data` (Physics "Flight model" on 6-DoF, docs/deviations.md §2): Modern IAF's own data
    /// folder, which a modern jet (`data_set::sixdof`) loads from in place of `install`, so its `Model = 6dof`
    /// sections fly the 6-DoF; "" or a 1998 jet: `install`. Returns an error string or "" on success.
    #[func]
    fn start(
        &mut self,
        install: GString,
        section: GString,
        position: Vector3,
        attitude_deg: Vector3,
        velocity: Vector3,
        flags: VarDictionary,
    ) -> GString {
        let flag = |k: &str| flags.get(k).is_some_and(|v| v.booleanize());
        let (airborne, engine_on, real_data) = (flag("airborne"), flag("engine_on"), flag("real_data"));
        let set = if real_data { iaf_flight::DataSet::Real } else { iaf_flight::DataSet::Original };
        // The game session's parameter blocks (iaf_flight::data_set::Blocks): this process is one session.
        static BLOCKS: std::sync::Mutex<iaf_flight::data_set::Blocks> =
            std::sync::Mutex::new(iaf_flight::data_set::Blocks::new());
        let mut blocks = BLOCKS.lock().unwrap_or_else(|e| e.into_inner());
        let section = section.to_string();
        let text = |k: &str| flags.get(k).and_then(|v| v.try_to::<GString>().ok()).unwrap_or_default().to_string();
        let (f16, f15) = (text("f16_variant"), text("f15_variant"));
        let switches = iaf_flight::airframe::Switches { f16: &f16, f15: &f15 };
        let name = iaf_flight::data_set::variant(&section, switches);
        let own = text("sixdof_data");
        let dir =
            if !own.is_empty() && iaf_flight::data_set::sixdof(&section, switches) { own } else { install.to_string() };
        match iaf_flight::load_in(std::path::Path::new(&dir), name, set, &mut blocks) {
            Ok((params, envelope)) => {
                let st = Start {
                    position: to_enu(position),
                    pitch: attitude_deg.x.to_radians(),
                    roll: attitude_deg.y.to_radians(),
                    heading: attitude_deg.z.to_radians(),
                    velocity: to_enu(velocity),
                    airborne,
                    engine_on,
                };
                self.aircraft = Some(Fm::start(name, params, envelope, st));
                self.g_max = 0.0;
                GString::new()
            }
            Err(e) => GString::from(e.as_str()),
        }
    }

    /// The flight-model name `start` takes for a bdb type code on the data in `install` (`iaf_flight::fm_name_in`,
    /// the Real or Original set): "F-16", "F-15", "F-35I"…; "" when that bd.ibx has no section for it. Modern IAF's
    /// player jets (Settings.fm_section in modern-iaf/sim_settings.gd).
    #[func]
    fn fm_type(install: GString, type_code: i64, real_data: bool) -> GString {
        let set = if real_data { iaf_flight::DataSet::Real } else { iaf_flight::DataSet::Original };
        iaf_flight::fm_name_in(std::path::Path::new(&install.to_string()), type_code, set).unwrap_or_default().into()
    }

    /// The start rule's base tests (`FUN_005a5820`, docs/ai.md §7.1): the base is the one whose lineup point
    /// (iaf.ibx) is nearest; x = at the base (within 5000 m horizontally and 15 m vertically of its tower),
    /// y = the engine runs (within 100 m of its lineup point). World coordinates.
    #[func]
    fn start_rule(install: GString, x: f64, y: f64, z: f64) -> Vector2i {
        let path = std::path::PathBuf::from(install.to_string()).join("iaf.ibx");
        let mut bases = std::fs::read(path).map(|b| Airbase::load_all(&b)).unwrap_or_default();
        crate::bases::map_airbases(&mut bases);
        let Some(b) = Airbase::nearest(&bases, [x as f32, y as f32, z as f32]) else { return Vector2i::ZERO };
        let near =
            (b.tower[0] as f64 - x).hypot(b.tower[1] as f64 - y) < 5000.0 && (z - b.tower[2] as f64).abs() < 15.0;
        let engine = (b.lineup[0] as f64 - x).hypot(b.lineup[1] as f64 - y) <= 100.0;
        Vector2i::new(near as i32, engine as i32)
    }

    /// The original's start decision: airborne ⇔ altitude > 800 m and not at a base.
    #[func]
    fn is_airborne_start(altitude: f64, near_base: bool) -> bool {
        Aircraft::start_is_airborne(altitude as f32, near_base)
    }

    /// Ours (Devices "Throttle rocker" = Roll trim): the rocker −1..1 held for `dt` s moves the roll trim.
    #[func]
    fn trim_roll(&mut self, rocker: f64, dt: f64) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.trim_roll(rocker as f32, dt as f32),
            Some(Fm::SixDof(s)) => s.trim_roll(rocker as f32, dt as f32),
            None => {}
        }
    }

    /// The roll trim −1..1 (stick units; 0 without a jet).
    #[func]
    fn roll_trim(&self) -> f64 {
        self.aircraft.as_ref().map_or(0.0, |ac| ac.roll_trim() as f64)
    }

    /// Stick x/y −1..1 (y: pull positive), rudder −1..1, throttle 0..1 (0.74 military, ≥0.75 AB).
    #[func]
    fn set_controls(&mut self, stick: Vector2, rudder: f64, throttle: f64, flaps: f64, gear_down: bool, brakes: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_controls(Controls {
                stick_x: stick.x,
                stick_y: stick.y,
                rudder: rudder as f32,
                throttle: throttle as f32,
                flaps: flaps as f32,
                gear_down,
                brakes,
            });
        }
    }

    /// The pilot's systems damage flags 0..24 (docs/damage.md §5.2, `player_damage.gd` flags) and whether the
    /// jet has two engines: engines / afterburner / fuel leak (thrust), hydraulics / total flight control
    /// (stick, spin).
    #[func]
    fn set_damage(&mut self, flags: VarArray, twin: bool) {
        let mask = (0..flags.len().min(25))
            .filter(|&i| flags.get(i).is_some_and(|v| v.booleanize()))
            .fold(0u32, |m, i| m | 1 << i);
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.set_damage(mask, twin),
            Some(Fm::SixDof(s)) => s.set_damage(mask, twin),
            None => {}
        }
    }

    /// Terrain elevation under the aircraft (metres).
    #[func]
    fn set_ground_height(&mut self, height: f64) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_ground_height(height as f32);
        }
    }

    /// The ground height passed in is scenery (a roof or a tree top, docs/scenery.md §4): meeting it is a crash.
    #[func]
    fn set_ground_obstacle(&mut self, on: bool) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.ground_obstacle = on,
            Some(Fm::SixDof(s)) => s.ground_obstacle = on,
            None => {}
        }
    }

    /// Height of the aircraft origin above its wheels (the model's `height` helper).
    #[func]
    fn set_gear_clearance(&mut self, metres: f64) {
        if let Some(ac) = self.aircraft.as_mut().and_then(Fm::original) {
            ac.gear_clearance = metres as f32;
        }
    }

    /// The mission's wind for Better physics `wind`: `knots` from `from_deg` (true); 0 knots for NO WIND
    /// (docs/flight-model.md §10).
    #[func]
    fn set_wind(&mut self, knots: f64, from_deg: f64) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.set_wind(knots as f32, from_deg as f32),
            Some(Fm::SixDof(s)) => s.set_wind(knots as f32, from_deg as f32),
            None => {}
        }
    }

    /// The true-size gear clearance (the `height` helper at scale 1) for the ground effect's wing height: the
    /// physics is the same in both world scales (docs/flight-model.md §10).
    #[func]
    fn set_true_gear_clearance(&mut self, metres: f64) {
        if let Some(ac) = self.aircraft.as_mut().and_then(Fm::original) {
            ac.true_clearance = Some(metres as f32);
        }
    }

    /// Terrain under the player's jet: the surface normal's vertical share `nz/|n|` (1 = flat; the
    /// landing check fails above 10° of slope) and the terraintype.dat flags (terrain.gd `surface_at`: water,
    /// runway, rough ground, map edge; docs/flight-model.md §15.6.2).
    #[func]
    fn set_ground_surface(&mut self, normal_z: f64, flags: i64) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => {
                ac.ground_normal_z = normal_z as f32;
                ac.ground_flags = Some(flags as u32);
            }
            Some(Fm::SixDof(s)) => s.set_ground_surface(normal_z as f32, flags as u32),
            None => {}
        }
    }

    /// Drag chute deployed (Shift+B on the ground): its drag under the Real data set (`Params::chute_cd`).
    #[func]
    fn set_drag_chute(&mut self, on: bool) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.drag_chute = on,
            Some(Fm::SixDof(_)) => sixdof_lacks("the drag chute"),
            None => {}
        }
    }

    /// "Better physics" option: opt-in fixes of original quirks (docs/flight-model.md §10, §15.11).
    #[func]
    fn set_better_physics(&mut self, on: bool) {
        if let Some(ac) = self.aircraft.as_mut().and_then(Fm::original) {
            ac.set_better_physics(on);
        }
    }

    /// One "better physics" option by its id (see `better_options`); set the start options right
    /// after `start`. Returns false for an unknown id.
    #[func]
    fn set_better_option(&mut self, name: GString, on: bool) -> bool {
        self.aircraft.as_mut().and_then(Fm::original).is_some_and(|ac| ac.set_better_option(&name.to_string(), on))
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
        if let Some(ac) = self.aircraft.as_mut().and_then(Fm::original) {
            ac.no_stalls = on;
        }
    }

    #[func]
    fn set_no_spins(&mut self, on: bool) {
        if let Some(ac) = self.aircraft.as_mut().and_then(Fm::original) {
            ac.no_spins = on;
        }
    }

    /// The player's autopilot is flying the landing (see `Aircraft::ap_landing`).
    #[func]
    fn set_ap_landing(&mut self, on: bool) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.ap_landing = on,
            Some(Fm::SixDof(s)) => s.ap_landing = on,
            None => {}
        }
    }

    #[func]
    fn set_easy_landing(&mut self, on: bool) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.easy_landing = on,
            Some(Fm::SixDof(s)) => s.easy_landing = on,
            None => {}
        }
    }

    #[func]
    fn set_invulnerable(&mut self, on: bool) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.invulnerable = on,
            Some(Fm::SixDof(s)) => s.no_crashes |= on,
            None => {}
        }
    }

    #[func]
    fn set_no_crashes(&mut self, on: bool) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.no_crashes = on,
            Some(Fm::SixDof(s)) => s.no_crashes = on,
            None => {}
        }
    }

    #[func]
    fn set_unlimited_fuel(&mut self, on: bool) {
        if let Some(ac) = &mut self.aircraft {
            ac.set_unlimited_fuel(on);
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

    /// Better physics "Asymmetric stores": the stores' lateral moment (kg·m, + right wing heavier) and the fuel tanks'
    /// at full fuel, after every `set_stores`. A change takes effect at once (an aero update) with the switch on and
    /// the jet airborne.
    #[func]
    fn set_stores_moment(&mut self, kg_m: f64, tanks_kg_m: f64) {
        match self.aircraft.as_mut() {
            Some(Fm::Original(ac)) => ac.set_stores_moment(kg_m as f32, tanks_kg_m as f32),
            Some(Fm::SixDof(s)) => s.set_stores_moment(kg_m as f32, tanks_kg_m as f32),
            None => {}
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
            ac.set_engine_on(on);
        }
    }

    /// Modern IAF's "start engine" command (its keys.json, command 200): the 6-DoF runs its jet's start sequence
    /// (modern-iaf/docs/training.md §7); nothing on the original model.
    #[func]
    fn start_engine(&mut self) {
        if let Some(ac) = &mut self.aircraft {
            ac.start_engine();
        }
    }

    /// Modern IAF's start-up checklist step by its key (commands 210–215, modern-iaf/docs/training.md §7.1):
    /// "main_power", "starter", "engine", "avionics", "ins", "canopy". The fault id of a step out of order, "" else.
    #[func]
    fn start_step(&mut self, step: GString) -> GString {
        let r = self.aircraft.as_mut().map_or(Ok(()), |ac| ac.start_step(&step.to_string()));
        GString::from(r.err().unwrap_or(""))
    }

    /// A start-up checklist switch (commands 210–215, modern-iaf/docs/cockpit.md §5.2) set: `want` 1 on, -1 off, 0
    /// the other way from its position. The fault id of a step out of order, "" else.
    #[func]
    fn start_switch(&mut self, step: GString, want: i64) -> GString {
        let want = want.signum() as i8;
        let r = self.aircraft.as_mut().map_or(Ok(()), |ac| ac.start_switch(&step.to_string(), want));
        GString::from(r.err().unwrap_or(""))
    }

    /// The position of start-up checklist step `step`'s switch (the one source the checklist and the cockpit read).
    #[func]
    fn start_on(&self, step: GString) -> bool {
        self.aircraft.as_ref().is_none_or(|ac| ac.start_on(&step.to_string()))
    }

    // --- AI (docs/ai.md) ------------------------------------------------------------------------------

    /// An AI jet: the FM's AI "team" test (not on the player's side) and the Preferences AI level (0..2).
    #[func]
    fn set_ai(&mut self, team: bool, level: i64) {
        if let Some(ac) = self.aircraft.as_mut().and_then(Fm::original) {
            ac.ai_team = team;
            ac.ai_level = level.clamp(0, 2) as u8;
        }
    }

    /// The AI jet's damage is ≤ 0.1 (crash immunity).
    #[func]
    fn set_ai_damage(&mut self, low: bool) {
        if let Some(ac) = self.aircraft.as_mut().and_then(Fm::original) {
            ac.ai_low_damage = low;
        }
    }

    /// Current fuel flow, kg/s.
    #[func]
    fn fuel_flow(&self) -> f64 {
        self.aircraft.as_ref().map_or(0.0, |ac| ac.fuel_flow() as f64)
    }

    /// Creates the autopilot: `[Autopilot]` of bd.ibx and the airbases of iaf.ibx; world coordinates (X east,
    /// Y north) are shifted by the terrain origin into the FM's frame.
    #[func]
    fn ap_setup(&mut self, install: GString, origin_x: f64, origin_y: f64) {
        let dir = std::path::PathBuf::from(install.to_string());
        let mut ap = Autopilot::new(autopilot::Config::load(&dir));
        let mut bases = std::fs::read(dir.join("iaf.ibx")).map(|b| Airbase::load_all(&b)).unwrap_or_default();
        crate::bases::map_airbases(&mut bases);
        let (ox, oy) = (origin_x as f32, origin_y as f32);
        for b in &mut bases {
            for p in [&mut b.tower, &mut b.lineup] {
                p[0] -= ox;
                p[1] -= oy;
            }
            for list in
                [&mut b.to_taxi, &mut b.from_taxi, &mut b.hangars, &mut b.to_hangar_turn, &mut b.from_hangar_turn]
            {
                for p in list.iter_mut() {
                    p.x -= ox;
                    p.y -= oy;
                }
            }
        }
        ap.bases = bases;
        ap.align_final = crate::bases::MOVES.read().unwrap().is_some();
        ap.origin = [origin_x, origin_y];
        self.ap = Some(ap);
        self.origin = (origin_x, origin_y);
    }

    /// The player's landing flare (`Autopilot::player_flare`, docs/autopilot.md §2.3): on when the player has left
    /// the original (World scale Real, Real flight data or a Better physics switch).
    #[func]
    fn ap_set_flare(&mut self, on: bool) {
        if let Some(ap) = &mut self.ap {
            ap.player_flare = on;
        }
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
                .as_chunks::<5>()
                .0
                .iter()
                .map(|w| Waypoint { x: w[0] - ox, y: w[1] - oy, z: w[2], t: w[3], action: w[4] as i32 })
                .collect();
        }
    }

    /// The mission editor's "takes off" rule: a take-off held by wp0's late planned time starts now (ours).
    #[func]
    fn ap_release_takeoff(&mut self, now: f64) {
        if let Some(ap) = &mut self.ap {
            ap.release_takeoff(now);
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
                Some(f) => {
                    f.call(&[Vector3::new(x as f32, 0.0, -y as f32).to_variant()]).try_to::<f32>().unwrap_or(-1.0e9)
                }
                None => 0.0,
            }
        };
        let o = ap.step(ac, &g);
        if o.release {
            d.set("release", true);
        }
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

    /// The HUD ILS deviations in degrees (x = localizer, y = glideslope; `iaf_flight::airbase::ils`, docs/cockpit.md
    /// "ILS") from the airbases of `ap_setup`; ZERO without them.
    #[func]
    fn ils(&self) -> Vector2 {
        self.ils_deg()
    }

    fn ils_deg(&self) -> Vector2 {
        let (Some(ap), Some(ac)) = (&self.ap, &self.aircraft) else { return Vector2::ZERO };
        let p = ac.state().position;
        match iaf_flight::airbase::ils(&ap.bases, [p[0] as f32, p[1] as f32, p[2] as f32]) {
            Some((loc, gs)) => Vector2::new(loc.to_degrees(), gs.to_degrees()),
            None => Vector2::ZERO,
        }
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
    /// velocity, attitude (pitch, roll, heading) in degrees; `has` false = I lead (or no formation).
    #[func]
    fn ap_set_leader(&mut self, has: bool, active: bool, pos: Vector3, vel: Vector3, attitude_deg: Vector3) {
        if let Some(ap) = &mut self.ap {
            ap.leader = has.then(|| Leader {
                pos: to_enu(pos),
                vel: to_enu(vel),
                att: [attitude_deg.x.to_radians(), attitude_deg.y.to_radians(), attitude_deg.z.to_radians()],
                active,
            });
        }
    }

    /// The combat manoeuvres' target (brain +0x70), as `ap_set_leader`; `has` false = none.
    #[func]
    fn ap_set_target(&mut self, has: bool, pos: Vector3, vel: Vector3, pitch: f64, roll: f64, heading: f64) {
        if let Some(ap) = &mut self.ap {
            ap.target = has.then(|| Leader {
                pos: to_enu(pos),
                vel: to_enu(vel),
                att: [(pitch as f32).to_radians(), (roll as f32).to_radians(), (heading as f32).to_radians()],
                active: true,
            });
        }
    }

    /// Dogchase has its nose on the aim point (condition 20 for the gun).
    #[func]
    fn ap_nose_on(&self) -> bool {
        self.ap.as_ref().is_some_and(|ap| ap.nose_on)
    }

    /// The landing's StopPlane has run (the landed handler, controller +0xe0).
    #[func]
    fn ap_landed(&self) -> bool {
        self.ap.as_ref().is_some_and(|ap| ap.landed)
    }

    /// TakeoffCL has finished above 100 m AGL (the AirborneReport, docs/radio.md §4).
    #[func]
    fn ap_airborne(&self) -> bool {
        self.ap.as_ref().is_some_and(|ap| ap.airborne)
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

    /// The cockpit state the panel / HUD / MFDs draw (iaf_flight::instruments, docs/cockpit.md): speeds in kt
    /// (`tas_kt`, `ground_kt`, `ias_kt`), `vs_fpm`, `agl_ft`, `fuel_fill`, and `engines` = [THROTTLE, RPM, TEMP]
    /// left then right (6 floats). `damage`: the player's damage flags 0..24 (docs/damage.md §5), or empty.
    /// Better cockpit (ours): `engines_better` (the same 6 floats from the FM's own values,
    /// `better_engine_needles`), `engine_temp_c` (2 floats, °C), `fuel_fill_total` (fuel / capacity with tanks),
    /// `nozzle_oil` (left nozzle %, left oil psi, then right; `nozzle_and_oil`), `fuel_flow_pph` (the FM's fuel
    /// flow, lb/h: the 3D cockpit's fuel flow indicator). The F-16 3D cockpit's (`TurnSlip`, docs/cockpit.md
    /// "3D cockpit"): `yaw_rate_dps` (the body yaw rate, °/s, right +), `lateral_g` / `normal_g` (the specific force
    /// along the right wing / the body's up axis, g), `cabin_alt_ft` (`cabin_altitude_ft`), `hyd_ab` (systems A, B:
    /// pressure / normal, `hydraulic_systems`).
    #[func]
    fn instruments(&mut self, damage: VarArray) -> VarDictionary {
        use iaf_flight::instruments::{self, EngineDamage};
        let mut d = VarDictionary::new();
        let Some(ac) = &self.aircraft else { return d };
        let flag = |i: usize| damage.get(i).is_some_and(|v| v.booleanize());
        let engine = |e: usize| EngineDamage {
            cut_out: flag(2 + e),
            fire: flag(16 + e),
            permanent: flag(22 + e),
            afterburner: flag(8 + e),
        };
        let dmg = [engine(0), engine(1)];
        let s = ac.state();
        let i = instruments::instruments(
            &s,
            ac.ground_height(),
            ac.gear_clearance(),
            ac.internal_fuel_kg(),
            ac.fuel_capacity_kg(),
            ac.params().ias_low_speed_fix,
            dmg,
        );
        let rpm = s.rpm * 0.01;
        let temps = self.temps.update(s.time, rpm, s.afterburner, dmg);
        let better: Vec<f32> =
            (0..2).flat_map(|e| instruments::better_engine_needles(rpm, s.afterburner, temps[e], dmg[e])).collect();
        d.set("engines_better", &PackedFloat32Array::from(better.as_slice()));
        d.set("engine_temp_c", &PackedFloat32Array::from(temps.as_slice()));
        let no: Vec<f32> = (0..2)
            .flat_map(|e| instruments::nozzle_and_oil(better[3 * e + 1], s.afterburner, s.gear <= 0.0, dmg[e]))
            .collect();
        d.set("nozzle_oil", &PackedFloat32Array::from(no.as_slice()));
        d.set("fuel_fill_total", i.fuel_fill_total);
        d.set("fuel_flow_pph", ac.fuel_flow() * 3600.0 / 0.45359);
        let v = Vec3::new(s.velocity[0] as f64, s.velocity[1] as f64, s.velocity[2] as f64);
        self.turn_slip.update(s.time, v, s.forward, s.right, s.up);
        d.set("yaw_rate_dps", self.turn_slip.yaw_rate_dps);
        d.set("lateral_g", self.turn_slip.lateral_g);
        d.set("normal_g", self.turn_slip.normal_g);
        d.set("cabin_alt_ft", instruments::cabin_altitude_ft(s.position[2] as f32 * 3.281));
        d.set("hyd_ab", &PackedFloat32Array::from(&instruments::hydraulic_systems(rpm, flag(18))[..]));
        d.set("tas_kt", i.tas_kt);
        d.set("ground_kt", i.ground_kt);
        d.set("ias_kt", i.ias_kt);
        d.set("vs_fpm", i.vs_fpm);
        d.set("agl_ft", i.agl_ft);
        d.set("fuel_fill", i.fuel_fill);
        d.set("engines", &PackedFloat32Array::from(i.engines.concat().as_slice()));
        d
    }

    /// Ours, the "Better cockpit" values (iaf_flight::instruments, docs/cockpit.md "Better cockpit"): `aoa_index`
    /// (0 no indexer, 1 slow, 2 on speed, 3 fast), the lamps `flcs`, `to_ldg_config` and `ar_nws`; the MiG gauges
    /// `fuel_l` / `fuel_l_total` (litres), `radalt_m` / `radalt_valid` / `radalt_danger`, `hyd` (kgf/cm²),
    /// `pnp_bars` (the ПНП's К / Г bars, −1..1) and `g_max` (the max-g memory). `damage`: as `instruments`.
    #[func]
    fn better_instruments(&mut self, damage: VarArray) -> VarDictionary {
        use iaf_flight::instruments;
        let mut d = VarDictionary::new();
        let Some(ac) = &self.aircraft else { return d };
        let s = ac.state();
        let flags: Vec<bool> = damage.iter_shared().map(|v| v.booleanize()).collect();
        let i = instruments::instruments(
            &s,
            ac.ground_height(),
            ac.gear_clearance(),
            ac.internal_fuel_kg(),
            ac.fuel_capacity_kg(),
            ac.params().ias_low_speed_fix,
            Default::default(),
        );
        let w = instruments::warnings(s.on_ground, s.position[2] as f32 * 3.281, i.ias_kt, i.vs_fpm, s.gear, &flags);
        d.set("aoa_index", instruments::aoa_indexer(ac.params().type_code, ac.indicated_aoa()) as i64);
        d.set("flcs", w.flcs);
        d.set("to_ldg_config", w.to_ldg_config);
        d.set("ar_nws", w.ar_nws);
        // The MiG gauges (docs/mig-cockpits.md §4): the litre fuel gauge, without / with the tanks.
        d.set("fuel_l", instruments::fuel_litres(s.fuel_kg, ac.internal_fuel_kg(), false));
        d.set("fuel_l_total", instruments::fuel_litres(s.fuel_kg, ac.internal_fuel_kg(), true));
        let (radalt_m, radalt_valid) = instruments::radar_altimeter(i.agl_ft, s.roll.to_degrees());
        d.set("radalt_m", radalt_m);
        d.set("radalt_valid", radalt_valid);
        d.set("radalt_danger", instruments::radar_alt_danger(radalt_m, radalt_valid));
        d.set("hyd", instruments::hydraulic_pressure(s.rpm * 0.01, flags.get(18).copied().unwrap_or(false)));
        let ils = self.ils_deg();
        let [k, g] = instruments::pnp_bars(ils.x, ils.y);
        d.set("pnp_bars", Vector2::new(k, g));
        self.g_max = instruments::g_memory(self.g_max, s.g, s.on_ground);
        d.set("g_max", self.g_max);
        d
    }

    /// Current state for the renderer and instruments.
    #[func]
    fn state(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(ac) = &self.aircraft else { return d };
        let s = ac.state();
        let v = s.velocity;
        d.set("position", to_godot(s.position));
        d.set("velocity", to_godot(Vec3::new(v[0] as f64, v[1] as f64, v[2] as f64)));
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
        if let Some(t) = ac.tef_deg() {
            d.set("tef", t); // the 6-DoF's trailing-edge flaps, deg down (the flaperons' droop)
        }
        d.set("aoa", ac.indicated_aoa()); // the cockpit's AoA: the 6-DoF's probe (modern-iaf/docs/cockpit.md §5.4)
        d.set("g", s.g);
        d.set("g_limit", ac.params().max_g_m1 + 1.0); // the flight data's MaxG (the F-15I row's +8.1)
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
        // The "Tornado" map-edge push-back and the EndWorld.wav count (docs/flight-model.md §15.5a).
        d.set("tornado", s.tornado);
        d.set("end_worlds", s.end_worlds as i64);
        d.set("time", s.time);
        d.set("alpha", s.alpha);
        d.set("beta", s.beta);
        // The pilot's controls as the flight model holds them (the part animation reads these).
        let c = ac.controls();
        // The stick the FM holds: on the ground a pedal event sets x = pedal, y = 0 (v1.1 59f5a0).
        let (sx, sy) = ac.stick();
        d.set("stick_x", sx);
        d.set("stick_y", sy);
        // Ours: the roll trim, and the stick the roll command takes in the air (stick + trim; the ailerons show it).
        d.set("roll_trim", ac.roll_trim());
        d.set("roll_stick", if s.on_ground { sx } else { ac.roll_stick() });
        d.set("rudder", c.rudder);
        d.set("flaps", c.flaps);
        d.set("gear_down", c.gear_down);
        d.set("brakes", c.brakes);
        d.set("engine_on", ac.engine_on());
        // The 6-DoF's ground start (modern-iaf/docs/training.md §7): power 0 none / 1 battery / 2 displays up, the
        // avionics up, each system up, the sequence's step. Absent for the original model (readers default to 2, true).
        if ac.original_ref().is_none() {
            d.set("power", ac.power() as i64);
            d.set("avionics", ac.avionics());
            // The F-16's per-system power switches each up (modern-iaf/docs/cockpit.md §5.2): name -> bool.
            let mut sys = VarDictionary::new();
            for n in iaf_flight::sixdof::start::SYSTEMS {
                sys.set(n, ac.system(n));
            }
            d.set("systems", &sys.to_variant());
            d.set("start_phase", ac.start_phase());
        }
        d.set("vortex", ac.vortex());
        // Which model flies (iaf_flight::fm::Fm): "original" or "6dof".
        d.set("model", if ac.original_ref().is_some() { "original" } else { "6dof" });
        d
    }
}
