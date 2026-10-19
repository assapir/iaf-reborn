//! `iaf-extract`'s work: reproduce the original "Full Install" of Jane's IAF from the CD image (`install`),
//! or copy only the CD launcher's files (`autorun`). All output paths are lower-cased.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result};
use iaf_formats::esa::Esa;
use iaf_formats::iso9660::Iso;
use iaf_formats::ssf::InstallScript;

use crate::log;
use crate::progress::{Progress, check, parent};

/// Files the game reads straight off the CD at runtime; we copy them too.
const CD_RUNTIME_DIRS: &[&str] = &["resource/avi"];

/// The CD's autorun launcher (`autorun.inf` runs `Jauto.exe`; docs/front-end.md §18.1): the program (its startup
/// sound is a resource in it), the poster and the button art with their named-rect files. Copied to `autorun/`.
const AUTORUN_FILES: &[&str] = &["JAUTO.EXE", "POSTER.BMP", "POSTER.RGN", "BUTTONS.BMP", "BUTTONS.RGN"];

fn copy_autorun(iso: &mut Iso, out: &Path, pr: &dyn Progress) -> Result<()> {
    for f in AUTORUN_FILES {
        copy_from_iso(iso, f, &dest_path(out, "autorun", f))?;
    }
    pr.log("cd: autorun files");
    Ok(())
}

fn open(iso: &Path) -> Result<Iso> {
    Iso::open(iso).with_context(|| format!("opening {}", iso.display()))
}

/// `iaf-extract --autorun`: only the CD launcher's files, into `<out>/autorun`.
pub fn autorun(iso: &Path, out: &Path, pr: &dyn Progress) -> Result<()> {
    copy_autorun(&mut open(iso)?, out, pr)
}

fn dest_path(out: &Path, dir: &str, name: &str) -> PathBuf {
    let mut p = out.to_path_buf();
    for part in dir.split('/').filter(|s| !s.is_empty()) {
        p.push(part.to_lowercase());
    }
    p.push(name.to_lowercase());
    p
}

fn write(path: &Path, data: &[u8]) -> Result<()> {
    fs::create_dir_all(parent(path)?)?;
    fs::write(path, data).with_context(|| format!("writing {}", path.display()))
}

fn copy_from_iso(iso: &mut Iso, src: &str, dest: &Path) -> Result<()> {
    let entry = iso.find(src).with_context(|| format!("{src} not found on CD"))?.clone();
    fs::create_dir_all(parent(dest)?)?;
    let mut out = fs::File::create(dest)?;
    io::copy(&mut iso.reader(&entry)?, &mut out)?;
    Ok(())
}

/// `iaf-extract`: the install script's groups out of the CD's archive, its CD-only files, the runtime
/// folders the game reads off the CD and the launcher files, under `out`.
pub fn install(iso_path: &Path, out: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let mut iso = open(iso_path)?;
    let script_entry = iso.find("FINSTALL.SSF").context("FINSTALL.SSF not on CD")?.clone();
    let script = InstallScript::parse(&String::from_utf8_lossy(&iso.read(&script_entry)?));

    let esa_entry = iso.find("setup.esa").context("setup.esa not on CD")?.clone();
    let esa_data = iso.read(&esa_entry)?;
    let esa = Esa::parse(&esa_data)?;

    let mut written = 0usize;
    let mut skipped: BTreeMap<&str, usize> = BTreeMap::new();
    for (n, entry) in esa.entries.iter().enumerate() {
        check(cancel)?;
        pr.fraction(n as f32 / esa.entries.len() as f32);
        let Some(dir) = script.group_dir(&entry.group) else {
            *skipped.entry(entry.group.as_str()).or_default() += 1;
            continue;
        };
        let data = esa.extract(entry)?;
        write(&dest_path(out, dir, &entry.name), &data)?;
        written += 1;
    }
    log!(pr, "archive: {written} files extracted from {} entries", esa.entries.len());
    for (group, n) in &skipped {
        log!(pr, "  skipped installer-only group {group} ({n} files)");
    }

    // INSTALL_EX_FILES: copied from the CD as-is (wildcards expand to a directory).
    for (src, dest_dir) in &script.cd_files {
        check(cancel)?;
        let (src_dir, pattern) = src.rsplit_once('/').unwrap_or(("", src.as_str()));
        if pattern.contains('*') {
            let files: Vec<_> = iso
                .entries()
                .iter()
                .filter(|e| !e.is_dir && e.path.rsplit_once('/').is_some_and(|(d, _)| d.eq_ignore_ascii_case(src_dir)))
                .cloned()
                .collect();
            for e in files {
                let name = e.path.rsplit('/').next().unwrap_or(&e.path);
                copy_from_iso(&mut iso, &e.path, &dest_path(out, dest_dir, name))?;
            }
        } else if iso.find(src).is_none() {
            // The Hebrew CD's script names Previews/Previewes.gid, which the disc does not have.
            log!(pr, "cd: {src} listed by the install script but not on the CD, skipped");
            continue;
        } else {
            copy_from_iso(&mut iso, src, &dest_path(out, dest_dir, pattern))?;
        }
        log!(pr, "cd: {src}");
    }

    for dir in CD_RUNTIME_DIRS {
        check(cancel)?;
        let files: Vec<_> = iso
            .entries()
            .iter()
            .filter(|e| !e.is_dir && e.path.to_lowercase().starts_with(&format!("{dir}/")))
            .cloned()
            .collect();
        for e in files {
            let (d, name) = e.path.rsplit_once('/').with_context(|| format!("{}: no folder", e.path))?;
            copy_from_iso(&mut iso, &e.path, &dest_path(out, d, name))?;
        }
        log!(pr, "cd: {dir}/");
    }
    copy_autorun(&mut iso, out, pr)
}
