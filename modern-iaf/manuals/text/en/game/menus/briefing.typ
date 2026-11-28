#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Briefing")The briefing is the screen between the #scr("missions") screen (@mission-list) and the flight. It opens when you pick a mission. A map of the base fills the screen. The mission card lies over it on one side and the mission's text on the other.

#screen("briefing_2012", [The briefing of a take-off from Ramon in the Sufa.])

=== The mission card <briefing-card>

The card holds, from the top:

- *The title and the line under it.* The mission's name, what it is in one sentence, then the jet, its squadron and its base.
- *The facts.* Four figures of the flight:

#grid-table(
  (auto, 1fr),
  ([Figure], [What it tells you]),
  [#scr("runway")], [The runway end you take off from and its heading, for example 25R and 246°. The heading is the one the jet's compass shows on that runway. A mission that ends before the take-off shows no runway.],
  [#scr("time")], [The time of day at the start, as four digits: 0800 is eight in the morning.],
  [#scr("wind")], [Where the wind comes from, in degrees, and its speed in knots. 000° and 0 kt is calm.],
  [#scr("time_allowed")], [The minutes you have from the start of the flight to reach the objectives.],
)

- *#scr("objectives").* What the game checks, each beside an empty box. The same checks decide the result in the #term("debrief") (@debrief). The last line, #scr("obj_safe"), stands for the things that fail any mission at once.
- *#scr("tab_arming").* The stores on the jet in short, the #scr("takeoff_weight") and #scr("edit"). The weight shows in the warning colour when it is over the jet's maximum. A #term("loadout") the jet cannot use in flight shows its reason here in one line (@loadout-rules).
- *The buttons.* #scr("back"), #scr("tab_arming") and #scr("fly").

#idx("Flights (briefing)")A mission with more than one flight also shows #scr("flights"): one tab for each flight, yours first, marked #scr("your_flight"). Pick a tab to see that flight's jets, task and stores and to bring its route into view on the map.

=== The mission's text <briefing-text>

The text card has two parts:

- *#scr("learn").* Two or three lines: what the #term("lesson") teaches. A mission of another kind shows #scr("purpose") here.
- *#scr("how").* Numbered paragraphs: what to do, in order, from the first call to the #term("tower") to the last objective. The keys in the text are your own keys, as you set them on the #scr("keys_screen") screen (@keys-joystick). The runway, the heading and the #term("time allowed") are the mission's own figures. A Start-up lesson shows a picture of each switch under its paragraph, with a ring round the switch.

Scroll the text with the mouse wheel. With the keyboard, move the focus to the text and use the arrow keys or #keycap("Page Up") and #keycap("Page Down").

#screen("startup_f16i", [The briefing of a start-up.])

=== The map <briefing-map>

#idx("Briefing map")The map shows north up. It opens on the base: your parking spot, the taxi route and the runway.

It draws:

- the ground as a photo, with the main roads and the towns' names;
- the base: its runways with their numbers, its taxiways, aprons and parking spots;
- your taxi route from the parking spot to the runway, as a dashed line;
- your route in the air from the runway through the mission's points, with an arrow, and the runway's heading beside its first leg;
- the other flights' routes, each in its own colour, in a mission that has them;
- a north arrow and a scale bar.

#idx("Pins (briefing map)")*The pins.* A numbered disc stands where a part of #scr("how") happens. The number is the first paragraph you do at that place. A plate beside it names the place:

#grid-table(
  (auto, 1fr),
  ([Pin], [The place]),
  [#scr("pin_start")], [Your parking spot. You start the jet and make the first calls here.],
  [Stop short of the runway], [The #term("holding point"): where you stop and ask the tower for the line-up (@tower).],
  [Take-off and the heading], [Where you line up on the runway and start the take-off roll.],
)

*Moving the map.*

#grid-table(
  (auto, 1fr),
  ([To], [Do this]),
  [Zoom], [Turn the mouse wheel, pinch on a trackpad, or click + and − beside #scr("map_zoom"). With the focus on the map, press #keycap("+") or #keycap("-").],
  [Scroll], [Drag with the left or the middle mouse button, or scroll with two fingers on a trackpad. With the focus on the map, use the arrow keys.],
  [Show the mission's area again], [Double-click the map, or press #keycap("0") with the focus on it.],
)

You can zoom out to the whole country and scroll to any place in it.

*The chips* at the top of the map:

- #idx("Labels (briefing map)")#scr("map_labels") shows or hides the names: the towns, the runway numbers, the base and the pins' plates.
- #idx("Photo (briefing map)")#scr("map_photo") shows the ground as a photo, or as a plain coloured map when off.
- #scr("map_zoom") zooms in and out one step.
- #idx("PRE targets (briefing map)")#scr("pre_title") shows only while the jet carries a GPS-guided bomb. It opens the PRE targets panel (@briefing-pre).

=== PRE targets <briefing-pre>

A GPS-guided bomb (GBU-31, GBU-38, GBU-39, SPICE) in PRE flies to a target planned before the flight. Here you plan it. Select #scr("pre_title") at the top of the map. The panel takes the place of the mission's text and lists the jet's GPS #term("Station", shown: "stations"), each with its bomb and its target. A rack of several bombs (four GBU-39 on the F-35I, two GBU-38 on the F-16) opens into one row for each bomb, the first to leave on top.

+ Click a station's row or a bomb's row. #then[The row reads #scr("pre_click_map").]
+ Click the target on the map: one of the mission's targets (an amber box with its name), one of the route's steerpoints, or any other point of the map. #then[The row shows the target; the map tags the target with the stations and bombs that aim at it.]

A right click on a row, or #keycap("Delete") with the focus on it, clears the row's target. A station with no target of its own takes the mission's target steerpoint (its row shows "· default" after the target). A bomb with no target of its own takes its station's.

The targets are kept with your loadout for the jet, and a loadout you save on the Loadout screen keeps them (@loadout). A target or a steerpoint is kept by its number, so a saved loadout aims at the same numbers on another mission; a point of the map belongs to the mission it was picked on. A row whose store you change on the Loadout screen loses its target.

In the flight each bomb takes its own target. #key("GPS bomb next PRE target") steps the next bomb from its own target through the other planned targets and the steerpoints.

=== Going on <briefing-go>

+ Read #scr("learn") and #scr("how").
+ Find each pin on the map.
+ To change the stores, select #scr("tab_arming") or #scr("edit").
  #then[The Loadout screen opens (@loadout).]
+ Select #scr("fly").
  #then[The loading screen shows (@loading), then the flight starts.]

#note[#scr("fly") is off while the loadout cannot be flown: the take-off weight is over the maximum, or a store needs a pod that is not on the jet. The #scr("tab_arming") part of the card shows why. Change the loadout (@loadout-rules), and #scr("fly") comes on again.]

#scr("back") or #keycap("Esc") goes to the mission list. #keycap("Tab") moves the focus through the buttons, the chips, the map and the text.
