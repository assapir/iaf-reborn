//! Terrain tools for `map.ptt`.
//!
//! `iaf-terrain info <map.ptt>`                   — list levels
//! `iaf-terrain mosaic <map.ptt> <level-index> <out.png>` — stitch one level's imagery into a single image
//! `iaf-terrain heights <map.ptt> <level-index> <out.png>` — stitch one level's elevation as greyscale
//! `iaf-terrain export <map.ptt> <level-index> <out-dir>` — engine chunks: colour JPEG + height PNG + meta.json

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
        [_, "heights", path, index, out] => {
            let mut ptt = Ptt::open(path)?;
            let level = ptt.levels.get(index.parse::<usize>()?).context("no such level")?.clone();
            let tiles = ptt.tiles(&level)?;
            let (cols, rows) = (level.columns(), level.rows());
            let n = TILE_PIXELS as usize;
            let (w, h) = (cols as usize * n, rows as usize * n);
            let mut grid = vec![u16::MAX; w * h];
            let (mut failed, mut empty) = (0, 0);
            for (k, t) in tiles.iter().enumerate() {
                let (c, r) = (k % cols as usize, k / cols as usize);
                match ptt.tile_heights(t) {
                    Ok(Some(tile)) => {
                        for y in 0..n {
                            let dst = (r * n + y) * w + c * n;
                            grid[dst..dst + n].copy_from_slice(&tile[y * n..(y + 1) * n]);
                        }
                    }
                    Ok(None) => empty += 1,
                    Err(e) => {
                        if failed == 0 {
                            eprintln!("tile {k}: {e}");
                        }
                        failed += 1;
                    }
                }
            }
            let valid: Vec<u16> = grid.iter().copied().filter(|&v| v != u16::MAX).collect();
            let (lo, hi) = (*valid.iter().min().unwrap_or(&0), *valid.iter().max().unwrap_or(&1));
            let img = image::GrayImage::from_fn(w as u32, h as u32, |x, y| {
                let v = grid[y as usize * w + x as usize];
                let t = if v == u16::MAX { 0.0 } else { (v - lo) as f32 / (hi - lo).max(1) as f32 };
                image::Luma([(t * 255.0) as u8])
            });
            img.save(out)?;
            println!("{cols}x{rows} tiles, raw height range {lo}..{hi}, {empty} without heights, {failed} failed -> {out}");
            Ok(())
        }
        [_, "height", path, tx, ty] => {
            let mut ptt = Ptt::open(path)?;
            let mut src = HeightSource::new(&mut ptt)?;
            let raw = src.sample(&mut ptt, tx.parse()?, ty.parse()?)?;
            println!("terrain ({tx}, {ty}): raw {raw:.1} -> {:.1} (raw-20342)/9.2575", (raw - 20342.0) / 9.2575);
            Ok(())
        }
        [_, "export", path, index, out] => export(path, index.parse()?, std::path::Path::new(out)),
        _ => bail!("usage: iaf-terrain info <map.ptt> | mosaic|heights <map.ptt> <level-index> <out.png> | export <map.ptt> <level-index> <out-dir>"),
    }
}

/// Elevation sampler over the finest whole-theatre level. Inset levels carry
/// colour only; the original engine derives their heights from the level above
/// (`FUN_004280a0`), we do the same with bilinear filtering.
struct HeightSource {
    level: iaf_formats::ptt::Level,
    tiles: Vec<iaf_formats::ptt::TileEntry>,
    cache: std::collections::HashMap<usize, Option<std::rc::Rc<Vec<u16>>>>,
}

impl HeightSource {
    fn new(ptt: &mut Ptt) -> Result<Self> {
        let level = ptt
            .levels
            .iter()
            .filter(|l| l.flag == 1)
            .min_by_key(|l| l.level)
            .context("no theatre level")?
            .clone();
        let tiles = ptt.tiles(&level)?;
        Ok(Self { level, tiles, cache: Default::default() })
    }

    /// Raw height at a source-level pixel (clamped to the level).
    fn pixel(&mut self, ptt: &mut Ptt, px: i64, py: i64) -> Result<f32> {
        let n = TILE_PIXELS as i64;
        let (cols, rows) = (self.level.columns() as i64, self.level.rows() as i64);
        let px = px.clamp(0, cols * n - 1);
        let py = py.clamp(0, rows * n - 1);
        let k = ((py / n) * cols + px / n) as usize;
        if !self.cache.contains_key(&k) {
            let h = ptt.tile_heights(&self.tiles[k])?.map(std::rc::Rc::new);
            self.cache.insert(k, h);
        }
        Ok(match &self.cache[&k] {
            Some(h) => h[((py % n) * n + px % n) as usize] as f32,
            None => 20342.0,
        })
    }

    /// Bilinear raw height at world coordinates.
    fn sample(&mut self, ptt: &mut Ptt, wx: f64, wy: f64) -> Result<f32> {
        let upp = self.level.tile_span() as f64 / TILE_PIXELS as f64;
        let fx = (wx - self.level.rect[0] as f64) / upp;
        let fy = (wy - self.level.rect[1] as f64) / upp;
        let (x0, y0) = (fx.floor() as i64, fy.floor() as i64);
        let (tx, ty) = ((fx - x0 as f64) as f32, (fy - y0 as f64) as f32);
        let a = self.pixel(ptt, x0, y0)?;
        let b = self.pixel(ptt, x0 + 1, y0)?;
        let c = self.pixel(ptt, x0, y0 + 1)?;
        let d = self.pixel(ptt, x0 + 1, y0 + 1)?;
        Ok((a * (1.0 - tx) + b * tx) * (1.0 - ty) + (c * (1.0 - tx) + d * tx) * ty)
    }
}

/// Tiles per chunk side: 8 × 128 px = 1024 px chunks.
const CHUNK_TILES: u32 = 8;

/// Writes `<out>/c_<cx>_<cy>.jpg` (colour, 1024²) and `<out>/h_<cx>_<cy>.png` (raw u16 height,
/// 1025² including the neighbour's first row/column, packed as R = high byte, G = low byte so it
/// survives 8-bit PNG losslessly) plus `meta.json`.
fn export(path: &str, index: usize, out: &std::path::Path) -> Result<()> {
    use image::codecs::jpeg::JpegEncoder;
    let mut ptt = Ptt::open(path)?;
    let level = ptt.levels.get(index).context("no such level")?.clone();
    let tiles = ptt.tiles(&level)?;
    let (cols, rows) = (level.columns(), level.rows());
    let (ccols, crows) = (cols.div_ceil(CHUNK_TILES), rows.div_ceil(CHUNK_TILES));
    let n = TILE_PIXELS;
    let side = CHUNK_TILES * n;
    std::fs::create_dir_all(out)?;
    let mut written = 0;
    let own_heights = tiles.first().is_some_and(|t| t.height_size > 0);
    let mut source = if own_heights { None } else { Some(HeightSource::new(&mut ptt)?) };
    let upp = level.tile_span() as f64 / n as f64;
    for cy in 0..crows {
        for cx in 0..ccols {
            let mut colour = RgbImage::new(side, side);
            // Heights get one extra row/column from the neighbouring chunk so chunk edges match.
            let mut height = RgbImage::new(side + 1, side + 1);
            let mut any = false;
            for ty in 0..=CHUNK_TILES {
                for tx in 0..=CHUNK_TILES {
                    let (c, r) = ((cx * CHUNK_TILES + tx).min(cols - 1), (cy * CHUNK_TILES + ty).min(rows - 1));
                    if cx * CHUNK_TILES + tx >= cols + 1 || cy * CHUNK_TILES + ty >= rows + 1 {
                        continue;
                    }
                    let t = &tiles[(r * cols + c) as usize];
                    let inside = tx < CHUNK_TILES && ty < CHUNK_TILES && cx * CHUNK_TILES + tx < cols && cy * CHUNK_TILES + ty < rows;
                    if inside {
                        let jpeg = ptt.tile_jpeg(t)?;
                        colour.copy_from(&image::load_from_memory(&jpeg)?.to_rgb8(), tx * n, ty * n)?;
                        any = true;
                    }
                    if !own_heights {
                        continue;
                    }
                    if let Some(h) = ptt.tile_heights(t)? {
                        for (i, v) in h.iter().enumerate() {
                            let (x, y) = (tx * n + i as u32 % n, ty * n + i as u32 / n);
                            if x <= side && y <= side {
                                height.put_pixel(x, y, image::Rgb([(v >> 8) as u8, (v & 0xff) as u8, 0]));
                            }
                        }
                    }
                }
            }
            if !any {
                continue;
            }
            if let Some(src) = source.as_mut() {
                for y in 0..=side {
                    for x in 0..=side {
                        let wx = level.rect[0] as f64 + ((cx * side + x) as f64) * upp;
                        let wy = level.rect[1] as f64 + ((cy * side + y) as f64) * upp;
                        let v = src.sample(&mut ptt, wx, wy)?.round().clamp(0.0, 65535.0) as u16;
                        height.put_pixel(x, y, image::Rgb([(v >> 8) as u8, (v & 0xff) as u8, 0]));
                    }
                }
                // Keep the cache bounded to the tiles near this chunk row.
                if src.cache.len() > 4096 {
                    src.cache.clear();
                }
            }
            let mut f = std::io::BufWriter::new(std::fs::File::create(out.join(format!("c_{cx}_{cy}.jpg")))?);
            colour.write_with_encoder(JpegEncoder::new_with_quality(&mut f, 92))?;
            height.save(out.join(format!("h_{cx}_{cy}.png")))?;
            written += 1;
        }
    }
    let span = level.tile_span();
    let meta = serde_json::json!({
        "level": level.level,
        "rect": level.rect,
        "tile_span": span,
        "chunk_pixels": side,
        "chunk_span": span * CHUNK_TILES,
        "chunks": [ccols, crows],
        "heights_from_level": source.as_ref().map_or(level.level, |s| s.level.level),
        "units_per_pixel": span as f64 / n as f64,
        // Engine world (metres, X east / Y north) from terrain units (FUN_004053b0/…420):
        //   X = tx * units_to_metres + x_shift ;  Y = y_shift - ty * units_to_metres
        // Heights: metres = (raw - sea_level_raw) / height_scale * units_to_metres
        // (checked: Ramat David runway 63.7 m vs 63 m in takeoff.mis).
        "units_to_metres": 1.2411389,
        "x_shift": -166850,
        "y_shift": 1043780,
        "sea_level_raw": 20342,
        "height_scale": 9.2575,
    });
    std::fs::write(out.join("meta.json"), serde_json::to_string_pretty(&meta)?)?;
    println!("{written} chunks ({ccols}x{crows}) -> {}", out.display());
    Ok(())
}
