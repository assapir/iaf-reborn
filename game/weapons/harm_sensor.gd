# The HARM page's emitter list (docs/mfd.md "HARM (10)"): the RWR's active emitters inside the HARM sensor's ±15°
# cone. The logic is iaf_avionics::harm (crates/iaf-avionics/src/harm.rs) through IafHarm; this keeps the GDScript
# face. World frame X east, Y north, Z up, radians; a base is Vector2(heading, pitch).
extends RefCounted

## [{key, type, az, el, dist}] as captured, and the selected key.
var list: Array:
	get:
		return _st.list
var selected: String:
	get:
		return _st.selected
## HUD mode 8 (FUN_0045c2b0 on / FUN_0045c2f0 off).
var active := false:
	set(v):
		active = v
		_h.set_active(v)

var _h = ClassDB.instantiate("IafHarm")
var _st: Dictionary = _h.state()


## A capture (the mcp's state 5) from the RWR's slots.
func capture(slots: Array, eye: Vector3, own_base: Vector2) -> void:
	_h.capture(slots, eye, own_base)
	_st = _h.state()


## Event 0x37(id) (a click on a symbol, FUN_0045c280): select it.
func select(key: String) -> void:
	_h.select(key)
	_st = _h.state()


## The page snapshot (state+0xa28.., +0xde8..+0xe00): entries {key, type, az, el, selected}, the field width, the
## heading / pitch change since the capture, "no source" (no round left or the sensor off) and "In Range".
func page(own_base: Vector2, rounds: int, in_range := false) -> Dictionary:
	var out := []
	for e in list:
		out.append({"key": e.key, "type": e.type, "az": e.az, "el": e.el, "selected": e.key == selected})
	var d: Vector2 = _h.drift(own_base)
	return {"list": out if active else [], "field": ClassDB.class_call_static("IafHarm", "field"), "dpsi": d.x,
		"dtheta": d.y, "no_source": not active or rounds == 0, "in_range": in_range}
