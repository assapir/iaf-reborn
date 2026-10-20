# The pre-flight Tactical Situation Display (screen 0x1e, docs/front-end.md §6, §8): the EMF
# vector map with grid / text overlays, units and waypoints, zoom and scrollbars, and the
# briefing window with its link windows. Panels and buttons are drawn by the front end, which
# forwards TSD button presses here.
extends Control

## Content window (TSD client) in 640x480 space.
const CLIENT := Rect2(155, 42, 453, 357)
## Map extent at zoom 1 (0x607fa8/e4).
const MAP_SIZE := Vector2(454, 590)
const ZOOM_STEP := 1.5
const ZOOM_MAX := 32.0
## Scrollbars by axis (0 = horizontal, 1 = vertical), screen coordinates, and the lengths of their
## arrow / thumb art along the bar.
const BARS := [Rect2(146, 399, 462, 10), Rect2(608, 42, 10, 356)]
const BAR_UP := [24.0, 23.0]
const BAR_DOWN := [21.0, 21.0]
const BAR_THUMB := [74.0, 75.0]
const BAR_ART := ["h", "v"]
const BAR_ARROWS := [["left", "right"], ["up", "down"]]
## Scroll arrow step: 5 map units (round(5·z) px).
const ARROW_STEP := 5.0
## World -> map (FUN_00500ec0): X shift = DataXShiftPR, Y shift, width / height of the world.
const WORLD_X_SHIFT := 166850.0
const WORLD_Y_SHIFT := 21144.0
const WORLD_W := 819200.0
const WORLD_H := 1064960.0
const MAP_X_FACTOR := 1.0071394
## Flight colours 1..4 (Alpha..Delta), 5-6 white.
const FLIGHT_COLORS := [
	Color8(226, 0, 180), Color8(4, 178, 39), Color8(0, 82, 250), Color8(215, 134, 1), Color.WHITE, Color.WHITE
]
const FLIGHT_NAMES := ["alpha", "bravo", "charlie", "delta"]
## Flyable type codes (FUN_00505730).
const FLYABLE_TYPES := [100, 110, 120, 130, 140, 160, 180, 190, 200]
## bdb object class (0x5aa) -> icon class: 1 aircraft, 2 ship, 3 structure, 4 vehicle, 5 SAM, 6 AAA.
const ICON_CLASS := {
	2: 1, 3: 1, 0x1c: 1, 0xf: 2, 0x10: 2, 0xc: 3, 0xd: 3, 0x1d: 3, 0x1e: 3, 5: 4, 6: 4, 8: 5, 9: 5, 10: 6
}
const ICON_ART := {1: "icair", 2: "icshp", 3: "icstr", 4: "icveh", 5: "icsam", 6: "icaaa"}
const FILTERS := {1: "aircrafts", 2: "ships", 3: "structures", 4: "vehicles", 5: "samsites", 6: "aaasites"}
## SAM ring radius (world units) by type code (class 8).
const SAM_RING := {290: 37080.0, 340: 37080.0, 300: 16686.0, 320: 22248.0}
## Selected-unit label line 1 (FUN_004f6da0 → FUN_004f7670): type code → name; other types by class.
const TYPE_NAMES := {
	110: "F-15",
	100: "F-16",
	120: "F-4E",
	130: "Kfir",
	140: "Lavi",
	150: "MiG21",
	160: "MiG23",
	170: "MiG25",
	180: "MiG29",
	190: "Mirage",
	200: "F-42000",
	210: "MiG17",
	220: "Bomber",
	225: "Transport",
	230: "Transport",
	240: "Transport",
	250: "Tank",
	260: "Truck",
	270: "Armored",
	280: "Soft",
	290: "SA-2",
	300: "SA-3",
	310: "SA-5",
	320: "SA-6",
	330: "SA8",
	340: "Hawk",
	350: "AAA",
	360: "Gundish",
	370: "Boat",
	380: "Ship",
	390: "Ship",
	400: "Building",
	410: "Strategic",
	420: "Bridge",
	430: "Road",
	440: "Airport"
}
const CLASS_NAMES := {
	2: "Helo",
	6: "Truck",
	9: "IR-SAM",
	0xb: "Building",
	0xc: "Building",
	0xd: "Building",
	0x1d: "Building",
	0x1e: "Building"
}
## Line 2: the flight-table names (FUN_005bd3c0), slots 1..6 only.
const FLIGHT_LABELS := ["", "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
## The selected-unit label colour (SetTextColor 0x00FFFF).
const LABEL_COLOR := Color8(255, 255, 0)
## The ruler (paint 501300): metres → NM (0x6081f4); text red (SetTextColor 0xff), line WHITE_PEN; the arrow's
## strokes 10 px (0x607fb4) at ±0.628 rad (0x607fb8).
const RULER_NM := 0.00053996
const RULER_TEXT := Color8(255, 0, 0)
const RULER_ARROW := 10.0
const RULER_ARROW_ANGLE := 0.6283185

const Img := preload("res://util/img.gd")
const MissionRuntime := preload("res://mission/mission_runtime.gd")
const ModelView := preload("res://menu/model_view.gd")

static var _map_cache := {}

var fe: Control
var zoom := 1.0
var scroll := Vector2.ZERO  # top-left of the view in map units
var layers := {"waypoint": true, "text": true, "grid": true}
var map_name := "82"
var map_canvas: Control
var overlay: Control
var windows: Control
var brief_window: Control
var link_windows := {}  # brl type -> window
var mission_id := -1
## Units shown on the map: {key (runtime entity key), pos (map units), klass, side, heading, leader, flight, type,
## cls, name, airport}.
var units: Array = []
## Flights by number: {members: [unit index], points: [map units], leader: unit index}.
var flights := {}
var mission_title := ""
var mission_clock := ""
var selected := -1  # the selected unit's index (DAT_006548a4: label, selection icon, Visit, zoom pivot)
var sel_flight := 0  # the selected flight (DAT_0083b8a4: Fly, Arm, the route drawn last, the waypoint drag)
## The ruler (+0xa4 start, +0xac end, world X / Y; +0xb4 dragging, +0xb8 kept after the release).
var ruler_a := Vector2.ZERO
var ruler_b := Vector2.ZERO
var ruler_on := false
var ruler_kept := false
var sel_textures := {}
var drag_wp := -1  # waypoint of the selected flight being dragged
var pressed_arrow := ""
var dragging := -1  # axis of the thumb being dragged
var drag_offset := 0.0


func setup(front_end: Control, mission: int) -> void:
	fe = front_end
	mission_id = mission
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Missions 110–119 use the 1967 map, 120–129 the 1973 map (FUN_004ffba0).
	if mission_id >= 110 and mission_id <= 119:
		map_name = "67"
	elif mission_id >= 120 and mission_id <= 129:
		map_name = "73"
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(clip)
	map_canvas = preload("res://menu/tsd_map.gd").new()
	map_canvas.tsd = self
	clip.add_child(map_canvas)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	clip.add_child(overlay)
	windows = Control.new()
	windows.clip_contents = true
	windows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(windows)
	map_canvas.load_maps(_map(map_name), _map("grid"), _map("text"))
	_load_units()


## World (mission) coordinates -> TSD map units (FUN_00500ec0).
static func world_to_map(x: float, y: float) -> Vector2:
	return Vector2(
		(x + WORLD_X_SHIFT) * MAP_SIZE.x * MAP_X_FACTOR / WORLD_W,
		MAP_SIZE.y - (y + WORLD_Y_SHIFT) * MAP_SIZE.y / WORLD_H
	)


## Inverse (FUN_00500f70).
static func map_to_world(m: Vector2) -> Vector2:
	return Vector2(
		m.x * WORLD_W / (MAP_SIZE.x * MAP_X_FACTOR) - WORLD_X_SHIFT,
		(MAP_SIZE.y - m.y) * WORLD_H / MAP_SIZE.y - WORLD_Y_SHIFT
	)


## The selected flight's route in world coordinates (what the TSD may have changed), for the flight.
func selected_route() -> Array:
	var n := default_flight()
	if not flights.has(n):
		return []
	var out := []
	for p in flights[n].points:
		out.append(map_to_world(p))
	return out


## The unit and flight tables (`FUN_004d2900`, docs/front-end.md §8.1): what the spawner created from the mission
## and its base missions, entities whose bdb class has an icon, placed in the world (the unused player slots sit at
## (-1, -1); as in mission_runtime.gd only both coordinates negative means unplaced). In flight (the FlyTSD) the
## table is the live battle: the spawned units' current positions and headings; a unit gets a record only while
## alive (state ∉ {4, 5}), controlled (+0x14 ≠ 0) and known to the player (+0x44: entity 0x35c, or detected by the
## player's radar).
func _load_units() -> void:
	var live = _runtime()
	var bdbs := {}
	var first := true
	var formations: Array = []  # [flight number, [member keys], points]
	var files := MissionRuntime.mission_files(mission_id)
	for fi in files.size():
		var m: Dictionary = files[fi].data
		if m.is_empty():
			continue
		var bdb_name := String(m.get("bdb", "")).to_lower()
		if not bdbs.has(bdb_name):
			bdbs[bdb_name] = MissionRuntime.bdb_objects(MissionRuntime.load_bdb(m))
		var objects: Dictionary = bdbs[bdb_name]
		if first:
			var misc: Dictionary = m.misc.items[0]
			mission_title = misc.get("0x44c", "")
			# The clock is the time of day (DAT_0069916c): the start time 0x460, in flight + the mission clock.
			var t := int(float(misc.get("0x460", 0.0)) + (live.now if live != null else 0.0))
			mission_clock = "%02d:%02d:%02d" % [t / 3600 % 24, t / 60 % 60, t % 60]
		for e in m.entities.items:
			if not (e is Dictionary) or (float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0):
				continue
			var obj: Dictionary = objects.get(int(e.get("0x2c6", -1)), {})
			var klass: int = ICON_CLASS.get(int(obj.get("0x5aa", -1)), 0)
			if klass == 0:
				continue
			var key := "%d:%d" % [fi, int(e["0x1e"])]
			var pos := Vector2(float(e["0x2e4"]), float(e["0x2ee"]))
			var heading := float(e.get("0x302", 0))
			if live != null:
				var ent: Dictionary = live.entities.get(key, {})
				if (
					ent.is_empty()
					or int(ent.state) in [4, 5]
					or int(ent.control) == 0
					or not (int(e.get("0x35c", 0)) != 0 or ent.get("known", false))
				):
					continue
				var w: Vector3 = live._world_of(ent)
				pos = Vector2(w.x, w.y)
				heading = (
					float(fe.flight.flight.state().heading)
					if ent.player and fe.flight.flight != null
					else float(ent.heading)
				)
			elif int(e.get("0x35c", 0)) == 0:
				continue
			var type := int(obj.get("0x5b4", -1))
			(
				units
				. append(
					{
						"key": key,
						"pos": world_to_map(pos.x, pos.y),
						"klass": klass,
						"side": int(e.get("0x2d0", 0)),
						"heading": heading,
						"type": type,
						"cls": int(obj.get("0x5aa", -1)),
						"leader": false,
						"flight": 0,
						"airport": type == 450,
						"name": String(e.get("0x2bc", "")),
					}
				)
			)
		if first:
			for f in m.formations.items:
				var n := int(f.get("0x3f2", 0))
				if n == -1:
					n = 8
				if n <= 0:
					continue
				# The flight's two member slots (0x41a).
				var keys: Array = f.get("members", []).slice(0, 2).map(
					func(mem): return "%d:%d" % [fi, int(mem.get("0x41a", -1))]
				)
				var pts: Array = []
				for p in f.get("points", []):
					pts.append(world_to_map(float(p[1]), float(p[2])))
				formations.append([n, keys, pts])
		first = false
	# A flight exists while either member has a record; its leader is member 0, else member 1 (FUN_004d35c0).
	var index := {}
	for i in units.size():
		index[units[i].key] = i
	for f in formations:
		var members: Array = f[1].filter(func(k): return index.has(k)).map(func(k): return index[k])
		if members.is_empty():
			continue
		flights[f[0]] = {"members": members, "points": f[2], "leader": members[0]}
		units[members[0]].leader = true
		for i in members:
			units[i].flight = f[0]
	# The default selection is the flight holding the player object (FUN_005bcd70): before the flight the leader of the
	# formation with id 1, else 2, 3, 4 (FUN_004bb439; mission_runtime.gd player_flight()); in flight the player's.
	var n := 0
	if live != null:
		var me: Dictionary = live.player_entity()
		for i in units.size():
			if not me.is_empty() and units[i].key == me.key:
				n = int(units[i].flight)
	else:
		var pf: Dictionary = MissionRuntime.player_flight(files[0].data) if not files.is_empty() else {}
		n = int(pf.get("flight", 0))
	if flights.has(n):
		select_flight(n)


## The flight's mission runtime (the FlyTSD reads the live battle), else null.
func _runtime():
	return fe.flight.runtime if fe != null and fe.flight != null and fe.flight.get("runtime") != null else null


## The selected flight (DAT_0083b8a4; 0 = none): the one Fly / Arm take and the player starts in.
func default_flight() -> int:
	return sel_flight


## Alpha..Delta enable rule (FUN_00505820): the flight exists, its leader's type is flyable, and the side rule.
func flight_enabled(n: int) -> bool:
	return flights.has(n) and int(units[flights[n].leader].type) in FLYABLE_TYPES and _side_rule(n)


## FUN_005055a0 in single player: flights 1..4 whose member's record has side 1.
func _side_rule(n: int) -> bool:
	return n >= 1 and n <= 4 and flights.has(n) and int(units[flights[n].leader].side) == 1


## Selects a flight (FUN_00503cb0): its leader becomes the selected unit and the view centres on it.
func select_flight(n: int) -> void:
	if not flights.has(n):
		return
	sel_flight = n
	selected = flights[n].leader
	centre_on(units[selected].pos)


func _map(name: String) -> Dictionary:
	if not _map_cache.has(name):
		var path: String = fe.dir.path_join("emf/%s.json" % name)
		_map_cache[name] = Settings.load_json(path)
	return _map_cache[name]


func _process(_delta: float) -> void:
	var client: Rect2 = fe._rect(CLIENT)
	for c in [get_child(0), windows]:
		c.position = client.position
		c.size = client.size
	map_canvas.position = -scroll * zoom * fe._scale()
	map_canvas.size = MAP_SIZE * zoom * fe._scale()
	overlay.size = client.size
	overlay.queue_redraw()
	queue_redraw()


# --- view ---------------------------------------------------------------------------------


func _view_size() -> Vector2:
	return CLIENT.size / zoom


func _clamp_scroll() -> void:
	scroll = scroll.clamp(Vector2.ZERO, (MAP_SIZE - _view_size()).max(Vector2.ZERO))


## Zoom, then centre the selected unit, or keep the view centre (5032d0).
func zoom_by(factor: float) -> void:
	var centre: Vector2 = units[selected].pos if selected >= 0 else scroll + _view_size() / 2
	var new_zoom := clampf(zoom * factor, 1.0, ZOOM_MAX)
	if is_equal_approx(new_zoom, zoom):
		return
	zoom = new_zoom
	centre_on(centre)
	map_canvas.queue_redraw()


func can_zoom_in() -> bool:
	return zoom < ZOOM_MAX - 0.001


func can_zoom_out() -> bool:
	return zoom > 1.001


func centre_on(map_point: Vector2) -> void:
	scroll = map_point - _view_size() / 2
	_clamp_scroll()


func set_layer(name: String, on: bool) -> void:
	layers[name] = on
	map_canvas.queue_redraw()


# --- briefing window (§6) -------------------------------------------------------------------


func _briefing() -> Dictionary:
	return fe.briefings.get("missions", {}).get(str(mission_id), {})


func has_briefing() -> bool:
	return not _briefing().is_empty()


func open_briefing(open: bool) -> void:
	if not open:
		for w in [brief_window] + link_windows.values():
			if is_instance_valid(w):
				w.queue_free()
		brief_window = null
		link_windows.clear()
		return
	if is_instance_valid(brief_window):
		return
	var b := _briefing()
	if b.is_empty():
		return
	brief_window = _new_window(Rect2(0, 0, floor(2 * CLIENT.size.x / 3), CLIENT.size.y), "framewnd/brief_t.png")
	brief_window.set_text(_text_of(b), _link_names(b))
	brief_window.link_clicked.connect(_on_link.bind(b))
	brief_window.closed.connect(func(): fe.tsd_briefing_closed())


func _new_window(r: Rect2, tab: String) -> Control:
	var w := preload("res://menu/frame_window.gd").new()
	w.setup(fe, CLIENT.position, r)
	w.tab_art = tab
	w.bounds = Rect2(Vector2.ZERO, CLIENT.size)
	windows.add_child(w)
	return w


## Briefing text in the current language; "<header>" becomes "<rank> <pilot name>" (DAT_0083b820 /
## DAT_0083b834, set at Login).
func _text_of(entry: Dictionary) -> String:
	var lang := "he" if fe._he() else "en"
	# null = no translation (briefings.json has "he": null where the Hebrew pack lacks the file).
	var texts: Dictionary = entry.get("text", {})
	var text: String = texts.get(lang) if texts.get(lang) != null else ""
	if text == "":
		text = texts.get("en") if texts.get("en") != null else ""
	var re := RegEx.create_from_string("(?i)<header>")
	return re.sub(text, "%s %s" % [Settings.pilot_rank, Settings.pilot_name], false)


func _link_names(entry: Dictionary) -> Array:
	var lang := "he" if fe._he() else "en"
	var names := []
	for e in entry.get("entries", []):
		var t = e.title.get(lang)
		names.append(String(t if t != null else e.title.en).to_lower())
	return names


## A link opens a window by its .brl type (FUN_00502cd0); an open slot is reused.
func _on_link(name: String, entry: Dictionary) -> void:
	var names := _link_names(entry)
	var i := names.find(name)
	if i < 0:
		return
	var link: Dictionary = entry.entries[i]
	var kind := int(link.get("type", 0))
	var file := String(link.file)
	var stem := file.get_file().get_basename().to_lower()
	# Ours: two type-0 records name a model / a bitmap (the original streams them as RTF): opened by their kind.
	if kind == 0 and file.ends_with(".x"):
		kind = 2
	elif kind == 0 and file.ends_with(".bmp"):
		kind = 3
	# A closed window is freed: its slot reads as none (a typed Control would refuse the freed instance).
	var held = link_windows.get(kind)
	var w: Control = held if is_instance_valid(held) else null
	var cw := CLIENT.size.x
	var ch := CLIENT.size.y
	match kind:
		0:
			# An RTF: a lesson (brief/text) or another briefing text (brief/txt, e.g. the war history 67.rtf).
			var lesson: Dictionary = fe.briefings.get("missions" if "/txt/" in file else "lessons", {}).get(stem, {})
			if lesson.is_empty():
				return
			if not is_instance_valid(w):
				w = _new_window(
					Rect2(floor(cw / 3), floor(ch / 2), floor(2 * cw / 3), floor(ch / 2)), "framewnd/brief_t.png"
				)
				link_windows[kind] = w
				var lw := w
				w.link_clicked.connect(func(n): _on_link(n, lw.get_meta("entry")))
			w.set_meta("entry", lesson)
			w.set_text(_text_of(lesson), _link_names(lesson))
		3:
			var tex: Texture2D = fe.briefing_image(stem)
			if tex == null:
				return
			if not is_instance_valid(w):
				w = _new_window(Rect2(floor(cw / 2), 0, floor(cw / 2), floor(ch / 2)), "")
				w.has_max = false
				link_windows[kind] = w
			w.set_image(tex)
		2:
			# The 3D-model window (§11): the brl's `_h.x` (relative to the install's resource dir; the one path without
			# "\\3dObjects\\" fails to load, as in the original) and its `_h.rtf`; it closes the target window.
			var key := file.trim_prefix("/").trim_suffix(".x")
			if not key.begins_with("3dobjects/"):
				return
			var info: Dictionary = fe.briefings.get("models", {}).get(key, {})
			var v := ModelView.new()
			if not v.setup(fe, key.trim_prefix("3dobjects/") + ".gltf", info.get("cp")):
				v.free()
				return
			if is_instance_valid(link_windows.get(5)):
				link_windows[5].queue_free()
			if not is_instance_valid(w):
				w = _new_window(Rect2(12, 16, 415, 260), "framewnd/obj_t.png")
				link_windows[kind] = w
			var texts: Dictionary = info.get("text", {})
			w.set_model(v, String(texts.get("en")) if texts.get("en") != null else "")
		5:
			# The target window (§10): the first line of brief/tar/<id>_N.txt names a mission object (exact match,
			# FUN_00439c40); none → nothing opens. It closes the 3D-model window; an open one is retargeted.
			var obj := _target_unit(
				(
					FileAccess
					. get_file_as_string(Settings.assets_dir().path_join("install/resource").path_join(file))
					. split("\n")[0]
				)
			)
			if obj.is_empty():
				return
			if is_instance_valid(link_windows.get(2)):
				link_windows[2].queue_free()
			if not is_instance_valid(w):
				w = _new_window(Rect2(22, 16, 406, 322), "framewnd/targ_t.png")
				link_windows[kind] = w
			var v := ModelView.new()
			v.setup_target(fe, obj.world, obj.units)
			w.set_target(v)
		_:
			return
	windows.move_child(w, -1)


## The mission object named `name` (entity 0x2bc, case-sensitive) in this mission's files: {world: Vector3 (X, Y,
## altitude), units: the placed units within TARGET_RADIUS of it for the target view}; {} when none has that name.
const TARGET_RADIUS := 6000.0


func _target_unit(name: String) -> Dictionary:
	var found := {}
	var placed := []  # [world, entity, bdb objects, present scales, bdb name]
	var models: Dictionary = Settings.load_json(Settings.assets_dir().path_join("converted/objects/objects.json"))
	for f in MissionRuntime.mission_files(mission_id):
		var m: Dictionary = f.data
		if m.is_empty():
			continue
		var bdb := MissionRuntime.load_bdb(m)
		var scales := {}
		for pr in bdb.get("present", {}).get("items", []):
			scales[int(pr.get("0x1e", -1))] = float(pr.get("0x65e", 10.0))
		var objs := MissionRuntime.bdb_objects(bdb)
		for e in m.get("entities", {}).get("items", []):
			if not (e is Dictionary) or (float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0):
				continue
			var at := Vector3(float(e["0x2e4"]), float(e["0x2ee"]), float(e.get("0x2f8", 0.0)))
			if found.is_empty() and String(e.get("0x2bc", "")) == name:
				found = {"world": at}
			placed.append([at, e, objs, scales, String(m.get("bdb", "")).to_lower()])
	if found.is_empty():
		return {}
	var units := []
	for p in placed:
		if Vector2(p[0].x, p[0].y).distance_to(Vector2(found.world.x, found.world.y)) > TARGET_RADIUS:
			continue
		var obj: Dictionary = p[2].get(int(p[1].get("0x2c6", -1)), {})
		var present := int(obj.get("0x53c", -1))
		var path: String = models.get(p[4], {}).get(str(present), "")
		if path == "" or int(obj.get("0x5aa", -1)) in [0x11, 0x12, 0x1b]:
			continue
		units.append(
			{
				"path": path,
				"scale": p[3].get(present, 1.0),
				"heading": float(p[1].get("0x302", 0.0)),
				"world": p[0],
				"ground": not int(obj.get("0x5aa", -1)) in [2, 3, 0x1c],
				"klass": int(obj.get("0x5aa", -1))
			}
		)
	found["units"] = units
	return found


# --- drawing ------------------------------------------------------------------------------


func _draw() -> void:
	# Each bar: track, arrows at the ends, thumb between them.
	for axis in 2:
		var bar: Rect2 = BARS[axis]
		var a: String = BAR_ART[axis]
		fe_blit("tsd/%sscroll.png" % a, bar.position)
		fe_blit("tsd/%sslupb_%d.png" % [a, 1 if pressed_arrow == BAR_ARROWS[axis][0] else 0], bar.position)
		fe_blit(
			"tsd/%ssldownb_%d.png" % [a, 1 if pressed_arrow == BAR_ARROWS[axis][1] else 0],
			_along(bar.position, axis, bar.end[axis] - BAR_DOWN[axis])
		)
		fe_blit("tsd/%sslider.png" % a, _along(bar.position, axis, _thumb(axis)))


func fe_blit(path: String, pos: Vector2) -> void:
	var t: Texture2D = fe._tex(path)
	if t != null:
		draw_texture_rect(t, fe._rect(Rect2(pos, fe._art_size(t))), false)


## `v` with its `axis` component replaced by `value`.
static func _along(v: Vector2, axis: int, value: float) -> Vector2:
	v[axis] = value
	return v


## Thumb travel along a bar (screen coordinates of the thumb's start).
func _thumb_range(axis: int) -> Vector2:
	var bar: Rect2 = BARS[axis]
	return Vector2(bar.position[axis] + BAR_UP[axis], bar.end[axis] - BAR_DOWN[axis] - BAR_THUMB[axis])


func _thumb(axis: int) -> float:
	var r := _thumb_range(axis)
	var room := MAP_SIZE[axis] - _view_size()[axis]
	return r.x if room <= 0.0 else lerpf(r.x, r.y, scroll[axis] / room)


## Labels of text.emf: re-issued at their map position without scaling (501060); then units,
## waypoints and the mission title / clock.
func _draw_overlay() -> void:
	var s: float = fe._scale()
	if layers.text:
		for op in map_canvas.text_ops:
			var pos: Vector2 = (op.pos - scroll) * zoom * s
			var px := int(round(op.px * s))
			if px < 1:
				continue
			overlay.draw_string(fe.font, pos, op.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, op.color)
	# Paint 501300 in order: title and clock, the rate, the routes, the units (the selected one last), the ruler.
	# Title and clock: Arial p10 weight 600, white (the second line is always empty).
	var fs := int(round(11 * s))
	var line_h: float = fe.font_bold.get_height(fs) / s
	overlay.draw_string(
		fe.font_bold,
		Vector2(4, 4) * s + Vector2(0, fe.font_bold.get_ascent(fs)),
		mission_title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		Color.WHITE
	)
	overlay.draw_string(
		fe.font_bold,
		Vector2(14, line_h + 6) * s + Vector2(0, fe.font_bold.get_ascent(fs)),
		mission_clock,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		Color.WHITE
	)
	# In flight (FlyTSD): the time compression rate "%dx" (0x654b74) with TA_RIGHT at (Wc - 4, 4) while > 1
	# (@5013f0).
	var rate: int = fe.flight.time_factor if fe.flight != null else 1
	if rate > 1:
		var t := "%dx" % rate
		var w: float = fe.font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		overlay.draw_string(
			fe.font_bold,
			Vector2((CLIENT.size.x - 4) * s - w, 4 * s + fe.font_bold.get_ascent(fs)),
			t,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			Color.WHITE
		)
	if layers.waypoint:
		for n in [1, 2, 3, 4]:
			if flights.has(n) and n != default_flight():
				_draw_route(n, s)
		if flights.has(default_flight()):
			_draw_route(default_flight(), s)
	_draw_units(s)
	_draw_ruler(s)


## Map units -> client pixels (640 space).
func _to_client(m: Vector2) -> Vector2:
	return (m - scroll) * zoom


func _unit_visible(u: Dictionary) -> bool:
	var filter: String = "airports" if u.airport else FILTERS[u.klass]
	return fe.tsd_checks.get("%s%d" % [filter, 1 if u.side == 1 else 2], true)


## Unit icons (FUN_00504ea0), centred on the unit; plain copies of the icon cell.
func _draw_units(s: float) -> void:
	for i in units.size():
		var u: Dictionary = units[i]
		if not _unit_visible(u):
			continue
		var c := _to_client(u.pos)
		var art: String = "icairport" if u.airport else ICON_ART[u.klass]
		var cell: Rect2
		if u.klass == 1:
			var row := 1 if u.side > 1 else (0 if u.leader else 2)
			var col := (int(fposmod(u.heading, 360.0)) / 45) % 8
			cell = Rect2(col * 27, row * 21, 27, 21)
		else:
			cell = Rect2(0, (1 if u.side > 1 else 0) * 17, 27, 17)
		var top_left := (c - (cell.size / 2).floor()).floor()
		var t: Texture2D = fe._tex("tsd/%s.png" % art)
		if t != null:
			var a: float = fe.art_scale
			overlay.draw_texture_rect_region(
				t, Rect2(top_left * s, cell.size * s), Rect2(cell.position * a, cell.size * a)
			)
		if u.cls == 8 and SAM_RING.has(u.type):
			var r := floorf(floorf(SAM_RING[u.type]) * MAP_SIZE.x / WORLD_W) * zoom
			overlay.draw_arc(c * s, r * s, 0, TAU, 64, Color.WHITE, maxf(1.0, s), true)
		if u.klass == 1 and u.flight >= 1 and u.flight <= 4:
			overlay.draw_rect(
				Rect2((top_left - Vector2(2, 2)) * s, (cell.size + Vector2(4, 4)) * s),
				FLIGHT_COLORS[u.flight - 1],
				false,
				2 * s
			)
	if selected >= 0 and _unit_visible(units[selected]):
		var u: Dictionary = units[selected]
		var t := _selection_texture("icselair" if u.klass == 1 else "icselveh")
		if t != null:
			var sz: Vector2 = Vector2(t.get_width(), t.get_height()) / fe.art_scale
			var top_left := (_to_client(u.pos) - (sz / 2).floor()).floor()
			overlay.draw_texture_rect(t, Rect2(top_left * s, sz * s), false)
			# The two-line label (FUN_005053c0), yellow, TA_CENTER|TA_TOP: the type 2 px below the icon, the flight
			# name a line lower.
			var x := top_left.x + floorf(sz.x / 2)
			var y := top_left.y + 2 + sz.y
			_text_top(unit_label(u), Vector2(x, y), LABEL_COLOR, s)
			var n := int(u.flight)
			if n >= 1 and n < FLIGHT_LABELS.size() and flights.has(n):
				_text_top(FLIGHT_LABELS[n], Vector2(x, y + _line_h(s) + 2), LABEL_COLOR, s)


## Line 1 of the selected-unit label: the type's name (FUN_004f6da0 → FUN_004f7670), a runway's own name.
static func unit_label(u: Dictionary) -> String:
	if int(u.type) == 450:
		return String(u.name).left(20)
	return TYPE_NAMES.get(int(u.type), CLASS_NAMES.get(int(u.cls), ""))


## The overlay font's line height L (`this+0x60`) in 640-space pixels.
func _line_h(s: float) -> float:
	return roundf(fe.font_bold.get_height(int(round(11 * s))) / s)


## Overlay text with TA_CENTER|TA_TOP at client point `p` (640 space).
func _text_top(text: String, p: Vector2, color: Color, s: float) -> void:
	if text == "":
		return
	var fs := int(round(11 * s))
	var w: float = fe.font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	overlay.draw_string(
		fe.font_bold,
		Vector2(p.x * s - w / 2, p.y * s + fe.font_bold.get_ascent(fs)),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		color
	)


## The ruler (paint 501300, while dragging and after): a white dot at the start (Ellipse(x−2, y−2, x+3, y+3)), a
## white line with a two-stroke arrow at the end, and in red under the end the distance "%.2f NM" and the true
## bearing "%03d T" (90° − atan2(dy, dx), wrapped into 0..360, truncated).
func _draw_ruler(s: float) -> void:
	if not (ruler_on or ruler_kept):
		return
	var a := _client_px(ruler_a)
	var b := _client_px(ruler_b)
	var w := Color.WHITE
	overlay.draw_circle((a + Vector2(0.5, 0.5)) * s, 2.5 * s, w)
	overlay.draw_line(a * s, b * s, w, maxf(1.0, s))
	var d := ruler_b - ruler_a
	var ang := atan2(d.y, d.x)
	if a != b:
		var p1 := (
			b
			+ Vector2(
				-int(RULER_ARROW * sin(PI / 2 - ang - RULER_ARROW_ANGLE)),
				int(RULER_ARROW * cos(PI / 2 - ang - RULER_ARROW_ANGLE))
			)
		)
		var p2 := (
			b
			+ Vector2(-int(RULER_ARROW * cos(ang - RULER_ARROW_ANGLE)), int(RULER_ARROW * sin(ang - RULER_ARROW_ANGLE)))
		)
		overlay.draw_line(b * s, p1 * s, w, maxf(1.0, s))
		overlay.draw_line(b * s, p2 * s, w, maxf(1.0, s))
	var l := _line_h(s)
	_text_top(ruler_distance(ruler_a, ruler_b), Vector2(b.x, b.y + 2 + l), RULER_TEXT, s)
	_text_top(ruler_bearing(ruler_a, ruler_b), Vector2(b.x, b.y + 2 + l + 2 + l), RULER_TEXT, s)


## A world point (X, Y) in whole client pixels (`FUN_00500ec0` × z, __ftol).
func _client_px(w: Vector2) -> Vector2:
	var c := _to_client(world_to_map(w.x, w.y))
	return Vector2(int(c.x), int(c.y))


static func ruler_distance(a: Vector2, b: Vector2) -> String:
	return "%.2f NM" % (a.distance_to(b) * RULER_NM)


static func ruler_bearing(a: Vector2, b: Vector2) -> String:
	var t := -(rad_to_deg(atan2(b.y - a.y, b.x - a.x)) - 90.0)
	while t < 0.0:
		t += 360.0
	while t >= 360.0:
		t -= 360.0
	return "%03d T" % int(t)


## Selection art: a masked sprite (top half sprite, bottom half its AND mask).
func _selection_texture(name: String) -> Texture2D:
	if sel_textures.has(name):
		return sel_textures[name]
	var src: Texture2D = fe._tex("tsd/%s.png" % name)
	if src == null:
		return null
	sel_textures[name] = ImageTexture.create_from_image(Img.masked_sprite(src.get_image()))
	return sel_textures[name]


## A flight's route: numbered circles (r 10 px) in the flight colour, joined when > 20 px apart.
func _draw_route(n: int, s: float) -> void:
	var color: Color = FLIGHT_COLORS[n - 1]
	var pts: Array = flights[n].points
	var fs := int(round(11 * s))
	for i in pts.size():
		var c := _to_client(pts[i])
		if i > 0:
			var prev := _to_client(pts[i - 1])
			if prev.distance_to(c) > 20:
				overlay.draw_line(prev * s, c * s, color, 2 * s, true)
	for i in pts.size():
		var c := _to_client(pts[i])
		overlay.draw_circle(c * s, 10 * s, color)
		overlay.draw_string(
			fe.font_bold,
			(c + Vector2(0, 4)) * s - Vector2(20 * s, 0),
			str(i + 1),
			HORIZONTAL_ALIGNMENT_CENTER,
			40 * s,
			fs,
			Color.WHITE
		)


# --- input ----------------------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouse):
		return
	var p: Vector2 = fe._to_menu(event.position)
	if _map_input(event, p - CLIENT.position):
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for axis in [1, 0]:
				if BARS[axis].has_point(p):
					_bar_press(p, axis)
					accept_event()
					break
		elif pressed_arrow != "" or dragging >= 0:
			pressed_arrow = ""
			dragging = -1
			accept_event()
	elif event is InputEventMouseMotion and dragging >= 0:
		var r := _thumb_range(dragging)
		scroll[dragging] = (
			clampf(inverse_lerp(r.x, r.y, p[dragging] - drag_offset), 0, 1)
			* maxf(0, MAP_SIZE[dragging] - _view_size()[dragging])
		)
		accept_event()


## Map mouse input (client coordinates; the map window captures the mouse while a button is down):
## * left press (FUN_00501e50): a unit's icon selects that unit; elsewhere the selection clears and a waypoint of the
##   selected flight within 10 px (FUN_00504dd0) starts a drag;
## * left move (501cb0): the dragged waypoint follows the cursor, before the flight only (in flight it stays put,
##   as the manual says: no waypoint changes after take-off);
## * left double-click (FUN_00501ef0): an own flight leader of a flyable type (class 0x1c) flies; in flight any
##   other unit is visited;
## * right press / move / release (5022d0 / 501cb0 / 502380): the ruler.
func _map_input(event: InputEvent, c: Vector2) -> bool:
	var inside := Rect2(Vector2.ZERO, CLIENT.size).has_point(c)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and inside:
			ruler_on = true
			ruler_kept = false
			ruler_a = _client_to_world(c)
			ruler_b = ruler_a
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN  # WM_SETCURSOR (501c60): no cursor while measuring
			return true
		if not event.pressed and ruler_on:
			ruler_on = false
			ruler_kept = true
			ruler_b = _client_to_world(c)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return true
		return false
	if not inside and drag_wp < 0 and not ruler_on:
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if drag_wp >= 0:
				drag_wp = -1
				return true
			return false
		if event.double_click:
			_double_click(c)
			return true
		var hit := unit_at(c)
		selected = hit
		if hit >= 0:
			return true
		drag_wp = _waypoint_at(c)
		return true
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and drag_wp >= 0:
			var n := default_flight()
			if fe.flight == null and flights.has(n):
				flights[n].points[drag_wp] = (c.clamp(Vector2.ZERO, CLIENT.size) / zoom + scroll).clamp(
					Vector2.ZERO, MAP_SIZE
				)
			return true
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT and ruler_on:
			ruler_b = _client_to_world(c)
			return true
	return false


## A client point → world X / Y (`FUN_00500f70` of point / z).
func _client_to_world(c: Vector2) -> Vector2:
	return map_to_world(Vector2(int(c.x), int(c.y)) / zoom + scroll)


## Double-click (FUN_00501ef0): the unit under the cursor becomes the selection; a flight leader (record [0x18]) of
## class 0x1c with a flyable type, on the side rule, flies (its flight becomes the selected one); otherwise, in flight
## only, the unit is visited.
func _double_click(c: Vector2) -> void:
	selected = unit_at(c)
	if selected < 0:
		return
	var u: Dictionary = units[selected]
	if int(u.cls) == 0x1c and int(u.type) in FLYABLE_TYPES and u.leader and _side_rule(int(u.flight)):
		fe.tsd_fly_flight(int(u.flight))
	elif fe.flight != null:
		fe.tsd_visit(String(u.key))


## The unit whose icon holds client point `c` (FUN_00504c00), -1 for none. The icon rects are the drawn cells,
## inclusive on all sides. The selected unit is tried first, then the others from the last record down, with the
## exe's walk: after a visible selected unit the walk restarts at count − 1 and steps once before testing, so the last
## record is skipped; a hidden selected unit makes the walk continue below it.
func unit_at(c: Vector2) -> int:
	var count := units.size()
	var px := Vector2i(int(c.x), int(c.y))
	var i := count
	while true:
		var test := -1
		if i != selected:
			if i != count:
				test = i
			elif selected != -1:
				test = selected
		if test >= 0:
			i = test
			if _unit_visible(units[i]):
				var size := Vector2i(27, 21) if units[i].klass == 1 else Vector2i(27, 17)
				var cc := _to_client(units[i].pos)
				var tl := Vector2i(int(cc.x) - size.x / 2, int(cc.y) - size.y / 2)
				if px.x >= tl.x and px.x <= tl.x + size.x and px.y >= tl.y and px.y <= tl.y + size.y:
					return i
				if i == selected:
					i = count - 1
		i -= 1
		if i < 0:
			return -1
	return -1


## The waypoint of the selected flight within 10 px of `c` (FUN_00504dd0: last waypoint first), -1 for none; only
## with Waypoint on.
func _waypoint_at(c: Vector2) -> int:
	var n := default_flight()
	if not layers.waypoint or not flights.has(n):
		return -1
	var pts: Array = flights[n].points
	for i in range(pts.size() - 1, -1, -1):
		var p := _to_client(pts[i])
		if Vector2(int(c.x), int(c.y)).distance_squared_to(Vector2(int(p.x), int(p.y))) <= 100.0:
			return i
	return -1


## The map window's keys (WM_KEYDOWN 5023e0): the arrows scroll 5 map units, Page Up / Down page vertically
## (502a90 codes 2 / 3), Numpad + zooms in, Numpad − and Insert zoom out (the handler also lists the character
## codes '+' '=' '-' '_'; as virtual keys only 0x2d, Insert, comes from a key). Returns whether the key was used.
func key(code: Key) -> bool:
	match code:
		KEY_LEFT:
			scroll.x -= ARROW_STEP
		KEY_RIGHT:
			scroll.x += ARROW_STEP
		KEY_UP:
			scroll.y -= ARROW_STEP
		KEY_DOWN:
			scroll.y += ARROW_STEP
		KEY_PAGEUP:
			scroll.y -= _view_size().y
		KEY_PAGEDOWN:
			scroll.y += _view_size().y
		KEY_KP_ADD:
			if can_zoom_in():
				zoom_by(ZOOM_STEP)
		KEY_KP_SUBTRACT, KEY_INSERT:
			if can_zoom_out():
				zoom_by(1.0 / ZOOM_STEP)
		_:
			return false
	_clamp_scroll()
	return true


func _exit_tree() -> void:
	if ruler_on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _bar_press(p: Vector2, axis: int) -> void:
	var bar: Rect2 = BARS[axis]
	var t := _thumb(axis)
	if p[axis] < bar.position[axis] + BAR_UP[axis]:
		pressed_arrow = BAR_ARROWS[axis][0]
		scroll[axis] -= ARROW_STEP / zoom
	elif p[axis] >= bar.end[axis] - BAR_DOWN[axis]:
		pressed_arrow = BAR_ARROWS[axis][1]
		scroll[axis] += ARROW_STEP / zoom
	elif p[axis] >= t and p[axis] < t + BAR_THUMB[axis]:
		dragging = axis
		drag_offset = p[axis] - t
	else:
		scroll[axis] += _view_size()[axis] * (1 if p[axis] > t else -1)
	_clamp_scroll()
