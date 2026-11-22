//! The SAM network (`iaf_ai::net`, docs/ai.md §15.5): the 64N6E2's sweep cues the sites with their search radars
//! off, one site per jet, the hand-over past a site's envelope, the sites' tracks in the picture, and the sites
//! autonomous once the radar or the post is lost.

use iaf_ai::Skill;
use iaf_ai::net::{Gci, Member, Net, SCAN};
use iaf_ai::site::{Emcon, FIGHTER, Kind, Out, Site, Target};
use iaf_flight::{Vec3, airframe};

fn flat(_: Vec3) -> Option<f64> {
    Some(0.0)
}

/// An F-16 at `pos` flying `vel`, inside an envelope of 40 km to 3 km from every site.
fn jet(id: &str, pos: Vec3, vel: Vec3) -> Target {
    Target {
        id: id.into(),
        pos,
        vel,
        nose: vel.try_normalize().unwrap_or(Vec3::NORTH),
        rcs: airframe::get("f16").and_then(|a| a.rcs).unwrap_or(FIGHTER),
        bays_open: false,
        stores: 0,
        cued: false,
        dlz: (40_000.0, 3_000.0),
        in_air: 0,
        jam: 0.0,
    }
}

/// S-300s at `at` under a network whose radar stands at `radar`, ticked every 0.5 s; each missile flies `fly` s.
struct Sim {
    net: Net,
    sites: Vec<Site>,
    alive: Vec<Vec<bool>>,
    radar: bool,
    post: bool,
    now: f64,
    targets: Vec<Target>,
    fly: f64,
    /// (site, target, until)
    flying: Vec<(usize, String, f64)>,
    log: Vec<(f64, Vec<Out>)>,
    /// Site i's own envelope to every jet, when it differs from the jets' own.
    dlz: Vec<Option<(f64, f64)>>,
}

impl Sim {
    fn new(radar: Vec3, at: &[Vec3], targets: Vec<Target>) -> Sim {
        Sim::of(radar, at.iter().map(|&p| Site::new(Kind::S300, p, 0.0, &[])).collect(), targets)
    }

    fn of(radar: Vec3, sites: Vec<Site>, targets: Vec<Target>) -> Sim {
        let alive = sites.iter().map(|s| vec![true; s.spec().parts.len()]).collect();
        let (net, now, fly, dlz) = (Net::new(radar), 0.0, 20.0, Vec::new());
        Sim { net, sites, alive, radar: true, post: true, now, targets, fly, flying: Vec::new(), log: Vec::new(), dlz }
    }

    fn run(&mut self, secs: f64) {
        let end = self.now + secs;
        while self.now < end - 1e-9 {
            let mut per: Vec<Vec<Target>> = (0..self.sites.len())
                .map(|i| {
                    let mut ts = self.targets.clone();
                    for t in &mut ts {
                        if let Some(d) = self.dlz.get(i).copied().flatten() {
                            t.dlz = d;
                        }
                        let mine = |f: &&(usize, String, f64)| f.0 == i && f.1 == t.id && f.2 > self.now;
                        t.in_air = self.flying.iter().filter(mine).count() as u32;
                    }
                    ts
                })
                .collect();
            let cues = {
                let mut members: Vec<Member> = self
                    .sites
                    .iter_mut()
                    .zip(&self.alive)
                    .zip(&per)
                    .map(|((site, alive), targets)| Member { site, alive, targets })
                    .collect();
                self.net.tick(self.now, self.radar, self.post, &mut members, &flat)
            };
            let mut outs = Vec::new();
            for (i, site) in self.sites.iter_mut().enumerate() {
                for t in &mut per[i] {
                    t.cued = cues[i].contains(&t.id);
                }
                let out = site.tick(self.now, &self.alive[i], &per[i], &flat);
                for (_, id) in &out.launches {
                    self.flying.push((i, id.clone(), self.now + self.fly));
                }
                outs.push(out);
            }
            self.log.push((self.now, outs));
            for t in &mut self.targets {
                t.pos += t.vel * 0.5;
            }
            self.now += 0.5;
        }
    }

    /// Site `i`'s launches: (time, target).
    fn launches(&self, i: usize) -> Vec<(f64, String)> {
        self.log.iter().flat_map(|(t, o)| o[i].launches.iter().map(|l| (*t, l.1.clone()))).collect()
    }

    /// The ticks at which site `i`'s output holds `f`.
    fn when(&self, i: usize, f: impl Fn(&Out) -> bool) -> Vec<f64> {
        self.log.iter().filter(|(_, o)| f(&o[i])).map(|(t, _)| *t).collect()
    }
}

/// 8 km up, `km` north of the origin, flying south at 250 m/s.
fn southbound(id: &str, km: f64) -> Target {
    jet(id, Vec3::new(0.0, km * 1000.0, 8000.0), Vec3::new(0.0, -250.0, 0.0))
}

#[test]
fn the_sweep_cues_the_track_radar_with_the_search_off() {
    let mut sim = Sim::new(Vec3::new(0.0, -20_000.0, 0.0), &[Vec3::ZERO], vec![southbound("a", 100.0)]);
    sim.run(300.0);
    assert!(sim.sites[0].net, "the site runs under the network");
    assert!(sim.log.iter().all(|(_, o)| !o[0].search), "the site's own search radar stays off");
    assert!(sim.net.picture.contains_key("a"), "the 64N6E2 sees the jet");
    let on = sim.when(0, |o| o.track)[0];
    // On for the last seconds: the medium crew's launch range (docs/ai.md §17) plus its reaction and 5 s acquisition at
    // the closing speed.
    let m = Skill::MEDIUM;
    let range = 3_000.0 + 37_000.0 * m.launch_range;
    let lead = 250.0 * (m.reaction_s + 5.0 * m.procedure);
    let slant = |t: f64| (100_000.0 - 250.0 * t).hypot(8000.0);
    assert!(slant(on) <= range + lead + 50.0 && slant(on) > range, "the track radar comes on at {} m", slant(on));
    let l = sim.launches(0);
    assert!(l.len() >= 2 && slant(l[0].0) <= range, "it fires inside the crew's range: {l:?}");
}

#[test]
fn the_sweep_waits_for_the_radar() {
    // No sweep has seen the jet before the first one: the picture fills on the radar's 12 s.
    let mut sim = Sim::new(Vec3::ZERO, &[Vec3::ZERO], vec![]);
    sim.run(1.0);
    sim.targets.push(southbound("a", 100.0));
    sim.run(SCAN - 1.5);
    assert!(sim.net.picture.is_empty(), "not before the next sweep");
    sim.run(1.0);
    assert!(sim.net.picture.contains_key("a"), "seen on the sweep");
}

#[test]
fn one_site_per_jet() {
    let at = [Vec3::new(-5000.0, 0.0, 0.0), Vec3::new(5000.0, 0.0, 0.0)];
    let mut sim = Sim::new(Vec3::new(0.0, -20_000.0, 0.0), &at, vec![southbound("a", 80.0)]);
    sim.run(250.0);
    let (a, b) = (sim.launches(0), sim.launches(1));
    assert!(a.len() + b.len() >= 4, "it is engaged: {a:?} {b:?}");
    assert!(a.is_empty() || b.is_empty(), "one site fires at it, not both: {a:?} {b:?}");
    let both = |o: &Vec<Out>| o.iter().all(|o| o.track);
    assert!(!sim.log.iter().any(|(_, o)| both(o)), "never both track radars on it");
}

#[test]
fn the_target_is_handed_over_past_the_envelope() {
    // Site 0 at the origin, site 1 100 km south: the jet passes over site 0 and flies on toward site 1.
    let at = [Vec3::ZERO, Vec3::new(0.0, -100_000.0, 0.0)];
    let mut sim = Sim::new(Vec3::new(30_000.0, -50_000.0, 0.0), &at, vec![southbound("a", 60.0)]);
    sim.fly = 60.0; // site 0 keeps rounds to the end of its envelope
    sim.run(500.0);
    let (a, b) = (sim.launches(0), sim.launches(1));
    assert!(!a.is_empty() && !b.is_empty(), "both fire in turn: {a:?} {b:?}");
    assert!(a.last().unwrap().0 < b[0].0, "site 0 first, then site 1");
    let last_a = *sim.when(0, |o| o.track).last().unwrap();
    let first_b = sim.when(1, |o| o.track)[0];
    assert!(last_a < first_b, "site 0's track ends ({last_a} s) before site 1's begins ({first_b} s)");
    // Site 0 lets it go once it is out of its envelope and opening.
    let y = 60_000.0 - 250.0 * last_a;
    assert!(y < 0.0 && y.hypot(8000.0) > 40_000.0 - 250.0, "handed over past the edge (y {y} m)");
    let y = 60_000.0 - 250.0 * b[0].0;
    assert!((y + 100_000.0).hypot(8000.0) <= 40_000.0, "site 1 fires inside its own envelope");
}

#[test]
fn the_sites_tracks_feed_the_picture() {
    // The jet is seen high, engaged, then drops below the 64N6E2's horizon: site 0's track keeps it in the picture
    // and the cue holds. Jet b flies low from the start: nothing of the network sees it.
    let a = jet("a", Vec3::new(0.0, 30_000.0, 8000.0), Vec3::ZERO);
    let b = jet("b", Vec3::new(30_000.0, 0.0, 300.0), Vec3::ZERO);
    let mut sim = Sim::new(Vec3::new(0.0, -200_000.0, 0.0), &[Vec3::ZERO], vec![a, b]);
    sim.fly = 1e9;
    sim.run(30.0);
    assert_eq!(sim.launches(0).len(), 2, "a salvo at a");
    sim.targets[0].pos.z = 300.0;
    sim.run(60.0);
    assert!(sim.net.picture.contains_key("a"), "the site's track keeps a in the picture");
    assert!(sim.log.last().unwrap().1[0].tracks == ["a"], "and the site on it");
    assert!(!sim.net.picture.contains_key("b"), "b is seen by no radar of the network");
}

#[test]
fn a_restored_network_keeps_the_site_on_its_jet() {
    // Alone, site 1 fights the jet and site 0 keeps silent; the network restored, site 1 keeps it: no second site
    // fires at it, not even while site 1's salvo flies.
    let at = [Vec3::new(-5000.0, 0.0, 0.0), Vec3::new(5000.0, 0.0, 0.0)];
    let mut sim = Sim::new(Vec3::new(0.0, -20_000.0, 0.0), &at, vec![southbound("a", 60.0)]);
    sim.sites[0].emcon = Emcon::Silent;
    sim.radar = false;
    sim.run(115.0); // the medium crew fires at 36.3 km (docs/ai.md §17)
    assert!(sim.launches(0).is_empty() && !sim.launches(1).is_empty(), "alone, site 1 fires");
    let b = sim.launches(1).len();
    sim.radar = true;
    sim.run(100.0);
    assert!(sim.launches(0).is_empty(), "site 0 holds fire: {:?}", sim.launches(0));
    assert!(sim.launches(1).len() > b, "site 1 goes on");
}

#[test]
fn a_gun_laying_on_a_jet_out_of_its_reach_leaves_it_to_the_s300() {
    // The jet crosses 4.8 km from the ZSU: inside its sight, outside its gun; the S-300 beside it is cued and fires.
    let sites =
        vec![Site::new(Kind::Zsu, Vec3::ZERO, 0.0, &[]), Site::new(Kind::S300, Vec3::new(0.0, -1000.0, 0.0), 0.0, &[])];
    let a = jet("a", Vec3::new(-1250.0, 4800.0, 500.0), Vec3::new(100.0, 0.0, 0.0));
    let mut sim = Sim::of(Vec3::new(0.0, -20_000.0, 0.0), sites, vec![a]);
    sim.dlz = vec![Some((4500.0, 200.0)), None];
    sim.run(25.0);
    assert!(sim.launches(0).is_empty(), "out of the gun's reach");
    assert!(!sim.launches(1).is_empty(), "the S-300 fires");
}

#[test]
fn a_full_site_takes_no_new_jet() {
    // Tor 0 guides salvos at x and y (both its channels); the more dangerous z goes to Tor 1. Every jet comes in fast
    // enough along the line of sight for the Tor's Doppler notch (30 m/s, docs/ai.md §15.3).
    let tor = |x: f64| Site::new(Kind::Tor, Vec3::new(x, 0.0, 0.0), 0.0, &[]);
    let near = |id: &str, x: f64, vy: f64| Target {
        dlz: (12_000.0, 1_500.0),
        ..jet(id, Vec3::new(x, 8000.0, 1000.0), Vec3::new(0.0, vy, 0.0))
    };
    let mut sim = Sim::of(
        Vec3::new(0.0, -10_000.0, 0.0),
        vec![tor(0.0), tor(1000.0)],
        vec![near("x", -500.0, -35.0), near("y", 500.0, -35.0)],
    );
    sim.fly = 1e9;
    sim.run(30.0);
    let ids = |l: Vec<(f64, String)>| l.into_iter().map(|x| x.1).collect::<Vec<_>>();
    assert_eq!(ids(sim.launches(0)), ["x", "x", "y", "y"], "Tor 0 takes both");
    sim.targets.push(near("z", 0.0, -100.0));
    sim.run(30.0);
    assert!(!ids(sim.launches(0)).contains(&"z".to_string()), "not to the full Tor 0");
    assert!(ids(sim.launches(1)).contains(&"z".to_string()), "Tor 1 fires at z");
}

#[test]
fn losing_the_radar_or_the_post_leaves_the_sites_autonomous() {
    for radar in [false, true] {
        let mut sim = Sim::new(Vec3::new(0.0, -20_000.0, 0.0), &[Vec3::ZERO], vec![southbound("a", 120.0)]);
        sim.run(10.0);
        assert!(!sim.log.last().unwrap().1[0].search, "networked: no search");
        sim.radar = radar;
        sim.post = !radar;
        sim.run(10.0);
        assert!(!sim.sites[0].net, "autonomous");
        assert!(sim.log.last().unwrap().1[0].search, "its own EMCON again: the 96L6E searches");
        assert!(sim.net.picture.is_empty());
        let l = sim.launches(0);
        sim.run(400.0);
        assert!(sim.launches(0).len() > l.len(), "and it fights alone");
        sim.radar = true;
        sim.post = true;
        sim.run(1.0);
        assert!(sim.sites[0].net, "restored");
    }
}

#[test]
fn gci_vectors_the_nearest_sweep_track() {
    // docs/ai.md §18: the 64N6E2's sweeps make the vector, a track reckoned between them; the nearest to the station
    // within the reach; lost with the radar or the post; a jet out of the sweeps drops after two of them.
    let radar = Vec3::ZERO;
    let station = Vec3::new(0.0, 50_000.0, 6000.0);
    let mut gci = Gci::new(radar);
    let a = jet("a", Vec3::new(0.0, 150_000.0, 6000.0), Vec3::new(0.0, -250.0, 0.0));
    let b = jet("b", Vec3::new(30_000.0, 180_000.0, 6000.0), Vec3::new(0.0, -250.0, 0.0));
    let far = jet("far", Vec3::new(0.0, 400_000.0, 6000.0), Vec3::new(0.0, -250.0, 0.0));
    let all = [a.clone(), b.clone(), far.clone()];
    gci.tick(0.0, true, &all, &flat);
    assert_eq!(gci.tracks.len(), 2, "the jet past the radar's reach is not seen");
    // Reckoned 6 s later (no sweep yet): 1.5 km nearer.
    gci.tick(6.0, true, &all, &flat);
    let v = gci.vector(6.0, station, 120_000.0).expect("a vector");
    assert_eq!(v.id, "a");
    assert!((v.pos.y - 148_500.0).abs() < 1e-6, "{:?}", v.pos);
    assert!(gci.vector(6.0, station, 90_000.0).is_none(), "both outside the reach");
    // A jet the sweeps no longer see (gone from the jets) drops; the next sweep is at 12 s.
    gci.tick(SCAN, true, std::slice::from_ref(&b), &flat);
    assert_eq!(gci.tracks.iter().map(|k| k.id.as_str()).collect::<Vec<_>>(), ["b"]);
    // Lost: no picture; restored, it sweeps at once.
    gci.tick(13.0, false, std::slice::from_ref(&b), &flat);
    assert!(gci.tracks.is_empty());
    gci.tick(13.5, true, &[b], &flat);
    assert_eq!(gci.tracks.len(), 1);
}
