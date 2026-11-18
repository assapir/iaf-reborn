#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Notebook")#idx("Kneeboard")Every flight carries the pilot's #term("notebook"): a paper kneeboard on the right thigh. It holds the jet's checklist, the radio calls, the mission's data and short pages for the landing, the weapons and emergencies.

#screen("notebook_raised", [The notebook raised at its CHECKLIST tab.])

=== Opening and stowing it <notebook-open>

+ Press #key("Checklist notebook").
  #then[The notebook rises to the lower corner of the screen. The flight goes on.]
+ Press #key("Checklist notebook") again.
  #then[The notebook goes back to the thigh.]

A Start-up #term("lesson") starts with the notebook raised at its #scr("nb_startup") tab. Every other flight starts with it stowed. In your first Start-up lesson a help line stands over the raised notebook with the keys of this section.

=== The tabs <notebook-tabs>

#grid-table(
  (auto, 1fr),
  ([Tab], [Its pages]),
  [#scr("nb_startup")], [The jet's own checklist card, section by section, ticked as you work (@notebook-checklist).],
  [#scr("nb_taxi")], [The radio calls, the taxi and the take-off as numbered steps, and the runway: its number, heading, length and elevation.],
  [#scr("nb_radio")], [Your callsign, the base's frequencies, and each call with the frequency to make it on and the #term("tower")'s answer (@tower-radio).],
  [#scr("nb_landing")], [The landing in five lines: the call, the gear, the final approach, the touchdown, the engine off on the parking spot.],
  [#scr("nb_weapons")], [Arming, air-to-ground and air-to-air as short steps, each with its switch, the switch's place and its key.],
  [#scr("nb_emergency")], [A red tab: an engine fire on the ground and the ejection; in the Sufa and the Barak also the #term("hot start").],
  [#scr("nb_data")], [The mission, the base and its code, the time, the wind, the jet, the runway and the route's first point.],
)

The pages name each switch and its place in the cockpit. Only the #scr("nb_weapons") tab names keys. Every key is on the #scr("keys_screen") screen (@keys-joystick).

=== Turning the pages <notebook-pages>

#idx("Notebook, paging")A tab's text is cut into pages. Turn them in any of these ways:

- Click a tab: its first page opens.
- Click ‹ or › at the foot of the page. The count between them, for example 1 / 2, is the page within the tab.
- Turn the mouse wheel over the notebook.
- Press #key("Checklist notebook: previous page") or #key("Checklist notebook: next page") while the notebook is raised.

Past a tab's last page the next tab's first page opens.

=== The CHECKLIST tab <notebook-checklist>

#idx("Checklist")The #scr("nb_startup") tab shows the jet's checklist card: the same card in every mission. The procedures themselves are in each jet's manual: the cold start in the #other("f16i", "cold-start"), the #other("f16d", "cold-start") and the #other("f35i", "cold-start"); the whole card with the other normal procedures in the #other("f16i", "normal"), the #other("f16d", "normal") and the #other("f35i", "normal").

Each item of the card shows its line, how to do it (the clicks, the waits), and its switch with the switch's place. The notebook follows the cockpit:

#grid-table(
  (auto, 1fr),
  ([Mark], [Meaning]),
  [A tick], [The item is done: its switch stands where the card wants it. Put the switch back, and the tick goes.],
  [A yellow band with an arrow], [#idx("Yellow band")The item to do now. The page turns by itself to keep it in view.],
  [A small ring (○)], [#idx("Read and acknowledge")An item you read and acknowledge. Its line reads: #scr-text("nb_ack"). The game ticks nothing for it and never makes it the item to do now.],
  [A red line under an item], [The jet refused the step, and why. In a lesson such a fault fails the mission (@scoring-order).],
)

An item done ahead of its turn is ticked. The yellow band stays on the earlier item until you do it.

=== The hint line <notebook-hints>

#idx("Hint line")Under the item on the yellow band the notebook says, in one blue line, what the item still lacks. The line changes as you work. Examples:

- #scr-text("nb_hint_batt")
- #scr-text("nb_hint_throttle_off")
- #scr-text("nb_hint_ins_off")
- #scr-text("nb_hint_ins_nav")
- #scr-text("nb_hint_selftest")

Other hint lines count for you: the engine's #term("RPM") so far while the starter turns it, the switches of a group that are still off, the seconds left of the #term("INS") alignment.

=== The ring round the control <notebook-ring>

#idx("Ring round a control")In a Training lesson the game also shows you where the item's control is. It draws a sky-blue outline round the switch of the item on the yellow band, in the cockpit itself.

#screen("notebook_training", [A lesson: the ring in the cockpit and the notebook beside it.])

- The ring carries the same words as the hint line.
- For an item that waits on a gauge, the ring goes round the gauge too, with the value to watch for.
- When the control is out of view, an arrow at the edge of the screen points toward it, with the item's line. Turn the head that way (@views-cockpit).
- When the raised notebook would cover the ring, the notebook slides aside.
- When the pilot's body covers the ringed switch, the body hides (@views-body).

Click the ringed switch (@clicking-rule), or press the item's key.
