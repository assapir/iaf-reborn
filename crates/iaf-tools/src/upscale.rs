//! Texture upscaling: 4× Lanczos3 resampling with premultiplied alpha — faithful to the
//! original art (no invented detail; lettering stays correct).

use image::RgbaImage;

pub const FACTOR: u32 = 4;

/// 4× Lanczos3 in premultiplied alpha, so transparent (colour-keyed) pixels
/// don't bleed their colour into the edges.
pub fn upscale(img: &RgbaImage) -> RgbaImage {
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
