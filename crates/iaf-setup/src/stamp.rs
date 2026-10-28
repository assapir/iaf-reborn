//! Step stamps: `<output>.stamp` holds what the step's output was made from (the converters' code, the step's options,
//! a checksum of each outside file it reads, the stamps of the steps it waits for). The same text again: up to date.

use std::io::Read;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

use crate::{Ctx, Hebrew, Step};

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
        "arm" => (None, conv("arm.stamp"), vec![ctx.repo.join("game/extra/planes")]),
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
    let mut text = format!("iaf-setup {}\nstep {}\n", env!("SETUP_CODE"), step.id);
    if step.id == "launcher" {
        text += &format!("repo {}\nxdg {:?}\n", ctx.repo.display(), ctx.xdg_data_home);
    }
    for p in &inputs {
        text += &describe(p)?;
    }
    Ok(Some(Stamp { path: stamp, text, output: out }))
}
