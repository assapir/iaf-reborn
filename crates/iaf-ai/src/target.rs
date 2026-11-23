//! Modern IAF's target drones (docs/ai.md §21; modern-iaf/docs/ai-plan.md C4): the weapons range's drones and the
//! intercept lesson's, the sim's own jets flown on the flight model by the autopilot's loops. Every period the
//! drone decides: it flies its route (WayPtSet, mode 7), and by its kind scans for the best air contact (its radar's
//! lock, heard on the target's RWR) or, with a fighter inside [`EVADE_M`], breaks 90° or runs away from it, at
//! random. It never shoots. The kind comes from the drone's brain record in the mission (data/db/brains: `drone`,
//! `drone_radar`, `drone_evade`), read from its actions; the 1998 game keeps its brain (`shared/ai/brain.gd`).

/// The decision period, s: the 1998 brain's for an enemy aircraft, 2 s × 1.5 at the Normal AI level (brain.gd
/// SKILL_PERIOD), the level Modern IAF keeps (it has no AI level preference).
pub const PERIOD_S: f64 = 3.0;
/// The evading drone manoeuvres against a fighter inside this, m: a little beyond the gun's and the short-range
/// missile's reach (the `drone_evade` record, inferred).
pub const EVADE_M: f64 = 9000.0;
/// ... breaking 90° on a roll (0..=100) under this, else running away (the record's `random < 50`).
pub const BREAK_ROLL: u32 = 50;

/// The brain actions a target drone's record may hold (sim.rs ACTIONS' codes): navigate, select an air target,
/// break 90°, run away.
const NAVIGATE: i64 = 240;
const SCAN: i64 = 400;
const BREAK_90: i64 = 170;
const RUN_AWAY: i64 = 160;

/// The autopilot's loops a drone flies (brain.gd MANOEUVRES): WayPtSet, RunAway, Break90.
pub const MODE_ROUTE: u8 = 7;
pub const MODE_RUN_AWAY: u8 = 0x12;
pub const MODE_BREAK_90: u8 = 0x13;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// Flies its route, radar silent, non-manoeuvring (`drone`; the lesson's drone).
    Route,
    /// Flies its route with its radar on (`drone_radar`).
    Radar,
    /// Flies its route and manoeuvres against a fighter that closes in (`drone_evade`).
    Evade,
}

impl Kind {
    /// The kind of a brain record by its actions' codes; None when it holds any other action (not a target drone's
    /// brain) or no navigate. The records' conditions are not read: their figures are [`EVADE_M`] and [`BREAK_ROLL`].
    pub fn of_actions(codes: &[i64]) -> Option<Kind> {
        if !codes.contains(&NAVIGATE) || codes.iter().any(|c| ![NAVIGATE, SCAN, BREAK_90, RUN_AWAY].contains(c)) {
            return None;
        }
        Some(if codes.contains(&BREAK_90) || codes.contains(&RUN_AWAY) {
            Kind::Evade
        } else if codes.contains(&SCAN) {
            Kind::Radar
        } else {
            Kind::Route
        })
    }
}

/// One target drone's decisions.
#[derive(Clone, Copy, Debug)]
pub struct Drone {
    pub kind: Kind,
    next: f64,
}

impl Drone {
    pub fn new(kind: Kind) -> Drone {
        Drone { kind, next: f64::MIN }
    }

    /// A decision is due at `now` (s): the first at once, then every [`PERIOD_S`].
    pub fn due(&mut self, now: f64) -> bool {
        if now < self.next {
            return false;
        }
        self.next = now + PERIOD_S;
        true
    }

    /// It scans for the best air contact this decision (before [`Drone::mode`], whose range is to that contact).
    pub fn scans(&self) -> bool {
        self.kind != Kind::Route
    }

    /// Its loop this decision: `range_m` to its contact alive (None: none), `roll` 0..=100 at random.
    pub fn mode(&self, range_m: Option<f64>, roll: u32) -> u8 {
        match (self.kind, range_m) {
            (Kind::Evade, Some(r)) if r < EVADE_M && roll < BREAK_ROLL => MODE_BREAK_90,
            (Kind::Evade, Some(r)) if r < EVADE_M => MODE_RUN_AWAY,
            _ => MODE_ROUTE,
        }
    }
}
