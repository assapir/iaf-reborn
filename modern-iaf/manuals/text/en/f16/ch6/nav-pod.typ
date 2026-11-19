#import "src.typ": *

#layout-head

The navigation pod hangs under the left side of the intake. Its infrared camera (FLIR) draws a picture of the ground ahead on the HUD, under the HUD's symbols, by day and at night. On the F-16I the pod is the LANTIRN AN/AAQ-13, whose terrain-following radar (TFR) also flies the jet low over the ground; on the F-16D it is the Pathfinder, the FLIR only. The pod is a store: it must be loaded (@stores).

=== Power and the FLIR format

+ #row("AVIONICS_MMC") and #row("l-hdpt-switch") on. #then[The FLIR format shows NOT TIMED OUT while the camera warms up, for 7 minutes; then STBY.]
+ Show the FLIR format (@mfd): FLIR by #osb(16) on the format menu. Without a navigation pod it is not offered.
+ #osb(1) to OPER. #then[The picture shows on the HUD; the format reads FLIR ON HUD.]

#table(columns: (21%, 19%, 1fr), table.header[*Button*][*Legend*][*What it does*],
  [#osb(1)], [STBY / OPER], [OPER puts the picture on the HUD; STBY takes it off.],
  [#osb(6)], [WHOT / BHOT], [The polarity: hot shows white, or black.],
  [#osb(20), #osb(19)], [GAIN+ / GAIN-], [The picture's contrast a step up or down.],
  [#osb(18), #osb(17)], [LVL+ / LVL-], [The picture's level a step up or down.],
)

=== Snap-look and look-into-turn

With the HUD the SOI (DMS up, @mfd), hold a cursor key: the picture shows the ground 20° to that side, or 10° up or down, and comes back when the key is let go. In a bank the picture leans into the turn by itself, up to 10°. #then[While the picture is shifted the flight path marker is dashed.]

=== Terrain following (F-16I)

The TFR format is TFR by #osb(17) on the format menu, offered with the LANTIRN only.

#table(columns: (21%, 19%, 1fr), table.header[*Button*][*Legend*][*What it does*],
  [#osb(1)], [NORM / WX / LPI / VLC], [The mode. With #row("quiet-switch") at QUIET the TFR stays in LPI; at SILENT it does not work.],
  [#osb(2)], [SCP], [The set clearance: 1,000, 500, 300 or 200 ft (VLC: 100 ft).],
  [#osb(3)], [HARD / SOFT / SMTH], [The ride: how hard the TFR pulls and pushes.],
)

The format shows the TF state at the top (ATF ACTIVE, ATF STBY, MAN TF, SILENT), the terrain ahead with the clearance line under the jet, and a fly-up's name at the bottom.

+ Manual TF: fly the flight path marker into the HUD's TF box.
+ Automatic TF: #row("adv-mode-button") (#key("ADV MODE (automatic TF)")). #then[The button's ACTIVE lights and the TFR flies the pitch; you fly the roll and the speed. Your own pitch adds to the TFR's.]
+ Keep the speed within the TF band (300 to 600 knots): outside it the airspeed scale flashes.

The HUD shows LIMIT beside the TF box when the climb needed is past the ride, and NO TER where the terrain ahead is unknown.

*Fly-ups.* The TFR pulls up at 2 g below half the clearance (FLY UP), at a slope too steep ahead (OBSTACLE) and when the climb has been past the ride for a second (G-LIMIT). The name flashes on the HUD and the voice calls "Pull up". In manual TF a fly-up comes only with MANUAL TF FLYUP at ENABLE (#key("MANUAL TF FLYUP switch")). Hold #key("Paddle switch: autopilot interrupted (hold)"), the one paddle switch on the stick, to hold a fly-up off. If the TFR stops under automatic TF (the RF switch at SILENT, the power lost), TF FAIL rolls the wings level and pulls up until ADV MODE is let go.

#in-sim[
  - The FLIR's heat is drawn from the view: the brightness, with the sky and the water cold.
  - The warm-up time, the speed band, the ride's limits, the fly-up's share and the formats' layouts are inferred.
  - #term("Not modelled"): the TFR's weather and low-emission modes' own effects; LO TF.
]
