//! Godot extension entry point for linux-iaf.

use godot::prelude::*;

mod flight;

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
