#import "src.typ": *

The lighting of the real jet is not public; this section describes the cockpit's controls, and what they do is inferred from their names.

=== Exterior lights

#row("LAND_TAXI") has three positions: LAND, TAXI and OFF. The lamp sits on the nose gear's strut and faces ahead. The throttle's Lights Master button turns the other exterior lights on and off; their modes are set on the #term("PCD").

=== Displays

The cockpit has few lit panels: most of what the pilot reads is on the #term("PCD") and in the helmet.

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("MFD_BRT")], [The brightness of the PCD.],
  [#row("MFD_MODE")], [The PCD's colours for day or for night.],
  [#row("HMD_BRT")], [The brightness of the helmet's symbols.],
  [#row("HMD_MODE")], [The #term("HMD")'s mode: OFF, NIGHT, AUTO, DAY.],
  [#row("VIDEO_BRT"), #row("VIDEO_CONT")], [The brightness and contrast of sensor video in the helmet.],
)

#in-sim[
  - *Exterior.* #key("Lights Master: navigation lights and strobe on / off (F-35I)") (the throttle's Lights Master) #sym.arrow.r *turns the navigation lights and the strobe on or off*, with the generator on line; they start off. #row("LAND_TAXI") at TAXI or LAND #sym.arrow.r *the taxi light or the landing light lights the ground ahead*, at night, with the gear down and the generator on line.
  - *Displays.* MFD BRT and HMD BRT change the brightness in steps of 2.5~%. #sym.arrow.r *HMD at OFF removes the helmet's symbols.* Each push of VIDEO BRT or VIDEO CONT #sym.arrow.r *steps the brightness or the contrast of the helmet's picture* (the night camera's and the DAS video), five steps each way (@hmd).
  - *#term("Not modelled").* DAY / NIGHT moves and does nothing; NIGHT, AUTO and DAY of the HMD knob act alike. The exterior lights' modes on the PCD are not modelled.
]
