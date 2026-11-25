#import "/modern-iaf/manuals/text/en/f35i/ch2/src.typ": *

The #jet.short takes fuel in the air from a tanker's boom, through a receptacle on its back (@fuel). The cockpit procedure is in the F-35's flight manual, which is not public: open. Two public rules touch it:

- On the ground the crew and the pilot have a hand signal for opening and closing the receptacle's door#afi[paragraph 3.2.3]. Inferred: the door is tried on the ground before a flight that will refuel.
- After a refuelling the pilot does the checks of the cruise again: the cautions and the fuel first (@cruise-checks)#afi[paragraph 3.14.1].

Inferred from the F-16's procedure: the weapons are made safe before the jet closes on the tanker, the door is opened before contact and closed after it, and the fuel is checked when the jet has left the boom. The steps below are these, inferred; the #term("notebook")'s air refuelling tab holds the same steps and ticks them in flight, when the flight has a tanker (#other("game", "notebook")).

#let caps = (front: [Under the display: the #term("HMD") knob, MASTER ARM and the MASTER CAUTION light.])

=== Before contact <ar-before>

#steps("ar_before", captions: caps, figs: ("front",))

=== Contact <ar-contact>

#steps("ar_contact")

=== After refuelling <ar-after>

#steps("ar_after", notes: (ar_checks: [The cruise checks: @cruise-checks.]))

#idx("Tanker")#in-sim[
  The tanker is a KC-46A Gideon or a 707 Re'em. It flies a left-hand racetrack at 30,000 ft and 310 KCAS (480 kt true), its legs 50 NM long and 20 NM apart, and shows on the radar and the data link as a friendly aircraft. Ask it for fuel on the radio (#other("game", "tanker")).
  - *Door.* #key("Air refuelling door (open / close)") opens and closes the receptacle's door. #sym.arrow.r *The #term("PCD")'s FUEL window shows AR DOOR OPEN.* These words are the sim's own: the real format's indication is open.
  - *Pre-contact.* About 15 m (50 ft) behind the contact position and 3 m below it, steady, closing at under 1 m/s, for 2 s. #sym.arrow.r *"Cleared contact".*
  - *Contact.* Close at 2 to 3 kt; within 1.5 m of the contact position the boom latches. #sym.arrow.r *"Contact"; the FUEL window shows AR CONTACT.* Fuel flows at 3,000 lb a minute from the KC-46A and 2,000 lb a minute from the Re'em. The pilot director lights under the tanker's nose command the moves: the left row up (U) and down (D), the right row forward (F) and aft (A).
  - *Disconnect.* Leaving the boom's envelope, #key("A/R DISC: disconnect from the boom") or closing the door. #sym.arrow.r *"Disconnect"; the FUEL window shows AR DISC for 3 s.* Back to pre-contact to be cleared again. Too close or too high: #sym.arrow.r *"breakaway, breakaway, breakaway"*: drop back 30 m and wait to be cleared again.
  - *Tanks full.* #sym.arrow.r *"Refuelling complete, cleared right wing".* Move to the tanker's right wing and close the door.
  - *#term("Not modelled").* The rendezvous; the boom operator's directions by distance; refuelling without radio; the lights at night.
]
