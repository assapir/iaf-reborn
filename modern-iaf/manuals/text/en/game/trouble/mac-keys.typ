#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Mac keyboard")#idx("macOS, keys")A Mac's keyboard names its modifier keys differently, a Mac laptop lacks some keys, and macOS keeps a few keys for itself. This section says what the game does about each.

=== How this manual shows a Mac's key <mac-keys-caps>

Where a command's key differs on a Mac, its key cap has two lines: the default key on top and the Mac's key under it, smaller. A cap with one line is the same key on every computer. The key card (@keys) shows every command this way.

=== The modifier keys <mac-keys-modifiers>

#idx("Cmd key")#idx("Option key")
#grid-table(
  (auto, 1fr),
  ([Key in the key table], [On a Mac]),
  [Ctrl], [Press Cmd. The game reads Cmd as Ctrl. The Ctrl key itself works too. The #scr("keys_screen") screen writes it as ⌘.],
  [Alt], [Press Option. The #scr("keys_screen") screen writes it as Option.],
  [Shift], [The same key.],
)

The game reads a key by its place on the keyboard. The characters that Option types in other programs change nothing.

=== The laptop key map <mac-keys-laptop>

On macOS the game starts from the #term("Laptop key map"), which uses only the keys of a Mac laptop: the rudder is on #key("Rudder left") and #key("Rudder right"), and the looks to the sides are on Option with the digits 1 to 9. The whole list is in @keys-joystick-laptop. On a Mac with a number pad you can put any command back on it on the #scr("keys_screen") screen (@keys-joystick-change).

=== Keys that macOS keeps <mac-keys-system>

#idx("macOS, system keys")macOS takes some key combinations before the game sees them. The rows below follow macOS's own default shortcuts. They are inferred from those defaults and have not been tried in the game on a Mac yet.

#caution[Cmd with Q is the macOS quit shortcut. Expect it to close the game at once, without a question, in the middle of a flight too.]

#grid-table(
  (1fr, 1.1fr, 1.3fr),
  ([Command], [What happens on a Mac], [What to do]),
  [Leave mission: #key("Leave mission")], [Cmd with Q is macOS's own quit: it closes the game at once. The #scr("keys_screen") screen shows this key with Ctrl.], [Hold the Ctrl key itself, as the cap shows. Or press #keycap("Esc") and select #scr("end_flight").],
  [Mute: #key("Mute / unmute sound")], [Cmd with M is macOS's own minimise: the window goes to the Dock. The #scr("keys_screen") screen shows this key with Ctrl.], [Hold the Ctrl key itself. Or switch #scr("mute") in the settings (@settings-sound).],
  [The cursor's slew: #key("Slew EO sensor / radar cursor left") and its three neighbours], [The Ctrl key itself with an arrow key changes the macOS desktop.], [Hold Cmd, as the cap shows.],
)

=== Keys that a Mac laptop lacks <mac-keys-missing>

#idx("Fn key")A Mac laptop's keyboard has no Home, End, Page Up, Page Down, forward Delete or Insert key, and macOS keeps F11 for Show Desktop. No default key of the laptop key map is one of these: every command of the #scr("keys_screen") screen has a key on a Mac laptop (@keys-joystick-laptop). Five of the missing keys are typed with the Fn key, for a command you put on one yourself.

#grid-table(
  (auto, 1fr),
  ([Key], [On a Mac laptop]),
  [Home], [Fn with the left arrow],
  [End], [Fn with the right arrow],
  [Page Up], [Fn with the up arrow],
  [Page Down], [Fn with the down arrow],
  [Delete], [Fn with Backspace],
  [Insert], [No key.],
)

By macOS's default the top row's keys set the brightness and the volume. Hold Fn with them for F1 to F12, or set macOS to use them as standard function keys. This too follows macOS's defaults and has not been tried in the game.
