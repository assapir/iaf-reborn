//! Airbase data the AI's ground control loops use (docs/ai.md §6): the ten `iaf.ibx` sections the
//! TowersManager (`DAT_00699344`, ctor `54eb30`) loads with `54eda0(rec, section)`.

use iaf_formats::ini::{Ini, Section};

/// A point of a taxi path: world position (X east, Y north, metres) and the heading of the leg that
/// leaves it (rad, clockwise from north, wrapped to ±π).
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct TaxiPt {
    pub x: f32,
    pub y: f32,
    pub hdg: f32,
}

#[derive(Debug, Clone, Default)]
pub struct Airbase {
    pub name: String,
    pub tower: [f32; 3],
    /// The runway start point (the take-off roll starts here; landings aim at it).
    pub lineup: [f32; 3],
    /// Take-off / landing direction, degrees (`RunwayNumber`).
    pub runway_deg: f32,
    /// Runway → hangars (arrival).
    pub to_taxi: Vec<TaxiPt>,
    /// Hangars → runway (departure).
    pub from_taxi: Vec<TaxiPt>,
    pub hangars: Vec<TaxiPt>,
    pub to_hangar_turn: Vec<TaxiPt>,
    pub from_hangar_turn: Vec<TaxiPt>,
}

/// The sections, in the TowersManager's record order.
pub const SECTIONS: [&str; 10] = [
    "Ramon",
    "David",
    "TelNof",
    "Refidim",
    "Inshas",
    "Damescuss",
    "Kuzeir",
    "Bley",
    "Ryak",
    "Aman",
];

/// `h = fmod(deg, 360); if h > 180: h −= 360; rad`.
fn hdg(deg: f32) -> f32 {
    let mut h = deg % 360.0;
    if h > 180.0 {
        h -= 360.0;
    }
    h.to_radians()
}

fn f(s: &Section, key: &str, default: f32) -> f32 {
    s.f32(key).unwrap_or(default)
}

fn pts(s: &Section, prefix: &str, n: usize) -> Vec<TaxiPt> {
    (0..n)
        .map(|i| TaxiPt {
            x: f(s, &format!("{prefix}X{i}"), 0.0),
            y: f(s, &format!("{prefix}Y{i}"), 0.0),
            hdg: hdg(f(s, &format!("{prefix}Hdg{i}"), 0.0)),
        })
        .collect()
}

impl Airbase {
    /// `54eda0`; the exe defaults for a missing tower / lineup (Ramon-like values).
    pub fn from_section(s: &Section) -> Self {
        let n = |k: &str| s.i32(k).unwrap_or(0).max(0) as usize;
        let nh = n("HangarsNum");
        Airbase {
            name: s.name.clone(),
            tower: [
                f(s, "TowerLocX", 302020.0),
                f(s, "TowerLocY", 397900.0),
                f(s, "TowerLocZ", 585.0),
            ],
            lineup: [
                f(s, "LineupLocX", 314800.0),
                f(s, "LineupLocY", 408890.0),
                f(s, "LineupLocZ", 585.0),
            ],
            runway_deg: s.i32("RunwayNumber").unwrap_or(5) as f32,
            to_taxi: pts(s, "ToTaxiPt", n("TaxiWayPtsTo")),
            from_taxi: pts(s, "FromTaxiPt", n("TaxiWayPtsFrom")),
            hangars: pts(s, "HangarPt", nh),
            to_hangar_turn: pts(s, "ToHangarTurnPt", nh),
            from_hangar_turn: pts(s, "FromHangarTurnPt", nh),
        }
    }

    /// Every airbase of an `iaf.ibx`.
    pub fn load_all(iaf_ibx: &[u8]) -> Vec<Airbase> {
        let ini = Ini::parse(iaf_ibx);
        SECTIONS
            .iter()
            .filter_map(|n| ini.section(n))
            .map(Airbase::from_section)
            .collect()
    }

    /// `551280`: the base whose lineup point is nearest in 3-D.
    pub fn nearest(bases: &[Airbase], p: [f32; 3]) -> Option<&Airbase> {
        let d = |b: &Airbase| (0..3).map(|i| (b.lineup[i] - p[i]).powi(2)).sum::<f32>();
        bases.iter().min_by(|a, b| d(a).total_cmp(&d(b)))
    }

    /// `5521c0`: the nearest hangar within 1000 m.
    pub fn hangar_near(&self, x: f32, y: f32) -> Option<usize> {
        let d = |h: &TaxiPt| (h.x - x).hypot(h.y - y);
        let (i, h) = self
            .hangars
            .iter()
            .enumerate()
            .min_by(|a, b| d(a.1).total_cmp(&d(b.1)))?;
        (d(h) < 1000.0).then_some(i)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_base() {
        let ini = b"[David]\r\nTowerLocX=353954.0\r\nLineupLocX=356483.0\r\nLineupLocY=602383.0\r\nLineupLocZ=63\r\nRunwayNumber=270\r\nTaxiWayPtsFrom=1\r\nFromTaxiPtX0=354934.0\r\nFromTaxiPtY0=602088.0\r\nFromTaxiPtHdg0=270\r\nHangarsNum=0\r\n";
        let b = Airbase::load_all(ini);
        assert_eq!(b.len(), 1);
        assert_eq!(b[0].lineup, [356483.0, 602383.0, 63.0]);
        assert_eq!(b[0].runway_deg, 270.0);
        assert!((b[0].from_taxi[0].hdg + 90f32.to_radians()).abs() < 1e-6);
    }
}
