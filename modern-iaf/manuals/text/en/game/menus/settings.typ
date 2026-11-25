#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Settings")The #scr("preferences") screen holds every option of the game. Open it from the #term("Hangar")'s top bar, or during a flight from the pause menu (@time-pause). A change applies at once and is saved at once; the screen has no save button.

#screen("prefs_graphics", [The #scr("preferences") screen on #scr("graphics").])

=== The parts of the screen <settings-screen>

#grid-table(
  (auto, 1fr),
  ([Part], [What it does]),
  [The search box], [Finds a setting by a word (@settings-search).],
  [The sections], [#scr("graphics"), #scr("language"), #scr("updates"), #scr("sound") and #scr("devices"), each with the number of its settings. Selecting one shows its settings.],
  [The rows], [One setting a row: its name and its control. A control is a row of choices, a switch (#scr("off") or #scr("on")), or a slider from 0 to 100 % in steps of 5 %. A graphics row ends with its #term("Cost chip") (@settings-cost).],
  [The pane], [Tells about the setting under the pointer or the focus: its name and what it does. For a graphics setting it also shows a picture (@settings-pictures) and the #term("Frame time") measured on this computer (@settings-frame). #scr("updates") has no pane: its setting is explained in @settings-updates.],
  [#scr("defaults")], [Puts the settings of the section shown back to their defaults (@settings-defaults).],
  [#scr("export_settings"), #scr("import_settings")], [Write the settings to a file and read them from one (@settings-file).],
  [#scr("back_hangar")], [Goes back to the Hangar. #keycap("Esc") does the same.],
)

A setting that cannot be used on this computer is greyed, and a line under its name says why.

=== Graphics <settings-graphics>

#idx("Graphics settings")
#settings-table(
  ("preset", "antialiasing", "upscaling", "shadows", "shadow_reach", "terrain_detail", "clouds", "scenery", "fullscreen", "vsync"),
  notes: (
    antialiasing: [On a Mac the fourth choice is named MetalFX.],
    shadow_reach: [The control is a switch: #scr("on") is the far reach.],
    clouds: [#scr("clouds_volumetric") is greyed on a computer whose graphics cannot draw it.],
    scenery: [Greyed, with the reason under its name, while setup's optional step is left out or not built (@setup-leave-out).],
  ),
)

#grid-table(
  (auto, 1fr, auto),
  ([Setting], [Values], [Default]),
  [#scr("preset")], [#scr("preset_laptop"), #scr("preset_balanced"), #scr("preset_high"), #scr("preset_everything"). #scr("preset_custom") lights by itself; it cannot be picked.], [#scr("preset_high")],
  [#scr("antialiasing")], [#scr("antialiasing_msaa4"), #scr("antialiasing_msaa4_fxaa"), #scr("antialiasing_taa"), *FSR 2*], [#scr("antialiasing_msaa4")],
  [#scr("upscaling")], [#scr("upscaling_off"), #scr("upscaling_quality"), #scr("upscaling_balanced")], [#scr("upscaling_off")],
  [#scr("shadows")], [#scr("off"), #scr("on")], [#scr("on")],
  [#scr("shadow_reach")], [#scr("off"), #scr("on")], [#scr("on")],
  [#scr("terrain_detail")], [0 to 100 %], [100 %],
  [#scr("clouds")], [#scr("clouds_original"), #scr("clouds_volumetric")], [#scr("clouds_original")],
  [#scr("scenery")], [#scr("off"), #scr("on"), #scr("scenery_detailed")], [#scr("on"); #scr("off") without setup's step],
  [#scr("fullscreen")], [#scr("off"), #scr("on")], [#scr("off")],
  [#scr("vsync")], [#scr("off"), #scr("on")], [#scr("on")],
)

=== The presets <settings-presets>

#idx("Presets")A #term("Preset") sets seven graphics settings in one click. #scr("fullscreen") and #scr("vsync") are yours alone: no preset changes them.

#grid-table(
  (1.3fr, 1fr, 1fr, 1fr, 1.2fr),
  ([Setting], [#scr("preset_laptop")], [#scr("preset_balanced")], [#scr("preset_high")], [#scr("preset_everything")]),
  [#scr("antialiasing")], [#scr-text("antialiasing_msaa4")], [#scr-text("antialiasing_msaa4")], [#scr-text("antialiasing_msaa4")], [#scr-text("antialiasing_msaa4_fxaa")],
  [#scr("upscaling")], [#scr-text("upscaling_balanced")], [#scr-text("upscaling_quality")], [#scr-text("upscaling_off")], [#scr-text("upscaling_off")],
  [#scr("shadows")], [#scr-text("on")], [#scr-text("on")], [#scr-text("on")], [#scr-text("on")],
  [#scr("shadow_reach")], [#scr-text("off")], [#scr-text("off")], [#scr-text("on")], [#scr-text("on")],
  [#scr("terrain_detail")], [50 %], [75 %], [100 %], [100 %],
  [#scr("clouds")], [#scr-text("clouds_original")], [#scr-text("clouds_original")], [#scr-text("clouds_original")], [#scr-text("clouds_volumetric")],
  [#scr("scenery")], [#scr-text("off")], [#scr-text("on")], [#scr-text("on")], [#scr-text("scenery_detailed")],
)

A choice that this computer cannot pick stays at its default: #scr("clouds_volumetric") where the graphics cannot draw it, #scr("scenery") without setup's step.

When you change one of the seven settings yourself, the row reads #scr("preset_custom").

=== The cost chips <settings-cost>

#idx("Cost chips")Each graphics row carries a chip. It names the frame time that the row's choice adds over the row's plain choice (#scr("off"), #scr("upscaling_off"), #scr("antialiasing_msaa4"), #scr("clouds_original"), the lowest terrain detail).

#grid-table(
  (auto, 1fr),
  ([Chip], [The choice's cost]),
  [#scr("cost_saves")], [The choice lowers the frame time.],
  [#scr("cost_none")], [Under 0.3 ms.],
  [#scr("cost_low")], [Under 1.5 ms.],
  [#scr("cost_medium")], [Under 4 ms.],
  [#scr("cost_high")], [4 ms or more. The chip is amber.],
  [A chip that starts with "under" and a time], [No cost was found: the difference is smaller than the measurement can tell. The cost is at most the time named.],
)

The costs were measured once, on a laptop with Intel Iris Xe built-in graphics in a 1920 × 1080 window. They rank the settings; your computer's own times differ. With that measurement the chips read:

#grid-table(
  (auto, 1fr),
  ([Setting], [The chip of each choice]),
  [#scr("antialiasing")], [#scr-text("antialiasing_msaa4"): #scr-text("cost_none"). #scr-text("antialiasing_msaa4_fxaa"): under 3.3 ms. #scr-text("antialiasing_taa"): #scr-text("cost_saves"). FSR 2: under 3.3 ms.],
  [#scr("upscaling")], [#scr-text("upscaling_off"): #scr-text("cost_none"). #scr-text("upscaling_quality"): under 3.3 ms. #scr-text("upscaling_balanced"): #scr-text("cost_saves").],
  [#scr("shadows")], [#scr-text("off"): #scr-text("cost_none"). #scr-text("on"): under 3.3 ms.],
  [#scr("shadow_reach")], [#scr-text("off"): #scr-text("cost_none"). #scr-text("on"): under 3.3 ms.],
  [#scr("terrain_detail")], [50 %: #scr-text("cost_none"). 75 % and 100 %: under 3.3 ms.],
  [#scr("clouds")], [#scr-text("clouds_original"): #scr-text("cost_none"). #scr-text("clouds_volumetric"): #scr-text("cost_medium").],
  [#scr("scenery")], [#scr-text("off"): #scr-text("cost_none"). #scr-text("on"): under 3.3 ms. #scr-text("scenery_detailed"): #scr-text("cost_high").],
  [#scr("fullscreen"), #scr("vsync")], [#scr-text("cost_none"): they cost no drawing time.],
)

=== The Off and On pictures <settings-pictures>

#idx("Settings, pictures")For seven graphics settings the pane shows one picture of the same view from the cockpit, split down the middle: the left half is drawn with the setting's lower choice, the right half with its higher one. The settings are #scr("antialiasing"), #scr("upscaling"), #scr("shadows"), #scr("shadow_reach"), #scr("terrain_detail"), #scr("clouds") and #scr("scenery"). #scr("fullscreen"), #scr("vsync") and the other sections have no picture.

#screen("prefs_about", [The pane on #scr("scenery"): what it does, its picture and the measured frame time.])

=== The measured frame time <settings-frame>

#idx("Frame time")Every flight measures its own frame time between its 10th and its 30th second. The pane shows the last measurement under #scr("frame_measured_none_head"):

- The time in milliseconds, and the frames a second that it gives.
- A bar up to 33 ms, with a line at 60 frames a second (16.7 ms). A bar that ends before the line is a smooth flight.
- The window's size at the measurement.
- When the graphics settings now differ from those of the measurement: an estimate for the settings now, worked out from the measured costs.

Before the first flight the pane reads: #scr-text("frame_none")

=== Language <settings-language>

#settings-table(("language",))

#grid-table(
  (auto, 1fr, auto),
  ([Setting], [Values], [Default]),
  [#scr("language")], [#scr("language_en"), #scr("language_he")], [#scr("language_en"), or the language picked in setup],
)

What the language changes is in @language.

=== Updates <settings-updates>

#idx("Updates")
#settings-table(("update_mode",))

#grid-table(
  (auto, 1fr, auto),
  ([Setting], [Values], [Default]),
  [#scr("update_mode")], [#scr("update_mode_ask"), #scr("update_mode_always"), #scr("update_mode_never")], [#scr("update_mode_ask")],
)

What the game looks for on start, and what #strong(upd("update")) does, is in @setup-updates.

=== Sound <settings-sound>

#idx("Sound settings")#idx("Volume")
#settings-table(("engine_volume", "sfx_volume", "speech_volume", "mute"))

#grid-table(
  (auto, 1fr, auto),
  ([Setting], [Values], [Default]),
  [#scr("engine_volume")], [0 to 100 %], [80 %],
  [#scr("sfx_volume")], [0 to 100 %], [100 %],
  [#scr("speech_volume")], [0 to 100 %], [100 %],
  [#scr("mute")], [#scr("off"), #scr("on")], [#scr("off")],
)

During a flight #key("Mute / unmute sound") switches #scr("mute").

#screen("prefs_sound", [The #scr("sound") section.], width: 80%)

=== Devices <settings-devices>

#idx("Devices settings")
#settings-table(
  ("flight_controls", "rudder", "throttle", "throttle_detent", "stick_response", "keys_screen", "joystick_screen"),
  notes: (
    throttle_detent: [The steps are in @keys-joystick-detent.],
    keys_screen: [#scr("change") opens the #scr("keys_screen") screen (@keys-joystick-keys).],
    joystick_screen: [#scr("change") opens the #scr("joystick_screen") screen (@keys-joystick-joystick).],
  ),
)

#grid-table(
  (auto, 1fr, auto),
  ([Setting], [Values], [Default]),
  [#scr("flight_controls")], [#scr("keyboard"), #scr("joystick")], [#scr("joystick")],
  [#scr("rudder")], [#scr("keyboard"), #scr("pedals")], [#scr("keyboard")],
  [#scr("throttle")], [#scr("keyboard"), #scr("lever")], [#scr("keyboard")],
  [#scr("throttle_detent")], [#scr("off"), #scr("set_at_lever"). Once set, the second choice shows the lever's place in percent.], [#scr("off")],
  [#scr("stick_response")], [#scr("linear"), #scr("soft")], [#scr("linear")],
)

With no joystick connected, the first three rows show #scr("keyboard") and their other choice is greyed; #scr("throttle_detent") and #scr("joystick_screen") are greyed and read #scr("joy_none") Your stored choices come back when a joystick is plugged in.

#screen("prefs_devices", [The #scr("devices") section.], width: 80%)

=== Searching for a setting <settings-search>

#idx("Settings, search")
+ Select the search box. Its hint reads: #scr-text("search_hint")
+ Type one or more words, in English or in Hebrew.
  #then[The screen lists the settings of every section whose name, description or choices hold every word typed, under their sections' names. Each section's number is the count of its matches.]
+ Change the setting in the list.
+ Clear the box to see the sections again.

When no setting holds the words, the screen reads: #scr-text("search_none")

#screen("prefs_search", [A search.], width: 80%)

=== Back to the defaults <settings-defaults>

#idx("Settings, defaults")
+ Select the section whose settings you want to put back, or search for the settings.
+ Select #scr("defaults").
  #then[The rows of that section, or the search's matches, go back to their defaults. The language stays as it is.]

The keys and the joystick have their own #scr("reset_all") on their screens (@keys-joystick).

=== The settings file <settings-file>

#idx("Settings, export and import")
+ To write your settings to a file, select #scr("export_settings") and choose a place and a name in the system's file dialog.
  #then[The game writes a `.cfg` file with the settings as they are.]
+ To read settings from such a file, select #scr("import_settings") and choose the file.
  #then[The settings are taken over, applied and saved at once.]

The active pilot and the picked jet stay this computer's own. The two buttons are on the screen opened from the Hangar; the screen opened from the pause menu has #scr("defaults") and #scr("back") only.
