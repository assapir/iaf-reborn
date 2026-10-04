//! `IafSeeker` (the IR seeker of the SRM HUD mode) and `IafMrmSight` (the radar missiles' / HARM's launch circle)
//! from `iaf_avionics::sight`, for `game/weapons/ir_seeker.gd` and `mrm_sight.gd`.

use crate::world::{get, num, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::missile::Dlz;
use iaf_avionics::sight::{self, Eye, Frame, Heat, Px, RadarLock, Seeker, Tone};

/// Limited heat (580): the ±60° azimuth limit.
const LIMITED_HEAT: i64 = 580;

fn frame(d: &VarDictionary) -> Frame {
    let v = |k: &str| vec3(get(d, k).unwrap_or_default());
    Frame { fwd: v("fwd"), up: v("up"), right: v("right") }
}

/// The own jet {pos, fwd, up, right, yaw, sight: {fwd, up, right}, helmet, view_fwd} (player_weapons.gd `own()`).
fn eye(o: &VarDictionary) -> Eye {
    Eye {
        pos: vec3(get(o, "pos").unwrap_or_default()),
        nose: frame(o),
        yaw: num(o, "yaw").unwrap_or_default(),
        sight: get::<VarDictionary>(o, "sight").map(|s| frame(&s)),
        helmet_axis: get(o, "helmet").unwrap_or(false).then(|| vec3(get(o, "view_fwd").unwrap_or_default())),
    }
}

fn heat(u: &VarDictionary) -> Heat {
    Heat {
        key: get::<GString>(u, "key").unwrap_or_default().to_string(),
        pos: vec3(get(u, "pos").unwrap_or_default()),
        vel: vec3(get(u, "vel").unwrap_or_default()),
        afterburner: get(u, "afterburner").unwrap_or(false),
    }
}

fn heats(units: &VarArray) -> Vec<Heat> {
    units.iter_shared().filter_map(|u| u.try_to::<VarDictionary>().ok()).map(|u| heat(&u)).collect()
}

fn px(off: &Variant) -> Option<Px> {
    off.try_to::<Vector2>().ok().map(|v| Px { x: v.x.into(), y: v.y.into() })
}

fn key(k: Option<&str>) -> GString {
    k.map(GString::from).unwrap_or_default()
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafSeeker {
    seeker: Seeker,
}

#[godot_api]
impl IafSeeker {
    #[func]
    fn set_generation(&mut self, generation: i64) {
        self.seeker.set_generation(generation);
    }

    /// The selected missile record: its generation, then the Real overrides (real_cone_deg, real_rear).
    #[func]
    fn set_weapon(&mut self, w: VarDictionary) {
        let generation = num(&w, "generation").unwrap_or_default() as i64;
        self.seeker.set_weapon(generation, num(&w, "real_cone_deg"), get(&w, "real_rear").unwrap_or(false));
    }

    #[func]
    fn rear_only(&self) -> bool {
        self.seeker.rear_only
    }

    #[func]
    fn lock_range(&self) -> f64 {
        self.seeker.lock_range()
    }

    /// The radar's locked unit ("" none) and its A-A flag.
    #[func]
    fn set_radar(&mut self, key: GString, air_to_air: bool) {
        self.seeker.radar = (!key.is_empty()).then(|| RadarLock { key: key.to_string(), air_to_air });
    }

    #[func]
    fn can_track(&self, own: VarDictionary, u: VarDictionary, type_code: i64) -> bool {
        self.seeker.can_track(&eye(&own), &heat(&u), type_code == LIMITED_HEAT)
    }

    #[func]
    fn in_view(&self, own: VarDictionary, u: VarDictionary) -> bool {
        self.seeker.in_view(&eye(&own), &heat(&u))
    }

    #[func]
    fn slaved(&self) -> bool {
        self.seeker.slaved()
    }

    /// One frame of the IR mode; `units` [{key, pos, vel, afterburner}].
    #[func]
    fn update(&mut self, now: f64, own: VarDictionary, units: VarArray, type_code: i64, have_rounds: bool) {
        self.seeker.update(now, &eye(&own), &heats(&units), type_code == LIMITED_HEAT, have_rounds);
    }

    /// The key of the target a launch takes ("" none).
    #[func]
    fn target_in_circle(&self, own: VarDictionary, units: VarArray) -> GString {
        let units = heats(&units);
        key(self.seeker.target_in_circle(&eye(&own), &units).map(|u| u.key.as_str()))
    }

    #[func]
    fn target_key(&self) -> GString {
        key(self.seeker.target())
    }

    #[func]
    fn lock(&self) -> bool {
        self.seeker.locked()
    }

    #[func]
    fn symbol(&self) -> Vector2 {
        let s = self.seeker.symbol();
        Vector2::new(s.x as f32, s.y as f32)
    }

    /// "seek", "lock" or "" (both off).
    #[func]
    fn tone(&self) -> GString {
        match self.seeker.tone() {
            Tone::Off => "",
            Tone::Seek => "seek",
            Tone::Lock => "lock",
        }
        .into()
    }

    #[func]
    fn start_empty_chirp(&mut self) {
        self.seeker.start_empty_chirp();
    }

    #[func]
    fn exit(&mut self) {
        self.seeker.exit();
    }

    /// The screen offset (px from the HUD centre, x right, y down) of a world point; null when behind.
    #[func]
    fn screen_offset(own: VarDictionary, p: Vector3) -> Variant {
        eye(&own).screen_offset(vec3(p)).map_or(Variant::nil(), |o| Vector2::new(o.x as f32, o.y as f32).to_variant())
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafMrmSight {}

#[godot_api]
impl IafMrmSight {
    /// `FUN_00462c10`: the circle size from the DLZ [max, min] ([] none) and the target's distance.
    #[func]
    fn circle(locked: bool, dlz: VarArray, dist: f64) -> f64 {
        let at = |i| dlz.get(i).and_then(|v| v.try_to::<f64>().ok());
        let z = at(0).zip(at(1)).map(|(max, min)| Dlz { max, min });
        sight::circle(locked, z, dist)
    }

    #[func]
    fn predicted(pos: Vector3, vel: Vector3, dist: f64) -> Vector3 {
        vector3(sight::predicted(vec3(pos), vec3(vel), dist))
    }

    /// `off` = the target's screen offset (null behind).
    #[func]
    fn target_in_circle(off: Variant, locked: bool) -> bool {
        sight::target_in_circle(px(&off), locked)
    }

    /// [inside, q].
    #[func]
    fn in_circle(off: Variant, r: f64, hud_only: bool) -> VarArray {
        let (inside, q) = sight::in_circle(px(&off), r, hud_only);
        varray![inside, q]
    }
}
