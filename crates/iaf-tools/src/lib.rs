//! Shared code for the iaf-reborn command-line tools.

pub mod airbases;
pub mod aircraft;
pub mod bc1;
pub mod convert;
pub mod exe;
pub mod extract;
pub mod f15;
pub mod foliage;
pub mod georef;
pub mod georef_measure;
pub mod gltf;
pub mod imagery;
pub mod imagery_run;
pub mod itm;
pub mod mis;
pub mod mission_creator;
pub mod mission_edit;
pub mod mission_events;
pub mod mission_intel;
pub mod mission_sanity;
pub mod mission_year;
pub mod pack;
pub mod patch;
pub mod plane;
pub mod progress;
pub mod rtpatch;
pub mod runway_fix;
pub mod scenery;
pub mod smooth;
pub mod terrain;
pub mod thirdparty;
pub use iaf_formats::terrain_types;
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
