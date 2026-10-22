//! The third-party CC0 textures (ambientCG, docs/credits.md): `iaf-textures <assets/thirdparty/ambientcg>` downloads
//! and packs every list of `iaf_tools::thirdparty` (materials done before are kept).

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Result, bail};
use iaf_tools::progress::Stdout;
use iaf_tools::thirdparty::{AMBIENTCG, LISTS, fetch};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let [_, dir] = &args[..] else { bail!("usage: iaf-textures <assets/thirdparty/ambientcg>") };
    for (name, list) in LISTS {
        let n = fetch(name, list, AMBIENTCG, Path::new(dir), &Stdout, &AtomicBool::new(false))?;
        println!("{name}: {n} fetched, {} kept", list.len() - n);
    }
    Ok(())
}
