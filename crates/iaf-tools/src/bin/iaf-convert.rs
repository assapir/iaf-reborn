//! Convert original IAF assets into engine-friendly formats.
//!
//! `iaf-convert model <file.x|file.xfr> <out-dir>` — one model → glTF + PNG textures.
//! `iaf-convert planes <install-dir> <out-dir>` — every controllable plane (`*_h.xfr`).
//!
//! `iaf-convert cockpit <install-dir> <cockpit> <out-dir>` — cockpit art (PNG) + layout (`cockpit.json`).
//! `iaf-convert menu <install-dir> <out-dir>` — front-end screens/lists (`menus.json`), strings
//! (`strings.json`), art (`img/…png`) and TrueType fonts.
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
        [_, "menu", install, out] => convert_menu(Path::new(install), Path::new(out), &opts),
        [_, "cockpit", install, name, out] => convert_cockpit(Path::new(install), name, Path::new(out), &opts),
        _ => bail!("usage: iaf-convert [--upscale] [--smooth] model <file.x|file.xfr> <out-dir>\n       iaf-convert [--upscale] [--smooth] planes <install-dir> <out-dir>\n       iaf-convert [--upscale] cockpit <install-dir> <cockpit> <out-dir>\n       iaf-convert [--upscale] menu <install-dir> <out-dir>"),
    }
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
            let value = v.parse::<f64>().map(serde_json::Value::from).unwrap_or_else(|_| serde_json::Value::from(v.as_str()));
            obj.entry(k.clone()).or_insert(value);
        }
        layout.insert(section.name.clone(), serde_json::Value::Object(obj));
    }
    let scale = if opts.upscaler.is_some() { upscale::FACTOR } else { 1 };
    layout.insert("image_scale".into(), scale.into());
    std::fs::write(out.join("cockpit.json"), serde_json::to_string_pretty(&layout)?)?;

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

fn convert_menu(install: &Path, out: &Path, opts: &Options) -> Result<()> {
    use iaf_formats::menu::{self, MenuFile};
    use iaf_tools::gltf::{COCKPIT_KEYS, COLOR_KEY, load_texture_keyed};
    use serde_json::json;
    let root = install.join("resource/menu");
    std::fs::create_dir_all(out)?;

    // Screens and lists.
    let mut menus = serde_json::Map::new();
    let mut files = Vec::new();
    walk_files(&root.join("dat"), &mut files);
    files.sort();
    for f in &files {
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
    let mut files = Vec::new();
    walk_files(&root.join("txt"), &mut files);
    for f in files.iter().filter(|f| f.extension().is_some_and(|e| e == "trx")) {
        let text: String = std::fs::read(f)?.iter().map(|&b| b as char).collect();
        strings.insert(f.file_stem().unwrap().to_string_lossy().to_lowercase(), text.trim().replace("\r\n", "\n").into());
    }
    std::fs::write(out.join("strings.json"), serde_json::to_string_pretty(&strings)?)?;

    // Fonts.
    for e in std::fs::read_dir(root.join("fnt"))?.flatten() {
        let p = e.path();
        if p.extension().is_some_and(|x| x.eq_ignore_ascii_case("ttf")) {
            std::fs::copy(&p, out.join(p.file_name().unwrap()))?;
        }
    }

    // Art.
    let mut images = Vec::new();
    walk_files(&root.join("bmp"), &mut images);
    let img_root = out.join("img");
    let mut n = 0;
    for src in images.iter().filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("bmp"))) {
        let rel = src.strip_prefix(root.join("bmp"))?.with_extension("png");
        let dest = img_root.join(rel.to_string_lossy().to_lowercase());
        let (img, transparent) = match load_texture_keyed(src, COCKPIT_KEYS) {
            Ok(v) => v,
            Err(e) => {
                println!("  skipped {}: {e:#}", src.display());
                continue;
            }
        };
        let img = match &opts.upscaler {
            Some(u) => u.upscale(&img, transparent.then_some(COLOR_KEY))?,
            None => img,
        };
        std::fs::create_dir_all(dest.parent().unwrap())?;
        img.save(&dest)?;
        n += 1;
    }
    std::fs::write(out.join("image_scale.txt"), if opts.upscaler.is_some() { "4" } else { "1" })?;
    println!("menu: {} screens/lists, {} strings, {n} images -> {}", menus.len(), strings.len(), out.display());
    Ok(())
}
