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

/// The HUD ILS reference glide path, −5° (`0x82f678`, set from −5.0 at `0x45fbce`).
pub const ILS_GLIDE_DEG: f32 = -5.0;
/// The localizer / glideslope deviation limits (`0x82f670` 19°, `0x82f67c` 5°).
pub const ILS_LOC_LIMIT_DEG: f32 = 19.0;
pub const ILS_GS_LIMIT_DEG: f32 = 5.0;

/// `5bdd50`: `fmod(a, 2π)` then into (−π, π].
fn wrap_pi(a: f32) -> f32 {
    let two_pi = 2.0 * std::f32::consts::PI;
    let mut r = a % two_pi;
    if r > std::f32::consts::PI {
        r -= two_pi;
    } else if r < -std::f32::consts::PI {
        r += two_pi;
    }
    r
}

/// The HUD ILS deviations (the NAV HUD mode object's update `460130`, docs/cockpit.md "ILS"): the base whose
/// lineup point is nearest in 2-D (`5511a0`), u = the unit vector from the jet at `p` to that lineup point;
/// localizer = wrap(atan2(u.x, u.y) − RunwayNumber) clamped ±19°, glideslope = wrap(−5° − asin(u.z)) clamped ±5°
/// (radians; both 0 on the 5° glide path down the runway heading; + = the runway point right of / below the
/// path). All in f32 as the original. None without a base.
pub fn ils(bases: &[Airbase], p: [f32; 3]) -> Option<(f32, f32)> {
    let mut best: Option<(&Airbase, f32)> = None;
    for b in bases {
        let d = ((b.lineup[1] - p[1]) * (b.lineup[1] - p[1]) + (b.lineup[0] - p[0]) * (b.lineup[0] - p[0])).sqrt();
        if best.is_none_or(|(_, m)| m == 0.0 || d < m) {
            best = Some((b, d));
        }
    }
    let b = best?.0;
    let d = [b.lineup[0] - p[0], b.lineup[1] - p[1], b.lineup[2] - p[2]];
    let len = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
    let k = if len == 0.0 { 1.0 } else { 1.0 / len };
    let u = [d[0] * k, d[1] * k, d[2] * k];
    let lim_gs = ILS_GS_LIMIT_DEG.to_radians();
    let gs = wrap_pi(ILS_GLIDE_DEG.to_radians() - u[2].clamp(-1.0, 1.0).asin()).clamp(-lim_gs, lim_gs);
    let bearing = if u[0] == 0.0 && u[1] == 0.0 { 0.0 } else { u[0].atan2(u[1]) };
    // RunwayNumber is read as an int (`54eda0` __ftol), then fmod 360 into ±180° (`459bd0`) and radians.
    let rn = hdg((b.runway_deg as i32) as f32);
    let lim_loc = ILS_LOC_LIMIT_DEG.to_radians();
    let loc = wrap_pi(wrap_pi(bearing) - rn).clamp(-lim_loc, lim_loc);
    Some((loc, gs))
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

    fn base(rn: f32) -> Airbase {
        Airbase { lineup: [1000.0, 2000.0, 100.0], runway_deg: rn, ..Default::default() }
    }

    #[test]
    fn ils_centres_on_the_5_degree_path_down_the_runway() {
        // Runway 090 (landing east): 3 km west of the lineup point, 5° above it.
        let b = [base(90.0)];
        let h = 3000.0 * 5f32.to_radians().tan();
        let (loc, gs) = ils(&b, [-2000.0, 2000.0, 100.0 + h]).unwrap();
        assert!(loc.abs() < 1e-4 && gs.abs() < 1e-4, "{loc} {gs}");
        // Higher: the glideslope line goes down (+); 1° steeper → +1°.
        let h6 = 3000.0 * 6f32.to_radians().tan();
        let (_, gs) = ils(&b, [-2000.0, 2000.0, 100.0 + h6]).unwrap();
        assert!((gs.to_degrees() - 1.0).abs() < 0.01, "{}", gs.to_degrees());
        // North of the centreline (left of it, landing east): the runway point is to the right (+).
        let (loc, _) = ils(&b, [-2000.0, 2000.0 + 3000.0 * 2f32.to_radians().tan(), 100.0 + h]).unwrap();
        assert!((loc.to_degrees() - 2.0).abs() < 0.01, "{}", loc.to_degrees());
        // Limits: ±19° and ±5°.
        let (loc, gs) = ils(&b, [1000.0, 0.0, 5000.0]).unwrap();
        assert!((loc.to_degrees() + 19.0).abs() < 1e-3 && (gs.to_degrees() - 5.0).abs() < 1e-3, "{loc} {gs}");
    }

    #[test]
    fn ils_uses_the_nearest_lineup_in_2d() {
        let mut far = base(270.0);
        far.lineup = [50000.0, 2000.0, 100.0];
        let b = [far, base(90.0)];
        let (loc, _) = ils(&b, [-2000.0, 2000.0, 400.0]).unwrap();
        assert!(loc.abs() < 1e-4);
        assert!(ils(&[], [0.0; 3]).is_none());
    }
}
