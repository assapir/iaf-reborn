#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Manuals")The game has four manuals. This one, the game manual, describes the game around the jets. Each jet has a flight manual of its own, which describes that jet completely: its systems, its procedures, its limits and its weapons.

#grid-table(
  (auto, 1fr),
  ([Manual], [What it covers]),
  [Modern IAF, game manual], [Setup, the menus, the settings, flying a mission, the lessons and how they are scored, the air bases, the #term("tower") and the radio.],
  [#other-manual("f16i")], [The F-16I #scr-text("sufa").],
  [#other-manual("f16d")], [The F-16D #scr-text("barak").],
  [#other-manual("f35i")], [The F-35I #scr-text("adir").],
)

Where this manual refers to a jet's procedure, it links to the section of each jet's manual. A link opens the other manual's file, so keep the four PDF files in one folder.

=== The Manuals screen <manuals-screen>

#idx("Manuals screen")The game opens the manuals itself.

+ On the #term("Hangar"), select #scr("manuals") at the foot of the screen.
  #then[The #scr("manuals") screen lists the three flight manuals and the game manual. Its line reads: #scr-text("manuals_sub")]
+ Select a manual.
  #then[The manual opens in the system's PDF viewer.]
+ Select #scr("back") or press #keycap("Esc") to go back to the Hangar.

A manual whose file is missing is greyed. The manuals are in English in both of the game's languages (@language).
