//! `IafBomb` (one falling store, `iaf_avionics::bombs`) with the impact prediction and ripple line as statics, and
//! `IafModes` (the master / HUD modes, `iaf_avionics::master`), for `game/weapons/bombs.gd` and `player_weapons.gd`.

use crate::world::{get, num, terrain, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::bombs::{self, Bomb};
use iaf_avionics::gps::{self, GpsBomb, Kit};
use iaf_avionics::master::{Hud, Master, MasterKey, Modes};

/// The falling store's state as a dictionary {t0, p0, v0, aim, acc, end, next_check, opened, done} (bombs.gd keeps
/// it in a plain Dictionary).
fn bomb_from(d: &VarDictionary) -> Bomb {
    let v = |k: &str| vec3(get(d, k).unwrap_or_default());
    let f = |k: &str| num(d, k).unwrap_or_default();
    Bomb {
        t0: f("t0"),
        p0: v("p0"),
        v0: v("v0"),
        aim: v("aim"),
        acc: v("acc"),
        end: f("end"),
        next_check: f("next_check"),
        opened: get(d, "opened").unwrap_or(false),
        done: get(d, "done").unwrap_or(false),
    }
}

fn bomb_dict(b: &Bomb) -> VarDictionary {
    vdict! {
        "t0" => b.t0, "p0" => vector3(b.p0), "v0" => vector3(b.v0), "aim" => vector3(b.aim), "acc" => vector3(b.acc),
        "end" => b.end, "next_check" => b.next_check, "opened" => b.opened, "done" => b.done,
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafBomb {}

#[godot_api]
impl IafBomb {
    /// `FUN_0045e7f0`: {point, t}. `wind`: Better physics `wind` (zero: the original).
    #[func]
    fn predict_impact(
        p: Vector3,
        vel: Vector3,
        nose: Vector3,
        drag_extra: Vector2,
        cockpit: bool,
        wind: Vector3,
        ground: Callable,
    ) -> VarDictionary {
        let de = (drag_extra.x.into(), drag_extra.y.into());
        let (i, t) =
            bombs::predict_impact(vec3(p), vec3(vel), vec3(nose), de, cockpit, vec3(wind), &terrain(Some(ground)));
        vdict! { "point" => vector3(i), "t" => t }
    }

    #[func]
    fn fall_time(vz: f64, h: f64) -> f64 {
        bombs::fall_time(vz, h)
    }

    /// `FUN_00457c20`: the ripple line's points.
    #[func]
    fn ripple_line(p: Vector3, qty: i64, spacing: f64, heading: f64, ground: Callable) -> VarArray {
        let qty = usize::try_from(qty).unwrap_or(0);
        bombs::ripple_line(vec3(p), qty, spacing, heading, &terrain(Some(ground)))
            .into_iter()
            .map(|a| vector3(a).to_variant())
            .collect()
    }

    /// The falling store's state at launch; `wind`: Better physics `wind` (zero: the original).
    #[func]
    fn launch(now: f64, p: Vector3, v: Vector3, aim: Vector3, clamp_acc: f64, wind: Vector3) -> VarDictionary {
        bomb_dict(&Bomb::launch(now, vec3(p), vec3(v), vec3(aim), clamp_acc, vec3(wind)))
    }

    #[func]
    fn position(b: VarDictionary, now: f64) -> Vector3 {
        vector3(bomb_from(&b).position(now))
    }

    #[func]
    fn velocity(b: VarDictionary, now: f64) -> Vector3 {
        vector3(bomb_from(&b).velocity(now))
    }

    /// The impact checks of `b` up to `now`, written back into it: {pos, t} or {}.
    #[func]
    fn check(mut b: VarDictionary, now: f64, ground: Callable, fix_burst: bool, open_h: f64) -> VarDictionary {
        let mut bomb = bomb_from(&b);
        let hit = bomb.check(now, &terrain(Some(ground)), fix_burst, open_h);
        b.set("next_check", bomb.next_check);
        b.set("opened", bomb.opened);
        b.set("done", bomb.done);
        hit.map_or_else(VarDictionary::new, |(p, t)| vdict! { "pos" => vector3(p), "t" => t })
    }
}

fn master(i: i64) -> Master {
    [Master::Nav, Master::Bombs, Master::AgGun, Master::AaGun, Master::Missiles, Master::LaserBomb, Master::Tv]
        .get(usize::try_from(i).unwrap_or(0))
        .copied()
        .unwrap_or_default()
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafModes {
    modes: Modes,
}

#[godot_api]
impl IafModes {
    #[func]
    fn master(&self) -> i64 {
        self.modes.master as i64
    }

    #[func]
    fn master_prev(&self) -> i64 {
        self.modes.prev as i64
    }

    /// The M key's cycle: 0 NAV, 1 AA, 2 AG.
    #[func]
    fn m_cycle(&self) -> i64 {
        self.modes.cycle().into()
    }

    #[func]
    fn hud(&self) -> i64 {
        self.modes.hud as i64
    }

    #[func]
    fn set_hud(&mut self, h: i64) {
        self.modes.hud = Hud::from_index(h);
    }

    /// `FUN_0044ec80`: [master, hud] of a store type, [] when the mode stays.
    #[func]
    fn for_store(type_code: i64, aa_key: bool, flir_pod: bool) -> VarArray {
        Modes::for_store(type_code, aa_key, flir_pod).map_or_else(VarArray::new, |(m, h)| varray![m as i64, h as i64])
    }

    #[func]
    fn set_master(&mut self, m: i64) {
        self.modes.set_master(master(m));
    }

    #[func]
    fn aa_key_cycles(&self, type_code: i64) -> bool {
        self.modes.aa_key_cycles(type_code)
    }

    #[func]
    fn ag_key_cycles(&self, type_code: i64) -> bool {
        self.modes.ag_key_cycles(type_code)
    }

    /// M: "aa", "ag" or "nav" (the master mode already NAV).
    #[func]
    fn master_key(&mut self) -> GString {
        match self.modes.master_key() {
            MasterKey::Aa => "aa",
            MasterKey::Ag => "ag",
            MasterKey::Nav => "nav",
        }
        .into()
    }

    #[func]
    fn nav_key(&mut self, m: i64) {
        self.modes.nav_key(master(m));
    }

    /// `FUN_00449810`: the MFD page of the master mode, −1 none.
    #[func]
    fn mfd_page(&self, type_code: i64, flir_pod: bool) -> i64 {
        self.modes.mfd_page(type_code, flir_pod).map_or(-1, i64::from)
    }

    /// The M key's MFD pages, slot by slot (`master::m_key_pages`).
    #[func]
    fn m_key_pages(cycle: i64, n: i64, panel_rwr: bool, harm: bool) -> PackedInt32Array {
        iaf_avionics::master::m_key_pages(cycle as u8, n.max(0) as usize, panel_rwr, harm)
            .into_iter()
            .map(i32::from)
            .collect()
    }

    /// `FUN_00449f20`: the slot for a master mode's page, −1 none (`master::free_slot`).
    #[func]
    fn free_slot(pages: PackedInt32Array) -> i64 {
        let pages: Vec<i64> = pages.as_slice().iter().map(|&p| i64::from(p)).collect();
        iaf_avionics::master::free_slot(&pages).map_or(-1, |i| i as i64)
    }

    /// The M key's R presses (`master::m_key_radar`).
    #[func]
    fn m_key_radar(cycle: i64, n: i64, aa: bool, mode: i64) -> i64 {
        i64::from(iaf_avionics::master::m_key_radar(cycle as u8, n.max(0) as usize, aa, mode as u8))
    }
}

/// A GPS kit from a weapon record's "gps" {glide, min_speed, max_speed, max_g} (modern_weapons.gd).
fn kit(d: &VarDictionary) -> Kit {
    let f = |k: &str, def: f64| num(d, k).unwrap_or(def);
    Kit {
        glide: f("glide", 1.0),
        min_speed: f("min_speed", 150.0),
        max_speed: f("max_speed", 300.0),
        max_g: f("max_g", 3.0),
    }
}

/// `IafGpsBomb`: one GPS-guided bomb in flight (`iaf_avionics::gps`, ours; docs/weapons.md §13.2).
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafGpsBomb {
    bomb: Option<GpsBomb>,
}

#[godot_api]
impl IafGpsBomb {
    #[func]
    fn launch(&mut self, gps: VarDictionary, now: f64, pos: Vector3, vel: Vector3, aim: Vector3) {
        self.bomb = Some(GpsBomb::launch(kit(&gps), now, vec3(pos), vec3(vel), vec3(aim)));
    }

    /// Flies to `now`; true when it bursts (at `position()`).
    #[func]
    fn advance(&mut self, now: f64, ground: Callable) -> bool {
        let t = terrain(Some(ground));
        self.bomb.as_mut().is_none_or(|b| b.advance(now, &t))
    }

    #[func]
    fn position(&self) -> Vector3 {
        self.bomb.as_ref().map(|b| vector3(b.pos)).unwrap_or_default()
    }

    #[func]
    fn velocity(&self) -> Vector3 {
        self.bomb.as_ref().map(|b| vector3(b.vel)).unwrap_or_default()
    }

    /// The time to impact (s, `GpsBomb::time_to_impact`), 0 once burst.
    #[func]
    fn time_to_impact(&self) -> f64 {
        self.bomb.as_ref().map_or(0.0, |b| b.time_to_impact())
    }

    #[func]
    fn aim(&self) -> Vector3 {
        self.bomb.as_ref().map(|b| vector3(b.aim)).unwrap_or_default()
    }

    /// The LAR: a release from `pos` at `vel` reaches `aim`.
    #[func]
    fn in_range(gps: VarDictionary, pos: Vector3, vel: Vector3, aim: Vector3) -> bool {
        kit(&gps).in_range(vec3(pos), vec3(vel), vec3(aim))
    }

    /// The launch acceptability region (`Kit::lar`): {range, rmin, rmax, in_range, tmr (s, or null)}.
    #[func]
    fn lar(gps: VarDictionary, pos: Vector3, vel: Vector3, aim: Vector3) -> VarDictionary {
        let l = kit(&gps).lar(vec3(pos), vec3(vel), vec3(aim));
        let tmr = l.tmr.map_or(Variant::nil(), |t| t.to_variant());
        vdict! { "range" => l.range, "rmin" => l.rmin, "rmax" => l.rmax, "in_range" => l.in_range, "tmr" => &tmr }
    }

    /// The PRE targets a station steps through (`gps::pre_targets`): `own` a world point or null.
    #[func]
    fn pre_targets(own: Variant, others: PackedVector3Array, steerpoints: PackedVector3Array) -> PackedVector3Array {
        let v = |a: &PackedVector3Array| a.as_slice().iter().map(|p| vec3(*p)).collect::<Vec<_>>();
        let own = own.try_to::<Vector3>().ok().map(vec3);
        gps::pre_targets(own, &v(&others), &v(&steerpoints)).into_iter().map(vector3).collect()
    }

    /// Each bomb's PRE target on a station of `count` bombs (`gps::rack_targets`): `station` and each of `own` a world
    /// point or null; null entries for the bombs without one.
    #[func]
    fn rack_targets(station: Variant, own: VarArray, count: i64) -> VarArray {
        let p = |v: &Variant| v.try_to::<Vector3>().ok().map(vec3);
        let own: Vec<_> = own.iter_shared().map(|v| p(&v)).collect();
        gps::rack_targets(p(&station), &own, count.max(0) as usize)
            .into_iter()
            .map(|t| t.map_or(Variant::nil(), |q| vector3(q).to_variant()))
            .collect()
    }

    /// The PRE target step `index` picks (`gps::pre_pick`), or null.
    #[func]
    fn pre_pick(own: Variant, list: PackedVector3Array, index: i64) -> Variant {
        let list: Vec<_> = list.as_slice().iter().map(|p| vec3(*p)).collect();
        let own = own.try_to::<Vector3>().ok().map(vec3);
        gps::pre_pick(own, &list, index.max(0) as usize).map_or(Variant::nil(), |p| vector3(p).to_variant())
    }

    /// The route's waypoint a station takes when the briefing set none (`gps::default_target`), -1 none.
    #[func]
    fn default_target(actions: PackedInt64Array) -> i64 {
        gps::default_target(actions.as_slice()).map_or(-1, |i| i as i64)
    }

    /// The ground distance a release `h` metres above the aim at speed `s` reaches.
    #[func]
    fn reach(gps: VarDictionary, h: f64, s: f64) -> f64 {
        kit(&gps).reach(h, s)
    }
}
