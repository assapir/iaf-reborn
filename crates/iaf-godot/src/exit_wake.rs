//! Godot 4.7.2's Wayland exit race, worked around (docs/rendering.md §1.5 "Wayland at exit"). At the quit
//! `WaylandThread::destroy` sets `thread_done`, sends a roundtrip to wake its "Wayland Events" thread and joins it;
//! when that thread was still dispatching, the main thread reads the roundtrip's reply itself and the events thread
//! then waits in `poll(…, -1)` on a socket that gets no more data, so the join never returns. From the extension's
//! last deinit stage on (before Godot deletes its display server), a thread here interrupts that `poll` with a
//! signal (a handler that does nothing) until the events thread is gone: `poll` returns `EINTR`, the thread sees
//! `thread_done` and ends. A `poll` interrupted earlier, before `thread_done`, only reads no events and polls again.

use std::time::{Duration, Instant};

/// SIGURG: unused by Godot and its libraries; its default action (ignore) would not interrupt `poll`.
const SIG: libc::c_int = libc::SIGURG;

extern "C" fn nothing(_: libc::c_int) {}

/// The thread id of Godot's "Wayland Events" thread, if it runs.
fn events_thread() -> Option<libc::pid_t> {
    std::fs::read_dir("/proc/self/task").ok()?.flatten().find_map(|e| {
        let comm = std::fs::read_to_string(e.path().join("comm")).ok()?;
        if comm.trim_end() != "Wayland Events" {
            return None;
        }
        e.file_name().to_str()?.parse().ok()
    })
}

/// Called at the extension's Scene deinit: on Wayland, starts the thread that wakes the events thread. It waits 1 s
/// (a clean exit has joined the events thread by then), then signals it every 250 ms, for at most 30 s.
pub fn start() {
    if events_thread().is_none() {
        return;
    }
    // SAFETY: a zeroed sigaction with a handler that does nothing (no SA_RESTART: poll is never restarted anyway).
    unsafe {
        let mut sa: libc::sigaction = std::mem::zeroed();
        sa.sa_sigaction = nothing as extern "C" fn(libc::c_int) as libc::sighandler_t;
        libc::sigemptyset(&mut sa.sa_mask);
        libc::sigaction(SIG, &sa, std::ptr::null_mut());
    }
    let spawned = std::thread::Builder::new().name("iaf exit wake".into()).spawn(|| {
        let t0 = Instant::now();
        std::thread::sleep(Duration::from_secs(1));
        while let Some(tid) = events_thread() {
            if t0.elapsed() > Duration::from_secs(30) {
                return;
            }
            // SAFETY: tgkill to a thread of this process, with a signal whose handler is installed above.
            unsafe { libc::syscall(libc::SYS_tgkill, libc::getpid(), tid, SIG) };
            std::thread::sleep(Duration::from_millis(250));
        }
    });
    if let Err(e) = spawned {
        eprintln!("exit wake thread: {e}");
    }
}
