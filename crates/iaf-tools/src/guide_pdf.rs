//! A pilot guide (docs/guides/<jet>.md) as a print-styled A4 PDF: assets/converted/guides/<jet>.pdf, drawn with
//! pdf.rs and the fonts in crates/iaf-tools/fonts (Liberation Sans and Mono, Helvetica's metrics; DejaVu Sans's
//! symbols for what Liberation lacks), so a release bundle makes it with nothing installed (docs/setup.md).
//!
//! The Markdown subset is the in-game viewer's (iaf-reborn/menu/guide_md.gd): # / ## / ### headings, paragraphs,
//! **bold**, *italic*, `code`, one-level bullet / numbered lists, pipe tables, `---`, [text](link) and pictures on a
//! line of their own, `![caption](shots/<jet>/<name>.png)` under assets/converted/guides (the guide shots, guides.rs in
//! iaf-setup; a .jpg beside a .png is used in its place); a numbered list right under a picture is its legend (the
//! picture's numbered callouts, `annotations` in <jet>.shots.json: the counts must match, else a warning), kept on the
//! picture's page with badges like the callouts. A title page with the Reference screen's picture of the jet
//! (assets/converted/reference/img/<jet>.png, else the guide's `external` shot), then a table of contents with links.
//! The look is the one the earlier HTML print had (its CSS's sizes, in mm and pt, are the constants below). The PDF
//! holds the original art, so it stays under assets/ (never committed).

use crate::pdf::{A4, Doc, Font, Image, Op, Rgb};
use crate::progress::Progress;
use anyhow::{Context, Result};
use rayon::prelude::*;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

const MM: f32 = 72.0 / 25.4;
const PX: f32 = 0.75;
/// The page's margins: top, side, bottom.
const TOP: f32 = 18.0 * MM;
const SIDE: f32 = 17.0 * MM;
const BOTTOM: f32 = 20.0 * MM;
const WIDTH: f32 = A4.0 - 2.0 * SIDE;
const BODY: f32 = 10.2;
const CODE: f32 = 9.0;
const INK: Rgb = Rgb::hex(0x1d1f24);
const GREEN: Rgb = Rgb::hex(0x2f6f4f);

const REG: usize = 0;
const BOLD: usize = 1;
const ITALIC: usize = 2;
const BOLD_ITALIC: usize = 3;
const MONO: usize = 4;
const SYMBOLS: usize = 5;

fn fonts() -> &'static [Font] {
    static F: OnceLock<Vec<Font>> = OnceLock::new();
    F.get_or_init(|| {
        vec![
            Font::parse("LiberationSans", include_bytes!("../fonts/LiberationSans-Regular.ttf")),
            Font::parse("LiberationSans-Bold", include_bytes!("../fonts/LiberationSans-Bold.ttf")),
            Font::parse("LiberationSans-Italic", include_bytes!("../fonts/LiberationSans-Italic.ttf")),
            Font::parse("LiberationSans-BoldItalic", include_bytes!("../fonts/LiberationSans-BoldItalic.ttf")),
            Font::parse("LiberationMono", include_bytes!("../fonts/LiberationMono-Regular.ttf")),
            Font::parse("DejaVuSans-Symbols", include_bytes!("../fonts/DejaVuSans-Symbols.ttf")),
        ]
    })
}

// ---- Inline text ------------------------------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Sty {
    bold: bool,
    italic: bool,
    code: bool,
    sup: bool,
}

#[derive(Clone, Debug, PartialEq)]
struct Run {
    text: String,
    sty: Sty,
    /// Which code span (its background box joins the span's words on a line).
    span: usize,
}

// Markers in the text between the passes: bold on / off, superscript on / off; an escaped character is ESC + its code.
const B_ON: char = '\u{e010}';
const B_OFF: char = '\u{e011}';
const S_ON: char = '\u{e012}';
const S_OFF: char = '\u{e013}';
const ESC: u32 = 0xe100;

fn word_char(c: Option<&char>) -> bool {
    c.is_some_and(|c| c.is_alphanumeric() || *c == '_')
}

/// A line of Markdown as styled runs (the HTML print's `inline`).
fn inline(t: &str) -> Vec<Run> {
    // Escaped punctuation stays as text.
    let mut s = String::new();
    let mut it = t.chars().peekable();
    while let Some(c) = it.next() {
        match (c, it.peek()) {
            ('\\', Some(&n)) if "\\`*_[]()#|".contains(n) => {
                s.push(char::from_u32(ESC + n as u32).unwrap_or(n));
                it.next();
            }
            _ => s.push(c),
        }
    }
    // A footnote's definition: [^x]: as bold [x].
    if let Some(rest) = s.strip_prefix("[^")
        && let Some(end) = rest.find("]:")
        && !rest[..end].contains(']')
        && end > 0
    {
        s = format!("{B_ON}[{}]{B_OFF}{}", &rest[..end], &rest[end + 2..]);
    }
    // Footnote references, then links (their text kept).
    let mut out = String::new();
    let mut rest = s.as_str();
    while let Some(i) = rest.find('[') {
        out += &rest[..i];
        let tail = &rest[i + 1..];
        let close = tail.find(']');
        match close {
            Some(j) if tail.starts_with('^') && j > 1 => {
                out += &format!("{S_ON}[{}]{S_OFF}", &tail[1..j]);
                rest = &tail[j + 1..];
            }
            Some(j) if tail[j + 1..].starts_with('(') && tail[j + 1..].contains(')') => {
                out += &tail[..j];
                let after = &tail[j + 1..];
                rest = &after[after.find(')').unwrap_or(0) + 1..];
            }
            _ => {
                out.push('[');
                rest = tail;
            }
        }
    }
    out += rest;
    // Code, bold, italic.
    let ch: Vec<char> = out.chars().collect();
    let mut runs: Vec<Run> = vec![];
    let mut sty = Sty::default();
    let (mut bold_close, mut ital_close) = (usize::MAX, usize::MAX);
    let mut span = 0;
    let push = |runs: &mut Vec<Run>, c: char, sty: Sty, span: usize| {
        let c = if (ESC..ESC + 128).contains(&(c as u32)) { char::from_u32(c as u32 - ESC).unwrap_or(c) } else { c };
        match runs.last_mut() {
            Some(r) if r.sty == sty && r.span == span => r.text.push(c),
            _ => runs.push(Run { text: c.to_string(), sty, span }),
        }
    };
    let mut i = 0;
    while i < ch.len() {
        let c = ch[i];
        match c {
            B_ON => sty.bold = true,
            B_OFF => sty.bold = false,
            S_ON => sty.sup = true,
            S_OFF => sty.sup = false,
            '`' => {
                if let Some(j) = ch[i + 1..].iter().position(|&c| c == '`').filter(|&j| j > 0) {
                    span += 1;
                    let code = Sty { code: true, ..sty };
                    for &c in &ch[i + 1..i + 1 + j] {
                        push(&mut runs, c, code, span);
                    }
                    span += 1;
                    i += j + 2;
                    continue;
                }
                push(&mut runs, c, sty, span);
            }
            '*' if i == bold_close => {
                sty.bold = false;
                bold_close = usize::MAX;
                i += 2;
                continue;
            }
            '*' if i == ital_close => {
                sty.italic = false;
                ital_close = usize::MAX;
            }
            '*' if ch.get(i + 1) == Some(&'*') && !sty.bold => {
                // **x**: the next ** with something between.
                match (i + 3..ch.len().saturating_sub(1)).find(|&j| ch[j] == '*' && ch[j + 1] == '*') {
                    Some(j) => {
                        sty.bold = true;
                        bold_close = j;
                        i += 2;
                        continue;
                    }
                    None => push(&mut runs, c, sty, span),
                }
            }
            '*' if !sty.italic => {
                // *x*: not after * or a word character, x has no * and does not start with a space, the closing * not
                // before * or a word character.
                let ok_open = (i == 0 || (ch[i - 1] != '*' && !word_char(ch.get(i - 1))))
                    && ch.get(i + 1).is_some_and(|n| *n != '*' && !n.is_whitespace());
                let close = ch[i + 1..].iter().position(|&c| c == '*').map(|j| i + 1 + j);
                match close {
                    Some(j) if ok_open && ch.get(j + 1) != Some(&'*') && !word_char(ch.get(j + 1)) => {
                        sty.italic = true;
                        ital_close = j;
                    }
                    _ => push(&mut runs, c, sty, span),
                }
            }
            _ => push(&mut runs, c, sty, span),
        }
        i += 1;
    }
    runs
}

// ---- Text layout ------------------------------------------------------------------------------------------------

/// A shaped piece of one font.
#[derive(Clone)]
struct Piece {
    font: usize,
    size: f32,
    rise: f32,
    glyphs: Vec<(u16, char)>,
    w: f32,
    code_span: Option<usize>,
}

fn face(sty: Sty, bold_base: bool, italic_base: bool) -> usize {
    let (b, i) = (sty.bold || bold_base, sty.italic || italic_base);
    if sty.code {
        MONO
    } else {
        match (b, i) {
            (false, false) => REG,
            (true, false) => BOLD,
            (false, true) => ITALIC,
            (true, true) => BOLD_ITALIC,
        }
    }
}

/// The text's glyphs in `font`, a character it lacks from the symbols font (else .notdef), as pieces.
fn shape(text: &str, font: usize, size: f32, rise: f32, code_span: Option<usize>) -> Vec<Piece> {
    let f = fonts();
    let mut out: Vec<Piece> = vec![];
    for c in text.chars() {
        let (fi, g) = match f[font].glyph(c) {
            Some(g) => (font, g),
            None => f[SYMBOLS].glyph(c).map(|g| (SYMBOLS, g)).unwrap_or((font, 0)),
        };
        let w = f[fi].advance(g) * size;
        match out.last_mut() {
            Some(p) if p.font == fi => {
                p.glyphs.push((g, c));
                p.w += w;
            }
            _ => out.push(Piece { font: fi, size, rise, glyphs: vec![(g, c)], w, code_span }),
        }
    }
    out
}

/// A word in the order it is drawn: each run of Hebrew letters reversed (right to left within the word).
/// ponytail: one word at a time; a phrase of several Hebrew words would also need its words' order reversed.
fn visual(word: &str) -> String {
    let hebrew = |c: &char| ('\u{0590}'..='\u{05ff}').contains(c);
    let mut out = String::new();
    let mut run: Vec<char> = vec![];
    for c in word.chars() {
        if hebrew(&c) {
            run.push(c);
        } else {
            out.extend(run.drain(..).rev());
            out.push(c);
        }
    }
    out.extend(run.into_iter().rev());
    out
}

/// A paragraph's style: size, line height, colour, the base weight / slant (headings, captions), alignment.
#[derive(Clone, Copy)]
struct Para {
    size: f32,
    lh: f32,
    color: Rgb,
    bold: bool,
    italic: bool,
    center: bool,
    spacing: f32,
}

impl Para {
    fn new(size: f32) -> Para {
        Para { size, lh: size * 1.5, color: INK, bold: false, italic: false, center: false, spacing: 0.0 }
    }
}

/// A word: pieces with no break between them, and the width of the space before it.
struct Word {
    pieces: Vec<Piece>,
    w: f32,
    space: f32,
}

fn words(runs: &[Run], p: &Para) -> Vec<Word> {
    let mut out: Vec<Word> = vec![];
    let mut space = 0.0;
    let mut fresh = true;
    for r in runs {
        let font = face(r.sty, p.bold, p.italic);
        let size = if r.sty.code {
            CODE // CSS: code is 9 pt wherever it is
        } else if r.sty.sup {
            p.size * 0.83
        } else {
            p.size
        };
        let rise = if r.sty.sup { p.size * 0.33 } else { 0.0 };
        let span = r.sty.code.then_some(r.span);
        for (k, part) in r.text.split(' ').enumerate() {
            if k > 0 {
                space += fonts()[font].glyph(' ').map(|g| fonts()[font].advance(g) * size).unwrap_or(size * 0.28)
                    + p.spacing;
                fresh = true;
            }
            if part.is_empty() {
                continue;
            }
            let pieces = shape(&visual(part), font, size, rise, span);
            let w: f32 = pieces.iter().map(|x| x.w + p.spacing * x.glyphs.len() as f32).sum();
            if fresh || out.is_empty() {
                out.push(Word { pieces, w, space: if out.is_empty() { 0.0 } else { space } });
                fresh = false;
            } else {
                let last = out.last_mut().expect("a word");
                last.pieces.extend(pieces);
                last.w += w;
            }
            space = 0.0;
        }
    }
    out
}

/// The widest word and the whole text on one line (a table cell's min / max content widths).
fn text_widths(runs: &[Run], p: &Para) -> (f32, f32) {
    let ws = words(runs, p);
    let min = ws.iter().map(|w| w.w).fold(0.0, f32::max);
    let max = ws.iter().map(|w| w.w + w.space).sum();
    (min, max)
}

/// The text broken into lines `width` wide: one op list per line, its top at y 0, from x 0.
fn wrap(runs: &[Run], p: &Para, width: f32) -> Vec<Vec<Op>> {
    let ws = words(runs, p);
    let mut rows: Vec<Vec<&Word>> = vec![];
    let mut w = 0.0;
    for word in &ws {
        match rows.last_mut() {
            Some(row) if w + word.space + word.w <= width + 0.01 => {
                w += word.space + word.w;
                row.push(word);
            }
            _ => {
                rows.push(vec![word]);
                w = word.w;
            }
        }
    }
    let f = fonts();
    let base = &f[face(Sty::default(), p.bold, p.italic)];
    let baseline = (p.lh - (base.ascent + base.descent) * p.size) / 2.0 + base.ascent * p.size;
    rows.iter()
        .map(|row| {
            let total: f32 = row.iter().enumerate().map(|(i, w)| w.w + if i > 0 { w.space } else { 0.0 }).sum();
            let mut x = if p.center { (width - total) / 2.0 } else { 0.0 };
            let mut ops = vec![];
            // A code span's background: from its first piece to its last on the line.
            let mut boxes: Vec<(usize, f32, f32)> = vec![];
            let mut text = vec![];
            let pad = 1.2 * MM;
            let mut last: Option<usize> = None; // the code span of the piece before
            for (i, word) in row.iter().enumerate() {
                let first = word.pieces.first().and_then(|p| p.code_span);
                if last.is_some() && first != last {
                    x += pad; // the closing pad, before the space
                }
                if i > 0 {
                    x += word.space;
                }
                for (k, piece) in word.pieces.iter().enumerate() {
                    if k > 0 && last.is_some() && piece.code_span != last {
                        x += pad;
                    }
                    if let Some(s) = piece.code_span {
                        match boxes.last_mut() {
                            Some(b) if b.0 == s => b.2 = x + piece.w + pad,
                            _ => {
                                x += pad;
                                boxes.push((s, x - pad, x + piece.w + pad));
                            }
                        }
                    }
                    last = piece.code_span;
                    text.push(Op::Text {
                        x,
                        y: baseline - piece.rise,
                        font: piece.font,
                        size: piece.size,
                        color: p.color,
                        glyphs: piece.glyphs.clone(),
                        spacing: p.spacing,
                    });
                    x += piece.w + p.spacing * piece.glyphs.len() as f32;
                }
                if i + 1 < row.len() && last.is_some() {
                    let next = row[i + 1].pieces.first().and_then(|p| p.code_span);
                    if next == last {
                        last = None; // the span goes on: no closing pad
                    }
                }
            }
            // The box of the print's monospace font (Noto Sans Mono: 1.069 em up, 0.293 down), taller than Liberation
            // Mono's.
            for (_, x0, x1) in boxes {
                let top = baseline - 1.069 * CODE - 0.2 * MM;
                let h = 1.362 * CODE + 0.4 * MM;
                ops.push(Op::Rect {
                    x: x0,
                    y: top,
                    w: x1 - x0,
                    h,
                    r: MM,
                    fill: Some(Rgb::hex(0xeef0f3)),
                    stroke: None,
                });
            }
            ops.extend(text);
            ops
        })
        .collect()
}

/// The ops moved by (dx, dy).
fn shift(ops: Vec<Op>, dx: f32, dy: f32) -> Vec<Op> {
    ops.into_iter()
        .map(|op| match op {
            Op::Rect { x, y, w, h, r, fill, stroke } => Op::Rect { x: x + dx, y: y + dy, w, h, r, fill, stroke },
            Op::Line { x0, y0, x1, y1, color, width } => {
                Op::Line { x0: x0 + dx, y0: y0 + dy, x1: x1 + dx, y1: y1 + dy, color, width }
            }
            Op::Text { x, y, font, size, color, glyphs, spacing } => {
                Op::Text { x: x + dx, y: y + dy, font, size, color, glyphs, spacing }
            }
            Op::Image { x, y, w, h, r, img } => Op::Image { x: x + dx, y: y + dy, w, h, r, img },
            Op::Link { x, y, w, h, dest } => Op::Link { x: x + dx, y: y + dy, w, h, dest },
        })
        .collect()
}

/// A paragraph as one block of ops (all its lines) and its height.
fn block(runs: &[Run], p: &Para, width: f32) -> (Vec<Op>, f32) {
    let ls = wrap(runs, p, width);
    let h = ls.len() as f32 * p.lh;
    (ls.into_iter().enumerate().flat_map(|(i, l)| shift(l, 0.0, i as f32 * p.lh)).collect(), h)
}

// ---- Blocks and pages -------------------------------------------------------------------------------------------

/// An unbreakable piece of the flow: a line, a table row, a figure. Margins collapse as CSS's do.
#[derive(Clone, Default)]
struct Slice {
    h: f32,
    mt: f32,
    mb: f32,
    ops: Vec<Op>,
    /// No page break between this slice and the next (a heading).
    keep_next: bool,
    /// A page break after it.
    break_after: bool,
    /// The table header that starts a page this row starts (index into Flow::headers).
    header: Option<usize>,
    /// Destinations at its top (a heading's id).
    anchors: Vec<String>,
}

#[derive(Default)]
struct Flow {
    slices: Vec<Slice>,
    headers: Vec<Slice>,
}

impl Flow {
    /// A paragraph's lines, each a slice; the block's margins on its first and last.
    fn para(&mut self, runs: &[Run], p: &Para, x: f32, width: f32, mt: f32, mb: f32) {
        let ls = wrap(runs, p, width);
        let n = ls.len();
        for (i, l) in ls.into_iter().enumerate() {
            self.slices.push(Slice {
                h: p.lh,
                mt: if i == 0 { mt } else { 0.0 },
                mb: if i + 1 == n { mb } else { 0.0 },
                ops: shift(l, x, 0.0),
                ..Default::default()
            });
        }
    }
}

fn slug(s: &str, seen: &mut Vec<String>) -> String {
    let mut base = String::new();
    for c in s.to_lowercase().chars() {
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            base.push(c);
        } else if !base.ends_with('-') {
            base.push('-');
        }
    }
    let base = base.trim_matches('-').to_string();
    let base = if base.is_empty() { "s".to_string() } else { base };
    let (mut out, mut n) = (base.clone(), 2);
    while seen.contains(&out) {
        out = format!("{base}-{n}");
        n += 1;
    }
    seen.push(out.clone());
    out
}

fn list_item(line: &str) -> Option<(bool, &str)> {
    let t = line.trim();
    if let Some(r) = t.strip_prefix("- ").or_else(|| t.strip_prefix("* ")) {
        return Some((false, r.trim_start()));
    }
    let digits = t.chars().take_while(|c| c.is_ascii_digit()).count();
    (digits > 0 && t[digits..].starts_with(". ")).then(|| (true, t[digits + 2..].trim_start()))
}

/// A picture for the PDF: a .png with a .jpg beside it as that JPEG.
fn picture(doc: &mut Doc, p: &Path) -> Result<usize> {
    let jpg = p.with_extension("jpg");
    let img =
        if p.extension().is_some_and(|e| e == "jpg") || (p.extension().is_some_and(|e| e == "png") && jpg.is_file()) {
            let f = if p.extension().is_some_and(|e| e == "jpg") { p } else { jpg.as_path() };
            Image::jpeg(std::fs::read(f).with_context(|| format!("{}", f.display()))?)?
        } else {
            let rgb = image::open(p).with_context(|| format!("{}", p.display()))?.to_rgb8();
            Image::Rgb { w: rgb.width(), h: rgb.height(), pixels: rgb.into_raw() }
        };
    doc.images.push(img);
    Ok(doc.images.len() - 1)
}

/// The legend's numbered items under a picture, at (x, y): ops and height (from the first item's top).
fn legend(items: &[String], first: usize, x: f32, width: f32) -> (Vec<Op>, f32) {
    let p = Para::new(9.0);
    let mut ops = vec![];
    let mut y = 0.0;
    for (i, it) in items.iter().enumerate() {
        if i > 0 {
            y += MM;
        }
        let d = 5.0 * MM;
        let (t, h) = block(&inline(it), &p, width - 7.5 * MM);
        ops.push(Op::Rect {
            x,
            y: y + 0.2 * MM,
            w: d,
            h: d,
            r: d / 2.0,
            fill: Some(Rgb::hex(0xffcc1a)),
            stroke: Some((Rgb::hex(0x0d0d0d), 1.2 * PX)),
        });
        let n = Para { center: true, bold: true, lh: d, ..Para::new(7.6) };
        let (num, _) = block(&[Run { text: (first + i + 1).to_string(), sty: Sty::default(), span: 0 }], &n, d);
        ops.extend(shift(num, x, y + 0.2 * MM));
        ops.extend(shift(t, x + 7.5 * MM, y));
        y += h;
    }
    (ops, y)
}

/// The guide's flow (after the cover), its title and its contents' [(level, text, id)].
fn body(
    doc: &mut Doc,
    md: &str,
    base: &Path,
    callouts: &[(String, usize)],
    pr: &dyn Progress,
) -> Result<(Flow, String)> {
    let mut lines: Vec<String> = vec![];
    for line in md.replace('\r', "").split('\n') {
        // An indented continuation line joins its list item.
        if line.starts_with(' ') && !line.trim().is_empty() && lines.last().is_some_and(|l| list_item(l).is_some()) {
            let l = lines.last_mut().expect("a line");
            *l += " ";
            *l += line.trim();
        } else {
            lines.push(line.to_string());
        }
    }
    let mut flow = Flow::default();
    let mut toc: Vec<(usize, String, String)> = vec![];
    let mut seen = vec![];
    let mut title = String::new();
    let mut para: Vec<String> = vec![];
    let body = Para::new(BODY);
    let flush = |flow: &mut Flow, para: &mut Vec<String>| {
        if !para.is_empty() {
            flow.para(&inline(&para.join(" ")), &body, SIDE, WIDTH, 0.0, 3.0 * MM);
            para.clear();
        }
    };
    let mut i = 0;
    while i < lines.len() {
        let t = lines[i].trim().to_string();
        let item = list_item(&t);
        if t.is_empty() {
            flush(&mut flow, &mut para);
        } else if t.starts_with('#') {
            flush(&mut flow, &mut para);
            let level = t.chars().take_while(|&c| c == '#').count();
            let text = t.trim_start_matches('#').trim().to_string();
            if level == 1 && title.is_empty() {
                title = text;
            } else {
                let id = slug(&text, &mut seen);
                if level == 2 || level == 3 {
                    toc.push((level, text.clone(), id.clone()));
                }
                let (size, mt, mb, color) = match level {
                    1 => (22.0, 0.0, 4.0 * MM, INK),
                    2 => (16.0, 9.0 * MM, 3.0 * MM, INK),
                    _ => (12.0, 6.0 * MM, 2.0 * MM, GREEN),
                };
                let p = Para { bold: true, color, ..Para::new(size) };
                let (mut ops, mut h) = block(&inline(&text), &p, WIDTH);
                if level == 2 {
                    h += 2.0 * MM + 2.5 * PX;
                    let y = h - 2.5 * PX / 2.0;
                    ops.push(Op::Line { x0: 0.0, y0: y, x1: WIDTH, y1: y, color: GREEN, width: 2.5 * PX });
                }
                flow.slices.push(Slice {
                    h,
                    mt,
                    mb,
                    ops: shift(ops, SIDE, 0.0),
                    keep_next: true,
                    anchors: vec![id],
                    ..Default::default()
                });
            }
        } else if t == "---" || t == "***" {
            flush(&mut flow, &mut para);
            let next = lines[i + 1..].iter().map(|l| l.trim()).find(|l| !l.is_empty()).unwrap_or("");
            if !next.starts_with("## ") {
                let color = Rgb::hex(0xd4d6dc);
                flow.slices.push(Slice {
                    h: PX,
                    mt: 5.0 * MM,
                    mb: 5.0 * MM,
                    ops: vec![Op::Line { x0: SIDE, y0: PX / 2.0, x1: SIDE + WIDTH, y1: PX / 2.0, color, width: PX }],
                    ..Default::default()
                });
            }
        } else if t.starts_with("![") && t.contains("](") {
            flush(&mut flow, &mut para);
            let close = t.find("](").expect("checked");
            let cap = &t[2..close];
            let src = &t[close + 2..t[close..].find(')').map(|j| close + j).unwrap_or(t.len())];
            let path = base.join(src);
            // The legend: a numbered list right under the picture (blank lines between allowed).
            let mut j = i + 1;
            while j < lines.len() && lines[j].trim().is_empty() {
                j += 1;
            }
            let mut items = vec![];
            while j < lines.len() && list_item(&lines[j]).is_some_and(|(n, _)| n) {
                items.push(list_item(&lines[j]).expect("checked").1.to_string());
                j += 1;
            }
            if !items.is_empty() {
                i = j - 1;
            }
            let stem = Path::new(src).file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
            if let Some((_, want)) = callouts.iter().find(|(n, _)| *n == stem)
                && *want != items.len()
            {
                pr.warn(&format!("guide PDF: warning: {src} has {want} callouts, its legend {} items", items.len()));
            }
            let caption = Para { italic: true, center: true, color: Rgb::hex(0x5b606c), ..Para::new(8.8) };
            if path.is_file() {
                let (pw, ph) = image::image_dimensions(&path).with_context(|| format!("{}", path.display()))?;
                let small = ph as f32 >= pw as f32 * 0.9; // the square MFD crops not page-wide
                let w = if small { WIDTH * 0.46 } else { WIDTH };
                let h = w * ph as f32 / pw as f32;
                let x = SIDE + (WIDTH - w) / 2.0;
                let img = picture(doc, &path)?;
                let border = Rgb::hex(0xc8cbd2);
                let mut ops = vec![
                    Op::Image { x, y: 0.0, w, h, r: 1.5 * MM, img },
                    Op::Rect { x, y: 0.0, w, h, r: 1.5 * MM, fill: None, stroke: Some((border, PX)) },
                ];
                let (c, ch) = block(&inline(cap), &caption, WIDTH);
                ops.extend(shift(c, SIDE, h + 1.8 * MM));
                let mut total = h + 1.8 * MM + ch;
                let pic = Slice { h: total, mt: 3.0 * MM, mb: 6.0 * MM, ops: ops.clone(), ..Default::default() };
                if !items.is_empty() {
                    let (l, lh) = legend(&items, 0, SIDE, WIDTH);
                    ops.extend(shift(l, 0.0, total + 2.5 * MM));
                    total += 2.5 * MM + lh;
                }
                if total <= A4.1 - TOP - BOTTOM {
                    flow.slices.push(Slice { h: total, mt: 3.0 * MM, mb: 6.0 * MM, ops, ..Default::default() });
                } else {
                    // Taller than a page: the legend's items flow on.
                    flow.slices.push(Slice { mb: 2.5 * MM, ..pic });
                    for (k, it) in items.iter().enumerate() {
                        let (l, lh) = legend(std::slice::from_ref(it), k, SIDE, WIDTH);
                        flow.slices.push(Slice { h: lh, mt: MM, mb: MM, ops: l, ..Default::default() });
                    }
                }
            } else {
                flow.para(&inline(cap), &Para { italic: true, ..body }, SIDE, WIDTH, 0.0, 3.0 * MM);
                if !items.is_empty() {
                    let (l, lh) = legend(&items, 0, SIDE, WIDTH);
                    flow.slices.push(Slice { h: lh, mt: 2.5 * MM, mb: MM, ops: l, ..Default::default() });
                }
            }
        } else if t.starts_with('|') {
            flush(&mut flow, &mut para);
            let mut rows: Vec<Vec<String>> = vec![];
            while i < lines.len() && lines[i].trim().starts_with('|') {
                let row = lines[i].trim();
                if !row.chars().all(|c| " :|-".contains(c)) {
                    rows.push(row.trim_matches('|').split('|').map(|c| c.trim().to_string()).collect());
                }
                i += 1;
            }
            i -= 1;
            table(&mut flow, &rows);
        } else if let Some((ordered, _)) = item {
            flush(&mut flow, &mut para);
            // The list: its items up to a line that is not one of the same kind.
            let mut items = vec![];
            while i < lines.len() && list_item(&lines[i]).is_some_and(|(o, _)| o == ordered) {
                items.push(list_item(&lines[i]).expect("checked").1.to_string());
                i += 1;
            }
            i -= 1;
            let n = items.len();
            for (k, it) in items.iter().enumerate() {
                let at = flow.slices.len();
                flow.para(
                    &inline(it),
                    &body,
                    SIDE + 6.0 * MM,
                    WIDTH - 6.0 * MM,
                    0.6 * MM,
                    if k + 1 == n { 3.0 * MM } else { 0.6 * MM },
                );
                // The marker and a space end 0.15 em before the item's text (the print's gap).
                let marker = if ordered { format!("{}. ", k + 1) } else { "\u{2022} ".to_string() };
                let mrun = [Run { text: marker, sty: Sty::default(), span: 0 }];
                let mw: f32 = mrun[0]
                    .text
                    .chars()
                    .map(|c| fonts()[REG].glyph(c).map_or(0.0, |g| fonts()[REG].advance(g)))
                    .sum::<f32>()
                    * BODY;
                let ml = wrap(&mrun, &body, WIDTH);
                if let (Some(first), Some(m)) = (flow.slices.get_mut(at), ml.into_iter().next()) {
                    first.ops.extend(shift(m, SIDE + 6.0 * MM - mw - 0.15 * BODY, 0.0));
                }
            }
        } else {
            para.push(t);
        }
        i += 1;
    }
    flush(&mut flow, &mut para);
    let mut out = Flow::default();
    contents(&mut out, &toc);
    out.slices.last_mut().expect("the contents' heading").break_after = true;
    let n = out.headers.len();
    out.slices.extend(flow.slices.into_iter().map(|s| Slice { header: s.header.map(|h| h + n), ..s }));
    out.headers.extend(flow.headers);
    Ok((out, title))
}

/// The table of contents: a heading and one linked line per ## / ### heading.
fn contents(flow: &mut Flow, toc: &[(usize, String, String)]) {
    let p = Para { bold: true, ..Para::new(16.0) };
    let (ops, h) = block(&inline("Contents"), &p, WIDTH);
    flow.slices.push(Slice {
        h: h + 2.0 * MM,
        mb: 3.0 * MM,
        ops: shift(ops, SIDE, 0.0),
        keep_next: true,
        ..Default::default()
    });
    for (level, text, id) in toc {
        let (p, pad, indent) = if *level == 2 {
            (Para::new(BODY), 1.6 * MM, 0.0)
        } else {
            (Para { color: Rgb::hex(0x4b4f5a), ..Para::new(9.4) }, 0.6 * MM, 7.0 * MM)
        };
        let (t, th) = block(&inline(text), &p, WIDTH - indent);
        let mut ops = shift(t, SIDE + indent, pad);
        let mut h = th + 2.0 * pad;
        if *level == 2 {
            ops.push(Op::Line {
                x0: SIDE,
                y0: h + PX / 2.0,
                x1: SIDE + WIDTH,
                y1: h + PX / 2.0,
                color: Rgb::hex(0xe3e4e8),
                width: PX,
            });
            h += PX;
        }
        ops.push(Op::Link { x: SIDE, y: 0.0, w: WIDTH, h, dest: id.clone() });
        flow.slices.push(Slice { h, mt: 0.6 * MM, mb: 0.6 * MM, ops, ..Default::default() });
    }
}

/// A pipe table: CSS's automatic column widths over the page's width, a dark header row repeated on each page,
/// rows striped and never split.
fn table(flow: &mut Flow, rows: &[Vec<String>]) {
    let n = rows.iter().map(Vec::len).max().unwrap_or(0);
    if n == 0 {
        return;
    }
    let pad = 2.2 * MM;
    let cell = Para::new(9.0);
    let head = Para { bold: true, color: Rgb::hex(0xffffff), ..cell };
    let cells: Vec<Vec<Vec<Run>>> =
        rows.iter().map(|r| (0..n).map(|k| inline(r.get(k).map(String::as_str).unwrap_or(""))).collect()).collect();
    let (mut min, mut max) = (vec![0.0f32; n], vec![0.0f32; n]);
    for (ri, r) in cells.iter().enumerate() {
        for (k, c) in r.iter().enumerate() {
            let (a, b) = text_widths(c, if ri == 0 { &head } else { &cell });
            min[k] = min[k].max(a + 2.0 * pad);
            max[k] = max[k].max(b + 2.0 * pad);
        }
    }
    let (smin, smax): (f32, f32) = (min.iter().sum(), max.iter().sum());
    let widths: Vec<f32> = if smax <= WIDTH {
        max.iter().map(|m| m + (WIDTH - smax) * m / smax.max(1.0)).collect()
    } else if smin >= WIDTH {
        min.clone()
    } else {
        let d = (smax - smin).max(1e-3);
        (0..n).map(|k| min[k] + (WIDTH - smin) * (max[k] - min[k]) / d).collect()
    };
    let row = |r: &[Vec<Run>], p: &Para, vpad: f32| -> (Vec<Op>, f32) {
        let mut ops = vec![];
        let mut x = SIDE;
        let mut h: f32 = 0.0;
        for (k, c) in r.iter().enumerate() {
            let (t, th) = block(c, p, widths[k] - 2.0 * pad);
            ops.extend(shift(t, x + pad, vpad));
            h = h.max(th);
            x += widths[k];
        }
        (ops, h + 2.0 * vpad)
    };
    let (hops, hh) = row(&cells[0], &head, 1.6 * MM);
    let mut ops =
        vec![Op::Rect { x: SIDE, y: 0.0, w: WIDTH, h: hh, r: 0.0, fill: Some(Rgb::hex(0x2f3440)), stroke: None }];
    ops.extend(hops);
    let header = Slice { h: hh, ops, ..Default::default() };
    flow.headers.push(header.clone());
    let hi = flow.headers.len() - 1;
    let alone = cells.len() == 1; // a header and no rows: the table's bottom margin on it
    flow.slices.push(Slice { mt: 2.0 * MM, mb: if alone { 5.0 * MM } else { 0.0 }, keep_next: !alone, ..header });
    let last = cells.len() - 1;
    for (ri, r) in cells.iter().enumerate().skip(1) {
        let (t, th) = row(r, &cell, 1.4 * MM);
        let h = th + PX;
        let mut ops = vec![];
        if ri % 2 == 0 {
            ops.push(Op::Rect { x: SIDE, y: 0.0, w: WIDTH, h, r: 0.0, fill: Some(Rgb::hex(0xf5f6f8)), stroke: None });
        }
        ops.extend(t);
        let color = Rgb::hex(0xdfe1e6);
        ops.push(Op::Line { x0: SIDE, y0: h - PX / 2.0, x1: SIDE + WIDTH, y1: h - PX / 2.0, color, width: PX });
        flow.slices.push(Slice {
            h,
            mb: if ri == last { 5.0 * MM } else { 0.0 },
            ops,
            header: Some(hi),
            ..Default::default()
        });
    }
}

/// The flow on pages after the ones in `doc`: margins collapse between slices and vanish at a page's top; a heading
/// moves to the next page with what follows it; a table row that starts a page brings its table's header.
fn paginate(doc: &mut Doc, flow: Flow) {
    let bottom = A4.1 - BOTTOM;
    let mut page: Vec<Op> = vec![];
    let mut y = TOP;
    let mut pending = 0.0f32; // the last slice's bottom margin
    let mut fresh = true;
    let mut i = 0;
    let s = &flow.slices;
    while i < s.len() {
        // The chain kept together: slices joined by keep_next, and the one after them.
        let mut end = i;
        while s[end].keep_next && end + 1 < s.len() {
            end += 1;
        }
        let gap = |k: usize, prev: f32| s[k].mt.max(prev);
        let mut need = s[i].h;
        for k in i + 1..=end {
            need += gap(k, s[k - 1].mb) + s[k].h;
        }
        let m = if fresh { 0.0 } else { gap(i, pending) };
        let new_page = !fresh && y + m + need > bottom;
        if new_page {
            doc.pages.push(std::mem::take(&mut page));
            y = TOP;
            fresh = true;
        }
        let place =
            |sl: &Slice, y: &mut f32, fresh: &mut bool, pending: &mut f32, page: &mut Vec<Op>, doc: &mut Doc| {
                if !*fresh {
                    *y += sl.mt.max(*pending);
                }
                for a in &sl.anchors {
                    doc.dest(a, doc.pages.len(), *y);
                }
                page.extend(shift(sl.ops.clone(), 0.0, *y));
                *y += sl.h;
                *pending = sl.mb;
                *fresh = false;
            };
        for k in i..=end {
            if fresh
                && k == i
                && let Some(h) = s[k].header
                && k > 0
                && s[k - 1].header.is_some()
            {
                place(&flow.headers[h], &mut y, &mut fresh, &mut pending, &mut page, doc);
            }
            place(&s[k], &mut y, &mut fresh, &mut pending, &mut page, doc);
            if s[k].break_after {
                doc.pages.push(std::mem::take(&mut page));
                y = TOP;
                fresh = true;
            }
        }
        i = end + 1;
    }
    if !page.is_empty() {
        doc.pages.push(page);
    }
}

/// The title page: the dark cover with the jet's picture.
fn cover(doc: &mut Doc, name: &str, img: &Path) -> Result<()> {
    let (pw, ph) = A4;
    let (x, w) = (22.0 * MM, pw - 44.0 * MM);
    let mut ops = vec![Op::Rect { x: 0.0, y: 0.0, w: pw, h: ph, r: 0.0, fill: Some(Rgb::hex(0x23252c)), stroke: None }];
    let mut y = 34.0 * MM;
    let kicker = Para { color: Rgb::hex(0x9ea3b0), spacing: 0.32 * 10.0, ..Para::new(10.0) };
    let (k, kh) = block(&inline("JANE'S IAF \u{b7} REBORN"), &kicker, w);
    ops.extend(shift(k, x, y));
    y += kh + 6.0 * MM;
    let h1 = Para { bold: true, color: Rgb::hex(0xf2f2f4), lh: 44.0, ..Para::new(40.0) };
    let (t, th) = block(&inline(name), &h1, w);
    ops.extend(shift(t, x, y));
    y += th + 4.0 * MM;
    let sub = Para { color: Rgb::hex(0xc9ccd4), ..Para::new(13.0) };
    let (s, sh) = block(
        &inline(
            "What the realistic options change in this jet: its real HUD modes, symbol by symbol, with worked \
             examples, and the numbers that change how it flies.",
        ),
        &sub,
        140.0 * MM,
    );
    ops.extend(shift(s, x, y));
    y += sh + 18.0 * MM;
    if img.is_file() {
        // The picture a little greyed (the print's grayscale(15%)).
        let mut rgb = image::open(img).with_context(|| format!("{}", img.display()))?.to_rgb8();
        for p in rgb.pixels_mut() {
            let l = 0.2126 * p[0] as f32 + 0.7152 * p[1] as f32 + 0.0722 * p[2] as f32;
            for c in 0..3 {
                p[c] = (p[c] as f32 * 0.85 + l * 0.15).round() as u8;
            }
        }
        let h = w * rgb.height() as f32 / rgb.width() as f32;
        doc.images.push(Image::Rgb { w: rgb.width(), h: rgb.height(), pixels: rgb.into_raw() });
        ops.push(Op::Image { x, y, w, h, r: 0.0, img: doc.images.len() - 1 });
        ops.push(Op::Rect { x, y, w, h, r: 0.0, fill: None, stroke: Some((Rgb::hex(0x4a4d57), PX)) });
    }
    let foot = Para { color: Rgb::hex(0x8a8f9c), ..Para::new(9.0) };
    let (f, fh) = block(&inline("Pictures rendered from your own install of the game."), &foot, w);
    ops.extend(shift(f, x, ph - 16.0 * MM - fh));
    doc.pages.push(ops);
    Ok(())
}

/// Where the guides' Markdown is (`docs`, docs/guides) and the assets folder: one guide's PDF, its bytes.
fn pdf(docs: &Path, assets: &Path, jet: &str, pr: &dyn Progress) -> Result<Vec<u8>> {
    let md = std::fs::read_to_string(docs.join(format!("{jet}.md")))?;
    let shots = docs.join(format!("{jet}.shots.json"));
    let callouts: Vec<(String, usize)> = if shots.is_file() {
        let v: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&shots)?)?;
        v.as_array()
            .into_iter()
            .flatten()
            .map(|s| {
                let n = s["annotations"].as_array().map(Vec::len).unwrap_or(0);
                (s["name"].as_str().unwrap_or("").to_string(), n)
            })
            .collect()
    } else {
        vec![]
    };
    let out = assets.join("converted/guides");
    let mut doc = Doc::new(fonts(), "");
    let (flow, title) = body(&mut doc, &md, &out, &callouts, pr)?;
    let name = if title.is_empty() { jet.to_uppercase() } else { title };
    doc.title = name.clone();
    // The cover goes first: its picture is drawn into page 0 after the flow's pictures were loaded.
    cover(&mut doc, &name, &cover_picture(assets, jet))?;
    paginate(&mut doc, flow);
    doc.write()
}

/// The title page's picture: the Reference screen's, else the guide's own `external` shot (a jet outside the
/// Reference records: the F-16I).
fn cover_picture(assets: &Path, jet: &str) -> PathBuf {
    let r = assets.join(format!("converted/reference/img/{jet}.png"));
    if r.is_file() { r } else { assets.join(format!("converted/guides/shots/{jet}/external.jpg")) }
}

/// What a guide's PDF is made from: its Markdown, shots list, pictures and the cover picture.
fn inputs(docs: &Path, assets: &Path, jet: &str) -> Vec<PathBuf> {
    let mut v =
        vec![docs.join(format!("{jet}.md")), docs.join(format!("{jet}.shots.json")), cover_picture(assets, jet)];
    if let Ok(d) = std::fs::read_dir(assets.join("converted/guides/shots").join(jet)) {
        v.extend(d.flatten().map(|e| e.path()));
    }
    v.into_iter().filter(|p| p.is_file()).collect()
}

/// The guides with a shots list in `docs` (docs/guides), sorted.
pub fn all(docs: &Path) -> Vec<String> {
    let mut v: Vec<String> = std::fs::read_dir(docs)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| e.file_name().to_str()?.strip_suffix(".shots.json").map(String::from))
        .collect();
    v.sort();
    v
}

/// The PDFs of `jets` (empty: every guide) into assets/converted/guides; one newer than all its inputs is kept unless
/// `force`. A PDF that fails is named and the rest go on; then the first error.
pub fn make(docs: &Path, assets: &Path, jets: &[String], force: bool, pr: &dyn Progress) -> Result<()> {
    let jets = if jets.is_empty() { all(docs) } else { jets.to_vec() };
    let out = assets.join("converted/guides");
    std::fs::create_dir_all(&out)?;
    let mtime = |p: &Path| std::fs::metadata(p).and_then(|m| m.modified()).ok();
    let errors: Vec<anyhow::Error> = jets
        .par_iter()
        .filter_map(|jet| {
            let file = out.join(format!("{jet}.pdf"));
            // ponytail: inputs' times only, so a change to this code keeps the PDFs (--force remakes them).
            let fresh = !force
                && mtime(&file)
                    .is_some_and(|t| inputs(docs, assets, jet).iter().all(|p| mtime(p).is_some_and(|m| m <= t)));
            if fresh {
                pr.log(&format!("guide PDF: {jet} up to date"));
                return None;
            }
            let r = pdf(docs, assets, jet, pr).and_then(|b| {
                let tmp = file.with_extension("pdf.part");
                std::fs::write(&tmp, b)?;
                std::fs::rename(&tmp, &file)?;
                Ok(())
            });
            match r {
                Ok(()) => {
                    pr.log(&format!("guide PDF: {}", file.display()));
                    None
                }
                Err(e) => Some(e.context(format!("guide PDF {jet}"))),
            }
        })
        .collect();
    match errors.into_iter().next() {
        Some(e) => Err(e),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn styled(t: &str) -> Vec<(String, bool, bool, bool, bool)> {
        inline(t).into_iter().map(|r| (r.text, r.sty.bold, r.sty.italic, r.sty.code, r.sty.sup)).collect()
    }

    #[test]
    fn inline_markup() {
        let s = |t: &str, b, i, c, u| (t.to_string(), b, i, c, u);
        assert_eq!(
            styled("A **bold** and *it* `AL 300` [link](x.md)[^n] 2*3 \\*"),
            vec![
                s("A ", false, false, false, false),
                s("bold", true, false, false, false),
                s(" and ", false, false, false, false),
                s("it", false, true, false, false),
                s(" ", false, false, false, false),
                s("AL 300", false, false, true, false),
                s(" link", false, false, false, false),
                s("[n]", false, false, false, true),
                s(" 2*3 *", false, false, false, false),
            ]
        );
        assert_eq!(styled("[^n]: Source")[0], s("[n]", true, false, false, false));
    }

    #[test]
    fn hebrew_drawn_right_to_left() {
        assert_eq!(visual("\"אדיר\","), "\"רידא\",");
        assert_eq!(visual("F-35I"), "F-35I");
    }

    #[test]
    fn a_small_guide_makes_a_pdf() {
        let dir = std::env::temp_dir().join(format!("iaf-guide-pdf-{}", std::process::id()));
        let docs = dir.join("docs");
        std::fs::create_dir_all(&docs).unwrap();
        let mut md = String::from("# X pilot guide\n\nIntro with `code` and → − ⊗ Привет.\n\n## 1. Table\n\n");
        md += "| A | B |\n| --- | --- |\n";
        for k in 0..80 {
            md += &format!("| row {k} | some longer text in the second column |\n");
        }
        md += "\n### Sub\n\n- one\n- two\n\n1. first\n2. second\n\n---\n\n## 2. End\n\n![Missing](shots/x/a.png)\n\n1. a\n";
        std::fs::write(docs.join("x.md"), md).unwrap();
        std::fs::write(docs.join("x.shots.json"), r#"[{"name": "a", "annotations": [{}]}]"#).unwrap();
        struct Quiet;
        impl Progress for Quiet {
            fn log(&self, _: &str) {}
        }
        make(&docs, &dir, &[], false, &Quiet).unwrap();
        let b = std::fs::read(dir.join("converted/guides/x.pdf")).unwrap();
        assert!(b.starts_with(b"%PDF-1.7") && b.ends_with(b"%%EOF\n"));
        let pages = b.windows(13).filter(|w| w == b"/Type /Page /").count();
        assert!(pages >= 4, "cover, contents, the table over two pages: {pages}");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
