//! The four-ship (modern-iaf/docs/ai-plan.md §6) on the 6-DoF Sufa and the sim's own data: #1 is a scripted lead flown
//! by the existing autopilot, #2–#4 the AI. Skips with a message when `assets/converted/own` is not built.

use std::path::{Path, PathBuf};

use iaf_ai::{Bogey, Call, Decoy, Flight, SHAPES, Threat, apply};
use iaf_flight::airbase::Airbase;
use iaf_flight::autopilot::{self, Autopilot, Config, Host, MODE_STEER, Waypoint};
use iaf_flight::fm::Fm;
use iaf_flight::sixdof::autopilot::{ALT_HOLD, HDG_SEL};
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;
/// The hangars' occupancy is one for the process (`autopilot::reset_hangars`): the tests that park take turns.
static HANGARS: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

/// The four jets, their flight and the frame loop.
struct World {
    jets: Vec<(Fm, Autopilot)>,
    alive: [bool; 4],
    flight: Flight,
    t: f64,
    ground: f32,
    /// The least distance between two live jets so far, in the air and on the ground (both on the ground), m.
    sep_air: f64,
    sep_ground: f64,
    /// Where the least air separation was: the time and the pair.
    sep_at: (f64, usize, usize),
    sep_ground_at: (f64, usize, usize),
    calls: Vec<(f64, Call)>,
    /// Frames and the wall time they took (FM + autopilot + AI).
    frames: u64,
    busy: std::time::Duration,
    /// The frame's time, s: [`DT`], or the game's under time compression.
    dt: f64,
    /// The lead's speed held by its throttle, m/s (else its autopilot's).
    lead_speed: Option<f64>,
    /// Each jet's last 20 s, every 0.5 s, for a failure's message.
    trace: [std::collections::VecDeque<String>; 4],
    /// The game's frame order and uneven frames ([`World::frame`]).
    /// The player's (the lead's) steps a frame; its wingmen take one (the game steps every jet `time_factor` times:
    /// here the cadences differ on purpose, one instant either way).
    lead_steps: usize,
    jitter: f64,
}

impl World {
    /// Four Sufas (F-16I) at `starts` (position, heading deg); #1 the scripted lead.
    fn new(dir: &Path, starts: [(Vec3, f32); 4], speed: f64, airborne: bool, ground: f32) -> World {
        World::of_type(dir, "F-16I", starts, speed, airborne, ground)
    }

    /// [`World::new`] with four jets of flight-model type `ty` (`data_set::TYPES`).
    fn of_type(dir: &Path, ty: &str, starts: [(Vec3, f32); 4], speed: f64, airborne: bool, ground: f32) -> World {
        let (p, e) = iaf_flight::load_with(dir, ty, DataSet::Original).unwrap();
        let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
        let mut flight = Flight::default();
        let mut jets = Vec::new();
        for (pos, hdg) in starts {
            let h = (hdg as f64).to_radians();
            let st = Start {
                position: pos,
                pitch: 0.0,
                roll: 0.0,
                heading: h as f32,
                velocity: Vec3::new(h.sin() * speed, h.cos() * speed, 0.0),
                airborne,
                engine_on: airborne,
            };
            let fm = Fm::start(ty, p.clone(), e.clone(), st);
            assert!(matches!(fm, Fm::SixDof(_)), "{ty} flies the 6-DoF");
            let mut ap = Autopilot::new(Config::load(dir));
            ap.bases = bases.clone();
            jets.push((fm, ap));
        }
        for (i, (fm, ap)) in jets.iter_mut().enumerate() {
            if let Fm::SixDof(s) = fm {
                s.set_ground_height(ground);
            }
            flight.add(i as u8 + 1, i > 0, fm, ap);
        }
        World {
            jets,
            alive: [true; 4],
            flight,
            t: 0.0,
            ground,
            sep_air: f64::MAX,
            sep_ground: f64::MAX,
            sep_at: (0.0, 0, 0),
            sep_ground_at: (0.0, 0, 0),
            calls: Vec::new(),
            frames: 0,
            busy: Default::default(),
            dt: DT,
            lead_speed: None,
            trace: Default::default(),
            lead_steps: 1,
            jitter: 0.0,
        }
    }

    fn frame(&mut self) {
        let clock = std::time::Instant::now();
        // The game's uneven frames: up to `jitter` × the frame's time longer or shorter.
        let dt = self.dt * (1.0 + self.jitter * (((self.frames as f64 * 12.9898).sin() * 43758.5453).fract()));
        for (i, (fm, ap)) in self.jets.iter().enumerate() {
            self.flight.sense(i as u8 + 1, self.alive[i], fm, ap);
        }
        for c in self.flight.step(self.t) {
            self.calls.push((self.t, c));
        }
        // Every jet stepped, then sensed (the game: the player's steps, then the AI's jets', then IafAi).
        for _ in 0..self.lead_steps {
            self.step_jet(0, dt / self.lead_steps as f64);
        }
        for i in 1..4 {
            self.step_jet(i, dt);
        }
        self.busy += clock.elapsed();
        self.frames += 1;
        self.t += dt;
        for i in 0..4 {
            let si = self.jets[i].0.state();
            if self.frames.is_multiple_of(30) {
                let (fm, ap) = &self.jets[i];
                let (p, c) = (si.position, fm.controls());
                self.trace[i].push_back(format!(
                    "t {:.1} {} pos ({:.0}, {:.0}, {:.1}) hdg {:.0} pitch {:.1} roll {:.1} v {:.1} g {:.2} stick ({:.2}, {:.2}) \
                     thr {:.2} brakes {} ground {}",
                    self.t, ap.stage(), p.x, p.y, p.z - self.ground as f64, si.heading, si.pitch.to_degrees(),
                    si.roll.to_degrees(), si.speed, si.g, c.stick_x, c.stick_y, c.throttle, c.brakes, si.on_ground
                ));
                if self.trace[i].len() > 40 {
                    self.trace[i].pop_front();
                }
            }
            if si.crashed.is_some() {
                let tr: Vec<_> = self.trace[i].iter().cloned().collect();
                panic!("#{} crashed ({:?}) in {}:\n{}", i + 1, si.crashed, self.jets[i].1.stage(), tr.join("\n"));
            }
            for j in i + 1..4 {
                if !(self.alive[i] && self.alive[j]) {
                    continue;
                }
                let sj = self.jets[j].0.state();
                let d = si.position.distance(sj.position);
                if si.on_ground && sj.on_ground {
                    if d < self.sep_ground {
                        self.sep_ground = d;
                        self.sep_ground_at = (self.t, i + 1, j + 1);
                    }
                } else if d < self.sep_air {
                    self.sep_air = d;
                    self.sep_at = (self.t, i + 1, j + 1);
                }
            }
        }
    }

    fn step_jet(&mut self, i: usize, dt: f64) {
        if !self.alive[i] {
            return;
        }
        let g = self.ground;
        let (fm, ap) = &mut self.jets[i];
        if i > 0 {
            apply(&self.flight.members[i].order, ap, fm);
        }
        if let Fm::SixDof(s) = fm {
            s.set_ground_height(g);
        }
        ap.step(fm, &|_, _| g);
        if let Some(v) = self.lead_speed.filter(|_| i == 0) {
            // The player's throttle: its speed held (the autopilot steers).
            let mut c = fm.controls();
            c.throttle = (0.3 + 0.05 * (v - fm.state().speed as f64)).clamp(0.0, 0.9) as f32;
            fm.set_controls(c);
        }
        fm.step(dt);
    }

    fn run(&mut self, seconds: f64) {
        for _ in 0..(seconds / self.dt) as usize {
            self.frame();
        }
    }

    /// Runs until `done` or `limit` s; the time it took.
    fn until(&mut self, limit: f64, done: &dyn Fn(&World) -> bool) -> Option<f64> {
        let t0 = self.t;
        while self.t - t0 < limit {
            self.frame();
            if done(self) {
                return Some(self.t - t0);
            }
        }
        None
    }

    /// The worst slot error of the live wingmen over `seconds`, m; with `only` the frames it holds.
    fn worst(&mut self, seconds: f64, only: &dyn Fn(&World) -> bool) -> f32 {
        let mut worst: f32 = 0.0;
        for _ in 0..(seconds / self.dt) as usize {
            self.frame();
            if only(self) {
                for m in self.flight.members.iter().filter(|m| m.alive && m.number != self.flight.lead()) {
                    worst = worst.max(m.slot_error);
                }
            }
        }
        worst
    }

    /// The time of `from`'s last call `id`.
    fn said(&self, from: u8, id: &str) -> Option<f64> {
        self.calls.iter().rev().find(|(_, c)| c.from == from && c.id == id).map(|(t, _)| *t)
    }

    /// The scripted lead: KeepAttitude2PtAtSpeed (mode 9 in the air: 400 kt, bank ≤ 45°) toward `p`.
    fn lead_to(&mut self, p: Vec3) {
        let (fm, ap) = &mut self.jets[0];
        ap.route = vec![Waypoint { x: p[0], y: p[1], z: p[2], t: 0.0, action: 3 }];
        ap.set_mode(fm, 0);
        ap.set_mode(fm, 9);
    }

    fn us_per_jet_frame(&self) -> f64 {
        self.busy.as_secs_f64() * 1e6 / (self.frames as f64 * 4.0)
    }
}

/// The flight at 3,000 m heading north at 400 kt, in fingertip (or `behind` m further back), #1 at the origin.
fn airborne(dir: &Path, behind: f64) -> World {
    let z = 3000.0;
    let start = |n: usize| {
        let s = if n == 0 { [0.0; 3] } else { SHAPES[0].1[n - 1] };
        let back = if n == 0 { 0.0 } else { behind };
        (Vec3::new(s[1] as f64, s[0] as f64 - back, z), 0.0)
    };
    let mut w = World::new(dir, [start(0), start(1), start(2), start(3)], 205.889, true, 0.0);
    w.lead_to(Vec3::new(0.0, 400_000.0, z));
    w
}

#[test]
fn one_time_base_for_every_jet() {
    // The player's flight model restarted 40 s after its wingmen's (test_four_ship's `tv.flight.start`, a late
    // spawn) and stepped 4 times a frame while they step once: the flight reads every jet at one instant, its leader
    // fed where it flies (its clock against theirs put it 50 m ahead).
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let mut w = airborne(&dir, 0.0);
    for _ in 0..(40.0 / w.dt) as usize {
        for i in 1..4 {
            w.step_jet(i, w.dt);
        }
    }
    w.lead_steps = 4;
    for _ in 0..30 {
        let lead = w.jets[0].0.state().position;
        w.frame();
        let fed = w.flight.member(2).and_then(|m| m.order.leader).expect("#2 is fed its leader");
        assert!(fed.pos.distance(lead) < 1e-6, "#2's leader {:.1} m off the lead", fed.pos.distance(lead));
    }
}

/// No two slots of a shape nearer than 84 m: 60 m is the step-down and the pull-away distance (flight.rs `SHAPES`).
#[test]
fn shapes_keep_the_jets_apart() {
    for (id, s) in SHAPES {
        let p = [[0.0; 3], s[0], s[1], s[2]];
        for (i, a) in p.iter().enumerate() {
            for (j, b) in p.iter().enumerate().skip(i + 1) {
                let d = a.iter().zip(b).map(|(x, y)| (x - y).powi(2)).sum::<f32>().sqrt();
                assert!(d >= 84.0, "{id}: #{} and #{} {d:.0} m apart", i + 1, j + 1);
            }
        }
    }
}

#[test]
fn airborne_four_ship_holds_slots_changes_shape_rejoins_and_promotes() {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let mut w = airborne(&dir, 0.0);
    w.run(30.0);
    let level = w.worst(60.0, &|_| true);
    println!("level, fingertip: worst slot error {level:.1} m");
    // Each shape, then back to fingertip.
    let mut shapes = Vec::new();
    for (id, _) in SHAPES.iter().skip(1).chain(&SHAPES[..1]) {
        let t0 = w.t;
        assert!(w.flight.command(w.t, 0, id));
        let took = w.until(300.0, &|w| (2..=4).all(|n| w.said(n, "in_position").is_some_and(|t| t > t0)));
        // Settled: the wingmen climb back from their transit step first.
        w.run(20.0);
        let held = w.worst(30.0, &|_| true);
        println!("{id} (from t {t0:.0} s): in position after {took:?} s, then worst slot error {held:.1} m");
        assert!(took.is_some(), "{id}: not in position");
        shapes.push((*id, held));
    }
    // A 45° bank turn: the lead turns back toward the south-west.
    let p = w.jets[0].0.ap_view().pos;
    w.lead_to(Vec3::new(p[0] - 60_000.0, p[1] - 30_000.0, 3000.0));
    let turn = w.worst(80.0, &|w| w.jets[0].0.ap_view().att.roll.abs() > 40f32.to_radians());
    println!("45° bank turn: worst slot error {turn:.1} m (bank > 40°)");
    println!("separation, all phases: {:.1} m (t {:.0} s, #{} and #{})", w.sep_air, w.sep_at.0, w.sep_at.1, w.sep_at.2);
    println!("cost: {:.2} µs per jet per 1/60 s frame (FM + autopilot + AI, {})", w.us_per_jet_frame(), build());
    assert!(level <= 30.0, "level {level}");
    for (id, held) in shapes {
        assert!(held <= 30.0, "{id} {held}");
    }
    assert!(turn <= 60.0, "turn {turn}");
    assert!(w.sep_air > 30.0, "separation {}", w.sep_air);

    // Rejoin from 5 km behind, then the lead is lost on its way to waypoint 1: #3 leads on from there (the route,
    // mode 7), #2 and #4 on it.
    let mut w = airborne(&dir, 5000.0);
    let wp = |y: f64| Waypoint { x: 0.0, y, z: 3000.0, t: 1e9, action: 3 };
    for (_, ap) in &mut w.jets[1..] {
        ap.route = vec![wp(-400_000.0), wp(400_000.0)];
    }
    w.flight.command(0.0, 0, "rejoin");
    let rejoin = w.until(400.0, &|w| (2..=4).all(|n| w.said(n, "in_position").is_some()));
    println!("rejoin from 5 km: in position after {rejoin:?} s; separation {:.1} m", w.sep_air);
    assert!(rejoin.is_some(), "rejoin");
    w.jets[0].1.wp_index = 1;
    w.alive[0] = false;
    w.run(60.0);
    let promoted = w.worst(60.0, &|_| true);
    println!(
        "#1 lost: lead #{}, {:?}; worst slot error on #3 {promoted:.1} m",
        w.flight.lead(),
        w.said(3, "lead_change")
    );
    assert_eq!(w.flight.lead(), 3);
    assert!(w.said(3, "lead_change").is_some());
    assert_eq!(w.jets[2].1.mode(), 7, "the new lead flies the route");
    assert_eq!(w.jets[2].1.wp_index, 1, "on from the lost lead's waypoint");
    assert!(promoted <= 30.0, "after the promotion {promoted}");
    assert!(w.sep_air > 30.0, "separation {}", w.sep_air);
}

fn build() -> &'static str {
    if cfg!(debug_assertions) { "debug build" } else { "release build" }
}

#[test]
fn fuel_calls_and_rtb() {
    // 50 km east of Ramon: bingo 800 + 2 × 50 km = 900 kg, joker 1,900 kg (flight.rs).
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let ramon = bases.iter().find(|b| b.name == "Ramon").unwrap();
    let r = Vec3::new(ramon.lineup[0] as f64, ramon.lineup[1] as f64, ramon.lineup[2] as f64);
    let home = Waypoint { x: r[0] + 13_700.0, y: r[1] + 6_100.0, z: r[2] + 1500.0, t: 0.0, action: 7 };
    let z = r[2] + 3000.0;
    let start = |n: usize| {
        let s = if n == 0 { [0.0; 3] } else { SHAPES[0].1[n - 1] };
        (Vec3::new(r[0] + 50_000.0 + s[1] as f64, r[1] + s[0] as f64, z), 0.0)
    };
    let mut w = World::new(&dir, [start(0), start(1), start(2), start(3)], 205.889, true, r[2] as f32);
    for (_, ap) in &mut w.jets {
        ap.route = vec![home];
    }
    // (The flight's home was named from the routes: re-add after setting them.)
    w.flight = Flight::default();
    for (i, (fm, ap)) in w.jets.iter_mut().enumerate() {
        w.flight.add(i as u8 + 1, i > 0, fm, ap);
    }
    w.lead_to(Vec3::new(r[0] + 50_000.0, r[1] + 400_000.0, z));
    w.run(20.0);
    assert!(w.flight.command(w.t, 0, "check"));
    assert!(w.flight.command(w.t, 0, "ops_check"));
    w.run(5.0);
    for n in 2..=4 {
        assert!(w.said(n, "ack").is_some() && w.said(n, "fuel_state").is_some(), "#{n} answers");
    }
    let bingo = w.flight.member(2).unwrap().bingo_kg;
    println!("#2 bingo {bingo:.0} kg");
    w.jets[1].0.set_fuel(bingo + 1020.0);
    let joker = w.until(120.0, &|w| w.said(2, "joker").is_some());
    w.jets[1].0.set_fuel(bingo + 5.0);
    let bingo_call = w.until(60.0, &|w| w.said(2, "bingo").is_some());
    w.jets[1].0.set_fuel(805.0);
    let rtb = w.until(60.0, &|w| w.said(2, "rtb").is_some() && w.jets[1].1.mode() == 8);
    println!("#2: joker after {joker:?} s, bingo after {bingo_call:?} s, home after {rtb:?} s");
    assert!(joker.is_some() && bingo_call.is_some() && rtb.is_some());
    assert!(w.said(2, "joker") < w.said(2, "bingo"), "joker before bingo");
    // The flight is sent home: #3, then #4 20 s later (#2 already went).
    w.jets[1].0.set_fuel(3000.0);
    assert!(w.flight.command(w.t, 0, "rtb"));
    let t0 = w.t;
    let home3 = w.until(60.0, &|w| w.jets[2].1.mode() == 8).map(|_| w.t - t0);
    let home4 = w.until(60.0, &|w| w.jets[3].1.mode() == 8).map(|_| w.t - t0);
    println!("RTB to the flight: #3 home after {home3:?} s, #4 after {home4:?} s");
    assert!(home3.is_some() && home4.is_some() && home4.unwrap() - home3.unwrap() >= 19.0);
    // Rejoin cancels the RTB: back to the slot, and in it.
    let t0 = w.t;
    assert!(w.flight.command(w.t, 0, "rejoin"));
    // (Beyond 6 km the far rejoin: the steer loop at the slot.)
    let to_slot = |m: u8| m == iaf_flight::autopilot::MODE_SLOT || m == MODE_STEER;
    let back = w.until(10.0, &|w| w.jets[1..].iter().all(|(_, ap)| to_slot(ap.mode())));
    let there = w.until(1500.0, &|w| (2..=4).all(|n| w.said(n, "in_position").is_some_and(|t| t > t0)));
    println!("rejoin after the RTB: back in the slot after {back:?} s, in position after {there:?} s more");
    assert!(back.is_some() && there.is_some(), "rejoin after the RTB");
    assert!(w.sep_air > 30.0, "separation {}", w.sep_air);
}

#[test]
fn rtb_from_a_turn_round_ramon() {
    // Sent home at points round the circle: the lead's heading at the RTB (test_four_ship's case: 243°); at 60 frames
    // a second and at the game's 0.1 s frames under its time compression (×6).
    for dt in [DT, 0.1] {
        for at in [243.0, 200.0, 290.0, 340.0, 30.0, 120.0] {
            rtb_turn(at, dt);
        }
    }
}

fn rtb_turn(at: f64, dt: f64) {
    // The four-ship test's case: the lead circles right round Ramon at 30° of bank (HDG SEL, 201 m/s: 7.1 km), the
    // flight in echelon right, then RTB to the flight: each goes home to a landing waypoint outside the circle, across
    // the others' paths, and keeps clear of them.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let ramon = bases.iter().find(|b| b.name == "Ramon").unwrap();
    let r = Vec3::new(ramon.lineup[0] as f64, ramon.lineup[1] as f64, ramon.lineup[2] as f64);
    let home = Waypoint { x: r[0] + 10_000.0, y: r[1] + 4000.0, z: r[2] + 500.0, t: 0.0, action: 7 };
    let z = r[2] + 1500.0;
    // Heading east 6 km north of Ramon: forward is east, right is south.
    let start = |n: usize| {
        let s = if n == 0 { [0.0; 3] } else { SHAPES[0].1[n - 1] };
        (Vec3::new(r[0] + s[0] as f64, r[1] + 6000.0 - s[1] as f64, z), 90.0)
    };
    let mut w = World::new(&dir, [start(0), start(1), start(2), start(3)], 205.889, true, r[2] as f32);
    (w.dt, w.lead_speed) = (dt, Some(201.0));
    for (_, ap) in &mut w.jets {
        ap.route = vec![home];
    }
    w.flight = Flight::default();
    for (i, (fm, ap)) in w.jets.iter_mut().enumerate() {
        w.flight.add(i as u8 + 1, i > 0, fm, ap);
    }
    // The lead keeps turning right round a circle of 30° of bank at the game's 201 m/s: its point 2 km on along the
    // circle, each second.
    let radius = 201f64.powi(2) / (9.81 * 30f64.to_radians().tan());
    let centre = Vec3::new(r[0], r[1] + 6000.0 - radius, z);
    let circle = |w: &mut World, seconds: f64| {
        for _ in 0..seconds as usize {
            let d = w.jets[0].0.ap_view().pos - centre;
            let b = d[0].atan2(d[1]) + 2000.0 / radius;
            w.lead_to(centre + Vec3::new(radius * b.sin(), radius * b.cos(), 0.0));
            w.run(1.0);
        }
    };
    let heading = |w: &World| (w.jets[0].0.state().heading as f64).to_degrees();
    assert!(w.flight.command(w.t, 0, "echelon_right"));
    circle(&mut w, 60.0);
    while (heading(&w) - at).rem_euclid(360.0) > 2.0 {
        circle(&mut w, 1.0);
    }
    assert!(w.flight.command(w.t, 0, "rtb"));
    let sep0 = w.sep_air;
    w.sep_air = f64::MAX;
    circle(&mut w, 120.0);
    let away = w.jets[1..].iter().filter(|(_, ap)| ap.mode() == 8).count();
    println!(
        "RTB from a turn round Ramon at {at}° ({:.0} s, frame {dt:.3} s): {away} gone home; separation before {sep0:.1} m, after {:.1} m (t {:.0} s, #{} and #{})",
        w.t - 120.0,
        w.sep_air,
        w.sep_at.0,
        w.sep_at.1,
        w.sep_at.2
    );
    assert_eq!(away, 3, "all three sent home");
    // The game's limit is 30 m; its uneven frames under time compression cost 10-20 m more than this run (a
    // prediction in straight lines gave 34-36 m here, 13-29 m in the game).
    assert!(w.sep_air > 45.0, "separation {}", w.sep_air);
}

#[test]
fn join_up_in_a_turn_round_ramon() {
    // test_four_ship's case: the lead circles right round Ramon at 30° of bank (201 m/s: 7.1 km, 1500 m up) while the
    // wingmen start in their shelters, take off in a stream and join it in fingertip; and rejoins from 4 km and from
    // 17 km behind (the far rejoin: test_four_ship's wingmen 17 km off after a SAM defence), all three arriving
    // together.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let _turn = HANGARS.lock().unwrap_or_else(|e| e.into_inner());
    for behind in [None, Some(4000.0), Some(17_000.0)] {
        join_turn(&dir, behind);
    }
}

/// The game's 0.1 s frames under its time compression until all three are in position, then every slot held within
/// 60 m for 30 s at 60 frames a second; the lead in 4 steps a frame, its wingmen in one (on purpose: the game steps
/// every jet `time_factor` times, and the flight reads them at one instant either way).
fn join_turn(dir: &Path, behind: Option<f64>) {
    autopilot::reset_hangars();
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let rb = bases.iter().find(|b| b.name == "Ramon").unwrap().clone();
    let r = Vec3::new(rb.lineup[0] as f64, rb.lineup[1] as f64, rb.lineup[2] as f64);
    let z = r[2] + 1500.0;
    // Heading east 6 km north of Ramon: forward is east, right is south.
    let air = |n: usize, back: f64| {
        let s = if n == 0 { [0.0; 3] } else { SHAPES[0].1[n - 1] };
        (Vec3::new(r[0] + s[0] as f64 - back, r[1] + 6000.0 - s[1] as f64, z), 90.0)
    };
    let shelter = |h: usize| {
        let p = rb.hangars[h];
        (Vec3::new(p.x as f64, p.y as f64, r[2]), p.hdg.to_degrees())
    };
    let mut w = match behind {
        Some(b) => World::new(dir, [air(0, 0.0), air(1, b), air(2, b), air(3, b)], 201.0, true, r[2] as f32),
        None => {
            let mut w = World::new(dir, [shelter(0), shelter(1), shelter(2), shelter(3)], 0.0, false, r[2] as f32);
            let (p, e) = iaf_flight::load_with(dir, "F-16I", DataSet::Original).unwrap();
            let (pos, _) = air(0, 0.0);
            let velocity = Vec3::new(201.0, 0.0, 0.0);
            let st = Start {
                position: pos,
                pitch: 0.0,
                roll: 0.0,
                heading: 90f32.to_radians(),
                velocity,
                airborne: true,
                engine_on: true,
            };
            w.jets[0].0 = Fm::start("F-16I", p, e, st);
            w
        }
    };
    let home = Waypoint { x: r[0] + 10_000.0, y: r[1] + 4000.0, z: r[2] + 500.0, t: 0.0, action: 7 };
    for (_, ap) in &mut w.jets {
        ap.route = vec![home];
    }
    w.flight = Flight::default();
    for (i, (fm, ap)) in w.jets.iter_mut().enumerate() {
        w.flight.add(i as u8 + 1, i > 0, fm, ap);
    }
    match behind {
        Some(_) => assert!(w.flight.command(0.0, 0, "rejoin")),
        None => w.flight.start_up(0.0),
    }
    (w.dt, w.lead_speed, w.lead_steps, w.jitter) = (0.1, Some(201.0), 4, 0.5);
    // The player's F-16 autopilot: ALT HOLD and HDG SEL, the heading bug 30° right of the heading (a 30° bank).
    let bug = |w: &mut World| {
        let Fm::SixDof(s) = &mut w.jets[0].0 else { unreachable!() };
        s.ap_panel.hdg_bug = Some((s.state().heading.to_degrees() as f64 + 30.0).rem_euclid(360.0));
    };
    bug(&mut w);
    if let Fm::SixDof(s) = &mut w.jets[0].0 {
        s.ap_switch(1, HDG_SEL).unwrap();
        s.ap_switch(0, ALT_HOLD).unwrap();
    }
    let mut trace: Vec<String> = Vec::new();
    // Each second: the wingmen's slot errors (A: pulling away, T: in transit) into the trace; the worst error while
    // `measure`.
    let second = |w: &mut World, trace: &mut Vec<String>, measure: bool| {
        let mut worst: f32 = 0.0;
        for _ in 0..(1.0 / w.dt).round() as usize {
            bug(w);
            worst = worst.max(w.worst(w.dt, &|_| measure));
        }
        let line: Vec<_> = (w.flight.members[1..].iter())
            .map(|m| {
                let a = if m.order.avoid.is_some() { "A" } else { "" };
                let t = if m.order.slot[2] < m.slot[2] { "T" } else { "" };
                format!("#{} {:.0} m{a}{t}", m.number, m.slot_error)
            })
            .collect();
        trace.push(format!("t {:.0}: {}", w.t, line.join(", ")));
        worst
    };
    let joined = |w: &World| (2..=4).all(|n| w.said(n, "in_position").is_some());
    while w.t < 900.0 && !joined(&w) {
        second(&mut w, &mut trace, false);
    }
    assert!(joined(&w), "all three in position by {:.0} s:\n{}", w.t, trace.join("\n"));
    w.dt = DT;
    let h0 = w.jets[0].0.state().heading;
    let held = (0..30).map(|_| second(&mut w, &mut trace, true)).fold(0f32, f32::max);
    let turned = ((w.jets[0].0.state().heading - h0).to_degrees() as f64).rem_euclid(360.0);
    assert!((40.0..180.0).contains(&turned), "the lead turned right {turned:.0}° in the 30 s");
    let said: Vec<_> = (2..=4).map(|n| w.said(n, "in_position").unwrap_or(0.0).round()).collect();
    let tail = trace[trace.len().saturating_sub(60)..].join("\n");
    println!(
        "join-up in a 30° turn ({behind:?} m behind, else from the shelters): in position at {said:?} s, then worst slot \
         error {held:.1} m; separation {:.1} m (t {:.0} s, #{} and #{})",
        w.sep_air, w.sep_at.0, w.sep_at.1, w.sep_at.2
    );
    assert!(held < 60.0, "slots held in the turn: worst {held:.1} m\n{tail}");
    assert!(w.sep_air > 30.0, "air separation {}", w.sep_air);
}

#[test]
fn ground_run_at_ramon() {
    // Start-up in the four Sufa shelters (Ramon's hangars 0–3, each with its own taxi path), taxi in order behind the
    // lead, stream take-off, join-up, a route, the landing in order and each to its own shelter, engine off. Each
    // carries 2 t of stores (the lesson's jets carry the player's load): with the original's take-off law every one
    // burst its main tyres past 225 kt on the runway.
    ground_run("F-16I");
}

#[test]
fn mig29_ground_run_at_ramon() {
    // K2 (modern-iaf/docs/ai-plan.md): the MiG-29A, an AI type of its own aircraft definition, flies the same ground
    // run on its 6-DoF set: start-up, taxi, take-off, the autopilot's route and join-up, landing and parking. Ramon
    // stands in for an enemy base (the sim has none yet); its CPU per jet (X5) is printed.
    ground_run("MiG-29A");
}

#[test]
fn mig29_ground_run_at_nevatim() {
    // The same at Nevatim: #2, sent home abeam of the landing waypoint and near it, circled it at KeepAttitude's
    // 45° bank until its fuel ran out, before GoHome's pass on the 6-DoF counted within 1.5 turns' radius.
    ground_run_at("MiG-29A", "Nevatim");
}

fn ground_run(ty: &str) {
    ground_run_at(ty, "Ramon");
}

fn ground_run_at(ty: &str, base: &str) {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let _turn = HANGARS.lock().unwrap_or_else(|e| e.into_inner());
    autopilot::reset_hangars();
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let rb = bases.iter().find(|b| b.name == base).unwrap().clone();
    let z = rb.lineup[2];
    let l = Vec3::new(rb.lineup[0] as f64, rb.lineup[1] as f64, z as f64);
    let (s, c) = (rb.runway_deg as f64).to_radians().sin_cos();
    let at = |along: f64, right: f64, up: f64| {
        Vec3::new(l[0] + along * s + right * c, l[1] + along * c - right * s, l[2] + up)
    };
    let shelter = |h: usize| {
        let p = rb.hangars[h];
        (Vec3::new(p.x as f64, p.y as f64, z as f64), p.hdg.to_degrees())
    };
    let mut w = World::of_type(&dir, ty, [shelter(0), shelter(1), shelter(2), shelter(3)], 0.0, false, z);
    // Take-off point, a turn to the north-east, the landing waypoint 15 km out on the approach.
    let wp = |p: Vec3, action: i32| Waypoint { x: p[0], y: p[1], z: p[2], t: 0.0, action };
    let route = vec![
        wp(at(15_000.0, 0.0, 1500.0), 2),
        wp(at(30_000.0, -30_000.0, 2500.0), 3),
        wp(at(-35_000.0, -10_000.0, 2500.0), 3),
        wp(at(-15_000.0, 0.0, 1500.0), 7),
    ];
    for (_, ap) in &mut w.jets {
        ap.route = route.clone();
    }
    for (fm, _) in &mut w.jets {
        fm.set_stores(2000.0, 0.0, 0.0);
    }
    let homes: Vec<_> = w.jets.iter().map(|(_, ap)| ap.home_hangar).collect();
    println!("home hangars {homes:?}");
    w.flight.start_up(0.0);
    w.jets[0].0.start_engine();
    let mut airborne = [None; 4];
    let mut landed = [None; 4];
    // The join-up: each wingman's least slot error while the lead flies the route.
    let mut least = [f32::MAX; 3];
    // The take-off's highest pitch on the wheels, deg (a tail strike past 15°).
    let mut rotation = [0f32; 4];
    // The pitch (deg; a tail strike past 15°: aircraft::landing_limits) and the speed (kt) at the touchdown.
    let mut touchdown = [None; 4];
    let parked = |w: &World| w.jets.iter().all(|(fm, ap)| ap.landed && !fm.engine_on() && fm.state().speed < 0.5);
    while w.t < 4000.0 && !parked(&w) {
        // The scripted lead: mode 9 once its engine runs, the route from the take-off point, home at the landing
        // waypoint (the 1998 brain's rules).
        let (fm, ap) = &mut w.jets[0];
        if ap.mode() == 0 && fm.engine_on() && !ap.landed {
            ap.set_mode(fm, 9);
        } else if ap.mode() == 9 && ap.stage().starts_with("take-off stage 3") {
            ap.wp_index = 1;
            ap.set_mode(fm, 7);
        } else if ap.mode() == 7 && ap.wp_index == 3 {
            ap.set_mode(fm, 8);
        }
        w.frame();
        for i in 0..4 {
            let (fm, ap) = &w.jets[i];
            let st = fm.state();
            if !ap.airborne && st.on_ground {
                rotation[i] = rotation[i].max(st.pitch.to_degrees());
            }
            if ap.airborne && st.on_ground && touchdown[i].is_none() {
                touchdown[i] = Some((st.pitch.to_degrees(), st.speed * 1.943844));
            }
            if ap.airborne && airborne[i].is_none() {
                airborne[i] = Some(w.t);
            }
            if ap.landed && landed[i].is_none() {
                landed[i] = Some(w.t);
            }
            if i > 0 && ap.airborne && w.jets[0].1.mode() == 7 {
                least[i - 1] = least[i - 1].min(w.flight.member(i as u8 + 1).unwrap().slot_error);
            }
        }
        if ((w.t * 60.0).round() as u64).is_multiple_of(60 * 60) {
            let st: Vec<_> =
                w.jets.iter().map(|(fm, ap)| format!("{} {:.0} m/s", ap.stage(), fm.state().speed)).collect();
            println!("t {:.0}: {st:?}", w.t);
        }
    }
    println!("{ty}: airborne {airborne:?}\nlanded {landed:?}\nhighest pitch on the wheels at take-off {rotation:?}");
    println!("{ty}: pitch and speed at the touchdown {touchdown:?}");
    assert!(touchdown.iter().all(|t| t.is_some_and(|(p, _)| p < 15.0)), "touchdown {touchdown:?}");
    println!("{ty}: {:.2} µs per jet per frame (FM + autopilot + AI)", w.us_per_jet_frame());
    assert!(rotation.iter().all(|&p| p < 13.0), "take-off pitch on the wheels {rotation:?}");
    // The join-up calls "in position" (#4, airborne 110 s after the lead, is still about 10 km behind when this short
    // route turns home).
    for n in 2..=4u8 {
        let said = w.calls.iter().find(|(_, c)| c.from == n && c.id == "in_position").map(|(t, _)| *t);
        println!("#{n}: join-up least slot error {:.1} m, in position at {said:?}", least[n as usize - 2]);
        assert!(n == 4 || said.is_some_and(|t| t > airborne[n as usize - 1].unwrap()), "#{n} joined up, in position");
    }
    println!(
        "separation: ground {:.1} m (t {:.0} s, #{} and #{}), air {:.1} m (t {:.0} s, #{} and #{})",
        w.sep_ground,
        w.sep_ground_at.0,
        w.sep_ground_at.1,
        w.sep_ground_at.2,
        w.sep_air,
        w.sep_at.0,
        w.sep_at.1,
        w.sep_at.2
    );
    for (i, (fm, ap)) in w.jets.iter().enumerate() {
        let p = fm.state().position;
        let h = rb.hangars[i];
        let off = (p.x - h.x as f64).hypot(p.y - h.y as f64);
        let burst = fm.limits().map_or(0, |l| l.tyres_burst);
        println!(
            "#{}: {}, engine {}, {off:.0} m from its shelter, {burst} tyres burst",
            i + 1,
            ap.stage(),
            fm.engine_on()
        );
        assert!(ap.landed && !fm.engine_on() && off < 40.0, "#{} parked at its shelter", i + 1);
        assert_eq!(burst, 0, "#{}: tyres burst", i + 1);
    }
    let order = |t: [Option<f64>; 4]| t.windows(2).all(|p| p[0].unwrap() < p[1].unwrap());
    assert!(order(airborne), "take-off in order");
    assert!(order(landed), "landing in order");
    // Nevatim's four shelters share one taxi-in path, where #4 closed to 1 m on #2 (open, docs/ai.md §18.4).
    if base != "Nevatim" {
        assert!(w.sep_ground > 30.0, "ground separation {}", w.sep_ground);
    }
    assert!(w.sep_air > 30.0, "air separation {}", w.sep_air);
}

#[test]
fn a_lead_landing_away_from_home() {
    // The flight's home is Nevatim, but the lead lands at Ramon, its gear down late: the sequence starts with the lead
    // low on final; the wingmen not yet sent home hold where they are until their turn, and all land at Ramon.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let _turn = HANGARS.lock().unwrap_or_else(|e| e.into_inner());
    autopilot::reset_hangars();
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let base = |name: &str| bases.iter().find(|b| b.name == name).unwrap().clone();
    let (rb, nb) = (base("Ramon"), base("Nevatim"));
    let z = rb.lineup[2];
    let l = Vec3::new(rb.lineup[0] as f64, rb.lineup[1] as f64, z as f64);
    let (s, c) = (rb.runway_deg as f64).to_radians().sin_cos();
    let at = |along: f64, up: f64| Vec3::new(l[0] + along * s, l[1] + along * c, l[2] + up);
    let start = |n: usize| {
        let o = if n == 0 { [0.0; 3] } else { SHAPES[0].1[n - 1] };
        let p = at(-40_000.0 + o[0] as f64, 2500.0);
        (Vec3::new(p[0] + o[1] as f64 * c, p[1] - o[1] as f64 * s, p[2]), rb.runway_deg.to_degrees())
    };
    let mut w = World::new(&dir, [start(0), start(1), start(2), start(3)], 205.889, true, z);
    let wp = |p: Vec3| Waypoint { x: p[0], y: p[1], z: p[2], t: 0.0, action: 7 };
    w.jets[0].1.route = vec![wp(Vec3::new(nb.lineup[0] as f64, nb.lineup[1] as f64, nb.lineup[2] as f64 + 1500.0))];
    w.flight = Flight::default();
    for (i, (fm, ap)) in w.jets.iter_mut().enumerate() {
        w.flight.add(i as u8 + 1, i > 0, fm, ap);
    }
    for (_, ap) in &mut w.jets {
        ap.route = vec![wp(at(-15_000.0, 1500.0))];
    }
    let (fm, ap) = &mut w.jets[0];
    ap.set_mode(fm, 8);
    let mut landed = [None; 4];
    let mut held = [false; 4];
    while w.t < 3000.0 && !w.jets.iter().all(|(fm, ap)| ap.landed && !fm.engine_on()) {
        w.frame();
        for i in 0..4 {
            let ap = &w.jets[i].1;
            held[i] |= ap.mode() == 10;
            if ap.landed && landed[i].is_none() {
                landed[i] = Some(w.t);
            }
        }
    }
    println!(
        "landed {landed:?}, held {held:?}; air separation {:.1} m (t {:.0} s, #{} and #{})",
        w.sep_air, w.sep_at.0, w.sep_at.1, w.sep_at.2
    );
    for (i, (fm, ap)) in w.jets.iter().enumerate() {
        let p = fm.state().position;
        let d = (p.x - l[0]).hypot(p.y - l[1]);
        println!("#{}: {}, engine {}, {d:.0} m from Ramon's lineup", i + 1, ap.stage(), fm.engine_on());
        assert!(ap.landed && !fm.engine_on() && d < 5000.0, "#{} landed at Ramon", i + 1);
    }
    assert!(landed.windows(2).all(|p| p[0].unwrap() < p[1].unwrap()), "landing in order");
    assert!(held[3], "#4 held until its turn");
    assert!(w.sep_air > 30.0, "air separation {}", w.sep_air);
}

/// The worst slot error of wingman `n` over `seconds`, m.
fn worst_of(w: &mut World, n: u8, seconds: f64) -> f32 {
    let mut worst: f32 = 0.0;
    for _ in 0..(seconds / w.dt) as usize {
        w.frame();
        worst = worst.max(w.flight.member(n).map_or(0.0, |m| m.slot_error));
    }
    worst
}

#[test]
fn elements_split_and_regroup() {
    // Two elements: #2 on #1, #4 on #3 (#4's slot relative to #3); the lead splits element 2 to its own target in the
    // same area, element 2 circles it with #4 on #3 while #2 stays on #1, then regroups (ai-plan F12).
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let mut w = airborne(&dir, 0.0);
    w.run(30.0);
    assert_eq!([2, 3, 4].map(|n| w.flight.leader(n)), [1, 1, 1], "in the shape each on the lead (#4 on #3's slot)");
    // Too far for one area: unable, no task.
    let p = w.jets[0].0.ap_view().pos;
    let t0 = w.t;
    assert!(w.flight.split(w.t, p + Vec3::new(80_000.0, 0.0, 0.0)));
    w.run(2.0);
    assert!(w.said(3, "unable").is_some_and(|t| t >= t0) && w.flight.member(3).unwrap().task.is_none());
    // Target B 12 km ahead and 6 km right of the lead.
    let b = p + Vec3::new(6_000.0, 12_000.0, -2000.0);
    let t0 = w.t;
    assert!(w.flight.split(w.t, b));
    let near = |w: &World| {
        let q = w.jets[2].0.ap_view().pos;
        (q[0] - b[0]).hypot(q[1] - b[1]) < 4000.0
    };
    let there = w.until(200.0, &near);
    assert_eq!([2, 4].map(|n| w.flight.leader(n)), [1, 3], "#4 on #3 on its task");
    let (two, four) = (worst_of(&mut w, 2, 60.0), worst_of(&mut w, 4, 60.0));
    let q = w.jets[2].0.ap_view().pos;
    println!(
        "split: #3 at B after {there:?} s, {:.0} m from it a minute on, at {:.0} m; #2 on #1 worst {two:.1} m, #4 on #3 \
         worst {four:.1} m; #1 {:.0} m from B",
        (q[0] - b[0]).hypot(q[1] - b[1]),
        q[2],
        w.jets[0].0.ap_view().pos.distance(b)
    );
    assert!(w.said(3, "ack").is_some_and(|t| t >= t0) && w.said(4, "ack").is_some_and(|t| t >= t0));
    assert!(there.is_some(), "#3 at its target");
    assert!((q[0] - b[0]).hypot(q[1] - b[1]) < 10_000.0, "#3 circles its target");
    assert!((q[2] - 3000.0).abs() < 300.0, "at its height ({:.0} m)", q[2]);
    assert!(two <= 30.0, "#2 on #1 {two}");
    assert!(four <= 120.0, "#4 on #3 in its turns {four}");
    // Regroup.
    let t0 = w.t;
    assert!(w.flight.command(w.t, 0, "regroup"));
    // (Element 2 catches up 20–30 km at the slot loop's 60 m/s overtake.)
    let back = w.until(900.0, &|w| [3, 4].iter().all(|&n| w.said(n, "in_position").is_some_and(|t| t > t0)));
    println!("regroup: in position after {back:?} s; separation {:.1} m", w.sep_air);
    assert!(back.is_some(), "regrouped");
    assert!(w.flight.member(3).unwrap().task.is_none());
    assert!(w.sep_air > 30.0, "separation {}", w.sep_air);
    // #3 lost: #4 flies on #1.
    w.alive[2] = false;
    w.run(2.0);
    assert_eq!(w.flight.leader(4), 1);
}

#[test]
fn reactions_to_locks_launches_and_awacs() {
    // A lock from the ground on #2, an infrared missile at #3: each calls and defends (the beam, the break into the
    // missile), #3 with its flares (a lock alone takes no chaff; a radar missile one at its cue, then inside ecm.rs
    // WINDOW_S), #3's mate #4 calls the break, each rejoins when clear. An AWACS call ahead is reported by #2.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let mut w = airborne(&dir, 0.0);
    w.run(30.0);
    let t0 = w.t;
    assert_eq!(w.flight.awacs(w.t, 0.0, 25.0, true), 2, "#2 holds a contact ahead");
    assert_eq!(w.flight.awacs(w.t, 180.0, 25.0, true), 0, "none behind");
    assert_eq!(w.flight.awacs(w.t, 0.0, 25.0, false), 0, "no report for friendlies");
    // A lock on #2 from a radar 30 km ahead-right: the beam is 45° left of the track (north).
    let p = w.jets[1].0.ap_view().pos;
    let radar = Threat {
        pos: p + Vec3::new(21_000.0, 21_000.0, -3000.0),
        vel: Vec3::ZERO,
        launch: false,
        ir: false,
        ground: true,
    };
    w.flight.threat(2, Some(radar));
    let mut chaff = false;
    let mut steer = false;
    for _ in 0..(20.0 / w.dt) as usize {
        w.frame();
        chaff |= w.flight.member(2).unwrap().order.decoy == Some(Decoy::Chaff);
        steer |= w.jets[1].1.mode() == MODE_STEER;
    }
    // The radar off #2's track, deg.
    let v = w.jets[1].0.ap_view();
    let d = radar.pos - v.pos;
    let off = (v.vel[0] * d[1] - v.vel[1] * d[0]).atan2(v.vel[0] * d[0] + v.vel[1] * d[1]).to_degrees();
    let mud = w.said(2, "mud").map(|t| t - t0);
    println!("lock on #2: mud after {mud:?} s, chaff {chaff}, the radar {off:.0}° off the track");
    assert!(mud.is_some_and(|t| t <= 1.6), "#2 calls the lock");
    assert!(!chaff && steer, "#2 defends, no chaff against a lock");
    assert!((off.abs() - 90.0).abs() < 20.0, "#2 beams the radar ({off:.0}°)");
    // The radar's missile at #2, 30 km and some 35 s out: one chaff at the launch's cue (cmds.rs AUTO), then none
    // while it is outside the window.
    let vel = (v.pos - radar.pos).try_normalize().unwrap() * 850.0;
    w.flight.threat(2, Some(Threat { vel, launch: true, ..radar }));
    // (The order stands for one decision, DECIDE_S: its frames count once.)
    let (mut cued, mut was) = (0, false);
    for _ in 0..(5.0 / w.dt) as usize {
        w.frame();
        let now = w.flight.member(2).unwrap().order.decoy == Some(Decoy::Chaff);
        cued += (now && !was) as u32;
        was = now;
    }
    assert_eq!(cued, 1, "#2's chaff at the launch's cue");
    w.flight.threat(2, Some(radar));
    // An infrared missile at #3 from behind-left, 2.8 km and 4 s out: the break into it (left), flares at military
    // power, #4 calls it.
    let t1 = w.t;
    let q = w.jets[2].0.ap_view().pos;
    let at = q + Vec3::new(-2000.0, -2000.0, 0.0);
    let vel = (q - at).try_normalize().unwrap() * 850.0;
    w.flight.threat(3, Some(Threat { pos: at, vel, launch: true, ir: true, ground: false }));
    let (mut flares, mut g, mut thr) = (false, 0f32, 0f32);
    for _ in 0..(12.0 / w.dt) as usize {
        w.frame();
        flares |= w.flight.member(3).unwrap().order.decoy == Some(Decoy::Flare);
        if w.flight.member(3).unwrap().defending {
            g = g.max(w.jets[2].0.state().g);
            thr = thr.max(w.jets[2].0.controls().throttle);
        }
    }
    println!(
        "launch at #3: defending {:?}, #4 {:?}, flares {flares}, up to {g:.1} g, throttle at most {thr:.2}",
        w.said(3, "defending").map(|t| t - t1),
        w.said(4, "break_left").map(|t| t - t1)
    );
    assert!(w.said(3, "defending").is_some_and(|t| t >= t1), "#3 calls defending");
    assert!(w.said(4, "break_left").is_some_and(|t| t >= t1), "#4 calls the break");
    assert!(flares && g > 4.0 && thr <= 0.74, "flares, above 4 g, no afterburner");
    // Clear: both rejoin.
    let t2 = w.t;
    w.flight.threat(2, None);
    w.flight.threat(3, None);
    let back = w.until(400.0, &|w| [2, 3].iter().all(|&n| w.said(n, "in_position").is_some_and(|t| t > t2)));
    println!("clear: in position after {back:?} s; separation {:.1} m", w.sep_air);
    assert!(back.is_some(), "rejoined");
    assert!(w.sep_air > 30.0, "separation {}", w.sep_air);
}

#[test]
fn engage_my_target_and_rejoin() {
    // "Engage my target" to the flight: #2 and #3 fly at the target, #4 stays on #3; with no target each says
    // "unable"; the target gone, they rejoin and call "in position".
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let mut w = airborne(&dir, 0.0);
    w.run(30.0);
    let t0 = w.t;
    assert_eq!(w.flight.engage(w.t, 2, None), Some(false));
    w.run(2.0);
    assert!(w.said(2, "unable").is_some_and(|t| t >= t0) && !w.flight.member(2).unwrap().engaging);
    // A target 20 km ahead and 5 km left of the lead.
    let p = w.jets[0].0.ap_view().pos;
    let at = p + Vec3::new(-5_000.0, 20_000.0, 0.0);
    let t0 = w.t;
    // The host's weapons: a missile left (wing_battle.rs fights with them).
    for n in 2..=4 {
        w.flight.weapons(n, (40_000.0, 2_000.0), true, false);
    }
    assert_eq!(w.flight.engage(w.t, 0, Some(Bogey { pos: at, vel: Vec3::ZERO })), Some(true));
    let flat = |w: &World, j: usize| {
        let q = w.jets[j].0.ap_view().pos;
        (q[0] - at[0]).hypot(q[1] - at[1])
    };
    let (d2, d3) = (flat(&w, 1), flat(&w, 2));
    w.run(30.0);
    println!("engage: #2 {d2:.0} → {:.0} m, #3 {d3:.0} → {:.0} m from the target", flat(&w, 1), flat(&w, 2));
    assert!([2, 3, 4].iter().all(|&n| w.said(n, "ack").is_some_and(|t| t >= t0)));
    assert!(w.flight.member(2).unwrap().engaging && w.flight.member(3).unwrap().engaging);
    assert!(!w.flight.member(4).unwrap().engaging && w.flight.leader(4) == 3, "#4 on #3");
    assert!(flat(&w, 1) < d2 - 3_000.0 && flat(&w, 2) < d3 - 3_000.0, "both close on the target");
    // The target gone: back in the shape.
    let t0 = w.t;
    w.flight.target(None, 0.0);
    let back = w.until(600.0, &|w| [2, 3].iter().all(|&n| w.said(n, "in_position").is_some_and(|t| t > t0)));
    println!("engage: rejoined after {back:?} s; separation {:.1} m", w.sep_air);
    assert!(back.is_some() && w.flight.member(2).unwrap().task.is_none());
    assert!(w.sep_air > 30.0, "separation {}", w.sep_air);
}

/// The close shapes changed in the lead's continuous 45° bank turn, as test_four_ship does in the game's: each wingman
/// calls "in position", then within 60 s all are within 60 m of their slots and stay so for 20 s (the turn's
/// tolerance there; a wingman pulled away by the collision avoidance in the change takes that long to come back, as
/// a real one drifts too).
#[test]
fn close_shapes_changed_in_a_turn() {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let mut w = airborne(&dir, 0.0);
    w.run(30.0);
    // Every 10 s the lead turns toward the point 90° right of its track.
    let turn = |w: &mut World| {
        let v = w.jets[0].0.ap_view();
        let (p, d) = (v.pos, v.vel.try_normalize().unwrap());
        w.lead_to(Vec3::new(p[0] + d[1] * 30_000.0, p[1] - d[0] * 30_000.0, 3000.0));
    };
    turn(&mut w);
    w.run(30.0);
    for id in ["diamond", "vic", "delta", "echelon_left", "echelon_right", "fingertip"] {
        let t0 = w.t;
        assert!(w.flight.command(w.t, 0, id));
        // In position (s after the command); all within 60 m since (s); held 20 s (s after "in position").
        let (mut said, mut since, mut held, mut worst) = (None, None, None, 0f32);
        while w.t - t0 < 300.0 && held.is_none() {
            w.frame();
            if (((w.t - t0) / w.dt).round() as usize).is_multiple_of(600) {
                turn(&mut w);
            }
            let e = (2..=4).map(|n| w.flight.member(n).unwrap().slot_error).fold(0.0, f32::max);
            if said.is_none() && (2..=4).all(|n| w.said(n, "in_position").is_some_and(|t| t > t0)) {
                said = Some(w.t - t0);
            } else if let Some(s) = said {
                worst = worst.max(e);
                since = if e < 60.0 { since.or(Some(w.t)) } else { None };
                if since.is_some_and(|b| w.t - b >= 20.0) {
                    held = Some(w.t - t0 - s);
                }
            }
        }
        println!(
            "{id} in the turn: in position after {said:?} s, held 20 s within 60 m {held:?} s later (worst {worst:.0} m)"
        );
        assert!(said.is_some() && held.is_some_and(|h| h <= 80.0), "{id}: {said:?} {held:?}");
    }
    assert!(w.sep_air > 30.0, "separation {}", w.sep_air);
}
