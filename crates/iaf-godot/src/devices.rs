//! `IafDevices`: Modern IAF's joystick axes store (`iaf_tools::devices`, modern-iaf/docs/front-end.md §9). Every
//! function takes absolute paths: `store` the player's file, `map` the joystick's device map ("" = none, `find_map`);
//! the ones that change the store write it back at once. The keys and buttons are `Settings.key_bindings`.

use godot::prelude::*;
use iaf_tools::devices;
use serde_json::Value;

use crate::world::{get, num, text};
use std::path::Path;

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafDevices {}

fn read(path: &GString) -> Value {
    devices::load(Path::new(&path.to_string()))
}

fn write(path: &GString, store: &Value) -> bool {
    match devices::save(Path::new(&path.to_string()), store) {
        Ok(()) => true,
        Err(e) => {
            godot_error!("devices store: {e:#}");
            false
        }
    }
}

#[godot_api]
impl IafDevices {
    /// The device map in folder `dir` for the joystick named `name`, "" = none.
    #[func]
    fn find_map(dir: GString, name: GString) -> GString {
        let p = devices::find_map(Path::new(&dir.to_string()), &name.to_string());
        GString::from(p.map(|p| p.display().to_string()).unwrap_or_default().as_str())
    }

    /// Drops the keys and buttons a store from before 2026-11-14 held, once the sim has them in
    /// `Settings.key_bindings`.
    #[func]
    fn drop_bindings(store: GString) -> bool {
        let mut s = read(&store);
        !devices::drop_bindings(&mut s) || write(&store, &s)
    }

    /// Every axis back to the defaults.
    #[func]
    fn reset_axes(store: GString) -> bool {
        let mut s = read(&store);
        devices::reset_axes(&mut s);
        write(&store, &s)
    }

    /// The roles (roll, pitch, throttle, rudder, trim) with the store's axes, as JSON text: `{role: {axis, invert,
    /// dead}}`; `soft`: the Soft centre stick response.
    #[func]
    fn axes(store: GString, map: GString, soft: bool) -> GString {
        text(&devices::axes(&read(&store), &read(&map), soft))
    }

    /// Puts `role` on `choice`: `{axis (−1 none), invert, dead, device (its name), main (the main joystick's name)}`;
    /// a role on that axis of that device gives it up (`devices::set_axis`).
    #[func]
    fn set_axis(store: GString, map: GString, role: GString, choice: VarDictionary, soft: bool) -> bool {
        let text = |k: &str| get::<GString>(&choice, k).unwrap_or_default().to_string();
        let (device, main) = (text("device"), text("main"));
        let c = devices::Choice {
            device: &device,
            main: &main,
            axis: num(&choice, "axis").map_or(-1, |a| a as i64),
            invert: get::<bool>(&choice, "invert").unwrap_or(false),
            dead: num(&choice, "dead").unwrap_or(0.0),
        };
        let mut s = read(&store);
        devices::set_axis(&mut s, &read(&map), &role.to_string(), &c, soft) && write(&store, &s)
    }
}
