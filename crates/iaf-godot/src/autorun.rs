//! `IafAutorun`: the CD launcher's data files for `menu/autorun.gd` (docs/front-end.md §18.1): the named rectangles
//! of a `.rgn` file (iaf_formats::rgn) and the startup sound inside Jauto.exe (iaf_formats::pe).

use godot::prelude::*;
use iaf_formats::{pe, rgn};

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafAutorun {}

#[godot_api]
impl IafAutorun {
    /// {name: Rect2i} of a `.rgn` file; empty when it is missing or bad.
    #[func]
    fn rects(path: GString) -> Dictionary<GString, Rect2i> {
        let mut d = Dictionary::new();
        let rects = std::fs::read(path.to_string()).ok().and_then(|b| rgn::parse(&b).ok()).unwrap_or_default();
        for r in rects {
            d.set(&GString::from(r.name.as_str()), Rect2i::new(Vector2i::new(r.left, r.top), Vector2i::new(r.right - r.left, r.bottom - r.top)));
        }
        d
    }

    /// The bytes of a RIFF WAVE resource `id` (type "WAVE") in a PE file; empty when there is none.
    #[func]
    fn wave(exe_path: GString, id: i64) -> PackedByteArray {
        let Ok(data) = std::fs::read(exe_path.to_string()) else { return PackedByteArray::new() };
        match pe::resource(&data, pe::ResType::Name("WAVE"), id as u32) {
            Ok(Some(w)) => PackedByteArray::from(w),
            _ => PackedByteArray::new(),
        }
    }
}
