//! `IafSurface`: terraintype.dat's surface flags (iaf_formats::terrain_types) rasterised around the camera for the
//! terrain shader (`terrain/render_options.gd`: the close up's airbases, the water's inland water).

use std::sync::{LazyLock, RwLock};

use godot::prelude::*;
use iaf_formats::terrain_types::{RUNWAY, TerrainTypes};

/// One tree for the process: the theatre's terraintype.dat.
static TYPES: LazyLock<RwLock<Option<TerrainTypes>>> = LazyLock::new(Default::default);

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafSurface {}

#[godot_api]
impl IafSurface {
    /// Reads terraintype.dat; false when it is missing or bad (the raster is then all land).
    #[func]
    fn load(path: GString) -> bool {
        let t = std::fs::read(path.to_string()).ok().and_then(|d| TerrainTypes::parse(&d).ok());
        let ok = t.is_some();
        *TYPES.write().unwrap() = t;
        ok
    }

    /// An `n` × `n` RG8 image of `cell` m texels whose (0, 0) texel's north-west corner is at engine metres (x0, y0),
    /// rows running south: R = water (islands excluded), G = airbase (runway flag).
    #[func]
    fn raster_rg8(x0: f64, y0: f64, cell: f64, n: i64) -> PackedByteArray {
        let n = n.max(0) as usize;
        let Some(t) = &*TYPES.read().unwrap() else {
            return PackedByteArray::from(vec![0u8; 2 * n * n]);
        };
        let px = |m: i32| [if TerrainTypes::is_water(m) { 255 } else { 0 }, if m & RUNWAY != 0 { 255 } else { 0 }];
        PackedByteArray::from(t.raster(x0, y0, cell, n).into_iter().flat_map(px).collect::<Vec<u8>>())
    }
}
