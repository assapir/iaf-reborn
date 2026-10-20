//! `IafRounds` (a fixed weapon's pool of rounds: gun, rockets, decoys) and `IafLcos` (the AA gun pipper) from
//! `iaf_avionics::gun`, for `game/weapons/gun_rounds.gd` and `player_weapons.gd`.

use crate::world::{get, terrain, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::gun::{self, Body, Flight, Hit, JetState, Lcos, Motion, Rounds, Shot};

fn bodies(keys: &PackedStringArray, positions: &PackedVector3Array, spans: &PackedFloat64Array) -> Vec<Body> {
    let spans = spans.as_slice();
    keys.as_slice()
        .iter()
        .zip(positions.as_slice())
        .enumerate()
        .map(|(i, (k, &p))| Body { key: k.to_string(), pos: vec3(p), half_span: spans.get(i).copied().unwrap_or(0.0) })
        .collect()
}

fn flight(f: &Flight) -> VarDictionary {
    vdict! { "p0" => vector3(f.p0), "u" => vector3(f.u), "s" => f.s, "t0" => f.t0, "t_end" => f.t_end, "A" => vector3(f.a) }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRounds {
    rounds: Option<Rounds>,
}

impl IafRounds {
    fn motion(&self) -> Motion {
        self.rounds.as_ref().map(|r| r.motion).unwrap_or_default()
    }
}

#[godot_api]
impl IafRounds {
    /// The motion of a weapons.ibx section (_absAcceleration, _limitVel, _limitDist, _velocityJump,
    /// _timeConstOrientation = the check period, _spiralAccel = the hit distance, _maxNumInAir) for weapon `type`
    /// (565 = the gun; with `real_hits` true, Weapon data Real: the swept real hit test); an empty pool.
    #[func]
    fn configure(&mut self, m: VarDictionary, r#type: i64) {
        let d = Motion::default();
        let f = |k: &str, v: f64| get::<f64>(&m, k).unwrap_or(v);
        let motion = Motion {
            abs_accel: f("_absAcceleration", d.abs_accel),
            limit_vel: f("_limitVel", d.limit_vel),
            limit_dist: f("_limitDist", d.limit_dist),
            velocity_jump: f("_velocityJump", d.velocity_jump),
            check_period: f("_timeConstOrientation", d.check_period),
            hit_distance: f("_spiralAccel", d.hit_distance),
            pool_size: get::<i64>(&m, "_maxNumInAir").and_then(|n| usize::try_from(n).ok()).unwrap_or(d.pool_size),
            cut_aim: r#type != 565,
            real_hits: r#type == 565 && get::<bool>(&m, "real_hits").unwrap_or(false),
        };
        self.rounds = Some(Rounds::new(motion));
    }

    #[func]
    fn velocity_jump(&self) -> f64 {
        self.motion().velocity_jump
    }

    /// The shot line: the nose 1° up for the player (`FUN_00456ff0`).
    #[func]
    fn shot_dir(nose: Vector3, up: Vector3, elevate: bool) -> Vector3 {
        vector3(gun::shot_dir(vec3(nose), vec3(up), elevate))
    }

    #[func]
    fn aim_point(&self, p: Vector3, vel: Vector3, d: Vector3, ag_mode: bool) -> Vector3 {
        vector3(self.motion().aim_point(vec3(p), vec3(vel), vec3(d), ag_mode))
    }

    /// The flight from `p0` at speed `s` to `a` from `t0` ({p0, u, s, t0, t_end, A}; the decoys: no candidates, so
    /// A is cut at the terrain, `FUN_004d7690`).
    #[func]
    fn flight(&self, t0: f64, p0: Vector3, s: f64, a: Vector3, terrain_at: Callable) -> VarDictionary {
        let m = self.motion();
        let a = gun::launch_aim(&m, vec3(p0), vec3(a), true, &terrain(Some(terrain_at)));
        flight(&m.flight(t0, vec3(p0), s, a))
    }

    /// A flight's position at `t` ({p0, u, s, t0, t_end, A}, as `slots()` gives them).
    #[func]
    fn position(&self, f: VarDictionary, t: f64) -> Vector3 {
        let v = |k: &str| vec3(get(&f, k).unwrap_or_default());
        let s = |k: &str| get(&f, k).unwrap_or_default();
        let fl = Flight { p0: v("p0"), u: v("u"), s: s("s"), t0: s("t0"), t_end: s("t_end"), a: v("A") };
        vector3(self.motion().position(&fl, t))
    }

    #[func]
    fn next_free(&self) -> bool {
        self.rounds.as_ref().is_some_and(Rounds::next_free)
    }

    /// One shot: its pool slot, or −1 when the pooled round is still in the air. `locked` "" = no radar lock; the units as keys,
    /// positions and drawn half-spans (m). `shot` = {origin, muzzle, velocity, aim (Vector3), locked, shooter (String), easy_aiming (bool), targets}:
    /// `targets` a PackedStringArray of a ground unit's round's only candidates (docs/ai.md §14), else null.
    #[func]
    fn fire(
        &mut self,
        now: f64,
        shot: VarDictionary,
        keys: PackedStringArray,
        positions: PackedVector3Array,
        spans: PackedFloat64Array,
        terrain_at: Callable,
    ) -> i64 {
        let v = |k: &str| vec3(get(&shot, k).unwrap_or_default());
        let s = |k: &str| get::<GString>(&shot, k).unwrap_or_default().to_string();
        let (locked, shooter) = (s("locked"), s("shooter"));
        let targets = shot.get("targets").unwrap_or_default();
        // A null Variant converts to an empty array: only a given array is a fixed list.
        let targets: Option<Vec<String>> = (!targets.is_nil())
            .then(|| targets.try_to::<PackedStringArray>().ok())
            .flatten()
            .map(|t| t.as_slice().iter().map(GString::to_string).collect());
        let shot = Shot {
            origin: v("origin"),
            muzzle: v("muzzle"),
            velocity: v("velocity"),
            aim: v("aim"),
            locked: Some(locked.as_str()).filter(|k| !k.is_empty()),
            shooter: &shooter,
            easy_aiming: get(&shot, "easy_aiming").unwrap_or(false),
            targets: targets.as_deref(),
        };
        let b = bodies(&keys, &positions, &spans);
        let t = terrain(Some(terrain_at));
        self.rounds.as_mut().and_then(|r| r.fire(now, &shot, &b, &t)).map_or(-1, |slot| slot as i64)
    }

    /// Advances to `now` up to the first detonation: {slot, pos, hit ("unit" / "ground" / "end"), key, candidates}
    /// or {} (none left). Call again after applying its damage.
    #[func]
    fn step(
        &mut self,
        now: f64,
        keys: PackedStringArray,
        positions: PackedVector3Array,
        spans: PackedFloat64Array,
        terrain_at: Callable,
    ) -> VarDictionary {
        let b = bodies(&keys, &positions, &spans);
        let t = terrain(Some(terrain_at));
        let Some(d) = self.rounds.as_mut().and_then(|r| r.step(now, &b, &t)) else { return VarDictionary::new() };
        let mut out = vdict! { "slot" => d.slot as i64, "pos" => vector3(d.pos) };
        match d.hit {
            Hit::Unit { key, candidates } => {
                out.set("hit", "unit");
                out.set("key", key.as_str());
                let c: PackedStringArray = candidates.iter().map(GString::from).collect();
                out.set("candidates", &c);
            }
            Hit::Ground => out.set("hit", "ground"),
            Hit::End => out.set("hit", "end"),
        }
        out
    }

    /// The pool: per slot {} (free) or {p0, u, s, t0, t_end, A, cands, hit_r}.
    #[func]
    fn slots(&self) -> VarArray {
        let Some(r) = &self.rounds else { return VarArray::new() };
        r.slots()
            .iter()
            .map(|s| {
                s.as_ref().map_or_else(VarDictionary::new, |round| {
                    let mut d = flight(&round.flight);
                    let c: PackedStringArray = round.candidates.iter().map(GString::from).collect();
                    d.set("cands", &c);
                    d.set("hit_r", round.hit_radius);
                    d
                })
            })
            .map(|d| d.to_variant())
            .collect()
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafLcos {
    lcos: Lcos,
}

#[godot_api]
impl IafLcos {
    #[func]
    fn reset(&mut self) {
        self.lcos.reset();
    }

    /// One frame in HUD mode 3: the flight model's state() (pitch, roll, heading, velocity, g, alpha) and the
    /// radar lock's range in metres (null: none).
    #[func]
    fn step(&mut self, t: f64, st: VarDictionary, lock_range: Variant) {
        let f = |k: &str| get::<f64>(&st, k).unwrap_or_default();
        let jet = JetState {
            pitch: f("pitch"),
            roll: f("roll"),
            heading: f("heading"),
            speed: get::<Vector3>(&st, "velocity").map_or(0.0, |v| v.length().into()),
            load_factor: f("g"),
            alpha: f("alpha"),
        };
        self.lcos.step(t, &jet, lock_range.try_to().ok());
    }

    /// The pipper off the gun cross in radians (x right, y down).
    #[func]
    fn offset(&self) -> Vector2 {
        let (x, y) = self.lcos.offset;
        Vector2::new(x as f32, y as f32)
    }
}
