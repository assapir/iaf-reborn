#import "src.typ": *

The #jet.short is flown through a computer. The #term("FLCS") is a digital fly-by-wire system with four channels: the stick, the pedals and the trim send electrical signals to it, and it moves the control surfaces#fm[page 1-120]. The #row("anim000") senses the force of the hand and moves only about a quarter of an inch#fm[page 1-127]. The jet cannot be flown without the computer; its four channels and its several sources of power (@electrical) are there for that (inferred).

=== The limiters

The computer limits what the pilot can ask for, so that full stick does not break the jet or throw it out of control#fm[page 1-121]:

- *Load factor.* Up to +9 g, and less as the angle of attack rises above 15°; down to −3 g.
- *Angle of attack, CAT I.* About 25°.
- *Angle of attack, #term("CAT III").* About 16° to 18°, with slower roll, for a jet with heavy or large stores (the reason, an earlier loss of control with such stores, is inferred).

#row("SW_STORES_CONFIG") chooses CAT I or CAT III#fm[page 1-130]. The #row("lamp_caution_stores_config_0") caution light means that the switch does not match the stores the jet carries (inferred from its name).

=== Flaps

- *Leading-edge flaps* move by themselves, as the computer schedules them. #row("SW_LE_FLAPS_50") at LOCK holds them where they are#fm[page 1-134].
- *Trailing-edge flaps.* The flaperons, which also roll the jet, droop 20° as flaps while the gear handle is down, and come up again as the speed rises above 240 knots. #row("SW_ALT_FLAPS_50") at EXTEND lowers them with the handle up#fm[page 1-120].

=== Speedbrakes

Two pairs of surfaces beside the engine nozzle open to 60°. With the right main gear down they stop at 43°, which keeps them clear of the runway at touchdown#fm[page 1-117]. The SPD BRK switch is on the throttle.

=== Trim

A button on the stick trims pitch and roll, and the MANUAL TRIM panel trims pitch, roll and yaw. The TRIM/AP DISC switch at DISC disconnects the stick's trim button and the autopilot#fm[pages 1-131 and 1-135].

=== Manual pitch override

#idx("Deep stall")#row("SW_MPO") is held at OVRD in one case: a #term("deep stall")#fm[page 1-130]. In a deep stall the jet has left controlled flight and settled at an angle of attack far past the limiter, falling almost flat with little forward speed. The computer already holds the tail fully nose-down, and that is not enough to lower the nose. The pilot sees the angle of attack at the end of its scale, a low airspeed and a nose that does not answer the stick. OVRD gives the stick direct control of the tail, so that the pilot can rock the nose up and down until it falls through (inferred from the switch's description; the recovery is in @emergency-control). The switch has no use in normal flight.

=== Autopilot

Two switches engage the autopilot#fm[pages 1-134 to 1-136]: #row("pitch-hold-switch") (ALT HOLD, A/P OFF, ATT HOLD) and #row("roll-hold-switch") (HDG SEL, ATT HOLD, STRG SEL: the heading set on the EHSI, the present attitude, or steering to the steerpoint). The autopilot banks up to 30°, works within ±60° of pitch and bank, and lets go above 15° angle of attack.

=== Tests and backup

- #row("SW_FLCS_BIT") runs the computer's built-in test on the ground, about 45 seconds#fm[page 1-135]\; #row("lamp_flcs_bit_run_0") is on while it runs, #row("lamp_flcs_bit_fail_0") when it fails.
- #row("SW_FLCS_TEST") checks that each power source reaches the computer#fm[page 1-86]: the #row("lamp_flcs_pwr_0") lights come on.
- #row("SW_DBU") selects a second, simpler set of control software, the digital backup, for a fault of the main software#fm[page 1-120]\; the #row("lamp_dbu_on_0") warning light is on with it.
- The red #row("lamp_flcs_0") warning light and the #row("lamp_caution_flt_cont_sys_0") caution light show faults of the system (@emergency-systems).

#in-sim[
  - *Limiters.* +9 and −3 g; 25° angle of attack in CAT I; 15.5° to 18°, by weight, with slower roll in CAT III. STORES CONFIG is read.
  - *Flaps.* The leading-edge flaps follow their schedule. The trailing-edge flaps go to 20° with the gear handle down and come up between 240 and 370 knots.
  - *Speedbrakes.* #key("Speedbrakes open (hold)") opens them while held, and they stay where the key is let go; #key("Speedbrakes close") closes them. Fully open is 60°, 43° with the gear down.
  - *Manual pitch override.* OVRD removes the negative-g limit and gives the stick direct control of the tail above 29° angle of attack.
  - *Autopilot.* #key("Autopilot: level / nav / off") steps through level flight, steering along the route, and off.
  - #sym.arrow.r *RUN lights with BIT, FLCS PWR with FLCS PWR TEST, DBU ON with DIGITAL BACKUP, the LE FLAPS caution with LE FLAPS at LOCK.* The FLCS warning light comes on after battle damage to the flight controls.
  - *#term("Not modelled").* Faults of the computer and the results of its tests; the digital backup's control laws; LE FLAPS LOCK; pitch and yaw trim, the MANUAL TRIM panel and TRIM/AP DISC (the sim trims roll only); the PITCH and ROLL autopilot switches, which move and do nothing; the STORES CONFIG caution.
]
