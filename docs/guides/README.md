# Pilot guides

Player guides for each jet as it flies in this game with the realistic options on (Flight data, Weapon data, Real
HUD, the Physics switches). The game shows them in the Reference screen (its **PILOT GUIDE** view, docs/front-end.md
§14), and setup prints each as a PDF (`assets/converted/guides/<jet>.pdf`, `python3 -I tools/guide_pdf.py`).

- [F-16](f16.md): settings, numbers, take-off and landing, the Real HUD, radar, MFDs, self-protection, every
  weapon, and a key card.
- [F-15](f15.md): the F-15C Baz: settings, numbers, take-off and landing, the Real HUD (TO 1F-15A-1), radar,
  MFDs, self-protection, every store it carries, and a key card.

Screenshots (`shots/<jet>/*.png`) are rendered locally from the game by setup (`tools/guide_shots.sh [jet]
[--only name,…]`, needs a display) into `assets/converted/guides/shots/`, from each guide's `<jet>.shots.json` (its
schema in the header of `tests/godot/_guide_shots.gd`). They show the original game's art, so they are never
committed. The guides use the Markdown subset in `game/menu/guide_md.gd` (the PDF tool reads the same).
