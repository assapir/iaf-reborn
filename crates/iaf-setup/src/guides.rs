//! The pilot guides (docs/guides, docs/front-end.md §14 "Pilot guide"): their pictures, real renders made by the game
//! itself (iaf-reborn/setup/guide_shots.gd, a few shots per process, several processes at once), then their PDFs
//! (iaf_tools::guide_pdf). Nothing outside the game is needed: a release bundle runs its own executable, a checkout
//! its Godot with --path. The pictures and PDFs hold the original art, so they stay under assets/ (never committed).
//!
//! A shot whose picture is up to date (its stamp, `<name>.stamp` beside it) is skipped. The stamp covers the shot's
//! entry in <jet>.shots.json, the shot script (in a checkout), Godot's version, the frame size and the data
//! (assets/install and assets/converted, every file's path and size; the guides' own output, hidden work folders and
//! what no shot draws left out: the scenery, roads and detailed models are off in every shot's settings). Other game
//! code changes do not re-render (so setup runs again without rendering): `force` does.

use anyhow::{Context, Result, bail};
use iaf_tools::progress::Progress;
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

/// The game's argument that runs the shot script (iaf-reborn/setup/guide_shots.gd, in the project so a bundle's .pck
/// has it) in place of the menu: menu/startup.gd. Not -s: Godot's export templates ignore a script on the command line.
const SHOTS_ARG: &str = "--guide-shots";
/// The frame (sharp crops, whatever the screen): GUIDE_SIZE overrides.
const SIZE: &str = "3840x2160";
/// Shots per process.
const BATCH: usize = 4;

/// How to start the game for a shot: its executable and the arguments before the script's.
#[derive(Clone, Debug)]
pub struct Game {
    pub exe: PathBuf,
    pub args: Vec<String>,
}

impl Game {
    /// The game this process is (the setup wizard, in-process): in a checkout (`repo` holds the project) Godot runs
    /// the project by --path; a release bundle's executable runs its own .pck.
    pub fn this_one(repo: &Path) -> Result<Game> {
        let exe = std::env::current_exe().context("the game's executable")?;
        Ok(Game { exe, args: project_args(repo) })
    }

    /// A checkout's Godot from the PATH (the iaf-setup CLI).
    pub fn checkout(repo: &Path) -> Game {
        Game { exe: "godot".into(), args: project_args(repo) }
    }
}

fn project_args(repo: &Path) -> Vec<String> {
    let p = repo.join("iaf-reborn");
    if p.join("project.godot").is_file() { vec!["--path".into(), p.to_string_lossy().into_owned()] } else { vec![] }
}

/// What to make: `jets` (empty: every guide), only the shots `only` (empty: all), `force` remakes what is up to date.
#[derive(Clone, Debug, Default)]
pub struct Options {
    pub jets: Vec<String>,
    pub only: Vec<String>,
    pub force: bool,
}

/// The guides' pictures, then their PDFs.
pub fn make(
    repo: &Path,
    assets: &Path,
    game: &Game,
    o: &Options,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<()> {
    let docs = repo.join("docs/guides");
    let jets = if o.jets.is_empty() { iaf_tools::guide_pdf::all(&docs) } else { o.jets.clone() };
    shots(&docs, assets, game, &Options { jets: jets.clone(), ..o.clone() }, pr, cancel)?;
    iaf_tools::guide_pdf::make(&docs, assets, &jets, o.force, pr)
}

/// The stamp's common part: the shot script, Godot's version, the frame size and the data's file list.
fn build_hash(repo_script: &Path, game: &Game, size: &str, assets: &Path) -> String {
    let mut h = Sha256::new();
    if let Ok(b) = std::fs::read(repo_script) {
        h.update(&b);
    }
    if let Ok(o) = Command::new(&game.exe).arg("--version").stderr(Stdio::null()).output() {
        h.update(&o.stdout);
    }
    h.update(size.as_bytes());
    let skip = ["guides", "scenery", "roads", "models"].map(|x| assets.join("converted").join(x));
    fn walk(d: &Path, rel: &str, skip: &[PathBuf], h: &mut Sha256) {
        let Ok(rd) = std::fs::read_dir(d) else { return };
        let mut es: Vec<_> = rd.flatten().collect();
        es.sort_by_key(|e| e.file_name());
        for e in es {
            let name = e.file_name().to_string_lossy().into_owned();
            let p = e.path();
            // std's metadata follows links, as the data's folders may be.
            let Ok(m) = std::fs::metadata(&p) else { continue };
            if m.is_dir() {
                if !name.starts_with('.') && !skip.contains(&p) {
                    walk(&p, &format!("{rel}/{name}"), skip, h);
                }
            } else if !name.ends_with(".secs") {
                // ponytail: path and size, not the time, so identical regenerated data keeps the pictures; a same-size
                // change goes unseen (force). A step's .secs (its last run's seconds) changes every run: left out.
                h.update(format!("{rel}/{name} {}\n", m.len()).as_bytes());
            }
        }
    }
    for top in ["install", "converted"] {
        walk(&assets.join(top), top, &skip, &mut h);
    }
    format!("{:x}", h.finalize())
}

/// What every shot process shares.
#[derive(Clone, Copy)]
struct Shots<'a> {
    game: &'a Game,
    docs: &'a Path,
    assets: &'a Path,
    out: &'a Path,
    size: &'a str,
    cancel: &'a AtomicBool,
}

/// One process's shots: (jet, names).
type Job = (String, Vec<String>);

/// The pictures of `o.jets` that are not up to date into assets/converted/guides/shots/<jet>/; failures named at the
/// end with their Godot logs (kept under assets/logs).
fn shots(docs: &Path, assets: &Path, game: &Game, o: &Options, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let size = std::env::var("GUIDE_SIZE").unwrap_or_else(|_| SIZE.into());
    let repo_script = docs.join("../../iaf-reborn/setup/guide_shots.gd");
    let build = build_hash(&repo_script, game, &size, assets);
    let out = assets.join("converted/guides/shots");
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let logs = assets.join(format!("logs/guide-shots-{secs}-{}", std::process::id()));
    let mut jobs: Vec<Job> = vec![];
    let mut stamps = vec![];
    for jet in &o.jets {
        let file = docs.join(format!("{jet}.shots.json"));
        let list: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&file).context(file.display().to_string())?)?;
        let mut names = vec![];
        for e in list.as_array().into_iter().flatten() {
            let name = e["name"].as_str().unwrap_or("").to_string();
            if !o.only.is_empty() && !o.only.contains(&name) {
                continue;
            }
            let stamp = format!("{:x}", Sha256::digest(format!("{build}{e}").as_bytes()));
            let pic = out.join(jet).join(&name);
            let fresh = pic.with_extension("png").is_file()
                && std::fs::read_to_string(pic.with_extension("stamp")).is_ok_and(|s| s == stamp);
            if fresh && !o.force {
                pr.log(&format!("up to date: {jet}/{name}"));
                continue;
            }
            stamps.push((jet.clone(), name.clone(), stamp));
            names.push(name);
        }
        jobs.extend(names.chunks(BATCH).map(|c| (jet.clone(), c.to_vec())));
    }
    if jobs.is_empty() {
        pr.log("guide shots: all up to date");
        return Ok(());
    }
    std::fs::create_dir_all(&logs)?;
    let at_once = parallel();
    pr.log(&format!("guide shots: {} processes, {at_once} at once, into {}", jobs.len(), out.display()));
    let total = jobs.len();
    let queue = Mutex::new(jobs.into_iter().enumerate().collect::<Vec<_>>());
    let failed = Mutex::new(vec![]);
    let ctx = Shots { game, docs, assets, out: &out, size: &size, cancel };
    let done = Mutex::new(0usize);
    std::thread::scope(|s| {
        for _ in 0..at_once {
            s.spawn(|| {
                loop {
                    let Some((i, (jet, names))) = queue.lock().unwrap().pop() else { break };
                    if cancel.load(Ordering::Relaxed) {
                        break;
                    }
                    let log = logs.join(format!("{jet}-{}.log", names[0]));
                    let lines = run_one(&ctx, &jet, &names, &log);
                    let mut bad = false;
                    for l in &lines {
                        if l.starts_with("FAIL") || l.contains("SCRIPT ERROR") {
                            bad = true;
                            pr.warn(&format!("{l} [log: {}]", log.display()));
                        } else {
                            pr.log(l);
                        }
                    }
                    // The stamp only for a shot that passed every check.
                    for n in &names {
                        let stamp = out.join(&jet).join(format!("{n}.stamp"));
                        let ok = out.join(&jet).join(format!("{n}.png")).is_file()
                            && lines.iter().any(|l| l.starts_with(&format!("PASS shot {n} ")))
                            && !lines.iter().any(|l| l.starts_with(&format!("FAIL shot {n}:")));
                        let want = stamps.iter().find(|(j, m, _)| *j == jet && m == n).map(|x| &x.2);
                        match (ok, want) {
                            (true, Some(w)) => {
                                let _ = std::fs::write(&stamp, w);
                            }
                            _ => {
                                let _ = std::fs::remove_file(&stamp);
                            }
                        }
                    }
                    if bad {
                        failed.lock().unwrap().push((i, log));
                    }
                    let mut d = done.lock().unwrap();
                    *d += 1;
                    pr.fraction(*d as f32 / total as f32);
                }
            });
        }
    });
    if cancel.load(Ordering::Relaxed) {
        bail!("cancelled");
    }
    let mut failed = failed.into_inner().unwrap();
    if !failed.is_empty() {
        failed.sort();
        let list: Vec<String> = failed.iter().map(|(_, l)| format!("  {}", l.display())).collect();
        bail!("guide shots: {} processes failed; their Godot logs:\n{}", failed.len(), list.join("\n"));
    }
    let _ = std::fs::remove_dir_all(&logs); // kept only when something failed
    pr.log("guide shots: done");
    Ok(())
}

/// Processes at once: GUIDE_JOBS, else half the cores, at most one per 2 GB of free memory (Linux; elsewhere four).
fn parallel() -> usize {
    if let Some(n) = std::env::var("GUIDE_JOBS").ok().and_then(|v| v.parse::<usize>().ok()) {
        return n.max(1);
    }
    let cores = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(2);
    // ponytail: 2 GB per process is the measured peak (≈1.1 GB RSS) plus room; MemAvailable only on Linux.
    let mem = std::fs::read_to_string("/proc/meminfo")
        .ok()
        .and_then(|m| {
            m.lines().find(|l| l.starts_with("MemAvailable:"))?.split_whitespace().nth(1)?.parse::<usize>().ok()
        })
        .map(|kb| kb / 1_048_576 / 2)
        .unwrap_or(4);
    (cores / 2).min(mem).max(1)
}

/// The command for one process, its window never on the player's screen: on macOS the app started hidden (open -g -j:
/// it renders, no window takes the focus); on Linux under xvfb-run with the desktop's WAYLAND_DISPLAY taken away, so
/// Godot cannot fall back to the desktop's compositor (it did: docs/rendering.md §1.5) and renders on the GPU in the
/// virtual X server. Linux without xvfb-run renders nothing: an error.
fn command(game: &Game, envs: &[(&str, String)], args: &[String]) -> Result<Command> {
    let all: Vec<String> = game.args.iter().chain(args).cloned().collect();
    let exe = real_path(&game.exe).to_string_lossy().into_owned();
    if cfg!(target_os = "macos")
        && let Some(i) = exe.find(".app/")
    {
        let mut c = Command::new("open");
        c.args(["-W", "-g", "-j", "-n", "-a", &exe[..i + 4]]);
        for (k, v) in envs {
            c.args(["--env", &format!("{k}={v}")]);
        }
        c.arg("--args").args(&all);
        return Ok(c);
    }
    let mut c = if !cfg!(target_os = "linux") {
        Command::new(&game.exe)
    } else if on_path("xvfb-run") {
        let mut c = Command::new("xvfb-run");
        c.arg("-a").arg(&game.exe);
        c
    } else {
        bail!("the pictures render out of sight in xvfb-run: install it (the xvfb package)")
    };
    c.args(&all);
    for (k, v) in envs {
        c.env(k, v);
    }
    if cfg!(target_os = "linux") {
        c.env_remove("DISPLAY").env_remove("WAYLAND_DISPLAY");
    }
    // In the caller's process group, so a Ctrl-C or a stopped setup stops the renders too.
    Ok(c)
}

fn on_path(name: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(name).is_file()))
}

/// The executable as a file: a bare name looked up on the PATH, links resolved (a macOS app is found by its
/// `.app/` folder in the real path).
fn real_path(exe: &Path) -> PathBuf {
    let found = if exe.components().count() == 1 {
        std::env::var_os("PATH").and_then(|p| {
            std::env::split_paths(&p)
                .map(|d| {
                    let f = d.join(exe);
                    let ext = std::env::consts::EXE_EXTENSION;
                    if ext.is_empty() { f } else { f.with_extension(ext) }
                })
                .find(|f| f.is_file())
        })
    } else {
        None
    };
    let p = found.unwrap_or_else(|| exe.to_path_buf());
    std::fs::canonicalize(&p).unwrap_or(p)
}

/// Stops a process: Godot by its log file (under xvfb-run, which then ends and takes its Xvfb along; the hidden macOS
/// app, which `open` only waits for), then the process itself if it is still there after 10 s.
fn stop(child: &mut Child, log: &Path) {
    #[cfg(unix)]
    let _ = Command::new("pkill").args(["-KILL", "-f", "--", &format!("--log-file {}", log.display())]).status();
    #[cfg(not(unix))]
    let _ = log;
    for _ in 0..10 {
        if child.try_wait().ok().flatten().is_some() {
            return;
        }
        std::thread::sleep(Duration::from_secs(1));
    }
    let _ = child.kill();
    let _ = child.wait();
}

/// Runs one process's shots; its PASS / FAIL / GUIDE_INFO / SCRIPT ERROR lines, and a FAIL line when it crashed or
/// was stopped. A process that runs past GUIDE_TIMEOUT s per shot (default 600) is stopped; one that printed its
/// RESULT and is still there 30 s later (Godot's Wayland exit race, docs/rendering.md §1.5) is stopped too, its
/// pictures kept.
fn run_one(r: &Shots, jet: &str, names: &[String], log: &Path) -> Vec<String> {
    let Shots { game, docs, assets, out, size, cancel } = *r;
    let envs = [
        ("GUIDE_JSON", docs.join(format!("{jet}.shots.json")).to_string_lossy().into_owned()),
        ("GUIDE_SHOTS", names.join(",")),
        ("GUIDE_OUT", out.join(jet).to_string_lossy().into_owned()),
        ("GUIDE_SIZE", size.to_string()),
        ("IAF_DEFAULT_SETTINGS", "1".into()),
        ("IAF_ASSETS_DIR", assets.to_string_lossy().into_owned()),
    ];
    let args: Vec<String> =
        ["--log-file", &log.to_string_lossy(), "--resolution", SIZE, "--audio-driver", "Dummy", "--", SHOTS_ARG]
            .map(String::from)
            .to_vec();
    let _ = std::fs::create_dir_all(out.join(jet));
    let mut note = None;
    match command(game, &envs, &args)
        .and_then(|mut c| c.stdout(Stdio::null()).stderr(Stdio::null()).spawn().map_err(Into::into))
    {
        Err(e) => note = Some(format!("FAIL {jet} {}: could not start the game: {e:#}", names.join(","))),
        Ok(mut child) => {
            let per = std::env::var("GUIDE_TIMEOUT").ok().and_then(|v| v.parse().ok()).unwrap_or(600u64);
            let limit = Duration::from_secs(per * names.len() as u64);
            let t0 = Instant::now();
            let mut result_at = None;
            while child.try_wait().ok().flatten().is_none() {
                std::thread::sleep(Duration::from_secs(1));
                if cancel.load(Ordering::Relaxed) {
                    stop(&mut child, log);
                    break;
                }
                let has_result =
                    std::fs::read_to_string(log).is_ok_and(|l| l.lines().any(|x| x.starts_with("RESULT ")));
                if has_result {
                    let at = *result_at.get_or_insert_with(Instant::now);
                    if at.elapsed() > Duration::from_secs(30) {
                        note = Some(format!(
                            "NOTE {jet} {}: still running 30 s after its RESULT, stopped",
                            names.join(",")
                        ));
                        stop(&mut child, log);
                    }
                } else if t0.elapsed() > limit {
                    note =
                        Some(format!("FAIL {jet} {}: no RESULT after {} s, stopped", names.join(","), limit.as_secs()));
                    stop(&mut child, log);
                }
            }
        }
    }
    let text = std::fs::read_to_string(log).unwrap_or_default();
    let mut lines: Vec<String> = text
        .lines()
        .filter(|l| {
            l.starts_with("PASS shot")
                || l.starts_with("FAIL shot")
                || l.starts_with("GUIDE_INFO")
                || l.contains("SCRIPT ERROR")
        })
        .map(String::from)
        .collect();
    let failed_note = note.as_ref().is_some_and(|n| n.starts_with("FAIL"));
    lines.extend(note);
    if !text.lines().any(|l| l.starts_with("RESULT ")) && !failed_note && !cancel.load(Ordering::Relaxed) {
        lines.push(format!("FAIL {jet} {}: Godot ended without a RESULT line", names.join(",")));
    }
    lines
}
