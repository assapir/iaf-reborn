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
+ *Hold* #key("Release selected weapon"). #sym.arrow.r *The bay doors open, the missile leaves, the doors shut.* Hold the key until the missile leaves.

The sim also takes a marked target as the weapons' target: the newest mark (@radar-aa).

=== A short-range missile <aa-short>

The AIM-9X hangs on the outer wing pylons only. You can aim it with the helmet: you look at the target.

+ *Press* #key("Next air-to-air weapon") *until the helmet names the AIM-9X.*
+ *Look at the target*, or lock it with the radar. #sym.arrow.r *The helmet shows the missile's aiming mark, and then a shoot cue.* These cues are those of the F-16s' helmet sight (inferred). They show when you look aside too.
+ *Press* #key("Release selected weapon"). #sym.arrow.r *The missile leaves the pylon at once: no door is in its way.*

=== The gun <aa-gun>

+ *Select the gun* with #key("Next air-to-air weapon"). #sym.arrow.r *The helmet shows a funnel: two lines that narrow away from you.*
+ *Fly the target between the funnel's lines*, where they are as wide as its wings.
+ *Hold* #key("Gun trigger"). #sym.arrow.r *The gun fires. The rounds count down on the function bar and on the SMS, from 180.*

=== What the sim lacks <aa-missing>

The real jet's own cues for each weapon, and any cue after the launch, are #nis. A missile's flight and its chances are outside this manual.
