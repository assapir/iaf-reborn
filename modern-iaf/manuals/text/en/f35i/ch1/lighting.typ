#import "src.typ": *

The lighting of the real jet is not public; this section describes the cockpit's controls, and what they do is inferred from their names.

=== Exterior lights

#row("LAND_TAXI") has three positions: LAND, TAXI and OFF.

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
  - *Exterior.* The exterior lights are always on; no switch controls them.
  - *Displays.* MFD BRT and HMD BRT change the brightness in steps of 2.5~%. #sym.arrow.r *HMD at OFF removes the helmet's symbols.*
  - *#term("Not modelled").* LAND/TAXI LIGHTS, DAY / NIGHT, VIDEO BRT and VIDEO CONT move and do nothing; NIGHT, AUTO and DAY of the HMD knob act alike.
]
