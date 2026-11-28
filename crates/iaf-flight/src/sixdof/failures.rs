//! The failures a lesson starts (modern-iaf/docs/training.md §15): a mission, a check ride's pick or a dev hook names
//! a failure and when it comes (a time, the take-off roll, after lift-off). Each failure is a real emergency of the
//! jet with its real indications; the pilot recovers by the real checklist's steps (T.O. GR1F-16CJ-1 section III for
//! the F-16s). The 6-DoF ([`super::flight::SixDof`]) applies the effects; the cockpit reads [`Failures`] for its
//! lamps, the fault list and the ICAWS.
//!
//! These are not the game's systems damage (docs/damage.md §5.2, a hit's random pick): that stays as it is, and both
//! act at once when both are set.

/// One failure.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Failure {
    /// A fire in the engine bay: ENG FIRE. Thrust to the least practical puts it out; kept burning it takes
    /// hydraulic system A, then the engine.
    EngineFire,
    /// The engine flames out (fuel starvation or a mechanical failure): the air start relights it.
    Flameout,
    /// Hydraulic system A lost: HYD/OIL PRESS, its gauge at zero, the speed brakes stay where they are.
    HydA,
    /// Hydraulic system B lost: HYD/OIL PRESS, its gauge at zero; the normal gear extension, the nose wheel steering
    /// and the normal brakes lost (ALT GEAR lowers the gear; the brakes run on the accumulators).
    HydB,
    /// The main generator (the F-35I's starter/generator): MAIN GEN, ELEC SYS; the standby generator carries the jet.
    GenMain,
    /// The main and standby generators: the EPU starts by itself and holds the emergency buses (the F-16s).
    GenBoth,
    /// The main and standby generators, and the EPU does not get its automatic start: EPU switch to ON (the F-16s).
    GenEpu,
    /// A dual air data failure: the FLCS on its standby gains (STBY GAINS, the FLCS warning light).
    StandbyGains,
    /// The landing gear stays where it is (GEAR FAIL): in the F-35A crash at Eielson on 28 January 2025 the gear did
    /// not retract after take-off (modern-iaf/docs/research/training.md §3.4).
    GearFault,
}

impl Failure {
    pub const ALL: [Failure; 9] = [
        Failure::EngineFire,
        Failure::Flameout,
        Failure::HydA,
        Failure::HydB,
        Failure::GenMain,
        Failure::GenBoth,
        Failure::GenEpu,
        Failure::StandbyGains,
        Failure::GearFault,
    ];

    /// The failure's name in a mission and in the recording.
    pub fn id(self) -> &'static str {
        match self {
            Failure::EngineFire => "engine_fire",
            Failure::Flameout => "flameout",
            Failure::HydA => "hyd_a",
            Failure::HydB => "hyd_b",
            Failure::GenMain => "gen_main",
            Failure::GenBoth => "gen_both",
            Failure::GenEpu => "gen_epu",
            Failure::StandbyGains => "standby_gains",
            Failure::GearFault => "gear_fault",
        }
    }

    pub fn from_id(id: &str) -> Option<Failure> {
        Failure::ALL.into_iter().find(|f| f.id() == id)
    }

    pub fn bit(self) -> u32 {
        1 << Failure::ALL.iter().position(|f| *f == self).unwrap_or(0)
    }

    /// Lights a warning light (the voice says "Warning"); else a caution ("Caution").
    pub fn warning(self) -> bool {
        !matches!(self, Failure::GenMain | Failure::GenBoth | Failure::GenEpu | Failure::GearFault)
    }

    /// The one rule every screen, mission and the flight take: whether the jet has this failure. `epu`: the jet has
    /// the F-16's EPU and its two hydraulic systems; the F-35I (IPP, its surfaces on their own electric actuators)
    /// has the fire, the flameout, its generator and its control system's degraded mode. Err: why not.
    pub fn allowed(self, epu: bool) -> Result<(), &'static str> {
        match self {
            Failure::HydA | Failure::HydB if !epu => Err("no_hydraulic_systems"),
            Failure::GenBoth | Failure::GenEpu if !epu => Err("no_epu"),
            _ => Ok(()),
        }
    }
}

/// When a planned failure comes.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum When {
    /// At this flight time, s.
    At(f64),
    /// On the take-off roll, at this ground speed, kt.
    Roll(f64),
    /// On the take-off roll, this long after it began (ground speed past [`ROLL_START_KT`]), s.
    RollAfter(f64),
    /// This long after lift-off, s.
    Airborne(f64),
}

impl When {
    /// From a mission's `on` ("time", "takeoff_roll", "airborne") and its value (s, kt, s).
    pub fn parse(on: &str, value: f64) -> Option<When> {
        let v = value.max(0.0);
        match on {
            "time" | "" => Some(When::At(v)),
            "takeoff_roll" => Some(When::Roll(v)),
            "takeoff_roll_s" => Some(When::RollAfter(v)),
            "airborne" => Some(When::Airborne(v)),
            _ => None,
        }
    }
}

/// The take-off roll begins at this ground speed, kt (inferred: past any taxi speed).
pub const ROLL_START_KT: f64 = 40.0;

/// A course's emergency (`modern-iaf/data/training/course.json` `emergencies`, the check ride's pick
/// `course::Course::check_ride_emergency`: its id, its moment `at` "roll" or "airborne", the time after it s) as the
/// failure the flight starts. `seed` picks between the failures one emergency stands for (hydraulic system A or B; the
/// EPU starting by itself or not). None: an emergency with no failure here (the F-35I's `gear_fault`).
pub fn from_course(id: &str, at: &str, after_s: f64, seed: u64) -> Option<(Failure, When)> {
    let either = |a, b| if seed.is_multiple_of(2) { a } else { b };
    let f = match id {
        "engine_fire_roll" | "engine_fire" => Failure::EngineFire,
        "flameout" => Failure::Flameout,
        "hydraulic" => either(Failure::HydA, Failure::HydB),
        "epu" => either(Failure::GenBoth, Failure::GenEpu),
        "electrical" => Failure::GenMain,
        "flight_controls" => Failure::StandbyGains,
        "gear_fault" => Failure::GearFault,
        _ => return None,
    };
    let when = match at {
        "roll" => When::RollAfter(after_s),
        "airborne" => When::Airborne(after_s),
        _ => return None,
    };
    Some((f, when))
}

/// The lever at or below which the engine runs at "the minimum practical" thrust (a quarter of its travel, below
/// military's 0.74; inferred: the procedure gives no figure).
pub const FIRE_MIN_LEVER: f64 = 0.25;
/// At minimum thrust, or with the fuel cut, a fire goes out in this long, s (inferred: the manual's nozzle fire goes
/// out "within approximately 30-45 seconds" of leaving the afterburner; a bay fire with its fuel starved is taken as
/// shorter).
pub const FIRE_OUT_S: f64 = 15.0;
/// A fire kept above minimum thrust this long burns through hydraulic system A (s, inferred: the manual names "the
/// loss of either hydraulic system" among the signs of a fire that persists), and at twice it the engine fails.
pub const FIRE_SPREAD_S: f64 = 60.0;
/// The brake/JFS accumulators hold "at least 75 seconds of continuous brake application" (p. 3-123).
pub const ACCUMULATOR_S: f64 = 75.0;

/// What the failures read from the flight each frame.
#[derive(Clone, Copy, Debug, Default)]
pub struct Inputs {
    pub on_ground: bool,
    /// Ground speed, kt.
    pub ground_kt: f64,
    /// The throttle lever (0 idle .. 1 full afterburner).
    pub lever: f64,
    /// The engine gets no fuel (the throttle at OFF, the engine stopped).
    pub fuel_cut: bool,
}

/// The planned and the active failures.
#[derive(Clone, Debug, Default)]
pub struct Failures {
    plan: Vec<(Failure, When)>,
    active: u32,
    /// Started since [`Failures::take_started`] (the 6-DoF's one-shot effects).
    started: u32,
    t: f64,
    airborne_at: Option<f64>,
    /// When this take-off roll began (s of flight time).
    roll_at: Option<f64>,
    /// The fire: burning, time at minimum thrust, time above it.
    fire: bool,
    fire_low_s: f64,
    fire_high_s: f64,
    /// The fire burnt through: hydraulic system A, the engine.
    burnt_hyd: bool,
    seized: bool,
    /// The brake accumulators' application left, s.
    accumulator_s: f64,
}

impl Failures {
    /// Plans `f` to come `when`.
    pub fn plan(&mut self, f: Failure, when: When) {
        self.plan.push((f, when));
    }

    /// Starts `f` now (a dev hook, or a plan's time come).
    pub fn start(&mut self, f: Failure) {
        if self.active & f.bit() != 0 {
            return;
        }
        self.active |= f.bit();
        self.started |= f.bit();
        match f {
            Failure::EngineFire => (self.fire, self.fire_low_s) = (true, 0.0),
            Failure::HydB => self.accumulator_s = ACCUMULATOR_S,
            _ => {}
        }
    }

    /// One frame of `dt` s.
    pub fn step(&mut self, i: &Inputs, dt: f64) {
        if dt.is_nan() || dt <= 0.0 {
            return;
        }
        if i.on_ground {
            self.airborne_at = None;
            if i.ground_kt < ROLL_START_KT {
                self.roll_at = None;
            } else if self.roll_at.is_none() {
                self.roll_at = Some(self.t);
            }
        } else if self.airborne_at.is_none() {
            self.airborne_at = Some(self.t); // the lift-off came in this frame
            // A take-off roll's failure not come by the lift-off does not come on a later (landing) roll.
            self.plan.retain(|(_, w)| !matches!(w, When::Roll(_) | When::RollAfter(_)));
            self.roll_at = None;
        }
        self.t += dt;
        let (t, airborne_at, roll_at) = (self.t, self.airborne_at, self.roll_at);
        let due: Vec<Failure> = self
            .plan
            .iter()
            .filter(|(_, w)| match *w {
                When::At(s) => t >= s,
                When::Roll(kt) => i.on_ground && i.ground_kt >= kt,
                When::RollAfter(s) => roll_at.is_some_and(|r| t - r >= s),
                When::Airborne(s) => airborne_at.is_some_and(|a| t - a >= s),
            })
            .map(|(f, _)| *f)
            .collect();
        self.plan.retain(|(f, _)| !due.contains(f));
        for f in due {
            self.start(f);
        }
        if self.fire {
            if i.fuel_cut || i.lever <= FIRE_MIN_LEVER {
                self.fire_low_s += dt;
                if self.fire_low_s >= FIRE_OUT_S {
                    self.fire = false;
                }
            } else {
                self.fire_low_s = 0.0;
                self.fire_high_s += dt;
                self.burnt_hyd |= self.fire_high_s >= FIRE_SPREAD_S;
                self.seized |= self.fire_high_s >= 2.0 * FIRE_SPREAD_S;
            }
        }
    }

    /// The failures started since the last call (bits of [`Failure::bit`]).
    pub fn take_started(&mut self) -> u32 {
        std::mem::take(&mut self.started)
    }

    /// `f` has started (it may be over: a fire out, an engine relit).
    pub fn on(&self, f: Failure) -> bool {
        self.active & f.bit() != 0
    }

    /// The active failures' bits ([`Failure::bit`]).
    pub fn active(&self) -> u32 {
        self.active
    }

    /// The fire burns (ENG FIRE lit).
    pub fn fire(&self) -> bool {
        self.fire
    }

    /// The engine failed for good (a fire kept burning): it no longer runs or relights.
    pub fn seized(&self) -> bool {
        self.seized
    }

    /// Hydraulic systems A and B up (their pumps' own state; the engine's RPM is the gauge's).
    pub fn hyd_ok(&self) -> [bool; 2] {
        [!self.on(Failure::HydA) && !self.burnt_hyd, !self.on(Failure::HydB)]
    }

    /// The main and the standby generator up.
    pub fn gens_ok(&self) -> [bool; 2] {
        let both = self.on(Failure::GenBoth) || self.on(Failure::GenEpu);
        [!both && !self.on(Failure::GenMain), !both]
    }

    /// The EPU gets its automatic start with the generators off line ([`Failure::GenEpu`] takes it away).
    pub fn epu_auto(&self) -> bool {
        !self.on(Failure::GenEpu)
    }

    /// The gear held where it is by a failure: hydraulic system B lost (unless `alt_gear` lowers it), or the gear
    /// fault (nothing moves it).
    pub fn gear_held(&self, alt_gear: bool) -> bool {
        self.on(Failure::GearFault) || (self.on(Failure::HydB) && !alt_gear)
    }

    /// The FLCS on its standby gains.
    pub fn standby_gains(&self) -> bool {
        self.on(Failure::StandbyGains)
    }

    /// The braking a pedal gives with system B lost: the accumulators' share, used up by the application
    /// (`applied` 0..1 for `dt` s). 1 with system B up.
    pub fn brakes(&mut self, applied: f64, dt: f64) -> f64 {
        if !self.on(Failure::HydB) {
            return 1.0;
        }
        let left = if self.accumulator_s > 0.0 { 1.0 } else { 0.0 };
        self.accumulator_s = (self.accumulator_s - applied.max(0.0) * dt).max(0.0);
        left
    }

    /// The brake accumulators' application left, s (system B lost).
    pub fn accumulator_s(&self) -> f64 {
        self.accumulator_s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn air(lever: f64) -> Inputs {
        Inputs { on_ground: false, ground_kt: 300.0, lever, fuel_cut: false }
    }

    #[test]
    fn ids_round_trip_and_the_f35i_has_its_own() {
        for f in Failure::ALL {
            assert_eq!(Failure::from_id(f.id()), Some(f));
            assert_eq!(f.allowed(true), Ok(()));
        }
        assert_eq!(Failure::HydB.allowed(false), Err("no_hydraulic_systems"));
        assert_eq!(Failure::GenEpu.allowed(false), Err("no_epu"));
        for f in [Failure::EngineFire, Failure::Flameout, Failure::GenMain, Failure::StandbyGains] {
            assert_eq!(f.allowed(false), Ok(()), "{f:?}");
        }
        assert_eq!(When::parse("takeoff_roll", 100.0), Some(When::Roll(100.0)));
        assert_eq!(When::parse("later", 1.0), None);
        assert_eq!(from_course("hydraulic", "airborne", 300.0, 1), Some((Failure::HydB, When::Airborne(300.0))));
        assert_eq!(from_course("engine_fire_roll", "roll", 5.0, 0), Some((Failure::EngineFire, When::RollAfter(5.0))));
        assert_eq!(from_course("gear_fault", "airborne", 300.0, 0), Some((Failure::GearFault, When::Airborne(300.0))));
        let mut f = Failures::default();
        f.start(Failure::GearFault);
        assert!(f.gear_held(true) && !Failure::GearFault.warning());
    }

    #[test]
    fn plans_come_at_their_time_roll_speed_or_after_lift_off() {
        let mut f = Failures::default();
        f.plan(Failure::GenMain, When::At(10.0));
        f.plan(Failure::EngineFire, When::Roll(100.0));
        f.plan(Failure::HydA, When::Airborne(5.0));
        let roll = |kt| Inputs { on_ground: true, ground_kt: kt, lever: 1.0, fuel_cut: false };
        f.step(&roll(90.0), 9.0);
        assert_eq!(f.active(), 0);
        f.step(&roll(110.0), 2.0);
        assert!(f.on(Failure::GenMain) && f.on(Failure::EngineFire) && !f.on(Failure::HydA));
        assert_eq!(f.take_started(), Failure::GenMain.bit() | Failure::EngineFire.bit());
        assert_eq!(f.take_started(), 0);
        f.step(&air(0.2), 4.0);
        assert!(!f.on(Failure::HydA));
        f.step(&air(0.2), 1.5);
        assert!(f.on(Failure::HydA) && f.hyd_ok() == [false, true]);
    }

    #[test]
    fn a_roll_failure_comes_seconds_into_the_roll_and_never_on_the_landing() {
        let mut f = Failures::default();
        f.plan(Failure::EngineFire, When::RollAfter(5.0));
        let ground = |kt| Inputs { on_ground: true, ground_kt: kt, lever: 1.0, fuel_cut: false };
        f.step(&ground(10.0), 30.0); // taxi: no roll yet
        f.step(&ground(60.0), 4.0);
        assert!(!f.fire());
        f.step(&ground(90.0), 1.5);
        assert!(f.fire(), "5 s into the roll");
        let mut f = Failures::default();
        f.plan(Failure::EngineFire, When::Roll(200.0)); // never reached on the roll
        f.step(&ground(150.0), 10.0);
        f.step(&air(0.9), 1.0);
        f.step(&ground(250.0), 1.0); // a landing roll
        assert!(!f.on(Failure::EngineFire));
    }

    #[test]
    fn a_fire_goes_out_at_minimum_thrust_and_burns_through_above_it() {
        let mut f = Failures::default();
        f.start(Failure::EngineFire);
        f.step(&air(0.9), 30.0);
        f.step(&air(0.2), FIRE_OUT_S - 1.0);
        assert!(f.fire(), "not yet out");
        f.step(&air(0.9), 1.0); // back up: the count starts again
        f.step(&air(0.2), FIRE_OUT_S - 1.0);
        assert!(f.fire());
        f.step(&air(0.2), 1.0);
        assert!(!f.fire() && f.hyd_ok() == [true, true] && !f.seized());

        let mut f = Failures::default();
        f.start(Failure::EngineFire);
        f.step(&air(1.0), FIRE_SPREAD_S);
        assert!(f.fire() && !f.hyd_ok()[0] && !f.seized());
        f.step(&air(1.0), FIRE_SPREAD_S);
        assert!(f.seized());

        // On the ground the throttle to OFF (the fuel cut) puts it out.
        let mut f = Failures::default();
        f.start(Failure::EngineFire);
        f.step(&Inputs { on_ground: true, ground_kt: 0.0, lever: 0.0, fuel_cut: true }, FIRE_OUT_S);
        assert!(!f.fire());
    }

    #[test]
    fn generators_epu_and_the_brake_accumulators() {
        let mut f = Failures::default();
        f.start(Failure::GenMain);
        assert_eq!(f.gens_ok(), [false, true]);
        assert!(f.epu_auto());
        let mut f = Failures::default();
        f.start(Failure::GenEpu);
        assert_eq!(f.gens_ok(), [false, false]);
        assert!(!f.epu_auto());

        let mut f = Failures::default();
        assert_eq!(f.brakes(1.0, 1.0), 1.0);
        f.start(Failure::HydB);
        assert_eq!(f.brakes(1.0, ACCUMULATOR_S - 1.0), 1.0);
        assert_eq!(f.brakes(0.0, 100.0), 1.0, "unused, the accumulators keep their charge");
        assert_eq!(f.brakes(1.0, 1.0), 1.0);
        assert_eq!(f.brakes(1.0, 1.0), 0.0, "spent");
    }
}
