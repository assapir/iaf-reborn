//! The third-party CC0 textures (ambientCG, docs/credits.md): `iaf-textures <assets/thirdparty/ambientcg>` packs every
//! list of `iaf_tools::thirdparty` (materials done before are kept), from the zips kept in `assets/source/ambientcg`
//! (downloaded there when missing).

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Result, bail};
use iaf_tools::progress::Stdout;
use iaf_tools::thirdparty::{AMBIENTCG, AMBIENTCG_SOURCE, LISTS, fetch};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let [_, dir] = &args[..] else { bail!("usage: iaf-textures <assets/thirdparty/ambientcg>") };
    // <assets>/thirdparty/ambientcg → <assets>/source/ambientcg.
    let src = Path::new(dir).join("../..").join(AMBIENTCG_SOURCE);
    for (name, list) in LISTS {
        let n = fetch(name, list, AMBIENTCG, &src, Path::new(dir), &Stdout, &AtomicBool::new(false))?;
        println!("{name}: {n} packed, {} kept", list.len() - n);
    }
    Ok(())
}
