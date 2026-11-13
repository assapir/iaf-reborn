# Bombs (docs/weapons.md §9): the HUD impact prediction, the ripple line and the falling store, the original's
# ballistic class 0x16. The logic is iaf_avionics::bombs (crates/iaf-avionics/src/bombs.rs) through IafBomb; this
# adds the wind and the terrain height, and callers call IafBomb's ripple_line / position / velocity / check directly.
# The bomb state stays a plain Dictionary {t0, p0, v0, aim, acc, end, next_check, opened, done}. World frame X east,
# Y north, Z up, metres, sim seconds; the terrain height comes from ground(p) -> float or null.
extends RefCounted

## The terrain height where none is loaded (0x60ce14).
const NO_GROUND := 0.1

## The air mass (m/s, this frame) for Better physics `wind`: the bombing computer knows it and the stores drift with
## it (terrain_view.gd `apply_wind`); zero is the original.
static var wind := Vector3.ZERO


## FUN_0045e7f0 (the HUD's predicted impact, with the terrain ray FUN_0045ed40; `cockpit`: the
## cockpit-like views 1 / 5 / 0x12 / 0x16): {point, t}.
static func predict_impact(
	p: Vector3, vel: Vector3, nose: Vector3, drag: float, extra: float, ground: Callable, cockpit := true
) -> Dictionary:
	return ClassDB.class_call_static(
		"IafBomb", "predict_impact", p, vel, nose, Vector2(drag, extra), cockpit, wind, ground
	)


static func _h(ground: Callable, p: Vector3) -> float:
	var h = ground.call(p) if ground.is_valid() else null
	return float(h) if h != null else NO_GROUND


## The falling store toward `aim` (the solver FUN_005611b0), the along-track correction clamped to ±`clamp_acc`.
static func launch(now: float, p: Vector3, v: Vector3, aim: Vector3, clamp_acc: float) -> Dictionary:
	return ClassDB.class_call_static("IafBomb", "launch", now, p, v, aim, clamp_acc, wind)
