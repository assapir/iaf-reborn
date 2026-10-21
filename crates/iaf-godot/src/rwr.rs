//! `IafRwr`: the RWR (`iaf_avionics::rwr`, docs/rwr.md) for `game/weapons/rwr.gd`. Every call that needs the world
//! takes the unit lookup `unit(key) -> {pos, klass, type, state}` ({} gone), the own jet {pos, yaw} and the sim time.

use crate::world::{get, num, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::rwr::{Emitter, Launched, Rwr, Shown, Site, World, spo15};
use iaf_avionics::vec3::Vec3;

fn emitter(d: &VarDictionary) -> Option<Emitter> {
    (!d.is_empty()).then(|| Emitter {
        pos: vec3(get(d, "pos").unwrap_or_default()),
        class: num(d, "klass").unwrap_or_default() as i64,
        type_code: num(d, "type").unwrap_or_default() as i64,
        state: num(d, "state").unwrap_or(1.0) as i64,
    })
}

/// Runs `f` with the world of `unit` / `own` / `now`.
fn with_world<R>(unit: &Callable, own: &VarDictionary, now: f64, f: impl FnOnce(&World) -> R) -> R {
    let lookup = |k: &str| unit.call(&[k.to_variant()]).try_to::<VarDictionary>().ok().and_then(|d| emitter(&d));
    let w = World {
        pos: vec3(get(own, "pos").unwrap_or_default()),
        yaw: num(own, "yaw").unwrap_or_default(),
        now,
        unit: &lookup,
    };
    f(&w)
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRwr {
    rwr: Rwr,
}

#[godot_api]
impl IafRwr {
    #[func]
    fn set_damaged(&mut self, on: bool) {
        self.rwr.damaged = on;
    }

    #[func]
    fn set_compact(&mut self, on: bool) {
        self.rwr.compact = on;
    }

    #[func]
    fn lock(&mut self, key: GString, unit: Callable, own: VarDictionary, now: f64) {
        with_world(&unit, &own, now, |w| self.rwr.lock(w, &key.to_string()));
    }

    #[func]
    fn unlock(&mut self, key: GString, unit: Callable, own: VarDictionary, now: f64) {
        with_world(&unit, &own, now, |w| self.rwr.unlock(w, &key.to_string()));
    }

    /// `missile` {id, pos, decoy} or {}; false when ignored (no sounds).
    #[func]
    fn launch(&mut self, key: GString, missile: VarDictionary, unit: Callable, own: VarDictionary, now: f64) -> bool {
        let m = (!missile.is_empty()).then(|| Launched {
            id: num(&missile, "id").unwrap_or_default() as i64,
            pos: vec3(get(&missile, "pos").unwrap_or_default()),
            decoy: get(&missile, "decoy").unwrap_or(false),
        });
        with_world(&unit, &own, now, |w| self.rwr.launch(w, &key.to_string(), m))
    }

    /// `id` the missile's (null none); false when ignored.
    #[func]
    fn missile_end(&mut self, key: GString, id: Variant) -> bool {
        let id = id.try_to::<i64>().ok().or_else(|| id.try_to::<f64>().ok().map(|f| f as i64));
        self.rwr.missile_end(&key.to_string(), id)
    }

    #[func]
    fn clear(&mut self) {
        self.rwr.clear();
    }

    #[func]
    fn refresh(&mut self, unit: Callable, own: VarDictionary, now: f64) {
        with_world(&unit, &own, now, |w| self.rwr.refresh(w));
    }

    #[func]
    fn update(&mut self, unit: Callable, own: VarDictionary, now: f64) {
        with_world(&unit, &own, now, |w| self.rwr.update(w));
    }

    /// Real RWR (`Rwr::search`): `sites` [{key, name, reach}] of the hostile ground units, `terrain` the ground height.
    #[func]
    fn search(&mut self, sites: VarArray, unit: Callable, own: VarDictionary, now: f64, terrain: Callable) {
        let sites: Vec<Site> = sites
            .iter_shared()
            .filter_map(|v| v.try_to::<VarDictionary>().ok())
            .map(|d| Site {
                key: get::<GString>(&d, "key").unwrap_or_default().to_string(),
                name: get::<GString>(&d, "name").unwrap_or_default().to_string(),
                reach: num(&d, "reach").unwrap_or_default(),
            })
            .collect();
        let ground = crate::world::terrain(Some(terrain));
        with_world(&unit, &own, now, |w| self.rwr.search(w, &sites, &ground));
    }

    /// The nearest listed emitter's key ("" none).
    #[func]
    fn nearest(&mut self, unit: Callable, own: VarDictionary, now: f64) -> GString {
        with_world(&unit, &own, now, |w| self.rwr.nearest(w)).as_deref().unwrap_or_default().into()
    }

    /// WRN_NEW_GUY is due (cleared by the call).
    #[func]
    fn take_new_guy(&mut self) -> bool {
        self.rwr.take_new_guy()
    }

    /// The cockpit copy: [{type, pos (world X / Y), launch, active, search}].
    #[func]
    fn display(&self) -> VarArray {
        self.rwr
            .display()
            .iter()
            .map(|s| {
                let pos = Vector2::new(s.pos.x as f32, s.pos.y as f32);
                vdict! { "type" => s.type_code, "pos" => pos, "launch" => s.launch, "active" => s.active,
                "search" => s.search }
                .to_variant()
            })
            .collect()
    }

    /// Ours, Better cockpit `spo15` (`iaf_avionics::rwr::spo15`): the MiG-23's SPO-15 lamps from the cockpit copy
    /// `entries` ([`display`](Self::display)), the own world X / Y and heading (degrees): {sectors (bits), power
    /// (lamps lit), lock, launch, types (bits)}.
    #[func]
    fn spo15(entries: VarArray, own: Vector2, heading_deg: f64) -> VarDictionary {
        let shown: Vec<Shown> = entries
            .iter_shared()
            .filter_map(|v| v.try_to::<VarDictionary>().ok())
            .map(|d| {
                let p: Vector2 = get(&d, "pos").unwrap_or_default();
                Shown {
                    type_code: num(&d, "type").unwrap_or_default() as i64,
                    pos: Vec3::new(p.x as f64, p.y as f64, 0.0),
                    launch: get(&d, "launch").unwrap_or(false),
                    active: get(&d, "active").unwrap_or(false),
                    search: get(&d, "search").unwrap_or(false),
                }
            })
            .collect();
        let s = spo15(&shown, Vec3::new(own.x as f64, own.y as f64, 0.0), heading_deg);
        vdict! {
            "sectors" => s.sectors as i64, "power" => s.power as i64, "lock" => s.lock, "launch" => s.launch,
            "types" => s.types as i64,
        }
    }

    /// {slots [{unit, type, pos, launch, missiles, drop, active}], count, ai, sam, threats [{id, dist}], next_refresh}.
    #[func]
    fn state(&self) -> VarDictionary {
        let r = &self.rwr;
        let slots: VarArray = r
            .slots()
            .iter()
            .map(|s| {
                vdict! {
                    "unit" => s.unit.as_deref().unwrap_or(""), "type" => s.type_code, "pos" => vector3(s.pos),
                    "launch" => s.launch, "missiles" => s.missiles, "drop" => s.drop, "active" => s.active,
                }
                .to_variant()
            })
            .collect();
        let threats: VarArray =
            r.threats().iter().map(|t| vdict! { "id" => t.id, "dist" => t.dist }.to_variant()).collect();
        vdict! {
            "slots" => &slots, "count" => r.count() as i64, "ai" => r.lamps.ai, "sam" => r.lamps.sam,
            "threats" => &threats, "next_refresh" => r.next_refresh(),
        }
    }
}
