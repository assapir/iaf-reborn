//! `IafF16Mfd`: one F-16 MFD's real formats (`iaf_avionics::f16_mfd`, docs/mfd.md §9) for `shared/cockpit/mfd.gd`.

use godot::prelude::*;
use iaf_avionics::f16_mfd::{self, Format, Mfd, Press};

fn label(f: Option<Format>) -> GString {
    GString::from(f.map_or("", Format::label))
}

#[derive(GodotClass)]
#[class(no_init, base = RefCounted)]
pub struct IafF16Mfd {
    mfd: Mfd,
}

impl IafF16Mfd {
    fn menu_of(modern: bool) -> VarArray {
        f16_mfd::menu(modern).iter().map(|f| varray![i64::from(f.menu_osb()), f.label()].to_variant()).collect()
    }
}

#[godot_api]
impl IafF16Mfd {
    /// The MFD of `side` (0 left, 1 right) with its starting formats.
    #[func]
    fn create(side: i64) -> Gd<Self> {
        Gd::from_object(Self { mfd: Mfd::new(side.max(0) as usize) })
    }

    /// Modern IAF's (`Mfd::modern`: the formats per master mode, the formats of its own, the HSD's settings).
    #[func]
    fn create_modern(side: i64) -> Gd<Self> {
        Gd::from_object(Self { mfd: Mfd::modern(side.max(0) as usize) })
    }

    /// {slots: [3 labels, "" empty], primary, menu, declutter, shown, group, soi (the shown format can be the SOI)}.
    #[func]
    fn state(&self) -> VarDictionary {
        let slots: PackedStringArray = self.mfd.slots.iter().map(|&f| label(f)).collect();
        vdict! {
            "slots" => &slots,
            "primary" => self.mfd.primary as i64,
            "menu" => self.mfd.menu,
            "declutter" => self.mfd.declutter,
            "shown" => &label(self.mfd.shown()),
            "group" => self.mfd.group as i64,
            "soi" => !self.mfd.menu && self.mfd.shown().is_some_and(Format::soi),
        }
    }

    /// The master mode group (`f16_mfd::group` of the game's master mode and store type); true when it changed the
    /// shown format set.
    #[func]
    fn set_master(&mut self, master: i64, store_type: i64) -> bool {
        self.mfd.set_group(f16_mfd::group(master as i32, store_type))
    }

    /// MSMD RESET.
    #[func]
    fn reset_modes(&mut self) {
        self.mfd.reset_modes();
    }

    /// DCLT off (the RESET MENU's PROG DCLT RESET).
    #[func]
    fn clear_declutter(&mut self) {
        self.mfd.declutter = false;
    }

    /// DMS left / right on this MFD: the next format's label ("" none).
    #[func]
    fn step(&mut self) -> GString {
        label(self.mfd.step())
    }

    /// DMS up / down: the new SOI (-1 the HUD, 0 / 1 an MFD) from `soi` and whether each MFD may hold it.
    #[func]
    fn dms(soi: i64, down: bool, ok_left: bool, ok_right: bool) -> i64 {
        i64::from(f16_mfd::dms(soi as i32, down, [ok_left, ok_right]))
    }

    #[func]
    fn soi_valid(soi: i64, ok_left: bool, ok_right: bool) -> i64 {
        i64::from(f16_mfd::soi_valid(soi as i32, [ok_left, ok_right]))
    }

    /// The HSD: {own (px), r (px), nm, exp (1/2/4), exp_at, cursor, cursor_set, frozen (null or [x, y, heading]),
    /// cntl, show [5 bools], labels [[osb, text, hl]]} for its own range `scale_nm` and the FCR's `fcr_nm`.
    #[func]
    fn hsd(&self, scale_nm: f64, fcr_nm: f64) -> VarDictionary {
        let h = &self.mfd.hsd;
        let (own, r, nm) = h.view(scale_nm, fcr_nm);
        let v2 = |p: (f64, f64)| Vector2::new(p.0 as f32, p.1 as f32);
        let labels: VarArray = h.labels().iter().map(|(o, t, hl)| varray![*o, t.as_str(), *hl].to_variant()).collect();
        let show: VarArray = h.show.iter().map(|b| b.to_variant()).collect();
        let frozen =
            h.frozen.map_or(Variant::nil(), |f| Vector3::new(f[0] as f32, f[1] as f32, f[2] as f32).to_variant());
        vdict! {
            "own" => v2(own), "r" => r, "nm" => nm, "exp" => h.exp_k(), "exp_at" => v2(h.exp_at),
            "cursor" => v2(h.cursor_px()), "cursor_set" => h.cursor.is_some(), "frozen" => &frozen, "cntl" => h.cntl,
            "show" => &show, "labels" => &labels,
        }
    }

    /// An HSD OSB (`Hsd::press`; `own` the ownship's world x, y and heading): true when the HSD took it.
    #[func]
    fn hsd_press(&mut self, osb: i64, own: Vector3) -> bool {
        self.mfd.hsd.press(osb as i32, [f64::from(own.x), f64::from(own.y), f64::from(own.z)])
    }

    #[func]
    fn hsd_slew(&mut self, dx: f64, dy: f64) {
        self.mfd.hsd.slew(dx, dy);
    }

    /// TMS up on the HSD: the index of the point under the cursor among `pts` (MFD px), -1 none.
    #[func]
    fn hsd_pick(&self, pts: PackedVector2Array) -> i64 {
        let v: Vec<(f64, f64)> = pts.as_slice().iter().map(|p| (f64::from(p.x), f64::from(p.y))).collect();
        self.mfd.hsd.pick(&v).map_or(-1, |i| i as i64)
    }

    /// The SMS A-G submodes for the selected bomb (`ag_submodes`).
    #[func]
    fn ag_submodes(gps: bool) -> PackedStringArray {
        f16_mfd::ag_submodes(gps).iter().map(|s| GString::from(*s)).collect()
    }

    #[func]
    fn flcs_bit(started: f64, now: f64, fault: bool) -> GString {
        GString::from(f16_mfd::flcs_bit((started >= 0.0).then_some(started), now, fault))
    }

    #[func]
    fn tgp_track(aim: i64, slaved: bool) -> GString {
        GString::from(f16_mfd::tgp_track(aim, slaved))
    }

    /// Follows the page the MFD shows (`Mfd::follow`).
    #[func]
    fn follow(&mut self, page: i64) {
        self.mfd.follow(page as i32);
    }

    /// A press of the game's button `id` (`Mfd::press` on its real number): {kind: "none" | "format" | "menu" |
    /// "swap" | "declutter" | "own", format (label), osb (the real number)}.
    #[func]
    fn press(&mut self, id: i64) -> VarDictionary {
        let osb = f16_mfd::real_osb(id as i32);
        let (kind, f) = match self.mfd.press(osb) {
            Press::None => ("none", None),
            Press::Format(f) => ("format", Some(f)),
            Press::Menu => ("menu", None),
            Press::Swap => ("swap", None),
            Press::Declutter => ("declutter", None),
            Press::Own(_) => ("own", None),
        };
        vdict! { "kind" => kind, "format" => &label(f), "osb" => osb as i64 }
    }

    /// The game page of the format `name` (WPN: the HARM page with `harm`); -1 unknown.
    #[func]
    fn page_of(name: GString, harm: bool) -> i64 {
        Format::from_label(&name.to_string()).map_or(-1, |f| i64::from(f.page(harm)))
    }

    /// The format a game page stands for ("" none: the menu or a page not offered).
    #[func]
    fn format_of(page: i64) -> GString {
        label(Format::of_page(page as i32))
    }

    #[func]
    fn offered(page: i64) -> bool {
        f16_mfd::offered(page as i32)
    }

    #[func]
    fn stand_in() -> i64 {
        i64::from(f16_mfd::STAND_IN)
    }

    /// The format menu: [[osb, label]] (`Format::menu_osb`).
    #[func]
    fn menu() -> VarArray {
        Self::menu_of(false)
    }

    /// The modern MFDs' format menu, with the formats of its own.
    #[func]
    fn menu_modern() -> VarArray {
        Self::menu_of(true)
    }

    /// [OSB 1, OSB 2] mnemonics of the radar mode (`fcr_mode`).
    #[func]
    fn fcr_mode(mode: i64) -> PackedStringArray {
        let (a, b) = f16_mfd::fcr_mode(mode as i32);
        [a, b].iter().map(|s| GString::from(*s)).collect()
    }

    /// The real FCR's OSB 2 (`fcr_real_submode`).
    #[func]
    fn fcr_real_submode(mode: i64, vsr: bool, acm: i64) -> GString {
        GString::from(f16_mfd::fcr_real_submode(mode as i32, vsr, acm))
    }

    #[func]
    fn fcr_azimuth(width: f64) -> GString {
        GString::from(f16_mfd::fcr_azimuth(width))
    }

    #[func]
    fn hsd_step(scale: i64, up: bool) -> i64 {
        i64::from(f16_mfd::hsd_step(scale as i32, up))
    }

    #[func]
    fn hsd_range_nm(scale: i64) -> i64 {
        i64::from(f16_mfd::hsd_range_nm(scale as i32))
    }

    #[func]
    fn wrap_presses(value: i64, lo: i64, hi: i64, step: i64) -> i64 {
        i64::from(f16_mfd::wrap_presses(value as i32, lo as i32, hi as i32, step as i32))
    }

    /// Swaps the formats with `other` (SWAP, OSB 15): the whole MFD on the 1998 game's, the current master mode's
    /// formats and the HSD's settings on the modern ones.
    #[func]
    fn swap_with(&mut self, mut other: Gd<IafF16Mfd>) {
        if self.mfd.modern {
            self.mfd.swap(&mut other.bind_mut().mfd);
        } else {
            std::mem::swap(&mut self.mfd, &mut other.bind_mut().mfd);
        }
    }
}
