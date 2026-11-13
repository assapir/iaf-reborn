//! Shared code for the iaf-reborn command-line tools.

pub mod airbases;
pub mod aircraft;
pub mod bc1;
pub mod briefing;
pub mod convert;
pub mod devices;
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
pub mod loadout;
pub mod mapi2015_fetch;
pub mod mig29;
pub mod mis;
pub mod mission_creator;
pub mod mission_edit;
pub mod mission_events;
pub mod mission_intel;
pub mod mission_sanity;
pub mod mission_year;
pub mod modern_map;
pub mod pack;
pub mod patch;
pub mod pilot_log;
pub mod plane;
pub mod progress;
pub mod roads;
pub mod rtpatch;
pub mod runway_fix;
pub mod scenery;
pub mod sim;
pub mod sim_bases;
pub mod sim_coast;
pub mod sim_cockpit;
pub mod sim_files;
pub mod sim_fm0;
pub mod sim_scenery;
pub mod sim_terrain;
pub mod sim_voices;
pub mod smooth;
pub mod terrain;
pub mod thirdparty;
pub mod training;
pub use iaf_formats::terrain_types;
pub mod upscale;

/// The box [min x, min y, max x, max y] of `points` ([MAX, MAX, MIN, MIN] when empty).
pub fn bbox<P: std::borrow::Borrow<[f64; 2]>>(points: impl IntoIterator<Item = P>) -> [f64; 4] {
    points.into_iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
        let p = p.borrow();
        [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
    })
}

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
