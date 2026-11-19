//! `IafAi`: Modern IAF's flight AI (`iaf_ai`, modern-iaf/docs/ai-plan.md §6) for one flight of up to four `IafFlight`
//! jets. Each frame, before the jets' `ap_step` and `step`, `step` reads every jet's flight model and autopilot and
//! sets the AI jets' autopilot (mode, leader, slot, engine start); the player's jet is read only but for its home
//! hangar (`add_member`).

use godot::prelude::*;
use iaf_ai::Flight;

use crate::flight::IafFlight;

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

    /// One frame at `now` (s), before the jets' `ap_step`: the AI's decisions and orders. Returns the calls due, each
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

    /// Jet `number` for tests and logs: role (lead / wingman), stage (its control loop), slot_error (m), fuel_kg,
    /// bingo_kg, released (sent home); empty for an unknown number.
    #[func]
    fn state(&self, number: i64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(m) = self.flight.member(number.clamp(0, 255) as u8) else { return d };
        d.set("role", if m.number == self.flight.lead() { "lead" } else { "wingman" });
        if let Some((_, jet, _)) = self.jets.iter().find(|j| j.0 == m.number) {
            d.set("stage", &jet.bind().ap_stage());
        }
        d.set("slot_error", m.slot_error);
        d.set("fuel_kg", m.fuel_kg);
        d.set("bingo_kg", m.bingo_kg);
        d.set("released", m.released);
        d
    }
}
