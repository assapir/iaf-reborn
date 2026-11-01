//! The converters' sources, one fingerprint per file (`$OUT_DIR/sources.rs`: `SOURCES`, path and FNV-1a hash). A
//! step's stamp holds the fingerprints of the files that decide its output (`stamp::STEP_SOURCES`), so new code in
//! one converter redoes only its steps. A Rust file's comment lines and `mod x;` lines are left out of its hash (they
//! change no output). `Cargo.lock:<crate>` is a crate's locked version(s).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() { walk(&p, out) } else { out.push(p) }
    }
}

fn fnv(bytes: impl IntoIterator<Item = u8>) -> u64 {
    bytes.into_iter().fold(0xcbf29ce484222325, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3))
}

/// The bytes that decide what `f` does: a Rust file without its comment and module-declaration lines.
fn content(f: &Path) -> Vec<u8> {
    let bytes = std::fs::read(f).unwrap_or_default();
    if f.extension().is_none_or(|e| e != "rs") {
        return bytes;
    }
    let text = String::from_utf8_lossy(&bytes);
    let dropped = |l: &str| {
        let l = l.trim();
        let m = l.strip_prefix("pub ").unwrap_or(l);
        l.starts_with("//")
            || m.strip_prefix("mod ")
                .and_then(|m| m.strip_suffix(';'))
                .is_some_and(|m| m.chars().all(|c| c == '_' || c.is_alphanumeric()))
    };
    text.lines().filter(|l| !dropped(l)).flat_map(|l| l.bytes().chain(*b"\n")).collect()
}

fn main() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let parts = [
        "crates/iaf-tools/src",
        "crates/iaf-tools/data",
        "crates/iaf-formats/src",
        "crates/iaf-setup/src",
        "tools/install-launcher.sh",
        "tools/windows/install-launcher.ps1",
    ];
    let mut files = Vec::new();
    for p in parts {
        let p = root.join(p);
        println!("cargo:rerun-if-changed={}", p.display());
        if p.is_dir() { walk(&p, &mut files) } else { files.push(p) }
    }
    files.sort();
    let mut out = String::from("pub(crate) const SOURCES: &[(&str, u64)] = &[\n");
    for f in &files {
        let rel = f.strip_prefix(&root).unwrap_or(f).to_string_lossy().replace('\\', "/");
        out += &format!("    ({rel:?}, 0x{:016x}),\n", fnv(content(f)));
    }
    // Cargo.lock: each crate's versions.
    let lock = root.join("Cargo.lock");
    println!("cargo:rerun-if-changed={}", lock.display());
    let mut crates: BTreeMap<String, String> = BTreeMap::new();
    let mut name = None;
    for l in std::fs::read_to_string(&lock).unwrap_or_default().lines() {
        if let Some(n) = l.strip_prefix("name = ") {
            name = Some(n.trim_matches('"').to_string());
        } else if let (Some(v), Some(n)) = (l.strip_prefix("version = "), name.take()) {
            *crates.entry(n).or_default() += &format!("{v} ");
        }
    }
    for (n, v) in &crates {
        out += &format!("    (\"Cargo.lock:{n}\", 0x{:016x}),\n", fnv(v.bytes()));
    }
    out += "];\n";
    std::fs::write(PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("sources.rs"), out).unwrap();
}
