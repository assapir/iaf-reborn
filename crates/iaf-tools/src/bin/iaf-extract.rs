//! Reproduce the original "Full Install" of Jane's IAF from the CD image,
//! without Windows: `iaf-extract <Jane's IAF.iso> <out-dir>`.
//! `iaf-extract --autorun <iso> <out-dir>` copies only the CD launcher's files (into `<out-dir>/autorun`),
//! for an install extracted before they were part of it.
//!
//! All output paths are lower-cased so lookups behave the same on every OS.

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Result, bail};
use iaf_tools::extract;
use iaf_tools::progress::Stdout;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match &args[..] {
        [_, flag, iso, out] if flag == "--autorun" => extract::autorun(Path::new(iso), Path::new(out), &Stdout),
        [_, iso, out] => extract::install(Path::new(iso), Path::new(out), &Stdout, &AtomicBool::new(false)),
        _ => bail!("usage: iaf-extract [--autorun] <Jane's IAF.iso> <out-dir>"),
    }
}
