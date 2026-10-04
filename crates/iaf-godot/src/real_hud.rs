//! `IafRealHud`: the Real HUD's layout (`iaf_avionics::real_hud`) for `game/cockpit/hud.gd`. The primitives come back
//! as dictionaries in HUD pixels from the HUD centre: {k: "line", a, b}, {k: "circle", c, r}, {k: "text", at, text,
//! align (0 left, 1 centre, 2 right)}.

use crate::world::{get, num};
use godot::prelude::*;
use iaf_avionics::real_hud::{Align, Field, Input, Prim, RealHud, Steerpoint};

fn v2((x, y): (f64, f64)) -> Vector2 {
    Vector2::new(x as f32, y as f32)
}

fn prims(ps: &[Prim]) -> VarArray {
    ps.iter()
        .map(|p| {
            match p {
                Prim::Line { a, b } => vdict! { "k" => "line", "a" => v2(*a), "b" => v2(*b) },
                Prim::Circle { c, r } => vdict! { "k" => "circle", "c" => v2(*c), "r" => *r },
                Prim::Text { at, text, align } => {
                    let align: i64 = match align {
                        Align::Left => 0,
                        Align::Centre => 1,
                        Align::Right => 2,
                    };
                    vdict! { "k" => "text", "at" => v2(*at), "text" => text.as_str(), "align" => align }
                }
            }
            .to_variant()
        })
        .collect()
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRealHud {
    hud: RealHud,
}

#[godot_api]
impl IafRealHud {
    #[func]
    fn reset_max_g(&mut self) {
        self.hud.reset_max_g();
    }

    /// One frame. `field` the symbology field (Rect2, HUD px from the HUD centre); `i` {kcas, alt_ft, heading, roll,
    /// mach, g, aoa, gear_down, fpm (Vector2 or null), horizon (the level point ahead), px_per_deg, master, steerpoint
    /// ({number, bearing, dist_m, eta_s (null)} or {})}. Returns {field: [prims], outer: [prims]}.
    #[func]
    fn frame(&mut self, field: Rect2, i: VarDictionary) -> VarDictionary {
        let f = |k: &str| num(&i, k).unwrap_or_default();
        let pt = |k: &str| get::<Vector2>(&i, k).map(|v| (f64::from(v.x), f64::from(v.y)));
        let fpm = pt("fpm");
        let steerpoint = get::<VarDictionary>(&i, "steerpoint").filter(|s| !s.is_empty()).map(|s| Steerpoint {
            number: num(&s, "number").unwrap_or_default() as i64,
            bearing_deg: num(&s, "bearing").unwrap_or_default(),
            dist_m: num(&s, "dist_m").unwrap_or_default(),
            eta_s: num(&s, "eta_s"),
        });
        let input = Input {
            kcas: f("kcas"),
            alt_ft: f("alt_ft"),
            heading_deg: f("heading"),
            roll_deg: f("roll"),
            mach: f("mach"),
            g: f("g"),
            aoa_deg: f("aoa"),
            gear_down: get(&i, "gear_down").unwrap_or(false),
            fpm,
            horizon: pt("horizon").unwrap_or_default(),
            px_per_deg: f("px_per_deg"),
            master: get::<GString>(&i, "master").unwrap_or_default().to_string(),
            steerpoint,
        };
        let r = Field {
            left: field.position.x.into(),
            top: field.position.y.into(),
            right: field.end().x.into(),
            bottom: field.end().y.into(),
        };
        let out = self.hud.frame(r, &input);
        vdict! { "field" => &prims(&out.field), "outer" => &prims(&out.outer) }
    }
}
