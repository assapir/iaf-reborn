//! `IafAi`: Modern IAF's flight AI (`iaf_ai`, modern-iaf/docs/ai-plan.md §6) for one flight of up to four `IafFlight`
//! jets. Each frame, after every jet's `step` (one instant), `step` reads every jet's flight model and autopilot and
//! sets the AI jets' autopilot for their next `ap_step` (mode, leader, slot, engine start); the player's jet is read
//! only but for its home hangar (`add_member`). `IafSite`: an air-defence site (`iaf_ai::site`, docs/ai.md §15)
//! for `shared/ai/air_defence.gd`, `IafNet` their network (`iaf_ai::net`, §15.5). `IafSalvo`: one-way attack drones
//! (`iaf_ai::drone`, §16) for `shared/ai/drones.gd`. An `IafAi` made an enemy pair (`enemy`) flies the enemy
//! fighter's trees (`iaf_ai::fighter`, §18); `IafGci` is a network's ground-controlled intercept (`iaf_ai::net::Gci`).
//! `IafConvoy`: a column of ground vehicles on the roads (`iaf_ai::convoy`, §19) for `shared/ai/convoys.gd`.
//! `IafTargetDrone`: a target drone's decisions (`iaf_ai::target`, §21) for `shared/ai/ai_flights.gd`.
//! `IafFreeCombat`: Scramble's roll, refusal, layout, air start and AWACS task call (`iaf_ai::free_combat`, §23).

use godot::prelude::*;
use iaf_ai::convoy::{self, Convoy, Route};
use iaf_ai::drone::{SHAHED_136, Salvo};
use iaf_ai::fighter;
use iaf_ai::free_combat;
use iaf_ai::net::{self, Gci, Member, Net};
use iaf_ai::site::{self, Emcon, Kind, Site, Target};
use iaf_ai::strike::{self, Pylon};
use iaf_ai::target::{Drone, Kind as DroneKind};
use iaf_ai::{Bandit, Bogey, Decoy, Flight, Skill, Tactic, Threat};
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

    /// The take-off in pairs (true: #2 lines up beside #1, #4 beside #3, each rolls with its lead) or in a stream
    /// behind the lead (false, the default; docs/ai.md §8.7).
    #[func]
    fn pairs(&mut self, on: bool) {
        self.flight.pairs(on);
    }

    /// A radio command at `now` to `to` (0 the flight, 5 the element #3–#4, 2..4 one wingman): check, ops_check,
    /// a shape of `iaf_ai::SHAPES` (fingertip, line_abreast, trail, echelon_right, echelon_left, diamond, vic, delta),
    /// close_up / spread_out (one step of `iaf_ai::CLOSE_STEPS`, to the flight), rejoin, rtb, cover (keep the slot,
    /// fight a bandit that attacks the lead). False: unknown, or nobody to take it.
    /// The answers come from `step` as calls.
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
    /// bandit `id` (of `set_bandits`; 0 none: each answers "unable"). 1: a jet took it; 0: each answered "unable" (a jet
    /// already engaging keeps its bandit); -1: nobody to take it. The engaging jets fight it (`state` "foe" its id); the
    /// host feeds their weapons and fires them (`shoot`, `gun`).
    #[func]
    fn engage(&mut self, now: f64, to: i64, id: i64) -> i64 {
        let id = (id > 0).then_some(id as u32);
        self.flight.engage(now, to.clamp(0, 5) as u8, id).map_or(-1, i64::from)
    }

    /// The lead's sort at `now` (to the flight, docs/ai.md §8.11): the picture's groups and jets shared out between the
    /// elements and their jets; the answers (targeted, ack, unable) come as calls. False: no AI wingman.
    #[func]
    fn sort(&mut self, now: f64) -> bool {
        self.flight.sort(now)
    }

    /// The lead's "attack my target" at `now` to `to` (0 the flight, 5 the element #3–#4, 2..4 one wingman) on the
    /// ground target at the scene position `at` moving at `vel` (docs/ai.md §8.10); `has` false: none (each answers
    /// "unable"). 1: a jet took it; 0: none could (no air-to-ground weapon, not flying); -1: nobody to take it. The
    /// attacking jets fly their runs one after the other (`state` "strike"); the host feeds `set_ground_target`,
    /// `set_ground_pylons` and `released`.
    #[func]
    fn attack(&mut self, now: f64, to: i64, has: bool, at: Vector3, vel: Vector3) -> i64 {
        let b = Bogey { pos: to_enu(at), vel: to_enu(vel) };
        self.flight.attack(now, to.clamp(0, 5) as u8, has.then_some(b)).map_or(-1, i64::from)
    }

    /// An AI-led flight's own attack at `now` (its lead first, then its wingmen) on the ground target at the scene
    /// position `at` moving at `vel`. False: the lead is the player's, or no jet could take it.
    #[func]
    fn strike(&mut self, now: f64, at: Vector3, vel: Vector3) -> bool {
        self.flight.strike(now, Bogey { pos: to_enu(at), vel: to_enu(vel) })
    }

    /// The flight's low level (docs/ai.md §20): its AI jets' steer loops fly `agl` m above the terrain ahead (150–500
    /// ft, clamped) and an attack's run comes in low and pops up; 0 or less: off.
    #[func]
    fn set_low(&mut self, agl: f64) {
        self.flight.low((agl > 0.0).then_some(agl as f32));
    }

    /// The flight flies low ([`Self::set_low`], the lead's "low" order).
    #[func]
    fn is_low(&self) -> bool {
        self.flight.low_m().is_some()
    }

    /// The attacked ground target this frame at the scene position `at` moving at `vel`; `alive` false: gone (the
    /// attacking jets end their attack and rejoin).
    #[func]
    fn set_ground_target(&mut self, alive: bool, at: Vector3, vel: Vector3) {
        self.flight.ground_target(alive.then(|| Bogey { pos: to_enu(at), vel: to_enu(vel) }));
    }

    /// Jet `number`'s pylons this frame (`pylons`: 4 values each, combat.gd's stations 0..8: the weapon's type, 1 when
    /// GPS-guided, the stores left, the weapon's id): its air-to-ground weapon left (`iaf_ai::strike::pylon`).
    #[func]
    fn set_ground_pylons(&mut self, number: i64, pylons: PackedInt64Array) {
        let guided = strike::pylon(&pylons_of(&pylons)).map(|p| p.1);
        self.flight.ground_weapon(number.clamp(0, 255) as u8, guided);
    }

    /// The release of an attack from the pylons `pylons` (as `set_ground_pylons`): (the pylon, the stores of one
    /// ripple, their spacing m); the pylon −1: none (`iaf_ai::strike::pylon`, `ripple`).
    #[func]
    fn ground_release(&self, pylons: PackedInt64Array) -> Vector3i {
        let ps = pylons_of(&pylons);
        strike::pylon(&ps).map_or(Vector3i::new(-1, 0, 0), |(i, _)| {
            Vector3i::new(i as i32, strike::ripple(&ps, i) as i32, strike::RIPPLE_M as i32)
        })
    }

    /// "Attack my target"'s ground target (`iaf_ai::strike::pick`) among the hostile ground units alive at the world
    /// positions `units`: `locked` (an index, −1 none: the radar's lock), else the one nearest the SPI `spi` (world)
    /// within 500 m; −1: the SPI itself.
    #[func]
    fn pick_ground(&self, locked: i64, spi: Vector3, units: PackedVector3Array) -> i64 {
        let us: Vec<Vec3> = units.as_slice().iter().map(|&u| vec3(u)).collect();
        let lock = usize::try_from(locked).ok();
        strike::pick(lock, vec3(spi), &us).map_or(-1, |i| i as i64)
    }

    /// Jet `number`'s release made at `now` (after `step`'s `release` order: combat.gd's AI ripple started): it calls
    /// "alpha" and egresses.
    #[func]
    fn released(&mut self, number: i64, now: f64) {
        self.flight.released(now, number.clamp(0, 255) as u8);
    }

    /// Jet `number` releases its air-to-ground weapon this frame (after `step`; the host's AI ripple, combat.gd).
    #[func]
    fn release(&self, number: i64) -> bool {
        self.flight.member(number.clamp(0, 255) as u8).is_some_and(|m| m.order.release)
    }

    /// The lead's "weapons free" at `now` to `to` (0 the flight, 5 the element #3–#4, 2..4 one wingman) in the area
    /// round the scene position `at` (within 40 km of the flight lead): the jets hunt the bandits there until a rejoin
    /// or joker fuel. 1: a jet took it; 0: none could; -1: nobody to take it. Not `free`: GDScript calls Object.free.
    #[func]
    fn weapons_free(&mut self, now: f64, to: i64, at: Vector3) -> i64 {
        self.flight.free(now, to.clamp(0, 5) as u8, to_enu(at)).map_or(-1, i64::from)
    }

    /// Jet `number` (the player's) shot at a bandit: an element lead's shot clears its wingman holding in a sort.
    #[func]
    fn fired(&mut self, number: i64) {
        self.flight.fired(number.clamp(0, 255) as u8);
    }

    /// The hostile jets this frame: each {id (the host's, > 0, never reused), pos, vel, nose (scene), jam (its jammer's
    /// burn-through share, 0 none), rcs (its definition's; none: an untreated fighter's), bays (open), stores (loaded
    /// external stations)}. A bandit an order named that is gone from the list is gone.
    #[func]
    fn set_bandits(&mut self, list: VarArray) {
        let bandits = list
            .iter_shared()
            .filter_map(|v| v.try_to::<VarDictionary>().ok())
            .map(|d| {
                let id = num(&d, "id").unwrap_or(0.0) as u32;
                let b = Bogey {
                    pos: to_enu(get(&d, "pos").unwrap_or_default()),
                    vel: to_enu(get(&d, "vel").unwrap_or_default()),
                };
                let mut b = Bandit::new(id, b, num(&d, "jam").unwrap_or(0.0));
                if let Some(n) = get::<Vector3>(&d, "nose").map(to_enu).and_then(|n| n.try_normalize()) {
                    b.nose = n;
                }
                b.rcs = rcs(&d, "rcs").unwrap_or(b.rcs);
                b.bays_open = get(&d, "bays").unwrap_or(false);
                b.stores = num(&d, "stores").unwrap_or(0.0).max(0.0) as u32;
                b
            })
            .collect();
        self.flight.bandits(bandits);
    }

    /// The bandit `id` shot down at `now`: the wingmen whose weapons were on it call "splash".
    #[func]
    fn splash(&mut self, now: f64, id: i64) {
        self.flight.splash(now, id.max(0) as u32);
    }

    /// The threat jet `number`'s RWR and MAW show this frame, at the scene position `at`: `kind` 0 none, 1 a radar
    /// locked on it from the air, 2 from the ground, 3 a radar missile flying at it, 4 an infrared one; `vel` the
    /// missile's scene velocity (zero for a lock).
    #[func]
    fn set_threat(&mut self, number: i64, kind: i64, at: Vector3, vel: Vector3) {
        let t = (1..=4).contains(&kind).then(|| Threat {
            pos: to_enu(at),
            vel: to_enu(vel),
            launch: kind >= 3,
            ir: kind == 4,
            ground: kind == 2,
        });
        self.flight.threat(number.clamp(0, 255) as u8, t);
    }

    /// Makes the flight an enemy pair on station at the scene position `station` (a CAP orbit's centre at its height,
    /// or where it was spawned in the air), every jet at the enemy's skill `level` (0 low, 1 medium, 2 high), after
    /// its `add_member`s.
    #[func]
    fn enemy(&mut self, level: i64, station: Vector3) {
        self.flight.enemy(Skill::enemy(level), to_enu(station));
    }

    /// An enemy pair's vector this frame: the ground's track (`has`; scene position and velocity) as the network
    /// reckons it and the id of the bandit it tracks (0 unknown). Its lead fights that bandit, else the one nearest the
    /// pair (`set_bandits`); its wingmen their share once committed (`state` "foe").
    #[func]
    fn set_gci(&mut self, has: bool, pos: Vector3, vel: Vector3, id: i64) {
        self.flight.gci(has.then(|| Bogey { pos: to_enu(pos), vel: to_enu(vel) }), id.max(0) as u32);
    }

    /// A jet `number`'s weapons this frame: its selected missile's envelope against its bogey (an enemy's; one of our
    /// wingmen's foe) (m), a missile or rounds left, its own missile flying at it.
    #[func]
    fn set_weapons(&mut self, number: i64, max: f64, min: f64, armed: bool, in_air: bool) {
        self.flight.weapons(number.clamp(0, 255) as u8, (max, min), armed, in_air);
    }

    /// An enemy jet `number` shoots at its bogey this frame (after `step`; the host's launch: combat.gd's).
    #[func]
    fn shoot(&self, number: i64) -> bool {
        self.flight.member(number.clamp(0, 255) as u8).is_some_and(|m| m.order.shoot)
    }

    /// An enemy jet `number` in the dogfight fires a gun burst at its bogey this frame (after `step`; the host's launch:
    /// combat.gd's).
    #[func]
    fn gun(&self, number: i64) -> bool {
        self.flight.member(number.clamp(0, 255) as u8).is_some_and(|m| m.order.gun)
    }

    /// An AWACS contact call at `now` (IafFlightController.scan's {bearing, miles, code}): an AI jet holding it in its
    /// radar reports "contact". Returns its number, 0 for none.
    #[func]
    fn awacs(&mut self, now: f64, bearing: f64, miles: f64, enemy: bool) -> i64 {
        self.flight.awacs(now, bearing, miles, enemy) as i64
    }

    /// Jet `number` has its jammer on this frame (after `step`; `Flight::jams`), when its definition has one.
    #[func]
    fn jams(&self, number: i64) -> bool {
        self.flight.jams(number.clamp(0, 255) as u8)
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
    /// break_left, break_right, contact, engaged, targeted, splash, winchester, in, alpha, done; the tower's to it:
    /// tower_land, tower_park}. `ground` (Callable(Vector3) -> float or null, at a world point) is the terrain the
    /// radars see over; `origin` the terrain's world origin (the flight's frame is the scene's: world = scene + origin).
    #[func]
    fn step(&mut self, now: f64, ground: Callable, origin: Vector2) -> VarArray {
        for (n, jet, alive) in &mut self.jets {
            if let Some((fm, ap)) = jet.bind_mut().parts() {
                self.flight.sense(*n, *alive, fm, ap);
            }
        }
        let (ground, o) = (terrain(Some(ground)), Vec3::new(f64::from(origin.x), f64::from(origin.y), 0.0));
        let calls = self.flight.step_on(now, &|p| ground(p + o));
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
    /// control loop), slot_error (m), close (the flight's close-up step, 0 standard), held (the step it holds now: looser
    /// while the lead manoeuvres past the parade's limits, iaf_ai `PARADE_LOOSE`), avoiding (it pulls away from
    /// another jet), task (element 2's lead on its split task), defending, tactic (the lead's order: "", cover, engage,
    /// sort, free), engaging, covering, holding (a sorted wingman holding its fire), foe (the bandit it fights, 0 none),
    /// fuel_kg, bingo_kg, released (sent home), hold (it waits on the ground: taxiing in behind a jet, a pair's lead for
    /// its wingman), strike (its attack's phase: "", wait, run, egress), profile (its run: level, dive, pop), low (the
    /// flight flies low, docs/ai.md §20); empty for an unknown number.
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
        d.set("close", self.flight.close_step() as i64);
        d.set("held", self.flight.held_step() as i64);
        d.set("avoiding", m.order.avoid.is_some());
        d.set("task", m.task.is_some());
        d.set("defending", m.defending);
        let tactic = match m.tactic {
            Tactic::None => "",
            Tactic::Cover => "cover",
            Tactic::Engage => "engage",
            Tactic::Sort => "sort",
            Tactic::Free => "free",
        };
        d.set("tactic", tactic);
        d.set("engaging", m.tactic == Tactic::Engage);
        d.set("covering", m.tactic == Tactic::Cover);
        d.set("holding", m.holding);
        d.set("foe", m.bandit.map_or(0, i64::from));
        d.set("fuel_kg", m.fuel_kg);
        d.set("bingo_kg", m.bingo_kg);
        d.set("released", m.released);
        d.set("hold", m.order.hold);
        d.set("phase", m.enemy.phase);
        d.set("committed", m.enemy.committed);
        d.set("contact", m.enemy.contact);
        d.set("strobe", m.enemy.strobe);
        d.set("visual", m.enemy.visual);
        d.set("strike", m.strike.phase.name());
        d.set("profile", m.strike.profile.name());
        d.set("low", m.order.low);
        d
    }
}

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafGci {
    gci: Gci,
}

#[godot_api]
impl IafGci {
    /// The ground-controlled intercept of a network whose 64N6E2 stands at `radar` (world).
    #[func]
    fn create(radar: Vector3) -> Gd<Self> {
        Gd::from_object(Self { gci: Gci::new(vec3(radar)) })
    }

    /// One tick at `now` (s): the radar and the post alive (`up`), the jets hostile to the network (target
    /// dictionaries as `IafSite.tick`'s; only id, pos, vel, nose, rcs, bays, stores are read), the terrain
    /// (Callable(Vector3) -> float or null).
    #[func]
    fn tick(&mut self, now: f64, up: bool, jets: VarArray, ground: Callable) {
        let jets: Vec<Target> =
            jets.iter_shared().filter_map(|v| v.try_to::<VarDictionary>().ok()).map(|d| target(&d)).collect();
        self.gci.tick(now, up, &jets, &terrain(Some(ground)));
    }

    /// The vector for fighters on station at `station` (world): {id, pos, vel} (world) of the track nearest it within
    /// the commit range (`iaf_ai::fighter::COMMIT_M`), reckoned to `now`; empty for none.
    #[func]
    fn vector(&self, now: f64, station: Vector3) -> VarDictionary {
        let Some(k) = self.gci.vector(now, vec3(station), fighter::COMMIT_M) else { return VarDictionary::new() };
        vdict! { "id" => k.id.as_str(), "pos" => vector3(k.pos), "vel" => vector3(k.vel) }
    }
}

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafSite {
    site: Site,
}

/// A target dictionary: {id, pos, vel, nose (world), rcs (an airframe's `rcs`, else a fighter's), bays, stores,
/// cued, dlz (Vector2: max, min m), in_air, jam (its jammer's burn-through share, 0 not jamming)}.
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
        jam: num(d, "jam").unwrap_or(0.0),
        ab: get(d, "ab").unwrap_or(false),
    }
}

#[godot_api]
impl IafSite {
    /// A site of `kind` (s300, tor, zsu, strela, igla) centred at `pos` (world), facing `heading` (degrees), with its
    /// alternate positions (Vector3s); null for an unknown kind.
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

    /// The site's own missile (docs/ai.md §15.1, §15.8), {} for a gun: {name, generation, ir (an infrared seeker, else
    /// radar-guided), kg, power, radius (the blast's, m), motion (the physical missile's keys, `missile.rs` Physics,
    /// and its seeker's `_decoyReject`)}.
    #[func]
    fn missile(&self) -> VarDictionary {
        let Some(m) = self.site.spec().missile else { return VarDictionary::new() };
        let p = m.phys;
        let motion = vdict! {
            "_motorThrust" => p.thrust, "_motorBurn" => p.burn, "_launchKg" => p.mass, "_propellantKg" => p.propellant,
            "_diameterM" => p.diameter, "_dragScale" => p.drag_scale, "_maxTime" => p.max_time, "_maxG" => p.max_g,
            "_navConstant" => p.nav, "_thrustVector" => if p.tvc { 1.0 } else { 0.0 },
            "_loft" => if p.loft { 1.0 } else { 0.0 }, "_decoyReject" => m.reject,
        };
        vdict! {
            "name" => m.name, "generation" => m.generation, "ir" => m.lock.is_some(), "kg" => p.mass,
            "power" => m.power, "radius" => m.blast(), "motion" => &motion,
        }
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

    /// The crew's skill: the enemy's level (0 low, 1 medium, 2 high; docs/ai.md §17).
    #[func]
    fn set_skill(&mut self, level: i64) {
        self.site.skill = Skill::enemy(level);
    }

    /// One decision at `now` (s): `alive` per part, the hostile jets alive (target dictionaries), the terrain
    /// (Callable(Vector3) -> float or null). {search, track, tracks, launches: [[part, id]], bursts: [[part, id,
    /// rounds, the laying error (Vector2, rad: across the line of sight, up)]], parts: [each part's ground position],
    /// heading (the vehicles', their course on the move), phase}.
    #[func]
    fn tick(&mut self, now: f64, alive: VarArray, targets: VarArray, ground: Callable) -> VarDictionary {
        let alive: Vec<bool> = alive.iter_shared().map(|v| v.try_to::<bool>().unwrap_or(true)).collect();
        let targets: Vec<Target> =
            targets.iter_shared().filter_map(|v| v.try_to::<VarDictionary>().ok()).map(|d| target(&d)).collect();
        let ground = terrain(Some(ground));
        let out = self.site.tick(now, &alive, &targets, &ground);
        if self.site.replan {
            // The march order: its route on the roads where they serve, as a convoy's (IafConvoy).
            let to = self.site.positions[self.site.at];
            let (a, b) = ([self.site.pos.x, self.site.pos.y], [to.x, to.y]);
            let road = crate::roads::route_graph(a, b, CONVOY_CLASS)
                .and_then(|r| r.route(a, b, CONVOY_CLASS))
                .unwrap_or_default();
            self.site.reroute(&road);
        }
        let tracks: PackedStringArray = out.tracks.iter().map(|s| GString::from(s.as_str())).collect();
        let launches: VarArray =
            out.launches.iter().map(|(p, id)| varray![*p as i64, id.as_str()].to_variant()).collect();
        let bursts: VarArray = out
            .bursts
            .iter()
            .map(|(p, id, n, e)| {
                varray![*p as i64, id.as_str(), i64::from(*n), Vector2::new(e[0] as f32, e[1] as f32)].to_variant()
            })
            .collect();
        let parts: VarArray =
            (0..self.site.spec().parts.len()).map(|i| vector3(self.site.part_pos(i, &ground)).to_variant()).collect();
        vdict! {
            "search" => out.search, "track" => out.track, "tracks" => &tracks, "launches" => &launches,
            "bursts" => &bursts, "parts" => &parts, "heading" => self.site.course, "phase" => self.site.phase(now),
        }
    }

    /// The march order now (`now` s) to its next position, its route on the roads where they serve (dev hook: a
    /// site relocates by itself after an engagement).
    #[func]
    fn relocate(&mut self, now: f64) {
        self.site.relocate(now);
    }

    /// A launch the caller could not make: its round back to `part`.
    #[func]
    fn refund(&mut self, part: i64, target: GString) {
        self.site.refund(part.max(0) as usize, &target.to_string());
    }

    /// For tests and logs: {phase, rounds (per part), engagements, at (the position index), pos (world), route (as
    /// IafConvoy's: its march's, empty in place)}.
    #[func]
    fn state(&self, now: f64) -> VarDictionary {
        let rounds: PackedInt64Array = self.site.rounds.iter().map(|&r| i64::from(r)).collect();
        let route = crate::world::route_dict(&self.site.route);
        vdict! {
            "phase" => self.site.phase(now), "rounds" => &rounds, "engagements" => i64::from(self.site.engagements),
            "at" => self.site.at as i64, "pos" => vector3(self.site.pos),
            "route" => &route,
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

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafTargetDrone {
    drone: Drone,
}

#[godot_api]
impl IafTargetDrone {
    /// The target drone flying under the brain record whose actions' codes are `actions` (brain.gd's rules); null
    /// when that is not a target drone's brain.
    #[func]
    fn create(actions: PackedInt64Array) -> Option<Gd<Self>> {
        let kind = DroneKind::of_actions(actions.as_slice())?;
        Some(Gd::from_object(Self { drone: Drone::new(kind) }))
    }

    /// Its kind: route, radar, evade.
    #[func]
    fn kind(&self) -> GString {
        match self.drone.kind {
            DroneKind::Route => "route",
            DroneKind::Radar => "radar",
            DroneKind::Evade => "evade",
        }
        .into()
    }

    /// A decision is due at `now` (s); then `scans` (pick the best air contact first) and `mode`.
    #[func]
    fn due(&mut self, now: f64) -> bool {
        self.drone.due(now)
    }

    #[func]
    fn scans(&self) -> bool {
        self.drone.scans()
    }

    /// Its autopilot loop this decision: `range_m` to its contact alive (< 0: none), `roll` 0..100 at random.
    #[func]
    fn mode(&self, range_m: f64, roll: i64) -> i64 {
        self.drone.mode((range_m >= 0.0).then_some(range_m), roll.clamp(0, 100) as u32) as i64
    }
}

/// The host's pylons, 4 values each (type, GPS, count, id).
fn pylons_of(a: &PackedInt64Array) -> Vec<Pylon> {
    a.as_slice()
        .as_chunks::<4>()
        .0
        .iter()
        .map(|&[kind, gps, count, id]| Pylon { kind, gps: gps != 0, count, id })
        .collect()
}

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafConvoy {
    convoy: Convoy,
}

/// A convoy keeps to roads of this class and the more important ones (tertiary; the route's cost per class prefers
/// the big ones, iaf_avionics::roads).
const CONVOY_CLASS: u8 = iaf_avionics::roads::CLASS_TERTIARY;

#[godot_api]
impl IafConvoy {
    /// A column of the unit records `ids` (head first: target_t72, target_ural) from `from` to `to` (world; z
    /// ignored): on the roads (IafRoads, opened) where they serve, else across country; its tail at `from`. Null
    /// without a known vehicle.
    #[func]
    fn create(ids: PackedStringArray, from: Vector3, to: Vector3) -> Option<Gd<Self>> {
        let specs: Vec<_> = ids.as_slice().iter().filter_map(|id| convoy::spec(&id.to_string())).collect();
        let (a, b) = ([from.x as f64, from.y as f64], [to.x as f64, to.y as f64]);
        let road =
            crate::roads::route_graph(a, b, CONVOY_CLASS).and_then(|r| r.route(a, b, CONVOY_CLASS)).unwrap_or_default();
        let convoy = Convoy::new(&specs, Route::plan(a, b, &road))?;
        Some(Gd::from_object(Self { convoy }))
    }

    /// The route: {points (PackedVector2Array, world), road (per segment), length (m)}.
    #[func]
    fn route(&self) -> VarDictionary {
        crate::world::route_dict(&self.convoy.route)
    }

    /// A blast at the world point `at` at `now` (s): within reach of a vehicle the convoy scatters; true when it did.
    #[func]
    fn alarm(&mut self, now: f64, at: Vector3) -> bool {
        self.convoy.alarm(now, vec3(at))
    }

    /// The game destroyed vehicle `i`: it stays where it is.
    #[func]
    fn down(&mut self, i: i64) {
        self.convoy.down(i.max(0) as usize);
    }

    /// The phase: move, scatter, rejoin, arrived.
    #[func]
    fn phase(&self) -> GString {
        self.convoy.phase.name().into()
    }

    /// Advances `dt` s at `now` on the terrain `ground` (Callable(Vector3) -> float or null): each vehicle head first
    /// {id, alive, pos, vel (world), heading, pitch (degrees)}.
    #[func]
    fn step(&mut self, now: f64, dt: f64, ground: Callable) -> VarArray {
        let ground = terrain(Some(ground));
        self.convoy.step(now, dt.max(0.0), &ground);
        self.convoy
            .vehicles
            .iter()
            .map(|v| {
                vdict! {
                    "id" => v.spec.id, "alive" => v.alive, "pos" => vector3(v.pos), "vel" => vector3(v.vel),
                    "heading" => v.heading, "pitch" => v.pitch,
                }
                .to_variant()
            })
            .collect()
    }
}

/// `IafFreeCombat`: Scramble's rules (`iaf_ai::free_combat`, docs/ai.md §23) for the front end's Scramble screen,
/// `modern-iaf/flight/fly.gd` and `modern-iaf/flight/free_combat.gd`. A setup is {cap_pairs, based_pairs (ints),
/// sam_net, shorad, drones, convoy (bools)}.
#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafFreeCombat {}

fn free_setup(d: &VarDictionary) -> free_combat::Setup {
    let pairs = |k: &str| num(d, k).unwrap_or(0.0).clamp(0.0, f64::from(free_combat::MAX_PAIRS)) as u8;
    let on = |k: &str| get::<bool>(d, k).unwrap_or(false);
    free_combat::Setup {
        cap_pairs: pairs("cap_pairs"),
        based_pairs: pairs("based_pairs"),
        sam_net: on("sam_net"),
        shorad: on("shorad"),
        drones: on("drones"),
        convoy: on("convoy"),
    }
}

#[godot_api]
impl IafFreeCombat {
    /// The fight's base drawn from `seed` among the theatre's `bases` (world), within reach of the player's `home`: its
    /// index in `bases`, -1 for none.
    #[func]
    fn area(seed: i64, home: Vector3, bases: PackedVector3Array) -> i64 {
        let bases: Vec<Vec3> = bases.as_slice().iter().map(|&b| vec3(b)).collect();
        free_combat::area(seed as u64, vec3(home), &bases).map_or(-1, |i| i as i64)
    }

    /// The runway start of a flight of `count` at the lineup point `lineup` (world) facing `heading` (deg): one {pos
    /// (world, the lineup's height), heading} per jet, the lead first, lined up in pairs.
    #[func]
    fn runway_start(lineup: Vector3, heading: f64, count: i64) -> VarArray {
        free_combat::runway_start(vec3(lineup), heading, count.max(1) as usize)
            .into_iter()
            .map(|[x, y, h]| vdict! {"pos" => Vector3::new(x as f32, y as f32, lineup.z), "heading" => h}.to_variant())
            .collect()
    }

    /// The enemy drawn from `seed` at enemy skill `skill` (0..2): a setup with its `task` (cap, drones, convoy, sam).
    #[func]
    fn roll(seed: i64, skill: i64) -> VarDictionary {
        let (s, task) = free_combat::roll(seed as u64, skill);
        vdict! {
            "cap_pairs" => i64::from(s.cap_pairs), "based_pairs" => i64::from(s.based_pairs), "sam_net" => s.sam_net,
            "shorad" => s.shorad, "drones" => s.drones, "convoy" => s.convoy, "task" => task.name()
        }
    }

    /// The air start of a flight of `count` round the fight's base `area` from the player's `home` among the
    /// theatre's `bases` (world): one {pos (world, the start's height), heading} per jet, the lead first.
    #[func]
    fn air_start(home: Vector3, area: Vector3, bases: PackedVector3Array, count: i64) -> VarArray {
        let bases: Vec<Vec3> = bases.as_slice().iter().map(|&b| vec3(b)).collect();
        free_combat::air_start(vec3(home), vec3(area), &bases, count.max(1) as usize)
            .into_iter()
            .map(|[x, y, h]| {
                let pos = Vector3::new(x as f32, y as f32, free_combat::START_ALT as f32);
                vdict! {"pos" => pos, "heading" => h}.to_variant()
            })
            .collect()
    }

    /// The start time `min` (minutes after local midnight) on the five-minute grid, in the day.
    #[func]
    fn time_valid(min: i64) -> i64 {
        free_combat::time_valid(min)
    }

    /// `min` stepped by `hours` hours and `steps` five-minute steps, round the clock.
    #[func]
    fn time_step(min: i64, hours: i64, steps: i64) -> i64 {
        free_combat::time_step(min, hours * free_combat::HOUR_STEP + steps * free_combat::MINUTE_STEP)
    }

    /// The start time as 24-hour military time HHMM ("0630").
    #[func]
    fn clock(min: i64) -> GString {
        GString::from(&free_combat::clock(min))
    }

    /// The flight's start time (minutes after local midnight): the set `min`, or drawn from `seed` with `random`.
    #[func]
    fn start_time(seed: i64, random: bool, min: i64) -> i64 {
        free_combat::start_time(seed as u64, random, min)
    }

    /// Israel's clock on `year`-`month`-`day`, hours ahead of UTC (3 on summer time, else 2).
    #[func]
    fn utc_offset(year: i64, month: i64, day: i64) -> f64 {
        free_combat::utc_offset(year, month, day)
    }

    /// The month (x, 1 to 12) and its day (y) of day `doy` of `year`.
    #[func]
    fn month_day(year: i64, doy: i64) -> Vector2i {
        let (m, d) = free_combat::month_day(year, doy);
        Vector2i::new(m as i32, d as i32)
    }

    /// The Scramble's date `doy` of `year` stepped by `days` days, then `months` months, round the year.
    #[func]
    fn date_step(year: i64, doy: i64, days: i64, months: i64) -> i64 {
        free_combat::date_step(year, doy, days, months)
    }

    /// The flight's day of `year`: the set `doy`, or drawn from `seed` with `random`.
    #[func]
    fn start_day(seed: i64, random: bool, year: i64, doy: i64) -> i64 {
        free_combat::start_day(seed as u64, random, year, doy)
    }

    /// The day of the year of `year`-`month`-`day` (1 for 1 January).
    #[func]
    fn day_of_year(year: i64, month: i64, day: i64) -> i64 {
        free_combat::day_of_year(year, month, day)
    }

    /// The AWACS's task call is due `airborne_s` after the player's jet left the ground, `since_s` after the last.
    #[func]
    fn task_due(airborne_s: f64, since_s: f64) -> bool {
        free_combat::task_due(airborne_s, since_s)
    }

    /// The AWACS's call of task `task` to `callsign` (the player's formation name) at `player` for its target at
    /// `target` (world): [template, its %S particles]; [] for an unknown task.
    #[func]
    fn task_call(task: GString, callsign: GString, player: Vector3, target: Vector3) -> VarArray {
        let Some(t) = free_combat::Task::from_name(&task.to_string()) else {
            return VarArray::new();
        };
        let (template, args) = free_combat::task_call(t, &callsign.to_string(), vec3(player), vec3(target));
        let args: PackedStringArray = args.iter().map(GString::from).collect();
        varray![template, &args]
    }

    /// The enemy of `setup` round the fight's base `area` facing the player's `home` (world, on the ground), in
    /// placing order: each {kind: site (kind, pos, heading), net (radar, post, heading), cap (jets [2], heading,
    /// station), based (first, station), convoy (from, to), drones (route, count, interval)}.
    #[func]
    fn plan(setup: VarDictionary, home: Vector3, area: Vector3) -> VarArray {
        use free_combat::Spawn;
        free_combat::plan(&free_setup(&setup), vec3(home), vec3(area))
            .into_iter()
            .map(|s| {
                match s {
                    Spawn::Site { kind, pos, heading } => {
                        vdict! {"kind" => "site", "site" => kind, "pos" => vector3(pos), "heading" => heading}
                    }
                    Spawn::Net { radar, post, heading } => {
                        vdict! {"kind" => "net", "radar" => vector3(radar), "post" => vector3(post), "heading" => heading}
                    }
                    Spawn::Cap { jets, heading, station } => {
                        let j: VarArray = jets.iter().map(|&v| vector3(v).to_variant()).collect();
                        vdict! {"kind" => "cap", "jets" => &j, "heading" => heading, "station" => vector3(station)}
                    }
                    Spawn::Based { first, station } => {
                        vdict! {"kind" => "based", "first" => i64::from(first), "station" => vector3(station)}
                    }
                    Spawn::Convoy { from, to } => vdict! {"kind" => "convoy", "from" => vector3(from), "to" => vector3(to)},
                    Spawn::Drones { route, count, interval } => {
                        let r: VarArray = route.iter().map(|&v| vector3(v).to_variant()).collect();
                        vdict! {"kind" => "drones", "route" => &r, "count" => i64::from(count), "interval" => interval}
                    }
                }
                .to_variant()
            })
            .collect()
    }
}
