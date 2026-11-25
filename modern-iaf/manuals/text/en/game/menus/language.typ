#import "/modern-iaf/manuals/layout/manual.typ": *

#idx("Language")#idx("Hebrew")#idx("English")The game has two languages, #scr("language_en") and Hebrew (#scr("language_he")). The #term("setup wizard") asks for the language on its first page, and the game starts in it.

=== Switching the language <language-switch>

+ On the #term("Hangar"), select #scr("preferences").
+ Select the section #scr("language").
+ In the row #scr("language"), select #scr("language_en") or #scr("language_he").
  #then[Every screen changes at once, the one you are on included.]

The same row is in the settings that the pause menu opens, so you can switch during a flight.

#screen("prefs_language", [The #scr("language") section.], width: 80%)

=== What changes <language-changes>

#grid-table(
  (auto, 1fr),
  ([Thing], [In Hebrew]),
  [The screens], [Every screen of the front end, the pause menu, the loading screen, the #term("debrief") and the setup wizard is in Hebrew, and is mirrored: what stands at the left in English stands at the right.],
  [The radio], [The #term("tower"), the #term("AWACS"), your wingmen and your own pilot speak Hebrew, and their lines are written in Hebrew over the flight. Your own pilot speaks in the voice picked on the #scr("pilot") screen (@pilots-edit). The other voices are men's and women's; who speaks which part changes from mission to mission, and each keeps one voice for the whole flight.],
  [The #term("notebook")], [The notebook's pages and its checklist are in Hebrew.],
  [Key names, numbers and clock times], [They read left to right, as in English.],
  [The licence lines in #scr("credits")], [They stay in English.],
)

=== What stays English <language-english>

- *The warning voice.* The jet's own warning voice speaks English in both languages.
- *The cockpit.* The labels of the switches and the displays are the real jets', in English.
- *The manuals.* The four manuals are PDF files in English (@manuals).
