# The world -> TSD map frame (FUN_00500ec0) and the SAM rings, shared by the front end's TSD (menu/tsd.gd), the
# cockpit's map and the stores' SAM threat list.
extends RefCounted

## World -> map: X shift = DataXShiftPR, Y shift, width / height of the world.
const WORLD_X_SHIFT := 166850.0
const WORLD_Y_SHIFT := 21144.0
const WORLD_W := 819200.0
const WORLD_H := 1064960.0
const MAP_X_FACTOR := 1.0071394
## SAM ring radius (world units) by type code (class 8).
const SAM_RING := {290: 37080.0, 340: 37080.0, 300: 16686.0, 320: 22248.0}
