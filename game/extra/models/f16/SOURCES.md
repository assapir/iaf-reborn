# Detailed F-16D and F-16I Sufa: sources and licence

`f16d.glb` and `f16i.glb` are derived works of the FlightGear F-16 and are licensed under the **GNU GPL, version 2 or
(at your option) any later version**, as their source is. This repository distributes them under GPL-3.0-or-later.

## Source

- FlightGear F-16, https://github.com/NikolaiVChr/f16, commit `ef4f192f06243cf4061c2be794511db0576ac2f9`.
  Its `copyright.txt`: "This copyright notice extends to all files in this Flightgear F-16 package. Copyright (C)
  2023 Erik Hofman [See also the authors.txt file]", GPL version 2 or any later version.
- Authors (its `authors.txt`): Erik Hofman (main author), Nikolai V. Chr. "Leto" (model, effects, pylons), J
  Maverick 16 (3D work: pilot model, stores, cockpit, exterior; liveries), Pensacola (liveries), Martin "Pegasus"
  Schmitt and Prohm "Rama" Snitwong (cockpit textures), Jonathan Redpath, Richard Harrison, Justin "pinto"
  Nicholson and the other contributors listed there.

## Files used

| file in the FlightGear F-16 | used for |
|---|---|
| `Models/f16.ac` | the airframe and its moving parts |
| `Models/nozzle-GE.ac`, `nozzle-GE.png`, `nozzle-ring.png` | the GE F110 nozzle |
| `Models/Cockpit/Main/cockpit.ac` and its textures | the two cockpit tubs |
| `Models/Cockpit/chair/chair.ac` and its textures | the two ejection seats |
| `Models/pilot_externalview.ac`, `Models/Pilots/*` | the two pilots |
| `Models/Liveries/Block40/90-0874.png` | the IAF desert livery (101 Squadron, tail 547) |
| `Models/central-pylon.ac` | the centreline pylon (station E) |
| `Models/F-16.xml`, `Models/Armament/loads_models.xml` | hinge lines, the nozzle's and the centreline pylon's placement, gear and door angles |

## Changes

Made by `tools/f16d/rig.py` (re-runnable; docs/aircraft-models.md):

1. Made two-seat: the canopy and the spine behind it stretched 0.95 m aft, a second tub, seat and pilot.
2. Given the IAF dorsal spine: the large avionics hump of Israel's F-16D Block 30 / 40 ("Brakeet"). It is a new
   mesh made by the script (a loft of rounded-box sections), not taken from FlightGear. It starts at the canopy
   glass's rear edge, at its width and height, and runs level, 0.25 m under the canopy's top, to a box under the fin
   that ends in a round cap just aft of the nozzle. Three vents sit on each side ahead of the fin. FlightGear's fin
   and rudder are lowered 0.27 m onto it and their root fairing squashed to meet them: FlightGear has the fin's root
   level with the canopy's top. FlightGear's blade antenna and formation light are set onto it. Its paint is the
   livery of the fuselage under it, spread over its sides. Shape from:
   - photographs on Wikimedia Commons, used only as references (no image is in the model): IAF F-16D 027 parked,
     side on, by Oren Rozen (CC BY-SA 4.0, https://commons.wikimedia.org/wiki/File:RamatDavid_020517_Barak_02.jpg):
     the spine's top level from the canopy's rear frame to the fin, the canopy's top 0.25 m above it, the vents;
     F-16C 333's tail by Oren Rozen (CC BY-SA 4.0,
     https://commons.wikimedia.org/wiki/File:RamatDavid_020517_Barak_01.jpg): the tail box's round end; F-16C 557 by
     MathKnight and Zachi Evenor (CC BY 4.0,
     https://commons.wikimedia.org/wiki/File:IAF-F-16C-Barak2020--Independence-Day-2017-Tel-Nof-IZE-190.jpg): the
     canopy standing above the fin's root on the single seater too; IAF F-16D 022, 046, 050 and 063 by Aldo Bidini (GFDL 1.2,
     https://commons.wikimedia.org/wiki/File:Lockheed_Martin_F-16D_Barak,_Israel_-_Air_Force_JP7236319.jpg and
     its neighbours JP7236316 / JP7236325 / JP7236336); F-16D 601 by Itayba (CC BY-SA 3.0,
     https://commons.wikimedia.org/wiki/File:IAF_F-16D.jpg). Used only as references; no image is in the model;
   - the model review at https://modelingmadness.com/review/mod/kolbrakeet.htm (the spine runs from the back of
     the canopy past the exhaust, where it becomes the tail extension);
   - the original game model's spine (`f16_h`) set its first shape (until 2026-10-29); its top climbs to the
     canopy's height at the fin, as FlightGear's fin root does, which the photographs above do not show.
3. Given FlightGear's centreline pylon, so a store on station E hangs from it.
4. Placed on the original game model's frame: the wing on the original's wing, the pylons moved onto the
   original's stations (each touching its station), the oleos compressed so the wheels touch where the original's do.
5. The moving parts joined, named and hinged as the game expects; closed gear-door copies added.
6. The cockpit tub, seat and pilot meshes decimated.
7. New maps made from the livery: a panel-line normal map, an occlusion map baked from the model, roughness and
   metallic.
8. The livery's wing roundels set as on IAF F-16s. The livery has one roundel above the left wing near the tip and
   one under the right wing. The script paints over the upper one and copies its art to three places:
   - above each wing, on the fixed panel forward of the flaperon, mid-chord, 43 % of the way from the fuselage side
     to the tip rail, 0.53 m across (0.2 of the local chord);
   - under the left wing, at the mirror image of the livery's roundel under the right wing, which stays.

   Placement from these photographs, used only as references (no image is in the model):
   - above the wings: IAF F-16I 407 and F-16D 998, supplied by the user
     (https://global.discourse-cdn.com/infiniteflight/original/4X/c/f/f/cfff3df65beecdafa031d6c22b4576455e80fc89.jpeg,
     https://global.discourse-cdn.com/infiniteflight/original/4X/c/1/c/c1c0b748011b6162dd14dbc0e467781b2b57685b.jpeg),
     and an IAF F-16I from above by the Israel Defense Forces (CC BY 4.0,
     https://commons.wikimedia.org/wiki/File:Flickr_-_Israel_Defense_Forces_-_IAF_Flight_for_Israel%27s_63rd_Independence_Day_(1)a.jpg);
   - under the wings: IAF F-16D 039 from below, Independence Day 2015, by מינוזיג (CC BY-SA 4.0,
     https://commons.wikimedia.org/wiki/File:F-16_IAF_Israel_Independence_Day_flyover.jpg). It shows a roundel
     under the left wing, just inboard of the outer pylon. The same place under the right wing is hidden by a
     fuel tank.
9. All textures re-encoded as KTX2 (Basis Universal).
10. The livery recoloured to the colours of IAF F-16Ds in service (`barak_livery`; docs/aircraft-models.md): its own
    pattern kept, its brown, sand and pale green made the faded tan, sand and grey-green, down to the strakes, its
    grey kept below; the stabilators' tops camouflaged. Colours measured, each tone against the sand in the same
    light, on F-16D 027 (Oren Rozen) and 601 (Itayba), the photographs of change 2. Used only as references.

The model contains about 60 helper positions measured from the original game model (where the game hangs stores,
draws the afterburner and puts the wheels). They are coordinates only. Every mesh and texture comes from the
FlightGear F-16, except the dorsal spine's mesh, which the script makes (its paint is FlightGear's livery), and,
in `f16i.glb`, the nose fairings and the camouflage, which the script makes too.

## The F-16I Sufa (`f16i.glb`)

Made by `tools/f16d/rig.py ... sufa` (docs/f16i.md §8.1): the F-16D above with these changes.

| file in the FlightGear F-16 | used for |
|---|---|
| `Models/Armament/External-stores/Fueltanks/CFT.ac` | the conformal fuel tanks, at their place in `loads_models-inner.xml` |
| `Models/nozzle-section.ac`, `nozzle-section.png` | the P&W F100 nozzle: 16 sections round the axis, as `nozzle.xml` places them |

1. The GE nozzle replaced by the P&W nozzle (F-16.xml's `PW_nozzle`, 4.617 m aft), its plates at rest.
2. The CFTs added and stretched with the fuselage for two seats, with their own UVs (an unpainted part of the
   livery).
3. The livery (the same FlightGear IAF livery): its underside grey and radome recoloured by the script to the
   F-16I's FS 595 colours; the upper surfaces and the CFTs repainted with our own three-tone camouflage (made by the
   script from noise over the airframe; the livery's panel lines kept); 101 Squadron's fin badge, red disc and
   stripes painted over; our own 107 Squadron orange crescent and a plain round badge (ours) on the fin; the tail
   number 457 made from the livery's own "547", smaller. References, not copied: 107 Squadron's F-16I 827 at the
   IAF Museum, Hatzerim, by Oren Rozen (CC BY-SA 4.0,
   https://commons.wikimedia.org/wiki/File:Hatzerm_131022_Sufa_01.jpg); for the camouflage, an F-16I (876) in
   flight, supplied by the user.
4. Our own nose fairings (meshes made by the script): the AIFF antenna row ahead of the windscreen and a sensor
   blister on each side of the nose. References, not copied: F-16I noses by the IDF Spokesperson's Unit (CC BY-SA
   3.0, https://commons.wikimedia.org/wiki/File:Aviad_Dagan,_May_2021._VIII.jpg and
   https://commons.wikimedia.org/wiki/File:Israeli_attacks_on_Yemen,_January_2025._XIV.jpg).
