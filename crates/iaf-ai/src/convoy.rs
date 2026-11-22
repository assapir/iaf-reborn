//! Modern IAF's moving ground vehicles (docs/ai.md §19; modern-iaf/docs/ai-plan.md K16): a convoy of T-72s and
//! Ural-4320s drives a route as one column, on the roads (OpenStreetMap's, `iaf_avionics::roads`, the route the host
//! finds) and across country where no road serves. Each vehicle keeps its place in the column, [`SPACING_M`] behind
//! the one ahead; the column drives at its slowest vehicle's march speed for the ground under its head (road or across
//! country); each stands on the terrain under it, its last known ground where the terrain is not loaded. Attacked (a
//! hit, a bomb or a gun's rounds within [`ALARM_M`] of a vehicle: [`Convoy::alarm`]) every vehicle drives off the road
//! to its side and stops; after [`QUIET_S`] without another alarm the survivors drive back onto the route, closed up
//! in their order, and the column drives on. At the route's end it stops. The caller (`shared/ai/convoys.gd`) makes
//! each vehicle a mission entity; no mission places one yet. Figures are inferred unless they say otherwise.

use iaf_flight::Vec3;

/// A vehicle type's figures.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Spec {
    /// Its unit record (modern-iaf/data/db/units).
    pub id: &'static str,
    /// Top speed on a road and across country (km/h).
    pub road_kmh: f64,
    pub cross_kmh: f64,
    /// Hull length (m): its pitch over the terrain is read at its two ends.
    pub length_m: f64,
}

/// The T-72: 60 km/h on roads (Wikipedia, "T-72"); 35 km/h across country (inferred); hull 6.86 m (Wikipedia).
pub const T72: Spec = Spec { id: "target_t72", road_kmh: 60.0, cross_kmh: 35.0, length_m: 6.86 };
/// The Ural-4320: 82 km/h on roads (its V8, Wikipedia, "Ural-4320"); 30 km/h across country (inferred); 7.37 m long.
pub const URAL: Spec = Spec { id: "target_ural", road_kmh: 82.0, cross_kmh: 30.0, length_m: 7.37 };
pub const SPECS: [&Spec; 2] = [&T72, &URAL];

/// The type of a unit record id.
pub fn spec(id: &str) -> Option<&'static Spec> {
    SPECS.iter().copied().find(|s| s.id == id)
}

/// A column marches at this share of its slowest vehicle's top speed (inferred).
pub const MARCH: f64 = 0.7;
/// Between two vehicles of the column (m): an open column's 300 feet or more (FHWA, military convoy facts).
pub const SPACING_M: f64 = 100.0;
/// A blast this near a vehicle alarms the convoy (m).
pub const ALARM_M: f64 = 500.0;
/// Off the road to this far, the vehicles alternating sides (m): `.0` plus up to `.1` more by its place.
pub const SCATTER_M: (f64, f64) = (60.0, 90.0);
/// Quiet this long after the last alarm, they drive on (s).
pub const QUIET_S: f64 = 60.0;
/// Reached a point within this (m).
const AT_M: f64 = 1.0;
/// Off the road a vehicle turns on the spot at this rate (deg/s) and drives once within [`TURNED_DEG`] of its goal.
const TURN_DPS: f64 = 45.0;
const TURNED_DEG: f64 = 30.0;
/// The road route is taken when its legs off the road add up to less than this share of the straight line.
const OFF_ROAD_MAX: f64 = 0.5;

/// A route: its points (world x, y) and, per segment, whether it is road.
#[derive(Clone, Debug, Default)]
pub struct Route {
    pub points: Vec<[f64; 2]>,
    pub road: Vec<bool>,
    /// The arc length at each point (m).
    cum: Vec<f64>,
}

fn dist(a: [f64; 2], b: [f64; 2]) -> f64 {
    (b[0] - a[0]).hypot(b[1] - a[1])
}

impl Route {
    fn new(points: Vec<[f64; 2]>, road: Vec<bool>) -> Route {
        let mut cum = vec![0.0];
        for w in points.windows(2) {
            cum.push(cum.last().unwrap() + dist(w[0], w[1]));
        }
        Route { points, road, cum }
    }

    /// From `from` to `to`: along `road` (the host's road route between the road points nearest the two, empty for
    /// none) with the legs to and from it across country, when those legs add up to less than [`OFF_ROAD_MAX`] of the
    /// straight line; else straight across country.
    pub fn plan(from: [f64; 2], to: [f64; 2], road: &[[f64; 2]]) -> Route {
        let straight = dist(from, to);
        if let (Some(&a), Some(&b)) = (road.first(), road.last())
            && road.len() >= 2
            && dist(from, a) + dist(b, to) < OFF_ROAD_MAX * straight
        {
            let (mut pts, mut surf) = (vec![from], Vec::new());
            let mut push = |p: [f64; 2], road: bool| {
                if dist(*pts.last().unwrap(), p) > 0.01 {
                    pts.push(p);
                    surf.push(road);
                }
            };
            push(a, false);
            for &p in &road[1..] {
                push(p, true);
            }
            push(to, false);
            return Route::new(pts, surf);
        }
        Route::new(vec![from, to], vec![false])
    }

    pub fn length(&self) -> f64 {
        *self.cum.last().unwrap_or(&0.0)
    }

    /// The point `s` m along (clamped), its course (degrees from north) and whether it is road.
    pub fn at(&self, s: f64) -> ([f64; 2], f64, bool) {
        let n = self.road.len();
        if n == 0 {
            return (self.points.first().copied().unwrap_or_default(), 0.0, false);
        }
        let s = s.clamp(0.0, self.length());
        let i = self.cum.partition_point(|&c| c <= s).clamp(1, n) - 1;
        let (a, b) = (self.points[i], self.points[i + 1]);
        let l = self.cum[i + 1] - self.cum[i];
        let f = if l > 0.0 { (s - self.cum[i]) / l } else { 0.0 };
        let p = [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
        (p, course(a, b), self.road[i])
    }
}

/// Degrees clockwise from north, a to b.
fn course(a: [f64; 2], b: [f64; 2]) -> f64 {
    (b[0] - a[0]).atan2(b[1] - a[1]).to_degrees().rem_euclid(360.0)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    /// The column drives the route.
    Move,
    /// Off the road to their scatter points, then stopped there.
    Scatter,
    /// Back onto the route, each to its place in the closed-up column.
    Rejoin,
    /// At the route's end, stopped.
    Arrived,
}

impl Phase {
    pub fn name(self) -> &'static str {
        match self {
            Phase::Move => "move",
            Phase::Scatter => "scatter",
            Phase::Rejoin => "rejoin",
            Phase::Arrived => "arrived",
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Vehicle {
    pub spec: &'static Spec,
    /// World; z its ground.
    pub pos: Vec3,
    pub vel: Vec3,
    /// Degrees from north; degrees nose up.
    pub heading: f64,
    pub pitch: f64,
    pub alive: bool,
    /// Its place along the route (m).
    pub s: f64,
    /// Where it drives off the route to (Scatter) or back to (Rejoin).
    pub goal: [f64; 2],
}

#[derive(Clone, Debug)]
pub struct Convoy {
    pub route: Route,
    pub vehicles: Vec<Vehicle>,
    pub phase: Phase,
    /// The last alarm (s).
    pub alarmed: f64,
}

impl Convoy {
    /// The column of `specs` (head first) on `route`, its tail at the route's start (a route shorter than the column:
    /// the front ones stand at its end); None without a vehicle or a route.
    pub fn new(specs: &[&'static Spec], route: Route) -> Option<Convoy> {
        if specs.is_empty() || route.road.is_empty() {
            return None;
        }
        let n = specs.len();
        let vehicles = specs
            .iter()
            .enumerate()
            .map(|(i, &spec)| {
                let s = ((n - 1 - i) as f64 * SPACING_M).min(route.length());
                let (p, h, _) = route.at(s);
                Vehicle {
                    spec,
                    pos: Vec3::new(p[0], p[1], 0.0),
                    vel: Vec3::ZERO,
                    heading: h,
                    pitch: 0.0,
                    alive: true,
                    s,
                    goal: p,
                }
            })
            .collect();
        Some(Convoy { route, vehicles, phase: Phase::Move, alarmed: f64::NEG_INFINITY })
    }

    /// The game destroyed vehicle `i`: it stays where it is.
    pub fn down(&mut self, i: usize) {
        if let Some(v) = self.vehicles.get_mut(i) {
            v.alive = false;
            v.vel = Vec3::ZERO;
        }
    }

    fn alive(&self) -> impl Iterator<Item = &Vehicle> {
        self.vehicles.iter().filter(|v| v.alive)
    }

    /// A blast (a hit, a bomb, a gun's round, a missile) at `at` at `now`: within [`ALARM_M`] of a vehicle alive, the
    /// convoy scatters (again: from where each is); true when it alarmed.
    pub fn alarm(&mut self, now: f64, at: Vec3) -> bool {
        let near = self.alive().any(|v| (v.pos.x - at.x).hypot(v.pos.y - at.y) <= ALARM_M);
        if !near {
            return false;
        }
        self.alarmed = now;
        if self.phase != Phase::Scatter {
            self.phase = Phase::Scatter;
            for (i, v) in self.vehicles.iter_mut().enumerate() {
                // Square to its course, right for the even places, left for the odd ones, a little ahead.
                let side = if i % 2 == 0 { 90.0 } else { -90.0 };
                let off = SCATTER_M.0 + SCATTER_M.1 * ((i * 7 % 10) as f64 / 10.0);
                let h = (v.heading + side * 0.8).to_radians();
                v.goal = [v.pos.x + off * h.sin(), v.pos.y + off * h.cos()];
            }
        }
        true
    }

    /// The column's march speed for the ground under its head (m/s): its slowest vehicle's top speed there times
    /// [`MARCH`].
    pub fn march_speed(&self, road: bool) -> f64 {
        let kmh = |s: &Spec| if road { s.road_kmh } else { s.cross_kmh };
        self.alive().map(|v| kmh(v.spec)).fold(f64::INFINITY, f64::min) * MARCH / 3.6
    }

    /// Advances `dt` s at `now` on the terrain `terrain` (world point → its ground, None where not loaded).
    pub fn step(&mut self, now: f64, dt: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) {
        match self.phase {
            Phase::Move => self.drive(dt),
            Phase::Scatter if now - self.alarmed >= QUIET_S => self.rejoin(),
            Phase::Scatter | Phase::Rejoin => {
                let mut all = true;
                for v in self.vehicles.iter_mut().filter(|v| v.alive) {
                    all &= off_road(v, dt);
                }
                if all && self.phase == Phase::Rejoin {
                    self.phase = Phase::Move;
                }
            }
            Phase::Arrived => {}
        }
        for v in &mut self.vehicles {
            if !v.alive {
                continue;
            }
            v.pos.z = terrain(v.pos).unwrap_or(v.pos.z);
            let h = v.heading.to_radians();
            let half = Vec3::new(h.sin(), h.cos(), 0.0) * (v.spec.length_m / 2.0);
            if let (Some(f), Some(b)) = (terrain(v.pos + half), terrain(v.pos - half)) {
                v.pitch = (f - b).atan2(v.spec.length_m).to_degrees();
            }
        }
    }

    /// The column on the route: its head's march speed; each vehicle stops at its place behind the end.
    fn drive(&mut self, dt: f64) {
        let head = self.alive().map(|v| v.s).fold(f64::NEG_INFINITY, f64::max);
        if head == f64::NEG_INFINITY || dt <= 0.0 {
            return;
        }
        let speed = self.march_speed(self.route.at(head).2);
        let len = self.route.length();
        let mut rank = 0.0;
        let mut moving = false;
        for v in self.vehicles.iter_mut().filter(|v| v.alive) {
            let end = (len - rank * SPACING_M).max(0.0);
            rank += 1.0;
            let s = (v.s + speed * dt).min(end.max(v.s));
            let ds = s - v.s;
            v.s = s;
            let (p, h, _) = self.route.at(s);
            v.pos = Vec3::new(p[0], p[1], v.pos.z);
            v.heading = h;
            v.vel = Vec3::new(h.to_radians().sin(), h.to_radians().cos(), 0.0) * (ds / dt.max(1e-9));
            moving |= ds > 0.0;
        }
        if !moving {
            self.phase = Phase::Arrived;
            for v in &mut self.vehicles {
                v.vel = Vec3::ZERO;
            }
        }
    }

    /// The survivors' places in the closed-up column behind the head (in their order), each driving back to its own.
    fn rejoin(&mut self) {
        self.phase = Phase::Rejoin;
        let head = self.alive().map(|v| v.s).fold(f64::NEG_INFINITY, f64::max);
        let mut rank = 0.0;
        for v in self.vehicles.iter_mut().filter(|v| v.alive) {
            v.s = (head - rank * SPACING_M).max(0.0);
            v.goal = self.route.at(v.s).0;
            rank += 1.0;
        }
    }
}

/// One vehicle's drive across country to its goal at its top speed there; true once there (stopped).
fn off_road(v: &mut Vehicle, dt: f64) -> bool {
    let (dx, dy) = (v.goal[0] - v.pos.x, v.goal[1] - v.pos.y);
    let d = dx.hypot(dy);
    if d <= AT_M {
        v.vel = Vec3::ZERO;
        return true;
    }
    let want = dx.atan2(dy).to_degrees();
    let dh = (want - v.heading + 540.0).rem_euclid(360.0) - 180.0;
    v.heading = (v.heading + dh.clamp(-TURN_DPS * dt, TURN_DPS * dt)).rem_euclid(360.0);
    if dh.abs() > TURNED_DEG {
        v.vel = Vec3::ZERO;
        return false;
    }
    let step = (v.spec.cross_kmh / 3.6 * dt).min(d);
    v.pos.x += dx / d * step;
    v.pos.y += dy / d * step;
    v.vel = Vec3::new(dx / d, dy / d, 0.0) * (step / dt.max(1e-9));
    false
}
