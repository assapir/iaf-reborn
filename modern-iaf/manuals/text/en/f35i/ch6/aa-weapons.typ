#import "src.typ": *

This section gives the cockpit steps for a missile from the bay, a missile from the wing and the gun. It gives no figures for what a missile can do. The real jet draws its gun's aiming symbols in the helmet#gun-cues. What the weapon symbols look like is open; the sim's are the F-16's, which stand in (inferred).

=== Before any shot <aa-before>

+ *Set* #ctl("MASTER_ARM") *to ARM* (@stores).
+ *Check that the landing gear handle is up.*
+ *Check the #term("HMD") is on* (@hmd).

=== A missile from the bay <aa-bay>

You aim the AIM-120 with a radar lock. It hangs in the bays, or under the inner wing pylons.

+ *Press* #key("Next air-to-air weapon") *until the helmet names the AIM-120.* #sym.arrow.r *The master mode is air-to-air. The SMS boxes the station.*
+ *Lock the target* on SRCH (@radar-aa). #sym.arrow.r *The helmet shows the designator on the target, with the shape of its identity. Beside the centre it shows a range bracket with the target's range, and the closing speed.*
+ *Check the identity.* A green circle is a friend.
+ *Wait for SHOOT* in the helmet.
+ *Hold* #key("Release selected weapon"). #sym.arrow.r *The bay doors open, the missile leaves, the doors shut.* Hold the key until the missile leaves.

The sim also takes a marked target as the weapons' target: the newest mark (@radar-aa).

=== A short-range missile <aa-short>

The AIM-9X hangs on the outer wing pylons only. You can aim it with the helmet: you look at the target.

+ *Press* #key("Next air-to-air weapon") *until the helmet names the AIM-9X.*
+ *Look at the target*, or lock it with the radar. #sym.arrow.r *The missile's tone rises: its seeker, the heat-sensing head in its nose, hears the target. The helmet shows the missile's aiming mark.* The seeker starts _caged_: it looks only along the radar's line to the target, or where you look, or straight ahead.
+ *Press* #key("Missile seeker: UNCAGE / CAGE"). #sym.arrow.r *The seeker is _uncaged_: it follows the target, and its circle grows. The helmet shows a shoot cue.* These cues are those of the F-16s' helmet sight (inferred). They show when you look aside too. A second press cages the seeker again; it also cages by itself when the target leaves its reach.
+ *Press* #key("Release selected weapon"). #sym.arrow.r *The missile leaves the pylon at once: no door is in its way.*

=== After the launch <aa-after>

Under the range bracket the helmet shows how long the missile still flies: _A_ and the seconds until the AIM-120's own radar comes on, then _T_ and the seconds until it reaches the target; the AIM-9X shows only _T_. With several missiles in the air it shows the one with the longest time. SRCH shows the same time at its top right, and marks the target: a short tail from the launch, flashing once the missile's radar is on, and an X for its last 8 seconds. These are the F-16's cues (inferred).

Keep the lock until _A_ runs out: until then the AIM-120 steers on your radar's track, sent over its data link. If the lock drops, it flies on to where the target would be and turns its own radar on there; a target that turned away by then is lost. A missile whose seeker loses the target flies on unguided.

#key("Missile seeker: SPOT / SCAN") widens a little the line on which the caged seeker hears a target (SCAN), or narrows it again (SPOT). The SMS shows which, beside the weapon.

=== The gun <aa-gun>

+ *Select the gun* with #key("Next air-to-air weapon"). #sym.arrow.r *The helmet shows a funnel: two lines that narrow away from you.*
+ *Fly the target between the funnel's lines*, where they are as wide as its wings.
+ *Hold* #key("Gun trigger"). #sym.arrow.r *The gun fires. The rounds count down on the function bar and on the SMS, from 180.*

=== What the sim lacks <aa-missing>

The real jet's own cues for each weapon, before and after the launch, are #nis: the sim shows the F-16's. A missile's flight and its chances are outside this manual.
