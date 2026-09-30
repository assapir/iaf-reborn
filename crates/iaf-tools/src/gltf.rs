//! Write an IAF [`Model`] as glTF 2.0 (`.gltf` + `.bin` + PNG textures).
//!
//! Direct3D is left-handed; glTF is right-handed. We mirror Z and reverse the
//! triangle winding (verified against the stored normals: after the mirror the
//! original order is clockwise, glTF wants counter-clockwise).

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use iaf_formats::model::{Frame, Material, Mesh, Model};
use image::RgbaImage;
use serde_json::{Value, json};

use crate::smooth::{self, Tri};
use crate::upscale;

/// Palette colour the original engine treats as transparent.
pub const COLOR_KEY: [u8; 3] = [0, 255, 255];

/// Frames that only carry positions for the engine (hinge axes, weapon
/// stations, camera…) rather than visible geometry.
pub fn is_helper(frame: &Frame, siblings: &[Frame]) -> bool {
    let n = frame.name.as_str();
    if matches!(n, "Camera" | "height") || n.starts_with("Station") {
        return true;
    }
    let base = n.trim_end_matches(['1', '2']);
    base != n && siblings.iter().any(|s| s.name == base)
}

/// Finds a texture by case-insensitive name in the given folders.
pub fn find_texture(name: &str, dirs: &[PathBuf]) -> Option<PathBuf> {
    let lower = name.to_lowercase();
    dirs.iter().map(|d| d.join(&lower)).find(|p| p.is_file())
}

/// Loads a BMP/TGA and applies the cyan colour key for images without alpha.
pub fn load_texture(path: &Path) -> Result<(RgbaImage, bool)> {
    load_texture_keyed(path, &[COLOR_KEY])
}

/// Colour keys used by the cockpit art: the 8-bit palettes use pure cyan, the
/// 24-bit panels (0, 210, 255).
pub const COCKPIT_KEYS: &[[u8; 3]] = &[COLOR_KEY, [0, 210, 255]];

/// Like [`load_texture`], with explicit colour keys.
pub fn load_texture_keyed(path: &Path, keys: &[[u8; 3]]) -> Result<(RgbaImage, bool)> {
    let img = image::open(path).with_context(|| format!("decoding {}", path.display()))?;
    let has_alpha = img.color().has_alpha();
    let mut rgba = img.to_rgba8();
    let mut transparent = has_alpha && rgba.pixels().any(|p| p[3] < 255);
    if !has_alpha {
        for p in rgba.pixels_mut() {
            if keys.iter().any(|k| p.0[0..3] == *k) {
                p[3] = 0;
                transparent = true;
            }
        }
    }
    Ok((rgba, transparent))
}

#[derive(Default)]
struct Builder {
    /// Resample textures 4× (see [`upscale`]).
    upscale: bool,
    /// Smooth normals + Phong tessellation (see [`smooth`]).
    smooth: bool,
    bin: Vec<u8>,
    buffer_views: Vec<Value>,
    accessors: Vec<Value>,
    meshes: Vec<Value>,
    nodes: Vec<Value>,
    materials: Vec<Value>,
    images: Vec<Value>,
    textures: Vec<Value>,
    /// texture file name (lower case) -> (texture index, has transparency)
    texture_cache: HashMap<String, Option<(usize, bool)>>,
    material_cache: HashMap<String, usize>,
    warnings: Vec<String>,
}

fn mirror_matrix(m: &[f32; 16]) -> [f32; 16] {
    // D3D row-major/row-vector memory layout == glTF column-major/column-vector.
    // Then conjugate by S = diag(1, 1, -1): negate elements with exactly one Z index.
    let mut out = *m;
    for i in [2, 6, 8, 9, 11, 14] {
        out[i] = -out[i];
    }
    out
}

impl Builder {
    fn push_view(&mut self, bytes: &[u8], target: Option<u32>) -> usize {
        while self.bin.len() % 4 != 0 {
            self.bin.push(0);
        }
        let offset = self.bin.len();
        self.bin.extend_from_slice(bytes);
        let mut view = json!({ "buffer": 0, "byteOffset": offset, "byteLength": bytes.len() });
        if let Some(t) = target {
            view["target"] = json!(t);
        }
        self.buffer_views.push(view);
        self.buffer_views.len() - 1
    }

    fn push_floats<const N: usize>(&mut self, data: &[[f32; N]], kind: &str, bounds: bool) -> usize {
        let bytes: Vec<u8> = data.iter().flatten().flat_map(|f| f.to_le_bytes()).collect();
        let view = self.push_view(&bytes, Some(34962));
        let mut acc = json!({ "bufferView": view, "componentType": 5126, "count": data.len(), "type": kind });
        if bounds {
            let mut min = [f32::MAX; N];
            let mut max = [f32::MIN; N];
            for v in data {
                for i in 0..N {
                    min[i] = min[i].min(v[i]);
                    max[i] = max[i].max(v[i]);
                }
            }
            acc["min"] = json!(min.as_slice());
            acc["max"] = json!(max.as_slice());
        }
        self.accessors.push(acc);
        self.accessors.len() - 1
    }

    fn push_indices(&mut self, data: &[u32]) -> usize {
        let bytes: Vec<u8> = data.iter().flat_map(|i| i.to_le_bytes()).collect();
        let view = self.push_view(&bytes, Some(34963));
        self.accessors.push(json!({ "bufferView": view, "componentType": 5125, "count": data.len(), "type": "SCALAR" }));
        self.accessors.len() - 1
    }

    fn texture(&mut self, name: &str, dirs: &[PathBuf], out_dir: &Path) -> Option<(usize, bool)> {
        let key = name.to_lowercase();
        if let Some(t) = self.texture_cache.get(&key) {
            return *t;
        }
        let result = match find_texture(name, dirs).map(|p| load_texture(&p)) {
            Some(Ok((img, transparent))) => {
                let img = if self.upscale { upscale::upscale(&img) } else { img };
                let file = format!("{}.png", key.rsplit_once('.').map_or(key.as_str(), |(s, _)| s));
                match img.save(out_dir.join(&file)) {
                    Ok(()) => {
                        self.images.push(json!({ "uri": file }));
                        self.textures.push(json!({ "source": self.images.len() - 1, "sampler": 0 }));
                        Some((self.textures.len() - 1, transparent))
                    }
                    Err(e) => {
                        self.warnings.push(format!("saving {file}: {e}"));
                        None
                    }
                }
            }
            Some(Err(e)) => {
                self.warnings.push(format!("{e:#}"));
                None
            }
            None => {
                self.warnings.push(format!("texture {name} not found"));
                None
            }
        };
        self.texture_cache.insert(key, result);
        result
    }

    fn material(&mut self, m: &Material, dirs: &[PathBuf], out_dir: &Path) -> usize {
        let key = format!("{:?}", (&m.name, m.diffuse.map(f32::to_bits), &m.texture));
        if let Some(&i) = self.material_cache.get(&key) {
            return i;
        }
        let name = m.name.clone().unwrap_or_else(|| format!("material{}", self.materials.len()));
        let name = name.strip_prefix("x3ds_mat_").unwrap_or(&name).to_string();
        let texture = m.texture.as_deref().and_then(|t| self.texture(t, dirs, out_dir));
        let mut pbr = json!({ "metallicFactor": 0.0, "roughnessFactor": 1.0 - (m.power / 100.0).clamp(0.0, 0.6) });
        match texture {
            Some((tex, _)) => pbr["baseColorTexture"] = json!({ "index": tex }),
            None => pbr["baseColorFactor"] = json!(m.diffuse),
        }
        let mut mat = json!({
            "name": name,
            "pbrMetallicRoughness": pbr,
            "doubleSided": name.contains("2side"),
        });
        if texture.is_some_and(|(_, transparent)| transparent) {
            mat["alphaMode"] = json!("MASK");
        }
        if m.emissive.iter().any(|&e| e > 0.0) && texture.is_none() {
            mat["emissiveFactor"] = json!(m.emissive);
        }
        self.materials.push(mat);
        self.material_cache.insert(key, self.materials.len() - 1);
        self.materials.len() - 1
    }

    fn mesh(&mut self, mesh: &Mesh, dirs: &[PathBuf], out_dir: &Path) -> Option<usize> {
        // Triangle soup in glTF space (Z mirrored, winding reversed), per-corner normals.
        let mut tris = Vec::new();
        for (fi, face) in mesh.faces.iter().enumerate() {
            let fnorm = mesh.face_normals.get(fi);
            let corner = |k: usize| {
                let v = face[k] as usize;
                let [x, y, z] = mesh.positions[v];
                let n = fnorm.and_then(|f| f.get(k)).and_then(|&n| mesh.normals.get(n as usize));
                let [nx, ny, nz] = n.copied().unwrap_or([0.0, 1.0, 0.0]);
                ([x, y, -z], [nx, ny, -nz], mesh.uvs.get(v).copied().unwrap_or([0.0, 0.0]))
            };
            // Fan-triangulate polygons.
            for k in 1..face.len().saturating_sub(1) {
                let (a, b, c) = (corner(0), corner(k + 1), corner(k));
                tris.push(Tri {
                    p: [a.0, b.0, c.0],
                    n: [a.1, b.1, c.1],
                    uv: [a.2, b.2, c.2],
                    material: mesh.face_materials.get(fi).copied().unwrap_or(0),
                });
            }
        }
        if self.smooth {
            tris = smooth::refine(&tris);
        }

        // Split by material, sharing identical corners.
        let mut groups: Vec<(u32, Vec<[f32; 3]>, Vec<[f32; 3]>, Vec<[f32; 2]>, Vec<u32>, HashMap<[u32; 8], u32>)> =
            Vec::new();
        for t in &tris {
            let gi = match groups.iter().position(|g| g.0 == t.material) {
                Some(i) => i,
                None => {
                    groups.push((t.material, vec![], vec![], vec![], vec![], HashMap::new()));
                    groups.len() - 1
                }
            };
            let g = &mut groups[gi];
            for c in 0..3 {
                let k = [t.p[c][0], t.p[c][1], t.p[c][2], t.n[c][0], t.n[c][1], t.n[c][2], t.uv[c][0], t.uv[c][1]]
                    .map(f32::to_bits);
                let idx = *g.5.entry(k).or_insert_with(|| {
                    g.1.push(t.p[c]);
                    g.2.push(t.n[c]);
                    g.3.push(t.uv[c]);
                    (g.1.len() - 1) as u32
                });
                g.4.push(idx);
            }
        }
        if groups.is_empty() {
            return None;
        }
        let mut primitives = Vec::new();
        for (mat, pos, nrm, uv, idx, _) in groups {
            let p = self.push_floats(&pos, "VEC3", true);
            let n = self.push_floats(&nrm, "VEC3", false);
            let mut attrs = json!({ "POSITION": p, "NORMAL": n });
            if !mesh.uvs.is_empty() {
                attrs["TEXCOORD_0"] = json!(self.push_floats(&uv, "VEC2", false));
            }
            let i = self.push_indices(&idx);
            let mut prim = json!({ "attributes": attrs, "indices": i });
            if let Some(m) = mesh.materials.get(mat as usize) {
                prim["material"] = json!(self.material(m, dirs, out_dir));
            }
            primitives.push(prim);
        }
        self.meshes.push(json!({ "name": mesh.name.clone().unwrap_or_default(), "primitives": primitives }));
        Some(self.meshes.len() - 1)
    }

    fn frame(&mut self, frame: &Frame, siblings: &[Frame], dirs: &[PathBuf], out_dir: &Path) -> usize {
        let helper = is_helper(frame, siblings);
        let children: Vec<usize> =
            frame.children.iter().map(|c| self.frame(c, &frame.children, dirs, out_dir)).collect();
        let mut node = json!({ "name": frame.name, "matrix": mirror_matrix(&frame.transform) });
        if helper {
            // Keep helper geometry as plain points for the engine (hinges, pylons…).
            let points: Vec<[f32; 3]> =
                frame.meshes.iter().flat_map(|m| m.positions.iter().map(|&[x, y, z]| [x, y, -z])).collect();
            node["extras"] = json!({ "iaf_helper": true, "points": points });
        } else {
            let mut meshes: Vec<usize> = frame.meshes.iter().filter_map(|m| self.mesh(m, dirs, out_dir)).collect();
            match meshes.len() {
                0 => {}
                1 => node["mesh"] = json!(meshes[0]),
                _ => {
                    // glTF allows one mesh per node: attach the rest as child nodes.
                    let first = meshes.remove(0);
                    node["mesh"] = json!(first);
                    let mut kids = children.clone();
                    for m in meshes {
                        self.nodes.push(json!({ "mesh": m }));
                        kids.push(self.nodes.len() - 1);
                    }
                    node["children"] = json!(kids);
                }
            }
        }
        if !children.is_empty() && node.get("children").is_none() {
            node["children"] = json!(children);
        }
        self.nodes.push(node);
        self.nodes.len() - 1
    }
}

/// Writes `<out_dir>/<name>.gltf`, `<name>.bin` and PNG textures.
/// `texture_dirs` are searched in order for texture files.
/// Returns warnings (missing textures etc.).
pub fn write_model(
    model: &Model,
    name: &str,
    texture_dirs: &[PathBuf],
    out_dir: &Path,
    upscale: bool,
    smooth: bool,
) -> Result<Vec<String>> {
    fs::create_dir_all(out_dir)?;
    let mut b = Builder { upscale, smooth, ..Default::default() };
    let roots: Vec<usize> = model.frames.iter().map(|f| b.frame(f, &model.frames, texture_dirs, out_dir)).collect();
    let bin_name = format!("{name}.bin");
    let doc = json!({
        "asset": { "version": "2.0", "generator": "iaf-reborn iaf-convert" },
        "scene": 0,
        "scenes": [{ "name": name, "nodes": roots }],
        "nodes": b.nodes,
        "meshes": b.meshes,
        "materials": b.materials,
        "textures": b.textures,
        "images": b.images,
        // Nearest filtering keeps the 1998 look; the engine can swap in upscaled textures.
        "samplers": [{ "magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497 }],
        "accessors": b.accessors,
        "bufferViews": b.buffer_views,
        "buffers": [{ "uri": bin_name, "byteLength": b.bin.len() }],
    });
    fs::write(out_dir.join(&bin_name), &b.bin)?;
    fs::write(out_dir.join(format!("{name}.gltf")), serde_json::to_string_pretty(&doc)?)?;
    Ok(b.warnings)
}
