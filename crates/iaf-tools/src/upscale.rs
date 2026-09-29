//! Texture upscaling.
//!
//! Default: 4× Lanczos3 resampling with premultiplied alpha — faithful to the
//! original art (no invented detail; lettering stays correct).
//! Experimental: AI upscaling via the external `realesrgan-ncnn-vulkan` tool
//! (AUR `realesrgan-ncnn-vulkan`). Rejected as default: it redraws text and
//! gives a painted look.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU32, Ordering};

use anyhow::{Context, Result, bail};
use image::RgbaImage;

const BINARY: &str = "realesrgan-ncnn-vulkan";
/// Crisp results on painted textures with decals and lettering (aircraft, vehicles).
pub const MODEL_PAINTED: &str = "realesrgan-x4plus-anime";
/// Better for photographic imagery (terrain).
pub const MODEL_PHOTO: &str = "realesrgan-x4plus";

/// Where packages put the model files; `IAF_UPSCALER_MODELS` overrides.
const MODEL_DIRS: &[&str] = &[
    "/usr/share/realesrgan-ncnn-vulkan/models",
    "/usr/share/realesrgan-ncnn-vulkan",
    "/usr/local/share/realesrgan-ncnn-vulkan/models",
    "/opt/realesrgan-ncnn-vulkan/models",
    "/opt/homebrew/share/realesrgan-ncnn-vulkan/models",
];

pub enum Upscaler {
    Lanczos,
    Ai { binary: PathBuf, models: PathBuf, model: String },
}

pub const FACTOR: u32 = 4;

/// 4× Lanczos3 in premultiplied alpha, so transparent (colour-keyed) pixels
/// don't bleed their colour into the edges.
fn lanczos(img: &RgbaImage) -> RgbaImage {
    use image::{Rgba32FImage, imageops};
    let pre = Rgba32FImage::from_fn(img.width(), img.height(), |x, y| {
        let p = img.get_pixel(x, y).0;
        let a = p[3] as f32 / 255.0;
        image::Rgba([p[0] as f32 / 255.0 * a, p[1] as f32 / 255.0 * a, p[2] as f32 / 255.0 * a, a])
    });
    let big = imageops::resize(&pre, img.width() * FACTOR, img.height() * FACTOR, imageops::FilterType::Lanczos3);
    RgbaImage::from_fn(big.width(), big.height(), |x, y| {
        let [r, g, b, a] = big.get_pixel(x, y).0;
        let a = a.clamp(0.0, 1.0);
        let un = |c: f32| if a > 1e-4 { (c / a).clamp(0.0, 1.0) } else { 0.0 };
        image::Rgba([(un(r) * 255.0).round() as u8, (un(g) * 255.0).round() as u8, (un(b) * 255.0).round() as u8, (a * 255.0).round() as u8])
    })
}

fn find_on_path(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| std::env::split_paths(&paths).map(|d| d.join(name)).find(|p| p.is_file()))
}

impl Upscaler {
    /// The external AI upscaler (experimental).
    pub fn find_ai(model: &str) -> Result<Self> {
        let binary = find_on_path(BINARY).with_context(|| {
            format!("{BINARY} not found on PATH (Arch: `paru -S realesrgan-ncnn-vulkan`)")
        })?;
        let override_dir = std::env::var_os("IAF_UPSCALER_MODELS").map(PathBuf::from);
        let candidates = override_dir.into_iter().chain(MODEL_DIRS.iter().map(PathBuf::from));
        let has_model = |d: &Path| d.join(format!("{model}.param")).is_file();
        let models = candidates.into_iter().find(|d| has_model(d)).with_context(|| {
            format!("model {model}.param not found; set IAF_UPSCALER_MODELS to the folder containing it")
        })?;
        Ok(Self::Ai { binary, models, model: model.to_string() })
    }

    /// Returns a 4× image. `key` pixels (the original colour key) become
    /// transparent again in the result.
    pub fn upscale(&self, img: &RgbaImage, key: Option<[u8; 3]>) -> Result<RgbaImage> {
        let Self::Ai { binary, models, model } = self else {
            return Ok(lanczos(img));
        };
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let id = format!("iaf-up-{}-{}", std::process::id(), COUNTER.fetch_add(1, Ordering::Relaxed));
        let tmp = std::env::temp_dir();
        let (input, output) = (tmp.join(format!("{id}-in.png")), tmp.join(format!("{id}-out.png")));
        // Upscale the colours only; transparency is rebuilt from the colour key afterwards.
        image::DynamicImage::ImageRgba8(img.clone()).to_rgb8().save(&input)?;
        let status = Command::new(binary)
            .arg("-i")
            .arg(&input)
            .arg("-o")
            .arg(&output)
            .arg("-n")
            .arg(model)
            .arg("-m")
            .arg(models)
            .output()
            .context("running realesrgan-ncnn-vulkan")?;
        let _ = std::fs::remove_file(&input);
        if !status.status.success() || !output.is_file() {
            bail!("upscaler failed: {}", String::from_utf8_lossy(&status.stderr).lines().last().unwrap_or(""));
        }
        let mut up = image::open(&output)?.to_rgba8();
        let _ = std::fs::remove_file(&output);

        let (w, h) = img.dimensions();
        for (x, y, p) in up.enumerate_pixels_mut() {
            // Alpha from the original (nearest), then also clear pixels that ended up near the key colour.
            let src = img.get_pixel((x * w / (w * 4)).min(w - 1), (y * h / (h * 4)).min(h - 1));
            p[3] = src[3];
            if let Some([r, g, b]) = key {
                let d = (p[0] as i32 - r as i32).abs() + (p[1] as i32 - g as i32).abs() + (p[2] as i32 - b as i32).abs();
                if d < 90 {
                    p[3] = 0;
                }
            }
        }
        Ok(up)
    }
}
