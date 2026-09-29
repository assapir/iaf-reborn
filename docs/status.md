# Status — checkpoint 1 (+ front end)

Goal of milestone 1: **start the game → Training → Basic → "Engines ON" (311) → brief/TSD → fly the takeoff
from Ramat David** in the original F-16 with the original 2D cockpit, everything extracted from the original data.

## Done (working, committed)
| area | state |
|---|---|
| **Pipeline** | `tools/setup.sh <ISO> [Brief.zip Menu.zip]` builds everything from the user's CD image |
| Install extraction | ISO 9660 + EA `setup.esa` (PKWARE DCL) → `assets/install` (docs/formats/esa.md) |
| Aircraft models | DirectX `.x/.xfr` → glTF, Lanczos 4× textures, optional smoothing (docs/formats/x.md) |
| Moving parts | gear/flaperons/stabs/rudder/speed brakes, original hinge rules & ranges (docs/part-animation.md) |
| Terrain | `map.ptt` imagery + LZO heights, chunk streaming in Godot, **original georeference** (engine metres, PlaneScale 1.2411) (docs/formats/ptt.md) |
| Flight model | Rust port of the original model (docs/flight-model.md), ground-roll mode, **original / real data sets** (Preferences), validation suite vs public F-16 data |
| Cockpit | original 2D F-16 panel from `cockpit.ibx`, gauges, ADI, standby horizon, conformal HUD with original HUD font, zoom / panel slide, cockpit + external views |
| Front end | rewritten to docs/front-end.md: original button states & press animation, panel slides + clips, title tab animation, BACK/MAIN/QUIT, list rows from `mis_1`/`mis_2` with hover-by-button, Arial text & colours, sounds + music, full navigation tables (training + campaigns), Jet list with per-mission jet locks, wait screen; Hebrew via the community packs |
| Briefings | RTF → BBCode (EN + HE pack), `.brl` link lists, diagrams (converted, not displayed yet) |
| Missions | `.mis` / `.bdb` parser (131/131), mission list, **mission start at Player1's position** (takeoff = Ramat David rwy 15) (docs/formats/mis.md) |

## Known gaps / wrong vs. the original (from the RE specs)
1. **Front end leftovers**: no message box yet (TSD quit confirm, QUIT), mission prerequisites not enforced
   (no pilot records), Jump In / Mission Creator / Reference / Multiplayer / original Preferences pages are
   navigable art only. Only the F-16 is flyable (other jets shown disabled); campaign missions start in the F-16.
2. **TSD leftovers**: 3D-model (obj_t) and target (targ_t) link windows, waypoint dragging, selected-unit label,
   click-to-select / double-click-to-fly, Arming screen content, map drag cursors. (Map, units, flights,
   waypoints, zoom, scrollbars, briefing + lesson + card windows, filters, msg boxes are done.)
3. **MFD leftovers**: radar contacts / lock / STT, radar MAP (isr.bmp) and GMT content, RWR threats, HARM / TV /
   FLIR content, full-screen weapon MFD, NAV distances / ETA, stores stations. Initial radar mode and range are not
   traced (LRS, 20 NM used). Original keys S (radar standby) and W (next waypoint) clash with our provisional throttle
   keys, so they are not bound yet. (Done: all cockpits converted, MFD placement / default pages per cockpit ini,
   radar / TSD / RWR / MENU / NAV / stores / damage / ADI pages, OSB clicks, T / D / Q / R / . / , keys.)
4. **Terrain detail**: airbase insets (levels 0–2, ~1.24 m/px) are streamed as detail tiles within 6 km (149 tiles); the level-3 regions outside airbases, insets outside the level-4 Israel rect (e.g. x < 327680) and the far theatre levels are not used yet.
5. **Mission objects**: every visible entity of the mission + base missions is placed with its original model (bdb object → Present record → `.x`, `iaf-convert objects`, 219 models). Open: whether ground objects are snapped to the terrain or use their altitude (same here), level-of-detail models (`_m`), damage states, ground-object shadows.
6. **Mission logic**: triggers/scripts/audio (instructor voice, win sensor) not run.
7. Controls: original default key table not found yet (current keys provisional, G/F confirmed by the briefing).
8. Nose-wheel steering, stall/spin modes, AB light-up delay not ported.
9. Gear lever: ground / 300 kt rules enforced; leg timing (2 s), gear sound and weapon-release lock not yet (docs/flight-model.md §12).
10. Sun shadow is coarse near the aircraft (one 2 km shadow range), so the shadow looks detached from the wheels.
11. g reads 0.8–0.9 when parked (should be 1.0).
12. No ground effect (not in the original model either). Decided: add it later behind a separate "better physics" option, not in the "real data" set.
13. Cockpit lights not drawn (gear lights, warning lights; docs/cockpit.md lists the light bitmaps).

## Plan (in order)
1. ~~Front end rewrite~~ (done; message box comes with the TSD).
2. ~~TSD screen~~ (done; leftovers in gaps).
3. ~~MFDs~~ (done; leftovers in gaps).
4. ~~Airbase~~ (done: detail tiles + mission objects).
5. Mission runtime for "Engines ON": audio markers, win sensor, success/fail message box (original `mbg*`).
6. Polish: sounds in flight, key table, remaining flight-model modes.

Later (unchanged): see docs/roadmap.md.
