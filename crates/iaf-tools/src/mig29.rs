//! The detailed MiG-29 (Graphics → MORE → Models: Detailed; docs/aircraft-models.md §7), built by a developer and
//! shipped in the repo (`game/extra/models/mig29/mig29.glb`).
//!
//! Source: the FlightGear MiG-29 9-12 (`github.com/Mercenary-Mercury/MiG-29_9-12`, external model by Enrique Laso
//! Leon, FDM / cockpit / submodels by Sergey "Mercenary_Mercury" Salov), GPL-3.0. [`build`] converts it with the
//! F-15's machinery ([`crate::f15`]):
//!
//! 1. reads `MiG-29.ac`, leaves out the mirrors inside the canopy and the Soviet side numbers, and adds the pilot and
//!    the K-36DM seat at Cockpit.xml's offsets;
//! 2. scales it to the original's length, its middle on the original's, its main wheels on the original's `height`;
//! 3. splits the moving parts under the original's names on MiG-29.xml's hinge lines, the gear doors open (`LdgDr`)
//!    and shut (`LdgDrUp`); `Parach`, the drag chute (shown only when deployed), is our own cone at the original
//!    chute's place and size;
//! 4. copies the original's helpers and puts `EngineL/R` on the nozzles' exits;
//! 5. repaints FlightGear's Soviet grey-green as a Syrian MiG-29's two-tone grey ([`repaint`]); the red stars become the
//!    Syrian roundel on the wings and the Syrian flag on the fins (ours, drawn here); adds our pylons ([`PYLON_LEN`]).
//!
//! `iaf-convert mig29-detailed <src dir> <assets>/converted/planes/mig29 <out.glb>` fetches the pinned files into
//! `<src dir>` (kept) and writes the glb.

use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, ensure};
use iaf_formats::ac3d;
use image::{Rgba, RgbaImage};
use serde_json::Value;

use crate::f15::{Hinge, Node, Piece, Tri, V, ac, add, axis_y, dot, fg, norm, pieces, rotate, scale, sub, write_glb};
use crate::progress::Progress;
use crate::thirdparty::Download;

/// The MiG-29 9-12 commit the files come from (its last, 2016-06-08).
pub const COMMIT: &str = "d4a299bf88412f579b2067874989a8088b2f6d66";

macro_rules! raw {
    ($p:literal) => {
        concat!(
            "https://raw.githubusercontent.com/Mercenary-Mercury/MiG-29_9-12/",
            "d4a299bf88412f579b2067874989a8088b2f6d66",
            "/Models/",
            $p
        )
    };
}

/// The files the model is made from (about 3.6 MB).
pub const SOURCE: &[Download] = &[
    Download {
        file: "MiG-29.ac",
        url: raw!("MiG-29.ac"),
        sha256: "c663f9189f89af9d61a3322346566ac9e8f7bdc26e8517a261b9b6e6a620167a",
        bytes: 2_138_186,
    },
    Download {
        file: "MiG-29_1.png",
        url: raw!("MiG-29_1.png"),
        sha256: "86569dd53cf3f55b996e7b8d353a4a420d3d822ce5b1af8fb0728f6ec4e71b47",
        bytes: 240_732,
    },
    Download {
        file: "MiG-29_2.png",
        url: raw!("MiG-29_2.png"),
        sha256: "dc98fe51606a0d26c1160788334383950361495e5d15b041a8a634905497203f",
        bytes: 172_324,
    },
    Download {
        file: "fighter_pilot_proto.ac",
        url: raw!("Submodels/Pilot/fighter_pilot_proto.ac"),
        sha256: "a230078ac64d01aeebfec285c3d579cdfdc902817dbcd8834d776accfb35d4f5",
        bytes: 830_681,
    },
    Download {
        file: "fighter_pilot_proto.png",
        url: raw!("Submodels/Pilot/fighter_pilot_proto.png"),
        sha256: "d3ae73dea6e0e74425c05606292901a83f5ad886e43a4ac9d9846d5f5eda1236",
        bytes: 69_000,
    },
    Download {
        file: "K-36DM.ac",
        url: raw!("Submodels/K-36DM/K-36DM.ac"),
        sha256: "0a2dc983894e98bf30a529fbe1b2ffe1fdaa3cb5d12cc9d584c65545a7f11239",
        bytes: 211_461,
    },
    Download {
        file: "K-36DM.png",
        url: raw!("Submodels/K-36DM/K-36DM.png"),
        sha256: "ba92cd9bbc663d9d44d81efd161c58005c8365262d4ce813140c2ce242dd76c5",
        bytes: 1_967,
    },
];

/// `iaf-convert mig29-detailed`: the sources into `src` (kept), then the glb at `out`.
pub fn setup(src: &Path, orig: &Path, out: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    crate::thirdparty::fetch_files(SOURCE, src, pr, cancel)?;
    let st = build(src, orig, out)?;
    pr.log(&format!("{}: {} triangles, {:.1} MB (scale {:.4})", out.display(), st.0, st.1 as f64 / 1e6, st.2));
    Ok(())
}

/// The textures (the AC3D files' names -> ours; `insignia_clip` is ours, below).
const TEXTURES: &[(&str, &str)] = &[
    ("MiG-29_1.png", "MiG-29_1.png"),
    ("MiG-29_2.png", "MiG-29_2.png"),
    ("fighter_pilot_proto.png", "fighter_pilot_proto.png"),
    ("K-36DM.png", "K-36DM.png"),
];

/// Left out: the mirrors inside the canopy (DROP, DROP_PREFIX) and the side numbers (Soviet "bort" numbers).
const DROP: &[&str] =
    &["MirrorC.Case", "MirrorC.K", "MirrorC.M", "MirrorC.Rt", "MirrorL.Case", "MirrorL.K", "MirrorL.M", "MirrorL.Rt"];
const DROP_PREFIX: &[&str] = &["MirrorR.", "MiG-29.BN"];

/// Mirrors a hinge across the centre line (FlightGear's y).
const fn mirror(h: Hinge) -> Hinge {
    ([h.0[0], -h.0[1], h.0[2]], [h.1[0], -h.1[1], h.1[2]])
}

const AILERON: Hinge = ([4.136, -3.693, -0.144], [4.536, -4.946, -0.228]);
const FLAP: Hinge = ([3.468, -1.731, -0.008381], [4.075, -3.592, -0.136]);
const STAB: Hinge = ([5.904, -1.738, -0.172], [5.904, -2.736, -0.24176]);
const RUDDER: Hinge = ([6.439, -1.691, 0.399], [6.785, -1.775, 1.661]);
const MAIN_GEAR: Hinge = ([2.445, -1.329, -0.065], [2.285, -1.167, -0.275]);

/// The moving parts: the original's name, FlightGear's objects and hinge (MiG-29.xml's `rotate` animations, its
/// frame: x aft, y right, z up). The airbrake's lower half stays shut in the body (the original's SpdbrU is one part).
const PARTS: &[(&str, &[&str], Option<Hinge>)] = &[
    ("AilerL", &["AileronL"], Some(AILERON)),
    ("AilerR", &["AileronR"], Some(mirror(AILERON))),
    ("FlapL", &["FlapL"], Some(FLAP)),
    ("FlapR", &["FlapR"], Some(mirror(FLAP))),
    ("ElevaL", &["StabL"], Some(STAB)),
    ("ElevaR", &["StabR"], Some(mirror(STAB))),
    ("RuddeL", &["RudderL"], Some(RUDDER)),
    ("Rudde", &["RudderR"], Some(mirror(RUDDER))),
    ("SpdbrU", &["AirbrakeU"], Some(axis_y([5.418, 0.0, -0.06732]))),
    (
        "LdgF",
        &[
            "Gear_jack",
            "Gear_jack_body",
            "Gear_strut",
            "Nose_oleo",
            "Fork",
            "Gear_strut_fork",
            "Nose_fork",
            "Nose_tyre_L",
            "Nose_tyre_R",
            "Nose_wheel_L",
            "Nose_wheel_R",
            "Nose_Gear_axle",
            "Mud_guard",
            "Mud_guard_brace",
            "FPK-250",
            "FPK-250.G",
        ],
        Some(axis_y([-1.820, 0.0, -0.010])),
    ),
    (
        "LdgL",
        &[
            "Main_gear_strutL",
            "Main_gr_compass_L",
            "Main_gr_compass_low_L",
            "Main_gr_oleoL",
            "Main_tyre_L",
            "Main_wheel_L",
            "Main_gr_jackL",
            "Main_gr_jack_bodyL",
        ],
        Some(MAIN_GEAR),
    ),
    (
        "LdgR",
        &[
            "Main_gear_strutR",
            "Main_gr_compass_R",
            "Main_gr_compass_low_R",
            "Main_gr_oleoR",
            "Main_tyre_R",
            "Main_wheel_R",
            "Main_gr_jackR",
            "Main_gr_jack_bodyR",
        ],
        Some(mirror(MAIN_GEAR)),
    ),
    ("canopy", &["Canopy", "CanopyGlass"], None),
];

/// The gear doors MiG-29.xml opens with the gear down: objects, hinge (two points, FlightGear's frame) and the angle
/// open (degrees; turned the way that swings the door down).
const DOORS: &[(&[&str], Hinge, f32)] = &[
    (&["fwdnosegeardoor"], axis_y([-3.026, 0.0, -0.326]), 27.0),
    (&["nosegeardoorL"], ([-1.902, -0.307, -0.259], [0.117, -0.307, -0.285]), 80.0),
    (&["nosegeardoorR"], ([-1.902, 0.307, -0.259], [0.117, 0.307, -0.285]), 80.0),
    (&["fwdgeardoor.L", "FP-8.L", "FP-8.GL"], ([0.416, -1.107, -0.552], [1.464, -1.153, -0.552]), 150.0),
    (&["fwdgeardoor.R", "FP-8.R", "FP-8.GR"], ([0.416, 1.107, -0.552], [1.464, 1.153, -0.552]), 150.0),
    (&["reargeardoor.L"], ([2.003, -1.638, -0.06473], [2.525, -1.603, -0.06381]), 60.0),
    (&["reargeardoor.R"], ([2.003, 1.638, -0.06473], [2.525, 1.603, -0.06381]), 60.0),
    (&["reargear2door.L"], ([3.48843, -1.48567, -0.1592083], [3.49124, -1.38178, -0.1920117]), 30.0),
    (&["reargear2door.R"], ([3.49124, 1.3864, -0.1920117], [3.48843, 1.49028, -0.1592083]), 30.0),
];

/// The pilot and the K-36DM seat (Cockpit.xml's offsets, FlightGear's frame).
const PILOT_AT: V = [-3.300, 0.0, 0.566];
const SEAT_AT: V = [-3.210, 0.0, -0.049];

/// What [`build`] made: triangles, bytes, scale.
pub type Stats = (usize, usize, f32);

/// Makes `out` from the files in `src` and the original MiG-29 in `orig` (its converted folder).
pub fn build(src: &Path, orig: &Path, out: &Path) -> Result<Stats> {
    let o = crate::f15::original(orig, "mig29")?;
    let read = |f: &str| -> Result<ac3d::Model> {
        let b = std::fs::read(src.join(f)).with_context(|| format!("reading {f}"))?;
        ac3d::parse(&String::from_utf8_lossy(&b)).with_context(|| f.to_string())
    };
    let mut all: Vec<Piece> = pieces(&read("MiG-29.ac")?, ac, TEXTURES)
        .into_iter()
        .filter(|p| !p.is(DROP) && !DROP_PREFIX.iter().any(|d| p.name.starts_with(d)))
        .collect();
    for p in &mut all {
        if p.name.starts_with("Nozzle") {
            p.top = "nozzle".into();
        }
        if p.name == "Insignia" {
            insignia(&mut p.tris);
        }
    }
    // The livery repainted on the skin before the fit (the pattern by FlightGear's metres).
    let mut atlases = Vec::new();
    for tex in ["MiG-29_1.png", "MiG-29_2.png"] {
        let mut img = image::open(src.join(tex))?.to_rgba8();
        repaint(&mut img, tex, &all);
        let mut png = Vec::new();
        img.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)?;
        atlases.push((tex, png));
    }
    for mut p in pieces(&read("fighter_pilot_proto.ac")?, |v| add(ac(v), fg(PILOT_AT)), TEXTURES) {
        p.top = "pilot".into();
        all.push(p);
    }
    for mut p in pieces(&read("K-36DM.ac")?, |v| add(ac(v), fg(SEAT_AT)), TEXTURES) {
        p.top = "cockpit".into();
        all.push(p);
    }

    // Fit: the original's length, its middle along the jet and across; the main wheels on its `height`.
    let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
    let mut wheel_lo = f32::MAX;
    for p in &all {
        for t in &p.tris {
            for v in t.1 {
                if p.name.starts_with("Main_tyre") {
                    wheel_lo = wheel_lo.min(v[1]);
                }
                if p.top != "pilot" && p.top != "cockpit" {
                    lo = [0, 1, 2].map(|k| lo[k].min(v[k]));
                    hi = [0, 1, 2].map(|k| hi[k].max(v[k]));
                }
            }
        }
    }
    ensure!(wheel_lo < f32::MAX, "MiG-29.ac: no main wheels");
    // The original's whole length (its body and parts: its body alone lacks the stabilators); FlightGear's model is
    // the real jet's size, as the original's length is.
    let (olo, ohi) = bounds(orig)?;
    let s = (ohi[2] - olo[2]) / (hi[2] - lo[2]);
    let height = o.helpers.iter().find(|h| h.0 == "height").context("no height helper")?.1[1];
    let shift = [
        (olo[0] + ohi[0]) / 2.0 - s * (lo[0] + hi[0]) / 2.0,
        height - s * wheel_lo,
        (olo[2] + ohi[2]) / 2.0 - s * (lo[2] + hi[2]) / 2.0,
    ];
    let place = |v: V| add(scale(v, s), shift);
    let place_fg = |v: V| place(fg(v));
    for p in &mut all {
        for t in &mut p.tris {
            t.1 = t.1.map(place);
        }
    }

    // The gear doors: shut in LdgDrUp, open in LdgDr.
    let mut nodes: Vec<Node> = Vec::new();
    let mut dr = Node { name: "LdgDr".into(), at: [0.0; 3], tris: Vec::new() };
    let mut dr_up = Node { name: "LdgDrUp".into(), at: [0.0; 3], tris: Vec::new() };
    for (names, (a, b), deg) in DOORS {
        let (c, axis) = (place_fg(*a), norm(sub(fg(*b), fg(*a))));
        let door: Vec<Tri> = all.iter().filter(|p| p.is(names)).flat_map(|p| p.tris.clone()).collect();
        ensure!(!door.is_empty(), "MiG-29.ac: no {names:?}");
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

    // The moving parts, each about its hinge.
    let mut helpers: Vec<(String, V)> = o.helpers.clone();
    for (part, names, hinge) in PARTS {
        let tris: Vec<Tri> = all.iter().filter(|p| p.is(names)).flat_map(|p| p.tris.clone()).collect();
        ensure!(!tris.is_empty(), "MiG-29.ac: no {names:?}");
        all.retain(|p| !p.is(names));
        let mid = scale(tris.iter().flat_map(|t| t.1).fold([0.0; 3], add), 1.0 / (3 * tris.len()) as f32);
        let at = match hinge {
            Some((a, b)) => {
                let (a, b) = (place_fg(*a), place_fg(*b));
                let mut axis = norm(sub(b, a));
                if o.axes.get(*part).is_some_and(|oa| dot(*oa, axis) < 0.0) {
                    axis = scale(axis, -1.0);
                }
                // The pivot: the hinge line's point nearest the part's middle; a gear leg's at MiG-29.xml's own
                // point, the leg's top (the main legs' slanted hinge passes the middle well outside the leg).
                let pivot = if part.starts_with("Ldg") { a } else { add(a, scale(axis, dot(sub(mid, a), axis))) };
                let t0 = (-dot(pivot, axis)).max(0.0) + 0.05;
                helpers.push((format!("{part}1"), add(pivot, scale(axis, t0))));
                helpers.push((format!("{part}2"), add(pivot, scale(axis, t0 + 1.0))));
                pivot
            }
            None => mid,
        };
        nodes.push(Node { name: part.to_string(), at, tris });
    }
    let crew: Vec<Tri> = all.iter().filter(|p| p.top == "pilot").flat_map(|p| p.tris.clone()).collect();
    all.retain(|p| p.top != "pilot");
    let crew_at = scale(crew.iter().flat_map(|t| t.1).fold([0.0; 3], add), 1.0 / (3 * crew.len().max(1)) as f32);
    nodes.push(Node { name: "pilot".into(), at: crew_at, tris: crew });
    nodes.push(dr);
    nodes.push(dr_up);
    nodes.push(chute(orig)?);
    for side in ["Parach1", "Parach2"] {
        helpers.retain(|h| h.0 != side);
    }
    let pa = nodes.last().map_or([0.0; 3], |n| n.at);
    helpers.push(("Parach1".into(), add(pa, [-0.49, 0.0, 0.0])));
    helpers.push(("Parach2".into(), add(pa, [0.49, 0.0, 0.0])));

    // The afterburners: EngineL/R at each nozzle's exit, EngineL1/R1 up by its radius.
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

    let mut body =
        Node { name: "mig29".into(), at: [0.0; 3], tris: all.into_iter().flat_map(|p| p.tris).collect::<Vec<Tri>>() };
    let mut pylons = Vec::new();
    for (st, len) in PYLON_LEN {
        let at = o.helpers.iter().find(|h| h.0 == st).with_context(|| format!("no {st}"))?.1;
        pylons.extend(pylon(at, &body.tris, len).with_context(|| format!("no skin above {st}"))?);
    }
    body.tris.extend(pylons);
    let triangles = body.tris.len() + nodes.iter().map(|n| n.tris.len()).sum::<usize>();
    let mut images = Vec::new();
    for (_, ours) in TEXTURES {
        let bytes = match atlases.iter().find(|a| a.0 == *ours) {
            Some(a) => a.1.clone(),
            None => std::fs::read(src.join(ours))?,
        };
        images.push((*ours, bytes, "image/png"));
    }
    for (name, pic) in [("insignia_clip", roundel(128)), ("flag_clip", flag(192))] {
        let mut png = Vec::new();
        pic.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)?;
        images.push((name, png, "image/png"));
    }
    let glb = write_glb(
        body,
        o.root_translation,
        nodes,
        helpers,
        &images,
        "FlightGear MiG-29 9-12: Enrique Laso Leon, Sergey Salov (GPL-3.0)",
    )?;
    if let Some(d) = out.parent() {
        std::fs::create_dir_all(d)?;
    }
    std::fs::write(out, &glb)?;
    Ok((triangles, glb.len(), s))
}

/// The lowest skin straight above (x, z) higher than `y0`, None where there is none.
fn skin_above(x: f32, z: f32, y0: f32, tris: &[Tri]) -> Option<f32> {
    let mut best: Option<f32> = None;
    for (_, [a, b, c], _, _) in tris {
        let d = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2]);
        if d.abs() < 1e-9 {
            continue;
        }
        let l0 = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / d;
        let l1 = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / d;
        let l2 = 1.0 - l0 - l1;
        if l0 < 0.0 || l1 < 0.0 || l2 < 0.0 {
            continue;
        }
        let y = l0 * a[1] + l1 * b[1] + l2 * c[1];
        if y > y0 && best.is_none_or(|b| y < b) {
            best = Some(y);
        }
    }
    best
}

/// Each station's pylon length (m), as the real MiG-29's three a wing: the original's stations D / F, C / G and
/// B / H are the real inner, middle and outer pylons (inner and middle long, reaching forward of the leading edge
/// as the real ones do); A / I, outboard of the real outer pylon, take a short stub; E the centre line tank's pylon.
const PYLON_LEN: [(&str, f32); 9] = [
    ("StationA", 0.6),
    ("StationB", 1.3),
    ("StationC", 1.9),
    ("StationD", 2.1),
    ("StationE", 1.6),
    ("StationF", 2.1),
    ("StationG", 1.9),
    ("StationH", 1.3),
    ("StationI", 0.6),
];

/// Our pylon from the original's station `at` (its foot, where the store hangs) up to the skin: a fairing `len`
/// long at the foot, its top on the skin from the first skin aft of the foot's front, swept back past the foot's
/// rear (the original's inner stations lie ahead of FlightGear's wing: their pylons reach back to it).
fn pylon(at: V, skin: &[Tri], len: f32) -> Option<Vec<Tri>> {
    const HALF_W: f32 = 0.06;
    let (x, y, z) = (at[0], at[1], at[2]);
    let (z0, z1) = (z - len * 0.45, z + len * 0.55);
    let top0 = (0..120).map(|k| z0 + 0.05 * k as f32).find(|zz| skin_above(x, *zz, y, skin).is_some())?;
    let top1 = (z1 + 0.1).max(top0 + 0.4);
    // Each top corner a little inside the skin (no gap where the skin curves).
    let ytop = |zz: f32| skin_above(x, zz, y, skin).or_else(|| skin_above(x, top0, y, skin)).map(|v| v + 0.03);
    let (ya, yb) = (ytop(top0)?, ytop(top1)?);
    let bottom = [[z0, y], [z1, y]];
    let top = [[top1, yb], [top0, ya]];
    // The side outline (z, y): bottom front, bottom back, top back, top front.
    let outline = [bottom[0], bottom[1], top[0], top[1]];
    let p = |k: usize, side: f32| -> V { [x + side * HALF_W, outline[k][1], outline[k][0]] };
    let mat = crate::f15::Mat { texture: "", rgba: [158, 161, 158, 255], two_sided: false };
    let mut tris = Vec::new();
    let mut quad = |a: V, b: V, c: V, d: V| {
        let n = norm(crate::f15::cross(sub(b, a), sub(c, a)));
        tris.push((mat.clone(), [a, b, c], [n; 3], [[0.0; 2]; 3]));
        tris.push((mat.clone(), [a, c, d], [n; 3], [[0.0; 2]; 3]));
    };
    quad(p(0, 1.0), p(1, 1.0), p(2, 1.0), p(3, 1.0)); // the right side
    quad(p(3, -1.0), p(2, -1.0), p(1, -1.0), p(0, -1.0)); // the left side
    for k in 0..4 {
        let j = (k + 1) % 4;
        quad(p(j, 1.0), p(k, 1.0), p(k, -1.0), p(j, -1.0)); // the edges: bottom, back, top, front
    }
    Some(tris)
}

/// The bounds of the original's meshes (its body and parts, by their nodes' translations), but the crew, the gear
/// doors, the chute and the afterburner markers.
fn bounds(orig: &Path) -> Result<(V, V)> {
    let g: Value = serde_json::from_slice(&std::fs::read(orig.join("mig29_h.gltf"))?)?;
    let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
    let skip = ["pilot", "Parach", "LdgDr", "EndWingL", "EndWingR", "EngineL", "EngineR"];
    for n in g["nodes"].as_array().context("nodes")? {
        if n["mesh"].is_null() || skip.iter().any(|k| n["name"] == *k) {
            continue;
        }
        let at: V = [12, 13, 14].map(|k| n["matrix"][k].as_f64().unwrap_or(0.0) as f32);
        let prims = g["meshes"][n["mesh"].as_u64().unwrap_or(0) as usize]["primitives"].as_array();
        for p in prims.into_iter().flatten() {
            let a = &g["accessors"][p["attributes"]["POSITION"].as_u64().unwrap_or(0) as usize];
            for k in 0..3 {
                lo[k] = lo[k].min(at[k] + a["min"][k].as_f64().unwrap_or(0.0) as f32);
                hi[k] = hi[k].max(at[k] + a["max"][k].as_f64().unwrap_or(0.0) as f32);
            }
        }
    }
    Ok((lo, hi))
}

/// The Insignia object's two stars (stacked in MiG-29_2.png's corner) drawn with our markings instead: each
/// triangle's uvs mapped from its half of the object's uv box onto the picture; the ones on the fins (facing
/// sideways) take the flag, as the original's fins, the wings' the roundel.
fn insignia(tris: &mut [Tri]) {
    let uvs = || tris.iter().flat_map(|t| t.3);
    let (u0, u1) = uvs().fold((f32::MAX, f32::MIN), |m, uv| (m.0.min(uv[0]), m.1.max(uv[0])));
    let (v0, v1) = uvs().fold((f32::MAX, f32::MIN), |m, uv| (m.0.min(uv[1]), m.1.max(uv[1])));
    let vm = (v0 + v1) / 2.0;
    for t in tris {
        let upper = t.3.iter().map(|uv| uv[1]).sum::<f32>() / 3.0 < vm;
        let (a, b) = if upper { (v0, vm) } else { (vm, v1) };
        t.3 = t.3.map(|uv| [(uv[0] - u0) / (u1 - u0), (uv[1] - a) / (b - a)]);
        let fin = norm(add(add(t.2[0], t.2[1]), t.2[2]))[1].abs() < 0.5;
        t.0.texture = if fin { "flag_clip" } else { "insignia_clip" };
    }
}

/// The Syrian colours (the flag's: red, green; Wikimedia Commons' roundel and flag of Syria 1980–2024).
const RED: Rgba<u8> = Rgba([206, 17, 38, 255]);
const GREEN: Rgba<u8> = Rgba([0, 122, 61, 255]);
const WHITE: Rgba<u8> = Rgba([245, 245, 245, 255]);
const BLACK: Rgba<u8> = Rgba([20, 20, 20, 255]);

/// True inside a five-pointed star of outer radius `r` round (cx, cy), a point up (picture coordinates, y down).
fn in_star(x: f32, y: f32, cx: f32, cy: f32, r: f32) -> bool {
    let corner = |k: usize| {
        let a = std::f32::consts::PI * (k as f32 / 5.0 - 0.5);
        let rr = if k.is_multiple_of(2) { r } else { r * 0.382 };
        (cx + rr * a.cos(), cy + rr * a.sin())
    };
    let mut inside = false;
    for k in 0..10 {
        let ((xa, ya), (xb, yb)) = (corner(k), corner((k + 1) % 10));
        if (ya > y) != (yb > y) && x < xa + (y - ya) / (yb - ya) * (xb - xa) {
            inside = !inside;
        }
    }
    inside
}

/// The Syrian roundel (1980–2024, as the original MiG-29's): red outside, a white ring with two green stars, a black
/// centre; transparent round it.
fn roundel(n: u32) -> RgbaImage {
    RgbaImage::from_fn(n, n, |x, y| {
        let (px, py) = ((x as f32 + 0.5) / n as f32 * 2.0 - 1.0, (y as f32 + 0.5) / n as f32 * 2.0 - 1.0);
        match px.hypot(py) {
            r if r > 0.95 => Rgba([0, 0, 0, 0]),
            r if r > 0.74 => RED,
            _ if in_star(px, py, -0.53, 0.0, 0.13) || in_star(px, py, 0.53, 0.0, 0.13) => GREEN,
            r if r > 0.30 => WHITE,
            _ => BLACK,
        }
    })
}

/// The Syrian flag (3 : 2, red, white with two green stars, black) across the middle of a square picture, for the
/// fins' square insignia: transparent above and below.
fn flag(n: u32) -> RgbaImage {
    RgbaImage::from_fn(n, n, |x, y| {
        let (u, v) = ((x as f32 + 0.5) / n as f32, ((y as f32 + 0.5) / n as f32 - 1.0 / 6.0) * 1.5);
        match v {
            v if !(0.0..1.0).contains(&v) => Rgba([0, 0, 0, 0]),
            v if v < 1.0 / 3.0 => RED,
            v if v >= 2.0 / 3.0 => BLACK,
            _ if in_star(u * 1.5, v, 0.5, 0.5, 0.13) || in_star(u * 1.5, v, 1.0, 0.5, 0.13) => GREEN,
            _ => WHITE,
        }
    })
}

/// The Syrian MiG-29s' two-tone grey (The War Zone's close-up photos, docs/aircraft-models.md §7; the original model's `mig-29.png`: light grey
/// with large dark blotches above, light below), sRGB.
const CAMO_LIGHT: [f32; 3] = [166.0, 169.0, 165.0];
const CAMO_DARK: [f32; 3] = [88.0, 93.0, 94.0];
const UNDERSIDE: [f32; 3] = [192.0, 195.0, 196.0];
/// FlightGear's paint colours we repaint (its base grey, green blotches, light greys and the white number panels),
/// each within PAINT_TOL.
const FG_PAINT: &[[f32; 3]] = &[
    [149.0, 157.0, 159.0],
    [119.0, 142.0, 130.0],
    [134.0, 150.0, 145.0],
    [211.0, 211.0, 210.0],
    [225.0, 225.0, 225.0],
    [231.0, 231.0, 233.0],
];
const PAINT_TOL: f32 = 22.0;
/// Objects not repainted: the gear, nozzles, intake tunnels, the insignia.
const UNPAINTED: &[&str] = &["Main_", "Nose_", "Gear_", "Fork", "Mud_", "Nozzle", "engtun", "Insignia", "FP-", "FPK"];

/// Smooth value noise in 3D (0..1), our camouflage's pattern.
fn noise(p: V) -> f32 {
    let h = |x: i32, y: i32, z: i32| {
        let mut n = (x as u32).wrapping_mul(0x8da6_b343)
            ^ (y as u32).wrapping_mul(0xd816_3841)
            ^ (z as u32).wrapping_mul(0xcb1a_b31f);
        n = (n ^ (n >> 13)).wrapping_mul(0x5bd1_e995);
        ((n ^ (n >> 15)) & 0xffff) as f32 / 65535.0
    };
    let f = p.map(f32::floor);
    let t = [0, 1, 2].map(|k| {
        let t = p[k] - f[k];
        t * t * (3.0 - 2.0 * t)
    });
    let (x, y, z) = (f[0] as i32, f[1] as i32, f[2] as i32);
    let lerp = |a: f32, b: f32, t: f32| a + (b - a) * t;
    let mut c = [0.0f32; 4];
    for (k, cy) in c.iter_mut().enumerate() {
        let (dy, dz) = ((k & 1) as i32, (k >> 1) as i32);
        *cy = lerp(h(x, y + dy, z + dz), h(x + 1, y + dy, z + dz), t[0]);
    }
    lerp(lerp(c[0], c[1], t[1]), lerp(c[2], c[3], t[1]), t[2])
}

/// Dark where the pattern's two octaves pass the threshold: large blotches about 3 m across.
fn camo_dark(p: V) -> bool {
    let q = scale(p, 0.33);
    noise(q) * 0.7 + noise(scale(q, 2.3)) * 0.3 > 0.48
}

/// Repaints FlightGear's grey-green livery (`img`, the atlas `tex`) as the Syrian two-tone grey: every texel of the
/// skin (`pieces` in our frame) whose colour is one of FG_PAINT takes CAMO_LIGHT / CAMO_DARK by our pattern where the
/// surface faces up or sideways, UNDERSIDE where it faces down; its shading kept (the texel's lightness over its
/// paint colour's).
fn repaint(img: &mut RgbaImage, tex: &str, pieces: &[Piece]) {
    let (w, h) = img.dimensions();
    let src = img.clone();
    // FlightGear's green blotches also reach into the islands' padding (seen in the far mipmaps): light grey first.
    let near = |p: &Rgba<u8>, f: [f32; 3]| (0..3).map(|k| (p[k] as f32 - f[k]).abs()).fold(0.0, f32::max) < PAINT_TOL;
    for p in img.pixels_mut() {
        if near(p, FG_PAINT[1]) || near(p, FG_PAINT[2]) {
            *p = Rgba([CAMO_LIGHT[0] as u8, CAMO_LIGHT[1] as u8, CAMO_LIGHT[2] as u8, 255]);
        }
    }
    for p in pieces.iter().filter(|p| !UNPAINTED.iter().any(|u| p.name.starts_with(u))) {
        for (_, pos, nrm, uv) in p.tris.iter().filter(|t| t.0.texture == tex) {
            let px = uv.map(|t| [t[0] * w as f32, t[1] * h as f32]);
            let den = (px[1][1] - px[2][1]) * (px[0][0] - px[2][0]) + (px[2][0] - px[1][0]) * (px[0][1] - px[2][1]);
            if den.abs() < 1e-9 {
                continue;
            }
            let lo =
                |k: usize, n: u32| px.iter().map(|q| q[k]).fold(f32::MAX, f32::min).floor().clamp(0.0, n as f32) as u32;
            let hi =
                |k: usize, n: u32| px.iter().map(|q| q[k]).fold(f32::MIN, f32::max).ceil().clamp(0.0, n as f32) as u32;
            for ty in lo(1, h)..hi(1, h) {
                for tx in lo(0, w)..hi(0, w) {
                    let (qx, qy) = (tx as f32 + 0.5, ty as f32 + 0.5);
                    let l0 = ((px[1][1] - px[2][1]) * (qx - px[2][0]) + (px[2][0] - px[1][0]) * (qy - px[2][1])) / den;
                    let l1 = ((px[2][1] - px[0][1]) * (qx - px[2][0]) + (px[0][0] - px[2][0]) * (qy - px[2][1])) / den;
                    let l2 = 1.0 - l0 - l1;
                    if l0 < -0.02 || l1 < -0.02 || l2 < -0.02 {
                        continue;
                    }
                    let s = src.get_pixel(tx, ty);
                    let c = [s[0] as f32, s[1] as f32, s[2] as f32];
                    let Some(base) =
                        FG_PAINT.iter().find(|f| (0..3).map(|k| (c[k] - f[k]).abs()).fold(0.0, f32::max) < PAINT_TOL)
                    else {
                        continue;
                    };
                    let at = add(add(scale(pos[0], l0), scale(pos[1], l1)), scale(pos[2], l2));
                    let n = norm(add(add(scale(nrm[0], l0), scale(nrm[1], l1)), scale(nrm[2], l2)));
                    let paint = if n[1] < -0.3 {
                        UNDERSIDE
                    } else if camo_dark(at) {
                        CAMO_DARK
                    } else {
                        CAMO_LIGHT
                    };
                    let shade = (c.iter().sum::<f32>() / base.iter().sum::<f32>()).clamp(0.85, 1.1);
                    let v = paint.map(|p| (p * shade).round().clamp(0.0, 255.0) as u8);
                    img.put_pixel(tx, ty, Rgba([v[0], v[1], v[2], 255]));
                }
            }
        }
    }
}

/// The drag chute (`Parach`, shown only deployed): ours, an orange cone with a dome at the original chute's place and
/// within its bounds, open towards the jet.
fn chute(orig: &Path) -> Result<Node> {
    let g: Value = serde_json::from_slice(&std::fs::read(orig.join("mig29_h.gltf"))?)?;
    let nodes = g["nodes"].as_array().context("nodes")?;
    let n = nodes.iter().find(|n| n["name"] == "Parach").context("no Parach")?;
    let m = &n["matrix"];
    let at: V = [12, 13, 14].map(|k| m[k].as_f64().unwrap_or(0.0) as f32);
    let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
    for p in
        g["meshes"][n["mesh"].as_u64().context("Parach mesh")? as usize]["primitives"].as_array().into_iter().flatten()
    {
        let a = &g["accessors"][p["attributes"]["POSITION"].as_u64().unwrap_or(0) as usize];
        for k in 0..3 {
            lo[k] = lo[k].min(a["min"][k].as_f64().unwrap_or(0.0) as f32);
            hi[k] = hi[k].max(a["max"][k].as_f64().unwrap_or(0.0) as f32);
        }
    }
    // The cone: its apex at the attachment (the bounds' front middle), its rim at the back.
    let r = ((hi[0] - lo[0]).max(hi[1] - lo[1]) / 2.0).max(0.3);
    let (cx, cy) = ((lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0);
    let (z0, z1) = (lo[2], hi[2]);
    let apex = [cx, cy, z0];
    let rim_z = z1 - r * 0.4;
    let mat = crate::f15::Mat { texture: "", rgba: [230, 120, 40, 255], two_sided: true };
    let ring = |k: usize, rad: f32, z: f32| -> V {
        let a = k as f32 / 16.0 * std::f32::consts::TAU;
        [cx + rad * a.cos(), cy + rad * a.sin(), z]
    };
    let mut tris = Vec::new();
    for k in 0..16 {
        let (p, q) = (ring(k, r, rim_z), ring(k + 1, r, rim_z));
        let nrm = norm(add(sub(p, apex), sub(q, apex)));
        tris.push((mat.clone(), [apex, p, q], [nrm; 3], [[0.0; 2]; 3]));
        let (pd, qd) = (ring(k, r * 0.5, z1), ring(k + 1, r * 0.5, z1));
        tris.push((mat.clone(), [p, pd, qd], [[0.0, 0.0, 1.0]; 3], [[0.0; 2]; 3]));
        tris.push((mat.clone(), [p, qd, q], [[0.0, 0.0, 1.0]; 3], [[0.0; 2]; 3]));
        tris.push((mat.clone(), [[cx, cy, z1], qd, pd], [[0.0, 0.0, 1.0]; 3], [[0.0; 2]; 3]));
    }
    // The node at the original's Parach (positions in its root frame; the cone in the node's own frame).
    let tris = tris.into_iter().map(|t: Tri| (t.0, t.1.map(|v| add(v, at)), t.2, t.3)).collect();
    Ok(Node { name: "Parach".into(), at, tris })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_source_is_pinned() {
        for d in SOURCE {
            assert!(d.sha256.len() == 64 && d.url.contains(COMMIT), "{}", d.file);
        }
    }

    #[test]
    fn hinges_mirror_and_roundel_rings() {
        assert_eq!(mirror(AILERON).0, [4.136, 3.693, -0.144]);
        let r = roundel(64);
        assert_eq!(r.get_pixel(32, 32)[0], 20);
        assert_eq!(r.get_pixel(32, 15)[1], 245);
        assert_eq!(r.get_pixel(32, 3)[0], 206);
        assert_eq!(r.get_pixel(15, 31).0, GREEN.0, "a star in the white ring");
        let f = flag(96);
        assert_eq!((f.get_pixel(48, 5)[3], f.get_pixel(48, 20).0, f.get_pixel(48, 75).0), (0, RED.0, BLACK.0));
        assert_eq!(r.get_pixel(0, 0)[3], 0);
    }

    /// The whole build on the downloaded sources when a developer has them (assets/source/mig29).
    #[test]
    fn builds_from_the_sources() {
        let a = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets");
        let src = a.join("source/mig29");
        if !SOURCE.iter().all(|d| crate::thirdparty::file_done(&src, d)) || !a.join("converted/planes/mig29").is_dir() {
            eprintln!("skipped: no assets/source/mig29 or no converted MiG-29");
            return;
        }
        let out = std::env::temp_dir().join(format!("iaf-mig29-{}.glb", std::process::id()));
        let st = build(&src, &a.join("converted/planes/mig29"), &out).unwrap();
        std::fs::remove_file(&out).unwrap();
        assert!((15_000..40_000).contains(&st.0), "{} triangles", st.0);
        assert!((st.2 - 1.0).abs() < 0.1, "scale {}", st.2);
    }
}
