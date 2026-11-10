//! `IafCockpitSound`: Modern IAF's cockpit sound model (`iaf_flight::cockpit_sound`, modern-iaf/docs/sound.md §1.9) for
//! `shared/audio/sound_buses.gd`.

use godot::prelude::*;
use iaf_flight::cockpit_sound::{self, Class};

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct IafCockpitSound {}

#[godot_api]
impl IafCockpitSound {
    /// The class of a sound table row: "inside", "engine", "airframe", "weapons" or "world".
    #[func]
    fn class_of(code: GString, sub: GString) -> GString {
        cockpit_sound::class_of(&code.to_string(), &sub.to_string()).name().into()
    }

    /// The class's level in the cockpit, dB (0 for an unknown name).
    #[func]
    fn gain_db(class: GString) -> f64 {
        Class::from_name(&class.to_string()).map_or(0.0, cockpit_sound::gain_db)
    }

    /// The cutoff of the 12 dB per octave low-pass (resonance 0.5) an outside class goes through, Hz.
    #[func]
    fn lowpass_hz(class: GString) -> f64 {
        cockpit_sound::lowpass_hz(Class::from_name(&class.to_string()).unwrap_or(Class::World))
    }
}
