//! The Elbit DASH helmet display of the IAF F-16C/D and F-15C/D (docs/real-hud.md "DASH helmet"): drawn while the
//! pilot looks aside with the Real HUD on, head-stabilised around the helmet's line of sight. A 20° circular, green,
//! stroke-written field [S]; the content follows the DASH-derived JHMCS basic / A-A set [SIM] where nothing
//! DASH-specific is public: the aiming cross, the line-of-sight indicator, airspeed, G, altitude, the master mode and
//! arm, the head's heading, the steerpoint, the radar target's box and the IR seeker's diamond.

use super::*;

const GREEN: [f32; 3] = [0.45, 1.0, 0.55];
const ROW: f64 = 9.0;

pub(super) fn frame(i: &Input) -> Frame {
    let mut fr = Frame { colour: Some(GREEN), ..Frame::default() };
    let o = &mut fr.outer;
    let c = i.head_view;
    let at = |dx: f64, dy: f64| (c.0 + dx, c.1 + dy);
    let r = i.deg(10.0);
    let w = &i.weapons;
    aiming_cross(o, i);
    // The line-of-sight indicator: a circle whose gap points where the head looks from the nose (12 o'clock = ahead and
    // up, 3 o'clock = right).
    let (az, el) = i.head_rel_deg;
    let gap = 0.6;
    let dir = az.atan2(el);
    o.push(Prim::Arc { c, r: i.mr(45.0), from: dir + gap / 2.0, sweep: std::f64::consts::TAU - gap });
    // Left: G above the airspeed, the master mode and arm under it; right: altitude, then the steerpoint.
    let (lx, rx, y) = (-0.75 * r, 0.75 * r, -0.15 * r);
    o.push(text(at(lx, y - ROW), format!("{:.1}", i.g), Align::Right));
    o.push(text(at(lx, y), format!("{}", i.kcas.max(0.0).round() as i64), Align::Right));
    o.push(text(at(lx, y + 2.0 * ROW), if w.hud_mode == 0 { "NAV" } else { "ARM" }, Align::Right));
    let weapon = mode_text(w);
    if !weapon.is_empty() {
        o.push(text(at(lx, y + 3.0 * ROW), weapon, Align::Right));
    }
    o.push(text(at(rx, y), format!("{}", i.alt_ft.round() as i64), Align::Left));
    if let Some(s) = i.steerpoint {
        o.push(text(
            at(rx, y + 2.0 * ROW),
            format!("{:03}>{:02}", ((s.dist_m / NM).round() as i64).min(999), s.number),
            Align::Left,
        ));
    }
    // The head's magnetic heading, above the cross (the JHMCS has it at the bottom; ours: the cockpit view's centre
    // sits low on the screen, where the bottom of the field falls off it).
    o.push(text(
        at(0.0, -0.6 * r),
        format!("{:03}", (i.head_heading_deg.round() as i64).rem_euclid(360)),
        Align::Centre,
    ));
    // The radar target's box, the IR seeker's diamond on its target, inside the field only.
    let inside = |p: P| (p.0 - c.0).hypot(p.1 - c.1) <= r;
    if let Some(p) = i.target.and_then(|t| t.at).filter(|p| inside(*p)) {
        let h = i.mr(15.0);
        o.push(line((p.0 - h, p.1 - h), (p.0 + h, p.1 - h)));
        o.push(line((p.0 + h, p.1 - h), (p.0 + h, p.1 + h)));
        o.push(line((p.0 + h, p.1 + h), (p.0 - h, p.1 + h)));
        o.push(line((p.0 - h, p.1 + h), (p.0 - h, p.1 - h)));
    }
    if w.hud_mode == 1
        && let Some(p) = w.seeker.filter(|p| inside(*p))
    {
        diamond(o, p, i.mr(8.0));
    }
    fr
}

/// The helmet's aiming cross: a plus with a centre gap on its line of sight.
pub(super) fn aiming_cross(o: &mut Vec<Prim>, i: &Input) {
    let at = |dx: f64, dy: f64| add(i.head_view, (dx, dy));
    let (g, l) = (i.mr(5.0), i.mr(20.0));
    o.push(line(at(-l, 0.0), at(-g, 0.0)));
    o.push(line(at(g, 0.0), at(l, 0.0)));
    o.push(line(at(0.0, -l), at(0.0, -g)));
    o.push(line(at(0.0, g), at(0.0, l)));
}

fn mode_text(w: &Weapons) -> String {
    match w.hud_mode {
        1 => format!("{} SRM", w.srm),
        2 => format!("{} MRM", w.mrm),
        3 | 4 => "GUN".into(),
        5..=8 => "A-G".into(),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    #[test]
    fn the_helmet_set_on_the_line_of_sight() {
        for jet in [Jet::F16, Jet::F15] {
            let mut i = Input {
                off_boresight: true,
                head_heading_deg: 271.0,
                kcas: 420.0,
                alt_ft: 12_340.0,
                g: 3.2,
                ..input(jet)
            };
            i.head_view = (30.0, -10.0);
            i.head_rel_deg = (-60.0, 5.0);
            let fr = RealHud::default().frame(FIELD, &i);
            assert_eq!(fr.colour, Some(GREEN), "{jet:?}: the DASH's green");
            let t = texts(&fr.outer);
            for want in ["420", "12340", "3.2", "271", "NAV"] {
                assert!(t.contains(&want), "{jet:?}: {want} in {t:?}");
            }
            // The aiming cross on the head's view; the LOS circle's gap toward the left (azimuth −60°).
            assert!(
                fr.outer.iter().any(|p| matches!(p, Prim::Line { a, b } if a.1 == -10.0 && b.1 == -10.0 && a.0 > 30.0))
            );
            assert!(
                fr.outer.iter().any(|p| matches!(p, Prim::Arc { c, from, .. } if *c == (30.0, -10.0) && *from < 0.0))
            );
        }
    }

    #[test]
    fn target_box_and_seeker_only_inside_the_field() {
        let mut i = Input { off_boresight: true, ..input(Jet::F16) };
        i.weapons.hud_mode = 1;
        i.weapons.srm = 2;
        i.target = Some(Target { range_m: 3000.0, closure: 0.0, at: Some((20.0, 0.0)), aspect: None });
        i.weapons.seeker = Some((20.0, 0.0));
        let lines = |i: &Input| {
            RealHud::default().frame(FIELD, i).outer.iter().filter(|p| matches!(p, Prim::Line { .. })).count()
        };
        let near = lines(&i);
        i.target = Some(Target { range_m: 3000.0, closure: 0.0, at: Some((500.0, 0.0)), aspect: None });
        i.weapons.seeker = Some((500.0, 0.0));
        assert_eq!(near - lines(&i), 8, "box (4) and diamond (4) inside, none outside");
        assert!(texts(&RealHud::default().frame(FIELD, &i).outer).contains(&"2 SRM"));
    }

    #[test]
    fn the_hud_when_looking_ahead() {
        let fr = RealHud::default().frame(FIELD, &input(Jet::F16));
        assert_ne!(fr.colour, Some(GREEN));
    }
}
