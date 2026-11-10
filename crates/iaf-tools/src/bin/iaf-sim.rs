//! Modern IAF's data compilers (modern-iaf/docs/data-formats.md):
//!
//! `iaf-sim <db|missions|own|fm|airbases|scenery|all> [data-dir (modern-iaf/data)] [assets-dir (assets)]`
//! `iaf-sim terrain [assets-dir (assets)] [--box E0 N0 E1 N1] [--out <dir>] [--threads N]`
//! `iaf-sim voices [--only <part of a file name>]` / `iaf-sim voices --say <role> <mode> <text> <out.ogg>`
//!
//! - `db`: the units and weapons → `converted/missions/sim.bdb.json`, `converted/objects/objects.json` ("sim.bdb"),
//!   `converted/own/resource/weaponsmotion/weapons.ibx`;
//! - `missions`: the missions → `converted/modern-iaf/missions/<id>.json` + `missionlist.json`;
//! - `airbases`: the four bases into the theatre's frame (modern-iaf/docs/airbases.md "In the game") →
//!   `converted/terrain/israel/airbases.json` + masks, `converted/own/iaf.ibx`, `converted/own/terraintype.dat`; needs
//!   the terrain;
//! - `scenery`: the buildings, trees, roads and city lights' stand-ins in the theatre's frame (modern-iaf/docs/scenery.md)
//!   → `converted/terrain/israel/scenery/`, `converted/terrain/israel/roads/`; needs the terrain, the airbases' step
//!   and GDAL; downloads only what `assets/source/scenery` and `assets/source/roads` lack;
//! - `fm`: the jets' flight data (modern-iaf/docs/flight-model.md) → `converted/own/resource/md/` (`bd.ibx`, `f16.dat`,
//!   `f15.dat`); the data dir is not read;
//! - `all`: db, own, fm, airbases and scenery (when the terrain is built; the scenery optional), missions;
//! - `own`: the sound table and clips → `converted/own/resource/soundfiles/`, the key table → `converted/own/keys.json`,
//!   each jet's cockpit display data → `converted/own/cockpits/<jet>/`, the F-16's aircraft descriptor from the repo's
//!   own model → `converted/own/planes/` (run it from the repo root);
//! - `terrain`: the theatre (modern-iaf/docs/terrain.md) → `converted/terrain/israel/` (`--out`: another folder),
//!   over the UTM 36N box `--box` (default `sim_terrain::BOX`);
//! - `voices`: Kokoro text to speech through Betty's chain or the radio chain (modern-iaf/docs/sound.md §5) →
//!   the clips in `modern-iaf/data/sounds/`, then the sounds of `own` → `converted/own/resource/soundfiles/`; needs
//!   ffmpeg and the Python of `tools/iaf-2026/kokoro_tts.py` (`IAF_KOKORO_PYTHON`); run it from the repo root.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::progress::Stdout;
use iaf_tools::{sim, sim_bases, sim_fm0, sim_scenery, sim_terrain, sim_voices};

fn terrain(args: &[String], cancel: &AtomicBool) -> Result<()> {
    let mut assets = PathBuf::from("assets");
    let (mut area, mut out, mut threads) = (sim_terrain::BOX, None, iaf_tools::terrain::default_threads());
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
    let data = Path::new(args.get(1).map_or("modern-iaf/data", String::as_str));
    let assets = Path::new(args.get(2).map_or("assets", String::as_str));
    sim::move_old_converted(assets)?;
    let cancel = AtomicBool::new(false);
    match args.first().map(String::as_str) {
        Some("db") => sim::db(data, assets, &Stdout, &cancel),
        Some("missions") => sim::missions(data, assets, &Stdout, &cancel),
        Some("own") => sim::own(data, Path::new("."), assets, &Stdout, &cancel),
        Some("fm") => sim_fm0::fm(assets, &Stdout),
        Some("airbases") => sim_bases::airbases(data, assets, &Stdout, &cancel),
        Some("terrain") => terrain(&args[1..], &cancel),
        Some("scenery") => sim_scenery::scenery(data, assets, &Stdout, &cancel).map(|s| {
            if s.up_to_date {
                println!("scenery: up to date");
            }
        }),
        Some("all") => {
            sim::db(data, assets, &Stdout, &cancel)?;
            sim::own(data, Path::new("."), assets, &Stdout, &cancel)?;
            sim_fm0::fm(assets, &Stdout)?;
            // The bases need the terrain's heights; the missions then stand on its ground.
            if assets.join("converted/terrain/israel/meta.json").is_file() {
                sim_bases::airbases(data, assets, &Stdout, &cancel)?;
                // Optional: the sim flies without it (no GDAL, offline).
                if let Err(e) = sim_scenery::scenery(data, assets, &Stdout, &cancel) {
                    eprintln!("scenery: skipped: {e:#}");
                }
            } else {
                eprintln!("airbases: no terrain yet (iaf-sim terrain): skipped");
            }
            sim::missions(data, assets, &Stdout, &cancel)
        }
        _ => bail!(
            "usage: iaf-sim <db|missions|own|fm|airbases|scenery|all> [data-dir (modern-iaf/data)] [assets-dir (assets)]\n       \
             iaf-sim terrain [assets-dir (assets)] [--box E0 N0 E1 N1] [--out <dir>] [--threads N]"
        ),
    }
}
