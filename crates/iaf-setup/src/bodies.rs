//! The bodies of the steps whose work is in this crate: extract, patch, hebrew and arm (docs/setup.md "A step's
//! sources": these steps' stamps hold this file, not steps.rs).

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::convert;
use iaf_tools::progress::Progress;
use iaf_tools::{extract, pack, patch};

use crate::{Ctx, Hebrew};

/// Removes `p`, a folder setup itself writes under `assets` (refuses anything else).
pub(crate) fn remove_dir(assets: &Path, p: &Path) -> Result<()> {
    if !p.starts_with(assets) || p == assets {
        bail!("{}: not a folder under {}", p.display(), assets.display());
    }
    match std::fs::remove_dir_all(p) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
            Err(e).with_context(|| format!("removing {}", p.display()))
        }
        _ => Ok(()),
    }
}

/// Copies every file under `from` to the same path under `to`.
fn copy_tree(from: &Path, to: &Path) -> Result<()> {
    for f in iaf_tools::walk_files(from)? {
        let dest = to.join(f.strip_prefix(from)?);
        std::fs::create_dir_all(dest.parent().context("no parent")?)?;
        std::fs::copy(&f, &dest).with_context(|| format!("copying {}", f.display()))?;
    }
    Ok(())
}

/// The original install from the CD image into `assets/install`.
pub(crate) fn extract(ctx: &Ctx, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let a = &ctx.assets;
    let install = a.join("install");
    // Files a previous run overlaid from the v1.1 patch: removed first, so the extraction brings back the
    // v1.0 ones and files only v1.1 has do not linger in an unpatched install.
    let manifest = install.join(".v1.1-files");
    if let Ok(list) = std::fs::read_to_string(&manifest) {
        for f in list.lines().filter(|f| !f.is_empty() && !f.contains("..")) {
            let _ = std::fs::remove_file(install.join(f));
        }
        std::fs::remove_file(&manifest)?;
    }
    remove_dir(a, &a.join("v1.0"))?;
    extract::install(&ctx.inputs.cd, &install, pr, cancel)?;
    Ok(())
}

/// The v1.1 patch over the install: the v1.0 originals into `assets/v1.0`, the patched files listed in
/// `install/.v1.1-files`.
pub(crate) fn patch(ctx: &Ctx, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let a = &ctx.assets;
    let install = a.join("install");
    let src = ctx.inputs.patch.as_ref().context("no patch given")?;
    let exe = a.join("patch/iafp1_1.exe");
    patch::unwrap(src, &exe, pr)?;
    let v11 = a.join("v1.1");
    remove_dir(a, &v11)?;
    let done = patch::apply(&exe, &install, &v11, pr, cancel)?;
    if done.failed > 0 {
        bail!("{} of {} records not applied", done.failed, done.failed + done.applied);
    }
    let mut files: Vec<String> = iaf_tools::walk_files(&v11)?
        .iter()
        .map(|f| Ok(f.strip_prefix(&v11)?.to_string_lossy().replace('\\', "/")))
        .collect::<Result<_>>()?;
    files.sort();
    for f in &files {
        if install.join(f).is_file() {
            let dest = a.join("v1.0").join(f);
            std::fs::create_dir_all(dest.parent().context("no parent")?)?;
            std::fs::copy(install.join(f), dest)?;
        }
    }
    copy_tree(&v11, &install)?;
    std::fs::write(install.join(".v1.1-files"), files.iter().map(|f| format!("{f}\n")).collect::<String>())?;
    Ok(())
}

/// The extra planes' arming art (docs/adding-a-plane.md §5) into each converted menu set: every plane's, those whose
/// front view setup makes (arm.json's `front`: the F-15I's, by the models step) once it is there.
pub(crate) fn arm(ctx: &Ctx, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let conv = ctx.assets.join("converted");
    let mut arms: Vec<PathBuf> = std::fs::read_dir(ctx.repo.join("shared/extra/planes"))
        .map(|rd| rd.flatten().map(|e| e.path().join("arm")).filter(|p| p.is_dir()).collect())
        .unwrap_or_default();
    arms.sort();
    for arm in &arms {
        let p = arm.parent().and_then(|p| p.file_name()).context("plane folder")?.to_string_lossy().to_string();
        for m in ["menu", "menu_he"] {
            let img = conv.join(m).join("img");
            if img.join("arm/jets").is_dir() {
                convert::arm_extra(&img, arm, &img.join(format!("arm/jets/x_{p}.png")), pr, cancel)?;
            }
        }
    }
    Ok(())
}

/// The Hebrew pack `assets/packs/he`, made again from the inputs: every translated briefing and menu file of the
/// Hebrew CD, or the preflight.us packs.
pub(crate) fn hebrew(ctx: &Ctx, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let a = &ctx.assets;
    let install = a.join("install");
    remove_dir(a, &a.join("packs/he"))?;
    match &ctx.inputs.hebrew {
        Hebrew::None => {}
        Hebrew::Packs { brief, menu } => {
            for p in [brief, menu].into_iter().flatten() {
                pack::import(p, "he", &install, &a.join("packs"), "resource", pr, cancel)?;
            }
        }
        Hebrew::Cd(iso) => {
            let (cd, pick) = (a.join("hebrew-cd"), a.join("hebrew-cd-pick"));
            remove_dir(a, &cd)?;
            remove_dir(a, &pick)?;
            // The extract is removed however the import ends (done, failed or cancelled).
            let r = (|| -> Result<()> {
                let quiet = Quiet;
                extract::install(iso, &cd, &quiet, cancel)?;
                for d in ["brief", "menu"] {
                    let from = cd.join("resource").join(d);
                    if from.is_dir() {
                        std::fs::create_dir_all(&pick)?;
                        std::fs::rename(&from, pick.join(d))?;
                    }
                }
                // The CD is v1.0: a file it holds as the English v1.0 original is not a translation (the v1.1 patch
                // replaced it in the install), so it stays out of the pack.
                for f in iaf_tools::walk_files(&pick)? {
                    let rel = f.strip_prefix(&pick)?;
                    if std::fs::read(a.join("v1.0/resource").join(rel))
                        .is_ok_and(|orig| std::fs::read(&f).is_ok_and(|d| d == orig))
                    {
                        std::fs::remove_file(&f)?;
                    }
                }
                pack::import(&pick, "he", &install, &a.join("packs"), "resource", pr, cancel)?;
                Ok(())
            })();
            remove_dir(a, &cd)?;
            remove_dir(a, &pick)?;
            r?;
        }
    }
    Ok(())
}

/// Progress that drops everything (the Hebrew CD's extraction).
pub(crate) struct Quiet;

impl Progress for Quiet {
    fn log(&self, _line: &str) {}
}
