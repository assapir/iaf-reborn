//! The flight lead layer (modern-iaf/docs/ai-plan.md §3, §6): a flight of up to four jets in two elements (#2 on #1,
//! #4 on #3), its lead (promoted 1 → 3 → 2 → 4 when lost), its shape and each wingman's slot, the split and the
//! regroup, the start-up, the landing sequence, the radio commands, the threats on each jet and the AWACS calls, and
//! the calls (after the wingman's reaction time). The jets fly the autopilot's loops ([`apply`]); every figure here is
//! inferred unless a doc says otherwise.

use crate::bfm;
use crate::bt::{Node, Status};
use crate::fighter::{self, Bogey, Enemy};
use crate::skill::Skill;
use crate::wingman;
use iaf_flight::Vec3;
use iaf_flight::airbase::Airbase;
use iaf_flight::aircraft::ApView;
use iaf_flight::aircraft::MILITARY;
use iaf_flight::autopilot::{self, Autopilot, Host, Leader, MODE_SLOT, Steer};
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
const AVOID_STEP_S: f64 = 0.25;
/// A jet's acceleration is smoothed over this, s (the frames' velocity steps are rough).
const ACC_S: f64 = 0.3;
/// Once pulling away, it goes on until the closest approach is this far, m (inferred: a pull that stopped at
/// [`AVOID_M`] left two AI jets 37 m apart, and an AI jet 13 m from the player's, who does not pull).
const AVOID_CLEAR_M: f64 = 100.0;
/// A slot is reached (the transit's end; "in position") within this, m.
const IN_POSITION_M: f32 = 50.0;
/// The indices of "line_abreast" and "trail" in [`SHAPES`].
const LINE_ABREAST: usize = 1;
const TRAIL: usize = 2;
/// Who leads when the lead is lost: #3 is the deputy (ai-plan F6).
const PROMOTION: [u8; 4] = [1, 3, 2, 4];
/// A split's point farther than this from the flight lead is refused: the elements' targets are in one area, m.
pub const SAME_AREA_M: f64 = 40_000.0;
/// The split element's turns, g (a 48° bank: #4 keeps its slot on #3 round the circle).
const TASK_G: f32 = 1.5;
/// The defensive turn's load factor against a lock and against a missile; its speed, m/s; how long a jet stays clear
/// before it rejoins, s.
const DEFEND_G: (f32, f32) = (4.0, 6.5);
const DEFEND_SPEED: f32 = 260.0;
const CLEAR_S: f64 = 5.0;
/// An engage ([`Flight::engage`]): the turn's load factor and the speed to the target, m/s (inferred: a hard turn at
/// about 0.85 Mach at altitude).
const ENGAGE_G: f32 = 4.0;
const ENGAGE_SPEED: f32 = 280.0;
/// The far rejoin: a wingman in the air farther than `.0` m from its slot flies at the slot point (the steer loop, at
/// `.2` g and its leader's speed plus `.3` m/s, at least [`DEFEND_SPEED`]) until nearer than `.1` m, then the slot
/// loop. The slot loop's capped
/// spring only matches the leader's velocity that far out: on a lead circling at 30° of bank, wingmen 17 km off flew
/// a parallel circle for ten minutes (test_four_ship, 20 Nov 2026; inferred figures).
const REJOIN: (f32, f32, f32, f32) = (6_000.0, 3_000.0, 3.0, 60.0);
/// An AI jet reports an AWACS contact inside its radar's reach, m, and this far off its nose, deg (a fighter radar's
/// 40 NM and ±60°).
const RADAR: (f64, f64) = (74_000.0, 60.0);

/// The shapes, the gallery of Hebrew Wikipedia's "טיסת מבנה" (echelon both ways; not the missing man): id, then the
/// slots of #2, #3, #4 (forward, right, up m) relative to #1. The spacing is inferred: any two jets at least 84 m
/// apart (60 m is the step-down and pull-away distance, [`CLEAR_M`], [`AVOID_M`]); the vic deeper than the
/// fingertip, as in the gallery; the delta #1 ahead of the three abreast; the diamond #4 behind #1 (docs/ai.md §8.7).
pub const SHAPES: [(&str, [[f32; 3]; 3]); 8] = [
    ("fingertip", [[-60.0, -60.0, 0.0], [-60.0, 60.0, 0.0], [-120.0, 120.0, 0.0]]),
    ("line_abreast", [[0.0, -1500.0, 0.0], [0.0, 1500.0, 0.0], [0.0, 3000.0, 0.0]]),
    ("trail", [[-600.0, 0.0, 0.0], [-1200.0, 0.0, 0.0], [-1800.0, 0.0, 0.0]]),
    ("echelon_right", [[-60.0, 60.0, 0.0], [-120.0, 120.0, 0.0], [-180.0, 180.0, 0.0]]),
    ("echelon_left", [[-60.0, -60.0, 0.0], [-120.0, -120.0, 0.0], [-180.0, -180.0, 0.0]]),
    ("diamond", [[-60.0, -60.0, 0.0], [-60.0, 60.0, 0.0], [-120.0, 0.0, 0.0]]),
    ("vic", [[-90.0, -45.0, 0.0], [-90.0, 45.0, 0.0], [-180.0, 90.0, 0.0]]),
    ("delta", [[-120.0, -120.0, 0.0], [-120.0, 120.0, 0.0], [-120.0, 0.0, 0.0]]),
];

/// What a jet's RWR and MAW show on it ([`Flight::threat`], the host's): a radar locked on it or a missile flying at
/// it, at `pos`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Threat {
    pub pos: Vec3,
    /// A missile (else a lock).
    pub launch: bool,
    /// An infrared missile (flares; else chaff).
    pub ir: bool,
    /// The lock's radar is on the ground.
    pub ground: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decoy {
    Chaff,
    Flare,
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
    /// The steer loop's order (the split's task, the defensive turn).
    pub steer: Option<Steer>,
    /// A decoy to release now (the host's release path and decoy rule; one each 4 s at most, combat.gd).
    pub decoy: Option<Decoy>,
    /// An enemy fighter: its missile at the bogey now (the host's launch, combat.gd).
    pub shoot: bool,
    /// An enemy fighter in the dogfight: a gun burst at the bogey now (the host's launch, combat.gd).
    pub gun: bool,
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
    /// The 6-DoF's corner speed now, m/s (`Fm::corner_speed`; None on the original model): the dogfight's turn.
    pub corner: Option<f32>,
    /// Its acceleration, m/s² (from the frames' velocities, smoothed over [`ACC_S`]): the turn and the throttle.
    acc: Vec3,
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
    /// Calls "in position" once in its slot: armed by a join-up or a command.
    pub(crate) report: bool,
    /// Flying the far rejoin ([`REJOIN`]) this decision.
    pub(crate) rejoining: bool,
    /// Pulling away from a jet ([`AVOID_CLEAR_M`]).
    avoiding: bool,
    /// The lead is low with the gear down, or on the ground again: no slot to keep on it.
    pub(crate) lead_low: bool,
    /// The threat on it this frame ([`Flight::threat`]); when it was first seen, the level called (1 a lock, 2 a
    /// launch), its mate's break called, defending, clear since.
    pub threat: Option<Threat>,
    pub(crate) cue: Option<f64>,
    pub(crate) called_level: u8,
    mate_called: bool,
    pub defending: bool,
    pub(crate) clear_since: Option<f64>,
    /// Element 2's lead while split, or a jet engaging: its task ([`Flight::split`], [`Flight::engage`]).
    pub task: Option<Steer>,
    /// Engages the player's target ([`Flight::engage`]).
    pub engaging: bool,
    /// An enemy fighter's facts and memory ([`Flight::enemy`]).
    pub enemy: Enemy,
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
    /// Element 2's task while split.
    split: Option<Steer>,
    /// The target the engaging jets fly at ([`Flight::engage`], [`Flight::target`]).
    target: Option<Vec3>,
    wingman: Node<Member>,
    lead_tree: Node<Member>,
    /// An enemy pair ([`Flight::enemy`]): its station; the ground's vector and the bogey as it is ([`Flight::bogey`]).
    station: Option<Vec3>,
    gci: Option<Bogey>,
    truth: Option<Bogey>,
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
            split: None,
            target: None,
            wingman: wingman::wingman(),
            lead_tree: wingman::lead(),
            station: None,
            gci: None,
            truth: None,
        }
    }
}

/// `m` as a leader, as sensed: every jet at one instant ([`Flight::sense`]).
fn leader_of(m: &Member) -> Leader {
    let a = m.v.att;
    Leader { pos: m.v.pos, vel: m.v.vel, att: [a.pitch, a.roll, a.heading], active: m.alive }
}

fn flat(a: Vec3, b: Vec3) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}

/// `at` inside `m`'s radar's reach and cone ([`RADAR`]).
fn in_radar(m: &Member, at: Vec3) -> bool {
    let (d, v) = (at - m.v.pos, m.v.vel);
    let off = (v[0] * d[1] - v[1] * d[0]).atan2(v[0] * d[0] + v[1] * d[1]).abs().to_degrees();
    flat(at, m.v.pos) < RADAR.0 && off < RADAR.1
}

/// `at` in `m`'s pilot's sight: inside [`bfm::VISUAL_M`], not in the blind cone behind its tail ([`bfm::BLIND_DEG`]).
fn in_sight(m: &Member, at: Vec3) -> bool {
    let d = at - m.v.pos;
    let tail = (-m.v.vel).try_normalize().unwrap_or(Vec3::NORTH);
    d.length() < bfm::VISUAL_M && d.dot(tail) < d.length() * bfm::BLIND_DEG.to_radians().cos()
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
        if ai {
            // A wingman taxies once the jet ahead has moved, not at its route's planned time (TaxiCL holds for wp0's).
            ap.release_takeoff(0.0);
        }
        self.members.push(Member {
            number,
            ai,
            alive: true,
            skill: Skill::WINGMAN,
            v,
            corner: None,
            acc: Vec3::ZERO,
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
            rejoining: false,
            avoiding: false,
            lead_low: false,
            threat: None,
            cue: None,
            called_level: 0,
            mate_called: false,
            defending: false,
            clear_since: None,
            task: None,
            engaging: false,
            enemy: Enemy::default(),
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

    /// Whom member `i` flies on in the air: #2 on #1 and #4 on #3, its element lead, while that one flies on its own
    /// (alive, in the air, not sent home, off the slot loop: the split's task, a defence; not the far rejoin, where each
    /// flies at its own slot); else the flight lead, with its slot in the shape relative to its element lead's slot.
    /// (Flown on #3 itself also in the shape, #4 amplified #3's corrections: 385 m off in a change of shape, 632 m in a
    /// join-up in a turn; tested and dropped 19 Nov.)
    fn leader_index(&self, i: usize) -> usize {
        let n = self.members[i].number;
        let el = n.is_multiple_of(2).then(|| self.index(n - 1)).flatten().filter(|&j| {
            let e = &self.members[j];
            let off = e.mode != MODE_SLOT && !e.rejoining;
            j != self.lead && e.alive && e.airborne && !e.landed && !e.released && !e.v.on_ground && off
        });
        el.unwrap_or(self.lead)
    }

    /// The number of the jet `number` flies on in the air (0: none, or it leads).
    pub fn leader(&self, number: u8) -> u8 {
        match self.index(number) {
            Some(i) if i != self.lead => self.members[self.leader_index(i)].number,
            _ => 0,
        }
    }

    /// The threat on jet `number` this frame (its RWR's lock, its MAW's missile; None: clear), for the reactions.
    pub fn threat(&mut self, number: u8, t: Option<Threat>) {
        if let Some(i) = self.index(number) {
            self.members[i].threat = t;
        }
    }

    /// The lead's split (ai-plan F12): element 2 (#3, #4 on it) takes its own task at `at`, its target in the same
    /// area (within [`SAME_AREA_M`] of the flight lead): it flies there at its present height and the lead's speed and
    /// circles it until a regroup (`command` "regroup"); the flight stays one (one route, one landing sequence, the
    /// threats and calls). False: no AI #3 in the air with the flight to take it. #3 and #4 answer (unable: too far).
    pub fn split(&mut self, now: f64, at: Vec3) -> bool {
        let Some(k) = self.index(3).filter(|&k| {
            let m = &self.members[k];
            k != self.lead && m.ai && m.alive && m.airborne && !m.landed && !m.rtb
        }) else {
            return false;
        };
        let lead = &self.members[self.lead];
        let ok = flat(at, lead.v.pos) <= SAME_AREA_M;
        if ok {
            let to = Vec3::new(at[0], at[1], self.members[k].v.pos[2]);
            self.split = Some(Steer { to, g: TASK_G, speed: lead.v.speed.max(200.0), thr_max: 1.0, fighter: false });
        }
        for m in self.members.iter().filter(|m| m.number >= 3 && m.ai && m.alive) {
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: if ok { "ack" } else { "unable" } }));
        }
        true
    }

    /// The lead's "engage my target" at `now` to `to` (0 the flight, 5 the element, 2..4 one wingman): each AI jet
    /// addressed in the air leaves its slot and flies at the target `at` (the host's radar lock, kept fresh by
    /// [`Flight::target`]) for the host's weapons to fire; #4 stays on #3 when #3 engages too. `at` None (no target
    /// to engage) or a jet not flying: "unable". Some(true): a jet took it; Some(false): each answered "unable" (a jet
    /// already engaging keeps its target); None: nobody to take it.
    pub fn engage(&mut self, now: f64, to: u8, at: Option<Vec3>) -> Option<bool> {
        let lead = self.lead;
        let takes = |m: &Member| m.ai && m.alive && (to == 0 || m.number == to || to == 5 && m.number >= 3);
        let who: Vec<usize> = (0..self.members.len()).filter(|&i| i != lead && takes(&self.members[i])).collect();
        if who.is_empty() {
            return None;
        }
        let can = |m: &Member| at.is_some() && m.airborne && !m.landed && !m.rtb && !m.released;
        let with_three = to != 4 && who.iter().any(|&i| self.members[i].number == 3 && can(&self.members[i]));
        let mut took = false;
        for &i in &who {
            let ok = can(&self.members[i]);
            let m = &mut self.members[i];
            if ok && !(with_three && m.number == 4) {
                (m.engaging, took) = (true, true);
            }
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: if ok { "ack" } else { "unable" } }));
        }
        if took {
            self.target = at;
        }
        Some(took)
    }

    /// The engaged target this frame (the host's): None, it is gone (destroyed, lost): the engaging jets rejoin.
    pub fn target(&mut self, at: Option<Vec3>) {
        self.target = at;
        if at.is_none() {
            for m in self.members.iter_mut().filter(|m| m.engaging) {
                (m.engaging, m.transit, m.report) = (false, true, true);
            }
        }
    }

    /// Makes the flight an enemy pair (or four; docs/ai.md §18) on station at `station`, every jet at `skill`: the
    /// enemy trees ([`fighter::lead`], [`fighter::wingman`]) in line abreast. Call it after adding its jets; a jet
    /// added on the ground is based there (`Enemy::based`): it scrambles on the ground's vector and lands after.
    pub fn enemy(&mut self, skill: Skill, station: Vec3) {
        (self.lead_tree, self.wingman) = (fighter::lead(), fighter::wingman());
        (self.station, self.shape) = (Some(station), LINE_ABREAST);
        for m in &mut self.members {
            (m.skill, m.enemy.based) = (skill, !m.airborne);
        }
    }

    /// An enemy pair's bogey this frame: the ground's vector (`gci`, its track as the network reckons it) and the jet
    /// as it is (`truth`), which a jet knows only while its radar holds it ([`RADAR`]); None, none.
    pub fn bogey(&mut self, gci: Option<Bogey>, truth: Option<Bogey>) {
        (self.gci, self.truth) = (gci, truth);
    }

    /// An enemy jet `number`'s weapons this frame (the host's): its selected missile's envelope against the bogey (m:
    /// max, min), a missile left, its own missile flying at the bogey.
    pub fn weapons(&mut self, number: u8, dlz: (f64, f64), armed: bool, in_air: bool) {
        if let Some(i) = self.index(number) {
            let e = &mut self.members[i].enemy;
            (e.dlz, e.armed, e.in_air) = (dlz, armed, in_air);
        }
    }

    /// An AWACS contact call (fctrl.rs) at `now`: the contact's compass bearing (deg) and range (NM) from the player's
    /// jet (else the lead's); `enemy`: hostile or unidentified. The first AI jet by number holding it in its radar's
    /// reach and cone ([`RADAR`]) reports "contact" after its reaction time. Returns its number, 0 for none.
    pub fn awacs(&mut self, now: f64, bearing_deg: f64, miles: f64, enemy: bool) -> u8 {
        let Some(from) = self.members.iter().find(|m| !m.ai).or(self.members.get(self.lead)) else { return 0 };
        if !enemy {
            return 0;
        }
        let b = bearing_deg.to_radians();
        let at = from.v.pos + Vec3::new(b.sin(), b.cos(), 0.0) * (miles * 1852.0);
        // ponytail: every AWACS call is answered once by the first jet that holds it; a memory of contacts reported
        // when the repeats grow too chatty.
        let Some(m) =
            self.members.iter().find(|m| m.ai && m.alive && m.airborne && !m.landed && !m.defending && in_radar(m, at))
        else {
            return 0;
        };
        self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: "contact" }));
        m.number
    }

    /// Jet `number` this frame: alive (the host's word; a crash counts as dead), its flight model and autopilot.
    /// The flight's one time base is the frame: the host steps every jet of the frame first (the player's, the AI's,
    /// at any cadence), then senses them all, so they are read at one instant. Their flight models' clocks are never
    /// compared: a restarted flight model, a late spawn or a skipped step puts them on other epochs (the player's
    /// 44 s apart from its wingmen's put the lead 50 m off where it flew, test_four_ship).
    pub fn sense(&mut self, number: u8, alive: bool, fm: &Fm, ap: &Autopilot) {
        let Some(i) = self.index(number) else { return };
        let m = &mut self.members[i];
        let s = fm.state();
        m.alive = alive && s.crashed.is_none();
        let v = fm.ap_view();
        let dt = v.t - m.v.t;
        // (Held while it pulls away: its own pull would clear the prediction early and toggle the pull.)
        if dt > 0.0 && !m.avoiding {
            m.acc = m.acc + ((v.vel - m.v.vel) / dt - m.acc) * (dt / ACC_S).min(1.0);
        }
        m.v = v;
        m.corner = fm.corner_speed();
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
        // The regroup: element 2 rejoins (from a split).
        let (to, cmd) = if cmd == "regroup" { (5, "rejoin") } else { (to, cmd) };
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
                    (m.rtb, m.released, m.transit, m.report, m.engaging) = (false, false, true, true, false);
                    if m.number == 3 {
                        self.split = None;
                    }
                    "ack"
                }
                "rtb" if flying => {
                    (m.rtb, m.engaging) = (true, false);
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
        // The split lasts while #3 flies its task with the flight: lost, sent home or the flight's lead, element 2
        // regroups.
        let on_task = self.index(3).is_some_and(|k| {
            let m = &self.members[k];
            k != self.lead && m.ai && m.alive && !m.rtb && !m.released
        });
        if !on_task {
            self.split = None;
        }
        let lead = &self.members[self.lead];
        // A lead that started without the tower's call: the flight starts with it.
        if lead.engine_on && lead.v.on_ground {
            self.cleared.get_or_insert(now);
        }
        let lead_n = lead.number;
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
                (self.shape, self.split) = (TRAIL, None);
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
        let committed = self.members[self.lead].enemy.committed;
        let base = SHAPES[self.shape].1;
        let table = |n: u8| if (2..=4).contains(&n) { base[n as usize - 2] } else { [0.0; 3] };
        let home = self.home;
        for i in 0..self.members.len() {
            let li = self.leader_index(i);
            let ld = leader_of(&self.members[li]);
            let lead_slot = table(self.members[li].number);
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
            let mut rejoin = None;
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
                let far = if m.rejoining { REJOIN.1 } else { REJOIN.0 };
                if m.slot_error > far && m.airborne && !m.v.on_ground && !m.v.gear_down {
                    let speed = (ld.vel.length() as f32 + REJOIN.3).max(DEFEND_SPEED);
                    rejoin = Some(Steer { to: s, g: REJOIN.2, speed, thr_max: 1.0, fighter: false });
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
            m.engaging &= m.alive && !m.rtb && !m.released;
            let engage = self.target.filter(|_| m.engaging);
            let engage = engage.map(|to| Steer { to, g: ENGAGE_G, speed: ENGAGE_SPEED, thr_max: 1.0, fighter: false });
            let own = engage.or(if m.number == 3 { self.split } else { None });
            m.rejoining = own.is_none() && rejoin.is_some();
            m.task = own.or(rejoin);
            (m.order.mode, m.order.decoy, m.order.shoot, m.order.gun) = (None, None, false, false);
            if let Some(st) = self.station {
                // On the ground its radar is off and its pilot looks for nothing: the ground's vector only.
                let up = !m.v.on_ground;
                let contact = self.truth.filter(|b| up && in_radar(m, b.pos));
                // (Once seen it stays seen inside the visual range: the pilot keeps sight, checking six.)
                let kept = |b: &Bogey| m.enemy.visual && b.pos.distance(m.v.pos) < bfm::VISUAL_M;
                let seen = self.truth.filter(|b| up && (in_sight(m, b.pos) || kept(b)));
                let e = &mut m.enemy;
                (e.station, e.contact, e.visual) = (st, contact.is_some(), seen.is_some());
                e.bogey = contact.or(seen).or(self.gci);
                e.fought = e.aim.take().map(|(aim, _)| aim);
                // The bogey's turn as seen: its velocity's swing since the last decision that knew it.
                let truth = contact.or(seen);
                e.rate = truth.map_or(0.0, |b| bfm::seen_rate(e.last, now, b.vel));
                e.last = truth.map(|b| (now, b.vel));
                if i != self.lead {
                    e.committed = committed;
                }
            }
            if i == self.lead {
                self.lead_tree.tick(m)
            } else {
                self.wingman.tick(m)
            };
            for id in m.calls.drain(..) {
                self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id }));
            }
        }
        // The element mate (1 and 2, 3 and 4) sees a missile launched at its partner (its smoke) and calls the break,
        // once a launch, unless it is defending itself. (A lock is heard only on the jet's own RWR.)
        for i in 0..self.members.len() {
            let p = &self.members[i];
            let Some(t) = p.threat.filter(|t| t.launch) else {
                self.members[i].mate_called = false;
                continue;
            };
            let mate =
                self.index(if p.number % 2 == 1 { p.number + 1 } else { p.number - 1 }).map(|j| &self.members[j]);
            let Some(mate) = mate.filter(|o| o.ai && o.alive && o.airborne && o.threat.is_none() && !p.mate_called)
            else {
                continue;
            };
            let id = if defence(p, &t).1 { "break_right" } else { "break_left" };
            self.calls.push((now + mate.skill.reaction_s, Call { from: mate.number, id }));
            self.members[i].mate_called = true;
        }
    }

    /// Each AI jet's leader this frame: on the ground the jet ahead in taxi order (TaxiCL's spacing, TakeoffCL's
    /// stream), in the air the flight lead; its slot, stepped down during a change of slots.
    fn feed(&mut self) {
        for i in 0..self.members.len() {
            let a = self.avoid(i);
            let ld = leader_of(&self.members[self.leader_index(i)]);
            let m = &mut self.members[i];
            m.avoiding = a.is_some_and(|(miss, _)| miss < if m.avoiding { AVOID_CLEAR_M } else { AVOID_M });
            m.order.avoid = a.filter(|_| m.avoiding).map(|(_, away)| away);
            let ahead = (0..i).rev().map(|j| &self.members[j]).find(|a| a.alive).map(leader_of);
            let m = &mut self.members[i];
            let ground = m.v.on_ground && !m.airborne || m.mode == 9 && !m.airborne;
            m.order.leader = if ground { ahead } else { Some(ld) };
            m.order.slot = m.slot;
            // The dogfight's point follows the bogey every frame while it is in sight.
            if let (Some((aim, lay)), Some(b)) = (m.enemy.aim, self.truth.filter(|_| m.enemy.visual)) {
                let to = bfm::aim_point(m.v.pos, &b, &aim, lay, bfm::floor(m));
                if let Some(s) = m.order.steer.as_mut() {
                    s.to = to;
                }
            }
            if m.transit {
                m.order.slot[2] -= TRANSIT_STEP * (m.number as f32 - 1.0);
            }
        }
    }
}

impl Flight {
    /// Member `i`, an AI jet in the air: the closest approach within [`AVOID_S`] to the jet it comes nearest to, m,
    /// and the way away from it (straight at it: the higher number goes down). Both go on as they turn and speed up
    /// now (their accelerations; in straight lines a jet released on afterburner from behind the lead was seen too
    /// late, 13–29 m from it), sampled every [`AVOID_STEP_S`] and at the straight lines' closest approach.
    fn avoid(&self, i: usize) -> Option<(f64, Vec3)> {
        let me = &self.members[i];
        if !me.ai || !me.alive || me.v.on_ground {
            return None;
        }
        let (miss, other) = (self.members.iter())
            .filter(|o| o.number != me.number && o.alive && !o.v.on_ground)
            .flat_map(|o| {
                let (op, ov) = (o.v.pos, o.v.vel);
                let (dp, dv, da) = (op - me.v.pos, ov - me.v.vel, o.acc - me.acc);
                // Also the straight lines' closest approach (head-on, a sample's step is 50 m).
                let straight = (-dp.dot(dv) / dv.dot(dv).max(1e-6)).clamp(0.0, AVOID_S);
                let steps = (0..=(AVOID_S / AVOID_STEP_S) as usize).map(|k| k as f64 * AVOID_STEP_S);
                steps.chain([straight]).map(move |t| (dp + dv * t + da * (t * t / 2.0), o.number))
            })
            .min_by(|a, b| a.0.length().total_cmp(&b.0.length()))?;
        let down = if me.number > other { -1.0 } else { 1.0 };
        Some((miss.length(), (-miss).try_normalize().unwrap_or(Vec3::UP * down)))
    }
}

/// `m`'s defence against `t` and whether it turns right: against a radar (a lock, a radar missile) the beam (the
/// threat 90° off the nose, the side nearer its track; the Doppler notch), against an infrared missile a break into
/// it; at [`DEFEND_G`], at military power against infrared (flares), at its height.
pub(crate) fn defence(m: &Member, t: &Threat) -> (Steer, bool) {
    use std::f64::consts::{FRAC_PI_2, PI, TAU};
    let wrap = |a: f64| (a + PI).rem_euclid(TAU) - PI;
    let p = m.v.pos;
    let track = m.v.vel[0].atan2(m.v.vel[1]);
    let b = (t.pos[0] - p[0]).atan2(t.pos[1] - p[1]);
    let h = if t.launch && t.ir {
        b
    } else if wrap(b + FRAC_PI_2 - track).abs() < wrap(b - FRAC_PI_2 - track).abs() {
        b + FRAC_PI_2
    } else {
        b - FRAC_PI_2
    };
    let to = p + Vec3::new(h.sin(), h.cos(), 0.0) * 50_000.0;
    let g = if t.launch { DEFEND_G.1 } else { DEFEND_G.0 };
    // Flares decoy only with the afterburner out (player_weapons.gd's decoy rule).
    let thr_max = if t.ir { MILITARY } else { 1.0 };
    (Steer { to, g, speed: DEFEND_SPEED, thr_max, fighter: false }, wrap(h - track) > 0.0)
}

/// A threat on it (its RWR's lock, its MAW's missile): the call at once (a lock: "spike" from the air, "mud" from the
/// ground; a launch: "defending"), heard after its reaction time; then the defence ([`defence`]) with a decoy (chaff
/// against a radar, flares against infrared) each decision. Clear for [`CLEAR_S`], it goes back (its rejoin or its
/// route).
pub(crate) fn defend(m: &mut Member) -> Status {
    let Some(t) = m.threat else {
        m.cue = None;
        if !m.defending {
            m.called_level = 0;
            return Status::Failure;
        }
        if m.now < *m.clear_since.get_or_insert(m.now) + CLEAR_S {
            return Status::Running; // the turn held
        }
        (m.defending, m.called_level, m.clear_since) = (false, 0, None);
        return Status::Failure;
    };
    m.clear_since = None;
    let level = 1 + t.launch as u8;
    if level > m.called_level {
        m.called_level = level;
        m.calls.push(if t.launch {
            "defending"
        } else if t.ground {
            "mud"
        } else {
            "spike"
        });
    }
    if m.now < *m.cue.get_or_insert(m.now) + m.skill.reaction_s {
        return Status::Failure;
    }
    m.defending = true;
    m.order.steer = Some(defence(m, &t).0);
    m.order.decoy = Some(if t.ir { Decoy::Flare } else { Decoy::Chaff });
    m.order.mode = Some(autopilot::MODE_STEER);
    Status::Running
}

/// A member's order to its autopilot and flight model (the tests and the Godot class alike).
pub fn apply(o: &Order, ap: &mut Autopilot, fm: &mut Fm) {
    ap.leader = o.leader;
    ap.slot = o.slot;
    ap.avoid = o.avoid;
    if o.steer.is_some() {
        ap.steer = o.steer;
    }
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
