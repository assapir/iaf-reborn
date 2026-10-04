//! `IafMissile` (the chase motion of a homing weapon) and `IafGuided` (the guided motion of the TV missile / laser
//! bomb) from `iaf_avionics::{missile, guided}`, for `game/weapons/missile.gd` and `guided.gd`.

use crate::world::{get, num, terrain, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::guided::{Guided, GuidedMotion, Phase};
use iaf_avionics::missile::{Aim, Chase, ChaseMotion, Dlz, Kinematics, Launcher, Missile, Tuning};

/// A `_debugParam` value through `db.debug_param(i, default)`.
fn debug(f: &Callable, i: i64, default: f64) -> f64 {
    let v = f.call(&[i.to_variant(), default.to_variant()]);
    v.try_to::<f64>().ok().or_else(|| v.try_to::<i64>().ok().map(|i| i as f64)).unwrap_or(default)
}

fn dlz_array(z: Dlz) -> VarArray {
    varray![z.max, z.min]
}

/// The chase motion of a weapons.ibx record (with its Real overrides, "burn" when set). A missing field is 0 for the
/// DLZ (`FUN_005624f0` on a zeroed record) but the motion's own default at a launch (`FUN_00561c30`).
fn chase_motion(m: &VarDictionary, launch: bool) -> ChaseMotion {
    let f = |k: &str, at_launch: f64| num(m, k).unwrap_or(if launch { at_launch } else { 0.0 });
    let part = |k: &str| num(m, k).unwrap_or(0.0);
    ChaseMotion {
        accel: f("_absAcceleration", 100.0),
        beta: f("_spiralAccelBeta", 0.08),
        spiral: f("_spiralAccel", 1000.0),
        t_co: f("_timeConstOrientation", 2.0),
        burn: num(m, "burn").unwrap_or_else(|| part("_timeAcceleration") + part("_timeConstVel") + part("_timeDecceleration")),
        chase: Chase::from_type(num(m, "_chaseType").unwrap_or(1.0) as i64),
        high_angle_turn: part("_highAngleTurn") != 0.0,
        release_time: part("_timeRelease"),
        release_accel: part("_absReleaseAcceleration"),
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafMissile {
    missile: Option<Missile>,
}

impl IafMissile {
    fn get<R: Default>(&self, f: impl FnOnce(&Missile) -> R) -> R {
        self.missile.as_ref().map(f).unwrap_or_default()
    }
}

#[godot_api]
impl IafMissile {
    /// Launch (`FUN_004d5d10` → `FUN_00561ef0`): motion record `m`, the Real turn limit `max_g` (0 none), the launcher
    /// at `pos` with velocity / nose / up, at the unit `target` ("" = the point), q; `debug` = db.debug_param.
    #[func]
    #[allow(clippy::too_many_arguments)] // a #[func]: GDScript has no struct to pass
    fn launch(
        &mut self,
        m: VarDictionary,
        max_g: f64,
        now: f64,
        pos: Vector3,
        vel: Vector3,
        nose: Vector3,
        up: Vector3,
        target: GString,
        point: Vector3,
        q: f64,
        debug_param: Callable,
    ) {
        let motion = chase_motion(&m, true);
        let tuning = Tuning {
            overshoot_dist: if motion.high_angle_turn { debug(&debug_param, 15, 1000.0) } else { debug(&debug_param, 1, 1.0e7) },
            no_end: debug(&debug_param, 5, 0.0) == 1.0,
            slow_launch_speed: debug(&debug_param, 0, 100.1),
            max_g: (max_g > 0.0).then_some(max_g),
        };
        let aim = if target.is_empty() { Aim::Point(vec3(point)) } else { Aim::Unit(target.to_string()) };
        let launcher = Launcher { pos: vec3(pos), vel: vec3(vel), fwd: vec3(nose), up: vec3(up) };
        self.missile = Some(Missile::launch(motion, tuning, now, vec3(pos), &launcher, aim, q));
    }

    #[func]
    fn position(&self, now: f64) -> Vector3 {
        vector3(self.get(|m| m.position(now)))
    }

    #[func]
    fn velocity(&self, now: f64) -> Vector3 {
        vector3(self.get(|m| m.velocity(now)))
    }

    /// One update (`FUN_005627e0`) with the target now; `ground` = terrain height under a point. True when it ends
    /// (burst at last_pos).
    #[func]
    fn update(&mut self, now: f64, t_pos: Vector3, t_vel: Vector3, ground: Callable) -> bool {
        let t = terrain(Some(ground));
        let target = Kinematics { pos: vec3(t_pos), vel: vec3(t_vel) };
        self.missile.as_mut().is_some_and(|m| m.update(now, target, &t))
    }

    #[func]
    fn time_left(&self, now: f64) -> f64 {
        self.get(|m| m.time_left(now))
    }

    #[func]
    fn retarget(&mut self, key: GString) {
        if let Some(m) = &mut self.missile {
            m.retarget(key.to_string());
        }
    }

    #[func]
    fn set_guidance_off(&mut self, off: bool) {
        if let Some(m) = &mut self.missile {
            m.guidance_off = off;
        }
    }

    #[func]
    fn guidance_off(&self) -> bool {
        self.get(|m| m.guidance_off)
    }

    /// {p0, v0, acc, t0, last_pos, next_update, ended, has_target, target_key, aim_point}.
    #[func]
    fn state(&self) -> VarDictionary {
        let Some(m) = &self.missile else { return VarDictionary::new() };
        let (p0, v0, acc) = m.segment();
        let (key, point) = match m.aim() {
            Aim::Unit(k) => (k.as_str(), Vector3::ZERO),
            Aim::Point(p) => ("", vector3(*p)),
        };
        vdict! {
            "p0" => vector3(p0), "v0" => vector3(v0), "acc" => vector3(acc), "t0" => m.t0(),
            "last_pos" => vector3(m.last_pos()), "next_update" => m.next_update(), "ended" => m.ended(),
            "has_target" => matches!(m.aim(), Aim::Unit(_)), "target_key" => key, "aim_point" => point,
        }
    }

    /// `FUN_005627b0`: the distance flown in `t` seconds from speed `s` with the motion of record `m`.
    #[func]
    fn flown(m: VarDictionary, s: f64, t: f64) -> f64 {
        chase_motion(&m, false).flown(s, t)
    }

    /// The DLZ (`FUN_005624f0`) of record `m` from {pos, fwd, vel} at {pos, vel} ({} none): [max, min] metres.
    #[func]
    fn dlz(m: VarDictionary, own: VarDictionary, target: VarDictionary) -> VarArray {
        let v = |d: &VarDictionary, k: &str| vec3(get(d, k).unwrap_or_default());
        let launcher = Launcher { pos: v(&own, "pos"), vel: v(&own, "vel"), fwd: v(&own, "fwd"), up: Default::default() };
        let t = (!target.is_empty()).then(|| Kinematics { pos: v(&target, "pos"), vel: v(&target, "vel") });
        dlz_array(chase_motion(&m, false).dlz(&launcher, t.as_ref()))
    }
}

/// The guided motion of a weapons.ibx record (`FUN_00563d30`; the ibx comments name their real use) and the
/// `_debugParam` values 11 (the DLZ's dive angle), 13 (the burst snap) and 14 (the terminal phase).
fn guided_motion(m: &VarDictionary, debug_param: &Callable) -> GuidedMotion {
    let d = GuidedMotion::default();
    let f = |k: &str, v: f64| num(m, k).unwrap_or(v);
    GuidedMotion {
        engine: f("_absAcceleration", d.engine),
        t_acc: f("_timeAcceleration", d.t_acc),
        switch_near2: f("_timeConstVel", d.switch_near2),
        turn: f("_absDeceleration", d.turn),
        up_acc: f("_timeDecceleration", d.up_acc),
        down_acc: f("_spiralAccelBeta", d.down_acc),
        end_time: f("_spiralAccel", d.end_time),
        max_vel: f("_absReleaseAcceleration", d.max_vel),
        damp: f("_timeRelease", d.damp),
        t_co: f("_timeConstOrientation", d.t_co),
        max_up: f("_rollRate", d.max_up),
        burst_dist: debug(debug_param, 13, d.burst_dist),
        terminal_dist: debug(debug_param, 14, d.terminal_dist),
        dive_deg: debug(debug_param, 11, d.dive_deg),
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafGuided {
    guided: Option<Guided>,
}

impl IafGuided {
    fn get<R: Default>(&self, f: impl FnOnce(&Guided) -> R) -> R {
        self.guided.as_ref().map(f).unwrap_or_default()
    }
}

#[godot_api]
impl IafGuided {
    /// `FUN_00563d30` + `FUN_00563f90`: record `m`, the release point / velocity, the aim point.
    #[func]
    fn launch(&mut self, m: VarDictionary, now: f64, pos: Vector3, vel: Vector3, point: Vector3, debug_param: Callable) {
        self.guided = Some(Guided::launch(guided_motion(&m, &debug_param), now, vec3(pos), vec3(vel), vec3(point)));
    }

    #[func]
    fn position(&self, now: f64) -> Vector3 {
        vector3(self.get(|g| g.position(now)))
    }

    #[func]
    fn velocity(&self, now: f64) -> Vector3 {
        vector3(self.get(|g| g.velocity(now)))
    }

    #[func]
    fn set_aim(&mut self, p: Vector3) {
        if let Some(g) = &mut self.guided {
            g.set_aim(vec3(p));
        }
    }

    #[func]
    fn time_left(&self, now: f64) -> f64 {
        self.get(|g| g.time_left(now))
    }

    /// One update (`FUN_005643a0`); `ground` = terrain height under a point. True when it ends (burst at last_pos).
    #[func]
    fn update(&mut self, now: f64, ground: Callable) -> bool {
        let t = terrain(Some(ground));
        self.guided.as_mut().is_some_and(|g| g.update(now, &t))
    }

    /// {mode (0 far, 1 near, 2 terminal), aim, last_pos, next_update, ended}.
    #[func]
    fn state(&self) -> VarDictionary {
        let Some(g) = &self.guided else { return VarDictionary::new() };
        let mode: i64 = match g.phase() {
            Phase::Far => 0,
            Phase::Near => 1,
            Phase::Terminal => 2,
        };
        vdict! {
            "mode" => mode, "aim" => vector3(g.aim()), "last_pos" => vector3(g.last_pos()),
            "next_update" => g.next_update(), "ended" => g.ended(),
        }
    }

    /// The DLZ (`FUN_005641c0`) from `agl` above the terrain at `vel`: [range, range].
    #[func]
    fn dlz(m: VarDictionary, agl: f64, vel: Vector3, debug_param: Callable) -> VarArray {
        let r = guided_motion(&m, &debug_param).dlz_range(agl, vec3(vel));
        dlz_array(Dlz { max: r, min: r })
    }
}
