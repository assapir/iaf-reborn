//! The setup pipeline from a terminal (for testing; tools/setup-cli.sh is the scripted way, the wizard the graphical one):
//!
//!   iaf-setup [--assets DIR] [--patch <v1.1 patch>] [--hebrew-iso <Hebrew CD>] [--imagery sentinel2,mapi2015,mapi2015-bases]
//!             [--guides] [--refresh-imagery] [--redo-all] [--xdg-data-home DIR] ["<Jane's IAF.iso>" [Brief.zip] [Menu.zip]]
//!   iaf-setup check <file>      what a CD image, patch or pack is
//!
//! `--assets` defaults to the repo's `assets/`. Without the ISO the last run's inputs (`assets/setup.json`) are used, with
//! the options given added. Steps whose stamp holds are "up to date"; `--redo-all` runs every step anyway.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_setup::{Ctx, Events, Hebrew, Imagery, Inputs, State, Step};
use iaf_tools::progress::Progress;

const USAGE: &str = "usage: iaf-setup [--assets DIR] [--patch P] [--hebrew-iso ISO] [--imagery sentinel2,mapi2015,mapi2015-bases] [--guides] [--refresh-imagery] [--redo-all] [--xdg-data-home DIR] [<Jane's IAF.iso> [Brief.zip] [Menu.zip]]\n       iaf-setup check <file>";

struct Print;

impl Events for Print {
    fn state(&self, step: &Step, state: &State) {
        match state {
            State::Waiting => {}
            State::Running => println!("==> {}", step.title),
            s => println!("    {}: {s:?}", step.id),
        }
    }
    fn log(&self, step: &Step, line: &str) {
        println!("[{}] {line}", step.id);
    }
}

fn main() -> Result<()> {
    let repo = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let [cmd, file] = &args[..]
        && cmd == "check"
    {
        let p = Path::new(file);
        println!("cd: {:?}", iaf_setup::check_cd(p));
        println!(
            "patch: {:?}",
            iaf_setup::check_patch(p).map_err(|e| format!("{e:#}"))
        );
        println!(
            "pack: {:?}",
            iaf_setup::check_pack(p).map_err(|e| format!("{e:#}"))
        );
        println!("tools: {:?}", iaf_setup::tools());
        return Ok(());
    }
    let (mut assets, mut patch, mut hebrew_iso, mut imagery, mut guides, mut redo_all, mut xdg) = (
        repo.join("assets"),
        None,
        None,
        Vec::new(),
        false,
        false,
        None,
    );
    let mut refresh = false;
    let mut pos = Vec::new();
    let mut it = args.into_iter();
    while let Some(a) = it.next() {
        let mut val = || it.next().context(USAGE);
        match a.as_str() {
            "--assets" => assets = PathBuf::from(val()?),
            "--patch" => patch = Some(PathBuf::from(val()?)),
            "--hebrew-iso" => hebrew_iso = Some(PathBuf::from(val()?)),
            "--imagery" => {
                for s in val()?.split(',') {
                    imagery.push(match s {
                        "sentinel2" => Imagery::Sentinel2,
                        "mapi2015" => Imagery::Mapi2015 { bases: false },
                        "mapi2015-bases" => Imagery::Mapi2015 { bases: true },
                        _ => bail!(
                            "unknown imagery source '{s}' (sentinel2, mapi2015, mapi2015-bases)"
                        ),
                    });
                }
            }
            "--guides" => guides = true,
            "--refresh-imagery" => refresh = true,
            "--redo-all" => redo_all = true,
            "--xdg-data-home" => xdg = Some(PathBuf::from(val()?)),
            "-h" | "--help" => bail!(USAGE),
            _ => pos.push(PathBuf::from(a)),
        }
    }
    let mut pos = pos.into_iter();
    let (cd, brief, menu) = (pos.next(), pos.next(), pos.next());
    let given = match (hebrew_iso, brief, menu) {
        (Some(iso), _, _) => Some(Hebrew::Cd(iso)),
        (None, None, None) => None,
        (None, brief, menu) => Some(Hebrew::Packs { brief, menu }),
    };
    let inputs = match cd {
        Some(cd) => Inputs {
            cd,
            patch,
            hebrew: given.unwrap_or(Hebrew::None),
            imagery,
            refresh,
            guides,
        },
        // Setup again: the last inputs, plus what is given now.
        None => {
            let mut i = iaf_setup::load_inputs(&assets)?.context(USAGE)?;
            i.patch = patch.or(i.patch);
            i.hebrew = given.unwrap_or(i.hebrew);
            for m in imagery {
                if !i.imagery.contains(&m) {
                    i.imagery.push(m);
                }
            }
            i.guides |= guides;
            i.refresh |= refresh;
            i
        }
    };
    iaf_setup::save_inputs(&assets, &inputs)?;
    let render =
        |pr: &dyn Progress, cancel: &AtomicBool| iaf_setup::script_guides(&repo, pr, cancel);
    let ctx = Ctx {
        assets,
        repo: repo.clone(),
        inputs: inputs.clone(),
        xdg_data_home: xdg,
        guides: if iaf_setup::tools().display {
            Some(&render)
        } else {
            None
        },
    };
    let steps = iaf_setup::plan(&inputs);
    let t0 = std::time::Instant::now();
    let states = iaf_setup::run(&steps, &ctx, &|_| redo_all, &Print, &AtomicBool::new(false));
    println!("\nsetup ({}):", iaf_tools::progress::duration(t0.elapsed()));
    let mut failed = false;
    for (id, s) in &states {
        println!("  {id:15} {s:?}");
        failed |= matches!(s, State::Failed(_) | State::Blocked | State::Cancelled);
    }
    if failed {
        bail!("setup did not finish");
    }
    Ok(())
}
