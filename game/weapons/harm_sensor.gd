# The HARM page's emitter list (docs/mfd.md "HARM (10)"): the original's HARM sensor (vtable 0x601190, a target
# sensor with a ±15° cone) captured by FUN_0045bb00 → FUN_00446050 into state+0xa28..0xe00. Ours lists the RWR's
# active emitters (rwr.gd slots) inside that cone — the HARM sensor itself waits for the AI target sensor
# (deviations.md). World frame X east, Y north, Z up, radians, sim seconds.
extends RefCounted

## The cone: cos 15° (0x601168 = 15.0, static init 0x45b68e); the page's field width = 2·acos = 30° (+0xdf8).
const HALF_ANGLE := 0.26179939
const FIELD := 2.0 * HALF_ANGLE
## The list holds at most 15 entries (FUN_00446050); the sensor keeps the best 5 by 100 / distance (ai.md §14).
const KEEP := 5

## [{key, type, az, el, dist}] as captured, the selected key, and the heading / pitch at the capture
## (DAT_0082f574 / 0x82f568: the symbols move with the jet's turns until the next capture).
var list: Array = []
var selected := ""
var base := Vector2.ZERO
var active := false  # HUD mode 8 (FUN_0045c2b0 on / FUN_0045c2f0 off)


## A capture (the mcp's state 5): the slots' active emitters inside the cone, nearest first, at most 5; the
## selection kept when still listed, else the nearest (UNCERTAIN: the sensor's own pick).
func capture(slots: Array, eye: Vector3, own_base: Vector2) -> void:
	base = own_base
	list = []
	var fwd := Vector3(sin(own_base.x) * cos(own_base.y), cos(own_base.x) * cos(own_base.y), sin(own_base.y))
	for s in slots:
		if String(s.get("unit", "")) == "" or not s.get("active", false):
			continue
		var d: Vector3 = s.pos - eye
		if d.length() < 1.0 or fwd.dot(d.normalized()) < cos(HALF_ANGLE):
			continue
		list.append({"key": String(s.unit), "type": int(s.type), "dist": d.length(),
			"az": wrapf(atan2(d.x, d.y) - own_base.x, -PI, PI),
			"el": atan2(d.z, Vector2(d.x, d.y).length()) - own_base.y})
	list.sort_custom(func(a, b): return a.dist < b.dist)
	list = list.slice(0, KEEP)
	if not list.any(func(e): return e.key == selected):
		selected = list[0].key if not list.is_empty() else ""


## Event 0x37(id) (a click on a symbol, FUN_0045c280): select it; the mcp then recaptures.
func select(key: String) -> void:
	if list.any(func(e): return e.key == key):
		selected = key


## The page snapshot (state+0xa28.., +0xde8..+0xe00): entries {key, type, az, el, selected}, the field width, the
## heading / pitch change since the capture (+0xdf4 / +0xdfc, wrapped to ±π), "no source" (+0xe00: no round
## left or the sensor off) and "In Range" (+0xdf0: the selected emitter nearer than the HARM's DLZ max, FUN_00460ac0).
func page(own_base: Vector2, rounds: int, in_range := false) -> Dictionary:
	var out := []
	for e in list:
		out.append({"key": e.key, "type": e.type, "az": e.az, "el": e.el, "selected": e.key == selected})
	return {"list": out if active else [], "field": FIELD, "dpsi": wrapf(base.x - own_base.x, -PI, PI),
		"dtheta": wrapf(base.y - own_base.y, -PI, PI), "no_source": not active or rounds == 0, "in_range": in_range}
