//! `IafAi`: Modern IAF's flight AI (`iaf_ai`, modern-iaf/docs/ai-plan.md §6) for one flight of up to four `IafFlight`
//! jets. Each frame, after every jet's `step` (one instant), `step` reads every jet's flight model and autopilot and
//! sets the AI jets' autopilot for their next `ap_step` (mode, leader, slot, engine start); the player's jet is read
//! only but for its home hangar (`add_member`). `IafSite`: an air-defence site (`iaf_ai::site`, docs/ai.md §15)
//! for `shared/ai/air_defence.gd`, `IafNet` their network (`iaf_ai::net`, §15.5). `IafSalvo`: one-way attack drones
//! (`iaf_ai::drone`, §16) for `shared/ai/drones.gd`.

use godot::prelude::*;
use iaf_ai::drone::{SHAHED_136, Salvo};
use iaf_ai::net::{self, Member, Net};
use iaf_ai::site::{self, Emcon, Kind, Site, Target};
use iaf_ai::{Decoy, Flight, Threat};
use iaf_flight::Vec3;

use crate::flight::{IafFlight, to_enu};
use crate::world::{get, num, rcs, terrain, vec3, vector3};

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafAi {
    flight: Flight,
    /// Each jet's number, flight and the host's word that it is alive.
    jets: Vec<(u8, Gd<IafFlight>, bool)>,
}

#[godot_api]
impl IafAi {
    /// Adds jet `number` (1..4; #3 leads the second element) flown by `flight`, after its `ap_setup` and route; `ai`
    /// false: the player's jet. The first one names the home base (the base nearest its route's last waypoint); a jet
    /// on the ground at a shelter parks there again after landing (the player's autopilot too). False, and not added:
    /// a number already in the flight, or a jet not started or without `ap_setup`.
    #[func]
    fn add_member(&mut self, mut flight: Gd<IafFlight>, number: i64, ai: bool) -> bool {
        let n = number.clamp(1, 4) as u8;
        if self.jets.iter().any(|j| j.0 == n) {
            return false;
        }
        if let Some((fm, ap)) = flight.bind_mut().parts() {
            self.flight.add(n, ai, fm, ap);
        } else {
            return false;
        }
        self.jets.push((n, flight, true));
        true
    }

    /// Jet `number` lost (shot down, crashed, ejected) or back: the lead's loss promotes the next (1 → 3 → 2 → 4).
    #[func]
    fn set_alive(&mut self, number: i64, alive: bool) {
        for j in self.jets.iter_mut().filter(|j| j.0 as i64 == number) {
            j.2 = alive;
        }
    }

    /// The tower's start-up clearance at `now` (s): the wingmen start their engines, 3 s apart, and taxi behind the
    /// jet ahead.
    #[func]
    fn start_up(&mut self, now: f64) {
        self.flight.start_up(now);
    }

    /// A radio command at `now` to `to` (0 the flight, 5 the element #3–#4, 2..4 one wingman): check, ops_check,
    /// a shape of `iaf_ai::SHAPES` (fingertip, line_abreast, trail, echelon_right, echelon_left, diamond, vic, delta),
    /// rejoin, rtb. False: unknown, or nobody to take it. The answers come from `step` as calls.
    #[func]
    fn command(&mut self, now: f64, to: i64, cmd: GString) -> bool {
        self.flight.command(now, to.clamp(0, 5) as u8, &cmd.to_string())
    }

    /// The lead's split at `now`: element 2 (#3, #4 on it) takes its own task at the scene position `at` (its target,
    /// within 40 km of the flight lead), circles it at its height until a "regroup". False: no AI #3 in the air to
    /// take it; the answers (ack, unable: too far) come as calls.
    #[func]
    fn split(&mut self, now: f64, at: Vector3) -> bool {
        self.flight.split(now, to_enu(at))
    }

    /// The lead's "engage my target" at `now` to `to` (0 the flight, 5 the element #3–#4, 2..4 one wingman) on the
    /// target at the scene position `at`; `has` false: no target to engage (each answers "unable"). 1: a jet took it;
    /// 0: each answered "unable" (a jet already engaging keeps its target); -1: nobody to take it. The engaging jets
    /// fly at it; the host fires their weapons.
    #[func]
    fn engage(&mut self, now: f64, to: i64, has: bool, at: Vector3) -> i64 {
        self.flight.engage(now, to.clamp(0, 5) as u8, has.then(|| to_enu(at))).map_or(-1, i64::from)
    }

    /// The engaged target this frame at the scene position `at`; `alive` false: gone, the engaging jets rejoin.
    #[func]
    fn set_target(&mut self, alive: bool, at: Vector3) {
        self.flight.target(alive.then(|| to_enu(at)));
    }

    /// The threat jet `number`'s RWR and MAW show this frame, at the scene position `at`: `kind` 0 none, 1 a radar
    /// locked on it from the air, 2 from the ground, 3 a radar missile flying at it, 4 an infrared one.
    #[func]
    fn set_threat(&mut self, number: i64, kind: i64, at: Vector3) {
        let t = (1..=4).contains(&kind).then(|| Threat {
            pos: to_enu(at),
            launch: kind >= 3,
            ir: kind == 4,
            ground: kind == 2,
        });
        self.flight.threat(number.clamp(0, 255) as u8, t);
    }

    /// An AWACS contact call at `now` (IafFlightController.scan's {bearing, miles, code}): an AI jet holding it in its
    /// radar reports "contact". Returns its number, 0 for none.
    #[func]
    fn awacs(&mut self, now: f64, bearing: f64, miles: f64, enemy: bool) -> i64 {
        self.flight.awacs(now, bearing, miles, enemy) as i64
    }

    /// The decoy jet `number` releases this frame (after `step`): 0 none, 1 chaff, 2 flares (combat.gd's release, one
    /// each 4 s at most, and the decoy rule).
    #[func]
    fn decoy(&self, number: i64) -> i64 {
        match self.flight.member(number.clamp(0, 255) as u8).and_then(|m| m.order.decoy) {
            Some(Decoy::Chaff) => 1,
            Some(Decoy::Flare) => 2,
            None => 0,
        }
    }

    /// One frame at `now` (s), after every jet's steps of the frame (one instant, `Flight::sense`): the AI's decisions
    /// and its jets' orders for their next `ap_step`. Returns the calls due, each
    /// {from: number, id: ack, unable, joker, bingo, rtb, fuel_state, lead_change, in_position, spike, mud, defending,
    /// break_left, break_right, contact}.
    #[func]
    fn step(&mut self, now: f64) -> VarArray {
        for (n, jet, alive) in &mut self.jets {
            if let Some((fm, ap)) = jet.bind_mut().parts() {
                self.flight.sense(*n, *alive, fm, ap);
            }
        }
        let calls = self.flight.step(now);
        for (n, jet, _) in &mut self.jets {
            let Some(m) = self.flight.member(*n).filter(|m| m.ai) else { continue };
            let order = m.order;
            if let Some((fm, ap)) = jet.bind_mut().parts() {
                iaf_ai::apply(&order, ap, fm);
            }
        }
        let mut out = VarArray::new();
        for c in calls {
            let mut d = VarDictionary::new();
            d.set("from", c.from as i64);
            d.set("id", c.id);
            out.push(&d.to_variant());
        }
        out
    }

    /// Jet `number` for tests and logs: role (lead / wingman), leader (the number it flies on, 0 none), stage (its
    /// control loop), slot_error (m), avoiding (it pulls away from another jet), task (element 2's lead on its split
    /// task), defending, engaging (it engages the player's target), fuel_kg, bingo_kg, released (sent home); empty for
    /// an unknown number.
    #[func]
    fn state(&self, number: i64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(m) = self.flight.member(number.clamp(0, 255) as u8) else { return d };
        d.set("role", if m.number == self.flight.lead() { "lead" } else { "wingman" });
        if let Some((_, jet, _)) = self.jets.iter().find(|j| j.0 == m.number) {
            d.set("stage", &jet.bind().ap_stage());
        }
        d.set("leader", self.flight.leader(m.number) as i64);
        d.set("slot_error", m.slot_error);
        d.set("avoiding", m.order.avoid.is_some());
        d.set("task", m.task.is_some());
        d.set("defending", m.defending);
        d.set("engaging", m.engaging);
        d.set("fuel_kg", m.fuel_kg);
        d.set("bingo_kg", m.bingo_kg);
        d.set("released", m.released);
        d
    }
}

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafSite {
    site: Site,
}

/// A target dictionary: {id, pos, vel, nose (world), rcs (an airframe's `rcs`, else a fighter's), bays, stores,
/// cued, dlz (Vector2: max, min m), in_air}.
fn target(d: &VarDictionary) -> Target {
    let dlz: Vector2 = get(d, "dlz").unwrap_or_default();
    Target {
        id: get::<GString>(d, "id").unwrap_or_default().to_string(),
        pos: vec3(get(d, "pos").unwrap_or_default()),
        vel: vec3(get(d, "vel").unwrap_or_default()),
        nose: vec3(get(d, "nose").unwrap_or_default()),
        rcs: rcs(d, "rcs").unwrap_or(site::FIGHTER),
        bays_open: get(d, "bays").unwrap_or(false),
        stores: num(d, "stores").unwrap_or(0.0) as u32,
        cued: get(d, "cued").unwrap_or(false),
        dlz: (dlz.x.into(), dlz.y.into()),
        in_air: num(d, "in_air").unwrap_or(0.0) as u32,
    }
}

#[godot_api]
impl IafSite {
    /// A site of `kind` (s300, tor, zsu) centred at `pos` (world), facing `heading` (degrees), with its alternate
    /// positions (Vector3s); null for an unknown kind.
    #[func]
    fn create(kind: GString, pos: Vector3, heading: f64, alternates: VarArray) -> Option<Gd<Self>> {
        let kind = Kind::from_name(&kind.to_string())?;
        let alt: Vec<Vec3> = alternates.iter_shared().filter_map(|v| v.try_to::<Vector3>().ok()).map(vec3).collect();
        Some(Gd::from_object(Self { site: Site::new(kind, vec3(pos), heading, &alt) }))
    }

    /// Its parts in order: [{name, type_code, klass, search, track, rounds, reach_km (a radar's reach, else 0)}].
    #[func]
    fn parts(&self) -> VarArray {
        let spec = self.site.spec();
        spec.parts
            .iter()
            .map(|p| {
                let reach = if p.search {
                    spec.search_reach
                } else if p.track {
                    spec.track_reach
                } else {
                    0.0
                };
                vdict! {
                    "name" => p.name, "type_code" => spec.type_code, "klass" => spec.class, "search" => p.search,
                    "track" => p.track, "rounds" => i64::from(p.rounds), "reach_km" => reach / 1000.0,
                }
                .to_variant()
            })
            .collect()
    }

    /// Each part's ground position (world) on the terrain `ground` (Callable(Vector3) -> float or null).
    #[func]
    fn positions(&self, ground: Callable) -> VarArray {
        let ground = terrain(Some(ground));
        (0..self.site.spec().parts.len()).map(|i| vector3(self.site.part_pos(i, &ground)).to_variant()).collect()
    }

    /// Emission control: radiate, silent or cue; false for an unknown one.
    #[func]
    fn set_emcon(&mut self, mode: GString) -> bool {
        let e = match mode.to_string().as_str() {
            "radiate" => Emcon::Radiate,
            "silent" => Emcon::Silent,
            "cue" => Emcon::Cue,
            _ => return false,
        };
        self.site.emcon = e;
        true
    }

    /// The 30N6E2 on its 40V6M tower.
    #[func]
    fn set_mast(&mut self, on: bool) {
        self.site.mast = on;
    }

    /// One decision at `now` (s): `alive` per part, the hostile jets alive (target dictionaries), the terrain
    /// (Callable(Vector3) -> float or null). {search, track, tracks, launches: [[part, id]], bursts: [[part, id,
    /// rounds]], parts: [each part's ground position], heading (the vehicles', their course on the move), phase}.
    #[func]
    fn tick(&mut self, now: f64, alive: VarArray, targets: VarArray, ground: Callable) -> VarDictionary {
        let alive: Vec<bool> = alive.iter_shared().map(|v| v.try_to::<bool>().unwrap_or(true)).collect();
        let targets: Vec<Target> =
            targets.iter_shared().filter_map(|v| v.try_to::<VarDictionary>().ok()).map(|d| target(&d)).collect();
        let ground = terrain(Some(ground));
        let out = self.site.tick(now, &alive, &targets, &ground);
        let tracks: PackedStringArray = out.tracks.iter().map(|s| GString::from(s.as_str())).collect();
        let launches: VarArray =
            out.launches.iter().map(|(p, id)| varray![*p as i64, id.as_str()].to_variant()).collect();
        let bursts: VarArray =
            out.bursts.iter().map(|(p, id, n)| varray![*p as i64, id.as_str(), i64::from(*n)].to_variant()).collect();
        let parts: VarArray =
            (0..self.site.spec().parts.len()).map(|i| vector3(self.site.part_pos(i, &ground)).to_variant()).collect();
        vdict! {
            "search" => out.search, "track" => out.track, "tracks" => &tracks, "launches" => &launches,
            "bursts" => &bursts, "parts" => &parts, "heading" => self.site.course, "phase" => self.site.phase(now),
        }
    }

    /// A launch the caller could not make: its round back to `part`.
    #[func]
    fn refund(&mut self, part: i64, target: GString) {
        self.site.refund(part.max(0) as usize, &target.to_string());
    }

    /// For tests and logs: {phase, rounds (per part), engagements, at (the position index)}.
    #[func]
    fn state(&self, now: f64) -> VarDictionary {
        let rounds: PackedInt64Array = self.site.rounds.iter().map(|&r| i64::from(r)).collect();
        vdict! {
            "phase" => self.site.phase(now), "rounds" => &rounds, "engagements" => i64::from(self.site.engagements),
            "at" => self.site.at as i64,
        }
    }
}

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafNet {
    net: Net,
}

#[godot_api]
impl IafNet {
    /// An 83M6E2 network whose 64N6E2 search radar stands at `radar` (world).
    #[func]
    fn create(radar: Vector3) -> Gd<Self> {
        Gd::from_object(Self { net: Net::new(vec3(radar)) })
    }

    /// Its parts, as `IafSite.parts`: the 64N6E2 search radar (the S-300's RWR symbol) and the 54K6E2 command post.
    #[func]
    fn parts() -> VarArray {
        let s = Kind::S300.spec();
        let radar = vdict! {
            "name" => "64N6E2 RADAR", "type_code" => s.type_code, "klass" => s.class, "search" => true,
            "track" => false, "rounds" => 0, "reach_km" => net::REACH / 1000.0,
        };
        let post = vdict! {
            "name" => "54K6E2", "type_code" => s.type_code, "klass" => s.class, "search" => false, "track" => false,
            "rounds" => 0, "reach_km" => 0.0,
        };
        varray![&radar, &post]
    }

    /// One decision at `now` (s), before the sites' ticks: the radar and the post alive, the members ([site
    /// (IafSite), its parts alive (bools), its targets (target dictionaries as `IafSite.tick`, each with that site's
    /// envelope)]), the terrain (Callable(Vector3) -> float or null). Each member's cues (target ids); all empty, the
    /// sites autonomous, while the radar or the post is lost. A member that is no site, or a site listed again, gets
    /// none.
    #[func]
    fn tick(&mut self, now: f64, radar_alive: bool, post_alive: bool, members: VarArray, ground: Callable) -> VarArray {
        let n = members.len();
        let mut gds: Vec<Gd<IafSite>> = Vec::new();
        let mut at = Vec::new();
        let mut alive: Vec<Vec<bool>> = Vec::new();
        let mut targets: Vec<Vec<Target>> = Vec::new();
        for (k, v) in members.iter_shared().enumerate() {
            let m = v.try_to::<VarArray>().unwrap_or_default();
            let Some(site) = m.get(0).and_then(|v| v.try_to::<Gd<IafSite>>().ok()) else { continue };
            if gds.iter().any(|g| g.instance_id() == site.instance_id()) {
                continue;
            }
            let list = |i: usize| m.get(i).and_then(|v| v.try_to::<VarArray>().ok()).unwrap_or_default();
            gds.push(site);
            at.push(k);
            alive.push(list(1).iter_shared().map(|v| v.try_to::<bool>().unwrap_or(true)).collect());
            targets.push(
                list(2).iter_shared().filter_map(|v| v.try_to::<VarDictionary>().ok()).map(|d| target(&d)).collect(),
            );
        }
        let ground = terrain(Some(ground));
        let mut guards: Vec<_> = gds.iter_mut().map(|g| g.bind_mut()).collect();
        let mut members: Vec<Member> = guards
            .iter_mut()
            .zip(&alive)
            .zip(&targets)
            .map(|((g, alive), targets)| Member { site: &mut g.site, alive, targets })
            .collect();
        let cues = self.net.tick(now, radar_alive, post_alive, &mut members, &ground);
        let mut out = vec![PackedStringArray::new(); n];
        for (k, c) in at.into_iter().zip(cues) {
            out[k] = c.iter().map(|s| GString::from(s.as_str())).collect();
        }
        out.iter().map(|c| c.to_variant()).collect()
    }
}

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafSalvo {
    salvo: Salvo,
}

#[godot_api]
impl IafSalvo {
    /// `count` drones of the Shahed-136 class along `route` (world Vector3s; the last is the end point on the ground),
    /// `agl` m above the terrain (0: the type's; clamped to its band), launched `interval` s apart (< 0: the type's);
    /// null for a route of fewer than two points.
    #[func]
    fn create(route: VarArray, count: i64, agl: f64, interval: f64) -> Option<Gd<Self>> {
        let route: Vec<Vec3> = route.iter_shared().filter_map(|v| v.try_to::<Vector3>().ok()).map(vec3).collect();
        let s = &SHAHED_136;
        let agl = if agl > 0.0 { agl } else { s.agl };
        let interval = if interval < 0.0 { s.interval } else { interval };
        let salvo = Salvo::new(s, &route, count.max(0) as usize, agl, interval)?;
        Some(Gd::from_object(Self { salvo }))
    }

    /// The type's radar cross-section, as an airframe's `rcs` (the player's radar reads it from the entity).
    #[func]
    fn rcs() -> VarDictionary {
        let r = SHAHED_136.rcs;
        vdict! {
            "front_m2" => r.front_m2, "side_m2" => r.side_m2, "rear_m2" => r.rear_m2, "bays_open_m2" => r.bays_open_m2,
            "store_m2" => r.store_m2,
        }
    }

    /// Advances `dt` s on the terrain `ground` (Callable(Vector3) -> float or null): each drone in launch order
    /// {phase (wait, cruise, dive, impact, down), pos, vel (world), heading, pitch (degrees)}.
    #[func]
    fn step(&mut self, dt: f64, ground: Callable) -> VarArray {
        let ground = terrain(Some(ground));
        self.salvo.step(dt.max(0.0), &ground);
        self.salvo
            .drones
            .iter()
            .map(|d| {
                vdict! {
                    "phase" => d.phase.name(), "pos" => vector3(d.pos), "vel" => vector3(d.vel),
                    "heading" => d.heading(), "pitch" => d.pitch(),
                }
                .to_variant()
            })
            .collect()
    }

    /// The game destroyed drone `i`: it flies no more.
    #[func]
    fn down(&mut self, i: i64) {
        self.salvo.down(i.max(0) as usize);
    }
}
