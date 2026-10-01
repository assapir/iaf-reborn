//! Georeference of the original world frame (docs/georef.md): a smooth warp between map.ptt terrain
//! units (`tx` east, `ty` south; engine metres `X = tx·1.2411389 − 166850`, `Y = 1043780 − ty·1.2411389`)
//! and real WGS84 longitude / latitude.
//!
//! The 1998 theatre is not a map projection of the real world (about 1.5× enlarged, not uniformly),
//! so the warp is a **thin-plate spline** fitted to control points measured on the original data
//! (`data/georef_points.json`, coordinates only): terrain → (lon, lat) is the spline, (lon, lat) →
//! terrain is its exact inverse by Newton iteration. Modern imagery is warped *into* the game frame
//! with it; the game frame itself never moves.

use anyhow::{Context, Result, bail};

const DATA: &str = include_str!("../data/georef_points.json");

/// Terrain units → metres in the engine frame (map.ptt `PlaneScalePR`).
pub const UNITS_TO_METRES: f64 = 1.2411389;
/// Spline inputs are terrain units / SCALE (one level-6 node = 1) for a well-conditioned system.
const SCALE: f64 = 65536.0;

/// One control point: the same ground feature in the original frame and in the real world.
#[derive(Clone, Debug, PartialEq)]
pub struct Point {
    pub id: String,
    /// "auto" (image correlation, docs/georef.md §2) or "airbase" (hand-measured runway).
    pub kind: String,
    /// Terrain units (x east, y south).
    pub game: [f64; 2],
    /// Longitude, latitude (degrees, WGS84).
    pub geo: [f64; 2],
}

/// The fitted warp.
#[derive(Clone, Debug)]
pub struct Georef {
    centres: Vec<[f64; 2]>,
    /// Kernel weights per centre, (lon, lat).
    w: Vec<[f64; 2]>,
    /// Affine part per output: c0 + c1·x + c2·y.
    a: [[f64; 3]; 2],
    pub lambda: f64,
    pub points: Vec<Point>,
}

fn kernel(r2: f64) -> f64 {
    if r2 <= 0.0 { 0.0 } else { 0.5 * r2 * r2.ln() } // r² ln r
}

impl Georef {
    /// The committed control points (`data/georef_points.json`) and their smoothing.
    pub fn load() -> Result<Self> {
        let (points, lambda) = parse(DATA)?;
        Self::fit(points, lambda)
    }

    /// Thin-plate spline through `points` (terrain → lon/lat) with smoothing `lambda` (0 =
    /// interpolating; larger values trade residuals for smoothness, docs/georef.md §3).
    pub fn fit(points: Vec<Point>, lambda: f64) -> Result<Self> {
        let n = points.len();
        if n < 3 {
            bail!("georef: need at least 3 control points, have {n}");
        }
        let c: Vec<[f64; 2]> = points.iter().map(|p| [p.game[0] / SCALE, p.game[1] / SCALE]).collect();
        let m = n + 3;
        // [K + λI  P; Pᵀ 0] [w; a] = [v; 0], two right-hand sides (lon, lat).
        let mut a = vec![0.0; m * m];
        let mut b = vec![[0.0f64; 2]; m];
        for i in 0..n {
            for j in 0..n {
                let (dx, dy) = (c[i][0] - c[j][0], c[i][1] - c[j][1]);
                a[i * m + j] = kernel(dx * dx + dy * dy) + if i == j { lambda } else { 0.0 };
            }
            for (k, v) in [1.0, c[i][0], c[i][1]].into_iter().enumerate() {
                a[i * m + n + k] = v;
                a[(n + k) * m + i] = v;
            }
            b[i] = points[i].geo;
        }
        solve(&mut a, &mut b, m).context("georef: singular system (duplicate or collinear points?)")?;
        let w = b[..n].to_vec();
        let aff = [[b[n][0], b[n + 1][0], b[n + 2][0]], [b[n][1], b[n + 1][1], b[n + 2][1]]];
        Ok(Self { centres: c, w, a: aff, lambda, points })
    }

    /// Terrain units → (lon, lat).
    pub fn to_geo(&self, tx: f64, ty: f64) -> [f64; 2] {
        let (x, y) = (tx / SCALE, ty / SCALE);
        let mut out = [
            self.a[0][0] + self.a[0][1] * x + self.a[0][2] * y,
            self.a[1][0] + self.a[1][1] * x + self.a[1][2] * y,
        ];
        for (c, w) in self.centres.iter().zip(&self.w) {
            let (dx, dy) = (x - c[0], y - c[1]);
            let k = kernel(dx * dx + dy * dy);
            out[0] += w[0] * k;
            out[1] += w[1] * k;
        }
        out
    }

    /// Engine metres (X east, Y north) → (lon, lat).
    pub fn engine_to_geo(&self, x: f64, y: f64) -> [f64; 2] {
        self.to_geo((x + 166850.0) / UNITS_TO_METRES, (1043780.0 - y) / UNITS_TO_METRES)
    }

    /// (lon, lat) → engine metres (X east, Y north): the inverse of `engine_to_geo`.
    pub fn geo_to_engine(&self, lon: f64, lat: f64) -> [f64; 2] {
        let [tx, ty] = self.to_game(lon, lat);
        [tx * UNITS_TO_METRES - 166850.0, 1043780.0 - ty * UNITS_TO_METRES]
    }

    /// (lon, lat) → terrain units: the inverse of `to_geo` (Newton iteration from the affine
    /// part's inverse; converges to well below a millimetre in a few steps).
    pub fn to_game(&self, lon: f64, lat: f64) -> [f64; 2] {
        // Start: invert the affine part.
        let [[a0, a1, a2], [b0, b1, b2]] = self.a;
        let det = a1 * b2 - a2 * b1;
        let (u, v) = (lon - a0, lat - b0);
        let mut p = [(u * b2 - a2 * v) / det * SCALE, (a1 * v - b1 * u) / det * SCALE];
        let h = 1.0; // one terrain unit for the numerical Jacobian
        for _ in 0..20 {
            let g = self.to_geo(p[0], p[1]);
            let (ex, ey) = (lon - g[0], lat - g[1]);
            let gx = self.to_geo(p[0] + h, p[1]);
            let gy = self.to_geo(p[0], p[1] + h);
            let (j00, j10) = ((gx[0] - g[0]) / h, (gx[1] - g[1]) / h);
            let (j01, j11) = ((gy[0] - g[0]) / h, (gy[1] - g[1]) / h);
            let d = j00 * j11 - j01 * j10;
            let step = [(ex * j11 - j01 * ey) / d, (j00 * ey - j10 * ex) / d];
            p = [p[0] + step[0], p[1] + step[1]];
            if step[0].abs() + step[1].abs() < 1e-4 {
                break;
            }
        }
        p
    }

    /// Per point: how far (metres in the game frame) the warp puts the point's real position from
    /// where the original shows it, i.e. |to_game(geo) − game| · 1.2411389.
    pub fn residuals_m(&self) -> Vec<f64> {
        self.points
            .iter()
            .map(|p| {
                let g = self.to_game(p.geo[0], p.geo[1]);
                (g[0] - p.game[0]).hypot(g[1] - p.game[1]) * UNITS_TO_METRES
            })
            .collect()
    }
}

/// `{"lambda": λ, "points": [{"id", "kind", "tx", "ty", "lon", "lat"}, …]}`.
pub fn parse(json: &str) -> Result<(Vec<Point>, f64)> {
    let v: serde_json::Value = serde_json::from_str(json)?;
    let lambda = v["lambda"].as_f64().unwrap_or(0.0);
    let mut out = Vec::new();
    for p in v["points"].as_array().context("georef: no 'points' array")? {
        let f = |k: &str| p[k].as_f64().with_context(|| format!("georef point: missing '{k}'"));
        out.push(Point {
            id: p["id"].as_str().unwrap_or("").to_string(),
            kind: p["kind"].as_str().unwrap_or("auto").to_string(),
            game: [f("tx")?, f("ty")?],
            geo: [f("lon")?, f("lat")?],
        });
    }
    Ok((out, lambda))
}

/// Gaussian elimination with partial pivoting, in place: `a` (m×m, row-major) · x = `b`; x in `b`.
fn solve(a: &mut [f64], b: &mut [[f64; 2]], m: usize) -> Option<()> {
    for k in 0..m {
        let p = (k..m).max_by(|&i, &j| a[i * m + k].abs().total_cmp(&a[j * m + k].abs()))?;
        if a[p * m + k].abs() < 1e-14 {
            return None;
        }
        if p != k {
            for j in 0..m {
                a.swap(k * m + j, p * m + j);
            }
            b.swap(k, p);
        }
        let piv = a[k * m + k];
        let (top, rest) = a.split_at_mut((k + 1) * m);
        let row_k = &top[k * m..];
        for i in 0..m - k - 1 {
            let row = &mut rest[i * m..(i + 1) * m];
            let f = row[k] / piv;
            if f != 0.0 {
                for j in k..m {
                    row[j] -= f * row_k[j];
                }
                let bk = b[k];
                b[k + 1 + i][0] -= f * bk[0];
                b[k + 1 + i][1] -= f * bk[1];
            }
        }
    }
    for k in (0..m).rev() {
        let mut s = b[k];
        for j in k + 1..m {
            s[0] -= a[k * m + j] * b[j][0];
            s[1] -= a[k * m + j] * b[j][1];
        }
        b[k] = [s[0] / a[k * m + k], s[1] / a[k * m + k]];
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn synthetic() -> Vec<Point> {
        // A smooth, non-affine "real world": lon/lat from terrain units.
        let f = |x: f64, y: f64| {
            [29.77 + x * 1.29e-5 + 2e-12 * x * y, 36.62 - y * 1.13e-5 + 0.02 * (x / 3e5).sin()]
        };
        let mut v = Vec::new();
        for j in 0..9 {
            for i in 0..7 {
                let (x, y) = (i as f64 * 1e5 + 3e3 * j as f64, j as f64 * 1e5);
                v.push(Point { id: format!("p{i}_{j}"), kind: "auto".into(), game: [x, y], geo: f(x, y) });
            }
        }
        v
    }

    #[test]
    fn interpolates_and_round_trips() {
        let g = Georef::fit(synthetic(), 0.0).unwrap();
        for r in g.residuals_m() {
            assert!(r < 0.01, "interpolating spline residual {r} m");
        }
        for &(x, y) in &[(1234.0, 5678.0), (333333.0, 444444.0), (650000.0, 850000.0), (-20000.0, 900000.0)] {
            let [lon, lat] = g.to_geo(x, y);
            let [bx, by] = g.to_game(lon, lat);
            assert!((bx - x).hypot(by - y) * UNITS_TO_METRES < 0.01, "round trip at ({x}, {y}): ({bx}, {by})");
        }
    }

    #[test]
    fn committed_points_fit_and_round_trip() {
        let g = Georef::load().unwrap();
        assert!(g.points.len() >= 100, "{} control points", g.points.len());
        let [x, y] = g.geo_to_engine(36.226, 33.479); // Mezzeh (§4) to engine metres and back
        assert!((g.engine_to_geo(x, y)[0] - 36.226).hypot(g.engine_to_geo(x, y)[1] - 33.479) < 1e-7, "engine round trip");
        // Well spread: every region of the theatre has points (docs/georef.md §4).
        for (name, lon0, lat0, lon1, lat1) in [
            ("Israel", 34.3, 29.5, 35.9, 33.3),
            ("Sinai", 32.6, 28.5, 34.5, 31.2),
            ("Nile delta / Suez", 30.0, 29.8, 32.6, 31.6),
            ("Jordan", 35.6, 29.3, 38.0, 32.5),
            ("Syria", 35.9, 32.4, 38.2, 35.5),
            ("Lebanon", 35.1, 33.1, 36.6, 34.7),
            ("Cyprus", 32.2, 34.5, 34.6, 35.7),
        ] {
            let n = g.points.iter().filter(|p| p.geo[0] > lon0 && p.geo[0] < lon1 && p.geo[1] > lat0 && p.geo[1] < lat1).count();
            // Cyprus is painted at ~1 km in the original: only the level-8 pass finds it.
            assert!(n >= if name == "Cyprus" { 3 } else { 10 }, "{name}: only {n} control points");
        }
        let mut r = g.residuals_m();
        r.sort_by(f64::total_cmp);
        let rms = (r.iter().map(|x| x * x).sum::<f64>() / r.len() as f64).sqrt();
        let p95 = r[r.len() * 95 / 100];
        // Bounds from docs/georef.md §5 (a level-6 pixel is 79 m).
        assert!(rms < 80.0, "rms residual {rms:.0} m");
        assert!(p95 < 150.0, "95th percentile residual {p95:.0} m");
        for p in &g.points {
            let [x, y] = g.to_game(p.geo[0], p.geo[1]);
            let [lon, lat] = g.to_geo(x, y);
            assert!((lon - p.geo[0]).abs() < 1e-8 && (lat - p.geo[1]).abs() < 1e-8, "{}", p.id);
        }
        // Theatre corners: inside the expected lat/lon box (docs/imagery-research.md §1).
        let [lon, lat] = g.to_geo(0.0, 0.0);
        assert!((lon - 29.77).abs() < 0.3 && (lat - 36.62).abs() < 0.3, "NW corner {lon} {lat}");
        let [lon, lat] = g.to_geo(655360.0, 851968.0);
        assert!((lon - 38.26).abs() < 0.3 && (lat - 27.09).abs() < 0.3, "SE corner {lon} {lat}");
    }
}
