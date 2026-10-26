# Detailed stores: sources and licence

The `.glb` files in this folder are derived works of the FlightGear F-16 and are licensed under the **GNU GPL,
version 2 or (at your option) any later version**, as their source is. This repository distributes them under
GPL-3.0-or-later.

## Source

- FlightGear F-16, https://github.com/NikolaiVChr/f16, commit `ef4f192f06243cf4061c2be794511db0576ac2f9`.
  Its `copyright.txt`: "This copyright notice extends to all files in this Flightgear F-16 package. Copyright (C)
  2023 Erik Hofman [See also the authors.txt file]", GPL version 2 or any later version.
- Authors (its `authors.txt`): J Maverick 16 (research, addition and 3D work of the weapons, stores and pods),
  Nikolai V. Chr. "Leto" (pylons and missile code), Erik Hofman (main author), Pensacola (liveries) and the other
  contributors listed there.

## Files used

All under `Models/` in the FlightGear F-16.

| our file | stands in for (the game's store) | FlightGear files |
|---|---|---|
| `aim9.glb` | AIM-9D / L / M, the SA-13's missile | `Armament/Weapons/AIM-9M/AIM-9M.ac`, `AIM-9M.png` |
| `aim7.glb` | AIM-7B / F / M, Shrike | `Armament/Weapons/AIM-7/AIM-7F.ac`, `AIM-7F.png` |
| `aim120.glb` | AMRAAM | `Armament/Weapons/AIM-120/AIM-120B.ac`, `AIM-120B.png` |
| `agm65.glb` | AGM-65 | `Armament/Weapons/AGM-65D/AGM-65D.ac`, `AGM-65D.png` |
| `agm88.glb` | AGM-88 | `Armament/Weapons/AGM-88/AGM-88.ac`, `AGM-88.png` |
| `mk82.glb`, `mk83.glb`, `mk84.glb` | MK-82, MK-83, MK-84 | `Armament/Weapons/MK-82/MK-82.ac`, `MK-83/MK-83.ac`, `MK-84/MK-84.ac` and their `.png` |
| `mk82lb.glb` | MK-82L | `Armament/Weapons/GBU-12/GBU-12.ac`, `GBU-12.png` |
| `mk83lb.glb`, `mk84lb.glb` | MK-83L, MK-84L | the MK-83 / MK-84 above with the GBU-12's guidance and tail kits |
| `cbu87.glb` | CBU-87, CBU-97 | `Armament/Weapons/CBU-87/CBU-87.ac`, `CBU-87.png` |
| `f16ftk.glb` | the F-16's 2700 lb (370 gal) wing tank | `Armament/External-stores/Fueltanks/370G.ac`, `Liveries/Block40/90-0874.png` |
| `f16ftkm.glb` | the F-16's 2100 lb (300 gal) centreline tank | `Armament/External-stores/Fueltanks/300G.ac`, `Liveries/Block40/90-0874.png` |
| `ecmpod.glb` | ECM pod | `Armament/External-stores/AN_ALQ-131/AN_ALQ-131.ac`, `AN_ALQ-131.png` |
| `flrpod.glb` | FLIR pod | `Armament/External-stores/LANTIRN/AN-AAQ-13.ac`, `AN-AAQ-13.png` |

## Changes

Made by `tools/stores/build.gd` (re-runnable; docs/aircraft-models.md §5):

1. Scaled and placed on the original game model of the store it stands in for: its length on the original's
   length, its axis on the original's axis (the tanks and pods: their top on the original's top, where the pylon
   meets it). The laser bombs keep their bomb's girth and so are longer than the original's.
2. MK-83L and MK-84L made from the plain bomb: its fuze, tail fins and arming wire removed, the GBU-12's Paveway II
   guidance section put on its nose and its tail kit (scaled to the bomb's girth) on its tail (a GBU-16 / GBU-10
   look; inferred).
3. CBU-87: the submunitions inside left out and the mesh simplified from 23 500 to about 4 900 triangles.
4. The 300 gal tank's own pylon left out. The tanks' paint is cut out of the IAF Block 40 livery (the texture the
   F-16D uses) to the part the tank's faces use.
5. The seeker glass and lenses (see-through in FlightGear) made opaque dark glass.
6. Every face drawn from both sides (as FlightGear marks them), smooth normals within each object's crease angle,
   one mesh per store, textures re-encoded as JPEG at 512 px or less.

Every mesh and texture comes from the FlightGear F-16. The placement uses only measurements of the original models
(their lengths, axes and tops); no original game data is in these files.
