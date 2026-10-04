//! The player's avionics of Jane's IAF (1998) — radar, gun, weapon sights, HUD values — re-implemented from the
//! reverse-engineered notes in `docs/`. Pure Rust, no engine dependencies; `iaf-godot` exposes it to GDScript.

pub mod bombs;
pub mod eo;
pub mod guided;
pub mod gun;
pub mod harm;
pub mod hud;
pub mod master;
pub mod missile;
pub mod radar;
pub mod real_hud;
pub mod release;
pub mod rwr;
pub mod sight;
pub mod stores;

pub use iaf_flight::vec3::{self, Vec3};
