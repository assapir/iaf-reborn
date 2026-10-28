//! The scenery (docs/scenery.md §1): `iaf-scenery fetch <assets> [--kinds K]` downloads the pinned sources the kinds
//! need into `<assets>/source/scenery`; `iaf-scenery build <assets> [--kinds K] [--near X,Y,KM]` makes the cells under
//! `<assets>/converted/scenery` (only the nodes within KM of the engine point X, Y with `--near`); K is both (the
//! default), buildings or trees;
//! `iaf-scenery lights <assets> [--near X,Y,KM]` makes the city lights' extra buildings where the scenery stops
//! (`<assets>/converted/scenery/lights`, docs/rendering.md §5.1; `build` makes them too);
//! `iaf-scenery tiles <assets>` lists the zoom-9 quadkeys the Survey 2 m layer touches (the tiles the list needs).

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::progress::Stdout;
use iaf_tools::{scenery, thirdparty};

const USAGE: &str =
    "usage: iaf-scenery fetch|build|lights|tiles <assets> [--kinds both|buildings|trees] [--near X,Y,KM]";

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (Some(cmd), Some(assets)) = (args.first(), args.get(1)) else { bail!(USAGE) };
    let assets = PathBuf::from(assets);
    let cancel = AtomicBool::new(false);
    let (mut kinds, mut near) = (scenery::Kinds::BOTH, None);
    let mut rest = args[2..].iter();
    while let Some(flag) = rest.next() {
        let v = rest.next().context(USAGE)?;
        match flag.as_str() {
            "--kinds" => kinds = scenery::Kinds::parse(v).context(USAGE)?,
            "--near" if cmd == "build" || cmd == "lights" => {
                let n: Vec<f64> = v.split(',').map(str::parse).collect::<Result<_, _>>().context(USAGE)?;
                let [x, y, km] = n[..] else { bail!(USAGE) };
                near = Some(([x, y], km));
            }
            _ => bail!(USAGE),
        }
    }
    match cmd.as_str() {
        "fetch" => {
            let list = kinds.downloads();
            let n = thirdparty::fetch_files(&list, &assets.join("source/scenery"), &Stdout, &cancel)?;
            println!("{n} fetched, {} kept", list.len() - n);
        }
        "build" | "lights" => {
            let r = scenery::Run { assets, near, kinds };
            if cmd == "build" && scenery::build(&r, &Stdout, &cancel)?.up_to_date {
                println!("scenery: up to date");
            }
            if scenery::build_lights(&r, &Stdout, &cancel)?.up_to_date {
                println!("city lights: up to date");
            }
        }
        "tiles" if args.len() == 2 => {
            for q in scenery::quadkeys(Path::new(&assets))? {
                println!("{q}");
            }
        }
        _ => bail!(USAGE),
    }
    Ok(())
}
