//! The F-16C/D HUD (T.O. GR1F-16CJ-34-1-1 figs. 1-110 / 1-111 / 1-115 and the A-A / A-G chapters; docs/real-hud.md
//! "F-16C/D"). Drawn for the F-16 only: the F-35, Lavi, Kurnass 2000 and Kfir have their own layouts (mod.rs `frame`).

use super::*;
use crate::delivery::Submode;

/// Scales: airspeed 0.6 px per kt (10 kt ticks, labels every 50 kt in tens), altitude 0.06 px per ft (100 ft ticks,
/// labels every 500 ft in hundreds with a thousands comma), heading 2 px per degree (5° ticks, labels every 10° in
/// tens); their half heights / widths.
const KT_PX: f64 = 0.6;
const FT_PX: f64 = 0.06;
const HDG_PX: f64 = 2.0;
const TAPE_HALF: f64 = 36.0;
const HDG_HALF: f64 = 34.0;
/// The DLZ scale: half height, 10 px inboard of the altitude scale, which moves 12 px outward while it shows.
const DLZ_HALF: f64 = 24.0;
const DLZ_IN: f64 = 10.0;
const ALT_OUT: f64 = 12.0;
/// The vertical velocity scale this far inboard of the altitude scale.
const VVI_IN: f64 = 20.0;
/// Data rows 9 px apart.
const ROW: f64 = 9.0;
/// The scales and data blocks this far in from the field's sides (`Field::inset`), the right block in A-A included.
const INSET: f64 = 14.0;

/// The field a limited steerpoint diamond (half size `h`) is held in: inside the scales' 5 px major ticks, clear of the
/// scales' labels outside them.
fn steer_limit(sc: Field, h: f64) -> Field {
    sc.inset(5.0 + h)
}

/// `fuel_reset`: WARN RESET has put the FUEL cue out (`RealHud::warn_reset`).
pub(super) fn frame(f: Field, i: &Input, max_g: f64, fuel_reset: bool) -> Frame {
    // DRIFT C/O: the flight path marker, and the ladder and cues drawn on it, centred laterally on the boresight
    // (modern-iaf/docs/cockpit.md §5.8; inferred from the switch's name and FlightGear's F-16, which sets the
    // marker's x to the centre).
    let centred;
    let i = match i.fpm {
        Some(p) if i.panel.drift_co => {
            centred = Input { fpm: Some((i.boresight.0, p.1)), ..i.clone() };
            &centred
        }
        _ => i,
    };
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let o = &mut fr.outer;
    let sc = f.inset(INSET);
    let tape_y = f.centre_y() - 6.0;
    let dlz = matches!(mode, 1 | 2).then_some(()).and(i.target.zip(i.dlz));
    // A GPS bomb's coordinates: its cues replace the CCIP's (docs/weapons.md §13.3).
    let gps = w.gps.is_some() && matches!(mode, 5 | 6);
    // Modern IAF's release submodes (modern-iaf/docs/weapons.md §9): CCRP, DTOS, LADD and MAN replace the CCIP cues.
    let dv = w.delivery.filter(|_| matches!(mode, 5 | 6) && !gps);
    let computed = dv.is_some_and(|d| d.submode != Submode::Ccip);
    let pn = &i.panel;
    let scales = pn.scales != Scales::Off;
    // Scales. The airspeed by the VELOCITY switch, CAS with the gear down or in DGFT (window 1's C / T / G).
    let (kt, letter) = match pn.velocity {
        _ if i.gear_down || pn.over == 1 => (i.kcas, "C"),
        Velocity::Cas => (i.kcas, "C"),
        Velocity::Tas => (i.tas_ms * MS_TO_KT, "T"),
        Velocity::Gnd => (i.ground_kt, "G"),
    };
    // The TFR's speed band: outside it the scale flashes (research/pods.md §3.3).
    let flash = pn.tf.as_ref().is_some_and(|t| t.speed_out) && !flash_on(i.time_s);
    airspeed(o, sc.left, tape_y, kt, letter, scales && !flash);
    o.push(text((sc.left + 3.0, tape_y - TAPE_HALF - 4.0), format!("{:.1}", i.g), Align::Left));
    // The HUD as the SOI: an asterisk at the upper left (the dash-34 as simulator forums quote it, docs/real-hud.md;
    // inferred place: left of the g readout).
    if pn.soi {
        o.push(text((sc.left - 8.0, tape_y - TAPE_HALF - 4.0), "*", Align::Left));
    }
    let alt_x = sc.right + if dlz.is_some() || gps { ALT_OUT } else { 0.0 };
    // The altitude by the ALT switch: RADAR the radar altitude (AR), AUTO the radar altitude's thermometer below
    // 1,200 ft, BARO (and a radar altitude out of reach) the barometric one.
    let agl = i.agl_ft.filter(|a| *a < 50_000.0);
    // `ar`: `AR` beside the index.
    let ar = match (pn.alt, agl) {
        (AltSwitch::Auto, Some(a)) if a < 1200.0 => {
            thermometer(o, alt_x, tape_y, a);
            true
        }
        (AltSwitch::Radar, Some(a)) => {
            altitude(o, alt_x, tape_y, a, scales, "AR");
            true
        }
        _ => {
            altitude(o, alt_x, tape_y, i.alt_ft, scales, "");
            false
        }
    };
    if let Some((t, z)) = dlz {
        dlz_scale(o, sc.right - DLZ_IN, tape_y, DLZ_HALF, t, z);
    } else if pn.scales == Scales::VvVah && !gps {
        vvi(o, alt_x - VVI_IN, tape_y, i.vs_fpm, ar);
    }
    // The heading scale: the lower position (below the scales) in NAV, A-A and strafe; the upper one in the A-G modes
    // and gear down.
    let hdg_y = if i.gear_down || matches!(mode, 5..=7) { f.top + 10.0 } else { tape_y + TAPE_HALF + 6.0 };
    // The left column (ARM, Mach, max g, the mode / weapon) ends at `lx`. The right column (radar altitude, slant
    // range, time, steerpoint) starts at `rx`. `right_under` (Modern IAF's F-16s): under the altitude scale, its rows
    // starting four character cells inboard of the scale's ticks (dash-34 figs. 1-110 / 1-115: the windows start that
    // far inboard and the longest ends at the scale's outer edge; docs/real-hud.md "Data windows"). Else from the
    // scale outward (the original game's Real HUD).
    let (lx, ly) = (sc.left + 4.0, tape_y + TAPE_HALF + 12.0);
    let rx = if i.right_under { alt_x - 5.0 - 4.0 * CHAR_W } else { alt_x + 2.0 };
    // EEGS has neither the heading scale nor the roll indicator (fig. 1-257); DED DATA's lines replace the roll
    // indicator (the dash-34 as a simulator forum quotes it, docs/real-hud.md "F-16C/D").
    if mode != 3 && scales {
        heading(o, hdg_y, i.heading_deg, i.steerpoint.map(|s| s.bearing_deg));
        if pn.ded.is_empty() {
            // The gap from the column's place without the DLZ's or GPS cues' shift: the arc keeps one size.
            roll_indicator(o, i, f.bottom, (rx - (alt_x - sc.right)).min(-lx));
        }
    }
    let mut row = 0.0;
    // ALIGN while the INS aligns, flashing once it can navigate (inferred place: the left column's top).
    if let Some(ready) = pn.align
        && (!ready || flash_on(i.time_s))
    {
        o.push(text((lx, ly - ROW), "ALIGN", Align::Right));
    }
    if pn.sim || mode > 0 {
        o.push(text((lx, ly), if pn.sim { "SIM" } else { "ARM" }, Align::Right));
        row += ROW;
    }
    o.push(text((lx, ly + row), format!("{:.2}", i.mach), Align::Right));
    o.push(text((lx, ly + row + ROW), format!("{max_g:.1}"), Align::Right));
    let mode_s = match pn.over {
        1 => "DGFT".to_string(),
        2 => "MSL".to_string(),
        _ => mode_text(w),
    };
    o.push(text((lx, ly + row + 2.0 * ROW), mode_s, Align::Right));
    // The right column.
    let ry = tape_y + TAPE_HALF + 12.0;
    let mut rows = Vec::new();
    if let Some(a) = i.agl_ft.filter(|a| *a < 50_000.0) {
        rows.push(format!("R {}", thousands(a)));
        // The ALOW setting under it (fig. 1-115 `AL 200`), flashing below it (p. 1-316; blank in the dark half).
        let alow = pn.alow_ft.unwrap_or(crate::gaaf::ALOW_FT);
        let lit = !crate::gaaf::alow_hud(a, i.vs_fpm, i.kcas, alow) || flash_on(i.time_s);
        rows.push(if lit { format!("AL {}", alow.round() as i64) } else { String::new() });
    }
    // The slant range: the FCR's target, else its AGR ranging (ours: the same F, inferred), else the steerpoint's.
    match (i.target, i.agr_m, i.steerpoint) {
        (Some(t), _, _) => rows.push(slant('F', t.range_m)),
        (None, Some(m), _) => rows.push(slant('F', m)),
        (None, None, Some(s)) => rows.push(slant('B', s.dist_m)),
        _ => {}
    }
    if mode == 3
        && let Some(t) = i.target
    {
        rows.push(format!("{}", (t.closure * MS_TO_KT).round() as i64));
    } else if let Some(m) = w.msl_time {
        // An air-to-air missile in flight: its time to active / to impact (the DCS F-16C guide's post-launch time,
        // there under the DLZ; ours in the timer's row, inferred, as the GPS bomb's).
        rows.push(m.text());
    } else if let Some(t) = w.tti {
        // A released GPS bomb's time to impact (ours, inferred: the timer's row, docs/real-hud.md "GPS bombs").
        rows.push(tti_text(t));
    } else if let Some(t) = dv.filter(|d| d.submode.automatic()).and_then(|d| d.pull_up.or(d.ttr)) {
        // A computed release: the time to the loft's pull-up, then to the release (MLU figs. 6-11..6-16).
        let t = t.clamp(0.0, 5999.0).ceil() as i64;
        rows.push(format!("{:02}:{:02}", t / 60, t % 60));
    } else if let Some(d) = w.delay.filter(|d| d.designated && matches!(mode, 5 | 6)) {
        // Designated delayed CCIP: the time to release (fig. 1-283 "TIME DELAY") in place of the steerpoint's.
        let t = (d.ttg - RELEASE_TTG).clamp(0.0, 5999.0).ceil() as i64;
        rows.push(format!("{:02}:{:02}", t / 60, t % 60));
    } else if let Some(t) = i.steerpoint.and_then(|s| s.eta_s) {
        let t = t.max(0.0).round() as i64;
        rows.push(format!("{:02}:{:02}", (t / 60).min(99), t % 60));
    }
    if let Some(s) = i.steerpoint {
        rows.push(format!("{:03}>{:02}", ((s.dist_m / NM).round() as i64).min(999), s.number));
    }
    for (n, r) in rows.into_iter().enumerate().filter(|(_, r)| !r.is_empty()) {
        o.push(text((rx, ry + n as f64 * ROW), r, Align::Left));
    }
    // The centre window: SHOOT (MLU) before FUEL.
    // FUEL flashes (dash-34 fig. 1-115 window 6) until WARN RESET (dash-1 "FUEL" mnemonic: "may be manually reset by
    // placing the WARN RESET switch to WARN RESET").
    if w.shoot || (i.fuel_lbs < i.bingo_lbs && !fuel_reset && flash_on(i.time_s)) {
        let cue = if w.shoot { "SHOOT" } else { "FUEL" };
        o.push(text((0.0, i.gun_cross.1 + i.mr(70.0)), cue, Align::Centre));
    }
    // DED DATA: the DED's lines low in the HUD (dash-34 "HUD remote control panel"): one character per cell, so the
    // DED's columns line up, in the gap between the left and the right column, from the right column's second row
    // down (inferred place: under the heading scale's lower position, where the roll indicator was).
    ded_block(o, &pn.ded, (lx, rx), ry + ROW);

    // The field: boresight cross, ladder, marker, AoA bracket, steerpoint, target, weapon symbols.
    let p = &mut fr.field;
    let delayed = w.delay.and_then(|d| d.target.map(|t| (d, t))).filter(|_| !gps && !computed);
    boresight_cross(p, i);
    // The FP MARKER switch: ATT/FPM the ladder and the marker, FPM the marker alone, OFF neither.
    let fpm_at = i.fpm.filter(|_| pn.fpm != FpmSwitch::Off);
    if let Some(fpm) = fpm_at {
        let style = LadderStyle {
            gap: i.deg(1.4),
            len: i.deg(2.6),
            horizon_len: i.deg(4.2),
            tip: i.deg(0.35),
            inner_tips: false,
            bend: true,
            both_labels: true,
            signed: false,
            bottom_band: f.bottom - hdg_y + 12.0,
            top_band: 0.0,
            zenith: Zenith::StarEarth,
            horizon_tabs: false,
        };
        if pn.fpm == FpmSwitch::AttFpm {
            ladder(p, i, fpm, f, style);
        }
        if pn.flir_shift {
            dashed_marker(p, fpm, i.mr(5.0), i.mr(10.0), i.mr(5.0));
        } else {
            marker(p, fpm, i.mr(5.0), i.mr(10.0), i.mr(5.0));
        }
        if let Some(tf) = &pn.tf {
            tf_cues(p, i, f, fpm, tf);
        }
        // LOW beside the marker: a bomb released now hits before its fuze arms (dash-34 p. 1-173; ours right of it).
        if dv.is_some_and(|d| d.low) {
            p.push(text((fpm.0 + i.mr(14.0), fpm.1 + 3.0), "LOW", Align::Left));
        }
        if i.gear_down {
            aoa_bracket(p, i, fpm);
        }
        if matches!(mode, 5 | 6)
            && delayed.is_none()
            && !gps
            && !computed
            && let Some(c) = w.pipper
        {
            p.push(line(fpm, c));
        }
    }
    if let Some(s) = i.steerpoint.filter(|_| !matches!(mode, 1..=3))
        && let Some(at) = s.at
    {
        // Held inside the scales' ticks, so it and its X stay off their labels (on the Barak's narrower glass the field's
        // edge put them over the altitude scale's "7,0", 2026-11-13).
        let (q, limited) = steer_limit(sc, i.mr(3.0)).clamp_from(i.boresight, at);
        diamond(p, q, i.mr(3.0));
        if limited {
            x_over(p, q, i.mr(3.0));
        }
    }
    if let Some(t) = i.target
        && let Some(at) = t.at
    {
        target_box(p, i, f, at, mode == 3, t);
    }
    acm_cue(p, i);
    match mode {
        1 => {
            let c = add(i.gun_cross, (0.0, i.deg(3.0)));
            p.push(Prim::Circle { c, r: i.mr(32.5) });
            if let Some(a) = i.target.and_then(|t| t.aspect) {
                aspect_triangle(p, c, i.mr(32.5), a, i.mr(5.0));
            }
            // The missile diamond: small while caged or not tracking, large uncaged and tracking (the DCS F-16C guide;
            // ours 8 mr, inferred).
            if let Some(s) = w.seeker {
                diamond(p, s, i.mr(if w.srm_track { 8.0 } else { 5.0 }));
            }
        }
        2 => {
            let (c, r) = super::mrm_circle(i).unwrap_or_default();
            p.push(Prim::Circle { c, r });
            if let Some(a) = i.target.and_then(|t| t.aspect) {
                aspect_triangle(p, c, r, a, i.mr(5.0));
            }
            if let Some(s) = w.steering {
                let (q, limited) = f.clamp_from(c, s);
                p.push(Prim::Circle { c: q, r: i.mr(4.0) });
                if limited {
                    x_over(p, q, i.mr(4.0));
                }
            }
        }
        3 => eegs(p, i, f),
        5 | 6 if gps => gps_cues(p, o, i, f, (sc.right - DLZ_IN, tape_y, DLZ_HALF), i.mr(4.0), true),
        5 | 6 if let Some(d) = dv.filter(|_| computed) => delivery_cues(p, i, f, d),
        5 | 6 if let Some((d, t)) = delayed => delayed_ccip(p, i, f, d, t),
        4..=6 => {
            if let Some(c) = w.pipper {
                pipper(p, c, i.mr(0.5).max(0.8), i.mr(6.0));
            }
        }
        _ => {}
    }
    // DGFT: the gun's EEGS funnel with the SRM's symbols (the trigger fires the gun, the pickle the missile).
    if mode == 1 && pn.over == 1 {
        eegs(p, i, f);
    }
    // DEPR RET at STBY: the standby reticle, a 50 mr ring with its 2 mr pipper, depressed from the gun cross by the
    // RET DEPR wheel (dash-34 "Standby reticle"; ours: the ring's size as the CCIP reticle's, inferred).
    if let Some(d) = pn.depr_mr {
        let c = add(i.gun_cross, (0.0, i.mr(d)));
        p.push(Prim::Circle { c, r: i.mr(25.0) });
        p.push(Prim::Dot { c, r: i.mr(1.0).max(0.8) });
    }
    ground_cues(p, i, f, dlz.is_some_and(|(t, z)| t.range_m < z.min));
    fr
}

/// The TFR's cues (modern-iaf/docs/weapons.md §7.4; research/pods.md §3.3, secondary; sizes and places ours): the TF
/// box, which the pilot flies the flight path marker into, held inside the field; LIMIT left of it and NO TER right of
/// it; the fly-up's legend flashing under the field's centre.
fn tf_cues(p: &mut Vec<Prim>, i: &Input, f: Field, fpm: P, tf: &TfCue) {
    let h = i.mr(7.0);
    let (c, _) = f.clamp_from(fpm, add(fpm, (0.0, -i.deg(tf.above_deg))));
    p.push(line((c.0 - h, c.1 - h), (c.0 + h, c.1 - h)));
    p.push(line((c.0 + h, c.1 - h), (c.0 + h, c.1 + h)));
    p.push(line((c.0 + h, c.1 + h), (c.0 - h, c.1 + h)));
    p.push(line((c.0 - h, c.1 + h), (c.0 - h, c.1 - h)));
    if tf.limit {
        p.push(text((c.0 - h - 4.0, c.1 + 3.0), "LIMIT", Align::Right));
    }
    if tf.no_ter {
        p.push(text((c.0 + h + 4.0, c.1 + 3.0), "NO TER", Align::Left));
    }
    if let Some(s) = tf.fly_up
        && flash_on(i.time_s)
    {
        p.push(text((0.5 * (f.left + f.right), f.centre_y() + i.mr(40.0)), s, Align::Centre));
    }
}

/// The break X (p. 1-173, fig. 1-212): flashing at the GAAF advisory (every master mode); steady in the A-A missile
/// modes inside Rmin (`rmin`). Ours: half its size = 0.3 of the field, on the field's centre, flashing at 2 Hz. With
/// the pull-up anticipation cue in the A-G modes. The F-35's helmet takes the same rule (`f35`; inferred: its
/// Auto-GCAS lineage, modern-iaf/docs/avionics-plan.md H8).
pub(super) fn ground_cues(p: &mut Vec<Prim>, i: &Input, f: Field, rmin: bool) {
    let mode = i.weapons.hud_mode;
    let gaaf = i.agl_ft.is_some_and(|h| {
        crate::gaaf::advisory(h, i.kcas, i.tas_ms, i.vs_fpm, i.roll_deg, i.gear_down, matches!(mode, 4..=7))
    });
    if rmin || (gaaf && flash_on(i.time_s)) {
        x_over(p, (0.5 * (f.left + f.right), f.centre_y()), 0.3 * (f.right - f.left).min(f.bottom - f.top));
    }
    if matches!(mode, 4..=7)
        && let Some(fpm) = i.fpm
        && let Some(s) = pullup_cue_s(i)
    {
        pullup_cue(p, i, fpm, s);
    }
}

/// The pull-up anticipation cue's time to the GAAF advisory (s; p. 1-173): None when GAAF is off or the advisory is
/// further than the cue's travel (ours: CUE_MAX_S, the solution cue's).
fn pullup_cue_s(i: &Input) -> Option<f64> {
    let agl = i.agl_ft.filter(|h| *h > 50.0)?;
    let gaaf = crate::gaaf::advisory_height(i.kcas, i.tas_ms, i.vs_fpm, i.roll_deg, i.gear_down, true);
    // Ours, Modern IAF's F-16s: also the fuze's arming height, whichever comes first (the cue rises for the release's
    // minimum height too, p. 1-173).
    let arm = i.weapons.delivery.and_then(|d| d.min_release_ft).filter(|_| i.vs_fpm < 0.0);
    let h = match (gaaf, arm) {
        (Some(a), Some(b)) => a.max(b),
        (a, b) => a.or(b)?,
    };
    let s = (agl - h).max(0.0) / (-i.vs_fpm / 60.0);
    (s <= CUE_MAX_S).then_some(s)
}

/// The pull-up anticipation cue (p. 1-173, fig. 1-212): a U under the flight path marker in the A-G modes, rising as
/// the jet dives until it cups the marker at the GAAF advisory, with the break X. Ours (inferred; the manual gives no
/// scale): CUE_MR_PER_S below the marker per second to the advisory (the solution cue's scale), 24 mr wide with 3 mr
/// ends (the figure: about the marker's span), level on the HUD.
fn pullup_cue(p: &mut Vec<Prim>, i: &Input, (x, y): P, s: f64) {
    let (w, h) = (i.mr(12.0), i.mr(3.0));
    let b = y + i.mr(5.0) + i.mr(CUE_MR_PER_S) * s;
    p.extend([line((x - w, b - h), (x - w, b)), line((x - w, b), (x + w, b)), line((x + w, b), (x + w, b - h))]);
}

/// The flashing cues' lit half (ours: 2 Hz).
fn flash_on(t: f64) -> bool {
    (t * 4.0).floor() as i64 % 2 == 0
}

/// The game releases the first bomb of a delayed CCIP at this time to go (s; docs/weapons.md §9.2 step 5).
const RELEASE_TTG: f64 = 0.9;
/// Ours: the solution cue's height above the marker per second to release and its longest time (inferred: the
/// dash-34 gives no scale; the original's cue moves 100 px over 10 s, which leaves our glass).
const CUE_MR_PER_S: f64 = 10.0;
const CUE_MAX_S: f64 = 10.0;

/// The delayed CCIP (dash-34 pp. 1-429..1-430, fig. 1-283; on the HUD the CCIP pipper is a 1 mr dot in a 12 mr circle
/// with the bomb fall line from the marker). With the impact point below the HUD (the game's delayed CCIP,
/// docs/weapons.md §9.4):
/// - before designation: the pipper on the target under the HUD-edge pipper (the real one is held about 14° below the
///   boresight cross; ours where the game holds it, kept on the glass), the fall line to it and the time delay cue
///   across the line, running from the marker to the pipper as the time to go falls from 10 to 0 s (the game's cue;
///   the real cue's motion is not stated);
/// - Space held (designated): the steering line through the target along the rolled vertical (its offset from the
///   marker is the azimuth error) and the solution cue on it, left of the line, coming down onto the marker's level at
///   the release (time to go 0.9 s), held at the glass's edge while further out.
fn delayed_ccip(p: &mut Vec<Prim>, i: &Input, f: Field, d: Delay, t: P) {
    let from = i.fpm.unwrap_or(i.gun_cross);
    if d.designated {
        let down = steering_line(p, i, f, t);
        if let Some(fpm) = i.fpm {
            let along = (fpm.0 - t.0) * down.0 + (fpm.1 - t.1) * down.1;
            let l = along - i.mr(CUE_MR_PER_S) * (d.ttg - RELEASE_TTG).clamp(0.0, CUE_MAX_S);
            let level = (t.0 + down.0 * along, t.1 + down.1 * along);
            // Pegged at the glass's edge while further out (as the CCRP's cue in its uppermost position, p. 1-428).
            let (q, _) = f.clamp_from(level, (t.0 + down.0 * l, t.1 + down.1 * l));
            let left = (-down.1, down.0);
            p.push(line(q, (q.0 + left.0 * i.mr(10.0), q.1 + left.1 * i.mr(10.0))));
        }
        return;
    }
    let (c, _) = f.clamp_from(from, t);
    let (dx, dy) = (c.0 - from.0, c.1 - from.1);
    let len = dx.hypot(dy);
    let ring = i.mr(6.0);
    if len > ring {
        let u = (dx / len, dy / len);
        p.push(line(from, (c.0 - u.0 * ring, c.1 - u.1 * ring)));
        let n = len * ((10.0 - d.ttg) / 10.0).clamp(0.0, 1.0);
        let (m, h) = ((from.0 + u.0 * n, from.1 + u.1 * n), i.mr(6.0));
        p.push(line((m.0 - u.1 * h, m.1 + u.0 * h), (m.0 + u.1 * h, m.1 - u.0 * h)));
    }
    pipper(p, c, i.mr(0.5).max(0.8), ring);
}

/// The azimuth steering line through the target `t` along the rolled vertical (its offset from the marker is the
/// azimuth error) across the glass; its unit vector down.
fn steering_line(p: &mut Vec<Prim>, i: &Input, f: Field, t: P) -> P {
    let roll = i.roll_deg.to_radians();
    let down = (roll.sin(), roll.cos());
    let long = (f.right - f.left).hypot(f.bottom - f.top);
    p.push(line((t.0 - down.0 * long, t.1 - down.1 * long), (t.0 + down.0 * long, t.1 + down.1 * long)));
    down
}

/// The release submodes' cues (MLU pp. 172–181, figs. 6-8..6-16 and 6-33; ours where the guide gives no scale: the
/// delayed CCIP's 10 mr per second, a 10 mr TD box as the dash-34's DTOS box):
/// - CCRP and LADD: the TD box on the target and the azimuth steering line through it; over the last 10 s before the
///   loft's pull-up the pull-up anticipation cue above the marker and the horizontal bar below it, meeting at the
///   marker at the pull-up; then the solution cue down the steering line to the marker at the release (the delayed
///   CCIP's cue); LADD's vertical steering bar at the 45° climb;
/// - DTOS: before designation the TD box on the flight path marker; designated, CCRP's box, line and solution cue;
/// - MAN: no computed symbol; at DEPR RET PRI the primary reticle depressed from the gun cross.
fn delivery_cues(p: &mut Vec<Prim>, i: &Input, f: Field, d: DeliveryCue) {
    let box_h = i.mr(5.0);
    if d.submode == Submode::Man {
        if let Some(mr) = d.man_mr {
            primary_reticle(p, i, mr);
        }
        return;
    }
    if d.submode == Submode::Dtos && !d.designated {
        if let Some(fpm) = i.fpm {
            td_box(p, fpm, box_h);
        }
        return;
    }
    let Some(t) = d.td else { return };
    // The radar's designated point has its own TD box (`target_box`).
    let (q, outside) = f.clamp_from(i.boresight, t);
    if !outside && i.target.is_none() {
        td_box(p, q, box_h);
    }
    if let Some(s) = d.pull_up {
        steering_line(p, i, f, t);
        if let Some(fpm) = i.fpm.filter(|_| s <= CUE_MAX_S) {
            let (w, off) = (i.mr(6.0), i.mr(CUE_MR_PER_S) * s);
            let (up, down) = (fpm.1 - i.mr(5.0) - off, fpm.1 + i.mr(5.0) + off);
            p.push(line((fpm.0 - w, up), (fpm.0 + w, up)));
            p.push(line((fpm.0 - 2.0 * w, down), (fpm.0 + 2.0 * w, down)));
        }
        return;
    }
    if d.submode == Submode::Ladd
        && let Some(fpm) = i.fpm
    {
        let climb = (i.vs_fpm * FT / 60.0 / i.tas_ms.max(1.0)).clamp(-1.0, 1.0).asin().to_degrees();
        if climb < crate::delivery::LOFT_DEG {
            let y = (fpm.1 - (crate::delivery::LOFT_DEG - climb) * i.px_per_deg).max(f.top);
            p.push(line((fpm.0 - i.mr(12.0), y), (fpm.0 + i.mr(12.0), y)));
        }
    }
    match d.ttr {
        Some(ttr) => delayed_ccip(p, i, f, Delay { ttg: ttr + RELEASE_TTG, target: Some(t), designated: true }, t),
        None => {
            steering_line(p, i, f, t);
        }
    }
}

/// A TD box of half size `h` about `c`.
fn td_box(p: &mut Vec<Prim>, c: P, h: f64) {
    p.extend(box_poly(c.0 - h, c.1 - h, c.0 + h, c.1 + h));
}

/// MAN's primary reticle (MLU fig. 6-33): a 2 mr pipper, a dashed 50 mr circle inside a 100 mr one, depressed `mr`
/// below the gun cross, the depression beside it ("displayed in the HUD", p. 191; ours right of the ring).
fn primary_reticle(p: &mut Vec<Prim>, i: &Input, mr: f64) {
    let c = add(i.gun_cross, (0.0, i.mr(mr)));
    p.push(Prim::Circle { c, r: i.mr(50.0) });
    let seg = std::f64::consts::TAU / 16.0;
    for k in 0..16 {
        p.push(Prim::Arc { c, r: i.mr(25.0), from: f64::from(k) * seg, sweep: 0.5 * seg });
    }
    p.push(Prim::Dot { c, r: i.mr(1.0).max(0.8) });
    p.push(text((c.0 + i.mr(52.0), c.1 + 3.0), format!("{mr:.0}"), Align::Left));
}

/// EEGS (dash-34 pp. 1-387..1-390, fig. 1-257). Without a lock, level 2: the funnel (600-3,000 ft) and the MRGS lines
/// at the bottom of the HUD sweeping toward the centre. With a radar track (range, velocity, acceleration: level 5):
/// the lengthened funnel, the T-symbol at the target's range — a long horizontal bar across the funnel (at most
/// 100 mr), the 1 g pipper "+" between its halves and the 9 g pipper tic in the funnel's centre — and the 4 mr
/// pipper on the lead-computed solution; the TD circle with its range arc and the maximum-effective-range dot is drawn
/// by `target_box`.
fn eegs(p: &mut Vec<Prim>, i: &Input, f: Field) {
    let Some(t) = i.target else {
        funnel(p, i, 3000.0);
        mrgs(p, i, f);
        return;
    };
    funnel(p, i, 6000.0);
    let r_ft = (t.range_m / FT).clamp(600.0, 6000.0);
    let (c, half) = funnel_at(i, r_ft, i.g);
    let bar = i.mr(50.0);
    p.push(line((c.0 - bar, c.1), (c.0 - half - 1.0, c.1)));
    p.push(line((c.0 + half + 1.0, c.1), (c.0 + bar, c.1)));
    let a = i.mr(2.0);
    p.push(line((c.0 - a, c.1), (c.0 + a, c.1)));
    p.push(line((c.0, c.1 - a), (c.0, c.1 + a)));
    let (c9, _) = funnel_at(i, r_ft, 9.0);
    p.push(line((c9.0 - a, c9.1), (c9.0 + a, c9.1)));
    if let Some(l) = i.weapons.lcos {
        p.push(Prim::Circle { c: l, r: i.mr(2.0) });
    }
}

/// The multiple reference gunsight lines: short lines near the HUD's bottom drawn for a target 1.5 wingspans long,
/// sweeping repeatedly from the outer edge toward the centre (one sweep a second; ours: five lines).
fn mrgs(p: &mut Vec<Prim>, i: &Input, f: Field) {
    let (y0, y1) = (f.bottom - 30.0, f.bottom - 18.0);
    let span = i.mr(36.0);
    let phase = i.time_s.rem_euclid(1.0);
    p.push(line((i.gun_cross.0, y0), (i.gun_cross.0, y1)));
    for k in 0..2 {
        let x = span * (1.0 - (phase + k as f64 * 0.5).rem_euclid(1.0));
        for side in [-1.0, 1.0] {
            let cx = i.gun_cross.0 + side * x;
            p.push(line((cx - side * 1.5, y0), (cx, y1)));
        }
    }
}

/// The operating mode / weapon window (8): NAV, "6 SRM", "3 MRM", EEGS, STRF, CCIP, PRE (Maverick / TV), HARM.
fn mode_text(w: &Weapons) -> String {
    match w.hud_mode {
        1 => format!("{} SRM", w.srm),
        2 => format!("{} MRM", w.mrm),
        3 => "EEGS".into(),
        4 => "STRF".into(),
        5 | 6 => match w.gps {
            Some(g) if g.pre => "PRE".into(),
            Some(_) => "VIS".into(),
            None => w.delivery.map_or("CCIP", |d| d.submode.name()).into(),
        },
        7 => "PRE".into(),
        8 => "HARM".into(),
        _ => "NAV".into(),
    }
}

/// "19,500".
fn thousands(ft: f64) -> String {
    let a = (ft / 10.0).round() as i64 * 10;
    if a.abs() >= 1000 { format!("{},{:03}", a / 1000, (a % 1000).abs()) } else { format!("{a}") }
}

/// The slant range window (10): the sensor letter and NM in tenths ("B115.0", "F02.5"); below 1 NM hundreds of feet
/// ("F 060").
fn slant(letter: char, m: f64) -> String {
    if m < NM { format!("{letter} {:03}", (m / FT / 100.0).round() as i64) } else { format!("{letter}{:04.1}", m / NM) }
}

/// The airspeed scale (left edge): ticks inward, labels every 50 kt in tens outside, the boxed readout with its caret
/// at the index and the "C" (calibrated) mnemonic beside it.
/// SCALES OFF leaves the box and the mnemonic (inferred).
fn airspeed(p: &mut Vec<Prim>, x: f64, y0: f64, kcas: f64, letter: &str, scale: bool) {
    let ticks_at = ticks(kcas, 10.0, KT_PX, TAPE_HALF, true).filter(|_| scale);
    if scale {
        p.push(line((x, y0 - TAPE_HALF), (x, y0 + TAPE_HALF)));
    }
    for (t, dy) in ticks_at {
        if t < 0.0 {
            continue;
        }
        let major = (t as i64) % 50 == 0;
        p.push(line((x, y0 + dy), (x + if major { 5.0 } else { 3.0 }, y0 + dy)));
        if major && dy.abs() > 8.0 {
            p.push(text((x - 2.0, y0 + dy + 3.0), format!("{}", t as i64 / 10), Align::Right));
        }
    }
    let (bx, by) = (x - 2.0, y0);
    p.extend(box_poly(bx - 26.0, by - 5.0, bx - 4.0, by + 5.0));
    p.push(line((bx - 4.0, by - 5.0), (bx, by)));
    p.push(line((bx, by), (bx - 4.0, by + 5.0)));
    p.push(text((bx - 6.0, by + 3.0), format!("{}", kcas.max(0.0).round() as i64), Align::Right));
    p.push(text((x + 7.0, y0 + 3.0), letter, Align::Left));
}

/// The altitude scale (right edge): ticks inward, labels every 500 ft ("20,5") outside, the boxed readout "20,000"
/// with its caret; `mnemonic` beside the box ("AR": the radar altitude). SCALES OFF leaves the box (inferred).
fn altitude(p: &mut Vec<Prim>, x: f64, y0: f64, alt_ft: f64, scale: bool, mnemonic: &str) {
    let ticks_at = ticks(alt_ft, 100.0, FT_PX, TAPE_HALF, true).filter(|_| scale);
    if scale {
        p.push(line((x, y0 - TAPE_HALF), (x, y0 + TAPE_HALF)));
    }
    for (t, dy) in ticks_at {
        let major = (t as i64).rem_euclid(500) == 0;
        p.push(line((x, y0 + dy), (x - if major { 5.0 } else { 3.0 }, y0 + dy)));
        if major && dy.abs() > 8.0 {
            let h = (t / 100.0).round() as i64;
            p.push(text((x + 2.0, y0 + dy + 3.0), format!("{},{}", h.div_euclid(10), h.rem_euclid(10)), Align::Left));
        }
    }
    index(p, x, y0, alt_ft, mnemonic);
}

/// The altitude scale's index at the scale's middle: the boxed readout with its caret, `mnemonic` beside it.
fn index(p: &mut Vec<Prim>, x: f64, y0: f64, ft: f64, mnemonic: &str) {
    let (bx, by) = (x + 2.0, y0);
    p.extend(box_poly(bx + 4.0, by - 5.0, bx + 34.0, by + 5.0));
    p.push(line((bx + 4.0, by - 5.0), (bx, by)));
    p.push(line((bx, by), (bx + 4.0, by + 5.0)));
    p.push(text((bx + 32.0, by + 3.0), thousands(ft), Align::Right));
    if !mnemonic.is_empty() {
        p.push(text((bx - 7.0, by + 3.0), mnemonic, Align::Right));
    }
}

/// ALT AUTO below 1,200 ft: the radar altitude's thermometer in place of the scale (docs/real-hud.md "Scales"): 0 to
/// 1,500 ft over the scale's height, ticks every 100 ft, labels 0 / 5 / 10 / 15 (hundreds), the bar filled up to the
/// radar altitude, `AR` and the radar altitude on the scale's index (as ALT RADAR's; until 2026-11-20 a box under the
/// scale, on the right column's first row).
fn thermometer(p: &mut Vec<Prim>, x: f64, y0: f64, agl_ft: f64) {
    let y = |ft: f64| y0 + TAPE_HALF - ft.clamp(0.0, 1500.0) / 1500.0 * 2.0 * TAPE_HALF;
    p.push(line((x, y(0.0)), (x, y(1500.0))));
    for k in 0..=15 {
        let ft = f64::from(k) * 100.0;
        p.push(line((x, y(ft)), (x - if k % 5 == 0 { 5.0 } else { 3.0 }, y(ft))));
        if k % 5 == 0 {
            p.push(text((x + 2.0, y(ft) + 3.0), format!("{k}"), Align::Left));
        }
    }
    // The bar: a second line beside the scale up to the height.
    p.push(line((x - 2.0, y(0.0)), (x - 2.0, y(agl_ft))));
    p.push(line((x - 3.0, y(0.0)), (x - 3.0, y(agl_ft))));
    index(p, x, y0, agl_ft, "AR");
}

/// SCALES VV/VAH: the vertical velocity scale inboard of the altitude scale (docs/real-hud.md "Scales": a fixed
/// scale, a moving triangle, ticks every 500 fpm). Ours: ±1,500 fpm over the scale's height with labels `1` / `0` /
/// `-1` (thousands), the triangle held at the ends (inferred). `ar`: `AR` beside the altitude index on the `0` label's
/// row, so the label is left out (since 2026-11-20; the two covered each other).
fn vvi(p: &mut Vec<Prim>, x: f64, y0: f64, vs_fpm: f64, ar: bool) {
    let y = |v: f64| y0 - v.clamp(-1500.0, 1500.0) / 1500.0 * TAPE_HALF;
    p.push(line((x, y(1500.0)), (x, y(-1500.0))));
    for k in -3..=3 {
        let v = f64::from(k) * 500.0;
        p.push(line((x, y(v)), (x + if k % 2 == 0 { 4.0 } else { 2.0 }, y(v))));
        if k % 2 == 0 && !(k == 0 && ar) {
            p.push(text((x + 6.0, y(v) + 3.0), format!("{}", k / 2), Align::Left));
        }
    }
    let t = y(vs_fpm);
    p.push(line((x - 1.0, t), (x - 5.0, t - 3.0)));
    p.push(line((x - 5.0, t - 3.0), (x - 5.0, t + 3.0)));
    p.push(line((x - 5.0, t + 3.0), (x - 1.0, t)));
}

/// The heading scale: 5° ticks, labels every 10° in tens either side of the boxed heading ("06 [070] 08"); the
/// steering tick at the steerpoint's bearing.
fn heading(p: &mut Vec<Prim>, y: f64, hdg: f64, bearing: Option<f64>) {
    let first = ((hdg - HDG_HALF / HDG_PX) / 5.0).ceil() as i64;
    let last = ((hdg + HDG_HALF / HDG_PX) / 5.0).floor() as i64;
    for n in first..=last {
        let t = n * 5;
        let x = (t as f64 - hdg) * HDG_PX;
        if x.abs() < 14.0 {
            continue; // under the box
        }
        let major = t.rem_euclid(10) == 0;
        p.push(line((x, y - 8.0), (x, y - if major { 12.0 } else { 10.0 })));
        if major {
            p.push(text((x, y), format!("{:02}", t.rem_euclid(360) / 10), Align::Centre));
        }
    }
    p.extend(box_poly(-12.0, y - 8.0, 12.0, y + 2.0));
    p.push(text((0.0, y), format!("{:03}", (hdg.round() as i64).rem_euclid(360)), Align::Centre));
    if let Some(b) = bearing {
        let d = rel_deg(b, hdg);
        let x = (d * HDG_PX).clamp(-HDG_HALF, HDG_HALF);
        p.push(line((x, y + 3.0), (x, y + 7.0)));
    }
}

/// The HUD's character cell (px): the text's average width (hud.gd `_gdi`, Arial h10 w5).
const CHAR_W: f64 = 5.0;

/// DED DATA's lines, one character per cell, centred in the gap `(left, right)` between the two data columns: a cell
/// clear of the left column's right-aligned text, 3 px of the right column's left-aligned text (its letters start at
/// their place). A cell is the text's own spacing (`CHAR_W`); a block wider than the gap (a narrow field) is drawn
/// smaller as a whole, its characters, cells and rows, so its characters never pack. The first row's baseline at
/// `y`, the others `ROW` apart at that size.
fn ded_block(o: &mut Vec<Prim>, lines: &[String], (left, right): (f64, f64), y: f64) {
    let w = lines.iter().map(|l| l.chars().count()).max().unwrap_or(0);
    if w == 0 {
        return;
    }
    let (left, right) = (left + CHAR_W, right - 3.0);
    let size = ((right - left) / (w as f64 * CHAR_W)).clamp(0.0, 1.0);
    let cell = CHAR_W * size;
    let c0 = (left + right) / 2.0 - cell * (w - 1) as f64 / 2.0;
    for (k, l) in lines.iter().enumerate() {
        for (j, ch) in l.chars().enumerate().filter(|(_, c)| *c != ' ') {
            let at = (c0 + j as f64 * cell, y + k as f64 * ROW * size);
            o.push(Prim::Text { at, text: ch.to_string(), align: Align::Centre, size });
        }
    }
}

/// The roll indicator: tics on a 70 mr arc centred 50 mr below the HUD centre, every 10° to ±30° and at ±45°, and the
/// pointer at the bank angle (limited to ±45°).
/// Its centre 50 mr below the FOV centre. With the original view the cockpit art's glass is shorter than the real
/// field of view, so ours raises it until its lowest tic stays above `bottom`; Real HUD view fits it (`Jet::fov_deg`).
/// The real arc sits between the data columns, its ±45° tics about 50 mr inboard of the right column (dash-34 figs.
/// 1-110 / 1-115). `gap`: the columns' inner edges' least distance from the centre; on a glass narrower than the real
/// field (Modern IAF's F-16s, their right column under the altitude scale) the arc shrinks the least that keeps its
/// tics 2 px clear of them, the pointer its size (since 2026-11-20; before, the tics crossed the column's rows).
fn roll_indicator(p: &mut Vec<Prim>, i: &Input, bottom: f64, gap: f64) {
    let real = i.mr(70.0);
    let r = real.min((gap - 2.0) * std::f64::consts::SQRT_2 - 2.5);
    let w = 3.0 * (real / r); // the pointer's half width: 3° on the real arc (exactly, unshrunk)
    let c = (0.0, i.mr(50.0).min(bottom - r - 4.0));
    let at = |deg: f64, rr: f64| {
        let a = deg.to_radians();
        (c.0 - rr * a.sin(), c.1 + rr * a.cos())
    };
    for d in [-45.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 45.0] {
        p.push(line(at(d, r), at(d, r + if d == 0.0 { 4.0 } else { 2.5 })));
    }
    let b = i.roll_deg.clamp(-45.0, 45.0);
    let tip = at(b, r - 1.0);
    let (l, rr) = (at(b - w, r - 5.0), at(b + w, r - 5.0));
    p.push(line(tip, l));
    p.push(line(l, rr));
    p.push(line(rr, tip));
}

/// The boresight cross: an incomplete plus (a centre gap) at the gun cross.
fn boresight_cross(p: &mut Vec<Prim>, i: &Input) {
    let (x, y) = i.gun_cross;
    let (g, l) = (i.mr(2.0), i.mr(8.0));
    p.push(line((x - l, y), (x - g, y)));
    p.push(line((x + g, y), (x + l, y)));
    p.push(line((x, y - l), (x, y - g)));
    p.push(line((x, y + g), (x, y + l)));
}

/// The real FCR's ACM pattern while nothing is locked (docs/radar.md §9.3; the shapes inferred from simulator
/// forums): the 10 × 60's vertical line through the boresight from 5° below it up to the field's top (two lines ±5°
/// out would sit on the airspeed and altitude scales); SLEW's cross at its
/// patch's centre, stabilised on the horizon; BORE's cross on the boresight, larger than the boresight cross. The
/// 30 × 20 shows nothing: it fills the HUD's field.
fn acm_cue(p: &mut Vec<Prim>, i: &Input) {
    let k = i.px_per_deg;
    let (bx, by) = i.boresight;
    let cross = |p: &mut Vec<Prim>, (x, y): P| {
        let l = i.mr(12.0);
        p.push(line((x - l, y), (x + l, y)));
        p.push(line((x, y - l), (x, y + l)));
    };
    match i.acm {
        Some(AcmCue::Sixty) => p.push(line((bx, by + 5.0 * k), (bx, by - 55.0 * k))),
        Some(AcmCue::Slew { az, el }) => {
            let (sn, cs) = i.roll_deg.to_radians().sin_cos();
            let h = i.horizon;
            cross(p, (h.0 + k * (az * cs - el * sn), h.1 + k * (-az * sn - el * cs)));
        }
        Some(AcmCue::Bore) => cross(p, i.boresight),
        None => {}
    }
}

/// The AoA bracket left of the marker (gear down): the marker at its top at 11°, centred at 13°, at its bottom at 15°.
fn aoa_bracket(p: &mut Vec<Prim>, i: &Input, (x, y): P) {
    let bx = x - i.mr(5.0) - i.mr(10.0) - 3.0;
    let (top, bottom) = (y + i.deg(i.aoa_deg - 15.0), y + i.deg(i.aoa_deg - 11.0));
    p.push(line((bx, top), (bx, bottom)));
    p.push(line((bx, top), (bx + 3.0, top)));
    p.push(line((bx, bottom), (bx + 3.0, bottom)));
}

/// The target designator: a 25 mr box (A-A gun: the TD circle with its range arc, 1,000 ft per clock hour, full beyond
/// 2 NM); off the field a 40 mr locator line from the gun cross toward it.
fn target_box(p: &mut Vec<Prim>, i: &Input, f: Field, at: P, gun: bool, t: Target) {
    if !f.contains(at) {
        let d = (at.0 - i.gun_cross.0, at.1 - i.gun_cross.1);
        let l = (d.0 * d.0 + d.1 * d.1).sqrt().max(1e-6);
        p.push(line(i.gun_cross, add(i.gun_cross, (d.0 / l * i.mr(40.0), d.1 / l * i.mr(40.0)))));
        return;
    }
    let h = i.mr(12.5);
    if gun {
        let ft = t.range_m / FT;
        let sweep =
            if t.range_m > 2.0 * NM { std::f64::consts::TAU } else { (ft / 12_000.0).min(1.0) * std::f64::consts::TAU };
        p.push(Prim::Arc { c: at, r: h, from: 0.0, sweep });
        // The maximum effective range (3,000 ft: 3 o'clock) as a dot outside the circle.
        p.push(Prim::Dot { c: (at.0 + h + 3.0, at.1), r: 1.0 });
    } else {
        p.extend(box_poly(at.0 - h, at.1 - h, at.0 + h, at.1 + h));
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    #[test]
    fn zenith_star_and_nadir_earth() {
        let spokes = |pitch: f64| {
            let mut i = input(Jet::F16);
            i.fpm = Some((0.0, 0.0));
            i.horizon = (0.0, pitch * i.px_per_deg);
            let fr = frame(FIELD, &i, 1.0, false);
            let ring = fr
                .field
                .iter()
                .any(|p| matches!(p, Prim::Circle { c, r } if c.1.abs() < 1.0 && (*r - i.mr(6.0)).abs() < 1e-9));
            let on = |q: &P| (0.99 * i.mr(6.0)..=1.81 * i.mr(6.0)).contains(&q.0.hypot(q.1));
            let n = fr.field.iter().filter(|p| matches!(p, Prim::Line { a, b } if on(a) && on(b))).count();
            (ring, n)
        };
        assert_eq!(spokes(90.0), (true, 8), "straight up: the star");
        assert_eq!(spokes(-90.0), (true, 2), "straight down: the earth's cross");
    }

    #[test]
    fn acm_patterns_on_the_hud() {
        let mut i = input(Jet::F16);
        let k = i.px_per_deg;
        let lines = |i: &Input| {
            let fr = frame(FIELD, i, 1.0, false);
            fr.field.into_iter().filter_map(|p| if let Prim::Line { a, b } = p { Some((a, b)) } else { None }).collect()
        };
        let base: Vec<(P, P)> = lines(&i);
        let added = |i: &Input| lines(i).into_iter().filter(|l| !base.contains(l)).collect::<Vec<_>>();
        i.acm = Some(AcmCue::Sixty);
        let sixty = added(&i);
        assert_eq!(sixty, [((0.0, 5.0 * k), (0.0, -55.0 * k))], "the 10 × 60: one line up through the boresight");
        i.acm = Some(AcmCue::Bore);
        let bore = added(&i);
        assert!(bore.len() == 2 && bore.iter().all(|(a, b)| ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0) == i.boresight));
        i.acm = Some(AcmCue::Slew { az: 10.0, el: 5.0 });
        let slew = added(&i);
        let c = ((slew[0].0.0 + slew[0].1.0) / 2.0, (slew[0].0.1 + slew[0].1.1) / 2.0);
        assert_eq!(c, (i.horizon.0 + 10.0 * k, i.horizon.1 - 5.0 * k), "SLEW: right and up of the horizon point");
    }

    #[test]
    fn the_roll_indicator_stays_above_the_field_bottom() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 0;
        let fr = frame(FIELD, &i, 1.0, false);
        let low = fr.outer.iter().filter_map(|p| match p {
            Prim::Line { a, b } => Some(a.1.max(b.1)),
            _ => None,
        });
        assert!(low.fold(f64::MIN, f64::max) <= FIELD.bottom, "a line below the glass");
    }

    /// A primitive's box (x0, y0, x1, y1): a text by its 5 px cells and 7 px capitals above the baseline, at its size.
    fn bbox(p: &Prim) -> (f64, f64, f64, f64) {
        match p {
            Prim::Text { at, text, align, size } => {
                let w = CHAR_W * size * text.chars().count() as f64;
                let x0 = match align {
                    Align::Left => at.0,
                    Align::Centre => at.0 - w / 2.0,
                    Align::Right => at.0 - w,
                };
                (x0, at.1 - 7.0 * size, x0 + w, at.1)
            }
            Prim::Line { a, b } => (a.0.min(b.0), a.1.min(b.1), a.0.max(b.0), a.1.max(b.1)),
            Prim::Circle { c, r } | Prim::Dot { c, r } | Prim::Arc { c, r, .. } => (c.0 - r, c.1 - r, c.0 + r, c.1 + r),
        }
    }

    #[test]
    fn ded_data_overlaps_nothing_in_any_mode() {
        let full: Vec<String> = (0..5).map(|_| "8".repeat(24)).collect();
        // FIELD, a narrower field (125 px between the columns), and the Sufa's and the Barak's fields (cockpit.json).
        let narrow = Field { left: -77.5, right: 77.5, ..FIELD };
        // The Sufa's and the Barak's with their right column under the altitude scale (`right_under`).
        let (sufa, barak) = (Field { left: -72.0, right: 72.0, ..FIELD }, Field { left: -58.0, right: 58.0, ..FIELD });
        let fields = [(FIELD, false), (narrow, false), (sufa, true), (barak, true)];
        for ((f, under), mode) in fields.into_iter().flat_map(|f| [0, 1, 2, 3, 5, 6, 7].map(|m| (f, m))) {
            for scales in [Scales::Vah, Scales::VvVah] {
                let mut i = input(Jet::F16);
                i.right_under = under;
                i.weapons.hud_mode = mode;
                i.agl_ft = Some(800.0);
                i.panel.scales = scales;
                let plain = frame(f, &i, 1.0, false).outer;
                i.panel.ded = full.clone();
                let with = frame(f, &i, 1.0, false).outer;
                let (ded, rest): (Vec<&Prim>, Vec<&Prim>) = with.iter().partition(|p| !plain.contains(p));
                assert_eq!(ded.len(), 120, "mode {mode}: every cell drawn");
                // The cells never closer than the text's own spacing at their size: a narrow field shrinks the block
                // as a whole.
                for d in ded.windows(2) {
                    if let [Prim::Text { at: a, size, .. }, Prim::Text { at: b, .. }] = d
                        && a.1 == b.1
                    {
                        assert!(b.0 - a.0 >= CHAR_W * size - 1e-9, "mode {mode} {f:?}: cells {a:?} {b:?} packed");
                    }
                }
                for d in ded.iter().map(|p| bbox(p)) {
                    assert!(d.0 >= f.left && d.2 <= f.right, "mode {mode}: {d:?} off the field");
                    for (p, r) in rest.iter().map(|p| (p, bbox(p))) {
                        // A text 3 px clear beside a cell, so the two do not read as one word.
                        let m = if matches!(p, Prim::Text { .. }) { 3.0 - 1e-9 } else { -0.5 };
                        let hit = d.0 - m < r.2 && r.0 < d.2 + m && d.1 < r.3 - 0.5 && r.1 < d.3 - 0.5;
                        assert!(!hit, "mode {mode} {scales:?}: DED cell {d:?} on {p:?}");
                    }
                }
            }
        }
    }

    #[test]
    fn ar_and_the_roll_tics_stay_off_the_text() {
        // The Sufa's and the Barak's fields (cockpit.json [HUD] borders), their right column under the altitude scale.
        let sufa = Field { left: -72.0, top: -66.0, right: 72.0, bottom: 67.0 };
        let barak = Field { left: -58.0, top: -61.0, right: 58.0, bottom: 67.0 };
        let hit = |a: (f64, f64, f64, f64), b: (f64, f64, f64, f64)| {
            a.0 < b.2 - 0.5 && b.0 < a.2 - 0.5 && a.1 < b.3 - 0.5 && b.1 < a.3 - 0.5
        };
        // The roll indicator's lines: the frame's less the frame's with DED DATA on, its lines blank (no indicator).
        let roll = |f: Field, i: &Input| {
            let mut no = i.clone();
            no.panel.ded = vec![String::new()];
            let no_roll = frame(f, &no, 1.0, false).outer;
            frame(f, i, 1.0, false).outer.into_iter().filter(|p| !no_roll.contains(p)).collect::<Vec<_>>()
        };
        for f in [sufa, barak] {
            for (alt, scales) in
                [AltSwitch::Auto, AltSwitch::Radar].into_iter().flat_map(|a| [(a, Scales::Vah), (a, Scales::VvVah)])
            {
                let mut i = input(Jet::F16);
                i.right_under = true;
                i.agl_ft = Some(800.0);
                i.panel.alt = alt;
                i.panel.scales = scales;
                let all = frame(f, &i, 1.0, false).outer;
                let tics: Vec<_> = roll(f, &i).iter().map(bbox).collect();
                assert_eq!(tics.len(), 12, "nine tics and the pointer's three lines");
                let texts: Vec<&Prim> = all.iter().filter(|p| matches!(p, Prim::Text { .. })).collect();
                for (t, r) in texts.iter().flat_map(|t| tics.iter().map(move |r| (t, r))) {
                    assert!(!hit(bbox(t), *r), "{f:?} {alt:?}: a roll tic {r:?} on {t:?}");
                }
                // The index: `AR` and the radar altitude, clear of every other text (the right column's `R 800` row,
                // VV/VAH's labels).
                let (index, rest): (Vec<&Prim>, Vec<&Prim>) = texts
                    .iter()
                    .copied()
                    .partition(|p| matches!(p, Prim::Text { text, .. } if text == "AR" || text == "800"));
                assert_eq!(index.len(), 2, "{alt:?}: AR and its readout");
                for (a, t) in index.iter().flat_map(|a| rest.iter().map(move |t| (a, t))) {
                    assert!(!hit(bbox(a), bbox(t)), "{f:?} {alt:?} {scales:?}: {a:?} on {t:?}");
                }
            }
            // The arc keeps its size when the DLZ moves the altitude scale and the column outward.
            let mut i = input(Jet::F16);
            i.right_under = true;
            i.weapons.hud_mode = 1;
            let plain = roll(f, &i);
            i.target =
                Some(Target { range_m: 3000.0, closure: 120.0, at: Some((10.0, -8.0)), aspect: None, ident: None });
            i.dlz = Some(Dlz { max: 9000.0, min: 900.0 });
            assert_eq!(roll(f, &i), plain, "{f:?}: the arc with the DLZ");
        }
    }

    #[test]
    fn the_right_column_sits_under_the_altitude_scale_with_right_under() {
        let mut i = input(Jet::F16);
        i.agl_ft = Some(4670.0);
        let r_x = |i: &Input| {
            frame(FIELD, i, 1.0, false).outer.iter().find_map(|p| match p {
                Prim::Text { at, text, .. } if text == "R 4,670" => Some(at.0),
                _ => None,
            })
        };
        let alt_x = FIELD.inset(INSET).right;
        assert_eq!(r_x(&i), Some(alt_x + 2.0), "the original game's: from the scale outward");
        i.right_under = true;
        assert_eq!(r_x(&i), Some(alt_x - 5.0 - 4.0 * CHAR_W), "four cells inboard of the scale's ticks");
    }

    #[test]
    fn a_limited_steerpoint_stays_off_the_scale_labels() {
        let mut i = input(Jet::F16);
        i.alt_ft = 6560.0;
        i.weapons.hud_mode = 0;
        let label = |fr: &Frame| {
            fr.outer.iter().find_map(|p| match p {
                Prim::Text { at, text, .. } if text == "7,0" => Some(*at),
                _ => None,
            })
        };
        let at = label(&frame(FIELD, &i, 1.0, false)).unwrap();
        // The steerpoint far right of a boresight level with the label's middle: held at the edge, with its X.
        let y = at.1 - 3.0;
        i.boresight = (0.0, y);
        i.steerpoint.as_mut().unwrap().at = Some((10.0 * FIELD.right, y));
        let fr = frame(FIELD, &i, 1.0, false);
        let right = fr
            .field
            .iter()
            .filter_map(|p| match p {
                Prim::Line { a, b } if (a.1 - y).abs() < 8.0 && (b.1 - y).abs() < 8.0 => Some(a.0.max(b.0)),
                _ => None,
            })
            .fold(f64::MIN, f64::max);
        assert!(right > 0.0 && right < at.0 - 6.0, "the diamond's right end {right}, the label at {}", at.0);
    }

    #[test]
    fn shoot_takes_the_centre_window() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 2;
        i.weapons.shoot = true;
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(texts(&fr.outer).contains(&"SHOOT"));
        i.weapons.shoot = false;
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(!texts(&fr.outer).contains(&"SHOOT"));
    }

    #[test]
    fn after_a_launch_the_time_to_active_then_to_impact() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 2;
        let before = frame(FIELD, &i, 1.0, false);
        assert!(!texts(&before.outer).contains(&"A12"), "no missile flying");
        i.weapons.msl_time = Some(MslTime { active: true, s: 11.2 });
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(texts(&fr.outer).contains(&"A12"), "{:?}", texts(&fr.outer));
        i.weapons.msl_time = Some(MslTime { active: false, s: 6.5 });
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(texts(&fr.outer).contains(&"T07") && !texts(&fr.outer).contains(&"A12"));
    }

    #[test]
    fn the_srm_diamond_grows_when_uncaged_and_tracking() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 1;
        i.weapons.seeker = Some((20.0, 10.0));
        let top = |i: &Input| {
            frame(FIELD, i, 1.0, false).field.iter().any(|p| {
                matches!(p, Prim::Line { a, b } if *a == (20.0, 10.0 - i.mr(8.0)) && *b == (20.0 + i.mr(8.0), 10.0))
            })
        };
        assert!(!top(&i), "caged: the small diamond");
        i.weapons.srm_track = true;
        assert!(top(&i), "uncaged and tracking: the large one");
    }

    #[test]
    fn nav_windows_as_the_dash_34() {
        let mut i = input(Jet::F16);
        i.agl_ft = Some(19_500.0);
        let fr = frame(FIELD, &i, 4.1, false);
        let t = texts(&fr.outer);
        for want in [
            "352", "C", "10,450", "2.3", "0.85", "4.1", "NAV", "R 19,500", "AL 300", "B12.0", "05:23", "012>03", "333",
            "32", "34",
        ] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        assert!(!t.contains(&"ARM"), "NAV: no ARM");
    }

    #[test]
    fn the_hud_panel_switches() {
        let mut i = input(Jet::F16);
        i.fpm = Some((0.0, 0.0));
        i.agl_ft = Some(800.0);
        i.vs_fpm = 1000.0;
        let all = |i: &Input| {
            let fr = frame(FIELD, i, 1.0, false);
            (texts(&fr.outer).into_iter().map(String::from).collect::<Vec<_>>(), fr.field.len(), fr.outer.len())
        };
        let (t0, field0, outer0) = all(&i);
        assert!(t0.iter().any(|t| t == "C") && t0.iter().any(|t| t == "352"), "CAS: {t0:?}");
        // VV/VAH: the vertical velocity scale's labels.
        i.panel.scales = Scales::VvVah;
        let (t, ..) = all(&i);
        assert!(t.iter().any(|t| t == "-1") && t.iter().filter(|t| *t == "1").count() >= 1, "{t:?}");
        // OFF: the scales go, the boxes stay.
        i.panel.scales = Scales::Off;
        let (t, _, outer) = all(&i);
        assert!(outer < outer0 && t.iter().any(|t| t == "352") && !t.iter().any(|t| t == "35"), "{t:?}");
        i.panel.scales = Scales::Vah;
        // FPM alone: fewer field symbols (no ladder); OFF: fewer still.
        i.panel.fpm = FpmSwitch::Fpm;
        let (_, f1, _) = all(&i);
        i.panel.fpm = FpmSwitch::Off;
        let (_, f2, _) = all(&i);
        assert!(f2 < f1 && f1 < field0, "{field0} {f1} {f2}");
        i.panel.fpm = FpmSwitch::AttFpm;
        // GND SPD; CAS again with the gear down.
        i.panel.velocity = Velocity::Gnd;
        let (t, ..) = all(&i);
        assert!(t.iter().any(|t| t == "G") && t.iter().any(|t| t == "380"), "{t:?}");
        i.gear_down = true;
        assert!(all(&i).0.iter().any(|t| t == "C"));
        i.gear_down = false;
        // ALT AUTO below 1,200 ft: the thermometer's AR box; RADAR: the radar altitude with AR.
        i.panel.alt = AltSwitch::Auto;
        let (t, ..) = all(&i);
        assert!(t.iter().any(|t| t == "AR") && t.iter().any(|t| t == "15") && t.iter().any(|t| t == "800"), "{t:?}");
        i.panel.alt = AltSwitch::Radar;
        assert!(all(&i).0.iter().any(|t| t == "AR"));
        i.panel.alt = AltSwitch::Baro;
        // ALIGN, SIM, DGFT, the SOI asterisk, DED DATA, the ALOW setting.
        i.panel.align = Some(false);
        i.panel.sim = true;
        i.panel.over = 1;
        i.panel.soi = true;
        i.panel.ded = vec!["UHF  305.00  STPT   1".into()];
        i.panel.alow_ft = Some(500.0);
        let (t, ..) = all(&i);
        // DED DATA: a character per cell, on the right column's second row (FIELD: -6 + 36 + 12 + 9).
        let row: String = frame(FIELD, &i, 1.0, false)
            .outer
            .iter()
            .filter_map(|p| match p {
                Prim::Text { at, text, .. } if at.1 == 51.0 && text.len() == 1 => Some(text.as_str()),
                _ => None,
            })
            .collect();
        assert_eq!(row, "UHF305.00STPT1");
        for s in ["ALIGN", "SIM", "DGFT", "*", "AL 500"] {
            assert!(t.iter().any(|x| x == s), "{s}: {t:?}");
        }
        i.panel.align = Some(true);
        i.time_s = 0.3;
        assert!(!all(&i).0.iter().any(|t| t == "ALIGN"), "ready: ALIGN flashes");
        // DEPR RET STBY: the standby reticle's ring, 100 mr down.
        i.panel.depr_mr = Some(100.0);
        let fr = frame(FIELD, &i, 1.0, false);
        let c = add(i.gun_cross, (0.0, i.mr(100.0)));
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Circle { c: q, .. } if *q == c)));
    }

    #[test]
    fn alow_flashes_below_its_height() {
        let mut i = input(Jet::F16);
        i.agl_ft = Some(250.0);
        let at = |fr: &Frame, s: &str| {
            fr.outer.iter().find_map(|p| match p {
                Prim::Text { at, text, .. } if text == s => Some(*at),
                _ => None,
            })
        };
        let lit = frame(FIELD, &i, 1.0, false);
        let (r, al) = (at(&lit, "R 250").unwrap(), at(&lit, "AL 300").unwrap());
        assert_eq!((al.0, al.1 - r.1), (r.0, ROW), "under the radar altitude");
        i.time_s = 0.3;
        let dark = frame(FIELD, &i, 1.0, false);
        assert!(at(&dark, "AL 300").is_none(), "flashing");
        assert_eq!(at(&dark, "B12.0").unwrap().1, at(&lit, "B12.0").unwrap().1, "the rows below stay");
        i.agl_ft = Some(400.0);
        assert!(at(&frame(FIELD, &i, 1.0, false), "AL 300").is_some(), "steady above ALOW");
    }

    #[test]
    fn drift_cut_out_centres_the_marker() {
        let mut i = input(Jet::F16);
        i.fpm = Some((12.0, 4.0));
        let has_marker_at = |i: &Input, x: f64| {
            frame(FIELD, i, 1.0, false)
                .field
                .iter()
                .any(|p| matches!(p, Prim::Circle { c, r } if (c.0 - x).abs() < 1e-9 && (*r - i.mr(5.0)).abs() < 1e-9))
        };
        assert!(has_marker_at(&i, 12.0) && !has_marker_at(&i, i.boresight.0), "NORM: the marker shows the drift");
        i.panel.drift_co = true;
        assert!(has_marker_at(&i, i.boresight.0) && !has_marker_at(&i, 12.0), "DRIFT C/O: centred");
    }

    #[test]
    fn warn_reset_puts_the_fuel_cue_out() {
        let mut i = input(Jet::F16);
        i.fuel_lbs = 2500.0;
        i.bingo_lbs = 3000.0;
        let mut h = crate::real_hud::RealHud::default();
        let fuel = |h: &mut crate::real_hud::RealHud, i: &Input| texts(&h.frame(FIELD, i).outer).contains(&"FUEL");
        assert!(fuel(&mut h, &i));
        h.warn_reset();
        assert!(!fuel(&mut h, &i), "reset");
        i.fuel_lbs = 3500.0;
        fuel(&mut h, &i);
        i.fuel_lbs = 2500.0;
        assert!(fuel(&mut h, &i), "back below the bingo: the cue again");
    }

    #[test]
    fn bingo_is_the_players() {
        let mut i = input(Jet::F16);
        i.fuel_lbs = 2500.0;
        assert!(!texts(&frame(FIELD, &i, 1.0, false).outer).contains(&"FUEL"));
        i.bingo_lbs = 3000.0;
        assert!(texts(&frame(FIELD, &i, 1.0, false).outer).contains(&"FUEL"));
    }

    #[test]
    fn pullup_cue_rises_to_the_marker() {
        // A 45° dive at 413 kt (the advisory at about 2,270 ft) in CCIP.
        let v = 413.0 * 0.514444;
        let mut i = Input {
            kcas: 413.0,
            tas_ms: v,
            vs_fpm: -v * std::f64::consts::FRAC_1_SQRT_2 * 196.85,
            fpm: Some((0.0, 0.0)),
            ..input(Jet::F16)
        };
        i.weapons.hud_mode = 5;
        let u = |i: &Input, agl: f64| {
            let i = Input { agl_ft: Some(agl), ..i.clone() };
            frame(FIELD, &i, 1.0, false).field.into_iter().find_map(|p| match p {
                Prim::Line { a, b }
                    if a.1 == b.1 && (b.0 + a.0).abs() < 1e-9 && (b.0 - a.0 - i.mr(24.0)).abs() < 1e-9 =>
                {
                    Some(a.1)
                }
                _ => None,
            })
        };
        let h = crate::gaaf::advisory_height(i.kcas, i.tas_ms, i.vs_fpm, 0.0, false, true).unwrap();
        let sink = -i.vs_fpm / 60.0;
        assert_eq!(u(&i, h + 12.0 * sink), None, "12 s out: not yet");
        let far = u(&i, h + 5.0 * sink).unwrap();
        assert!((far - i.mr(5.0 + 50.0)).abs() < 1e-6, "5 s out: 50 mr below the marker's circle");
        assert!((u(&i, h - 10.0).unwrap() - i.mr(5.0)).abs() < 1e-9, "at the advisory: cupping the marker");
        i.weapons.hud_mode = 0;
        assert_eq!(u(&i, h + 5.0 * sink), None, "A-G modes only");
    }

    #[test]
    fn weapon_modes() {
        let mut i = input(Jet::F16);
        i.weapons = Weapons { hud_mode: 2, mrm: 3, circle: 4.0, ..Weapons::default() };
        i.target =
            Some(Target { range_m: 15.0 * NM, closure: 200.0, at: Some((5.0, -5.0)), aspect: None, ident: None });
        i.dlz = Some(Dlz { max: 18.0 * NM, min: 2.0 * NM });
        let t = frame(FIELD, &i, 2.3, false);
        let tx = texts(&t.outer);
        for want in ["ARM", "3 MRM", "F15.0", "390>", "20"] {
            assert!(tx.contains(&want), "{want} in {tx:?}");
        }
        i.weapons.hud_mode = 3;
        i.target = Some(Target { range_m: 600.0, closure: 100.0, at: Some((5.0, -5.0)), aspect: None, ident: None });
        let g = frame(FIELD, &i, 2.3, false);
        let gt = texts(&g.outer);
        assert!(gt.contains(&"EEGS") && gt.contains(&"F 020") && gt.contains(&"194"), "{gt:?}");
        assert!(g.field.iter().any(|p| matches!(p, Prim::Arc { .. })), "the TD circle's range arc");
    }

    #[test]
    fn break_x() {
        let f = Field { left: -100.0, top: -80.0, right: 100.0, bottom: 80.0 };
        let long = |fr: &Frame| {
            fr.field
                .iter()
                .filter(|p| matches!(p, Prim::Line { a, b } if (a.0 - b.0).abs() > 90.0 && (a.1 - b.1).abs() > 90.0))
                .count()
        };
        // A 45° dive at 413 kt, 2,000 ft above the ground: the GAAF X, flashing.
        let v = 413.0 * 0.514444;
        let mut i = Input {
            agl_ft: Some(2000.0),
            tas_ms: v,
            kcas: 413.0,
            vs_fpm: -v * std::f64::consts::FRAC_1_SQRT_2 * 196.85,
            ..input(Jet::F16)
        };
        i.weapons.hud_mode = 5;
        assert_eq!(long(&frame(f, &i, 1.0, false)), 2, "the break X");
        i.time_s = 0.3;
        assert_eq!(long(&frame(f, &i, 1.0, false)), 0, "flashing");
        i.agl_ft = Some(3000.0);
        i.time_s = 0.0;
        assert_eq!(long(&frame(f, &i, 1.0, false)), 0, "above the advisory height");
        // A-A: the target inside Rmin.
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 2;
        i.target = Some(Target { range_m: 1000.0, ..Default::default() });
        i.dlz = Some(Dlz { max: 20_000.0, min: 1500.0 });
        assert_eq!(long(&frame(f, &i, 1.0, false)), 2, "inside Rmin");
        i.target = Some(Target { range_m: 5000.0, ..Default::default() });
        assert_eq!(long(&frame(f, &i, 1.0, false)), 0, "inside the DLZ");
    }

    #[test]
    fn eegs_levels() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 3;
        let low = |fr: &Frame| {
            fr.field
                .iter()
                .filter(|p| matches!(p, Prim::Line { a, .. } if (a.1 - (FIELD.bottom - 30.0)).abs() < 1e-9))
                .count()
        };
        let l2 = frame(FIELD, &i, 2.3, false);
        assert_eq!(low(&l2), 5, "level 2: the five MRGS lines");
        i.target =
            Some(Target { range_m: 1500.0 * FT, closure: 50.0, at: Some((0.0, 20.0)), aspect: None, ident: None });
        i.weapons.lcos = Some((1.0, 18.0));
        let l5 = frame(FIELD, &i, 2.3, false);
        assert_eq!(low(&l5), 0, "with a track the MRGS lines go");
        let long_bar = l5
            .field
            .iter()
            .any(|p| matches!(p, Prim::Line { a, b } if (a.1 - b.1).abs() < 1e-9 && (b.0 - a.0) > i.mr(30.0)));
        assert!(long_bar, "the T-symbol's bars");
        assert!(l5.field.iter().any(|p| matches!(p, Prim::Dot { .. })), "the maximum-effective-range dot");
    }

    #[test]
    fn release_submodes_on_the_hud() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 5;
        i.fpm = Some((0.0, 0.0));
        i.weapons.pipper = Some((0.0, 30.0));
        let h = i.mr(5.0);
        let has_box = |fr: &Frame, c: P| {
            fr.field
                .iter()
                .any(|p| matches!(p, Prim::Line { a, b } if *a == (c.0 - h, c.1 - h) && *b == (c.0 + h, c.1 - h)))
        };
        let cue = |s| DeliveryCue { submode: s, td: Some((10.0, -20.0)), ttr: Some(4.0), ..DeliveryCue::default() };
        // CCRP: the mode, the time to release, the TD box and the steering line through it; no CCIP pipper.
        i.weapons.delivery = Some(cue(Submode::Ccrp));
        let fr = frame(FIELD, &i, 1.0, false);
        let t = texts(&fr.outer);
        assert!(t.contains(&"CCRP") && t.contains(&"00:04"), "{t:?}");
        assert!(!fr.field.iter().any(|p| matches!(p, Prim::Dot { .. })), "no CCIP pipper");
        assert!(has_box(&fr, (10.0, -20.0)), "the TD box");
        let asl = fr.field.iter().any(
            |p| matches!(p, Prim::Line { a, b } if a.0 == 10.0 && b.0 == 10.0 && a.1 < FIELD.top && b.1 > FIELD.bottom),
        );
        assert!(asl, "the azimuth steering line");
        // LADD 4 s before the pull-up: the time to it, the anticipation cue 40 mr above the marker's top.
        i.weapons.delivery = Some(DeliveryCue { pull_up: Some(4.0), ..cue(Submode::Ladd) });
        let fr = frame(FIELD, &i, 1.0, false);
        let up = -i.mr(5.0) - i.mr(CUE_MR_PER_S) * 4.0;
        let anticipation = fr.field.iter().any(|p| {
            matches!(p, Prim::Line { a, b } if (a.1 - up).abs() < 1e-9 && (b.1 - up).abs() < 1e-9 && a.0 < 0.0 && b.0 > 0.0)
        });
        assert!(anticipation && texts(&fr.outer).contains(&"LADD"), "the pull-up anticipation cue");
        // DTOS before designation: the TD box rides the marker.
        i.weapons.delivery = Some(DeliveryCue { submode: Submode::Dtos, ..DeliveryCue::default() });
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(has_box(&fr, (0.0, 0.0)) && texts(&fr.outer).contains(&"DTOS"));
        // MAN at PRI: the primary reticle and its depression, no pipper.
        i.weapons.delivery = Some(DeliveryCue { submode: Submode::Man, man_mr: Some(120.0), ..DeliveryCue::default() });
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(texts(&fr.field).contains(&"120") && texts(&fr.outer).contains(&"MAN"));
        let c = add(i.gun_cross, (0.0, i.mr(120.0)));
        let ring = |p: &Prim| matches!(p, Prim::Circle { c: k, r } if *k == c && (*r - i.mr(50.0)).abs() < 1e-9);
        assert!(fr.field.iter().any(ring), "the 100 mr circle");
        // LOW beside the marker, in CCIP too, which keeps its pipper.
        i.weapons.delivery = Some(DeliveryCue { low: true, ..DeliveryCue::default() });
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(texts(&fr.field).contains(&"LOW") && texts(&fr.outer).contains(&"CCIP"));
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Dot { .. })), "the CCIP pipper");
    }

    #[test]
    fn delayed_ccip() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 5;
        i.fpm = Some((0.0, 0.0));
        i.weapons.pipper = Some((0.0, 200.0)); // the impact point, below the glass
        let pip = |fr: &Frame| fr.field.iter().find_map(|p| if let Prim::Dot { c, .. } = p { Some(*c) } else { None });
        // The delay cue: a 12 mr line across the fall line at height y.
        let h = i.mr(6.0);
        let ticks = |fr: &Frame, y: f64| {
            fr.field.iter().filter(|p| matches!(p, Prim::Line { a, b } if (a.1 - y).abs() < 1e-6 && (b.1 - y).abs() < 1e-6 && (a.0 + b.0).abs() < 1e-6 && ((a.0 - b.0).abs() - 2.0 * h).abs() < 1e-6)).count()
        };
        // CCIP: the pipper on the impact point (clipped by the field).
        assert_eq!(pip(&frame(FIELD, &i, 1.0, false)), Some((0.0, 200.0)));
        // Delayed: the pipper on the target under the HUD-edge point, kept on the glass; the delay cue across the
        // fall line from the marker toward it (5 s to go: half way).
        i.weapons.delay = Some(Delay { ttg: 5.0, target: Some((0.0, 100.0)), designated: false });
        let fr = frame(FIELD, &i, 1.0, false);
        assert_eq!(pip(&fr), Some((0.0, FIELD.bottom)), "held on the glass");
        assert_eq!(ticks(&fr, 0.5 * FIELD.bottom), 1, "the time delay cue half way");
        i.weapons.delay = Some(Delay { ttg: 12.0, target: Some((0.0, 60.0)), designated: false });
        assert_eq!(ticks(&frame(FIELD, &i, 1.0, false), 0.0), 1, "10 s or more: the cue at the marker");
        // Designated: no pipper; the steering line through the target, the solution cue above the marker.
        i.weapons.delay = Some(Delay { ttg: 4.9, target: Some((20.0, 60.0)), designated: true });
        let fr = frame(FIELD, &i, 1.0, false);
        assert_eq!(pip(&fr), None);
        let steer = fr.field.iter().any(
            |p| matches!(p, Prim::Line { a, b } if a.0 == 20.0 && b.0 == 20.0 && a.1 < FIELD.top && b.1 > FIELD.bottom),
        );
        assert!(steer, "the steering line through the target");
        let cue_y = -i.mr(CUE_MR_PER_S) * 4.0;
        let cue = fr.field.iter().any(|p| matches!(p, Prim::Line { a, b } if (a.0 - 20.0).abs() < 1e-9 && b.0 < 20.0 && (a.1 - cue_y).abs() < 1e-9 && (b.1 - cue_y).abs() < 1e-9));
        assert!(cue, "the solution cue 4 s above the marker, left of the line");
        assert!(texts(&fr.outer).contains(&"00:04"), "the time to release");
        // Far out: pegged at the glass's top.
        i.weapons.delay = Some(Delay { ttg: 30.0, target: Some((20.0, 60.0)), designated: true });
        let low = Field { top: -40.0, ..FIELD };
        let fr = frame(low, &i, 1.0, false);
        let pegged = |q: &P| (q.1 - low.top).abs() < 1e-9;
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Line { a, b } if (a.0 - 20.0).abs() < 1e-9 && b.0 < 20.0 && pegged(a) && pegged(b))), "pegged");
        // At the release the cue reaches the marker's level; rolled 90° right the line runs across the HUD.
        i.weapons.delay = Some(Delay { ttg: 0.9, target: Some((20.0, 60.0)), designated: true });
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(
            fr.field
                .iter()
                .any(|p| matches!(p, Prim::Line { a, b } if a.0 == 20.0 && a.1.abs() < 1e-9 && b.1.abs() < 1e-9)),
            "the cue on the marker"
        );
        i.roll_deg = 90.0;
        let fr = frame(FIELD, &i, 1.0, false);
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Line { a, b } if (a.1 - 60.0).abs() < 1e-9 && (b.1 - 60.0).abs() < 1e-9 && a.0 < FIELD.left && b.0 > FIELD.right)));
    }

    #[test]
    fn slant_formats() {
        assert_eq!(slant('B', 115.0 * NM), "B115.0");
        assert_eq!(slant('F', 2.5 * NM), "F02.5");
        assert_eq!(slant('F', 6000.0 * FT), "F 060");
        // AGR's ranging replaces the steerpoint's (docs/radar.md §9.7).
        let mut i = input(Jet::F16);
        i.agr_m = Some(2.5 * NM);
        let t = frame(FIELD, &i, 1.0, false);
        assert!(texts(&t.outer).contains(&"F02.5") && !texts(&t.outer).contains(&"B12.0"));
    }
}
