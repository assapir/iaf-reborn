#import "/modern-iaf/manuals/layout/manual.typ": *
#let jet = book.jet
#let src = [#footnote[The Hellenic Air Force's flight manual for the F-16C/D Block 50/52+, a public copy dated 15 June 2003: #link("https://archive.org/details/haf-f-16"). Each control's function was checked against the manual's section I "Description and Operation" on 18 November 2026; a row whose control section I does not describe says "inferred". The labels and positions are those of the cockpit model, which is derived from the FlightGear F-16.]<cockpit-src>]

This section shows every panel of the #jet.name's cockpit and names everything on it: each control, light, gauge and display.

Figures 1-1 to 1-3 show the cockpit's three sides with each panel's figure number. Each panel then has its own figure, with a number on every item, and a table under it. A number belongs to its item for good: the manual refers to a control by its figure and its number, as in #ctl("MAIN_PWR"), and every such reference is a link to the control's row.

A row gives the item's label as the panel writes it, the words behind its initials, its positions, what it does in the real jet#src, and after *In the sim* what the sim does with it. The last column is its state in the sim:

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

#control-tables()
