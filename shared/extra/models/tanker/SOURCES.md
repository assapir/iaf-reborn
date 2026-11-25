# The tankers' models

Our own low-poly models, built by `tools/tanker/build.py` in Blender (no free model was on disk;
[modern-iaf/docs/research/air-refuelling.md](../../../../modern-iaf/docs/research/air-refuelling.md) §8.1). Each has its
refuelling boom as separate nodes (`boom_pivot`, `boom`, `boom_inner`, `nozzle`) and two markers for the pilot director
lights (`pdl_l`, `pdl_r`), which `shared/ai/tanker.gd` moves and lights.

| file | aircraft | dimensions used | source |
|---|---|---|---|
| `kc46.glb` | KC-46A Pegasus (IAF: Gideon), a Boeing 767-2C | 50.5 m long, 47.6 m span, 15.9 m high; the 767's 5.03 m wide fuselage and 31.5° wing sweep; two engines; the boom 57.5 ft at full extension | Boeing, "KC-46 Pegasus" product page[^boeing46]; the 767's body and sweep: Wikipedia, "Boeing 767"[^w767] (taken for the KC-46: inferred) |
| `reem.glb` | Boeing 707-320C (IAF: Re'em) | 46.6 m long, 44.4 m span, 12.9 m high, a 3.76 m wide fuselage, 35° sweep, four engines; the KC-135's boom, 47 ft at full extension | Wikipedia, "Boeing 707"[^w707]; the boom: US Patent 4,129,270[^pat] |

Every shape between those figures (the nose and tail profiles, the nacelles, the tail surfaces, the boom's
ruddevators) is inferred, by eye. Licence: the repository's.

The KC-46A's paint and details were matched in the sim, from the same camera, to US Air Force photographs on Wikimedia
Commons (25 November 2026; reference only, none shipped): in flight from the left[^p-side], refuelling an F-16 from
the front left[^p-f16], from below behind[^p-below], the boom close up[^p-boom] and the boom from an F-16's
cockpit[^p-cockpit]. They show one medium blue-grey all over (sRGB 156, 165, 177 in the model, matched under the sim's
light, a shade darker toward the belly), faint panel lines, door outlines and antennas (an image the build draws on
the fuselage), the radome a shade darker, the dark flight deck windows, bare-metal inlet lips, bronze exhaust cones, a
yellow line on the belly up to the boom operator's camera fairing; the boom's faired root, its grey tube, the darker V
ruddevators near its end, the pale yellow-green telescope with red, orange and yellow bands next to the tube, and the
bare-metal nozzle assembly. Inferred: the IAF roundels (`tools/eitam/markings.png`, ours) where the USAF star sits and
on the wings (no photograph of an IAF KC-46A was found), the bands' places along the telescope, the panel lines' and
doors' places. The Re'em has the same details in its own grey.

[^boeing46]: <https://www.boeing.com/defense/tankers-and-transports/kc-46-pegasus>
[^w707]: <https://en.wikipedia.org/wiki/Boeing_707>
[^w767]: <https://en.wikipedia.org/wiki/Boeing_767>
[^pat]: <https://patents.google.com/patent/US4129270A/en>
[^p-side]: "KC-46 Pegasus prepares to refuel C-17 (cropped)", US Air Force, public domain:
  <https://commons.wikimedia.org/wiki/File:KC-46_Pegasus_prepares_to_refuel_C-17_(cropped).jpg>
[^p-f16]: "Boeing KC-46A Pegasus of the 916th ARW refuels a General Dynamics F-16C of the 309th FS on 3 November
  2023", US Air Force, public domain:
  <https://commons.wikimedia.org/wiki/File:Boeing_KC-46A_Pegasus_of_the_916th_ARW_refuels_a_General_Dynamics_F-16C_of_the_309th_FS_on_3_November_2023_(231103-F-RL243-9102).JPG>
[^p-below]: "190129-F-ZZ999-002", US Air Force, public domain: <https://commons.wikimedia.org/wiki/File:190129-F-ZZ999-002.JPG>
[^p-boom]: "USAF KC-46A Pegasus Refuels RAAF F-35 Lightning", US Air Force, public domain:
  <https://commons.wikimedia.org/wiki/File:USAF_KC-46A_Pegasus_Refuels_RAAF_F-35_Lightning_(7951709).jpg>
[^p-cockpit]: "KC-46 refuels 480th EFS F-16s during NATO air policing operations", US Air Force, public domain:
  <https://commons.wikimedia.org/wiki/File:KC-46_refuels_480th_EFS_F-16s_during_NATO_air_policing_operations_(7178389).jpg>
