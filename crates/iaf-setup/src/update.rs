//! The release bundles' update on start (docs/release.md §7): which nightly is newer, the download for this game and
//! system, its check, and the swap of the game's folder; and setup's own update on start: the steps whose stamps no
//! longer hold, with what each would download.

use std::cmp::Ordering;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering as AtomicOrdering};

use anyhow::{Context, Result, bail};
use sha2::{Digest, Sha256};

use crate::sim::{SimCtx, SimInputs};
use crate::{Ctx, Step};

/// A nightly's version: `<major>.<minor>.<patch>-nightly.<YYYYMMDD>+<short hash>` (tools/release/bundle.sh).
#[derive(Debug, PartialEq, Eq)]
pub struct Version {
    pub base: [u32; 3],
    pub date: u32,
    pub hash: String,
}

/// `v` as a nightly's version; None for anything else ("dev", the checkout's).
pub fn parse(v: &str) -> Option<Version> {
    let (base, rest) = v.trim().split_once("-nightly.")?;
    let (date, hash) = rest.split_once('+')?;
    let mut b = base.split('.').map(|n| n.parse::<u32>().ok());
    let base = [b.next()??, b.next()??, b.next()??];
    if b.next().is_some() || date.len() != 8 || hash.is_empty() {
        return None;
    }
    Some(Version { base, date: date.parse().ok()?, hash: hash.into() })
}

/// True when the release's `remote` should replace `own`: a later base or day; on the same base and day a different
/// build (the rolling nightly is the latest one). Never from or to a version that is not a nightly's.
pub fn newer(own: &str, remote: &str) -> bool {
    let (Some(o), Some(r)) = (parse(own), parse(remote)) else { return false };
    match (r.base, r.date).cmp(&(o.base, o.date)) {
        Ordering::Greater => true,
        Ordering::Equal => r.hash != o.hash,
        Ordering::Less => false,
    }
}

/// The nightly's download of `project` (modern-iaf, iaf-reborn) for Godot's OS name `os` (Linux, macOS, Windows).
pub fn asset(project: &str, os: &str) -> Option<String> {
    let tail = match os {
        "Linux" => "linux-x86_64.tar.gz",
        "macOS" => "macos-arm64.dmg",
        "Windows" => "windows-x86_64.zip",
        _ => return None,
    };
    matches!(project, "modern-iaf" | "iaf-reborn").then(|| format!("{project}-nightly-{tail}"))
}

/// One download of the release, as its manifest (`nightly.json`, tools/release/manifest.sh) lists it.
#[derive(Debug, PartialEq, Eq)]
pub struct Offer {
    pub name: String,
    pub version: String,
    pub size: u64,
    pub sha256: String,
}

/// The manifest's entry for `project` on `os`; None when the manifest does not list it or cannot be read.
pub fn pick(manifest: &str, project: &str, os: &str) -> Option<Offer> {
    let name = asset(project, os)?;
    let v: serde_json::Value = serde_json::from_str(manifest).ok()?;
    let a = v["assets"].as_array()?.iter().find(|a| a["name"] == name.as_str())?;
    Some(Offer {
        name,
        version: a["version"].as_str()?.into(),
        size: a["size"].as_u64()?,
        sha256: a["sha256"].as_str()?.to_ascii_lowercase(),
    })
}

/// Ok when `file` has `size` bytes and the SHA-256 `sha256` (hex); an error "cancelled" once `stop` is set.
pub fn verify(file: &Path, size: u64, sha256: &str, stop: &AtomicBool) -> Result<()> {
    let len = std::fs::metadata(file).with_context(|| format!("{}", file.display()))?.len();
    if len != size {
        bail!("{}: {len} bytes, the release lists {size}", file.display());
    }
    let mut f = std::fs::File::open(file)?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        if stop.load(AtomicOrdering::Relaxed) {
            bail!("cancelled");
        }
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    let got: String = h.finalize().iter().map(|b| format!("{b:02x}")).collect();
    if !got.eq_ignore_ascii_case(sha256) {
        bail!("{}: SHA-256 {got}, the release lists {sha256}", file.display());
    }
    Ok(())
}

/// The game's folder from its program `exe`: the program's folder; on macOS the `.app` (`Contents/MacOS/<name>`).
pub fn app_dir(exe: &Path, os: &str) -> PathBuf {
    let dir = exe.parent().unwrap_or(exe);
    if os == "macOS" { dir.parent().and_then(Path::parent).unwrap_or(dir).into() } else { dir.into() }
}

/// Beside the game's folder `app`, with a leading dot: `.<name>.<tag>`.
fn beside(app: &Path, tag: &str) -> PathBuf {
    let name = app.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    app.with_file_name(format!(".{name}.{tag}"))
}

/// Where the new version is unpacked (the folder it then runs from once, to swap).
pub fn stage_dir(app: &Path) -> PathBuf {
    beside(app, "update")
}

/// Where the old version waits until the new one has started.
pub fn old_dir(app: &Path) -> PathBuf {
    beside(app, "old")
}

/// Unpacks the download `archive` into `stage` (emptied first) and returns the new game's folder in it (the folder
/// or `.app` with the same name as `app`). Linux: tar; Windows: the zip; macOS: the disk image, attached read-only
/// and the app copied out with ditto (it keeps the signature and the links). Once `stop` is set the tool is stopped,
/// the stage removed and the error is "cancelled".
pub fn unpack(archive: &Path, stage: &Path, app: &Path, os: &str, stop: &AtomicBool) -> Result<PathBuf> {
    let r = unpack_into(archive, stage, app, os, stop);
    if stop.load(AtomicOrdering::Relaxed) {
        let _ = std::fs::remove_dir_all(stage);
        bail!("cancelled");
    }
    r
}

fn unpack_into(archive: &Path, stage: &Path, app: &Path, os: &str, stop: &AtomicBool) -> Result<PathBuf> {
    let _ = std::fs::remove_dir_all(stage);
    std::fs::create_dir_all(stage)?;
    let name = app.file_name().context("the game's folder has no name")?;
    match os {
        "Linux" => run_until(Command::new("tar").arg("-xzf").arg(archive).arg("-C").arg(stage), stop)?,
        "Windows" => zip::ZipArchive::new(std::fs::File::open(archive)?)?.extract(stage)?,
        "macOS" => {
            let mnt = stage.join(".mnt");
            std::fs::create_dir_all(&mnt)?;
            // diskutil image where diskutil has it (hdiutil is deprecated there and warns); hdiutil on older macOS.
            let diskutil = run(Command::new("diskutil")
                .args(["image", "attach", "--readOnly", "--mountOptions", "nobrowse", "--mountPoint"])
                .arg(&mnt)
                .arg(archive))
            .is_ok();
            if !diskutil {
                run(Command::new("hdiutil")
                    .args(["attach", "-nobrowse", "-readonly", "-mountpoint"])
                    .arg(&mnt)
                    .arg(archive))?;
            }
            let copied = run_until(Command::new("ditto").arg(mnt.join(name)).arg(stage.join(name)), stop);
            let _ = match diskutil {
                true => run(Command::new("diskutil").args(["eject", "force"]).arg(&mnt)),
                false => run(Command::new("hdiutil").arg("detach").arg(&mnt).arg("-force")),
            };
            let _ = std::fs::remove_dir(&mnt);
            copied?;
        }
        _ => bail!("no update for {os}"),
    }
    let new = stage.join(name);
    if !new.is_dir() {
        bail!("the download holds no {}", name.to_string_lossy());
    }
    Ok(new)
}

/// [`run`], stopped (killed) once `stop` is set.
fn run_until(c: &mut Command, stop: &AtomicBool) -> Result<()> {
    let mut child = c.stdout(Stdio::null()).stderr(Stdio::piped()).spawn().with_context(|| format!("{c:?}"))?;
    while child.try_wait()?.is_none() {
        if stop.load(AtomicOrdering::Relaxed) {
            let _ = child.kill();
            let _ = child.wait();
            bail!("cancelled");
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    let out = child.wait_with_output()?;
    if !out.status.success() {
        bail!("{c:?}: {}", String::from_utf8_lossy(&out.stderr).trim());
    }
    Ok(())
}

fn run(c: &mut Command) -> Result<()> {
    let out = c.output().with_context(|| format!("{c:?}"))?;
    if !out.status.success() {
        bail!("{c:?}: {}", String::from_utf8_lossy(&out.stderr).trim());
    }
    Ok(())
}

/// The swap, run by the new version from `new` once the old one has quit: the game's folder `app` moves to
/// [`old_dir`], `new` is copied to `app`. A failed copy puts the old folder back. Refused while an earlier update's
/// old folder is still there (`cleanup` first). On Windows a folder stays locked a moment after its program quit:
/// the move is tried again for up to 30 s.
pub fn swap(app: &Path, new: &Path) -> Result<()> {
    let old = old_dir(app);
    if old.exists() {
        bail!("an earlier update's old version is still at {}", old.display());
    }
    let mut tries = 0;
    while let Err(e) = std::fs::rename(app, &old) {
        tries += 1;
        if tries >= 60 {
            return Err(e).with_context(|| format!("{} to {}", app.display(), old.display()));
        }
        std::thread::sleep(std::time::Duration::from_millis(500));
    }
    if let Err(e) = copy_tree(new, app) {
        rollback(app).with_context(|| format!("{e:#}; and the old version is not back"))?;
        return Err(e);
    }
    Ok(())
}

/// [`swap`], and whether the game's folder still holds a runnable old version after a failure (the move never
/// happened, or the copy failed and the old one is back): "" and true when it swapped.
pub fn swap_or_keep(app: &Path, new: &Path) -> (String, bool) {
    let had_old = old_dir(app).exists();
    match swap(app, new) {
        Ok(()) => (String::new(), true),
        Err(e) => (format!("{e:#}"), had_old || !old_dir(app).exists()),
    }
}

/// How the new version's first start went ([`start_and_wait`]).
#[derive(Debug, PartialEq, Eq)]
pub enum Start {
    /// It wrote its started file.
    Started,
    /// It ended without writing it.
    Ended,
    /// It still ran after the time given without writing it, and was stopped.
    Stopped,
}

/// Starts `exe` with `args` in `cwd` ([`launch`]'s rules) and waits for it to write `started`, end, or run past `secs`
/// (then it is stopped). A start that is slow but alive is waited for to the end of `secs`.
pub fn start_and_wait(exe: &Path, args: &[String], cwd: &Path, started: &Path, secs: f64) -> Result<Start> {
    let mut child =
        Command::new(exe).args(args).current_dir(cwd).spawn().with_context(|| format!("{}", exe.display()))?;
    let end = std::time::Instant::now() + std::time::Duration::from_secs_f64(secs);
    loop {
        if started.exists() {
            return Ok(Start::Started);
        }
        if child.try_wait()?.is_some() {
            return Ok(if started.exists() { Start::Started } else { Start::Ended });
        }
        if std::time::Instant::now() >= end {
            let _ = child.kill();
            let _ = child.wait();
            return Ok(Start::Stopped);
        }
        std::thread::sleep(std::time::Duration::from_millis(300));
    }
}

/// The old version back in `app` (the new one failed to copy or to start). The new one moves aside first and goes
/// only once the old one is in place; when that move fails, the new one is put back.
pub fn rollback(app: &Path) -> Result<()> {
    let old = old_dir(app);
    if !old.is_dir() {
        bail!("no old version at {}", old.display());
    }
    let failed = beside(app, "failed");
    let _ = std::fs::remove_dir_all(&failed);
    if app.exists() {
        std::fs::rename(app, &failed).with_context(|| format!("{} to {}", app.display(), failed.display()))?;
    }
    if let Err(e) = std::fs::rename(&old, app) {
        let _ = std::fs::rename(&failed, app);
        return Err(e).with_context(|| format!("{} to {}", old.display(), app.display()));
    }
    let _ = std::fs::remove_dir_all(&failed);
    Ok(())
}

/// After the new version started from `app`, or before a new download: the old folder and the unpacked download
/// go, except the folder this program runs from.
pub fn cleanup(app: &Path) {
    let me = std::env::current_exe().unwrap_or_default();
    for d in [old_dir(app), stage_dir(app), beside(app, "failed")] {
        if !me.starts_with(&d) {
            let _ = std::fs::remove_dir_all(d);
        }
    }
}

/// True when process `pid` runs (not a child of ours: Godot's OS.is_process_running knows only those). A zombie (ended,
/// not yet reaped by its parent) has ended.
#[cfg(unix)]
pub fn running(pid: u32) -> bool {
    Command::new("ps")
        .args(["-o", "stat=", "-p", &pid.to_string()])
        .stderr(std::process::Stdio::null())
        .output()
        .is_ok_and(|o| o.status.success() && !String::from_utf8_lossy(&o.stdout).trim().starts_with('Z'))
}

#[cfg(windows)]
pub fn running(pid: u32) -> bool {
    use std::os::windows::process::CommandExt;
    // CREATE_NO_WINDOW: no console flashes over the game.
    Command::new("tasklist")
        .args(["/FI", &format!("PID eq {pid}"), "/NH", "/FO", "CSV"])
        .creation_flags(0x0800_0000)
        .output()
        .is_ok_and(|o| String::from_utf8_lossy(&o.stdout).contains(&format!("\"{pid}\"")))
}

/// Waits up to `secs` for process `pid` to end; true when it did (at once for 0: no process).
pub fn wait_exit(pid: u32, secs: f64) -> bool {
    if pid == 0 {
        return true;
    }
    let end = std::time::Instant::now() + std::time::Duration::from_secs_f64(secs);
    while running(pid) {
        if std::time::Instant::now() >= end {
            return false;
        }
        std::thread::sleep(std::time::Duration::from_millis(300));
    }
    true
}

/// Starts `exe` with `args` in the folder `cwd` (never the game's own folder: on Windows a program's working folder
/// cannot be moved) and returns its process id.
pub fn launch(exe: &Path, args: &[String], cwd: &Path) -> Result<u32> {
    Ok(Command::new(exe).args(args).current_dir(cwd).spawn().with_context(|| format!("{}", exe.display()))?.id())
}

/// `from` copied to `to`, links as links (a macOS app's frameworks), the files' permissions kept.
fn copy_tree(from: &Path, to: &Path) -> Result<()> {
    std::fs::create_dir_all(to)?;
    for e in std::fs::read_dir(from)? {
        let e = e?;
        let (src, dst) = (e.path(), to.join(e.file_name()));
        let t = e.file_type()?;
        if t.is_dir() {
            copy_tree(&src, &dst)?;
        } else if t.is_symlink() {
            link(&std::fs::read_link(&src)?, &dst)?;
        } else {
            std::fs::copy(&src, &dst).with_context(|| format!("{}", dst.display()))?;
        }
    }
    Ok(())
}

#[cfg(unix)]
fn link(target: &Path, at: &Path) -> Result<()> {
    Ok(std::os::unix::fs::symlink(target, at)?)
}

#[cfg(not(unix))]
fn link(target: &Path, at: &Path) -> Result<()> {
    bail!("a link in the download: {} -> {}", at.display(), target.display())
}

/// A setup step a run would do again: its stamp no longer holds (its code or its inputs changed, or a newer version
/// added it). `download`: the bytes of the free sources it would fetch first, 0 when they are all on disk, -1 when
/// it fetches some of unknown size.
#[derive(Debug, PartialEq)]
pub struct Stale {
    pub id: &'static str,
    pub title: &'static str,
    pub download: i64,
}

/// The steps of the last run's choices in `assets` that a run would do again, for Jane's IAF reborn (`sim` false:
/// setup.json's inputs) or Modern IAF (`sim` true: the steps left out, with the Survey photo and its missing
/// sheets). Empty before the first run. Steps that keep no stamp (imagery, the scenery's fetch, the guides) decide
/// for themselves when they run and are left out, as is the launcher in a release bundle (it has none); the Survey's
/// sheet download is listed while sheets are missing.
pub fn setup_stale(assets: &Path, repo: &Path, sim: bool) -> Vec<Stale> {
    // Only the steps with a stamp that no longer holds (None: no stamp).
    let with_bytes = |v: Vec<(&'static str, Option<bool>)>, steps: &[Step], bytes: &dyn Fn(&str) -> i64| {
        v.into_iter()
            .filter(|(_, up)| *up == Some(false))
            .filter_map(|(id, _)| steps.iter().find(|s| s.id == id))
            .map(|s| Stale { id: s.id, title: s.title, download: bytes(s.id) })
            .collect()
    };
    if sim {
        // Never set up: no choice file (the wizard's Include boxes write it, a run starts with it) or no step that
        // finished a run (no stamp). Nothing then, also where some data is there.
        if !crate::sim::sim_choice_file(assets).is_file() {
            return vec![];
        }
        let out = crate::sim_excluded(assets);
        let out: Vec<&str> = out.iter().map(String::as_str).collect();
        // The Survey photo always (the wizard's SURVEY_ID): a theatre built without it is stale. Its sheets' download
        // keeps no stamp: the run Update starts fetches the missing ones.
        let inputs = SimInputs { survey: true, ..Default::default() }.without(&out);
        let steps = crate::sim_plan(&inputs);
        if !steps.iter().any(|s| crate::stamp::sim_stamp_path(assets, s.id).is_file()) {
            return vec![];
        }
        let ctx = SimCtx { assets: assets.into(), repo: repo.into(), inputs };
        let stamped = crate::stamped_with(&steps, &|s| crate::stamp::sim_of(s, &ctx));
        let optional = crate::sim_optional(assets);
        let bytes = |id: &str| match id {
            "sim-terrain" => match crate::sim_terrain_fetch(assets, repo, inputs.survey) {
                Ok(v) if v.is_empty() => 0,
                _ => -1,
            },
            _ => optional.iter().find(|o| o.id == id).map_or(0, |o| o.download as i64),
        };
        let mut stale: Vec<Stale> = with_bytes(stamped, &steps, &bytes);
        // The Survey's sheets keep no stamp: still missing ones (an install from before every sheet was fetched) make
        // the download step stale, by the sheets' mean size (17.27 GB for 79, data.gov.il).
        let all = SimInputs::default().with_survey("mapi2015");
        let missing = all.survey_missing(assets);
        if missing > 0 {
            let title = crate::sim_plan(&all)[0].title;
            stale.insert(
                0,
                Stale { id: crate::sim::SURVEY_FETCH, title, download: missing as i64 * 17_270_000_000 / 79 },
            );
        }
        stale
    } else {
        let Ok(Some(inputs)) = crate::load_inputs(assets) else { return vec![] };
        let steps = crate::plan(&inputs);
        let ctx = Ctx { assets: assets.into(), repo: repo.into(), inputs, guides: None };
        let bundle = !repo.join(crate::steps::LAUNCHER).is_file();
        let stamped = crate::stamped_with(&steps, &|s| crate::stamp::of_quick(s, &ctx))
            .into_iter()
            .map(|(id, up)| (id, if bundle && id == "launcher" { None } else { up }))
            .collect();
        let bytes = |id: &str| match id {
            "models" => {
                let src = assets.join("source/f15");
                iaf_tools::f15::SOURCE
                    .iter()
                    .filter(|d| !iaf_tools::thirdparty::file_done(&src, d))
                    .map(|d| d.bytes as i64)
                    .sum()
            }
            _ => 0,
        };
        with_bytes(stamped, &steps, &bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_compare_by_base_then_day_then_build() {
        let v = "0.1.0-nightly.20261124+abc1234";
        assert_eq!(parse(v), Some(Version { base: [0, 1, 0], date: 20261124, hash: "abc1234".into() }));
        assert!(parse("dev").is_none() && parse("0.1-nightly.20261124+a").is_none());
        assert!(newer(v, "0.1.0-nightly.20261125+def5678"));
        assert!(newer(v, "0.2.0-nightly.20261101+def5678"));
        assert!(newer(v, "0.1.0-nightly.20261124+def5678"));
        assert!(!newer(v, v));
        assert!(!newer(v, "0.1.0-nightly.20261123+def5678"));
        assert!(!newer("dev", "0.1.0-nightly.20261125+def5678"));
        assert!(!newer(v, "garbage"));
    }

    #[test]
    fn the_manifest_gives_this_games_download_for_this_system() {
        let m = r#"{"assets":[
            {"name":"modern-iaf-nightly-linux-x86_64.tar.gz","version":"0.1.0-nightly.20261125+d","size":3,"sha256":"AB"},
            {"name":"iaf-reborn-nightly-macos-arm64.dmg","version":"1.1.0-nightly.20261125+d","size":4,"sha256":"cd"}]}"#;
        let o = pick(m, "modern-iaf", "Linux").unwrap();
        assert_eq!((o.version.as_str(), o.size, o.sha256.as_str()), ("0.1.0-nightly.20261125+d", 3, "ab"));
        assert_eq!(pick(m, "iaf-reborn", "macOS").unwrap().name, "iaf-reborn-nightly-macos-arm64.dmg");
        assert!(pick(m, "modern-iaf", "Windows").is_none() && pick(m, "x", "Linux").is_none());
        assert!(pick("not json", "modern-iaf", "Linux").is_none());
        assert_eq!(asset("iaf-reborn", "Windows").unwrap(), "iaf-reborn-nightly-windows-x86_64.zip");
    }

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("iaf-update-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn verify_checks_size_and_sha256() {
        let d = tmp("verify");
        let f = d.join("a");
        std::fs::write(&f, b"abc").unwrap();
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
        let go = AtomicBool::new(false);
        assert!(verify(&f, 3, abc, &go).is_ok());
        assert!(verify(&f, 3, &abc.to_uppercase(), &go).is_ok());
        assert!(verify(&f, 4, abc, &go).is_err());
        assert!(verify(&f, 3, &abc.replace('b', "c"), &go).is_err());
        // Cancelled (the player's Later): the check stops (the statemachines audit, #4).
        let e = verify(&f, 3, abc, &AtomicBool::new(true)).unwrap_err();
        assert_eq!(format!("{e:#}"), "cancelled");
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn the_swap_keeps_the_old_folder_until_cleanup_and_rolls_back() {
        assert_eq!(app_dir(Path::new("/A/M.app/Contents/MacOS/M"), "macOS"), Path::new("/A/M.app"));
        assert_eq!(app_dir(Path::new("/opt/Modern IAF/Modern IAF.x86_64"), "Linux"), Path::new("/opt/Modern IAF"));
        let d = tmp("swap");
        let app = d.join("Game");
        std::fs::create_dir_all(app.join("sub")).unwrap();
        std::fs::write(app.join("sub/v"), "1").unwrap();
        assert_eq!(stage_dir(&app), d.join(".Game.update"));
        let new = stage_dir(&app).join("Game");
        std::fs::create_dir_all(new.join("sub")).unwrap();
        std::fs::write(new.join("sub/v"), "2").unwrap();
        swap(&app, &new).unwrap();
        assert_eq!(std::fs::read_to_string(app.join("sub/v")).unwrap(), "2");
        assert_eq!(std::fs::read_to_string(old_dir(&app).join("sub/v")).unwrap(), "1");
        rollback(&app).unwrap();
        assert_eq!(std::fs::read_to_string(app.join("sub/v")).unwrap(), "1");
        assert!(rollback(&app).is_err(), "no old version: nothing to roll back to");
        let (e, intact) = swap_or_keep(&app, &d.join("missing"));
        assert!(!e.is_empty() && intact, "a failed copy: the old version is back");
        swap(&app, &new).unwrap();
        assert!(swap(&app, &new).is_err(), "an old version still there: refused");
        cleanup(&app);
        assert!(!old_dir(&app).exists() && !stage_dir(&app).exists());
        assert_eq!(std::fs::read_to_string(app.join("sub/v")).unwrap(), "2");
        // A copy that fails (no new folder) leaves the old one in place.
        assert!(swap(&app, &d.join("missing")).is_err());
        assert_eq!(std::fs::read_to_string(app.join("sub/v")).unwrap(), "2");
        assert!(!old_dir(&app).exists() && !beside(&app, "failed").exists());
        std::fs::remove_dir_all(d).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn a_process_is_waited_for_and_launched_elsewhere() {
        let d = tmp("launch");
        let args = ["-c".to_string(), "pwd > here.txt".to_string()];
        let pid = launch(Path::new("sh"), &args, &d).unwrap();
        for _ in 0..100 {
            if d.join("here.txt").is_file() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        assert!(pid > 0 && d.join("here.txt").is_file(), "it ran in the folder given");
        // Not a child of ours (as the old game is not the swap's): a sleep its shell left behind.
        let out = Command::new("sh").args(["-c", "sleep 1 >/dev/null 2>&1 & echo $!"]).output().unwrap();
        let orphan: u32 = String::from_utf8_lossy(&out.stdout).trim().parse().unwrap();
        assert!(running(orphan) && !wait_exit(orphan, 0.1));
        assert!(wait_exit(orphan, 10.0), "it ends");
        // The first start: its started file, an end without one, a start past its time.
        let started = d.join("started");
        let sh = |c: &str| ["-c".to_string(), c.to_string()];
        let go = |c: &str, secs| start_and_wait(Path::new("sh"), &sh(c), &d, &started, secs).unwrap();
        assert_eq!(go("touch started; sleep 5", 10.0), Start::Started);
        std::fs::remove_file(&started).unwrap();
        assert_eq!(go("exit 1", 10.0), Start::Ended);
        assert_eq!(go("sleep 5", 0.5), Start::Stopped);
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn the_setup_check_finds_nothing_before_the_first_setup() {
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let a = tmp("stale");
        // Data but never set up (no choice file, no stamp): nothing, so Always download starts no first setup.
        std::fs::create_dir_all(a.join("converted/modern-iaf/missions")).unwrap();
        assert_eq!(setup_stale(&a, &repo, true), vec![]);
        assert_eq!(setup_stale(&a, &repo, false), vec![], "the remake: no setup.json");
        // A choice made on the wizard's Include boxes, no run: still nothing.
        crate::save_sim_excluded(&a, &[]).unwrap();
        assert_eq!(setup_stale(&a, &repo, true), vec![]);
        // A run that finished a step (its stamp, from an older version): the steps whose stamps do not hold.
        std::fs::write(crate::stamp::sim_stamp_path(&a, "sim-db"), "older").unwrap();
        assert!(setup_stale(&a, &repo, true).iter().any(|s| s.id == "sim-db"));
        std::fs::remove_dir_all(a).unwrap();
    }

    /// The disk image attached and the app copied out (macOS only: diskutil image, or hdiutil on older macOS).
    #[cfg(target_os = "macos")]
    #[test]
    fn unpack_copies_the_app_out_of_a_disk_image() {
        let d = tmp("dmg");
        std::fs::create_dir_all(d.join("src/Game.app")).unwrap();
        std::fs::write(d.join("src/Game.app/x"), "3").unwrap();
        let dmg = d.join("g.dmg");
        run(Command::new("hdiutil")
            .args(["create", "-quiet", "-format", "UDZO", "-srcfolder"])
            .arg(d.join("src"))
            .arg(&dmg))
        .unwrap();
        let app = d.join("Game.app");
        let new = unpack(&dmg, &stage_dir(&app), &app, "macOS", &AtomicBool::new(false)).unwrap();
        assert_eq!(std::fs::read_to_string(new.join("x")).unwrap(), "3");
        assert!(!stage_dir(&app).join(".mnt").exists(), "detached, its mount point removed");
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn unpack_finds_the_game_in_a_linux_bundle() {
        if cfg!(not(target_os = "linux")) {
            return;
        }
        let d = tmp("unpack");
        std::fs::create_dir_all(d.join("src/Game")).unwrap();
        std::fs::write(d.join("src/Game/x"), "2").unwrap();
        let tgz = d.join("g.tar.gz");
        run(Command::new("tar").arg("-czf").arg(&tgz).arg("-C").arg(d.join("src")).arg("Game")).unwrap();
        let app = d.join("Game");
        let go = AtomicBool::new(false);
        let new = unpack(&tgz, &stage_dir(&app), &app, "Linux", &go).unwrap();
        assert_eq!(std::fs::read_to_string(new.join("x")).unwrap(), "2");
        assert!(unpack(&tgz, &stage_dir(&app), &d.join("Other"), "Linux", &go).is_err());
        // Cancelled: no stage folder left behind (the statemachines audit, #4).
        let e = unpack(&tgz, &stage_dir(&app), &app, "Linux", &AtomicBool::new(true)).unwrap_err();
        assert!(format!("{e:#}") == "cancelled" && !stage_dir(&app).exists());
        std::fs::remove_dir_all(d).unwrap();
    }
}
