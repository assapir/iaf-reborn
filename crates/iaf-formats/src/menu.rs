//! Front-end menu definitions (`resource/menu/dat/*.trx`).
//!
//! Two kinds of file:
//! * **screens** — `sName tTitle x0 y0 x1 y1 flag`, then panels `side pName x y count` each
//!   followed by `count` buttons `Label x y w h Kind [arg]` (`Push`, `CheckGroup 1`, …);
//! * **lists** (mission/jet lists shown in a screen's content window) — a count, then rows
//!   `id f1 f2 f3 f4 Name rx ry rw rh tx0 ty0 tx1 ty1 titleKey dx0 dy0 dx1 dy1 descKey`.
//!
//! Coordinates are in the original 640×480 screen. Labels use `_` for spaces.

#[derive(Debug, Clone, PartialEq)]
pub struct Button {
    pub label: String,
    pub rect: [i32; 4],
    pub kind: String,
    pub arg: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Panel {
    pub side: String,
    pub name: String,
    pub pos: [i32; 2],
    pub buttons: Vec<Button>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Screen {
    pub name: String,
    pub title: String,
    /// Content window (x0, y0, x1, y1).
    pub window: [i32; 4],
    pub flag: i32,
    pub panels: Vec<Panel>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ListRow {
    /// Mission id (matches briefing files, e.g. 311 → brief/txt/311.rtf), −1 when not a mission.
    pub id: i32,
    pub flags: [i32; 4],
    pub name: String,
    /// Row rectangle inside the content window (x, y, w, h).
    pub rect: [i32; 4],
    pub title_box: [i32; 4],
    pub title_key: String,
    pub desc_box: [i32; 4],
    pub desc_key: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum MenuFile {
    Screen(Screen),
    List(Vec<ListRow>),
}

fn ints<const N: usize>(t: &[&str]) -> Option<[i32; N]> {
    let mut out = [0; N];
    for (o, s) in out.iter_mut().zip(t) {
        *o = s.parse().ok()?;
    }
    (t.len() >= N).then_some(out)
}

pub fn parse(data: &[u8]) -> Option<MenuFile> {
    let text = crate::bytes::latin1(data);
    let lines: Vec<Vec<&str>> =
        text.lines().map(|l| l.split_whitespace().collect::<Vec<_>>()).filter(|t| !t.is_empty()).collect();
    let first = lines.first()?;
    if first.len() == 1 {
        // List: count, then rows.
        let rows = lines[1..]
            .iter()
            .filter_map(|t| {
                if t.len() < 20 {
                    return None;
                }
                Some(ListRow {
                    id: t[0].parse().ok()?,
                    flags: ints(&t[1..5])?,
                    name: t[5].replace('_', " "),
                    rect: ints(&t[6..10])?,
                    title_box: ints(&t[10..14])?,
                    title_key: t[14].to_string(),
                    desc_box: ints(&t[15..19])?,
                    desc_key: t[19].to_string(),
                })
            })
            .collect();
        return Some(MenuFile::List(rows));
    }
    if first.len() < 7 {
        return None;
    }
    let mut screen = Screen {
        name: first[0].to_string(),
        title: first[1].to_string(),
        window: ints(&first[2..6])?,
        flag: first[6].parse().ok()?,
        panels: Vec::new(),
    };
    let mut i = 1;
    while i < lines.len() {
        let t = &lines[i];
        i += 1;
        if t.len() < 5 {
            continue;
        }
        let Some([x, y, count]) = ints::<3>(&t[2..5]) else { continue };
        let mut panel = Panel { side: t[0].to_string(), name: t[1].to_string(), pos: [x, y], buttons: Vec::new() };
        for b in lines.iter().skip(i).take(count as usize) {
            if let Some(rect) = b.get(1..5).and_then(ints::<4>) {
                panel.buttons.push(Button {
                    label: b[0].replace('_', " "),
                    rect,
                    kind: b.get(5).unwrap_or(&"Push").to_string(),
                    arg: b.get(6).map(|s| s.to_string()),
                });
            }
        }
        i += count as usize;
        screen.panels.push(panel);
    }
    Some(MenuFile::Screen(screen))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn screen_and_list() {
        let s = parse(b"sDemo  tDemoTitle  150  40  600  400  1\r\n\r\n\tleft pDemo 0 30 2\r\n\t\tAlpha 10 60 100 40 Push\r\n\t\tBravo_Two 10 110 100 40 CheckGroup 1\r\n").unwrap();
        let MenuFile::Screen(s) = s else { panic!() };
        assert_eq!(s.window, [150, 40, 600, 400]);
        assert_eq!(s.panels[0].buttons[1].label, "Bravo Two");
        assert_eq!(s.panels[0].buttons[1].arg.as_deref(), Some("1"));
        let l = parse(b"1\r\n901 0 0 0 1 Alpha 0 30 450 40 20 20 140 40 tDemo1 160 30 430 70 dDemo1\r\n").unwrap();
        let MenuFile::List(rows) = l else { panic!() };
        assert_eq!(rows[0].id, 901);
        assert_eq!(rows[0].desc_key, "dDemo1");
    }
}
