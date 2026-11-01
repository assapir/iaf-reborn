# The F-16's 3D cockpit: sources and licence

`f16.glb`, `f16.json` and `barak_panels.webp` are derived works of the FlightGear F-16 and are licensed under the
**GNU GPL, version 2 or (at your option) any later version**, as their source is. This repository distributes them
under GPL-3.0-or-later.

## Source

- FlightGear F-16, https://github.com/NikolaiVChr/f16, commit `ef4f192f06243cf4061c2be794511db0576ac2f9` (the
  commit of the detailed F-16D, `../f16/SOURCES.md`). Its `copyright.txt`: "This copyright notice extends to all
  files in this Flightgear F-16 package. Copyright (C) 2023 Erik Hofman [See also the authors.txt file]", GPL version
  2 or any later version.
- Authors (its `authors.txt`): J Maverick 16 (3D work: cockpit; block-specific panel layouts; MFD and DED updates),
  Martin "Pegasus" Schmitt and Prohm "Rama" Snitwong (cockpit textures and layout), Nikolai V. Chr. "Leto" (MFD,
  HUD and 3D cockpit changes, CDU, PFD), Jonathan Redpath (cockpit work), Erik Hofman (main author) and the other
  contributors listed there.

## Files used

| file in the FlightGear F-16 | used for |
|---|---|
| `Models/Cockpit/Main/cockpit.xml` | the parts and where they sit (`<offsets>`), which parts the Block 50/52 shows (its conditions), which lamps and flags are off (`select`), how the needles turn (`rotate`) |
| `Models/Cockpit/Main/cockpit.ac` and its textures | the tub and glareshield ahead of the eye |
| `Models/Cockpit/hud.xml`, `hud.ac` | the Barak's HUD and its combiner glass |
| `Models/Cockpit/f16_war.xml`, `f16_war_hud.ac` | the Sufa's: FlightGear's wide-angle HUD and its combiner glass |
| `Models/Cockpit/Avionics/MFD/*` | both MFDs, their screens and 20 push buttons each |
| `Models/Cockpit/Avionics/DED`, `PFD`, `EWS/US_threat_warning_prime.*`, `EWS/rwr.*` | the DED, the small PFD, the RWR head and its control panel (their screens dark) |
| `Models/Cockpit/Panels/icp.*`, `instr.*`, `fuel-qty-sel.*` | the ICP and the small panels |
| `Models/Cockpit/Instruments/*` (ASI, AoA, ADI, VSI, EHSI, fuel flow, standby ADI, compass) | the instruments |
| `Models/Cockpit/Main/engine.*`, `misc.*`, `eyebrow_*.*`, `panels_mlu_*.*` | the engine gauges, the eyebrow lamp panels, the four consoles (decimated) |
| `Models/Cockpit/Main/stick.xml`, `F-16-FS.ac`, `throttle.*`, `rudder_pedals.*` | the stick, throttle and pedals |
| `Models/Cockpit/Textures/*`, `Textures/Block-panels/blck50-panels1.png`, `blck40-panels1.png` | the textures; the Block 50 panel sheet in the model (the Sufa's), the Block 40 one in `barak_panels.webp` (the Barak's) |

## Changes

Made by `tools/f16d/cockpit3d.py` (re-runnable; docs/cockpit.md "3D cockpit"):

1. The parts of the Block 50/52 cockpit (`sim/variant-id` 5) placed by FlightGear's offsets; the seat, kneeboards,
   helmet, pilot and the other blocks' HUDs and stick left out.
2. The tub cut at the pilot's eye (the detailed F-16's own tub and seat draw the rest).
3. The consoles, ICP, throttle and stick decimated (about 40 % of their triangles kept).
4. FlightGear's lamps and off flags hidden as on a powered jet with every lamp off; the needles FlightGear animates
   and the game drives made separate nodes on their hinges, with FlightGear's value tables in `f16.json`.
5. The DED's and PFD's canvas placeholders replaced by a dark screen; the rudder pedals made black.
6. Textures larger than 1024 px halved; all re-encoded as KTX2 (Basis Universal); the Block 40 panel sheet as WebP.
7. An altimeter added (FlightGear's comes from FGData, outside the package): the ASI's mount and dial plate copied
   to the altimeter's place, the dial `Models/Cockpit/Textures/faces1.png`'s altimeter face, a needle made by the
   script.
8. FlightGear's duplicate materials merged; the MFD push buttons joined into the body, their centres listed in
   `f16.json`.
9. Two HUDs kept as separate nodes: `hud.xml` (the Barak's) and `f16_war.xml` (the Sufa's).
10. Placed in the detailed F-16's frame (`../f16/SOURCES.md`: 1.05 m aft, under the original model's root).
