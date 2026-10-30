//! `IafF16Mfd`: one F-16 MFD's real formats (`iaf_avionics::f16_mfd`, docs/mfd.md §9) for `game/cockpit/mfd.gd`.

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

#[godot_api]
impl IafF16Mfd {
    /// The MFD of `side` (0 left, 1 right) with its starting formats.
    #[func]
    fn create(side: i64) -> Gd<Self> {
        Gd::from_object(Self { mfd: Mfd::new(side.max(0) as usize) })
    }

    /// {slots: [3 labels, "" empty], primary, menu, declutter, shown}.
    #[func]
    fn state(&self) -> VarDictionary {
        let slots: PackedStringArray = self.mfd.slots.iter().map(|&f| label(f)).collect();
        vdict! {
            "slots" => &slots,
            "primary" => self.mfd.primary as i64,
            "menu" => self.mfd.menu,
            "declutter" => self.mfd.declutter,
            "shown" => &label(self.mfd.shown()),
        }
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
        Format::ALL.iter().map(|f| varray![i64::from(f.menu_osb()), f.label()].to_variant()).collect()
    }

    /// [OSB 1, OSB 2] mnemonics of the radar mode (`fcr_mode`).
    #[func]
    fn fcr_mode(mode: i64) -> PackedStringArray {
        let (a, b) = f16_mfd::fcr_mode(mode as i32);
        [a, b].iter().map(|s| GString::from(*s)).collect()
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

    /// Swaps the formats with `other` (SWAP, OSB 15).
    #[func]
    fn swap_with(&mut self, mut other: Gd<IafF16Mfd>) {
        std::mem::swap(&mut self.mfd, &mut other.bind_mut().mfd);
    }
}
