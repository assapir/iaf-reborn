# Pilot guides

Player guides for each jet as it flies in this game with the realistic options on (Flight data, Weapon data, Real
HUD, the Physics switches). The game shows them in the Reference screen (its **PILOT GUIDE** view, docs/front-end.md
§14), and setup prints each as a PDF (`assets/converted/guides/<jet>.pdf`, `python3 -I tools/guide_pdf.py`).

- [F-16](f16.md): settings, numbers, take-off and landing, the Real HUD, radar, MFDs, self-protection, every
  weapon, and a key card.
- [F-15](f15.md): the F-15C Baz: settings, numbers, take-off and landing, the Real HUD (TO 1F-15A-1), radar,
  MFDs, self-protection, every store it carries, and a key card.
- [Lavi](lavi.md): the two-seat Lavi of the game's model, on the design figures: the F-16-style Real HUD
  (a reconstruction), the EL/M-2035 radar, three MFDs, built-in ECM, every store it carries, and a key card.
- [Mirage](mirage.md): the Mirage IIICJ Shahak: no HUD but the CSF 95 gunsight, the Cyrano radar, one display,
  Shafrir 2 / AIM-9D, bombs and rockets, and the fast no-flap approach.
- [F-35I](f35i.md): our F-35I Adir (Extras → F-35I replaces): the helmet's virtual HUD, the APG-81, the panoramic
  display, the weapon bays, and a key card. It has no Reference record, so the game shows it only as the PDF
  (`assets/converted/guides/f35i.pdf`; the Lavi guide points to it).
- [F-4E](f4.md): the F-4E Kurnass: the AN/ASG-26 sight (no HUD), the APQ-120, AIM-9D / Shafrir 2 / AIM-7B /
  Shrike, the drag chute.
- [Kurnass 2000](f42000.md): the F-4E Phantom 2000 upgrade: the F-16-style HUD reconstruction, the APG-76, two MFDs,
  laser / TV / HARM weapons.
- [Kfir](cfir.md): the Kfir C7: the Elbit HUD reconstruction, the ranging radar, DEFA guns, IR missiles and bombs.

The file names follow the Reference screen's record folders (`f4`, `f42000`, `cfir`), not the cockpit folders.

Screenshots (`shots/<jet>/*.png`) are rendered locally from the game by setup (`tools/guide_shots.sh [jet]
[--only name,…]`, needs a display) into `assets/converted/guides/shots/`, from each guide's `<jet>.shots.json` (its
schema in the header of `tests/godot/_guide_shots.gd`). They show the original game's art, so they are never
committed. The guides use the Markdown subset in `game/menu/guide_md.gd` (the PDF tool reads the same).
