//! Godot extension entry point for iaf-reborn.

use godot::prelude::*;

mod autorun;
mod bases;
mod bombs;
mod city_lights;
mod emf;
mod fctrl;
mod flight;
mod gun;
mod heights;
mod hid;
mod imode;
mod mcr;
mod missile;
mod mission_edit;
mod mission_intel;
mod radar;
mod real_hud;
mod release;
mod roads;
mod rwr;
mod scenery;
mod sensors;
mod setup;
mod sight;
mod stores;
mod surface;
mod world;

struct IafExtension;

#[gdextension]
unsafe impl ExtensionLibrary for IafExtension {
    fn on_stage_init(stage: InitStage) {
        if stage == InitStage::Scene {
            // After godot-rust's own hook (the message and its file:line): the stack into the game log too, so a
            // player's log shows where a Rust panic came from (the release build keeps the function names).
            let prev = std::panic::take_hook();
            std::panic::set_hook(Box::new(move |info| {
                prev(info);
                // Godot's own frames have no symbols here ("<unknown>"): left out.
                let bt = std::backtrace::Backtrace::force_capture().to_string();
                let frames: Vec<&str> = bt.lines().filter(|l| !l.ends_with("<unknown>")).collect();
                godot_error!("[panic backtrace]\n{}", frames.join("\n"));
            }));
        }
    }
}

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

    /// The git commit the extension was built from ("" unknown; build.rs).
    #[func]
    fn commit(&self) -> GString {
        GString::from(env!("IAF_GIT_COMMIT"))
    }
}
