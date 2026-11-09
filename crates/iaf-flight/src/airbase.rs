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

/// The sections, in the TowersManager's record order; Modern IAF's own iaf.ibx adds Hatzerim and Nevatim after them
/// (iaf-2026/docs/data-formats.md §12). The original's file has neither, so the original game reads the same ten.
pub const SECTIONS: [&str; 12] = [
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
    "Hatzerim",
    "Nevatim",
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
            tower: [f(s, "TowerLocX", 302020.0), f(s, "TowerLocY", 397900.0), f(s, "TowerLocZ", 585.0)],
            lineup: [f(s, "LineupLocX", 314800.0), f(s, "LineupLocY", 408890.0), f(s, "LineupLocZ", 585.0)],
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
        SECTIONS.iter().filter_map(|n| ini.section(n)).map(Airbase::from_section).collect()
    }

    /// `551280`: the base whose lineup point is nearest in 3-D.
    pub fn nearest(bases: &[Airbase], p: [f32; 3]) -> Option<&Airbase> {
        let d = |b: &Airbase| (0..3).map(|i| (b.lineup[i] - p[i]).powi(2)).sum::<f32>();
        bases.iter().min_by(|a, b| d(a).total_cmp(&d(b)))
    }

    /// `5521c0`: the nearest hangar within 1000 m.
    pub fn hangar_near(&self, x: f32, y: f32) -> Option<usize> {
        let d = |h: &TaxiPt| (h.x - x).hypot(h.y - y);
        let (i, h) = self.hangars.iter().enumerate().min_by(|a, b| d(a.1).total_cmp(&d(b.1)))?;
        (d(h) < 1000.0).then_some(i)
    }
}

/// Better physics "Wind and turbulence": the tower turns the runway into the wind from this speed up (knots). The
/// missions' winds are 0, 10, 15 or 20 kt, so any announced wind counts and a calm one never does
/// (docs/flight-model.md §10).
pub const INTO_WIND_KT: f32 = 5.0;

/// A runway's length where the setup measured none (the AI's default, docs/world-scale.md §1.2).
pub const DEFAULT_RUNWAY_M: f32 = 3000.0;

/// Whether the tower flies runway `rwy_deg` (true heading) the other way round in a `knots` wind from `from_deg`:
/// the wind at least `INTO_WIND_KT` and more than 90° off the runway's heading (the reverse end is then nearer the
/// wind's direction; at exactly 90° the base keeps its own).
pub fn wind_reverses(rwy_deg: f32, knots: f32, from_deg: f32) -> bool {
    let d = (from_deg - rwy_deg).rem_euclid(360.0);
    knots >= INTO_WIND_KT && d > 90.0 && d < 270.0
}

/// The heading of (dx, dy) (rad, clockwise from north).
fn bearing(dx: f32, dy: f32) -> f32 {
    dx.atan2(dy)
}

/// A runway whose middle lies farther than this from a base's lineup point is another frame's (m): the original game
/// flown over Modern IAF's theatre reads the install's iaf.ibx (1998 frame) beside the theatre's UTM airbases.json.
pub const SAME_BASE_M: f32 = 10_000.0;

impl Airbase {
    /// `ends` when they are this base's runway in this frame (its middle within SAME_BASE_M of the lineup), else None.
    pub fn own_runway(&self, ends: Option<[[f32; 2]; 2]>) -> Option<[[f32; 2]; 2]> {
        ends.filter(|e| {
            let m = [(e[0][0] + e[1][0]) / 2.0, (e[0][1] + e[1][1]) / 2.0];
            (m[0] - self.lineup[0]).hypot(m[1] - self.lineup[1]) <= SAME_BASE_M
        })
    }

    /// The base flown from the main runway's other end (Better physics "Wind and turbulence", docs/autopilot.md §2.4),
    /// in the game's frame. `ends`: the main runway's ends (airbases.json's first runway); None: `DEFAULT_RUNWAY_M`
    /// ahead of the lineup.
    /// - The lineup point mirrored about the runway's middle along its axis (as far from the other threshold), the
    ///   heading +180°.
    /// - Departure: the hangars' path to the old lineup, then down the runway to the new one (a backtrack).
    /// - Arrival: the departure path backwards (from the old lineup's end to the hangar turn point, then the hangar),
    ///   each point's heading toward the next.
    pub fn reversed(&self, ends: Option<[[f32; 2]; 2]>) -> Airbase {
        let h = self.runway_deg.to_radians();
        let d = [h.sin(), h.cos()];
        let l = self.lineup;
        let along = |p: [f32; 2]| (p[0] - l[0]) * d[0] + (p[1] - l[1]) * d[1];
        let s = ends.map_or(DEFAULT_RUNWAY_M, |e| along(e[0]) + along(e[1]));
        let lineup = [l[0] + s * d[0], l[1] + s * d[1], l[2]];
        let runway_deg = (self.runway_deg + 180.0).rem_euclid(360.0);
        let mut from_taxi = self.from_taxi.clone();
        from_taxi.push(TaxiPt { x: lineup[0], y: lineup[1], hdg: hdg(runway_deg) });
        // The arrival: the departure's points backwards, each heading toward the next; the last toward the hangar
        // turn points' middle (one heading for every hangar, as the original's to-taxi path).
        let mut to_taxi: Vec<TaxiPt> = self.from_taxi.iter().rev().copied().collect();
        let n = self.from_hangar_turn.len().max(1) as f32;
        let mid = self.from_hangar_turn.iter().fold([0.0, 0.0], |a, t| [a[0] + t.x / n, a[1] + t.y / n]);
        for i in 0..to_taxi.len() {
            let next = match to_taxi.get(i + 1) {
                Some(q) => [q.x, q.y],
                None if !self.from_hangar_turn.is_empty() => mid,
                None => break,
            };
            to_taxi[i].hdg = bearing(next[0] - to_taxi[i].x, next[1] - to_taxi[i].y);
        }
        let to_hangar_turn = self
            .from_hangar_turn
            .iter()
            .zip(&self.hangars)
            .map(|(t, g)| TaxiPt { hdg: bearing(g.x - t.x, g.y - t.y), ..*t })
            .collect();
        Airbase { lineup, runway_deg, from_taxi, to_taxi, to_hangar_turn, ..self.clone() }
    }

    /// An aircraft placed at this base's lineup (within `LINEUP_ZONE_M` of it, on the ground, within 45° of the
    /// runway's heading) moved to the reversed base `rev`'s: its offset from the lineup turned 180° about it, the
    /// heading +180° (deg). None for any other place.
    pub fn to_reversed_lineup(&self, rev: &Airbase, p: [f32; 3], heading_deg: f32) -> Option<([f32; 3], f32)> {
        let off = [p[0] - self.lineup[0], p[1] - self.lineup[1]];
        let dh = (heading_deg - self.runway_deg).rem_euclid(360.0);
        let aligned = !(45.0..=315.0).contains(&dh);
        let on_ground = p[2] <= self.lineup[2] + 15.0;
        (off[0].hypot(off[1]) < LINEUP_ZONE_M && aligned && on_ground)
            .then(|| ([rev.lineup[0] - off[0], rev.lineup[1] - off[1], p[2]], (heading_deg + 180.0).rem_euclid(360.0)))
    }
}

/// How far from the lineup point a mission's ground start counts as lined up (the tower's "near the lineup" range,
/// 0x60cb38).
pub const LINEUP_ZONE_M: f32 = 400.0;

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

    /// A runway from another frame (UTM ends against a 1998-frame lineup) is not the base's: the default length then.
    #[test]
    fn a_runway_from_another_frame_is_not_the_bases() {
        let b = Airbase { lineup: [317547.0, 411215.0, 580.0], ..Default::default() };
        let near = [[317646.0, 411290.0], [314963.0, 409018.0]];
        let utm = [[658000.0, 3405500.0], [660700.0, 3406700.0]];
        assert_eq!(b.own_runway(Some(near)), Some(near));
        assert_eq!(b.own_runway(Some(utm)), None);
        assert_eq!(b.own_runway(None), None);
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

    /// A straight 3° approach from 5 NM to 500 m at 75 m/s, 60 frames a second: the deviations change smoothly, on
    /// the original game's Ramon (1998 frame) and the sim's (UTM 36N). Max frame-to-frame step 0.01°. The positions
    /// are about the flight's start (a spot 2 km off the lineup), as `IafFlight.ap_setup` takes them: in raw UTM, f32
    /// holds the 3.4 M m northing in 0.25 m steps and the step reaches 0.023° near the runway (measured 2026-11-08).
    #[test]
    fn ils_is_smooth_on_a_straight_approach() {
        for (lineup, rn) in [([317547.0, 411215.0, 580.0], 230.0), ([660563.2, 3406637.2, 633.1], 246.0)] {
            let origin = [lineup[0] as f64 - 1500.0, lineup[1] as f64 - 1400.0];
            let local = [(lineup[0] as f64 - origin[0]) as f32, (lineup[1] as f64 - origin[1]) as f32, lineup[2]];
            let b = [Airbase { lineup: local, runway_deg: rn, ..Default::default() }];
            let back = ((rn as f64) + 180.0).to_radians();
            let (dt, v, start) = (1.0 / 60.0, 75.0, 9260.0);
            let (mut prev, mut max_step): (Option<(f32, f32)>, f32) = (None, 0.0);
            let mut d = start;
            while d > 500.0 {
                let p = [
                    (local[0] as f64 + d * back.sin()) as f32,
                    (local[1] as f64 + d * back.cos()) as f32,
                    (lineup[2] as f64 + d * 3f64.to_radians().tan()) as f32,
                ];
                let (loc, gs) = ils(&b, p).unwrap();
                if let Some((l, g)) = prev {
                    max_step = max_step.max((loc - l).abs().to_degrees()).max((gs - g).abs().to_degrees());
                }
                prev = Some((loc, gs));
                d -= v * dt;
            }
            assert!(max_step < 0.01, "{lineup:?}: max step {max_step}°");
        }
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
