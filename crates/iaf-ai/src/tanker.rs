//! The tanker and its boom (modern-iaf/docs/research/air-refuelling.md §7): a KC-46A on its refuelling track, the
//! boom operator who clears the receivers and flies the boom into a receptacle held within the envelope, the pilot
//! director lights, the fuel offload and the disconnects. The tanker flies its racetrack as a path (a real tanker on
//! the track flies its autopilot: a steady platform); the receivers are the player's jet and the AI wingmen
//! (`flight`), flown by their own pilots. Frame: the world's (X east, Y north, Z up, m); a body frame is
//! (forward, right, up). Every figure is the research page's, or inferred where it says so.

use iaf_flight::Vec3;
use iaf_flight::aircraft::Euler;
use iaf_flight::autopilot::Leader;

const G: f64 = 9.80665;
const KT: f64 = NM / 3600.0;
const FT: f64 = 0.3048;
const LB: f32 = 0.453_592_37;
const NM: f64 = 1852.0;
const DEG: f64 = std::f64::consts::PI / 180.0;

/// One tanker type's figures (research §8.1).
#[derive(Debug, Clone, Copy)]
pub struct Spec {
    /// The boom's hinge in the tanker's body frame (forward, right, up), m: the model's `boom_pivot`
    /// (tools/tanker/build.py).
    pub pivot: [f64; 3],
    /// The fixed tube's length to the telescope's root, m, and the telescope's travel (min, max), m.
    pub boom_len: f64,
    pub ext: (f64, f64),
    /// The elevation below the tanker's horizontal (min, max), rad, and the azimuth either side, rad: the envelope a
    /// contact is held in.
    pub elev: (f64, f64),
    pub az: f64,
    /// The offload, kg/s.
    pub offload: f32,
}

impl Spec {
    /// The contact position: the envelope's elevation of 30° and the telescope's middle.
    pub fn contact(&self) -> (f64, f64) {
        (30f64.to_radians(), (self.ext.0 + self.ext.1) / 2.0)
    }
}

/// The KC-46A Gideon: its boom 57.5 ft at full extension, the KC-10's telescope (6 to 21 ft), 3,000 lb a minute.
pub const KC46: Spec = Spec {
    pivot: [-20.6, 0.0, -0.6],
    boom_len: (57.5 - 21.0) * FT,
    ext: (6.0 * FT, 21.0 * FT),
    elev: (25.0 * DEG, 40.0 * DEG),
    az: 10.0 * DEG,
    offload: 3000.0 * LB / 60.0,
};

/// The 707 Re'em: the KC-135's boom, 47 ft at full extension, its telescope 6 to 18 ft, 2,000 lb a minute.
pub const REEM: Spec = Spec {
    pivot: [-19.0, 0.0, -0.5],
    boom_len: (47.0 - 18.0) * FT,
    ext: (6.0 * FT, 18.0 * FT),
    elev: (25.0 * DEG, 40.0 * DEG),
    az: 10.0 * DEG,
    offload: 2000.0 * LB / 60.0,
};

/// The track (research §4): 310 KCAS at 30,000 ft, 480 kt true (ISA), m/s; the height, m; the legs' length and
/// the distance between them, m.
pub const TRACK_SPEED: f64 = 480.0 * KT;
pub const TRACK_ALT: f64 = 30_000.0 * FT;
pub const TRACK_LEG: f64 = 50.0 * NM;
pub const TRACK_APART: f64 = 20.0 * NM;

/// Pre-contact: this far behind and below the contact point along the tanker's axes, m (about 50 ft behind the boom's
/// nozzle and a little below it), held within `.2` m for `.3` s at under `.4` m/s relative.
pub const PRECONTACT: (f64, f64, f64, f64, f64) = (15.0, 3.0, 6.0, 2.0, 1.0);
/// The boom's rates: elevation and azimuth, rad/s; the telescope, m/s (inferred).
pub const RATE: (f64, f64) = (6.0 * DEG, 1.5);
/// The boom reaches for a receptacle within `.0` m of the contact position closing at under `.2` m/s (the receiver
/// stabilised there, research §4), and makes contact within `.1` m of it (inferred).
pub const REACH: (f64, f64, f64) = (1.5, 0.15, 0.5);
/// Breakaway: the receptacle this far inside the telescope's shortest, m, or this far above the boom's highest, rad.
pub const BREAKAWAY: (f64, f64) = (1.5, 5.0 * std::f64::consts::PI / 180.0);
/// After a breakaway the receiver is cleared again once it is this far behind the contact point, m.
pub const CLEAR_AFT: f64 = 30.0;
/// A receiver cleared to contact closes on it at this rate, m/s (2–3 kt, research §4); an AI receiver's station moves
/// from pre-contact to contact at it.
pub const CLOSURE: f64 = 2.5 * KT;
/// A receiver with room for less than this is full, kg (its last refuel valve closed: the boom unlatches, research
/// §5; the engine burns while it takes fuel, so the room never stays at zero).
pub const FULL_KG: f32 = 5.0;
/// The first in the queue not cleared to contact this long after its turn came (it turned away to fight, or is still
/// far off), s, while others wait: it goes to the back of the queue and the next is cleared (inferred).
pub const HEAD_WAIT_S: f64 = 300.0;

/// The tanker's pose.
#[derive(Debug, Clone, Copy, Default)]
pub struct Pose {
    pub pos: Vec3,
    pub vel: Vec3,
    /// Pitch, roll (right wing down +), heading (clockwise from north), rad.
    pub att: [f64; 3],
}

impl Pose {
    /// The body frame's axes in the world (forward, right, up).
    pub fn axes(&self) -> [Vec3; 3] {
        let [pitch, roll, heading] = self.att.map(|a| a as f32);
        let (f, r, u) = Euler { pitch, roll, heading }.basis();
        [f, r, u]
    }

    /// The pose as a leader of the autopilot's slot loop.
    pub fn leader(&self) -> Leader {
        Leader { pos: self.pos, vel: self.vel, att: self.att.map(|a| a as f32), active: true }
    }

    /// A body point (forward, right, up) in the world.
    pub fn to_world(&self, b: [f64; 3]) -> Vec3 {
        let [f, r, u] = self.axes();
        self.pos + f * b[0] + r * b[1] + u * b[2]
    }

    /// A world point in the body frame.
    pub fn to_body(&self, w: Vec3) -> [f64; 3] {
        let [f, r, u] = self.axes();
        let d = w - self.pos;
        [d.dot(f), d.dot(r), d.dot(u)]
    }
}

/// The racetrack (research §4): the inbound leg starts at `anchor` on `course` (rad from north); left turns.
#[derive(Debug, Clone, Copy)]
pub struct Track {
    pub anchor: Vec3,
    pub course: f64,
    pub leg: f64,
    pub radius: f64,
    pub speed: f64,
    pub bank: f64,
}

impl Track {
    /// The standard track from `anchor` (its height taken from [`TRACK_ALT`]) on `course`.
    pub fn new(anchor: Vec3, course: f64) -> Self {
        let radius = TRACK_APART / 2.0;
        let speed = TRACK_SPEED;
        let bank = (speed * speed / (G * radius)).atan();
        Track { anchor: Vec3::new(anchor.x, anchor.y, TRACK_ALT), course, leg: TRACK_LEG, radius, speed, bank }
    }

    pub fn length(&self) -> f64 {
        2.0 * self.leg + 2.0 * std::f64::consts::PI * self.radius
    }

    /// The pose `s` m along the loop (wrapped). The bank is the turn's on the turns, eased in and out at 5° a second
    /// at their ends (inferred).
    pub fn at(&self, s: f64) -> Pose {
        use std::f64::consts::{PI, TAU};
        let s = s.rem_euclid(self.length());
        let turn = PI * self.radius;
        let dir = |h: f64| Vec3::new(h.sin(), h.cos(), 0.0);
        let left = |h: f64| Vec3::new(-h.cos(), h.sin(), 0.0);
        let c = self.course;
        let (pos, heading, into) = if s < self.leg {
            (self.anchor + dir(c) * s, c, None)
        } else if s < self.leg + turn {
            let a = (s - self.leg) / self.radius;
            let centre = self.anchor + dir(c) * self.leg + left(c) * self.radius;
            (centre - left(c - a) * self.radius, c - a, Some(s - self.leg))
        } else if s < 2.0 * self.leg + turn {
            let d = s - self.leg - turn;
            let start = self.anchor + dir(c) * self.leg + left(c) * (2.0 * self.radius);
            (start + dir(c + PI) * d, c + PI, None)
        } else {
            let a = (s - 2.0 * self.leg - turn) / self.radius;
            let centre = self.anchor + left(c) * self.radius;
            let h = c + PI - a;
            (centre - left(h) * self.radius, h, Some(s - 2.0 * self.leg - turn))
        };
        let ease = self.speed * self.bank / (5.0 * DEG);
        let bank = into.map_or(0.0, |d| -self.bank * (d / ease).min((turn - d) / ease).clamp(0.0, 1.0));
        let vel = dir(heading) * self.speed;
        // A level jet flies a few degrees nose up (inferred: 3°, a cruise α).
        Pose { pos, vel, att: [3.0 * DEG, bank, heading.rem_euclid(TAU)] }
    }
}

/// The boom's state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Boom {
    /// Up against the tail: no receiver.
    Stowed,
    /// Down at the contact position's angles, waiting.
    Trail,
    /// Flying to a cleared receiver's receptacle.
    Flying,
    /// Latched in a receptacle: fuel flows.
    Contact,
}

/// A receiver this frame: its id (the flight's number: 1 the player's lead), its receptacle's world point and the jet's
/// velocity, its door open (the receptacle ready), the fuel it has room for, kg, and the pilot's disconnect button.
#[derive(Debug, Clone, Copy)]
pub struct Receiver {
    pub id: u32,
    pub receptacle: Vec3,
    pub vel: Vec3,
    pub door: bool,
    pub room_kg: f32,
    pub disconnect: bool,
}

/// What the tanker says or does (the radio calls and the receivers' lamps).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Event {
    /// To the receiver: cleared to the pre-contact position (its request granted).
    ClearedPrecontact(u32),
    /// The boom is busy: hold on the left wing (the observation position).
    StandBy(u32),
    /// Stable in pre-contact with the door open: cleared to contact.
    ClearedContact(u32),
    /// Latched (the receiver's AR/NWS lamp).
    Contact(u32),
    /// Unlatched: by limits, by the receiver's button, or the receiver full (the DISC lamp).
    Disconnect(u32),
    /// Too close or too high under the tanker: breakaway (the receiver drops back).
    Breakaway(u32),
    /// The offload is done: kg given; cleared to the right wing.
    Complete(u32, f32),
}

/// The wing positions (forward, right, up) m in the tanker's body frame: the observation position on the left wing
/// and the reform on the right one, past the wingtips; each further jet waiting or done `WING_STEP` further out and
/// back, in echelon (inferred).
pub const OBSERVATION: [f64; 3] = [-8.0, -40.0, -3.0];
pub const REFORM: [f64; 3] = [-8.0, 40.0, -3.0];
pub const WING_STEP: [f64; 3] = [-15.0, 25.0, -3.0];

/// The `k`-th jet's wing position from `first` (the left wing's steps go left).
fn echelon(first: [f64; 3], k: usize) -> [f64; 3] {
    let side = first[1].signum();
    let k = k as f64;
    [first[0] + WING_STEP[0] * k, first[1] + side * WING_STEP[1] * k, first[2] + WING_STEP[2] * k]
}

/// Where a receiver in the queue is to fly ([`Tanker::station`]).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Station {
    /// Its receptacle on this body point: pre-contact, contact.
    Receptacle([f64; 3]),
    /// The jet on this body point: the observation or the reform position.
    Wing([f64; 3]),
}

/// The tanker.
#[derive(Debug, Clone)]
pub struct Tanker {
    pub spec: Spec,
    pub track: Track,
    /// Distance flown along the track, m.
    pub s: f64,
    pub boom: Boom,
    /// The boom's elevation, azimuth (+ right), rad, and the telescope's extension, m.
    pub angles: [f64; 3],
    /// The receivers that asked, in order; the first is the one on the boom.
    pub queue: Vec<u32>,
    /// The receivers done (on the right wing until they leave).
    pub done: Vec<u32>,
    /// The first in the queue: cleared to contact; broken away (cleared again once back).
    cleared: bool,
    /// When it was cleared (s).
    cleared_at: f64,
    /// When the first in the queue got its turn.
    head_at: f64,
    broke_away: bool,
    stable_since: Option<f64>,
    /// The fuel given to the first in the queue, kg.
    pub given: f32,
    /// Why the last disconnect came (for the logs): "limits" with the boom's angles there, "button", "door", "full".
    pub why: String,
    /// The pilot director lights: (elevation, telescope), each −2..=2, 0 in position; elevation + the receiver is
    /// high (fly down, D), telescope + it is forward (fly aft, A). None: dark.
    pub pdl: Option<(i8, i8)>,
    t: f64,
}

/// The body point's distance to another, m.
fn gap(a: [f64; 3], b: [f64; 3]) -> f64 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}

impl Tanker {
    pub fn new(spec: Spec, track: Track) -> Self {
        Tanker {
            spec,
            track,
            s: 0.0,
            boom: Boom::Stowed,
            angles: [0.0, 0.0, spec.ext.0],
            queue: Vec::new(),
            done: Vec::new(),
            cleared: false,
            cleared_at: 0.0,
            head_at: 0.0,
            broke_away: false,
            stable_since: None,
            given: 0.0,
            why: String::new(),
            pdl: None,
            t: 0.0,
        }
    }

    pub fn pose(&self) -> Pose {
        self.track.at(self.s)
    }

    /// The boom's nozzle in the body frame for boom angles `a`.
    fn tip_body(&self, a: [f64; 3]) -> [f64; 3] {
        let [e, z, x] = a;
        let l = self.spec.boom_len + x;
        let pv = self.spec.pivot;
        [pv[0] - l * e.cos() * z.cos(), pv[1] + l * e.cos() * z.sin(), pv[2] - l * e.sin()]
    }

    /// The nozzle in the world.
    pub fn nozzle(&self) -> Vec3 {
        self.pose().to_world(self.tip_body(self.angles))
    }

    /// The boom angles that put the nozzle on body point `b` (unclamped).
    fn angles_to(&self, b: [f64; 3]) -> [f64; 3] {
        let pv = self.spec.pivot;
        let d = [pv[0] - b[0], b[1] - pv[1], pv[2] - b[2]];
        let l = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
        [d[2].atan2(d[0].hypot(d[1])), d[1].atan2(d[0]), l - self.spec.boom_len]
    }

    /// The contact position (the nozzle at the contact angles) in the body frame.
    pub fn contact_body(&self) -> [f64; 3] {
        let (e, x) = self.spec.contact();
        self.tip_body([e, 0.0, x])
    }

    /// The pre-contact position in the body frame.
    pub fn precontact_body(&self) -> [f64; 3] {
        let c = self.contact_body();
        [c[0] - PRECONTACT.0, c[1], c[2] - PRECONTACT.1]
    }

    /// A receiver asks to refuel (its radio call): cleared to pre-contact when it is first, else stand by on the left
    /// wing. A receiver done asks again: it goes to the back of the queue.
    pub fn request(&mut self, id: u32) -> Event {
        self.done.retain(|&d| d != id);
        if !self.queue.contains(&id) {
            self.queue.push(id);
            // The head's clock starts with its turn, and again once another waits behind it (the timeout counts only
            // while others wait).
            if self.queue.len() <= 2 {
                self.head_at = self.t;
            }
        }
        if self.queue[0] == id { Event::ClearedPrecontact(id) } else { Event::StandBy(id) }
    }

    /// The receiver leaves (it flew away, or is lost): out of the queue and the done list; a contact ends
    /// (Disconnect) and the next is cleared.
    pub fn leave(&mut self, id: u32) -> Vec<Event> {
        self.done.retain(|&d| d != id);
        if self.queue.first() == Some(&id) {
            return self.next();
        }
        self.queue.retain(|&q| q != id);
        Vec::new()
    }

    /// The first in the queue is through: a boom still in its receptacle unlatches (Disconnect), the next one is
    /// cleared to pre-contact.
    fn next(&mut self) -> Vec<Event> {
        let mut ev = Vec::new();
        let head = (!self.queue.is_empty()).then(|| self.queue.remove(0));
        (self.cleared, self.broke_away, self.stable_since, self.given) = (false, false, None, 0.0);
        self.head_at = self.t;
        if self.boom == Boom::Contact {
            self.boom = Boom::Trail;
            ev.extend(head.map(Event::Disconnect));
        }
        ev.extend(self.queue.first().map(|&n| Event::ClearedPrecontact(n)));
        ev
    }

    /// Where receiver `id` is to fly now: its receptacle at contact once cleared (pre-contact after a breakaway), at
    /// pre-contact when first, the jet on the left wing while it waits, on the right wing once done; None for a
    /// receiver the tanker does not know.
    pub fn station(&self, id: u32) -> Option<Station> {
        if let Some(k) = self.done.iter().position(|&d| d == id) {
            return Some(Station::Wing(echelon(REFORM, k)));
        }
        let (pre, c) = (self.precontact_body(), self.contact_body());
        match self.queue.iter().position(|&q| q == id)? {
            0 if self.broke_away => Some(Station::Receptacle([c[0] - CLEAR_AFT - 5.0, pre[1], pre[2] - 3.0])),
            0 if self.cleared => {
                let k = ((self.t - self.cleared_at) * CLOSURE / gap(pre, c)).min(1.0);
                Some(Station::Receptacle([0, 1, 2].map(|i| pre[i] + (c[i] - pre[i]) * k)))
            }
            0 => Some(Station::Receptacle(pre)),
            k => Some(Station::Wing(echelon(OBSERVATION, k - 1))),
        }
    }

    /// AI receiver `id`'s slot now, for the autopilot's slot loop on [`Pose::leader`]: (forward, right, up) m in the
    /// tanker's horizontal frame (`autopilot::slot_point`) of the jet whose receptacle sits `receptacle` (forward,
    /// right, up) m from its centre (the jet taken level on the tanker's heading); None: not in the queue or done.
    pub fn slot(&self, id: u32, receptacle: [f64; 3]) -> Option<[f32; 3]> {
        let p = self.pose();
        let (b, off) = match self.station(id)? {
            Station::Receptacle(b) => (b, receptacle),
            Station::Wing(b) => (b, [0.0; 3]),
        };
        let d = p.to_world(b) - p.pos;
        let h = p.vel.x.atan2(p.vel.y);
        let (fwd, right) = (Vec3::new(h.sin(), h.cos(), 0.0), Vec3::new(h.cos(), -h.sin(), 0.0));
        Some([(d.dot(fwd) - off[0]) as f32, (d.dot(right) - off[1]) as f32, (d.z - off[2]) as f32])
    }

    /// One frame of `dt` s: the boom operator works the first receiver in the queue (the receivers as they are at the
    /// tanker's [`Tanker::pose`] now), then the tanker flies on. Returns the calls and the fuel given (receiver, kg).
    pub fn step(&mut self, dt: f64, receivers: &[Receiver]) -> (Vec<Event>, Option<(u32, f32)>) {
        let out = self.work(dt, receivers);
        self.advance(dt);
        out
    }

    /// The tanker flies on `dt` s.
    pub fn advance(&mut self, dt: f64) {
        self.t += dt;
        self.s += self.track.speed * dt;
    }

    /// The boom operator's frame of `dt` s with the receivers as they are at the tanker's [`Tanker::pose`] now.
    pub fn work(&mut self, dt: f64, receivers: &[Receiver]) -> (Vec<Event>, Option<(u32, f32)>) {
        self.pdl = None;
        let mut ev = Vec::new();
        let Some(&id) = self.queue.first() else {
            self.move_boom(dt, None);
            return (ev, None);
        };
        let Some(rx) = receivers.iter().find(|r| r.id == id) else {
            // The first in the queue is gone (lost, out of reach): the next one is cleared.
            ev.extend(self.next());
            self.move_boom(dt, None);
            return (ev, None);
        };
        let pose = self.pose();
        let b = pose.to_body(rx.receptacle);
        let target = self.angles_to(b);
        let (ce, cx) = self.spec.contact();
        let c = self.contact_body();
        // The PDLs while the receiver is behind the tanker, from pre-contact in.
        if c[0] - b[0] < PRECONTACT.0 + 5.0 && b[0] < c[0] + 10.0 && b[1].abs() < 10.0 {
            let step = |x: f64, s: f64| (x / s).round().clamp(-2.0, 2.0) as i8;
            self.pdl = Some((step(ce - target[0], 2.5 * DEG), step(cx - target[2], 0.9)));
        }
        if self.broke_away {
            if c[0] - b[0] > CLEAR_AFT {
                (self.broke_away, self.cleared, self.stable_since) = (false, false, None);
                ev.push(Event::ClearedPrecontact(id));
            }
            self.move_boom(dt, None);
            return (ev, None);
        }
        let near = (b[0] - c[0]).abs() < 10.0 && b[1].abs() < 10.0;
        let too_close = target[2] < self.spec.ext.0 - BREAKAWAY.0 || target[0] < self.spec.elev.0 - BREAKAWAY.1;
        if self.cleared && near && too_close {
            if self.boom == Boom::Contact {
                ev.push(Event::Disconnect(id));
            }
            self.broke_away = true;
            ev.push(Event::Breakaway(id));
            self.move_boom(dt, None);
            return (ev, None);
        }
        if self.boom == Boom::Contact {
            if self.inside(target) && !rx.disconnect && rx.door && rx.room_kg > FULL_KG {
                self.angles = target;
                let kg = (self.spec.offload * dt as f32).min(rx.room_kg);
                self.given += kg;
                return (ev, Some((id, kg)));
            }
            self.why = if rx.room_kg <= FULL_KG {
                "full".into()
            } else if rx.disconnect {
                "button".into()
            } else if !rx.door {
                "door".into()
            } else {
                let d = target.map(|a| a as f32);
                format!(
                    "limits: elevation {:.1}° azimuth {:.1}° extension {:.2} m",
                    d[0].to_degrees(),
                    d[1].to_degrees(),
                    d[2]
                )
            };
            // Unlatched: back to pre-contact, to be cleared again (research §4).
            (self.boom, self.cleared, self.stable_since) = (Boom::Trail, false, None);
            ev.push(Event::Disconnect(id));
            if rx.room_kg <= FULL_KG {
                ev.push(Event::Complete(id, self.given));
                self.done.push(id);
                ev.extend(self.next());
            }
            self.move_boom(dt, None);
            return (ev, None);
        }
        if !self.cleared && self.queue.len() > 1 && self.t - self.head_at > HEAD_WAIT_S {
            // Its turn lapsed: to the back of the queue, the next one cleared.
            self.queue.push(id);
            ev.push(Event::StandBy(id));
            ev.extend(self.next());
            self.move_boom(dt, None);
            return (ev, None);
        }
        if !self.cleared {
            let p = self.precontact_body();
            let held =
                (0..3).all(|i| (b[i] - p[i]).abs() < PRECONTACT.2) && (rx.vel - pose.vel).length() < PRECONTACT.4;
            if held && rx.door {
                let since = *self.stable_since.get_or_insert(self.t);
                if self.t - since >= PRECONTACT.3 {
                    (self.cleared, self.cleared_at) = (true, self.t);
                    ev.push(Event::ClearedContact(id));
                }
            } else {
                self.stable_since = None;
            }
            self.move_boom(dt, None);
            return (ev, None);
        }
        let steady = (rx.vel - pose.vel).length() < REACH.2 || self.boom == Boom::Flying;
        if self.inside(target) && rx.door && gap(c, b) < REACH.0 && steady {
            self.boom = Boom::Flying;
            self.move_boom(dt, Some(target));
            if gap(pose.to_body(self.nozzle()), b) < REACH.1 {
                self.boom = Boom::Contact;
                self.angles = target;
                ev.push(Event::Contact(id));
            }
        } else {
            self.move_boom(dt, None);
        }
        (ev, None)
    }

    /// Boom angles within the envelope.
    fn inside(&self, a: [f64; 3]) -> bool {
        let s = &self.spec;
        a[0] >= s.elev.0 && a[0] <= s.elev.1 && a[1].abs() <= s.az && a[2] >= s.ext.0 && a[2] <= s.ext.1
    }

    /// The boom moves at its rates toward `to` (a receptacle's angles, clamped to the envelope); without one to the
    /// trail position (the contact elevation, the telescope in) while a receiver waits, else stowed.
    fn move_boom(&mut self, dt: f64, to: Option<[f64; 3]>) {
        let s = self.spec;
        let goal = match to {
            Some(a) => [a[0].clamp(s.elev.0, s.elev.1), a[1].clamp(-s.az, s.az), a[2].clamp(s.ext.0, s.ext.1)],
            None => [if self.queue.is_empty() { 0.0 } else { s.contact().0 }, 0.0, s.ext.0],
        };
        if to.is_none() {
            self.boom = if self.queue.is_empty() { Boom::Stowed } else { Boom::Trail };
        }
        let mv = |x: f64, g: f64, r: f64| x + (g - x).clamp(-r * dt, r * dt);
        self.angles = [
            mv(self.angles[0], goal[0], RATE.0),
            mv(self.angles[1], goal[1], RATE.0),
            mv(self.angles[2], goal[2], RATE.1),
        ];
    }
}
