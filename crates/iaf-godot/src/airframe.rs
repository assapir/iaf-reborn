//! `IafAirframe`: the aircraft definitions (`iaf_flight::airframe`, docs/adding-a-plane.md "Modern planes") for
//! GDScript, through `Settings.airframe(type_code)`.

use godot::prelude::*;
use iaf_flight::airframe::{self, Switches};
use serde_json::Value;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafAirframe {}

#[godot_api]
impl IafAirframe {
    /// The adapter: the definition id a jet of bdb type `type_code` flies as with the Extras switches
    /// (Settings `f16_variant`, `f15_variant`); "" for a 1998 jet without one.
    #[func]
    fn id_for(type_code: i64, f16_variant: GString, f15_variant: GString) -> GString {
        let (f16, f15) = (f16_variant.to_string(), f15_variant.to_string());
        airframe::id_for(type_code, Switches { f16: &f16, f15: &f15 }).unwrap_or_default().into()
    }

    /// The model drawn in place of the 1998 model file `file` with the Extras switches (`airframe::model_for`: a
    /// res:// path or one under assets/), "" to keep the original's.
    #[func]
    fn model_for(file: GString, f16_variant: GString, f15_variant: GString) -> GString {
        let (f16, f15) = (f16_variant.to_string(), f15_variant.to_string());
        airframe::model_for(&file.to_string(), Switches { f16: &f16, f15: &f15 }).unwrap_or_default().into()
    }

    /// Every definition's own model (what `model_for` can give), whatever the switches.
    #[func]
    fn models() -> PackedStringArray {
        airframe::all().filter_map(|(_, a)| a["model"].as_str()).map(GString::from).collect()
    }

    /// The resolved definition `id` (its base merged in); {} for an unknown id.
    #[func]
    fn definition(id: GString) -> VarDictionary {
        airframe::get(&id.to_string()).map(variant).and_then(|v| v.try_to().ok()).unwrap_or_default()
    }
}

/// A JSON value as a Variant: objects as Dictionaries, arrays as Arrays, whole numbers as int.
fn variant(v: &Value) -> Variant {
    match v {
        Value::Null => Variant::nil(),
        Value::Bool(b) => b.to_variant(),
        Value::Number(n) => n.as_i64().map_or_else(|| n.as_f64().unwrap_or(0.0).to_variant(), |i| i.to_variant()),
        Value::String(s) => s.to_variant(),
        Value::Array(a) => a.iter().map(variant).collect::<VarArray>().to_variant(),
        Value::Object(m) => {
            let mut d = VarDictionary::new();
            for (k, x) in m {
                d.set(k.as_str(), &variant(x));
            }
            d.to_variant()
        }
    }
}
