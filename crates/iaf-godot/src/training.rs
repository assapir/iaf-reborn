//! `IafTraining`: IAF 2026's training scorer (`iaf_tools::training`, iaf-2026/docs/training.md) for the game, run at a
//! training mission's end on the flight's recording.

use godot::prelude::*;
use std::path::Path;

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafTraining {}

#[godot_api]
impl IafTraining {
    /// The debrief record (training.md §4) of the recording `flight` against the readable mission file `mission`
    /// with the airbase files in `airbases` (absolute paths), as JSON text; `{"error": …}` when it cannot be scored.
    #[func]
    fn score(flight: GString, mission: GString, airbases: GString) -> GString {
        let p = |s: &GString| s.to_string();
        let out = match iaf_tools::training::score_files(
            Path::new(&p(&flight)),
            Path::new(&p(&mission)),
            Path::new(&p(&airbases)),
        ) {
            Ok(d) => d.to_json(),
            Err(e) => serde_json::json!({ "error": format!("{e:#}") }),
        };
        GString::from(out.to_string().as_str())
    }
}
