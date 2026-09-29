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
2. **TSD / briefing screen** not built (EMF vector map `menu/emf/82.emf`, briefing window, links, filters, formation).
3. **MFDs** empty (RE in progress → docs/mfd.md).
4. **Terrain detail**: only the level-4 Israel inset (16 m/px); airbase insets (to ~1 m/px) and far levels not used.
5. **Airbase objects**: base missions (`bmisrdvd`: hangars, runway objects…) not placed; no 3D models for them yet.
6. **Mission logic**: triggers/scripts/audio (instructor voice, win sensor) not run.
7. Controls: original default key table not found yet (current keys provisional, G/F confirmed by the briefing).
8. Nose-wheel steering, stall/spin modes, AB light-up delay not ported.

## Plan (in order)
1. ~~Front end rewrite~~ (done; message box comes with the TSD).
2. TSD screen: EMF map converter + briefing window with links (lesson RTF, instructor card).
3. MFDs per docs/mfd.md.
4. Airbase: high-detail insets around the start + base-mission objects (stationary 3D models).
5. Mission runtime for "Engines ON": audio markers, win sensor, success/fail message box (original `mbg*`).
6. Polish: sounds in flight, key table, remaining flight-model modes.

Later (unchanged): see docs/roadmap.md.
