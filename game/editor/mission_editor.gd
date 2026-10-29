# The mission editor (ours, docs/mission-editor.md): opens a converted mission, edits it on the pre-flight TSD's map
# (game/menu/tsd.gd in its edit mode, hosted by MapHost below) and saves it under user://missions/. The original
# missions only open read-only; Fork copies one into a mission of your own. Fly starts the edited mission through the
# game's TSD (Settings.fly_edited). The mission logic (ids, routes, flights, the checks) is IafMissionEdit's.
extends Control

const Tsd := preload("res://menu/tsd.gd")
const EditApi := preload("res://editor/_edit_api.gd")
const Img := preload("res://util/img.gd")
const ScenarioEditor := preload("res://editor/scenario_editor.gd")

const UNDO_MAX := 50
## A take-off waypoint's planned time while its flight waits for a rule (mission_events.rs WAIT_T,
## docs/mission-editor.md §18.3), and the time it gets back (the enemy flights' 30 s).
const WAIT_T := 1.0e7
const NO_WAIT_T := 30.0
## The Add picker's classes: label → bdb object classes (0x5aa).
const ADD_CLASSES := [
	["Aircraft", [2, 3, 0x1c]],
	["SAM / AAA", [8, 9, 10, 11]],
	["Vehicles", [5, 6]],
	["Buildings", [0xc, 0xd, 0x1d, 0x1e]],
	["Ships", [0xf, 0x10]],
]
const AIR_CLASSES := [2, 3, 0x1c]
const SHIP_CLASSES := [0xf, 0x10]
const SIDES := ["Blue", "Red", "Neutral"]
const ROLES := ["Must survive", "Target", "Neutral"]
## One colour per side (Blue, Red, Neutral) wherever the editor names a side: the Units list's rows, the map's labels
## and the legend; the TSD's blue and red icons.
const SIDE_COLORS := [Color(0.45, 0.75, 1.0), Color(1.0, 0.45, 0.4), Color(0.75, 0.75, 0.75)]
## The selection's ring on the map: white, apart from both sides' colours and the checks' yellow and red rings.
const SEL_COLOR := Color.WHITE
## Every unit's name shows under its icon from this zoom on (the TSD's own label names the selected unit only).
const NAMES_ZOOM := 8.0
## The editor's labels and status line (theme font size).
const MARK_FS := 14
## Wind as the Mission Creator's Better combos (mission_creator.gd); Random stores 1, which the game turns into a
## random one of 0 / 10 / 15 / 20 kt (Settings.pick_wind).
const WIND_KT := [["Calm", 0], ["10 kt", 10], ["15 kt", 15], ["20 kt", 20], ["Random", 1]]
const WIND_FROM := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
## The weather (ours, misc `weather`, docs/formats/mis.md): [label, value]; Random picks one at the start
## (Settings.mission_weather). Default (no weather of its own, as the originals) rains at the Graphics Rain level.
const WEATHER := [
	["Default (Graphics Rain)", ""],
	["Clear", "clear"],
	["Light rain", "light"],
	["Heavy rain", "heavy"],
	["Random", "random"],
]
## The scenery's buildings (docs/scenery.md §5): drawn from this zoom on (a 20 m house is a few pixels), the editor
## zooming in to SCENERY_ZOOM_MAX; a click picks a building within PICK_PX pixels.
const BUILDINGS_ZOOM := 240.0
const SCENERY_ZOOM_MAX := 1024.0
const PICK_PX := 6.0
const BUILDING_COLOR := Color(0.85, 0.85, 0.8, 0.7)
const SCENERY_MARKER := 51  # bdb object civilhouse, a scenery target's marker

## Where your missions are saved (a test points it elsewhere).
var missions_dir := "user://missions"
var api := EditApi.new()
var mission_dir := ""
## The original missions: id → {title, files: [stem…]} (missionlist.json, misc 0x44c).
var originals := {}
## A placed entity of each bdb object id from the originals, the template for Add.
var templates := {}

var source := -1  # the mission id the edited mission is built on
var mission_name := ""
var main_name := ""  # the main file's name (the source's)
var data := {}  # the main file being edited
var base_files: Array = []  # [{name, data}], re-read from the source
var briefing := {"en": "", "he": ""}
## The mission year (1966 … 1998; 1967 is the Six-Day War itself, from the pre-war lines) and whether
## never-served (what-if) aircraft are allowed; both saved in the custom file (docs/mission-editor.md §12).
var year := 1998.0
var what_if := false
var file := ""  # its user:// file, "" while unsaved
var read_only := true
var objects := {}  # the bdb's Objects by id
var undo: Array = []
var issues: Array = []
var conditions := {}  # what passes and fails the mission (IafMissionEdit.conditions)
var sel_id := -1  # the selected entity (main file)
var sel_wp := -1  # the selected waypoint of the TSD's selected flight
var mode := ""  # "" | "add" | "route"
var route_pts: Array = []  # world Vector3, while drawing a route
## While drawing a route: the line the units will drive (world, along the roads when they follow them) through the
## clicked points, and on to the mouse.
var route_line := PackedVector2Array()
var route_ghost := PackedVector2Array()
var has_roads := false  # the road layer of setup (IafRoads): ground routes can follow the roads
var _ghost_timer := Timer.new()
var add_object := -1  # the bdb object id the Add places
## Under the mouse on the map: a unit (tsd.units index), a waypoint of the selected flight, the world point (null off
## the map); and in Add the ground check of that point (IafMissionEdit.place_issues).
var hover := -1
var hover_wp := -1
var mouse_world = null
var place_check: Array = []
## The Units list's row under the mouse (an entity id, -1 for none): its unit gets a ring and label on the map.
var list_hover := -1

var tsd: Control
var host: Control
var _ui := {}
var has_scenery := false
## The building a click picked: {id, height, area, points}, {} for none.
var sel_building := {}
var _outlines_key := []
var _outlines := PackedVector2Array()
var _name_purpose := ""


func _ready() -> void:
	mission_dir = Settings.assets_dir().path_join("converted/missions")
	_load_originals()
	has_scenery = api.has_scenery()
	has_roads = IafRoads.open(Settings.assets_dir().path_join("converted/roads"))
	_ghost_timer.one_shot = true
	_ghost_timer.wait_time = 0.12
	_ghost_timer.timeout.connect(_road_ghost)
	add_child(_ghost_timer)
	_build_ui()
	_hidpi()
	var reopen: String = Settings.editor_file
	if reopen != "" and FileAccess.file_exists(reopen):
		open_file(reopen)
	else:
		_refresh()


# --- missions -------------------------------------------------------------------------------------------------------


func _load_originals() -> void:
	var list := Settings.load_json(mission_dir.path_join("missionlist.json"))
	for k in list:
		# 666 (0x29a) is the Mission Creator's template and 777 multiplayer All-Out War: not missions to fork.
		if int(k) in [0x29a, 777]:
			continue
		var stems: Array = list[k]
		var m := Settings.load_json(mission_dir.path_join(String(stems[0]) + ".json"))
		if m.is_empty():
			continue
		var misc: Array = m.get("misc", {}).get("items", [])
		originals[int(k)] = {"title": String(misc[0].get("0x44c", k)) if not misc.is_empty() else k, "files": stems}
		for e in m.get("entities", {}).get("items", []):
			var t := int(e.get("0x2c6", -1))
			if t >= 0 and int(e.get("0x14", 0)) == 0 and not templates.has(t):
				templates[t] = e


## Your missions: [{name, path}].
func own_missions() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(missions_dir):
		return out
	for f in DirAccess.get_files_at(missions_dir):
		if f.ends_with(".json"):
			var d := Settings.load_json(missions_dir.path_join(f))
			out.append({"name": String(d.get("name", f.get_basename())), "path": missions_dir.path_join(f)})
	return out


func _taken() -> PackedStringArray:
	var out := PackedStringArray()
	for id in originals:
		out.append(originals[id].title)
	for m in own_missions():
		out.append(m.name)
	return out


func _read_bases(id: int, stems: Array = []) -> Array:
	var out := []
	for stem in stems if not stems.is_empty() else originals.get(id, {}).get("files", []).slice(1):
		if stem is Dictionary:  # a base mission with its sides flipped, kept in the custom file
			out.append({"name": String(stem.name), "data": stem.data, "flipped": true})
			continue
		out.append({"name": String(stem), "data": Settings.load_json(mission_dir.path_join(String(stem) + ".json"))})
	return out


func open_original(id: int) -> void:
	if not originals.has(id):
		return
	var stems: Array = originals[id].files
	_open(id, originals[id].title, String(stems[0]), Settings.load_json(mission_dir.path_join(stems[0] + ".json")))
	var b: Dictionary = (
		Settings
		. load_json(Settings.assets_dir().path_join("converted/briefings/briefings.json"))
		. get("missions", {})
		. get(str(id), {})
		. get("text", {})
	)
	for lang in ["en", "he"]:
		briefing[lang] = _plain(String(b.get(lang))) if b.get(lang) != null else ""
	_intel_opened(_original_links(id), {})
	read_only = true
	file = ""
	_default_year()
	_refresh()


## An original's year by its id; the game's own future (2xx and up) flies the Lavi, so what-if is on there.
func _default_year() -> void:
	year = api.default_year(source)
	what_if = source >= 200


func open_file(path: String) -> void:
	var d := Settings.load_json(path)
	if d.is_empty() or d.get("files", []).is_empty():
		return
	_open(int(d.source), String(d.name), String(d.files[0].name), d.files[0].data)
	_default_year()
	year = floorf(float(d.get("year", year)))
	what_if = bool(d.get("what_if", what_if))
	if d.has("bases"):
		base_files = _read_bases(source, d.bases)
		_refresh()
	var b: Dictionary = d.get("briefing", {})
	briefing = {"en": String(b.get("en", "")), "he": String(b.get("he", ""))}
	_intel_opened(b.get("entries", []), d.get("random", {}))
	read_only = false
	file = path
	_refresh()


func _open(id: int, name: String, main: String, main_data: Dictionary) -> void:
	source = id
	parked_bases.clear()
	mission_name = name
	main_name = main
	data = main_data
	base_files = _read_bases(id)
	objects = Tsd.MissionRuntime.bdb_objects(Tsd.MissionRuntime.load_bdb(data))
	undo.clear()
	sel_id = -1
	sel_wp = -1
	mode = ""
	_new_map(id)
	_fill_object_picker()
	_fill_flight_types()


## A fresh TSD for mission `id` (its era's map; 0 = the modern map with no units).
func _new_map(id: int) -> void:
	if tsd != null:
		tsd.queue_free()
	tsd = Tsd.new()
	host.add_child(tsd)
	host.move_child(tsd, 0)
	host.tsd = tsd
	tsd.setup(host, id)
	tsd.edit = true
	if has_scenery:
		tsd.zoom_max = SCENERY_ZOOM_MAX
		tsd.draw_under = _draw_buildings
	host.fit()
	tsd.unit_dragged.connect(_on_unit_dragged)
	tsd.waypoint_dragged.connect(_on_waypoint_dragged)
	tsd.map_clicked.connect(_on_map_clicked)
	_frame_view()


## The editor opens zoomed in (two TSD steps) on the blue units, else on Israel (near Jerusalem's label).
func _frame_view() -> void:
	var sum := Vector2.ZERO
	var n := 0
	for u in tsd.units:
		if int(u.side) == 1:
			sum += u.pos
			n += 1
	tsd.zoom = Tsd.ZOOM_STEP * Tsd.ZOOM_STEP
	tsd.centre_on(sum / n if n > 0 else Vector2(255, 300))


## HiDPI (a Mac's Retina screen): the controls grow with the OS scale, as the setup wizard's do.
## The window then grows to hold 1600 × 1000 of those scaled units (as far as the work area allows), centred, as the
## setup wizard sizes its window (wizard.gd).
func _hidpi() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	var win := get_window()
	if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		return
	if win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED
		await get_tree().process_frame
	var scale := maxf(1.0, DisplayServer.screen_get_scale(win.current_screen))
	win.content_scale_factor = scale
	var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
	var want := Vector2i(mini(int(1600 * scale), screen.size.x), mini(int(1000 * scale), screen.size.y))
	DisplayServer.window_set_size(want, win.get_window_id())
	DisplayServer.window_set_position(screen.position + (screen.size - want) / 2, win.get_window_id())


## The briefing's BBCode as plain text.
static func _plain(bb: String) -> String:
	return RegEx.create_from_string("\\[/?[a-zA-Z][^\\]]*\\]").sub(bb, "", true)


## The files Fly and the map use: the edited main file, then the source's base missions.
func files() -> Array:
	return [{"name": main_name, "data": data}] + base_files


## "" when `name` can be a new name for your mission, else the reason.
func name_error(name: String) -> String:
	var why := api.valid_name(name)
	if why != "":
		return why
	for id in originals:
		if String(originals[id].title).to_lower() == name.to_lower():
			return "An original mission is called %s." % originals[id].title
	return ""


## Whether `name` would replace another of your missions (the file names compare without case).
func own_clash(name: String) -> bool:
	var path := _path_of(name)
	for m in own_missions():
		if m.path.to_lower() == path.to_lower() or String(m.name).to_lower() == name.to_lower():
			return m.path != file
	return false


func _path_of(name: String) -> String:
	return missions_dir.path_join(api.stem(name) + ".json")


func suggest_name() -> String:
	return api.free_name(mission_name, _taken())


## A new mission called `name` from scratch on the year's original (IafMissionEdit year_source: its TSD map and
## airbases): only Alpha stays, at blue home base `base` (a name of year_bases) with `jet`, and a wingman if asked.
func new_mission(name: String, y: float, base: String, jet: int, wingman: bool, hypothetical := false) -> void:
	var b := {}
	for it in api.year_bases(y, 1):
		if it.name == base:
			b = it
	if b.is_empty():
		return
	open_original(api.year_source(y))
	year = y
	what_if = hypothetical
	data = api.blank(data)
	_add_base(b.stem, 1)
	var st: Array = b.start
	var ahead := Vector2(st[0], st[1]) + Vector2.from_angle(deg_to_rad(90.0 - st[3])) * 20000.0
	var spec := {"type": jet, "count": 2 if wingman else 1, "slot_x": st[0], "slot_y": st[1], "alt": st[2]}
	# Planned arrival 150 s after the start: the take-off and 20 km at about 250 m/s (inferred).
	spec.merge({"heading": st[3], "points": [[ahead.x, ahead.y, 3000.0, 150.0, 2]]})
	data = api.set_flight(data, 1, spec)
	briefing = {"en": "", "he": ""}
	_intel_opened([], {})
	read_only = false
	file = ""
	save_as(name)
	_refresh()
	_frame_view()


## Base mission `stem` among the base files, for `side`: added when missing; a copy with blue and red swapped when the
## data has it for the other side (its runway, the first unit, tells).
func _add_base(stem: String, side: int) -> void:
	for i in base_files.size():
		var f: Dictionary = base_files[i]
		if f.name == stem or f.name == stem + "_flipped":
			if _base_side(f.data) == side:
				return
			base_files.remove_at(i)
			break
	var d := Settings.load_json(mission_dir.path_join(stem + ".json"))
	if _base_side(d) == side:
		base_files.append({"name": stem, "data": d})
	else:
		base_files.append({"name": stem + "_flipped", "data": api.flip_base(d), "flipped": true})


static func _base_side(d: Dictionary) -> int:
	for e in d.get("entities", {}).get("items", []):
		if int(e.get("0x14", 0)) == 0:
			return int(e.get("0x2d0", 0))
	return 0


## A red flight of `count` `jet`s taking off from red base `stem` (IafMissionEdit set_red_flight); the base mission
## comes with it.
func add_enemy_flight(stem: String, jet: int, count: int) -> void:
	if read_only or data.is_empty():
		return
	_add_base(stem, 2)
	var name := String(objects.get(jet, {}).get("0x528", "Red")).replace("MIG", "MiG")
	var spec := {"type": jet, "count": count, "base": stem, "name": name}
	if templates.has(jet):
		spec["template"] = templates[jet]
	_edit(api.set_red_flight(data, spec))


## The year (or the what-if switch) changed: the checks run again.
func set_year(y: float, hypothetical: bool) -> void:
	year = y
	what_if = hypothetical
	_follow_year_map()
	_refresh()


## Deletes the open mission's file (your own only: originals are never touched) and closes it.
func delete_mission() -> void:
	if read_only or file == "" or not file.begins_with(missions_dir):
		return
	DirAccess.remove_absolute(file)
	source = -1
	mission_name = ""
	data = {}
	base_files = []
	file = ""
	read_only = true
	undo.clear()
	if tsd != null:
		tsd.queue_free()
		tsd = null
		host.tsd = null
	_refresh()


## The open mission copied into your own, called `name` (name_error / own_clash answered first).
func fork(name: String) -> void:
	read_only = false
	file = ""
	save_as(name)


func save_as(name: String) -> void:
	if read_only or name_error(name) != "":
		return
	mission_name = name
	data.misc.items[0]["0x44c"] = name
	file = _path_of(name)
	save()


func save() -> void:
	if read_only or file == "":
		return
	DirAccess.make_dir_recursive_absolute(missions_dir)
	var out := {"source": source, "name": mission_name, "files": [{"name": main_name, "data": data}]}
	# The base missions by name (New may add a home base the source lacks); read again at Open.
	out["bases"] = base_files.map(
		func(f): return {"name": f.name, "data": f.data} if f.get("flipped", false) else f.name
	)
	out["year"] = year
	out["what_if"] = what_if
	out["briefing"] = briefing.duplicate(true)
	out["random"] = random
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "\t", false, true))
	_refresh()


# --- editing --------------------------------------------------------------------------------------------------------


## Takes `new_data` as the mission, the old one onto the undo stack.
# ponytail: whole-mission snapshots (a mission is ≤ 160 kB); per-edit diffs if missions get large.
func _edit(new_data: Dictionary) -> void:
	if read_only:
		_refresh()
		return
	undo.append(data)
	if undo.size() > UNDO_MAX:
		undo.pop_front()
	data = new_data
	_refresh()


func undo_last() -> void:
	if undo.is_empty() or read_only:
		return
	data = undo.pop_back()
	_refresh()


func entity(id: int) -> Dictionary:
	for e in data.get("entities", {}).get("items", []):
		if int(e.get("0x1e", -1)) == id and int(e.get("0x14", 0)) == 0:
			return e
	return {}


func _class_of(e: Dictionary) -> int:
	return int(objects.get(int(e.get("0x2c6", -1)), {}).get("0x5aa", -1))


## Moves entity `id` to world X / Y; a ground unit takes the terrain's height.
func move_entity(id: int, x: float, y: float) -> void:
	var d := data.duplicate(true)
	var e := _entity_in(d, id)
	if e.is_empty() or e.has("scenery"):  # a scenery target stays on its building
		_refresh()
		return
	e["0x2e4"] = roundf(x)
	e["0x2ee"] = roundf(y)
	if not _class_of(e) in AIR_CLASSES:
		var g = api.ground_height(x, y)
		if g != null:
			e["0x2f8"] = roundf(g)
	_edit(d)


static func _entity_in(d: Dictionary, id: int) -> Dictionary:
	for e in d.entities.items:
		if int(e.get("0x1e", -1)) == id and int(e.get("0x14", 0)) == 0:
			return e
	return {}


## Adds a unit of bdb object `obj` at world X / Y; returns its id (-1 when none was added).
func add_unit(obj: int, x: float, y: float, side: int, role: int) -> int:
	if read_only or not objects.has(obj):
		return -1
	var template: Dictionary = templates.get(obj, {})
	for e in data.entities.items:
		if int(e.get("0x2c6", -1)) == obj and int(e.get("0x14", 0)) == 0:
			template = e
	if template.is_empty():
		template = data.entities.items[0]
	var air := int(objects[obj].get("0x5aa", -1)) in AIR_CLASSES
	var g = api.ground_height(x, y)
	var fields := {
		"0x2bc": "%s_%d" % [objects[obj].get("0x514", "unit"), data.entities.items.size()],
		"0x2c6": obj,
		"0x2d0": side,
		"0x2e4": roundf(x),
		"0x2ee": roundf(y),
		"0x2f8": 3000.0 if air else (roundf(g) if g != null else 0.0),
		"0x302": 0,
		"0x32a": role,
		"0x35c": 1,
	}
	var r := api.add_entity(data, template, fields)
	if int(r.id) < 0:
		return -1
	sel_id = int(r.id)
	_edit(r.mission)
	return sel_id


func delete_selected() -> void:
	if sel_id >= 0:
		var id := sel_id
		sel_id = -1
		_edit(api.remove_entity(data, id))


func set_field(key: String, value) -> void:
	if entity(sel_id).is_empty() or entity(sel_id).get(key) == value:
		return
	var d := data.duplicate(true)
	_entity_in(d, sel_id)[key] = value
	_edit(d)


func _formation_of(n: int) -> int:
	return int(tsd.flights[n].formation) if tsd != null and tsd.flights.has(n) else -1


func set_waypoint(n: int, i: int, x: float, y: float) -> void:
	var fo := _formation_of(n)
	if fo < 0:
		return
	var d := data.duplicate(true)
	var p: Array = d.formations.items[fo].points[i]
	p[1] = roundf(x)
	p[2] = roundf(y)
	_edit(d)


func set_waypoint_value(column: int, value: float) -> void:
	var fo := _formation_of(tsd.sel_flight)
	if fo < 0 or sel_wp < 0 or sel_wp >= data.formations.items[fo].points.size():
		return
	var d := data.duplicate(true)
	d.formations.items[fo].points[sel_wp][column] = value
	_edit(d)


## A waypoint after the selected one (halfway to the next, or 5 km on), or the selected one removed.
func insert_waypoint() -> void:
	var fo := _formation_of(tsd.sel_flight)
	if fo < 0:
		return
	var d := data.duplicate(true)
	var pts: Array = d.formations.items[fo].points
	var i := clampi(sel_wp, 0, pts.size() - 1)
	var p: Array = pts[i].duplicate()
	if i + 1 < pts.size():
		p[1] = roundf((float(pts[i][1]) + float(pts[i + 1][1])) / 2)
		p[2] = roundf((float(pts[i][2]) + float(pts[i + 1][2])) / 2)
	else:
		p[1] = float(p[1]) + 5000.0
	p[5] = 0
	pts.insert(i + 1, p)
	_renumber(pts)
	sel_wp = i + 1
	_edit(d)


## The selected flight's take-off waits for a rule (wp0's planned time WAIT_T) or takes off at NO_WAIT_T.
func set_waits(on: bool) -> void:
	var fo := _formation_of(tsd.sel_flight)
	if fo < 0 or data.formations.items[fo].points.is_empty():
		return
	var d := data.duplicate(true)
	d.formations.items[fo].points[0][4] = WAIT_T if on else NO_WAIT_T
	_edit(d)


func delete_waypoint() -> void:
	var fo := _formation_of(tsd.sel_flight)
	if fo < 0 or sel_wp < 0 or data.formations.items[fo].points.size() <= 1:
		return
	var d := data.duplicate(true)
	d.formations.items[fo].points.remove_at(sel_wp)
	_renumber(d.formations.items[fo].points)
	sel_wp = -1
	_edit(d)


static func _renumber(pts: Array) -> void:
	for i in pts.size():
		pts[i][0] = i + 1


## The selected units (the list's selection) follow the drawn route.
func apply_route() -> void:
	var ids := PackedInt64Array()
	for i in _ui.units.get_selected_items():
		ids.append(int(_ui.units.get_item_metadata(i)))
	if ids.is_empty() or route_pts.size() < 2:
		return
	var pts := PackedVector3Array()
	for p in _routed(route_pts):
		pts.append(Vector3(p.x, p.y, 0.0))  # z 0: on the terrain
	mode = ""
	route_pts.clear()
	route_line.clear()
	route_ghost.clear()
	_edit(api.set_route(data, ids, pts, _ui.route_speed.value, _ui.route_hover.button_pressed))


## Whether the route being drawn follows the roads: Follow roads on, road data there, and no flyer or ship among
## the units selected in the list.
func on_roads() -> bool:
	if not has_roads or not _ui.route_roads.button_pressed:
		return false
	for i in _ui.units.get_selected_items():
		var c := _class_of(entity(int(_ui.units.get_item_metadata(i))))
		if c in AIR_CLASSES or c in SHIP_CLASSES:
			return false
	return true


## The clicked points (world) as the line the units drive: along the roads (IafMissionEdit.road_route) or straight.
func _routed(clicks: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in clicks:
		pts.append(Vector2(p.x, p.y))
	return api.road_route(pts) if on_roads() and pts.size() > 1 else pts


## The route line, again after a click or a change of Follow roads.
func _update_route_line() -> void:
	route_line = _routed(route_pts)
	_update_ghost()


## The line on to the mouse: straight at once, along the roads once the mouse rests (a road route takes 20–150 ms).
func _update_ghost() -> void:
	route_ghost.clear()
	if mode == "route" and not route_line.is_empty() and mouse_world != null:
		route_ghost = PackedVector2Array([route_line[-1], Vector2(mouse_world.x, mouse_world.y)])
		if on_roads():
			_ghost_timer.start()
	host.preview.queue_redraw()


func _road_ghost() -> void:
	if mode == "route" and not route_pts.is_empty() and mouse_world != null:
		route_ghost = _routed([route_pts[-1], mouse_world])
		host.preview.queue_redraw()


func clear_route() -> void:
	if sel_id >= 0:
		_edit(api.clear_route(data, sel_id))


## Flight `n` (Alpha..Delta) from the Flights tab's row: its type and jets, starting at its leader's place (or the
## view's centre).
func apply_flight(n: int) -> void:
	var row: Dictionary = _ui.flight_rows[n - 1]
	if row.type.selected < 0:
		return
	var spec := {"type": row.type.get_selected_metadata(), "count": int(row.count.value)}
	var stem = row.start.get_selected_metadata() if row.start.selected >= 0 else ""
	if stem != "":
		# On the base's runway, its route taking off to 20 km ahead (as New).
		for b in api.year_bases(year, 1):
			if b.stem == stem:
				_add_base(stem, 1)
				var st: Array = b.start
				var ahead := Vector2(st[0], st[1]) + Vector2.from_angle(deg_to_rad(90.0 - st[3])) * 20000.0
				spec.merge({"slot_x": st[0], "slot_y": st[1], "alt": st[2], "heading": st[3]})
				spec["points"] = [[ahead.x, ahead.y, 3000.0, 150.0, 2]]
				_edit(api.set_flight(data, n, spec))
				return
	var lead := {}
	if tsd.flights.has(n):
		lead = entity(int(String(tsd.units[tsd.flights[n].leader].key).split(":")[1]))
	if lead.is_empty():
		var w := Tsd.map_to_world(tsd.scroll + tsd._view_size() / 2)
		spec.merge({"slot_x": roundf(w.x), "slot_y": roundf(w.y), "alt": 3000.0, "heading": 0.0})
	else:
		spec.merge({"slot_x": lead["0x2e4"], "slot_y": lead["0x2ee"], "alt": lead["0x2f8"], "heading": lead["0x302"]})
	_edit(api.set_flight(data, n, spec))


func remove_flight(n: int) -> void:
	_edit(api.remove_flight(data, n))


func set_misc(key: String, value) -> void:
	if data.is_empty() or data.misc.items[0].get(key) == value:
		return
	var d := data.duplicate(true)
	d.misc.items[0][key] = value
	_edit(d)


# --- map signals ----------------------------------------------------------------------------------------------------


func _key_id(key: String) -> int:
	return int(key.split(":")[1]) if key.begins_with("0:") else -1


func _on_unit_dragged(i: int) -> void:
	var u: Dictionary = tsd.units[i]
	sel_id = _key_id(u.key)
	if not Input.is_key_pressed(KEY_SHIFT):
		_ui.units.deselect_all()  # a click on the map selects that unit alone; Shift adds it to the list's selection
	var e := entity(sel_id)
	var w := Tsd.map_to_world(u.pos)
	if not e.is_empty() and Vector2(float(e["0x2e4"]), float(e["0x2ee"])).distance_to(w) > 1.0:
		move_entity(sel_id, w.x, w.y)
	else:
		_refresh()


func _on_waypoint_dragged(n: int, i: int) -> void:
	sel_wp = i
	var w := Tsd.map_to_world(tsd.flights[n].points[i])
	set_waypoint(n, i, w.x, w.y)


func _on_map_clicked(at: Vector2) -> void:
	var w := Tsd.map_to_world(at)
	match mode:
		"add":
			_ui.units.deselect_all()
			add_unit(add_object, w.x, w.y, _ui.add_side.selected + 1, _ui.add_role.selected)
		"route":
			route_pts.append(Vector3(roundf(w.x), roundf(w.y), 0.0))  # z 0: on the terrain
			_update_route_line()
		"paste":
			paste_at(w.x, w.y)
		_:
			sel_id = -1
			sel_wp = -1
			_ui.units.deselect_all()
			sel_building = pick_building(w.x, w.y)
			_refresh()
			if sel_building.is_empty():
				host.panning = true  # a drag from empty map pans it
			else:
				_offer_building()


# --- the scenery's buildings (docs/scenery.md §5) ------------------------------------------------------------------


## The building under world (x, y) when the buildings show, {} for none.
func pick_building(x: float, y: float) -> Dictionary:
	if not has_scenery or tsd == null or tsd.zoom < BUILDINGS_ZOOM:
		return {}
	var r: float = PICK_PX / (_map_per_metre() * tsd.zoom)
	var b := api.scenery_at(x, y, r)
	if not b.is_empty():
		b.at = Vector2(x, y)
		b.r = r
	return b


static func _map_per_metre() -> float:
	return Tsd.MAP_SIZE.x * Tsd.MAP_X_FACTOR / Tsd.WORLD_W


## The picked building's menu at the mouse: what it is, and Set as target (a building is never removed).
func _offer_building() -> void:
	var m: PopupMenu = _ui.building_menu
	m.set_item_text(0, "Building, %d m high, %d m²" % [roundi(sel_building.height), roundi(sel_building.area)])
	m.set_item_disabled(1, read_only)
	m.reset_size()
	m.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _on_building_menu(i: int) -> void:
	if i == 1 and not sel_building.is_empty():
		set_scenery_target(sel_building.at.x, sel_building.at.y, sel_building.r)


## Makes the building nearest world (x, y) a target: a marker entity on it (IafMissionEdit.scenery_target); returns
## its id, -1 when no building is there or the mission is read-only.
func set_scenery_target(x: float, y: float, r := 5.0) -> int:
	if read_only:
		return -1
	var template: Dictionary = templates.get(SCENERY_MARKER, {})
	var out := api.scenery_target(data, template, x, y, r)
	if int(out.id) < 0:
		return -1
	sel_building = {}
	sel_id = int(out.id)
	if out.mission == data:
		_refresh()  # already a target: its marker selected
	else:
		_edit(out.mission)
	return sel_id


## The selected unit's "Move to clear ground" place (its check issue's move_to), [] for none.
func clear_ground_of(id: int) -> Array:
	for it in issues:
		if int(it.id) == id and it.has("move_to"):
			return it.move_to
	return []


func move_to_clear() -> void:
	var p := clear_ground_of(sel_id)
	if not p.is_empty():
		move_entity(sel_id, float(p[0]), float(p[1]))


## The TSD's hook under the unit icons: every building in view as an outline, the picked one yellow.
func _draw_buildings(canvas: Control, s: float) -> void:
	if not has_scenery or tsd.zoom < BUILDINGS_ZOOM:
		return
	# World (X east, Y north) → overlay pixels: tsd.world_to_map, then (map - scroll) · zoom · s.
	var a := _map_per_metre()
	var b := Tsd.MAP_SIZE.y / Tsd.WORLD_H
	var k: float = tsd.zoom * s
	var o: Vector2 = Vector2(Tsd.WORLD_X_SHIFT * a, Tsd.MAP_SIZE.y - Tsd.WORLD_Y_SHIFT * b) - tsd.scroll
	var xf := Transform2D(Vector2(a * k, 0.0), Vector2(0.0, -b * k), o * k)
	var key := [tsd.zoom, tsd.scroll, s, tsd.area.size]
	if key != _outlines_key:
		_outlines_key = key
		var p0: Vector2 = Tsd.map_to_world(tsd.scroll)
		var p1: Vector2 = Tsd.map_to_world(tsd.scroll + tsd._view_size())
		_outlines = api.scenery_outlines(p0.x - 100.0, p1.y - 100.0, p1.x + 100.0, p0.y + 100.0, xf)
	if _outlines.size() > 1:
		canvas.draw_multiline(_outlines, BUILDING_COLOR, 1.0)
	if not sel_building.is_empty():
		var pts: PackedVector2Array = xf * sel_building.points
		pts.append(pts[0])
		canvas.draw_polyline(pts, Tsd.LABEL_COLOR, 2.0)


# --- checks and Fly -------------------------------------------------------------------------------------------------


func errors() -> int:
	return issues.filter(func(i): return i.level == "error").size()


func fly_flight() -> int:
	var i: int = _ui.fly_as.selected
	return i + 1 if i >= 0 and not _ui.fly_as.is_item_disabled(i) else 0


func fly(anyway := false) -> void:
	if read_only or errors() > 0 or fly_flight() == 0:
		return
	if not anyway and not issues.is_empty():
		_ui.fly_anyway.popup_centered()
		return
	save()
	Settings.fly_edited(source, _fly_files(), briefing.duplicate(true), fly_flight(), file, year)


# --- UI -------------------------------------------------------------------------------------------------------------


func _refresh() -> void:
	if tsd != null:
		var keep_sel := sel_id
		tsd.edit = not (intel_preview or roll_preview)
		tsd.reload(_map_files())
		tsd.selected = -1
		for i in tsd.units.size():
			if tsd.units[i].key == "0:%d" % keep_sel:
				tsd.selected = i
	issues = api.check(data) + api.year_issues(data, year, what_if) if not data.is_empty() else []
	issues += api.random_issues(data, random) if not data.is_empty() else []
	issues += _more_issues()
	conditions = api.conditions(data) if not data.is_empty() else {}
	if tsd != null:
		tsd.issues = {}
		for it in issues:
			var key := "0:%d" % int(it.id)
			if tsd.issues.get(key, "") != "error":
				tsd.issues[key] = it.level
	_refresh_ui()


func _refresh_ui() -> void:
	if _ui.is_empty():
		return
	var title := mission_name if mission_name != "" else "No mission"
	_ui.title.text = title + (" (original, read-only: Fork to edit)" if read_only and source >= 0 else "")
	_ui.title.tooltip_text = _ui.title.text
	_ui.fork.disabled = source < 0
	_ui.start.visible = source < 0
	_ui.zoom_in.get_parent().visible = tsd != null
	_ui.zoom_in.disabled = tsd == null or not tsd.can_zoom_in()
	_ui.zoom_out.disabled = tsd == null or not tsd.can_zoom_out()
	_ui.save.disabled = read_only
	_ui.save_as.disabled = read_only
	_ui.delete.disabled = read_only or file == ""
	_ui.undo.disabled = read_only or undo.is_empty()
	# Fly as: the flights the TSD lets you fly (tsd.gd flight_enabled).
	var fa: OptionButton = _ui.fly_as
	var keep := fa.selected
	for n in 4:
		fa.set_item_disabled(n, tsd == null or not tsd.flight_enabled(n + 1))
	if keep < 0 or fa.is_item_disabled(keep):
		keep = -1
		for n in 4:
			if not fa.is_item_disabled(n):
				keep = n
				break
	fa.select(keep)
	var list: ItemList = _ui.issues
	list.clear()
	# Errors first, then warnings; the same finding on several units is one line with their count (a click selects
	# the first of them).
	for level in ["error", "warning"]:
		var seen := {}
		for it in issues:
			if it.level != level:
				continue
			if seen.has(it.text):
				seen[it.text][1] += 1
				continue
			seen[it.text] = [list.item_count, 1]
			# The unit's name in front when the text does not already name it ("Boat_1: route point 1: …").
			var who := String(entity(int(it.id)).get("0x2bc", "")) if int(it.id) >= 0 else ""
			var line: String = it.text if who == "" or String(it.text).begins_with(who) else "%s: %s" % [who, it.text]
			list.add_item("%s: %s" % [level.capitalize(), line])
			list.set_item_metadata(list.item_count - 1, int(it.id))
			list.set_item_custom_fg_color(list.item_count - 1, Color.RED if level == "error" else Color.YELLOW)
		for t in seen:
			if seen[t][1] > 1:
				list.set_item_text(seen[t][0], "%s: %s (%d units)" % [level.capitalize(), t, seen[t][1]])
	# The list shows only when there is something in it, as tall as its lines up to four (then it scrolls).
	list.visible = not issues.is_empty()
	list.custom_minimum_size.y = mini(list.item_count, 4) * 30 + 6
	_ui.issues_head.text = (
		"No errors or warnings"
		if issues.is_empty()
		else "%d errors, %d warnings" % [errors(), issues.size() - errors()]
	)
	_ui.fly.disabled = read_only or errors() > 0 or fly_flight() == 0
	_fill_units()
	_fill_props()
	_fill_flight_types()
	_fill_flights()
	_fill_mission()
	_fill_conditions()
	_fill_intel()
	_fill_clipboard()
	_ui.scenario.refresh()
	_show_hint()
	host.preview.queue_redraw()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_ui.new = _button(bar, "New", func(): _ask_name("new", api.free_name("My mission", _taken())))
	_ui.open = _button(bar, "Open", _show_open)
	_ui.fork = _button(bar, "Fork", func(): _ask_name("fork", suggest_name()))
	_ui.duplicate = _button(bar, "Duplicate", func(): _ask_name("duplicate", suggest_name()))
	_ui.save = _button(bar, "Save", save)
	_ui.save_as = _button(bar, "Save as", func(): _ask_name("save_as", mission_name))
	_ui.undo = _button(bar, "Undo", undo_last)
	_ui.delete = _button(bar, "Delete", func(): _ui.delete_dlg.popup_centered())
	_ui.title = Label.new()
	_ui.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A long title clips (its full text is the tooltip) so it never pushes Fly off the bar.
	_ui.title.clip_text = true
	_ui.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ui.title.custom_minimum_size.x = 80
	_ui.title.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(_ui.title)
	bar.add_child(_label("Fly as"))
	_ui.fly_as = OptionButton.new()
	for n in Tsd.FLIGHT_LABELS.slice(1, 5):
		_ui.fly_as.add_item(n)
	_ui.fly_as.item_selected.connect(func(_i): _refresh_ui())
	bar.add_child(_ui.fly_as)
	_ui.fly = _button(bar, "Fly", fly)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	# Bottom: what passes and fails the mission, then its errors and warnings (a click selects the unit).
	_ui.cond_line = _label("")
	_ui.cond_line.clip_text = true
	_ui.cond_line.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_ui.cond_line)
	_ui.issues_head = _label("")
	root.add_child(_ui.issues_head)
	_ui.issues = ItemList.new()
	_ui.issues.custom_minimum_size.y = 36
	_ui.issues.size_flags_vertical = Control.SIZE_SHRINK_END
	_ui.issues.item_clicked.connect(func(i, _at, _button): _on_issue_pressed(i))
	root.add_child(_ui.issues)
	host = MapHost.new()
	host.editor = self
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_stretch_ratio = 3.0
	split.add_child(host)
	# Nothing open: the start choices stand where the map goes.
	_ui.start = CenterContainer.new()
	_ui.start.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(_ui.start)
	var choices := VBoxContainer.new()
	_ui.start.add_child(choices)
	_button(choices, "New mission", func(): _ask_name("new", api.free_name("My mission", _taken())))
	_button(choices, "Open a mission (yours, or an original to fork)", _show_open)
	# Zoom, top right of the map (the mouse wheel zooms too).
	var zoom := HBoxContainer.new()
	zoom.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	zoom.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	host.add_child(zoom)
	_ui.zoom_in = _button(zoom, " + ", func(): _zoom(Tsd.ZOOM_STEP))
	_ui.zoom_out = _button(zoom, " − ", func(): _zoom(1.0 / Tsd.ZOOM_STEP))
	# The status line along the map's foot: what the mouse does where it is (hint_text).
	_ui.hint = Label.new()
	_ui.hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_ui.hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.hint.clip_text = true
	_ui.hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var hint_bg := StyleBoxFlat.new()
	hint_bg.bg_color = Color(0, 0, 0, 0.75)
	hint_bg.set_content_margin_all(4)
	hint_bg.content_margin_left = 8
	_ui.hint.add_theme_stylebox_override("normal", hint_bg)
	host.add_child(_ui.hint)
	var tabs := TabContainer.new()
	# A fixed side panel: the map keeps its size whichever tab is open.
	tabs.custom_minimum_size.x = 560
	tabs.size_flags_horizontal = Control.SIZE_FILL
	# The dialogs' grey: on the default near-black panel the unchecked boxes do not show.
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.25, 0.25, 0.27)
	panel.set_content_margin_all(8)
	tabs.add_theme_stylebox_override("panel", panel)
	split.add_child(tabs)
	_build_units_tab(_tab(tabs, "Units"))
	_build_flights_tab(_tab(tabs, "Flights"))
	_build_mission_tab(_tab(tabs, "Mission"))
	_build_intel_tab(_tab(tabs, "Intel"))
	_ui.scenario = ScenarioEditor.new(self)
	tabs.add_child(_ui.scenario)
	_build_dialogs()
	_wrap_texts(tabs)


## Every label and check box standing on a line of its own in the side panel wraps at its width, so no text widens the
## panel (labels inside a row or a block palette keep their line).
func _wrap_texts(node: Node) -> void:
	for c in node.find_children("*", "Label", true, false) + node.find_children("*", "CheckBox", true, false):
		if c.get_parent() is VBoxContainer:
			c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _tab(tabs: TabContainer, name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	# Never wider than the panel: content that would widen it (and move the map) wraps instead (_wrap_texts).
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	return box


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _row(parent: Control, text: String, c: Control) -> Control:
	var h := HBoxContainer.new()
	var l := _label(text)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	parent.add_child(h)
	return c


func _spin(lo: float, hi: float, step: float, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value_changed.connect(cb)
	return s


func _options(items: Array, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.item_selected.connect(cb)
	return o


func _build_units_tab(box: VBoxContainer) -> void:
	_ui.units = ItemList.new()
	_ui.units.select_mode = ItemList.SELECT_MULTI
	_ui.units.custom_minimum_size.y = 170
	_ui.units.multi_selected.connect(func(_i, _s): _on_unit_listed())
	_ui.units.gui_input.connect(_on_units_hover)
	_ui.units.mouse_exited.connect(func(): _on_units_hover(null))
	box.add_child(_ui.units)
	# Adding comes first, right under the list: the most used action stays in view without scrolling.
	box.add_child(_label("Add a unit"))
	_ui.add_class = _row(box, "Kind", _options(ADD_CLASSES.map(func(c): return c[0]), func(_i): _fill_object_picker()))
	_ui.add_obj = _row(box, "Object", _options([], func(_i): add_object = _ui.add_obj.get_selected_metadata()))
	# Side and role on one line, Place under them.
	var line := HBoxContainer.new()
	box.add_child(line)
	var side_l := _label("Side")
	side_l.custom_minimum_size.x = 110
	line.add_child(side_l)
	_ui.add_side = _options(SIDES, func(_i): _show_hint())
	_ui.add_side.select(1)
	_ui.add_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_ui.add_side)
	line.add_child(_label("Role"))
	_ui.add_role = _options(ROLES, func(_i): _show_hint())
	_ui.add_role.select(1)
	_ui.add_role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_ui.add_role)
	_ui.add_mode = _button(box, "Place on the map", func(): _set_mode("add"))
	_ui.add_mode.tooltip_text = "Then click the map where it goes (each click places one); Esc stops"
	_ui.add_mode.toggle_mode = true
	_ui.add_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(HSeparator.new())
	_ui.sel_head = _label("")
	box.add_child(_ui.sel_head)
	_ui.p_name = _row(box, "Name", LineEdit.new())
	_ui.p_name.text_submitted.connect(func(t): set_field("0x2bc", t))
	_ui.p_side = _row(box, "Side", _options(SIDES, func(i): set_field("0x2d0", i + 1)))
	_ui.p_role = _row(box, "Role", _options(ROLES, func(i): set_field("0x32a", i)))
	_ui.p_heading = _row(box, "Heading °", _spin(0, 359, 1, func(v): set_field("0x302", v)))
	_ui.p_alt = _row(box, "Altitude m", _spin(-1000, 20000, 1, func(v): set_field("0x2f8", v)))
	_ui.p_where = _row(box, "Position", _label(""))
	_ui.p_clear = _button(box, "Move to clear ground", move_to_clear)
	_ui.p_delete = _button(box, "Delete unit", delete_selected)
	_build_roles(box)
	box.add_child(HSeparator.new())
	box.add_child(_label("Give a route to the units selected in the list"))
	_ui.route_speed = _row(box, "Speed km/h", _spin(1, 2000, 1, func(_v): pass))
	_ui.route_speed.value = 40
	_ui.route_hover = _row(box, "At the end", CheckBox.new())
	_ui.route_hover.text = "Stop and hold at the last point"
	_ui.route_roads = _row(box, "Roads", CheckBox.new())
	_ui.route_roads.text = "Follow roads" if has_roads else "Follow roads: no road data (run setup again)"
	_ui.route_roads.tooltip_text = (
		"Ground vehicles drive along the roads between the points. A point within 1 km of a road moves onto it;"
		+ " a farther point is joined by straight lines. Flyers and ships go straight."
	)
	_ui.route_roads.button_pressed = has_roads
	_ui.route_roads.disabled = not has_roads
	_ui.route_roads.toggled.connect(func(_on): _update_route_line())
	_ui.route_mode = _button(box, "Draw the route (click points)", func(): _set_mode("route"))
	_ui.route_mode.toggle_mode = true
	_button(box, "Give the route", apply_route)
	_button(box, "Clear the selected unit's route", clear_route)
	_build_clipboard(box)
	_build_random(box)


func _build_flights_tab(box: VBoxContainer) -> void:
	# Above the jet lists it widens: the never-served types (the Lavi).
	_ui.m_what_if = CheckBox.new()
	_ui.m_what_if.text = "What-if (hypothetical) aircraft"
	_ui.m_what_if.toggled.connect(func(_on): _on_year_picked())
	box.add_child(_ui.m_what_if)
	_ui.flight_rows = []
	for n in 4:
		var h := HBoxContainer.new()
		var l := _label(Tsd.FLIGHT_LABELS[n + 1])
		l.custom_minimum_size.x = 70
		h.add_child(l)
		var t := OptionButton.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		h.add_child(_label("jets"))
		var c := _spin(1, 2, 1, func(_v): pass)
		h.add_child(c)
		var k := n + 1
		box.add_child(h)
		# Its second line: where it starts, then Add / Set and Remove.
		var h2 := HBoxContainer.new()
		var pad := _label("from")
		pad.custom_minimum_size.x = 70
		pad.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h2.add_child(pad)
		var st := OptionButton.new()
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.fit_to_longest_item = false
		st.tooltip_text = "Where the flight starts: on a base's runway (blue's bases in the mission's year), or in the air"
		h2.add_child(st)
		var add := _button(h2, "Add", func(): apply_flight(k))
		var rm := _button(h2, "Remove", func(): remove_flight(k))
		box.add_child(h2)
		_ui.flight_rows.append({"type": t, "count": c, "start": st, "set": add, "remove": rm})
	box.add_child(HSeparator.new())
	box.add_child(_label("Route of the flight (click its unit or pick it here)"))
	_ui.route_of = _row(box, "Flight", _options([], _on_route_flight))
	# Shown only for an enemy (non Alpha … Delta) flight picked above.
	_ui.red_remove = _button(box, "Remove this enemy flight and its jets", remove_enemy_flight)
	_ui.wait_rule = CheckBox.new()
	_ui.wait_rule.text = "Waits parked at its base until a rule makes it take off"
	_ui.wait_rule.tooltip_text = 'Scenario tab: add a rule with the THEN block "Flight takes off"'
	_ui.wait_rule.toggled.connect(set_waits)
	box.add_child(_ui.wait_rule)
	_ui.wps = ItemList.new()
	_ui.wps.custom_minimum_size.y = 200
	_ui.wps.item_selected.connect(_on_waypoint_listed)
	box.add_child(_ui.wps)
	_ui.wp_alt = _row(box, "Altitude m", _spin(0, 20000, 10, func(v): set_waypoint_value(3, v)))
	# The waypoint's 5th field is its planned arrival time, seconds after the start (docs/ai.md §7.2), 0 none.
	_ui.wp_speed = _row(box, "Arrive at (s)", _spin(0, 36000, 10, func(v): set_waypoint_value(4, v)))
	_button(box, "Insert a waypoint after", insert_waypoint)
	_button(box, "Delete the waypoint", delete_waypoint)
	box.add_child(HSeparator.new())
	box.add_child(_label("Add an enemy flight (red, from a base red holds in the mission's year)"))
	_ui.red_base = _row(box, "Base", OptionButton.new())
	_ui.red_jet = _row(box, "Jet", OptionButton.new())
	_ui.red_count = _row(box, "Jets", _spin(1, 2, 1, func(_v): pass))
	_ui.red_count.value = 2
	_ui.red_add = _button(box, "Add enemy flight", _on_add_enemy)


func _build_mission_tab(box: VBoxContainer) -> void:
	_build_conditions(box)
	_ui.m_name = _row(box, "Name", _label(""))
	_ui.m_year = _row(box, "Year", _year_picker(func(_v): _on_year_picked()))
	_ui.m_hour = _row(box, "Start hour", _spin(0, 23, 1, func(_v): _set_time()))
	_ui.m_min = _row(box, "Start minute", _spin(0, 59, 1, func(_v): _set_time()))
	_ui.m_wind = _row(
		box, "Wind", _options(WIND_KT.map(func(w): return w[0]), func(i): set_misc("0x46a", WIND_KT[i][1]))
	)
	_ui.m_from = _row(box, "From", _options(WIND_FROM, func(i): set_misc("0x474", i * 45)))
	_ui.m_weather = _row(
		box, "Weather", _options(WEATHER.map(func(w): return w[0]), func(i): set_misc("weather", WEATHER[i][1]))
	)
	box.add_child(_label("Briefing (English)"))
	_ui.brief_en = TextEdit.new()
	_ui.brief_en.custom_minimum_size.y = 220
	_ui.brief_en.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_ui.brief_en.text_changed.connect(func(): briefing.en = _ui.brief_en.text)
	box.add_child(_ui.brief_en)
	box.add_child(_label("Briefing (Hebrew)"))
	_ui.brief_he = TextEdit.new()
	_ui.brief_he.custom_minimum_size.y = 220
	_ui.brief_he.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_ui.brief_he.text_direction = Control.TEXT_DIRECTION_RTL
	_ui.brief_he.text_changed.connect(func(): briefing.he = _ui.brief_he.text)
	box.add_child(_ui.brief_he)


func _build_dialogs() -> void:
	_ui.building_menu = PopupMenu.new()
	_ui.building_menu.add_item("Building", 0)
	_ui.building_menu.set_item_disabled(0, true)
	_ui.building_menu.add_item("Set as target", 1)
	_ui.building_menu.id_pressed.connect(_on_building_menu)
	add_child(_ui.building_menu)
	_ui.open_dlg = ConfirmationDialog.new()
	_ui.open_dlg.title = "Open a mission"
	_ui.open_dlg.ok_button_text = "Open"
	# A search box over the list (66 originals): typing narrows it by number or title.
	var ov := VBoxContainer.new()
	_ui.open_filter = LineEdit.new()
	_ui.open_filter.placeholder_text = "Search by number or title"
	_ui.open_filter.text_changed.connect(func(_t): _fill_open())
	ov.add_child(_ui.open_filter)
	_ui.open_list = ItemList.new()
	_ui.open_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui.open_list.item_activated.connect(func(_i): _ui.open_dlg.hide.call_deferred())
	_ui.open_list.item_activated.connect(func(_i): _open_picked())
	ov.add_child(_ui.open_list)
	_ui.open_dlg.add_child(ov)
	_ui.open_dlg.confirmed.connect(_open_picked)
	add_child(_ui.open_dlg)
	_ui.name_dlg = ConfirmationDialog.new()
	var v := VBoxContainer.new()
	# New's choices: the year, then that year's blue home bases and jets, the wingman and the what-if switch.
	_ui.era_row = GridContainer.new()
	_ui.era_row.columns = 2
	_ui.new_year = _year_picker(func(_v): _fill_new_choices())
	_ui.new_base = OptionButton.new()
	_ui.new_jet = OptionButton.new()
	_ui.wingman = CheckBox.new()
	_ui.wingman.text = "Wingman"
	_ui.wingman.button_pressed = true
	_ui.new_what_if = CheckBox.new()
	_ui.new_what_if.text = "What-if (hypothetical) aircraft"
	_ui.new_what_if.toggled.connect(func(_on): _fill_new_choices())
	var rows := [["Year", _ui.new_year], ["Home base", _ui.new_base], ["", _ui.new_what_if], ["Jet", _ui.new_jet]]
	for row in rows + [["", _ui.wingman]]:
		_ui.era_row.add_child(_label(row[0]))
		_ui.era_row.add_child(row[1])
	# The name first (English letters, digits, spaces, _ and -: it is also the file's name), then New's choices.
	v.add_child(_label("Name (English letters, digits, spaces, _ or -)"))
	_ui.name_edit = LineEdit.new()
	_ui.name_edit.custom_minimum_size.x = 360
	_ui.name_edit.text_changed.connect(func(t): _set_why(name_error(t)))
	v.add_child(_ui.name_edit)
	_ui.name_why = _label("")
	_ui.name_why.modulate = Color.RED
	_ui.name_why.visible = false
	v.add_child(_ui.name_why)
	v.add_child(_ui.era_row)
	_ui.name_dlg.add_child(v)
	_ui.name_dlg.confirmed.connect(_name_confirmed)
	add_child(_ui.name_dlg)
	_ui.delete_dlg = ConfirmationDialog.new()
	_ui.delete_dlg.ok_button_text = "Delete"
	_ui.delete_dlg.about_to_popup.connect(
		func(): _ui.delete_dlg.dialog_text = "Delete your mission %s? This cannot be undone." % mission_name
	)
	_ui.delete_dlg.confirmed.connect(delete_mission)
	add_child(_ui.delete_dlg)
	_ui.replace_dlg = ConfirmationDialog.new()
	_ui.replace_dlg.ok_button_text = "Replace"
	_ui.replace_dlg.confirmed.connect(_name_done)
	add_child(_ui.replace_dlg)
	_ui.fly_anyway = ConfirmationDialog.new()
	_ui.fly_anyway.dialog_text = "The mission has warnings. Fly anyway?"
	_ui.fly_anyway.ok_button_text = "Fly anyway"
	_ui.fly_anyway.confirmed.connect(func(): fly(true))
	add_child(_ui.fly_anyway)


func _show_open() -> void:
	_ui.open_filter.text = ""
	_fill_open()
	# Sized to the window, so its buttons stay on screen in a small one.
	var vp := get_viewport_rect().size
	_ui.open_list.custom_minimum_size = Vector2(minf(520, vp.x * 0.8), minf(520, vp.y * 0.55))
	_ui.open_dlg.popup_centered_clamped(Vector2.ZERO, 0.9)
	_ui.open_filter.grab_focus()


## The Open list: your missions, then the originals, those matching the search box.
func _fill_open() -> void:
	var l: ItemList = _ui.open_list
	var q: String = _ui.open_filter.text.strip_edges().to_lower()
	l.clear()
	for section in ["My missions", "Original missions (read-only)"]:
		l.add_item(section)
		l.set_item_disabled(l.item_count - 1, true)
		if section == "My missions":
			for m in own_missions():
				if q == "" or String(m.name).to_lower().contains(q):
					l.add_item("    " + m.name)
					l.set_item_metadata(l.item_count - 1, m.path)
		else:
			var ids := originals.keys()
			ids.sort()
			for id in ids:
				var row := "%d  %s" % [id, originals[id].title]
				if q == "" or row.to_lower().contains(q):
					l.add_item("    " + row)
					l.set_item_metadata(l.item_count - 1, id)


func _open_picked() -> void:
	var sel: PackedInt32Array = _ui.open_list.get_selected_items()
	if sel.is_empty():
		return
	var meta = _ui.open_list.get_item_metadata(sel[0])
	if meta is String:
		open_file(meta)
	elif meta != null:
		open_original(int(meta))


func _ask_name(purpose: String, suggestion: String) -> void:
	_name_purpose = purpose
	_ui.name_dlg.title = (
		{"fork": "Fork: the new mission's name", "new": "New mission", "duplicate": "Duplicate: the copy's name"}
		. get(purpose, "Save as")
	)
	_ui.era_row.visible = purpose == "new"
	if purpose == "new":
		_fill_new_choices()
	_ui.name_edit.text = suggestion
	_set_why(name_error(suggestion))
	_ui.name_dlg.popup_centered()


## A year box, 1966 … 1998 (1998 the game's present; 1967 is the Six-Day War itself).
func _year_picker(cb: Callable) -> SpinBox:
	var y := _spin(1966, 1998, 1, cb)
	y.value = 1998
	y.tooltip_text = "1967 is the Six-Day War itself, from the pre-war lines."
	return y


## The bdb's name of each id in `ids` into picker `o` (metadata: the id).
func _fill_jets(o: OptionButton, ids: PackedInt64Array) -> void:
	o.clear()
	if objects.is_empty():
		objects = Tsd.MissionRuntime.bdb_objects(Tsd.MissionRuntime.load_bdb({"bdb": "default6_1.bdb"}))
	var bdb := objects
	for id in ids:
		o.add_item(String(bdb.get(id, {}).get("0x528", str(id))))
		o.set_item_metadata(o.item_count - 1, id)


## New's year's blue home bases and jets into its pickers.
func _fill_new_choices() -> void:
	var y: float = _ui.new_year.value
	_ui.new_base.clear()
	for b in api.year_bases(y, 1):
		_ui.new_base.add_item(b.name)
	_fill_jets(_ui.new_jet, api.year_jets(y, 1, _ui.new_what_if.button_pressed))


## The name's problem under the name box; the line shows only when there is one.
func _set_why(t: String) -> void:
	_ui.name_why.text = t
	_ui.name_why.visible = t != ""


func _name_confirmed() -> void:
	var n: String = _ui.name_edit.text.strip_edges()
	var why := name_error(n)
	if why != "":
		_set_why(why)
		_ui.name_dlg.popup_centered.call_deferred()
		return
	if own_clash(n):
		_ui.replace_dlg.dialog_text = "You have a mission called %s. Replace it?" % n
		_ui.replace_dlg.popup_centered()
		return
	_name_done()


func _name_done() -> void:
	var n: String = _ui.name_edit.text.strip_edges()
	if _name_purpose == "new":
		var y: float = _ui.new_year.value
		var jet: int = _ui.new_jet.get_selected_metadata()
		var base: String = _ui.new_base.get_item_text(_ui.new_base.selected)
		new_mission(n, y, base, jet, _ui.wingman.button_pressed, _ui.new_what_if.button_pressed)
	elif _name_purpose == "fork":
		fork(n)
	elif _name_purpose == "duplicate":
		duplicate_mission(n)
	else:
		save_as(n)


func _zoom(factor: float) -> void:
	if tsd != null:
		tsd.zoom_by(factor)
		tsd.queue_redraw()
		_refresh_ui()


func _on_issue_pressed(i: int) -> void:
	var id = _ui.issues.get_item_metadata(i)
	if id != null and int(id) >= 0:
		sel_id = int(id)
		_refresh()
		if tsd.selected >= 0:
			tsd.centre_on(tsd.units[tsd.selected].pos)


func _set_mode(m: String) -> void:
	mode = "" if mode == m else m
	route_pts.clear()
	route_line.clear()
	route_ghost.clear()
	place_check = []
	if mode == "add" and mouse_world != null:
		_check_place(mouse_world)
	_show_hint()
	_ui.add_mode.set_pressed_no_signal(mode == "add")
	_ui.add_mode.text = "Placing: click the map (Esc stops)" if mode == "add" else "Place on the map"
	_ui.paste.set_pressed_no_signal(mode == "paste")
	_ui.route_mode.set_pressed_no_signal(mode == "route")
	host.preview.queue_redraw()


func _set_time() -> void:
	set_misc("0x460", _ui.m_hour.value * 3600.0 + _ui.m_min.value * 60.0)


func _on_unit_listed() -> void:
	var sel: PackedInt32Array = _ui.units.get_selected_items()
	sel_id = int(_ui.units.get_item_metadata(sel[-1])) if not sel.is_empty() else -1
	var e := entity(sel_id)
	if tsd != null:
		tsd.selected = -1
		for i in tsd.units.size():
			if tsd.units[i].key == "0:%d" % sel_id:
				tsd.selected = i
				if tsd.flights.has(tsd.units[i].flight):
					tsd.sel_flight = tsd.units[i].flight
				tsd.centre_on(tsd.units[i].pos)
	if not e.is_empty():
		_fill_props()
		_fill_flights()


func _on_waypoint_listed(i: int) -> void:
	sel_wp = i
	_fill_flights()


func _on_route_flight(i: int) -> void:
	tsd.sel_flight = _ui.route_of.get_item_metadata(i)
	sel_wp = -1
	_fill_flights()


func _fill_units() -> void:
	var l: ItemList = _ui.units
	var picked := {}
	var current := -1
	for i in l.get_selected_items():
		picked[l.get_item_metadata(i)] = true
	l.clear()
	for e in data.get("entities", {}).get("items", []):
		if int(e.get("0x14", 0)) != 0:
			continue
		var id := int(e.get("0x1e", -1))
		var obj: Dictionary = objects.get(int(e.get("0x2c6", -1)), {})
		var side: int = clampi(int(e.get("0x2d0", 1)), 1, 3)
		var role := clampi(int(e.get("0x32a", 2)), 0, 2)
		var tag: String = "" if role == 2 else "  [%s]" % ROLES[role]
		l.add_item("%d  %s  (%s, %s)%s" % [id, e.get("0x2bc", ""), _object_name(obj), SIDES[side - 1], tag])
		l.set_item_metadata(l.item_count - 1, id)
		l.set_item_custom_fg_color(l.item_count - 1, SIDE_COLORS[side - 1])
		if picked.has(id) or id == sel_id:
			l.select(l.item_count - 1, false)
		if id == sel_id:
			current = l.item_count - 1
	if current >= 0:
		l.ensure_current_is_visible.call_deferred()


func _fill_props() -> void:
	var e := entity(sel_id)
	var can := not e.is_empty() and not read_only
	for k in ["p_name", "p_heading", "p_alt"]:
		_ui[k].editable = can
	for k in ["p_side", "p_role"]:
		_ui[k].disabled = not can
	_ui.p_clear.visible = can and not clear_ground_of(sel_id).is_empty()
	# With nothing selected only the "Selected: nothing" line shows: no greyed values that look like a unit's.
	for k in ["p_name", "p_side", "p_role", "p_heading", "p_alt", "p_where"]:
		_ui[k].get_parent().visible = not e.is_empty()
	_ui.p_delete.visible = not e.is_empty()
	_ui.sel_head.text = (
		"Selected: nothing (click a unit on the map or in the list)"
		if e.is_empty()
		else "Selected: %s" % _describe_entity(e)
	)
	_ui.sel_head.add_theme_color_override(
		"font_color", Color.WHITE if e.is_empty() else SIDE_COLORS[clampi(int(e.get("0x2d0", 1)), 1, 3) - 1]
	)
	if e.is_empty():
		_ui.p_name.text = ""
		_ui.p_where.text = ""
		return
	_ui.p_name.text = String(e.get("0x2bc", ""))
	_ui.p_side.select(clampi(int(e.get("0x2d0", 1)), 1, 3) - 1)
	_ui.p_role.select(clampi(int(e.get("0x32a", 2)), 0, 2))
	_ui.p_heading.set_value_no_signal(fposmod(float(e.get("0x302", 0)), 360.0))
	_ui.p_alt.set_value_no_signal(float(e.get("0x2f8", 0)))
	var why := issues.filter(func(it): return int(it.id) == sel_id).map(func(it): return it.text)
	if e.has("scenery"):  # short lines: the row's label does not wrap
		why = (
			[
				"Scenery building, %d m high" % roundi(float(e.get("scenery_height", 0))),
				"%d m², %d buildings within 1 km" % [int(e.get("scenery_area", 0)), int(e.get("scenery_count", 0))],
			]
			+ why
		)
	_ui.p_where.text = (
		"X %d, Y %d m%s" % [int(e["0x2e4"]), int(e["0x2ee"]), "\n" + "\n".join(why) if not why.is_empty() else ""]
	)


func _fill_object_picker() -> void:
	var o: OptionButton = _ui.add_obj
	o.clear()
	var classes: Array = ADD_CLASSES[maxi(_ui.add_class.selected, 0)][1]
	# The game's display name first ("SA 6"), the object's own name after it ("sa6launcher") to tell a battery's parts
	# apart; objects without a display name (antennas, domes) last, by their own name. Sorted by what shows.
	var rows := []
	for id in objects:
		var obj: Dictionary = objects[id]
		if int(obj.get("0x5aa", -1)) in classes:
			var shown := String(obj.get("0x528", "")).strip_edges()
			var own := String(obj.get("0x514", str(id)))
			rows.append([shown == "", ("%s  (%s)" % [shown, own]) if shown != "" else own, int(id)])
	rows.sort()
	for r in rows:
		o.add_item(r[1])
		o.set_item_metadata(o.item_count - 1, r[2])
	add_object = o.get_item_metadata(0) if o.item_count > 0 else -1


## Alpha … Delta's jet lists: the blue jets in service in the mission's year (what-if adds the never-served).
func _fill_flight_types() -> void:
	var ids := api.year_jets(year, 1, what_if)
	var bases := api.year_bases(year, 1) if not data.is_empty() else []
	for row in _ui.flight_rows:
		_fill_jets(row.type, ids)
		var o: OptionButton = row.start
		var keep = o.get_selected_metadata() if o.selected >= 0 else ""
		o.clear()
		o.add_item("as placed (new: in the air)")
		o.set_item_metadata(0, "")
		for b in bases:
			o.add_item(String(b.name))
			o.set_item_metadata(o.item_count - 1, String(b.stem))
			if b.stem == keep:
				o.select(o.item_count - 1)


func _fill_flights() -> void:
	if tsd == null:
		return
	for n in 4:
		var row: Dictionary = _ui.flight_rows[n]
		if tsd.flights.has(n + 1):
			var lead: Dictionary = tsd.units[tsd.flights[n + 1].leader]
			var obj := int(entity(_key_id(lead.key)).get("0x2c6", -1))
			var found := false
			for i in row.type.item_count:
				if row.type.get_item_metadata(i) == obj:
					row.type.select(i)
					found = true
			if not found:
				# A type outside the year's list (a forked original's) stays shown, marked.
				row.type.add_item("%s (not in %d)" % [objects.get(obj, {}).get("0x528", str(obj)), int(year)])
				row.type.set_item_metadata(row.type.item_count - 1, obj)
				row.type.select(row.type.item_count - 1)
			row.count.set_value_no_signal(tsd.flights[n + 1].members.size())
		else:
			# No such flight yet: no jet shown, Add makes it.
			row.type.select(-1)
			row.count.set_value_no_signal(2)
		row.set.text = "Set" if tsd.flights.has(n + 1) else "Add"
		row.remove.disabled = read_only or not tsd.flights.has(n + 1)
		row.set.disabled = read_only
	var ro: OptionButton = _ui.route_of
	ro.clear()
	var keys: Array = tsd.flights.keys()
	keys.sort()
	for n in keys:
		var fo: int = tsd.flights[n].formation
		ro.add_item("%s (%s)" % [data.formations.items[fo].get("0x3e8", ""), "blue" if n <= 4 else "enemy"])
		ro.set_item_metadata(ro.item_count - 1, n)
		if n == tsd.sel_flight:
			ro.select(ro.item_count - 1)
	_ui.wps.clear()
	var fo := _formation_of(tsd.sel_flight)
	var pts: Array = data.formations.items[fo].points if fo >= 0 else []
	for i in pts.size():
		var at := "waits for a rule" if float(pts[i][4]) >= WAIT_T else "arrive at %d s" % int(pts[i][4])
		_ui.wps.add_item("%d: alt %d m, %s" % [i + 1, int(pts[i][3]), at])
	# Only a flight that takes off from a base (wp0 action 2) can wait on the ground.
	_ui.wait_rule.set_pressed_no_signal(not pts.is_empty() and float(pts[0][4]) >= WAIT_T)
	_ui.wait_rule.disabled = read_only or pts.is_empty() or pts[0].size() < 6 or int(pts[0][5]) != 2
	if sel_wp >= 0 and sel_wp < pts.size():
		_ui.wps.select(sel_wp)
		_ui.wp_alt.set_value_no_signal(float(pts[sel_wp][3]))
		_ui.wp_speed.set_value_no_signal(float(pts[sel_wp][4]))


func _on_year_picked() -> void:
	set_year(_ui.m_year.value, _ui.m_what_if.button_pressed)


func _on_add_enemy() -> void:
	if _ui.red_base.selected >= 0 and _ui.red_jet.selected >= 0:
		var stem: String = _ui.red_base.get_selected_metadata()
		add_enemy_flight(stem, _ui.red_jet.get_selected_metadata(), int(_ui.red_count.value))


## The Flights tab's enemy flight pickers: red's bases and jets in the mission's year.
func _fill_enemy() -> void:
	var keep: String = _ui.red_base.get_item_text(_ui.red_base.selected) if _ui.red_base.selected >= 0 else ""
	_ui.red_base.clear()
	for b in api.year_bases(year, 2):
		_ui.red_base.add_item(b.name)
		_ui.red_base.set_item_metadata(_ui.red_base.item_count - 1, b.stem)
		if b.name == keep:
			_ui.red_base.select(_ui.red_base.item_count - 1)
	var jet = _ui.red_jet.get_selected_metadata() if _ui.red_jet.selected >= 0 else -1
	_fill_jets(_ui.red_jet, api.year_jets(year, 2, what_if))
	for i in _ui.red_jet.item_count:
		if _ui.red_jet.get_item_metadata(i) == jet:
			_ui.red_jet.select(i)
	_ui.red_add.disabled = read_only or data.is_empty()


func _fill_mission() -> void:
	_ui.m_name.text = mission_name
	_ui.m_year.set_value_no_signal(year)
	_ui.m_what_if.set_pressed_no_signal(what_if)
	_ui.m_year.editable = not read_only
	_ui.m_what_if.disabled = read_only
	_fill_enemy()
	if data.is_empty():
		return
	var misc: Dictionary = data.misc.items[0]
	var t := int(float(misc.get("0x460", 0)))
	_ui.m_hour.set_value_no_signal(t / 3600 % 24)
	_ui.m_min.set_value_no_signal(t / 60 % 60)
	var kt := int(misc.get("0x46a", 0))
	var i := [0, 10, 15, 20].find(kt)
	_ui.m_wind.select(i if i >= 0 else 4)
	_ui.m_from.select(int(posmod(int(misc.get("0x474", 0)) + 22, 360) / 45))
	_ui.m_weather.select(maxi(0, WEATHER.map(func(w): return w[1]).find(misc.get("weather", ""))))
	if _ui.brief_en.text != briefing.en:
		_ui.brief_en.text = briefing.en
	if _ui.brief_he.text != briefing.he:
		_ui.brief_he.text = briefing.he
	for c in [_ui.m_hour, _ui.m_min]:
		c.editable = not read_only
	for c in [_ui.m_wind, _ui.m_from, _ui.m_weather]:
		c.disabled = read_only
	_ui.brief_en.editable = not read_only
	_ui.brief_he.editable = not read_only


## The TSD's host: what tsd.gd reads from the front end (art, fonts, the 640 × 480 mapping), here mapping the TSD's
## content window and scrollbars onto the whole control; the mouse wheel zooms. It also draws a route being drawn.
class MapHost:
	extends Control
	## The TSD client and its scrollbars in 640 × 480 space (tsd.gd CLIENT, BARS).
	const AREA := Rect2(146, 42, 472, 367)

	var editor: Control
	var tsd: Control
	var dir := Settings.assets_dir().path_join("converted/menu")
	var art_scale := 1.0
	var font: Font = Img.arial(400)
	var font_bold: Font = Img.arial(700)
	var tsd_checks := {}
	var briefings := {}
	var flight = null
	var preview := Control.new()
	var _textures := {}

	func _init() -> void:
		clip_contents = true
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.draw.connect(_draw_preview)
		add_child(preview)
		var f := dir.path_join("image_scale.txt")
		if FileAccess.file_exists(f):
			art_scale = float(FileAccess.get_file_as_string(f).strip_edges())

	## The scale keeps the TSD's art and icons at the size the original's frame would have here; the TSD's client
	## (tsd.area) then grows to the whole pane, so the map fills it at any window size (fit()).
	func _scale() -> float:
		return maxf(0.01, minf(size.x / AREA.size.x, size.y / AREA.size.y))

	func _origin() -> Vector2:
		return -Tsd.CLIENT.position * _scale()

	## The TSD's client: the whole pane, in its 640 × 480 units; the zoom and scroll kept inside the map.
	func fit() -> void:
		if tsd == null:
			return
		tsd.area = Rect2(Tsd.CLIENT.position, size / _scale())
		tsd.zoom = maxf(tsd.zoom, tsd.min_zoom())
		tsd._clamp_scroll()
		tsd.map_canvas.queue_redraw()

	## The marks follow the map as it pans and zooms (the TSD redraws its overlay every frame too).
	func _process(_delta: float) -> void:
		preview.queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			fit()
		elif what == NOTIFICATION_MOUSE_EXIT and editor != null:
			editor.hover_at(null)

	func _to_screen(p: Vector2) -> Vector2:
		return _origin() + p * _scale()

	func _to_menu(p: Vector2) -> Vector2:
		return (p - _origin()) / _scale()

	func _rect(r: Rect2) -> Rect2:
		return Rect2(_to_screen(r.position), r.size * _scale())

	func _art_size(t: Texture2D) -> Vector2:
		return Vector2(t.get_width(), t.get_height()) / art_scale

	func _tex(path: String) -> Texture2D:
		if not _textures.has(path):
			_textures[path] = Img.load_texture(dir.path_join("img").path_join(path), true)
		return _textures[path]

	func _he() -> bool:
		return false

	func tsd_fly_flight(n: int) -> void:
		editor._ui.fly_as.select(n - 1)
		editor._refresh_ui()

	func tsd_visit(_key: String) -> void:
		pass

	func tsd_briefing_closed() -> void:
		pass

	func briefing_image(_stem: String) -> Texture2D:
		return null

	## Mouse: the wheel zooms about the point under the cursor; a drag with the middle button, or with the left one on
	## empty map while no tool is on (Add, route, paste), pans the map.
	var panning := false

	func _gui_input(event: InputEvent) -> void:
		if tsd == null:
			return
		if event is InputEventMouseButton:
			var b: int = event.button_index
			if event.pressed and b in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var c: Vector2 = _to_menu(event.position) - tsd.area.position
				var at: Vector2 = tsd.scroll + c / tsd.zoom
				var f: float = tsd.ZOOM_STEP if b == MOUSE_BUTTON_WHEEL_UP else 1.0 / tsd.ZOOM_STEP
				tsd.zoom = clampf(tsd.zoom * f, tsd.min_zoom(), tsd.zoom_max)
				tsd.scroll = at - c / tsd.zoom
				tsd._clamp_scroll()
				tsd.map_canvas.queue_redraw()
				editor._refresh_ui()
				accept_event()
			elif b == MOUSE_BUTTON_MIDDLE:
				panning = event.pressed
			elif b == MOUSE_BUTTON_LEFT and not event.pressed:
				panning = false  # a left press on empty map starts it (the editor's _on_map_clicked)
		elif event is InputEventMouseMotion and panning:
			tsd.scroll -= event.relative / (_scale() * tsd.zoom)
			tsd._clamp_scroll()
			tsd.map_canvas.queue_redraw()
			accept_event()
		elif event is InputEventMouseMotion:
			editor.hover_at(_to_menu(event.position) - tsd.area.position)

	## A map point (TSD map units) in the pane's pixels.
	func map_px(m: Vector2) -> Vector2:
		return _to_screen(tsd.area.position + tsd._to_client(m))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)

	## The route being drawn: its clicked points as white dots on the line the units will drive.
	func _draw_preview() -> void:
		if tsd == null:
			return
		editor.draw_line_world(preview, editor.route_line, Color.WHITE)
		for p in editor.route_pts:
			preview.draw_circle(map_px(Tsd.world_to_map(p.x, p.y)), 5.0, Color.WHITE)
		editor.draw_marks(preview)


# --- what is where: hover, the status line, the editor's marks (docs/mission-editor.md §20) -------------------------


## A bdb object's name as the game shows it ("SA 6"), else its own ("sa6launcher").
static func _object_name(obj: Dictionary) -> String:
	var shown := String(obj.get("0x528", "")).strip_edges()
	return shown if shown != "" else String(obj.get("0x514", "?"))


## "sa6launcher_11 (SA 6) · Red · Target": a unit of the main file by its name, what it is, its side and role (the
## Units list's order).
func _describe_entity(e: Dictionary) -> String:
	var parts := ["%s (%s)" % [e.get("0x2bc", ""), _object_name(objects.get(int(e.get("0x2c6", -1)), {}))]]
	parts.append(SIDES[clampi(int(e.get("0x2d0", 1)), 1, 3) - 1])
	var role := clampi(int(e.get("0x32a", 2)), 0, 2)
	if role != 2:
		parts.append(ROLES[role])
	return " · ".join(parts)


## The map's unit `i` (tsd.units) in words, its flight too; a base mission's unit (an airbase's) is fixed.
func describe(i: int) -> String:
	var u: Dictionary = tsd.units[i]
	var e := entity(_key_id(u.key))
	var t := (
		_describe_entity(e)
		if not e.is_empty()
		else "%s (%s) · %s · airbase (fixed)" % [u.name, Tsd.unit_label(u), SIDES[clampi(int(u.side), 1, 3) - 1]]
	)
	var n := int(u.flight)
	if n > 0 and tsd.flights.has(n):
		t += " · %s%s" % [flight_name(n), " leader" if u.leader else ""]
	return t


## Flight `n` (tsd.flights' key) by its call sign: Alpha … Delta, an enemy flight by its formation's name.
func flight_name(n: int) -> String:
	if n >= 1 and n <= 4:
		return Tsd.FLIGHT_LABELS[n]
	var fo := _formation_of(n)
	return String(data.formations.items[fo].get("0x3e8", "Enemy")) if fo >= 0 else "Enemy"


## The mouse at client point `c` of the map (null: off the map): what is under it, and in Add the ground check there.
func hover_at(c) -> void:
	if tsd == null:
		return
	var h := -1
	var w := -1
	var at = null
	if c != null and Rect2(Vector2.ZERO, tsd.area.size).has_point(c):
		h = tsd.unit_at(c)
		w = tsd._waypoint_at(c) if h < 0 else -1
		at = Tsd.map_to_world(c / tsd.zoom + tsd.scroll)
	hover = h
	hover_wp = w
	mouse_world = at
	if mode == "add" and at != null:
		_check_place(at)
	if mode == "route":
		_update_ghost()
	_show_hint()
	host.preview.queue_redraw()


func _on_units_hover(event) -> void:
	var id := -1
	if event is InputEventMouseMotion:
		var i: int = _ui.units.get_item_at_position(event.position, true)
		id = int(_ui.units.get_item_metadata(i)) if i >= 0 else -1
	elif event != null:
		return
	if id != list_hover:
		list_hover = id
		host.preview.queue_redraw()


func _check_place(at: Vector2) -> void:
	var cls := int(objects.get(add_object, {}).get("0x5aa", -1))
	place_check = api.place_issues(cls, at.x, at.y)
	place_check.sort_custom(func(a, b): return a.level == "error" and b.level != "error")


## What Add places: "SA 6 (Red, Target)".
func add_text() -> String:
	var role: String = "" if _ui.add_role.selected == 2 else ", " + ROLES[_ui.add_role.selected]
	return "%s (%s%s)" % [_object_name(objects.get(add_object, {})), SIDES[_ui.add_side.selected], role]


## The status line: what a click or drag does where the mouse is, in the mode the editor is in.
func hint_text() -> String:
	if data.is_empty():
		return "Start with New mission, or Open one of yours or an original."
	var ro := "Original, read-only: Fork it to edit. " if read_only else ""
	match mode:
		"add":
			var here := ""
			if not place_check.is_empty():
				here = "Here: %s (%s). " % [place_check[0].text, place_check[0].level]
			return here + "Click the map to place %s; each click places one. Esc stops." % add_text()
		"route":
			var roads := " Along the roads: a point within 1 km of a road moves onto it." if on_roads() else ""
			return (
				(
					"Click the route's points (%d so far) for the units selected in the list, then Give the route."
					+ roads
					+ " Esc stops."
				)
				% route_pts.size()
			)
		"paste":
			return "Click the map to paste the %d copied units there. Esc stops." % clipboard.size()
	if hover >= 0:
		var can := not read_only and not entity(_key_id(tsd.units[hover].key)).is_empty()
		return ro + "%s. Click selects it%s." % [describe(hover), ", drag moves it" if can else ""]
	if hover_wp >= 0:
		return ro + "%s waypoint %d. Drag moves it." % [flight_name(tsd.sel_flight), hover_wp + 1]
	return ro + "Click a unit to select it (Shift adds). Drag the map to pan, wheel zooms, right-drag measures."


func _show_hint() -> void:
	if _ui.has("hint"):
		_ui.hint.text = hint_text()
		_ui.hint.visible = tsd != null


## The editor's marks over the TSD (MapHost's preview, never in the game's TSD): the flights' call signs, the
## units' names when zoomed in, the selection's ring (and the list's other picks), the unit under the mouse with its
## label, Add's ghost icon with its ground check, the route being drawn, the legend.
func draw_marks(c: Control) -> void:
	var s: float = host._scale()
	var font := ThemeDB.fallback_font
	if tsd.zoom >= NAMES_ZOOM:
		for u in tsd.units:
			if tsd._unit_visible(u) and not u.leader and u.name != "":
				var p: Vector2 = host.map_px(u.pos) + Vector2(0, 12 * s + font.get_ascent(MARK_FS - 2))
				var w := font.get_string_size(u.name, HORIZONTAL_ALIGNMENT_LEFT, -1, MARK_FS - 2).x
				c.draw_string_outline(font, p - Vector2(w / 2, 0), u.name, 0, -1, MARK_FS - 2, 3, Color.BLACK)
				c.draw_string(font, p - Vector2(w / 2, 0), u.name, 0, -1, MARK_FS - 2, Color(0.9, 0.9, 0.9))
	_draw_unit_routes(c)
	var keys := {}
	for i in _ui.units.get_selected_items():
		keys["0:%d" % int(_ui.units.get_item_metadata(i))] = true
	for i in tsd.units.size():
		if keys.has(tsd.units[i].key) and i != tsd.selected:
			_ring(c, host.map_px(tsd.units[i].pos), 17 * s, 2.0)
	# The labels, most important first: the selected unit's, the hovered one's (on the map or in the Units list), the
	# flights' call signs; each placed clear of the icons and of the labels placed before it (_place).
	var hv := hover if mode == "" else -1
	if hv < 0 and list_hover >= 0:
		hv = _unit_index(list_hover)
	var labels := []
	if tsd.selected >= 0 and tsd._unit_visible(tsd.units[tsd.selected]):
		labels.append([tsd.selected, describe(tsd.selected), SEL_COLOR, 31 * s])
	if hv >= 0 and hv != tsd.selected:
		labels.append([hv, describe(hv), Color.WHITE, 21 * s])
	for n in tsd.flights:
		var lead: int = tsd.flights[n].leader
		if lead != tsd.selected and lead != hv and tsd._unit_visible(tsd.units[lead]):
			var col: Color = (
				Tsd.FLIGHT_COLORS[n - 1] if n <= 4 else SIDE_COLORS[clampi(int(tsd.units[lead].side), 1, 3) - 1]
			)
			labels.append([lead, flight_name(n), col, 17 * s])
	var taken := _icon_rects(s)
	var placed := []
	for l in labels:
		placed.append(_place(host.map_px(tsd.units[l[0]].pos), _chip_size(l[1]), l[3], taken))
	# Drawn the other way round: the call signs, the hovered unit, the selection last, always on top.
	for k in range(labels.size() - 1, -1, -1):
		var l: Array = labels[k]
		var p: Vector2 = host.map_px(tsd.units[l[0]].pos)
		if l[0] == tsd.selected:
			_ring(c, p, 20 * s, 3.0)
			for t in 4:  # four ticks, as a sight
				var d := Vector2.from_angle(t * PI / 2)
				c.draw_line(p + d * 22 * s, p + d * 30 * s, SEL_COLOR, 3.0)
		elif l[0] == hv:
			_ring(c, p, 18 * s, 2.0, Color.WHITE)
		if not placed[k][2] and l[0] != tsd.selected and l[0] != hv:
			continue  # a call sign with no free place (a leader under the legend): left out
		var r: Rect2 = placed[k][0]
		if placed[k][1]:  # placed farther out: a leader line from the icon
			c.draw_line(p, p.clamp(r.position, r.end), Color.BLACK, 4.0)
			c.draw_line(p, p.clamp(r.position, r.end), l[2], 2.0)
		_chip(c, r.position, l[1], l[2])
	if hover_wp >= 0 and mode == "" and tsd.flights.has(tsd.sel_flight):
		_ring(c, host.map_px(tsd.flights[tsd.sel_flight].points[hover_wp]), 13 * s, 2.0)
	if mouse_world != null and mode in ["add", "paste"]:
		var p: Vector2 = host.map_px(Tsd.world_to_map(mouse_world.x, mouse_world.y))
		var col := Color(0.4, 1.0, 0.4)
		var text := add_text() if mode == "add" else "%d units" % clipboard.size()
		if not place_check.is_empty():
			col = Color.RED if place_check[0].level == "error" else Color.YELLOW
			text += ": " + String(place_check[0].text)
		if mode == "add":
			_ghost(c, p, s)
		_ring(c, p, 20 * s, 2.0, col)
		_chip(c, p + Vector2(-20 * s, 24 * s), text, col)
	if mode == "route":
		draw_line_world(c, route_ghost, Color(1, 1, 1, 0.6))
	_draw_legend(c)


## A world line (X east, Y north) on the map, with a dark edge.
func draw_line_world(c: Control, line: PackedVector2Array, col: Color) -> void:
	if line.size() < 2:
		return
	var px := PackedVector2Array()
	for p in line:
		px.append(host.map_px(Tsd.world_to_map(p.x, p.y)))
	c.draw_polyline(px, Color(0, 0, 0, 0.7 * col.a), 4.0, true)
	c.draw_polyline(px, col, 2.0, true)


## The routes (Path, motion op 16) of the units selected in the list, as they will be driven, the end marked.
func _draw_unit_routes(c: Control) -> void:
	var paths := {}
	for i in _ui.units.get_selected_items():
		for sc in entity(int(_ui.units.get_item_metadata(i))).get("scripts0", {}).get("items", []):
			if int(sc.get("0x83e", -1)) == 16:
				paths[int(sc.get("0x8ac", -1))] = true
	for p in data.get("paths", {}).get("items", []):
		if paths.has(int(p.get("0x1e", -2))) and p.get("points", []).size() > 1:
			var line := PackedVector2Array()
			for q in p.points:
				line.append(Vector2(float(q[1]), float(q[2])))
			draw_line_world(c, line, SEL_COLOR)
			_ring(c, host.map_px(Tsd.world_to_map(line[-1].x, line[-1].y)), 6 * host._scale(), 2.0)


## A ring with a dark edge, readable on both the sea and the desert.
func _ring(c: Control, p: Vector2, r: float, width: float, col := SEL_COLOR) -> void:
	c.draw_arc(p, r, 0, TAU, 48, Color(0, 0, 0, 0.8), width + 2.0, true)
	c.draw_arc(p, r, 0, TAU, 48, col, width, true)


## A label's box size.
func _chip_size(text: String) -> Vector2:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MARK_FS) + Vector2(8, 4)


## The map's free area for labels: above the legend and the status line.
func _label_area() -> Rect2:
	return Rect2(
		Vector2.ZERO, host.size - Vector2(0, _ui.hint.size.y + ThemeDB.fallback_font.get_height(MARK_FS - 2) + 6)
	)


## The visible units' icons (and the TSD's own label under the selected one) in the pane's pixels, a little grown.
func _icon_rects(s: float) -> Array:
	var out := []
	var view := Rect2(Vector2.ZERO, host.size)
	for u in tsd.units:
		var p: Vector2 = host.map_px(u.pos)
		if tsd._unit_visible(u) and view.has_point(p):
			var sz := Vector2(27, 21 if u.klass == 1 else 17) * s
			out.append(Rect2(p - sz / 2, sz).grow(2))
	if tsd.selected >= 0:
		var p: Vector2 = host.map_px(tsd.units[tsd.selected].pos)
		out.append(Rect2(p + Vector2(-45 * s, 10 * s), Vector2(90 * s, 32 * s)))  # tsd.gd's two yellow lines
	return out


## A label of size `sz` for the icon at `p`: the first of eight places around it (right, left, below, above, the
## corners) at `r` that stays in the free area clear of `taken`, else the same farther out with a leader line, else
## right of it. Returns [rect, leader, found]; a found rect joins `taken`.
func _place(p: Vector2, sz: Vector2, r: float, taken: Array) -> Array:
	var area := _label_area()
	var out := [Rect2(p + Vector2(r, -sz.y / 2), sz), false, false]
	var found := false
	for far in [false, true]:
		var d: float = r * (2.5 if far else 1.0)
		var e := d * 0.7
		for at in [
			Vector2(d, -sz.y / 2),
			Vector2(-d - sz.x, -sz.y / 2),
			Vector2(-sz.x / 2, d),
			Vector2(-sz.x / 2, -d - sz.y),
			Vector2(e, -e - sz.y),
			Vector2(e, e),
			Vector2(-e - sz.x, -e - sz.y),
			Vector2(-e - sz.x, e),
		]:
			var rect := Rect2(p + at, sz)
			if area.encloses(rect) and not taken.any(func(t): return t.intersects(rect)):
				out = [rect, far, true]
				found = true
				break
		if found:
			break
	if found:
		taken.append(out[0])
	return out


## The map's index of the main file's unit `id`, -1 when not on the map.
func _unit_index(id: int) -> int:
	for i in tsd.units.size():
		if tsd.units[i].key == "0:%d" % id:
			return i
	return -1


## A white label on a dark box framed in `col` at `p` (its top left), kept inside the map.
func _chip(c: Control, p: Vector2, text: String, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var sz := _chip_size(text)
	p = p.clamp(Vector2.ZERO, (host.size - sz - Vector2(0, _ui.hint.size.y)).max(Vector2.ZERO))
	c.draw_rect(Rect2(p, sz), Color(0, 0, 0, 0.75))
	c.draw_rect(Rect2(p, sz), col, false, 2.0)
	c.draw_string(font, p + Vector2(4, 2 + font.get_ascent(MARK_FS)), text, 0, -1, MARK_FS, Color.WHITE)


## Add's object as its TSD icon at `p`, half see-through.
func _ghost(c: Control, p: Vector2, s: float) -> void:
	var klass: int = Tsd.ICON_CLASS.get(int(objects.get(add_object, {}).get("0x5aa", -1)), 0)
	if klass == 0:
		return
	var t: Texture2D = host._tex("tsd/%s.png" % Tsd.ICON_ART[klass])
	if t == null:
		return
	var cell := Tsd.icon_cell(klass, _ui.add_side.selected + 1, false, 0.0)
	var a: float = host.art_scale
	c.draw_texture_rect_region(
		t, Rect2(p - cell.size * s / 2, cell.size * s), Rect2(cell.position * a, cell.size * a), Color(1, 1, 1, 0.6)
	)


## The legend, bottom left over the status line: the sides' colours, the rings, the flights' squares.
func _draw_legend(c: Control) -> void:
	var font := ThemeDB.fallback_font
	var fs := MARK_FS - 2
	var items := [
		["Blue", SIDE_COLORS[0], "box"],
		["Red", SIDE_COLORS[1], "box"],
		["selected", SEL_COLOR, "ring"],
		["warning", Color.YELLOW, "ring"],
		["error", Color.RED, "ring"],
	]
	for n in 4:
		items.append([Tsd.FLIGHT_LABELS[n + 1], Tsd.FLIGHT_COLORS[n], "square"])
	var w := 8.0
	for it in items:
		w += 18 + font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10
	var h := font.get_height(fs) + 6
	var top: float = host.size.y - _ui.hint.size.y - h
	c.draw_rect(Rect2(0, top, w, h), Color(0, 0, 0, 0.6))
	var x := 8.0
	var mid := top + h / 2
	for it in items:
		match it[2]:
			"box":
				c.draw_rect(Rect2(x, mid - 6, 13, 12), it[1])
			"ring":
				c.draw_arc(Vector2(x + 6, mid), 6, 0, TAU, 24, it[1], 2.0, true)
			"square":
				c.draw_rect(Rect2(x, mid - 6, 12, 12), it[1], false, 2.0)
		x += 18
		c.draw_string(font, Vector2(x, mid - h / 2 + 3 + font.get_ascent(fs)), it[0], 0, -1, fs, Color.WHITE)
		x += font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10


# --- win and lose (docs/mission-editor.md §12) ---------------------------------------------------------------------


## Sets role `role` (0 must survive, 1 target, 2 neutral) on every unit selected in the Units list (else the selected
## unit).
func mark_selected(role: int) -> void:
	var ids := PackedInt64Array()
	for i in _ui.units.get_selected_items():
		ids.append(int(_ui.units.get_item_metadata(i)))
	if ids.is_empty() and sel_id >= 0:
		ids.append(sel_id)
	if not ids.is_empty():
		_edit(api.set_role(data, ids, role))


## Selects in the Units list every unit of the selected unit's bdb object (all the SA-6s, all the T-62s…).
func select_same_kind() -> void:
	var obj := int(entity(sel_id).get("0x2c6", -2))
	for i in _ui.units.item_count:
		if int(entity(int(_ui.units.get_item_metadata(i))).get("0x2c6", -1)) == obj:
			_ui.units.select(i, false)


func _build_roles(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	box.add_child(_label("Win and lose: mark the units selected in the list"))
	var h := HBoxContainer.new()
	box.add_child(h)
	_ui.mark = [
		_button(h, "Target", func(): mark_selected(1)),
		_button(h, "Must survive", func(): mark_selected(0)),
		_button(h, "Neutral", func(): mark_selected(2)),
	]
	_ui.same_kind = _button(box, "Select all units of this kind", select_same_kind)


func _build_conditions(box: VBoxContainer) -> void:
	box.add_child(_label("Win and lose (what passes and fails it: the line under the map)"))
	_ui.passed_text = _row(box, "Passed headline", LineEdit.new())
	_ui.passed_text.text_submitted.connect(func(t): set_misc("0x47e", t))
	_ui.passed_text.focus_exited.connect(func(): set_misc("0x47e", _ui.passed_text.text))
	_ui.failed_text = _row(box, "Failed headline", LineEdit.new())
	_ui.failed_text.text_submitted.connect(func(t): set_misc("0x492", t))
	_ui.failed_text.focus_exited.connect(func(): set_misc("0x492", _ui.failed_text.text))
	box.add_child(HSeparator.new())


func _fill_conditions() -> void:
	var text := String(conditions.get("summary", ""))
	_ui.cond_line.text = text
	_ui.cond_line.tooltip_text = text
	_ui.cond_line.modulate = Color.WHITE if conditions.get("can_pass", true) else Color.RED
	for k in ["passed_text", "failed_text"]:
		if not _ui[k].has_focus():
			_ui[k].text = String(conditions.get(k, ""))
		_ui[k].editable = not read_only
	for b in _ui.mark:
		b.disabled = read_only


# --- intel and randomness (docs/mission-editor.md §14, §15) ---------------------------------------------------------

## The quick intel picks: label → bdb object classes (0x5aa); [] every class.
const KNOWN_KINDS := [
	["All units", []],
	["SAM / AAA", [8, 9, 10]],
	["Ground units", [5, 6, 8, 9, 10, 11, 0xc, 0xd, 0x1d, 0x1e, 0xf, 0x10]],
	["Aircraft", [2, 3, 0x1c]],
	["Ships", [0xf, 0x10]],
]
const KNOWN_SIDES := ["Red", "Blue", "Any side"]

## The random settings per entity id ({"<id>": {chance (%), spread_km}}), saved as the custom file's "random"; Fly
## rolls them (IafMissionEdit roll), the mission data never holds them.
var random := {}
## The map as the pilot sees it before the flight: the TSD out of its edit mode (only known units).
var intel_preview := false
## The map shows one roll (preview_seed) of the random settings.
var roll_preview := false
var preview_seed := 0
## Fly's roll seed; -1 a fresh one each Fly (a test sets it).
var roll_seed := -1


## The briefing links, the random settings and the previews of a mission just opened.
func _intel_opened(entries: Array, rnd: Dictionary) -> void:
	briefing["entries"] = entries.duplicate(true)
	random = rnd.duplicate(true)
	intel_preview = false
	roll_preview = false


## An original mission's briefing links (briefings.json missions[id].entries).
func _original_links(id: int) -> Array:
	var b := Settings.load_json(Settings.assets_dir().path_join("converted/briefings/briefings.json"))
	return b.get("missions", {}).get(str(id), {}).get("entries", [])


## The files the map shows: the edited ones, or one roll of them in the roll preview.
func _map_files() -> Array:
	return _rolled(preview_seed) if roll_preview else files()


## The files Fly gives the game: the random settings rolled with a fresh seed (roll_seed when set).
func _fly_files() -> Array:
	return _rolled(roll_seed if roll_seed >= 0 else randi())


func _rolled(seed: int) -> Array:
	if random.is_empty():
		return files()
	return [{"name": main_name, "data": api.roll(data, random, seed)}] + base_files


## The units selected in the Units list, else the selected unit.
func _picked_ids() -> PackedInt64Array:
	var ids := PackedInt64Array()
	for i in _ui.units.get_selected_items():
		ids.append(int(_ui.units.get_item_metadata(i)))
	if ids.is_empty() and sel_id >= 0:
		ids.append(sel_id)
	return ids


## "Shown on the pilot's TSD" (entity 0x35c) on or off for `ids`.
func set_known(ids: PackedInt64Array, known: bool) -> void:
	if not ids.is_empty():
		_edit(api.set_known(data, ids, known))


## The units of bdb classes `classes` ([] all) on side `side` (1 blue, 2 red, 0 any).
func units_of(classes: Array, side: int) -> PackedInt64Array:
	var ids := PackedInt64Array()
	for e in data.get("entities", {}).get("items", []):
		if int(e.get("0x14", 0)) != 0 or (side > 0 and int(e.get("0x2d0", 0)) != side):
			continue
		if classes.is_empty() or _class_of(e) in classes:
			ids.append(int(e.get("0x1e", -1)))
	return ids


## The chance (0..100 %) and the start spread (km) of the units `ids`; 100 % and 0 km remove the setting.
func set_random(ids: PackedInt64Array, chance: float, spread_km: float) -> void:
	if read_only:
		return
	for id in ids:
		if chance >= 100.0 and spread_km <= 0.0:
			random.erase(str(id))
		else:
			random[str(id)] = {"chance": chance, "spread_km": spread_km}
	_refresh()


func set_intel_preview(on: bool) -> void:
	intel_preview = on
	_refresh()


## The map shows a new roll (on), or the mission as edited.
func set_roll_preview(on: bool) -> void:
	roll_preview = on
	preview_seed = randi()
	_refresh()


func add_link(link: Dictionary) -> void:
	if read_only or briefing.entries.any(func(l): return l.file == link.file):
		return
	briefing.entries.append(link.duplicate(true))
	_refresh_ui()


func remove_link(i: int) -> void:
	if not read_only and i >= 0 and i < briefing.entries.size():
		briefing.entries.remove_at(i)
		_refresh_ui()


func _set_link_title(lang: String, t: String) -> void:
	var sel: PackedInt32Array = _ui.links.get_selected_items()
	if not read_only and not sel.is_empty() and t.strip_edges() != "":
		briefing.entries[sel[0]].title[lang] = t.strip_edges()
		_refresh_ui()


func _build_random(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	box.add_child(_label("Random, rolled at each Fly (the units selected in the list; a flight rolls as one)"))
	_ui.r_chance = _row(box, "Appears %", _spin(0, 100, 5, func(_v): pass))
	_ui.r_chance.value = 100
	_ui.r_spread = _row(box, "Start spread km", _spin(0, 100, 0.5, func(_v): pass))
	_ui.r_set = _button(
		box, "Set for the selected units", func(): set_random(_picked_ids(), _ui.r_chance.value, _ui.r_spread.value)
	)
	var h := HBoxContainer.new()
	box.add_child(h)
	_ui.r_preview = _button(h, "Roll preview", func(): set_roll_preview(_ui.r_preview.button_pressed))
	_ui.r_preview.toggle_mode = true
	_button(h, "Roll again", func(): set_roll_preview(true))


func _build_intel_tab(box: VBoxContainer) -> void:
	box.add_child(_label("What the pilot sees before the flight"))
	_ui.i_preview = _row(box, "", CheckBox.new())
	_ui.i_preview.text = "Intel preview: the map as the pilot sees it"
	_ui.i_preview.toggled.connect(set_intel_preview)
	_ui.i_known = _row(box, "", CheckBox.new())
	_ui.i_known.text = "Shown on the pilot's TSD (the units selected in the list)"
	_ui.i_known.toggled.connect(func(on): set_known(_picked_ids(), on))
	var note := _label("The TSD draws a SAM's range ring around each SAM it shows.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	_ui.i_kind = _row(box, "Units", _options(KNOWN_KINDS.map(func(k): return k[0]), func(_i): pass))
	_ui.i_side = _row(box, "Side", _options(KNOWN_SIDES, func(_i): pass))
	var h := HBoxContainer.new()
	box.add_child(h)
	_ui.i_quick = [
		_button(h, "Show all", func(): set_known(_quick_ids(), true)),
		_button(h, "Hide all", func(): set_known(_quick_ids(), false)),
	]
	box.add_child(HSeparator.new())
	box.add_child(_label("Briefing links (the TSD briefing's model windows)"))
	_ui.links = ItemList.new()
	_ui.links.custom_minimum_size.y = 140
	_ui.links.item_selected.connect(func(_i): _fill_intel())
	box.add_child(_ui.links)
	_ui.link_en = _row(box, "Title (English)", LineEdit.new())
	_ui.link_en.text_submitted.connect(func(t): _set_link_title("en", t))
	_ui.link_he = _row(box, "Title (Hebrew)", LineEdit.new())
	_ui.link_he.text_direction = Control.TEXT_DIRECTION_RTL
	_ui.link_he.text_submitted.connect(func(t): _set_link_title("he", t))
	_ui.link_remove = _button(box, "Remove the link", func(): remove_link(_selected_link()))
	_ui.link_pick = _row(box, "Unit type", OptionButton.new())
	_ui.link_add = _button(box, "Add the link", _on_add_link)


func _quick_ids() -> PackedInt64Array:
	return units_of(KNOWN_KINDS[_ui.i_kind.selected][1], [2, 1, 0][_ui.i_side.selected])


func _selected_link() -> int:
	var sel: PackedInt32Array = _ui.links.get_selected_items()
	return sel[0] if not sel.is_empty() else -1


func _on_add_link() -> void:
	var i: int = _ui.link_pick.selected
	if i >= 0:
		add_link(_ui.link_pick.get_item_metadata(i))


func _fill_intel() -> void:
	if not _ui.has("links"):
		return
	var e := entity(sel_id)
	_ui.i_known.set_pressed_no_signal(int(e.get("0x35c", 0)) != 0)
	_ui.i_preview.set_pressed_no_signal(intel_preview)
	_ui.r_preview.set_pressed_no_signal(roll_preview)
	var r: Dictionary = random.get(str(sel_id), {})
	_ui.r_chance.set_value_no_signal(float(r.get("chance", 100)))
	_ui.r_spread.set_value_no_signal(float(r.get("spread_km", 0)))
	for c in [_ui.i_known, _ui.r_set, _ui.link_remove, _ui.link_add] + _ui.i_quick:
		c.disabled = read_only or data.is_empty()
	var keep := _selected_link()
	_ui.links.clear()
	var entries: Array = briefing.get("entries", [])
	for l in entries:
		_ui.links.add_item("%s / %s" % [l.title.get("en", ""), l.title.get("he", "")])
	if keep >= 0 and keep < entries.size():
		_ui.links.select(keep)
		_ui.link_en.text = String(entries[keep].title.get("en", ""))
		_ui.link_he.text = String(entries[keep].title.get("he", ""))
	_ui.link_pick.clear()
	for l in api.intel_links(data) if not data.is_empty() else []:
		if not entries.any(func(x): return x.file == l.file):
			_ui.link_pick.add_item(String(l.title.en))
			_ui.link_pick.set_item_metadata(_ui.link_pick.item_count - 1, l)


# --- the sanity check, Duplicate, Copy / Paste, the year's map (docs/mission-editor.md §16, §17, §12) ---------------

## The units Copy took: their entities as they were (any mission's).
var clipboard: Array = []
## Base missions a year change dropped (nobody held the base), by stem: a later year that allows it brings them back.
var parked_bases := {}


## The sanity check's warnings and the base missions that do not fit the year, added to the check.
func _more_issues() -> Array:
	if data.is_empty():
		return []
	var bases := base_files.map(func(f): return [String(f.name), _base_side(f.data)])
	return api.sanity(data) + api.base_issues(bases, year)


## The open mission of your own copied under `name`; you go on editing this one (Save as edits the copy).
func duplicate_mission(name: String) -> void:
	if read_only or file == "" or name_error(name) != "":
		return
	var keep := [file, mission_name]
	save_as(name)
	file = keep[0]
	mission_name = keep[1]
	data.misc.items[0]["0x44c"] = mission_name
	_refresh()


## The units selected in the Units list (else the selected unit) copied for Paste. Their routes are not copied.
func copy_selected() -> void:
	var ids := []
	for i in _ui.units.get_selected_items():
		ids.append(int(_ui.units.get_item_metadata(i)))
	if ids.is_empty() and sel_id >= 0:
		ids.append(sel_id)
	clipboard = ids.map(func(id): return entity(id).duplicate(true)).filter(func(e): return not e.is_empty())
	_fill_clipboard()


## The copied units placed with their centre at world X / Y, keeping their layout and headings: new ids, a ground unit
## at the terrain's height, roles kept, no routes. The pasted units become the selection.
func paste_at(x: float, y: float) -> Array:
	if read_only or data.is_empty() or clipboard.is_empty():
		return []
	var c := Vector2.ZERO
	for e in clipboard:
		c += Vector2(float(e["0x2e4"]), float(e["0x2ee"]))
	c /= clipboard.size()
	var r := api.paste_group(data, clipboard, x - c.x, y - c.y)
	var ids: Array = r.ids.map(func(i): return int(i))
	if ids.is_empty():
		return []
	sel_id = ids[-1]
	_set_mode("")
	_edit(r.mission)
	_ui.units.deselect_all()
	for i in _ui.units.item_count:
		if int(_ui.units.get_item_metadata(i)) in ids:
			_ui.units.select(i, false)
	return ids


## Removes the enemy flight picked on the Flights tab, with its jets.
func remove_enemy_flight() -> void:
	if read_only or tsd == null or tsd.sel_flight <= 4 or not tsd.flights.has(tsd.sel_flight):
		return
	var fo := _formation_of(tsd.sel_flight)
	tsd.sel_flight = 0
	sel_wp = -1
	sel_id = -1
	_edit(api.remove_formation(data, fo))


## A year on another TSD map than the source's: the mission moves to the year's original (its map, its base
## missions), its units kept. The bases of before stay while someone holds them that year, else they wait in
## parked_bases for a year that allows them; base_issues warns of a base now held by the other side.
func _follow_year_map() -> void:
	if read_only or source < 0:
		return
	var s := api.year_map_source(source, year)
	if s == source or not originals.has(s):
		return
	var new_bases := _read_bases(s)
	var stems := new_bases.map(func(f): return String(f.name).trim_suffix("_flipped"))
	for f in base_files + parked_bases.values():
		var stem := String(f.name).trim_suffix("_flipped")
		# An airbase of the year table (held in 1966 or 1998) that nobody holds this year waits.
		var airbase := api.base_owner(stem, 1966.0) != 0 or api.base_owner(stem, 1998.0) != 0
		if airbase and api.base_owner(stem, year) == 0:
			if not stem in stems:
				parked_bases[stem] = f
			continue
		parked_bases.erase(stem)
		var i: int = stems.find(stem)
		if i >= 0:
			new_bases[i] = f  # yours (a flipped copy too) in place of the original's
		else:
			new_bases.append(f)
			stems.append(stem)
	source = s
	base_files = new_bases
	# The new map opens on the same place and zoom.
	var centre: Vector2 = tsd.scroll + tsd._view_size() / 2
	var zoom: float = tsd.zoom
	_new_map(s)
	tsd.zoom = zoom
	tsd.centre_on(centre)


func _build_clipboard(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var head := _label("Copy the units selected in the list (Ctrl+C), then Paste (Ctrl+V) and click the map")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var h := HBoxContainer.new()
	box.add_child(h)
	_ui.copy = _button(h, "Copy", copy_selected)
	_ui.paste = _button(h, "Paste (click the map)", func(): _set_mode("paste"))
	_ui.paste.toggle_mode = true
	_ui.clip_info = _label("")
	_ui.clip_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_ui.clip_info)


func _fill_clipboard() -> void:
	_ui.duplicate.disabled = read_only or file == ""
	_ui.copy.disabled = data.is_empty()
	_ui.paste.disabled = read_only or clipboard.is_empty()
	_ui.clip_info.text = (
		"" if clipboard.is_empty() else "%d units copied (their routes are not copied)" % clipboard.size()
	)
	_ui.red_remove.visible = tsd != null and tsd.sel_flight > 4 and tsd.flights.has(tsd.sel_flight)
	_ui.red_remove.disabled = read_only


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE and (mode != "" or sel_id >= 0):
		# Esc leaves a placing mode (Add, route, paste), else clears the selection.
		if mode != "":
			_set_mode("")
		else:
			sel_id = -1
			sel_wp = -1
			_ui.units.deselect_all()
			_refresh()
	elif event.is_command_or_control_pressed() and event.keycode == KEY_C:
		copy_selected()
	elif event.is_command_or_control_pressed() and event.keycode == KEY_V and not clipboard.is_empty():
		_set_mode("paste")
	else:
		return
	get_viewport().set_input_as_handled()
