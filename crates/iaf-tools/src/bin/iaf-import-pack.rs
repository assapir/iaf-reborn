//! Import a community mod (zip or folder) as a language/content pack that
//! overlays the base install:
//!
//! `iaf-import-pack <mod.zip|dir> <pack-name> <install-dir> <packs-dir> [--into <dir>]`
//!
//! The mod's contents are placed at `<packs-dir>/<pack-name>/<into>/...` with
//! lower-cased paths, mirroring the base install layout. `--into` is where the
//! mod's readme told users to extract it, relative to the install root
//! (default `resource`). Only game files are imported: files that override a
//! base file with different content, or new files with an extension the base
//! folder already uses.

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::pack;
use iaf_tools::progress::Stdout;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let (positional, into) = match args.iter().position(|a| a == "--into") {
        Some(i) => {
            let into = args.get(i + 1).context("--into needs a value")?.clone();
            ([&args[..i], &args[i + 2..]].concat(), into)
        }
        None => (args.clone(), "resource".to_string()),
    };
    let [_, src, name, install, packs] = &positional[..] else {
        bail!("usage: iaf-import-pack <mod.zip|dir> <pack-name> <install-dir> <packs-dir> [--into <dir>]");
    };
    pack::import(Path::new(src), name, Path::new(install), Path::new(packs), &into, &Stdout, &AtomicBool::new(false))?;
    Ok(())
}
