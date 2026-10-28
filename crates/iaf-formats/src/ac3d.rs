//! AC3D (`.ac`) models, the format of FlightGear's aircraft (docs/aircraft-models.md §6): a text file of
//! `MATERIAL` lines and a tree of `OBJECT`s, each with its name, texture, `loc` (and `rot`) relative to its parent,
//! vertices and surfaces. [`parse`] flattens the tree: every object's vertices in the file's frame, its parents' names
//! in `path`. Polygons only (surface type 0); lines and closed lines are dropped.

use crate::Error;

#[derive(Debug, Clone, PartialEq)]
pub struct Material {
    pub name: String,
    pub rgb: [f32; 3],
    /// 0 opaque … 1 invisible.
    pub trans: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Surface {
    pub mat: usize,
    /// Smooth shaded (flag 0x10); else flat.
    pub smooth: bool,
    /// Both sides drawn (flag 0x20).
    pub two_sided: bool,
    /// (vertex index, u, v), in the file's order.
    pub refs: Vec<(usize, [f32; 2])>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Object {
    pub name: String,
    /// The names of its parents, outermost first (the world object and unnamed ones left out).
    pub path: Vec<String>,
    pub texture: Option<String>,
    /// Smoothing angle in degrees (AC3D's default 61).
    pub crease: f32,
    /// In the file's frame (parents' `loc` / `rot` applied).
    pub verts: Vec<[f32; 3]>,
    pub surfaces: Vec<Surface>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Model {
    pub materials: Vec<Material>,
    pub objects: Vec<Object>,
}

/// An object's frame in the file's: rotation rows, translation.
type Frame = ([[f32; 3]; 3], [f32; 3]);
/// An object whose kids are being read: its name (empty for the world), its frame, the kids still to come.
type Open = (String, Frame, usize);

fn bad(line: usize, what: &str) -> Error {
    Error::Format(format!("AC3D line {}: {what}", line + 1))
}

/// Parses an AC3D file's text.
pub fn parse(text: &str) -> Result<Model, Error> {
    let lines: Vec<&str> = text.lines().collect();
    if !lines.first().is_some_and(|l| l.starts_with("AC3D")) {
        return Err(bad(0, "no AC3D header"));
    }
    let mut m = Model::default();
    let mut i = 1;
    while i < lines.len() && !lines[i].starts_with("OBJECT") {
        if let Some(rest) = lines[i].strip_prefix("MATERIAL") {
            m.materials.push(material(rest).ok_or_else(|| bad(i, "bad MATERIAL"))?);
        }
        i += 1;
    }
    // (object, its frame: rotation rows and translation, number of kids left)
    let ident = ([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]], [0.0; 3]);
    let mut stack: Vec<Open> = Vec::new();
    while i < lines.len() {
        if lines[i].trim().is_empty() {
            i += 1;
            continue;
        }
        if !lines[i].starts_with("OBJECT") {
            return Err(bad(i, "OBJECT expected"));
        }
        let world = lines[i].split_whitespace().nth(1) == Some("world");
        i += 1;
        let mut o = Object { crease: 61.0, ..Default::default() };
        let (mut rot, mut loc) = ident;
        let mut local: Vec<[f32; 3]> = Vec::new();
        let kids;
        loop {
            let l = *lines.get(i).ok_or_else(|| bad(i, "file ends inside an OBJECT"))?;
            let w: Vec<&str> = l.split_whitespace().collect();
            i += 1;
            let f = |k: usize| w.get(k).and_then(|s| s.parse::<f32>().ok()).ok_or_else(|| bad(i - 1, "number"));
            match w.first().copied().unwrap_or("") {
                "name" => o.name = unquote(l[4..].trim()),
                "texture" => o.texture = Some(unquote(l[7..].trim())),
                "crease" => o.crease = f(1)?,
                "loc" => loc = [f(1)?, f(2)?, f(3)?],
                "rot" => rot = [[f(1)?, f(4)?, f(7)?], [f(2)?, f(5)?, f(8)?], [f(3)?, f(6)?, f(9)?]],
                "data" => i += 1,
                "numvert" => {
                    let n = f(1)? as usize;
                    for k in 0..n {
                        let v: Vec<f32> = lines
                            .get(i + k)
                            .ok_or_else(|| bad(i + k, "vertex"))?
                            .split_whitespace()
                            .take(3)
                            .filter_map(|s| s.parse().ok())
                            .collect();
                        let [x, y, z] = v[..] else { return Err(bad(i + k, "vertex")) };
                        local.push([x, y, z]);
                    }
                    i += n;
                }
                "numsurf" => {
                    for _ in 0..f(1)? as usize {
                        let (s, next) = surface(&lines, i)?;
                        i = next;
                        if let Some(s) = s {
                            o.surfaces.push(s);
                        }
                    }
                }
                "kids" => {
                    kids = f(1)? as usize;
                    break;
                }
                _ => {}
            }
        }
        // This object's frame in the file's: the parent's applied to its own.
        let (prot, ploc) = stack.last().map_or(ident, |s| s.1);
        let mul = |r: &[[f32; 3]; 3], v: [f32; 3]| [0, 1, 2].map(|k| r[k][0] * v[0] + r[k][1] * v[1] + r[k][2] * v[2]);
        let frame_rot = [0, 1, 2].map(|r| [0, 1, 2].map(|c| (0..3).map(|k| prot[r][k] * rot[k][c]).sum()));
        let pl = mul(&prot, loc);
        let frame_loc = [ploc[0] + pl[0], ploc[1] + pl[1], ploc[2] + pl[2]];
        o.verts = local
            .iter()
            .map(|v| {
                let r = mul(&frame_rot, *v);
                [r[0] + frame_loc[0], r[1] + frame_loc[1], r[2] + frame_loc[2]]
            })
            .collect();
        o.path = stack.iter().map(|s| s.0.clone()).filter(|n| !n.is_empty()).collect();
        let name = if world { String::new() } else { o.name.clone() };
        m.objects.push(o);
        if let Some(top) = stack.last_mut() {
            top.2 -= 1;
        }
        stack.push((name, (frame_rot, frame_loc), kids));
        while stack.last().is_some_and(|s| s.2 == 0) {
            stack.pop();
        }
    }
    for o in &mut m.objects {
        o.surfaces.retain(|s| s.mat < m.materials.len() && s.refs.iter().all(|r| r.0 < o.verts.len()));
    }
    Ok(m)
}

fn unquote(s: &str) -> String {
    s.trim_matches('"').to_string()
}

fn material(rest: &str) -> Option<Material> {
    let (name, rest) = rest.trim().strip_prefix('"')?.split_once('"')?;
    let w: Vec<&str> = rest.split_whitespace().collect();
    let num = |key: &str, k: usize| w.iter().position(|t| *t == key).and_then(|p| w.get(p + k)?.parse::<f32>().ok());
    Some(Material {
        name: name.to_string(),
        rgb: [num("rgb", 1)?, num("rgb", 2)?, num("rgb", 3)?],
        trans: num("trans", 1).unwrap_or(0.0),
    })
}

/// One `SURF` block from line `i`: the surface (None for lines) and the line after it.
fn surface(lines: &[&str], mut i: usize) -> Result<(Option<Surface>, usize), Error> {
    let flags = lines
        .get(i)
        .and_then(|l| l.strip_prefix("SURF"))
        .map(|f| f.trim().trim_start_matches("0x").trim_start_matches("0X"))
        .and_then(|h| u32::from_str_radix(h, 16).ok())
        .ok_or_else(|| bad(i, "SURF expected"))?;
    i += 1;
    let mut mat = 0;
    loop {
        let l = lines.get(i).ok_or_else(|| bad(i, "file ends inside a SURF"))?;
        i += 1;
        if let Some(m) = l.strip_prefix("mat") {
            mat = m.trim().parse().map_err(|_| bad(i - 1, "mat"))?;
        } else if let Some(n) = l.strip_prefix("refs") {
            let n: usize = n.trim().parse().map_err(|_| bad(i - 1, "refs"))?;
            let mut refs = Vec::with_capacity(n);
            for k in 0..n {
                let w: Vec<&str> = lines.get(i + k).ok_or_else(|| bad(i + k, "ref"))?.split_whitespace().collect();
                let v = w.first().and_then(|s| s.parse().ok()).ok_or_else(|| bad(i + k, "ref"))?;
                let uv = |k: usize| w.get(k).and_then(|s| s.parse().ok()).unwrap_or(0.0);
                refs.push((v, [uv(1), uv(2)]));
            }
            i += n;
            let poly = flags & 0xf == 0;
            let s = Surface { mat, smooth: flags & 0x10 != 0, two_sided: flags & 0x20 != 0, refs };
            return Ok((poly.then_some(s), i));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "AC3Db
MATERIAL \"a\" rgb 1 0.5 0  amb 0.2 0.2 0.2  emis 0 0 0  spec 0 0 0  shi 0  trans 0.25
OBJECT world
kids 1
OBJECT group
name \"wing\"
loc 1 0 0
kids 2
OBJECT poly
name \"flap\"
loc 0 2 0
texture \"skin.png\"
crease 45.000000
numvert 3
0 0 0
1 0 0
0 0 1
numsurf 2
SURF 0x30
mat 0
refs 3
0 0 0
1 1 0
2 0 1
SURF 0x2
mat 0
refs 2
0 0 0
1 1 0
kids 0
OBJECT poly
name \"tip\"
numvert 1
5 5 5
numsurf 0
kids 0
";

    #[test]
    fn flattens_the_tree() {
        let m = parse(SAMPLE).unwrap();
        assert_eq!(m.materials, [Material { name: "a".into(), rgb: [1.0, 0.5, 0.0], trans: 0.25 }]);
        let flap = m.objects.iter().find(|o| o.name == "flap").unwrap();
        assert_eq!(flap.path, ["wing"]);
        assert_eq!(flap.texture.as_deref(), Some("skin.png"));
        assert_eq!(flap.crease, 45.0);
        assert_eq!(flap.verts, [[1.0, 2.0, 0.0], [2.0, 2.0, 0.0], [1.0, 2.0, 1.0]]);
        assert_eq!(flap.surfaces.len(), 1, "the line is dropped");
        let s = &flap.surfaces[0];
        assert!(s.smooth && s.two_sided && s.refs[2] == (2, [0.0, 1.0]));
        let tip = m.objects.iter().find(|o| o.name == "tip").unwrap();
        assert_eq!(tip.verts, [[6.0, 5.0, 5.0]], "the group's loc only");
    }

    #[test]
    fn rejects_other_files() {
        assert!(parse("OBJECT world").is_err());
    }
}
