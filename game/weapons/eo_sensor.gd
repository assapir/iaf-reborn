# The player's EO sensor (docs/mfd.md "FLIR (6), TV (5)"): the controller's EO mode, the camera of view slot 1,
# WIDE / SPOT, the laser flag and the FLIR / TV page values. The logic is iaf_avionics::eo
# (crates/iaf-avionics/src/eo.rs) through IafEo; this keeps the GDScript face. World frame X east, Y north, Z up,
# metres, radians, sim seconds; a base is Vector2(heading, pitch).
extends RefCounted

enum { NONE, TV, FLIR }
## Camera +0x50: 1 free (angles from the slew rates), 2 tracking a point or a unit.
enum { FREE = 1, TRACK = 2 }

## The gimbal limits by the store's class (FUN_005817a0): [az, el max, el min]; the pod ±45°, +30° / −80°, the
## weapons ±30°, +15° / −45° (the same values as eo.rs).
const POD_LIMITS := [PI / 4.0, PI / 6.0, -1.3962634015954636]
const WEAPON_LIMITS := [PI / 6.0, PI / 12.0, -PI / 4.0]
## The picture's field of view is 50° / zoom across its width (FUN_004dc990: 0x605250 = 50).
const FOV_DEG := 50.0

var mode: int:
	get:
		return _st.mode
## Slot 1 holds the EO camera once one was started.
var camera: bool:
	get:
		return _st.camera
var limits: Array:
	get:
		return _st.limits
var track: int:
	get:
		return _st.track
var point: Vector3:
	get:
		return _st.point
## A tracked unit (key), "" none.
var target: String:
	get:
		return _st.target
var zoom: float:
	get:
		return _st.zoom
var spot: bool:
	get:
		return _st.spot
## ctl+0x960.
var laser: bool:
	get:
		return _st.laser
	set(v):
		_e.set_laser(v)
		_st = _e.state()
## +0x208 / +0x220: the base frozen when a slew starts from tracking; null = the jet's live one.
var frozen:
	get:
		return _st.frozen
## The slew rates (az, el) in rad/s.
var rate: Vector2:
	get:
		return _st.rate
## weapons.ibx [DEBUGDATA] _debugParam008 (0.09): °/s per key unit (±100) at zoom 1.
var pan_k := 0.09:
	set(v):
		pan_k = v
		_e.set_pan_k(v)
## Owner: unit_pos(key) -> Vector3 (world) or null when gone.
var unit_pos: Callable

var _e = ClassDB.instantiate("IafEo")
var _st: Dictionary = _e.state()


## FUN_00450280 → FUN_005817a0 with a store: EO mode `m`, limits by the store's class (`pod` = class 0x1a), aim =
## null (free), a world point or a unit key (tracked).
func start(m: int, pod: bool, aim, t: float) -> void:
	_e.start(m, pod, aim, t)
	_st = _e.state()


## FUN_0044e6e0: leaving the EO master modes.
func stop() -> void:
	_e.stop()
	_st = _e.state()


## FUN_005805e0: the camera's (az, el) at `t` against `base` from `eye`, clamped to the limits.
func angles(t: float, base: Vector2, eye: Vector3) -> Vector2:
	var ae: Vector2 = _e.angles(t, base, eye, unit_pos)
	_st = _e.state()
	return ae


## The camera's line of sight (world unit vector) for angles `ae` on `base`.
func los(ae: Vector2, base: Vector2) -> Vector3:
	return _e.los(ae, base)


## Event 0x8a(x, y) (Ctrl+arrows): the slew, or with the keys released the lock on the EO centre point `centre`.
func pan(x: int, y: int, t: float, base: Vector2, eye: Vector3, centre, launched := false) -> void:
	_e.pan(x, y, t, base, eye, centre, launched, unit_pos)
	_st = _e.state()


## Events 0x14 / 0x15 on the EO camera: zoom in / out.
func zoom_step(zoom_in: bool) -> void:
	_e.zoom_step(zoom_in)
	_st = _e.state()


## Event 0x20 (FLIR OSB 5): WIDE ↔ SPOT.
func wide_spot() -> void:
	_e.wide_spot()
	_st = _e.state()


## Event 0x6a (L, FLIR OSB 3): only with the pod fitted.
func laser_key(pod_fitted: bool) -> void:
	_e.laser_key(pod_fitted)
	_st = _e.state()


## The FLIR page values (FUN_0045d7f0): {zoom, u, v, laser, spot, range}.
func flir_page(ae: Vector2, range_m: float) -> Dictionary:
	return _e.flir_page(ae, range_m)


## The TV page values (FUN_004604c0): {status, zoom, u, v}.
func tv_page(ae: Vector2, status: int) -> Dictionary:
	return _e.tv_page(ae, status)
