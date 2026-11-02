# IAF 2026: status

What works and what is open, by work item ([plan.md](plan.md)). Newest first.

## Works
- **A1, the project (2026-11-02):** the `iaf-2026/` Godot project with its `shared` link, `sim_settings.gd`, the
  `install_dir()` / `own_dir()` / `keys_file()` calls in the shared code (the original game reads the same files as
  before), the launchers `./iaf2026` and `./iaf2026-setup` (+ `.ps1`), `tools/test.sh` over `iaf-2026/tests` and
  gdparse on both projects, the M0 probe.
- **Own sources for the flight-model type and the bases (2026-11-03):** the player's jet takes its flight-model type
  from the sim's table (`Settings.fm_section`), not the converted descriptor; `IafBases` reads `own_dir()`'s
  `iaf.ibx`, not the install's ([README.md](README.md) "How the sim reads its data"). `test_own_sources.gd`.
- **The M0 probe (2026-11-02):** passes the no-install check, the profile, the key and sound tables, and for each jet
  the mission's object database, the aircraft definition, the motion table, the 3D cockpit model and the flight
  model's start from the own `bd.ibx` (item C1's FM-0 data; `NEEDS DATA` without that file). It prints `NEEDS DATA`
  for the terrain (item B1) and the in-flight checks.
- A2 (the data compilers), B2a (the airbases' layouts), E1b (sounds, voices, keys), E3a (the training scoring): see
  their rows in [plan.md](plan.md).

## Open
- **No screen yet:** `./iaf2026` runs the M0 probe until the front end (item E2, its main scene `main.tscn`); the sim's
  `Settings` still has the original's `front_end_scene()` / `front_end_overlay()` (E2 overrides them).
- **No wizard yet:** `./iaf2026-setup` runs `iaf-sim all` from the command line until item A3.
- **The probe's flight checks:** the heights and the 3D-only cockpit (no 2D panel) need a flight on the sim's
  terrain; they are written when B1's terrain hook lands (the probe prints FAIL for them once the terrain exists).
- **No own `iaf.ibx` and `terraintype.dat` yet (B2b):** the base move, the tower's wind turn and the radio's bases
  read `own_dir()`'s `iaf.ibx`, so the sim has no bases until B2b writes one; the terrain's `terraintype.dat` too.
  The temp-root run of item F finds any read of the original's data still left.
