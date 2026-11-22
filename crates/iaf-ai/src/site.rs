//! Modern IAF's air-defence sites (docs/ai.md §15; modern-iaf/docs/ai-plan.md K5, K7): an S-300PMU-2 battery, a
//! Tor-M1 and a ZSU-23-4 with the crews' procedure of modern-iaf/docs/research/enemies.md §2.3–§2.6, §3.1 and §5.2.
//! A plain state machine per site (one fixed procedure needs no behaviour tree): the site is Ready (silent or
//! searching), and each of its channels takes one target through Acquire → Track → launch → Guide → assess; after the
//! engagement it ceases, marches, moves to its next position and sets up. Detection and tracking scale with the
//! target's radar cross-section and need terrain line of sight over the earth's curvature. The crew's skill
//! (`skill`, §17) sets its reaction, its drills, its gun's laying error and how deep in the envelope it fires. The
//! caller (`shared/ai/air_defence.gd`) fires through the existing weapons; no mission uses a site yet.

use crate::skill::Skill;
use iaf_avionics::radar::{line_of_sight, reach, sigma};
use iaf_flight::Vec3;
use iaf_flight::airframe::Rcs;

/// A jet without an `rcs` (the 1998 types, the drones): an untreated fighter at the reference size (inferred).
pub const FIGHTER: Rcs = Rcs { front_m2: 5.0, side_m2: 25.0, rear_m2: 12.5, bays_open_m2: 0.0, store_m2: 0.5 };
/// The earth's radius (m) and the standard refraction's 4/3 earth radius for the radar horizon (inferred standard).
const EARTH_R: f64 = 6_371_000.0;
const REFRACTION: f64 = 4.0 / 3.0;
/// The quiet time after the last track ends before the crew ceases fire and moves (s, inferred).
const CEASE: f64 = 20.0;
/// The 30N6E2 on its optional 40V6M tower (enemies.md §2.3): the antenna's height (m, inferred).
pub const MAST: f64 = 25.0;
/// The Tor's duty limits (enemies.md §2.6): 10 min on, 10 min off; after three engagements at least an hour off, in
/// which it may be switched on once for one minute to fire.
const DUTY_ON: f64 = 600.0;
const DUTY_OFF: f64 = 600.0;
const BREAK_AFTER: u32 = 3;
const BREAK: f64 = 3600.0;
const BREAK_WINDOW: f64 = 60.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    S300,
    Tor,
    Zsu,
}

/// Emission control (enemies.md §5.2), the caller's choice per site: Radiate searches all the time; Silent never
/// radiates (a gun lays optically); Cue keeps the radars off until a cued target (the network's track, §11-35) is
/// seconds from the launch envelope, then the track radar comes on to acquire it and fire (§11-134). A radar track
/// the cue is taken from ends unless its salvo flies (the network handed the target over, `net`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Emcon {
    Radiate,
    Silent,
    Cue,
}

/// One vehicle of a site.
#[derive(Clone, Copy, Debug)]
pub struct Part {
    /// Its placed name: a radar's holds "RADAR" (the RWR's and HARM's class-8 rule, `harm.rs` `radar_class`).
    pub name: &'static str,
    pub search: bool,
    pub track: bool,
    pub rounds: u32,
    /// The antenna's height above the ground (m).
    pub antenna: f64,
    /// Where it stands from the site's centre (m): right, ahead. No source gives the distances (inferred).
    pub at: [f64; 2],
}

/// A site type's make-up and the figures of its procedure.
#[derive(Clone, Copy, Debug)]
pub struct Spec {
    /// The RWR's symbol (modern-iaf/docs/threat-records.md §3: the 1998 code of the closest system).
    pub type_code: i64,
    /// 8 a radar SAM, 10 a gun (iaf-tools `sim.rs` classes).
    pub class: i64,
    pub parts: &'static [Part],
    /// The search and track radars' reach against `radar::REF_RCS` (m).
    pub search_reach: f64,
    pub track_reach: f64,
    /// The optical sight's reach (m), 0 without one.
    pub optical: f64,
    /// Ground clutter (docs/ai.md §15.3): the radars lose a target slower than this along the line of sight (m/s, the
    /// pulse-Doppler rejection speed; 0: none) or lower than `floor` above the ground (m; 0: none).
    pub reject: f64,
    pub floor: f64,
    /// Targets engaged at once.
    pub channels: usize,
    /// Missiles per target (a gun: rounds per burst).
    pub salvo: u32,
    /// Time between launches across the site (a gun: between bursts), s.
    pub spacing: f64,
    pub gun: bool,
    /// From designation to a track (s).
    pub acquire: f64,
    /// From cease to moving (s).
    pub march: f64,
    /// From a halt at the new position to search (s).
    pub setup: f64,
    /// Road speed (m/s).
    pub speed: f64,
    pub searches_moving: bool,
    pub fires_moving: bool,
    /// The stop before a shot when it cannot fire on the move (s).
    pub halt: f64,
    /// The Tor's duty limits.
    pub duty: bool,
}

const S300_PARTS: &[Part] = &[
    // The antennas' heights on their vehicles: inferred.
    Part { name: "96L6E RADAR", search: true, track: false, rounds: 0, antenna: 6.0, at: [0.0, -300.0] },
    Part { name: "30N6E2 RADAR", search: false, track: true, rounds: 0, antenna: 8.0, at: [0.0, 0.0] },
    // Four launchers round the engagement radar's berm (enemies.md §2.3), four rounds each.
    Part { name: "5P85TE2", search: false, track: false, rounds: 4, antenna: 0.0, at: [-150.0, 150.0] },
    Part { name: "5P85TE2", search: false, track: false, rounds: 4, antenna: 0.0, at: [150.0, 150.0] },
    Part { name: "5P85TE2", search: false, track: false, rounds: 4, antenna: 0.0, at: [-150.0, -150.0] },
    Part { name: "5P85TE2", search: false, track: false, rounds: 4, antenna: 0.0, at: [150.0, -150.0] },
];
// The radar on the turret, 5.1 m high raised (enemies.md §2.5); eight rounds.
const TOR_PARTS: &[Part] =
    &[Part { name: "9A331 TOR RADAR", search: true, track: true, rounds: 8, antenna: 5.0, at: [0.0, 0.0] }];
// The dish on the turret (inferred height); about 2,000 rounds (enemies.md §3.1).
const ZSU_PARTS: &[Part] =
    &[Part { name: "ZSU-23-4", search: true, track: true, rounds: 2000, antenna: 3.5, at: [0.0, 0.0] }];

const S300: Spec = Spec {
    type_code: 310,
    class: 8,
    parts: S300_PARTS,
    search_reach: 300_000.0, // the 96L6E's 5–300 km (missilery.info)
    track_reach: 200_000.0,  // the 30N6E2: open; the record's 200 km held (threat-records.md)
    optical: 0.0,
    reject: 0.0, // the radars' processing: open
    floor: 0.0,
    channels: 6,  // six targets at once (FAS)
    salvo: 2,     // two missiles per target (FAS)
    spacing: 3.0, // 3 s; FAS's "three per second" conflicts (enemies.md §2.4)
    gun: false,
    acquire: 5.0, // inferred
    march: 300.0, // inferred: the set-up's 5 min taken for the march order too
    setup: 300.0, // "five minutes to deploy once it comes to the halt" (FAS)
    speed: 10.0,  // inferred: a tractor and semi-trailer on roads
    searches_moving: false,
    fires_moving: false,
    halt: 0.0,
    duty: false,
};

const TOR: Spec = Spec {
    type_code: 330,
    class: 8,
    parts: TOR_PARTS,
    search_reach: 25_000.0, // F-band search 25 km (threats.md §2)
    track_reach: 20_000.0,  // G/H-band track 20 km (threats.md §2)
    optical: 0.0,
    reject: 30.0, // both radars pulse-Doppler (Wikipedia); the speed inferred
    floor: 0.0,
    channels: 2, // two targets at once (enemies.md §2.6)
    salvo: 2,    // one or two missiles, about 4 s apart: two taken
    spacing: 4.0,
    gun: false,
    acquire: 3.0, // inferred
    march: 10.0,  // inferred: the antenna folded, then off
    setup: 0.0,   // it searches on the move
    speed: 8.0,   // inferred: a tracked vehicle across country
    searches_moving: true,
    fires_moving: false, // fires only at a halt
    halt: 5.0,           // inferred
    duty: true,
};

const ZSU: Spec = Spec {
    type_code: 360,
    class: 10,
    parts: ZSU_PARTS,
    search_reach: 20_000.0, // the RPK-2's 20 km (threats.md §2)
    track_reach: 20_000.0,
    optical: 5_000.0, // inferred: the optical sight's useful reach
    reject: 0.0,      // the radar's processing: open
    floor: 60.0,      // "many false returns (ground clutter) under 60 m" (Wikipedia)
    channels: 1,      // stays on one target (§11-132)
    salvo: 10,        // "2-3 rounds per barrel" × 4 (FAS's text; its table's 30 conflicts)
    spacing: 3.0,     // inferred
    gun: true,
    acquire: 2.0, // inferred
    march: 5.0,   // inferred
    setup: 0.0,
    speed: 8.0, // inferred
    searches_moving: true,
    fires_moving: true, // it fires on the move (§11-70)
    halt: 0.0,
    duty: false,
};

impl Kind {
    pub fn spec(self) -> &'static Spec {
        match self {
            Kind::S300 => &S300,
            Kind::Tor => &TOR,
            Kind::Zsu => &ZSU,
        }
    }

    pub fn from_name(name: &str) -> Option<Kind> {
        match name {
            "s300" => Some(Kind::S300),
            "tor" => Some(Kind::Tor),
            "zsu" => Some(Kind::Zsu),
            _ => None,
        }
    }
}

/// A jet the site may engage (the caller passes only the hostile ones alive).
#[derive(Clone, Debug)]
pub struct Target {
    pub id: String,
    pub pos: Vec3,
    pub vel: Vec3,
    /// Its nose direction.
    pub nose: Vec3,
    pub rcs: Rcs,
    pub bays_open: bool,
    /// Loaded external stations.
    pub stores: u32,
    /// The network cues it (EMCON Cue).
    pub cued: bool,
    /// The caller's launch envelope from the site (m: max, min): `Missile.dlz` from a launcher, a gun's range.
    pub dlz: (f64, f64),
    /// The site's missiles flying at it.
    pub in_air: u32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Mode {
    /// In place: silent or searching by its EMCON.
    Ready,
    /// The march order until the time; radars off.
    March(f64),
    /// Driving to its next position.
    Move,
    /// Setting up until the time; radars off.
    Setup(f64),
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Stage {
    /// The track radar looks for the designated target until the time.
    Acquire(f64),
    /// Locked; launches when inside the envelope.
    Track,
    /// The salvo flies; the track holds until its missiles end.
    Guide,
}

#[derive(Clone, Debug)]
pub struct Channel {
    pub target: String,
    pub stage: Stage,
    /// Missiles of this salvo launched.
    pub fired: u32,
    /// Tracked by radar (a lock on the RWR); false: laid optically.
    pub radar: bool,
    /// Its salvo counted as an engagement (a refund takes it back).
    pub counted: bool,
}

/// A tick's result.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Out {
    /// The search radar radiates.
    pub search: bool,
    /// The track radar radiates.
    pub track: bool,
    /// The targets locked by radar.
    pub tracks: Vec<String>,
    /// Missiles to launch: (part, target).
    pub launches: Vec<(usize, String)>,
    /// Gun bursts: (part, target, rounds, the laying error in rad: across the line of sight, up).
    pub bursts: Vec<(usize, String, u32, [f64; 2])>,
}

#[derive(Clone, Debug)]
pub struct Site {
    pub kind: Kind,
    /// The crew's.
    pub skill: Skill,
    pub emcon: Emcon,
    /// The network commands it (`net::Net`): it runs Cue whatever its own `emcon`, which holds again once the network
    /// is lost.
    pub net: bool,
    /// The 30N6E2 on its tower.
    pub mast: bool,
    /// Where it was placed, then its alternate positions (§11-121: two or three).
    pub positions: Vec<Vec3>,
    /// The position it holds or drives to.
    pub at: usize,
    /// Its centre now, on the ground (the placed height where the terrain has none).
    pub pos: Vec3,
    /// The layout's heading, degrees from north, clockwise.
    pub heading: f64,
    /// The vehicles' heading on the move (their travel bearing); the layout's in place.
    pub course: f64,
    pub mode: Mode,
    /// Rounds left per part.
    pub rounds: Vec<u32>,
    pub channels: Vec<Channel>,
    /// Salvos fired since the last break (the Tor's break counts them; none counted in a break's window).
    pub engagements: u32,
    next_shot: f64,
    /// Launches and bursts at this position (a refund takes one back).
    fired_here: u32,
    quiet_since: f64,
    last: f64,
    on_since: Option<f64>,
    /// The radars forced off until then (the Tor's duty limits); a break may open one window, until `window_until`.
    off_until: f64,
    window_ok: bool,
    window_until: f64,
    halt_until: Option<f64>,
    /// The laying errors' sequence: its seed (the placed position) and the bursts fired.
    seed: u64,
    burst_n: u64,
}

/// The farthest a crew of `skill` fires at `t`: its share of the envelope from the minimum range out; a gun, the
/// whole.
fn fire_range(gun: bool, skill: Skill, t: &Target) -> f64 {
    if gun { t.dlz.0 } else { t.dlz.1 + (t.dlz.0 - t.dlz.1) * skill.launch_range }
}

/// The earth's bulge (m) at `s` along a line of length `l` over the 4/3 earth.
fn bulge(s: f64, l: f64) -> f64 {
    s * (l - s) / (2.0 * REFRACTION * EARTH_R)
}

/// Terrain line of sight from `a` to `b` over the curved earth: the radar's `line_of_sight` with the ground lifted
/// by the bulge at each sample, so the radar horizon of the two heights holds; sea level where the terrain has none.
pub fn visible(a: Vec3, b: Vec3, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
    let l = (b.x - a.x).hypot(b.y - a.y);
    line_of_sight(a, b, &|p: Vec3| Some(terrain(p).unwrap_or(0.0) + bulge((p.x - a.x).hypot(p.y - a.y), l)))
}

/// Time to arrive at `at` (s): the "most dangerous" measure (inferred); opening targets come last by distance.
pub(crate) fn arrival(t: &Target, at: Vec3) -> f64 {
    let d = at - t.pos;
    let dist = d.length();
    dist / (t.vel.dot(d) / dist.max(1.0)).max(1.0)
}

impl Site {
    pub fn new(kind: Kind, pos: Vec3, heading: f64, alternates: &[Vec3]) -> Site {
        let spec = kind.spec();
        Site {
            kind,
            skill: Skill::MEDIUM,
            emcon: Emcon::Radiate,
            net: false,
            mast: false,
            positions: std::iter::once(pos).chain(alternates.iter().copied()).collect(),
            at: 0,
            pos,
            heading,
            course: heading,
            mode: Mode::Ready,
            rounds: spec.parts.iter().map(|p| p.rounds).collect(),
            channels: Vec::new(),
            engagements: 0,
            next_shot: f64::NEG_INFINITY,
            fired_here: 0,
            quiet_since: f64::NEG_INFINITY,
            last: f64::NEG_INFINITY,
            on_since: None,
            off_until: f64::NEG_INFINITY,
            window_ok: false,
            window_until: f64::NEG_INFINITY,
            halt_until: None,
            seed: pos.x.to_bits() ^ pos.y.to_bits().rotate_left(32),
            burst_n: 0,
        }
    }

    /// From a target found to a track (s): the crew's reaction, then the acquisition drill.
    fn acquire_s(&self) -> f64 {
        self.skill.reaction_s + self.spec().acquire * self.skill.procedure
    }

    /// The farthest the crew fires at `t`: its share of the envelope from the minimum range out (a gun: the whole).
    fn fire_range(&self, t: &Target) -> f64 {
        fire_range(self.spec().gun, self.skill, t)
    }

    pub fn spec(&self) -> &'static Spec {
        self.kind.spec()
    }

    /// In place, or on the move with radars that work on the move.
    fn placed(&self) -> bool {
        match self.mode {
            Mode::Ready => true,
            Mode::Move => self.spec().searches_moving,
            Mode::March(_) | Mode::Setup(_) => false,
        }
    }

    /// The EMCON it runs: Cue under the network, else its own.
    fn emission(&self) -> Emcon {
        if self.net { Emcon::Cue } else { self.emcon }
    }

    /// Part `i` on the ground (z: the terrain's height there).
    pub fn part_pos(&self, i: usize, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Vec3 {
        let p = &self.spec().parts[i];
        let (s, c) = self.heading.to_radians().sin_cos();
        let q = Vec3::new(self.pos.x + p.at[0] * c + p.at[1] * s, self.pos.y - p.at[0] * s + p.at[1] * c, 0.0);
        Vec3::new(q.x, q.y, terrain(q).unwrap_or(self.pos.z))
    }

    /// Part `i`'s antenna (its sight for the optical one).
    fn antenna(&self, i: usize, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Vec3 {
        let p = &self.spec().parts[i];
        // The tower is the 30N6E2's (a track radar only).
        self.part_pos(i, terrain).raised(if p.track && !p.search && self.mast { MAST } else { p.antenna })
    }

    /// The first part alive that searches (`track` false) or tracks.
    fn radar(&self, alive: &[bool], track: bool) -> Option<usize> {
        let parts = self.spec().parts;
        (0..parts.len())
            .find(|&i| alive.get(i).copied().unwrap_or(true) && if track { parts[i].track } else { parts[i].search })
    }

    /// The radar at `from` with `reach_m` against `radar::REF_RCS` sees `t`: inside its range for the jet's
    /// cross-section from there, and in sight over the terrain and the earth's curvature.
    pub(crate) fn sees(from: Vec3, reach_m: f64, t: &Target, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
        let s = sigma(&t.rcs, t.nose, from - t.pos, t.bays_open, t.stores);
        t.pos.distance(from) <= reach(reach_m, s) && visible(from, t.pos, terrain)
    }

    /// This site's radar at `from` sees `t` (`sees`) clear of the ground's clutter: fast enough along the line of
    /// sight for its Doppler rejection and above its floor (docs/ai.md §15.3).
    fn sees_clear(&self, from: Vec3, reach_m: f64, t: &Target, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
        let spec = self.spec();
        let along = t.vel.dot((t.pos - from).try_normalize().unwrap_or(Vec3::ZERO)).abs();
        along >= spec.reject
            && t.pos.z - terrain(t.pos).unwrap_or(0.0) >= spec.floor
            && Self::sees(from, reach_m, t, terrain)
    }

    /// The search radar (alive, radiating or not) detects `t`.
    pub fn detects(&self, alive: &[bool], t: &Target, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
        self.radar(alive, false)
            .is_some_and(|i| self.sees_clear(self.antenna(i, terrain), self.spec().search_reach, t, terrain))
    }

    /// The track radar (alive) can hold `t`.
    pub fn trackable(&self, alive: &[bool], t: &Target, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
        self.radar(alive, true)
            .is_some_and(|i| self.sees_clear(self.antenna(i, terrain), self.spec().track_reach, t, terrain))
    }

    /// Seconds until the site could fire at `t` (the network's pick, `net`): 0 inside its envelope with the track
    /// radar able to hold it, else the time to the envelope's edge at the closing speed; infinite when it cannot (no
    /// rounds or track radar, not set up, in the Tor's break with its window spent, masked or too close inside the
    /// envelope, opening outside it). The edge is the nearer of the envelope's and the track radar's reach for the
    /// jet's cross-section.
    pub fn eta(&self, now: f64, alive: &[bool], t: &Target, terrain: &dyn Fn(Vec3) -> Option<f64>) -> f64 {
        let spec = self.spec();
        let placed = self.placed();
        let resting = now < self.off_until && now >= self.window_until && !self.window_ok;
        let Some(i) = self.radar(alive, true).filter(|_| placed && !resting && t.dlz.0 > 0.0) else {
            return f64::INFINITY;
        };
        if !self.rounds.iter().any(|&r| r > 0) {
            return f64::INFINITY;
        }
        let at = self.antenna(i, terrain);
        let edge = t.dlz.0.min(reach(spec.track_reach, sigma(&t.rcs, t.nose, at - t.pos, t.bays_open, t.stores)));
        let d = t.pos.distance(self.pos);
        if d <= edge {
            return if d >= t.dlz.1 && visible(at, t.pos, terrain) { 0.0 } else { f64::INFINITY };
        }
        let closing = t.vel.dot(self.pos - t.pos) / d;
        if closing > 0.0 { (d - edge) / closing } else { f64::INFINITY }
    }

    /// The optical sight sees `t`.
    fn sighted(&self, alive: &[bool], t: &Target, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
        let spec = self.spec();
        spec.optical > 0.0
            && self.radar(alive, true).is_some_and(|i| {
                let eye = self.antenna(i, terrain);
                t.pos.distance(eye) <= spec.optical && visible(eye, t.pos, terrain)
            })
    }

    /// A cued target seconds from the crew's launch range: the track radar comes on for it (§11-134).
    fn cue_due(&self, t: &Target) -> bool {
        let d = self.pos - t.pos;
        let closing = t.vel.dot(d) / d.length().max(1.0);
        self.emission() == Emcon::Cue
            && t.cued
            && d.length() <= self.fire_range(t) + closing.max(0.0) * self.acquire_s()
    }

    /// One decision at `now` (s; about every 0.5 s): `alive` per part, the hostile jets alive, the terrain's height.
    pub fn tick(&mut self, now: f64, alive: &[bool], targets: &[Target], terrain: &dyn Fn(Vec3) -> Option<f64>) -> Out {
        let spec = self.spec();
        let dt = if self.last.is_finite() { (now - self.last).max(0.0) } else { 0.0 };
        self.last = now;
        self.pos.z = terrain(self.pos).unwrap_or(self.pos.z);
        // A part destroyed takes its rounds.
        for (r, a) in self.rounds.iter_mut().zip(alive) {
            if !a {
                *r = 0;
            }
        }
        match self.mode {
            Mode::March(t) if now >= t => self.mode = Mode::Move,
            Mode::Setup(t) if now >= t => self.mode = Mode::Ready,
            Mode::Move => self.drive(dt, now),
            _ => {}
        }
        let can_track = self.radar(alive, true).is_some();
        // The Tor's third engagement starts its hour's break here, a tick after the salvo: a launch the caller
        // refused (`refund`) is uncounted first.
        if spec.duty && now >= self.off_until && self.engagements >= BREAK_AFTER {
            self.engagements = 0;
            self.rest(now + BREAK, true);
        }
        // The Tor's break: one window of a minute for a cued target in reach.
        if now < self.off_until
            && self.window_ok
            && targets.iter().any(|t| t.cued && t.pos.distance(self.pos) <= spec.track_reach)
        {
            self.window_ok = false;
            self.window_until = now + BREAK_WINDOW;
        }
        let duty_off = now < self.off_until && now >= self.window_until;
        let placed = self.placed();
        let up = placed && !duty_off;
        let search_on = up && self.emission() == Emcon::Radiate && self.radar(alive, false).is_some();
        let track_ok = up && can_track && self.emission() != Emcon::Silent;
        // How the site holds `t` now: Some(true) by radar, Some(false) optically.
        let hold = |s: &Site, t: &Target, radar_before: bool| -> Option<bool> {
            let radar = track_ok && (s.emission() == Emcon::Radiate || radar_before || s.cue_due(t));
            if radar && s.trackable(alive, t, terrain) {
                Some(true)
            } else if placed && s.sighted(alive, t, terrain) {
                Some(false)
            } else {
                None
            }
        };
        // Tracks lost (gone, out of reach, masked) end; with no rounds left, each once its missiles have ended; under
        // Cue a radar track whose cue was taken away, unless its salvo flies.
        let armed = self.rounds.iter().any(|&r| r > 0);
        let cue = self.emission() == Emcon::Cue;
        let mut kept = std::mem::take(&mut self.channels);
        kept.retain_mut(|c| {
            let Some(t) = targets.iter().find(|t| t.id == c.target) else { return false };
            let guide = c.stage == Stage::Guide;
            (armed || guide)
                && !(cue && c.radar && !t.cued && !guide)
                && hold(self, t, c.radar).inspect(|&r| c.radar = r).is_some()
        });
        self.channels = kept;
        // New ones: the most dangerous detected first, while a channel is free.
        if armed && self.channels.len() < spec.channels {
            let mut seen: Vec<&Target> = targets
                .iter()
                .filter(|t| !self.channels.iter().any(|c| c.target == t.id))
                .filter(|t| {
                    (search_on && self.detects(alive, t, terrain))
                        || (track_ok && self.cue_due(t))
                        || (placed && self.sighted(alive, t, terrain))
                })
                .collect();
            seen.sort_by(|a, b| arrival(a, self.pos).total_cmp(&arrival(b, self.pos)));
            for t in seen {
                if self.channels.len() >= spec.channels {
                    break;
                }
                if let Some(radar) = hold(self, t, false) {
                    let stage = Stage::Acquire(now + self.acquire_s());
                    self.channels.push(Channel { target: t.id.clone(), stage, fired: 0, radar, counted: false });
                }
            }
        }
        let mut out = Out { search: search_on, ..Out::default() };
        self.engage(now, targets, &mut out);
        out.track = self.channels.iter().any(|c| c.radar);
        out.tracks = self
            .channels
            .iter()
            .filter(|c| c.radar && !matches!(c.stage, Stage::Acquire(_)))
            .map(|c| c.target.clone())
            .collect();
        self.cease(now);
        self.duty(now, out.search || out.track);
        out
    }

    /// The channels' stages: acquisition, the launches inside the envelope, the salvo's flight, the assessment.
    fn engage(&mut self, now: f64, targets: &[Target], out: &mut Out) {
        let spec = self.spec();
        let skill = self.skill;
        let in_env = |t: &Target, at: Vec3| {
            let d = t.pos.distance(at);
            t.dlz.0 > 0.0 && d >= t.dlz.1 && d <= fire_range(spec.gun, skill, t)
        };
        let target = |id: &str| targets.iter().find(|t| t.id == id);
        // A site that fires only at a halt stops first (the Tor on the move).
        let wants = self
            .channels
            .iter()
            .any(|c| c.stage == Stage::Track && target(&c.target).is_some_and(|t| in_env(t, self.pos)))
            && self.rounds.iter().any(|&r| r > 0);
        let firing = match self.mode {
            Mode::Ready => true,
            Mode::Move if spec.fires_moving => true,
            Mode::Move if wants => *self.halt_until.get_or_insert(now + spec.halt * self.skill.procedure) <= now,
            _ => false,
        };
        if !wants {
            self.halt_until = None;
        }
        for k in 0..self.channels.len() {
            let Some(t) = target(&self.channels[k].target) else { continue };
            if let Stage::Acquire(until) = self.channels[k].stage
                && now >= until
            {
                self.channels[k].stage = Stage::Track;
            }
            match self.channels[k].stage {
                Stage::Track if firing && now >= self.next_shot && in_env(t, self.pos) => {
                    // The launcher (or gun) with the most rounds left.
                    let Some(p) =
                        (0..self.rounds.len()).filter(|&i| self.rounds[i] > 0).max_by_key(|&i| self.rounds[i])
                    else {
                        continue;
                    };
                    self.next_shot = now + spec.spacing;
                    self.fired_here += 1;
                    if spec.gun {
                        let n = spec.salvo.min(self.rounds[p]);
                        self.rounds[p] -= n;
                        out.bursts.push((p, t.id.clone(), n, self.skill.lay(self.seed, self.burst_n)));
                        self.burst_n += 1;
                        continue;
                    }
                    self.rounds[p] -= 1;
                    out.launches.push((p, t.id.clone()));
                    let c = &mut self.channels[k];
                    c.fired += 1;
                    if c.fired >= spec.salvo {
                        c.stage = Stage::Guide;
                        c.counted = now >= self.off_until;
                        self.engagements += u32::from(c.counted);
                    }
                }
                // The salvo ended: assess; a target still alive is engaged again (shoot-look-shoot).
                Stage::Guide if t.in_air == 0 => {
                    self.channels[k].fired = 0;
                    self.channels[k].stage = Stage::Track;
                }
                _ => {}
            }
        }
    }

    /// A launch the caller could not make: its round back, and the launch and the salvo's engagement uncounted.
    pub fn refund(&mut self, part: usize, target: &str) {
        if let Some(r) = self.rounds.get_mut(part) {
            *r += 1;
        }
        self.fired_here = self.fired_here.saturating_sub(1);
        if let Some(c) = self.channels.iter_mut().find(|c| c.target == target) {
            c.fired = c.fired.saturating_sub(1);
            if c.stage == Stage::Guide {
                c.stage = Stage::Track;
                if c.counted {
                    self.engagements = self.engagements.saturating_sub(1);
                }
            }
        }
    }

    /// After an engagement, quiet for `CEASE` s: march order to the next position (§11-121; a single site moves whole,
    /// inferred from §11-119's third).
    fn cease(&mut self, now: f64) {
        if !self.channels.is_empty() || self.mode != Mode::Ready {
            self.quiet_since = now;
            return;
        }
        if self.fired_here > 0 && self.positions.len() > 1 && now - self.quiet_since >= CEASE {
            self.fired_here = 0;
            self.at = (self.at + 1) % self.positions.len();
            self.mode = Mode::March(now + self.spec().march * self.skill.procedure);
        }
    }

    /// Drives toward the position it moves to; at a halt for a shot it waits.
    fn drive(&mut self, dt: f64, now: f64) {
        if self.halt_until.is_some() {
            return;
        }
        let to = self.positions[self.at];
        let d = Vec3::new(to.x - self.pos.x, to.y - self.pos.y, 0.0);
        let dist = d.length();
        let step = self.spec().speed * dt;
        if dist <= step {
            self.pos = Vec3::new(to.x, to.y, to.z);
            self.course = self.heading;
            let setup = self.spec().setup * self.skill.procedure;
            self.mode = if setup > 0.0 { Mode::Setup(now + setup) } else { Mode::Ready };
        } else {
            self.pos += d * (step / dist);
            self.course = d.x.atan2(d.y).to_degrees().rem_euclid(360.0);
        }
    }

    /// The Tor's duty limit: 10 min on forces 10 min off (its hour's break after three engagements: `tick`).
    fn duty(&mut self, now: f64, on: bool) {
        if !self.spec().duty {
            return;
        }
        let window = now < self.window_until;
        if !on {
            self.on_since = None;
        } else if now - *self.on_since.get_or_insert(now) >= DUTY_ON && !window {
            self.rest(now + DUTY_OFF, false);
        }
    }

    fn rest(&mut self, until: f64, window: bool) {
        self.off_until = until;
        self.window_ok = window;
        self.window_until = f64::NEG_INFINITY;
        self.on_since = None;
        self.channels.clear();
    }

    /// The state's name: silent, search, engage, march, move, setup, rest.
    pub fn phase(&self, now: f64) -> &'static str {
        match self.mode {
            Mode::March(_) => "march",
            Mode::Move => "move",
            Mode::Setup(_) => "setup",
            Mode::Ready if now < self.off_until && now >= self.window_until => "rest",
            Mode::Ready if !self.channels.is_empty() => "engage",
            Mode::Ready if self.emission() == Emcon::Radiate => "search",
            Mode::Ready => "silent",
        }
    }
}
