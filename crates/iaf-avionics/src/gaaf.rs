//! The F-16's ground collision avoidance advisories (Real HUD only; docs/real-hud.md "Ground avoidance"): the
//! ground avoidance advisory function (GAAF: the break X and "PULL UP – PULL UP") and CARA ALOW ("ALTITUDE –
//! ALTITUDE"). Sources: T.O. GR1F-16CJ-34-1-1 pp. 1-173, 1-313..1-316; the ALOW default from docs/real-betty.md;
//! what the sources leave open is inferred (marked "ours").

const G: f64 = 9.80665;
const FT: f64 = 3.28084;
/// The recovery: a 4.0 g wings-level pull-up.
const PULL_G: f64 = 4.0;
/// Pilot reaction time 1 s; 0.45 s in the A-G modes at a low dive angle, low bank and high speed.
const REACTION_S: f64 = 1.0;
const REACTION_AG_S: f64 = 0.45;
/// "Low dive angle, low bank, high speed" in numbers: ours.
const AG_LOW_DIVE_DEG: f64 = 30.0;
const AG_LOW_BANK_DEG: f64 = 30.0;
const AG_HIGH_KCAS: f64 = 400.0;
/// The roll to wings level before the pull-up: the manual uses the jet's maximum roll rate for its stores; ours a
/// fixed 180°/s (ours).
const ROLL_RATE_DPS: f64 = 180.0;
/// CARA ALOW: the default 300 ft (docs/real-betty.md); the dash-34's DED example shows 200 ft (fig. 1-213).
pub const ALOW_FT: f64 = 300.0;

/// GAAF (p. 1-313): gear up, above 50 ft AGL, descending at 960 fpm or more, and the height at or below the height
/// lost in the recovery (reaction, the roll to wings level, the 4 g pull-up) plus the clearance buffer: above 375 KCAS
/// 12.5 % of it + 50 ft, below 325 KCAS 25 % + 150 ft, linear between (p. 1-314). `ag`: an A-G HUD mode.
#[allow(clippy::too_many_arguments)]
pub fn advisory(agl_ft: f64, kcas: f64, tas_ms: f64, vs_fpm: f64, roll_deg: f64, gear_down: bool, ag: bool) -> bool {
    if gear_down || agl_ft <= 50.0 || vs_fpm > -960.0 || tas_ms <= 0.0 {
        return false;
    }
    let sink = -vs_fpm / 60.0 / FT; // m/s
    let dive = (sink / tas_ms).clamp(0.0, 1.0).asin();
    let bank = roll_deg.abs().min(180.0);
    let fast_shallow = ag && dive.to_degrees() < AG_LOW_DIVE_DEG && bank < AG_LOW_BANK_DEG && kcas > AG_HIGH_KCAS;
    let react = if fast_shallow { REACTION_AG_S } else { REACTION_S };
    let roll_s = bank / ROLL_RATE_DPS;
    let radius = tas_ms * tas_ms / (G * (PULL_G - 1.0));
    let loss_ft = (sink * (react + roll_s) + radius * (1.0 - dive.cos())) * FT;
    let k = ((kcas - 325.0) / 50.0).clamp(0.0, 1.0);
    let buffer = loss_ft * (0.25 - 0.125 * k) + 150.0 - 100.0 * k;
    agl_ft <= loss_ft + buffer
}

/// CARA ALOW's voice (p. 1-316): below the ALOW height; it stops above it, climbing faster than 1,200 fpm, with the
/// gear handle down or below 15 ft.
pub fn alow(agl_ft: f64, vs_fpm: f64, gear_down: bool) -> bool {
    (15.0..ALOW_FT).contains(&agl_ft) && vs_fpm <= 1200.0 && !gear_down
}

#[cfg(test)]
mod tests {
    use super::*;

    const KT: f64 = 0.514444;

    fn dive(deg: f64, kt: f64) -> (f64, f64) {
        let v = kt * KT;
        (v, -v * deg.to_radians().sin() * FT * 60.0)
    }

    #[test]
    fn dives() {
        // 45° at 413 kt: about 2,270 ft (the 2,300 ft bombing dive is just outside).
        let (v, vs) = dive(45.0, 413.0);
        assert!(advisory(2200.0, 413.0, v, vs, 0.0, false, true));
        assert!(!advisory(2400.0, 413.0, v, vs, 0.0, false, true));
        // 20° at 414 kt strafing: the shorter A-G reaction, about 520 ft.
        let (v, vs) = dive(20.0, 414.0);
        assert!(advisory(500.0, 414.0, v, vs, 0.0, false, true));
        assert!(!advisory(560.0, 414.0, v, vs, 0.0, false, true));
        assert!(advisory(560.0, 414.0, v, vs, 0.0, false, false), "1 s reaction outside A-G");
        // Gated: gear down, level flight, at 50 ft.
        assert!(!advisory(500.0, 414.0, v, vs, 0.0, true, true));
        assert!(!advisory(500.0, 414.0, v, -500.0, 0.0, false, true));
        assert!(!advisory(50.0, 414.0, v, vs, 0.0, false, true));
        // Banked: the roll to wings level costs height.
        assert!(advisory(700.0, 414.0, v, vs, 120.0, false, false));
    }

    #[test]
    fn alow_rule() {
        assert!(alow(250.0, -500.0, false));
        assert!(!alow(350.0, -500.0, false) && !alow(150.0, 1500.0, false) && !alow(150.0, 0.0, true));
        assert!(!alow(10.0, 0.0, false));
    }
}
