//! Modern IAF's AI (modern-iaf/docs/ai-plan.md): behaviour trees per role and the flight lead over the autopilot's
//! loops (`iaf_flight::autopilot`), which fly every AI jet on the same flight model as the player's. The 1998 game
//! keeps its own brain (`shared/ai/brain.gd`). The air-defence sites (`site`) and their network (`net`): docs/ai.md
//! §15; the one-way attack drones (`drone`): §16; a unit's skill (`skill`): §17; the enemy fighters (`fighter`, the
//! network's vector `net::Gci`): §18; the air-to-ground attack (`strike`): §8.10; the sort of the bandits between the
//! jets (`sort`): §8.11; the moving ground vehicles (`convoy`): §19; the target drones of the range and the lessons
//! (`target`): §21; Scramble's rules (`free_combat`): §23.

pub mod bfm;
pub mod bt;
pub mod convoy;
pub mod drone;
pub mod fighter;
pub mod flight;
pub mod free_combat;
pub mod net;
pub mod site;
pub mod skill;
pub mod sort;
pub mod strike;
pub mod target;
pub mod wingman;

pub use fighter::Bogey;
pub use flight::{Bandit, CLOSE_STEPS, Call, Decoy, Flight, Member, Order, SHAPES, Tactic, Threat, apply};
pub use skill::Skill;
