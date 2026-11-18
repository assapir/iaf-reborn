//! `IafRealHud`: the Real HUD's layout (`iaf_avionics::real_hud`, docs/real-hud.md) for `shared/cockpit/hud.gd`. The
//! primitives come back as dictionaries in HUD pixels from the HUD centre: {k: "line", a, b}, {k: "circle", c, r},
//! {k: "dot", c, r}, {k: "arc", c, r, from, sweep (radians clockwise from 12 o'clock)}, {k: "text", at, text, align
//! (0 left, 1 centre, 2 right)}.

use crate::world::{get, num, v2};
use godot::prelude::*;
use iaf_avionics::aiff::Ident;
use iaf_avionics::gps::Lar;
use iaf_avionics::missile::Dlz;
use iaf_avionics::real_hud::{
    AcmCue, Align, AltSwitch, Delay, Field, FpmSwitch, GpsCue, Hobs, Input, Jet, P, Panel, Prim, RealHud, Scales,
    Steerpoint, Target, Velocity, Weapons,
};

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

/// Modern IAF's F-16 HUD panel {scales (0 VV/VAH, 1 VAH, 2 OFF), fpm (0 ATT/FPM, 1 FPM, 2 OFF), velocity (0 CAS,
/// 1 TAS, 2 GND SPD), alt (0 RADAR, 1 BARO, 2 AUTO), ded (the DED's lines, [] OFF), depr_mr (or null), alow_ft, align
/// (null, false aligning, true ready), over (1 DGFT, 2 MSL OVRD), sim, soi, drift_co}.
fn panel(p: &VarDictionary) -> Panel {
    let k = |key: &str, d: i64| num(p, key).map_or(d, |v| v as i64);
    Panel {
        scales: [Scales::VvVah, Scales::Vah, Scales::Off][k("scales", 1).clamp(0, 2) as usize],
        fpm: [FpmSwitch::AttFpm, FpmSwitch::Fpm, FpmSwitch::Off][k("fpm", 0).clamp(0, 2) as usize],
        velocity: [Velocity::Cas, Velocity::Tas, Velocity::Gnd][k("velocity", 0).clamp(0, 2) as usize],
        alt: [AltSwitch::Radar, AltSwitch::Baro, AltSwitch::Auto][k("alt", 1).clamp(0, 2) as usize],
        ded: get::<PackedStringArray>(p, "ded")
            .map(|a| a.as_slice().iter().map(|s| s.to_string()).collect())
            .unwrap_or_default(),
        depr_mr: num(p, "depr_mr"),
        alow_ft: num(p, "alow_ft"),
        align: get::<bool>(p, "align"),
        over: k("over", 0).clamp(0, 2) as u8,
        sim: get(p, "sim").unwrap_or(false),
        soi: get(p, "soi").unwrap_or(false),
        drift_co: get(p, "drift_co").unwrap_or(false),
    }
}

/// Modern IAF's F-16 release submode {submode ("CCIP" … "MAN"), td (the TD box, HUD px, or null), designated, ttr,
/// pull_up (s or null), low, min_release_ft (or null), man_mr (or null)} (`DeliveryCue`).
fn delivery(d: &VarDictionary) -> iaf_avionics::real_hud::DeliveryCue {
    iaf_avionics::real_hud::DeliveryCue {
        submode: iaf_avionics::delivery::Submode::from_name(
            &get::<GString>(d, "submode").unwrap_or_default().to_string(),
        ),
        td: pt(d, "td"),
        designated: get(d, "designated").unwrap_or(false),
        ttr: num(d, "ttr"),
        pull_up: num(d, "pull_up"),
        low: get(d, "low").unwrap_or(false),
        min_release_ft: num(d, "min_release_ft"),
        man_mr: num(d, "man_mr"),
    }
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

    /// The F-16's CARA ALOW voice ("ALTITUDE", `iaf_avionics::gaaf::alow`) below `alow_ft` (the DED's ALOW page in
    /// Modern IAF, `gaaf::ALOW_FT` otherwise).
    #[func]
    fn alow(agl_ft: f64, vs_fpm: f64, gear_down: bool, alow_ft: f64) -> bool {
        iaf_avionics::gaaf::alow(agl_ft, vs_fpm, gear_down, alow_ft)
    }

    /// Extras "Real Betty": the sim's Betty sub code a real jet of voice `set` speaks for the game's call `sub`
    /// ("vms", "f15", "tones"; `iaf_avionics::betty::real_call`), "" when it says nothing.
    #[func]
    fn real_betty(set: GString, sub: GString) -> GString {
        iaf_avionics::betty::real_call(&set.to_string(), &sub.to_string()).unwrap_or_default().into()
    }

    /// Real view (`Jet::real_view_px_per_deg`): the HUD px per degree that fit the cockpit `dir`'s real HUD field in
    /// its glass `field` (HUD px from the HUD centre); 0: keep the original projection.
    #[func]
    fn real_view_px_per_deg(dir: GString, field: Rect2) -> f64 {
        let f = Field {
            left: field.position.x.into(),
            top: field.position.y.into(),
            right: field.end().x.into(),
            bottom: field.end().y.into(),
        };
        Jet::of_cockpit(&dir.to_string()).real_view_px_per_deg(f).unwrap_or(0.0)
    }

    /// True when the cockpit `dir`'s display is its helmet, with no glass (the F-35's: `Jet::fov_deg` None).
    #[func]
    fn helmet_only(dir: GString) -> bool {
        Jet::of_cockpit(&dir.to_string()).fov_deg().is_none()
    }

    #[func]
    fn reset_max_g(&mut self) {
        self.hud.reset_max_g();
    }

    /// The F-16 ICP's WARN RESET (`RealHud::warn_reset`): the FUEL cue out until the fuel is above the bingo again.
    #[func]
    fn warn_reset(&mut self) {
        self.hud.warn_reset();
    }

    /// One frame. `field` the symbology field (Rect2, HUD px from the HUD centre); `i` {cockpit (the cockpit dir), time, off_boresight, head_heading, head_view, head_rel ([az, el]),
    /// kcas, ground_kt, tas_ms, alt_ft, agl_ft (null), vs_fpm, heading, pitch, roll, mach, g, g_limit, aoa, gear_down, fuel_lbs, bingo_lbs, fpm
    /// (null), boresight, gun_cross, horizon, px_per_deg, radar_mode, acm (the real FCR's
    /// ACM pattern: 1 the 10 × 60, 2 SLEW at acm_at ([az, el] deg), 3 BORE; else none), ils (the ILS bars' [x, y] or null), steerpoint ({number, bearing, dist_m, eta_s, at} or {}),
    /// target ({range_m, closure, at, aspect, ident ("friend" / "unknown" / "hostile", the F-35I's combat ID)} or {}), maw ([{bearing, tti}], the MAW's warnings), dlz ([max, min] or []), weapons {hud_mode, name, selected, srm, mrm, seeker,
    /// lcos, pipper, steering, circle, shoot, delay (the delayed CCIP's time to go, or null), delay_at
    /// (the target under its pipper), designated, gps ({pre, at, range, rmin, rmax, in_range, tmr} or {}), hobs ({cone, at (the seeker's target or null), loal} or {}), delivery (`delivery`, or {})}}. Returns {field, outer, colour (Color or null), sight (no HUD), mrm_inside (the MRM dot in the drawn circle, or null)}.
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
            g_limit: f("g_limit"),
            aoa_deg: f("aoa"),
            gear_down: get(&i, "gear_down").unwrap_or(false),
            fuel_lbs: f("fuel_lbs"),
            bingo_lbs: f("bingo_lbs"),
            fpm: pt(&i, "fpm"),
            boresight: pt(&i, "boresight").unwrap_or_default(),
            gun_cross: pt(&i, "gun_cross").unwrap_or_default(),
            horizon: pt(&i, "horizon").unwrap_or_default(),
            px_per_deg: f("px_per_deg"),
            radar_mode: f("radar_mode") as i64,
            acm: match f("acm") as i64 {
                1 => Some(AcmCue::Sixty),
                2 => pt(&i, "acm_at").map(|(az, el)| AcmCue::Slew { az, el }),
                3 => Some(AcmCue::Bore),
                _ => None,
            },
            agr_m: num(&i, "agr_m"),
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
                ident: get::<GString>(&t, "ident")
                    .and_then(|n| [Ident::Friend, Ident::Unknown, Ident::Hostile].into_iter().find(|k| n == k.name())),
            }),
            dlz: get::<VarArray>(&i, "dlz").and_then(|a| {
                let at = |k| a.get(k).and_then(|v| v.try_to::<f64>().ok());
                at(0).zip(at(1)).map(|(max, min)| Dlz { max, min })
            }),
            weapons: Weapons {
                hud_mode: wn("hud_mode") as i64,
                name: get::<GString>(&w, "name").unwrap_or_default().to_string(),
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
                gps: get::<VarDictionary>(&w, "gps").filter(|g| !g.is_empty()).map(|g| GpsCue {
                    pre: get(&g, "pre").unwrap_or(false),
                    at: pt(&g, "at"),
                    lar: Lar {
                        range: num(&g, "range").unwrap_or_default(),
                        rmin: num(&g, "rmin").unwrap_or_default(),
                        rmax: num(&g, "rmax").unwrap_or_default(),
                        in_range: get(&g, "in_range").unwrap_or(false),
                        tmr: num(&g, "tmr"),
                    },
                }),
                tti: num(&w, "tti"),
                hobs: get::<VarDictionary>(&w, "hobs").filter(|h| !h.is_empty()).map(|h| Hobs {
                    cone_deg: num(&h, "cone").unwrap_or_default(),
                    target: pt(&h, "at"),
                    loal: get(&h, "loal").unwrap_or(false),
                }),
                delivery: get::<VarDictionary>(&w, "delivery").filter(|d| !d.is_empty()).map(|d| delivery(&d)),
                srm_track: get(&w, "srm_track").unwrap_or(false),
                // {active, s}; absent or null: no missile flying.
                msl_time: get::<VarDictionary>(&w, "msl_time").filter(|m| !m.is_empty()).map(|m| {
                    iaf_avionics::real_hud::MslTime {
                        active: get(&m, "active").unwrap_or(false),
                        s: num(&m, "s").unwrap_or_default(),
                    }
                }),
            },
            maw: get::<VarArray>(&i, "maw")
                .unwrap_or_default()
                .iter_shared()
                .filter_map(|v| v.try_to::<VarDictionary>().ok())
                .map(|m| (num(&m, "bearing").unwrap_or_default(), num(&m, "tti").unwrap_or(f64::INFINITY)))
                .collect(),
            panel: dict("panel").map(|p| panel(&p)).unwrap_or_default(),
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
            "mrm_inside" => &out.mrm_inside.map_or(Variant::nil(), |b| b.to_variant()),
        }
    }
}
