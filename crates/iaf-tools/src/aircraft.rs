//! Aircraft descriptors: what the original engine takes from an aircraft frame file (`*_h.xfr`)
//! at load time (docs/part-animation.md §1, docs/aircraft.md), written as `aircraft.json` next
//! to the converted glTF so the game can animate any aircraft generically.
//!
//! Coordinates are glTF (the X file with Z mirrored), metres (the unscaled X file units).

use iaf_formats::model::{Frame, Model};
use serde_json::{Value, json};

/// Descriptor format version (bump when the layout changes).
pub const FORMAT: u32 = 1;

/// Clump scale of the flown models (`error.c`: "Scale= 5.000" for the F-16 and the MiG-17).
pub const SCALE: f32 = 5.0;

/// The frame-name table built by `FUN_005876a0` (`x3ds_<name>` → id). Ids 1..=0x27 also get the
/// hinge helpers `<name>1` (id + 0x3f) and `<name>2` (id + 0x67). Matching is case-insensitive.
pub const PART_NAMES: &[(&str, u32)] = &[
    ("AilerL", 0x01),
    ("AilerR", 0x02),
    ("CanarL", 0x03),
    ("CanarR", 0x04),
    ("RuddeL", 0x05),
    ("Rudde", 0x06),
    ("FlapL", 0x07),
    ("FlapR", 0x08),
    ("SpdbrU", 0x09),
    ("SpdbrD", 0x0a),
    ("ElevaL", 0x0b),
    ("ElevaR", 0x0c),
    ("ElevoL", 0x0d),
    ("ElevoR", 0x0e),
    ("LdgL", 0x0f),
    ("LdgR", 0x10),
    ("LdgF", 0x11),
    ("LdgDr", 0x12),
    ("Hook", 0x13),
    ("Parach", 0x27),
    ("canopy", 0x16),
    ("canopyB", 0x17),
    ("pilot", 0x14),
    ("pilotB", 0x15),
    ("StationA", 0x29),
    ("StationB", 0x2a),
    ("StationC", 0x2b),
    ("StationD", 0x2c),
    ("StationE", 0x2d),
    ("StationF", 0x2e),
    ("StationG", 0x2f),
    ("StationH", 0x30),
    ("StationI", 0x31),
    ("StationGun", 0x32),
    ("StationCha", 0x33),
    ("StationFla", 0x34),
    ("Pilon", 0x35),
    ("Camera", 0x36),
    ("Turret", 0x18),
    ("Radar", 0x19),
    ("Carrier", 0x1a),
    ("Launcher", 0x1b),
    ("Missile", 0x1c),
    ("RotorA", 0x1d),
    ("RotorB", 0x1e),
    ("RotorC", 0x1f),
    ("RotorD", 0x20),
    ("WheelsA", 0x21),
    ("WheelsB", 0x22),
    ("WheelsC", 0x23),
    ("WheelsD", 0x24),
    ("WheelsE", 0x25),
    ("WheelsF", 0x26),
    ("EndWingR", 0x38),
    ("EndWingL", 0x37),
    ("Height", 0x39),
    ("EngineL", 0x3a),
    ("EngineR", 0x3b),
    ("top02", 0x3c),
];

/// Flight-model data section per aircraft type (`FUN_005a8980`); other types keep the F-16 data.
pub fn fm_section(type_code: i64) -> Option<&'static str> {
    Some(match type_code {
        100 => "F-16",
        110 => "F-15",
        120 | 200 => "F-4",
        130 => "KFIR",
        140 => "LAVI",
        150 => "MIG21",
        160 => "MIG23",
        170 => "MIG25",
        180 => "MIG29",
        190 => "MIRAGE",
        210 => "MIG17",
        220 => "TU22",
        225 => "C130",
        _ => return None,
    })
}

/// Table id of a frame name (case-insensitive, first entry wins), including the X1/X2 helpers.
pub fn part_id(name: &str) -> Option<u32> {
    for &(n, id) in PART_NAMES {
        if n.eq_ignore_ascii_case(name) {
            return Some(id);
        }
    }
    for &(n, id) in PART_NAMES {
        if id > 0x27 {
            continue;
        }
        if name.len() == n.len() + 1 && name.is_char_boundary(n.len()) && name[..n.len()].eq_ignore_ascii_case(n) {
            match &name[n.len()..] {
                "1" => return Some(id + 0x3f),
                "2" => return Some(id + 0x67),
                _ => {}
            }
        }
    }
    None
}

/// Frame origin in X-file coordinates (row 3 of the frame matrix).
fn origin(f: &Frame) -> [f32; 3] {
    [f.transform[12], f.transform[13], f.transform[14]]
}

/// X file → glTF (mirror Z).
fn gl(p: [f32; 3]) -> [f32; 3] {
    [p[0], p[1], -p[2]]
}

fn len(p: [f32; 3]) -> f32 {
    (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt()
}

fn round(p: [f32; 3]) -> Value {
    json!(p.iter().map(|&v| (v as f64 * 1e5).round() / 1e5).collect::<Vec<f64>>())
}

/// One flying object of the object database (`.bdb`) that uses the model.
#[derive(Clone, Debug)]
pub struct DbObject {
    pub name: String,
    pub class: String,
    pub label: String,
    /// Aircraft type code (field 0x5b4; −1 for helicopters).
    pub type_code: i64,
}

/// Builds the descriptor of an aircraft frame file. `folder` is the plane folder name, `model`
/// the glTF file name, `source` the install-relative path, `objects` the database objects using it.
pub fn describe(model: &Model, folder: &str, gltf: &str, source: &str, objects: &[DbObject]) -> Value {
    let root = model.frames.first();
    let children: &[Frame] = root.map_or(&[], |r| r.children.as_slice());
    // FUN_0041c270: each direct child of the root is looked up in the table (a later frame with
    // the same name replaces the entry); unmatched children are dropped (never drawn).
    let mut entries: Vec<(u32, &Frame)> = Vec::new();
    let mut dropped = Vec::new();
    for c in children {
        match part_id(&c.name) {
            Some(id) => {
                entries.retain(|(i, _)| *i != id);
                entries.push((id, c));
            }
            None => dropped.push(c.name.clone()),
        }
    }
    let pos = |id: u32| entries.iter().find(|(i, _)| *i == id).map(|(_, f)| origin(f));
    let name_of = |id: u32| entries.iter().find(|(i, _)| *i == id).map(|(_, f)| f.name.clone());

    // Subparts (FUN_0053da00): ids 1..=0x27 and the engines; hinge axis from the X1/X2 helpers.
    let mut parts = serde_json::Map::new();
    for &(id, f) in &entries {
        if !(1..=0x27).contains(&id) && id != 0x3a && id != 0x3b {
            continue;
        }
        let mut axis = Value::Null;
        if (1..=0x27).contains(&id) {
            if let Some(p1) = pos(id + 0x3f) {
                // X2 is not checked: a missing X2 reads as the origin.
                let p2 = pos(id + 0x67).unwrap_or([0.0; 3]);
                let d = if len(p1) <= len(p2) { [p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2]] } else { [p1[0] - p2[0], p1[1] - p2[1], p1[2] - p2[2]] };
                let l = len(d);
                if l > 0.0 {
                    axis = round(gl([d[0] / l, d[1] / l, d[2] / l]));
                }
            }
        }
        parts.insert(f.name.clone(), json!({ "id": id, "pivot": round(gl(origin(f))), "axis": axis }));
    }

    // FUN_0041c680: afterburner nozzles. The pair (EngineX, EngineX1) gives the radius |ΔY|; the
    // stored position ends up as the plain EngineX frame; each completed pair counts once.
    const UNSET: f32 = 99999.0;
    let (mut right, mut left) = ([UNSET; 3], [UNSET; 3]);
    let (mut radius, mut pairs) = (0.0_f32, 0);
    for c in children {
        let n = c.name.as_str();
        let p = origin(c);
        let (slot, plain) = if n.eq_ignore_ascii_case("EngineR") || n.eq_ignore_ascii_case("EngineR1") {
            (&mut right, n.eq_ignore_ascii_case("EngineR"))
        } else if n.eq_ignore_ascii_case("EngineL") || n.eq_ignore_ascii_case("EngineL1") {
            (&mut left, n.eq_ignore_ascii_case("EngineL"))
        } else {
            continue;
        };
        if slot[0] == UNSET {
            *slot = p;
        } else {
            radius = (slot[1] - p[1]).abs();
            pairs += 1;
            if plain {
                *slot = p;
            }
        }
    }
    let engine = |p: [f32; 3]| if p[0] == UNSET { Value::Null } else { round(gl(p)) };

    // FUN_0041c7f0: the gun muzzle (last StationGun frame).
    let gun = children.iter().filter(|c| c.name.eq_ignore_ascii_case("StationGun")).last().map(|c| round(gl(origin(c))));

    let mut stations = serde_json::Map::new();
    for id in 0x29..=0x34 {
        if let (Some(p), Some(n)) = (pos(id), name_of(id)) {
            stations.insert(n, round(gl(p)));
        }
    }
    let end_wing = match (pos(0x37), pos(0x38)) {
        (Some(l), Some(r)) => json!({ "left": round(gl(l)), "right": round(gl(r)) }),
        (None, Some(r)) => json!({ "left": Value::Null, "right": round(gl(r)) }),
        _ => Value::Null,
    };
    let eye = pos(0x35).or(pos(0x36)).map(|p| round(gl(p))).unwrap_or(Value::Null);

    // Primary type: the most frequent type code among the database objects (ties: lowest).
    let mut types: Vec<i64> = objects.iter().map(|o| o.type_code).collect();
    types.sort();
    types.dedup();
    let primary = types
        .iter()
        .copied()
        .max_by_key(|t| (objects.iter().filter(|o| o.type_code == *t).count(), -t))
        .unwrap_or(-1);
    let label = objects.iter().find(|o| o.type_code == primary).map(|o| o.label.clone()).unwrap_or_default();

    json!({
        "format": FORMAT,
        "name": folder,
        "model": gltf,
        "source": source,
        "scale": SCALE,
        "root": root.map(|r| r.name.clone()).unwrap_or_default(),
        "type": primary,
        "types": types,
        "fm_section": fm_section(primary),
        "label": label,
        "objects": objects.iter().map(|o| json!({ "name": o.name, "class": o.class, "label": o.label, "type": o.type_code })).collect::<Vec<_>>(),
        "parts": parts,
        "dropped": dropped,
        "engines": {
            "left": engine(left),
            "right": engine(right),
            "radius": (radius as f64 * 1e5).round() / 1e5,
            "pairs": pairs,
        },
        "gun": gun,
        "stations": stations,
        "end_wing": end_wing,
        "height": pos(0x39).map(|p| (p[1] as f64 * 1e5).round() / 1e5),
        "eye": eye,
    })
}

/// Every converted object database of a missions folder (`<missions>/*.bdb.json`), as
/// (file stem, e.g. `iaf`, JSON).
pub fn read_bdbs(missions: &std::path::Path) -> anyhow::Result<Vec<(String, Value)>> {
    let mut out = Vec::new();
    for entry in std::fs::read_dir(missions)?.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let Some(stem) = name.strip_suffix(".bdb.json") else { continue };
        out.push((stem.to_string(), serde_json::from_slice(&std::fs::read(entry.path())?)?));
    }
    Ok(out)
}

/// The Present records of an object database, in order: (id `0x1e`, model path `0x64a` under
/// `3dobjects`, lower case with `/`; empty when the record has no model).
pub fn present_models(bdb: &Value) -> Vec<(i64, String)> {
    bdb["present"]["items"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|it| Some((it["0x1e"].as_i64()?, it["0x64a"].as_str()?.replace('\\', "/").to_lowercase())))
        .collect()
}

/// The flying objects of a converted object database (`<missions>/*.bdb.json`), keyed by the
/// lower-case model path (`controllableplanes/f16/f16_h.xfr`).
pub fn db_objects(bdb: &Value) -> std::collections::HashMap<String, Vec<DbObject>> {
    let present: std::collections::HashMap<_, _> = present_models(bdb).into_iter().collect();
    let mut out: std::collections::HashMap<String, Vec<DbObject>> = std::collections::HashMap::new();
    for o in bdb["objects"]["items"].as_array().into_iter().flatten() {
        let Some(path) = o["0x53c"].as_i64().and_then(|id| present.get(&id)) else { continue };
        let Some(type_code) = o["0x5b4"].as_i64() else { continue };
        out.entry(path.clone()).or_default().push(DbObject {
            name: o["0x514"].as_str().unwrap_or_default().to_string(),
            class: o["0x51e"].as_str().unwrap_or_default().to_string(),
            label: o["0x528"].as_str().unwrap_or_default().to_string(),
            type_code,
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_and_helpers() {
        assert_eq!(part_id("x"), None);
        assert_eq!(part_id("AilerL"), Some(1));
        assert_eq!(part_id("Canopy"), Some(0x16));
        assert_eq!(part_id("AilerL1"), Some(0x40));
        assert_eq!(part_id("ailerl2"), Some(0x68));
        assert_eq!(part_id("Rudde1"), Some(0x45));
        assert_eq!(part_id("RuddeL1"), Some(0x44));
        assert_eq!(part_id("height"), Some(0x39));
        // Only ids 1..0x27 get helpers: EngineL1 is not in the table.
        assert_eq!(part_id("EngineL1"), None);
        // stricmp: the AI planes' "LdGr" is LdgR.
        assert_eq!(part_id("LdGr"), Some(0x10));
        assert_eq!(part_id("WingL1"), None);
    }

    fn frame(name: &str, p: [f32; 3]) -> Frame {
        let mut t = [1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.];
        t[12] = p[0];
        t[13] = p[1];
        t[14] = p[2];
        Frame { name: name.into(), transform: t, meshes: vec![], children: vec![] }
    }

    #[test]
    fn descriptor_rules() {
        let root = Frame {
            name: "jet".into(),
            children: vec![
                frame("AilerL", [-3.0, 0.0, -1.0]),
                frame("AilerL1", [-4.0, 0.0, -1.0]),
                frame("AilerL2", [-2.0, 0.0, -1.0]),
                frame("EngineL1", [0.0, 0.5, -7.0]),
                frame("EngineL", [0.0, 0.1, -7.1]),
                frame("WingL1", [0.0, 0.0, 0.0]),
                frame("StationGun", [1.0, 0.0, 2.0]),
            ],
            ..frame("jet", [0.0; 3])
        };
        let d = describe(&Model { frames: vec![root] }, "jet", "jet_h.gltf", "x", &[]);
        // Axis from the helper nearer the origin (AilerL2, |2.24|) to the farther (AilerL1).
        assert_eq!(d["parts"]["AilerL"]["axis"], json!([-1.0, 0.0, -0.0]));
        assert_eq!(d["parts"]["AilerL"]["pivot"], json!([-3.0, 0.0, 1.0]));
        assert_eq!(d["engines"]["pairs"], 1);
        assert!((d["engines"]["radius"].as_f64().unwrap() - 0.4).abs() < 1e-5);
        // The plain EngineL arriving second overwrites the stored EngineL1 position.
        assert_eq!(d["engines"]["left"], json!([0.0, 0.1, 7.1]));
        assert_eq!(d["engines"]["right"], Value::Null);
        assert_eq!(d["dropped"], json!(["EngineL1", "WingL1"]));
        assert_eq!(d["gun"], json!([1.0, 0.0, -2.0]));
    }
}
