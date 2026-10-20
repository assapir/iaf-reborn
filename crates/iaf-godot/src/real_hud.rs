//! `IafRealHud`: the Real HUD's layout (`iaf_avionics::real_hud`, docs/real-hud.md) for `game/cockpit/hud.gd`. The
//! primitives come back as dictionaries in HUD pixels from the HUD centre: {k: "line", a, b}, {k: "circle", c, r},
//! {k: "dot", c, r}, {k: "arc", c, r, from, sweep (radians clockwise from 12 o'clock)}, {k: "text", at, text, align
//! (0 left, 1 centre, 2 right)}.

use crate::world::{get, num};
use godot::prelude::*;
use iaf_avionics::missile::Dlz;
use iaf_avionics::real_hud::{Align, Delay, Field, Input, Jet, P, Prim, RealHud, Steerpoint, Target, Weapons};

fn v2((x, y): P) -> Vector2 {
    Vector2::new(x as f32, y as f32)
}

fn prims(ps: &[Prim]) -> VarArray {
    ps.iter()
        .map(|p| {
            match p {
                Prim::Line { a, b } => vdict! { "k" => "line", "a" => v2(*a), "b" => v2(*b) },
                Prim::Circle { c, r } => vdict! { "k" => "circle", "c" => v2(*c), "r" => *r },
                Prim::Dot { c, r } => vdict! { "k" => "dot", "c" => v2(*c), "r" => *r },
                Prim::Arc { c, r, from, sweep } => {
                    vdict! { "k" => "arc", "c" => v2(*c), "r" => *r, "from" => *from, "sweep" => *sweep }
                }
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

/// A Vector2 entry as a point (null / missing: None).
fn pt(d: &VarDictionary, k: &str) -> Option<P> {
    get::<Vector2>(d, k).map(|v| (f64::from(v.x), f64::from(v.y)))
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafRealHud {
    hud: RealHud,
}

#[godot_api]
impl IafRealHud {
    /// The F-16's ground avoidance advisory (GAAF, `iaf_avionics::gaaf::advisory`): the break X and "PULL UP".
    #[func]
    fn gaaf(agl_ft: f64, kcas: f64, tas_ms: f64, vs_fpm: f64, roll_deg: f64, gear_down: bool, ag: bool) -> bool {
        iaf_avionics::gaaf::advisory(agl_ft, kcas, tas_ms, vs_fpm, roll_deg, gear_down, ag)
    }

    /// The F-16's CARA ALOW voice ("ALTITUDE", `iaf_avionics::gaaf::alow`).
    #[func]
    fn alow(agl_ft: f64, vs_fpm: f64, gear_down: bool) -> bool {
        iaf_avionics::gaaf::alow(agl_ft, vs_fpm, gear_down)
    }

    #[func]
    fn reset_max_g(&mut self) {
        self.hud.reset_max_g();
    }

    /// One frame. `field` the symbology field (Rect2, HUD px from the HUD centre); `i` {cockpit (the cockpit dir), time, off_boresight, head_heading, head_view, head_rel ([az, el]),
    /// kcas, ground_kt, tas_ms, alt_ft, agl_ft (null), vs_fpm, heading, pitch, roll, mach, g, aoa, gear_down, fuel_lbs, fpm
    /// (null), boresight, gun_cross, horizon, px_per_deg, radar_mode, ils (the ILS bars' [x, y] or null), steerpoint ({number, bearing, dist_m, eta_s, at} or {}),
    /// target ({range_m, closure, at, aspect} or {}), dlz ([max, min] or []), weapons {hud_mode, selected, srm, mrm, seeker,
    /// lcos, pipper, steering, circle, shoot, delay (the delayed CCIP's time to go, or null), delay_at
    /// (the target under its pipper), designated}}. Returns {field, outer, colour (Color or null), sight (no HUD)}.
    #[func]
    fn frame(&mut self, field: Rect2, i: VarDictionary) -> VarDictionary {
        let f = |k: &str| num(&i, k).unwrap_or_default();
        let dict = |k: &str| get::<VarDictionary>(&i, k).filter(|d| !d.is_empty());
        let w = dict("weapons").unwrap_or_default();
        let wn = |k: &str| num(&w, k).unwrap_or_default();
        let input = Input {
            jet: Jet::of_cockpit(&get::<GString>(&i, "cockpit").unwrap_or_default().to_string()),
            time_s: f("time"),
            off_boresight: get(&i, "off_boresight").unwrap_or(false),
            head_heading_deg: f("head_heading"),
            head_view: pt(&i, "head_view").unwrap_or_default(),
            head_rel_deg: pt(&i, "head_rel").unwrap_or_default(),
            kcas: f("kcas"),
            ground_kt: f("ground_kt"),
            tas_ms: f("tas_ms"),
            alt_ft: f("alt_ft"),
            agl_ft: num(&i, "agl_ft"),
            vs_fpm: f("vs_fpm"),
            heading_deg: f("heading"),
            pitch_deg: f("pitch"),
            roll_deg: f("roll"),
            mach: f("mach"),
            g: f("g"),
            aoa_deg: f("aoa"),
            gear_down: get(&i, "gear_down").unwrap_or(false),
            fuel_lbs: f("fuel_lbs"),
            fpm: pt(&i, "fpm"),
            boresight: pt(&i, "boresight").unwrap_or_default(),
            gun_cross: pt(&i, "gun_cross").unwrap_or_default(),
            horizon: pt(&i, "horizon").unwrap_or_default(),
            px_per_deg: f("px_per_deg"),
            radar_mode: f("radar_mode") as i64,
            ils: pt(&i, "ils"),
            steerpoint: dict("steerpoint").map(|s| Steerpoint {
                number: num(&s, "number").unwrap_or_default() as i64,
                bearing_deg: num(&s, "bearing").unwrap_or_default(),
                dist_m: num(&s, "dist_m").unwrap_or_default(),
                eta_s: num(&s, "eta_s"),
                at: pt(&s, "at"),
            }),
            target: dict("target").map(|t| Target {
                range_m: num(&t, "range_m").unwrap_or_default(),
                closure: num(&t, "closure").unwrap_or_default(),
                at: pt(&t, "at"),
                aspect: num(&t, "aspect"),
            }),
            dlz: get::<VarArray>(&i, "dlz").and_then(|a| {
                let at = |k| a.get(k).and_then(|v| v.try_to::<f64>().ok());
                at(0).zip(at(1)).map(|(max, min)| Dlz { max, min })
            }),
            weapons: Weapons {
                hud_mode: wn("hud_mode") as i64,
                selected: wn("selected") as i64,
                srm: wn("srm") as i64,
                mrm: wn("mrm") as i64,
                seeker: pt(&w, "seeker"),
                lcos: pt(&w, "lcos"),
                pipper: pt(&w, "pipper"),
                steering: pt(&w, "steering"),
                circle: wn("circle"),
                shoot: get(&w, "shoot").unwrap_or(false),
                delay: num(&w, "delay").map(|ttg| Delay {
                    ttg,
                    target: pt(&w, "delay_at"),
                    designated: get(&w, "designated").unwrap_or(false),
                }),
            },
        };
        let r = Field {
            left: field.position.x.into(),
            top: field.position.y.into(),
            right: field.end().x.into(),
            bottom: field.end().y.into(),
        };
        let out = self.hud.frame(r, &input);
        let colour = out.colour.map_or(Variant::nil(), |[r, g, b]| Color::from_rgb(r, g, b).to_variant());
        vdict! {
            "field" => &prims(&out.field), "outer" => &prims(&out.outer), "colour" => &colour, "sight" => out.sight,
        }
    }
}
