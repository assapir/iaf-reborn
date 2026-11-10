# Modern IAF's front end

**Terms:** front end = the screens before and after a flight; inline start / end = the side a line of text starts / ends
on (the left / right in English, the right / left in Hebrew); debrief record = the scorer's JSON for one flight
([training.md](training.md) §4); pilot log = the record of every attempt ([training.md](training.md) §9).

The front end (item [E2](plan.md#e2-the-front-end)) is the sim's main scene, `modern-iaf/main.tscn`. `./start-modern-iaf` opens it.
It builds the round-3 design the user approved on 3 November 2026: one screen per step, in Hebrew and English, with the
Heebo font and the Israeli Air Force flag's colours.

```sh
./start-modern-iaf                     # Home (the first start: the Pilot screen makes the profile first)
./start-modern-iaf -- --mission 2011   # flies that mission at once, then shows its debrief
```

The window opens plain in the front end's background colour (#1d2025, no Godot splash image) until Home draws.

## 1. The screens

| screen | what it does | English | Hebrew |
|---|---|---|---|
| Home | the sim's name, Missions, the menu: Pilot log, Preferences, Attributions, Quit; the pilot's nickname in the top bar with the name under it, no counts, no jet | ![Home](pictures/front-end/home_en.webp) | ![Home, Hebrew](pictures/front-end/home_he.webp) |
| Pick a plane | the Sufa (Ramon, 253 Squadron), the Barak (Ramat David, 109 Squadron) and the Adir (Nevatim, 140 Squadron) in one row, each card with its code, name, base and squadron (airbases.md §3), then the Ra'am (Hatzerim, 69 Squadron) and the Baz (Tel Nof, 133 Squadron) greyed; the pick sets the jet everywhere and stays highlighted on the next visit | ![Pick a plane](pictures/front-end/plane_en.webp) | ![Pick a plane, Hebrew](pictures/front-end/plane_he.webp) |
| Training | the programme: its missions with their last result and the progress | ![Training](pictures/front-end/training_en.webp) | ![Training, Hebrew](pictures/front-end/training_he.webp) |
| Pick a mission | the missions beside the picked one's briefing (§10) on three pages: Briefing (base, runway and heading, time, wind, time allowed, objectives, how), Map (one zoomable map) and Arming (the jet's front view with its stores, its weights); Fly | ![Pick a mission](pictures/front-end/mission_en.webp) | ![Pick a mission, Hebrew](pictures/front-end/mission_he.webp) |
| Preferences | the sections Graphics, Language, Sound and Devices listed at the inline start; the picked one's settings open beside them as controls: dropdown, switch, slider, radio list | ![Preferences](pictures/front-end/prefs_graphics_en.webp) | ![Preferences, Hebrew](pictures/front-end/prefs_graphics_he.webp) |
| Debrief | the record as a sheet: Plane flown, From, Time, Mission, Result, the mission's goals (a take-off: runway, lift-off and reference speed, centreline offset, tower calls; a start-up: none), Remarks (the fail reason first, or that it passed; the lift-off against the reference); Back to missions, Fly again | ![Debrief](pictures/front-end/debrief_en.webp) | ![Debrief, Hebrew](pictures/front-end/debrief_he.webp) |
| Pilot | Home → the pilot's name: the picture in a service ID photo's fixed 3:4 frame (a click on it, or Choose a picture…, opens the system's file dialog), the name and the nickname, and the logbook (§3); the footer's Reset the log, Change pilot, Back and Save (§3) | ![Pilot](pictures/front-end/pilot_en.webp) | ![Pilot, Hebrew](pictures/front-end/pilot_he.webp) |
| Create your pilot | the first start, before Home: the Pilot screen with Save only (§3) | ![Create your pilot](pictures/front-end/pilot_first_en.webp) | ![Create your pilot, Hebrew](pictures/front-end/pilot_first_he.webp) |
| Reset the log | the Pilot screen's Reset: a warning modal, then a second confirm (§3) | ![Reset the log](pictures/front-end/pilot_reset_en.webp) | ![Reset the log, Hebrew](pictures/front-end/pilot_reset_he.webp) |
| Pilots | the Pilot screen's Change pilot: every pilot with a name, the active one marked Current; New pilot (§3) | ![Pilots](pictures/front-end/pilots_en.webp) | ![Pilots, Hebrew](pictures/front-end/pilots_he.webp) |
| Pilot log | every attempt, newest first; a row opens its debrief | ![Pilot log](pictures/front-end/log_en.webp) | ![Pilot log, Hebrew](pictures/front-end/log_he.webp) |
| Attributions | the setup wizard's list of sources and licences, the jet photos with them | ![Attributions](pictures/front-end/credits_en.webp) | ![Attributions, Hebrew](pictures/front-end/credits_he.webp) |

At a training mission's end a banner over the view says "Mission complete" (or "Fail" and the reason); about 5 s
later the flight ends into its debrief ([training.md](training.md) §9).

Over a flight, Esc opens the pause menu: Continue the flight, Preferences, End the flight. It is laid out on the
front end's canvas scaled to the window and centred by a container, so it sits in the middle at any window size and in
either language (the Mac run of 2026-11-08: in Hebrew in a 2560 × 1440 window the overlay mirrored its own position
by its unscaled width and sat off the right edge, its buttons' labels outside the screen). Ending a training flight
scores it as it stands and opens its debrief; a flight that was not scored goes back to Home. The sheet shows only
the record's `goals` ([training.md](training.md) §4); every other number stays in the record file.

| the Hebrew pause menu before the fix (2026-11-08) | after |
|---|---|
| ![The pause menu shifted left, the dim cut off at the right](pictures/front-end/pause_he_before.webp) | ![The pause menu centred](pictures/front-end/pause_he.webp) |

| screen | English | Hebrew |
|---|---|---|
| the pause menu over the flight | ![Pause menu](pictures/front-end/pause_en.webp) | ![Pause menu, Hebrew](pictures/front-end/pause_he.webp) |
| a failed debrief (a take-off with the gear never raised) | ![Failed debrief](pictures/front-end/debrief_fail_en.webp) | ![Failed debrief, Hebrew](pictures/front-end/debrief_fail_he.webp) |
| the debrief of that flight | ![Debrief after a flight](pictures/front-end/flown_debrief_en.webp) | ![Debrief after a flight, Hebrew](pictures/front-end/flown_debrief_he.webp) |

Keys: Enter picks the focused control, Esc goes one screen back (Home has no back), the arrow keys and Tab move the
focus. The bottom bar holds the photo credit (centred; a long one, the plane screen's five photos, wraps to a second
line; "public domain" in Hebrew is "נחלת הכלל") and the screen's buttons; it shows no key hints (the user, 2026-11-09: "this is
obvious and people will use mouse anyway"). Every breadcrumb in the top bar but the current one opens its
screen (a jet's name: its Training); the picks are kept.

| screen | English | Hebrew |
|---|---|---|
| Preferences: Graphics | ![Graphics](pictures/front-end/prefs_graphics_en.webp) | ![Graphics, Hebrew](pictures/front-end/prefs_graphics_he.webp) |
| Preferences: Sound | ![Sound](pictures/front-end/prefs_sound_en.webp) | ![Sound, Hebrew](pictures/front-end/prefs_sound_he.webp) |
| Preferences: Devices | ![Devices](pictures/front-end/prefs_devices_en.webp) | ![Devices, Hebrew](pictures/front-end/prefs_devices_he.webp) |
| Preferences: Language | ![Language](pictures/front-end/prefs_language_en.webp) | ![Language, Hebrew](pictures/front-end/prefs_language_he.webp) |

## 2. The flow

Home → Missions → Pick a plane → Continue → Training → Open → Pick a mission → Fly → the flight → the debrief → Home.
Every start opens Home, which shows no jet (the user, 2026-11-09: the plane is the second step). Pick a plane opens with
the last pick highlighted; its Continue (off until a pick) goes to Training, Esc back to Home. Esc on Training goes back
to Pick a plane. The breadcrumbs follow the same order: Home · Plane · the jet (its Training) · the mission screen.
Training is the one programme; a campaign card takes its place beside it later.

The plane cards stand in one row. Five jets (with the Ra'am and the Baz) fit across at 1920 × 1080 with the photos at
their full height, each cropped narrower. Tested 2026-11-09 and dropped: a row of three and a row of two, which halved
the photos' height into strips.

The Ra'am (F-15I, `f15i`) and the Baz (F-15C, `f15c`) show after the three flyable jets, disabled until the sim flies
them (the user, 2026-11-10): the card dimmed, its photo in grey, no click, no focus, no text on why. Each card shows
its code, name, squadron and base like the others (`SOON` in `front_end.gd`; the squadrons in the Hatzerim and Tel Nof
base files, airbases.md §3). Making one flyable moves its row from `SOON` to `JETS`.

- **The plane:** a card press stores the unit (`Settings.sim_jet`: `f16i`, `f16d` or `f35i`; `settings.cfg` section
  `[sim]`, key `jet`) and sets the F-16 switch (`Settings.set_jet`).
- **The missions:** the compiled list `assets/converted/modern-iaf/missions/missionlist.json` (`iaf-sim missions`), each
  read from its readable file `modern-iaf/data/missions/<name>.json`, kept when its player unit is the picked jet and it
  has `training` rules, in menu-id order.
- **Fly:** `flight/fly.gd` `start(menu id)` loads the compiled mission, picks the mission's jet (a `--mission` run,
  Fly again on another jet's debrief) and changes to the flight scene.
- **Back to missions** on a debrief opens that mission's jet with the flown mission picked.
- **The flight's end:** the flight scene returns to `Settings.front_end_scene()` (`res://main.tscn`). When the flight
  stored a sortie (`flight/sim_flight.gd` sets `Settings.flown_sortie`), the front end opens its debrief.

## 3. The data it reads

| what | where | written by |
|---|---|---|
| the sorties and their debrief records | `user://modern-iaf.sqlite` (tests: `<temp>/modern-iaf-records/`), `Settings.records_db()`, read through `IafPilotLog` ([storage.md](storage.md) §5) | `sim_flight.gd` at the scoring: the scorer's record plus `flight`, `date` (the end, local time) and `elapsed_s` (the flight's length, s) |
| the picked jet | `user://settings.cfg` `[sim] jet` | the front end |
| the jet photos | `modern-iaf/data/photos/` (§5) | — |

The pilot's profile (the Pilot screen) is in the records database's `pilots` row ([storage.md](storage.md) §5): the
name, the nickname and the picture, a copy of the chosen file in `pictures/` beside the database. Every screen's top
bar shows the nickname, else the name, else the computer's user name; with a picture, the picture in a small 3:4
frame in place of the initials' disc. The picture keeps square corners and no round mask, as a service ID photo; it is
cropped to fill the frame.

**The Pilot screen** (2026-11-10, the user's findings on it):

- **A draft until Save.** The name, the nickname and a newly chosen picture change nothing until Save (primary, at
  the footer's end, greyed without a name), which stores them and opens Home; the picture file is copied beside the
  database then. Back (and Esc) opens Home, after a modal "Discard the changes?" (Discard / Keep editing) when
  something changed; Change pilot and the Home crumb ask the same. The empty fields show hints ("Full name", "For example: Viper"): the nickname field used to show
  the pilot's name in grey, which read as text that no click could edit.
- **The picture** opens the file dialog on a click, as Choose a picture… does.
- **The logbook** beside the profile (`IafPilotLog.logbook`): per plane flown, most hours first, its flight time
  (`clock`) and its flights, passes and fails, then each mission flown on it with its passes and fails. A sortie
  stored before the records kept its plane counts for its mission's jet (the readable mission's `start.unit`).
- **Reset the log** (greyed with no flights) opens a modal, "Reset the pilot log?" / "לאפס את יומן הטיסות?", then a
  second one, "Reset for good?" / "לאפס סופית?"; each has Reset / לאפס and Cancel, Cancel focused and Esc closing it.
  Reset deletes the pilot's sorties and their debriefs; the name, nickname and picture stay.
- **Several pilots.** Change pilot opens the pilot list: each pilot with a name (picture or initials, nickname, name),
  Current on the active one. A click makes that pilot active and opens Home; New pilot opens the Pilot screen empty,
  and its Save makes the pilot and makes it active. The active pilot is `Settings.pilot_id`, kept in `settings.cfg`
  `[sim] pilot` (the default pilot 14 before any pick).
- **The first start.** While the active pilot has no name stored, Home's place is taken by the Pilot screen titled
  "Create your pilot" with only Save (Esc stays); Save stores the profile on the active pilot, its imported sorties
  kept, and opens Home. When the records hold other pilots with a name, the pilot list opens instead.
- **The modal** is the sim's: the screen dimmed, a panel with the title, the text, the safe choice and the action;
  mirrored in Hebrew. The Hebrew texts are in the infinitive, gender neutral.

The debrief's number is its sortie's id, the sortie's place among all stored flights, oldest first. Training's status
and best time are `IafPilotLog.summary`'s. Its Time is the day, then the mission's clock from its start (the mission's `time`) to the start plus
`elapsed_s`. The pilot's name is the profile's nickname or name, else the computer's user name. The Remarks are
the record's fail reasons, then what its
numbers say: the lift-off speed against the reference speed for the weight, and the largest offset from the
centreline in the roll.

## 4. Look and layout

- **Palette** (round 3): background `#1d2025`, panels `#262a31`, lines `#3b414b`, text `#eef0f2` / `#aab1bb`, the one
  accent `#6699ff` (the Air Force flag's sky blue) with `#000055` (its navy) on it, the debrief paper `#f3efe6` with
  rules `#b9b09c`. All in `modern-iaf/menu/look.gd`, which builds the theme on the wizard's Heebo
  (`setup/wizard_theme.gd`).
- **Sizes:** every screen lays out on a 1920 × 1080 canvas that the window shows scaled to its height (stretch mode
  "canvas items", aspect "expand"); the body text is 21 px, 1.9 % of the height, as in the mock-ups. The front end sets
  the scaling only while it is the scene, so the flight keeps the project's own. Over a flight the pause menu scales
  itself the same way.
- **Hebrew:** the front end's layout direction is right to left, so Godot mirrors the containers, the anchors, the
  labels' alignment, the sliders, the progress bar, the toggles (on: the knob at the inline end) and the radio lists.
  The photos never flip (their tail numbers would read backwards); Home places its photo on the inline-end side. Latin
  codes (F-16I, 25R, 08:00) run left to right inside the Hebrew lines; "MSAA 4×" carries a left-to-right mark.
- **Strings:** `modern-iaf/menu/strings_en.json` and `strings_he.json`, formal and gender-neutral (infinitives: לטוס,
  להתניע, לבקש). The Language row switches every string at once. The in-flight mission card's objective is the
  compiled mission's (§8), the briefing's objectives and steps the rules' (§10). A training mission's title is its
  kind ("Take-off", "המראה"; the missions' `title`, the user, 2026-11-09): the base is its own field everywhere it
  shows (the briefing, the loading screen's second line, the debrief's From).
- **The jet's subtitle** (the top bar, the plane cards, Training, Pick a mission, the briefing): its tail number, its
  squadron and its base, "482 · 253 Squadron Negev · Ramon", "482 · טייסת 253 הנגב · רמון" (the user, 2026-11-09: the
  wing is the base, so it is left out). The tail number is the unit record's `tail`, one real jet of the squadron
  from a public photo ([data-formats.md](data-formats.md) §3); the squadron is its airbase file's
  ([airbases.md](airbases.md) §3).
- **Preferences:** one screen: the sections listed at the inline start, the picked one's rows beside them (Graphics
  until one is picked; the user, 2026-11-09, of the screen per section: "I liked it more before"). The section's pane
  scrolls over its full height, its scroll bar running from its top to its bottom. A row shows its name and its
  control, no line under it; a greyed row says why (Scenery without its setup step, §4). Over a flight Esc on the
  Preferences goes back to the pause menu; the Keys and Joystick screens go back to the Preferences on Devices. Tried
  2026-11-08 and dropped 2026-11-09: one screen per section, the list as cards with the rows' names under each
  section. Realism and aids have no switch (plan.md "physics";
  the user, 2026-11-08): the sim's `PROFILE` (`modern-iaf/sim_settings.gd`) fixes the original Gameplay page's aids off
  (easy landing, unlimited fuel, no damage, no crashes, no G effects…) and the look switches to the sim's own
  (Detailed airbases, water, night lights; the ground textures and roads whenever their data exist), so
  none of them is a row. The weather is the mission's (no Rain row). Volumetric clouds are greyed without a
  RenderingDevice. Graphics → "Buildings and trees" is the shared Scenery setting (Off / On / Detailed, On by
  default, [scenery.md](scenery.md) §6); without setup's optional scenery step it is greyed at Off, with a note
  naming that step. The HUD's brightness has no row: it is the cockpit's SYM wheel ([cockpit.md](cockpit.md) §5.1;
  the mouse: §9.1).
- **Sound samples:** moving a Sound slider plays a short clip of its class at the new level, on that slider's bus, from
  the sim's own clips (`converted/own/resource/soundfiles`, `SoundTable`): Engine the engine
  (`SFX_START_ENGINE`), Effects the master caution tone (`SFX_WARNING` `WRN_MASTER`, the effects' class), Radio
  voices a tower call (`twr_takeoff.wav`). Betty's calls ride the Radio voices bus too, so the tower call stands for
  them. A sample still playing follows the slider; another slider's starts in its place.

## 5. The photos

Six Wikimedia Commons photos, downscaled, each credited in the footer of the screen that shows it, on Attributions
and in [../../docs/credits.md](../../docs/credits.md) "Modern IAF's photos". The list with each page:
`modern-iaf/data/photos/SOURCES.md`. Round 3's Barak photo was CC BY-SA; the front end uses a CC BY 2.0 one instead.

## 6. Checks

- `modern-iaf/tests/test_front_end.gd` walks Home → Pick a plane → Training → Pick a mission → the debrief of a stored
  record → Home in English and Hebrew: the texts, the mirrored order of the cards, the mission list and the home
  column, the layout direction; the plane pick; the Ra'am's and the Baz's cards with their squadrons, greyed and not
  pickable; the Preferences' controls and the live language switch; the Pilot log
  and Attributions. With `-- --fly` it also flies Ramon's start-up from the mission screen to a pass, opens the pause
  menu, ends the flight and finds that flight's debrief. Run in a real render through `tools/godot_window.sh` it is
  the real run (`SHOT_DIR=<dir>` saves the two pictures of §1's second table).
  It also checks the first start (the Pilot screen before Home, Save only with a name typed through real input
  events, Esc staying, Save storing the name on the active pilot and opening Home; then Home's Missions, the picker, Continue to Training, Esc back through the picker to a
  Home with no jet), Home's Pilot log entry opening the Pilot log, the breadcrumbs, each
  Preferences section opening beside the list on the same screen (its pane over 700 px high, on the inline-end side),
  no line under an option, no aid, realism or weather row and no read of the original's data, the
  sim's settings (no aid on, the log dumps naming only the sim's settings), F1–F4 opening no pause menu, and the
  pause menu inside viewports of 1920 × 1080, 2560 × 1440 and 1280 × 800 in both languages, and the Pilot screen in
  both languages: Home's pilot name opens it, the nickname field shows a hint and takes a click and typed keys, the
  logbook's Sufa with its counts and per-mission passes and fails, Back's discard prompt (Keep editing keeps the
  draft), a click on the picture opening the file picker, a file that is no picture refused, a picture shown in its
  3:4 frame and copied beside the records only on Save, Save opening Home with the nickname and the name under it;
  then Change pilot: the list marking the active pilot, New pilot making a second pilot, active, with an empty log,
  its sortie kept through Reset's first modal and deleted by the second (the other pilot's log kept), and the list
  picking the first pilot back.
- The briefing (§10): the title as the kind, the time as "0800", the wind as "000° / 0 kt" ("קשר"), the take-off's
  four objectives, its runway with the heading, its four steps in a four-column table, the three tabs mirrored and
  the arrow keys between them; the six take-off steps (each tower call its own, with its pick and the answer to wait
  for); the wind's figures left to right; the subtitle with the tail number and no wing; the Arming
  page's own Sufa drawing with a slot per station (the wing slots in station order 9 to 1, apart; the tanks in the
  second row straight under 4 and 6), each store's name as its tooltip, the title "Sufa · F-16I · 482" with the Latin
  and digits isolated, no F-16C, the rounds, chaff, flares, fuel, take-off weight and maximum weight each a field,
  centred, no credit on Briefing or Arming, the Map's credit at the footer's inline end, the Adir's own drawing; the start-up's steps with their switches and waits;
  the map over the page with the screen's aspect, the ground colour, roads, Mitzpe Ramon, the airbase, taxi and
  route, the credit; the wheel zooms around the pointer and the scale bar follows, a drag scrolls, a double click
  resets, + zooms, an arrow scrolls the focused map (not the tabs), 0 resets; the page kept for the next mission; the
  start-up's six checklist steps with their keys.
- `cargo test -p iaf-tools --lib briefing`: the map of Ramon's take-off (the base, the taxi from the parking spot to
  the lineup, the waypoint west-south-west of it, the aspect, the fills inside the map, the base's shapes, the towns
  inside it only), of every start-up and take-off; the Sufa's and the F-35I's stores.
- `modern-iaf/tests/_front_end_shot.gd` takes §1's pictures at 1920 × 1080 (its header), and the failed debrief.
- `modern-iaf/tests/test_flight_ui.gd` checks §8 in both languages.

## 7. The loading screen

While a flight waits for its ground, the sim shows its own loading screen, `modern-iaf/flight/loading_screen.gd`. The
flight scene asks `Settings.loading_screen_scene()` for it; the original game keeps its menu-art screen
(`shared/terrain/loading_screen.gd`). It reads nothing of the original game's art.

The screen is one panel in the front end's look (§4, `modern-iaf/menu/look.gd`). It shows:

- the mission's title in the sim's language (the compiled mission's `sim.title`; without a mission, the sim's name);
- its base's name ("Ramon", "רמון"; no wing: the wing is the base), from the compiled mission's `sim.base`
  (`iaf-sim missions`);
- a progress bar and, under it, the loading step under way. The flight names each real phase of its start
  (`terrain_view.gd _loading_step` → the screen's `step(name, done)`); the bar takes each phase's share (`STEPS`),
  smoothed and never going back. The original game's screen shows the ground's progress alone, as before.

| step | what loads | share of the bar | measured |
|---|---|---|---|
| The jet and its cockpit | the start, the player's jet and its cockpit, the ground preloaded by the front end handed over | 0–1 % | 0.02 s |
| Buildings, trees and sounds | the models' detail textures, the scenery's materials drawn once, the sounds, the radio, the training run | 1–11 % | 2.1 s |
| Effects and damage | explosions, smoke trails, the systems damage | 11–16 % | 1.1 s |
| The flight model | the flight overlay, the flight model's start | 16–17 % | 0.2 s |
| The jet on the ground, its weapons and views | the jet placed, the views, the weapons | 17–52 % | 7.6 s |
| The ground around the base | the terrain near the jet at full detail (`ground_progress()`) | 52–78 % | 5.8 s |
| The mission's models | the mission's models parsed ahead | 78–80 % | none left |
| The views | the external view drawn once for its shaders, the last scenery | 80–100 % | 4.9 s |

The shares follow one measured start on the development laptop (Intel Iris Xe, a real window, 2026-11-09): Ramon's
start-up from Fly.start to the flight, 21.8 s, its steps logged as above. Before, the bar sat at 0 % through the build
(the flight fed it only once the build was done) and then jumped with the ground.

Each new step is logged with its time since the screen opened (`loading: terrain at 11081 ms`).

In Hebrew the page is mirrored: the bar fills from the inline start, the right.

| English | Hebrew |
|---|---|
| ![The loading screen: "Take-off", "Ramon", the bar in the ground's step, "The ground around the base" under it](pictures/front-end/loading_en.webp) | ![The loading screen in Hebrew: "המראה", "רמון", the bar filling from the right, "הקרקע סביב הבסיס" under it](pictures/front-end/loading_he.webp) |

`modern-iaf/tests/_loading_shot.gd` takes these pictures (its header).

## 8. Over the flight: the mission card, the radio lines, the key hint

The sim draws its own text over the flight in the front end's look (`modern-iaf/flight/flight_ui.gd`, Heebo, look.gd's
palette, on the 1080-high canvas scaled to the window), mirrored in Hebrew; the original game's console and panels
stay the original's (`terrain_view.gd _on_subtitle` hands each line to the flight add-on when it has a `subtitle()`).

- **The mission card** opens at a training mission's start: the mission's title, its objective with the keys as
  bound ("Ctrl + T"; "Cmd + T" on macOS) and the runway, and the keys that matter with their labels, from the
  compiled mission's `sim.card` ([data-formats.md](data-formats.md) §5; a default per mission kind). The flight is
  frozen while it is open. Space, Enter, Esc or a click close it; H (the key table's Mission card, record 118; the HUD
  colour moved to Shift + H) opens it again. Scripted runs (`IAF_DEFAULT_SETTINGS=1`) start with it closed.
- **The radio lines and messages** show in a strip centred at the top, over the sky rather than the cockpit's panel,
  the newest at the bottom, three at most, each for 8 s, wholly in the game's language ([training.md](training.md)
  §8).
- **The panel** at the inline-start top holds the radio menu (Ctrl+T) and the training result.
- **The key hint** at the bottom: the Mission card key and Esc's pause menu. It shows for the first 8 s of a flight,
  for 4 s after a language change and for 4 s after the mission card closes (so the player learns the key that opens
  it again), then fades out. It is hidden while the mission card or the start-up checklist card is open (the user,
  2026-11-10: the hint stays out of the way of the narrative). The pause menu's own key hints are separate.

A language switched over the flight (Esc → Preferences → Language) applies at once to the key hint, the panel and
the start-up checklist card ([training.md](training.md) §7.1); a radio line already shown stays in its language.

| | English | Hebrew |
|---|---|---|
| the take-off's card (no key hint under it) | ![The mission card of Ramon's take-off](pictures/front-end/card_en.webp) | ![The mission card in Hebrew](pictures/front-end/card_he.webp) |
| the strip after a tower call, the key hint still showing | ![A tower call in the band](pictures/front-end/band_en.webp) | ![A tower call in Hebrew](pictures/front-end/band_he.webp) |
| 10 s into the flight: the key hint faded out | ![The take-off 10 s in, no key hint](pictures/front-end/flight10_en.webp) | ![The take-off 10 s in, Hebrew](pictures/front-end/flight10_he.webp) |

## 9. Keys and Joystick

Preferences → Devices has two rows that open their own screens: **Keys** and **Joystick**. Esc on either goes back to
the Preferences on Devices. Both read and write one file, the device store (§9.4). A change applies at once: the front end's
next flight reads it, and over a flight the Preferences apply it when they close.

### 9.1 Keys

The screen lists every command of the sim's key table (`modern-iaf/data/keys.json`) that has a `group`, in five groups:
Flight, Weapons, Sensors and displays, Views, General. The tabs on the inline-start side scroll to each group. A row
shows the command and its key; on macOS a key with Ctrl shows as Cmd (`key_table.gd`, docs/controls.md §2). The
table's records without a group are the commands the sim lacks (the chat, the wingman orders, the debug keys, the
screen capture): no row.

- **Rebind:** click a row, and its key reads "Press a key…". The next key with its one modifier (Ctrl / Cmd, Shift,
  Alt) becomes the command's key. Esc cancels; a lone modifier waits for the key.
- **Conflict:** a key another command already has opens a line under the row: "K already runs “Pitch up”." Its
  choices: **Swap** (the other command takes this one's old key), **Use it here** (the other command has no key then),
  **Cancel**. The check covers every record of the table, listed or not, since the flight runs the first record bound
  to a key.
- **Default** shows on a changed row and puts that command back to the table's key. **Reset all** in the bottom bar
  puts every key back.

**The laptop map.** A laptop has no numpad, so on macOS the sim starts from the laptop map: the same table with the
keys of `keys.json`'s `laptop` column (compiled into `converted/own/keys_laptop.json`; `Settings.laptop_keys`). A Mac
with a full keyboard gets it too; Rebind puts any command back on the numpad. Default and Reset all go back to the
laptop map there. The commands it moves:

| Command | Key | Laptop map |
|---|---|---|
| Rudder left / right | Numpad 0 / Decimal | Z / X |
| Weapon page full screen | Z | Shift + Z |
| Extinguish engine fire | X | Shift + X |
| Look back-left, back, back-right | Numpad 1, 2, 3 | Alt + 1, 2, 3 |
| Look left, forward, right | Numpad 4, 5, 6 | Alt + 4, 5, 6 |
| Look front-left, up, front-right | Numpad 7, 8, 9 | Alt + 7, 8, 9 |
| Free look (numpad) | Shift + Numpad 8, 2, 4, 6 | none: Shift + the arrows |
| Zoom (numpad) | Numpad − / + | none: − / = |

The key table has no trim command (the trim is the joystick's rocker), so trim needs no laptop key.

**The mouse in the 3D cockpit.** The pointer works the cockpit's controls (`Settings.cockpit_controls()`,
[cockpit.md](cockpit.md) §5.1): over a control it lights it, the wheel and a left drag turn a knob, a left click
works a switch, each through the key's own command. The F-16s' controls: the SYM wheel, the HUD's brightness, which
Shift + H also steps (its position kept in the sim's settings file, not in the device store), and the start-up
checklist's switches (MAIN PWR, JFS, the throttle, the AVIONIC POWER switches, the INS knob, the canopy handle;
[cockpit.md](cockpit.md) §5.2). The checklist card names each step's switch and its place under its line, beside the
key.

| | English | Hebrew |
|---|---|---|
| Pitch up rebound to K | ![The Keys screen: the Flight group, Pitch up on K with its Default](pictures/front-end/keys_en.jpg) | ![The Keys screen in Hebrew, mirrored](pictures/front-end/keys_he.jpg) |
| K pressed for Pitch down | ![The conflict line under Pitch down: Swap, Use it here, Cancel](pictures/front-end/keys_conflict_en.jpg) | ![The conflict line in Hebrew](pictures/front-end/keys_conflict_he.jpg) |

### 9.2 Joystick

With no joystick connected the Devices section's Joystick row is greyed, its Change off, and it says "No joystick
connected."; it comes alive when one is plugged in (`Input.joy_connection_changed` builds the section again). Tests see
only their fake joysticks (`Joystick.device()`).

- **Devices:** every connected joystick by name. The first one flies the jet ("Flies the jet"); the others are listed
  only. Without one the screen says so.
- **Axes:** the six axes Godot reports (fewer when the device's USB descriptor says so, `Joystick.axis_count`). Each
  row has a live bar, the axis' role, Invert and a dead zone (0–50 %). The roles: Roll, Pitch, Throttle, Rudder, Roll
  trim (the throttle rocker, docs/controls.md §5.2), None. A role sits on one axis: giving it to another axis leaves
  the old one with None. The bar shows the axis after its role's invert and dead zone, so the dead zone is visible
  as the bar's still centre. The throttle has no centre and no dead zone.
- **Buttons:** the Keys screen's list with the joystick's buttons. Click a row, then press a button or a hat
  direction. Conflicts, Default and Reset all work as on the Keys screen. The hat's four directions count as buttons
  (Hat up, Hat right, Hat down, Hat left); by default they are the four look keys (up, right, back, left).
- **Reset all** puts the buttons and the axes back to the defaults.

The Joystick screen has no rows for the Devices group's choices (Flight controls, Rudder, Throttle, Stick response):
they stay in the Preferences. A role with no axis leaves its keys working, as Keyboard does: with Roll on None and
Pitch on an axis, the roll keys roll the jet while the stick pitches it (`Joystick.stick_mixed`).

| English | Hebrew |
|---|---|
| ![The Joystick screen: the Hotas X flies the jet, six axes with their bars, roles, Invert and dead zones](pictures/front-end/joystick_en.jpg) | ![The Joystick screen in Hebrew: mirrored, the bars still fill left to right](pictures/front-end/joystick_he.jpg) |

In Hebrew the screens are mirrored; the key names and the device name run left to right, and the axis bars keep the
stick's own direction (right is right). The dropdowns draw the same box both ways: right to left Godot draws an
OptionButton's `*_mirrored` boxes, so `look.gd` sets them to the left-to-right ones.

### 9.3 Device maps

A known joystick gets its own defaults from a device map in `modern-iaf/data/devices/` (JSON): `match` (a part of the
device's name, case ignored), `axes` (role → Godot axis) and `buttons` (key-table record → button, the hat 32–35). The
map replaces the table's whole button column for that device: a record it leaves out has no button. The first map
whose `match` is in the name wins (file-name order); a device with no map takes the table's own buttons and axes 0–4.

| file | device | axes | buttons |
|---|---|---|---|
| `hotas_x.json` | Thrustmaster T.Flight Hotas X | roll 0, pitch 1, throttle 2, rudder 3 (the twist), roll trim 4 (the rocker, 5-axis mode) | 1 gun, 2 release, 3 next target, 4 flares, 5 chaff, 6 master mode, 7 radar mode, 8 drop lock, 9 gear, 10 flaps, 11 wheel brakes, 12 autopilot; the hat: the look keys |

The Hotas X's axes are the ones docs/controls.md §5.2 found on that stick. The button choice is ours (inferred: the
trigger fires the gun, the buttons next to it release and pick targets).

### 9.4 The device store

The store is `user://devices.json`, written compact and only with what differs from the defaults:

```json
{"keys":{"24":37},"buttons":{"64":5},"axes":{"pitch":{"axis":3,"invert":true,"dead":0.1},"rudder":{"axis":-1}}}
```

- `keys`: record → key, DIK | modifiers << 16 as `key_table.gd` stores it (0 = no key).
- `buttons`: record → the joystick's 0-based button, 32–35 the hat, −1 = none.
- `axes`: role (`roll`, `pitch`, `throttle`, `rudder`, `trim`) → `axis` (−1 = none), `invert`, `dead` (0–0.9). An
  absent field is the default: the device map's axis (else 0–4 in role order), no invert, and the dead zone of
  `joystick.gd` (25 % on the stick and the rudder, 5 % with Stick response Soft centre, 10 % on the rocker). A dead
  zone outside 0–0.9 in a hand-edited file reads as its nearest end.

A missing or corrupt file reads as an empty store: every default.

Tests and pictures use a temporary file (`Settings.devices_path`, or in isolated runs a file of the process in the
temporary folder, so no run reads another's).

The logic is Rust's: `iaf_tools::devices` (unit tests in the same file) behind `IafDevices`
(`crates/iaf-godot/src/devices.rs`):

| function | does |
|---|---|
| `find_map(dir, name)` | the device map for a joystick's name, "" = none |
| `keys(table, store, map)` | the key table with the map's buttons and the store's keys and buttons in it, each record with `default_key` and `default_joystick` |
| `conflict(table, store, map, record, column, value)` | the other record bound to `value` in `column` ("key" / "button"), −1 = none |
| `bind(table, store, map, record, column, value)` | binds and writes; the entry goes when it is the default again |
| `reset(store, record, column)` | one record (−1: every record) back to its default |
| `reset_joystick(store)` | every button and axis back |
| `axes(store, map, soft)` | every role's axis, invert and dead zone |
| `set_axis(store, map, role, axis, invert, dead, soft)` | sets a role; a role on that axis gives it up |

How the flight reads it:

- **Keys and buttons:** the flight's key table is `KeyTable.load_table()`, whose contents come from
  `Settings.key_table_data()`. The original game returns the file as it is; the sim returns `IafDevices.keys` over
  its own table, the connected joystick's map and the store. The flight loads it at its start and again when the
  Preferences close over it (`terrain_view.gd _apply_preferences`).
- **Axes:** `Settings.apply_devices()` (at start, on every Preferences save, when a joystick connects) sets
  `Settings.joy_axes` to the roles' axes, `Joystick.tune` to their invert and dead zone, Roll trim on while the trim
  role has an axis, and `Joystick.hat_buttons` (the hat as buttons 32–35 in place of the original's snap views).
  `joystick.gd` reads them each poll. The original game leaves `tune` empty and `hat_buttons` off, so its joystick is
  unchanged (`tests/godot/test_joystick.gd`, `test_controls.gd`, `test_keyboard_stick.gd`).
- **The maps' folder:** `Settings.joy_maps_dir()`: the original game's `menu/joy` in the install (its `.joy` files),
  the sim's `modern-iaf/data/devices`, where the shared `.joy` reader finds none and so reads no install. A missing
  folder is skipped.

### 9.5 Checks

- `modern-iaf/tests/test_devices.gd`: the Devices rows open both screens in English and Hebrew; Pitch up bound to K by a
  synthetic key reaches the flight's key table; K for Pitch down shows the conflict, Swap trades them; Esc cancels;
  Default and Reset all; with a fake joystick, axis 4 given the pitch inverted with a 10 % dead zone drives the
  poller's stick y (+100 at +1, 0 inside the dead zone, +50 at 0.55); a button and the hat bound by pressing them;
  the Hotas X's map; with `Settings.laptop_keys` on, the laptop map: the rudder on Z / X, no key on two records, no
  numpad key, a stored key wins over it. `iaf-sim own`'s unit test checks the laptop table compiles the same way.
- `modern-iaf/tests/test_m0_boot.gd` connects a fake joystick: the probe's gate line stays at 0 refused paths.
- `modern-iaf/tests/_devices_shot.gd` takes §9's pictures (its header).

## 10. The mission briefing

Selecting a mission on Pick a mission shows its briefing beside the list (the user, 2026-11-09: "briefing, with map,
when selecting a mission"; his verdicts A14 the same day gave it its pages). Three tabs at its top, Briefing, Map and
Arming (חימוש), switch the pages; so do the arrow keys (toward the inline end: the next page), except while the map has the
focus. The page shown stays for the next mission picked. Fly / לטוס beside the tabs starts the mission from any page.

**Briefing:**
- **The heading:** the title (the mission's kind) and the jet's subtitle (§4).
- **The facts:** the runway end and its true heading ("25R · 254°"; a take-off only), the time as military time
  ("0800"), the wind as pilots read it, direction and speed ("250° / 8 kt", "250° / 8 קשר"; calm is "000° / 0 kt"),
  from the mission's `wind_from` and `wind_kt`, the time allowed. Both languages keep the digits left to right.
- **Objectives:** what the scorer judges ([training.md](training.md) §3), in the rules' figures: a start-up's engine
  at idle and avionics up; a take-off from its runway and the climb-out with the gear up on the runway heading
  (`heading_tolerance_deg`); then the time allowed and the at-once fails (§3.0).
- **How:** the steps, each with the key as bound, the switch and its place, and the state to wait for (the user,
  2026-11-09). A start-up's are its checklist (the rules' `checklist`, [training.md](training.md) §7.1): the line, its
  `where` (the switch's name as the panel labels it and its panel) and its `wait` (the JFS's 20 % RPM, the idle with
  the main generator, the INS's 90 s), the same data the in-flight checklist card shows. A take-off's are its
  `steps` ([training.md](training.md) §8): each call to the tower on its own at its place (request start-up, start the
  engine, request taxi once at idle with the avionics up, taxi short of the runway, request take-off), its key with
  the menu's pick ("Ctrl + T, 2") and the tower's answer to wait for, then the take-off on the runway heading with the
  gear up.
- **The facts' figures:** each value's figures are a label of their own, left to right, and its unit a label beside
  them, so "16,069 / 23,582 ק״ג", "000° / 0 קשר" and "25R · 247°" keep their order in a Hebrew line.

**Map:** one map over the whole page, north up, that zooms and scrolls. The mouse wheel zooms around the pointer
(1× to 32×, 1.25× a notch), a drag scrolls, a double click shows the whole map again; with the focus (a click on the
map), + and − zoom, the arrows scroll and 0 resets. The view stays on the map. It draws:
- the theatre's ground colour (its level-5 colour nodes, 32 m a pixel, [terrain.md](terrain.md) §3, resampled once
  by `IafBriefing.ground`; without them the TSD map's polygons, `converted/own/cockpits/<jet>/map.json`,
  [data-formats.md](data-formats.md) §14);
- the main roads (motorway to secondary, the theatre's road layer `roads/main.bin`, [data-formats.md](data-formats.md)
  §15) over a dark casing;
- the towns' names in the game's language (OpenStreetMap's places, `places.json`; the villages only where fewer than
  six towns and cities are in the map; a name that would cover an earlier label is left out);
- the whole airbase as filled shapes: the aprons and the shelters' pads, the taxiways and the stopways at their
  widths, the runways at their widths; zoomed in (from 0.15 px a metre) their dashed centrelines, the parking spots,
  the runways' designators at their ends and the start spot's label;
- the taxi from the parking spot to the lineup as a dashed line (the base's departure route, the one the sim's AI
  taxis), the start, the route from the lineup through the mission's waypoints with an arrow, the runway end and its
  heading beside the first leg, the base's label at the whole map's zoom.

The whole map holds the runways, the start and the route with 6 km around them, at least 50 km across. A north arrow
(true north: the map is UTM 36N's grid, about 1° off) and a scale bar (100 m to 50 km, the longest within a quarter
of the width) follow the zoom. The map never mirrors; in Hebrew its north arrow and scale bar swap corners. Its
credit, OpenStreetMap's, is in the footer on this page. Tested 2026-11-09 and dropped: the area beside a separate close-up of the
base; one zoomable map shows both and leaves each the whole page (the user's A14, round 4).

**Arming:** the jet's name, type and tail number ("Sufa · F-16I · 482"; the Latin and the digits in isolates, so
Hebrew reads "סופה · F-16I · 482" in order), its front view in light lines traced from our own
model (`modern-iaf/data/drawings/<jet>_front.png`: the Sufa from `f16i.glb` with its two seats, conformal tanks and
spine, the Barak from `f16d.glb`, the Adir from `f35i.gltf`; `modern-iaf/tests/_jet_fronts.gd` renders each from the
front with its surfaces coloured by their normals and traces the edges 2–3 px wide; `<jet>_front.json` places the
stations, the model's hardpoints `F16_SIM_STATIONS` and the Adir's descriptor stations projected, its bay stations
where the bays open under the fuselage), centred, as wide as the room left by the slots (at most 62 % of its width). Under the jet, one
slot per station (after the original's Arming screen, [the original's front end](../../docs/front-end.md) §15: a box per station in station order,
joined to its station by a line): a thin rounded frame, 88 × 80 px for every station of every jet, with the
station's number on its top edge, the store's side view fitted by its longest side into one 76 × 24 px picture box
(the same box for every store, so a drop tank and a missile take the same room; the user, 2026-11-10;
`modern-iaf/data/stores/<weapon id>.png`, our store models rendered by `modern-iaf/tests/_store_pictures.gd`) and its
short name under it on up to two lines ("AIM-9M", "370 gal drop tank", "בידון 370 גלון"; also the tooltip). An empty station shows its
empty slot. The wing stations' slots form one row in station order, 9 to 1 left to right as the front view shows them;
the inboard stations' (4, 5, 6: the drop tanks) a second row, each straight under its station. Each slot's leader runs
straight up to its station, or up to the station's height and across to it, none crossing another
(`menu/arming_drawing.gd`; each slot is a Control of its own, so a drop target per slot is a small step later). The
drawing never mirrors: station 1, the left wing tip, is on the viewer's right. The stores are the unit record's fixed loadout (`pylons`,
[data-formats.md](data-formats.md) §3; the Sufa and the Barak: an AIM-9M on 1, 2, 3, 7, 8 and 9, a 370 gal drop tank
on 4 and 6; the Adir: an AIM-120 on 5 and 7). The Adir's eleven stations but 6: its bays' four (the record's
`internal`) form the second row, side by side under the fuselage, each marked "internal" / "פנימי" on its bottom
edge; the empty wing stations' slots the first row, three each side clear of the bay leaders; every leader runs straight
from its slot's top to its station, a fan that crosses none.

**The inventory:** a column on the drawing's block-end side (the right in English, the left in Hebrew), 150 px wide,
headed "Available" / "זמין": the stores the jet may carry (the record's `inventory`), grouped under small headings
air-to-air, air-to-ground and drop tanks (by the weapon's kind), each its picture in the slots' picture box, its caption and
the record's count (none given yet, so none shown). Display only; each entry is one Control (`arming_drawing.gd`
`Item`), so dragging it onto a slot is a small step later (the user, 2026-11-10). Under the drawing, centred: the gun's rounds, the chaff, the flares (`loadout`),
the internal fuel (the 6-DoF jet's, `iaf_flight::sixdof::jets`), the take-off weight (the 6-DoF's empty weight +
internal fuel + the stores' `kg`) and, a field of its own, the jet's maximum weight (the record's `max_takeoff_kg`; the
Sufa: 16,069 kg and 23,582 kg). `IafBriefing.arming(unit, weapons)` answers the figures (`briefing::arming`).

The footer carries a credit on the Map page only, OpenStreetMap's, at the footer's inline end (right in English, left
in Hebrew) in 16 px type. The Arming drawing is our own render of our own models; the attribution those models need
(the FlightGear F-16, GPL; andertan's F-35, CC BY 4.0) is in docs/credits.md, the setup wizard's Attributions and the
credits roll.

The geometry is Rust's: `iaf_tools::briefing` (`crates/iaf-tools/src/briefing.rs`) behind `IafBriefing.map(mission,
airbases, map, aspect)` (`crates/iaf-godot/src/briefing.rs`) reads the readable mission, the airbase files and the
compiled map, and answers the map in its own metres (x east, y south from its north-west
corner):

| key | meaning |
|---|---|
| `base`, `runway`, `heading` | the base's name, the take-off runway end and its true heading (null for a start-up) |
| `north` | true north as a grid bearing (deg) |
| `size`, `extent` | the map's width and height (m) and its box in the sim's frame, at the screen's aspect: the runways, the start and the route with 6 km around them, at least 50 km on the shorter side |
| `fills` | the map's polygons cut to the map, in paint order: `color` and `tris` (triangles, `iaf_formats::emf::fill_triangles`, as `IafEmf`) |
| `runways` | each `[x0, y0, x1, y1, width, designator 0, designator 1]` |
| `taxiways`, `stopways`, `aprons`, `shelters`, `parking` | the base's paved shapes (`{w, pts}` for a taxiway) and spots |
| `roads`, `places` | the map's main roads (`{class, pts}`) and towns (`{kind, en, he, at}`) |
| `start`, `taxi`, `route` | the start; the taxi (the base's departure route, `sim_bases::routes`, when the runway is the base's take-off end); the lineup and the waypoints |

`IafBriefing.ground(theatre, extent, width)` answers the area's ground colour as {w, h, rgb} (`briefing::ground`).
`IafBriefing.arming(unit, weapons)` answers the Arming page's figures (`briefing::arming`).
`modern-iaf/menu/briefing_map.gd` draws the maps. `modern-iaf/tests/_briefing_shot.gd` takes the pictures (its header).

| | English | Hebrew |
|---|---|---|
| start-up at Ramon (2011) | ![The start-up's briefing](pictures/front-end/briefing_2011_en.webp) | ![The start-up's briefing in Hebrew](pictures/front-end/briefing_2011_he.webp) |
| take-off from Ramon (2012) | ![The take-off's briefing](pictures/front-end/briefing_2012_en.webp) | ![The take-off's briefing in Hebrew](pictures/front-end/briefing_2012_he.webp) |
| the take-off's Map page | ![The take-off's map](pictures/front-end/map_2012_en.webp) | ![The take-off's map in Hebrew](pictures/front-end/map_2012_he.webp) |
| the map zoomed in on the start | ![The map zoomed in on Ramon](pictures/front-end/map_zoom_2012_en.webp) | ![The map zoomed in, Hebrew](pictures/front-end/map_zoom_2012_he.webp) |
| the take-off's Arming page | ![The Sufa's front view with its stores](pictures/front-end/stores_2012_en.webp) | ![The Sufa's arming in Hebrew](pictures/front-end/stores_2012_he.webp) |
| the Barak's Arming page (take-off from Ramat David) | ![The Barak's front view with its stores](pictures/front-end/stores_f16d_en.webp) | ![The Barak's arming in Hebrew](pictures/front-end/stores_f16d_he.webp) |
| the Adir's Arming page (take-off from Nevatim) | ![The Adir's front view](pictures/front-end/stores_f35i_en.webp) | ![The Adir's arming in Hebrew](pictures/front-end/stores_f35i_he.webp) |
