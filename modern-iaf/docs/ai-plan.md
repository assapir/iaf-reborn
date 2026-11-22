# Modern IAF AI: allies and enemies, the plan

**Terms:** AAA = anti-aircraft artillery; AWACS = airborne warning and control; BFM = basic fighter manoeuvres (the
dogfight); BVR = beyond visual range; ECM = electronic countermeasures (jamming); EMCON = emission control (a radar on or
off by choice); GCI = ground-controlled intercept; IADS = integrated air defence system (sites that cue each other); ms
= milliseconds; SEAD = suppression of enemy air defences; SAM = surface-to-air missile; 6-DoF = the six-degrees-of-freedom flight model ([flight-model.md](flight-model.md));
"inferred" = our own reasoning; "open" = not decided by the user, or no source found.

19 November 2026. The user held the AI plan session: "lets plan how AI (both allies and enemies) going to work ... (we
have very good models fe and gameplay I think"; "I am not sure how good is the current impl, but I am sure it has been
some progress since 98". This document is the plan only; it changes no code. It holds his decisions (§1), what exists
(§2), the architecture (§3), the shared needs and the work rows in his milestone order (§4–§8), the open questions
(§9) and the rows outside his words (§10).

Discussion is not decision: a point he did not decide is listed in §9 as open, not built.

## 1. The decisions of 19 November 2026

His words in quotes; the orchestrator's reading after each.

1. **AI is the next big thing:** yes (his words above).
2. **Approach:** a new Rust AI, a behaviour tree per role plus a flight / package lead, with the existing autopilot
   loops and combat engine as its hands. The 1998 game keeps its own brain unchanged.
3. **Milestone order:** a four-ship of Sufas that takes off, flies formation, follows commands and lands with the
   player; then the intercept lesson; then one Epic Fury strike.
4. **Enemy flight model:** the 6-DoF for every AI jet, enemies included, from sourced 6-DoF data per enemy type.
5. **The parked rows:** missiles unparked ("ok so finish the missile works"); countermeasure effectiveness and
   electronic attack unparked too ("Unpark both").
6. **Wingman commands:** "radion menu instead of hotkeys": the four-ship set (the flight, the element, each wingman)
   through one radio menu, no new hotkeys.
7. **Dogfight:** a new energy-aware BFM in the Rust AI, with skill levels; planned, not in the four-ship milestone.
8. **SAMs:** the real procedure per site (search then track, launch counts, emission on / off, relocating), then an
   integrated network.
9. **How many AI jets:** "as much as needed? like the player can have 4 in his flight and 2-3 other flights (bravo,
   charlie, etc) even with other kind of planes + enemies". No fixed cap: the plan sizes for the player's four-ship,
   two or three other flights of mixed types and the enemies, measures the ms per jet, and adds far-distance cost
   cuts where needed to hold that on the Iris Xe laptop.
10. **Jammers:** "i think the f16D/I doesn't need a pod but has that in the dorsal thingy they have, check it". The
    Sufa's jammer (Elisra SPS-3000; Elbit ASPS from 2025) is internal, in the dorsal spine
    ([../../docs/f16i.md](../../docs/f16i.md) §8, [research/pods.md](research/pods.md)); no source shows an external
    ECM pod on today's IAF fighters. The Barak: [research/pods.md](research/pods.md) names Elta's EL/L-8240, internal,
    on its third batch; what today's upgraded Barak carries is open.
11. **First combat enemy set:** the smaller set first: one long-range SAM, one short-range SAM, AAA and the MiG-29;
    the rest of the draft list after.
12. **Skill:** reaction time, aim and tactics quality; the same physics for all, none of the 1998 AI's flight-model
    cases (no crash immunity, no stall-free experts).
13. **AWACS / GCI:** a controller who answers requests (picture, bogey dope, declare, vectors) plus an Eitam flying in
    the sky that the enemy can target, from the start ("Plus Eitam in the sky now").
14. **Models:** openly licensed models already on disk first, stand-ins elsewhere; a named list of files, licences
    and sizes goes to him, and each download waits for his word.
15. **Voices:** answered (§9 question 1): Hebrew voices.

## 2. What exists today

The engine's reference for the 1998 AI is [../../docs/ai.md](../../docs/ai.md) (brain, control loops, formations,
take-off and landing, combat, ground defences) and [../../docs/autopilot.md](../../docs/autopilot.md) (the player's
autopilot). In Modern IAF today:

- **Flight model.** The sim's AI jets fly the 6-DoF: the sim's `bd.ibx` sections say `Model = 6dof`, and `Fm::start`
  (`crates/iaf-flight/src/fm.rs`) picks it. Its cost is 4.1 µs per jet per 1/60 s frame against a 20 µs budget
  (flight-model.md §9.13, the test `frame_cost_within_budget`). The data holds four jets (the sim's F-16s and F-35);
  any other type fails to load (flight-model.md §8).
- **The hands.** The control loops in `crates/iaf-flight/src/autopilot.rs` (navigate, take-off, circuit and landing
  with the 6-DoF's own landing laws, close and tactical formation on one leader, the combat manoeuvres), and the combat
  engine in `shared/ai/combat.gd` (air sensor, target pick, lock, missile and gun shots, flares and chaff, SAM and AAA
  fire). Formation, take-off and the manoeuvres were tuned on the 1998 flight model and are not tested on the 6-DoF.
- **The brain.** `shared/ai/brain.gd`, the 1998 rule list run every 2 s; the sim's brains are JSON
  (`modern-iaf/data/db/brains`) with a small vocabulary and no weapon actions.
- **Missiles.** The AIM-9M, AIM-9X, Python 5 and AIM-120 fly the physical missile, for the player and the AI alike
  ([avionics-plan.md](avionics-plan.md) §7.2).
- **Around the AI.** The range's five drones; AWACS contact calls in the AWACS voice and a virtual AWACS sensor
  ([ews.md](ews.md) §6–§7); the data link's picture; four parking spots per unit at each base, the third and fourth for
  a four-ship ([airbases.md](airbases.md)); the radio menu on Ctrl+T, with the tower's calls
  ([training.md](training.md) §8); the briefing's Kidon 1..4 flights, drawn but not flown.
- **Enemy records.** Drafts only, awaiting the user (`modern-iaf/data/db/drafts/`, [threat-records.md](threat-records.md),
  [threats.md](threats.md)).

## 3. The architecture

```
 package lead ── flight lead (Kidon 1, Kidon 2 …) ── per-jet behaviour tree (role) ── hands
 (timing, roles,   (formation slot, element,      (fighter, SAM site, AAA,          autopilot.rs loops,
  push / abort)     sorting, commands, promotion)  controller, AWACS jet)            combat engine, missiles
```

- **A new crate module in Rust** (inferred home: a new crate `iaf-ai`, or a module of `iaf-flight`; decided by the first
  slice's design). Game logic is in Rust; Godot wires the jets and draws them.
- **A behaviour tree per role.** Each AI unit runs the tree of its role: wingman, flight lead, enemy fighter, SAM
  site, AAA, controller, AWACS jet. A tree has fast leaves (formation keeping, BFM, a site's tracking: every frame or
  about 0.1 s, inferred) and slow decisions (tactics, about 1 s, inferred), with the skill's reaction time between a
  cue and the answer (X4).
- **A flight lead and a package lead.** The flight lead holds the formation slots, the element pairs, target sorting
  and the commands from the radio menu, and promotes a new lead when the lead is lost. The package lead holds the
  flights' timing, roles and push / abort.
- **The hands are the existing engine.** The trees steer through the autopilot's loops (`ap_set_mode`, `ap_set_route`,
  `ap_set_leader` through `crates/iaf-godot/src/flight.rs`) and fire through the combat engine and the shared missile
  model. A loop the trees need that does not exist (four-ship slots, rejoin, BFM) is added to `autopilot.rs` and
  serves both games' engine.
- **The 1998 game keeps its own brain.** `brain.gd` and its rule lists stay as they are for the 1998 game; its
  behaviour does not change. Modern IAF's units take the new AI; the sim's JSON brains (the range drones) move to
  it (inferred: one AI per game).
- **Knowledge from sensors.** A unit knows what its radar, its eyes, its wingmen and the data link tell it, never the
  world's truth (inferred; the radar, RWR and data-link code is shared).

## 4. How to read the rows

| status | meaning |
|---|---|
| **Engine** | the logic exists in `shared/` or `crates/` (the 1998 engine or the sim's own); the row wires or extends it |
| **Planned** | decided by the user, no code yet |
| **Open** | waits on a decision of the user (§9) or a source |
| **Built** | works in Modern IAF |

Each row says what it needs; a row needing a download names it in X3 and waits for his word. Every new cockpit or
radio function has its key or menu entry, both languages, and its row in the controls doc.

## 5. Needs every milestone shares

| # | need | what it takes | status |
|---|---|---|---|
| X1 | **The AI core** | the Rust crate module: behaviour trees, the flight lead, the package lead, the tick (fast leaves, slow decisions), the knowledge from sensors; the gdext class Godot calls; Rust unit tests per tree | Engine (19 Nov, milestone 1 slice 1: `crates/iaf-ai` with the behaviour tree, the flight lead, the wingman's and the AI lead's trees, decisions every 0.5 s, `IafAi`, tests); Planned (the package lead, the knowledge from sensors) |
| X2 | **6-DoF data per AI type** | for each jet the AI flies, a sourced 6-DoF data set in the sim's `bd.ibx` (no 1998 data): the Sufa (exists), the Eitam (C1), the MiG-29 (K2); each with its source cited, "open" where none is found; the jet takes off, flies the loops and lands in a headless test | Engine (Sufa); MiG-29A done (2026-11-22, K2: [flight-model.md](flight-model.md) §9.21); Planned (the Eitam) |
| X3 | **Models** | first the openly licensed models already on disk: the Sufa and the F-35I (ours), the FlightGear MiG-29 9-12 (GPL-3.0, `shared/extra/models/mig29/`); stand-ins elsewhere; a list of each missing model's file, licence and size goes to the user, one download per yes: the Eitam (a Gulfstream G550 CAEW), the long-range SAM's radars and launchers, the short-range SAM, the AAA | Partly done (2026-11-22): the S-300 launcher, the 30N6E on its tower, the Tor-M1, the ZSU-23-4, the Shahed-136, the T-72 and the Ural-4320 are in (docs/ai.md §15.4); open: the Eitam, the 64N6E2 and 96L6E radars (no clean model) |
| X4 | **Skill** | levels set per unit (three levels for the enemies, chosen by the player, wingmen fixed: §9 question 5): reaction time (the delay from a cue to the answer), aim (the gun's and the shot's error), tactics quality (which tree branches a unit may take); the same physics for every level. Built 2026-11-21 ([../../docs/ai.md](../../docs/ai.md) §17): `iaf_ai::Skill` with Low / Medium / High, the pilot's pick on the Pilot screen (Medium by default), the wingmen fixed at Medium; the sites' reaction, drills, launch range and the guns' laying error. The fighters (K3, 2026-11-22): the reaction (the commit, the defence, the launch after the bogey has been in its window that long), the launch range (the shot), the tactics (the crank and notch from Medium, the drag at High); a missile takes no laying error (it guides itself). The dogfight (K4, 2026-11-22): the tactics pick the BFM moves (§18.2's table), the gun's lead point laid off by the level's error | Built |
| X5 | **Performance budget** | measure the ms per AI jet on the Iris Xe laptop, CPU (6-DoF, autopilot, tree, sensor scan) and GPU (model, trails, vapour, sound), in one test with the player's four-ship, two or three other flights and enemies; then far-distance cost cuts where the measure says (a slower tick far away, a cheaper sensor scan, a lower model level; inferred list); the figure written in this row | Planned; first figure (19 Nov): 3.5–3.8 µs per jet per 1/60 s frame for the 6-DoF, the autopilot and the AI, on the build Mac (release build, `crates/iaf-ai/tests/four_ship.rs`); on the Iris Xe laptop (19 Nov, slice 2): 0.17 ms CPU per AI jet per frame (0.165–0.205 ms over four runs: flight model, autopilot, AI, model and sound; headless at time scale 1 in the join-up, `modern-iaf/tests/test_four_ship.gd`) and 0.127 ms GPU per AI jet drawn (22.21 ms with three wingmen in view, 21.83 ms hidden; 1920 × 1080, `_four_ship_bench_shot.gd`). For the user's sizing (his three wingmen, 2–3 other flights of four, enemies: about 20 AI jets, inferred) that is about 3.4 ms CPU and at most 2.5 ms GPU a frame with all drawn; the Rust part is about 4 µs a jet (the Mac's figure), the rest the per-jet GDScript and the model (inferred). The MiG-29A (K2, 2026-11-22): 4.21 µs per jet per frame on the build Mac (the Sufa's 4.26 in the same ground run, `four_ship.rs` `mig29_ground_run_at_ramon`); on the Iris Xe laptop 0.149 ms CPU per AI jet per frame (flight model, autopilot, model and sound; six jets, headless at time scale 1, `modern-iaf/tests/test_mig29.gd`; the Sufa wingmen's: 0.165–0.205 ms). The enemy pair in the intercept (K3, 2026-11-22): 3.9 µs per jet per frame on the build Mac (`crates/iaf-ai/tests/intercept.rs`); on the Iris Xe laptop 0.171–0.173 ms CPU per AI jet per frame (eight jets with the S-300 network and the scripted jet, headless at time scale 1, `modern-iaf/tests/test_intercept.gd`). The dogfight (K4, 2026-11-22): 4.1–7.8 µs per jet per frame on the build Mac with two fighters in the BFM leaf (`crates/iaf-ai/tests/dogfight.rs`); on the Iris Xe laptop 0.164–0.179 ms CPU per AI jet per frame (seven jets, the MiG in the BFM leaf behind the scripted jet, headless at time scale 1, five runs, `modern-iaf/tests/test_dogfight.gd`). The far-distance cuts: Planned |
| X6 | **Missiles** (dependency) | the shared physical missile and its next steps ([avionics-plan.md](avionics-plan.md) §7.2: seekers in flight and the AIM-120's mid-course, loft, fuzes, the MAW's missile type, the threat missiles); the AI's shot decisions read the same fly-out | Engine (core built 19 Nov); next steps running |
| X7 | **Radio and voices** | the AI's calls and the controller's answers as text in both languages and Hebrew and English voice clips (BlueTTS and Kokoro, the voices step, [sound.md](sound.md)); Hebrew terms searched before writing (CLAUDE.md "Modern IAF rules") | Done (Hebrew voices, BlueTTS, both genders, f50a4910; Kidon callsigns, 7724cba6) |

## 6. Milestone 1: the four-ship

A four-ship of Sufas (the player as lead, three AI wingmen) that starts in the base's shelters, takes off, flies
formation, takes commands through the radio menu, and lands with the player.

| # | row | what it needs | status |
|---|---|---|---|
| F1 | **The flight in the mission** | a mission with four Sufas on the unit's four spots ([airbases.md](airbases.md)); the briefing's flight card naming Kidon 1; the wingmen's loads from the mission | Done: mission `ramon_four_ship` (menu 2014) puts Kidon 1-1 to 1-4 in shelters S2, S3, S1 and S5 (`start.count` 4, [data-formats.md](data-formats.md) §5); the briefing's FLIGHTS card has one tab "Kidon 1" and "4 × F-16I Sufa"; the wingmen carry the lead's load (inferred) |
| F2 | **Start-up and taxi** | the wingmen start with the player (the tower's start-up call clears the flight) and taxi behind the lead in order on the spots' taxi routes; mode 9's taxi on the 6-DoF ([../../docs/ai.md](../../docs/ai.md) §8.2) | Engine (19 Nov, Rust: start 3 s apart, taxi behind the jet ahead once it has moved 150 m, the 6-DoF's taxi laws, ai.md §8.7; tested at Ramon); Done (19 Nov, slice 2: in `ramon_four_ship` the tower's start-up clearance clears the flight, `ai_flights.gd` drives Kidon 1-2 to 1-4 by `IafAi`; `modern-iaf/tests/test_four_ship.gd`) |
| F3 | **Take-off** | in pairs or a stream behind the lead (spacing inferred until a source); the tower clears the flight once; the take-off sequence tuned on the 6-DoF | Engine (19 Nov, Rust: the stream behind the lead, 24–60 s apart at Ramon); Done (19 Nov, slice 2: the stream in the game, Kidon 1-2, 1-3 and 1-4 airborne 143, 192 and 212 s after the lead left in the headless test); Planned (pairs) |
| F4 | **Join-up and formation** | four slots in the shapes that have a Hebrew term in Hebrew Wikipedia's "טיסת מבנה" (the user, 20 Nov: "just pick others that has the Hebrew term"; "You can use diamond also"): fingertip, line abreast, trail, echelon right / left, diamond, vic, delta (the spacing inferred, ai.md §8.7); rejoin from any place; turns that keep the slots; a loop for four slots tuned on the 6-DoF | Engine (19 Nov, Rust: a new slot loop, mode 0x20, ai.md §8.7, in place of growing the 1998 loops 1 / 3, whose two fixed slots and laws reborn keeps: six shapes, slots held within 9.3 m level and 23.5 m in a 45° bank turn, rejoin, a step down while changing slots, a 3 g pull away from a jet coming nearer than 60 m within 4 s, on until 100 m); Done (19 Nov, slice 2, behind the player: the join-up after the take-off calls "in position" (until 19 Nov only a command armed that call, so a join-up never made it), in the player's 30° bank turn at 201 m/s the slots held within 32–42 m in 5 runs of 5 (one earlier run: 235 m; the test's tolerance, inferred: within 300 m and each back within 60 m in 60 s, as a real wingman drifts in a turn too), at least 66 m between any two jets; every jet read at one instant and a far slot more than 60° off flown at no less than its speed less 30 m/s (ai.md §8.7); the Rust join-up in that turn within 33.6 m (28.4 m from 4 km behind), 71–84 m apart, echelon right flown; `modern-iaf/tests/test_four_ship.gd`); Done (20 Nov: the eight shapes, the wedge out, diamond, vic and delta in, each held within 10.7 m level in the Rust test and, ordered in a 45° bank turn, within 60 m for 20 s by 31 s after "in position"; any two slots at least 84 m apart; the delta widened to 120 m when 90 m set off the pull-away, ai.md §8.7) |
| F5 | **The radio menu's flight page** | Ctrl+T's menu gains the flight's calls, to the flight, the element or one wingman: for example formation, rejoin, attack my target, engage, cover me, return to base (inferred list); each wingman answers by voice and subtitle; no new hotkeys | Engine (19 Nov, Rust: the commands and the answers' ids, `IafAi.command`; slice 3: `IafAi.engage`, "engage my target": each jet addressed flies at the radar's locked enemy aircraft at 4 g and 280 m/s and fires through combat.gd's air-to-air pick and launch, #4 stays on #3, the target gone it rejoins; ground targets are milestone 3's, [../../docs/ai.md](../../docs/ai.md) §8.8); Done (19 Nov, slice 3: every answer said by the wingmen's voice, Kokoro `am_eric`, with its subtitle, the words in [research/radio-terms.md](research/radio-terms.md)); Built (A72, merged e5c62019; slice 3's screen): Ctrl+T's list gains, after the tower's calls, Kidon 1 (flight), the element 3–4 (element), Kidon 1-2, 1-3, 1-4, each opening its page: Formation (the flight: the shapes, eight since 20 Nov, numbered 1–8), Rejoin (to the element: the regroup), Split (the element, to the SPI: the radar's designated point, else the steerpoint), Engage my target, RTB, Check in, Ops check; 0 back, a click picks a line; `sim_flight.gd`, `flight_ui.gd show_menu`, `test_four_ship.gd` drives the commands through it. Built (22 Nov, the user: "Finish wingman in battle"; [../../docs/ai.md](../../docs/ai.md) §8.9): engage my target fights the target with the enemy fighters' leaves (the collision course, the shot inside the envelope's share, the crank, the BFM leaf and the gun); Cover me (keep the slot, fight a hostile jet within 37 km of the lead); the fight's calls engaged, Fox 1 / 2 / 3, guns, splash, winchester; `crates/iaf-ai/tests/wing_battle.rs`, `modern-iaf/tests/test_wing_battle.gd` (the four-ship in the air by the dev hook `flight_in_air` against a MiG-29A pair) |
| F6 | **Element and lead** | Kidon 1-3 leads the second element; a lost lead hands over to the next (the 1998 engine has no promotion: [../../docs/ai.md](../../docs/ai.md) §7.3) | Engine (19 Nov, Rust: promotion 1 → 3 → 2 → 4, the new lead flies the route and home from the lost lead's waypoint, the element as an addressee); slice 4: #4 flies on #3, F12); Done (19 Nov, slice 2: the player's current steerpoint fed to the flight every frame, `ai_flights.gd`) |
| F7 | **Return and landing** | the flight returns with the player, breaks into the circuit in order, lands at its spacing and taxis to its spots; mode 8 with the 6-DoF's landing laws, the tower's landing calls for the flight | Engine (19 Nov, Rust: once the lead's gear is down within 20 km of home, or low with the gear down anywhere, or on the ground again, the others wait (in trail; holding where they are once the lead is low) and one wingman goes home every 20 s; each lands and parks at its own shelter, engine off; at least 41 m between jets in the air); Done (19 Nov, slice 2: RTB to the flight in the game: each lands at Ramon and parks at its own shelter, engine off; `modern-iaf/tests/test_four_ship.gd`); Planned (the tower's landing calls for the flight) |
| F8 | **Fuel and bingo** | each wingman watches its fuel and calls bingo; the flight lead answers by the commands | Engine (19 Nov, Rust: bingo = 800 kg + 2 kg per km home, joker = bingo + 1,000 kg, below 800 kg home on its own; all inferred); Done (19 Nov, slice 3: joker, bingo, RTB and the ops check's fuel state, "Two, six point two" in thousands of pounds, said with subtitles) |
| F9 | **Data link** | the wingmen's positions and radar contacts on the player's HSD (the shared data link already shows the flight) | Engine |
| F10 | **Measure** | X5's first figure: the four-ship from start-up to engines off, headless and in a real render on the Iris Xe | Done (19 Nov, slice 2): on the Iris Xe laptop 0.17 ms CPU and 0.127 ms GPU per AI jet a frame (X5) |
| F11 | **Tests** | a headless test per step (start-up, take-off, formation slots held within a distance, each command answered, all four land) | Done (19 Nov): `crates/iaf-ai/tests/four_ship.rs` (Rust: the slots, shapes, rejoin, promotion, fuel, RTB from a turn, the ground run at Ramon, the join-up in the lead's 30° bank turn, every jet read at one instant with the lead's clock 40 s behind and stepped 4 times a frame) and `modern-iaf/tests/test_four_ship.gd` (headless, the mission from the tower's start-up call to all three parked, at least 30 m between jets in the air) |
| F12 | **Elements, split and regroup** | the user, 19 Nov: "In pairs means that the leader can say to split, so 1+2 doing one thing and 3+4 doing other. Every wingman in the pair follow it's lead 1/3"; "Not completely separate, but for example one pair can attack target a and the other target b"; "In the same area": #2 on #1, #4 on #3; the lead's split sends element 2 to its own target in the same area as one flight; a regroup brings it back | Engine (19 Nov, slice 4, Rust: #4 on #3 whenever #3 flies on its own, on #3's slot in the shape; `Flight::split` / `IafAi.split` (a target within 40 km of the lead: element 2 flies there and circles it at 1.5 g, #4 on #3 within 19 m), command `regroup`; the steer loop, mode 0x21; [../../docs/ai.md](../../docs/ai.md) §8.8); Done (19 Nov: in the game, `modern-iaf/tests/test_four_ship.gd`); Built (the radio menu's split and regroup: Split and Rejoin on the element's page, e5c62019) |
| F13 | **Reactions** | the user, 19 Nov: "wongmans and other flights should react to things, for example, if enemy is lock on it they should say and try to decoy, response to AWACS etc."; "It's ok if wingman isn't perfect, as in reality": on a lock or a launch each AI jet calls, defends (a turn suited to the threat's bearing) with decoys by the existing decoy rule, its mate supports, then it rejoins | Engine (19 Nov, slice 4, Rust: the call (spike, mud, defending), the beam against a radar at 4 g / 6.5 g, the break into an infrared missile at military power, chaff or flares each decision through combat.gd's release and decoy rule, the mate's break call on a launch at its partner, the rejoin 5 s clear; ai.md §8.8); Done (19 Nov: a scripted ground radar's lock on Kidon 1-2 in the game, `test_four_ship.gd`); Done (19 Nov, slice 3: the calls said with subtitles; a real S-300PMU-2 15 km from the flight, `shared/ai/air_defence.gd`, locks and launches at the wingmen: each locked one calls "mud", beams with chaff, a launch is called "defending", and each rejoins once the site is silent, `test_four_ship.gd`) |
| F14 | **AWACS calls** | act on the AWACS contact calls ([../../docs/radio.md](../../docs/radio.md) §4, `fctrl.rs`) | Engine (19 Nov, slice 4: the first AI jet holding the called contact within 74 km and ±60° reports "contact"; `radio.gd` passes each call); Done (19 Nov, slice 3: "Three, contact" said with its subtitle); Planned (later, outside his words: a commit on the call, the controller's answers to requests, Q12; ai.md §8.8 "Later") |

## 7. Milestone 2: the intercept lesson

The air-to-air lesson decided on 12 November: intercept a drone, radar search, lock and a missile shot on a
non-manoeuvring target, guided by a controller. On 19 November the controller answers requests, and an Eitam flies in
the sky.

| # | row | what it needs | status |
|---|---|---|---|
| C1 | **The Eitam in the sky** | the IAF's G550 CAEW as an AI aircraft flying an orbit; its 6-DoF data (X2), its model (X3: a stand-in until his word); the AWACS's virtual sensor moves onto it, so its picture comes from where it flies; the enemy can target it (a target for milestone 3) | Planned |
| C2 | **The controller** | the player's requests by the radio menu: picture, bogey dope, declare, vectors; the answers from the Eitam's picture in brevity words, voice and subtitle (X7); the existing contact calls (`fctrl.rs`) kept | Engine (contact calls); Planned |
| C3 | **GCI vectors for the lesson** | heading, range and altitude to the drone until the player's radar has it, then "judy" handing over (brevity word inferred until a source) | Planned |
| C4 | **The drone on the new AI** | the lesson's drone flies a route under the new core, non-manoeuvring as decided; the range's drones move over too | Planned |
| C5 | **The lesson** | the mission, its scoring and debrief ([training.md](training.md)); the instructor's lines per the decision of 12 November (a full talk-through; a script and a voice sample to the user first) | Planned |
| C6 | **Missile dependency** | the AIM-120's mid-course on the data link and its seeker going active (X6, avionics-plan.md §7.2 step 1), so the lesson's shot flies the real profile | Engine; next step running |
| C7 | **Tests** | the controller answers each request; the vectors bring the player inside radar range; a shot kills the drone | Planned |

## 8. Milestone 3: one Epic Fury strike

One strike of the Epic Fury campaign (Iran) against the smaller enemy set: one long-range SAM, one short-range SAM,
AAA and the MiG-29. The draft records hold the candidates: the S-300PMU-2 for the long range, the Tor-M1 for the short
range, the ZSU-23-4 for the AAA ([threats.md](threats.md) §6, [threat-records.md](threat-records.md)). The SAM pair
was left to the sources ("Let the agent pick by sources", 19 November): the research picks the S-300PMU-2 and the
Tor-M1, and holds the models on disk and to download, the MiG-29's flight data, the sites' make-up and procedure and
the behaviour sources ([research/enemies.md](research/enemies.md)). The rest of the draft list (3rd Khordad, Kub,
Misagh-2, F-14A) follows after this milestone, as he decided.

No mission uses the sites of K5 and K7 or the drones of K14 yet ("Just isn't reachable by mission yet", the user, 19
November): they run in headless tests and through dev hooks (`shared/ai/air_defence.gd`, `shared/ai/drones.gd`), with
stand-in shapes and records.

| # | row | what it needs | status |
|---|---|---|---|
| K1 | **The package** | the player's four-ship plus two or three other flights of mixed types (escort, strike, SEAD as the mission says) under the package lead: timing, push, roles, abort; the briefing's flights flown | Planned |
| K2 | **The MiG-29** | its 6-DoF data (X2; source open), the on-disk model (X3), its record approved, its weapons (R-73, R-27R) on the physical missile (X6 step 5) | Flies (2026-11-22): the MiG-29A, type 1020, an AI type of its own aircraft definition (`shared/extra/planes/mig29a`); its 6-DoF set by TP-1538's tables on its wing ([flight-model.md](flight-model.md) §9.21); the record `data/db/units/mig29a.json` approved with its 30 mm, R-73 and R-27R records, drawn with our model (the sim's own plane `mig29a`); it takes off, flies the autopilot's loops and lands (`crates/iaf-ai/tests/four_ship.rs` `mig29_ground_run_at_ramon`, `modern-iaf/tests/test_mig29.gd` through the dev hook `ai_flights.gd` `spawn`; no mission places one). Its weapons in flight: K3 (built 2026-11-22) |
| K14 | **One-way attack drones** | the Shahed-136 class, Epic Fury's air threats (the user, 19 November): a route flown at the real cruise speed and height, salvoes, the dive at the end point; found by the player's radar by its small cross-section and the terrain; brought down by the gun and missiles; they do not shoot | Engine: built 19 Nov as a capability (`iaf_ai::drone`, docs/ai.md §16): a point mass on the route (the 6-DoF data open), 0.01 m², a stand-in shape; no mission uses it. Ground clutter built 21 Nov: in look-down the player's radar loses it outside MTR's speed gate (docs/radar.md §9.8) |
| K3 | **Enemy fighter behaviour** | scramble or CAP, the commit, the BVR shot from the same fly-out as the DLZ, the defence after a shot (crank, notch, drag; inferred list) | Engine (2026-11-22, [../../docs/ai.md](../../docs/ai.md) §18.1): an enemy pair (`IafAi.enemy`, the trees in `crates/iaf-ai/src/fighter.rs`) on a CAP orbit or where spawned in the air, vectored by the S-300 network's 64N6E2 and 54K6E2 (`IafGci`); the commit after the lead's reaction, the collision course, the shot inside the skill's share of the DLZ through combat.gd's launch with the MiG-29A's R-27R and R-73 records, the crank, the defence by the skill's tactics (beam, notch, drag, break); `crates/iaf-ai/tests/intercept.rs`, `modern-iaf/tests/test_intercept.gd` through the dev hook `ai_flights.gd` `enemy_flight`; no mission places one. The scramble from a base (2026-11-22, §18.3): a pair parked in a base's shelters starts on the network's vector after the lead's reaction, taxies, takes off, intercepts, goes home and parks (`crates/iaf-ai/tests/scramble.rs`, `modern-iaf/tests/test_enemy_scramble.gd` through the dev hook `ai_flights.gd` `enemy_base`; the sim has no enemy base, so any base stands in by the hook's argument; no mission places one). Every AI jet's ground, flare and arrival home (2026-11-22, §18.4): its ground wherever the player is, the flare over the runway's height with a 1 s lead on its sink, GoHome passed near its waypoint (`crates/iaf-ai/tests/landing.rs`, `modern-iaf/tests/test_ai_far_landing.gd`) |
| K4 | **Energy-aware BFM** | a new BFM leaf that weighs energy, turn rate and the turn circle against the opponent's, with the skill's tactics (X4); for enemies and wingmen alike; the 6-DoF's real limits (no 1998 cases); placed here because the MiG-29 needs it (inferred; §9 question 4) | Engine (2026-11-22, [../../docs/ai.md](../../docs/ai.md) §18.2): the leaf in the enemy trees (`crates/iaf-ai/src/bfm.rs`) inside 6 km of a bogey in sight: offensive pursuit (lead, pure, lag) and the yo-yos, the defensive break and guns jink, the neutral rate, radius or vertical fight after Shaw, picked by the skill's tactics; its turn from the 6-DoF's corner speed (`SixDof::corner_speed`), the energy heights, the bogey's turn as seen; flown by the autopilot's BFM loop (`MODE_BFM`); the gun's burst through combat.gd (370, 300) with the level's laying error; `crates/iaf-ai/tests/dogfight.rs`, `modern-iaf/tests/test_dogfight.gd`; no mission places one. The level turns hold their height within 30 m (the fighter's turn laws, `Steer::fighter`) and the offensive moves control the closure (throttle, speed brake), 22 Nov. The wingmen's use of it (22 Nov, [../../docs/ai.md](../../docs/ai.md) §8.9): our wingmen fly the same leaf, shot, intercept and defence on their foe (the lead's target, a hostile jet near the lead while covering, or one attacking them); `crates/iaf-ai/tests/wing_battle.rs`, `modern-iaf/tests/test_wing_battle.gd` |
| K5 | **SAM site procedure** | per site: search radar, then the track radar on a chosen target; launch counts and salvo rules per system from its record; emission on / off as a choice (EMCON); relocating after firing; the RWR and MAW cues these make; the 1998 quirks (one missile in the air, no shot 90° off the heading) left behind | Engine: built 19 Nov as a capability (`iaf_ai::site`, docs/ai.md §15): the S-300PMU-2 and the Tor-M1 with their crews' procedure, EMCON, relocation, detection by the jet's radar cross-section and terrain sight; ground clutter (21 Nov: the Tor's Doppler notch, the ZSU's 60 m floor; docs/ai.md §15.3); the stand-in missile; no mission uses it |
| K6 | **SAM network** | after K5: an early-warning radar cues the sites, the sites share the picture and hand targets over | Engine: built 21 Nov as a capability (`iaf_ai::net`, docs/ai.md §15.5): the 83M6E2's 64N6E2 search radar and 54K6E2 command post; the picture from the radar's 12 s sweep and the sites' tracks; each site's track radar cued with its own search off, one site per jet, the hand-over past a site's envelope; losing the radar or the post leaves the sites autonomous; no mission uses it |
| K7 | **AAA** | the ZSU-23-4's radar and optical laying, rate of fire and burst rules from its record | Engine: built 19 Nov as a capability (docs/ai.md §15): radar and optical laying, bursts on the move, the 2,000 rounds, the 20 mm round standing in; no mission uses it |
| K8 | **Countermeasures: effectiveness** | flares against infrared seekers and chaff against radar seekers, for both sides, on the physical missile's seeker (X6 step 1); the AI's own flare and chaff use by its tree | Engine (2026-11-22, [../../docs/real-weapons.md](../../docs/real-weapons.md) §2.3, [../../docs/ai.md](../../docs/ai.md) §15.6): each missile at the releasing jet rolls on its own seeker's chance (`ecm.rs`): the kind, its record's rejection (`_decoyReject`: AIM-9M 0.5, AIM-9X and Python 5 0.85, R-73 0.3, AIM-120 0.8, R-27R 0.5; inferred), chaff working on the beam, the time to go (full inside 6 s), the afterburner and the g; the player's keys and CMDS and the AI's tree feed it through one release path; the AI jets (wingmen, enemy fighters) release at a missile's launch cue and within 6 s, none against a lock alone; `modern-iaf/tests/test_countermeasures.gd`. The 1998 game keeps its rule |
| K9 | **Jamming** | the Sufa's internal jammer (SPS-3000 / ASPS, in the spine) acting on the enemy radars' detection and lock; the enemy's jamming of the player's radar; the J key and the CMDS's JMR exist ([avionics-plan.md](avionics-plan.md) E3); the Barak's jammer per §1 item 10 | Engine (2026-11-22, [../../docs/ai.md](../../docs/ai.md) §15.6): the burn-through (reach · share · √(σ / 5 m²)); the Sufa's jammer (its definition's `jammer.burn_through` 0.3, inferred) on the J key holds the sites' search and track radars, the network's 64N6E2 and the enemy fighters' radar to it; an AI jet with a jammer in its definition jams while its RWR shows a lock or a missile or it defends, not on the commit alone (the enemy fighters' radar flies at its strobe, home on jam, to the burn-through); an enemy one jams the player's radar (none today: the MiG-29A (9.12) has none, the L-203BE Gardeniya-1 came with the 9.13; docs/ai.md §15.6); the cues: the threat display's chevrons, the FCR's and the PCD's jam strobe; the 1998 beacon and the J key's break-lock of the missiles in flight off; a friendly jammer (a wingman's) never blinds the player's radar. The Barak's jammer stays open (§1 item 10). Not started: jamming against a missile's own seeker |
| K10 | **The Eitam as a target** | enemy fighters may go for the Eitam (C1); its orbit and escape | Planned |
| K11 | **Models and records** | X3's list for the set; the records approved by the user (threat-records.md) | Open (his word per file and record) |
| K12 | **Measure** | X5 with the whole package and the enemies; the far-distance cuts it calls for | Planned |
| K13 | **Tests** | headless: each site's procedure, the MiG-29 commits and shoots, the package reaches the target and returns; a real render per X5 | Planned |

## 9. Open questions for the user

The rows still Planned are open issues: the user, 20 Nov: "Leave it as open issue. We need to finalize things".

1. **Voices:** answered: Hebrew voices (BlueTTS, both genders), merged f50a4910.
2. **The wingmen's callsigns and the radio words:** answered: Kidon N-M callsigns, merged 7724cba6, after Hebrew
   Wikipedia's טיסת מבנה; the user, 19 Nov: "I said search for IAF terms and if not fallback to NATO".
3. **The enemy set's systems:** which long-range SAM (S-300PMU-2, Bavar-373, 3rd Khordad) and which short-range one
   (Tor-M1, others) fill milestone 3. Answered 19 November: "Let the agent pick by sources"; picked: the S-300PMU-2
   and the Tor-M1 ([research/enemies.md](research/enemies.md) §2.2). The draft records still wait for his approval.
4. **BFM's milestone:** the BFM in milestone 3 for the MiG-29 (as planned here), or the MiG-29 BVR-only first and the
   BFM after.
5. **Skill levels:** answered, the user, 19 Nov: "wingman are always the same, it only effect enemeis, choosen from 3
   options per player" (three levels for the enemies, chosen by the player; the wingmen's skill is fixed).
6. **The Barak's jammer:** whether today's Barak carries the EL/L-8240 or another set (no source found).
7. **The strike itself:** the target, the base and the package's flights for the first Epic Fury mission.

## 10. Not started (outside his words)

Listed, not built: tankers and refuelling; AI departures and arrivals at the bases beside the player's flight (the
tower's traffic); moving ground forces, convoys and launchers; ships manoeuvring; terrain masking and low-level
routes for the AI.
The instructor voice is its own item (decided 12 November; C5 uses it).
