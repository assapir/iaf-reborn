//! The git commit the extension is built from (`IafInfo.commit()`, printed in the game log at startup).

fn main() {
    let rev = std::process::Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned())
        .unwrap_or_default();
    println!("cargo:rustc-env=IAF_GIT_COMMIT={rev}");
    // A commit or checkout appends to HEAD's reflog (a worktree has its own under .git/worktrees).
    let gitdir = std::process::Command::new("git")
        .args(["rev-parse", "--absolute-git-dir"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned());
    if let Some(d) = gitdir {
        println!("cargo:rerun-if-changed={d}/logs/HEAD");
    }
    println!("cargo:rerun-if-changed=build.rs");
}
