//! `IafRadar`: the player's radar (`iaf_avionics::radar`, docs/radar.md) for `shared/weapons/radar.gd`.
//!
//! `set_input` hands over the own jet, the units and the terrain before a call that can scan; `state()` and
//! `events()` read the result back.

use crate::world::{get, terrain, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::radar::{Contact, Event, Fcr, Input, Own, Radar, Tms, Unit};

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRadar {
    radar: Option<Radar>,
    own: Own,
    units: Vec<Unit>,
    terrain: Option<Callable>,
}

impl IafRadar {
    /// Runs `f` on the radar with the last input; a no-op before `setup`.
    fn with<R: Default>(&mut self, f: impl FnOnce(&mut Radar, &Input) -> R) -> R {
        let terrain = terrain(self.terrain.clone());
        let input = Input { own: self.own, units: &self.units, terrain: &terrain };
        self.radar.as_mut().map(|r| f(r, &input)).unwrap_or_default()
    }
}

fn contact(r: &Radar, c: &Contact) -> VarDictionary {
    vdict! {
        "key" => c.key.as_str(),
        "pos" => vector3(c.pos),
        "heading" => c.heading,
        "locked" => r.is_locked(c),
        "selected" => r.is_selected(c),
        "hostile" => c.hostile,
        "prio" => c.priority(),
        "aspect" => c.aspect,
        "az" => c.az,
        "el" => c.el,
        "dist" => c.dist,
        "speed" => c.speed_kt,
        "type" => c.type_code,
        "alt" => c.pos.z,
        "mach" => c.mach,
        "closure" => c.closure_kt,
        "age" => r.now() - c.seen,
        "scope" => { let (x, y) = r.scope_xy(c); Vector2::new(x as f32, y as f32) },
    }
}

fn record(r: &Radar, c: Option<&Contact>) -> VarDictionary {
    c.map(|c| contact(r, c)).unwrap_or_default()
}

fn unit(u: &VarDictionary) -> Unit {
    Unit {
        key: get::<GString>(u, "key").unwrap_or_default().to_string(),
        pos: vec3(get(u, "pos").unwrap_or_default()),
        vel: vec3(get(u, "vel").unwrap_or_default()),
        class: get(u, "klass").unwrap_or(-1),
        state: get(u, "state").unwrap_or(1),
        coll_radius: get(u, "coll_radius").unwrap_or_default(),
        heading: get(u, "heading").unwrap_or_default(),
        type_code: get(u, "type").unwrap_or(-1),
        hostile: get(u, "hostile").unwrap_or(true),
    }
}

#[godot_api]
impl IafRadar {
    /// Create (`FUN_004ace60`) for cockpit index `cockpit` (`FUN_00447e70`); `lrs_nm` > 0: the LRS / STT detection
    /// range (Weapon data Real); `sam_tracks` > 0: ours, the real F-16 FCR (the aircraft definition's `radar.fcr`);
    /// `ours`: Modern IAF's power rules.
    #[func]
    fn setup(&mut self, cockpit: i64, lrs_nm: f64, sam_tracks: i64, ours: bool) {
        let fcr = usize::try_from(sam_tracks).ok().filter(|&n| n > 0).map(|sam_tracks| Fcr { sam_tracks });
        let lrs = (lrs_nm > 0.0).then_some(lrs_nm);
        self.radar = Some(Radar::new(usize::try_from(cockpit).unwrap_or(1), lrs, fcr, ours));
    }

    /// The own jet {pos, fwd, yaw}, the units [{key, pos, vel, klass, state, coll_radius, heading, type, hostile}]
    /// and the terrain (Callable(Vector3) -> float or null) for the next calls.
    #[func]
    fn set_input(&mut self, own: VarDictionary, units: VarArray, terrain: Callable) {
        self.own = Own {
            pos: vec3(get(&own, "pos").unwrap_or_default()),
            fwd: vec3(get(&own, "fwd").unwrap_or_default()),
            yaw: get(&own, "yaw").unwrap_or_default(),
            up: vec3(get(&own, "up").unwrap_or_default()),
            vel: vec3(get(&own, "vel").unwrap_or_default()),
            wow: get(&own, "wow").unwrap_or_default(),
        };
        self.units = units.iter_shared().filter_map(|v| v.try_to::<VarDictionary>().ok()).map(|u| unit(&u)).collect();
        self.terrain = Some(terrain);
    }

    /// The terrain line of sight from `a` to `b` (world points; terrain: Callable(Vector3) -> float or null), the
    /// radar's (`iaf_avionics::radar::line_of_sight`): the ground units' sensors and fire use it too.
    #[func]
    fn line_of_sight(a: Vector3, b: Vector3, terrain: Callable) -> bool {
        iaf_avionics::radar::line_of_sight(vec3(a), vec3(b), &crate::world::terrain(Some(terrain)))
    }

    #[func]
    fn update(&mut self, now: f64) {
        self.with(|r, i| r.update(now, i));
    }

    #[func]
    fn scan(&mut self, now: f64) {
        self.with(|r, i| r.scan(now, i));
    }

    #[func]
    fn cycle_mode(&mut self, now: f64) {
        self.with(|r, i| r.cycle_mode(now, i));
    }

    #[func]
    fn toggle_aa_ag(&mut self, now: f64) {
        self.with(|r, i| r.toggle_aa_ag(now, i));
    }

    #[func]
    fn step_range(&mut self, step: i64, now: f64) {
        let step = if step < 0 { -1 } else { 1 };
        self.with(|r, i| r.step_range(step, now, i));
    }

    #[func]
    fn deselect(&mut self, now: f64) {
        self.with(|r, i| r.deselect(now, i));
    }

    #[func]
    fn designate(&mut self, point: Vector3, now: f64) {
        self.with(|r, i| r.designate(vec3(point), now, i));
    }

    #[func]
    fn standby(&mut self) {
        self.with(|r, _| r.standby());
    }

    #[func]
    fn boresight(&mut self, down: bool) {
        self.with(|r, _| r.boresight(down));
    }

    #[func]
    fn next_target(&mut self, forward: bool) {
        self.with(|r, _| r.next_target(forward));
    }

    #[func]
    fn lock_key(&mut self, key: GString) -> bool {
        self.with(|r, _| r.lock_key(&key.to_string()))
    }

    #[func]
    fn select_key(&mut self, key: GString) -> bool {
        self.with(|r, _| r.select_key(&key.to_string()))
    }

    #[func]
    fn lock_stt(&mut self) {
        self.with(|r, _| r.lock_stt());
    }

    #[func]
    fn toggle_exp(&mut self) {
        self.with(|r, _| r.toggle_exp());
    }

    /// Ours, the real FCR: the TMS (0 up, 1 down, 2 right, 3 left).
    #[func]
    fn tms(&mut self, dir: i64, now: f64) {
        let dir = match dir {
            0 => Tms::Up,
            1 => Tms::Down,
            2 => Tms::Right,
            _ => Tms::Left,
        };
        self.with(|r, i| r.tms(dir, now, i));
    }

    /// Ours, the real FCR: OSB 2's submode / pattern.
    #[func]
    fn cycle_submode(&mut self, now: f64) {
        self.with(|r, i| r.cycle_submode(now, i));
    }

    /// Ours, the real FCR: OSB 18 (azimuth) or OSB 17 (`bars`).
    #[func]
    fn step_scan(&mut self, bars: bool) {
        self.with(|r, _| r.step_scan(bars));
    }

    /// Ours, the real FCR: the antenna elevation thumbwheel (−1..1, 0 stops).
    #[func]
    fn set_elevation_rate(&mut self, rate: f64) {
        self.with(|r, _| r.set_slews(Some(rate), None));
    }

    /// Ours, the real FCR: the cursor's slew (x right, y up, −1..1).
    #[func]
    fn set_cursor_slew(&mut self, x: f64, y: f64) {
        self.with(|r, _| r.set_slews(None, Some((x, y))));
    }

    /// Ours, the real FCR: the cursor at a place on the scope (0..1 across, up).
    #[func]
    fn set_cursor(&mut self, x: f64, y: f64) {
        self.with(|r, _| r.set_cursor(x, y));
    }

    /// Ours, the real FCR: a press on the CNTL page's OSB.
    #[func]
    fn cntl_press(&mut self, osb: i64) {
        self.with(|r, _| r.cntl_press(osb as u8));
    }

    /// The CNTL page's options: [osb, legend, values…] each, in the `cntl` state's order.
    #[func]
    fn cntl_table() -> VarArray {
        iaf_avionics::radar::CNTL
            .iter()
            .map(|(osb, name, vals)| {
                let mut a = varray![*osb as i64, *name];
                for v in vals.iter() {
                    a.push(&v.to_variant());
                }
                a.to_variant()
            })
            .collect()
    }

    /// Ours, the real FCR: OSB 4 OVRD.
    #[func]
    fn toggle_ovrd(&mut self) {
        self.with(|r, _| r.toggle_ovrd());
    }

    #[func]
    fn set_damaged(&mut self, on: bool) {
        self.with(|r, _| r.set_damaged(on));
    }

    /// Everything the cockpit and the weapons read: mode, last_aa, aa, off, damaged, bore_held, sel_key, sel_locked,
    /// contacts, stt ({} none), locked ({} none: the HUD / gun / seeker target), has_lock, antenna, heading_shift,
    /// designated, desig, exp, modes {mode: {max, nm, idx}}, range_index, range_m, scope_width.
    #[func]
    fn state(&self) -> VarDictionary {
        let Some(r) = &self.radar else { return VarDictionary::new() };
        let contacts: VarArray = r.contacts().iter().map(|c| contact(r, c).to_variant()).collect();
        let mut modes = VarDictionary::new();
        for (m, range) in r.ranges().iter() {
            modes.set(m as i64, &vdict! { "max" => range.max, "nm" => range.nm, "idx" => range.index });
        }
        let selection = r.selection();
        let (az, el) = r.antenna();
        let real = r.real().map_or_else(VarDictionary::new, |x| {
            let (half, bars) = x.scan(r.mode() == iaf_avionics::radar::Mode::Tws);
            let v = r.volume();
            let alt = r.cursor_alt(self.own.pos.z);
            vdict! {
                "half" => half,
                "bars" => bars,
                "elevation" => x.elevation,
                "cursor" => r.cursor_xy().map_or(Vector2::ZERO, |(cx, cy)| Vector2::new(cx as f32, cy as f32)),
                "cursor_alt" => alt.map_or(Vector2::new(f32::NAN, f32::NAN), |(h, l)| {
                    Vector2::new(h as f32, l as f32)
                }),
                "vsr" => x.vsr,
                "sam" => &x.sam.iter().map(|k| k.to_variant()).collect::<VarArray>(),
                "acm" => x.acm as i64,
                "ovrd" => x.ovrd,
                "volume" => v.map_or(Vector4::ZERO, |v| {
                    Vector4::new((v.az - v.half) as f32, (v.az + v.half) as f32, v.lo as f32, v.hi as f32)
                }),
                "vsr_max" => iaf_avionics::radar::VSR_MAX_KT,
                "exp" => r.exp_centre().is_some(),
                "cntl" => &x.cntl.iter().map(|&v| v as i64).collect::<PackedInt64Array>(),
                "history" => &r
                    .history_xy()
                    .iter()
                    .enumerate()
                    .flat_map(|(age, f)| f.iter().map(move |&(hx, hy)| Vector3::new(hx as f32, hy as f32, age as f32 + 1.0)))
                    .collect::<PackedVector3Array>(),
            }
        });
        vdict! {
            "mode" => r.mode() as i64,
            "last_aa" => r.last_aa() as i64,
            "aa" => r.air_to_air(),
            "off" => !r.mode().radiating(),
            "emit" => r.radiating(),
            "real" => &real,
            "damaged" => r.damaged(),
            "bore_held" => r.bore_held(),
            "sel_key" => selection.map_or("", |s| s.key.as_str()),
            "sel_locked" => selection.is_some_and(|s| s.locked),
            "contacts" => &contacts,
            "stt" => &record(r, r.stt()),
            "locked" => &record(r, r.locked()),
            "has_lock" => r.has_lock(),
            "antenna" => Vector2::new(az as f32, el as f32),
            "heading_shift" => r.heading_shift(),
            "designated" => r.designated().is_some(),
            "desig" => vector3(r.designated().unwrap_or_default()),
            "exp" => r.expanded(),
            "modes" => &modes,
            "range_index" => r.range_index(),
            "range_m" => r.range_m(),
            "scope_width" => r.scope_width(),
        }
    }

    /// The events since the last call, in order: ["lock", key, on] (the target's RWR), ["illum"] (`FUN_00458130`,
    /// the semi-active missiles lose their guidance) or ["detected", key] (the scan recorded the unit).
    #[func]
    fn events(&mut self) -> VarArray {
        let Some(r) = &mut self.radar else { return VarArray::new() };
        r.take_events()
            .into_iter()
            .map(|e| match e {
                Event::Lock { key, on } => varray!["lock", key, on],
                Event::IlluminationLost => varray!["illum"],
                Event::Detected { key } => varray!["detected", key],
            })
            .map(|a| a.to_variant())
            .collect()
    }
}
