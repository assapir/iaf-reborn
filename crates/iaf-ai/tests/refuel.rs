//! An AI wingman refuels from the tanker (modern-iaf/docs/research/air-refuelling.md §8.3): the lead's "refuel", the
//! slot loop on the tanker's stations (pre-contact, contact, the right wing) on the 6-DoF Sufa, the boom operator's
//! clearances, the contact, the offload to full and the rejoin. Skips with a message when `assets/converted/own` is
//! not built.

use std::path::PathBuf;

use iaf_ai::tanker::{Boom, Event, KC46, Receiver, Station, Tanker, Track};
use iaf_ai::{Flight, apply};
use iaf_flight::autopilot::{Autopilot, Config, Waypoint};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;
/// The Sufa's receptacle from its centre (forward, right, up), m: the airframe definition's (shared/extra/planes).
const RECEPTACLE: [f64; 3] = [1.6, 0.0, 1.1];

#[test]
fn an_ai_wingman_refuels_to_full_and_rejoins() {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    if !dir.join("resource/md/bd.ibx").is_file() {
        println!("skipped: assets/converted/own not built");
        return;
    }
    let (p, e) = iaf_flight::load_with(&dir, "F-16I", DataSet::Original).unwrap();
    let mut tanker = Tanker::new(KC46, Track::new(Vec3::ZERO, 0.0));
    // 90 s before the end of the inbound leg: the contact goes on into the turn.
    tanker.s = tanker.track.leg - tanker.track.speed * 90.0;
    let t0 = tanker.pose();
    let v = t0.vel;
    // #1 (the player, flown by its autopilot) ahead and right; #2 300 m behind the tanker and 100 m below.
    // (#2 2 km behind and to the left, 200 m below: the far join to its station.)
    let starts = [t0.pos + Vec3::new(200.0, 500.0, 0.0), t0.pos + Vec3::new(-800.0, -2000.0, -200.0)];
    let mut jets: Vec<(Fm, Autopilot)> = starts
        .iter()
        .map(|&pos| {
            let st = Start {
                position: pos,
                pitch: 0.0,
                roll: 0.0,
                heading: 0.0,
                velocity: v,
                airborne: true,
                engine_on: true,
            };
            (Fm::start("F-16I", p.clone(), e.clone(), st), Autopilot::new(Config::load(&dir)))
        })
        .collect();
    let mut flight = Flight::default();
    for (i, (fm, ap)) in jets.iter_mut().enumerate() {
        flight.add(i as u8 + 1, i > 0, fm, ap);
    }
    {
        let (fm, ap) = &mut jets[0];
        ap.route = vec![Waypoint { x: 0.0, y: 400_000.0, z: t0.pos.z, t: 0.0, action: 3 }];
        ap.set_mode(fm, 0);
        ap.set_mode(fm, 9);
    }
    // Room for 1,500 kg: the fuel taken down that far.
    {
        let fm = &mut jets[1].0;
        let cap = fm.fuel_capacity_kg();
        fm.set_fuel(cap - 1500.0);
    }
    let mut t = 0.0;
    let mut events: Vec<(f64, Event)> = Vec::new();
    let mut given = 0.0f32;
    let mut asked = false;
    let mut worst_contact: f64 = 0.0;
    let mut contact_s = 0.0;
    let mut banked_s = 0.0;
    while t < 600.0 {
        for (i, (fm, ap)) in jets.iter().enumerate() {
            flight.sense(i as u8 + 1, true, fm, ap);
        }
        if !asked && t > 1.0 {
            assert!(flight.command(t, 2, "refuel"));
            assert_eq!(tanker.request(2), Event::ClearedPrecontact(2));
            asked = true;
        }
        // The receiver as it is now; the tanker's work; its station for the AI.
        let s = jets[1].0.state();
        let rcpt = s.position + s.forward * RECEPTACLE[0] + s.right * RECEPTACLE[1] + s.up * RECEPTACLE[2];
        let vel = Vec3::new(s.velocity[0] as f64, s.velocity[1] as f64, s.velocity[2] as f64);
        let room = (jets[1].0.fuel_capacity_kg() - s.fuel_kg).max(0.0);
        let rx = Receiver { id: 2, receptacle: rcpt, vel, door: true, room_kg: room, disconnect: false };
        // The station at the tanker's pose now (the jets' instant), then the tanker's frame.
        let station = tanker.slot(2, RECEPTACLE).map(|slot| (tanker.pose().leader(), slot));
        let latched = tanker.boom == Boom::Contact;
        let off = tanker.nozzle().distance(rcpt);
        let (ev, fuel) = tanker.step(DT, &[rx]);
        if let Some((_, kg)) = fuel {
            given += kg;
            jets[1].0.add_fuel(kg);
        }
        if latched && tanker.boom == Boom::Contact {
            contact_s += DT;
            worst_contact = worst_contact.max(off);
            if tanker.pose().att[1].abs() > 0.3 {
                banked_s += DT;
            }
        }
        for e in ev {
            println!(
                "t {t:.1}: {e:?} {} room {room:.0}",
                if matches!(e, Event::Disconnect(_)) { tanker.why.as_str() } else { "" }
            );
            events.push((t, e));
        }
        if asked && flight.members[1].refuelling {
            flight.set_refuel(2, station);
        }
        flight.step(t);
        for (i, (fm, ap)) in jets.iter_mut().enumerate() {
            if i > 0 {
                apply(&flight.members[i].order, ap, fm);
            }
            ap.step(fm, &|_, _| 0.0);
            fm.step(DT);
            assert!(fm.state().crashed.is_none(), "#{} crashed at {t:.1}", i + 1);
        }
        t += DT;
        if events.iter().any(|(_, e)| matches!(e, Event::Complete(..))) && t > 30.0 {
            break;
        }
    }
    let when = |want: fn(&Event) -> bool| events.iter().find(|(_, e)| want(e)).map(|(t, _)| *t);
    let cleared = when(|e| matches!(e, Event::ClearedContact(2)));
    let contact = when(|e| matches!(e, Event::Contact(2)));
    let complete = when(|e| matches!(e, Event::Complete(2, _)));
    println!(
        "cleared {cleared:?} contact {contact:?} complete {complete:?}, {given:.0} kg, {contact_s:.0} s in contact, {banked_s:.0} s banked"
    );
    assert!(cleared.is_some_and(|c| c < 120.0), "stable at pre-contact within 2 min");
    assert!(contact.is_some(), "contact made");
    assert!(complete.is_some(), "refuelled to full");
    // 1,500 kg and what the engine burnt meanwhile (about 0.7 kg/s).
    assert!(given > 1500.0 && given < 1600.0, "1,500 kg taken and the burn: {given}");
    let disconnects = events.iter().filter(|(_, e)| matches!(e, Event::Disconnect(_))).count();
    assert!(disconnects <= 2, "held the contact: {disconnects} disconnects");
    assert!(worst_contact < 0.2, "the boom on the receptacle: {worst_contact}");
    assert!(banked_s > 20.0, "held the contact in the tanker's turn: {banked_s:.0} s at its full bank");
    assert_eq!(tanker.station(2), Some(Station::Wing(iaf_ai::tanker::REFORM)));
    // On the right wing within a minute; then the tanker lets it go and it rejoins the flight.
    for _ in 0..(60.0 / DT) as usize {
        for (i, (fm, ap)) in jets.iter().enumerate() {
            flight.sense(i as u8 + 1, true, fm, ap);
        }
        let station = tanker.slot(2, RECEPTACLE).map(|slot| (tanker.pose().leader(), slot));
        tanker.step(DT, &[]);
        flight.set_refuel(2, station);
        flight.step(t);
        for (i, (fm, ap)) in jets.iter_mut().enumerate() {
            if i > 0 {
                apply(&flight.members[i].order, ap, fm);
            }
            ap.step(fm, &|_, _| 0.0);
            fm.step(DT);
        }
        t += DT;
    }
    let wing = tanker.pose().to_world(iaf_ai::tanker::REFORM);
    let d = jets[1].0.state().position.distance(wing);
    assert!(d < 30.0, "on the tanker's right wing: {d:.0} m off");
    tanker.leave(2);
    flight.set_refuel(2, None);
    assert!(!flight.members[1].refuelling, "back to the flight");
    // Sent to the tanker again, then home: the RTB holds once the tanker lets it go.
    assert!(flight.command(t, 2, "refuel"));
    assert!(flight.command(t, 2, "rtb"));
    assert!(!flight.members[1].refuelling && flight.members[1].rtb, "rtb ends the refuelling");
    flight.set_refuel(2, None);
    assert!(flight.members[1].rtb, "the lead's RTB stays");
}
