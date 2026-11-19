//! The flight lead layer (modern-iaf/docs/ai-plan.md §3, §6): a flight of up to four jets, its lead (promoted 1 → 3 →
//! 2 → 4 when lost), its shape and each wingman's slot, the start-up, the landing sequence, the radio commands, and
//! the calls (after the wingman's reaction time). The jets fly the autopilot's loops ([`apply`]); every figure here is
//! inferred unless a doc says otherwise.

use crate::bt::Node;
use crate::wingman;
use iaf_flight::Vec3;
use iaf_flight::airbase::Airbase;
use iaf_flight::aircraft::ApView;
use iaf_flight::autopilot::{self, Autopilot, Host, Leader, MODE_SLOT};
use iaf_flight::fm::Fm;

/// The decision tick, s (the slot loop runs at 0.1 s on its own).
pub const DECIDE_S: f64 = 0.5;
/// The fuel kept for the circuit and a second approach, kg: the minimum; below it a wingman goes home on its own.
pub const RESERVE_KG: f32 = 800.0;
/// The fuel to fly home at cruise, kg per km (the Sufa near 0.8 Mach at altitude, about 1.5 kg/km, rounded up).
pub const KG_PER_KM: f32 = 2.0;
/// Joker = bingo + this, kg.
pub const JOKER_KG: f32 = 1000.0;
/// The landing sequence: one wingman sent home this long after the one before, s.
pub const RELEASE_S: f64 = 20.0;
/// The landing sequence starts when the lead is airborne with the gear down this near the home base, m, or with the
/// gear down this low anywhere, m above the ground (or on the ground again).
const CIRCUIT_M: f64 = 20_000.0;
const LOW_M: f32 = 300.0;
/// The jet ahead in taxi order has moved this far from its spot: the next one taxies, m.
const MOVED_M: f64 = 150.0;
/// A wingman changing slots flies this much lower per number (#2 one step, #4 three) until it is over its new slot,
/// so paths that cross do not meet, m.
const TRANSIT_STEP: f32 = 35.0;
/// A wingman nearer another jet than the first steps down until clear of the second, m.
const CLEAR_M: (f64, f64) = (50.0, 60.0);
/// Collision avoidance: a jet whose closest approach to another within this time, s, comes nearer than this, m, pulls
/// away (`Autopilot::avoid`), checked every frame.
const AVOID_S: f64 = 4.0;
const AVOID_M: f64 = 60.0;
/// A slot is reached (the transit's end; "in position") within this, m.
const IN_POSITION_M: f32 = 50.0;
/// The index of "trail" in [`SHAPES`].
const TRAIL: usize = 5;
/// Who leads when the lead is lost: #3 is the deputy (ai-plan F6).
const PROMOTION: [u8; 4] = [1, 3, 2, 4];

/// The shapes: id, then the slots of #2, #3, #4 (forward, right, up m) relative to #1.
pub const SHAPES: [(&str, [[f32; 3]; 3]); 6] = [
    ("fingertip", [[-60.0, -60.0, 0.0], [-60.0, 60.0, 0.0], [-120.0, 120.0, 0.0]]),
    ("echelon_right", [[-60.0, 60.0, 0.0], [-120.0, 120.0, 0.0], [-180.0, 180.0, 0.0]]),
    ("echelon_left", [[-60.0, -60.0, 0.0], [-120.0, -120.0, 0.0], [-180.0, -180.0, 0.0]]),
    ("line_abreast", [[0.0, -1500.0, 0.0], [0.0, 1500.0, 0.0], [0.0, 3000.0, 0.0]]),
    ("wedge", [[-600.0, -1200.0, 0.0], [-600.0, 1200.0, 0.0], [-1200.0, 2400.0, 0.0]]),
    ("trail", [[-600.0, 0.0, 0.0], [-1200.0, 0.0, 0.0], [-1800.0, 0.0, 0.0]]),
];

/// A unit's skill (ai-plan X4). Wingmen take [`Skill::WINGMAN`]; the enemy's levels come later.
#[derive(Debug, Clone, Copy)]
pub struct Skill {
    /// From a cue to the answer, s.
    pub reaction_s: f64,
}

impl Skill {
    pub const WINGMAN: Skill = Skill { reaction_s: 1.0 };
}

/// A radio call: the caller's number and the call's id (the radio maps it to a voice clip and its lines).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Call {
    pub from: u8,
    pub id: &'static str,
}

/// What a member's autopilot is told this frame ([`apply`]).
#[derive(Debug, Clone, Copy, Default)]
pub struct Order {
    pub mode: Option<u8>,
    /// The taxi's jet ahead on the ground, else the flight lead.
    pub leader: Option<Leader>,
    pub slot: [f32; 3],
    /// Start the engine (once).
    pub start_engine: bool,
    /// The route's waypoint to go on from (once: a promoted lead takes the lost lead's).
    pub wp_index: Option<usize>,
    /// The direction to pull away in from a jet about to come too near (world, unit).
    pub avoid: Option<Vec3>,
}

/// One jet of the flight: what it is this frame ([`Flight::sense`]) and the AI's memory of it. The trees read and
/// write it.
pub struct Member {
    pub number: u8,
    /// Flown by the AI; false: the player.
    pub ai: bool,
    pub alive: bool,
    pub skill: Skill,
    pub v: ApView,
    pub mode: u8,
    /// TakeoffCL has ended in the air.
    pub airborne: bool,
    /// StopPlane has run.
    pub landed: bool,
    pub engine_on: bool,
    pub fuel_kg: f32,
    pub bingo_kg: f32,
    /// The current waypoint and its action (7: land).
    pub wp_index: usize,
    pub wp_action: i32,
    /// The slot (forward, right, up m) relative to the flight lead, and the distance to it, m.
    pub slot: [f32; 3],
    pub slot_error: f32,
    /// Wants to go home (ordered, the landing sequence, or its fuel); sent home by the flight ([`RELEASE_S`]).
    pub rtb: bool,
    pub released: bool,
    pub order: Order,
    // The decision's facts and the memory the trees use.
    pub(crate) now: f64,
    pub(crate) cleared: Option<f64>,
    pub(crate) ahead_moved: bool,
    pub(crate) start_sent: bool,
    pub(crate) taxi_go: bool,
    /// Joker, bingo called.
    pub(crate) called: [bool; 2],
    pub(crate) calls: Vec<&'static str>,
    spot: Vec3,
    pub(crate) transit: bool,
    report: bool,
    /// The lead is low with the gear down, or on the ground again: no slot to keep on it.
    pub(crate) lead_low: bool,
}

/// The flight.
pub struct Flight {
    pub members: Vec<Member>,
    /// The index of the flight lead in `members`.
    lead: usize,
    shape: usize,
    /// The home base's lineup (bingo's distance, the landing sequence).
    home: Option<Vec3>,
    cleared: Option<f64>,
    next: f64,
    lead_gear_up: bool,
    last_release: f64,
    calls: Vec<(f64, Call)>,
    wingman: Node<Member>,
    lead_tree: Node<Member>,
}

impl Default for Flight {
    fn default() -> Self {
        Flight {
            members: Vec::new(),
            lead: 0,
            shape: 0,
            home: None,
            cleared: None,
            next: 0.0,
            lead_gear_up: false,
            last_release: f64::MIN,
            calls: Vec::new(),
            wingman: wingman::wingman(),
            lead_tree: wingman::lead(),
        }
    }
}

fn leader_of(m: &Member) -> Leader {
    let a = m.v.att;
    Leader { pos: m.v.pos, vel: m.v.vel, att: [a.pitch, a.roll, a.heading], active: m.alive }
}

fn flat(a: Vec3, b: Vec3) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}

impl Flight {
    /// Adds jet `number` (1..4; `ai` false: the player). The first one names the home base: the base nearest its
    /// route's last waypoint (else itself). A jet on the ground at a hangar takes it as its home hangar
    /// (`Autopilot::home_hangar`).
    pub fn add(&mut self, number: u8, ai: bool, fm: &Fm, ap: &mut Autopilot) {
        let v = fm.ap_view();
        let p = ap.route.last().map_or(v.pos, |w| Vec3::new(w.x, w.y, w.z));
        if let Some(b) = Airbase::nearest(&ap.bases, [p[0] as f32, p[1] as f32, p[2] as f32]) {
            self.home.get_or_insert(Vec3::new(b.lineup[0] as f64, b.lineup[1] as f64, b.lineup[2] as f64));
        }
        if v.on_ground {
            let (x, y) = (v.pos[0] as f32, v.pos[1] as f32);
            ap.home_hangar = ap.bases.iter().enumerate().find_map(|(i, b)| b.hangar_near(x, y).map(|h| (i, h)));
        }
        self.members.push(Member {
            number,
            ai,
            alive: true,
            skill: Skill::WINGMAN,
            v,
            mode: ap.mode(),
            airborne: !v.on_ground,
            landed: false,
            engine_on: fm.engine_on(),
            fuel_kg: fm.state().fuel_kg,
            bingo_kg: RESERVE_KG,
            wp_index: ap.wp_index,
            wp_action: 0,
            slot: [0.0; 3],
            slot_error: 0.0,
            rtb: false,
            released: false,
            order: Order::default(),
            now: 0.0,
            cleared: None,
            ahead_moved: false,
            start_sent: false,
            taxi_go: false,
            called: [false; 2],
            calls: Vec::new(),
            spot: v.pos,
            transit: false,
            report: false,
            lead_low: false,
        });
        self.members.sort_by_key(|m| m.number);
        self.lead = 0;
    }

    pub fn member(&self, number: u8) -> Option<&Member> {
        self.members.iter().find(|m| m.number == number)
    }

    fn index(&self, number: u8) -> Option<usize> {
        self.members.iter().position(|m| m.number == number)
    }

    /// The flight lead's number.
    pub fn lead(&self) -> u8 {
        self.members.get(self.lead).map_or(0, |m| m.number)
    }

    /// Jet `number` this frame: alive (the host's word; a crash counts as dead), its flight model and autopilot.
    pub fn sense(&mut self, number: u8, alive: bool, fm: &Fm, ap: &Autopilot) {
        let Some(i) = self.index(number) else { return };
        let m = &mut self.members[i];
        let s = fm.state();
        m.alive = alive && s.crashed.is_none();
        m.v = fm.ap_view();
        m.mode = ap.mode();
        // An AI jet: TakeoffCL ended (or it started in the air); the player: off the ground once.
        m.airborne = if m.ai { ap.airborne || m.airborne && !m.v.on_ground } else { m.airborne || !m.v.on_ground };
        m.landed = ap.landed;
        m.engine_on = fm.engine_on();
        m.fuel_kg = s.fuel_kg;
        m.wp_index = ap.wp_index;
        m.wp_action = ap.route.get(ap.wp_index).map_or(0, |w| w.action);
    }

    /// The tower's start-up clearance: the wingmen start their engines, one after the other.
    pub fn start_up(&mut self, now: f64) {
        self.cleared.get_or_insert(now);
    }

    /// A radio command (design §4) to `to`: 0 the flight, 5 the element (#3, #4), 2..4 one wingman. Returns false for
    /// an unknown command or nobody to take it; the answers come as calls.
    pub fn command(&mut self, now: f64, to: u8, cmd: &str) -> bool {
        let lead = self.lead;
        let who: Vec<usize> = (0..self.members.len())
            .filter(|&i| {
                let m = &self.members[i];
                i != lead && m.ai && m.alive && (to == 0 || m.number == to || to == 5 && m.number >= 3)
            })
            .collect();
        if who.is_empty() {
            return false;
        }
        let shape = SHAPES.iter().position(|s| s.0 == cmd);
        let mut acked = false;
        for &i in &who {
            let m = &mut self.members[i];
            let flying = m.airborne && !m.landed;
            let answer = match cmd {
                "check" => "ack",
                "ops_check" => "fuel_state",
                _ if shape.is_some() => {
                    if to == 0 && flying {
                        "ack"
                    } else {
                        "unable"
                    }
                }
                // Once in its landing pattern (the gear down), a jet sent home lands.
                "rejoin" if flying && !(m.released && m.v.gear_down) => {
                    (m.rtb, m.released, m.transit, m.report) = (false, false, true, true);
                    "ack"
                }
                "rtb" if flying => {
                    m.rtb = true;
                    "ack"
                }
                "rejoin" | "rtb" => "unable",
                _ => return false,
            };
            acked |= answer == "ack";
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: answer }));
        }
        if let Some(s) = shape.filter(|_| acked) {
            self.shape = s;
            for m in self.members.iter_mut().filter(|m| m.airborne && !m.landed) {
                (m.transit, m.report) = (true, true);
            }
        }
        true
    }

    /// One frame: the decisions every [`DECIDE_S`], each member's order (its leader and slot every frame); returns
    /// the calls now due.
    pub fn step(&mut self, now: f64) -> Vec<Call> {
        if self.members.is_empty() {
            return Vec::new();
        }
        for m in &mut self.members {
            m.order.start_engine = false;
            m.order.wp_index = None;
        }
        if now >= self.next {
            self.next = now + DECIDE_S;
            self.decide(now);
        }
        self.feed();
        let (due, later) = std::mem::take(&mut self.calls).into_iter().partition(|(t, _)| *t <= now);
        self.calls = later;
        due.into_iter().map(|(_, c)| c).collect::<Vec<_>>()
    }

    fn decide(&mut self, now: f64) {
        // Promotion: the new lead goes on along the route from the lost lead's waypoint.
        if !self.members[self.lead].alive
            && let Some(i) = PROMOTION.iter().filter_map(|&n| self.index(n)).find(|&i| self.members[i].alive)
        {
            let wp = self.members[self.lead].wp_index;
            self.lead = i;
            // "The gear up once" is the new lead's to show while it is on the ground (it starts no landing sequence).
            if self.members[i].v.on_ground {
                self.lead_gear_up = false;
            }
            let m = &mut self.members[i];
            m.order.wp_index = Some(wp);
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: "lead_change" }));
            for m in self.members.iter_mut().filter(|m| m.airborne) {
                m.transit = true;
            }
        }
        let lead = &self.members[self.lead];
        let lead_n = lead.number;
        let ld = leader_of(lead);
        // The landing sequence: the lead in the circuit (the gear down again near home, or low anywhere, or on the
        // ground again), or an RTB to the flight. (Starting it when the lead came back within 20 km sent the
        // wingmen home at once, and the circuit's speeds brought #2 and #3 onto the runway 0.3 s apart.)
        let low = lead.v.on_ground || lead.v.gear_down && lead.v.pos[2] as f32 - lead.v.ground_height < LOW_M;
        let lead_low = lead.alive && self.lead_gear_up && low;
        if lead.alive {
            let near = self.home.is_some_and(|h| flat(h, lead.v.pos) < CIRCUIT_M);
            if !lead.v.gear_down && !lead.v.on_ground {
                self.lead_gear_up = true;
            } else if self.lead_gear_up && (near || low) {
                // The wingmen not yet sent home wait in trail, stepped down: no slot is held in the circuit's tight
                // turns (in fingertip #3 came within 18.8 m of the lead there).
                self.shape = TRAIL;
                for m in self.members.iter_mut().filter(|m| m.number != lead_n && m.airborne) {
                    m.rtb = true;
                    m.transit |= !m.released;
                }
            }
        }
        // Send home the first that wants to go, one per RELEASE_S.
        if now >= self.last_release + RELEASE_S
            && let Some(m) = self.members.iter_mut().find(|m| m.alive && m.rtb && !m.released && m.number != lead_n)
        {
            m.released = true;
            self.last_release = now;
        }
        let base = SHAPES[self.shape].1;
        let table = |n: u8| if (2..=4).contains(&n) { base[n as usize - 2] } else { [0.0; 3] };
        let lead_slot = table(lead_n);
        let home = self.home;
        for i in 0..self.members.len() {
            let ahead_moved = (0..i)
                .rev()
                .map(|j| &self.members[j])
                .find(|a| a.alive)
                .is_none_or(|a| flat(a.v.pos, a.spot) > MOVED_M);
            // The nearest other jet in the air, m.
            let me = &self.members[i];
            let nearest = (self.members.iter())
                .filter(|o| o.number != me.number && o.alive && !o.v.on_ground && !me.v.on_ground)
                .map(|o| o.v.pos.distance(me.v.pos))
                .fold(f64::MAX, f64::min);
            let m = &mut self.members[i];
            let t = table(m.number);
            m.slot = [t[0] - lead_slot[0], t[1] - lead_slot[1], t[2] - lead_slot[2]];
            if i != self.lead {
                let s = autopilot::slot_point(&ld, m.slot);
                let flat_err = flat(s, m.v.pos) as f32;
                m.slot_error = s.distance(m.v.pos) as f32;
                // Too near another jet: step down as in a change of slots (the higher number gives way: its step is
                // the larger), until in its slot and clear.
                if nearest < CLEAR_M.0 && m.mode == MODE_SLOT {
                    m.transit = true;
                } else if m.transit && flat_err < IN_POSITION_M && nearest > CLEAR_M.1 {
                    m.transit = false;
                }
                if m.report && !m.transit && m.slot_error < IN_POSITION_M && m.mode == MODE_SLOT {
                    m.report = false;
                    m.calls.push("in_position");
                }
            }
            if !m.ai {
                continue;
            }
            m.now = now;
            m.lead_low = lead_low;
            m.cleared = self.cleared;
            m.ahead_moved = ahead_moved;
            m.bingo_kg = RESERVE_KG + KG_PER_KM * home.map_or(0.0, |h| flat(h, m.v.pos) as f32 / 1000.0);
            m.order.mode = None;
            if i == self.lead {
                self.lead_tree.tick(m)
            } else {
                self.wingman.tick(m)
            };
            for id in m.calls.drain(..) {
                self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id }));
            }
        }
    }

    /// Each AI jet's leader this frame: on the ground the jet ahead in taxi order (TaxiCL's spacing, TakeoffCL's
    /// stream), in the air the flight lead; its slot, stepped down during a change of slots.
    fn feed(&mut self) {
        let ld = leader_of(&self.members[self.lead]);
        for i in 0..self.members.len() {
            self.members[i].order.avoid = self.avoid(i);
            let ahead = (0..i).rev().map(|j| &self.members[j]).find(|a| a.alive).map(leader_of);
            let m = &mut self.members[i];
            let ground = m.v.on_ground && !m.airborne || m.mode == 9 && !m.airborne;
            m.order.leader = if ground { ahead } else { Some(ld) };
            m.order.slot = m.slot;
            if m.transit {
                m.order.slot[2] -= TRANSIT_STEP * (m.number as f32 - 1.0);
            }
        }
    }
}

impl Flight {
    /// Member `i`, an AI jet in the air: the way away from the jet it comes nearest to within [`AVOID_S`], when that is
    /// nearer than [`AVOID_M`] (straight at it: the higher number goes down).
    fn avoid(&self, i: usize) -> Option<Vec3> {
        let me = &self.members[i];
        if !me.ai || !me.alive || me.v.on_ground {
            return None;
        }
        let (miss, other) = (self.members.iter())
            .filter(|o| o.number != me.number && o.alive && !o.v.on_ground)
            .map(|o| {
                let (dp, dv) = (o.v.pos - me.v.pos, o.v.vel - me.v.vel);
                let t = (-dp.dot(dv) / dv.dot(dv).max(1e-6)).clamp(0.0, AVOID_S);
                (dp + dv * t, o.number)
            })
            .min_by(|a, b| a.0.length().total_cmp(&b.0.length()))?;
        if miss.length() >= AVOID_M {
            return None;
        }
        let down = if me.number > other { -1.0 } else { 1.0 };
        Some((-miss).try_normalize().unwrap_or(Vec3::UP * down))
    }
}

/// A member's order to its autopilot and flight model (the tests and the Godot class alike).
pub fn apply(o: &Order, ap: &mut Autopilot, fm: &mut Fm) {
    ap.leader = o.leader;
    ap.slot = o.slot;
    ap.avoid = o.avoid;
    if let Some(i) = o.wp_index {
        ap.wp_index = i;
    }
    if o.start_engine {
        fm.start_engine();
    }
    if let Some(mode) = o.mode {
        ap.set_mode(fm, mode);
    }
}
