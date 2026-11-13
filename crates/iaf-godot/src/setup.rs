//! `IafSetup`: the setup pipeline (`iaf_setup`, docs/setup.md) for the wizards (`iaf-reborn/setup/wizard.gd`, IAF
//! 2026's `modern-iaf/setup/wizard.gd`). `start` (`sim_start`) runs the plan on its own thread; the wizard calls `poll`
//! every frame for the steps' states, fractions and new log lines.
//! Inputs travel as setup.json's JSON text (`iaf_setup::to_json` / `from_json`).

use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use godot::prelude::*;
use iaf_setup::{CdKind, Ctx, Events, SimCtx, SimInputs, State, Step};
use iaf_tools::progress::Progress;

struct Row {
    id: &'static str,
    title: &'static str,
    required: bool,
    state: &'static str,
    detail: String,
    fraction: f32,
    /// Its measured seconds (`iaf_setup::Pace`).
    expected: Option<f64>,
}

#[derive(Default)]
struct Shared {
    rows: Vec<Row>,
    log: Vec<String>,
    done: bool,
    error: String,
}

/// The run's events into `Shared`; log lines name files relative to the assets folder (`prefix`). The log file gets
/// every line and state change with full paths.
struct Sink(Arc<Mutex<Shared>>, String, Option<Mutex<std::fs::File>>);

impl Sink {
    fn write(&self, line: &str) {
        if let Some(f) = &self.2 {
            let _ = writeln!(f.lock().unwrap(), "{line}");
        }
    }
}

fn state_name(s: &State) -> (&'static str, String) {
    match s {
        State::Waiting => ("waiting", String::new()),
        State::Running => ("running", String::new()),
        State::UpToDate => ("up_to_date", String::new()),
        State::Done => ("done", String::new()),
        State::Skipped(w) => ("skipped", w.clone()),
        State::Failed(w) => ("failed", w.clone()),
        State::Blocked => ("blocked", String::new()),
        State::Cancelled => ("cancelled", String::new()),
    }
}

impl Events for Sink {
    fn state(&self, step: &Step, state: &State) {
        let (name, why) = state_name(state);
        self.write(&format!("{}: [{name}] {why}", step.id));
        let mut sh = self.0.lock().unwrap();
        if let Some(r) = sh.rows.iter_mut().find(|r| r.id == step.id) {
            (r.state, r.detail) = state_name(state);
            if matches!(state, State::Done | State::UpToDate) {
                r.fraction = 1.0;
            }
        }
    }
    fn log(&self, step: &Step, line: &str) {
        self.write(&format!("{}: {line}", step.id));
        self.0.lock().unwrap().log.push(format!("{}: {}", step.id, line.replace(&self.1, "")));
    }
    fn fraction(&self, step: &Step, f: f32) {
        if let Some(r) = self.0.lock().unwrap().rows.iter_mut().find(|r| r.id == step.id) {
            r.fraction = f.clamp(0.0, 1.0);
        }
    }
}

fn err(e: anyhow::Error) -> GString {
    GString::from(format!("{e:#}").as_str())
}

fn inputs(json: &GString) -> anyhow::Result<iaf_setup::Inputs> {
    iaf_setup::from_json(&serde_json::from_str(&json.to_string())?)
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafSetup {
    shared: Arc<Mutex<Shared>>,
    cancel: Arc<AtomicBool>,
    /// The background jobs (`begin`): name → None while it runs, else its result as JSON text.
    jobs: Arc<Mutex<std::collections::HashMap<String, Option<String>>>>,
}

#[godot_api]
impl IafSetup {
    /// {kind: "english" | "hebrew" | "none", why}.
    #[func]
    fn check_cd(path: GString) -> VarDictionary {
        match iaf_setup::check_cd(&PathBuf::from(path.to_string())) {
            CdKind::English => vdict! { "kind" => "english", "why" => "" },
            CdKind::Hebrew => vdict! { "kind" => "hebrew", "why" => "" },
            CdKind::NotIaf(why) => vdict! { "kind" => "none", "why" => why.as_str() },
        }
    }

    /// {ok, records, why}.
    #[func]
    fn check_patch(path: GString) -> VarDictionary {
        match iaf_setup::check_patch(&PathBuf::from(path.to_string())) {
            Ok(n) => vdict! { "ok" => true, "records" => n as i64, "why" => "" },
            Err(e) => vdict! { "ok" => false, "records" => 0, "why" => &err(e) },
        }
    }

    /// {ok, brief, menu (file counts), why}.
    #[func]
    fn check_pack(path: GString) -> VarDictionary {
        match iaf_setup::check_pack(&PathBuf::from(path.to_string())) {
            Ok(p) => vdict! { "ok" => true, "brief" => p.brief as i64, "menu" => p.menu as i64, "why" => "" },
            Err(e) => vdict! { "ok" => false, "brief" => 0, "menu" => 0, "why" => &err(e) },
        }
    }

    /// {gdal, curl, python3, firefox, display}: the outside programs present.
    #[func]
    fn tools() -> VarDictionary {
        let t = iaf_setup::tools();
        vdict! { "gdal" => t.gdal, "curl" => t.curl, "python3" => t.python3, "firefox" => t.firefox, "display" => t.display }
    }

    /// The CD launcher's UNINSTALL: removes what the setup wrote under `assets` (`iaf_setup::OUTPUTS`), with
    /// `everything` also the imported packs and the imagery downloads (`iaf_setup::KEPT`); "" or the error.
    #[func]
    fn uninstall(assets: GString, everything: bool) -> GString {
        match iaf_setup::uninstall(&PathBuf::from(assets.to_string()), everything) {
            Ok(()) => GString::new(),
            Err(e) => err(e),
        }
    }

    /// The bytes of the files under `path` (0 when missing): what an earlier run left on disk.
    #[func]
    fn disk_bytes(path: GString) -> i64 {
        iaf_setup::disk_bytes(&PathBuf::from(path.to_string())) as i64
    }

    /// The bytes the scenery's sources for `kinds` ("both", "buildings", "trees") download (the pinned sizes).
    #[func]
    fn scenery_download_bytes(kinds: GString) -> i64 {
        let k = iaf_tools::scenery::Kinds::parse(&kinds.to_string()).unwrap_or_default();
        // With the rest of the theatre's sources and the other countries' extracts (docs/scenery.md §1.1).
        k.downloads()
            .iter()
            .chain(&k.theatre_downloads())
            .chain(iaf_tools::thirdparty::ROADS)
            .map(|d| d.bytes as i64)
            .sum()
    }

    /// The last run's inputs (setup.json's text), or "" before the first run.
    #[func]
    fn load_inputs(assets: GString) -> GString {
        match iaf_setup::load_inputs(&PathBuf::from(assets.to_string())) {
            Ok(Some(i)) => GString::from(iaf_setup::to_json(&i).to_string().as_str()),
            _ => GString::new(),
        }
    }

    /// The plan for `inputs` (setup.json text): [{id, title, required}], empty when the inputs do not parse.
    #[func]
    fn plan(inputs_json: GString) -> VarArray {
        let Ok(i) = inputs(&inputs_json) else { return VarArray::new() };
        iaf_setup::plan(&i)
            .iter()
            .map(|s| vdict! { "id" => s.id, "title" => s.title, "required" => s.required }.to_variant())
            .collect()
    }

    /// Starts a background job (gdext objects can only be called on the main thread, so the slow checks run here);
    /// `result(job)` gives its answer. `job` is a kind, optionally with `#<anything>` after it:
    /// - "preview" [assets, repo, inputs JSON]: {step id: true when a run would find it up to date} (reads the inputs);
    /// - "sim_preview" [assets, repo, survey "1" | "0", left-out step ids…]: the same for Modern IAF's steps;
    /// - "scan" [folder]: {"english" | "hebrew" | "patch" | "brief" | "menu": path} found in it (`iaf_setup::scan`);
    /// - "stale" [assets, layer ids…]: the imagery units older rules made, -1 when it cannot tell (e.g. offline).
    #[func]
    fn begin(&mut self, job: GString, args: PackedStringArray) {
        let (job, args): (String, Vec<String>) =
            (job.to_string(), args.as_slice().iter().map(|s| s.to_string()).collect());
        let jobs = self.jobs.clone();
        jobs.lock().unwrap().insert(job.clone(), None);
        std::thread::spawn(move || {
            let r = std::panic::catch_unwind(|| -> serde_json::Value {
                // "preview#2": the kind before '#', the rest tells runs of the same kind apart.
                match (job.split('#').next().unwrap_or_default(), args.as_slice()) {
                    ("preview", [assets, repo, i]) => {
                        let Ok(i) = iaf_setup::from_json(&serde_json::from_str(i).unwrap_or_default()) else {
                            return serde_json::json!({});
                        };
                        let steps = iaf_setup::plan(&i);
                        let ctx = Ctx {
                            assets: assets.into(),
                            repo: repo.into(),
                            inputs: i,
                            xdg_data_home: None,
                            guides: None,
                        };
                        iaf_setup::preview(&steps, &ctx)
                            .into_iter()
                            .map(|(id, up)| (id.to_string(), serde_json::Value::Bool(up)))
                            .collect()
                    }
                    ("sim_preview", [assets, repo, survey, out @ ..]) => {
                        let out: Vec<&str> = out.iter().map(String::as_str).collect();
                        let inputs = SimInputs { survey: survey == "1", ..Default::default() }.without(&out);
                        let ctx = SimCtx { assets: assets.into(), repo: repo.into(), inputs };
                        iaf_setup::sim_preview(&iaf_setup::sim_plan(&inputs), &ctx)
                            .into_iter()
                            .map(|(id, up)| (id.to_string(), serde_json::Value::Bool(up)))
                            .collect()
                    }
                    ("scan", [dir]) => iaf_setup::scan(dir.as_ref())
                        .into_iter()
                        .map(|(k, p)| (k.to_string(), serde_json::Value::String(p.display().to_string())))
                        .collect(),
                    ("stale", [assets, layers @ ..]) => {
                        let n: anyhow::Result<usize> =
                            layers.iter().map(|id| iaf_setup::imagery_stale(assets.as_ref(), id)).sum();
                        n.map_or(-1, |n| n as i64).into()
                    }
                    _ => serde_json::Value::Null,
                }
            });
            jobs.lock().unwrap().insert(job, Some(r.unwrap_or_default().to_string()));
        });
    }

    /// A job's result as JSON text, once (then it is forgotten); "" while it runs or when there is none.
    #[func]
    fn result(&mut self, job: GString) -> GString {
        let mut jobs = self.jobs.lock().unwrap();
        match jobs.get(&job.to_string()) {
            Some(Some(_)) => GString::from(jobs.remove(&job.to_string()).flatten().unwrap_or_default().as_str()),
            _ => GString::new(),
        }
    }

    /// Starts setup on its own thread: saves the inputs to setup.json, then runs the plan (or only the steps `only`
    /// and what they wait for); the steps in `redo` run although they are up to date ("*": all). The whole log also
    /// goes to `log_file` (its folder made; "" none). "" when started, else why not.
    #[func]
    fn start(
        &mut self,
        assets: GString,
        repo: GString,
        inputs_json: GString,
        redo: PackedStringArray,
        only: PackedStringArray,
        log_file: GString,
    ) -> GString {
        if self.running() {
            return "setup is running".into();
        }
        let i = match inputs(&inputs_json) {
            Ok(i) => i,
            Err(e) => return err(e),
        };
        let (assets, repo) = (PathBuf::from(assets.to_string()), PathBuf::from(repo.to_string()));
        if let Err(e) = iaf_setup::save_inputs(&assets, &i) {
            return err(e);
        }
        let redo: Vec<String> = redo.as_slice().iter().map(|s| s.to_string()).collect();
        let mut steps = iaf_setup::plan(&i);
        let only: Vec<String> = only.as_slice().iter().map(|s| s.to_string()).collect();
        if !only.is_empty() {
            steps = iaf_setup::only(&steps, &only.iter().map(String::as_str).collect::<Vec<_>>());
        }
        let header = format!("setup: {inputs_json}\nredo: {redo:?}, only: {only:?}");
        let prefix = format!("{}/", assets.display());
        self.launch(steps.clone(), &header, log_file, prefix, move |sink, cancel| {
            let guides = |pr: &dyn Progress, c: &AtomicBool| iaf_setup::script_guides(&repo, pr, c);
            let ctx = Ctx { assets, repo: repo.clone(), inputs: i, xdg_data_home: None, guides: Some(&guides) };
            iaf_setup::run(&steps, &ctx, &|id| redo.iter().any(|r| r == "*" || r == id), sink, cancel)
        });
        GString::new()
    }

    /// Modern IAF's plan (`iaf_setup::sim_plan`) with every optional step: [{id, title, required}].
    #[func]
    fn sim_plan(survey: bool) -> VarArray {
        iaf_setup::sim_plan(&SimInputs { survey, ..Default::default() })
            .iter()
            .map(|s| vdict! { "id" => s.id, "title" => s.title, "required" => s.required }.to_variant())
            .collect()
    }

    /// The optional steps the player left out at the last run (`iaf_setup::sim_excluded`).
    #[func]
    fn sim_excluded(assets: GString) -> PackedStringArray {
        iaf_setup::sim_excluded(&PathBuf::from(assets.to_string())).iter().map(|s| GString::from(s.as_str())).collect()
    }

    /// Remembers the optional steps the player left out (the wizard's unticked rows); "" or the error.
    #[func]
    fn sim_save_excluded(assets: GString, ids: PackedStringArray) -> GString {
        let ids: Vec<String> = ids.as_slice().iter().map(|s| s.to_string()).collect();
        match iaf_setup::save_sim_excluded(&PathBuf::from(assets.to_string()), &ids) {
            Ok(()) => GString::new(),
            Err(e) => err(e),
        }
    }

    /// The optional steps' sizes (`iaf_setup::sim_optional`): [{id, built, download, disk, sources, shared}].
    #[func]
    fn sim_optional(assets: GString) -> VarArray {
        iaf_setup::sim_optional(&PathBuf::from(assets.to_string()))
            .iter()
            .map(|o| {
                vdict! { "id" => o.id, "built" => o.built, "download" => o.download as i64, "disk" => o.disk as i64,
                "sources" => o.sources as i64, "shared" => o.shared }
                .to_variant()
            })
            .collect()
    }

    /// What the sim's terrain step would fetch (`iaf_setup::sim_terrain_fetch`): the sources by name, empty when it
    /// reads only local files; ["?"] when it cannot tell.
    #[func]
    fn sim_terrain_fetch(assets: GString, survey: bool) -> PackedStringArray {
        match iaf_setup::sim_terrain_fetch(&PathBuf::from(assets.to_string()), survey) {
            Ok(v) => v.iter().map(|n| GString::from(n.as_str())).collect(),
            Err(_) => PackedStringArray::from(&[GString::from("?")]),
        }
    }

    /// Removes a left-out optional step's data (`iaf_setup::sim_remove`): {freed: bytes, error: "" or why}.
    #[func]
    fn sim_remove(assets: GString, id: GString, downloads: bool) -> VarDictionary {
        match iaf_setup::sim_remove(&PathBuf::from(assets.to_string()), &id.to_string(), downloads) {
            Ok(n) => vdict! { "freed" => n as i64, "error" => "" },
            Err(e) => vdict! { "freed" => 0i64, "error" => format!("{e:#}").as_str() },
        }
    }

    /// The bytes of the sim's Sentinel-2 tiles already cached under `assets` (the wizard's disk check).
    #[func]
    fn sim_s2_cached(assets: GString) -> i64 {
        let cache = PathBuf::from(assets.to_string()).join(iaf_tools::imagery_run::S2_CACHE);
        iaf_tools::sim_terrain::s2_cached_bytes(&cache) as i64
    }

    /// The Survey of Israel sheet ZIPs already under `assets` (Modern IAF's Survey choice needs them).
    #[func]
    fn survey_sheets(assets: GString) -> i64 {
        iaf_setup::survey_sheets(&PathBuf::from(assets.to_string())) as i64
    }

    /// Starts Modern IAF's setup (`iaf_setup::sim_run`) on its own thread, as `start` does the original's, without the
    /// optional steps `excluded` (remembered: `sim_excluded`); `poll` and `cancel` serve both.
    #[func]
    fn sim_start(
        &mut self,
        assets: GString,
        repo: GString,
        survey: bool,
        redo: PackedStringArray,
        excluded: PackedStringArray,
        log_file: GString,
    ) -> GString {
        if self.running() {
            return "setup is running".into();
        }
        let redo: Vec<String> = redo.as_slice().iter().map(|s| s.to_string()).collect();
        let out: Vec<String> = excluded.as_slice().iter().map(|s| s.to_string()).collect();
        if let Err(e) = iaf_setup::save_sim_excluded(&PathBuf::from(assets.to_string()), &out) {
            return err(e);
        }
        let inputs =
            SimInputs { survey, ..Default::default() }.without(&out.iter().map(String::as_str).collect::<Vec<_>>());
        let steps = iaf_setup::sim_plan(&inputs);
        let ctx = SimCtx { assets: PathBuf::from(assets.to_string()), repo: PathBuf::from(repo.to_string()), inputs };
        let header = format!("Modern IAF setup: survey {survey}\nredo: {redo:?}\nleft out: {out:?}");
        let prefix = format!("{}/", ctx.assets.display());
        self.launch(steps.clone(), &header, log_file, prefix, move |sink, cancel| {
            let redo = |id: &str| redo.iter().any(|r| r == "*" || r == id);
            let expected = iaf_setup::sim_expected(&steps, &ctx, &redo);
            for (r, e) in sink.0.lock().unwrap().rows.iter_mut().zip(expected) {
                r.expected = e;
            }
            iaf_setup::sim_run(&steps, &ctx, &redo, sink, cancel)
        });
        GString::new()
    }

    /// {steps: [{id, title, required, state, detail, fraction}], log: new lines since the last poll, done, error, left:
    /// all steps' seconds left from measured durations (-1: not measured), step, of: step `step` of `of` instead}.
    #[func]
    fn poll(&mut self) -> VarDictionary {
        let mut sh = self.shared.lock().unwrap();
        let steps: VarArray = sh
            .rows
            .iter()
            .map(|r| {
                vdict! { "id" => r.id, "title" => r.title, "required" => r.required, "state" => r.state, "detail" => r.detail.as_str(), "fraction" => r.fraction }
                    .to_variant()
            })
            .collect();
        let paces: Vec<iaf_setup::Pace> = sh
            .rows
            .iter()
            .map(|r| iaf_setup::Pace {
                finished: !matches!(r.state, "waiting" | "running"),
                fraction: r.fraction,
                expected: r.expected,
            })
            .collect();
        let (left, step, of) = match iaf_setup::time_left(&paces) {
            iaf_setup::Left::Secs(s) => (s, 0, 0),
            iaf_setup::Left::Step(n, m) => (-1.0, n as i64, m as i64),
        };
        let log: PackedStringArray = sh.log.drain(..).map(|l| GString::from(l.as_str())).collect();
        vdict! {
            "steps" => &steps, "log" => &log, "done" => sh.done, "error" => sh.error.as_str(),
            "left" => left, "step" => step, "of" => of,
        }
    }

    /// Stops the run: the running steps end at their next item.
    #[func]
    fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
    }
}

impl IafSetup {
    fn running(&self) -> bool {
        self.shared.lock().unwrap().rows.iter().any(|r| r.state == "running")
    }

    /// Runs `body` on its own thread with fresh rows for `steps`, the log also to `log_file` (after `header`).
    fn launch(
        &mut self,
        steps: Vec<Step>,
        header: &str,
        log_file: GString,
        prefix: String,
        body: impl FnOnce(&Sink, &AtomicBool) -> Vec<(&'static str, State)> + Send + 'static,
    ) {
        *self.shared.lock().unwrap() = Shared {
            rows: steps
                .iter()
                .map(|s| Row {
                    id: s.id,
                    title: s.title,
                    required: s.required,
                    state: "waiting",
                    detail: String::new(),
                    fraction: 0.0,
                    expected: None,
                })
                .collect(),
            ..Default::default()
        };
        let log_file = PathBuf::from(log_file.to_string());
        let file = (!log_file.as_os_str().is_empty())
            .then(|| {
                std::fs::create_dir_all(log_file.parent()?).ok()?;
                let mut f = std::fs::File::create(&log_file).ok()?;
                let _ = writeln!(f, "{header}");
                Some(Mutex::new(f))
            })
            .flatten();
        self.cancel = Arc::new(AtomicBool::new(false));
        let (shared, cancel) = (self.shared.clone(), self.cancel.clone());
        std::thread::spawn(move || {
            let sink = Sink(shared.clone(), prefix, file);
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| body(&sink, &cancel)));
            let mut sh = shared.lock().unwrap();
            sh.error = match result {
                Err(_) => "setup stopped: an internal error (panic)".into(),
                Ok(states) => states
                    .iter()
                    .filter(|(_, s)| matches!(s, State::Failed(_) | State::Blocked | State::Cancelled))
                    .map(|(id, s)| format!("{id}: {}", state_name(s).0))
                    .collect::<Vec<_>>()
                    .join(", "),
            };
            sh.done = true;
        });
    }
}
