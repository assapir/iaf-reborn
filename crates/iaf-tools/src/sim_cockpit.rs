//! `iaf-sim own`'s cockpit display data (iaf-2026/docs/cockpit.md "Display data", data-formats.md §14): every jet's
//! `<data>/planes/_shared/cockpit/` and `<data>/planes/<jet>/cockpit/` (its own file wins) → `<assets>/COCKPITS_DIR/<jet>/`,
//! the files the shared cockpit readers take from a cockpit dir: `map.json` (the TSD map, cockpit.gd `_load_tsd_map`)
//! and `isr.png` (the GM picture, mfd.gd `_isr`) compiled from `tsd_map.json` into the sim's UTM 36N frame; the art
//! (`rwrsymb.png`, `adi.png`, …) copied and the layout (`cockpit.json`) copied with the GM picture's `MAPFRAME`.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};

use crate::progress::{Progress, check};
use crate::sim_bases::{fill_spans, utm36n};
use crate::sim_terrain::BOX;

/// Under the assets root: one dir per jet, named as its data folder.
pub const COCKPITS_DIR: &str = "converted/own/cockpits";
/// Under `<data>/planes`: every jet's files.
const SHARED: &str = "_shared";

/// The TSD map's frame (shared/util/world_map.gd, cockpit.gd `_load_tsd_map`): engine X / Y → the normalised
/// map.emf frame `u = (X + X_SHIFT) / W · F`, `v = (H − Y_SHIFT − Y) / H · F`. The reader turns it back into world X /
/// Y, which in the sim are the UTM easting / northing (iaf-2026/docs/terrain.md §2).
const X_SHIFT: f64 = 166850.0;
const Y_SHIFT: f64 = 21144.0;
const W: f64 = 819200.0;
const H: f64 = 1064960.0;
const F: f64 = 1.0071394;
/// The GM picture (mfd.gd `isr_px`): the original's 640 × 832 px, here 640 m a pixel from the theatre's north-west
/// corner (E0, N1), so the box (347 × 511 km) fits; the rest is black.
const ISR: (u32, u32) = (640, 832);
const ISR_M: f64 = 640.0;

/// World (UTM) metres → the map frame.
fn to_map(p: [f64; 2]) -> [f64; 2] {
    [(p[0] + X_SHIFT) / W * F, (H - Y_SHIFT - p[1]) / H * F]
}

/// The layout's `MAPFRAME` for isr.png, in the reader's terms (cockpits.ibx [MAPFRAME], mfd.gd `isr_px`: col =
/// (X + 166828 − left) / (right − left) · 640, row = (top − (Y + 21164)) / (top − bottom) · 832).
fn mapframe() -> Value {
    let (left, top) = (BOX[0] + 166828.0, BOX[3] + 21164.0);
    json!({"left": left, "top": top, "right": left + ISR.0 as f64 * ISR_M, "bottom": top - ISR.1 as f64 * ISR_M})
}

fn rgb(v: &Value, what: &str) -> Result<[u8; 3]> {
    let a = v.as_array().filter(|a| a.len() == 3).with_context(|| format!("tsd_map: {what} must be [r, g, b]"))?;
    let c = |i: usize| a[i].as_u64().filter(|&c| c < 256).map(|c| c as u8).context("tsd_map: a colour is 0..255");
    Ok([c(0)?, c(1)?, c(2)?])
}

/// `tsd_map.json` (polygons in lon / lat, painted in order over the background) → the EMF-JSON map.json the cockpit
/// reads (a background rectangle over the theatre's box, then one polygon op per ring, each point in UTM 36N) and the
/// GM picture (each layer at its `radar` brightness).
pub fn compile_map(map: &Value) -> Result<(Value, image::GrayImage)> {
    let bg = rgb(&map["background"], "background")?;
    let mut isr =
        image::GrayImage::from_pixel(ISR.0, ISR.1, image::Luma([map["background_radar"].as_u64().unwrap_or(0) as u8]));
    let flat = |pts: &[[f64; 2]]| -> Vec<f64> {
        pts.iter().flat_map(|p| [(p[0] * 1e5).round() / 1e5, (p[1] * 1e5).round() / 1e5]).collect()
    };
    let op = |ring: Vec<f64>, brush: [u8; 3]| json!({"t": "polygon", "rings": [ring], "pen": null, "brush": brush, "alternate": true});
    let corners = [[BOX[0], BOX[3]], [BOX[2], BOX[3]], [BOX[2], BOX[1]], [BOX[0], BOX[1]]];
    let mut ops = vec![op(flat(&corners.map(to_map)), bg)];
    for layer in map["layers"].as_array().context("tsd_map: no \"layers\"")? {
        let name = layer["name"].as_str().context("tsd_map: a layer has no name")?;
        let brush = rgb(&layer["brush"], name)?;
        let radar = layer["radar"].as_u64().filter(|&r| r < 256).with_context(|| format!("tsd_map: {name}: radar"))?;
        for ring in layer["rings"].as_array().with_context(|| format!("tsd_map: {name}: no rings"))? {
            let pts = ring.as_array().filter(|r| r.len() >= 3).with_context(|| format!("tsd_map: {name}: a ring"))?;
            let mut engine = Vec::with_capacity(pts.len());
            for p in pts {
                let (lon, lat) = (p[0].as_f64(), p[1].as_f64());
                let (lon, lat) = lon.zip(lat).with_context(|| format!("tsd_map: {name}: a point is [lon, lat]"))?;
                ensure!((-180.0..=180.0).contains(&lon) && (-90.0..=90.0).contains(&lat), "tsd_map: {name}: {p}");
                engine.push(utm36n(lon, lat));
            }
            ops.push(op(flat(&engine.iter().map(|&e| to_map(e)).collect::<Vec<_>>()), brush));
            let (w, h) = (ISR.0 as usize, ISR.1 as usize);
            fill_spans(w, h, [BOX[0], BOX[3]], ISR_M, &engine, |y, x0, x1| {
                for x in x0..x1 {
                    isr.put_pixel(x as u32, y as u32, image::Luma([radar as u8]));
                }
            });
        }
    }
    // frame_mm: map.emf's (the original's 126.01 × 163.83 mm); the cockpit reads only the ops.
    Ok((json!({"frame_mm": [126.01, 163.83], "ops": ops}), isr))
}

/// The files of `dirs` by name, a later dir's file over an earlier one's; subfolders left out.
fn files(dirs: &[PathBuf]) -> Result<BTreeMap<String, PathBuf>> {
    let mut out = BTreeMap::new();
    for d in dirs.iter().filter(|d| d.is_dir()) {
        for e in std::fs::read_dir(d).with_context(|| d.display().to_string())? {
            let e = e?;
            if e.file_type()?.is_file() {
                out.insert(e.file_name().to_string_lossy().into_owned(), e.path());
            }
        }
    }
    Ok(out)
}

/// One jet's cockpit dir: the files of `srcs` (the shared folder, then the jet's) → `out` (anything there that it did
/// not write is removed). The art must have the sizes the readers cut: rwrsymb.png 17 slots of 10 × 10, adi.png
/// 128 × 128 and mfds.png 264 × 924, times the layout's image_scale; the layout (cockpit.json, required) borrows
/// nothing ("Shared") and names no panel art.
fn jet(srcs: &[PathBuf], out: &Path, cancel: &AtomicBool) -> Result<BTreeSet<String>> {
    std::fs::create_dir_all(out).with_context(|| out.display().to_string())?;
    let mut written = BTreeSet::new();
    let mut scale = None;
    for (name, path) in files(srcs)? {
        check(cancel)?;
        let ctx = || path.display().to_string();
        match name.rsplit_once('.').map(|p| p.1) {
            _ if name == "tsd_map.json" => {
                let map: Value =
                    serde_json::from_str(&std::fs::read_to_string(&path).with_context(ctx)?).with_context(ctx)?;
                let (emf, isr) = compile_map(&map).with_context(ctx)?;
                std::fs::write(out.join("map.json"), serde_json::to_string(&emf)?)?;
                isr.save(out.join("isr.png")).context("isr.png")?;
                written.extend(["map.json".to_string(), "isr.png".to_string()]);
            }
            Some("json") => {
                let mut v: Value =
                    serde_json::from_str(&std::fs::read_to_string(&path).with_context(ctx)?).with_context(ctx)?;
                if name == "cockpit.json" {
                    ensure!(v.get("Shared").is_none(), "{}: an own cockpit borrows nothing (no \"Shared\")", ctx());
                    let art = v
                        .as_object()
                        .into_iter()
                        .flatten()
                        .find(|(_, sec)| sec.get("FileName").is_some() || sec.get("NightFileName").is_some());
                    if let Some((key, _)) = art {
                        bail!("{}: [{key}] names panel art (the sim's cockpit has none)", ctx());
                    }
                    let k = v["image_scale"].as_u64();
                    ensure!(
                        k.is_some() && scale.is_none_or(|s| Some(s) == k),
                        "{}: image_scale {k:?}, the art's {scale:?}",
                        ctx()
                    );
                    scale = k;
                    v.as_object_mut().with_context(ctx)?.insert("MAPFRAME".into(), mapframe());
                }
                std::fs::write(out.join(&name), serde_json::to_string(&v)?).with_context(ctx)?;
                written.insert(name);
            }
            Some("png" | "webp") => {
                let img = image::open(&path).with_context(ctx)?;
                let (w, h) = (img.width(), img.height());
                let want = match name.as_str() {
                    "rwrsymb.png" => Some((10, 170)),
                    "adi.png" => Some((128, 128)),
                    "mfds.png" => Some((264, 924)),
                    _ => None,
                };
                if let Some((bw, bh)) = want {
                    ensure!(w % bw == 0 && w / bw * bh == h, "{}: {w} x {h} is not {bw} x {bh} scaled", ctx());
                    let s = u64::from(w / bw);
                    ensure!(scale.is_none_or(|k| k == s), "{}: scale {s}, cockpit.json's image_scale {scale:?}", ctx());
                    scale = Some(s);
                }
                std::fs::copy(&path, out.join(&name)).with_context(ctx)?;
                written.insert(name);
            }
            _ => {} // sources and notes stay in the data
        }
    }
    for need in ["cockpit.json", "rwrsymb.png", "mfds.png"] {
        ensure!(written.contains(need), "{}: no {need}", srcs[srcs.len() - 1].display());
    }
    for e in std::fs::read_dir(out)? {
        let e = e?;
        if !written.contains(&*e.file_name().to_string_lossy()) {
            let p = e.path();
            if e.file_type()?.is_dir() { std::fs::remove_dir_all(&p) } else { std::fs::remove_file(&p) }
                .with_context(|| p.display().to_string())?;
        }
    }
    Ok(written)
}

/// Every `<data>/planes/<jet>/cockpit/` with `<data>/planes/_shared/cockpit/` → `<assets>/COCKPITS_DIR/<jet>/`; the
/// number of jets.
pub fn cockpits(data: &Path, assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<usize> {
    let planes = data.join("planes");
    let mut jets: Vec<String> = std::fs::read_dir(&planes)
        .with_context(|| planes.display().to_string())?
        .filter_map(|e| e.ok().map(|e| e.file_name().to_string_lossy().into_owned()))
        .filter(|j| j != SHARED && planes.join(j).join("cockpit").is_dir())
        .collect();
    jets.sort();
    if jets.is_empty() {
        bail!("{}: no <jet>/cockpit folder", planes.display());
    }
    for j in &jets {
        let out = assets.join(COCKPITS_DIR).join(j);
        let files = jet(&[planes.join(SHARED).join("cockpit"), planes.join(j).join("cockpit")], &out, cancel)?;
        crate::log!(pr, "own: cockpit {j}: {} -> {}", files.into_iter().collect::<Vec<_>>().join(", "), out.display());
    }
    Ok(jets.len())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::progress::Stdout;

    fn data() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../iaf-2026/data")
    }

    /// Even-odd point-in-polygon on a flat [x, y, …] ring.
    fn inside(ring: &[f64], p: [f64; 2]) -> bool {
        let n = ring.len() / 2;
        let mut c = false;
        for i in 0..n {
            let (a, b) = ([ring[2 * i], ring[2 * i + 1]], [ring[2 * ((i + 1) % n)], ring[2 * ((i + 1) % n) + 1]]);
            if (a[1] > p[1]) != (b[1] > p[1]) && p[0] < a[0] + (p[1] - a[1]) / (b[1] - a[1]) * (b[0] - a[0]) {
                c = !c;
            }
        }
        c
    }

    /// The colour the painter's order leaves at map point `p`.
    fn colour_at(ops: &[Value], p: [f64; 2]) -> Value {
        let mut out = Value::Null;
        for op in ops {
            let ring: Vec<f64> = op["rings"][0].as_array().unwrap().iter().map(|v| v.as_f64().unwrap()).collect();
            if inside(&ring, p) {
                out = op["brush"].clone();
            }
        }
        out
    }

    /// Every jet's display data compiles from the shared folder and its own: the readers' files are written in their
    /// shapes (map.json's ops as cockpit.gd reads them, isr.png 640 × 832, the glyph sheet and ADI ball at the cut
    /// sizes); the map, read back into world X / Y as cockpit.gd does, paints places at their UTM 36N metres (gdaltransform
    /// EPSG:4326 → EPSG:32636): Tel Aviv, Katzrin and Majdal Shams as Israel (the Golan to the 1974 line), old Quneitra
    /// (east of it), Amman as neighbours, Ramallah and Gaza City as the PA's areas, Ariel and Ma'ale Adumim as Area C, the
    /// Mediterranean and the Sea of Galilee as water; the GM picture through the layout's MAPFRAME is lit on land and
    /// dark at sea; each layout has its sections and the MFD atlas its size; a stale file and folder go, and a borrowed
    /// cockpit ("Shared") or one naming panel art is refused.
    #[test]
    fn own_cockpits_compile() {
        let root = std::env::temp_dir().join(format!("iaf-sim-cockpits-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let f16i = root.join(COCKPITS_DIR).join("f16i");
        std::fs::create_dir_all(&f16i).unwrap();
        std::fs::write(f16i.join("stale.png"), b"x").unwrap();
        std::fs::create_dir_all(f16i.join("stale/inner")).unwrap();
        let n = cockpits(&data(), &root, &Stdout, &AtomicBool::new(false)).unwrap();
        assert_eq!(n, 3, "the jets, not the shared folder");
        assert!(!f16i.join("stale.png").exists() && !f16i.join("stale").exists());
        let (israel, neighbour, area_c, pa, sea) = (
            json!([200, 199, 199]),
            json!([137, 136, 135]),
            json!([186, 185, 184]),
            json!([157, 156, 154]),
            json!([34, 34, 91]),
        );
        for jet in ["f16i", "f16d", "f35i"] {
            let dir = root.join(COCKPITS_DIR).join(jet);
            let map: Value = serde_json::from_str(&std::fs::read_to_string(dir.join("map.json")).unwrap()).unwrap();
            let ops = map["ops"].as_array().unwrap();
            assert!(ops.len() > 10, "{jet}: {} ops", ops.len());
            for op in ops {
                assert_eq!(op["t"], "polygon");
                assert_eq!(op["brush"].as_array().unwrap().len(), 3);
                let ring = op["rings"][0].as_array().unwrap();
                assert!(ring.len() >= 6 && ring.len() % 2 == 0);
                assert!(ring.iter().all(|v| v.as_f64().unwrap().abs() < 3.0), "{jet}: a point far off the frame");
            }
            // World X / Y (cockpit.gd: X = u / F · W − X_SHIFT, Y = H − Y_SHIFT − v / F · H) of each op's points.
            let world: Vec<Value> = ops
                .iter()
                .map(|op| {
                    let r = op["rings"][0].as_array().unwrap().iter().map(|v| v.as_f64().unwrap()).collect::<Vec<_>>();
                    let pts = r.chunks(2).flat_map(|p| [p[0] / F * W - X_SHIFT, H - Y_SHIFT - p[1] / F * H]);
                    json!({"rings": [pts.collect::<Vec<_>>()], "brush": op["brush"]})
                })
                .collect();
            let at = |e: f64, n: f64| colour_at(&world, [e, n]);
            assert_eq!(at(668_156.0, 3_551_280.0), israel, "Tel Aviv");
            assert_eq!(at(751_301.0, 3_653_669.0), israel, "Katzrin");
            assert_eq!(at(757_882.0, 3_684_573.0), israel, "Majdal Shams");
            assert_eq!(at(763_438.0, 3_668_760.0), neighbour, "old Quneitra");
            assert_eq!(at(776_795.0, 3_539_071.0), neighbour, "Amman");
            assert_eq!(at(708_438.0, 3_531_892.0), pa, "Ramallah");
            assert_eq!(at(639_298.0, 3_486_137.0), pa, "Gaza City");
            assert_eq!(at(704_443.0, 3_554_196.0), area_c, "Ariel");
            assert_eq!(at(717_798.0, 3_518_021.0), area_c, "Ma'ale Adumim");
            assert_eq!(at(546_813.0, 3_629_226.0), sea, "the Mediterranean");
            assert_eq!(at(742_471.0, 3_634_304.0), sea, "the Sea of Galilee");
            let lay: Value = serde_json::from_str(&std::fs::read_to_string(dir.join("cockpit.json")).unwrap()).unwrap();
            let isr = image::open(dir.join("isr.png")).unwrap().to_luma8();
            assert_eq!(isr.dimensions(), ISR);
            // mfd.gd isr_px through the layout's MAPFRAME.
            let px = |e: f64, n: f64| {
                let f = |k: &str| lay["MAPFRAME"][k].as_f64().unwrap();
                let col = (e + 166828.0 - f("left")) / (f("right") - f("left")) * ISR.0 as f64;
                let row = (f("top") - (n + 21164.0)) / (f("top") - f("bottom")) * ISR.1 as f64;
                isr.get_pixel(col as u32, row as u32).0[0]
            };
            assert!(px(668_156.0, 3_551_280.0) > 100 && px(708_438.0, 3_531_892.0) > 100, "land lit");
            assert!(px(546_813.0, 3_629_226.0) == 0 && px(742_471.0, 3_634_304.0) == 0, "water dark");
            let rwr = image::open(dir.join("rwrsymb.png")).unwrap();
            assert_eq!((rwr.width(), rwr.height()), (40, 680));
            if jet != "f35i" {
                let adi = image::open(dir.join("adi.png")).unwrap();
                assert_eq!((adi.width(), adi.height()), (512, 512));
            }
            let mfds = image::open(dir.join("mfds.png")).unwrap();
            assert_eq!((mfds.width(), mfds.height()), (1056, 3696));
            assert_eq!(lay["image_scale"], 4);
            assert!(lay["HUD"]["BorePositionY"].is_number() && lay["MFD"].is_object(), "{jet}: [HUD], [MFD]");
            assert_eq!(lay.get("PCD").is_some(), jet == "f35i", "{jet}: [PCD] on the F-35I only");
        }
        // A cockpit that borrows the original's art is refused.
        let bad = root.join("bad/planes/x/cockpit");
        std::fs::create_dir_all(&bad).unwrap();
        std::fs::write(bad.join("cockpit.json"), r#"{"Shared": "f16"}"#).unwrap();
        std::fs::copy(data().join("planes/_shared/cockpit/rwrsymb.png"), bad.join("rwrsymb.png")).unwrap();
        let err = cockpits(&root.join("bad"), &root, &Stdout, &AtomicBool::new(false)).unwrap_err();
        assert!(format!("{err:#}").contains("Shared"), "{err:#}");
        // So is one that names panel art.
        std::fs::write(bad.join("cockpit.json"), r#"{"image_scale": 4, "PANEL": {"FileName": "f16panel.bmp"}}"#)
            .unwrap();
        let err = cockpits(&root.join("bad"), &root, &Stdout, &AtomicBool::new(false)).unwrap_err();
        assert!(format!("{err:#}").contains("panel art"), "{err:#}");
        std::fs::remove_dir_all(&root).unwrap();
    }
}
