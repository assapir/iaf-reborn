//! WGS84 (lon, lat) → Israeli Transverse Mercator grid (EPSG:2039, "Israel 1993 / Israeli TM Grid"), the grid of
//! the Survey of Israel orthophoto sheets (docs/imagery.md §8). The datum shift WGS84 → Israel 1993 is not
//! negligible (≈ 78 m around Tel Aviv): the 7-parameter Helmert "Israel 1993 to WGS 84 (2)" (EPSG, 0.5 m, the
//! operation PROJ / GDAL pick for EPSG:2039) inverted, then the transverse Mercator on GRS80 (Krüger series).
//! Matches `gdaltransform -s_srs EPSG:4326 -t_srs EPSG:2039` to a few mm (test below).

const GRS80_A: f64 = 6378137.0;
const GRS80_F: f64 = 1.0 / 298.257222101;
const WGS84_F: f64 = 1.0 / 298.257223563;
const LAT0: f64 = 31.0 + 44.0 / 60.0 + 3.817 / 3600.0;
const LON0: f64 = 35.0 + 12.0 / 60.0 + 16.261 / 3600.0;
const K0: f64 = 1.0000067;
const FE: f64 = 219529.584;
const FN: f64 = 626907.390;
/// Israel 1993 → WGS 84 (coordinate frame rotation): metres, arc-seconds, ppm.
const HELMERT: [f64; 7] = [23.772, 17.49, 17.859, 0.3132, 1.85274, -1.67299, -5.4262];

fn to_ecef(lon: f64, lat: f64, f: f64) -> [f64; 3] {
    let e2 = f * (2.0 - f);
    let (sp, cp) = lat.to_radians().sin_cos();
    let (sl, cl) = lon.to_radians().sin_cos();
    let n = GRS80_A / (1.0 - e2 * sp * sp).sqrt();
    [n * cp * cl, n * cp * sl, n * (1.0 - e2) * sp]
}

/// ECEF → (lon, lat) radians (Bowring, then two refinements; the height is ~0 and ignored).
fn from_ecef(p: [f64; 3], f: f64) -> (f64, f64) {
    let e2 = f * (2.0 - f);
    let r = p[0].hypot(p[1]);
    let mut lat = p[2].atan2(r * (1.0 - e2));
    for _ in 0..4 {
        let s = lat.sin();
        let n = GRS80_A / (1.0 - e2 * s * s).sqrt();
        lat = (p[2] + e2 * n * s).atan2(r);
    }
    (p[1].atan2(p[0]), lat)
}

/// Transverse Mercator on GRS80 (Krüger n-series to n³): (lon, lat) radians → (easting, northing) metres.
fn tm(lon: f64, lat: f64) -> [f64; 2] {
    let n = GRS80_F / (2.0 - GRS80_F);
    let a = GRS80_A / (1.0 + n) * (1.0 + n * n / 4.0 + n.powi(4) / 64.0);
    let al = [n / 2.0 - 2.0 * n * n / 3.0 + 5.0 * n.powi(3) / 16.0, 13.0 * n * n / 48.0 - 3.0 * n.powi(3) / 5.0, 61.0 * n.powi(3) / 240.0];
    let c = 2.0 * n.sqrt() / (1.0 + n);
    let xi_eta = |lon: f64, lat: f64| {
        let s = lat.sin();
        let t = (s.atanh() - c * (c * s).atanh()).sinh();
        let dl = lon - LON0.to_radians();
        let xi1 = t.atan2(dl.cos());
        let eta1 = (dl.sin() / (1.0 + t * t).sqrt()).atanh();
        let (mut xi, mut eta) = (xi1, eta1);
        for (j, a) in al.iter().enumerate() {
            let k = 2.0 * (j + 1) as f64;
            xi += a * (k * xi1).sin() * (k * eta1).cosh();
            eta += a * (k * xi1).cos() * (k * eta1).sinh();
        }
        (xi, eta)
    };
    let (xi0, _) = xi_eta(LON0.to_radians(), LAT0.to_radians());
    let (xi, eta) = xi_eta(lon, lat);
    [FE + K0 * a * eta, FN + K0 * a * (xi - xi0)]
}

/// WGS84 (lon, lat) degrees → Israeli TM Grid (easting, northing) metres.
pub fn from_wgs84(lon: f64, lat: f64) -> [f64; 2] {
    let p = to_ecef(lon, lat, WGS84_F);
    // Inverse Helmert: X_israel = R⁻¹ (X_wgs − T) / (1 + s), R⁻¹ ≈ Rᵀ (rotations of a few arc-seconds).
    let [tx, ty, tz, rx, ry, rz, s] = HELMERT;
    let sec = std::f64::consts::PI / 180.0 / 3600.0;
    let (rx, ry, rz) = (rx * sec, ry * sec, rz * sec);
    let d = [p[0] - tx, p[1] - ty, p[2] - tz].map(|v| v / (1.0 + s * 1e-6));
    // Coordinate frame: X' = R X with R = [[1, rz, −ry], [−rz, 1, rx], [ry, −rx, 1]]; X = Rᵀ X'.
    let q = [d[0] - rz * d[1] + ry * d[2], rz * d[0] + d[1] - rx * d[2], -ry * d[0] + rx * d[1] + d[2]];
    let (lon, lat) = from_ecef(q, GRS80_F);
    tm(lon, lat)
}

#[cfg(test)]
mod tests {
    #[test]
    fn matches_proj() {
        // `gdaltransform -s_srs EPSG:4326 -t_srs EPSG:2039` (GDAL 3.13, PROJ's default operation).
        for (lon, lat, e, n) in [
            (34.82, 31.96, 183112.976276673, 651947.424207911),
            (35.2, 31.77, 219035.655804613, 630814.607652746),
            (34.95, 29.55, 194796.112420859, 384721.165324509),
            (35.6, 33.25, 256318.512350731, 795012.149433868),
            (34.3, 31.3, 133347.294375563, 579054.026471915),
        ] {
            let p = super::from_wgs84(lon, lat);
            assert!((p[0] - e).abs() < 0.02 && (p[1] - n).abs() < 0.02, "{lon} {lat}: {p:?} vs {e} {n}");
        }
    }
}
