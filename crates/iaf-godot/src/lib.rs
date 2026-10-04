//! Godot extension entry point for iaf-reborn.

use godot::prelude::*;

mod bombs;
mod flight;
mod gun;
mod missile;
mod radar;
mod rwr;
mod sight;
mod stores;
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
