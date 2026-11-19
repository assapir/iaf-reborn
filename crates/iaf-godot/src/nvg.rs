//! `IafGoggles`: the night-vision goggles of Modern IAF's F-16s (`iaf_avionics::nvg`), held by `cockpit.gd`
//! `goggles` and flipped by `terrain_view.gd` `_goggles_key`.

use godot::prelude::*;
use iaf_avionics::nvg::{FIELD_DEG, Goggles};

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafGoggles {
    g: Goggles,
}

#[godot_api]
impl IafGoggles {
    /// The goggles' key (`Goggles::flip`): true when they are now down.
    #[func]
    fn flip(&mut self) -> bool {
        self.g.flip()
    }

    /// Down before the eyes.
    #[func]
    fn down(&self) -> bool {
        self.g.down
    }

    /// The night-vision shader's `glare` with the lighting panel's NVIS / NORMAL switch at NVIS (`nvis`) or NORMAL
    /// (`Goggles::glare`).
    #[func]
    fn glare(&self, nvis: bool) -> f64 {
        self.g.glare(nvis)
    }

    /// Whether the tubes' field is drawn with the view the pilot's own eye or not (`Goggles::drawn`).
    #[func]
    fn drawn(&self, pilot_view: bool) -> bool {
        self.g.drawn(pilot_view)
    }

    /// The tubes' round field of view across, degrees (`FIELD_DEG`).
    #[func]
    fn field_deg(&self) -> f64 {
        FIELD_DEG
    }
}
