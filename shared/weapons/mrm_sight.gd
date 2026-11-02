# The HUD objects of the radar missiles (HUD mode 2, MRM) and the HARM (mode 8; docs/weapons.md §11): the launch
# circle, the predicted point, the in-circle tests and q. The logic is iaf_avionics::sight
# (crates/iaf-avionics/src/sight.rs) through IafMrmSight. Screen offsets are original 640x480 pixels from the HUD
# centre (ir_seeker.gd `screen_offset`).
extends RefCounted

## The circle's base size (FUN_00463210).
const R0 := 5.0


## FUN_00462c10: the circle size from the DLZ [max, min] ([] none) and the target's distance.
static func circle(locked: bool, dlz: Array, dist: float) -> float:
	return ClassDB.class_call_static("IafMrmSight", "circle", locked, dlz, dist)


## FUN_00462f70: the target's position led by dist / 2000 s.
static func predicted(t_pos: Vector3, t_vel: Vector3, dist: float) -> Vector3:
	return ClassDB.class_call_static("IafMrmSight", "predicted", t_pos, t_vel, dist)


## FUN_00462ad0: the target's screen point within 240 px with a lock, else 60 px (`off` null: never).
static func target_in_circle(off, locked: bool) -> bool:
	return ClassDB.class_call_static("IafMrmSight", "target_in_circle", off, locked)


## FUN_00462e80 / FUN_00463160: [inside, q] of the predicted point's screen offset `off` in the circle of size r.
static func in_circle(off, r: float, hud_only: bool) -> Array:
	return ClassDB.class_call_static("IafMrmSight", "in_circle", off, r, hud_only)
