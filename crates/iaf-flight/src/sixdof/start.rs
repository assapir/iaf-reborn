//! The engine's ground start (item E3b, iaf-2026/docs/training.md §7): one "start engine" command runs the real
//! sequence's steps and timings: the starter (the F-16's jet fuel starter, the F-35's integrated power package)
//! cranks the engine to the light-off RPM, the throttle goes to idle, the fuel lights, the engine accelerates to idle;
//! the main generator comes on line on the way and the displays and the avionics come up after it. Sources and the
//! inferred figures: training.md §7.
//!
//! The start-up mission flies the same sequence step by step by keys (`Start::press`, training.md §7.1): the F-16's
//! checklist (main power, JFS, throttle to idle at 20 %, avionics power after the generators, INS stored-heading
//! alignment, canopy) and the F-35I's (battery, IPP, engine start, canopy). A step out of order has the real
//! consequence (no power for the starter, a hot start that stops the engine, a switch that does nothing) and is
//! returned as a fault for the debrief.

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
    /// By keys: the engine start runs on its own once commanded (the F-35's): no throttle step, no avionics switches.
    pub fadec: bool,
    /// By keys: the INS stored-heading alignment, s (0: none to fly).
    pub ins_align_s: f64,
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
    fadec: false,
    ins_align_s: 90.0,
};

/// The F-35I's: battery, the IPP (10 s to run, inferred), the engine start button; the displays on the IPP's power;
/// the aircraft declares itself ready 90 s after the start (AIR International, 2012). The engine's own steps are the
/// F-16's (inferred: none published).
pub const IPP: StartSpec = StartSpec {
    starter: "IPP",
    starter_s: 10.0,
    displays_on_starter: true,
    ready_s: 90.0,
    fadec: true,
    ins_align_s: 0.0,
    ..JFS
};

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
    /// Flown by keys (`press`): the steps wait for their keys.
    manual: bool,
    /// By keys: the fuel on (the F-16's throttle to idle; the F-35's engine start).
    fuel_on: bool,
    /// By keys: the F-16's avionics power switched on, and the INS alignment's start (s since the command).
    avionics_at: Option<f64>,
    ins_at: Option<f64>,
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
            // By keys the F-35's IPP runs until the engine start, the F-16's JFS holds at light-off for the throttle.
            Phase::Starter if self.phase_t >= s.starter_s && !(self.manual && s.fadec && !self.fuel_on) => {
                self.next(Phase::Crank)
            }
            Phase::Crank => {
                self.rpm = (self.rpm + s.crank_rate * dt).min(s.lightoff_rpm);
                if self.rpm >= s.lightoff_rpm && (!self.manual || self.fuel_on) {
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

    /// The electrical power: 0 none (cold), 1 the battery (lamps, engine gauges), 2 the displays up (by keys, the
    /// F-16's also after its avionics power switch).
    pub fn power(&self, s: &StartSpec) -> u8 {
        let up = match self.displays_at {
            Some(at) if self.manual && !s.fadec => self.avionics_at.map(|a| a.max(at)),
            d => d,
        };
        match up {
            Some(at) if self.t >= at + s.warmup_s => 2,
            _ if self.commanded => 1,
            _ => 0,
        }
    }

    /// The avionics up: the displays up and, for a jet with a self test, its time passed.
    pub fn avionics(&self, s: &StartSpec) -> bool {
        let aligned = !self.manual || s.ins_align_s <= 0.0 || self.ins_at.is_some_and(|a| self.t >= a + s.ins_align_s);
        self.power(s) == 2 && self.t >= s.ready_s && aligned
    }

    /// One checklist step by its key (training.md §7.1): "main_power", "starter", "engine", "avionics", "ins",
    /// "canopy". Err: the fault of a step out of order, with its consequence applied (the switch does nothing; a hot
    /// start stops the engine).
    pub fn press(&mut self, s: &StartSpec, step: &str) -> Result<(), &'static str> {
        if self.phase == Phase::Running && !self.manual {
            return Ok(()); // an engine already running (an airborne start, Ctrl+E)
        }
        match step {
            "main_power" => {
                if !self.commanded {
                    *self = Start { commanded: true, manual: true, ..Start::default() };
                }
            }
            "starter" if !self.commanded => return Err("no_power"),
            "starter" => {
                if self.phase == Phase::Off {
                    self.phase = Phase::Starter;
                    self.phase_t = 0.0;
                }
            }
            "engine" if s.fadec => match self.phase {
                Phase::Off => return Err("no_ipp"),
                Phase::Starter if self.phase_t < s.starter_s => return Err("ipp_not_ready"),
                _ => self.fuel_on = true,
            },
            "engine" => match self.phase {
                Phase::Off => return Err("no_rotation"),
                // Fuel below the light-off RPM: a hot start; the engine is shut down (the battery stays on).
                Phase::Starter | Phase::Crank if self.rpm < s.lightoff_rpm => {
                    *self = Start { commanded: true, manual: true, ..Start::default() };
                    return Err("hot_start");
                }
                _ => self.fuel_on = true,
            },
            "avionics" if self.displays_at.is_none() => return Err("avionics_early"),
            "avionics" => self.avionics_at = self.avionics_at.or(Some(self.t)),
            "ins" if self.avionics_at.is_none() => return Err("ins_no_power"),
            "ins" => self.ins_at = self.ins_at.or(Some(self.t)),
            _ => {}
        }
        Ok(())
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

    /// Presses `steps` at 30 Hz, each `gap` s after the last; the faults, and the time the avionics came up.
    fn keys(s: &StartSpec, steps: &[(&str, f64)]) -> (Vec<&'static str>, Option<f64>) {
        let (mut st, mut faults, mut t, mut av) = (Start::default(), vec![], 0.0, None);
        for (step, gap) in steps {
            let until = t + gap;
            while t < until {
                st.step(s, 1.0 / 30.0);
                t += 1.0 / 30.0;
            }
            if let Err(f) = st.press(s, step) {
                faults.push(f);
            }
        }
        while t < 300.0 {
            st.step(s, 1.0 / 30.0);
            t += 1.0 / 30.0;
            av = av.or(st.avionics(s).then_some(t));
        }
        (faults, av)
    }

    #[test]
    fn the_f16_checklist_in_order_brings_everything_up() {
        let order = [("main_power", 1.0), ("starter", 2.0), ("engine", 16.0), ("avionics", 25.0), ("ins", 2.0)];
        let (faults, av) = keys(&JFS, &order);
        assert!(faults.is_empty(), "{faults:?}");
        // The INS aligned 90 s after its knob (at 46 s).
        assert!((av.unwrap() - 136.0).abs() < 0.2, "{av:?}");
    }

    #[test]
    fn the_f16_checklist_out_of_order_has_its_consequence() {
        // The JFS without main power: nothing runs.
        assert_eq!(keys(&JFS, &[("starter", 1.0)]), (vec!["no_power"], None));
        // The throttle to idle at 5 % RPM: a hot start, the engine stopped.
        let mut st = Start::default();
        st.press(&JFS, "main_power").unwrap();
        st.press(&JFS, "starter").unwrap();
        for _ in 0..100 {
            st.step(&JFS, 0.05);
        }
        assert_eq!(st.press(&JFS, "engine"), Err("hot_start"));
        assert_eq!((st.phase, st.rpm, st.power(&JFS)), (Phase::Off, 0.0, 1));
        // The avionics before the generators, the INS before the avionics: the switch does nothing.
        let early = [("main_power", 1.0), ("avionics", 1.0), ("ins", 1.0), ("starter", 1.0), ("engine", 16.0)];
        assert_eq!(keys(&JFS, &early), (vec!["avionics_early", "ins_no_power"], None));
        // The throttle never to idle: the JFS holds the engine at 20 %, no light-off.
        let (_, av) = keys(&JFS, &[("main_power", 1.0), ("starter", 1.0)]);
        assert_eq!(av, None);
    }

    #[test]
    fn the_f35_ipp_sequence() {
        let (faults, av) = keys(&IPP, &[("main_power", 1.0), ("starter", 1.0), ("engine", 11.0)]);
        assert!(faults.is_empty(), "{faults:?}");
        assert!((av.unwrap() - 92.0).abs() < 0.2, "the self test 90 s after the battery: {av:?}");
        assert_eq!(keys(&IPP, &[("main_power", 1.0), ("engine", 1.0)]).0, ["no_ipp"]);
        assert_eq!(keys(&IPP, &[("main_power", 1.0), ("starter", 1.0), ("engine", 2.0)]).0, ["ipp_not_ready"]);
    }

    #[test]
    fn a_running_engine_has_everything_up_and_ignores_the_command() {
        let mut st = Start::running();
        st.begin();
        st.step(&IPP, 0.1);
        assert_eq!((st.phase, st.power(&IPP), st.avionics(&IPP)), (Phase::Running, 2, true));
    }
}
