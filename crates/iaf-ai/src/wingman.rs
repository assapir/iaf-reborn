//! The trees of the flight's AI jets (design: modern-iaf/docs/ai-plan.md §6): the wingman's, and the AI flight lead's
//! after a promotion. Each is ticked on its [`Member`] every decision ([`crate::flight::DECIDE_S`]); its actions set the
//! member's order and queue its radio calls.

use crate::bt::Node::{self, *};
use crate::bt::Status;
use crate::flight::{Member, RESERVE_KG, Tactic, defend};
use crate::{bfm, fighter, strike};
use iaf_flight::autopilot::{MODE_SLOT, MODE_STEER};

/// Inferred: each wingman starts its engine this long after the one before it (#2 this long after the clearance).
pub const START_STEP_S: f64 = 3.0;

pub(crate) fn idle(_: &mut Member) -> Status {
    Status::Running
}

pub(crate) fn set_mode(m: &mut Member, mode: u8) -> Status {
    m.order.mode = Some(mode);
    Status::Running
}

/// Cleared by the tower: the engine start at its turn.
fn start_engine(m: &mut Member) -> Status {
    if let Some(t) = m.cleared
        && !m.start_sent
        && m.now >= t + START_STEP_S * (m.number as f64 - 1.0)
    {
        m.start_sent = true;
        m.order.start_engine = true;
    }
    Status::Running
}

/// Mode 9: TaxiCL behind the jet ahead (its leader), TakeoffCL's stream take-off.
fn taxi(m: &mut Member) -> Status {
    m.taxi_go = true;
    set_mode(m, 9)
}

/// Joker and bingo, once each (a side effect: the tree goes on).
fn fuel_calls(m: &mut Member) -> Status {
    if m.fuel_kg <= m.bingo_kg && !m.called[1] {
        m.called = [true, true];
        m.calls.push("bingo");
    } else if m.fuel_kg <= m.bingo_kg + crate::flight::JOKER_KG && !m.called[0] {
        m.called[0] = true;
        m.calls.push("joker");
    }
    Status::Failure
}

/// Below the reserve: home on its own (the flight releases it, [`crate::flight::RELEASE_S`] after the one before).
fn rtb_own(m: &mut Member) -> Status {
    if !m.rtb {
        m.rtb = true;
        m.calls.push("rtb");
    }
    Status::Failure
}

/// The slot on the flight lead; a join-up (from the take-off or the way home) comes in stepped down and calls "in
/// position" there, as a change of slots does.
pub(crate) fn keep_slot(m: &mut Member) -> Status {
    if m.mode != MODE_SLOT {
        (m.transit, m.report) = (true, true);
    }
    set_mode(m, MODE_SLOT)
}

/// Element 2's lead while split: to its task's point and round it ([`crate::Flight::split`]).
pub(crate) fn fly_task(m: &mut Member) -> Status {
    m.order.steer = m.task;
    set_mode(m, MODE_STEER)
}

/// In the air with the gear up: a threat on it is answered ([`defend`]).
pub(crate) fn flying(m: &Member) -> bool {
    m.airborne && !m.v.on_ground && !m.v.gear_down
}

/// On the ground before its take-off: the engine at its turn after the clearance, the taxi once the jet ahead has
/// moved, TaxiCL and TakeoffCL until airborne.
pub(crate) fn before_takeoff() -> Node<Member> {
    Sel(vec![
        Seq(vec![
            Cond(|m| m.v.on_ground && !m.airborne),
            Sel(vec![
                Seq(vec![Cond(|m| !m.engine_on), Act(start_engine)]),
                Seq(vec![Cond(|m| m.ahead_moved || m.taxi_go), Act(taxi)]),
                Act(idle),
            ]),
        ]),
        Seq(vec![Cond(|m| m.mode == 9 && !m.airborne), Act(idle)]),
    ])
}

/// A threat on it: in the fight the enemy fighters' defence ([`fighter::evade`]: a lock called but no stop to the
/// attack, a missile defended by the tactics), in the shape the wingmen's ([`defend`]).
fn guard(m: &mut Member) -> Status {
    if m.enemy.committed { fighter::evade(m) } else { defend(m) }
}

/// The fight's way in: the enemy fighters' intercept (the collision course, the crank while its missile flies). It
/// ends (fails) with the foe lost or past [`fighter::ABORT_M`] of the flight lead, or with nothing left to shoot and
/// none of its missiles flying: then "winchester", the lead's order over; back to the slot ("in position").
fn press(m: &mut Member) -> Status {
    if fighter::intercept(m) == Status::Running {
        return Status::Running;
    }
    if !m.enemy.armed && !m.enemy.in_air && !m.winchester {
        (m.winchester, m.tactic, m.assigned, m.holding, m.bandit) = (true, Tactic::None, None, false, None);
        m.calls.push("winchester");
    }
    // (Back to the slot once: a foe held but not found leaves it in the slot, with no call each decision.)
    if m.mode != MODE_SLOT {
        (m.transit, m.report) = (true, true);
    }
    Status::Failure
}

/// The wingman (design §2).
pub fn wingman() -> Node<Member> {
    Sel(vec![
        Seq(vec![Cond(|m| !m.alive), Act(idle)]),
        // Parked: ParkInHangar has stopped the engine.
        Seq(vec![Cond(|m| m.landed && !m.engine_on), Act(idle)]),
        Seq(vec![Cond(flying), Act(guard)]),
        Seq(vec![Cond(|m| m.mode == 8 && m.released), Act(idle)]),
        before_takeoff(),
        Act(fuel_calls),
        Seq(vec![Cond(|m| m.fuel_kg <= RESERVE_KG), Act(rtb_own)]),
        Seq(vec![Cond(|m| m.released), Act(|m| set_mode(m, 8))]),
        // Its turn to go home not come yet, with no lead in the air to keep a slot on: the Hold (mode 10) where it is.
        Seq(vec![Cond(|m| m.rtb && m.lead_low), Act(|m| set_mode(m, 10))]),
        // In the fight (a foe, Flight::decide): the enemy fighters' shot, dogfight and intercept.
        Seq(vec![
            Cond(|m| m.enemy.committed),
            Sel(vec![Act(fighter::shoot), Seq(vec![Cond(bfm::fighting), Act(bfm::fight)]), Act(press)]),
        ]),
        // On the tanker's station (tanker.rs): the slot loop on the tanker.
        Seq(vec![Cond(|m| m.refuelling && m.refuel.is_some() && flying(m)), Act(|m| set_mode(m, MODE_SLOT))]),
        // Its air-to-ground attack (strike.rs): the slot until its turn, then the run, the egress and the rejoin.
        Seq(vec![Cond(strike::striking), Act(strike::fly)]),
        Seq(vec![Cond(|m| m.task.is_some()), Act(fly_task)]),
        Act(keep_slot),
    ])
}

/// An AI flight lead (after a promotion): the route (mode 7), then home (mode 8) at its landing waypoint, on an RTB
/// or below the reserve; a threat on it is answered as a wingman's; an attack it has (strike.rs) before the route.
pub fn lead() -> Node<Member> {
    Sel(vec![
        Seq(vec![Cond(|m| !m.alive), Act(idle)]),
        Seq(vec![Cond(|m| m.landed && !m.engine_on), Act(idle)]),
        Seq(vec![Cond(flying), Act(defend)]),
        Seq(vec![Cond(|m| m.mode == 8), Act(idle)]),
        Seq(vec![Cond(|m| m.v.on_ground && !m.airborne), Act(idle)]),
        Act(fuel_calls),
        Seq(vec![Cond(|m| m.rtb || m.fuel_kg <= RESERVE_KG || m.wp_action == 7), Act(|m| set_mode(m, 8))]),
        Seq(vec![Cond(strike::striking), Act(strike::fly)]),
        Act(|m| set_mode(m, 7)),
    ])
}
