#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Missions screen")The #scr("missions") screen opens from the #term("Hangar")'s #scr("fly"). It holds the picked jet's missions, in sections.

#screen("missions", [The #scr("missions") screen: a card for each section.])

=== The sections <mission-list-sections>

Each section is a card with its number, its title and, at its foot, your progress in it: how many of its missions you passed, and a bar.

#grid-table(
  (auto, 1fr),
  ([Section], [What it holds]),
  [#scr("sec_training")#idx("Training")], [Each jet's three lessons from its home base: #scr("kind_startup"), #scr("kind_takeoff") and the weapons range (@lessons).],
  [#scr("sec_campaign")#idx("Campaign")], [Comes in a later version. The card is greyed and marked #scr("coming_later").],
  [#scr("sec_single")#idx("Single missions")], [Comes in a later version. The card is greyed and marked #scr("coming_later").],
  [#scr("sec_fly_now")#idx("Scramble")], [A quick fight against an enemy drawn at random, with the task given by the #term("AWACS") (@mission-list-scramble). The card shows no progress.],
)

A greyed card takes no click and no focus.

=== A section's list <mission-list-rows>

Selecting #scr("sec_training") opens its list: the picked jet's missions in order, numbered from 1.

#screen("section", [The list of #scr("sec_training"), with the panel on the mission under the focus.])

#grid-table(
  (auto, 1fr),
  ([Part of a row], [What it shows]),
  [The number and the title], [The mission's place in the section and its name.],
  [The line under the title], [The base and what the mission trains.],
  [The last result], [#scr("pass") with your best time, #scr("fail"), or #scr("not_flown").],
  [#scr("next_up")], [The mark on the mission to fly next: the one after the mission you flew last. After the section's last mission it is the first one you have not passed. With every mission passed, no row is marked.],
)

The panel beside the list tells more about the mission under the focus or the pointer: its number and title, #scr("learn"), its base, #scr("time_allowed"), #scr("last_result") with its day, and #scr("best_time").

=== Starting a mission <mission-list-fly>

#idx("Mission, starting")
+ On the #scr("missions") screen, select a section.
  #then[The section's list opens. The mission marked #scr("next_up") has the focus.]
+ Select a mission's row, or press #keycap("Enter") on it.
  #then[The mission's briefing opens (@briefing).]
+ Select #scr("fly") on the briefing.
  #then[The mission loads (@loading).]

#scr("back") or #keycap("Esc") goes one screen back: from the list to the #scr("missions") screen, from there to the Hangar.

=== Scramble <mission-list-scramble>

#idx("Scramble")Selecting #scr("sec_fly_now") opens a screen where you set up a quick fight: no mission, no score. Your flight flies from the picked jet's home base, and the screen names that base. The fight is round another base within reach of yours, and the enemy you meet there is drawn at random each time you fly. How well the enemy flies and shoots, and how much of it there is, comes from #scr("enemy_skill") on the Pilot screen (@pilots); the screen names it under the rows.

#screen("free", [The #scr("sec_fly_now") screen.])

#grid-table(
  (auto, 1fr),
  ([Row], [What you pick]),
  [#scr("fc_flight")], [#scr("fc_flight_1"), #scr("fc_flight_2") or #scr("fc_flight_4"). The computer flies your wingmen.],
  [#scr("fc_start")], [#scr("fc_start_air"): your flight starts 60 km (32 nautical miles) from the fight, at 6,000 m, heading for it. #scr("fc_start_runway"): your flight is lined up on your base's runway in pairs, engines running; take off, and your wingmen take off in pairs behind you. #scr("fc_start_ground"): you start up, taxi and take off first (@tower).],
)

Each pick is kept for your next visit. #scr("tab_arming") opens the #term("Loadout") screen for the jet (@loadout). #scr("fly") loads the flight (@loading).

Once you are in the air, the #term("AWACS") gives your task by radio: what to intercept or attack, and where: the bearing and distance from you (@awacs-task). The task is one of these:

- intercept a MiG-29 pair on patrol between the fight's base and yours;
- intercept four one-way attack drones flying over the fight's base towards yours;
- attack a convoy of two T-72 tanks and two trucks on the roads near the fight's base;
- attack the S-300 battery beyond the fight's base.

Other threats may wait there too: more MiG-29 pairs in the air or in that base's shelters, the S-300 network that sends them up, short-range air defence, the drones or the convoy. A higher #scr("enemy_skill") brings more of them. The flight is not scored; end it from the pause menu.

=== The screen without missions <mission-list-nodata>

When the game's data is not built, every section is greyed and a note under the title says so and names a setup command. What to do is in @after-update-no-missions.
