#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Missions screen")The #scr("missions") screen opens from the #term("Hangar")'s #scr("fly"). It holds the picked jet's training course and its missions, in sections.

#screen("missions", [The #scr("missions") screen: a card for each section.])

=== The sections <mission-list-sections>

Each section is a card with its number, its title and, at its foot, your progress in it: how many of its lessons or missions you passed, and a bar.

#grid-table(
  (auto, 1fr),
  ([Section], [What it holds]),
  [#scr("sec_training")#idx("Training")], [The picked jet's training course: its eight phases and their lessons (@mission-list-training). The card counts the course's lessons you passed.],
  [#scr("sec_campaign")#idx("Campaign")], [Comes in a later version. The card is greyed and marked #scr("coming_later").],
  [#scr("sec_single")#idx("Single missions")], [Comes in a later version. The card is greyed and marked #scr("coming_later").],
  [#scr("sec_fly_now")#idx("Scramble")], [A quick fight against an enemy drawn at random, with the task given by the #term("AWACS") (@mission-list-scramble). The card shows no progress.],
)

A greyed card takes no click and no focus.

=== Training: the phases <mission-list-training>

#idx("Training")#idx("Phases")Selecting #scr("sec_training") opens the picked jet's training course: 47 lessons in eight phases, flown in order. The title line shows how many of the course's lessons you passed, for example #strong(scr-text("passed_of").replace("%d", "5", count: 1).replace("%d", "47", count: 1)).

The eight phases stand as cards in two rows of four. Each card shows the phase's number, its title and, at its foot, how many of the phase's lessons you passed, with a bar. A #term("lesson") counts as passed with #scr("pass") or #scr("grade_marginal"). Each jet keeps its own count.

Select a card, or press #keycap("Enter") on it, to open the phase's lessons.

=== A phase's lessons <mission-list-lessons>

#idx("Lessons")The list's title is the phase's number and title, for example #strong(scr-text("phase_n").replace("%d", "2")), with how many of its lessons you passed. Each row is one lesson: the day lessons, then the night lesson, then the check ride.

#grid-table(
  (auto, 1fr),
  ([Part of a row], [What it shows]),
  [The number], [The phase and the lesson: 2.1 is the first lesson of phase 2.],
  [The title and the line under it], [The lesson's name and what it trains.],
  [The grade], [Your best grade in the lesson: #scr("pass"), #scr("grade_marginal") or #scr("grade_unsat"); #scr("not_flown") before your first flight of it.],
)

The panel beside the list tells more about the lesson under the focus or the pointer: its number (#strong(scr-text("lesson_n").replace("%d.%d", "2.1"))), its title, #scr("learn") and #scr("last_result") with its day.

Select a lesson, or press #keycap("Enter") on it, to open its briefing (@briefing-lesson). A lesson of a phase that has no flights yet opens nothing; its panel says #scr("coming_later").

#scr("back") or #keycap("Esc") goes one screen back: from the lessons to the phases, from the phases to the #scr("missions") screen, from there to the Hangar.

=== Scramble <mission-list-scramble>

#idx("Scramble")Selecting #scr("sec_fly_now") opens a screen where you set up a quick fight: no mission, no score. Your flight flies from the picked jet's home base, and the screen names that base. The fight is round another base within reach of yours, and the enemy you meet there is drawn at random each time you fly. How well the enemy flies and shoots, and how much of it there is, comes from #scr("enemy_skill") on the Pilot screen (@pilots); the screen names it under the rows.

#screen("free", [The #scr("sec_fly_now") screen.])

#grid-table(
  (auto, 1fr),
  ([Row], [What you pick]),
  [#scr("fc_flight")], [#scr("fc_flight_1"), #scr("fc_flight_2") or #scr("fc_flight_4"). The computer flies your wingmen.],
  [#scr("fc_start")], [#scr("fc_start_air"): your flight starts 60 km (32 nautical miles) from the fight, at 6,000 m, heading for it. #scr("fc_start_runway"): your flight is lined up on your base's runway in pairs, engines running; take off, and your wingmen take off in pairs behind you. #scr("fc_start_ground"): you start up, taxi and take off first (@tower).],
  [#scr("fc_when")], [First the date, then the time. The date: the day the flight flies, this year. The arrows beside the day step a day, the arrows beside the month a month. The date sets when the sun rises and sets: 0630 is still dark on 21 December and full day on 21 June. It also sets the moon: its phase and where it stands. A night under a full moon is dim grey; a night without a moon is nearly black, with only the lights on the ground and the stars. The weather and the air's temperature stay the same all year. #scr("fc_random") (lit when the screen opens): the day is drawn when you fly, any day of the year; your #term("notebook")'s #scr("nb_data") page shows it. The time: the time of day the flight starts, Israel time, as four 24-hour digits: 0630 is 6:30 in the morning, 2200 is 10 at night. The arrows beside the hours step an hour, the arrows beside the minutes five minutes; the clock goes round past midnight. The sun, the sky and the lights follow the time: at night you fly by your instruments and the night sky. #scr("fc_random") (lit when the screen opens): the time is drawn when you fly, any hour of the day; your notebook's #scr("nb_data") page shows it (@notebook-tabs).],
)

#scr("fc_flight") and #scr("fc_start") are kept for your next visit; the date and the time start again at #scr("fc_random") each time you open the screen (with today and 0800 under it). #scr("tab_arming") opens the #term("Loadout") screen for the jet (@loadout). #scr("fly") loads the flight (@loading).

Once you are in the air, the #term("AWACS") gives your task by radio: what to intercept or attack, and where: the bearing and distance from you (@awacs-task). The task is one of these:

- intercept a MiG-29 pair on patrol between the fight's base and yours;
- intercept four one-way attack drones flying over the fight's base towards yours;
- attack a convoy of two T-72 tanks and two trucks on the roads near the fight's base;
- attack the S-300 battery beyond the fight's base. As a real battery, it has a Tor-M1 short-range missile system beside it, against jets that come in low.

Other threats may wait there too: more MiG-29 pairs in the air or in that base's shelters, the S-300 network that sends them up, short-range air defence, the drones or the convoy. A higher #scr("enemy_skill") brings more of them. Half the flights also have a #term("tanker") on a track between your base and the fight; ask it for fuel on the radio (@tanker). The flight is not scored; end it from the pause menu.

The enemy fights as real crews do. Close in, its fighters dogfight: they turn for your tail, slow down beside you so that you fly past them, run off to gain speed and come back, and fire their heat-seeking missile at a jet their pilot can see, with no radar needed. The S-300 network shares what its radars and its fighters see: a battery with its own radars off can lock and fire on that picture, so your radar warning receiver may hear no search before the lock. At a higher #scr("enemy_skill") the fighters fly more of these moves, the batteries turn their search radar on only in short bursts, and they move to a new place sooner after they fire.

=== The screen without missions <mission-list-nodata>

When the game's data is not built, every section is greyed and a note under the title says so and names a setup command. What to do is in @after-update-no-missions.
