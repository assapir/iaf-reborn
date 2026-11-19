#import "src.typ": *

#layout-head

The #term("HUD") shows the flight data and the aiming symbols over the view ahead#d34[section I, "Head-up display (HUD)", page 1-156]. Its symbols follow the master mode (@stores).

#display("hud_modes", [The HUD with the #term("DED")'s lines repeated on it. Top: navigation, air-to-air. Bottom: air-to-ground with the bomb's impact point, dogfight.], width: 100%)

=== What every mode shows

The airspeed scale on the left, the altitude scale on the right, the heading scale, the pitch ladder, the flight path marker (where the jet is going), the gun cross (where the nose points), the g, and the master arm's state: ARM, or SIM with #row("master-arm-switch") at SIMULATE. The lower right column holds the slant range, the low-altitude warning height (AL), the time and distance to the steerpoint. *FUEL* flashes below the #term("Bingo fuel"). *ALIGN* shows while the #term("INS") aligns and flashes when it is ready.

#table(columns: (auto, 1fr), table.header[*Mode*][*Added symbols*],
  [Navigation], [The steerpoint's diamond and the steering cue. With the gear down: the ILS's two needles.],
  [Air-to-air, a missile selected], [The missile's circle. With a radar lock: a box on the target, a range scale on the right with the target's caret, and the closing speed. Without a lock in a dogfight pattern: the pattern's line or cross (@radar-aa).],
  [Air-to-air, the gun], [The funnel of the gun's sight; with a lock, the aiming dot (@aa-weapons).],
  [Air-to-ground, a bomb], [The impact point (a dot in a circle) at the end of the bomb fall line (@ag-weapons).],
  [Air-to-ground, a guided bomb], [The target's box, a steering line and a range scale (@ag-weapons).],
  [Air-to-ground, the gun], [The strafing dot with the slant range.],
)

=== Ground-avoidance cues

A large *X* flashes when the radar altitude and the dive call for an immediate pull-up, and the voice says "Pull up". The cue needs #row("RDR_ALT") on. Below the height set on the DED's ALOW page *AL* flashes and the voice says "Altitude".

=== The HUD control panel

#table(columns: (27%, 1fr, 22%), table.header[*Switch*][*Positions*][*Key*],
  [#row("w_vah-switch")], [VV/VAH adds the vertical velocity scale beside the altitude scale. VAH: the speed, altitude and heading scales. OFF: the read-outs alone.], [#key("HUD SCALES (VV/VAH / VAH / OFF)")],
  [#row("att_fpm-switch")], [ATT/FPM: the ladder and the flight path marker. FPM: the marker alone. OFF: neither.], [#key("HUD FP MARKER (ATT/FPM / FPM / OFF)")],
  [#row("tas-switch")], [Calibrated airspeed (C), true airspeed (T) or ground speed (G). With the gear down or in dogfight the scale is calibrated airspeed.], [#key("HUD VELOCITY (CAS / TAS / GND SPD)")],
  [#row("altrad-switch")], [RADAR: the radar altitude on the scale. BARO. AUTO: the radar altitude's own scale below 1,200 ft.], [#key("HUD ALT (RADAR / BARO / AUTO)")],
  [#row("deddata-switch")], [Repeats the DED's five lines, or the fault list's, low in the HUD.], [#key("HUD DED DATA (DED / PFL / OFF)")],
  [#row("depr-ret-switch")], [STBY shows the standby reticle, a ring with its dot; PRI the manual bombing mode's reticle. #row("depr_ret") lowers either.], [#key("HUD DEPR RET (STBY / PRI / OFF)")],
  [#row("SYM")], [The symbols' brightness.], [#key("Step HUD brightness")],
)

=== The helmet display

The helmet sight puts an aiming cross on the visor. Look at a target to point a short-range missile's seeker at it; a diamond shows where the seeker tracks. #row("HMCS_SYM_INT_KNOB") dims it to off. That the real helmet's symbols look the same is inferred: no figure of them is public.

#display("helmet", [The helmet looking 54° left at a locked target, a short-range missile selected: the aiming cross, the radar's box and the seeker's diamond on the target, the circle whose gap shows where the head looks from the nose, the head's heading above, the g and speed at the left, the altitude and steerpoint at the right.], width: 90%)

#in-sim[
  - #row("test-step-switch") moves only: the HUD's four test patterns#d34[page 1-158] are not drawn.
  - #row("drift") at DRIFT C/O (#key("DRIFT C/O (DRIFT C/O / NORM)")) #then[centres the flight path marker and the ladder.] At WARN RESET (#key("WARN RESET")) #then[the flashing FUEL cue and the repeating "Altitude" call stop.]
  - #row("cont") (#key("HUD CONT (contrast): next step")) is partly modelled: #then[the symbols' edges wash out as it turns down.] The HUD draws no infrared picture for it to set.
  - The release modes' cues (TD box, steering line, solution and pull-up cues, the manual reticle, LOW) are described with the modes (@ag-weapons).
]
