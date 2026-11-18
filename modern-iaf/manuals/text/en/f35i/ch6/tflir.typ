#import "src.typ": *

The #jet.short has a targeting sensor built in under its nose: an infrared camera with a laser. The displays call it TFLIR. The real format works the infrared camera, which identifies and designates targets#ife; its details are open.

=== The format <tflir-format>

The TFLIR format of the #term("PCD") shows:

- the camera's picture in a square. Before the camera runs the square reads NO VIDEO;
- a cross fixed at the picture's centre: the line of sight, and the place of the laser's spot;
- top left, Z and the zoom step; top right, WIDE or SPOT, the field of view;
- bottom left, LSR SAFE, or LSR ARM in yellow while the laser fires;
- bottom right, the distance to the point under the cross.

#display("tflir", [The TFLIR at zoom 4 over the range with the laser firing: the cross on the ground, its distance at the lower right.], width: 60%)

=== To use it <tflir-use>

+ *Press* #key("FLIR page"). #sym.arrow.r *The TFLIR format comes to a portal and the camera's picture runs.* With TFLIR already on a portal, as when the display starts, its picture runs. A click on the picture, or TFLIR picked on a portal (@pcd-choose), starts it too. From then on the cursor keys move the camera, not the radar's cursor.
+ *Move the line of sight* with #key("Slew EO sensor / radar cursor up"), #key("Slew EO sensor / radar cursor down"), #key("Slew EO sensor / radar cursor left") and #key("Slew EO sensor / radar cursor right"). #sym.arrow.r *The picture moves under the cross. With the keys free the camera stays on the same ground while the jet moves.*
+ *Zoom* with #key("Zoom in (equals key)") and #key("Zoom out (minus key)"), or ZOOM IN and ZOOM OUT on the portal's control page (@pcd-cntl). #sym.arrow.r *Z shows the step.*
+ *Change the field of view* with WIDE or SPOT on the control page. #sym.arrow.r *The legend at the top right changes.*
+ *Fire the laser* with #key("Laser designator"). #sym.arrow.r *The legend reads LSR ARM.* The point under the cross is now the aim of a bomb in VIS (@ag-weapons). The same key stops the laser.

#in-sim[The format's own face has no legend to click; its controls are on its control page (@pcd-cntl).]
