# Mission Creator files (`MCR\<mission name>`)

The Mission Creator (docs/front-end.md §19) keeps its choices in one global record, `DAT_0083ca10`, 0x5ac (1452)
bytes. SAVE writes that record to a file unchanged and LOAD reads a file back into it, so a Mission Creator file is a
raw copy of the record. There is no header, signature or version. The port reads and writes the same bytes, so files
saved by the original load in the port and the other way round (`crates/iaf-formats/src/mcr.rs`).

## Where the files are

* The original (`FUN_004fae70`): `<folder of iafjets.exe>\MCR\<mission name>`. The file name is the MISSION NAME
  text as typed, with no extension (`_makepath` with no extension, `FUN_00569940`).
* The port: `user://mcr/<mission name>` (the Godot user data folder; tests use a temporary folder). Put files from
  the original there to load them.

## Layout

All numbers are little-endian 32-bit signed integers. Every choice is the item index of its combo box on the screen
(the lists are below).

| offset | size | field | values |
|---|---|---|---|
| 0x000 | 0x100 | MISSION NAME | ANSI text, NUL-terminated |
| 0x100 | 0x400 | NOTES | ANSI text, NUL-terminated |
| 0x500 + 0x10·i | 4 | formation i: No | 0..2 jets |
| 0x504 + 0x10·i | 4 | formation i: TYPE | type index |
| 0x508 + 0x10·i | 4 | formation i: AI TYPE | AI index |
| 0x50c + 0x10·i | 4 | formation i: base | a copy of BASE |
| 0x580 | 4 | BASE | 0 Tel Nof, 1 Ramat David, 2 Ramon |
| 0x584 | 4 | TIME | 0 Noon, 1 Dawn, 2 Sunset, 3 Night |
| 0x588 | 4 | STARTING ALT. | 0 Runway, 1 5000ft, 2 10000ft, 3 15000ft |
| 0x58c | 4 | TARGET | 0 No Target, 1 Bunker, 2 Armored Column, 3 Radar Station, 4 Terrorists Camp |
| 0x590 | 4 | SAMS | 0..3 |
| 0x594 | 4 | AAA | 0..3 |
| 0x598 | 4 | WEAPONS | 0 Guns Only, 1 Multipurpose, 2 Air To Air |
| 0x59c | 4 | VICTORY CONDITION | 0 By Kills, 1 By Target |
| 0x5a0 | 4 | multiplayer: re-entries | 0 No Revive, 1 1 Time, 2 2 Times, 3 3 Times, 4 Unlimited |
| 0x5a4 | 4 | multiplayer: wait | 0 0 Seconds, 1 10 Seconds, 2 20 Seconds |
| 0x5a8 | 4 | multiplayer: re-entry weapons | 0 Reload, 1 Current |

* Formations i = 0..3 are Alpha, Bravo (Blue Force) and Charlie, Delta (Red Force). Formations 4..7 belong to the
  multiplayer screen; single player only writes their base copy.
* A change of BASE copies the base into all eight formation records (`FUN_004fb180`).
* The text fields hold what the edit boxes accept: space, `.`, digits and Latin letters (the edit class's WM_CHAR,
  `FUN_004f1da0`). Bytes after the NUL are whatever the buffer held before; the port writes zeros.

TYPE indexes (`.data 0x652648`, 10 bytes each): 0 F-15, 1 F-16, 2 F-4 E, 3 F-42000, 4 Lavi, 5 Kfir, 6 Mirage,
7 MiG-23, 8 MiG-29, 9 A-4 N, 10 MiG-17, 11 MiG-21, 12 MiG-25, 13 Su-22, 14 Su-24, 15 Tu-22. Alpha's list holds the
first 9 (the jets a player can fly); the other formations' lists hold all 16 (`FUN_004fa450`).

AI TYPE indexes (`.data 0x6526f8`, 11 bytes each): 0 Aggressors, 1 Defenders, 2 Bombers, 3 Kamikaze, 4 Aces. The Blue
lists hold the first four, the Red lists the first two. Index 4 can only come from RANDOM, which draws 0..4.

## Reading and writing

* **SAVE** (`FUN_004fae70`) first takes the texts from the two edit boxes. An empty name shows msg 49 "You should
  enter the mission name before saving." If the file exists, msg 46 "Mission already exists. Do you want to replace
  it?" (Yes / No) asks first. Then it writes the 0x5ac bytes.
* **LOAD** (`FUN_004facb0`) opens the Windows file dialog titled "Open Mission" in the `MCR` folder, with the file
  name `*` and no filter. It reads 0x5ac bytes from the chosen file. A shorter file shows "Bad misison file" (sic),
  and the record keeps the bytes read so far. The screen then shows the record (`FUN_004fafb0`).
* The port refuses a file shorter than 0x5ac bytes and keeps the screen as it was.

## Ours: the wind and weather trailer

With Extras "Mission Creator: Better" on (front-end.md §19.4) the port's SAVE writes 16 more bytes after the record:

| offset | size | field | values |
|---|---|---|---|
| 0x5ac | 4 | tag | `IAFW` |
| 0x5b0 | 4 | WIND | knots: 0, 10, 15, 20 |
| 0x5b4 | 4 | FROM | degrees true: 0, 45 … 315 |
| 0x5b8 | 4 | WEATHER | 0 Default (no weather of its own), 1 Clear, 2 Light rain, 3 Heavy rain, 4 Random |

A trailer saved before the weather ends at 0x5b8 and loads as Default.

The record itself has no free bytes (the text buffers' tails hold whatever the exe's buffer held), so the trailer goes
after it. The original's LOAD reads exactly 0x5ac bytes (`ReadFile`) and ignores the rest, so it loads these files;
its SAVE creates the file anew (`CREATE_ALWAYS`) and drops the trailer. With the switch off the port writes the
original's 0x5ac bytes and its LOAD ignores a trailer.
