//! `IafBases`: World scale Real 1:1's base move (iaf_flight::base_move, docs/world-scale.md §3.3) for the whole
//! process: set up from the setting at mission load, read by the flight model's bases (`flight.rs`), the surface
//! lookups (`surface.rs`), the terrain's image patches and the mission data (GDScript).

use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::{LazyLock, RwLock};

use godot::prelude::*;
use iaf_avionics::heights::{HeightField, Meta};
use iaf_flight::airbase::Airbase;
use iaf_flight::base_move::{BaseMoves, GameBase, Mask};

/// The moves; None in Original (every path then is the original's).
pub static MOVES: LazyLock<RwLock<Option<BaseMoves>>> = LazyLock::new(Default::default);
/// The theatre's frame (meta.json) for the image patches.
static META: LazyLock<RwLock<Meta>> = LazyLock::new(Default::default);

/// iaf.ibx's bases at their new sites (no change in Original).
pub fn map_airbases(bases: &mut [Airbase]) {
    if let Some(m) = &*MOVES.read().unwrap() {
        m.map_airbases(bases);
    }
}

fn load(assets: &Path) -> Option<(BaseMoves, Meta)> {
    let ibx = Airbase::load_all(&std::fs::read(assets.join("install/iaf.ibx")).ok()?);
    let terrain = assets.join("converted/terrain");
    let j: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(terrain.join("airbases.json")).ok()?).ok()?;
    let mj: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(terrain.join("theatre/meta.json")).ok()?).ok()?;
    let f = |k: &str| mj[k].as_f64().unwrap_or(0.0);
    let meta = Meta {
        node_pixels: f("node_pixels") as usize,
        span: f("node_pixels") * 2f64.powi(f("height_level") as i32),
        sea_level_raw: f("sea_level_raw"),
        height_scale: f("height_scale"),
        m_per_unit: f("units_to_metres"),
        x_shift: f("x_shift"),
        y_shift: f("y_shift"),
    };
    let pt = |v: &serde_json::Value| [v[0].as_f64().unwrap_or(0.0), v[1].as_f64().unwrap_or(0.0)];
    let jbases = j["bases"].as_array()?;
    let mut masks = Vec::new();
    let games: Vec<GameBase> = ibx
        .iter()
        .filter_map(|b| {
            let jb = jbases.iter().find(|x| x["name"] == b.name.as_str())?;
            let rw = jb["runways"].as_array()?.iter().map(|r| [pt(&r["ends"][0]), pt(&r["ends"][1])]).collect();
            let widths = jb["runways"].as_array()?.iter().map(|r| r["width"].as_f64().unwrap_or(0.0)).collect();
            let m = &jb["mask"];
            let img = m["file"].as_str().and_then(|f| image::open(terrain.join(f)).ok()).map(|i| i.to_rgb8());
            masks.push((
                b.name.clone(),
                img.map(|i| Mask {
                    origin: pt(&m["origin"]),
                    w: i.width() as usize,
                    h: i.height() as usize,
                    px_m: m["px_m"].as_f64().unwrap_or(2.5),
                    rgb: i.into_raw(),
                }),
            ));
            Some(GameBase { widths, ..GameBase::new(b, rw) })
        })
        .collect();
    let mut moves = BaseMoves::new(&games);
    for b in &mut moves.bases {
        b.mask = masks.iter().find(|(n, _)| *n == b.name).and_then(|(_, m)| m.clone());
    }
    // The elevations from the original level-6 heights (unpatched).
    let mut field = HeightField::default();
    field.set_meta(meta);
    let mut loaded = std::collections::HashSet::new();
    for b in &moves.bases {
        for t in [0.0, 0.5, 1.0] {
            let p = [b.real_c[0] + t * b.real_len * b.real_d[0], b.real_c[1] + t * b.real_len * b.real_d[1]];
            let (tx, ty) = ((p[0] - meta.x_shift) / meta.m_per_unit, (meta.y_shift - p[1]) / meta.m_per_unit);
            let (i, j) = ((tx / meta.span).floor() as i64, (ty / meta.span).floor() as i64);
            if loaded.insert((i, j)) {
                let path = terrain.join(format!("theatre/L6/h_{i}_{j}.png"));
                if let Ok(img) = image::open(&path) {
                    let img = img.to_rgb8();
                    let rg8: Vec<u8> = img.pixels().flat_map(|p| [p[0], p[1]]).collect();
                    field.add(i, j, img.width() as usize, &rg8);
                }
            }
        }
    }
    moves.set_elevations(|x, y| field.height(iaf_avionics::Vec3::new(x, y, 0.0)));
    Some((moves, meta))
}

/// The terrain levels that get the new sites' fine art (finer than the old sites' fill level, 3).
const INSET_LEVELS: std::ops::Range<i32> = 0..3;

/// The original's colour nodes of one level that the warp reads.
struct Art {
    level: i32,
    meta: Meta,
    nodes: HashMap<(i64, i64), image::RgbImage>,
}

impl Art {
    fn pixel(&self, gx: i64, gy: i64) -> Option<[u8; 3]> {
        let np = self.meta.node_pixels as i64;
        let img = self.nodes.get(&(gx.div_euclid(np), gy.div_euclid(np)))?;
        let (x, y) = (gx.rem_euclid(np) as u32, gy.rem_euclid(np) as u32);
        (x < img.width() && y < img.height()).then(|| img.get_pixel(x, y).0)
    }

    /// The colour at an engine point, bilinear; None where a pixel is missing.
    fn sample(&self, p: [f64; 2]) -> Option<[f64; 3]> {
        let upp = 2f64.powi(self.level) * self.meta.m_per_unit;
        let gx = (p[0] - self.meta.x_shift) / upp - 0.5;
        let gy = (self.meta.y_shift - p[1]) / upp - 0.5;
        let (x0, y0) = (gx.floor() as i64, gy.floor() as i64);
        let (fx, fy) = (gx - x0 as f64, gy - y0 as f64);
        let (a, b, c, d) =
            (self.pixel(x0, y0)?, self.pixel(x0 + 1, y0)?, self.pixel(x0, y0 + 1)?, self.pixel(x0 + 1, y0 + 1)?);
        Some(std::array::from_fn(|k| {
            let l = |v: [u8; 3]| v[k] as f64;
            (l(a) * (1.0 - fx) + l(b) * fx) * (1.0 - fy) + (l(c) * (1.0 - fx) + l(d) * fx) * fy
        }))
    }
}

/// `f` over `items` on every core; the results in order.
fn par_map<T: Sync, R: Send>(items: &[T], f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    let next = std::sync::atomic::AtomicUsize::new(0);
    let out = std::sync::Mutex::new(Vec::new());
    let n = std::thread::available_parallelism().map_or(4, |n| n.get()).min(items.len());
    std::thread::scope(|s| {
        for _ in 0..n {
            s.spawn(|| {
                loop {
                    let i = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    let Some(t) = items.get(i) else { break };
                    let r = f(t);
                    out.lock().unwrap().push((i, r));
                }
            });
        }
    });
    let mut v = out.into_inner().unwrap();
    v.sort_by_key(|(i, _)| *i);
    v.into_iter().map(|(_, r)| r).collect()
}

/// The new sites' fine art (docs/world-scale.md §4.3): per base and level 0–2, the nodes over the new zone A with
/// the old site's original art warped through the move, as RGBA PNGs (alpha = the weight) in `out`
/// (`L<level>/c_<i>_<j>.png`; the terrain lays them over the node's own colour). Made once; `out/nodes.txt` holds
/// the moves they were made for and the nodes. Returns [level, i, j] per node.
fn insets(moves: &BaseMoves, meta: Meta, theatre: &Path, out: &Path) -> std::io::Result<Vec<[i64; 3]>> {
    let stamp = format!(
        "v1 {:?}",
        moves
            .bases
            .iter()
            .map(|b| (&b.name, b.game_c, b.game_d, b.real_c, b.real_d, b.k, b.lo, b.hi))
            .collect::<Vec<_>>()
    );
    let list = out.join("nodes.txt");
    if let Ok(t) = std::fs::read_to_string(&list)
        && let Some(rest) = t.strip_prefix(&format!("{stamp}\n"))
    {
        return Ok(rest
            .lines()
            .filter_map(|l| {
                let v: Vec<i64> = l.split(' ').filter_map(|x| x.parse().ok()).collect();
                (v.len() == 3).then(|| [v[0], v[1], v[2]])
            })
            .collect());
    }
    let mj: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(theatre.join("meta.json"))?)?;
    let np = meta.node_pixels;
    let mut done: Vec<[i64; 3]> = Vec::new();
    for level in INSET_LEVELS {
        let have: HashSet<(i64, i64)> = mj["nodes"][level.to_string()]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|ij| Some((ij[0].as_i64()?, ij[1].as_i64()?)))
            .collect();
        let span = np as f64 * 2f64.powi(level) * meta.m_per_unit;
        let upp = span / np as f64;
        let nodes = |b: [f64; 4]| {
            let (i0, i1) =
                (((b[0] - meta.x_shift) / span).floor() as i64, ((b[2] - meta.x_shift) / span).floor() as i64);
            let (j0, j1) =
                (((meta.y_shift - b[3]) / span).floor() as i64, ((meta.y_shift - b[1]) / span).floor() as i64);
            (i0..=i1).flat_map(move |i| (j0..=j1).map(move |j| (i, j)))
        };
        let dir = out.join(format!("L{level}"));
        std::fs::create_dir_all(&dir)?;
        for b in &moves.bases {
            let src: Vec<(i64, i64)> = nodes(b.zone_box(false)).filter(|n| have.contains(n)).collect();
            if src.is_empty() {
                continue;
            }
            let decoded = par_map(&src, |n| {
                image::open(theatre.join(format!("L{level}/c_{}_{}.jpg", n.0, n.1))).ok().map(|i| (*n, i.to_rgb8()))
            });
            let art = Art { level, meta, nodes: decoded.into_iter().flatten().collect() };
            let outs: Vec<(i64, i64)> = nodes(b.zone_box(true)).collect();
            let made = par_map(&outs, |&(i, j)| -> std::io::Result<bool> {
                let path = dir.join(format!("c_{i}_{j}.png"));
                let mut rgba = match done.contains(&[level as i64, i, j]) {
                    true => image::open(&path).map_err(std::io::Error::other)?.to_rgba8().into_raw(),
                    false => vec![0u8; 4 * np * np],
                };
                let px = |x: usize, y: usize| {
                    [
                        i as f64 * span + (x as f64 + 0.5) * upp + meta.x_shift,
                        meta.y_shift - j as f64 * span - (y as f64 + 0.5) * upp,
                    ]
                };
                if !b.bake_inset(&mut rgba, np, np, px, |q| art.sample(q)) {
                    return Ok(false);
                }
                let tmp = dir.join(format!("c_{i}_{j}.png.tmp"));
                let file = std::io::BufWriter::new(std::fs::File::create(&tmp)?);
                let enc = image::codecs::png::PngEncoder::new_with_quality(
                    file,
                    image::codecs::png::CompressionType::Fast,
                    image::codecs::png::FilterType::Adaptive,
                );
                image::ImageEncoder::write_image(enc, &rgba, np as u32, np as u32, image::ExtendedColorType::Rgba8)
                    .map_err(std::io::Error::other)?;
                std::fs::rename(&tmp, &path)?;
                Ok(true)
            });
            for (&(i, j), m) in outs.iter().zip(made) {
                if m? && !done.contains(&[level as i64, i, j]) {
                    done.push([level as i64, i, j]);
                }
            }
        }
    }
    let mut t = format!("{stamp}\n");
    for n in &done {
        t += &format!("{} {} {}\n", n[0], n[1], n[2]);
    }
    let tmp = out.join("nodes.txt.tmp");
    std::fs::write(&tmp, t)?;
    std::fs::rename(&tmp, &list)?;
    Ok(done)
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafBases {}

#[godot_api]
impl IafBases {
    /// Real (`on`): the moves from `assets` (iaf.ibx, airbases.json and its masks, the level-6 heights); Original:
    /// none. False when on but the data is missing (then none).
    #[func]
    fn setup(on: bool, assets: GString) -> bool {
        let got = if on { load(Path::new(&assets.to_string())) } else { None };
        let ok = got.is_some() == on;
        if let Some((m, meta)) = got {
            *META.write().unwrap() = meta;
            *MOVES.write().unwrap() = Some(m);
        } else {
            *MOVES.write().unwrap() = None;
        }
        ok
    }

    #[func]
    fn active() -> bool {
        MOVES.read().unwrap().is_some()
    }

    /// A point's move: [x, y, turn (deg, clockwise), scale (k on the base, 1 around it), dz]; empty when it stays.
    #[func]
    fn map(x: f64, y: f64) -> PackedFloat64Array {
        let g = MOVES.read().unwrap();
        match g.as_ref().and_then(|m| m.map([x, y])) {
            Some(m) => PackedFloat64Array::from(&[m.p[0], m.p[1], m.turn, m.scale, m.dz][..]),
            None => PackedFloat64Array::new(),
        }
    }

    /// The surface flags at a world point (terraintype.dat through the moves).
    #[func]
    fn surface(x: f64, y: f64) -> i64 {
        crate::surface::at(x, y) as i64
    }

    /// The real designator's number (1–36) of base `name`'s runway flown at true `heading` (deg); 0 when not moved.
    #[func]
    fn designator(name: GString, heading: f64) -> i64 {
        let g = MOVES.read().unwrap();
        g.as_ref().and_then(|ms| ms.get(&name.to_string())).map_or(0, |m| m.designator(heading))
    }

    /// A runway sign at the world point (its new site) showing runway `n` in the game: the real designation there
    /// as a sign reads it ("25L", "09"); `n` ("23") off the moved bases (docs/world-scale.md §4.3).
    #[func]
    fn sign_designation(x: f64, y: f64, n: i64) -> GString {
        let g = MOVES.read().unwrap();
        let s = g.as_ref().and_then(|ms| ms.sign_designation([x, y], n));
        GString::from(&s.unwrap_or_else(|| format!("{n:02}")))
    }

    /// The moved base `name`'s paved-surface mask (RGB8, airbases.json's size) with the 1998 runways' wider part cut
    /// to the real width (`BaseMove::moved_mask`); empty when not moved or without a mask.
    #[func]
    fn moved_mask(name: GString) -> PackedByteArray {
        let g = MOVES.read().unwrap();
        let m = g.as_ref().and_then(|ms| ms.get(&name.to_string())).map(|m| m.moved_mask()).unwrap_or_default();
        PackedByteArray::from(m)
    }

    /// The moved base `name` in airbases.json's layout for the Detailed airbases drawing: runways (ends, width,
    /// numbers, thresholds) at the new site, `mask_affine` = the game point of a new-site point
    /// ([a0, a1, a2, b0, b1, b2]: x = a0·X + a1·Y + a2), `centre`; {} when not moved.
    #[func]
    fn base(name: GString, game: VarDictionary) -> VarDictionary {
        let g = MOVES.read().unwrap();
        let Some(m) = g.as_ref().and_then(|ms| ms.get(&name.to_string())) else { return VarDictionary::new() };
        let mut out = game.duplicate_deep();
        let mv = |p: [f64; 2]| m.map(p).map_or(p, |q| q.p);
        let mut runways = VarArray::new();
        let src: VarArray = game.get("runways").and_then(|v| v.try_to().ok()).unwrap_or_default();
        for r in src.iter_shared() {
            let Ok(r) = r.try_to::<VarDictionary>() else { continue };
            let ends: VarArray = r.get("ends").and_then(|v| v.try_to().ok()).unwrap_or_default();
            let e = |i: usize| -> [f64; 2] {
                let a: VarArray = ends.get(i).and_then(|v| v.try_to().ok()).unwrap_or_default();
                let n = |j: usize| a.get(j).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0);
                mv([n(0), n(1)])
            };
            let (e0, e1) = (e(0), e(1));
            // The real runway's designation (magnetic, OSM's ref) nearest the moved runway's middle, docs/world-scale.md
            // §4.3: the number and the letter of a parallel pair.
            let mid = [0.5 * (e0[0] + e1[0]), 0.5 * (e0[1] + e1[1])];
            let num =
                |a: [f64; 2], b: [f64; 2]| m.designation((b[0] - a[0]).atan2(b[1] - a[1]).to_degrees(), Some(mid));
            let th: VarArray = r.get("thresholds").and_then(|v| v.try_to().ok()).unwrap_or_default();
            let t = |i: usize| th.get(i).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0) * m.k;
            let mut d = r.duplicate_deep();
            d.set("ends", &varray![&varray![e0[0], e0[1]], &varray![e1[0], e1[1]]]);
            d.set("width", m.width);
            let (n0, n1) = (num(e0, e1), num(e1, e0));
            d.set("numbers", &varray![n0.0, n1.0]);
            d.set("letters", &varray![n0.1.as_str(), n1.1.as_str()]);
            d.set("thresholds", &varray![t(0), t(1)]);
            runways.push(&d.to_variant());
        }
        out.set("runways", &runways);
        let a = m.game_affine();
        out.set("mask_affine", &PackedFloat64Array::from(&[a[0][0], a[0][1], a[0][2], a[1][0], a[1][1], a[1][2]][..]));
        let l = mv([m.game_c[0], m.game_c[1]]);
        let c = [l[0] + 0.5 * m.real_len * m.real_d[0], l[1] + 0.5 * m.real_len * m.real_d[1]];
        out.set("centre", Vector2::new(c[0] as f32, c[1] as f32));
        out.set("k", m.k);
        out
    }

    /// The boxes where the terrain images need the patches: [x0, y0, x1, y1] per base (engine metres); empty in
    /// Original. The terrain's decode workers test their nodes against these (the extension is not callable there).
    #[func]
    fn bounds() -> PackedFloat64Array {
        let g = MOVES.read().unwrap();
        PackedFloat64Array::from(g.as_ref().map(|m| m.bounds().concat()).unwrap_or_default().as_slice())
    }

    /// The colour nodes of `level` under the old sites' fills (docs/world-scale.md §4.3): [i0, j0, i1, j1, …].
    #[func]
    fn fill_nodes(level: i64) -> PackedInt64Array {
        let g = MOVES.read().unwrap();
        let Some(m) = g.as_ref() else { return PackedInt64Array::new() };
        let meta = *META.read().unwrap();
        let span = meta.node_pixels as f64 * 2f64.powi(level as i32) * meta.m_per_unit;
        let mut out = Vec::new();
        for b in m.fill_boxes() {
            let (i0, i1) =
                (((b[0] - meta.x_shift) / span).floor() as i64, ((b[2] - meta.x_shift) / span).floor() as i64);
            let (j0, j1) =
                (((meta.y_shift - b[3]) / span).floor() as i64, ((meta.y_shift - b[1]) / span).floor() as i64);
            for i in i0..=i1 {
                for j in j0..=j1 {
                    out.extend([i, j]);
                }
            }
        }
        PackedInt64Array::from(out.as_slice())
    }

    /// The new sites' fine-art nodes (`insets`, made into `out` when missing or stale): [level, i, j, …]; empty in
    /// Original or on a failure (the new sites then keep the coarse ground).
    #[func]
    fn moved_insets(theatre: GString, out: GString) -> PackedInt64Array {
        let g = MOVES.read().unwrap();
        let Some(m) = g.as_ref() else { return PackedInt64Array::new() };
        let meta = *META.read().unwrap();
        match insets(m, meta, Path::new(&theatre.to_string()), Path::new(&out.to_string())) {
            Ok(v) => PackedInt64Array::from(v.concat().as_slice()),
            Err(e) => {
                godot_warn!("world scale real: the new sites' fine ground: {e}");
                PackedInt64Array::new()
            }
        }
    }

    /// A colour image of node (level, i, j) (RGB8) as a source of the old sites' fills; `done`: the last one.
    #[func]
    fn fill_source(rgb: PackedByteArray, w: i64, h: i64, level: i64, i: i64, j: i64, done: bool) {
        let mut g = MOVES.write().unwrap();
        let Some(m) = g.as_mut() else { return };
        let meta = *META.read().unwrap();
        let span = meta.node_pixels as f64 * 2f64.powi(level as i32);
        let nw = [i as f64 * span * meta.m_per_unit + meta.x_shift, meta.y_shift - j as f64 * span * meta.m_per_unit];
        m.add_fill_source(rgb.as_slice(), w as usize, h as usize, nw, span / w.max(1) as f64 * meta.m_per_unit);
        if done {
            m.finish_fill();
        }
    }

    /// A height image of node (level, i, j) (RG8, w × h texels at its vertices) with the new sites flattened.
    #[func]
    fn bake_heights(rg8: PackedByteArray, w: i64, h: i64, level: i64, i: i64, j: i64) -> PackedByteArray {
        let g = MOVES.read().unwrap();
        let Some(m) = g.as_ref() else { return rg8 };
        let meta = *META.read().unwrap();
        let span = meta.node_pixels as f64 * 2f64.powi(level as i32);
        let upp = span / meta.node_pixels as f64;
        let mut v = rg8.to_vec();
        m.bake_heights(
            &mut v,
            w as usize,
            h as usize,
            |x, y| {
                let tx = i as f64 * span + x as f64 * upp;
                let ty = j as f64 * span + y as f64 * upp;
                [tx * meta.m_per_unit + meta.x_shift, meta.y_shift - ty * meta.m_per_unit]
            },
            |raw| (raw - meta.sea_level_raw) / meta.height_scale * meta.m_per_unit,
            |m_| m_ / meta.m_per_unit * meta.height_scale + meta.sea_level_raw,
        );
        PackedByteArray::from(v)
    }

    /// A colour image of node (level, i, j) (RGB8, w × h pixels over the node) with the old sites painted over and
    /// the new sites' paved surface drawn.
    #[func]
    fn bake_colour(rgb: PackedByteArray, w: i64, h: i64, level: i64, i: i64, j: i64) -> PackedByteArray {
        let g = MOVES.read().unwrap();
        let Some(m) = g.as_ref() else { return rgb };
        let meta = *META.read().unwrap();
        let span = meta.node_pixels as f64 * 2f64.powi(level as i32);
        let upp = span / w.max(1) as f64;
        let mut v = rgb.to_vec();
        m.bake_colour(
            &mut v,
            w as usize,
            h as usize,
            |x, y| {
                let tx = i as f64 * span + (x as f64 + 0.5) * upp;
                let ty = j as f64 * span + (y as f64 + 0.5) * upp;
                [tx * meta.m_per_unit + meta.x_shift, meta.y_shift - ty * meta.m_per_unit]
            },
            upp * meta.m_per_unit,
        );
        PackedByteArray::from(v)
    }
}
