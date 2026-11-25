//! The tanker and its boom operator (crates/iaf-ai/src/tanker.rs; modern-iaf/docs/research/air-refuelling.md §8):
//! the track, the clearances, the contact, the offload, the disconnects, the breakaway and the queue, with receivers
//! flown exactly where the test puts them.

use iaf_ai::tanker::{Boom, Event, FULL_KG, KC46, OBSERVATION, REFORM, Receiver, Station, Tanker, Track};
use iaf_flight::Vec3;

const DT: f64 = 0.05;

fn tanker() -> Tanker {
    Tanker::new(KC46, Track::new(Vec3::new(0.0, 0.0, 0.0), 0.0))
}

/// Receiver `id` with its receptacle on tanker body point `b`, moving with the tanker.
fn at(t: &Tanker, id: u32, b: [f64; 3], room: f32) -> Receiver {
    let p = t.pose();
    Receiver { id, receptacle: p.to_world(b), vel: p.vel, door: true, room_kg: room, disconnect: false }
}

/// Runs `secs` with the receivers placed by `place` each frame; every event and the fuel given.
fn run(t: &mut Tanker, secs: f64, mut place: impl FnMut(&Tanker) -> Vec<Receiver>) -> (Vec<Event>, f32) {
    let (mut evs, mut kg) = (Vec::new(), 0.0);
    for _ in 0..(secs / DT).round() as usize {
        let rx = place(t);
        let (e, f) = t.step(DT, &rx);
        evs.extend(e);
        kg += f.map_or(0.0, |f| f.1);
    }
    (evs, kg)
}

#[test]
fn the_track_is_a_closed_left_hand_racetrack() {
    let t = Track::new(Vec3::new(1000.0, 2000.0, 0.0), 0.5);
    let bank = t.bank.to_degrees();
    assert!((bank - 18.6).abs() < 0.1, "18.6° of bank at 480 kt on a 10 NM radius: {bank}");
    let step = 10.0;
    let mut s = 0.0;
    while s < t.length() {
        let (a, b) = (t.at(s), t.at(s + step));
        assert!(a.pos.distance(b.pos) < step * 1.001, "continuous at {s}");
        s += step;
    }
    assert!(t.at(0.0).pos.distance(t.at(t.length()).pos) < 1e-6);
    // The first turn is to the left, with the left wing down.
    let mid = t.at(t.leg + t.radius);
    assert!(mid.att[1] < -t.bank * 0.99, "banked left mid-turn: {}", mid.att[1]);
    assert!((t.at(0.0).pos.z - 9144.0).abs() < 1.0, "at 30,000 ft");
}

#[test]
fn a_receiver_is_cleared_makes_contact_takes_fuel_and_is_complete() {
    let mut t = tanker();
    assert_eq!(t.request(1), Event::ClearedPrecontact(1));
    let pre = t.precontact_body();
    // 1.5 s held at pre-contact: not yet cleared; 2 s and it is.
    let (e, _) = run(&mut t, 1.5, |t| vec![at(t, 1, pre, 1000.0)]);
    assert!(e.is_empty(), "{e:?}");
    let (e, _) = run(&mut t, 1.0, |t| vec![at(t, 1, pre, 1000.0)]);
    assert_eq!(e, vec![Event::ClearedContact(1)]);
    // The station moves from pre-contact to contact at 2.5 kt: 15.3 m in about 12 s.
    let Some(Station::Receptacle(s0)) = t.station(1) else { panic!() };
    assert!((s0[0] - pre[0]).abs() < 1.0, "near pre-contact as it is cleared: {s0:?}");
    run(&mut t, 13.0, |t| vec![at(t, 1, pre, 1000.0)]);
    assert_eq!(t.station(1), Some(Station::Receptacle(t.contact_body())), "at contact 13 s later");
    // The receiver closes on the contact position at 1 m/s; the boom flies to it and latches.
    let c = t.contact_body();
    let mut x = 0.0;
    let (e, _) = run(&mut t, 30.0, |t| {
        x = (x + DT).min(15.0);
        vec![at(t, 1, [pre[0] + x, c[1], pre[2] + x * 3.0 / 15.0], 1000.0)]
    });
    assert_eq!(e.first(), Some(&Event::Contact(1)), "{e:?}");
    assert_eq!(t.boom, Boom::Contact);
    assert!(t.pdl == Some((0, 0)), "the PDLs centred in the contact position: {:?}", t.pdl);
    // 3,000 lb a minute (22.7 kg/s): 1,000 kg take 44 s, the last 5 kg left (the receiver full).
    let mut room = 1000.0_f32;
    let mut evs = Vec::new();
    let mut secs = 0.0;
    while room > FULL_KG && secs < 60.0 {
        let (e, f) = t.step(DT, &[at(&t, 1, c, room)]);
        evs.extend(e);
        room -= f.map_or(0.0, |f| f.1);
        secs += DT;
    }
    assert!((secs - 43.9).abs() < 0.3, "1,000 kg at 3,000 lb a minute: {secs} s");
    let (e, _) = run(&mut t, 0.1, |t| vec![at(t, 1, c, 0.0)]);
    assert_eq!(e[0], Event::Disconnect(1));
    assert!(matches!(e[1], Event::Complete(1, kg) if kg > 990.0), "{e:?}");
    assert_eq!(t.station(1), Some(Station::Wing(REFORM)));
    let (_, _) = run(&mut t, 20.0, |_| vec![]);
    assert_eq!(t.boom, Boom::Stowed);
}

/// A receiver in contact.
fn in_contact() -> Tanker {
    let mut t = tanker();
    t.request(1);
    let pre = t.precontact_body();
    run(&mut t, 2.5, |t| vec![at(t, 1, pre, 5000.0)]);
    let c = t.contact_body();
    let (e, _) = run(&mut t, 20.0, |t| vec![at(t, 1, c, 5000.0)]);
    assert!(e.contains(&Event::Contact(1)), "{e:?}");
    t
}

#[test]
fn leaving_the_envelope_disconnects_and_the_boom_reconnects_inside_it() {
    let mut t = in_contact();
    let c = t.contact_body();
    // 5 m aft: past the telescope's outer limit.
    let (e, _) = run(&mut t, 0.2, |t| vec![at(t, 1, [c[0] - 5.0, c[1], c[2]], 5000.0)]);
    assert_eq!(e, vec![Event::Disconnect(1)]);
    assert_ne!(t.boom, Boom::Contact);
    assert_eq!(t.station(1), Some(Station::Receptacle(t.precontact_body())), "back to pre-contact");
    let pre = t.precontact_body();
    let (e, _) = run(&mut t, 2.5, |t| vec![at(t, 1, pre, 5000.0)]);
    assert_eq!(e, vec![Event::ClearedContact(1)]);
    let (e, _) = run(&mut t, 10.0, |t| vec![at(t, 1, c, 5000.0)]);
    assert_eq!(e, vec![Event::Contact(1)]);
}

#[test]
fn the_pilots_button_disconnects() {
    let mut t = in_contact();
    let c = t.contact_body();
    let (e, _) = run(&mut t, 1.0, |t| vec![Receiver { disconnect: true, ..at(t, 1, c, 5000.0) }]);
    assert_eq!(e, vec![Event::Disconnect(1)], "no contact again until cleared again");
}

#[test]
fn too_close_is_a_breakaway_and_the_receiver_is_cleared_again_once_back() {
    let mut t = in_contact();
    let c = t.contact_body();
    // 4 m forward and up along the boom: inside the telescope's inner limit.
    let (e, _) = run(&mut t, 0.1, |t| vec![at(t, 1, [c[0] + 4.0, c[1], c[2] + 2.0], 5000.0)]);
    assert_eq!(e, vec![Event::Disconnect(1), Event::Breakaway(1)]);
    let Some(Station::Receptacle(back)) = t.station(1) else { panic!("{:?}", t.station(1)) };
    assert!(c[0] - back[0] > 30.0, "sent back past 30 m: {back:?}");
    let (e, _) = run(&mut t, 1.0, |t| vec![at(t, 1, back, 5000.0)]);
    assert_eq!(e, vec![Event::ClearedPrecontact(1)]);
}

#[test]
fn the_receivers_refuel_in_the_order_they_asked() {
    let mut t = tanker();
    assert_eq!(t.request(2), Event::ClearedPrecontact(2));
    assert_eq!(t.request(3), Event::StandBy(3));
    assert_eq!(t.station(3), Some(Station::Wing(OBSERVATION)));
    // A third waits further out on the left wing, in echelon.
    assert_eq!(t.request(4), Event::StandBy(4));
    assert_eq!(t.station(4), Some(Station::Wing([-23.0, -65.0, -6.0])));
    t.leave(4);
    let pre = t.precontact_body();
    let c = t.contact_body();
    let wing = |t: &Tanker| at(t, 3, OBSERVATION, 300.0);
    let mut e = run(&mut t, 2.5, |t| vec![at(t, 2, pre, 300.0), wing(t)]).0;
    e.extend(run(&mut t, 30.0, |t| vec![at(t, 2, c, 300.0 - t.given), wing(t)]).0);
    assert!(e.contains(&Event::Complete(2, 300.0)) || e.iter().any(|v| matches!(v, Event::Complete(2, _))), "{e:?}");
    assert_eq!(e.last(), Some(&Event::ClearedPrecontact(3)));
    assert_eq!(t.station(3), Some(Station::Receptacle(t.precontact_body())));
    // A receiver lost while first: the next is cleared.
    let mut t = tanker();
    t.request(2);
    t.request(3);
    let (e, _) = run(&mut t, 0.1, |t| vec![at(t, 3, OBSERVATION, 100.0)]);
    assert_eq!(e, vec![Event::ClearedPrecontact(3)]);
}

#[test]
fn the_door_closed_is_never_cleared_to_contact() {
    let mut t = tanker();
    t.request(1);
    let pre = t.precontact_body();
    let (e, _) = run(&mut t, 5.0, |t| vec![Receiver { door: false, ..at(t, 1, pre, 1000.0) }]);
    assert!(e.is_empty(), "{e:?}");
}

#[test]
fn a_receiver_leaving_in_contact_is_disconnected() {
    // The receiver leaves while the boom is in its receptacle (the player ejects, a wingman is called back): the boom
    // unlatches with a Disconnect (the AR lamp off, the DISC call), then the next is cleared (the statemachines audit,
    // #28).
    let mut t = tanker();
    t.request(1);
    t.request(2);
    let (pre, c) = (t.precontact_body(), t.contact_body());
    run(&mut t, 15.5, |t| vec![at(t, 1, pre, 1000.0)]);
    let mut x = 0.0;
    let (e, _) = run(&mut t, 30.0, |t| {
        x = (x + DT).min(15.0);
        vec![at(t, 1, [pre[0] + x, c[1], pre[2] + x * 3.0 / 15.0], 1000.0)]
    });
    assert!(e.contains(&Event::Contact(1)) && t.boom == Boom::Contact, "{e:?}");
    assert_eq!(t.leave(1), vec![Event::Disconnect(1), Event::ClearedPrecontact(2)]);
    assert_ne!(t.boom, Boom::Contact);
}

#[test]
fn a_first_receiver_that_never_comes_loses_its_turn() {
    // The first in the queue stays away (it turned to fight): after HEAD_WAIT_S the next one is cleared and the first
    // waits at the back (the statemachines audit, #28); alone, it keeps its turn.
    let mut t = tanker();
    t.request(1);
    let far = |t: &Tanker, id| at(t, id, [-3000.0, 0.0, 0.0], 1000.0);
    // Alone past HEAD_WAIT_S: its turn stands when a second asks; the timeout counts from then.
    let (e, _) = run(&mut t, iaf_ai::tanker::HEAD_WAIT_S + 10.0, |t| vec![far(t, 1)]);
    assert!(e.is_empty(), "{e:?}");
    t.request(2);
    let (e, _) = run(&mut t, 1.0, |t| vec![far(t, 1), far(t, 2)]);
    assert!(e.is_empty() && t.queue == vec![1, 2], "{e:?}");
    let (e, _) = run(&mut t, iaf_ai::tanker::HEAD_WAIT_S + 1.0, |t| vec![far(t, 1), far(t, 2)]);
    assert_eq!(e, vec![Event::StandBy(1), Event::ClearedPrecontact(2)]);
    assert_eq!(t.queue, vec![2, 1]);
    t.leave(1);
    let (e, _) = run(&mut t, 2.0 * iaf_ai::tanker::HEAD_WAIT_S, |t| vec![far(t, 2)]);
    assert!(e.is_empty() && t.queue == vec![2], "{e:?}");
}
