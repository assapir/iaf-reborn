#import "src.typ": *

=== Exterior lights

The EXT LIGHTING panel controls the lights that let others see the jet#fm[figure 1-57, page 1-149]:

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("SW_MASTER_50")], [The master switch of all exterior lights but the landing and taxi lights.],
  [#row("SW_ANTI_COLLISION_50")], [The white anticollision strobe light.],
  [#row("SW_WING-TAIL_50")], [The position lights on the wing tips, the intake and the tail. BRT, OFF, DIM.],
  [#row("SW_FUSELAGE_50")], [The position lights on the fuselage. BRT, OFF, DIM.],
  [#row("SW_POS_LIGHTS_50")], [The position lights steady or flashing.],
  [#row("SW_KNOB_EXT_FORM_LIGHT_50")], [The brightness of the formation lights: strips that a wingman flies on at night (inferred).],
  [#row("SW_KNOB_REFUEL_50")], [The brightness of the light that shows the refuelling door to the tanker.],
)

#row("light-land-switch") has three positions: LANDING, OFF, TAXI#fm[page 1-154].

=== Interior lights

The LIGHTING panel#fm[figure 1-61, page 1-155]:

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("console-primary-knob"), #row("inst-pnl-primary-knob")], [The lighting inside the legends of the consoles and of the instrument panel.],
  [#row("console-flood-knob"), #row("inst-pnl-flood-knob")], [Flood lights over the consoles and the panel.],
  [#row("data-entry-display-knob")], [The brightness of the #term("DED").],
  [#row("mal-ind-lts-switch")], [The warning and caution lights bright or dim.],
)

#in-sim[
  - *Exterior.* Every switch of the panel works. The lights need the generator on line (@electrical) and MASTER on. With WING/TAIL at OFF the FORM knob also lights the wing tips. The refuelling light also needs #row("SW_AIR_REFUEL") at OPEN.
  - *Landing and taxi lights.* They shine with the gear down and the generator on line.
  - *Interior.* The four console and panel knobs work at night; by day they change nothing. The DED knob dims the DED. MAL & IND LTS sets the lights bright or dim; #row("indv-lgt-cont") dims the angle-of-attack indexer, and #row("mms-switch") dims the lights for night-vision goggles.
]
