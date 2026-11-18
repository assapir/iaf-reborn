#import "/modern-iaf/manuals/text/en/f35i/ch2/src.typ": *
#let caps = (
  gear_panel: [The gear panel, left of the display.],
  front: [Under the display: the #term("HMD") knob, MASTER ARM and the MASTER CAUTION light.],
  start_panel: [The start panel on the left console.],
)

This section takes the #jet.name from the end of the landing roll to a cold, dark jet. It follows the last two sections of the checklist card. No F-35 checklist is public: both sections are inferred from the F-16's and from this cockpit.

#phases(
  ("after_landing", "shutdown"),
  ([No.], [Phase of the card], [Steps], [Ticked by the sim]),
)

=== After landing <shutdown-after-landing>

Leave the runway to its cold side#afi[paragraph 3.21.3]: the side that the jets landing behind do not use (the meaning is inferred). Do these steps once the jet is off the runway and slow.

#steps(
  "after_landing",
  captions: caps,
  notes: (taxi_light_in: [The switch moves only: the landing and taxi lights are #term("not modelled"); the navigation lights and the strobe are always on.]),
  figs: ("gear_panel", "front"),
)

Taxi back as you taxied out, at no more than 30 kt, and 10 kt in a turn#afi[paragraph 3.4.1].

=== Engine shutdown <shutdown-engine>

Stop on the parking spot.

#steps(
  "shutdown",
  captions: caps,
  seen: (
    throttle_off: [#term("RPM") falls: stopped after about a minute; the display goes dark at about 52~%],
  ),
  figs: ("gear_panel", "start_panel"),
  notes: (
    throttle_off: [The throttle stops at idle; OFF takes its own key.],
  ),
)

#idx("Throttle OFF")#caution[The throttle at OFF cuts the engine's fuel at once, wherever the jet is. On the ground after a flight that is the shutdown. In the air it stops the engine: the jet glides. The only use of OFF in the air is as a step of an engine restart (@emergency-engine; the sim restarts the engine with the ground start only). The key is apart from the other throttle keys for this reason.]

After the flight the real pilot walks around the jet once more and looks for bird strikes, lost panels and damage from too much g#afi[paragraph 3.28]. #term("Not modelled").

#in-sim[A jet shut down can be started again with the card from its first section, once the RPM is under 20~%.]
