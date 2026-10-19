//! Convert original IAF assets into engine-friendly formats.
//!
//! `iaf-convert model <file.x|file.xfr> <out-dir>` — one model → glTF + PNG textures.
//! `iaf-convert aircraft <install-dir> <missions-dir> <out-dir>` — every aircraft (controllable and
//! non-controllable `*_h.xfr`) plus its descriptor `aircraft.json` (docs/aircraft.md).
//!
//! `iaf-convert cockpit <install-dir> <cockpit> <out-dir>` — cockpit art (PNG) + layout (`cockpit.json`).
//! `iaf-convert briefings <install-dir> <packs-dir> <out-dir>` — briefing/lesson texts (RTF → BBCode,
//! English + Hebrew pack), `.brl` entry lists and diagrams (`briefings.json`, `img/`, `img_he/`).
//! `iaf-convert reference <install-dir> <out-dir>` — the Reference screen's records (`resource/ref/refers.ref`,
//! sorted) with their `<dir>_0.rtf` description (BBCode), model path (glTF under converted/objects) and `.cp`
//! view limits (`reference.json`), and the `<dir>_0.bmp` pictures (`img/<dir>.png`), docs/front-end.md §14.
//! `iaf-convert missions <install-dir> <out-dir>` — every `.mis` and the `.bdb` → JSON, plus the
//! mission list (menu id → mission + base-mission files).
//! `iaf-convert fonts <install-dir> <out-dir>` — HUD/MFD/key raster fonts → BMFont (`.fnt` + `.png`).
//! `iaf-convert menu <install-dir> <out-dir> [--pack <pack-dir>]` — front-end screens/lists
//! (`menus.json`), strings (`strings.json`), art (`img/…png`) and TrueType fonts; with `--pack`,
//! files present in the pack (e.g. assets/packs/he, Hebrew art/strings in Windows-1255) win.
//!
//! `iaf-convert keys <install-dir> <packs-dir> <out.json>` — the original default key table from
//! `iafjets.exe` (117 records at 0x64c3c8) with the `keys.trx` labels (+ the Hebrew pack's when
//! present), the DirectInput key names and modifier prefixes of the Controls page
//! (docs/front-end.md §12.7, docs/controls.md).
//!
//! `iaf-convert plane-describe <model.gltf> <out-dir> [--type N] [--section NAME] [--label L]` — the
//! descriptor (`aircraft.json`) of a hand-made glTF plane plus a report of what the game will miss
//! (docs/adding-a-plane.md). `iaf-convert plane-checklist <type> [repo-dir]` — every code table a
//! new aircraft type goes into, with file:line and whether the type is already there.
//!
//! `--upscale` resamples textures 4× (Lanczos).
//! `--smooth` rounds the low-poly geometry (smooth normals + Phong tessellation).

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::convert::{self, Options};
use iaf_tools::progress::Stdout;

fn main() -> Result<()> {
    let mut args: Vec<String> = std::env::args().collect();
    let mut flag = |name: &str| args.iter().position(|a| a == name).map(|i| args.remove(i)).is_some();
    let opts = Options { upscale: flag("--upscale"), smooth: flag("--smooth") };
    let mut value = |name: &str| args.iter().position(|a| a == name).filter(|&i| i + 1 < args.len()).map(|i| {
        args.remove(i);
        args.remove(i)
    });
    let plane = PlaneOptions { type_code: value("--type"), section: value("--section"), label: value("--label") };
    let (pr, cancel) = (&Stdout, &AtomicBool::new(false));
    let p = Path::new;
    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [_, "model", src, out] => convert::model(p(src), p(out), &[], &opts, pr),
        [_, "aircraft", install, missions, out] => convert::aircraft(p(install), p(missions), p(out), &opts, pr, cancel),
        [_, "missions", install, out] => convert::missions(p(install), p(out), pr, cancel),
        [_, "objects", install, missions, out] => convert::objects(p(install), p(missions), p(out), &opts, pr, cancel),
        [_, "fonts", install, out] => convert::fonts(p(install), p(out), pr, cancel),
        [_, "briefings", install, packs, out] => convert::briefings(p(install), p(packs), p(out), &opts, pr, cancel),
        [_, "reference", install, out] => convert::reference(p(install), p(out), &opts, pr, cancel),
        [_, "menu", install, out] => convert::menu(p(install), None, p(out), &opts, pr, cancel),
        [_, "menu", install, out, "--pack", pack] => convert::menu(p(install), Some(p(pack)), p(out), &opts, pr, cancel),
        [_, "keys", install, packs, out] => convert::keys(p(install), p(packs), p(out), pr, cancel),
        [_, "icon", install, out] => convert::icon(p(install), p(out), pr, cancel),
        [_, "cockpit", install, name, out] => convert::cockpit(p(install), name, p(out), &opts, pr, cancel),
        [_, "arm-extra", menu_img, arm_dir, out] => convert::arm_extra(p(menu_img), p(arm_dir), p(out), pr, cancel),
        [_, "plane-describe", model, out] => plane_describe(Path::new(model), Path::new(out), &plane),
        [_, "plane-checklist", code] => plane_checklist(code, Path::new(".")),
        [_, "plane-checklist", code, repo] => plane_checklist(code, Path::new(repo)),
        _ => bail!("usage: iaf-convert [--upscale] [--smooth] model <file.x|file.xfr> <out-dir>\n       iaf-convert [--upscale] [--smooth] aircraft <install-dir> <missions-dir> <out-dir>\n       iaf-convert [--upscale] cockpit <install-dir> <cockpit> <out-dir>\n       iaf-convert [--upscale] menu <install-dir> <out-dir> [--pack <pack-dir>]\n       iaf-convert [--upscale] briefings <install-dir> <packs-dir> <out-dir>\n       iaf-convert keys <install-dir> <packs-dir> <out.json>\n       iaf-convert plane-describe <model.gltf> <out-dir> [--type N] [--section NAME] [--label L]\n       iaf-convert plane-checklist <type> [repo-dir]"),
    }
}

struct PlaneOptions {
    type_code: Option<String>,
    section: Option<String>,
    label: Option<String>,
}

/// A hand-made glTF plane: its descriptor (`<out>/aircraft.json`, as `convert_aircraft` writes for
/// the original models) and the report of what the game will miss (docs/adding-a-plane.md §2).
fn plane_describe(model: &Path, out: &Path, opts: &PlaneOptions) -> Result<()> {
    use iaf_tools::{aircraft, plane};
    let gltf: serde_json::Value = serde_json::from_slice(&std::fs::read(model)?).with_context(|| format!("reading {}", model.display()))?;
    let folder = out.file_name().map_or_else(String::new, |f| f.to_string_lossy().to_lowercase());
    let file = model.file_name().unwrap().to_string_lossy().to_string();
    let mut d = aircraft::describe(&plane::to_model(&gltf), &folder, &file, &format!("hand-made: {file}"), &[]);
    if let Some(t) = &opts.type_code {
        let t: i64 = t.parse().context("--type")?;
        if plane::RESERVED.contains(&t) {
            bail!("type {t} is skipped by the RWR (rwr.gd IGNORED_TYPES): pick another");
        }
        d["type"] = t.into();
        d["types"] = serde_json::json!([t]);
    }
    if let Some(s) = &opts.section {
        d["fm_section"] = s.as_str().into();
    }
    if let Some(l) = &opts.label {
        d["label"] = l.as_str().into();
    }
    std::fs::create_dir_all(out)?;
    std::fs::write(out.join("aircraft.json"), serde_json::to_string_pretty(&d)?)?;
    println!("{} -> {}/aircraft.json", model.display(), out.display());
    let findings = plane::report(&gltf, &d);
    for f in &findings {
        println!("  {f}");
    }
    if findings.is_empty() {
        println!("  no findings");
    }
    Ok(())
}
/// The code tables a new aircraft type goes into (docs/adding-a-plane.md §1).
fn plane_checklist(code: &str, repo: &Path) -> Result<()> {
    use iaf_tools::plane;
    let code: i64 = code.parse().context("type code")?;
    if plane::RESERVED.contains(&code) {
        println!("type {code} is skipped by the RWR (game/weapons/rwr.gd IGNORED_TYPES): pick another");
    }
    let mut missing = 0;
    for r in plane::checklist(repo, code) {
        let at = r.line.map_or_else(|| format!("{} (anchor not found: {})", r.table.file, r.table.anchor), |l| format!("{}:{l}", r.table.file));
        let mark = match (r.line, r.present, r.table.list) {
            (None, _, _) => "??",
            (_, true, _) => "ok",
            (_, false, true) => "--",
            (_, false, false) => "..",
        };
        missing += usize::from(mark == "--");
        println!("{mark} {at}  {}", r.table.what);
    }
    println!("ok = has {code}, -- = add it, .. = conditions to review, ?? = table moved (update plane.rs TABLES); {missing} to add");
    Ok(())
}
