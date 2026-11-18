#import "src.typ": *

The jet tells the pilot of a fault in three ways: a red warning light, an amber caution light, and a voice.

=== Warning lights

The warning lights are red and stand on the glareshield, at eye level#fm[page 1-140 and figure 1-55, pages 1-142 to 1-144]. A warning is a fault that needs action now.

#table(
  columns: (auto, 1fr),
  stroke: none,
  inset: (x: 6pt, y: 3.5pt),
  fill: (_, y) => if calc.even(y) { paper },
  [#row("lamp_eng_fire_0")], [Fire in the engine bay (@engine).],
  [#row("lamp_engine_0")], [The engine has flamed out or runs too hot (@engine).],
  [#row("lamp_hyd_oil_press_0")], [Low hydraulic or oil pressure (@hydraulic).],
  [#row("lamp_flcs_0")], [A fault of the #term("FLCS") (@flight-controls).],
  [#row("lamp_dbu_on_0")], [The flight controls are on their backup software.],
  [#row("lamp_to_ldg_config_0")], [The gear is not down on an approach, or the jet is not set for take-off (@gear).],
  [#row("lamp_canopy_0")], [The canopy is not locked (@canopy-seat).],
  [#row("lamp_tf_fail_0")], [A fault of terrain following (inferred from its name).],
)

=== Caution lights

A caution is a fault that needs attention soon. Each has an amber light on the #link(label("panel-caution"))[caution light panel]. Any caution also lights #row("master_reset"), so that the pilot looks down at the panel. Pressing the face of the MASTER CAUTION light puts it out and makes it ready for the next caution; the caution's own light stays on while the fault lasts#fm[page 1-146].

=== The voice

A recorded voice speaks a word or two for the faults and events that matter most#fm[pages 1-145 and 1-146]: "Pull up", "Altitude", "Warning" (a warning light has been on for 1.5 seconds), "Caution" (a caution light has been on for 7 seconds without the MASTER CAUTION being reset), "Bingo", "Jammer", "Counter", "Chaff flare", "Low", "Out", "Lock" and "Data". #row("voice-msg-switch") at INHIBIT silences it.

=== Testing the lights

#row("MAL_IND_LTS") lights every warning, caution and indicator light while it is held#fm[page 1-147]. A light that stays dark has failed.

#in-sim[
  - *MASTER CAUTION* lights with any battle damage and with a new caution; a click on it resets it. The ELEC SYS caution is acknowledged with #row("CAUTION_RESET") instead.
  - *Warning lights.* All but TF FAIL can light: ENG FIRE with a fire; ENGINE with engine damage or a stopped engine; HYD/OIL PRESS, FLCS, DBU ON, TO/LDG CONFIG and CANOPY as their sections say.
  - *Caution lights that can light:* ENGINE FAULT, AVIONICS FAULT, FLCS FAULT, ADC and CADC (battle damage), ELEC SYS, EQUIP HOT, PROBE HEAT (it flashes with #row("SW_PROBE_HEAT") at TEST), HOOK, OVERHEAT, CABIN PRESS, FWD FUEL LOW, AFT FUEL LOW, LE FLAPS and ECM. Every other caution light comes on in the lamp test only: its system is #term("not modelled").
  - *The voice* says "Pull up" and "Altitude" (@hud), "Caution" after battle damage, "Warning" for a fire or engine damage, "Bingo" (@fuel), and the countermeasures' "Chaff flare", "Counter", "Low" and "Out" (@ew). "Jammer", "Lock" and "Data" are not spoken, and VOICE MESSAGE moves and does nothing.
  - *The lamp test* works with electrical power on.
]
