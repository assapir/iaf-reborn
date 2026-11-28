# Modern IAF's front end

**Terms:** front end = the screens before and after a flight; inline start / end = the side a line of text starts / ends
on (the left / right in English, the right / left in Hebrew); debrief record = the scorer's JSON for one flight
([training.md](training.md) §4); pilot log = the record of every attempt ([training.md](training.md) §9).

The front end (item [E2](plan.md#e2-the-front-end)) is the sim's main scene, `modern-iaf/main.tscn`. `./start-modern-iaf` opens it.
It builds the round-3 design the user approved on 3 November 2026: one screen per step, in Hebrew and English, with the
Heebo font. Since 13 November 2026 it wears the roundel-blue theme (§4) and opens on the Hangar (§12), the first screen
of the menu redesign the user approved then (A25).

```sh
./start-modern-iaf                     # the Hangar (the first start: the Pilot screen makes the profile first)
./start-modern-iaf -- --mission 2011   # flies that mission at once, then shows its debrief
```

The window opens on the start's splash (approved by the user on 26 November 2026, A128), the same in every language: on
the front end's background colour (#00163C), the logo's English horizontal lockup with "Modern IAF — loading…" under it
in the normal text, then the Hebrew lockup with "הזרוע הארוכה — בטעינה…", centred (each lockup 112 px tall on the
1080-high canvas). Godot shows it as the boot splash from the window's first frame (`project.godot`
`application/boot_splash/image`, `branding/splash.png`, scaled to the window keeping its shape). The front end then
draws the same splash (`front_end.gd splash`, `_loading_line`) before it builds the first screen, so the window keeps
showing it while the build and the first screen's shader compiles hold the main loop (about 3.5 s on the laptop's first
start; a Mac compiles shaders about ten times slower, §7); the Hangar then takes its place.
`modern-iaf/tests/_splash_shot.gd` draws `branding/splash.png` from the front end's splash: run it again when the logo,
the line or the theme changes.

## 1. The screens

| screen | what it does | English | Hebrew |
|---|---|---|---|
| Hangar | the first screen (§12): the jets at the inline start, the picked one in 3D in the middle (the player looks at it from any side) with its full name faint behind it, its card at the inline end (squadron and base, facts, Fly to the Missions screen); Settings and the pilot in the top bar, Attributions, Manuals and Quit at the foot | ![Hangar](pictures/front-end/hangar_en.webp) | ![Hangar, Hebrew](pictures/front-end/hangar_he.webp) |
| Missions | the Hangar's Fly (§2): a card per section, Training, Campaign, Single missions and Scramble, each with its number, its title and the pilot's progress in it (Training: the jet's course, lessons passed of 47); a section without missions greyed, "Coming later", out of the focus, without a click; Scramble (§2.1) shows no progress; the footer's Back (Esc) | ![Missions](pictures/front-end/missions_en.webp) | ![Missions, Hebrew](pictures/front-end/missions_he.webp) |
| Training | Training on the Missions screen (§2.2): the Hangar jet's course as eight phase cards in two rows of four, each with its number, its title and its lessons passed of all; under the title the course's lessons passed of all; a card opens its lessons; the footer's Back (Esc) | ![Training](pictures/front-end/training_en.webp) | ![Training, Hebrew](pictures/front-end/training_he.webp) |
| A phase's lessons | a phase card (§2.2): the phase's lessons numbered 1.1, 1.2 …, each with its title, one line on what it trains and the pilot's best grade (Pass, Marginal, Unsatisfactory, Not flown yet); beside the list a panel on the lesson under the focus or the pointer; the footer's Back (Esc) | ![A phase's lessons](pictures/front-end/lessons_en.webp) | ![A phase's lessons, Hebrew](pictures/front-end/lessons_he.webp) |
| A section's list | Campaign's and Single missions' list (none built yet): the Hangar jet's missions of the section in order, numbered 1, 2 …: the title, the base and what it trains, the last result (Pass with the best time, Fail, Not flown yet); the next one to fly marked Next, tinted and focused (every mission passed: no Next, the first focused); beside the list a panel on the mission under the focus or the pointer (§2); the footer's Back (Esc) | ![A section's list](pictures/front-end/section_en.webp) | ![A section's list, Hebrew](pictures/front-end/section_he.webp) |
| Briefing | the briefing, map first (§10): the map over the screen, opened on the base and the route with the pins; the mission card (the facts, the objectives, the Arming summary with Edit, Back to the section's list, Arming, Fly: Edit and Arming open the Loadout screen §10.1); what you will learn and how to fly it, the keys as bound; the map's chips | ![Briefing](pictures/front-end/mission_en.webp) | ![Briefing, Hebrew](pictures/front-end/mission_he.webp) |
| Settings | the search; the sections Graphics, Language, Updates (Updates on start: Ask / Always download / Never, ../../docs/release.md §7), Sound and Devices with their counts at the inline start; the picked one's settings beside them as segmented buttons, switches and sliders, Graphics with its Preset row and a cost chip per row; the pane at the inline end on the hovered setting (§14; none on Updates: the game manual explains it, the user 25 Nov 2026); Devices has the afterburner detent (§9.2); the footer's Defaults, Export settings file / Import settings file (below) and Back to the hangar | ![Settings](pictures/front-end/prefs_graphics_en.webp) | ![Settings, Hebrew](pictures/front-end/prefs_graphics_he.webp) |
| Debrief | the sheet at the inline start (Plane flown, From, Time, Mission, Result; the goals with the target, the flown figure and ✓ / !; Remarks with "Next time:"), at the inline end the whole flight on the map and the flight's graphs (§13); Pilot log, Export flight data (below), Back to missions, Fly again, Next mission (§2) | ![Debrief](pictures/front-end/debrief_en.webp) | ![Debrief, Hebrew](pictures/front-end/debrief_he.webp) |
| Pilot | the Hangar → the pilot: the name and the nickname, the enemy's skill (Low / Medium / High), under them the picture in a service ID photo's fixed 3:4 frame (a click on it, or Choose a picture…, opens the system's file dialog; without a picture the initials, or a head and shoulders before there is a name), and beside that column the logbook panel down to the bottom bar (§3) with its Pilot log button, and once the pilot has flown combat the four combat totals and More stats (§3); the footer's Reset the log, Delete profile, Change pilot, Back and Save (§3) | ![Pilot](pictures/front-end/pilot_en.webp) | ![Pilot, Hebrew](pictures/front-end/pilot_he.webp) |
| Create your pilot | the first start, before the Hangar: the Pilot screen with Save only and no pilot in the top bar yet; the logbook panel says "No flights yet." (§3) | ![Create your pilot](pictures/front-end/pilot_first_en.webp) | ![Create your pilot, Hebrew](pictures/front-end/pilot_first_he.webp) |
| Reset the log | the Pilot screen's Reset: a warning modal, then a second confirm (§3) | ![Reset the log](pictures/front-end/pilot_reset_en.webp) | ![Reset the log, Hebrew](pictures/front-end/pilot_reset_he.webp) |
| Pilots | the Pilot screen's Change pilot: every pilot with a name, the active one marked Current; New pilot (§3) | ![Pilots](pictures/front-end/pilots_en.webp) | ![Pilots, Hebrew](pictures/front-end/pilots_he.webp) |
| Pilot log | the Pilot screen → Pilot log: every attempt, newest first, its day as the debrief writes it and the time ("2 Nov 2026 · 08:14", "2 בנובמבר 2026 · 08:14"); two filters, a jet and a mission (those flown, "All jets" / "All missions" first; with a jet picked, only its missions; a filter the pilot's log does not hold, kept from another pilot, falls back to All); a row opens its debrief; the footer's Back (Esc) to the Pilot screen | ![Pilot log](pictures/front-end/log_en.webp) | ![Pilot log, Hebrew](pictures/front-end/log_he.webp) |
| More stats | the Pilot screen → More stats (every combat flight; a debrief's More stats shows that flight): air kills and ground targets by type, the weapons fired and their hits (missiles, bombs, the gun's rounds), the jets lost by cause as counts, how many of them were the flight's other jets, the ejections; from the Pilot screen also each combat flight; the footer's Back (Esc) (§3) | ![More stats](pictures/front-end/more_stats_en.webp) | ![More stats, Hebrew](pictures/front-end/more_stats_he.webp) |
| Manuals | the four manuals' list ("מדריכים" in Hebrew; [manuals.md](manuals.md)); with the game in Hebrew the game manual's row opens its Hebrew edition (`manuals.json` `of`, `lang`), the jets' rows the English manuals, and the line under the title says so; the Hangar's foot opens it, a row opens its PDF in the system's PDF viewer (`OS.shell_open`; the PDFs of a source checkout, `modern-iaf/manuals/pdf/`), a row whose file is missing is greyed; the footer's Back (Esc) | ![Manuals](pictures/front-end/manuals_en.webp) | ![Manuals, Hebrew](pictures/front-end/manuals_he.webp) |
| Attributions | the game's version under the title ("Version 0.2.0-nightly.…", "dev" in the checkout; docs/release.md §3); the setup wizard's list of sources and licences, the jet models with them; the Hangar's foot opens it ("קרדיטים ורישיונות" in Hebrew); the arrows and Page Up / Down scroll it (Down at its end reaches Back), and with the focus the list wears the rows' accent ring (look.gd `ListScroll`; none until 2026-11-16); the footer's Back (Esc) | ![Attributions](pictures/front-end/credits_en.webp) | ![Attributions, Hebrew](pictures/front-end/credits_he.webp) |
| Hangar without data | a fresh install before `./modern-iaf-setup` (no missions built): the card says what is missing and the command (`./modern-iaf-setup`; Windows `.\modern-iaf-setup.ps1`) under the facts; Fly greyed and out of the focus, the picked jet focused; the F-16s' still pictures (§12) | ![Hangar without data](pictures/front-end/nodata_hangar_en.webp) | ![Hangar without data, Hebrew](pictures/front-end/nodata_hangar_he.webp) |
| Loadout | Edit on the briefing's Arming summary (§10.1): the jet from beneath with a callout per station, the loadouts (the mission's, the pilot's saved ones), the take-off weight and the stores; Reset to the mission's, Briefing, Fly | ![Loadout](pictures/front-end/loadout_f16i_en.webp) | ![Loadout, Hebrew](pictures/front-end/loadout_f16i_he.webp) |
| Missions without data | the same note under the title, every section greyed; the Hangar crumb focused | ![Missions without data](pictures/front-end/nodata_missions_en.webp) | ![Missions without data, Hebrew](pictures/front-end/nodata_missions_he.webp) |

At a training mission's goal the flight pauses under a panel in the pause menu's look: "Mission accomplished" /
"המשימה הושלמה בהצלחה", a line saying the pass is kept, and two buttons (the user, 2026-11-15: "it pause and show
'continue/debrief' buttons"):
- **Continue the flight** (focused; Enter, a click or the gamepad's accept) resumes the flight. The panel does not come
  back in that flight, and the pass stays stored. Esc also continues, so Esc never ends the flight by accident.
- **Debrief** ends the flight into its debrief, as the pause menu's End the flight does.

The panel waits until the radio has said every line already queued (the tower's last answer), so the pause never cuts
a voice; the flight runs on meanwhile. The pilot's notebook (H) and the radio menu are put away when the panel opens.
A fail ends the flight about 5 s later into its debrief, the reason first, with nothing over the view meanwhile (the
fail banner went on 2026-11-25: only radio over the flight; [training.md](training.md) §9).

Over a flight, Esc opens the pause menu: the mission and the jet flown ("Take-off · F-16I Sufa"), then Continue the
flight, Settings, End the flight, Quit to desktop ("יציאה לשולחן העבודה"; it asks "Quit the sim?" first; the user,
2026-11-17: "we don't have a quit button"). It is laid out on the
front end's canvas scaled to the window and centred by a container, so it sits in the middle at any window size and in
either language (the Mac run of 2026-11-08: in Hebrew in a 2560 × 1440 window the overlay mirrored its own position
by its unscaled width and sat off the right edge, its buttons' labels outside the screen). Ending a training flight
scores it as it stands and opens its debrief; a flight that was not scored goes back to the Hangar. The sheet shows only
the record's `checks` ([training.md](training.md) §4); every other number stays in the record file.

| the Hebrew pause menu before the fix (2026-11-08) | after |
|---|---|
| ![The pause menu shifted left, the dim cut off at the right](pictures/front-end/pause_he_before.webp) | ![The pause menu centred](pictures/front-end/pause_he.webp) |

| screen | English | Hebrew |
|---|---|---|
| the pause menu over the flight | ![Pause menu](pictures/front-end/pause_en.webp) | ![Pause menu, Hebrew](pictures/front-end/pause_he.webp) |
| the Settings over the flight: the front end's top bar (the crumb Paused goes back to the pause menu) and a footer with Back | ![Settings over the flight](pictures/front-end/flight_prefs_en.webp) | ![Settings over the flight, Hebrew](pictures/front-end/flight_prefs_he.webp) |
| a training mission accomplished: the flight paused | ![Mission accomplished](pictures/front-end/accomplished_en.webp) | ![Mission accomplished, Hebrew](pictures/front-end/accomplished_he.webp) |
| a failed debrief from before the goals and the recording (a take-off with the gear never raised): its numbers, the right column's empty state | ![Failed debrief](pictures/front-end/debrief_fail_en.webp) | ![Failed debrief, Hebrew](pictures/front-end/debrief_fail_he.webp) |
| the debrief of that flight | ![Debrief after a flight](pictures/front-end/flown_debrief_en.webp) | ![Debrief after a flight, Hebrew](pictures/front-end/flown_debrief_he.webp) |

Keys: Enter picks the focused control, Esc goes one screen back (on the Hangar it asks "Quit the sim?", Cancel focused),
the arrow keys and Tab move the focus. The bottom bar holds a credit where a screen shows one (the Map's) and the
screen's buttons; it shows no key hints (the user, 2026-11-09: "this is
obvious and people will use mouse anyway"). Every breadcrumb in the top bar but the current one opens its
screen (the jet's name: the Missions screen, on the Missions screen itself the Hangar; Training: the phases; a section: its list; the
mission: its briefing); the picks are kept.

| screen | English | Hebrew |
|---|---|---|
| Settings: Graphics | ![Graphics](pictures/front-end/prefs_graphics_en.webp) | ![Graphics, Hebrew](pictures/front-end/prefs_graphics_he.webp) |
| Settings: Sound | ![Sound](pictures/front-end/prefs_sound_en.webp) | ![Sound, Hebrew](pictures/front-end/prefs_sound_he.webp) |
| Settings: Devices | ![Devices](pictures/front-end/prefs_devices_en.webp) | ![Devices, Hebrew](pictures/front-end/prefs_devices_he.webp) |
| Settings: Language | ![Language](pictures/front-end/prefs_language_en.webp) | ![Language, Hebrew](pictures/front-end/prefs_language_he.webp) |

## 2. The flow

The Hangar → Fly → Missions → a section → its list → the briefing (Arming ↔ the briefing) → Fly → the flight → the
debrief → Next mission, Fly again or Back to missions (the user's menu flow, 15 November 2026: one list on one screen
would not hold more than a few missions). Every start opens the Hangar with the jet picked last (flown or picked),
else the first, the Sufa; the earlier rule of no jet picked on entry (2026-11-09, 2026-11-11) went with Home and Pick a
plane, since the Hangar always shows a jet. Esc goes one step up: the briefing to its list, the list to Missions,
Missions, the Settings and Attributions to the Hangar, the loadout screen to the briefing, the debrief to its section's
list. The breadcrumbs: Hangar · the jet (Missions) · the section (its list) · the mission (the briefing) · Arming (the
loadout screen) or Debrief.

- **The sections** (`SECTIONS` in `front_end.gd`): Training, Campaign, Single missions and Scramble. Training holds
  the Hangar jet's course (§2.2); Campaign and Single missions hold the jet's missions of their `category` (the
  readable mission's: `campaign`, `single`); Scramble is the jet's Scramble start (category `fly_now`). A card, 320 px
  high, the row of cards in the middle of the room under the title, shows its number and title and at its foot the
  pilot's progress ("0 of 47 passed" and a bar). Training's progress is the course's lessons passed of all, counted
  per jet (`IafPilotLog.course_logbook`, a Marginal counted as passed); it is open whenever the jet has a course and
  opens the phases (§2.2). Scramble's card has no progress and opens the Scramble screen (§2.1). A section without
  missions is greyed, marked "Coming later" / "יגיע בהמשך", no click and no focus: today Campaign and Single missions.
  A card has no subtitle and no "What it holds" list (the user, 2026-11-16: "remove the subtitles and what it holds").
- **The training missions** (category `training`: each base's start-up, take-off and weapons range, and Ramon's
  four-ship) are listed in no section (the user, 28 November 2026: "The current existing train should be deleted,
  o/c. It replaces them"). Their files stay for the automated tests and `--mission <id>` runs
  ([training.md](training.md) §13).
- **Each jet's own missions** (the user, 15 November 2026: "you should show only the same plane missions"): a
  section lists only the missions whose start is in the Hangar's jet (the readable mission's `start.unit`), numbered
  1, 2 … after that filter. The statuses, Next, "N of M passed" and the side panel count that jet's missions only. A mission is flown in its own jet
  (`flight/fly.gd` `start(menu id)`); the debrief's Next mission is the next one of the flown mission's jet.
- **A section's list:** the missions in menu-id order with their last result (`IafPilotLog.summary`: Pass with the best
  time, Fail, Not flown yet). The next one to fly is the one after the last one flown, the first when none was; once
  the last one was flown, the first one not passed, else the first (`MissionList.after_last_flown`,
  `shared/mission/mission_list.gd`, the same rule reborn's Jump_In uses for the scramble missions). It is marked
  Next, tinted as a picked jet and focused; with every mission passed nothing is marked Next and the first is
  focused (F6, 2026-11-16: the first one was marked Next again). Enter or a click on a row opens its briefing. The panel beside the list
  follows the focus and the pointer: the mission's number and title, what you will learn (another section's: its
  purpose; the briefing's `briefing.purpose`, its keys as bound), its base, the time allowed, the last result with its
  day and the best time. It holds no map: the briefing's map is the briefing's own screen.
- **Back:** the Missions screen and a section's list have Back in the footer, the same button as every other
  screen's footer Back (`back_button`); Esc does the same. Tab reaches it after the cards or the rows, Down from the
  last row. No key cap on any button since 2026-11-16 (the user: "remove the back/esc hint"; until then Back carried
  an "Esc" cap).
- **The debrief's buttons:** Next mission (the mission after the flown one in its section, `MissionList.next_in`,
  reborn's Next Mission rule; absent after the section's last one), focused when there; Fly again (the flown mission's
  briefing with Fly focused: Enter or a click on Fly starts the flight); Back to missions (the section's list). Each
  picks the jet flown (the record's `plane`).

The Ra'am (F-15I, `f15i`) and the Baz (F-15C, `f15c`) are listed after the three flyable jets, disabled until the sim
flies them (the user, 2026-11-10 and A25): the row dimmed, no click, no focus, no text on why. Each row shows the full
name, the squadron's number and the base like the others (`SOON` in `front_end.gd`; the squadrons in the Hatzerim and
Tel Nof base files, airbases.md §3). Making one flyable moves its row from `SOON` to `JETS`.

- **The plane:** a row's click stores the unit (`Settings.sim_jet`: `f16i`, `f16d` or `f35i`; `settings.cfg` section
  `[sim]`, key `jet`) and sets the F-16 switch (`Settings.set_jet`).
- **The missions:** the compiled list `assets/converted/modern-iaf/missions/missionlist.json` (`iaf-sim missions`), each
  read from its readable file `modern-iaf/data/missions/<name>.json`, in its section by its `category`, in menu-id
  order.
- **Fly:** `flight/fly.gd` `start(menu id)` loads the compiled mission in its own jet and changes to the flight
  scene.
- **Export flight data** on a debrief copies the flight's recording (the record's `flight`, JSON lines) where the
  player picks in the system's file dialog, named `iaf-<the recording's name>`. Without that file (a record from
  before the recorder, or the file deleted) the button is greyed and out of the focus.
- **Export settings file / Import settings file** in the Settings footer (the front end's; the pause menu's Settings
  shows none) write the settings as they are to a `.cfg` file, or read one, store and save it at once by the sim's
  own rules (`sim_settings.gd`: the forced settings stay forced, the player's own values kept). Hebrew without its
  font falls back to English. The pilot flying and the jet picked stay this computer's.
  Both games share the file dialog and these rules: `shared/util/file_export.gd` (reborn's Extras Settings file, its
  debrief Export flight data and its Mission Creator LOAD, [../../docs/front-end.md](../../docs/front-end.md); the
  Pilot screen's Choose a picture… here).
- **The flight's end:** the flight scene returns to `Settings.front_end_scene()` (`res://main.tscn`). When the flight
  stored a sortie (`flight/sim_flight.gd` sets `Settings.flown_sortie`), the front end opens its debrief.

### 2.1 Scramble

Scramble (Hebrew הזנקה) is a quick fight, not a mission: the player's flight against an enemy drawn at random, the
task given by the AWACS by radio. The user, 22 November 2026, approving the AI jobs' order ("Ok follow your suggested
order"), whose last item was this setup; on its first version (A81), 24 November 2026: "1. call it "Scramble" and
הזנקה in hebrew. 2. where is based on the plane they choose, right? 3. by default, start in-air, with awacs calling or
giving orders what to bomb. 3. too much enemy options, should be some random selection." Scramble on the Missions
screen opens the Scramble screen (`menu/free_combat_page.gd`); its picks fly from the jet's Scramble start
(`data/missions/<base>_free.json`, a flight of four parked cold at the jet's home base), and the enemy is drawn and
placed in flight ([../../docs/ai.md](../../docs/ai.md) §23).

| English | Hebrew |
|---|---|
| ![Scramble](pictures/front-end/free_en.webp) | ![Scramble, Hebrew](pictures/front-end/free_he.webp) |

- **The screen:** the title, Scramble, and under it the home base the flight flies from (the base of the jet picked in
  the Hangar) and one line on what comes: the fight's area and the enemy drawn at random, the task and where from the
  AWACS. One panel, Your flight, of rows, each row a label and its segments, the one picked lit: Flight (Alone, Pair,
  Four-ship), Start (In the air; On the runway, engine running; Cold, at parking), Date and time (below). Under the
  rows one line names the enemy's skill, the Pilot screen's own value (docs/ai.md §17: "Enemy skill: Medium, as set on
  the Pilot screen."); it sizes the enemy, one to three threats beside the task's target.
- **His round-3 words** (2026-11-24, A81: "why we choose area if in all other places the area is tied to the
  airplane? why we choose a enemies skill if that already by pilot?"; then "allow it to start in cold, runway or in
  air"): the Area and Enemy skill rows went; the Start row has the three starts, in the air by default.
- **The time** (the user, 25 November 2026: "Add to scramble options: what time of the day is it. Or it should be
  random, wdyt?", then "No, do a specific military time to choose", then "And random"): the flight's start time, Israel
  time, as 24-hour military time HHMM (0630, 1415, 2200; `IafFreeCombat.clock`), left to right in both languages as the
  digits read: the hour's ▼ ▲ (an hour), the time, the minutes' ▼ ▲ (five minutes; round the clock,
  `IafFreeCombat.time_step`), then the Random toggle. Random dims the time and its arrows and keeps the set time for
  when it is off again; Fly draws the time from the Scramble's seed, any five-minute step of the day
  (`IafFreeCombat.start_time`). The flight starts at that time (misc `0x460`, `flight/fly.gd prepare_free`) on the
  date's day, so the sun, the sky, the city lights and the night cockpit follow it ([terrain.md](terrain.md) §17). The
  notebook's DATA page shows the flight's start time (the drawn one under Random). The AWACS's calls state no time (none
  of the AWACS calls we have sources for names one: modern-iaf/docs/research/radio-terms.md). Hebrew שעה, the notebook's
  term for the same thing (no other term was found in IAF usage for a start time's row).
- **One row, date first** (the user, 25 November 2026: "put the date and taim on the same row, date first, by default
  both should be random"): the date and the time share one row, Date and time (תאריך ושעה): the date's arrows,
  the date and its Random, a gap, then the time's arrows, the time and its Random (`free_combat_page.gd` `_when_row`).
- **The date** (the user, 25 November 2026: "Maybe we should add season, or date also?", then "Yes, but what about
  picking a year?", answered: no year now, the current year): the flight's day of this year, shown as the day and its
  month ("25 November", "25 בנובמבר"; `IafFreeCombat.month_day`), the day's ▼ ▲ (a day, round the year), the date, the
  month's ▼ ▲ (a month, the day cut to the month's last: `IafFreeCombat.date_step`), then Random; in Hebrew the row
  reads right to left. Random dims the date and its arrows; Fly draws a day of the year from the seed
  (`IafFreeCombat.start_day`, its own draw). The flight flies on that day with Israel's clock of the day (summer time
  included; `IafFreeCombat.utc_offset`, `time_of_day.gd` `year` / `day` / `utc_offset`): the date moves the sun's path
  and the day's length, so whether a set hour is day, dusk or night (0630: dark on 21 December, day on 21 June). The
  moon, the air's temperature, the haze and the weather do not follow the date ([terrain.md](terrain.md) §17). The
  notebook's DATA page shows the date ("21 December 2026"). Hebrew תאריך; the months by their Hebrew names in use
  (ינואר … דצמבר).
- **Not remembered** (the user, 25 November 2026: "No need to remember last choice"): each opening of the screen from
  the Missions screen starts with both Randoms on, under them 0800 today (`free_combat_page.gd` `reset`, `when`); a
  step or Random holds for that visit (Arming and back keep it) and is never stored in the settings.
- **The fight's area** is drawn at Fly with the enemy (`flight/fly.gd free_area`, `IafFreeCombat.area`): one of the
  theatre's bases other than the home base, alike from those within 180 km of it (inferred: a short sortie; from Ramon
  Nevatim, Hatzerim or Tel Nof, from Ramat David Tel Nof, Hatzerim or Nevatim). The AWACS's call says where.
- **The picks** of Flight and Start are kept at once (`Settings.free_combat`, `settings.cfg` `[sim]` `free_combat`); a
  first visit picks a pair in the air.
- **Refused here:** a load the one load rule blocks (weapons.md §7.1) gives the Loadout screen's line. Fly is off and
  the line, one short line in the warning colour at the footer, says why.
- **The footer:** Back (Esc: the Missions screen), Arming (the Loadout screen, §10.1, on the jet's Scramble start; its
  crumb Hangar · the jet · Scramble · Arming, its back button Scramble), Fly. Fly (here or on Arming) draws a new
  seed for the area and the enemy and flies the picks (`front_end.gd fly_free`, `flight/fly.gd prepare_free`: the
  start's flight cut to the size picked; in the air 60 km from the area for the air start; for the runway start lined
  up in pairs on the home base's runway, Kidon 1-2 15 m left of the lead, the second element 60 m behind, every
  engine running (the start rule's 100 m of the lineup point, docs/ai.md §7.1), and the take-off in pairs, docs/ai.md
  §8.7).
- **Keyboard:** Tab and Shift+Tab go through the segments row by row (the Date and time row's arrows and Randoms too),
  then Back, Arming, Fly; the arrows move by place; Enter or Space picks or steps.
- **The flight:** the AWACS gives the task once the jet is in the air ("Kidon 1, attack the convoy, bearing 040, 25
  miles, free to engage") and again every minute while its target lives. It is not scored and stores no sortie; it
  ends from the pause menu, back to the Hangar.
- **Checks:** `modern-iaf/tests/test_free_combat.gd`.

### 2.2 Training: the phases and a phase's lessons

Training on the Missions screen opens the Hangar jet's training course ([training-plan.md](training-plan.md) §5;
the course's data and logbook: [training.md](training.md) §13). Both screens use the existing screens' parts: the
Missions screen's cards and the section list's rows and side panel (Approvals A130 and A131, 28 November 2026).

- **The phases** (`_page_phases`): the crumbs Hangar · the jet · Missions · Training; the title Training with the
  course's lessons passed of all beside it ("0 of 47 passed", the same 47 for each jet). Under it the eight phases as
  the Missions screen's cards, two rows of four: each with its number (01–08), its title from the course
  (`IafTraining.course`, in the screen's language) and at its foot its lessons passed of its own with the bar. A
  lesson counts as passed with a Pass or a Marginal, per jet (`IafPilotLog.course_logbook`). Enter or a click opens
  the phase's lessons; Back (Esc) goes to the Missions screen. The focus starts on the first phase not yet passed
  (all passed: the first) and returns to the phase last opened (the user, A140, 28 November 2026).
- **A phase's lessons** (`_page_lessons`): the crumbs Hangar · the jet · Training · Phase N; the title "Phase N · its
  title" with its lessons passed of all. The rows, in the section list's look, are numbered phase.lesson (1.1, 1.2 …):
  the lesson's title, under it one line on what it trains (the course's `line`), and the pilot's best grade at the
  inline end: Pass or Marginal in the pass chip, Unsatisfactory in the fail chip, else "Not flown yet". Beside the list
  a panel on the lesson under the focus or the pointer: "Lesson p.l", the title, "What you will learn" (the line) and
  "Last result" (the best grade and its day, else "Not flown yet"). The focus starts on the first lesson not yet
  passed (all passed: the first). A lesson row opens nothing yet: its briefing
  (A132) comes next. Back (Esc) goes to the phases.
- **Checks:** `modern-iaf/tests/test_training_phases.gd` (English and Hebrew: the phases' names and counts, each
  jet's own count, the rows' numbers, lines and chips, the side panel following the focus, Back and Esc).

## 3. The data it reads

| what | where | written by |
|---|---|---|
| the sorties and their debrief records | `user://modern-iaf.sqlite` (tests: `<temp>/modern-iaf-records-<pid>/`, the run's own), `Settings.records_db()`, read through `IafPilotLog` ([storage.md](storage.md) §5) | `sim_flight.gd` at the scoring: the scorer's record plus `flight`, `date` (the end, local time) and `elapsed_s` (the flight's length, s) |
| the picked jet | `user://settings.cfg` `[sim] jet` | the front end |

The pilot's profile (the Pilot screen) is in the records database's `pilots` row ([storage.md](storage.md) §5): the
name, the nickname and the picture, a copy of the chosen file in `pictures/` beside the database. Every screen's top
bar shows the nickname, else the name, else the computer's user name; on the Hangar the nickname, the name under it and
the picture are one button (hover, pressed and focus in the crumbs' look) that opens the Pilot screen; with a picture, the picture in a small 3:4
frame in place of the initials' disc. The picture keeps square corners and no round mask, as a service ID photo; it is
cropped to fill the frame.

**The Pilot screen** (2026-11-10, the user's findings on it):

- **A draft until Save.** The name, the nickname and a newly chosen picture change nothing until Save (primary, at
  the footer's end, greyed without a name), which stores them and opens the Hangar; the picture file is copied beside
  the database then. Back (and Esc) opens the Hangar, after a modal "Discard the changes?" (Discard / Keep editing) when
  something changed; Change pilot and the Hangar crumb ask the same. The empty fields show hints ("Full name", "For example: Viper"): the nickname field used to show
  the pilot's name in grey, which read as text that no click could edit.
- **The enemy's skill** (2026-11-21, the user, 19 Nov: "wingman are always the same, it only effect enemeis, choosen
  from 3 options per player"): a row under the nickname, "Enemy skill" / "מיומנות האויב", three segments Low /
  Medium / High ("נמוכה / בינונית / גבוהה", the Settings' cost words). Part of the draft; Save stores it with the pilot
  (`IafPilotLog.set_skill`); a pilot who never picked, and every pilot from before, has Medium. It sets the enemy
  crews' reaction, drills, aim and launch range, never the wingmen's ([../../docs/ai.md](../../docs/ai.md) §17).
- **The radio voice** (2026-11-25, the user: "in the pilot preference, one should be picked male or female voice"):
  a row under the enemy's skill, "Your radio voice" / "הקול שלך בקשר", two segments Man / Woman ("גבר / אישה"). Part
  of the draft; Save stores it with the pilot (`IafPilotLog.set_voice`); a pilot who never picked, and every pilot
  from before, has a man's voice. It picks the player's own voice and the flight's cast ([sound.md](sound.md) §3.2).
- **The picture** opens the file dialog on a click, as Choose a picture… does. Without a picture the frame shows the
  name's initials as they are typed, and a head and shoulders (`Look.person_icon`) before there is a name (F1,
  2026-11-14: the first start's frame was empty).
- **The layout** (F6, 2026-11-16): one column holds the fields and the picture under them, and the logbook takes the
  rest of the width. Before, the fields stood in a middle column with nothing under Nickname. Since 2026-11-24 (the
  user: "you can make the left side (name, nick etc) a bit smaller, then choose pic button as the bottom of the pic")
  the column is 520 px wide (it was 640), its titles 22 px (25), the picture 240 × 320 (255 × 340), and Choose a
  picture… is the picture's bottom edge: as wide as the frame, right under it. Since 2026-11-25 the radio voice row
  takes the height the picture gave up: the picture is 165 × 220 and Choose a picture… 17 px, so the column fits a
  1080-high window above the bottom bar.
- **The keys:** Up and Down move between Name and Nickname (a text field keeps the arrows otherwise), Down from Nickname
  to the skill picked (a gamepad has no Tab). Tab goes the fields, the three skill segments, Choose a picture, More
  stats (when shown), the Pilot log, the bottom bar's buttons, the Hangar crumb, and round.
- **The logbook** beside the profile, a panel in the card look running down to the bottom bar (F1, 2026-11-14: the
  screen's lower 40 % was empty), its list scrolling inside (`IafPilotLog.logbook`): per plane flown, most hours first, its flight time
  (`clock`) and its flights, passes and fails, then each mission flown on it with its passes and fails. A sortie
  stored before the records kept its plane counts for its mission's jet (the readable mission's `start.unit`).
  Its **Pilot log** button opens the Pilot log, every attempt with its debrief: the one way there since Home's
  Pilot log entry went (the user, 2026-11-11). A jet's line counts its flights, passes and fails in the singular for
  one ("1 flight", "טיסה אחת", "כישלון אחד"; `counted`, a string's `_1` form).
- **The combat logbook** (2026-11-24, `combat_page.gd`, the approved mock wt/logbook-mock c6c14055; the records'
  `combat`, [storage.md](storage.md) §5): once the pilot has flown combat, the logbook's list starts with "Combat" /
  "קרב" and four totals of every flight, each a tile with its figure, its name and a line under it: **Air kills** /
  "הפלות" ("1 shared" / "משותפות: 1", "none shared"), **Ground targets** / "מטרות קרקע" ("destroyed" / "הושמדו"),
  **Hits** / "פגיעות" ("of 7 fired" / "מתוך 7 חימושים": the missiles and bombs; the gun's rounds are left out, a burst
  being hundreds), **Jets lost** / "מטוסים שאבדו" (the player's jet and the flight's other jets together: "1 shot down ·
  1 crashed" / "1 הופלו · 1 התרסקו"). These four were picked as the ones that answer "how did my fights go" (the user,
  24 Nov 2026: "too many stats. move the least relvant to some "more stats""). **More stats** / "סטטיסטיקה מפורטת"
  (the user's word, 24 Nov 2026) stands beside Pilot log and opens the page below. A pilot without combat sees
  neither.
- **More stats** ("combat" page): from the Pilot screen every combat flight, from a debrief that flight. Three columns
  in a panel: the air kills by type (a "N shared" chip) and the ground targets by type; the weapons in three groups,
  each with its verb and the hits (missiles "Fired" / "שוגרו", bombs "Dropped" / "הוטלו", the gun "Rounds fired" /
  "נורו": the user's words of 24 Nov 2026); the jets lost by cause (a SAM, AAA, a fighter, crashed), "Of them, the
  flight's other jets" / "מהם, משאר מטוסי המבנה", then the ejections. From the Pilot screen also the combat flights,
  newest first, each with its kills, targets and jets lost as chips. Back and Esc return where it was opened. A unit's
  name is its string (`unit_<type>`), else its record's label; a weapon's its store name.
- **Reset the log** (greyed with no flights) opens a modal, "Reset the pilot log?" / "לאפס את יומן הטיסות?", then a
  second one, "Reset for good?" / "לאפס סופית?"; each has Reset / לאפס and Cancel, Cancel focused and Esc closing it.
  Reset deletes the pilot's sorties and their debriefs; the name, nickname and picture stay.
- **Delete profile** opens a modal, "Delete the profile?" / "למחוק את הפרופיל?", then "Delete for good?" /
  "למחוק סופית?", each with Delete / למחוק and Cancel. Delete removes the pilot: its sorties and debriefs, its
  loadouts, its profile and its picture file (`IafPilotLog.delete_pilot`). The pilot list opens next, or Create your
  pilot when no other pilot is left.
- **The fields** show only their labels and hints, no text on where the nickname shows.
- **Several pilots.** Change pilot opens the pilot list: each pilot with a name (picture or initials, nickname, name),
  Current on the active one. A click makes that pilot active and opens the Hangar; New pilot opens the Pilot screen empty,
  and its Save makes the pilot and makes it active. The active pilot is `Settings.pilot_id`, kept in `settings.cfg`
  `[sim] pilot` (the default pilot 14 before any pick).
- **The first start.** While the active pilot has no name stored, the Hangar's place is taken by the Pilot screen titled
  "Create your pilot" with only Save (Esc stays), no pilot in the top bar yet (it showed the computer's user name) and
  the logbook panel saying "No flights yet."; Save stores the profile on the active pilot, its imported sorties
  kept, and opens the Hangar. When the records hold other pilots with a name, the pilot list opens instead.
- **The modal** is the sim's: the screen dimmed, a panel with the title, the text, the safe choice and the action;
  mirrored in Hebrew. The Hebrew texts are in the infinitive, gender neutral.

The debrief's number is its sortie's id, the sortie's place among all stored flights, oldest first. The Missions
screen's progress and the list's status and best time are `IafPilotLog.summary`'s, by menu id whatever jet flew it.
Its Time is the day, then the mission's clock from its start (the mission's `time`) to the start plus
`elapsed_s`. The pilot's name is the profile's nickname or name, else the computer's user name. The Remarks are
the record's fail reasons, then what its
numbers say: the lift-off speed against the reference speed for the weight, and the largest offset from the
centreline in the roll.

## 4. Look and layout

- **Palette** (the roundel-blue theme, the user's A25, 2026-11-13: "use the deep blue from the roundel"): background
  `#00163C`, panels `#001E50` (the roundel's blue as Wikimedia Commons draws it, not an official specification),
  raised panels and hover `#0A2A66`, fields `#00194A`, lines `#1D3A70`, borders `#5A73A3`, text `#F2F5FA` / `#A9B8D4`,
  the one accent `#5B8CFF` with `#001E50` on it, links `#A8C3FF`; the debrief paper `#f3efe6` with rules `#b9b09c`
  stays. Every text pair passes WCAG AA. All in `modern-iaf/menu/look.gd`, which builds the theme on the wizard's Heebo
  (`setup/wizard_theme.gd`); every sim screen (the front end, the loading screen, the pause menu, the flight's
  overlays) takes its colours from there. The setup wizard keeps Godot's default dark theme (`wizard_theme.gd`). Until
  2026-11-13: the round-3 slate (`#1d2025`, `#262a31`, accent `#6699ff`).
- **The logo** (the user's pick of 2026-11-19, concept 4 with the roundel E3, medium disc: four F-35s over the two
  names, a faint roundel behind the jets and the big name; `modern-iaf/branding/`, drawn by `tools/iaf-2026/logo.py`,
  credits in docs/credits.md "Modern IAF's logo"). The screens show its horizontal lockup (`bar_<lang>_dark`, the
  layout fix of 2026-11-19: the stacked one was too small to read in the bar): the mark (the four-ship over the faint
  disc, as in the app icon) on the inline start of the name in one line, MODERN IAF in English, הזרוע הארוכה in
  Hebrew. It is at the inline start of every screen's top bar, 64 px tall, at the top of the pause menu and the
  Mission accomplished panel (`front_end.gd` `_mark`), and in both languages on the start's splash
  (`front_end.gd splash`; the wizard's `Wizard.logo` draws it); its accessible name is the sim's name. The stacked
  lockup (`lockup_<lang>_<mode>`: in English MODERN IAF big with הזרוע הארוכה under it, in Hebrew the other way
  round) is on the manuals' title pages and the READMEs. The logo replaced the name in letters (`Mark`, Heebo 800 at
  28 px). The project's icon is the four-ship and the disc on the navy tile (`icon_256.png`: the window's and the Dock's
  icon). The start shows the sim's own splash, never Godot's logo (the intro).
- **A list that picks one** (the Hangar's jets): the picked row filled in the accent's tint, the focus a 2 px accent
  ring; no bar at the row's side (the user, 2026-11-13).
- **Sizes:** every screen lays out on a 1920 × 1080 canvas that the window shows scaled to its height (stretch mode
  "canvas items", aspect "expand"); the body text is 21 px, 1.9 % of the height, as in the mock-ups. The front end sets
  the scaling only while it is the scene, so the flight keeps the project's own. Over a flight the pause menu scales
  itself the same way.
- **Hebrew:** the front end's layout direction is right to left, so Godot mirrors the containers, the anchors, the
  labels' alignment, the sliders, the progress bar, the toggles (on: the knob at the inline end) and the radio lists.
  The photos and the Hangar's jet never flip (their tail numbers would read backwards). Latin
  codes (F-16I, 25R, 08:00) run left to right inside the Hebrew lines; "MSAA 4×" carries a left-to-right mark.
- **Strings:** `modern-iaf/menu/strings_en.json` and `strings_he.json`, formal and gender-neutral (infinitives: לטוס,
  להתניע, לבקש), loaded by `Settings.strings("res://menu/strings")` (shared/settings.gd), the loader both games use.
  Godot's `tr()` is no drop-in: the tables hold lists as well as texts, reborn's Hebrew is keyed by its English
  labels in groups, and auto-translated controls would also translate the texts kept in English. The Language row
  switches every string at once. The briefing's objectives and steps are the rules' (§10).
  A training mission's title is its
  kind ("Take-off", "המראה"; the missions' `title`, the user, 2026-11-09): the base is its own field everywhere it
  shows (the briefing, the loading screen's second line, the debrief's From).
- **The jet's name** is its code and name, "F-16I Sufa" / "F-16I סופה", wherever it shows (the user, A25), from one
  function, `full_name`. In Hebrew it starts with a right-to-left mark: a Label takes its paragraph's direction from
  the first strong letter, so without it the line turned left to right and read "סופה F-16I", the code last (the
  user, A31). `test_hangar.gd` checks the code's place on every label that names a jet.
- **The jet's subtitle** (the top bar, the briefing): its tail number, its
  squadron and its base, "846 · 201 Squadron The One · Ramon", "846 · טייסת 201 האחת · רמון" (the user, 2026-11-09: the
  wing is the base, so it is left out). The tail number is the unit record's `tail`, the number painted on the jet's model
  ([data-formats.md](data-formats.md) §3); the squadron is its airbase file's
  ([airbases.md](airbases.md) §3).
- **Settings** ("Preferences" until 2026-11-14, the approved mocks' word): one screen in the approved r3_settings layout (§14, the finish list's F7, 2026-11-16): the search, the sections with their counts at the inline start, the picked one's rows beside them (Graphics
  until one is picked; the user, 2026-11-09, of the screen per section: "I liked it more before"), and the pane at the
  inline end telling about the hovered or focused setting. A row shows its name, its control (segmented buttons, a switch, a
  slider or a button) and, on Graphics, its cost chip; a greyed row says why (Scenery without its setup step, §4). The
  Graphics section fits between the bars at 1920 × 1080 with no row cut. Over a flight the Settings, Keys and Joystick screens have the front end's top bar (the
  crumbs start at Paused, the pilot and the jet at the inline end) and a footer with Back (since 2026-11-16, finish
  list F4; before, a bare title and no Back); Esc or Back on the Settings goes back to the pause menu, and the Keys
  and Joystick screens go back to the Settings on Devices. Tried
  2026-11-08 and dropped 2026-11-09: one screen per section, the list as cards with the rows' names under each
  section. Realism and aids have no switch (plan.md "physics";
  the user, 2026-11-08): the sim's `PROFILE` (`modern-iaf/sim_settings.gd`) fixes the original Gameplay page's aids off
  (easy landing, unlimited fuel, no damage, no crashes, no G effects…) and the look switches to the sim's own
  (Detailed airbases, water, night lights; the ground textures and roads whenever their data exist), so
  none of them is a row. The weather is the mission's (no Rain row). The rows reborn shows too (anti-aliasing,
  upscaling, long shadows, clouds, scenery, full screen, language) take their choices and when each can be picked from
  the same source as reborn's Extras page, `shared/util/pref_choices.gd`; the sim keeps only the list of its rows
  (`PREFS`) and names each choice by its own strings (`<setting>_<value>`). The temporal upscaler reads MetalFX on a
  Mac and FSR 2 elsewhere (`RenderOptions.temporal_name()`; "FSR 2" everywhere before 2026-11-14). Volumetric clouds
  are greyed where they cannot draw (`VolumetricClouds.supported()`). Graphics → "Buildings and trees" is the shared Scenery setting (Off / On / Detailed, On by
  default, [scenery.md](scenery.md) §6); without setup's optional scenery step it is greyed at Off, with a note
  naming that step. The HUD's brightness has no row: it is the cockpit's SYM wheel and its DAY / AUTO BRT / NIGHT
  switch ([cockpit.md](cockpit.md) §5.1;
  the mouse: §9.1).
- **Sound samples:** moving a Sound slider plays a short clip of its class at the new level, on that slider's bus, from
  the sim's own clips (`converted/own/resource/soundfiles`, `SoundTable`): Engine the engine
  (`SFX_START_ENGINE`), Effects the master caution tone (`SFX_WARNING` `WRN_MASTER`, the effects' class), Radio
  voices a tower call (`twr_takeoff.wav`). Betty's calls ride the Radio voices bus too, so the tower call stands for
  them. A sample still playing follows the slider; another slider's starts in its place.

## 5. The photos

Six Wikimedia Commons photos of the jets shipped in modern-iaf/data/photos until 2026-11-16. No screen showed them
after the debrief's redo (§13, 2026-11-15); Home, Pick a plane and Training, which showed them whole, had gone with
the Hangar (2026-11-13). The finish list's F8 deleted them with their Attributions entry and their credits.

## 6. Checks

- `modern-iaf/tests/test_front_end.gd` walks the Hangar → Missions → Training → the briefing → the debrief of a stored
  record (the sample flight scored, §13; then a record from before the goals) → Back to missions, Fly again, Next mission in English and Hebrew: the texts, each jet's card with its
  squadron, the four sections (Training open and focused with the course's count, Campaign and Single missions greyed,
  "Coming later", without focus or click), Training opening the phases, the footer's Back with Esc; the section list on the
  tests' training missions: the Sufa's missions with their statuses (the range not flown: Next), the
  next one marked and focused, the side panel following the focus, the layout direction; each jet's own missions
  (numbered 1, 2, the Barak's own progress and Next, Next mission by the flown mission's jet);
  the plane pick; the Ra'am's and the Baz's rows greyed and not pickable; the Settings' controls and the live language switch; the Pilot log
  and Attributions. With `-- --fly` it also flies Ramon's start-up from the mission screen to a pass, finds the flight
  paused under Mission accomplished, continues it with Esc (the panel not coming back), opens the pause menu, ends the
  flight and finds that flight's debrief. Run in a real render through `tools/godot_window.sh` it is
  the real run (`SHOT_DIR=<dir>` saves the pictures of §1's second table).
  It also checks the first start (the Pilot screen before the Hangar, no pilot in its top bar, the empty picture's head
  and shoulders turning into the typed name's initials, Save only with a name typed through real input events, Down and
  Up between Name and Nickname, Esc staying, Save storing the name on the active pilot and opening the Hangar), no Pilot log entry on the
  Hangar, the Pilot screen's Pilot log button opening the Pilot log, the breadcrumbs, each
  Settings section opening beside the list on the same screen (its pane over 700 px high, on the inline-end side),
  no line under an option, no aid, realism or weather row and no read of the original's data, the
  sim's settings (no aid on, the log dumps naming only the sim's settings), F1–F4 opening no pause menu, and the
  pause menu inside viewports of 1920 × 1080, 2560 × 1440 and 1280 × 800 in both languages, and the Pilot screen in
  both languages: the Hangar's pilot name opens it, the nickname field shows a hint and takes a click and typed keys, the
  logbook's Sufa with its counts and per-mission passes and fails, Back's discard prompt (Keep editing keeps the
  draft), a click on the picture opening the file picker, a file that is no picture refused, a picture shown in its
  3:4 frame and copied beside the records only on Save, Save opening the Hangar with the nickname and the name under it;
  then Change pilot: the list marking the active pilot, New pilot making a second pilot, active, with an empty log,
  its sortie kept through Reset's first modal and deleted by the second (the other pilot's log kept), and the list
  picking the first pilot back.
- The briefing (§10): the title as the kind, the time as "0800", the wind as "000° / 0 kt" ("קשר"), the take-off's
  four objectives, its runway with the heading, its four steps in a four-column table, no mission tabs, Fly focused
  and Back to the section's list; the six take-off steps (each tower call its own, with its pick and the answer to wait
  for); the wind's figures left to right; the subtitle with the tail number and no wing; Arming opening the Loadout
  screen (§10.1, its own checks there) and its Briefing coming back; no credit on Briefing, the Map's credit at the
  footer's inline end; the start-up's steps with their switches and waits;
  the map over the page with the screen's aspect, the ground colour, roads, Mitzpe Ramon, the airbase, taxi and
  route, the credit; the wheel zooms around the pointer and the scale bar follows, a drag scrolls, a double click
  resets, + zooms, an arrow scrolls the focused map, 0 resets; the page kept for the next mission; the
  start-up's six checklist steps with their keys.
- `cargo test -p iaf-tools --lib briefing`: the map of Ramon's take-off (the base, the taxi from the parking spot to
  the lineup, the waypoint west-south-west of it, the aspect, the fills inside the map, the base's shapes, the towns
  inside it only), of every start-up and take-off; the Sufa's and the F-35I's stores.
- `modern-iaf/tests/test_hangar.gd` checks the Hangar (§12) in English and Hebrew: the first screen, the jet picked
  last (else the first) picked, the five rows with the full names, the F-15s greyed with no focus and no text, a click
  picking the Barak (the F-16 switch) and the Adir with their cards and models, the card's facts and no training progress,
  no campaign button, Settings and the pilot in the top bar, the focus order by Tab and the arrows, the mirrored sides,
  Fly to the Missions screen and the Hangar crumb back, Esc's quit prompt, the jet's view (still
  when left alone; a drag orbiting it, the camera above and below the jet within the limits; the wheel and − zooming to
  the limits; the arrows orbiting with the focus; a double click and Home resetting it), the turntable rendering
  nothing once hidden; then a fresh install (`IAF_ASSETS_DIR` an empty folder): the note and the command on
  the Hangar, Fly dim and out of the focus, the still picture with no model load tried.
- `modern-iaf/tests/_hangar_shot.gd` takes the Hangar's pictures with each jet, the briefing and the Settings at
  1920 × 1080 and 2560 × 1440 in both languages (`PITCH`, `ZOOM`, `YAW` set the jet's view), prints the turntable's
  measured render time and, with `STILLS=1`, writes the stills of `data/hangar/` (its header).
- `modern-iaf/tests/_front_end_shot.gd` takes §1's pictures at 1920 × 1080 (`SHOT_SIZE=1280x720` another size; its
  header), the failed debrief and the two screens without data.
- `modern-iaf/tests/test_flight_ui.gd` checks §8 in both languages.

## 7. The loading screen

**The preload (2026-11-14):** while the mission page is open, the ground around the picked mission's start and the
flight's models load in the background with reborn's preload (`shared/terrain/terrain_preload.gd`, which reborn runs
on its TSD): the mission page sets the mission up (`flight/fly.gd prepare`), aims the preload at the start
(`MissionRuntime.player_start`) and polls it each frame (`front_end.gd _preload_ground` through
`TerrainPreload.follow`, the driver reborn's TSD calls too); another mission re-aims it,
leaving the page drops it. Scramble's screen and its Arming preload its ground start only; its air start (60 km from the area,
`IafFreeCombat.air_start`) loads cold. Fly waits for the flight scene's load on menu frames (`TerrainPreload.fly`, reborn's Fly
too) and the flight's terrain takes the loaded nodes. A `--mission` start loads cold, as before.
`modern-iaf/tests/test_terrain_preload.gd` checks it on the 1:1 theatre (388 nodes at Ramon). Measured on the Mac
(Metal, a real 1920 × 1080 window, Ramon take-off after 6 s on the page, warm, three runs each): Fly to the first
flying frame 2.3–2.7 s before, 1.7–2.8 s with the preload. The ground's decode was not what the start waited for
there: the step "The ground around the base" still takes about 1.2 s, the near scenery being drawn
(`scenery.ground_ready()`), not the ground's textures.

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

| step | what loads | share of the bar | first start | warm |
|---|---|---|---|---|
| The mission | the start, the player's jet chosen, its models (the jet, the 3D cockpit, the pilot's body, the stores, the mission's) handed to worker threads to parse (`TerrainPreload.prefetch_flight`) | 0–1 % | 0.3 s | 0.3 s |
| Buildings, trees and sounds | the models' detail textures, the scenery's materials drawn once, the sounds, the radio, the training run | 1–5 % | 1.3 s | 1.1 s |
| Effects and damage | explosions, smoke trails, the systems damage, drawn once | 5–15 % | 3.7 s | 0.3 s |
| The flight model | the flight overlay, the flight model's start | 15–27 % | 1.6 s | 0.1 s |
| The jet | the jet model, placed and drawn once | 27–32 % | 0.2 s | 0.2 s |
| The cockpit | the cockpit cut from the jet model, the 3D cockpit and the pilot's body, drawn once | 32–38 % | 2.6 s | 0.6 s |
| The weapons and the views | the views, the weapons and their stores, the cockpit and the HUD drawn once | 38–75 % | 4.1 s | 0.1 s |
| The ground around the base | the terrain near the jet at full detail (`ground_progress()`) | 75–88 % | 4.3 s | 1.8 s |
| The mission's models | the mission's models parsed ahead | 88–90 % | none left | none left |
| The views | the external view drawn once for its shaders, the last scenery | 90–100 % | 0.3 s | 0.3 s |
| **The start** | from the flight scene to the flight | | **18.1 s** | **4.4 s** |

Measured on the development laptop (Intel Iris Xe, a real window, `--mission 2012`, 2026-11-10). "First start": a new
`user://` (Godot's shader cache empty) with Mesa's cache off; "warm": the same again. Most of a first start is the
graphics' shaders, compiled by Godot as each part is first drawn (behind the loading screen); Godot keeps them in
`user://shader_cache` for the next start. Before this change the same start took 26–48 s first and 5.1 s warm: the jet,
its cockpit and its weapons came in one frame (11.9 s on a first start, 3.4 s warm, the jet and 3D cockpit models parsed
on the main thread), and the bar sat on "The jet on the ground, its weapons and views" through it. On a Mac (Metal)
the shaders compile about ten times slower: the same frame took 134 s there.

The steps split the work so that each part's first drawing falls in its own frame: the bar moves between them and the
step under it names the part being prepared. A frame longer than 2 s (shaders being compiled) adds a line under the
step: "A first start after an update prepares the graphics for this computer once: it takes longer." A single frame
cannot show progress inside it: the drawing of the screen waits for the same compilation.

The log names every step with its time since the screen opened (`loading: terrain at 2250 ms`), every sub-step with its
own time (`loading:   cockpit cut 213 ms`), and the end (`loading: done at 4199 ms`).

**The watchdog.** The loading must end. The screen opens the crash page (§11) and logs `hang: the loading stopped at
<step> (<why>); waiting for <what>` (the ground's share, the near nodes still blocked, the height under the jet, the
scenery, the models left to parse, the views) when:
- the flight is paused under it (only the player's own pause or menu may pause it);
- its step and progress do not change for 30 s while frames still run.

A main thread that draws no frame for 30 s gets `hang: no frame for 30 s; loading step <step>, after <sub-step>` from
the log's own thread (docs/logs.md §2): the line names what never returned.

On 2026-11-10 a mission card opened at the start under the loading screen and froze the flight, so the loading never
ended (the user's Mac). That card is gone since 2026-11-13; `modern-iaf/tests/test_start_watch.gd` checks that the
loading finishes and the flight runs.

In Hebrew the page is mirrored: the bar fills from the inline start, the right.

| English | Hebrew |
|---|---|
| ![The loading screen: "Take-off", "Ramon", the bar in the ground's step, "The ground around the base" under it](pictures/front-end/loading_en.webp) | ![The loading screen in Hebrew: "המראה", "רמון", the bar filling from the right, "הקרקע סביב הבסיס" under it](pictures/front-end/loading_he.webp) |

`modern-iaf/tests/_loading_shot.gd` takes these pictures (its header).

## 8. Over the flight: the radio lines only, no key hint

The sim draws its own text over the flight in the front end's look (`modern-iaf/flight/flight_ui.gd`, Heebo, look.gd's
palette, on the 1080-high canvas scaled to the window), mirrored in Hebrew; the original game's console and panels
stay the original's (`terrain_view.gd _on_subtitle` hands each line to the flight add-on when it has a `subtitle()`).

- **A clean start:** a flight starts with the flight running and nothing over it (the user, 2026-11-13; no key hint
  since 2026-11-15, below). A start-up mission starts with the pilot's notebook raised; H (the Checklist notebook key) raises and stows it ([training.md](training.md) §11). The mission's goals
  are in the briefing (§10), the completion message and the debrief ([training.md](training.md) §3). The panel's live
  "To complete: …" line and the wrong-runway line went on 2026-11-25 (below; the tower still names a wrong runway). The in-flight mission card on H was
  removed on 2026-11-13 (the user's order); H is the notebook's key since the same day (record 118).
- **The radio lines** show in a strip centred at the top, over the sky rather than the cockpit's panel,
  the newest at the bottom, three at most, wholly in the game's language ([training.md](training.md)
  §8). A radio line shows while its voice plays: from its first clip's start to its last clip's end, not at the menu's
  pick: the pilot's call after its key click, the tower's answer after the pilot's call and the gap (the user,
  2026-11-13: "comms subtitle should show up as talking"; 28 Nov, A141: "subtitles not sync with sound"; `radio.gd
  cue_subtitle`, `flight_sounds.gd on_start`; the band drops the line when its last clip's player ends). A line
  without a clip (no sound file) shows when the speech before it ends, for 8 s; with no sound, at once. The text is subtitle size, 20 px at 1080 (the Mac play test, 2026-11-11: 26 px was too big).
- **Nothing but the radio** (the user, 2026-11-25: "why I still see any popup in flight? remove this functionality
  completely for nothing which isn't radio"; before that, 2026-11-19: no line for a change the cockpit shows): every
  line that is not a radio call (a switch's new state, a refusal, damage, a cheat) goes through
  `terrain_view.gd _cockpit_note`, which in Modern IAF (`Settings.cockpit_notes()` false) only writes it to the
  recorded flight. Radio calls (`radio.gd say`, `cue_subtitle`) and the mission's messages (`mission_runtime.gd`
  `subtitle`) keep `_on_subtitle` and the strip. The original game keeps all its console lines. The autopilot's lines
  went on 2026-11-25 (the user: "why the fuck there is still notes on a/p, I thought we removed them all?"): until then
  a refused PITCH switch said "A/P OFF: …" (twice in the Scramble dusk pictures, with the sim's own autopilot
  flying).

  | Line | The strip | Why |
  |---|---|---|
  | "Master arm" / "Master safe" (command 202) | removed | the MASTER ARM switch's position; ARM in the stores page and the HUD or helmet |
  | "Helmet night camera" / "Helmet DAS video" / "Helmet video off" (302 p1 3) | removed | the view itself |
  | the Lights Master (302 p1 4, the F-35I) | none | the navigation lights and the strobe on the jet's model |
  | "Dogfight" / "Missile override" / "… off" (251) | removed | the HUD's and the MFDs' master mode |
  | "IFF IDENT" (255) | removed | the DED's CNI page shows `I` while IDENT replies |
  | "Bay doors open" / "closed" (301) | removed | the SMS's DOORS legend, the doors on the model |
  | "Laser armed" / "Laser safe" (241) | removed | the LASER ARM switch's position |
  | "ADV MODE on" / "off" (242 p1 0) | removed | the ADV MODE button's STBY / ACTIVE lamps |
  | "Data link on" / "off" (265) | removed | the DL switch's position, the tracks on the HSD |
  | "Parking brake …", "Master fuel …", "Engine feed …", "Fuel quantity …" (270) | removed | the switches' positions |
  | the bombs' submode, fuze, arming delay (290) | removed | the SMS's A-G page |
  | "VIS" / "PRE" (233) | removed | the SMS's A-G page |
  | "Seeker SPOT" / "Seeker SCAN" (280 p1 1) | removed | the SMS's OSB 2 |
  | "PITCH …" / "ROLL …" (the autopilot switches, 292) | removed | the switches' positions |
  | "A/P OFF: …" (a PITCH switch that will not stay engaged) | removed (2026-11-25) | the switch springs back; the manual lists the conditions |
  | "TRIM/AP DISC …" (294), "FLCS RESET" (295) | removed (2026-11-25) | the MANUAL TRIM panel's TRIM/AP DISC switch; the FLT CONTROL panel's FLCS RESET switch and the fault list ([cockpit.md](cockpit.md) §5.10) |
  | "Manual TF fly-up …" (242 p1 1) | removed (2026-11-25) | the TFR page's MAN FLYUP OFF (`f16_mfd.gd`); the switch itself is not in the cockpit model |
  | "CMDS …" mode (262) | removed (2026-11-25) | the MODE knob (every mode) and the DED's EWS CONTROLS page |
  | "CMDS program …" (263) | removed (2026-11-25) | the CMDS panel's PRGM knob ([cockpit.md](cockpit.md) §5.13) |
  | "Seeker uncaged" / "caged" (280 p1 0) | removed (2026-11-25) | the HUD's diamond grows with a track |
  | "PRE n/m" (234) | removed (2026-11-25) | the F-16 SMS page's STA n PP n/N; the F-35I WPN-S page's target per bomb |
  | "FLC: no layers on this format" (302) | removed (2026-11-25) | nothing changes on the format |
  | "No goggles: use the helmet's night camera" (303, the F-35I) | removed (2026-11-25) | nothing changes; the F-35I has no goggles |
  | "Structural damage" and the other damage lines | removed (2026-11-25) | the caution and warning lamps |
  | the cheats' lines (Shift + R, S, D, F) | removed (2026-11-25) | none (not a cockpit function) |
  | the training's fail banner ("Fail" and the reason) | removed (2026-11-25) | the debrief, the reason first |
  | "To complete: …", "Wrong runway: …" (the training panel) | removed (2026-11-25) | the tower's call names a wrong runway; the debrief names an open goal |
  | radio lines, mission messages | kept | the radio |
- **The panel** at the inline-start top (the left in English, the right in Hebrew) holds the radio menu (Ctrl+T). A
  request that cannot be made now is dimmed and takes no click; no line says why (the user, 2026-11-25: "no need to
  write why something is disabled, this goes in game manual"); the game manual says when each is off. Its text runs in the language's direction; the panel itself keeps the root's direction and
  takes its side from its anchors. Until 2026-11-13 the panel was set right-to-left too, and Godot mirrors such a
  control's anchors, so in Hebrew the radio menu and "To complete" stood at the top left (the Mac run of 2026-11-13).
- **The info line** (F12, at the top left): the mission's name and the frames per second (`Settings.info_line_full`
  false; the original game's line also holds the modes, the place, the speed and the controls).
- **No key hint** (the user, 2026-11-15: "why are you still showing the hint when mission start (esc for menu)? we
  said to remove it completely"; 2026-11-13: "lets remove the kb hints"): nothing over the flight names a key, at the
  start or later, in either language. From 2026-11-10 to 2026-11-15 a line at the bottom showed Esc and the pause menu
  for the first 8 s and after a language change; it is gone. The keys are listed in the pilot's notebook (H) and on the
  Keys screen; the one line over the flight naming keys is the notebook's own help line in the pilot's first start-up
  mission (approved 2026-11-13, [training.md](training.md) §11). Esc still opens the pause menu.
  `test_flight_ui.gd` checks that no hint shows. Pictures in these docs taken before 2026-11-15 may still show the
  line.
- **Under the front end** (the pause menu, its Settings, Keys and Joystick screens, Mission accomplished): only the
  frozen 3D view shows behind the dim. `terrain_view.gd _open_front_end` hides every 2D layer of the flight (this
  text, the messages, the info line, the 2D cockpit) and `close_front_end` shows them again. Until 2026-11-16 the
  radio band showed faintly through the Settings top bar. `test_flight_ui.gd` checks each of those screens.

A language switched over the flight (Esc → Settings → Language) applies at once to the panel (an
open radio menu), the pilot's notebook ([training.md](training.md)
§11) and the radio lines: `radio.gd` keeps each line it prints in both languages (`subtitles`, the pilot's call from
`sim_flight.gd pick`), so a line shown, or still waiting for its voice, shows in the language of the moment.
Before 2026-11-13 a line kept the language it was said in: the Mac's take-off pictures, switched to Hebrew after the
calls, showed the tower's lines in English under a Hebrew "To complete" panel. `modern-iaf/tests/test_flight_ui.gd`
checks the layout at a start in each language and after a switch each way, and the band's lines after a switch.

| | English | Hebrew |
|---|---|---|
| the strip after a tower call (taken before 2026-11-15: the key hint since removed still shows) | ![A tower call in the band](pictures/front-end/band_en.webp) | ![A tower call in Hebrew](pictures/front-end/band_he.webp) |
| 10 s into the flight | ![The take-off 10 s in, no key hint](pictures/front-end/flight10_en.webp) | ![The take-off 10 s in, Hebrew](pictures/front-end/flight10_he.webp) |

## 9. Keys and Joystick

Settings → Devices has two rows that open their own screens: **Keys** and **Joystick**. Esc on either goes back to
the Settings on Devices. Both read and write one file, the device store (§9.4). A change applies at once: the front end's
next flight reads it, and over a flight the Settings apply it when they close.

### 9.1 Keys

The screen lists every command of the sim's key table (`modern-iaf/data/keys.json`) that has a `group`, in five groups:
Flight, Weapons, Sensors and displays, Views, General. The tabs on the inline-start side scroll to each group, and the tab of the group at the
top of the list lights as the list scrolls (`front_end.gd spy`; the Joystick screen's Devices, Axes and Buttons too).
Back in the bottom bar, as Esc, goes to the Settings on Devices; the top bar's breadcrumbs read Hangar · Settings ·
Devices · Keys. A row shows the command and its key; on macOS a key with Ctrl shows as ⌘ and one with Alt as Option
(`KeyTable.mac_symbols`, which the sim sets; the 1998 game keeps Cmd and Alt; docs/controls.md §2). Leave mission and
Mute show Ctrl + Q and Ctrl + M there (since 2026-11-18): macOS takes ⌘ + Q and ⌘ + M itself, and Ctrl works. The
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

**The laptop map.** A Mac laptop has no numpad and no Insert, forward Delete, Home, End, Page Up or Page Down without
Fn, and macOS takes F11 (Show Desktop). So on macOS the sim starts from the laptop map: the same table with the
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
| Zoom (numpad) | Numpad − / + | none: − / = |
| Raise / lower the head | Shift + Page Up / Page Down | Shift + = / Shift + − |
| DMS up / down | Ctrl + Page Up / Page Down | Ctrl + U / Ctrl + D |
| DED field up / down (DCS up / down) | Alt + Page Up / Page Down | Ctrl + = / Ctrl + − |
| DED back to CNI / next sub-page (DCS RTN / SEQ) | Alt + Home / Alt + End | Ctrl + , / Ctrl + . |
| Checklist notebook: previous / next page | Page Up / Page Down | Alt + Space / Shift + Space |

Every listed command has a key on a Mac laptop's keyboard: iaf-tools' test
`every_listed_command_has_a_key_on_a_mac_laptop` fails on a record whose key that keyboard lacks and that has no
`laptop` key (nor another record for the same command). On every keyboard since 2026-11-18: Drop chaff on Ctrl + Z
and Drop flares on Ctrl + X (were Insert and Delete), View from the weapon on F2 (was F11).

**One head-look set.** The sim's head look is the snap views (records 28–36: the numpad, Option + 1–9 on the laptop
map; the hat sends the same views in its eight directions) and the mouse (the right button held). The 1998 game's duplicates are empty slots in
the sim's table: F2 rear view (record 74, the same as Look back) and the free look on Shift + the numpad and Shift + the
arrows (records 86–93). The 1998 game keeps all of them.

**The switch keys (2026-11-18).** Commands that had a key and no row are records of the table now, listed and rebound as
any other: Speedbrakes open (hold) and Speedbrakes close (B, Shift + B: the SPD BRK switch,
[flight-model.md](flight-model.md) §9.11; the user, 2026-11-18, "B should be the airbrake"), Wheel brakes (hold) (W: the
wheels only, braking while the key is held), Parking brake (Shift + G; a ground start begins with it set), MASTER
FUEL, ENG FEED and FUEL QTY SEL (Ctrl + F, Shift + E, Shift + U; [cockpit.md](cockpit.md) §5.7), DRIFT C/O and WARN
RESET (Shift + J, Ctrl + R), HUD CONT and the left and right MFDs' CON and GAIN (Ctrl + H, Shift + 7 / 8 / 9 / 0, a
step down each press, round from the bottom to the top; [cockpit.md](cockpit.md) §5.8), Roll trim left / right
(Alt + Left / Right, held), MANUAL PITCH override (Alt + M, held), STORES CONFIG switch (Alt + S), GPS bomb PRE / VIS
and GPS bomb next PRE target (K, Shift + K); and later the same day the flight scene's own Ctrl + F-keys, Leave mission
(second key) on Ctrl + F1, Cockpit / outside view on Ctrl + F2 and Flight information line on Ctrl + F12 (records
219–221; the 1998 game keeps them as its own keys, docs/controls.md §2), and the Checklist notebook's previous and next
page on Page Up / Page Down (records 222 / 223, while the notebook is raised; [training.md](training.md) §11). Shift + N,
the 1998 game's night-vision goggles' key, is record 255 since 2026-11-19 (command 303): the F-16s' goggles flipped
down / up ([cockpit.md](cockpit.md) §5.5). The brakes took W from Next waypoint (the user, 2026-11-18, on a Mac
laptop's keyboard, where no plain key was left): Next waypoint is on Shift + W, and Previous waypoint moved from there
to Shift + Q, the key beside it (Alt + W is the wingman's "attack another target", Ctrl + W a debug key). The 1998
game's Drag chute has no row and no key: no Modern IAF jet has a drag chute (record 23 is an empty slot).
On 2026-11-19 the F-16's own autopilot got its keys (records 231–237; [cockpit.md](cockpit.md) §5.10): its PITCH switch
a step up / down (Shift + 2 / 3), its ROLL switch a step up / down (Shift + 4 / 5), the paddle switch (Shift + I,
held), TRIM/AP DISC (Shift + 6) and FLCS RESET (Ctrl + L).

On 2026-11-25 air refuelling got its two keys (records 259 / 260; [research/air-refuelling.md](research/air-refuelling.md)
§8.2): the refuelling door, open / close, on Shift + F1 (command 296; the F-16's AIR REFUEL switch, the F-35I's door)
and the stick's A/R disconnect on Shift + F2 (command 297), both in the Flight group.

The training fight against an aggressor has the player's "knock it off" on Shift + F4 (record 261, command 304,
the Sim group; [../../docs/ai.md](../../docs/ai.md) §26): the engagement ends and the next set-up follows.

**The missile seeker's keys (2026-11-18).** Two records in the Weapons group work the seeker head of the air-to-air
missiles on every Modern IAF jet ([weapons.md](weapons.md) §8.1): Missile seeker: UNCAGE / CAGE on Shift + M (record
224) and Missile seeker: SPOT / SCAN on Ctrl + S (record 225; on the F-16s also OSB 2 of the SMS's AAM page). Both
send command 280 (p1 0 / 1).

**The bombs' keys (2026-11-18).** Five records in the Weapons group work the F-16s' bomb release
([weapons.md](weapons.md) §9): A-G release submode: next on Ctrl + G (record 226; CCIP → DTOS → CCRP, as the missile
step switch), Bomb fuze: next on Alt + Q (227), Bomb arming delay: next on Alt + 0 (228), all command 290 (p1 0 / 1
/ 2), and the RET DEPR wheel's reticle down / up on Ctrl + V / Alt + V (229 / 230, command 291, p1 1 / -1, 5 mr a
press); the SMS's OSBs 2, 17 and 18 and the 3D cockpit's wheel do the same.

**The navigation pod's TFR keys (2026-11-19).** Two records in the Sensors group work the Sufa's terrain-following
radar ([weapons.md](weapons.md) §7.4), both command 242: ADV MODE (automatic TF) on Shift + F8 (record 238, p1 0; the 3D
cockpit's ADV MODE button does the same) and the MANUAL TF FLYUP switch on Shift + F9 (239, p1 1). The paddle switch
(Shift + I, held, record 235, command 293) is the autopilot's and the TFR's: one switch on the stick, so it also holds
a TF fly-up off (2026-11-19). With the navigation FLIR's picture
on the HUD and the HUD the SOI, the cursor keys (records 48–51) shift the picture (snap-look).

**The mouse in the 3D cockpit.** The pointer works the cockpit's controls (`Settings.cockpit_controls()`,
[cockpit.md](cockpit.md) §5.1): over a control it lights it, the wheel and a left drag turn a knob, a left click
works a switch, each through the key's own command. The F-16s' controls: the SYM wheel, the HUD's brightness, which
Shift + H also steps (its position kept in the sim's settings file, not in the device store), the HUD's DAY / AUTO
BRT / NIGHT switch (kept there too), and the start-up
checklist's switches (MAIN PWR, JFS, the throttle, the AVIONIC POWER switches, the INS knob;
[cockpit.md](cockpit.md) §5.2). The pilot's notebook names each step's
switch and its place under its line, and no key ([training.md](training.md) §11).

| | English | Hebrew |
|---|---|---|
| Pitch up rebound to K | ![The Keys screen: the Flight group, Pitch up on K with its Default](pictures/front-end/keys_en.jpg) | ![The Keys screen in Hebrew, mirrored](pictures/front-end/keys_he.jpg) |
| K pressed for Pitch down | ![The conflict line under Pitch down: Swap, Use it here, Cancel](pictures/front-end/keys_conflict_en.jpg) | ![The conflict line in Hebrew](pictures/front-end/keys_conflict_he.jpg) |

The pictures date from before 2026-11-18, when K had no command; K is GPS bomb PRE / VIS since, so the first rebind
asks the same question about it.

### 9.2 Joystick

With no joystick connected the Devices section's Joystick row is greyed, its Change off, and it says "No joystick
connected."; it comes alive when one is plugged in (`Input.joy_connection_changed` builds the section again). Tests see
only their fake joysticks (`Joystick.device()`).

**Plugged in or out (since 2026-11-25).** A device plugged in during a flight works from the next frame: the poller
picks a new main joystick up with its device map's buttons and axes (`Joystick._process` → `Settings.joystick_connected`),
and looks a role's second device up by name each poll. A device pulled out sends its stick and rudder axes to the
centre once and gives their keys back (`Joystick._lost`); the 1998 game keeps the last values, as its poller does. The
Joystick screen builds itself again when a device comes or goes.

Back in the bottom bar and the breadcrumbs Hangar · Settings · Devices · Joystick work as on the Keys screen; the
side list (Devices, Axes, Buttons) follows the scroll.

- **Devices:** every connected device by name. The main joystick flies the jet ("Flies the jet"): its buttons, its hat
  and every role without a device of its own. It is the device the Roll role names, else the first connected one
  (`Joystick.device()`). Without a device the screen says so.
- **Axes:** per device, the main joystick's first, the six axes Godot reports (fewer when the device's USB descriptor
  says so, `IafHid.axis_count`); with several devices each device's rows are under its name. Each
  row has a live bar, the axis' role, Invert and a dead zone (0–50 %). The roles: Roll, Pitch, Throttle, Rudder, Roll
  trim (the throttle rocker, docs/controls.md §5.2), None. A role sits on one axis: giving it to another axis leaves
  the old one with None. A role given to another device's axis is read from that device (a throttle or rudder
  pedals beside the stick, since 2026-11-25): the store keeps the device's name (§9.4), `Joystick.role_names` carries
  it to the poller, which looks the device up by name each poll. Two devices with the same name are told apart by
  the order they were plugged in: the second is "<name> #2" (the lowest number free among the connected ones of that
  name) and keeps it until it is pulled out, so a twin pulled out never hands its roles or buttons to the other one
  (`Joystick.dev_key`; two identical devices report one name and one GUID, so nothing else tells them apart). Roll moved to another device makes that one the main
  joystick; the roles still on the old one are pinned to it by name first (`iaf_tools::devices::set_axis`). The bar shows the axis as the flight reads it (`Joystick.role_value`: the role's invert,
  dead zone and sense), so the dead zone is visible as the bar's still centre and the bar fills the way the jet
  responds: the throttle lever forward is a full bar (full power), the stick pushed forward a full pitch bar. The
  throttle has no centre and no dead zone. Tested on the Mac 2026-11-11: the bars showed Godot's raw reading, where a
  lever or stick pushed forward is −1, so the throttle's bar was empty at full power while the flight (and the 1998
  game) read it right. The one sense now lives in `joystick.gd` (`SENSE`, `shaped`), which the poller and the bars both
  read.
- **Buttons:** the Keys screen's list with the joystick's buttons. Click a row, then press a button. Conflicts, Default and Reset all work as on the Keys screen.
  A button on another device (a throttle, pedals; since 2026-11-25) binds the same way and shows with the device's
  name ("Pedals · Button 3"). The store numbers such devices (`button_devices`, §9.4) and the binding is
  `slot × 1000 + button` in `Settings.key_bindings`, so the key table keeps one number per binding
  (`Joystick.button_of`); the main joystick's buttons are 0–999 as before, so they follow the device that flies the
  jet when Roll moves. The 1998 game reads the main joystick's buttons only. A second device without an SDL mapping
  gets the main joystick's (its 12th and later buttons off the hat's indices). The hat is the
  1998 game's POV, read by the same code (`Joystick.poll`), its eight directions the snap views (up, right, back, left
  and the corner views front-right, back-right, back-left, front-left). Tested on the Mac 2026-11-11: the sim had
  turned the hat into four buttons of its own, so the diagonals did nothing; reborn's hat had them all along.
- **Reset all** puts the buttons and the axes back to the defaults.

The Joystick screen has no rows for the Devices group's choices (Flight controls, Rudder, Throttle, Afterburner detent,
Stick response): they stay in the Settings.

**Afterburner detent** (Settings → Devices, greyed with no joystick): the throttle lever's click where the
afterburner starts, as the 1998 game's Devices "Detent = MIL" (docs/controls.md §5). Put the lever in its click and
choose Set at lever: the row then reads "At n%" (the lever's raw position) and that position gives military power, the
travel past it the afterburner (`Joystick.detent_choice` and `detent_map`, the code reborn's page runs). With the lever
in its click the engine is at military with the burner off; the burner lights 4 points past it
(`modern-iaf/tests/test_detent.gd`). Off puts the lever back to linear. One setting
(`Settings.throttle_detent`) for the throttle role's axis. A role with no axis leaves its keys working, as Keyboard does: with Roll on None and
Pitch on an axis, the roll keys roll the jet while the stick pitches it (`Joystick.stick_mixed`).

| English | Hebrew |
|---|---|
| ![The Joystick screen: the Hotas X flies the jet, six axes with their bars, roles, Invert and dead zones](pictures/front-end/joystick_en.jpg) | ![The Joystick screen in Hebrew: mirrored, the bars still fill left to right](pictures/front-end/joystick_he.jpg) |
| ![Rudder pedals as a second device: their axes under their name, the rudder on their axis 3](pictures/front-end/joystick_two_en.jpg) | ![The same in Hebrew](pictures/front-end/joystick_two_he.jpg) |
| ![The gear on the pedals' button 3: the chip names the device, then the button](pictures/front-end/joystick_two_buttons_en.jpg) | ![The same in Hebrew: the button first, then the device](pictures/front-end/joystick_two_buttons_he.jpg) |

In Hebrew the screens are mirrored; the key names and the device name run left to right, and the axis bars keep the
stick's own direction (right is right). The dropdowns draw the same box both ways: right to left Godot draws an
OptionButton's `*_mirrored` boxes, so `look.gd` sets them to the left-to-right ones.

### 9.3 Device maps

A known joystick gets its own defaults from a device map in `modern-iaf/data/devices/` (JSON): `match` (a part of the
device's name, case ignored), `axes` (role → Godot axis) and `buttons` (key-table record → button). The
map replaces the table's whole button column for that device: a record it leaves out has no button. The first map
whose `match` is in the name wins (file-name order); a device with no map takes the table's own buttons and axes 0–4.

| file | device | axes | buttons |
|---|---|---|---|
| `hotas_x.json` | Thrustmaster T.Flight Hotas X | roll 0, pitch 1, throttle 2, rudder 3 (the twist), roll trim 4 (the rocker, 5-axis mode) | 1 gun, 2 release, 3 next target, 4 flares, 5 chaff, 6 master mode, 7 radar mode, 8 drop lock, 9 gear, 10 flaps, 11 wheel brakes, 12 autopilot; the hat: the snap views in eight directions (the 1998 game's) |

The Hotas X's axes are the ones docs/controls.md §5.2 found on that stick. The button choice is ours (inferred: the
trigger fires the gun, the buttons next to it release and pick targets).

### 9.4 The device store

The keys and buttons are the store both games use: `Settings.key_bindings`, saved in the settings file (`[keys]`,
`r<record> = [key, button]`), with the rules of `shared/controls/key_table.gd`, the same ones reborn's Controls page
uses (`find_key` / `find_joystick` for the conflict, `key_of` / `joystick_of`). A key is DIK | modifiers << 16 (0 = no
key), a button the joystick's 0-based button (−1 = none). The sim binds one column at a time (`set_column`): the
other column stays null, its default, so a button follows the connected joystick's device map. An entry goes when
both columns are the default again.

The axes are in `user://devices.json`, written compact and only with what differs from the defaults:

```json
{"axes":{"pitch":{"axis":3,"invert":true,"dead":0.1},"rudder":{"axis":2,"device":"Saitek Pro Flight Rudder Pedals"}}}
```

- `axes`: role (`roll`, `pitch`, `throttle`, `rudder`, `trim`) → `axis` (−1 = none), `invert`, `dead` (0–0.9),
  `device` (the name of the device the axis is on, as Godot reports it; absent = the main joystick). An
  absent field is the default: the device map's axis (else 0–4 in role order), no invert, and the dead zone of
  `joystick.gd` (25 % on the stick and the rudder, 5 % with Stick response Soft centre, 10 % on the rocker). A dead
  zone outside 0–0.9 in a hand-edited file reads as its nearest end.
- `button_devices`: the devices other than the main joystick whose buttons are bound, by name (`"<name> #2"` for a
  twin); a button b on the device at index i is bound as `(i + 1) × 1000 + b`. Reset all keeps the list.

A missing or corrupt file reads as an empty store: every default. A `devices.json` from before 2026-11-14 also held
`keys` (record → key) and `buttons` (record → button); at its start the sim moves them into `Settings.key_bindings`
once (`sim_settings.gd _take_old_bindings`) and drops them from the file.

Tests and pictures use a temporary file (`Settings.devices_path`, or in isolated runs a file of the process in the
temporary folder, so no run reads another's).

The axes' logic is Rust's: `iaf_tools::devices` (unit tests in the same file) behind `IafDevices`
(`crates/iaf-godot/src/devices.rs`):

| function | does |
|---|---|
| `find_map(dir, name)` | the device map for a joystick's name, "" = none |
| `axes(store, map, soft)` | every role's axis, invert and dead zone |
| `set_axis(store, map, role, choice, soft)` | sets a role to `choice` {axis, invert, dead, device, main}; a role on that axis of that device gives it up |
| `reset_axes(store)` | every axis back |
| `button_slot(store, name)` | the slot (1..) of a device's buttons, added when new; 0 for the main joystick |
| `button_devices(store)` | the devices of the slots in order |
| `drop_bindings(store)` | drops the keys and buttons of a store from before 2026-11-14 |

How the flight reads it:

- **Keys and buttons:** the flight's key table is `KeyTable.load_table()` (the sim's own table) with
  `Settings.key_bindings`, as in the original game. When a joystick connects, the sim hands its device map's button
  column to `Joystick.default_buttons` (`sim_settings.gd _map_buttons`), where reborn's `.joy` files put theirs.
- **Axes:** `Settings.apply_devices()` (at start, on every Settings save, when a joystick connects) sets
  `Settings.joy_axes` to the roles' axes, `Joystick.tune` to their invert and dead zone, `Joystick.role_names` to
  their devices, `Joystick.button_devices` to the button slots' devices, Roll trim on while the trim
  role has an axis. The hat is the original's POV snap views in both games.
  `joystick.gd` reads them each poll. The original game leaves `tune` empty, so its joystick is
  unchanged (`tests/godot/test_joystick.gd`, `test_controls.gd`, `test_keyboard_stick.gd`).
- **The maps' folder:** `Settings.joy_maps_dir()`: the original game's `menu/joy` in the install (its `.joy` files),
  the sim's `modern-iaf/data/devices`, where the shared `.joy` reader finds none and so reads no install. A missing
  folder is skipped.

### 9.5 Checks

- `modern-iaf/tests/test_devices.gd`: the Devices rows open both screens in English and Hebrew; Pitch up bound to F11 by a
  synthetic key reaches the flight's key table; F11 for Pitch down shows the conflict, Swap trades them; Esc cancels;
  Default and Reset all; with a fake joystick, axis 4 given the pitch inverted with a 10 % dead zone drives the
  poller's stick y (+100 at +1, 0 inside the dead zone, +50 at 0.55); a button and the hat bound by pressing them;
  the axis mapping against the 1998 game's table (with the Hotas X's defaults every role sends reborn's event at five
  positions, every bar has its event's sign and size, the lever forward is a full throttle bar); the hat through the
  1998 game's poller (up then up-right sends the front-right view, centred releases it) and binds nothing; 180 commands listed (no drag chute, the eight switch keys since 2026-11-18), one head-look set;
  the Hotas X's map; with `Settings.laptop_keys` on, the laptop map: the rudder on Z / X, no key on two records, no
  numpad key, Ctrl + Q and Ctrl + M named with Ctrl on macOS, a stored key wins over it; a `devices.json` from before 2026-11-14 and a settings file with reborn's
  `[keys]` entries both load into `Settings.key_bindings`. `iaf-sim own`'s unit test checks the laptop table compiles
  the same way.
- `modern-iaf/tests/test_devices.gd` `second`: rudder pedals as a second fake device: 6 + 6 axis rows, the rudder on the
  pedals' axis 3 stored with their name and read from them (bar and role value); Gear bound to the pedals' button 3 by
  pressing it (1002, shown "Pedals · Button 3"), the stick's button 3 its own; twin pedals: the second is "Pedals #2",
  its button binds in slot 2 and keeps it while the first is pulled out, the first plugged in again is "Pedals"; Reset
  all puts every role and button back.
- `modern-iaf/tests/test_joy_hotplug.gd` flies the Barak with fake devices plugged in and out mid-flight: a stick
  plugged in rolls the jet from the next frames with its map's buttons (the Hotas X's gun on button 1); pedals plugged
  in move the rudder while the stick's twist does not, the stick's lever still drives the throttle; a pedals' button
  bound to the gear raises it; the pedals pulled
  out centre the rudder and give its keys back; the stick pulled out centres the stick.
- `modern-iaf/tests/test_switch_keys.gd` flies the Barak: W (Wheel brakes (hold)) held in the air brakes and opens no
  speedbrake, and lets go with the key; the waypoints' keys are Shift + W and Shift + Q, and after Shift + W with Shift
  let go first W brakes nothing; B held opens them
  and they stay when let go, Shift + B closes them (also with Shift let go first); Alt + Right trims (also with Right
  down before Alt), Alt + M is MPO, Alt + S is STORES CONFIG; MPO rebound to J works on J and no longer on Alt + M; no
  key for a drag chute.
- `modern-iaf/tests/test_m0_boot.gd` connects a fake joystick: the probe's gate line stays at 0 refused paths.
- `modern-iaf/tests/_devices_shot.gd` takes §9's pictures (its header).

## 10. The mission briefing

A row of a section's list opens its mission's briefing (the user, 2026-11-09: "briefing, with map, when selecting a
mission"), map first since 2026-11-14 (the approved mock r3_briefing, the user's A25 round 3: "the briefing is
amazing"). The crumb reads "Hangar · F-16I Sufa · Training · Take-off". This section's examples and pictures are
the tests' training missions, which no front-end section lists (§2); a course lesson's briefing (Approvals A132)
opens here once built. The map fills the screen under the bars;
over it sit two cards and the map's chips (`menu/briefing_page.gd` lays them out):

**The mission card** at the inline start (the left in English, the right in Hebrew), 600 px wide:
- **The title and the line under it**: the mission's kind, then what it is and the jet's squadron ("Radio calls, taxi
  and take-off. F-16I Sufa · 201 Squadron The One · Ramon"), once; the tail number is the top bar's.
- **Flights** (מבנים), in a mission of more than one flight only (the user, 2026-11-15: "briefing need future support
  for multiple flights together (alpha, bravo, etc)"): a tab a flight, its callsign (Kidon 1, the player's, first and
  picked; Kidon 2, 3 and 4: kidon style since 20 November 2026, [research/radio-terms.md](research/radio-terms.md)), and under the tabs the picked flight's line: "Your flight · 1 × F-16I Sufa ·
  Training · 6 × AIM-9M · 2 × 370 gal tank" (the player's stores as the Arming summary's, another flight's its unit
  record's own pylons). Another flight picked, the map fits its route into view and draws it wider; Kidon 1
  picked again, the map's opening view. The flights are Rust's
  (`IafBriefing.flights`, `crates/iaf-tools/src/flights.rs`, from the mission's `start` and `flights`,
  [data-formats.md](data-formats.md) §5); `iaf-sim` writes the same list into the compiled mission's `sim.flights`.
  A mission of one flight, every mission today, shows no Flights block: its card is as before.
- **The facts:** the runway end and its grid heading ("25R · 246°"; a take-off only), the time as military time
  ("0800"), the wind as pilots read it, direction and speed ("250° / 8 kt", "250° / 8 קשר"; calm is "000° / 0 kt"),
  from the mission's `wind_from` and `wind_kt`, the time allowed. Both languages keep the digits left to right.
  The heading is the grid one, the number the HUD and the compass read (the sim's world is grid north), as in the
  pilot's notebook and airbases.json; before 2026-11-13 the briefing said true 247° for Ramon's 25R, the HUD 246°.
- **Objectives:** what the scorer judges ([training.md](training.md) §3), in the rules' figures, each beside an empty
  box: a start-up's engine at idle and avionics up; a take-off from its runway and the climb-out with the gear up on
  the runway heading (`heading_tolerance_deg`); then the time allowed and the at-once fails (§3.0).
- **Arming:** the stores on the jet ("6 × AIM-9M · 2 × 370 gal tank", the pilot's loadout, below), the take-off
  weight (in the warning colour over the maximum) and **Edit**, which opens the loadout screen.
- **Back** (the section's list), **Arming** and **Fly** (focused on entry), off while the loadout blocks the take-off (over the maximum weight).
  Arming opens the loadout screen, as Edit does (the user, 2026-11-15: "it's unclear how do I go to arming page from
  the brief page"). It has no key of its own: its key A and key cap were removed the same day (the user: "remove the
  key shortcut for arming"); the mouse, Tab / the arrows and a gamepad reach it.
- **The facts' figures:** each value's figures are a label of their own, left to right, and its unit a label beside
  them, so "16,471 ק"ג", "000° / 0 קשר" and "25R · 246°" keep their order in a Hebrew line.

**The mission's text** at the inline end, from under the chips to the bottom, 640 px wide (since 2026-11-15, the
user's note after playing: "it should have a short summary of the purpose (in training: what would you learn) and a
longer explanation on how and what to do"; it replaced the ORDER OF ACTIONS card's checklist, which stays in the
pilot's notebook, H):
- **What you will learn** (מה לומדים; a mission of another category: **Purpose**, מטרה): the mission's
  `briefing.purpose`, two or three lines in the accent's text colour.
- **How to fly it** (מהלך הטיסה): the mission's `briefing.how`, the explanation of what to do and how in paragraphs
  of prose, 23 px type (15 px at 1280 × 720), each numbered. The keys stand in it as bound, in key caps, from the
  key table for the player's platform ("⌘ + T, 2" on a Mac: the radio menu's pick after the key); the runway, the
  climb-out's tolerance and the time allowed are the mission's figures. A start-up's paragraphs show their switches'
  pictures under them, 240 × 160, each with its `where` as its tooltip.
- The explanation scrolls: the wheel (a touchscreen's drag), and with the focus (the card's frame then in the accent)
  the arrows, the gamepad's pad and Page Up / Down; at its top or bottom an arrow moves the focus on.
- The texts are mission data, written for every mission in English and Hebrew ([data-formats.md](data-formats.md)
  §5): a start-up's from the tower's start-up call (since 2026-11-15: the engine start needs it) through the checklist's
  order with each switch's place and the state to wait for; a take-off's from
  the cold start through the four tower calls, the taxi, the line-up and the take-off to the climb-out, with what
  fails the mission at each place ([training.md](training.md) §3, §7, §8).

The switch pictures are the switch cut from the jet's own 3D cockpit: as the cold jet has it, a ring in the accent
colour round it. They are `modern-iaf/data/switches/<unit>/<step>.webp` (300 × 200, the step ids of `sim_flight.gd`
`STEP_IDS`), committed beside the jet photos and made by `modern-iaf/tests/_switch_crops.gd` (its header) from each
jet's start-up mission: for each step the head turns to the clickable controls whose command is the step's
([cockpit.md](cockpit.md) §5.2; the F-16's four AVIONIC POWER switches in one ring, the F-35I's engine step its ENGINE
switch, the F-16's its throttle with the pilot's glove on it; the pilot's body hidden for the rest).
A step without a picture has none under its paragraph. The F-16s' canopy picture shows its switch and lock lever
([cockpit.md](cockpit.md) §5.6); the F-35I's its yellow canopy lever on the left wall aft of the throttle (since
2026-11-25; before, the tool skipped it from when the lever sat behind the seat's side). Run the
tool again when a cockpit model or a control's place changes. From 2026-11-10
to 2026-11-15 the ORDER OF ACTIONS card listed the steps (a start-up's checklist, a take-off's `steps`) with their keys,
a step with the focus opening to its wait and picture; the user found a checklist the wrong thing to read before the
flight (2026-11-15).

**The map's chips** at the top inline end: **Labels** (the towns, the runways' designators, the base and the pins'
names) and **Photo** (the ground photo, else the TSD map's colours) each turn their layer off and on. The taxi and the
route are always drawn, navy over a pale edge. Until 2026-11-15 a **Taxi route** chip turned them off; it worked, but
the navy lines alone were lost on the dark photo, so the user saw it change nothing ("the taxi route button doesn't
show anything I think it isn't needed at all") and it was removed; **Zoom + / −** zooms around the middle of the room between the cards.

Focus: Tab runs the flights' tabs (several flights), Edit, Back, Arming, Fly, the chips, the map and the text, round;
the arrows move the same way on the screen (down from a mission to Edit, then Fly; from Fly toward the inline end the
text; up from the text's top the chips). Esc goes to the Hangar.

| the Sufa's start-up at Ramon, the explanation scrolled | the Adir's at Nevatim |
|---|---|
| ![The Sufa's start-up in Hebrew, the explanation scrolled to its switch pictures](pictures/front-end/startup_steps_f16i_he.webp) | ![The Adir's start-up in Hebrew, the explanation scrolled](pictures/front-end/startup_steps_f35i_he.webp) |

**The map** under the cards, north up, that zooms and scrolls over the whole built theatre. It opens on the base and the route: the start, the taxi
and the lineup with 400 m around them, at least 2.5 km across (IafBriefing's `focus`), fitted into the room between the
mission card, the chips and the text card, above the scale bar, with 40 px kept round it and room for the pins'
names on their right (so no panel covers a pin or its name; checked at 1280 × 720, 1920 × 1080 and 2560 × 1440 in both
languages). It frames again when the window or a card changes size. The mouse wheel zooms around the pointer
(from the whole theatre, 347 × 511 km, to 32× the mission's area, 1.25× a notch; one way per scroll, as the cockpit's
zoom: `Settings.zoom_steps` drops the reverse steps a Mac's scroll ends with), a drag with the left or middle button
scrolls, a double click shows the mission's area, fitted into the same room;
on a trackpad a two-finger scroll (`InputEventPanGesture`, and a wheel's horizontal notches) scrolls and a pinch
(`InputEventMagnifyGesture`) zooms around the pointer; with the focus, + and − zoom, the arrows scroll and 0 shows the
mission's area. The view's centre stays on the theatre, so a drag moves it at every zoom, the whole theatre too. Until
2026-11-15 the map held only the mission's area (the user's note after playing: "the map in briefing should
dynamically load more and not only the 'relevant' place"). Fixed 2026-11-10, the Mac's P1: at 1× the view was held
on the whole map, so a drag did nothing, and a trackpad's scroll and pinch arrive as gesture events, which the map
did not handle, so it could not be zoomed in to make a drag move. It draws:
- the theatre's ground colour, loaded by the view: the theatre's colour nodes ([terrain.md](terrain.md) §3, the
  flight's own tiles) at the level whose pixel is the largest within a screen pixel (2 m zoomed in on a base, 256 m
  for the whole theatre at 1080 px) and the two levels above it, coarser ones too where the finer have no node
  (`IafBriefing.tiles`, Rust's `briefing::Pyramid::tiles`). Coarse ones draw first, so a coarser picture shows while
  a finer one loads; until the view's first tile is in, the TSD map's colours show. They decode on two worker tasks as the flight's terrain decodes its nodes
  (`terrain.gd` `load_colour`: setup's BC1 `.dds` when there, else the JPEG, mipmapped). Every task is waited for
  when the screen closes or the game quits. At most 64 decoded tiles are kept (about 0.7 MB each); past that the
  ones seen longest ago that the view does not need go. Without the theatre the TSD map's polygons,
  `converted/own/cockpits/<jet>/map.json`, [data-formats.md](data-formats.md) §14;
- the main roads (the theatre's road layer `roads/main.bin`, [data-formats.md](data-formats.md) §15) over a dark
  casing: motorway to secondary, from 60 m a pixel to primary, from 200 m a pixel motorways and trunk roads only, no
  two points nearer than a pixel;
- the towns' names in the game's language (OpenStreetMap's places, `places.json`; the villages only where fewer than
  six towns and cities are in the box, the cities alone from 200 m a pixel; a name that would cover an earlier label
  or reach above the room between the cards, into the header's band, is left out).
  The roads, the towns and the TSD map's polygons come for the view (`IafBriefing.layers`, `briefing::layers`): for a
  box half a view larger on every side, asked again when the view leaves that box, or its scale changes
  twofold (Rust keeps `roads/main.bin` and `places.json` read once a process);
- the whole airbase as filled shapes: the aprons and the shelters' pads, the taxiways and the stopways at their
  widths, the runways at their widths; zoomed in (from 0.15 px a metre) their dashed centrelines, the parking spots
  and the runways' designators at their ends;
- the taxi from the parking spot to the lineup as a dashed line (the base's departure route, the one the sim's AI
  taxis), the route from the lineup through the mission's waypoints with an arrow, the runway end and its heading
  beside the first leg, the base's label at the whole map's zoom; zoomed out past the mission's area (past the
  zoom a double click or 0 shows, which keeps them) the runway's label and the pins' names stay off (the pins a few
  pixels apart), and a label whose place is off the map is left out;
- the mission's other flights (Kidon 2..; IafBriefing's `flights`): each from its start (a square) through its
  waypoints (rings) to an arrow, each in a colour of its own (orange, green, purple) apart from the player's navy,
  its callsign on a plate at its start, the one the Flights tabs pick wider;
- the pins: a disc in the accent with the number of the text's first paragraph done at its place, the place's name on
  a dark plate beside it ("Start", "Stop short of 25R", "Take-off · 246°"). The pins stay tied to the explanation:
  the places are Rust's (IafBriefing's `pins`): a paragraph's `at` in the mission's `briefing.how` (`start`, `hold`,
  `lineup`; [data-formats.md](data-formats.md) §5) moves the run there, a paragraph without one is done where the one
  before it was. Until 2026-11-15 the steps' `at` placed them and a run showed "Steps 1–3" under its name. The start is the parking spot, the holding point the taxi's last
  point before the lineup (iaf.ibx's `TaxiWayPtsFrom`, as the flight's radio menu takes it), the lineup the runway's.
  A take-off: paragraphs 1–3 at the parking spot, 4 at the holding point, 5–6 at the lineup; a start-up: its whole
  text at the parking spot.

The mission's area holds the runways, the start and the routes (the other flights' too) with 6 km around them, at least
50 km across. A north arrow (true north: the map is UTM 36N's grid, about 1° off) at the room's top inline-end corner
and a scale bar (100 m to 100 km, the longest within a quarter of the width) at its bottom beside the mission card
follow the zoom. The map never mirrors; in Hebrew its north arrow and scale bar swap sides. Its credit, OpenStreetMap's,
sits under the scale bar in 16 px type. Tested 2026-11-09 and dropped: the area beside a separate close-up of the base;
one zoomable map shows both and leaves each the whole page (the user's A14, round 4). From 2026-11-09 to 2026-11-14 the
briefing sat beside a list of the missions, in three tabs (Briefing, Map, Arming) switched by the arrow keys; the
map-first screen replaced them (the user's A25 round 3), the Arming page moving to the loadout screen.

Until 2026-11-25 the whole map's ground showed rectangles of other tones and a step at the border with Sinai: the
Survey of Israel sheets' own levels and the end of its coverage, where Sentinel-2 alone goes on. The border has been
toned since 2026-11-15 and the sheets to each other since 2026-11-25 ([terrain.md](terrain.md) §4).
That is the theatre's colour as built, the same in flight, not the map's drawing (checked 2026-11-14 on the Mac's
assets; inferred from the edges' places: not on the colour nodes' 32.8 km grid). Zoomed in on a base, the ground is
the base's toned Sentinel-2 (terrain.md §4).

**The loadout screen:** Edit on the Arming summary opens the Loadout screen (§10.1).

### 10.1 The Loadout screen

The picked mission's arming on a screen of its own (the user's round-3 design `r3_loadout`, 2026-11-13: "a look from
beneath the plane, where things really mount to"; saved loadouts "amazing idea"), opened by Edit on the briefing's Arming summary.
The crumb reads "Hangar · F-16I Sufa · Training · Take-off · Arming"; the mission's title opens its briefing, as do
Esc and the footer's Briefing. `modern-iaf/menu/loadout_screen.gd` builds it; `menu/arming_drawing.gd` holds its
editing pieces (the callout, the store, the stores' column).

- **The jet from beneath**, in the middle under "Seen from below, where the stores hang": the Hangar's live model
  (`shared/aircraft/turntable.gd`, the flight's own model with the stores hung as the flight hangs them) with its
  camera straight under the jet, the nose up the screen, still, lit from below, the F-35I's bay doors open with the
  bays' stores in view (`below`). The jet never mirrors: seen from beneath, its left wing (station 1) is on the right.
  Without the converted model (before setup) the callouts stand alone, with no lines.
- **The callouts:** one per station that takes a store (the record's `allowed`; the Adir's 2 / 10 take none, so they
  have none; the F-16s' centreline, 5, takes the 300 gal tank and stands under the jet), 170 × 84 px, in a column on each side of the jet, in the order of their
  stations' height on the screen, so the lines do not cross (a station on the middle line would sit under the jet): "6 · INBOARD" (the number and the station's place, the record's `positions`:
  WINGTIP, OUTBOARD, MID, INBOARD, CENTRELINE, BAY OUTBOARD, BAY INBOARD), the store's short name and its weight with
  the rack's ("1,321 kg" for a full 370 gal tank, its fuel and its own empty weight, `briefing::arming`'s slot `kg`); an empty station's frame is dashed
  with "Empty" / "ריק". A line runs from each callout's inner edge to a dot on its station: the station's attach point
  on the model, projected by the turntable's camera (`turntable.gd` `points`). A rack shows its "×3" badge at the
  callout's bottom corner. In Hebrew the callouts' text stands at their right.
- **LOADOUTS** at the inline start: the mission's own (its title, the badge "Mission" / "המשימה") and the pilot's
  saved loadouts for this jet (their names, the badge "Saved" / "שמורה", "×" to delete after a prompt), each with
  its stores in short ("4 × AIM-9M · 2 × AIM-120 · 2 × 370 gal tank"). The one on the jet is filled in the accent's
  tint; no bar at its side (the user, 2026-11-13: "remove the left bold border on loadouts"). A changed loadout that
  matches none leaves every row plain. A click puts that loadout on the jet. "+ Save this loadout" opens a name field
  in its place with a name offered ("My loadout, 14 Nov 2026"), selected; Enter or Save stores it (the same name
  again replaces that one; an empty name keeps the field open), Esc closes it. Between Mission and the saved ones the record's real loadouts
  (`real_loadouts`, [data-formats.md](data-formats.md) "Real loadouts"), each with the badge "Operational" /
  "מבצעית": the Sufa's "Air-to-air, long range" / "אוויר-אוויר, טווח ארוך" since 2026-11-25; the other jets have
  none yet (no sourced loadout of our stores).
- **TAKE-OFF WEIGHT** at the inline end: the figure, a bar with its share of the maximum ("70 % of the maximum, 23,582
  kg"), the wings' balance (a track from Left to Right as the pilot sits, in both languages, its middle marked, the
  marker where the stores lean: `balance`, the moment over the record's `lateral_limit_kgm`, else the wings'
  difference over their stores) with "Wings balanced" or "Left wing heavier by 1,321 kg", then Fuel (internal and the
  tanks'), Gun rounds and Chaff / flares. Over the maximum the figure, the bar and the share read in the warning
  colour and Fly is off; past the balance limit the marker and its line read amber (a warning: Fly stays on unless the
  record's `lateral_limit_hard`). A store that cannot be employed (a laser bomb with no targeting pod) also turns Fly
  and "+ Save this loadout" off, with one short warning-coloured line in the footer at the notice size, "GBU-12 needs
  the Litening pod" ([weapons.md](weapons.md) §7.1); the briefing's Arming summary shows the same line in its small
  text. A saved loadout from before that rule loads whole and shows the line. The chin callouts read 5R and 5L, the
  centreline's 5 (the record's `labels`); the centreline's callout stands under the jet, its 300 gal tank's alone.
- **STORES** under it: the stores the jet may carry (the record's `inventory`), two to a row, each its short name in a
  thin frame (the full name the tooltip), the ones left where the record gives a count (none does yet).
- **The footer:** "Reset to the mission's" at the inline start (off while the mission's own is on the jet), Briefing
  and Fly at the inline end, Fly the size of Briefing in the accent colour (the user, 2026-11-15: "the fly button in
  arming should be the same size as other buttons"). The briefing's larger Fly is the approved mock's; the debrief's
  buttons are all one size.
- **The keyboard, the joystick:** Tab runs the loadouts, Save, the callouts, Mirror, the stores, Reset, Briefing and Fly; the
  arrows move by place; the focus is the loadout on the jet when the screen opens.

The Sufa's take-off, its own loadout beside a saved one, the Adir's with its bays open, a one-sided edit and the racks:

| | English | Hebrew |
|---|---|---|
| the Sufa | ![The Sufa from beneath with its callouts, the loadouts and the take-off weight](pictures/front-end/loadout_f16i_en.webp) | ![The same in Hebrew, the columns mirrored, the jet not](pictures/front-end/loadout_f16i_he.webp) |
| a bomb dragged over station 3 | ![The callouts that take an MK-84 framed, the others dimmed](pictures/front-end/loadout_f16i_drag_en.webp) | ![The same in Hebrew](pictures/front-end/loadout_f16i_drag_he.webp) |
| the Adir | ![The Adir from beneath, its bays open with two AIM-120](pictures/front-end/loadout_f35i_en.webp) | ![The Adir in Hebrew](pictures/front-end/loadout_f35i_he.webp) |
| one station edited, Mirror off | ![An MK-84 on 3 alone, 7 keeps its AIM-9M; "Left wing heavier by 839 kg", the Mirror switch off](pictures/front-end/loadout_f16i_one_side_en.webp) | ![The same in Hebrew](pictures/front-end/loadout_f16i_one_side_he.webp) |
| racks, every store drawn | ![Two GBU-38 on a BRU-57/A on 3 / 7, three Mk 82 on a TER-9/A on 4 / 6, each bomb in its place](pictures/front-end/loadout_f16i_rack_en.webp) | ![The same in Hebrew](pictures/front-end/loadout_f16i_rack_he.webp) |

**The loadout editor** (the user, 2026-11-10: "can we already select ammunition?"):
- **Drag and drop.** A store drags from STORES onto a callout, from a callout onto another, or from a callout back
  onto STORES. While it is dragged, its picture (`modern-iaf/data/stores/<weapon id>.png`, our store models rendered by
  `modern-iaf/tests/_store_pictures.gd`) rides on the pointer, lifted a little over its shadow, and every callout whose
  station takes it, an empty one too, is framed in the accent colour and tinted, the others dimmed, so the player sees
  where it can go before the drop. A store on a station that holds another sends that one back.
- **Racks.** Where the record's `allowed` gives a station a rack (three Mk 82 on a TER-9/A on the F-16s' 3 / 7 and
  4 / 6, two GBU-38 on a BRU-57/A on 3 / 7, four GBU-39 on a BRU-61/A in the Adir's bays 4 / 8), a drop hangs the full
  rack (as many as are left), drawn on the jet with each store in its place ([weapons.md](weapons.md) §5); the callout shows a "×3" badge at its bottom corner; the stores count per store; the weight adds each store and the rack's `rack_kg` (the TER-9/A 47.6 kg, the BRU-57/A 120.2 kg, the BRU-61/A
  147 kg). In flight the station carries that many (`Settings.arm_loadouts`' count) and the rack's weight and drag
  (`sim_load`'s third and fourth values, `stores.rs` `rack_kg` / `rack_drag`); the rack stays on the jet when its
  stores go.
- **What a station takes.** The unit record's `allowed`, station by station ([data-formats.md](data-formats.md) §3:
  the table with its sources and what is inferred). A refused drop
  leaves the loadout as it was; its callout shakes for a quarter of a second with its frame in the warning colour, no
  text.
- **One station at a time; Mirror.** An edit changes the station it was made on, and only that one (the user,
  2026-11-15: "by default change only the station that was used"). "Mirror to the other wing" / "שיקוף לכנף הנגדית",
  a switch under the wings' balance, off when the game starts and kept while it runs, makes each edit fill the mirror
  station too (3 with 7, 4 with 6, the Adir's 4 with 8; the stations numbered from the left wing tip, so station n's
  mirror is the highest + 1 − n) where that takes the store; back to STORES, the mirror's store goes too when it is the
  same store; a move takes the pair along; the badge's count goes to both. Until 2026-11-15 every edit filled the
  pair unless Shift was held; Shift does nothing now. The pair rule stays in `loadout.rs` (`pair`), the switch passes
  it. An uneven load shows in the wings' balance ("Left wing heavier by 925 kg", amber past the limit); saved
  loadouts keep each station's store.
- **The keyboard and the joystick.** Enter on a callout picks it and puts the focus on the first store its station
  takes; the arrows move through the stores, Enter hangs the store (its mirror's too with Mirror on). An
  "Empty" / "ריק" entry heads the stores while a picked callout holds a store: Enter there takes it off. Esc leaves
  the callout as it was (a second Esc goes back to the briefing).
- **Not yet flyable.** A store whose record has no model of ours is greyed in STORES (every listed store has one
  since the 600 US gal tank's, 2026-11-20): it neither drags nor takes the focus, and nothing says why (the user, A15
  round 3: "disabled for now"). Its record stays.
- **The rack's count.** The "×n" badge on a rack's callout is a control: a click takes one store off, from one back to the
  full rack (a TER 3 → 2 → 1 → 3, a BRU-57/A 2 → 1 → 2), the mirror's along with Mirror on, the weight and the
  stores following (`loadout::cycle`). The keyboard: Enter on the callout, then Enter on the store it holds.
- **The wings' balance.** The stores' rolling moment (each station's stores and rack at its distance from the jet's
  middle in the drawing) against the record's `lateral_limit_kgm` (the F-16s: 25,020 ft-lb, 3,459 kg·m,
  [data-formats.md](data-formats.md) §3); past it the balance's marker and line read amber with the heavier wing and
  the difference in kg. A warning: Fly stays on unless the record's `lateral_limit_hard` is true.
  The sum, the wings' shares and the moment come from `loadout::weigh`, the weight rule reborn's Arming screen uses
  too; each game keeps its own limit (reborn the original's 5 % of the load, the sim the jet's moment).
  The Adir's limit is open, so it never warns; its gauge shows the wings' difference over their stores.
- **The figures** follow each change: the fuel, the take-off weight against the maximum. Over the maximum the
  take-off weight reads in the warning colour and Fly is off (no sourced loadout reaches a jet's maximum:
  `loadout::tests` hangs the heaviest store on every station of the Sufa and the Adir and stays under it).
- **Kept per pilot per jet** in the records database (`loadouts`, [storage.md](storage.md) §5), stored at each change;
  the Hangar's jet carries it too (§12). Reset to the mission's brings back the mission's own load
  (its `loadout`, [data-formats.md](data-formats.md) §5: the range lessons'), else the record's default. The saved
  loadouts are the pilot's per jet (`saved_loadouts`, the same database).
- **In flight.** Fly hands the stored loadout to the mission start (`flight/fly.gd` `arm`): pylons A..I as the engine
  holds them (`IafBriefing.sim_load`: each store's weapon record number and count, or the record's `sim`, the
  `modern_weapons.gd` record flown in its place: the GBU-31's 1003; and its rack's kg and drag) in
  `Settings.arm_loadouts` for the player's flight, which the stores code loads in place of the record's pylons
  (`player_weapons.gd` `_armed`): their mass and drag through the stores weight path, the tanks' fuel, their models
  on the jet. The gun rounds, chaff and flares stay the record's.
- **A mission that fixes the loadout** (`fixed_loadout: true` in its readable file, [data-formats.md](data-formats.md)
  §5) shows the mission's own load (else the record's default) read-only: no drag, no Reset, no saved loadouts, nothing said about it. No training mission fixes it.
- **The rules are Rust's:** `iaf_tools::loadout` (`crates/iaf-tools/src/loadout.rs`: `allowed`, `mirror`, `put`,
  `take`, `shift`, `sim_load`) behind `IafBriefing.put / take / shift / sim_load`; the weights `briefing::arming`;
  the store `pilot_log::loadout / set_loadout / saved_loadouts / save_loadout / delete_saved_loadout` behind
  `IafPilotLog`. `menu/loadout_screen.gd` and `menu/arming_drawing.gd` only drag, drop and display.
- **Checks:** `cargo test -p iaf-tools --lib loadout` (the Sufa's rules, pairs, racks, moves and pylons; the Adir's
  bays, the AIM-9X on the wingtips only, the GBU-39 rack; the badge's cycle; a one-sided load past the Sufa's limit; the heaviest loadouts under the maximum; the store round trip
  and the version-3 file migrated; `pilot_log` the saved loadouts per pilot per jet);
  `modern-iaf/tests/test_front_end.gd` (the screen from Edit, its crumb, a callout per station with its
  place and weight, the stations' places on the model with the left wing on the right, the mission's row on without a
  side bar, the columns mirrored, the weight panel's figures, Fly the size of Briefing, a refused drop, Mirror off: one
  station changed and the wings uneven, Mirror on: a pair, a tank pair back, six Mk 82 drawn on two TERs, the keyboard
  path and Esc, a TER on 4 / 6, its badge 3 → 2, the Delilah not offered, a one-sided load's amber balance, the
  flight's pylons, the Hangar's jet, save / pick / delete a saved loadout, a lowered maximum, Reset; both languages); `test_mvp.gd --only loadout` (a take-off with MK-84s on 3 / 7 and three Mk 82 on 4 / 6: the pylons
  and counts, the stores' mass, no tanks' fuel, the bomb's model, the gun's rounds). `modern-iaf/tests/_loadout_shot.gd` takes the pictures; `modern-iaf/tests/_store_pictures.gd` renders the stores'.

The Loadout screen's jet is our own model; the attribution those models need
(the FlightGear F-16, GPL; andertan's F-35, CC BY 4.0) is in docs/credits.md, the setup wizard's Attributions and the
credits roll.

The geometry is Rust's: `iaf_tools::briefing` (`crates/iaf-tools/src/briefing.rs`) behind `IafBriefing.map(mission,
airbases, map, aspect)` (`crates/iaf-godot/src/briefing.rs`) reads the readable mission, the airbase files and the
compiled map, and answers the map in its own metres (x east, y south from its north-west
corner):

| key | meaning |
|---|---|
| `base`, `runway`, `heading` | the base's name, the take-off runway end and its grid heading (null for a start-up) |
| `north` | true north as a grid bearing (deg) |
| `size`, `extent` | the map's width and height (m) and its box in the sim's frame, at the screen's aspect: the runways, the start and the route with 6 km around them, at least 50 km on the shorter side |
| `fills` | the map's polygons cut to the map, in paint order: `color` and `tris` (triangles, `iaf_formats::emf::fill_triangles`, as `IafEmf`) |
| `runways` | each `[x0, y0, x1, y1, width, designator 0, designator 1]` |
| `taxiways`, `stopways`, `aprons`, `shelters`, `parking` | the base's paved shapes (`{w, pts}` for a taxiway) and spots |
| `roads`, `places` | the map's main roads (`{class, pts}`) and towns (`{kind, en, he, at}`) |
| `start`, `taxi`, `route` | the start; the taxi (the base's departure route, `sim_bases::routes`, when the runway is the base's take-off end); the lineup and the waypoints |
| `pins` | the text's places in paragraph order: `{place, at, first, last}`, `place` one of `start`, `hold`, `lineup`, `first` / `last` the run's paragraphs of `briefing.how` (from 0) |
| `focus` | the view the map opens on `[x0, y0, x1, y1]`: the start, the taxi and the lineup, 400 m around them, at least 2.5 km across |
| `theatre` | the whole built theatre `[x0, y0, x1, y1]` (its `meta.json`), where the view may go; null without it |

`IafBriefing.layers(map, theatre, view, origin, m_per_px)` answers `fills`, `roads` and `places` over a view (the
map's metres from `origin`, the map's north-west corner in UTM metres). `IafBriefing.tiles(theatre, view, origin,
m_per_px)` answers the colour nodes that draw it, coarse to fine, `[level, i, j, x0, y0, x1, y1]` each.
`IafBriefing.arming(unit, weapons, loadout)` answers the Loadout screen's figures (`briefing::arming`).
`modern-iaf/menu/briefing_map.gd` draws the map, `modern-iaf/menu/briefing_page.gd` lays out the screen. `modern-iaf/tests/_briefing_shot.gd` takes the pictures (its header).

| | English | Hebrew |
|---|---|---|
| start-up at Ramon (2011) | ![The start-up's briefing](pictures/front-end/briefing_2011_en.webp) | ![The start-up's briefing in Hebrew](pictures/front-end/briefing_2011_he.webp) |
| take-off from Ramon (2012) | ![The take-off's briefing](pictures/front-end/briefing_2012_en.webp) | ![The take-off's briefing in Hebrew](pictures/front-end/briefing_2012_he.webp) |
| the take-off, the explanation focused and scrolled | ![The take-off with its explanation scrolled](pictures/front-end/briefing_2012_text_en.webp) | ![The same in Hebrew](pictures/front-end/briefing_2012_text_he.webp) |
| the take-off, labels and photo off | ![The take-off's map without labels or photo](pictures/front-end/briefing_2012_plain_en.webp) | ![The same in Hebrew](pictures/front-end/briefing_2012_plain_he.webp) |
| the take-off, zoomed out to the whole theatre | ![The map zoomed out to the whole theatre](pictures/front-end/briefing_2012_theatre_en.webp) | ![The same in Hebrew](pictures/front-end/briefing_2012_theatre_he.webp) |
| two flights (the test sample `modern-iaf/tests/data/two_flights.json`), Kidon 2 picked | ![Two flights, Kidon 2 picked and its route in view](pictures/front-end/briefing_two_flights_en.webp) | ![The same in Hebrew](pictures/front-end/briefing_two_flights_he.webp) |
| the take-off, scrolled 100 km north of Ramon (2×) | ![The map far from the base, near Beit Shemesh](pictures/front-end/briefing_2012_far_en.webp) | ![The same in Hebrew](pictures/front-end/briefing_2012_far_he.webp) |
| the same place zoomed in (24×, the 2 m photo) | ![The map zoomed in far from the base on a village](pictures/front-end/briefing_2012_far_close_en.webp) | ![The same in Hebrew](pictures/front-end/briefing_2012_far_close_he.webp) |

### 10.2 The PRE targets panel

The GPS bombs' pre-planned targets (A61, the user's pick of option A on 19 Nov 2026: "A61: a"). With a GPS store on
the jet (a weapon record with `guidance` "gps": the GBU-31, GBU-38, GBU-39, SPICE 1000 / 2000, Delilah), the map's
chips start with **PRE targets** (`MapPre`). On, its panel (`PreTargets`, `menu/pre_panel.gd`) takes the text card's
place, and off gives the text back:

- the heading, a line on how to pick, the rows, a rule and a footer naming the default (the route's target
  steerpoint) and the key that steps the targets in flight (record 207, Shift + K);
- a row per GPS station in station order (`PreRow_<station>`: "STA 4", the store, the target at the inline end); a
  rack (the F-35I's four GBU-39, the F-16's two GBU-38) opens on a click into a row per bomb (`PreRow_<station>_<n>`,
  "4-1" the first to leave), and stays open while one of its bombs has a target of its own;
- a row's target: its own pick in amber; else, muted, the station's ("Target 2 · as station") or the default
  ("Steerpoint 2 · default"); the armed row reads "click the map…" in the accent's text colour and the pointer is a
  cross over the map.

A click on a row arms it (again: disarms; a rack's station row opens or closes its bombs). The next left click on the
map gives it the mission target or steerpoint within 24 px of the click, else the point itself. A right click on a
row, or Delete with the focus on it, clears it; a station's clear clears its bombs' own picks. The map draws every
mission target as an amber box with its name, and under each place aimed at the stations or bombs aimed there on an
amber tag ("4-1 4-2 4-4"); a map point is an amber cross. The rows and the clicks are the shared PRE pick's
(`shared/weapons/pre_pick.gd`), the 1998 game's briefing TSD's ([../../docs/front-end.md](../../docs/front-end.md) §8.2).

The picks are kept with the pilot's loadout for the jet, as its `pre` (data-formats.md §3), so the Loadout screen's
saved loadouts keep them and a loadout saved before has none; a mission's own `loadout` may carry them the same way.
One rule in Rust decides which picks stand (`gps.rs` `pick_ok`, through `briefing::pre` / `pre_set`): the station
holds a GPS store, a bomb's own pick is on a rack and one of its bombs, a target or steerpoint is one the mission has
(by number, so a saved loadout aims at the same numbers on another mission), a map point was made on that mission. A
pick the rule refuses is not made and the panel says so in one line; a pick that no longer stands (another mission, a
station's store changed on the Loadout screen) is left out everywhere: the panel, the flight and the next save. As the
flight starts, `flight/fly.gd` `pre_targets` hands the picks to `Settings.gps_targets` (docs/weapons.md §13.2).

## 11. The crash page

Every failure the sim cannot go on from ends on one page, never in an empty world or a loading screen that never ends
(the user, 2026-11-10: "every error is a crash"). `Settings.crash(what, step)` (`modern-iaf/sim_settings.gd`) opens
it over everything, on its own canvas layer, and pauses the game under it. The log gets `crash: <what> (loading step
<step>)`; a flight's start then stops building, and its last line is `loading: stopped at <step> by the crash page`.
A scripted start (`tests/godot/base.gd` `start_mission`) fails at once with `RESULT FAIL` (2026-11-11: a bench whose
settings asked the sim for the original's cloud art crashed at the start, and the log read as a hang after its steps). `modern-iaf/menu/crash_page.gd` draws it in
the front end's look (§4), mirrored in Hebrew. It shows:

- the title "Modern IAF stopped" ("הזרוע הארוכה נעצרה");
- what failed, in one line;
- the loading step it happened in, when it happened during a flight's start, by the name the loading screen shows
  in the page's language ("While loading: The ground around the base", "בזמן הטעינה: הקרקע סביב הבסיס"; a sub-step
  such as "terrain, after tiles" by its step, the first frames as "The first frames"; the issue keeps the logged step);
- the log file's path (docs/logs.md); in Hebrew one left-to-right run (an isolate), so its slashes stay in order
  (F10, 2026-11-16: the leading "/" jumped to the line's end).
- **Report the problem on GitHub:** opens a new issue on `github.com/assapir/iaf-reborn` in the browser
  (`OS.shell_open`). The title is the failure's line. The body holds the step, the build (the extension's commit, the
  Godot version), the OS and its version, the GPU, its vendor, the renderer and the driver API, then the log's last 60
  lines. The link stays within 8,000 characters: the log's oldest lines go first;
- **Quit.**

What opens it:

| failure | where |
|---|---|
| any error (`push_error`, a script error, an engine error, a shader error) while a flight starts | the timed log (`shared/util/timed_log.gd`) hands it to `Settings`; `Settings.loading_step` set from the flight scene's start to its 10th frame after the loading (step "first frames", `terrain_view.gd _first_frames`) |
| the loading stopped (paused under the screen, or no progress for 30 s) | the loading screen's watchdog (§7) |
| a shader in use that did not compile, or a shader error in the log, after the first 10 frames | `Settings.flight_drawn` (§11.1) |
| a mission the compiled list lacks | `flight/fly.gd start` |
| the terrain's `meta.json` missing | `shared/terrain/terrain.gd` |

The original game keeps its behaviour: there `Settings.crash` does nothing more than the error already in the log.

`modern-iaf/tests/test_start_watch.gd` opens it three times headless (a shader that does not compile, a pause under the loading screen, a missing mission) and checks
the issue link's title and body fields, its length cut, and both buttons.

### 11.1 Finding a graphics failure: the shader check and the bisect switch

After a flight's first 10 frames the sim logs every shader the scene draws with (`shader: ok <file> (<n> uniforms)`, the
sub-viewports' too) and a summary (`shaders: 24 in use, 0 failed, 0 shader errors logged`). A shader failed when its
uniform list is empty while its code declares uniforms (the compile failed), or when the log caught a `SHADER ERROR` or
an error naming a shader or the Metal driver. Any failure opens the crash page with the shader files. The log also
times the first world frame (`loading: first world frame drawn at <ms>`) and the 10th.

The bisect switch turns graphics features off for one run, whatever the settings say:

    IAF_SAFE=all ./start-modern-iaf            # every feature below off
    IAF_SAFE=sky,water,clouds ./start-modern-iaf
    ./start-modern-iaf --safe sky,water        # the same as a flag (Windows: .\start-modern-iaf.ps1 --safe sky)

| name | off means |
|---|---|
| `sky` | the plain gradient sky instead of the Atmospheric (`atmosphere.gdshader`) |
| `grading` | colour grading Original |
| `closeup` | no terrain close up |
| `textures` | the ambientCG ground textures off |
| `water` | the flat water |
| `clouds` | no volumetric clouds |
| `scenery` | no buildings or trees |
| `shadows` | no sun shadows |
| `taa` | MSAA 4× instead of TAA or the temporal upscaler (MetalFX / FSR 2) |
| `upscaling` | the 3D view at full size |
| `cockpit_origin` | the cockpit drawn in the flight's world (no `cockpit_composite.gdshader` over the view) |
| `patches` | the terrain close up's colour patches off (`terrain_patches` 0) |
| `glass` | no combiner glass in the 3D cockpit; the HUD drawn plain (no `hud_glass.gdshader`: unclipped, not added) |
| `hudglow` | the HUD drawn over the scene in its plain colours, not added as light |

Each name in force is logged at the start (`safe: sky off (sky atmospheric -> original)`); an unknown name is a warning. The
settings file keeps the player's own values. To find a failure, start with `all`, then turn half the names back on per
run. `test_start_watch.gd` checks that each name turns its feature off and that a flight starts with all of them.

## 12. The Hangar

The Hangar is the sim's first screen (the user's A25, 2026-11-13: "hanger is great idea"; "home should be replaced with
hangar everywhere", Hebrew דת"ק). It replaces Home, Pick a plane and the jet's Training page. The mock-ups it follows:
round 3 of the menu ideas (`r3_hangar_en.png`, `r3_hangar_he.png`, outside the repo).

| what | where, from what |
|---|---|
| the top bar | the logo (§4) and the Hangar crumb; Settings (the gear and the word; "הגדרות") and the pilot (the nickname, the name under it, the picture or initials: one button to the Pilot screen) at the inline end |
| the jets | at the inline start under "Aircraft" / "מטוסים": the full name ("F-16I Sufa"), the squadron's number and the base; the Ra'am and the Baz greyed (§2). A click, or Enter on the focused row, picks the jet; the arrows move between the rows and on to the card |
| the jet | in the middle, standing still in its start view; the player looks at it from any side (below); its full name in large faint letters behind it; no help line (the user: "it should be obvious you can use the mouse") |
| the card | at the inline end: the full name, then this jet's own data, the same three for every jet (the user, A31: "Just the specific plane data"): Squadron (its number and name, the airbase file's), Base and Tail number (the unit record's, the number painted on the model); no type figures (weight, gun rounds, radar range: tried 13 November and dropped by the user). Then Fly (focused on entry; opens the Missions screen, §2). The card shows no training progress: the course's progress belongs in the Pilot screen's logbook (Approvals A135, not built yet). Without missions (the sim's data not built) the box says so with the command `./modern-iaf-setup` on a line of its own (Windows: `.\modern-iaf-setup.ps1`) and Fly is greyed, out of the focus |
| the foot | Attributions at the inline start: the models' credits live there (`docs/credits.md`; the FlightGear F-16 is GPL, the F-35I CC BY 4.0, neither asks for a line on the screen) |

**The jet's view** is `shared/aircraft/turntable.gd`: the flight's own model through `AircraftModel.create` (the same
file, descriptor and gear-down ground pose as the flight; the plane folder is the aircraft definition's base, else its
id), with the stores hung as the flight hangs them (`PlayerWeapons` store models, `IafStores` slots, bombs and tanks by
their top from the station's lugs). The stores are the loadout the Loadout screen shows (§10.1): the pilot's for the
jet, else the unit record's (the missions' own), each on the pylon its real station maps to (`IafBriefing.arming`'s
slot `pylon`: the F-35I's station 5 is D); the F-35I's bay stores stay inside its shut bays, as in flight. The Loadout
screen shows the same turntable from beneath (`below`: the camera straight under the jet, still, the bays open). It renders in a SubViewport of its own world at the window's pixel size
of its area (the canvas is scaled to the window, so a SubViewportContainer would render at the canvas size and blur),
with MSAA 4× and one shadowed sun, and only while it is shown: a hidden or freed turntable, or a minimised window,
renders nothing. When the model's converted descriptor is missing (no `assets/converted/own/planes/f16` before setup)
no model load is tried, and when the model does not load, a still picture of the jet takes its place, `modern-iaf/data/hangar/<unit>.webp` (rendered by `_hangar_shot.gd` `STILLS=1`).

The jet stands still; the player orbits the camera round it (the user, 15 November 2026: "the planes in the hangar
should be able to look from all directions, not only move right to left and not move by default"):

| input | what it does |
|---|---|
| mouse drag | sideways turns the jet all the way round (0.35° a pixel); down raises the camera, up lowers it, from 45° under the jet's level to 80° over it (the camera's up never flips, and it never goes inside the jet) |
| mouse wheel, a trackpad's two-finger scroll or pinch | zoom, from 0.6 to 1.6 times the start distance (1.1 times a step); one way per scroll (`Settings.zoom_steps`, as the cockpit's zoom) |
| gamepad right stick, triggers | the stick orbits (120° a second at full push), the right trigger zooms in, the left out; the first known gamepad (`Input.is_joy_known`: a flight stick's axes 2 and 3 are often a throttle or rudder resting off centre) |
| with the focus: the arrows (and the D-pad), + / − | orbit 6° a press, zoom a step |
| double click; with the focus 0, Home or the right stick's click | back to the start view: the nose toward the inline start (−20°, in Hebrew 107°), the camera 16° over the jet's level, the start distance |

The view carries over between pages and jets (the next jet picked is seen from where the last one was); a switch of
language turns the jet to the new layout's start. A caller sets a start view through the script's static `yaw`, `pitch`
and `zoom` before `show_jet()` (`yaw` NAN: the layout's start turn). The view takes the focus by Tab (between the jets
and Fly) or a click. Only the keyboard's or a gamepad's focus shows a ring, the theme's faint one (`Turntable` in
`look.gd`); a click's focus is hidden (`grab_focus(true)`), so no frame shows while the jet is dragged (the user, 15
November 2026: "remove the white borders around it"; the frame was Godot's default focus box, which the view drew
while it held a click's focus).

**The gear** (`Look.gear_icon`): our own drawing of eight teeth round a hub, in the text colour, stroked as the radio
rings; drawn at four times its size and mipmapped, so it stays crisp from 1280 × 720 to 2560 × 1440. It stands
before Settings in the Hangar's top bar and on the pause menu, and before the Settings screen's title (it replaced a
sun-like ring of rays, the user, 15 November 2026: "the sun icon on the setting button is wrong").

**Frame cost** (`_hangar_shot.gd`, the user's Mac, 13 November 2026; measured with the jet turning, the same work as the view standing still or moving): the turntable adds about 1.3 ms of GPU time a
frame at both 1920 × 1080 (its area 1070 × 800 px) and 2560 × 1440 (1426 × 1066 px), and 0.1 ms of the renderer's
CPU time. On the Iris Xe laptop (`COST_ONLY=1`, 1920 × 1080): the turntable 7.1 ms of the GPU's time, the whole
Hangar frame 14.2 ms with it (7.1 ms without), about 70 frames a second, so it draws every frame at full quality. The
in-flight graphics budget (about 1 ms for an extra) does not apply: nothing else is drawn on the menu. A 30 Hz cap
would come in only if the whole frame passed 16 ms.

**The focus** (F1, 2026-11-14): Tab goes Settings → the pilot → the jets → the jet's view → Fly → Attributions and
round (the view by Tab only: with the focus, its arrows orbit the jet). Down from
the top bar goes to the picked jet, Down from the last flyable jet to Attributions, toward the inline end from a jet to
Fly, Up from Fly to Settings; Down from Fly stays (it went to the foot first, the inventory of 14 November).

**Esc** on the Hangar asks "Quit the sim?" / "לצאת מהסימולטור?" (Cancel focused), and so does **Quit** / "יציאה" at
the foot beside Attributions (2026-11-17, the user: "we don't have a quit button"; Home's Quit had gone with Home, with
its greyed Guides). The window's close button and the system's quit key (Cmd+Q on a Mac, Alt+F4 elsewhere) quit at
once, from any screen and from a flight (`Settings._notification`: the window's close request, `Settings.quit`).


## 13. The debrief

The approved mock r3_debrief (the user, A25 round 3, 2026-11-13: "awesome"; "maybe heights / G scales / graphs?"),
built by `menu/debrief_page.gd`:

- **The sheet** at the inline start: Plane flown, From, Time (the day with the month named in both languages, "2 Nov
  2026" / "2 בנובמבר 2026", and the mission clock from the start to the end), Mission, Result; GOALS, each row a mark
  (✓ met, ! off the mark with the mission passed, ✗ failed), the goal, its target ("25R", "max 22.6 m", "246° ±10")
  and the flown figure; REMARKS: the reason that failed it or that it passed, then "Next time:" with the scorer's
  tip. All of it is the Rust scorer's record ([training.md](training.md) §4); the sheet ends after Remarks. Its cells'
  1 px rules are anti-aliased so they show at 1280 × 720. A flight with combat (2026-11-24) has COMBAT / "קרב" between
  GOALS and REMARKS: that flight's four totals as on the Pilot screen's logbook (the Pilot screen above), the jets lost
  in red when any.
- **The whole flight on the map** at the inline end: the briefing map (§10) of the mission with the recorded track
  over it (IafTraining.track, [training.md](training.md) §4.1), coloured by phase over a dark casing, the planned
  taxi and route, pins at the start (a disc), the lift-off (a ring) and the end (a square) with their mission-clock
  times, opened on all of the track; the base inset at its bottom left (the start and the taxi, the briefing's view);
  the legend of the phases flown and the planned route. With the focus it zooms and scrolls as the briefing's map.
- **The flight**: the phase band over three graphs against the mission clock, speed (kt), height above the ground
  (ft) and load (g), with the marked events (the rotation's load, the lift-off speed, the gear-up height, the highest
  load; a touchdown, crash, hit or ejection as a line across all three). The clock runs left to right in Hebrew too:
  clock times and numbers read left to right in Hebrew, and the approved Hebrew mock draws it so.
- **The footer**: Pilot log, Export flight data and (a flight with combat) More stats, that flight's page, at the
  inline start; Back to missions, Fly again and Next mission
  at the inline end, the last the primary and focused. Tab and Shift + Tab go round the map and the buttons; Up from a
  button goes to the map; with the focus on the map the arrows scroll it and Tab leaves it.
- A record without a recording (records from before it, a flight file deleted) shows the sheet, and both panels of
  the right column say "This sortie has no flight recording."; Export flight data is greyed and out of the focus.
- Hebrew mirrors the page: the sheet at the right, the map and graphs at the left; the map and the graphs never
  mirror.
- The sample flight for the tests and pictures: `modern-iaf/tests/data/ramon_takeoff_flight.jsonl`, a synthetic
  take-off at Ramon written by `sample_flight.py` beside it (its header).

| screen | English | Hebrew |
|---|---|---|
| the debrief of the sample flight | ![Debrief](pictures/front-end/debrief_en.webp) | ![Debrief, Hebrew](pictures/front-end/debrief_he.webp) |
| at 1280 × 720 | ![Debrief at 1280 × 720](pictures/front-end/debrief_1280_en.webp) | ![Debrief at 1280 × 720, Hebrew](pictures/front-end/debrief_1280_he.webp) |

## 14. The Settings

The Settings follow the approved mock r3_settings (the finish list's F7, 2026-11-16).

- **Search** (the field beside the title): the rows of every section whose name, description or choices hold every
  word typed, in English or Hebrew, listed under their sections' names. While it is set no section is lit and each
  section's count is its matches; cleared, the counts are the sections' rows again.
- **Preset** (Graphics' first row): Laptop, Balanced, High and Everything on set the seven graphics settings below at
  once (`shared/util/pref_choices.gd` `PRESETS`); a choice this computer cannot pick (Volumetric clouds without their
  support, Buildings and trees without their setup step) is left at its default. Custom lights when the settings match
  no preset; it is never a pick.

| setting | Laptop | Balanced | High | Everything on |
|---|---|---|---|---|
| Antialiasing | MSAA 4× | MSAA 4× | MSAA 4× | MSAA 4× + FXAA |
| Upscaling | Balanced | Quality | Native | Native |
| Shadows | on | on | on | on |
| Long shadows | off | off | on | on |
| Terrain detail | 50 % | 75 % | 100 % | 100 % |
| Clouds | Flat layer | Flat layer | Flat layer | Volumetric |
| Buildings and trees | Off | On | On | Detailed |

- **The pane** (inline end): the hovered or focused setting's name and what it does (strings `<setting>_about`); for
  a graphics setting its Off / On picture (§14.1) and the frame time measured on this computer (§14.2).
- **Devices:** with no joystick connected, Flight controls, Rudder and Throttle show Keyboard with the device's choice
  greyed (Joystick reads no axis then); the stored choice comes back when one is plugged in. The afterburner detent is
  Off or "Set at lever" (once set, its percent). The Keys and Joystick screens use the Settings' frame (title row, side
  list and columns at the same places); the Joystick screen has no axis rows with no joystick connected.
- **Footer:** Defaults (the section's rows, or the search's matches, back to their defaults by
  `Settings.default_value`, as reborn's DEFAULT; the language kept), Export / Import settings file (§2) and Back to the
  hangar. Over a flight: Defaults and Back (to the pause menu).

### 14.1 The cost chips and the Off / On pictures

Each graphics row carries a chip naming the frame time its current choice adds on the Iris Xe laptop over the row's
plain choice (Off, Native, MSAA 4×, Flat layer, the lowest terrain detail): saves (under −0.3 ms), none (under
0.3 ms), low (under 1.5 ms), medium (under 4 ms), high (amber, 4 ms or more); a difference smaller than the
measurement's noise reads "under" the noise (below). Full screen and VSync cost no GPU time and read none.

How the costs were measured: `tools/settings_cost.sh` runs the flight bench (`modern-iaf/tests/_flight_bench.gd`)
on this Linux laptop (Intel Iris Xe, a 1920 × 1080 window): the take-off mission's jet held over Tel Aviv at 500 m
for 12 s once the ground has streamed in, cockpit view, VSync off, the random draws seeded so the cloud layer is the
same. Each choice that differs from the preset High is run right after a run of High. The High runs spread over a few
ms: the laptop's integrated GPU shares its power with the processor, and other work on the laptop (on 2026-11-16 a
second session's tests) slows it (High read 30 to 36 ms). So a choice's cost is its run's average GPU time minus the
median of all the High runs, and the noise (`noise_ms`) is half the High runs' spread (the largest minus the smallest); a
difference smaller than the noise reads "under" the noise (below). The results go to `modern-iaf/data/settings/cost.json` with the date,
the computer and High's median time (`base_ms`). Terrain detail's chip interpolates between its measured
points (50 %, 75 %, 100 %).

The measurement of 2026-11-16, evening (High's median 30.1 ms, noise 3.3 ms; other sessions'
jobs ran on the laptop between the runs, so the noise stayed high, as at the first measurement that morning: 31.6 ms,
noise 2.9 ms). A choice other than its row's plain one whose difference is smaller than the noise reads "under
3.3 ms" ("פחות מ־3.3 מ"ש"): no cost found, at most that much; the plain choice reads none.

| setting | choice | GPU time against High (ms) | chip |
|---|---|---|---|
| Antialiasing | MSAA 4× | +0.0 | none |
| Antialiasing | MSAA 4× + FXAA | +1.1 | under 3.3 ms |
| Antialiasing | TAA | -10.0 | saves |
| Antialiasing | FSR 2 | -3.0 | under 3.3 ms |
| Upscaling | Native | +0.0 | none |
| Upscaling | Quality | -3.0 | under 3.3 ms |
| Upscaling | Balanced | -6.6 | saves |
| Shadows | off | -3.1 | none |
| Shadows | on | +0.0 | under 3.3 ms |
| Long shadows | off | -0.5 | none |
| Long shadows | on | +0.0 | under 3.3 ms |
| Terrain detail | 50 % | +3.1 | none |
| Terrain detail | 75 % | +4.0 | under 3.3 ms |
| Terrain detail | 100 % | +0.0 | under 3.3 ms |
| Clouds | Flat layer | +0.0 | none |
| Clouds | Volumetric | +3.7 | medium |
| Buildings and trees | Off | -0.9 | none |
| Buildings and trees | On | +0.0 | under 3.3 ms |
| Buildings and trees | Detailed | +4.5 | high |

The Off / On pictures are our own renders: `modern-iaf/tests/_settings_previews.gd` flies the same mission twice per
setting with High but for that setting's two choices (`data/settings/previews.json`), the jet over Tel Aviv at 350 m in
the cockpit view, and joins the left half of the first picture to the right half of the second
(`data/settings/<setting>.webp`, 840 × 472; Antialiasing and Upscaling show the view's middle at the screen's own
pixels, where their difference shows). Full screen, VSync and the other sections have no picture.

### 14.2 The frame time measured on this computer

Every flight measures its own frame time from its 10th to its 30th second (`modern-iaf/flight/frame_meter.gd`): each
frame's cost is the larger of the GPU's time and the CPU's (the scripts' process and physics time plus the render
thread's draw calls), so VSync's wait does not count. The average is kept with the window's size and the graphics
settings it was taken with (`Settings.frame_measured`, `settings.cfg` `[sim] frame_measured`). The pane shows it on a
bar up to 33 ms with a line at 60 frames a second (16.7 ms). When the graphics settings now differ from those it was
measured with, a line under it gives the estimate for the settings now: the measured time scaled by the ratio of the
two configurations' Iris Xe frame times (§14.1). Before the first flight the pane says it is not measured yet.

| screen | English | Hebrew |
|---|---|---|
| Graphics with the pane on Buildings and trees | ![Settings, the pane](pictures/front-end/prefs_about_en.webp) | ![Settings, the pane, Hebrew](pictures/front-end/prefs_about_he.webp) |
| a search | ![Settings, a search](pictures/front-end/prefs_search_en.webp) | ![Settings, a search, Hebrew](pictures/front-end/prefs_search_he.webp) |
