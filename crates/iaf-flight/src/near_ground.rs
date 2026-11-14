//! What the air does near the ground, for both flight models: ground effect on the wing and the light turbulence of
//! the mission's wind. Reborn's original model takes them with Better physics `ground_effect` / `wind`
//! (docs/flight-model.md), Modern IAF's 6-DoF always (modern-iaf/docs/flight-model.md §9.12).

use crate::Vec3;

/// McCormick's ground-effect factor on the induced drag, `φ = (16h/b)² / (1 + (16h/b)²)` (h = the wing's height above
/// the terrain, b = span, m): 0.5 at h ≈ b/16, 0.8 at b/8, 0.94 at b/4; 1 from 4 spans up, at least 0.05.
pub fn induced_factor(h: f32, span: f32) -> f32 {
    let r = 16.0 * h.max(0.0) / span.max(1.0);
    if !r.is_finite() || r > 64.0 {
        return 1.0;
    }
    (r * r / (1.0 + r * r)).max(0.05)
}

/// Ground effect on the lift at the same α: the wing's effective aspect ratio near the ground is `A/φ`
/// ([`induced_factor`]); Helmbold's lift-curve slope `a(A) = 2πA / (2 + √(A² + 4))` gives `a(A/φ) / a(A)`.
/// F-16 (A ≈ 3.2): ×1.06 at 1.7 m, ×1.02 at 3.4 m, 1.002 at one span.
pub fn lift_factor(h: f32, span: f32, area: f32) -> f32 {
    let slope = |ar: f32| ar / (2.0 + (ar * ar + 4.0).sqrt());
    let ar = span * span / area.max(1.0);
    slope(ar / induced_factor(h, span)) / slope(ar)
}

/// The gusts added to the mission's wind `wind` (ENU, m/s) at time `t` (s), `height` m above the terrain: rms 0.1 ×
/// the wind speed vertically (half that across) below 300 m, falling to 30 % of that at 1500 m and above; none in
/// calm air.
pub fn gust(wind: Vec3, t: f64, height: f32) -> Vec3 {
    let w = wind.length() as f32;
    if w == 0.0 {
        return Vec3::ZERO;
    }
    let low = 1.0 - 0.7 * ((height - 300.0) / 1200.0).clamp(0.0, 1.0);
    // ponytail: three sines in time per axis (rms 1), not a Dryden spectrum in space; replace if the gusts must
    // scale with the airspeed.
    let tt = t * std::f64::consts::TAU;
    let n = |ph: f64| {
        ((0.17 * tt + ph).sin() + 0.7 * (0.43 * tt + 2.0 * ph).sin() + 0.4 * (1.1 * tt + 3.0 * ph).sin()) / 0.908
    };
    let sigma = (0.1 * w * low) as f64;
    Vec3::new(0.5 * sigma * n(0.4), 0.5 * sigma * n(2.1), sigma * n(1.3))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ground_effect_figures() {
        let (b, s) = (9.45, 27.87); // the F-16's span and wing area, m, m²
        assert!((induced_factor(b / 16.0, b) - 0.5).abs() < 1e-3 && induced_factor(5.0 * b, b) == 1.0);
        assert!((lift_factor(1.7, b, s) - 1.06).abs() < 0.01, "{}", lift_factor(1.7, b, s));
        assert!(lift_factor(b, b, s) < 1.003);
    }

    #[test]
    fn gusts_by_height_and_calm() {
        let w = Vec3::new(10.0, 0.0, 0.0);
        let rms = |h: f32| {
            let n = 20_000;
            ((0..n).map(|i| gust(w, i as f64 * 0.05, h).z.powi(2)).sum::<f64>() / n as f64).sqrt()
        };
        assert!((rms(100.0) - 1.0).abs() < 0.1, "{}", rms(100.0));
        assert!((rms(2000.0) - 0.3).abs() < 0.05, "{}", rms(2000.0));
        assert_eq!(gust(Vec3::ZERO, 3.0, 50.0), Vec3::ZERO);
    }
}
