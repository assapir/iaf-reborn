# Ours (docs/front-end.md §8.2, docs/weapons.md §13.2): the GPS bombs' pre-planned (PRE) targets on the briefing TSD.
# While the selected flight carries GPS bombs a panel in the map's lower-right corner lists its GPS stations and each
# one's target. A click on a row arms it; the next click on the map gives that station the unit under the cursor (its
# position now), a waypoint of the flight, or the point itself. A right click on a row clears it back to the default:
# the route's target waypoint (IafGpsBomb.default_target), else none. The targets are stored as coordinates in
# Settings.gps_targets ({flight: {station: [x, y, label]}}) and drawn on the map: a box with the station numbers.
extends RefCounted

const ModernWeapons := preload("res://weapons/modern_weapons.gd")
const MissionWeapons := preload("res://weapons/mission_weapons.gd")
const COLOR := Color8(255, 255, 0)
const PANEL := Color(0, 0, 0, 0.75)
const ROW_H := 13.0
const PANEL_W := 160.0

var tsd: Control
## The station whose target the next map click sets, -1 none.
var armed := -1


func _init(owner: Control) -> void:
	tsd = owner


func _active() -> bool:
	return not tsd.edit and tsd.fe.get("flight") == null


## The selected flight's GPS stations: [[station 0..8, weapon name]].
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
			out.append([i, gps[int(load[i][0])]])
	return out


## Station `i`'s target: {map (map units), label, set (chosen on the TSD)}, or {} none.
func target(i: int) -> Dictionary:
	var n: int = tsd.default_flight()
	var t = Settings.gps_targets.get(n, {}).get(i)
	if t != null:
		return {"map": tsd.world_to_map(t[0], t[1]), "label": t[2], "set": true}
	if not tsd.flights.has(n):
		return {}
	var d: int = ClassDB.class_call_static(
		"IafGpsBomb", "default_target", PackedInt64Array(tsd.flights[n].get("actions", []))
	)
	if d < 0:
		return {}
	return {"map": tsd.flights[n].points[d], "label": "WP%d" % (d + 1), "set": false}


## The panel's rows (client px): [[rect, station or -1 for the header]].
func _rows(list: Array) -> Array:
	var top: float = tsd.area.size.y - 4.0 - ROW_H * (list.size() + 1)
	var left: float = tsd.area.size.x - 4.0 - PANEL_W
	var out := [[Rect2(left, top, PANEL_W, ROW_H), -1]]
	for k in list.size():
		out.append([Rect2(left, top + ROW_H * (k + 1), PANEL_W, ROW_H), list[k][0]])
	return out


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
	# Each target once on the map: a box with the numbers of the stations aimed at it.
	var at := {}
	for r in rows:
		var rect: Rect2 = r[0]
		var base := (rect.position + Vector2(3, ROW_H - 3)) * s
		var i: int = r[1]
		if i < 0:
			var head := "GPS TARGETS" if armed < 0 else "CLICK A TARGET FOR STA %d" % (armed + 1)
			ci.draw_string(font, base, head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COLOR)
			continue
		var t := target(i)
		var label: String = "-" if t.is_empty() else String(t.label) + ("" if t.set else " (TGT WP)")
		var col: Color = COLOR if i == armed else Color.WHITE
		if i == armed:
			ci.draw_rect(Rect2(rect.position * s, rect.size * s), COLOR, false, maxf(1.0, s))
		ci.draw_string(font, base, "STA %d %s" % [i + 1, names[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		ci.draw_string(font, base + Vector2(72, 0) * s, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if not t.is_empty():
			var key := Vector2i(t.map.round())
			at[key] = at.get(key, []) + [str(i + 1)]
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
			if event.button_index == MOUSE_BUTTON_RIGHT and i >= 0:
				Settings.gps_targets.get(tsd.default_flight(), {}).erase(i)
				armed = -1
			elif event.button_index == MOUSE_BUTTON_LEFT:
				armed = -1 if i == armed or i < 0 else i
			return true
	if armed < 0 or event.button_index != MOUSE_BUTTON_LEFT or event.double_click:
		return false
	_assign(armed, c)
	armed = -1
	return true


## Station `i` takes the unit, waypoint or map point at client point `c`.
func _assign(i: int, c: Vector2) -> void:
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
	Settings.gps_targets[n][i] = [w.x, w.y, label.substr(0, 12)]
