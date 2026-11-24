//! The air-defence sites (`iaf_ai::site`, docs/ai.md §15): the crews' procedure, the counts, EMCON, relocation, the
//! Tor's halt and duty limits, the ZSU's radar and optical laying, the radar cross-section and the terrain; each at
//! the crew's medium skill (its reaction before the acquisition, its launch range a share of the envelope's).

use iaf_ai::Skill;
use iaf_ai::site::{Emcon, FIGHTER, Kind, Mode, Out, Site, Target};
use iaf_flight::{Vec3, airframe};

fn flat(_: Vec3) -> Option<f64> {
    Some(0.0)
}

/// A jet of definition `def` at `pos` flying `vel`, its nose along it.
fn jet(id: &str, def: &str, pos: Vec3, vel: Vec3) -> Target {
    Target {
        id: id.into(),
        pos,
        vel,
        nose: vel.try_normalize().unwrap_or(Vec3::NORTH),
        rcs: airframe::get(def).and_then(|a| a.rcs).unwrap_or(FIGHTER),
        bays_open: false,
        stores: 0,
        cued: false,
        dlz: (0.0, 0.0),
        in_air: 0,
        jam: 0.0,
        ab: false,
    }
}

/// An F-16 `km` north of the site at 8 km, inbound at 250 m/s, inside an envelope of 40 km to 3 km.
fn inbound(id: &str, km: f64, bearing: f64) -> Target {
    let (s, c) = bearing.to_radians().sin_cos();
    let dir = Vec3::new(s, c, 0.0);
    Target { dlz: (40_000.0, 3_000.0), ..jet(id, "f16", dir * (km * 1000.0) + Vec3::UP * 8000.0, dir * -250.0) }
}

/// The medium crew's reaction (s) and launch range inside the 40 km envelope (m).
const REACT: f64 = Skill::MEDIUM.reaction_s;
const LAUNCH: f64 = 3_000.0 + 37_000.0 * Skill::MEDIUM.launch_range;

/// Coming at a site to the south (a Tor's Doppler radars lose a jet without speed along the line of sight).
const INBOUND: Vec3 = Vec3::new(0.0, -200.0, 0.0);

/// The first tick (0.5 s steps) at which `f` holds.
fn first_tick(f: impl Fn(f64) -> bool) -> f64 {
    (0..100_000).map(|i| i as f64 * 0.5).find(|&t| f(t)).unwrap()
}

/// `inbound(km, 0)`'s slant range and closing speed at time `t`.
fn slant(km: f64, t: f64) -> (f64, f64) {
    let y = km * 1000.0 - 250.0 * t;
    let s = y.hypot(8000.0);
    (s, 250.0 * y / s)
}

/// A site ticked every 0.5 s, its targets flying straight (`still`: held in place, their velocity only seen by the
/// radars); each missile flies `fly` s.
struct Sim {
    site: Site,
    still: bool,
    now: f64,
    targets: Vec<Target>,
    alive: Vec<bool>,
    fly: f64,
    flying: Vec<(String, f64)>,
    log: Vec<(f64, Out, Vec3)>,
}

impl Sim {
    fn new(site: Site, targets: Vec<Target>) -> Sim {
        let alive = vec![true; site.spec().parts.len()];
        Sim { site, still: false, now: 0.0, targets, alive, fly: 20.0, flying: Vec::new(), log: Vec::new() }
    }

    fn run(&mut self, secs: f64) {
        let end = self.now + secs;
        while self.now < end - 1e-9 {
            for t in &mut self.targets {
                t.in_air = self.flying.iter().filter(|f| f.0 == t.id && f.1 > self.now).count() as u32;
            }
            let out = self.site.tick(self.now, &self.alive, &self.targets, &flat);
            for (_, id) in &out.launches {
                self.flying.push((id.clone(), self.now + self.fly));
            }
            self.log.push((self.now, out, self.site.pos));
            if !self.still {
                for t in &mut self.targets {
                    t.pos += t.vel * 0.5;
                }
            }
            self.now += 0.5;
        }
    }

    fn launches(&self) -> Vec<(f64, String)> {
        self.log.iter().flat_map(|(t, o, _)| o.launches.iter().map(|l| (*t, l.1.clone()))).collect()
    }

    fn pos(&self, t: f64) -> Vec3 {
        self.log.iter().find(|x| x.0 == t).unwrap().2
    }

    fn first(&self, f: impl Fn(&Out) -> bool) -> Option<f64> {
        self.log.iter().find(|(_, o, _)| f(o)).map(|(t, _, _)| *t)
    }
}

#[test]
fn s300_searches_tracks_and_fires_two_per_target() {
    let mut sim = Sim::new(Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]), vec![inbound("a", 60.0, 0.0)]);
    sim.run(200.0);
    assert!(sim.log[0].1.search, "the 96L6E searches from the start");
    let lock = sim.first(|o| !o.tracks.is_empty()).unwrap();
    assert_eq!(lock, REACT + 5.0, "a track the reaction and 5 s (acquisition) after detection");
    let l = sim.launches();
    assert!(l.len() >= 4, "{l:?}");
    assert_eq!(l[0].0, first_tick(|t| slant(60.0, t).0 <= LAUNCH), "the first launch at the crew's range");
    assert_eq!(l[1].0 - l[0].0, 3.0, "two missiles, 3 s apart");
    assert!(l[2].0 >= l[1].0 + 20.0, "the salvo guided to its end before the next (shoot-look-shoot): {l:?}");
    assert!(sim.site.engagements >= 1);
    assert!(
        sim.log.iter().filter(|(t, _, _)| *t >= lock && *t < 120.0).all(|(_, o, _)| o.tracks == ["a"]),
        "held while guiding"
    );
}

#[test]
fn s300_six_targets_at_once_rounds_run_out() {
    let mut targets: Vec<Target> = (0..8).map(|i| inbound(&format!("t{i}"), 45.0, i as f64 * 45.0)).collect();
    targets[5].vel = targets[5].vel * 1.5; // the most dangerous: first to arrive
    let mut sim = Sim::new(Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]), targets);
    sim.fly = 6.0;
    sim.run(400.0);
    assert!(sim.log.iter().all(|(_, o, _)| o.tracks.len() <= 6));
    assert_eq!(sim.log.iter().map(|(_, o, _)| o.tracks.len()).max(), Some(6), "six channels");
    let l = sim.launches();
    assert_eq!(l[0].1, "t5", "the most dangerous first");
    assert_eq!(l.len(), 16, "four launchers of four rounds: {}", l.len());
    assert!(l.windows(2).all(|w| w[1].0 - w[0].0 >= 3.0), "3 s between launches across the battery");
    assert!(sim.site.rounds.iter().all(|&r| r == 0));
}

#[test]
fn s300_parts_destroyed() {
    let mut sim = Sim::new(Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]), vec![inbound("a", 45.0, 0.0)]);
    sim.alive[1] = false; // the 30N6E2
    sim.alive[2] = false; // a launcher
    sim.run(60.0);
    assert!(sim.log.iter().all(|(_, o, _)| o.search && o.tracks.is_empty() && o.launches.is_empty()), "no engagement");
    assert_eq!(sim.site.rounds[2], 0, "its rounds went with the launcher");
    sim.alive = vec![false, true, true, true, true, true]; // the 96L6E
    sim.site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]);
    sim.run(5.0);
    assert!(sim.log.last().is_some_and(|(_, o, _)| !o.search), "no search");
}

#[test]
fn emcon_silent_cue_radiate() {
    let mut site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]);
    site.emcon = Emcon::Silent;
    let mut sim = Sim::new(site, vec![inbound("a", 35.0, 0.0)]);
    sim.run(60.0);
    assert!(sim.log.iter().all(|(_, o, _)| !o.search && !o.track && o.launches.is_empty()), "Silent: dark");
    assert_eq!(sim.site.phase(sim.now), "silent");

    let mut site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]);
    site.emcon = Emcon::Cue;
    let mut sim = Sim::new(site.clone(), vec![inbound("a", 60.0, 0.0)]);
    sim.run(120.0);
    assert!(sim.log.iter().all(|(_, o, _)| !o.search && !o.track), "Cue, no cue: dark");
    let mut a = inbound("a", 60.0, 0.0);
    a.cued = true;
    let mut sim = Sim::new(site, vec![a]);
    sim.run(120.0);
    assert!(sim.log.iter().all(|(_, o, _)| !o.search), "Cue: the search radar stays off");
    // On for the last seconds: the launch range plus the reaction and the acquisition's 5 s at the closing speed.
    let on = sim.first(|o| o.track).unwrap();
    let due = first_tick(|t| slant(60.0, t).0 <= LAUNCH + (REACT + 5.0) * slant(60.0, t).1);
    assert_eq!(on, due, "the track radar comes on only seconds before the envelope");
    assert!(slant(60.0, on).0 < 42_000.0);
    assert_eq!(sim.launches()[0].0, first_tick(|t| t >= on + REACT + 5.0 && slant(60.0, t).0 <= LAUNCH));
}

#[test]
fn s300_relocates_after_the_engagement() {
    let alt = Vec3::new(5000.0, 0.0, 0.0);
    let mut sim = Sim::new(Site::new(Kind::S300, Vec3::ZERO, 0.0, &[alt]), vec![inbound("a", 45.0, 0.0)]);
    sim.run(45.0);
    assert_eq!(sim.launches().len(), 2);
    sim.targets.clear(); // shot down
    sim.run(19.5);
    assert_eq!(sim.site.mode, Mode::Ready, "quiet 20 s before the march order");
    sim.run(1.0);
    assert!(matches!(sim.site.mode, Mode::March(_)));
    assert!(sim.log.last().is_some_and(|(_, o, _)| !o.search && !o.track), "radars off for the march");
    sim.run(300.0);
    assert_eq!(sim.site.mode, Mode::Move, "the march order takes 5 min");
    let p0 = sim.site.pos;
    sim.run(10.0);
    assert!((sim.site.pos.x - p0.x - 60.0).abs() < 1e-6, "no road: across country at 0.6 of its 10 m/s");
    sim.run(825.0);
    assert!(matches!(sim.site.mode, Mode::Setup(_)), "{:?}", sim.site.mode);
    assert_eq!((sim.site.pos.x, sim.site.pos.y), (alt.x, alt.y), "at the alternate position");
    assert!(sim.log.last().is_some_and(|(_, o, _)| !o.search), "setting up: silent");
    sim.run(300.0);
    assert!(sim.log.last().is_some_and(|(_, o, _)| o.search), "set up: it searches again");
}

/// The march on the roads (K5 with the convoy's routes, docs/ai.md §15): the host's road route between the road
/// points nearest the two positions; the site drives off the road to it at 0.6 of its road speed, along it at its road
/// speed, and off it to the alternate position, every point of its way on the route.
#[test]
fn s300_relocates_along_the_road() {
    let alt = Vec3::new(5000.0, 0.0, 0.0);
    let mut site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[alt]);
    (site.at, site.mode) = (1, Mode::Move);
    let road = [[0.0, 100.0], [0.0, 2000.0], [5000.0, 2000.0], [5000.0, 100.0]];
    site.reroute(&road);
    assert_eq!(site.route.road, [false, true, true, true, false], "off the road, three road legs, off the road");
    assert!((site.route.length() - 9000.0).abs() < 1e-6);
    let mut sim = Sim::new(site, vec![]);
    // 200 m across country at 6 m/s and 8,800 m of road at 10 m/s: 913.3 s.
    sim.run(913.0);
    assert_eq!(sim.site.mode, Mode::Move, "still on its way");
    let off = |p: Vec3| {
        let pts = [[0.0, 0.0], road[0], road[1], road[2], road[3], [alt.x, alt.y]];
        pts.windows(2)
            .map(|w| {
                let (a, b) = (Vec3::new(w[0][0], w[0][1], 0.0), Vec3::new(w[1][0], w[1][1], 0.0));
                let q = Vec3::new(p.x, p.y, 0.0);
                let f = ((q - a).dot(b - a) / (b - a).dot(b - a)).clamp(0.0, 1.0);
                q.distance(a + (b - a) * f)
            })
            .fold(f64::MAX, f64::min)
    };
    assert!(sim.log.iter().all(|(_, _, p)| off(*p) < 1e-6), "every point on the route");
    assert!(sim.log.iter().any(|(_, _, p)| p.y > 1999.0 && p.x > 2000.0), "it drove the road's far leg");
    assert!((sim.site.course - 180.0).abs() < 1e-6, "south on the last leg off the road: {}", sim.site.course);
    sim.run(1.0);
    assert!(matches!(sim.site.mode, Mode::Setup(_)), "{:?}", sim.site.mode);
    assert_eq!((sim.site.pos.x, sim.site.pos.y), (alt.x, alt.y));
}

#[test]
fn tor_halts_to_fire_and_keeps_its_duty_limits() {
    let mut site = Site::new(Kind::Tor, Vec3::ZERO, 0.0, &[Vec3::new(0.0, -50_000.0, 0.0)]);
    site.mode = Mode::Move;
    site.at = 1;
    let t = Target {
        dlz: (12_000.0, 1_500.0),
        ..jet("a", "f16", Vec3::new(0.0, 16_000.0, 1000.0), Vec3::new(0.0, -200.0, 0.0))
    };
    let mut sim = Sim::new(site, vec![t]);
    sim.run(40.0);
    assert!(sim.log.iter().all(|(_, o, _)| o.search), "it searches on the move");
    let l = sim.launches();
    assert!(l.len() == 2 && l[1].0 - l[0].0 == 4.0, "two missiles 4 s apart: {l:?}");
    let t0 = l[0].0;
    assert!(sim.pos(t0 - 5.5).y > sim.pos(t0 - 5.0).y, "moving until the target is in the envelope");
    assert_eq!(sim.pos(t0 - 5.0), sim.pos(t0), "then at a halt for 5 s before the shot");
    assert!(sim.site.pos.y < sim.pos(t0 + 4.0).y, "on its way again after the salvo");

    // 10 min on, 10 min off.
    let mut sim = Sim::new(Site::new(Kind::Tor, Vec3::ZERO, 0.0, &[]), vec![]);
    sim.run(1300.0);
    let on = |t: f64| sim.log.iter().find(|x| x.0 == t).unwrap().1.search;
    assert!(on(599.5) && !on(600.5) && !on(1199.5) && on(1200.5), "the duty cycle");

    // After three engagements an hour's break, with one window of a minute for a cue.
    let t = Target { dlz: (12_000.0, 1_500.0), ..jet("a", "f16", Vec3::new(0.0, 8000.0, 1000.0), INBOUND) };
    let mut sim = Sim::new(Site::new(Kind::Tor, Vec3::ZERO, 0.0, &[]), vec![t]);
    sim.still = true;
    sim.fly = 5.0;
    sim.run(60.0);
    assert_eq!(sim.launches().len(), 6, "three engagements of two");
    assert_eq!(sim.site.phase(sim.now), "rest");
    let quiet = sim.log.len();
    sim.run(100.0);
    assert!(sim.log[quiet..].iter().all(|(_, o, _)| !o.search && o.launches.is_empty()), "the break");
    sim.targets[0].cued = true;
    sim.run(70.0);
    let window: Vec<f64> = sim.log.iter().filter(|(t, o, _)| *t > 160.0 && o.search).map(|x| x.0).collect();
    assert!(!window.is_empty() && window.last().unwrap() - window[0] < 60.0, "one window of a minute: {window:?}");
    assert!(sim.launches().len() > 6, "it fires in the window");
    sim.run(600.0);
    assert!(sim.log.iter().filter(|(t, _, _)| *t > 240.0).all(|(_, o, _)| !o.search), "once only");
}

#[test]
fn tor_two_channels_and_engagements_counted_by_salvo() {
    // Three jets in reach, missiles that fly on: two channels; a jet shot down frees its channel.
    let at =
        |id: &str, x: f64| Target { dlz: (12_000.0, 1_500.0), ..jet(id, "f16", Vec3::new(x, 8000.0, 1000.0), INBOUND) };
    let mut sim =
        Sim::new(Site::new(Kind::Tor, Vec3::ZERO, 0.0, &[]), vec![at("a", 0.0), at("b", 300.0), at("c", -300.0)]);
    sim.still = true;
    sim.fly = 1000.0;
    sim.run(30.0);
    assert_eq!(sim.log.iter().map(|(_, o, _)| o.tracks.len()).max(), Some(2), "two targets at once");
    assert_eq!(sim.launches().len(), 4, "a salvo each, then guiding");
    let shot: Vec<String> = sim.launches().iter().map(|l| l.1.clone()).collect();
    sim.targets.retain(|t| !shot.contains(&t.id)); // both destroyed: no assessment ever comes
    sim.run(30.0);
    assert_eq!(sim.launches().len(), 6, "the third jet's salvo");
    assert_eq!(sim.site.phase(sim.now), "rest", "three salvos: the hour's break");
}

#[test]
fn refused_launches_count_for_nothing() {
    // The caller refuses every launch after the first (no sight from the launcher): the second missile of the salvo
    // is tried again and again, yet no salvo completes, so no engagement counts and no break comes.
    let t = Target { dlz: (12_000.0, 1_500.0), ..jet("a", "f16", Vec3::new(0.0, 8000.0, 1000.0), INBOUND) };
    let tick = |site: &mut Site, refuse_from: usize, secs: f64| {
        let alive = vec![true; site.spec().parts.len()];
        let mut n = 0;
        for i in 0..(secs * 2.0) as usize {
            let out = site.tick(i as f64 * 0.5, &alive, std::slice::from_ref(&t), &flat);
            for (p, id) in &out.launches {
                n += 1;
                if n > refuse_from {
                    site.refund(*p, id);
                }
            }
        }
        n
    };
    let mut tor = Site::new(Kind::Tor, Vec3::ZERO, 0.0, &[]);
    assert!(tick(&mut tor, 1, 120.0) > 6, "the second missile tried more than three times");
    assert!(tor.engagements == 0 && tor.phase(120.0) != "rest", "no engagement counted, no break");
    assert_eq!(tor.rounds.iter().sum::<u32>(), 7, "one round spent");

    // Every launch refused: nothing fired here, so the target gone, the site stays where it is.
    let mut tor = Site::new(Kind::Tor, Vec3::ZERO, 0.0, &[Vec3::new(0.0, -5000.0, 0.0)]);
    assert!(tick(&mut tor, 0, 30.0) > 0);
    let alive = vec![true; tor.spec().parts.len()];
    for i in 60..200 {
        tor.tick(i as f64 * 0.5, &alive, &[], &flat);
    }
    assert!(tor.at == 0 && matches!(tor.mode, Mode::Ready), "no relocation: {:?}", tor.mode);
}

#[test]
fn zsu_radar_and_optical_laying() {
    let gun =
        |km: f64| Target { dlz: (2_250.0, 0.0), ..jet("a", "f16", Vec3::new(0.0, km * 1000.0, 300.0), Vec3::ZERO) };
    // Radar: it tracks and fires bursts, on the move too, until the 2,000 rounds are gone.
    let mut site = Site::new(Kind::Zsu, Vec3::ZERO, 0.0, &[Vec3::new(-100_000.0, 0.0, 0.0)]);
    site.mode = Mode::Move;
    site.at = 1;
    site.reroute(&[[0.0, 0.0], [-100_000.0, 0.0]]); // on a road west, at its road speed
    let west = Vec3::new(-8.0, 0.0, 0.0);
    let b = Target { id: "b".into(), vel: west, ..gun(2.5) };
    let mut sim = Sim::new(site, vec![Target { vel: west, ..gun(2.0) }, b]);
    sim.run(700.0);
    assert!(sim.log.iter().all(|(_, o, _)| o.tracks.len() <= 1), "one target at a time");
    let bursts: Vec<(f64, u32)> = sim.log.iter().flat_map(|(t, o, _)| o.bursts.iter().map(|b| (*t, b.2))).collect();
    assert!(sim.log[10].1.track && sim.log[10].1.tracks == ["a"], "a radar track");
    assert_eq!(bursts[0], (REACT + 2.0, 10), "bursts of 10 rounds once acquired");
    assert!(bursts.windows(2).all(|w| w[1].0 - w[0].0 >= 3.0));
    assert_eq!(bursts.iter().map(|b| b.1).sum::<u32>(), 2000, "the load");
    assert!(sim.site.pos.x < -1000.0, "it fired on the move");
    // Silent: the radar off, laid optically within its sight's reach.
    let mut site = Site::new(Kind::Zsu, Vec3::ZERO, 0.0, &[]);
    site.emcon = Emcon::Silent;
    let mut sim = Sim::new(site.clone(), vec![gun(2.0)]);
    sim.run(10.0);
    assert!(sim.log.iter().all(|(_, o, _)| !o.search && !o.track && o.tracks.is_empty()), "no radar");
    assert!(sim.log.iter().any(|(_, o, _)| !o.bursts.is_empty()), "optical laying fires");
    let mut sim = Sim::new(site, vec![gun(6.0)]);
    sim.run(5.0);
    assert!(sim.site.channels.is_empty(), "beyond the sight");
    let mut sim = Sim::new(Site::new(Kind::Zsu, Vec3::ZERO, 0.0, &[]), vec![gun(6.0)]);
    sim.run(5.0);
    assert!(!sim.site.channels.is_empty() && sim.site.channels[0].radar, "the radar holds it at 6 km");
}

#[test]
fn ground_clutter_tor_notch_and_zsu_floor() {
    // The Tor's pulse-Doppler radars lose a jet on the beam (no speed along the line of sight); so do the S-300's (the
    // 96L6E's Doppler speeds start at 30 m/s).
    let tor = Site::new(Kind::Tor, Vec3::ZERO, 0.0, &[]);
    let s300 = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]);
    let (a1, a6) = (vec![true; tor.spec().parts.len()], vec![true; s300.spec().parts.len()]);
    let at = |vel| jet("a", "f16", Vec3::new(0.0, 10_000.0, 1000.0), vel);
    let (hot, beam) = (at(Vec3::new(0.0, -250.0, 0.0)), at(Vec3::new(250.0, 0.0, 0.0)));
    assert!(tor.detects(&a1, &hot, &flat) && tor.trackable(&a1, &hot, &flat), "coming: seen");
    assert!(!tor.detects(&a1, &beam, &flat) && !tor.trackable(&a1, &beam, &flat), "on the beam: in the notch");
    assert!(s300.detects(&a6, &hot, &flat) && s300.trackable(&a6, &hot, &flat), "the S-300: coming, seen");
    assert!(!s300.detects(&a6, &beam, &flat) && !s300.trackable(&a6, &beam, &flat), "the S-300: on the beam, lost");
    // The ZSU's radar loses a jet under 60 m in the ground's clutter; the optical sight lays on it.
    let zsu = Site::new(Kind::Zsu, Vec3::ZERO, 0.0, &[]);
    let low = |z| Target { dlz: (2_250.0, 0.0), ..jet("a", "f16", Vec3::new(0.0, 4000.0, z), INBOUND) };
    assert!(!zsu.trackable(&[true], &low(40.0), &flat) && zsu.trackable(&[true], &low(100.0), &flat));
    let mut sim = Sim::new(zsu, vec![low(40.0)]);
    sim.still = true;
    sim.run(5.0);
    assert!(!sim.site.channels.is_empty() && !sim.site.channels[0].radar, "laid optically");
}

/// The range (m) at which the S-300's search radar first detects the target `at(range)` as it comes in.
fn detection_range(at: impl Fn(f64) -> Target, terrain: &dyn Fn(Vec3) -> Option<f64>) -> f64 {
    let site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]);
    let alive = [true; 6];
    let mut r = 400_000.0;
    while r > 0.0 && !site.detects(&alive, &at(r), terrain) {
        r -= 250.0;
    }
    r
}

/// The range (m) at which the S-300's track radar can first hold the target `at(range)`.
fn track_range(at: impl Fn(f64) -> Target) -> f64 {
    let site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]);
    let alive = [true; 6];
    let mut r = 400_000.0;
    while r > 0.0 && !site.trackable(&alive, &at(r), &flat) {
        r -= 250.0;
    }
    r
}

#[test]
fn rcs_decides_the_detection_range() {
    let head_on =
        |def: &'static str| move |r: f64| jet("a", def, Vec3::new(0.0, r, 8000.0), Vec3::new(0.0, -250.0, 0.0));
    let f16 = detection_range(head_on("f16"), &flat);
    let adir = detection_range(head_on("f35i"), &flat);
    let bays = detection_range(|r| Target { bays_open: true, ..head_on("f35i")(r) }, &flat);
    let stores = detection_range(|r| Target { stores: 2, ..head_on("f35i")(r) }, &flat);
    let beam = detection_range(|r| Target { nose: Vec3::new(1.0, 0.0, 0.0), ..head_on("f35i")(r) }, &flat);
    assert!(f16 > 3.0 * adir, "the F-16 at {f16} m, the clean Adir at {adir} m");
    assert!(bays > 3.0 * adir, "the bays open: {bays} m");
    assert!(stores > 3.0 * adir, "external stores: {stores} m");
    assert!(beam > adir, "beam on: {beam} m");
    let f16_stores = detection_range(|r| Target { stores: 4, ..head_on("f16")(r) }, &flat);
    assert!(f16_stores > f16, "the F-16's stores add to it");
    // The track radar the same way.
    let (f16, adir) = (track_range(head_on("f16")), track_range(head_on("f35i")));
    let bays = track_range(|r| Target { bays_open: true, ..head_on("f35i")(r) });
    assert!(
        f16 > 3.0 * adir && bays > 3.0 * adir,
        "tracked: the F-16 at {f16} m, the Adir {adir} m, bays open {bays} m"
    );
}

#[test]
fn a_jammer_holds_the_radars_to_its_burn_through() {
    // The Sufa head on (1.2 m²) with its jammer at 0.3 (docs/ai.md §15.6): the 96L6E finds it at 300 km · 0.3 ·
    // √(1.2 / 5) = 44 km in place of 210 km, the 30N6E2 holds it inside 29 km in place of 140 km (level).
    let head_on = |jam: f64| {
        move |r: f64| Target { jam, ..jet("a", "f16", Vec3::new(0.0, r, 8000.0), Vec3::new(0.0, -250.0, 0.0)) }
    };
    let (clear, jammed) = (detection_range(head_on(0.0), &flat), detection_range(head_on(0.3), &flat));
    println!("search: {clear:.0} m clear, {jammed:.0} m jammed");
    // (8 km up the line of sight is tilted: a little of the side's return adds to the jammed figure.)
    assert!((clear - 210_000.0).abs() < 1_000.0 && (43_000.0..48_000.0).contains(&jammed));
    let (clear, jammed) = (track_range(head_on(0.0)), track_range(head_on(0.3)));
    println!("track: {clear:.0} m clear, {jammed:.0} m jammed");
    assert!((clear - 140_000.0).abs() < 1_000.0 && (28_500.0..33_000.0).contains(&jammed));
    // Inside the burn-through the jammer changes nothing.
    let site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]);
    assert!(site.detects(&[true; 6], &head_on(0.3)(40_000.0), &flat));
}

#[test]
fn terrain_and_the_earth_curvature_mask() {
    // A 1,000 m ridge 19–21 km north of the site.
    let ridge = |p: Vec3| Some(if (19_000.0..21_000.0).contains(&p.y) { 1000.0 } else { 0.0 });
    let site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[]);
    let alive = [true; 6];
    let at = |alt: f64, y: f64| jet("a", "f16", Vec3::new(0.0, y, alt), Vec3::new(0.0, -250.0, 0.0));
    assert!(!site.detects(&alive, &at(500.0, 40_000.0), &ridge), "masked behind the ridge");
    assert!(site.detects(&alive, &at(3000.0, 40_000.0), &ridge), "above the ridge line");
    assert!(site.detects(&alive, &at(500.0, 40_000.0), &flat), "the same jet without the ridge");
    // The radar horizon over flat ground: 6 m and 100 m see each other to about 51 km.
    assert!(!site.detects(&alive, &at(100.0, 60_000.0), &flat), "below the horizon");
    assert!(site.detects(&alive, &at(100.0, 45_000.0), &flat), "above it");
}

/// The crew's skill (docs/ai.md §17): the same radar finds the target at the same moment at every level; the track
/// comes the reaction and the scaled acquisition later, the first launch at the level's share of the envelope, the
/// salvo's spacing the same, the march order its scaled drill.
#[test]
fn skill_changes_the_crew_not_the_physics() {
    let half = |s: f64| (s * 2.0).ceil() / 2.0;
    let mut found = Vec::new();
    for skill in [Skill::LOW, Skill::MEDIUM, Skill::HIGH] {
        let mut site = Site::new(Kind::S300, Vec3::ZERO, 0.0, &[Vec3::new(5000.0, 0.0, 0.0)]);
        site.skill = skill;
        let mut sim = Sim::new(site, vec![inbound("a", 60.0, 0.0)]);
        sim.run(120.0);
        let seen = sim.first(|o| o.track).unwrap();
        found.push(seen);
        let lock = sim.first(|o| !o.tracks.is_empty()).unwrap();
        assert_eq!(lock, seen + half(skill.reaction_s + 5.0 * skill.procedure), "{skill:?}");
        let l = sim.launches();
        let range = 3_000.0 + 37_000.0 * skill.launch_range;
        assert_eq!(l[0].0, first_tick(|t| t >= lock && slant(60.0, t).0 <= range), "{skill:?}");
        assert_eq!(l[1].0 - l[0].0, 3.0, "the same spacing: {skill:?}");
        sim.targets.clear();
        while !matches!(sim.site.mode, Mode::March(_)) {
            sim.run(0.5);
        }
        let Mode::March(until) = sim.site.mode else { unreachable!() };
        assert_eq!(until - (sim.now - 0.5), 300.0 * skill.procedure, "the march order: {skill:?}");
    }
    assert!(found.windows(2).all(|w| w[0] == w[1]), "the same detection: {found:?}");
}

/// The gun's laying error: each burst's error the same draw at every level, scaled by its aim, spread about it; the
/// bursts' rounds and spacing the same.
#[test]
fn skill_sets_the_gun_laying_error() {
    let bursts = |skill: Skill| {
        let mut site = Site::new(Kind::Zsu, Vec3::new(100.0, 200.0, 0.0), 0.0, &[]);
        site.skill = skill;
        let t = Target { dlz: (2_250.0, 0.0), ..jet("a", "f16", Vec3::new(0.0, 1500.0, 300.0), Vec3::ZERO) };
        let mut sim = Sim::new(site, vec![t]);
        sim.run(120.0);
        sim.log.iter().flat_map(|(t, o, _)| o.bursts.iter().map(|b| (*t, b.2, b.3))).collect::<Vec<_>>()
    };
    let levels = [bursts(Skill::LOW), bursts(Skill::MEDIUM), bursts(Skill::HIGH)];
    for (b, skill) in levels.iter().zip([Skill::LOW, Skill::MEDIUM, Skill::HIGH]) {
        assert!(b.len() >= 30 && b.iter().all(|x| x.1 == 10), "bursts of 10: {skill:?}");
        assert!(b.windows(2).all(|w| w[1].0 - w[0].0 == 3.0), "3 s apart: {skill:?}");
        let rms = (b.iter().map(|x| x.2[0] * x.2[0] + x.2[1] * x.2[1]).sum::<f64>() / (2 * b.len()) as f64).sqrt();
        assert!((rms * 1000.0 / skill.aim_mrad - 1.0).abs() < 0.3, "spread {rms} about {} mrad", skill.aim_mrad);
    }
    let [low, medium, high] = &levels;
    for ((l, m), h) in low.iter().zip(medium).zip(high).take(30) {
        assert!(h.2 != [0.0, 0.0]);
        for (e, aim) in [(l.2, Skill::LOW.aim_mrad), (m.2, Skill::MEDIUM.aim_mrad)] {
            let r = aim / Skill::HIGH.aim_mrad;
            assert!((e[0] - h.2[0] * r).abs() < 1e-12 && (e[1] - h.2[1] * r).abs() < 1e-12, "{e:?} {h:?}");
        }
    }
}

// --- shoulder-fired teams (docs/ai.md §15.8) ---------------------------------------------------------------------

/// A jet `y` m north of the team at `agl` m, flying `vy` m/s north (negative: toward it), `x` m east.
fn low(id: &str, x: f64, y: f64, agl: f64, vy: f64) -> Target {
    // The caller's envelope from rest (`Missile.dlz`) is wider than the published one, which takes over.
    Target { dlz: (8_000.0, 300.0), ..jet(id, "f16", Vec3::new(x, y, agl), Vec3::new(0.0, vy, 0.0)) }
}

/// Each team's missile from rest at sea level: its published top speed and range (the straight flight before its
/// end, less the DLZ's last 2 s).
#[test]
fn manpads_missiles_fly_their_published_figures() {
    for (kind, top, km) in [(Kind::Strela, 500.0, 4.2), (Kind::Igla, 570.0, 5.2)] {
        let ir = kind.spec().ir.unwrap();
        let mut best = 0.0f64;
        let mut flown = Vec::new();
        ir.phys.fly_straight(0.0, 0.0, 0.0, |t, d, v| {
            best = best.max(v);
            flown.push((t, d));
            false
        });
        let end = flown.last().unwrap().0 - 2.0;
        let reach = flown.iter().filter(|f| f.0 <= end).map(|f| f.1).fold(0.0, f64::max);
        println!("{kind:?}: top {best:.0} m/s, reach {:.2} km, flight {:.1} s", reach / 1e3, end + 2.0);
        assert!((best / top - 1.0).abs() < 0.05, "{kind:?}: top {best:.0} m/s against {top}");
        assert!((reach / 1e3 / km - 1.0).abs() < 0.05, "{kind:?}: {:.2} km against {km}", reach / 1e3);
        assert!((ir.blast() - 5.7).abs() < 0.1, "{kind:?}: the blast scaled from the AIM-9A / B's 9 m for 4.5 kg");
    }
}

/// A team is passive: it holds a low jet by eye (no search, no track, no lock on the RWR), fires after the crew's
/// reaction and drill from the shoulder once the jet is inside its envelope and its seeker has it, one missile, then
/// its second once the first has ended (shoot-look-shoot).
#[test]
fn a_team_sees_a_low_jet_and_fires_by_eye() {
    // Head on 12 km out at 150 m, 250 m/s: the Igla's front lock (2.5 km) comes before its minimum range.
    let mut sim = Sim::new(Site::new(Kind::Igla, Vec3::ZERO, 0.0, &[]), vec![low("a", 300.0, 12_000.0, 150.0, -250.0)]);
    sim.fly = 6.0;
    let mut seen = None;
    while sim.now < 60.0 {
        sim.run(0.5);
        if seen.is_none() && !sim.site.channels.is_empty() {
            seen = Some(sim.now - 0.5);
        }
    }
    let seen = seen.expect("seen by eye");
    let y0 = |t: f64| 12_000.0 - 250.0 * t;
    assert_eq!(seen, first_tick(|t| Vec3::new(300.0, y0(t), 150.0).distance(Vec3::UP * 1.7) <= 10_000.0), "10 km");
    assert!(sim.log.iter().all(|(_, o, _)| !o.search && !o.track && o.tracks.is_empty()), "nothing radiates");
    let l = sim.launches();
    assert_eq!(l.len(), 2, "its two rounds: {l:?}");
    let drill = Skill::MEDIUM.reaction_s + 8.0;
    assert!(l[0].0 >= seen + drill, "after the drill: {l:?}");
    let d0 = Vec3::new(300.0, y0(l[0].0), 150.0).length();
    assert!(d0 <= 4_000.0 && y0(l[0].0) > 0.0, "head on inside the front lock (afterburner off: 2.5 km): {d0:.0}");
    assert!(l[1].0 >= l[0].0 + 6.0, "the second after the first has ended: {l:?}");
    assert_eq!(sim.site.rounds, [0]);
}

/// The Strela-2M's uncooled seeker sees only a jet's tail: no launch while it approaches, a launch once it recedes
/// inside the range.
#[test]
fn the_strela_fires_only_at_a_receding_jet() {
    let mut sim =
        Sim::new(Site::new(Kind::Strela, Vec3::ZERO, 0.0, &[]), vec![low("a", 500.0, 8_000.0, 200.0, -220.0)]);
    sim.fly = 1e9;
    sim.run(80.0);
    let l = sim.launches();
    assert_eq!(l.len(), 1, "{l:?}");
    let y = 8_000.0 - 220.0 * l[0].0;
    assert!(y < 0.0, "past the team, going away: y {y:.0}");
    assert!(Vec3::new(500.0, y, 200.0).length() <= 4_200.0);
}

/// The envelope's height band and the fastest target: no launch at a jet above the ceiling or too fast; the Igla
/// takes a jet the Strela cannot (its height, its front).
#[test]
fn a_team_keeps_to_its_envelope() {
    let fired = |kind: Kind, t: Target| {
        let mut sim = Sim::new(Site::new(kind, Vec3::ZERO, 0.0, &[]), vec![t]);
        sim.fly = 1e9;
        sim.run(80.0);
        !sim.launches().is_empty()
    };
    assert!(!fired(Kind::Igla, low("a", 0.0, 8_000.0, 3_800.0, -200.0)), "above the Igla's 3.5 km");
    assert!(fired(Kind::Igla, low("a", 0.0, 8_000.0, 3_000.0, -200.0)), "inside it");
    assert!(!fired(Kind::Strela, low("a", 0.0, 8_000.0, 3_000.0, -200.0)), "above the Strela's 2.3 km");
    assert!(!fired(Kind::Igla, low("a", 0.0, 8_000.0, 200.0, -400.0)), "faster than its 320 m/s head on");
    // At 30 m a hill 2 km out hides the jet from the team until it is over the hill (the eye needs a line of sight).
    let hill = |p: Vec3| Some(if (p.y - 2_000.0).abs() < 100.0 { 60.0 } else { 0.0 });
    let mut site = Site::new(Kind::Igla, Vec3::ZERO, 0.0, &[]);
    let t = low("a", 0.0, 8_000.0, 30.0, -200.0);
    let out = site.tick(0.0, &[true], &[t], &hill);
    assert!(out.launches.is_empty() && site.channels.is_empty(), "masked");
}

/// The crew's skill: the same sighting, the launch later for a slower crew (its reaction and drill).
#[test]
fn skill_sets_the_team_s_reaction() {
    let first = |skill: Skill| {
        let mut site = Site::new(Kind::Igla, Vec3::ZERO, 0.0, &[]);
        site.skill = skill;
        // Crossing behind, receding: inside the rear lock all the way.
        let mut sim = Sim::new(site, vec![low("a", 1_500.0, 500.0, 300.0, 200.0)]);
        sim.fly = 1e9;
        sim.run(40.0);
        sim.launches()[0].0
    };
    let (low_t, med, high) = (first(Skill::LOW), first(Skill::MEDIUM), first(Skill::HIGH));
    let drill = |s: Skill| s.reaction_s + 8.0 * s.procedure;
    assert!(low_t > med && med > high, "{low_t} {med} {high}");
    assert!(((low_t - high) - (drill(Skill::LOW) - drill(Skill::HIGH))).abs() <= 0.5, "{low_t} {high}");
}

/// A team takes no cue from a network: no radar to acquire with.
#[test]
fn a_team_is_no_network_member() {
    let site = Site::new(Kind::Igla, Vec3::ZERO, 0.0, &[]);
    let t = low("a", 0.0, 3_000.0, 200.0, -200.0);
    assert!(site.eta(0.0, &[true], &t, &flat).is_infinite());
}
