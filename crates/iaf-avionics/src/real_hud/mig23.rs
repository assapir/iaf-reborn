//! The MiG-23ML's АСП-17МЛ sight (docs/mig-cockpits.md §5, docs/real-hud.md "MiG-23ML"). The ML has no radar scope:
//! the Sapfir-23ML's target, the IRST data and the gun reticle go onto the sight. Public: the designation limits
//! (+16 / −18° vertically, ±12° in azimuth), «НОП» (aiming error too large), «ПР» (launch authorised), the К / Г
//! director symbols, the range scale in km with Dmin / Dmax. No source shows a ladder, tapes or flight numbers, and the
//! reticle's drawing is not public: the layout is a reconstruction [R].

use super::*;
use std::f64::consts::TAU;

const ROW: f64 = 9.0;
/// The range scale's steps (km): from 3 km to 20 km [uncertain], 45 km for the R-24R's long range (inferred, the
/// radar's БС II range).
const SCALES_KM: [f64; 5] = [3.0, 5.0, 10.0, 20.0, 45.0];
/// The sight's designation limits (°): up, down, either side.
const LIM_UP: f64 = 16.0;
const LIM_DOWN: f64 = 18.0;
const LIM_SIDE: f64 = 12.0;
/// The gun reticle's range bar: a full turn at this range (m; inferred).
const GUN_FULL_M: f64 = 2000.0;

pub(super) fn frame(f: Field, i: &Input) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let gc = i.gun_cross;
    let p = &mut fr.field;
    // The fixed cross (not in the gun mode: the moving reticle is the aiming mark there).
    if mode != 3 {
        let (g, l) = (i.mr(3.0), i.mr(12.0));
        p.push(line((gc.0 - l, gc.1), (gc.0 - g, gc.1)));
        p.push(line((gc.0 + g, gc.1), (gc.0 + l, gc.1)));
        p.push(line((gc.0, gc.1 - l), (gc.0, gc.1 - g)));
        p.push(line((gc.0, gc.1 + g), (gc.0, gc.1 + l)));
    }
    let mut nop = false;
    match mode {
        0 => {
            // The steering mark: a small ring on the waypoint, an X when held on the field's edge.
            if let Some(at) = i.steerpoint.and_then(|s| s.at) {
                let (q, limited) = f.clamp_from(gc, at);
                let r = i.mr(5.0);
                p.push(Prim::Circle { c: q, r });
                if limited {
                    x_over(p, q, r);
                }
            }
        }
        1 | 2 => {
            if let Some(at) = i.target.and_then(|t| t.at) {
                // The target mark, held at the designation limits: «НОП» beyond them (inferred mapping).
                let lim = Field {
                    left: gc.0 - i.deg(LIM_SIDE),
                    right: gc.0 + i.deg(LIM_SIDE),
                    top: gc.1 - i.deg(LIM_UP),
                    bottom: gc.1 + i.deg(LIM_DOWN),
                };
                let (q, limited) = lim.clamp_from(gc, at);
                nop = limited;
                diamond(p, f.clamp_from(gc, q).0, i.mr(8.0));
            }
            // The IR missile's seeker (the IRST's track, or the seeker searching on the boresight).
            if mode == 1 {
                p.push(Prim::Circle { c: w.seeker.unwrap_or(gc), r: i.mr(6.0) });
            }
        }
        3 => {
            let c = w.lcos.unwrap_or(gc);
            let ro = i.mr(25.0);
            p.push(Prim::Dot { c, r: i.mr(1.0).max(0.8) });
            p.push(Prim::Circle { c, r: ro });
            if let Some(t) = i.target {
                let sweep = (t.range_m / GUN_FULL_M).clamp(0.0, 1.0) * TAU;
                p.push(Prim::Arc { c, r: ro - 1.5, from: 0.0, sweep: sweep.max(0.02) });
            }
        }
        4..=6 => {
            if let Some(c) = w.pipper {
                if mode != 4 {
                    p.push(line(gc, c));
                }
                pipper(p, c, i.mr(1.0).max(0.8), i.mr(10.0));
            }
        }
        _ => {}
    }

    let o = &mut fr.outer;
    if matches!(mode, 1 | 2)
        && let Some(t) = i.target
    {
        let half = 0.3 * (f.bottom - f.top);
        km_scale(o, f.right - 6.0, f.centre_y(), half, t, i.dlz, &SCALES_KM);
    }
    if matches!(mode, 1 | 2) && w.shoot {
        o.push(text((f.left + 2.0, f.top + ROW), "ПР", Align::Left));
    }
    if nop {
        o.push(text((f.left + 2.0, f.top + 2.0 * ROW), "НОП", Align::Left));
    }
    // К (course) and Г (glide) on the director bars the HUD draws with the gear down.
    if mode == 0
        && i.gear_down
        && let Some((x, y)) = i.ils
    {
        o.push(text((x + 3.0, -16.0 - 2.0), "К", Align::Left));
        o.push(text((-16.0 - 3.0, y + 3.0), "Г", Align::Right));
    }
    fr
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    fn with(mode: i64) -> Input {
        let mut i = input(Jet::MiG23);
        i.weapons.hud_mode = mode;
        i.gun_cross = (0.0, 20.0);
        i
    }

    #[test]
    fn nav_has_no_flight_data_only_the_cross_and_steering_ring() {
        let i = with(0);
        let fr = RealHud::default().frame(FIELD, &i);
        assert!(fr.outer.is_empty() && !fr.sight && fr.colour.is_none(), "no numbers, the HUD's colour");
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Circle { c, .. } if *c == (30.0, 20.0))), "steering ring");
        assert!(!fr.field.iter().any(|p| matches!(p, Prim::Text { .. })));
    }

    #[test]
    fn ils_legends_with_the_gear_down() {
        let mut i = with(0);
        i.gear_down = true;
        i.ils = Some((5.0, -4.0));
        let fr = frame(FIELD, &i);
        assert_eq!(texts(&fr.outer), ["К", "Г"]);
    }

    #[test]
    fn missile_range_scale_in_km_launch_and_aiming_error() {
        let mut i = with(2);
        i.target = Some(Target { range_m: 8000.0, closure: 100.0, at: Some((5.0, 0.0)), aspect: None });
        i.dlz = Some(Dlz { max: 15_000.0, min: 1500.0 });
        i.weapons.shoot = true;
        let t = texts(&frame(FIELD, &i).outer).into_iter().map(String::from).collect::<Vec<_>>();
        assert!(t.contains(&"20".into()) && t.contains(&"8.0".into()) && t.contains(&"ПР".into()), "{t:?}");
        assert!(!t.contains(&"НОП".into()));
        // 30° right: outside the ±12° limits, the mark held at 12° (inside the field at 4 px / °), «НОП».
        i.px_per_deg = 4.0;
        i.target.as_mut().unwrap().at = Some((i.deg(30.0), 20.0));
        let fr = frame(FIELD, &i);
        assert!(texts(&fr.outer).contains(&"НОП"));
        let x = i.deg(LIM_SIDE);
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Line { a, .. } if (a.0 - x).abs() < 1e-9)), "held at 12°");
    }

    #[test]
    fn gun_reticle_rides_the_lead_with_a_metre_range_bar() {
        let mut i = with(3);
        i.weapons.lcos = Some((4.0, 30.0));
        i.target = Some(Target { range_m: 1000.0, closure: 0.0, at: None, aspect: None });
        let fr = frame(FIELD, &i);
        let arc =
            fr.field.iter().find_map(|p| if let Prim::Arc { c, sweep, .. } = p { Some((*c, *sweep)) } else { None });
        assert_eq!(arc, Some(((4.0, 30.0), TAU / 2.0)), "1,000 m: half a turn");
    }
}
