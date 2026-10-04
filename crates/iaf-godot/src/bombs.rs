//! `IafBomb` (one falling store, `iaf_avionics::bombs`) with the impact prediction and ripple line as statics, and
//! `IafModes` (the master / HUD modes, `iaf_avionics::master`), for `game/weapons/bombs.gd` and `player_weapons.gd`.

use crate::world::{get, num, terrain, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::bombs::{self, Bomb};
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
    /// `FUN_0045e7f0`: {point, t}.
    #[func]
    fn predict_impact(p: Vector3, vel: Vector3, nose: Vector3, drag: f64, extra: f64, ground: Callable) -> VarDictionary {
        let (i, t) = bombs::predict_impact(vec3(p), vec3(vel), vec3(nose), drag, extra, &terrain(Some(ground)));
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
        bombs::ripple_line(vec3(p), qty, spacing, heading, &terrain(Some(ground))).into_iter().map(|a| vector3(a).to_variant()).collect()
    }

    /// The falling store's state at launch.
    #[func]
    fn launch(now: f64, p: Vector3, v: Vector3, aim: Vector3, clamp_acc: f64) -> VarDictionary {
        bomb_dict(&Bomb::launch(now, vec3(p), vec3(v), vec3(aim), clamp_acc))
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
}
