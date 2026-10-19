//! `iaf-import-pack`'s work: import a community mod (zip or folder) as a language / content pack overlaying
//! the base install (`<packs>/<name>/<into>/...`, lower-cased). Only game files: files that override a base
//! file with different content, or new files with an extension the base folder already uses.

use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result};

use crate::log;
use crate::progress::{Progress, check, parent};

struct ModFile {
    /// `/`-separated path inside the mod, original case.
    path: String,
    data: Vec<u8>,
}

fn read_zip(path: &Path) -> Result<Vec<ModFile>> {
    let mut zip = zip::ZipArchive::new(fs::File::open(path)?)?;
    let mut files = Vec::new();
    for i in 0..zip.len() {
        let mut f = zip.by_index(i)?;
        if f.is_dir() {
            continue;
        }
        let path = f.name()?.replace('\\', "/");
        let mut data = Vec::with_capacity(f.size() as usize);
        f.read_to_end(&mut data)?;
        files.push(ModFile { path, data });
    }
    Ok(files)
}

fn read_dir(root: &Path) -> Result<Vec<ModFile>> {
    crate::walk_files(root)?
        .into_iter()
        .map(|p| {
            let rel = p.strip_prefix(root)?.to_string_lossy().replace('\\', "/");
            Ok(ModFile { path: rel, data: fs::read(&p)? })
        })
        .collect()
}

fn extension(path: impl AsRef<Path>) -> Option<String> {
    Some(path.as_ref().extension()?.to_string_lossy().to_lowercase())
}

/// Extensions used by files directly inside `dir`.
fn extensions_in(dir: &Path) -> HashSet<String> {
    fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| extension(e.file_name()))
        .collect()
}

/// What `import` did: files overriding a base file, new files, files identical to the base (not copied), and
/// the non-game files skipped.
#[derive(Debug, Clone, Default)]
pub struct Imported {
    pub overrides: usize,
    pub added: usize,
    pub unchanged: usize,
    pub skipped: Vec<String>,
}

/// `iaf-import-pack`: `src` (zip or folder) into `<packs>/<name>/<into>`; `into` is where the mod's readme said
/// to extract it, relative to the install root (the CLI's default: `resource`).
pub fn import(src: &Path, name: &str, install: &Path, packs: &Path, into: &str, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Imported> {
    let files = if src.is_dir() { read_dir(src)? } else { read_zip(src).with_context(|| format!("reading {}", src.display()))? };

    let into = into.to_lowercase();
    let install = install.join(&into);
    let out_root = packs.join(name);
    let mut r = Imported::default();
    for file in &files {
        check(cancel)?;
        // Files at the mod root (readme, .diz) are not game data.
        if !file.path.contains('/') {
            r.skipped.push(file.path.clone());
            continue;
        }
        let rel: PathBuf = file.path.split('/').map(str::to_lowercase).collect();
        let base = install.join(&rel);
        let known_ext = extension(&rel).is_some_and(|e| extensions_in(parent(&base).unwrap_or(&install)).contains(&e));
        if base.is_file() {
            if fs::read(&base)? == file.data {
                r.unchanged += 1;
                continue;
            }
            r.overrides += 1;
        } else if known_ext {
            r.added += 1;
        } else {
            r.skipped.push(file.path.clone());
            continue;
        }
        let dest = out_root.join(&into).join(&rel);
        fs::create_dir_all(parent(&dest)?)?;
        fs::write(&dest, &file.data)?;
    }

    log!(pr, "pack '{name}': {} files override the base install, {} new, {} identical to base (not copied)", r.overrides, r.added, r.unchanged);
    for s in &r.skipped {
        log!(pr, "  skipped non-game file {s:?}");
    }
    log!(pr, "written to {}", out_root.display());
    Ok(r)
}
