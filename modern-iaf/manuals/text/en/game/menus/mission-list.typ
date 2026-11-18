#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Missions screen")The #scr("missions") screen opens from the #term("Hangar")'s #scr("fly"). It holds the picked jet's missions, in sections.

#screen("missions", [The #scr("missions") screen: a card for each section.])

=== The sections <mission-list-sections>

Each section is a card with its number, its title and, at its foot, your progress in it: how many of its missions you passed, and a bar.

#grid-table(
  (auto, 1fr),
  ([Section], [What it holds]),
  [#scr("sec_training")#idx("Training")], [Each jet's three lessons from its home base: #scr("kind_startup"), #scr("kind_takeoff") and the weapons range (@lessons).],
  [#scr("sec_campaign")#idx("Campaign")], [Not in the sim yet. The card is greyed and marked #scr("coming_later").],
  [#scr("sec_single")#idx("Single missions")], [Not in the sim yet. The card is greyed and marked #scr("coming_later").],
  [#scr("sec_fly_now")#idx("Fly now")], [Not in the sim yet. The card is greyed and marked #scr("coming_later").],
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

=== The screen without missions <mission-list-nodata>

When the game's data is not built, every section is greyed and a note under the title says so and names the setup command. What to do is in @after-update-no-missions.
