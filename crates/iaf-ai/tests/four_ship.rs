//! The four-ship (modern-iaf/docs/ai-plan.md §6) on the 6-DoF Sufa and the sim's own data: #1 is a scripted lead flown
//! by the existing autopilot, #2–#4 the AI. Skips with a message when `assets/converted/own` is not built.

use std::path::{Path, PathBuf};

use iaf_ai::{Call, Flight, SHAPES, apply};
use iaf_flight::airbase::Airbase;
use iaf_flight::autopilot::{self, Autopilot, Config, Host, Waypoint};
use iaf_flight::fm::Fm;
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
    /// Each jet's last 20 s, every 0.5 s, for a failure's message.
    trace: [std::collections::VecDeque<String>; 4],
}

impl World {
    /// Four Sufas (F-16I) at `starts` (position, heading deg); #1 the scripted lead.
    fn new(dir: &Path, starts: [(Vec3, f32); 4], speed: f64, airborne: bool, ground: f32) -> World {
        let (p, e) = iaf_flight::load_with(dir, "F-16I", DataSet::Original).unwrap();
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
            let fm = Fm::start("F-16I", p.clone(), e.clone(), st);
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
            trace: Default::default(),
        }
    }

    fn frame(&mut self) {
        let clock = std::time::Instant::now();
        for (i, (fm, ap)) in self.jets.iter().enumerate() {
            self.flight.sense(i as u8 + 1, self.alive[i], fm, ap);
        }
        for c in self.flight.step(self.t) {
            self.calls.push((self.t, c));
        }
        let g = self.ground;
        for (i, (fm, ap)) in self.jets.iter_mut().enumerate() {
            if !self.alive[i] {
                continue;
            }
            if i > 0 {
                apply(&self.flight.members[i].order, ap, fm);
            }
            if let Fm::SixDof(s) = fm {
                s.set_ground_height(g);
            }
            ap.step(fm, &|_, _| g);
            fm.step(DT);
        }
        self.busy += clock.elapsed();
        self.frames += 1;
        self.t += DT;
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

    fn run(&mut self, seconds: f64) {
        for _ in 0..(seconds / DT) as usize {
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
        for _ in 0..(seconds / DT) as usize {
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
    let back = w.until(10.0, &|w| w.jets[1..].iter().all(|(_, ap)| ap.mode() == iaf_flight::autopilot::MODE_SLOT));
    let there = w.until(1500.0, &|w| (2..=4).all(|n| w.said(n, "in_position").is_some_and(|t| t > t0)));
    println!("rejoin after the RTB: back in the slot after {back:?} s, in position after {there:?} s more");
    assert!(back.is_some() && there.is_some(), "rejoin after the RTB");
    assert!(w.sep_air > 30.0, "separation {}", w.sep_air);
}

#[test]
fn ground_run_at_ramon() {
    // Start-up in the four Sufa shelters (Ramon's hangars 0–3, each with its own taxi path), taxi in order behind the
    // lead, stream take-off, join-up, a route, the landing in order and each to its own shelter, engine off.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    let _turn = HANGARS.lock().unwrap_or_else(|e| e.into_inner());
    autopilot::reset_hangars();
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let rb = bases.iter().find(|b| b.name == "Ramon").unwrap().clone();
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
    let mut w = World::new(&dir, [shelter(0), shelter(1), shelter(2), shelter(3)], 0.0, false, z);
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
    let homes: Vec<_> = w.jets.iter().map(|(_, ap)| ap.home_hangar).collect();
    println!("home hangars {homes:?}");
    w.flight.start_up(0.0);
    w.jets[0].0.start_engine();
    let mut airborne = [None; 4];
    let mut landed = [None; 4];
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
            let ap = &w.jets[i].1;
            if ap.airborne && airborne[i].is_none() {
                airborne[i] = Some(w.t);
            }
            if ap.landed && landed[i].is_none() {
                landed[i] = Some(w.t);
            }
        }
        if ((w.t * 60.0).round() as u64).is_multiple_of(60 * 60) {
            let st: Vec<_> =
                w.jets.iter().map(|(fm, ap)| format!("{} {:.0} m/s", ap.stage(), fm.state().speed)).collect();
            println!("t {:.0}: {st:?}", w.t);
        }
    }
    println!("airborne {airborne:?}\nlanded {landed:?}");
    println!(
        "separation: ground {:.1} m, air {:.1} m (t {:.0} s, #{} and #{})",
        w.sep_ground, w.sep_air, w.sep_at.0, w.sep_at.1, w.sep_at.2
    );
    for (i, (fm, ap)) in w.jets.iter().enumerate() {
        let p = fm.state().position;
        let h = rb.hangars[i];
        let off = (p.x - h.x as f64).hypot(p.y - h.y as f64);
        println!("#{}: {}, engine {}, {off:.0} m from its shelter", i + 1, ap.stage(), fm.engine_on());
        assert!(ap.landed && !fm.engine_on() && off < 40.0, "#{} parked at its shelter", i + 1);
    }
    let order = |t: [Option<f64>; 4]| t.windows(2).all(|p| p[0].unwrap() < p[1].unwrap());
    assert!(order(airborne), "take-off in order");
    assert!(order(landed), "landing in order");
    assert!(w.sep_ground > 30.0, "ground separation {}", w.sep_ground);
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
