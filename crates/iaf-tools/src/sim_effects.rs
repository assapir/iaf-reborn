//! Modern IAF's effect sprites, drawn from formulas (no source image; ours) by `iaf-sim own` into the original's
//! resource layout ([`crate::sim::ART_DIR`]), named as the original game's converted sprites: the shared readers take
//! them through `Settings.effect_art()` (modern-iaf/docs/weapons.md §2). Every image tiles where its reader repeats it
//! (the flame around its cone, the trail along its segments); the alpha carries the shape.

use anyhow::{Context, Result};
use image::{Rgb, RgbImage, Rgba, RgbaImage};
use std::f32::consts::TAU;
use std::path::Path;

type Rgbf = [f32; 3];

fn lerp(a: Rgbf, b: Rgbf, t: f32) -> Rgbf {
    let t = t.clamp(0.0, 1.0);
    [0, 1, 2].map(|i| a[i] + (b[i] - a[i]) * t)
}

fn px(c: Rgbf, a: f32) -> Rgba<u8> {
    let q = |v: f32| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
    Rgba([q(c[0]), q(c[1]), q(c[2]), q(a)])
}

/// A repeatable hash of a cell to 0..1 (the chaff's foil, the splash's spray).
fn hash(x: u32, y: u32, seed: u32) -> f32 {
    let mut h = x.wrapping_mul(0x9e37_79b1) ^ y.wrapping_mul(0x85eb_ca77) ^ seed.wrapping_mul(0xc2b2_ae3d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x2c1b_3c6d);
    h ^= h >> 12;
    (h & 0xffff) as f32 / 65535.0
}

/// `afterburn.png`, the afterburner's two nested cones (afterburner.gd: u around the cone, repeated; v = 1 at the
/// nozzle, 0 at the tip; added): a blue-white core at the nozzle, yellow-white, then orange fading to the tip, with
/// three shock diamonds as brighter bands and faint streaks around.
fn afterburn() -> RgbaImage {
    let (w, h) = (256, 128);
    RgbaImage::from_fn(w, h, |x, y| {
        let u = (x as f32 + 0.5) / w as f32;
        let d = 1.0 - (y as f32 + 0.5) / h as f32; // 0 at the nozzle, 1 at the tip
        let core = [0.55, 0.66, 1.0];
        let hot = [1.0, 0.8, 0.45];
        let orange = [1.0, 0.45, 0.12];
        let tail = [0.8, 0.2, 0.05];
        let mut c = if d < 0.15 {
            lerp(core, hot, d / 0.15)
        } else if d < 0.5 {
            lerp(hot, orange, (d - 0.15) / 0.35)
        } else {
            lerp(orange, tail, (d - 0.5) / 0.5)
        };
        // Shock diamonds: bands at d = 0.12, 0.27, 0.42, fading out along the flame.
        let phase = (d - 0.12) / 0.15;
        let band = if phase > -0.5 && phase < 2.5 { (-((phase - phase.round()) / 0.2).powi(2)).exp() } else { 0.0 };
        let band = band * (1.0 - d / 0.6).max(0.0);
        c = lerp(c, [1.0, 0.92, 0.8], band * 0.9);
        let streak = 0.82
            + 0.18 * (0.5 + 0.5 * (TAU * (3.0 * u + 0.6 * d) + 1.3).sin()) * (0.5 + 0.5 * (TAU * 7.0 * u + 0.4).sin());
        let a = 0.4 * (1.0 - d).powf(1.1) * (1.0 + 2.0 * band) * streak;
        px(c, a)
    })
}

/// `missflr.png`, a flare (decoy_fx.gd, added) and a missile's motor glow (trails.gd): a small white-hot point
/// (about 1 m across in a flare's 12.8 m sprite) in a tight white-yellow glow, a faint warm halo, clear well inside
/// the rim, so released flares read as separate bright points.
fn missflr() -> RgbaImage {
    let n = 128;
    RgbaImage::from_fn(n, n, |x, y| {
        let r = ((x as f32 + 0.5 - n as f32 / 2.0).hypot(y as f32 + 0.5 - n as f32 / 2.0)) / (n as f32 / 2.0);
        let core = (-(r / 0.08).powi(2)).exp();
        let glow = 0.8 * (-(r / 0.16).powi(2)).exp();
        let halo = 0.12 * (-(r / 0.3).powi(2)).exp();
        let a = (core + glow + halo).min(1.0);
        let c = lerp(lerp([1.0, 0.65, 0.25], [1.0, 0.85, 0.4], glow / (glow + halo + 1e-6)), [1.0, 1.0, 0.97], core);
        px(c, a)
    })
}

/// `chaff.png`, the chaff pieces (decoy_fx.gd: opaque, one triangle of it per piece): aluminium foil, grey cells
/// with bright glints.
fn chaff() -> RgbImage {
    RgbImage::from_fn(64, 64, |x, y| {
        let v = 0.5 + 0.35 * hash(x / 4, y / 4, 1);
        let v = if hash(x / 2, y / 2, 2) > 0.93 { 1.0 } else { v };
        let q = (v * 255.0).round() as u8;
        Rgb([q, q, (q as f32 * 1.03).min(255.0) as u8])
    })
}

/// `trail.png`, the smoke trails (trails.gd: four frames stacked, picked by the segment's age, young at the top; u
/// along the segment, repeated; v across): white smoke, dense and narrow when young, wider and thinner with age.
fn trail() -> RgbaImage {
    let (w, h) = (128, 256);
    RgbaImage::from_fn(w, h, |x, y| {
        let f = (y / 64) as f32;
        let u = (x as f32 + 0.5) / w as f32;
        let v = ((y % 64) as f32 + 0.5) / 64.0;
        let width = 0.16 + 0.04 * f;
        let lumps = 0.85 + 0.15 * (TAU * 2.0 * u + f).sin() * (TAU * 5.0 * u + 2.0 * f).cos();
        let a = [0.8, 0.62, 0.45, 0.28][f as usize] * (-((v - 0.5) / width).powi(2)).exp() * lumps;
        let edge = (v.min(1.0 - v) / 0.08).min(1.0);
        px(lerp([0.96, 0.96, 0.95], [0.86, 0.86, 0.86], f / 3.0), a * edge)
    })
}

/// `w_splash.png`, a hit's water splash (damage_effects.gd: two crossed quads standing on the burst, the bottom edge
/// on the water): a spray column wide at the water, narrowing upward, streaked, thinning at the top.
fn w_splash() -> RgbaImage {
    let n = 64;
    RgbaImage::from_fn(n, n, |x, y| {
        let s = (x as f32 + 0.5) / n as f32 * 2.0 - 1.0;
        let up = 1.0 - (y as f32 + 0.5) / n as f32;
        let width = 0.12 + 0.5 * (1.0 - up);
        let streak = 0.6 + 0.4 * hash(x, 0, 3);
        let a = (-(s / width).powi(2)).exp() * (1.0 - up).powf(0.6) * streak * (s.abs() < 0.97) as u8 as f32;
        px([1.0, 1.0, 1.0], a)
    })
}

/// `w_circle.png`, a hit's ring on the water (damage_effects.gd: one level quad, growing): a foam ring with a
/// fainter inner one, clear at the centre and the rim.
fn w_circle() -> RgbaImage {
    let n = 64;
    RgbaImage::from_fn(n, n, |x, y| {
        let r = ((x as f32 + 0.5 - n as f32 / 2.0).hypot(y as f32 + 0.5 - n as f32 / 2.0)) / (n as f32 / 2.0);
        let a = (-((r - 0.82) / 0.07).powi(2)).exp() + 0.35 * (-((r - 0.58) / 0.1).powi(2)).exp();
        px([1.0, 1.0, 1.0], a.min(1.0) * (r < 1.0) as u8 as f32)
    })
}

/// Draws every sprite into `<assets>/ART_DIR`.
pub fn effects_art(assets: &Path) -> Result<()> {
    let dir = assets.join(crate::sim::ART_DIR);
    std::fs::create_dir_all(&dir).with_context(|| dir.display().to_string())?;
    let rgba = [
        ("afterburn.png", afterburn()),
        ("missflr.png", missflr()),
        ("trail.png", trail()),
        ("w_splash.png", w_splash()),
        ("w_circle.png", w_circle()),
    ];
    for (name, img) in rgba {
        img.save(dir.join(name)).with_context(|| dir.join(name).display().to_string())?;
    }
    chaff().save(dir.join("chaff.png")).with_context(|| dir.join("chaff.png").display().to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sprites_have_their_shape() {
        // The flame: opaque-ish at the nozzle (bottom row), clear at the tip; blue-white at the nozzle, orange later;
        // the same at both sides of the seam (it repeats around the cone).
        let f = afterburn();
        let (nozzle, tip) = (f.get_pixel(40, 127), f.get_pixel(40, 0));
        assert!(nozzle[3] > 70 && tip[3] < 10, "{nozzle:?} {tip:?}");
        assert!(nozzle[2] >= nozzle[0] && f.get_pixel(40, 50)[2] < f.get_pixel(40, 50)[0]);
        assert!((f.get_pixel(0, 100)[3] as i32 - f.get_pixel(255, 100)[3] as i32).abs() < 6);
        // The flare: white-hot centre, clear corners.
        let m = missflr();
        assert!(m.get_pixel(64, 64)[3] == 255 && m.get_pixel(64, 64)[2] > 230 && m.get_pixel(0, 0)[3] == 0);
        // The trail: dense in its young frame's middle, clear at every frame's edges, thinner with age.
        let t = trail();
        assert!(t.get_pixel(10, 32)[3] > t.get_pixel(10, 224)[3] && t.get_pixel(10, 224)[3] > 40);
        assert!((0..4).all(|k| t.get_pixel(10, k * 64)[3] == 0 && t.get_pixel(10, k * 64 + 63)[3] == 0));
        // The water: the splash stands on its bottom edge, the ring is clear at its centre.
        assert!(w_splash().get_pixel(32, 63)[3] > 150 && w_splash().get_pixel(32, 0)[3] < 40);
        let r = w_circle();
        assert!(r.get_pixel(32, 32)[3] < 10 && r.get_pixel(32 + 26, 32)[3] > 200);
    }
}
