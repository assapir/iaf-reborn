#import "/modern-iaf/manuals/layout/manual.typ": *

*Who it is for.* This manual is for the pilot who flies Modern IAF. It needs no earlier knowledge of the jet.

*What it describes.* #book.scope #if is-jet [Everything around the jet is in the #other-manual("game"). ]A chapter that the outline lists as planned is written once the outline is approved.

*Real jet and sim.* The manual follows the order of a real flight manual and describes the real jet from public sources, in our own words. Each source is a footnote. Where the sim does less than the real jet, the text says *not modelled*:

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 0pt, y: 4pt),
  column-gutter: 10pt,
  sim-chip("full"), [The sim does what the section describes.],
  sim-chip("part"), [The sim does part of it. The section names what is missing.],
  sim-chip("none"), [The real jet's content, for reference. The sim does not do it.],
)

*Steps.* A procedure is a numbered table. Each step names the control, then its position: *MAIN PWR – BATT*. Do the steps in order. A step marked ○ is one the sim does not check, in most cases because its system is not modelled: read it and go on. The Key column shows the key that does the same as a click on the control. The control you act on is in bold at the start of the step. What the jet does in answer, a light, a needle, a message on a display, follows on its own line in bold after an arrow (#text(fill: accent, weight: 700, sym.arrow.r)), with the name as the panel or display writes it.

*Keys.* A key is shown as #keycap("G"). Where macOS uses another key, one cap shows both: the key on top and the macOS key under it, smaller, as in #key("Avionics power"). On a Mac the sim reads Cmd as Ctrl, names Alt Option, and starts from its laptop key map.

*Pictures.* Every cockpit picture is taken from the sim. In a procedure, a picture stands just before the steps it serves, and the number on an arrow is the number of the step that uses that control.#if is-jet [ In chapter 1 every item of a panel has a number of its own, and the table under the picture describes each.]

#if is-jet [*Controls.* A control's name is followed by its figure in chapter 1 and its number there: *#systems.panels.first().controls.first().label* #ctl-ref(systems.panels.first().controls.first().node) is a control of the first panel's figure. The reference is a link to the control's description.]

*Safety words.* The manual uses three:

#warning[An action that loses the jet or ends the flight in the sim.]
#caution[An action that damages a system or costs time in the sim.]
#note[Something that helps.]

These describe the sim. They are not instructions for a real aircraft.

*Finding things.* The contents, every cross-reference and every index entry are links. The bookmarks pane of the PDF viewer shows the same contents. A link to another manual opens that PDF when the manuals are kept in one folder.
