//! Model detail (Graphics → MORE → Model detail: ambientCG; docs/rendering.md "Model detail"): a small fixed set of
//! CC0 PBR materials from ambientCG (<https://ambientcg.com>), downloaded at setup into
//! `assets/thirdparty/ambientcg/<id>/` and packed into one texture per material for the game's detail shader.
//!
//! The pack (`<id>_detail.png`, RGBA, laid out for DXT5 / BC3, which the game compresses it to): R roughness,
//! G normal Y, B the colour map's brightness about its mean (0.5 = mean, ±2 σ to 0 / 1: stains, chips, scratches),
//! A normal X (the alpha block keeps the most precision). Normals are the OpenGL ones (+Y up).

use std::path::Path;
use std::process::Command;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use image::{GrayImage, RgbaImage, imageops::FilterType};

use crate::progress::{Progress, check};

/// One ambientCG material: its pinned asset id, the detail class the game gives it, the pack's size (px).
pub struct Material {
    pub id: &'static str,
    pub class: &'static str,
    pub size: u32,
}

/// The model materials (each CC0, ambientCG's licence page: <https://docs.ambientcg.com/license/>).
pub const MODEL_MATERIALS: &[Material] = &[
    Material { id: "PaintedMetal002", class: "painted", size: 1024 },
    Material { id: "Metal016", class: "worn", size: 1024 },
    Material { id: "Concrete029", class: "concrete", size: 1024 },
    Material { id: "Rubber004", class: "rubber", size: 512 },
];

/// The download each material comes from (ambientCG's 1K JPG set).
pub const RESOLUTION: &str = "1K-JPG";

/// The manifest the game reads (under the ambientcg folder): `{class: "<id>/<id>_detail.png"}`.
pub const MANIFEST: &str = "model_detail.json";

fn url(id: &str) -> String {
    format!("https://ambientcg.com/get?file={id}_{RESOLUTION}.zip")
}

/// Downloads material `id` (curl) and unpacks its maps into `dir/<id>/`; a folder already holding them is kept.
pub fn fetch(id: &str, dir: &Path, pr: &dyn Progress) -> Result<()> {
    let out = dir.join(id);
    if map_path(&out, id, "NormalGL").exists() {
        return Ok(());
    }
    std::fs::create_dir_all(&out)?;
    let zip = dir.join(format!("{id}_{RESOLUTION}.zip"));
    pr.log(&format!("downloading {}", url(id)));
    let st = Command::new("curl")
        .args(["-sfL", "-m", "300", "-o"])
        .arg(&zip)
        .arg(url(id))
        .status()
        .context("running curl")?;
    if !st.success() {
        let _ = std::fs::remove_file(&zip);
        bail!("downloading {} failed ({st})", url(id));
    }
    let r = (|| -> Result<()> {
        let mut a = zip::ZipArchive::new(std::fs::File::open(&zip)?)?;
        for i in 0..a.len() {
            let mut f = a.by_index(i)?;
            let name = f.enclosed_name().context("bad name in the zip")?;
            let Some(file) = name.file_name() else { continue };
            if name.extension().is_some_and(|e| e.eq_ignore_ascii_case("jpg")) {
                std::io::copy(&mut f, &mut std::fs::File::create(out.join(file))?)?;
            }
        }
        Ok(())
    })();
    let _ = std::fs::remove_file(&zip);
    r
}

fn map_path(dir: &Path, id: &str, map: &str) -> std::path::PathBuf {
    dir.join(format!("{id}_{RESOLUTION}_{map}.jpg"))
}

/// The pack of material `m` from its maps in `dir/<id>/`, written beside them as `<id>_detail.png`.
pub fn pack(m: &Material, dir: &Path) -> Result<()> {
    let d = dir.join(m.id);
    let open = |map: &str| -> Result<image::DynamicImage> {
        let p = map_path(&d, m.id, map);
        let img = image::open(&p).with_context(|| format!("{}", p.display()))?;
        Ok(img.resize_exact(m.size, m.size, FilterType::Triangle))
    };
    let normal = open("NormalGL")?.to_rgb8();
    let rough = open("Roughness")?.to_luma8();
    let colour = open("Color")?.to_luma8();
    let detail = brightness_detail(&colour);
    let mut out = RgbaImage::new(m.size, m.size);
    for (x, y, px) in out.enumerate_pixels_mut() {
        let n = normal.get_pixel(x, y);
        *px = image::Rgba([rough.get_pixel(x, y)[0], n[1], detail.get_pixel(x, y)[0], n[0]]);
    }
    out.save(d.join(format!("{}_detail.png", m.id)))?;
    Ok(())
}

/// The brightness about its mean: 0.5 + (v − mean) / (4 σ), clamped (±2 σ spans 0..1).
pub fn brightness_detail(g: &GrayImage) -> GrayImage {
    let n = (g.width() * g.height()).max(1) as f64;
    let mean = g.pixels().map(|p| p[0] as f64).sum::<f64>() / n;
    let var = g.pixels().map(|p| (p[0] as f64 - mean).powi(2)).sum::<f64>() / n;
    let k = 1.0 / (4.0 * var.sqrt().max(1.0));
    GrayImage::from_fn(g.width(), g.height(), |x, y| {
        let v = 0.5 + (g.get_pixel(x, y)[0] as f64 - mean) * k;
        image::Luma([(v.clamp(0.0, 1.0) * 255.0).round() as u8])
    })
}

/// Fetches and packs every model material into `dir` (assets/thirdparty/ambientcg), then writes the manifest.
pub fn run(dir: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let mut manifest = serde_json::Map::new();
    for (k, m) in MODEL_MATERIALS.iter().enumerate() {
        check(cancel)?;
        fetch(m.id, dir, pr)?;
        pack(m, dir)?;
        manifest.insert(m.class.into(), format!("{0}/{0}_detail.png", m.id).into());
        pr.fraction((k + 1) as f32 / MODEL_MATERIALS.len() as f32);
    }
    std::fs::write(dir.join(MANIFEST), serde_json::to_string_pretty(&manifest)?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brightness_detail_centres_on_the_mean() {
        let g = GrayImage::from_fn(4, 1, |x, _| image::Luma([[100, 100, 140, 60][x as usize]]));
        let d = brightness_detail(&g);
        // mean 100, σ = √800 ≈ 28.3: ±40 is ±1.41 σ → 0.5 ± 0.354
        assert_eq!(d.get_pixel(0, 0)[0], 128);
        assert_eq!(d.get_pixel(2, 0)[0], 218);
        assert_eq!(d.get_pixel(3, 0)[0], 37);
    }

    #[test]
    fn pack_lays_out_the_channels() {
        let dir = std::env::temp_dir().join(format!("iaf-model-detail-{}", std::process::id()));
        let m = Material { id: "Test001", class: "painted", size: 2 };
        let d = dir.join(m.id);
        std::fs::create_dir_all(&d).unwrap();
        image::RgbImage::from_pixel(2, 2, image::Rgb([10, 200, 255])).save(map_path(&d, m.id, "NormalGL")).unwrap();
        GrayImage::from_pixel(2, 2, image::Luma([90])).save(map_path(&d, m.id, "Roughness")).unwrap();
        GrayImage::from_pixel(2, 2, image::Luma([50])).save(map_path(&d, m.id, "Color")).unwrap();
        pack(&m, &dir).unwrap();
        let p = image::open(d.join("Test001_detail.png")).unwrap().to_rgba8();
        let px = p.get_pixel(1, 1);
        std::fs::remove_dir_all(&dir).unwrap();
        // JPEG is lossy: within a few levels.
        let near = |a: u8, b: u8| (a as i32 - b as i32).abs() <= 6;
        assert!(near(px[0], 90) && near(px[1], 200) && px[2] == 128 && near(px[3], 10), "{px:?}");
    }

    #[test]
    fn classes_are_unique() {
        let mut c: Vec<_> = MODEL_MATERIALS.iter().map(|m| m.class).collect();
        c.sort();
        c.dedup();
        assert_eq!(c.len(), MODEL_MATERIALS.len());
    }
}
