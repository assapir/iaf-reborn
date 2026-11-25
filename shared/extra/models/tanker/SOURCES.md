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
ruddevators) is inferred, by eye. The paint is a plain grey (inferred). Licence: the repository's.

[^boeing46]: <https://www.boeing.com/defense/tankers-and-transports/kc-46-pegasus>
[^w707]: <https://en.wikipedia.org/wiki/Boeing_707>
[^w767]: <https://en.wikipedia.org/wiki/Boeing_767>
[^pat]: <https://patents.google.com/patent/US4129270A/en>
