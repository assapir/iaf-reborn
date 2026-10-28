//! `IafCityLights`: the city lights at night (iaf_avionics::city_lights, docs/rendering.md §5.1) for
//! `game/terrain/city_lights.gd`, in blocks of 4 × 4 scenery cells (≈ 10 km). One thread of its own reads a block's
//! cell files (the buildings only), places the lights and stands them on the terrain height field.
//!
//! Frames: `blocks_near` takes the engine world frame (X east, Y north); a block's `origin` is its north-west corner,
//! world frame (Z = 0); its points are Godot axes (x east, y up, z south) relative to it, heights absolute.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc::{Sender, channel};
use std::sync::{LazyLock, Mutex};

use godot::prelude::*;
use iaf_avionics::Vec3;
use iaf_avionics::city_lights::{self, Glow};
use iaf_avionics::scenery::Cell;

use crate::scenery::{ground, origin};

/// A block is this many scenery cells on a side.
const BLOCK: i64 = 4;
/// The lights of rank below this make a block's far mesh, drawn to the far range; the rest its near mesh.
const FAR_SHARE: f32 = 0.1;

type Points = (PackedVector3Array, PackedColorArray);

/// A made block: its points (the far ones first), the far ones' count, whether the near ones were asked; None when
/// the terrain under it was not loaded.
type Made = Option<(Vec<[f32; 3]>, Vec<[f32; 4]>, usize, bool)>;

/// A cell file: its path and the seed of its lights.
type CellFile = (PathBuf, u32);

struct State {
    /// Block → its cell files: the scenery's and the city lights' own (where the scenery stops).
    blocks: HashMap<(i64, i64), Vec<CellFile>>,
}

static STATE: LazyLock<Mutex<State>> = LazyLock::new(|| Mutex::new(State { blocks: HashMap::new() }));
static MADE: LazyLock<Mutex<HashMap<(i64, i64), Made>>> = LazyLock::new(Default::default);
/// The towns' glow when made (`glow`).
static GLOW: LazyLock<Mutex<Option<Glow>>> = LazyLock::new(Default::default);
/// The glow's square (m).
const GLOW_M: f64 = 125.0;

/// A job of the lights thread.
enum Job {
    /// A block, with its near points.
    Block((i64, i64), bool),
    /// The towns' glow over every cell.
    Glow,
}
static QUEUE: LazyLock<Mutex<Sender<Job>>> = LazyLock::new(|| {
    let (tx, rx) = channel::<Job>();
    std::thread::spawn(move || {
        while let Ok(job) = rx.recv() {
            match job {
                Job::Block(b, near) => {
                    let made = make(b, near);
                    MADE.lock().unwrap().insert(b, made);
                }
                Job::Glow => *GLOW.lock().unwrap() = Some(glow()),
            }
        }
    });
    Mutex::new(tx)
});

/// Every cell's lights summed per GLOW_M square.
fn glow() -> Glow {
    let (keys, cells): (Vec<(i64, i64)>, Vec<CellFile>) = {
        let s = STATE.lock().unwrap();
        (s.blocks.keys().copied().collect(), s.blocks.values().flatten().cloned().collect())
    };
    let mut b = [f64::MAX, f64::MAX, f64::MIN, f64::MIN];
    for &(bi, bj) in &keys {
        let ([x0, y1], [x1, y0]) = (origin(bi * BLOCK, bj * BLOCK), origin((bi + 1) * BLOCK, (bj + 1) * BLOCK));
        b = [b[0].min(x0), b[1].min(y0), b[2].max(x1), b[3].max(y1)];
    }
    let mut g = Glow::new(if keys.is_empty() { [0.0; 4] } else { b }, GLOW_M);
    for (path, seed) in cells {
        if let Some(bs) = Cell::read_buildings(&path) {
            city_lights::lights(&bs, seed).iter().for_each(|l| g.add(l));
        }
    }
    g
}

/// Every light of the block, far ones (rank < FAR_SHARE) first; the count of far ones. Near false: the far ones only.
fn make(b: (i64, i64), near: bool) -> Made {
    let cells = STATE.lock().unwrap().blocks.get(&b).cloned().unwrap_or_default();
    let o = origin(b.0 * BLOCK, b.1 * BLOCK);
    let (mut far, mut rest) = (Vec::new(), Vec::new());
    for (path, seed) in cells {
        let Some(bs) = Cell::read_buildings(&path) else { continue };
        for l in city_lights::lights(&bs, seed) {
            if !near && l.rank >= FAR_SHARE {
                continue;
            }
            let (x, y) = (l.at[0] as f64, l.at[1] as f64);
            let h = ground(Vec3::new(x, y, 0.0))?;
            let p = [(x - o[0]) as f32, (h + l.up as f64) as f32, -(y - o[1]) as f32];
            let c = [l.color[0], l.color[1], l.color[2], l.rank];
            if l.rank < FAR_SHARE { far.push((p, c)) } else { rest.push((p, c)) }
        }
    }
    let n_far = far.len();
    let (p, c) = far.into_iter().chain(rest).unzip();
    Some((p, c, n_far, near))
}

fn points(p: &[[f32; 3]], c: &[[f32; 4]]) -> Points {
    (
        p.iter().map(|v| Vector3::new(v[0], v[1], v[2])).collect(),
        c.iter().map(|v| Color::from_rgba(v[0], v[1], v[2], v[3])).collect(),
    )
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafCityLights {}

#[godot_api]
impl IafCityLights {
    /// Indexes the cell files under `dir` (`assets/converted/scenery`) by block: the scenery's (`L1`) and the city
    /// lights' own where the scenery stops (`lights/L1`, `iaf-scenery lights`); the number of blocks.
    #[func]
    fn open(dir: GString) -> i64 {
        let dir = PathBuf::from(dir.to_string());
        let mut blocks: HashMap<(i64, i64), Vec<CellFile>> = HashMap::new();
        for (sub, salt) in [("L1", 0u32), ("lights/L1", 0x5bd1_e995)] {
            for e in std::fs::read_dir(dir.join(sub)).into_iter().flatten().flatten() {
                let name = e.file_name().to_string_lossy().into_owned();
                let ij = name.strip_prefix("s_").and_then(|n| n.strip_suffix(".bin")).and_then(|n| n.split_once('_'));
                if let Some((Ok(i), Ok(j))) = ij.map(|(i, j)| (i.parse::<i64>(), j.parse::<i64>())) {
                    let seed = (i as u32).wrapping_mul(7919) ^ j as u32 ^ salt;
                    blocks.entry((i.div_euclid(BLOCK), j.div_euclid(BLOCK))).or_default().push((e.path(), seed));
                }
            }
        }
        let n = blocks.len() as i64;
        *STATE.lock().unwrap() = State { blocks };
        MADE.lock().unwrap().clear();
        *GLOW.lock().unwrap() = None;
        n
    }

    /// The blocks whose square lies within `range` m of the world point (x, y): [bi, bj, distance m] per block.
    #[func]
    fn blocks_near(x: f64, y: f64, range: f64) -> PackedInt32Array {
        let s = STATE.lock().unwrap();
        let mut out = PackedInt32Array::new();
        for &(bi, bj) in s.blocks.keys() {
            let [x0, y1] = origin(bi * BLOCK, bj * BLOCK);
            let [x1, y0] = origin((bi + 1) * BLOCK, (bj + 1) * BLOCK);
            let d = (x - x.clamp(x0, x1)).hypot(y - y.clamp(y0, y1));
            if d <= range {
                out.extend([bi as i32, bj as i32, d as i32]);
            }
        }
        out
    }

    /// Makes the block's lights on the lights thread (`take` hands them over). `near`: the near points too.
    #[func]
    fn request(bi: i64, bj: i64, near: bool) {
        // The thread lives as long as the process (a std thread: nothing for Godot's pool to wait for at quit).
        let _ = QUEUE.lock().unwrap().send(Job::Block((bi, bj), near));
    }

    /// The requested block: {} while it is made; {retry: true} when the terrain under it was not loaded (request
    /// again later); else {origin: Vector3 (world), far: [PackedVector3Array, PackedColorArray], near: [...] (when
    /// asked)}: colour × brightness in RGB, the light's rank in A.
    #[func]
    fn take(bi: i64, bj: i64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(made) = MADE.lock().unwrap().remove(&(bi, bj)) else { return d };
        let Some((p, c, n_far, near)) = made else {
            d.set("retry", true);
            return d;
        };
        let [x, y] = origin(bi * BLOCK, bj * BLOCK);
        d.set("origin", Vector3::new(x as f32, y as f32, 0.0));
        let (fp, fc) = points(&p[..n_far], &c[..n_far]);
        d.set("far", &varray![&fp, &fc]);
        if near {
            let (np, nc) = points(&p[n_far..], &c[n_far..]);
            d.set("near", &varray![&np, &nc]);
        }
        d
    }

    /// Starts making the towns' glow on the lights thread (after the blocks asked so far).
    #[func]
    fn request_glow() {
        let _ = QUEUE.lock().unwrap().send(Job::Glow);
    }

    /// The towns' glow once made, else {}: {bytes: one per square (R8, row 0 north), w, h, x0: west edge, y1: north
    /// edge (world m), m: the square's side}.
    #[func]
    fn glow() -> VarDictionary {
        let mut d = VarDictionary::new();
        if let Some(g) = GLOW.lock().unwrap().as_ref() {
            d.set("bytes", &PackedByteArray::from(g.bytes().as_slice()));
            d.set("w", g.w as i64);
            d.set("h", g.h as i64);
            d.set("x0", g.x0);
            d.set("y1", g.y1);
            d.set("m", g.m);
        }
        d
    }
}
