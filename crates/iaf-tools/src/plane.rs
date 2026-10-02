//! Adding a new plane (docs/adding-a-plane.md): the descriptor of a hand-made glTF model, its
//! validation report, and the checklist of every code table a new aircraft type goes into.

use std::path::Path;

use iaf_formats::model::{Frame, Model};
use serde_json::Value;

/// The frame tree of a glTF (the first scene's first root and its descendants) as a [`Model`] for
/// [`crate::aircraft::describe`]: names and local translations only (the descriptor reads nothing
/// else), back in X-file coordinates (Z mirrored, as `gltf.rs` writes it). Nodes with a `matrix`
/// give its translation (elements 12..15), the others their `translation`.
pub fn to_model(gltf: &Value) -> Model {
    let nodes = gltf["nodes"].as_array().cloned().unwrap_or_default();
    let roots: Vec<usize> = gltf["scenes"][gltf["scene"].as_u64().unwrap_or(0) as usize]["nodes"]
        .as_array()
        .map(|a| a.iter().filter_map(|v| v.as_u64()).map(|v| v as usize).collect())
        .unwrap_or_default();
    fn frame(nodes: &[Value], i: usize, depth: usize) -> Frame {
        let n = &nodes[i];
        let t = match n["matrix"].as_array() {
            Some(m) => [12, 13, 14].map(|k| m.get(k).and_then(Value::as_f64).unwrap_or(0.0) as f32),
            None => [0, 1, 2].map(|k| n["translation"][k].as_f64().unwrap_or(0.0) as f32),
        };
        let mut transform = [1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.];
        transform[12..15].copy_from_slice(&[t[0], t[1], -t[2]]);
        let children = if depth > 64 {
            Vec::new()
        } else {
            n["children"].as_array().into_iter().flatten().filter_map(Value::as_u64).map(|c| frame(nodes, c as usize, depth + 1)).collect()
        };
        Frame { name: n["name"].as_str().unwrap_or_default().to_string(), transform, meshes: Vec::new(), children }
    }
    Model { frames: roots.iter().filter(|&&i| i < nodes.len()).map(|&i| frame(&nodes, i, 0)).collect() }
}

/// Parts a flyable jet should have (docs/adding-a-plane.md §2), with what is lost without them.
const EXPECTED: &[(&str, &str)] = &[
    ("AilerL", "no left aileron / flaperon movement"),
    ("AilerR", "no right aileron / flaperon movement"),
    ("LdgL", "no left gear leg (gear up / down)"),
    ("LdgR", "no right gear leg"),
    ("LdgF", "no nose gear leg"),
    ("canopy", "no canopy (ejection throws nothing)"),
    ("pilot", "no pilot (ejection, crew shown)"),
    ("Height", "no wheel height: the jet sits on its origin"),
];

/// Problems of a descriptor built from a hand-made glTF (each line one finding; empty = none).
pub fn report(gltf: &Value, desc: &Value) -> Vec<String> {
    let mut out = Vec::new();
    let roots = gltf["scenes"][gltf["scene"].as_u64().unwrap_or(0) as usize]["nodes"].as_array().map_or(0, Vec::len);
    if roots != 1 {
        out.push(format!("the scene has {roots} root nodes: the game reads the parts as the direct children of one root"));
    }
    let parts = desc["parts"].as_object().cloned().unwrap_or_default();
    let has = |name: &str| {
        parts.keys().any(|k| k.eq_ignore_ascii_case(name))
            || (name.eq_ignore_ascii_case("Height") && !desc["height"].is_null())
    };
    for (name, loss) in EXPECTED {
        if !has(name) {
            out.push(format!("missing {name}: {loss}"));
        }
    }
    if !["ElevaL", "ElevaR", "ElevoL", "ElevoR"].iter().any(|n| has(n)) {
        out.push("no ElevaL/R or ElevoL/R: pitch shows only on a delta (aircraft_model.gd delta_wing: the ailerons)".into());
    }
    for (name, p) in &parts {
        let id = p["id"].as_u64().unwrap_or(0);
        // The parts the callback turns (docs/aircraft.md §2.1); doors, canards, crew, rotors and wheels stay at 0.
        let turns = matches!(id, 1 | 2 | 5..=0x11 | 0x13 | 0x27 | 0x90..=0x93);
        if turns && p["axis"].is_null() {
            out.push(format!("{name} has no hinge axis ({name}1 / {name}2 helpers): it never rotates"));
        }
    }
    if desc["engines"]["pairs"].as_u64().unwrap_or(0) == 0 {
        out.push("no EngineL + EngineL1 pair: no afterburner flame".into());
    }
    if desc["gun"].is_null() {
        out.push("no StationGun: rounds leave from the origin".into());
    }
    if desc["stations"].as_object().is_none_or(|s| s.is_empty()) {
        out.push("no StationA..I: every store hangs at the origin".into());
    }
    if desc["eye"].is_null() {
        out.push("no Camera (or Pilon): no cockpit eye point".into());
    } else if desc["eye"][2].as_f64().unwrap_or(0.0) > 0.0 {
        out.push("the eye is behind the origin (+Z): the nose should point to -Z".into());
    }
    // The engine-pair helpers are dropped as frames by design (the original's too).
    let names: Vec<&str> = desc["dropped"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter(|n| !n.eq_ignore_ascii_case("EngineL1") && !n.eq_ignore_ascii_case("EngineR1"))
        .collect();
    if !names.is_empty() {
        out.push(format!("root children the game hides (not a part name): {}", names.join(", ")));
    }
    // Glass: a canopy drawn with an alpha cutout or opaque (the original's canopies are partial alpha).
    for (name, _) in parts.iter().filter(|(k, _)| k.to_ascii_lowercase().starts_with("canopy")) {
        let node = gltf["nodes"].as_array().into_iter().flatten().find(|n| n["name"].as_str() == Some(name));
        let mesh = node.and_then(|n| n["mesh"].as_u64()).map(|m| &gltf["meshes"][m as usize]);
        let blends = mesh.is_some_and(|m| {
            m["primitives"].as_array().into_iter().flatten().any(|p| {
                p["material"].as_u64().is_some_and(|i| gltf["materials"][i as usize]["alphaMode"] == "BLEND")
            })
        });
        if !blends {
            out.push(format!("{name}: no alpha-blended material, the glass draws opaque or cut out"));
        }
    }
    out
}

/// One code table that lists aircraft type codes: file (repo-relative), the text its definition
/// starts with, and what it decides.
pub struct Table {
    pub file: &'static str,
    pub anchor: &'static str,
    pub what: &'static str,
    /// false: the table holds conditions, not a list; read it (the presence check is only a hint).
    pub list: bool,
}

/// Every place the code tables or switches on aircraft type codes (docs/adding-a-plane.md §1).
pub const TABLES: &[Table] = &[
    Table { file: "game/aircraft/player_aircraft.gd", anchor: "const FLYABLE :=", what: "flyable types (else flown as the F-16)", list: true },
    Table { file: "game/aircraft/player_aircraft.gd", anchor: "const COCKPIT :=", what: "cockpit index in cockpits.ibx (also radar.gd's table row)", list: true },
    Table { file: "game/aircraft/player_aircraft.gd", anchor: "const TWIN :=", what: "twin engines (cockpit gauges)", list: true },
    Table { file: "game/aircraft/player_aircraft.gd", anchor: "const JET_TYPES :=", what: "Jet list id -> type", list: true },
    Table { file: "crates/iaf-flight/src/data_set.rs", anchor: "pub const TYPES: &[Type] = &[", what: "flight-model type: name, model folder, section, code", list: true },
    Table { file: "crates/iaf-flight/src/data_set.rs", anchor: "const REAL: &[Real] = &[", what: "Real flight data row (by name; base section)", list: false },
    Table { file: "crates/iaf-flight/src/params.rs", anchor: "pub fn type_code(section: &str)", what: "section -> type code (original sections only)", list: true },
    Table { file: "crates/iaf-tools/src/aircraft.rs", anchor: "pub fn fm_section(type_code: i64)", what: "type -> flight-model section in the descriptor", list: true },
    Table { file: "crates/iaf-flight/src/aircraft.rs", anchor: "FLAPS_MAX * if self.params.type_code == 100", what: "F-16 flaps third", list: false },
    Table { file: "crates/iaf-flight/src/aircraft.rs", anchor: "self.better.fbw_departure && matches!(self.params.type_code", what: "fly-by-wire deep stall", list: true },
    Table { file: "crates/iaf-flight/src/aircraft.rs", anchor: "if !aero || p.type_code == 100", what: "fly-by-wire: no spin", list: true },
    Table { file: "game/aircraft/aircraft_model.gd", anchor: "var delta_wing := type_code in", what: "delta wing (elevons)", list: false },
    Table { file: "game/aircraft/aircraft_model.gd", anchor: "func part_pose(", what: "per-type part signs (speed brake, elevators, gear legs)", list: false },
    Table { file: "game/audio/flight_sounds.gd", anchor: "const BETTY_TYPES :=", what: "voice warnings (also RWR and damage)", list: true },
    Table { file: "game/weapons/real_weapons.gd", anchor: "const RADAR_KM :=", what: "real radar range", list: true },
    Table { file: "game/weapons/real_weapons.gd", anchor: "const GUN_ROUNDS :=", what: "real gun rounds", list: true },
    Table { file: "game/weapons/mission_weapons.gd", anchor: "const JET_ART :=", what: "Arming screen art + station boxes", list: true },
    Table { file: "game/menu/pilots.gd", anchor: "const TYPE_CATEGORY :=", what: "pilot records kill category", list: true },
    Table { file: "game/menu/tsd.gd", anchor: "const FLYABLE_TYPES :=", what: "flights selectable on the TSD", list: true },
    Table { file: "game/cockpit/cockpit.gd", anchor: "const RWR_GLYPH :=", what: "RWR symbol when others see this type", list: true },
    Table { file: "crates/iaf-tools/src/bin/iaf-mission-report.rs", anchor: "const FLYABLE_NOW: &[i64]", what: "mission coverage report", list: true },
    Table { file: "tests/godot/test_jet_list.gd", anchor: "const JETS :=", what: "Jet list test row", list: true },
];

/// Type codes a new type must not take: skipped by the RWR (`rwr.gd` IGNORED_TYPES).
pub const RESERVED: &[i64] = &[220, 250, 270];

/// One checklist row: the table, its 1-based line (None = anchor not found), and whether the type
/// appears in its definition.
pub struct Row {
    pub table: &'static Table,
    pub line: Option<usize>,
    pub present: bool,
}

/// The definition text from `start`: up to the line where its brackets close (at most 120 lines).
fn statement(lines: &[&str], start: usize) -> String {
    let mut depth = 0i32;
    let mut out = String::new();
    for (k, l) in lines[start..].iter().enumerate().take(120) {
        out.push_str(l);
        out.push('\n');
        depth += l.matches(['[', '{', '(']).count() as i32 - l.matches([']', '}', ')']).count() as i32;
        if depth <= 0 && (k > 0 || !l.trim_end().ends_with(['[', '{', '('])) {
            break;
        }
    }
    out
}

fn has_code(text: &str, code: i64) -> bool {
    let c = code.to_string();
    text.match_indices(&c).any(|(i, _)| {
        let digit = |b: Option<&u8>| b.is_some_and(u8::is_ascii_digit);
        !digit(i.checked_sub(1).and_then(|j| text.as_bytes().get(j))) && !digit(text.as_bytes().get(i + c.len()))
    })
}

/// Every table of [`TABLES`] under `repo`, with whether `code` is in it.
pub fn checklist(repo: &Path, code: i64) -> Vec<Row> {
    TABLES
        .iter()
        .map(|t| {
            let src = std::fs::read_to_string(repo.join(t.file)).unwrap_or_default();
            let lines: Vec<&str> = src.lines().collect();
            let line = lines.iter().position(|l| l.contains(t.anchor));
            let present = line.is_some_and(|i| has_code(&statement(&lines, i), code));
            Row { table: t, line: line.map(|i| i + 1), present }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// A minimal jet: root with an aileron (hinge helpers), one engine pair, wheel height, a
    /// station, the gun, the eye, a canopy with an opaque material and one stray node.
    fn tiny() -> Value {
        let n = |name: &str, t: [f32; 3]| json!({ "name": name, "translation": t });
        json!({
            "scene": 0,
            "scenes": [{ "nodes": [0] }],
            "nodes": [
                { "name": "f35", "children": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] },
                n("AilerL", [-3.0, 0.0, 1.0]),
                n("AilerL1", [-1.0, 0.0, 1.0]),
                n("AilerL2", [-4.0, 0.0, 1.0]),
                n("EngineL", [0.0, 0.0, 6.0]),
                n("EngineL1", [0.0, 0.6, 6.0]),
                n("Height", [0.0, -1.5, 0.0]),
                n("StationA", [-2.0, -0.5, 0.0]),
                n("StationGun", [-0.5, 0.3, -3.0]),
                n("Camera", [0.0, 0.8, -4.0]),
                { "name": "canopy", "translation": [0.0, 1.0, -4.0], "mesh": 0 },
            ],
            "meshes": [{ "primitives": [{ "material": 0 }] }],
            "materials": [{ "name": "glass" }],
        })
    }

    #[test]
    fn describes_a_hand_made_gltf() {
        let g = tiny();
        let d = crate::aircraft::describe(&to_model(&g), "f35", "f35.gltf", "hand-made", &[]);
        assert_eq!(d["root"], "f35");
        assert_eq!(d["parts"]["AilerL"]["id"], 1);
        assert_eq!(d["parts"]["AilerL"]["axis"], json!([-1.0, 0.0, 0.0]));
        assert_eq!(d["parts"]["AilerL"]["pivot"], json!([-3.0, 0.0, 1.0]));
        assert_eq!(d["engines"]["pairs"], 1);
        assert_eq!(d["engines"]["radius"], 0.6);
        assert_eq!(d["height"], -1.5);
        assert_eq!(d["stations"]["StationA"], json!([-2.0, -0.5, 0.0]));
        assert_eq!(d["gun"], json!([-0.5, 0.3, -3.0]));
        assert_eq!(d["eye"], json!([0.0, 0.8, -4.0]));

        let r = report(&g, &d);
        assert!(r.iter().any(|l| l.starts_with("missing LdgF")));
        assert!(r.iter().any(|l| l.starts_with("canopy: no alpha-blended")));
        assert!(!r.iter().any(|l| l.contains("EngineL")));
        assert!(!r.iter().any(|l| l.contains("hinge axis")));
        assert!(!r.iter().any(|l| l.starts_with("missing Height")));
    }

    #[test]
    fn checklist_finds_codes_in_definitions() {
        let dir = std::env::temp_dir().join(format!("iaf-plane-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("game/aircraft")).unwrap();
        std::fs::write(
            dir.join("game/aircraft/player_aircraft.gd"),
            "const FLYABLE := [110, 100]\nconst COCKPIT := {\n\t110: 0,\n\t1100: 1,\n}\nconst TWIN := [110]\n",
        )
        .unwrap();
        let rows = checklist(&dir, 100);
        let row = |a: &str| rows.iter().find(|r| r.table.anchor == a).unwrap();
        assert!(row("const FLYABLE :=").present);
        assert_eq!(row("const COCKPIT :=").line, Some(2));
        assert!(!row("const COCKPIT :=").present, "1100 is not 100");
        assert!(!row("const TWIN :=").present);
        assert_eq!(row("const BETTY_TYPES :=").line, None);
        std::fs::remove_dir_all(dir).ok();
    }
}

/// The arming screen art of an extra plane (docs/adding-a-plane.md §5), composed on the user's machine from the
/// original's arming art (never committed) and the plane's own front view:
/// - the background: a low percentile (the lower quarter) of every original jet image per pixel: each jet's
///   silhouette and leader lines (brighter than the dark background) are outvoted, the grid and radar ring they
///   all share remain;
/// - the station boxes and the bottom band (labels, DEFAULT) copied from `base` (an original jet's image whose box
///   layout the plane uses);
/// - the title area cleared (the game draws the plane's title);
/// - the front view over it, and a leader line from each box's top to its station point.
///
/// `scale`: art px per menu px (the converted menu art is 4×). Boxes and points are menu px.
pub fn compose_arm(
    originals: &[image::RgbaImage],
    base: &image::RgbaImage,
    front: &image::RgbaImage,
    boxes: &[(f32, f32)],
    points: &[(f32, f32)],
    scale: f32,
) -> image::RgbaImage {
    let (w, h) = base.dimensions();
    let mut out = image::RgbaImage::new(w, h);
    let mut vals: Vec<u8> = Vec::with_capacity(originals.len());
    for y in 0..h {
        for x in 0..w {
            let mut px = [0u8; 4];
            for (c, slot) in px.iter_mut().enumerate().take(3) {
                vals.clear();
                vals.extend(originals.iter().filter(|o| o.dimensions() == (w, h)).map(|o| o.get_pixel(x, y)[c]));
                vals.sort_unstable();
                *slot = if vals.is_empty() { 0 } else { vals[vals.len() / 4] };
            }
            px[3] = 255;
            out.put_pixel(x, y, image::Rgba(px));
        }
    }
    let s = |v: f32| (v * scale).round() as i64;
    let copy = |out: &mut image::RgbaImage, x0: i64, y0: i64, x1: i64, y1: i64| {
        for y in y0.max(0)..y1.min(h as i64) {
            for x in x0.max(0)..x1.min(w as i64) {
                out.put_pixel(x as u32, y as u32, *base.get_pixel(x as u32, y as u32));
            }
        }
    };
    // The bottom band (CURRENT LOAD, DEFAULT, MAX T.O.W.) and the boxes (51 × 32 with their frame).
    copy(&mut out, 0, s(322.0), w as i64, h as i64);
    for &(bx, by) in boxes {
        copy(&mut out, s(bx - 2.0), s(by - 2.0), s(bx + 53.0), s(by + 34.0));
    }
    // The title (top right, the base jet's name): the background of the rows just left of it.
    let (tx0, ty0, tx1, ty1) = (s(370.0), s(8.0), s(454.0).min(w as i64), s(34.0).min(h as i64));
    for y in ty0..ty1 {
        for x in tx0..tx1 {
            let src = *out.get_pixel((x - (tx1 - tx0)).max(0) as u32, y as u32);
            out.put_pixel(x as u32, y as u32, src);
        }
    }
    // Leader lines: up from each box's top centre to the station's row, then to the station.
    let line = image::Rgba([60u8, 190, 50, 255]);
    let seg = |out: &mut image::RgbaImage, a: (f32, f32), b: (f32, f32)| {
        let n = (((b.0 - a.0).abs().max((b.1 - a.1).abs())) * scale).ceil().max(1.0) as i64;
        for i in 0..=n {
            let t = i as f32 / n as f32;
            let (x, y) = (s(a.0 + (b.0 - a.0) * t), s(a.1 + (b.1 - a.1) * t));
            for dy in -1..=1 {
                for dx in -1..=1 {
                    let (px, py) = (x + dx, y + dy);
                    if px >= 0 && py >= 0 && (px as u32) < w && (py as u32) < h {
                        out.put_pixel(px as u32, py as u32, line);
                    }
                }
            }
        }
    };
    for (&(bx, by), &(px, py)) in boxes.iter().zip(points) {
        let top = (bx + 25.5, by - 2.0);
        let elbow = (top.0, (py + 14.0).min(top.1));
        seg(&mut out, top, elbow);
        seg(&mut out, elbow, (px, py));
    }
    // The front view, alpha over.
    for y in 0..h.min(front.height()) {
        for x in 0..w.min(front.width()) {
            let f = front.get_pixel(x, y);
            let a = f[3] as f32 / 255.0;
            if a <= 0.0 {
                continue;
            }
            let o = out.get_pixel_mut(x, y);
            for c in 0..3 {
                o[c] = (f[c] as f32 * a + o[c] as f32 * (1.0 - a)).round() as u8;
            }
        }
    }
    out
}

#[cfg(test)]
mod arm_tests {
    use super::*;

    #[test]
    fn median_drops_a_lone_silhouette_and_keeps_the_boxes() {
        let bg = image::Rgba([0u8, 20, 5, 255]);
        let mut a = image::RgbaImage::from_pixel(80, 80, bg);
        let b = a.clone();
        let mut c = a.clone();
        a.put_pixel(10, 10, image::Rgba([200, 200, 200, 255])); // a jet pixel only in one image
        c.put_pixel(4, 4, image::Rgba([0, 255, 0, 255])); // the base's box frame
        let front = image::RgbaImage::new(80, 80);
        let out = compose_arm(&[a, b, c.clone()], &c, &front, &[(3.0, 3.0)], &[(10.0, 0.0)], 1.0);
        assert_eq!(*out.get_pixel(10, 10), bg, "outvoted");
        assert_eq!(*out.get_pixel(4, 4), image::Rgba([0, 255, 0, 255]), "box copied from the base");
    }
}
