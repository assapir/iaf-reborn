#import "/modern-iaf/manuals/layout/manual.typ": *

=== Starting <start-game-start>

#idx("Starting the game")
+ Open a terminal in the game's folder.
+ Run `./start-modern-iaf`. On Windows run `.\start-modern-iaf.ps1`.
  #then[The script builds what changed in the game's program, then the game's window opens on the #term("Hangar") (@main-menu).]

While the game's data is missing, the same script opens the #term("setup wizard") instead (@setup). The wizard's last page starts the game with #stp("start_game").

=== The first start <start-game-first>

#idx("First start")On the first start the game has no pilot yet, so it opens the screen #scr("first_pilot") in the Hangar's place.

+ Type your name in #scr("pilot_name").
+ Type a nickname in #scr("pilot_nickname"), if you want one.
+ Select #scr("save").
  #then[The Hangar opens. The top bar shows your nickname, or your name when you gave no nickname.]

The pilot, its picture and its log are described in @pilots.

#screen("pilot_first", [The first start: #scr("first_pilot").])

=== Where the game keeps your files <start-game-files>

#idx("Settings file")#idx("User folder")The game keeps what you make in one folder of your user account, named "Modern IAF":

#grid-table(
  (auto, 1fr),
  ([System], [Folder]),
  [Linux], [`~/.local/share/godot/app_userdata/Modern IAF/`],
  [macOS], [`~/Library/Application Support/Godot/app_userdata/Modern IAF/`],
  [Windows], [`%APPDATA%\Godot\app_userdata\Modern IAF\`],
)

#grid-table(
  (auto, 1fr),
  ([File or folder], [What it holds]),
  [`settings.cfg`], [The settings, the changed keys and joystick buttons, the picked jet and the active pilot.],
  [`devices.json`], [The joystick's axes, where you changed them.],
  [`modern-iaf.sqlite`], [The pilots, every flight with its #term("debrief"), and the pilots' loadouts.],
  [`pictures/`], [The pilots' pictures.],
  [`flights/`], [The flight recordings, one file a flight; the newest 10 are kept.],
  [`logs/`], [The game's logs; the newest 30 are kept (@crash-page).],
)

The data that setup builds, and its downloads, are in the folder `assets` inside the game's folder.

=== Quitting <start-game-quit>

#idx("Quit")
+ On the Hangar, select #scr("quit") or press #keycap("Esc").
  #then[The game asks #scr("quit_q"), with #scr("cancel") picked.]
+ Select #scr("quit").

From a flight, press #keycap("Esc") for the pause menu, then select #scr("quit_desktop") and confirm; #scr("end_flight") ends the flight into its debrief instead (@time-pause).

The window's close button and the system's own quit key close the game at once, from any screen and from a flight.
