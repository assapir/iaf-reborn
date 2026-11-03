# IAF 2026: status

What works and what is open, by work item ([plan.md](plan.md)). Newest first.

## Works
- **B1, the terrain (2026-11-03):** `iaf-sim terrain` builds the sim's theatre `converted/terrain/israel/` from open
  data (GLO-30, Sentinel-2, the Survey of Israel), UTM 36N at 1:1 ([terrain.md](terrain.md)); the sim streams it
  (`theatre_dir()`); the M0 probe flies 5 s over it and checks the heights.
- **C2 stage (b), engines, gear, the jets' data (2026-11-03):** TP-1538's engine model scaled to the F110-GE-100,
  F100-PW-229 and F135; a three-strut gear with brakes, steering and a braked stand; the four jets' mass, inertia and
  geometry; tests against the ratings, the spool times, a take-off roll and a stop ([flight-model.md](flight-model.md)
  §9.7–9.10). The take-off roll is 26 % short of the F-16A's SAC figure (open).
- **C2 stage (a), the 6-DoF's core (2026-11-03):** `crates/iaf-flight/src/sixdof/`: NASA TP-1538's aerodynamic
  tables checked value by value against the scan, appendix B's coefficient build-up, a quaternion rigid body; the
  trim tests match the report's trims and Stevens & Lewis's ([flight-model.md](flight-model.md) §9). Nothing calls
  it yet.
- **D2 drafts (2026-11-03), pending the user's decision:** the threat set's 12 units and 10 weapons as readable
  records in `iaf-2026/data/db/drafts/`, every figure sourced; `iaf-sim db` skips them, and a test compiles them as if
  approved ([threat-records.md](threat-records.md)).
- **A1, the project (2026-11-02):** the `iaf-2026/` Godot project with its `shared` link, `sim_settings.gd`, the
  `install_dir()` / `own_dir()` / `keys_file()` calls in the shared code (the original game reads the same files as
  before), the launchers `./iaf2026` and `./iaf2026-setup` (+ `.ps1`), `tools/test.sh` over `iaf-2026/tests` and
  gdparse on both projects, the M0 probe.
- **Own sources for the flight-model type and the bases (2026-11-03):** the player's jet takes its flight-model type
  from the sim's table (`Settings.fm_section`), not the converted descriptor; `IafBases` reads `own_dir()`'s
  `iaf.ibx`, not the install's ([README.md](README.md) "How the sim reads its data"). `test_own_sources.gd`.
- **The M0 probe (2026-11-02):** passes the no-install check, the profile, the key and sound tables, and for each jet
  the mission's object database, the aircraft definition, the motion table, the 3D cockpit model and the flight
  model's start from the own `bd.ibx` (item C1's FM-0 data; `NEEDS DATA` without that file). With the terrain built
  (B1) it flies 5 s over it and checks the heights; the 3D-only cockpit check waits for E1.
- A2 (the data compilers), B2a (the airbases' layouts), E1b (sounds, voices, keys), E3a (the training scoring): see
  their rows in [plan.md](plan.md).

## Open
- **The 6-DoF flies nothing yet (C2 stage (c)):** the `IafFlight` switch (`Model=6dof`), the flight control system,
  fuel burn, Mach effects, the validation rows and the bench ([flight-model.md](flight-model.md) §9.6).
- **No screen yet:** `./iaf2026` runs the M0 probe until the front end (item E2, its main scene `main.tscn`); the sim's
  `Settings` still has the original's `front_end_scene()` / `front_end_overlay()` (E2 overrides them).
- **No wizard yet:** `./iaf2026-setup` runs `iaf-sim all` from the command line until item A3.
- **The probe's 3D-only cockpit check** (no 2D panel in flight) prints NEEDS DATA until E1.
- **No own `iaf.ibx` and `terraintype.dat` yet (B2b):** the base move, the tower's wind turn and the radio's bases
  read `own_dir()`'s `iaf.ibx`, so the sim has no bases until B2b writes one; the terrain's `terraintype.dat` too.
  The temp-root run of item F finds any read of the original's data still left.
