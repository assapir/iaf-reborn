//! The engine's ground start (item E3b, iaf-2026/docs/training.md §7): one "start engine" command runs the real
//! sequence's steps and timings: the starter (the F-16's jet fuel starter, the F-35's integrated power package)
//! cranks the engine to the light-off RPM, the throttle goes to idle, the fuel lights, the engine accelerates to idle;
//! the main generator comes on line on the way and the displays and the avionics come up after it. Sources and the
//! inferred figures: training.md §7.

/// The 6-DoF's idle RPM, % (its gauge's line, iaf-2026/docs/flight-model.md §9.7).
pub const IDLE_RPM: f64 = 60.0;

/// One jet's start sequence.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StartSpec {
    /// The starter's name ("JFS", "IPP").
    pub starter: &'static str,
    /// From the command to the starter cranking the engine, s.
    pub starter_s: f64,
    /// The starter's cranking rate, % RPM per s, up to `lightoff_rpm`.
    pub crank_rate: f64,
    /// The throttle goes to idle (the fuel on) at this RPM, %.
    pub lightoff_rpm: f64,
    /// From the fuel on to the light-off, s.
    pub lightoff_s: f64,
    /// From the light-off to idle, s.
    pub accel_s: f64,
    /// The main generator comes on line at this RPM, % (the engine self-sustaining, the starter off).
    pub generator_rpm: f64,
    /// The displays take their power from the starter (the F-35's IPP) rather than the main generator.
    pub displays_on_starter: bool,
    /// The displays' warm-up after their power, s.
    pub warmup_s: f64,
    /// The avionics report ready this long after the command at the earliest (the F-35's self test), s.
    pub ready_s: f64,
}

/// The F-16's (the Sufa, the Barak; the F-15I's inferred the same): the JFS cranks the engine to 20 % in 15 s, the
/// throttle to idle at 20 % (a T.O. checklist), light-off 5 s later, idle 15 s after it, the main
/// generator at 52 % (the engine self-sustaining, the JFS off), the displays 3 s after it. The times are inferred.
pub const JFS: StartSpec = StartSpec {
    starter: "JFS",
    starter_s: 0.0,
    crank_rate: 20.0 / 15.0,
    lightoff_rpm: 20.0,
    lightoff_s: 5.0,
    accel_s: 15.0,
    generator_rpm: 52.0,
    displays_on_starter: false,
    warmup_s: 3.0,
    ready_s: 0.0,
};

/// The F-35I's: battery, the IPP (10 s to run, inferred), the engine start button; the displays on the IPP's power;
/// the aircraft declares itself ready 90 s after the start (AIR International, 2012). The engine's own steps are the
/// F-16's (inferred: none published).
pub const IPP: StartSpec =
    StartSpec { starter: "IPP", starter_s: 10.0, displays_on_starter: true, ready_s: 90.0, ..JFS };

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Phase {
    /// Cold: no power.
    #[default]
    Off,
    /// The starter spools up.
    Starter,
    /// The starter cranks the engine.
    Crank,
    /// The fuel is on, waiting for the light-off.
    LightOff,
    /// Lit, accelerating to idle.
    Accel,
    /// At idle or above: the engine runs.
    Running,
}

impl Phase {
    pub fn name(self) -> &'static str {
        match self {
            Phase::Off => "off",
            Phase::Starter => "starter",
            Phase::Crank => "crank",
            Phase::LightOff => "light-off",
            Phase::Accel => "accel",
            Phase::Running => "running",
        }
    }
}

/// A start in progress (or none): the phase, the RPM it gives, when the displays got power.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Start {
    pub phase: Phase,
    /// Since the command, and since the phase began, s.
    t: f64,
    phase_t: f64,
    /// The engine's RPM while it starts, %.
    pub rpm: f64,
    /// When the displays got their power (s since the command).
    displays_at: Option<f64>,
    /// The command was given (the battery is on).
    commanded: bool,
}

impl Start {
    /// An engine already running (an airborne or runway start): every system up.
    pub fn running() -> Start {
        // Its clock long past every step of the sequence.
        Start {
            phase: Phase::Running,
            t: f64::INFINITY,
            rpm: IDLE_RPM,
            displays_at: Some(0.0),
            commanded: true,
            ..Start::default()
        }
    }

    /// The "start engine" command: a stopped engine begins its sequence; otherwise nothing.
    pub fn begin(&mut self) {
        if self.phase == Phase::Off {
            *self = Start { phase: Phase::Starter, commanded: true, ..Start::default() };
        }
    }

    /// The engine stopped: no RPM, the displays and the avionics down, the battery on (a new command restarts).
    pub fn shutdown(&mut self) {
        *self = Start { commanded: true, ..Start::default() };
    }

    /// Advances `dt` s; true on the step the sequence reaches idle.
    pub fn step(&mut self, s: &StartSpec, dt: f64) -> bool {
        if dt.is_nan() || dt <= 0.0 || self.phase == Phase::Off {
            return false;
        }
        let was = self.phase;
        self.t += dt;
        self.phase_t += dt;
        match self.phase {
            Phase::Starter if self.phase_t >= s.starter_s => self.next(Phase::Crank),
            Phase::Crank => {
                self.rpm = (self.rpm + s.crank_rate * dt).min(s.lightoff_rpm);
                if self.rpm >= s.lightoff_rpm {
                    self.next(Phase::LightOff);
                }
            }
            Phase::LightOff if self.phase_t >= s.lightoff_s => self.next(Phase::Accel),
            Phase::Accel => {
                let k = (self.phase_t / s.accel_s).min(1.0);
                self.rpm = s.lightoff_rpm + (IDLE_RPM - s.lightoff_rpm) * k;
                if k >= 1.0 {
                    self.next(Phase::Running);
                }
            }
            _ => {}
        }
        let powered = if s.displays_on_starter { self.phase != Phase::Starter } else { self.rpm >= s.generator_rpm };
        if self.displays_at.is_none() && (powered || self.phase == Phase::Running) {
            self.displays_at = Some(self.t);
        }
        was != Phase::Running && self.phase == Phase::Running
    }

    fn next(&mut self, p: Phase) {
        self.phase = p;
        self.phase_t = 0.0;
    }

    /// The electrical power: 0 none (cold), 1 the battery (lamps, engine gauges), 2 the displays up.
    pub fn power(&self, s: &StartSpec) -> u8 {
        match self.displays_at {
            Some(at) if self.t >= at + s.warmup_s => 2,
            _ if self.commanded => 1,
            _ => 0,
        }
    }

    /// The avionics up: the displays up and, for a jet with a self test, its time passed.
    pub fn avionics(&self, s: &StartSpec) -> bool {
        self.power(s) == 2 && self.t >= s.ready_s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Runs a start at 30 Hz; (time to idle, time to the displays, time to the avionics), s.
    fn run(s: &StartSpec) -> (f64, f64, f64) {
        let mut st = Start::default();
        assert_eq!(st.power(s), 0);
        st.begin();
        let (mut idle, mut disp, mut av, mut t) = (None, None, None, 0.0);
        while t < 200.0 {
            st.step(s, 1.0 / 30.0);
            t += 1.0 / 30.0;
            idle = idle.or((st.phase == Phase::Running).then_some(t));
            disp = disp.or((st.power(s) == 2).then_some(t));
            av = av.or(st.avionics(s).then_some(t));
        }
        (idle.unwrap(), disp.unwrap(), av.unwrap())
    }

    #[test]
    fn f16_start_reaches_idle_with_the_displays_on_the_generator() {
        let (idle, disp, av) = run(&JFS);
        assert!((idle - 35.0).abs() < 0.2, "idle at {idle}");
        // The generator at 52 %: 15 + 5 + 12 s, plus the 3 s warm-up.
        assert!((disp - 35.0).abs() < 0.2, "displays at {disp}");
        assert_eq!(disp, av);
    }

    #[test]
    fn f35_displays_come_with_the_ipp_and_the_avionics_after_the_self_test() {
        let (idle, disp, av) = run(&IPP);
        assert!((idle - 45.0).abs() < 0.2, "idle at {idle}");
        assert!((disp - 13.0).abs() < 0.2, "displays at {disp}");
        assert!((av - 90.0).abs() < 0.1, "avionics at {av}");
    }

    #[test]
    fn a_running_engine_has_everything_up_and_ignores_the_command() {
        let mut st = Start::running();
        st.begin();
        st.step(&IPP, 0.1);
        assert_eq!((st.phase, st.power(&IPP), st.avionics(&IPP)), (Phase::Running, 2, true));
    }
}
