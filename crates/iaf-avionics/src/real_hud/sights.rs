//! The jets without a HUD: their reticle is all there is (docs/real-hud.md).
//!
//! - The F-4E's AN/ASG-26 lead-computing optical sight (T.O. 1F-4E-1 / -34 via the Heatblur manual): red, a 2 mr pipper,
//!   a dashed 25 mr inner ring, a solid 50 mr outer ring, three roll tabs, and with a radar lock the range bar inside
//!   the outer ring from 6 o'clock counter-clockwise.
//! - The Mirage IIICJ's CSF gyro gunsight (the CSF 97K drawings of the RAAF Mirage IIIO manual): a 2.5 mr pipper in a
//!   fixed 50 mr ring of 14 diamonds moving over a fixed cross and an inverted V; lamp-lit orange.
//!
//! The reticle sits on the gun's lead-computing pipper in the A-A gun mode, on the gun cross (the radar boresight)
//! otherwise; in the bombing modes ours sets the depression automatically to the CCIP point (the real sights are set by
//! hand from bombing tables: a reconstruction, docs/deviations.md).

use super::*;
use std::f64::consts::{FRAC_PI_6, PI, TAU};

const RED: [f32; 3] = [1.0, 0.28, 0.2];
const ORANGE: [f32; 3] = [1.0, 0.62, 0.2];

/// The reticle's centre in the current mode.
fn reticle_at(i: &Input) -> P {
    let w = &i.weapons;
    match w.hud_mode {
        3 => w.lcos.unwrap_or(i.gun_cross),
        4..=6 => w.pipper.unwrap_or(i.gun_cross),
        _ => i.gun_cross,
    }
}

pub(super) fn lcoss(i: &Input) -> Frame {
    let mut fr = Frame { colour: Some(RED), sight: true, ..Frame::default() };
    let p = &mut fr.field;
    let c = reticle_at(i);
    let (ro, ri) = (i.mr(25.0), i.mr(12.5));
    p.push(Prim::Dot { c, r: i.mr(1.0).max(0.8) });
    for k in 0..12 {
        p.push(Prim::Arc { c, r: ri, from: k as f64 * TAU / 12.0 + 0.1, sweep: TAU / 12.0 - 0.2 });
    }
    p.push(Prim::Circle { c, r: ro });
    // The roll tabs at 9, 12 and 3 o'clock with wings level, turning with the bank.
    for base in [-PI / 2.0, 0.0, PI / 2.0] {
        let a = base - i.roll_deg.to_radians();
        let (s, co) = a.sin_cos();
        p.push(line((c.0 + ro * s, c.1 - ro * co), (c.0 + (ro + i.mr(5.0)) * s, c.1 - (ro + i.mr(5.0)) * co)));
    }
    // The range bar with a lock: guns 1,000 ft at 6 o'clock + 1,000 ft per clock hour (to 6,667 ft), else 3,000 ft +
    // 3,000 ft per hour (to 20,000 ft).
    if let Some(t) = i.target {
        let (start, per_hour, max) = if i.weapons.hud_mode == 3 { (1000.0, 1000.0, 6667.0) } else { (3000.0, 3000.0, 20_000.0) };
        let ft = (t.range_m / FT).clamp(start, max);
        let ccw = (ft - start) / per_hour * FRAC_PI_6;
        p.push(Prim::Arc { c, r: ro - i.mr(2.0), from: PI - ccw, sweep: ccw.max(0.02) });
    }
    fr
}

pub(super) fn csf(i: &Input) -> Frame {
    let mut fr = Frame { colour: Some(ORANGE), sight: true, ..Frame::default() };
    let p = &mut fr.field;
    // The fixed images: the cross 50 mr below the gun idle (40 mr wide, a 10 mr stub up, a short separate dash down)
    // and the inverted V 40 mr above it.
    let (x, y) = add(i.gun_cross, (0.0, i.mr(50.0)));
    let (h, s) = (i.mr(20.0), i.mr(10.0));
    p.push(line((x - h, y), (x + h, y)));
    p.push(line((x, y - s), (x, y)));
    p.push(line((x, y + s * 0.4), (x, y + s)));
    let (vx, vy) = (x, y - i.mr(40.0));
    p.push(line((vx - i.mr(5.0), vy + i.mr(4.0)), (vx, vy)));
    p.push(line((vx, vy), (vx + i.mr(5.0), vy + i.mr(4.0))));
    // The moving images: the pipper and the 14 diamonds on the 50 mr ring.
    let c = reticle_at(i);
    p.push(Prim::Dot { c, r: i.mr(1.25).max(0.9) });
    let r = i.mr(25.0);
    for k in 0..14 {
        let a = k as f64 * TAU / 14.0;
        diamond(p, (c.0 + r * a.sin(), c.1 - r * a.cos()), i.mr(1.5).max(1.2));
    }
    fr
}

#[cfg(test)]
mod tests {
    use super::super::tests::input;
    use super::*;

    #[test]
    fn the_phantom_range_bar_unwinds_from_6_oclock() {
        let mut i = input(Jet::Phantom);
        i.weapons.hud_mode = 3;
        i.target = Some(Target { range_m: 4000.0 * FT, closure: 0.0, at: None });
        let fr = lcoss(&i);
        assert!(fr.sight && fr.colour == Some(RED) && fr.outer.is_empty());
        let arc = fr.field.iter().rev().find_map(|p| if let Prim::Arc { from, sweep, .. } = p { Some((*from, *sweep)) } else { None });
        let (from, sweep) = arc.unwrap();
        assert!((sweep - PI / 2.0).abs() < 1e-9 && (from - PI / 2.0).abs() < 1e-9, "4,000 ft at 3 o'clock: {from} {sweep}");
    }

    #[test]
    fn the_mirage_sight_has_fourteen_diamonds() {
        let fr = csf(&input(Jet::Mirage));
        let lines = fr.field.iter().filter(|p| matches!(p, Prim::Line { .. })).count();
        assert_eq!(lines, 5 + 14 * 4);
        assert_eq!(fr.colour, Some(ORANGE));
    }
}
