#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Debrief")The #term("debrief") opens when a flight ends. It tells you whether the mission passed, shows each goal against what you flew, and lays the whole flight out on a map and three graphs.

#screen("debrief", [The debrief of a passed Take-off #term("lesson").])

=== The sheet <debrief-sheet>

The sheet is the paper-coloured card. Its band gives the sortie's number in your #term("pilot log").

*The head of the sheet:*

#grid-table(
  (auto, 1fr),
  ([Field], [What it shows]),
  [#scr("plane_flown")], [The jet.],
  [#scr("from")], [The base, and the runway of a mission with a take-off.],
  [#scr("f_time")], [The date you flew, and the mission's clock from the start to the end of the flight.],
  [#scr("mission")], [The mission's name.],
  [#scr("result")], [#idx("Result stamp")The stamp: #scr("stamp_pass") or #scr("stamp_fail").],
)

*#scr("goals")* lists what the game checked, one row each: a mark, the goal, the target and the figure you flew.

#grid-table(
  (auto, 1fr),
  ([Mark], [Meaning]),
  [✓], [The goal is met.],
  [!], [You were off the target. The mission still passes. The goal is one to improve.],
  [✗], [The goal failed.],
)

A target written with "max" is an upper limit. A target with ± allows that much either way. The goals of each #term("lesson") are explained with the lesson: @lesson-startup, @lesson-takeoff and @lesson-range.

*#scr("combat")* follows the goals in a flight with combat: that flight's #scr("combat_air_kills"), #scr("combat_ground"), #scr("combat_hits") and #scr("combat_lost"), as on the #scr("pilot") screen (@pilots-combat).

*#scr("remarks")* gives the outcome in a sentence: that the mission passed, or the reason it failed. When several things went wrong, the reason that ended the flight comes first.

*#scr("next_time")* follows with one tip: what to do differently in the next flight. It addresses the reason of a fail, or else the first goal that is not marked ✓. A flight with every goal met has no tip.

#screen("debrief_fail", [The debrief of a failed lesson.])

=== The whole flight on the map <debrief-map>

#idx("Debrief map")The panel #scr("map_flight") draws the path you flew over the briefing's map (@briefing-map).

- *The track* is coloured by the phase of the flight: start-up, taxi, hold, the take-off roll and airborne. The legend under the map gives the colours.
- *#scr("legend_route")* is the mission's planned taxi and route, for comparison.
- *Three pins* mark the start (a disc), the lift-off (a ring) and the end of the flight (a square), each with its time on the mission's clock.
- *The inset* at the corner is a close view of the base: your start and your taxi.

Move the focus to the map to zoom and scroll it as on the briefing: #keycap("+") and #keycap("-"), the arrow keys, the mouse wheel and a drag.

=== The graphs <debrief-graphs>

#idx("Debrief graphs")The panel #scr("graphs") shows the flight against the mission's clock. A band along the top names the phases. Under it are three graphs:

#grid-table(
  (auto, 1fr),
  ([Graph], [What it shows, and the moments marked on it]),
  [#scr("g_speed")], [Your speed. The lift-off is marked with its speed.],
  [#scr("g_agl")], [Your height over the ground under the jet. The moment the gear came up is marked with its height.],
  [#scr("g_load")], [The load on the jet in g. The rotation and the highest load in the air are marked.],
)

A touchdown, a crash, a hit or an ejection shows as a line down all three graphs.

=== The buttons <debrief-buttons>

#grid-table(
  (auto, 1fr),
  ([Button], [What it does]),
  [#scr("next_mission")], [Opens the briefing of the next mission in the list. The last mission of a list shows no such button.],
  [#scr("fly_again")], [#idx("Fly again")Opens the briefing of the mission you just flew, ready to fly.],
  [#scr("back_missions")], [Goes to the #scr("missions") screen (@mission-list).],
  [#scr("pilot_log")], [Opens your pilot log (@pilots).],
  [#scr("combat_more")], [A flight with combat: opens that flight's combat statistics (@pilots-combat).],
  [#scr("export_flight")], [#idx("Export flight data")Saves the flight's recording as a file where you choose: every moment of the flight with its position, speed, height and events, as the game recorded them.],
)

=== Where the debrief is kept <debrief-kept>

Every flight of a mission goes into the pilot log of the pilot who flew it, with its whole debrief. Open a flight in the log to see its debrief again (@pilots).

The map and the graphs come from the flight's recording. When a recording is gone, the sheet still shows, both panels read "#scr-text("no_recording")", and #scr("export_flight") is off.
