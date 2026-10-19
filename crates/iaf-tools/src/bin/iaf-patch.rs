//! Apply a Pocket Soft .RTPatch update (e.g. the official IAF v1.1 patch) to
//! an extracted install, without Windows.
//!
//!   iaf-patch list   <patch>
//!   iaf-patch apply  <patch> <install-dir> <out-dir>
//!   iaf-patch unwrap <patch> <out.exe>
//!
//! `<patch>` is a bare .rtp file, a self-applying patch executable
//! (`iafp1_1.exe`), or a zip / WinZip self-extractor holding one (the
//! downloadable v1.1 patch).
//!
//! `apply` writes each updated file to `<out-dir>/<lower-cased relative path>`;
//! the install directory is only read. Every source and result is checked
//! against the size and checksums the patch carries. `unwrap` writes the patch exe (or bare patch)
//! found inside a zip / self-extractor, e.g. `iafp1_1.exe` out of the downloaded v1.1 update.

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Result, bail};
use iaf_tools::patch;
use iaf_tools::progress::Stdout;

const USAGE: &str = "usage: iaf-patch list <patch>  |  iaf-patch apply <patch> <install-dir> <out-dir>  |  iaf-patch unwrap <patch> <out.exe>";

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let p = Path::new;
    match &args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [_, "unwrap", patch, out] => patch::unwrap(p(patch), p(out), &Stdout),
        [_, "list", path] => {
            let raw = patch::read_patch(p(path))?;
            let patch = patch::parse(&raw)?;
            println!("RTPatch container version {}, {} records", patch.version, patch.records.len());
            for r in &patch.records {
                let (from, to) = (r.sources.first().map_or(0, |e| e.size), r.dests.first().map_or(0, |e| e.size));
                println!("{:<7?} {:>9} -> {:>9}  diff {:>7}  {}", r.kind, from, to, r.diff.len(), r.path);
            }
            Ok(())
        }
        [_, "apply", patch, install, out] => {
            let done = patch::apply(p(patch), p(install), p(out), &Stdout, &AtomicBool::new(false))?;
            if done.failed > 0 {
                bail!("{} of {} records not applied", done.failed, done.failed + done.applied);
            }
            Ok(())
        }
        _ => bail!(USAGE),
    }
}
