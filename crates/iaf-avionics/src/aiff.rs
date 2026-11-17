//! Ours, Modern IAF's Sufa (modern-iaf/docs/avionics-plan.md R15, G13): the AIFF interrogator (the AN/APX-113 class,
//! docs/real-hud.md "IFF"). TMS left under half a second asks a SCAN interrogation (±60° in azimuth and elevation),
//! half a second or more a line-of-sight one (LOS, ±15° in azimuth about the FCR's cursor) (MLU M1 pp. 52–54). The
//! replies show where they came from: a green circle for a friend, a yellow square for an unknown reply, nothing for
//! no reply (MLU M1 p. 53); a SCAN blanks the FCR's own targets meanwhile. World frame X east, Y north, Z up, metres.

use crate::vec3::{Vec3, wrap_pi};

const DEG: f64 = std::f64::consts::PI / 180.0;
/// SCAN's volume: ±60° in azimuth and elevation (MLU M1 p. 53).
pub const SCAN_HALF: f64 = 60.0 * DEG;
/// LOS's volume: ±15° in azimuth about the cursor (MLU M1 p. 53); its elevation as SCAN's (inferred).
pub const LOS_HALF: f64 = 15.0 * DEG;
/// The interrogator's reach (inferred: the FCR's longest scale).
pub const RANGE_M: f64 = 160.0 * 1852.0;
/// A reply shows this long (a simulator guide's 3 s; docs/real-hud.md "IFF").
pub const SHOW_S: f64 = 3.0;
/// A SCAN blanks the FCR's targets this long (inferred).
pub const BLANK_S: f64 = 1.0;

/// How a unit answers: a friend's correct reply, a reply of unknown nature, or none.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Answer {
    Friend,
    Unknown,
    None,
}

/// A unit offered to the interrogation.
#[derive(Clone, Debug)]
pub struct Target {
    pub key: String,
    pub pos: Vec3,
    pub answer: Answer,
}

/// A reply where it came from.
#[derive(Clone, Debug, PartialEq)]
pub struct Reply {
    pub key: String,
    pub pos: Vec3,
    pub friend: bool,
}

/// The own jet: its position, heading and pitch (radians).
#[derive(Clone, Copy, Debug, Default)]
pub struct Own {
    pub pos: Vec3,
    pub heading: f64,
    pub pitch: f64,
}

#[derive(Clone, Debug, Default)]
pub struct Aiff {
    /// The last interrogation: Some(true) LOS, Some(false) SCAN (the DED's INTG page).
    pub last: Option<bool>,
    replies: Vec<Reply>,
    until: f64,
    blank_until: f64,
}

impl Aiff {
    /// An interrogation from `own`, LOS about the cursor's azimuth `cursor_az` (radians off the nose, right +) or
    /// SCAN: the targets in the volume and in reach that answer reply.
    pub fn interrogate(&mut self, los: bool, own: &Own, cursor_az: f64, targets: &[Target], now: f64) {
        let (centre, half) = if los { (cursor_az, LOS_HALF) } else { (0.0, SCAN_HALF) };
        self.replies = targets
            .iter()
            .filter(|t| t.answer != Answer::None)
            .filter(|t| {
                let d = t.pos - own.pos;
                let az = wrap_pi(d.x.atan2(d.y) - own.heading - centre);
                let el = d.z.atan2(d.x.hypot(d.y)) - own.pitch;
                d.length() <= RANGE_M && az.abs() <= half && el.abs() <= SCAN_HALF
            })
            .map(|t| Reply { key: t.key.clone(), pos: t.pos, friend: t.answer == Answer::Friend })
            .collect();
        self.until = now + SHOW_S;
        self.last = Some(los);
        if !los {
            self.blank_until = now + BLANK_S;
        }
    }

    /// The replies on show.
    pub fn replies(&self, now: f64) -> &[Reply] {
        if now < self.until { &self.replies } else { &[] }
    }

    /// A SCAN is blanking the FCR's own targets.
    pub fn blanking(&self, now: f64) -> bool {
        now < self.blank_until
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn friends_reply_hostiles_do_not() {
        let t = |key: &str, x, y, answer| Target { key: key.into(), pos: Vec3::new(x, y, 0.0), answer };
        let targets = [
            t("friend", 0.0, 20000.0, Answer::Friend),
            t("hostile", 1000.0, 20000.0, Answer::None),
            t("unknown", -5000.0, 20000.0, Answer::Unknown),
            t("behind", 0.0, -20000.0, Answer::Friend),
            t("wide", 20000.0, 2000.0, Answer::Friend),
            t("far", 0.0, 400000.0, Answer::Friend),
        ];
        let mut a = Aiff::default();
        a.interrogate(false, &Own::default(), 0.0, &targets, 10.0);
        let r = a.replies(10.5);
        assert_eq!(r.iter().map(|r| r.key.as_str()).collect::<Vec<_>>(), ["friend", "unknown"]);
        assert!(r[0].friend && !r[1].friend && a.blanking(10.5) && !a.blanking(11.5));
        assert!(a.replies(13.1).is_empty(), "shown 3 s");
        // LOS about a cursor 80° right: only the wide one.
        a.interrogate(true, &Own::default(), 80.0 * DEG, &targets, 20.0);
        assert_eq!(a.replies(20.0).iter().map(|r| r.key.as_str()).collect::<Vec<_>>(), ["wide"]);
        assert!(!a.blanking(20.0) && a.last == Some(true), "LOS leaves the targets on the FCR");
        // Heading south, SCAN: the one behind is ahead now.
        let south = Own { heading: std::f64::consts::PI, ..Own::default() };
        a.interrogate(false, &south, 0.0, &targets, 30.0);
        assert_eq!(a.replies(30.0).iter().map(|r| r.key.as_str()).collect::<Vec<_>>(), ["behind"]);
    }
}
