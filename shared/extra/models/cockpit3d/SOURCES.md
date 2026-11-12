# The 3D cockpits: sources and licence

`f35i.glb`, `f35i.json` (`tools/f35i/cockpit3d.py --glb`) and `f35i_controls.json` (hand-written; docs/f35i.md §4.5), the F-35I's, are our own.
The rest of this file is the F-16's.

`f16.glb`, `f16.json`, `f16_light.png`, `f16_pilot.glb` and `barak_panels.webp` are derived works of the FlightGear F-16 and are licensed under the
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
| `Models/Pilots/pilot_internalview.ac`, `Tex_0004_1.jpg`, `Tex_0008_1.jpg` | the pilot's body in `f16_pilot.glb` (Modern IAF): legs, arms, gloves, harness and vest, no head |
| `Models/Cockpit/Textures/*`, `Textures/Block-panels/blck50-panels1.png`, `blck40-panels1.png` | the textures; the Block 50 panel sheet in the model (the Sufa's), the Block 40 one in `barak_panels.webp` (the Barak's) |

## Changes

Made by `tools/f16d/cockpit3d.py` (re-runnable; docs/cockpit.md "3D cockpit"):

1. The parts of the Block 50/52 cockpit (`sim/variant-id` 5) placed by FlightGear's offsets; the seat, kneeboards,
   helmet, pilot and the other blocks' HUDs and stick left out.
2. The tub cut at the pilot's eye (the detailed F-16's own tub and seat draw the rest); its side walls and sill
   border (`COCKPIT`, `cockpit_border`) 0.42 m behind it (2026-11-02).
3. The ICP and the stick decimated (about 45 % of their triangles kept; the ICP's four thumbwheels kept whole and
   black, its six round buttons kept whole, 2026-11-09); the consoles and the throttle (2026-11-02)
   their flat faces merged (a planar decimation within 3°), only their parts over 1,600 triangles decimated to 40 %.
4. FlightGear's lamps and off flags hidden as on a powered jet with every lamp off; the needles FlightGear animates
   and the game drives made separate nodes on their hinges, with FlightGear's value tables in `f16.json`. The ICP's SYM
   wheel (2026-11-09) is one, the node `SYM`, the first of the clickable controls in `f16_controls.json` (ours: the
   game's bindings, no FlightGear data); the start-up switches (2026-11-09) are others: `MAIN_PWR`, `JFS`
   (`panels_mlu_left-console`), `AVIONICS_MMC`, `AVIONICS_ST_STA`, `AVIONICS_MFD`, `AVIONICS_UFC`, `INS`
   (`panels_mlu_right-console`) and `THROTTLE` (the throttle's `GRIP`).
5. The DED's and PFD's canvas placeholders replaced by a dark screen (the game draws into them); the rudder pedals made black.
6. Textures larger than 2048 px halved (none: the console sheets, 1024 x 2048, kept whole since 2026-11-02); all re-encoded as KTX2 (Basis Universal); the Block 40 panel sheet as WebP.
7. An altimeter added (FlightGear's comes from FGData, outside the package): the ASI's mount and dial plate copied
   to the altimeter's place, the dial `Models/Cockpit/Textures/faces1.png`'s altimeter face, a needle made by the
   script.
8. FlightGear's duplicate materials merged; the MFD push buttons joined into the body, their centres listed in
   `f16.json`.
9. Two HUDs kept as separate nodes: `hud.xml` (the Barak's) and `f16_war.xml` (the Sufa's).
   The wide-angle HUD (`f16_war_hud.ac`): its frame and box made black; its top left out, so the combiner plate
   stands free between the two side posts as on the F-16I: the lid (`HUDtop`, `screws`, `tissue`), the second glass
   ahead of the combiner and its cover (`BackGlass`, `BackGlassCover`) and `HUDFrame`'s bar over the combiner glass
   (2026-11-02; docs/cockpit.md "3D cockpit"); the glass's rim (`HUDedge`) a 25 % opaque amber glass (a light edge
   strip of ours down each side, 2026-11-09, was removed on 2026-11-12). The glareshield's two slabs beside the HUD
   (`cockpit.ac` `box_left`, `box_right`) left out (2026-11-12). The Block 50 HUD's thick combiner top (`hud.ac` `HUDedge`, opaque light grey) the same glass. Both HUDs keep FlightGear's
   height and place (a raised and widened wide-angle plate, 2026-11-02, was undone the same day) and are made wider
   about their centre line (2026-11-02): the Block 50's ×1.15, the wide-angle one's ×1.12, every part; the wide-angle
   plate's image glass (`HUDImage2`) spans the plate's whole width, its clear rim included (±7.9 cm before widening).
10. The ADI's turn needle moved 3.5 mm and its glide slope index 0.7 mm toward the pilot, in front of the face
    plate (2.8 mm behind it and on its plane in `adi.ac`: hidden); its ILS steering bars kept (FlightGear hides them
    with no ILS in range) and scaled to their stops at the full-scale deviation (`ILS_BARS`).
11. Placed in the detailed F-16's frame (`../f16/SOURCES.md`: 1.05 m aft, under the original model's root).
12. Rounded (2026-11-02): the HUD posts and frames (`hud.ac` `hud_sides`, `f16_war_hud.ac` `HUDFrame`,
    `HUDFrame.001`): every edge sharper than 35° bevelled 3 mm in two segments, the faces shaded smooth.
13. Its ambient occlusion baked in Blender's Cycles (2026-11-02) into `f16_light.png` (2048 px, greyscale) over a
    second UV set of every part but the glasses and screens (`TEXCOORD_1`, a smart UV projection packed over the
    whole cockpit), each texel the more open of its face's two sides.
14. Remodelled (2026-11-02, `hud_posts`, `coaming`): the Block 50 HUD's posts (`hud.ac` `hud_sides`) above the
    glass's foot cut off and replaced by slender tapered posts of ours along the glass's sides, rounded-rectangle
    sections 2.0 × 3.4 cm at the foot, 1.3 × 2.2 cm at the domed top, satin black; the glareshield's (`cockpit.ac`
    `poly`) aft top edge bevelled 1 cm in four segments and shaded smooth.
15. The panel paint lifted (2026-11-02, `lift_paint`): every sheet but the tub's walls, the vents, the stick and
    the glass (the tub's floor sheet `floor.png` too, its painted black footwell shadow made dark grey), linear colour `0.06 + 0.94 · c` (FlightGear's #101010 console plates become #484848, its
    #2D2D2D panel #525252); the Block 40 sheet in `barak_panels.webp` too.
16. The tub's top border under the canopy sills (`cockpit.ac` `cockpit_border`, untextured light grey) made near
    black (2026-11-02).
17. The knobs (2026-11-02, `darken_knobs`): the light grey texels under every knob's and throttle button's UV
    footprint darkened to a fifth (the white index lines and labels kept), in `panels-MLU-right_console.png`,
    `panels-MLU-left_console.png`, `panels-B50-left_right-aux-consoles.png`, `throttle.png`, `temp.zKnob.png` and the
    instruments' sheets, and over the whole of `panels-B50-left_console.png` (its knobs painted on flat panels); the
    left console's untextured rotary knobs (`SW_KNOB_*`) made black, its switch guards
    (`*Guards*`) dark grey; the stick's boot (`F-16-FS.ac` `Grommet`) black.
18. Ours (2026-11-02, `sills`): along each canopy sill a black seal tube and a dark grey rounded lip under it with a
    row of screw heads; the tub's side walls above the consoles (`COCKPIT`'s faces facing in) near black.
19. The pilot's body (`f16_pilot.glb`, `tools/f16d/pilot.py`, 2026-11-09): FlightGear's internal-view pilot as it is
    posed (its pose fits FlightGear's stick, throttle and pedals, which `f16.glb` places where FlightGear does), placed
    as the cockpit; its materials matte (roughness 0.85), the suit's sheet halved to 1024 x 2048, both sheets as JPEG.
    Ours (2026-11-11): the left forearm and glove turned and moved onto the throttle's grip, and two shape keys
    (`throttle_idle`, `throttle_full`) that turn them with the grip over its travel.
