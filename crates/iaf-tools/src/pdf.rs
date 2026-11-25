//! The pilot guides' PDFs (guide_pdf.rs) as pages of drawing ops: filled shapes, lines, shaped text, pictures and
//! internal links, written by krilla (fonts subset and embedded, text searchable and copyable). Text is shaped with
//! rustybuzz. Coordinates are points, from the page's top left, y down.

use anyhow::{Result, anyhow};
use krilla::Document;
use krilla::annotation::{Annotation, LinkAnnotation, Target};
use krilla::color::rgb;
use krilla::destination::{Destination, XyzDestination};
use krilla::geom::{PathBuilder, Point, Rect, Size, Transform};
use krilla::image::Image as KImage;
use krilla::metadata::Metadata;
use krilla::num::NormalizedF32;
use krilla::page::PageSettings;
use krilla::paint::{Fill, Stroke};
use krilla::text::{GlyphId, KrillaGlyph};
use std::collections::BTreeMap;
use std::ops::Range;

/// An sRGB colour, 0..1 per channel.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgb(pub f32, pub f32, pub f32);

impl Rgb {
    /// From 0xRRGGBB.
    pub const fn hex(v: u32) -> Rgb {
        Rgb(((v >> 16) & 255) as f32 / 255.0, ((v >> 8) & 255) as f32 / 255.0, (v & 255) as f32 / 255.0)
    }

    fn color(self) -> rgb::Color {
        let c = |v: f32| (v * 255.0).round() as u8;
        rgb::Color::new(c(self.0), c(self.1), c(self.2))
    }
}

/// A font: krilla's for the PDF, rustybuzz's for shaping, and the line metrics the layout needs.
pub struct Font {
    pub pdf: krilla::text::Font,
    face: rustybuzz::Face<'static>,
    upm: f32,
    /// The ascent and descent a browser lays lines out with, in em: OS/2's typo values when the font asks for them
    /// (USE_TYPO_METRICS), else its Windows values.
    pub line_ascent: f32,
    pub line_descent: f32,
    /// A synthetic oblique's slant (x per y), for a family without an italic.
    pub slant: f32,
}

/// One shaped glyph: its id, the byte range of its cluster in the shaped text, its advance and offsets in em.
#[derive(Clone, Debug)]
pub struct Shaped {
    pub id: u16,
    pub cluster: Range<usize>,
    pub adv: f32,
    pub dx: f32,
    pub dy: f32,
}

impl Font {
    /// Parses `data` (a TrueType file). Panics on a malformed font: the fonts are the crate's own.
    pub fn parse(name: &str, data: &'static [u8]) -> Font {
        let face = rustybuzz::Face::from_slice(data, 0).unwrap_or_else(|| panic!("{name}: not a font"));
        let pdf = krilla::text::Font::new(data.into(), 0).unwrap_or_else(|| panic!("{name}: krilla refused it"));
        let upm = face.units_per_em() as f32;
        let os2 = face.tables().os2.unwrap_or_else(|| panic!("{name}: no OS/2 table"));
        let (a, d) = if os2.use_typographic_metrics() {
            (os2.typographic_ascender(), os2.typographic_descender())
        } else {
            (os2.windows_ascender(), os2.windows_descender())
        };
        Font { pdf, face, upm, line_ascent: a as f32 / upm, line_descent: -(d as f32) / upm, slant: 0.0 }
    }

    /// The same font drawn slanted (a browser's synthetic italic).
    pub fn oblique(self) -> Font {
        Font { slant: 0.2, ..self }
    }

    /// Whether the font has a glyph for `c`.
    pub fn has(&self, c: char) -> bool {
        self.face.glyph_index(c).is_some()
    }

    /// `text` shaped (ligatures, kerning, marks), in visual order; right to left when `rtl`.
    pub fn shape(&self, text: &str, rtl: bool) -> Vec<Shaped> {
        let mut buf = rustybuzz::UnicodeBuffer::new();
        buf.push_str(text);
        buf.guess_segment_properties();
        buf.set_direction(if rtl { rustybuzz::Direction::RightToLeft } else { rustybuzz::Direction::LeftToRight });
        let out = rustybuzz::shape(&self.face, &[], buf);
        let mut starts: Vec<usize> = out.glyph_infos().iter().map(|i| i.cluster as usize).collect();
        starts.sort_unstable();
        starts.dedup();
        out.glyph_infos()
            .iter()
            .zip(out.glyph_positions())
            .map(|(i, p)| {
                let start = i.cluster as usize;
                let end = starts.iter().copied().find(|&s| s > start).unwrap_or(text.len());
                Shaped {
                    id: i.glyph_id as u16,
                    cluster: start..end,
                    adv: p.x_advance as f32 / self.upm,
                    dx: p.x_offset as f32 / self.upm,
                    dy: p.y_offset as f32 / self.upm,
                }
            })
            .collect()
    }
}

/// A glyph placed in a text op: its id, the bytes of the op's text it shows, its advance and offsets in points.
#[derive(Clone, Debug, PartialEq)]
pub struct Glyph {
    pub id: u16,
    pub text: Range<usize>,
    pub adv: f32,
    pub dx: f32,
    pub dy: f32,
}

/// An image to place: a JPEG as it is, or 8-bit RGB pixels.
pub enum Image {
    Jpeg(Vec<u8>),
    Rgb { pixels: Vec<u8>, w: u32, h: u32 },
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
    /// Glyphs of font `font` from baseline point (x, y), showing `text`.
    Text {
        x: f32,
        y: f32,
        font: usize,
        size: f32,
        color: Rgb,
        text: String,
        glyphs: Vec<Glyph>,
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
    /// The document information's producer.
    pub producer: &'static str,
}

/// A rectangle with rounded corners (r 0: plain).
fn rect_path(x: f32, y: f32, w: f32, h: f32, r: f32) -> Option<krilla::geom::Path> {
    let mut p = PathBuilder::new();
    let r = r.min(w / 2.0).min(h / 2.0);
    if r <= 0.0 {
        p.push_rect(Rect::from_xywh(x, y, w, h)?);
        return p.finish();
    }
    let k = r * (1.0 - 0.5523); // the Bézier circle's handle, from the corner
    let (x1, y1) = (x + w, y + h);
    p.move_to(x + r, y);
    p.line_to(x1 - r, y);
    p.cubic_to(x1 - k, y, x1, y + k, x1, y + r);
    p.line_to(x1, y1 - r);
    p.cubic_to(x1, y1 - k, x1 - k, y1, x1 - r, y1);
    p.line_to(x + r, y1);
    p.cubic_to(x + k, y1, x, y1 - k, x, y1 - r);
    p.line_to(x, y + r);
    p.cubic_to(x, y + k, x + k, y, x + r, y);
    p.close();
    p.finish()
}

fn fill(c: Rgb) -> Fill {
    Fill { paint: c.color().into(), opacity: NormalizedF32::ONE, rule: Default::default() }
}

fn stroke(c: Rgb, width: f32) -> Stroke {
    Stroke { paint: c.color().into(), width, ..Default::default() }
}

impl<'f> Doc<'f> {
    pub fn new(fonts: &'f [Font], title: &str, producer: &'static str) -> Doc<'f> {
        Doc { fonts, images: vec![], pages: vec![], dests: BTreeMap::new(), title: title.into(), producer }
    }

    pub fn dest(&mut self, name: &str, page: usize, y: f32) {
        self.dests.entry(name.into()).or_insert((page, y));
    }

    /// The finished file.
    pub fn write(&self) -> Result<Vec<u8>> {
        let mut doc = Document::new();
        doc.set_metadata(Metadata::new().title(self.title.clone()).producer(self.producer.into()));
        let images: Vec<KImage> = self
            .images
            .iter()
            .map(|i| match i {
                Image::Jpeg(d) => KImage::from_jpeg(d.clone().into(), true).map_err(|e| anyhow!("JPEG: {e}")),
                Image::Rgb { pixels, w, h } => {
                    let rgba = pixels.chunks(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect();
                    Ok(KImage::from_rgba8(rgba, *w, *h))
                }
            })
            .collect::<Result<_>>()?;
        let (pw, ph) = A4;
        for ops in &self.pages {
            let mut page = doc.start_page_with(PageSettings::from_wh(pw, ph).ok_or_else(|| anyhow!("page size"))?);
            let mut links = vec![];
            let mut s = page.surface();
            for op in ops {
                match op {
                    Op::Rect { x, y, w, h, r, fill: f, stroke: st } => {
                        // A stroke is drawn inside the box, as CSS's border.
                        let inset = st.map(|s| s.1 / 2.0).unwrap_or(0.0);
                        if f.is_none() && st.is_none() {
                            continue;
                        }
                        let Some(path) = rect_path(x + inset, y + inset, w - 2.0 * inset, h - 2.0 * inset, *r) else {
                            continue;
                        };
                        s.set_fill(f.map(fill));
                        s.set_stroke(st.map(|(c, width)| stroke(c, width)));
                        s.draw_path(&path);
                    }
                    Op::Line { x0, y0, x1, y1, color, width } => {
                        let mut p = PathBuilder::new();
                        p.move_to(*x0, *y0);
                        p.line_to(*x1, *y1);
                        let Some(path) = p.finish() else { continue };
                        s.set_fill(None);
                        s.set_stroke(Some(stroke(*color, *width)));
                        s.draw_path(&path);
                    }
                    Op::Text { x, y, font, size, color, text, glyphs } => {
                        let f = &self.fonts[*font];
                        let gs: Vec<KrillaGlyph> = glyphs
                            .iter()
                            .map(|g| {
                                let id = GlyphId::new(g.id as u32);
                                KrillaGlyph::new(id, g.adv / size, g.dx / size, g.dy / size, 0.0, g.text.clone(), None)
                            })
                            .collect();
                        s.set_fill(Some(fill(*color)));
                        s.set_stroke(None);
                        // A synthetic oblique: slanted about the baseline.
                        let slanted = f.slant != 0.0;
                        if slanted {
                            s.push_transform(&Transform::from_row(1.0, 0.0, -f.slant, 1.0, f.slant * y, 0.0));
                        }
                        s.draw_glyphs(Point::from_xy(*x, *y), &gs, f.pdf.clone(), text, *size, false);
                        if slanted {
                            s.pop();
                        }
                    }
                    Op::Image { x, y, w, h, r, img } => {
                        let clip = if *r > 0.0 { rect_path(*x, *y, *w, *h, *r) } else { None };
                        if let Some(p) = &clip {
                            s.push_clip_path(p, &Default::default());
                        }
                        s.push_transform(&Transform::from_translate(*x, *y));
                        if let Some(size) = Size::from_wh(*w, *h) {
                            s.draw_image(images[*img].clone(), size);
                        }
                        s.pop();
                        if clip.is_some() {
                            s.pop();
                        }
                    }
                    Op::Link { x, y, w, h, dest } => {
                        let Some(&(p, dy)) = self.dests.get(dest) else { continue };
                        if let Some(rect) = Rect::from_xywh(*x, *y, *w, *h) {
                            let to = XyzDestination::new(p, Point::from_xy(0.0, dy));
                            let target = Target::Destination(Destination::Xyz(to));
                            links.push(Annotation::new_link(LinkAnnotation::new(rect, target), None));
                        }
                    }
                }
            }
            s.finish();
            for l in links {
                page.add_annotation(l);
            }
            page.finish();
        }
        doc.finish().map_err(|e| anyhow!("writing the PDF: {e:?}"))
    }
}
