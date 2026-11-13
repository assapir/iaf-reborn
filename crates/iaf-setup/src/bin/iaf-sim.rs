//! Modern IAF's data compilers (modern-iaf/data-formats.md), through setup's step graph: every step a command names
//! runs as the setup wizard runs it (the steps before it first when they are not up to date), and writes the stamp the
//! wizard reads, so a step built here is "up to date" there (modern-iaf/docs/setup.md §3). Outputs built before by a
//! run that wrote no stamp are adopted when they are current (`iaf_setup::sim_adopt`).
//!
//! `iaf-sim <terrain|db|missions|own|fm|airbases|scenery|textures|all> [assets-dir (assets)] [--redo]` (run from the
//! repo root: the data is `modern-iaf/data`)
//! `iaf-sim adopt [assets-dir (assets)]`: only stamp the current outputs built without a stamp; prints each step's state
//! `iaf-sim terrain --box E0 N0 E1 N1 | --out <dir> [--threads N] [assets-dir]`: a theatre elsewhere (tests, studies):
//!   not the theatre setup reads, so not a step and not stamped
//! `iaf-sim voices [--only <part of a file name>]` / `iaf-sim voices --say <role> <mode> <text> <out.ogg>`
//!
//! - `terrain`: the theatre (modern-iaf/docs/terrain.md) → `converted/terrain/israel/`;
//! - `db`: the units and weapons → `converted/missions/sim.bdb.json`, `converted/objects/objects.json` ("sim.bdb"),
//!   `converted/own/resource/weaponsmotion/weapons.ibx`;
//! - `missions`: the missions → `converted/modern-iaf/missions/<id>.json` + `missionlist.json`;
//! - `airbases`: the four bases into the theatre's frame (modern-iaf/docs/airbases.md "In the game") →
//!   `converted/terrain/israel/airbases.json` + masks, `converted/own/iaf.ibx`, `converted/own/terraintype.dat`;
//! - `scenery`: the buildings, trees, roads and city lights' stand-ins (modern-iaf/docs/scenery.md) →
//!   `converted/terrain/israel/scenery/`, `converted/terrain/israel/roads/`; needs GDAL;
//! - `fm`: the jets' flight data (modern-iaf/docs/flight-model.md) → `converted/own/resource/md/`;
//! - `own`: the sound table and clips, the key table, the cockpit display data, the F-16's aircraft descriptor;
//! - `textures`: the CC0 ground and model textures (download);
//! - `all`: every step of the wizard's plan;
//! - `voices`: Kokoro text to speech through Betty's chain or the radio chain (modern-iaf/docs/sound.md §5) →
//!   the clips in `modern-iaf/data/sounds/`, then `own`; needs ffmpeg and the Python of
//!   `tools/iaf-2026/kokoro_tts.py` (`IAF_KOKORO_PYTHON`).

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_setup::{Print, SimCtx, SimInputs, State};
use iaf_tools::progress::Stdout;
use iaf_tools::{sim_terrain, sim_voices};

/// A theatre over another box or into another folder (`--box`, `--out`): not a setup step, no stamp.
fn terrain_elsewhere(args: &[String], cancel: &AtomicBool) -> Result<()> {
    let mut assets = PathBuf::from("assets");
    let (mut area, mut out, mut threads) = (sim_terrain::BOX, None, iaf_tools::progress::threads());
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let mut val = || it.next().with_context(|| format!("{a}: value missing"));
        match a.as_str() {
            "--box" => {
                for v in &mut area {
                    *v = val()?.parse()?;
                }
            }
            "--out" => out = Some(PathBuf::from(val()?)),
            "--threads" => threads = val()?.parse()?,
            _ if !a.starts_with("--") => assets = PathBuf::from(a),
            _ => bail!("unknown option {a}"),
        }
    }
    let run = sim_terrain::Run {
        out: out.unwrap_or_else(|| assets.join("converted/terrain/israel")),
        dem_cache: assets.join(iaf_tools::imagery_run::DEM_CACHE),
        s2_cache: assets.join(iaf_tools::imagery_run::S2_CACHE),
        sheet_index: assets.join("converted/imagery/.work/mapi2015/sheets.tsv"),
        sheets: assets.join("source/imagery/mapi2015"),
        airbases: PathBuf::from("modern-iaf/data/airbases"),
        osm: assets.clone(),
        area,
        detail: sim_terrain::DETAIL,
        threads,
    };
    sim_terrain::terrain(&run, &Stdout, cancel)
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("voices") {
        let (data, repo) = (Path::new("modern-iaf/data"), Path::new("."));
        return match &args[1..] {
            [o, role, mode, text, out] if o == "--say" => sim_voices::say(data, repo, role, mode, text, Path::new(out)),
            [o, only] if o == "--only" => {
                sim_voices::voices(data, repo, Path::new("assets"), Some(only), &Stdout, &AtomicBool::new(false))
            }
            [] => sim_voices::voices(data, repo, Path::new("assets"), None, &Stdout, &AtomicBool::new(false)),
            _ => bail!("usage: iaf-sim voices [--only <part of a file name>] | --say <role> <mode> <text> <out.ogg>"),
        };
    }
    let cmd = args.first().map(String::as_str).unwrap_or("");
    if cmd == "terrain" && args.iter().any(|a| a == "--box" || a == "--out") {
        return terrain_elsewhere(&args[1..], &AtomicBool::new(false));
    }
    let ids: &[&str] = match cmd {
        "terrain" => &["sim-terrain"],
        "db" => &["sim-db"],
        "missions" => &["sim-missions"],
        "own" => &["sim-own"],
        "fm" => &["sim-fm"],
        "airbases" => &["sim-airbases"],
        "scenery" => &["sim-scenery"],
        "textures" => &["sim-textures"],
        "all" | "adopt" => &[],
        _ => bail!(
            "usage: iaf-sim <terrain|db|missions|own|fm|airbases|scenery|textures|all|adopt> [assets-dir (assets)] [--redo]\n       \
             iaf-sim terrain --box E0 N0 E1 N1 | --out <dir> [--threads N] [assets-dir]\n       \
             iaf-sim voices [--only <part>] | --say <role> <mode> <text> <out.ogg>"
        ),
    };
    let redo = args.iter().any(|a| a == "--redo");
    if let Some(a) = args[1..].iter().find(|a| a.starts_with("--") && *a != "--redo") {
        bail!("unknown option {a}");
    }
    let dirs: Vec<&String> = args[1..].iter().filter(|a| !a.starts_with("--")).collect();
    if dirs.len() > 1 {
        bail!("one assets folder only (the data is modern-iaf/data): {dirs:?}");
    }
    let assets = PathBuf::from(dirs.first().map_or("assets", |a| a.as_str()));
    let repo = std::env::current_dir()?;
    if !repo.join("modern-iaf/data").is_dir() {
        bail!("run iaf-sim from the repo root (modern-iaf/data not found)");
    }
    // The wizard's choices: the built theatre's imagery (else the Survey photo when its sheets are there), the
    // optional steps it left out.
    let survey = iaf_setup::sim_survey(&assets, &repo);
    let excluded = iaf_setup::sim_excluded(&assets);
    let excluded: Vec<&str> = excluded.iter().map(String::as_str).collect();
    let inputs = SimInputs { survey, ..SimInputs::default() }.without(&excluded);
    let plan = iaf_setup::sim_plan(&inputs);
    let ctx = SimCtx { assets, repo, inputs };
    if cmd == "adopt" {
        let adopted = iaf_setup::sim_adopt(&plan, &ctx);
        println!("adopted: {}", if adopted.is_empty() { "none".to_string() } else { adopted.join(", ") });
        for (id, up) in iaf_setup::sim_preview(&plan, &ctx) {
            println!("  {id:15} {}", if up { "up to date" } else { "will run" });
        }
        return Ok(());
    }
    if let Some(id) = ids.iter().find(|id| !plan.iter().any(|s| s.id == **id)) {
        bail!("{id} is left out in setup (assets/converted/modern-iaf/setup.json)");
    }
    // A step run alone goes through the same graph, so it writes the stamp the wizard reads.
    let steps = if ids.is_empty() { plan } else { iaf_setup::only(&plan, ids) };
    let named = |id: &str| redo && (ids.is_empty() || ids.contains(&id));
    let states = iaf_setup::sim_run(&steps, &ctx, &named, &Print, &AtomicBool::new(false));
    let mut failed = false;
    for (id, s) in &states {
        println!("  {id:15} {s:?}");
        failed |= matches!(s, State::Failed(_) | State::Blocked | State::Cancelled);
    }
    if failed {
        bail!("not finished");
    }
    Ok(())
}
