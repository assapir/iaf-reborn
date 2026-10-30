# Detailed stores: sources and licence

The `.glb` files in this folder are derived works of FlightGear aircraft and keep their source's licence, but for our
own (below):

- the F-16's stores (most files): the **GNU GPL, version 2 or (at your option) any later version**; this repository
  distributes them under GPL-3.0-or-later;
- the Soviet stores (`aa2`, `aa8`, `aa10`, `aa11`, `mig29ftk`): the **GNU GPL, version 3**, as the MiG-21bis and the
  MiG-29 9-12 are (their `License.txt` / `LICENSE`: the GPL 3.0 text).

## Source

- FlightGear F-16, https://github.com/NikolaiVChr/f16, commit `ef4f192f06243cf4061c2be794511db0576ac2f9`.
  Its `copyright.txt`: "This copyright notice extends to all files in this Flightgear F-16 package. Copyright (C)
  2023 Erik Hofman [See also the authors.txt file]", GPL version 2 or any later version.
- Authors (its `authors.txt`): J Maverick 16 (research, addition and 3D work of the weapons, stores and pods),
  Nikolai V. Chr. "Leto" (pylons and missile code), Erik Hofman (main author), Pensacola (liveries) and the other
  contributors listed there.

- FlightGear MiG-21bis (OPRF), https://github.com/l0k1/MiG-21bis, commit `9ca6f5b739aecb8d662ab89f7c73ff2203584c05`.
  Licence: its `License.txt`, GPL 3.0. Authors (its `MiG-21bis-set.xml`): Petar Jedvaj, David Culp, Raptor, Stuart
  Cassie, Gary Brown, Brendan Black, bugman, Tomaskom, Steve Brown, JMav-16, NikolaiVChr, Kokos, Rudolf339, alaxeijd,
  Colin Geniet, AxelPaccalin, Josh (Octal450) and pinto.
- FlightGear MiG-29 9-12, https://github.com/Mercenary-Mercury/MiG-29_9-12, commit
  `d4a299bf88412f579b2067874989a8088b2f6d66`. Licence: its `LICENSE`, GPL 3.0. Authors (its `MiG-29_9-12-set.xml`):
  Sergey "Mercenary_Mercury" Salov (FDM, cockpit, submodels, systems; the stores are its submodels), Enrique Laso Leon
  (external model).

## Files used

Under `Models/` in the FlightGear F-16, unless the row names another aircraft.

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
| `aim9x.glb` | AIM-9X (ours, the F-16I Sufa's) | `Armament/Weapons/AIM-9X/AIM-9X.ac`, `AIM-9X.png` |
| `gbu31.glb` | GBU-31, GBU-31(V)3 (the Sufa's) | `Armament/Weapons/GBU-31/GBU-31.ac`, `GBU-31.png` |
| `gbu38.glb` | GBU-38 (the Sufa's) | `Armament/Weapons/GBU-54/GBU-54.ac`, `GBU-54.png` (the laser JDAM's look) |
| `gbu32.glb` | GBU-32 (ours) | `Armament/Weapons/GBU-31/GBU-31.ac`, `GBU-31.png`, scaled to the GBU-32's length |
| `gbu31v3.glb` | GBU-31(V)3 (ours, the BLU-109's) | `Armament/Weapons/GBU-31/GBU-31.ac`, `GBU-31.png`, slimmer to the BLU-109's girth |
| `aa2.glb` | AA-2 (and the "Rockets" record, which shares its model) | MiG-21bis: `Models/Stores/R-3S/r-3s.ac`, `r-3s.png` |
| `aa8.glb` | AA-8 | MiG-29 9-12: `Models/Submodels/R-60M/R-60M.ac`, `R-60M.png` |
| `aa10.glb` | AA-10 | MiG-29 9-12: `Models/Submodels/R-27R/R-27R.ac`, `R-27R.png` |
| `aa11.glb` | AA-11 | MiG-29 9-12: `Models/Submodels/R-73/R-73.ac`, `R-73.png` |
| `mig29ftk.glb` | the MiG-29's 3500 lb centreline tank | MiG-29 9-12: `Models/Submodels/PTB-1500/PTB-1500.ac`, `PTB-1500.png` |

## Changes

Made by `tools/stores/build.gd` (re-runnable; docs/aircraft-models.md §5):

1. Scaled and placed on the original game model of the store it stands in for: its length on the original's
   length (the Sufa's AIM-9X, GBU-31 and GBU-38: at the scale of the AIM-9M / MK-84 / MK-82 fitted so, their real size),
   its axis on the original's axis (the tanks and pods: their top on the original's top, where the pylon
   meets it). The laser bombs keep their bomb's girth and so are longer than the original's.
2. MK-83L and MK-84L made from the plain bomb: its fuze, tail fins and arming wire removed, the GBU-12's Paveway II
   guidance section put on its nose and its tail kit (scaled to the bomb's girth) on its tail (a GBU-16 / GBU-10
   look; inferred).
3. CBU-87: the submunitions inside left out and the mesh simplified from 23 500 to about 4 900 triangles.
4. The 300 gal tank's own pylon left out. The tanks' paint is cut out of the IAF Block 40 livery (the texture the
   F-16D uses) to the part the tank's faces use.
5. The seeker glass and lenses (see-through in FlightGear) made opaque dark glass.
6. Every face drawn from both sides (as FlightGear marks them), smooth normals within each object's crease angle,
   one mesh per store, textures re-encoded as JPEG (512 px or less; the Soviet missiles keep their 1024 × 512).
7. The AA-2, AA-8, AA-10 and AA-11 textures (white, with no baked shading) given a light grey paint factor
   (ours, set by eye).

The Arming screen icons in `game/extra/weapons/arm/` are renders of these models (`tools/stores/icons.gd`) under
the same licence.

## Our own

`pyth5.glb`, `gbu39.glb`, `bru61.glb`, `popeye.glb`, `spice1000.glb`, `spice2000.glb` and `spikenlos.glb` are ours,
made by `tools/stores/build.gd` from the shapes in `tools/stores/ours.gd` (no third-party mesh or texture), under the
repository's licence (GPL-3.0-or-later). Their sizes come from these sources; the rest is measured by eye on the
photos (inferred):

- Python 5: 3.1 m, 160 mm, 640 mm span: Wikipedia, "Python (missile)", https://en.wikipedia.org/wiki/Python_(missile);
  photos: Wikimedia Commons, Category:Python-5 ("Python5 missile.jpg", "Python-5-missile-0004.jpg"),
  https://commons.wikimedia.org/wiki/Category:Python-5
- GBU-39: 1.80 m, 190 mm: Boeing, "Small Diameter Bomb" product card,
  https://www.boeing.com/content/dam/boeing/boeingdotcom/defense/weapons-weapons/images/small_diameter_bomb_product_card.pdf;
  BRU-61/A 143 × 16 × 16 in: the same card; photos: Commons, Category:GBU-39 Small Diameter Bomb ("BRU-61+4xGBU-39.jpg",
  "Boeing GBU-39 Small Diameter Bomb.jpg", "SDB3.jpg"), https://commons.wikimedia.org/wiki/Category:GBU-39_Small_Diameter_Bomb
- Popeye: 4.82 m, 533 mm, 1.98 m span: Wikipedia, "Popeye (missile)", https://en.wikipedia.org/wiki/Popeye_(missile),
  and FAS, "AGM-142 Have Nap", https://man.fas.org/dod-101/sys/smart/agm-142.htm; photo: Commons "Popey missile.jpg",
  https://commons.wikimedia.org/wiki/Category:Popeye_(missile)
- SPICE 1000 / 2000: the Mk 83 / Mk 84 bodies they fit (Rafael's SPICE brochure, https://omnirole-rafale.com/wp-content/uploads/2019/10/Spice.pdf),
  12 control surfaces in three groups (Wikipedia, "Spice (bomb)", https://en.wikipedia.org/wiki/Spice_(bomb)); photos:
  Commons "ILA Berlin 2012 PD 035.JPG" and "Spice bomb front.JPG"; their lengths are open (inferred from the photos)
- Spike NLOS: 1.7 m: Janes, "Rafael unveils sixth-generation Spike NLOS",
  https://www.janes.com/defence-news/rafael-unveils-sixth-generation-spike-nlos; photo: Commons "Spike NLOS Missile
  FSMU (ADAS 2016).jpg", https://commons.wikimedia.org/wiki/Category:Spike_NLOS; its diameter is open

The photos were looked at only; none is in the repository.

Every FlightGear-derived mesh and texture comes from the FlightGear aircraft above. The placement uses only measurements of the original models
(their lengths, axes and tops); no original game data is in these files.
