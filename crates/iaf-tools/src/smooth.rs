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
    let caps = find_caps(&tris);
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
    round_caps(&mut out, &caps);
    out
}

/// One cross-section ring of a loft: a near-regular polygon perpendicular to the loft's axis.
#[derive(Clone, Copy)]
struct Ring {
    t: f32,
    c: [f32; 2],
    r: f32,
    phase: f32,
}

/// A body built from coaxial rings (bomb, missile, tank, strut, tyre): along axis `k` (0 = x, 1 = y, 2 = z), every
/// ring with `n` sides.
struct Loft {
    k: usize,
    n: usize,
    rings: Vec<Ring>,
}

/// The two in-plane coordinates for axis `k`.
fn plane(p: V3, k: usize) -> [f32; 2] {
    match k {
        0 => [p[1], p[2]],
        1 => [p[2], p[0]],
        _ => [p[0], p[1]],
    }
}

/// Rings of 5–16 vertices in planes perpendicular to x, y or z (concentric rings in one plane are separated
/// by radius), joined into lofts of ≥ 2 coaxial rings with the same side count.
fn find_caps(tris: &[Tri]) -> Vec<Loft> {
    let mut pts: Vec<V3> = Vec::new();
    for t in tris {
        for p in t.p {
            if !pts.iter().any(|q| key(*q) == key(p)) {
                pts.push(p);
            }
        }
    }
    let size = pts.iter().fold(0f32, |m, p| m.max(p[0].abs()).max(p[1].abs()).max(p[2].abs())).max(1e-3);
    let tol = 2e-3 * size;
    let mut lofts = Vec::new();
    for k in 0..3 {
        // Planes along axis k.
        let mut planes: Vec<(f32, Vec<[f32; 2]>)> = Vec::new();
        for p in &pts {
            match planes.iter_mut().find(|(t, _)| (t - p[k]).abs() < tol) {
                Some(pl) => pl.1.push(plane(*p, k)),
                None => planes.push((p[k], vec![plane(*p, k)])),
            }
        }
        let mut rings: Vec<(usize, Ring)> = Vec::new();
        for (t, ps) in planes {
            if ps.len() < 5 {
                continue;
            }
            let before = rings.len();
            let c = ps.iter().fold([0.0f32; 2], |a, q| [a[0] + q[0], a[1] + q[1]]).map(|v| v / ps.len() as f32);
            // Concentric layers: cluster by distance from the centre.
            let mut ds: Vec<([f32; 2], f32)> = ps.iter().map(|q| (*q, ((q[0] - c[0]).powi(2) + (q[1] - c[1]).powi(2)).sqrt())).collect();
            ds.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
            let mut layer: Vec<([f32; 2], f32)> = Vec::new();
            let flush = |layer: &mut Vec<([f32; 2], f32)>, rings: &mut Vec<(usize, Ring)>| {
                let n = layer.len();
                if (5..=16).contains(&n) {
                    let r = layer.iter().map(|x| x.1).sum::<f32>() / n as f32;
                    let mut ang: Vec<f32> = layer.iter().map(|(q, _)| (q[1] - c[1]).atan2(q[0] - c[0])).collect();
                    ang.sort_by(|a, b| a.partial_cmp(b).unwrap());
                    let step = std::f32::consts::TAU / n as f32;
                    let even = (0..n).all(|i| {
                        let g = if i + 1 < n { ang[i + 1] - ang[i] } else { ang[0] + std::f32::consts::TAU - ang[n - 1] };
                        (g - step).abs() < 0.25 * step
                    });
                    if r > 1e-4 && even && layer.iter().all(|x| (x.1 - r).abs() < 0.08 * r) {
                        rings.push((n, Ring { t: 0.0, c, r, phase: ang[0] }));
                    }
                }
                layer.clear();
            };
            for d in ds {
                if d.1 < 1e-4 {
                    continue; // a centre vertex
                }
                if let Some(last) = layer.last() {
                    if d.1 > last.1 * 1.15 {
                        flush(&mut layer, &mut rings);
                    }
                }
                layer.push(d);
            }
            flush(&mut layer, &mut rings);
            for r in rings[before..].iter_mut() {
                r.1.t = t;
            }
        }
        // Join coaxial rings with the same side count into lofts (centres within 15 % of the radius).
        let mut used = vec![false; rings.len()];
        for i in 0..rings.len() {
            if used[i] {
                continue;
            }
            let (n, r0) = rings[i];
            let mut members = vec![r0];
            used[i] = true;
            for j in i + 1..rings.len() {
                let (m, r1) = rings[j];
                let dc = ((r1.c[0] - r0.c[0]).powi(2) + (r1.c[1] - r0.c[1]).powi(2)).sqrt();
                if !used[j] && m == n && dc < 0.15 * r0.r.max(r1.r) && (r1.t - r0.t).abs() > tol {
                    members.push(r1);
                    used[j] = true;
                }
            }
            if members.len() >= 2 {
                members.sort_by(|a, b| a.t.partial_cmp(&b.t).unwrap());
                lofts.push(Loft { k, n, rings: members });
            }
        }
    }
    lofts
}

/// Moves every point on a loft's surface (between its end rings, within its polygonal cross-section) out to the
/// circle through the polygon's corners: cross-sections become round. A pure function of position, so coincident
/// vertices of neighbouring triangles move together (no cracks); corners and points outside (fins) stay put.
fn round_caps(tris: &mut [Tri], lofts: &[Loft]) {
    use std::f32::consts::PI;
    for t in tris.iter_mut() {
        for p in t.p.iter_mut() {
            let mut best: Option<(f32, V3)> = None;
            for l in lofts {
                let tk = p[l.k];
                let (first, last) = (l.rings[0], l.rings[l.rings.len() - 1]);
                if tk < first.t - 1e-4 || tk > last.t + 1e-4 {
                    continue;
                }
                let i = l.rings.windows(2).position(|w| tk <= w[1].t + 1e-4).unwrap_or(0);
                let (a, b) = (l.rings[i], l.rings[(i + 1).min(l.rings.len() - 1)]);
                let f = if (b.t - a.t).abs() > 1e-6 { ((tk - a.t) / (b.t - a.t)).clamp(0.0, 1.0) } else { 0.0 };
                let c = [a.c[0] + (b.c[0] - a.c[0]) * f, a.c[1] + (b.c[1] - a.c[1]) * f];
                let r = a.r + (b.r - a.r) * f;
                let q = plane(*p, l.k);
                let (dx, dy) = (q[0] - c[0], q[1] - c[1]);
                let dist = (dx * dx + dy * dy).sqrt();
                if dist < 1e-6 {
                    continue;
                }
                let half = PI / l.n as f32;
                let phi = dy.atan2(dx) - a.phase;
                let ang = phi.rem_euclid(2.0 * half) - half;
                let rp = r * half.cos() / ang.cos();
                if dist > 1.03 * rp {
                    continue; // outside the body (fins, struts' brackets)
                }
                let s = r / rp;
                let nq = [c[0] + dx * s, c[1] + dy * s];
                let mut np = *p;
                match l.k {
                    0 => { np[1] = nq[0]; np[2] = nq[1]; }
                    1 => { np[2] = nq[0]; np[0] = nq[1]; }
                    _ => { np[0] = nq[0]; np[1] = nq[1]; }
                }
                // Several lofts may contain the point (concentric layers): the one whose surface it is nearest.
                let err = (dist - rp).abs() / rp;
                if best.is_none_or(|b| err < b.0) {
                    best = Some((err, np));
                }
            }
            if let Some((_, np)) = best {
                *p = np;
            }
        }
    }
}
