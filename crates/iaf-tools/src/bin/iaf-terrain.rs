//! Terrain tools for `map.ptt`.
//!
//! `iaf-terrain info <map.ptt>`                   — list levels
//! `iaf-terrain mosaic <map.ptt> <level-index> <out.png>` — stitch one level's imagery into a single image

use anyhow::{Context, Result, bail};
use iaf_formats::ptt::{Ptt, TILE_PIXELS};
use image::{GenericImage, RgbImage};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [_, "info", path] => {
            let ptt = Ptt::open(path)?;
            for (i, l) in ptt.levels.iter().enumerate() {
                println!(
                    "{i:3}  level {:2}  {}  rect {:?}  {}x{} tiles of {} units",
                    l.level,
                    if l.flag == 1 { "theatre" } else { "inset  " },
                    l.rect,
                    l.columns(),
                    l.rows(),
                    l.tile_span()
                );
            }
            Ok(())
        }
        [_, "mosaic", path, index, out] => {
            let mut ptt = Ptt::open(path)?;
            let level = ptt.levels.get(index.parse::<usize>()?).context("no such level")?.clone();
            let tiles = ptt.tiles(&level)?;
            let (cols, rows) = (level.columns(), level.rows());
            let mut img = RgbImage::new(cols * TILE_PIXELS, rows * TILE_PIXELS);
            let mut failed = 0;
            // Row-major from the level origin; row 0 is the top (north) of the image.
            for (k, t) in tiles.iter().enumerate() {
                let (c, r) = (k as u32 % cols, k as u32 / cols);
                match ptt.tile_jpeg(t).map_err(anyhow::Error::from).and_then(|j| Ok(image::load_from_memory(&j)?)) {
                    Ok(tile) => img.copy_from(&tile.to_rgb8(), c * TILE_PIXELS, r * TILE_PIXELS)?,
                    Err(_) => failed += 1,
                }
            }
            img.save(out)?;
            println!("{cols}x{rows} tiles -> {out} ({failed} failed)");
            Ok(())
        }
        _ => bail!("usage: iaf-terrain info <map.ptt> | mosaic <map.ptt> <level-index> <out.png>"),
    }
}
