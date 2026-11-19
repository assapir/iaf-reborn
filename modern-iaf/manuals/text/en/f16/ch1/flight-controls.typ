#import "src.typ": *

The #jet.short is flown through a computer. The #term("FLCS") is a digital fly-by-wire system with four channels: the stick, the pedals and the trim send electrical signals to it, and it moves the control surfaces#fm[page 1-120]. The #row("anim000") senses the force of the hand and moves only about a quarter of an inch#fm[page 1-127]. The jet cannot be flown without the computer; its four channels and its several sources of power (@electrical) are there for that (inferred).

=== The limiters

The computer limits what the pilot can ask for, so that full stick does not break the jet or throw it out of control#fm[page 1-121]:

- *Load factor.* Up to +9 g, and less as the angle of attack rises above 15°; down to −3 g.
- *Angle of attack, CAT I.* About 25°.
- *Angle of attack, #term("CAT III").* About 16° to 18°, with slower roll, for a jet with heavy or large stores (the reason, an earlier loss of control with such stores, is inferred).

#row("SW_STORES_CONFIG") chooses CAT I or CAT III#fm[page 1-130]. The #row("lamp_caution_stores_config_0") caution light means that the switch is in the wrong position for the loading category, or that the stores management set's category disagrees with the load#fm[figure 3-2, sheet 6].

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

#idx("Autopilot")Two switches on the MISC panel work the autopilot#fm[pages 1-134 to 1-136]. #row("roll-hold-switch") engages it: ALT HOLD holds the altitude, ATT HOLD the pitch attitude, A/P OFF disengages it. #row("pitch-hold-switch") chooses the roll mode while the autopilot is engaged: HDG SEL turns to the heading set on the EHSI and holds it, ATT HOLD holds the bank, STRG SEL steers to the selected steerpoint. Set the heading marker to the present heading before you engage HDG SEL, or the jet turns to the marker.

The autopilot's commands add to the stick's, within limits: in pitch +0.5 to +2 g, in roll 30° of bank and 20° a second of roll rate. ALT HOLD engaged in a climb or dive under 2,000 feet a minute picks an altitude it can level at; it holds it within 100 feet up to 40,000 feet. The attitude modes stop working beyond 60° of pitch or bank, while the switch stays engaged. In the attitude modes a firm push on the stick flies the jet by hand, and the autopilot holds the attitude where the stick is let go. The paddle switch on the stick interrupts the autopilot while it is held; in ALT HOLD the autopilot then holds the altitude where the paddle is let go.

The PITCH switch is held engaged by a solenoid. It drops to A/P OFF, or will not stay engaged, with AIR REFUEL at OPEN, ALT FLAPS at EXTEND below 400 knots, the gear handle down, MPO at OVRD, TRIM/AP DISC at DISC, or the low speed warning tone sounding#fm[page 1-135]. Above 15° angle of attack, or without the data it needs, the autopilot disconnects: #row("lamp_caution_flt_cont_sys_0") lights and the fault list shows FLCS A/P FAIL. It cannot be engaged again until an FLCS RESET in 1 g flight below 15° clears the fault. An autopilot that is engaged but does not hold its mode gives FLCS A/P DEGR and stays engaged#fm[page 3-112].

=== Tests and backup

- #row("SW_FLCS_BIT") runs the computer's built-in test on the ground, about 45 seconds#fm[page 1-135]\; #row("lamp_flcs_bit_run_0") is on while it runs, #row("lamp_flcs_bit_fail_0") when it fails.
- #row("SW_FLCS_TEST") checks that each power source reaches the computer#fm[page 1-86]: the #row("lamp_flcs_pwr_0") lights come on.
- #row("SW_DBU") selects a second, simpler set of control software, the digital backup, for a fault of the main software#fm[page 1-120]\; the #row("lamp_dbu_on_0") warning light is on with it.
- The red #row("lamp_flcs_0") warning light and the #row("lamp_caution_flt_cont_sys_0") caution light show faults of the system (@emergency-systems).

#in-sim[
  - *Limiters.* +9 and −3 g; 25° angle of attack in CAT I; 15.5° to 18°, by weight, with slower roll in CAT III. STORES CONFIG is read. #sym.arrow.r *The STORES CONFIG caution lights while the switch is off the load's category* (@limits-g).
  - *Flaps.* The leading-edge flaps follow their schedule. The trailing-edge flaps go to 20° with the gear handle down and come up between 240 and 370 knots.
  - *Speedbrakes.* #key("Speedbrakes open (hold)") opens them while held, and they stay where the key is let go; #key("Speedbrakes close") closes them. Fully open is 60°, 43° with the gear down.
  - *Manual pitch override.* OVRD removes the negative-g limit and gives the stick direct control of the tail above 29° angle of attack.
  - *Autopilot.* #key("Autopilot PITCH switch up (ALT HOLD)") and #key("Autopilot PITCH switch down (ATT HOLD)") move the PITCH switch a step; #key("Autopilot ROLL switch up (HDG SEL)") and #key("Autopilot ROLL switch down (STRG SEL)") the ROLL switch. #key("Paddle switch: autopilot interrupted (hold)") is the paddle, #key("TRIM/AP DISC switch (NORM / DISC)") the disconnect switch, #key("FLCS RESET") the reset. #sym.arrow.r *A switch that does not stay engaged springs back to A/P OFF, and a line says why.* The modes, limits and disengage conditions above are modelled; the stick's trim button is not.
  - *The sim's own autopilot.* #key("Autopilot: level / nav / off") steps through level flight, steering along the route, and off. While it flies, the PITCH switch stays at A/P OFF.
  - #sym.arrow.r *RUN lights with BIT, FLCS PWR with FLCS PWR TEST, DBU ON with DIGITAL BACKUP, the LE FLAPS caution with LE FLAPS at LOCK.* The FLCS warning light comes on after battle damage to the flight controls.
  - *#term("Not modelled").* Faults of the computer and the results of its tests; the digital backup's control laws; LE FLAPS LOCK; pitch and yaw trim and the MANUAL TRIM panel (the sim trims roll only); the autopilot's terrain-following blend and its transonic behaviour.
]
