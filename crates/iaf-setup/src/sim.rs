//! Modern IAF's setup steps (modern-iaf/docs/setup.md): the `iaf-sim` compilers as a plan for [`run_graph`], with stamps
//! like the original game's steps. The terrain first (heights and imagery, downloads), the airbases on it, the
//! missions on the bases; the database and the sounds beside them.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result};
use iaf_tools::progress::Progress;
use iaf_tools::{sim, sim_bases, sim_fm0, sim_scenery, sim_terrain};

use crate::{Events, Outcome, Redo, State, Step, stamp};

/// What the player chooses for the sim.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SimInputs {
    /// The Survey of Israel 2 m photo over Israel, from the sheet ZIPs already in `assets/source/imagery/mapi2015`
    /// (else Sentinel-2 everywhere).
    pub survey: bool,
    /// The optional steps, each included (the default) or left out: neither downloaded nor built.
    pub scenery: bool,
    pub textures: bool,
}

impl Default for SimInputs {
    fn default() -> Self {
        SimInputs { survey: false, scenery: true, textures: true }
    }
}

impl SimInputs {
    /// These inputs with the optional steps `ids` left out (the wizard's unticked rows; unknown ids ignored).
    pub fn without(self, ids: &[&str]) -> Self {
        SimInputs { scenery: !ids.contains(&"sim-scenery"), textures: !ids.contains(&"sim-textures"), ..self }
    }
}

/// The sim's choice file: the optional steps the player left out, remembered for the next run of the wizard.
pub fn sim_choice_file(assets: &Path) -> PathBuf {
    assets.join("converted/modern-iaf/setup.json")
}

/// The optional steps left out at the last run (none before the first). Only the plan's optional steps: an id that
/// is required (or unknown) in the file is dropped, so a required step always runs.
pub fn sim_excluded(assets: &Path) -> Vec<String> {
    let t = std::fs::read_to_string(sim_choice_file(assets)).unwrap_or_default();
    let v: serde_json::Value = serde_json::from_str(&t).unwrap_or_default();
    let optional: Vec<_> = sim_plan(&SimInputs::default()).into_iter().filter(|s| !s.required).map(|s| s.id).collect();
    v["excluded"].as_array().map_or(vec![], |a| {
        a.iter().filter_map(|x| x.as_str()).filter(|x| optional.contains(x)).map(String::from).collect()
    })
}

/// Remembers the optional steps left out (`sim_excluded` reads them back; the game greys their Preferences rows).
pub fn save_sim_excluded(assets: &Path, ids: &[String]) -> Result<()> {
    let f = sim_choice_file(assets);
    std::fs::create_dir_all(f.parent().unwrap_or(assets))?;
    std::fs::write(&f, serde_json::json!({ "excluded": ids }).to_string() + "\n")
        .with_context(|| format!("{}", f.display()))
}

/// One optional step's sizes for the wizard's row: `download` the bytes still to fetch (0 when `assets/source` holds
/// them), `disk` the bytes its outputs take (built) or will take (an estimate from a full build), `sources` the bytes
/// of its own downloads kept in `assets/source` (what "also the downloads" frees), `shared` when another setup in
/// this assets folder (the original game's, `assets/install`) reads the same files, so they stay.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Optional {
    pub id: &'static str,
    pub built: bool,
    pub download: u64,
    pub disk: u64,
    pub sources: u64,
    pub shared: bool,
}

/// A full build's outputs (2026-11-12, the 21-node theatre): the scenery 1,056 MB plus the roads 118 MB; the
/// ambientCG materials 313 MB, downloaded as about 310 MB of zips.
const SCENERY_DISK: u64 = 1_174_000_000;
const TEXTURES_DISK: u64 = 313_000_000;
const TEXTURES_DOWNLOAD: u64 = 310_000_000;

/// The scenery's own downloads (not the extracts the airbases' water is cut from, which stay), with their folders.
fn scenery_own_sources(assets: &Path) -> Vec<(iaf_tools::thirdparty::Download, PathBuf)> {
    let geo = iaf_tools::sim_bases::theatre_geo(sim_terrain::BOX);
    let water: Vec<&str> = iaf_tools::sim_coast::water_extracts(geo).iter().map(|(d, _)| d.file).collect();
    sim_scenery::downloads(geo)
        .into_iter()
        .filter(|d| !water.contains(&d.file))
        .map(|d| (d, assets.join("source/scenery")))
        .collect()
}

/// The outputs of optional step `id` under `assets`.
fn optional_outputs(assets: &Path, id: &str) -> Vec<PathBuf> {
    match id {
        "sim-scenery" => vec![assets.join(THEATRE).join("scenery"), assets.join(THEATRE).join("roads")],
        "sim-textures" => vec![assets.join("thirdparty/ambientcg")],
        _ => vec![],
    }
}

/// The sim's optional steps' sizes (`Optional`), in the plan's order.
pub fn sim_optional(assets: &Path) -> Vec<Optional> {
    use iaf_tools::thirdparty;
    let shared = assets.join("install").is_dir();
    let out = |id| optional_outputs(assets, id).iter().map(|p| crate::disk_bytes(p)).sum::<u64>();
    // The scenery: its own files and the extracts the roads read (the airbases' step fetches those first).
    let geo = iaf_tools::sim_bases::theatre_geo(sim_terrain::BOX);
    let all = sim_scenery::downloads(geo)
        .into_iter()
        .map(|d| (d, assets.join("source/scenery")))
        .chain(iaf_tools::sim_coast::road_downloads(geo).into_iter().map(|d| (d, assets.join("source/roads"))));
    let scenery_dl = all.filter(|(d, dir)| !thirdparty::file_done(dir, d)).map(|(d, _)| d.bytes).sum();
    let own = scenery_own_sources(assets);
    let scenery_built = assets.join(THEATRE).join("scenery/manifest.json").is_file();
    // The textures: the zips not yet packed nor kept, a share of the whole download.
    let (src, dir) = (assets.join("source/ambientcg"), assets.join("thirdparty/ambientcg"));
    let mats: Vec<_> = thirdparty::LISTS.iter().flat_map(|(_, l)| l.iter()).collect();
    let textures_built = mats.iter().all(|m| thirdparty::is_done(&dir, m)) && iaf_tools::foliage::is_done(&dir);
    let missing = mats.iter().filter(|m| !thirdparty::is_done(&dir, m) && !thirdparty::zip_kept(&src, m)).count();
    vec![
        Optional {
            id: "sim-scenery",
            built: scenery_built,
            download: scenery_dl,
            disk: if scenery_built { out("sim-scenery") } else { SCENERY_DISK },
            sources: own.iter().map(|(d, dir)| crate::disk_bytes(&dir.join(d.file))).sum(),
            shared,
        },
        Optional {
            id: "sim-textures",
            built: textures_built,
            download: TEXTURES_DOWNLOAD * missing as u64 / mats.len().max(1) as u64,
            disk: if textures_built { out("sim-textures") } else { TEXTURES_DISK },
            sources: crate::disk_bytes(&src),
            shared,
        },
    ]
}

/// What the terrain step would fetch over the network for these choices (`sim_terrain::would_fetch`): empty when it
/// reads only local files (the wizard's "Nothing to download" on the step's row).
pub fn sim_terrain_fetch(assets: &Path, survey: bool) -> Result<Vec<String>> {
    let inputs = SimInputs { survey, ..SimInputs::default() };
    sim_terrain::would_fetch(&SimCtx { assets: assets.to_path_buf(), repo: PathBuf::new(), inputs }.terrain())
}

/// Removes optional step `id`'s data (its outputs and stamp) and, with `downloads`, its own downloads in
/// `assets/source`; returns the bytes freed. Data another setup in this folder reads too stays (an error says so).
pub fn sim_remove(assets: &Path, id: &str, downloads: bool) -> Result<u64> {
    let shared = assets.join("install").is_dir();
    let outputs = optional_outputs(assets, id);
    anyhow::ensure!(!outputs.is_empty(), "{id}: not an optional step");
    anyhow::ensure!(!(shared && id == "sim-textures"), "the textures are shared with another setup in this folder");
    let mut gone: Vec<PathBuf> = outputs;
    let stamp = stamp::sim_stamp_path(assets, id);
    gone.extend([stamp.with_extension("secs"), stamp]);
    if downloads {
        anyhow::ensure!(!shared, "the downloads are shared with another setup in this folder");
        match id {
            "sim-scenery" => {
                for (d, dir) in scenery_own_sources(assets) {
                    gone.extend(["", ".ok", ".part"].map(|x| dir.join(format!("{}{x}", d.file))));
                }
            }
            _ => gone.push(assets.join("source/ambientcg")),
        }
    }
    let mut freed = 0;
    for p in gone {
        let n = crate::disk_bytes(&p);
        let r = if p.is_dir() { std::fs::remove_dir_all(&p) } else { std::fs::remove_file(&p) };
        match r {
            Ok(()) => freed += n,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e).with_context(|| format!("{}", p.display())),
        }
    }
    Ok(freed)
}

/// Everything a sim run needs.
pub struct SimCtx {
    pub assets: PathBuf,
    /// The repo checkout (`modern-iaf/data`).
    pub repo: PathBuf,
    pub inputs: SimInputs,
}

impl SimCtx {
    pub(crate) fn data(&self) -> PathBuf {
        self.repo.join("modern-iaf/data")
    }

    /// The terrain run for these choices (`iaf-sim terrain`'s defaults); without the Survey no sheet folder.
    pub(crate) fn terrain(&self) -> sim_terrain::Run {
        sim_terrain::Run {
            out: self.assets.join(THEATRE),
            dem_cache: self.assets.join(iaf_tools::imagery_run::DEM_CACHE),
            s2_cache: self.assets.join(iaf_tools::imagery_run::S2_CACHE),
            sheet_index: self.assets.join("converted/imagery/.work/mapi2015/sheets.tsv"),
            sheets: if self.inputs.survey { survey_dir(&self.assets) } else { PathBuf::new() },
            airbases: self.data().join("airbases"),
            osm: self.assets.clone(),
            area: sim_terrain::BOX,
            detail: sim_terrain::DETAIL,
            threads: iaf_tools::progress::threads(),
        }
    }
}

/// The sim's theatre under `assets/`.
pub const THEATRE: &str = "converted/terrain/israel";

/// Where the Survey of Israel sheet ZIPs are (`iaf-imagery fetch-mapi2015`).
pub fn survey_dir(assets: &Path) -> PathBuf {
    assets.join("source/imagery/mapi2015")
}

/// The Survey of Israel sheet ZIPs in `assets` (0: the Survey choice is not available).
pub fn survey_sheets(assets: &Path) -> usize {
    std::fs::read_dir(survey_dir(assets)).map_or(0, |d| {
        d.filter_map(|e| e.ok()).filter(|e| e.path().extension().is_some_and(|x| x.eq_ignore_ascii_case("zip"))).count()
    })
}

/// The sim's steps, in `iaf-sim all`'s order.
pub fn sim_plan(inputs: &SimInputs) -> Vec<Step> {
    let mut v = Vec::new();
    let mut add = |id, title, after: &[&'static str]| v.push(Step { id, title, required: true, after: after.to_vec() });
    add(
        "sim-terrain",
        if inputs.survey {
            "terrain: Copernicus GLO-30 heights, Sentinel-2 imagery, the Survey of Israel 2 m photo over Israel"
        } else {
            "terrain: Copernicus GLO-30 heights, Sentinel-2 imagery"
        },
        &[],
    );
    add("sim-db", "units and weapons", &[]);
    add("sim-fm", "flight data: the jets' bd.ibx and envelopes", &[]);
    add("sim-own", "sounds, voices and keys", &[]);
    add("sim-airbases", "airbases: Ramon, Hatzerim, Nevatim, Ramat David", &["sim-terrain"]);
    add("sim-missions", "training missions", &["sim-airbases", "sim-db"]);
    // Optional: the sim flies without it (no GDAL, offline, or left out).
    if inputs.scenery {
        v.push(Step {
        id: "sim-scenery",
        title: "scenery: buildings, trees, roads and city lights (OpenStreetMap, Microsoft footprints, GHS-BUILT-H, ETH canopy)",
        required: false,
        after: vec!["sim-airbases"],
        });
    }
    // Optional: the ground textures, the model detail and the scenery trees' foliage (the original's "textures" step).
    if inputs.textures {
        v.push(Step {
            id: "sim-textures",
            title: "textures: ambientCG CC0 materials for the ground, the models and the trees (download, about 310 MB)",
            required: false,
            after: vec![],
        });
    }
    v
}

/// The converted folder's old name moved to the new one before the stamps are read (`iaf_tools::sim::move_old_converted`).
fn move_old_converted(ctx: &SimCtx) {
    if let Err(e) = iaf_tools::sim::move_old_converted(&ctx.assets) {
        eprintln!("Modern IAF: {e:#}");
    }
}

/// Runs the sim's `steps` (from [`sim_plan`]) as [`crate::run`] does the original's.
pub fn sim_run(
    steps: &[Step],
    ctx: &SimCtx,
    redo: &Redo,
    events: &dyn Events,
    cancel: &AtomicBool,
) -> Vec<(&'static str, State)> {
    move_old_converted(ctx);
    sim_adopt(steps, ctx);
    let exec = |s: &Step, pr: &dyn Progress| exec(s, ctx, redo(s.id), pr, cancel);
    crate::run_graph(steps, redo, events, cancel, &|s| stamp::sim_of(s, ctx), &exec)
}

/// Stamps the steps whose outputs were built without a stamp and are current (`crate::adopt_with`), so the wizard
/// and the command line find them up to date instead of building them again: the terrain when its `meta.json` was
/// built from the same inputs and rules (`sim_terrain::stamp`), the scenery when its own stamps hold
/// (`sim_scenery::current`), any other step when its output is newer than every file that decides it (its code and
/// its authored inputs). Run before every preview and run (the wizard's and `iaf-sim`'s); `iaf-sim adopt` alone.
pub fn sim_adopt(steps: &[Step], ctx: &SimCtx) -> Vec<&'static str> {
    crate::adopt_with(steps, &|s| stamp::sim_of(s, ctx), &|s| sim_current(s.id, ctx))
}

/// Whether sim step `id`'s output on disk is what a run would make now (`sim_adopt`).
fn sim_current(id: &str, ctx: &SimCtx) -> bool {
    match id {
        "sim-terrain" => terrain_built(ctx),
        "sim-scenery" => iaf_tools::sim_scenery::current(&ctx.data(), &ctx.assets),
        _ => {
            let Some((out, inputs)) = stamp::sim_io(id, ctx) else { return false };
            let code = stamp::code_paths(id).into_iter().map(|p| ctx.repo.join(p));
            let built = newest(&out);
            built.is_some() && inputs.into_iter().chain(code).all(|p| newest(&p) <= built)
        }
    }
}

/// Whether the theatre's `meta.json` holds the `built_from` a terrain run for `ctx`'s choices compares.
fn terrain_built(ctx: &SimCtx) -> bool {
    let run = ctx.terrain();
    let meta: serde_json::Value =
        std::fs::read(run.out.join("meta.json")).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    meta["built_from"] == sim_terrain::stamp(&run)
}

/// The Survey choice of a run without the wizard (`iaf-sim`): the built theatre's (built with or without the sheets),
/// else the Survey when its sheets are there (the wizard's default).
pub fn sim_survey(assets: &Path, repo: &Path) -> bool {
    let sheets = survey_sheets(assets) > 0;
    let built = |survey| {
        let inputs = SimInputs { survey, ..SimInputs::default() };
        terrain_built(&SimCtx { assets: assets.into(), repo: repo.into(), inputs })
    };
    sheets && !(built(false) && !built(true))
}

/// The newest modification time of `p` or of any file under it; None when it does not exist.
fn newest(p: &Path) -> Option<std::time::SystemTime> {
    let m = std::fs::metadata(p).ok()?;
    if !m.is_dir() {
        return m.modified().ok();
    }
    std::fs::read_dir(p).ok()?.flatten().filter_map(|e| newest(&e.path())).max()
}

/// Which of the sim's steps a run would find up to date ([`crate::preview`]).
pub fn sim_preview(steps: &[Step], ctx: &SimCtx) -> Vec<(&'static str, bool)> {
    move_old_converted(ctx);
    sim_adopt(steps, ctx);
    crate::preview_with(steps, &|s| stamp::sim_of(s, ctx))
}

/// Each step's expected seconds for a run of `steps` (the wizard's "all steps" time left): 0 when up to date and not
/// redone, else the seconds its last finished run took (`Stamp::secs_path`), `None` when it never ran here.
pub fn sim_expected(steps: &[Step], ctx: &SimCtx, redo: &Redo) -> Vec<Option<f64>> {
    sim_preview(steps, ctx)
        .into_iter()
        .map(|(id, up)| {
            if up && !redo(id) {
                return Some(0.0);
            }
            let secs = stamp::sim_stamp_path(&ctx.assets, id).with_extension("secs");
            std::fs::read_to_string(secs).ok()?.trim().parse().ok()
        })
        .collect()
}

/// Runs one step; `redo`: the player asked to run it although it is up to date.
fn exec(step: &Step, ctx: &SimCtx, redo: bool, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    let (data, assets) = (ctx.data(), ctx.assets.as_path());
    match step.id {
        "sim-terrain" => {
            let run = ctx.terrain();
            if redo {
                forget_terrain(&run.out)?;
            }
            sim_terrain::terrain(&run, pr, cancel)?
        }
        "sim-db" => sim::db(&data, assets, pr, cancel)?,
        "sim-own" => sim::own(&data, &ctx.repo, assets, pr, cancel)?,
        "sim-airbases" => sim_bases::airbases(&data, assets, pr, cancel)?,
        "sim-missions" => sim::missions(&data, assets, pr, cancel)?,
        "sim-fm" => sim_fm0::fm(assets, pr)?,
        "sim-scenery" => return scenery(&data, assets, pr, cancel),
        "sim-textures" => return crate::steps::textures_into(assets, pr, cancel),
        id => anyhow::bail!("unknown step {id}"),
    }
    Ok(Outcome::Done)
}

/// The scenery and road layer (`iaf-sim scenery`, modern-iaf/docs/scenery.md): skipped without GDAL, or offline with a
/// file to download.
fn scenery(data: &Path, assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    if !crate::tools().gdal {
        return Ok(Outcome::Skipped("GDAL is needed (gdalwarp, ogr2ogr)".into()));
    }
    match sim_scenery::scenery(data, assets, pr, cancel) {
        Ok(s) => Ok(scenery_outcome(&s)),
        Err(_) if !crate::steps::reachable(crate::steps::SCENERY_PROBE) => Ok(Outcome::Skipped(
            "the scenery's sources cannot be reached (offline?): Scenery stays off; run setup again online".into(),
        )),
        Err(e) => Err(e),
    }
}

/// A finished scenery run as the step's outcome. Built without some optional sources: skipped with "built,
/// incomplete" (the wizard translates it by that start, wizard.gd reason), so no stamp is written and the next run
/// fetches the missing files, only them, and builds again.
fn scenery_outcome(s: &sim_scenery::Summary) -> Outcome {
    if !s.missing.is_empty() {
        let n = s.missing.len();
        return Outcome::Skipped(format!(
            "built, incomplete: {n} sources missing ({}); Retry fetches them",
            s.missing.join(", ")
        ));
    }
    if s.up_to_date { Outcome::UpToDate } else { Outcome::Done }
}

/// Makes `iaf-sim terrain` build the theatre in `out` again (a redo): its `meta.json` (whose `built_from` would say
/// "up to date") and its finished-unit marks (`.work/`) go; the tiles stay until they are written over.
fn forget_terrain(out: &Path) -> Result<()> {
    for p in [out.join("meta.json"), out.join(".work")] {
        let r = if p.is_dir() { std::fs::remove_dir_all(&p) } else { std::fs::remove_file(&p) };
        match r {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
                return Err(e).with_context(|| format!("{}", p.display()));
            }
            _ => {}
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[test]
    fn the_plan_waits_terrain_then_bases_then_missions() {
        let p = sim_plan(&SimInputs::default());
        let after = |id: &str| p.iter().find(|s| s.id == id).unwrap().after.clone();
        assert_eq!(after("sim-airbases"), ["sim-terrain"]);
        assert_eq!(after("sim-missions"), ["sim-airbases", "sim-db"]);
        assert!(after("sim-fm").is_empty());
        assert_eq!(after("sim-scenery"), ["sim-airbases"]);
        assert!(!p.iter().find(|s| s.id == "sim-scenery").unwrap().required);
        assert!(!p.iter().find(|s| s.id == "sim-textures").unwrap().required);
        assert!(sim_plan(&SimInputs { survey: true, ..Default::default() })[0].title.contains("Survey"));
    }

    /// A scenery built with sources missing is not stamped (skipped, its reason naming them); a full one is.
    #[test]
    fn an_incomplete_scenery_is_not_stamped() {
        let mut s =
            sim_scenery::Summary { missing: vec!["eth-N30E033.tif", "ms-Cyprus-1.csv.gz"], ..Default::default() };
        assert!(matches!(scenery_outcome(&s), Outcome::Skipped(ref w)
            if w.starts_with("built, incomplete: 2 sources missing") && w.contains("eth-N30E033.tif")));
        s.missing.clear();
        assert!(matches!(scenery_outcome(&s), Outcome::Done));
        s.up_to_date = true;
        assert!(matches!(scenery_outcome(&s), Outcome::UpToDate));
    }

    /// A left-out optional step is neither in the plan nor run; the choice is remembered.
    #[test]
    fn an_optional_step_left_out_is_not_planned() {
        let ids = |i: SimInputs| sim_plan(&i).iter().map(|s| s.id).collect::<Vec<_>>();
        let all = ids(SimInputs::default());
        assert!(all.contains(&"sim-scenery") && all.contains(&"sim-textures"));
        let without = ids(SimInputs::default().without(&["sim-scenery", "sim-terrain"]));
        assert!(!without.contains(&"sim-scenery") && without.contains(&"sim-textures"));
        assert!(without.contains(&"sim-terrain"), "a required step cannot be left out");
        let dir = std::env::temp_dir().join(format!("iaf-sim-choice-{}", std::process::id()));
        assert!(sim_excluded(&dir).is_empty(), "none left out before the first run");
        save_sim_excluded(&dir, &["sim-textures".into()]).unwrap();
        assert_eq!(sim_excluded(&dir), ["sim-textures"]);
        // A required step left out by an older file is read back as included: it runs.
        save_sim_excluded(&dir, &["sim-missions".into(), "sim-terrain".into(), "sim-scenery".into()]).unwrap();
        assert_eq!(sim_excluded(&dir), ["sim-scenery"]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Removing a left-out step's data: its outputs and stamp go, its downloads only when asked, the airbases' extracts
    /// never; with another setup in the folder the shared files stay.
    #[test]
    fn removing_an_optional_step() {
        let dir = std::env::temp_dir().join(format!("iaf-sim-remove-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let put = |p: &str, n: usize| {
            std::fs::create_dir_all(dir.join(p).parent().unwrap()).unwrap();
            std::fs::write(dir.join(p), vec![0u8; n]).unwrap();
        };
        put("converted/terrain/israel/scenery/manifest.json", 10);
        put("converted/terrain/israel/roads/main.bin", 5);
        put("converted/modern-iaf/sim-scenery.stamp", 1);
        let own = &scenery_own_sources(&dir)[0].0;
        put(&format!("source/scenery/{}", own.file), 7);
        put(&format!("source/scenery/{}", iaf_tools::sim_coast::osm_extract().file), 3);
        let o = sim_optional(&dir);
        assert!(o[0].built && o[0].disk == 15 && o[0].sources == 7 && !o[0].shared, "{o:?}");
        assert_eq!(sim_remove(&dir, "sim-scenery", false).unwrap(), 16);
        assert!(
            !dir.join(THEATRE).join("scenery").exists() && !dir.join("converted/modern-iaf/sim-scenery.stamp").exists()
        );
        assert!(dir.join("source/scenery").join(own.file).exists(), "the downloads stay unless asked");
        assert!(!sim_optional(&dir)[0].built);
        std::fs::create_dir_all(dir.join("install")).unwrap();
        assert!(sim_remove(&dir, "sim-scenery", true).is_err(), "shared with another setup: kept");
        assert!(sim_remove(&dir, "sim-textures", false).is_err());
        std::fs::remove_dir(dir.join("install")).unwrap();
        assert_eq!(sim_remove(&dir, "sim-scenery", true).unwrap(), 7);
        assert!(
            dir.join("source/scenery").join(iaf_tools::sim_coast::osm_extract().file).exists(),
            "the airbases' extract stays"
        );
        assert!(sim_remove(&dir, "sim-terrain", false).is_err(), "a required step has no removal");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A sim run on a scratch root with a fake terrain: the small steps run, then are up to date; the terrain's
    /// stamp follows the Survey choice.
    #[test]
    fn stamps_make_a_second_run_up_to_date() {
        let dir = std::env::temp_dir().join(format!("iaf-sim-setup-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join(THEATRE)).unwrap();
        std::fs::write(dir.join(THEATRE).join("meta.json"), "{}").unwrap();
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let ctx = SimCtx { assets: dir.clone(), repo: repo.clone(), inputs: SimInputs::default() };
        // The textures step has no stamp (it checks its own files, as the original's does).
        let steps: Vec<_> = sim_plan(&ctx.inputs).into_iter().filter(|s| s.id != "sim-textures").collect();
        struct Quiet;
        impl Events for Quiet {
            fn state(&self, _: &Step, _: &State) {}
            fn log(&self, _: &Step, _: &str) {}
        }
        let ran = Mutex::new(Vec::new());
        let go = |ctx: &SimCtx| {
            ran.lock().unwrap().clear();
            crate::run_graph(
                &steps,
                &|_| false,
                &Quiet,
                &AtomicBool::new(false),
                &|s| stamp::sim_of(s, ctx),
                &|s, _| {
                    ran.lock().unwrap().push(s.id);
                    Ok(Outcome::Done)
                },
            )
        };
        assert!(go(&ctx).iter().all(|(_, s)| *s == State::Done));
        // The outputs the stamps ask for (the fake run wrote none).
        for f in [
            "converted/missions/sim.bdb.json",
            "converted/own/keys.json",
            "converted/own/iaf.ibx",
            "converted/own/resource/md/bd.ibx",
            "converted/terrain/israel/scenery/manifest.json",
        ] {
            std::fs::create_dir_all(dir.join(f).parent().unwrap()).unwrap();
            std::fs::write(dir.join(f), "").unwrap();
        }
        std::fs::create_dir_all(dir.join("converted/modern-iaf/missions")).unwrap();
        let st = go(&ctx);
        assert!(st.iter().all(|(_, s)| *s == State::UpToDate), "{st:?}");
        assert!(sim_expected(&steps, &ctx, &|_| false).iter().all(|e| *e == Some(0.0)), "up to date: no time");
        assert!(sim_expected(&steps, &ctx, &|_| true).iter().all(|e| e.is_some()), "each run's seconds were recorded");
        assert!(sim_preview(&steps, &ctx).iter().all(|(_, up)| *up));
        let survey = SimCtx { inputs: SimInputs { survey: true, ..Default::default() }, ..ctx };
        std::fs::create_dir_all(survey_dir(&dir)).unwrap();
        std::fs::write(survey_dir(&dir).join("a.zip"), "z").unwrap();
        assert_eq!(survey_sheets(&dir), 1);
        let up: Vec<_> = sim_preview(&steps, &survey).into_iter().filter(|p| !p.1).map(|p| p.0).collect();
        assert_eq!(
            up,
            ["sim-terrain", "sim-scenery"],
            "the Survey redoes the terrain and the scenery (its roofs' colours), not the bases nor the missions"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Outputs built without a stamp (a command line run before every run stamped, an agent's build): the current
    /// ones are adopted (the terrain by its meta.json's `built_from`, the others newer than their code and inputs),
    /// so the wizard finds them up to date; an output older than its code, a terrain from other inputs, a scenery
    /// whose own stamps do not hold are not.
    #[test]
    fn current_outputs_without_stamps_are_adopted() {
        let dir = std::env::temp_dir().join(format!("iaf-sim-adopt-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let ctx = SimCtx { assets: dir.clone(), repo, inputs: SimInputs::default() };
        let steps: Vec<_> = sim_plan(&ctx.inputs).into_iter().filter(|s| s.id != "sim-textures").collect();
        std::fs::create_dir_all(dir.join(THEATRE)).unwrap();
        let meta = serde_json::json!({ "built_from": sim_terrain::stamp(&ctx.terrain()) });
        std::fs::write(dir.join(THEATRE).join("meta.json"), meta.to_string()).unwrap();
        for f in [
            "converted/missions/sim.bdb.json",
            "converted/own/keys.json",
            "converted/own/iaf.ibx",
            "converted/own/resource/md/bd.ibx",
            "converted/terrain/israel/scenery/manifest.json",
            "converted/modern-iaf/missions/missionlist.json",
        ] {
            std::fs::create_dir_all(dir.join(f).parent().unwrap()).unwrap();
            std::fs::write(dir.join(f), "").unwrap();
        }
        // The flight data built before its code: not adopted.
        let old = std::fs::File::options().write(true).open(dir.join("converted/own/resource/md/bd.ibx")).unwrap();
        old.set_modified(std::time::UNIX_EPOCH + std::time::Duration::from_secs(86400)).unwrap();
        let adopted = sim_adopt(&steps, &ctx);
        assert_eq!(adopted, ["sim-terrain", "sim-db", "sim-own", "sim-airbases", "sim-missions"], "{adopted:?}");
        let stale: Vec<_> = sim_preview(&steps, &ctx).into_iter().filter(|p| !p.1).map(|p| p.0).collect();
        assert_eq!(stale, ["sim-fm", "sim-scenery"], "only what is not current will run");
        assert!(sim_adopt(&steps, &ctx).is_empty(), "a stamp once written is not adopted again");
        // A terrain built from other inputs (another box) is not adopted.
        std::fs::remove_file(stamp::sim_stamp_path(&dir, "sim-terrain")).unwrap();
        std::fs::write(dir.join(THEATRE).join("meta.json"), r#"{"built_from":{"box":[0,0,1,1]}}"#).unwrap();
        assert!(!sim_adopt(&steps, &ctx).contains(&"sim-terrain"));
        // A stale step's dependents are not adopted: it runs again, and may make something else.
        for id in ["sim-db", "sim-missions"] {
            std::fs::remove_file(stamp::sim_stamp_path(&dir, id)).unwrap();
        }
        let db = std::fs::File::options().write(true).open(dir.join("converted/missions/sim.bdb.json")).unwrap();
        db.set_modified(std::time::UNIX_EPOCH + std::time::Duration::from_secs(86400)).unwrap();
        assert!(sim_adopt(&steps, &ctx).is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// `iaf-sim airbases` runs the airbases' step and the terrain it waits for through the graph: the wizard then
    /// finds both up to date, as after its own run.
    #[test]
    fn a_step_run_alone_writes_the_wizards_stamp() {
        let dir = std::env::temp_dir().join(format!("iaf-sim-alone-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let ctx = SimCtx { assets: dir.clone(), repo, inputs: SimInputs::default() };
        let plan: Vec<_> = sim_plan(&ctx.inputs).into_iter().filter(|s| s.id != "sim-textures").collect();
        let alone = crate::only(&plan, &["sim-airbases"]);
        assert_eq!(alone.iter().map(|s| s.id).collect::<Vec<_>>(), ["sim-terrain", "sim-airbases"]);
        struct Quiet;
        impl Events for Quiet {
            fn state(&self, _: &Step, _: &State) {}
            fn log(&self, _: &Step, _: &str) {}
        }
        let st = crate::run_graph(
            &alone,
            &|_| false,
            &Quiet,
            &AtomicBool::new(false),
            &|s| stamp::sim_of(s, &ctx),
            &|s, _| {
                let out = stamp::sim_io(s.id, &ctx).unwrap().0;
                std::fs::create_dir_all(out.parent().unwrap()).unwrap();
                std::fs::write(&out, "{}").unwrap();
                Ok(Outcome::Done)
            },
        );
        assert!(st.iter().all(|(_, s)| *s == State::Done), "{st:?}");
        let up: Vec<_> =
            crate::preview_with(&plan, &|s| stamp::sim_of(s, &ctx)).into_iter().filter(|p| p.1).map(|p| p.0).collect();
        assert_eq!(up, ["sim-terrain", "sim-airbases"]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A redo of the terrain drops its "up to date" mark and its unit marks, not its tiles.
    #[test]
    fn a_terrain_redo_forgets_the_marks() {
        let dir = std::env::temp_dir().join(format!("iaf-sim-forget-{}", std::process::id()));
        std::fs::create_dir_all(dir.join(".work")).unwrap();
        std::fs::create_dir_all(dir.join("L3")).unwrap();
        for f in ["meta.json", ".work/s2_8m_1", "L3/c_0_0.jpg"] {
            std::fs::write(dir.join(f), "x").unwrap();
        }
        forget_terrain(&dir).unwrap();
        assert!(!dir.join("meta.json").exists() && !dir.join(".work").exists() && dir.join("L3/c_0_0.jpg").exists());
        forget_terrain(&dir).unwrap();
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The airbases' outlines decide the terrain (the Survey photo gives way inside them): a changed outline makes
    /// the terrain, and what stands on it, out of date.
    #[test]
    fn an_airbase_change_redoes_the_terrain() {
        let root = std::env::temp_dir().join(format!("iaf-sim-bases-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (repo, assets) = (root.join("repo"), root.join("assets"));
        let bases = repo.join("modern-iaf/data/airbases");
        std::fs::create_dir_all(&bases).unwrap();
        std::fs::write(bases.join("ramon.json"), "{}").unwrap();
        std::fs::create_dir_all(assets.join(THEATRE)).unwrap();
        std::fs::write(assets.join(THEATRE).join("meta.json"), "{}").unwrap();
        let ctx = SimCtx { assets: assets.clone(), repo, inputs: SimInputs::default() };
        let steps = sim_plan(&ctx.inputs);
        let terrain = steps.iter().find(|s| s.id == "sim-terrain").unwrap();
        stamp::sim_of(terrain, &ctx).unwrap().unwrap().write().unwrap();
        assert!(stamp::sim_of(terrain, &ctx).unwrap().unwrap().holds());
        std::fs::write(bases.join("ramon.json"), "{\"boundary\": []}").unwrap();
        assert!(!stamp::sim_of(terrain, &ctx).unwrap().unwrap().holds());
        let _ = std::fs::remove_dir_all(&root);
    }
}
