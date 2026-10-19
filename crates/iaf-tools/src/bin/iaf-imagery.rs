//! Modern terrain imagery layers (docs/imagery.md).
//!
//! `iaf-imagery sentinel2 <install-dir> <theatre-dir> <out-root> [--area lon0,lat0,lon1,lat1] [--dry-run] [--threads N]`
//! `iaf-imagery mapi2015  <install-dir> <theatre-dir> <out-root> [--sheets DIR] [--area …] [--dry-run] [--threads N]`
//!
//! `sentinel2`: ESA WorldCover 2021 Sentinel-2 RGB (10 m, CC BY 4.0) for the land outside Israel, fetched by
//! HTTP range reads through GDAL (`gdalbuildvrt` / `gdal_translate` over `/vsicurl/`), written at level 3.
//! `mapi2015`: the Survey of Israel 2015 2 m orthophoto sheets downloaded into `--sheets` (default
//! `<install-dir>/../source/imagery/mapi2015`, ZIPs read in place through `/vsizip/`), for Israel, written at
//! level 1. Each source is warped into the game frame with the georeference and written as two layers under
//! `<out-root>`: `<id>` (colour-matched to the 1998 imagery) and `<id>_modern`, each a node set like the
//! converted theatre (`L<L>/c_<i>_<j>.jpg`, the layer level .. 11) plus `manifest.json`.
//! Resumable and incremental: finished work units are remembered in `<out-root>/.work/` with the sheets they
//! used, so a re-run after adding sheets redoes only the units those sheets touch.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_tools::imagery::{Cache, Key, Theatre};
use iaf_tools::imagery_run::{self, MAPI2015, Run, SENTINEL2};
use iaf_tools::progress::Stdout;

/// Every layer `compare` looks for (1998 colours, modern colours).
const ALL_LAYERS: [[&str; 2]; 2] = [["sentinel2", "sentinel2_modern"], ["mapi2015", "mapi2015_modern"]];

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let [cmd, theatre, layers, level, i, j, png] = &args[..]
        && cmd == "compare"
    {
        // Side by side: the original as drawn, then each converted layer's node (docs/imagery.md §6).
        let t = Theatre::load(Path::new(theatre))?;
        let k: Key = (level.parse()?, i.parse()?, j.parse()?);
        let pair = ALL_LAYERS
            .iter()
            .find(|p| Path::new(layers).join(p[0]).join(format!("L{}/c_{}_{}.jpg", k.0, k.1, k.2)).exists());
        let pair = pair.context("no layer has that node")?;
        let mut row = image::RgbImage::new(1024 * 3, 1024);
        if let Some(img) = t.rendition(k, &mut Cache::default())? {
            image::imageops::replace(&mut row, img.as_ref(), 0, 0);
        }
        for (n, layer) in pair.iter().enumerate() {
            let f = Path::new(layers).join(layer).join(format!("L{}/c_{}_{}.jpg", k.0, k.1, k.2));
            if let Ok(img) = image::open(&f) {
                image::imageops::replace(&mut row, &img.to_rgb8(), 1024 * (n as i64 + 1), 0);
            }
        }
        row.save(png)?;
        return Ok(());
    }
    if let [cmd, install, theatre, out] = &args[..]
        && cmd == "footprints"
    {
        // The airbase footprints the layers leave to the 1998 inset (docs/imagery.md §3): areas, and the inset art
        // with the footprint (outside it darkened) per site.
        let t = Theatre::load(Path::new(theatre))?;
        let missions = Path::new(theatre).join("../../missions");
        std::fs::create_dir_all(out)?;
        for s in iaf_tools::airbases::sites(Path::new(install), &t, &missions)? {
            let g = &s.footprint;
            let r = s.rect;
            let rect_km2 =
                (r[2] - r[0]) as f64 * (r[3] - r[1]) as f64 * iaf_tools::georef::UNITS_TO_METRES.powi(2) / 1e6;
            let art =
                t.original_rect(2, (g.x0 / g.cell) as i64, (g.y0 / g.cell) as i64, g.w, g.h, &mut Cache::default())?;
            let img = image::RgbImage::from_fn(g.w as u32, g.h as u32, |x, y| {
                let k = y as usize * g.w + x as usize;
                let edge = g.v[k]
                    && [(1i64, 0i64), (-1, 0), (0, 1), (0, -1)].iter().any(|(dx, dy)| {
                        let (a, b) = (x as i64 + dx, y as i64 + dy);
                        a < 0 || b < 0 || a >= g.w as i64 || b >= g.h as i64 || !g.v[b as usize * g.w + a as usize]
                    });
                let c = art[k].map(|v| if g.v[k] { v } else { v * 0.45 });
                image::Rgb(if edge { [255, 40, 40] } else { c.map(|v| v as u8) })
            });
            let name = format!("footprint_{}_{}.png", r[0], r[1]);
            img.save(Path::new(out).join(&name))?;
            println!("site {:?}: rect {:.1} km², footprint {:.1} km²  {name}", r, rect_km2, g.area_km2());
            // The missions' units in the site that stand on the layer's ground (outside the footprint).
            let lineups = iaf_tools::airbases::ibx_lineups(&std::fs::read(Path::new(install).join("iaf.ibx"))?);
            let units: Vec<_> = iaf_tools::airbases::mission_units(&missions)
                .into_iter()
                .filter(|u| iaf_tools::airbases::on_ground(&lineups, u))
                .collect();
            let inside: Vec<_> = units
                .iter()
                .map(|u| (u, iaf_tools::airbases::units(u[0], u[1])))
                .filter(|(_, t)| t[0] >= r[0] as f64 && t[0] < r[2] as f64 && t[1] >= r[1] as f64 && t[1] < r[3] as f64)
                .collect();
            let out: Vec<_> = inside.iter().filter(|(_, t)| !g.at(t[0], t[1])).collect();
            println!(
                "  units in the site {}, outside the footprint {}: {:?}",
                inside.len(),
                out.len(),
                out.iter()
                    .take(if std::env::var("ALL").is_ok() { 9999 } else { 12 })
                    .map(|(u, _)| [u[0].round(), u[1].round()])
                    .collect::<Vec<_>>()
            );
        }
        return Ok(());
    }
    let usage = "usage: iaf-imagery sentinel2|mapi2015 <install-dir> <theatre-dir> <out-root> [--sheets DIR] [--area lon0,lat0,lon1,lat1] [--dry-run] [--stale] [--threads N]\n       iaf-imagery compare <theatre-dir> <layers-root> <level> <i> <j> <out.png>\n       iaf-imagery footprints <install-dir> <theatre-dir> <out-dir>";
    let [source, install, theatre, out, rest @ ..] = &args[..] else { bail!(usage) };
    let spec = match source.as_str() {
        "sentinel2" => &SENTINEL2,
        "mapi2015" => &MAPI2015,
        _ => bail!("unknown source '{source}' (known: sentinel2, mapi2015)\n{usage}"),
    };
    let mut area: Option<[f64; 4]> = None;
    let mut dry = false;
    let mut stale = false;
    let mut threads = 4;
    let mut sheets = Path::new(install).join("../source/imagery/mapi2015");
    let mut it = rest.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--area" => {
                let v: Vec<f64> = it.next().context(usage)?.split(',').map(str::parse).collect::<Result<_, _>>()?;
                area = Some(v.try_into().map_err(|_| anyhow::anyhow!("--area wants lon0,lat0,lon1,lat1"))?);
            }
            "--dry-run" => dry = true,
            "--stale" => stale = true,
            "--threads" => threads = it.next().context(usage)?.parse()?,
            "--sheets" => sheets = PathBuf::from(it.next().context(usage)?),
            _ => bail!(usage),
        }
    }
    let r = Run {
        spec,
        install: install.into(),
        theatre: theatre.into(),
        out: out.into(),
        sheets,
        area,
        dry_run: dry,
        stale,
        threads,
    };
    imagery_run::run(&r, &Stdout, &AtomicBool::new(false))?;
    Ok(())
}
