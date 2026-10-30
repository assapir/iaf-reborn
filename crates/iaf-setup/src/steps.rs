//! The steps' work: tools/setup-cli.sh's jobs, through the iaf-tools library (outside programs as child processes).

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::convert::{self, Options};
use iaf_tools::imagery_run::{self, MAPI2015, Run, SENTINEL2};
use iaf_tools::progress::{Progress, check, par_map, threads};
use iaf_tools::{extract, f15, foliage, pack, patch, terrain, thirdparty};

use crate::{Ctx, Hebrew, Imagery, Outcome, Step};

/// The cockpits setup converts (every flyable jet).
pub const COCKPITS: [&str; 9] = ["f16", "f15", "f4-2000", "phantom", "cfir", "lavi", "mirage", "mig23", "mig29"];

/// Removes `p`, a folder setup itself writes under `assets` (refuses anything else).
fn remove_dir(assets: &Path, p: &Path) -> Result<()> {
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

/// What the setup writes under `assets/` (folders and files), which the CD launcher's UNINSTALL removes
/// (docs/setup.md "Uninstall"). Anything else there (the decompile, the manuals) stays.
pub const OUTPUTS: &[&str] = &[
    "install",
    "install.stamp",
    "v1.0",
    "v1.1",
    "v1.1.stamp",
    "patch",
    "converted",
    "packs-none",
    "hebrew-cd",
    "hebrew-cd-pick",
    "setup.json",
];

/// What the setup keeps on an uninstall unless asked: the imported packs (the pack zips may be gone) and the
/// downloads (imagery: hours and tens of GB to fetch again; the scenery's and the F-15's sources; the third-party
/// textures).
pub const KEPT: &[&str] = &["packs", "source/imagery", "source/scenery", "source/roads", "source/f15", "thirdparty"];

/// Removes the setup's outputs ([`OUTPUTS`]) from `assets`, and with `everything` the [`KEPT`] ones too; a
/// missing one is fine.
pub fn uninstall(assets: &Path, everything: bool) -> Result<()> {
    let kept: &[&str] = if everything { KEPT } else { &[] };
    for name in OUTPUTS.iter().chain(kept) {
        let p = assets.join(name);
        if p.is_dir() {
            remove_dir(assets, &p)?;
        } else if p.exists() {
            std::fs::remove_file(&p).with_context(|| format!("removing {}", p.display()))?;
        }
    }
    Ok(())
}

/// The bytes of the files under `p` (a file: its size; missing: 0), for the wizard's expected size.
pub fn disk_bytes(p: &Path) -> u64 {
    let files = if p.is_dir() { iaf_tools::walk_files(p).unwrap_or_default() } else { vec![p.to_path_buf()] };
    files.iter().filter_map(|f| std::fs::metadata(f).ok()).map(|m| m.len()).sum()
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

/// `p` without Windows' verbatim prefix (`\\?\C:\…` → `C:\…`, `\\?\UNC\server\…` → `\\server\…`): PowerShell's
/// -File leaves a verbatim script's $PSScriptRoot empty.
fn plain_path(p: &Path) -> String {
    let s = p.to_string_lossy();
    if let Some(unc) = s.strip_prefix(r"\\?\UNC\") {
        format!(r"\\{unc}")
    } else {
        s.strip_prefix(r"\\?\").unwrap_or(&s).to_string()
    }
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
        }
        "fonts" => convert::fonts(&install, &conv.join("fonts"), pr, cancel)?,
        "cockpits" => {
            par_map(&COCKPITS, cancel, |c| {
                convert::cockpit(&install, c, &conv.join("cockpits").join(c), &up, pr, cancel)
            })?;
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
            terrain::theatre(
                &install.join("resource/terrain/map.ptt"),
                &conv.join("terrain/theatre"),
                threads(),
                pr,
                cancel,
            )?;
        }
        "airbases" => {
            terrain::airbases(&install, &conv.join("terrain/theatre"), &conv.join("terrain"), None, pr, cancel)?
        }
        "icon" => convert::icon(&install, &conv.join("icon.png"), pr, cancel)?,
        "launcher" => {
            let cmd = if cfg!(windows) {
                // Start Menu shortcuts (with xdg_data_home: into a folder there instead).
                let script = plain_path(&ctx.repo.join(r"tools\windows\install-launcher.ps1"));
                let mut c = Command::new("powershell");
                c.args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", &script]);
                if let Some(x) = &ctx.xdg_data_home {
                    c.args(["-Menu", &plain_path(&x.join("Start Menu"))]);
                }
                c
            } else {
                let mut c = Command::new(ctx.repo.join("tools/install-launcher.sh"));
                if let Some(x) = &ctx.xdg_data_home {
                    c.env("XDG_DATA_HOME", x);
                }
                c
            };
            child(cmd, pr, cancel)?;
        }
        "sentinel2" | "mapi2015" => return imagery(step, ctx, pr, cancel),
        "textures" => return textures(&a.join("thirdparty/ambientcg"), thirdparty::AMBIENTCG, pr, cancel),
        "scenery-fetch" => {
            let list = ctx.inputs.scenery_kinds.downloads();
            let scenery = scenery_fetch(&list, &a.join("source/scenery"), SCENERY_PROBE, pr, cancel)?;
            // The road layer's other countries (docs/scenery.md §1.1), each optional.
            if matches!(scenery, Outcome::Skipped(_))
                || thirdparty::ROADS.iter().all(|d| thirdparty::file_done(&a.join("source/roads"), d))
            {
                return Ok(scenery);
            }
            iaf_tools::roads::fetch(a, pr, cancel)?;
            return Ok(Outcome::Done);
        }
        "scenery" => return scenery(a, ctx.inputs.scenery_kinds, pr, cancel),
        "models" => return f15(a, F15_PROBE, pr, cancel),
        "bc1" => {
            let mut dirs = vec![conv.join("terrain/theatre")];
            // Only the imagery layers the game is set to show (each layer's .dds is ~4.5 GB); without the game's
            // settings every converted layer. A layer chosen later loads through the CPU fallback until the next run.
            let chosen = game_imagery_layers();
            if let Ok(rd) = std::fs::read_dir(conv.join("imagery")) {
                dirs.extend(rd.flatten().map(|e| e.path()).filter(|p| {
                    let name = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                    p.is_dir() && !name.starts_with('.') && chosen.as_ref().is_none_or(|c| c.contains(&name))
                }));
            }
            dirs.sort();
            if iaf_tools::bc1::trees(&dirs, pr, cancel)? == 0 {
                return Ok(Outcome::UpToDate);
            }
        }
        "imagery-refresh" => {
            let mut any = false;
            for spec in [&SENTINEL2, &MAPI2015] {
                let id = if std::ptr::eq(spec, &SENTINEL2) { "sentinel2" } else { "mapi2015" };
                let chosen = ctx.inputs.imagery.iter().any(|m| {
                    matches!((m, id), (Imagery::Sentinel2, "sentinel2") | (Imagery::Mapi2015 { .. }, "mapi2015"))
                });
                if chosen || !a.join("converted/imagery").join(id).is_dir() {
                    continue;
                }
                if id == "mapi2015" && !a.join("source/imagery/mapi2015").is_dir() {
                    pr.warn("the Survey sheets are not here (assets/source/imagery/mapi2015): the mapi2015 units keep their older rules");
                    continue;
                }
                let mut r = imagery_job(ctx, spec, true);
                r.stale = true;
                if imagery_run::run(&r, pr, cancel)?.to_convert > 0 {
                    r.dry_run = false;
                    imagery_run::run(&r, pr, cancel)?;
                    any = true;
                }
            }
            if !any {
                return Ok(Outcome::UpToDate);
            }
        }
        "mapi2015-fetch" => {
            let bases = ctx.inputs.imagery.contains(&Imagery::Mapi2015 { bases: true })
                && !ctx.inputs.imagery.contains(&Imagery::Mapi2015 { bases: false });
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
struct Quiet;

impl Progress for Quiet {
    fn log(&self, _line: &str) {}
}

/// The third-party textures (iaf_tools::thirdparty::LISTS) into `dir` from `base`: up to date when every material is
/// there; skipped (the game's switch then stays Original) when `base` cannot be reached.
/// The imagery layers the game's settings.cfg chooses (`imagery_israel`, `imagery_outside`; "original" is no layer),
/// None when the file is missing or names neither (then every layer is compressed).
fn game_imagery_layers() -> Option<Vec<String>> {
    // Windows: Godot's user data is under %APPDATA% (no HOME there).
    if let Some(appdata) = std::env::var_os("APPDATA").filter(|_| cfg!(windows)) {
        let cfg = PathBuf::from(appdata).join("Godot/app_userdata/iaf-reborn/settings.cfg");
        return imagery_layers_in(&std::fs::read_to_string(cfg).ok()?);
    }
    let home = PathBuf::from(std::env::var_os("HOME")?);
    let data = std::env::var_os("XDG_DATA_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".local/share"));
    let cfg = [
        data.join("godot/app_userdata/iaf-reborn/settings.cfg"),
        home.join("Library/Application Support/Godot/app_userdata/iaf-reborn/settings.cfg"),
    ]
    .iter()
    .find_map(|p| std::fs::read_to_string(p).ok())?;
    imagery_layers_in(&cfg)
}

/// `imagery_israel` / `imagery_outside` values of a Godot ConfigFile text other than "original".
fn imagery_layers_in(cfg: &str) -> Option<Vec<String>> {
    let mut seen = false;
    let mut out = Vec::new();
    for line in cfg.lines() {
        let Some((k, v)) = line.split_once('=') else { continue };
        if matches!(k.trim(), "imagery_israel" | "imagery_outside") {
            seen = true;
            let v = v.trim().trim_matches('"').to_string();
            if v != "original" && !v.is_empty() {
                out.push(v);
            }
        }
    }
    seen.then_some(out)
}

fn textures(dir: &Path, base: &str, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    let all = || thirdparty::LISTS.iter().flat_map(|(_, l)| l.iter());
    if all().all(|m| thirdparty::is_done(dir, m)) && foliage::is_done(dir) {
        return Ok(Outcome::UpToDate);
    }
    if !reachable(base) {
        return Ok(Outcome::Skipped(
            "ambientcg.com cannot be reached (offline?): Ground textures and Model detail stay Original, scenery trees plain; run setup again online".into(),
        ));
    }
    for (name, list) in thirdparty::LISTS {
        thirdparty::fetch(name, list, base, dir, pr, cancel)?;
    }
    if !foliage::is_done(dir) {
        pr.log("composing the scenery trees' foliage");
        foliage::build(dir)?;
    }
    Ok(Outcome::Done)
}

/// True when `url`'s server answers: any answer will do (no -f); no connection is offline.
fn reachable(url: &str) -> bool {
    Command::new("curl")
        .args(["-sI", "--max-time", "15", url])
        .stdout(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

/// The detailed F-15 (iaf_tools::f15, docs/aircraft-models.md §6): its FlightGear sources into `assets/source/f15`
/// (kept), then the model; skipped (the F-15 stays Original with Models Detailed) when GitHub cannot be reached.
fn f15(a: &Path, probe: &str, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    let src = a.join("source/f15");
    if !f15::SOURCE.iter().all(|d| thirdparty::file_done(&src, d)) && !reachable(probe) {
        return Ok(Outcome::Skipped(
            "GitHub cannot be reached (offline?): the F-15 stays Original with Models Detailed; run setup again online"
                .into(),
        ));
    }
    f15::setup(a, pr, cancel)?;
    Ok(Outcome::Done)
}

/// Answers when the F-15's sources can be downloaded.
const F15_PROBE: &str = "https://raw.githubusercontent.com/";

/// Answers when the scenery's sources can be downloaded (Geofabrik, the largest).
const SCENERY_PROBE: &str = "https://download.geofabrik.de/";

/// The scenery's sources the chosen kinds need (`list`, from iaf_tools::thirdparty::SCENERY) into `dir`: up to date
/// when every file is there; skipped (Scenery then stays off in the game) when `probe` cannot be reached.
fn scenery_fetch(
    list: &[thirdparty::Download],
    dir: &Path,
    probe: &str,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<Outcome> {
    if list.iter().all(|d| thirdparty::file_done(dir, d)) {
        return Ok(Outcome::UpToDate);
    }
    if !reachable(probe) {
        return Ok(Outcome::Skipped(
            "the scenery's sources cannot be reached (offline?): Scenery stays off; run setup again online".into(),
        ));
    }
    thirdparty::fetch_files(list, dir, pr, cancel)?;
    Ok(Outcome::Done)
}

/// The road layer (iaf_tools::roads), the scenery cells and the city lights' buildings (iaf_tools::scenery): skipped
/// without GDAL or the sources; the cells and lights also without the Survey 2 m layer.
fn scenery(a: &Path, kinds: iaf_tools::scenery::Kinds, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    if !crate::tools().gdal {
        return Ok(Outcome::Skipped("GDAL is needed (gdalwarp, ogr2ogr)".into()));
    }
    if !kinds.downloads().iter().all(|d| thirdparty::file_done(&a.join("source/scenery"), d)) {
        return Ok(Outcome::Skipped("the scenery's sources are not downloaded (step scenery-fetch)".into()));
    }
    // The road layer (docs/scenery.md §6) needs only the OpenStreetMap extract.
    let roads = iaf_tools::roads::build(a, pr, cancel)?.up_to_date;
    if !a.join("converted/imagery/mapi2015/L1").is_dir() {
        return Ok(Outcome::Skipped("Scenery needs the Survey of Israel 2 m layer (imagery mapi2015)".into()));
    }
    let r = iaf_tools::scenery::Run { assets: a.to_path_buf(), near: None, kinds };
    let cells = iaf_tools::scenery::build(&r, pr, cancel)?.up_to_date;
    // The city lights' buildings where the scenery stops (docs/rendering.md §5.1).
    let lights = iaf_tools::scenery::build_lights(&r, pr, cancel)?.up_to_date;
    Ok(if cells && lights && roads { Outcome::UpToDate } else { Outcome::Done })
}

/// A modern imagery layer: the estimate first; nothing to convert (every unit's mark holds) is up to date.
fn imagery(step: &Step, ctx: &Ctx, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    if !crate::tools().gdal {
        return Ok(Outcome::Skipped("GDAL is needed (gdal_translate, gdalbuildvrt)".into()));
    }
    let spec = if step.id == "sentinel2" { &SENTINEL2 } else { &MAPI2015 };
    let mut r = imagery_job(ctx, spec, true);
    if imagery_run::run(&r, pr, cancel)?.to_convert == 0 {
        return Ok(Outcome::UpToDate);
    }
    r.dry_run = false;
    imagery_run::run(&r, pr, cancel)?;
    Ok(Outcome::Done)
}

/// An imagery run on `ctx`'s assets (sentinel2: 4 network workers; mapi2015: all cores but two).
fn imagery_job(ctx: &Ctx, spec: &'static imagery_run::Spec, dry_run: bool) -> Run {
    let a = &ctx.assets;
    let n = threads();
    Run {
        spec,
        install: a.join("install"),
        theatre: a.join("converted/terrain/theatre"),
        out: a.join("converted/imagery"),
        sheets: a.join("source/imagery/mapi2015"),
        area: None,
        dry_run,
        stale: false,
        threads: if std::ptr::eq(spec, &SENTINEL2) {
            4
        } else if n > 2 {
            n - 2
        } else {
            1
        },
    }
}

/// The units of the imagery layer `id` ("sentinel2", "mapi2015") on disk that older rules made (what
/// "imagery-refresh" converts again); 0 without the layer or the theatre. sentinel2 lists WorldCover over the network.
pub fn imagery_stale(assets: &Path, id: &str) -> Result<usize> {
    let spec = match id {
        "sentinel2" => &SENTINEL2,
        "mapi2015" => &MAPI2015,
        _ => bail!("unknown imagery layer {id}"),
    };
    if !assets.join("converted/imagery").join(id).is_dir()
        || !assets.join("converted/terrain/theatre/meta.json").is_file()
    {
        return Ok(0);
    }
    let ctx = Ctx {
        assets: assets.to_path_buf(),
        repo: PathBuf::new(),
        inputs: crate::Inputs::default(),
        xdg_data_home: None,
        guides: None,
    };
    let mut r = imagery_job(&ctx, spec, true);
    r.stale = true;
    Ok(imagery_run::run(&r, &Quiet, &AtomicBool::new(false))?.to_convert)
}

/// The scripted pilot guides: tools/guide_shots.sh (real renders, a display needed) then tools/guide_pdf.py, output
/// into the log.
pub fn script_guides(repo: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    if cfg!(windows) {
        bail!("the pilot guides' pictures are made by a bash script (tools/guide_shots.sh): not on Windows yet");
    }
    let mut shots = Command::new(repo.join("tools/guide_shots.sh"));
    shots.current_dir(repo);
    child(shots, pr, cancel)?;
    let mut pdf = Command::new("python3");
    pdf.args(["-I", "tools/guide_pdf.py"]).current_dir(repo);
    child(pdf, pr, cancel)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uninstall_removes_only_the_setups_outputs() {
        let a = std::env::temp_dir().join(format!("iaf-uninstall-{}", std::process::id()));
        for d in ["install/resource", "converted/terrain", "source/imagery/mapi2015", "source/keep", "ghidra"] {
            std::fs::create_dir_all(a.join(d)).unwrap();
        }
        for f in ["setup.json", "install.stamp", "converted/terrain/x.json", "ghidra/iafjets.c"] {
            std::fs::write(a.join(f), "x").unwrap();
        }
        uninstall(&a, true).unwrap();
        for gone in ["install", "converted", "source/imagery", "setup.json", "install.stamp"] {
            assert!(!a.join(gone).exists(), "{gone} removed");
        }
        assert!(a.join("ghidra/iafjets.c").exists() && a.join("source/keep").is_dir(), "the rest stays");
        uninstall(&a, true).unwrap(); // nothing left to remove: fine
        assert_eq!(disk_bytes(&a), 1, "ghidra/iafjets.c");
        assert_eq!(disk_bytes(&a.join("nothing")), 0);
        std::fs::remove_dir_all(&a).unwrap();
    }
}

#[cfg(test)]
mod textures_tests {
    use super::*;

    #[test]
    fn textures_skip_offline() {
        let dir = std::env::temp_dir().join(format!("iaf-setup-textures-{}", std::process::id()));
        let r = textures(&dir, "http://127.0.0.1:9/", &Quiet, &AtomicBool::new(false)).unwrap();
        assert!(matches!(r, Outcome::Skipped(ref w) if w.contains("Original")));
        assert!(!dir.exists(), "nothing written");
        let list = thirdparty::SCENERY;
        let r = scenery_fetch(list, &dir, "http://127.0.0.1:9/", &Quiet, &AtomicBool::new(false)).unwrap();
        assert!(matches!(r, Outcome::Skipped(ref w) if w.contains("offline")));
        assert!(!dir.exists(), "nothing written");
        let r = f15(&dir, "http://127.0.0.1:9/", &Quiet, &AtomicBool::new(false)).unwrap();
        assert!(matches!(r, Outcome::Skipped(ref w) if w.contains("F-15 stays Original")));
        assert!(!dir.exists(), "nothing written");
    }
}

#[cfg(test)]
mod uninstall_tests {
    use super::*;

    #[test]
    fn keeps_packs_and_downloads_unless_asked() {
        let dir = std::env::temp_dir().join(format!("iaf-setup-uninstall-{}", std::process::id()));
        let make = || {
            for d in ["install/resource", "converted/fonts", "packs/he", "source/imagery/x", "manual_en"] {
                std::fs::create_dir_all(dir.join(d)).unwrap();
            }
            std::fs::write(dir.join("setup.json"), "{}").unwrap();
        };
        make();
        uninstall(&dir, false).unwrap();
        assert!(!dir.join("install").exists() && !dir.join("converted").exists() && !dir.join("setup.json").exists());
        assert!(
            dir.join("packs/he").exists() && dir.join("source/imagery/x").exists() && dir.join("manual_en").exists()
        );
        uninstall(&dir, true).unwrap();
        assert!(!dir.join("packs").exists() && !dir.join("source/imagery").exists() && dir.join("manual_en").exists());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}

#[cfg(test)]
mod bc1_layer_tests {
    #[test]
    fn imagery_layers_from_settings() {
        let cfg = "[game]\nimagery_israel=\"mapi2015_modern\"\nimagery_outside=\"sentinel2_modern\"\n";
        assert_eq!(super::imagery_layers_in(cfg).unwrap(), ["mapi2015_modern", "sentinel2_modern"]);
        let off = "imagery_israel=\"original\"\nimagery_outside=\"original\"\n";
        assert_eq!(super::imagery_layers_in(off).unwrap(), Vec::<String>::new());
        assert!(super::imagery_layers_in("[game]\nlanguage=\"he\"\n").is_none());
    }
}
