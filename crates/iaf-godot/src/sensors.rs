//! `IafEo` (the EO sensor, `iaf_avionics::eo`) and `IafHarm` (the HARM page's emitter list, `iaf_avionics::harm`) for
//! `game/weapons/eo_sensor.gd` and `harm_sensor.gd`. A base is Vector2(heading, pitch).

use crate::world::{get, num, vec3, vector3};
use godot::prelude::*;
use iaf_avionics::eo::{Aim, Eo, Mode};
use iaf_avionics::harm::{self, Emitter, Harm};
use iaf_avionics::Vec3;

fn base(v: Vector2) -> (f64, f64) {
    (v.x.into(), v.y.into())
}

fn v2((x, y): (f64, f64)) -> Vector2 {
    Vector2::new(x as f32, y as f32)
}

/// null → free, a String → that unit, a Vector3 → that point.
fn aim(v: &Variant) -> Aim {
    if let Ok(p) = v.try_to::<Vector3>() {
        Aim::Point(vec3(p))
    } else if let Ok(k) = v.try_to::<GString>() {
        Aim::Unit(k.to_string())
    } else {
        Aim::Free
    }
}

/// `unit_pos(key)` -> Vector3 or null.
fn lookup(f: &Callable) -> impl Fn(&str) -> Option<Vec3> + '_ {
    move |k| f.is_valid().then(|| f.call(&[k.to_variant()])).and_then(|v| v.try_to::<Vector3>().ok()).map(vec3)
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafEo {
    eo: Eo,
}

#[godot_api]
impl IafEo {
    #[func]
    fn set_pan_k(&mut self, k: f64) {
        self.eo.pan_k = k;
    }

    /// `mode` 1 TV, 2 FLIR; `aim` null / a unit key / a world point.
    #[func]
    fn start(&mut self, mode: i64, pod: bool, aim_at: Variant, t: f64) {
        let mode = match mode {
            1 => Mode::Tv,
            2 => Mode::Flir,
            _ => Mode::None,
        };
        self.eo.start(mode, pod, aim(&aim_at), t);
    }

    #[func]
    fn stop(&mut self) {
        self.eo.stop();
    }

    #[func]
    fn set_laser(&mut self, on: bool) {
        self.eo.laser = on;
    }

    #[func]
    fn angles(&mut self, t: f64, b: Vector2, eye: Vector3, unit_pos: Callable) -> Vector2 {
        v2(self.eo.angles(t, base(b), vec3(eye), &lookup(&unit_pos)))
    }

    #[func]
    fn los(&self, ae: Vector2, b: Vector2) -> Vector3 {
        vector3(self.eo.los(base(ae), base(b)))
    }

    #[func]
    #[allow(clippy::too_many_arguments)] // a #[func]: GDScript has no struct to pass
    fn pan(&mut self, x: i64, y: i64, t: f64, b: Vector2, eye: Vector3, centre: Variant, launched: bool, unit_pos: Callable) {
        self.eo.pan((x, y), t, base(b), vec3(eye), aim(&centre), launched, &lookup(&unit_pos));
    }

    #[func]
    fn zoom_step(&mut self, zoom_in: bool) {
        self.eo.zoom_step(zoom_in);
    }

    #[func]
    fn wide_spot(&mut self) {
        self.eo.wide_spot();
    }

    #[func]
    fn laser_key(&mut self, pod_fitted: bool) {
        self.eo.laser_key(pod_fitted);
    }

    /// {zoom, u, v, laser, spot, range}.
    #[func]
    fn flir_page(&self, ae: Vector2, range_m: f64) -> VarDictionary {
        let (zoom, u, v, range) = self.eo.flir_page(base(ae), range_m);
        vdict! { "zoom" => zoom, "u" => u, "v" => v, "laser" => self.eo.laser, "spot" => self.eo.spot(), "range" => range.as_str() }
    }

    /// {status, zoom, u, v}.
    #[func]
    fn tv_page(&self, ae: Vector2, status: i64) -> VarDictionary {
        let (zoom, u, v) = self.eo.tv_page(base(ae));
        vdict! { "status" => status, "zoom" => zoom, "u" => u, "v" => v }
    }

    /// {mode, camera, limits [az, el max, el min], track (1 free, 2 tracking), point, target ("" none), zoom, spot,
    /// laser, rate (rad/s), frozen (base or null)}.
    #[func]
    fn state(&self) -> VarDictionary {
        let e = &self.eo;
        let l = e.limits();
        let (track, target) = match e.aim() {
            Aim::Free => (1, ""),
            Aim::Point(_) => (2, ""),
            Aim::Unit(k) => (2, k.as_str()),
        };
        vdict! {
            "mode" => e.mode as i64, "camera" => e.camera(), "limits" => &varray![l.az, l.el_max, l.el_min],
            "track" => track, "point" => vector3(e.point()), "target" => target, "zoom" => e.zoom(),
            "spot" => e.spot(), "laser" => e.laser, "rate" => v2(e.rate()),
            "frozen" => &e.frozen().map_or(Variant::nil(), |b| v2(b).to_variant()),
        }
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafHarm {
    harm: Harm,
}

#[godot_api]
impl IafHarm {
    #[func]
    fn field() -> f64 {
        harm::FIELD
    }

    #[func]
    fn set_active(&mut self, on: bool) {
        self.harm.active = on;
    }

    /// A capture from the RWR's slots [{unit, type, pos, active}].
    #[func]
    fn capture(&mut self, slots: VarArray, eye: Vector3, b: Vector2) {
        let emitters: Vec<Emitter> = slots
            .iter_shared()
            .filter_map(|s| s.try_to::<VarDictionary>().ok())
            .filter_map(|s| {
                let key = get::<GString>(&s, "unit").unwrap_or_default().to_string();
                (!key.is_empty()).then(|| Emitter {
                    key,
                    type_code: num(&s, "type").unwrap_or_default() as i64,
                    pos: vec3(get(&s, "pos").unwrap_or_default()),
                    active: get(&s, "active").unwrap_or(false),
                })
            })
            .collect();
        self.harm.capture(&emitters, vec3(eye), base(b));
    }

    #[func]
    fn select(&mut self, key: GString) {
        self.harm.select(&key.to_string());
    }

    /// The heading / pitch change since the capture.
    #[func]
    fn drift(&self, b: Vector2) -> Vector2 {
        v2(self.harm.drift(base(b)))
    }

    /// {list [{key, type, az, el, dist}], selected ("" none)}.
    #[func]
    fn state(&self) -> VarDictionary {
        let list: VarArray = self
            .harm
            .list()
            .iter()
            .map(|c| vdict! { "key" => c.key.as_str(), "type" => c.type_code, "az" => c.az, "el" => c.el, "dist" => c.dist }.to_variant())
            .collect();
        vdict! { "list" => &list, "selected" => self.harm.selected().unwrap_or("") }
    }
}
