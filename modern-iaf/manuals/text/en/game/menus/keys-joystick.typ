#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Keys")#idx("Joystick")The keyboard flies the whole jet: every command has a key, and a joystick is an addition. Two screens set them up, #scr("keys_screen") and #scr("joystick_screen"). Both open from #scr("preferences"), section #scr("devices"), with the #scr("change") button of their rows (@settings-devices). #scr("back") or #keycap("Esc") on either goes back to #scr("devices").

A change applies at once. During a flight it applies when you close the settings.

Every command with its key is listed on the key card, @keys.

=== The Keys screen <keys-joystick-keys>

#idx("Keys screen")The #scr("keys_screen") screen lists every command with its key, in five groups: #scr("group_flight"), #scr("group_weapons"), #scr("group_sensors"), #scr("group_views") and #scr("group_sim"). The tabs at the side scroll the list to a group. The line under the title reads: #scr-text("keys_sub")

#screen("devices_keys", [The #scr("keys_screen") screen.])

=== Changing a key <keys-joystick-change>

#idx("Keys, changing")
+ Select the command's row.
  #then[The row's key reads #scr("press_key")]
+ Press the new key, alone or together with one modifier key.
  #then[The row shows the new key, and a #scr("default") button.]

#keycap("Esc") in place of a key leaves the command as it was.

#screen("devices_keys_wait", [A row waiting for its new key.], width: 80%)

=== A key that another command has <keys-joystick-conflict>

#idx("Keys, conflict")When the key you press already runs another command, a line opens under the row. It names the key and the other command, and offers three choices.

#grid-table(
  (auto, 1fr),
  ([Choice], [What it does]),
  [#scr("swap")], [The two commands trade keys: this command takes the key, the other one takes this command's old key.],
  [#scr("take")], [This command takes the key. The other command is left without a key.],
  [#scr("cancel")], [Both commands stay as they were.],
)

#screen("devices_keys_conflict", [The line under the row, with its three choices.], width: 80%)

=== Back to the default keys <keys-joystick-default>

#idx("Keys, defaults")
- #scr("default") on a changed row puts that command back on its own key.
- #scr("reset_all") in the bottom bar puts every key back.

#caution[#scr("reset_all") drops every key you changed, at once and without a question. Use #scr("default") on a row to put one command back.]

=== The laptop key map <keys-joystick-laptop>

#idx("Laptop key map")The default keys use the number pad for the rudder and for looking around, and Page Up, Page Down, Home and End for a few more commands. A Mac laptop has none of these keys, so on macOS the game starts from the #term("Laptop key map"): the same table with the commands below on other keys. A Mac with a full keyboard gets it too; there #scr("default") and #scr("reset_all") go back to the laptop key map. On Linux and Windows the game starts from the default keys.

In this manual a key cap with two lines shows the default key on top and the macOS key under it.

#grid-table(
  (1fr, auto, 1fr, auto),
  ([Command], [Key], [Command], [Key]),
  [Rudder left], [#key("Rudder left")], [Rudder right], [#key("Rudder right")],
  [Weapon page full screen], [#key("Weapon page full screen")], [Extinguish engine fire], [#key("Extinguish engine fire")],
  [Look back-left], [#key("Look back-left (135 deg)")], [Look back], [#key("Look back")],
  [Look back-right], [#key("Look back-right (135 deg)")], [Look left], [#key("Look left (90 deg)")],
  [Look forward], [#key("Look forward")], [Look right], [#key("Look right (90 deg)")],
  [Look front-left], [#key("Look front-left (45 deg)")], [Look up], [#key("Look up (30 deg)")],
  [Look front-right], [#key("Look front-right (45 deg)")], [Raise the head], [#key("Raise the head")],
  [Lower the head], [#key("Lower the head")], [DMS up], [#key("DMS up (SOI to the HUD)")],
  [DMS down], [#key("DMS down (SOI to an MFD)")], [DED field up], [#key("DED field up (DCS up)")],
  [DED field down], [#key("DED field down (DCS down)")], [DED back to CNI], [#key("DED back to CNI (DCS RTN)")],
  [DED next sub-page], [#key("DED next sub-page (DCS SEQ)")], [Notebook: previous page], [#key("Checklist notebook: previous page")],
  [Notebook: next page], [#key("Checklist notebook: next page")], [], [],
)

The number pad's two zoom keys have no key on the laptop key map. The zoom's other pair works on every keyboard: #key("Zoom out (minus key)") and #key("Zoom in (equals key)").

On macOS the #scr("keys_screen") screen writes the modifier keys with the Mac's own names. More about a Mac's keyboard is in @mac-keys.

#screen("devices_keys_mac", [The #scr("keys_screen") screen with the laptop key map.], width: 80%)

=== The Joystick screen <keys-joystick-joystick>

#idx("Joystick screen")The #scr("joystick_screen") screen has three parts: #scr("joy_devices"), #scr("joy_axes") and #scr("joy_buttons"). With no joystick connected its row in the settings is greyed and reads #scr("joy_none") It comes alive when you plug one in.

#screen("devices_joystick", [The #scr("joystick_screen") screen: the device and its axes.])

#grid-table(
  (auto, 1fr),
  ([Part], [What it holds]),
  [#scr("joy_devices")], [Every connected joystick by its name. The first one is marked #scr("joy_in_use"); the others are listed only.],
  [#scr("joy_axes")], [One row for each axis of the joystick, up to six: a live bar, the axis' role, #scr("invert") and #scr("dead_zone").],
  [#scr("joy_buttons")], [The list of commands, as on the #scr("keys_screen") screen, with the joystick's button of each.],
  [#scr("reset_all")], [Puts the buttons and the axes back to their defaults.],
)

=== Setting an axis <keys-joystick-axes>

#idx("Joystick, axes")
+ Move the stick, the lever or the pedals.
  #then[The bar of the axis that you move follows it.]
+ In that row, choose the axis' role from the list.
  #then[The axis has the role. An axis that had the role before reads #scr("role_none").]
+ Move the control again and watch the bar.
  #then[The bar fills the way the jet responds: the throttle lever fully forward is a full bar.]
+ When the bar moves the wrong way, tick #scr("invert").
+ Set #scr("dead_zone") so that the bar stays still while the stick rests.

#grid-table(
  (auto, 1fr),
  ([Role], [What the axis does]),
  [#scr("role_roll")], [Rolls the jet: the stick left and right.],
  [#scr("role_pitch")], [Raises and lowers the nose: the stick back and forward.],
  [#scr("role_throttle")], [Sets the engine's power. It has no centre and no #term("dead zone").],
  [#scr("role_rudder")], [Moves the rudder: pedals, or a stick's twist.],
  [#scr("role_trim")], [Trims the roll: a rocker on the throttle.],
  [#scr("role_none")], [The axis does nothing.],
)

A role sits on one axis only. A role without an axis leaves its keys working: with #scr("role_roll") on no axis, the roll keys roll the jet while the stick pitches it.

The #term("Dead zone") goes from 0 to 50 %. Its default is 25 % on the stick and the rudder, 5 % on them with #scr("stick_response") on #scr("soft"), and 10 % on the trim rocker.

An axis is read only when its setting says so: #scr("flight_controls") on #scr("joystick") for the stick, #scr("rudder") on #scr("pedals"), #scr("throttle") on #scr("lever") (@settings-devices).

=== Joystick buttons and the hat <keys-joystick-buttons>

#idx("Joystick, buttons")#idx("Joystick, hat")
+ Under #scr("joy_buttons"), select the command's row.
  #then[The row reads #scr("press_button")]
+ Press the button on the joystick.
  #then[The row shows the button's number.]

A button that another command has opens the same three choices as a key (@keys-joystick-conflict), and #scr("default") works as on the #scr("keys_screen") screen.

#scr-text("joy_buttons_note")

#screen("devices_joystick_buttons", [The #scr("joy_buttons") part.], width: 80%)

=== Joysticks the game knows <keys-joystick-maps>

#idx("Thrustmaster T.Flight Hotas X")A joystick that the game knows by its name gets a #term("Device map"): its axes and buttons are set when you plug it in. The game has one device map.

#grid-table(
  (auto, 1fr),
  ([Thrustmaster T.Flight Hotas X], []),
  [Axes], [Axis 1 #scr-text("role_roll"), axis 2 #scr-text("role_pitch"), axis 3 #scr-text("role_throttle"), axis 4 #scr-text("role_rudder") (the stick's twist), axis 5 #scr-text("role_trim") (the rocker, with the joystick in its 5-axis mode).],
  [Buttons], [1 the gun trigger, 2 release the selected weapon, 3 next target, 4 flares, 5 chaff, 6 master mode, 7 radar mode, 8 drop the target lock, 9 landing gear, 10 flaps, 11 wheel brakes, 12 autopilot.],
  [Hat], [The view, in eight directions.],
)

Any other joystick starts with axes 1 to 5 as roll, pitch, throttle, rudder and roll trim. Set it up on the #scr("joystick_screen") screen.

=== The afterburner detent <keys-joystick-detent>

#idx("Afterburner detent")Many throttle levers have a click near the end of their travel. The setting #scr("throttle_detent") tells the game where that click is, so that the lever at its click gives full power without the afterburner, and the travel past it lights the afterburner. The #term("Afterburner detent") needs a connected joystick with the #scr("role_throttle") role on an axis.

+ Open #scr("preferences"), section #scr("devices").
+ Move the throttle lever into its click and leave it there.
+ In the row #scr("throttle_detent"), select #scr("set_at_lever").
  #then[The choice shows the lever's place in percent.]

#scr("off") makes the lever's travel even again, with the afterburner at its end.

#screen("devices_prefs_detent", [The row #scr("throttle_detent") after it is set.], width: 80%)

=== The control settings <keys-joystick-settings>

The five settings that say what flies the jet are rows of the settings' #scr("devices") section: #scr("flight_controls"), #scr("rudder"), #scr("throttle"), #scr("throttle_detent") and #scr("stick_response"). Each is described, with its values and its default, in @settings-devices.
