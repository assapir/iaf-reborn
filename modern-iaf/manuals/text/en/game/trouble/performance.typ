#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Performance")#idx("Stutter")A flight is smooth when the computer draws each picture in time. This section lowers the #term("Frame time") with the graphics settings, the costly ones first. All of them are on the #scr("preferences") screen, section #scr("graphics") (@settings-graphics), which you can open during a flight from the pause menu.

=== Measure first <performance-measure>

+ Fly any mission for at least 30 seconds.
  #then[The flight measures its frame time between its 10th and its 30th second.]
+ Open #scr("preferences"), section #scr("graphics"), and point at any graphics row.
  #then[The pane shows the measured frame time on a bar, with a line at 60 frames a second (@settings-frame).]

A bar that ends before the line needs no change. A bar past the line is a flight under 60 frames a second; at the bar's end, 33 ms, it is about 30.

#note[The first flight after an update loads slowly while the game prepares its graphics once (@after-update-slow). Measure on a second flight.]

=== The quick way: the Laptop preset <performance-laptop>

#idx("Laptop preset")
+ In the row #scr("preset"), select #scr("preset_laptop").
  #then[Seven settings change at once: the picture is drawn smaller and scaled up, the far shadows, the buildings and the trees are off, and the far ground is drawn more coarsely (@settings-presets).]
+ Fly again and read the measured frame time.

#scr("preset_laptop") is made for a laptop's built-in graphics. When the flight is smooth with it, go up to #scr("preset_balanced"), which brings the buildings and trees back.

=== The slow way: one setting at a time <performance-order>

Each graphics row carries a #term("Cost chip") (@settings-cost). Lower the settings in this order, and measure after each change. After a change the pane also shows an estimate for the settings now, before you fly.

+ Look for a row whose chip reads #scr("cost_high") or #scr("cost_medium"), and pick its plain choice.
  #then[With the measured costs these are #scr("scenery") on #scr("scenery_detailed") (pick #scr("on")) and #scr("clouds") on #scr("clouds_volumetric") (pick #scr("clouds_original")).]
+ Set #scr("upscaling") to #scr("upscaling_quality"), then to #scr("upscaling_balanced").
  #then[The chip reads #scr("cost_saves") on #scr("upscaling_balanced"). The world is drawn with fewer pixels; the cockpit's text stays sharp.]
+ Switch #scr("shadow_reach") off.
+ Set #scr("scenery") to #scr("off").
+ Switch #scr("shadows") off.
+ Lower #scr("terrain_detail").

=== Upscaling <performance-upscaling>

#idx("Upscaling")#scr-text("upscaling_about")

#scr("upscaling") is the setting with the largest saving that leaves every effect on. On the measuring laptop #scr("upscaling_quality") saved about 3 ms a frame and #scr("upscaling_balanced") about 6.6 ms, of 30 ms.

=== What does not help <performance-not>

- #scr("fullscreen") and #scr("vsync") cost no drawing time; their chips read #scr("cost_none"). #scr("vsync") holds the game to the screen's own rate; it does not make a slow flight slower to draw.
- The sound and the device settings do not change the frame time.

When the flight is slow with #scr("preset_laptop") too, report it with the measured frame time and the log (@crash-page-report).
