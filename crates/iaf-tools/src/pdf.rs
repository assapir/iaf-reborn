//! A small PDF writer: pages of filled shapes, lines, text in embedded TrueType fonts (Type0 / Identity-H, with a
//! ToUnicode map so the text can be searched and copied), JPEG and RGB images and internal links. The pilot guides'
//! PDFs (guide_pdf.rs) are drawn with it. Coordinates are points, from the page's top left, y down.

use anyhow::{Context, Result, bail};
use std::collections::BTreeMap;
use std::io::Write;

/// An sRGB colour, 0..1 per channel.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgb(pub f32, pub f32, pub f32);

impl Rgb {
    /// From 0xRRGGBB.
    pub const fn hex(v: u32) -> Rgb {
        Rgb(((v >> 16) & 255) as f32 / 255.0, ((v >> 8) & 255) as f32 / 255.0, (v & 255) as f32 / 255.0)
    }
}

/// A TrueType font's metrics and character map (the parts a PDF needs).
pub struct Font {
    pub data: &'static [u8],
    pub name: &'static str,
    upm: f32,
    /// hhea ascender / descender (positive down), in em.
    pub ascent: f32,
    pub descent: f32,
    cap: f32,
    bbox: [i16; 4],
    italic: f32,
    advances: Vec<u16>,
    cmap: BTreeMap<u32, u16>,
}

fn u16_at(d: &[u8], o: usize) -> u16 {
    u16::from_be_bytes([d[o], d[o + 1]])
}
fn i16_at(d: &[u8], o: usize) -> i16 {
    i16::from_be_bytes([d[o], d[o + 1]])
}
fn u32_at(d: &[u8], o: usize) -> u32 {
    u32::from_be_bytes([d[o], d[o + 1], d[o + 2], d[o + 3]])
}

impl Font {
    /// Parses `data` (a TrueType file). Panics on a malformed font: the fonts are the crate's own.
    pub fn parse(name: &'static str, data: &'static [u8]) -> Font {
        let table = |tag: &[u8; 4]| -> usize {
            (0..u16_at(data, 4) as usize)
                .map(|i| 12 + 16 * i)
                .find(|&r| &data[r..r + 4] == tag)
                .map(|r| u32_at(data, r + 8) as usize)
                .unwrap_or_else(|| panic!("{name}: no {} table", String::from_utf8_lossy(tag)))
        };
        let (head, hhea, hmtx, maxp, os2, post, cmap) = (
            table(b"head"),
            table(b"hhea"),
            table(b"hmtx"),
            table(b"maxp"),
            table(b"OS/2"),
            table(b"post"),
            table(b"cmap"),
        );
        let upm = u16_at(data, head + 18) as f32;
        let n_glyphs = u16_at(data, maxp + 4) as usize;
        let n_metrics = u16_at(data, hhea + 34) as usize;
        let advances = (0..n_glyphs).map(|g| u16_at(data, hmtx + 4 * g.min(n_metrics - 1))).collect();
        let mut map = BTreeMap::new();
        // The Windows Unicode subtables: format 12 (full) wins over format 4 (BMP).
        let mut subs: Vec<(u16, usize)> = (0..u16_at(data, cmap + 2) as usize)
            .map(|i| cmap + 4 + 8 * i)
            .filter(|&r| u16_at(data, r) == 3 && matches!(u16_at(data, r + 2), 1 | 10))
            .map(|r| {
                let at = cmap + u32_at(data, r + 4) as usize;
                (u16_at(data, at), at)
            })
            .collect();
        subs.sort();
        for (format, at) in subs {
            match format {
                4 => {
                    let segs = u16_at(data, at + 6) as usize / 2;
                    let (ends, starts) = (at + 14, at + 16 + 2 * segs);
                    let (deltas, ranges) = (starts + 2 * segs, starts + 4 * segs);
                    for s in 0..segs {
                        let (start, end) = (u16_at(data, starts + 2 * s) as u32, u16_at(data, ends + 2 * s) as u32);
                        let (delta, range) = (u16_at(data, deltas + 2 * s), u16_at(data, ranges + 2 * s) as usize);
                        for c in start..=end.min(0xfffe) {
                            let g = if range == 0 {
                                (c as u16).wrapping_add(delta)
                            } else {
                                let o = ranges + 2 * s + range + 2 * (c - start) as usize;
                                match u16_at(data, o) {
                                    0 => 0,
                                    g => g.wrapping_add(delta),
                                }
                            };
                            if g != 0 {
                                map.insert(c, g);
                            }
                        }
                    }
                }
                12 => {
                    for i in 0..u32_at(data, at + 12) as usize {
                        let g = at + 16 + 12 * i;
                        let (start, end, first) = (u32_at(data, g), u32_at(data, g + 4), u32_at(data, g + 8));
                        for c in start..=end {
                            map.insert(c, (first + c - start) as u16);
                        }
                    }
                }
                _ => {}
            }
        }
        Font {
            data,
            name,
            upm,
            ascent: i16_at(data, hhea + 4) as f32 / upm,
            descent: -(i16_at(data, hhea + 6) as f32) / upm,
            cap: if u16_at(data, os2) >= 2 { i16_at(data, os2 + 88) as f32 / upm } else { 0.7 },
            bbox: [i16_at(data, head + 36), i16_at(data, head + 38), i16_at(data, head + 40), i16_at(data, head + 42)],
            italic: u32_at(data, post + 4) as i32 as f32 / 65536.0,
            advances,
            cmap: map,
        }
    }

    pub fn glyph(&self, c: char) -> Option<u16> {
        self.cmap.get(&(c as u32)).copied()
    }

    /// Glyph `g`'s advance in em.
    pub fn advance(&self, g: u16) -> f32 {
        self.advances.get(g as usize).copied().unwrap_or(0) as f32 / self.upm
    }
}

/// An image to place: a JPEG as it is, or 8-bit RGB pixels.
pub enum Image {
    Jpeg { data: Vec<u8>, w: u32, h: u32, gray: bool },
    Rgb { pixels: Vec<u8>, w: u32, h: u32 },
}

impl Image {
    pub fn size(&self) -> (u32, u32) {
        match self {
            Image::Jpeg { w, h, .. } | Image::Rgb { w, h, .. } => (*w, *h),
        }
    }

    /// A JPEG's size and components from its start-of-frame marker.
    pub fn jpeg(data: Vec<u8>) -> Result<Image> {
        let mut i = 2;
        while i + 9 < data.len() {
            if data[i] != 0xff {
                bail!("JPEG: bad marker at {i}");
            }
            let m = data[i + 1];
            let len = u16_at(&data, i + 2) as usize;
            if (0xc0..=0xcf).contains(&m) && !matches!(m, 0xc4 | 0xc8 | 0xcc) {
                let (h, w) = (u16_at(&data, i + 5) as u32, u16_at(&data, i + 7) as u32);
                let gray = data[i + 9] == 1;
                return Ok(Image::Jpeg { data, w, h, gray });
            }
            i += 2 + len;
        }
        bail!("JPEG: no frame header")
    }
}

/// One drawing operation on a page.
#[derive(Clone)]
pub enum Op {
    Rect {
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        r: f32,
        fill: Option<Rgb>,
        stroke: Option<(Rgb, f32)>,
    },
    Line {
        x0: f32,
        y0: f32,
        x1: f32,
        y1: f32,
        color: Rgb,
        width: f32,
    },
    /// Glyphs of font `font` (each with the character it shows) from baseline point (x, y); `spacing` added after
    /// each glyph (letter spacing).
    Text {
        x: f32,
        y: f32,
        font: usize,
        size: f32,
        color: Rgb,
        glyphs: Vec<(u16, char)>,
        spacing: f32,
    },
    /// Image `img` into the box, its corners rounded by `r`.
    Image {
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        r: f32,
        img: usize,
    },
    /// A link to destination `dest` (a name given to Doc::dest).
    Link {
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        dest: String,
    },
}

pub const A4: (f32, f32) = (595.276, 841.89);

/// A document under construction: fonts, images, pages of ops, named destinations.
pub struct Doc<'f> {
    pub fonts: &'f [Font],
    pub images: Vec<Image>,
    pub pages: Vec<Vec<Op>>,
    dests: BTreeMap<String, (usize, f32)>,
    pub title: String,
}

/// The path of a rectangle with rounded corners (r 0: plain), PDF coordinates (y up, `y` its bottom).
fn rect_path(s: &mut String, x: f32, y: f32, w: f32, h: f32, r: f32) {
    use std::fmt::Write;
    let r = r.min(w / 2.0).min(h / 2.0);
    if r <= 0.0 {
        let _ = writeln!(s, "{x:.2} {y:.2} {w:.2} {h:.2} re");
        return;
    }
    let k = r * 0.5523; // the Bézier circle's handle
    let (x1, y1) = (x + w, y + h);
    let _ = writeln!(
        s,
        "{:.2} {y:.2} m {:.2} {y:.2} l {:.2} {y:.2} {x1:.2} {:.2} {x1:.2} {:.2} c {x1:.2} {:.2} l {x1:.2} {:.2} {:.2} {y1:.2} {:.2} {y1:.2} c \
         {:.2} {y1:.2} l {:.2} {y1:.2} {x:.2} {:.2} {x:.2} {:.2} c {x:.2} {:.2} l {x:.2} {:.2} {:.2} {y:.2} {:.2} {y:.2} c h",
        x + r,
        x1 - r,
        x1 - r + k,
        y + r - k,
        y + r,
        y1 - r,
        y1 - r + k,
        x1 - r + k,
        x1 - r,
        x + r,
        x + r - k,
        y1 - r + k,
        y1 - r,
        y + r,
        y + r - k,
        x + r - k,
        x + r,
    );
}

fn deflate(b: &[u8]) -> Vec<u8> {
    let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    z.write_all(b).expect("in memory");
    z.finish().expect("in memory")
}

impl<'f> Doc<'f> {
    pub fn new(fonts: &'f [Font], title: &str) -> Doc<'f> {
        Doc { fonts, images: vec![], pages: vec![], dests: BTreeMap::new(), title: title.into() }
    }

    pub fn dest(&mut self, name: &str, page: usize, y: f32) {
        self.dests.entry(name.into()).or_insert((page, y));
    }

    /// The finished file.
    pub fn write(&self) -> Result<Vec<u8>> {
        let mut objs: Vec<Vec<u8>> = vec![vec![], vec![]]; // 1 catalog, 2 page tree (filled at the end)
        fn push(objs: &mut Vec<Vec<u8>>, o: Vec<u8>) -> usize {
            objs.push(o);
            objs.len()
        }
        let stream = |dict: &str, data: Vec<u8>| {
            let mut o = format!("<< {dict} /Length {} >>\nstream\n", data.len()).into_bytes();
            o.extend(data);
            o.extend(b"\nendstream");
            o
        };
        // Fonts: each glyph a page shows, with its character (the text layer's map).
        let mut used: Vec<BTreeMap<u16, char>> = self.fonts.iter().map(|_| BTreeMap::new()).collect();
        for op in self.pages.iter().flatten() {
            if let Op::Text { font, glyphs, .. } = op {
                for &(g, c) in glyphs {
                    used[*font].entry(g).or_insert(c);
                }
            }
        }
        let mut font_ids = vec![0; self.fonts.len()];
        for (i, f) in self.fonts.iter().enumerate() {
            if used[i].is_empty() {
                continue;
            }
            let file =
                push(&mut objs, stream(&format!("/Filter /FlateDecode /Length1 {}", f.data.len()), deflate(f.data)));
            let em = |v: f32| (v * 1000.0).round() as i32;
            let s = |v: i16| (v as f32 * 1000.0 / f.upm).round() as i32;
            let flags = 32 + if f.italic != 0.0 { 64 } else { 0 };
            let desc = push(&mut objs, format!(
                "<< /Type /FontDescriptor /FontName /{} /Flags {flags} /FontBBox [{} {} {} {}] /ItalicAngle {} /Ascent {} \
                 /Descent {} /CapHeight {} /StemV 80 /FontFile2 {file} 0 R >>",
                f.name,
                s(f.bbox[0]),
                s(f.bbox[1]),
                s(f.bbox[2]),
                s(f.bbox[3]),
                f.italic,
                em(f.ascent),
                -em(f.descent),
                em(f.cap)
            )
            .into_bytes());
            let w: String =
                used[i].keys().map(|&g| format!("{g} [{}] ", em(f.advance(g)))).collect::<Vec<_>>().concat();
            let cid = push(
                &mut objs,
                format!(
                    "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /{} /CIDSystemInfo << /Registry (Adobe) /Ordering \
                 (Identity) /Supplement 0 >> /FontDescriptor {desc} 0 R /W [{w}] /CIDToGIDMap /Identity >>",
                    f.name
                )
                .into_bytes(),
            );
            let mut cmap = String::from(
                "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) \
                 /Ordering (UCS) /Supplement 0 >> def\n/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 \
                 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n",
            );
            let pairs: Vec<_> = used[i].iter().collect();
            for chunk in pairs.chunks(100) {
                cmap += &format!("{} beginbfchar\n", chunk.len());
                for (g, c) in chunk {
                    let u: String = c.encode_utf16(&mut [0; 2]).iter().map(|u| format!("{u:04X}")).collect();
                    cmap += &format!("<{g:04X}> <{u}>\n");
                }
                cmap += "endbfchar\n";
            }
            cmap += "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n";
            let to_uni = push(&mut objs, stream("/Filter /FlateDecode", deflate(cmap.as_bytes())));
            font_ids[i] = push(
                &mut objs,
                format!(
                    "<< /Type /Font /Subtype /Type0 /BaseFont /{} /Encoding /Identity-H /DescendantFonts [{cid} 0 R] \
                 /ToUnicode {to_uni} 0 R >>",
                    f.name
                )
                .into_bytes(),
            );
        }
        // Images.
        let mut img_ids = vec![];
        for img in &self.images {
            img_ids.push(push(
                &mut objs,
                match img {
                    Image::Jpeg { data, w, h, gray } => stream(
                        &format!(
                            "/Type /XObject /Subtype /Image /Width {w} /Height {h} /ColorSpace /{} /BitsPerComponent 8 \
                         /Filter /DCTDecode",
                            if *gray { "DeviceGray" } else { "DeviceRGB" }
                        ),
                        data.clone(),
                    ),
                    Image::Rgb { pixels, w, h } => stream(
                        &format!(
                            "/Type /XObject /Subtype /Image /Width {w} /Height {h} /ColorSpace /DeviceRGB \
                         /BitsPerComponent 8 /Filter /FlateDecode"
                        ),
                        deflate(pixels),
                    ),
                },
            ));
        }
        let res = {
            let fonts: String = font_ids
                .iter()
                .enumerate()
                .filter(|(_, id)| **id > 0)
                .map(|(i, id)| format!("/F{i} {id} 0 R "))
                .collect();
            let imgs: String = img_ids.iter().enumerate().map(|(i, id)| format!("/I{i} {id} 0 R ")).collect();
            push(&mut objs, format!("<< /Font << {fonts}>> /XObject << {imgs}>> >>").into_bytes())
        };
        // Pages: their ids are known before the links are written (a link names its target page).
        let first_page = objs.len() + 1;
        let page_id = |i: usize| first_page + 2 * i; // each page: the page, then its content
        let (pw, ph) = A4;
        let mut kids = String::new();
        for (pi, ops) in self.pages.iter().enumerate() {
            let mut s = String::new();
            let mut annots = String::new();
            let c = |c: Rgb| format!("{:.3} {:.3} {:.3}", c.0, c.1, c.2);
            for op in ops {
                match op {
                    Op::Rect { fill: None, stroke: None, .. } => {}
                    Op::Rect { x, y, w, h, r, fill, stroke } => {
                        s += "q ";
                        if let Some(f) = fill {
                            s += &format!("{} rg ", c(*f));
                        }
                        if let Some((col, lw)) = stroke {
                            s += &format!("{} RG {lw:.2} w ", c(*col));
                        }
                        // A stroke is drawn inside the box, as CSS's border.
                        let inset = stroke.map(|s| s.1 / 2.0).unwrap_or(0.0);
                        rect_path(&mut s, x + inset, ph - y - h + inset, w - 2.0 * inset, h - 2.0 * inset, *r);
                        s += match (fill.is_some(), stroke.is_some()) {
                            (true, true) => "B Q\n",
                            (true, false) => "f Q\n",
                            _ => "S Q\n",
                        };
                    }
                    Op::Line { x0, y0, x1, y1, color, width } => {
                        s += &format!(
                            "q {} RG {width:.2} w {x0:.2} {:.2} m {x1:.2} {:.2} l S Q\n",
                            c(*color),
                            ph - y0,
                            ph - y1
                        );
                    }
                    Op::Text { x, y, font, size, color, glyphs, spacing } => {
                        let hex: String = glyphs.iter().map(|(g, _)| format!("{g:04X}")).collect();
                        s += &format!(
                            "BT /F{font} {size:.2} Tf {} rg {spacing:.3} Tc {x:.2} {:.2} Td <{hex}> Tj ET\n",
                            c(*color),
                            ph - y
                        );
                    }
                    Op::Image { x, y, w, h, r, img } => {
                        s += "q ";
                        if *r > 0.0 {
                            rect_path(&mut s, *x, ph - y - h, *w, *h, *r);
                            s += " W n ";
                        }
                        s += &format!("{w:.2} 0 0 {h:.2} {x:.2} {:.2} cm /I{img} Do Q\n", ph - y - h);
                    }
                    Op::Link { x, y, w, h, dest } => {
                        let Some(&(p, dy)) = self.dests.get(dest) else { continue };
                        annots += &format!(
                            "<< /Type /Annot /Subtype /Link /Rect [{x:.2} {:.2} {:.2} {:.2}] /Border [0 0 0] /Dest [{} 0 \
                             R /XYZ 0 {:.2} null] >> ",
                            ph - y - h,
                            x + w,
                            ph - y,
                            page_id(p),
                            ph - dy
                        );
                    }
                }
            }
            let id = page_id(pi);
            let got = push(&mut objs, format!(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {pw:.3} {ph:.3}] /Resources {res} 0 R /Contents {} 0 R \
                 /Annots [{annots}] >>",
                id + 1
            )
            .into_bytes());
            assert_eq!(got, id);
            push(&mut objs, stream("/Filter /FlateDecode", deflate(s.as_bytes())));
            kids += &format!("{id} 0 R ");
        }
        objs[0] = b"<< /Type /Catalog /Pages 2 0 R >>".to_vec();
        objs[1] = format!("<< /Type /Pages /Kids [{kids}] /Count {} >>", self.pages.len()).into_bytes();
        let title: String = self.title.encode_utf16().map(|u| format!("{u:04X}")).collect();
        let info = objs.len() + 1;
        objs.push(format!("<< /Title <FEFF{title}> /Producer (iaf-tools guide_pdf) >>").into_bytes());
        let mut out = b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n".to_vec();
        let mut offsets = vec![];
        for (i, o) in objs.iter().enumerate() {
            offsets.push(out.len());
            writeln!(out, "{} 0 obj", i + 1)?;
            out.extend(o);
            out.extend(b"\nendobj\n");
        }
        let xref = out.len();
        write!(out, "xref\n0 {}\n0000000000 65535 f \n", objs.len() + 1)?;
        for o in offsets {
            writeln!(out, "{o:010} 00000 n ")?;
        }
        write!(out, "trailer\n<< /Size {} /Root 1 0 R /Info {info} 0 R >>\nstartxref\n{xref}\n%%EOF\n", objs.len() + 1)
            .context("writing the PDF")?;
        Ok(out)
    }
}
