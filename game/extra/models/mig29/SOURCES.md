# Detailed MiG-29: source and licence

`mig29.glb` is a derived work of the FlightGear MiG-29 9-12 and is licensed under the **GNU GPL, version 3**, as its
source is (its `LICENSE`: the GPL 3.0 text).

## Source

- FlightGear MiG-29 9-12, https://github.com/Mercenary-Mercury/MiG-29_9-12, commit
  `d4a299bf88412f579b2067874989a8088b2f6d66`. Authors (its `MiG-29_9-12-set.xml`): Enrique Laso Leon (external
  model), Sergey "Mercenary_Mercury" Salov (FDM, cockpit, submodels, systems).
- Files used (under `Models/`): `MiG-29.ac`, `MiG-29_1.png`, `MiG-29_2.png` (the default livery),
  `Submodels/Pilot/fighter_pilot_proto.ac` and `.png`, `Submodels/K-36DM/K-36DM.ac` and `.png`. Each is pinned by its
  SHA-256 in `crates/iaf-tools/src/mig29.rs` (`SOURCE`).

## Changes

Made by `iaf-convert mig29-detailed <src dir> <assets>/converted/planes/mig29 game/extra/models/mig29/mig29.glb`
(`crates/iaf-tools/src/mig29.rs`; docs/aircraft-models.md §7):

- scaled by 0.997 to the original model's length and placed on it (its middle, its main wheels on the original's
  `height`); the pilot and K-36DM seat added at the FlightGear cockpit's offsets;
- the moving parts split and named as the original's, hinged on `MiG-29.xml`'s lines; the gear doors opened by
  its angles (`LdgDr`) and kept shut (`LdgDrUp`);
- left out: the mirrors inside the canopy and the side numbers;
- repainted: FlightGear's grey-green camouflage and side-number panels become our two-tone grey (light and dark
  grey above by our pattern, light grey below); the red stars become the Syrian roundel on the wings and the
  Syrian flag on the fins (our drawings, in the converter);
- added, our own: nine pylons from the original's stations up to the skin (shaped as the real jet's three a wing,
  the outermost a stub), and the drag chute (`Parach`, an orange
  cone at the original chute's place).
