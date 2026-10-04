# Bombs (docs/weapons.md §9): the HUD impact prediction, the ripple line and the falling store, the original's
# ballistic class 0x16. The logic is iaf_avionics::bombs (crates/iaf-avionics/src/bombs.rs) through IafBomb; this
# keeps the GDScript face. The bomb state stays a plain Dictionary {t0, p0, v0, aim, acc, end, next_check, opened,
# done}. World frame X east, Y north, Z up, metres, sim seconds; the terrain height comes from ground(p) -> float or
# null.
extends RefCounted

## The terrain height where none is loaded (0x60ce14).
const NO_GROUND := 0.1


## FUN_0045e7f0 (the HUD's predicted impact): {point, t}.
static func predict_impact(p: Vector3, vel: Vector3, nose: Vector3, drag: float, extra: float, ground: Callable) -> Dictionary:
	return ClassDB.class_call_static("IafBomb", "predict_impact", p, vel, nose, drag, extra, ground)


## FUN_0045e330: the later root of h + vz·t − 4.903·t² = 0 (0 when there is none).
static func fall_time(vz: float, h: float) -> float:
	return ClassDB.class_call_static("IafBomb", "fall_time", vz, h)


static func _h(ground: Callable, p: Vector3) -> float:
	var h = ground.call(p) if ground.is_valid() else null
	return float(h) if h != null else NO_GROUND


## FUN_00457c20: the ripple line, `qty` points `spacing` m apart along the heading, centred on P, on the terrain.
static func ripple_line(p: Vector3, qty: int, spacing: float, heading_rad: float, ground: Callable) -> Array:
	return ClassDB.class_call_static("IafBomb", "ripple_line", p, qty, spacing, heading_rad, ground)


## The falling store toward `aim` (the solver FUN_005611b0), the along-track correction clamped to ±`clamp_acc`.
static func launch(now: float, p: Vector3, v: Vector3, aim: Vector3, clamp_acc: float) -> Dictionary:
	return ClassDB.class_call_static("IafBomb", "launch", now, p, v, aim, clamp_acc)


static func position(b: Dictionary, now: float) -> Vector3:
	return ClassDB.class_call_static("IafBomb", "position", b, now)


static func velocity(b: Dictionary, now: float) -> Vector3:
	return ClassDB.class_call_static("IafBomb", "velocity", b, now)


## The impact checks of FUN_00561750 up to `now` (b is updated): {} or {pos, t}. `fix_burst`: the burst on the
## ground (Physics "Bombs burst at the ground"); `open_h` > 0 (510): the cluster opens that high (b.opened).
static func check(b: Dictionary, now: float, ground: Callable, fix_burst := false, open_h := 0.0) -> Dictionary:
	return ClassDB.class_call_static("IafBomb", "check", b, now, ground, fix_burst, open_h)
