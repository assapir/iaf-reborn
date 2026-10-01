# Roadmap notes

## Later
- **Separate joystick / throttle / pedal devices** (e.g. a stick, a throttle quadrant and pedals as three USB
  devices): the original and the port use one device (the first connected joypad, docs/controls.md §5). Later: an
  Extras option to take each role (stick, throttle, rudder, buttons) from its own device.
- **Extra joystick axes** (e.g. the Hotas X's 5th axis, the throttle rocker = raw axis 4 in its 5-axis mode): the
  original reads four (x, y, throttle, rudder). Later: an Extras option to give a spare axis a role (e.g. zoom, panel
  slide, head pan, rudder on the rocker instead of the twist) and an axis-mapping row instead of editing
  `[devices] joy_axes` by hand.
- **Throttle detent = MIL** (Extras, later): the original maps the lever linearly, so MIL (74 %, the "6" key) and AB1
  (78 %) fall wherever they fall on the lever, not at a physical detent (e.g. the Hotas X's click). Option: measure
  the detent's raw value once and map lever → throttle piecewise so the detent is exactly MIL and the travel past it
  is afterburner.
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
- Braking pitch (later): the wheel brakes pitch the nose down (weight transfer / nose-gear compression).

## Mission replayer (after the missions work)
Generalize the blackbox replay used to debug "Engines ON" (feed a recorded `last_flight.csv` path into the mission
runtime at 8× speed and print every subtitle / pass / box with its time) into a tool for any mission: record →
replay → timeline, and replay recorded flights as regression tests.

## "Real weapons" option (like the Real flight data set)
When the weapons are ported, compare the original's weapon data (ranges, speeds, seeker limits, warhead / Pk,
drag and weight on the stations) with public data. Where the 1998 numbers are off, offer a corrected set behind its own
Extras switch "Weapon data: Original / Real" (separate from Flight data); also the real station rules per jet (which
stores may go on which station, counts per rack, e.g. F-16 stations 1/9 wingtip rails, centreline 5 tank / pod) vs
the game's CDMEWeaponLoadItem lists; the original stays the default. Same method as the flight model's validation report.
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

## Pilot photo: your own picture (after the work)
The original already lets you change it: left click on the Dossier photo cycles the 14 stock photos, right click opens a
file dialog for a custom .bmp (ported, docs/front-end.md §13.4). Later: any image (PNG / JPEG / camera), with a crop to
the photo frame, and an easier way to find it than a right click (e.g. a small "Change" hint).

## Glance-down key (Extras, later)
Hold a key to slide the panel fully into view, release to look ahead again (as modern sims do; a real pilot glances
down with the eyes). The original only has the stepped panel slide (PgUp / PgDn, V).

## Modern aircraft and weapons (post everything)
Newer aircraft (e.g. F-16I Sufa, F-15I Ra'am, F-35I Adir, and modern threats) together with their weapons (e.g.
AIM-120 AMRAAM, AIM-9X, Python 5, Derby, JDAM / SPICE / GBU families, Delilah, modern SAMs), following docs/aircraft.md
"adding a new aircraft" and the weapon data format from docs/weapons.md; real public data with sources. Needs new
models and cockpits (not in the original data).

## More airbases, pick your base (post everything)
Let the player choose the home airbase (the original has 3 spawn bases: Tel Nof, Ramat David, Ramon); add more
Israeli bases (e.g. Hatzerim, Nevatim, Hatzor, Palmachim, Ovda) with their real layouts where the terrain has no
inset (our own airbase imagery / models, real coordinates), selectable in the briefing / Jump In.

## Real world scale — 1:1 mode (decided: we want it; after modern imagery + georeference warp)
The terrain itself is real size (measured with the georeference: ×0.99–1.03 everywhere, docs/georef.md); what is
enlarged are the models (bdb Present scale ×2 aircraft / buildings, ×3–4 vehicles) and the airbases (runways, base
distances 0.75–1.13 of real, not at their real positions — not uniform). Scaling it to
real size would touch mission coordinates, terrain, route timing, weapon/sensor ranges; fits naturally with the
modern imagery (which is real-scale and gets warped to the game frame). Evaluate as an option once modern imagery
and the georeference warp exist.

## Better imagery outside Israel (Extras switch)
Sentinel-2 10 m (WorldCover 2021 / EOX 2017, CC BY) where the original has only ~79 m/px (Sinai, Egypt, Jordan,
Syria, Lebanon, Cyprus); the original stays over Israel (≈10 m, as good or better). 1998 colours by default (needs
per-land-cover colour matching), modern colours as its own switch. Comparisons: docs/imagery-research.md.

## Imagery sources — decisions (2026-10-01, docs/imagery-sources.md)
- Generic, pluggable imagery layers: each source is converted into its own node set; the game picks per region from
  what was converted (a drop-down per region, e.g. Israel: Original / Survey of Israel 2 m / SPOT 5; outside Israel:
  Original / SPOT 5 / Sentinel-2). Options are disabled when their data isn't downloaded / converted.
- Israel: Survey of Israel 2015 2 m (data.gov.il, open licence, no account; large download, the user fetches the
  sheets in a browser). Outside Israel: SPOT 5 (CNES SWH, 5 m; maybe also over Israel if it is smaller).
- Cyprus orthophotos: not used. (No inquiry to the Survey of Israel for now.)

## Hebrew retail edition ("כוכב כחול" / Blue Star) — analysed (docs/packs.md)
The Hebrew CD (archive.org `iaf_20230527`, `IAF.Iso`) is v1.0 with copy protection; its 591 translated files are
byte-identical to Brief.zip + Menu.zip. Setup's `--hebrew-iso` takes the only extras (startup splash, Graphics page).
Its patch `IAFheb1_1.EXE` does not apply to the CD's protected `iafjets.exe` (it wants preflight.us's
`IAF_Hebrew_Fix.zip`, offline) and turns those extras back into the English v1.1 files. Left: the CD's Hebrew
briefing 112 is v1.0 text (v1.1 changed its objective), unused unless that sentence is corrected.
