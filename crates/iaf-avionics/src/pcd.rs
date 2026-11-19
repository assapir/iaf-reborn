//! The F-35I's panoramic cockpit display (PCD) as the pilot lays it out (docs/real-mfd.md "F-35I", docs/f35i.md §4.3,
//! modern-iaf/docs/research/f35-cockpit.md §3): what each portal and window shows, the MENU grid, widening a portal
//! over its half (Code One's LEFT / RIGHT arrows), enlarging it over its windows (the DOWN arrow; its windows become
//! tabs), a window swapped into its portal, the function bar's pop-ups and its SWAP (its halves trade places, the
//! portals stay: a simulator manual), CRUS (the default layout), the portal with the cursor (the sensor of interest)
//! and the five preset layouts. The drawing is `shared/cockpit/pcd.gd`.
//!
//! Geometry: the glass under the function bar is a unit square; the halves are x 0–0.5 and 0.5–1; a quarter portal is
//! 0.25 wide; the windows' row is `win` tall along the foot.

/// The MENU grid's formats, in its order (the simulator manual's and the LM videos' list, real-mfd.md "Formats"; ASR
/// is SRCH's air-to-surface page, which the radar's mode picks).
pub const FORMATS: [&str; 20] = [
    "TSD-1", "TSD-2", "TSD-3", "SRCH", "SMS", "WPN-A", "WPN-S", "TFLIR", "DAS", "TWD", "EFI", "ICAWS", "FUEL", "ENG",
    "CNI", "FCS", "PHM", "CHKLST", "DIM", "HUD",
];

/// Formats only the function bar opens (pop-ups, not in the MENU): the autopilot's and the additional MENU page (CRUS).
pub const POPUPS: [&str; 2] = ["AP", "MENU"];

/// A format's name as the static string the layout keeps, None when unknown.
pub fn format(s: &str) -> Option<&'static str> {
    FORMATS.iter().chain(POPUPS.iter()).copied().find(|f| *f == s)
}

/// x, y, width, height in the glass under the function bar (0..1).
pub type Rect = (f64, f64, f64, f64);

/// One layout: per portal (0–1 the left half, 2–3 the right) its format and its two windows'; per half whether its
/// first portal is widened over it (the second hidden, its windows still shown); per portal whether it is enlarged
/// over its windows (they become its tabs; a widened half reads its first portal's).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Layout {
    pub main: [&'static str; 4],
    pub tabs: [[&'static str; 2]; 4],
    pub wide: [bool; 2],
    pub big: [bool; 4],
}

/// The five layouts the pilot sets in mission planning and calls in flight (SLDinfo's LM slides; their contents
/// inferred): 1 the user's simulator photo (the left half one large portal, the right two portals over windows; the
/// default since 2026-11-17); 2 LM's four portals over eight windows; 3 two large portals (Code One's "2 large"); 4 LM
/// slide 8, a double-width TSD over its four windows with the TFLIR and the radar enlarged on the right (3 portals and
/// 4 windows); 5 LM slide 7, four portals over six windows (the first enlarged).
pub const PRESETS: [Layout; 5] = [
    Layout {
        main: ["TSD-1", "SMS", "SRCH", "TFLIR"],
        tabs: [["TSD-2", "ENG"], ["TSD-3", "ICAWS"], ["TWD", "FUEL"], ["EFI", "ENG"]],
        wide: [true, false],
        big: [true, false, false, false],
    },
    Layout {
        main: ["TSD-1", "SMS", "SRCH", "TFLIR"],
        tabs: [["TSD-2", "WPN-S"], ["FUEL", "ENG"], ["TWD", "WPN-A"], ["EFI", "ICAWS"]],
        wide: [false, false],
        big: [false; 4],
    },
    Layout {
        main: ["TSD-1", "SMS", "SRCH", "TFLIR"],
        tabs: [["TSD-2", "FUEL"], ["ENG", "ICAWS"], ["TWD", "EFI"], ["WPN-S", "CNI"]],
        wide: [true, true],
        big: [true, false, true, false],
    },
    Layout {
        main: ["TSD-1", "TSD-2", "TFLIR", "SRCH"],
        tabs: [["FUEL", "ENG"], ["ICAWS", "EFI"], ["SMS", "TWD"], ["WPN-S", "CNI"]],
        wide: [true, false],
        big: [false, false, true, true],
    },
    Layout {
        main: ["TSD-1", "TSD-2", "SRCH", "TFLIR"],
        tabs: [["TSD-3", "SMS"], ["FUEL", "ENG"], ["TWD", "ICAWS"], ["EFI", "CNI"]],
        wide: [false, false],
        big: [true, false, false, false],
    },
];

/// The display's state.
#[derive(Clone, Debug, PartialEq)]
pub struct Pcd {
    pub layout: Layout,
    /// The preset last called (0–4).
    pub preset: usize,
    /// Per portal: its MENU grid open.
    pub menu: [bool; 4],
    /// The MENU grid's cursor (an index into FORMATS).
    pub menu_cur: usize,
    /// The portal with the cursor (the sensor of interest on the display).
    pub focus: usize,
    /// DMS up: the sensor of interest is the helmet / HUD, not a portal.
    pub hud_soi: bool,
    /// A function bar pop-up: its portal and the format it covers.
    pub popup: Option<(usize, &'static str)>,
    /// The function bar's SWAP: its two halves traded (the portals stay).
    pub bar_swapped: bool,
    /// The TSD-1 / 2 / 3's layer setting (the FLC's push, `flc_push`): 0 every layer, 1 without the map and the route,
    /// 2 the tracks only (the SAM sites off too; inferred).
    pub layers: [u8; 3],
}

impl Default for Pcd {
    fn default() -> Self {
        Pcd {
            layout: PRESETS[0],
            preset: 0,
            menu: [false; 4],
            menu_cur: 0,
            focus: 2,
            hud_soi: false,
            popup: None,
            bar_swapped: false,
            layers: [0; 3],
        }
    }
}

fn first(i: usize) -> usize {
    i & !1
}

impl Pcd {
    /// Preset `n` (0–4): its layout; menus and pop-ups closed; the cursor kept on a shown portal.
    pub fn apply(&mut self, n: usize) {
        self.preset = n % PRESETS.len();
        self.layout = PRESETS[self.preset];
        self.menu = [false; 4];
        self.popup = None;
        if !self.shown(self.focus) {
            self.focus = first(self.focus);
        }
    }

    /// Portal `i` shows (a widened half hides its second).
    pub fn shown(&self, i: usize) -> bool {
        !(self.layout.wide[i / 2] && i % 2 == 1)
    }

    /// Portal `i` is enlarged over its windows.
    pub fn enlarged(&self, i: usize) -> bool {
        self.layout.big[if self.layout.wide[i / 2] { first(i) } else { i }]
    }

    /// The four portals' rects (None: hidden).
    pub fn portals(&self, win: f64) -> [Option<Rect>; 4] {
        std::array::from_fn(|i| {
            let h = (i / 2) as f64 * 0.5;
            let tall = if self.enlarged(i) { 1.0 } else { 1.0 - win };
            if !self.shown(i) {
                None
            } else if self.layout.wide[i / 2] {
                Some((h, 0.0, 0.5, tall))
            } else {
                Some((h + 0.25 * (i % 2) as f64, 0.0, 0.25, tall))
            }
        })
    }

    /// The windows shown along the foot: (rect, portal, its window 0 / 1). A widened half shows both portals' four;
    /// an enlarged portal shows none (they are its tabs).
    pub fn windows(&self, win: f64) -> Vec<(Rect, usize, usize)> {
        let mut out = Vec::new();
        for i in 0..4 {
            if self.enlarged(i) {
                continue;
            }
            for t in 0..2 {
                out.push(((0.125 * (2 * i + t) as f64, 1.0 - win, 0.125, win), i, t));
            }
        }
        out
    }

    /// The tabs along an enlarged portal's foot: its windows' formats; a widened half's also the hidden portal's
    /// format and windows. Empty when not enlarged.
    pub fn tabs(&self, i: usize) -> Vec<&'static str> {
        if !self.shown(i) || !self.enlarged(i) {
            return Vec::new();
        }
        let l = &self.layout;
        let mut v = l.tabs[i].to_vec();
        if l.wide[i / 2] {
            v.push(l.main[i + 1]);
            v.extend(l.tabs[i + 1]);
        }
        v
    }

    fn close_popup(&mut self) {
        if let Some((i, was)) = self.popup.take() {
            self.layout.main[i] = was;
        }
    }

    /// Portal `i` shows format `f` (a MENU pick, a window or tab tapped): where `f` already is (its half first, then
    /// the other) it takes `i`'s format in exchange, so each format stays in one place; a format shown nowhere
    /// replaces `i`'s. The portal's menu closes; an open pop-up ends first (its portal's format back), so the new
    /// format takes the place of the portal's own.
    pub fn show(&mut self, i: usize, f: &'static str) {
        self.close_popup();
        self.menu[i] = false;
        let l = &mut self.layout;
        let old = l.main[i];
        if old == f {
            return;
        }
        let half = first(i);
        let order = [half, half + 1, half ^ 2, (half ^ 2) + 1];
        'find: for k in order {
            if k != i && l.main[k] == f {
                l.main[k] = old;
                break;
            }
            if let Some(t) = l.tabs[k].iter_mut().find(|t| **t == f) {
                *t = old;
                break 'find;
            }
        }
        l.main[i] = f;
    }

    /// The MENU grid on portal `i` (its cursor on the format shown); again closes it.
    pub fn toggle_menu(&mut self, i: usize) {
        self.menu[i] = !self.menu[i];
        if self.menu[i] {
            self.focus = i;
            self.menu_cur = FORMATS.iter().position(|f| *f == self.layout.main[i]).unwrap_or(0);
        }
    }

    /// The MENU cursor `d` formats on (wrapping).
    pub fn menu_step(&mut self, d: i32) {
        let n = FORMATS.len() as i32;
        self.menu_cur = (self.menu_cur as i32 + d).rem_euclid(n) as usize;
    }

    /// Select on the focused portal: its open MENU takes the cursor's format; true when it did.
    pub fn select(&mut self) -> bool {
        let i = self.focus;
        if !self.menu[i] {
            return false;
        }
        self.show(i, FORMATS[self.menu_cur]);
        true
    }

    /// Portal `i` widened over its half (its format moves to the half's first portal), or back to two portals.
    pub fn widen(&mut self, i: usize) {
        self.close_popup();
        let h = i / 2;
        let a = first(i);
        let l = &mut self.layout;
        if l.wide[h] {
            l.wide[h] = false;
            l.big[a + 1] = l.big[a];
        } else {
            if i != a {
                l.main.swap(a, i);
                l.big[a] = l.big[i];
            }
            l.wide[h] = true;
        }
        self.focus = if self.shown(self.focus) { self.focus } else { a };
        self.menu = [false; 4];
    }

    /// Portal `i` enlarged over its windows, or back above them.
    pub fn enlarge(&mut self, i: usize) {
        self.close_popup();
        let k = if self.layout.wide[i / 2] { first(i) } else { i };
        self.layout.big[k] = !self.layout.big[k];
    }

    /// The function bar's SWAP: "will swap the left and right sides of the top bar. The status of the portals will
    /// not be changed" (the IndiaFoxtEcho manual p. 34, docs/real-mfd.md "F-35I").
    pub fn swap_bar(&mut self) {
        self.bar_swapped = !self.bar_swapped;
    }

    /// The MENU page's CRUS: "will restore the PCD configuration to the default" (the same manual): preset 1, the bar
    /// unswapped.
    pub fn restore(&mut self) {
        self.apply(0);
        self.bar_swapped = false;
    }

    /// Portal `i`'s next window (or tab) into it: its format and its windows' (a widened half's: also the hidden
    /// portal's) rotate one place, so each press brings the next one up.
    pub fn cycle(&mut self, i: usize) {
        self.close_popup();
        let l = &mut self.layout;
        let mut at: Vec<(usize, Option<usize>)> = vec![(i, None), (i, Some(0)), (i, Some(1))];
        if l.wide[i / 2] && i.is_multiple_of(2) {
            at.extend([(i + 1, None), (i + 1, Some(0)), (i + 1, Some(1))]);
        }
        let get = |l: &Layout, (k, t): (usize, Option<usize>)| t.map_or(l.main[k], |t| l.tabs[k][t]);
        let vals: Vec<&'static str> = at.iter().map(|p| get(l, *p)).collect();
        for (n, (k, t)) in at.iter().enumerate() {
            let v = vals[(n + 1) % vals.len()];
            match t {
                Some(t) => l.tabs[*k][*t] = v,
                None => l.main[*k] = v,
            }
        }
    }

    /// The cursor `d` shown portals on (wrapping), off the helmet.
    pub fn focus_step(&mut self, d: i32) {
        self.hud_soi = false;
        for _ in 0..4 {
            self.focus = (self.focus as i32 + d).rem_euclid(4) as usize;
            if self.shown(self.focus) {
                return;
            }
        }
    }

    /// DMS (ours: inferred for the F-35, its grip's switch named by the USAF): 0 up the helmet the sensor of
    /// interest, 1 down back to the display, 2 / 3 left / right the cursor to the next portal.
    pub fn dms(&mut self, dir: i32) {
        match dir {
            0 => self.hud_soi = true,
            1 => self.hud_soi = false,
            2 => self.focus_step(-1),
            _ => self.focus_step(1),
        }
    }

    /// A function bar item's pop-up: format `f` over portal `i` (the portal under the item), its format back when
    /// the item is tapped again or another pop-up opens.
    pub fn popup(&mut self, i: usize, f: &'static str) {
        let again = self.popup.is_some_and(|p| p.0 == i) && self.layout.main[i] == f;
        self.close_popup();
        if !again {
            self.popup = Some((i, self.layout.main[i]));
            self.layout.main[i] = f;
            self.menu[i] = false;
        }
    }

    /// The portal under x (0..1 across the glass), shown.
    pub fn portal_at(&self, x: f64) -> usize {
        let h = if x < 0.5 { 0 } else { 2 };
        if self.layout.wide[h / 2] || x - h as f64 * 0.25 < 0.25 { h } else { h + 1 }
    }

    /// The throttle's FLC ("Format Layer Control", switch T8 of the USAF's HOTAS list) turned `d` places: the cursor's
    /// portal steps through the MENU grid's formats (inferred: the switch's name only is public).
    pub fn flc_turn(&mut self, d: i32) {
        let i = self.focus;
        let n = FORMATS.len() as i32;
        let at = FORMATS.iter().position(|f| *f == self.layout.main[i]).unwrap_or(0) as i32;
        self.show(i, FORMATS[(at + d).rem_euclid(n) as usize]);
    }

    /// The FLC pushed: the cursor portal's TSD steps to its next layer setting (`layers`); false when the portal shows
    /// a format without layers (inferred, as `flc_turn`).
    pub fn flc_push(&mut self) -> bool {
        let Some(k) = ["TSD-1", "TSD-2", "TSD-3"].iter().position(|f| *f == self.layout.main[self.focus]) else {
            return false;
        };
        self.layers[k] = (self.layers[k] + 1) % 3;
        true
    }

    /// The sensor of interest's format, None on the helmet.
    pub fn soi(&self) -> Option<&'static str> {
        (!self.hud_soi).then(|| self.layout.main[self.focus])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn counts(p: &Pcd) -> (usize, usize) {
        (p.portals(0.26).iter().flatten().count(), p.windows(0.26).len())
    }

    #[test]
    fn presets_hold_known_formats_and_their_splits() {
        let mut p = Pcd::default();
        let want = [(3, 4), (4, 8), (2, 0), (3, 4), (4, 6)];
        for (n, w) in want.iter().enumerate() {
            p.apply(n);
            assert_eq!(counts(&p), *w, "preset {}", n + 1);
            let l = p.layout;
            assert!(l.main.iter().chain(l.tabs.iter().flatten()).all(|f| format(f).is_some()));
            // Every portal and window inside the glass, none overlapping another.
            let mut rs: Vec<Rect> = p.portals(0.26).iter().flatten().copied().collect();
            rs.extend(p.windows(0.26).iter().map(|w| w.0));
            for (a, r) in rs.iter().enumerate() {
                assert!(r.0 >= 0.0 && r.1 >= 0.0 && r.0 + r.2 <= 1.0 + 1e-9 && r.1 + r.3 <= 1.0 + 1e-9);
                for s in &rs[a + 1..] {
                    let ox = r.0 < s.0 + s.2 - 1e-9 && s.0 < r.0 + r.2 - 1e-9;
                    let oy = r.1 < s.1 + s.3 - 1e-9 && s.1 < r.1 + r.3 - 1e-9;
                    assert!(!(ox && oy), "preset {}: {r:?} overlaps {s:?}", n + 1);
                }
            }
        }
        assert_eq!(Pcd::default().layout, PRESETS[0]);
    }

    #[test]
    fn show_swaps_so_each_format_stays_in_one_place() {
        let mut p = Pcd::default();
        p.apply(1);
        p.show(0, "TWD"); // a window of the other half
        assert_eq!(p.layout.main[0], "TWD");
        assert_eq!(p.layout.tabs[2][0], "TSD-1");
        p.show(0, "SRCH"); // another portal's
        assert_eq!((p.layout.main[0], p.layout.main[2]), ("SRCH", "TWD"));
        p.show(1, "CNI"); // shown nowhere
        assert_eq!(p.layout.main[1], "CNI");
    }

    #[test]
    fn widen_enlarge_and_swap() {
        let mut p = Pcd::default();
        p.apply(1);
        p.widen(3);
        assert_eq!(p.layout.main[2], "TFLIR");
        assert!(!p.shown(3) && p.portals(0.26)[2] == Some((0.5, 0.0, 0.5, 0.74)));
        assert_eq!(p.windows(0.26).len(), 8, "a widened portal keeps the windows under it");
        p.enlarge(2);
        assert_eq!(p.portals(0.26)[2], Some((0.5, 0.0, 0.5, 1.0)));
        assert_eq!(p.tabs(2), vec!["TWD", "WPN-A", "SRCH", "EFI", "ICAWS"]);
        p.widen(2);
        assert!(p.shown(3) && p.enlarged(2) && p.enlarged(3));
        let before = p.layout;
        p.swap_bar();
        assert!(p.bar_swapped && p.layout == before, "SWAP trades the bar's halves only");
        p.popup(0, "MENU");
        p.restore();
        assert_eq!((p.layout, p.bar_swapped, p.popup), (PRESETS[0], false, None));
    }

    #[test]
    fn cycle_brings_each_window_up_in_turn() {
        let mut p = Pcd::default();
        p.apply(1);
        let seen: Vec<&str> = (0..3)
            .map(|_| {
                p.cycle(0);
                p.layout.main[0]
            })
            .collect();
        assert_eq!(seen, ["TSD-2", "WPN-S", "TSD-1"]);
        p.apply(0); // the wide half: six formats round
        for _ in 0..6 {
            p.cycle(0);
        }
        assert_eq!(p.layout, PRESETS[0]);
    }

    #[test]
    fn menu_cursor_select_and_popups() {
        let mut p = Pcd::default();
        p.toggle_menu(2);
        assert_eq!((p.focus, FORMATS[p.menu_cur]), (2, "SRCH"));
        p.menu_step(-1);
        assert!(p.select());
        assert_eq!(p.layout.main[2], "TSD-3");
        assert!(!p.select(), "no MENU open");
        p.popup(2, "CNI");
        assert_eq!(p.layout.main[2], "CNI");
        p.popup(2, "FUEL"); // another item: the first pop-up ends
        assert_eq!(p.popup, Some((2, "TSD-3")));
        p.popup(2, "FUEL");
        assert_eq!((p.layout.main[2], p.popup), ("TSD-3", None));
        assert_eq!(p.portal_at(0.1), 0);
        assert_eq!(p.portal_at(0.8), 3);
    }

    #[test]
    fn a_popup_never_takes_a_formats_place() {
        let all = |p: &Pcd| {
            let mut v: Vec<&str> = p.layout.main.iter().chain(p.layout.tabs.iter().flatten()).copied().collect();
            v.sort();
            v
        };
        let mut p = Pcd::default();
        let want = all(&p);
        p.popup(2, "FUEL");
        p.show(2, "TWD"); // a window tapped under the pop-up
        assert_eq!((all(&p), p.layout.main[2], p.popup), (want.clone(), "TWD", None));
        p.popup(2, "AP");
        p.toggle_menu(2);
        p.menu_cur = FORMATS.iter().position(|f| *f == "EFI").unwrap();
        assert!(p.select());
        assert_eq!(all(&p), want);
        p.popup(3, "CNI");
        p.widen(3);
        p.widen(2);
        assert_eq!((all(&p), p.popup), (want.clone(), None));
        p.popup(2, "FUEL");
        p.enlarge(2);
        assert_eq!((all(&p), p.popup), (want, None));
    }

    #[test]
    fn flc_turns_formats_and_steps_the_tsd_layers() {
        let mut p = Pcd { focus: 0, ..Default::default() };
        assert_eq!(p.layout.main[0], "TSD-1");
        assert!(p.flc_push());
        assert!(p.flc_push());
        assert_eq!(p.layers, [2, 0, 0]);
        assert!(p.flc_push());
        assert_eq!(p.layers[0], 0);
        p.flc_turn(1);
        assert_eq!(p.layout.main[0], "TSD-2");
        p.flc_turn(-2);
        assert_eq!(p.layout.main[0], "HUD", "wraps back past the grid's first");
        assert!(!p.flc_push(), "the HUD repeat has no layers");
        p.flc_turn(1);
        assert_eq!(p.layout.main[0], "TSD-1");
        let n = p.layout.main.iter().chain(p.layout.tabs.iter().flatten()).filter(|f| **f == "TSD-1").count();
        assert_eq!(n, 1, "the format turned to stays in one place");
    }

    #[test]
    fn dms_moves_the_cursor_over_shown_portals() {
        let mut p = Pcd::default(); // the left half widened: portals 0, 2, 3
        p.dms(3);
        assert_eq!(p.focus, 3);
        p.dms(3);
        assert_eq!(p.focus, 0);
        p.dms(2);
        assert_eq!(p.focus, 3);
        p.dms(0);
        assert_eq!(p.soi(), None);
        p.dms(1);
        assert_eq!(p.soi(), Some("TFLIR"));
    }
}
