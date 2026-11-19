//! Modern IAF's AI (modern-iaf/docs/ai-plan.md): behaviour trees per role and the flight lead over the autopilot's
//! loops (`iaf_flight::autopilot`), which fly every AI jet on the same flight model as the player's. The 1998 game
//! keeps its own brain (`shared/ai/brain.gd`).

pub mod bt;
pub mod flight;
pub mod wingman;

pub use flight::{Call, Flight, Member, Order, SHAPES, Skill, apply};
