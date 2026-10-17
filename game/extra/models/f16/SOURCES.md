# Detailed F-16D: sources and licence

`f16d.glb` is a derived work of the FlightGear F-16 and is licensed under the **GNU GPL, version 2 or (at your
option) any later version**, as its source is. This repository distributes it under GPL-3.0-or-later.

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
   mesh made by the script (a loft of rounded-box sections), not taken from FlightGear. It runs straight from the
   back of the canopy to the foot of the fin, goes on as a box under the fin and ends square just aft of the nozzle.
   FlightGear's blade antenna and formation light are raised onto it. Its paint is the livery of the fuselage under
   it, spread over its sides. Shape from:
   - photographs on Wikimedia Commons: IAF F-16D 022, 046, 050 and 063 by Aldo Bidini (GFDL 1.2,
     https://commons.wikimedia.org/wiki/File:Lockheed_Martin_F-16D_Barak,_Israel_-_Air_Force_JP7236319.jpg and
     its neighbours JP7236316 / JP7236325 / JP7236336); F-16D 601 by Itayba (CC BY-SA 3.0,
     https://commons.wikimedia.org/wiki/File:IAF_F-16D.jpg). Used only as references; no image is in the model;
   - the model review at https://modelingmadness.com/review/mod/kolbrakeet.htm (the spine runs from the back of
     the canopy past the exhaust, where it becomes the tail extension);
   - the original game model's spine (`f16_h`), whose top profile it follows (0.12 m lower, to meet FlightGear's
     lower canopy and fin root).
3. Given FlightGear's centreline pylon, so a store on station E hangs from it.
4. Placed on the original game model's frame: the wing on the original's wing, the pylons moved onto the
   original's stations (each touching its station), the oleos compressed so the wheels touch where the original's do.
5. The moving parts joined, named and hinged as the game expects; closed gear-door copies added.
6. The cockpit tub, seat and pilot meshes decimated.
7. New maps made from the livery: a panel-line normal map, an occlusion map baked from the model, roughness and
   metallic.
8. All textures re-encoded as KTX2 (Basis Universal).

The model contains about 60 helper positions measured from the original game model (where the game hangs stores,
draws the afterburner and puts the wheels). They are coordinates only. Every mesh and texture comes from the
FlightGear F-16, except the dorsal spine's mesh, which the script makes (its paint is FlightGear's livery).
