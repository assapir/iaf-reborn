//! The engine's ground start (item E3b, modern-iaf/docs/training.md §7): one "start engine" command runs the real
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
//!
//! Each step is a switch with a position, settable both ways at any time (`Start::press` on, `Start::release` off;
//! the switches audit's M2, modern-iaf/docs/cockpit.md §5.2): main power off darkens everything, the starter off stops
//! a crank, the avionics off darken the displays (a warm-up again when back on) and lose the INS alignment, the INS
//! knob off loses it too. `Start::on` is the switch's position, the one source the checklist and the 3D cockpit read.

/// The 6-DoF's idle RPM, % (its gauge's line, modern-iaf/docs/flight-model.md §9.7).
pub const IDLE_RPM: f64 = 60.0;

/// The shutdown (training.md §7.2): with the fuel cut the core winds down as `e^(-t/RUNDOWN_TAU)` (s) and stops below
/// `STOP_RPM` (%): from idle 61 s, the generators off line (52 %) after 2 s, below the starter's 20 % after 16 s.
/// Inferred: no public run-down figure; "about a minute" to a stop.
pub const RUNDOWN_TAU: f64 = 15.0;
pub const STOP_RPM: f64 = 1.0;

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
    /// The fuel cut (the throttle to OFF): the core winds down to a stop.
    Rundown,
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
            Phase::Rundown => "rundown",
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
    /// The command was given: the MAIN PWR switch (the F-35I's BATT) on.
    commanded: bool,
    /// Flown by keys (`press`): the steps wait for their keys.
    manual: bool,
    /// By keys: the fuel on (the F-16's throttle to idle; the F-35's engine start).
    fuel_on: bool,
    /// By keys: the F-16's avionics power switched on, and the INS alignment's start (s since the command).
    avionics_at: Option<f64>,
    ins_at: Option<f64>,
    /// The switches without a timing of their own: the starter (the JFS switch, the IPP; springs back to OFF once the
    /// engine sustains itself), the avionics power, the INS knob, the canopy closed.
    starter_on: bool,
    avionics_on: bool,
    ins_on: bool,
    canopy_closed: bool,
}

impl Start {
    /// An engine already running (an airborne or runway start): every system up.
    pub fn running() -> Start {
        // Its clock long past every step of the sequence.
        Start { phase: Phase::Running, t: 1.0e6, rpm: IDLE_RPM, displays_at: Some(0.0), ..Start::switched_on() }
    }

    /// Every switch on, the INS aligned (the "start engine" command flies the whole checklist).
    fn switched_on() -> Start {
        Start {
            commanded: true,
            fuel_on: true,
            avionics_at: Some(0.0),
            ins_at: Some(-1.0e6),
            avionics_on: true,
            ins_on: true,
            canopy_closed: true,
            ..Start::default()
        }
    }

    /// The "start engine" command: a stopped engine begins its sequence (one winding down once below the starter's
    /// RPM, [`Start::starter_engages`]); otherwise nothing.
    pub fn begin(&mut self, s: &StartSpec) {
        if self.starter_engages(s) {
            *self = Start {
                phase: Phase::Starter,
                rpm: self.rpm,
                fuel_on: false,
                starter_on: true,
                ..Start::switched_on()
            };
        }
    }

    /// The starter can turn the engine: stopped, or winding down below the light-off RPM (inferred: the starter
    /// cranks up to that RPM).
    fn starter_engages(&self, s: &StartSpec) -> bool {
        self.phase == Phase::Off || (self.phase == Phase::Rundown && self.rpm < s.lightoff_rpm)
    }

    /// The throttle to OFF (the fuel cut) at the engine's RPM `rpm` (%): an engine lit or running winds down
    /// ([`RUNDOWN_TAU`]); the fault: "shutdown" for a running engine, "no_start" for one still starting. A cold or
    /// cranking engine has no fuel to cut (the throttle's next move from OFF is the idle step again).
    pub fn cut_off(&mut self, rpm: f64) -> Result<(), &'static str> {
        self.fuel_on = false;
        let fault = match self.phase {
            Phase::Running => "shutdown",
            Phase::LightOff | Phase::Accel => "no_start",
            _ => return Ok(()),
        };
        self.rpm = rpm;
        self.next(Phase::Rundown);
        Err(fault)
    }

    /// The engine stopped: no RPM, the displays and the avionics down, the switches as they are (a new command
    /// restarts).
    pub fn shutdown(&mut self) {
        self.next(Phase::Off);
        self.rpm = 0.0;
        self.fuel_on = false;
        self.starter_on = false;
        self.displays_at = None;
        self.ins_at = None;
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
            Phase::Rundown => {
                self.rpm *= (-dt / RUNDOWN_TAU).exp();
                // The generators off line: the displays and the avionics down, the INS to align again (inferred).
                if self.rpm < s.generator_rpm {
                    self.displays_at = None;
                    self.ins_at = None;
                }
                if self.rpm < STOP_RPM {
                    self.rpm = 0.0;
                    self.next(Phase::Off);
                }
            }
            Phase::Accel => {
                let k = (self.phase_t / s.accel_s).min(1.0);
                self.rpm = s.lightoff_rpm + (IDLE_RPM - s.lightoff_rpm) * k;
                if k >= 1.0 {
                    self.next(Phase::Running);
                }
            }
            _ => {}
        }
        // The starter's switch springs back to OFF once the engine sustains itself (the JFS cuts out at 50–54 %).
        if self.rpm >= s.generator_rpm {
            self.starter_on = false;
        }
        let powered = self.commanded
            && self.phase != Phase::Rundown
            && self.phase != Phase::Off
            && if s.displays_on_starter { self.phase != Phase::Starter } else { self.rpm >= s.generator_rpm };
        if self.displays_at.is_none() && (powered || (self.commanded && self.phase == Phase::Running)) {
            self.displays_at = Some(self.t);
        }
        // The INS knob left on through a power loss aligns again once the avionics have power (inferred).
        if self.ins_on && self.ins_at.is_none() && self.commanded && self.displays_at.is_some() {
            self.ins_at = self.avionics_at.map(|_| self.t);
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
        if !self.commanded {
            return 0;
        }
        let up = match self.displays_at {
            Some(at) if !s.fadec => self.avionics_at.map(|a| a.max(at)),
            d => d,
        };
        match up {
            Some(at) if self.t >= at + s.warmup_s => 2,
            _ => 1,
        }
    }

    /// The avionics up: the displays up and, for a jet with a self test, its time passed.
    pub fn avionics(&self, s: &StartSpec) -> bool {
        let aligned = s.ins_align_s <= 0.0 || self.ins_at.is_some_and(|a| self.t >= a + s.ins_align_s);
        self.power(s) == 2 && self.t >= s.ready_s && aligned
    }

    /// One checklist step by its key (training.md §7.1): "main_power", "starter", "engine", "avionics", "ins",
    /// "canopy". Err: the fault of a step out of order, with its consequence applied (the switch does nothing; a hot
    /// start stops the engine).
    pub fn press(&mut self, s: &StartSpec, step: &str) -> Result<(), &'static str> {
        match step {
            "main_power" => {
                if !self.commanded && self.phase == Phase::Off {
                    self.manual = true;
                }
                self.commanded = true;
            }
            "starter" if !self.commanded => return Err("no_power"),
            // Winding down above the light-off RPM: the starter waits, the key does nothing.
            "starter" if self.phase == Phase::Rundown && !self.starter_engages(s) => return Err("starter_high"),
            "starter" => {
                if self.starter_engages(s) {
                    self.next(Phase::Starter);
                }
                // Turned with the engine sustaining itself it springs back at once (`step`).
                self.starter_on = true;
            }
            "engine" if s.fadec => match self.phase {
                Phase::Off | Phase::Rundown => return Err("no_ipp"),
                Phase::Starter if self.phase_t < s.starter_s => return Err("ipp_not_ready"),
                _ => self.fuel_on = true,
            },
            "engine" => match self.phase {
                Phase::Off | Phase::Rundown => return Err("no_rotation"),
                // Fuel below the light-off RPM: a hot start; the engine is shut down (the battery stays on).
                Phase::Starter | Phase::Crank if self.rpm < s.lightoff_rpm => {
                    self.shutdown();
                    return Err("hot_start");
                }
                _ => self.fuel_on = true,
            },
            "avionics" if self.displays_at.is_none() => return Err("avionics_early"),
            "avionics" => {
                self.avionics_at = self.avionics_at.or(Some(self.t));
                self.avionics_on = true;
            }
            "ins" if self.avionics_at.is_none() => return Err("ins_no_power"),
            "ins" => {
                self.ins_at = self.ins_at.or(Some(self.t));
                self.ins_on = true;
            }
            "canopy" => self.canopy_closed = true,
            _ => {}
        }
        Ok(())
    }

    /// A checklist switch back off (the F-16's engine step, the throttle to OFF, is [`Start::cut_off`]); never a
    /// fault. Main power off: no power at all, the displays to warm up again, the INS alignment lost, a crank stops
    /// (the engine lit runs on: inferred). The starter off: a crank stops. The avionics off: the displays dark, a
    /// warm-up again when back on, the INS alignment lost (inferred). The INS knob off: the alignment lost. The
    /// canopy: open.
    pub fn release(&mut self, step: &str) {
        match step {
            "main_power" => {
                self.commanded = false;
                self.displays_at = None;
                self.ins_at = None;
                self.starter_on = false; // held on by its power only (inferred), as the JFS switch's spring-back
                self.stop_crank();
            }
            "starter" => {
                self.starter_on = false;
                self.stop_crank();
            }
            "avionics" => {
                self.avionics_on = false;
                self.avionics_at = None;
                self.ins_at = None;
            }
            "ins" => {
                self.ins_on = false;
                self.ins_at = None;
            }
            "canopy" => self.canopy_closed = false,
            _ => {}
        }
    }

    /// The starter stops: an engine it was turning (unlit) winds down.
    fn stop_crank(&mut self) {
        if matches!(self.phase, Phase::Starter | Phase::Crank) {
            self.next(if self.rpm > 0.0 { Phase::Rundown } else { Phase::Off });
        }
    }

    /// The position of checklist step `step`'s switch: main power, the starter (on while it runs, and done once the
    /// engine is lit: its switch springs back), the engine (the fuel on), the avionics power, the INS knob, the
    /// canopy closed.
    pub fn on(&self, step: &str) -> bool {
        let lit = matches!(self.phase, Phase::LightOff | Phase::Accel | Phase::Running);
        match step {
            "main_power" => self.commanded,
            "starter" => self.starter_on || lit,
            "engine" => self.fuel_on || lit,
            "avionics" => self.avionics_on,
            "ins" => self.ins_on,
            "canopy" => self.canopy_closed,
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Runs a start at 30 Hz; (time to idle, time to the displays, time to the avionics), s.
    fn run(s: &StartSpec) -> (f64, f64, f64) {
        let mut st = Start::default();
        assert_eq!(st.power(s), 0);
        st.begin(s);
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
        st.begin(&IPP);
        st.step(&IPP, 0.1);
        assert_eq!((st.phase, st.power(&IPP), st.avionics(&IPP)), (Phase::Running, 2, true));
    }

    /// Every switch back off and on (the switches audit's M2): each its consequence, the position read back.
    #[test]
    fn the_switches_go_both_ways() {
        let tick = |st: &mut Start, s: f64| {
            for _ in 0..(s * 30.0) as usize {
                st.step(&JFS, 1.0 / 30.0);
            }
        };
        let mut st = Start::running();
        for step in ["main_power", "engine", "avionics", "ins", "canopy"] {
            assert!(st.on(step), "a hot jet's {step} on");
        }
        tick(&mut st, 0.1);
        assert!(!st.starter_on && st.on("starter"), "the JFS switch back at OFF, the step done (the engine lit)");
        // The avionics off: the displays dark, the INS alignment lost; back on: 3 s of warm-up, 90 s to align.
        st.release("avionics");
        assert_eq!((st.on("avionics"), st.power(&JFS), st.avionics(&JFS)), (false, 1, false));
        st.press(&JFS, "avionics").unwrap();
        tick(&mut st, 2.0);
        assert_eq!(st.power(&JFS), 1, "warming up");
        tick(&mut st, 1.5);
        assert_eq!((st.power(&JFS), st.avionics(&JFS)), (2, false), "up, the INS aligning");
        tick(&mut st, 90.0);
        assert!(st.avionics(&JFS), "aligned again");
        // The INS knob off: the alignment lost; on: 90 s again.
        st.release("ins");
        assert!(!st.avionics(&JFS) && !st.on("ins"));
        st.press(&JFS, "ins").unwrap();
        tick(&mut st, 89.0);
        assert!(!st.avionics(&JFS));
        tick(&mut st, 1.5);
        assert!(st.avionics(&JFS));
        // Main power off: no power, the engine runs on (inferred); on again: the displays warm up, the INS aligns.
        st.release("main_power");
        tick(&mut st, 1.0);
        assert_eq!((st.power(&JFS), st.phase, st.on("main_power")), (0, Phase::Running, false));
        st.press(&JFS, "main_power").unwrap();
        tick(&mut st, 3.5);
        assert_eq!((st.power(&JFS), st.avionics(&JFS)), (2, false));
        tick(&mut st, 91.0);
        assert!(st.avionics(&JFS));
        // The canopy opens and closes.
        st.release("canopy");
        assert!(!st.on("canopy"));
        st.press(&JFS, "canopy").unwrap();
        assert!(st.on("canopy"));
        // A cold jet: the JFS off during the crank stops it; main power off stops it too.
        let mut st = Start::default();
        st.press(&JFS, "main_power").unwrap();
        st.press(&JFS, "starter").unwrap();
        tick(&mut st, 5.0);
        assert!(st.on("starter") && st.rpm > 0.0);
        st.release("starter");
        assert_eq!((st.on("starter"), st.phase), (false, Phase::Rundown));
        tick(&mut st, 60.0);
        assert_eq!(st.phase, Phase::Off);
        st.press(&JFS, "starter").unwrap();
        tick(&mut st, 5.0);
        st.release("main_power");
        assert_eq!((st.phase, st.power(&JFS), st.on("starter")), (Phase::Rundown, 0, false));
        assert_eq!(st.press(&JFS, "starter"), Err("no_power"), "no power for the JFS");
        // The F-35I's IPP off before the engine start: it stops.
        let mut st = Start::default();
        st.press(&IPP, "main_power").unwrap();
        st.press(&IPP, "starter").unwrap();
        st.release("starter");
        assert_eq!((st.phase, st.on("starter")), (Phase::Off, false));
    }

    /// The throttle to OFF at idle: the run-down's timings, the displays dark at the generators, the starter again
    /// below 20 %, a restart by keys back to idle with the displays up.
    #[test]
    fn a_shutdown_winds_down_and_the_jfs_restarts_it() {
        let mut st = Start::running();
        assert_eq!(st.cut_off(IDLE_RPM), Err("shutdown"));
        let (mut t, mut dark, mut low, mut stop) = (0.0_f64, None, None, None);
        while t < 90.0 {
            st.step(&JFS, 1.0 / 30.0);
            t += 1.0 / 30.0;
            dark = dark.or((st.power(&JFS) < 2).then_some(t));
            low = low.or((st.rpm < JFS.lightoff_rpm).then_some(t));
            stop = stop.or((st.phase == Phase::Off).then_some(t));
            if low.is_none() {
                assert_eq!(st.press(&JFS, "starter"), Err("starter_high"));
                assert_eq!(st.phase, Phase::Rundown, "the starter waits for 20 %");
            }
        }
        assert!((dark.unwrap() - 2.1).abs() < 0.1, "generators off at {dark:?}");
        assert!((low.unwrap() - 16.5).abs() < 0.1, "20 % at {low:?}");
        assert!((stop.unwrap() - 61.4).abs() < 0.1, "stopped at {stop:?}");
        assert_eq!((st.rpm, st.power(&JFS), st.avionics(&JFS)), (0.0, 1, false));
        // A restart by keys (the hot jet's avionics switches stay on): the JFS, the throttle up from OFF at 20 %.
        let mut st = Start::running();
        st.cut_off(IDLE_RPM).unwrap_err();
        st.manual = true;
        st.avionics_at = Some(0.0);
        for _ in 0..600 {
            st.step(&JFS, 1.0 / 30.0);
        }
        assert_eq!(st.press(&JFS, "engine"), Err("no_rotation"), "the fuel on with no starter");
        st.press(&JFS, "starter").unwrap();
        assert_eq!(st.phase, Phase::Starter);
        for _ in 0..300 {
            st.step(&JFS, 1.0 / 30.0);
        }
        st.press(&JFS, "engine").unwrap();
        for _ in 0..1500 {
            st.step(&JFS, 1.0 / 30.0);
        }
        assert_eq!((st.phase, st.power(&JFS)), (Phase::Running, 2));
        // The fuel cut during the light-off: no start.
        let mut st = Start::default();
        st.begin(&JFS);
        while st.phase != Phase::Accel {
            st.step(&JFS, 0.1);
        }
        assert_eq!(st.cut_off(st.rpm), Err("no_start"));
        assert_eq!(st.phase, Phase::Rundown);
    }
}
