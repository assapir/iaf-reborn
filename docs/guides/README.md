# Pilot guides

Player guides for each jet as it flies in this game with the realistic options on (Flight data, Weapon data, Real
HUD, World scale, the Physics switches). The game shows them in the Reference screen's **PILOT GUIDE** view
(docs/front-end.md §14). Setup prints each one as a PDF (`assets/converted/guides/<jet>.pdf`).

## Section order

Every guide follows the same order, for the sections its jet has:

1. What's different in this jet: the 1998 game against the realistic options, the original HUD's picture, the voice
   and HUD warnings.
2. Settings: the Preferences rows to set.
3. The HUD or sight in flight (NAV): the instruments you fly by and how to reach the steerpoint.
4. Flying the jet: the flight-model numbers, how it handles, the Physics switches that change it, the take-off and
   landing numbers.
5. Radar and self-protection (the F-35I: the panoramic display and the bays): the radar keys, chaff, flares, ECM,
   the AWACS calls and the flight reports.
6. The helmet or look-aside display, where the jet has one (DASH, the F-35I's head set).
7. The weapons: IR missiles, radar missiles, the A-A gun, the A-G gun, bombs and rockets, then laser / TV / HARM or
   Shrike.
8. Landing: the gear-down HUD (the HUD jets).
9. Better cockpit: everything Extras → Better cockpit changes in that jet.
10. Key card and abbreviations.

Each mode section gives when to use it, the keys, an annotated picture with its legend, and a worked example from
the shot's own values.

## The guides

- [F-16](f16.md): the F-16C HUD (NAV, gear down, EEGS, SRM, MRM with the DLZ, STRF, CCIP), the DASH helmet, laser /
  TV / HARM weapons, the deep stall.
- [F-15](f15.md): the F-15C Baz: the TO 1F-15A-1 HUD, the DASH helmet, the APG-63, Sparrows.
- [Lavi](lavi.md): the two-seat Lavi of the game's model: its wide-angle HUD (a reconstruction), the EL/M-2035 radar.
- [Mirage](mirage.md): the Mirage IIICJ Shahak: the CSF 95 gyro gunsight, the Cyrano radar, Shafrir 2 / AIM-9D.
- [F-35I](f35i.md): our F-35I Adir (Extras → F-35I replaces): the helmet's virtual HUD, the APG-81, the weapon bays,
  the built-in EOTS. It sits outside the Reference records, so the game shows it only as the PDF (the Lavi guide
  points to it).
- [F-4E](f4.md): the F-4E Kurnass: the AN/ASG-26 lead-computing sight, the APQ-120, the drag chute.
- [Kurnass 2000](f42000.md): the F-4E Phantom 2000 upgrade: its HUD reconstruction, the APG-76, laser / TV / HARM.
- [Kfir](cfir.md): the Kfir C7: the Elbit HUD reconstruction, the ranging radar, DEFA guns.
- [MiG-23ML](mig23.md): flown from the Mission Creator: the АСП-17МЛ sight (a reconstruction), the metric dials, the
  SPO-15 lamps, the R-60s.
- [MiG-29](mig29.md): flown from the Mission Creator: the ИЛС-31 HUD in km/h and metres, the Щель-3УМ helmet sight, the
  radar altimeter and AoA / g meter.

The file names follow the Reference screen's record folders (`f4`, `f42000`, `cfir`, `mig23`, `mig29`).

## Markdown

The guides use the Markdown subset of `game/menu/guide_md.gd`, which `tools/guide_pdf.py` reads too: `#` / `##` /
`###` headings, paragraphs, bold / italic / code, one-level lists, pipe tables, `---`, footnotes (`[^name]` in the
text, `[^name]: source` at the end, shown as `[name]`) and pictures on a line of
their own, `![caption](shots/<jet>/<name>.png)`. A numbered list right under a picture is its legend: one item per
numbered callout, in order.

## Pictures and PDFs

Setup's last step makes both (it needs a display). They show the original game's art, so they stay under
`assets/converted/guides/` and are never committed.

1. `tools/guide_shots.sh [jet …] [--only name,…] [--force]` renders each entry of `<jet>.shots.json` (its schema in
   the header of `tests/godot/_guide_shots.gd`) into `shots/<jet>/<name>.png`, in a 3840×2160 frame whatever the
   screen's size.
   - An entry sets the settings, the mission (`mc` builds a Mission Creator mission, 666: the MiGs fly only there),
     the start (mission, airborne, dive, final approach), a placed target, actions (a
     radar lock, a store, a camera on the target) and the crop: the whole frame, `hud`, an MFD, `compass` (the panel
     compass dial) or `panel` (a box around `crop_at`, [x, y] panel px of the 1920-px strip). `hud` and `compass`
     take `crop_w` (the box's width as a fraction of the frame; smaller zooms in) and `crop_dy` (the box moved down
     by that fraction of the frame's height).
   - `annotations` draw numbered yellow callouts with arrows: to a symbol found in the Real HUD's own output (a
     `text:` regex ends on the box the HUD draws that text in, `hud.gd` `prim_text_box`) or to a point of the crop.
     A reading that moves by a few feet between renders takes a pattern, such as `text:^[89]\d\d$`, and the guide
     says "about". A symbol not found fails the shot.
   - Each Godot process takes up to `GUIDE_BATCH` shots (default 4), each from the default settings and a fresh
     mission; `GUIDE_JOBS` processes run at once (default half the cores, at most one per 2 GB of free memory). The
     F-16's 13 shots take about 2.5 minutes on an 8-core laptop.
   - A picture whose stamp (`<name>.stamp`: its entry, the shot tools, Godot's version, the frame size, the data's
     paths and sizes) still matches is kept; `--force` or `GUIDE_FORCE=1` renders every one. A FAIL line, a crash
     or a process stuck past `GUIDE_TIMEOUT` s per shot (default 600) makes the exit status 1.
2. `python3 -I tools/guide_pdf.py [jet …] [--force]` prints each guide as an A4 PDF: a title page with the Reference
   screen's picture of the jet, contents, the pictures with their legends kept on the same page. It warns when a
   legend's length differs from the picture's callouts. Headless Firefox prints it (Chrome / Chromium when Firefox
   is missing). A PDF newer than its Markdown, shots list, pictures and the script is kept unless `--force`.
