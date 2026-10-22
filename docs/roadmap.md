# Roadmap notes

This page lists features planned beyond the original game, and the decisions taken on them. What works today, the
current priorities and what is built: [status.md](status.md).

- **Original by default:** every item that changes the 1998 game is an opt-in switch (Preferences → Extras or
  Physics); the original stays the default.
- **Tags:** each heading carries its priority or state: "wishlist", "later", "low priority", "maybe", "after …",
  "post everything", "started", "measured, skipped".
- **Order:** the "Later" list first, then one section per feature.

**Terms:** AAA = anti-aircraft artillery; ASE / ASC = the F-16 HUD's allowable steering error circle / attack steering
cue; BFM = basic fighter manoeuvres; DEM = digital elevation model (terrain heights); EO = electro-optical sensor; FCR
/ SMS / HSD / WPN / TGP = F-16 MFD pages (fire-control radar, stores management, horizontal situation display,
weapon, targeting pod); HUD = head-up display; JHMCS = joint helmet-mounted cueing system; LLM = large language
model; MFD = multi-function display; OSB = option select button (the MFD's edge buttons); PBR = physically based
rendering (modern material maps); RWR = radar warning receiver; SAM = surface-to-air missile; TSD = tactical
situation display (map).

## Later
Graphics options (models, cockpit, DEM, water, effects, vegetation, lighting, upscaling), with measured costs and a
ranked order: [graphics-research.md](graphics-research.md).

- **Iran theatre** (wishlist, user 2026-10-20): a second map east of the original's, for modern long-range strikes.
  The 1998 world is one fixed theatre (Israel and its neighbours); Iran is far outside it, so this means new terrain,
  imagery, bases and units (large).
- **Fighting in Gaza** (wishlist, user 2026-10-20): missions over Gaza, which lies inside the theatre. The Mission
  Creator (original first, then a freer editor) is the way in.
- **More airbases, pick your base** (wishlist, user 2026-10-20; post everything). The game has ten bases (Israel:
  Ramon, Tel Nof, Ramat David; Refidim / Bir Gifgafa in Sinai; Inshas, Damascus (Mezzeh), Al Qusayr, Bley, Rayak,
  Amman), three of them spawn bases (Tel Nof, Ramat David, Ramon).
  - Wanted: Hatzerim, Hatzor, Nevatim, Ovda, Palmachim, and maybe the civil airports Ben Gurion (LLBG) and Ramon
    Airport (LLER, "Ilan and Asaf Ramon", Timna; not the game's Ramon air base).
  - Each needs a base layout (runways, taxiways, shelters, tower, lineup / taxi / hangar points in iaf.ibx terms),
    its 3D objects and ground art at its real coordinates, and missions that use it (inferred: the Mission Creator
    and the Real 1:1 base move already read bases from data).
  - The player picks the home base in the briefing / Jump In.
- **Mission Creator "Better"** (built): the wind levels (Extras "Mission Creator: Better": WIND / FROM beside the time
  of day, written to misc 0x46a / 0x474; front-end.md §19.4) and the free map editor, a separate tool
  (`./mission-editor`, mission-editor.md: forks and new missions, units, routes, flights, the mission year, win and
  lose, intel, randomness, the sanity check, copy / paste, the Scenario tab, with an AI flight that waits parked until a rule makes it take off).
- **A modern TSD map** (wishlist, user 2026-10-20; "just for fun"): an Extras overlay on the static maps (TSD /
  briefing EMF maps, map texts) with today's borders, names and places, drawn by us; the 1998 maps stay the default.
- **Realistic night vision** (built, user 2026-10-21): Graphics → MORE "Night vision", Shift+N puts the goggles on
  (rendering.md §8), the tube by the mission's year (§8.1). Open: a gain knob, the goggles' round view, the P20
  afterglow, white phosphor; when IAF fighter pilots began to fly with goggles (§8.2).
- **Rain** (wishlist, user 2026-10-21): rain as a weather choice (Extras), with falling rain, wet surfaces and
  lower visibility.
- **Four-ship flights** (wishlist, user 2026-10-22): a real flight of four (Extras). The original's flight is a pair:
  two member slots in the mission file (formats/mis.md) and a leader / wingman formation in the AI (ai.md §7.2); its
  4-ships are two pairs on one route. Ours would add slots 3 and 4 holding finger-four on the leader, the radio's
  commands to the whole flight, #4 taking over a lost #3, and the mission editor's flights of up to 4 jets.
- **Multiplayer** (not approved; if it goes ahead, after the single-player game): how the original does it, a plan
  and the discussion so far: [multiplayer.md](multiplayer.md) (§3.5 is discussion, not decisions).
- **Separate joystick / throttle / pedal devices** (e.g. a stick, a throttle quadrant and pedals as three USB
  devices). The original and the port read one device: the first connected joypad (controls.md §5). Later: an Extras
  option to take each role (stick, throttle, rudder, buttons) from its own device.
- **Extra joystick axes** (e.g. the Hotas X's throttle rocker = raw axis 4 in its 5-axis mode). The original reads
  four (x, y, throttle, rudder). Later: an Extras option to give a spare axis a role (e.g. zoom, panel slide, head
  pan, rudder on the rocker), and an axis-mapping row so nobody edits `[devices] joy_axes` by hand.
- **Better aircraft graphics** (wishlist; Extras → Models, the 1998 meshes by default): high-detail PBR models in
  place of the 1998 meshes (~800 triangles). The F-16D is built (aircraft-models.md); next the other flyable jets,
  then the AI types. Keep the original dimensions, hinge points (`<part>1/2` helpers), weapon stations, camera eye
  point and IAF markings; fit each model and repaint onto the new UVs.
- **Better weapon / store models** (Graphics → MORE → Models, the 1998 meshes by default): bombs, missiles, tanks and pods to a
  DCS-level bar (FlightGear F-16 shapes, GPLv2+, with our own PBR pass; our own for the gaps), committed to the repo
  and fitted at load time. Design: graphics-research.md §3.13.
- **Modern DEM** (SRTM / Copernicus 30 m) for finer relief.
- **Detailed cockpit-view model:** with the detailed models (graphics-research.md §3.7, §3.13), a detailed
  `<plane>_bc` can follow the original one (views.md §4.3).
- **Realistic 3D cockpit** (wishlist; Extras switch, the original 2D cockpit by default): a modelled cockpit per jet
  (DCS-style: free head look, the real panel layout, clickable switches, the MFDs / HUD / gauges drawn live on it),
  together with the high-detail model of that jet, the F-16 first.
  - Licence rule: the repo is GPL-3.0-or-later, so a model can ship only under GPL-2.0-**or-later** or a compatible
    licence. Check each file's copyright first.
  - Open references:

    | jet | source | licence |
    |---|---|---|
    | F-16 | FlightGear `github.com/NikolaiVChr/f16` | GPL-2.0 or later (the Detailed F-16D uses it, credits.md) |
    | F-15C/D | `github.com/Zaretto/fg-aircraft` (model Enrique Laso, cockpit photo textures GeneB) | not stated on the repo page |
    | F-4 | `github.com/Zaretto/F-4X` (early alpha, an F-4S) | GPLv2+ |
    | Mirage 2000 | FlightGear Mirage 2000 / 2000-5 | GPLv2+ |
    | Kfir, Lavi, F-35I | no open model found (only paid ones) | — |

- **Pilot guides: the MFD and radar pages** (after "Real MFDs"): an annotated section per real page, with pictures,
  as the HUD sections have. Until then the MFDs are the original pages, which the original manual covers (EN
  4.12–4.24, manual-audit.md); the guides give only the values the realistic options change (e.g. the radar ranges,
  guides/f16.md §14).

## Mission replayer (after the missions work)
Today a recorded blackbox flight (`user://flights/*.jsonl` with its mission events and subtitles,
blackbox.schema.json) replays into the mission runtime at 8× speed and prints every subtitle / pass / box with its
time; `tools/flight_timeline.py` turns a flight into a timeline and summary. Goal: replay any mission's recorded
flights as regression tests.

## AI debrief (later)
An opt-in debrief after a flight, written by an LLM.
- **Input:** the flight recorder (inputs and the state per frame), the mission (briefing goals, events, kills /
  losses, the crash or landing reason) and the pilot's settings.
- **Output:** a personal debrief — what went wrong and why (e.g. "the approach was flown at idle with the air brakes
  out: dive, pull, balloon, dive; touchdown at 7 m/s against the 4 m/s limit"), with advice.
- **Maybe:** going over the flight together: the debrief points at moments and the replay jumps there (the sink rate,
  the speed and the stick shown).
- **Needs:** an API key setting and the user's consent to send the data.

## "Real weapons" option — started
Extras → Weapon data: Original / Real (real-weapons.md). Built: the missiles (weights, top speed, range, IR seeker
lock ranges and cones), the guns, the seven jets' radar ranges, the gun's hit test and the published lethal radii.
- **Left:** the bombs and rockets keep the 1998 numbers; the real station rules per jet (which stores may go on which
  station, counts per rack, e.g. F-16 stations 1/9 wingtip rails, centreline 5 tank / pod) vs the game's
  CDMEWeaponLoadItem lists; each new weapon type as it comes (g limits need sources).

## "Better AI" option
- **Today:** the original AI brain flies and fights as the exe (ai.md §13–§14).
- **Plan:** smarter behaviour behind its own switches (e.g. energy-aware BFM, realistic missile employment /
  defence, wingman coordination, SAM / AAA radar discipline). The original stays the default.
- **Switches:** separate ones for enemies and wingmen (the original's skill level seems to apply to sides 2 / 3 only;
  wingmen probably have their own command-driven logic), and an option to apply the skill level to both sides.

## Extra sounds (not in the original)
Optional sound additions behind an Extras switch, off by default (sound.md):
- wind / airflow noise vs speed (the original has an unused `SFX_WIND` code);
- canopy, engine start-up / spool-down;
- the shipped-but-unused engine idle loops, `afterburner1/2`, `gearup` / `geardown`, `speedbreak(loop)`;
- the silent Betty rows whose files exist (`cock_bty_pull.wav`, `cock_bty_bingo.wav`, `cock_bty_spin.wav`).

## Low-end profile (low priority) — e.g. Raspberry Pi 5
- A performance pass: draw calls, streaming cost (measured hotspots: graphics-research.md §1–§2).
- A low-end profile: Godot Compatibility renderer (GLES3) with the terrain / detail / afterburner shaders checked
  there; ETC2 texture compression (the Pi's GPU has no S3TC, so BC1 is out); lower terrain detail and resolution.
- Rust / godot-rust already build for ARM64 Linux.

## "Real MFDs" option (wishlist)
Started: research done, nothing built. Each jet's real head-down formats behind their own Extras switch (the
original's pages by default, mfd.md); the per-jet reference, the user's decisions (2026-10-21) and the build order
(F-35I and F-16 first) are in [real-mfd.md](real-mfd.md).
- IFF on the radar formats, as the real jets show it (real-hud.md "IFF"): the F-15C's and F-4E's interrogation
  replies, and the F-35I's track colours and shapes (green circle friend, yellow square unknown, red diamond hostile).
- Pairs with the realistic 3D cockpit (MFDs drawn live on it).

## "Real HUD" and "Real DASH": what is left
Built: every jet's real HUD / sight and the F-16 / F-15 DASH helmet set (real-hud.md "What ours draws", "DASH
helmet"). Left:
- a settable bingo;
- what real-hud.md marks "not drawn";
- **the real field of view.** The cockpit art's HUD glass is shorter than the real HUD's (the F-16's ≈ 25° total),
  so the F-16 bank scale sits raised into the glass, away from its real place 50 mr below the FOV centre
  (`real_hud/f16.rs` `roll_indicator`). Fix the view so the whole real field fits the glass (eye position / zoom, or
  a taller glass in the art), then put the bank scale back at its real place;
- the DASH's own horizon symbol, shoot cue and Python-specific cues if a source appears; the RWR symbols and
  declutter levels. The Lavi / Kurnass 2000 / Kfir keep the original helmet display (their helmets are not
  documented).

## Setup wizard: the user's review
Built (`./setup`, `game/setup/`, setup.md); the pages wait for the user's review. Running setup again is the way to
add an extra or redo a step; there is no setup button in the game (user decision).

## Exported build (with the setup wizard)
A packaged Linux and macOS build of the game (Godot export: one program and its game file, the Rust extension
bundled), so players need no Godot, Rust or cargo and no `./iafjets` build step; with the setup wizard, no terminal
at all.
- **Needs:** Godot's export templates; the extension built and bundled per platform; the data folder beside the
  program instead of `res://../assets`; macOS signing / notarisation (to check).
- **Gain:** distribution. Run-time speed is the same (Godot compiles scripts to bytecode at load either way).
- Development keeps running unexported; the export is built for releases.

## Keyboard stick option (maybe, post game)
The original keyboard stick is full deflection at once (taps > ~0.45 s reach 3 g in the F-16; flight-model.md §8).
Possible Extras option: a key ramp / sensitivity setting for keyboard players, original by default.

## Pilot photo: your own picture (after the work)
The original lets you change it: left click on the Dossier photo cycles the 14 stock photos, right click opens a
file dialog for a custom .bmp (ported, front-end.md §13.4). Later: any image (PNG / JPEG / camera), with a crop to
the photo frame, and an easier way to find it than a right click (e.g. a small "Change" hint).

## Video record key (Extras, future idea; 2026-10-18)
A key in flight starts and stops a video recording, next to the screenshot key. Godot's movie writer
(`--write-movie`) is switched on at launch only, and it steps game time by one frame per rendered frame, which slows
live play while recording at 4K. Two ways:
1. Live capture: each frame copied from the screen to ffmpeg (optional, found at run time) into an mp4. It holds the
   frame rate at 1080p; at 4K the GPU readback is likely to drop it.
2. Record a replay, then render it with the movie writer at any quality (4K, 60 fps). This needs a full replay of
   every unit (the flight recorder holds only the player's jet).

## "Real Betty" option (Extras switch, wishlist; researched 2026-10-19)
- **Switch:** voice warnings per real aircraft. The default is the game's Betty (sound.md §4). With Real HUD the F-16
  and F-35I already speak their real dive and height warnings (deviations.md §2 "HUD").
- **Per jet:** which jets speak which warnings, with sources: [real-betty.md](real-betty.md) §1.
- **Voice, licences and open questions:** real-betty.md §2–§6.

## F-16I Sufa option (Extras switch, wishlist; decided 2026-10-17, F-16I chosen 2026-10-19)
- **Switch:** "F-16: Barak (1990s) / Sufa (F-16I)". The default is the game's early-1990s F-16D Barak.
- **Sufa:** the IAF's F-16I (Block 52+ two-seater), in the same cockpit and model slot as the F-16D.
- **What it changes** (each with public sources, as real-aircraft.md and real-hud.md):
  - flight data (F100-PW-229 engine, weights, the conformal fuel tanks);
  - radar (APG-68(V)9) and its modes;
  - AIFF (APX-113 class interrogator; real-hud.md "IFF");
  - helmet (Elbit DASH) and the HUD symbology of its software;
  - weapons (AIM-120C, Python 5, Derby, JDAM / SPICE as in "Modern aircraft and weapons");
  - RWR / self-protection suite;
  - how it looks: the Sufa model on the Detailed F-16D (tools/f16d/rig.py: conformal fuel tanks, the large dorsal
    spine, the IAF Sufa livery and markings), and its cockpit (colour MFDs);
  - its voice warnings ("Real Betty" option above).
- **Steps:** 1. research (done: [f16i.md](f16i.md), with its open questions and build outline); 2. build it behind the
  switch, the 1990s Barak unchanged.

## Modern aircraft and weapons (post everything)
- Newer aircraft (e.g. F-16I Sufa, F-15I Ra'am, and modern threats; the F-35I Adir is built, f35i.md) together with
  their weapons (e.g. AIM-120 AMRAAM, AIM-9X, Python 5, Derby, JDAM / SPICE / GBU families, Delilah, modern SAMs).
- Follow adding-a-plane.md and the weapon data format from weapons.md; real public data with sources.
- Needs new models and cockpits (the original data has none).

## Imagery sources — decisions (2026-10-01, imagery-sources.md)
- Generic, pluggable imagery layers, picked per region from what was converted; an option is disabled while its data
  is missing (built: imagery.md).
- Left: SPOT 5 (CNES SWH, 5 m) outside Israel, maybe also over Israel if it is smaller.
- Cyprus orthophotos: not used. No inquiry to the Survey of Israel for now.

## Hebrew retail edition ("כוכב כחול" / Blue Star)
Analysed in packs.md. Left: the CD's Hebrew briefing 112 is v1.0 text (v1.1 changed its objective), unused unless
that sentence is corrected.

## Faster mission start: pre-baked terrain, shader warm-up — measured, skipped (2026-10-20)
Two ideas to shorten a mission start, both measured on 2026-10-20 (Intel Iris Xe, 8 cores, Vulkan) and skipped by
user decision: each saves about half a second of an 8.6–9.1 s start.
- **Pre-baked terrain tiles:** setup would store each colour tile already mipmapped and BC1-compressed, so
  `terrain.gd` `_decode()` would only load it.
  - Per tile today: 9.2 ms for the base terrain (load 4.5, mipmaps 0.8, BC1 3.9), 13.4 ms for the Survey 2015
    imagery; pre-baked: about 1 ms.
  - A start loads about 290 tiles (missions 311, 231) on 6 worker threads: about 2.6 s of work, so about 0.4–0.5 s
    of the start.
  - In flight nothing changes: the tiles already decode off the main thread.
  - Cost: the baked tiles are about 3 times the JPEG size (+0.5 GB for the base terrain, +7–9 GB with the imagery).
- **Shader warm-up during setup:** Godot already keeps its shader cache and Vulkan pipeline cache in the user folder,
  and every real-render run (the game, the guide shots) fills them. Mission 311 with empty caches: 9.1 s to the
  ground; with warm caches: 8.6–8.8 s. The slowest of the first 120 frames was 19 ms in both cases, so the first
  flight does not stutter. A warm-up would save 0.3–0.5 s once, on the first flight after an install or a Godot or
  driver update.
