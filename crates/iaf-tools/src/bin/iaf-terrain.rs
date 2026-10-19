//! Terrain tools for `map.ptt`.
//!
//! `iaf-terrain theatre <map.ptt> <out-dir> [threads]` — every level and every inset of the file as
//! a quadtree of 1024-pixel nodes (docs/formats/ptt.md "Converted layout"): colour JPEGs per level,
//! raw heights for the whole-theatre levels 6..11, `meta.json`.

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Result, bail};
use iaf_tools::progress::Stdout;
use iaf_tools::terrain::{self, default_threads};
fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [_, "theatre", path, out] => terrain::theatre(Path::new(path), Path::new(out), default_threads(), &Stdout, &AtomicBool::new(false)),
        [_, "theatre", path, out, threads] => terrain::theatre(Path::new(path), Path::new(out), threads.parse()?, &Stdout, &AtomicBool::new(false)),
        [_, "airbases", install, theatre, out] => terrain::airbases(Path::new(install), Path::new(theatre), Path::new(out), None, &Stdout, &AtomicBool::new(false)),
        [_, "airbases", install, theatre, out, "--debug", dbg] => {
            terrain::airbases(Path::new(install), Path::new(theatre), Path::new(out), Some(Path::new(dbg)), &Stdout, &AtomicBool::new(false))
        }
        [_, "georef-points", theatre, z9, z10, out, lambda] => {
            georef_points(Path::new(theatre), Path::new(z9), Path::new(z10), Path::new(out), lambda.parse()?)
        }
        [_, "geo", points, x, y] => {
            // Engine metres (X east, Y north) -> lon / lat with the given control points.
            let (pts, lambda) = iaf_tools::georef::parse(&std::fs::read_to_string(points)?)?;
            let g = iaf_tools::georef::Georef::fit(pts, lambda)?;
            let [lon, lat] = g.engine_to_geo(x.parse()?, y.parse()?);
            println!("{lat:.6} {lon:.6}");
            Ok(())
        }
        [_, "game", points, lat, lon] => {
            // lat / lon -> engine metres (X east, Y north): the inverse of `geo`.
            let (pts, lambda) = iaf_tools::georef::parse(&std::fs::read_to_string(points)?)?;
            let g = iaf_tools::georef::Georef::fit(pts, lambda)?;
            let [x, y] = g.geo_to_engine(lon.parse()?, lat.parse()?);
            println!("{x:.1} {y:.1}");
            Ok(())
        }
        _ => bail!(
            "usage: iaf-terrain theatre <map.ptt> <out-dir> [threads]\n       \
             iaf-terrain airbases <install-dir> <theatre-dir> <out-dir> [--debug <dir>]\n       \
             iaf-terrain georef-points <theatre-dir> <eox-z9-dir> <eox-z10-dir> <out.json> <lambda>\n       \
             iaf-terrain geo <points.json> <X> <Y>      (engine metres -> lat lon)\n       \
             iaf-terrain game <points.json> <lat> <lon>  (lat lon -> engine metres X Y)"
        ),
    }
}

/// `iaf-terrain georef-points`: measures the automatic georeference control points (docs/georef.md
/// §2) and writes them with the hand-measured points already in `out` (kind other than "auto",
/// kept as they are; none so far).
fn georef_points(theatre: &Path, z9: &Path, z10: &Path, out: &Path, lambda: f64) -> Result<()> {
    use iaf_tools::georef_measure as gm;
    let coarse = gm::Pair::load(theatre, 7, z9, 9, 6.0)?;
    let fine = gm::Pair::load(theatre, 6, z10, 10, 6.0)?;
    // Level 8 (318 m) with 20 km patches: the coarse, painted parts of the original (Cyprus, the
    // Nile valley) where the finer passes find nothing.
    let rough = gm::Pair::load(theatre, 8, z9, 9, 16.0)?;
    let mut rough_ms = Vec::new();
    let extra: Vec<iaf_tools::georef::Point> = match std::fs::read_to_string(out) {
        Ok(s) => iaf_tools::georef::parse(&s)?.0.into_iter().filter(|p| p.kind != "auto").collect(),
        Err(_) => Vec::new(),
    };
    let threads = default_threads();
    let mut warp = gm::initial()?;
    let mut kept = Vec::new();
    for (pair, step, margin, k, floor) in [
        (&coarse, 32768.0, 40, 3.0, 300.0),
        (&coarse, 16384.0, 8, 3.0, 150.0),
        (&fine, 12288.0, 6, 3.0, 80.0),
        (&fine, 12288.0, 3, 3.0, 60.0),
    ] {
        let mut ms = gm::pass(pair, &warp, step, margin, threads);
        if pair.level == 6 {
            if rough_ms.is_empty() {
                rough_ms = gm::pass(&rough, &warp, 24576.0, 30, threads);
            }
            // Coarse points only where the fine pass has none within 20 km.
            let near = |m: &gm::Match| ms.iter().any(|f: &gm::Match| (f.game[0] - m.game[0]).hypot(f.game[1] - m.game[1]) < 16000.0);
            let add: Vec<gm::Match> = rough_ms.iter().filter(|m| m.ncc >= 0.5 && !near(m)).map(|m| gm::Match { game: m.game, geo: m.geo, ncc: m.ncc, level: m.level }).collect();
            ms.extend(add);
        }
        let n = ms.len();
        let (g, ks) = gm::robust_fit(ms, &extra, lambda, k, floor)?;
        let mut r = g.residuals_m();
        r.sort_by(f64::total_cmp);
        let rms = (r.iter().map(|x| x * x).sum::<f64>() / r.len() as f64).sqrt();
        println!(
            "pass L{} step {step} margin {margin}: {n} matches, {} kept; residual rms {rms:.0} m, median {:.0} m, max {:.0} m",
            pair.level,
            ks.len(),
            r[r.len() / 2],
            r[r.len() - 1]
        );
        warp = g;
        kept = ks;
    }
    // Hold-out check: fit on 4/5 of the points, residuals of the other fifth (docs/georef.md §3).
    let all = gm::to_points(&kept);
    let mut held = Vec::new();
    let mut worst = Vec::new();
    for f in 0..5 {
        let train: Vec<_> = all.iter().enumerate().filter(|(i, _)| i % 5 != f).map(|(_, p)| p.clone()).chain(extra.iter().cloned()).collect();
        let g = iaf_tools::georef::Georef::fit(train, lambda)?;
        for p in all.iter().skip(f).step_by(5) {
            let q = g.to_game(p.geo[0], p.geo[1]);
            let e = (q[0] - p.game[0]).hypot(q[1] - p.game[1]) * iaf_tools::georef::UNITS_TO_METRES;
            held.push(e);
            worst.push((e, p.id.clone(), p.geo));
        }
    }
    held.sort_by(f64::total_cmp);
    let rms = (held.iter().map(|x| x * x).sum::<f64>() / held.len() as f64).sqrt();
    worst.sort_by(|a, b| b.0.total_cmp(&a.0));
    for (e, id, g) in worst.iter().take(8) {
        println!("  hold-out {e:.0} m at {id} ({:.3} N {:.3} E)", g[1], g[0]);
    }
    println!("hold-out: rms {rms:.0} m, median {:.0} m, 95% {:.0} m, max {:.0} m", held[held.len() / 2], held[held.len() * 95 / 100], held[held.len() - 1]);
    let mut pts: Vec<serde_json::Value> = gm::to_points(&kept)
        .iter()
        .zip(&kept)
        .map(|(p, m)| serde_json::json!({"id": p.id, "kind": p.kind, "tx": p.game[0], "ty": p.game[1],
            "lon": (p.geo[0] * 1e6).round() / 1e6, "lat": (p.geo[1] * 1e6).round() / 1e6, "ncc": (m.ncc * 100.0).round() / 100.0}))
        .collect();
    pts.extend(extra.iter().map(|p| serde_json::json!({"id": p.id, "kind": p.kind, "tx": p.game[0], "ty": p.game[1], "lon": p.geo[0], "lat": p.geo[1]})));
    let json = serde_json::json!({
        "about": "Georeference control points (docs/georef.md): terrain units (tx east, ty south) <-> WGS84 lon/lat. \
                  auto = correlation of the original level-6/7/8 imagery with EOxCloudless 2017 (iaf-terrain georef-points).",
        "lambda": lambda,
        "points": pts,
    });
    let mut s = serde_json::to_string(&json)?;
    // One point per line (readable diffs).
    s = s.replace("},{\"id\"", "},\n{\"id\"").replace("[{\"id\"", "[\n{\"id\"");
    std::fs::write(out, s + "\n")?;
    println!("{} points -> {}", pts.len(), out.display());
    Ok(())
}

