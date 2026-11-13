//! `IafDevices`: Modern IAF's keys, joystick buttons and axes store (`iaf_tools::devices`, modern-iaf/docs/front-end.md
//! §8). Every function takes absolute paths: `table` the compiled key table, `store` the player's file, `map` the
//! joystick's device map ("" = none, `find_map`); the ones that change the store write it back at once.

use godot::prelude::*;
use iaf_tools::devices::{self, Column};
use serde_json::Value;

use crate::world::text;
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

fn defaults(table: &GString, map: &GString) -> Value {
    devices::with_map(&read(table), &read(map))
}

#[godot_api]
impl IafDevices {
    /// The device map in folder `dir` for the joystick named `name`, "" = none.
    #[func]
    fn find_map(dir: GString, name: GString) -> GString {
        let p = devices::find_map(Path::new(&dir.to_string()), &name.to_string());
        GString::from(p.map(|p| p.display().to_string()).unwrap_or_default().as_str())
    }

    /// The key table with the store's keys and buttons in it, as JSON text (the table `key_table.gd` reads in the
    /// sim); each record also has `default_key` and `default_joystick`.
    #[func]
    fn keys(table: GString, store: GString, map: GString) -> GString {
        text(&devices::merge_keys(&defaults(&table, &map), &read(&store)))
    }

    /// The record other than `record` bound to `value` in `column` ("key" / "button"), −1 = none.
    #[func]
    fn conflict(table: GString, store: GString, map: GString, record: i64, column: GString, value: i64) -> i64 {
        let Some(col) = Column::parse(&column.to_string()) else { return -1 };
        devices::conflict(&defaults(&table, &map), &read(&store), record as usize, col, value).map_or(-1, |j| j as i64)
    }

    /// Binds `record` to `value` in `column` ("key": DIK | modifiers << 16, 0 none; "button": 0-based, −1 none).
    #[func]
    fn bind(table: GString, store: GString, map: GString, record: i64, column: GString, value: i64) -> bool {
        let Some(col) = Column::parse(&column.to_string()) else { return false };
        let mut s = read(&store);
        devices::set(&defaults(&table, &map), &mut s, record as usize, col, value);
        write(&store, &s)
    }

    /// `record` back to its default in `column`; `record` −1: every record in that column.
    #[func]
    fn reset(store: GString, record: i64, column: GString) -> bool {
        let Some(col) = Column::parse(&column.to_string()) else { return false };
        let mut s = read(&store);
        devices::reset(&mut s, (record >= 0).then_some(record as usize), col);
        write(&store, &s)
    }

    /// Every button and axis back to the defaults.
    #[func]
    fn reset_joystick(store: GString) -> bool {
        let mut s = read(&store);
        devices::reset(&mut s, None, Column::Button);
        devices::reset_axes(&mut s);
        write(&store, &s)
    }

    /// The roles (roll, pitch, throttle, rudder, trim) with the store's axes, as JSON text: `{role: {axis, invert,
    /// dead}}`; `soft`: the Soft centre stick response.
    #[func]
    fn axes(store: GString, map: GString, soft: bool) -> GString {
        text(&devices::axes(&read(&store), &read(&map), soft))
    }

    /// Puts `role` on device axis `axis` (−1 none) with `invert` and dead zone `dead`; a role on that axis gives it up.
    #[func]
    fn set_axis(store: GString, map: GString, role: GString, axis: i64, invert: bool, dead: f64, soft: bool) -> bool {
        let mut s = read(&store);
        devices::set_axis(&mut s, &read(&map), &role.to_string(), axis, invert, dead, soft) && write(&store, &s)
    }
}
