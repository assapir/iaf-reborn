//! Godot extension entry point for iaf-reborn.

use godot::prelude::*;

mod autorun;
mod bases;
mod bombs;
mod fctrl;
mod flight;
mod gun;
mod heights;
mod imode;
mod mcr;
mod missile;
mod mission_edit;
mod radar;
mod real_hud;
mod release;
mod rwr;
mod sensors;
mod setup;
mod sight;
mod stores;
mod surface;
mod world;

struct IafExtension;

#[gdextension]
unsafe impl ExtensionLibrary for IafExtension {}

/// Small smoke-test class: `IafInfo.new().version()` from GDScript.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct IafInfo {}

#[godot_api]
impl IafInfo {
    #[func]
    fn version(&self) -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }
}
