//! `IafPcd`: the F-35I's panoramic display layout (`iaf_avionics::pcd`, docs/f35i.md §4.3) for `shared/cockpit/pcd.gd`.

use godot::prelude::*;
use iaf_avionics::pcd::{self, Pcd, Rect};

fn rect(r: Rect) -> Rect2 {
    Rect2::new(Vector2::new(r.0 as f32, r.1 as f32), Vector2::new(r.2 as f32, r.3 as f32))
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafPcd {
    pcd: Pcd,
}

#[godot_api]
impl IafPcd {
    /// The MENU grid's formats.
    #[func]
    fn formats() -> PackedStringArray {
        pcd::FORMATS.iter().map(|f| GString::from(*f)).collect()
    }

    /// {main [4], tabs [4 × 2], wide [2], big [4], menu [4], menu_cur, focus, hud_soi, popup (portal, -1 none),
    /// preset, bar_swapped, portals [4 Rect2, an empty one hidden], windows [[Rect2, portal, window]], tab_rows [4 × the enlarged
    /// portals' tabs]} with the windows' row `win` tall (of the glass under the function bar).
    #[func]
    fn state(&self, win: f64) -> VarDictionary {
        let p = &self.pcd;
        let l = &p.layout;
        let strs = |v: &[&str]| -> PackedStringArray { v.iter().map(|f| GString::from(*f)).collect() };
        let tabs: VarArray = l.tabs.iter().map(|t| strs(t).to_variant()).collect();
        let tab_rows: VarArray = (0..4).map(|i| strs(&p.tabs(i)).to_variant()).collect();
        let portals: VarArray = p.portals(win).iter().map(|r| r.map_or(Rect2::default(), rect).to_variant()).collect();
        let windows: VarArray =
            p.windows(win).iter().map(|(r, i, t)| varray![rect(*r), *i as i64, *t as i64].to_variant()).collect();
        let b = |v: &[bool]| -> VarArray { v.iter().map(|x| x.to_variant()).collect() };
        vdict! {
            "main" => &strs(&l.main), "tabs" => &tabs, "wide" => &b(&l.wide), "big" => &b(&l.big),
            "menu" => &b(&p.menu), "menu_cur" => p.menu_cur as i64, "focus" => p.focus as i64, "hud_soi" => p.hud_soi,
            "popup" => p.popup.map_or(-1, |q| q.0 as i64), "preset" => p.preset as i64,
            "bar_swapped" => p.bar_swapped, "portals" => &portals,
            "windows" => &windows, "tab_rows" => &tab_rows,
        }
    }

    #[func]
    fn apply(&mut self, n: i64) {
        self.pcd.apply(n.max(0) as usize);
    }

    /// Portal `i` shows format `f` (a known one).
    #[func]
    fn show(&mut self, i: i64, f: GString) {
        if let Some(f) = pcd::format(&f.to_string()) {
            self.pcd.show(i.clamp(0, 3) as usize, f);
        }
    }

    #[func]
    fn toggle_menu(&mut self, i: i64) {
        self.pcd.toggle_menu(i.clamp(0, 3) as usize);
    }

    #[func]
    fn menu_step(&mut self, d: i64) {
        self.pcd.menu_step(d as i32);
    }

    /// Select on the focused portal: its MENU's pick; true when one was open.
    #[func]
    fn select(&mut self) -> bool {
        self.pcd.select()
    }

    #[func]
    fn widen(&mut self, i: i64) {
        self.pcd.widen(i.clamp(0, 3) as usize);
    }

    #[func]
    fn enlarge(&mut self, i: i64) {
        self.pcd.enlarge(i.clamp(0, 3) as usize);
    }

    /// The function bar's SWAP: its halves trade places.
    #[func]
    fn swap_bar(&mut self) {
        self.pcd.swap_bar();
    }

    /// CRUS: the default layout, the bar unswapped.
    #[func]
    fn restore(&mut self) {
        self.pcd.restore();
    }

    #[func]
    fn cycle(&mut self, i: i64) {
        self.pcd.cycle(i.clamp(0, 3) as usize);
    }

    #[func]
    fn set_focus(&mut self, i: i64) {
        if self.pcd.shown(i.clamp(0, 3) as usize) {
            self.pcd.focus = i.clamp(0, 3) as usize;
            self.pcd.hud_soi = false;
        }
    }

    /// DMS: 0 up, 1 down, 2 left, 3 right.
    #[func]
    fn dms(&mut self, dir: i64) {
        self.pcd.dms(dir as i32);
    }

    /// A function bar item's pop-up `f` over the portal under `x` (0..1 across the glass).
    #[func]
    fn popup(&mut self, x: f64, f: GString) {
        if let Some(f) = pcd::format(&f.to_string()) {
            let i = self.pcd.portal_at(x);
            self.pcd.popup(i, f);
        }
    }

    /// The sensor of interest's format, "" the helmet.
    #[func]
    fn soi(&self) -> GString {
        GString::from(self.pcd.soi().unwrap_or(""))
    }
}
