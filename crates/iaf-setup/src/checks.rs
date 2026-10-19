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
    let exe = esa.entries.iter().find(|e| e.name.eq_ignore_ascii_case("iafjets.exe")).context("no iafjets.exe in the archive")?;
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
        iaf_tools::walk_files(path)?.iter().filter_map(|f| f.strip_prefix(path).ok().map(|r| r.to_string_lossy().replace('\\', "/"))).collect()
    } else {
        let zip = zip::ZipArchive::new(std::fs::File::open(path).with_context(|| format!("{}", path.display()))?).context("not a zip")?;
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
    std::env::var_os("PATH").is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(name).is_file()))
}

pub fn tools() -> Tools {
    let env = |k: &str| std::env::var_os(k).is_some_and(|v| !v.is_empty());
    Tools {
        gdal: on_path("gdal_translate") && on_path("gdalbuildvrt"),
        curl: on_path("curl"),
        python3: on_path("python3"),
        // macOS: the app bundle, which puts nothing on PATH (the same place tools/guide_pdf.py looks).
        firefox: on_path("firefox") || Path::new("/Applications/Firefox.app/Contents/MacOS/firefox").is_file(),
        display: env("DISPLAY") || env("WAYLAND_DISPLAY") || (cfg!(target_os = "macos") && !env("SSH_CONNECTION")),
    }
}
