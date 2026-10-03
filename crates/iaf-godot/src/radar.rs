//! `IafRadar`: the player's radar (`iaf_avionics::radar`, docs/radar.md) for `game/weapons/radar.gd`.
//!
//! World frame X east, Y north, Z up (as the GDScript weapons). `set_input` hands over the own pose, the units and
//! the terrain before a call that can scan; `state()` and `events()` read the result back.

use godot::prelude::*;
use iaf_avionics::radar::{Contact, Event, Input, Own, Radar, Unit, V3};

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRadar {
    radar: Option<Radar>,
    own: Own,
    units: Vec<Unit>,
    /// Terrain height at a world point: Callable(Vector3) -> float or null.
    ground: Option<Callable>,
}

fn v3(v: Vector3) -> V3 {
    [v.x as f64, v.y as f64, v.z as f64]
}

fn gv(v: V3) -> Vector3 {
    Vector3::new(v[0] as f32, v[1] as f32, v[2] as f32)
}

fn get<T: FromGodot>(d: &VarDictionary, k: &str) -> Option<T> {
    d.get(k).and_then(|v| v.try_to::<T>().ok())
}

fn contact(c: &Contact) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("key", c.key.clone());
    d.set("pos", gv(c.pos));
    d.set("heading", c.heading);
    d.set("locked", c.locked);
    d.set("selected", c.selected);
    d.set("hostile", c.hostile);
    d.set("prio", c.prio);
    d.set("aspect", c.aspect);
    d.set("az", c.az);
    d.set("el", c.el);
    d.set("dist", c.dist);
    d.set("speed", c.speed);
    d.set("type", c.type_code);
    d.set("alt", c.alt);
    d
}

impl IafRadar {
    /// Runs `f` on the radar with this call's input.
    fn with<R: Default>(&mut self, f: impl FnOnce(&mut Radar, &Input) -> R) -> R {
        let ground = self.ground.clone().filter(|c| c.is_valid());
        let g = move |p: V3| -> Option<f64> {
            let v = ground.as_ref()?.call(&[gv(p).to_variant()]);
            v.try_to::<f64>().ok()
        };
        let inp = Input { own: self.own, units: &self.units, ground: &g };
        match &mut self.radar {
            Some(r) => f(r, &inp),
            None => R::default(),
        }
    }
}

#[godot_api]
impl IafRadar {
    /// Create (`FUN_004ace60`) for cockpit index `cockpit` (`FUN_00447e70`); `lrs_nm` > 0: the LRS / STT
    /// detection range (Weapon data Real).
    #[func]
    fn setup(&mut self, cockpit: i64, lrs_nm: f64) {
        self.radar = Some(Radar::new(cockpit.max(0) as usize, lrs_nm));
    }

    /// The own pose {pos, fwd, yaw}, the units [{key, pos, vel, klass, state, coll_radius, heading, type, hostile}]
    /// and the terrain for the next calls.
    #[func]
    fn set_input(&mut self, own: VarDictionary, units: VarArray, ground: Callable) {
        self.own = Own {
            pos: v3(get(&own, "pos").unwrap_or_default()),
            fwd: v3(get(&own, "fwd").unwrap_or_default()),
            yaw: get(&own, "yaw").unwrap_or_default(),
        };
        self.units = units
            .iter_shared()
            .filter_map(|v| v.try_to::<VarDictionary>().ok())
            .map(|u| Unit {
                key: get::<GString>(&u, "key").unwrap_or_default().to_string(),
                pos: v3(get(&u, "pos").unwrap_or_default()),
                vel: v3(get(&u, "vel").unwrap_or_default()),
                klass: get(&u, "klass").unwrap_or(-1),
                state: get(&u, "state").unwrap_or(1),
                coll_radius: get(&u, "coll_radius").unwrap_or(0.0),
                heading: get(&u, "heading").unwrap_or(0.0),
                type_code: get(&u, "type").unwrap_or(-1),
                hostile: get(&u, "hostile").unwrap_or(true),
            })
            .collect();
        self.ground = Some(ground);
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
    fn step_range(&mut self, d: i64, now: f64) {
        self.with(|r, i| r.step_range(d, now, i));
    }

    #[func]
    fn deselect(&mut self, now: f64) {
        self.with(|r, i| r.deselect(now, i));
    }

    #[func]
    fn designate(&mut self, p: Vector3, now: f64) {
        self.with(|r, i| r.designate(v3(p), now, i));
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
    fn lock_stt(&mut self) {
        self.with(|r, _| r.lock_stt());
    }

    #[func]
    fn toggle_exp(&mut self) {
        self.with(|r, _| r.toggle_exp());
    }

    #[func]
    fn set_damaged(&mut self, on: bool) {
        self.with(|r, _| r.set_damaged(on));
    }

    /// Everything the cockpit and the weapons read: mode, aa, off, damaged, dirty, sel_key, sel_locked, contacts,
    /// stt ({} none), locked ({} none: the HUD / gun / seeker target), has_lock, antenna, heading_shift,
    /// designated, desig, exp, modes {mode: {max, nm, idx}}, range_index, range_m, scope_width, last_aa.
    #[func]
    fn state(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(r) = &self.radar else { return d };
        d.set("mode", r.mode as i64);
        d.set("last_aa", r.last_aa as i64);
        d.set("aa", r.aa);
        d.set("off", r.off);
        d.set("damaged", r.damaged);
        d.set("dirty", r.dirty);
        d.set("bore_held", r.bore_held);
        d.set("sel_key", r.sel_key.clone());
        d.set("sel_locked", r.sel_locked);
        let mut cs = VarArray::new();
        for c in &r.contacts {
            cs.push(&contact(c).to_variant());
        }
        d.set("contacts", &cs);
        d.set("stt", &r.stt.as_ref().map(contact).unwrap_or_default());
        d.set("locked", &r.locked().map(contact).unwrap_or_default());
        d.set("has_lock", r.has_lock());
        d.set("antenna", Vector2::new(r.antenna.0 as f32, r.antenna.1 as f32));
        d.set("heading_shift", r.heading_shift);
        d.set("designated", r.designated);
        d.set("desig", gv(r.desig));
        d.set("exp", r.exp);
        let mut modes = VarDictionary::new();
        for (m, mr) in r.modes.iter().enumerate() {
            if let Some(mr) = mr {
                let mut e = VarDictionary::new();
                e.set("max", mr.max);
                e.set("nm", mr.nm);
                e.set("idx", mr.idx);
                modes.set(m as i64, &e);
            }
        }
        d.set("modes", &modes);
        d.set("range_index", r.range_index());
        d.set("range_m", r.range_m());
        d.set("scope_width", r.scope_width());
        d
    }

    /// The events since the last call, in order: ["lock", key, on] (the target's RWR) or ["illum"]
    /// (`FUN_00458130`, the semi-active missiles lose their guidance).
    #[func]
    fn events(&mut self) -> VarArray {
        let mut out = VarArray::new();
        let Some(r) = &mut self.radar else { return out };
        for e in r.events.drain(..) {
            let a: VarArray = match e {
                Event::Lock(k, on) => varray!["lock", k, on],
                Event::IlluminationLost => varray!["illum"],
            };
            out.push(&a.to_variant());
        }
        out
    }
}
