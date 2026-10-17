# Roadmap notes

This page lists features planned beyond the original game, and the decisions taken on them. What works today and
the current priorities are in docs/status.md.

- **Original by default:** every item that changes the 1998 game is an opt-in switch (Preferences → Extras or
  Physics); the original stays the default.
- **Tags:** each heading carries its priority or status in brackets or after a dash: "nice to have", "wishlist",
  "later", "low priority", "maybe", "after the …", "post everything", "parked", "started", "built", "done",
  "analysed", "decided".
- **Order:** the "Later" list first, then one section per feature.

**Terms:** AAA = anti-aircraft artillery; ASE / ASC = the F-16 HUD's allowable steering error circle / attack steering
cue; BFM = basic fighter manoeuvres; DEM = digital elevation model (terrain heights); DLZ = dynamic launch zone
(missile range band); EEGS = enhanced envelope gun sight; EO = electro-optical sensor; FCR / SMS / HSD / WPN / TGP =
F-16 MFD pages (fire-control radar, stores management, horizontal situation display, weapon, targeting pod); FOV =
field of view; HSI = horizontal situation indicator; HARM = anti-radiation missile; HUD = head-up display; IR =
infrared; JHMCS = joint helmet-mounted cueing system; LLM = large language model; MFD = multi-function display; OSB =
option select button (the MFD's edge buttons); PBR = physically based rendering (modern material maps); RWR = radar
warning receiver; SAM = surface-to-air missile; TSD = tactical situation display (map).

## Later
Graphics options (models, cockpit, DEM, water, effects, vegetation, lighting, upscaling), with measured costs and a
ranked order, are in [docs/graphics-research.md](graphics-research.md).

- **Separate joystick / throttle / pedal devices** (e.g. a stick, a throttle quadrant and pedals as three USB
  devices). Today the original and the port use one device: the first connected joypad (docs/controls.md §5). Later:
  an Extras option to take each role (stick, throttle, rudder, buttons) from its own device.
- **Extra joystick axes** (e.g. the Hotas X's 5th axis, the throttle rocker = raw axis 4 in its 5-axis mode). The
  original reads four (x, y, throttle, rudder). Later: an Extras option to give a spare axis a role (e.g. zoom, panel
  slide, head pan, rudder on the rocker in place of the twist), and an axis-mapping row so nobody edits
  `[devices] joy_axes` by hand.
- **Better aircraft graphics** (wishlist; Extras switch, the 1998 meshes by default): high-detail PBR models to
  replace the 1998 meshes (~800 triangles).
  - Order: the F-16 first (candidate: FlightGear's F-16, check the licence, or a CC-licensed model), then the other
    flyable jets and the AI types.
  - Keep the original dimensions, hinge points (`<part>1/2` helpers), weapon stations, camera eye point and IAF
    markings; fit each model and repaint onto the new UVs.
- **Better weapon / store models** (Extras switch "Models: Original / Detailed", the 1998 meshes by default): bombs,
  missiles, tanks and pods to a DCS-level bar (FlightGear F-16 shapes, GPLv2+, with our own PBR pass; our own for the
  gaps), committed to the repo and fitted at load time. Design: [docs/graphics-research.md](graphics-research.md)
  §3.13.
- **Modern DEM** (SRTM / Copernicus 30 m) for finer relief. (The modern imagery itself: Sentinel-2 outside Israel is
  done, docs/imagery.md; Survey of Israel 2 m over Israel is done too; SPOT 5 is left, below.)
- **Own jet seen from the cockpit** — done (a fidelity fix, docs/views.md §4.3): the original draws the jet's
  cockpit-view model (`<plane>_bc`) in the cockpit, free-look and padlock views; the port does too. With the
  detailed models (graphics-research.md §3.7, §3.13) a detailed cockpit-view model can follow.
- **Realistic 3D cockpit** (wishlist; Extras switch, the original 2D cockpit by default): a modelled cockpit per jet
  (DCS-style: free head look, the real panel layout, clickable switches, the MFDs / HUD / gauges drawn live on it),
  together with the high-detail model of that jet, the F-16 first.
  - Licence rule: the repo is GPL-3.0-or-later, so a model can ship only under GPL-2.0-**or-later** / a compatible
    licence. Check each file's copyright first.
  - Open references:

    | jet | source | licence |
    |---|---|---|
    | F-16 | FlightGear `github.com/NikolaiVChr/f16` | GPL-2.0 (check "or later" in its copyright.txt) |
    | F-15C/D | `github.com/Zaretto/fg-aircraft` (model Enrique Laso, cockpit photo textures GeneB) | not stated on the repo page |
    | F-4 | `github.com/Zaretto/F-4X` (early alpha, an F-4S) | GPLv2+ |
    | Mirage 2000 | FlightGear Mirage 2000 / 2000-5 | GPLv2+ |
    | Kfir, Lavi, F-35I | no open model found (only paid ones) | — |

- **Validate the F-16 flight data** against public sources: USAF fact sheet / RTF reference card, NASA TP-1538
  (F-16 wind-tunnel aero data, used by JSBSim), JSBSim/FlightGear F-16, engine thrust data (F100-PW-220/229,
  F110-GE-100/129), E-M (energy-manoeuvrability) diagrams.
  - Automated checks in `iaf-flight`: max level speed (SL, 40k ft), sustained / instantaneous turn at corner speed,
    roll rate, climb, stall/approach speeds, fuel burn.
  - Report deviations; let the user choose "faithful 1998" vs "realistic" per item (or a setting).

## Mouse wheel in the settings (nice to have)
The mouse wheel scrolls the settings / preferences pages and their lists. An Extras option sets the direction:
regular (wheel down scrolls down) or natural (reversed, as on macOS trackpads).

## "Real RWR" option: search radars (Extras, wishlist)
- **Original:** the RWR shows a ground site only once it locks or launches (docs/rwr.md).
- **Real RWR:** it also shows a SAM / AAA search or acquisition radar that is painting the jet (threat symbol + search
  tone) before it engages, and loses it when terrain masks the jet. That is how real pilots learn terrain masking (a
  real jet gives no "you are seen" cue).
- **Option** (off by default): a radiating site radar inside its detection range, with terrain line of sight to the
  jet (`IafRadar.line_of_sight`, the sites' own check), shows as a search contact; masked → gone. It helps the "fly
  low" training (313).

## "Better physics" option (separate from original / real data)
Improvements over the 1998 model that the player can opt into, decided case by case with the user. Every "better
physics" option has its own switch; all are listed in docs/flight-model.md §10.
- Ground effect — **done** for the induced drag (McCormick φ(h/b), docs/flight-model.md §10). Lift / α / stall speed
  in ground effect stay unmodelled (the model commands g, not CL).
- 1 g hold on the flight path (in place of the nose pitch), so there is no slow dive at high speed — **done**
  (`flight_path_hold`).
- F-16 / Lavi departure: FLCS (flight control system) deep stall with MPO (manual pitch override) rocking recovery —
  **done** (`fbw_departure`, docs/flight-model.md §10.1).
- Braking pitch (later): the wheel brakes pitch the nose down (weight transfer / nose-gear compression).

## Mission replayer (after the missions work)
Turn the blackbox replay used to debug "Engines ON" into a tool for any mission. Today it feeds a recorded blackbox
flight (`user://flights/*.jsonl` with its mission events and subtitles, docs/blackbox.schema.json) into the mission
runtime at 8× speed and prints every subtitle / pass / box with its time. Goal: record → replay → timeline, and
replay recorded flights as regression tests.

## AI debrief (later)
An opt-in debrief after a flight, written by an LLM.
- **Input:** the flight recorder (inputs and the state per frame), the mission (briefing goals, events, kills /
  losses, the crash or landing reason) and the pilot's settings.
- **Output:** a personal debrief — what went wrong and why (e.g. "the approach was flown at idle with the air brakes
  out: dive, pull, balloon, dive; touchdown at 7 m/s against the 4 m/s limit"), with advice.
- **Maybe:** going over the flight together: the debrief points at moments and the replay jumps there (the sink rate,
  the speed and the stick shown).
- **Needs:** an API key setting and the user's consent to send the data.

## "Real weapons" option (like the Real flight data set)
- **Method:** compare the original's weapon data (ranges, speeds, seeker limits, warhead / Pk, drag and weight on the
  stations) with public data — the same method as the flight model's validation report. Where the 1998 numbers are
  off, offer a corrected set behind its own Extras switch "Weapon data: Original / Real" (separate from Flight data).
- **Station rules:** also the real station rules per jet (which stores may go on which station, counts per rack, e.g.
  F-16 stations 1/9 wingtip rails, centreline 5 tank / pod) vs the game's CDMEWeaponLoadItem lists.
- The original stays the default.
- **Status: started** for the gun and IR missiles (docs/real-weapons.md: weights, top speed, range, gun rounds / rate
  / muzzle velocity) and the radar ranges of the seven jets. Bombs and rockets keep the 1998 numbers so far. Extend
  with each new weapon type (seeker limits and g limits need sources).

## "Better AI" option
- **Today:** the original AI brain is ported for flight (docs/ai.md: the bdb brains fly every AI jet through the same
  flight model, docs/flight-model.md §15); its combat is traced, not built (ai.md §13).
- **Plan:** once it fights, offer smarter behaviour behind its own switches (e.g. energy-aware BFM, realistic missile
  employment / defence, wingman coordination, SAM/AAA radar discipline). The original stays the default.
- **Switches:** separate ones for enemies and wingmen (the original's skill level seems to apply to sides 2/3 only;
  wingmen probably have their own command-driven logic), and an option to apply the skill level to both sides.

## Extra sounds (not in the original)
Optional sound additions behind an Extras switch, off by default (original):
- wind / airflow noise vs speed (the original has an unused `SFX_WIND` code);
- canopy, engine start-up / spool-down;
- the shipped-but-unused engine idle loops, `afterburner1/2`, `gearup` / `geardown`, `speedbreak(loop)`;
- the silent Betty rows whose files exist (`cock_bty_pull.wav`, `cock_bty_bingo.wav`, `cock_bty_spin.wav`).

Details: docs/sound.md.

## Low-end profile (low priority) — e.g. Raspberry Pi 5
- A performance pass: draw calls, streaming cost (the dev machine dips to 13–24 fps in places).
- A low-end profile: Godot Compatibility renderer (GLES3) with the terrain / detail / afterburner shaders checked
  there; ETC2 texture compression (the Pi's GPU has no S3TC, so BC1 is out); lower terrain detail and resolution.
- Rust / godot-rust already build for ARM64 Linux.

## "Real MFDs" option (wishlist)
Like the Real HUD: realistic MFD pages per jet behind their own Extras switch (the original's MFD pages by default,
docs/mfd.md).
- The real page formats and symbology from public references (e.g. F-16 FCR, SMS, HSD, WPN / TGP, RWR; F-15 / F-4E /
  Mirage / Kfir / Lavi / F-35I equivalents), the OSB labels and their functions.
- Driven by the same avionics state (radar, stores, RWR, EO / HARM sensors).
- Pairs with the realistic 3D cockpit (MFDs drawn live on it).

## "Real HUD" option
The original HUD is a simplified 1998 F-16 HUD. This option offers a realistic HUD per aircraft behind its own Extras
switch (original by default): real symbology and layout, from public references (collected per aircraft in
docs/real-hud.md).
- **Built** (Extras > HUD, docs/cockpit.md "Real HUD"): every flyable jet's HUD / sight per docs/real-hud.md "What
  ours draws" (F-16 incl. EEGS, ASE / ASC, DLZ; F-15; F-4E / Mirage reticles; F-35I).
- **Left:**
  - a settable bingo;
  - what that list marks "not drawn";
  - **the real field of view.** The cockpit art's HUD glass is shorter than the real HUD's (the F-16's ≈ 25° total),
    so the F-16 bank scale sits raised into the glass, away from its real place 50 mr below the FOV centre
    (`real_hud/f16.rs` `roll_indicator`). Fix the view so the whole real field fits the glass (eye position / zoom,
    or a taller glass in the art), then put the bank scale back at its real place.

## "Real DASH" (with the Real HUD) — built for the F-16 / F-15 cockpits
Looking aside with the Real HUD on, the F-16 and F-15 now show the Elbit DASH's helmet set (docs/real-hud.md "DASH
helmet": fielding and optics sourced, the layout from the DASH-derived JHMCS).
- **Left:** the DASH's own horizon symbol, shoot cue and Python-specific cues if a source appears; the RWR symbols and
  declutter levels.
- The Lavi / Kurnass 2000 / Kfir keep the original helmet display (their helmets are not documented).

## Updated maps (later, just for fun)
The static maps (TSD / briefing EMF maps, map texts, borders, city names) show the 1998 situation. An optional Extras
switch adds an updated overlay with today's borders, names and places (drawn by us; original maps by default).

## Setup wizard (after the features)
A first-run wizard in the game itself (Linux + macOS) to replace `tools/setup.sh` for players:
1. pick the ISO, optionally the v1.1 patch and the Hebrew packs (file dialogs, with checks: right ISO, patch version,
   pack contents);
2. show progress per step;
3. re-run individual steps later from a menu.

The CLI stays for scripting / CI.

## Keyboard stick option (maybe, post game)
The original keyboard stick is full deflection at once (taps > ~0.45 s reach 3 g in the F-16; docs/flight-model.md
§8). Possible Extras option: a key ramp / sensitivity setting for keyboard players, original by default.

## Pilot photo: your own picture (after the work)
The original already lets you change it: left click on the Dossier photo cycles the 14 stock photos, right click
opens a file dialog for a custom .bmp (ported, docs/front-end.md §13.4). Later: any image (PNG / JPEG / camera), with
a crop to the photo frame, and an easier way to find it than a right click (e.g. a small "Change" hint).

## Turning panel compass / HSI (Extras, future)
In the original, every jet's panel compass and HSI is static art; the heading shows only on the HUD tape and the MFD
pages (docs/cockpit.md). Option: the compass card / HSI rotates with the heading (and the course / bearing pointers on
an HSI), first on the Kfir's panel compass, then on each jet that has one in its panel art; original by default.

## Glance-down key (Extras, later)
Hold a key to slide the panel fully into view, release to look ahead again (as modern sims do; a real pilot glances
down with the eyes). The original has only the stepped panel slide (PgUp / PgDn, V).

## Modern F-16 (Extras switch, wishlist; decided 2026-10-17, research first)
- **Switch:** "F-16: 1990s (Barak) / Today". The default is the game's early-1990s F-16D Barak.
- **Today:** the current IAF two-seat F-16 standard with its upgrades, for the same cockpit and model slot. The
  closest is the F-16I Sufa (Block 52+ two-seater), or the upgraded Barak; the research picks one and says why.
- **What it changes** (each with public sources, as docs/real-aircraft.md and docs/real-hud.md):
  - flight data (engine, weights, conformal fuel tanks on the Sufa);
  - radar (APG-68(V)9 class) and its modes;
  - AIFF (APX-113 class interrogator; docs/real-hud.md "IFF");
  - helmet (the Elbit helmet of the period) and the HUD symbology of that software;
  - weapons (AIM-120C, Python 5, Derby, JDAM / SPICE as in "Modern aircraft and weapons");
  - RWR / self-protection suite.
- **Steps:**
  1. Research the standard and its public data; write it into docs/real-aircraft.md.
  2. Build it behind the switch, the 1990s Barak unchanged.

## Modern aircraft and weapons (post everything)
- Newer aircraft (e.g. F-16I Sufa, F-15I Ra'am, F-35I Adir, and modern threats) together with their weapons (e.g.
  AIM-120 AMRAAM, AIM-9X, Python 5, Derby, JDAM / SPICE / GBU families, Delilah, modern SAMs).
- Follow docs/aircraft.md "adding a new aircraft" and the weapon data format from docs/weapons.md; real public data
  with sources.
- Needs new models and cockpits (the original data has none).

## More airbases, pick your base (post everything)
- Let the player choose the home airbase (the original has 3 spawn bases: Tel Nof, Ramat David, Ramon).
- Add more Israeli bases (e.g. Hatzerim, Nevatim, Hatzor, Palmachim, Ovda) with their real layouts where the terrain
  has no inset (our own airbase imagery / models, real coordinates), selectable in the briefing / Jump In.

## Real world scale — 1:1 mode (decided: we want it; parked, docs/status.md)
- **Today:** the terrain itself is real size (measured with the georeference: ×0.99–1.01, docs/georef.md). Two
  things are enlarged: the models (bdb Present scale ×2 aircraft / buildings, ×3–4 vehicles) and the airbases
  (runways, base distances 0.75–1.13 of real, away from their real positions — not uniform).
- **Cost:** scaling to real size would touch mission coordinates, terrain, route timing, weapon/sensor ranges.
- **Fit:** it fits naturally with the modern imagery (which is real-scale and gets warped to the game frame). Both
  exist now (docs/georef.md, docs/imagery.md); evaluate the option when it is unparked.

## Better imagery outside Israel (Extras switch) — done (imagery phase 1, docs/imagery.md)
- Sentinel-2 10 m (the ESA WorldCover 2021 composite, CC BY 4.0) where the original has only ~79 m/px (Sinai, Egypt,
  Jordan, Syria, Lebanon, Cyprus).
- The original stays over Israel (≈10 m, as good or better).
- 1998 colours by default (a local colour match to the original, imagery.md §4); modern colours as their own choice.
- Comparisons: docs/imagery-research.md.

## Imagery sources — decisions (2026-10-01, docs/imagery-sources.md)
- Generic, pluggable imagery layers: each source is converted into its own node set, and the game picks per region
  from what was converted (a drop-down per region, e.g. Israel: Original / Survey of Israel 2 m / SPOT 5; outside
  Israel: Original / SPOT 5 / Sentinel-2). An option is disabled while its data is not downloaded / converted.
- Israel: Survey of Israel 2015 2 m — done (imagery phase 2, docs/imagery.md; data.gov.il, open licence, no account;
  large download, the user fetches the sheets in a browser). Outside Israel: SPOT 5 (CNES SWH, 5 m; maybe also over
  Israel if it is smaller).
- Cyprus orthophotos: not used. (No inquiry to the Survey of Israel for now.)

## Hebrew retail edition ("כוכב כחול" / Blue Star) — analysed (docs/packs.md)
- The Hebrew CD (archive.org `iaf_20230527`, `IAF.Iso`) is v1.0 with copy protection. Its 591 translated files are
  byte-identical to Brief.zip + Menu.zip.
- Setup's `--hebrew-iso` takes the only extras (startup splash, Graphics page).
- Its patch `IAFheb1_1.EXE` fails on the CD's protected `iafjets.exe` (it wants preflight.us's
  `IAF_Hebrew_Fix.zip`, offline) and turns those extras back into the English v1.1 files.
- Left: the CD's Hebrew briefing 112 is v1.0 text (v1.1 changed its objective), unused unless that sentence is
  corrected.
