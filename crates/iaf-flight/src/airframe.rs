//! Ours: the aircraft definitions of the modern jets (docs/adding-a-plane.md "Modern planes"). Each is one
//! `game/extra/planes/<id>/airframe.json`, built into the crate. A definition may name a `base`: it is then a JSON
//! Merge Patch (RFC 7386) on that base, holding only what differs (an object merges key by key, `null` removes a key,
//! any other value replaces). The 1998 type codes reach a definition through [`id_for`]; a 1998 jet without one keeps
//! its type-code tables. The resolved definition is read into [`Airframe`], which rejects an unknown field or a wrong
//! type: a new field means adding it there.

use std::collections::BTreeMap;
use std::sync::LazyLock;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// A resolved aircraft definition (docs/adding-a-plane.md "Modern planes": what each field decides and who reads it).
/// Every field is optional: a reader without it falls back to the 1998 type-code table.
#[derive(Clone, Debug, Default, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Airframe {
    /// The definition this one patches (in the file only: none once resolved).
    pub base: Option<String>,
    pub name: Option<String>,
    pub doc: Option<String>,
    pub label: Option<String>,
    pub info_tag: Option<String>,
    pub jet_list: Option<JetList>,
    pub flyable: Option<bool>,
    pub cockpit: Option<String>,
    pub hud: Option<String>,
    pub fm: Option<String>,
    pub original_model: Option<String>,
    pub model: Option<String>,
    pub voice: Option<Voice>,
    pub radar: Option<Radar>,
    pub gun_rounds: Option<u32>,
    pub flir: Option<bool>,
    pub weapons: Option<Weapons>,
    pub hud_3d: Option<String>,
    /// The 3D cockpit's model (Extras "Cockpit": 3D; docs/cockpit.md "3D cockpit").
    pub cockpit_3d: Option<String>,
    pub mfd: Option<String>,
    /// The fly-by-wire flight controls: the roll-rate command and the deep stall in place of the spin (aircraft.rs).
    pub fly_by_wire: Option<bool>,
    /// The engine's spool times in seconds, `[idle_mil, mil_idle, ab_light, ab_fill]` (spool.rs `Spool`).
    pub engine_spool: Option<[f32; 4]>,
    /// The night-vision goggles' tube whatever the year (terrain_view.gd `TUBES`), its cockpit lit for them.
    pub goggles: Option<String>,
    pub guide: Option<String>,
    /// Each value's source, by field (`"radar.km"`); read by no code.
    pub notes: Option<BTreeMap<String, String>>,
}

/// `jet_list`: the Jet list button, row and description.
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct JetList {
    pub title: String,
    pub title_he: Option<String>,
    pub row_he: Option<String>,
    pub desc: String,
}

/// `voice`: the voice warnings and the Real HUD's calls.
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Voice {
    pub betty: Option<bool>,
    pub real: Option<String>,
}

/// `radar`: the radar table row, the Real range (km), the AI's sensor range (NM).
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Radar {
    pub row: Option<u32>,
    pub km: Option<f64>,
    pub ai_nm: Option<f64>,
}

/// `weapons`: the Arming art, the modern weapons ("always"), and their stations: record id -> (count, stations A..I).
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Weapons {
    pub arm_art: Option<String>,
    pub modern: Option<String>,
    pub loads: Option<BTreeMap<u32, (u32, String)>>,
}

impl Airframe {
    /// As JSON, without the fields it lacks (what GDScript gets as a Dictionary).
    pub fn to_value(&self) -> Value {
        let mut v = serde_json::to_value(self).expect("an Airframe is JSON");
        strip_nulls(&mut v);
        v
    }
}

fn strip_nulls(v: &mut Value) {
    if let Value::Object(m) = v {
        m.retain(|_, x| !x.is_null());
        m.values_mut().for_each(strip_nulls);
    }
}

/// Every definition: its id (the folder) and the file's text.
const FILES: &[(&str, &str)] = &[
    ("f15", include_str!("../../../game/extra/planes/f15/airframe.json")),
    ("f15i", include_str!("../../../game/extra/planes/f15i/airframe.json")),
    ("f16", include_str!("../../../game/extra/planes/f16/airframe.json")),
    ("f16i", include_str!("../../../game/extra/planes/f16i/airframe.json")),
    ("f35i", include_str!("../../../game/extra/planes/f35i/airframe.json")),
];

/// The Extras switches that pick a 1998 jet's variant (Settings `f16_variant`, `f15_variant`).
#[derive(Clone, Copy, Debug, Default)]
pub struct Switches<'a> {
    pub f16: &'a str,
    pub f15: &'a str,
}

/// The adapter: the definition a jet of bdb type `type_code` flies as with the Extras switches `s`, None for a 1998
/// jet without one (its tables decide). The F-16 (100): its base `f16` (the Barak), the F-16I `f16i` on Sufa; the F-15
/// (110): its base `f15` (the Baz), the F-15I `f15i` on Ra'am.
pub fn id_for(type_code: i64, s: Switches) -> Option<&'static str> {
    match type_code {
        100 => Some(if s.f16 == "sufa" { "f16i" } else { "f16" }),
        110 => Some(if s.f15 == "raam" { "f15i" } else { "f15" }),
        1000 => Some("f35i"),
        _ => None,
    }
}

/// The resolved definition `id` (its base merged in), None for an unknown id.
pub fn get(id: &str) -> Option<&'static Airframe> {
    RESOLVED.get(id)
}

/// The definition of a jet the flight model flies by type code alone: the switches off (the F-16 and F-15 their 1998
/// bases, which hold no flight-model field; the F-35I its own).
pub fn of_fm_type(type_code: u32) -> Option<&'static Airframe> {
    of_type(type_code as i64, Switches::default())
}

/// Every definition id with its resolved definition.
pub fn all() -> impl Iterator<Item = (&'static str, &'static Airframe)> {
    RESOLVED.iter().map(|(k, v)| (*k, v))
}

/// The resolved definition of a jet (the adapter, then [`get`]).
pub fn of_type(type_code: i64, s: Switches) -> Option<&'static Airframe> {
    get(id_for(type_code, s)?)
}

/// The model drawn in place of the 1998 model file `file` (e.g. "f16_h.gltf"): the `model` of the definition the
/// switches `s` pick for the jet whose `original_model` it is; None to keep the original's.
pub fn model_for(file: &str, s: Switches) -> Option<&'static str> {
    [100, 110, 1000]
        .into_iter()
        .filter_map(|code| of_type(code, s))
        .find(|a| a.original_model.as_deref() == Some(file))?
        .model
        .as_deref()
}

static RESOLVED: LazyLock<BTreeMap<&'static str, Airframe>> = LazyLock::new(|| {
    let raw: BTreeMap<&str, Value> = FILES
        .iter()
        .map(|&(id, text)| (id, serde_json::from_str(text).unwrap_or_else(|e| panic!("{id}/airframe.json: {e}"))))
        .collect();
    raw.keys().map(|&id| (id, parse(id, &resolve(&raw, id, 0)).unwrap_or_else(|e| panic!("{e}")))).collect()
});

/// The resolved definition `v` of `id` as an [`Airframe`]; an unknown field or a wrong type is an error naming the
/// file and the line of the resolved definition that holds it.
fn parse(id: &str, v: &Value) -> Result<Airframe, String> {
    let text = serde_json::to_string_pretty(v).expect("a Value is JSON");
    serde_json::from_str(&text).map_err(|e| {
        let line = text.lines().nth(e.line().saturating_sub(1)).unwrap_or_default().trim();
        format!("game/extra/planes/{id}/airframe.json (base merged in): {e}: {line}")
    })
}

/// `id` with its bases merged in (at most 8 deep: a loop of bases stops there).
fn resolve(raw: &BTreeMap<&str, Value>, id: &str, depth: usize) -> Value {
    let Some(own) = raw.get(id) else { return Value::Object(Default::default()) };
    let mut out = match own.get("base").and_then(Value::as_str) {
        Some(b) if depth < 8 => resolve(raw, b, depth + 1),
        _ => Value::Object(Default::default()),
    };
    merge(&mut out, own);
    if let Value::Object(m) = &mut out {
        m.remove("base");
    }
    out
}

/// RFC 7386 JSON Merge Patch: `patch` onto `target`.
fn merge(target: &mut Value, patch: &Value) {
    let Value::Object(p) = patch else {
        *target = patch.clone();
        return;
    };
    if !target.is_object() {
        *target = Value::Object(Default::default());
    }
    let Value::Object(t) = target else { return };
    for (k, v) in p {
        if v.is_null() {
            t.remove(k);
        } else {
            merge(t.entry(k.clone()).or_insert(Value::Null), v);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_variant_holds_only_what_differs_from_its_base() {
        let raw: BTreeMap<&str, Value> = [
            ("fam", json!({"radar": {"row": 1, "km": 80.0}, "hud": "std", "panels": "a.webp"})),
            ("var", json!({"base": "fam", "radar": {"km": 104.0}, "hud": "wide", "panels": null})),
            ("loop", json!({"base": "loop", "x": 1})),
        ]
        .into_iter()
        .collect();
        assert_eq!(resolve(&raw, "var", 0), json!({"radar": {"row": 1, "km": 104.0}, "hud": "wide"}));
        assert_eq!(resolve(&raw, "fam", 0)["panels"], "a.webp");
        assert_eq!(resolve(&raw, "loop", 0), json!({"x": 1}));
    }

    #[test]
    fn every_file_parses_and_its_base_exists() {
        for &(id, text) in FILES {
            let v: Value = serde_json::from_str(text).unwrap();
            if let Some(b) = v.get("base").and_then(Value::as_str) {
                assert!(get(b).is_some(), "{id}: base {b}");
            }
            assert!(get(id).is_some(), "{id}");
        }
    }

    /// A misspelt or wrongly typed field fails, naming the file and the field.
    #[test]
    fn a_typo_names_the_file_and_field() {
        let e = parse("x", &json!({"name": "X", "radar": {"row": 1, "kms": 9.0}})).unwrap_err();
        assert!(e.contains("x/airframe.json") && e.contains("kms"), "{e}");
        let e = parse("x", &json!({"radar": {"km": "far"}})).unwrap_err();
        assert!(e.contains("\"km\": \"far\""), "{e}");
        let e = parse("x", &json!({"jet_list": {"title": "X"}})).unwrap_err();
        assert!(e.contains("desc"), "{e}");
        assert!(parse("x", &json!({"weapons": {"loads": {"10x1": [1, "A"]}}})).is_err());
    }

    #[test]
    fn the_adapter() {
        let off = Switches { f16: "barak", f15: "baz" };
        assert_eq!(id_for(1000, off), Some("f35i"));
        assert_eq!(id_for(100, off), Some("f16"));
        assert_eq!(id_for(100, Switches { f16: "sufa", f15: "baz" }), Some("f16i"));
        assert_eq!(id_for(100, Switches { f16: "junk", f15: "" }), Some("f16"));
        assert_eq!(id_for(110, off), Some("f15"));
        assert_eq!(id_for(110, Switches { f16: "barak", f15: "raam" }), Some("f15i"));
        // Every other 1998 jet has no definition: its tables decide.
        for code in [120, 130, 140, 150, 160, 170, 180, 190, 200, 210, 220, 230] {
            assert_eq!(id_for(code, off), None, "{code}");
        }
        assert_eq!(of_type(1000, off).and_then(|a| a.radar.as_ref()?.km), Some(148.0));
    }

    /// With every switch off a 1998 jet's definition holds no value its type-code tables decide, so the game reads
    /// exactly the 1998 values; only what the original has no table for (the model file it is, the 3D cockpit and
    /// its HUD).
    #[test]
    fn switches_off_give_the_1998_values() {
        let off = Switches { f16: "barak", f15: "baz" };
        // Every 1998 type code: those without a definition (None) keep their tables.
        for code in [100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 210, 220, 230] {
            let Some(a) = of_type(code, off).map(Airframe::to_value) else { continue };
            let a = a.as_object().unwrap();
            let keys: Vec<&str> = a.keys().map(String::as_str).collect();
            assert!(
                keys.iter().all(|k| ["name", "doc", "notes", "original_model", "hud_3d", "cockpit_3d"].contains(k)),
                "{code}: {keys:?}"
            );
        }
        assert_eq!(of_type(100, off).unwrap().hud_3d.as_deref(), Some("HUD_std"));
        // The F-35I flies its definition's engine and flight controls (type 1000 has no 1998 row).
        assert_eq!(crate::spool::of_type("F-35I", 1000).map(|s| s.idle_mil), Some(4.0));
        assert_eq!(crate::spool::engine(1000), None, "the type table holds the 1998 jets only");
        assert_eq!(of_fm_type(1000).and_then(|a| a.fly_by_wire), Some(true));
    }

    #[test]
    fn the_sufa_is_the_f16_base_with_its_own_values() {
        let s = of_type(100, Switches { f16: "sufa", f15: "baz" }).unwrap();
        assert_eq!(s.original_model.as_deref(), Some("f16_h.gltf"), "from the base");
        assert_eq!((s.fm.as_deref(), s.hud_3d.as_deref()), (Some("F-16I"), Some("HUD_wide")));
        assert_eq!(s.radar.as_ref().and_then(|r| r.km), Some(104.0));
        assert_eq!(s.weapons.as_ref().and_then(|w| w.loads.as_ref()?.get(&1007).cloned()), Some((4, "CDFG".into())));
        assert!(s.base.is_none());
        let (sufa, barak) = (Switches { f16: "sufa", f15: "baz" }, Switches { f16: "barak", f15: "baz" });
        assert_eq!(model_for("f16_h.gltf", sufa), Some("res://extra/models/f16/f16i.glb"));
        assert_eq!(model_for("f16_h.gltf", barak), None);
        assert_eq!(model_for("f15_h.gltf", sufa), None);
        let raam = Switches { f16: "barak", f15: "raam" };
        assert_eq!(model_for("f15_h.gltf", raam), Some("converted/models/f15/f15i.glb"));
        assert_eq!(model_for("f16_h.gltf", raam), None);
        let r = of_type(110, raam).unwrap();
        assert_eq!((r.original_model.as_deref(), r.fm.as_deref()), (Some("f15_h.gltf"), Some("F-15I")));
        assert_eq!(r.radar.as_ref().map(|r| (r.row, r.km, r.ai_nm)), Some((None, Some(104.0), Some(30.8))));
        assert_eq!(r.gun_rounds, Some(500));
        assert_eq!(r.weapons.as_ref().and_then(|w| w.loads.as_ref()?.get(&1004).cloned()), Some((1, "BCDEFGH".into())));
    }
}
