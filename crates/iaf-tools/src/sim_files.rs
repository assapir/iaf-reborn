//! Where `iaf-sim db` writes the IAF 2026 object database (iaf-2026/docs/data-formats.md), in a file of its own so the
//! original game's converters (aircraft.rs, scenery.rs), which only skip these names, do not reach the sim compiler.

/// The compiled object database's name: missions name it in `bdb`, the object index keys its models by it and
/// `weapon_db.gd` finds that key through the bdb's `_file`.
pub const BDB: &str = "sim.bdb";
/// Under the assets root.
pub const BDB_FILE: &str = "converted/missions/sim.bdb.json";
