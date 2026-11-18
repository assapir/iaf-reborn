#import "../ch4/src.typ": *

#block-head

The #jet.short is unstable by design and flown by its computer (@flight-controls). The pilot does not move the surfaces; the stick asks for a response, and the #term("FLCS") gives the same response at every speed and height#fm[section VI, "Normal flight characteristics", page 6-3].

=== What the controls command

- *Stick, fore and aft.* A force on the stick commands a change of g from the trimmed state, up to 15° angle of attack. Above 15° the stick grows heavier, as the cue of a rising angle of attack. The buffet that warns in other jets is not always there near the limits#fm[section VI, "Normal flight characteristics", page 6-3].
- *Stick, sideways.* A force commands a roll rate#fm[section VI, "Normal flight characteristics", page 6-3].
- *Pedals.* A force commands a rudder position. In a roll the computer adds the rudder itself, so pedals do not improve a roll; they make a departure more likely#fm[section VI, "Normal flight characteristics", page 6-3].

=== Hands off

With the stick free the jet holds 1 g, whatever the speed, until the angle of attack passes 15°. Speed changes therefore move neither the stick nor the trim, and the jet gives little sign of them: watch the airspeed. Above 15° the computer lowers the nose slowly as a warning#fm[section VI, "Trim", page 6-2]. In roll the free stick holds a roll rate of zero#fm[section VI, "Trim", page 6-2].

=== The limiters

The limiters of g, angle of attack, roll rate and rudder make full stick safe in most of the envelope (@limits-g). They need air over the tail to work. In a climb with the nose high and the speed falling they run out of it, and the jet can depart with the stick doing nothing wrong at that moment#fm[section VI, "FLCS limiters", page 6-1]. The manual's cure is the rule of @limits-airspeed: recover at the tone.

=== With the gear down

With the gear handle down the trailing-edge flaps come down and the computer changes its gains: the stick commands a pitch rate up to 10° angle of attack, and the jet no longer holds 1 g by itself#fm[section I, "Trim", page 1-135]. STORES CONFIG has no effect#fm[section I, "AOA/g limiter", page 1-121].

=== Speedbrakes, thrust and trim

- The speedbrakes slow the jet at any speed with no change of trim and almost no buffet#fm[section VI, "Speedbrakes", page 6-2].
- A change of thrust changes the trim little or not at all#fm[section VI, "Effect of thrust", page 6-5].
- The roll trim's authority is about a fifth of the stick's#fm[section VI, "Trim", page 6-2].

=== Engine response

#if sufa [
  The engine's computer keeps the response the same over the envelope (@engine). The time from idle to military power of the #jet.short's F100-PW-229 is open; the earlier F100-PW-220 takes about 3 seconds#tm4320.
] else [
  The time from idle to military power of the #jet.short's F110-GE-100 is open.
]
How the thrust is used on the approach is in @handling-takeoff-landing.

#in-sim[
  - The stick commands g and roll rate as above; with it free the jet holds 1 g. A full pull at 550 kt reaches 9 g in about 2 seconds. Full stick rolls at about 240° a second.
  - The stick grows no heavier above 15°: a keyboard or a spring stick cannot show it. The tone above about 27° is the cue.
  - *Engine.* Idle to military power takes about 3 seconds#if sufa [, to full afterburner about 3.5 seconds]#if not sufa [ (inferred from the F100's time)].
  - *Trim.* Roll only.
  - #term("Not modelled"): the change of gains with the gear down (the stick commands g there too), the stick's forces, the small oscillations and roll hesitations the manual lists, the pitch and yaw trim.
]
