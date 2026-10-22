//! `IafScenery`: the buildings and trees over the Survey of Israel 2 m photo (iaf_avionics::scenery,
//! docs/scenery.md §2), one process-wide store `game/terrain/scenery.gd` loads cells into. `world::terrain` adds its
//! tops to `mission_ground`, so every Rust weapon / sensor sees roofs and trees.
//!
//! Frames: `cell_origin` and every point passed in are the engine world frame (X east, Y north, Z up); mesh vertices
//! and tree transforms are Godot axes (x east, y up, z south) relative to `cell_origin`, heights absolute.

use std::collections::{HashMap, VecDeque};
use std::sync::{LazyLock, Mutex, RwLock};

use godot::classes::mesh::ArrayType;
use godot::prelude::*;
use iaf_avionics::Vec3;
use iaf_avionics::scenery::{self, Cell, Mesh, Scenery};

use crate::heights::FIELD;
use crate::world::vec3;

pub static SCENERY: LazyLock<RwLock<Scenery>> = LazyLock::new(Default::default);

/// A cell's meshes and trees made off the main thread (`prepare`), handed over one piece per call (`take_next`):
/// None when the terrain under it was not loaded.
enum Piece {
    Near(Mesh),
    Far(Mesh),
    Trees(Vec<(scenery::TreeKind, Vec<f32>)>),
}
type Built = Option<VecDeque<Piece>>;

/// The side (m) of the tiles a cell's buildings and trees are drawn in: Godot culls each tile by its own distance, not
/// the whole cell's; the shaders then cut each building or tree by its own (scenery.gd).
const TILE_M: f64 = 500.0;

/// Vertices per uploaded mesh: a dense cell reaches the GPU over several frames.
const CHUNK_VERTICES: usize = 60_000;
static BUILT: LazyLock<Mutex<HashMap<(i64, i64), Built>>> = LazyLock::new(Default::default);

fn build(i: i64, j: i64, modern: bool) -> Built {
    // A copy: holding the store's read lock through the build would stall the main thread's drop_cell (a write).
    let c = SCENERY.read().unwrap().cell(i, j)?.clone();
    let (c, o) = (&c, origin(i, j));
    let near = scenery::mesh_chunks(c, o, true, modern, &ground, TILE_M, CHUNK_VERTICES)?;
    let far = scenery::mesh_chunks(c, o, false, modern, &ground, TILE_M, CHUNK_VERTICES)?;
    let trees = scenery::tree_tiles(c, o, TILE_M as f32, &ground)?;
    let mut q: VecDeque<Piece> = near.into_iter().map(Piece::Near).chain(far.into_iter().map(Piece::Far)).collect();
    q.push_back(Piece::Trees(trees));
    Some(q)
}

fn arrays(m: &Mesh) -> VarArray {
    if m.index.is_empty() {
        return VarArray::new();
    }
    let mut a: Vec<Variant> = vec![Variant::nil(); ArrayType::MAX.ord() as usize];
    a[ArrayType::VERTEX.ord() as usize] = v3(&m.vertex).to_variant();
    a[ArrayType::NORMAL.ord() as usize] = v3(&m.normal).to_variant();
    a[ArrayType::TEX_UV.ord() as usize] = v2(&m.uv).to_variant();
    a[ArrayType::TEX_UV2.ord() as usize] = v2(&m.uv2).to_variant();
    let colors: PackedColorArray = m.color.iter().map(|c| Color::from_rgba(c[0], c[1], c[2], c[3])).collect();
    a[ArrayType::COLOR.ord() as usize] = colors.to_variant();
    let custom: PackedFloat32Array = m.custom0.iter().flatten().copied().collect();
    a[ArrayType::CUSTOM0.ord() as usize] = custom.to_variant();
    a[ArrayType::INDEX.ord() as usize] = PackedInt32Array::from(m.index.as_slice()).to_variant();
    a.into_iter().collect()
}

fn tree_dict(rows: &[Vec<f32>; 4]) -> VarDictionary {
    let mut d = VarDictionary::new();
    for (k, r) in rows.iter().enumerate().filter(|(_, r)| !r.is_empty()) {
        d.set(k as i64, &PackedFloat32Array::from(r.as_slice()).to_variant());
    }
    d
}

fn ground(p: Vec3) -> Option<f64> {
    FIELD.read().unwrap().height(p)
}

/// The world (X, Y) of a level-1 node's north-west corner (terrain meta: level 0 spans node_pixels units).
fn origin(i: i64, j: i64) -> [f64; 2] {
    let m = FIELD.read().unwrap().meta();
    let span = 2.0 * m.node_pixels as f64;
    [i as f64 * span * m.m_per_unit + m.x_shift, m.y_shift - j as f64 * span * m.m_per_unit]
}

fn v3(v: &[[f32; 3]]) -> PackedVector3Array {
    v.iter().map(|p| Vector3::new(p[0], p[1], p[2])).collect()
}

fn v2(v: &[[f32; 2]]) -> PackedVector2Array {
    v.iter().map(|p| Vector2::new(p[0], p[1])).collect()
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafScenery {}

#[godot_api]
impl IafScenery {
    /// Reads a cell file (`assets/converted/scenery/L1/s_<i>_<j>.bin`); false when it is missing or unreadable.
    #[func]
    fn load_cell(path: GString, i: i64, j: i64) -> bool {
        let Some(cell) = std::fs::read(path.to_string()).ok().and_then(|d| Cell::decode(&d)) else { return false };
        SCENERY.write().unwrap().insert(i, j, cell);
        true
    }

    #[func]
    fn drop_cell(i: i64, j: i64) {
        SCENERY.write().unwrap().remove(i, j);
        BUILT.lock().unwrap().remove(&(i, j));
    }

    /// The cell's mesh origin, world frame (Z = 0); needs `IafHeights.set_meta` first.
    #[func]
    fn cell_origin(i: i64, j: i64) -> Vector3 {
        let [x, y] = origin(i, j);
        Vector3::new(x as f32, y as f32, 0.0)
    }

    /// Starts making the cell's meshes and trees on a thread of its own (the main thread only copies them out);
    /// `prepared` tells when they are done.
    #[func]
    fn prepare(i: i64, j: i64, modern: bool) {
        std::thread::spawn(move || {
            let b = build(i, j, modern);
            // A cell dropped meanwhile keeps nothing.
            if SCENERY.read().unwrap().cell(i, j).is_some() {
                BUILT.lock().unwrap().insert((i, j), b);
            }
        });
    }

    /// 1 when `prepare` finished the cell (pieces wait in `take_next`), −1 when it could not (the terrain under it not
    /// loaded yet: prepare again), 0 while it runs. A −1 is reported once.
    #[func]
    fn prepared(i: i64, j: i64) -> i64 {
        let mut built = BUILT.lock().unwrap();
        match built.get(&(i, j)) {
            None => 0,
            Some(Some(_)) => 1,
            Some(None) => {
                built.remove(&(i, j));
                -1
            }
        }
    }

    /// The prepared cell's next piece, {} when none is left: {near: true, arrays} or {near: false, arrays} (a chunk of
    /// the near / far buildings for `ArrayMesh.add_surface_from_arrays`, Mesh.ARRAY_MAX arrays: VERTEX, NORMAL, COLOR,
    /// TEX_UV, TEX_UV2, CUSTOM0 (RGBA float: the building's centre at its base), INDEX; one `TILE_M` tile, at most
    /// `CHUNK_VERTICES`), or {trees: [[kind (TreeKind as int), PackedFloat32Array of
    /// TRANSFORM_3D rows, 12 floats each, for a 10 m model] per `TILE_M` tile and kind]}. Near = parapets, gabled
    /// and dome roofs; far = bare prisms.
    #[func]
    fn take_next(i: i64, j: i64) -> VarDictionary {
        let mut built = BUILT.lock().unwrap();
        let mut d = VarDictionary::new();
        let Some(Some(q)) = built.get_mut(&(i, j)) else { return d };
        loop {
            match q.pop_front() {
                None => {
                    built.remove(&(i, j));
                    return d;
                }
                Some(Piece::Near(m) | Piece::Far(m)) if m.index.is_empty() => continue,
                Some(Piece::Near(m)) => {
                    d.set("near", true);
                    d.set("arrays", &arrays(&m));
                }
                Some(Piece::Far(m)) => {
                    d.set("near", false);
                    d.set("arrays", &arrays(&m));
                }
                Some(Piece::Trees(t)) => {
                    let tiles: VarArray = t
                        .iter()
                        .map(|(k, r)| varray![*k as i64, &PackedFloat32Array::from(r.as_slice())].to_variant())
                        .collect();
                    d.set("trees", &tiles);
                }
            }
            return d;
        }
    }

    /// The cell's buildings, made on the calling thread (`prepare` / `take_next` for the streamed cells).
    #[func]
    fn mesh_arrays(i: i64, j: i64, near: bool, modern: bool) -> VarArray {
        let s = SCENERY.read().unwrap();
        s.cell(i, j)
            .and_then(|c| scenery::mesh(c, origin(i, j), near, modern, &ground))
            .map_or_else(VarArray::new, |m| arrays(&m))
    }

    /// The cell's trees, made on the calling thread.
    #[func]
    fn trees(i: i64, j: i64) -> VarDictionary {
        let s = SCENERY.read().unwrap();
        s.cell(i, j)
            .and_then(|c| scenery::tree_rows(c, origin(i, j), &ground))
            .map_or_else(VarDictionary::new, |r| tree_dict(&r))
    }

    /// The scenery's height above ground (m) at a world point; 0 where none stands.
    #[func]
    fn top(w: Vector3) -> f64 {
        SCENERY.read().unwrap().top(w.x.into(), w.y.into(), &ground)
    }

    /// The distance along a world-frame ray to the first building or tree within `max`, −1 for none.
    #[func]
    fn ray(from: Vector3, dir: Vector3, max: f64) -> f64 {
        SCENERY.read().unwrap().ray(vec3(from), vec3(dir), max, &ground).unwrap_or(-1.0)
    }

    /// The building nearest a world point (X, Y) within `r` m: {id, centroid (Vector2 world), height, area}, or {}.
    #[func]
    fn nearest(x: f64, y: f64, r: f64) -> VarDictionary {
        SCENERY.read().unwrap().nearest(x, y, r).map_or_else(VarDictionary::new, |f| {
            vdict! {
                "id" => f.id.as_str(),
                "centroid" => Vector2::new(f.centroid[0] as f32, f.centroid[1] as f32),
                "height" => f.height,
                "area" => f.area,
            }
        })
    }

    #[func]
    fn count_within(x: f64, y: f64, r: f64) -> i64 {
        SCENERY.read().unwrap().count_within(x, y, r) as i64
    }

    /// Marks a building ("<i>_<j>:<index>") damaged or whole; kept across cell loads.
    #[func]
    fn set_damaged(id: GString, damaged: bool) {
        SCENERY.write().unwrap().set_damaged(&id.to_string(), damaged);
    }

    /// A bomb's, missile's or rocket's blast of radius `r` at a world point (docs/scenery.md §4): damages the building
    /// it meets and returns its id, "" for none.
    #[func]
    fn blast(w: Vector3, r: f64) -> GString {
        GString::from(SCENERY.write().unwrap().blast(vec3(w), r, &ground).unwrap_or_default().as_str())
    }

    #[func]
    fn is_damaged(id: GString) -> bool {
        SCENERY.read().unwrap().is_damaged(&id.to_string())
    }

    /// One byte per building of a loaded cell, 1 = damaged (UV2.x indexes it).
    #[func]
    fn damage_index(i: i64, j: i64) -> PackedByteArray {
        PackedByteArray::from(SCENERY.read().unwrap().damage_index(i, j).as_slice())
    }
}
