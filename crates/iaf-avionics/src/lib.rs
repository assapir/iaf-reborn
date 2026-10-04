//! The player's avionics of Jane's IAF (1998) — radar, gun, weapon sights, HUD values — re-implemented from the
//! reverse-engineered notes in `docs/`. Pure Rust, no engine dependencies; `iaf-godot` exposes it to GDScript.

pub mod guided;
pub mod gun;
pub mod missile;
pub mod radar;
pub mod sight;
pub mod vec3;

pub use vec3::Vec3;
