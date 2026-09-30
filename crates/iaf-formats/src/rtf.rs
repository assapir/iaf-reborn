//! Minimal RTF reader for the briefing texts (`resource/brief/{txt,text}/*.rtf`),
//! producing BBCode (bold / italic / underline / colour, paragraphs) for Godot's RichTextLabel.
//!
//! Handles the subset Word 97 wrote for the game and for the Hebrew pack: `\ansicpg`
//! (1252 English, 1255 Hebrew), `\'xx` escapes, `\uN` Unicode, `\par`, `\tab`, `\b`,
//! `\i`, `\ul`, `\plain`, and skips destination groups (font/colour tables, info, `\*…`).

/// Windows-1252 bytes 0x80..0x9F (the rest maps to Latin-1).
const CP1252_80: [char; 32] = [
    '€', '\u{81}', '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', '\u{8d}', 'Ž', '\u{8f}', '\u{90}', '‘', '’',
    '“', '”', '•', '–', '—', '˜', '™', 'š', '›', 'œ', '\u{9d}', 'ž', 'Ÿ',
];

fn decode_byte(b: u8, codepage: u32) -> char {
    match (codepage, b) {
        (_, 0x00..=0x7f) => b as char,
        (1255, 0xe0..=0xfa) => char::from_u32(0x05d0 + (b - 0xe0) as u32).unwrap_or('?'),
        (1255, 0xc0..=0xd2) => char::from_u32(0x05b0 + (b - 0xc0) as u32).unwrap_or('?'), // niqqud
        (1255, 0xa4) => '₪',
        (1255, 0xfd) => '\u{200e}',
        (1255, 0xfe) => '\u{200f}',
        (_, 0x80..=0x9f) => CP1252_80[(b - 0x80) as usize],
        _ => b as char,
    }
}

#[derive(Clone, Copy, Default)]
struct Style {
    bold: bool,
    italic: bool,
    underline: bool,
    skip: bool,
    /// Current font's code page (from its `\fcharset`), 0 = document default.
    font_codepage: u32,
    /// `\cfN` as N + 1 (0 = no `\cf` seen: default colour).
    color: u16,
}

/// The `\colortbl` entries as RGB (index 0 is "auto" and has no colour).
fn color_table(data: &[u8]) -> Vec<Option<[u8; 3]>> {
    let text = crate::bytes::latin1(data);
    let Some(start) = text.find("\\colortbl") else { return Vec::new() };
    let body = &text[start + 9..];
    let body = &body[..body.find('}').unwrap_or(body.len())];
    body.split(';')
        .map(|entry| {
            let get = |name: &str| {
                entry.find(name).and_then(|j| entry[j + name.len()..].chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse::<u8>().ok())
            };
            match (get("\\red"), get("\\green"), get("\\blue")) {
                (Some(r), Some(g), Some(b)) => Some([r, g, b]),
                _ => None,
            }
        })
        .collect()
}

/// Font number → code page, from `\fN … \fcharsetM` in the font table
/// (177 Hebrew → 1255, 178 Arabic → 1256; anything else uses the document code page).
fn font_codepages(data: &[u8]) -> Vec<(i32, u32)> {
    let text = crate::bytes::latin1(data);
    let Some(start) = text.find("\\fonttbl") else { return Vec::new() };
    let table = &text[start..];
    // Each font entry starts with `{\fN` (N digits); its charset follows before the next entry.
    let starts: Vec<usize> = table
        .match_indices("{\\f")
        .map(|(i, _)| i)
        .filter(|&i| table[i + 3..].starts_with(|c: char| c.is_ascii_digit()))
        .collect();
    let mut out = Vec::new();
    for (k, &i) in starts.iter().enumerate() {
        let end = starts.get(k + 1).copied().unwrap_or(table.len().min(i + 400));
        let entry = &table[i + 3..end];
        let digits: String = entry.chars().take_while(|c| c.is_ascii_digit()).collect();
        let Ok(n) = digits.parse::<i32>() else { continue };
        let cp = entry
            .find("\\fcharset")
            .map(|j| entry[j + 9..].chars().take_while(|c| c.is_ascii_digit()).collect::<String>())
            .and_then(|d| d.parse::<u32>().ok())
            .map_or(0, |cs| match cs {
                177 => 1255,
                178 => 1256,
                _ => 0,
            });
        out.push((n, cp));
    }
    out
}

/// Converts RTF to BBCode. Paragraphs become `\n`.
pub fn to_bbcode(data: &[u8]) -> String {
    let mut out = String::new();
    let mut codepage = 1252;
    let mut stack: Vec<Style> = Vec::new();
    let mut st = Style::default();
    let mut shown = Style::default(); // style currently open in `out`
    let mut i = 0;
    let mut pending_skip_uc = 0usize;
    let fonts = font_codepages(data);
    let colors = color_table(data);
    let color_of = |i: u16| if i == 0 { None } else { colors.get(i as usize - 1).copied().flatten() };
    let cp_of = |st: &Style, doc: u32| if st.font_codepage != 0 { st.font_codepage } else { doc };

    let sync = |out: &mut String, shown: &mut Style, st: &Style| {
        // Colour is the outermost tag: a change closes everything and reopens.
        let (had, want) = (color_of(shown.color), color_of(st.color));
        if had != want {
            let target = *st;
            let open = Style { color: shown.color, ..Style::default() };
            sync_tags(out, shown, &open);
            if had.is_some() {
                out.push_str("[/color]");
            }
            if let Some([r, g, b]) = want {
                out.push_str(&format!("[color=#{r:02x}{g:02x}{b:02x}]"));
            }
            shown.color = target.color;
        }
        sync_tags(out, shown, st);
    };
    fn sync_tags(out: &mut String, shown: &mut Style, st: &Style) {
        // Close in reverse order of opening, then reopen what is needed.
        if shown.underline && !st.underline {
            out.push_str("[/u]");
            shown.underline = false;
        }
        if shown.italic && !st.italic {
            out.push_str("[/i]");
            shown.italic = false;
        }
        if shown.bold && !st.bold {
            out.push_str("[/b]");
            shown.bold = false;
        }
        if st.bold && !shown.bold {
            out.push_str("[b]");
            shown.bold = true;
        }
        if st.italic && !shown.italic {
            out.push_str("[i]");
            shown.italic = true;
        }
        if st.underline && !shown.underline {
            out.push_str("[u]");
            shown.underline = true;
        }
    }

    let emit = |out: &mut String, shown: &mut Style, st: &Style, c: char| {
        if st.skip || c == '\0' {
            return;
        }
        sync(out, shown, st);
        match c {
            '[' => out.push_str("[lb]"),
            ']' => out.push_str("[rb]"),
            _ => out.push(c),
        }
    };

    while i < data.len() {
        let b = data[i];
        match b {
            b'{' => {
                stack.push(st);
                i += 1;
                // Destinations we don't render.
                let rest = &data[i..];
                if rest.starts_with(b"\\*")
                    || [&b"\\fonttbl"[..], b"\\colortbl", b"\\stylesheet", b"\\info", b"\\listtable", b"\\listoverridetable", b"\\pict", b"\\object", b"\\header", b"\\footer", b"\\pn"]
                        .iter()
                        .any(|d| rest.starts_with(d))
                {
                    st.skip = true;
                }
            }
            b'}' => {
                st = stack.pop().unwrap_or_default();
                i += 1;
            }
            b'\\' => {
                i += 1;
                let Some(&c) = data.get(i) else { break };
                if c == b'\'' {
                    let hex = std::str::from_utf8(data.get(i + 1..i + 3).unwrap_or(b"3f")).unwrap_or("3f");
                    let byte = u8::from_str_radix(hex, 16).unwrap_or(b'?');
                    i += 3;
                    if pending_skip_uc > 0 {
                        pending_skip_uc -= 1;
                    } else {
                        emit(&mut out, &mut shown, &st, decode_byte(byte, cp_of(&st, codepage)));
                    }
                    continue;
                }
                if !c.is_ascii_alphabetic() {
                    // Control symbol: \\ \{ \} \~ \- \_ …
                    let ch = match c {
                        b'~' => Some('\u{a0}'),
                        b'_' => Some('-'),
                        b'\\' | b'{' | b'}' => Some(c as char),
                        _ => None,
                    };
                    if let Some(ch) = ch {
                        emit(&mut out, &mut shown, &st, ch);
                    }
                    i += 1;
                    continue;
                }
                let start = i;
                while data.get(i).is_some_and(|c| c.is_ascii_alphabetic()) {
                    i += 1;
                }
                let word = std::str::from_utf8(&data[start..i]).unwrap_or("");
                let nstart = i;
                if data.get(i) == Some(&b'-') {
                    i += 1;
                }
                while data.get(i).is_some_and(|c| c.is_ascii_digit()) {
                    i += 1;
                }
                let param: Option<i32> = std::str::from_utf8(&data[nstart..i]).ok().and_then(|s| s.parse().ok());
                if data.get(i) == Some(&b' ') {
                    i += 1;
                }
                match word {
                    "ansicpg" => codepage = param.unwrap_or(1252) as u32,
                    "f" => {
                        let n = param.unwrap_or(0);
                        st.font_codepage = fonts.iter().find(|(f, _)| *f == n).map_or(0, |(_, cp)| *cp);
                    }
                    "par" | "line" => {
                        if !st.skip {
                            sync(&mut out, &mut shown, &Style::default());
                            out.push('\n');
                        }
                    }
                    "tab" => emit(&mut out, &mut shown, &st, '\t'),
                    "b" => st.bold = param != Some(0),
                    "i" => st.italic = param != Some(0),
                    "ul" => st.underline = param != Some(0),
                    "cf" => st.color = param.unwrap_or(0).max(0) as u16 + 1,
                    "ulnone" => st.underline = false,
                    "plain" => {
                        st = Style { skip: st.skip, font_codepage: st.font_codepage, ..Style::default() };
                    }
                    "u" => {
                        if let Some(n) = param {
                            let cp = if n < 0 { n + 65536 } else { n } as u32;
                            if let Some(ch) = char::from_u32(cp) {
                                emit(&mut out, &mut shown, &st, ch);
                            }
                            pending_skip_uc = 1;
                        }
                    }
                    "bullet" => emit(&mut out, &mut shown, &st, '•'),
                    "emdash" => emit(&mut out, &mut shown, &st, '—'),
                    "endash" => emit(&mut out, &mut shown, &st, '–'),
                    "lquote" => emit(&mut out, &mut shown, &st, '‘'),
                    "rquote" => emit(&mut out, &mut shown, &st, '’'),
                    "ldblquote" => emit(&mut out, &mut shown, &st, '“'),
                    "rdblquote" => emit(&mut out, &mut shown, &st, '”'),
                    _ => {}
                }
            }
            b'\r' | b'\n' => i += 1,
            _ => {
                if pending_skip_uc > 0 {
                    pending_skip_uc -= 1;
                } else {
                    emit(&mut out, &mut shown, &st, decode_byte(b, cp_of(&st, codepage)));
                }
                i += 1;
            }
        }
    }
    sync(&mut out, &mut shown, &Style::default());
    // Tidy: collapse runs of blank lines.
    let mut tidy = String::new();
    let mut blank = 0;
    for line in out.lines() {
        if line.trim().is_empty() {
            blank += 1;
            if blank > 1 {
                continue;
            }
        } else {
            blank = 0;
        }
        tidy.push_str(line.trim_end());
        tidy.push('\n');
    }
    tidy.trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_and_hebrew() {
        let en = to_bbcode(br"{\rtf1\ansi\ansicpg1252{\fonttbl{\f0 Arial;}}\plain\b Mission:\b0  Engines ON\par Line [2]}");
        assert_eq!(en, "[b]Mission:[/b] Engines ON\nLine [lb]2[rb]");
        let he = to_bbcode(br"{\rtf1\ansi\ansicpg1255\plain\rtlch \'ee\'e0\'fa\par}");
        assert_eq!(he, "מאת");
        let he2 = to_bbcode(br"{\rtf1\ansi\ansicpg1252{\fonttbl{\f0 Arial;}{\f4\fcharset177 David;}}\plain\f4 \'ee\'e0\'fa\par}");
        assert_eq!(he2, "מאת");
    }
}
