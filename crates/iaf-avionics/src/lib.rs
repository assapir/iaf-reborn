//! The player's avionics of Jane's IAF (1998) — radar, gun, weapon sights, HUD values — re-implemented from the
//! reverse-engineered notes in `docs/`. Pure Rust, no engine dependencies; `iaf-godot` exposes it to GDScript.

pub mod gun;
pub mod radar;
pub mod vec3;

pub use vec3::Vec3;
