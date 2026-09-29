//! Flight envelope (`16.dat` & co.): minimum speed per integer load factor and
//! altitude (`FUN_005b23c0`, `FUN_005b1fa0`, `FUN_005b2810`).
//!
//! Faithful quirk: rows are parsed with `%d %d %d`, so a row with a decimal
//! value is silently skipped (e.g. `0 70.3 13000` in the F-16 file).
//! Simplification: the original fits a plane through three table points; we
//! interpolate linearly in altitude within each g-graph and linearly between
//! neighbouring graphs, which agrees at the table points.

const KT: f32 = 0.514722;
const FT: f32 = 0.3048;
/// Sentinel altitude the original appends to every graph.
const SENTINEL_ALT: f32 = 30000.0;

#[derive(Debug, Clone)]
struct Graph {
    g: i32,
    /// (altitude m, minimum speed m/s), ascending altitude, ending in the sentinel row.
    rows: Vec<(f32, f32)>,
    /// Altitude of the last real row: the ceiling for this load factor.
    ceiling: f32,
}

impl Graph {
    fn vmin(&self, alt: f32) -> f32 {
        let r = &self.rows;
        if alt <= r[0].0 {
            return r[0].1;
        }
        for w in r.windows(2) {
            let ((a0, v0), (a1, v1)) = (w[0], w[1]);
            if alt < a1 {
                return v0 + (v1 - v0) * (alt - a0) / (a1 - a0);
            }
        }
        r.last().unwrap().1
    }
}

#[derive(Debug, Clone)]
pub struct Envelope {
    graphs: Vec<Graph>,
    pub altitude_step: f32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum GLimit {
    /// Below the minimum speed at this altitude (original code 0).
    Stall,
    /// Above the envelope's altitude range (code 2).
    TooHigh,
    /// Fast enough for the commanded g (code 3).
    None,
    /// The commanded g is limited to this value (code 4).
    Max(f32),
}

impl Envelope {
    pub fn parse(data: &[u8]) -> Self {
        let text: String = data.iter().map(|&b| b as char).collect();
        let mut altitude_step = 3000.0 * FT;
        let mut graphs: Vec<Graph> = Vec::new();
        let mut in_table = false;
        for line in text.lines() {
            let line = line.trim();
            if let Some(v) = line.strip_prefix("AltitudeStep").and_then(|l| l.split('=').nth(1)) {
                altitude_step = v.trim().parse::<f32>().unwrap_or(3000.0) * FT;
            }
            if line.starts_with('[') {
                in_table = line.eq_ignore_ascii_case("[Min Velocity Table]");
                continue;
            }
            if !in_table || line.starts_with(';') {
                continue;
            }
            // `%d %d %d`: every field must be a plain integer.
            let fields: Vec<&str> = line.split_whitespace().collect();
            let [g, vel, alt] = fields[..] else { continue };
            let (Ok(g), Ok(vel), Ok(alt)) = (g.parse::<i32>(), vel.parse::<i32>(), alt.parse::<i32>()) else {
                continue;
            };
            let row = (alt as f32 * FT, vel as f32 * KT);
            match graphs.last_mut() {
                Some(last) if last.g == g => last.rows.push(row),
                _ => graphs.push(Graph { g, rows: vec![row], ceiling: 0.0 }),
            }
        }
        for gr in &mut graphs {
            gr.rows.sort_by(|a, b| a.0.total_cmp(&b.0));
            gr.ceiling = gr.rows.last().map_or(0.0, |r| r.0);
            let last_v = gr.rows.last().map_or(0.0, |r| r.1);
            gr.rows.push((SENTINEL_ALT, last_v));
        }
        graphs.sort_by_key(|g| g.g);
        Self { graphs, altitude_step }
    }

    pub fn g_range(&self) -> (f32, f32) {
        (self.graphs.first().map_or(0, |g| g.g) as f32, self.graphs.last().map_or(0, |g| g.g) as f32)
    }

    fn graph(&self, g: i32) -> &Graph {
        let (lo, hi) = self.g_range();
        let g = g.clamp(lo as i32, hi as i32);
        self.graphs.iter().find(|gr| gr.g == g).unwrap_or_else(|| {
            // Missing graph: nearest one.
            self.graphs.iter().min_by_key(|gr| (gr.g - g).abs()).unwrap()
        })
    }

    /// Interpolates a per-graph value between the integer graphs around `g`.
    fn between(&self, g: f32, f: impl Fn(&Graph) -> f32) -> f32 {
        let (lo, hi) = self.g_range();
        let g = g.clamp(lo, hi);
        let a = g.trunc();
        let b = if g >= 0.0 { a + 1.0 } else { a - 1.0 };
        let frac = (g - a).abs();
        let (va, vb) = (f(self.graph(a as i32)), f(self.graph(b as i32)));
        va + (vb - va) * frac
    }

    /// Highest altitude at which load factor `g` can be pulled (`FUN_005b22e0`).
    pub fn ceiling(&self, g: f32) -> f32 {
        self.between(g, |gr| gr.ceiling)
    }

    /// Minimum speed (m/s) for load factor `g` at `alt` (`FUN_005b1fa0` / `FUN_005b2170`).
    pub fn vmin(&self, alt: f32, g: f32) -> f32 {
        let alt = alt.clamp(0.0, (self.ceiling(g) - 1.0).max(0.0));
        self.between(g, |gr| gr.vmin(alt))
    }

    /// Load-factor limit at `alt` and speed `v` for a commanded `g` (`FUN_005b2810`).
    pub fn g_limit(&self, alt: f32, v: f32, g_cmd: f32) -> GLimit {
        let (lo, hi) = self.g_range();
        let top = self.graphs.iter().map(|g| g.ceiling).fold(0.0, f32::max);
        if alt > top + self.altitude_step {
            return GLimit::TooHigh;
        }
        let edge = if g_cmd >= 0.0 { hi } else { lo };
        // Slower than the minimum speed of the gentlest graph on this side → stall.
        let gentlest = if g_cmd >= 0.0 { 0.0f32.max(lo) } else { 0.0f32.min(hi) };
        if v < self.vmin(alt, gentlest) {
            return GLimit::Stall;
        }
        if v >= self.vmin(alt, edge) {
            if alt <= self.ceiling(g_cmd) {
                return GLimit::None;
            }
            // Above the ceiling for this g: limit falls linearly with altitude (UNCERTAIN anchor).
            let (c_edge, c0) = (self.ceiling(edge), self.ceiling(0.0));
            let t = if c0 > c_edge { ((alt - c_edge) / (c0 - c_edge)).clamp(0.0, 1.0) } else { 1.0 };
            return GLimit::Max(edge * (1.0 - t));
        }
        // Largest |g| whose minimum speed is at or below v (vmin grows with |g|).
        let (mut a, mut b) = (0.0f32, edge);
        for _ in 0..30 {
            let m = 0.5 * (a + b);
            if self.vmin(alt, m) <= v {
                a = m;
            } else {
                b = m;
            }
        }
        let lim = a;
        if lim.signum() != g_cmd.signum() && lim != 0.0 { GLimit::Max(0.0) } else { GLimit::Max(lim) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const F16: &[u8] = b"[Params]\r\nNumberOfG-Graphs=13\r\nAltitudeStep = 3000\r\n[Min Velocity Table]\r\n\
        0\t50\t0\r\n0\t70.3\t13000\r\n0\t100\t27000\r\n\
        1\t90\t0\r\n1\t100\t5000\r\n1\t110\t10000\r\n\
        9\t420\t0\r\n9\t450\t5000\r\n9\t660\t25000\r\n[End Of Envelope]\r\n";

    #[test]
    fn decimal_rows_are_skipped_like_the_original() {
        let e = Envelope::parse(F16);
        let g0 = e.graphs.iter().find(|g| g.g == 0).unwrap();
        assert_eq!(g0.rows.len(), 2 + 1); // 50@0, 100@27000, sentinel
    }

    #[test]
    fn vmin_and_limits() {
        let e = Envelope::parse(F16);
        assert!((e.vmin(0.0, 1.0) - 86.0 * KT).abs() < 0.01);
        assert!((e.vmin(5000.0 * FT, 9.0) - 442.0 * KT).abs() < 0.01);
        assert_eq!(e.g_limit(0.0, 500.0 * KT, 9.0), GLimit::None);
        match e.g_limit(0.0, 300.0 * KT, 9.0) {
            GLimit::Max(g) => assert!(g > 1.0 && g < 9.0, "{g}"),
            other => panic!("{other:?}"),
        }
        assert_eq!(e.g_limit(0.0, 20.0, 1.0), GLimit::Stall);
    }
}
