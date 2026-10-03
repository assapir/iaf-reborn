# The HUD objects of the radar missiles (HUD mode 2, MRM: FUN_00460ea0, vtable 0x601618) and the HARM (mode 8:
# FUN_00460a90, vtable 0x601560), both on the base FUN_00462ab0 (vtable 0x6015b0; docs/weapons.md §11): the
# launch circle sized by the selected store's DLZ (vfunc +0x3c FUN_00462c10), the target's predicted point
# (FUN_00462f70), the in-circle tests of the launch (vfunc +0x30 FUN_00462ad0, +0x34 FUN_00462e80) and its q
# (vfunc +0x38 FUN_00463160). Scene independent: screen offsets are original 640x480 pixels from the HUD centre
# (ir_seeker.gd `screen_offset`: 12 px/deg from the camera ray through it).
extends RefCounted

## The circle's base size (vfunc +0x40 FUN_00463210: 0x601798 = 5) and its smallest share (0x6017ac = 1/3); the
## HUD draws it ×12 px (0x6017b4, at least 10 px).
const R0 := 5.0
const R_MIN_K := 1.0 / 3.0
const PX := 12.0
## Launch circle around the HUD centre (vfunc +0x44 / +0x48: 0x6017a0² / 0x60179c²): 60 px without a lock,
## 240 px with one.
const FREE_PX2 := 60.0 * 60.0
const LOCKED_PX2 := 240.0 * 240.0
## The predicted point leads the target by t = √(dist² · 2.5e-7) s = dist / 2000 (0x6017bc).
const LEAD_K := 2.5e-7


## FUN_00462c10: the circle size from the DLZ [max, min] and the target's distance: R0 without a lock / target;
## at or inside min, or at or beyond max, R0 / 3; between, R0 · (1 − (dist − min) / (max − min)), at least R0 / 3.
static func circle(locked: bool, dlz: Array, dist: float) -> float:
	if not locked or dlz.is_empty():
		return R0
	var mx: float = dlz[0]
	var mn: float = dlz[1]
	if dist <= mn or dist >= mx:
		return R0 * R_MIN_K
	return maxf(R0 * (1.0 - (dist - mn) / (mx - mn)), R0 * R_MIN_K)


## FUN_00462f70: the target's position led by dist / 2000 s at its velocity (with a lock and a target).
static func predicted(t_pos: Vector3, t_vel: Vector3, dist: float) -> Vector3:
	return t_pos + t_vel * sqrt(dist * dist * LEAD_K)


## FUN_00462ad0 (vfunc +0x30): the target's screen point within 240 px of the HUD centre with a lock, else 60 px
## (`off` null = behind the camera: never).
static func target_in_circle(off, locked: bool) -> bool:
	return off != null and (off as Vector2).length_squared() <= (LOCKED_PX2 if locked else FREE_PX2)


## FUN_00462e80 (vfunc +0x34) with a lock: the predicted point's screen offset `off` within the circle (r · 12
## px; in the HUD-only view within √2 of it: the original compares d² with 2·R²). [inside, q]: q = 1 inside,
## else R / d.
static func in_circle(off, r: float, hud_only: bool) -> Array:
	if off == null:
		return [false, 0.0]
	var r2 := (r * PX) * (r * PX)
	var d2: float = (off as Vector2).length_squared()
	var inside := d2 <= (r2 + r2 if hud_only else r2)
	return [inside, 1.0 if inside else sqrt(r2) / sqrt(d2)]
