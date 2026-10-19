# Pilot guides

Player guides for each jet as it flies in this game with the realistic options on (Flight data, Weapon data, Real
HUD, the Physics switches). The game shows them in the Reference screen (its **PILOT GUIDE** view, docs/front-end.md
§14), and setup prints each as a PDF (`assets/converted/guides/<jet>.pdf`, `python3 -I tools/guide_pdf.py`).

Each guide leads with what the realistic options change in that jet, then one section per HUD, sight or helmet mode
the jet has (when to use it, the keys, an annotated picture, what each symbol means, a worked example), then the
flight-model numbers that change how it flies, a short take-off and landing table, the key card and the
abbreviations.

- [F-16](f16.md): the F-16C HUD (NAV, gear down, EEGS, SRM, MRM with the DLZ, STRF, CCIP), the DASH helmet, laser /
  TV / HARM weapons, the deep stall.
- [F-15](f15.md): the F-15C Baz: the TO 1F-15A-1 HUD, the DASH helmet, the APG-63, Sparrows.
- [Lavi](lavi.md): the two-seat Lavi of the game's model: its wide-angle HUD (a reconstruction), the EL/M-2035 radar.
- [Mirage](mirage.md): the Mirage IIICJ Shahak: the CSF 95 gyro gunsight, the Cyrano radar, Shafrir 2 / AIM-9D.
- [F-35I](f35i.md): our F-35I Adir (Extras → F-35I replaces): the helmet's virtual HUD, the APG-81, the weapon bays.
  It sits outside the Reference records, so the game shows it only as the PDF (`assets/converted/guides/f35i.pdf`;
  the Lavi guide points to it).
- [F-4E](f4.md): the F-4E Kurnass: the AN/ASG-26 lead-computing sight, the APQ-120, the drag chute.
- [Kurnass 2000](f42000.md): the F-4E Phantom 2000 upgrade: its HUD reconstruction, the APG-76, laser / TV / HARM.
- [Kfir](cfir.md): the Kfir C7: the Elbit HUD reconstruction, the ranging radar, DEFA guns.

The file names follow the Reference screen's record folders (`f4`, `f42000`, `cfir`).

Screenshots (`shots/<jet>/*.png`) are rendered locally from the game by setup (`tools/guide_shots.sh [jet]
[--only name,…] [--force]`, needs a display; up-to-date pictures are kept) into `assets/converted/guides/shots/`, from each guide's `<jet>.shots.json` (its
schema in the header of `tests/godot/_guide_shots.gd`). A "hud" crop takes `crop_w` (the box's width as a fraction of
the frame; smaller zooms in) and `crop_dy` (the box moved down by that fraction of the frame's height; negative moves
it up): the F-4E and Mirage gunsight shots use them to centre and enlarge a reticle that sits high on the glass.
A "compass" crop frames the panel's compass dial (`game/cockpit/compass.gd`) with the same `crop_w` / `crop_dy`: the
Kfir, F-4E and Mirage guides show it with Better cockpit on. A
`text:` callout's arrow ends on the box the HUD draws the text in (`hud.gd prim_text_box`). Readings that move by a few feet from one render to the next (the start height settles differently) take a pattern, such as `text:^[89]\d\d$` for an altitude near 900 ft, and the guide gives them as "about". A shot's `annotations` draw numbered yellow callouts with
arrows onto the picture; the guide gives their legend as a numbered list right under the picture (same count:
`tools/guide_pdf.py` warns otherwise). They show the original game's art, so they stay
local (git-ignored). The guides use the Markdown subset in `game/menu/guide_md.gd` (the PDF tool reads the same).
