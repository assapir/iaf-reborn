# Modern IAF's manuals

Four manuals and one Hebrew edition, five PDFs, built by one command from text, the game's data and pictures taken
from the game:

| manual | PDF (`modern-iaf/manuals/pdf/`) | text (`modern-iaf/manuals/text/en/`) |
|---|---|---|
| F-16I Sufa flight manual | `f16i-sufa-flight-manual.pdf` | `f16i/outline.yaml`, `f16/` |
| F-16D Barak flight manual | `f16d-barak-flight-manual.pdf` | `f16d/outline.yaml`, `f16/` |
| F-35I Adir flight manual | `f35i-adir-flight-manual.pdf` | `f35i/` |
| Modern IAF game manual | `game-manual.pdf` | `game/outline.yaml`, `game/<chapter>/<section>.typ` |
| the game manual in Hebrew (§2.1) | `game-manual-he.pdf` | `text/he/game/`, the same files |

The plan is the user's (17 November 2026): each jet has a full flight manual in the real manual's order, complete
about its jet; the game manual holds what is not about a jet and links to the jets' manuals; PDF is the only
published form.

## 1. State and next (18 November 2026)

**State.** The user approved the manuals on 18 November 2026 ("Ok with manauals, finish them"); they are on `main`.
Written in the three jet manuals: chapter 1 "Description and systems" whole (1.1 The aircraft, 1.2 Cockpit
arrangement with every panel and item numbered, 1.3 to 1.12 the systems; §2) and chapter 2 "Normal procedures" whole
(2.1 Preflight and cockpit entry, 2.2 Cold start to take-off, 2.3 Climb, cruise and descent, 2.4 Approach and landing,
2.5 After landing and engine shutdown, 2.6 Air refuelling; §2 "Chapter 2") and chapter 3 "Emergency procedures" whole
(3.1 to 3.8; §2 "Chapter 3"), chapter 4 "Limits" whole (4.1 to 4.4) and chapter 5 "Flight characteristics" whole (5.1 to
5.5; §2 "Chapters 4 and 5"). The
appendices (checklist, key card, controls, abbreviations, attributions, index) are drawn from the game's data, so they
are whole. The Hangar's Manuals entry opens the four manuals, the game manual in the game's language
([front-end.md](front-end.md) §1).

Chapter 6 "Weapons and avionics" is written whole in the three jet manuals (§2 "Chapter 6"), with the pictures listed
as owed in §7.

The game manual is written whole (§2 "The game manual"): six chapters, 34 sections, with the screens' pictures; no
outline holds a planned section any more.

The game manual has a Hebrew edition (§2.1), written whole on 18 November 2026. The user reads it before it counts as
final: no agent is a native reviewer.

**Next, in this order.**

1. Chapter 6's owed pictures and the game manual's four (§7).
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

Every manual, in each language, follows ISO 24495-1 plain language (the user, 18 November 2026: "do iso sweep on all
guides"). Modern IAF stands alone: a manual names no other game, its data or the sim's history, and says what a thing
is and does. The build checks it: the word list is `PLAIN` in `tools/manuals.py` (another game and history words, and
the commonest "what it isn't" phrasings), read against each manual's outline, section files, About text and glossary.
A line that marks what is not modelled, a warning or a caution is exempt, and so are comments and quoted sources.
The same check stops scripts, options and commands (the user, 18 November 2026: "we should not encourage script usage"): the player starts the game and the setup with `./start-modern-iaf` and `./modern-iaf-setup` (`.ps1` on Windows) and nothing else; installing a program is said by its package manager (the distribution's, Homebrew, winget), never as a command.

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

**Chapter 3** (`text/en/f16/ch3/`, `text/en/f35i/ch3/`, a file a section, in the order of a flight: how an emergency
shows, ground, take-off, engine, systems, out-of-control, landing, ejection). Each emergency is a heading with its
own state chip under it (`state("full" | "part" | "none")` in `ch3/src.typ`): what it is, why it matters, the
indications in bold with each light by figure and number (`row`), the actions in order, what follows, and an "In the
sim:" box. The sim's side was written from an inventory of the code (the damage flags of
`shared/mission/player_damage.gd`, the lamps of `shared/cockpit/cockpit3d.gd`, the start's faults in
`crates/iaf-flight/src/sixdof/start.rs`, the status data), not from the outline's plan.

| jet | chapter 3's sources |
|---|---|
| F-16 | the flight manual's section III, by page: 3-3, 3-26 to 3-29, 3-33 to 3-41, 3-43 to 3-45, 3-61, 3-62, 3-70, 3-79, 3-80, 3-98, 3-99, 3-105, 3-108, 3-117, 3-118, 3-121, 3-123, 3-124, 3-128 to 3-131, 3-134, 3-136, 3-139, 3-140. Where the steps read are the Pratt & Whitney engine's, the Barak's text says "inferred". The single FLCS procedures (pages 3-108 to 3-116) are named, not repeated. |
| F-35I | US Air Force Instruction 11-2F-35A Volume 3, chapter 7 and the paragraphs named in the footnotes. No emergency checklist of the F-35 is public: every procedure it would hold is "open", and the manual gives no invented steps. |

**Chapters 4 and 5** (`text/en/f16/ch4/`, `ch5/`, `text/en/f35i/ch4/`, `ch5/`, a file a section; `ch4/src.typ` holds
both chapters' sources). Each section gives the real jet's limit or behaviour with its footnote, the word "open" where
no public source gives the figure, and an "In the sim:" box with the sim's own value and what is not modelled. The
sim's side is written from [flight-model.md](flight-model.md) §9.7 to §9.19, `docs/damage.md` §5.2 (the gear's limits),
the aircraft definitions (`gear_limit`) and the units' records (`max_takeoff_kg`, `lateral_limit_kgm`,
`crates/iaf-tools/src/briefing.rs`). Section 5.5 "Performance" holds the sim's own figures only: the real charts are
in supplements that are not public.

| jet | chapters 4 and 5's sources |
|---|---|
| F-16 | the flight manual's section V (pages 5-1 to 5-5, figures 5-1 to 5-8 on pages 5-6 to 5-15) and section VI (pages 6-1 to 6-9), section I page 1-121 (the limiters) and 1-135 (the gains with the gear down), section II pages 2-21, 2-24, 2-26 and 2-27. Open, because they are in the supplements T.O. GR1F-16CJ-1-1 (performance), -1-2 (stores) and -5-2 (centre of gravity): the stores' categories as a list and every store's limits, the rolling g limits, the centre-of-gravity limits, the crosswind limits, the brake speeds, the take-off speeds and every performance chart; also the service ceiling, a landing weight, the touchdown sink rate, the nose tyre's limit for the Israeli builds and the arresting speeds (figure 5-5's first sheet is a picture in this copy). |
| F-16D Barak | The sim's Barak is an F-16D Block 40 with the F110-GE-100 (`crates/iaf-flight/src/sixdof/jets.rs` `f110_100`, [flight-model.md](flight-model.md) §9.7; F-16.net for the Israeli F-16Ds). The public flight manual covers Blocks 50 and 52 with the F100-PW-229 and the F110-GE-129. The Barak's engine limits are therefore the manual's F110-GE-129 figures, each marked "inferred" for the F110-GE-100, whose own limits are open; the figures of the airframe are marked "inferred" for its blocks. Chapter 3 was corrected the same way: its engine section says that its signs and actions are the F100-PW-229's pages (inferred for the Barak), the hot start's 935 °C and the 10 s light-off are the F110-GE-129's, and the Barak's own air start is open. |
| F-35I | The maker's product card (9 g), the 50° angle-of-attack limit (Second Line of Defense), US Air Force Instruction 11-2F-35A Volume 3 by paragraph. Every other limit, the control laws and the handling with stores are "open". Five footnotes (the top speeds, the Eglin accident's approach figures, a pilot's account of the handling, the lowered turn specification, the F135's response) carry sources taken from `docs/f35i.md` and [flight-model.md](flight-model.md) with the words "not read again for this chapter"; the F-16's Block 40 weight and NASA TM-4320 the same. |

**Chapter 6** (`text/en/f16/ch6/`, `text/en/f35i/ch6/`, a file a section; `ch6/src.typ` holds the sources and the
chapter's parts). It describes the sim's avionics as built and how the pilot works them: each display's pages button
by button (`osb(n)`: an MFD button with its figure and number), each switch with its key, and each weapon's
employment as numbered steps with the reaction in bold (`then[…]`). It is written from the avionics docs
([avionics-plan.md](avionics-plan.md) §2 to §4, [ufc.md](ufc.md), [ews.md](ews.md), [weapons.md](weapons.md),
`docs/radar.md` §9, `docs/mfd.md` §9), not from the outline's plan. A real-jet statement carries a footnote to the
public Block 50 manuals those docs cite (marked "not read again for this chapter") or the word "inferred"; each
F-16 section opens with the line that the jet's own pages are not public. The user's safety rule holds in every
section: cockpit procedure and the sim's display only, with no missile performance, no countermeasure effectiveness,
no electronic attack and no naming of a missile by the missile warning. The Adir's sections describe what is on
`main` and mark the rest "not in the sim yet".

A display's picture is `display("<name>", [caption])`: `pictures/<cockpit>/d_<name>.jpg`, a figure labelled
`fig-d-<name>` (§4).

**The game manual** (`text/en/game/`, a folder a chapter, a file a section). Its chapters: 1 Getting started
(what you need, setup, starting the game, flying a mission in five steps, the manuals), 2 The menus (the Hangar, pilots and the
pilot log, jet and base, the Missions screen, the briefing, the Loadout screen and its rules, Settings with every
option, keys and joystick, language), 3 Flying a mission (loading, views, the pointer, the notebook, the tower and
the radio flow, the AWACS, pause / time / leaving, the debrief), 4 Missions and training (the lessons in order, one
section a lesson, "Pass and fail": the game's consequences, which the jets' procedures link to as
`other("game", "missions-training")`), 5 Air bases, 6 Troubleshooting (setup faults, after an update, the crash
page, slow flight, keys on a Mac). It is written from the game as built: the code, the data and the docs named in
each section's brief.

| part | rule |
|---|---|
| a screen's, button's, option's or tab's name | `scr("<key>")`, drawn from the front end's strings (`modern-iaf/menu/strings_<lang>.json`); the setup wizard's with `stp("<key>")` (`modern-iaf/setup/strings_<lang>.json`). A key a table no longer has stops the build, so a renamed screen renames itself in the manual and a removed one is found. |
| the Settings' options | `settings-table((keys…))`: each option's name and the game's own description (`<key>_about`) |
| a screen's picture | `screen("<name>", [caption])`: `pictures/game/<name>.jpg` (§4), a figure labelled `fig-s-<name>` |
| a screen's parts | `screen("<name>", [caption], numbered: true)` draws a number beside each part of `<name>.json` (§4), and `screen-table("<name>", cols, head, ("<node>", cells…), …)` is its table: one row a part, by its node, drawn in the numbers' order with the number first ("No."). A text names a part by its name, or by its number where that finds it faster: "(2)". The build stops on a row without a number, a number without a row, and a numbered picture without its table in the same file (`screen_tables` in `tools/manuals.py`) |
| a task | a numbered list, one instruction a step, its reaction after `then[…]`; a safety box stands before its step |
| a glossary term | linked at its first use in a section; the build checks it for the game manual too (`glossary_links`) |

The text files hold no layout beyond these calls, so the Hebrew edition is a `text/he/game/` folder with the same
calls: the names then come from the Hebrew string tables by themselves.

### 2.1 The Hebrew edition of the game manual

The user's decision (18 November 2026: "wdyt with translating only the game manual to hebrew? but keep initials and
techincal terms in english?", and "yes" to the plan): only the game manual has a Hebrew edition; the three jets'
manuals stay English. The Hebrew manual links to the English jets' manuals and says so once, in "על המדריך".

| part | rule |
|---|---|
| the registry | `manuals.json` `"game-he": {"file": "game-manual-he.pdf", "of": "game", "lang": "he"}`: an edition names its manual and its language; the build passes `lang=he` and reads `text/he/` |
| initials, a panel's or a display's text | English, exactly as shown |
| a technical term | the Hebrew term the field uses, English where Hebrew speakers say it in English, never a coined word. One thing has one term: `text/he/terms.yaml` is the term table (the English term, the Hebrew one, where it comes from, and `not`: other words for the same thing) |
| a screen's, button's or option's name | `scr`, `stp`, `settings-table`: the game's own Hebrew strings, so the manual says what the screen says |
| the wording | gender-neutral and formal, as the front end's strings: the infinitive or "יש ל…" for an instruction |
| an abbreviation in Hebrew | the straight " and ' (בד"ח, ת'רדים), never the Hebrew gershayim and geresh (the user, 18 November 2026: "no one really use the hebrew quotes"); the build stops on one (`edition` in `tools/manuals.py`) |
| the glossary | `text/he/glossary.yaml`: the Hebrew terms; an inflected form in a text is `term("מגדל", shown: "המגדל")` |
| the pictures | `pictures/game-he/`, the same names as `pictures/game/`, taken with the game in Hebrew (§4) |
| the key card, the Attributions | drawn from the same data: the key table's `he` labels, `own_keys.json`'s `he`, the setup's Hebrew strings; the fixed labels are `text/he/ui.yaml` |

**Right to left.** Typst sets the text right to left from `lang: he`; tables, step columns, the header and the footer
mirror with it. The layout mirrors what has a side of its own: the title page's edge, a safety box's bar, the
reaction's arrow. Code, file paths, commands and key caps are set left to right in their own box, and the keyboard's
drawing keeps its places (it is a picture of a physical keyboard). The Attributions' licences and credit lines are
English, so their cells read left to right; the index's page numbers stand in a box, so they keep their end of the
line after an entry that ends in Latin letters.

**The build stops** for the Hebrew edition (`edition` in `tools/manuals.py`) when:

- its outline's chapters, sections, ids or files differ from the English outline's;
- a section's file is missing or still holds English text;
- a section names a screen, option, picture, key or link (`scr`, `stp`, `screen`, `key`, `other`, a `settings-table`
  key) that its English section lacks, or lacks one the English has: the two editions hold the same keys, and a key
  without a Hebrew string stops Typst, so the editions cannot drift;
- a Hebrew word holds a straight quote;
- a text holds a `not` word of the term table;
- the first use of a glossary term in a section is no link (as in English; a one-letter prefix counts).

`IAF_MANUAL_DRAFT=1` builds the edition anyway, for a look at its pages while a chapter is translated.

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
python3 -I tools/manuals.py            # all five PDFs
python3 -I tools/manuals.py game-he    # the game manual's Hebrew edition
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
text right to left, and the checklist's lines come from the card's `he`. The game manual has one (§2.1).

**Drawn from the game's data** at every build:

| part | from |
|---|---|
| a procedure's steps (`steps("before_start")`) | the checklist card, `modern-iaf/data/checklists/*.json`: each item's line, how, where, and whether the sim ticks it |
| a step's key; a key named in the text (`key("Call the tower")`) | the sim's key table, `modern-iaf/data/keys.json` |
| a control named in the text (`ctl("MAIN_PWR")`) with its figure and number; the numbers and arrows on a picture | the cockpit's control table, `shared/extra/models/cockpit3d/<cockpit>.json` `controls` under `<cockpit>_controls.json`; `numbers.json`; `pictures/<cockpit>/marks.json` |
| a control's state in the sim | `shared/extra/models/cockpit3d/<cockpit>_status.json` |
| appendix A Checklist, B Key card, C Controls | the same three |
| the key card's keyboards (below) | the key table: the commands the Keys screen lists, each on its key's cap; and `own_keys.json`, the keys the flight scene reads by itself (`shared/terrain/terrain_view.gd` `_own_key`) that work in Modern IAF and have no record in its key table. The build stops when the scene no longer has a name of a record's `code`, and when `_own_key` reads a key that no record names (`own_keys` in `tools/manuals.py`): an own key keeps its row and its key, and a new command takes a free key |
| the game manual's Attributions | the game's record of credits, `shared/credits.json` `sim` and `made_with` (docs/credits.md), with each use's words from the setup's strings (`modern-iaf/setup/strings_<lang>.json`) |
| the game manual's screen, option and step names (`scr`, `stp`, `settings-table`) | the front end's and the setup's strings, `modern-iaf/menu/strings_<lang>.json`, `modern-iaf/setup/strings_<lang>.json` |
| a link to another manual (`other("game", "tower")`) | that manual's outline: the section's number and title |

**The build stops**, naming the file and the name, when a text names a key command the key table lacks, a control
the control table lacks, a checklist section or item the card lacks, a picture or pictured control without a name, a
section another manual's outline lacks, a listed key that the keyboard drawing has no cap for (or a modifier without a
keyboard, or two commands on one key), a credit without its use, licence, link or lines, a jet manual's text with one of the game's words (§2), or a picture that is black (§4 "Black captures"). A change to a key, a control, the card or a procedure therefore updates the
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
text ("Ctrl +", `hand_keys` in `tools/manuals.py`). The keyboards draw the default map; the laptop map's 21 moved
commands show their macOS key in the tables.

Faults of the game this found, for a Mac laptop's keyboard, fixed 2026-11-18 ([front-end.md](front-end.md) §9.1):
Drop chaff and Drop flares sat on Insert and Delete, keys that keyboard lacks (now Ctrl + Z and Ctrl + X); the Keys
screen showed ⌘ + Q for Leave mission and ⌘ + M for Mute, which macOS takes (it shows Ctrl + Q and Ctrl + M, which
work); F11 (View from the weapon) is macOS's Show Desktop (now F2); the eight commands on Home, End, Page Up and Page
Down have laptop keys. A test of the key table fails on a listed command with no key on that keyboard.

**Finding things in a PDF:** the contents, the bookmarks, every cross-reference, footnote and index entry are links.
A link to another manual is a relative link to `<file>.pdf#<section id>` (Typst writes each section's label as a
named destination), so it works while the PDFs sit in one folder. Whether a viewer opens the other file at that
section is the viewer's: checked 18 November 2026 only that the destinations are in the files (`pdfinfo -dests`);
macOS Preview is open.

### 3.1 The build in CI

The user's decision (18 November 2026): "Yes, ci to build manuals and update the repo on change".
[The Manuals workflow](../../.github/workflows/manuals.yml) runs when a push or a pull request changes an input of the
build: `modern-iaf/manuals/` (text, layout, pictures, lists), `modern-iaf/data/checklists/`, `modern-iaf/data/keys.json`,
`modern-iaf/data/fonts/`, the control tables `shared/extra/models/cockpit3d/*.json`, the credits `shared/credits.json`, the setup's strings
`modern-iaf/setup/strings_*.json`, the front end's `modern-iaf/menu/strings_*.json`, `tools/manuals.py`, `shared/terrain/terrain_view.gd` (its own keys are on the key card), or the
workflow.

| where | what it does |
|---|---|
| a branch, a pull request | installs the same Typst release (0.15.1, the official asset, checked against its SHA-256), runs the build, and keeps the PDFs for 7 days as the run's `manuals` artifact. A stop of the build (the list above) fails the run. |
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
  today). Checked 18 November 2026: two builds in a row gave the same SHA-256 for all four PDFs, and the same day for the Hebrew edition.

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

**The displays' pictures** (`d_<name>.jpg`, chapter 6) are taken by the avionics slices' own shot scripts, each a
real render with its command in its header, and then cut and joined with ImageMagick: `_fcr_shot.gd` (`d_fcr_modes`,
`d_fcr_pages`, `d_hud_lock`), `_fcr_ag_shot.gd` (`d_fcr_ag`), `_mfd_s4_shot.gd` (`d_mfd_formats`, `d_mfd_menu_sms`),
`_avionics_s5_shot.gd` (`d_ded_pages`, `d_ded_ins`, `d_hud_modes`, `d_hsd`, `d_fcr_aiff`, `d_threat`, `d_threat_radars`) and
`_adir_s7b_shot.gd` (the Adir's), `_adir_tflir_shot.gd` (`d_tflir`). The Sufa's serve both F-16 manuals.

**The game manual's screens** (`pictures/game/`, 18 November 2026) are taken in English by the front end's own shot
scripts, each a real render with its command in its header, and scaled to 1,600 px JPEGs with ImageMagick (the name
without `_en`; a prefix per script): `_front_end_shot.gd` (no prefix), `_loadout_shot.gd` (`loadout_`),
`_briefing_shot.gd` (no prefix), `_notebook_shot.gd` (`notebook_`), `_flight_ui_shot.gd` (`flight_`),
`_devices_shot.gd` (`devices_`). The setup wizard's (`setup_*`) and the loading screen's are the pictures of
`_setup_wizard_shot.gd` (`setup_welcome`, `setup_imagery`, `setup_install`) and, converted, the pictures of
`modern-iaf/docs/pictures/setup/` (the skipped step, the remove dialog) and `front-end/loading_en.webp`. Only the pictures a section uses are
kept. The pilot on them is the shot scripts' sample pilot.

**A screen's numbered parts** (the user, 18 November 2026: "in game manual: use numbers on the screen shot instead
of where coulmn in the table"). The shot script writes beside a screen's picture `<screen>_<lang>.json`: `parts`, the
box of each node its `MARKS` lists (`get_global_rect()`, as fractions of the picture; a picture with a transparent
ground, the Hangar's jet, only where it draws), and `busy`, the boxes of the screen's other texts, buttons and
pictures. It is copied to `pictures/game/<name>.json` (`pictures/game-he/` from the Hebrew picture, whose layout is
mirrored). The parts are numbered in reading order, by lines from the top and in a line from the left, or from the right
in Hebrew. Each number stands outside its part, in the first free place beside it with a short leader to its edge
(`callouts` with `src`, `layout/manual.typ`): on no other part and no busy box, apart from the other numbers; the build
stops when a part has no such place. Numbered: the Hangar (`_front_end_shot.gd`, `hangar`).

**The Hebrew edition's screens** (`pictures/game-he/`, 18 November 2026) are the same scripts' Hebrew pictures
(`<name>_he.png`), scaled the same way. Three pictures have no language in their script: `notebook_radio` and
`notebook_training` are taken with `SHOT_LANG=he NB_SHOTS=radio,training` (`_notebook_shot.gd`), `devices_keys_mac`
with `SHOT_LANG=he` (`_devices_shot.gd`). `flight_mfd_view` shows a display of the jet, which is English in both.
`setup_install_remove` and `setup_install_skipped` are converted from `modern-iaf/docs/pictures/setup/*_he.webp`.

**Black captures** (found 18 November 2026). `_mfd_s4_shot.gd`, `_fcr_ag_shot.gd` and `_avionics_s5_shot.gd` put the
jet in the air and then sent the "start engine" command (213). An air start has every system running; the command ran
the start sequence again, so the AVIONIC POWER systems (MMC, ST STA, MFD, UFC) were off and the MFDs and the DED drew
nothing until the script's next air start. The command is removed from the three scripts. The build stops on a picture
under `pictures/` whose mean brightness is under 0.005 of white (`dark_pictures` in `tools/manuals.py`, measured with
ImageMagick; the darkest good picture, the Adir's threat display with a missile warning, has 0.011).

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
- Retaken 2026-11-18 on the Linux laptop, for the switches that now work: the F-16's `overview_all` (with the canopy
  panel's own box), `elec`, `flt_control`, `p_fuel` (MASTER FUEL's guard down), `gear`, `p_gear` (PARKING BRAKE set)
  and `p_right_aux` (the fuel indicator). The overview had come out turned 25° to the left since the lean control
  (414a77af): the shot script set `views.lean`, which the lean keys' update pulls back to the seat each frame; it sets
  `views.lean_to` now, which holds. The Adir's pictures were taken again and showed no change, so they stay.
- The manuals' marks checked against the status data and the code on 2026-11-18: the F-16's CMDS O1, O2 and JMR
  switches only move (`cmds.rs` keeps their state and nothing reads it), so their status is `moves`.
- The RPM indicator's picture for "Starting engine": the gauge's needle node (`anim069`) has no mesh the shot script
  can box; the text names its place instead.
- Fixed 2026-11-18 (the faults the manuals exposed, group A): the F-16's airspeed dial reads indicated airspeed
  (`cockpit3d.gd`, the HUD's and the Adir's displays already did); an empty tank flames the engine out
  ([flight-model.md](flight-model.md) "Flame-out").
- Fixed 2026-11-18 (group B, lamps): CABIN PRESS lights with AIR SOURCE at OFF, DUMP or RAM above 27,000 ft; MAIN
  GEN, STBY GEN and ELEC SYS light after generator damage (flags 19, 21); FLCS FAULT, ADC / CADC and FLCS BIT FAIL
  light from their modelled causes; the Adir's ICAWS writes FCS DEGD / FCS FAIL (`test_cockpit_lamps.gd`).
- Fixed 2026-11-18 (the key faults): MANUAL PITCH, CAT III, the roll trim and the GPS bomb's keys are records of
  `keys.json` (202–207), on the Keys screen and the key card; the key table has no drag chute; the speedbrakes have
  their own switch keys (records 200 / 201) and the Wheel brakes (hold) key brakes the wheels only (on W, held, with the
  waypoints on Shift + W / Shift + Q: the user, 2026-11-18; chapter 1's gear section and the cold starts say so); the
  cards' "Throttle – OFF" and the F-16's "Throttle – IDLE" items carry their `key`, so the step tables show it.
- Found while writing chapter 1, the game's and listed, not changed here: ALT FLAPS and the Flaps key move the game's flaps lever
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
- Found while writing chapter 2, the game's and listed, not changed here: the autopilot's PITCH and ROLL switches move only (the A key
  is the only way); the F-16's FUEL QTY SEL knob showed RSVR and INT WING as NORM (one fuel tank; every position shows its tanks since
  2026-11-18, cockpit.md §5.7); the card has no line for the speedbrakes or the altimeter before landing, which the real "Descent/before
  landing" has.
- Found while writing chapter 3, the game's and listed, not changed here:
  - STORES CONFIG stayed dark: the sim had no data on which loads are category III (lights since 2026-11-18 on an
    inferred rule, cockpit.md §5.7). FLCS BIT FAIL lights from the MFD's BIT only.
  - The "engine cut out" damage (flag 2) is never picked, so its restart path is dead code.
  - An engine fire stops the thrust of a single-engine jet (`damage_bits`); the extinguisher (a 1998 function; the real
    jets have none in the cockpit procedure) restores the engine at once.
  - An ejection works at any height: the low limits (50 m, 200 m inverted) only mark the recording's `eject` event
    `short` (`Settings.eject_ends_sortie`).
  - "Bingo" is spoken at a fixed 1,000 lb and 500 lb; the HUD's FUEL cue uses the pilot's bingo.
  - The F-16's `alt-gear` handle moves only while the F-35I's ALT GEAR works; the hook, the EPU and the F-35I's ENG
    FIRE push, FCS RESET, AUTO RECOVERY and ejection handle move only.
  - With the brakes damaged (flag 5) the wheel brake key does nothing, but the parking brake still holds the wheels
    (`flight.rs` reads it apart from the key; found 2026-11-18, the manuals say so).
  - The notebook's EMERGENCY pages (`modern-iaf/data/notebook.json`) hold steps the sim cannot do: motoring after a
    hot start, an engine fire on the ground, the ejection handle.
  - No horn or light warns of a low speed or of the gear up beyond TO/LDG CONFIG; `horn_silencer` moves only.
- Found while writing chapters 4 and 5, the game's and listed, not changed here:
  - Nothing happens above the jet's speed limit (800 kt, Mach 2.05) or g limit: only the gear's limit damages.
  - The limits with the gear down (g, 15° angle of attack with stores, roll) and the rolling g limits are not there.
  - The control laws do not change with the gear handle down (read from flight-model.md §9.11, not from the code): the stick commands g on the approach, where the real
    F-16 commands pitch rate up to 10° angle of attack.
  - A category III load flown at CAT I flies as a clean jet: stores change no stability. (The STORES CONFIG caution
    lights since 2026-11-18, cockpit.md §5.7.)
  - The yaw departure, the inverted deep stall and the centre of gravity (fuel and stores sit at it) are not
    modelled; open speedbrakes do not lower the departure resistance.
  - The Adir's limits (checked 2026-11-18): its sourced ones are its own data (`data_set::F35I`: +9 g, 50° angle of
    attack, the approach; `jets.rs`: the top speeds' fit; `modern-iaf/data/db/units/f35i.json`: the 70,000 lb take-off weight). Open, no
    public figure found, so the F-16's value stays (inferred): the touchdown limits, the gear limit (`gear_limit`),
    the negative g limit, the roll and the control laws; it has no asymmetric-load limit, so no warning.
  - The JFS's time limits and the negative-g fuel limits are not there.
  - The low-speed warning tone follows the angle of attack alone (27°, the Adir 52°); the real F-16's tone has its own
    conditions (the flight manual's figure 1-50, a picture; not compared).
- Open after the footnote check (§8): the Barak's own engine limits and air start (F110-GE-100, a Block 40 manual) have
  no public source found.
- Open in chapter 3's sources: for the F-35 every emergency procedure (fire, engine failure and restart, electrical
  and flight control failures, out-of-control recovery, alternate gear, ejection envelope).
- Open in chapter 2's sources: the F-16's climb schedules (the performance manual, not public); for the F-35 the climb
  schedule, the approach speeds, the landing technique and the air-refuelling cockpit procedure; the footnote for the
  F-16's exterior inspection names figure 2-4 without its page.
- Owed after chapter 6, the F-16s' pictures: the delayed CCIP's cues, the gun's funnel with a lock, a GPS bomb's HUD
  cues and the helmet's symbols have no shot script. The black ones are taken (§4 "Black captures").
- Found by the black captures, the game's and listed, not changed here: the "start engine" command (213) sent in the
  air runs the start sequence again, so MMC, ST STA, MFD and UFC go off and the displays go dark until it ends.
- Found while writing chapter 6, the game's and listed, not changed here:
  - A GPS bomb's PRE target cannot be set in Modern IAF (avionics-plan.md G4): PRE has a target only when the route
    has a target steerpoint.
  - The CMDS MODE knob of the cockpit has three positions; SEMI, AUTO and BYP are on the key alone.
  - DED DATA and DEPR RET have no switch in the cockpit, and IFF IDENT, HANDOFF and SYS TEST no button.
  - The Adir: `systems.json` says EMER_JETT "drops the external stores" while the code drops the bays' too; JETT_SEL
    moves only. Fixed 2026-11-18: the function bar's SWAP and MENU and the portals' `CNTL>` work (the TFLIR's WIDE /
    SPOT is on its CNTL page).
- Owed after chapter 6, the Adir: a picture of a GPS bomb's helmet cues (no shot script). The TFLIR with video is taken
  (`d_tflir`, `_adir_tflir_shot.gd`, 18 November 2026).
  The SMS and the MENU grid are taken (`d_sms`, `d_menu`); the default layout is `d_pcd`. Not verified in the game: how
  the gun is selected in A-A and A-G, the zoom keys and the cursor keys on the TFLIR, the dispenser's modes on the Adir.
- Fixed 2026-11-18: the TFLIR stayed at NO VIDEO. The display set the TFLIR's page without starting the camera, and
  the FLIR page key refused a page 6 already shown (`player_weapons.gd` `flir_on`). Now picking TFLIR, the key and a
  click on the picture start it (`pcd.gd` `_start_flir`).
- Owed after the game manual, pictures no shot script takes: a holding sign and a direction sign on a taxiway and the
  runway's markings from the threshold (section 5.2), the crash page (section 6.3). The full MFD view is taken
  (`flight_mfd_view`, `_mfd_view_shot.gd`). The review of 18 November 2026 checked the lessons, the
  tower, the Settings, the Loadout rules, setup and the bases against the code; the pilots, Hangar, keys and joystick
  and troubleshooting sections were read with few code checks, and the one-instruction-a-step rule was sampled.
- Found while writing the game manual, the game's and listed, not changed here (read from the code, not run):
  - The Quick-command menu key opens a menu of six blank items in Modern IAF, and the Leave mission key a box with
    no text and blank buttons: `sim_settings.gd` `msgs()` is empty (`shared/terrain/flight_overlay.gd`,
    `shared/mission/render_box.gd`). The manual leaves both out.
  - `keys.json`: record 0 is labelled "Toggle map / cockpit" while Esc opens the pause menu; "Look forward" sends
    the F1 command, so in the cockpit it toggles the HUD-only view; "Drag chute" has a group and no jet a chute.
  - Fixed 2026-11-18: a range lesson's own loadout had no bombs while the lesson asks for two ground kills. Each
    range mission carries its load now ([training.md](training.md) §3.4).
  - `strings_en.json` `shadow_reach_about` says "Far draws…" while the row is an Off / On switch; the fourth
    Antialiasing choice (FSR 2 / MetalFX) has no string key.
  - The Hangar's greyed Ra'am and Baz rows carry no "Coming later" text; the Keys screen's "Reset all" asks no
    confirmation.
  - Fixed 2026-11-18: a range lesson's briefing said "four" ground targets while targets 5 and 6 count too; it
    names the six (`modern-iaf/data/missions/*_range.json`).
  - Docs behind the code: [setup.md](setup.md) §3 says "the four bases" (`data/airbases/` has five files);
    `modern-iaf/README.md` says `./start-modern-iaf` opens "Home"; [cockpit.md](cockpit.md) §5.3 says the take-off
    lessons ring nothing (`kneeboard.gd` rings in every cold-start lesson); [front-end.md](front-end.md) §8 gives
    F12 as the info line (`keys.json`: I-mode); [training.md](training.md) §3's table gives the start-up's time as 120 s
    (the missions: 600).

## 8. The footnotes checked at their sources

Checked 18 November 2026: every footnote of the three jet manuals was read at its cited place. The F-16 flight manual
(T.O. GR1F-16CJ-1) and the avionics manual (T.O. GR1F-16CJ-34-1-1, page scans) were read from their public copies; web
pages were fetched once each. A citation stays only where the source was seen to support the statement.

| manual | uses | confirmed (place fixed) | corrected to the source | downgraded to inferred / open | removed |
|---|---|---|---|---|---|
| F-16I Sufa and F-16D Barak (one text, `f16/`) | 284 | 260 (28) | 24 | 0 | 0 |
| F-35I Adir (`f35i/`) | 130 | 104 (5) | 19 | 6 | 1 |

- The F-16's section 1.2 rows (`f16/systems.json` "does"): 299 checked against the flight manual's section I; 29
  corrected, 144 marked inferred (avionics the section does not describe: the MFD's buttons, the ICP, the CMDS, the
  threat warning, the HUD's remote panel, AVIONIC POWER, the KY-58), 126 agree.
- Corrected in the F-16s, the larger ones: the thrust in SEC (70 to 80 % for the Sufa's engine), the Barak's zoom
  speed, the air start's wording, the trapped fuel's AIR SOURCE positions, the roll rate in CAT III, the arresting
  speeds, the oxygen levers and OXY LOW, the FUSELAGE and FORM lights, the bingo cue; the INS alignment times are the
  simulator manual's.
- The Adir's downgraded: the grips' switch list (sam.gov), the helmet's frames (slideshare, four uses), a lift-off
  speed (WION). Removed: the bay doors' timing. One footnote stays second-hand and says so (Pratt & Whitney's page
  returned no text). The real maximum take-off weight is now 65,918 lb; the sim's own 70,000 lb stays in its data.
- Of the Adir's 104 confirmed, one is the second-hand footnote.
