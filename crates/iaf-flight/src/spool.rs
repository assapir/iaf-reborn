//! Better physics `engine_spool` (docs/flight-model.md §10.2): the thrust follows each real engine's
//! spool-up instead of the throttle at once. The original's thrust follows the throttle at the next aero
//! update (`FUN_005b4120`), only its RPM gauge ramps (15 %/s) and its afterburner waits for that ramp
//! (`FUN_0059f7d0`, §15.8).

/// One engine's transient times (seconds, sea-level static; sources in docs/flight-model.md §10.2).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Spool {
    /// Idle → military: the core spools from idle (RPM 60 %) to military (100 %).
    pub idle_mil: f32,
    /// Military → idle.
    pub mil_idle: f32,
    /// Afterburner light-off once the core is at military.
    pub ab_light: f32,
    /// Light-off → maximum afterburner (the zones fill; minimum afterburner at half this).
    pub ab_fill: f32,
}

const fn spool(idle_mil: f32, mil_idle: f32, ab_light: f32, ab_fill: f32) -> Spool {
    Spool { idle_mil, mil_idle, ab_light, ab_fill }
}

/// The engine of each flyable type, by type code (`Params::type_code`). Types without a row keep the
/// original's response.
pub const ENGINES: &[(u32, Spool)] = &[
    // F-16D Block 30/40, F110-GE-100: no public figure; the F100's (inferred, open).
    (100, spool(3.0, 5.0, 0.5, 2.0)),
    // F-15 Baz, F100-PW-220: idle → intermediate 3 s (NASA TM-4320); afterburner initiation at military, then one
    // second per segment hold (NASA TM-85902).
    (110, spool(3.0, 5.0, 0.5, 2.0)),
    // F-4E Kurnass and Kurnass 2000 (both fly the F-4 type, code 120), J79-GE-17: idle → military 5 s at best
    // (test-cell chart, quoted); afterburner times open.
    (120, spool(5.0, 5.0, 1.0, 1.5)),
    // Kfir C7, J79-J1E (licence J79-GE-17): the -17's.
    (130, spool(5.0, 5.0, 1.0, 1.5)),
    // Lavi, PW1120 (the F100's core and control): the F100's (inferred).
    (140, spool(3.0, 5.0, 0.5, 2.0)),
    // MiG-23ML, R-35-300: no public figure; the 5 s idle → maximum limit of the norms (open).
    (160, spool(5.0, 5.0, 1.0, 1.5)),
    // MiG-29 9.12, RD-33: idle → maximum 3–4 s, maximum → full afterburner 2–3 s, idle → full 4–5 s.
    (180, spool(3.0, 5.0, 0.8, 1.2)),
    // Mirage IIIC, Atar 9C: no public figure; the 5 s limit (open).
    (190, spool(5.0, 5.0, 1.0, 1.5)),
    // F-35I Adir, F135-PW-100: flight idle → maximum power about 6 s (Pratt & Whitney); the split inferred.
    (1000, spool(4.0, 5.0, 0.8, 1.2)),
];

pub fn engine(type_code: u32) -> Option<Spool> {
    ENGINES.iter().find(|(c, _)| *c == type_code).map(|(_, s)| *s)
}

/// The rate's offset: the core's rate is ∝ (x + A), x = 0 at idle, 1 at military, so it spools 11× faster near
/// military than at idle (inferred: the compressor's surplus power grows with its speed).
const A: f32 = 0.1;

/// The core's spool state `x` (0 idle … 1 military): a closed-form channel like the original's ramps,
/// `x + A = (x0 + A)·e^(±c·τ)` toward its target.
#[derive(Debug, Clone, Copy, Default)]
pub struct Core {
    t0: f64,
    x0: f32,
    target: f32,
}

impl Core {
    /// `1/c` = idle_mil / ln((1 + A)/A).
    fn rate(s: &Spool, up: bool) -> f32 {
        ((1.0 + A) / A).ln() / if up { s.idle_mil } else { s.mil_idle }.max(1e-3)
    }

    pub fn sample(&self, s: &Spool, t: f64) -> f32 {
        let tau = (t - self.t0).max(0.0) as f32;
        let up = self.target >= self.x0;
        let x = (self.x0 + A) * (if up { 1.0 } else { -1.0 } * Self::rate(s, up) * tau).exp() - A;
        if up { x.min(self.target) } else { x.max(self.target) }
    }

    /// Re-bases at `t` toward a new target.
    pub fn set(&mut self, s: &Spool, t: f64, target: f32) {
        *self = Core { t0: t, x0: self.sample(s, t), target: target.clamp(0.0, 1.0) };
    }

    /// Jumps to `x`.
    pub fn reset(&mut self, t: f64, x: f32) {
        let x = x.clamp(0.0, 1.0);
        *self = Core { t0: t, x0: x, target: x };
    }

    /// Seconds from `t` until the core is at military (spooling up from its value at `t`).
    pub fn to_military(&self, s: &Spool, t: f64) -> f32 {
        ((1.0 + A) / (self.sample(s, t) + A)).ln() / Self::rate(s, true)
    }
}
