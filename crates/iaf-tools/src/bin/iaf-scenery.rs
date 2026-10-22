//! The scenery (docs/scenery.md §1): `iaf-scenery fetch <assets>` downloads the pinned sources into
//! `<assets>/source/scenery`; `iaf-scenery build <assets> [--near X,Y,KM]` makes the cells under
//! `<assets>/converted/scenery` (only the nodes within KM of the engine point X, Y with `--near`);
//! `iaf-scenery tiles <assets>` lists the zoom-9 quadkeys the Survey 2 m layer touches (the tiles the list needs).

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::progress::Stdout;
use iaf_tools::{scenery, thirdparty};

const USAGE: &str = "usage: iaf-scenery fetch|build|tiles <assets> [--near X,Y,KM]";

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (Some(cmd), Some(assets)) = (args.first(), args.get(1)) else { bail!(USAGE) };
    let assets = PathBuf::from(assets);
    let cancel = AtomicBool::new(false);
    match (cmd.as_str(), &args[2..]) {
        ("fetch", []) => {
            let n = thirdparty::fetch_files(thirdparty::SCENERY, &assets.join("source/scenery"), &Stdout, &cancel)?;
            println!("{n} fetched, {} kept", thirdparty::SCENERY.len() - n);
        }
        ("build", rest) => {
            let near = match rest {
                [] => None,
                [flag, v] if flag == "--near" => {
                    let n: Vec<f64> = v.split(',').map(str::parse).collect::<Result<_, _>>().context(USAGE)?;
                    let [x, y, km] = n[..] else { bail!(USAGE) };
                    Some(([x, y], km))
                }
                _ => bail!(USAGE),
            };
            let s = scenery::build(&scenery::Run { assets, near }, &Stdout, &cancel)?;
            if s.up_to_date {
                println!("scenery: up to date");
            }
        }
        ("tiles", []) => {
            for q in scenery::quadkeys(Path::new(&assets))? {
                println!("{q}");
            }
        }
        _ => bail!(USAGE),
    }
    Ok(())
}
