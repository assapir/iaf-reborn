//! The night-vision goggles of Modern IAF's F-16s (modern-iaf/docs/research/nvg.md, its options O1–O4 as the user
//! picked them on 19 November 2026; docs/rendering.md §8): the goggles on the helmet, flipped down before the eyes or
//! up by one key, at any height; the lighting panel's NVIS / NORMAL switch decides whether the cockpit's own light
//! glares in the tubes. While they are down the helmet display shows no symbols (`real_hud::Input::goggles_down`).
//! Down, the tubes' picture is a round field on the head's forward line, seen only from the pilot's own eye; the pilot
//! looks under it at the panel with the naked eye (the user's "fix", 19 November 2026).

/// The cockpit's own light in the tubes from lighting the goggles do not suit: the night-vision shader's `glare`
/// (docs/rendering.md §8.3).
pub const GLARE: f64 = 0.15;

/// The goggles' round field of view across, degrees: the AN/AVS-9 class (F4949) the jets' lighting was built for
/// (research §2.1, §4).
pub const FIELD_DEG: f64 = 40.0;

/// The goggles on the helmet. A flight starts with them up: the pilot takes off unaided (research §3, the US
/// practice).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Goggles {
    pub down: bool,
}

impl Goggles {
    /// The goggles' key: down when up, up when down, at any height (no minimum height: the user's pick). True when
    /// they are now down.
    pub fn flip(&mut self) -> bool {
        self.down = !self.down;
        self.down
    }

    /// The cockpit's glare in the tubes: none with the NVIS / NORMAL switch at NVIS (the goggle-compatible lighting,
    /// research §3), `GLARE` at NORMAL; none while the goggles are up.
    pub fn glare(self, nvis: bool) -> f64 {
        if self.down && !nvis { GLARE } else { 0.0 }
    }

    /// Whether the tubes' field is drawn: down, and the view is the pilot's own eye (the cockpit, free look, padlock,
    /// HUD only). An outside view has no head to fix the field to, so it shows the naked-eye night.
    pub fn drawn(self, pilot_view: bool) -> bool {
        self.down && pilot_view
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_key_flips_them_and_nvis_keeps_the_glare_out() {
        let mut g = Goggles::default();
        assert!(!g.down, "a flight starts with them up");
        assert_eq!(g.glare(false), 0.0, "up: no picture, no glare");
        assert!(g.flip() && g.down);
        assert_eq!((g.glare(true), g.glare(false)), (0.0, GLARE), "down: NVIS none, NORMAL the glare");
        assert!(!g.flip() && !g.down, "the same key flips them up");
        assert!(!g.drawn(true), "up: no field");
        g.flip();
        assert!(g.drawn(true) && !g.drawn(false), "down: the field in the pilot's own view only");
    }
}
