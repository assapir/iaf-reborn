#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Hangar")#idx("Main menu")The #term("Hangar") is the game's first screen and its main menu. Every start opens it with the jet you picked last. From it you reach every other screen.

#screen("hangar", [The Hangar: the jets, the picked jet and its card.], numbered: true)

=== What the Hangar holds <main-menu-entries>

#screen-table(
  "hangar",
  (auto, 1fr),
  ([No.], [Entry], [What it does]),
  ("CrumbOn", [#scr("hangar")], [The first breadcrumb on every screen. It opens the Hangar.]),
  ("Settings", [#scr("preferences")], [Opens the settings: graphics, language, sound and devices (@settings).]),
  ("PilotBlock", [The pilot], [Your nickname, your name and your picture, as one button. It opens the #scr("pilot") screen, and from there the #scr("pilot_log") (@pilots).]),
  ("Jets", [#scr("aircraft")], [The jets. Selecting one picks it for every later screen (@hangar). The jets that come in a later version are greyed.]),
  ("Turntable", [The jet], [The picked jet, with the stores of its #term("loadout"). You can look at it from any side (@main-menu-jet).]),
  ("JetCard", [The card], [The picked jet's #scr("squadron_l"), #scr("base_l") and #scr("tail_number"); then #scr("training"): how many of the jet's lessons are passed, and the last flight on the jet with its result.]),
  ("Fly", [#scr("fly")], [Opens the #scr("missions") screen for the picked jet: Training and the other sections (@mission-list). It is picked when the Hangar opens, so #keycap("Enter") goes straight on.]),
  ("credits", [#scr("credits")], [Opens the list of the game's sources and their licences. The arrow keys scroll it. The same list is in @attributions.]),
  ("manuals", [#scr("manuals")], [Opens the list of the four manuals (@manuals-screen).]),
  ("quit", [#scr("quit")], [Asks #scr("quit_q"), then closes the game (@start-game-quit).]),
)

When the game's data is not built, the card says so in place of the training's progress, names a setup command (use the setup entry instead, @setup-start), and #scr("fly") is greyed (@after-update-no-missions).

=== Looking at the jet <main-menu-jet>

#idx("Hangar, the jet's view")
#grid-table(
  (auto, 1fr),
  ([Input], [What it does]),
  [Drag with the mouse], [Sideways turns the jet all the way round. Up and down lower and raise your eye.],
  [Mouse wheel, or a two-finger scroll or pinch], [Zooms in and out.],
  [Double click], [Goes back to the start view.],
  [A gamepad's right stick and triggers], [The stick turns the view; the right trigger zooms in, the left one out. A click of the stick goes back to the start view.],
  [With #keycap("Tab") on the jet: the arrow keys, #keycap("+") and #keycap("−"), #keycap("0") or #keycap("Home")], [Turn the view, zoom, and go back to the start view.],
)

The view stays as you left it when you pick another jet.

=== Moving between screens <main-menu-moving>

#idx("Back")#idx("Breadcrumbs")
- *The mouse.* Click a button or a row.
- *The keyboard.* The arrow keys and #keycap("Tab") move the focus. #keycap("Enter") selects the control under the focus.
- *Back.* #keycap("Esc") goes one screen back. Each screen's bottom bar has a #scr("back") button that does the same. On the Hangar, #keycap("Esc") asks #scr("quit_q") with #scr("cancel") picked.
- *The breadcrumbs.* The top bar shows the way to the screen you are on: #scr("hangar"), the jet, the section, the mission. Selecting one of them opens that screen. Your picks are kept.

After a flight the game comes back to the front end by itself and shows the flight's #term("debrief") (@debrief).
