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
//!
//! The F-16's INS knob has six positions (`INS_KNOB`, `Start::turn_ins`, cockpit.md §5.2): OFF, STOR HDG (the 90 s
//! stored-heading alignment), NORM (the gyrocompass alignment, `NORM_ALIGN_S`), NAV, IN FLT ALIGN and ATT.
//!
//! The F-16's power switches one by one (the switches audit's M2b, cockpit.md §5.2): the generators give the displays'
//! power (`Start::power` 2); each AVIONIC POWER switch (MMC, ST STA, MFD, UFC) and SNSR PWR switch (FCR, RDR ALT) then
//! powers its own system after the warm-up (`Start::system`). The checklist's avionics step is the four on.
//!
//! The F-16's switches of three positions (finish list C3, cockpit.md §5.2; `Start::position`): MAIN PWR OFF / BATT /
//! MAIN PWR ("main_power_batt": the battery alone, the generators kept off the buses, so the displays stay dark;
//! inferred), JFS START 1 / OFF / START 2 ("starter_1": the JFS from one accumulator; it starts the engine as START 2
//! does, inferred) and RDR ALT OFF / STBY / RDR ALT ("rdr_alt_stby": warmed up, no radar altitude until RDR ALT).
//! Each is one enum (`MainPwr`, `Jfs`, `Sys`), so a position that does not exist (BATT with the switch off)
//! cannot be held.
//!
//! The canopy ([`Canopy`], modern-iaf/docs/cockpit.md §5.6): its travel over `CANOPY_S` and the F-16's lock lever. The
//! switch runs it while held (`Start::canopy_switch`), the lever goes down over a shut canopy only, the Canopy key and
//! the Start engine command run the whole sequence (down, then the lever). A jet without the lever (the F-35I) has one
//! CANOPY switch: closed and locked at once, the canopy following.

/// The 6-DoF's idle RPM, % (its gauge's line, modern-iaf/docs/flight-model.md §9.7).
pub const IDLE_RPM: f64 = 60.0;

/// The shutdown (training.md §7.2): with the fuel cut the core winds down as `e^(-t/RUNDOWN_TAU)` (s) and stops below
/// `STOP_RPM` (%): from idle 61 s, the generators off line (52 %) after 2 s, below the starter's 20 % after 16 s.
/// Inferred: no public run-down figure; "about a minute" to a stop.
pub const RUNDOWN_TAU: f64 = 15.0;
pub const STOP_RPM: f64 = 1.0;

/// In the air (modern-iaf/docs/training.md §7.2): the airflow windmills the core at `WINDMILL_RPM_PER_KT` × KCAS, %
/// (inferred: 20 % at 250 KCAS, inside the "20–25 %" a dive gives, secondary); the run-down settles there instead of
/// stopping. The throttle up from OFF lights a windmilling engine from `AIRSTART_RPM`, % (below it the main fuel
/// pump gives too little flow, second-hand); below it the JFS cranks it, inside `JFS_AIR_ENVELOPE` (ft, KCAS: below
/// 20,000 ft and 400 KCAS, secondary). Sources in modern-iaf/docs/training.md §7.2.
pub const WINDMILL_RPM_PER_KT: f64 = 0.08;
pub const AIRSTART_RPM: f64 = 12.0;
pub const JFS_AIR_ENVELOPE: (f64, f64) = (20_000.0, 400.0);

/// The F-16's per-system power switches (`Start::system`): the four AVIONIC POWER switches (the checklist's avionics
/// step) and the SNSR PWR panel's FCR, RDR ALT, LEFT HDPT and RIGHT HDPT (the chin stations' pods: the navigation pod
/// on 5L, the targeting pod on 5R; modern-iaf/docs/weapons.md §7.3); IafFlight command 219's p2 indexes them.
pub const SYSTEMS: [&str; 8] = ["mmc", "st_sta", "mfd", "ufc", "fcr", "rdr_alt", "l_hdpt", "r_hdpt"];
/// The first `AVIONICS` of `SYSTEMS` make the avionics step.
const AVIONICS: usize = 4;

/// The F-16's INS knob's positions, in FlightGear's values 0–5 (`f16/avionics/ins-knob`: its HUD shows ALIGN at 2 and
/// 4, NAV at 3; modern-iaf/docs/cockpit.md §5.2). OFF: no INS; STOR HDG and NORM align; NAV and IN FLT ALIGN go on
/// with the alignment (aligned once it is done); ATT: attitude only, the alignment lost (inferred).
pub const INS_KNOB: [&str; 6] = ["OFF", "STOR HDG", "NORM", "NAV", "IN FLT ALIGN", "ATT"];
const INS_OFF: u8 = 0;
const INS_STOR_HDG: u8 = 1;
const INS_NORM: u8 = 2;
const INS_NAV: u8 = 3;
const INS_ATT: u8 = 5;
/// The NORM (gyrocompass) alignment, s: about 8 minutes (the user's training decisions, 2026-11-12; inferred figure).
pub const NORM_ALIGN_S: f64 = 480.0;
/// RDR ALT's index in `SYSTEMS` (the switch with a STBY position).
const RDR_ALT: usize = 5;

/// The canopy's travel, open to shut (s): FlightGear's F-16 (Systems/jsb-controls.xml fcs/canopy-control-1, 10 s); the
/// F-35I's inferred the same.
pub const CANOPY_S: f64 = 10.0;

/// The MAIN PWR switch (the F-35I's BATT): OFF, BATT (the battery alone, the generators kept off the buses), MAIN PWR.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum MainPwr {
    #[default]
    Off,
    Batt,
    Main,
}

/// The JFS switch (the F-35I's IPP: START 2 is on): OFF, START 1 (one accumulator), START 2. It springs back to OFF
/// once the engine sustains itself.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Jfs {
    #[default]
    Off,
    Start1,
    Start2,
}

/// `!jfs`: the switch at OFF.
impl std::ops::Not for Jfs {
    type Output = bool;
    fn not(self) -> bool {
        self == Jfs::Off
    }
}

/// One of the F-16's `SYSTEMS` switches: OFF, or on since a time (s since the command); RDR ALT also at STBY (warmed up
/// with its time, no radar altitude).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
enum Sys {
    #[default]
    Off,
    Stby(f64),
    On(f64),
}

impl Sys {
    /// When it went on (at STBY or on), None at OFF.
    fn since(self) -> Option<f64> {
        match self {
            Sys::Off => None,
            Sys::Stby(at) | Sys::On(at) => Some(at),
        }
    }
}

/// The canopy and its lock lever (modern-iaf/docs/cockpit.md §5.6).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Canopy {
    /// Stopped off its seat (a cold jet's: fully up), the lever up.
    #[default]
    Up,
    /// Running down: the switch held at CLOSE, or with `lock` the whole sequence (the Canopy key, the Start engine
    /// command, the F-35I's CANOPY switch), the lever going down at the bottom.
    Closing { lock: bool },
    /// Shut, the lever up.
    Down,
    /// Shut, the lever down: the checklist's canopy step.
    Locked,
    /// Running up: the switch held at OPEN, or the Canopy key's sequence.
    Opening,
}

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
    /// In the air with the engine below `generator_rpm`, the starter keeps the displays up as the emergency power: the
    /// F-35's IPP (no limit). The F-16's EPU is its own system ([`Start::epu`]).
    pub starter_emergency: bool,
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
    starter_emergency: false,
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
    // The IPP is also the jet's emergency power in the air, on the main fuel: no limit (inferred: no figure is
    // public).
    starter_emergency: true,
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
    /// The MAIN PWR switch (the F-35I's BATT): on at BATT or MAIN PWR is the command given.
    main: MainPwr,
    /// Flown by keys (`press`): the steps wait for their keys.
    manual: bool,
    /// By keys: the fuel on (the F-16's throttle to idle; the F-35's engine start).
    fuel_on: bool,
    /// The INS alignment's start (s since the command), its length (s: the mode it started in), and the alignment
    /// done (held until the INS loses it).
    ins_at: Option<f64>,
    ins_need: f64,
    ins_aligned: bool,
    /// The F-16's `SYSTEMS` switches.
    systems: [Sys; SYSTEMS.len()],
    /// The starter's switch (the JFS, the IPP), the INS knob's position (`INS_KNOB`).
    starter_on: Jfs,
    ins_knob: u8,
    /// The canopy, how far down it is (0 up .. 1 shut), and whether the jet has the F-16's lock lever (set by its
    /// cockpit; without it the one CANOPY switch). `canopy_hot`: a hot start's jet without the lever keeps its canopy
    /// shut, its switch's OPEN included (as the game drew it before the canopy moved here; set by the game).
    canopy: Canopy,
    canopy_shut: f64,
    pub canopy_lever: bool,
    pub canopy_hot: bool,
    /// The whole sequence lifted the F-16's lever over an open canopy (the Start engine command, a hand putting a
    /// locked canopy open) since the game last took it ([`Start::canopy_tick`]): recorded as the lever up.
    canopy_lifted: bool,
    /// In the air: (KCAS, altitude ft), set by the flight before each step; None on the ground.
    pub air: Option<(f64, f64)>,
    /// The RPM the acceleration to idle started from, %.
    accel_from: f64,
    /// The F-16's EPU runs (set by its cockpit each frame: the EPU switch, its hydrazine; modern-iaf/docs/cockpit.md
    /// "EPU"): in the air it holds the displays' power with the generators off line.
    pub epu: bool,
    /// Both generators failed (set by the flight each frame from its failures, `failures.rs`): the generators off
    /// line at any RPM, so the displays drop unless the emergency power holds them.
    pub gens_failed: bool,
}

impl Start {
    /// An engine already running (an airborne or runway start): every system up.
    pub fn running() -> Start {
        // Its clock long past every step of the sequence.
        Start { phase: Phase::Running, t: 1.0e6, rpm: IDLE_RPM, displays_at: Some(0.0), ..Start::switched_on() }
    }

    /// Every switch on, the INS aligned and at NAV (the "start engine" command flies the whole checklist).
    fn switched_on() -> Start {
        Start {
            main: MainPwr::Main,
            fuel_on: true,
            ins_at: Some(-1.0e6),
            ins_aligned: true,
            systems: [Sys::On(0.0); SYSTEMS.len()],
            ins_knob: INS_NAV,
            canopy: Canopy::Locked,
            canopy_shut: 1.0,
            ..Start::default()
        }
    }

    /// An engine already running with `old`'s canopy (the engine on at once, [`Start::running`]): the canopy comes down
    /// and locks, as the "start engine" command's.
    pub fn running_from(old: &Start) -> Start {
        Start::running().canopy_of(old)
    }

    /// `self` with `old`'s canopy, which then runs the whole sequence (the start flies every checklist step): an open
    /// canopy comes down and the lever locks it at the bottom; a shut one locks at once.
    fn canopy_of(mut self, old: &Start) -> Start {
        (self.canopy_shut, self.canopy_lever, self.canopy_hot) = (old.canopy_shut, old.canopy_lever, old.canopy_hot);
        self.canopy_lifted = old.canopy_lifted || (self.canopy_lever && self.canopy_shut < 1.0);
        self.canopy = Canopy::Closing { lock: true };
        self.settle();
        self
    }

    /// The "start engine" command: a stopped engine begins its sequence (one winding down once below the starter's
    /// RPM, [`Start::starter_engages`]); otherwise nothing.
    pub fn begin(&mut self, s: &StartSpec) {
        if self.starter_engages(s) {
            *self = Start {
                phase: Phase::Starter,
                rpm: self.rpm,
                fuel_on: false,
                starter_on: Jfs::Start2,
                ..Start::switched_on()
            }
            .canopy_of(self);
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

    /// The flame out (an empty tank) at the engine's RPM `rpm` (%): an engine lit or running winds down as after the
    /// fuel cut, the throttle where it is. True when it flamed out.
    pub fn flame_out(&mut self, rpm: f64) -> bool {
        let lit = matches!(self.phase, Phase::LightOff | Phase::Accel | Phase::Running);
        if lit {
            self.rpm = rpm;
            self.next(Phase::Rundown);
        }
        lit
    }

    /// The engine stopped: no RPM, the displays and the avionics down, the switches as they are (a new command
    /// restarts).
    pub fn shutdown(&mut self) {
        self.next(Phase::Off);
        self.rpm = 0.0;
        self.fuel_on = false;
        self.starter_on = Jfs::Off;
        self.displays_at = None;
    }

    /// Advances `dt` s; true on the step the sequence reaches idle.
    pub fn step(&mut self, s: &StartSpec, dt: f64) -> bool {
        // On main power the clock runs for the INS alignment (a jet with one), the engine stopped or not.
        let aligning = self.main_on() && s.ins_align_s > 0.0;
        if dt.is_nan() || dt <= 0.0 || (self.phase == Phase::Off && !aligning) {
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
            Phase::LightOff if self.phase_t >= s.lightoff_s => {
                self.accel_from = self.rpm.min(IDLE_RPM);
                self.next(Phase::Accel)
            }
            Phase::Rundown => {
                // Toward the windmill's RPM in the air (`WINDMILL_RPM_PER_KT`), to a stop on the ground.
                let wind = self.windmill_rpm();
                self.rpm = wind + (self.rpm - wind) * (-dt / RUNDOWN_TAU).exp();
                // The generators off line: the displays and the avionics down (the INS stays on main power), unless
                // the emergency power holds them in the air.
                if self.rpm < s.generator_rpm && !self.emergency(s) {
                    self.displays_at = None;
                }
                if self.rpm < STOP_RPM {
                    self.rpm = 0.0;
                    self.next(Phase::Off);
                }
            }
            Phase::Accel => {
                // From the light-off RPM (an airstart's from its windmill's) to idle at the start's rate.
                // A quick relight still at idle or above (the fuel cut at power) is at idle at once.
                let from = self.accel_from;
                let k = if from >= IDLE_RPM {
                    1.0
                } else {
                    (self.phase_t / (s.accel_s * (IDLE_RPM - from) / (IDLE_RPM - s.lightoff_rpm))).min(1.0)
                };
                self.rpm = from + (IDLE_RPM - from) * k;
                if k >= 1.0 {
                    self.next(Phase::Running);
                }
            }
            _ => {}
        }
        // The starter's switch springs back to OFF once the engine sustains itself (the JFS cuts out at 50–54 %).
        if self.rpm >= s.generator_rpm {
            self.starter_on = Jfs::Off;
        }
        let main = self.main == MainPwr::Main; // MAIN PWR at MAIN PWR: the generators on the buses
        let powered = main
            && !self.gens_failed
            && self.phase != Phase::Rundown
            && self.phase != Phase::Off
            && if s.displays_on_starter { self.phase != Phase::Starter } else { self.rpm >= s.generator_rpm };
        // The emergency power coming on after the generators dropped (the EPU starts once they are off line) brings
        // the displays back after their warm-up.
        let emergency = main && self.emergency(s);
        if self.gens_failed && !emergency {
            self.displays_at = None;
        }
        if self.displays_at.is_none() && (powered || emergency || (main && self.phase == Phase::Running)) {
            self.displays_at = Some(self.t);
        }
        // The INS knob left on through a main power loss aligns again once main power is back (inferred).
        if self.ins_aligning() && self.ins_at.is_none() && self.main_on() {
            self.ins_start(s);
        }
        self.ins_aligned = self.ins_aligned || self.ins_done(s);
        was != Phase::Running && self.phase == Phase::Running
    }

    /// The RPM the airflow windmills the core at: in the air `WINDMILL_RPM_PER_KT` × KCAS, on the ground none.
    fn windmill_rpm(&self) -> f64 {
        self.air.map_or(0.0, |(kcas, _)| WINDMILL_RPM_PER_KT * kcas.max(0.0))
    }

    /// The emergency power runs in the air: the EPU ([`Start::epu`]), or the starter ([`StartSpec::starter_emergency`]).
    fn emergency(&self, s: &StartSpec) -> bool {
        self.air.is_some() && (self.epu || s.starter_emergency)
    }

    /// A windmilling engine the throttle up from OFF lights (an airstart without the starter): in the air, winding
    /// down at `AIRSTART_RPM` or more.
    fn airstart(&self) -> bool {
        self.air.is_some() && self.phase == Phase::Rundown && self.rpm >= AIRSTART_RPM
    }

    fn next(&mut self, p: Phase) {
        self.phase = p;
        self.phase_t = 0.0;
    }

    /// The electrical power: 0 none (cold), 1 the battery (lamps, engine gauges), 2 the displays' power up (the
    /// generators, or the F-35's IPP, and the warm-up).
    pub fn power(&self, s: &StartSpec) -> u8 {
        match self.displays_at {
            _ if self.main == MainPwr::Off => 0,
            _ if self.main == MainPwr::Batt => 1,
            Some(at) if self.t >= at + s.warmup_s => 2,
            _ => 1,
        }
    }

    /// System `name` of `SYSTEMS` up: the displays' power, and the F-16's own switch on for the warm-up (inferred: the
    /// displays' 3 s). The F-35I's systems come with the power (no per-system switches are sourced).
    pub fn system(&self, s: &StartSpec, name: &str) -> bool {
        let on = |i: usize| matches!(self.systems[i], Sys::On(at) if self.t >= at + s.warmup_s);
        self.power(s) == 2 && (s.fadec || SYSTEMS.iter().position(|n| *n == name).is_some_and(on))
    }

    /// The avionics up: the four AVIONIC POWER systems up, the INS aligned, and, for a jet with a self test, its time
    /// passed.
    pub fn avionics(&self, s: &StartSpec) -> bool {
        let aligned = s.ins_align_s <= 0.0 || self.ins_aligned || self.ins_done(s);
        SYSTEMS[..AVIONICS].iter().all(|n| self.system(s, n)) && self.t >= s.ready_s && aligned
    }

    /// One checklist step by its key (training.md §7.1): "main_power", "starter", "engine", "avionics" (the four
    /// AVIONIC POWER switches and the SNSR PWR panel's four), "ins", "canopy"; or one of `SYSTEMS`. Err: the fault of a step out of order, with its consequence applied (the switch does nothing; a hot
    /// start stops the engine).
    pub fn press(&mut self, s: &StartSpec, step: &str) -> Result<(), &'static str> {
        match step {
            "main_power" | "main_power_batt" => {
                if !self.main_on() && self.phase == Phase::Off {
                    self.manual = true;
                }
                let to = if step == "main_power_batt" { MainPwr::Batt } else { MainPwr::Main };
                if to == MainPwr::Batt && self.main != MainPwr::Batt {
                    self.displays_at = None; // the generators off the buses: the displays dark, a warm-up again
                }
                self.main = to;
            }
            "starter_1" => {
                self.press(s, "starter")?;
                self.starter_on = Jfs::Start1;
            }
            "starter" if !self.main_on() => return Err("no_power"),
            // In the air the JFS runs only inside its envelope.
            "starter"
                if !s.fadec
                    && self.air.is_some_and(|(kcas, ft)| ft >= JFS_AIR_ENVELOPE.0 || kcas >= JFS_AIR_ENVELOPE.1) =>
            {
                return Err("starter_envelope");
            }
            // Winding down above the light-off RPM: the starter waits, the key does nothing.
            "starter" if self.phase == Phase::Rundown && !self.starter_engages(s) => return Err("starter_high"),
            "starter" => {
                if self.starter_engages(s) {
                    self.next(Phase::Starter);
                }
                // Turned with the engine sustaining itself it springs back at once (`step`).
                self.starter_on = Jfs::Start2;
            }
            // A windmilling engine lights from the throttle alone (`airstart`): fuel, the light-off, idle.
            "engine" if self.airstart() => {
                self.fuel_on = true;
                self.next(Phase::LightOff);
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
            // An AVIONIC POWER switch before the generators: it does nothing (FCR and RDR ALT wait for the power).
            "avionics" | "mmc" | "st_sta" | "mfd" | "ufc" if self.displays_at.is_none() => {
                return Err("avionics_early");
            }
            // The key throws the SNSR PWR panel's four on with the four (inferred: the checklist turns
            // them on with the avionics; until 2026-11-17 they stayed off, the radar held dead and the GAAF without a
            // radar altitude after a keyed start). Its release leaves them on: they have switches of their own.
            "avionics" => {
                for sw in self.systems.iter_mut().filter(|sw| **sw == Sys::Off) {
                    *sw = Sys::On(self.t);
                }
            }
            "ins" if self.ins_knob == INS_OFF => return self.turn_ins(s, 1),
            "ins" => {}
            "canopy" => self.canopy_set(1),
            // STBY keeps the time it went on (warmed up there, RDR ALT gives the altitude at once).
            "rdr_alt_stby" => self.systems[RDR_ALT] = Sys::Stby(self.systems[RDR_ALT].since().unwrap_or(self.t)),
            _ => {
                if let Some(i) = SYSTEMS.iter().position(|n| *n == step) {
                    self.systems[i] = Sys::On(self.systems[i].since().unwrap_or(self.t));
                }
            }
        }
        Ok(())
    }

    /// A checklist switch back off (the F-16's engine step, the throttle to OFF, is [`Start::cut_off`]); never a
    /// fault. Main power off: no power at all, the displays to warm up again, the INS alignment lost, a crank stops
    /// (the engine lit runs on: inferred). The starter off: a crank stops. The avionics: the four AVIONIC POWER
    /// switches off; one of `SYSTEMS`: its system down, a warm-up again when back on. The INS knob off: the alignment
    /// lost. The canopy: open.
    pub fn release(&mut self, step: &str) {
        match step {
            "main_power" => {
                self.main = MainPwr::Off;
                self.displays_at = None;
                self.ins_lost();
                self.starter_on = Jfs::Off; // held on by its power only (inferred), as the JFS switch's spring-back
                self.stop_crank();
            }
            "starter" => {
                self.starter_on = Jfs::Off;
                self.stop_crank();
            }
            "avionics" => self.systems[..AVIONICS].fill(Sys::Off),
            "ins" => {
                self.ins_knob = INS_OFF;
                self.ins_lost();
            }
            "canopy" => self.canopy_set(-1),
            _ => {
                if let Some(i) = SYSTEMS.iter().position(|n| *n == step) {
                    self.systems[i] = Sys::Off;
                }
            }
        }
    }

    /// The INS knob turned (commands 214's p1, cockpit.md §5.2): `way` 1 one position on (to ATT at most), -1 one back
    /// (to OFF at most), 0 one on with ATT going round to OFF (the key, a click). Out of OFF it needs main power (the
    /// fault `ins_no_power`: the knob stays at OFF). Into STOR HDG or NORM before the alignment is done it starts again
    /// with that mode's length; NAV and IN FLT ALIGN go on with it; OFF and ATT lose it.
    pub fn turn_ins(&mut self, s: &StartSpec, way: i8) -> Result<(), &'static str> {
        let last = INS_KNOB.len() as u8 - 1;
        let to = match way {
            0 if self.ins_knob == last => INS_OFF,
            0 => self.ins_knob + 1,
            w if w > 0 => (self.ins_knob + 1).min(last),
            _ => self.ins_knob.saturating_sub(1),
        };
        if self.ins_knob == INS_OFF && to != INS_OFF && !self.main_on() {
            return Err("ins_no_power");
        }
        self.ins_aligned = self.ins_aligned || self.ins_done(s);
        let mode_changed = to != self.ins_knob && (to == INS_STOR_HDG || to == INS_NORM);
        self.ins_knob = to;
        if !self.ins_aligning() {
            self.ins_lost();
        } else if self.main_on() && (self.ins_at.is_none() || (mode_changed && !self.ins_aligned)) {
            self.ins_start(s);
        }
        Ok(())
    }

    /// The INS knob's position (`INS_KNOB`'s index, FlightGear's value).
    pub fn ins_knob(&self) -> u8 {
        self.ins_knob
    }

    /// The INS alignment as the DED's INS page shows it (modern-iaf/docs/ufc.md): the seconds it has run, its
    /// length (the knob's mode as it started) and whether it is done.
    pub fn ins_status(&self, s: &StartSpec) -> (f64, f64, bool) {
        let ran = self.ins_at.map_or(0.0, |a| (self.t - a).clamp(0.0, self.ins_need.max(0.0)));
        (ran, self.ins_need, self.ins_aligned || self.ins_done(s))
    }

    /// The knob at a position where the INS runs its alignment on (STOR HDG, NORM, NAV, IN FLT ALIGN).
    fn ins_aligning(&self) -> bool {
        self.ins_knob != INS_OFF && self.ins_knob != INS_ATT
    }

    /// The alignment starts now, its length the knob's mode: NORM's gyrocompass `NORM_ALIGN_S`, any other aligning
    /// position the stored-heading `ins_align_s`.
    fn ins_start(&mut self, s: &StartSpec) {
        self.ins_at = Some(self.t);
        self.ins_need = if self.ins_knob == INS_NORM { NORM_ALIGN_S } else { s.ins_align_s };
    }

    /// The alignment's time done (its length as it started).
    fn ins_done(&self, s: &StartSpec) -> bool {
        self.ins_aligning() && s.ins_align_s > 0.0 && self.ins_at.is_some_and(|a| self.t >= a + self.ins_need)
    }

    fn ins_lost(&mut self) {
        self.ins_at = None;
        self.ins_aligned = false;
    }

    /// The starter stops: an engine it was turning (unlit) winds down.
    fn stop_crank(&mut self) {
        if matches!(self.phase, Phase::Starter | Phase::Crank) {
            self.next(if self.rpm > 0.0 { Phase::Rundown } else { Phase::Off });
        }
    }

    /// The position of checklist step `step`'s switch: main power, the starter (on while it runs, and done once the
    /// engine is lit: its switch springs back), the engine (the fuel on), the avionics power (all four AVIONIC POWER
    /// switches), the INS knob, the canopy closed; or one of `SYSTEMS`.
    pub fn on(&self, step: &str) -> bool {
        let lit = matches!(self.phase, Phase::LightOff | Phase::Accel | Phase::Running);
        match step {
            "main_power" => self.main_on(),
            "starter" => self.starter_on != Jfs::Off || lit,
            "engine" => self.fuel_on || lit,
            // Not a switch: the windmill turns the engine fast enough for an airstart (the throttle's idle step).
            "airstart" => self.airstart(),
            "avionics" => self.systems[..AVIONICS].iter().all(|sw| *sw != Sys::Off),
            "ins" => self.ins_aligning(),
            // The lever down; the F-35I's one switch at CLOSE, the canopy following.
            "canopy" => {
                self.canopy == Canopy::Locked || (!self.canopy_lever && self.canopy == Canopy::Closing { lock: true })
            }
            _ => SYSTEMS.iter().position(|n| *n == step).is_some_and(|i| self.systems[i] != Sys::Off),
        }
    }

    /// The position of a switch of three positions, in FlightGear's values: "main_power" 0 OFF, 1 BATT, 2 MAIN PWR;
    /// "starter" (the JFS switch as it stands: back at OFF once the JFS has cut out) -1 START 1, 0 OFF, 1 START 2;
    /// "rdr_alt" 0 OFF, 1 STBY, 2 RDR ALT. Any other step: 1 on, 0 off.
    pub fn position(&self, step: &str) -> i8 {
        match step {
            "main_power" => self.main as i8, // OFF 0, BATT 1, MAIN PWR 2
            "starter" => match self.starter_on {
                Jfs::Start1 => -1,
                Jfs::Off => 0,
                Jfs::Start2 => 1,
            },
            "rdr_alt" => match self.systems[RDR_ALT] {
                Sys::Off => 0,
                Sys::Stby(_) => 1,
                Sys::On(_) => 2,
            },
            _ => i8::from(self.on(step)),
        }
    }

    /// MAIN PWR at BATT or MAIN PWR (the command given).
    fn main_on(&self) -> bool {
        self.main != MainPwr::Off
    }

    /// The canopy's lever or switch (commands 215's p1, modern-iaf/docs/cockpit.md §5.6). With the F-16's lock lever:
    /// `want` 0 (the Canopy key) the whole sequence the other way from now (locked or closing to lock: the lever up,
    /// then the canopy up; else the canopy down, then the lever down); 1 the lever down over a shut canopy only; -1 the
    /// lever up. A click on the lever ends the key's sequence (the canopy stops); in the air the lever stays down. The
    /// one CANOPY switch (the F-35I): 1 closed and locked, the canopy following; -1 open; 0 the other way.
    pub fn canopy_set(&mut self, want: i8) {
        use Canopy::*;
        let c = self.canopy;
        self.canopy = if !self.canopy_lever {
            match (if want == 0 { !self.on("canopy") } else { want > 0 }, c) {
                (true, Locked) => Locked,
                (true, _) => Closing { lock: true },
                (false, _) => self.opening(),
            }
        } else if c == Locked && want <= 0 && self.air.is_some() {
            Locked // airborne: the lever stays down
        } else {
            match (want, c) {
                (0, Locked | Closing { lock: true }) => Opening,
                (0, _) => Closing { lock: true },
                (w, _) if w > 0 && self.canopy_shut >= 1.0 => Locked,
                (w, Locked) if w < 0 => Down,
                (_, Closing { lock: true } | Opening) => self.stopped(),
                _ => c,
            }
        };
        self.settle();
    }

    /// The F-16's canopy switch held at `v` (1 OPEN, -1 CLOSE) or let go (0): the canopy runs while it is held, a key's
    /// sequence ends. The lever down guards it (its click lifts the lever first, the cockpit's guard).
    pub fn canopy_switch(&mut self, v: i8) {
        if self.canopy != Canopy::Locked {
            self.canopy = match v.signum() {
                1 => Canopy::Opening,
                -1 => Canopy::Closing { lock: false },
                _ => self.stopped(),
            };
            self.settle();
        }
    }

    /// The canopy's state.
    pub fn canopy(&self) -> Canopy {
        self.canopy
    }

    /// The canopy's opening, 0 shut .. 1 fully up (the outside model's and the cockpit frame's turn).
    pub fn canopy_open(&self) -> f64 {
        1.0 - self.canopy_shut
    }

    /// The canopy's run: -1 coming down, 1 going up, 0 stopped (one door sound per run).
    pub fn canopy_run(&self) -> i8 {
        match self.canopy {
            Canopy::Closing { .. } => -1,
            Canopy::Opening => 1,
            _ => 0,
        }
    }

    /// The canopy put at `open` (0 shut .. 1 up) by a hand other than its own controls (a test, a picture's helper):
    /// with the lever stopped there, or running on; a locked lever over an open canopy runs the whole sequence (down,
    /// then locked). Without the lever the canopy runs back to where its switch puts it (open: up, unless pinned).
    pub fn set_canopy_open(&mut self, open: f64) {
        self.canopy_shut = (1.0 - open).clamp(0.0, 1.0);
        self.canopy_lifted |= self.canopy == Canopy::Locked && self.canopy_lever && self.canopy_shut < 1.0;
        self.canopy = match self.canopy {
            Canopy::Locked => Canopy::Closing { lock: true },
            Canopy::Up | Canopy::Down if !self.canopy_lever => self.opening(),
            Canopy::Up | Canopy::Down => self.stopped(),
            c => c,
        };
        self.settle();
    }

    /// A hot start's jet without the lever (`canopy_hot`): its canopy kept shut.
    fn pinned(&self) -> bool {
        self.canopy_hot && !self.canopy_lever
    }

    /// The one CANOPY switch at open: the canopy up, or, pinned, down to shut with the switch open.
    fn opening(&self) -> Canopy {
        if self.pinned() { Canopy::Closing { lock: false } } else { Canopy::Opening }
    }

    /// The canopy stopped where it is: down when shut, else up.
    fn stopped(&self) -> Canopy {
        if self.canopy_shut >= 1.0 { Canopy::Down } else { Canopy::Up }
    }

    /// A run at its stop ends: up, down, or locked at the end of the whole sequence.
    fn settle(&mut self) {
        self.canopy = match self.canopy {
            Canopy::Opening if self.canopy_shut <= 0.0 => Canopy::Up,
            Canopy::Closing { lock: true } if self.canopy_shut >= 1.0 => Canopy::Locked,
            Canopy::Closing { lock: false } if self.canopy_shut >= 1.0 => Canopy::Down,
            c => c,
        };
    }

    /// The canopy runs `dt` s, the whole travel in `CANOPY_S`: the game's frame time, frozen, stopped or crashed
    /// included (as the canopy ran before it moved here). True when the whole sequence lifted the lever since the last
    /// call (`canopy_lifted`).
    pub fn canopy_tick(&mut self, dt: f64) -> bool {
        if dt > 0.0 {
            let d = f64::from(self.canopy_run()) * dt / CANOPY_S;
            self.canopy_shut = (self.canopy_shut - d).clamp(0.0, 1.0);
            self.settle();
        }
        std::mem::take(&mut self.canopy_lifted)
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

    /// The user, 15 Nov: "radar isn't working? can't move out of stby?": a keyed start left the FCR (and RDR ALT)
    /// off. The avionics key turns the SNSR PWR panel's two on with the four; its release leaves them on.
    #[test]
    fn the_avionics_key_powers_the_fcr_and_rdr_alt() {
        let mut st = Start::default();
        st.press(&JFS, "main_power").unwrap();
        st.displays_at = Some(0.0);
        st.t = 10.0;
        st.press(&JFS, "avionics").unwrap();
        st.t = 20.0;
        assert!(SYSTEMS.iter().all(|n| st.on(n) && st.system(&JFS, n)), "all eight up");
        assert_eq!(st.position("rdr_alt"), 2, "RDR ALT at RDR ALT");
        st.release("avionics");
        assert!(st.system(&JFS, "fcr") && st.system(&JFS, "rdr_alt") && !st.system(&JFS, "mmc"));
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
        // The avionics before the generators, the INS before main power: the switch does nothing.
        let early = [("main_power", 1.0), ("avionics", 1.0), ("ins", 1.0), ("starter", 1.0), ("engine", 16.0)];
        assert_eq!(keys(&JFS, &early), (vec!["avionics_early"], None));
        assert_eq!(keys(&JFS, &[("ins", 1.0)]).0, ["ins_no_power"]);
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
        // The avionics off: the four systems down, the generators' power and the INS stay; back on: 3 s of warm-up.
        st.release("avionics");
        assert_eq!((st.on("avionics"), st.power(&JFS), st.avionics(&JFS)), (false, 2, false));
        assert!(SYSTEMS[..AVIONICS].iter().all(|n| !st.on(n) && !st.system(&JFS, n)));
        assert!(st.system(&JFS, "fcr") && st.system(&JFS, "rdr_alt"), "the SNSR PWR switches on their own");
        st.press(&JFS, "avionics").unwrap();
        tick(&mut st, 2.0);
        assert!(!st.avionics(&JFS), "warming up");
        tick(&mut st, 1.5);
        assert!(st.avionics(&JFS), "up again, the INS still aligned");
        // Each switch alone: its own system down, the others up; back on after the warm-up.
        for n in SYSTEMS {
            st.release(n);
            assert!(!st.on(n) && !st.system(&JFS, n), "{n} off");
            assert!(SYSTEMS.iter().filter(|m| **m != n).all(|m| st.system(&JFS, m)), "{n} off: the others up");
            assert_eq!(st.on("avionics"), SYSTEMS[AVIONICS..].contains(&n), "{n} off: the avionics step");
            st.press(&JFS, n).unwrap();
            tick(&mut st, 2.0);
            assert!(st.on(n) && !st.system(&JFS, n), "{n} warming up");
            tick(&mut st, 1.5);
            assert!(st.system(&JFS, n), "{n} up");
        }
        // The INS knob off: the alignment lost; on: 90 s again.
        st.release("ins");
        assert!(!st.avionics(&JFS) && !st.on("ins"));
        st.press(&JFS, "ins").unwrap();
        tick(&mut st, 45.0);
        let (ran, need, done) = st.ins_status(&JFS);
        assert!((ran - 45.0).abs() < 1e-6 && need == 90.0 && !done, "the DED's INS page halfway");
        tick(&mut st, 44.0);
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
        // A cold jet: every power switch off; one before the generators does nothing (FCR, RDR ALT go on).
        let mut st = Start::default();
        assert!(SYSTEMS.iter().all(|n| !st.on(n)));
        st.press(&JFS, "main_power").unwrap();
        assert_eq!(st.press(&JFS, "mmc"), Err("avionics_early"));
        st.press(&JFS, "fcr").unwrap();
        assert_eq!((st.on("mmc"), st.on("fcr"), st.system(&JFS, "fcr")), (false, true, false));
        // The INS aligns on main power, the engine stopped.
        st.press(&JFS, "ins").unwrap();
        tick(&mut st, 91.0);
        assert!(st.ins_done(&JFS));
        assert_eq!(st.ins_status(&JFS), (90.0, 90.0, true));
        // The JFS off during the crank stops it; main power off stops it too.
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
        // The F-35I: no per-system switches; its systems come with the power.
        let mut st = Start::running();
        st.release("mmc");
        st.step(&IPP, 0.1);
        assert!(st.system(&IPP, "mmc") && st.avionics(&IPP));
        // The F-35I's IPP off before the engine start: it stops.
        let mut st = Start::default();
        st.press(&IPP, "main_power").unwrap();
        st.press(&IPP, "starter").unwrap();
        st.release("starter");
        assert_eq!((st.phase, st.on("starter")), (Phase::Off, false));
    }

    /// The switches of three positions (finish list C3): MAIN PWR at BATT, JFS at START 1, RDR ALT at STBY.
    #[test]
    fn the_in_between_positions() {
        let tick = |st: &mut Start, s: f64| {
            for _ in 0..(s * 30.0) as usize {
                st.step(&JFS, 1.0 / 30.0);
            }
        };
        // BATT: the battery's power alone; START 1 cranks and starts the engine; the displays wait for MAIN PWR.
        let mut st = Start::default();
        st.press(&JFS, "main_power_batt").unwrap();
        assert_eq!((st.position("main_power"), st.power(&JFS)), (1, 1));
        st.press(&JFS, "starter_1").unwrap();
        assert_eq!(st.position("starter"), -1, "the JFS at START 1");
        tick(&mut st, 30.0);
        st.press(&JFS, "engine").unwrap();
        tick(&mut st, 60.0);
        assert_eq!((st.phase, st.position("starter"), st.power(&JFS)), (Phase::Running, 0, 1), "BATT: no displays");
        st.press(&JFS, "main_power").unwrap();
        tick(&mut st, 3.5);
        assert_eq!((st.position("main_power"), st.power(&JFS)), (2, 2));
        // Back to BATT: the displays dark; OFF: no power.
        st.press(&JFS, "main_power_batt").unwrap();
        tick(&mut st, 3.5);
        assert_eq!((st.position("main_power"), st.power(&JFS)), (1, 1));
        st.release("main_power");
        assert_eq!((st.position("main_power"), st.power(&JFS)), (0, 0));
        // RDR ALT: STBY warms up with no radar altitude; RDR ALT gives it at once; OFF.
        let mut st = Start::running();
        st.release("rdr_alt");
        assert_eq!(st.position("rdr_alt"), 0);
        st.press(&JFS, "rdr_alt_stby").unwrap();
        tick(&mut st, 3.5);
        assert_eq!((st.position("rdr_alt"), st.system(&JFS, "rdr_alt")), (1, false));
        st.press(&JFS, "rdr_alt").unwrap();
        assert_eq!((st.position("rdr_alt"), st.system(&JFS, "rdr_alt")), (2, true));
        st.press(&JFS, "rdr_alt_stby").unwrap();
        assert_eq!((st.position("rdr_alt"), st.system(&JFS, "rdr_alt")), (1, false));
        st.release("rdr_alt");
        assert_eq!(st.position("rdr_alt"), 0);
    }

    /// The INS knob through its six positions both ways (cockpit.md §5.2): each position reached by a turn on and a
    /// turn back, the key's turn going round from ATT to OFF; STOR HDG aligns in 90 s, NORM in 8 min, NAV goes on
    /// with the alignment and keeps it, ATT and OFF lose it; off main power the knob stays at OFF.
    #[test]
    fn the_ins_knob_reaches_every_position_both_ways() {
        let tick = |st: &mut Start, s: f64| {
            for _ in 0..(s * 30.0) as usize {
                st.step(&JFS, 1.0 / 30.0);
            }
        };
        let aligned = |st: &Start| st.ins_aligned || st.ins_done(&JFS);
        let mut st = Start::default();
        assert_eq!((st.turn_ins(&JFS, 1), st.ins_knob()), (Err("ins_no_power"), 0));
        st.press(&JFS, "main_power").unwrap();
        for (i, _) in INS_KNOB.iter().enumerate().skip(1) {
            st.turn_ins(&JFS, 1).unwrap();
            assert_eq!(st.ins_knob() as usize, i);
            assert_eq!(st.on("ins"), i != 5, "the checklist's step done at an aligning position, not at ATT");
        }
        st.turn_ins(&JFS, 1).unwrap();
        assert_eq!(st.ins_knob(), 5, "no turn on past ATT");
        for i in (0..5).rev() {
            st.turn_ins(&JFS, -1).unwrap();
            assert_eq!(st.ins_knob(), i);
        }
        st.turn_ins(&JFS, -1).unwrap();
        assert_eq!((st.ins_knob(), st.on("ins")), (0, false), "no turn back past OFF");
        for i in [1, 2, 3, 4, 5, 0] {
            st.turn_ins(&JFS, 0).unwrap();
            assert_eq!(st.ins_knob(), i, "the key turns on, ATT round to OFF");
        }
        // STOR HDG: 90 s; through NORM to NAV once aligned: aligned at NAV.
        st.turn_ins(&JFS, 1).unwrap();
        tick(&mut st, 89.0);
        assert!(!aligned(&st));
        tick(&mut st, 1.5);
        assert!(aligned(&st));
        st.turn_ins(&JFS, 1).unwrap();
        st.turn_ins(&JFS, 1).unwrap();
        assert_eq!((st.ins_knob(), aligned(&st)), (3, true));
        // ATT: attitude only, the alignment lost; back to NAV: aligning again.
        st.turn_ins(&JFS, 1).unwrap();
        st.turn_ins(&JFS, 1).unwrap();
        assert!(!aligned(&st));
        st.turn_ins(&JFS, -1).unwrap();
        assert!(!aligned(&st));
        // NORM from OFF: the gyrocompass alignment, 8 min.
        st.release("ins");
        st.turn_ins(&JFS, 1).unwrap();
        st.turn_ins(&JFS, 1).unwrap();
        tick(&mut st, 470.0);
        assert!(!aligned(&st));
        tick(&mut st, 11.0);
        assert!(aligned(&st));
        // Through NORM to NAV before the alignment is done: NORM's 8 min go on at NAV (no 90 s short cut).
        st.release("ins");
        for _ in 0..3 {
            st.turn_ins(&JFS, 1).unwrap();
        }
        tick(&mut st, 100.0);
        assert!(st.ins_knob() == 3 && !aligned(&st), "NORM's alignment, not STOR HDG's, at NAV");
        tick(&mut st, 381.0);
        assert!(aligned(&st));
        // The checklist's key from OFF goes to STOR HDG; the hot jet's knob stands at NAV.
        st.release("ins");
        st.press(&JFS, "ins").unwrap();
        assert_eq!(st.ins_knob(), 1);
        assert_eq!(Start::running().ins_knob(), 3);
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

    /// In the air (training.md §7.2): the fuel cut at 300 KCAS, 10,000 ft: the core windmills at 24 % instead of
    /// stopping, the EPU holds the displays while it runs, the throttle up from OFF lights it again to idle with no
    /// starter. At 150 KCAS the windmill's 12 %; slower the JFS, which runs only below 20,000 ft and 400 KCAS. The
    /// F-35I's IPP holds the displays with no limit.
    #[test]
    fn in_the_air_the_engine_windmills_the_epu_holds_and_the_throttle_relights() {
        let air = |st: &mut Start, kcas: f64, ft: f64, s: f64| {
            st.air = Some((kcas, ft));
            for _ in 0..(s * 30.0) as usize {
                st.step(&JFS, 1.0 / 30.0);
            }
        };
        let mut st = Start::running();
        st.air = Some((300.0, 10_000.0));
        assert_eq!(st.cut_off(IDLE_RPM), Err("shutdown"));
        // The EPU starts once the generators are off line (the cockpit sees the RPM below 52 %): the displays drop,
        // then come back after their warm-up.
        air(&mut st, 300.0, 10_000.0, 5.0);
        assert_eq!(st.power(&JFS), 1);
        st.epu = true;
        air(&mut st, 300.0, 10_000.0, 115.0);
        assert_eq!(st.phase, Phase::Rundown);
        assert!((st.rpm - 24.0).abs() < 0.1, "windmilling at {}", st.rpm);
        assert_eq!(st.power(&JFS), 2, "the EPU holds the displays");
        assert!(st.on("airstart"));
        st.press(&JFS, "engine").unwrap();
        assert_eq!(st.phase, Phase::LightOff);
        air(&mut st, 300.0, 10_000.0, 30.0);
        assert_eq!((st.phase, st.power(&JFS)), (Phase::Running, 2));
        // A quick relight at military power: the RPM still above idle lights straight to idle.
        let mut q = Start::running();
        q.air = Some((300.0, 10_000.0));
        q.cut_off(100.0).unwrap_err();
        air(&mut q, 300.0, 10_000.0, 0.5);
        q.press(&JFS, "engine").unwrap();
        air(&mut q, 300.0, 10_000.0, 10.0);
        assert_eq!((q.phase, q.rpm), (Phase::Running, IDLE_RPM));
        // The EPU stopped (its hydrazine spent, its switch OFF): the displays go dark with the generators.
        st.cut_off(IDLE_RPM).unwrap_err();
        st.epu = false;
        air(&mut st, 300.0, 10_000.0, 20.0);
        assert_eq!(st.power(&JFS), 1, "no EPU");
        // Slow: below the airstart's 12 %, the throttle does nothing; the JFS cranks within its envelope.
        let mut st = Start::running();
        st.cut_off(IDLE_RPM).unwrap_err();
        air(&mut st, 140.0, 25_000.0, 120.0);
        assert!(!st.on("airstart") && st.rpm < AIRSTART_RPM);
        assert_eq!(st.press(&JFS, "engine"), Err("no_rotation"));
        assert_eq!(st.press(&JFS, "starter"), Err("starter_envelope"), "above 20,000 ft");
        st.air = Some((140.0, 15_000.0));
        st.press(&JFS, "starter").unwrap();
        air(&mut st, 140.0, 15_000.0, 60.0);
        assert_eq!(st.phase, Phase::Running, "the JFS-assisted airstart");
        // The F-35I's IPP: the displays held for good.
        let mut st = Start::running();
        st.cut_off(IDLE_RPM).unwrap_err();
        st.air = Some((300.0, 10_000.0));
        for _ in 0..30 * 3600 {
            st.step(&IPP, 1.0 / 30.0);
        }
        assert_eq!(st.power(&IPP), 2);
    }

    /// The switches of three positions are one value each (the statemachines audit, #10): the JFS back at OFF has no
    /// START 1 left over (its next turn is START 2), RDR ALT's STBY stays through the avionics key and goes with its
    /// own OFF, MAIN PWR's BATT goes with OFF.
    #[test]
    fn a_switch_of_three_positions_holds_one_position() {
        let tick = |st: &mut Start, s: f64| {
            for _ in 0..(s * 30.0) as usize {
                st.step(&JFS, 1.0 / 30.0);
            }
        };
        let mut st = Start::default();
        assert_eq!([st.position("main_power"), st.position("starter"), st.position("rdr_alt")], [0, 0, 0]);
        st.press(&JFS, "main_power_batt").unwrap();
        st.press(&JFS, "starter_1").unwrap();
        assert_eq!((st.main, st.starter_on), (MainPwr::Batt, Jfs::Start1));
        tick(&mut st, 30.0);
        st.press(&JFS, "engine").unwrap();
        tick(&mut st, 60.0);
        assert_eq!((st.starter_on, st.position("starter")), (Jfs::Off, 0), "sprung back: nothing of START 1 kept");
        st.press(&JFS, "starter").unwrap();
        assert_eq!(st.position("starter"), 1, "the next turn: START 2");
        st.release("main_power");
        assert_eq!((st.main, st.position("main_power"), st.power(&JFS)), (MainPwr::Off, 0, 0));
        st.press(&JFS, "main_power").unwrap();
        st.press(&JFS, "main_power_batt").unwrap();
        st.press(&JFS, "main_power").unwrap();
        assert_eq!(st.position("main_power"), 2);
        // RDR ALT: the avionics key leaves STBY at STBY, OFF clears it, the key then puts it on.
        assert_eq!(SYSTEMS[RDR_ALT], "rdr_alt");
        let mut st = Start::running();
        st.press(&JFS, "rdr_alt_stby").unwrap();
        st.press(&JFS, "avionics").unwrap();
        assert_eq!(st.position("rdr_alt"), 1);
        st.release("rdr_alt");
        assert_eq!((st.systems[RDR_ALT], st.on("rdr_alt")), (Sys::Off, false));
        st.press(&JFS, "avionics").unwrap();
        assert_eq!(st.position("rdr_alt"), 2);
    }

    /// Runs the canopy `s` s at 30 Hz.
    fn canopy_tick(st: &mut Start, s: f64) {
        for _ in 0..(s * 30.0).round() as usize {
            st.canopy_tick(1.0 / 30.0);
        }
    }

    /// The F-16's canopy (modern-iaf/docs/cockpit.md §5.6; the statemachines audit, #11): the switch runs it while
    /// held, the lever goes down over a shut canopy only and guards the switch, all with no power.
    #[test]
    fn the_f16_canopy_switch_and_lever() {
        let mut st = Start { canopy_lever: true, ..Start::default() };
        assert_eq!((st.canopy(), st.canopy_open(), st.on("canopy")), (Canopy::Up, 1.0, false), "cold: up");
        st.canopy_set(1);
        assert_eq!((st.canopy(), st.on("canopy")), (Canopy::Up, false), "the lever over an open canopy stays up");
        st.canopy_switch(-1);
        canopy_tick(&mut st, 3.0);
        assert_eq!(st.canopy_run(), -1);
        assert!((st.canopy_open() - 0.7).abs() < 1e-6, "held 3 s: {}", st.canopy_open());
        st.canopy_switch(0);
        let part = st.canopy_open();
        canopy_tick(&mut st, 1.0);
        assert_eq!((st.canopy(), st.canopy_run(), st.canopy_open()), (Canopy::Up, 0, part), "let go: it stops");
        st.canopy_switch(-1);
        canopy_tick(&mut st, 8.0);
        assert_eq!((st.canopy(), st.canopy_open(), st.on("canopy")), (Canopy::Down, 0.0, false), "down, unlocked");
        st.canopy_switch(0);
        st.canopy_set(1);
        assert_eq!((st.canopy(), st.on("canopy")), (Canopy::Locked, true), "the lever down: the step done");
        st.canopy_switch(1);
        canopy_tick(&mut st, 1.0);
        assert_eq!((st.canopy(), st.canopy_open()), (Canopy::Locked, 0.0), "the lever guards the switch");
        st.canopy_set(-1);
        assert_eq!((st.canopy(), st.on("canopy")), (Canopy::Down, false), "the lever up");
        st.canopy_switch(1);
        canopy_tick(&mut st, 2.0);
        assert_eq!((st.canopy(), st.canopy_run()), (Canopy::Opening, 1));
        assert!((st.canopy_open() - 0.2).abs() < 1e-6);
        st.canopy_switch(0);
        assert_eq!(st.canopy(), Canopy::Up);
    }

    /// The Canopy key's whole sequence each way, reversed mid-run and ended by a hand on the lever; in the air the
    /// lever stays down.
    #[test]
    fn the_f16_canopy_key_runs_the_whole_sequence() {
        let mut st = Start { canopy_lever: true, ..Start::default() };
        st.canopy_set(0);
        assert_eq!((st.canopy(), st.on("canopy")), (Canopy::Closing { lock: true }, false), "the lever waits");
        canopy_tick(&mut st, CANOPY_S + 0.1);
        assert_eq!((st.canopy(), st.canopy_open(), st.on("canopy")), (Canopy::Locked, 0.0, true), "down, locked");
        st.canopy_set(0);
        assert_eq!((st.canopy(), st.on("canopy")), (Canopy::Opening, false), "the lever up at once");
        canopy_tick(&mut st, CANOPY_S + 0.1);
        assert_eq!((st.canopy(), st.canopy_open()), (Canopy::Up, 1.0));
        // Reversed mid-run; the switch held at CLOSE and the key: the key's sequence.
        st.canopy_set(0);
        canopy_tick(&mut st, 4.0);
        st.canopy_set(0);
        assert_eq!(st.canopy(), Canopy::Opening);
        st.canopy_switch(-1);
        st.canopy_set(0);
        assert_eq!(st.canopy(), Canopy::Closing { lock: true });
        // A click on the lever ends it where it is; the key over a shut, unlocked canopy locks it.
        st.canopy_set(-1);
        assert_eq!((st.canopy(), st.canopy_run()), (Canopy::Up, 0));
        st.set_canopy_open(0.0);
        assert_eq!(st.canopy(), Canopy::Down, "put shut by another hand");
        st.canopy_set(0);
        assert_eq!(st.canopy(), Canopy::Locked);
        // In the air the lever stays down: the key, the lever up.
        st.air = Some((300.0, 5000.0));
        st.canopy_set(0);
        st.canopy_set(-1);
        assert_eq!((st.canopy(), st.on("canopy")), (Canopy::Locked, true));
        // Locked over an open canopy put by another hand: the whole sequence, the lever up until it is down.
        st.air = None;
        st.set_canopy_open(0.5);
        assert_eq!((st.canopy(), st.on("canopy")), (Canopy::Closing { lock: true }, false));
    }

    /// The Start engine command over an open canopy (part 1's fix, now the flight model's own): the lever waits, the
    /// canopy comes down over `CANOPY_S`, then the lever locks it; over a shut canopy it locks at once. The engine on at
    /// once (`running_from`) does the same.
    #[test]
    fn start_engine_over_an_open_canopy_lowers_then_locks() {
        let mut st = Start { canopy_lever: true, ..Start::default() };
        st.begin(&JFS);
        assert_eq!((st.canopy(), st.on("canopy"), st.canopy_open()), (Canopy::Closing { lock: true }, false, 1.0));
        canopy_tick(&mut st, CANOPY_S - 0.5);
        assert!(!st.on("canopy") && st.canopy_open() > 0.0);
        canopy_tick(&mut st, 0.6);
        assert_eq!((st.canopy(), st.on("canopy"), st.canopy_open()), (Canopy::Locked, true, 0.0));
        assert!(st.canopy_lever, "the lever kept through the start");
        let mut st = Start { canopy_lever: true, ..Start::default() };
        st.canopy_switch(-1);
        canopy_tick(&mut st, CANOPY_S + 0.1);
        st.canopy_switch(0);
        st.begin(&JFS);
        assert_eq!(st.canopy(), Canopy::Locked, "shut: locked at once");
        let old = Start { canopy_lever: true, ..Start::default() };
        let st = Start::running_from(&old);
        assert_eq!((st.phase, st.canopy(), st.canopy_open()), (Phase::Running, Canopy::Closing { lock: true }, 1.0));
    }

    /// The F-35I's one CANOPY switch: closed and locked at once, the canopy following; open the other way.
    #[test]
    fn the_f35_canopy_switch_locks_at_once() {
        let mut st = Start::default();
        st.canopy_set(0);
        assert_eq!((st.on("canopy"), st.canopy_open(), st.canopy_run()), (true, 1.0, -1));
        canopy_tick(&mut st, CANOPY_S + 0.1);
        assert_eq!((st.canopy(), st.canopy_open()), (Canopy::Locked, 0.0));
        st.canopy_set(0);
        assert_eq!((st.on("canopy"), st.canopy_run()), (false, 1));
        st.canopy_set(1);
        assert_eq!((st.on("canopy"), st.canopy()), (true, Canopy::Locked), "still shut: locked at once");
        st.canopy_set(0);
        canopy_tick(&mut st, 1.0);
        st.canopy_set(1);
        assert_eq!((st.on("canopy"), st.canopy()), (true, Canopy::Closing { lock: true }), "part up: comes down");
    }

    /// A hot start's F-35I (no lever, `canopy_hot`): the switch opens, the checklist's step undone, the canopy stays
    /// shut (as the game drew it before #11); closed again, locked at once.
    #[test]
    fn a_hot_f35_canopy_stays_shut() {
        let mut st = Start { canopy_hot: true, ..Start::running() };
        st.canopy_set(0);
        assert_eq!((st.on("canopy"), st.canopy(), st.canopy_open()), (false, Canopy::Down, 0.0));
        st.set_canopy_open(0.5);
        canopy_tick(&mut st, 6.0);
        assert_eq!((st.on("canopy"), st.canopy(), st.canopy_open()), (false, Canopy::Down, 0.0), "back down");
        st.canopy_set(0);
        assert_eq!((st.on("canopy"), st.canopy()), (true, Canopy::Locked));
        // The F-16's lever is not pinned: it opens.
        let mut st = Start { canopy_hot: true, canopy_lever: true, ..Start::running() };
        st.canopy_set(0);
        assert_eq!(st.canopy(), Canopy::Opening);
    }

    /// The canopy runs on the game's frame time (`canopy_tick`), not in the flight model's step: a parked, frozen or
    /// stopped flight model still moves it, and a long frame is not cut short.
    #[test]
    fn the_canopy_runs_on_the_frame_time() {
        let mut st = Start { canopy_lever: true, ..Start::default() };
        st.canopy_switch(-1);
        st.step(&JFS, 1.0);
        assert_eq!(st.canopy_open(), 1.0, "the flight model's step leaves it");
        st.canopy_tick(0.5);
        assert!((st.canopy_open() - 0.95).abs() < 1e-9, "{}", st.canopy_open());
        st.canopy_tick(f64::NAN);
        assert!((st.canopy_open() - 0.95).abs() < 1e-9);
    }

    /// A cold F-35I's canopy put shut by another hand runs back up over `CANOPY_S` (its switch at open).
    #[test]
    fn a_cold_f35_canopy_put_shut_rises_back() {
        let mut st = Start::default();
        st.set_canopy_open(0.0);
        assert_eq!((st.canopy(), st.canopy_open()), (Canopy::Opening, 0.0));
        canopy_tick(&mut st, CANOPY_S + 0.1);
        assert_eq!((st.canopy(), st.canopy_open()), (Canopy::Up, 1.0));
    }

    /// The whole sequence over an open canopy lifts the F-16's lever, taken once by the game (recorded as the lever
    /// up): the Start engine command, the switch held at CLOSE too, and a locked canopy put open; never over a shut one
    /// or without the lever.
    #[test]
    fn the_sequence_over_an_open_canopy_lifts_the_lever() {
        let mut st = Start { canopy_lever: true, ..Start::default() };
        st.canopy_switch(-1);
        canopy_tick(&mut st, 2.0);
        st.begin(&JFS);
        assert!(st.canopy_tick(0.0), "Start engine with the switch held at CLOSE");
        assert!(!st.canopy_tick(0.0), "taken once");
        canopy_tick(&mut st, CANOPY_S);
        assert_eq!(st.canopy(), Canopy::Locked);
        st.set_canopy_open(0.5);
        assert!(st.canopy_tick(0.0), "a locked canopy put open");
        let mut st = Start { canopy_lever: true, canopy_shut: 1.0, canopy: Canopy::Down, ..Start::default() };
        st.begin(&JFS);
        assert!(!st.canopy_tick(0.0) && st.canopy() == Canopy::Locked, "shut: locked at once");
        let mut st = Start::default();
        st.begin(&IPP);
        assert!(!st.canopy_tick(0.0), "no lever");
        let st = Start::running_from(&Start { canopy_lever: true, ..Start::default() });
        assert!(st.canopy_lifted);
    }
}
