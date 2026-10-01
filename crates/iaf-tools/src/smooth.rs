//! Geometry refinement for the low-poly 1998 models:
//! crease-aware smooth normals + Phong tessellation (Boubekeur & Alexa 2008).
//!
//! Original vertices stay where they are; new vertices are pushed onto the
//! curved surface implied by the normals, which rounds silhouettes without
//! shrinking the model. Edges across a crease (or open edges) are kept
//! straight so neighbouring triangles never crack apart.

use std::collections::HashMap;

#[derive(Debug, Clone, Copy)]
pub struct Tri {
    pub p: [[f32; 3]; 3],
    pub n: [[f32; 3]; 3],
    pub uv: [[f32; 2]; 3],
    pub material: u32,
}

/// Faces meeting at more than this angle keep a hard edge.
pub const CREASE_DEGREES: f32 = 65.0;
/// How strongly new vertices follow the curved surface (0 = flat, 1 = full).
pub const SHAPE_FACTOR: f32 = 0.75;
/// Each triangle becomes `LEVEL * LEVEL` triangles.
pub const LEVEL: usize = 3;

type V3 = [f32; 3];

fn sub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn add(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}
fn scale(a: V3, s: f32) -> V3 {
    [a[0] * s, a[1] * s, a[2] * s]
}
fn dot(a: V3, b: V3) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn cross(a: V3, b: V3) -> V3 {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
fn normalize(a: V3) -> V3 {
    let l = dot(a, a).sqrt();
    if l > 1e-12 { scale(a, 1.0 / l) } else { [0.0, 1.0, 0.0] }
}

/// Position key that welds vertices duplicated for UV seams / materials.
fn key(p: V3) -> [i32; 3] {
    p.map(|c| (c * 1e4).round() as i32)
}

/// Recomputes per-corner normals: area-weighted average of the faces around
/// each (welded) position whose normal is within [`CREASE_DEGREES`].
pub fn smooth_normals(tris: &mut [Tri]) {
    let face_n: Vec<V3> = tris.iter().map(|t| cross(sub(t.p[1], t.p[0]), sub(t.p[2], t.p[0]))).collect();
    let mut around: HashMap<[i32; 3], Vec<usize>> = HashMap::new();
    for (i, t) in tris.iter().enumerate() {
        for p in t.p {
            around.entry(key(p)).or_default().push(i);
        }
    }
    let cos_limit = CREASE_DEGREES.to_radians().cos();
    let unit: Vec<V3> = face_n.iter().map(|&n| normalize(n)).collect();
    for i in 0..tris.len() {
        for c in 0..3 {
            let mut sum = [0.0; 3];
            for &j in &around[&key(tris[i].p[c])] {
                if dot(unit[i], unit[j]) >= cos_limit {
                    sum = add(sum, face_n[j]);
                }
            }
            tris[i].n[c] = normalize(sum);
        }
    }
}

fn edge_key(a: V3, b: V3) -> ([i32; 3], [i32; 3]) {
    let (a, b) = (key(a), key(b));
    if a < b { (a, b) } else { (b, a) }
}

/// Edges shared by exactly two triangles with matching normals at both ends
/// can bulge; everything else stays straight.
fn smooth_edges(tris: &[Tri]) -> Vec<[bool; 3]> {
    let mut edges: HashMap<([i32; 3], [i32; 3]), Vec<(usize, usize)>> = HashMap::new();
    for (i, t) in tris.iter().enumerate() {
        for e in 0..3 {
            edges.entry(edge_key(t.p[e], t.p[(e + 1) % 3])).or_default().push((i, e));
        }
    }
    let normal_at = |t: &Tri, p: V3| t.n[(0..3).find(|&c| key(t.p[c]) == key(p)).unwrap()];
    let same = |a: V3, b: V3| dot(a, b) > 0.9999;
    tris.iter()
        .map(|t| {
            let mut flags = [false; 3];
            for (e, flag) in flags.iter_mut().enumerate() {
                let (a, b) = (t.p[e], t.p[(e + 1) % 3]);
                let users = &edges[&edge_key(a, b)];
                if let [x, y] = users[..] {
                    let (t1, t2) = (&tris[x.0], &tris[y.0]);
                    *flag = same(normal_at(t1, a), normal_at(t2, a)) && same(normal_at(t1, b), normal_at(t2, b));
                }
            }
            flags
        })
        .collect()
}

fn phong(t: &Tri, w: [f32; 3]) -> V3 {
    let p = add(add(scale(t.p[0], w[0]), scale(t.p[1], w[1])), scale(t.p[2], w[2]));
    let mut q = [0.0; 3];
    for i in 0..3 {
        // Project the flat point onto the tangent plane of corner i.
        let proj = sub(p, scale(t.n[i], dot(sub(p, t.p[i]), t.n[i])));
        q = add(q, scale(proj, w[i]));
    }
    add(scale(p, 1.0 - SHAPE_FACTOR), scale(q, SHAPE_FACTOR))
}

/// Smooth normals, then tessellate every triangle into `LEVEL²` curved ones.
pub fn refine(tris: &[Tri]) -> Vec<Tri> {
    let mut tris = tris.to_vec();
    smooth_normals(&mut tris);
    let smooth = smooth_edges(&tris);
    let l = LEVEL as f32;
    let mut out = Vec::with_capacity(tris.len() * LEVEL * LEVEL);
    for (t, flags) in tris.iter().zip(&smooth) {
        // Grid point (i, j) has barycentrics w = (1 - (i+j)/L, i/L, j/L).
        let vert = |i: usize, j: usize| -> (V3, V3, [f32; 2]) {
            let w = [1.0 - (i + j) as f32 / l, i as f32 / l, j as f32 / l];
            // Edge e runs from corner e to corner e+1, so its opposite corner is (e + 2) % 3.
            let on_straight_edge = (0..3).any(|e| !flags[e] && w[(e + 2) % 3] < 1e-6);
            let flat = add(add(scale(t.p[0], w[0]), scale(t.p[1], w[1])), scale(t.p[2], w[2]));
            let p = if on_straight_edge { flat } else { phong(t, w) };
            let n = normalize(add(add(scale(t.n[0], w[0]), scale(t.n[1], w[1])), scale(t.n[2], w[2])));
            let uv = [0, 1].map(|k| t.uv[0][k] * w[0] + t.uv[1][k] * w[1] + t.uv[2][k] * w[2]);
            (p, n, uv)
        };
        let mut push = |a: (usize, usize), b: (usize, usize), c: (usize, usize)| {
            let (va, vb, vc) = (vert(a.0, a.1), vert(b.0, b.1), vert(c.0, c.1));
            out.push(Tri { p: [va.0, vb.0, vc.0], n: [va.1, vb.1, vc.1], uv: [va.2, vb.2, vc.2], material: t.material });
        };
        for i in 0..LEVEL {
            for j in 0..LEVEL - i {
                push((i, j), (i + 1, j), (i, j + 1));
                if i + j + 1 < LEVEL {
                    push((i + 1, j), (i + 1, j + 1), (i, j + 1));
                }
            }
        }
    }
    out
}
