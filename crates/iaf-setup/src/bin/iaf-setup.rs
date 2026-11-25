//! The setup pipeline from a terminal (tools/setup-cli.sh wraps it; the wizard is the graphical way):
//!
//!   iaf-setup [--assets DIR] [--patch <v1.1 patch>] [--hebrew-iso <Hebrew CD>] [--imagery sentinel2,mapi2015,mapi2015-bases]
//!             [--guides] [--scenery] [--scenery-kinds both|buildings|trees] [--refresh-imagery] [--redo-all] ["<Jane's IAF.iso>" [Brief.zip] [Menu.zip]]
//!   iaf-setup check <file>      what a CD image, patch or pack is
//!   iaf-setup guides [--assets DIR] [--only name,name] [--force] [--game EXE] [jet …]   the pilot guides' pictures
//!                               and PDFs (a display needed; the checkout's Godot from the PATH, or a release
//!                               bundle's executable EXE, which runs its own .pck)
//!
//! `--assets` defaults to the repo's `assets/`. Without the ISO the last run's inputs (`assets/setup.json`) are used, with
//! the options given added. Steps whose stamp holds are "up to date"; `--redo-all` runs every step anyway.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_setup::{Ctx, Hebrew, Imagery, Inputs, Print, State};
use iaf_tools::progress::Progress;

const USAGE: &str = "usage: iaf-setup [--assets DIR] [--patch P] [--hebrew-iso ISO] [--imagery sentinel2,mapi2015,mapi2015-bases] [--guides] [--scenery] [--scenery-kinds both|buildings|trees] [--refresh-imagery] [--redo-all] [<Jane's IAF.iso> [Brief.zip] [Menu.zip]]\n       iaf-setup check <file>\n       iaf-setup guides [--assets DIR] [--only name,name] [--force] [--game EXE] [jet …]";

fn main() -> Result<()> {
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..").canonicalize()?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let [cmd, file] = &args[..]
        && cmd == "check"
    {
        let p = Path::new(file);
        println!("cd: {:?}", iaf_setup::check_cd(p));
        println!("patch: {:?}", iaf_setup::check_patch(p).map_err(|e| format!("{e:#}")));
        println!("pack: {:?}", iaf_setup::check_pack(p).map_err(|e| format!("{e:#}")));
        println!("tools: {:?}", iaf_setup::tools());
        return Ok(());
    }
    if args.first().is_some_and(|a| a == "guides") {
        return guides(&repo, args.into_iter().skip(1));
    }
    let (mut assets, mut patch, mut hebrew_iso, mut imagery, mut guides, mut redo_all) =
        (repo.join("assets"), None, None, Vec::new(), false, false);
    let (mut refresh, mut scenery, mut kinds) = (false, false, None);
    let mut pos = Vec::new();
    let mut it = args.into_iter();
    while let Some(a) = it.next() {
        let mut val = || it.next().context(USAGE);
        match a.as_str() {
            "--assets" => assets = PathBuf::from(val()?),
            "--patch" => patch = Some(PathBuf::from(val()?)),
            "--hebrew-iso" => hebrew_iso = Some(PathBuf::from(val()?)),
            "--imagery" => {
                for s in val()?.split(',') {
                    imagery.push(match s {
                        "sentinel2" => Imagery::Sentinel2,
                        "mapi2015" => Imagery::Mapi2015 { bases: false },
                        "mapi2015-bases" => Imagery::Mapi2015 { bases: true },
                        _ => bail!("unknown imagery source '{s}' (sentinel2, mapi2015, mapi2015-bases)"),
                    });
                }
            }
            "--guides" => guides = true,
            "--scenery" => scenery = true,
            "--scenery-kinds" => {
                let v = val()?;
                kinds = Some(iaf_tools::scenery::Kinds::parse(&v).context(USAGE)?);
            }
            "--refresh-imagery" => refresh = true,
            "--redo-all" => redo_all = true,
            "-h" | "--help" => bail!(USAGE),
            _ => pos.push(PathBuf::from(a)),
        }
    }
    let mut pos = pos.into_iter();
    let (cd, brief, menu) = (pos.next(), pos.next(), pos.next());
    let given = match (hebrew_iso, brief, menu) {
        (Some(iso), _, _) => Some(Hebrew::Cd(iso)),
        (None, None, None) => None,
        (None, brief, menu) => Some(Hebrew::Packs { brief, menu }),
    };
    let inputs = match cd {
        Some(cd) => Inputs {
            cd,
            patch,
            hebrew: given.unwrap_or(Hebrew::None),
            imagery,
            refresh,
            guides,
            scenery,
            scenery_kinds: kinds.unwrap_or_default(),
        },
        // Setup again: the last inputs, plus what is given now.
        None => {
            let mut i = iaf_setup::load_inputs(&assets)?.context(USAGE)?;
            i.patch = patch.or(i.patch);
            i.hebrew = given.unwrap_or(i.hebrew);
            for m in imagery {
                if !i.imagery.contains(&m) {
                    i.imagery.push(m);
                }
            }
            i.guides |= guides;
            i.refresh = refresh; // once, after a restore
            i.scenery |= scenery;
            i.scenery_kinds = kinds.unwrap_or(i.scenery_kinds);
            i
        }
    };
    iaf_setup::save_inputs(&assets, &inputs)?;
    let game = iaf_setup::Game::checkout(&repo);
    let guide_assets = assets.clone();
    // --redo-all renders every guide picture and makes every PDF again.
    let render = |pr: &dyn Progress, cancel: &AtomicBool| {
        let o = iaf_setup::GuideOptions { force: redo_all, ..Default::default() };
        iaf_setup::make_guides(&repo, &guide_assets, &game, &o, pr, cancel)
    };
    let ctx = Ctx {
        assets,
        repo: repo.clone(),
        inputs: inputs.clone(),
        guides: if iaf_setup::tools().display { Some(&render) } else { None },
    };
    let steps = iaf_setup::plan(&inputs);
    let t0 = std::time::Instant::now();
    let states = iaf_setup::run(&steps, &ctx, &|_| redo_all, &Print, &AtomicBool::new(false));
    println!("\nsetup ({}):", iaf_tools::progress::duration(t0.elapsed()));
    let mut failed = false;
    for (id, s) in &states {
        println!("  {id:15} {s:?}");
        failed |= matches!(s, State::Failed(_) | State::Blocked | State::Cancelled);
    }
    if failed {
        bail!("setup did not finish");
    }
    Ok(())
}

/// `iaf-setup guides`: the pilot guides' pictures (only those not up to date, unless --force) and PDFs.
fn guides(repo: &Path, args: impl Iterator<Item = String>) -> Result<()> {
    let mut assets = repo.join("assets");
    let mut o = iaf_setup::GuideOptions::default();
    let mut game = iaf_setup::Game::checkout(repo);
    let mut it = args;
    while let Some(a) = it.next() {
        match a.as_str() {
            "--assets" => assets = PathBuf::from(it.next().context(USAGE)?),
            "--only" => o.only = it.next().context(USAGE)?.split(',').map(String::from).collect(),
            "--force" => o.force = true,
            "--game" => game = iaf_setup::Game { exe: it.next().context(USAGE)?.into(), args: vec![] },
            "-h" | "--help" => bail!(USAGE),
            _ => o.jets.push(a),
        }
    }
    // Absolute: the game is started in another folder (the hidden macOS app).
    let assets = std::path::absolute(&assets)?;
    iaf_setup::make_guides(repo, &assets, &game, &o, &iaf_tools::progress::Stdout, &AtomicBool::new(false))
}
