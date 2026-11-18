# Modern IAF: status

What works and what is open, by work item ([plan.md](plan.md)). Newest first.

## Works
- **The key faults the manuals exposed (2026-11-18; the user plays on a Mac laptop's keyboard, no HOTAS;
  [front-end.md](front-end.md) §9.1):** the speedbrakes have their own switch keys (Speedbrakes open (hold) on
  B, Speedbrakes close on Shift + B: open while held, they stay when let go; [flight-model.md](flight-model.md)
  §9.11) and Wheel brakes (Shift + G) brakes the wheels only; the Drag chute key and row are gone (no jet has one);
  the roll trim, MANUAL PITCH, STORES CONFIG and the GPS bomb's keys are rows of the Keys screen and of the manuals' key card;
  the cards' Throttle – OFF items carry their key (Shift + 1). For the Mac: chaff and flares on Ctrl + Z / Ctrl + X,
  the weapon view on F2, laptop keys for the eight commands on Page Up / Page Down / Home / End, and Ctrl + Q /
  Ctrl + M named with Ctrl. A test fails on a listed command with no key on a Mac laptop
  (`every_listed_command_has_a_key_on_a_mac_laptop`); `modern-iaf/tests/test_switch_keys.gd`, `test_devices.gd`. Owed:
  the run on the Mac. Not started (not in the user's words): records for the four keys still read outside the table
  (Ctrl + F1 quit box, Ctrl + F2 cockpit / outside, Ctrl + F12 flight information line, Shift + N goggles); a
  SPD BRK switch to click (the cockpit models have none); the speedbrakes' own line on the F-16's landing card; a
  speedbrake button in the Hotas X's map (`data/devices/hotas_x.json`: its brake button is the wheel brakes now); a
  laptop key for the notebook's page turn (Page Up / Page Down; the wheel, the trackpad and the tabs turn it too).
  The notebook's card keeps naming no key (the user, 2026-11-13); the manuals' step tables show the throttle's keys.
  With an autopilot mode flying, the brake control still opens the speedbrakes in the air.
- **The F-16s' lighting controls (2026-11-17, the lights audit part B, [cockpit.md](cockpit.md) §5.5; approved
  17 Nov):** the lighting panel's dimmers, MAL & IND LTS, NVIS, INDV LTG CONT and DATA ENTRY DISPLAY,
  the ICP's BRT wheel, the exterior lights panel and LANDING / TAXI each do their job; LE FLAPS rests at AUTO and its
  caution lights at LOCK (`modern-iaf/tests/test_cockpit_lights.gd`). ANTI SKID, STORES CONFIG and SEAT NOT ARMED stay
  test only: the anti-skid system, the load's category and the seat lever are not modelled.
- **The Adir's radar, sensors and helmet (2026-11-17, avionics-plan.md slice 7 part B, A2–A7, E5, H6–H8, N9, P5):**
  the real FCR's controls on the APG-81's row (`radar.fcr`; the Sufa's keys): SRCH with CRM RWS / TWS / VSR, SAM's
  four bugs, STT, ACM and BORE, the cursor with its altitude coverage; ASR with the ground map as a grey SAR picture
  (GM, EXP, DBS1, DBS2, FZ, SP, CZ, GMT, SEA, AGR); the combat ID (friend green circle, unknown yellow square,
  hostile red diamond) on SRCH, ASR, the TSD and the helmet's lock (`aiff.rs` `combat_id`, inferred); the TWD with the
  range's radar drones; the DAS's MAW on the TWD and in the helmet; the data link's tracks on the TSD; the helmet's
  break X and pull-up cue (the F-16's GAAF rule, inferred). `modern-iaf/tests/test_sim_adir_radar.gd`. Electronic
  attack stays out (§8.5); the SRCH layout stays inferred (G32: no source).
- **The Barak's avionics (2026-11-17, avionics-plan.md slice 6, §3 B1–B11):** today's upgraded F-16D (Barak 2020,
  the Sufa's avionics installed) as data merged over the F-16's definition (`modern-iaf/data/planes/f16.json`): the
  real FCR's controls on the APG-68's row (CRM RWS to 43 NM, SAM with one bug), the colour MFDs with the HSD's map, the
  AIFF, no MAW, the wide-angle HUD. Every Sufa avionics test now flies both jets (`base.gd` `sim_f16s`;
  `IAF_SIM_JET=f16d` runs one). Found and fixed: the Barak had none of the real FCR (its definition had no
  `radar.fcr`); the TACAN started on Ramon's channel on every jet (now the home base's station).
- **The F-16s' 3D-cockpit lamps (2026-11-17, the lights audit, [cockpit.md](cockpit.md) §5.2):** every lamp of the
  model lights, the caution panel's 32 among them; each is wired to the state that lights it (the start-up's lamps on
  the battery, the ELEC panel, JFS RUN, the cautions and MASTER CAUTION with its reset and the ELEC panel's CAUTION
  RESET, the test switches, the threat warning panel's buttons, ECM ENBL), and MAL & IND LTS lights them all. Lamps of
  systems the game lacks (the EPU, TF, the AR system, the marker beacons, the seat, oxygen) light only in that test
  (`modern-iaf/tests/test_cockpit_lamps.gd`).
- **The Sufa's up-front controls, HUD panel, navigation and DGFT (2026-11-17, avionics-plan.md slice 5 part A,
  G2, G17, G18, G28, G29; [ufc.md](ufc.md)):** every DED page the sim can feed with data entry on keys and the 3D
  ICP (STPT editing, markpoints 26–30, BINGO, ALOW, CRUS, TIME, T-ILS with TACAN to the bases, INS, BULL, LASR,
  COM1 / COM2 and the backup UHF); the HUD control panel's switches, ALIGN, SIM and the SOI asterisk; no steering
  until the INS navigates; DGFT / MSL OVRD on V / Shift + V; the EHSI's TCN.
- **The F-16s' EW and identification (2026-11-17, avionics-plan.md slice 5 part B, E1, E2, E4, R15, N5, N6; G13,
  G19, G20, G30, G31; [ews.md](ews.md)):** the threat display on the 3D RWR scope after the dash-34 and the ALR-69
  (labels by class, diamond, lock square, launch circle, new-threat flash and tone, PRI / OPEN, UNKNOWN, TGT SEP,
  HANDOFF, SYS TEST, the volume knobs), the range's radar drones heard from every side as "35"; the Sufa's MAW (an
  "M" with the seconds to impact); the CMDS panel, programs 1–4 and the CMS keys (P, Shift + P, Y; Shift + Y MODE,
  Ctrl + Y program) releasing through the game's dispense with the VMS's "Counter" and "Chaff flare low / out"; the
  Sufa's AIFF (O, Shift + O, TMS left in CRM: green circles, yellow squares); the data link on the HSD and the FCR (the
  DL switch); the DED's EWS pages (programs, BINGO, REQCTR / BINGO / FDBK / REQJAM), IFF, DLNK and INTG; the transponder's modes, codes and IFF IDENT (Alt + K); the AWACS's contact calls voiced. Fixed the
  same day: the HUD's DED DATA overlapped its right column (now a block of character cells between the columns, the
  roll indicator off meanwhile), the threat symbols piled on the centre (now on rings by lethality, apart), the AIFF's
  circle sat below its FCR contact (now by slant range), the 3D DED showed 3 of its 5 lines and its columns did not
  line up. The MAW names no missile type (the parked rows of missile performance).
- **The Sufa's MFDs (2026-11-17, avionics-plan.md slice 4, G8 DMS, G14–G16, G24, G25;
  [../../docs/mfd.md](../../docs/mfd.md) §9 "Modern MFDs"):** each MFD keeps three formats per master mode (NAV,
  A-A, A-G); the menu adds DTE, FLCS, BLANK and the RESET MENU; the sensor of interest with its box and NOT SOI, DMS on
  Ctrl + Page Up / Down and Ctrl + `[` / `]`, the cursor and TMS keys acting on the SOI; the HSD's DEP / CEN, CPL, EXP,
  FRZ, CNTL page, bullseye and cursor (TMS up on a steerpoint makes it current); the SMS's submode menu and PROF1 /
  PROF2 per weapon; the Litening pod on the chin with the TGP's POINT / AREA / INR tracks, slaving to the radar's
  designation or the steerpoint, LASER ARM (Shift + L, the 3D cockpit's switch) and the laser; the GBU-10, GBU-12
  and GBU-16 on both F-16s ([weapons.md](weapons.md) §7). Checked on the range: a GBU-12 lased by the pod hits a
  hulk (`modern-iaf/tests/test_sim_mfd.gd`). Pods part 1 (2026-11-17): a laser bomb needs the pod (the loadout's
  Fly off with a line saying what to add, the briefing's line, the SMS's NO LASER; weapons.md §7.1) and the pod's
  cockpit steps (power-up, STBY, CZ, the TD box, the laser code, the automatic laser, MASK; §7.2;
  `modern-iaf/tests/test_sim_pod.gd`). Open: the HUD's own SOI mark (no source shows it). The Litening
  drawn with its own model (FlightGear's AN/AAQ-28 at the real 2.20 m by 0.406 m, 2026-11-17,
  [../../docs/aircraft-models.md](../../docs/aircraft-models.md) §5.1); the Hangar and the Loadout screen hang it by its
  top from the chin station, as the flight does, under the model's right chin pylon (FlightGear's, 0.69 m right).
  Pods part 1, step B (2026-11-17): the chin stations 5R (the Litening) and 5L (the engine's 13th station, pylon J),
  the LANTIRN navigation pod (AN/AAQ-13) on the Sufa's 5L and the Pathfinder on the Barak's, carried, drawn (their
  own model, `lantirn.glb`), weighed and kept by the jettisons, on the SMS inventory under 5R (weapons.md §7.3;
  `modern-iaf/tests/test_sim_chin_pods.gd`); a load with a laser bomb and no pod is not saved as a preset, and the
  Loadout screen's line is one short line, the front end's Hebrew saying פוד. The navigation pods' HUD picture and
  terrain following come in pods part 2.
- **The Sufa's radar, air to ground (2026-11-17, avionics-plan.md slice 3, G9–G12;
  [../../docs/radar.md](../../docs/radar.md) §9.7):** R gives GM, Q steps GMT and SEA; NORM's fan and the EXP, DBS1
  and DBS2 patches (Ctrl + `;`) over a radar picture made from the terrain (slopes, shadows, dark water and runways,
  bright returns); the ground cursor on the cursor keys or the mouse; FZ, SP, CZ and STP / TGT (Alt + `;`, `'`, `/`,
  `.`); TMS up designates the cursor's point or tracks the return under it (FTT), and the GPS bombs, the SPICE in VIS
  and the HUD's TD box take that point; GMT lists the movers on a dimmed map, SEA the ships; AGR ranges a CCIP
  delivery for the FCR and the HUD. Each range has a towed hulk (GMT) and a barge at sea (SEA). Checked on the range
  (`modern-iaf/tests/test_sim_fcr_ag.gd`). BCN and TF stay parked (avionics-plan.md G12).
- **The Sufa's radar, air to air (2026-11-17, avionics-plan.md slice 2, G1 and G5–G8;
  [../../docs/radar.md](../../docs/radar.md) §9):** the real F-16 FCR on the game's modes: STBY at power-on, no
  radiating with weight on wheels, CRM by itself once airborne; RWS with the A6 / A3 / A1 scans, B4 / B1 / B2 bars and
  the antenna elevation; SAM keeping four bugged tracks while searching; TWS's track files kept 13 s; VSR; ACM's 20,
  60, SLEW and BORE patterns with their HUD cues; the bug centring the scan; EXP (Ctrl + `;`); the CNTL page with
  target history and MTR; NO RAD; the acquisition cursor and the TMS on keys (`/`, `;`, `'` with Shift / Ctrl, Alt +
  Up / Down, Ctrl + arrows), listed on the Keys screen. Checked against the range's drones (`modern-iaf/tests/test_sim_fcr.gd`).
- **A weapons range per jet (2026-11-17, avionics-plan.md slice 1, G3; [training.md](training.md) §3.4):** the
  Training list's third mission for the Sufa, the Barak and the Adir: a cold start, then five drones (the sim's own
  F-16 and F-35 on the shared AI under the sim's own brains: co-altitude, low, a manoeuvring one, a pair whose radars
  the RWR hears; red for the exercise, never shooting) and six ground targets (four retired airframes parked, a fifth
  towed, a target barge at sea); the mission's own load carries the bombs for them (2026-11-18, [training.md](training.md)
  §3.4: until then the load had none and the lesson could not be passed as briefed). The radar finds the
  drones, the gun, missiles and bombs destroy them, and the scorer counts air and ground kills on the debrief
  (`modern-iaf/tests/test_sim_range.gd`).
- **Every F-16 3D-cockpit control is seen to move (2026-11-16, finish list C4, [cockpit.md](cockpit.md) §5.2 "Every
  control"):** the parts FlightGear does not animate are pressed in or tilted; the proof renders every control through
  its positions (`modern-iaf/tests/_controls_shot.gd`). 2026-11-17 (C4b): the M button and the right MFD's GAIN rocker
  move (a row's own property is read from the store); the MFDs' inboard rockers and MAX POWER are seen with the head
  leaned; the proof compares full-size crops and pictures a hidden part from a lean; the EHSI draws the heading bug and
  course arrow its HDG and CRS knobs set; the ADV MODE button shows (the build hides FlightGear's Block 15 panel face
  over it) and its STBY legend lights while selected.
- **The Settings in the r3 layout (2026-11-16, the finish list's F7, [front-end.md](front-end.md) §14):** a search
  across the sections in English or Hebrew, the sections' counts, Graphics' Preset row (Laptop, Balanced, High,
  Everything on, Custom), segmented buttons for every row's choices, a cost chip per graphics row from measurements on
  the Iris Xe laptop (`tools/settings_cost.sh`), the pane on the hovered setting with its Off / On picture (our own
  renders), its description and the frame time measured during the player's last flight; Defaults and Back to the
  hangar in the footer. Devices: Keyboard with no joystick connected; the Joystick screen without axis rows then; the
  Keys and Joystick screens in the Settings' frame.
- **The autopilot lands softly; the roll starts faster (2026-11-16, finish list: autopilot touchdown, roll onset,
  [flight-model.md](flight-model.md) §9.6, §9.13):** on the 6-DoF the autopilot flies a real final, 3° (inferred) at
  the speed of the F-16 manual's 13° α (about 145 kt), with a flare from about 15 m: touchdowns at 2.0–2.6 m/s (were
  4.3–9.6). The stick's roll command ramps at 688 deg/s² as reborn's Real roll does (its roll channel): 90° in
  0.80 / 0.85 s at 350 kt and 0.65 / 0.68 s at 480 kt (Barak / Sufa, were 0.87 / 0.88 and 0.78 / 0.80); the
  flaperons' sourced 62 deg/s keep it above the command's 0.55 s.
- **The Missions cards and no key caps (2026-11-16, the user, [front-end.md](front-end.md) §2):** a section's card
  shows its number, title and progress (no subtitle or "What it holds"); no button carries a key cap (Back's "Esc"
  gone everywhere, Esc still works).
- **Attributions (2026-11-16, the finish list's F8, [front-end.md](front-end.md) §5):** a footer Back, the list
  scrolls by the arrows and Page Up / Down; the six unused jet photos, their entry and credits deleted.
- **MAIN PWR's BATT, the JFS's START 1 and RDR ALT's STBY (2026-11-16, finish list C3, [cockpit.md](cockpit.md)
  §5.2):** each a position of its own in the flight model with its consequence, clicked or dragged in the 3D cockpit.
- **The crash page in Hebrew (2026-11-16, the finish list's F10, [front-end.md](front-end.md) §11):** the loading
  step by its loading-screen name in the page's language; the log's path one left-to-right run.
- **The F-16s' 3D cockpit switches work their systems (2026-11-16, finish list C2, [cockpit.md](cockpit.md) §5.2
  "Every control"):** MASTER ARM, EMER JETT, the ICP's A-A / A-G, the MFD BRT rockers, ALT FLAPS, STORES CONFIG,
  MPO, HMCS SYM INT (the helmet display's power), MAL & IND LTS (the lamp test) and MASTER CAUTION (its reset) work
  their systems, and their keys move them too. Test: `modern-iaf/tests/test_controls_systems.gd`.
- **The Pilot log, the Pilot screen, the section list (2026-11-16, the finish list's F6, [front-end.md](front-end.md)
  §2, §3):** the log's dates as the debrief's with the time, filters by jet and by mission, rows named, a footer Back;
  the Pilot screen's form in one column (no empty middle column); with every mission passed no Next on the list.
- **The pause menu and the Settings over a flight (2026-11-16, the finish list's F4, [front-end.md](front-end.md)
  §8, §9):** the pause menu names the mission and the jet; the Settings, Keys and Joystick screens over the flight
  have the front end's top bar (crumbs from Paused) and a footer with Back; a row's choices side by side, so Graphics
  fits with VSync whole. The notebook's frame cost and pictures in [training.md](training.md) §11.
- **The debrief (2026-11-15, the front-end finish list's F5, [front-end.md](front-end.md) §13):** the approved
  r3_debrief: the sheet with the goals (target, flown figure, ✓ / !) and "Next time:" from the Rust scorer, the whole
  flight on the map (the track coloured by phase, the planned route, Start / Lift-off / End pins with their times, the
  base inset) and the speed, height and load graphs with the phase band and the marked events (`IafTraining.track`);
  Pilot log, Export flight data, Back to missions, Fly again, Next mission; a record without a recording shows the
  sheet and the right column's empty state; Hebrew dates name the month.
- **The Missions and section screens, each jet's own missions (2026-11-15, the front-end finish list's M2,
  [front-end.md](front-end.md) §2, §12):** a section lists only the Hangar jet's missions (the user: "show only the
  same plane missions"), numbered 1, 2 …, with that jet's statuses, Next and progress (also on the Hangar's card); a
  mission flies in its own jet again and the debrief's Next mission is that jet's next one. The Missions screen's
  cards fill the screen and say what each section holds (Training: the jet's missions and the lessons coming later;
  the others "Coming later" with what they will hold); the section's list has a side panel on the mission under the
  focus (what it is for, base, time allowed, last result, best time); both screens have the footer's Back with Esc.
  The Settings' icon is a gear of our own, crisp at every size (Hangar, pause menu, Settings title). The Hangar's jet
  view shows no white frame while dragged; only the keyboard's focus shows a faint ring.
- **The briefing ready for several flights (2026-11-15, the front-end finish list's N1, [front-end.md](front-end.md)
  §10):** a mission names its flights (Alpha, the player's, and Bravo..Delta: callsign, jet, task, route, stores; Rust
  `flights.rs`, compiled into `sim.flights`); the briefing shows a mission of several flights as tabs with the
  player's picked and its line, and the map draws each other flight's route in its own colour. Every mission has one
  flight today and shows no tabs. Multi-flight missions themselves wait for their AI flights' missions.
  `cargo test -p iaf-tools --lib flights briefing sim`, `test_front_end.gd` (the sample mission
  `modern-iaf/tests/data/two_flights.json`).
- **The menu flow (2026-11-15, the front-end finish list's M, [front-end.md](front-end.md) §1, §2):** the Hangar's Fly
  opens a Missions screen with the sections Training, Campaign, Single missions and Fly now (a section without
  missions greyed, no click, no focus; Fly now greyed until random missions and dogfights come); a section opens its
  list with each mission's last result (Pass with the best time, Fail, Not flown yet) and the next one to fly marked
  and focused; a row opens its briefing (no mission tabs on it any more), whose Back returns to the list; Arming
  returns to the briefing; the debrief has Next mission, Fly again and Back to missions. The list's progression logic
  is shared with reborn (`shared/mission/mission_list.gd`). Campaign and Single missions wait for their missions.
- **The Loadout screen (2026-11-14, the front-end finish list's F3, [front-end.md](front-end.md) §10.1):** Arming on
  the briefing opens a screen of its own: the jet seen from beneath (the Hangar's live model, the camera under it, the
  F-35I's bays open) with a callout per station (number, place on the wing, store, weight; an empty one dashed) and
  its line to the station on the model; LOADOUTS (the mission's own and the pilot's saved ones, named per jet, saved,
  picked and deleted on the screen; the one on the jet tinted, no side bar); TAKE-OFF WEIGHT (figure, share of the
  maximum, the wings' balance, fuel, gun rounds, chaff / flares) and STORES; Reset to the mission's, Briefing, Fly.
  The editor's rules stay (racks, refusal, drag and drop, keyboard). Since 2026-11-15 (finish list L, the user's
  notes): an edit changes its own station only, "Mirror to the other wing" (off by default) fills the pair; Fly the
  size of its neighbours; every store of a rack drawn in its place on the Loadout screen's, the Hangar's and the
  flown jet (a TER-9/A's three Mk 82, a BRU-57/A's two GBU-38; our own rack models). Open: named type loadouts wait for a
  sourced real loadout. `test_front_end.gd`, `cargo test -p iaf-tools --lib loadout pilot_log`.
- **Weapon physics (2026-11-14, the physics finish list W rows):** the gun's rounds fly a ballistic path (muzzle
  velocity plus the jet's, the M56's drag by air density, gravity) and the EEGS funnel predicts it (W2,
  [weapons.md](weapons.md) §1); the unguided bombs fall by gravity and their own drag through the wind, nothing
  steering them, and CCIP predicts that fall (W5, W6); the GPS bombs miss by their published CEP (W11); a drop tank's own empty weight loads the jet until it is
  jettisoned (370 gal 443 lb sourced, 600 gal 611 lb inferred; F27). Shared with the original game's Weapon data Real.
- **Release limits, jettisons, bay doors (2026-11-15, W17, W18, W22):** a bomb leaves only at 600 KCAS or less and in
  a dive of 60° or less; Shift+C is the F-16's emergency jettison (every store and rack but the A-A missiles and the pods in one
  press, unarmed, the tanks' fuel with them); the F-16 SMS's S-J and Space jettison the selected store with its racks;
  the F-35I's bay doors open in 0.47 s, shut 0.5 s after the release and add drag while open
  ([../../docs/real-weapons.md](../../docs/real-weapons.md) §1.11). Shared with the original game's Weapon data Real.
  Test: `test_sim_jettison.gd`.
- **Bombs, missiles and the gun in every flight (2026-11-14, the user: "the fact that you can drop weapons"):** on
  the Sufa, the Barak and the F-35I the stores hung on the Loadout screen fly with the mission; after the
  take-off's pass the flight goes on, and Shift+A, `[` and Space release the bombs (the HUD's CCIP cue; the F-35I's
  bay doors open by themselves), which fall and burst on the terrain; `]` and Space launch a missile, Tab fires the
  gun ([weapons.md](weapons.md) §5). The notebook's WEAPONS tab (key H) lists the steps per jet with their switches
  and keys; the SMS pages show the stores, the counts and the master arm. Tests: `test_weapons_flight.gd`; pictures: `_weapons_shot.gd`, flown from the front end.
- **Flight data and settings files (2026-11-14, the front-end finish list's D1, [front-end.md](front-end.md) §2):**
  the debrief's Export flight data copies the flight's recording (greyed and out of the focus without it); the
  Settings footer's Export / Import settings file write or read a `.cfg` by the sim's rules (Hebrew without its font
  in English, the pilot and the jet kept). The file dialog and these rules are reborn's, moved to
  `shared/util/file_export.gd`, which both games call.
- **First run, Hangar, missing data (2026-11-14, the front-end finish list's F1, [front-end.md](front-end.md) §1, §3,
  §12):** "Preferences" is "Settings" on every screen (the Hangar's button, the title, the crumbs, the pause menu);
  Attributions in Hebrew "קרדיטים ורישיונות" (the front end and the setup wizard). Create your pilot shows a head and
  shoulders in the empty 3:4 frame, then the typed name's initials, and no pilot in the top bar yet; Up / Down move
  between Name and Nickname, Up from Name to Choose a picture. The Pilot screen's logbook is a panel down to the bottom
  bar. The Hangar's focus order: Settings, the pilot, the jets, Fly, Attributions; Down from Fly stays. Without the
  sim's data the Hangar and Pick a mission say what is missing and the command `./modern-iaf-setup` (Windows
  `.\modern-iaf-setup.ps1`), Fly greyed and out of the focus, and the Hangar tries no model load without the converted
  descriptor (its still picture instead). Missions and campaign stays greyed.
- **The canopy opens and closes (2026-11-14, canopy round 3):** on the Sufa, the Barak and the F-35I the canopy
  stands up 30° at a cold start and comes down over 10 s at its checklist step (shut at once on a hot or airborne
  start), outside and from the seat alike. Each canopy has an opaque frame round the glass painted as the airframe
  and turns about its own hinge (the F-16s' aft, the F-35I's front); the F-35I's control is a yellow lever on the
  left wall, aft of the throttle ([training.md](training.md) §7.1, [cockpit.md](cockpit.md) §5.2,
  [../../docs/f35i.md](../../docs/f35i.md) §4.1, [../../docs/aircraft-models.md](../../docs/aircraft-models.md)).
  Pictures: `_canopy_shot.gd`. The F-16D model is also reborn's "Models: Detailed" F-16, which shows the new frame.
- **The start-up switches both ways (2026-11-13, the switches audit's M2, first part):** on all three jets every
  start-up switch goes back off by its key or a click and on again, with its consequence: main power off darkens
  everything, the starter off stops a crank, the avionics off darken the displays and lose the INS alignment (a
  warm-up and a new alignment when back on), the INS knob off loses it (since 2026-11-15 the knob turns through all
  six positions both ways, by the mouse and its key: STOR HDG 90 s, NORM 8 min, NAV keeps the alignment, ATT loses
  it; cockpit.md §5.2), the canopy opens; the JFS switch springs back to OFF at 52 %. The flight model holds the
  positions (`start.rs` `Start::on`); the checklist, the card and the debrief read them, so a switch back off undoes its step ([cockpit.md](cockpit.md) §5.2 "Both ways";
  `test_switches_both_ways.gd`). Open: the in-between positions (MAIN PWR BATT, JFS START 1, RDR ALT STBY), the
  lamps and cues (M3).
- **Each power switch its own system (2026-11-13, the switches audit's M2b):** on the Sufa and the Barak the
  generators give the displays' power, and each AVIONIC POWER and SNSR PWR switch powers its own system after a 3 s
  warm-up: MMC the HUD, ST STA store release, MFD the MFDs, UFC the DED, FCR the radar, RDR ALT the HUD's radar
  altitude; the INS needs main power only. Each has its own command (219); Ctrl+A throws the four AVIONIC POWER
  switches, and since 2026-11-17 the FCR and RDR ALT on with them (a keyed start had left the radar held at STBY and
  the HUD without the break X's radar altitude; `test_sim_radar.gd`); after a start by clicks the key powers the FCR
  too, and the switches work after a lesson's pass (`test_radar_cold.gd`); the avionics step is the four on
  ([cockpit.md](cockpit.md) §5.2 "One by one"; `test_switches_both_ways.gd`).
  Open: the real consequences beyond the switches' names (sources), the CARA ALOW and GAAF voices without RDR ALT.
- **The jet's checklist card (2026-11-17):** one real checklist per jet in every mission, the notebook's CHECKLIST tab:
  the F-16s' after the real F-16C/D normal procedures (67 items, 49 checked by the sim, 18 read and acknowledged), the
  F-35I's from the public start flow and inferred (38 items, 26 and 12); each checked item ticks from the cockpit's
  state, the current one ringed in a lesson; the start-up lessons ask for its items through BEFORE TAXI; LEFT HDPT and
  RIGHT HDPT power the chin pods ([training.md](training.md) §12; `test_checklist_card.gd`). Since 2026-11-18: the
  F-35I's card holds the items a public US Air Force instruction requires (the survival kit switch, loose items, the
  helmet display's preflight, the ops check, the "gear down" report, the post-flight walk-around, the taxi speeds and
  the fuel calls); both cards name each control as its panel does and state the reaction the cockpit shows; BEFORE
  LANDING opens on the approach (it never did: the rule read a height above the ground the flight's state does not
  hold); `test_card_landing.gd` flies the card home to a cold jet. Open: the systems behind the read-and-acknowledge
  items (oxygen, IFF, trim, the ejection seat's lever, the speedbrakes' check); the autopilot's landing circuit with
  the 6-DoF jets (NAV to a landing waypoint slowed the Sufa to 151 kt at idle with the gear up and sank it into the
  ground at "landing step 5", 2026-11-18, laptop, headless; Modern IAF's missions have no landing waypoint).
- **Every checklist switch by the mouse (2026-11-13, the switches audit's M1):** the throttle takes no mouse since
  2026-11-15 (the user: "shouldn't be able to move the throttle or stick from the mouse"; it took the wheel and drags);
  the landing gear handles (both F-16s, the F-35I) send the G key's
  toggle; the F-16's FCR and RDR ALT switches (FlightGear's own `fcr-switch` / `rdr-alt-switch`, now nodes of `f16.glb`) move on a click
  and power the radar and the radar altimeter since M2b ([cockpit.md](cockpit.md) §5.2). `test_switches_click.gd` checks every switch of each jet's
  start-up, take-off and landing steps resolves to a clickable part, lights and sends its command. The F-35I's
  CANOPY control is a lever on the left wall since 2026-11-14 (the canopy entry above).
- **The pointer comes back after a mouse look (2026-11-13, the user's Mac):** the right drag hides the pointer while
  held; on release, a release the view missed, a lost focus or a pause it shows again where it was
  ([cockpit.md](cockpit.md) §2). `test_sim_look.gd` checks it.
- **The right glove holds the stick (2026-11-13, the user):** looking down in the F-16s the right glove wraps the
  side-stick's grip (it hung 9 cm ahead of it) and the left palm sits on the throttle's head (it lay on the console
  beside it), its fingers closed on the grip (they spread onto the panel beside it), cold and in flight
  ([cockpit.md](cockpit.md) §5.3). `test_cockpit_view.gd` checks both hands.
- **No mission card (2026-11-13, the user):** a flight starts with nothing over it, the flight running; the in-flight
  mission card and its H key are gone (record 118 and H are the Checklist notebook's since). No key hint over the
  flight since 2026-11-15 (the Esc line removed; [front-end.md](front-end.md) §8); only the notebook's help line in
  the pilot's first start-up mission. The goals are in the briefing, the live "To
  complete" line, the completion message and the debrief. `test_flight_ui.gd` checks it.
- **Reborn's code reused (2026-11-14, the reuse audit's R1–R3):** the mission page preloads the ground and models
  with reborn's `TerrainPreload` ([front-end.md](front-end.md) §7); the briefing map's wheel zoom and the notebook's
  wheel take `Settings.zoom_steps` / `wheel_steps`; the Settings' shared rows take their choices and greying from
  `shared/util/pref_choices.gd` (MetalFX named on a Mac).
- **The pilot's checklist notebook, part 1 (2026-11-13, the approved mock-up's look A):** in every flight a paper
  notebook on the right thigh; H raises it at the screen's lower right and stows it. Tabs START-UP, TAXI / T-O, RADIO,
  LANDING, EMERGENCY, DATA; a tab click, the wheel or a trackpad's scroll (`Settings.wheel_steps`, as reborn's
  text windows, 2026-11-14), PgUp / PgDn and the page's own ‹ › with its page count turn it. No
  key hints on it; a help line in the first start-up mission only. It replaces the start-up card: the steps whose
  switches are on ticked (a switch back off unticks its step), the step to take now marked. In a start-up training
  mission an outline of the current step's switch's own shape (and of the F-16's RPM dial for the idle step), a pointer
  at the screen's edge for a part out of view, the board sliding off an outline it would cover. English and Hebrew (mirrored). RADIO's
  frequencies: OurAirports' where published, the rest invented ([training.md](training.md) §11). `test_notebook.gd`.
  Open: the GUIDE tab and the front end's Guides screen (part 2); the throttle OFF, the brakes and the ejection handle
  by the mouse.
- **The F-16's approach speed matches the manual (2026-11-11):** TP-1538's speed-brake tables gave the open speed
  brake lift (+0.25 CL at 13° α); the 6-DoF flies the JSBSim model's speed-brake drag instead, and its flaps' lift
  (+0.122). The 13° α approach is 136–139 kt at the manual's three weights (manual 139–141 kt, was 118–121 kt)
  ([flight-model.md](flight-model.md) §9.17). Since 2026-11-15 the F-16s' speed brake stops at 43° with the main gear down
  (T.O. 1F-16A-1); the Adir's surfaces have no such limit (inferred).
- **The Adir's own flight figures (2026-11-16, finish list F23):** one F-35I set (`data_set::F35I`) that the 6-DoF
  and the original game's F-35I both read: the control law's 50° α limit (Lockheed Martin; a full pull at 150–400 kt
  peaks at 51–52° and holds 50°, a full push recovers in under 6 s), +9 g, the F-16's roll (inferred), a nose-down
  moment at high α and an α-rate lead in the limiter (both inferred), the approach at 152 KCAS and 13° α (USAF
  accident report) and a 134 kt 1 g stall (inferred; 128 kt measured) asserted ([flight-model.md](flight-model.md)
  §9.19, [../../docs/f35i.md](../../docs/f35i.md) §2.1). Open: the F-35's roll rate, sustained turn condition and
  climb.
- **The trailing-edge flaps droop with the gear handle (2026-11-11):** on the 6-DoF the F-16s' and the Adir's
  flaperons go 20° down with the gear handle below 240 kt, less to 370 kt, and up with the handle, in the gear's 3.1 s
  (the F-16 flight manual); their lift, drag and nose-down moment are inferred (DATCOM, FM-0's drag); the models'
  flaperons droop with them ([flight-model.md](flight-model.md) §9.16).
- **The cockpit zoom one way per scroll; every jet's view alike (2026-11-11, the Mac play test's P1):** each wheel or
  trackpad step narrows the view (the true size kept between the wide and the narrow view; a step against the scroll
  dropped until it pauses), clamped at both ends; the trackpad zooms too. The Barak, the Sufa and the F-35I open at the
  same wide view, the F-16s at the same eye ([cockpit.md](cockpit.md) §2). Home's Pilot log entry removed: the pilot
  block → the Pilot screen's Pilot log button ([front-end.md](front-end.md) §3). `test_cockpit_view.gd`,
  `test_front_end.gd`. Open: the Barak's view looked closer on the Mac; at default settings both jets render the same
  view (only the HUDs differ: the Barak's Block 50 frame against the Sufa's wide-angle glass).
- **Mouse look in the cockpit (2026-11-11, the Mac play test's finding 9):** hold the right button and move the mouse
  to turn the head, double right-click to centre it; the wheel zooms from the wide view through the true size to a
  narrow 20° view for reading the MFDs. The left button stays on the switches. No head lean with the mouse
  ([cockpit.md](cockpit.md) §2). `test_sim_look.gd`.
- **The HUD stays on its glass (2026-11-11, the Mac play test's finding 10):** looking down or aside at the dash the
  HUD's symbols stay on the combiner glass while any of it is on the screen; the DASH takes over only once the glass
  is out of view ([cockpit.md](cockpit.md) §4, docs/cockpit.md "3D cockpit").
- **The F-16s' canopy by its key (2026-11-18, the user: "remove the f16 cockpit handle. It isn't right for sure"):**
  the grey rod drawn on the left canopy sill since 2026-11-11 is removed with its click area; Ctrl+K closes and opens
  the canopy, and the notebook's canopy line points to the Canopy key on the Keys screen ([cockpit.md](cockpit.md)
  §5.2).
- **The hands on the stick and the throttle (2026-11-11, the Mac play test's finding 12):** the left glove holds the
  throttle's grip and follows it over its travel (two shape keys in `f16_pilot.glb`); the right glove holds the stick
  ([cockpit.md](cockpit.md) §5.3).
- **The start-up checklist card, one step at a time (2026-11-11, the Mac play test):** a start-up flight opens with the
  checklist card only; the card is smaller and shows the step to take now with its key, place and wait, and its number
  of the steps ([training.md](training.md) §7.1). Replaced by the pilot's notebook on 2026-11-13
  ([training.md](training.md) §11).
- **The radio lines at subtitle size (2026-11-11, the Mac play test):** 20 px at 1080, was 26
  ([front-end.md](front-end.md) §8). `test_flight_ui.gd`.
- **The F12 info line: the mission and the FPS (2026-11-11, the Mac play test):** the sim's line leaves out the 1998
  game's modes, place, speed and controls (`Settings.info_line_full`, [front-end.md](front-end.md) §8).
  `test_flight_ui.gd`.
- **The black world with TAA or Upscaling (2026-11-12):** with Anti-aliasing TAA, or Upscaling Quality / Balanced,
  the 3D cockpit's own picture lost its alpha and laid black over the whole world (reproduced on Linux, Iris Xe, with
  the player's settings; each of TAA alone, FSR 1 alone and FSR 2 did it). The cockpit's picture is now drawn at full
  size with MSAA 4× whenever the flight uses TAA or an upscaler ([cockpit.md](cockpit.md)).
- **Finding the Mac's black world (2026-11-11):** a flight's start on the Mac ended in a black world under a fine 3D
  cockpit. A bisect switch now turns graphics features off for one run (`IAF_SAFE=all ./start-modern-iaf`, then half
  the names back on per run); after the first 10 frames the log lists every shader in use and whether it compiled,
  and a failed one opens the crash page; the start watch covers those frames too, and a pause no longer counts as a
  hang (a 30 s frame only logs `hang:`: a Mac's first start can compile shaders that long in one frame) ([front-end.md](front-end.md) §11.1). Fixed on suspicion, not yet seen on a Mac:
  the Levant sky's `acos` of a direction a hair over 1 gave NaN, which Metal carries into the radiance map, the fog
  and the ambient light (`atmosphere.gdshader`, also `normalize` of a zero vector looking straight down and two
  reversed `smoothstep` edges; the same `acos` in `cloud_layer.gd`, an `exp` overflow in `city_glow.gdshaderinc`); and
  the cockpit's picture no longer goes through MetalFX, whose output need not keep its alpha (an opaque cockpit
  picture would lay black over the world; `cockpit_origin.gd`). Open: the Mac's log with these.
- **A flight's start: no hang, faster, watched (2026-11-10, the Mac's P1 finding):** the mission card opened at the
  start under the loading screen and froze the flight, so the loading never ended on a player's machine (every
  scripted run skipped the card); the card is gone since 2026-11-13. The jet, the 3D cockpit and the pilot's body parse on
  worker threads from the start; the jet, the cockpit and the weapons are each drawn first in their own frame, named
  on the bar. Ramon's take-off from the flight scene: first start (no shader cache) 18.1 s, was 26–48 s; warm 4.4 s,
  was 5.1 s ([front-end.md](front-end.md) §7). A watchdog opens the crash page (§11) when the loading stops; every log
  line starts with its time ([../../docs/logs.md](../../docs/logs.md) §2). `test_start_watch.gd`.
- **The folder `modern-iaf/` (2026-11-10, [plan.md](plan.md#decisions-of-10-november-2026)):** the code folder was `iaf-2026/`; the game
  launcher is `./start-modern-iaf` (+ `.ps1`). Built data in `assets/converted/iaf-2026` moves to `converted/modern-iaf` on the
  first run of a launcher, the wizard or `iaf-sim` ([setup.md](setup.md)).
- **[D3](plan.md#d3-f-15c-baz-at-tel-nof), the F-15C Baz's data and Tel Nof (2026-11-09):** the Baz's unit record
  (`data/db/units/f15c.json`) compiles into the sim's bdb, and Tel Nof (LLEK, from OpenStreetMap and OurAirports) is
  the fifth base `iaf-sim airbases` compiles, with a Baz parking spot and a paved taxi path to 33L
  ([airbases.md](airbases.md)). `sim::tests::every_data_file_compiles_and_loads`,
  `sim_bases::tests::the_departure_is_paved`.
- **Compact JSON (2026-11-09, [plan.md](plan.md#rules-the-user-3-november-2026) rules):** every JSON file the
  sim writes is on one line ([data-formats.md](data-formats.md) §7).
- **The cockpit sound model (2026-11-09, Approvals A13, branch `wt/iaf-2026-cockpit-sound`, waits for the user's
  listening):** from the cockpit the outside sounds (engine, airframe, weapons, the world) come through the canopy and
  the HGU-55/P's ear cups: a 166 Hz low-pass and a level per class; the radio, Betty and the tones are unchanged; the
  external views hear everything unmuffled. The gun comes through the structure (a 700 Hz low-pass) and sits 5 dB
  over the engine and the wind, as in a cockpit recording (it was 6 dB, unfiltered). The wind stops at its row's level from 450 kt ([sound.md](sound.md) §1.9). The original
  game keeps its buses. `test_mvp.gd`, the original's `test_sounds.gd`.
- **The core sounds against real references (2026-11-09, Approvals A12, branch `wt/iaf-2026-core-sound`):** the
  dry engine plays its idle recording at its own pitch at idle (it was 4.2 semitones up) and rises to 1.3 and 6 dB at
  military; the start plays a JFS whine (its partials measured on an F-16 start), the engine's pitch and level by its
  RPM, a light-off thump and the JFS winding down at the generators; the gun buzzes at 100 rounds a second (it was
  48); the wind follows the dynamic pressure; the canopy closes at its checklist step; the touchdown is an airplane
  tyre skid with a thump, not a bicycle squeal ([sound.md](sound.md) §1.3–§1.8). The original game keeps its rules.
  `test_mvp.gd`, the original's `test_sounds.gd`.
- **The ground as the original game's (2026-11-13, the user's order):** the sim renders the ground with the
  original game's values (one set of terrain shader globals in both projects; Sky Atmospheric, Colour grading
  Original): no gold tint, no detail gain, no Levant haze; the Judean hills' gold speckle is gone. Its 2 m photo is
  levelled per sheet as the original game's (no match to Sentinel-2), its 4 m and 8 m levels built from it, its grey
  hills warmed as that layer's: the ground reads as the original game's photo. A rebuild of the theatre's photo
  (setup's terrain step "will run", nothing to download). Pictures in [terrain.md](terrain.md) §15.
- **Steady taxi lines (2026-11-15, the user: "the yellow marks on taxi way show strange if even a bit far"):** the
  yellow taxiway centreline is one thin line from the cockpit at every distance, fading with it, from the air too;
  before, it broke into dashes and blobs and vanished along the view (the shared shader's line read from a 2 m
  distance field, [rendering.md](../../docs/rendering.md) §7). The original game's Detailed airbases get the same fix.
- **Signs and taxi routes to the runway's start (2026-11-15, awaiting the user's yes on the pictures; the user: "ab
  signs should lead to runway start only, not to the middle of the runway, it's confusing"):** a direction sign's board
  leads only to a runway's start (a way may cross a runway on its way there); a mid-field intersection keeps its
  holding sign with both ends, and no board leads there. The departure the briefing draws and the tower clears keeps
  to the taxiways to the start instead of back-taxiing on the runway (Ramon, Ramat David, Tel Nof), so it agrees with
  the signs. Since 2026-11-16 every sign a departure to any runway end passes names that end with the route's turn
  (Ramon's way to 25R read "25L" alone; now "25L 25R" on the shared parallel taxiway). A rebuild of the airbases step (nothing to download) ([airbases.md](airbases.md) §9,
  [data-formats.md](data-formats.md) §12).
- **The borders (2026-11-15, approved 2026-11-17: "A52 approved"; the user: "the change between israel and other
  country looks bad"):** Sentinel-2 beyond the photo's edge (Lebanon, Syria, Jordan, Egypt, Gaza) toned to the
  photo's colour and brightness along the border, fading out over 10 km, with the bases' colour map per 16 km block
  ([terrain.md](terrain.md) §4). A rebuild of the theatre's border units (setup's terrain step, then the scenery:
  nothing to download). Open: Sentinel-2 stays softer (10 m) than the photo (2 m) beside it; along the Egyptian border
  stepped block edges and a lighter outlined patch; on a theatre built before, the border units over 10 m tiles not kept on disk
  stay untoned (nothing is fetched for them).
- **The airbases from the air (2026-11-14, built, awaiting the user's yes on the pictures):** the bases' Sentinel-2
  fill toned to the photo around (no tan block; one colour map per base from the medians of the ground around, an odd
  Survey sheet left out, Sentinel-2's brighter dry grass brought down to the earth tones around); the painted
  runways, taxiways and aprons out to 28 km, kept at their paved share far away, their asphalt darker so they read
  on that ground. A rebuild of the theatre's base units (setup's terrain step, then the scenery: nothing to
  download) ([terrain.md](terrain.md) §4, [airbases.md](airbases.md) §9). Open: the bases stay softer than the 2 m
  photo (10 m pixels).
  `test_sim_look.gd`, the original's `test_terrain.gd`.
- **Towns in the air photo's colours, the roads to the buildings' range (2026-11-13, look study A20):** each roof in
  its own colour from the air photo with solar heaters, the walls in the palette's colours chosen by the photo around
  each building, ribbon windows, a sun / shade step, grey city pavement (moot since the gold tint went), and every road drawn
  as dark asphalt to 5.5 km (was 1.5 km). Needs the scenery step again (no download) ([scenery.md](scenery.md) §7).
  Open: Scenery Detailed keeps its own near roofs; far shadows and contact shading (the grounding round).
- **The ground against a photo of Makhtesh Ramon (2026-11-11, Approvals A17, causes 1 and 2; dropped 2026-11-13,
  [terrain.md](terrain.md) §15.1):** a golden tint
  on the land at every hour, through Colour grading Natural (the albedo × `terrain_grade_tint` 0.86 / 0.78 / 0.43; the
  sea, inland water and the airbases' pavement keep their colour), and the photo's detail ×4.5 (it was ×2.5). The Ramon view's ground reads
  150 / 118 / 66 against the photo's 149 / 118 / 63 (it was 160 / 134 / 105); its spread 18.4 within the photo's 23.4.
  No GPU cost. Pictures and numbers in [terrain.md](terrain.md) §15.1. `test_sim_look.gd`, the original's
  `test_terrain.gd`.
- **[B4](plan.md#b4-ground-look-parity), the ground as good as the original game's (2026-11-09):** the pale,
  washed-out desert (sand 208 / 192 / 171) now reads tan with its relief (177 / 152 / 120): Colour grading Natural
  takes the photo toward a real ground's reflectance, with a little contrast and saturation after the tone mapper
  (docs/rendering.md §1.9). The close up's patches are back in tone only, the ground textures hold farther out by the
  photo's land cover, a macro tint breaks the photo's repeats, and the sim's setup fetches the ambientCG textures
  itself. Pictures beside the original game's in [terrain.md](terrain.md) §9.1. `test_sim_look.gd`, the original's
  `test_terrain.gd` (its picture unchanged with the rows off).
- **The afterburner sounds like an F-16's (2026-11-09, the Mac play test's finding 27):** measured against an F-16
  hush-house run and take-offs, the burner now rises over 1.5 s with a low thump at light-off, dies away over 1.3 s
  at the cut, sits 6 dB over the dry engine, and is a real RNLAF F-16's roar with no pulse and no pitch shift
  ([sound.md](sound.md) §1.2). The original game keeps its rule. `test_mvp.gd`, the original's `test_sounds.gd`.
- **[B3](plan.md#b3-scenery-roads-and-inland-water), the sea and the shore's ground (2026-11-08):** the sea is one
  surface: Sentinel-2's from the beach out, with no Survey photo (its white no-data patch, its lighter blocks) beyond
  the coastline, and the open sea's fill in the composite's own tone, so its edge no longer shows as steps
  ([terrain.md](terrain.md) §3, §12). Near the camera the ground keeps the close up's grain and relief without its
  colour patches, which had speckled the pale desert orange ([terrain.md](terrain.md) §13). Pictures before and after
  in [scenery.md](scenery.md) §7. `sim_terrain::tests::the_shore_follows_the_coastline`.
- **[B2b](plan.md#b2-the-airbases) / [B3](plan.md#b3-scenery-roads-and-inland-water), the bases' ground and the shore (2026-11-08):** the taxiways and aprons
  are paved for the flight model (no rough-ground crash taxiing out), taxiway signs at the holding points and
  junctions ([airbases.md](airbases.md) §9), the sea follows OpenStreetMap's coastline in the photo and the surface
  flags ([terrain.md](terrain.md) §12), the airbases step downloads the extracts its water needs, and the wizard has
  an optional scenery step ([setup.md](setup.md) §3).
- **The gun (2026-11-08, the Mac play test):** the rounds are the unit record's (Sufa and Barak 511, F-35I 180) and
  run out; our own muzzle flash and tracers; every flight starts with the master arm safe, Shift+A arms
  ([weapons.md](weapons.md)). `test_sim_gun.gd`.
- **The Mac play test's findings (2026-11-08, [plan.md](plan.md#f-the-probe) F):** the mission card (removed 2026-11-13), the radio lines
  in the sim's band wholly in the game's language; the pause menu centred at any size in Hebrew;
  Preferences without an aid or realism row and the aids off; Home on every start;
  clickable breadcrumbs ([front-end.md](front-end.md) §1, §8). `test_flight_ui.gd`, `test_front_end.gd`.
- **Keys and Joystick (P1, 2026-11-08, the Mac run's "keys / joystick mapping"):** Settings → Devices opens a
  Keys screen (every command the sim has, by group; click and press to rebind, Cmd on macOS, conflicts with Swap /
  Use it here, Default, Reset all) and a Joystick screen (the devices, each axis' role with a live bar, Invert and a
  dead zone, the buttons and hat bound by pressing them, Reset all), in English and Hebrew. The keys and
  buttons are `Settings.key_bindings`, the store reborn uses too (2026-11-14; an older `devices.json`'s move there once);
  the axes are in `user://devices.json`, read and written by Rust (`IafDevices`). The Thrustmaster Hotas X has its own default map (`modern-iaf/data/devices/`), and a joystick connecting no
  longer asks for the install's `menu/joy` ([front-end.md](front-end.md) §9). On macOS the keys start from the
  laptop map, no numpad: the rudder on Z / X, the snap views on Alt + 1–9 (§9.1). `test_devices.gd`, the M0 probe
  with a fake joystick.
- **The Mac findings batch, devices and front end (P1, 2026-11-11, [front-end.md](front-end.md) §1, §2, §9):** the
  Joystick screen's bars show each role as the flight reads it (`Joystick.role_value`, one sense for the poller and the
  bars): the throttle forward is a full bar, checked against the 1998 game's events axis by axis (`test_devices.gd`);
  the afterburner detent on Settings → Devices (reborn's Detent = MIL rule, `Joystick.detent_choice`); the hat is
  reborn's POV again (the sim's own four hat buttons dropped the diagonals), its eight directions the snap views; the Keys and Joystick side lists follow the scroll and both
  screens have Back; one head-look key set (the snap views; F2 rear view and the Shift free look are empty slots);
  on macOS the keys say ⌘ and Option; Home has Guides and Training has Missions and campaign, both greyed with
  "Coming in a later version"; Pick a plane picks on a click (no Next, no card picked on entry, the arrows move the
  focus, Enter picks).
- **The play test's polish (2026-11-09):** the Preferences back to the side layout (the sections listed, the picked
  one beside them, no line under an option); a Sound slider plays a sample of its class; Devices → Joystick greyed
  until a stick is plugged in; the Pilot screen (name, nickname shown on every screen, a 3:4 ID photo; records schema
  version 2); the loading bar follows the flight's real loading steps, named under it; the throttle up from OFF is the
  start-up's idle step (Ctrl+I gone); no drag-chute warning per flight ([front-end.md](front-end.md) §1, §4, §7, §9.2;
  [training.md](training.md) §7.1). `test_front_end.gd`, `test_devices.gd`, `test_mvp.gd`, the pilot_log unit tests.
- **The Pilot screen's findings (2026-11-10):** the nickname field editable (a hint in place of the name); Save and
  Back (a discard prompt); the picture opens the file picker; Reset the log after a warning and a second confirm;
  several pilots (a list, New pilot, the active one in `settings.cfg`); the first start makes the profile before Home;
  the logbook per plane on the Pilot screen, Home with the name and nickname only (records schema version 3, the
  sortie's plane) ([front-end.md](front-end.md) §1, §3; [storage.md](storage.md) §5). `test_front_end.gd`, the
  pilot_log unit tests.
- **Home's pilot block and Delete profile (2026-11-10):** Home's nickname, name and picture are one button to the
  Pilot screen; the Pilot screen keeps only the fields' labels and hints; Delete profile removes the pilot, its log
  and its picture after two confirms ([front-end.md](front-end.md) §1, §3). `test_front_end.gd`, the pilot_log unit
  tests.
- **The engine shutdown (2026-11-11):** Throttle OFF (Shift+1) cuts the fuel: the RPM winds down over about a minute,
  the generators drop at 52 % with the displays, the HUD and the avionics, the FTIT falls, the engine loop pitches
  down and fades; the recording's `checklist` step `cutoff` with fault `shutdown` / `no_start` fails a training
  mission; the JFS below 20 % and the throttle up from OFF restart it ([training.md](training.md) §7.2). `test_mvp.gd`
  (shutdown), the start.rs and training.rs unit tests. Open: the EPU and windmilling in the air.
- **The HUD's light (2026-11-09, Approvals A10):** the F-16s' HUD in the P43 green, drawn over the scene, bright by day
  and dimmed to a night floor as the sun sets, with a faint halo, the original's thin pen and the combiner glass
  untinted (2026-11-13; a quarter of 14 % before); the 3D cockpit's SYM wheel sets the day level (hover, wheel, drag; kept in the settings file) and Shift + H steps
  it, on the general clickable-control layer `cockpit3d_controls.gd` ([cockpit.md](cockpit.md) §5.1). The F-35I's HMD
  BRT knob turns the same level, its MFD BRT knob the displays' brightness (kept in the settings file too); the F-35I's
  helmet display lights as the HUD does, in P43 at that level. `test_hud.gd`, `test_mvp.gd` `_knob`. The F-16s' DAY / AUTO BRT / NIGHT switch on the right console (2026-11-11):
  clicked or scrolled, DAY keeps the day level at night, NIGHT the night floor by day, AUTO follows the sun; kept in
  the settings file (`test_mvp.gd` `_hud_mode`).
- **The HUD on a 2× display (2026-11-11, the Mac play test):** the HUD keeps its angular size, stroke and text crispness
  at every display scale: the pen's least width and the texts' raster size are physical pixels
  ([real-hud.md](../../docs/real-hud.md#modern-iafs-hud-light) "Display scale"; the rule holds in both games). The
  stroke is the original game's thin pen (0.87 mrad), the halo 0.73 mrad outside it and at least one pixel (an angle
  since 2026-11-13: one pixel at every size before), and the HUD is drawn over the scene instead of
  added (no white core over the sky), so it reads as crisp as the original game's Real HUD. The Mac's pictures matched Linux at scale 1: its "closer view" and
  "twice the size" came from an enlarged crop, and the glass is untinted. The side edge strips beside the
  HUD are removed (2026-11-12). The AoA indexer and AR / NWS bodies beside the posts' feet take the glareshield's
  paint (they drew flat black) and stand 2.5 cm outboard of them, clear of the posts as in the F-16C photo
  (2026-11-13). Their lamps are seen whole from the eye (their hoods aim at it), glow bright enough to read by day and stay
  dark when off (2026-11-16,
  [cockpit.md](../../docs/cockpit.md) "3D cockpit" lamps). The combiner plate is fitted inside the curved posts.
  A 1× monitor beside a Retina screen (the user's Dell): Godot renders it at twice its pixels and the system halves the
  picture. The 14 Nov switch to the monitor's own pixels (hiDPI off) was reverted on 15 Nov at the user's word: with
  Upscaling Quality the cockpit came out soft there. Open again: the HUD's thin stroke on that monitor, two half-lit
  pixels (real-hud.md "A 1× monitor beside a Retina screen").
- **The start-up lesson's lines and waits (2026-11-17, the user: "it needs 2 clicks. the checklist isn't clear
  enough", "I also see align on the hud but no idea how to do that", "it takes to long after finishing the startup to
  get the mission accomplished screen"):** each line says the position and the clicks, the waits say WAIT, the
  notebook and the ring say what the current step still misses, the INS step goes on to NAV after the alignment, the
  alignment's 90 s wait is the INS step with a countdown (it was a silent wait after the last step) and the pass comes
  within a second of NAV, and the take-off lessons ring the start-up's
  switches ([training.md](training.md) §7.1). The radio menu marks no call ("(next)" removed). `test_lesson_steps.gd`.
- **One click sound a click (2026-11-17, the user: "the clicks on the panel are happens twice for every click I
  think"):** an ICP key's click sounded three times and entered once; every control now sounds once a click
  ([cockpit.md](cockpit.md) §5.2). `test_one_click.gd`.
- **The pilot's body off the switches (2026-11-17, the user: "I am unable to click the main power on the second
  traininig"):** Alt + H hides the body while held, Alt + G for the flight; the first lesson hides it while it covers
  the ringed switch; the body never took the click ([cockpit.md](cockpit.md) §5.3). `test_lesson_clicks.gd`.
- **No white cockpit flashes with Upscaling (2026-11-17, the user: "the cockpit goes white, brighter for a sec when
  it jumps for a sec when starting the first training", "also moving the view doing white flashs"):** the sharp
  layer's exposure grey is solid geometry that holds still, so the Mac's temporal upscaler keeps it whole; the cockpit
  is sharp with Upscaling again (2026-11-18, [cockpit.md](cockpit.md) §6.3). `_cockpit_flash_shot.gd` (real render).
- **One lean control and the full MFD view (2026-11-18, the user: "Ok hud is more important. So have a lean button +
  full MFD view", "Why need lean in arrows and also in other keys?"; approved):** Shift + arrows / Page Up / Page Down
  held lean the head (6 cm aside, 10 cm forward and on to 30 cm, the F-35I 2 cm) and the release brings it back
  (records 126–131, command 204); Shift + , / . show the left / right MFD close up with every push button on the
  screen, the F-35I's panoramic display from either key, and the same key or Esc goes back (records 198 / 199,
  command 207). From the seat the F-16s' two top inboard buttons of each MFD and the right MFD's GAIN rocker stay
  behind the ICP's corners, as in the real jet; the lean and the full view show and click them
  ([cockpit.md](cockpit.md) §2, "The MFDs from the seat"). `test_mfd_buttons_seen.gd`, `test_cockpit_view.gd`.
  Owed: the real-window run of the test on the Mac. The views moved from Shift + N / M to Shift + , / . the same day:
  Shift + N is the night-vision goggles' key (`terrain_view.gd` `_own_key`), and the manuals' build now stops when a
  key `_own_key` reads has no row in `modern-iaf/manuals/own_keys.json`. Open, the user's decision (a visible
  change): the goggles need `Settings.night_vision`, which Modern IAF has no Preferences row for, so Shift + N
  does nothing in the sim yet.
- **Zoom toward the pointer and the lean (2026-11-15, the user's Mac play: "can't zoom in to see things under the
  throttle"):** the wheel zooms the 3D cockpit toward the point under the pointer; Shift + arrows / Page Up / Page Down
  lean the head (records 126–131, command 204; held since 2026-11-18, the entry above) short of the cockpit's surfaces,
  the pilot's body hidden while leaning, so the ELEC panel under the left glove, the consoles and the lower pedestal
  show close up; a switch under the pointer leaves the wheel to the zoom ([cockpit.md](cockpit.md) §2).
  `test_cockpit_view.gd`.
- **The start-up lesson's guidance on every step (2026-11-15, the user: "it never shows the avionics panel to turn it
  on"):** the F-16s' avionics step outlines the AVIONIC POWER switches still off (it showed none); `test_mvp.gd`
  checks on every start-up step of the Sufa, the Barak and the F-35I that the guidance names the step's control, that
  it is outlined on the screen once the head is on it, and that it moves on only as switches are done
  ([training.md](training.md) §11).
- **The NOZ POS needle glides (2026-11-16, the user: "in the right, you have 4 gauges. the second move by the
  throttle, but jump"):** the right eyebrow's second gauge is NOZ POS; each AB stage jumped it 50 % in one frame. The
  nozzle now follows with a 0.8 s lag (`iaf_flight::instruments::NozzleLag`); OIL, RPM and FTIT were already smooth
  (measured per frame). The F-35I has no round engine gauges (its engine page is on the panoramic display).
- **Click areas and the training outline by shape (2026-11-15, the user's Mac play):** a 3D cockpit control's hit area
  is its mesh's own surface (the nearest along the pointer's ray: never bigger than the part, never a neighbour's);
  the training highlight outlines the switch's own shape and the RPM dial as the ellipse it
  shows (it had circled the NOZ POS gauge). Every control of the three jets checked at 1,280 x 720 and 2,560 x 1,440
  (`_click_areas_shot.gd`; [cockpit.md](cockpit.md) §5.1, [training.md](training.md) §11). `test_switches_click.gd`.
- **The start-up switches (2026-11-09):** the F-16s' start-up checklist by the mouse in the 3D cockpit: MAIN PWR, the
  JFS switch, the throttle, the AVIONIC POWER switches, the INS knob (their own nodes of `f16.glb`, each turning to its
  on position), each sending its key's command (the canopy its key alone since 2026-11-18); the card names each switch
  and its
  place ([cockpit.md](cockpit.md) §5.2). The F-35I's the same on its own panels: BATT, IPP, ENG (or START, or the
  throttle) and CANOPY, new nodes of `f35i.glb` at inferred places. `test_mvp.gd` (the Sufa's and the F-35I's
  start-up by clicks). Open: the JFS switch's spring back to OFF, the INS knob mostly hidden by the right sill from
  the eye, the F-35I's ENG guard.
- **AVIONIC POWER switches one by one, the AoA at rest on the ground (2026-11-11, from the user's Mac):** a click
  throws one AVIONIC POWER switch with its click; the four on take the step; MFD powers the MFDs, UFC the DED
  ([cockpit.md](cockpit.md) §5.2). The AoA gauge, indexer and HUD rest at 0° below 60 kt and follow the flow above it
  through a 0.25 s lag (§5.4). `test_mvp.gd`. FCR and RDR ALT: FlightGear's console has both as own parts; clickable since
  2026-11-13.
- **Town labels: dropped from the sim (2026-11-11, the Mac play test):** the sim draws no town names over the view and
  Settings has no "Town labels" row; the sim's profile fixes the switch off. The 1998 game keeps its own (Extras →
  "Town labels", [../../docs/scenery.md](../../docs/scenery.md) §3.5). [scenery.md](scenery.md) §7. `test_sim_look.gd`,
  `test_front_end.gd`.
- **Wall shading and long shadows (2026-11-09, the look study's proposal 5):** the buildings' walls away from the sun
  take less sky light, and Settings → Graphics "Long shadows" (on by default) draws the sun's shadows to 2.5 km with
  the near buildings casting them; +0.5 ms on the Iris Xe ([scenery.md](scenery.md) §7). `test_scenery.gd`. Open: at
  the Shoham pose the change is small (the sun behind the camera), so the reference's shaded street sides are still
  apart.
- **The cockpit holds still (2026-11-09, the Mac play test's finding 25):** far from the flight's start the whole
  cockpit jumped against the eye (32-bit floats: 3.1 mm steps 30 km out, 4.4 mm at 60 km). The sim draws the cockpit
  in its own world about the origin and lays it over the flight's view ([cockpit.md](cockpit.md) §6.2): it no longer
  moves against the eye at any distance; about +4 to +5 ms GPU a frame on the Iris Xe. `test_sim_look.gd`.
- **The ILS bars glide (2026-11-09, the Mac play test's finding 24):** the HUD's ILS lines sit at the exact
  deviation instead of the original's whole-pixel steps, which jumped about 5.5 screen pixels at a time on the 3D
  HUD glass ([real-hud.md](../../docs/real-hud.md#what-ours-draws-status)). `test_mvp.gd` checks all three jets.
- **The F-16s' loadout (2026-11-08, the Mac play test):** the Sufa and the Barak fly with an AIM-9M on the wingtip
  rails and on stations 2 / 8 and 3 / 7 and a 370 US gal tank on each inboard pylon, so the look back shows the stores
  instead of a bare rail and pylons ([data-formats.md](data-formats.md) §3). The Python and AIM-120 records (the
  AIM-9M stands in) and the tank's drag are open.
- **The sim's own look (2026-11-08, the Mac run):** the look switches whose 1998 value draws art the sim does not
  have are fixed to ours in `PROFILE`: Detailed airbases (the runways, taxiways and aprons were missing), the
  atmospheric sky, water, night lights, effects, the conformal ladder; the CC0 ground and model textures when setup
  downloaded them ([airbases.md](airbases.md) §9). `test_sim_look.gd`.
- **[E2](plan.md#e2-the-front-end), the front end (2026-11-08):** `./start-modern-iaf` opens Home; Pick a plane, Training, Pick a mission, Fly,
  the flight, its debrief sheet, the Pilot log, Preferences and Attributions, in English and Hebrew (mirrored), in the
  round-3 look ([front-end.md](front-end.md)). Esc over a flight opens the pause menu. `test_front_end.gd`.
- **The mission briefing, map first (2026-11-14, the approved mock r3_briefing; finish list F2):** the map fills the
  screen and opens on the base and the route, the pins numbered as the text's paragraphs; since 2026-11-15 the text card says what
  you will learn and how to fly it in prose, the keys as bound, scrolled by the wheel, the keys and the gamepad (every
  mission's texts in English and Hebrew, mission data `briefing`); the mission card holds the missions as tabs with
  their pass chips, the facts, the objectives, the Arming summary with Edit, Back, Arming (key A) and Fly; the
  map's chips turn the taxi route, the labels and the photo off and zoom. The whole map's rectangles of other tones are
  the Survey of Israel sheets' own levels (terrain.md §10, Open). From 2026-11-09: one zoomable map (the theatre's
  ground colour, roads, towns, the route, the whole airbase); from 2026-11-15 it zooms and scrolls over the whole theatre,
  its ground tiles, roads and towns loaded for the view (finish list C); Edit on the Arming summary opens the Loadout screen (until 2026-11-14 an Arming page with
  each jet's front view); the subtitles name the tail number and squadron, no wing; the missions' titles are their kinds ([front-end.md](front-end.md) §10, `IafBriefing`). `test_front_end.gd`, `cargo test -p iaf-tools --lib briefing`.
- **The briefing's switch pictures (2026-11-11, awaiting the user's approval):** a start-up's paragraph in the
  briefing's text shows its switch cut from the jet's 3D cockpit with a ring round it and the state to wait for
  (`modern-iaf/data/switches`, `modern-iaf/tests/_switch_crops.gd`; [front-end.md](front-end.md) §10). `test_front_end.gd`.
- **The loadout editor (2026-11-10, awaiting the user's approval; on the Loadout screen since 2026-11-14):** a store
  drags from the stores onto a station, between stations and back; each station takes only what the unit record's `allowed` lists
  (re-sourced per jet, data-formats.md §3; each store its own record with its weight and size), racks (a TER of three
  Mk 82, two GBU-38, four GBU-39) with a "×n" badge that cycles the count, the stores without a model greyed, an
  amber imbalance warning past the F-16's asymmetric moment limit, a refused drop shakes its station; an edit changes
  its own station, and the mirror station too with Mirror on (until 2026-11-15 a drop filled both unless Shift was
  held); the keyboard path (Enter on a station, Enter on a store); the fuel
  and the take-off weight follow, over the maximum it reads red and Fly is off; the loadout is the pilot's per jet in
  the records database and flies with the mission (mass, drag, tanks' fuel, the stores' models), Reset brings back
  the record's ([front-end.md](front-end.md) §10). Since 2026-11-11 the racks' weight rides in flight too (the
  BRU-57/A's 120.2 kg sourced), and since 2026-11-14 every store's and rack's drag index (inferred from its size, none in the F-35I's bays; [flight-model.md](flight-model.md) §9.18), the bombs, guided bombs and tanks hang by their lugs under the
  F-16's pylons, and the Python 5 and SPICE 2000 fly as `modern_weapons.gd` records with their public figures. The
  Delilah is dropped for now (the user, 2026-11-14): no store list offers or carries it, as it needs a powered
  cruise-missile flight class the engine does not have; its record stays. Open: a model of the 600 gal tank (the user, 2026-11-15:
  "no rush"; greyed until then), a Sufa / Barak station chart.
- **Inventory counts:** no public source gives the IAF's store counts; the records list none, so the inventory is
  unlimited. `cargo test -p iaf-tools --lib loadout`, `test_front_end.gd`,
  `test_mvp.gd --only loadout`.
- **The records in SQLite (2026-11-09):** the sorties and their debrief records are in `user://modern-iaf.sqlite`
  (`iaf_tools::pilot_log`, `IafPilotLog`, a schema version and migrations); its first open imports the JSON records
  from before it once and leaves them in place; Home, Training, the Debrief and the Pilot log read it
  ([storage.md](storage.md) §5). `cargo test -p iaf-tools --lib pilot_log`, `test_front_end.gd`, `test_mvp.gd`.
- **[A4](plan.md#a4-the-gate), the gates on the original's converted data and install (2026-11-08):** every path under
  `assets/converted` a shared script reads goes through `Settings.converted()`, every path under the install through
  `Settings.install()`; the sim refuses everything but its own converted data and the M0 probe fails on any refusal
  (0 today). The sim's own loading screen in English and Hebrew ([front-end.md](front-end.md) §7).
  The flight shows no message texts until the sim's own messages. The effects draw the sim's own sprites since
  2026-11-14 (`iaf-sim own`, [weapons.md](weapons.md) §2; before: a soft dot, the afterburner a white shaft): flares as bright
  points with thin smoke trails. Since 2026-11-16 a flare sinks away under the jet and burns 4 s, chaff stops in the
  air behind it, so both show from a chase view behind the jet too (weapons.md §2); the F-35I's dispensers sit on its
  lower aft fuselage. Open: a bomb's hit still draws the shared grey domes.
- **[A3](plan.md#a3-the-setup-wizard), the setup wizard (2026-11-03):** `./modern-iaf-setup` opens the wizard; it builds the terrain,
  the airbases, the units and weapons, the sounds and voices and the training missions as a step graph with stamps (a
  second run is all up to date), in English and Hebrew ([setup.md](setup.md)). Its look is Godot's default theme until
  the user's next round. Since 2026-11-09 Done's **Start the game** opens the front end in the same process
  (Close quits), and Install shows "this step" in the running row and "all steps" from the durations measured on
  earlier runs, or the step count before any run ([setup.md](setup.md) "Time left").
  Since 2026-11-12 every optional step (Buildings, trees and roads; Ground and model textures) has an Include tick
  with its download and disk sizes: a left-out step is neither downloaded nor built, the choice is remembered, and
  unticking a built one offers to remove its data. Each step has its own Run again tick, and a skipped or failed step
  shows its reason (in Hebrew too) with Retry ([setup.md](setup.md) §3). Since 2026-11-13 a required step has no tick
  at all (an older choice file that left one out is ignored for it), and a long "about … left" wraps inside the
  state column instead of pushing the row aside.
- **[B3](plan.md#b3-scenery-roads-and-inland-water), scenery and inland water (2026-11-03):** `iaf-sim scenery` builds the original's buildings, trees, road
  layer and city lights in the sim's UTM theatre from the shared open-data cache ([scenery.md](scenery.md)); the sim
  shows them over its own ground when Scenery is on (Settings → Graphics → "Buildings and trees": Off / On /
  Detailed, On by default, greyed without the step, 2026-11-08); `iaf-sim airbases` flags the Dead Sea, the Sea of
  Galilee, the evaporation pans and the reservoirs as inland water ([terrain.md](terrain.md) §11). Since 2026-11-12
  the sim draws its own road layer (Roads Detailed on by default when the step made it; the probe asked for the
  original game's path before, [scenery.md](scenery.md)).
- **[E3b](plan.md#e3-the-training-missions), the training missions in the game (2026-11-03):** `./start-modern-iaf -- --mission 2011` (… 2032) flies a start-up or
  take-off mission without the front end: parked cold, the start command (Ctrl+E) runs the jet's start sequence on
  the 6-DoF, the screens and the HUD come alive at the real moments; the radio menu (Ctrl+T) asks the base's
  tower for start-up, taxi, line-up and take-off, since 2026-11-13 listing every ground call on the ground (the next one
  marked) and landing in the air, line-up its own call, a call out of order answered "negative, hold position, request
  … first", each subtitle shown as its voice starts; the pilot's own voice makes the call through the helmet chain, then the English TTS tower answers (since 2026-11-12, item A21, [sound.md](sound.md) §5.2); at the end the flight is scored, the
  sortie and its debrief record stored in the records database ([training.md](training.md) §7–§10).
  `modern-iaf/tests/test_mvp.gd` flies both missions for the Sufa, the Barak and the F-35I to a Pass. Since 2026-11-08
  a crash, any damage or the wheels off the pavement fail a mission at once with that reason first; a pass is kept
  and the flight goes on until the player ends it (since 2026-11-13); the debrief sheet shows only the mission's goals
  ([training.md](training.md) §3.0, §4). A pass pauses the flight under "Mission accomplished" with Continue the flight and
  Debrief (since 2026-11-15); a fail shows a banner with its reason, then the flight ends into the debrief; an ejection ends the sortie: silent, outside view, Fail "ejected" (§9). Since 2026-11-13 (the
  user: "missions should fail if I start without tower permissions") a take-off mission fails at once on a phase
  without the tower's clearance (the engine start, leaving the spot, entering the runway, the roll), the tower saying
  so (the start-up missions since 2026-11-15 too: the engine start and leaving the spot, after the start-up call as
  their first step); lined up on another runway end the tower names it and the roll there fails; airborne, the goal still missing
  shows live ("To complete: raise the gear.") ([training.md](training.md) §3.3, §9). The start-up
  mission is the real start by keys: the F-16's six-step checklist and the F-35I's battery, IPP, engine, canopy, on
  a card in both languages; a step out of order has its consequence (a hot start, no power) and fails (§7.1).
- **[B2b](plan.md#b2-the-airbases), the airbases in the game (2026-11-03):** `iaf-sim airbases` compiles Ramon, Ramat David, Hatzerim and
  Nevatim into the theatre: `airbases.json` and paved masks (Detailed airbases), an own `iaf.ibx` and
  `terraintype.dat` ([airbases.md](airbases.md) §9); the missions start on the bases' parking spots; the M0 probe
  parks each jet on its spot, on the ground, at a base the flight model finds.
- **[B1](plan.md#b1-the-terrain), the terrain (2026-11-03):** `iaf-sim terrain` builds the sim's theatre `converted/terrain/israel/` from open
  data (GLO-30, Sentinel-2, the Survey of Israel), UTM 36N at 1:1 ([terrain.md](terrain.md)); the sim streams it
  (`theatre_dir()`); the M0 probe flies 5 s over it and checks the heights.
  Every download is shared with the original game in `assets/source/` (the WorldCover tiles in
  `source/imagery/sentinel2/`, also read by `iaf-imagery sentinel2`; the DEM in `source/dem/`): a complete cache
  builds with no network; the heights and the colour build at the same time ([terrain.md](terrain.md) §1.1, §4).
  Since 2026-11-09 the setup downloads only the 14 WorldCover tiles under the 8 m nodes (8.28 GB, before 21 tiles,
  10.62 GB) and reads the other 7 at 20 m over the network (offline, the build stops and says so); the DEM fetch is the shared `imagery_run::fetch_dem`
  (resumes a `.part`); every download logs its MB every 15 s ([terrain.md](terrain.md) §1, §2, §4).
- **[C2](plan.md#c2-the-6-dof) stage (c), the 6-DoF flies the sim's jets (2026-11-03):** TP-1538's control system (g command, α limiter, roll
  and yaw), `Fm { Original, SixDof }` behind `IafFlight` chosen by `Model = 6dof` in the own data (the original game's
  data never reaches it, tested), fuel burn, Mach effects (inferred), the validation rows on the 6-DoF, a real Sufa
  flight in mission 311 ([flight-model.md](flight-model.md) §9.11–9.14). Since 2026-11-14 it takes reborn's ground
  effect, gusts, stores moment (a tank's with its fuel), the stores' drag difference, the roll trim, the systems damage and the landing limits (with Easy landing and the autopilot's landing) through the same
  functions and calls (`near_ground`, `set_stores_moment`, `trim_roll`, `landing_limits`; [flight-model.md](flight-model.md) §9.12). A release changes the 6-DoF's mass, drag and roll at once (`test_sim_release.gd`).
  Since 2026-11-14 (finish list F2) the Barak and the Sufa roll at the F-16's sourced 240 deg/s with 62 deg/s
  flaperons, the figure reborn's Real F-16 rows read ([flight-model.md](flight-model.md) §9.11, §9.13); open: their
  0 → 90° time, 0.78–0.88 s against ~0.55 s.
- **The 6-DoF's control laws (2026-11-15, finish list F3, F7, F15):** 9 g in about 2 s below the α limiter, the
  STORES CONFIG switch (CAT III α limit and roll), the MANUAL PITCH override with deep
  stall recovery by rocking, `stalled` / `spinning` from the motion ([flight-model.md](flight-model.md) §9.11, §9.13).
  Open: the autopilot's touchdown sinks 4.5–10 m/s, over the 4 m/s landing limit (§9.6).
- **[C2](plan.md#c2-the-6-dof) stage (b), engines, gear, the jets' data (2026-11-03):** TP-1538's engine model scaled to the F110-GE-100,
  F100-PW-229 and F135; a three-strut gear with brakes, steering and a braked stand; the four jets' mass, inertia and
  geometry; tests against the ratings, the spool times, a take-off roll and a stop ([flight-model.md](flight-model.md)
  §9.7–9.10). Since 2026-11-15 the take-off roll meets both F-16A SAC rolls within 10 % (2,201 / 3,623 ft against
  2,380 / 3,725 ft, the rotation at 170 kt, §9.13); the tyres brake at NASA's antiskid figure with a friction circle,
  a 25 kt crosswind take-off and landing roll stay within 4 m of the centreline, the autopilot's taxi turns run on the
  wheels; a touchdown past 10 ft/s damages the gear, gear damage holds the gear, and the gear's 300 KCAS limit comes
  from the aircraft definition ([flight-model.md](flight-model.md) §9.8; docs/damage.md §5.2). Since 2026-11-16 full
  pedal yaws the jet hard at any speed and never tips it (air-spring strut stiffness), centred pedals let the nose
  wheel castor, and the keyboard's rudder keys ramp the pedals over 1 s. Since 2026-11-17 the nose wheel follows
  centred pedals back to straight below 30 kt (a released ground turn stops), the brakes ramp in over 0.5 s and the
  struts damp their extension four times harder: braking dips the nose 1° and it eases back with no rock
  ([flight-model.md](flight-model.md) §9.8). Since 2026-11-18 the sloping ground stays in place between two frames
  and weight on wheels is a compressed strut: the jet leaves the runway once at lift-off (before, the wheels left a
  sloping runway and fell back on it every frame).
- **[C2](plan.md#c2-the-6-dof) stage (a), the 6-DoF's core (2026-11-03):** `crates/iaf-flight/src/sixdof/`: NASA TP-1538's aerodynamic
  tables checked value by value against the scan, appendix B's coefficient build-up, a quaternion rigid body; the
  trim tests match the report's trims and Stevens & Lewis's ([flight-model.md](flight-model.md) §9). Nothing calls
  it yet.
- **[D2](plan.md#d2-units-and-weapons) drafts (2026-11-03), pending the user's decision:** the threat set's 12 units and 10 weapons as readable
  records in `modern-iaf/data/db/drafts/`, every figure sourced; `iaf-sim db` skips them, and a test compiles them as if
  approved ([threat-records.md](threat-records.md)).
- **[A1](plan.md#a1-the-project-skeleton), the project (2026-11-02):** the `modern-iaf/` Godot project with its `shared` link, `sim_settings.gd`, the
  `install_dir()` / `own_dir()` / `keys_file()` calls in the shared code (the original game reads the same files as
  before), the launchers `./start-modern-iaf` and `./modern-iaf-setup` (+ `.ps1`), `tools/test.sh` over `modern-iaf/tests` and
  gdparse on both projects, the M0 probe.
- **Own sources for the flight-model type and the bases (2026-11-03):** the player's jet takes its flight-model type
  from the sim's table (`Settings.fm_section`), not the converted descriptor; `IafBases` reads `own_dir()`'s
  `iaf.ibx`, not the install's ([README.md](../README.md) "How the sim reads its data"). `test_own_sources.gd`.
- **The M0 probe (2026-11-02):** passes the no-install check, the profile, the key and sound tables, and for each jet
  the mission's object database, the aircraft definition, the motion table, the 3D cockpit model and the flight
  model's start from the own `bd.ibx` (item [C1](plan.md#c1-fm-0-data)'s FM-0 data; `NEEDS DATA` without that file). With the terrain built
  ([B1](plan.md#b1-the-terrain), the terrain) it flies 5 s over it and checks the heights. On every flight it makes (the free flight, each jet's start-up) the
  3D-only cockpit check (2026-11-08): the cockpit dir the sim's own, no panel, lamp, HUD glass or ADI art loaded, the
  3D cockpit up ([cockpit.md](cockpit.md)).
- [A2](plan.md#a2-the-iaf-sim-compilers) (the data compilers), [B2a](plan.md#b2-the-airbases) (the airbases' layouts), [E1b](plan.md#e1-cockpit-data-sounds-and-voices) (sounds, voices, keys), [E3a](plan.md#e3-the-training-missions) (the training scoring): see
  their rows in [plan.md](plan.md).
- **[E1a](plan.md#e1-cockpit-data-sounds-and-voices), the HUD and display font (2026-11-08):** Hershey's Roman Simplex stroke font
  on the HUD, the MFDs, the small screens and the F-35I's panoramic display ([cockpit.md](cockpit.md) §5); each jet's
  cockpit by day and at night in [cockpit.md](cockpit.md) §6.
- **The voices (item A5, 2026-11-09, branch wt/iaf-2026-voices, waiting for the user's ear):** every speech clip is
  Kokoro text to speech in American voices, made by `iaf-sim voices` as Ogg: Betty measured against two real
  recordings (pace, pitch, repeat), the tower's calls in one breath, the radio chain with key clicks around each
  call ([sound.md](sound.md) §5).
- The setup wizard's headings use Heebo's weights since 2026-11-08 (the font axis is set by its tag number; a "wght"
  string key had left every weight at the regular).

## Open
- **The manuals** ([manuals.md](manuals.md)): the Typst build, the page design, each manual's outline and one written
  section per jet (Cold start to take-off) wait for the user's approval (18 November 2026); every other section is
  planned in the outlines. The main menu's Manuals entry is not built.
- **Avionics, missiles and bombs (2026-11-17):** the inventory per jet, the gap list and the build order are in
  [avionics-plan.md](avionics-plan.md); the 15 November bugs (radar standby, break X and the HUD against reborn,
  SPICE / GPS targets, the gun flash) are its first slice; the range is slice 1. The briefing's PRE target pick for the
  GPS bombs is built on its own branch and waits for the user's yes; until then a PRE bomb steps to the range's ground
  steerpoint with Shift+K.
- **The process staying alive after Quit on macOS**: reported once, on the user's Mac on 2026-11-15; it did not
  reproduce on Linux (headless or in a hidden real render) and is not being pursued unless it is seen again. The leak
  reported with it is fixed (docs/rendering.md §1.5; `modern-iaf/tests/test_exit.gd`).
- **The canopy, after round 3** (2026-11-14): from the F-35I's seat the frame's sides look wide with the lid open;
  the F-16s' lid opens less far than in photos (30°, FlightGear's value); the frames' colours and sizes are
  estimated from photos. The briefing still shows the F-35I's canopy lever as text, no picture
  (`_switch_crops.gd` `HIDDEN`), from when it sat behind the seat.
- **A first start's shader compilation** (2026-11-10): 14 s of the 18 s first start here; with Metal on a Mac it
  takes about ten times as long. Godot compiles a material's shaders when the material is first drawn. The loading
  steps spread this work over named frames, but a single frame cannot show progress while it compiles. Godot keeps the
  compiled shaders across restarts (`user://shader_cache`, the driver's pipeline cache in `user://vulkan`): the next
  start is the warm 4.4 s. A warm-up in the front end was weighed and not built (2026-11-10). The compilation blocks
  the main thread wherever it runs, so the wait would move from the loading screen to a frozen menu; it would not get
  shorter. What remains open: compiling shaders off the main thread, which needs Godot's export-time shader baking
  (Godot 4.5+, for exported builds only).
- **CI for the sim (2026-11-09):** [ci.md](ci.md) recommends parse-checking `modern-iaf/` in the godot job and adding
  `modern-iaf/tests/` to the sweep; the workflow is unchanged.
- **[D3](plan.md#d3-f-15c-baz-at-tel-nof), the Baz is not flyable:** it has no 3D cockpit and no model of its own,
  so the front end does not offer it and no mission flies it; type 110 flies the F-15I's flight-model row. Tel Nof's
  apron is placed by eye ([airbases.md](airbases.md) §5).
- **The core sounds' open points** ([sound.md](sound.md) §1.3–§1.8): the cockpit's idle-to-military step, the
  wind's real spectrum, the gun's spin-up, a real canopy's run time, the gear and flaps clips against a real F-16, the
  F-35I's own IPP, the tower's key clicks (on `wt/iaf-2026-voices`).
- **The cockpit sound model's open points** ([sound.md](sound.md) §1.9): the canopy's measured transmission loss, the
  helmet in flight, the air-conditioning hiss, the engine and wind levels by ear.
- **The afterburner's open points** ([sound.md](sound.md) §1.2): the light-off delay after the detent, the level in
  the cockpit, FlightGear's F-16 sounds not compared, the F-35I's own burner.
- **Keys and Joystick's open points** ([front-end.md](front-end.md) §9): one joystick flies (the first; a separate
  throttle or pedals as a second device is listed but not read); a joystick plugged in during a flight takes its map's
  buttons at the next flight or when the Settings close; the hat's diagonals press two look commands, the last one
  wins; maps for more sticks than the Hotas X; the Hotas X's button choice is ours, untried on the stick.
- **[B3](plan.md#b3-scenery-roads-and-inland-water)'s open points** ([scenery.md](scenery.md) §9).
- **The scenery over a dense town is over its budget (2026-11-11):** on the Iris Xe at 500 m it takes 14 % of the GPU
  time over Tel Aviv (3.1 ms) and 13 % over Beersheba (2.7 ms), against the 7 % budget; 17 % and 15 % before the
  buildings' colours per vertex and their 250 m tiles, which keep the picture ([scenery.md](scenery.md) §6).
- **The 6-DoF's wave drag is a fit ([C2](plan.md#c2-the-6-dof), the 6-DoF):** fit to each jet's published top speeds, not a sourced table; open: a public
  F-16 drag rise, the flaps' sourced aerodynamics and the approach speed
  ([flight-model.md](flight-model.md) §9.6, §9.16).
- **[E3b](plan.md#e3-the-training-missions)'s open points** ([training.md](training.md) §6): the Hebrew voice (the user), the
  pilot's request voice (sound.md §7).
- **[E2](plan.md#e2-the-front-end)'s open points** ([front-end.md](front-end.md)): a pilot list (the name is the computer's user
  name); the debrief sheet and the pilot log in the original game ([shared.md](shared.md)); the missions'
  own Hebrew briefings in `modern-iaf/data/missions/` still use the masculine imperative (the front end shows its own
  gender-neutral ones).
- **[Floating origin / camera-relative cockpit](plan.md#floating-origin--camera-relative-cockpit)**: open; the 3D
  cockpit's screens hold their depth out to 100 km from the flight's start (the F-35I's depth pull).
- **The airbases' open points** ([airbases.md](airbases.md) §9): the towers of Ramon, Hatzerim and Ramat David (their
  reference points stand in), one taxi hub per base. The temp-root run of item F finds any read of the
  original's data still left.
