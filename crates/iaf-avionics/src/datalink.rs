//! Ours, Modern IAF's F-16s (modern-iaf/docs/avionics-plan.md N5, G30): the data link's picture on the HSD and the FCR:
//! the flight's other jets (their own reports) and the AWACS's tracks of the aircraft it sees, while the DL switch is
//! on. The AWACS sees as the game's AWACS calls do (`fctrl`: the 96 km query, aircraft above the terrain + 175 m), and
//! names each track friend or hostile by its side (inferred). World frame X east, Y north, Z up, metres.

use crate::fctrl::{AWACS_RADIUS, CONTACT_AGL};
use crate::vec3::Vec3;

/// The tracks are refreshed this often (inferred).
pub const PERIOD: f64 = 4.0;
/// The AWACS's query (`fctrl`: |p − c|² < r² · 3).
const REACH_SQ: f64 = AWACS_RADIUS * AWACS_RADIUS * 3.0;

/// An aircraft offered to the link.
#[derive(Clone, Debug, Default)]
pub struct Unit {
    pub key: String,
    pub pos: Vec3,
    /// The terrain height under it.
    pub ground: f64,
    /// Degrees clockwise from north.
    pub heading: f64,
    /// m/s.
    pub speed: f64,
    pub friend: bool,
    /// Its place in the player's flight (2, 3, 4), None outside it.
    pub member: Option<u8>,
}

/// A track's symbol.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// A flight member with its number.
    Team(u8),
    Friend,
    Hostile,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Track {
    pub key: String,
    pub pos: Vec3,
    pub heading: f64,
    pub speed: f64,
    pub kind: Kind,
}

#[derive(Clone, Debug, Default)]
pub struct Link {
    pub power: bool,
    tracks: Vec<Track>,
    next: f64,
}

impl Link {
    pub fn tracks(&self) -> &[Track] {
        &self.tracks
    }

    /// The DL switch: off clears the picture; on fills it at the next update.
    pub fn set_power(&mut self, on: bool) {
        self.power = on;
        self.tracks.clear();
        self.next = f64::NEG_INFINITY;
    }

    /// Every frame from the own position: every [`PERIOD`] the flight's members wherever they are, and the AWACS's
    /// tracks within its reach and above the terrain + 175 m.
    pub fn update(&mut self, now: f64, own: Vec3, units: &[Unit]) {
        if !self.power || now < self.next {
            return;
        }
        self.next = now + PERIOD;
        self.tracks = units
            .iter()
            .filter(|u| {
                u.member.is_some() || ((u.pos - own).length_squared() < REACH_SQ && u.pos.z - u.ground > CONTACT_AGL)
            })
            .map(|u| Track {
                key: u.key.clone(),
                pos: u.pos,
                heading: u.heading,
                speed: u.speed,
                kind: match u.member {
                    Some(n) => Kind::Team(n),
                    None if u.friend => Kind::Friend,
                    None => Kind::Hostile,
                },
            })
            .collect();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn members_and_awacs_tracks_with_the_switch() {
        let u = |key: &str, x: f64, z: f64, friend, member| Unit {
            key: key.into(),
            pos: Vec3::new(x, 0.0, z),
            friend,
            member,
            ..Default::default()
        };
        let units = [
            u("two", 300000.0, 3000.0, true, Some(2)),
            u("bandit", 50000.0, 5000.0, false, None),
            u("friend", 20000.0, 4000.0, true, None),
            u("low", 20000.0, 100.0, false, None),
            u("far", 120000.0, 5000.0, false, None),
        ];
        let mut l = Link::default();
        l.update(0.0, Vec3::ZERO, &units);
        assert!(l.tracks().is_empty(), "DL off");
        l.set_power(true);
        l.update(0.0, Vec3::ZERO, &units);
        let kinds: Vec<(&str, Kind)> = l.tracks().iter().map(|t| (t.key.as_str(), t.kind)).collect();
        assert_eq!(kinds, [("two", Kind::Team(2)), ("bandit", Kind::Hostile), ("friend", Kind::Friend)]);
        let moved = [u("bandit", 40000.0, 5000.0, false, None)];
        l.update(1.0, Vec3::ZERO, &moved);
        assert_eq!(l.tracks().len(), 3, "kept until the next refresh");
        l.update(PERIOD, Vec3::ZERO, &moved);
        assert!(l.tracks().len() == 1 && l.tracks()[0].pos.x == 40000.0);
        l.set_power(false);
        assert!(l.tracks().is_empty());
    }
}
