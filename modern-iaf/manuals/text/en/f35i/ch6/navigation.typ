#import "src.typ": *

This section covers how the jet knows where it is, the route and its steerpoints, the map format and the instrument landing system. The real jet's navigation pages belong to the CNI format, which is not public in detail: open.

=== The self test and the inertial system <nav-ins>

After the engine start the real pilot starts a self test of the jet's systems with one button, and about 90 seconds later the jet reports itself ready#ayton. The pilot does not align the #term("INS") by hand (inferred).

#in-sim[The 90 seconds start when the battery switch goes to ON (@cold-start).]

=== Steerpoints and the route <nav-route>

A steerpoint is a point of the planned route. The jet steers to one steerpoint at a time: the selected one.

- #key("Next waypoint") and #key("Previous waypoint") select the next or the previous steerpoint.
- #sym.arrow.r *The function bar of the #term("PCD") shows its number beside NAV.*
- #sym.arrow.r *The helmet shows its number, bearing and distance at the lower right.* A caret under the heading tape marks its bearing; at the tape's end the caret means "turn further". A small square lies on the steerpoint's place on the ground; outside the display's field it waits at the edge.
- #key("Autopilot: level / nav / off") at NAV flies the jet along the route. The function bar shows NAV as the autopilot's mode.

The caret and the square are inferred. No public source says how the symbols behave.

=== The TSD format <nav-tsd>

#display("tsd_link", [The TSD at the 40 NM range: the jet at the centre, the compass rose, the map's outlines, the route's line to steerpoint 1, and four hostile tracks.])

The tactical situation display, TSD, is a map with the jet at its centre and the jet's heading at the top (@fig-d-tsd_link). It shows:

- the compass rose; its radius is the selected range;
- the map's outlines, in grey;
- the route as a white line, with the selected steerpoint;
- the tracks of the radar and of the data link, each by the shape and colour of its identity (@radios), with a line along its heading. A white ring marks the radar's lock;
- the known air-defence sites with a red ring.

Controls, with the pointer:

- *The arrows at the left* step the range: 10, 20, 40 and 80 NM.
- *MAP at the right* shows or hides the map's outlines. The legend is boxed while they show.

#key("TSD page on MFD") brings the TSD to a portal.

#in-sim[TSD-1, TSD-2 and TSD-3 are the same format. On the real jet the three are set up for different tasks (inferred); their real contents are open.]

=== The instrument landing system <nav-ils>

With the master mode at NAV and the landing gear handle down, the helmet shows two lines, one for the runway's centre line and one for the glide path. #sym.arrow.r *Fly the flight path marker to where the lines cross* (@landing). #key("Navigation mode") returns the master mode to NAV.

=== What the sim lacks <nav-missing>

A radio navigation aid and the navigation pages of the CNI format are #nis. Whether the real helmet shows such an aid's channel and distance is open.
