//! Windows enhanced metafiles (`.emf`) as used by the IAF menus: the TSD maps
//! (`menu/emf/82.emf`, `67.emf`, `73.emf`) and their `grid.emf` / `text.emf` overlays.
//!
//! Only the record types these files contain are interpreted (polygons, polylines, pens,
//! brushes, fonts, text and the window/viewport mapping). Every coordinate is resolved to
//! the picture frame, normalised to 0..1 on both axes (x right, y down), which is how
//! `PlayEnhMetaFile` stretches the frame onto the destination rectangle.

use crate::Error;

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
    Polygon { rings: Vec<Vec<[f32; 2]>>, pen: Option<Pen>, brush: Option<Rgb>, alternate: bool },
    Polyline { points: Vec<[f32; 2]>, pen: Pen },
    /// Text at a reference point (see `align`, GDI `TA_*` flags).
    Text { pos: [f32; 2], text: String, font: Font, color: Rgb, align: u32 },
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

struct Reader<'a>(&'a [u8]);

impl Reader<'_> {
    fn u32(&self, o: usize) -> Result<u32, Error> {
        self.0
            .get(o..o + 4)
            .map(|b| u32::from_le_bytes(b.try_into().unwrap()))
            .ok_or_else(|| Error::Format("emf: record truncated".into()))
    }
    fn i32(&self, o: usize) -> Result<i32, Error> {
        self.u32(o).map(|v| v as i32)
    }
    fn i16(&self, o: usize) -> Result<i16, Error> {
        self.0
            .get(o..o + 2)
            .map(|b| i16::from_le_bytes(b.try_into().unwrap()))
            .ok_or_else(|| Error::Format("emf: record truncated".into()))
    }
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
    let r = Reader(data);
    if r.u32(0)? != 1 || data.get(40..44) != Some(b" EMF") {
        return Err(Error::Format("not an enhanced metafile".into()));
    }
    let frame = [r.i32(24)?, r.i32(28)?, r.i32(32)?, r.i32(36)?];
    let device_px = [r.i32(72)?, r.i32(76)?];
    let device_mm = [r.i32(80)?, r.i32(84)?];
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
        let kind = r.u32(o)?;
        let size = r.u32(o + 4)? as usize;
        if size < 8 || o + size > data.len() {
            return Err(Error::Format(format!("emf: bad record size at {o:#x}")));
        }
        let pair = |a: usize| -> Result<[f32; 2], Error> { Ok([r.i32(o + a)? as f32, r.i32(o + a + 4)? as f32]) };
        match kind {
            14 => break, // EOF
            9 => map.win_ext = pair(8)?,
            10 => map.win_org = pair(8)?,
            11 => map.vp_ext = pair(8)?,
            12 => map.vp_org = pair(8)?,
            17 => map.anisotropic = matches!(r.u32(o + 8)?, 7 | 8), // MM_ISOTROPIC / MM_ANISOTROPIC
            19 => alternate = r.u32(o + 8)? == 1,
            22 => text_align = r.u32(o + 8)?,
            24 => text_color = rgb(r.u32(o + 8)?),
            38 => {
                // CREATEPEN: ih, LOGPEN { style, width.x, width.y, color }
                let ih = r.u32(o + 8)? as usize;
                let style = r.u32(o + 12)?;
                let p = (style & 0xf != 5).then(|| Pen { color: rgb(r.u32(o + 24).unwrap_or(0)), width: map.len_x(r.i32(o + 16).unwrap_or(0) as f32) });
                set(&mut objects, ih, Obj::Pen(p));
            }
            39 => {
                // CREATEBRUSHINDIRECT: ih, LOGBRUSH { style, color, hatch }
                let ih = r.u32(o + 8)? as usize;
                let style = r.u32(o + 12)?;
                set(&mut objects, ih, Obj::Brush((style != 1).then(|| rgb(r.u32(o + 16).unwrap_or(0)))));
            }
            82 => {
                // EXTCREATEFONTINDIRECTW: ih, LOGFONTW
                let ih = r.u32(o + 8)? as usize;
                let lf = o + 12;
                let height = r.i32(lf)? as f32;
                let weight = r.i32(lf + 16)?;
                let italic = data[lf + 20] != 0;
                let face: Vec<u16> = (0..32).map(|i| r.i16(lf + 28 + i * 2).unwrap_or(0) as u16).take_while(|&c| c != 0).collect();
                let f = Font { height: map.len_y(height), weight, italic, face: String::from_utf16_lossy(&face) };
                set(&mut objects, ih, Obj::Font(f));
            }
            37 => {
                let ih = r.u32(o + 8)?;
                let obj = if ih & 0x8000_0000 != 0 { stock(ih) } else { objects.get(ih as usize).cloned().flatten() };
                match obj {
                    Some(Obj::Pen(p)) => pen = p,
                    Some(Obj::Brush(b)) => brush = b,
                    Some(Obj::Font(f)) => font = f,
                    None => {}
                }
            }
            40 => {
                if let Some(slot) = objects.get_mut(r.u32(o + 8)? as usize) {
                    *slot = None;
                }
            }
            86 | 87 => {
                // POLYGON16 / POLYLINE16: bounds, count, POINTS
                let n = r.u32(o + 24)? as usize;
                let pts = (0..n)
                    .map(|i| Ok(map.point(r.i16(o + 28 + i * 4)? as f32, r.i16(o + 30 + i * 4)? as f32)))
                    .collect::<Result<Vec<_>, Error>>()?;
                if kind == 86 {
                    ops.push(Op::Polygon { rings: vec![pts], pen, brush, alternate });
                } else if let Some(pen) = pen {
                    ops.push(Op::Polyline { points: pts, pen });
                }
            }
            91 => {
                // POLYPOLYGON16: bounds, nPolys, total, counts[nPolys], POINTS
                let polys = r.u32(o + 24)? as usize;
                let mut p = o + 32 + polys * 4;
                let mut rings = Vec::with_capacity(polys);
                for i in 0..polys {
                    let n = r.u32(o + 32 + i * 4)? as usize;
                    let ring = (0..n)
                        .map(|k| Ok(map.point(r.i16(p + k * 4)? as f32, r.i16(p + 2 + k * 4)? as f32)))
                        .collect::<Result<Vec<_>, Error>>()?;
                    p += n * 4;
                    rings.push(ring);
                }
                ops.push(Op::Polygon { rings, pen, brush, alternate });
            }
            84 => {
                // EXTTEXTOUTW: bounds, mode, exScale, eyScale, EMRTEXT { ref, nChars, offString, ... }
                let reference = pair(36)?;
                let n = r.u32(o + 44)? as usize;
                let off = r.u32(o + 48)? as usize;
                let chars: Vec<u16> = (0..n).map(|i| r.i16(o + off + i * 2).unwrap_or(0) as u16).collect();
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

fn set(objects: &mut Vec<Option<Obj>>, ih: usize, obj: Obj) {
    if objects.len() <= ih {
        objects.resize(ih + 1, None);
    }
    objects[ih] = Some(obj);
}

#[cfg(test)]
mod tests {
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
            if let Some(super::Op::Text { text, font, .. }) = mf.ops.iter().find(|o| matches!(o, super::Op::Text { .. })) {
                println!("  first text {text:?} {font:?}");
            }
            assert!(!mf.ops.is_empty());
            assert!(lo[0] > -0.05 && hi[0] < 1.05 && lo[1] > -0.05 && hi[1] < 1.05);
        }
    }
}
