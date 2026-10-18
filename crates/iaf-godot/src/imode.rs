//! `IafImode`: I-mode (`iaf_avionics::imode`, docs/cockpit.md "I-mode") for `terrain_view.gd` and `hud.gd`. Positions
//! and axes are Godot's (any one frame works: only dot products are taken).

use crate::world::{get, num};
use godot::prelude::*;
use iaf_avionics::imode::{self, Aircraft, Camera, Entry};
use iaf_avionics::Vec3;

fn v(p: Vector3) -> Vec3 {
    Vec3::new(p.x.into(), p.y.into(), p.z.into())
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct IafImode {}

#[godot_api]
impl IafImode {
    /// The gather (`FUN_0045c530`): `aircraft` [{pos, radius, friend}], `cam` {eye, right, up, forward, focal} (focal in
    /// original pixels), the 3D view's height in original rows. Returns [{x, y, friend, dist, off_axis}].
    #[func]
    fn scan(own: Vector3, aircraft: VarArray, cam: VarDictionary, view_h: i64) -> VarArray {
        let list = aircraft.iter_shared().filter_map(|a| a.try_to::<VarDictionary>().ok()).map(|d| Aircraft {
            pos: v(get(&d, "pos").unwrap_or_default()),
            radius: num(&d, "radius").unwrap_or_default(),
            friend: get(&d, "friend").unwrap_or(false),
        });
        let c = Camera {
            eye: v(get(&cam, "eye").unwrap_or_default()),
            right: v(get(&cam, "right").unwrap_or_default()),
            up: v(get(&cam, "up").unwrap_or_default()),
            forward: v(get(&cam, "forward").unwrap_or_default()),
            focal: num(&cam, "focal").unwrap_or_default(),
        };
        imode::scan(v(own), list, &c, view_h as i32)
            .iter()
            .map(|e| vdict! { "x" => e.x, "y" => e.y, "friend" => e.friend, "dist" => e.dist, "off_axis" => e.off_axis }.to_variant())
            .collect()
    }

    /// The drawing (`FUN_0052fcc0`) of `entries` (from `scan`) in a 3D view `view_h` rows high: [{at, to (Vector2i,
    /// original pixels), friend}].
    #[func]
    fn marks(entries: VarArray, view_h: i64) -> VarArray {
        let list: Vec<Entry> = entries
            .iter_shared()
            .filter_map(|e| e.try_to::<VarDictionary>().ok())
            .map(|d| Entry {
                x: num(&d, "x").unwrap_or_default() as i32,
                y: num(&d, "y").unwrap_or_default() as i32,
                friend: get(&d, "friend").unwrap_or(false),
                dist: num(&d, "dist").unwrap_or_default(),
                off_axis: num(&d, "off_axis").unwrap_or_default(),
            })
            .collect();
        imode::marks(&list, view_h as i32)
            .iter()
            .map(|m| {
                let at = Vector2i::new(m.at.0, m.at.1);
                let to = Vector2i::new(m.to.0, m.to.1);
                vdict! { "at" => at, "to" => to, "friend" => m.friend }.to_variant()
            })
            .collect()
    }
}
