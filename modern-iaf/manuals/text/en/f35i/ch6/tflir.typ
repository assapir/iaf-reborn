#import "src.typ": *

The #jet.short has a targeting sensor built in under its nose: an infrared camera with a laser. The displays call it TFLIR. The jet needs no pod for it. The real format shows the camera's picture and the laser's state#ife; its details are open.

=== The format <tflir-format>

The TFLIR format of the #term("PCD") shows:

- the camera's picture in a square. Before the camera runs the square reads NO VIDEO;
- a cross fixed at the picture's centre: the line of sight, and the place of the laser's spot;
- top left, Z and the zoom step; top right, WIDE or SPOT, the field of view;
- bottom left, LSR SAFE, or LSR ARM in yellow while the laser fires;
- bottom right, the distance to the point under the cross.

=== To use it <tflir-use>

+ *Press* #key("FLIR page"). #sym.arrow.r *The TFLIR format comes to a portal and the camera's picture runs.*
+ *Move the line of sight* with #key("Slew EO sensor / radar cursor up"), #key("Slew EO sensor / radar cursor down"), #key("Slew EO sensor / radar cursor left") and #key("Slew EO sensor / radar cursor right"). #sym.arrow.r *The picture moves under the cross. With the keys free the camera stays on the same ground while the jet moves.*
+ *Zoom* with #key("Zoom in (equals key)") and #key("Zoom out (minus key)"). #sym.arrow.r *Z shows the step.*
+ *Fire the laser* with #key("Laser designator"). #sym.arrow.r *The legend reads LSR ARM.* The point under the cross is now the aim of a bomb in VIS (@ag-weapons). The same key stops the laser.

#in-sim[The format has no legend to click. A control for WIDE and SPOT on this format is #nis.]
