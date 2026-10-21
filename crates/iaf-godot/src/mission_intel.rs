//! `IafMissionEdit`'s intel and randomness calls (`iaf_tools::mission_intel`, docs/mission-editor.md §14, §15), as
//! JSON strings like the rest of the class (`mission_edit.rs`).

use std::sync::OnceLock;

use godot::prelude::*;
use iaf_tools::mission_edit::Issue;
use iaf_tools::mission_intel as mi;
use serde_json::{Value, json};

use crate::mission_edit::{DATA, IafMissionEdit, parse, text};

/// The converted briefings.json, read once.
static BRIEFINGS: OnceLock<Value> = OnceLock::new();

#[godot_api(secondary)]
impl IafMissionEdit {
    /// Entity flag 0x35c (the pre-flight TSD shows the unit) on or off for the entities `ids`.
    #[func]
    fn set_known(mission: GString, ids: PackedInt64Array, known: bool) -> GString {
        text(&mi::set_known(parse(&mission), ids.as_slice(), known))
    }

    /// The model links the mission's unit types can have in its briefing: a JSON array of briefings.json entries
    /// {file, title {en, he}, type 2}.
    #[func]
    fn intel_links(mission: GString) -> GString {
        let mut d = DATA.lock().unwrap();
        d.load();
        let path = d.assets.join("converted/briefings/briefings.json");
        let b = BRIEFINGS.get_or_init(|| {
            std::fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(Value::Null)
        });
        text(&json!(mi::intel_links(&parse(&mission), d.bdb.as_ref().unwrap_or(&Value::Null), b)))
    }

    /// One roll of the random settings `random` (JSON {"<entity id>": {chance, spread_km}}) with `seed`: the mission
    /// as the pilot gets it. Without the converted terrain the mission comes back unrolled.
    #[func]
    fn roll(mission: GString, random: GString, seed: i64) -> GString {
        let mut d = DATA.lock().unwrap();
        d.load();
        let d = &mut *d;
        let (Some(h), Some(bdb)) = (d.heights.as_mut(), d.bdb.as_ref()) else { return mission };
        text(&mi::roll(parse(&mission), &parse(&random), seed as u64, bdb, h, d.types.as_ref()))
    }

    /// The randomness warnings: a JSON array of {id, level, text}.
    #[func]
    fn random_issues(mission: GString, random: GString) -> GString {
        text(&json!(
            mi::random_issues(&parse(&mission), &parse(&random)).iter().map(Issue::to_json).collect::<Vec<_>>()
        ))
    }
}
