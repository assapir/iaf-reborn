#import "../ch4/src.typ": *

=== Take-off

The rotation and take-off speeds, and the technique, are open. The public rules add#afi[paragraphs 3.6.2 to 3.6.5]: use the afterburner when the roll at military power would take more than half the runway; steer to the centre of the runway at the start of the roll.

=== Approach and landing

In an accident in 2020 a jet held 202 kt on its approach, about 50 kt too fast, and touched down at 5.2° angle of attack, about 8° less than it should have had; it bounced and was lost#eglin. The normal final approach is therefore flown at about 13° angle of attack and near 150 kt at a light weight (both inferred from those figures). The flare, the landing roll and the braking technique are open.

=== Crosswind

The technique and the limits are open. In formation the wingman flies on the upwind side when the crosswind is above 5 kt#afi[paragraph 3.27.1.2].

#in-sim[
  - *Take-off.* The pedals steer the nose wheel. Ease the stick back at about 165 kt (@cold-start-takeoff).
  - *Approach.* At 13° angle of attack and 36,000 lb the jet flies about 152 kt; the speed follows the weight. The flaperons droop by themselves with the gear handle down.
  - *Ground effect, wind and gusts.* Modelled as for every jet of the sim: the jet floats a little near the runway, and the wind moves it.
  - #term("Not modelled"): the F-35's own landing aids and control laws on the approach.
]
