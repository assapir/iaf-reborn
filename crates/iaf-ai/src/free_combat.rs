//! Modern IAF's Scramble (the front end's Scramble card, modern-iaf/docs/front-end.md §2.1; docs/ai.md §23): the
//! player picks the flight and the start, then flies; no mission places the enemy. [`area`] draws the fight's base
//! within reach of the player's, [`roll`] draws the enemy and the task the AWACS gives (at the Pilot screen's enemy
//! skill), [`plan`] lays the enemy out round the fight's base (`shared/ai`'s hooks place it:
//! `modern-iaf/flight/free_combat.gd`), [`air_start`] puts the flight in the air, [`runway_start`] lines it up on the
//! runway, [`task_call`] is the AWACS's tasking call. Every distance and time here is ours (inferred).

use crate::skill::mix;
use iaf_avionics::fctrl;
use iaf_flight::Vec3;

/// The most enemy pairs of each kind (the four shelters of the smallest base hold two based pairs).
pub const MAX_PAIRS: u8 = 2;
/// The CAP's station towards the player's base from the fight's (m), each pair this far to a side (m), at this height
/// (m above the base) and 1,000 m higher for the second.
const CAP_AHEAD: f64 = 25_000.0;
const CAP_SIDE: f64 = 12_000.0;
const CAP_ALT: f64 = 6_000.0;
/// A pair's wingman beside its lead (m).
const WING: f64 = 700.0;
/// The based pairs' station towards the player's base (m), at CAP_ALT.
const BASED_AHEAD: f64 = 15_000.0;
/// The S-300 battery beyond the base (m); the network's search radar and command post beside it (m).
const S300_BEYOND: f64 = 12_000.0;
/// The battery's own point defence, a Tor-M1 this far from its centre towards the player (m): a long-range battery
/// has a short-range missile system at its site (Russia's S-400 sites a Pantsir-S1, Iran's short-range tier the Tor;
/// modern-iaf/docs/research/enemies.md §2.7); the distance inferred: its 12 km zone over the launchers and the approach.
const S300_GUARD: f64 = 1_000.0;
const NET_BEYOND: f64 = 8_000.0;
const NET_SIDE: f64 = 3_000.0;
/// The convoy's tail and head towards the player's base (m), off to a side (m).
const CONVOY_FROM: f64 = 12_000.0;
const CONVOY_TO: f64 = 4_000.0;
const CONVOY_SIDE: f64 = 6_000.0;
/// The short-range sites round their centre (the convoy's middle, else beside the base) (m).
const SHORAD_SIDE: f64 = 4_000.0;
/// The ZSU-23-4s go in pairs about 200 m apart (FAS; enemies.md §3.1).
const ZSU_PAIR: f64 = 200.0;
/// The drones' launch point beyond the base (m) and to a side (m); they fly over the fight's base at the player's.
const DRONES_BEYOND: f64 = 80_000.0;
const DRONES_SIDE: f64 = 10_000.0;
pub const DRONES: u8 = 4;
const DRONES_INTERVAL: f64 = 10.0;

/// A Scramble's enemy ([`roll`]): the MiG-29 pairs on CAP and parked at the fight's base (each up to [`MAX_PAIRS`]),
/// the S-300 network (the battery with its Tor-M1), the short-range sites (a Tor-M1, a pair of ZSU-23-4s and an Igla
/// team), a salvo of Shahed-136s, a convoy.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Setup {
    pub cap_pairs: u8,
    pub based_pairs: u8,
    pub sam_net: bool,
    pub shorad: bool,
    pub drones: bool,
    pub convoy: bool,
}

/// One thing to place (world: x east, y north, z up, m; headings in degrees from north).
#[derive(Clone, Debug, PartialEq)]
pub enum Spawn {
    /// An air-defence site of `kind` (air_defence.gd `spawn`), in the network when there is one.
    Site { kind: &'static str, pos: Vec3, heading: f64 },
    /// The S-300's network (air_defence.gd `spawn_net`) over every site.
    Net { radar: Vec3, post: Vec3, heading: f64 },
    /// A MiG-29A pair in the air on its CAP station (ai_flights.gd `spawn`, `enemy_flight`).
    Cap { jets: [Vec3; 2], heading: f64, station: Vec3 },
    /// A MiG-29A pair parked in the fight's base's shelters from `first` (ai_flights.gd `enemy_base`).
    Based { first: u8, station: Vec3 },
    /// A convoy from `from` to `to` (convoys.gd `spawn`; the roads nearest them where there are roads).
    Convoy { from: Vec3, to: Vec3 },
    /// A salvo of Shahed-136s along `route` (drones.gd `spawn`).
    Drones { route: Vec<Vec3>, count: u8, interval: f64 },
}

/// The fight's base is at most this far from the player's (m; inferred: a short sortie for an F-16, and every base of
/// the theatre has at least two others in reach).
const REACH: f64 = 180_000.0;

/// The fight's base drawn from `seed` among `bases` (world), alike from those within [`REACH`] of the player's base
/// `home` and not at it; the nearest other base when none is in reach; None when every base is at `home`. Its index.
pub fn area(seed: u64, home: Vec3, bases: &[Vec3]) -> Option<usize> {
    let d = |i: &usize| flat_dist(home, bases[*i]);
    let others: Vec<usize> = (0..bases.len()).filter(|i| d(i) > 1_000.0).collect();
    let near: Vec<usize> = others.iter().copied().filter(|i| d(i) <= REACH).collect();
    if near.is_empty() {
        return others.into_iter().min_by(|a, b| d(a).total_cmp(&d(b)));
    }
    Some(near[(mix(seed ^ mix(0)) % near.len() as u64) as usize])
}

/// The tanker's track ([`tanker`]): its inbound leg's middle this far from the player's base towards the fight's (m;
/// inferred: over our own side, short of the enemy's fighters' CAP).
const TANKER_FROM_HOME: f64 = 40_000.0;

/// A Scramble's tanker (modern-iaf/docs/research/air-refuelling.md §8.1), drawn from `seed`: on half the flights (the
/// user, 25 Nov 2026: "if available (not for every mission)"), a KC-46A Gideon or a 707 Re'em alike. Its track runs
/// across the line from the player's base `home` to the fight's `area` (world), its inbound leg's middle
/// [`TANKER_FROM_HOME`] out on that line, its left-hand turns towards home: (kind, the inbound leg's start, its
/// course in degrees). None: no tanker, or the two bases are one point.
pub fn tanker(seed: u64, home: Vec3, area: Vec3) -> Option<(&'static str, Vec3, f64)> {
    let r = mix(seed ^ mix(0x7a4c));
    let d = Vec3::new(area.x - home.x, area.y - home.y, 0.0);
    if r.is_multiple_of(2) || d.length() < 1.0 {
        return None;
    }
    let u = d / d.length();
    // The course: home's direction to the left of it (the turns are left), so the far leg is nearer home.
    let dir = Vec3::new(-u.y, u.x, 0.0);
    let start = home + u * TANKER_FROM_HOME - dir * (crate::tanker::TRACK_LEG / 2.0);
    let kind = if (r / 2).is_multiple_of(2) { "kc46" } else { "reem" };
    Some((kind, Vec3::new(start.x, start.y, 0.0), dir.x.atan2(dir.y).to_degrees().rem_euclid(360.0)))
}

/// What the AWACS sends the player's flight to do: intercept the MiG-29 pair on CAP or the drones, attack the convoy
/// or the S-300 battery. The roll is built round it, so its target is always there.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Task {
    Cap,
    Drones,
    Convoy,
    Sam,
}

impl Task {
    pub const ALL: [Task; 4] = [Task::Cap, Task::Drones, Task::Convoy, Task::Sam];

    /// Its name for the flight's scripts (cap, drones, convoy, sam).
    pub fn name(self) -> &'static str {
        match self {
            Task::Cap => "cap",
            Task::Drones => "drones",
            Task::Convoy => "convoy",
            Task::Sam => "sam",
        }
    }

    /// The radio particle the AWACS names it with (voices.json `TASK_*`).
    pub fn particle(self) -> &'static str {
        match self {
            Task::Cap => "TASK_CAP",
            Task::Drones => "TASK_DRONES",
            Task::Convoy => "TASK_CONVOY",
            Task::Sam => "TASK_SAM",
        }
    }

    /// The task named `name`, None for another word.
    pub fn from_name(name: &str) -> Option<Task> {
        Task::ALL.into_iter().find(|t| t.name() == name)
    }

    /// `s` with the task's own target in it.
    fn add(self, s: &mut Setup) {
        match self {
            Task::Cap => s.cap_pairs = s.cap_pairs.max(1),
            Task::Drones => s.drones = true,
            Task::Convoy => s.convoy = true,
            Task::Sam => s.sam_net = true,
        }
    }
}

/// One more threat a roll can add to `s`: a MiG-29 pair on CAP, a pair on alert (with the S-300 network, whose
/// vector scrambles it), the network, the short-range sites, the drones, the convoy; the ones `s` has no room for left
/// out.
fn extras(s: &Setup) -> Vec<fn(&mut Setup)> {
    let mut out: Vec<fn(&mut Setup)> = vec![];
    if s.cap_pairs < MAX_PAIRS {
        out.push(|s| s.cap_pairs += 1);
    }
    if s.based_pairs < MAX_PAIRS {
        out.push(|s| {
            s.based_pairs += 1;
            s.sam_net = true;
        });
    }
    if !s.sam_net {
        out.push(|s| s.sam_net = true);
    }
    if !s.shorad {
        out.push(|s| s.shorad = true);
    }
    if !s.drones {
        out.push(|s| s.drones = true);
    }
    if !s.convoy {
        out.push(|s| s.convoy = true);
    }
    out
}

/// A Scramble's enemy, drawn from `seed`: the task first (any of the four alike), its target, then one more threat
/// per enemy skill level (`skill` 0 low, 1 medium, 2 high: one, two or three), each drawn alike from those
/// [`extras`] still has room for. The same seed and skill draw the same enemy.
pub fn roll(seed: u64, skill: i64) -> (Setup, Task) {
    let mut n = 0;
    let mut draw = |k: usize| {
        n += 1;
        (mix(seed ^ mix(n)) % k as u64) as usize
    };
    let task = Task::ALL[draw(Task::ALL.len())];
    let mut s = Setup::default();
    task.add(&mut s);
    for _ in 0..=skill.clamp(0, 2) {
        let pool = extras(&s);
        if pool.is_empty() {
            break;
        }
        pool[draw(pool.len())](&mut s);
    }
    (s, task)
}

/// The air start: this far from the fight's base towards the player's (m), at this height (m), at least this far from
/// every base (m: the start rule takes a start within 5 km of a base for a ground start, docs/ai.md §7.1), moved out in
/// these steps until it is.
const START_FROM: f64 = 60_000.0;
pub const START_ALT: f64 = 6_000.0;
const START_CLEAR: f64 = 8_000.0;
const START_STEP: f64 = 2_000.0;
/// A wingman's step back and aside from the jet ahead of it in the air start (m; ai_flights.gd `flight_in_air`'s).
const START_SLOT: f64 = 150.0;

/// The air start of a flight of `count` (1 to 4) round the fight's base `area`, the player's base `home`, the
/// theatre's bases `bases` (world, m): [x, y, heading] for each jet, the lead first, heading for `area`, at
/// [`START_ALT`]. The lead [`START_FROM`] from `area` on the line towards `home` (beyond it when `home` is nearer),
/// moved out until [`START_CLEAR`] from every base; each wingman a step back and to alternate sides. Empty when the two
/// bases are one point.
pub fn air_start(home: Vec3, area: Vec3, bases: &[Vec3], count: usize) -> Vec<[f64; 3]> {
    let d = Vec3::new(home.x - area.x, home.y - area.y, 0.0);
    if d.length() < 1.0 {
        return vec![];
    }
    let u = d / d.length();
    let flat = |v: Vec3| Vec3::new(v.x, v.y, 0.0);
    let mut r = START_FROM;
    while bases.iter().any(|b| (flat(*b) - flat(area + u * r)).length() < START_CLEAR) {
        r += START_STEP;
    }
    let lead = flat(area + u * r);
    // Heading for the area (-u), and the right hand of that heading.
    let fwd = -u;
    let right = Vec3::new(fwd.y, -fwd.x, 0.0);
    let heading = fwd.x.atan2(fwd.y).to_degrees().rem_euclid(360.0);
    (1..=count.clamp(1, 4))
        .map(|n| {
            let side = if n == 1 {
                0.0
            } else if n % 2 == 1 {
                START_SLOT
            } else {
                -START_SLOT
            };
            let p = lead - fwd * (START_SLOT * (n - 1) as f64) + right * side;
            [p.x, p.y, heading]
        })
        .collect()
}

/// The runway start's pairs (ai-plan F1, iaf-ai flight.rs `PAIR_M`): #2 this far left of the lead, #4 right of #3 (m;
/// fingertip's sides), the second element this far behind the first (m; inside the start rule's 100 m of the lineup
/// point that starts an engine, docs/ai.md §7.1).
const RUNWAY_SIDE: f64 = 15.0;
const RUNWAY_BACK: f64 = 60.0;

/// The runway start of a flight of `count` (1 to 4) at the lineup point `lineup` facing `heading` (deg; world, m):
/// [x, y, heading] for each jet, the lead first, lined up in pairs for a pairs take-off.
pub fn runway_start(lineup: Vec3, heading: f64, count: usize) -> Vec<[f64; 3]> {
    let h = heading.to_radians();
    let (fwd, right) = (Vec3::new(h.sin(), h.cos(), 0.0), Vec3::new(h.cos(), -h.sin(), 0.0));
    [(0.0, 0.0), (0.0, -RUNWAY_SIDE), (-RUNWAY_BACK, 0.0), (-RUNWAY_BACK, RUNWAY_SIDE)]
        .iter()
        .take(count.clamp(1, 4))
        .map(|&(back, side)| {
            let p = lineup + fwd * back + right * side;
            [p.x, p.y, heading]
        })
        .collect()
}

/// The AWACS's task call: this long after the player's jet is first in the air (s), then again this often (s) while
/// the task's target is alive.
const TASK_FIRST_S: f64 = 5.0;
const TASK_REPEAT_S: f64 = 60.0;

/// The task call is due `airborne_s` after the player's jet left the ground, `since_s` after the last one (infinite
/// before the first).
pub fn task_due(airborne_s: f64, since_s: f64) -> bool {
    airborne_s >= TASK_FIRST_S && since_s >= TASK_REPEAT_S
}

/// A distance in the task call (m → nautical miles, truncated): 1 to 10 as they are, then down to fives to 50, then
/// to tens up to 90 (voices.json's MILESnn particles; the contact calls stop at 35, fctrl.rs).
fn task_miles(dist: f64) -> i32 {
    let m = (dist / 1852.0) as i32;
    match m {
        ..=1 => 1,
        2..=10 => m,
        11..=50 => m - m % 5,
        _ => (m - m % 10).min(90),
    }
}

/// The AWACS's task call to the player (`callsign`, its formation name, "Alpha") at `player` for the task's target at
/// `target` (world, m): the template AWX_TASK and its particles: "Kidon 1, attack the convoy, bearing 040, 25 miles,
/// free to engage". The bearing and its tens as the contact calls' (fctrl.rs).
pub fn task_call(task: Task, callsign: &str, player: Vec3, target: Vec3) -> (&'static str, Vec<String>) {
    let b = fctrl::tens(fctrl::bearing(player, target));
    let m = task_miles(flat_dist(player, target));
    let args = vec![format!("{callsign}_r"), task.particle().into(), format!("BEARING{b:03}"), format!("MILES{m:02}")];
    ("AWX_TASK", args)
}

/// The start time's steps (min: an hour, five minutes) and a day's minutes; a start time is minutes after local
/// midnight, Israel time (the Scramble screen's first default 0800: free_combat_page.gd DEFAULT).
pub const HOUR_STEP: i64 = 60;
pub const MINUTE_STEP: i64 = 5;
const DAY_MIN: i64 = 24 * 60;

/// A stored start time `min` (minutes after midnight) on the five-minute grid, in the day: wrapped, rounded down to
/// [`MINUTE_STEP`].
pub fn time_valid(min: i64) -> i64 {
    let m = min.rem_euclid(DAY_MIN);
    m - m % MINUTE_STEP
}

/// `min` stepped by `delta` minutes (an hour or [`MINUTE_STEP`] either way), round the clock.
pub fn time_step(min: i64, delta: i64) -> i64 {
    time_valid(time_valid(min) + delta)
}

/// The start time as the player sets it, 24-hour military time HHMM ("0630", "2200").
pub fn clock(min: i64) -> String {
    let m = min.rem_euclid(DAY_MIN);
    format!("{:02}{:02}", m / 60, m % 60)
}

/// The flight's start time (minutes after local midnight): the set `min`, or with `random` one drawn from the
/// Scramble's `seed` alike over the day's five-minute steps (its own draw: the area's and the roll's draws differ).
pub fn start_time(seed: u64, random: bool, min: i64) -> i64 {
    if !random {
        return time_valid(min);
    }
    (mix(seed ^ mix(0x7173)) % (DAY_MIN / MINUTE_STEP) as u64) as i64 * MINUTE_STEP
}

const BEFORE: [i64; 12] = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];

fn leap(year: i64) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

/// The day of the year (1 for 1 January) of `year`-`month`-`day` (Gregorian), for the sun on the flight's date.
pub fn day_of_year(year: i64, month: i64, day: i64) -> i64 {
    BEFORE[(month.clamp(1, 12) - 1) as usize] + day + i64::from(leap(year) && month > 2)
}

/// The days of `year`: 365, 366 in a leap year.
pub fn year_days(year: i64) -> i64 {
    365 + i64::from(leap(year))
}

/// The month (1 to 12) and its day of day `doy` of `year` (wrapped into the year).
pub fn month_day(year: i64, doy: i64) -> (i64, i64) {
    let doy = (doy - 1).rem_euclid(year_days(year)) + 1;
    let m = (1..=12).rev().find(|&m| day_of_year(year, m, 1) <= doy).unwrap_or(1);
    (m, doy - day_of_year(year, m, 1) + 1)
}

/// The Scramble's date `doy` of `year` stepped by `days` days round the year, then by `months` months round the year
/// (the day kept, cut to the month's last: 31 January a month on is 28 or 29 February).
pub fn date_step(year: i64, doy: i64, days: i64, months: i64) -> i64 {
    let doy = (doy - 1 + days).rem_euclid(year_days(year)) + 1;
    if months == 0 {
        return doy;
    }
    let (m, d) = month_day(year, doy);
    let m = (m - 1 + months).rem_euclid(12) + 1;
    let last = if m == 12 { 31 } else { day_of_year(year, m + 1, 1) - day_of_year(year, m, 1) };
    day_of_year(year, m, d.min(last))
}

/// The flight's day of `year`: the set `doy`, or with `random` one drawn from the Scramble's `seed` alike over the
/// year's days (its own draw, apart from the start time's).
pub fn start_day(seed: u64, random: bool, year: i64, doy: i64) -> i64 {
    if !random {
        return (doy - 1).rem_euclid(year_days(year)) + 1;
    }
    (mix(seed ^ mix(0x6461)) % year_days(year) as u64) as i64 + 1
}

/// Israel's clock on `year`-`month`-`day`, hours ahead of UTC: 3 on summer time (Israel Daylight Time, from the
/// Friday before March's last Sunday to October's last Sunday: Israel's Time Determination Law, 2013), else 2.
pub fn utc_offset(year: i64, month: i64, day: i64) -> f64 {
    // The weekday (0 Sunday; Sakamoto's method) and the month's last Sunday.
    let weekday = |y: i64, m: i64, d: i64| {
        const T: [i64; 12] = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
        let y = if m < 3 { y - 1 } else { y };
        (y + y / 4 - y / 100 + y / 400 + T[(m - 1) as usize] + d).rem_euclid(7)
    };
    let last_sunday = |m: i64| 31 - weekday(year, m, 31);
    let today = day_of_year(year, month, day);
    let from = day_of_year(year, 3, last_sunday(3)) - 2;
    let to = day_of_year(year, 10, last_sunday(10));
    if (from..to).contains(&today) { 3.0 } else { 2.0 }
}

fn flat_dist(a: Vec3, b: Vec3) -> f64 {
    ((a.x - b.x).powi(2) + (a.y - b.y).powi(2)).sqrt()
}

/// The enemy of `s` round the fight's base `area` (on the ground), facing the player's base `home`: the sites first
/// (the network takes them), then the network, the fighters (vectored by it), the convoy and the drones. Empty when
/// the two bases are one point.
pub fn plan(s: &Setup, home: Vec3, area: Vec3) -> Vec<Spawn> {
    let d = Vec3::new(home.x - area.x, home.y - area.y, 0.0);
    if d.length() < 1.0 {
        return vec![];
    }
    // Towards the player (u), to the side (p), the heading that faces the player.
    let u = d / d.length();
    let p = Vec3::new(u.y, -u.x, 0.0);
    let facing = u.x.atan2(u.y).to_degrees().rem_euclid(360.0);
    let at = |ahead: f64, side: f64| area + u * ahead + p * side;
    let up = |v: Vec3, h: f64| Vec3::new(v.x, v.y, area.z + h);
    let mut out = vec![];
    let convoy = (at(CONVOY_FROM, CONVOY_SIDE), at(CONVOY_TO, CONVOY_SIDE));
    if s.sam_net {
        out.push(Spawn::Site { kind: "s300", pos: at(-S300_BEYOND, 0.0), heading: facing });
        out.push(Spawn::Site { kind: "tor", pos: at(S300_GUARD - S300_BEYOND, 0.0), heading: facing });
    }
    if s.shorad {
        let c = if s.convoy { (convoy.0 + convoy.1) / 2.0 } else { at(0.0, -SHORAD_SIDE) };
        let zsu = [("zsu", -800.0, -500.0), ("zsu", -800.0 - ZSU_PAIR, -500.0)];
        for (kind, side, ahead) in [("tor", 1_500.0, 1_000.0), zsu[0], zsu[1], ("igla", 300.0, 1_500.0)] {
            out.push(Spawn::Site { kind, pos: c + p * side + u * ahead, heading: facing });
        }
    }
    if s.sam_net {
        let radar = at(-NET_BEYOND, NET_SIDE);
        out.push(Spawn::Net { radar, post: radar + p * 1_000.0 - u * 1_000.0, heading: facing });
    }
    for k in 0..s.cap_pairs.min(MAX_PAIRS) {
        let side = if k == 0 { -CAP_SIDE } else { CAP_SIDE };
        let station = up(at(CAP_AHEAD, side), CAP_ALT + 1_000.0 * f64::from(k));
        out.push(Spawn::Cap { jets: [station, station + p * WING - u * WING], heading: facing, station });
    }
    for k in 0..s.based_pairs.min(MAX_PAIRS) {
        out.push(Spawn::Based { first: 2 * k, station: up(at(BASED_AHEAD, 0.0), CAP_ALT) });
    }
    if s.convoy {
        out.push(Spawn::Convoy { from: convoy.0, to: convoy.1 });
    }
    if s.drones {
        let route = vec![up(at(-DRONES_BEYOND, DRONES_SIDE), 0.0), area, home];
        out.push(Spawn::Drones { route, count: DRONES, interval: DRONES_INTERVAL });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const EVERY: Setup =
        Setup { cap_pairs: 2, based_pairs: 2, sam_net: true, shorad: true, drones: true, convoy: true };

    #[test]
    fn areas_in_reach() {
        // Ramon's distances to the other bases (km): David 215, Tel Nof 117, Hatzerim 49, Nevatim 58.
        let km = |x: f64| Vec3::new(0.0, x * 1_000.0, 0.0);
        let bases = [km(0.0), km(215.0), km(117.0), km(49.0), km(58.0)];
        let mut got = vec![];
        for seed in 0..100 {
            let i = area(seed, bases[0], &bases).unwrap();
            assert_eq!(area(seed, bases[0], &bases), Some(i), "a seed draws the same area");
            assert!(i != 0 && i != 1, "never home, never out of reach: {i}");
            got.push(i);
        }
        assert!([2, 3, 4].iter().all(|i| got.contains(i)), "every base in reach is drawn");
        assert_eq!(area(1, km(0.0), &[km(0.0), km(300.0), km(250.0)]), Some(2), "none in reach: the nearest");
        assert_eq!(area(1, km(0.0), &[km(0.0)]), None);
    }

    #[test]
    fn runway_lined_up_in_pairs() {
        let l = Vec3::new(1_000.0, 2_000.0, 600.0);
        let s = runway_start(l, 90.0, 4);
        assert_eq!(s.len(), 4);
        let near = |p: [f64; 3], x: f64, y: f64| (p[0] - x).abs() < 1e-6 && (p[1] - y).abs() < 1e-6 && p[2] == 90.0;
        // Facing east: #2 left (north), #3 behind (west), #4 right of #3 (south); all within 100 m of the lineup.
        assert!(near(s[0], 1_000.0, 2_000.0) && near(s[1], 1_000.0, 2_015.0), "{s:?}");
        assert!(near(s[2], 940.0, 2_000.0) && near(s[3], 940.0, 1_985.0), "{s:?}");
        assert_eq!(runway_start(l, 0.0, 1).len(), 1);
    }

    #[test]
    fn a_tanker_on_half_the_flights_across_the_way_to_the_fight() {
        use crate::tanker::{TRACK_LEG, Track};
        let (home, area) = (Vec3::new(1000.0, 2000.0, 0.0), Vec3::new(101_000.0, 2000.0, 0.0));
        let drawn: Vec<_> = (0..400u64).filter_map(|s| tanker(s, home, area)).collect();
        assert!((150..250).contains(&drawn.len()), "about half: {}", drawn.len());
        let kc46 = drawn.iter().filter(|t| t.0 == "kc46").count();
        assert!(kc46 > 50 && drawn.len() - kc46 > 50, "both kinds");
        let (_, start, course) = drawn[0];
        assert!((course - 0.0).abs() < 1e-6, "across the line east: north: {course}");
        let track = Track::new(start, course.to_radians());
        let mid = track.at(TRACK_LEG / 2.0).pos;
        assert!((mid.x - 41_000.0).abs() < 1.0 && (mid.y - 2000.0).abs() < 1.0, "40 km out: {mid:?}");
        // The far leg is nearer home (west).
        assert!(track.at(TRACK_LEG * 1.5 + track.radius * std::f64::consts::PI).pos.x < mid.x - 30_000.0);
        assert_eq!(tanker(7, home, home), None);
    }

    #[test]
    fn rolls() {
        let mut tasks = vec![];
        for skill in 0..3 {
            for seed in 0..200u64 {
                let (s, task) = roll(seed, skill);
                assert_eq!(roll(seed, skill), (s, task), "a seed draws the same enemy");
                tasks.push(task);
                // The task's target is there; alert pairs come with the network; the threats grow with the skill.
                let has = match task {
                    Task::Cap => s.cap_pairs > 0,
                    Task::Drones => s.drones,
                    Task::Convoy => s.convoy,
                    Task::Sam => s.sam_net,
                };
                assert!(has, "{task:?} in {s:?}");
                assert!(s.based_pairs == 0 || s.sam_net, "{s:?}");
                assert!(s.cap_pairs <= MAX_PAIRS && s.based_pairs <= MAX_PAIRS);
                let threats = s.cap_pairs
                    + s.based_pairs
                    + [s.sam_net, s.shorad, s.drones, s.convoy].map(u8::from).iter().sum::<u8>();
                let k = skill as u8;
                assert!((k + 2..=2 * k + 3).contains(&threats), "skill {skill}: {s:?}");
            }
        }
        for t in Task::ALL {
            assert!(tasks.contains(&t), "every task is drawn");
            assert_eq!(Task::from_name(t.name()), Some(t));
        }
        assert_ne!(roll(1, 1), roll(2, 1), "seeds differ");
    }

    #[test]
    fn air_start_clear_of_the_bases() {
        // Hatzerim's fight, the player from Ramon 49 km south of it: the start 60 km south of Hatzerim, 11 km past Ramon.
        let area = Vec3::new(0.0, 0.0, 200.0);
        let home = Vec3::new(0.0, -49_000.0, 600.0);
        let s = air_start(home, area, &[home, area], 4);
        assert_eq!(s.len(), 4);
        assert!((s[0][1] + START_FROM).abs() < 1e-6 && s[0][0].abs() < 1e-6, "{s:?}");
        assert!(s[0][2].abs() < 1e-6, "heading north for the area");
        assert!(s[1][1] < s[0][1] && s[1][0] < 0.0 && s[2][0] > 0.0, "the wingmen behind, alternate sides");
        // A base 2 km from that point pushes the start out until 8 km clear.
        let near = Vec3::new(0.0, -58_000.0, 0.0);
        let s = air_start(near, area, &[near, area], 1);
        assert!((s[0][1] - near.y).abs() >= START_CLEAR, "{s:?}");
        assert!(air_start(area, area, &[], 2).is_empty());
    }

    #[test]
    fn the_task_call() {
        assert!(!task_due(4.0, f64::INFINITY) && task_due(5.0, f64::INFINITY));
        assert!(!task_due(100.0, 59.0) && task_due(100.0, 60.0));
        assert_eq!([500.0, 9_000.0, 40_000.0, 90_000.0, 130_000.0, 400_000.0].map(task_miles), [1, 4, 20, 45, 70, 90]);
        let (t, args) =
            task_call(Task::Convoy, "Alpha", Vec3::new(0.0, 0.0, 6000.0), Vec3::new(30_000.0, 30_000.0, 0.0));
        assert_eq!(t, "AWX_TASK");
        assert_eq!(args, ["Alpha_r", "TASK_CONVOY", "BEARING040", "MILES20"]);
    }

    #[test]
    fn the_start_time() {
        assert_eq!(clock(8 * 60), "0800");
        assert_eq!(
            [clock(6 * 60 + 30), clock(14 * 60 + 15), clock(22 * 60), clock(0)],
            ["0630", "1415", "2200", "0000"]
        );
        assert_eq!(time_step(23 * 60 + 30, HOUR_STEP), 30, "an hour past 2330: 0030");
        assert_eq!(time_step(0, -MINUTE_STEP), 23 * 60 + 55, "five minutes before 0000: 2355");
        assert_eq!(time_valid(-1), 23 * 60 + 55);
        assert_eq!(time_valid(487), 485);
        assert_eq!(start_time(9, false, 6 * 60 + 30), 390, "a set time flies as set");
        let mut got = std::collections::HashSet::new();
        for seed in 0..2000 {
            let t = start_time(seed, true, 0);
            assert_eq!(start_time(seed, true, 0), t, "a seed draws the same time");
            assert!((0..DAY_MIN).contains(&t) && t % MINUTE_STEP == 0, "{t}");
            got.insert(t / 60);
        }
        assert_eq!(got.len(), 24, "every hour is drawn");
        assert_eq!([day_of_year(2026, 1, 1), day_of_year(2026, 3, 20), day_of_year(2026, 11, 25)], [1, 79, 329]);
        assert_eq!([day_of_year(2024, 3, 1), day_of_year(2024, 12, 31), day_of_year(2100, 3, 1)], [61, 366, 60]);
        // 2026: summer time from Friday 27 March to Sunday 25 October; 2025: 28 March to 26 October.
        let o = |y, m, d| utc_offset(y, m, d);
        assert_eq!(
            [o(2026, 3, 26), o(2026, 3, 27), o(2026, 7, 1), o(2026, 10, 24), o(2026, 10, 25)],
            [2.0, 3.0, 3.0, 3.0, 2.0]
        );
        assert_eq!(
            [o(2025, 3, 27), o(2025, 3, 28), o(2025, 10, 25), o(2025, 10, 26), o(2026, 11, 25)],
            [2.0, 3.0, 3.0, 2.0, 2.0]
        );
    }

    #[test]
    fn the_date() {
        assert_eq!([year_days(2026), year_days(2028), year_days(2100)], [365, 366, 365]);
        assert_eq!([month_day(2026, 1), month_day(2026, 329), month_day(2026, 365)], [(1, 1), (11, 25), (12, 31)]);
        assert_eq!([month_day(2028, 60), month_day(2028, 61), month_day(2026, 0)], [(2, 29), (3, 1), (12, 31)]);
        assert_eq!(date_step(2026, 365, 1, 0), 1, "a day past 31 December: 1 January");
        assert_eq!(date_step(2026, 1, -1, 0), 365);
        assert_eq!(month_day(2026, date_step(2026, 31, 0, 1)), (2, 28), "31 January a month on: 28 February");
        assert_eq!(month_day(2028, date_step(2028, 31, 0, 1)), (2, 29));
        assert_eq!(month_day(2026, date_step(2026, 329, 0, 2)), (1, 25), "25 November two months on: 25 January");
        assert_eq!(month_day(2026, date_step(2026, 10, 0, -1)), (12, 10));
        assert_eq!(start_day(9, false, 2026, 329), 329, "a set date flies as set");
        let mut got = std::collections::HashSet::new();
        for seed in 0..3000 {
            let d = start_day(seed, true, 2026, 1);
            assert_eq!(start_day(seed, true, 2026, 1), d, "a seed draws the same day");
            assert!((1..=365).contains(&d), "{d}");
            got.insert(month_day(2026, d).0);
        }
        assert_eq!(got.len(), 12, "every month is drawn");
    }

    #[test]
    fn layout_faces_the_player() {
        // Ramon south of Hatzerim: the player's base due south of the fight's.
        let home = Vec3::new(0.0, -50_000.0, 600.0);
        let area = Vec3::new(0.0, 0.0, 200.0);
        let p = plan(&EVERY, home, area);
        let kinds: Vec<&str> = p
            .iter()
            .map(|s| match s {
                Spawn::Site { kind, .. } => kind,
                Spawn::Net { .. } => "net",
                Spawn::Cap { .. } => "cap",
                Spawn::Based { .. } => "based",
                Spawn::Convoy { .. } => "convoy",
                Spawn::Drones { .. } => "drones",
            })
            .collect();
        assert_eq!(
            kinds,
            ["s300", "tor", "tor", "zsu", "zsu", "igla", "net", "cap", "cap", "based", "based", "convoy", "drones"]
        );
        let sites: Vec<Vec3> =
            p.iter().filter_map(|s| if let Spawn::Site { pos, .. } = s { Some(*pos) } else { None }).collect();
        assert!(flat_dist(sites[0], sites[1]) <= 1_500.0, "the battery's Tor at its site");
        assert!((flat_dist(sites[3], sites[4]) - ZSU_PAIR).abs() < 1e-6, "the ZSUs a pair");
        for s in &p {
            match s {
                Spawn::Site { kind: "s300", pos, heading } => {
                    assert!(pos.y > 0.0, "the battery beyond the base");
                    assert!((heading - 180.0).abs() < 1e-6, "facing the player");
                }
                Spawn::Cap { station, jets, .. } => {
                    assert!((station.y + CAP_AHEAD).abs() < 1e-6, "the CAP between the bases");
                    assert!(station.z >= area.z + CAP_ALT && jets[0] != jets[1]);
                }
                Spawn::Drones { route, .. } => assert_eq!(route.last(), Some(&home)),
                _ => {}
            }
        }
        let firsts: Vec<u8> =
            p.iter().filter_map(|s| if let Spawn::Based { first, .. } = s { Some(*first) } else { None }).collect();
        assert_eq!(firsts, [0, 2], "the second pair in the next shelters");
        assert!(plan(&EVERY, area, area).is_empty());
        let one = Setup { cap_pairs: 1, ..Setup::default() };
        assert_eq!(plan(&one, home, area).len(), 1);
    }
}
