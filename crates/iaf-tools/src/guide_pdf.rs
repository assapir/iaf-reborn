//! A pilot guide (docs/guides/<jet>.md) as a print-styled A4 PDF: assets/converted/guides/<jet>.pdf, drawn with
//! pdf.rs and the fonts in crates/iaf-tools/fonts (tools/guide_fonts.py: the game's Heebo for all text, Hebrew
//! included, slanted for italic; Noto Sans Mono for code; DejaVu Sans's arrows, maths signs and Cyrillic, which Heebo
//! lacks), so a release bundle makes it with nothing installed (docs/setup.md). Text is shaped with rustybuzz,
//! ordered with unicode-bidi and broken at unicode-linebreak's opportunities.
//!
//! The Markdown subset is the in-game viewer's (iaf-reborn/menu/guide_md.gd): # / ## / ### headings, paragraphs,
//! **bold**, *italic*, `code`, one-level bullet / numbered lists, pipe tables, `---`, [text](link) and pictures on a
//! line of their own, `![caption](shots/<jet>/<name>.png)` under assets/converted/guides (the guide shots, guides.rs in
//! iaf-setup; a .jpg beside a .png is used in its place); a numbered list right under a picture is its legend (the
//! picture's numbered callouts, `annotations` in <jet>.shots.json: the counts must match, else a warning), kept on the
//! picture's page with badges like the callouts. A title page with the Reference screen's picture of the jet
//! (assets/converted/reference/img/<jet>.png, else the guide's `external` shot), then a table of contents with links.
//! The layout follows the earlier HTML print (docs/guides/README.md "Pictures and PDFs"): its CSS's sizes (in mm and
//! pt, the constants below) and a browser's line heights, table columns and page breaks, in Firefox's 1/80 pt units.
//! The PDF holds the original art, so it stays under assets/ (never committed).

use crate::pdf::{Doc, Font, Glyph, Image, Op, Rgb};
use crate::progress::Progress;
use anyhow::{Context, Result};
use rayon::prelude::*;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use unicode_bidi::{BidiInfo, Level};
use unicode_linebreak::linebreaks;

const MM: f32 = 72.0 / 25.4;
/// Firefox's page: A4 and the print CSS's margins (top 18 mm, sides 17 mm, bottom 20 mm), in its units.
const PAGE: (f32, f32) = (595.275, 841.8875);
const TOP: f32 = 51.025;
const SIDE: f32 = 48.1875;
const BOTTOM: f32 = 56.6875;
const WIDTH: f32 = 498.9;
/// A 1 px border as printed (Firefox rounds borders down to its 0.5 pt device pixels), and the h2's 2.5 px one.
const BORDER: f32 = 0.5;
const H2_BORDER: f32 = 1.5;
const BODY: f32 = 10.2;
const CODE: f32 = 9.0;
const INK: Rgb = Rgb::hex(0x1d1f24);
const GREEN: Rgb = Rgb::hex(0x2f6f4f);

const REG: usize = 0;
const BOLD: usize = 1;
const ITALIC: usize = 2;
const BOLD_ITALIC: usize = 3;
const MONO: usize = 4;
/// What Heebo lacks: arrows, maths signs, geometric shapes, Cyrillic.
const SYMBOLS: usize = 5;

/// Firefox's layout unit: 1/80 pt (1/60 CSS px).
fn au(v: f32) -> f32 {
    (v * 80.0).round() / 80.0
}

fn mm(v: f32) -> f32 {
    au(v * MM)
}

const HEEBO: &[u8] = include_bytes!("../fonts/Heebo-Regular.ttf");
const HEEBO_BOLD: &[u8] = include_bytes!("../fonts/Heebo-Bold.ttf");

fn fonts() -> &'static [Font] {
    static F: OnceLock<Vec<Font>> = OnceLock::new();
    F.get_or_init(|| {
        vec![
            Font::parse("Heebo-Regular", HEEBO),
            Font::parse("Heebo-Bold", HEEBO_BOLD),
            Font::parse("Heebo-Regular", HEEBO).oblique(),
            Font::parse("Heebo-Bold", HEEBO_BOLD).oblique(),
            Font::parse("NotoSansMono-Regular", include_bytes!("../fonts/NotoSansMono-Regular.ttf")),
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

fn face(bold: bool, italic: bool) -> usize {
    match (bold, italic) {
        (false, false) => REG,
        (true, false) => BOLD,
        (false, true) => ITALIC,
        (true, true) => BOLD_ITALIC,
    }
}

/// An inline element's box on a line (CSS 2.1 §10.8): its font, size, line height and raise above the baseline.
#[derive(Clone, Copy, Debug, PartialEq)]
struct InlineBox {
    font: usize,
    size: f32,
    lh: f32,
    rise: f32,
}

impl InlineBox {
    fn new(font: usize, size: f32, rise: f32) -> InlineBox {
        InlineBox { font, size, lh: au(1.5 * size), rise }
    }

    /// How far it reaches above and below the baseline: its line height split evenly around the font's ascent and
    /// descent, which Firefox rounds to its 0.5 pt device pixels.
    fn extent(&self) -> (f32, f32) {
        let f = &fonts()[self.font];
        let half = |v: f32| (v * 2.0 + 0.5).floor() / 2.0;
        let (a, d) = (half(f.line_ascent * self.size), half(f.line_descent * self.size));
        (self.rise + (self.lh + a - d) / 2.0, (self.lh - a + d) / 2.0 - self.rise)
    }
}

/// A paragraph's style: size, line height, colour, the base weight / slant (headings, captions), alignment, letter
/// spacing.
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
        Para { size, lh: au(1.5 * size), color: INK, bold: false, italic: false, center: false, spacing: 0.0 }
    }

    /// The paragraph's own box on every line (CSS's strut).
    fn strut(&self) -> InlineBox {
        InlineBox { font: face(self.bold, self.italic), size: self.size, lh: self.lh, rise: 0.0 }
    }
}

/// One character as laid out.
#[derive(Clone)]
struct Ch {
    c: char,
    /// The glyphs its cluster draws, on its first character (none on the others of a ligature and on spaces).
    glyphs: Vec<Glyph>,
    /// How many characters its cluster covers (0 inside another's).
    cluster: usize,
    /// Its bidi embedding level (odd: right to left).
    level: Level,
    font: usize,
    size: f32,
    rise: f32,
    /// Its cluster's advance, in Firefox's units.
    adv: f32,
    /// Its code span, and that span's padding before / after it.
    span: Option<usize>,
    pad_l: f32,
    pad_r: f32,
    /// The inline boxes it sits in (bold, italic, code, superscript, a fallback font's).
    boxes: Vec<InlineBox>,
}

/// A paragraph's characters: fonts, sizes, inline boxes, code padding, bidi levels and the advances shaped by
/// rustybuzz (a run of one font, style and direction at a time, as a browser shapes). Spaces collapse, as in HTML.
fn chars(runs: &[Run], p: &Para) -> Vec<Ch> {
    let f = fonts();
    let mut out: Vec<Ch> = vec![];
    let mut run_of: Vec<usize> = vec![];
    for (ri, r) in runs.iter().enumerate() {
        let (b, i) = (r.sty.bold || p.bold, r.sty.italic || p.italic);
        // CSS: code is 9 pt wherever it is; sup is `smaller` (÷ 1.2), raised 0.34 em of its parent.
        let size = if r.sty.code {
            CODE
        } else if r.sty.sup {
            p.size / 1.2
        } else {
            p.size
        };
        let rise = if r.sty.sup { au(0.34 * p.size) } else { 0.0 };
        let mut boxes = vec![];
        if r.sty.bold {
            boxes.push(InlineBox::new(face(true, p.italic), p.size, 0.0));
        }
        if r.sty.italic {
            boxes.push(InlineBox::new(face(p.bold, true), p.size, 0.0));
        }
        if r.sty.bold && r.sty.italic {
            boxes.push(InlineBox::new(BOLD_ITALIC, p.size, 0.0));
        }
        if r.sty.sup {
            boxes.push(InlineBox::new(face(b, i), size, rise));
        }
        if r.sty.code {
            boxes.push(InlineBox::new(MONO, CODE, rise));
        }
        let main = if r.sty.code { MONO } else { face(b, i) };
        for c in r.text.chars() {
            if c == ' ' && out.last().is_none_or(|l| l.c == ' ') {
                continue;
            }
            // The run's font, else the first fallback that has the character.
            let font = [main, REG, SYMBOLS, MONO].into_iter().find(|&k| c == ' ' || f[k].has(c)).unwrap_or(main);
            let mut bx = boxes.clone();
            if font != main {
                bx.push(InlineBox::new(font, size, rise));
            }
            let span = r.sty.code.then_some(r.span);
            let level = Level::ltr();
            let ch = Ch {
                c,
                glyphs: vec![],
                cluster: 0,
                level,
                font,
                size,
                rise,
                adv: 0.0,
                span,
                pad_l: 0.0,
                pad_r: 0.0,
                boxes: bx,
            };
            out.push(ch);
            run_of.push(ri);
        }
    }
    while out.last().is_some_and(|l| l.c == ' ') {
        out.pop();
        run_of.pop();
    }
    // Bidi levels: the paragraph's direction from its first strong character.
    let text: String = out.iter().map(|c| c.c).collect();
    let bidi = BidiInfo::new(&text, None);
    for (c, (at, _)) in out.iter_mut().zip(text.char_indices()) {
        c.level = bidi.levels[at];
    }
    // Shaping, run by run.
    let mut i = 0;
    while i < out.len() {
        let mut j = i + 1;
        while j < out.len() && run_of[j] == run_of[i] && out[j].font == out[i].font && out[j].level == out[i].level {
            j += 1;
        }
        let font = &f[out[i].font];
        let run: String = out[i..j].iter().map(|c| c.c).collect();
        let at: Vec<usize> = run.char_indices().map(|(b, _)| b).collect();
        let of_byte = |b: usize| at.iter().position(|&x| x == b).unwrap_or(at.len());
        let size = out[i].size;
        for g in font.shape(&run, out[i].level.is_rtl()) {
            let k = i + of_byte(g.cluster.start);
            let ch = &mut out[k];
            ch.cluster = of_byte(g.cluster.end) - of_byte(g.cluster.start);
            ch.glyphs.push(Glyph { id: g.id, text: 0..0, adv: g.adv * size, dx: g.dx * size, dy: g.dy * size });
        }
        for ch in &mut out[i..j] {
            let w: f32 = ch.glyphs.iter().map(|g| g.adv).sum();
            if ch.cluster > 0 {
                ch.adv = au(w) + p.spacing;
                if let Some(last) = ch.glyphs.last_mut() {
                    last.adv += ch.adv - w;
                }
            }
            if ch.c == ' ' {
                ch.glyphs.clear();
            }
        }
        i = j;
    }
    // A code span's padding: before its first character, after its last.
    let pad = mm(1.2);
    for k in 0..out.len() {
        if let Some(s) = out[k].span {
            if k == 0 || out[k - 1].span != Some(s) {
                out[k].pad_l = pad;
            }
            if out.get(k + 1).is_none_or(|n| n.span != Some(s)) {
                out[k].pad_r = pad;
            }
        }
    }
    out
}

/// An unbreakable piece of a paragraph: its characters, the width of the space before it and its own width.
struct Seg {
    chars: std::ops::Range<usize>,
    space: f32,
    w: f32,
}

/// The paragraph's unbreakable pieces: split at spaces and at UAX #14's other break opportunities.
fn segments(cs: &[Ch]) -> Vec<Seg> {
    let seg = |r: std::ops::Range<usize>, space: f32| {
        let w = cs[r.clone()].iter().map(|c| c.adv + c.pad_l + c.pad_r).sum();
        Seg { chars: r, space, w }
    };
    // UAX #14's break opportunities, as the characters they come before.
    let text: String = cs.iter().map(|c| c.c).collect();
    let at: Vec<usize> = text.char_indices().map(|(b, _)| b).collect();
    let mut breaks = vec![false; cs.len() + 1];
    for (b, _) in linebreaks(&text) {
        breaks[at.iter().position(|&x| x == b).unwrap_or(cs.len())] = true;
    }
    let mut out = vec![];
    let mut start: Option<usize> = None;
    let mut space = 0.0;
    for k in 0..cs.len() {
        if cs[k].c == ' ' {
            if let Some(s) = start.take() {
                out.push(seg(s..k, space));
            }
            space = cs[k].adv + cs[k].pad_l + cs[k].pad_r;
            continue;
        }
        let s = *start.get_or_insert(k);
        if cs.get(k + 1).is_some_and(|n| n.c != ' ') && breaks[k + 1] {
            out.push(seg(s..k + 1, space));
            start = None;
            space = 0.0;
        }
    }
    if let Some(s) = start {
        out.push(seg(s..cs.len(), space));
    }
    out
}

/// The widest unbreakable piece and the whole text on one line (a table cell's min / max content widths).
fn text_widths(runs: &[Run], p: &Para) -> (f32, f32) {
    let segs = segments(&chars(runs, p));
    let min = segs.iter().map(|s| s.w).fold(0.0, f32::max);
    let max = segs.iter().enumerate().map(|(k, s)| s.w + if k > 0 { s.space } else { 0.0 }).sum();
    (min, max)
}

/// The text broken into lines `width` wide, greedily as Firefox does: one op list per line (its top at y 0, from
/// x 0) and the line's height.
fn wrap(runs: &[Run], p: &Para, width: f32) -> Vec<(Vec<Op>, f32)> {
    let cs = chars(runs, p);
    let segs = segments(&cs);
    let pad = mm(1.2);
    let mut rows: Vec<Vec<&Seg>> = vec![];
    let mut w = 0.0;
    for seg in &segs {
        // A break inside a code span keeps room for the span's end padding (Firefox reserves an open inline's end).
        let last = &cs[seg.chars.end - 1];
        let reserve = if last.span.is_some() && last.pad_r == 0.0 { pad } else { 0.0 };
        match rows.last_mut() {
            Some(row) if w + seg.space + seg.w + reserve <= width + 0.001 => {
                w += seg.space + seg.w;
                row.push(seg);
            }
            _ => {
                rows.push(vec![seg]);
                w = seg.w;
            }
        }
    }
    let mono = fonts()[MONO].line_ascent * CODE;
    let half = |v: f32| (v * 2.0 + 0.5).floor() / 2.0;
    let (code_up, code_h) = (half(mono), half(mono) + half(fonts()[MONO].line_descent * CODE));
    rows.iter()
        .map(|row| {
            let (mut up, mut down) = p.strut().extent();
            for seg in row {
                for c in &cs[seg.chars.clone()] {
                    for b in &c.boxes {
                        let (u, d) = b.extent();
                        up = up.max(u);
                        down = down.max(d);
                    }
                }
            }
            let (up, down) = (au(up), au(down));
            let total: f32 = row.iter().enumerate().map(|(k, s)| s.w + if k > 0 { s.space } else { 0.0 }).sum();
            let mut x = if p.center { (width - total) / 2.0 } else { 0.0 };
            let mut text: Vec<Op> = vec![];
            // A code span's background: from its padding's start to its end on this line.
            let mut boxes: Vec<(usize, f32, f32)> = vec![];
            let mut gap = true; // a space or padding since the last glyph: a new text op
            // The line's characters in visual order (UAX #9's reordering of its levels).
            let line = row[0].chars.start..row[row.len() - 1].chars.end;
            let levels: Vec<Level> = cs[line.clone()].iter().map(|c| c.level).collect();
            for k in BidiInfo::reorder_visual(&levels) {
                let k = line.start + k;
                let c = &cs[k];
                let x0 = x;
                if c.pad_l > 0.0 {
                    x += c.pad_l;
                    gap = true;
                }
                if !c.glyphs.is_empty() {
                    let joins = !gap
                        && matches!(text.last(), Some(Op::Text { font, size, y, .. })
                            if *font == c.font && *size == c.size && *y == up - c.rise);
                    if !joins {
                        text.push(Op::Text {
                            x,
                            y: up - c.rise,
                            font: c.font,
                            size: c.size,
                            color: p.color,
                            text: String::new(),
                            glyphs: vec![],
                        });
                    }
                    if let Some(Op::Text { text: t, glyphs, .. }) = text.last_mut() {
                        // The cluster's characters: this one and the next ones it covers (a ligature).
                        let shown: String = cs[k..(k + c.cluster).min(cs.len())].iter().map(|c| c.c).collect();
                        let r = t.len()..t.len() + shown.len();
                        t.push_str(&shown);
                        glyphs.extend(c.glyphs.iter().map(|g| Glyph { text: r.clone(), ..g.clone() }));
                    }
                    gap = false;
                } else if c.adv > 0.0 {
                    gap = true;
                }
                x += c.adv;
                if c.pad_r > 0.0 {
                    x += c.pad_r;
                    gap = true;
                }
                if let Some(s) = c.span {
                    match boxes.last_mut() {
                        Some(b) if b.0 == s => b.2 = x,
                        _ => boxes.push((s, x0, x)),
                    }
                }
            }
            let mut ops: Vec<Op> = boxes
                .into_iter()
                .map(|(_, x0, x1)| Op::Rect {
                    x: x0,
                    y: up - code_up - mm(0.2),
                    w: x1 - x0,
                    h: code_h + 2.0 * mm(0.2),
                    r: MM,
                    fill: Some(Rgb::hex(0xeef0f3)),
                    stroke: None,
                })
                .collect();
            ops.extend(text);
            (ops, up + down)
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
            Op::Text { x, y, font, size, color, text, glyphs } => {
                Op::Text { x: x + dx, y: y + dy, font, size, color, text, glyphs }
            }
            Op::Image { x, y, w, h, r, img } => Op::Image { x: x + dx, y: y + dy, w, h, r, img },
            Op::Link { x, y, w, h, dest } => Op::Link { x: x + dx, y: y + dy, w, h, dest },
        })
        .collect()
}

/// A paragraph as one block of ops (all its lines) and its height.
fn block(runs: &[Run], p: &Para, width: f32) -> (Vec<Op>, f32) {
    let mut ops = vec![];
    let mut h = 0.0;
    for (l, lh) in wrap(runs, p, width) {
        ops.extend(shift(l, 0.0, h));
        h += lh;
    }
    (ops, h)
}

// ---- Blocks and pages -------------------------------------------------------------------------------------------

/// An unbreakable piece of the flow: a line, a table row, a figure. Margins collapse as CSS's do.
#[derive(Clone, Default)]
struct Slice {
    h: f32,
    mt: f32,
    mb: f32,
    ops: Vec<Op>,
    /// A page break after it.
    break_after: bool,
    /// A table row's header, repeated at the top of a page the row starts (index into Flow::headers).
    header: Option<usize>,
    /// Destinations at its top (a heading's id).
    anchors: Vec<String>,
    /// Kept on the page of the slice after it (a heading, a table's header row).
    keep: bool,
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
        for (i, (l, h)) in ls.into_iter().enumerate() {
            self.slices.push(Slice {
                h,
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
            Image::Jpeg(std::fs::read(f).with_context(|| format!("{}", f.display()))?)
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
            y += mm(1.0);
        }
        let d = mm(5.0);
        let (t, h) = block(&inline(it), &p, width - mm(7.5));
        ops.push(Op::Rect {
            x,
            y: y + mm(0.2),
            w: d,
            h: d,
            r: d / 2.0,
            fill: Some(Rgb::hex(0xffcc1a)),
            stroke: Some((Rgb::hex(0x0d0d0d), BORDER)),
        });
        let n = Para { center: true, bold: true, lh: d, ..Para::new(7.6) };
        let (num, _) = block(&[Run { text: (first + i + 1).to_string(), sty: Sty::default(), span: 0 }], &n, d);
        ops.extend(shift(num, x, y + mm(0.2)));
        ops.extend(shift(t, x + mm(7.5), y));
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
            flow.para(&inline(&para.join(" ")), &body, SIDE, WIDTH, 0.0, mm(3.0));
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
                    1 => (22.0, 0.0, mm(4.0), INK),
                    2 => (16.0, mm(9.0), mm(3.0), INK),
                    _ => (12.0, mm(6.0), mm(2.0), GREEN),
                };
                let p = Para { bold: true, color, ..Para::new(size) };
                let (mut ops, mut h) = block(&inline(&text), &p, WIDTH);
                if level == 2 {
                    h += mm(2.0) + H2_BORDER;
                    let y = h - H2_BORDER / 2.0;
                    ops.push(Op::Line { x0: 0.0, y0: y, x1: WIDTH, y1: y, color: GREEN, width: H2_BORDER });
                }
                // CSS: main > h2:first-child has no top margin.
                let mt = if level == 2 && flow.slices.is_empty() { 0.0 } else { mt };
                flow.slices.push(Slice {
                    h,
                    mt,
                    mb,
                    ops: shift(ops, SIDE, 0.0),
                    anchors: vec![id],
                    keep: true,
                    ..Default::default()
                });
            }
        } else if t == "---" || t == "***" {
            flush(&mut flow, &mut para);
            let next = lines[i + 1..].iter().map(|l| l.trim()).find(|l| !l.is_empty()).unwrap_or("");
            if !next.starts_with("## ") {
                let color = Rgb::hex(0xd4d6dc);
                flow.slices.push(Slice {
                    h: BORDER,
                    mt: mm(5.0),
                    mb: mm(5.0),
                    ops: vec![Op::Line {
                        x0: SIDE,
                        y0: BORDER / 2.0,
                        x1: SIDE + WIDTH,
                        y1: BORDER / 2.0,
                        color,
                        width: BORDER,
                    }],
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
                let w = if small { au(WIDTH * 0.46) } else { WIDTH };
                // CSS: border-box sizing, so the picture's ratio holds inside its 1 px border.
                let h = au((w - 2.0 * BORDER) * ph as f32 / pw as f32 + 2.0 * BORDER);
                let x = SIDE + (WIDTH - w) / 2.0;
                let img = picture(doc, &path)?;
                let border = Rgb::hex(0xc8cbd2);
                let mut ops = vec![
                    Op::Image { x, y: 0.0, w, h, r: mm(1.5), img },
                    Op::Rect { x, y: 0.0, w, h, r: mm(1.5), fill: None, stroke: Some((border, BORDER)) },
                ];
                let (c, ch) = block(&inline(cap), &caption, WIDTH);
                ops.extend(shift(c, SIDE, h + mm(1.8)));
                let mut total = h + mm(1.8) + ch;
                let pic = Slice { h: total, mt: mm(3.0), mb: mm(6.0), ops: ops.clone(), ..Default::default() };
                if !items.is_empty() {
                    let (l, lh) = legend(&items, 0, SIDE, WIDTH);
                    ops.extend(shift(l, 0.0, total + mm(2.5)));
                    total += mm(2.5) + lh;
                }
                if total <= PAGE.1 - TOP - BOTTOM {
                    flow.slices.push(Slice { h: total, mt: mm(3.0), mb: mm(6.0), ops, ..Default::default() });
                } else {
                    // Taller than a page: the legend's items flow on.
                    flow.slices.push(Slice { mb: mm(2.5), ..pic });
                    for (k, it) in items.iter().enumerate() {
                        let (l, lh) = legend(std::slice::from_ref(it), k, SIDE, WIDTH);
                        flow.slices.push(Slice { h: lh, mt: mm(1.0), mb: mm(1.0), ops: l, ..Default::default() });
                    }
                }
            } else {
                flow.para(&inline(cap), &Para { italic: true, ..body }, SIDE, WIDTH, 0.0, mm(3.0));
                if !items.is_empty() {
                    let (l, lh) = legend(&items, 0, SIDE, WIDTH);
                    flow.slices.push(Slice { h: lh, mt: mm(2.5), mb: mm(1.0), ops: l, ..Default::default() });
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
                    SIDE + mm(6.0),
                    WIDTH - mm(6.0),
                    mm(0.6),
                    if k + 1 == n { mm(3.0) } else { mm(0.6) },
                );
                // The marker and a space end 0.15 em before the item's text (the print's gap).
                let marker = if ordered { format!("{}. ", k + 1) } else { "\u{2022} ".to_string() };
                let mrun = [Run { text: marker, sty: Sty::default(), span: 0 }];
                let mw: f32 = fonts()[REG].shape(&mrun[0].text, false).iter().map(|g| g.adv).sum::<f32>() * BODY;
                let ml = wrap(&mrun, &body, WIDTH);
                if let (Some(first), Some((m, _))) = (flow.slices.get_mut(at), ml.into_iter().next()) {
                    first.ops.extend(shift(m, SIDE + mm(6.0) - mw - 0.15 * BODY, 0.0));
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
    flow.slices.push(Slice { h: h + mm(2.0), mb: mm(3.0), ops: shift(ops, SIDE, 0.0), ..Default::default() });
    for (level, text, id) in toc {
        let (p, pad, indent) = if *level == 2 {
            (Para::new(BODY), mm(1.6), 0.0)
        } else {
            (Para { color: Rgb::hex(0x4b4f5a), ..Para::new(9.4) }, mm(0.6), mm(7.0))
        };
        let (t, th) = block(&inline(text), &p, WIDTH - indent);
        let mut ops = shift(t, SIDE + indent, pad);
        let mut h = th + 2.0 * pad;
        if *level == 2 {
            ops.push(Op::Line {
                x0: SIDE,
                y0: h + BORDER / 2.0,
                x1: SIDE + WIDTH,
                y1: h + BORDER / 2.0,
                color: Rgb::hex(0xe3e4e8),
                width: BORDER,
            });
            h += BORDER;
        }
        ops.push(Op::Link { x: SIDE, y: 0.0, w: WIDTH, h, dest: id.clone() });
        flow.slices.push(Slice { h, mt: mm(0.6), mb: mm(0.6), ops, ..Default::default() });
    }
}

/// A pipe table: CSS's automatic column widths over the page's width, a dark header row repeated on each page,
/// rows striped and never split.
fn table(flow: &mut Flow, rows: &[Vec<String>]) {
    let n = rows.iter().map(Vec::len).max().unwrap_or(0);
    if n == 0 {
        return;
    }
    let pad = mm(2.2);
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
    // A header cell sits in the middle of its row (the browser's vertical-align for th), a body cell at the top.
    let row = |r: &[Vec<Run>], p: &Para, vpad: f32, middle: bool| -> (Vec<Op>, f32) {
        let blocks: Vec<(Vec<Op>, f32)> =
            r.iter().enumerate().map(|(k, c)| block(c, p, widths[k] - 2.0 * pad)).collect();
        let h = blocks.iter().map(|b| b.1).fold(0.0, f32::max);
        let mut ops = vec![];
        let mut x = SIDE;
        for (k, (t, th)) in blocks.into_iter().enumerate() {
            let dy = if middle { (h - th) / 2.0 } else { 0.0 };
            ops.extend(shift(t, x + pad, vpad + dy));
            x += widths[k];
        }
        (ops, h + 2.0 * vpad)
    };
    let (hops, hh) = row(&cells[0], &head, mm(1.6), true);
    let mut ops =
        vec![Op::Rect { x: SIDE, y: 0.0, w: WIDTH, h: hh, r: 0.0, fill: Some(Rgb::hex(0x2f3440)), stroke: None }];
    ops.extend(hops);
    let header = Slice { h: hh, ops, ..Default::default() };
    flow.headers.push(header.clone());
    let hi = flow.headers.len() - 1;
    let alone = cells.len() == 1; // a header and no rows: the table's bottom margin on it
    flow.slices.push(Slice { mt: mm(2.0), mb: if alone { mm(5.0) } else { 0.0 }, keep: !alone, ..header });
    let last = cells.len() - 1;
    for (ri, r) in cells.iter().enumerate().skip(1) {
        let (t, th) = row(r, &cell, mm(1.4), false);
        let h = th + BORDER;
        let mut ops = vec![];
        if ri % 2 == 0 {
            ops.push(Op::Rect { x: SIDE, y: 0.0, w: WIDTH, h, r: 0.0, fill: Some(Rgb::hex(0xf5f6f8)), stroke: None });
        }
        ops.extend(t);
        let color = Rgb::hex(0xdfe1e6);
        let y = h - BORDER / 2.0;
        ops.push(Op::Line { x0: SIDE, y0: y, x1: SIDE + WIDTH, y1: y, color, width: BORDER });
        flow.slices.push(Slice {
            h,
            mb: if ri == last { mm(5.0) } else { 0.0 },
            ops,
            header: Some(hi),
            ..Default::default()
        });
    }
}

/// The flow on pages after the ones in `doc`: a slice that does not fit starts the next page;
/// margins collapse between slices and vanish at a page's top; a table row that starts a page brings its table's
/// header; a heading moves to the next page with the slice after it.
fn paginate(doc: &mut Doc, flow: Flow) {
    let bottom = PAGE.1 - BOTTOM;
    let mut page: Vec<Op> = vec![];
    let mut y = TOP;
    let mut pending = 0.0f32; // the last slice's bottom margin
    let mut fresh = true;
    for (i, sl) in flow.slices.iter().enumerate() {
        // The height down to the end of the first slice after this one and the headings that follow it.
        let mut need = sl.mt.max(pending) + sl.h;
        let mut k = i;
        while flow.slices[k].keep && k + 1 < flow.slices.len() {
            need += flow.slices[k + 1].mt.max(flow.slices[k].mb) + flow.slices[k + 1].h;
            k += 1;
        }
        // A chain taller than a page cannot be kept together: the slice alone decides.
        if need > bottom - TOP {
            need = sl.mt.max(pending) + sl.h;
        }
        if !fresh && y + need > bottom + 0.001 {
            doc.pages.push(std::mem::take(&mut page));
            y = TOP;
            fresh = true;
        }
        let parts = match sl.header {
            Some(h) if fresh => vec![&flow.headers[h], sl],
            _ => vec![sl],
        };
        for part in parts {
            if !fresh {
                y += part.mt.max(pending);
            }
            for a in &part.anchors {
                doc.dest(a, doc.pages.len(), y);
            }
            page.extend(shift(part.ops.clone(), 0.0, y));
            y += part.h;
            pending = part.mb;
            fresh = false;
        }
        if sl.break_after {
            doc.pages.push(std::mem::take(&mut page));
            y = TOP;
            fresh = true;
        }
    }
    if !page.is_empty() {
        doc.pages.push(page);
    }
}

/// The title page: the dark cover with the jet's picture.
fn cover(doc: &mut Doc, name: &str, img: &Path) -> Result<()> {
    let (pw, ph) = PAGE;
    let (x, w) = (mm(22.0), pw - mm(44.0));
    let mut ops = vec![Op::Rect { x: 0.0, y: 0.0, w: pw, h: ph, r: 0.0, fill: Some(Rgb::hex(0x23252c)), stroke: None }];
    let mut y = mm(34.0);
    let kicker = Para { color: Rgb::hex(0x9ea3b0), spacing: 0.32 * 10.0, ..Para::new(10.0) };
    let (k, kh) = block(&inline("JANE'S IAF \u{b7} REBORN"), &kicker, w);
    ops.extend(shift(k, x, y));
    y += kh + mm(6.0);
    let h1 = Para { bold: true, color: Rgb::hex(0xf2f2f4), lh: 44.0, ..Para::new(40.0) };
    let (t, th) = block(&inline(name), &h1, w);
    ops.extend(shift(t, x, y));
    y += th + mm(4.0);
    let sub = Para { color: Rgb::hex(0xc9ccd4), ..Para::new(13.0) };
    let (s, sh) = block(
        &inline(
            "What the realistic options change in this jet: its real HUD modes, symbol by symbol, with worked \
             examples, and the numbers that change how it flies.",
        ),
        &sub,
        mm(140.0),
    );
    ops.extend(shift(s, x, y));
    y += sh + mm(18.0);
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
        ops.push(Op::Rect { x, y, w, h, r: 0.0, fill: None, stroke: Some((Rgb::hex(0x4a4d57), BORDER)) });
    }
    let foot = Para { color: Rgb::hex(0x8a8f9c), ..Para::new(9.0) };
    let (f, fh) = block(&inline("Pictures rendered from your own install of the game."), &foot, w);
    ops.extend(shift(f, x, ph - mm(16.0) - fh));
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
    let mut doc = Doc::new(fonts(), "", PRODUCER);
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

/// The PDFs' producer: its version names the layout (2: Heebo, krilla), so an older PDF is made again.
const PRODUCER: &str = "iaf-tools guide_pdf 2";

/// Whether the PDF at `p` was made by this layout: its producer, in the document information near the file's end.
fn made_by_this(p: &Path) -> bool {
    use std::io::{Read, Seek, SeekFrom};
    let Ok(mut f) = std::fs::File::open(p) else { return false };
    let mut tail = vec![];
    f.seek(SeekFrom::End(-65536)).or_else(|_| f.seek(SeekFrom::Start(0))).is_ok()
        && f.read_to_end(&mut tail).is_ok()
        && tail.windows(PRODUCER.len()).any(|w| w == PRODUCER.as_bytes())
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
            // ponytail: inputs' times and the layout's version only; another code change keeps the PDFs (--force
            // remakes them). Bump PRODUCER when the look changes.
            let fresh = !force
                && made_by_this(&file)
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

    /// Line heights and break opportunities (docs/guides/README.md "Pictures and PDFs").
    #[test]
    fn line_heights_and_breaks() {
        let p = Para::new(9.0);
        let h = |t: &str, p: &Para| wrap(&inline(t), p, 1000.0)[0].1;
        assert!((h("plain", &p) - 13.5).abs() < 1e-3);
        assert!(h("a note[^1]", &Para::new(BODY)) > au(1.5 * BODY), "a superscript raises the line");
        let pieces = segments(&chars(&inline("F-16 target-aspect 1/2 AN/APG"), &p)).len();
        assert_eq!(pieces, 6, "F-16 | target- aspect | 1/2 | AN/ APG");
    }

    #[test]
    fn hebrew_drawn_right_to_left() {
        let p = Para::new(9.0);
        let (ops, _) = block(&inline("F-35I (Hebrew \"אדיר\") flies"), &p, 1000.0);
        let shown: String = ops
            .iter()
            .filter_map(|o| match o {
                Op::Text { text, .. } => Some(text.as_str()),
                _ => None,
            })
            .collect();
        assert!(shown.contains("רידא"), "the Hebrew word in visual order: {shown}");
        assert!(shown.starts_with("F-35I"), "{shown}");
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
        assert!(made_by_this(&dir.join("converted/guides/x.pdf")), "the producer marks this layout's PDF");
        let b = std::fs::read(dir.join("converted/guides/x.pdf")).unwrap();
        assert!(b.starts_with(b"%PDF-") && b.windows(5).any(|w| w == b"%%EOF"));
        let pages = b.windows(11).filter(|w| w.starts_with(b"/Type/Page") && w[10] != b's').count();
        assert!(pages >= 4, "cover, contents, the table over two pages: {pages}");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
