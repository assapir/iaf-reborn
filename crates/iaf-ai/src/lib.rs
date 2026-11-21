//! Modern IAF's AI (modern-iaf/docs/ai-plan.md): behaviour trees per role and the flight lead over the autopilot's
//! loops (`iaf_flight::autopilot`), which fly every AI jet on the same flight model as the player's. The 1998 game
//! keeps its own brain (`shared/ai/brain.gd`). The air-defence sites (`site`) and their network (`net`): docs/ai.md
//! §15; the one-way attack drones (`drone`): §16.

pub mod bt;
pub mod drone;
pub mod flight;
pub mod net;
pub mod site;
pub mod wingman;

pub use flight::{Call, Decoy, Flight, Member, Order, SHAPES, Skill, Threat, apply};
