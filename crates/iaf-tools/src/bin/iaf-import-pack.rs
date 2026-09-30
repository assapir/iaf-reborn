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

use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};

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
        let path = f.name().replace('\\', "/");
        let mut data = Vec::with_capacity(f.size() as usize);
        f.read_to_end(&mut data)?;
        files.push(ModFile { path, data });
    }
    Ok(files)
}

fn read_dir(root: &Path) -> Result<Vec<ModFile>> {
    iaf_tools::walk_files(root)?
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
    let src = Path::new(src);
    let files = if src.is_dir() { read_dir(src)? } else { read_zip(src).with_context(|| format!("reading {}", src.display()))? };

    let into = into.to_lowercase();
    let install = Path::new(install).join(&into);
    let out_root = Path::new(packs).join(name);
    let (mut overrides, mut added, mut unchanged, mut skipped) = (0, 0, 0, Vec::new());
    for file in &files {
        // Files at the mod root (readme, .diz) are not game data.
        if !file.path.contains('/') {
            skipped.push(file.path.clone());
            continue;
        }
        let rel: PathBuf = file.path.split('/').map(str::to_lowercase).collect();
        let base = install.join(&rel);
        let known_ext = extension(&rel).is_some_and(|e| extensions_in(base.parent().unwrap()).contains(&e));
        if base.is_file() {
            if fs::read(&base)? == file.data {
                unchanged += 1;
                continue;
            }
            overrides += 1;
        } else if known_ext {
            added += 1;
        } else {
            skipped.push(file.path.clone());
            continue;
        }
        let dest = out_root.join(&into).join(&rel);
        fs::create_dir_all(dest.parent().unwrap())?;
        fs::write(&dest, &file.data)?;
    }

    println!("pack '{name}': {overrides} files override the base install, {added} new, {unchanged} identical to base (not copied)");
    for s in &skipped {
        println!("  skipped non-game file {s:?}");
    }
    println!("written to {}", out_root.display());
    Ok(())
}
