# Roadmap notes

## Later
- **High-detail F-16 model** to replace the 1998 mesh (~800 triangles): candidate is FlightGear's F-16 (check the licence) or a CC-licensed model. Keep the original dimensions, hinge points (`<part>1/2` helpers), weapon stations, camera eye point and IAF markings; fit it and repaint onto the new UVs.
- v1.1 patch (RTPatch): extract `bdgen.dat`, fixed missions, `msgs.trx` / `credits.trx`.
- **Better satellite imagery**: after georeferencing, optional modern imagery pack (e.g. Sentinel-2, 10 m/px, free) layered over the 1998 photos; optionally modern DEM (SRTM/Copernicus 30 m) for finer relief.
- **3D virtual cockpit** (after the original 2D cockpit works), together with the high-detail F-16 model.
- **Validate the F-16 flight data** against public sources: USAF fact sheet / RTF reference card, NASA TP-1538
  (F-16 wind-tunnel aero data, used by JSBSim), JSBSim/FlightGear F-16, engine thrust data (F100-PW-220/229,
  F110-GE-100/129), E-M diagrams. Automated checks in `iaf-flight`: max level speed (SL, 40k ft), sustained /
  instantaneous turn at corner speed, roll rate, climb, stall/approach speeds, fuel burn. Report deviations; let the
  user choose "faithful 1998" vs "realistic" per item (or a setting).

## "Better physics" option (separate from original / real data)
Improvements over the 1998 model that the player can opt into, decided case by case with the user:
- Ground effect — **done** for the induced drag (McCormick φ(h/b), docs/flight-model.md §10); lift / α / stall speed
  in ground effect not modelled (the model commands g, not CL).
- 1 g hold on the flight path instead of the nose pitch (no slow dive at high speed) — **done** (`flight_path_hold`).
- F-16 / Lavi departure: FLCS deep stall with MPO rocking recovery — **done** (`fbw_departure`, §10.1). Every
  "better physics" option has its own switch; all are listed in docs/flight-model.md §10.

## Mission replayer (after the missions work)
Generalize the blackbox replay used to debug "Engines ON" (feed a recorded `last_flight.csv` path into the mission
runtime at 8× speed and print every subtitle / pass / box with its time) into a tool for any mission: record →
replay → timeline, and replay recorded flights as regression tests.

## "Real weapons" option (like the Real flight data set)
When the weapons are ported, compare the original's weapon data (ranges, speeds, seeker limits, warhead / Pk,
drag and weight on the stations) with public data. Where the 1998 numbers are off, offer a corrected set behind its own
Extras switch "Weapon data: Original / Real" (separate from Flight data); the original stays the default. Same method as the flight model's validation report.
**Started** for the gun and IR missiles (docs/real-weapons.md: weights, top speed, range, gun rounds / rate / muzzle
velocity); to extend with each new weapon type (seeker limits and g limits need sources).

## "Better AI" option
After the original AI brain is ported (AI jets fly the same flight model with AI special cases, docs/flight-model.md
§15; the brain itself is not decoded yet), offer smarter behaviour behind its own switches (e.g. energy-aware BFM,
realistic missile employment / defence, wingman coordination, SAM/AAA radar discipline). The original stays the default.
Separate switches for enemies and wingmen (the original's skill level seems to apply to sides 2/3 only; wingmen
probably have their own command-driven logic), and an option to apply the skill level to both sides.

## Extra sounds (not in the original)
Optional sound additions behind an Extras switch, original default off: wind / airflow noise vs speed (the
original has an unused `SFX_WIND` code), canopy, engine start-up / spool-down, the shipped-but-unused engine idle
loops, `afterburner1/2`, `gearup` / `geardown`, `speedbreak(loop)`, and the silent Betty rows whose files exist
(`cock_bty_pull.wav`, `cock_bty_bingo.wav`, `cock_bty_spin.wav`) — see docs/sound.md.

## Low-end profile (low priority) — e.g. Raspberry Pi 5
Performance pass (draw calls, streaming cost; the dev machine dips to 13–24 fps in places) plus a low-end profile:
Godot Compatibility renderer (GLES3) with the terrain / detail / afterburner shaders checked there, ETC2 instead of
BC1 texture compression (the Pi's GPU has no S3TC), lower terrain detail and resolution. Rust / godot-rust already
build for ARM64 Linux.

## "Real HUD" option
The original HUD is a simplified 1998 F-16 HUD. Offer a realistic HUD per aircraft behind its own Extras switch
(original by default): real symbology and layout (e.g. F-16 Block 30/40 HUD: airspeed / altitude tapes, heading
tape, real pitch ladder with dashed negative rungs, flight path marker, AoA bracket, g / Mach / max-g window,
master arm / weapon modes, bingo / waypoint data), from public references.

## Updated maps (later, just for fun)
The static maps (TSD / briefing EMF maps, map texts, borders, city names) show the 1998 situation. Optional Extras
switch: an updated overlay with today's borders, names and places (drawn by us; original maps by default).

## Setup wizard (after the features)
A first-run wizard in the game itself (Linux + macOS) instead of `tools/setup.sh`: pick the ISO, optionally the v1.1
patch and the Hebrew packs (file dialogs, with checks: right ISO, patch version, pack contents), show progress per
step, and re-run individual steps later from a menu. The CLI stays for scripting / CI.

## Keyboard stick option (maybe, post game)
The original keyboard stick is full deflection at once (taps > ~0.45 s reach 3 g in the F-16; docs/flight-model.md §8).
Possible Extras option: a key ramp / sensitivity setting for keyboard players, original by default.

## Modern aircraft and weapons (post everything)
Newer aircraft (e.g. F-16I Sufa, F-15I Ra'am, F-35I Adir, and modern threats) together with their weapons (e.g.
AIM-120 AMRAAM, AIM-9X, Python 5, Derby, JDAM / SPICE / GBU families, Delilah, modern SAMs), following docs/aircraft.md
"adding a new aircraft" and the weapon data format from docs/weapons.md; real public data with sources. Needs new
models and cockpits (not in the original data).
