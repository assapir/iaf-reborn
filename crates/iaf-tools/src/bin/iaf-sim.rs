//! IAF 2026's data compilers (iaf-2026/docs/data-formats.md):
//!
//! `iaf-sim <db|missions|own|airbases|all> [data-dir (iaf-2026/data)] [assets-dir (assets)]`
//! `iaf-sim terrain [assets-dir (assets)] [--box E0 N0 E1 N1] [--out <dir>] [--threads N]`
//!
//! - `db`: the units and weapons → `converted/missions/sim.bdb.json`, `converted/objects/objects.json` ("sim.bdb"),
//!   `converted/own/resource/weaponsmotion/weapons.ibx`;
//! - `missions`: the missions → `converted/iaf-2026/missions/<id>.json` + `missionlist.json`;
//! - `airbases`: the four bases into the theatre's frame (iaf-2026/docs/airbases.md "In the game") →
//!   `converted/terrain/israel/airbases.json` + masks, `converted/own/iaf.ibx`, `converted/own/terraintype.dat`; needs
//!   the terrain;
//! - `all`: db, own, airbases (when the terrain is built), missions;
//! - `own`: the sound table and clips → `converted/own/resource/soundfiles/`, the key table → `converted/own/keys.json`;
//! - `terrain`: the theatre (iaf-2026/docs/terrain.md) → `converted/terrain/israel/` (`--out`: another folder),
//!   over the UTM 36N box `--box` (default `sim_terrain::BOX`).

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::progress::Stdout;
use iaf_tools::{sim, sim_bases, sim_terrain};

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
        dem_cache: assets.join("source/dem"),
        sheets: assets.join("source/imagery/mapi2015"),
        airbases: PathBuf::from("iaf-2026/data/airbases"),
        area,
        detail: sim_terrain::DETAIL,
        threads,
    };
    sim_terrain::terrain(&run, &Stdout, cancel)
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let data = Path::new(args.get(1).map_or("iaf-2026/data", String::as_str));
    let assets = Path::new(args.get(2).map_or("assets", String::as_str));
    let cancel = AtomicBool::new(false);
    match args.first().map(String::as_str) {
        Some("db") => sim::db(data, assets, &Stdout, &cancel),
        Some("missions") => sim::missions(data, assets, &Stdout, &cancel),
        Some("own") => sim::own(data, assets, &Stdout, &cancel),
        Some("airbases") => sim_bases::airbases(data, assets, &Stdout, &cancel),
        Some("terrain") => terrain(&args[1..], &cancel),
        Some("all") => {
            sim::db(data, assets, &Stdout, &cancel)?;
            sim::own(data, assets, &Stdout, &cancel)?;
            // The bases need the terrain's heights; the missions then stand on its ground.
            if assets.join("converted/terrain/israel/meta.json").is_file() {
                sim_bases::airbases(data, assets, &Stdout, &cancel)?;
            } else {
                eprintln!("airbases: no terrain yet (iaf-sim terrain): skipped");
            }
            sim::missions(data, assets, &Stdout, &cancel)
        }
        _ => bail!(
            "usage: iaf-sim <db|missions|own|airbases|all> [data-dir (iaf-2026/data)] [assets-dir (assets)]\n       \
             iaf-sim terrain [assets-dir (assets)] [--box E0 N0 E1 N1] [--out <dir>] [--threads N]"
        ),
    }
}
