//! Modern IAF's AWACS controller (docs/ai.md §24): the player's requests by the radio menu's AWACS page (picture,
//! bogey dope, declare, a vector to the target, home or the tanker), answered in NATO brevity from the controller's
//! sensor: the Eitam's radar where it flies, or the 1998 game's virtual AWACS round the player where the flight has no
//! Eitam. A lost Eitam ends the service. The host gathers the contacts and says the lines (`shared/audio/radio.gd`).
//! World frame X east, Y north, Z up, metres.

use crate::flight::flat;
use crate::{site, sort};
use iaf_avionics::fctrl;
use iaf_flight::Vec3;

/// The EL/W-2085's tracking range: "to a range of 243 nmi (450 km)" (Wikipedia, IAI EL/W-2085).
pub const EITAM_RANGE_M: f64 = 450_000.0;
/// The virtual AWACS's reach round the player (`fctrl`'s query, |p − c|² < r² · 3: 96.3 km).
const VIRTUAL_REACH_SQ: f64 = fctrl::AWACS_RADIUS * fctrl::AWACS_RADIUS * 3.0;
/// A picture names at most this many groups, the nearest first (inferred: the picture's words stay short).
pub const PICTURE_GROUPS: usize = 3;
/// The farthest group a picture or bogey dope names (NM; the farthest range said, inferred).
pub const MAX_MILES: f64 = 250.0;
const FT: f64 = 0.3048;

/// A contact's identity in the controller's words (NATO HOSTILE, BOGEY, FRIENDLY).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ident {
    Hostile,
    Bogey,
    Friendly,
}

impl Ident {
    fn particle(self) -> &'static str {
        match self {
            Ident::Hostile => "AWX_HOSTILE",
            Ident::Bogey => "AWX_BOGEY",
            Ident::Friendly => "AWX_FRIENDLY",
        }
    }
}

/// An aircraft offered to the controller (alive, in the air).
#[derive(Clone, Debug)]
pub struct Contact {
    pub key: String,
    pub pos: Vec3,
    /// The terrain height under it.
    pub ground: f64,
    /// Compass heading, degrees.
    pub heading: f64,
    pub ident: Ident,
    /// A friendly tanker (air refuelling's; none flies yet).
    pub tanker: bool,
}

/// Where the controller's picture comes from.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Sensor {
    /// No Eitam in the flight: the 1998 game's AWACS, a sphere round the player (`fctrl`).
    Virtual,
    /// The Eitam's radar at its position.
    Eitam(Vec3),
    /// The Eitam was shot down: no service.
    Lost,
}

/// A request of the radio menu's AWACS page.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Request {
    Picture,
    BogeyDope,
    /// The identity of the player's radar's locked track (its key, None without a lock).
    Declare,
    /// A vector to the target: Scramble's task target where the flight has one, else the nearest hostile group.
    VectorTarget,
    VectorHome,
    VectorTanker,
}

/// Why a request cannot be made now (the menu shows its line off with this reason).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// The Eitam is lost.
    Lost,
    /// Declare without a radar lock.
    NoLock,
    /// No tanker in the air.
    NoTanker,
    /// No home base known.
    NoHome,
}

impl Refusal {
    pub fn id(self) -> &'static str {
        match self {
            Refusal::Lost => "lost",
            Refusal::NoLock => "no_lock",
            Refusal::NoTanker => "no_tanker",
            Refusal::NoHome => "no_home",
        }
    }
}

/// One spoken line: the template and its %S particles (voices.json).
pub type Line = (&'static str, Vec<String>);

/// A group the answer named: where from the player (for the flight's "contact", `Flight::awacs`).
#[derive(Clone, Debug, PartialEq)]
pub struct Named {
    pub bearing: i32,
    pub miles: i32,
    pub hostile: bool,
}

/// The controller's answer: its lines in order, and the groups it named.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Answer {
    pub lines: Vec<Line>,
    pub named: Vec<Named>,
}

/// What the request needs besides the contacts.
#[derive(Clone, Debug, Default)]
pub struct Ask {
    /// The player's formation name ("Alpha").
    pub callsign: String,
    pub player: Vec3,
    /// The player's radar's locked track (a contact's key).
    pub locked: Option<String>,
    /// Scramble's task target (its nearest), where the flight has one.
    pub task: Option<Vec3>,
    /// The flight's home base.
    pub home: Option<Vec3>,
}

/// The sensor sees `c`: above the terrain + 175 m (the AWACS calls' and the data link's floor, `fctrl`), and the
/// Eitam inside its range over the earth's curvature (the sites' radar horizon, `site::visible`, at sea level), or the
/// virtual AWACS inside its sphere round the player.
pub fn sees(sensor: Sensor, player: Vec3, c: &Contact) -> bool {
    if c.pos.z - c.ground <= fctrl::CONTACT_AGL {
        return false;
    }
    match sensor {
        Sensor::Virtual => (c.pos - player).length_squared() < VIRTUAL_REACH_SQ,
        Sensor::Eitam(at) => c.pos.distance(at) <= EITAM_RANGE_M && site::visible(at, c.pos, &|_| None),
        Sensor::Lost => false,
    }
}

/// A range in the controller's words (m → NM, truncated): 1 to 10 as they are, then fives to 50, tens to 150, fifties
/// to 250 (voices.json's MILESnn particles: MILES100 to MILES250 come with the AWACS page's voices, §24.6).
pub fn miles(dist: f64) -> i32 {
    let m = (dist / 1852.0) as i32;
    match m {
        ..=1 => 1,
        2..=10 => m,
        11..=50 => m - m % 5,
        51..=150 => m - m % 10,
        _ => (m - m % 50).min(MAX_MILES as i32),
    }
}

/// A height in thousands of feet, as the controller says it (rounded: 1 to 10, then fives to 50; inferred).
pub fn thousands(z: f64) -> i32 {
    let k = (z / FT / 1000.0).round() as i32;
    match k {
        ..=1 => 1,
        2..=10 => k,
        _ => ((k + 2) / 5 * 5).min(50),
    }
}

/// The group's aspect to the player by the angle off its nose of the line to the player (degrees): HOT 0–30, FLANK
/// 31–70, BEAM 71–120, DRAG 121–180 (NATO; the brevity's "from nose" ranges).
pub fn aspect(group_heading: f64, group: Vec3, player: Vec3) -> &'static str {
    let to_player = fctrl::bearing(group, player) as f64;
    let off = (to_player - group_heading).rem_euclid(360.0);
    let off = if off > 180.0 { 360.0 - off } else { off };
    match off {
        x if x <= 30.0 => "AWX_HOT",
        x if x <= 70.0 => "AWX_FLANK",
        x if x <= 120.0 => "AWX_BEAM",
        _ => "AWX_DRAG",
    }
}

pub(crate) struct Group {
    pub pos: Vec3,
    pub top: f64,
    pub heading: f64,
    pub ident: Ident,
    /// From the requester (m, horizontal).
    pub dist: f64,
}

/// The groups of the contacts the sensor sees, nearest the player first (NATO GROUP: within 3 NM); a group is
/// hostile when any of its contacts is, else a bogey; its heading its first contact's, its height the highest.
pub(crate) fn groups(
    sensor: Sensor,
    player: Vec3,
    contacts: &[Contact],
    pick: impl Fn(&Contact) -> bool,
) -> Vec<Group> {
    let seen: Vec<&Contact> = contacts.iter().filter(|c| pick(c) && sees(sensor, player, c)).collect();
    let pts: Vec<Vec3> = seen.iter().map(|c| c.pos).collect();
    let mut out: Vec<Group> = sort::groups(&pts)
        .into_iter()
        .map(|g| {
            let cs: Vec<&Contact> = g.iter().map(|&i| seen[i]).collect();
            let pos = sort::centre(&g.iter().map(|&i| pts[i]).collect::<Vec<_>>());
            let ident = if cs.iter().any(|c| c.ident == Ident::Hostile) { Ident::Hostile } else { cs[0].ident };
            Group {
                pos,
                top: cs.iter().map(|c| c.pos.z).fold(f64::MIN, f64::max),
                heading: cs[0].heading,
                ident,
                dist: flat(pos, player),
            }
        })
        .filter(|g| g.dist / 1852.0 < MAX_MILES + 1.0)
        .collect();
    out.sort_by(|a, b| a.dist.total_cmp(&b.dist));
    out
}

fn bearing_key(from: Vec3, to: Vec3) -> (i32, String) {
    let b = fctrl::tens(fctrl::bearing(from, to));
    (b, format!("BEARING{b:03}"))
}

/// The group's BRAA fill-ins: bearing, range, altitude, aspect and identity.
fn braa(g: &Group, player: Vec3) -> (Vec<String>, Named) {
    let (b, bk) = bearing_key(player, g.pos);
    let m = miles(g.dist);
    let args = vec![
        bk,
        format!("MILES{m:02}"),
        format!("AWX_ALT{:02}", thousands(g.top)),
        aspect(g.heading, g.pos, player).into(),
        g.ident.particle().into(),
    ];
    (args, Named { bearing: b, miles: m, hostile: g.ident == Ident::Hostile })
}

fn hostile_or_bogey(c: &Contact) -> bool {
    c.ident != Ident::Friendly
}

/// The request can be made now, or why not.
pub fn check(sensor: Sensor, req: Request, ask: &Ask, contacts: &[Contact]) -> Result<(), Refusal> {
    if sensor == Sensor::Lost {
        return Err(Refusal::Lost);
    }
    match req {
        Request::Declare if ask.locked.is_none() => Err(Refusal::NoLock),
        Request::VectorHome if ask.home.is_none() => Err(Refusal::NoHome),
        Request::VectorTanker if !contacts.iter().any(|c| c.tanker && c.ident == Ident::Friendly) => {
            Err(Refusal::NoTanker)
        }
        _ => Ok(()),
    }
}

/// The controller's answer to `req` (empty when [`check`] refuses it):
/// - picture: "Kidon 1, two groups." then each group's BRAA, the nearest [`PICTURE_GROUPS`] ("Group bearing 040, 25
///   miles, 20 thousand, hot, hostile."); "Kidon 1, clean." when it sees none;
/// - bogey dope: the nearest group's BRAA ("Kidon 1, group bearing …"), or clean;
/// - declare: the locked track's identity ("Kidon 1, hostile."), or clean when the sensor does not see it;
/// - vector: "Kidon 1, vector 040, 25 miles, target / home plate / tanker." (clean for a target when there is none).
pub fn answer(sensor: Sensor, req: Request, ask: &Ask, contacts: &[Contact]) -> Answer {
    if check(sensor, req, ask, contacts).is_err() {
        return Answer::default();
    }
    let cs = format!("{}_r", ask.callsign);
    let p = ask.player;
    let clean = || Answer { lines: vec![("AWX_CLEAN", vec![cs.clone()])], named: vec![] };
    let vector = |to: Vec3, what: &str| {
        let b = fctrl::tens(fctrl::bearing(p, to));
        let args =
            vec![cs.clone(), format!("AWX_VECTOR{b:03}"), format!("MILES{:02}", miles(flat(p, to))), what.into()];
        Answer { lines: vec![("AWX_VECTOR", args)], named: vec![] }
    };
    match req {
        Request::Picture => {
            let gs = groups(sensor, p, contacts, hostile_or_bogey);
            if gs.is_empty() {
                return clean();
            }
            let mut a = Answer {
                lines: vec![("AWX_PICTURE", vec![cs, format!("AWX_GROUPS{}", gs.len().min(9))])],
                named: vec![],
            };
            for g in gs.iter().take(PICTURE_GROUPS) {
                let (args, n) = braa(g, p);
                a.lines.push(("AWX_GROUP", args));
                a.named.push(n);
            }
            a
        }
        Request::BogeyDope => match groups(sensor, p, contacts, hostile_or_bogey).first() {
            None => clean(),
            Some(g) => {
                let (args, n) = braa(g, p);
                Answer { lines: vec![("AWX_BRAA", [vec![cs], args].concat())], named: vec![n] }
            }
        },
        Request::Declare => {
            let c = contacts.iter().find(|c| Some(&c.key) == ask.locked.as_ref() && sees(sensor, p, c));
            match c {
                None => clean(),
                Some(c) => Answer { lines: vec![("AWX_DECLARE", vec![cs, c.ident.particle().into()])], named: vec![] },
            }
        }
        Request::VectorTarget => {
            let to =
                ask.task.or_else(|| groups(sensor, p, contacts, |c| c.ident == Ident::Hostile).first().map(|g| g.pos));
            match to {
                None => clean(),
                Some(to) => vector(to, "DESC_TARGET"),
            }
        }
        Request::VectorHome => vector(ask.home.unwrap_or(p), "AWX_HOME_PLATE"),
        Request::VectorTanker => {
            let t = contacts
                .iter()
                .filter(|c| c.tanker && c.ident == Ident::Friendly)
                .min_by(|a, b| flat(a.pos, p).total_cmp(&flat(b.pos, p)));
            match t {
                None => clean(),
                Some(t) => vector(t.pos, "AWX_TANKER"),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NM: f64 = 1852.0;

    fn c(key: &str, x_nm: f64, y_nm: f64, alt_ft: f64, heading: f64, ident: Ident) -> Contact {
        Contact {
            key: key.into(),
            pos: Vec3::new(x_nm * NM, y_nm * NM, alt_ft * FT),
            ground: 0.0,
            heading,
            ident,
            tanker: false,
        }
    }

    fn ask() -> Ask {
        Ask { callsign: "Alpha".into(), player: Vec3::new(0.0, 0.0, 6000.0), ..Default::default() }
    }

    #[test]
    fn the_words() {
        assert_eq!([0.5, 7.6, 23.0, 57.0, 149.0, 199.0, 600.0].map(|n| miles(n * NM)), [1, 7, 20, 50, 140, 150, 250]);
        assert_eq!(
            [300.0, 5_200.0, 20_400.0, 23_000.0, 41_000.0, 70_000.0].map(|f| thousands(f * FT)),
            [1, 5, 20, 25, 40, 50]
        );
        let o = Vec3::ZERO;
        let north = Vec3::new(0.0, 30.0 * NM, 0.0);
        // A group 30 NM north: heading south is hot, east beam, north drag, south-east (45° off) flank.
        assert_eq!(aspect(180.0, north, o), "AWX_HOT");
        assert_eq!(aspect(90.0, north, o), "AWX_BEAM");
        assert_eq!(aspect(0.0, north, o), "AWX_DRAG");
        assert_eq!(aspect(135.0, north, o), "AWX_FLANK");
    }

    #[test]
    fn picture_and_bogey_dope() {
        let cs = [
            c("mig1", 0.0, 30.0, 20_000.0, 180.0, Ident::Hostile),
            c("mig2", 1.0, 30.5, 21_000.0, 180.0, Ident::Hostile),
            c("bogey", 40.0, 0.0, 10_000.0, 90.0, Ident::Bogey),
            c("friend", -10.0, 0.0, 15_000.0, 0.0, Ident::Friendly),
            c("far", 0.0, -60.0, 30_000.0, 0.0, Ident::Hostile),
        ];
        // The virtual AWACS sees 52 NM round the player: the far one is left out.
        let a = answer(Sensor::Virtual, Request::Picture, &ask(), &cs);
        assert_eq!(a.lines[0], ("AWX_PICTURE", vec!["Alpha_r".into(), "AWX_GROUPS2".into()]));
        let want: Vec<String> =
            ["BEARING360", "MILES30", "AWX_ALT20", "AWX_HOT", "AWX_HOSTILE"].map(String::from).into();
        assert_eq!(a.lines[1], ("AWX_GROUP", want));
        assert_eq!(a.lines[2].1[4], "AWX_BOGEY");
        assert_eq!(a.named[0], Named { bearing: 360, miles: 30, hostile: true });
        assert_eq!(a.named.len(), 2);
        // The Eitam 100 NM south at 41,000 ft sees all three groups (the far one too).
        let eitam = Sensor::Eitam(Vec3::new(0.0, -100.0 * NM, 41_000.0 * FT));
        let a = answer(eitam, Request::Picture, &ask(), &cs);
        assert_eq!(a.lines[0].1[1], "AWX_GROUPS3");
        let b = answer(eitam, Request::BogeyDope, &ask(), &cs);
        assert_eq!(b.lines.len(), 1);
        assert_eq!(b.lines[0].0, "AWX_BRAA");
        assert_eq!(b.lines[0].1[..3], ["Alpha_r", "BEARING360", "MILES30"]);
        // Nothing seen: clean.
        assert_eq!(answer(eitam, Request::BogeyDope, &ask(), &[]).lines, [("AWX_CLEAN", vec!["Alpha_r".to_string()])]);
    }

    #[test]
    fn the_eitam_sees_over_the_horizon_only_so_far() {
        let at = Vec3::new(0.0, 0.0, 41_000.0 * FT);
        let e = Sensor::Eitam(at);
        let p = Vec3::ZERO;
        // 240 NM out at 30,000 ft: in range and above the horizon (≈ 900 km for the two heights).
        assert!(sees(e, p, &c("a", 0.0, 240.0, 30_000.0, 0.0, Ident::Hostile)));
        // Beyond its 450 km.
        assert!(!sees(e, p, &c("b", 0.0, 250.0, 30_000.0, 0.0, Ident::Hostile)));
        // From 20,000 ft its horizon is about 320 km: 230 NM out a jet at 1,000 ft (horizon 72 km) is under it.
        let e20 = Sensor::Eitam(Vec3::new(0.0, 0.0, 20_000.0 * FT));
        assert!(!sees(e20, p, &c("c", 0.0, 230.0, 1_000.0, 0.0, Ident::Hostile)));
        assert!(sees(e20, p, &c("c", 0.0, 230.0, 30_000.0, 0.0, Ident::Hostile)));
        // Under the 175 m floor; and lost sees nothing.
        assert!(!sees(e, p, &c("d", 0.0, 10.0, 400.0, 0.0, Ident::Hostile)));
        assert!(!sees(Sensor::Lost, p, &c("a", 0.0, 10.0, 30_000.0, 0.0, Ident::Hostile)));
    }

    #[test]
    fn declare_and_vectors() {
        let mut tanker = c("kc", -20.0, -20.0, 25_000.0, 90.0, Ident::Friendly);
        tanker.tanker = true;
        let cs = [c("mig", 0.0, 30.0, 20_000.0, 180.0, Ident::Hostile), tanker.clone()];
        let mut q = ask();
        assert_eq!(check(Sensor::Virtual, Request::Declare, &q, &cs), Err(Refusal::NoLock));
        q.locked = Some("mig".into());
        let a = answer(Sensor::Virtual, Request::Declare, &q, &cs);
        assert_eq!(a.lines, [("AWX_DECLARE", vec!["Alpha_r".to_string(), "AWX_HOSTILE".into()])]);
        q.locked = Some("gone".into());
        assert_eq!(answer(Sensor::Virtual, Request::Declare, &q, &cs).lines[0].0, "AWX_CLEAN");
        // The target: the task's target when the flight has one, else the nearest hostile group.
        let v = answer(Sensor::Virtual, Request::VectorTarget, &q, &cs);
        assert_eq!(v.lines[0].1, ["Alpha_r", "AWX_VECTOR360", "MILES30", "DESC_TARGET"]);
        q.task = Some(Vec3::new(40.0 * NM, 0.0, 0.0));
        assert_eq!(
            answer(Sensor::Virtual, Request::VectorTarget, &q, &cs).lines[0].1[1..3],
            ["AWX_VECTOR090", "MILES40"]
        );
        // Home: refused without a base; the tanker: refused with none in the air (none flies yet).
        assert_eq!(check(Sensor::Virtual, Request::VectorHome, &q, &cs), Err(Refusal::NoHome));
        q.home = Some(Vec3::new(0.0, -80.0 * NM, 0.0));
        let h = answer(Sensor::Virtual, Request::VectorHome, &q, &cs);
        assert_eq!(h.lines[0].1, ["Alpha_r", "AWX_VECTOR180", "MILES80", "AWX_HOME_PLATE"]);
        let t = answer(Sensor::Virtual, Request::VectorTanker, &q, &cs);
        assert_eq!(t.lines[0].1[3], "AWX_TANKER");
        tanker.tanker = false;
        assert_eq!(check(Sensor::Virtual, Request::VectorTanker, &q, &[tanker]), Err(Refusal::NoTanker));
        // Lost: everything refused and unanswered.
        assert_eq!(check(Sensor::Lost, Request::Picture, &q, &cs), Err(Refusal::Lost));
        assert!(answer(Sensor::Lost, Request::Picture, &q, &cs).lines.is_empty());
    }
}
