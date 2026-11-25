//! `IafAwacs`: Modern IAF's AWACS controller (`iaf_ai::awacs`, docs/ai.md §24) and its Eitam (`iaf_ai::eitam`) for
//! `shared/audio/radio.gd`: the radio menu's requests answered from the controller's sensor (the Eitam where it flies,
//! the 1998 game's virtual AWACS where the flight has none), the Eitam's orbit, retreat and call for help. Contacts
//! are dictionaries {key, pos (world), ground, heading (deg), ident ("hostile", "bogey", "friendly"), tanker}.

use crate::world::{get, num, vec3, vector3};
use godot::prelude::*;
use iaf_ai::awacs::{self, Ask, Contact, Ident, Request, Sensor};
use iaf_ai::eitam::{self, Eitam};

fn string(d: &VarDictionary, key: &str) -> String {
    get::<GString>(d, key).map(|s| s.to_string()).unwrap_or_default()
}

fn contacts(a: &VarArray) -> Vec<Contact> {
    a.iter_shared()
        .filter_map(|v| v.try_to::<VarDictionary>().ok())
        .map(|d| Contact {
            key: string(&d, "key"),
            pos: vec3(get(&d, "pos").unwrap_or_default()),
            ground: num(&d, "ground").unwrap_or_default(),
            heading: num(&d, "heading").unwrap_or_default(),
            ident: match string(&d, "ident").as_str() {
                "hostile" => Ident::Hostile,
                "friendly" => Ident::Friendly,
                _ => Ident::Bogey,
            },
            tanker: get(&d, "tanker").unwrap_or(false),
        })
        .collect()
}

fn request(id: &str) -> Option<Request> {
    Some(match id {
        "picture" => Request::Picture,
        "bogey_dope" => Request::BogeyDope,
        "declare" => Request::Declare,
        "vector_target" => Request::VectorTarget,
        "vector_home" => Request::VectorHome,
        "vector_tanker" => Request::VectorTanker,
        _ => return None,
    })
}

fn opt_pos(d: &VarDictionary, key: &str) -> Option<iaf_flight::Vec3> {
    get::<Vector3>(d, key).map(vec3)
}

/// {callsign, player, locked (a key; absent: no lock), task, home (world; absent: none)}.
fn ask(d: &VarDictionary) -> Ask {
    let locked = string(d, "locked");
    Ask {
        callsign: string(d, "callsign"),
        player: vec3(get(d, "player").unwrap_or_default()),
        locked: (!locked.is_empty()).then_some(locked),
        task: opt_pos(d, "task"),
        home: opt_pos(d, "home"),
    }
}

fn line(t: &str, args: &[String]) -> Variant {
    let args: PackedStringArray = args.iter().map(GString::from).collect();
    varray![t, &args].to_variant()
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafAwacs {
    eitam: Option<Eitam>,
}

impl IafAwacs {
    fn sensor(&self) -> Sensor {
        self.eitam.as_ref().map_or(Sensor::Virtual, Eitam::sensor)
    }
}

#[godot_api]
impl IafAwacs {
    /// The Eitam on its station for a fight at `area` flown from `home` (the flight's base) and `start` (its start
    /// point), all world points: behind the flight's way to the fight and to its side, at 41,000 ft.
    #[func]
    fn place_eitam(&mut self, area: Vector3, home: Vector3, start: Vector3) {
        self.eitam = Some(Eitam::new(eitam::station(vec3(area), vec3(home), vec3(start))));
    }

    /// The Eitam {pos (world), heading (deg), speed (m/s), alive, retreating}; empty when the flight has none.
    #[func]
    fn eitam(&self) -> VarDictionary {
        self.eitam.as_ref().map_or_else(VarDictionary::new, |e| {
            vdict! {
                "pos" => vector3(e.pos), "heading" => e.heading, "speed" => e.speed, "alive" => e.alive,
                "retreating" => e.threat.is_some(),
            }
        })
    }

    /// The Eitam was shot down: the controller's service ends.
    #[func]
    fn eitam_down(&mut self) {
        if let Some(e) = &mut self.eitam {
            e.alive = false;
        }
    }

    /// True while the controller works (no Eitam, or the Eitam alive).
    #[func]
    fn in_service(&self) -> bool {
        self.sensor() != Sensor::Lost
    }

    /// The Eitam's `dt` s at `now` with the `contacts`; its calls to `callsign` at `player` (world) as [{template,
    /// args (PackedStringArray), bearing, miles, hostile}] (the call for help and the group it names).
    #[func]
    fn step(&mut self, now: f64, dt: f64, contacts_: VarArray, callsign: GString, player: Vector3) -> VarArray {
        let Some(e) = &mut self.eitam else { return VarArray::new() };
        let cs = contacts(&contacts_);
        e.step(now, dt, &cs, &callsign.to_string(), vec3(player))
            .iter()
            .map(|(t, a, n)| {
                let args: PackedStringArray = a.iter().map(GString::from).collect();
                vdict! {
                    "template" => *t, "args" => &args, "bearing" => n.bearing as i64, "miles" => n.miles as i64,
                    "hostile" => n.hostile,
                }
                .to_variant()
            })
            .collect()
    }

    /// The Eitam's radar cross-section, as an airframe's `rcs` (the radars read it from the entity).
    #[func]
    fn eitam_rcs() -> VarDictionary {
        let r = eitam::RCS;
        vdict! {
            "front_m2" => r.front_m2, "side_m2" => r.side_m2, "rear_m2" => r.rear_m2, "bays_open_m2" => r.bays_open_m2,
            "store_m2" => r.store_m2,
        }
    }

    /// The controller's sensor sees `contact` (the player at `player`, world).
    #[func]
    fn sees(&self, player: Vector3, contact: VarDictionary) -> bool {
        contacts(&varray![&contact]).first().is_some_and(|c| awacs::sees(self.sensor(), vec3(player), c))
    }

    /// Why request `id` (picture, bogey_dope, declare, vector_target, vector_home, vector_tanker) cannot be made now
    /// (lost, no_lock, no_tanker, no_home), "" when it can; `ask` as `answer`'s.
    #[func]
    fn refusal(&self, id: GString, ask_: VarDictionary, contacts_: VarArray) -> GString {
        let Some(r) = request(&id.to_string()) else { return "unknown".into() };
        match awacs::check(self.sensor(), r, &ask(&ask_), &contacts(&contacts_)) {
            Ok(()) => GString::new(),
            Err(e) => e.id().into(),
        }
    }

    /// The controller's answer to request `id` for `ask` {callsign, player, locked, task, home}: {lines: [[template,
    /// PackedStringArray args]], named: [{bearing, miles, hostile}]} (the groups it named, for the flight's calls).
    #[func]
    fn answer(&self, id: GString, ask_: VarDictionary, contacts_: VarArray) -> VarDictionary {
        let Some(r) = request(&id.to_string()) else { return VarDictionary::new() };
        let a = awacs::answer(self.sensor(), r, &ask(&ask_), &contacts(&contacts_));
        let lines: VarArray = a.lines.iter().map(|(t, args)| line(t, args)).collect();
        let named: VarArray = a
            .named
            .iter()
            .map(|n| {
                vdict! { "bearing" => n.bearing as i64, "miles" => n.miles as i64, "hostile" => n.hostile }.to_variant()
            })
            .collect();
        vdict! { "lines" => &lines, "named" => &named }
    }
}
