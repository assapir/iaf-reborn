//! `IafSetup`: the setup pipeline (`iaf_setup`, docs/setup.md) for the wizard (`game/setup/wizard.gd`). `start` runs
//! the plan on its own thread; the wizard calls `poll` every frame for the steps' states, fractions and new log lines.
//! Inputs travel as setup.json's JSON text (`iaf_setup::to_json` / `from_json`).

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

/// The run's events into `Shared`; log lines name files relative to the assets folder (`prefix`).
struct Sink(Arc<Mutex<Shared>>, String);

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
        let mut sh = self.0.lock().unwrap();
        if let Some(r) = sh.rows.iter_mut().find(|r| r.id == step.id) {
            (r.state, r.detail) = state_name(state);
            if matches!(state, State::Done | State::UpToDate) {
                r.fraction = 1.0;
            }
        }
    }
    fn log(&self, step: &Step, line: &str) {
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
        iaf_setup::plan(&i).iter().map(|s| vdict! { "id" => s.id, "title" => s.title, "required" => s.required }.to_variant()).collect()
    }

    /// The units of imagery layer `id` on disk that older rules made; -1 when it cannot tell (e.g. offline).
    #[func]
    fn imagery_stale(assets: GString, id: GString) -> i64 {
        iaf_setup::imagery_stale(&PathBuf::from(assets.to_string()), &id.to_string()).map_or(-1, |n| n as i64)
    }

    /// Starts setup on its own thread: saves the inputs to setup.json, then runs the plan (or only the steps `only`
    /// and what they wait for); the steps in `redo` run although they are up to date ("*": all). "" when started,
    /// else why not.
    #[func]
    fn start(&mut self, assets: GString, repo: GString, inputs_json: GString, redo: PackedStringArray, only: PackedStringArray) -> GString {
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
            rows: steps.iter().map(|s| Row { id: s.id, title: s.title, required: s.required, state: "waiting", detail: String::new(), fraction: 0.0 }).collect(),
            ..Default::default()
        };
        self.cancel = Arc::new(AtomicBool::new(false));
        let (shared, cancel) = (self.shared.clone(), self.cancel.clone());
        std::thread::spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let guides = |pr: &dyn Progress, c: &AtomicBool| iaf_setup::script_guides(&repo, pr, c);
                let prefix = format!("{}/", assets.display());
                let ctx = Ctx { assets, repo: repo.clone(), inputs: i, xdg_data_home: None, guides: Some(&guides) };
                iaf_setup::run(&steps, &ctx, &|id| redo.iter().any(|r| r == "*" || r == id), &Sink(shared.clone(), prefix), &cancel)
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
