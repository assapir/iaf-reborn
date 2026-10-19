//! `iaf-patch`'s work: read a Pocket Soft .RTPatch update (a bare .rtp, a self-applying patch exe or a zip /
//! WinZip self-extractor holding one), `unwrap` it, `apply` it to an extracted install.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};

use crate::log;
use crate::progress::{Progress, check, parent};
use crate::rtpatch::{Patch, RecordType, find_embedded};

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
pub fn read_patch(path: &Path) -> Result<Vec<u8>> {
    let raw = fs::read(path).with_context(|| format!("reading {}", path.display()))?;
    if raw.starts_with(b"K*") || find_embedded(&raw).is_some() {
        return Ok(raw);
    }
    let mut zip = zip::ZipArchive::new(std::io::Cursor::new(&raw)).context("not an RTPatch file, patch exe or zip")?;
    for i in 0..zip.len() {
        let mut f = zip.by_index(i)?;
        let name = f.name()?.to_lowercase();
        if name.ends_with(".exe") || name.ends_with(".rtp") {
            let mut data = Vec::new();
            std::io::Read::read_to_end(&mut f, &mut data)?;
            if data.starts_with(b"K*") || find_embedded(&data).is_some() {
                return Ok(data);
            }
        }
    }
    bail!("{}: no RTPatch file inside", path.display())
}

/// The patch in `raw` (as `read_patch` returns it), parsed.
pub fn parse(raw: &[u8]) -> Result<Patch<'_>> {
    Patch::parse(find_embedded(raw).unwrap_or(raw))
}

/// `iaf-patch unwrap`: writes the patch exe (or bare patch) found in `patch` to `out`, once it parses.
pub fn unwrap(patch: &Path, out: &Path, pr: &dyn Progress) -> Result<()> {
    let raw = read_patch(patch)?;
    parse(&raw)?;
    if let Some(dir) = out.parent() {
        fs::create_dir_all(dir)?;
    }
    fs::write(out, &raw).with_context(|| format!("writing {}", out.display()))?;
    log!(pr, "{} ({} bytes)", out.display(), raw.len());
    Ok(())
}

/// What `apply` did: records written, records missing their source or failing their checks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Applied {
    pub applied: usize,
    pub failed: usize,
}

/// `iaf-patch apply`: each updated file to `<out>/<lower-cased relative path>` (the install is only read),
/// every source and result checked against the patch's sizes and checksums.
pub fn apply(patch: &Path, install: &Path, out: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Applied> {
    let raw = read_patch(patch)?;
    let patch = parse(&raw)?;
    let mut done = Applied { applied: 0, failed: 0 };
    for (n, r) in patch.records.iter().enumerate() {
        check(cancel)?;
        pr.fraction(n as f32 / patch.records.len() as f32);
        let src = match (r.kind, find_ci(install, &r.path)) {
            (_, Some(p)) => fs::read(&p)?,
            (RecordType::Add, None) => Vec::new(),
            (_, None) => {
                pr.warn(&format!("MISSING {}", r.path));
                done.failed += 1;
                continue;
            }
        };
        match patch.apply(r, &src) {
            Ok(new) => {
                let dest = out.join(r.path.replace('\\', "/").to_lowercase());
                fs::create_dir_all(parent(&dest)?)?;
                fs::write(&dest, &new).with_context(|| format!("writing {}", dest.display()))?;
                log!(pr, "ok {} ({} -> {} bytes)", r.path, src.len(), new.len());
                done.applied += 1;
            }
            Err(e) => {
                pr.warn(&format!("FAIL {e:#}"));
                done.failed += 1;
            }
        }
    }
    Ok(done)
}
