#import "src.typ": *

The #term("HUD") is the main flight instrument: it shows airspeed, altitude, heading, attitude and the flight path over the view ahead (@hud). The instruments on the panel below it show the same without the HUD and without the #term("MMC")#fm[figure 1-87, page 1-215, the instrument panel].

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("anim096")], [The attitude director indicator: a ball that shows pitch and bank, with the #row("ADI_glide-slope-index") of the instrument landing system and, under it, the #row("anim095").],
  [#row("EHSI_screen")], [The electronic horizontal situation indicator: a compass card with the course and the bearing and distance to the steerpoint or the TACAN station. #row("HSI_hdg-knob") and #row("HSI_course-knob") set its heading and course marks, #row("EHSI_button") its mode (@navigation).],
  [#row("anim089")], [Airspeed on a dial, Mach number in a window; #row("ASI_bug-left") moves a reference mark.],
  [#row("anim202")], [The altimeter: barometric altitude, with its pressure setting.],
  [#row("anim099")], [The vertical velocity indicator: climb or descent in feet a minute.],
  [#row("AOA_tape")], [Angle of attack on a moving tape.],
  [#row("anim165")], [The standby attitude indicator: self-contained and electrically powered#fm[page 1-216].],
  [#row("anim170")], [A magnetic compass.],
  [#row("anim105")], [A clock with a stopwatch (#row("chronometer-button")).],
)

=== Angle of attack on the approach

The #jet.short is flown down the approach at a fixed angle of attack, about 13°, whatever its weight#fm[page 1-138]: this is "on speed". The three lights of the angle-of-attack indexer show it without a look inside: #row("lamp_aoa_slow_0") means too slow (the angle is too high), #row("lamp_aoa_on_speed_0") on speed, #row("lamp_aoa_fast_0") too fast.

#in-sim[
  - Every instrument of the table is driven; the stopwatch button moves and does nothing.
  - The airspeed dial shows true airspeed; the HUD shows the airspeed that #row("tas-switch") selects.
  - The angle-of-attack tape reads zero below 60 knots.
  - The indexer: the top light above 14°, the middle one from 12° to 14°, the bottom one below 12°.
  - The EHSI is a display: it needs the generator on line (@electrical).
]
