//! Reproduce the original "Full Install" of Jane's IAF from the CD image,
//! without Windows: `iaf-extract <Jane's IAF.iso> <out-dir>`.
//!
//! All output paths are lower-cased so lookups behave the same on every OS.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use iaf_formats::esa::Esa;
use iaf_formats::iso9660::Iso;
use iaf_formats::ssf::InstallScript;

/// Files the game reads straight off the CD at runtime; we copy them too.
const CD_RUNTIME_DIRS: &[&str] = &["resource/avi"];

fn dest_path(out: &Path, dir: &str, name: &str) -> PathBuf {
    let mut p = out.to_path_buf();
    for part in dir.split('/').filter(|s| !s.is_empty()) {
        p.push(part.to_lowercase());
    }
    p.push(name.to_lowercase());
    p
}

fn write(path: &Path, data: &[u8]) -> Result<()> {
    fs::create_dir_all(path.parent().unwrap())?;
    fs::write(path, data).with_context(|| format!("writing {}", path.display()))
}

fn copy_from_iso(iso: &mut Iso, src: &str, dest: &Path) -> Result<()> {
    let entry = iso.find(src).with_context(|| format!("{src} not found on CD"))?.clone();
    fs::create_dir_all(dest.parent().unwrap())?;
    let mut out = fs::File::create(dest)?;
    io::copy(&mut iso.reader(&entry)?, &mut out)?;
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let [_, iso_path, out] = &args[..] else {
        bail!("usage: iaf-extract <Jane's IAF.iso> <out-dir>");
    };
    let out = Path::new(out);
    let mut iso = Iso::open(iso_path).with_context(|| format!("opening {iso_path}"))?;

    let script_entry = iso.find("FINSTALL.SSF").context("FINSTALL.SSF not on CD")?.clone();
    let script = InstallScript::parse(&String::from_utf8_lossy(&iso.read(&script_entry)?));

    let esa_entry = iso.find("setup.esa").context("setup.esa not on CD")?.clone();
    let esa_data = iso.read(&esa_entry)?;
    let esa = Esa::parse(&esa_data)?;

    let mut written = 0usize;
    let mut skipped: BTreeMap<&str, usize> = BTreeMap::new();
    for entry in &esa.entries {
        let Some(dir) = script.group_dir(&entry.group) else {
            *skipped.entry(entry.group.as_str()).or_default() += 1;
            continue;
        };
        let data = esa.extract(entry)?;
        write(&dest_path(out, dir, &entry.name), &data)?;
        written += 1;
    }
    println!("archive: {written} files extracted from {} entries", esa.entries.len());
    for (group, n) in &skipped {
        println!("  skipped installer-only group {group} ({n} files)");
    }

    // INSTALL_EX_FILES: copied from the CD as-is (wildcards expand to a directory).
    for (src, dest_dir) in &script.cd_files {
        let (src_dir, pattern) = src.rsplit_once('/').unwrap_or(("", src.as_str()));
        if pattern.contains('*') {
            let files: Vec<_> = iso
                .entries()
                .iter()
                .filter(|e| !e.is_dir && e.path.rsplit_once('/').is_some_and(|(d, _)| d.eq_ignore_ascii_case(src_dir)))
                .cloned()
                .collect();
            for e in files {
                let name = e.path.rsplit('/').next().unwrap();
                copy_from_iso(&mut iso, &e.path, &dest_path(out, dest_dir, name))?;
            }
        } else if iso.find(src).is_none() {
            // The Hebrew CD's script names Previews/Previewes.gid, which the disc does not have.
            println!("cd: {src} listed by the install script but not on the CD, skipped");
            continue;
        } else {
            copy_from_iso(&mut iso, src, &dest_path(out, dest_dir, pattern))?;
        }
        println!("cd: {src}");
    }

    for dir in CD_RUNTIME_DIRS {
        let files: Vec<_> = iso
            .entries()
            .iter()
            .filter(|e| !e.is_dir && e.path.to_lowercase().starts_with(&format!("{dir}/")))
            .cloned()
            .collect();
        for e in files {
            let (d, name) = e.path.rsplit_once('/').unwrap();
            copy_from_iso(&mut iso, &e.path, &dest_path(out, d, name))?;
        }
        println!("cd: {dir}/");
    }
    Ok(())
}
