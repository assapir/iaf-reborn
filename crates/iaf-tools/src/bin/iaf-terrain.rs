//! Terrain tools for `map.ptt`.
//!
//! `iaf-terrain export <map.ptt> <level-index> <out-dir>` — engine chunks: colour JPEG + height PNG + meta.json
//! `iaf-terrain details <map.ptt> <base-level-index> <out-dir>` — high-detail tiles where the map has
//!   airbase insets (levels 0..2), 1 unit per pixel, aligned to the base export's chunks

use anyhow::{Context, Result, bail};
use iaf_formats::ptt::{Ptt, TILE_PIXELS};
use image::{GenericImage, RgbImage};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [_, "export", path, index, out] => export(path, index.parse()?, std::path::Path::new(out)),
        [_, "details", path, index, out] => details(path, index.parse()?, std::path::Path::new(out)),
        _ => bail!("usage: iaf-terrain export|details <map.ptt> <level-index> <out-dir>"),
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

/// Detail tile side in terrain units (and pixels: 1 unit per pixel, the level-0 resolution).
const DETAIL_SPAN: u32 = 2048;
/// Finest-first inset levels that get detail tiles (the airbase insets).
const DETAIL_MAX_LEVEL: u32 = 2;

/// Writes `<out>/d_<gx>_<gy>.jpg` (2048², 1 unit per pixel) for every 2048-unit cell of the base
/// level's grid touched by an inset of level <= 2, plus `details.json`. Each tile is painted
/// coarse to fine: the base level, then every inset of level 3..0 that covers it, each level
/// mosaicked at its own resolution and Lanczos-resampled to the tile. Then the runway-number
/// fixes (`iaf_tools::runway_fix`, a deliberate improvement over the original imagery) that touch
/// the tile are applied, each re-sampled from its own composition so it is seamless across tiles.
fn details(path: &str, base_index: usize, out: &std::path::Path) -> Result<()> {
    use image::codecs::jpeg::JpegEncoder;
    let mut ptt = Ptt::open(path)?;
    let base = ptt.levels.get(base_index).context("no such level")?.clone();
    std::fs::create_dir_all(out)?;
    let fixes = iaf_tools::runway_fix::load()?;
    // Painting order: base, then insets inside the base from coarse to fine.
    let mut sources: Vec<iaf_formats::ptt::Level> = ptt
        .levels
        .iter()
        .filter(|l| l.flag == 0 && l.level < base.level && overlaps(&l.rect, &base.rect))
        .cloned()
        .collect();
    sources.sort_by_key(|l| std::cmp::Reverse(l.level));
    sources.insert(0, base.clone());
    // Cells to export: those touched by an airbase inset.
    let mut cells = std::collections::BTreeSet::new();
    for l in sources.iter().filter(|l| l.flag == 0 && l.level <= DETAIL_MAX_LEVEL) {
        let r = clip(&l.rect, &base.rect);
        for gy in (r[1] - base.rect[1]) / DETAIL_SPAN..(r[3] - base.rect[1]).div_ceil(DETAIL_SPAN) {
            for gx in (r[0] - base.rect[0]) / DETAIL_SPAN..(r[2] - base.rect[0]).div_ceil(DETAIL_SPAN) {
                cells.insert((gx, gy));
            }
        }
    }
    let mut tile_lists = std::collections::HashMap::new();
    for (i, l) in sources.iter().enumerate() {
        tile_lists.insert(i, ptt.tiles(l)?);
    }
    let mut written = Vec::new();
    let mut fixed = 0;
    for &(gx, gy) in &cells {
        let cell = [
            base.rect[0] + gx * DETAIL_SPAN,
            base.rect[1] + gy * DETAIL_SPAN,
            base.rect[0] + (gx + 1) * DETAIL_SPAN,
            base.rect[1] + (gy + 1) * DETAIL_SPAN,
        ];
        let mut img = compose(&mut ptt, &sources, &tile_lists, cell)?;
        for fix in fixes.iter().filter(|f| f.intersects(&cell)) {
            // Source: the unfixed imagery around the patch (aligned to the coarsest source pixel,
            // 16 units, so the resampled levels line up exactly with the tile's own composition).
            let r = clip(&fix.source_rect(16, 16), &base.rect);
            let src = compose(&mut ptt, &sources, &tile_lists, r)?;
            fix.apply(&mut img, [cell[0], cell[1]], &src, [r[0], r[1]]);
            println!("d_{gx}_{gy}: runway number fix '{}'", fix.name);
            fixed += 1;
        }
        let mut f = std::io::BufWriter::new(std::fs::File::create(out.join(format!("d_{gx}_{gy}.jpg")))?);
        img.write_with_encoder(JpegEncoder::new_with_quality(&mut f, 90))?;
        written.push([gx, gy]);
    }
    let meta = serde_json::json!({
        "base_level": base.level,
        "base_rect": base.rect,
        "span": DETAIL_SPAN,
        "pixels": DETAIL_SPAN,
        "tiles": written,
    });
    std::fs::write(out.join("details.json"), serde_json::to_string(&meta)?)?;
    println!("{} detail tiles -> {} ({fixed} runway-number patches)", written.len(), out.display());
    Ok(())
}

/// Paints the world rect `rect` (1 unit per pixel) from `sources`, coarse to fine: each level is
/// mosaicked at its own resolution and Lanczos-resampled to 1 unit per pixel.
fn compose(
    ptt: &mut Ptt,
    sources: &[iaf_formats::ptt::Level],
    tile_lists: &std::collections::HashMap<usize, Vec<iaf_formats::ptt::TileEntry>>,
    cell: [u32; 4],
) -> Result<RgbImage> {
    use image::imageops::{FilterType, resize};
    let mut img = RgbImage::new(cell[2] - cell[0], cell[3] - cell[1]);
    for (i, l) in sources.iter().enumerate() {
        if !overlaps(&l.rect, &cell) {
            continue;
        }
        let r = clip(&l.rect, &cell);
        let upp = l.tile_span() / TILE_PIXELS; // units per source pixel
        // Source tiles covering r, mosaicked at native resolution.
        let (c0, r0) = ((r[0] - l.rect[0]) / l.tile_span(), (r[1] - l.rect[1]) / l.tile_span());
        let (c1, r1) = ((r[2] - l.rect[0]).div_ceil(l.tile_span()), (r[3] - l.rect[1]).div_ceil(l.tile_span()));
        let mut mosaic = RgbImage::new((c1 - c0) * TILE_PIXELS, (r1 - r0) * TILE_PIXELS);
        for tr in r0..r1 {
            for tc in c0..c1 {
                let t = &tile_lists[&i][(tr * l.columns() + tc) as usize];
                if let Ok(tile) = ptt.tile_jpeg(t).map_err(anyhow::Error::from).and_then(|j| Ok(image::load_from_memory(&j)?)) {
                    mosaic.copy_from(&tile.to_rgb8(), (tc - c0) * TILE_PIXELS, (tr - r0) * TILE_PIXELS)?;
                }
            }
        }
        // Crop to r (source pixels), resample to 1 unit per pixel, paste.
        let (ox, oy) = ((r[0] - l.rect[0]) / upp - c0 * TILE_PIXELS, (r[1] - l.rect[1]) / upp - r0 * TILE_PIXELS);
        let (w, h) = ((r[2] - r[0]).div_ceil(upp), (r[3] - r[1]).div_ceil(upp));
        let crop = image::imageops::crop_imm(&mosaic, ox, oy, w, h).to_image();
        let scaled = if upp == 1 { crop } else { resize(&crop, r[2] - r[0], r[3] - r[1], FilterType::Lanczos3) };
        img.copy_from(&scaled, r[0] - cell[0], r[1] - cell[1])?;
    }
    Ok(img)
}

fn overlaps(a: &[u32; 4], b: &[u32; 4]) -> bool {
    a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3]
}

fn clip(a: &[u32; 4], b: &[u32; 4]) -> [u32; 4] {
    [a[0].max(b[0]), a[1].max(b[1]), a[2].min(b[2]), a[3].min(b[3])]
}
