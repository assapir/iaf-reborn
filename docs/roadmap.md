# Roadmap notes

## Later
- **High-detail F-16 model** to replace the 1998 mesh (~800 triangles): candidate is FlightGear's F-16 (check the licence) or a CC-licensed model. Keep the original dimensions, hinge points (`<part>1/2` helpers), weapon stations, camera eye point and IAF markings; fit it and repaint onto the new UVs.
- v1.1 patch (RTPatch): extract `bdgen.dat`, fixed missions, `msgs.trx` / `credits.trx`.
- **Better satellite imagery**: after georeferencing, optional modern imagery pack (e.g. Sentinel-2, 10 m/px, free) layered over the 1998 photos; optionally modern DEM (SRTM/Copernicus 30 m) for finer relief.
- **3D virtual cockpit** (after the original 2D cockpit works), together with the high-detail F-16 model.
- **Validate the F-16 flight data** against public sources: USAF fact sheet / RTF reference card, NASA TP-1538
  (F-16 wind-tunnel aero data, used by JSBSim), JSBSim/FlightGear F-16, engine thrust data (F100-PW-220/229,
  F110-GE-100/129), E-M diagrams. Automated checks in `iaf-flight`: max level speed (SL, 40k ft), sustained /
  instantaneous turn at corner speed, roll rate, climb, stall/approach speeds, fuel burn. Report deviations; let the
  user choose "faithful 1998" vs "realistic" per item (or a setting).

## "Better physics" option (separate from original / real data)
Improvements over the 1998 model that the player can opt into, decided case by case with the user:
- Ground effect.
- 1 g hold on the flight path instead of the nose pitch (no slow dive at high speed) — **done** (`better_physics`).
