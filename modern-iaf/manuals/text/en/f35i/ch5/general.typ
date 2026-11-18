#import "../ch4/src.typ": *

The #jet.short is flown through its computer (@flight-controls): the stick asks for a response, and the flight control system moves the surfaces to give it. The F-35's control laws are not public, so what exactly the stick commands in each phase of flight is open.

What pilots have said in public#hanche:

- The jet flies at a much higher angle of attack than the F-16, and at its limit it still answers the pedals quickly.
- It slows down very fast when the pilot asks for it.
- It shakes at high g and at high angle of attack; the buffet is a cue of high g and high angle of attack.

=== Engine response

The F135 goes from flight idle to maximum power in about six seconds#pw135. The time to military power alone is open.

#in-sim[
  - The stick commands g, and a roll rate sideways; with it free the jet holds 1 g. These are the F-16's control laws, moved up to the #jet.short's limits (inferred). A full pull at 550 kt reaches 9 g in about 2 seconds. Full stick rolls at about 240° a second (the F-16's figure, inferred).
  - *Engine.* Idle to military power takes about 5 seconds, to full afterburner 6 seconds.
  - *Speedbrake.* The jet slows as with the F-16's speedbrakes fully open, at any speed and with the gear down too.
  - *Trim.* Roll only.
  - #term("Not modelled"): the buffet, the active stick's forces, any change of the control laws with the gear down.
]
