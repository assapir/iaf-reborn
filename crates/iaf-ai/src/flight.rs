//! The flight lead layer (modern-iaf/docs/ai-plan.md §3, §6): a flight of up to four jets in two elements (#2 on #1,
//! #4 on #3), its lead (promoted 1 → 3 → 2 → 4 when lost), its shape and each wingman's slot, the split and the
//! regroup, the start-up, the landing sequence, the radio commands (the lead's targets: engage, sort, weapons free,
//! cover; docs/ai.md §8.11), the threats on each jet and the AWACS calls, and the calls (after the wingman's reaction
//! time). The jets fly the autopilot's loops ([`apply`]); every figure here is
//! inferred unless a doc says otherwise.

use crate::bfm;
use crate::bt::{Node, Status};
use crate::fighter::{self, Bogey, Enemy};
use crate::site;
use crate::skill::Skill;
use crate::sort;
use crate::strike::{self, Phase, Strike};
use crate::wingman;
use iaf_avionics::ecm::{self, Shot};
use iaf_avionics::radar::{look_down, sigma};
use iaf_flight::Vec3;
use iaf_flight::airbase::Airbase;
use iaf_flight::aircraft::ApView;
use iaf_flight::aircraft::MILITARY;
use iaf_flight::airframe::Rcs;
use iaf_flight::autopilot::{self, Autopilot, Host, Leader, MODE_GO_HOME, MODE_SLOT, MODE_TAKE_OFF, Steer};
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
/// Going home, each jet keeps this long behind the jet ahead of it on the way to the lineup, s (inferred: jets in a
/// circuit land some 15-40 s apart): below it, it flies its leader's speed less `.1` per m short, at least `.2` m/s
/// (above the circuit's base-leg speed, 87.5 m/s), until the turn to final ([`Autopilot::pace`]).
const SPACING: (f64, f64, f32) = (30.0, 0.02, 85.0);
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
/// Once pulling away, it goes on until the closest approach is this far, m, or, a jet in its slot, no nearer than
/// the second with the jets no longer closing (the closest approach is now; inferred: a pull that stopped at
/// [`AVOID_M`] left two AI jets 37 m apart, and an AI jet 13 m from the player's, who does not pull; one that went on
/// to this far, more than the slots' 84 m, never stopped in a slot: in the lead's 30° bank turn #3 and #4, 69 m apart
/// at the join-up, pulled on and scattered the flight 500 m, test_four_ship, 2026-11-22).
const AVOID_CLEAR_M: f64 = 100.0;
const AVOID_SLOT_CLEAR_M: f64 = 70.0;
/// On a tanker's station ([`Flight::set_refuel`]) the slot loop takes the station's gains within this, m (inferred).
const PRECISE_M: f64 = 100.0;
/// A slot is reached (the transit's end; "in position") within this, m.
const IN_POSITION_M: f32 = 50.0;
/// The lead's "close up" / "spread out" ([`Flight::command`]): the close shapes' spacing by step, a share of
/// [`SHAPES`]' (standard, close, tight). Tight is the parade position: an F-16's 9.96 m span 12 m from the next jet's
/// centreline leaves 2 m (7 ft) between the wingtips, inside parade's 4 to 10 ft[^cnatra-parade]; close halves the
/// standard (inferred). Line abreast and trail keep theirs. Every distance the flight keeps between its jets in the
/// close shapes ([`CLEAR_M`], [`AVOID_M`], [`AVOID_CLEAR_M`], [`AVOID_SLOT_CLEAR_M`], [`IN_POSITION_M`]) takes the
/// same share.
///
/// [^cnatra-parade]: CNATRAINST 1542.154 / 1542.61L, Parade / Fingertip: "wingtip separation of 4 feet to 10 feet"
///     (second-hand: a search engine's quote), docs/ai.md §8.7;
///     <https://navyflightmanuals.tpub.com/1542.61L_wch1/Parade-Fingertip-1542-61L_Wch10166-166.htm>
pub const CLOSE_STEPS: [f32; 3] = [1.0, 0.5, 0.2];
/// Closer than this step of [`CLOSE_STEPS`], the flight loosens to it while the lead manoeuvres past the parade's
/// limits ([`PARADE_LIMITS`]) and closes back up once the lead has flown within them for [`PARADE_SETTLE_S`]: the
/// parade's lead turns at 30° of bank at the parade rate of roll (about 10°/s)[^p1213-parade]; past that the section
/// flies cruise, whose lead is not held to 30°[^p1213-cruise]. (The 10°/s is second-hand: a search engine's quote.)
///
/// [^p1213-parade]: CNATRA P-1213 (draft), Parade Turns: "rolling into 30 degrees AOB at the parade rate of roll";
///     <https://navyflightmanuals.tpub.com/Draft_P-1213/Parade-Turns-Draft_P-12130041-41.htm>
/// [^p1213-cruise]: CNATRA P-1213 (draft), Cruise Position (second-hand: a search engine's quote);
///     <https://navyflightmanuals.tpub.com/Draft_P-1213/Cruise-Position-Draft_P-12130050-50.htm>
const PARADE_LOOSE: usize = 1;
/// The lead's bank (rad), roll rate (rad/s) and load factor past which the flight loosens ([`PARADE_LOOSE`]); the
/// parade's 30° and 10°/s with a margin, and a 30° bank turn's 1.15 g with one (inferred).
const PARADE_LIMITS: (f32, f32, f64) = (35.0 * std::f32::consts::PI / 180.0, 20.0 * std::f32::consts::PI / 180.0, 1.5);
/// The lead within [`PARADE_LIMITS`] this long, s, the flight closes back up (inferred).
const PARADE_SETTLE_S: f64 = 5.0;
/// The indices of "line_abreast" and "trail" in [`SHAPES`].
const LINE_ABREAST: usize = 1;
const TRAIL: usize = 2;
/// Who leads when the lead is lost: #3 is the deputy (ai-plan F6).
const PROMOTION: [u8; 4] = [1, 3, 2, 4];
/// A split's point farther than this from the flight lead is refused: the elements' targets are in one area, m.
pub const SAME_AREA_M: f64 = 40_000.0;
/// Every AI jet's ground collision avoidance floor (m above the terrain; `Autopilot::floor`, docs/ai.md §20; inferred:
/// 100 ft, under the lowest terrain following height).
pub const FLOOR_M: f32 = 30.0;
/// The terrain following's heights by order ([`Flight::low`]): 150 to 500 ft (m; the low-level band of the brief,
/// inferred).
pub const LOW_M_RANGE: (f32, f32) = (45.7, 152.4);
/// The lead's radio order "low level" ([`Flight::command`]): 300 ft (m; inferred, the band's middle).
pub const LOW_ORDER_M: f32 = 91.4;
/// The split element's turns, g (a 48° bank: #4 keeps its slot on #3 round the circle).
const TASK_G: f32 = 1.5;
/// The defensive turn's load factor against a lock and against a missile; its speed, m/s; how long a jet stays clear
/// before it rejoins, s.
const DEFEND_G: (f32, f32) = (4.0, 6.5);
const DEFEND_SPEED: f32 = 260.0;
const CLEAR_S: f64 = 5.0;
/// A wingman ordered to cover ([`Flight::command`] "cover") keeps fighting a bandit that attacked the lead while it
/// stays this near the lead, m (20 NM, inside an R-27R's reach of the lead; inferred).
pub const COVER_M: f64 = 37_000.0;
/// A radar locked on the lead is the bandit's within this, m (the RWR's position of the lock against the host's).
const LOCK_MATCH_M: f64 = 1000.0;
/// Weapons free: the area's radius round its point, m; a bandit hunted is dropped beyond this share of it (inferred:
/// 20 NM, the cover's reach).
pub const FREE_R: f64 = 37_000.0;
const FREE_KEEP: f64 = 1.25;
/// A splash is a wingman's when its missile flew at the foe, or its gun fired at it this recently, s (a burst and the
/// rounds' flight; inferred).
const SPLASH_S: f64 = 3.0;
/// The far rejoin: a wingman in the air farther than `.0` m from its slot flies at the slot point (the steer loop, at
/// `.2` g and its leader's speed plus `.3` m/s, at least [`DEFEND_SPEED`]) until nearer than `.1` m, then the slot
/// loop. The slot loop's capped
/// spring only matches the leader's velocity that far out: on a lead circling at 30° of bank, wingmen 17 km off flew
/// a parallel circle for ten minutes (test_four_ship, 20 Nov 2026; inferred figures).
const REJOIN: (f32, f32, f32, f32) = (6_000.0, 3_000.0, 3.0, 60.0);
/// An AI jet reports an AWACS contact inside its radar's reach, m, and this far off its nose, deg (a fighter radar's
/// 40 NM and ±60°).
const RADAR: (f64, f64) = (74_000.0, 60.0);
/// The AI jets' pulse-Doppler radar in look-down loses a jet slower than this along the line of sight, m/s (the ground's
/// Doppler band; the real FCR's MTR LO, 60 kt, docs/radar.md §9.8, taken for every AI fighter's radar: inferred).
const RADAR_REJECT: f64 = 30.0;
/// Taxiing in, a jet holds while another jet of the flight with its engine running is on the ground in its way:
/// within `.0` m along its heading and `.1` m across, or nearer than `.2` m and not behind it (inferred: room to stop
/// from the 30 kt taxi speed on the brakes, the width of a taxiway with a wing either side, and a pivot's turn toward
/// a jet beside the way; at 80 m along a jet stopped 21 m behind the one ahead, and one turning toward a jet stopped
/// beside its turn point came within 31 m).
const TAXI_HOLD_M: (f64, f64, f64) = (150.0, 25.0, 60.0);
/// Taxiing out on a base turned into the wind, a jet holds this near the runway entry while a jet ahead is still on
/// the runway, m (inferred: the holding point is 86–101 m before the entry; room for the jet's turn onto it).
const BACKTRACK_HOLD_M: f64 = 150.0;
/// A pairs take-off ([`Flight::pairs`]): the wingman lines up this far beside its element lead, m (inferred: a 10 m
/// span either side of a 45 m runway's centreline, 5 m between the tips); the lead waits on the runway for it at most
/// this long, s.
const PAIR_M: f32 = 15.0;
const PAIR_WAIT_S: f64 = 90.0;
/// A pairs take-off: the mates fly free of each other's collision avoidance from the roll until they are this far
/// apart (the wingman's way out to its slot; the slots are at least 84 m apart), m, or this long after lift-off, s.
const PAIR_FREE: (f64, f64) = (60.0, 120.0);
/// The landing pattern's steps that bring the tower's calls (autopilot `phase`): the turn to final (LandingCL's CH4)
/// and StopPlane's end.
const TURN_FINAL: usize = 11;
/// An AI lead with the player as its wingman (`Flight::add`, a lesson's `start.seat`): it taxis once every other jet
/// of the flight has run its engine this long, s (inferred: the stored-heading alignment's 90 s and a margin).
pub const TAXI_AFTER_S: f64 = 120.0;
/// A tactical turn ([`LeadStep::Turn`]): "the outside man ... turns first", "a 14-unit AOA turn, using approximately
/// 70 degrees AOB", at 300 KIAS; "the inside man waits until the outside man is nose on" (CNATRA P-1221, Tac Turn[^tac]).
/// A level turn at 70° of bank pulls 2.9 g (1 / cos 70°). Ours for the wait: each inside jet starts once the outside
/// jet has flown the distance across between them at the turn's start (two equal turns then end abeam at the same
/// spacing, the sides swapped; inferred: the nose-on rule's aim). A jet has turned within [`TURNED_DEG`] of the new
/// heading; the turn is over at the latest after [`TAC_MAX_S`] (inferred). The in-place turn turns every jet at once,
/// 180°.
///
/// [^tac]: CNATRA P-1221, Tactical Formation, Tac Turn; <https://navyflightmanuals.tpub.com/P-1221/Tac-Turn-27.htm>
pub const TAC_G: f32 = 2.9;
const TURNED_DEG: f64 = 10.0;
const TAC_MAX_S: f64 = 120.0;

/// One order of an AI lead's plan ([`Flight::set_plan`], [`Flight::lead_order`]): a shape of [`SHAPES`] (its index),
/// the rejoin (to fingertip), close up or spread out one step, a tactical turn (right or left; in place: 180°, else
/// 90°).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LeadStep {
    Shape(usize),
    Rejoin,
    Close,
    Spread,
    Turn { right: bool, in_place: bool },
}

/// The lead's calls for its orders: the shapes' in [`SHAPES`] order, then the rejoin, close up, spread out and the
/// turns (tac right, tac left, in-place right, in-place left).
pub const LEAD_CALLS: [&str; 15] = [
    "lead_fingertip",
    "lead_line_abreast",
    "lead_trail",
    "lead_echelon_right",
    "lead_echelon_left",
    "lead_diamond",
    "lead_vic",
    "lead_delta",
    "lead_rejoin",
    "lead_close_up",
    "lead_spread_out",
    "lead_tac_right",
    "lead_tac_left",
    "lead_in_place_right",
    "lead_in_place_left",
];

/// A tactical turn under way: its start, the heading before it and the new one (rad), its way, each jet's wait after
/// the start (s), the numbers that have started their turn and those that have turned.
#[derive(Debug, Clone)]
struct Tac {
    at: f64,
    from: f64,
    to: f64,
    right: bool,
    wait: Vec<(u8, f64)>,
    started: Vec<u8>,
    done: Vec<u8>,
}

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
    /// A missile's velocity (zero for a lock): its time to go sets the decoys' timing ([`defend`]).
    pub vel: Vec3,
    /// A missile (else a lock).
    pub launch: bool,
    /// An infrared missile (flares; else chaff).
    pub ir: bool,
    /// The lock's radar is on the ground.
    pub ground: bool,
}

/// A hostile jet the host sees this frame ([`Flight::bandits`]): its id (the host's, never reused), where, how fast,
/// and its self-protection jammer's burn-through share (0 not jamming; docs/ai.md §15.6).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Bandit {
    pub id: u32,
    pub pos: Vec3,
    pub vel: Vec3,
    pub jam: f64,
    /// What a radar sees of it (the sites' `site::Target`): its nose, its definition's cross-section (an untreated
    /// fighter's, `site::FIGHTER`, without one), its bays open, its loaded external stations.
    pub nose: Vec3,
    pub rcs: Rcs,
    pub bays_open: bool,
    pub stores: u32,
}

impl Bandit {
    /// A bandit of an untreated fighter's cross-section, its nose along its velocity, clean.
    pub fn new(id: u32, b: Bogey, jam: f64) -> Bandit {
        let nose = b.vel.try_normalize().unwrap_or(Vec3::NORTH);
        Bandit { id, pos: b.pos, vel: b.vel, jam, nose, rcs: site::FIGHTER, bays_open: false, stores: 0 }
    }

    fn bogey(&self) -> Bogey {
        Bogey { pos: self.pos, vel: self.vel }
    }
}

/// The lead's order on targets that one of our wingmen flies (docs/ai.md §8.11): none (it keeps its slot, calls its
/// contacts and fights only a bandit that attacks it); cover (it fights a bandit that attacks the lead); engage (the
/// bandit the lead named); sort (its share of the picture, [`sort::deal`]); free (it hunts any bandit in an area).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Tactic {
    #[default]
    None,
    Cover,
    Engage,
    Sort,
    Free,
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
    /// The slot is a close-up step ([`CLOSE_STEPS`], `Autopilot::close`).
    pub close: bool,
    /// The slot is a station on the tanker (`Autopilot::precise`).
    pub precise: bool,
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
    /// Stop on the ground (taxiing in behind a jet ahead; a pair's lead waiting on the runway for its wingman).
    pub hold: bool,
    /// Taxiing out on a base turned into the wind: stop short of the runway (`Flight::backtrack_hold`).
    pub hold_short: bool,
    /// A pairs take-off's wingman: its lineup this far right of the lineup point, m (0: the stream's).
    pub lineup_offset: f32,
    /// A pairs take-off's lead with its wingman beside it: the roll at military power.
    pub pair_lead: bool,
    /// Its attack's release now (the host's AI ripple of its air-to-ground weapon, combat.gd; [`strike`]; one frame).
    pub release: bool,
    /// The steer loop flies this high above the terrain ahead (`Autopilot::follow`; [`Flight::low`], the attack's
    /// low run-in and egress); None: its point's height.
    pub follow: Option<f32>,
    /// Going home: the speed it flies at most, m/s, its spacing behind the jet ahead (`Autopilot::pace`).
    pub pace: Option<f32>,
    /// The flight flies low ([`Flight::low`]): the ground collision avoidance in place of the watch-ground
    /// (`Autopilot::low`).
    pub low: bool,
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
    /// The take-off's stage or the landing pattern's step (`Autopilot::phase`).
    pub phase: Option<usize>,
    /// Going home, the way left to the lineup along its track, m (`Autopilot::to_go`).
    pub to_go: Option<f64>,
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
    /// When it was sent home, s: the order the jets going home keep ([`SPACING`]).
    pub released_at: f64,
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
    /// The flight lead flies its attack's run or egress: no slot to keep on it ([`strike`]).
    pub(crate) lead_striking: bool,
    /// Another jet of the flight flies its attack's run (one run at a time, [`strike`]).
    pub(crate) run_busy: bool,
    /// The threat on it this frame ([`Flight::threat`]); when it was first seen, the level called (1 a lock, 2 a
    /// launch), its mate's break called, defending, clear since.
    pub threat: Option<Threat>,
    /// The host's threat this frame as it came (the tree clears `threat` for a lock it fights through): the jammer's
    /// cue ([`Flight::jams`]).
    rwr: bool,
    /// The decoy of the launch's cue released ([`defend`]).
    launch_decoy: bool,
    pub(crate) cue: Option<f64>,
    pub(crate) called_level: u8,
    mate_called: bool,
    pub defending: bool,
    pub(crate) clear_since: Option<f64>,
    /// Element 2's lead while split, or a jet engaging: its task ([`Flight::split`], [`Flight::engage`]).
    pub task: Option<Steer>,
    /// The lead's order on targets ([`Tactic`]); the bandit it gave (engage, sort) or the one hunted (free); a sorted
    /// wingman holds its fire until its element lead shoots or it is threatened; the free hunt's area.
    pub tactic: Tactic,
    pub assigned: Option<u32>,
    pub holding: bool,
    pub area: Option<Vec3>,
    /// Whom it fights this decision (a bandit's id; the enemy trees' leaves, `enemy` its facts), None in the shape. A
    /// holding wingman has its sorted bandit here, not committed.
    pub bandit: Option<u32>,
    /// When it last fired (a missile or a burst; [`SPLASH_S`]); "winchester" called (nothing left to shoot).
    pub(crate) last_shot: f64,
    pub(crate) winchester: bool,
    /// An enemy fighter's facts and memory ([`Flight::enemy`]).
    pub enemy: Enemy,
    /// The tower's calls to it made: cleared to land, taxi to parking.
    tower: [bool; 2],
    /// A pairs take-off: lined up on the runway since (the lead's wait, [`PAIR_WAIT_S`]); flying free of its mate's
    /// collision avoidance since its lift-off ([`PAIR_FREE`]; None on the ground).
    lined_up: Option<f64>,
    pair_free: Option<Option<f64>>,
    /// Its air-to-ground attack ([`Flight::attack`], [`Flight::strike`]).
    pub strike: Strike,
    /// Sent to the tanker by the lead's "refuel" ([`Flight::command`]); the tanker's station for it this frame
    /// ([`Flight::set_refuel`]: the tanker as its leader and its slot on it; tanker.rs).
    pub refuelling: bool,
    pub refuel: Option<(Leader, [f32; 3])>,
    /// The flight's low-level height this decision ([`Flight::low`]).
    pub(crate) low: Option<f32>,
    /// Its engine running since (the host's time); an AI lead waits for the flight's ([`TAXI_AFTER_S`]).
    engine_since: Option<f64>,
    /// An AI lead on the ground: another jet of the flight has not run its engine [`TAXI_AFTER_S`] yet.
    pub(crate) flight_wait: bool,
    /// An AI lead with the player in its flight.
    pub(crate) leads_player: bool,
    /// The bandits its radar holds this decision ([`radar_holds`]), and the jammers beyond their burn-through it sees
    /// as strobes (in its cone and reach and in sight).
    radar: Vec<u32>,
    strobes: Vec<u32>,
}

impl Member {
    /// The lead's order on targets ([`Tactic`]) and its ground attack ([`strike`]) over, with the bandit it fought.
    /// The two are one job at a time: each order begins here, so a tactic other than None means no attack, and an
    /// attack (its phase not None) means no tactic. Its weapon stays (the host's).
    pub(crate) fn end_order(&mut self) {
        self.strike.clear();
        (self.tactic, self.assigned, self.holding, self.area, self.bandit) = (Tactic::None, None, false, None, None);
    }
}

/// The flight.
pub struct Flight {
    pub members: Vec<Member>,
    /// The index of the flight lead in `members`.
    lead: usize,
    shape: usize,
    /// The close shapes' spacing: an index of [`CLOSE_STEPS`].
    close: usize,
    /// Since when the lead has flown within [`PARADE_LIMITS`] (the host's time, as `now`: the jets' clocks differ);
    /// None: it is past them, the flight loosened.
    parade: Option<f64>,
    /// The last frame's time ([`Flight::step`]).
    now: f64,
    /// The home base's lineup (bingo's distance, the landing sequence).
    home: Option<Vec3>,
    /// The home base's runway entry on a base turned into the wind (`Airbase::backtrack`).
    entry: Option<Vec3>,
    cleared: Option<f64>,
    next: f64,
    lead_gear_up: bool,
    last_release: f64,
    calls: Vec<(f64, Call)>,
    /// Element 2's task while split.
    split: Option<Steer>,
    /// The hostile jets this frame ([`Flight::bandits`]); those any jet of the flight sees (its radar or its pilot:
    /// the flight's picture, shared by the data link); the ones a contact was called for.
    bandits: Vec<Bandit>,
    picture: Vec<u32>,
    reported: Vec<u32>,
    wingman: Node<Member>,
    lead_tree: Node<Member>,
    /// An enemy pair ([`Flight::enemy`]): its station; the ground's vector and the id of the jet it tracks
    /// ([`Flight::gci`]).
    station: Option<Vec3>,
    gci: Option<(Bogey, u32)>,
    /// A pairs take-off ([`Flight::pairs`]).
    pairs: bool,
    /// The ground target the attacking jets attack ([`Flight::attack`], [`Flight::ground_target`]).
    ground: Option<Bogey>,
    /// The jet that released last on it ([`Flight::released`]): its "alpha" when it is destroyed, also after its
    /// "done" ([`Flight::ground_hit`]).
    hit_by: Option<u8>,
    /// The flight's low-level height ([`Flight::low`]).
    low: Option<f32>,
    /// An AI lead's plan: (the waypoint, its order once the lead has passed it), in route order ([`Flight::set_plan`]).
    plan: Vec<(usize, LeadStep)>,
    /// A tactical turn under way; the slots mirrored (each turn swaps the sides).
    tac: Option<Tac>,
    mirror: bool,
}

impl Default for Flight {
    fn default() -> Self {
        Flight {
            members: Vec::new(),
            lead: 0,
            shape: 0,
            close: 0,
            parade: Some(f64::NEG_INFINITY),
            now: 0.0,
            home: None,
            entry: None,
            cleared: None,
            next: 0.0,
            lead_gear_up: false,
            last_release: f64::MIN,
            calls: Vec::new(),
            split: None,
            bandits: Vec::new(),
            picture: Vec::new(),
            reported: Vec::new(),
            wingman: wingman::wingman(),
            lead_tree: wingman::lead(),
            station: None,
            gci: None,
            pairs: false,
            ground: None,
            hit_by: None,
            low: None,
            plan: Vec::new(),
            tac: None,
            mirror: false,
        }
    }
}

/// `m` as a leader, as sensed: every jet at one instant ([`Flight::sense`]).
fn leader_of(m: &Member) -> Leader {
    let a = m.v.att;
    Leader { pos: m.v.pos, vel: m.v.vel, att: [a.pitch, a.roll, a.heading], active: m.alive }
}

pub(crate) fn flat(a: Vec3, b: Vec3) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}

/// `at` inside `m`'s radar's cone ([`RADAR`]).
fn in_cone(m: &Member, at: Vec3) -> bool {
    let (d, v) = (at - m.v.pos, m.v.vel);
    (v[0] * d[1] - v[1] * d[0]).atan2(v[0] * d[0] + v[1] * d[1]).abs().to_degrees() < RADAR.1
}

/// `at` inside `m`'s radar's reach against the reference cross-section and its cone ([`RADAR`]).
fn in_radar(m: &Member, at: Vec3) -> bool {
    flat(at, m.v.pos) < RADAR.0 && in_cone(m, at)
}

/// `m`'s radar holds `b` (docs/ai.md §18.1): in its cone, inside its reach for `b`'s cross-section seen from `m` (its
/// burn-through when `b` jams) and in sight over the terrain and the earth's curvature (the sites' rule,
/// [`site::in_reach`]), and clear of the ground's clutter: in look-down, not slower than [`RADAR_REJECT`] along the line
/// of sight.
fn radar_holds(m: &Member, b: &Bandit, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
    let from = m.v.pos;
    let d = b.pos - from;
    let along = b.vel.dot(d.try_normalize().unwrap_or(Vec3::ZERO)).abs();
    let s = sigma(&b.rcs, b.nose, -d, b.bays_open, b.stores);
    in_cone(m, b.pos)
        && !(along < RADAR_REJECT && look_down(from, b.pos, RADAR.0, terrain))
        && site::in_reach(from, RADAR.0, s, b.pos, b.jam, terrain)
}

/// `at` in `m`'s pilot's sight: inside [`bfm::VISUAL_M`], not in the blind cone behind its tail ([`bfm::BLIND_DEG`]).
fn in_sight(m: &Member, at: Vec3) -> bool {
    let d = at - m.v.pos;
    let tail = (-m.v.vel).try_normalize().unwrap_or(Vec3::NORTH);
    d.length() < bfm::VISUAL_M && d.dot(tail) < d.length() * bfm::BLIND_DEG.to_radians().cos()
}

/// What `m` knows of its bogey this decision (the fighter's facts, [`Enemy`]), its station `station`: `truth` (the jet
/// as it is) while its radar holds it (through the bandit's jammer) or its pilot sees it, else `known` (the
/// ground's vector, the lead's data link), else the strobe of the bogey's jammer in its radar beyond the burn-through
/// (a jammer broadcasts its position[^w-jam]: the radar's home on jam tracks its angle, not its range; the pilot flies
/// at it as at a vector, inferred: its range taken as known); the bogey's turn as seen.
///
/// [^w-jam]: Wikipedia, "Radar jamming and deception": "When a target is using self-protective jamming (SPJ), it
///     essentially broadcasts its position."
fn know(m: &mut Member, station: Vec3, known: Option<Bogey>, truth: Option<&Bandit>, now: f64) {
    // On the ground its radar is off and its pilot looks for nothing.
    let up = !m.v.on_ground;
    let id = truth.map(|b| b.id);
    let truth = truth.map(Bandit::bogey);
    let contact = truth.filter(|_| up && id.is_some_and(|id| m.radar.contains(&id)));
    let strobe = truth.filter(|_| up && contact.is_none() && id.is_some_and(|id| m.strobes.contains(&id)));
    // (Once seen it stays seen inside the visual range: the pilot keeps sight, checking six.)
    let kept = |b: &Bogey| m.enemy.visual && b.pos.distance(m.v.pos) < bfm::VISUAL_M;
    let seen = truth.filter(|b| up && (in_sight(m, b.pos) || kept(b)));
    let e = &mut m.enemy;
    (e.station, e.contact, e.strobe, e.visual) = (station, contact.is_some(), strobe.is_some(), seen.is_some());
    e.bogey = contact.or(seen).or(known).or(strobe);
    e.fought = e.aim.take().map(|(aim, _)| aim);
    // The bogey's turn as seen: its velocity's swing since the last decision that knew it.
    let truth = contact.or(seen);
    e.rate = truth.map_or(0.0, |b| bfm::seen_rate(e.last, now, b.vel));
    e.last = truth.map(|b| (now, b.vel));
}

/// `b` is behind `m` and pointing at it: the dogfight's defensive geometry against it ([`bfm::defensive`]).
fn on_six(m: &Member, b: &Bandit) -> bool {
    let own = bfm::Jet { pos: m.v.pos, vel: m.v.vel, rate: 0.0 };
    let (range, ata, aa) = bfm::geometry(&own, &bfm::Jet { pos: b.pos, vel: b.vel, rate: 0.0 });
    bfm::defensive(range, ata, aa)
}

/// `b` attacks `m`: on its six ([`on_six`]) in its pilot's sight.
fn attacked(m: &Member, b: &Bandit) -> bool {
    in_sight(m, b.pos) && on_six(m, b)
}

/// `b` attacks the lead `l` (the cover's): its radar locked on it (the lead's RWR, its position within
/// [`LOCK_MATCH_M`]) or on its six.
fn attacks_lead(l: &Member, b: &Bandit) -> bool {
    let lock = l.threat.is_some_and(|t| !t.launch && !t.ground && t.pos.distance(b.pos) < LOCK_MATCH_M);
    l.alive && (lock || on_six(l, b))
}

/// `b` in `m`'s radar (this decision's, [`radar_holds`]) or its pilot's sight: the flight's picture.
fn sees(m: &Member, b: &Bandit) -> bool {
    m.alive && !m.v.on_ground && (m.radar.contains(&b.id) || in_sight(m, b.pos))
}

/// Whether member `m` (AI, alive) can take a fight order: in the air with the gear up, not sent home, something to shoot.
fn can_fight(m: &Member) -> bool {
    m.ai && m.alive && wingman::flying(m) && !m.landed && !m.rtb && !m.released && !m.winchester
}

impl Flight {
    /// Adds jet `number` (1..4; `ai` false: the player). The first one names the home base: the base nearest its
    /// route's last waypoint (else itself). A jet on the ground at a hangar takes it as its home hangar
    /// (`Autopilot::home_hangar`).
    pub fn add(&mut self, number: u8, ai: bool, fm: &Fm, ap: &mut Autopilot) {
        let v = fm.ap_view();
        let p = ap.route.last().map_or(v.pos, |w| Vec3::new(w.x, w.y, w.z));
        if let Some(b) = Airbase::nearest(&ap.bases, [p[0] as f32, p[1] as f32, p[2] as f32])
            && self.home.is_none()
        {
            let v = |p: [f32; 3]| Vec3::new(p[0] as f64, p[1] as f64, p[2] as f64);
            (self.home, self.entry) = (Some(v(b.lineup)), b.backtrack.map(v));
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
            phase: ap.phase(),
            to_go: ap.to_go(v.pos),
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
            released_at: 0.0,
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
            lead_striking: false,
            run_busy: false,
            threat: None,
            rwr: false,
            launch_decoy: false,
            cue: None,
            called_level: 0,
            mate_called: false,
            defending: false,
            clear_since: None,
            task: None,
            tactic: Tactic::None,
            assigned: None,
            holding: false,
            area: None,
            bandit: None,
            last_shot: f64::MIN,
            winchester: false,
            enemy: Enemy::default(),
            radar: Vec::new(),
            strobes: Vec::new(),
            tower: [false; 2],
            lined_up: None,
            pair_free: None,
            strike: Strike::default(),
            refuelling: false,
            refuel: None,
            low: None,
            engine_since: None,
            flight_wait: false,
            leads_player: false,
        });
        self.members.sort_by_key(|m| m.number);
        self.lead = 0;
    }

    pub fn member(&self, number: u8) -> Option<&Member> {
        self.members.iter().find(|m| m.number == number)
    }

    /// Jet `number` switches its self-protection jammer on (when its definition has one; docs/ai.md §15.6): alive,
    /// with a threat on its RWR (a radar locked on it, a missile at it) or defending. Not on the commit alone: a
    /// jammer broadcasts the jet's position ([`know`]'s strobe), so it answers the radar that tracks it (inferred).
    pub fn jams(&self, number: u8) -> bool {
        self.member(number).is_some_and(|m| m.alive && (m.rwr || m.defending))
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
    /// flies at its own slot, nor an attack's run); else the flight lead, with its slot in the shape relative to its element lead's slot.
    /// (Flown on #3 itself also in the shape, #4 amplified #3's corrections: 385 m off in a change of shape, 632 m in a
    /// join-up in a turn; tested and dropped 19 Nov.)
    fn leader_index(&self, i: usize) -> usize {
        let n = self.members[i].number;
        let el = n.is_multiple_of(2).then(|| self.index(n - 1)).flatten().filter(|&j| {
            let e = &self.members[j];
            // (Not on its attack's run: #4 keeps its slot in the shape.)
            let off = e.mode != MODE_SLOT && !e.rejoining && !strike::striking(e);
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

    /// The share of the standard spacing the flight keeps ([`CLOSE_STEPS`]): its close-up step in a close shape, else 1.
    fn spacing(&self) -> f64 {
        self.spacing_at(self.held_step())
    }

    /// [`Flight::spacing`] at close-up step `step`.
    fn spacing_at(&self, step: usize) -> f64 {
        if matches!(self.shape, LINE_ABREAST | TRAIL) { 1.0 } else { CLOSE_STEPS[step] as f64 }
    }

    /// The share the distances the jets keep from each other take (the step down, the pull-away): the ordered step's,
    /// so a flight loosened from the tight step ([`PARADE_LOOSE`]) steps down and pulls away as at the tight step until
    /// it closes back up (with the close step's, the jets still 17 m apart stepped down and pulled away: 213 m off).
    fn guard(&self) -> f64 {
        self.spacing_at(self.close)
    }

    /// The close-up step the flight holds now: the ordered one ([`Flight::close_step`]), or [`PARADE_LOOSE`] while
    /// the lead manoeuvres past the parade's limits and [`PARADE_SETTLE_S`] after.
    pub fn held_step(&self) -> usize {
        let settled = self.parade.is_some_and(|t| self.now - t >= PARADE_SETTLE_S);
        if settled { self.close } else { self.close.min(PARADE_LOOSE) }
    }

    /// The lead past the parade's limits ([`PARADE_LIMITS`]) this frame: the flight loosens; within them, the time
    /// since.
    fn watch_parade(&mut self, now: f64) {
        self.now = now;
        let Some(l) = self.members.get(self.lead) else { return };
        let (bank, rate, n) = PARADE_LIMITS;
        const G: f64 = 9.80665;
        let g = (l.acc + Vec3::UP * G).length() / G;
        let past = l.airborne && (l.v.att.roll.abs() > bank || l.v.rates[1].abs() > rate || g > n);
        self.parade = if past { None } else { Some(self.parade.unwrap_or(now)) };
    }

    /// The slots of #2, #3, #4 in the shape now, at its spacing ([`Flight::spacing`]).
    fn slots(&self) -> [[f32; 3]; 3] {
        let k = self.spacing() as f32;
        let side = if self.mirror { -1.0 } else { 1.0 };
        SHAPES[self.shape].1.map(|s| [s[0] * k, s[1] * k * side, s[2] * k])
    }

    /// The close-up step the flight keeps: 0 standard, 1 close, 2 tight ([`CLOSE_STEPS`]).
    pub fn close_step(&self) -> usize {
        self.close
    }

    /// The threat on jet `number` this frame (its RWR's lock, its MAW's missile; None: clear), for the reactions.
    pub fn threat(&mut self, number: u8, t: Option<Threat>) {
        if let Some(i) = self.index(number) {
            let m = &mut self.members[i];
            (m.threat, m.rwr) = (t, t.is_some());
            m.launch_decoy &= t.is_some_and(|t| t.launch);
        }
    }

    /// The lead's split (ai-plan F12): element 2 (#3, #4 on it) takes its own task at `at`, its target in the same
    /// area (within [`SAME_AREA_M`] of the flight lead): it flies there at its present height and the lead's speed and
    /// circles it until a regroup (`command` "regroup"); the flight stays one (one route, one landing sequence, the
    /// threats and calls). False: no AI #3 in the air with the flight to take it. #3 and #4 answer (unable: too far).
    pub fn split(&mut self, now: f64, at: Vec3) -> bool {
        if !self.player_may_order(5) {
            return false;
        }
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
        for m in self.members.iter_mut().filter(|m| m.number >= 3 && m.ai && m.alive) {
            if ok {
                m.strike.clear(); // the split ends an attack (docs/ai.md §8.10)
            }
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: if ok { "ack" } else { "unable" } }));
        }
        true
    }

    /// The AI jets (indices, not the flight lead) a command to `to` reaches: 0 the flight, 5 the element (#3, #4), 2..4
    /// one wingman.
    fn addressed(&self, to: u8) -> Vec<usize> {
        let takes = |m: &Member| m.ai && m.alive && (to == 0 || m.number == to || to == 5 && m.number >= 3);
        (0..self.members.len()).filter(|&i| i != self.lead && takes(&self.members[i])).collect()
    }

    /// The lead's "engage my target" at `now` to `to` (0 the flight, 5 the element, 2..4 one wingman; docs/ai.md §8.11):
    /// each AI jet addressed that can fight leaves its slot and fights the bandit `id` (the host's radar lock, known to
    /// it by the data link) with the enemy fighters' leaves (the intercept, the shot, the crank, the dogfight;
    /// [`Tactic::Engage`]); #4 stays on #3 when #3 engages too. So the lead names a bandit for each jet or element in
    /// turn: lock it, engage. `id` None or not a bandit now, or a jet that cannot fight: "unable". Some(true): a jet took
    /// it; Some(false): each answered "unable" (a jet already engaging keeps its bandit); None: nobody to take it.
    pub fn engage(&mut self, now: f64, to: u8, id: Option<u32>) -> Option<bool> {
        if !self.player_may_order(to) {
            return None;
        }
        let who = self.addressed(to);
        if who.is_empty() {
            return None;
        }
        let id = id.filter(|&id| self.bandits.iter().any(|b| b.id == id));
        let can = |m: &Member| id.is_some() && can_fight(m);
        let with_three = to != 4 && who.iter().any(|&i| self.members[i].number == 3 && can(&self.members[i]));
        let mut took = false;
        for &i in &who {
            let ok = can(&self.members[i]);
            let m = &mut self.members[i];
            if ok && !(with_three && m.number == 4) {
                (m.tactic, m.assigned, m.holding, m.area, took) = (Tactic::Engage, id, false, None, true);
            }
            if ok {
                m.strike.clear(); // the lead's new order ends its attack (docs/ai.md §8.10)
            }
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: if ok { "ack" } else { "unable" } }));
        }
        Some(took)
    }

    /// The lead's sort at `now` (to the flight; docs/ai.md §8.11): the picture's groups ([`sort::groups`]) go to the
    /// elements and each group's jets to its element's jets by [`sort::deal`]; with both elements on one group (one
    /// group in the picture) each element takes one of its jets, its wingman the same. Each AI jet that can fight takes
    /// its share ([`Tactic::Sort`]): an element lead commits at once and calls "targeted"; a wingman with its element
    /// lead in the sort answers "ack" and supports it, its slot on it and its radar on its share, holding its fire until
    /// that lead shoots ([`Flight::fired`]) or a threat is on it. A bandit of the share gone, it takes the nearest one of
    /// the picture nobody has, else the nearest; none left: it rejoins. Nothing in the picture, or a jet that cannot
    /// fight: "unable". False: no AI wingman to take it.
    pub fn sort(&mut self, now: f64) -> bool {
        if !self.player_may_order(0) {
            return false;
        }
        let who = self.addressed(0);
        if who.is_empty() {
            return false;
        }
        let able = |m: &Member| if m.ai { can_fight(m) } else { m.alive && !m.v.on_ground };
        let elements: Vec<Vec<usize>> = [[1u8, 2], [3, 4]]
            .iter()
            .map(|e| e.iter().filter_map(|&n| self.index(n)).filter(|&i| able(&self.members[i])).collect::<Vec<_>>())
            .filter(|e| !e.is_empty())
            .collect();
        let pic: Vec<Bandit> = self.bandits.iter().filter(|b| self.picture.contains(&b.id)).copied().collect();
        let pts: Vec<Vec3> = pic.iter().map(|b| b.pos).collect();
        let pos = |is: &[usize]| is.iter().map(|&i| self.members[i].v.pos).collect::<Vec<_>>();
        let mut share: Vec<(usize, u32)> = Vec::new();
        if !pic.is_empty() {
            let groups = sort::groups(&pts);
            let jets = |g: &Vec<usize>| g.iter().map(|&k| pts[k]).collect::<Vec<_>>();
            let centres: Vec<Vec3> = groups.iter().map(|g| sort::centre(&jets(g))).collect();
            let leads: Vec<usize> = elements.iter().map(|e| e[0]).collect();
            let g_of = sort::deal(&pos(&leads), &centres);
            for (gi, g) in groups.iter().enumerate() {
                let on: Vec<usize> = (0..elements.len()).filter(|&e| g_of[e] == gi).collect();
                if let [e] = on[..] {
                    let d = sort::deal(&pos(&elements[e]), &jets(g));
                    share.extend(elements[e].iter().zip(d).map(|(&i, k)| (i, pic[g[k]].id)));
                } else {
                    let d = sort::deal(&pos(&on.iter().map(|&e| leads[e]).collect::<Vec<_>>()), &jets(g));
                    for (&e, k) in on.iter().zip(d) {
                        share.extend(elements[e].iter().map(|&i| (i, pic[g[k]].id)));
                    }
                }
            }
        }
        for &i in &who {
            let id = share.iter().find(|s| s.0 == i).map(|s| s.1);
            let n = self.members[i].number;
            let lead_in = n.is_multiple_of(2)
                && self
                    .index(n - 1)
                    .is_some_and(|j| (who.contains(&j) || !self.members[j].ai) && share.iter().any(|s| s.0 == j));
            let m = &mut self.members[i];
            let answer = if id.is_some() {
                (m.tactic, m.assigned, m.holding, m.area) = (Tactic::Sort, id, lead_in, None);
                m.strike.clear();
                if lead_in { "ack" } else { "targeted" }
            } else {
                "unable"
            };
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: answer }));
        }
        true
    }

    /// The lead's "weapons free" at `now` to `to` (0 the flight, 5 the element, 2..4 one wingman) in the area round `at`
    /// (within [`SAME_AREA_M`] of the flight lead, as the split's; docs/ai.md §8.11): each AI jet addressed that can
    /// fight hunts the bandits of the picture within [`FREE_R`] of `at` ([`Tactic::Free`]), one that no other jet hunts
    /// first, the nearest; with none it circles `at`; a wingman whose element lead hunts too supports it (it takes the
    /// other jet of its lead's group by [`sort::deal`]). The hunt ends at joker fuel or on "rejoin". Too far, or a jet
    /// that cannot fight: "unable". Some(true): a jet took it; Some(false): none could; None: nobody to take it.
    pub fn free(&mut self, now: f64, to: u8, at: Vec3) -> Option<bool> {
        if !self.player_may_order(to) {
            return None;
        }
        let who = self.addressed(to);
        if who.is_empty() {
            return None;
        }
        let near = flat(at, self.members[self.lead].v.pos) <= SAME_AREA_M;
        let mut took = false;
        for &i in &who {
            let m = &mut self.members[i];
            let ok = near && can_fight(m);
            if ok {
                (m.tactic, m.assigned, m.holding, m.area, took) = (Tactic::Free, None, false, Some(at), true);
                m.strike.clear();
            }
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: if ok { "ack" } else { "unable" } }));
        }
        Some(took)
    }

    /// Jet `number` shot at a bandit (the host's word for the player; an AI jet's own shots count too): an element
    /// lead's shot (#1, #3) is the call that clears its wingman holding in a sort to shoot.
    pub fn fired(&mut self, number: u8) {
        if let Some(i) = (number % 2 == 1).then(|| self.index(number + 1)).flatten() {
            self.members[i].holding = false;
        }
    }

    /// The bandit `id` was shot down at `now` (the host's): each AI jet fighting it whose missile flew at it, or whose
    /// gun fired within [`SPLASH_S`], calls "splash" after its reaction time (a kill by another is not called).
    pub fn splash(&mut self, now: f64, id: u32) {
        for m in self.members.iter().filter(|m| m.ai && m.alive && m.bandit == Some(id)) {
            if m.enemy.in_air || now - m.last_shot <= SPLASH_S {
                self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: "splash" }));
            }
        }
    }

    /// The player may give an order to `to` (0 the flight, 5 the element, 2..4 one jet): always as the lead; in an AI
    /// lead's flight only to its own wingman (#4 when it flies #3), the flight's orders being the lead's
    /// ([`Flight::lead_order`]). The radio menu offers only these.
    pub fn player_may_order(&self, to: u8) -> bool {
        let player =
            self.members.iter().position(|m| !m.ai).filter(|&i| i != self.lead).map(|i| self.members[i].number);
        player.is_none_or(|p| p % 2 == 1 && to == p + 1)
    }

    /// The lead's "attack my target" at `now` to `to` (0 the flight, 5 the element, 2..4 one wingman) on the ground target
    /// `at` (the host's: a ground unit, a point; docs/ai.md §8.10): each AI jet addressed in the air with an
    /// air-to-ground weapon ([`Flight::ground_weapon`]) answers "ack" and attacks it in number order, each run
    /// [`strike::STAGGER_S`] after the one before (the order on targets or an attack it had ends: a run under way is
    /// broken off at once, the autopilot's ground watch on); the others "unable". The flight has one ground target: a
    /// new one is every attacking jet's. `at` None:
    /// each "unable". Some(true): a jet took it; Some(false): none could; None: nobody to take it.
    pub fn attack(&mut self, now: f64, to: u8, at: Option<Bogey>) -> Option<bool> {
        let who = self.addressed(to);
        if who.is_empty() {
            return None;
        }
        Some(self.assign(now, &who, at, now))
    }

    /// An AI-led flight's attack on the ground target `at` at `now` (the AI lead's own order; an enemy pair's, docs/ai.md
    /// §8.10): the lead takes it at once when it can, then orders its wingmen as [`Flight::attack`] to the flight, the
    /// first run [`strike::STAGGER_S`] after its own. False: the lead is the player's, or no jet could take it.
    pub fn strike(&mut self, now: f64, at: Bogey) -> bool {
        if !self.members.get(self.lead).is_some_and(|m| m.ai) {
            return false;
        }
        let all: Vec<usize> = (0..self.members.len()).filter(|&i| self.members[i].ai).collect();
        self.assign(now, &all, Some(at), now)
    }

    /// The jets `who` (indices, in number order) take the ground target `at`, the first run at `first`, each next
    /// [`strike::STAGGER_S`] later; each AI wingman answers. Whether any took it.
    fn assign(&mut self, now: f64, who: &[usize], at: Option<Bogey>, first: f64) -> bool {
        let mut turn = first;
        let mut took = false;
        for &i in who {
            let m = &mut self.members[i];
            let ok = at.is_some()
                && m.alive
                && m.airborne
                && !m.landed
                && !m.rtb
                && !m.released
                && m.strike.weapon.is_some();
            if ok {
                m.end_order();
                (m.strike.phase, m.strike.turn, took) = (Phase::Wait, turn, true);
                turn += strike::STAGGER_S;
            }
            if i != self.lead {
                self.calls
                    .push((now + m.skill.reaction_s, Call { from: m.number, id: if ok { "ack" } else { "unable" } }));
            }
        }
        if took {
            // A new target (not the one attacked again): no release on it yet.
            let same = |a: &Bogey, b: &Bogey| (a.pos[0] - b.pos[0]).hypot(a.pos[1] - b.pos[1]) <= strike::SNAP_M;
            if !matches!((&self.ground, &at), (Some(a), Some(b)) if same(a, b)) {
                self.hit_by = None;
            }
            self.ground = at;
        }
        took
    }

    /// The flight's low level (the lead's order, a mission's profile; docs/ai.md §20): its AI jets' steer loops fly
    /// `agl` m above the terrain ahead (within [`LOW_M_RANGE`]), and an attack's run comes in low and pops up
    /// ([`strike`]); None: their points' heights.
    pub fn low(&mut self, agl: Option<f32>) {
        self.low = agl.map(|h| h.clamp(LOW_M_RANGE.0, LOW_M_RANGE.1));
    }

    /// The flight's low level's height (m), None: not low ([`Flight::low`]).
    pub fn low_m(&self) -> Option<f32> {
        self.low
    }

    /// The attacked ground target this frame (the host's): None, it is gone (destroyed): the attacking jets end their
    /// attack ("done" after their release) and rejoin.
    pub fn ground_target(&mut self, at: Option<Bogey>) {
        self.ground = at;
    }

    /// Jet `number`'s air-to-ground weapon left this frame (the host's): Some(true) a guided bomb, Some(false) a bomb or
    /// rockets, None none ([`strike::profile`]).
    pub fn ground_weapon(&mut self, number: u8, guided: Option<bool>) {
        if let Some(i) = self.index(number) {
            self.members[i].strike.weapon = guided;
        }
    }

    /// Jet `number`'s bombing manoeuvre released at `now` (the host's AI ripple started): in its run it calls "release"
    /// and egresses.
    pub fn released(&mut self, now: f64, number: u8) {
        if let Some(i) = self.index(number) {
            let m = &mut self.members[i];
            if m.strike.phase == Phase::Run && !m.strike.released {
                (m.strike.released, m.strike.released_at) = (true, now);
                self.calls.push((now, Call { from: m.number, id: "release" }));
                self.hit_by = Some(number);
            }
        }
    }

    /// The attacked ground target destroyed at `now` (the host's, before [`Flight::ground_target`] says it is gone):
    /// the live jet that released last on it calls "alpha", the hit (the user, 25 Nov 2026: "Alpha is for exact hit"),
    /// also when it already called "done"; once per target. Inferred: the last release is the one that hit; a kill by
    /// another (the player's bomb) is said too.
    pub fn ground_hit(&mut self, now: f64) {
        let Some(n) = self.hit_by.take() else { return };
        if self.ground.is_some() && self.index(n).is_some_and(|i| self.members[i].alive) {
            self.calls.push((now, Call { from: n, id: "alpha" }));
        }
    }

    /// The hostile jets this frame (the host's: every live jet of the other side, each with its id). A bandit an order
    /// named that is gone from the list is gone (destroyed, out of the world).
    pub fn bandits(&mut self, list: Vec<Bandit>) {
        self.bandits = list;
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

    /// An enemy pair's vector this frame: the ground's track as the network reckons it and the id of the jet it tracks
    /// (0 unknown); None, none. Its lead fights that jet, else the bandit nearest the pair; a jet knows a bandit as it
    /// is only while its radar holds it ([`RADAR`], through its jammer) or its pilot sees it.
    pub fn gci(&mut self, track: Option<Bogey>, id: u32) {
        self.gci = track.map(|t| (t, id));
    }

    /// An enemy jet `number`'s weapons this frame (the host's): its selected missile's envelope against the bogey (m:
    /// max, min), a missile left, its own missile flying at the bogey.
    pub fn weapons(&mut self, number: u8, dlz: (f64, f64), armed: bool, in_air: bool) {
        if let Some(i) = self.index(number) {
            let e = &mut self.members[i].enemy;
            (e.dlz, e.armed, e.in_air) = (dlz, armed, in_air);
        }
    }

    /// Jet `number`'s selected missile homes on infrared ([`Enemy::ir`](crate::fighter::Enemy::ir)).
    pub fn weapon_ir(&mut self, number: u8, ir: bool) {
        if let Some(i) = self.index(number) {
            self.members[i].enemy.ir = ir;
        }
    }

    /// An AWACS contact call (fctrl.rs) at `now`: the contact's compass bearing (deg) and range (NM) from the player's
    /// jet (else the lead's); `enemy`: hostile or unidentified. The first AI jet by number holding it in its radar
    /// reports "contact" after its reaction time: a bandit at the point as this decision's radar holds it
    /// ([`radar_holds`]), else the point in its radar's reach and cone ([`RADAR`]). Returns its number, 0 for none.
    pub fn awacs(&mut self, now: f64, bearing_deg: f64, miles: f64, enemy: bool) -> u8 {
        let Some(from) = self.members.iter().find(|m| !m.ai).or(self.members.get(self.lead)) else { return 0 };
        if !enemy {
            return 0;
        }
        let b = bearing_deg.to_radians();
        let at = from.v.pos + Vec3::new(b.sin(), b.cos(), 0.0) * (miles * 1852.0);
        let near = self.bandits.iter().find(|b| flat(b.pos, at) < sort::GROUP_M).map(|b| b.id);
        let holds = |m: &Member| near.map_or_else(|| in_radar(m, at), |id| m.radar.contains(&id));
        // (Answered by the first jet that holds it; the memory of the bandits called is the contact calls'.)
        let Some(m) =
            self.members.iter().find(|m| m.ai && m.alive && m.airborne && !m.landed && !m.defending && holds(m))
        else {
            return 0;
        };
        // (A bandit at the called point that a jet already called is not called again; it is called now.)
        if let Some(id) = near {
            if self.reported.contains(&id) {
                return 0;
            }
            self.reported.push(id);
        }
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
        let now = self.now;
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
        m.phase = ap.phase();
        m.to_go = ap.to_go(m.v.pos);
        // An AI jet: TakeoffCL ended (or it started in the air); the player: off the ground once.
        m.airborne = if m.ai { ap.airborne || m.airborne && !m.v.on_ground } else { m.airborne || !m.v.on_ground };
        m.landed = ap.landed;
        m.engine_on = fm.engine_on();
        m.engine_since = if m.engine_on { m.engine_since.or(Some(now)) } else { None };
        m.fuel_kg = s.fuel_kg;
        m.wp_index = ap.wp_index;
        m.wp_action = ap.route.get(ap.wp_index).map_or(0, |w| w.action);
    }

    /// The tower's start-up clearance: the wingmen start their engines, one after the other.
    pub fn start_up(&mut self, now: f64) {
        self.cleared.get_or_insert(now);
    }

    /// An AI lead's plan (a lesson's `lead_plan`, modern-iaf/docs/data-formats.md §5): each order given once the lead
    /// has passed its waypoint ([`Flight::lead_order`]). The player as the lead has no plan.
    pub fn set_plan(&mut self, plan: Vec<(usize, LeadStep)>) {
        self.plan = plan;
    }

    /// The shape now ([`SHAPES`]' index) and whether its sides are mirrored by the tactical turns flown.
    pub fn shape(&self) -> (usize, bool) {
        (self.shape, self.mirror)
    }

    /// The flight for the instructor's calls (training.md §16.3): the player, a wingman, in its slot (within the
    /// in-position distance, no turn under way); every other live jet in position (in the air in its slot, not
    /// changing slots; the lead counts as in); every live jet down after its flight (an AI jet stopped after its
    /// landing roll, the player on the ground after its take-off). A lost jet counts for neither.
    pub fn facts(&self) -> (bool, bool, bool) {
        let k = self.spacing() as f32;
        let in_pos = |m: &Member| m.airborne && !m.v.on_ground && !m.transit && m.slot_error < IN_POSITION_M * k;
        let lead = self.members.get(self.lead).map(|m| m.number);
        let me = self.members.iter().find(|m| !m.ai);
        let in_slot = me.is_some_and(|m| Some(m.number) != lead && in_pos(m) && self.tac.is_none());
        let live = || self.members.iter().filter(|m| m.alive);
        let joined = live().all(|m| Some(m.number) == lead || in_pos(m));
        let down = live().all(|m| m.airborne && m.v.on_ground && (m.landed || !m.ai));
        (in_slot, joined, down)
    }

    /// A tactical turn under way ([`LeadStep::Turn`]).
    pub fn turning(&self) -> bool {
        self.tac.is_some()
    }

    /// The lead's order `step` at `now`, said by the lead ([`LEAD_CALLS`]) and acknowledged by each AI wingman in
    /// the air: a shape (the rejoin: fingertip), a close-up step, or a tactical turn (the lead in the air with the gear
    /// up). False: refused (a turn under way, the lead on the ground, close up past the last step).
    pub fn lead_order(&mut self, now: f64, step: LeadStep) -> bool {
        let Some(lead) = self.members.get(self.lead) else { return false };
        if !wingman::flying(lead) || self.tac.is_some() {
            return false;
        }
        let call = match step {
            // (A new shape is flown as drawn: the sides the turns swapped go back.)
            LeadStep::Shape(s) if s < SHAPES.len() => {
                (self.shape, self.split, self.mirror) = (s, None, false);
                LEAD_CALLS[s]
            }
            LeadStep::Shape(_) => return false,
            LeadStep::Rejoin => {
                (self.shape, self.split, self.mirror) = (0, None, false);
                LEAD_CALLS[8]
            }
            LeadStep::Close | LeadStep::Spread => {
                let up = step == LeadStep::Close;
                let c = if up { self.close + 1 } else { self.close.wrapping_sub(1) };
                if c >= CLOSE_STEPS.len() || matches!(self.shape, LINE_ABREAST | TRAIL) {
                    return false;
                }
                self.close = c;
                LEAD_CALLS[if up { 9 } else { 10 }]
            }
            LeadStep::Turn { right, in_place } => {
                let l = &self.members[self.lead];
                let from = l.v.vel[0].atan2(l.v.vel[1]);
                let sign = if right { 1.0 } else { -1.0 };
                let turn = if in_place { std::f64::consts::PI } else { std::f64::consts::FRAC_PI_2 };
                // The outside jet: the farthest from the turn's side (the lead's right: (cos h, -sin h)).
                let across = |m: &Member| {
                    let d = m.v.pos - l.v.pos;
                    sign * (d[0] * from.cos() - d[1] * from.sin())
                };
                let flying: Vec<&Member> = self.members.iter().filter(|m| m.alive && wingman::flying(m)).collect();
                let outside = flying.iter().map(|m| across(m)).fold(f64::MAX, f64::min);
                let wait = (flying.iter())
                    .map(|m| {
                        (m.number, if in_place { 0.0 } else { (across(m) - outside) / m.v.speed.max(50.0) as f64 })
                    })
                    .collect();
                let to = from + sign * turn;
                self.tac = Some(Tac { at: now, from, to, right, wait, started: vec![], done: vec![] });
                self.mirror = !self.mirror;
                LEAD_CALLS[11 + 2 * in_place as usize + !right as usize]
            }
        };
        let lead_n = self.members[self.lead].number;
        self.calls.push((now, Call { from: lead_n, id: call }));
        for m in self.members.iter_mut().filter(|m| m.number != lead_n && m.alive && m.airborne && !m.landed) {
            (m.transit, m.report) = (true, true);
            if m.ai {
                self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: "ack" }));
            }
        }
        true
    }

    /// The plan's next order once the lead has passed its waypoint; the tactical turn under way: who starts now (its
    /// wait over), who has turned, and its end (every jet turned, or [`TAC_MAX_S`]). Each AI jet's
    /// steer this decision while it turns (its old heading until it starts), by number.
    fn tac_step(&mut self, now: f64) -> Vec<(u8, Steer)> {
        if self.tac.is_none()
            && let Some(&(wp, step)) = self.plan.first()
            && self.members.get(self.lead).is_some_and(|l| l.ai && l.wp_index > wp)
        {
            self.plan.remove(0);
            self.lead_order(now, step);
        }
        let Some(t) = self.tac.as_mut() else { return vec![] };
        use std::f64::consts::{FRAC_PI_2, PI, TAU};
        let track = |m: &Member| m.v.vel[0].atan2(m.v.vel[1]);
        let mut out = vec![];
        for m in self.members.iter().filter(|m| m.alive && wingman::flying(m)) {
            let due = t.wait.iter().find(|w| w.0 == m.number).is_none_or(|w| now - t.at >= w.1);
            if !t.started.contains(&m.number) && due {
                t.started.push(m.number);
            }
            let sign = if t.right { 1.0 } else { -1.0 };
            // The turn left in its way (0 to 2π; past the new heading a little: 0).
            let left = (sign * (t.to - track(m))).rem_euclid(TAU);
            let left = if left > 1.5 * PI { 0.0 } else { left };
            if t.started.contains(&m.number) && left <= TURNED_DEG.to_radians() && !t.done.contains(&m.number) {
                t.done.push(m.number);
            }
            let aim = if !t.started.contains(&m.number) {
                t.from
            } else if t.done.contains(&m.number) {
                t.to
            } else {
                track(m) + sign * left.min(FRAC_PI_2)
            };
            let to = m.v.pos + Vec3::new(aim.sin(), aim.cos(), 0.0) * 20_000.0;
            out.push((m.number, Steer { to, g: TAC_G, speed: m.v.speed, thr_max: 1.0, fighter: false }));
        }
        let all = self.members.iter().filter(|m| m.alive && wingman::flying(m)).all(|m| t.done.contains(&m.number));
        if all || now - t.at > TAC_MAX_S {
            self.tac = None;
            return vec![];
        }
        out
    }

    /// The take-off in pairs (true) or in a stream behind the lead (false, the default): #2 lines up beside #1 and #4
    /// beside #3, [`PAIR_M`] apart on the side of their slot in the shape; an AI element lead waits on the runway until
    /// its wingman is lined up (at most [`PAIR_WAIT_S`]), and the wingman rolls with it.
    pub fn pairs(&mut self, on: bool) {
        self.pairs = on;
    }

    /// Jet `n`'s station on the tanker this frame (the tanker as its leader, its slot on it; tanker.rs `slot`), set
    /// by the host each frame while the jet is [`Member::refuelling`]; None: the tanker is through with it (done, or
    /// gone): the jet rejoins its slot in the flight.
    pub fn set_refuel(&mut self, n: u8, station: Option<(Leader, [f32; 3])>) {
        let Some(m) = self.members.iter_mut().find(|m| m.number == n) else { return };
        if station.is_none() && m.refuelling {
            (m.refuelling, m.transit, m.report) = (false, true, true);
            // Refuelled: its fuel's RTB and joker / bingo calls are over (an RTB the lead ordered stays while the fuel
            // is short of joker); each call is armed again once the fuel is above its mark, RTB or not.
            let joker = m.fuel_kg > m.bingo_kg + JOKER_KG;
            if m.rtb && !m.released && joker {
                m.rtb = false;
            }
            m.called = [m.called[0] && !joker, m.called[1] && m.fuel_kg <= m.bingo_kg];
        }
        m.refuel = station;
    }

    /// A radio command (design §4) to `to`: 0 the flight, 5 the element (#3, #4), 2..4 one wingman. Returns false for
    /// an unknown command or nobody to take it; the answers come as calls. "close_up" / "spread_out" to the flight
    /// take the close shapes one step of [`CLOSE_STEPS`] in or out; "unable" at the last step, in line abreast or
    /// trail, or to one jet or the element. "low" / "high" to the flight set and end
    /// its low level at [`LOW_ORDER_M`] ([`Flight::low`]); they return false when no jet took them.
    pub fn command(&mut self, now: f64, to: u8, cmd: &str) -> bool {
        // The regroup: element 2 rejoins (from a split).
        let (to, cmd) = if cmd == "regroup" { (5, "rejoin") } else { (to, cmd) };
        if !self.player_may_order(to) {
            return false;
        }
        let who = self.addressed(to);
        if who.is_empty() {
            return false;
        }
        let shape = SHAPES.iter().position(|s| s.0 == cmd);
        // Close up / spread out: one step of [`CLOSE_STEPS`], in a close shape, to the flight.
        let step = match cmd {
            "close_up" => (self.close + 1 < CLOSE_STEPS.len()).then_some(self.close + 1),
            "spread_out" => self.close.checked_sub(1),
            _ => None,
        }
        .filter(|_| to == 0 && !matches!(self.shape, LINE_ABREAST | TRAIL));
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
                    (m.refuelling, m.refuel) = (false, None);
                    m.end_order();
                    if m.number == 3 {
                        self.split = None;
                    }
                    "ack"
                }
                "rtb" if flying => {
                    (m.rtb, m.tactic, m.assigned, m.bandit) = (true, Tactic::None, None, None);
                    // Sent home from the tanker: it leaves the tanker's queue (tanker.gd) and goes.
                    (m.refuelling, m.refuel) = (false, None);
                    "ack"
                }
                // Cover (defend the lead): it keeps its slot and fights a bandit that attacks the lead (decide); with
                // something to shoot. It ends the order it had.
                "cover" if flying && !m.rtb && !m.winchester => {
                    m.end_order();
                    m.tactic = Tactic::Cover;
                    "ack"
                }
                "low" | "high" if to == 0 && flying => "ack",
                // To the tanker (the host asks for each in turn, tanker.rs): it flies the tanker's stations once the
                // host gives them (set_refuel).
                // (A jet going home for its fuel may refuel: the end of its refuelling ends that RTB, set_refuel.)
                "refuel" if flying && !m.released => {
                    m.refuelling = true;
                    "ack"
                }
                "close_up" | "spread_out" if step.is_some() && flying => "ack",
                "rejoin" | "rtb" | "cover" | "low" | "high" | "close_up" | "spread_out" | "refuel" => "unable",
                _ => return false,
            };
            acked |= answer == "ack";
            self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: answer }));
        }
        if let Some(c) = step.filter(|_| acked) {
            self.close = c;
            for m in self.members.iter_mut().filter(|m| m.airborne && !m.landed) {
                m.report = true;
            }
        }
        if let Some(s) = shape.filter(|_| acked) {
            self.shape = s;
            for m in self.members.iter_mut().filter(|m| m.airborne && !m.landed) {
                (m.transit, m.report) = (true, true);
            }
        }
        if cmd == "low" || cmd == "high" {
            if acked {
                self.low((cmd == "low").then_some(LOW_ORDER_M));
            }
            return acked;
        }
        true
    }

    /// One frame: the decisions every [`DECIDE_S`], each member's order (its leader and slot every frame); returns
    /// the calls now due.
    pub fn step(&mut self, now: f64) -> Vec<Call> {
        self.step_on(now, &|_| None)
    }

    /// [`Flight::step`] over the terrain's height `terrain` (None: sea level): the radars' sight and look-down.
    pub fn step_on(&mut self, now: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> Vec<Call> {
        if self.members.is_empty() {
            return Vec::new();
        }
        for m in &mut self.members {
            m.order.start_engine = false;
            m.order.wp_index = None;
            m.order.release = false;
        }
        if now >= self.next {
            self.next = now + DECIDE_S;
            self.scan(terrain);
            self.decide(now);
        }
        self.watch_parade(now);
        self.feed(now);
        let (due, later) = std::mem::take(&mut self.calls).into_iter().partition(|(t, _)| *t <= now);
        self.calls = later;
        due.into_iter().map(|(_, c)| c).collect::<Vec<_>>()
    }

    /// Each jet's radar this decision: the bandits it holds and the jammers it sees as strobes (none on the ground).
    fn scan(&mut self, terrain: &dyn Fn(Vec3) -> Option<f64>) {
        for m in &mut self.members {
            let up = m.alive && !m.v.on_ground;
            let holds: Vec<u32> =
                self.bandits.iter().filter(|b| up && radar_holds(m, b, terrain)).map(|b| b.id).collect();
            let strobes = (self.bandits.iter())
                .filter(|b| up && b.jam > 0.0 && !holds.contains(&b.id) && in_radar(m, b.pos))
                .filter(|b| site::visible(m.v.pos, b.pos, terrain))
                .map(|b| b.id)
                .collect();
            (m.radar, m.strobes) = (holds, strobes);
        }
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
            && let Some(m) =
                self.members.iter_mut().find(|m| m.alive && m.rtb && !m.released && !m.refuelling && m.number != lead_n)
        {
            (m.released, m.released_at) = (true, now);
            self.last_release = now;
        }
        // The jets going home keep their spacing on the way to the lineup, in the order they were sent home (an AI
        // lead first; the player's own landing has no track): each behind the one sent just before it, slower while
        // it is short of that or ahead of it.
        let lead_i = self.lead;
        let sent = |i: usize, m: &Member| if i == lead_i { f64::MIN } else { m.released_at };
        let going: Vec<(f64, f64, f32)> = (self.members.iter().enumerate())
            .filter(|(i, m)| m.alive && m.airborne && !m.landed && (*i == lead_i || m.released))
            .filter_map(|(i, m)| Some((sent(i, m), m.to_go?, m.v.speed)))
            .collect();
        for (i, m) in self.members.iter_mut().enumerate() {
            let me = (m.ai && m.alive && m.airborne && !m.landed && m.released && i != lead_i)
                .then_some((m.released_at, m.to_go))
                .and_then(|(t, d)| Some((t, d?)));
            let ahead = me.and_then(|(t, d)| {
                let a = going.iter().filter(|g| g.0 < t).max_by(|a, b| a.0.total_cmp(&b.0))?;
                Some((d - a.1, a.2))
            });
            m.order.pace = ahead.and_then(|(gap, v)| {
                let short = SPACING.0 * v as f64 - gap;
                (short > 0.0).then(|| (v - (SPACING.1 * short) as f32).max(SPACING.2))
            });
        }
        let tac = self.tac_step(now);
        // An AI lead with the player in its flight starts, taxies and takes off with it: it taxies once every other
        // jet has run its engine [`TAXI_AFTER_S`] (any other AI lead stays on the ground as before).
        let led_player = self.members[self.lead].ai && self.members.iter().any(|m| !m.ai);
        let lead_i = self.lead;
        let waiting = (self.members.iter().enumerate()).any(|(i, m)| {
            i != lead_i
                && m.alive
                && m.v.on_ground
                && !m.airborne
                && m.engine_since.is_none_or(|t| now - t < TAXI_AFTER_S)
        });
        (self.members[lead_i].flight_wait, self.members[lead_i].leads_player) = (waiting, led_player);
        let committed = self.members[self.lead].enemy.committed;
        let lead_striking = matches!(self.members[self.lead].strike.phase, Phase::Run | Phase::Egress);
        // The bandits: the flight's picture; our flight's orders kept up (and its contact calls), an enemy pair's share.
        let picture: Vec<u32> =
            self.bandits.iter().filter(|b| self.members.iter().any(|m| sees(m, b))).map(|b| b.id).collect();
        self.picture = picture;
        let enemy_lead = if self.station.is_some() { self.share(committed) } else { None };
        let supports = if self.station.is_none() { self.upkeep(now) } else { vec![false; self.members.len()] };
        let lead_attackers: Vec<u32> =
            self.bandits.iter().filter(|b| attacks_lead(&self.members[self.lead], b)).map(|b| b.id).collect();
        let mut shooters = Vec::new();
        let lead_pos = self.members[self.lead].v.pos;
        let base = self.slots();
        let (k, kg) = (self.spacing(), self.guard());
        let (clear, in_position) = ((CLEAR_M.0 * kg, CLEAR_M.1 * kg), IN_POSITION_M * k as f32);
        let table = |n: u8| if (2..=4).contains(&n) { base[n as usize - 2] } else { [0.0; 3] };
        let home = self.home;
        for (i, &support) in supports.iter().enumerate() {
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
                .filter(|o| !pair_free(me, o))
                .map(|o| o.v.pos.distance(me.v.pos))
                .fold(f64::MAX, f64::min);
            let busy = (0..self.members.len()).any(|j| j != i && self.members[j].strike.phase == Phase::Run);
            let m = &mut self.members[i];
            m.run_busy = busy;
            let t = table(m.number);
            m.slot = [t[0] - lead_slot[0], t[1] - lead_slot[1], t[2] - lead_slot[2]];
            let mut rejoin = None;
            if i != self.lead {
                let s = autopilot::slot_point(&ld, m.slot);
                let flat_err = flat(s, m.v.pos) as f32;
                m.slot_error = s.distance(m.v.pos) as f32;
                // Too near another jet: step down as in a change of slots (the higher number gives way: its step is
                // the larger), until in its slot and clear.
                if nearest < clear.0 && m.mode == MODE_SLOT {
                    m.transit = true;
                } else if m.transit && flat_err < in_position && nearest > clear.1 {
                    m.transit = false;
                }
                if m.report && !m.transit && m.slot_error < in_position && m.mode == MODE_SLOT {
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
            m.lead_striking = lead_striking && i != self.lead;
            m.cleared = self.cleared;
            m.ahead_moved = ahead_moved;
            m.bingo_kg = RESERVE_KG + KG_PER_KM * home.map_or(0.0, |h| flat(h, m.v.pos) as f32 / 1000.0);
            if !m.alive || m.rtb || m.released {
                m.end_order();
            }
            m.strike.target = self.ground.filter(|_| m.strike.phase != Phase::None);
            (m.order.mode, m.order.decoy, m.order.shoot, m.order.gun) = (None, None, false, false);
            let bandits = &self.bandits;
            let find = |id: Option<u32>| id.and_then(|id| bandits.iter().find(|b| b.id == id));
            let mut orbit = None;
            (m.low, m.order.follow, m.order.low) = (self.low, self.low, self.low.is_some());
            if let Some(st) = self.station {
                // An enemy jet: the lead on the ground's vector's jet (else the nearest), a wingman on its share once
                // the pair has committed ([`Flight::share`]); the bandit as its radar and its pilot see it.
                let id = if i != self.lead && committed { m.assigned.or(enemy_lead) } else { enemy_lead };
                let known = self.gci.filter(|_| id == enemy_lead).map(|g| g.0);
                m.bandit = id;
                know(m, st, known, find(id), now);
                if i != self.lead {
                    m.enemy.committed = committed;
                }
            } else {
                // One of our wingmen (an AI lead, promoted, has none): its order's bandit (a holding wingman only once
                // cleared), else a bandit that attacks it (its own defence), else, covering, one that attacks the lead.
                let fit = i != self.lead && can_fight(m);
                let near = |b: &&Bandit| b.pos.distance(m.v.pos);
                // (A fight begun in its own defence goes on while the attacker stays inside the dogfight's reach.)
                let kept = find(m.bandit).filter(|b| {
                    let own = m.enemy.committed && m.assigned != Some(b.id) && m.tactic != Tactic::Cover;
                    own && b.pos.distance(m.v.pos) < 1.5 * bfm::BFM_M
                });
                let attacker = bandits.iter().filter(|b| attacked(m, b)).min_by(|a, b| near(a).total_cmp(&near(b)));
                let attacker = attacker.or(kept).map(|b| b.id);
                if m.holding && (m.rwr || attacker.is_some()) {
                    m.holding = false;
                }
                let ordered = matches!(m.tactic, Tactic::Engage | Tactic::Sort | Tactic::Free);
                let bandit = if !fit {
                    None
                } else if let Some(id) = m.assigned.filter(|_| ordered && !m.holding) {
                    Some(id)
                } else if attacker.is_some() {
                    attacker
                } else if m.holding {
                    m.assigned
                } else if m.tactic == Tactic::Cover {
                    let kept = find(m.bandit).filter(|b| flat(b.pos, lead_pos) <= COVER_M).map(|b| b.id);
                    kept.or(lead_attackers.first().copied())
                } else {
                    None
                };
                let committed = bandit.is_some() && !(m.holding && bandit == m.assigned);
                let given = matches!(m.tactic, Tactic::Engage | Tactic::Sort) && bandit == m.assigned;
                if committed && bandit != m.bandit && !given {
                    m.calls.push("engaged");
                }
                if bandit.is_none() && m.bandit.is_some() {
                    (m.transit, m.report) = (true, true);
                }
                m.bandit = bandit;
                // An order's bandit and the lead's attacker are known by the data link (the flight's picture, the
                // lead's RWR); its own attacker only by its own radar and eyes.
                let linked = bandit != attacker || bandit == m.assigned;
                let truth = find(bandit);
                know(m, lead_pos, truth.filter(|_| linked).map(Bandit::bogey), truth, now);
                m.enemy.committed = committed;
                // Weapons free with nothing to hunt: round its area's point (a supporting wingman keeps its slot).
                if m.tactic == Tactic::Free && !committed && !support {
                    let to = m.area.map(|a| Vec3::new(a[0], a[1], m.v.pos[2]));
                    let speed = m.v.speed.max(200.0);
                    orbit = to.map(|to| Steer { to, g: TASK_G, speed, thr_max: 1.0, fighter: false });
                }
            }
            let turn = tac.iter().find(|t| t.0 == m.number).map(|t| t.1);
            // (The lead's own task is its tactical turn only: a promoted lead keeps no wingman's orbit or split.)
            let own =
                if i == self.lead { turn } else { turn.or(orbit).or(if m.number == 3 { self.split } else { None }) };
            m.rejoining = own.is_none() && rejoin.is_some();
            m.task = own.or(rejoin);
            if i == self.lead {
                self.lead_tree.tick(m)
            } else {
                self.wingman.tick(m)
            };
            if m.order.shoot || m.order.gun {
                m.last_shot = now;
                shooters.push(m.number);
            }
            for id in m.calls.drain(..) {
                self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id }));
            }
        }
        for n in shooters {
            self.fired(n);
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
        self.pairs_take_off(now);
        self.tower_calls(now);
    }

    /// A pairs take-off's bookkeeping: each AI jet's time lined up on the runway, and a wingman lined up beside its
    /// lead flies free of the lead's collision avoidance until [`PAIR_FREE`].
    fn pairs_take_off(&mut self, now: f64) {
        for i in 0..self.members.len() {
            let n = self.members[i].number;
            let lead_pos = self.index(n.wrapping_sub(1)).map(|j| self.members[j].v.pos).filter(|_| n.is_multiple_of(2));
            // The player as a pair's wingman: lined up once stopped on the ground within 40 m of its lead lined up.
            let lead_lined = (self.index(n.wrapping_sub(1)).map(|j| &self.members[j]))
                .filter(|l| n.is_multiple_of(2) && l.lined_up.is_some())
                .map(|l| l.v.pos);
            let m = &mut self.members[i];
            let player_lined =
                !m.ai && m.v.on_ground && m.v.speed < 2.0 && lead_lined.is_some_and(|p| flat(p, m.v.pos) < 40.0);
            let on_runway = m.mode == MODE_TAKE_OFF && m.phase == Some(1) || player_lined;
            m.lined_up = if on_runway { Some(m.lined_up.unwrap_or(now)) } else { None };
            if self.pairs && on_runway && m.v.on_ground && m.order.lineup_offset != 0.0 && m.pair_free.is_none() {
                m.pair_free = Some(None);
            }
            if let Some(free) = m.pair_free {
                let since = free.or((!m.v.on_ground).then_some(now));
                let apart = lead_pos.is_none_or(|p| p.distance(m.v.pos) > PAIR_FREE.0);
                let over = since.is_some_and(|t| now - t > PAIR_FREE.1 || apart && !m.v.on_ground);
                m.pair_free = (!over && m.alive).then_some(since);
            }
        }
    }

    /// The tower's landing calls to our AI jets (not an enemy flight's: [`Flight::enemy`]): "cleared to land" on the
    /// turn to final, "taxi to parking" once the landing roll has stopped.
    fn tower_calls(&mut self, now: f64) {
        if self.station.is_some() {
            return;
        }
        for m in self.members.iter_mut().filter(|m| m.ai && m.alive) {
            if m.mode == MODE_GO_HOME && m.phase.is_some_and(|p| p >= TURN_FINAL) && !m.landed && !m.tower[0] {
                m.tower[0] = true;
                self.calls.push((now, Call { from: m.number, id: "tower_land" }));
            }
            if m.landed && !m.tower[1] {
                m.tower = [true; 2];
                self.calls.push((now, Call { from: m.number, id: "tower_park" }));
            }
        }
    }

    /// Each AI jet's leader this frame: on the ground the jet ahead in taxi order (TaxiCL's spacing, TakeoffCL's
    /// stream), in the air the flight lead; its slot, stepped down during a change of slots.
    fn feed(&mut self, now: f64) {
        let t = SHAPES[self.shape].1;
        let (k, kg) = (self.spacing(), self.guard());
        let side = |n: u8| {
            let right = if n == 2 { t[0][1] } else { t[2][1] - t[1][1] };
            if right > 0.0 { PAIR_M } else { -PAIR_M }
        };
        for i in 0..self.members.len() {
            let hold = self.taxi_hold(i) || self.pair_hold(i, now);
            self.members[i].order.hold_short = self.backtrack_hold(i);
            let n = self.members[i].number;
            let mate = self.index(n + 1).map(|j| &self.members[j]);
            // (Until the lead's own lift-off: a wingman off the ground a moment first leaves its stage on the runway.)
            let rolling = self.members[i].lined_up.is_some();
            let mate_up = |o: &Member| o.lined_up.is_some() || o.airborne;
            let pair_lead = self.pairs && n % 2 == 1 && rolling && mate.is_some_and(|o| o.alive && mate_up(o));
            self.members[i].order.pair_lead = pair_lead;
            self.members[i].order.hold = hold;
            self.members[i].order.lineup_offset = if self.pairs && n.is_multiple_of(2) { side(n) } else { 0.0 };
            let a = self.avoid(i);
            let ld = leader_of(&self.members[self.leader_index(i)]);
            let m = &mut self.members[i];
            let in_slot = m.mode == MODE_SLOT && !m.transit && m.slot_error < IN_POSITION_M * k as f32;
            m.avoiding = a.is_some_and(|(miss, _, closing)| {
                if !m.avoiding {
                    miss < AVOID_M * kg
                } else {
                    miss < AVOID_CLEAR_M * kg && (closing || miss < AVOID_SLOT_CLEAR_M * kg || !in_slot)
                }
            });
            // On the tanker the stations keep the jets apart (tanker.rs): no pull-away from one another there.
            if m.refuelling && m.refuel.is_some() {
                m.avoiding = false;
            }
            m.order.avoid = a.filter(|_| m.avoiding).map(|(_, away, _)| away);
            let ahead = (0..i).rev().map(|j| &self.members[j]).find(|a| a.alive).map(leader_of);
            let m = &mut self.members[i];
            let ground = m.v.on_ground && !m.airborne || m.mode == MODE_TAKE_OFF && !m.airborne;
            m.order.leader = if ground { ahead } else { Some(ld) };
            m.order.slot = m.slot;
            (m.order.close, m.order.precise) = (k < 1.0, false);
            // The dogfight's point follows the bogey every frame while it is in sight.
            let b = m.bandit.and_then(|id| self.bandits.iter().find(|b| b.id == id)).map(Bandit::bogey);
            if let (Some((aim, lay)), Some(b)) = (m.enemy.aim, b.filter(|_| m.enemy.visual)) {
                let to = bfm::aim_point(m.v.pos, &b, &aim, lay, bfm::floor(m));
                if let Some(s) = m.order.steer.as_mut() {
                    s.to = to;
                }
            }
            if let Some((ld, slot)) = m.refuel.filter(|_| m.refuelling) {
                // On the tanker's station: its leader and slot, flown close; no step down; the station's gains once
                // near it (far off they overshoot: a jet 700 m behind swung ±500 m round its station at full throttle).
                (m.order.leader, m.order.slot, m.order.close, m.transit, m.report) =
                    (Some(ld), slot, true, false, false);
                m.order.precise = autopilot::slot_point(&ld, slot).distance(m.v.pos) < PRECISE_M;
            } else if m.transit {
                m.order.slot[2] -= TRANSIT_STEP * (m.number as f32 - 1.0);
            }
        }
    }
}

impl Flight {
    /// Member `i`, an AI jet taxiing in: another jet of the flight on the ground with its engine running ahead of it
    /// on its way ([`TAXI_HOLD_M`]). Two jets taxiing in that each have the other ahead (head on): the higher number
    /// holds.
    fn taxi_hold(&self, i: usize) -> bool {
        let taxiing_in = |m: &Member| m.ai && m.alive && m.airborne && m.v.on_ground && m.mode == MODE_GO_HOME;
        let me = &self.members[i];
        if !taxiing_in(me) {
            return false;
        }
        let in_way = |a: &Member, b: &Member| {
            let (d, h) = (b.v.pos - a.v.pos, a.v.att.heading as f64);
            let along = d[0] * h.sin() + d[1] * h.cos();
            let across = d[0] * h.cos() - d[1] * h.sin();
            along > 0.0 && along < TAXI_HOLD_M.0 && across.abs() < TAXI_HOLD_M.1
                || along > -10.0 && along.hypot(across) < TAXI_HOLD_M.2
        };
        self.members.iter().any(|o| {
            // Each in the other's way: the higher number holds.
            let holds_for_me = taxiing_in(o) && in_way(o, me) && o.number > me.number;
            o.number != me.number && o.alive && o.v.on_ground && o.engine_on && in_way(me, o) && !holds_for_me
        })
    }

    /// Member `i`, an AI jet taxiing out on a base the tower turned into the wind ([`Flight::entry`]): it holds within
    /// [`BACKTRACK_HOLD_M`] of the runway entry while a jet ahead of it in order is still on the ground with its
    /// engine running (backtracking, lined up or rolling back toward the entry), so no jet meets another head on on
    /// the runway (docs/ai.md §8.7). A pairs wingman goes down the runway with its element lead.
    fn backtrack_hold(&self, i: usize) -> bool {
        let me = &self.members[i];
        let Some(e) = self.entry else { return false };
        let out =
            me.ai && me.alive && me.v.on_ground && !me.airborne && me.mode == MODE_TAKE_OFF && me.lined_up.is_none();
        if !out || (me.v.pos[0] - e[0]).hypot(me.v.pos[1] - e[1]) > BACKTRACK_HOLD_M {
            return false;
        }
        let mate = |o: &Member| self.pairs && me.number.is_multiple_of(2) && o.number + 1 == me.number;
        self.members
            .iter()
            .any(|o| o.number < me.number && o.alive && o.v.on_ground && o.engine_on && !o.airborne && !mate(o))
    }

    /// Member `i`, an AI element lead (#1, #3) lined up for a pairs take-off: it waits on the runway while its AI
    /// wingman, alive and still on the ground, is not yet lined up beside it, at most [`PAIR_WAIT_S`].
    fn pair_hold(&self, i: usize, now: f64) -> bool {
        let me = &self.members[i];
        let mate = self.index(me.number + 1).map(|j| &self.members[j]);
        // (The player as its wingman: no limit; the lesson waits for the student.)
        let player = mate.is_some_and(|o| !o.ai);
        let waiting = me.lined_up.is_some_and(|t| player || now - t < PAIR_WAIT_S);
        if !(self.pairs && me.ai && me.number % 2 == 1 && waiting) {
            return false;
        }
        mate.is_some_and(|o| o.alive && !o.airborne && o.lined_up.is_none())
    }

    fn bandit(&self, id: Option<u32>) -> Option<&Bandit> {
        id.and_then(|id| self.bandits.iter().find(|b| b.id == id))
    }

    /// The jets of the group (bandits within [`sort::GROUP_M`] of each other, [`sort::groups`]) that bandit `id` is in,
    /// of `among`; `id` itself when it is not among them.
    fn group_of(&self, id: u32, among: &[Bandit]) -> Vec<Bandit> {
        let pts: Vec<Vec3> = among.iter().map(|b| b.pos).collect();
        let g = sort::groups(&pts).into_iter().find(|g| g.iter().any(|&k| among[k].id == id));
        match g {
            Some(g) => g.into_iter().map(|k| among[k]).collect(),
            None => self.bandit(Some(id)).into_iter().copied().collect(),
        }
    }

    /// Which of `group`'s jets the jets `who` (indices) take, by [`sort::deal`], with jet `who[0]` held on `first`
    /// (its own bandit): the jet the deal gives it goes to whoever the deal put on `first`.
    fn deal_from(&self, who: &[usize], group: &[Bandit], first: u32) -> Vec<u32> {
        let pos: Vec<Vec3> = who.iter().map(|&i| self.members[i].v.pos).collect();
        let jets: Vec<Vec3> = group.iter().map(|b| b.pos).collect();
        let d = sort::deal(&pos, &jets);
        let swap = group.get(d[0]).map_or(first, |b| b.id);
        d.iter().map(|&k| group.get(k).map_or(first, |b| b.id)).map(|id| if id == first { swap } else { id }).collect()
    }

    /// An enemy pair's share: its lead's bandit (the ground's vector's jet while it is one, else the bandit nearest a
    /// jet of the pair, kept once committed while it lives), returned; once the pair has committed, each wingman without a bandit of its own takes its share
    /// of the lead's bandit's group by [`sort::deal`] (the same rule as our flight's sort: two jets do not take one
    /// bandit while another flies free), kept until it is gone. Not committed: none of its own.
    fn share(&mut self, committed: bool) -> Option<u32> {
        let near = |b: &Bandit| {
            let live = self.members.iter().filter(|m| m.alive);
            live.map(|m| b.pos.distance(m.v.pos)).fold(f64::MAX, f64::min)
        };
        let vectored = self.gci.map(|g| g.1).filter(|&id| self.bandit(Some(id)).is_some());
        // (Committed, the lead keeps its bandit while it lives: a pilot does not switch to whichever is nearest.)
        let kept = self.members[self.lead].bandit.filter(|_| committed);
        let kept = self.bandit(kept).map(|b| b.id);
        let lead = if self.gci.is_some() {
            vectored
        } else {
            kept.or(self.bandits.iter().min_by(|a, b| near(a).total_cmp(&near(b))).map(|b| b.id))
        };
        let gone: Vec<usize> = (0..self.members.len())
            .filter(|&i| {
                let a = self.members[i].assigned;
                i != self.lead && (!committed || a == lead || self.bandit(a).is_none())
            })
            .collect();
        for &i in &gone {
            self.members[i].assigned = None;
        }
        if let Some(l) = lead.filter(|_| committed && !gone.is_empty()) {
            let group = self.group_of(l, &self.bandits);
            let who: Vec<usize> = std::iter::once(self.lead)
                .chain((0..self.members.len()).filter(|&i| i != self.lead && self.members[i].alive))
                .collect();
            let ids = self.deal_from(&who, &group, l);
            for (&i, id) in who.iter().zip(ids).skip(1) {
                if gone.contains(&i) {
                    self.members[i].assigned = Some(id);
                }
            }
        }
        lead
    }

    /// Our flight's orders kept up at `now` (docs/ai.md §8.11), before its jets decide: an engage's bandit gone ends
    /// it (the jet rejoins); a sort's gone, the jet takes the nearest bandit of the picture nobody has, else the
    /// nearest, else rejoins; weapons free ends at joker fuel, and drops a bandit gone or past [`FREE_KEEP`] ×
    /// [`FREE_R`] from the area's point, then hunts the next ([`Flight::free`]). Each AI jet calls "contact" for a
    /// bandit its radar finds first (once a bandit, one call a decision). Returns which jets support their element lead
    /// in a free hunt.
    fn upkeep(&mut self, now: f64) -> Vec<bool> {
        let n = self.members.len();
        let pic: Vec<Bandit> = self.bandits.iter().filter(|b| self.picture.contains(&b.id)).copied().collect();
        let taken = |f: &Flight, me: usize, id: u32| (0..n).any(|j| j != me && f.members[j].assigned == Some(id));
        let mut supports = vec![false; n];
        for i in 0..n {
            let m = &self.members[i];
            if i == self.lead || !m.ai {
                continue;
            }
            let gone = self.bandit(m.assigned).is_none();
            let pos = m.v.pos;
            let near = |b: &&Bandit| b.pos.distance(pos);
            let next = match m.tactic {
                Tactic::Engage if gone => None,
                Tactic::Sort if gone => {
                    let free = pic.iter().filter(|b| !taken(self, i, b.id)).min_by(|a, b| near(a).total_cmp(&near(b)));
                    free.or(pic.iter().min_by(|a, b| near(a).total_cmp(&near(b)))).map(|b| Some(b.id))
                }
                Tactic::Free if m.fuel_kg <= m.bingo_kg + JOKER_KG => None,
                Tactic::Free => {
                    let area = m.area.unwrap_or(pos);
                    let out = self.bandit(m.assigned).is_none_or(|b| flat(b.pos, area) > FREE_KEEP * FREE_R);
                    Some(if out { None } else { m.assigned })
                }
                _ => Some(m.assigned),
            };
            let m = &mut self.members[i];
            match next {
                Some(id) => m.assigned = id,
                None => {
                    // (A tactic: no attack, so this ends no attack.)
                    m.end_order();
                    (m.transit, m.report) = (true, true);
                }
            }
        }
        // The free hunts, in number order: a wingman whose element lead hunts takes its share of the lead's group;
        // another the nearest bandit of the picture in its area that no other jet has, else the nearest there.
        for i in (0..n).filter(|&i| i != self.lead) {
            let m = &self.members[i];
            if m.tactic != Tactic::Free || !can_fight(m) {
                continue;
            }
            let num = m.number;
            let el = num.is_multiple_of(2).then(|| self.index(num - 1)).flatten().filter(|&j| {
                let l = &self.members[j];
                j != self.lead && l.tactic == Tactic::Free && can_fight(l)
            });
            if let Some(j) = el {
                supports[i] = true;
                if self.members[i].assigned.is_none()
                    && let Some(l) = self.members[j].assigned
                {
                    let group = self.group_of(l, &self.bandits);
                    self.members[i].assigned = self.deal_from(&[j, i], &group, l).get(1).copied();
                }
                continue;
            }
            if m.assigned.is_some() {
                continue;
            }
            let (pos, area) = (m.v.pos, m.area.unwrap_or(m.v.pos));
            let near = |b: &&Bandit| b.pos.distance(pos);
            let inside: Vec<&Bandit> = pic.iter().filter(|b| flat(b.pos, area) <= FREE_R).collect();
            let free = inside.iter().filter(|b| !taken(self, i, b.id)).min_by(|a, b| near(a).total_cmp(&near(b)));
            let pick = free.or(inside.iter().min_by(|a, b| near(a).total_cmp(&near(b)))).map(|b| b.id);
            self.members[i].assigned = pick;
        }
        // The contacts: each AI jet in the air calls a bandit its own radar finds that no jet has called.
        for i in 0..n {
            let m = &self.members[i];
            if !m.ai || !m.alive || !wingman::flying(m) || m.defending {
                continue;
            }
            let found = self.bandits.iter().find(|b| !self.reported.contains(&b.id) && m.radar.contains(&b.id));
            if let Some(b) = found {
                self.reported.push(b.id);
                self.calls.push((now + m.skill.reaction_s, Call { from: m.number, id: "contact" }));
            }
        }
        supports
    }

    /// Member `i`, an AI jet in the air: the closest approach within [`AVOID_S`] to the jet it comes nearest to, m,
    /// and the way away from it (straight at it: the higher number goes down). Both go on as they turn and speed up
    /// now (their accelerations; in straight lines a jet released on afterburner from behind the lead was seen too
    /// late, 13–29 m from it), sampled every [`AVOID_STEP_S`] and at the straight lines' closest approach; and
    /// whether they still close (the closest approach later than now).
    fn avoid(&self, i: usize) -> Option<(f64, Vec3, bool)> {
        let me = &self.members[i];
        if !me.ai || !me.alive || me.v.on_ground {
            return None;
        }
        // (The look-ahead shrinks with the spacing: at the tight step, 0.8 s.)
        let (h, dt) = (AVOID_S * self.guard(), AVOID_STEP_S * self.guard());
        // (A lead keeps its line and leaves the room to its wingman: an AI lead takes no avoiding action from the
        // player flying on it.)
        let mine = |o: &Member| i == self.lead && !o.ai;
        let (miss, other, closing) = (self.members.iter())
            .filter(|o| o.number != me.number && o.alive && !o.v.on_ground && !pair_free(me, o) && !mine(o))
            .flat_map(|o| {
                let (op, ov) = (o.v.pos, o.v.vel);
                let (dp, dv, da) = (op - me.v.pos, ov - me.v.vel, o.acc - me.acc);
                // Also the straight lines' closest approach (head-on, a sample's step is 50 m).
                let straight = (-dp.dot(dv) / dv.dot(dv).max(1e-6)).clamp(0.0, h);
                let steps = (0..=(h / dt).round() as usize).map(move |k| k as f64 * dt);
                steps.chain([straight]).map(move |t| (dp + dv * t + da * (t * t / 2.0), o.number, t > 0.0))
            })
            .min_by(|a, b| a.0.length().total_cmp(&b.0.length()))?;
        let down = if me.number > other { -1.0 } else { 1.0 };
        Some((miss.length(), (-miss).try_normalize().unwrap_or(Vec3::UP * down), closing))
    }
}

/// `a` and `b` are a pair's mates flying free of each other's collision avoidance after a pairs take-off
/// ([`PAIR_FREE`]).
fn pair_free(a: &Member, b: &Member) -> bool {
    let (w, l) = if a.number.is_multiple_of(2) { (a, b) } else { (b, a) };
    w.pair_free.is_some() && l.number + 1 == w.number
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
/// against a radar, flares against infrared) at the launch's cue and each decision while a missile is inside
/// [`ecm::WINDOW_S`] of arriving. Clear for [`CLEAR_S`], it goes back (its rejoin or its route).
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
    // The decoys against a missile: one at the launch's cue (the dispenser's automatic program starts on the RWR's
    // launch or the MAW's warning, cmds.rs AUTO; a missile defeated by the turn alone, or one long in flight, never
    // comes inside the window), then each decision inside the window of its arrival (ecm.rs WINDOW_S: one earlier has
    // less chance, it burns out while the missile is still far). A lock alone takes none.
    let shot = Shot { missile_pos: t.pos, missile_vel: t.vel, target_pos: m.v.pos, target_vel: m.v.vel };
    if t.launch && (!m.launch_decoy || shot.time_to_go().is_some_and(|s| s <= ecm::WINDOW_S)) {
        m.launch_decoy = true;
        m.order.decoy = Some(if t.ir { Decoy::Flare } else { Decoy::Chaff });
    }
    m.order.mode = Some(autopilot::MODE_STEER);
    Status::Running
}

/// A member's order to its autopilot and flight model (the tests and the Godot class alike).
pub fn apply(o: &Order, ap: &mut Autopilot, fm: &mut Fm) {
    ap.leader = o.leader;
    ap.slot = o.slot;
    ap.close = o.close;
    ap.precise = o.precise;
    ap.avoid = o.avoid;
    ap.hold = o.hold;
    ap.hold_short = o.hold_short;
    ap.lineup_offset = o.lineup_offset;
    ap.pair_lead = o.pair_lead;
    ap.floor = Some(FLOOR_M);
    ap.follow = o.follow;
    ap.pace = o.pace;
    ap.low = o.low;
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
