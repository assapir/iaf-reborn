# IAF 2026: status

What works and what is open, by work item ([plan.md](plan.md)). Newest first.

## Works
- **[E3b](plan.md#e3-the-training-missions), the training missions in the game (2026-11-03):** `./iaf2026 -- --mission 2011` (… 2032) flies a start-up or
  take-off mission without the front end: parked cold, the start command (Ctrl+E) runs the jet's start sequence on
  the 6-DoF, the screens and the HUD come alive at the real moments; the radio menu (Ctrl+T, 1–3) asks the base's
  tower for start-up, taxi and take-off and the English TTS tower answers; at the end the flight is scored, the
  debrief record written to `user://debriefs/` and the attempt to the pilot log ([training.md](training.md) §7–§10).
  `iaf-2026/tests/test_mvp.gd` flies both missions for the Sufa, the Barak and the F-35I to a Pass.
- **[B2b](plan.md#b2-the-airbases), the airbases in the game (2026-11-03):** `iaf-sim airbases` compiles Ramon, Ramat David, Hatzerim and
  Nevatim into the theatre: `airbases.json` and paved masks (Detailed airbases), an own `iaf.ibx` and
  `terraintype.dat` ([airbases.md](airbases.md) §9); the missions start on the bases' parking spots; the M0 probe
  parks each jet on its spot, on the ground, at a base the flight model finds.
- **[B1](plan.md#b1-the-terrain), the terrain (2026-11-03):** `iaf-sim terrain` builds the sim's theatre `converted/terrain/israel/` from open
  data (GLO-30, Sentinel-2, the Survey of Israel), UTM 36N at 1:1 ([terrain.md](terrain.md)); the sim streams it
  (`theatre_dir()`); the M0 probe flies 5 s over it and checks the heights.
- **[C2](plan.md#c2-the-6-dof) stage (c), the 6-DoF flies the sim's jets (2026-11-03):** TP-1538's control system (g command, α limiter, roll
  and yaw), `Fm { Original, SixDof }` behind `IafFlight` chosen by `Model = 6dof` in the own data (the original game's
  data never reaches it, tested), fuel burn, Mach effects (inferred), the validation rows on the 6-DoF, a real Sufa
  flight in mission 311 ([flight-model.md](flight-model.md) §9.11–9.14).
- **[C2](plan.md#c2-the-6-dof) stage (b), engines, gear, the jets' data (2026-11-03):** TP-1538's engine model scaled to the F110-GE-100,
  F100-PW-229 and F135; a three-strut gear with brakes, steering and a braked stand; the four jets' mass, inertia and
  geometry; tests against the ratings, the spool times, a take-off roll and a stop ([flight-model.md](flight-model.md)
  §9.7–9.10). The take-off roll is 26 % short of the F-16A's SAC figure (open).
- **[C2](plan.md#c2-the-6-dof) stage (a), the 6-DoF's core (2026-11-03):** `crates/iaf-flight/src/sixdof/`: NASA TP-1538's aerodynamic
  tables checked value by value against the scan, appendix B's coefficient build-up, a quaternion rigid body; the
  trim tests match the report's trims and Stevens & Lewis's ([flight-model.md](flight-model.md) §9). Nothing calls
  it yet.
- **[D2](plan.md#d2-units-and-weapons) drafts (2026-11-03), pending the user's decision:** the threat set's 12 units and 10 weapons as readable
  records in `iaf-2026/data/db/drafts/`, every figure sourced; `iaf-sim db` skips them, and a test compiles them as if
  approved ([threat-records.md](threat-records.md)).
- **[A1](plan.md#a1-the-project-skeleton), the project (2026-11-02):** the `iaf-2026/` Godot project with its `shared` link, `sim_settings.gd`, the
  `install_dir()` / `own_dir()` / `keys_file()` calls in the shared code (the original game reads the same files as
  before), the launchers `./iaf2026` and `./iaf2026-setup` (+ `.ps1`), `tools/test.sh` over `iaf-2026/tests` and
  gdparse on both projects, the M0 probe.
- **Own sources for the flight-model type and the bases (2026-11-03):** the player's jet takes its flight-model type
  from the sim's table (`Settings.fm_section`), not the converted descriptor; `IafBases` reads `own_dir()`'s
  `iaf.ibx`, not the install's ([README.md](../README.md) "How the sim reads its data"). `test_own_sources.gd`.
- **The M0 probe (2026-11-02):** passes the no-install check, the profile, the key and sound tables, and for each jet
  the mission's object database, the aircraft definition, the motion table, the 3D cockpit model and the flight
  model's start from the own `bd.ibx` (item [C1](plan.md#c1-fm-0-data)'s FM-0 data; `NEEDS DATA` without that file). With the terrain built
  ([B1](plan.md#b1-the-terrain), the terrain) it flies 5 s over it and checks the heights; the 3D-only cockpit check waits for [E1](plan.md#e1-cockpit-data-sounds-and-voices), the cockpit data.
- [A2](plan.md#a2-the-iaf-sim-compilers) (the data compilers), [B2a](plan.md#b2-the-airbases) (the airbases' layouts), [E1b](plan.md#e1-cockpit-data-sounds-and-voices) (sounds, voices, keys), [E3a](plan.md#e3-the-training-missions) (the training scoring): see
  their rows in [plan.md](plan.md).

## Open
- **The 6-DoF's wave drag is a fit ([C2](plan.md#c2-the-6-dof), the 6-DoF):** fit to each jet's published top speeds, not a sourced table; open: a public
  F-16 drag rise, the high-speed g onset, the take-off roll, the flaps ([flight-model.md](flight-model.md) §9.6).
- **[E3b](plan.md#e3-the-training-missions)'s open points** ([training.md](training.md) §6): the debrief page ([E2](plan.md#e2-the-front-end), the front end), the Hebrew voice (the user), the
  pilot's request voice and the starter's sound (sound.md §7); the 6-DoF's short take-off roll.
- **No screen yet:** `./iaf2026` runs the M0 probe (or with `-- --mission <id>` one mission) until the front end (item [E2](plan.md#e2-the-front-end), the front end, its main scene `main.tscn`); the sim's
  `Settings` still has the original's `front_end_scene()` / `front_end_overlay()` ([E2](plan.md#e2-the-front-end) overrides them).
- **No wizard yet:** `./iaf2026-setup` runs `iaf-sim all` from the command line until item [A3](plan.md#a3-the-setup-wizard), the setup wizard.
- **The probe's 3D-only cockpit check** (no 2D panel in flight) prints NEEDS DATA until [E1](plan.md#e1-cockpit-data-sounds-and-voices), the cockpit data.
- **The airbases' open points** ([airbases.md](airbases.md) §9): the towers of Ramon, Hatzerim and Ramat David (their
  reference points stand in), inland water, one taxi hub per base. The temp-root run of item F finds any read of the
  original's data still left.
