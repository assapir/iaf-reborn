//! Convert original IAF assets into engine-friendly formats.
//!
//! `iaf-convert model <file.x|file.xfr> <out-dir>` — one model → glTF + PNG textures.
//! `iaf-convert planes <install-dir> <out-dir>` — every controllable plane (`*_h.xfr`).
//!
//! `iaf-convert cockpit <install-dir> <cockpit> <out-dir>` — cockpit art (PNG) + layout (`cockpit.json`).
//! `iaf-convert briefings <install-dir> <packs-dir> <out-dir>` — briefing/lesson texts (RTF → BBCode,
//! English + Hebrew pack), `.brl` entry lists and diagrams (`briefings.json`, `img/`, `img_he/`).
//! `iaf-convert missions <install-dir> <out-dir>` — every `.mis` and the `.bdb` → JSON, plus the
//! mission list (menu id → mission + base-mission files).
//! `iaf-convert fonts <install-dir> <out-dir>` — HUD/MFD/key raster fonts → BMFont (`.fnt` + `.png`).
//! `iaf-convert menu <install-dir> <out-dir> [--pack <pack-dir>]` — front-end screens/lists
//! (`menus.json`), strings (`strings.json`), art (`img/…png`) and TrueType fonts; with `--pack`,
//! files present in the pack (e.g. assets/packs/he, Hebrew art/strings in Windows-1255) win.
//!
//! `--upscale` resamples textures 4× (Lanczos). `--upscale-ai` uses the experimental AI
//! upscaler instead (needs `realesrgan-ncnn-vulkan`; not recommended: it redraws text).
//! `--smooth` rounds the low-poly geometry (smooth normals + Phong tessellation).

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use iaf_formats::model::Model;
use iaf_tools::gltf::write_model;
use iaf_tools::upscale::{self, Upscaler};

struct Options {
    upscaler: Option<Upscaler>,
    smooth: bool,
}

fn convert(src: &Path, out_dir: &Path, extra_texture_dirs: &[PathBuf], opts: &Options) -> Result<()> {
    let model = Model::parse(&std::fs::read(src)?).with_context(|| format!("parsing {}", src.display()))?;
    let name = src.file_stem().unwrap().to_string_lossy().to_lowercase();
    let mut dirs = vec![src.parent().unwrap().to_path_buf()];
    dirs.extend_from_slice(extra_texture_dirs);
    let warnings = write_model(&model, &name, &dirs, out_dir, opts.upscaler.as_ref(), opts.smooth)?;
    println!("{} -> {}/{name}.gltf", src.display(), out_dir.display());
    for w in warnings {
        println!("  warning: {w}");
    }
    Ok(())
}

fn main() -> Result<()> {
    let mut args: Vec<String> = std::env::args().collect();
    let mut flag = |name: &str| args.iter().position(|a| a == name).map(|i| args.remove(i)).is_some();
    let upscale_ai = flag("--upscale-ai");
    let upscale = flag("--upscale");
    let smooth = flag("--smooth");
    let upscaler = if upscale_ai {
        Some(Upscaler::find_ai(upscale::MODEL_PAINTED)?)
    } else if upscale {
        Some(Upscaler::Lanczos)
    } else {
        None
    };
    let opts = Options { upscaler, smooth };
    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [_, "model", src, out] => convert(Path::new(src), Path::new(out), &[], &opts),
        [_, "planes", install, out] => {
            let planes = Path::new(install).join("resource/3dobjects/controllableplanes");
            let shared = vec![Path::new(install).join("resource/3dobjects")];
            let mut dirs: Vec<_> = std::fs::read_dir(&planes)?.flatten().map(|e| e.path()).collect();
            dirs.sort();
            for dir in dirs {
                let plane = dir.file_name().unwrap().to_string_lossy().to_string();
                for entry in std::fs::read_dir(&dir)?.flatten() {
                    let p = entry.path();
                    if p.to_string_lossy().ends_with("_h.xfr") {
                        convert(&p, &Path::new(out).join(&plane), &shared, &opts)?;
                    }
                }
            }
            Ok(())
        }
        [_, "missions", install, out] => convert_missions(Path::new(install), Path::new(out)),
        [_, "objects", install, missions, out] => convert_objects(Path::new(install), Path::new(missions), Path::new(out), &opts),
        [_, "fonts", install, out] => convert_fonts(Path::new(install), Path::new(out)),
        [_, "briefings", install, packs, out] => convert_briefings(Path::new(install), Path::new(packs), Path::new(out), &opts),
        [_, "menu", install, out] => convert_menu(Path::new(install), None, Path::new(out), &opts),
        [_, "menu", install, out, "--pack", pack] => convert_menu(Path::new(install), Some(Path::new(pack)), Path::new(out), &opts),
        [_, "cockpit", install, name, out] => convert_cockpit(Path::new(install), name, Path::new(out), &opts),
        _ => bail!("usage: iaf-convert [--upscale] [--smooth] model <file.x|file.xfr> <out-dir>\n       iaf-convert [--upscale] [--smooth] planes <install-dir> <out-dir>\n       iaf-convert [--upscale] cockpit <install-dir> <cockpit> <out-dir>\n       iaf-convert [--upscale] menu <install-dir> <out-dir> [--pack <pack-dir>]\n       iaf-convert [--upscale] briefings <install-dir> <packs-dir> <out-dir>"),
    }
}

/// Every model the object databases reference: `.bdb` Present records (`0x64a` model path under
/// `3dobjects`, e.g. `STATIONARY\FCTRY\FCTRY3_H.X`; objects point at them with `0x53c`).
/// Writes `<out>/<path>.gltf` and `<out>/objects.json` = {bdb: {present id: gltf path}}.
fn convert_objects(install: &Path, missions: &Path, out: &Path, opts: &Options) -> Result<()> {
    let root = install.join("resource/3dobjects");
    let mut index = serde_json::Map::new();
    let mut done = std::collections::HashMap::new();
    for entry in std::fs::read_dir(missions)?.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let Some(bdb) = name.strip_suffix(".bdb.json") else { continue };
        let data: serde_json::Value = serde_json::from_slice(&std::fs::read(entry.path())?)?;
        let mut map = serde_json::Map::new();
        for item in data["present"]["items"].as_array().into_iter().flatten() {
            let (Some(id), Some(path)) = (item["0x1e"].as_i64(), item["0x64a"].as_str()) else { continue };
            if path.is_empty() {
                continue;
            }
            let rel = PathBuf::from(path.replace('\\', "/").to_lowercase());
            let gltf = rel.with_extension("gltf").with_file_name(format!(
                "{}.gltf",
                rel.file_stem().unwrap().to_string_lossy()
            ));
            if !done.contains_key(&rel) {
                let src = root.join(&rel);
                let ok = match convert(&src, &out.join(rel.parent().unwrap()), &[root.clone()], opts) {
                    Ok(()) => true,
                    Err(e) => {
                        println!("  skipped {}: {e:#}", src.display());
                        false
                    }
                };
                done.insert(rel.clone(), ok);
            }
            if done[&rel] {
                map.insert(id.to_string(), gltf.to_string_lossy().into());
            }
        }
        index.insert(format!("{bdb}.bdb"), serde_json::Value::Object(map));
    }
    std::fs::write(out.join("objects.json"), serde_json::to_string_pretty(&index)?)?;
    println!("objects: {} models -> {}", done.values().filter(|ok| **ok).count(), out.display());
    Ok(())
}

/// Cockpit images shared by all aircraft (MFD sprites, RWR symbols, map).
const SHARED_COCKPIT_IMAGES: &[&str] = &["mfds.bmp", "rwrsymb.bmp", "isr.bmp"];

fn convert_cockpit(install: &Path, name: &str, out: &Path, opts: &Options) -> Result<()> {
    use iaf_formats::ini::Ini;
    use iaf_tools::gltf::{COCKPIT_KEYS, COLOR_KEY, load_texture_keyed};
    let root = install.join("resource/cockpits");
    let dir = root.join(name.to_lowercase());
    std::fs::create_dir_all(out)?;

    // Layout: every section/key of cockpit.ibx, numbers as numbers.
    let ini = Ini::parse(&std::fs::read(dir.join("cockpit.ibx")).context("cockpit.ibx")?);
    let mut layout = serde_json::Map::new();
    for section in &ini.sections {
        let mut obj = serde_json::Map::new();
        for (k, v) in &section.entries {
            // GetPrivateProfileInt reads an empty value (`MiddleOffsetX =`) as 0.
            let value = if v.trim().is_empty() {
                serde_json::Value::from(0)
            } else {
                v.parse::<f64>().map(serde_json::Value::from).unwrap_or_else(|_| serde_json::Value::from(v.as_str()))
            };
            obj.entry(k.clone()).or_insert(value);
        }
        layout.insert(section.name.clone(), serde_json::Value::Object(obj));
    }
    let scale = if opts.upscaler.is_some() { upscale::FACTOR } else { 1 };
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
    for src in images {
        let (img, transparent) = load_texture_keyed(&src, COCKPIT_KEYS)?;
        let img = match &opts.upscaler {
            Some(u) => u.upscale(&img, transparent.then_some(COLOR_KEY))?,
            None => img,
        };
        let file = format!("{}.png", src.file_stem().unwrap().to_string_lossy().to_lowercase());
        img.save(out.join(&file))?;
        println!("  {file} {}x{}", img.width(), img.height());
    }
    println!("{} -> {}", dir.display(), out.display());
    Ok(())
}

fn walk_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for e in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let p = e.path();
        if p.is_dir() {
            walk_files(&p, out);
        } else {
            out.push(p);
        }
    }
}

/// Files under `rel` (relative to resource/menu) from the base install, each replaced by the
/// pack's copy when the pack has one, plus pack-only files. Returned as (relative path, file).
fn overlay_files(root: &Path, pack_root: Option<&Path>, rel: &str) -> Vec<(PathBuf, PathBuf)> {
    let mut map = std::collections::BTreeMap::new();
    for r in [Some(root), pack_root].into_iter().flatten() {
        let mut files = Vec::new();
        walk_files(&r.join(rel), &mut files);
        for f in files {
            let key = f.strip_prefix(r).unwrap().to_string_lossy().to_lowercase();
            map.insert(PathBuf::from(key), f);
        }
    }
    map.into_iter().collect()
}

/// Windows-1252, or Windows-1255 Hebrew for pack files. Stray NUL bytes are dropped.
fn decode_text(data: &[u8], hebrew: bool) -> String {
    data.iter()
        .filter(|&&c| c != 0)
        .map(|&c| match (hebrew, c) {
            (true, 0xe0..=0xfa) => char::from_u32(0x05d0 + (c - 0xe0) as u32).unwrap_or('?'),
            _ => c as char,
        })
        .collect()
}

fn convert_menu(install: &Path, pack: Option<&Path>, out: &Path, opts: &Options) -> Result<()> {
    use iaf_formats::menu::{self, MenuFile};
    use iaf_tools::gltf::{COCKPIT_KEYS, COLOR_KEY, load_texture_keyed};
    use serde_json::json;
    let root = install.join("resource/menu");
    let pack_root = pack.map(|p| p.join("resource/menu"));
    let from_pack = |f: &Path| pack_root.as_ref().is_some_and(|p| f.starts_with(p));
    std::fs::create_dir_all(out)?;

    // Screens and lists.
    let mut menus = serde_json::Map::new();
    for (_, f) in &overlay_files(&root, pack_root.as_deref(), "dat") {
        let key = f.file_stem().unwrap().to_string_lossy().to_lowercase();
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
    for (_, f) in overlay_files(&root, pack_root.as_deref(), "txt").iter().filter(|(r, _)| r.extension().is_some_and(|e| e == "trx")) {
        let text = decode_text(&std::fs::read(f)?, from_pack(f));
        strings.insert(f.file_stem().unwrap().to_string_lossy().to_lowercase(), text.trim().replace("\r\n", "\n").into());
    }
    std::fs::write(out.join("strings.json"), serde_json::to_string_pretty(&strings)?)?;

    // Fonts.
    for (rel, p) in overlay_files(&root, pack_root.as_deref(), "fnt") {
        if rel.extension().is_some_and(|x| x == "ttf") {
            std::fs::copy(&p, out.join(rel.file_name().unwrap()))?;
        }
    }

    // Art.
    // Panel masks (1-bit, black = panel visible): the original draws mask AND, panel OR.
    let masks: Vec<image::GrayImage> = ["maskleft", "maskbottom1", "maskbottom2"]
        .iter()
        .filter_map(|m| image::open(root.join(format!("bmp/misc/{m}.bmp"))).ok().map(|i| i.to_luma8()))
        .collect();
    let img_root = out.join("img");
    let mut n = 0;
    for (rel, src) in overlay_files(&root, pack_root.as_deref(), "bmp").iter().filter(|(r, _)| r.extension().is_some_and(|e| e == "bmp")) {
        let dest = img_root.join(rel.strip_prefix("bmp")?.with_extension("png"));
        let (mut img, mut transparent) = match load_texture_keyed(src, COCKPIT_KEYS) {
            Ok(v) => v,
            Err(e) => {
                println!("  skipped {}: {e:#}", src.display());
                continue;
            }
        };
        if rel.starts_with("bmp/palettes") {
            // The mask whose size is closest to the panel (bottom panels are a few pixels larger).
            if let Some(mask) = masks.iter().min_by_key(|m| (m.width() as i64 - img.width() as i64).abs() + (m.height() as i64 - img.height() as i64).abs()) {
                if (mask.width() as i64 - img.width() as i64).abs() <= 4 && (mask.height() as i64 - img.height() as i64).abs() <= 4 {
                    for (x, y, p) in img.enumerate_pixels_mut() {
                        let visible = if x < mask.width() && y < mask.height() {
                            mask.get_pixel(x, y)[0] < 128
                        } else {
                            p[0] as u32 + p[1] as u32 + p[2] as u32 > 0
                        };
                        if !visible {
                            p[3] = 0;
                            transparent = true;
                        }
                    }
                }
            }
        }
        let img = match &opts.upscaler {
            Some(u) => u.upscale(&img, transparent.then_some(COLOR_KEY))?,
            None => img,
        };
        std::fs::create_dir_all(dest.parent().unwrap())?;
        img.save(&dest)?;
        n += 1;
    }
    // Sounds (button clicks, panel slides, menu music).
    std::fs::create_dir_all(out.join("wav"))?;
    for (rel, p) in overlay_files(&root, pack_root.as_deref(), "wav") {
        if rel.extension().is_some_and(|x| x == "wav") && rel.parent().is_some_and(|d| d == Path::new("wav")) {
            std::fs::copy(&p, out.join("wav").join(rel.file_name().unwrap()))?;
        }
    }
    // TSD maps and overlays (vector, see docs/front-end.md §8).
    std::fs::create_dir_all(out.join("emf"))?;
    let mut emfs = 0;
    for (rel, p) in overlay_files(&root, pack_root.as_deref(), "emf") {
        if !rel.extension().is_some_and(|x| x.eq_ignore_ascii_case("emf")) {
            continue;
        }
        let mf = iaf_formats::emf::parse(&std::fs::read(&p)?)?;
        let name = rel.file_stem().unwrap().to_string_lossy().to_lowercase();
        std::fs::write(out.join("emf").join(format!("{name}.json")), serde_json::to_string(&emf_json(&mf))?)?;
        emfs += 1;
    }
    std::fs::write(out.join("image_scale.txt"), if opts.upscaler.is_some() { "4" } else { "1" })?;
    println!("menu: {emfs} maps,");
    println!("menu: {} screens/lists, {} strings, {n} images -> {}", menus.len(), strings.len(), out.display());
    Ok(())
}

/// A metafile as JSON: frame size, then drawing ops with points normalised to the frame
/// (0..1, flat [x0, y0, x1, y1, ...]).
fn emf_json(mf: &iaf_formats::emf::Metafile) -> serde_json::Value {
    use iaf_formats::emf::Op;
    use serde_json::json;
    let flat = |pts: &[[f32; 2]]| pts.iter().flat_map(|p| [(p[0] * 1e5).round() / 1e5, (p[1] * 1e5).round() / 1e5]).collect::<Vec<f32>>();
    let pen = |p: &Option<iaf_formats::emf::Pen>| p.map(|p| json!({"color": p.color, "width": p.width}));
    let ops: Vec<_> = mf.ops.iter().map(|op| match op {
        Op::Polygon { rings, pen: pn, brush, alternate } => json!({
            "t": "polygon", "rings": rings.iter().map(|r| flat(r)).collect::<Vec<_>>(),
            "pen": pen(pn), "brush": brush, "alternate": alternate,
        }),
        Op::Polyline { points, pen: pn } => json!({"t": "polyline", "points": flat(points), "pen": pen(&Some(*pn))}),
        Op::Text { pos, text, font, color, align } => json!({
            "t": "text", "pos": pos, "text": text, "color": color, "align": align,
            "font": {"height": font.height, "weight": font.weight, "italic": font.italic, "face": font.face},
        }),
    }).collect();
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
    let text = |b: &[u8]| -> String {
        let b = b.split(|&c| c == 0).next().unwrap_or(&[]);
        b.iter()
            .map(|&c| match (hebrew, c) {
                (true, 0xe0..=0xfa) => char::from_u32(0x05d0 + (c - 0xe0) as u32).unwrap_or('?'),
                _ => c as char,
            })
            .collect::<String>()
            .trim()
            .to_string()
    };
    data.chunks_exact(516)
        .map(|e| (text(&e[..256]), i32::from_le_bytes(e[256..260].try_into().unwrap()), text(&e[260..]).replace('\\', "/").to_lowercase()))
        .filter(|(t, _, f)| !t.is_empty() || !f.is_empty())
        .collect()
}

fn convert_briefings(install: &Path, packs: &Path, out: &Path, opts: &Options) -> Result<()> {
    use iaf_formats::rtf::to_bbcode;
    use iaf_tools::gltf::{COLOR_KEY, load_texture};
    use serde_json::json;
    let base = install.join("resource/brief");
    let he = packs.join("he/resource/brief");
    std::fs::create_dir_all(out)?;
    let read_rtf = |dir: &Path, name: &str| std::fs::read(dir.join(name)).ok().map(|d| to_bbcode(&d));
    let read_brl = |dir: &Path, name: &str, hebrew: bool| std::fs::read(dir.join(name)).ok().map(|d| parse_brl(&d, hebrew));
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
    std::fs::write(out.join("briefings.json"), serde_json::to_string_pretty(&doc)?)?;

    // Diagrams: original, and the Hebrew pack's relabelled versions.
    let mut n = 0;
    for (src_dir, dest) in [(base.join("bmp"), out.join("img")), (he.join("bmp"), out.join("img_he"))] {
        let Ok(rd) = std::fs::read_dir(&src_dir) else { continue };
        std::fs::create_dir_all(&dest)?;
        for e in rd.flatten() {
            let p = e.path();
            if !p.extension().is_some_and(|x| x.eq_ignore_ascii_case("bmp")) {
                continue;
            }
            let Ok((img, transparent)) = load_texture(&p) else { continue };
            let img = match &opts.upscaler {
                Some(u) => u.upscale(&img, transparent.then_some(COLOR_KEY))?,
                None => img,
            };
            img.save(dest.join(format!("{}.png", p.file_stem().unwrap().to_string_lossy().to_lowercase())))?;
            n += 1;
        }
    }
    println!("briefings: {} missions, {} lessons, {n} diagrams -> {}",
        doc["missions"].as_object().map_or(0, |m| m.len()), doc["lessons"].as_object().map_or(0, |m| m.len()), out.display());
    Ok(())
}

/// Raster fonts → BMFont text format + atlas (Godot: `FontFile.load_bitmap_font`). Glyphs are
/// kept at their original pixel size; the engine scales them.
fn convert_fonts(install: &Path, out: &Path) -> Result<()> {
    use iaf_formats::winfnt;
    std::fs::create_dir_all(out)?;
    for name in ["hud", "mfd", "key"] {
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
            font.face, h, h, font.ascent, glyphs.len()
        );
        for (g, &(gx, gy)) in glyphs.iter().zip(&places) {
            for py in 0..h {
                for px in 0..g.width {
                    let v = g.pixels[(py * g.width + px) as usize];
                    img.put_pixel(gx + px, gy + py, image::Rgba([255, 255, 255, v]));
                }
            }
            // Windows-1252 code → Unicode.
            let ch = if (0x80..0xa0).contains(&g.code) { g.code } else { g.code };
            desc.push_str(&format!(
                "char id={ch} x={gx} y={gy} width={} height={h} xoffset=0 yoffset=0 xadvance={} page=0 chnl=15\n",
                g.width, g.width
            ));
        }
        img.save(out.join(format!("{name}.png")))?;
        std::fs::write(out.join(format!("{name}.fnt")), desc)?;
        println!("{name}: {} glyphs, {}px tall ({})", glyphs.len(), h, font.face);
    }
    Ok(())
}

fn convert_missions(install: &Path, out: &Path) -> Result<()> {
    use iaf_tools::mis;
    let dir = install.join("resource/missions");
    std::fs::create_dir_all(out)?;
    let (mut ok, mut failed) = (0, Vec::new());
    let mut bdb_version = 9;
    let mut entries: Vec<_> = std::fs::read_dir(&dir)?.flatten().map(|e| e.path()).collect();
    entries.sort();
    for p in &entries {
        let name = p.file_name().unwrap().to_string_lossy().to_lowercase();
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
        let name = p.file_name().unwrap().to_string_lossy().to_lowercase().replace(".bdb", ".bdb.json");
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
    println!("missions: {ok} converted, {} failed, {} ids -> {}", failed.len(), map.len(), out.display());
    for f in failed {
        println!("  {f}");
    }
    Ok(())
}
