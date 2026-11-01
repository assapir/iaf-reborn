//! The Survey of Israel 2015 2 m orthophoto sheets (data.gov.il, 79 ZIPs, ~250 MB each) into
//! `assets/source/imagery/mapi2015` (docs/imagery.md §5). data.gov.il sits behind an AWS WAF JavaScript challenge
//! that blocks a plain curl. With the WAF token (`aws-waf-token`) a Firefox profile earned, curl downloads the
//! sheets; without one the links open in the default browser a few at a time, and each finished ZIP is moved from
//! the download folder into place. Sheets already present are skipped; run again to resume.
//! Licence: data.gov.il open licence, credit "© Survey of Israel 2015, via data.gov.il" (docs/imagery-sources.md §2.1).

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::AtomicBool;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};

use crate::progress::{Progress, check, duration};

/// Every sheet: its Hebrew name, then its download link.
const SHEETS: &str = include_str!("../../../tools/imagery/mapi2015_sheets.tsv");
/// The sheets around the airbases (Ramat David, Tel Nof, Ramon; ~2 GB).
const BASES: [&str; 9] = ["shf", "nzr", "nzl", "gdr", "rng", "rsh", "mzr", "hrd", "hlz"];
/// The browser curl presents itself as.
const UA: &str = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0";
/// Links opened in the browser at once.
const BATCH: usize = 4;

/// The sheets still missing from `dest` (only those around the airbases with `bases`): (name, file, link).
fn todo(dest: &Path, bases: bool) -> Vec<(&'static str, &'static str, &'static str)> {
    SHEETS
        .lines()
        .filter_map(|l| l.split_once('\t'))
        .map(|(name, url)| (name, url.rsplit('/').next().unwrap_or(url), url))
        .filter(|(_, f, _)| !bases || BASES.iter().any(|b| f.strip_suffix(".zip") == Some(b)))
        .filter(|(_, f, _)| std::fs::metadata(dest.join(f)).map_or(true, |m| m.len() == 0))
        .collect()
}

/// Downloads the missing sheets into `dest` (module doc).
pub fn fetch(dest: &Path, bases: bool, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    std::fs::create_dir_all(dest)?;
    let todo = todo(dest, bases);
    if todo.is_empty() {
        pr.log(&format!("all sheets present in {}", dest.display()));
        return Ok(());
    }
    match firefox_token() {
        Some(t) => with_token(&todo, dest, &t, pr, cancel),
        None => {
            pr.log("no aws-waf-token for data.gov.il in Firefox (open one sheet link in Firefox, cancel the download, run again");
            pr.log("for the fast path); fetching through your browser's tabs instead");
            with_browser(&todo, dest, pr, cancel)
        }
    }
}

/// The Firefox profile folders on Linux (classic, XDG, snap, flatpak), macOS and Windows.
fn profile_roots() -> Vec<PathBuf> {
    let mut v = Vec::new();
    if let Some(h) = std::env::home_dir() {
        for r in [
            ".mozilla/firefox",
            ".config/mozilla/firefox",
            "snap/firefox/common/.mozilla/firefox",
            ".var/app/org.mozilla.firefox/.mozilla/firefox",
            "Library/Application Support/Firefox/Profiles",
        ] {
            v.push(h.join(r));
        }
    }
    if let Some(a) = std::env::var_os("APPDATA") {
        v.push(PathBuf::from(a).join("Mozilla/Firefox/Profiles"));
    }
    v
}

/// The newest data.gov.il WAF token in any Firefox profile. The cookie store is copied first (Firefox keeps it
/// open), with its write-ahead log, which holds the cookies set since Firefox last checkpointed.
fn firefox_token() -> Option<String> {
    let tmp = std::env::temp_dir().join(format!("iaf-cookies-{}", std::process::id()));
    let mut best: Option<(i64, String)> = None;
    for profile in profile_roots().iter().filter_map(|r| std::fs::read_dir(r).ok()).flatten().flatten() {
        let src = profile.path().join("cookies.sqlite");
        let _ = std::fs::remove_dir_all(&tmp);
        if std::fs::create_dir_all(&tmp).is_err() || std::fs::copy(&src, tmp.join("c.sqlite")).is_err() {
            continue;
        }
        let _ = std::fs::copy(profile.path().join("cookies.sqlite-wal"), tmp.join("c.sqlite-wal"));
        let row = rusqlite::Connection::open(tmp.join("c.sqlite")).ok().and_then(|c| {
            c.query_row(
                "select expiry, value from moz_cookies where host like '%data.gov.il' and name = 'aws-waf-token' \
                 order by expiry desc limit 1",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .ok()
        });
        if let Some(r) = row
            && best.as_ref().is_none_or(|b| r.0 > b.0)
        {
            best = Some(r);
        }
    }
    let _ = std::fs::remove_dir_all(&tmp);
    best.map(|b| b.1).filter(|t| !t.is_empty())
}

/// True when `p` is a whole ZIP: every member reads back with its CRC.
fn zip_ok(p: &Path) -> bool {
    let Ok(mut z) = std::fs::File::open(p).map_err(anyhow::Error::from).and_then(|f| Ok(zip::ZipArchive::new(f)?))
    else {
        return false;
    };
    (0..z.len()).all(|i| z.by_index(i).is_ok_and(|mut e| std::io::copy(&mut e, &mut std::io::sink()).is_ok()))
}

/// The sheets through curl with the token; stops at the first refused one (HTTP 202: the token expired).
fn with_token(
    todo: &[(&str, &str, &str)],
    dest: &Path,
    token: &str,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<()> {
    let (t0, mut got) = (Instant::now(), 0u64);
    for (k, (name, f, url)) in todo.iter().enumerate() {
        check(cancel)?;
        pr.log(&format!("== sheet {} of {}: {f} {name}", k + 1, todo.len()));
        let part = dest.join(format!("{f}.part"));
        let mut c = Command::new("curl")
            .args(["-sS", "-L", "-C", "-", "-A", UA, "-b", &format!("aws-waf-token={token}"), "-w", "%{http_code}"])
            .args(crate::thirdparty::CURL_PATIENCE)
            .arg("-o")
            .arg(&part)
            .arg(url)
            .stdout(Stdio::piped())
            .spawn()
            .context("running curl")?;
        let status = loop {
            if let Some(s) = c.try_wait()? {
                break s;
            }
            if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                let _ = c.kill();
                let _ = c.wait();
                let _ = std::fs::remove_file(&part);
                bail!("cancelled");
            }
            std::thread::sleep(Duration::from_millis(250));
        };
        let code = std::io::read_to_string(c.stdout.take().context("curl's stdout")?)?;
        let whole = code == "200" || code == "206";
        if !status.success() && whole {
            // A broken connection: the part is kept, and the next run resumes it.
            bail!("{f}: download failed ({}); run setup again to resume it", crate::thirdparty::curl_error(status));
        }
        if status.success() && whole && zip_ok(&part) {
            let size = std::fs::metadata(&part)?.len();
            std::fs::rename(&part, dest.join(f))?;
            got += size;
            let secs = t0.elapsed().as_secs_f64();
            let left = Duration::from_secs_f64(secs / (k + 1) as f64 * (todo.len() - k - 1) as f64);
            pr.log(&format!(
                "   {:.0} MB; {:.0} MB so far, {:.1} MB/s, about {} left",
                size as f64 / 1e6,
                got as f64 / 1e6,
                got as f64 / 1e6 / secs.max(0.001),
                duration(left)
            ));
            pr.fraction((k + 1) as f32 / todo.len() as f32);
        } else {
            let _ = std::fs::remove_file(&part);
            if code == "202" {
                bail!(
                    "data.gov.il turned {f} away: Firefox's data.gov.il pass expired. Open this link in Firefox, cancel \
                     the download, then run setup again: {url}"
                );
            }
            if whole {
                bail!("{f} is not a whole ZIP: removed, run setup again to download it again");
            }
            bail!("{f}: data.gov.il answered HTTP {code} ({}); run setup again", crate::thirdparty::curl_error(status));
        }
        std::thread::sleep(Duration::from_secs(2));
    }
    Ok(())
}

/// The browser's download folder: XDG's on Linux, else `~/Downloads`.
fn downloads() -> Result<PathBuf> {
    if let Ok(o) = Command::new("xdg-user-dir").arg("DOWNLOAD").output()
        && o.status.success()
    {
        let d = String::from_utf8_lossy(&o.stdout).trim().to_string();
        if !d.is_empty() {
            return Ok(d.into());
        }
    }
    Ok(std::env::home_dir().context("no home folder")?.join("Downloads"))
}

/// Opens `url` in the default browser.
fn open(url: &str) -> Result<()> {
    let mut c = if cfg!(windows) {
        let mut c = Command::new("rundll32");
        c.args(["url.dll,FileProtocolHandler", url]);
        c
    } else {
        let mut c = Command::new(if cfg!(target_os = "macos") { "open" } else { "xdg-open" });
        c.arg(url);
        c
    };
    c.stdout(Stdio::null()).stderr(Stdio::null()).spawn().context("opening the browser")?;
    Ok(())
}

/// A finished download of `f` in `dirs`: there, no browser partial file beside it (Firefox's `.part`, Chromium's
/// `.crdownload`) and its size stable for 2 s.
fn finished(f: &str, dirs: &[&Path]) -> Option<PathBuf> {
    dirs.iter().map(|d| d.join(f)).find(|p| {
        let len = || std::fs::metadata(p).map_or(0, |m| m.len());
        let partial = [".part", ".crdownload"].iter().any(|s| p.with_file_name(format!("{f}{s}")).exists());
        let a = len();
        a > 0 && !partial && {
            std::thread::sleep(Duration::from_secs(2));
            len() == a
        }
    })
}

/// The sheets through the browser's tabs, `BATCH` at a time; each waits up to 60 min.
fn with_browser(todo: &[(&str, &str, &str)], dest: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let dl = downloads()?;
    for (b, group) in todo.chunks(BATCH).enumerate() {
        let first = b * BATCH + 1;
        pr.log(&format!(
            "opening {} link(s) in the browser ({first}–{} of {})…",
            group.len(),
            first + group.len() - 1,
            todo.len()
        ));
        for (_, _, url) in group {
            open(url)?;
            std::thread::sleep(Duration::from_secs(1));
        }
        for (_, f, _) in group {
            let (t0, mut said) = (Instant::now(), 0);
            let p = loop {
                check(cancel)?;
                if let Some(p) = finished(f, &[&dl, dest]) {
                    break p;
                }
                let min = t0.elapsed().as_secs() / 60;
                if min >= 60 {
                    bail!("{f} did not arrive in 60 min; run setup again to retry");
                }
                if min > said {
                    said = min;
                    pr.log(&format!("  waiting for {f} in {} or {} ({min} min)…", dl.display(), dest.display()));
                }
                std::thread::sleep(Duration::from_secs(5));
            };
            if !zip_ok(&p) {
                let _ = std::fs::remove_file(&p);
                bail!("{f} is not a whole ZIP (the browser saved data.gov.il's check page?): removed, run setup again");
            }
            if p != dest.join(f) {
                // A rename fails across disks: copy, then remove.
                if std::fs::rename(&p, dest.join(f)).is_err() {
                    std::fs::copy(&p, dest.join(f))?;
                    std::fs::remove_file(&p)?;
                }
            }
            pr.log(&format!("  ok {f}"));
        }
        pr.fraction(((b + 1) * BATCH).min(todo.len()) as f32 / todo.len() as f32);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sheet_list() {
        let dir = std::env::temp_dir().join(format!("iaf-mapi-fetch-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert_eq!(todo(&dir, false).len(), 79);
        assert_eq!(todo(&dir, true).len(), BASES.len());
        std::fs::write(dir.join("shf.zip"), b"x").unwrap();
        assert_eq!(todo(&dir, true).len(), BASES.len() - 1);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
