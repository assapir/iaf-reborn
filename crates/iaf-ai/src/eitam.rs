//! Modern IAF's Eitam in the sky (docs/ai.md §24.3): the IAF's Gulfstream G550 CAEW flying a standoff orbit behind the
//! friendly side, its radar covering the fight; on a threat it retreats and calls for help. It flies as the other AI
//! aircraft do: its 6-DoF (`iaf_flight::sixdof::jets::g550`, its aircraft definition `eitam`) under the autopilot's
//! steer loop, so its turns, climbs and speed changes are the G550's. The controller's sensor
//! (`awacs::Sensor::Eitam`) is where it flies. World frame X east, Y north, Z up, metres.

use std::path::Path;

use crate::awacs::{self, Contact, Ident};
use crate::flight::flat;
use iaf_avionics::fctrl;
use iaf_flight::airframe::{self, Rcs};
use iaf_flight::autopilot::{Autopilot, Config, MODE_STEER, Steer};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

/// The speed of sound at 41,000 ft (m/s; the standard atmosphere's 295.1 above the tropopause).
const SOUND_41K: f64 = 295.07;
/// The orbit's height: the G550's cruise altitude, 41,000 ft (Wikipedia, Gulfstream G550: "Long Range Cruise: M0.80
/// at 41,000 ft").
pub const ALT_M: f64 = 41_000.0 * 0.3048;
/// On the orbit: the long-range cruise, Mach 0.80; retreating: the high-speed cruise, Mach 0.85 (the same source).
pub const ORBIT_MPS: f64 = 0.80 * SOUND_41K;
pub const RETREAT_MPS: f64 = 0.85 * SOUND_41K;
/// The orbit's bank (degrees; inferred, an airliner's standard turn): the steer loop's load factor 1 / cos 25°.
pub const BANK_DEG: f64 = 25.0;
/// The racetrack's legs, across the axis to the fight (m; inferred).
pub const LEG_M: f64 = 50_000.0;
/// The station: this far behind the flight's rearmost point on its way to the fight (its base, or its air start where
/// that lies farther back) and this far to the side of that way, so it never flies on the flight's route nor over the
/// fight (m; inferred, the user 25 Nov 2026: "not directly in the middle of the flight").
const BEHIND_M: f64 = 40_000.0;
const SIDE_M: f64 = 30_000.0;
/// A hostile group inside this range and pointing at it (hot or flank), or inside the close range whatever it does,
/// is a threat (m; inferred; NATO THREAT: "within a briefed range").
const THREAT_M: f64 = 100_000.0;
const CLOSE_M: f64 = 50_000.0;
/// A retreat pulls the station back this far from the threat (m; inferred).
pub const PULL_M: f64 = 60_000.0;
/// It goes back on station after this long clear, and repeats its call for help this often while threatened (s;
/// inferred).
const CLEAR_S: f64 = 30.0;
const HELP_REPEAT_S: f64 = 60.0;

/// The station's racetrack: its centre and the unit vector along its legs.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Orbit {
    pub centre: Vec3,
    pub along: Vec3,
}

fn unit_flat(v: Vec3) -> Vec3 {
    let l = v.x.hypot(v.y);
    if l < 1.0 { Vec3::new(0.0, 1.0, 0.0) } else { Vec3::new(v.x / l, v.y / l, 0.0) }
}

/// The station for a fight at `area` flown from `home` (the flight's base) and `start` (its start point): the
/// rearmost of the two along the way to the fight, then [`BEHIND_M`] further back and [`SIDE_M`] to the left of that
/// way, at [`ALT_M`]; the legs across the way.
pub fn station(area: Vec3, home: Vec3, start: Vec3) -> Orbit {
    let u = unit_flat(home - area);
    let back = flat(home, area).max((start - area).dot(u));
    let left = Vec3::new(-u.y, u.x, 0.0);
    let c = area + u * (back + BEHIND_M) + left * SIDE_M;
    Orbit { centre: Vec3::new(c.x, c.y, ALT_M), along: left }
}

/// A call the Eitam makes: the template, its particles (voices.json) and the group it names (for the flight's
/// "contact", `Flight::awacs`).
pub type Call = (&'static str, Vec<String>, awacs::Named);

/// Its flight model's type (`iaf_flight::data_set` G550) and its aircraft definition's id.
pub const TYPE: &str = "G550";
pub const AIRFRAME: &str = "eitam";
/// Its fuel on station (kg; inferred: some hours' worth, under its 16,560 kg of fuel at the maximum take-off).
const FUEL_KG: f32 = 12_000.0;
/// The flight model's step (s): the AI jets' frame.
const STEP_S: f64 = 1.0 / 60.0;
/// The steer loop's point: this far ahead along the wanted heading (m; inferred, far enough for a level turn).
const AHEAD_M: f64 = 20_000.0;
/// The throttle at most: military power (the steer loop's 0.74; the BR710 has no afterburner).
const THR_MAX: f32 = 0.74;
/// Its autothrottle: the speed error summed into the steer loop's speed (1/s) up to a bound (m/s), while the lever is
/// inside its travel (no wind-up while it speeds up at military power or slows down at idle); the loop's own speed
/// law is proportional only, with its lever at 0.7 at no error, which held the G550 12–15 m/s fast (inferred).
const SPEED_I: f64 = 0.15;
const SPEED_I_MAX: f64 = 30.0;

/// Its radar cross-section, from its aircraft definition (`shared/extra/planes/eitam`).
pub fn rcs() -> Rcs {
    airframe::get(AIRFRAME).and_then(|a| a.rcs).unwrap_or(crate::site::FIGHTER)
}

/// The Eitam's state.
pub struct Eitam {
    pub pos: Vec3,
    /// Compass heading, degrees; pitch and bank (+ right wing down), degrees.
    pub heading: f64,
    pub pitch: f64,
    pub roll: f64,
    pub speed: f64,
    /// Its flight model and autopilot.
    jet: Box<(Fm, Autopilot)>,
    /// The autothrottle's sum, m/s.
    speed_i: f64,
    pub orbit: Orbit,
    /// The planned station; a retreat's pull is measured from it, so pulls never add up.
    pub base: Orbit,
    pub alive: bool,
    /// Retreating from the threat at this point.
    pub threat: Option<Vec3>,
    clear_since: f64,
    help_at: f64,
    /// Flying the leg towards +along (else back).
    out: bool,
}

impl Eitam {
    /// On station at the start of its outbound leg, at the long-range cruise, its flight model and autopilot from the
    /// sim's own data `own` (`assets/converted/own`: the flight data and the autopilot's tables).
    pub fn new(orbit: Orbit, own: &Path) -> Result<Eitam, String> {
        let pos = orbit.centre - orbit.along * (LEG_M / 2.0);
        let heading = fctrl::bearing(Vec3::ZERO, orbit.along) as f64;
        let (prm, env) = iaf_flight::load_with(own, TYPE, DataSet::Real)?;
        let h = heading.to_radians();
        let st = Start {
            position: pos,
            pitch: 0.0,
            roll: 0.0,
            heading: h as f32,
            velocity: Vec3::new(h.sin(), h.cos(), 0.0) * ORBIT_MPS,
            airborne: true,
            engine_on: true,
        };
        let mut fm = Fm::start(TYPE, prm, env, st);
        if !matches!(fm, Fm::SixDof(_)) {
            return Err(format!("{TYPE}: no 6-DoF flight data in {}", own.display()));
        }
        fm.set_ground_height(0.0);
        fm.set_fuel(FUEL_KG);
        let ap = Autopilot::new(Config::load(own));
        Ok(Eitam {
            pos,
            heading,
            pitch: 0.0,
            roll: 0.0,
            speed: ORBIT_MPS,
            jet: Box::new((fm, ap)),
            speed_i: 0.0,
            orbit,
            base: orbit,
            alive: true,
            threat: None,
            clear_since: f64::NEG_INFINITY,
            help_at: f64::NEG_INFINITY,
            out: true,
        })
    }

    /// The controller's sensor: its radar where it flies, none once it is down.
    pub fn sensor(&self) -> awacs::Sensor {
        if self.alive { awacs::Sensor::Eitam(self.pos) } else { awacs::Sensor::Lost }
    }

    /// The nearest threatening hostile group its radar sees (its centre and highest contact's height): inside
    /// [`CLOSE_M`], or inside [`THREAT_M`] hot or flank.
    fn threat_of(&self, contacts: &[Contact]) -> Option<(Vec3, f64)> {
        awacs::groups(self.sensor(), self.pos, contacts, |c| c.ident == Ident::Hostile)
            .into_iter()
            .find(|g| {
                let pointing = matches!(awacs::aspect(g.heading, g.pos, self.pos), "AWX_HOT" | "AWX_FLANK");
                g.dist <= CLOSE_M || (g.dist <= THREAT_M && pointing)
            })
            .map(|g| (g.pos, g.top))
    }

    /// One step of `dt` s at `now`: the threat check, then the flight (a retreat straight away from the threat at the
    /// high-speed cruise, else the racetrack at the long-range cruise). The calls due: the call for help to
    /// `callsign` (the player's formation name) at `player` when a threat starts, then every [`HELP_REPEAT_S`] while
    /// it lasts: "Kidon 1, threat, group bearing 040, 30 miles, 25 thousand, Eitam retrograding, commit."
    pub fn step(&mut self, now: f64, dt: f64, contacts: &[Contact], callsign: &str, player: Vec3) -> Vec<Call> {
        let mut calls = Vec::new();
        if !self.alive {
            return calls;
        }
        match self.threat_of(contacts) {
            Some((at, top)) => {
                if self.threat.is_none() {
                    // A new threat pulls the station back from the planned one, away from it.
                    let away = unit_flat(self.base.centre - at);
                    self.orbit.centre = self.base.centre + away * PULL_M;
                }
                self.threat = Some(at);
                self.clear_since = now;
                if now - self.help_at >= HELP_REPEAT_S {
                    self.help_at = now;
                    let b = fctrl::tens(fctrl::bearing(player, at));
                    let m = awacs::miles(flat(player, at));
                    calls.push((
                        "AWX_HELP",
                        vec![
                            format!("{callsign}_r"),
                            format!("BEARING{b:03}"),
                            format!("MILES{m:02}"),
                            format!("AWX_ALT{:02}", awacs::thousands(top)),
                        ],
                        awacs::Named { bearing: b, miles: m, hostile: true },
                    ));
                }
            }
            None if self.threat.is_some() && now - self.clear_since >= CLEAR_S => {
                self.threat = None;
                self.help_at = f64::NEG_INFINITY;
            }
            None => {}
        }
        let (want, speed) = match self.threat {
            Some(at) => (fctrl::bearing(at, self.pos) as f64, RETREAT_MPS),
            None => (self.orbit_heading(), ORBIT_MPS),
        };
        self.fly(dt, want, speed);
        calls
    }

    /// The racetrack: out along the legs to the far end, then back; more than two legs from its centre, straight to
    /// the end of the leg it flies.
    fn orbit_heading(&mut self) -> f64 {
        let o = &self.orbit;
        let s = (self.pos - o.centre).dot(o.along);
        if self.out && s >= LEG_M / 2.0 {
            self.out = false;
        } else if !self.out && s <= -LEG_M / 2.0 {
            self.out = true;
        }
        let end = o.centre + o.along * if self.out { LEG_M / 2.0 } else { -LEG_M / 2.0 };
        // Aim beyond the end along the leg, so the leg is flown along its line and the turn comes at its end.
        let aim = end + o.along * if self.out { LEG_M } else { -LEG_M } * 0.5;
        fctrl::bearing(self.pos, if flat(self.pos, o.centre) > 2.0 * LEG_M { end } else { aim }) as f64
    }

    /// `dt` s of flight towards heading `want` at `speed` m/s and [`ALT_M`]: the autopilot's steer loop to a point
    /// [`AHEAD_M`] along it, turning at [`BANK_DEG`], at most military power, on its 6-DoF in steps of [`STEP_S`].
    fn fly(&mut self, dt: f64, want: f64, speed: f64) {
        let (fm, ap) = &mut *self.jet;
        let h = want.to_radians();
        let to = Vec3::new(self.pos.x + h.sin() * AHEAD_M, self.pos.y + h.cos() * AHEAD_M, ALT_M);
        let g = 1.0 / BANK_DEG.to_radians().cos() as f32;
        let lever = fm.state().throttle;
        if lever > 0.01 && lever < THR_MAX - 0.01 {
            let err = speed - self.speed;
            self.speed_i = (self.speed_i + SPEED_I * err * dt).clamp(-SPEED_I_MAX, SPEED_I_MAX);
        }
        let ask = (speed + self.speed_i) as f32;
        ap.steer = Some(Steer { to, g, speed: ask, thr_max: THR_MAX, fighter: false });
        if ap.mode() != MODE_STEER {
            ap.set_mode(fm, MODE_STEER);
        }
        let n = (dt / STEP_S).ceil().max(0.0) as usize;
        for _ in 0..n {
            ap.step(fm, &|_, _| 0.0);
            fm.step(dt / n as f64);
        }
        let st = fm.state();
        self.pos = st.position;
        self.heading = (st.heading as f64).to_degrees().rem_euclid(360.0);
        self.pitch = (st.pitch as f64).to_degrees();
        self.roll = (st.roll as f64).to_degrees();
        self.speed = st.speed as f64;
    }
}
