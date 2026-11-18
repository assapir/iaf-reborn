#import "/modern-iaf/manuals/layout/manual.typ": *
#let jet = book.jet
#let src = [#footnote[Mark Ayton, "Blue Sky OPS", AIR International, 26 April 2012, quoted on F-16.net, "Engine start up procedure": "just three switch selections, one each for the battery, integrated power pack and the engine" (checked 18 November 2026), #link("https://www.f-16.net/forum/viewtopic.php?p=317934").]<cockpit-src>]

This section shows every panel of the #jet.name's cockpit and names everything on it: each control, light, gauge and display.

Figures 1-1 to 1-3 show the cockpit's three sides with each panel's figure number. Each panel then has its own figure, with a number on every item, and a table under it. A number belongs to its item for good: the manual refers to a control by its figure and its number, as in #ctl("BATT"), and every such reference is a link to the control's row.

A row gives the item's label as the panel writes it, the words behind its initials, its positions, what it does, and after *In the sim* what the sim does with it. The last column is its state in the sim:

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 0pt, y: 4pt),
  column-gutter: 10pt,
  chip(ui.statuses.works, colour: green, filled: true), [The item does its real job.],
  chip(ui.statuses.partly, colour: amber), [Only a part works: a light or a caution, or one of the positions.],
  chip(ui.statuses.moves, colour: muted), [The control moves and keeps its position; nothing else happens.],
  chip(ui.statuses.at("none"), colour: muted), [A light, gauge or display that the sim does not drive. A light comes on in the lamp test only.],
)

An item marked #term("not modelled") has no system behind it in the sim.

Little of the real cockpit is public: the three start switches follow the one public description of the start#src. Every other item's place, label and function is inferred.

#control-tables()
