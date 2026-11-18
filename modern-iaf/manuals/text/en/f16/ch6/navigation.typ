#import "src.typ": *

#layout-head

=== The INS

The #term("INS") gives the jet its position, heading and attitude. It must align before it can navigate: the full alignment at NORM takes 8 minutes, the stored-heading alignment (#term("STOR HDG")) 90 seconds#fm[section I, "Inertial navigation system"]. Then #row("INS") goes to NAV. The steps are in @cold-start.

#in-sim[
  - While it aligns #then[the #term("HUD") shows ALIGN; the #term("DED")'s INS page (LIST, 6) counts its status down from 99 to 10 and then shows RDY; ALIGN flashes.]
  - Until the INS navigates, the HUD, the EHSI and the DED show no steerpoint, and the NAV page reads LOW.
  - The INS does not drift.
]

=== Steerpoints

The route is a list of steerpoints. The current one is on the DED's main page, on the HUD (a diamond, with its bearing, distance and time) and on the HSD (@mfd).

+ Step the steerpoint: #key("Next waypoint") or #key("Previous waypoint"), or the #term("ICP")'s rocker on the main page (@ufc). #then[The HUD's diamond and the HSD's filled steerpoint move to it.]
+ Edit one: the STPT page; type the latitude, longitude, elevation and time, each with ENTR.
+ Mark a place: the MARK page, ENTR. #then[It becomes steerpoint 26; the next marks take 27 to 30. The HSD draws each as an X.] Pick a markpoint on the STPT page to steer to it.

The autopilot's steering follows the route's steerpoints, not a markpoint.

=== TACAN and the EHSI

The TACAN gives the bearing and distance to a ground station. Set its channel and band on the T-ILS page. The EHSI, the compass display low on the centre panel, steers to the steerpoint or to the TACAN station: #key("EHSI mode NAV / TCN") steps its mode. A station is received within the line of sight.

=== ILS

With the gear down the HUD shows the ILS's two needles, the localizer and the glide slope, for the runway. The approach is in @landing.

#in-sim[#term("Not modelled"): the ILS's own frequencies (the ILS serves the runway at any frequency), marker beacons, the INS's position error and its updates.]
