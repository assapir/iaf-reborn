//! What the player gives setup, checked before a run: the CDs, the patch, the Hebrew packs, and the outside programs.

use std::path::Path;

use anyhow::{Context, Result, bail};
use iaf_formats::esa::Esa;
use iaf_formats::iso9660::Iso;
use iaf_tools::exe::PeImage;

/// What a CD image is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CdKind {
    /// The English CD (v1.0; the game runs from it).
    English,
    /// The Hebrew retail CD (its translated briefings and menus; its exe is the copy-protected build).
    Hebrew,
    /// Not a Jane's IAF CD, and why.
    NotIaf(String),
}

/// The share of Hebrew letters (Windows-1255 0xE0..=0xFA) among a text's non-ASCII-control bytes.
fn hebrew_share(data: &[u8]) -> f64 {
    let letters = data.iter().filter(|&&b| (0xe0..=0xfa).contains(&b)).count();
    let text = data.iter().filter(|&&b| b >= 0x20).count();
    if text == 0 { 0.0 } else { letters as f64 / text as f64 }
}

/// Probes a CD image: the install script and archive make it a Jane's IAF CD; Hebrew menu strings (`.trx`, Windows-1255)
/// make it the Hebrew CD; otherwise its `iafjets.exe` must be a release the tools know (`PeImage::release`).
pub fn check_cd(path: &Path) -> CdKind {
    match probe(path) {
        Ok(k) => k,
        Err(e) => CdKind::NotIaf(format!("{e:#}")),
    }
}

fn probe(path: &Path) -> Result<CdKind> {
    let mut iso = Iso::open(path).context("not a CD image (ISO 9660)")?;
    if iso.find("FINSTALL.SSF").is_none() {
        return Ok(CdKind::NotIaf("no Jane's IAF install script (FINSTALL.SSF)".into()));
    }
    let Some(esa) = iso.find("setup.esa").cloned() else {
        return Ok(CdKind::NotIaf("no Jane's IAF archive (setup.esa)".into()));
    };
    let data = iso.read(&esa)?;
    let esa = Esa::parse(&data)?;
    let mut trx = 0;
    for e in esa.entries.iter().filter(|e| e.name.to_lowercase().ends_with(".trx")) {
        if hebrew_share(&esa.extract(e)?) > 0.3 {
            trx += 1;
        }
    }
    if trx >= 5 {
        return Ok(CdKind::Hebrew);
    }
    let exe = esa
        .entries
        .iter()
        .find(|e| e.name.eq_ignore_ascii_case("iafjets.exe"))
        .context("no iafjets.exe in the archive")?;
    match PeImage::parse(esa.extract(exe)?).and_then(|p| p.release()) {
        Ok(_) => Ok(CdKind::English),
        Err(e) => Ok(CdKind::NotIaf(format!("iafjets.exe is no known release: {e:#}"))),
    }
}

/// Checks a v1.1 patch file (self-extractor, `iafp1_1.exe` or a bare patch): its record count.
pub fn check_patch(path: &Path) -> Result<usize> {
    let raw = iaf_tools::patch::read_patch(path)?;
    let patch = iaf_tools::patch::parse(&raw)?;
    if !patch.records.iter().any(|r| r.path.to_lowercase().ends_with("iafjets.exe")) {
        bail!("{}: a patch, but not for iafjets.exe", path.display());
    }
    Ok(patch.records.len())
}

/// What a Hebrew pack (zip or folder) holds: files for `resource/brief` and `resource/menu`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PackInfo {
    pub brief: usize,
    pub menu: usize,
}

/// Counts a pack's briefing and menu files (`Brief/…`, `Menu/…` at its root, any case).
pub fn check_pack(path: &Path) -> Result<PackInfo> {
    let names: Vec<String> = if path.is_dir() {
        iaf_tools::walk_files(path)?
            .iter()
            .filter_map(|f| f.strip_prefix(path).ok().map(|r| r.to_string_lossy().replace('\\', "/")))
            .collect()
    } else {
        let zip = zip::ZipArchive::new(std::fs::File::open(path).with_context(|| format!("{}", path.display()))?)
            .context("not a zip")?;
        zip.file_names().filter_map(|n| n.ok()).map(|n| n.replace('\\', "/")).collect()
    };
    let mut info = PackInfo::default();
    for n in names.iter().map(|n| n.to_lowercase()) {
        if n.starts_with("brief/") {
            info.brief += 1;
        } else if n.starts_with("menu/") {
            info.menu += 1;
        }
    }
    if info.brief + info.menu == 0 {
        bail!("{}: no Brief/ or Menu/ folder inside", path.display());
    }
    Ok(info)
}

/// The outside programs the optional steps use.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Tools {
    /// gdal_translate and gdalbuildvrt (imagery).
    pub gdal: bool,
    /// curl (the Survey sheets).
    pub curl: bool,
    /// python3 (the Survey sheets' token, the guide PDFs).
    pub python3: bool,
    /// firefox (the Survey sheets' token, the guide PDFs).
    pub firefox: bool,
    /// A display (the guides' pictures are real renders).
    pub display: bool,
}

fn on_path(name: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(program(name)).is_file()))
}

/// A program's file name.
#[cfg(not(windows))]
fn program(name: &str) -> String {
    name.to_string()
}

/// A program's file name: name.exe.
#[cfg(windows)]
fn program(name: &str) -> String {
    format!("{name}.exe")
}

/// Firefox where its installer puts it, off PATH: the app bundle.
#[cfg(target_os = "macos")]
fn firefox_installed() -> bool {
    Path::new("/Applications/Firefox.app/Contents/MacOS/firefox").is_file()
}

/// Firefox where its installer puts it, off PATH: Program Files.
#[cfg(windows)]
fn firefox_installed() -> bool {
    std::env::var_os("ProgramFiles").is_some_and(|p| Path::new(&p).join("Mozilla Firefox/firefox.exe").is_file())
}

#[cfg(not(any(target_os = "macos", windows)))]
fn firefox_installed() -> bool {
    false
}

/// A desktop without DISPLAY / WAYLAND_DISPLAY: macOS and Windows have one unless reached over SSH.
#[cfg(any(target_os = "macos", windows))]
fn desktop() -> bool {
    std::env::var_os("SSH_CONNECTION").is_none_or(|v| v.is_empty())
}

#[cfg(not(any(target_os = "macos", windows)))]
fn desktop() -> bool {
    false
}

pub fn tools() -> Tools {
    let env = |k: &str| std::env::var_os(k).is_some_and(|v| !v.is_empty());
    Tools {
        gdal: on_path("gdal_translate") && on_path("gdalbuildvrt"),
        curl: on_path("curl"),
        python3: on_path("python3"),
        firefox: on_path("firefox") || firefox_installed(),
        display: env("DISPLAY") || env("WAYLAND_DISPLAY") || desktop(),
    }
}

/// Looks in `dir` and its subfolders (3 levels, hidden ones skipped) for the inputs: the first file of each kind, as
/// (`"english"` | `"hebrew"` | `"patch"` | `"brief"` | `"menu"`, path).
pub fn scan(dir: &Path) -> Vec<(&'static str, std::path::PathBuf)> {
    let mut found: Vec<(&'static str, std::path::PathBuf)> = vec![];
    let has = |f: &Vec<(&str, _)>, k| f.iter().any(|(x, _)| *x == k);
    let mut todo = vec![(dir.to_path_buf(), 0)];
    while let Some((at, depth)) = todo.pop() {
        let Ok(rd) = std::fs::read_dir(&at) else { continue };
        let mut entries: Vec<_> = rd.filter_map(|e| e.ok().map(|e| e.path())).collect();
        entries.sort();
        for p in entries {
            let name = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            if p.is_dir() {
                if depth < 3 && !name.starts_with('.') {
                    todo.push((p, depth + 1));
                }
                continue;
            }
            match p.extension().map(|e| e.to_string_lossy().to_lowercase()).as_deref() {
                Some("iso") => {
                    let kind = match check_cd(&p) {
                        CdKind::English => "english",
                        CdKind::Hebrew => "hebrew",
                        CdKind::NotIaf(_) => continue,
                    };
                    if !has(&found, kind) {
                        found.push((kind, p));
                    }
                }
                Some("exe" | "rtp") if !has(&found, "patch") && check_patch(&p).is_ok() => found.push(("patch", p)),
                Some("zip") => match check_pack(&p) {
                    Ok(i) if i.brief > 0 && !has(&found, "brief") => found.push(("brief", p)),
                    Ok(i) if i.menu > 0 && !has(&found, "menu") => found.push(("menu", p)),
                    _ => {}
                },
                _ => {}
            }
        }
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A pack two folders down is found; a zip that is no pack and a hidden folder are not looked at.
    #[test]
    fn scan_finds_a_pack() {
        let dir = std::env::temp_dir().join(format!("iaf-setup-scan-{}", std::process::id()));
        let zip_at = |p: &Path, entry: &str| {
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            let mut z = zip::ZipWriter::new(std::fs::File::create(p).unwrap());
            z.start_file(entry, zip::write::SimpleFileOptions::default()).unwrap();
            z.finish().unwrap();
        };
        zip_at(&dir.join("a/b/Brief.zip"), "Brief/txt/1.rtf");
        zip_at(&dir.join("other.zip"), "readme.txt");
        zip_at(&dir.join(".hidden/Menu.zip"), "Menu/txt/msgs.trx");
        let found = scan(&dir);
        std::fs::remove_dir_all(&dir).unwrap();
        assert_eq!(found, [("brief", dir.join("a/b/Brief.zip"))]);
    }
}
