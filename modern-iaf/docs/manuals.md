# Modern IAF's manuals

Four PDFs, built by one command from text, the game's data and pictures taken from the game:

| manual | PDF (`modern-iaf/manuals/pdf/`) | text (`modern-iaf/manuals/text/en/`) |
|---|---|---|
| F-16I Sufa flight manual | `f16i-sufa-flight-manual.pdf` | `f16i/outline.yaml`, `f16/` |
| F-16D Barak flight manual | `f16d-barak-flight-manual.pdf` | `f16d/outline.yaml`, `f16/` |
| F-35I Adir flight manual | `f35i-adir-flight-manual.pdf` | `f35i/` |
| Modern IAF game manual | `game-manual.pdf` | `game/outline.yaml` |

The plan is the user's (17 November 2026): each jet has a full flight manual in the real manual's order, complete
about its jet; the game manual holds what is not about a jet and links to the jets' manuals; PDF is the only
published form.

## 1. State and next (18 November 2026)

**State.** The user approved the manuals on 18 November 2026 ("Ok with manauals, finish them"); they are on `main`.
Written in the three jet manuals: chapter 1 "Description and systems" whole (1.1 The aircraft, 1.2 Cockpit
arrangement with every panel and item numbered, 1.3 to 1.12 the systems; §2) and chapter 2 "Normal procedures" whole
(2.1 Preflight and cockpit entry, 2.2 Cold start to take-off, 2.3 Climb, cruise and descent, 2.4 Approach and landing,
2.5 After landing and engine shutdown, 2.6 Air refuelling; §2 "Chapter 2"); in the game manual the key card and Attributions. Every other section is a plan in the outline. The
appendices (checklist, key card, controls, abbreviations, attributions, index) are drawn from the game's data, so they
are whole. The Hangar's Manuals entry opens the four PDFs ([front-end.md](front-end.md) §1).

**Next, in this order.**

1. The other chapters, a chapter a branch, the three jets together: 3 Emergency procedures, 4 Limits, 5 Flight
   characteristics, 6 Weapons and avionics; then the game manual, with "Missions and training".
2. Each row of section 1.2's F-16 tables against the flight manual's section I (§7); its text is now searchable
   (§2 "Chapter 1's system sections").

## 2. The outline

A manual's outline is `text/en/<manual>/outline.yaml`: its chapters and sections in order. The PDF is put together
from it (`main.typ`), so the contents page of each PDF is the outline.

| key | meaning |
|---|---|
| `id` | the section's label: the target of cross-references, and of links from the other manuals |
| `title` | the heading |
| `sim` | `full` (modelled), `part` (partly modelled), `none` (not modelled: the real jet's content, for reference) |
| `covers`, `not` | a planned section: what it will cover, and what of it the sim does not model |
| `file` | a written section: its text file under `text/en/` |
| `see` | links to the other manuals' sections, `[manual, section id]` |

A jet manual's chapters: 1 Description and systems, 2 Normal procedures, 3 Emergency procedures, 4 Limits, 5 Flight
characteristics, 6 Weapons and avionics; then the appendices A Checklist, B Key card, C Controls of the 3D cockpit, D
Abbreviations, E Glossary, F Index. The game manual's appendices: A Key card, B Attributions, C Glossary, D Index. The `sim` marks come from [avionics-plan.md](avionics-plan.md) §2–4, [cockpit.md](cockpit.md) §5.2
and [training.md](training.md); each is checked against the game again when its section is written.

The Sufa and the Barak share one cockpit and one checklist card in the game, so their written sections share text files
(`text/en/f16/`), filled with each jet's own name, base, pictures and data. Each PDF is complete by itself.

A jet's manual is general (the user, 18 November 2026: "Aircraft guides: should be general. 'puts you in the seat at
Ramon' is specific"): it describes the aircraft and its procedures as a real flight manual does, independent of any
base, lesson, mission, the instructor, the menus or the scoring. That context (where a flight starts, the tower's
radio flow, what fails a lesson) is the game manual's, and the jet's manual links to it. The build checks it: the
word list is `GAME_FLOW` in `tools/manuals.py`, read against each jet manual's outline, section files, the About
text, its glossary entries and the controls' names; a link to the game manual is exempt.

A jet's manual states the aircraft's consequence of an action, never the game's (the user, 18 November 2026: "When
you talk about hot start … don't mention it fails the mission. This is game side"): what happens to the engine or the
system, the limit passed, the damage, and what the pilot does. An abnormal condition is explained where it first
appears: what it is, why it matters, how the pilot recognises it, the action, and where else it has a use. Every
term of the glossary (`text/en/glossary.yaml`) is a link to its entry at its first use in a written section
(`term("…")`); the build stops otherwise (`glossary_links` in `tools/manuals.py`). The game's consequences are the
game manual's: its outline carries the proposed section "Missions and training" (`proposed: true`, waiting for the
user's yes), and a jet's procedure links to it for how the sim marks the procedure.

**Chapter 1's cockpit arrangement** (the user, 18 November 2026: "On cockpit arrangements don't show only the keys you
think that are needed. Show arrows to all. Then the checklist/manual can refer to a key by number"). Section 1.2 shows
every panel of each jet's cockpit and names everything on it: each control of the control table, each lamp, gauge and
display.

| data | holds |
|---|---|
| `text/en/<cockpit>/systems.json` `panels` | per panel its id, title, area (left, front, right) and rows; a row is a node of the control table or of the model (`nodes`: several parts under one number, a lamp's segments or a rocker's halves), its label as the panel writes it, the full name, the positions, what it does in the real jet, and `sim`, what the sim does with it |
| `numbers.json` | cockpit → panel → node → the number on its arrow. `python3 -I tools/manuals.py --numbers` gives a new row its panel's next number; a number given stays, so a row added later renumbers nothing and a removed row's number is not used again |
| `shared/extra/models/cockpit3d/<cockpit>_status.json` | per control, lamp, gauge and display its state in the sim, `status` (`works`, `partly`, `moves`, `none`) and a short `note`: the controls from the audit of 18 November 2026 (F-16: 98 work, 11 partly, 54 move only; F-35I: 10, 5, 32), the lamps, gauges and displays traced to the reader of their state (`cockpit3d.gd` `_lamp_on`, `_prop`, `_instrument_prop`) |
| `pictures/<cockpit>/p_<panel>.jpg`, `overview_all.jpg`, `marks.json` | the panel's picture with each row's box; the whole cockpit's picture with each panel's box (§4) |

The layout (`control-tables`) draws first the overview, one figure of the whole cockpit from above the seat with every
panel in its box under its figure's number (`overview_all`: the head raised and back, a view 110° high, wider than the
game's widest), then per
panel its figure and its table: number, label and full name, positions, what it does and "In the sim", and the state
as a chip. A figure shows the part of the picture that holds the panel; the numbers stand in a column on each side with
a leader line to each item (`callouts`), so no number covers a control or another number, and the build stops when a
column has no room ("split the panel"). The numbers are 7 pt, the tables 8 pt.

**Chapter 1's system sections** (1.1 and 1.3 to 1.12; `text/en/f16/ch1/`, `text/en/f35i/ch1/`, a file a section).
Each describes the real system first, every statement with a footnote that names the exact place of its source, or the
word "inferred"; then a box "In the sim:" (`in-sim`) with what the sim does, each reaction in bold after an arrow, and
last what is not modelled, from the status data. A control, light or gauge is named with `row("<node>")`: its label on
the panel with its figure and number. The Sufa and the Barak share the F-16's files; `sufa` chooses the sentences
that differ (engine, fuel, weights).

| jet | sources |
|---|---|
| F-16 | the Hellenic Air Force's flight manual T.O. GR1F-16CJ-1 (F-16C/D Blocks 50 and 52+, 15 October 2002, Change 1 of 15 June 2003), a public copy at https://archive.org/details/haf-f-16. The PDF has a text layer (`pdftotext`), so a statement is checked by a search; the footnotes give the manual's page. F-16.net and Airforce Technology for the Israeli jets. |
| F-35I | Lockheed Martin's AIAA papers on the air vehicle and the mission systems, its F-35A product card, a US Air Force accident report (the engine start), Martin-Baker, and Wikipedia where no first source was found. The F-35's flight manual is not public: what this cockpit's switches do in the real jet is "inferred from their names". |

Sites that refused automated access and were left alone (18 November 2026): af.mil, e-publishing.af.mil,
prattwhitney.com, keymilitary.com.

**Chapter 2** (`text/en/f16/ch2/`, `text/en/f35i/ch2/`, and `cold-start.typ`). Every step table is drawn from the
checklist card (`steps("<card section>")`); the text files hold only the reactions and notes by item id, so a change of
the card's wording or items shows in the next build, and a note for an item the card no longer has stops it. The
pictures are the cold start's, drawn again with each section's step numbers. Section 2.1 and 2.6 give the real jet's
content only (`sim: none`).

| jet | chapter 2's sources |
|---|---|
| F-16 | the flight manual's section II, pages 2-2 to 2-30 (take-off 2-20 and 2-21, the checks in flight 2-22 and 2-23, the landing 2-23 to 2-27 with figure 2-3's approach speeds, the shutdown 2-27 to 2-30), the hot start on the ground page 3-26, air refuelling page 8-34. Section 2.2's footnotes now name these pages; its JFS and generator figures are the manual's (55 % and 60 %), with the sim's 52 % said beside them. |
| F-35I | US Air Force Instruction 11-2F-35A Volume 3 (7 June 2012, no releasability restrictions), by paragraph: flying rules of the jet's development period (taxi speeds, the checks in flight, the fuel calls, the pattern, the approach category). It holds no checklist, and the manual says so; a copy and notes are kept outside the repo. The footnotes carry no link: the publisher's site refuses automated access. Climb schedule, approach speeds and the landing technique are "open". |

**References.** Every mention of a control carries its figure and number as a link to its row, in one form: "MAIN PWR
(1-8, 1)" (`ctl-ref`): a procedure's steps, the checklist card, the Controls appendix, and `ctl("…")` in a text. Figures
are numbered chapter-figure ("1-8").

**The build stops** (`cockpit_data` in `tools/manuals.py`) on a control of the control table that no panel has, a row
without its number or without its arrow (its box in the panel's picture), a panel the overview does not show, and a
control or row without a status; each is listed.

**No place in words beside a picture** (the user, 18 November 2026: "Under every pic there is a table that say where
it is which is always the above pic"). No table under a picture has a "where" column, and a step's line names a place
only when no figure of chapter 1 shows its control (the figure and number say where it is).

**The abbreviations.** In a procedure an abbreviation's full name stands once a chapter, in brackets under the first
step that has it. Appendix "Abbreviations" lists `systems.json`'s `abbreviations` and `short`; the build stops on a
word in capitals that is in none of the file's lists (`abbreviations` in `tools/manuals.py`). It reads every written
text of the manual: the sections with their footnotes, the About text, the checklist card, the controls' names and
notes, the glossary's entries, the outline's titles and introductions, and `systems.json` itself. The planned
sections' plans join when they are written. The game manual has no such list yet.

Weapons sections give the employment procedure only: switches, pages, cues, counts. Missile performance, how well a
countermeasure works and electronic attack stay out.

## 3. The build

```sh
python3 -I tools/manuals.py            # all four PDFs
python3 -I tools/manuals.py f35i       # one
```

It needs Typst 0.15 (`$IAF_TYPST`, `typst` on the PATH, or `~/.local/share/iaf-typst/typst`; the official release from
https://github.com/typst/typst/releases, checked against the release's SHA-256). Fonts: Heebo from
`modern-iaf/data/fonts/` (the front end's; it has Hebrew and Latin) and the DejaVu Sans Mono that Typst carries. The
build reads no system font and fetches nothing.

| file (`modern-iaf/manuals/`) | holds |
|---|---|
| `manuals.json` | each manual's PDF name, checklist card, cockpit |
| `main.typ` | puts one manual together from its outline |
| `layout/manual.typ` | the page design and every part a text may use; no sentence of a manual |
| `text/<lang>/ui.yaml` | the layout's own words (Contents, WARNING, column heads) |
| `text/<lang>/controls.yaml` | the controls' names and places, by the control table's node |
| `text/<lang>/glossary.yaml` | the glossary |
| `text/<lang>/…/*.typ` | a written section: prose and calls of the layout's parts |
| `shots.json`, `pictures/<cockpit>/` | the pictures' list; the pictures and `marks.json` (§4) |

Text and layout are apart, so a Hebrew edition is a `text/he/` folder: `--input lang=he` reads it, Typst sets the
text right to left, and the checklist's lines come from the card's `he`. Only English is written.

**Drawn from the game's data** at every build:

| part | from |
|---|---|
| a procedure's steps (`steps("before_start")`) | the checklist card, `modern-iaf/data/checklists/*.json`: each item's line, how, where, and whether the sim ticks it |
| a step's key; a key named in the text (`key("Call the tower")`) | the sim's key table, `modern-iaf/data/keys.json` |
| a control named in the text (`ctl("MAIN_PWR")`) with its figure and number; the numbers and arrows on a picture | the cockpit's control table, `shared/extra/models/cockpit3d/<cockpit>.json` `controls` under `<cockpit>_controls.json`; `numbers.json`; `pictures/<cockpit>/marks.json` |
| a control's state in the sim | `shared/extra/models/cockpit3d/<cockpit>_status.json` |
| appendix A Checklist, B Key card, C Controls | the same three |
| the key card's keyboards (below) | the key table: the commands the Keys screen lists, each on its key's cap; and `own_keys.json`, the keys the flight scene reads by itself (`shared/terrain/terrain_view.gd` `_own_key`, the trim and switch keys) that work in Modern IAF. The build stops when the scene no longer has a name of a record's `code`, and when `_own_key` reads a key that no record names (`own_keys` in `tools/manuals.py`): an own key keeps its row and its key, and a new command takes a free key |
| the game manual's Attributions | the game's record of credits, `shared/credits.json` `sim` and `made_with` (docs/credits.md), with each use's words from the setup's strings (`modern-iaf/setup/strings_<lang>.json`) |
| a link to another manual (`other("game", "tower")`) | that manual's outline: the section's number and title |

**The build stops**, naming the file and the name, when a text names a key command the key table lacks, a control
the control table lacks, a checklist section or item the card lacks, a picture or pictured control without a name, a
section another manual's outline lacks, a listed key that the keyboard drawing has no cap for (or a modifier without a
keyboard, or two commands on one key), a credit without its use, licence, link or lines, or a jet manual's text with one of the game's words (§2). A change to a key, a control, the card or a procedure therefore updates the
manuals' text and PDFs in the same merge: run the build.

**The keyboards** (the key card of every manual): landscape pages, one keyboard for the keys alone and one for each
modifier that has commands (Shift, Ctrl, Alt; a command has one modifier). The drawing is the ISO physical layout
(tall Enter, the key beside the left Shift) with the function row, the navigation keys and the numpad, in Typst
(`manual.typ` `kb-caps`); the sim reads keys by their place, so the caps carry the US legends. A cap shows its legend and
the command's name in 6 pt on its group's colour (the Keys screen's five groups). The colour is the group's only mark
(the user, 18 November 2026: "Keycard: no need for both color and a letter"); the five differ in lightness, each a
step darker than the one before (CIE lightness about 95, 89, 83, 73, 65), so they stay apart in a greyscale print; a name too long for its cap becomes a number, listed under the keyboard. The held
modifier's caps are dark. The keyboards and the tables hold every command of the table that has a group and a key,
the ones the Keys screen leaves out too (the stick on the arrows, the throttle steps on 9 and 0, the rudder).

**Keys on macOS** (the user, 18 November 2026: "Where we state ctrl key need to know if it is replaced with cmd on Mac
or not"). The facts, from `shared/controls/key_table.gd` and [front-end.md](front-end.md) §9.1: on macOS the sim
reads Cmd as Ctrl (`ctrl()`, `_held_modifiers()`), Ctrl still works, its Keys screen names Ctrl ⌘ and Alt Option, and
it starts from the laptop map (the record's `laptop` key). Keys are read by their place (`physical_keycode`), so
Option's characters change nothing. Inferred, not yet tried on the Mac: macOS keeps Cmd + Q (quit) and Cmd + M
(minimise) for itself, and Ctrl + arrows for its desktops. Every key a manual shows goes through one part of the
layout (`key-of`, behind `key("<command>")`, the steps' Key column, the controls list and the key tables): it prints
the key and, where macOS differs, one cap with the key on top and the macOS key under it, smaller (the user, 18
November 2026: "No need to write (macos: key). Just have the other option written below the current key"): the laptop
map's key, Cmd for Ctrl (Ctrl kept for Q and M, `mac-keeps-ctrl`), Option for Alt. The cap takes one line's height in
running text. "About this manual" explains it. The keyboards name both on the modifier caps (Win / Cmd, Alt / Option), darken Cmd
with Ctrl, and each page says which modifier a Mac takes. The build stops on a key combination typed by hand in a
text ("Ctrl +", `hand_keys` in `tools/manuals.py`). The keyboards draw the default map; the laptop map's 13 moved
commands show their macOS key in the tables.

Faults of the game this found, for a Mac laptop's keyboard (listed, not fixed here): Drop chaff sits on Insert, a key
that keyboard lacks, and the laptop map gives it no other; the Keys screen shows ⌘ + Q for Leave mission and ⌘ + M
for Mute, which macOS takes (Ctrl + Q and Ctrl + M work); F11 (View from the weapon) is macOS's Show Desktop by
default. Home, End, Page Up, Page Down and Delete need Fn with the arrows and Backspace there.

**Finding things in a PDF:** the contents, the bookmarks, every cross-reference, footnote and index entry are links.
A link to another manual is a relative link to `<file>.pdf#<section id>` (Typst writes each section's label as a
named destination), so it works while the four PDFs sit in one folder. Whether a viewer opens the other file at that
section is the viewer's: checked 18 November 2026 only that the destinations are in the files (`pdfinfo -dests`);
macOS Preview is open.

### 3.1 The build in CI

The user's decision (18 November 2026): "Yes, ci to build manuals and update the repo on change".
[The Manuals workflow](../../.github/workflows/manuals.yml) runs when a push or a pull request changes an input of the
build: `modern-iaf/manuals/` (text, layout, pictures, lists), `modern-iaf/data/checklists/`, `modern-iaf/data/keys.json`,
`modern-iaf/data/fonts/`, the control tables `shared/extra/models/cockpit3d/*.json`, the credits `shared/credits.json`, the setup's strings
`modern-iaf/setup/strings_*.json`, `tools/manuals.py`, `shared/terrain/terrain_view.gd` (its own keys are on the key card), or the
workflow.

| where | what it does |
|---|---|
| a branch, a pull request | installs the same Typst release (0.15.1, the official asset, checked against its SHA-256), runs the build, and keeps the four PDFs for 7 days as the run's `manuals` artifact. A stop of the build (the list above) fails the run. |
| `main` | the same; then, when a built PDF differs from the committed one, the `publish` job commits the PDFs to `main` as `github-actions[bot]`: `Manuals: the PDFs rebuilt by CI from <commit> [skip ci]`. |

- The commit is a normal new commit on top of `main`. When `main` moved during the run, the job rebases its commit (its own PDFs win over an earlier run's)
  and pushes once more; a second refusal fails the run.
- Only the `publish` job may write to the repo (`contents: write`); it runs no build, it takes the PDFs from the
  build job's artifact.
- The bot's commit starts no new run: it changes only `modern-iaf/manuals/pdf/`, which the workflow's paths leave
  out, and its message holds `[skip ci]`.
- CI has no game assets and starts no Godot. It uses the pictures committed under `modern-iaf/manuals/pictures/`;
  every picture and `marks.json` the manuals use is tracked. A cockpit change that needs new pictures is shot locally
  (§4) and committed with the change.
- The same inputs give the same bytes: Typst gets a fixed creation time and the edition date, both from the last
  commit to the manuals' sources (the PDFs themselves do not count; sources edited and not yet committed count as
  today). Checked 18 November 2026: two builds in a row gave the same SHA-256 for all four PDFs.

## 4. The pictures

`modern-iaf/tests/_manual_shots.gd` (a real render; its header has the command) takes them from the game. For each
cockpit it starts a cold start-up lesson and hides the pilot's body and the overlays. It saves
`pictures/<cockpit>/<shot>.jpg` (1,600 px wide) and, in `marks.json`, each part's box in its picture. The Sufa and the
Barak share the F-16's cockpit, so both manuals draw the one set `pictures/f16/`.

| shots | from | camera | marks |
|---|---|---|---|
| a procedure's (`elec`, `jfs`, …) | `shots.json` | the pilot's eye: the head turns to the parts, as close as keeps them all in the picture; the cockpit cold and dark, as the procedure finds it | each control's box; the build draws a numbered arrow to each, the number of the step that uses it, at the nearest free spot |
| `p_<panel>` | every row of the panel in `systems.json` | square in front of the panel (below) | each row's box (a row's `nodes` together); the build crops to them and numbers them |
| `overview_all` | every panel | the whole cockpit from above the seat | each panel's box |

**A panel's picture** is a figure, so it is taken from where every control shows (the orchestrator's brief, 18
November 2026), with the battery on and the lamp test held, so every lamp and legend is lit:

- The camera stands on the normal of the plane through the marked parts' middles, on the pilot's side, far enough to
  hold them in 0.8 of the picture at a 30° view. Parts on one line (a row of switches) span no plane: the camera
  looks across the line from the eye's side.
- Its near plane is 4 cm before the nearest marked part, so what stands in the way (the stick, the throttle, the
  ICP's edge before the MFDs' inner buttons, a sill) is cut away without a list of things to hide.
- The picture's top is the pilot's own: up on the front panels; on a console the nose or the outboard side, whichever
  is nearer to the top of the pilot's view of it from the seat, as the F-16's console legends are turned. The Adir's
  console legends all read toward the nose (`"legends": "nose"` in `shots.json`).
- The marks are projected through the camera that drew the picture, in the same frame, so picture and marks agree.
- A panel that stands turned about its own normal to the jet's axes (the caution light panel, about 15°; `GRID` in
  the script) has its picture's top turned to the grid of its marks, so its rows lie level.
- The stick and the throttle are hidden in every picture but their own, the whole cockpit's and a panel's that
  marks them (the Adir's seat panel shows its stick) (`HIDE`): from the seat they stand before the panels beside
  them (the AIR SOURCE knob was behind the stick).
- The stick, the throttle, the HUD and the DED's group are no flat panel: their pictures stay
  from the pilot's eye (`EYE` in the script; the stick's with a lamp at the eye and the head leant, `LAMP`, `LEAN`).

**The numbers on a panel's picture** stand in a column at each side with a leader to their mark. A number whose
leader would run over another mark (the ICP's inner keys, an MFD's top buttons) sits on its own mark's edge without a
leader, in 6 pt. The build stops when two numbers' boxes overlap or a number is drawn under 6 pt: each number's drawn
height is measured against a 6 pt digit's (`checked` in `callouts`, `layout/manual.typ`; a number that is a link to a
figure has no size yet, so a digit drawn the same way is measured for it).

`SHOT_ONLY=p_` (or `overview`) takes only those and keeps the others' pictures and marks. A picture is taken again
when the cockpit's model, the shot list or a panel's rows change.

The F-16's cockpit model is derived from the FlightGear F-16 (GPL-2.0-or-later,
`shared/extra/models/cockpit3d/SOURCES.md`), so its pictures carry that licence; the F-35I's cockpit is ours.

## 5. The page design

A4, one column, Heebo 10.5 pt, the front end's navy and blue. A title page; a header with the manual and the chapter;
a footer with the edition (the date of the last commit to the manual's sources) and the page. Chapters start a page.
Parts:

- **Status chips** on the contents page and on each planned section: Modelled, Partly modelled, Not modelled.
- **Steps**: a numbered table; the control in bold, then its position; how to do it; where it is; the key. The
  reaction to the action (a light, a needle, a message on a display) stands on its own line, bold after a blue arrow
  (the user, 18 November 2026: "bold on reactions like a light should turn on or needle move because of the click");
  "About this manual" states the convention. The card holds no reaction field, so a section's text gives them
  (`steps(..., seen:)`), only ones the card's `how` or `check` or the sim shows. A step of a system that is not modelled carries ○ and "Not modelled: read and
  acknowledge". The ○ has its own column beside the number's (the user, 18 November 2026: "the circle symbol … is
  moving the number, not good"), so numbers, circles and texts stand in straight columns in every step table and on
  the checklist card; a step's row stays on one page.
- **Contents**: a section's status chip has its own column before the page number.
- **Pictures in a procedure** (the user, 18 November 2026: "the legend for each pic is disturbing the read flow"): a
  picture stands just before the first step that uses a control on it, and the number on each arrow is the number of
  the step that uses that control (two steps: both numbers); no legend. `steps(sid, figs:)` derives it from the card's
  `control` and `marks.json`; a picture of another section is drawn again with that section's numbers. The build
  stops when a picture shows no control of its section's steps, or a step uses a pictured control that none of the
  section's pictures shows.
- **Pictures in "Description and systems"** (`callouts`): the panel's part of its picture, the numbers in a column on
  each side with leader lines, the panel's table under it (§2).
- **WARNING / CAUTION / NOTE** boxes (red, amber, blue): what happens and how to avoid it. They describe the sim.
- **Sources** as footnotes; our own reasoning is said to be inferred in the text.

## 6. The standards

| standard | how the manuals meet it |
|---|---|
| ISO 24495-1 (plain language) | short sentences, the pilot addressed as "you", one term per thing (the glossary), what the reader needs first (purpose, then steps), findable through contents, bookmarks, cross-references and index |
| ISO/IEC/IEEE 26514 (software user documentation) | a title page with the edition, contents, "About this manual" (audience, scope, conventions), procedures as numbered steps with their start conditions and results, a troubleshooting table per procedure, reference appendices, glossary, index; the manual is checked against the software by the build |
| IEC/IEEE 82079-1 (instructions for use) | the signal words WARNING, CAUTION and NOTE with one meaning each, stated in "About this manual"; a safety message names the consequence and how to avoid it and stands before the step it concerns; pictures beside the steps they serve; the statement that the manual instructs for the sim, not for a real aircraft |

## 7. Open

- Cross-manual links in macOS Preview: to check on the Mac.
- The F-35I card's place for the HMD knob (`modern-iaf/data/checklists/f35i.json` `hmd`: "right of the front panel")
  differs from the cockpit, where the knob sits under the display, left of centre (Figure 2.2 of the Adir's manual).
  The step shows the card's text; the card is the game's data and is corrected there.
- Section 1.2's F-16 rows ("what it does") were written from memory of the public flight manual's section I, and
  each is to be checked against it. The rows marked "inferred" are parts the cockpit model draws and the flight
  manual's figure does not name.
- The RPM indicator's picture for "Starting engine": the gauge's needle node (`anim069`) has no mesh the shot script
  can box; the text names its place instead.
- Found while writing chapter 1, the game's and listed, not changed here: the airspeed dial of the F-16 shows true
  airspeed (`cockpit3d.gd`); MANUAL PITCH, CAT III and the roll trim have keys read by the flight scene with no record
  in `keys.json`, so the manuals name their switches only; ALT FLAPS and the Flaps key move the game's flaps lever
  while the 6-DoF flaps follow the gear handle, so chapter 1 says nothing of ALT FLAPS in the sim; the Manuals screen
  names the game manual "Modern IAF".
- The Adir's `p_seat` picture is the one taken before `HIDE` (its throttle shows); it is taken again with the next
  pictures (`SHOT_ONLY=p_seat`).
- The Adir's displays in a start by keys: the manual and [training.md](training.md) §7 say they light 3 s after the
  IPP is up; in `start.rs` a keyed start holds the `Starter` phase until ENG, and `displays_on_starter` powers them
  only after that phase. To check in the game; the manual follows training.md.
- Open in chapter 1's sources: the AOA indexer's colours, the caution panel's count and the cabin pressure schedule
  (pictures in the flight manual); for the F-35 the tank layout, the gear and brake systems, the ICAWS categories'
  definitions and the cockpit switches' functions.
- Found while writing chapter 2, the game's and listed, not changed here: the key table lists "Drag chute" (Shift + B)
  with a group, so the Keys screen and the key cards show it, while no Modern IAF jet has a drag chute
  (`airframe.json` `drag_chute: false`); the speedbrakes have no key or switch of their own (the Wheel brakes key
  opens them in the air, [flight-model.md](flight-model.md)), so a landing roll cannot hold the nose up with the
  speedbrakes shut, nor brake the wheels without them; the autopilot's PITCH and ROLL switches move only (the A key
  is the only way); the cards' "Throttle – OFF" item names its key in words and carries no `key`, so the step tables'
  Key column is empty there; the F-16's FUEL QTY SEL knob moves only, so the card's fuel check cannot be done as the
  real one; the card has no line for the speedbrakes or the altimeter before landing, which the real "Descent/before
  landing" has.
- Open in chapter 2's sources: the F-16's climb schedules (the performance manual, not public); for the F-35 the climb
  schedule, the approach speeds, the landing technique and the air-refuelling cockpit procedure; the footnote for the
  F-16's exterior inspection names figure 2-4 without its page.
