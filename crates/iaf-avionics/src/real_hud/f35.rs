//! The F-35's helmet display, its forward aircraft-stabilised "virtual HUD" (LM "The F-35 Cockpit" slides, US Navy
//! flight-test video; docs/real-hud.md "F-35I"): boxed airspeed and altitude (no tapes), the GS / M / G / α / max-g
//! stack, vertical velocity and radar altitude, the heading tape on top, the "-W-" waterline, the ladder with inner
//! tips and signed labels, the bank scale at the bottom, the mode / weapon / ARM block and the steerpoint block, the
//! steerpoint's caret under the heading tape and its small square on the ground (both seen in the LM "Virtual HUD
//! Looking Forward" frame). The gun and A-G graphics are not public: the F-16's funnel and pipper stand in
//! (reconstruction). Green.

use super::*;

const ROW: f64 = 9.0;
const HDG_PX: f64 = 2.0;
const HDG_HALF: f64 = 34.0;
const GREEN: [f32; 3] = [0.45, 1.0, 0.55];

/// The helmet's forward symbology spans most of its 40° × 30° field, not the cockpit's HUD glass: ours lays it out in a
/// 32° × 22° field centred on the boresight.
const FIELD_W_DEG: f64 = 32.0;
const FIELD_H_DEG: f64 = 22.0;

pub(super) fn frame(_hud: Field, i: &Input, max_g: f64) -> Frame {
    if i.off_boresight {
        return off_boresight(i);
    }
    let (bx, by) = i.boresight;
    let f = Field {
        left: bx - i.deg(FIELD_W_DEG / 2.0),
        right: bx + i.deg(FIELD_W_DEG / 2.0),
        top: by - i.deg(FIELD_H_DEG * 0.35),
        bottom: by + i.deg(FIELD_H_DEG * 0.65),
    };
    let mut fr = Frame { colour: Some(GREEN), ..Frame::default() };
    let w = &i.weapons;
    let mode = w.hud_mode;
    // A GPS bomb's coordinates: its cues replace the CCIP's (docs/weapons.md §13.3; the F-35's are not public, the
    // F-16's stand in).
    let gps = w.gps.is_some() && matches!(mode, 5 | 6);
    let o = &mut fr.outer;
    heading(o, f.top + 10.0, i.heading_deg, i.steerpoint.map(|s| s.bearing_deg));
    // Airspeed box (left) and its stack; altitude box (right), vertical velocity, radar altitude.
    let y0 = f.centre_y() + 8.0;
    let lx = f.left - 4.0;
    o.extend(box_poly(lx - 26.0, y0 - 6.0, lx, y0 + 5.0));
    o.push(line((lx - 30.0, y0), (lx - 26.0, y0)));
    o.push(text((lx - 2.0, y0 + 3.0), format!("{}", i.kcas.max(0.0).round() as i64), Align::Right));
    for (n, s) in [
        format!("GS {}", i.ground_kt.round() as i64),
        format!("M {:.2}", i.mach),
        format!("G {:.1}", i.g),
        format!("α {:.1}", i.aoa_deg),
        format!("{max_g:.1}"),
    ]
    .into_iter()
    .enumerate()
    {
        o.push(text((lx - 26.0, y0 + 16.0 + n as f64 * ROW), s, Align::Left));
    }
    let rx = f.right + 4.0;
    o.extend(box_poly(rx, y0 - 6.0, rx + 30.0, y0 + 5.0));
    o.push(text((rx + 28.0, y0 + 3.0), format!("{}", i.alt_ft.round() as i64), Align::Right));
    o.push(text((rx, y0 + 16.0), format!("{}", (i.vs_fpm / 5.0).round() as i64 * 5), Align::Left));
    if let Some(a) = i.agl_ft.filter(|a| *a < 50_000.0) {
        o.push(text((rx, y0 + 16.0 + ROW), format!("R{}", a.round() as i64), Align::Left));
    }
    // Lower left: master mode, weapon, ARM; lower right: steerpoint (number bearing / range) and time to go.
    let by = f.bottom - 22.0;
    let (master, weapon) = mode_block(w);
    o.push(text((lx - 26.0, by), master, Align::Left));
    if let Some(wt) = weapon {
        o.push(text((lx - 26.0, by + ROW), wt, Align::Left));
        o.push(text((lx - 20.0, by + 2.0 * ROW), "ARM", Align::Left));
    }
    if let Some(s) = i.steerpoint {
        o.push(text(
            (rx, by),
            format!("{:03} {:03}/{:.1}", s.number, (s.bearing_deg.round() as i64).rem_euclid(360), s.dist_m / NM),
            Align::Left,
        ));
        if let Some(t) = s.eta_s {
            let t = t.max(0.0).round() as i64;
            o.push(text((rx, by + ROW), format!("{:02}:{:02}:{:02}", t / 3600, (t / 60) % 60, t % 60), Align::Left));
        }
    }
    bank_scale(o, i, f.bottom - 4.0);
    if matches!(mode, 1 | 2)
        && let (Some(t), Some(z)) = (i.target, i.dlz)
    {
        let x = 0.5 * f.right;
        dlz_scale(o, x, y0, 18.0, t, z);
        o.push(text((x, y0 + 30.0), format!("{:.1}", t.range_m / NM), Align::Centre));
    }

    // The field: waterline, ladder, marker, targets, weapon symbols.
    let p = &mut fr.field;
    waterline(p, i.boresight, i.mr(14.0));
    if let Some(fpm) = i.fpm {
        let style = LadderStyle {
            gap: i.deg(1.4),
            len: i.deg(2.4),
            horizon_gap: i.deg(1.4),
            horizon_len: 2.0 * (f.right - f.left),
            tip: i.deg(0.3),
            inner_tips: true,
            bend: false,
            both_labels: false,
            signed: true,
            bottom_band: 14.0,
            top_band: 22.0,
            zenith: Zenith::None,
        };
        ladder(p, i, fpm, f, style);
        marker(p, fpm, i.mr(5.0), i.mr(9.0), i.mr(5.0));
        if matches!(mode, 5 | 6)
            && !gps
            && let Some(c) = w.pipper
        {
            p.push(line(fpm, c));
        }
    }
    // The steerpoint on the ground: a small square, in every master mode (the LM frame shows it in AA1); held at the
    // field's edge when outside it, as the target designator is (ours: the real edge behaviour is not public).
    if let Some(at) = i.steerpoint.and_then(|s| s.at) {
        let (q, _) = f.clamp_from(i.boresight, at);
        let h = i.mr(3.0);
        p.extend(box_poly(q.0 - h, q.1 - h, q.0 + h, q.1 + h));
    }
    if let Some(t) = i.target
        && let Some(at) = t.at
    {
        let (q, _) = f.clamp_from(i.boresight, at);
        let h = i.mr(12.0);
        p.push(Prim::Circle { c: q, r: h * 0.6 });
        x_over(p, q, h);
    }
    match mode {
        1 => {
            if let Some(s) = w.seeker {
                p.push(Prim::Circle { c: s, r: i.mr(6.0) });
            }
        }
        2 => {
            let c = add(i.boresight, (0.0, i.deg(4.0)));
            p.push(Prim::Circle { c, r: i.mr(40.0) * (w.circle / 5.0).clamp(0.4, 1.0) });
            if let Some(s) = w.steering {
                let (q, _) = f.clamp_from(c, s);
                p.push(Prim::Dot { c: q, r: i.mr(3.0) });
            }
        }
        3 => funnel(p, i, 3000.0),
        5 | 6 if gps => gps_cues(p, o, i, f, (0.5 * f.right, y0, 18.0), i.mr(4.0)),
        4..=6 => {
            if let Some(c) = w.pipper {
                pipper(p, c, i.mr(0.5).max(0.8), i.mr(6.0));
            }
        }
        _ => {}
    }
    // Not clipped to the cockpit's HUD glass: the helmet draws over the whole view.
    let mut field = std::mem::take(&mut fr.field);
    fr.outer.append(&mut field);
    fr
}

/// Looking off the nose (flight-test video; docs/real-hud.md "F-35I"): the aircraft-stabilised virtual HUD is left
/// behind and a reduced head-stabilised set shows around the helmet's centre — the head line-of-sight "+", a heading
/// tape for where the head points with the steering caret (the LM "HMD Looking Behind" frame), the airspeed and altitude as bare numbers, the steerpoint block, the target
/// designator and a GPS bomb's TD box; no ladder, marker, boxes or data stack.
fn off_boresight(i: &Input) -> Frame {
    let mut fr = Frame { colour: Some(GREEN), ..Frame::default() };
    let o = &mut fr.outer;
    let (w, h) = (i.deg(13.0), i.deg(8.0));
    let a = i.mr(10.0);
    o.push(line((-a, 0.0), (a, 0.0)));
    o.push(line((0.0, -a), (0.0, a)));
    heading(o, -h, i.head_heading_deg, i.steerpoint.map(|s| s.bearing_deg));
    o.push(text((-w, h * 0.6), format!("{}", i.kcas.max(0.0).round() as i64), Align::Left));
    o.push(text((w, h * 0.6), format!("{}", i.alt_ft.round() as i64), Align::Right));
    if let Some(s) = i.steerpoint {
        o.push(text(
            (w, h * 0.6 + 2.0 * ROW),
            format!("{:03} {:03}/{:.1}", s.number, (s.bearing_deg.round() as i64).rem_euclid(360), s.dist_m / NM),
            Align::Right,
        ));
        if let Some(t) = s.eta_s {
            let t = t.max(0.0).round() as i64;
            o.push(text(
                (w, h * 0.6 + 3.0 * ROW),
                format!("{:02}:{:02}:{:02}", t / 3600, (t / 60) % 60, t % 60),
                Align::Right,
            ));
        }
    }
    let field = Field { left: -w, right: w, top: -h, bottom: h };
    if let Some(t) = i.target
        && let Some(at) = t.at
    {
        let (q, _) = field.clamp_from((0.0, 0.0), at);
        let s = i.mr(12.0);
        o.push(Prim::Circle { c: q, r: s * 0.6 });
        x_over(o, q, s);
    }
    // A GPS bomb's aim: its TD box, held at the set's edge with an X over it when outside (as on the forward set).
    if matches!(i.weapons.hud_mode, 5 | 6)
        && let Some(at) = i.weapons.gps.and_then(|g| g.at)
    {
        let (q, limited) = field.clamp_from((0.0, 0.0), at);
        let h = i.mr(4.0);
        o.extend(box_poly(q.0 - h, q.1 - h, q.0 + h, q.1 + h));
        if limited {
            x_over(o, q, h);
        }
    }
    fr
}

/// The master mode and the selected weapon ("AA1" / "2 AIM-A"); NAV without one.
fn mode_block(w: &Weapons) -> (String, Option<String>) {
    match w.hud_mode {
        1 => ("AA1".into(), Some(format!("{} AIM-9", w.srm))),
        2 => ("AA1".into(), Some(format!("{} AIM-A", w.mrm))),
        3 => ("AA1".into(), Some("GUN".into())),
        4 => ("AG1".into(), Some("GUN".into())),
        5 | 6 if let Some(g) = w.gps => {
            ("AG1".into(), Some(format!("{} {}", w.selected, if g.pre { "PRE" } else { "VIS" })))
        }
        5..=8 => ("AG1".into(), Some(format!("{} AG", w.selected))),
        _ => ("NAV".into(), None),
    }
}

/// The heading tape on top: labels every 10° in tens, the boxed heading with its pointer and, under the tics, the
/// steering caret "^" at the steerpoint's bearing, held at the tape's end when the bearing is off the tape (ours: the
/// LM frame shows the caret just past the tape's last tic, the real limit is not public).
fn heading(p: &mut Vec<Prim>, y: f64, hdg: f64, bearing: Option<f64>) {
    let first = ((hdg - HDG_HALF / HDG_PX) / 5.0).ceil() as i64;
    let last = ((hdg + HDG_HALF / HDG_PX) / 5.0).floor() as i64;
    for n in first..=last {
        let t = n * 5;
        let x = (t as f64 - hdg) * HDG_PX;
        if x.abs() < 13.0 {
            continue;
        }
        let major = t.rem_euclid(10) == 0;
        p.push(line((x, y + 2.0), (x, y + if major { 5.0 } else { 3.5 })));
        if major {
            p.push(text((x, y), format!("{:02}", t.rem_euclid(360) / 10), Align::Centre));
        }
    }
    p.extend(box_poly(-11.0, y - 8.0, 11.0, y + 2.0));
    p.push(text((0.0, y), format!("{:03}", (hdg.round() as i64).rem_euclid(360)), Align::Centre));
    p.push(line((0.0, y + 2.0), (0.0, y + 6.0)));
    if let Some(b) = bearing {
        let x = (((b - hdg + 180.0).rem_euclid(360.0) - 180.0) * HDG_PX).clamp(-HDG_HALF, HDG_HALF);
        p.push(line((x - 2.5, y + 10.0), (x, y + 7.0)));
        p.push(line((x, y + 7.0), (x + 2.5, y + 10.0)));
    }
}

/// The bank scale at the bottom: tics every 10° to ±30° and at ±45° / ±60° on an arc, the pointer at the bank.
fn bank_scale(p: &mut Vec<Prim>, i: &Input, y: f64) {
    let r = 30.0;
    let c = (0.0, y - r);
    let at = |deg: f64, rr: f64| {
        let a = deg.to_radians();
        (c.0 - rr * a.sin(), c.1 + rr * a.cos())
    };
    for d in [-60.0, -45.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 45.0, 60.0] {
        p.push(line(at(d, r), at(d, r - if d == 0.0 { 4.0 } else { 2.0 })));
    }
    let b = i.roll_deg.clamp(-60.0, 60.0);
    p.push(Prim::Circle { c: at(b, r - 5.0), r: 1.2 });
    p.push(line(at(b, r - 6.0), at(b, r - 10.0)));
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    #[test]
    fn the_virtual_hud_as_the_lm_slides() {
        let mut i = input(Jet::F35);
        i.agl_ft = Some(15_060.0);
        i.vs_fpm = -1125.0;
        i.weapons = Weapons { hud_mode: 2, mrm: 2, circle: 4.0, ..Weapons::default() };
        let fr = frame(FIELD, &i, 1.9);
        let t = texts(&fr.outer);
        for want in [
            "352",
            "GS 380",
            "M 0.85",
            "G 2.3",
            "1.9",
            "10450",
            "-1125",
            "R15060",
            "AA1",
            "2 AIM-A",
            "ARM",
            "003 010/12.0",
            "00:05:23",
            "333",
        ] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        assert_eq!(fr.colour, Some(GREEN));
    }

    #[test]
    fn the_steering_caret_sits_at_the_bearing_and_holds_at_the_tape_end() {
        let caret_tip = |bearing: Option<f64>| {
            let mut p = Vec::new();
            heading(&mut p, 0.0, 333.0, bearing);
            match p.last() {
                Some(Prim::Line { a, .. }) if a.1 == 7.0 => Some(a.0),
                _ => None,
            }
        };
        for (bearing, want) in
            [(340.0, 14.0), (333.0, 0.0), (320.0, -26.0), (10.0, HDG_HALF), (150.0, HDG_HALF), (200.0, -HDG_HALF)]
        {
            assert_eq!(caret_tip(Some(bearing)), Some(want), "bearing {bearing}");
        }
        assert_eq!(caret_tip(None), None);
    }

    #[test]
    fn the_steerpoint_square_sits_on_its_ground_point_or_held_at_the_edge() {
        let mut i = input(Jet::F35);
        let h = i.mr(3.0);
        let top_side = |c: P| line((c.0 - h, c.1 - h), (c.0 + h, c.1 - h));
        // In the field: on the projection (the default input's (30, 20)), also in A-A as the LM frame shows.
        i.weapons.hud_mode = 2;
        assert!(frame(FIELD, &i, 1.9).outer.contains(&top_side((30.0, 20.0))));
        // Far right: held on the field's right edge, on the line from the boresight.
        i.steerpoint.as_mut().unwrap().at = Some((384.0, 0.0)); // twice the right edge (16° × 12 px)
        assert!(frame(FIELD, &i, 1.9).outer.contains(&top_side((i.deg(FIELD_W_DEG / 2.0), 0.0))));
        // Behind the view: no square (the caret alone shows the way).
        i.steerpoint.as_mut().unwrap().at = None;
        let n = frame(FIELD, &i, 1.9).outer.len();
        i.steerpoint.as_mut().unwrap().at = Some((30.0, 20.0));
        assert_eq!(frame(FIELD, &i, 1.9).outer.len(), n + 4);
    }

    #[test]
    fn off_boresight_reduces_to_the_head_set() {
        let i = Input { off_boresight: true, head_heading_deg: 60.0, fpm: Some((0.0, 0.0)), ..input(Jet::F35) };
        let fr = frame(FIELD, &i, 1.9);
        let t = texts(&fr.outer);
        assert!(t.contains(&"352") && t.contains(&"10450") && t.contains(&"060"), "{t:?}");
        assert!(!t.iter().any(|x| x.starts_with("GS") || x.starts_with("M ")), "no data stack: {t:?}");
        assert!(
            !fr.outer.iter().any(|p| matches!(p, Prim::Circle { r, .. } if (*r - i.mr(5.0)).abs() < 1e-9)),
            "no marker"
        );
    }
}
