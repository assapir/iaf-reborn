# The briefing's drawings

The jets' front views (until 2026-11-14 the briefing's Arming page; the Loadout screen shows the jet from beneath,
modern-iaf/docs/front-end.md §10.1, so no screen shows the pictures now), each traced from our own model by
`modern-iaf/tests/_jet_fronts.gd` (an orthographic front render coloured by the surfaces' normals, its edges as light
lines); `<jet>_front.json` places the F-16 stations on it (the model's hardpoints, sim.rs `F16_SIM_STATIONS`). The
JSON is in use: `briefing::arming` reads each station's distance from the jet's middle from it (the wings' balance).

| file | model | licence |
|---|---|---|
| f16i_front.png | `shared/extra/models/f16/f16i.glb` (the Sufa: two seats, conformal tanks, the dorsal spine) | GPL 2.0 or later (the FlightGear F-16, `shared/extra/models/f16/SOURCES.md`) |
| f16d_front.png | `shared/extra/models/f16/f16d.glb` (the Barak) | GPL 2.0 or later (the same) |
| f35i_front.png | `shared/extra/planes/f35i/f35i.gltf` (the Adir; geometry only, no texture) | CC BY 4.0, "Lockheed Martin F35 Lightning II" by andertan (`shared/extra/planes/f35i/CREDITS.md`) |
