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

/// `f` over `items` on `threads()` workers pulling from a shared index; the results in `items`' order. Stops at
/// the first error (or once `cancel` is set) and returns it.
pub fn par_map<T: Sync, R: Send>(items: &[T], cancel: &AtomicBool, f: impl Fn(&T) -> Result<R> + Sync) -> Result<Vec<R>> {
    use std::sync::Mutex;
    use std::sync::atomic::AtomicUsize;
    let next = AtomicUsize::new(0);
    let failed = AtomicBool::new(false);
    let results: Mutex<Vec<Option<R>>> = Mutex::new((0..items.len()).map(|_| None).collect());
    std::thread::scope(|s| -> Result<()> {
        let workers: Vec<_> = (0..threads().min(items.len()).max(1))
            .map(|_| {
                s.spawn(|| -> Result<()> {
                    loop {
                        check(cancel)?;
                        if failed.load(Ordering::Relaxed) {
                            return Ok(());
                        }
                        let k = next.fetch_add(1, Ordering::Relaxed);
                        let Some(item) = items.get(k) else { return Ok(()) };
                        let r = f(item).inspect_err(|_| failed.store(true, Ordering::Relaxed))?;
                        results.lock().map_err(|_| anyhow::anyhow!("worker panicked"))?[k] = Some(r);
                    }
                })
            })
            .collect();
        let mut first = Ok(());
        for w in workers {
            let r = w.join().map_err(|_| anyhow::anyhow!("worker panicked")).and_then(|r| r);
            if first.is_ok() {
                first = r;
            }
        }
        first
    })?;
    results.into_inner().map_err(|_| anyhow::anyhow!("worker panicked"))?.into_iter().map(|r| r.context("item not done")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn par_map_keeps_order_and_stops_on_error() {
        let no = AtomicBool::new(false);
        let v: Vec<u32> = (0..100).collect();
        assert_eq!(par_map(&v, &no, |&x| Ok(x * 2)).unwrap(), v.iter().map(|x| x * 2).collect::<Vec<_>>());
        assert!(par_map(&v, &no, |&x| if x == 50 { bail!("x") } else { Ok(x) }).is_err());
        assert!(par_map(&v, &AtomicBool::new(true), |&x| Ok(x)).is_err(), "cancelled");
    }
}
