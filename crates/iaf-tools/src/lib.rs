//! Shared code for the iaf-reborn command-line tools.

pub mod aircraft;
pub mod gltf;
pub mod mis;
pub mod rtpatch;
pub mod runway_fix;
pub mod smooth;
pub mod upscale;

/// Every file under `dir`, recursively (unordered).
pub fn walk_files(dir: &std::path::Path) -> std::io::Result<Vec<std::path::PathBuf>> {
    let mut out = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir)? {
            let p = entry?.path();
            if p.is_dir() {
                stack.push(p);
            } else {
                out.push(p);
            }
        }
    }
    Ok(out)
}
