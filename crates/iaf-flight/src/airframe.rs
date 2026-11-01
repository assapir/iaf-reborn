//! Ours: the aircraft definitions of the modern jets (docs/adding-a-plane.md "Modern planes"). Each is one
//! `game/extra/planes/<id>/airframe.json`, built into the crate. A definition may name a `base`: it is then a JSON
//! Merge Patch (RFC 7386) on that base, holding only what differs (an object merges key by key, `null` removes a key,
//! any other value replaces). The 1998 type codes reach a definition through [`id_for`]; a 1998 jet without one keeps
//! its type-code tables.

use std::collections::BTreeMap;
use std::sync::LazyLock;

use serde_json::Value;

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
pub fn get(id: &str) -> Option<&'static Value> {
    RESOLVED.get(id)
}

/// Every definition id with its resolved definition.
pub fn all() -> impl Iterator<Item = (&'static str, &'static Value)> {
    RESOLVED.iter().map(|(k, v)| (*k, v))
}

/// The resolved definition of a jet (the adapter, then [`get`]).
pub fn of_type(type_code: i64, s: Switches) -> Option<&'static Value> {
    get(id_for(type_code, s)?)
}

/// The model drawn in place of the 1998 model file `file` (e.g. "f16_h.gltf"): the `model` of the definition the
/// switches `s` pick for the jet whose `original_model` it is; None to keep the original's.
pub fn model_for(file: &str, s: Switches) -> Option<&'static str> {
    [100, 110, 1000]
        .into_iter()
        .filter_map(|code| of_type(code, s))
        .find(|a| a["original_model"].as_str() == Some(file))?["model"]
        .as_str()
}

static RESOLVED: LazyLock<BTreeMap<&'static str, Value>> = LazyLock::new(|| {
    let raw: BTreeMap<&str, Value> = FILES
        .iter()
        .map(|&(id, text)| (id, serde_json::from_str(text).unwrap_or_else(|e| panic!("{id}/airframe.json: {e}"))))
        .collect();
    raw.keys().map(|&id| (id, resolve(&raw, id, 0))).collect()
});

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
            assert!(get(id).is_some_and(Value::is_object), "{id}");
        }
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
        assert_eq!(of_type(1000, off).and_then(|a| a["radar"]["km"].as_f64()), Some(148.0));
    }

    /// With every switch off a 1998 jet's definition holds no value its type-code tables decide, so the game reads
    /// exactly the 1998 values; only what the original has no table for (the model file it is, the 3D cockpit's HUD).
    #[test]
    fn switches_off_give_the_1998_values() {
        let off = Switches { f16: "barak", f15: "baz" };
        // Every 1998 type code: those without a definition (None) keep their tables.
        for code in [100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 210, 220, 230] {
            let Some(a) = of_type(code, off).and_then(Value::as_object) else { continue };
            let keys: Vec<&str> = a.keys().map(String::as_str).collect();
            assert!(
                keys.iter().all(|k| ["name", "doc", "notes", "original_model", "hud_3d"].contains(k)),
                "{code}: {keys:?}"
            );
        }
        assert_eq!(of_type(100, off).unwrap()["hud_3d"], "HUD_std");
    }

    #[test]
    fn the_sufa_is_the_f16_base_with_its_own_values() {
        let s = of_type(100, Switches { f16: "sufa", f15: "baz" }).unwrap();
        assert_eq!(s["original_model"], "f16_h.gltf", "from the base");
        assert_eq!((s["fm"].as_str(), s["hud_3d"].as_str()), (Some("F-16I"), Some("HUD_wide")));
        assert_eq!(s["radar"]["km"].as_f64(), Some(104.0));
        assert!(s.get("base").is_none());
        let (sufa, barak) = (Switches { f16: "sufa", f15: "baz" }, Switches { f16: "barak", f15: "baz" });
        assert_eq!(model_for("f16_h.gltf", sufa), Some("res://extra/models/f16/f16i.glb"));
        assert_eq!(model_for("f16_h.gltf", barak), None);
        assert_eq!(model_for("f15_h.gltf", sufa), None);
        let raam = Switches { f16: "barak", f15: "raam" };
        assert_eq!(model_for("f15_h.gltf", raam), Some("converted/models/f15/f15i.glb"));
        assert_eq!(model_for("f16_h.gltf", raam), None);
        // The Ra'am differs from the Baz in its model only.
        let (mut r, b) = (of_type(110, raam).unwrap().clone(), of_type(110, barak).unwrap());
        r.as_object_mut().unwrap().retain(|k, _| !matches!(k.as_str(), "model" | "name" | "notes"));
        let mut b = b.clone();
        b.as_object_mut().unwrap().retain(|k, _| !matches!(k.as_str(), "name" | "notes"));
        assert_eq!(r, b);
    }
}
