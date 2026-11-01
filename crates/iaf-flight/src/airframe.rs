//! Ours: the aircraft definitions of the modern jets (docs/adding-a-plane.md "Modern planes"). Each is one
//! `game/extra/planes/<id>/airframe.json`, built into the crate. A definition may name a `base`: it is then a JSON
//! Merge Patch (RFC 7386) on that base, holding only what differs (an object merges key by key, `null` removes a key,
//! any other value replaces). The 1998 type codes reach a definition through [`id_for`]; a 1998 jet without one keeps
//! its type-code tables.

use std::collections::BTreeMap;
use std::sync::LazyLock;

use serde_json::Value;

/// Every definition: its id (the folder) and the file's text.
const FILES: &[(&str, &str)] = &[("f35i", include_str!("../../../game/extra/planes/f35i/airframe.json"))];

/// The Extras switches that pick a 1998 jet's variant (Settings `f16_variant`, `f15_variant`).
#[derive(Clone, Copy, Debug, Default)]
pub struct Switches<'a> {
    pub f16: &'a str,
    pub f15: &'a str,
}

/// The adapter: the definition a jet of bdb type `type_code` flies as with the Extras switches `s`, None for a 1998
/// jet without one (its tables decide).
pub fn id_for(type_code: i64, _s: Switches) -> Option<&'static str> {
    match type_code {
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
        // Every other 1998 jet has no definition: its tables decide.
        for code in [120, 130, 140, 150, 160, 170, 180, 190, 200, 210, 220, 230] {
            assert_eq!(id_for(code, off), None, "{code}");
        }
        assert_eq!(of_type(1000, off).and_then(|a| a["radar"]["km"].as_f64()), Some(148.0));
    }
}
