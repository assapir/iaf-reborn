//! The F-16's own autopilot, a loop of its flight control computer (modern-iaf/docs/research/f16-autopilot.md;
//! T.O. GR1F-16CJ-1 pp. 1-129, 1-131, 1-134 to 1-136, 3-112, 6-2). The PITCH switch (ALT HOLD / A/P OFF / ATT HOLD)
//! engages it; the ROLL switch (HDG SEL / ATT HOLD / STRG SEL) picks the roll mode. Its commands are added to the
//! stick's in the control laws ([`super::fcs::Pilot`] `ap_g`, `ap_p`): "the autopilot command is additive to stick
//! commands" (p. 6-2). The PITCH switch is solenoid held: each condition of p. 1-135 drops it to A/P OFF.
//!
//! The manual gives the modes, their limits and the disengage rules; the gains, the stick-steering threshold and the
//! altitude ALT HOLD selects are inferred.

/// The PITCH switch's positions (FlightGear's `f16/fcs/switch-pitch-block20`): 1 ALT HOLD, 0 A/P OFF, −1 ATT HOLD.
pub const ALT_HOLD: i8 = 1;
pub const ATT_HOLD: i8 = -1;
/// The ROLL switch's (`switch-roll-block20`): 1 HDG SEL, 0 ATT HOLD, −1 STRG SEL.
pub const HDG_SEL: i8 = 1;
pub const STRG_SEL: i8 = -1;

/// Above this α (deg) the autopilot disconnects, FLCS A/P FAIL (p. 1-136).
const AOA_LIMIT: f64 = 15.0;
/// Beyond this pitch or bank (deg) an attitude mode does not function; the switch stays (p. 1-136).
const ATT_LIMIT: f64 = 60.0;
/// The FLCS limits the pitch command to +0.5 g to +2 g (p. 1-136, ALT HOLD; ATT HOLD the same, inferred).
const G_MIN: f64 = 0.5;
const G_MAX: f64 = 2.0;
/// HDG SEL and STRG SEL: at most 30° of bank and 20 deg/s of roll rate (p. 1-136; ATT HOLD the same rate, inferred).
const BANK_MAX: f64 = 30.0;
const ROLL_RATE_MAX: f64 = 20.0;
/// ALT HOLD engaged below 2,000 ft/min selects an altitude it can capture within its g limits (p. 1-136), m/s; the
/// climb or dive it flies back to its altitude at (inferred: the same rate).
const CAPTURE_VS: f64 = 2000.0 * 0.3048 / 60.0;
/// ALT FLAPS at EXTEND drops the autopilot below this calibrated airspeed, kt (p. 1-135).
const ALT_FLAPS_KT: f64 = 400.0;
/// FLCS A/P DEGR after this long (s): outside the attitude limits with no stick input; the roll command at its
/// authority in roll ATT HOLD; the pitch command at its authority, no stick input and not correcting (p. 3-112).
const DEGR_OUTSIDE_S: f64 = 12.0;
const DEGR_ROLL_S: f64 = 12.0;
const DEGR_PITCH_S: f64 = 5.0;
/// The low speed warning tone (figure 1-50, p. 1-132; the line as FlightGear reads it, `jsb-misc.xml`): with the
/// gear handle up and ALT FLAPS at NORM, pitch above 45° and the calibrated airspeed below this line (deg, kt).
const LOW_SPEED: [(f64, f64); 2] = [(45.0, 75.0), (90.0, 183.0)];
/// The gains (inferred): climb rate per metre of altitude error (1/s); g per m/s of climb-rate error × g (1/s);
/// flight-path rate per pitch error (1/s); roll rate per degree of bank error (1/s); bank per degree of heading error.
const K_ALT: f64 = 0.1;
const K_VS: f64 = 0.5;
const K_PITCH: f64 = 0.5;
const K_BANK: f64 = 1.0;
const K_HDG: f64 = 2.0;
/// A stick past this share of its travel is stick steering in the attitude hold modes, and a stick input for the DEGR
/// timers (inferred: just past the gradients' dead bands, `fcs::PITCH_GRADIENT` / `ROLL_GRADIENT`, about 0.06).
pub const STEER: f64 = 0.1;
const G: f64 = crate::units::G;

/// The panel and stick inputs the autopilot reads besides the jet's motion.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Panel {
    /// The stick's paddle switch held: the autopilot is interrupted (p. 1-129).
    pub paddle: bool,
    /// TRIM/AP DISC at DISC (p. 1-131).
    pub disc: bool,
    /// AIR REFUEL at OPEN.
    pub air_refuel: bool,
    /// The EHSI's heading marker, deg (None: never set, HDG SEL holds the heading it engaged on; inferred).
    pub hdg_bug: Option<f64>,
    /// The bearing to the selected steerpoint, deg (None: no steerpoint, STRG SEL holds its heading; inferred).
    pub steer: Option<f64>,
}

/// The jet as the autopilot senses it (the INS's attitude, the CADC's air data).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Sensed {
    /// Pitch, bank (right +) and heading (clockwise from north), deg.
    pub pitch: f64,
    pub roll: f64,
    pub heading: f64,
    /// Altitude, m, and climb rate, m/s.
    pub alt: f64,
    pub vs: f64,
    /// True airspeed, m/s; calibrated, kt; α, deg.
    pub speed: f64,
    pub cas_kt: f64,
    pub alpha: f64,
    /// The stick, −1…1: x right, y pulled.
    pub stick: (f64, f64),
    pub gear_handle_down: bool,
    pub alt_flaps: bool,
    /// The MANUAL PITCH override at OVRD.
    pub mpo: bool,
    /// The data the loop needs (power, the INS aligned, the autopilot not damaged): without it, A/P FAIL.
    pub data_ok: bool,
    /// The game's own autopilot (`crate::autopilot`, the A key) flies the jet.
    pub other_ap: bool,
}

/// The autopilot's state: the two switches, the latched faults, the references.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct F16Autopilot {
    /// The PITCH switch ([`ALT_HOLD`], 0, [`ATT_HOLD`]) and the ROLL switch ([`HDG_SEL`], 0, [`STRG_SEL`]).
    pub pitch_sw: i8,
    pub roll_sw: i8,
    /// FLCS A/P FAIL: latched until an FLCS RESET clears it; the autopilot cannot be engaged meanwhile (p. 3-112).
    pub fail: bool,
    /// FLCS A/P DEGR: the autopilot is not providing its mode (p. 3-112); it stays engaged.
    pub degr: bool,
    alt_ref: f64,
    pitch_ref: f64,
    bank_ref: f64,
    hdg_ref: f64,
    /// A reference is taken at the next step out of the paddle or stick steering.
    take_pitch: bool,
    take_roll: bool,
    t_outside: f64,
    t_roll_max: f64,
    t_pitch_max: f64,
    last_err: f64,
}

/// The low speed warning tone sounds (figure 1-50; the gear-down half of the tone is the AoA's 15°, which fails the
/// autopilot first).
pub fn low_speed_tone(s: &Sensed) -> bool {
    let [(p0, v0), (p1, v1)] = LOW_SPEED;
    !s.gear_handle_down
        && !s.alt_flaps
        && s.pitch > p0
        && s.cas_kt < v0 + (v1 - v0) * ((s.pitch - p0) / (p1 - p0)).min(1.0)
}

/// Why the PITCH switch cannot stay engaged (p. 1-135's conditions; DBU and standby gains the sim has not), or None.
pub fn inhibit(s: &Sensed, p: &Panel) -> Option<&'static str> {
    if p.air_refuel {
        Some("AIR REFUEL open")
    } else if s.alt_flaps && s.cas_kt < ALT_FLAPS_KT {
        Some("ALT FLAPS extended")
    } else if s.gear_handle_down {
        Some("gear handle down")
    } else if s.mpo {
        Some("MPO at OVRD")
    } else if p.disc {
        Some("TRIM/AP DISC at DISC")
    } else if low_speed_tone(s) {
        Some("low speed")
    } else if s.other_ap {
        Some("the game's autopilot flies")
    } else {
        None
    }
}

/// The autopilot fails: α above 15° or its data missing (p. 3-112).
fn fails(s: &Sensed) -> bool {
    s.alpha > AOA_LIMIT || !s.data_ok
}

/// `deg` wrapped to −180…180.
fn wrap(deg: f64) -> f64 {
    (deg + 180.0).rem_euclid(360.0) - 180.0
}

impl F16Autopilot {
    /// The PITCH switch moved to `pos`. Out of A/P OFF it engages both axes, unless a condition holds it off (the
    /// switch drops back, the reason returned) or the autopilot fails (FLCS A/P FAIL; p. 3-112: "If engagement is
    /// attempted with a failure … the autopilot does not engage").
    pub fn set_pitch(&mut self, pos: i8, s: &Sensed, p: &Panel) -> Result<(), &'static str> {
        let pos = pos.clamp(-1, 1);
        if pos != 0 {
            if self.fail || fails(s) {
                self.fail = true;
                self.pitch_sw = 0;
                return Err("FLCS A/P FAIL");
            }
            if let Some(why) = inhibit(s, p) {
                self.pitch_sw = 0;
                return Err(why);
            }
            self.take_roll |= self.pitch_sw == 0;
            self.take_pitch = true;
            self.capture(s, true, self.take_roll);
        }
        self.pitch_sw = pos;
        Ok(())
    }

    /// The ROLL switch moved to `pos`: the new mode takes its reference now.
    pub fn set_roll(&mut self, pos: i8, s: &Sensed) {
        self.roll_sw = pos.clamp(-1, 1);
        self.capture(s, false, true);
    }

    /// FLCS RESET: A/P FAIL clears when its cause has (1 g, α below 15°, the data back), A/P DEGR clears (it comes back
    /// if the autopilot still is not providing its mode).
    pub fn reset(&mut self, s: &Sensed) {
        self.fail &= fails(s);
        self.degr = false;
        (self.t_outside, self.t_roll_max, self.t_pitch_max) = (0.0, 0.0, 0.0);
    }

    fn capture(&mut self, s: &Sensed, pitch: bool, roll: bool) {
        if pitch {
            // ALT HOLD below 2,000 ft/min: the altitude where the jet levels off at the g limit (inferred).
            let a = (if s.vs > 0.0 { 1.0 - G_MIN } else { G_MAX - 1.0 }) * G;
            let lead = if s.vs.abs() < CAPTURE_VS { s.vs * s.vs.abs() / (2.0 * a) } else { 0.0 };
            (self.alt_ref, self.pitch_ref, self.take_pitch) = (s.alt + lead, s.pitch, false);
        }
        if roll {
            (self.bank_ref, self.hdg_ref, self.take_roll) = (s.roll, s.heading, false);
        }
    }

    /// One step of `dt` s: the commands added to the stick's, (g increment, roll rate deg/s). The PITCH switch drops to
    /// A/P OFF when a disengage condition holds.
    pub fn step(&mut self, s: &Sensed, p: &Panel, dt: f64) -> (f64, f64) {
        if self.pitch_sw != 0 && fails(s) {
            self.fail = true;
            self.pitch_sw = 0;
        }
        if self.pitch_sw != 0 && inhibit(s, p).is_some() {
            self.pitch_sw = 0;
        }
        if self.pitch_sw == 0 || p.paddle {
            // Off, or interrupted while the paddle is held: the references are taken anew when it is let go.
            (self.take_pitch, self.take_roll) = (true, true);
            (self.t_outside, self.t_roll_max, self.t_pitch_max) = (0.0, 0.0, 0.0);
            return (0.0, 0.0);
        }
        let (sx, sy) = s.stick;
        let quiet = sx.abs() <= STEER && sy.abs() <= STEER;
        // Stick steering, only in the attitude hold modes (p. 1-136): the axis's reference is dropped while the stick
        // is out and taken where it is let go.
        let steer_pitch = self.pitch_sw == ATT_HOLD && sy.abs() > STEER;
        let steer_roll = self.roll_sw == 0 && sx.abs() > STEER;
        self.take_pitch |= steer_pitch;
        self.take_roll |= steer_roll;
        let (tp, tr) = (self.take_pitch && !steer_pitch, self.take_roll && !steer_roll);
        self.capture(s, tp, tr);

        // Pitch: the g a level path needs at this bank (inferred), plus the mode's correction, within +0.5…+2 g.
        let bank = s.roll.clamp(-ATT_LIMIT, ATT_LIMIT).to_radians();
        let level = s.pitch.to_radians().cos() / bank.cos() - 1.0;
        let (want, err) = if self.pitch_sw == ALT_HOLD {
            let e = self.alt_ref - s.alt;
            let vs_cmd = (K_ALT * e).clamp(-CAPTURE_VS, CAPTURE_VS);
            (level + K_VS * (vs_cmd - s.vs) / G, e.abs())
        } else {
            let e = self.pitch_ref - s.pitch;
            (level + K_PITCH * e.to_radians() * s.speed / G, e.abs())
        };
        let lo_hi = (G_MIN - 1.0, G_MAX - 1.0);
        let dg = if steer_pitch || (self.pitch_sw == ATT_HOLD && s.pitch.abs() > ATT_LIMIT) {
            0.0
        } else {
            want.clamp(lo_hi.0, lo_hi.1)
        };
        let pitch_max = dg <= lo_hi.0 || dg >= lo_hi.1;

        // Roll: ATT HOLD the bank it took; HDG SEL / STRG SEL a bank toward the heading, at most 30°.
        let toward = |h: f64| (K_HDG * wrap(h - s.heading)).clamp(-BANK_MAX, BANK_MAX);
        let bank_cmd = match self.roll_sw {
            HDG_SEL => toward(p.hdg_bug.unwrap_or(self.hdg_ref)),
            STRG_SEL => toward(p.steer.unwrap_or(self.hdg_ref)),
            _ => self.bank_ref,
        };
        let dp = if steer_roll || s.roll.abs() > ATT_LIMIT {
            0.0
        } else {
            (K_BANK * (bank_cmd - s.roll)).clamp(-ROLL_RATE_MAX, ROLL_RATE_MAX)
        };

        // FLCS A/P DEGR (p. 3-112).
        let attitude_modes = self.pitch_sw == ATT_HOLD || self.roll_sw == 0;
        let outside = s.pitch.abs() > ATT_LIMIT || s.roll.abs() > ATT_LIMIT;
        let tick = |t: f64, on: bool| if on { t + dt } else { 0.0 };
        self.t_outside = tick(self.t_outside, attitude_modes && outside && quiet);
        self.t_roll_max = tick(self.t_roll_max, self.roll_sw == 0 && dp.abs() >= ROLL_RATE_MAX);
        self.t_pitch_max = tick(self.t_pitch_max, pitch_max && quiet && err >= self.last_err);
        self.last_err = err;
        self.degr |=
            self.t_outside > DEGR_OUTSIDE_S || self.t_roll_max > DEGR_ROLL_S || self.t_pitch_max > DEGR_PITCH_S;
        (dg, dp)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Level flight at 3,000 m, 300 kt, heading 090°, the data good.
    fn level() -> Sensed {
        Sensed {
            heading: 90.0,
            alt: 3000.0,
            speed: 180.0,
            cas_kt: 300.0,
            alpha: 3.0,
            data_ok: true,
            ..Sensed::default()
        }
    }

    fn engaged(pitch: i8, roll: i8) -> F16Autopilot {
        let mut ap = F16Autopilot::default();
        ap.set_roll(roll, &level());
        assert_eq!(ap.set_pitch(pitch, &level(), &Panel::default()), Ok(()));
        ap
    }

    #[test]
    fn each_condition_of_page_1_135_holds_the_switch_off_and_drops_it() {
        let p0 = Panel::default();
        let cases: [(&str, Sensed, Panel); 7] = [
            ("AIR REFUEL open", level(), Panel { air_refuel: true, ..p0 }),
            ("ALT FLAPS extended", Sensed { alt_flaps: true, ..level() }, p0),
            ("gear handle down", Sensed { gear_handle_down: true, ..level() }, p0),
            ("MPO at OVRD", Sensed { mpo: true, ..level() }, p0),
            ("TRIM/AP DISC at DISC", level(), Panel { disc: true, ..p0 }),
            ("low speed", Sensed { pitch: 60.0, cas_kt: 90.0, ..level() }, p0),
            ("the game's autopilot flies", Sensed { other_ap: true, ..level() }, p0),
        ];
        for (why, s, p) in cases {
            let mut ap = F16Autopilot::default();
            assert_eq!(ap.set_pitch(ALT_HOLD, &s, &p), Err(why));
            assert_eq!(ap.pitch_sw, 0, "{why}: refused");
            let mut ap = engaged(ATT_HOLD, 0);
            assert_eq!(ap.step(&s, &p, 0.1), (0.0, 0.0), "{why}");
            assert_eq!(ap.pitch_sw, 0, "{why}: dropped to A/P OFF");
            assert!(!ap.fail, "{why}: no A/P FAIL");
        }
        // ALT FLAPS only below 400 kt.
        let fast = Sensed { alt_flaps: true, cas_kt: 450.0, ..level() };
        assert_eq!(F16Autopilot::default().set_pitch(ALT_HOLD, &fast, &p0), Ok(()));
        // The low speed tone: not at 45° and 150 kt, nor with the gear down (the gear rule drops it anyway).
        assert!(!low_speed_tone(&Sensed { pitch: 45.0, cas_kt: 150.0, ..level() }));
        assert!(low_speed_tone(&Sensed { pitch: 90.0, cas_kt: 180.0, ..level() }));
    }

    #[test]
    fn aoa_or_missing_data_fails_it_until_flcs_reset() {
        let mut ap = engaged(ALT_HOLD, HDG_SEL);
        let high = Sensed { alpha: 16.0, ..level() };
        ap.step(&high, &Panel::default(), 0.1);
        assert!(ap.fail && ap.pitch_sw == 0, "α 16°: A/P FAIL, disengaged");
        assert_eq!(ap.set_pitch(ALT_HOLD, &level(), &Panel::default()), Err("FLCS A/P FAIL"), "no engagement");
        ap.reset(&high);
        assert!(ap.fail, "a reset above 15° leaves it");
        ap.reset(&level());
        assert!(!ap.fail);
        assert_eq!(ap.set_pitch(ALT_HOLD, &level(), &Panel::default()), Ok(()));
        // Engaging without the data (an in-flight alignment, a damaged autopilot): A/P FAIL.
        let mut ap = F16Autopilot::default();
        assert!(ap.set_pitch(ATT_HOLD, &Sensed { data_ok: false, ..level() }, &Panel::default()).is_err());
        assert!(ap.fail && ap.pitch_sw == 0);
    }

    #[test]
    fn alt_hold_commands_toward_its_altitude_within_its_g() {
        let mut ap = engaged(ALT_HOLD, 0);
        let p = Panel::default();
        let (dg, dp) = ap.step(&level(), &p, 0.02);
        assert!(dg.abs() < 1e-9 && dp.abs() < 1e-9, "on its altitude: nothing ({dg}, {dp})");
        let (dg, _) = ap.step(&Sensed { alt: 2900.0, ..level() }, &p, 0.02);
        assert!(dg > 0.0 && dg <= 1.0, "100 m low: a pull within +2 g ({dg})");
        let (dg, _) = ap.step(&Sensed { alt: 4000.0, vs: 50.0, ..level() }, &p, 0.02);
        assert!((dg + 0.5).abs() < 1e-9, "far above and climbing: +0.5 g ({dg})");
        // Engaged in a 1,500 ft/min climb: the altitude ahead where 0.5 g levels it (7.6²/(2·4.9) ≈ 5.9 m).
        let mut ap = F16Autopilot::default();
        let climb = Sensed { vs: 7.62, ..level() };
        ap.set_pitch(ALT_HOLD, &climb, &p).unwrap();
        assert!((ap.alt_ref - 3005.9).abs() < 0.2, "{}", ap.alt_ref);
        // Above 2,000 ft/min: the altitude it engaged at.
        let mut ap = F16Autopilot::default();
        ap.set_pitch(ALT_HOLD, &Sensed { vs: 15.0, ..level() }, &p).unwrap();
        assert_eq!(ap.alt_ref, 3000.0);
        // The g a 60° bank needs to stay level: +1 g, the most it adds.
        let (dg, _) = engaged(ALT_HOLD, 0).step(&Sensed { roll: 60.0, ..level() }, &p, 0.02);
        assert!((dg - 1.0).abs() < 1e-6, "{dg}");
    }

    #[test]
    fn att_hold_keeps_pitch_and_bank_and_lets_the_stick_steer() {
        let p = Panel::default();
        let mut ap = F16Autopilot::default();
        let s = Sensed { pitch: 5.0, roll: 20.0, ..level() };
        ap.set_roll(0, &s);
        ap.set_pitch(ATT_HOLD, &s, &p).unwrap();
        let (dg, dp) = ap.step(&Sensed { pitch: 3.0, roll: 25.0, ..level() }, &p, 0.02);
        assert!(dg > 0.0 && dp < 0.0, "nose low, banked over: pull and roll back ({dg}, {dp})");
        // Stick steering: the stick out, no command on that axis; let go at 10° pitch, that is the new reference.
        let steer = Sensed { pitch: 10.0, stick: (0.0, 0.5), ..s };
        assert_eq!(ap.step(&steer, &p, 0.02).0, 0.0);
        let (dg, _) = ap.step(&Sensed { stick: (0.0, 0.0), ..steer }, &p, 0.02);
        assert!(dg.abs() < 0.05, "held at its new 10° ({dg})");
        assert_eq!(ap.pitch_ref, 10.0);
        // Beyond ±60° it does not function; the switch stays.
        let (dg, dp) = ap.step(&Sensed { pitch: 70.0, roll: 70.0, ..s }, &p, 0.02);
        assert!(dg == 0.0 && dp == 0.0 && ap.pitch_sw == ATT_HOLD);
    }

    #[test]
    fn hdg_sel_and_strg_sel_bank_at_most_30_degrees_at_20_deg_per_s() {
        let mut ap = engaged(ALT_HOLD, HDG_SEL);
        let p = Panel { hdg_bug: Some(180.0), steer: Some(0.0), ..Panel::default() };
        let (_, dp) = ap.step(&level(), &p, 0.02);
        assert_eq!(dp, 20.0, "bug 90° right: rolls right at 20 deg/s");
        let (_, dp) = ap.step(&Sensed { roll: 30.0, ..level() }, &p, 0.02);
        assert!(dp.abs() < 1e-9, "held at 30° of bank ({dp})");
        ap.set_roll(STRG_SEL, &level());
        let (_, dp) = ap.step(&level(), &p, 0.02);
        assert_eq!(dp, -20.0, "the steerpoint to the north: rolls left");
        // HDG SEL with no marker set: the heading it engaged on.
        let mut ap = engaged(ALT_HOLD, HDG_SEL);
        let (_, dp) = ap.step(&Sensed { heading: 95.0, ..level() }, &Panel::default(), 0.02);
        assert!(dp < 0.0, "{dp}");
        // The stick does not steer these modes: its roll is added in the control laws.
        let (_, dp) = ap.step(&Sensed { heading: 95.0, stick: (0.5, 0.0), ..level() }, &Panel::default(), 0.02);
        assert!(dp < 0.0);
    }

    #[test]
    fn the_paddle_interrupts_and_takes_a_new_altitude() {
        let mut ap = engaged(ALT_HOLD, 0);
        let p = Panel { paddle: true, ..Panel::default() };
        assert_eq!(ap.step(&Sensed { alt: 3300.0, ..level() }, &p, 0.02), (0.0, 0.0));
        assert_eq!(ap.pitch_sw, ALT_HOLD, "interrupted, still engaged");
        let (dg, _) = ap.step(&Sensed { alt: 3300.0, ..level() }, &Panel::default(), 0.02);
        assert!(dg.abs() < 1e-9 && ap.alt_ref == 3300.0, "let go at 3,300 m: holds it");
    }

    #[test]
    fn degr_after_its_times_and_cleared_by_a_reset() {
        let p = Panel::default();
        // Outside the attitude limits with no stick input for 12 s.
        let mut ap = engaged(ATT_HOLD, 0);
        let out = Sensed { roll: 70.0, ..level() };
        for _ in 0..110 {
            ap.step(&out, &p, 0.1);
        }
        assert!(!ap.degr, "11 s: not yet");
        for _ in 0..15 {
            ap.step(&out, &p, 0.1);
        }
        assert!(ap.degr && ap.pitch_sw == ATT_HOLD, "after 12 s: A/P DEGR, still engaged");
        ap.reset(&level());
        assert!(!ap.degr);
        // The pitch command at its authority, not correcting, for 5 s.
        let mut ap = engaged(ALT_HOLD, HDG_SEL);
        let low = Sensed { alt: 2000.0, vs: -20.0, ..level() };
        for _ in 0..55 {
            ap.step(&low, &p, 0.1);
        }
        assert!(ap.degr, "5 s at +2 g, still 1,000 m low and sinking");
        // Roll ATT HOLD with its roll command at its authority for 12 s.
        let mut ap = engaged(ATT_HOLD, 0);
        ap.bank_ref = 50.0;
        for _ in 0..125 {
            ap.step(&level(), &p, 0.1);
        }
        assert!(ap.degr);
    }
}
