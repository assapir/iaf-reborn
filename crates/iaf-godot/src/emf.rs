//! `IafEmf`: the TSD map's polygon fill (`iaf_formats::emf::fill_triangles`) for `menu/tsd_map.gd`.

use godot::prelude::*;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafEmf {}

#[godot_api]
impl IafEmf {
    /// The triangles GDI's polygon fill covers: `rings` as one region under ALTERNATE (`alternate`) or WINDING.
    #[func]
    fn fill_triangles(rings: Array<PackedVector2Array>, alternate: bool) -> PackedVector2Array {
        let rings: Vec<Vec<[f32; 2]>> =
            rings.iter_shared().map(|r| r.as_slice().iter().map(|p| [p.x, p.y]).collect()).collect();
        iaf_formats::emf::fill_triangles(&rings, alternate).into_iter().map(|p| Vector2::new(p[0], p[1])).collect()
    }
}
