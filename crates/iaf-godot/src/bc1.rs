//! `IafImage`: the BC1 encoder an exported Godot game lacks (Image.compress has none in the export templates), for
//! the release bundles (docs/release.md); shared/util/img.gd `compress_bc1` calls it there.

use godot::prelude::*;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafImage {}

#[godot_api]
impl IafImage {
    /// An RGBA8 Image's data (`width`×`height`, then its mip levels when `mipmaps`) as BC1 (DXT1) with the same
    /// levels (iaf_tools::bc1::godot_image). Thread-safe: the terrain's decode workers call it.
    #[func]
    fn bc1(rgba: PackedByteArray, width: i64, height: i64, mipmaps: bool) -> PackedByteArray {
        let out = iaf_tools::bc1::godot_image(rgba.as_slice(), width.max(1) as usize, height.max(1) as usize, mipmaps);
        PackedByteArray::from(out.as_slice())
    }
}
