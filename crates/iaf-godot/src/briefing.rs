//! `IafBriefing`: Modern IAF's mission briefing map (`iaf_tools::briefing`, modern-iaf/docs/front-end.md §10) for the
//! Pick a mission screen (`menu/briefing_map.gd` draws it).

use godot::prelude::*;
use iaf_tools::briefing;
use std::path::Path;

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafBriefing {}

#[godot_api]
impl IafBriefing {
    /// The map of the readable mission file `mission` over the airbase files in `airbases`, the compiled TSD map
    /// `map` and the theatre's folder `theatre` (roads, towns; absolute paths), `aspect` = its width / height on
    /// screen, as JSON text (`Briefing::to_json`); `{"error": …}` when
    /// it cannot be made.
    #[func]
    fn map(mission: GString, airbases: GString, map: GString, theatre: GString, aspect: f64) -> GString {
        let p = |s: &GString| s.to_string();
        let out = match briefing::briefing_files(
            Path::new(&p(&mission)),
            Path::new(&p(&airbases)),
            Path::new(&p(&map)),
            Path::new(&p(&theatre)),
            aspect,
        ) {
            Ok(b) => b.to_json(),
            Err(e) => serde_json::json!({ "error": format!("{e:#}") }),
        };
        GString::from(out.to_string().as_str())
    }

    /// The theatre's ground colour (`briefing::ground`) over `extent` [x0, y0, x1, y1] (UTM metres), `width` px
    /// wide: {w, h, rgb (RGB8)}, {} without the theatre.
    #[func]
    fn ground(theatre: GString, extent: PackedFloat64Array, width: i64) -> VarDictionary {
        let e = extent.as_slice();
        if e.len() != 4 {
            return VarDictionary::new();
        }
        match briefing::ground(Path::new(&theatre.to_string()), [e[0], e[1], e[2], e[3]], width.max(1) as u32) {
            Some((w, h, rgb)) => {
                let mut d = vdict! { "w" => w as i64, "h" => h as i64 };
                d.set("rgb", &PackedByteArray::from(rgb));
                d
            }
            None => VarDictionary::new(),
        }
    }

    /// The Arming page of the unit record `unit` with the weapon records in `weapons` (absolute paths;
    /// `briefing::arming`) as JSON text, `{}` when the record is unreadable.
    #[func]
    fn arming(unit: GString, weapons: GString) -> GString {
        let v = std::fs::read(unit.to_string())
            .ok()
            .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
            .map_or(serde_json::json!({}), |u| briefing::arming(&u, Path::new(&weapons.to_string())));
        GString::from(v.to_string().as_str())
    }
}
