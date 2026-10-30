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
    if w.hud_mode == 1 && w.hobs.is_some() {
        hobs_cues(o, i, c, r);
    } else if w.hud_mode == 1
        && let Some(p) = w.seeker.filter(|p| inside(*p))
    {
        diamond(o, p, i.mr(8.0));
    }
    fr
}

/// The high off-boresight missile's cues on a helmet set centred on its line of sight `c`, `r` px to its edge (the
/// AIM-9X / Python 5, docs/real-hud.md "DASH helmet"; the JHMCS's in a simulator guide, the layout inferred):
/// - the seeker diamond: on its target while it tracks one (held on the edge when the target is outside the set); else
///   on the aiming cross, the seeker slaved to the helmet, while the head looks within the missile's cone of the nose;
/// - beyond the cone the seeker stops at its gimbal limit: the diamond on the edge toward the nose, an X over it;
/// - SHOOT under the cross with the mode-1 shoot cue (the seeker's lock in range), LOAL flashing under it while a
///   missile launched without a lock still searches.
pub(super) fn hobs_cues(o: &mut Vec<Prim>, i: &Input, c: P, r: f64) {
    let w = &i.weapons;
    let Some(h) = w.hobs else { return };
    let size = i.mr(8.0);
    let on_edge = |d: P| {
        let n = d.0.hypot(d.1);
        let k = if n > r - size { (r - size) / n } else { 1.0 };
        ((c.0 + d.0 * k, c.1 + d.1 * k), k < 1.0)
    };
    let (az, el) = i.head_rel_deg;
    let off = (az.to_radians().cos() * el.to_radians().cos()).clamp(-1.0, 1.0).acos().to_degrees();
    if let Some(s) = h.target {
        diamond(o, on_edge((s.0 - c.0, s.1 - c.1)).0, size);
    } else if off <= h.cone_deg {
        diamond(o, c, size);
    } else {
        // Toward the nose: left and down from a head turned right and up (screen y down).
        let n = az.hypot(el).max(1e-9);
        let (q, _) = on_edge((-az / n * r, el / n * r));
        diamond(o, q, size);
        x_over(o, q, size);
    }
    if w.shoot {
        o.push(text(add(c, (0.0, 0.4 * r)), "SHOOT", Align::Centre));
    }
    if h.loal && i.time_s.rem_euclid(1.0) < 0.5 {
        o.push(text(add(c, (0.0, 0.4 * r + ROW)), "LOAL", Align::Centre));
    }
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

    /// A diamond of half size `h` centred near `c`.
    fn diamond_at(ps: &[Prim], c: P, h: f64) -> bool {
        let near = |a: P, b: P| (a.0 - b.0).abs() < 0.01 && (a.1 - b.1).abs() < 0.01;
        ps.iter().any(|p| matches!(p, Prim::Line { a, b } if near(*a, (c.0, c.1 - h)) && near(*b, (c.0 + h, c.1))))
    }

    /// The Sufa's DASH with an AIM-9X (cone 90°), the head 70° left of the nose.
    fn hobs_input(jet: Jet) -> Input {
        let mut i = Input { off_boresight: true, ..input(jet) };
        i.head_view = (10.0, -5.0);
        i.head_rel_deg = (-70.0, 0.0);
        i.weapons.hud_mode = 1;
        i.weapons.srm = 2;
        i.weapons.hobs = Some(Hobs { cone_deg: 90.0, target: None, loal: false });
        i
    }

    #[test]
    fn hobs_seeker_slaved_to_the_helmet_then_on_its_target() {
        let mut i = hobs_input(Jet::F16);
        let h = i.mr(8.0);
        let fr = RealHud::default().frame(FIELD, &i);
        assert!(diamond_at(&fr.outer, (10.0, -5.0), h), "no target: the seeker on the aiming cross");
        assert!(!texts(&fr.outer).contains(&"SHOOT"));
        // The seeker takes the target 4° right of the cross and locks in range: the diamond on it, SHOOT.
        i.weapons.hobs = Some(Hobs { cone_deg: 90.0, target: Some((58.0, -5.0)), loal: false });
        i.weapons.shoot = true;
        let fr = RealHud::default().frame(FIELD, &i);
        assert!(diamond_at(&fr.outer, (58.0, -5.0), h), "the diamond on the target");
        assert!(!diamond_at(&fr.outer, (10.0, -5.0), h), "not on the cross any more");
        assert!(texts(&fr.outer).contains(&"SHOOT"));
        // A target outside the 20° field: the diamond held on its edge toward it.
        i.weapons.hobs = Some(Hobs { cone_deg: 90.0, target: Some((1000.0, -5.0)), loal: false });
        let r = i.deg(10.0);
        assert!(diamond_at(&RealHud::default().frame(FIELD, &i).outer, (10.0 + r - h, -5.0), h));
    }

    #[test]
    fn hobs_seeker_limit_beyond_the_cone() {
        let mut i = hobs_input(Jet::F16);
        i.head_rel_deg = (-120.0, 0.0);
        let (h, r) = (i.mr(8.0), i.deg(10.0));
        let fr = RealHud::default().frame(FIELD, &i);
        // The head 120° left, the cone 90°: the diamond stops on the edge toward the nose (right), crossed out.
        let q = (10.0 + r - h, -5.0);
        assert!(diamond_at(&fr.outer, q, h), "the diamond at the gimbal limit");
        assert!(fr.outer.iter().any(|p| matches!(p, Prim::Line { a, .. } if *a == (q.0 - h, q.1 - h))), "X over it");
        // The Python 5's 100° cone takes 95°.
        i.head_rel_deg = (-95.0, 0.0);
        i.weapons.hobs = Some(Hobs { cone_deg: 100.0, target: None, loal: false });
        assert!(diamond_at(&RealHud::default().frame(FIELD, &i).outer, (10.0, -5.0), h));
    }

    #[test]
    fn hobs_loal_flashes_while_the_missile_searches() {
        let mut i = hobs_input(Jet::F15);
        i.weapons.hobs = Some(Hobs { cone_deg: 100.0, target: None, loal: true });
        i.time_s = 10.2;
        assert!(texts(&RealHud::default().frame(FIELD, &i).outer).contains(&"LOAL"));
        i.time_s = 10.7;
        assert!(!texts(&RealHud::default().frame(FIELD, &i).outer).contains(&"LOAL"), "the dark half");
        // The F-35I's head set draws the same cues around its centre.
        let mut j = hobs_input(Jet::F35);
        j.weapons.shoot = true;
        let fr = RealHud::default().frame(FIELD, &j);
        assert!(diamond_at(&fr.outer, (0.0, 0.0), j.mr(8.0)) && texts(&fr.outer).contains(&"SHOOT"));
    }

    #[test]
    fn the_hud_when_looking_ahead() {
        let fr = RealHud::default().frame(FIELD, &input(Jet::F16));
        assert_ne!(fr.colour, Some(GREEN));
    }
}
