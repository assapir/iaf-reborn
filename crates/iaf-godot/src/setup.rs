//! `IafSetup`: the setup pipeline (`iaf_setup`, docs/setup.md) for the wizard (`game/setup/wizard.gd`). `start` runs
//! the plan on its own thread; the wizard calls `poll` every frame for the steps' states, fractions and new log lines.
//! Inputs travel as setup.json's JSON text (`iaf_setup::to_json` / `from_json`).

use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use godot::prelude::*;
use iaf_setup::{CdKind, Ctx, Events, State, Step};
use iaf_tools::progress::Progress;

struct Row {
    id: &'static str,
    title: &'static str,
    required: bool,
    state: &'static str,
    detail: String,
    fraction: f32,
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
        if self.shared.lock().unwrap().rows.iter().any(|r| r.state == "running") {
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
                })
                .collect(),
            ..Default::default()
        };
        let log_file = PathBuf::from(log_file.to_string());
        let file = (!log_file.as_os_str().is_empty())
            .then(|| {
                std::fs::create_dir_all(log_file.parent()?).ok()?;
                let mut f = std::fs::File::create(&log_file).ok()?;
                let _ = writeln!(f, "setup: {inputs_json}\nredo: {redo:?}, only: {only:?}");
                Some(Mutex::new(f))
            })
            .flatten();
        self.cancel = Arc::new(AtomicBool::new(false));
        let (shared, cancel) = (self.shared.clone(), self.cancel.clone());
        std::thread::spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let guides = |pr: &dyn Progress, c: &AtomicBool| iaf_setup::script_guides(&repo, pr, c);
                let prefix = format!("{}/", assets.display());
                let ctx = Ctx { assets, repo: repo.clone(), inputs: i, xdg_data_home: None, guides: Some(&guides) };
                iaf_setup::run(
                    &steps,
                    &ctx,
                    &|id| redo.iter().any(|r| r == "*" || r == id),
                    &Sink(shared.clone(), prefix, file),
                    &cancel,
                )
            }));
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
        GString::new()
    }

    /// {steps: [{id, title, required, state, detail, fraction}], log: new lines since the last poll, done, error}.
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
        let log: PackedStringArray = sh.log.drain(..).map(|l| GString::from(l.as_str())).collect();
        vdict! { "steps" => &steps, "log" => &log, "done" => sh.done, "error" => sh.error.as_str() }
    }

    /// Stops the run: the running steps end at their next item.
    #[func]
    fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
    }
}
