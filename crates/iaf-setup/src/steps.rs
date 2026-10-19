//! The steps' work: tools/setup-cli.sh's jobs, through the iaf-tools library (outside programs as child processes).

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::convert::{self, Options};
use iaf_tools::imagery_run::{self, MAPI2015, Run, SENTINEL2};
use iaf_tools::progress::{Progress, check, par_map, threads};
use iaf_tools::{extract, pack, patch, terrain};

use crate::{Ctx, Hebrew, Imagery, Outcome, Step};

/// The cockpits setup converts (every flyable jet).
pub const COCKPITS: [&str; 9] = ["f16", "f15", "f4-2000", "phantom", "cfir", "lavi", "mirage", "mig23", "mig29"];

/// Removes `p`, a folder setup itself writes under `assets` (refuses anything else).
fn remove_dir(assets: &Path, p: &Path) -> Result<()> {
    if !p.starts_with(assets) || p == assets {
        bail!("{}: not a folder under {}", p.display(), assets.display());
    }
    match std::fs::remove_dir_all(p) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e).with_context(|| format!("removing {}", p.display())),
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

/// Runs `cmd`, its output lines into the step's log.
fn child(mut cmd: Command, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let name = format!("{:?}", cmd.get_program());
    let mut c = cmd.stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().with_context(|| format!("running {name}"))?;
    let (out, err) = (c.stdout.take().context("stdout")?, c.stderr.take().context("stderr")?);
    std::thread::scope(|s| {
        s.spawn(|| BufReader::new(err).lines().map_while(Result::ok).for_each(|l| pr.warn(&l)));
        BufReader::new(out).lines().map_while(Result::ok).for_each(|l| pr.log(&l));
    });
    let status = c.wait()?;
    check(cancel)?;
    if !status.success() {
        bail!("{name} failed ({status})");
    }
    Ok(())
}

pub(crate) fn run(step: &Step, ctx: &Ctx, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    let a = &ctx.assets;
    let install = a.join("install");
    let conv = a.join("converted");
    let up = Options { upscale: true, smooth: false };
    let smooth = Options { upscale: true, smooth: true };
    let he = ctx.inputs.hebrew != Hebrew::None;
    // Without Hebrew content the converters see no pack (a pack left by an earlier run is not used).
    let packs = if he { a.join("packs") } else { a.join("packs-none") };
    match step.id {
        "extract" => {
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
        }
        "patch" => {
            let src = ctx.inputs.patch.as_ref().context("no patch given")?;
            let exe = a.join("patch/iafp1_1.exe");
            patch::unwrap(src, &exe, pr)?;
            let v11 = a.join("v1.1");
            remove_dir(a, &v11)?;
            let done = patch::apply(&exe, &install, &v11, pr, cancel)?;
            if done.failed > 0 {
                bail!("{} of {} records not applied", done.failed, done.failed + done.applied);
            }
            let mut files: Vec<String> =
                iaf_tools::walk_files(&v11)?.iter().map(|f| Ok(f.strip_prefix(&v11)?.to_string_lossy().replace('\\', "/"))).collect::<Result<_>>()?;
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
        }
        "fonts" => convert::fonts(&install, &conv.join("fonts"), pr, cancel)?,
        "cockpits" => {
            par_map(&COCKPITS, cancel, |c| convert::cockpit(&install, c, &conv.join("cockpits").join(c), &up, pr, cancel))?;
        }
        "hebrew" => hebrew(ctx, pr, cancel)?,
        "briefings" => convert::briefings(&install, &packs, &conv.join("briefings"), &up, pr, cancel)?,
        "reference" => convert::reference(&install, &conv.join("reference"), &up, pr, cancel)?,
        "menu" => convert::menu(&install, None, &conv.join("menu"), &up, pr, cancel)?,
        "menu_he" => convert::menu(&install, Some(&a.join("packs/he")), &conv.join("menu_he"), &up, pr, cancel)?,
        "arm" => {
            // Extra planes' arming art (docs/adding-a-plane.md §5) for each converted menu set.
            let mut arms: Vec<PathBuf> = std::fs::read_dir(ctx.repo.join("game/extra/planes"))
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
        }
        "keys" => convert::keys(&install, &packs, &conv.join("keys.json"), pr, cancel)?,
        "missions" => convert::missions(&install, &conv.join("missions"), pr, cancel)?,
        "aircraft" => convert::aircraft(&install, &conv.join("missions"), &conv.join("planes"), &smooth, pr, cancel)?,
        "objects" => convert::objects(&install, &conv.join("missions"), &conv.join("objects"), &smooth, pr, cancel)?,
        "theatre" => {
            remove_dir(a, &conv.join("terrain/israel_l4"))?; // the old Israel-only layout
            terrain::theatre(&install.join("resource/terrain/map.ptt"), &conv.join("terrain/theatre"), threads(), pr, cancel)?;
        }
        "airbases" => terrain::airbases(&install, &conv.join("terrain/theatre"), &conv.join("terrain"), None, pr, cancel)?,
        "icon" => convert::icon(&install, &conv.join("icon.png"), pr, cancel)?,
        "launcher" => {
            let mut cmd = Command::new(ctx.repo.join("tools/install-launcher.sh"));
            if let Some(x) = &ctx.xdg_data_home {
                cmd.env("XDG_DATA_HOME", x);
            }
            child(cmd, pr, cancel)?;
        }
        "sentinel2" | "mapi2015" => return imagery(step, ctx, pr, cancel),
        "mapi2015-fetch" => {
            let bases = ctx.inputs.imagery.contains(&Imagery::Mapi2015 { bases: true }) && !ctx.inputs.imagery.contains(&Imagery::Mapi2015 { bases: false });
            let mut cmd = Command::new(ctx.repo.join("tools/imagery/fetch-mapi2015-curl.sh"));
            if bases {
                cmd.arg("--bases");
            }
            child(cmd, pr, cancel)?;
        }
        "guides" => {
            let Some(g) = ctx.guides else { return Ok(Outcome::Skipped("no guide renderer".into())) };
            g(pr, cancel)?;
        }
        other => bail!("unknown step {other}"),
    }
    Ok(Outcome::Done)
}

/// The Hebrew pack `assets/packs/he`, made again from the inputs: every translated briefing and menu file of the
/// Hebrew CD, or the preflight.us packs.
fn hebrew(ctx: &Ctx, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
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
                if std::fs::read(a.join("v1.0/resource").join(rel)).is_ok_and(|orig| std::fs::read(&f).is_ok_and(|d| d == orig)) {
                    std::fs::remove_file(&f)?;
                }
            }
            pack::import(&pick, "he", &install, &a.join("packs"), "resource", pr, cancel)?;
            remove_dir(a, &cd)?;
            remove_dir(a, &pick)?;
        }
    }
    Ok(())
}

/// Progress that drops everything (the Hebrew CD's extraction).
struct Quiet;

impl Progress for Quiet {
    fn log(&self, _line: &str) {}
}

/// A modern imagery layer: the estimate first; nothing to convert (every unit's mark holds) is up to date.
fn imagery(step: &Step, ctx: &Ctx, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    if !crate::tools().gdal {
        return Ok(Outcome::Skipped("GDAL is needed (gdal_translate, gdalbuildvrt)".into()));
    }
    let a = &ctx.assets;
    let spec = if step.id == "sentinel2" { &SENTINEL2 } else { &MAPI2015 };
    let n = threads();
    let mut r = Run {
        spec,
        install: a.join("install"),
        theatre: a.join("converted/terrain/theatre"),
        out: a.join("converted/imagery"),
        sheets: a.join("source/imagery/mapi2015"),
        area: None,
        dry_run: true,
        stale: false,
        threads: if step.id == "sentinel2" { 4 } else if n > 2 { n - 2 } else { 1 },
    };
    if imagery_run::run(&r, pr, cancel)?.to_convert == 0 {
        return Ok(Outcome::UpToDate);
    }
    r.dry_run = false;
    imagery_run::run(&r, pr, cancel)?;
    Ok(Outcome::Done)
}
