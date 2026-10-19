//! The converters' fingerprint (`SETUP_CODE`): an FNV-1a hash of the sources and data that decide what setup writes
//! (iaf-tools, iaf-formats, this crate, Cargo.lock). A step's stamp holds it, so new converter code redoes the steps.

use std::path::{Path, PathBuf};

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() { walk(&p, out) } else { out.push(p) }
    }
}

fn main() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let parts = ["crates/iaf-tools/src", "crates/iaf-tools/data", "crates/iaf-formats/src", "crates/iaf-setup/src", "Cargo.lock"];
    let mut files = Vec::new();
    for p in parts {
        let p = root.join(p);
        println!("cargo:rerun-if-changed={}", p.display());
        if p.is_dir() { walk(&p, &mut files) } else { files.push(p) }
    }
    files.sort();
    let mut h: u64 = 0xcbf29ce484222325;
    for f in &files {
        let rel = f.strip_prefix(&root).unwrap_or(f).to_string_lossy().into_owned();
        for b in rel.bytes().chain(std::fs::read(f).unwrap_or_default()) {
            h = (h ^ b as u64).wrapping_mul(0x100000001b3);
        }
    }
    println!("cargo:rustc-env=SETUP_CODE={h:016x}");
}
