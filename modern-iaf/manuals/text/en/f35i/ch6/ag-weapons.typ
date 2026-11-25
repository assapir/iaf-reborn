#import "src.typ": *

This section gives the cockpit steps for the bombs that fly to coordinates, and for the gun against the ground. The real jet's weapon formats and its helmet's bombing symbols are not public; the sim's cues are the F-16's, which stand in (inferred).

=== The bombs <ag-bombs>

The GBU-31, the GBU-32 and the GBU-39 steer themselves to a point on the ground that the jet gives them at the release. They do not follow the laser. Where the jet carries one large bomb it can carry four GBU-39 instead#sdb. In the sim the four hang on one rack in the bay, and each takes its own target.

A bomb takes its point in one of two modes. #key("GPS bomb PRE / VIS") changes the selected bomb's mode; the helmet's weapon line reads PRE or VIS.

- *PRE, planned:* the point is known before the release. Each bay station, and each of the four GBU-39 on its rack, takes its own PRE target before the flight (#other("game", "briefing")). A bomb with no target of its own takes its station's; a station with none takes the route's target steerpoint, on the weapons range the steerpoint on the targets. #key("GPS bomb next PRE target") steps the next bomb's point from its own through the other planned targets and the route's steerpoints; the WPN-S page lists each bomb's target.
- *VIS, by eye:* the point is the one you designate in flight: the point under the TFLIR's cross while its laser fires (@tflir), or else the point designated on the radar's ground map (@radar-ag).

The WPN-S format (@pcd) lists each bomb of the selected store with its PRE target by name (TGT 2, STPT 1, PT for a point of the map), its distance and bearing, greys the bombs gone, and sets the release profile: PROF, SGL or PAIR, the count and the interval.

#in-sim[The PRE targets are picked on a map before the flight (#other("game", "briefing")), not loaded from a planning computer.]

=== The helmet's cues <ag-cues>

With one of these bombs selected and a point to aim at, the helmet shows:

#display("helmet_gps", [A GBU-31 in PRE, level, 18 km from Target 1: the steering line through the centre, the bracket and its caret, and TMR 0:45 under the bracket.], width: 100%)

- *a box* on the point. Outside the display's field it waits at the edge with an X over it. It shows when you look aside too;
- *a steering line* through the point. #sym.arrow.r *Put the flight path marker on it;*
- *a bracket* right of the centre, with a caret beside it. The caret is the distance to the point; the bracket is the span of distances from which the bomb can be released;
- *under the bracket,* TMR with the time until the caret enters the bracket, and then IN RNG;
- *after the release,* TTI with the time until the last bomb arrives, in the time's row at the lower right.

With no point to aim at, the helmet shows the aiming mark of a falling bomb instead, and the bomb goes where that mark lies.

=== To release <ag-release>

+ *Set* #ctl("MASTER_ARM") *to ARM.*
+ *Press* #key("Next air-to-ground weapon") *until the helmet names the bomb.* #sym.arrow.r *The master mode is air-to-surface. The SMS boxes the station.*
+ *Choose PRE or VIS.* In VIS, designate the point.
+ *Turn until the flight path marker is on the steering line.*
+ *Wait for IN RNG.*
+ *Check:* at most 600 KCAS, a dive of at most 60°, the landing gear handle up (@stores).
+ *Hold* #key("Release selected weapon"). #sym.arrow.r *The bay doors open, the bomb leaves, the doors shut. TTI counts down.* Hold the key for the next bomb; each takes its own point.

=== Strafing <ag-strafe>

+ *Select the gun in the air-to-surface master mode.* #sym.arrow.r *The helmet shows an aiming mark for the gun, and the radar measures the distance to the ground along it (@radar-ag).*
+ *Dive, put the mark on the target and hold* #key("Gun trigger").
+ *Pull out early.* The break X means pull now (@hmd).
