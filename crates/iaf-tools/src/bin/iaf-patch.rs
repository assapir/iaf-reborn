//! Apply a Pocket Soft .RTPatch update (e.g. the official IAF v1.1 patch) to
//! an extracted install, without Windows.
//!
//!   iaf-patch list  <patch>
//!   iaf-patch apply <patch> <install-dir> <out-dir>
//!
//! `<patch>` is a bare .rtp file, a self-applying patch executable
//! (`iafp1_1.exe`), or a zip / WinZip self-extractor holding one (the
//! downloadable v1.1 patch).
//!
//! `apply` writes each updated file to `<out-dir>/<lower-cased relative path>`;
//! the install directory is only read. Every source and result is checked
//! against the size and checksums the patch carries.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use iaf_tools::rtpatch::{Patch, RecordType, find_embedded};

/// `rel` (Windows separators, any case) under `root`, matched case-insensitively.
fn find_ci(root: &Path, rel: &str) -> Option<PathBuf> {
    let mut p = root.to_path_buf();
    for part in rel.split(['\\', '/']).filter(|s| !s.is_empty()) {
        let exact = p.join(part);
        p = if exact.exists() {
            exact
        } else {
            fs::read_dir(&p)
                .ok()?
                .filter_map(|e| e.ok())
                .find(|e| e.file_name().to_string_lossy().eq_ignore_ascii_case(part))?
                .path()
        };
    }
    Some(p)
}

/// The raw bytes of `path`, or of the first `.exe` / `.rtp` inside it when it is a zip
/// (self-extracting zips included).
fn read_patch(path: &str) -> Result<Vec<u8>> {
    let raw = fs::read(path).with_context(|| format!("reading {path}"))?;
    if raw.starts_with(b"K*") || find_embedded(&raw).is_some() {
        return Ok(raw);
    }
    let mut zip = zip::ZipArchive::new(std::io::Cursor::new(&raw)).context("not an RTPatch file, patch exe or zip")?;
    for i in 0..zip.len() {
        let mut f = zip.by_index(i)?;
        let name = f.name().to_lowercase();
        if name.ends_with(".exe") || name.ends_with(".rtp") {
            let mut data = Vec::new();
            std::io::Read::read_to_end(&mut f, &mut data)?;
            if data.starts_with(b"K*") || find_embedded(&data).is_some() {
                return Ok(data);
            }
        }
    }
    bail!("{path}: no RTPatch file inside")
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let (cmd, patch_path) = match &args[..] {
        [_, c, p, ..] => (c.as_str(), p),
        _ => bail!("usage: iaf-patch list <patch>  |  iaf-patch apply <patch> <install-dir> <out-dir>"),
    };
    let raw = read_patch(patch_path)?;
    let data = find_embedded(&raw).unwrap_or(&raw);
    let patch = Patch::parse(data)?;

    match (cmd, &args[3..]) {
        ("list", []) => {
            println!("RTPatch container version {}, {} records", patch.version, patch.records.len());
            for r in &patch.records {
                let (from, to) = (r.sources.first().map_or(0, |e| e.size), r.dests.first().map_or(0, |e| e.size));
                println!("{:<7?} {:>9} -> {:>9}  diff {:>7}  {}", r.kind, from, to, r.diff.len(), r.path);
            }
        }
        ("apply", [install, out]) => {
            let (install, out) = (Path::new(install), Path::new(out));
            let mut failed = 0;
            for r in &patch.records {
                let src = match (r.kind, find_ci(install, &r.path)) {
                    (_, Some(p)) => fs::read(&p)?,
                    (RecordType::Add, None) => Vec::new(),
                    (_, None) => {
                        eprintln!("MISSING {}", r.path);
                        failed += 1;
                        continue;
                    }
                };
                match patch.apply(r, &src) {
                    Ok(new) => {
                        let dest = out.join(r.path.replace('\\', "/").to_lowercase());
                        fs::create_dir_all(dest.parent().unwrap())?;
                        fs::write(&dest, &new).with_context(|| format!("writing {}", dest.display()))?;
                        println!("ok {} ({} -> {} bytes)", r.path, src.len(), new.len());
                    }
                    Err(e) => {
                        eprintln!("FAIL {e:#}");
                        failed += 1;
                    }
                }
            }
            if failed > 0 {
                bail!("{failed} of {} records not applied", patch.records.len());
            }
        }
        _ => bail!("usage: iaf-patch list <patch>  |  iaf-patch apply <patch> <install-dir> <out-dir>"),
    }
    Ok(())
}
