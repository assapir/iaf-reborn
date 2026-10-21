# The mission editor (ours, docs/mission-editor.md): opens a converted mission, edits it on the pre-flight TSD's map
# (game/menu/tsd.gd in its edit mode, hosted by MapHost below) and saves it under user://missions/. The original
# missions only open read-only; Fork copies one into a mission of your own. Fly starts the edited mission through the
# game's TSD (Settings.fly_edited). The mission logic (ids, routes, flights, the checks) is IafMissionEdit's.
extends Control

const Tsd := preload("res://menu/tsd.gd")
const EditApi := preload("res://editor/_edit_api.gd")
const Img := preload("res://util/img.gd")

const UNDO_MAX := 50
## The Add picker's classes: label → bdb object classes (0x5aa).
const ADD_CLASSES := [
	["Aircraft", [2, 3, 0x1c]],
	["SAM / AAA", [8, 9, 10, 11]],
	["Vehicles", [5, 6]],
	["Buildings", [0xc, 0xd, 0x1d, 0x1e]],
	["Ships", [0xf, 0x10]],
]
const AIR_CLASSES := [2, 3, 0x1c]
const SIDES := ["Blue", "Red", "Neutral"]
const ROLES := ["Must survive", "Target", "Neutral"]
## Wind as the Mission Creator's Better combos (mission_creator.gd); Random stores 1, which the game turns into a
## random one of 0 / 10 / 15 / 20 kt (Settings.pick_wind).
const WIND_KT := [["Calm", 0], ["10 kt", 10], ["15 kt", 15], ["20 kt", 20], ["Random", 1]]
## New: per era, the original the mission is built on (its TSD map and airbases), the blue home bases and jets.
## Inferred from history: Sinai's Refidim was Israeli 1967–1982 (so 1973 only); Ramon opened in 1982; the jets by
## their IAF service (bdb object ids: 47 Mirage, 48 F-4 of the 1970s, 1 F-16, 40 F-15, 17 F-4 2000, 99 Kfir, 74 Lavi).
const NEW_ERAS := [
	["1998", 231, ["Ramat David", "Tel Nof", "Ramon"], [1, 40, 17, 99, 74]],
	["1973", 121, ["Ramat David", "Tel Nof", "Refidim"], [48, 47]],
	["1967", 111, ["Ramat David", "Tel Nof"], [47]],
]
## Home base → its base mission and start point (x, y, z, heading): the Mission Creator's (mission_creator.rs
## BASES), Refidim from 121's Alpha.
const NEW_BASES := {
	"Tel Nof": ["bmistlnf", 312984.0, 500459.0, 59.0, 90.0],
	"Ramat David": ["bmisrdvd", 356404.0, 602402.0, 28.0, 270.0],
	"Ramon": ["bmisrmon", 317439.0, 411135.0, 579.0, 230.0],
	"Refidim": ["bmisrfdim", 153765.0, 373720.0, 98.0, 0.0],
}
const WIND_FROM := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

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
var file := ""  # its user:// file, "" while unsaved
var read_only := true
var objects := {}  # the bdb's Objects by id
var undo: Array = []
var issues: Array = []
var sel_id := -1  # the selected entity (main file)
var sel_wp := -1  # the selected waypoint of the TSD's selected flight
var mode := ""  # "" | "add" | "route"
var route_pts: Array = []  # world Vector3, while drawing a route
var add_object := -1  # the bdb object id the Add places

var tsd: Control
var host: Control
var _ui := {}
var _name_purpose := ""


func _ready() -> void:
	mission_dir = Settings.assets_dir().path_join("converted/missions")
	_load_originals()
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
	read_only = true
	file = ""
	_refresh()


func open_file(path: String) -> void:
	var d := Settings.load_json(path)
	if d.is_empty() or d.get("files", []).is_empty():
		return
	_open(int(d.source), String(d.name), String(d.files[0].name), d.files[0].data)
	if d.has("bases"):
		base_files = _read_bases(source, d.bases)
		_refresh()
	var b: Dictionary = d.get("briefing", {})
	briefing = {"en": String(b.get("en", "")), "he": String(b.get("he", ""))}
	read_only = false
	file = path
	_refresh()


func _open(id: int, name: String, main: String, main_data: Dictionary) -> void:
	source = id
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
func _hidpi() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	win.content_scale_factor = maxf(1.0, DisplayServer.screen_get_scale(win.current_screen))


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


## A new mission called `name` from scratch on the era's original (NEW_ERAS): only its Alpha flight stays.
func new_mission(name: String, era: int, base: String, jet: int, wingman: bool) -> void:
	var e: Array = NEW_ERAS[era]
	var b: Array = NEW_BASES[base]
	open_original(e[1])
	data = api.blank(data)
	if not b[0] in base_files.map(func(f): return f.name):
		base_files.append({"name": b[0], "data": Settings.load_json(mission_dir.path_join(b[0] + ".json"))})
	var ahead := Vector2(b[1], b[2]) + Vector2.from_angle(deg_to_rad(90.0 - b[4])) * 20000.0
	var spec := {"type": jet, "count": 2 if wingman else 1, "slot_x": b[1], "slot_y": b[2], "alt": b[3]}
	spec.merge({"heading": b[4], "points": [[ahead.x, ahead.y, 3000.0, 800.0]]})
	data = api.set_flight(data, 1, spec)
	briefing = {"en": "", "he": ""}
	read_only = false
	file = ""
	save_as(name)
	_refresh()
	_frame_view()


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
	out["bases"] = base_files.map(func(f): return f.name)
	out["briefing"] = briefing.duplicate()
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
	if e.is_empty():
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
	var pts := PackedVector3Array(route_pts)
	mode = ""
	route_pts.clear()
	_edit(api.set_route(data, ids, pts, _ui.route_speed.value, _ui.route_hover.button_pressed))


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
			add_unit(add_object, w.x, w.y, _ui.add_side.selected + 1, _ui.add_role.selected)
		"route":
			route_pts.append(Vector3(roundf(w.x), roundf(w.y), 0.0))  # z 0: on the terrain
			host.preview.queue_redraw()
		_:
			sel_id = -1
			sel_wp = -1
			_refresh()


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
	Settings.fly_edited(source, files(), briefing.duplicate(), fly_flight(), file)


# --- UI -------------------------------------------------------------------------------------------------------------


func _refresh() -> void:
	if tsd != null:
		var keep_sel := sel_id
		tsd.reload(files())
		tsd.selected = -1
		for i in tsd.units.size():
			if tsd.units[i].key == "0:%d" % keep_sel:
				tsd.selected = i
	issues = api.check(data) if not data.is_empty() else []
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
	_ui.fork.disabled = source < 0
	_ui.start.visible = source < 0
	_ui.save.disabled = read_only
	_ui.save_as.disabled = read_only
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
	var pop: PopupMenu = _ui.issues.get_popup()
	pop.clear()
	for it in issues:
		pop.add_item("%s: %s" % [it.level.capitalize(), it.text])
		pop.set_item_metadata(pop.item_count - 1, int(it.id))
	_ui.issues.text = (
		"No issues" if issues.is_empty() else "%d errors, %d warnings" % [errors(), issues.size() - errors()]
	)
	_ui.issues.modulate = Color.RED if errors() > 0 else (Color.YELLOW if not issues.is_empty() else Color.WHITE)
	_ui.fly.disabled = read_only or errors() > 0 or fly_flight() == 0
	_fill_units()
	_fill_props()
	_fill_flights()
	_fill_mission()
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
	_ui.save = _button(bar, "Save", save)
	_ui.save_as = _button(bar, "Save as", func(): _ask_name("save_as", mission_name))
	_ui.undo = _button(bar, "Undo", undo_last)
	_ui.title = Label.new()
	_ui.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_ui.title)
	_ui.issues = MenuButton.new()
	_ui.issues.get_popup().index_pressed.connect(_on_issue_pressed)
	bar.add_child(_ui.issues)
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
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.x = 400
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(tabs)
	_build_units_tab(_tab(tabs, "Units"))
	_build_flights_tab(_tab(tabs, "Flights"))
	_build_mission_tab(_tab(tabs, "Mission"))
	_build_dialogs()


func _tab(tabs: TabContainer, name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	_ui.units.custom_minimum_size.y = 260
	_ui.units.multi_selected.connect(func(_i, _s): _on_unit_listed())
	box.add_child(_ui.units)
	box.add_child(_label("Selected unit"))
	_ui.p_name = _row(box, "Name", LineEdit.new())
	_ui.p_name.text_submitted.connect(func(t): set_field("0x2bc", t))
	_ui.p_side = _row(box, "Side", _options(SIDES, func(i): set_field("0x2d0", i + 1)))
	_ui.p_role = _row(box, "Role", _options(ROLES, func(i): set_field("0x32a", i)))
	_ui.p_heading = _row(box, "Heading °", _spin(0, 359, 1, func(v): set_field("0x302", v)))
	_ui.p_alt = _row(box, "Altitude m", _spin(-1000, 20000, 1, func(v): set_field("0x2f8", v)))
	_ui.p_where = _row(box, "Position", _label(""))
	_button(box, "Delete unit", delete_selected)
	box.add_child(HSeparator.new())
	box.add_child(_label("Add a unit"))
	_ui.add_class = _row(box, "Kind", _options(ADD_CLASSES.map(func(c): return c[0]), func(_i): _fill_object_picker()))
	_ui.add_obj = _row(box, "Object", _options([], func(_i): add_object = _ui.add_obj.get_selected_metadata()))
	_ui.add_side = _row(box, "Side", _options(SIDES, func(_i): pass))
	_ui.add_side.select(1)
	_ui.add_role = _row(box, "Role", _options(ROLES, func(_i): pass))
	_ui.add_role.select(1)
	_ui.add_mode = _button(box, "Place on the map (click)", func(): _set_mode("add"))
	_ui.add_mode.toggle_mode = true
	box.add_child(HSeparator.new())
	box.add_child(_label("Give a route to the units selected in the list"))
	_ui.route_speed = _row(box, "Speed km/h", _spin(1, 2000, 1, func(_v): pass))
	_ui.route_speed.value = 40
	_ui.route_hover = _row(box, "At the end", CheckBox.new())
	_ui.route_hover.text = "Hover"
	_ui.route_mode = _button(box, "Draw the route (click points)", func(): _set_mode("route"))
	_ui.route_mode.toggle_mode = true
	_button(box, "Give the route", apply_route)
	_button(box, "Clear the selected unit's route", clear_route)


func _build_flights_tab(box: VBoxContainer) -> void:
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
		_button(h, "Set", func(): apply_flight(k))
		_button(h, "Remove", func(): remove_flight(k))
		box.add_child(h)
		_ui.flight_rows.append({"type": t, "count": c})
	box.add_child(HSeparator.new())
	box.add_child(_label("Route of the flight (click its unit or pick it here)"))
	_ui.route_of = _row(box, "Flight", _options([], _on_route_flight))
	_ui.wps = ItemList.new()
	_ui.wps.custom_minimum_size.y = 200
	_ui.wps.item_selected.connect(_on_waypoint_listed)
	box.add_child(_ui.wps)
	_ui.wp_alt = _row(box, "Altitude m", _spin(0, 20000, 10, func(v): set_waypoint_value(3, v)))
	_ui.wp_speed = _row(box, "Speed km/h", _spin(0, 3000, 10, func(v): set_waypoint_value(4, v)))
	_button(box, "Insert a waypoint after", insert_waypoint)
	_button(box, "Delete the waypoint", delete_waypoint)


func _build_mission_tab(box: VBoxContainer) -> void:
	_ui.m_name = _row(box, "Name", _label(""))
	_ui.m_hour = _row(box, "Start hour", _spin(0, 23, 1, func(_v): _set_time()))
	_ui.m_min = _row(box, "Start minute", _spin(0, 59, 1, func(_v): _set_time()))
	_ui.m_wind = _row(
		box, "Wind", _options(WIND_KT.map(func(w): return w[0]), func(i): set_misc("0x46a", WIND_KT[i][1]))
	)
	_ui.m_from = _row(box, "From", _options(WIND_FROM, func(i): set_misc("0x474", i * 45)))
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
	_ui.open_dlg = ConfirmationDialog.new()
	_ui.open_dlg.title = "Open a mission"
	_ui.open_dlg.ok_button_text = "Open"
	_ui.open_list = ItemList.new()
	_ui.open_list.custom_minimum_size = Vector2(520, 520)
	_ui.open_list.item_activated.connect(func(_i): _ui.open_dlg.hide.call_deferred())
	_ui.open_list.item_activated.connect(func(_i): _open_picked())
	_ui.open_dlg.add_child(_ui.open_list)
	_ui.open_dlg.confirmed.connect(_open_picked)
	add_child(_ui.open_dlg)
	_ui.name_dlg = ConfirmationDialog.new()
	var v := VBoxContainer.new()
	# New's choices: era, then the era's home bases and jets, and the wingman.
	_ui.era_row = GridContainer.new()
	_ui.era_row.columns = 2
	_ui.era = OptionButton.new()
	for e in NEW_ERAS:
		_ui.era.add_item(e[0])
	_ui.era.item_selected.connect(_fill_new_choices)
	_ui.new_base = OptionButton.new()
	_ui.new_jet = OptionButton.new()
	_ui.wingman = CheckBox.new()
	_ui.wingman.text = "Wingman"
	_ui.wingman.button_pressed = true
	for row in [["Era", _ui.era], ["Home base", _ui.new_base], ["Jet", _ui.new_jet], ["", _ui.wingman]]:
		_ui.era_row.add_child(_label(row[0]))
		_ui.era_row.add_child(row[1])
	v.add_child(_ui.era_row)
	_ui.name_edit = LineEdit.new()
	_ui.name_edit.custom_minimum_size.x = 360
	_ui.name_edit.text_changed.connect(func(t): _ui.name_why.text = name_error(t))
	v.add_child(_ui.name_edit)
	_ui.name_why = _label("")
	_ui.name_why.modulate = Color.RED
	v.add_child(_ui.name_why)
	_ui.name_dlg.add_child(v)
	_ui.name_dlg.confirmed.connect(_name_confirmed)
	add_child(_ui.name_dlg)
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
	var l: ItemList = _ui.open_list
	l.clear()
	for section in ["My missions", "Original missions (read-only)"]:
		l.add_item(section)
		l.set_item_disabled(l.item_count - 1, true)
		if section == "My missions":
			for m in own_missions():
				l.add_item("    " + m.name)
				l.set_item_metadata(l.item_count - 1, m.path)
		else:
			var ids := originals.keys()
			ids.sort()
			for id in ids:
				l.add_item("    %d  %s" % [id, originals[id].title])
				l.set_item_metadata(l.item_count - 1, id)
	_ui.open_dlg.popup_centered()


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
	_ui.name_dlg.title = {"fork": "Fork: the new mission's name", "new": "New mission"}.get(purpose, "Save as")
	_ui.era_row.visible = purpose == "new"
	if purpose == "new":
		_fill_new_choices(_ui.era.selected)
	_ui.name_edit.text = suggestion
	_ui.name_why.text = name_error(suggestion)
	_ui.name_dlg.popup_centered()


## The home bases and jets of era `i` (NEW_ERAS) into New's pickers.
func _fill_new_choices(i: int) -> void:
	var e: Array = NEW_ERAS[i]
	_ui.new_base.clear()
	for b in e[2]:
		_ui.new_base.add_item(b)
	_ui.new_jet.clear()
	var bdb := Tsd.MissionRuntime.bdb_objects(Tsd.MissionRuntime.load_bdb({"bdb": "default6_1.bdb"}))
	for id in e[3]:
		_ui.new_jet.add_item(String(bdb.get(id, {}).get("0x528", str(id))))
		_ui.new_jet.set_item_metadata(_ui.new_jet.item_count - 1, id)


func _name_confirmed() -> void:
	var n: String = _ui.name_edit.text.strip_edges()
	var why := name_error(n)
	if why != "":
		_ui.name_why.text = why
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
		var era: int = _ui.era.selected
		var jet: int = _ui.new_jet.get_selected_metadata()
		new_mission(n, era, _ui.new_base.get_item_text(_ui.new_base.selected), jet, _ui.wingman.button_pressed)
	elif _name_purpose == "fork":
		fork(n)
	else:
		save_as(n)


func _on_issue_pressed(i: int) -> void:
	var id = _ui.issues.get_popup().get_item_metadata(i)
	if id != null and int(id) >= 0:
		sel_id = int(id)
		_refresh()
		if tsd.selected >= 0:
			tsd.centre_on(tsd.units[tsd.selected].pos)


func _set_mode(m: String) -> void:
	mode = "" if mode == m else m
	route_pts.clear()
	_ui.add_mode.set_pressed_no_signal(mode == "add")
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
	for i in l.get_selected_items():
		picked[l.get_item_metadata(i)] = true
	l.clear()
	for e in data.get("entities", {}).get("items", []):
		if int(e.get("0x14", 0)) != 0:
			continue
		var id := int(e.get("0x1e", -1))
		var obj: Dictionary = objects.get(int(e.get("0x2c6", -1)), {})
		var side: int = clampi(int(e.get("0x2d0", 1)), 1, 3)
		l.add_item("%d  %s  (%s, %s)" % [id, e.get("0x2bc", ""), obj.get("0x514", "?"), SIDES[side - 1]])
		l.set_item_metadata(l.item_count - 1, id)
		if picked.has(id) or id == sel_id:
			l.select(l.item_count - 1, false)


func _fill_props() -> void:
	var e := entity(sel_id)
	var can := not e.is_empty() and not read_only
	for k in ["p_name", "p_heading", "p_alt"]:
		_ui[k].editable = can
	for k in ["p_side", "p_role"]:
		_ui[k].disabled = not can
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
	_ui.p_where.text = (
		"X %d, Y %d m%s" % [int(e["0x2e4"]), int(e["0x2ee"]), "\n" + "\n".join(why) if not why.is_empty() else ""]
	)


func _fill_object_picker() -> void:
	var o: OptionButton = _ui.add_obj
	o.clear()
	var classes: Array = ADD_CLASSES[maxi(_ui.add_class.selected, 0)][1]
	var ids := objects.keys()
	ids.sort()
	for id in ids:
		var obj: Dictionary = objects[id]
		if int(obj.get("0x5aa", -1)) in classes:
			o.add_item("%s (%s)" % [obj.get("0x514", id), obj.get("0x528", obj.get("0x51e", ""))])
			o.set_item_metadata(o.item_count - 1, int(id))
	add_object = o.get_item_metadata(0) if o.item_count > 0 else -1


func _fill_flight_types() -> void:
	for row in _ui.flight_rows:
		var t: OptionButton = row.type
		t.clear()
		var ids := objects.keys()
		ids.sort()
		for id in ids:
			var obj: Dictionary = objects[id]
			if int(obj.get("0x5aa", -1)) == 0x1c and int(obj.get("0x5b4", -1)) in Tsd.FLYABLE_TYPES:
				t.add_item(String(obj.get("0x528", obj.get("0x514", ""))))
				t.set_item_metadata(t.item_count - 1, int(id))


func _fill_flights() -> void:
	if tsd == null:
		return
	for n in 4:
		var row: Dictionary = _ui.flight_rows[n]
		if tsd.flights.has(n + 1):
			var lead: Dictionary = tsd.units[tsd.flights[n + 1].leader]
			var obj := int(entity(_key_id(lead.key)).get("0x2c6", -1))
			for i in row.type.item_count:
				if row.type.get_item_metadata(i) == obj:
					row.type.select(i)
			row.count.set_value_no_signal(tsd.flights[n + 1].members.size())
	var ro: OptionButton = _ui.route_of
	ro.clear()
	var keys: Array = tsd.flights.keys()
	keys.sort()
	for n in keys:
		var fo: int = tsd.flights[n].formation
		ro.add_item("%s (%s)" % [data.formations.items[fo].get("0x3e8", ""), "blue" if n <= 4 else "other"])
		ro.set_item_metadata(ro.item_count - 1, n)
		if n == tsd.sel_flight:
			ro.select(ro.item_count - 1)
	_ui.wps.clear()
	var fo := _formation_of(tsd.sel_flight)
	var pts: Array = data.formations.items[fo].points if fo >= 0 else []
	for i in pts.size():
		_ui.wps.add_item("%d: alt %d m, %d km/h" % [i + 1, int(pts[i][3]), int(pts[i][4])])
	if sel_wp >= 0 and sel_wp < pts.size():
		_ui.wps.select(sel_wp)
		_ui.wp_alt.set_value_no_signal(float(pts[sel_wp][3]))
		_ui.wp_speed.set_value_no_signal(float(pts[sel_wp][4]))


func _fill_mission() -> void:
	_ui.m_name.text = mission_name
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
	if _ui.brief_en.text != briefing.en:
		_ui.brief_en.text = briefing.en
	if _ui.brief_he.text != briefing.he:
		_ui.brief_he.text = briefing.he
	for c in [_ui.m_hour, _ui.m_min]:
		c.editable = not read_only
	for c in [_ui.m_wind, _ui.m_from]:
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

	func _scale() -> float:
		return minf(size.x / AREA.size.x, size.y / AREA.size.y)

	func _origin() -> Vector2:
		return (size - AREA.size * _scale()) / 2 - AREA.position * _scale()

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

	func _gui_input(event: InputEvent) -> void:
		if tsd != null and event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and tsd.can_zoom_in():
				tsd.zoom_by(tsd.ZOOM_STEP)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and tsd.can_zoom_out():
				tsd.zoom_by(1.0 / tsd.ZOOM_STEP)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)

	## The route being drawn: white points joined by a line.
	func _draw_preview() -> void:
		if tsd == null:
			return
		var pts := PackedVector2Array()
		for p in editor.route_pts:
			pts.append(_to_screen(tsd.CLIENT.position + tsd._to_client(tsd.world_to_map(p.x, p.y))))
		if pts.size() > 1:
			preview.draw_polyline(pts, Color.WHITE, 2.0)
		for p in pts:
			preview.draw_circle(p, 5.0, Color.WHITE)
