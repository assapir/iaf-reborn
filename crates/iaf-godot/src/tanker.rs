//! `IafTanker`: the tanker and its boom operator (`iaf_ai::tanker`; modern-iaf/docs/research/air-refuelling.md §8)
//! for `shared/ai/tanker.gd`. Positions and velocities are the scene's (the flights' frame, as `IafAi`'s).

use godot::prelude::*;
use iaf_ai::tanker::{Boom, Event, KC46, REEM, Receiver, Station, Tanker, Track};

use crate::flight::{to_enu, to_godot};
use crate::world::{get, num};

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafTanker {
    t: Tanker,
}

/// An event as [name, receiver id, kg]: cleared_precontact, stand_by, cleared_contact, contact, disconnect,
/// breakaway, complete (kg the fuel given).
fn event(e: Event) -> VarArray {
    let (name, id, kg) = match e {
        Event::ClearedPrecontact(id) => ("cleared_precontact", id, 0.0),
        Event::StandBy(id) => ("stand_by", id, 0.0),
        Event::ClearedContact(id) => ("cleared_contact", id, 0.0),
        Event::Contact(id) => ("contact", id, 0.0),
        Event::Disconnect(id) => ("disconnect", id, 0.0),
        Event::Breakaway(id) => ("breakaway", id, 0.0),
        Event::Complete(id, kg) => ("complete", id, kg),
    };
    varray![name, id as i64, kg as f64]
}

#[godot_api]
impl IafTanker {
    /// A tanker of `kind` ("kc46" the KC-46A Gideon, "reem" the 707 Re'em) on its racetrack: the inbound leg from the
    /// scene point `anchor` (its height the track's, 30,000 ft) on `course` (deg from north); null for another kind.
    #[func]
    fn create(kind: GString, anchor: Vector3, course: f64) -> Option<Gd<Self>> {
        let spec = match kind.to_string().as_str() {
            "kc46" => KC46,
            "reem" => REEM,
            _ => return None,
        };
        Some(Gd::from_object(IafTanker { t: Tanker::new(spec, Track::new(to_enu(anchor), course.to_radians())) }))
    }

    /// Its pose now: {position (scene), velocity, forward, right, up (scene unit vectors)}.
    #[func]
    fn pose(&self) -> VarDictionary {
        let p = self.t.pose();
        let [f, r, u] = p.axes();
        let mut d = VarDictionary::new();
        d.set("position", to_godot(p.pos));
        d.set("velocity", to_godot(p.vel));
        d.set("forward", to_godot(f));
        d.set("right", to_godot(r));
        d.set("up", to_godot(u));
        d
    }

    /// The boom: {state (stowed, trail, flying, contact), elevation, azimuth (rad, + right), extension (m), nozzle
    /// (scene), pdl (Vector2i: elevation, telescope, each -2..2, + fly down / fly aft; absent: dark)}.
    #[func]
    fn boom(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let state = match self.t.boom {
            Boom::Stowed => "stowed",
            Boom::Trail => "trail",
            Boom::Flying => "flying",
            Boom::Contact => "contact",
        };
        d.set("state", state);
        let [e, a, x] = self.t.angles;
        d.set("elevation", e);
        d.set("azimuth", a);
        d.set("extension", x);
        d.set("nozzle", to_godot(self.t.nozzle()));
        if let Some((pe, pt)) = self.t.pdl {
            d.set("pdl", Vector2i::new(pe as i32, pt as i32));
        }
        d
    }

    /// Receiver `id` asks to refuel: its answer's event ([`event`]).
    #[func]
    fn request(&mut self, id: i64) -> VarArray {
        event(self.t.request(id as u32))
    }

    /// Receiver `id` leaves (gone, or flown away): the next one's clearance, or an empty array.
    #[func]
    fn leave(&mut self, id: i64) -> VarArray {
        self.t.leave(id as u32).map_or_else(VarArray::new, event)
    }

    /// The receivers it knows: the queue (the first on the boom), then those done.
    #[func]
    fn receivers(&self) -> PackedInt64Array {
        self.t.queue.iter().chain(&self.t.done).map(|&i| i as i64).collect()
    }

    /// Receiver `id` is done (refuelled, on the right wing until it leaves).
    #[func]
    fn is_done(&self, id: i64) -> bool {
        self.t.done.contains(&(id as u32))
    }

    /// Where receiver `id` is to fly: {kind: receptacle (its receptacle on the point) or wing (the jet on it), at
    /// (scene)}; empty when the tanker does not know it.
    #[func]
    fn station(&self, id: i64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let p = self.t.pose();
        match self.t.station(id as u32) {
            Some(Station::Receptacle(b)) => {
                d.set("kind", "receptacle");
                d.set("at", to_godot(p.to_world(b)));
            }
            Some(Station::Wing(b)) => {
                d.set("kind", "wing");
                d.set("at", to_godot(p.to_world(b)));
            }
            None => {}
        }
        d
    }

    /// AI receiver `id`'s station for `IafAi.set_refuel`: {position, velocity, attitude (Vector3 pitch, roll,
    /// heading rad: the tanker as the slot loop's leader), slot (Vector3 forward, right, up m)} for the jet whose
    /// receptacle is `receptacle` (forward, right, up m) from its centre; empty: none.
    #[func]
    fn slot(&self, id: i64, receptacle: Vector3) -> VarDictionary {
        let mut d = VarDictionary::new();
        let r = [receptacle.x as f64, receptacle.y as f64, receptacle.z as f64];
        if let Some(s) = self.t.slot(id as u32, r) {
            let p = self.t.pose();
            d.set("position", to_godot(p.pos));
            d.set("velocity", to_godot(p.vel));
            d.set("attitude", Vector3::new(p.att[0] as f32, p.att[1] as f32, p.att[2] as f32));
            d.set("slot", Vector3::new(s[0], s[1], s[2]));
        }
        d
    }

    /// One frame of `dt` s: the tanker flies on to now, then works the receivers as they are now (after their own
    /// steps: each {id, receptacle (scene), velocity (scene), door, room_kg, disconnect}; every receiver it knows,
    /// else it counts as gone): {events: [[name, id, kg]], fuel: [id, kg] (absent: none given), why (the last
    /// disconnect's reason)}.
    #[func]
    fn step(&mut self, dt: f64, receivers: VarArray) -> VarDictionary {
        let rx: Vec<Receiver> = receivers
            .iter_shared()
            .filter_map(|v| v.try_to::<VarDictionary>().ok())
            .map(|r| Receiver {
                id: num(&r, "id").unwrap_or(0.0) as u32,
                receptacle: to_enu(get(&r, "receptacle").unwrap_or_default()),
                vel: to_enu(get(&r, "velocity").unwrap_or_default()),
                door: get(&r, "door").unwrap_or(false),
                room_kg: num(&r, "room_kg").unwrap_or(0.0) as f32,
                disconnect: get(&r, "disconnect").unwrap_or(false),
            })
            .collect();
        self.t.advance(dt);
        let (events, fuel) = self.t.work(dt, &rx);
        let mut d = VarDictionary::new();
        let list: VarArray = events.into_iter().map(|e| event(e).to_variant()).collect();
        d.set("events", &list);
        if let Some((id, kg)) = fuel {
            d.set("fuel", &varray![id as i64, kg as f64]);
        }
        d.set("why", self.t.why.as_str());
        d
    }
}
