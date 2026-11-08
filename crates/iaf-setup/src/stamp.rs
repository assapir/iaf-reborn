//! Step stamps: `<output>.stamp` holds what the step's output was made from (the fingerprints of the source files that
//! decide it, the step's options, a checksum of each outside file it reads, the stamps of the steps it waits for). The
//! same text again: up to date.

use std::io::Read;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

use crate::sim::{SimCtx, THEATRE};
use crate::{Ctx, Hebrew, Step};

include!(concat!(env!("OUT_DIR"), "/sources.rs"));

/// What every converter reads with: iaf-tools' lib.rs (`walk_files`), iaf-formats' lib.rs and byte readers, the
/// terrain-type table iaf-tools re-exports. progress.rs is left out (logging and threads: no output).
const BASE: &[&str] = &[
    "crates/iaf-tools/src/lib.rs",
    "crates/iaf-formats/src/lib.rs",
    "crates/iaf-formats/src/bytes.rs",
    "crates/iaf-formats/src/terrain_types.rs",
];
/// iaf_tools::extract and its formats (the CD's ISO 9660, ESA archives, SSF); `explode` unpacks the ESA entries.
const EXTRACT: &[&str] = &[
    "crates/iaf-tools/src/extract.rs",
    "crates/iaf-formats/src/iso9660.rs",
    "crates/iaf-formats/src/esa.rs",
    "crates/iaf-formats/src/ssf.rs",
    "Cargo.lock:explode",
];
/// iaf_tools::convert and every module it reaches; `image` decodes, scales and writes the pictures.
const CONVERT: &[&str] = &[
    "crates/iaf-tools/src/convert.rs",
    "crates/iaf-tools/src/aircraft.rs",
    "crates/iaf-tools/src/sim_files.rs",
    "crates/iaf-tools/src/exe.rs",
    "crates/iaf-tools/src/gltf.rs",
    "crates/iaf-tools/src/mis.rs",
    "crates/iaf-tools/src/plane.rs",
    "crates/iaf-tools/src/smooth.rs",
    "crates/iaf-tools/src/upscale.rs",
    "crates/iaf-formats/src/emf.rs",
    "crates/iaf-formats/src/ini.rs",
    "crates/iaf-formats/src/menu.rs",
    "crates/iaf-formats/src/model.rs",
    "crates/iaf-formats/src/refs.rs",
    "crates/iaf-formats/src/rtf.rs",
    "crates/iaf-formats/src/winfnt.rs",
    "crates/iaf-formats/src/xfile.rs",
    "Cargo.lock:image",
];
/// iaf_tools::terrain (the theatre and the airbases) and every module it reaches.
const TERRAIN: &[&str] = &[
    "crates/iaf-tools/src/terrain.rs",
    "crates/iaf-tools/src/airbases.rs",
    "crates/iaf-tools/src/georef.rs",
    "crates/iaf-tools/src/imagery.rs",
    "crates/iaf-tools/src/runway_fix.rs",
    "crates/iaf-tools/data/georef_points.json",
    "crates/iaf-tools/data/runway_number_fixes.json",
    "crates/iaf-formats/src/ini.rs",
    "crates/iaf-formats/src/lzo.rs",
    "crates/iaf-formats/src/ptt.rs",
    "Cargo.lock:image",
];
/// The bodies of extract, patch, hebrew and arm in this crate (their one-line calls in steps.rs do not count).
const STEPS: &[&str] = &["crates/iaf-setup/src/bodies.rs"];

/// The sim's compilers (`iaf_tools::sim`, `sim_bases`, `sim_cockpit`) and every module they reach.
const SIM: &[&str] = &[
    "crates/iaf-formats/src/xfile.rs",
    "crates/iaf-formats/src/model.rs",
    "crates/iaf-tools/src/aircraft.rs",
    "crates/iaf-tools/src/mission_year.rs",
    "crates/iaf-tools/src/mission_events.rs",
    "crates/iaf-formats/src/mcr.rs",
    "crates/iaf-formats/src/ini.rs",
    "crates/iaf-tools/src/mission_creator.rs",
    "crates/iaf-tools/src/sim.rs",
    "crates/iaf-tools/src/sim_bases.rs",
    "crates/iaf-tools/src/sim_cockpit.rs",
    "crates/iaf-tools/src/thirdparty.rs",
    "crates/iaf-tools/src/itm.rs",
    "crates/iaf-tools/src/imagery_run.rs",
    "crates/iaf-formats/src/lzo.rs",
    "crates/iaf-formats/src/ptt.rs",
    "crates/iaf-tools/src/airbases.rs",
    "crates/iaf-tools/data/georef_points.json",
    "crates/iaf-tools/src/georef.rs",
    "crates/iaf-tools/src/imagery.rs",
    "crates/iaf-tools/src/sim_terrain.rs",
    "crates/iaf-tools/src/sim_files.rs",
    "crates/iaf-tools/src/mission_edit.rs",
    "crates/iaf-tools/src/training.rs",
];
/// Modern IAF's terrain (`iaf_tools::sim_terrain`) and every module it reaches.
const SIM_TERRAIN: &[&str] = &[
    "crates/iaf-tools/src/itm.rs",
    "crates/iaf-formats/src/lzo.rs",
    "crates/iaf-formats/src/ptt.rs",
    "crates/iaf-formats/src/ini.rs",
    "crates/iaf-tools/src/airbases.rs",
    "crates/iaf-tools/data/georef_points.json",
    "crates/iaf-tools/src/georef.rs",
    "crates/iaf-tools/src/sim_terrain.rs",
    "crates/iaf-tools/src/imagery.rs",
    "crates/iaf-tools/src/imagery_run.rs",
    "crates/iaf-tools/src/thirdparty.rs",
    "Cargo.lock:image",
];

/// The sources (files, folders, `Cargo.lock:<crate>`) that decide each stamped step's output, as groups. A new step
/// with a stamp gets a row (the tests check every stamped step has one and that each row holds every module its
/// files reach).
pub(crate) const STEP_SOURCES: &[(&str, &[&[&str]])] = &[
    ("extract", &[BASE, EXTRACT, STEPS]),
    (
        "patch",
        &[
            BASE,
            STEPS,
            &["crates/iaf-tools/src/patch.rs", "crates/iaf-tools/src/rtpatch.rs", "crates/iaf-tools/src/exe.rs"],
        ],
    ),
    ("hebrew", &[BASE, EXTRACT, STEPS, &["crates/iaf-tools/src/pack.rs"]]),
    ("arm", &[BASE, CONVERT, STEPS]),
    ("launcher", &[&["tools/install-launcher.sh", "tools/windows/install-launcher.ps1"]]),
    ("theatre", &[BASE, TERRAIN]),
    ("airbases", &[BASE, TERRAIN]),
    ("keys", &[BASE, CONVERT]),
    ("icon", &[BASE, CONVERT]),
    ("fonts", &[BASE, CONVERT]),
    ("cockpits", &[BASE, CONVERT]),
    ("briefings", &[BASE, CONVERT]),
    ("reference", &[BASE, CONVERT]),
    ("menu", &[BASE, CONVERT]),
    ("menu_he", &[BASE, CONVERT]),
    ("missions", &[BASE, CONVERT]),
    ("aircraft", &[BASE, CONVERT]),
    ("objects", &[BASE, CONVERT]),
    (
        "models",
        &[
            BASE,
            &[
                "crates/iaf-tools/src/f15.rs",
                "crates/iaf-tools/src/thirdparty.rs",
                "crates/iaf-formats/src/ac3d.rs",
                "crates/iaf-tools/data/f15-livery",
                "Cargo.lock:image",
            ],
        ],
    ),
    ("sim-terrain", &[BASE, SIM_TERRAIN]),
    ("sim-db", &[BASE, SIM]),
    ("sim-own", &[BASE, SIM]),
    ("sim-airbases", &[BASE, SIM]),
    ("sim-missions", &[BASE, SIM]),
    // The script is the step's input (its lines in the stamp); the call is in sim.rs.
    ("sim-fm", &[&["crates/iaf-setup/src/sim.rs"]]),
];

/// One `code <path> <hash>` line per source file of step `id` (from `sources`, the build's `SOURCES`), a folder's
/// files each; a listed source not in `sources`: `code <path> missing`. The stamp holds their hash ([`code`]).
fn code_lines(id: &str, sources: &[(&str, u64)]) -> String {
    let Some((_, groups)) = STEP_SOURCES.iter().find(|(s, _)| *s == id) else {
        return format!("code {id} undeclared\n");
    };
    let mut paths: Vec<&str> = groups.iter().flat_map(|g| g.iter().copied()).collect();
    paths.sort();
    paths.dedup();
    let mut s = String::new();
    for p in paths {
        let dir = format!("{p}/");
        let mut any = false;
        for (f, h) in sources.iter().filter(|(f, _)| *f == p || f.starts_with(&dir)) {
            s += &format!("code {f} {h:016x}\n");
            any = true;
        }
        if !any {
            s += &format!("code {p} missing\n");
        }
    }
    s
}

pub(crate) struct Stamp {
    pub path: PathBuf,
    pub text: String,
    /// Must exist for the stamp to hold.
    pub output: Option<PathBuf>,
}

impl Stamp {
    pub fn holds(&self) -> bool {
        std::fs::read_to_string(&self.path).is_ok_and(|t| t == self.text)
            && self.output.as_ref().is_none_or(|o| o.exists())
    }
    /// Removed before the step runs, so a step that fails half way is not up to date.
    pub fn clear(&self) -> Result<()> {
        match std::fs::remove_file(&self.path) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
                Err(e).with_context(|| format!("{}", self.path.display()))
            }
            _ => Ok(()),
        }
    }
    pub fn write(&self) -> Result<()> {
        if let Some(d) = self.path.parent() {
            std::fs::create_dir_all(d)?;
        }
        std::fs::write(&self.path, &self.text).with_context(|| format!("{}", self.path.display()))
    }
}

/// Step `id`'s code fingerprint: an FNV-1a hash of [`code_lines`]. One fixed-length line, so a stamp keeps its
/// size (tools/guide_shots.sh's stamps hold the converted files' sizes).
fn code(id: &str, sources: &[(&str, u64)]) -> u64 {
    code_lines(id, sources).bytes().fold(0xcbf29ce484222325, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3))
}

/// CRC-32 of a file's content.
fn crc_file(p: &Path) -> Result<u32> {
    let mut f = std::fs::File::open(p).with_context(|| format!("{}", p.display()))?;
    let mut h = crc32fast::Hasher::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            return Ok(h.finalize());
        }
        h.update(&buf[..n]);
    }
}

/// [`describe`] with each path relative to `base` and with `/` between its parts (the same stamp on every system and
/// in every checkout).
pub(crate) fn describe_under(p: &Path, base: &Path) -> Result<String> {
    let rel = |f: &Path| f.strip_prefix(base).unwrap_or(f).to_string_lossy().replace('\\', "/");
    let files = if p.is_dir() {
        let mut v = iaf_tools::walk_files(p)?;
        v.sort();
        v
    } else {
        vec![p.to_path_buf()]
    };
    let mut s = String::new();
    for f in files {
        s += &if f.is_file() {
            format!("input {} {} {:08x}\n", rel(&f), std::fs::metadata(&f)?.len(), crc_file(&f)?)
        } else {
            format!("input {} missing\n", rel(&f))
        };
    }
    Ok(s)
}

/// One line per file of `p` (a file, or every file under a folder): path, size, CRC-32.
pub(crate) fn describe(p: &Path) -> Result<String> {
    if p.is_dir() {
        let mut files = iaf_tools::walk_files(p)?;
        files.sort();
        let mut s = String::new();
        for f in files {
            s += &format!("input {} {} {:08x}\n", f.display(), std::fs::metadata(&f)?.len(), crc_file(&f)?);
        }
        Ok(s)
    } else if p.is_file() {
        Ok(format!("input {} {} {:08x}\n", p.display(), std::fs::metadata(p)?.len(), crc_file(p)?))
    } else {
        Ok(format!("input {} missing\n", p.display()))
    }
}

/// The stamp of `step`, without the lines of the steps it waits for (`run_one` adds them); `None`: the step keeps none
/// (imagery keeps its own per-unit marks; the scenery's sources their `.ok` marks and its cells `manifest.json`'s
/// `made_from`; the guides decide per picture).
pub(crate) fn of(step: &Step, ctx: &Ctx) -> Result<Option<Stamp>> {
    let a = &ctx.assets;
    let i = &ctx.inputs;
    let conv = |p: &str| a.join("converted").join(p);
    let (out, stamp, inputs): (Option<PathBuf>, PathBuf, Vec<PathBuf>) = match step.id {
        "extract" => (
            Some(a.join("install")),
            a.join("install.stamp"),
            [Some(i.cd.clone()), i.patch.clone()].into_iter().flatten().collect(),
        ),
        "patch" => (Some(a.join("v1.1")), a.join("v1.1.stamp"), i.patch.iter().cloned().collect()),
        "hebrew" => {
            let files = match &i.hebrew {
                Hebrew::None => vec![],
                Hebrew::Cd(p) => vec![p.clone()],
                Hebrew::Packs { brief, menu } => [brief.clone(), menu.clone()].into_iter().flatten().collect(),
            };
            (Some(a.join("packs/he")), a.join("packs/he.stamp"), files)
        }
        "arm" => (None, conv("arm.stamp"), vec![ctx.repo.join("shared/extra/planes")]),
        "launcher" => (None, conv("launcher.stamp"), vec![]),
        "theatre" => (Some(conv("terrain/theatre")), conv("terrain/theatre.stamp"), vec![]),
        "airbases" => (Some(conv("terrain/airbases.json")), conv("terrain/airbases.json.stamp"), vec![]),
        "keys" => (Some(conv("keys.json")), conv("keys.json.stamp"), vec![]),
        "icon" => (Some(conv("icon.png")), conv("icon.png.stamp"), vec![]),
        "fonts" | "cockpits" | "briefings" | "reference" | "menu" | "menu_he" | "missions" => {
            (Some(conv(step.id)), conv(&format!("{}.stamp", step.id)), vec![])
        }
        "aircraft" => (Some(conv("planes")), conv("planes.stamp"), vec![]),
        "objects" => (Some(conv("objects")), conv("objects.stamp"), vec![]),
        "models" => (Some(a.join(iaf_tools::f15::OUTPUT)), conv("models/f15.stamp"), vec![]),
        _ => return Ok(None),
    };
    let mut text = format!("iaf-setup {:016x}\nstep {}\n", code(step.id, SOURCES), step.id);
    if step.id == "launcher" {
        text += &format!("repo {}\nxdg {:?}\n", ctx.repo.display(), ctx.xdg_data_home);
    }
    for p in &inputs {
        text += &describe(p)?;
    }
    Ok(Some(Stamp { path: stamp, text, output: out }))
}

/// The stamp of one of Modern IAF's steps (`sim::sim_plan`), in `converted/iaf-2026/`: the code, the authored data it
/// reads; for the terrain, what `iaf-sim terrain` itself compares (the box and the Survey sheets' names and sizes).
pub(crate) fn sim_of(step: &Step, ctx: &SimCtx) -> Result<Option<Stamp>> {
    let (a, data) = (&ctx.assets, ctx.data());
    let (out, inputs): (PathBuf, Vec<PathBuf>) = match step.id {
        "sim-terrain" => (a.join(THEATRE).join("meta.json"), vec![data.join("airbases")]),
        "sim-db" => (a.join("converted/missions/sim.bdb.json"), vec![data.join("db")]),
        "sim-own" => (
            a.join("converted/own/keys.json"),
            vec![
                data.join("sounds"),
                data.join("keys.json"),
                data.join("planes"),
                ctx.repo.join(iaf_tools::sim::F16_GLB),
            ],
        ),
        "sim-airbases" => (a.join("converted/own/iaf.ibx"), vec![data.join("airbases")]),
        "sim-fm" => (a.join("converted/own/resource/md/bd.ibx"), vec![ctx.repo.join(crate::sim::FM0)]),
        "sim-missions" => {
            (a.join("converted/iaf-2026/missions"), vec![data.join("missions"), data.join("db"), data.join("airbases")])
        }
        _ => return Ok(None),
    };
    let mut text = format!("iaf-setup {:016x}\nstep {}\n", code(step.id, SOURCES), step.id);
    if step.id == "sim-terrain" {
        text += &format!("built_from {}\n", iaf_tools::sim_terrain::stamp(&ctx.terrain()));
    }
    for p in &inputs {
        // The repo's path is not part of what the data is.
        text += &describe_under(p, &ctx.repo)?;
    }
    let stamp = a.join("converted/iaf-2026").join(format!("{}.stamp", step.id));
    Ok(Some(Stamp { path: stamp, text, output: Some(out) }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    fn row(id: &str) -> BTreeSet<&'static str> {
        let (_, groups) = STEP_SOURCES.iter().find(|(s, _)| *s == id).unwrap_or_else(|| panic!("{id}: no row"));
        groups.iter().flat_map(|g| g.iter().copied()).collect()
    }

    #[test]
    fn every_stamped_step_has_a_row_and_every_source_exists() {
        let dir = std::env::temp_dir().join(format!("iaf-stamp-rows-{}", std::process::id()));
        let inputs = crate::Inputs {
            cd: dir.join("cd.iso"),
            patch: Some(dir.join("p.exe")),
            hebrew: Hebrew::Cd(dir.join("he.iso")),
            guides: true,
            scenery: true,
            ..Default::default()
        };
        let ctx =
            Ctx { assets: dir.clone(), repo: dir.clone(), inputs: inputs.clone(), xdg_data_home: None, guides: None };
        let mut stamped: BTreeSet<&str> =
            crate::plan(&inputs).iter().filter(|s| of(s, &ctx).unwrap().is_some()).map(|s| s.id).collect();
        let sim = SimCtx { assets: dir.clone(), repo: dir.clone(), inputs: Default::default() };
        stamped
            .extend(crate::sim_plan(&sim.inputs).iter().filter(|s| sim_of(s, &sim).unwrap().is_some()).map(|s| s.id));
        let rows: BTreeSet<&str> = STEP_SOURCES.iter().map(|(s, _)| *s).collect();
        assert_eq!(stamped, rows, "a row per stamped step, none for others");
        for id in rows {
            let lines = code_lines(id, SOURCES);
            assert!(!lines.contains("missing"), "{id}: {lines}");
        }
    }

    /// The modules and data files `path` (an iaf-tools or iaf-formats source) names: `crate::m`, `iaf_formats::m`
    /// (a name without its own file: the crate's lib.rs), `include_str!` / `include_bytes!` paths. Comment lines are
    /// skipped.
    fn reaches(root: &Path, path: &str) -> Vec<String> {
        let tools = path.starts_with("crates/iaf-tools/");
        let text: String = std::fs::read_to_string(root.join(path))
            .unwrap()
            .lines()
            .filter(|l| !l.trim().starts_with("//"))
            .map(|l| format!("{l}\n"))
            .collect();
        let mut out = Vec::new();
        let module = |krate: &str, name: &str| {
            let f = format!("crates/{krate}/src/{name}.rs");
            if root.join(&f).is_file() { f } else { format!("crates/{krate}/src/lib.rs") }
        };
        let own = if tools { "iaf-tools" } else { "iaf-formats" };
        for (prefix, krate) in [("crate::", own), ("iaf_formats::", "iaf-formats")] {
            for (k, _) in text.match_indices(prefix) {
                if text[..k].ends_with(|c: char| c == '_' || c.is_alphanumeric()) {
                    continue;
                }
                let rest = &text[k + prefix.len()..];
                let names = match rest.strip_prefix('{') {
                    Some(group) => &group[..group.find('}').unwrap()],
                    None => &rest[..rest.find(|c: char| c != '_' && !c.is_alphanumeric()).unwrap_or(rest.len())],
                };
                let names = names.split(|c: char| c != '_' && !c.is_alphanumeric());
                for n in names.filter(|n| !n.is_empty() && *n != "self") {
                    out.push(module(krate, n));
                }
            }
        }
        if tools && text.contains("iaf_formats::") {
            out.push("crates/iaf-formats/src/lib.rs".into());
        }
        let dir = Path::new(path).parent().unwrap();
        for mac in ["include_str!(\"", "include_bytes!(concat!(\"", "include_bytes!(\""] {
            for (k, _) in text.match_indices(mac) {
                let rest = &text[k + mac.len()..];
                let mut p = dir.to_path_buf();
                for c in rest[..rest.find('"').unwrap()].trim_end_matches('/').split('/') {
                    if c == ".." {
                        p.pop();
                    } else {
                        p.push(c);
                    }
                }
                out.push(p.to_string_lossy().replace('\\', "/"));
            }
        }
        out
    }

    #[test]
    fn each_row_holds_its_steps_module_and_everything_it_reaches() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let own = |id: &str| -> &[&str] {
            match id {
                "extract" => &["crates/iaf-tools/src/extract.rs", "crates/iaf-setup/src/bodies.rs"],
                "patch" => &["crates/iaf-tools/src/patch.rs", "crates/iaf-setup/src/bodies.rs"],
                "hebrew" => &[
                    "crates/iaf-tools/src/pack.rs",
                    "crates/iaf-tools/src/extract.rs",
                    "crates/iaf-setup/src/bodies.rs",
                ],
                "arm" => &["crates/iaf-tools/src/convert.rs", "crates/iaf-setup/src/bodies.rs"],
                "theatre" | "airbases" => &["crates/iaf-tools/src/terrain.rs"],
                "models" => &["crates/iaf-tools/src/f15.rs"],
                "launcher" => &["tools/install-launcher.sh"],
                "sim-terrain" => &["crates/iaf-tools/src/sim_terrain.rs"],
                "sim-fm" => &["crates/iaf-setup/src/sim.rs"],
                "sim-db" | "sim-own" | "sim-airbases" | "sim-missions" => {
                    &["crates/iaf-tools/src/sim.rs", "crates/iaf-tools/src/sim_bases.rs"]
                }
                _ => &["crates/iaf-tools/src/convert.rs"],
            }
        };
        for (id, _) in STEP_SOURCES {
            let set = row(id);
            for m in own(id) {
                assert!(set.contains(m), "{id}: its module {m}");
            }
            for f in set.iter().filter(|f| f.ends_with(".rs") && !f.starts_with("crates/iaf-setup/")) {
                for dep in reaches(&root, f) {
                    let covered = dep == "crates/iaf-tools/src/progress.rs"
                        || set.iter().any(|s| dep == *s || dep.starts_with(&format!("{s}/")));
                    assert!(covered, "{id}: {f} reaches {dep}, not in its row");
                }
            }
        }
    }

    #[test]
    fn a_step_stamp_changes_only_with_its_own_sources() {
        let changed = |path: &str| -> Vec<(&'static str, u64)> {
            SOURCES.iter().map(|&(f, h)| (f, if f == path { h ^ 1 } else { h })).collect()
        };
        let differs = |id: &str, path: &str| code(id, SOURCES) != code(id, &changed(path));
        let cockpit = "crates/iaf-tools/src/convert.rs";
        assert!(differs("cockpits", cockpit) && differs("objects", cockpit));
        assert!(!differs("extract", cockpit) && !differs("patch", cockpit) && !differs("theatre", cockpit));
        let ptt = "crates/iaf-formats/src/ptt.rs";
        assert!(differs("theatre", ptt) && !differs("cockpits", ptt) && !differs("extract", ptt));
        let shared = "crates/iaf-formats/src/bytes.rs";
        assert!(differs("extract", shared) && differs("cockpits", shared));
        assert!(!differs("extract", "crates/iaf-tools/src/progress.rs"), "logging decides no output");
        assert!(differs("cockpits", "Cargo.lock:image") && !differs("extract", "Cargo.lock:image"));
        assert!(differs("models", "crates/iaf-tools/data/f15-livery/bird.png"), "a folder's files");
        let steps = "crates/iaf-setup/src/steps.rs";
        assert!(STEP_SOURCES.iter().all(|(id, _)| !differs(id, steps)), "steps.rs: the calls only");
        assert!(differs("extract", "crates/iaf-setup/src/bodies.rs"));
    }

    /// A sim stamp names its inputs relative to the repo, whatever the checkout's path.
    #[test]
    fn sim_inputs_are_relative() {
        let dir = std::env::temp_dir().join(format!("iaf-stamp-rel-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("iaf-2026/data/db")).unwrap();
        std::fs::write(dir.join("iaf-2026/data/db/a.json"), "{}").unwrap();
        let t = describe_under(&dir.join("iaf-2026/data/db"), &dir).unwrap();
        assert!(t.starts_with("input iaf-2026/data/db/a.json 2 "), "{t}");
        assert!(describe_under(&dir.join("nothing"), &dir).unwrap().contains("input nothing missing"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
