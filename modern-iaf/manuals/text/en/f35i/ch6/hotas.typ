#import "src.typ": *

The pilot flies and fights with both hands on the controls: the switches for the sensors and the weapons are on the grips of #row("side_stick") and #row("throttle"). The list below is the sim's. The real grips' switch list is open.

- On the stick: the weapon release button, the trigger, the trim switch, the target management switch (TMS), the display management switch (DMS), the countermeasures management switch (CMS), a switch that marks a point, a switch that zooms a sensor, the paddle that disconnects the autopilot, and the nose wheel steering button.
- On the throttle: the cursor control, which moves the display's cursor and selects when pushed; the master mode switch; the switch that cages or uncages a seeker; and the FLC, "Format Layer Control"#footnote[United States Air Force Test Center, solicitation "F-35 HOTAS Throttle and Side Stick", 25 July 2019, its list of the grips' switches, #link("https://sam.gov/opp/6481842093ca4c35c0461b221c26cb0b/view").]. Only its name is public.

What each switch does in each format of the display is not public: open.

#in-sim[The grips move with the flight controls, and their switches do not move. Each function has a key. The keyboard is the first input; a joystick button can be given to any key (#other("game", "keys-joystick")).]

=== The keys of the grips' functions <hotas-keys>

#table(
  columns: (1.1fr, 1.5fr, 1.6fr),
  stroke: none,
  inset: (x: 6pt, y: 5pt),
  fill: (_, y) => if y == 0 { navy } else if calc.even(y) { paper },
  table.header(..([Function], [Key], [What it does in the sim]).map(t => text(fill: white, weight: 600, size: 8.5pt, t))),
  [Weapon release], [#key("Release selected weapon")], [Releases the selected missile or bomb (@stores).],
  [Trigger], [#key("Gun trigger")], [Fires the gun.],
  [TMS up], [#key("Radar: bug / lock (TMS up)")], [Marks the target under the radar's cursor, then locks it. On the ground map: tracks or designates.],
  [TMS down], [#key("Radar: drop bug / lock (TMS down)")], [Drops the lock, the marks or the designation.],
  [TMS right], [#key("Radar: next submode, ACM 10 x 60 (TMS right)")], [Steps the search submode; in ACM selects the tall pattern (@radar-aa).],
  [TMS left], [#key("Radar: ACM slew (TMS left)")], [In ACM selects the pattern that follows the cursor.],
  [Cursor], [#key("Slew EO sensor / radar cursor up") #key("Slew EO sensor / radar cursor down") #key("Slew EO sensor / radar cursor left") #key("Slew EO sensor / radar cursor right")], [Moves the radar's cursor. While the TFLIR's picture runs, moves its line of sight (@tflir).],
  [Master mode], [#key("Cycle master mode")], [Steps navigation, air-to-air and air-to-surface.],
  [Weapon choice], [#key("Next air-to-air weapon") #key("Next air-to-ground weapon")], [Selects the next weapon of that kind and its master mode.],
  [Expand], [#key("Radar expand (EXP)")], [Enlarges the radar's picture.],
  [Cage / uncage], [#key("Missile seeker: UNCAGE / CAGE")], [Uncages the AIM-9X's seeker so that it follows the target it hears; a second press cages it (@aa-short).],
  [CMS], [#key("CMS forward: run the CMDS program") #key("CMS aft: stop dispensing") #key("CMS right: consent (SEMI) / enable AUTO")], [Works the countermeasures dispenser (@ew).],
  [Trim], [#key("Roll trim left") #key("Roll trim right")], [Trims the roll.],
  [Autopilot], [#key("Autopilot: level / nav / off")], [Steps the autopilot; the last press disconnects it.],
  [FLC turned], [#key("FLC: previous format in the cursor's portal") #key("FLC: next format in the cursor's portal")], [Steps the format of the portal with the cursor through the MENU grid's formats (@pcd). Inferred from the switch's name.],
  [FLC pushed], [#key("FLC push: the TSD's next layers")], [On a TSD, steps its layers: all; without the map and the route (LYR 1); the tracks only (LYR 2). On another format a notice says it has no layers. Inferred from the switch's name.],
)

=== What the sim does differently <hotas-differences>

- *The DMS.* On the real jet it manages the display (inferred from its name). In the sim its keys move the display's cursor between the portals and give the sensor of interest to the helmet and back (@pcd); a format is chosen with the pointer or the display's keys.
- *The pointer.* A click on the display works its legends and tabs. The pointer does not move the radar's cursor.
- *The mark point switch.* #term("Not modelled").
