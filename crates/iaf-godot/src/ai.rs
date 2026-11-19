//! `IafAi`: Modern IAF's flight AI (`iaf_ai`, modern-iaf/docs/ai-plan.md §6) for one flight of up to four `IafFlight`
//! jets. Each frame, after every jet's `step` (one instant), `step` reads every jet's flight model and autopilot and
//! sets the AI jets' autopilot for their next `ap_step` (mode, leader, slot, engine start); the player's jet is read
//! only but for its home hangar (`add_member`). `IafSite`: an air-defence site (`iaf_ai::site`, docs/ai.md §15)
//! for `shared/ai/air_defence.gd`.

use godot::prelude::*;
use iaf_ai::Flight;
use iaf_ai::site::{self, Emcon, Kind, Site, Target};
use iaf_flight::Vec3;
use iaf_flight::airframe::Rcs;

use crate::flight::IafFlight;
use crate::world::{get, num, terrain, vec3, vector3};

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
    /// fingertip, echelon_right, echelon_left, line_abreast, wedge, trail, rejoin, rtb. False: unknown, or nobody to
    /// take it. The answers come from `step` as calls.
    #[func]
    fn command(&mut self, now: f64, to: i64, cmd: GString) -> bool {
        self.flight.command(now, to.clamp(0, 5) as u8, &cmd.to_string())
    }

    /// One frame at `now` (s), after every jet's steps of the frame (one instant, `Flight::sense`): the AI's decisions
    /// and its jets' orders for their next `ap_step`. Returns the calls due, each
    /// {from: number, id: ack, unable, joker, bingo, rtb, fuel_state, lead_change, in_position}.
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

    /// Jet `number` for tests and logs: role (lead / wingman), stage (its control loop), slot_error (m), avoiding (it
    /// pulls away from another jet), fuel_kg, bingo_kg, released (sent home); empty for an unknown number.
    #[func]
    fn state(&self, number: i64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(m) = self.flight.member(number.clamp(0, 255) as u8) else { return d };
        d.set("role", if m.number == self.flight.lead() { "lead" } else { "wingman" });
        if let Some((_, jet, _)) = self.jets.iter().find(|j| j.0 == m.number) {
            d.set("stage", &jet.bind().ap_stage());
        }
        d.set("slot_error", m.slot_error);
        d.set("avoiding", m.order.avoid.is_some());
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
    let rcs = get::<VarDictionary>(d, "rcs").and_then(|r| {
        Some(Rcs {
            front_m2: num(&r, "front_m2")?,
            side_m2: num(&r, "side_m2")?,
            rear_m2: num(&r, "rear_m2")?,
            bays_open_m2: num(&r, "bays_open_m2").unwrap_or(0.0),
            store_m2: num(&r, "store_m2")?,
        })
    });
    let dlz: Vector2 = get(d, "dlz").unwrap_or_default();
    Target {
        id: get::<GString>(d, "id").unwrap_or_default().to_string(),
        pos: vec3(get(d, "pos").unwrap_or_default()),
        vel: vec3(get(d, "vel").unwrap_or_default()),
        nose: vec3(get(d, "nose").unwrap_or_default()),
        rcs: rcs.unwrap_or(site::FIGHTER),
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
