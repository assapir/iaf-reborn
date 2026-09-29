//! Typed view of IAF 3D models (DirectX `.X` Frame / Mesh / Material templates).

use crate::Error;
use crate::xfile::{Values, XObject};

#[derive(Debug, Clone)]
pub struct Material {
    pub name: Option<String>,
    pub diffuse: [f32; 4],
    pub power: f32,
    pub specular: [f32; 3],
    pub emissive: [f32; 3],
    pub texture: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct Mesh {
    pub name: Option<String>,
    pub positions: Vec<[f32; 3]>,
    /// Polygons as vertex indices (usually triangles).
    pub faces: Vec<Vec<u32>>,
    pub normals: Vec<[f32; 3]>,
    /// Per face, per corner index into `normals` (parallel to `faces`).
    pub face_normals: Vec<Vec<u32>>,
    /// Per vertex texture coordinates.
    pub uvs: Vec<[f32; 2]>,
    /// Per face index into `materials`.
    pub face_materials: Vec<u32>,
    pub materials: Vec<Material>,
}

#[derive(Debug, Clone)]
pub struct Frame {
    pub name: String,
    /// Row-major, row-vector convention (Direct3D): translation in elements 12..15.
    pub transform: [f32; 16],
    pub meshes: Vec<Mesh>,
    pub children: Vec<Frame>,
}

#[derive(Debug, Clone, Default)]
pub struct Model {
    /// Top-level frames (for `.x` files without frames, a single synthetic root).
    pub frames: Vec<Frame>,
}

const IDENTITY: [f32; 16] = [1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.];

fn parse_material(o: &XObject) -> Result<Material, Error> {
    let mut v = Values::new(&o.values);
    let diffuse = v.floats::<4>()?;
    let power = v.float()?;
    let specular = v.floats::<3>()?;
    let emissive = v.floats::<3>()?;
    let texture = match o.child("TextureFilename") {
        Some(t) => Some(Values::new(&t.values).string()?.to_string()),
        None => None,
    };
    Ok(Material { name: o.name.clone(), diffuse, power, specular, emissive, texture })
}

fn parse_face_list(v: &mut Values, count: u32) -> Result<Vec<Vec<u32>>, Error> {
    (0..count)
        .map(|_| {
            let n = v.int()?;
            (0..n).map(|_| v.int()).collect()
        })
        .collect()
}

fn parse_mesh(o: &XObject, globals: &[Material]) -> Result<Mesh, Error> {
    let mut v = Values::new(&o.values);
    let nverts = v.int()?;
    let positions = (0..nverts).map(|_| v.floats::<3>()).collect::<Result<_, _>>()?;
    let nfaces = v.int()?;
    let faces = parse_face_list(&mut v, nfaces)?;
    let mut mesh = Mesh { name: o.name.clone(), positions, faces, ..Default::default() };

    if let Some(n) = o.child("MeshNormals") {
        let mut v = Values::new(&n.values);
        let count = v.int()?;
        mesh.normals = (0..count).map(|_| v.floats::<3>()).collect::<Result<_, _>>()?;
        let nf = v.int()?;
        mesh.face_normals = parse_face_list(&mut v, nf)?;
    }
    if let Some(t) = o.child("MeshTextureCoords") {
        let mut v = Values::new(&t.values);
        let count = v.int()?;
        mesh.uvs = (0..count).map(|_| v.floats::<2>()).collect::<Result<_, _>>()?;
    }
    if let Some(m) = o.child("MeshMaterialList") {
        let mut v = Values::new(&m.values);
        let _nmat = v.int()?;
        let nidx = v.int()?;
        mesh.face_materials = (0..nidx).map(|_| v.int()).collect::<Result<_, _>>()?;
        // Materials are either inline or `{ name }` references to top-level ones.
        for inline in m.children_of("Material") {
            mesh.materials.push(parse_material(inline)?);
        }
        for r in &m.refs {
            let mat = globals
                .iter()
                .find(|g| g.name.as_deref() == Some(r))
                .ok_or_else(|| Error::Format(format!("unknown material reference {r}")))?;
            mesh.materials.push(mat.clone());
        }
        // A single-index list applies to every face.
        if mesh.face_materials.len() == 1 && mesh.faces.len() > 1 {
            mesh.face_materials = vec![mesh.face_materials[0]; mesh.faces.len()];
        }
    }
    Ok(mesh)
}

fn parse_frame(o: &XObject, globals: &[Material]) -> Result<Frame, Error> {
    let transform = match o.child("FrameTransformMatrix") {
        Some(m) => Values::new(&m.values).floats::<16>()?,
        None => IDENTITY,
    };
    let name = o.name.clone().unwrap_or_default();
    let name = name.strip_prefix("x3ds_").unwrap_or(&name).to_string();
    let meshes = o.children_of("Mesh").map(|m| parse_mesh(m, globals)).collect::<Result<_, _>>()?;
    let children = o.children_of("Frame").map(|f| parse_frame(f, globals)).collect::<Result<_, _>>()?;
    Ok(Frame { name, transform, meshes, children })
}

impl Model {
    pub fn from_x(objects: &[XObject]) -> Result<Self, Error> {
        let globals: Vec<Material> =
            objects.iter().filter(|o| o.template == "Material").map(parse_material).collect::<Result<_, _>>()?;
        let mut frames: Vec<Frame> =
            objects.iter().filter(|o| o.template == "Frame").map(|f| parse_frame(f, &globals)).collect::<Result<_, _>>()?;
        let loose: Vec<Mesh> =
            objects.iter().filter(|o| o.template == "Mesh").map(|m| parse_mesh(m, &globals)).collect::<Result<_, _>>()?;
        if !loose.is_empty() {
            frames.push(Frame { name: "root".into(), transform: IDENTITY, meshes: loose, children: Vec::new() });
        }
        Ok(Self { frames })
    }

    pub fn parse(data: &[u8]) -> Result<Self, Error> {
        Self::from_x(&crate::xfile::parse(data)?)
    }
}
