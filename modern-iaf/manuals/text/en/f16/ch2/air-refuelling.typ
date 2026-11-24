#import "/modern-iaf/manuals/text/en/f16/ch1/src.typ": *

The F-16 takes fuel in the air from a tanker's boom, through a receptacle on its back behind the canopy (@fuel). The sim has no tanker: this whole section is #term("not modelled") and gives the real jet's cockpit procedure in outline#fm[the section on air refuelling, "Normal air refueling procedures", page 8-34].

+ *Safe the weapons* before closing on the tanker: MASTER ARM off or at SIMULATE, the laser off, the stores page checked.
+ *Before contact:* the radar and the other emitters as the tanker's rules ask; at night the outside lights dim and steady, the anti-collision light off. Then #row("SW_AIR_REFUEL") to OPEN. #sym.arrow.r *#row("lamp_ar_rdy_0") comes on*: the door is open and the receptacle is ready.
+ *Contact:* the boom's operator flies the boom into the receptacle. #sym.arrow.r *#row("lamp_ar_nws_0") comes on.* Hold position and watch the fuel quantity rise.
+ *Disconnect:* press the disconnect button on the stick for a moment. #sym.arrow.r *#row("lamp_ar_disc_0") comes on.* Stay in position until the boom is seen to be clear.
+ *After refuelling:* AIR REFUEL to CLOSE; the three lights out; check the fuel; set the weapons, the radar and the lights back.

#idx("AIR REFUEL switch")#caution[With the AIR REFUEL switch at OPEN the flight controls fly the jet as they do with the gear down, gentler and with a fixed roll rate, which is what flying close behind a tanker needs; and the external tanks lose their pressure, so that they can be filled. Left at OPEN after the refuelling, the jet stays slow in roll and the external tanks do not feed the engine#fm[the section on air refuelling, "Post air refueling", the caution at item 1, page 8-34]. You recognise it by the RDY light still on. The switch has one more use: in the real jet's fuel emergencies it is opened on purpose, to take the pressure off the external tanks (@emergency-systems).]

#in-sim[The switch moves and its door's light can be set (@fuel, @lighting). #sym.arrow.r *#row("lamp_ar_rdy_0") comes on at OPEN while hydraulic system B has pressure. No fuel is taken.*]
