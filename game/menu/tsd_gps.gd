# Ours (docs/front-end.md §8.2, docs/weapons.md §13.2): the GPS bombs' pre-planned (PRE) targets on the briefing TSD.
# While the selected flight carries GPS bombs a panel in the map's lower-right corner lists its GPS stations and each
# one's target; a rack (several bombs on one station, the GBU-39s) opens into one row per bomb (STA 3-1 .. 3-4, bomb 1
# the first to leave). A click on a row arms it; the next click on the map gives that station (all its bombs) or that
# bomb the unit under the cursor (its position now), a waypoint of the flight, or the point itself. A right click on a
# row clears it: a bomb back to its station's target, a station back to the default, the route's target waypoint
# (IafGpsBomb.default_target), else none. The targets are stored as coordinates in Settings.gps_targets ({flight:
# {station: [x, y, label], Vector2i(station, bomb): [x, y, label]}}) and drawn on the map: a box with the stations (3)
# or bombs (3-1,3-2) aimed at it.
extends RefCounted

const ModernWeapons := preload("res://weapons/modern_weapons.gd")
const MissionWeapons := preload("res://weapons/mission_weapons.gd")
const COLOR := Color8(255, 255, 0)
const PANEL := Color(0, 0, 0, 0.75)
const ROW_H := 13.0
const PANEL_W := 160.0
## A bomb row whose target is its station's.
const INHERITED := Color(0.6, 0.6, 0.6)

var tsd: Control
## The station whose target the next map click sets, -1 none; `armed_bomb` the bomb of a rack, -1 the whole station.
var armed := -1
var armed_bomb := -1
## The racks opened into their bombs' rows (station -> true).
var opened := {}


func _init(owner: Control) -> void:
	tsd = owner


func _active() -> bool:
	return not tsd.edit and tsd.fe.get("flight") == null


## The selected flight's GPS stations: [[station 0..8, weapon name, bombs]].
func stations() -> Array:
	var n: int = tsd.default_flight()
	if tsd.fe.mission_weapons == null:
		tsd.fe.mission_weapons = MissionWeapons.create(Settings.mission_id, Settings.real_weapons())
	var mw = tsd.fe.mission_weapons
	var load: Array = Settings.arm_loadouts.get(n, mw.defaults.get(n, []))
	var gps := {}
	for r in ModernWeapons.RECORDS:
		if r.has("gps"):
			gps[int(r.id)] = r.name
	var out := []
	for i in mini(9, load.size()):
		if int(load[i][1]) != 0 and gps.has(int(load[i][0])):
			out.append([i, gps[int(load[i][0])], int(load[i][1])])
	return out


func _chosen() -> Dictionary:
	return Settings.gps_targets.get(tsd.default_flight(), {})


## Station `i`'s target (bomb `b` >= 0: that bomb's, else its station's): {map (map units), label, set (chosen on the
## TSD), own (set for the bomb itself)}, or {} none.
func target(i: int, b := -1) -> Dictionary:
	var n: int = tsd.default_flight()
	var t = _chosen().get(Vector2i(i, b)) if b >= 0 else null
	if t != null:
		return {"map": tsd.world_to_map(t[0], t[1]), "label": t[2], "set": true, "own": true}
	t = _chosen().get(i)
	if t != null:
		return {"map": tsd.world_to_map(t[0], t[1]), "label": t[2], "set": true, "own": false}
	if not tsd.flights.has(n):
		return {}
	var d: int = ClassDB.class_call_static(
		"IafGpsBomb", "default_target", PackedInt64Array(tsd.flights[n].get("actions", []))
	)
	if d < 0:
		return {}
	return {"map": tsd.flights[n].points[d], "label": "WP%d" % (d + 1), "set": false, "own": false}


## A rack with a target set for one of its bombs.
func _has_own(i: int, count: int) -> bool:
	return range(count).any(func(b): return _chosen().has(Vector2i(i, b)))


## The panel's rows (client px): [[rect, station or -1 for the header, bomb or -1 for the station]].
func _rows(list: Array) -> Array:
	var keys := []
	for l in list:
		keys.append([l[0], -1])
		if l[2] > 1 and (opened.has(l[0]) or _has_own(l[0], l[2])):
			for b in l[2]:
				keys.append([l[0], b])
	var top: float = tsd.area.size.y - 4.0 - ROW_H * (keys.size() + 1)
	var left: float = tsd.area.size.x - 4.0 - PANEL_W
	var out := [[Rect2(left, top, PANEL_W, ROW_H), -1, -1]]
	for k in keys.size():
		out.append([Rect2(left, top + ROW_H * (k + 1), PANEL_W, ROW_H), keys[k][0], keys[k][1]])
	return out


func _name(i: int, b: int) -> String:
	return "%d" % (i + 1) if b < 0 else "%d-%d" % [i + 1, b + 1]


func draw(ci: CanvasItem, s: float) -> void:
	if not _active():
		return
	var list := stations()
	if list.is_empty():
		return
	var font: Font = tsd.fe.font_bold
	var fs := int(round(10 * s))
	var rows := _rows(list)
	var names := {}
	for l in list:
		names[l[0]] = l[1]
	ci.draw_rect(Rect2(rows[0][0].position * s, Vector2(PANEL_W, ROW_H * rows.size()) * s), PANEL)
	for r in rows:
		var rect: Rect2 = r[0]
		var base := (rect.position + Vector2(3, ROW_H - 3)) * s
		var i: int = r[1]
		var b: int = r[2]
		if i < 0:
			var head := "GPS TARGETS" if armed < 0 else "CLICK A TARGET FOR STA %s" % _name(armed, armed_bomb)
			ci.draw_string(font, base, head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COLOR)
			continue
		var t := target(i, b)
		var label: String = "-" if t.is_empty() else String(t.label) + ("" if t.set else " (TGT WP)")
		var on := i == armed and b == armed_bomb
		var col: Color = COLOR if on else (Color.WHITE if b < 0 or t.get("own", false) else INHERITED)
		if on:
			ci.draw_rect(Rect2(rect.position * s, rect.size * s), COLOR, false, maxf(1.0, s))
		var text := "STA %d %s" % [i + 1, names[i]] if b < 0 else "   STA %s" % _name(i, b)
		ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		ci.draw_string(font, base + Vector2(72, 0) * s, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# Each target once on the map: a box with the stations (a rack without own targets: its number) or bombs aimed at it.
	var at := {}
	for l in list:
		var per_bomb: bool = l[2] > 1 and _has_own(l[0], l[2])
		for b in l[2] if per_bomb else 1:
			var t := target(l[0], b if per_bomb else -1)
			if not t.is_empty():
				var key := Vector2i(t.map.round())
				at[key] = at.get(key, []) + [_name(l[0], b if per_bomb else -1)]
	for key in at:
		var c: Vector2 = tsd._to_client(Vector2(key)) * s
		var h := 6.0 * s
		ci.draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), COLOR, false, maxf(1.0, s))
		ci.draw_line(c - Vector2(0, h + 3 * s), c - Vector2(0, h), COLOR, maxf(1.0, s))
		ci.draw_line(c + Vector2(0, h), c + Vector2(0, h + 3 * s), COLOR, maxf(1.0, s))
		ci.draw_string(font, c + Vector2(h + 2 * s, -h), ",".join(at[key]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COLOR)


## A mouse event at client point `c`; true when used.
func input(event: InputEvent, c: Vector2) -> bool:
	if not _active() or not (event is InputEventMouseButton) or not event.pressed:
		return false
	var list := stations()
	if list.is_empty():
		armed = -1
		return false
	for r in _rows(list):
		if r[0].has_point(c):
			var i: int = r[1]
			var b: int = r[2]
			if event.button_index == MOUSE_BUTTON_RIGHT and i >= 0:
				_clear(i, b)
				armed = -1
			elif event.button_index == MOUSE_BUTTON_LEFT:
				var again := i == armed and b == armed_bomb
				armed = -1 if again or i < 0 else i
				armed_bomb = -1 if armed < 0 else b
				# A rack's station row opens its bombs' rows, a second click closes them.
				if b < 0 and i >= 0:
					if again:
						opened.erase(i)
					else:
						opened[i] = true
			return true
	if armed < 0 or event.button_index != MOUSE_BUTTON_LEFT or event.double_click:
		return false
	_assign(armed, c, armed_bomb)
	armed = -1
	armed_bomb = -1
	return true


## Clears bomb `b` of station `i` (back to the station's target), or with `b` -1 the station and all its bombs.
func _clear(i: int, b: int) -> void:
	var t := _chosen()
	if b >= 0:
		t.erase(Vector2i(i, b))
		return
	t.erase(i)
	for k in t.keys():
		if k is Vector2i and k.x == i:
			t.erase(k)


## Station `i` (all its bombs; `b` >= 0: that bomb only) takes the unit, waypoint or map point at client point `c`.
func _assign(i: int, c: Vector2, b := -1) -> void:
	var n: int = tsd.default_flight()
	var m: Vector2 = c / tsd.zoom + tsd.scroll
	var label := "PT"
	var u: int = tsd.unit_at(c)
	var wp: int = tsd._waypoint_at(c)
	if u >= 0:
		m = tsd.units[u].pos
		label = tsd.unit_label(tsd.units[u])
		label = label if label != "" else "UNIT"
	elif wp >= 0:
		m = tsd.flights[n].points[wp]
		label = "WP%d" % (wp + 1)
	var w: Vector2 = tsd.map_to_world(m)
	if not Settings.gps_targets.has(n):
		Settings.gps_targets[n] = {}
	if b < 0:
		_clear(i, -1)
	Settings.gps_targets[n][Vector2i(i, b) if b >= 0 else i] = [w.x, w.y, label.substr(0, 12)]
