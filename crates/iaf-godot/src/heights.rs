//! `IafHeights`: the terrain height field (iaf_avionics::heights) `terrain.gd` feeds with its full-detail height nodes,
//! read by every `world::terrain` lookup of `mission_ground` without a call back into GDScript.

use std::sync::{LazyLock, RwLock};

use godot::prelude::*;
use iaf_avionics::heights::{HeightField, Meta};

use crate::world::{num, vec3};

/// One field for the process: the terrain is the same data whichever instance streams it.
pub static FIELD: LazyLock<RwLock<HeightField>> = LazyLock::new(Default::default);

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafHeights {}

#[godot_api]
impl IafHeights {
    /// {node_pixels, span, sea_level_raw, height_scale, m_per_unit, x_shift, y_shift} (terrain.gd).
    #[func]
    fn set_meta(m: VarDictionary) {
        let f = |k: &str| num(&m, k).unwrap_or(0.0);
        FIELD.write().unwrap().set_meta(Meta {
            node_pixels: f("node_pixels") as usize,
            span: f("span"),
            sea_level_raw: f("sea_level_raw"),
            height_scale: f("height_scale"),
            m_per_unit: f("m_per_unit"),
            x_shift: f("x_shift"),
            y_shift: f("y_shift"),
        });
    }

    /// A height node's RG8 image bytes, loaded by a terrain instance.
    #[func]
    fn add(i: i64, j: i64, width: i64, rg8: PackedByteArray) {
        FIELD.write().unwrap().add(i, j, width as usize, rg8.as_slice());
    }

    #[func]
    fn remove(i: i64, j: i64) {
        FIELD.write().unwrap().remove(i, j);
    }

    /// The height at a world point (X east, Y north), null where no node is loaded.
    #[func]
    fn height(w: Vector3) -> Variant {
        FIELD.read().unwrap().height(vec3(w)).map_or(Variant::nil(), |h| h.to_variant())
    }
}
