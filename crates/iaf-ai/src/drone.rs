//! Modern IAF's one-way attack drones of the Shahed-136 class (docs/ai.md §16; modern-iaf/docs/ai-plan.md K14): a
//! point mass flown along a route of waypoints at the cruise speed and a set height above the terrain, turning and
//! climbing within inferred limits; at the route's end it dives onto the end point. A salvo launches its drones one
//! after another along the same route. They do not shoot. The 6-DoF has no data for the type (open): the point mass
//! stands in. The caller (`shared/ai/drones.gd`) makes each a mission entity the player's sensors and weapons see; no
//! mission uses one yet.

use iaf_flight::Vec3;
use iaf_flight::airframe::Rcs;
use iaf_flight::vec3::wrap_pi;

const G: f64 = 9.81;
/// The terrain ahead is read this often (m).
const LOOK_STEP: f64 = 100.0;

/// A drone type's figures.
#[derive(Clone, Copy, Debug)]
pub struct Spec {
    /// Cruise speed (m/s).
    pub cruise: f64,
    /// The height band above the terrain it flies in (m) and its height there unless told (m).
    pub agl_min: f64,
    pub agl_max: f64,
    pub agl: f64,
    /// The bank of its turns (degrees): the turn rate g·tan(bank)/v.
    pub bank_deg: f64,
    /// The most it climbs and sinks (m/s).
    pub climb: f64,
    pub sink: f64,
    /// The time it closes a height error in (s) and how far ahead it reads the terrain (s at cruise).
    pub height_tau: f64,
    pub look_ahead: f64,
    /// The dive onto the end point, below the horizon (degrees).
    pub dive_deg: f64,
    /// Between two launches of a salvo (s).
    pub interval: f64,
    pub rcs: Rcs,
}

/// The Shahed-136 (docs/ai.md §16): cruise about 180 km/h; the band 60–4,000 m. Its height in the band, the turn,
/// climb and dive limits and the launch interval are inferred; the cross-section is the one published estimate,
/// about 0.01 m² on average (the aspects alike: inferred).
pub const SHAHED_136: Spec = Spec {
    cruise: 50.0,
    agl_min: 60.0,
    agl_max: 4000.0,
    agl: 500.0,
    bank_deg: 30.0,
    climb: 5.0,
    sink: 10.0,
    height_tau: 5.0,
    look_ahead: 20.0,
    dive_deg: 40.0,
    interval: 10.0,
    rcs: Rcs { front_m2: 0.01, side_m2: 0.01, rear_m2: 0.01, bays_open_m2: 0.0, store_m2: 0.0 },
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    /// Not launched yet.
    Wait,
    Cruise,
    Dive,
    /// At the end point, or into the terrain: the caller shows the impact and removes it.
    Impact,
    /// Destroyed by the game: it flies no more.
    Down,
}

impl Phase {
    pub fn name(self) -> &'static str {
        match self {
            Phase::Wait => "wait",
            Phase::Cruise => "cruise",
            Phase::Dive => "dive",
            Phase::Impact => "impact",
            Phase::Down => "down",
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Drone {
    pub pos: Vec3,
    pub vel: Vec3,
    pub phase: Phase,
    /// The waypoint it flies to.
    pub leg: usize,
    /// The last known ground under it (m): the terrain away from the player may not be loaded.
    pub ground: f64,
}

impl Drone {
    /// Degrees clockwise from north.
    pub fn heading(&self) -> f64 {
        self.vel.x.atan2(self.vel.y).to_degrees().rem_euclid(360.0)
    }

    /// Degrees above the horizon.
    pub fn pitch(&self) -> f64 {
        self.vel.z.atan2(self.vel.x.hypot(self.vel.y)).to_degrees()
    }

    pub fn flying(&self) -> bool {
        matches!(self.phase, Phase::Cruise | Phase::Dive)
    }
}

/// A salvo: `drones` launched `interval` s apart from the route's first point, each flown `agl` m above the terrain
/// to the last point and diving onto it.
#[derive(Clone, Debug)]
pub struct Salvo {
    pub spec: &'static Spec,
    pub route: Vec<Vec3>,
    pub agl: f64,
    pub interval: f64,
    /// Since the first launch (s).
    pub t: f64,
    pub drones: Vec<Drone>,
}

/// The horizontal length.
fn flat(v: Vec3) -> f64 {
    v.x.hypot(v.y)
}

impl Salvo {
    /// `count` drones of `spec` along `route` (world; the last point is the end point on the ground; a point's z
    /// stands for the ground where the terrain is not known), `agl` clamped to the type's band, `interval` s apart;
    /// None for a route of fewer than two points.
    pub fn new(spec: &'static Spec, route: &[Vec3], count: usize, agl: f64, interval: f64) -> Option<Salvo> {
        if route.len() < 2 {
            return None;
        }
        let drone = Drone { pos: route[0], vel: Vec3::ZERO, phase: Phase::Wait, leg: 1, ground: route[0].z };
        Some(Salvo {
            spec,
            route: route.to_vec(),
            agl: agl.clamp(spec.agl_min, spec.agl_max),
            interval: interval.max(0.0),
            t: 0.0,
            drones: vec![drone; count],
        })
    }

    /// The turn rate at cruise (rad/s) and the turn's radius (m).
    fn turn(&self) -> (f64, f64) {
        let rate = G * self.spec.bank_deg.to_radians().tan() / self.spec.cruise;
        (rate, self.spec.cruise / rate)
    }

    /// Advances `dt` s: the drones due are launched (at the route's first point, at their height, heading for the
    /// second point) and every one flying moves.
    pub fn step(&mut self, dt: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) {
        self.t += dt;
        for i in 0..self.drones.len() {
            let due = i as f64 * self.interval;
            if self.drones[i].phase == Phase::Wait && self.t >= due {
                let p = self.route[0];
                let d = (self.route[1] - p).flat_dir();
                let g = terrain(p).unwrap_or(p.z);
                self.drones[i].ground = g;
                self.drones[i].pos = Vec3::new(p.x, p.y, g + self.agl);
                self.drones[i].vel = d * self.spec.cruise;
                self.drones[i].phase = Phase::Cruise;
                // It flies the part of the step after its launch time.
                let mut d = self.drones[i];
                self.fly(&mut d, (self.t - due).min(dt), terrain);
                self.drones[i] = d;
            } else if self.drones[i].flying() {
                let mut d = self.drones[i];
                self.fly(&mut d, dt, terrain);
                self.drones[i] = d;
            }
        }
    }

    /// The game destroyed drone `i`.
    pub fn down(&mut self, i: usize) {
        if let Some(d) = self.drones.get_mut(i) {
            d.phase = Phase::Down;
        }
    }

    /// One drone's move: in cruise it turns for its waypoint at the turn rate and holds its height over the terrain
    /// (the highest of here and every 100 m to `look_ahead` s ahead; where the terrain is not known, the last known
    /// ground) within its climb and sink; a waypoint within the turn's radius is passed. On the last leg it dives once
    /// the end point lies `dive_deg` below, or inside its turn's radius; it ends at the end point, or where it meets
    /// known terrain.
    fn fly(&self, d: &mut Drone, dt: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) {
        let s = self.spec;
        let last = self.route.len() - 1;
        let end = self.route[last];
        let end = Vec3::new(end.x, end.y, terrain(end).unwrap_or(end.z));
        d.ground = terrain(d.pos).unwrap_or(d.ground);
        if d.phase == Phase::Cruise {
            let (rate, radius) = self.turn();
            while d.leg < last && flat(self.route[d.leg] - d.pos) <= radius {
                d.leg += 1;
            }
            let to = self.route[d.leg] - d.pos;
            let h = d.vel.x.atan2(d.vel.y);
            let h = h + wrap_pi(to.x.atan2(to.y) - h).clamp(-rate * dt, rate * dt);
            let dir = Vec3::new(h.sin(), h.cos(), 0.0);
            let samples = (s.cruise * s.look_ahead / LOOK_STEP).ceil() as usize;
            let ahead = (1..=samples).filter_map(|k| terrain(d.pos + dir * (LOOK_STEP * k as f64)));
            let want = ahead.fold(d.ground, f64::max) + self.agl;
            let vz = ((want - d.pos.z) / s.height_tau).clamp(-s.sink, s.climb);
            let vh = (s.cruise * s.cruise - vz * vz).max(0.0).sqrt();
            d.vel = Vec3::new(vh * h.sin(), vh * h.cos(), vz);
            let left = flat(end - d.pos);
            if d.leg == last && (left * s.dive_deg.to_radians().tan() <= d.pos.z - end.z || left <= radius) {
                d.phase = Phase::Dive;
            }
        }
        if d.phase == Phase::Dive {
            let to = end - d.pos;
            if to.length() <= s.cruise * dt {
                d.pos = end;
                d.phase = Phase::Impact;
                return;
            }
            d.vel = to / to.length() * s.cruise;
        }
        d.pos += d.vel * dt;
        if let Some(g) = terrain(d.pos).filter(|&g| d.pos.z <= g) {
            d.pos.z = g;
            d.phase = Phase::Impact;
        }
    }
}
