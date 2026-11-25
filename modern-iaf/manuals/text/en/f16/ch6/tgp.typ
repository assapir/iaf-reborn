#import "src.typ": *

#layout-head

The targeting pod is a camera with a laser, hung under the right side of the intake. It shows a picture of the ground, holds its aim on a point or a vehicle, and marks the target with its laser for the laser-guided bombs#dcs["Targeting/sensor pods", page 41]. In this two-seat jet the rear crew member works the pod; in the sim you do. The pod is a store: it must be loaded (@stores).

=== Power

+ #row("AVIONICS_MMC") and #row("r-hdpt-switch") on. #then[The TGP format shows NOT TIMED OUT while the pod cools, for 3 minutes.]
+ Show the TGP format (@mfd). Without a pod it reads NO POD.

#picture("snsr_pwr", ("r-hdpt-switch": "1"), width: 60%)

=== The format's buttons

The two pictures of the format are in @fig-d-mfd_formats.

#table(columns: (21%, 19%, 1fr, 15%), table.header[*Button*][*Legend*][*What it does*][*Key*],
  [#osb(1)], [STBY / A-G], [Standby: the picture, no track, no laser. A-G: the working mode.], [],
  [#osb(2)], [WIDE / NARO], [The field of view.], [],
  [#osb(3)], [LASR], [Fires the laser; inverse while it fires.], [#key("Laser designator")],
  [#osb(7)], [CZ], [Cursor zero: the pod back on the designated point.], [],
  [#osb(20), #osb(19)], [the zoom arrows], [The zoom: 1, 2, 4, 8.], [],
)

Read on the picture: the track's name at the top; the laser code at the lower left with ARM under it when the laser is armed; at the lower right the slant range, or a released bomb's time to impact.

=== Aiming the pod

Make the TGP the SOI (@mfd). Then:

#table(columns: (27%, 1fr, 22%), table.header[*Action*][*Result*][*Key*],
  [TMS down], [The pod is slaved to the radar's designated point (@radar-ag), else to the steerpoint, and follows it. No track name shows.], [#key("Radar: drop bug / lock (TMS down)")],
  [The cursor keys], [The pod slews; the name reads INR. On release it holds the ground point: AREA.], [#key("Slew EO sensor / radar cursor up")],
  [TMS up], [POINT: the pod follows the vehicle under the cross. With none there: AREA.], [#key("Radar: bug / lock (TMS up)")],
  [TMS right], [AREA: the pod holds the ground point under the cross.], [#key("Radar: next submode, ACM 10 x 60 (TMS right)")],
)

#then[Once the pod tracks, the #term("HUD")'s box sits on the pod's aim point with its slant range.] When the jet's body hides the aim point the format shows *MASK* and the laser holds.

=== The laser

+ Set the code if needed: the #term("DED")'s LASR page (LIST, 0, 5). The pod and the bombs start on 1688; a bomb follows the laser only when the codes match.
+ #row("laser-arm-switch") to ARM: #key("Laser arm"). #then[ARM shows at the lower left of the picture.]
+ Fire: #key("Laser designator") or #osb(3). #then[LASR turns inverse and an L flashes.] Press again to stop.
+ With the laser armed, the pod fires it by itself in the last seconds of a released bomb's fall (the time is the DED's LASER ST TIME).

#in-sim[
  - The laser fires only in A-G, armed, with the aim point in sight. When the pod leaves A-G (STBY, or its power lost), the laser stops; fire it again once the pod works.
  - The cooling time, the masking angle and the automatic laser's layout are inferred.
  - #term("Not modelled"): the picture's polarity (WHOT, BHOT) and its television picture; the laser's spot search and tracking of another laser.
]
