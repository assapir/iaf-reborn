//! `IafDelivery`: Modern IAF's F-16 release submodes, fuzing and the LOW cue (`iaf_avionics::delivery`) as statics for
//! `shared/weapons/player_weapons.gd` (modern-iaf/docs/weapons.md §9).

use crate::world::{get, num, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::delivery::{self, Fuze, Shot, Submode};

fn name(s: &GString) -> String {
    s.to_string()
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafDelivery {}

#[godot_api]
impl IafDelivery {
    /// The release computer this frame (`delivery::solve`). `s` {submode ("CCIP" … "MAN"), p, v (world), beta, wind,
    /// target (world point or null), ground (the ground's height under the jet, m), arm_delay (s)} → {release, low,
    /// fall_s, min_release_m, along, cross, ttr (s or null), pull_up (s or null), impact (world point or null)}.
    #[func]
    fn solve(s: VarDictionary) -> VarDictionary {
        let v = |k: &str| vec3(get::<Vector3>(&s, k).unwrap_or_default());
        let shot = Shot {
            submode: Submode::from_name(&name(&get::<GString>(&s, "submode").unwrap_or_default())),
            p: v("p"),
            v: v("v"),
            beta: num(&s, "beta").unwrap_or_default(),
            wind: v("wind"),
            target: get::<Vector3>(&s, "target").map(vec3),
            ground: num(&s, "ground").unwrap_or_default(),
            arm_delay: num(&s, "arm_delay").unwrap_or(delivery::ARM_DELAY),
        };
        let r = delivery::solve(&shot);
        let opt = |o: Option<f64>| o.map_or(Variant::nil(), |x| x.to_variant());
        vdict! {
            "release" => r.release, "low" => r.low, "fall_s" => r.fall_s, "min_release_m" => r.min_release_m,
            "along" => r.along, "cross" => r.cross, "ttr" => &opt(r.ttr), "pull_up" => &opt(r.pull_up),
            "impact" => &r.impact.map_or(Variant::nil(), |p| vector3(p).to_variant()),
        }
    }

    /// The release waits for the solution and goes by itself (CCRP, DTOS, LADD).
    #[func]
    fn automatic(submode: GString) -> bool {
        Submode::from_name(&name(&submode)).automatic()
    }

    /// The missile step switch in A-G: the next submode (CCIP → DTOS → CCRP → CCIP).
    #[func]
    fn step(submode: GString) -> GString {
        GString::from(Submode::from_name(&name(&submode)).step().name())
    }

    /// OSB 18: the next fuze option (NSTL → NOSE → TAIL).
    #[func]
    fn next_fuze(fuze: GString) -> GString {
        GString::from(Fuze::from_name(&name(&fuze)).next().name())
    }

    /// The next arming delay (s), wrapping; `arm_delay` (s) the default one.
    #[func]
    fn next_arm_delay(ad: f64) -> f64 {
        delivery::next_arm_delay(ad)
    }

    #[func]
    fn arm_delay() -> f64 {
        delivery::ARM_DELAY
    }

    /// A bomb released at `released` has armed by `now` (a sooner hit is a dud).
    #[func]
    fn armed(released: f64, now: f64, arm_delay: f64) -> bool {
        delivery::armed(released, now, arm_delay)
    }
}
