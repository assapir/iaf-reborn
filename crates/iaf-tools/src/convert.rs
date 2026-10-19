//! `iaf-convert`'s work (docs in the bin): each entry point converts one kind of original asset under
//! `<install-dir>` into `<out>`, reporting through a `Progress` and stopping between items once `cancel` is set.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use anyhow::{Context, Result, bail};
use iaf_formats::model::Model;
use image::RgbaImage;

use crate::exe::{PeImage, Release};
use crate::gltf::write_model;
use crate::log;
use crate::progress::{Progress, check, name_lc, par_map, parent, stem_lc};
use crate::upscale;

/// `--upscale` / `--smooth`.
#[derive(Clone, Copy, Debug, Default)]
pub struct Options {
    /// Resample textures 4× (Lanczos).
    pub upscale: bool,
    /// Round the low-poly geometry (smooth normals + Phong tessellation).
    pub smooth: bool,
}

impl Options {
    /// `img` resampled 4× with `--upscale`, else unchanged.
    fn scaled(&self, img: RgbaImage) -> RgbaImage {
        if self.upscale { upscale::upscale(&img) } else { img }
    }
}

/// `iaf-convert model`: one model → glTF + PNG textures (textures also looked up in `extra_texture_dirs`).
pub fn model(
    src: &Path,
    out_dir: &Path,
    extra_texture_dirs: &[PathBuf],
    opts: &Options,
    pr: &dyn Progress,
) -> Result<()> {
    let model = Model::parse(&std::fs::read(src)?).with_context(|| format!("parsing {}", src.display()))?;
    let name = stem_lc(src)?;
    let mut dirs = vec![parent(src)?.to_path_buf()];
    dirs.extend_from_slice(extra_texture_dirs);
    let warnings = write_model(&model, &name, &dirs, out_dir, opts.upscale, opts.smooth)?;
    log!(pr, "{} -> {}/{name}.gltf", src.display(), out_dir.display());
    for w in warnings {
        log!(pr, "  warning: {w}");
    }
    Ok(())
}

/// An extra plane's arming art (docs/adding-a-plane.md §5) from the original arming art in `menu_img`
/// (`<converted menu>/img`, its `arm/jets/*.png`) and the plane's `arm_dir` (`front.png`, `arm.json`).
pub fn arm_extra(menu_img: &Path, arm_dir: &Path, out: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    check(cancel)?;
    let jets = menu_img.join("arm/jets");
    let arm: serde_json::Value =
        serde_json::from_slice(&std::fs::read(arm_dir.join("arm.json"))?).context("arm.json")?;
    let base_name = arm["base_art"].as_str().unwrap_or("f-16");
    let mut originals = Vec::new();
    let mut base = None;
    for e in std::fs::read_dir(&jets).with_context(|| format!("{}", jets.display()))? {
        let p = e?.path();
        let stem = p.file_stem().unwrap_or_default().to_string_lossy().to_string();
        if p.extension().is_some_and(|x| x == "png") && Path::new(&p) != out && !stem.starts_with("x_") {
            let img = image::open(&p)?.to_rgba8();
            if stem == base_name {
                base = Some(img.clone());
            }
            originals.push(img);
        }
    }
    let base = base.with_context(|| format!("no {base_name}.png in {}", jets.display()))?;
    let front = image::open(arm_dir.join("front.png"))?.to_rgba8();
    let pairs = |k: &str| -> Vec<(f32, f32)> {
        arm[k]
            .as_array()
            .into_iter()
            .flatten()
            .map(|p| (p[0].as_f64().unwrap_or(0.0) as f32, p[1].as_f64().unwrap_or(0.0) as f32))
            .collect()
    };
    let scale = base.width() as f32 / 454.0;
    let img = crate::plane::compose_arm(&originals, &base, &front, &pairs("boxes"), &pairs("points"), scale);
    img.save(out)?;
    log!(pr, "{} -> {} ({} originals)", arm_dir.display(), out.display(), originals.len());
    Ok(())
}

/// Every aircraft of the install (controllable and non-controllable `*_h.xfr` frame files):
/// the glTF model plus `aircraft.json` (docs/aircraft.md) per plane folder, the index
/// `<out>/aircraft.json` and the afterburner texture `<out>/afterburn.png`. `missions` is the
/// converted mission folder (the object database gives each model its aircraft type codes).
pub fn aircraft(
    install: &Path,
    missions: &Path,
    out: &Path,
    opts: &Options,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<()> {
    use crate::aircraft;
    let objects_root = install.join("resource/3dobjects");
    let mut db = std::collections::HashMap::new();
    for (_, v) in aircraft::read_bdbs(missions)? {
        for (k, list) in aircraft::db_objects(&v) {
            db.entry(k).or_insert_with(Vec::new).extend(list);
        }
    }
    std::fs::create_dir_all(out)?;
    // Every `*_h.xfr` in order (group, plane folder, file); planes run in parallel, the files of one plane
    // folder in order (they write the same `aircraft.json`).
    type PlaneFiles = Vec<(usize, &'static str, PathBuf)>;
    let mut jobs: Vec<(String, PlaneFiles)> = Vec::new();
    let mut n = 0;
    for group in ["controllableplanes", "noncontrollableplanes"] {
        let mut dirs: Vec<_> = std::fs::read_dir(objects_root.join(group))?.flatten().map(|e| e.path()).collect();
        dirs.sort();
        for dir in dirs {
            let plane = name_lc(&dir)?;
            let mut files: Vec<_> = std::fs::read_dir(&dir)?.flatten().map(|e| e.path()).collect();
            files.sort();
            for src in files.into_iter().filter(|p| p.to_string_lossy().to_lowercase().ends_with("_h.xfr")) {
                let k = match jobs.iter().position(|j| j.0 == plane) {
                    Some(k) => k,
                    None => {
                        jobs.push((plane.clone(), Vec::new()));
                        jobs.len() - 1
                    }
                };
                jobs[k].1.push((n, group, src));
                n += 1;
            }
        }
    }
    let done = AtomicUsize::new(0);
    let results = par_map(&jobs, cancel, |(plane, files)| -> Result<Vec<(usize, serde_json::Value)>> {
        let mut entries = Vec::new();
        for (n, group, src) in files {
            let plane_out = out.join(plane);
            model(src, &plane_out, std::slice::from_ref(&objects_root), opts, pr)?;
            let m = Model::parse(&std::fs::read(src)?)?;
            let stem = stem_lc(src)?;
            let rel = format!("{group}/{plane}/{}", name_lc(src)?);
            let objs = db.get(&rel).cloned().unwrap_or_default();
            let d = aircraft::describe(&m, plane, &format!("{stem}.gltf"), &rel, &objs);
            std::fs::write(plane_out.join("aircraft.json"), serde_json::to_string_pretty(&d)?)?;
            entries.push((*n, serde_json::json!({ "model": format!("{plane}/{stem}.gltf"), "descriptor": format!("{plane}/aircraft.json"),
                "type": d["type"], "label": d["label"], "group": group })));
        }
        pr.fraction((done.fetch_add(1, Ordering::Relaxed) + 1) as f32 / jobs.len() as f32);
        Ok(entries)
    })?;
    // The index in the sequential order.
    let mut entries: Vec<(usize, &str, serde_json::Value)> = jobs
        .iter()
        .zip(results)
        .flat_map(|((plane, _), e)| e.into_iter().map(move |(n, v)| (n, plane.as_str(), v)))
        .collect();
    entries.sort_by_key(|e| e.0);
    let mut index = serde_json::Map::new();
    for (_, plane, v) in entries {
        index.insert(plane.to_string(), v);
    }
    std::fs::write(out.join("aircraft.json"), serde_json::to_string_pretty(&index)?)?;
    // The afterburner flame texture (FUN_004121e0; the hardware path uses the 32-bit TGA).
    let (img, _) = crate::gltf::load_texture(&objects_root.join("afterburn.tga"))?;
    opts.scaled(img).save(out.join("afterburn.png"))?;
    log!(pr, "aircraft: {} models -> {}", index.len(), out.display());
    Ok(())
}

/// Every model the object databases reference: `.bdb` Present records (`0x64a` model path under
/// `3dobjects`, e.g. `STATIONARY\FCTRY\FCTRY3_H.X`; objects point at them with `0x53c`).
/// Writes `<out>/<path>.gltf` and `<out>/objects.json` = {bdb: {present id: gltf path}}, plus the
/// decoy sprites `<out>/missflr.png` and `<out>/chaff.png` and the trail sprite `<out>/trail.png`.
pub fn objects(
    install: &Path,
    missions: &Path,
    out: &Path,
    opts: &Options,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<()> {
    let root = install.join("resource/3dobjects");
    // Every model the databases reference, first use first; models of one folder run in order on one worker
    // (an `.x` and an `.xfr` of the same name, LOD siblings and textures share the folder's files).
    let bdbs = crate::aircraft::read_bdbs(missions)?;
    let mut wanted: Vec<PathBuf> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for (_, data) in &bdbs {
        for (_, path) in crate::aircraft::present_models(data) {
            if !path.is_empty() && seen.insert(PathBuf::from(&path)) {
                wanted.push(PathBuf::from(path));
            }
        }
    }
    let convert_all = |rels: Vec<PathBuf>, lods: bool| -> Result<Vec<(PathBuf, bool)>> {
        let mut groups: Vec<(PathBuf, Vec<PathBuf>)> = Vec::new();
        for rel in rels {
            let dir = parent(&rel)?.to_path_buf();
            match groups.iter_mut().find(|g| g.0 == dir) {
                Some(g) => g.1.push(rel),
                None => groups.push((dir, vec![rel])),
            }
        }
        let n = AtomicUsize::new(0);
        let done = par_map(&groups, cancel, |(dir, rels)| -> Result<Vec<(PathBuf, bool)>> {
            let mut done = Vec::new();
            for rel in rels {
                let src = root.join(rel);
                let ok = match model(&src, &out.join(dir), std::slice::from_ref(&root), opts, pr) {
                    Ok(()) => true,
                    Err(e) => {
                        log!(pr, "  skipped {}: {e:#}", if lods { src.display() } else { rel.display() });
                        false
                    }
                };
                // The level-of-detail siblings the loader takes next to a `_h` model (`FUN_0041c120`: `_m`, `_l`),
                // drawn by OBJECT DETAIL's pixel-size rule (docs/front-end.md §12.4).
                if ok && lods {
                    for sib in lod_siblings(&src) {
                        if let Err(e) = model(&sib, &out.join(dir), std::slice::from_ref(&root), opts, pr) {
                            log!(pr, "  skipped {}: {e:#}", sib.display());
                        }
                    }
                }
                done.push((rel.clone(), ok));
            }
            pr.fraction((n.fetch_add(1, Ordering::Relaxed) + 1) as f32 / groups.len() as f32);
            Ok(done)
        })?;
        Ok(done.into_iter().flatten().collect())
    };
    let mut done: std::collections::HashMap<PathBuf, bool> = convert_all(wanted, true)?.into_iter().collect();
    let mut index = serde_json::Map::new();
    for (bdb, data) in &bdbs {
        let mut map = serde_json::Map::new();
        for (id, path) in crate::aircraft::present_models(data) {
            if path.is_empty() {
                continue;
            }
            let rel = PathBuf::from(path);
            let stem = rel.file_stem().with_context(|| format!("{}: no file name", rel.display()))?;
            let gltf = rel.with_extension("gltf").with_file_name(format!("{}.gltf", stem.to_string_lossy()));
            if done[&rel] {
                map.insert(id.to_string(), gltf.to_string_lossy().into());
            }
        }
        index.insert(format!("{bdb}.bdb"), serde_json::Value::Object(map));
    }
    // The briefings' 3D-model windows (brl type 2, docs/front-end.md §11) show any `_h` model with a description
    // (`<name>_h.rtf`), also the ones no mission places (f4e_h).
    let mut extra = Vec::new();
    for rtf in crate::walk_files(&root)? {
        let name = name_lc(&rtf)?;
        let Some(stem) = name.strip_suffix(".rtf").filter(|s| s.ends_with("_h")) else { continue };
        let rel = rtf.strip_prefix(&root)?.with_file_name(format!("{stem}.x"));
        // The same glTF as a converted `.xfr` (its frames: turret, launcher, radar…): keep that one.
        if done.contains_key(&rel)
            || done.contains_key(&rel.with_extension("xfr"))
            || !root.join(&rel).exists()
            || extra.contains(&rel)
        {
            continue;
        }
        extra.push(rel);
    }
    check(cancel)?;
    done.extend(convert_all(extra, false)?);
    std::fs::write(out.join("objects.json"), serde_json::to_string_pretty(&index)?)?;
    // The decoy sprites (docs/weapons.md §10): the burning flare (missFLR.tga, sprite 0xcd) and
    // the chaff pieces' texture (chaff.bmp, sprite 0xce).
    // The trail sprite (trail.tga, 4 frames of 64×32: missile and wingtip trails, docs/damage.md §6.4).
    for (src, dst) in [("missflr.tga", "missflr.png"), ("chaff.bmp", "chaff.png"), ("trail.tga", "trail.png")] {
        let (img, _) = crate::gltf::load_texture(&root.join(src))?;
        opts.scaled(img).save(out.join(dst))?;
    }
    // The textured sky's cloud layer (Cloud256_<rand()%6>.pal, docs/front-end.md §12.4).
    for i in 0..6 {
        let img = crate::gltf::load_pal(&root.join(format!("cloud256_{i}.pal")))?;
        opts.scaled(img).save(out.join(format!("cloud256_{i}.png")))?;
    }
    log!(pr, "objects: {} models -> {}", done.values().filter(|ok| **ok).count(), out.display());
    Ok(())
}

/// The existing `_m` / `_l` files next to a `*_h.x` / `*_h.xfr` model (any case, either extension).
fn lod_siblings(h: &Path) -> Vec<PathBuf> {
    let stem = h.file_stem().unwrap_or_default().to_string_lossy().to_lowercase();
    let Some(base) = stem.strip_suffix("_h") else { return vec![] };
    let Some(dir) = h.parent() else { return vec![] };
    let mut out = vec![];
    for lod in ["_m", "_l"] {
        let want = format!("{base}{lod}");
        if let Ok(rd) = std::fs::read_dir(dir) {
            let mut hits: Vec<PathBuf> = rd
                .flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.file_stem().is_some_and(|s| s.to_string_lossy().to_lowercase() == want)
                        && p.extension()
                            .is_some_and(|e| matches!(e.to_string_lossy().to_lowercase().as_str(), "x" | "xfr"))
                })
                .collect();
            hits.sort();
            out.extend(hits.into_iter().next());
        }
    }
    out
}

/// Cockpit images shared by all aircraft (MFD sprites, RWR symbols, map).
const SHARED_COCKPIT_IMAGES: &[&str] = &["mfds.bmp", "rwrsymb.bmp", "isr.bmp"];

/// `iaf-convert cockpit`: cockpit art (PNG) + layout (`cockpit.json`).
pub fn cockpit(
    install: &Path,
    name: &str,
    out: &Path,
    opts: &Options,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<()> {
    use crate::gltf::{COCKPIT_KEYS, load_texture_keyed};
    use iaf_formats::ini::Ini;
    let root = install.join("resource/cockpits");
    let dir = root.join(name.to_lowercase());
    std::fs::create_dir_all(out)?;

    // Layout: every section/key of cockpit.ibx, numbers as numbers.
    let ini = Ini::parse(&std::fs::read(dir.join("cockpit.ibx")).context("cockpit.ibx")?);
    let mut layout = serde_json::Map::new();
    for section in &ini.sections {
        let mut obj = serde_json::Map::new();
        for (k, v) in &section.entries {
            // GetPrivateProfileInt returns the caller's default for an empty value (`ClockCenterX =`: it reads the
            // string first and an empty one gives the default, Wine's GetPrivateProfileIntW): leave the key out,
            // so the reader's default (the exe's) applies.
            if v.trim().is_empty() {
                continue;
            }
            let value =
                v.parse::<f64>().map(serde_json::Value::from).unwrap_or_else(|_| serde_json::Value::from(v.as_str()));
            obj.entry(k.clone()).or_insert(value);
        }
        layout.insert(section.name.clone(), serde_json::Value::Object(obj));
    }
    let scale = if opts.upscale { upscale::FACTOR } else { 1 };
    layout.insert("image_scale".into(), scale.into());
    std::fs::write(out.join("cockpit.json"), serde_json::to_string_pretty(&layout)?)?;
    // The MFD TSD map (shared by every cockpit, docs/mfd.md §3).
    let map = iaf_formats::emf::parse(&std::fs::read(root.join("emf/map.emf")).context("emf/map.emf")?)?;
    std::fs::write(out.join("map.json"), serde_json::to_string(&emf_json(&map))?)?;

    let mut images: Vec<PathBuf> = std::fs::read_dir(&dir)?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "bmp"))
        .collect();
    images.extend(SHARED_COCKPIT_IMAGES.iter().map(|f| root.join(f)));
    par_map(&images, cancel, |src| -> Result<()> {
        let img = opts.scaled(load_texture_keyed(src, COCKPIT_KEYS)?.0);
        let file = format!("{}.png", stem_lc(src)?);
        img.save(out.join(&file))?;
        log!(pr, "  {file} {}x{}", img.width(), img.height());
        Ok(())
    })?;
    log!(pr, "{} -> {}", dir.display(), out.display());
    Ok(())
}

/// Files under `rel` (relative to resource/menu) from the base install, each replaced by the
/// pack's copy when the pack has one, plus pack-only files (a folder missing from either is
/// skipped). Returned as (relative path, file).
fn overlay_files(root: &Path, pack_root: Option<&Path>, rel: &str) -> Result<Vec<(PathBuf, PathBuf)>> {
    let mut map = std::collections::BTreeMap::new();
    for r in [Some(root), pack_root].into_iter().flatten() {
        let dir = r.join(rel);
        if !dir.is_dir() {
            continue;
        }
        for f in crate::walk_files(&dir)? {
            let key = f.strip_prefix(r)?.to_string_lossy().to_lowercase();
            map.insert(PathBuf::from(key), f);
        }
    }
    Ok(map.into_iter().collect())
}

/// Windows-1252, or Windows-1255 Hebrew for pack files. Stray NUL bytes are dropped.
fn decode_text(data: &[u8], hebrew: bool) -> String {
    let codepage = if hebrew { 1255 } else { 1252 };
    data.iter().filter(|&&c| c != 0).map(|&c| iaf_formats::rtf::decode_byte(c, codepage)).collect()
}

/// `iaf-convert menu`: front-end screens / lists (`menus.json`), strings, art and TrueType fonts; files in `pack` win.
pub fn menu(
    install: &Path,
    pack: Option<&Path>,
    out: &Path,
    opts: &Options,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<()> {
    use crate::gltf::{COCKPIT_KEYS, load_texture_keyed};
    use iaf_formats::menu::{self, MenuFile};
    use serde_json::json;
    let root = install.join("resource/menu");
    let pack_root = pack.map(|p| p.join("resource/menu"));
    let from_pack = |f: &Path| pack_root.as_ref().is_some_and(|p| f.starts_with(p));
    std::fs::create_dir_all(out)?;

    // Screens and lists.
    let mut menus = serde_json::Map::new();
    for (_, f) in &overlay_files(&root, pack_root.as_deref(), "dat")? {
        let key = stem_lc(f)?;
        let value = match menu::parse(&std::fs::read(f)?) {
            Some(MenuFile::Screen(s)) => json!({
                "type": "screen", "name": s.name, "title": s.title, "window": s.window, "flag": s.flag,
                "panels": s.panels.iter().map(|p| json!({
                    "side": p.side, "name": p.name, "pos": p.pos,
                    "buttons": p.buttons.iter().map(|b| json!({"label": b.label, "rect": b.rect, "kind": b.kind, "arg": b.arg})).collect::<Vec<_>>(),
                })).collect::<Vec<_>>(),
            }),
            Some(MenuFile::List(rows)) => json!({
                "type": "list",
                "rows": rows.iter().map(|r| json!({
                    "id": r.id, "flags": r.flags, "name": r.name, "rect": r.rect,
                    "title_box": r.title_box, "title_key": r.title_key.to_lowercase(),
                    "desc_box": r.desc_box, "desc_key": r.desc_key.to_lowercase(),
                })).collect::<Vec<_>>(),
            }),
            None => continue,
        };
        menus.insert(key, value);
    }
    std::fs::write(out.join("menus.json"), serde_json::to_string_pretty(&menus)?)?;

    // Strings (mission / jet titles and descriptions), Windows-1252.
    let mut strings = serde_json::Map::new();
    for (rel, f) in overlay_files(&root, pack_root.as_deref(), "txt")?
        .iter()
        .filter(|(r, _)| r.extension().is_some_and(|e| e == "trx"))
    {
        let mut text = decode_text(&std::fs::read(f)?, from_pack(f));
        // msgs.trx is indexed by line number (the message box, docs/front-end.md §3.3). A pack made
        // for an older version lacks the lines added later (v1.1 added line 56, docs/v1.1.md): keep
        // the install's lines past the pack's end.
        if from_pack(f)
            && rel.file_name().is_some_and(|n| n == "msgs.trx")
            && let Ok(base) = std::fs::read(root.join(rel))
        {
            let base = decode_text(&base, false);
            let (have, all): (Vec<&str>, Vec<&str>) =
                (text.trim_end().lines().collect(), base.trim_end().lines().collect());
            if all.len() > have.len() {
                text = [&have[..], &all[have.len()..]].concat().join("\r\n");
            }
        }
        strings.insert(stem_lc(f)?, text.trim().replace("\r\n", "\n").into());
    }
    std::fs::write(out.join("strings.json"), serde_json::to_string_pretty(&strings)?)?;

    // Fonts.
    for (rel, p) in overlay_files(&root, pack_root.as_deref(), "fnt")? {
        if rel.extension().is_some_and(|x| x == "ttf") {
            std::fs::copy(&p, out.join(name_lc(&rel)?))?;
        }
    }

    // Art.
    // Panel masks (1-bit, black = panel visible): the original draws mask AND, panel OR.
    let masks: Vec<image::GrayImage> = ["maskleft", "maskbottom1", "maskbottom2"]
        .iter()
        .filter_map(|m| image::open(root.join(format!("bmp/misc/{m}.bmp"))).ok().map(|i| i.to_luma8()))
        .collect();
    let img_root = out.join("img");
    let bmps: Vec<_> = overlay_files(&root, pack_root.as_deref(), "bmp")?
        .into_iter()
        .filter(|(r, _)| r.extension().is_some_and(|e| e == "bmp"))
        .collect();
    let saved = par_map(&bmps, cancel, |(rel, src)| -> Result<bool> {
        let dest = img_root.join(rel.strip_prefix("bmp")?.with_extension("png"));
        let mut img = match load_texture_keyed(src, COCKPIT_KEYS) {
            Ok((img, _)) => img,
            Err(e) => {
                log!(pr, "  skipped {}: {e:#}", src.display());
                return Ok(false);
            }
        };
        if rel.starts_with("bmp/palettes") {
            // The mask whose size is closest to the panel (bottom panels are a few pixels larger).
            if let Some(mask) = masks.iter().min_by_key(|m| {
                (m.width() as i64 - img.width() as i64).abs() + (m.height() as i64 - img.height() as i64).abs()
            }) && (mask.width() as i64 - img.width() as i64).abs() <= 4
                && (mask.height() as i64 - img.height() as i64).abs() <= 4
            {
                for (x, y, p) in img.enumerate_pixels_mut() {
                    let visible = if x < mask.width() && y < mask.height() {
                        mask.get_pixel(x, y)[0] < 128
                    } else {
                        p[0] as u32 + p[1] as u32 + p[2] as u32 > 0
                    };
                    if !visible {
                        p[3] = 0;
                    }
                }
            }
        }
        std::fs::create_dir_all(parent(&dest)?)?;
        opts.scaled(img).save(&dest)?;
        Ok(true)
    })?;
    let n = saved.iter().filter(|s| **s).count();
    // Sounds (button clicks, panel slides, menu music; wav/pref: the Preferences volume previews).
    std::fs::create_dir_all(out.join("wav"))?;
    for (rel, p) in overlay_files(&root, pack_root.as_deref(), "wav")? {
        let Some(dir) = rel.parent() else { continue };
        if rel.extension().is_some_and(|x| x == "wav") && (dir == Path::new("wav") || dir == Path::new("wav/pref")) {
            std::fs::create_dir_all(out.join(dir))?;
            std::fs::copy(&p, out.join(&rel))?;
        }
    }
    // TSD maps and overlays (vector, see docs/front-end.md §8).
    std::fs::create_dir_all(out.join("emf"))?;
    let mut emfs = 0;
    for (rel, p) in overlay_files(&root, pack_root.as_deref(), "emf")? {
        if !rel.extension().is_some_and(|x| x.eq_ignore_ascii_case("emf")) {
            continue;
        }
        let mf = iaf_formats::emf::parse(&std::fs::read(&p)?)?;
        let name = stem_lc(&rel)?;
        std::fs::write(out.join("emf").join(format!("{name}.json")), serde_json::to_string(&emf_json(&mf))?)?;
        emfs += 1;
    }
    std::fs::write(out.join("image_scale.txt"), if opts.upscale { "4" } else { "1" })?;
    log!(pr, "menu: {emfs} maps,");
    log!(pr, "menu: {} screens/lists, {} strings, {n} images -> {}", menus.len(), strings.len(), out.display());
    Ok(())
}

/// A metafile as JSON: frame size, then drawing ops with points normalised to the frame
/// (0..1, flat [x0, y0, x1, y1, ...]).
fn emf_json(mf: &iaf_formats::emf::Metafile) -> serde_json::Value {
    use iaf_formats::emf::Op;
    use serde_json::json;
    let flat = |pts: &[[f32; 2]]| {
        pts.iter().flat_map(|p| [(p[0] * 1e5).round() / 1e5, (p[1] * 1e5).round() / 1e5]).collect::<Vec<f32>>()
    };
    let pen = |p: &Option<iaf_formats::emf::Pen>| p.map(|p| json!({"color": p.color, "width": p.width}));
    let ops: Vec<_> = mf
        .ops
        .iter()
        .map(|op| match op {
            Op::Polygon { rings, pen: pn, brush, alternate } => json!({
                "t": "polygon", "rings": rings.iter().map(|r| flat(r)).collect::<Vec<_>>(),
                "pen": pen(pn), "brush": brush, "alternate": alternate,
            }),
            Op::Polyline { points, pen: pn } => {
                json!({"t": "polyline", "points": flat(points), "pen": pen(&Some(*pn))})
            }
            Op::Text { pos, text, font, color, align } => json!({
                "t": "text", "pos": pos, "text": text, "color": color, "align": align,
                "font": {"height": font.height, "weight": font.weight, "italic": font.italic, "face": font.face},
            }),
        })
        .collect();
    json!({
        "frame_mm": [(mf.frame[2] - mf.frame[0]) as f32 / 100.0, (mf.frame[3] - mf.frame[1]) as f32 / 100.0],
        "ops": ops,
    })
}

fn strip_bbcode(line: &str) -> String {
    let mut out = String::new();
    let mut tag = false;
    for c in line.chars() {
        match c {
            '[' => tag = true,
            ']' if tag => tag = false,
            _ if !tag => out.push(c),
            _ => {}
        }
    }
    out
}

/// `.brl` briefing links: 516-byte records `{name[256], i32 type, path[256]}` (Windows-1252 in
/// the original, Windows-1255 in the Hebrew pack). Type: 0 RTF, 1 unused, 2 3D model (.x),
/// 3 bitmap, 5 target (docs/front-end.md §6).
fn parse_brl(data: &[u8], hebrew: bool) -> Vec<(String, i32, String)> {
    let text = |b: &[u8]| decode_text(b.split(|&c| c == 0).next().unwrap_or(&[]), hebrew).trim().to_string();
    data.as_chunks::<516>()
        .0
        .iter()
        .map(|e| {
            (
                text(&e[..256]),
                i32::from_le_bytes(e[256..260].try_into().unwrap()),
                text(&e[260..]).replace('\\', "/").to_lowercase(),
            )
        })
        .filter(|(t, _, f)| !t.is_empty() || !f.is_empty())
        .collect()
}

/// `iaf-convert briefings`: briefing / lesson texts (English + the Hebrew pack), `.brl` entries and diagrams.
pub fn briefings(
    install: &Path,
    packs: &Path,
    out: &Path,
    opts: &Options,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<()> {
    use crate::gltf::load_texture;
    use iaf_formats::rtf::to_bbcode;
    use serde_json::json;
    let base = install.join("resource/brief");
    let he = packs.join("he/resource/brief");
    std::fs::create_dir_all(out)?;
    let read_rtf = |dir: &Path, name: &str| std::fs::read(dir.join(name)).ok().map(|d| to_bbcode(&d));
    let read_brl =
        |dir: &Path, name: &str, hebrew: bool| std::fs::read(dir.join(name)).ok().map(|d| parse_brl(&d, hebrew));
    let entries_json = |en: Option<Vec<(String, i32, String)>>, he: Option<Vec<(String, i32, String)>>| {
        let en = en.unwrap_or_default();
        let he = he.unwrap_or_default();
        en.iter()
            .enumerate()
            .map(|(i, (t, kind, f))| json!({"title": {"en": t, "he": he.get(i).map(|e| e.0.clone())}, "type": kind, "file": f}))
            .collect::<Vec<_>>()
    };
    let mut doc = serde_json::Map::new();
    for (sub, key) in [("txt", "missions"), ("text", "lessons")] {
        let mut map = serde_json::Map::new();
        let mut names: Vec<String> = std::fs::read_dir(base.join(sub))?
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_lowercase())
            .filter(|n| n.ends_with(".rtf") && !n.starts_with("~$"))
            .collect();
        names.sort();
        for name in names {
            let stem = name.trim_end_matches(".rtf").to_string();
            let brl = format!("{stem}.brl");
            let (text_en, text_he) = (read_rtf(&base.join(sub), &name), read_rtf(&he.join(sub), &name));
            // The mission name as written in the briefing ("Mission: …"; Hebrew pack: "משימה: …" / "מבצע: …").
            let title = |text: &Option<String>, labels: &[&str]| {
                text.as_ref().and_then(|t| {
                    t.lines().map(strip_bbcode).find_map(|l| {
                        labels.iter().find_map(|label| l.trim().strip_prefix(label).map(|n| n.trim().to_string()))
                    })
                })
            };
            map.insert(stem.clone(), json!({
                "title": {"en": title(&text_en, &["Mission:"]), "he": title(&text_he, &["משימה:", "מבצע:"])},
                "text": {"en": text_en, "he": text_he},
                "entries": entries_json(read_brl(&base.join(sub), &brl, false), read_brl(&he.join(sub), &brl, true)),
            }));
        }
        doc.insert(key.into(), serde_json::Value::Object(map));
    }
    // The 3D-model windows' descriptions (`<model>_h.rtf`, English only) and `.cp` view limits ("dist height", §11),
    // keyed by the model path as the .brl writes it, without the extension: "3dobjects/…/mig21/mig21_h".
    let objects = install.join("resource/3dobjects");
    let mut models = serde_json::Map::new();
    for rtf in crate::walk_files(&objects)? {
        let rel = rtf.strip_prefix(install.join("resource"))?.to_string_lossy().replace('\\', "/").to_lowercase();
        let Some(key) = rel.strip_suffix(".rtf").filter(|k| k.ends_with("_h")) else { continue };
        let cp = std::fs::read_to_string(rtf.with_extension("cp")).ok().and_then(|t| {
            let v: Vec<f64> = t.split_whitespace().filter_map(|w| w.parse().ok()).collect();
            (v.len() >= 2).then(|| json!([v[0], v[1]]))
        });
        models.insert(
            key.to_string(),
            json!({"text": {"en": std::fs::read(&rtf).ok().map(|d| to_bbcode(&d))}, "cp": cp}),
        );
    }
    doc.insert("models".into(), serde_json::Value::Object(models));
    std::fs::write(out.join("briefings.json"), serde_json::to_string_pretty(&doc)?)?;

    // Diagrams: original, and the Hebrew pack's relabelled versions.
    let mut diagrams = Vec::new();
    for (src_dir, dest) in [(base.join("bmp"), out.join("img")), (he.join("bmp"), out.join("img_he"))] {
        let Ok(rd) = std::fs::read_dir(&src_dir) else { continue };
        std::fs::create_dir_all(&dest)?;
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().is_some_and(|x| x.eq_ignore_ascii_case("bmp")) {
                diagrams.push((p, dest.clone()));
            }
        }
    }
    let saved = par_map(&diagrams, cancel, |(p, dest)| -> Result<bool> {
        let Ok((img, _)) = load_texture(p) else { return Ok(false) };
        opts.scaled(img).save(dest.join(format!("{}.png", stem_lc(p)?)))?;
        Ok(true)
    })?;
    let n = saved.iter().filter(|s| **s).count();
    log!(
        pr,
        "briefings: {} missions, {} lessons, {n} diagrams -> {}",
        doc["missions"].as_object().map_or(0, |m| m.len()),
        doc["lessons"].as_object().map_or(0, |m| m.len()),
        out.display()
    );
    Ok(())
}

/// `iaf-convert reference`: the Reference screen's records, descriptions, models and pictures (`reference.json`, `img/`).
pub fn reference(install: &Path, out: &Path, opts: &Options, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    use serde_json::json;
    let res = install.join("resource");
    let refs = iaf_formats::refs::parse(&std::fs::read(res.join("ref/refers.ref"))?)?;
    std::fs::create_dir_all(out.join("img"))?;
    let mut dirs: Vec<String> = refs.iter().map(|r| r.dir.to_lowercase()).collect();
    dirs.sort();
    dirs.dedup();
    par_map(&dirs, cancel, |dir| -> Result<()> {
        if let Ok(img) = image::open(res.join("ref").join(dir).join(format!("{dir}_0.bmp"))) {
            opts.scaled(img.to_rgba8()).save(out.join(format!("img/{dir}.png")))?;
        }
        Ok(())
    })?;
    let mut records = Vec::new();
    for r in &refs {
        let dir = r.dir.to_lowercase();
        let base = res.join("ref").join(&dir);
        let text = std::fs::read(base.join(format!("{dir}_0.rtf"))).ok().map(|d| iaf_formats::rtf::to_bbcode(&d));
        // "\ControllablePlanes\F16\F16_h.x" -> "controllableplanes/f16/f16_h" (the converted glTF and the .cp beside the .x).
        let model = r.model.replace('\\', "/").trim_start_matches('/').to_lowercase();
        let model = model.strip_suffix(".x").unwrap_or(&model).to_string();
        let cp = std::fs::read_to_string(res.join("3dobjects").join(format!("{model}.cp"))).ok().and_then(|t| {
            let v: Vec<f64> = t.split_whitespace().filter_map(|w| w.parse().ok()).collect();
            (v.len() >= 2).then(|| json!([v[0], v[1]]))
        });
        records.push(json!({"name": r.name, "dir": dir, "model": format!("{model}.gltf"), "idf": r.idf,
            "enemy": r.enemy, "category": r.category, "text": text, "cp": cp}));
    }
    std::fs::write(out.join("reference.json"), serde_json::to_string_pretty(&json!({"records": records}))?)?;
    log!(pr, "reference: {} records -> {}", records.len(), out.display());
    Ok(())
}

/// Raster fonts → BMFont text format + atlas (Godot: `FontFile.load_bitmap_font`). Glyphs are
/// kept at their original pixel size; the engine scales them.
pub fn fonts(install: &Path, out: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    use iaf_formats::winfnt;
    std::fs::create_dir_all(out)?;
    for name in ["hud", "mfd", "key"] {
        check(cancel)?;
        let font = winfnt::parse(&std::fs::read(install.join(format!("resource/menu/fnt/{name}.fnt")))?)?;
        let glyphs: Vec<_> = font.glyphs.iter().filter(|g| g.width > 0).collect();
        // Simple row packing into a 256-wide atlas with 1 px padding.
        let (atlas_w, h) = (256u32, font.height);
        let mut x = 0u32;
        let mut y = 0u32;
        let mut places = Vec::new();
        for g in &glyphs {
            if x + g.width + 1 > atlas_w {
                x = 0;
                y += h + 1;
            }
            places.push((x, y));
            x += g.width + 1;
        }
        let atlas_h = (y + h + 1).next_power_of_two();
        let mut img = image::RgbaImage::new(atlas_w, atlas_h);
        let mut desc = format!(
            "info face=\"{}\" size={} bold=0 italic=0 charset=\"\" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1\n\
             common lineHeight={} base={} scaleW={atlas_w} scaleH={atlas_h} pages=1 packed=0\n\
             page id=0 file=\"{name}.png\"\nchars count={}\n",
            font.face,
            h,
            h,
            font.ascent,
            glyphs.len()
        );
        for (g, &(gx, gy)) in glyphs.iter().zip(&places) {
            for py in 0..h {
                for px in 0..g.width {
                    let v = g.pixels[(py * g.width + px) as usize];
                    img.put_pixel(gx + px, gy + py, image::Rgba([255, 255, 255, v]));
                }
            }
            // The glyph id is the font's Windows-1252 byte code, kept as is (HUD / MFD text is ASCII).
            desc.push_str(&format!(
                "char id={} x={gx} y={gy} width={} height={h} xoffset=0 yoffset=0 xadvance={} page=0 chnl=15\n",
                g.code, g.width, g.width
            ));
        }
        img.save(out.join(format!("{name}.png")))?;
        std::fs::write(out.join(format!("{name}.fnt")), desc)?;
        log!(pr, "{name}: {} glyphs, {}px tall ({})", glyphs.len(), h, font.face);
    }
    Ok(())
}

/// `iaf-convert missions`: every `.mis` and `.bdb` → JSON, plus the mission list (`missionlist.json`).
pub fn missions(install: &Path, out: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    use crate::mis;
    let dir = install.join("resource/missions");
    std::fs::create_dir_all(out)?;
    let (mut ok, mut failed) = (0, Vec::new());
    let mut bdb_version = 9;
    let mut entries: Vec<_> = std::fs::read_dir(&dir)?.flatten().map(|e| e.path()).collect();
    entries.sort();
    for p in &entries {
        check(cancel)?;
        let name = name_lc(p)?;
        if !name.ends_with(".mis") {
            continue;
        }
        match mis::parse_mission(&std::fs::read(p)?) {
            Ok(v) => {
                bdb_version = v["version"].as_i64().unwrap_or(9) as i32;
                std::fs::write(out.join(name.replace(".mis", ".json")), serde_json::to_string(&v)?)?;
                ok += 1;
            }
            Err(e) => failed.push(format!("{name}: {e:#}")),
        }
    }
    for p in entries.iter().filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("bdb"))) {
        let v = mis::parse_bdb(&std::fs::read(p)?, bdb_version)?;
        let name = name_lc(p)?.replace(".bdb", ".bdb.json");
        std::fs::write(out.join(name), serde_json::to_string(&v)?)?;
    }
    // Menu mission id -> [main mission, base missions…] (lower-cased file stems).
    let list = iaf_formats::ini::Ini::parse(&std::fs::read(dir.join("missionlist.ibx"))?);
    let mut map = serde_json::Map::new();
    for s in &list.sections {
        let files: Vec<String> = s
            .entries
            .iter()
            .filter(|(k, _)| k.to_uppercase().starts_with("MISSION"))
            .map(|(_, v)| v.to_lowercase().trim_end_matches(".mis").to_string())
            .collect();
        if !files.is_empty() {
            map.insert(s.name.clone(), serde_json::json!(files));
        }
    }
    std::fs::write(out.join("missionlist.json"), serde_json::to_string_pretty(&map)?)?;
    log!(pr, "missions: {ok} converted, {} failed, {} ids -> {}", failed.len(), map.len(), out.display());
    for f in failed {
        log!(pr, "  {f}");
    }
    Ok(())
}

/// Key table (docs/front-end.md §12.7, docs/controls.md): 117 records of 9 dwords in `.data` — press
/// command, press p1, p2, release command, release p1, p2, key (DIK scancode | modifier << 16),
/// joystick button (−1 none), shown in the Controls list. Record i is `keys.trx` line i (both are
/// indexed by the same i in `FUN_004e0b80`'s "pressed %s" trace). The records are byte-identical in
/// v1.0 and v1.1 (docs/v1.1.md); only their addresses moved, so both exes are read.
const KEY_RECORDS: usize = 117;

/// Where the key table and its strings are in one version of iafjets.exe.
struct KeyAddrs {
    version: &'static str,
    table: u32,
    /// `FUN_005122b0`: DIK scancode -> the address of its name string (other codes: no name).
    dik_names: &'static [(u32, u32)],
    /// `FUN_005121e0`: modifier bits (tested in this order) -> prefix string address.
    modifiers: [(u32, u32); 4],
    /// `FUN_00512a90`: joystick button n (0-based) is shown as this format with n + 1.
    button_format: u32,
}

const KEYS_V11: KeyAddrs = KeyAddrs {
    version: "v1.1",
    table: 0x64c3c8,
    dik_names: &[
        (0x01, 0x658ec4),
        (0x02, 0x64da60),
        (0x03, 0x658ec0),
        (0x04, 0x658ebc),
        (0x05, 0x658eb8),
        (0x06, 0x658eb4),
        (0x07, 0x658eb0),
        (0x08, 0x658eac),
        (0x09, 0x658ea8),
        (0x0a, 0x658ea4),
        (0x0b, 0x64f7b4),
        (0x0c, 0x658ea0),
        (0x0d, 0x658e9c),
        (0x0e, 0x658e90),
        (0x0f, 0x658e8c),
        (0x10, 0x658e88),
        (0x11, 0x658e84),
        (0x12, 0x658e80),
        (0x13, 0x658e7c),
        (0x14, 0x658e78),
        (0x15, 0x658e74),
        (0x16, 0x658e70),
        (0x17, 0x658e6c),
        (0x18, 0x658e68),
        (0x19, 0x658e64),
        (0x1a, 0x658e60),
        (0x1b, 0x658e5c),
        (0x1c, 0x658e54),
        (0x1d, 0x658e4c),
        (0x1e, 0x658e48),
        (0x1f, 0x658e44),
        (0x20, 0x658e40),
        (0x21, 0x658e3c),
        (0x22, 0x658e38),
        (0x23, 0x658e34),
        (0x24, 0x658e30),
        (0x25, 0x658e2c),
        (0x26, 0x658e28),
        (0x27, 0x658e24),
        (0x28, 0x658e20),
        (0x29, 0x658e1c),
        (0x2a, 0x658e14),
        (0x2b, 0x628140),
        (0x2c, 0x658e10),
        (0x2d, 0x658e0c),
        (0x2e, 0x658e08),
        (0x2f, 0x658e04),
        (0x30, 0x658e00),
        (0x31, 0x658dfc),
        (0x32, 0x658df8),
        (0x33, 0x63fd54),
        (0x34, 0x658df4),
        (0x35, 0x658df0),
        (0x36, 0x658de8),
        (0x37, 0x658ddc),
        (0x38, 0x658dd4),
        (0x39, 0x658dcc),
        (0x3a, 0x658dc0),
        (0x3b, 0x658dbc),
        (0x3c, 0x658db8),
        (0x3d, 0x658db4),
        (0x3e, 0x656f74),
        (0x3f, 0x658db0),
        (0x40, 0x658dac),
        (0x41, 0x658da8),
        (0x42, 0x658da4),
        (0x43, 0x658da0),
        (0x44, 0x658d9c),
        (0x45, 0x658d94),
        (0x46, 0x658d88),
        (0x47, 0x658d7c),
        (0x48, 0x658d70),
        (0x49, 0x658d64),
        (0x4a, 0x658d58),
        (0x4b, 0x658d4c),
        (0x4c, 0x658d40),
        (0x4d, 0x658d34),
        (0x4e, 0x658d28),
        (0x4f, 0x658d1c),
        (0x50, 0x658d10),
        (0x51, 0x658d04),
        (0x52, 0x658cf8),
        (0x53, 0x658cf0),
        (0x56, 0x658ce8),
        (0x57, 0x658ce4),
        (0x58, 0x658ce0),
        (0x64, 0x658cdc),
        (0x65, 0x658cd8),
        (0x66, 0x65583c),
        (0x70, 0x658cd0),
        (0x79, 0x658cc8),
        (0x7b, 0x658cbc),
        (0x7d, 0x658cb8),
        (0x8d, 0x658cac),
        (0x90, 0x658ca0),
        (0x91, 0x658c9c),
        (0x92, 0x658c94),
        (0x93, 0x658c88),
        (0x94, 0x658c80),
        (0x95, 0x658c78),
        (0x96, 0x658c74),
        (0x97, 0x658c6c),
        (0x9c, 0x658c64),
        (0x9d, 0x658c5c),
        (0xb3, 0x658c4c),
        (0xb5, 0x658c40),
        (0xb7, 0x658c38),
        (0xb8, 0x658c30),
        (0xc7, 0x658c28),
        (0xc8, 0x658c24),
        (0xc9, 0x658c1c),
        (0xcb, 0x658c14),
        (0xcd, 0x658c0c),
        (0xcf, 0x658c08),
        (0xd0, 0x658c00),
        (0xd1, 0x658bf4),
        (0xd2, 0x658bec),
        (0xd3, 0x658be4),
        (0xdb, 0x658bdc),
        (0xdc, 0x658bd4),
        (0xdd, 0x658bcc),
    ],
    modifiers: [(0x11, 0x658ba8), (0x22, 0x658bb0), (0x44, 0x658bbc), (0x88, 0x658bc4)],
    button_format: 0x658ec8,
};

// v1.0 key-name addresses (the unpatched exe; the v1.1 ones above are these moved, docs/v1.1.md).
const KEYS_V10: KeyAddrs = KeyAddrs {
    version: "v1.0",
    table: 0x647ff8,
    dik_names: &[
        (0x01, 0x654af8),
        (0x02, 0x649690),
        (0x03, 0x654af4),
        (0x04, 0x654af0),
        (0x05, 0x654aec),
        (0x06, 0x654ae8),
        (0x07, 0x654ae4),
        (0x08, 0x654ae0),
        (0x09, 0x654adc),
        (0x0a, 0x654ad8),
        (0x0b, 0x654ad4),
        (0x0c, 0x654ad0),
        (0x0d, 0x654acc),
        (0x0e, 0x654ac0),
        (0x0f, 0x654abc),
        (0x10, 0x654ab8),
        (0x11, 0x654ab4),
        (0x12, 0x654ab0),
        (0x13, 0x654aac),
        (0x14, 0x654aa8),
        (0x15, 0x654aa4),
        (0x16, 0x654aa0),
        (0x17, 0x654a9c),
        (0x18, 0x654a98),
        (0x19, 0x654a94),
        (0x1a, 0x654a90),
        (0x1b, 0x654a8c),
        (0x1c, 0x654a84),
        (0x1d, 0x654a7c),
        (0x1e, 0x654a78),
        (0x1f, 0x654a74),
        (0x20, 0x654a70),
        (0x21, 0x654a6c),
        (0x22, 0x654a68),
        (0x23, 0x654a64),
        (0x24, 0x654a60),
        (0x25, 0x654a5c),
        (0x26, 0x654a58),
        (0x27, 0x654a54),
        (0x28, 0x654a50),
        (0x29, 0x654a4c),
        (0x2a, 0x654a44),
        (0x2b, 0x6240d0),
        (0x2c, 0x654a40),
        (0x2d, 0x654a3c),
        (0x2e, 0x654a38),
        (0x2f, 0x654a34),
        (0x30, 0x654a30),
        (0x31, 0x654a2c),
        (0x32, 0x654a28),
        (0x33, 0x63bb14),
        (0x34, 0x654a24),
        (0x35, 0x654a20),
        (0x36, 0x654a18),
        (0x37, 0x654a0c),
        (0x38, 0x654a04),
        (0x39, 0x6549fc),
        (0x3a, 0x6549f0),
        (0x3b, 0x6549ec),
        (0x3c, 0x6549e8),
        (0x3d, 0x6549e4),
        (0x3e, 0x652ba4),
        (0x3f, 0x6549e0),
        (0x40, 0x6549dc),
        (0x41, 0x6549d8),
        (0x42, 0x6549d4),
        (0x43, 0x6549d0),
        (0x44, 0x6549cc),
        (0x45, 0x6549c4),
        (0x46, 0x6549b8),
        (0x47, 0x6549ac),
        (0x48, 0x6549a0),
        (0x49, 0x654994),
        (0x4a, 0x654988),
        (0x4b, 0x65497c),
        (0x4c, 0x654970),
        (0x4d, 0x654964),
        (0x4e, 0x654958),
        (0x4f, 0x65494c),
        (0x50, 0x654940),
        (0x51, 0x654934),
        (0x52, 0x654928),
        (0x53, 0x654920),
        (0x56, 0x654918),
        (0x57, 0x654914),
        (0x58, 0x654910),
        (0x64, 0x65490c),
        (0x65, 0x654908),
        (0x66, 0x65146c),
        (0x70, 0x654900),
        (0x79, 0x6548f8),
        (0x7b, 0x6548ec),
        (0x7d, 0x6548e8),
        (0x8d, 0x6548dc),
        (0x90, 0x6548d0),
        (0x91, 0x6548cc),
        (0x92, 0x6548c4),
        (0x93, 0x6548b8),
        (0x94, 0x6548b0),
        (0x95, 0x6548a8),
        (0x96, 0x6548a4),
        (0x97, 0x65489c),
        (0x9c, 0x654894),
        (0x9d, 0x65488c),
        (0xb3, 0x65487c),
        (0xb5, 0x654870),
        (0xb7, 0x654868),
        (0xb8, 0x654860),
        (0xc7, 0x654858),
        (0xc8, 0x654854),
        (0xc9, 0x65484c),
        (0xcb, 0x654844),
        (0xcd, 0x65483c),
        (0xcf, 0x654838),
        (0xd0, 0x654830),
        (0xd1, 0x654824),
        (0xd2, 0x65481c),
        (0xd3, 0x654814),
        (0xdb, 0x65480c),
        (0xdc, 0x654804),
        (0xdd, 0x6547fc),
    ],
    modifiers: [(0x11, 0x6547d8), (0x22, 0x6547e0), (0x44, 0x6547ec), (0x88, 0x6547f4)],
    button_format: 0x654afc,
};

/// The key table of `exe` (told apart by its PE link time, `crate::exe`), checked before use: the
/// names of Esc / Ctrl / joystick buttons and every record's fields must read as expected.
fn key_addrs(exe: &PeImage) -> Result<&'static KeyAddrs> {
    let k = match exe.release()? {
        Release::V10 => &KEYS_V10,
        Release::V11 => &KEYS_V11,
    };
    let esc = k.dik_names.iter().find(|(d, _)| *d == 1).map(|&(_, va)| va).context("no Esc key name")?;
    if exe.cstr(esc)? != b"Esc"
        || exe.cstr(k.modifiers[0].1)? != b"Ctrl + "
        || exe.cstr(k.button_format)? != b"Button %d"
    {
        bail!("iafjets.exe {}: the key-name strings are not where expected", k.version);
    }
    for i in 0..KEY_RECORDS {
        let at = |j: usize| exe.i32_at(k.table + (i * 36 + j * 4) as u32);
        let (key, button, shown) = (at(6)? as u32, at(7)?, at(8)?);
        if key >> 24 != 0 || key & 0xff00 != 0 || button < -1 || !(0..=1).contains(&shown) {
            bail!("iafjets.exe {}: key record {i} does not look like a key record", k.version);
        }
    }
    Ok(k)
}

/// `iaf-convert keys`: the exe's default key table with the `keys.trx` labels (+ the Hebrew pack's), key names.
pub fn keys(install: &Path, packs: &Path, out: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    check(cancel)?;
    use serde_json::json;
    let exe = PeImage::load(&install.join("iafjets.exe"))?;
    let k = key_addrs(&exe)?;
    let lines = |path: &Path, hebrew: bool| -> Option<Vec<String>> {
        let data = std::fs::read(path).ok()?;
        Some(decode_text(&data, hebrew).lines().map(|l| l.trim().to_string()).collect())
    };
    let labels = lines(&install.join("resource/menu/txt/keys.trx"), false).context("keys.trx missing")?;
    // The Hebrew packs carry no keys.trx so far; use it when a pack has one.
    let labels_he = lines(&packs.join("he/resource/menu/txt/keys.trx"), true);
    let mut names = serde_json::Map::new();
    for &(dik, va) in k.dik_names {
        names.insert(dik.to_string(), decode_text(exe.cstr(va)?, false).into());
    }
    let mut modifiers = Vec::new();
    for &(bits, va) in &k.modifiers {
        modifiers.push(json!({"bits": bits, "prefix": decode_text(exe.cstr(va)?, false)}));
    }
    let mut records = Vec::new();
    for i in 0..KEY_RECORDS {
        let f = (0..9).map(|j| exe.i32_at(k.table + (i * 36 + j * 4) as u32)).collect::<Result<Vec<_>>>()?;
        let key = f[6] as u32;
        records.push(json!({
            "index": i,
            "label": labels.get(i).cloned().unwrap_or_default(),
            "label_he": labels_he.as_ref().and_then(|l| l.get(i).cloned()),
            "press": [f[0], f[1], f[2]],
            "release": [f[3], f[4], f[5]],
            "dik": key & 0xffff,
            "modifiers": (key >> 16) & 0xff,
            "joystick": f[7],
            "shown": f[8] != 0,
        }));
    }
    let doc = json!({
        "source": format!("iafjets.exe {} default key table {:#x}, {KEY_RECORDS} records x 36 bytes", k.version, k.table),
        "records": records,
        "key_names": names,
        "modifiers": modifiers,
        "button_format": decode_text(exe.cstr(k.button_format)?, false),
    });
    if let Some(dir) = out.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(out, serde_json::to_string_pretty(&doc)?)?;
    log!(pr, "keys ({}): {KEY_RECORDS} records, {} key names -> {}", k.version, k.dik_names.len(), out.display());
    Ok(())
}

/// The game's icon from iafjets.exe (the largest RT_ICON), 4× Lanczos, as PNG (for the desktop launcher).
pub fn icon(install: &Path, out: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    check(cancel)?;
    let exe = crate::exe::PeImage::load(&install.join("iafjets.exe"))?;
    let icon = exe.icons()?.into_iter().next().context("no icon in iafjets.exe")?;
    let big =
        image::imageops::resize(&icon, icon.width() * 4, icon.height() * 4, image::imageops::FilterType::Lanczos3);
    big.save(out)?;
    log!(pr, "icon {}x{} -> {}", icon.width(), icon.height(), out.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Both real exes (when present: v1.0 in `assets/v1.0` or an unpatched `assets/install`, v1.1 in
    /// `assets/v1.1`) pass the key-table checks and hold the same records and names.
    #[test]
    fn key_table_in_both_releases() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        let read = |exe: &PeImage| -> Vec<Vec<u8>> {
            let k = key_addrs(exe).unwrap();
            let mut out: Vec<Vec<u8>> = (0..KEY_RECORDS * 9)
                .map(|n| exe.i32_at(k.table + 4 * n as u32).unwrap().to_le_bytes().to_vec())
                .collect();
            out.extend(k.dik_names.iter().map(|&(_, va)| exe.cstr(va).unwrap().to_vec()));
            out
        };
        let mut tables = std::collections::HashMap::new();
        for p in ["v1.0/iafjets.exe", "install/iafjets.exe", "v1.1/iafjets.exe"] {
            if let Ok(exe) = PeImage::load(&root.join(p)) {
                tables.insert(exe.release().unwrap(), read(&exe));
            }
        }
        match (tables.get(&Release::V10), tables.get(&Release::V11)) {
            (Some(a), Some(b)) => assert_eq!(a, b),
            _ => eprintln!("skipped: needs both the v1.0 and the v1.1 iafjets.exe under assets/"),
        }
    }
}
