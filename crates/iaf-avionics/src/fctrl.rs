//! The FlightController's radio reports (`DAT_00699348`, ctor `FUN_0054acc0`, docs/radio.md §4): the AWACS contact
//! calls (FlightControllerTimer `FUN_0054b130`), the kill calls (`FUN_0054c2a0`) and the repeat filters of the
//! airborne / landed reports (`FUN_0054e310` / `FUN_0054de90`). The host gathers the units and speaks the phrases.

use crate::Vec3;

/// FlightControllerTimer period, single player (`54af40`: 12 s, + the session's delay in a network game).
pub const AWACS_PERIOD: f64 = 12.0;
/// The query sphere around the player (`54ba10`: 0x47594400 = 55 620 m, 30 nm). The query (`4d2620`) takes a unit
/// when |p − c|² < (r + ro)² · 3 (0x604e6c), so it reaches 96.3 km; the calls stop at 35 nm (`54bb60`).
pub const AWACS_RADIUS: f64 = 55620.0;
/// The player is at least this high above the terrain (0x60ca90, |z − terrain|).
pub const PLAYER_AGL: f64 = 50.0;
/// A contact flies higher than terrain + 175 m (0x60ca80).
pub const CONTACT_AGL: f64 = 175.0;
/// A same-side contact is called only this close (0x60caa0: 10 m, so in practice never).
const FRIEND_RANGE: f32 = 10.0;
/// The contact table (`5672d0(…, 0x20, 0x18)`): 24 slots.
const SLOTS: usize = 24;
/// A slot's lifetime (`54b790` / `54ac20`): 60, minus 12 per scan.
const LIFE: i32 = 60;
/// The kill calls' repeat gate at +0x318 (`4d3fa0(0, 3.0, 0)`).
const KILL_GATE: f64 = 3.0;

/// One aircraft the scan found (class 0x1c / 2 / 3, alive, controlled, not the player or the wingman).
#[derive(Clone, Debug, Default)]
pub struct Unit {
    pub key: String,
    /// `FUN_005513c0(unit)`: its formation name (kinds 2–6, 9, 10), else "Alpha".
    pub callsign: String,
    /// On another side than the player (`4a4cf0`).
    pub enemy: bool,
    /// Known to the player (status +0x44: entity 0x35c or a radar scan of the player's).
    pub known: bool,
    pub pos: Vec3,
    /// The terrain height under it.
    pub ground: f64,
    /// Compass heading, degrees.
    pub heading: f64,
    /// A `rand()` value (0..0x7fff); used for an enemy only (`54bc20`).
    pub rand: i32,
}

/// One AWACS call (`FUN_0054be80`): ACFT_FCTRL_LONG or ACFT_FCTRL_SHORT.
#[derive(Clone, Debug, PartialEq)]
pub struct Call {
    pub long: bool,
    /// 0 friendlies, 1 target free to engage, 2 target already engaged, 3 unidentified.
    pub code: u8,
    pub bearing: i32,
    pub miles: i32,
    pub heading: i32,
}

impl Call {
    /// The template and its %S arguments; `callsign` is the player's formation name ("Alpha").
    pub fn phrase(&self, callsign: &str) -> (&'static str, Vec<String>) {
        let (desc, instr) = match self.code {
            0 => ("DESC_FRIENDS", "NULL"),
            1 => ("DESC_TARGET", "FREE_TO_ENGAGE"),
            2 => ("DESC_TARGET", "TRGT_ALRDY_ENGAGE"),
            _ => ("DESC_UNID_CONTACT", "PLEASE_IDENTIFY"),
        };
        let b = format!("BEARING{:03}", self.bearing);
        let m = format!("MILES{:02}", self.miles);
        if self.long {
            let h = format!("HEADING{:03}", self.heading);
            (
                "ACFT_FCTRL_LONG",
                vec![format!("{callsign}_r"), b, m, desc.into(), h, instr.into()],
            )
        } else {
            ("ACFT_FCTRL_SHORT", vec![b, m, desc.into()])
        }
    }
}

#[derive(Clone, Debug, Default)]
struct Slot {
    key: String,
    dist: f32,
    delta: [f32; 3],
    life: i32,
    seen: bool,
    callsign: String,
}

/// A unit in a kill call.
#[derive(Clone, Debug, Default)]
pub struct KillUnit {
    /// On another side than the player (`4a4cf0`).
    pub enemy: bool,
    pub klass: i64,
    pub type_code: i64,
    /// The unit's name (unit +0x20, 19 characters at most, `4a4c50`).
    pub name: String,
    /// `FUN_0054ccb0`: "ALPHALEADER" …, "" for "Other".
    pub callsign: String,
}

impl KillUnit {
    /// Classes 3, 0x1c, 2, 1 count as aircraft here.
    fn air(&self) -> bool {
        matches!(self.klass, 1 | 2 | 3 | 0x1c)
    }
}

/// The FlightController's report state.
#[derive(Clone, Debug)]
pub struct FlightController {
    slots: Vec<Slot>,
    /// +0x310: the scans to skip first (`54af40`: 50 / 12 = 4).
    countdown: i32,
    /// +0x318: [last, next] of the kill gate (`4d4100`; 1e7 at start).
    gate: [f64; 2],
    /// +0x378 / +0x37c / +0x380 / +0x384: the last kill call's S1, S2, S3 and template.
    last_kill: [String; 4],
    /// +0x390: the ground-kill counter (MULTITARGET).
    multi: i32,
    /// +0x388 / +0x38c: the last landed / airborne callsign.
    last_landed: String,
    last_airborne: String,
}

impl Default for FlightController {
    fn default() -> Self {
        FlightController {
            slots: vec![Slot::default(); SLOTS],
            countdown: 50 / AWACS_PERIOD as i32,
            gate: [1.0e7; 2],
            last_kill: Default::default(),
            multi: 1,
            last_landed: String::new(),
            last_airborne: String::new(),
        }
    }
}

/// `FUN_0054bc40`: the bearing from `from` to `to` (2-D), as coded: acos of the north component of the direction,
/// 6.28 − that west of north, times 57.3248 (180 / 3.14). The east / west test is inferred (the frame is the identity).
#[allow(clippy::approx_constant)] // 6.28 (0x60cab4) as coded, not 2π
pub fn bearing(from: Vec3, to: Vec3) -> f32 {
    let (dx, dy) = ((to.x - from.x) as f32, (to.y - from.y) as f32);
    let n = (dx * dx + dy * dy).sqrt();
    let s = if n == 0.0 { 1.0 } else { 1.0 / n };
    let a = (dy * s).clamp(-1.0, 1.0).acos();
    if dx * s >= 0.0 {
        a * 57.32484
    } else {
        (6.28 - a) * 57.32484
    }
}

/// `FUN_0054bbf0`: degrees truncated to tens; 0 is 360.
fn tens(deg: f32) -> i32 {
    match (deg as i32) / 10 * 10 {
        0 => 360,
        d => d,
    }
}

/// `FUN_0054bb60`: metres → nautical miles (× 0.000539374, truncated); above 10 down to fives; none above 35 or
/// below 1.
fn miles(dist: f32) -> Option<i32> {
    let m = (dist * 0.000_539_374_3) as i32;
    if m > 35 {
        return None;
    }
    let m = if m > 10 { m - m % 5 } else { m };
    (m >= 1).then_some(m)
}

/// Case-insensitive compare (`FUN_0056a9f0`).
fn eq_ic(a: &str, b: &str) -> bool {
    a.eq_ignore_ascii_case(b)
}

/// CString::Left(n).
fn left(s: &str, n: usize) -> &str {
    s.char_indices().nth(n).map_or(s, |(i, _)| &s[..i])
}

/// `FUN_0054ce80`: an aircraft's particle key, by class, type code and name.
pub fn air_name(klass: i64, type_code: i64, name: &str) -> &'static str {
    let is = |a: &str, b: &str| eq_ic(left(name, 4), a) || eq_ic(left(name, 5), b);
    let transport = |other| {
        if is("C130", "C-130") {
            "C130"
        } else if is("B707", "B-707") {
            "B707"
        } else if is("IL76", "IL-76") {
            "IL76"
        } else {
            other
        }
    };
    if klass == 2 || klass == 1 {
        return if is("MI24", "MI-24") {
            "MI24"
        } else if eq_ic(left(name, 3), "MI8") || eq_ic(left(name, 4), "MI-8") {
            "MI8"
        } else if is("UH60", "UH-60") {
            "UH60"
        } else if is("CH53", "CH-53") {
            "CH53"
        } else {
            "AIRTARGET"
        };
    }
    match type_code {
        100 => "F16",
        110 => "F15",
        120 => "F4",
        130 => "KFIR",
        140 => "LAVI",
        150 => "MIG21",
        160 if is("SU22", "SU-22") => "SU22",
        160 => "MIG23",
        170 => "MIG25",
        180 => "MIG29",
        190 => "MIRAGE",
        200 => "PHANTOM2000",
        210 => "MIG17",
        220 if is("SU24", "SU-24") => "SU24",
        220 if is("SU22", "SU-22") => "SU22",
        220 if is("TU22", "TU-22") => "TU22",
        220 => "AIRTARGET",
        225 => transport("LARGEAIRCRAFT"),
        _ => transport("AIRTARGET"),
    }
}

/// `FUN_0054d8d0`: a ground unit's particle key, by class, type code and name.
pub fn ground_name(klass: i64, type_code: i64, name: &str) -> &'static str {
    if klass == 9 {
        return "IRSAM";
    }
    match type_code {
        250 => "TANK",
        260 => "TRUCK",
        270 if eq_ic(left(name, 4), "SCUD") => "SCUD",
        270 => "ARMOREDVEHICLE",
        280 => "SOFTVEHICLE",
        290 | 300 | 310 | 320 | 330 | 340 => "SAM",
        350 => "AAA",
        360 => "GUNDISH",
        370 => "SHIP",
        380 => "PATROLSHIP",
        390 => "MISSILESHIP",
        400 => "BUILDING",
        410 => "NUCLEARREACTOR",
        420 => "BRIDGE",
        450 => "RUNWAY",
        _ => "GROUNDTARGET",
    }
}

impl FlightController {
    pub fn new() -> Self {
        Self::default()
    }

    /// One FlightControllerTimer tick (`54b130`): false while the first ticks count down (+0x310), then true (scan).
    pub fn awacs_due(&mut self) -> bool {
        if self.countdown >= 1 {
            self.countdown -= 1;
            return false;
        }
        true
    }

    /// The scan of `54b130` around the player at `player` (the host checked the player: alive, controlled, at
    /// least 50 m above the terrain): every unit inside the sphere and 175 m above its terrain is entered into the
    /// contact table (`54b790`); the calls due, in unit order. `long_always`: +0x314, the player on the FlyTSD.
    pub fn scan(&mut self, player: Vec3, units: &[Unit], long_always: bool) -> Vec<Call> {
        let mut calls = Vec::new();
        for s in &mut self.slots {
            s.seen = false; // 54b980
        }
        for u in units {
            // ponytail: the unit's collision radius ro (≤ 20 m) is left out of the 96 km reach.
            if (u.pos - player).length_squared() >= AWACS_RADIUS * AWACS_RADIUS * 3.0
                || u.ground + CONTACT_AGL >= u.pos.z
            {
                continue;
            }
            let delta = [
                (player.x - u.pos.x) as f32,
                (player.y - u.pos.y) as f32,
                (player.z - u.pos.z) as f32,
            ];
            let dist = (delta[0] * delta[0] + delta[1] * delta[1] + delta[2] * delta[2]).sqrt();
            if !u.enemy && dist > FRIEND_RANGE {
                continue;
            }
            let code = if u.enemy {
                match (u.known, u.rand % 9 == 6) {
                    (false, _) => 3,
                    (true, true) => 2,
                    (true, false) => 1,
                }
            } else {
                0
            };
            let heading = u.heading.rem_euclid(360.0) as f32;
            if let Some(c) = self.contact(u, code, bearing(player, u.pos), dist, heading, delta, long_always) {
                calls.push(c);
            }
        }
        for s in &mut self.slots {
            if !s.seen {
                *s = Slot::default(); // 54b9a0
            }
        }
        calls
    }

    /// `FUN_0054b790`: the contact table's entry for one unit.
    #[allow(clippy::too_many_arguments)]
    fn contact(
        &mut self,
        u: &Unit,
        code: u8,
        bearing: f32,
        dist: f32,
        heading: f32,
        delta: [f32; 3],
        long_always: bool,
    ) -> Option<Call> {
        // Another unit of the same formation name already has a slot: this one is not called (nor kept).
        if self
            .slots
            .iter()
            .any(|s| s.key != u.key && eq_ic(&s.callsign, &u.callsign))
        {
            return None;
        }
        let call = |long, miles| Call {
            long,
            code,
            bearing: tens(bearing),
            miles,
            heading: tens(heading),
        };
        if let Some(s) = self.slots.iter_mut().find(|s| s.key == u.key) {
            s.dist = dist;
            s.seen = true;
            let m = miles(dist)?;
            let long = long_always || matches!(m, 10 | 20 | 30);
            // 54ac20: the lifetime ran out, or the relative position moved more than 5 nm.
            s.life -= 12;
            let moved = || {
                let d = [delta[0] - s.delta[0], delta[1] - s.delta[1], delta[2] - s.delta[2]];
                ((d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt() as i32).abs() / 1854 > 5
            };
            if s.life >= 1 && !moved() {
                return None;
            }
            s.delta = delta;
            s.life = LIFE;
            return Some(call(long, m));
        }
        let s = self.slots.iter_mut().find(|s| s.key.is_empty())?;
        *s = Slot {
            key: u.key.clone(),
            dist,
            delta,
            life: LIFE,
            seen: true,
            callsign: u.callsign.clone(),
        };
        Some(call(true, miles(dist)?))
    }

    /// `FUN_0054c2a0(victim, killer)`, 5 s after the kill: the template and its two %S arguments, or none.
    /// `sides_differ`: the victim and the killer are on different sides.
    pub fn kill(
        &mut self,
        now: f64,
        v: &KillUnit,
        k: &KillUnit,
        sides_differ: bool,
    ) -> Option<(&'static str, String, String)> {
        // The gate (4d4100 on +0x318) fires when now is outside [last, next].
        let fired = !(self.gate[0] <= now && now <= self.gate[1]);
        if fired {
            self.gate = [now, now + KILL_GATE];
        }
        let air = |u: &KillUnit| air_name(u.klass, u.type_code, &u.name).to_string();
        let ground = |u: &KillUnit| ground_name(u.klass, u.type_code, &u.name).to_string();
        // (template, S1, S2, S3); the SHOT_BY_* calls name the killer in S3.
        let (t, s1, mut s2, s3) = if sides_differ {
            if k.air() && v.air() {
                if v.enemy && k.klass == 0x1c {
                    ("SHOT_ENEMY", k.callsign.clone(), air(v), String::new())
                } else if !v.enemy && v.klass == 0x1c {
                    ("SHOT_BY_ENEMY", v.callsign.clone(), String::new(), air(k))
                } else {
                    return None;
                }
            } else if k.air() {
                if k.enemy || k.klass != 0x1c {
                    return None;
                }
                ("SHOT_GROUND_TARGET", k.callsign.clone(), ground(v), String::new())
            } else if k.enemy && v.klass == 0x1c {
                ("SHOT_BY_GROUND_TARGET", v.callsign.clone(), String::new(), ground(k))
            } else {
                return None;
            }
        } else if k.enemy || !k.air() || k.klass != 0x1c {
            return None; // the enemy's own-side kills only log ":Enemy shot its own side target"
        } else {
            (
                "SHOT_FRIENDLY_PHRASE",
                k.callsign.clone(),
                if v.air() { air(v) } else { ground(v) },
                String::new(),
            )
        };
        if t == "SHOT_GROUND_TARGET" {
            // Ground kills by the same callsign inside the gate: the third and later become MULTITARGET, then "".
            if fired {
                self.multi = 1;
            } else if !s1.is_empty() && self.last_kill[0] == s1 && self.last_kill[1] != s2 {
                if self.multi == 2 {
                    s2 = "MULTITARGET".into();
                } else if self.multi > 2 {
                    s2.clear();
                }
                self.multi += 1;
            }
        }
        if s1.is_empty() {
            return None;
        }
        let key = [s1, s2, s3, t.to_string()];
        if !fired && key == self.last_kill {
            return None;
        }
        self.last_kill = key;
        let [s1, s2, s3, _] = &self.last_kill;
        Some((t, s1.clone(), if s3.is_empty() { s2.clone() } else { s3.clone() }))
    }

    /// `FUN_0054de90`: LandedReport is said unless the same callsign was the last one (+0x388).
    pub fn landed(&mut self, callsign: &str) -> bool {
        repeat_filter(&mut self.last_landed, callsign)
    }

    /// `FUN_0054e310`: AirborneReport, the same with +0x38c.
    pub fn airborne(&mut self, callsign: &str) -> bool {
        repeat_filter(&mut self.last_airborne, callsign)
    }
}

fn repeat_filter(last: &mut String, callsign: &str) -> bool {
    if callsign.is_empty() || last == callsign {
        return false;
    }
    *last = callsign.to_string();
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn enemy(key: &str, cs: &str, x: f64, y: f64) -> Unit {
        Unit {
            key: key.into(),
            callsign: cs.into(),
            enemy: true,
            known: true,
            pos: Vec3::new(x, y, 3000.0),
            ground: 0.0,
            heading: 90.0,
            rand: 0,
        }
    }

    #[test]
    fn numbers() {
        let o = Vec3::ZERO;
        assert_eq!(tens(bearing(o, Vec3::new(1000.0, 0.0, 0.0))), 90);
        assert_eq!(tens(bearing(o, Vec3::new(0.0, 1000.0, 0.0))), 360);
        // 6.28 and 57.3248 (180 / 3.14) as coded: due west is 269.95, called "bearing 260".
        assert_eq!(tens(bearing(o, Vec3::new(-1000.0, 0.0, 0.0))), 260);
        assert_eq!(tens(bearing(o, Vec3::new(0.0, -1000.0, 0.0))), 180);
        assert_eq!(miles(1853.0), None);
        assert_eq!(miles(7.6 * 1854.0), Some(7));
        assert_eq!(miles(23.0 * 1854.0), Some(20));
        assert_eq!(miles(36.5 * 1854.0), None);
        assert_eq!(air_name(0x1c, 180, "Mig29 leader"), "MIG29");
        assert_eq!(air_name(3, 225, "C-130Br1"), "C130");
        assert_eq!(air_name(2, 0, "Mi-24 east"), "MI24");
        assert_eq!(ground_name(8, 300, "SA6"), "SAM");
        assert_eq!(ground_name(9, 0, "x"), "IRSAM");
    }

    #[test]
    fn awacs() {
        let mut fc = FlightController::new();
        assert!((0..4).all(|_| !fc.awacs_due()));
        assert!(fc.awacs_due());
        let p = Vec3::new(0.0, 0.0, 3000.0);
        // 15 nm east, a second MiG of the same formation, a friendly, one too low and one out of the sphere.
        let mut low = enemy("c", "Delta", 0.0, 20000.0);
        low.ground = 2900.0;
        let mut friend = enemy("d", "Bravo", 0.0, 5000.0);
        friend.enemy = false;
        let units = [
            enemy("a", "Enemy", 15.2 * 1854.0, 0.0),
            enemy("b", "Enemy", 15.2 * 1854.0, 900.0),
            low,
            friend,
            enemy("e", "Echo", 0.0, 97000.0),
        ];
        let calls = fc.scan(p, &units, false);
        assert_eq!(
            calls,
            vec![Call {
                long: true,
                code: 1,
                bearing: 90,
                miles: 15,
                heading: 90
            }]
        );
        let (t, args) = calls[0].phrase("Alpha");
        assert_eq!(t, "ACFT_FCTRL_LONG");
        assert_eq!(
            args,
            [
                "Alpha_r",
                "BEARING090",
                "MILES15",
                "DESC_TARGET",
                "HEADING090",
                "FREE_TO_ENGAGE"
            ]
        );
        // Known contacts are called again after 5 scans (60 s), short unless at 10 / 20 / 30 nm.
        for _ in 0..4 {
            assert!(fc.scan(p, &units, false).is_empty());
        }
        let c = fc.scan(p, &units, false);
        assert_eq!(c.len(), 1);
        assert!(!c[0].long);
        assert_eq!(c[0].phrase("Alpha").1, ["BEARING090", "MILES15", "DESC_TARGET"]);
        // Moving more than 5 nm calls at once; unidentified when unknown.
        let mut moved = units[0].clone();
        moved.pos.y = 7.0 * 1854.0;
        moved.known = false;
        let c = fc.scan(p, &[moved.clone()], false);
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].code, 3);
        // A contact gone from one scan leaves the table: the next call is a new contact (long).
        assert!(fc.scan(p, &[], false).is_empty());
        assert!(fc.scan(p, &[moved], false)[0].long);
    }

    fn unit(enemy: bool, klass: i64, type_code: i64, cs: &str) -> KillUnit {
        KillUnit {
            enemy,
            klass,
            type_code,
            name: "x".into(),
            callsign: cs.into(),
        }
    }

    #[test]
    fn kills() {
        let mut fc = FlightController::new();
        let me = unit(false, 0x1c, 100, "ALPHALEADER");
        let mig = unit(true, 0x1c, 180, "ENEMYLEADER");
        let sam = unit(true, 8, 300, "");
        assert_eq!(
            fc.kill(0.0, &mig, &me, true),
            Some(("SHOT_ENEMY", "ALPHALEADER".into(), "MIG29".into()))
        );
        // The same call again within 3 s is dropped.
        assert_eq!(fc.kill(1.0, &mig, &me, true), None);
        assert_eq!(
            fc.kill(5.0, &me, &mig, true),
            Some(("SHOT_BY_ENEMY", "ALPHALEADER".into(), "MIG29".into()))
        );
        assert_eq!(
            fc.kill(10.0, &me, &sam, true),
            Some(("SHOT_BY_GROUND_TARGET", "ALPHALEADER".into(), "SAM".into()))
        );
        // Ground kills: the second inside the gate as is, the third MULTITARGET.
        let tank = unit(true, 5, 250, "");
        let truck = unit(true, 5, 260, "");
        let ship = unit(true, 0xd, 370, "");
        assert_eq!(fc.kill(20.0, &tank, &me, true).unwrap().2, "TANK");
        assert_eq!(fc.kill(20.5, &truck, &me, true).unwrap().2, "TRUCK");
        assert_eq!(fc.kill(21.0, &ship, &me, true).unwrap().2, "MULTITARGET");
        // Friendly fire; an enemy's own-side kill says nothing.
        let wing = unit(false, 0x1c, 100, "ALPHAWINGMAN");
        assert_eq!(fc.kill(30.0, &wing, &me, false).unwrap().0, "SHOT_FRIENDLY_PHRASE");
        assert_eq!(fc.kill(40.0, &mig, &mig, false), None);
        // Landed / airborne: not twice in a row for one callsign.
        assert!(fc.landed("ALPHAWINGMAN") && !fc.landed("ALPHAWINGMAN") && fc.landed("ALPHALEADER"));
        assert!(fc.airborne("ALPHAWINGMAN") && !fc.airborne(""));
    }
}
