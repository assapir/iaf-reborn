//! Modern IAF's setup steps (iaf-2026/docs/setup.md): the `iaf-sim` compilers as a plan for [`run_graph`], with stamps
//! like the original game's steps. The terrain first (heights and imagery, downloads), the airbases on it, the
//! missions on the bases; the database and the sounds beside them.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result};
use iaf_tools::progress::Progress;
use iaf_tools::{sim, sim_bases, sim_fm0, sim_scenery, sim_terrain};

use crate::{Events, Outcome, Redo, State, Step, stamp};

/// What the player chooses for the sim.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SimInputs {
    /// The Survey of Israel 2 m photo over Israel, from the sheet ZIPs already in `assets/source/imagery/mapi2015`
    /// (else Sentinel-2 everywhere).
    pub survey: bool,
}

/// Everything a sim run needs.
pub struct SimCtx {
    pub assets: PathBuf,
    /// The repo checkout (`iaf-2026/data`).
    pub repo: PathBuf,
    pub inputs: SimInputs,
}

impl SimCtx {
    pub(crate) fn data(&self) -> PathBuf {
        self.repo.join("iaf-2026/data")
    }

    /// The terrain run for these choices (`iaf-sim terrain`'s defaults); without the Survey no sheet folder.
    pub(crate) fn terrain(&self) -> sim_terrain::Run {
        sim_terrain::Run {
            out: self.assets.join(THEATRE),
            dem_cache: self.assets.join("source/dem"),
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
    // Optional: the sim flies without it (no GDAL, offline).
    v.push(Step {
        id: "sim-scenery",
        title: "scenery: buildings, trees, roads and city lights (OpenStreetMap, Microsoft footprints, GHS-BUILT-H, ETH canopy)",
        required: false,
        after: vec!["sim-airbases"],
    });
    v
}

/// Runs the sim's `steps` (from [`sim_plan`]) as [`crate::run`] does the original's.
pub fn sim_run(
    steps: &[Step],
    ctx: &SimCtx,
    redo: &Redo,
    events: &dyn Events,
    cancel: &AtomicBool,
) -> Vec<(&'static str, State)> {
    let exec = |s: &Step, pr: &dyn Progress| exec(s, ctx, redo(s.id), pr, cancel);
    crate::run_graph(steps, redo, events, cancel, &|s| stamp::sim_of(s, ctx), &exec)
}

/// Which of the sim's steps a run would find up to date ([`crate::preview`]).
pub fn sim_preview(steps: &[Step], ctx: &SimCtx) -> Vec<(&'static str, bool)> {
    crate::preview_with(steps, &|s| stamp::sim_of(s, ctx))
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
        id => anyhow::bail!("unknown step {id}"),
    }
    Ok(Outcome::Done)
}

/// The scenery and road layer (`iaf-sim scenery`, iaf-2026/docs/scenery.md): skipped without GDAL, or offline with a
/// file to download.
fn scenery(data: &Path, assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Outcome> {
    if !crate::tools().gdal {
        return Ok(Outcome::Skipped("GDAL is needed (gdalwarp, ogr2ogr)".into()));
    }
    match sim_scenery::scenery(data, assets, pr, cancel) {
        Ok(s) => Ok(if s.up_to_date { Outcome::UpToDate } else { Outcome::Done }),
        Err(_) if !crate::steps::reachable(crate::steps::SCENERY_PROBE) => Ok(Outcome::Skipped(
            "the scenery's sources cannot be reached (offline?): Scenery stays off; run setup again online".into(),
        )),
        Err(e) => Err(e),
    }
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
        assert!(sim_plan(&SimInputs { survey: true })[0].title.contains("Survey"));
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
        let steps = sim_plan(&ctx.inputs);
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
        std::fs::create_dir_all(dir.join("converted/iaf-2026/missions")).unwrap();
        let st = go(&ctx);
        assert!(st.iter().all(|(_, s)| *s == State::UpToDate), "{st:?}");
        assert!(sim_preview(&steps, &ctx).iter().all(|(_, up)| *up));
        let survey = SimCtx { inputs: SimInputs { survey: true }, ..ctx };
        std::fs::create_dir_all(survey_dir(&dir)).unwrap();
        std::fs::write(survey_dir(&dir).join("a.zip"), "z").unwrap();
        assert_eq!(survey_sheets(&dir), 1);
        let up: Vec<_> = sim_preview(&steps, &survey).into_iter().filter(|p| !p.1).map(|p| p.0).collect();
        assert_eq!(
            up,
            ["sim-terrain", "sim-airbases", "sim-missions", "sim-scenery"],
            "the Survey redoes the terrain and what is on it"
        );
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
        let bases = repo.join("iaf-2026/data/airbases");
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
