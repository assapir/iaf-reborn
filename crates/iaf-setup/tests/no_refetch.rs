//! A code change never downloads again: with every source already in `assets/source` under its own name, the setup's
//! fetch steps (both games' fetchers) open no connection. `curl` and `gdal_translate` (which cuts the edge tiles'
//! 20 m extracts over the network) on the PATH are fakes that record any call and fail, so nothing real is fetched.
//! One test: it sets the process's PATH.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::sync::atomic::AtomicBool;

use iaf_setup::{Events, Imagery, Inputs, State, Step};
use iaf_tools::progress::Stdout;
use iaf_tools::thirdparty::{self, Download};
use iaf_tools::{f15, imagery_run, sim_bases, sim_coast, sim_scenery, sim_terrain};

struct Quiet;
impl Events for Quiet {
    fn state(&self, _: &Step, _: &State) {}
    fn log(&self, _: &Step, _: &str) {}
}

/// A stand-in for a download: one byte, and its `.ok` mark with the pinned hash (as `fetch_files` leaves it).
fn kept(dir: &Path, file: &str, sha256: &str) {
    std::fs::create_dir_all(dir).unwrap();
    std::fs::write(dir.join(file), "x").unwrap();
    std::fs::write(dir.join(format!("{file}.ok")), format!("{sha256}\n2026-01-01\n")).unwrap();
}

fn keep_all(dir: &Path, list: &[Download]) {
    list.iter().for_each(|d| kept(dir, d.file, d.sha256));
}

#[test]
fn kept_downloads_are_never_fetched_again() {
    let root = std::env::temp_dir().join(format!("iaf-no-refetch-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let (bin, a, log) = (root.join("bin"), root.join("assets"), root.join("curl.log"));
    std::fs::create_dir_all(&bin).unwrap();
    std::fs::write(bin.join("curl"), format!("#!/bin/sh\necho \"$0 $*\" >> '{}'\nexit 7\n", log.display())).unwrap();
    std::fs::copy(bin.join("curl"), bin.join("gdal_translate")).unwrap();
    for f in ["curl", "gdal_translate"] {
        std::fs::set_permissions(bin.join(f), std::fs::Permissions::from_mode(0o755)).unwrap();
    }
    let path = format!("{}:{}", bin.display(), std::env::var("PATH").unwrap_or_default());
    // SAFETY: this test binary holds this one test, so no other thread reads the environment.
    unsafe { std::env::set_var("PATH", path) };

    // Every source of both games, under its own name.
    let src = a.join("source");
    keep_all(&src.join("scenery"), thirdparty::SCENERY);
    keep_all(&src.join("scenery"), thirdparty::SCENERY_THEATRE);
    keep_all(&src.join("roads"), thirdparty::ROADS);
    keep_all(&src.join("f15"), f15::SOURCE);
    for m in thirdparty::LISTS.iter().flat_map(|(_, l)| l.iter()) {
        kept(&a.join(thirdparty::AMBIENTCG_SOURCE), &format!("{}_2K-JPG.zip", m.id), m.sha256);
    }
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let sheets = std::fs::read_to_string(repo.join("tools/imagery/mapi2015_sheets.tsv")).unwrap();
    for url in sheets.lines().filter_map(|l| l.split_once('\t')).map(|(_, u)| u) {
        kept(&src.join("imagery/mapi2015"), url.rsplit('/').next().unwrap(), "-");
    }
    let geo = sim_bases::theatre_geo(sim_terrain::BOX);
    let (dem, s2) = (a.join(imagery_run::DEM_CACHE), a.join(imagery_run::S2_CACHE));
    std::fs::create_dir_all(&dem).unwrap();
    std::fs::create_dir_all(&s2).unwrap();
    let mut names = Vec::new();
    for lat in geo[1].floor() as i32..=geo[3].floor() as i32 {
        let mut listing = String::new();
        for lon in geo[0].floor() as i32..=geo[2].floor() as i32 {
            let name = format!("N{lat:02}E{lon:03}");
            std::fs::write(dem.join(format!("Copernicus_DSM_COG_10_N{lat:02}_00_E{lon:03}_00_DEM.tif")), "x").unwrap();
            std::fs::write(s2.join(format!("ESA_WorldCover_10m_2021_v200_{name}_S2RGBNIR.tif")), "x").unwrap();
            listing += &format!("{name}\t1\n");
            names.push(name);
        }
        std::fs::write(s2.join(format!("listing_N{lat:02}.tsv")), listing).unwrap();
    }

    // The original game's fetch steps, each run again (as after a code change).
    let inputs = Inputs { scenery: true, imagery: vec![Imagery::Mapi2015 { bases: false }], ..Default::default() };
    let steps: Vec<Step> = iaf_setup::plan(&inputs)
        .into_iter()
        .filter(|s| ["scenery-fetch", "textures", "models", "mapi2015-fetch"].contains(&s.id))
        .map(|s| Step { after: vec![], ..s })
        .collect();
    assert_eq!(steps.len(), 4);
    let ctx = iaf_setup::Ctx { assets: a.clone(), repo, inputs, xdg_data_home: None, guides: None };
    let states = iaf_setup::run(&steps, &ctx, &|_| true, &Quiet, &AtomicBool::new(false));
    // textures and models then fail on the stand-in files: only the network matters here.
    println!("{states:?}");
    let state = |id: &str| states.iter().find(|(s, _)| *s == id).unwrap().1.clone();
    assert_eq!(state("scenery-fetch"), State::UpToDate);
    assert_eq!(state("mapi2015-fetch"), State::Done);

    // Modern IAF's fetchers (its terrain, airbases and scenery steps call these).
    let no = AtomicBool::new(false);
    assert!(!sim_coast::fetch_extracts(&a, geo, &Stdout, &no).unwrap().is_empty());
    assert_eq!(thirdparty::fetch_files(&sim_scenery::downloads(geo), &src.join("scenery"), &Stdout, &no).unwrap(), 0);
    let (tiles, line) = imagery_run::fetch_dem(&dem, geo, &Stdout, &no).unwrap();
    assert!(!tiles.is_empty() && line.contains("fetched 0 MB"), "{line}");
    let listed =
        imagery_run::list_tiles(&s2, imagery_run::BUCKET, geo[1].floor() as i32, geo[3].floor() as i32).unwrap();
    // A third of them edge tiles (read at 20 m): a whole one on disk is used as it is, the others' 20 m extracts cut
    // by an earlier run (`.ok`: the window they hold) are read with no network (gdal_translate is a fake too).
    let third = names.len() / 3;
    let edges = imagery_run::Edges { names: &names[..2 * third], window: geo };
    for n in &names[third..2 * third] {
        let tile = s2.join(format!("ESA_WorldCover_10m_2021_v200_{n}_S2RGBNIR.tif"));
        std::fs::remove_file(tile).unwrap();
        let e = imagery_run::edge_file(&s2, n);
        std::fs::write(&e, "x").unwrap();
        std::fs::write(e.with_extension("ok"), format!("{} {} {} {}\n", geo[0], geo[1], geo[2], geo[3])).unwrap();
    }
    let (paths, line) =
        imagery_run::tile_sources(&s2, imagery_run::BUCKET, &listed, &names, &edges, &Stdout, &no).unwrap();
    assert!(paths.values().all(|p| !p.starts_with("/vsicurl/")), "{paths:?}");
    assert_eq!(paths[&names[third]], imagery_run::edge_file(&s2, &names[third]).to_str().unwrap());
    assert!(line.contains(&format!("{} kept, 0 cut", third)) && line.contains("0 fetched"), "{line}");

    assert!(!log.exists(), "the network was used:\n{}", std::fs::read_to_string(&log).unwrap_or_default());
    std::fs::remove_dir_all(&root).unwrap();
}
