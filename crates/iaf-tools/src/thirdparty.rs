//! Third-party CC0 textures from ambientCG (<https://ambientcg.com/>, licence: <https://docs.ambientcg.com/license/>),
//! downloaded by setup into `assets/thirdparty/ambientcg/<id>/` (docs/rendering.md §1.4, §9, docs/credits.md). Each
//! list below is one use (Ground textures, Model detail); `fetch` takes any list, so more uses add a list.
//!
//! Per material `fetch` downloads `<id>_2K-JPG.zip`, checks its SHA-256 against the pinned one, keeps the colour,
//! normal (OpenGL) and roughness maps, and packs them at 1024² with every mip level, compressed as the GPU reads them
//! (the game only uploads them):
//! - `albedo.bc1`: BC1 (DXT1), RGB = the colour (linear) over the material's mean colour, halved (1.0 = the mean is
//!   128): the game multiplies the imagery by it, so the photo keeps its own hue and brightness;
//! - `nr.bc3`: BC3 (DXT5), R = roughness, G = normal Y, B = the colour's brightness about its mean (0.5 = the mean,
//!   ±2 σ to 0 / 1: stains, chips, scratches; Model detail's tint), A = normal X (the DXT5 normal layout).
//!
//! Then `material.json` (id, size, checksum) marks the material done, and `<list>.json` lists the list's materials.
//!
//! The scenery's sources (`SCENERY`, docs/scenery.md §1.1) are kept as they come: `fetch_files` downloads each into
//! `assets/source/scenery/` and checks its pinned SHA-256.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use image::{GrayImage, RgbaImage, imageops::FilterType};
use serde_json::json;
use sha2::{Digest, Sha256};
use texpresso::{Algorithm, Format, Params};

use crate::progress::{Progress, check};

/// One ambientCG material: its asset id, the SHA-256 of its `<id>_2K-JPG.zip`, the real size one texture repeat
/// covers (metres; ambientCG's dimension where it gives one, else inferred) and what the game uses it for.
pub struct Material {
    pub id: &'static str,
    pub sha256: &'static str,
    pub size_m: f32,
    pub used_for: &'static str,
}

/// The "Ground textures" materials (Graphics → MORE, terrain.gdshader), in the shader's layer order.
pub const GROUND_TEXTURES: &[Material] = &[
    Material {
        id: "Asphalt027C",
        sha256: "5c20e533bc497645f06401972abbff2b49e854b899ece727730d213973961c15",
        size_m: 2.5,
        used_for: "runways and taxiways: cracked asphalt",
    },
    Material {
        id: "Concrete040",
        sha256: "f757c69e3c9e380b76bfd9fd0641f519d3717b8ecd1dd76a99e14c3a3695dd7f",
        size_m: 1.4,
        used_for: "aprons: rough concrete",
    },
    Material {
        id: "Ground054",
        sha256: "643e7c8689bac041f17c660eff6a5459bfe0535d4466737beb0e64902b23235a",
        size_m: 3.5,
        used_for: "pale ground: sand",
    },
    Material {
        id: "Ground062L",
        sha256: "a24162411319167954438c0bf5479e38c0d9042d96eadaab4b5f05b8bd0199cb",
        size_m: 3.0,
        used_for: "grey-brown ground: gravel desert",
    },
    Material {
        id: "Ground037",
        sha256: "defa9f880ec692eb3ef5435fd7bc7b8721c0d577f7824ea18ac68537f01ab65b",
        size_m: 2.1,
        used_for: "green ground: grass and fields",
    },
    Material {
        id: "Ground109",
        sha256: "1f32c5ffa599e32c61405417d9b682dcc23e6ccc38f8a3a09880f204a481e0c8",
        size_m: 2.8,
        used_for: "brown ground: dry soil and scrub",
    },
    Material {
        id: "Rock045",
        sha256: "95f8f208d4426ab7885a896a6004a85ce83dac3e098b9790a3cd7422f2d3d021",
        size_m: 2.4,
        used_for: "steep slopes: rock",
    },
];

/// The "Model detail" materials (Graphics → MORE, game/util/model_detail.gd), in that file's MATERIALS order: painted,
/// worn, concrete, rubber. The game sets each use's own repeat; `size_m` is the material's real size.
pub const MODEL_DETAIL: &[Material] = &[
    Material {
        id: "PaintedMetal002",
        sha256: "c95fc5a065582deded194e7bc4d9592706b58aa0259110989931ec8f8ad1a9a0",
        size_m: 1.0,
        used_for: "stores and jets: painted metal",
    },
    Material {
        id: "Metal016",
        sha256: "0fbb57ee6787731f538f711223109eb5539287f8c0eda7ccba690858c3ece213",
        size_m: 1.5,
        used_for: "vehicles, ships, metal structures: worn steel",
    },
    Material {
        id: "Concrete029",
        sha256: "7685a6a63cfd21cf737c3eae61c226dee2d9259a57aa93164bdd1b2e748afd94",
        size_m: 3.0,
        used_for: "buildings and shelters: cast concrete",
    },
    Material {
        id: "Rubber004",
        sha256: "dc1566f645f6ef7853bb3a3e7a15ef450edbb90cbd471c6097d44cd04521bea0",
        size_m: 0.5,
        used_for: "tyres: rubber",
    },
];

/// Every list setup fetches: (name, materials). A new use adds its list here; `<dir>/<name>.json` lists it for the game.
pub const LISTS: &[(&str, &[Material])] = &[("ground", GROUND_TEXTURES), ("model", MODEL_DETAIL)];

/// One downloaded file kept as it comes (the scenery's sources, docs/scenery.md §1.1): its name under the download
/// folder, where it comes from and its pinned SHA-256.
pub struct Download {
    pub file: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
}

/// The scenery's sources (`crate::scenery`), each file pinned: every install makes the same scenery.
pub const SCENERY: &[Download] = &[
    // LIST
];

/// True when `<dir>/<file>.ok` records the pinned checksum (downloaded and checked before) and the file is there.
pub fn file_done(dir: &Path, d: &Download) -> bool {
    std::fs::read_to_string(dir.join(format!("{}.ok", d.file))).is_ok_and(|t| t.lines().next() == Some(d.sha256))
        && dir.join(d.file).is_file()
}

/// The day (YYYY-MM-DD, UTC) `fetch_files` checked the file, from its `.ok` mark.
pub fn file_date(dir: &Path, d: &Download) -> Option<String> {
    let t = std::fs::read_to_string(dir.join(format!("{}.ok", d.file))).ok()?;
    t.lines().nth(1).map(str::to_string)
}

/// Today (UTC) as YYYY-MM-DD.
fn today() -> String {
    let days = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs() / 86400);
    // Howard Hinnant's civil_from_days.
    let z = days as i64 + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    format!("{:04}-{m:02}-{d:02}", yoe + era * 400 + (m <= 2) as i64)
}

/// Every file of `list` into `dir` (curl, so `file://` works too), checked against its pinned SHA-256. Files done before are kept. Returns how many it fetched.
pub fn fetch_files(list: &[Download], dir: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<usize> {
    std::fs::create_dir_all(dir)?;
    let mut n = 0;
    for (k, d) in list.iter().enumerate() {
        check(cancel)?;
        if !file_done(dir, d) {
            let (p, part) = (dir.join(d.file), dir.join(format!("{}.part", d.file)));
            // A file already there (copied in by hand) only needs its check.
            if !(p.is_file() && sha256_file(&p)? == d.sha256) {
                pr.log(&format!("downloading {}", d.file));
                let status = Command::new("curl")
                    .args(["-fsSL", "--retry", "3", "--connect-timeout", "30", "-o"])
                    .arg(&part)
                    .arg(d.url)
                    .status()
                    .context("running curl")?;
                let sum = if status.success() { sha256_file(&part)? } else { String::new() };
                if sum != d.sha256 {
                    let _ = std::fs::remove_file(&part);
                    if status.success() {
                        bail!(
                            "{}: checksum mismatch (got {sum}, pinned {}): the file at {} changed",
                            d.file,
                            d.sha256,
                            d.url
                        );
                    }
                    bail!("{}: download failed (curl {status})", d.file);
                }
                std::fs::rename(&part, &p)?;
                n += 1;
            }
            std::fs::write(dir.join(format!("{}.ok", d.file)), format!("{}\n{}\n", d.sha256, today()))?;
        }
        pr.fraction((k + 1) as f32 / list.len() as f32);
    }
    Ok(n)
}

/// Where ambientCG serves the zips.
pub const AMBIENTCG: &str = "https://ambientcg.com/get?file=";
/// The packed maps' side (texels).
pub const SIDE: u32 = 1024;
/// The packing's version: `material.json` records it, and a material packed by another version is fetched again.
pub const PACK: u32 = 4;

/// The lowercase hex SHA-256 of a file.
pub fn sha256_file(p: &Path) -> Result<String> {
    let mut f = std::fs::File::open(p).with_context(|| format!("{}", p.display()))?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            return Ok(h.finalize().iter().map(|b| format!("{b:02x}")).collect());
        }
        h.update(&buf[..n]);
    }
}

/// True when `<dir>/<id>/material.json` records this material's checksum (fetched and packed before).
pub fn is_done(dir: &Path, m: &Material) -> bool {
    std::fs::read_to_string(dir.join(m.id).join("material.json"))
        .ok()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
        .is_some_and(|v| v["sha256"] == m.sha256 && v["pack"] == PACK && dir.join(m.id).join("nr.bc3").is_file())
}

/// Every material of `list` into `dir` (fetched from `base`, e.g. [`AMBIENTCG`], with the zip's name appended; curl,
/// so `file://` works too), then `<dir>/<name>.json`. Materials already done are kept. Returns how many it fetched.
pub fn fetch(
    name: &str,
    list: &[Material],
    base: &str,
    dir: &Path,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<usize> {
    std::fs::create_dir_all(dir)?;
    let mut n = 0;
    for (k, m) in list.iter().enumerate() {
        check(cancel)?;
        if !is_done(dir, m) {
            fetch_one(m, base, dir, pr)?;
            n += 1;
        }
        pr.fraction((k + 1) as f32 / list.len() as f32);
    }
    let mats: Vec<_> = list.iter().map(|m| json!({ "id": m.id, "size_m": m.size_m, "used_for": m.used_for })).collect();
    std::fs::write(dir.join(format!("{name}.json")), serde_json::to_string_pretty(&json!({ "materials": mats }))?)?;
    Ok(n)
}

fn fetch_one(m: &Material, base: &str, dir: &Path, pr: &dyn Progress) -> Result<()> {
    let zip_name = format!("{}_2K-JPG.zip", m.id);
    let part = dir.join(format!("{zip_name}.part"));
    pr.log(&format!("{}: downloading {zip_name}", m.id));
    let status = Command::new("curl")
        .args(["-fsSL", "--retry", "2", "--connect-timeout", "20", "-o"])
        .arg(&part)
        .arg(format!("{base}{zip_name}"))
        .status()
        .context("running curl")?;
    let r = (|| -> Result<()> {
        if !status.success() {
            bail!("{}: download failed (curl {status})", m.id);
        }
        let sum = sha256_file(&part)?;
        if sum != m.sha256 {
            bail!("{}: checksum mismatch (got {sum}, pinned {}): the file on ambientCG changed", m.id, m.sha256);
        }
        unpack(m, &part, &dir.join(m.id))
    })();
    let _ = std::fs::remove_file(&part);
    r
}

/// The zip's colour, normal and roughness maps into `out`, packed (module doc).
fn unpack(m: &Material, zip_path: &Path, out: &Path) -> Result<()> {
    let mut zip = zip::ZipArchive::new(std::fs::File::open(zip_path)?)?;
    std::fs::create_dir_all(out)?;
    let mut map = |kind: &str| -> Result<(PathBuf, RgbaImage)> {
        let name = format!("{}_2K-JPG_{kind}.jpg", m.id);
        let mut data = Vec::new();
        zip.by_name(&name).with_context(|| format!("{name} not in the zip"))?.read_to_end(&mut data)?;
        let p = out.join(&name);
        std::fs::write(&p, &data)?;
        let img = image::load_from_memory(&data).with_context(|| name.clone())?.to_rgba8();
        Ok((p, image::imageops::resize(&img, SIDE, SIDE, FilterType::Triangle)))
    };
    let (_, colour) = map("Color")?;
    let (_, normal) = map("NormalGL")?;
    let (_, rough) = map("Roughness")?;
    let bright = brightness_detail(&image::DynamicImage::ImageRgba8(colour.clone()).to_luma8());
    let albedo = detail_ratio(&colour);
    let mut nr = RgbaImage::new(SIDE, SIDE);
    for (x, y, p) in nr.enumerate_pixels_mut() {
        let n = normal.get_pixel(x, y).0;
        p.0 = [rough.get_pixel(x, y).0[0], n[1], bright.get_pixel(x, y).0[0], n[0]];
    }
    std::fs::write(out.join("albedo.bc1"), compress(&mip_chain(albedo), Format::Bc1, [1.0, 1.0, 1.0]))?;
    // The normal's Y in G weighs most.
    std::fs::write(out.join("nr.bc3"), compress(&mip_chain(nr), Format::Bc3, [0.3, 1.0, 0.5]))?;
    let meta = json!({ "id": m.id, "size_m": m.size_m, "sha256": m.sha256, "side": SIDE, "pack": PACK, "licence": "CC0 1.0",
        "source": format!("https://ambientcg.com/a/{}", m.id) });
    std::fs::write(out.join("material.json"), serde_json::to_string_pretty(&meta)?)?;
    Ok(())
}

/// sRGB `colour` as (linear colour / its mean) / 2 per channel, in 0..255 (A = 255).
pub fn detail_ratio(colour: &RgbaImage) -> RgbaImage {
    let lin = |v: u8| {
        let c = v as f64 / 255.0;
        if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
    };
    let lut: Vec<f64> = (0..=255u8).map(lin).collect();
    let mut mean = [0f64; 3];
    for p in colour.pixels() {
        (0..3).for_each(|c| mean[c] += lut[p.0[c] as usize]);
    }
    let n = (colour.width() * colour.height()).max(1) as f64;
    let mean = mean.map(|m| (m / n).max(1e-4));
    let mut out = RgbaImage::new(colour.width(), colour.height());
    for (q, p) in out.pixels_mut().zip(colour.pixels()) {
        let r = |c: usize| (lut[p.0[c] as usize] / mean[c] * 0.5 * 255.0).round().clamp(0.0, 255.0) as u8;
        q.0 = [r(0), r(1), r(2), 255];
    }
    out
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

/// Every level of `levels` compressed as `format` (block weights `w` for R, G, B), concatenated (Godot's
/// `Image.create_from_data` layout for a compressed image with mipmaps).
pub fn compress(levels: &[RgbaImage], format: Format, w: [f32; 3]) -> Vec<u8> {
    let params = Params { algorithm: Algorithm::ClusterFit, weights: w, weigh_colour_by_alpha: false };
    let mut out = Vec::new();
    for l in levels {
        let (wd, ht) = (l.width() as usize, l.height() as usize);
        let mut buf = vec![0u8; format.compressed_size(wd, ht)];
        format.compress(l.as_raw(), wd, ht, params, &mut buf);
        out.extend_from_slice(&buf);
    }
    out
}

/// The image and every 2×2 box-filtered level down to 1×1.
pub fn mip_chain(mut img: RgbaImage) -> Vec<RgbaImage> {
    let mut out = vec![img.clone()];
    while img.width() > 1 || img.height() > 1 {
        let (w, h) = ((img.width() / 2).max(1), (img.height() / 2).max(1));
        let mut next = RgbaImage::new(w, h);
        for (x, y, p) in next.enumerate_pixels_mut() {
            let mut s = [0u32; 4];
            for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let q = img.get_pixel((2 * x + dx).min(img.width() - 1), (2 * y + dy).min(img.height() - 1)).0;
                (0..4).for_each(|c| s[c] += q[c] as u32);
            }
            p.0 = s.map(|v| ((v + 2) / 4) as u8);
        }
        out.push(next.clone());
        img = next;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::progress::Stdout;
    use std::io::Write;

    /// A fake material zip (8×8 maps) in a fresh folder; returns (folder, zip path).
    fn fake_zip(tag: &str) -> (PathBuf, PathBuf) {
        let d = std::env::temp_dir().join(format!("iaf-thirdparty-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("src")).unwrap();
        let zp = d.join("src/Fake001_2K-JPG.zip");
        let mut z = zip::ZipWriter::new(std::fs::File::create(&zp).unwrap());
        for kind in ["Color", "NormalGL", "Roughness"] {
            let mut jpg = Vec::new();
            image::RgbImage::from_pixel(8, 8, image::Rgb([128, 100, 200]))
                .write_to(&mut std::io::Cursor::new(&mut jpg), image::ImageFormat::Jpeg)
                .unwrap();
            z.start_file(format!("Fake001_2K-JPG_{kind}.jpg"), zip::write::SimpleFileOptions::default()).unwrap();
            z.write_all(&jpg).unwrap();
        }
        z.finish().unwrap();
        (d, zp)
    }

    #[test]
    fn detail_ratio_maps_the_mean_to_half() {
        let mut img = RgbaImage::from_pixel(2, 1, image::Rgba([60, 60, 60, 255]));
        img.put_pixel(1, 0, image::Rgba([200, 200, 200, 255]));
        let r = detail_ratio(&img);
        let (a, b) = (r.get_pixel(0, 0).0[0] as u32, r.get_pixel(1, 0).0[0] as u32);
        assert!((a + b).abs_diff(255) <= 1 && a < b, "{a} {b}");
    }

    #[test]
    fn mip_chain_has_every_level() {
        let v = mip_chain(RgbaImage::from_pixel(4, 4, image::Rgba([10, 20, 30, 40])));
        assert_eq!(v.iter().map(|l| l.width()).collect::<Vec<_>>(), [4, 2, 1]);
        assert_eq!(v[2].get_pixel(0, 0).0, [10, 20, 30, 40]);
        // BC1: 8 bytes per 4×4 block, a level under 4 px one block.
        assert_eq!(compress(&v, Format::Bc1, [1.0; 3]).len(), 3 * 8);
    }

    #[test]
    fn fetch_checks_the_pinned_checksum() {
        let (d, zp) = fake_zip("sum");
        let sum = sha256_file(&zp).unwrap();
        let base = format!("file://{}/", zp.parent().unwrap().display());
        let out = d.join("out");
        let bad = [Material { id: "Fake001", sha256: "00", size_m: 2.0, used_for: "test" }];
        let e = fetch("test", &bad, &base, &out, &Stdout, &AtomicBool::new(false)).unwrap_err();
        assert!(format!("{e:#}").contains("checksum mismatch"), "{e:#}");
        assert!(!out.join("Fake001/material.json").exists() && !out.join("Fake001_2K-JPG.zip.part").exists());

        let sum: &'static str = Box::leak(sum.into_boxed_str());
        let good = [Material { id: "Fake001", sha256: sum, size_m: 2.0, used_for: "test" }];
        assert_eq!(fetch("test", &good, &base, &out, &Stdout, &AtomicBool::new(false)).unwrap(), 1);
        let nr = std::fs::read(out.join("Fake001/nr.bc3")).unwrap();
        assert_eq!(nr.len(), (0..=10).map(|k| 16 * ((SIDE as usize >> k).div_ceil(4)).pow(2)).sum::<usize>());
        assert!(out.join("Fake001/Fake001_2K-JPG_Color.jpg").is_file() && out.join("test.json").is_file());
        // Done before: kept, nothing fetched (the source may be gone).
        std::fs::remove_file(&zp).unwrap();
        assert_eq!(fetch("test", &good, &base, &out, &Stdout, &AtomicBool::new(false)).unwrap(), 0);
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn fetch_files_checks_and_keeps() {
        let (d, zp) = fake_zip("files");
        let url: &'static str = Box::leak(format!("file://{}", zp.display()).into_boxed_str());
        let sum: &'static str = Box::leak(sha256_file(&zp).unwrap().into_boxed_str());
        let out = d.join("out");
        let no = AtomicBool::new(false);
        let bad = [Download { file: "a.zip", url, sha256: "00" }];
        assert!(format!("{:#}", fetch_files(&bad, &out, &Stdout, &no).unwrap_err()).contains("checksum mismatch"));
        assert!(!out.join("a.zip").exists() && !out.join("a.zip.part").exists());
        let good = [Download { file: "a.zip", url, sha256: sum }];
        assert_eq!(fetch_files(&good, &out, &Stdout, &no).unwrap(), 1);
        assert!(file_done(&out, &good[0]) && file_date(&out, &good[0]).is_some_and(|d| d.len() == 10));
        assert_eq!(fetch_files(&good, &out, &Stdout, &no).unwrap(), 0, "kept");
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn brightness_detail_centres_on_the_mean() {
        let g = GrayImage::from_fn(4, 1, |x, _| image::Luma([[100, 100, 140, 60][x as usize]]));
        let d = brightness_detail(&g);
        // mean 100, σ = √800 ≈ 28.3: ±40 is ±1.41 σ → 0.5 ± 0.354
        assert_eq!([0, 2, 3].map(|x| d.get_pixel(x, 0)[0]), [128, 218, 37]);
    }

    #[test]
    fn every_list_is_pinned() {
        let mut ids: Vec<_> = LISTS.iter().flat_map(|(_, l)| l.iter().map(|m| m.id)).collect();
        ids.sort();
        ids.dedup();
        assert_eq!(ids.len(), LISTS.iter().map(|(_, l)| l.len()).sum::<usize>(), "a material in two lists");
        for m in LISTS.iter().flat_map(|(_, l)| l.iter()) {
            assert!(m.sha256.len() == 64 && m.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "{}", m.id);
            assert!(m.size_m >= 0.25 && m.size_m < 10.0, "{}", m.id);
        }
    }
}
