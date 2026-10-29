//! `IafRoads`: OpenStreetMap's roads and railways of the theatre (iaf_avionics::roads, docs/scenery.md §6), one
//! process-wide store over `assets/converted/roads`: `main.bin` (motorway to secondary, whole theatre) loaded at
//! `open`, the blocks (`L3/r_<i>_<j>.bin`, every class, about 10 km) read when a query needs them. Every point is
//! engine metres, X east / Y north (a Vector2), no height. Classes: `CLASS_*` of iaf_avionics::roads (0 motorway …
//! 7 track, 8 rail); `max_class` keeps that class and the more important ones. A query up to secondary reads
//! `main.bin`; a finer one the blocks.

use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use godot::prelude::*;
use iaf_avionics::roads::*;

/// A block range: its first and last block.
type Blocks = ((i32, i32), (i32, i32));

#[derive(Default)]
struct Store {
    dir: PathBuf,
    main: Option<Arc<Roads>>,
    /// Blocks read (None: no file there), oldest first in `order`.
    blocks: HashMap<(i32, i32), Option<Arc<Roads>>>,
    order: VecDeque<(i32, i32)>,
    /// The last blocks merged (their first and last block) for a route: the mission editor's routes ask again and
    /// again around the same place.
    merged: Option<(Blocks, Arc<Roads>)>,
}

/// Blocks kept in memory (a dense block is about 2 MB on disk).
// ponytail: oldest-first eviction; an LRU if streaming shows re-reads.
const KEEP_BLOCKS: usize = 96;
/// A route on the blocks covers the box of its ends grown by this (m), at most MAX_ROUTE_BLOCKS blocks.
const ROUTE_PAD_M: f64 = 5000.0;
const MAX_ROUTE_BLOCKS: usize = 64;

static STORE: Mutex<Option<Store>> = Mutex::new(None);

fn main() -> Option<Arc<Roads>> {
    STORE.lock().unwrap().as_ref()?.main.clone()
}

/// The blocks meeting the rect, read as needed.
fn blocks(min: [f64; 2], max: [f64; 2]) -> Vec<Arc<Roads>> {
    let mut g = STORE.lock().unwrap();
    let Some(s) = g.as_mut() else { return Vec::new() };
    // Block j grows southwards: the rect's north edge is the least j.
    let (a, b) = (block_of([min[0], max[1]]), block_of([max[0], min[1]]));
    let mut out = Vec::new();
    for j in a.1..=b.1 {
        for i in a.0..=b.0 {
            if !s.blocks.contains_key(&(i, j)) {
                let r = Roads::load(&s.dir.join(format!("L3/r_{i}_{j}.bin"))).map(Arc::new);
                s.blocks.insert((i, j), r);
                s.order.push_back((i, j));
                while s.order.len() > KEEP_BLOCKS {
                    let old = s.order.pop_front().unwrap();
                    s.blocks.remove(&old);
                }
            }
            out.extend(s.blocks[&(i, j)].clone());
        }
    }
    out
}

/// The roads to answer a `max_class` query around the rect: `main.bin`, or the blocks merged.
fn graph_for(min: [f64; 2], max: [f64; 2], max_class: u8) -> Option<Arc<Roads>> {
    if max_class <= MAIN_CLASS {
        return main();
    }
    let (a, b) = (block_of([min[0], max[1]]), block_of([max[0], min[1]]));
    if ((b.0 - a.0 + 1) * (b.1 - a.1 + 1)) as usize > MAX_ROUTE_BLOCKS {
        return None;
    }
    if let Some(m) = STORE.lock().unwrap().as_ref()?.merged.as_ref().filter(|m| m.0 == (a, b)) {
        return Some(m.1.clone());
    }
    let parts = blocks(min, max);
    let r = Arc::new(Roads::merge(&parts.iter().map(Arc::as_ref).collect::<Vec<_>>()));
    STORE.lock().unwrap().as_mut()?.merged = Some(((a, b), r.clone()));
    Some(r)
}

/// The roads for a route from `a` to `b`: around the box of the ends grown by ROUTE_PAD_M (None: too many blocks
/// for a class finer than secondary, or no road data).
pub(crate) fn route_graph(a: [f64; 2], b: [f64; 2], max_class: u8) -> Option<Arc<Roads>> {
    let pad = ROUTE_PAD_M;
    let lo = [a[0].min(b[0]) - pad, a[1].min(b[1]) - pad];
    let hi = [a[0].max(b[0]) + pad, a[1].max(b[1]) + pad];
    graph_for(lo, hi, max_class)
}

fn v2(p: [f64; 2]) -> Vector2 {
    Vector2::new(p[0] as f32, p[1] as f32)
}

fn xy(v: Vector2) -> [f64; 2] {
    [v.x as f64, v.y as f64]
}

fn class(c: i64) -> u8 {
    c.clamp(0, CLASS_RAIL as i64) as u8
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafRoads {}

#[godot_api]
impl IafRoads {
    /// Opens the road folder (`assets/converted/roads`) and reads its `main.bin` once (later calls answer at once);
    /// false when it is missing or unreadable (an older setup): then every query answers empty.
    #[func]
    fn open(dir: GString) -> bool {
        let mut g = STORE.lock().unwrap();
        if g.as_ref().is_some_and(|s| s.main.is_some()) {
            return true;
        }
        let dir = PathBuf::from(dir.to_string());
        let Some(main) = Roads::load(&dir.join("main.bin")) else { return false };
        *g = Some(Store { dir, main: Some(Arc::new(main)), ..Default::default() });
        true
    }

    #[func]
    fn is_open() -> bool {
        main().is_some()
    }

    /// The ways of class `max_class` or more important whose box meets the rect [min, max]. Up to secondary: whole
    /// ways from `main.bin`; finer: the blocks' pieces (a way is cut at each block's edge). Each: `points`
    /// (PackedVector2Array), `class`, `link`, `width` (m), `bridge`, `tunnel`, `layer`, `paved`, `oneway` (points run
    /// in the direction of travel), `lit` (1 yes, 0 no, -1 untagged), `off_ground` (over an airbase, World scale
    /// Real's base sites or the 1998 sea: not for the ground), `osm_id`.
    #[func]
    fn roads_in_rect(min: Vector2, max: Vector2, max_class: i64) -> Array<VarDictionary> {
        let (lo, hi, mc) = (xy(min), xy(max), class(max_class));
        let files = if mc <= MAIN_CLASS { main().into_iter().collect() } else { blocks(lo, hi) };
        let mut out = Array::new();
        for r in &files {
            for k in r.in_rect(lo, hi, mc) {
                let w = &r.ways[k as usize];
                let f = |b: u8| w.flags & b != 0;
                let lit = if f(FLAG_LIT) {
                    1
                } else if f(FLAG_UNLIT) {
                    0
                } else {
                    -1
                };
                let pts: PackedVector2Array = r.way_points(k).map(v2).collect();
                out.push(&vdict! {
                    "points" => &pts, "class" => w.class as i64, "link" => f(FLAG_LINK), "width" => w.width,
                    "bridge" => f(FLAG_BRIDGE), "tunnel" => f(FLAG_TUNNEL), "layer" => w.layer as i64,
                    "paved" => !f(FLAG_UNPAVED), "oneway" => f(FLAG_ONEWAY), "lit" => lit,
                    "off_ground" => f(FLAG_OFF_GROUND), "osm_id" => w.osm_id as i64,
                });
            }
        }
        out
    }

    /// Every segment of `main.bin`'s classes `min_class..=max_class` as point pairs (for a PRIMITIVE_LINES mesh).
    #[func]
    fn segments(min_class: i64, max_class: i64) -> PackedVector2Array {
        let Some(r) = main() else { return PackedVector2Array::new() };
        let mut out = Vec::new();
        for k in 0..r.ways.len() as u32 {
            if (min_class..=max_class).contains(&(r.ways[k as usize].class as i64)) {
                for s in r.way_index(k).windows(2) {
                    out.push(v2(r.point(s[0])));
                    out.push(v2(r.point(s[1])));
                }
            }
        }
        PackedVector2Array::from(out.as_slice())
    }

    /// The nearest point within 10 km on a road of class `max_class` or more important (railways left out):
    /// `point`, `distance` (m), `class`, `osm_id`; empty without one.
    #[func]
    fn nearest(p: Vector2, max_class: i64) -> VarDictionary {
        let (p, pad) = (xy(p), 10_000.0);
        let Some(r) = graph_for([p[0] - pad, p[1] - pad], [p[0] + pad, p[1] + pad], class(max_class)) else {
            return VarDictionary::new();
        };
        r.nearest(p, class(max_class)).filter(|n| n.dist <= pad).map_or_else(VarDictionary::new, |n| {
            let w = &r.ways[n.way as usize];
            vdict! {"point" => v2(n.point), "distance" => n.dist, "class" => w.class as i64, "osm_id" => w.osm_id as i64}
        })
    }

    /// The shortest road route (classes up to `max_class`, oneway ignored) from the road point nearest `a` to the one
    /// nearest `b`: the snapped start, the junctions and bends, the snapped end; empty when not connected (a finer
    /// class than secondary searches only the box of the ends grown by 5 km, at most 64 blocks, about 80 km square).
    #[func]
    fn route(a: Vector2, b: Vector2, max_class: i64) -> PackedVector2Array {
        let (a, b) = (xy(a), xy(b));
        let Some(r) = route_graph(a, b, class(max_class)) else { return PackedVector2Array::new() };
        r.route(a, b, class(max_class)).into_iter().flatten().map(v2).collect()
    }
}
