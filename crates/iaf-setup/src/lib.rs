//! The setup pipeline (docs/setup.md): from the player's own CDs to everything the game reads under `assets/`,
//! in-process. `plan` lists the steps of tools/setup-cli.sh with what each waits for; `run` runs them as a
//! dependency graph (independent steps at once), skips the steps whose stamp is unchanged, and reports per step.

use std::collections::HashMap;
use std::path::PathBuf;
#[cfg(test)]
use std::path::Path;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;

use anyhow::Result;
use iaf_tools::progress::Progress;

mod checks;
mod saved;
mod stamp;
mod steps;

pub use checks::{CdKind, PackInfo, Tools, check_cd, check_pack, check_patch, tools};
pub use saved::{from_json, inputs_file, load_inputs, save_inputs, to_json};
pub use steps::{COCKPITS, imagery_stale, script_guides};

/// The Hebrew content: the Hebrew retail CD (everything translated), or the preflight.us packs.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum Hebrew {
    #[default]
    None,
    Cd(PathBuf),
    Packs { brief: Option<PathBuf>, menu: Option<PathBuf> },
}

/// Modern terrain imagery (docs/imagery.md).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Imagery {
    /// ESA WorldCover 2021 Sentinel-2 outside Israel (GDAL range reads over the network).
    Sentinel2,
    /// The Survey of Israel 2015 sheets, downloaded then converted; `bases`: only the sheets around the airbases.
    Mapi2015 { bases: bool },
}

/// What the player gives setup.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Inputs {
    /// The English CD image (required).
    pub cd: PathBuf,
    /// The official v1.1 patch (self-extractor, `iafp1_1.exe` or a bare patch).
    pub patch: Option<PathBuf>,
    pub hebrew: Hebrew,
    pub imagery: Vec<Imagery>,
    /// Convert again the imagery units made under older rules, in the layers on disk not chosen above (after a
    /// restore from a mirror; `iaf-imagery --stale`).
    pub refresh: bool,
    /// Render the pilot guides (needs a display; the renderer is `Ctx::guides`).
    pub guides: bool,
}

/// One step of the plan.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Step {
    pub id: &'static str,
    pub title: &'static str,
    /// A failure stops the setup (an optional step's failure only blocks what waits for it).
    pub required: bool,
    /// The steps whose output this one reads.
    pub after: Vec<&'static str>,
}

/// The steps for `inputs`, in tools/setup-cli.sh's order and conditions.
pub fn plan(inputs: &Inputs) -> Vec<Step> {
    let mut v = Vec::new();
    let mut add = |id, title, required, after: &[&'static str]| v.push(Step { id, title, required, after: after.to_vec() });
    add("extract", "extracting the original install from the CD image", true, &[]);
    let base: &'static str = if inputs.patch.is_some() {
        add("patch", "v1.1 patch (the v1.0 originals are kept in assets/v1.0)", true, &["extract"]);
        "patch"
    } else {
        "extract"
    };
    let he = inputs.hebrew != Hebrew::None;
    let he_menu = matches!(&inputs.hebrew, Hebrew::Cd(_) | Hebrew::Packs { menu: Some(_), .. });
    add("fonts", "original HUD / MFD fonts", true, &[base]);
    add("cockpits", "cockpits (art and layout, every aircraft)", true, &[base]);
    if he {
        add("hebrew", "Hebrew briefings and menus", true, &[base]);
    }
    let with_he: &[&'static str] = if he { &[base, "hebrew"] } else { &[base] };
    add("briefings", "briefings (English + Hebrew when given)", true, with_he);
    add("reference", "Reference screen (records, descriptions, pictures)", true, &[base]);
    add("menu", "front-end menus (screens, strings, art, fonts)", true, &[base]);
    if he_menu {
        add("menu_he", "front-end menus in Hebrew", true, &[base, "hebrew"]);
    }
    add("arm", "extra planes' arming art", true, if he_menu { &["menu", "menu_he"] } else { &["menu"] });
    add("keys", "key table (default keys from the exe + keys.trx labels)", true, with_he);
    add("missions", "missions (all .mis + object database -> JSON, mission list)", true, &[base]);
    add("aircraft", "aircraft: every plane's model and descriptor", true, &["missions"]);
    add("objects", "mission object models", true, &["missions"]);
    add("theatre", "terrain: every level and inset of map.ptt as a node quadtree", true, &[base]);
    add("airbases", "airbases: runways, taxi paths and paved surface", true, &["theatre"]);
    add("icon", "icon (the original icon from iafjets.exe)", true, &[base]);
    add("launcher", "desktop launcher", false, &["icon"]);
    let mut last: Vec<&'static str> = Vec::new();
    for im in &inputs.imagery {
        match im {
            Imagery::Sentinel2 => {
                add("sentinel2", "imagery: Sentinel-2 outside Israel (ESA WorldCover 2021)", false, &["airbases"]);
                last.push("sentinel2");
            }
            Imagery::Mapi2015 { .. } => {
                add("mapi2015-fetch", "imagery: Survey of Israel 2015 2 m sheets (data.gov.il)", false, &[]);
                add("mapi2015", "imagery: Survey of Israel 2015 2 m layer", false, &["airbases", "mapi2015-fetch"]);
                last.push("mapi2015");
            }
        }
    }
    if inputs.refresh {
        add("imagery-refresh", "imagery: convert again what older rules made", false, &["airbases"]);
        last.push("imagery-refresh");
    }
    if inputs.guides {
        let mut after = vec!["briefings", "reference", "menu", "arm", "keys", "aircraft", "objects", "airbases", "icon"];
        after.extend(last);
        add("guides", "pilot guides: pictures and PDFs", false, &after);
    }
    v
}

/// The steps `ids` of `steps` and every step they wait for (a shorter run, e.g. for a test), in `steps`' order.
pub fn only(steps: &[Step], ids: &[&str]) -> Vec<Step> {
    let mut want: Vec<&str> = ids.to_vec();
    let mut k = 0;
    while k < want.len() {
        if let Some(s) = steps.iter().find(|s| s.id == want[k]) {
            for a in &s.after {
                if !want.contains(a) {
                    want.push(a);
                }
            }
        }
        k += 1;
    }
    steps.iter().filter(|s| want.contains(&s.id)).cloned().collect()
}

/// A step's state as `run` reports it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum State {
    Waiting,
    Running,
    /// Its stamp matched: nothing to do.
    UpToDate,
    Done,
    /// Not run, and why (e.g. no display for the guides).
    Skipped(String),
    Failed(String),
    /// A step it waits for failed or was cancelled.
    Blocked,
    Cancelled,
}

impl State {
    fn ok(&self) -> bool {
        matches!(self, State::UpToDate | State::Done | State::Skipped(_))
    }
    fn finished(&self) -> bool {
        !matches!(self, State::Waiting | State::Running)
    }
}

/// Where `run` reports: each step's state changes, log lines and fraction done. Called from the step threads.
pub trait Events: Sync {
    fn state(&self, step: &Step, state: &State);
    fn log(&self, step: &Step, line: &str);
    fn fraction(&self, _step: &Step, _f: f32) {}
}

/// A step's own `Progress` (the converters' sink), forwarding to `Events`.
struct StepProgress<'a> {
    step: &'a Step,
    events: &'a dyn Events,
}

impl Progress for StepProgress<'_> {
    fn log(&self, line: &str) {
        self.events.log(self.step, line);
    }
    fn fraction(&self, f: f32) {
        self.events.fraction(self.step, f);
    }
}

/// Renders the pilot guides (the wizard: in-process; the CLI: tools/guide_shots.sh + tools/guide_pdf.py).
pub type GuidesFn<'a> = dyn Fn(&dyn Progress, &AtomicBool) -> Result<()> + Sync + 'a;

/// Everything a run needs besides the plan.
pub struct Ctx<'a> {
    /// The assets folder (`<repo>/assets` normally).
    pub assets: PathBuf,
    /// The repo checkout (game/extra/planes, tools/install-launcher.sh, tools/imagery).
    pub repo: PathBuf,
    pub inputs: Inputs,
    /// The launcher's XDG_DATA_HOME (default: the user's).
    pub xdg_data_home: Option<PathBuf>,
    pub guides: Option<&'a GuidesFn<'a>>,
}

/// What a step body did.
pub(crate) enum Outcome {
    Done,
    UpToDate,
    Skipped(String),
}

/// Runs `steps` (from `plan`) as a dependency graph: a step starts once every step it waits for is done or up to date;
/// independent steps run at once. A step whose stamp matches is up to date unless `redo_all`. A required step's failure
/// sets `cancel` (the other running steps stop at their next item); setting `cancel` stops the run the same way.
/// Returns every step's final state, in `steps`' order.
pub fn run(steps: &[Step], ctx: &Ctx, redo_all: bool, events: &dyn Events, cancel: &AtomicBool) -> Vec<(&'static str, State)> {
    run_graph(steps, redo_all, events, cancel, &|step| stamp::of(step, ctx), &|step, pr| steps::run(step, ctx, pr, cancel))
}

type StampFn<'a> = dyn Fn(&Step) -> Result<Option<stamp::Stamp>> + Sync + 'a;
type ExecFn<'a> = dyn Fn(&Step, &dyn Progress) -> Result<Outcome> + Sync + 'a;

/// `run`'s engine: `stamp` gives a step's stamp (`None`: it keeps none), `exec` runs it.
pub(crate) fn run_graph(steps: &[Step], redo_all: bool, events: &dyn Events, cancel: &AtomicBool, stamp: &StampFn, exec: &ExecFn) -> Vec<(&'static str, State)> {
    let states: Mutex<Vec<State>> = Mutex::new(vec![State::Waiting; steps.len()]);
    // The stamps of the finished steps: a step's stamp holds those of the steps it waits for.
    let stamps: Mutex<HashMap<&'static str, String>> = Mutex::new(HashMap::new());
    let index: HashMap<&str, usize> = steps.iter().enumerate().map(|(k, s)| (s.id, k)).collect();
    let set = |k: usize, s: State| {
        events.state(&steps[k], &s);
        states.lock().unwrap()[k] = s;
    };
    for s in steps {
        events.state(s, &State::Waiting);
    }
    let (tx, rx) = mpsc::channel::<()>();
    std::thread::scope(|scope| {
        let mut running = 0;
        loop {
            // Start every waiting step whose steps all succeeded; block the ones behind a failure.
            let snapshot = states.lock().unwrap().clone();
            for (k, step) in steps.iter().enumerate() {
                if snapshot[k] != State::Waiting {
                    continue;
                }
                let deps: Vec<&State> = step.after.iter().filter_map(|a| index.get(a).map(|&i| &snapshot[i])).collect();
                if cancel.load(Ordering::Relaxed) {
                    set(k, State::Cancelled);
                } else if deps.iter().any(|d| d.finished() && !d.ok()) {
                    set(k, State::Blocked);
                } else if deps.iter().all(|d| d.ok()) {
                    set(k, State::Running);
                    running += 1;
                    let (tx, stamps, set) = (tx.clone(), &stamps, &set);
                    scope.spawn(move || {
                        let pr = StepProgress { step, events };
                        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run_one(step, redo_all, &pr, stamps, stamp, exec)));
                        let state = match r {
                            Ok(Ok(s)) => s,
                            Ok(Err(_)) if cancel.load(Ordering::Relaxed) => State::Cancelled,
                            Ok(Err(e)) => State::Failed(format!("{e:#}")),
                            Err(_) => State::Failed("panicked".into()),
                        };
                        if let State::Failed(e) = &state {
                            pr.warn(&format!("FAILED: {e}"));
                            if step.required {
                                cancel.store(true, Ordering::Relaxed);
                            }
                        }
                        set(k, state);
                        let _ = tx.send(());
                    });
                }
            }
            if running == 0 {
                break;
            }
            let _ = rx.recv();
            running -= 1;
        }
    });
    let states = states.into_inner().unwrap();
    steps.iter().zip(states).map(|(s, st)| (s.id, if st == State::Waiting { State::Blocked } else { st })).collect()
}

/// One step: up to date when its stamp file holds the same text (and its output is there), else run and stamped.
fn run_one(step: &Step, redo_all: bool, pr: &dyn Progress, stamps: &Mutex<HashMap<&'static str, String>>, stamp: &StampFn, exec: &ExecFn) -> Result<State> {
    let s = stamp(step)?.map(|mut s| {
        let done = stamps.lock().unwrap();
        for a in &step.after {
            let t = done.get(a).map_or("none", String::as_str);
            s.text += &format!("after {a} {:08x}\n", crc32fast::hash(t.as_bytes()));
        }
        s
    });
    let record = |text: &str| {
        stamps.lock().unwrap().insert(step.id, text.to_string());
    };
    if let Some(s) = &s {
        if !redo_all && s.holds() {
            record(&s.text);
            return Ok(State::UpToDate);
        }
        s.clear()?;
    }
    match exec(step, pr)? {
        Outcome::Done => {
            if let Some(s) = &s {
                s.write()?;
                record(&s.text);
            } else {
                record("ran");
            }
            Ok(State::Done)
        }
        Outcome::UpToDate => {
            record(s.as_ref().map_or("ran", |s| s.text.as_str()));
            Ok(State::UpToDate)
        }
        Outcome::Skipped(why) => Ok(State::Skipped(why)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    fn inputs() -> Inputs {
        Inputs { cd: "cd.iso".into(), patch: None, hebrew: Hebrew::None, imagery: vec![], refresh: false, guides: false }
    }

    fn ids(steps: &[Step]) -> Vec<&'static str> {
        steps.iter().map(|s| s.id).collect()
    }

    #[test]
    fn plan_follows_the_inputs() {
        let base = plan(&inputs());
        assert_eq!(ids(&base), ["extract", "fonts", "cockpits", "briefings", "reference", "menu", "arm", "keys", "missions", "aircraft", "objects", "theatre", "airbases", "icon", "launcher"]);
        assert!(base.iter().filter(|s| s.id != "extract" && s.after.contains(&"extract")).count() >= 8);

        let full = plan(&Inputs {
            patch: Some("p.exe".into()),
            hebrew: Hebrew::Cd("he.iso".into()),
            imagery: vec![Imagery::Sentinel2, Imagery::Mapi2015 { bases: true }],
            guides: true,
            ..inputs()
        });
        let get = |id: &str| full.iter().find(|s| s.id == id).unwrap_or_else(|| panic!("{id}"));
        assert_eq!(get("fonts").after, ["patch"]);
        assert_eq!(get("briefings").after, ["patch", "hebrew"]);
        assert_eq!(get("menu_he").after, ["patch", "hebrew"]);
        assert_eq!(get("arm").after, ["menu", "menu_he"]);
        assert_eq!(get("aircraft").after, ["missions"]);
        assert_eq!(get("airbases").after, ["theatre"]);
        assert!(get("guides").after.contains(&"sentinel2") && get("guides").after.contains(&"mapi2015"));
        // Every step waits only for steps planned before it.
        for (k, s) in full.iter().enumerate() {
            for a in &s.after {
                assert!(full[..k].iter().any(|p| p.id == *a), "{} waits for {a}", s.id);
            }
        }
        // The briefings pack alone: no Hebrew menus.
        let brief = plan(&Inputs { hebrew: Hebrew::Packs { brief: Some("b.zip".into()), menu: None }, ..inputs() });
        assert!(ids(&brief).contains(&"hebrew") && !ids(&brief).contains(&"menu_he"));
        assert_eq!(ids(&only(&full, &["aircraft", "fonts"])), ["extract", "patch", "fonts", "missions", "aircraft"]);
    }

    /// tools/setup-cli.sh's `step "…"` lines and the plan's steps: every line is a step here (or a CLI-only one),
    /// every step here has its line.
    #[test]
    fn steps_match_setup_cli() {
        const LINES: &[(&str, &[&str])] = &[
            ("imagery: restore from", &["cli"]),
            ("imagery: convert again", &["imagery-refresh"]),
            ("imagery: Sentinel-2", &["sentinel2"]),
            ("imagery: Survey of Israel 2015 2 m sheets", &["mapi2015-fetch"]),
            ("imagery: Survey of Israel 2015 2 m layer", &["mapi2015"]),
            ("building tools", &["cli"]),
            ("extracting the original install", &["extract"]),
            ("v1.1 patch", &["patch"]),
            ("original HUD / MFD fonts", &["fonts"]),
            ("cockpits", &["cockpits"]),
            ("Hebrew pack", &["hebrew"]),
            ("Hebrew CD", &["hebrew"]),
            ("briefings", &["briefings"]),
            ("Reference screen", &["reference"]),
            ("front-end menus (", &["menu"]),
            ("front-end menus in Hebrew", &["menu_he"]),
            ("extra planes' arming art", &["arm"]),
            ("key table", &["keys"]),
            ("missions (", &["missions"]),
            ("aircraft:", &["aircraft"]),
            ("mission object models", &["objects"]),
            ("terrain:", &["theatre"]),
            ("airbases:", &["airbases"]),
            ("Godot extension", &["cli"]),
            ("icon and desktop launcher", &["icon", "launcher"]),
            ("pilot guides", &["guides"]),
            ("done", &["cli"]),
        ];
        let script = std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tools/setup-cli.sh")).unwrap();
        let mut seen = std::collections::HashSet::new();
        for line in script.lines() {
            let Some((_, title)) = line.split_once("step \"") else { continue };
            let hits: Vec<_> = LINES.iter().filter(|(p, _)| title.starts_with(p)).collect();
            assert_eq!(hits.len(), 1, "setup-cli.sh step \"{title}\" needs one entry here");
            seen.extend(hits[0].1.iter().copied());
        }
        let all = plan(&Inputs {
            patch: Some("p".into()),
            hebrew: Hebrew::Cd("h".into()),
            imagery: vec![Imagery::Sentinel2, Imagery::Mapi2015 { bases: false }],
            refresh: true,
            guides: true,
            ..inputs()
        });
        for s in &all {
            assert!(seen.contains(s.id), "step {} has no line in setup-cli.sh", s.id);
        }
        for (p, ids) in LINES {
            assert!(script.contains(&format!("step \"{p}")), "no setup-cli.sh line \"{p}…\"");
            for id in *ids {
                assert!(*id == "cli" || all.iter().any(|s| s.id == *id), "{id}");
            }
        }
    }

    struct Quiet;
    impl Events for Quiet {
        fn state(&self, _: &Step, _: &State) {}
        fn log(&self, _: &Step, _: &str) {}
    }

    /// The engine on made-up steps: stamps make a second run all up to date; a changed input redoes its step and
    /// what waits for it; a failed required step blocks what waits and cancels the rest.
    #[test]
    fn stamps_and_order() {
        let dir = std::env::temp_dir().join(format!("iaf-setup-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let step = |id, after: &[&'static str]| Step { id, title: id, required: true, after: after.to_vec() };
        let steps = [step("a", &[]), step("b", &["a"]), step("c", &["a"]), step("d", &["b", "c"])];
        for s in &steps {
            std::fs::write(dir.join(format!("{}.in", s.id)), "1").unwrap();
        }
        let ran: Mutex<Vec<&str>> = Mutex::new(vec![]);
        let fail = AtomicUsize::new(usize::MAX);
        let go = |redo: bool| {
            ran.lock().unwrap().clear();
            let st = |s: &Step| -> Result<Option<stamp::Stamp>> {
                Ok(Some(stamp::Stamp { path: dir.join(format!("{}.stamp", s.id)), text: stamp::describe(&dir.join(format!("{}.in", s.id)))?, output: None }))
            };
            let ex = |s: &Step, _: &dyn Progress| -> Result<Outcome> {
                // Order: a step runs after the steps it waits for.
                let done = ran.lock().unwrap().clone();
                assert!(s.after.iter().all(|a| done.contains(a) || dir.join(format!("{a}.stamp")).exists()));
                if steps.iter().position(|x| x.id == s.id) == Some(fail.load(Ordering::Relaxed)) {
                    anyhow::bail!("boom");
                }
                ran.lock().unwrap().push(s.id);
                Ok(Outcome::Done)
            };
            let states = run_graph(&steps, redo, &Quiet, &AtomicBool::new(false), &st, &ex);
            let mut r = ran.lock().unwrap().clone();
            r.sort();
            (r, states)
        };
        assert_eq!(go(false).0, ["a", "b", "c", "d"]);
        let (r, states) = go(false);
        assert!(r.is_empty() && states.iter().all(|s| s.1 == State::UpToDate), "{states:?}");
        std::fs::write(dir.join("c.in"), "2").unwrap();
        assert_eq!(go(false).0, ["c", "d"], "c changed: c and what waits for it");
        assert_eq!(go(true).0, ["a", "b", "c", "d"], "redo all");
        assert!(go(false).0.is_empty(), "redone: the same stamps");
        std::fs::write(dir.join("a.in"), "2").unwrap();
        fail.store(1, Ordering::Relaxed);
        let (r, states) = go(false);
        assert!(r.contains(&"a") && !r.contains(&"d"));
        assert!(matches!(states[1].1, State::Failed(_)) && states[3].1 != State::Done, "{states:?}");
        assert!(!dir.join("b.stamp").exists(), "a failed step has no stamp");
        fail.store(usize::MAX, Ordering::Relaxed);
        assert!(go(false).0.contains(&"b"), "b runs again after its failure");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    /// Running setup again with an extra added (or Hebrew content given) runs only the new steps and what waits for them.
    #[test]
    fn an_added_extra_runs_alone() {
        let dir = std::env::temp_dir().join(format!("iaf-setup-extra-{}", std::process::id()));
        let ran: Mutex<Vec<&str>> = Mutex::new(vec![]);
        let go = |i: &Inputs| {
            ran.lock().unwrap().clear();
            let st = |s: &Step| -> Result<Option<stamp::Stamp>> {
                Ok(Some(stamp::Stamp { path: dir.join(format!("{}.stamp", s.id)), text: format!("step {}\n", s.id), output: None }))
            };
            let ex = |s: &Step, _: &dyn Progress| -> Result<Outcome> {
                ran.lock().unwrap().push(s.id);
                Ok(Outcome::Done)
            };
            let states = run_graph(&plan(i), false, &Quiet, &AtomicBool::new(false), &st, &ex);
            assert!(states.iter().all(|s| s.1.ok()), "{states:?}");
            let mut r = ran.lock().unwrap().clone();
            r.sort();
            r
        };
        let first = inputs();
        assert_eq!(go(&first).len(), plan(&first).len());
        assert!(go(&first).is_empty());
        let more = Inputs { imagery: vec![Imagery::Sentinel2], ..first.clone() };
        assert_eq!(go(&more), ["sentinel2"]);
        let he = Inputs { hebrew: Hebrew::Packs { brief: Some("b.zip".into()), menu: Some("m.zip".into()) }, ..more.clone() };
        assert_eq!(go(&he), ["arm", "briefings", "hebrew", "keys", "menu_he"]);
        assert!(go(&he).is_empty());
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn english_cd_is_english() {
        let iso = Path::new(&std::env::var("HOME").unwrap_or_default())
            .join("Downloads/Janes-Combat-Simulations-IAF-Israeli-Air-Force_Win_EN_ISO-Version/Jane's IAF.iso");
        if !iso.exists() {
            eprintln!("skipped: no English ISO at {}", iso.display());
            return;
        }
        assert_eq!(check_cd(&iso), CdKind::English);
        assert!(matches!(check_cd(Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml").as_path()), CdKind::NotIaf(_)));
    }
}
