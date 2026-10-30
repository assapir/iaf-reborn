//! The detailed F-15 (Graphics → MORE → Models: Detailed; docs/aircraft-models.md §6), made on the player's machine.
//!
//! Source: Richard Harrison's (Zaretto) FlightGear F-15C (`github.com/Zaretto/fg-aircraft`, `aircraft/F-15`; 3D model
//! by Enrique Laso, rig by Richard Harrison, cockpit textures by GeneB), GPL-2.0-only. It cannot ship in our
//! GPL-3.0-or-later repo, so setup downloads it at a pinned commit ([`SOURCE`], each file's SHA-256 checked) into
//! `assets/source/f15/` and [`build`] converts it into `assets/converted/models/f15/f15c.glb`:
//!
//! 1. reads the AC3D files (`iaf_formats::ac3d`), keeps the single-seat F-15C without its stores, conformal tanks,
//!    ladder and rivet heads, and turns it into the game's frame (x right, y up, z aft);
//! 2. scales it to the original's length and puts it on the original: its middle on the original's, its wheels on
//!    the original's `height`;
//! 3. splits the moving parts under the original's names, each with its origin and `<part>1/2` helpers on
//!    FlightGear's own hinge line (f15c.xml), the axis turned the original's way; the gear doors open (`LdgDr`) and
//!    shut (`LdgDrUp`); the nozzles' petals ringed (nozzle-L/R.xml); the pylons moved onto the original's stations;
//! 4. copies the original's helpers (stations, eye, gun, wingtips, height) and puts `EngineL/R` and `EngineL1/R1`
//!    on the nozzles' exits (the afterburner);
//! 5. paints the livery as the IAF F-15C 802 "Panther" of 133 Squadron: FlightGear's grey F-15C (USAF 80-0007)
//!    without its US markings, tinted to the Baz's bluish grey, with our own markings ([`MARKS`], drawn in
//!    `data/f15-livery`) projected onto the skin by their places on the jet;
//! 6. writes a binary glTF with smooth normals (AC3D crease angles) and its JPEG / PNG textures inside; the game
//!    compresses them at the parse and makes the LODs (util/gltf.gd).
//!
//! The same files also make the F-15I Ra'am ([`OUTPUT_I`], Extras "F-15 version"; docs/aircraft-models.md §6.7):
//! FlightGear's two-seat canopy, conformal tanks with their pylons, rear cockpit and back-seater, in its IAF livery
//! (F-15I 269 of 69 Squadron) as it comes.

use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail, ensure};
use iaf_formats::ac3d;
use image::{Rgba, RgbaImage};
use serde_json::{Value, json};

use crate::progress::Progress;
use crate::thirdparty::Download;

/// The fg-aircraft commit the files come from (the last change to `aircraft/F-15`, 2020-01-03).
pub const COMMIT: &str = "062cb58a87e1bb97367bfa3b169778ce26aacc76";

macro_rules! raw {
    ($p:literal) => {
        concat!(
            "https://raw.githubusercontent.com/Zaretto/fg-aircraft/",
            "062cb58a87e1bb97367bfa3b169778ce26aacc76",
            "/aircraft/F-15/Models/",
            $p
        )
    };
}

/// The files the detailed F-15 is made from (about 18 MB), into `assets/source/f15/`.
pub const SOURCE: &[Download] = &[
    Download {
        file: "f15c.ac",
        url: raw!("f15c.ac"),
        sha256: "4577b4e7996842e74af2947ff597c0f3bf9d07ee407963d5c163298b053c7045",
        bytes: 14_351_291,
    },
    Download {
        file: "nozzleL.ac",
        url: raw!("nozzleL.ac"),
        sha256: "320f200e8730d84ef53b0e2939441a0339006316a89aac184d05ed8f827ea2d3",
        bytes: 124_366,
    },
    Download {
        file: "nozzleR.ac",
        url: raw!("nozzleR.ac"),
        sha256: "583d730c00086e4f0ae954ade8980f1d774be2479488e621b4e965331081bbeb",
        bytes: 124_446,
    },
    Download {
        file: "pilot.ac",
        url: raw!("pilot.ac"),
        sha256: "e9e32cae2ec6353cb8f1ff4f3501f1dcd9cd060ff087bbd943dc3c5e79fce23e",
        bytes: 329_765,
    },
    Download {
        file: "f15c-interior-front.ac",
        url: raw!("Cockpit/f15c-interior-front.ac"),
        sha256: "1e1782172f0fc4e95fb5b8110f2f54e0e3fdd48da0514efbc174be254dbd1920",
        bytes: 1_430_694,
    },
    Download {
        file: "livery.AF80-0007.jpg",
        url: raw!("Liveries/livery.AF80-0007.jpg"),
        sha256: "72439ce29fb53dd0663011b4e59ca54a6ee9b8959cbda44ddb71de163dd07c2d",
        bytes: 481_364,
    },
    Download {
        file: "common.png",
        url: raw!("common.png"),
        sha256: "391cf54f3dff4442c15dbc9ea6fd9724645f8606ae3fe8250aaf9f0bccb2a138",
        bytes: 319_228,
    },
    Download {
        file: "aces2.png",
        url: raw!("Cockpit/aces2.png"),
        sha256: "b56d59761ab3b1b127e9c56a3331ae2aaf6641c146e894ca6e2668b9ee1006c1",
        bytes: 87_169,
    },
    Download {
        file: "livery.IAF.jpg",
        url: raw!("Liveries/livery.IAF%20235-69%20SQ%20HAMMERS.jpg"),
        sha256: "1d5b04ebfe380dc75c697b696250acab45659b6d7be040ff983514aebf3596e4",
        bytes: 555_660,
    },
    Download {
        file: "f15-interior-back.ac",
        url: raw!("Cockpit/f15-interior-back.ac"),
        sha256: "8b392f5247992f991ae5836a1a6ad15eb189a5ff1631659e2591aa196500f54f",
        bytes: 1_044_690,
    },
    Download {
        file: "patch.IAF.jpg",
        url: raw!("Liveries/patch.IAF.jpg"),
        sha256: "19949fa632d95b249b1cec070f382866b8508e42839b1a006485a976fa3da22a",
        bytes: 17_660,
    },
];

/// The game's file, under `assets/`.
pub const OUTPUT: &str = "converted/models/f15/f15c.glb";
/// The F-15I Ra'am's (Extras "F-15 version" on Ra'am), under `assets/`.
pub const OUTPUT_I: &str = "converted/models/f15/f15i.glb";

/// Setup's step (and `iaf-convert f15-detailed`): the sources into `<assets>/source/f15` (the files there kept),
/// then the models at `<assets>/`[`OUTPUT`] and [`OUTPUT_I`].
pub fn setup(assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let src = assets.join("source/f15");
    crate::thirdparty::fetch_files(SOURCE, &src, pr, cancel)?;
    for (out, raam) in [(OUTPUT, false), (OUTPUT_I, true)] {
        pr.log(if raam { "converting the FlightGear F-15 as the F-15I" } else { "converting the FlightGear F-15C" });
        let st = build(&src, &assets.join("converted/planes/f15"), &assets.join(out), raam)?;
        pr.log(&format!("{out}: {} triangles, {:.1} MB (scale {:.4})", st.triangles, st.bytes as f64 / 1e6, st.scale));
    }
    Ok(())
}

/// A hinge from f15c.xml in FlightGear's frame (x aft, y right, z up, metres): two points on the line.
pub(crate) type Hinge = ([f32; 3], [f32; 3]);

pub(crate) const fn axis_y(c: [f32; 3]) -> Hinge {
    (c, [c[0], c[1] + 1.0, c[2]])
}

/// The moving parts: the original's name, FlightGear's objects (top-level names; a group's name takes its children)
/// and FlightGear's hinge (f15c.xml's `rotate` animations; None: the part does not turn).
const PARTS: &[(&str, &[&str], Option<Hinge>)] = &[
    ("AilerL", &["AileronL"], Some(([5.0335, -5.3892, 0.4772], [4.4189, -3.7767, 0.5701]))),
    ("AilerR", &["AileronR"], Some(([5.0335, 5.4368, 0.4754], [4.44085, 3.8377, 0.5746]))),
    ("FlapL", &["FlapL"], Some(([4.4107, -3.7839, 0.5651], [4.3970, -1.9840, 0.5725]))),
    ("FlapR", &["FlapR"], Some(([4.44085, 3.8298, 0.5566], [4.4111, 2.02199, 0.6155]))),
    ("ElevaL", &["StabilatorL"], Some(axis_y([7.9652, -1.7929, 0.0]))),
    ("ElevaR", &["StabilatorR"], Some(axis_y([7.9652, 1.7929, 0.0]))),
    ("RuddeL", &["rudder"], Some(([7.7720, -1.7059, 2.3325], [7.3705, -1.6659, 0.7031]))),
    ("Rudde", &["rudder.001"], Some(([7.7720, 1.7596, 2.3325], [7.3705, 1.7928, 0.7031]))),
    ("SpdbrU", &["Airbrake", "AirbrakeInside"], Some(axis_y([-0.7927, 0.0206, 1.1368]))),
    ("Hook", &["Hook"], Some(axis_y([6.16672, -0.20863, -0.01927]))),
    (
        "LdgF",
        &[
            "nosegear retraction linkage",
            "Upper FWD oleo",
            "Lower FWD oleo",
            "fwd retract strut",
            "Landing light",
            "Taxi light",
            "Landing lightBulb",
            "Taxi lightBulb",
            "Nose wheel",
        ],
        Some(axis_y([-3.4141, 0.0, -0.3202])),
    ),
    (
        "LdgL",
        &[
            "Left Main Upper oleo",
            "Left Main lower oleo",
            "Left Main retraction linkage",
            "Left Main retract strut",
            "Left Main wheel",
        ],
        Some(axis_y([1.95, -1.32, -0.483])),
    ),
    (
        "LdgR",
        &[
            "Right Main Upper oleo",
            "Right Main lower oleo",
            "Right Main retraction linkage",
            "Right Main retract strut",
            "Right Main wheel",
        ],
        Some(axis_y([1.9, 1.32, -0.483])),
    ),
    ("canopy", &["Canopy", "CanopyGlass"], None),
];

/// The gear doors f15c.xml opens with the gear down (the others are shut both up and down): objects, the hinge
/// (centre, axis) and the angle open (degrees; turned the way that swings the door down).
struct Door {
    objects: &'static [&'static str],
    centre: [f32; 3],
    axis: [f32; 3],
    deg: f32,
}

const DOORS: &[Door] = &[
    Door {
        objects: &["Nose door 2.000", "Nose door 2.001"],
        centre: [-3.3083, 0.0250, -0.3220],
        axis: [0.0, 1.0, 0.0],
        deg: 110.0,
    },
    Door {
        objects: &["Left Main door 3a", "Left Main door 3b"],
        centre: [2.0028, -1.4783, -0.5905],
        axis: [1.0, 0.0, 0.0],
        deg: 90.0,
    },
    Door {
        objects: &["Right Main door 3a", "Right Main door 3b"],
        centre: [2.0028, 1.4783, -0.5905],
        axis: [1.0, 0.0, 0.0],
        deg: 90.0,
    },
];

/// Groups and objects of f15c.ac left out of both: the stores and their rails (the game hangs its own), the ladder,
/// the radio call plates, the collision hull, and the canopy's rivet heads (60 000 triangles), inside glass,
/// mirrors, lamps and wire (inside the canopy, textures we do not read).
const DROP: &[&str] = &[
    "aim-9",
    "aim-120",
    "mk-84",
    "aim-7",
    "tanks",
    "lau128-l1",
    "lau128-l2",
    "lau128-r1",
    "lau128-r2",
    "adu552-l1",
    "adu552-l2",
    "adu552-r1",
    "adu552-r2",
    "aircraft-ladder",
    "radio-call",
    "convexhull",
    "canopy-outside-handle",
    "WindscreenFasteners",
    "CanopyFasteners",
    "CanopyGlassInside",
    "WindscreenGlassInside",
    "CanopyMirrors",
    "CanopyLockShootLightLamp",
    "CanopyLockShootLight",
    "CanopyRefuelReadyLight",
    "CanopyRefuelReadyLightLamp",
    "StandbyCompass",
    "CanopyWire",
    "CanopyBackCover",
];

/// Left out of the F-15C only: the two-seat canopy and the conformal tanks with their pylons.
const DROP_C: &[&str] = &["f15d-canopy", "CFT-left", "CFT-right", "CFT-left-pylons", "CFT-right-pylons"];
/// Left out of the F-15I only: the single-seat canopy (with the cover behind the seat).
const DROP_I: &[&str] = &["f15c-canopy"];
/// The rear cockpit's parts kept from f15-interior-back.ac (the F-15I's): its tub, side consoles, glare shield,
/// instrument panel and seat (the rudder pedals are left out).
const COCKPIT_BACK: &[&str] = &["interior-back", "Consoles", "InsideStructure"];
/// The back-seater: FlightGear's pilot moved by f15c.xml's offset ("Backseater"; FlightGear's frame, m).
const BACKSEATER: [f32; 3] = [1.4635, -0.0088, 0.1375];

/// The front cockpit's parts kept from f15c-interior-front.ac (the tub, glare shields and the ACES II seat; the
/// instrument panel and pedals are left out).
const COCKPIT: &[&str] = &["InteriorBucket", "GlareShield", "HudGlareShield", "aces2", "seat-cushion"];

/// The pylons: FlightGear's object and the original's station its foot goes to.
const PYLONS: &[(&str, &str)] = &[("su59-l", "StationB"), ("su59-r", "StationH"), ("su59-c", "StationE")];

/// The nozzles' rings: each petal object `<name>.<k>` is FlightGear's petal turned k · 22.5° about the nozzle's axis
/// (x) through its centre (nozzle-L/R.xml).
const NOZZLES: &[(&str, [f32; 3])] =
    &[("nozzleL.ac", [7.4506, -0.68663, 0.071]), ("nozzleR.ac", [7.4506, 0.73888, 0.071])];

/// The livery's textures (f15c.ac's names) -> our files.
const TEXTURES: &[(&str, &str)] = &[
    ("Liveries/livery.AF80-0007.jpg", "livery"),
    ("common.png", "common.png"),
    ("aces2.png", "aces2.png"),
    ("Liveries/patch.bitburg.jpg", "patch.IAF.jpg"),
];

/// FlightGear's frame (x aft, y right, z up) -> ours (x right, y up, z aft).
pub(crate) fn fg(p: [f32; 3]) -> [f32; 3] {
    [p[1], p[2], p[0]]
}

/// An AC3D file's frame (x aft, y up, z left) -> ours.
pub(crate) fn ac(p: [f32; 3]) -> [f32; 3] {
    [-p[2], p[1], p[0]]
}

pub(crate) type V = [f32; 3];
pub(crate) fn sub(a: V, b: V) -> V {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
pub(crate) fn add(a: V, b: V) -> V {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}
pub(crate) fn scale(a: V, s: f32) -> V {
    [a[0] * s, a[1] * s, a[2] * s]
}
pub(crate) fn dot(a: V, b: V) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
pub(crate) fn cross(a: V, b: V) -> V {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
pub(crate) fn norm(a: V) -> V {
    let l = dot(a, a).sqrt();
    if l > 0.0 { scale(a, 1.0 / l) } else { a }
}

/// `p` turned by `deg` about the line through `c` along unit `axis` (right hand).
pub(crate) fn rotate(p: V, c: V, axis: V, deg: f32) -> V {
    let (s, co) = deg.to_radians().sin_cos();
    let v = sub(p, c);
    let r = add(add(scale(v, co), scale(cross(axis, v), s)), scale(axis, dot(axis, v) * (1.0 - co)));
    add(r, c)
}

/// A triangle soup of one material: corners (position, normal, uv).
#[derive(Default)]
pub(crate) struct Soup {
    pos: Vec<V>,
    nrm: Vec<V>,
    uv: Vec<[f32; 2]>,
}

/// What a surface is painted with.
#[derive(Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub(crate) struct Mat {
    /// Our texture's name, or "" for a plain colour.
    pub(crate) texture: &'static str,
    /// sRGB colour × 255, alpha × 255.
    pub(crate) rgba: [u8; 4],
    pub(crate) two_sided: bool,
}

/// A triangle: its paint, corners, corner normals and uvs.
pub(crate) type Tri = (Mat, [V; 3], [V; 3], [[f32; 2]; 3]);

/// One AC3D object made into triangles in our frame, with smooth normals.
pub(crate) struct Piece {
    pub(crate) name: String,
    pub(crate) top: String,
    pub(crate) tris: Vec<Tri>,
}

impl Piece {
    /// One of `names`, itself or its top-level group.
    pub(crate) fn is(&self, names: &[&str]) -> bool {
        names.contains(&self.name.as_str()) || names.contains(&self.top.as_str())
    }
}

/// `textures`: the AC3D files' texture names -> ours (any other texture: a dark grey).
pub(crate) fn pieces(m: &ac3d::Model, f: impl Fn(V) -> V, textures: &[(&str, &'static str)]) -> Vec<Piece> {
    let mut out = Vec::new();
    for o in &m.objects {
        if o.surfaces.is_empty() {
            continue;
        }
        let verts: Vec<V> = o.verts.iter().map(|v| f(*v)).collect();
        let texture = o.texture.as_deref().map(|t| textures.iter().find(|(n, _)| *n == t).map_or("?", |x| x.1));
        let glass = o.name.contains("Glass");
        // Face normals (Newell), then per position the faces about it.
        let faces: Vec<V> = o
            .surfaces
            .iter()
            .map(|s| {
                let mut n = [0.0; 3];
                for k in 0..s.refs.len() {
                    let (a, b) = (verts[s.refs[k].0], verts[s.refs[(k + 1) % s.refs.len()].0]);
                    n = add(
                        n,
                        [(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])],
                    );
                }
                n
            })
            .collect();
        let key = |v: V| v.map(|c| (c * 1e4).round() as i64);
        let mut around: HashMap<[i64; 3], Vec<usize>> = HashMap::new();
        for (fi, s) in o.surfaces.iter().enumerate() {
            for r in &s.refs {
                around.entry(key(verts[r.0])).or_default().push(fi);
            }
        }
        let cos = o.crease.to_radians().cos();
        let mut tris = Vec::new();
        for (fi, s) in o.surfaces.iter().enumerate() {
            let fnorm = norm(faces[fi]);
            if dot(fnorm, fnorm) == 0.0 || s.refs.len() < 3 {
                continue;
            }
            let mat = &m.materials[s.mat];
            let mat = match (glass, texture) {
                (true, _) => Mat { texture: "", rgba: [38, 44, 52, 90], two_sided: true },
                (false, Some(t)) if t != "?" => Mat { texture: t, rgba: [255; 4], two_sided: s.two_sided },
                // Objects whose texture we do not read: a dark grey.
                (false, Some(_)) => Mat { texture: "", rgba: [60, 62, 64, 255], two_sided: s.two_sided },
                (false, None) => Mat {
                    texture: "",
                    rgba: [
                        srgb8(mat.rgb[0]),
                        srgb8(mat.rgb[1]),
                        srgb8(mat.rgb[2]),
                        (255.0 * (1.0 - mat.trans)).round() as u8,
                    ],
                    two_sided: s.two_sided,
                },
            };
            if mat.rgba[3] == 0 {
                continue;
            }
            let corner = |k: usize| -> (V, V, [f32; 2]) {
                let (vi, uv) = s.refs[k];
                let p = verts[vi];
                let n = if s.smooth {
                    let mut n = [0.0; 3];
                    for &g in &around[&key(p)] {
                        if dot(norm(faces[g]), fnorm) >= cos {
                            n = add(n, faces[g]);
                        }
                    }
                    norm(n)
                } else {
                    fnorm
                };
                (p, n, [uv[0], 1.0 - uv[1]])
            };
            let c0 = corner(0);
            for k in 1..s.refs.len() - 1 {
                let (c1, c2) = (corner(k), corner(k + 1));
                tris.push((mat.clone(), [c0.0, c1.0, c2.0], [c0.1, c1.1, c2.1], [c0.2, c1.2, c2.2]));
            }
        }
        let top = o.path.first().cloned().unwrap_or_else(|| o.name.clone());
        out.push(Piece { name: o.name.clone(), top, tris });
    }
    out
}

pub(crate) fn srgb8(c: f32) -> u8 {
    (c.clamp(0.0, 1.0) * 255.0).round() as u8
}

/// The original model's facts the detailed one is fitted to (its glTF and descriptor).
pub(crate) struct Original {
    /// Helper nodes (no mesh) and their position under the root.
    pub(crate) helpers: Vec<(String, V)>,
    pub(crate) root_translation: V,
    /// The body mesh's bounds.
    pub(crate) lo: V,
    pub(crate) hi: V,
    /// Part name -> axis (unit) from aircraft.json.
    pub(crate) axes: HashMap<String, V>,
}

/// The original model `<dir>/<name>_h.gltf` (its root node `name`) and its descriptor.
pub(crate) fn original(dir: &Path, name: &str) -> Result<Original> {
    let file = format!("{name}_h.gltf");
    let g: Value = serde_json::from_slice(&std::fs::read(dir.join(&file)).with_context(|| file.clone())?)?;
    let d: Value = serde_json::from_slice(&std::fs::read(dir.join("aircraft.json"))?)?;
    let nodes = g["nodes"].as_array().context("nodes")?;
    let t = |n: &Value| -> V {
        let m = &n["matrix"];
        [
            m[12].as_f64().unwrap_or(0.0) as f32,
            m[13].as_f64().unwrap_or(0.0) as f32,
            m[14].as_f64().unwrap_or(0.0) as f32,
        ]
    };
    let root = nodes.iter().find(|n| n["name"] == name).context("no root")?;
    let acc = &g["accessors"]
        [g["meshes"][root["mesh"].as_u64().context("root mesh")? as usize]["primitives"][0]["attributes"]["POSITION"]
            .as_u64()
            .context("position")? as usize];
    let v3 = |v: &Value| -> V { [0, 1, 2].map(|k| v[k].as_f64().unwrap_or(0.0) as f32) };
    let mut lo = v3(&acc["min"]);
    let mut hi = v3(&acc["max"]);
    for p in g["meshes"][root["mesh"].as_u64().unwrap_or(0) as usize]["primitives"].as_array().into_iter().flatten() {
        let a = &g["accessors"][p["attributes"]["POSITION"].as_u64().unwrap_or(0) as usize];
        lo = [0, 1, 2].map(|k| lo[k].min(v3(&a["min"])[k]));
        hi = [0, 1, 2].map(|k| hi[k].max(v3(&a["max"])[k]));
    }
    let mut helpers = Vec::new();
    for c in root["children"].as_array().into_iter().flatten() {
        let n = &nodes[c.as_u64().unwrap_or(0) as usize];
        let name = n["name"].as_str().unwrap_or("").to_string();
        let part_helper = name.ends_with(['1', '2']) && d["parts"].get(&name[..name.len() - 1]).is_some();
        if d["parts"].get(&name).is_none() && !part_helper {
            helpers.push((name, t(n)));
        }
    }
    let mut axes = HashMap::new();
    for (k, p) in d["parts"].as_object().context("parts")? {
        if p["axis"].is_array() {
            axes.insert(k.clone(), norm(v3(&p["axis"])));
        }
    }
    Ok(Original { helpers, root_translation: t(root), lo, hi, axes })
}

/// One node of the output: name, position (under the root), triangles in its own frame.
pub(crate) struct Node {
    pub(crate) name: String,
    pub(crate) at: V,
    pub(crate) tris: Vec<Tri>,
}

/// What [`build`] made.
pub struct Stats {
    pub triangles: usize,
    pub bytes: usize,
    pub scale: f32,
}

/// Makes `out` (the glb) from the downloaded files in `src` and the original F-15 in `orig` (its converted folder):
/// the F-15C 802, or with `raam` the F-15I.
pub fn build(src: &Path, orig: &Path, out: &Path, raam: bool) -> Result<Stats> {
    let o = original(orig, "f15")?;
    let read = |f: &str| -> Result<ac3d::Model> {
        let b = std::fs::read(src.join(f)).with_context(|| format!("reading {f}"))?;
        ac3d::parse(&String::from_utf8_lossy(&b)).with_context(|| f.to_string())
    };
    let main = read("f15c.ac")?;
    let variant_drop = if raam { DROP_I } else { DROP_C };
    let mut all: Vec<Piece> =
        pieces(&main, ac, TEXTURES).into_iter().filter(|p| !p.is(DROP) && !p.is(variant_drop)).collect();
    let skin: Vec<Skin> =
        all.iter().flat_map(|p| &p.tris).filter(|t| t.0.texture == "livery").map(|t| (t.1, t.2, t.3)).collect();
    for (file, c) in NOZZLES {
        for mut p in pieces(&read(file)?, ac, TEXTURES) {
            let k: f32 = p.name.rsplit_once('.').and_then(|(_, k)| k.parse().ok()).unwrap_or(0.0);
            for t in &mut p.tris {
                t.1 = t.1.map(|v| rotate(v, fg(*c), [0.0, 0.0, 1.0], 22.5 * k));
                t.2 = t.2.map(|v| rotate(v, [0.0; 3], [0.0, 0.0, 1.0], 22.5 * k));
            }
            p.top = "nozzle".into();
            all.push(p);
        }
    }
    let pilot = read("pilot.ac")?;
    for seat in if raam { &[[0.0; 3], BACKSEATER][..] } else { &[[0.0; 3]][..] } {
        for mut p in pieces(&pilot, |v| add(ac(v), fg(*seat)), TEXTURES) {
            p.top = "pilot".into();
            all.push(p);
        }
    }
    for p in pieces(&read("f15c-interior-front.ac")?, ac, TEXTURES) {
        if COCKPIT.contains(&p.top.as_str()) {
            all.push(Piece { top: "cockpit".into(), ..p });
        }
    }
    if raam {
        for p in pieces(&read("f15-interior-back.ac")?, ac, TEXTURES) {
            if COCKPIT_BACK.contains(&p.top.as_str()) {
                all.push(Piece { top: "cockpit".into(), ..p });
            }
        }
    }

    // Fit: the original's length, its middle along the jet and across; the main wheels on its `height`.
    let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
    let mut wheel_lo = f32::MAX;
    for p in &all {
        for t in &p.tris {
            for v in t.1 {
                if p.name.ends_with("Main wheel") {
                    wheel_lo = wheel_lo.min(v[1]);
                }
                if p.top != "pilot" && p.top != "cockpit" {
                    lo = [0, 1, 2].map(|k| lo[k].min(v[k]));
                    hi = [0, 1, 2].map(|k| hi[k].max(v[k]));
                }
            }
        }
    }
    ensure!(wheel_lo < f32::MAX, "f15c.ac: no main wheels");
    let s = (o.hi[2] - o.lo[2]) / (hi[2] - lo[2]);
    let height = o.helpers.iter().find(|h| h.0 == "height").context("no height helper")?.1[1];
    let shift = [
        (o.lo[0] + o.hi[0]) / 2.0 - s * (lo[0] + hi[0]) / 2.0,
        height - s * wheel_lo,
        (o.lo[2] + o.hi[2]) / 2.0 - s * (lo[2] + hi[2]) / 2.0,
    ];
    let place = |v: V| add(scale(v, s), shift);
    let place_fg = |v: V| place(fg(v));
    for p in &mut all {
        for t in &mut p.tris {
            t.1 = t.1.map(place);
        }
    }

    // The gear doors open: the closed copies go to LdgDrUp; each opened about its hinge, the way down.
    let mut nodes: Vec<Node> = Vec::new();
    let mut dr = Node { name: "LdgDr".into(), at: [0.0; 3], tris: Vec::new() };
    let mut dr_up = Node { name: "LdgDrUp".into(), at: [0.0; 3], tris: Vec::new() };
    for Door { objects: names, centre: c, axis, deg } in DOORS {
        let (c, axis) = (place_fg(*c), fg(*axis));
        let door: Vec<_> = all.iter().filter(|p| p.is(names)).flat_map(|p| p.tris.clone()).collect();
        ensure!(!door.is_empty(), "f15c.ac: no {names:?}");
        let mean_y = |deg: f32| -> f32 {
            door.iter().flat_map(|t| t.1).map(|v| rotate(v, c, axis, deg)[1]).sum::<f32>() / (3 * door.len()) as f32
        };
        let deg = if mean_y(*deg) < mean_y(-*deg) { *deg } else { -*deg };
        dr_up.tris.extend(door.iter().cloned());
        dr.tris
            .extend(door.into_iter().map(|t| {
                (t.0, t.1.map(|v| rotate(v, c, axis, deg)), t.2.map(|n| rotate(n, [0.0; 3], axis, deg)), t.3)
            }));
        all.retain(|p| !p.is(names));
    }

    // The pylons: each foot (its lowest point's middle) onto its station.
    for (name, st) in PYLONS {
        let at = o.helpers.iter().find(|h| h.0 == *st).with_context(|| format!("no {st}"))?.1;
        let p = all.iter_mut().find(|p| p.name == *name).with_context(|| format!("f15c.ac: no {name}"))?;
        let vs: Vec<V> = p.tris.iter().flat_map(|t| t.1).collect();
        let ylo = vs.iter().map(|v| v[1]).fold(f32::MAX, f32::min);
        let foot: Vec<&V> = vs.iter().filter(|v| v[1] < ylo + 0.03).collect();
        let mid = [0, 2].map(|k| {
            let (a, b) = foot.iter().fold((f32::MAX, f32::MIN), |m, v| (m.0.min(v[k]), m.1.max(v[k])));
            (a + b) / 2.0
        });
        let d = [at[0] - mid[0], at[1] - ylo, at[2] - mid[1]];
        for t in &mut p.tris {
            t.1 = t.1.map(|v| add(v, d));
        }
    }

    // The moving parts, each about its hinge.
    let mut helpers: Vec<(String, V)> = o.helpers.clone();
    for (part, names, hinge) in PARTS {
        let tris: Vec<_> = all.iter().filter(|p| p.is(names)).flat_map(|p| p.tris.clone()).collect();
        ensure!(!tris.is_empty(), "f15c.ac: no {names:?}");
        all.retain(|p| !p.is(names));
        let at = match hinge {
            Some((a, b)) => {
                let (a, b) = (place_fg(*a), place_fg(*b));
                let mut axis = norm(sub(b, a));
                if o.axes.get(*part).is_some_and(|oa| dot(*oa, axis) < 0.0) {
                    axis = scale(axis, -1.0);
                }
                // The pivot: the hinge line's point nearest the part's middle; the helpers on the line, the
                // nearer one first (the game takes the axis from the nearer to the farther).
                let mid = scale(tris.iter().flat_map(|t| t.1).fold([0.0; 3], add), 1.0 / (3 * tris.len()) as f32);
                let pivot = add(a, scale(axis, dot(sub(mid, a), axis)));
                let t0 = (-dot(pivot, axis)).max(0.0) + 0.05;
                helpers.push((format!("{part}1"), add(pivot, scale(axis, t0))));
                helpers.push((format!("{part}2"), add(pivot, scale(axis, t0 + 1.0))));
                pivot
            }
            None => scale(tris.iter().flat_map(|t| t.1).fold([0.0; 3], add), 1.0 / (3 * tris.len()) as f32),
        };
        nodes.push(Node { name: part.to_string(), at, tris });
    }
    let crew: Vec<_> = all.iter().filter(|p| p.top == "pilot").flat_map(|p| p.tris.clone()).collect();
    all.retain(|p| p.top != "pilot");
    let crew_at = scale(crew.iter().flat_map(|t| t.1).fold([0.0; 3], add), 1.0 / (3 * crew.len().max(1)) as f32);
    nodes.push(Node { name: "pilot".into(), at: crew_at, tris: crew });
    nodes.push(dr);
    nodes.push(dr_up);

    // The afterburners: EngineL/R at each nozzle's exit (its aftmost ring's middle), EngineL1/R1 up by its radius.
    for (side, x_sign) in [("L", -1.0f32), ("R", 1.0)] {
        let ring: Vec<V> = all
            .iter()
            .filter(|p| p.top == "nozzle")
            .flat_map(|p| p.tris.iter().flat_map(|t| t.1))
            .filter(|v| v[0] * x_sign > 0.0)
            .collect();
        let zmax = ring.iter().map(|v| v[2]).fold(f32::MIN, f32::max);
        let exit: Vec<&V> = ring.iter().filter(|v| v[2] > zmax - 0.05).collect();
        ensure!(!exit.is_empty(), "no nozzle {side}");
        let (xa, xb) = exit.iter().fold((f32::MAX, f32::MIN), |m, v| (m.0.min(v[0]), m.1.max(v[0])));
        let (ya, yb) = exit.iter().fold((f32::MAX, f32::MIN), |m, v| (m.0.min(v[1]), m.1.max(v[1])));
        let c = [(xa + xb) / 2.0, (ya + yb) / 2.0, zmax];
        helpers.retain(|h| h.0 != format!("Engine{side}") && h.0 != format!("Engine{side}1"));
        helpers.push((format!("Engine{side}"), c));
        helpers.push((format!("Engine{side}1"), add(c, [0.0, (yb - ya) / 2.0, 0.0])));
    }

    let body = Node { name: "f15".into(), at: [0.0; 3], tris: all.into_iter().flat_map(|p| p.tris).collect() };
    let triangles = body.tris.len() + nodes.iter().map(|n| n.tris.len()).sum::<usize>();
    let livery = if raam { image::open(src.join("livery.IAF.jpg"))?.to_rgba8() } else { livery(src, &skin)? };
    let mut jpg = Vec::new();
    image::DynamicImage::ImageRgba8(livery)
        .to_rgb8()
        .write_with_encoder(image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpg, 92))?;
    let mut images = Vec::new();
    for (_, ours) in TEXTURES {
        images.push(if *ours == "livery" {
            (*ours, jpg.clone(), "image/jpeg")
        } else {
            (*ours, std::fs::read(src.join(ours))?, if ours.ends_with(".png") { "image/png" } else { "image/jpeg" })
        });
    }
    let glb = write_glb(
        body,
        o.root_translation,
        nodes,
        helpers,
        &images,
        "FlightGear F-15C: Enrique Laso, Richard Harrison, GeneB (GPL-2.0-only)",
    )?;
    if let Some(d) = out.parent() {
        std::fs::create_dir_all(d)?;
    }
    let tmp = out.with_extension("glb.part");
    std::fs::write(&tmp, &glb)?;
    std::fs::rename(&tmp, out)?;
    Ok(Stats { triangles, bytes: glb.len(), scale: s })
}

/// The grey livery's US markings painted out (x0, y0, x1, y1): the squadron bands at the fin tips, the tail codes
/// and the fin flash.
const ERASE: &[[u32; 4]] = &[
    [1616, 358, 1726, 386],
    [1896, 380, 2016, 406],
    [1804, 486, 1938, 594],
    [1457, 666, 1594, 716],
    [1744, 664, 1852, 692],
    [1830, 772, 1960, 912],
];
/// The USAF crests on the fuselage sides painted out: centre, radius.
const CRESTS: &[([u32; 2], u32)] = &[([1869, 1545], 40), ([916, 1714], 40)];

/// The grey F-15C livery as F-15C 802 (see [`build`]): `skin`, the livery's triangles (our frame, unscaled).
fn livery(src: &Path, skin: &[Skin]) -> Result<RgbaImage> {
    let mut grey = image::open(src.join("livery.AF80-0007.jpg"))?.to_rgba8();
    ensure!(grey.dimensions() == (2048, 2048), "livery.AF80-0007.jpg: unexpected size");
    let blank = |p: &Rgba<u8>| p[0] > 235 && p[1] > 235 && p[2] > 235;
    // Paints a region out: each of its pixels (background left out) the mean of its neighbours, repeated until it
    // settles (a membrane over the colours round it: no streaks, no text).
    let erase = |img: &mut RgbaImage, inside: &dyn Fn(u32, u32) -> bool, x0: u32, y0: u32, x1: u32, y1: u32| {
        // The region and a pixel round it: (a hole pixel, its colour or None for background).
        let (gx, gy) = (x0.saturating_sub(1), y0.saturating_sub(1));
        let (w, h) = ((x1 + 2).min(2048) - gx, (y1 + 2).min(2048) - gy);
        let mut cells: Vec<(bool, Option<[f32; 3]>)> = (0..w * h)
            .map(|i| {
                let (x, y) = (gx + i % w, gy + i / w);
                let p = img.get_pixel(x, y);
                let hole = (x0..=x1).contains(&x) && (y0..=y1).contains(&y) && inside(x, y);
                (hole, (!blank(p)).then(|| [p[0] as f32, p[1] as f32, p[2] as f32]))
            })
            .collect();
        // Starting from the mean colour round it.
        let rim: Vec<[f32; 3]> = cells.iter().filter(|c| !c.0).filter_map(|c| c.1).collect();
        let start = if rim.is_empty() {
            [128.0; 3]
        } else {
            scale(rim.iter().fold([0.0; 3], |a, c| add(a, *c)), 1.0 / rim.len() as f32)
        };
        for c in cells.iter_mut().filter(|c| c.0) {
            c.1 = Some(start);
        }
        for _ in 0..400 {
            for i in 0..cells.len() {
                let (x, y) = (i as u32 % w, i as u32 / w);
                if !cells[i].0 || x == 0 || y == 0 || x == w - 1 || y == h - 1 {
                    continue;
                }
                let around = [i - 1, i + 1, i - w as usize, i + w as usize];
                let near: Vec<[f32; 3]> = around.iter().filter_map(|&j| cells[j].1).collect();
                if !near.is_empty() {
                    cells[i].1 = Some(scale(near.iter().fold([0.0; 3], |a, c| add(a, *c)), 1.0 / near.len() as f32));
                }
            }
        }
        for (i, c) in cells.iter().enumerate() {
            if let (true, Some(c)) = c {
                let (x, y) = (gx + i as u32 % w, gy + i as u32 / w);
                img.put_pixel(x, y, Rgba([c[0].round() as u8, c[1].round() as u8, c[2].round() as u8, 255]));
            }
        }
    };
    for r in ERASE {
        let keep = grey.clone();
        erase(&mut grey, &|x, y| !blank(keep.get_pixel(x, y)), r[0], r[1], r[2], r[3]);
    }
    for (c, r) in CRESTS {
        let (cx, cy, r) = (c[0] as i64, c[1] as i64, *r as i64);
        let inside = |x: u32, y: u32| (x as i64 - cx).pow(2) + (y as i64 - cy).pow(2) <= r * r;
        erase(&mut grey, &inside, (cx - r) as u32, (cy - r) as u32, (cx + r) as u32, (cy + r) as u32);
    }
    tint(&mut grey);
    paint(&mut grey, skin)?;
    Ok(grey)
}

/// A triangle of the livery: its corners (our frame, before the fit), their normals and uvs (0..1, y down).
type Skin = ([V; 3], [V; 3], [[f32; 2]; 3]);

/// FlightGear's grey is neutral; the Baz's air superiority greys (FS 36375 / 36320) are bluish. Each channel is
/// scaled to the hue of 802's paint on its photos, white-balanced on its roundel (docs/aircraft-models.md §6.1).
const TINT: [f32; 3] = [0.90, 0.95, 1.0];

fn tint(img: &mut RgbaImage) {
    for p in img.pixels_mut() {
        for k in 0..3 {
            p[k] = (p[k] as f32 * TINT[k]).round() as u8;
        }
    }
}

/// A marking of F-15C 802 (docs/aircraft-models.md §6.1): our picture (`data/f15-livery`, drawn as seen from the
/// jet's left), its width (m), its centre on the left half (our frame before the fit: x right, y up, z aft; m) and
/// the way the surface faces there. The right half takes it mirrored across the centre line: text reads the same
/// way there, art is mirrored (so it faces forward on both sides).
struct Mark {
    png: &'static [u8],
    width: f32,
    at: V,
    facing: V,
    text: bool,
}

macro_rules! mark {
    ($f:literal, $w:expr, $at:expr, $facing:expr, $text:expr) => {
        Mark {
            png: include_bytes!(concat!("../data/f15-livery/", $f, ".png")),
            width: $w,
            at: $at,
            facing: $facing,
            text: $text,
        }
    };
}

const LEFT: V = [-1.0, 0.0, 0.0];
const RIGHT: V = [1.0, 0.0, 0.0];
const UP: V = [0.0, 1.0, 0.0];
const DOWN: V = [0.0, -1.0, 0.0];

/// The markings, measured on photos of 802 and its sister jets (docs/aircraft-models.md §6.1). Later ones lie over
/// earlier ones.
const MARKS: &[Mark] = &[
    // The nose: the roundel under the canopy's rear, the name behind the radome, four kills, the tail number.
    mark!("roundel", 0.57, [-0.62, 0.66, -5.49], LEFT, true),
    mark!("name_802", 0.47, [-0.60, 0.60, -7.30], LEFT, true),
    mark!("kills", 0.82, [-0.62, 0.80, -6.70], LEFT, true),
    mark!("serial_nose", 0.29, [-0.62, 0.40, -6.52], LEFT, true),
    // A roundel above and under each wing, on the outer panel.
    mark!("roundel", 0.60, [-4.9, 0.58, 4.0], UP, true),
    mark!("roundel", 0.60, [-4.9, 0.46, 4.0], DOWN, true),
    // The outer faces of the fins: the red emblem, the bird of prey, the tail number.
    mark!("emblem_802", 0.13, [-1.76, 2.97, 7.82], LEFT, false),
    mark!("bird", 0.94, [-1.76, 2.16, 7.26], LEFT, false),
    mark!("serial_fin", 0.68, [-1.76, 1.09, 7.07], LEFT, true),
    // The inner faces: 133 Squadron's black band with the eagle's head (wider than the fin; the fin takes its part).
    mark!("band_133", 2.4, [-1.74, 2.615, 7.66], RIGHT, false),
];

/// How far off its surface a marking reaches (m): the curve of the fuselage under it, not the next surface.
const MARK_DEPTH: f32 = 0.2;

/// A marking placed on one side: its picture (premultiplied), centre, facing, the picture's right and down (m).
struct Placed {
    pic: Vec<[f32; 4]>,
    size: (usize, usize),
    at: V,
    n: V,
    u: V,
    v: V,
    w: f32,
    h: f32,
}

impl Placed {
    /// The premultiplied colour at (s, t) in 0..1, bilinear.
    fn sample(&self, s: f32, t: f32) -> [f32; 4] {
        let (w, h) = self.size;
        let x = (s * w as f32 - 0.5).clamp(0.0, (w - 1) as f32);
        let y = (t * h as f32 - 0.5).clamp(0.0, (h - 1) as f32);
        let (x0, y0) = (x as usize, y as usize);
        let (x1, y1) = ((x0 + 1).min(w - 1), (y0 + 1).min(h - 1));
        let (fx, fy) = (x - x0 as f32, y - y0 as f32);
        let p = |x: usize, y: usize| self.pic[y * w + x];
        [0, 1, 2, 3].map(|k| {
            let top = p(x0, y0)[k] * (1.0 - fx) + p(x1, y0)[k] * fx;
            let bottom = p(x0, y1)[k] * (1.0 - fx) + p(x1, y1)[k] * fx;
            top * (1.0 - fy) + bottom * fy
        })
    }
}

/// The markings both sides, each projected along its facing onto the livery's triangles that face that way within
/// [`MARK_DEPTH`]: every texel sampled 3 × 3 on its triangles (smooth edges, also across the skin's seams).
fn paint(img: &mut RgbaImage, skin: &[Skin]) -> Result<()> {
    let mut placed = Vec::new();
    for m in MARKS {
        let pic = image::load_from_memory(m.png)?.to_rgba8();
        let size = (pic.width() as usize, pic.height() as usize);
        let pre: Vec<[f32; 4]> = pic
            .pixels()
            .map(|p| {
                let a = p[3] as f32 / 255.0;
                [p[0] as f32 * a, p[1] as f32 * a, p[2] as f32 * a, a]
            })
            .collect();
        let h = m.width * size.1 as f32 / size.0 as f32;
        for right in [false, true] {
            let flip = |v: V| if right { [-v[0], v[1], v[2]] } else { v };
            let n = flip(m.facing);
            let (u, v) = if n[1].abs() > 0.5 {
                ([1.0, 0.0, 0.0], [0.0, 0.0, 1.0])
            } else if n[0] > 0.0 && m.text {
                ([0.0, 0.0, -1.0], DOWN)
            } else {
                ([0.0, 0.0, 1.0], DOWN)
            };
            placed.push(Placed { pic: pre.clone(), size, at: flip(m.at), n, u, v, w: m.width, h });
        }
    }
    const SS: u32 = 3;
    let (tw, th) = img.dimensions();
    // Per texel: the markings' premultiplied colour and alpha summed over its samples, and the samples.
    let mut acc: HashMap<u32, ([f32; 4], u32)> = HashMap::new();
    for (pos, nrm, uv) in skin {
        let fnorm = norm(add(add(nrm[0], nrm[1]), nrm[2]));
        let near: Vec<&Placed> = placed
            .iter()
            .filter(|d| {
                let r = (d.w * d.w + d.h * d.h).sqrt() / 2.0 + MARK_DEPTH;
                dot(fnorm, d.n) > 0.3
                    && (0..3).all(|k| pos.iter().any(|p| p[k] > d.at[k] - r) && pos.iter().any(|p| p[k] < d.at[k] + r))
            })
            .collect();
        if near.is_empty() {
            continue;
        }
        let px = uv.map(|t| [t[0] * tw as f32, t[1] * th as f32]);
        let den = (px[1][1] - px[2][1]) * (px[0][0] - px[2][0]) + (px[2][0] - px[1][0]) * (px[0][1] - px[2][1]);
        if den.abs() < 1e-9 {
            continue;
        }
        let lo =
            |k: usize, n: u32| px.iter().map(|p| p[k]).fold(f32::MAX, f32::min).floor().clamp(0.0, n as f32) as u32;
        let hi = |k: usize, n: u32| px.iter().map(|p| p[k]).fold(f32::MIN, f32::max).ceil().clamp(0.0, n as f32) as u32;
        for ty in lo(1, th)..hi(1, th) {
            for tx in lo(0, tw)..hi(0, tw) {
                for k in 0..SS * SS {
                    let qx = tx as f32 + ((k % SS) as f32 + 0.5) / SS as f32;
                    let qy = ty as f32 + ((k / SS) as f32 + 0.5) / SS as f32;
                    let l0 = ((px[1][1] - px[2][1]) * (qx - px[2][0]) + (px[2][0] - px[1][0]) * (qy - px[2][1])) / den;
                    let l1 = ((px[2][1] - px[0][1]) * (qx - px[2][0]) + (px[0][0] - px[2][0]) * (qy - px[2][1])) / den;
                    if l0 < 0.0 || l1 < 0.0 || l0 + l1 > 1.0 {
                        continue;
                    }
                    let p = add(add(scale(pos[0], l0), scale(pos[1], l1)), scale(pos[2], 1.0 - l0 - l1));
                    let mut c = [0.0f32; 4];
                    for d in &near {
                        let r = sub(p, d.at);
                        let (s, t) = (dot(r, d.u) / d.w + 0.5, dot(r, d.v) / d.h + 0.5);
                        if dot(r, d.n).abs() > MARK_DEPTH || !(0.0..1.0).contains(&s) || !(0.0..1.0).contains(&t) {
                            continue;
                        }
                        let m = d.sample(s, t);
                        c = [0, 1, 2, 3].map(|k| m[k] + c[k] * (1.0 - m[3]));
                    }
                    let e = acc.entry(ty * tw + tx).or_insert(([0.0; 4], 0));
                    e.0 = [0, 1, 2, 3].map(|k| e.0[k] + c[k]);
                    e.1 += 1;
                }
            }
        }
    }
    for (i, (c, n)) in acc {
        if c[3] <= 0.0 {
            continue;
        }
        let p = img.get_pixel_mut(i % tw, i / tw);
        let a = c[3] / n as f32;
        for k in 0..3 {
            p[k] = (p[k] as f32 * (1.0 - a) + c[k] / n as f32).round().clamp(0.0, 255.0) as u8;
        }
    }
    Ok(())
}

/// The binary glTF: the body as the root mesh `f15` (at `root`, the original's), the parts and helpers under it
/// (every position in the root's frame).
/// `images`: each texture's name (the triangles' `Mat::texture`), its file's bytes and MIME type.
pub(crate) fn write_glb(
    body: Node,
    root: V,
    parts: Vec<Node>,
    helpers: Vec<(String, V)>,
    images_in: &[(&'static str, Vec<u8>, &'static str)],
    copyright: &str,
) -> Result<Vec<u8>> {
    let mut bin: Vec<u8> = Vec::new();
    let (mut views, mut accessors, mut meshes, mut nodes) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let mut view = |bin: &mut Vec<u8>, bytes: &[u8], target: Option<u32>| -> usize {
        while !bin.len().is_multiple_of(4) {
            bin.push(0);
        }
        let mut v = json!({"buffer": 0, "byteOffset": bin.len(), "byteLength": bytes.len()});
        if let Some(t) = target {
            v["target"] = json!(t);
        }
        bin.extend_from_slice(bytes);
        views.push(v);
        views.len() - 1
    };
    let mut images = Vec::new();
    let mut tex_index: HashMap<&str, usize> = HashMap::new();
    for (name, bytes, mime) in images_in {
        let v = view(&mut bin, bytes, None);
        tex_index.insert(name, images.len());
        images.push(json!({"bufferView": v, "mimeType": mime}));
    }
    let mut mats: Vec<Mat> = Vec::new();
    let mut mesh_of =
        |bin: &mut Vec<u8>, n: &Node, accessors: &mut Vec<Value>, meshes: &mut Vec<Value>| -> Option<usize> {
            if n.tris.is_empty() {
                return None;
            }
            let mut groups: std::collections::BTreeMap<Mat, Soup> = Default::default();
            for (m, p, nr, uv) in &n.tris {
                let g = groups.entry(m.clone()).or_default();
                for k in 0..3 {
                    g.pos.push(sub(p[k], n.at));
                    g.nrm.push(nr[k]);
                    g.uv.push(uv[k]);
                }
            }
            let mut prims = Vec::new();
            for (m, g) in groups {
                let mi = mats.iter().position(|x| *x == m).unwrap_or_else(|| {
                    mats.push(m.clone());
                    mats.len() - 1
                });
                // Shared corners (same position, normal and uv) are indexed once.
                let mut idx: HashMap<[u32; 8], u32> = HashMap::new();
                let (mut p, mut nr, mut uv, mut ind) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
                for k in 0..g.pos.len() {
                    let key = [
                        g.pos[k][0],
                        g.pos[k][1],
                        g.pos[k][2],
                        g.nrm[k][0],
                        g.nrm[k][1],
                        g.nrm[k][2],
                        g.uv[k][0],
                        g.uv[k][1],
                    ]
                    .map(f32::to_bits);
                    let i = *idx.entry(key).or_insert_with(|| {
                        p.push(g.pos[k]);
                        nr.push(g.nrm[k]);
                        uv.push(g.uv[k]);
                        (p.len() - 1) as u32
                    });
                    ind.push(i);
                }
                let f = |d: &[f32]| d.iter().flat_map(|x| x.to_le_bytes()).collect::<Vec<u8>>();
                let (lo, hi) = p.iter().fold(([f32::MAX; 3], [f32::MIN; 3]), |(lo, hi), v| {
                    ([0, 1, 2].map(|k| lo[k].min(v[k])), [0, 1, 2].map(|k| hi[k].max(v[k])))
                });
                let a = accessors.len();
                let pv = view(bin, &f(p.as_flattened()), Some(34962));
                accessors.push(json!({
                    "bufferView": pv, "componentType": 5126, "count": p.len(), "type": "VEC3", "min": lo, "max": hi
                }));
                let nv = view(bin, &f(nr.as_flattened()), Some(34962));
                accessors.push(json!({"bufferView": nv, "componentType": 5126, "count": nr.len(), "type": "VEC3"}));
                let uvv = view(bin, &f(uv.as_flattened()), Some(34962));
                accessors.push(json!({"bufferView": uvv, "componentType": 5126, "count": uv.len(), "type": "VEC2"}));
                let iv = view(bin, &ind.iter().flat_map(|x| x.to_le_bytes()).collect::<Vec<u8>>(), Some(34963));
                accessors.push(json!({"bufferView": iv, "componentType": 5125, "count": ind.len(), "type": "SCALAR"}));
                prims.push(json!({
                "attributes": {"POSITION": a, "NORMAL": a + 1, "TEXCOORD_0": a + 2}, "indices": a + 3, "material": mi
            }));
            }
            meshes.push(json!({"name": n.name, "primitives": prims}));
            Some(meshes.len() - 1)
        };
    let mut kids = Vec::new();
    for n in &parts {
        let mut node = json!({"name": n.name, "translation": n.at});
        if let Some(m) = mesh_of(&mut bin, n, &mut accessors, &mut meshes) {
            node["mesh"] = json!(m);
        }
        nodes.push(node);
        kids.push(nodes.len() - 1);
    }
    for (name, at) in &helpers {
        nodes.push(json!({"name": name, "translation": at}));
        kids.push(nodes.len() - 1);
    }
    let mut root = json!({"name": body.name, "translation": root, "children": kids});
    if let Some(m) = mesh_of(&mut bin, &body, &mut accessors, &mut meshes) {
        root["mesh"] = json!(m);
    }
    nodes.push(root);
    let materials: Vec<Value> = mats
        .iter()
        .enumerate()
        .map(|(i, m)| {
            let c = m.rgba.map(|v| v as f32 / 255.0);
            let lin = |v: f32| if v <= 0.04045 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) };
            let mut pbr = json!({
                "baseColorFactor": [lin(c[0]), lin(c[1]), lin(c[2]), c[3]],
                "metallicFactor": 0.1,
                "roughnessFactor": 0.6
            });
            if !m.texture.is_empty() {
                pbr["baseColorTexture"] = json!({"index": tex_index[m.texture]});
            }
            let mut v = json!({"name": format!("m{i}"), "pbrMetallicRoughness": pbr, "doubleSided": m.two_sided});
            if m.rgba[3] < 255 {
                v["alphaMode"] = json!("BLEND");
            } else if m.texture.ends_with("_clip") {
                v["alphaMode"] = json!("MASK"); // a marking: its texture's alpha cuts it out
            }
            v
        })
        .collect();
    let textures: Vec<Value> = (0..images.len()).map(|i| json!({"source": i})).collect();
    while !bin.len().is_multiple_of(4) {
        bin.push(0);
    }
    let doc = json!({
        "asset": {
            "version": "2.0",
            "generator": "iaf-reborn iaf-convert",
            "copyright": copyright
        },
        "scene": 0,
        "scenes": [{"nodes": [nodes.len() - 1]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "textures": textures,
        "images": images,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": bin.len()}],
    });
    let mut js = serde_json::to_vec(&doc)?;
    while !js.len().is_multiple_of(4) {
        js.push(b' ');
    }
    let total = 12 + 8 + js.len() + 8 + bin.len();
    let mut out = Vec::with_capacity(total);
    out.extend_from_slice(b"glTF");
    out.extend_from_slice(&2u32.to_le_bytes());
    out.extend_from_slice(&(total as u32).to_le_bytes());
    out.extend_from_slice(&(js.len() as u32).to_le_bytes());
    out.extend_from_slice(b"JSON");
    out.extend_from_slice(&js);
    out.extend_from_slice(&(bin.len() as u32).to_le_bytes());
    out.extend_from_slice(b"BIN\0");
    out.extend_from_slice(&bin);
    if out.len() != total {
        bail!("glb size");
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_source_is_pinned() {
        let mut files: Vec<_> = SOURCE.iter().map(|d| d.file).collect();
        files.sort();
        files.dedup();
        assert_eq!(files.len(), SOURCE.len());
        for d in SOURCE {
            assert!(d.sha256.len() == 64 && d.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "{}", d.file);
            assert!(d.url.contains(COMMIT) && !d.url.contains(' '), "{}", d.file);
        }
    }

    #[test]
    fn frames_and_turns() {
        // FlightGear's aft / right / up and AC3D's aft / up / left are our z / x / y.
        assert_eq!(fg([1.0, 2.0, 3.0]), [2.0, 3.0, 1.0]);
        assert_eq!(ac([1.0, 2.0, 3.0]), [-3.0, 2.0, 1.0]);
        let r = rotate([1.0, 0.0, 0.0], [0.0; 3], [0.0, 0.0, 1.0], 90.0);
        assert!((r[0]).abs() < 1e-6 && (r[1] - 1.0).abs() < 1e-6);
    }

    /// The markings land where MARKS puts them: a 1 m square of skin facing left round the nose roundel's centre
    /// takes the roundel (blue star in the middle, white ring, grey corners), and its mirror on the right likewise.
    #[test]
    fn marks_land_in_place() {
        for x in [-0.62f32, 0.62] {
            let c = [x, 0.66, -5.49];
            let q = |dy: f32, dz: f32| [x, c[1] + dy, c[2] + dz];
            let n = [[x.signum(), 0.0, 0.0]; 3];
            // uv: z -> u, y -> v (down), the square on the whole 64² image.
            let skin = [
                ([q(0.5, -0.5), q(0.5, 0.5), q(-0.5, 0.5)], n, [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0]]),
                ([q(0.5, -0.5), q(-0.5, 0.5), q(-0.5, -0.5)], n, [[0.0, 0.0], [1.0, 1.0], [0.0, 1.0]]),
            ];
            let mut img = RgbaImage::from_pixel(64, 64, Rgba([128, 128, 128, 255]));
            paint(&mut img, &skin).unwrap();
            let at = |dz: f32, dy: f32| *img.get_pixel(((dz + 0.5) * 64.0) as u32, ((0.5 - dy) * 64.0) as u32);
            let (mid, ring, corner) = (at(0.0, 0.0), at(0.0, 0.26), at(0.45, 0.45));
            assert!(mid[2] > 150 && mid[0] < 60, "{x}: star {mid:?}");
            assert!(ring[0] > 220 && ring[2] > 220, "{x}: ring {ring:?}");
            assert_eq!(corner, Rgba([128, 128, 128, 255]), "{x}: corner");
        }
    }

    /// The whole conversion on the downloaded sources (setup's `models` step), when they are there.
    #[test]
    fn builds_from_the_sources() {
        let a = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        let src = a.join("source/f15");
        if !SOURCE.iter().all(|d| crate::thirdparty::file_done(&src, d)) || !a.join("converted/planes/f15").is_dir() {
            eprintln!("skipped: no assets/source/f15 (setup's models step) or no converted F-15");
            return;
        }
        let out = std::env::temp_dir().join(format!("iaf-f15-{}.glb", std::process::id()));
        for raam in [false, true] {
            let st = build(&src, &a.join("converted/planes/f15"), &out, raam).unwrap();
            let glb = std::fs::read(&out).unwrap();
            std::fs::remove_file(&out).unwrap();
            assert!(glb.starts_with(b"glTF") && glb.len() == st.bytes);
            assert!((30_000..70_000).contains(&st.triangles), "raam {raam}: {} triangles", st.triangles);
            assert!((st.scale - 1.0).abs() < 0.05, "scale {}", st.scale);
        }
    }
}
