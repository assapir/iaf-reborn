//! Modern IAF's Eitam in the sky (docs/ai.md §24.3): the IAF's Gulfstream G550 CAEW as a point mass flying a standoff
//! orbit behind the friendly side, its radar covering the fight; on a threat it retreats and calls for help. The
//! controller's sensor (`awacs::Sensor::Eitam`) is where it flies. World frame X east, Y north, Z up, metres.

use crate::awacs::{self, Contact, Ident};
use crate::flight::flat;
use iaf_avionics::fctrl;
use iaf_flight::Vec3;
use iaf_flight::airframe::Rcs;

const G: f64 = 9.80665;
/// The speed of sound at 41,000 ft (m/s; the standard atmosphere's 295.1 above the tropopause).
const SOUND_41K: f64 = 295.07;
/// The orbit's height: the G550's cruise altitude, 41,000 ft (Wikipedia, Gulfstream G550: "Long Range Cruise: M0.80
/// at 41,000 ft").
pub const ALT_M: f64 = 41_000.0 * 0.3048;
/// On the orbit: the long-range cruise, Mach 0.80; retreating: the high-speed cruise, Mach 0.85 (the same source).
pub const ORBIT_MPS: f64 = 0.80 * SOUND_41K;
pub const RETREAT_MPS: f64 = 0.85 * SOUND_41K;
/// The orbit's bank (degrees; inferred, an airliner's standard turn).
const BANK_DEG: f64 = 25.0;
/// The racetrack's legs, across the axis to the fight (m; inferred).
const LEG_M: f64 = 50_000.0;
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
const PULL_M: f64 = 60_000.0;
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

/// Its radar cross-section: a business jet's, larger than a fighter's from every side (m²; inferred, no public
/// figure).
pub const RCS: Rcs = Rcs { front_m2: 10.0, side_m2: 40.0, rear_m2: 15.0, bays_open_m2: 0.0, store_m2: 0.0 };

/// The Eitam's state.
#[derive(Clone, Debug)]
pub struct Eitam {
    pub pos: Vec3,
    /// Compass heading, degrees.
    pub heading: f64,
    pub speed: f64,
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
    /// On station at the start of its outbound leg.
    pub fn new(orbit: Orbit) -> Eitam {
        let pos = orbit.centre - orbit.along * (LEG_M / 2.0);
        let heading = fctrl::bearing(Vec3::ZERO, orbit.along) as f64;
        Eitam {
            pos,
            heading,
            speed: ORBIT_MPS,
            orbit,
            base: orbit,
            alive: true,
            threat: None,
            clear_since: f64::NEG_INFINITY,
            help_at: f64::NEG_INFINITY,
            out: true,
        }
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

    /// Turn at the rate of [`BANK_DEG`] at this speed towards `want`, accelerate gently towards `speed`, hold [`ALT_M`].
    fn fly(&mut self, dt: f64, want: f64, speed: f64) {
        let rate = (G * BANK_DEG.to_radians().tan() / self.speed).to_degrees();
        let err = (want - self.heading + 540.0).rem_euclid(360.0) - 180.0;
        self.heading = (self.heading + err.clamp(-rate * dt, rate * dt)).rem_euclid(360.0);
        // ponytail: 1 m/s² towards the wanted speed; the G550's thrust and drag are not modelled (no 6-DoF data).
        self.speed += (speed - self.speed).clamp(-dt, dt);
        let h = self.heading.to_radians();
        self.pos += Vec3::new(h.sin(), h.cos(), 0.0) * (self.speed * dt);
        self.pos.z += (ALT_M - self.pos.z).clamp(-10.0 * dt, 10.0 * dt);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const KM: f64 = 1000.0;

    fn mig(key: &str, pos: Vec3, heading: f64) -> Contact {
        Contact { key: key.into(), pos, ground: 0.0, heading, ident: Ident::Hostile, tanker: false }
    }

    /// The distance from `p` to the segment a–b (horizontal).
    fn to_segment(p: Vec3, a: Vec3, b: Vec3) -> f64 {
        let ab = Vec3::new(b.x - a.x, b.y - a.y, 0.0);
        let t = (Vec3::new(p.x - a.x, p.y - a.y, 0.0).dot(ab) / ab.dot(ab)).clamp(0.0, 1.0);
        flat(p, a + ab * t)
    }

    #[test]
    fn the_station_stands_off_the_route_and_covers_the_fight() {
        let area = Vec3::new(0.0, 150.0 * KM, 0.0);
        let home = Vec3::ZERO;
        for start in [Vec3::new(0.0, 90.0 * KM, 6000.0), Vec3::new(0.0, -20.0 * KM, 6000.0)] {
            let o = station(area, home, start);
            let mut e = Eitam::new(o);
            let mut far = 0.0f64;
            let mut near = f64::MAX;
            for i in 0..36_000 {
                e.step(i as f64 * 0.1, 0.1, &[], "Alpha", start);
                far = far.max(flat(e.pos, area));
                near = near.min(to_segment(e.pos, start, area)).min(to_segment(e.pos, home, area));
            }
            // An hour on station: never within 15 km of the flight's way, the fight always inside its radar.
            assert!(near > 15.0 * KM, "near the route: {near}");
            assert!(far < awacs::EITAM_RANGE_M * 0.6, "far from the fight: {far}");
            assert!((e.pos.z - ALT_M).abs() < 1.0 && (e.speed - ORBIT_MPS).abs() < 0.1);
            // It stays round its station.
            assert!(flat(e.pos, o.centre) < LEG_M);
        }
    }

    #[test]
    fn a_threat_sends_it_away_with_a_call_for_help() {
        let o = station(Vec3::new(0.0, 150.0 * KM, 0.0), Vec3::ZERO, Vec3::ZERO);
        let mut e = Eitam::new(o);
        let player = Vec3::new(0.0, 60.0 * KM, 6000.0);
        // A MiG pair 120 km off, pointing at it: not yet (beyond 100 km).
        let here = e.pos;
        let toward = |p: Vec3| fctrl::bearing(p, here) as f64;
        let far = e.pos + Vec3::new(0.0, 120.0 * KM, 7000.0 - ALT_M);
        assert!(e.step(0.0, 0.1, &[mig("a", far, toward(far))], "Alpha", player).is_empty());
        // At 90 km, cold: no threat; hot: the call and the retreat.
        let at = e.pos + Vec3::new(0.0, 90.0 * KM, 7000.0 - ALT_M);
        assert!(e.step(1.0, 0.1, &[mig("a", at, (toward(at) + 180.0) % 360.0)], "Alpha", player).is_empty());
        let pair = [mig("a", at, toward(at)), mig("b", at + Vec3::new(900.0, 0.0, 300.0), toward(at))];
        let calls = e.step(2.0, 0.1, &pair, "Alpha", player);
        assert_eq!(calls.len(), 1);
        let (t, args, named) = &calls[0];
        assert!(named.hostile && named.miles == awacs::miles(flat(player, at)));
        assert_eq!(*t, "AWX_HELP");
        assert_eq!(args[0], "Alpha_r");
        assert_eq!(args[3], "AWX_ALT25");
        let before = o.centre;
        assert!(flat(e.orbit.centre, at) > flat(before, at) + PULL_M * 0.9, "the station pulled back");
        // It turns away and runs at Mach 0.85; the call comes again only after a minute.
        let start = flat(e.pos, at);
        for i in 0..580 {
            assert!(e.step(2.1 + i as f64 * 0.1, 0.1, &pair, "Alpha", player).is_empty());
        }
        assert!((e.speed - RETREAT_MPS).abs() < 0.1, "the high-speed cruise");
        // Quiet up to the minute.
        for t in [60.0, 61.0, 61.9] {
            assert!(e.step(t, 0.1, &pair, "Alpha", player).is_empty());
        }
        assert_eq!(e.step(62.5, 0.1, &pair, "Alpha", player).len(), 1);
        // Two minutes on: turned (at 25° of bank, 1.1°/s) and running, out of the threat's range.
        for i in 0..1200 {
            e.step(62.6 + i as f64 * 0.1, 0.1, &pair, "Alpha", player);
        }
        assert!(flat(e.pos, at) > start + 20.0 * KM, "running away: {}", flat(e.pos, at) - start);
        // Clear for 30 s: back on (the pulled-back) station, at the long-range cruise.
        for i in 0..400 {
            e.step(183.0 + i as f64 * 0.1, 0.1, &[], "Alpha", player);
        }
        assert!(e.threat.is_none());
        // A second threat: the station pulled from the planned one again, never further.
        let pulled = e.orbit.centre;
        let at2 = e.pos + Vec3::new(0.0, 40.0 * KM, 0.0);
        assert_eq!(e.step(230.0, 0.1, &[mig("c", at2, 0.0)], "Alpha", player).len(), 1);
        assert!((flat(e.orbit.centre, o.centre) - PULL_M).abs() < 1.0 && flat(pulled, o.centre) <= PULL_M + 1.0);
        for i in 0..400 {
            e.step(231.0 + i as f64 * 0.1, 0.1, &[], "Alpha", player);
        }
        // Down: no sensor, no calls.
        e.alive = false;
        assert_eq!(e.sensor(), awacs::Sensor::Lost);
        assert!(e.step(300.0, 0.1, &pair, "Alpha", player).is_empty());
    }
}
