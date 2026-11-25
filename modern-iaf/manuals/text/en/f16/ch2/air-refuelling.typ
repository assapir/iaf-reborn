#import "/modern-iaf/manuals/text/en/f16/ch1/src.typ": *

#let caps = (master_arm: [The MASTER ARM switch on the MISC panel.])

The F-16 takes fuel in the air from a tanker's boom, through a receptacle on its back behind the canopy (@fuel). The steps below are the real jet's cockpit procedure in outline#fm[the section on air refuelling, "Normal air refueling procedures", page 8-34]; the box after them gives what the sim does. The #term("notebook")'s air refuelling tab holds the same steps and ticks them in flight; it is there only when the flight has a tanker (#other("game", "notebook")).

=== Before contact <ar-before>

#steps(
  "ar_before",
  captions: caps,
  figs: ("master_arm",),
  seen: (ar_door_open: [#row("lamp_ar_rdy_0") comes on: the door is open and the receptacle is ready]),
  notes: (
    ar_arm_off: [The weapons are made safe before the jet closes on the tanker; the laser goes off and the stores page is checked with them.],
  ),
)

=== Contact <ar-contact>

#steps(
  "ar_contact",
  notes: (
    ar_contact: [To leave the boom, press the disconnect button on the stick for a moment. #row("lamp_ar_disc_0") comes on. Stay in position until the boom is seen to be clear.],
  ),
)

=== After refuelling <ar-after>

#steps(
  "ar_after",
  seen: (ar_door_closed: [RDY, AR/NWS and DISC out]),
)

#idx("AIR REFUEL switch")#caution[With the AIR REFUEL switch at OPEN the flight controls fly the jet as they do with the gear down, gentler and with a fixed roll rate, which is what flying close behind a tanker needs; and the external tanks lose their pressure, so that they can be filled. Left at OPEN after the refuelling, the jet stays slow in roll and the external tanks do not feed the engine#fm[the section on air refuelling, "Post air refueling", the caution at item 1, page 8-34]. You recognise it by the RDY light still on. The switch has one more use: in the real jet's fuel emergencies it is opened on purpose, to take the pressure off the external tanks (@emergency-systems).]

#idx("Tanker")#idx("Pre-contact")#idx("Pilot director lights")#in-sim[
  The tanker is a KC-46A Gideon or a 707 Re'em. It flies a left-hand racetrack at 30,000 ft and 310 KCAS (480 kt true), its legs 50 NM long and 20 NM apart, and shows on the radar and the data link as a friendly aircraft. Find it there and join it from behind and below. Ask it for fuel on the radio (#other("game", "tanker")).
  - *Request.* #sym.arrow.r *The tanker answers "cleared pre-contact"*, or "stand by, observation left" while another jet is on the boom: wait off its left wing until it clears you.
  - *Door.* #row("SW_AIR_REFUEL") to OPEN (#key("Air refuelling door (open / close)"), or a click on the switch). #sym.arrow.r *#row("lamp_ar_rdy_0") comes on while hydraulic system B has pressure.* While the switch is at OPEN the external tanks hold their fuel and feed nothing.
  - *Pre-contact.* Fly to about 15 m (50 ft) behind the contact position and 3 m below it, and hold there steady, closing at under 1 m/s, for 2 s. #sym.arrow.r *"Cleared contact".*
  - *Contact.* Close at 2 to 3 kt to the contact position. Within 1.5 m of it and steady, the boom's operator flies the boom in and latches it. #sym.arrow.r *"Contact"; #row("lamp_ar_nws_0") on, RDY out.* Fuel flows at 3,000 lb a minute from the KC-46A and 2,000 lb a minute from the Re'em.
  - *Holding position.* Two rows of five lamps under the tanker's nose, the pilot director lights, tell you where to move. The left row is the elevation: U forward, D aft. The right row is the telescope: F forward, A aft. The lit lamp commands the move. The centre lamp is green, then amber, then red the further you are off.
  - *Leaving the boom's envelope* disconnects. The boom reaches from 25° to 40° below the tanker and 10° to each side; its telescope from 6 to 21 ft on the KC-46A and from 6 to 18 ft on the Re'em. #sym.arrow.r *"Disconnect"; #row("lamp_ar_disc_0") on for 3 s, then RDY again.* Go back to pre-contact to be cleared again.
  - *Too close or too high.* #sym.arrow.r *"Breakaway, breakaway, breakaway".* Drop back 30 m and wait: the tanker clears you to pre-contact again.
  - *Disconnect yourself* with #key("A/R DISC: disconnect from the boom") (the stick's NWS A/R DISC MSL STEP button), or with AIR REFUEL to CLOSE.
  - *Tanks full.* #sym.arrow.r *The boom lets go; "refuelling complete, cleared right wing".* Move to the tanker's right wing and close the door. The next jet is cleared to the boom.
  - *#term("Not modelled").* The flight controls' take-off and landing gains with the door open; the rendezvous; the boom operator's directions by distance; refuelling without radio; the lights at night.
]
