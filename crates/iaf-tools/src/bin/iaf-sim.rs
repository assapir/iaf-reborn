//! IAF 2026's data compilers (iaf-2026/docs/data-formats.md):
//!
//! `iaf-sim <db|missions|all> [data-dir (iaf-2026/data)] [assets-dir (assets)]`
//!
//! - `db`: the units and weapons → `converted/missions/sim.bdb.json`, `converted/objects/objects.json` ("sim.bdb"),
//!   `converted/own/resource/weaponsmotion/weapons.ibx`;
//! - `missions`: the missions → `converted/iaf-2026/missions/<id>.json` + `missionlist.json`.

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Result, bail};
use iaf_tools::progress::Stdout;
use iaf_tools::sim;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let data = Path::new(args.get(1).map_or("iaf-2026/data", String::as_str));
    let assets = Path::new(args.get(2).map_or("assets", String::as_str));
    let cancel = AtomicBool::new(false);
    match args.first().map(String::as_str) {
        Some("db") => sim::db(data, assets, &Stdout, &cancel),
        Some("missions") => sim::missions(data, assets, &Stdout, &cancel),
        Some("all") => {
            sim::db(data, assets, &Stdout, &cancel)?;
            sim::missions(data, assets, &Stdout, &cancel)
        }
        _ => bail!("usage: iaf-sim <db|missions|all> [data-dir (iaf-2026/data)] [assets-dir (assets)]"),
    }
}
