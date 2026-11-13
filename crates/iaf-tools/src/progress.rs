//! Progress reporting and cancelling for the setup-path entry points (`convert`, `extract`, `patch`, `pack`,
//! `terrain`, `imagery_run`): each takes a `&dyn Progress` and a cancel flag.

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{Context, Result, bail};

/// Where an entry point reports: log lines and, where it knows them, the fraction done.
pub trait Progress: Sync {
    fn log(&self, line: &str);
    /// A warning or a skipped item (the CLIs print these on stderr).
    fn warn(&self, line: &str) {
        self.log(line);
    }
    /// 0..1 of the current entry point's work.
    fn fraction(&self, _f: f32) {}
}

/// The CLIs' progress: lines on stdout, warnings on stderr, no fractions.
pub struct Stdout;

impl Progress for Stdout {
    fn log(&self, line: &str) {
        println!("{line}");
    }
    fn warn(&self, line: &str) {
        eprintln!("{line}");
    }
}

/// A part of a longer piece of work: its fractions 0..1 become `from..to` of the whole; the lines pass through.
pub struct Part<'a> {
    pub pr: &'a dyn Progress,
    pub from: f32,
    pub to: f32,
}

impl Progress for Part<'_> {
    fn log(&self, line: &str) {
        self.pr.log(line);
    }
    fn warn(&self, line: &str) {
        self.pr.warn(line);
    }
    fn fraction(&self, f: f32) {
        self.pr.fraction(self.from + (self.to - self.from) * f);
    }
}

/// `p.log(&format!(…))`.
#[macro_export]
macro_rules! log {
    ($p:expr, $($t:tt)*) => { $p.log(&format!($($t)*)) };
}

/// An error once `cancel` is set (checked between items and in the worker loops).
pub fn check(cancel: &AtomicBool) -> Result<()> {
    if cancel.load(Ordering::Relaxed) {
        bail!("cancelled");
    }
    Ok(())
}

/// The file name of `p`, lower-cased.
pub fn name_lc(p: &Path) -> Result<String> {
    Ok(p.file_name().with_context(|| format!("{}: no file name", p.display()))?.to_string_lossy().to_lowercase())
}

/// The file stem of `p`, lower-cased.
pub fn stem_lc(p: &Path) -> Result<String> {
    Ok(p.file_stem().with_context(|| format!("{}: no file name", p.display()))?.to_string_lossy().to_lowercase())
}

/// The folder holding `p`.
pub fn parent(p: &Path) -> Result<&Path> {
    p.parent().with_context(|| format!("{}: no parent folder", p.display()))
}

/// `p` as UTF-8 (for external programs' arguments).
pub fn utf8(p: &Path) -> Result<&str> {
    p.to_str().with_context(|| format!("{}: not a UTF-8 path", p.display()))
}

/// The worker count for the parallel loops: the machine's parallelism.
pub fn threads() -> usize {
    std::thread::available_parallelism().map_or(4, |n| n.get())
}

/// `f` over `items` on rayon's workers (`threads()` of them); the results in `items`' order. Stops at the first error
/// (or once `cancel` is set) and returns it.
pub fn par_map<T: Sync, R: Send>(
    items: &[T],
    cancel: &AtomicBool,
    f: impl Fn(&T) -> Result<R> + Sync,
) -> Result<Vec<R>> {
    use rayon::prelude::*;
    items.par_iter().map(|x| check(cancel).and_then(|()| f(x))).collect()
}

/// A rayon pool of `threads` workers, for a loop with its own worker count (`--threads`, a download limit).
pub fn pool(threads: usize) -> Result<rayon::ThreadPool> {
    Ok(rayon::ThreadPoolBuilder::new().num_threads(threads.max(1)).build()?)
}

/// `par_map` for an `f` that cannot fail and runs to the end (no cancel).
pub fn par_map_all<T: Sync, R: Send>(items: &[T], f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    use rayon::prelude::*;
    items.par_iter().map(&f).collect()
}

/// A duration for the log: "42 s", "9 min 15 s", "1 h 05 min".
pub fn duration(d: std::time::Duration) -> String {
    let s = d.as_secs_f64().round() as u64;
    match s {
        0..60 => format!("{s} s"),
        60..3600 => format!("{} min {} s", s / 60, s % 60),
        _ => format!("{} h {:02} min", s / 3600, s % 3600 / 60),
    }
}

/// A download's progress line: "downloaded 170 of 520 MB, 4.2 MB/s, about 1 min 23 s left". `got` bytes came in
/// `secs` seconds of this run; `done` of `total` bytes are on disk (files kept from before count as done).
pub fn download_line(done: u64, total: u64, got: u64, secs: f64) -> String {
    let mb = |b: u64| b as f64 / 1e6;
    let rate = got as f64 / secs.max(0.001);
    let mut line = format!("downloaded {:.0} of {:.0} MB", mb(done), mb(total));
    if got > 0 {
        line += &format!(", {:.1} MB/s", rate / 1e6);
        let left = total.saturating_sub(done) as f64 / rate.max(1.0);
        line += &format!(", about {} left", duration(std::time::Duration::from_secs_f64(left)));
    }
    line
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn download_lines() {
        assert_eq!(download_line(170_000_000, 520_000_000, 0, 1.0), "downloaded 170 of 520 MB");
        assert_eq!(
            download_line(170_000_000, 520_000_000, 100_000_000, 20.0),
            "downloaded 170 of 520 MB, 5.0 MB/s, about 1 min 10 s left"
        );
    }

    #[test]
    fn durations() {
        let d = |s| duration(std::time::Duration::from_secs(s));
        assert_eq!([d(42), d(555), d(3600 + 5 * 60 + 9)], ["42 s", "9 min 15 s", "1 h 05 min"]);
    }

    #[test]
    fn par_map_keeps_order_and_stops_on_error() {
        let no = AtomicBool::new(false);
        let v: Vec<u32> = (0..100).collect();
        assert_eq!(par_map(&v, &no, |&x| Ok(x * 2)).unwrap(), v.iter().map(|x| x * 2).collect::<Vec<_>>());
        assert!(par_map(&v, &no, |&x| if x == 50 { bail!("x") } else { Ok(x) }).is_err());
        assert!(par_map(&v, &AtomicBool::new(true), |&x| Ok(x)).is_err(), "cancelled");
        assert_eq!(par_map_all(&v, |&x| x + 1), v.iter().map(|x| x + 1).collect::<Vec<_>>());
    }
}
