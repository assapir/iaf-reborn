//! Windows enhanced metafiles (`.emf`) as used by the IAF menus: the TSD maps
//! (`menu/emf/82.emf`, `67.emf`, `73.emf`) and their `grid.emf` / `text.emf` overlays.
//!
//! Only the record types these files contain are interpreted (polygons, polylines, pens,
//! brushes, fonts, text and the window/viewport mapping). Every coordinate is resolved to
//! the picture frame, normalised to 0..1 on both axes (x right, y down), which is how
//! `PlayEnhMetaFile` stretches the frame onto the destination rectangle.

use crate::Error;
use crate::bytes::{i16_at, i32_at, u32_at};

/// RGB colour.
pub type Rgb = [u8; 3];

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Pen {
    pub color: Rgb,
    /// Width in frame units (0..1 of the frame width); 0 = one device pixel (cosmetic).
    pub width: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Font {
    /// Character height in frame units (0..1 of the frame height).
    pub height: f32,
    pub weight: i32,
    pub italic: bool,
    pub face: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Op {
    /// Filled polygon(s); several rings = `PolyPolygon` (filled with `alternate` rule).
    Polygon {
        rings: Vec<Vec<[f32; 2]>>,
        pen: Option<Pen>,
        brush: Option<Rgb>,
        alternate: bool,
    },
    Polyline {
        points: Vec<[f32; 2]>,
        pen: Pen,
    },
    /// Text at a reference point (see `align`, GDI `TA_*` flags).
    Text {
        pos: [f32; 2],
        text: String,
        font: Font,
        color: Rgb,
        align: u32,
    },
}

#[derive(Debug, Clone)]
pub struct Metafile {
    /// Picture frame in 0.01 mm (left, top, right, bottom).
    pub frame: [i32; 4],
    /// Reference device size in pixels and millimetres.
    pub device_px: [i32; 2],
    pub device_mm: [i32; 2],
    pub ops: Vec<Op>,
}

#[derive(Clone)]
enum Obj {
    Pen(Option<Pen>),
    Brush(Option<Rgb>),
    Font(Font),
}

fn rgb(c: u32) -> Rgb {
    [(c & 0xff) as u8, (c >> 8 & 0xff) as u8, (c >> 16 & 0xff) as u8]
}

/// Logical → device → frame mapping state.
struct Mapping {
    anisotropic: bool,
    win_org: [f32; 2],
    win_ext: [f32; 2],
    vp_org: [f32; 2],
    vp_ext: [f32; 2],
    /// Device pixel → normalised frame.
    px_to_frame: [f32; 2],
    frame_org: [f32; 2],
}

impl Mapping {
    fn device(&self, x: f32, y: f32) -> [f32; 2] {
        if self.anisotropic && self.win_ext[0] != 0.0 && self.win_ext[1] != 0.0 {
            [
                (x - self.win_org[0]) * self.vp_ext[0] / self.win_ext[0] + self.vp_org[0],
                (y - self.win_org[1]) * self.vp_ext[1] / self.win_ext[1] + self.vp_org[1],
            ]
        } else {
            [x, y]
        }
    }
    fn point(&self, x: f32, y: f32) -> [f32; 2] {
        let d = self.device(x, y);
        [d[0] * self.px_to_frame[0] - self.frame_org[0], d[1] * self.px_to_frame[1] - self.frame_org[1]]
    }
    /// A logical length along x (pen widths) or y (font heights) in frame units.
    fn len_x(&self, l: f32) -> f32 {
        let s = if self.anisotropic && self.win_ext[0] != 0.0 { self.vp_ext[0] / self.win_ext[0] } else { 1.0 };
        (l * s * self.px_to_frame[0]).abs()
    }
    fn len_y(&self, l: f32) -> f32 {
        let s = if self.anisotropic && self.win_ext[1] != 0.0 { self.vp_ext[1] / self.win_ext[1] } else { 1.0 };
        (l * s * self.px_to_frame[1]).abs()
    }
}

/// Stock objects (`GetStockObject` index | 0x80000000).
fn stock(index: u32) -> Option<Obj> {
    Some(match index & 0x7fff_ffff {
        0 => Obj::Brush(Some([255, 255, 255])),
        1 => Obj::Brush(Some([192, 192, 192])),
        2 => Obj::Brush(Some([128, 128, 128])),
        3 => Obj::Brush(Some([64, 64, 64])),
        4 => Obj::Brush(Some([0, 0, 0])),
        5 => Obj::Brush(None),
        6 => Obj::Pen(Some(Pen { color: [255, 255, 255], width: 0.0 })),
        7 => Obj::Pen(Some(Pen { color: [0, 0, 0], width: 0.0 })),
        8 => Obj::Pen(None),
        _ => return None,
    })
}

pub fn parse(data: &[u8]) -> Result<Metafile, Error> {
    if u32_at(data, 0)? != 1 || data.get(40..44) != Some(b" EMF") {
        return Err(Error::Format("not an enhanced metafile".into()));
    }
    let frame = [i32_at(data, 24)?, i32_at(data, 28)?, i32_at(data, 32)?, i32_at(data, 36)?];
    let device_px = [i32_at(data, 72)?, i32_at(data, 76)?];
    let device_mm = [i32_at(data, 80)?, i32_at(data, 84)?];
    let fw = (frame[2] - frame[0]).max(1) as f32;
    let fh = (frame[3] - frame[1]).max(1) as f32;
    let px_to_frame = [
        device_mm[0] as f32 * 100.0 / device_px[0].max(1) as f32 / fw,
        device_mm[1] as f32 * 100.0 / device_px[1].max(1) as f32 / fh,
    ];
    let mut map = Mapping {
        anisotropic: false,
        win_org: [0.0; 2],
        win_ext: [1.0; 2],
        vp_org: [0.0; 2],
        vp_ext: [1.0; 2],
        px_to_frame,
        frame_org: [frame[0] as f32 / fw, frame[1] as f32 / fh],
    };
    let mut objects: Vec<Option<Obj>> = Vec::new();
    let mut pen: Option<Pen> = Some(Pen { color: [0, 0, 0], width: 0.0 });
    let mut brush: Option<Rgb> = Some([255, 255, 255]);
    let mut font = Font { height: 0.02, weight: 400, italic: false, face: "Arial".into() };
    let mut text_color: Rgb = [0, 0, 0];
    let mut text_align = 0u32;
    let mut alternate = true;
    let mut ops = Vec::new();

    let mut o = 0usize;
    while o + 8 <= data.len() {
        let kind = u32_at(data, o)?;
        let size = u32_at(data, o + 4)? as usize;
        if size < 8 || o + size > data.len() {
            return Err(Error::Format(format!("emf: bad record size at {o:#x}")));
        }
        let pair = |a: usize| -> Result<[f32; 2], Error> {
            Ok([i32_at(data, o + a)? as f32, i32_at(data, o + a + 4)? as f32])
        };
        match kind {
            14 => break, // EOF
            9 => map.win_ext = pair(8)?,
            10 => map.win_org = pair(8)?,
            11 => map.vp_ext = pair(8)?,
            12 => map.vp_org = pair(8)?,
            17 => map.anisotropic = matches!(u32_at(data, o + 8)?, 7 | 8), // MM_ISOTROPIC / MM_ANISOTROPIC
            19 => alternate = u32_at(data, o + 8)? == 1,
            22 => text_align = u32_at(data, o + 8)?,
            24 => text_color = rgb(u32_at(data, o + 8)?),
            38 => {
                // CREATEPEN: ih, LOGPEN { style, width.x, width.y, color }
                let ih = u32_at(data, o + 8)? as usize;
                let style = u32_at(data, o + 12)?;
                let p = (style & 0xf != 5).then(|| Pen {
                    color: rgb(u32_at(data, o + 24).unwrap_or(0)),
                    width: map.len_x(i32_at(data, o + 16).unwrap_or(0) as f32),
                });
                set(&mut objects, ih, Obj::Pen(p));
            }
            39 => {
                // CREATEBRUSHINDIRECT: ih, LOGBRUSH { style, color, hatch }
                let ih = u32_at(data, o + 8)? as usize;
                let style = u32_at(data, o + 12)?;
                set(&mut objects, ih, Obj::Brush((style != 1).then(|| rgb(u32_at(data, o + 16).unwrap_or(0)))));
            }
            82 => {
                // EXTCREATEFONTINDIRECTW: ih, LOGFONTW
                let ih = u32_at(data, o + 8)? as usize;
                let lf = o + 12;
                let height = i32_at(data, lf)? as f32;
                let weight = i32_at(data, lf + 16)?;
                let italic = data[lf + 20] != 0;
                let face: Vec<u16> = (0..32)
                    .map(|i| i16_at(data, lf + 28 + i * 2).unwrap_or(0) as u16)
                    .take_while(|&c| c != 0)
                    .collect();
                let f = Font { height: map.len_y(height), weight, italic, face: String::from_utf16_lossy(&face) };
                set(&mut objects, ih, Obj::Font(f));
            }
            37 => {
                let ih = u32_at(data, o + 8)?;
                let obj = if ih & 0x8000_0000 != 0 { stock(ih) } else { objects.get(ih as usize).cloned().flatten() };
                match obj {
                    Some(Obj::Pen(p)) => pen = p,
                    Some(Obj::Brush(b)) => brush = b,
                    Some(Obj::Font(f)) => font = f,
                    None => {}
                }
            }
            40 => {
                if let Some(slot) = objects.get_mut(u32_at(data, o + 8)? as usize) {
                    *slot = None;
                }
            }
            86 | 87 => {
                // POLYGON16 / POLYLINE16: bounds, count, POINTS
                let n = u32_at(data, o + 24)? as usize;
                let pts = (0..n)
                    .map(|i| Ok(map.point(i16_at(data, o + 28 + i * 4)? as f32, i16_at(data, o + 30 + i * 4)? as f32)))
                    .collect::<Result<Vec<_>, Error>>()?;
                if kind == 86 {
                    ops.push(Op::Polygon { rings: vec![pts], pen, brush, alternate });
                } else if let Some(pen) = pen {
                    ops.push(Op::Polyline { points: pts, pen });
                }
            }
            91 => {
                // POLYPOLYGON16: bounds, nPolys, total, counts[nPolys], POINTS
                let polys = u32_at(data, o + 24)? as usize;
                let mut p = o + 32 + polys * 4;
                let mut rings = Vec::with_capacity(polys);
                for i in 0..polys {
                    let n = u32_at(data, o + 32 + i * 4)? as usize;
                    let ring = (0..n)
                        .map(|k| Ok(map.point(i16_at(data, p + k * 4)? as f32, i16_at(data, p + 2 + k * 4)? as f32)))
                        .collect::<Result<Vec<_>, Error>>()?;
                    p += n * 4;
                    rings.push(ring);
                }
                ops.push(Op::Polygon { rings, pen, brush, alternate });
            }
            84 => {
                // EXTTEXTOUTW: bounds, mode, exScale, eyScale, EMRTEXT { ref, nChars, offString, ... }
                let reference = pair(36)?;
                let n = u32_at(data, o + 44)? as usize;
                let off = u32_at(data, o + 48)? as usize;
                let chars: Vec<u16> = (0..n).map(|i| i16_at(data, o + off + i * 2).unwrap_or(0) as u16).collect();
                ops.push(Op::Text {
                    pos: map.point(reference[0], reference[1]),
                    text: String::from_utf16_lossy(&chars),
                    font: font.clone(),
                    color: text_color,
                    align: text_align,
                });
            }
            _ => {}
        }
        o += size;
    }
    Ok(Metafile { frame, device_px, device_mm, ops })
}

/// The region GDI fills for a `Polygon` / `PolyPolygon`, as triangles (three points each): every ring together as
/// one region under the fill mode, ALTERNATE (`alternate`, even-odd) or WINDING (non-zero). Rings may self-intersect
/// and overlap one another, as they do in the TSD maps.
///
/// A sweep in y: the slabs between successive vertex and edge-crossing heights hold no crossing, so in each one the
/// edges keep their left-to-right order and the filled spans lie between known edge pairs. A span bounded by the
/// same two edges in successive slabs grows into one trapezoid (two triangles).
pub fn fill_triangles(rings: &[Vec<[f32; 2]>], alternate: bool) -> Vec<[f32; 2]> {
    // Edges with a < b in y, and +1 / -1 for the ring's direction; horizontal edges bound no span.
    let mut edges: Vec<([f64; 2], [f64; 2], i32)> = Vec::new();
    for r in rings {
        for (i, p) in r.iter().enumerate() {
            let q = r[(i + 1) % r.len()];
            let (p, q) = ([p[0] as f64, p[1] as f64], [q[0] as f64, q[1] as f64]);
            if p[1] < q[1] {
                edges.push((p, q, 1));
            } else if p[1] > q[1] {
                edges.push((q, p, -1));
            }
        }
    }
    let x_at = |e: &([f64; 2], [f64; 2], i32), y: f64| e.0[0] + (e.1[0] - e.0[0]) * (y - e.0[1]) / (e.1[1] - e.0[1]);
    let mut ys: Vec<f64> = edges.iter().flat_map(|e| [e.0[1], e.1[1]]).collect();
    // ponytail: all-pairs crossing test, O(n²) per polygon; fine for the maps' rings (at most ~1500 points).
    for (i, e) in edges.iter().enumerate() {
        for f in &edges[i + 1..] {
            if e.1[1] <= f.0[1] || f.1[1] <= e.0[1] {
                continue;
            }
            let (r, s) = ([e.1[0] - e.0[0], e.1[1] - e.0[1]], [f.1[0] - f.0[0], f.1[1] - f.0[1]]);
            let d = r[0] * s[1] - r[1] * s[0];
            if d == 0.0 {
                continue; // parallel: equal x along a shared stretch, the span walk handles them
            }
            let w = [f.0[0] - e.0[0], f.0[1] - e.0[1]];
            let (t, u) = ((w[0] * s[1] - w[1] * s[0]) / d, (w[0] * r[1] - w[1] * r[0]) / d);
            if t > 0.0 && t < 1.0 && u > 0.0 && u < 1.0 {
                ys.push(e.0[1] + t * r[1]);
            }
        }
    }
    ys.sort_by(f64::total_cmp);
    ys.dedup();
    let mut out = Vec::new();
    let mut emit = |l: usize, r: usize, y0: f64, y1: f64| {
        let (el, er) = (&edges[l], &edges[r]);
        let p = |x: f64, y: f64| [x as f32, y as f32];
        let (lt, rt, rb, lb) = (p(x_at(el, y0), y0), p(x_at(er, y0), y0), p(x_at(er, y1), y1), p(x_at(el, y1), y1));
        // Zero-area triangles (a span's pointed end, a slab thinner than f32) are left out.
        for t in [[lt, rt, rb], [lt, rb, lb]] {
            if (t[1][0] - t[0][0]) * (t[2][1] - t[0][1]) != (t[2][0] - t[0][0]) * (t[1][1] - t[0][1]) {
                out.extend(t);
            }
        }
    };
    // Open trapezoids: (left edge, right edge, top y).
    let mut open: Vec<(usize, usize, f64)> = Vec::new();
    let mut active: Vec<(f64, usize)> = Vec::new();
    for w in ys.windows(2) {
        let (y0, y1) = (w[0], w[1]);
        let ym = 0.5 * (y0 + y1);
        active.clear();
        active.extend(
            edges.iter().enumerate().filter(|(_, e)| e.0[1] < ym && ym < e.1[1]).map(|(i, e)| (x_at(e, ym), i)),
        );
        active.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut spans: Vec<(usize, usize, f64)> = Vec::new();
        let (mut wind, mut left) = (0, 0);
        for &(_, i) in &active {
            let was = if alternate { wind & 1 != 0 } else { wind != 0 };
            wind += edges[i].2;
            let is = if alternate { wind & 1 != 0 } else { wind != 0 };
            if !was && is {
                left = i;
            } else if was && !is {
                let top = open.iter().find(|o| o.0 == left && o.1 == i).map_or(y0, |o| o.2);
                spans.push((left, i, top));
            }
        }
        for &(l, r, top) in &open {
            if !spans.iter().any(|s| s.0 == l && s.1 == r) {
                emit(l, r, top, y0);
            }
        }
        open = spans;
    }
    if let Some(&y) = ys.last() {
        for &(l, r, top) in &open {
            emit(l, r, top, y);
        }
    }
    out
}

fn set(objects: &mut Vec<Option<Obj>>, ih: usize, obj: Obj) {
    if objects.len() <= ih {
        objects.resize(ih + 1, None);
    }
    objects[ih] = Some(obj);
}

#[cfg(test)]
mod tests {
    fn area(tris: &[[f32; 2]]) -> f32 {
        tris.chunks(3)
            .map(|t| {
                ((t[1][0] - t[0][0]) * (t[2][1] - t[0][1]) - (t[2][0] - t[0][0]) * (t[1][1] - t[0][1])).abs() / 2.0
            })
            .sum()
    }

    /// GDI's fill rules: a hole (even-odd), a same-direction overlap (non-zero fills it) and a self-crossing bow tie.
    #[test]
    fn fill_rules() {
        let sq = |a: f32, b: f32| vec![[a, a], [b, a], [b, b], [a, b]];
        let rings = [sq(0.0, 4.0), sq(1.0, 3.0)];
        assert_eq!(area(&super::fill_triangles(&rings, true)), 12.0);
        assert_eq!(area(&super::fill_triangles(&rings, false)), 16.0);
        let bow = [vec![[0.0, 0.0], [2.0, 2.0], [2.0, 0.0], [0.0, 2.0]]];
        assert_eq!(area(&super::fill_triangles(&bow, false)), 2.0);
        // A spiral wound twice round the centre: non-zero fills the inner square, even-odd leaves it empty.
        let twice =
            [vec![[0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0], [0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0]]];
        assert_eq!(area(&super::fill_triangles(&twice, false)), 16.0);
        assert_eq!(area(&super::fill_triangles(&twice, true)), 0.0);
    }

    /// Parses the TSD maps of a local install (skipped when the install is absent).
    #[test]
    fn tsd_maps() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/install/resource/menu/emf");
        for name in ["82", "grid", "text"] {
            let Ok(data) = std::fs::read(dir.join(format!("{name}.emf"))) else { return };
            let mf = super::parse(&data).unwrap();
            let (mut lo, mut hi) = ([f32::MAX; 2], [f32::MIN; 2]);
            for op in &mf.ops {
                let pts: Vec<[f32; 2]> = match op {
                    super::Op::Polygon { rings, .. } => rings.concat(),
                    super::Op::Polyline { points, .. } => points.clone(),
                    super::Op::Text { pos, .. } => vec![*pos],
                };
                for p in pts {
                    for i in 0..2 {
                        lo[i] = lo[i].min(p[i]);
                        hi[i] = hi[i].max(p[i]);
                    }
                }
            }
            println!("{name}: {} ops, extent {lo:?}..{hi:?}", mf.ops.len());
            if let Some(super::Op::Text { text, font, .. }) =
                mf.ops.iter().find(|o| matches!(o, super::Op::Text { .. }))
            {
                println!("  first text {text:?} {font:?}");
            }
            assert!(!mf.ops.is_empty());
            assert!(lo[0] > -0.05 && hi[0] < 1.05 && lo[1] > -0.05 && hi[1] < 1.05);
        }
    }
}
